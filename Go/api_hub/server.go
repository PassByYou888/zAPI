//go:build cgo
// +build cgo

package api_hub

/*
#include <stdlib.h>

// Callback types matching the C ABI.
typedef int (*TCallCallback)(void* trigger, void* input, void* output);
typedef int (*TNotifyCallback)(void* trigger, void* input);

// Trampolines defined in Go.
extern int goCallCallback(void* trigger, void* input, void* output);
extern int goNotifyCallback(void* trigger, void* input);
*/
import "C"
import (
	"errors"
	"fmt"
	"sync"
	"syscall"
	"unsafe"
)

// Server represents an application that exposes APIs to the network.
// It manages an application handle and a set of registered callbacks.
//
// ⚠️ CRITICAL: Callbacks (registered with RegisterCall/RegisterNotify)
// are executed in background threads from the library's internal thread pool.
// Therefore:
//   - Do NOT perform long‑blocking operations inside callbacks.
//   - Do NOT call API_Call, API_Notify, or any other blocking API from
//     within a callback – this may cause deadlocks.
//   - Offload heavy work to separate goroutines or queues.
//   - Access shared data with proper synchronisation.
type Server struct {
	app       uintptr
	name      string
	callIDs   []uintptr
	notifyIDs []uintptr
	loaded    bool
}

// Internal maps to store Go callbacks, keyed by a unique trigger ID.
var (
	callMu    sync.Mutex
	callMap   = make(map[uintptr]func(DataHnd, DataHnd))
	notifyMu  sync.Mutex
	notifyMap         = make(map[uintptr]func(DataHnd))
	nextID    uintptr = 1
)

// NewServer creates a new application with the given name and description.
// The name must be unique within the network.
// Thread‑safe.
func NewServer(name, desc string) (*Server, error) {
	if err := loadLibrary(); err != nil {
		return nil, fmt.Errorf("Init failed: %w", err)
	}
	cName := syscall.StringBytePtr(name)
	cDesc := syscall.StringBytePtr(desc)
	ret := callFunc(funcs.CreateAppHnd, uintptr(unsafe.Pointer(cName)), uintptr(unsafe.Pointer(cDesc))) //nolint:unsafeptr
	if ret == 0 {
		return nil, errors.New("API_Create_APPHnd failed")
	}
	return &Server{
		app:    ret,
		name:   name,
		loaded: true,
	}, nil
}

// RegisterCall registers a request‑response API.
// apiName: unique within this application (case‑sensitive).
// fn: called with input (read‑only) and output (write‑only) handles.
// Returns an error if the API name is already registered.
// Thread‑safe.
//
// ⚠️ WARNING: The callback fn runs in a background thread (C thread pool).
// Do NOT call API_Call, API_Notify, or block inside fn.
func (s *Server) RegisterCall(apiName, desc string, fn func(DataHnd, DataHnd)) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := syscall.StringBytePtr(apiName)
	cDesc := syscall.StringBytePtr(desc)

	callMu.Lock()
	id := nextID
	nextID++
	callMap[id] = fn
	callMu.Unlock()
	s.callIDs = append(s.callIDs, id)

	trigger := unsafe.Pointer(uintptr(id))
	ret := callFunc(funcs.RegCall,
		s.app,
		uintptr(unsafe.Pointer(cName)),
		uintptr(unsafe.Pointer(cDesc)),
		uintptr(trigger),
		uintptr(C.goCallCallback),
	)
	if ret == 0 {
		callMu.Lock()
		delete(callMap, id)
		callMu.Unlock()
		return fmt.Errorf("register call '%s' failed", apiName)
	}
	return nil
}

// RegisterNotify registers a one‑way notification API.
// Similar to RegisterCall but no output is produced.
// Thread‑safe.
func (s *Server) RegisterNotify(apiName, desc string, fn func(DataHnd)) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := syscall.StringBytePtr(apiName)
	cDesc := syscall.StringBytePtr(desc)

	notifyMu.Lock()
	id := nextID
	nextID++
	notifyMap[id] = fn
	notifyMu.Unlock()
	s.notifyIDs = append(s.notifyIDs, id)

	trigger := unsafe.Pointer(uintptr(id))
	ret := callFunc(funcs.RegNotify,
		s.app,
		uintptr(unsafe.Pointer(cName)),
		uintptr(unsafe.Pointer(cDesc)),
		uintptr(trigger),
		uintptr(C.goNotifyCallback),
	)
	if ret == 0 {
		notifyMu.Lock()
		delete(notifyMap, id)
		notifyMu.Unlock()
		return fmt.Errorf("register notify '%s' failed", apiName)
	}
	return nil
}

// Unregister removes a previously registered API from this application.
//
// The API is **immediately** removed from the local registry and a network
// broadcast is triggered. Remote peers will stop seeing this API within
// approximately 3 seconds (depending on network latency and the C4 update
// interval). During that short window, remote calls may still be attempted;
// they will fail gracefully (the remote side receives a "not found" error).
//
// Use this function to dynamically unload plugins, temporarily disable
// services, or adjust exposed functionality at runtime without restarting
// the application.
//
// Returns nil if the API was found and unregistered, or an error if the
// API name does not exist or the server is closed.
// Thread‑safe.
func (s *Server) Unregister(apiName string) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := syscall.StringBytePtr(apiName)
	ret := callFunc(funcs.UnReg, s.app, uintptr(unsafe.Pointer(cName)))
	if ret == 0 {
		return fmt.Errorf("API '%s' not found", apiName)
	}
	// Remove from internal maps (optional, but prevents accidental reuse)
	// The library has already removed it, but we can clean up our side.
	// Since we don't have a reverse map from name to ID, we skip this.
	// The callback will not be called after unregistration anyway.
	return nil
}

// Start prepares and launches the service.
// addr: listening/publishing address, e.g., "0.0.0.0:9898" or "ipc:my_service".
// This will automatically prepare a service and a client (to register the app).
// Blocks until the network is ready.
// Thread‑safe (but should be called once).
func (s *Server) Start(addr string) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cAddr := syscall.StringBytePtr(addr)
	callFunc(funcs.ResetPrepare)
	callFunc(funcs.PrepareService, uintptr(unsafe.Pointer(cAddr)), uintptr(unsafe.Pointer(cAddr)))
	callFunc(funcs.PrepareClient, uintptr(unsafe.Pointer(cAddr)), s.app)
	ret := callFunc(funcs.PrepareDone)
	if ret != 1 {
		return errors.New("Prepare_Done failed")
	}
	return nil
}

// Stop terminates the service and releases resources.
// It calls ExitMainThread and Shutdown internally.
// After Stop, the Server cannot be reused.
// Thread‑safe.
func (s *Server) Stop() {
	if !s.loaded {
		return
	}
	callFunc(funcs.ExitMainThread)
	callFunc(funcs.Shutdown)
	callFunc(funcs.FreeAppHnd, s.app)
	s.loaded = false

	callMu.Lock()
	for _, id := range s.callIDs {
		delete(callMap, id)
	}
	callMu.Unlock()
	notifyMu.Lock()
	for _, id := range s.notifyIDs {
		delete(notifyMap, id)
	}
	notifyMu.Unlock()
}

// LocalCall synchronously invokes a registered Call API locally (bypassing the network).
// Returns a new DataHnd that must be freed by the caller.
// Thread‑safe.
func (s *Server) LocalCall(param DataHnd) DataHnd {
	if !s.loaded || s.app == 0 {
		return 0
	}
	ret := callFunc(funcs.LocalAppCall, s.app, uintptr(param))
	if ret == 0 {
		return 0
	}
	return DataHnd(ret)
}

// LocalNotify sends a notification locally within the same application.
// No result is produced. Thread‑safe.
func (s *Server) LocalNotify(param DataHnd) {
	if !s.loaded || s.app == 0 || param == 0 {
		return
	}
	callFunc(funcs.LocalAppNotify, s.app, uintptr(param))
}

// ---------- CGO Trampolines ----------
// These functions are called from the C library’s thread pool.
// They look up the Go callback by trigger ID and invoke it.

//export goCallCallback
func goCallCallback(trigger unsafe.Pointer, input unsafe.Pointer, output unsafe.Pointer) C.int {
	id := uintptr(trigger)
	callMu.Lock()
	fn, ok := callMap[id]
	callMu.Unlock()
	if !ok {
		return 0
	}
	fn(DataHnd(uintptr(input)), DataHnd(uintptr(output)))
	return 1
}

//export goNotifyCallback
func goNotifyCallback(trigger unsafe.Pointer, input unsafe.Pointer) C.int {
	id := uintptr(trigger)
	notifyMu.Lock()
	fn, ok := notifyMap[id]
	notifyMu.Unlock()
	if !ok {
		return 0
	}
	fn(DataHnd(uintptr(input)))
	return 1
}
