//go:build cgo
// +build cgo

package api_hub

/*
#include <stdlib.h>

typedef void (*TCallCallback)(void* trigger, void* input, void* output);
typedef void (*TNotifyCallback)(void* trigger, void* input);

extern void goCallCallback(void* trigger, void* input, void* output);
extern void goNotifyCallback(void* trigger, void* input);
*/
import "C"
import (
	"errors"
	"fmt"
	"sync"
	"unsafe"
)

// Server represents an application that exposes APIs.
type Server struct {
	app       uintptr
	name      string
	callIDs   []uintptr
	notifyIDs []uintptr
	loaded    bool
	mu        sync.Mutex // protects callIDs, notifyIDs
}

var (
	callMu    sync.Mutex
	callMap   = make(map[uintptr]func(DataHnd, DataHnd))
	notifyMu  sync.Mutex
	notifyMap = make(map[uintptr]func(DataHnd))
	idMu      sync.Mutex
	nextID    uintptr = 1
)

func NewServer(name, desc string) (*Server, error) {
	if err := loadLibrary(); err != nil {
		return nil, fmt.Errorf("Init failed: %w", err)
	}
	cName := C.CString(name)
	cDesc := C.CString(desc)
	defer C.free(unsafe.Pointer(cName))
	defer C.free(unsafe.Pointer(cDesc))
	ret := callFunc(funcs.CreateAppHnd, uintptr(unsafe.Pointer(cName)), uintptr(unsafe.Pointer(cDesc)))
	if ret == 0 {
		return nil, errors.New("API_Create_APPHnd failed")
	}
	return &Server{app: ret, name: name, loaded: true}, nil
}

func (s *Server) RegisterCall(apiName, desc string, fn func(DataHnd, DataHnd)) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := C.CString(apiName)
	cDesc := C.CString(desc)
	defer C.free(unsafe.Pointer(cName))
	defer C.free(unsafe.Pointer(cDesc))

	idMu.Lock()
	id := nextID
	nextID++
	idMu.Unlock()

	callMu.Lock()
	callMap[id] = fn
	callMu.Unlock()

	s.mu.Lock()
	s.callIDs = append(s.callIDs, id)
	s.mu.Unlock()

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
		s.mu.Lock()
		// remove id from slice (simple but O(n) – okay for small sets)
		for i, v := range s.callIDs {
			if v == id {
				s.callIDs = append(s.callIDs[:i], s.callIDs[i+1:]...)
				break
			}
		}
		s.mu.Unlock()
		return fmt.Errorf("register call '%s' failed", apiName)
	}
	return nil
}

func (s *Server) RegisterNotify(apiName, desc string, fn func(DataHnd)) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := C.CString(apiName)
	cDesc := C.CString(desc)
	defer C.free(unsafe.Pointer(cName))
	defer C.free(unsafe.Pointer(cDesc))

	idMu.Lock()
	id := nextID
	nextID++
	idMu.Unlock()

	notifyMu.Lock()
	notifyMap[id] = fn
	notifyMu.Unlock()

	s.mu.Lock()
	s.notifyIDs = append(s.notifyIDs, id)
	s.mu.Unlock()

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
		s.mu.Lock()
		for i, v := range s.notifyIDs {
			if v == id {
				s.notifyIDs = append(s.notifyIDs[:i], s.notifyIDs[i+1:]...)
				break
			}
		}
		s.mu.Unlock()
		return fmt.Errorf("register notify '%s' failed", apiName)
	}
	return nil
}

func (s *Server) Unregister(apiName string) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cName := C.CString(apiName)
	defer C.free(unsafe.Pointer(cName))
	ret := callFunc(funcs.UnReg, s.app, uintptr(unsafe.Pointer(cName)))
	if ret == 0 {
		return fmt.Errorf("API '%s' not found", apiName)
	}
	return nil
}

func (s *Server) Start(addr string) error {
	if !s.loaded {
		return errors.New("server closed")
	}
	cAddr := C.CString(addr)
	defer C.free(unsafe.Pointer(cAddr))
	callFunc(funcs.ResetPrepare)
	callFunc(funcs.PrepareService, uintptr(unsafe.Pointer(cAddr)), uintptr(unsafe.Pointer(cAddr)))
	callFunc(funcs.PrepareClient, uintptr(unsafe.Pointer(cAddr)), s.app)
	ret := callFunc(funcs.PrepareDone)
	if ret != 1 {
		// 清理：释放应用句柄
		callFunc(funcs.FreeAppHnd, s.app)
		s.loaded = false
		return errors.New("Prepare_Done failed")
	}
	return nil
}

func (s *Server) Stop() {
	if !s.loaded {
		return
	}
	callFunc(funcs.ExitMainThread)
	callFunc(funcs.Shutdown)
	callFunc(funcs.FreeAppHnd, s.app)
	s.loaded = false

	s.mu.Lock()
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
	s.callIDs = nil
	s.notifyIDs = nil
	s.mu.Unlock()
}

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

func (s *Server) LocalNotify(param DataHnd) {
	if !s.loaded || s.app == 0 || param == 0 {
		return
	}
	callFunc(funcs.LocalAppNotify, s.app, uintptr(param))
}

// ---------- CGO Trampolines (void return) ----------
//
//export goCallCallback
func goCallCallback(trigger unsafe.Pointer, input unsafe.Pointer, output unsafe.Pointer) {
	id := uintptr(trigger)
	callMu.Lock()
	fn, ok := callMap[id]
	callMu.Unlock()
	if !ok {
		return
	}
	fn(DataHnd(uintptr(input)), DataHnd(uintptr(output)))
}

//export goNotifyCallback
func goNotifyCallback(trigger unsafe.Pointer, input unsafe.Pointer) {
	id := uintptr(trigger)
	notifyMu.Lock()
	fn, ok := notifyMap[id]
	notifyMu.Unlock()
	if !ok {
		return
	}
	fn(DataHnd(uintptr(input)))
}
