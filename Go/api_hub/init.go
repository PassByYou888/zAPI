//go:build cgo
// +build cgo

// Package api_hub provides Go bindings for the API Hub dynamic library.
// It uses CGO to call the C ABI exported by z_api_hub64.dll (Windows),
// libz_api_hub.so (Linux/BSD), or libz_api_hub.dylib (macOS).
//
// Thread safety: all functions are fully thread‑safe.
// Execution order of concurrent calls is NOT guaranteed – see package docs.
package api_hub

/*
#include <stdint.h>
#include <stdlib.h>

// Callback signatures matching the C library.
typedef int (*TCallCallback)(void* trigger, void* input, void* output);
typedef int (*TNotifyCallback)(void* trigger, void* input);

// Forward declarations for the Go callback trampolines.
extern int goCallCallback(void* trigger, void* input, void* output);
extern int goNotifyCallback(void* trigger, void* input);
*/
import "C"
import (
	"fmt"
	"runtime"
	"sync"
	"syscall"
)

// ---------- Global library handle and function pointers ----------
var (
	libHandle uintptr
	funcs     struct {
		CreateDataHnd  uintptr
		FreeDataHnd    uintptr
		GetBuffer      uintptr
		WriteBuffer    uintptr
		ReadBuffer     uintptr
		GetPos         uintptr
		SetPos         uintptr
		GetSize        uintptr
		SetSize        uintptr
		PrepareClient  uintptr
		PrepareService uintptr
		ResetPrepare   uintptr
		PrepareDone    uintptr
		Call           uintptr
		Notify         uintptr
		Shutdown       uintptr
		CreateAppHnd   uintptr
		FreeAppHnd     uintptr
		RegCall        uintptr
		RegNotify      uintptr
		UnReg          uintptr // added
		LocalAppCall   uintptr
		LocalAppNotify uintptr
		ExitMainThread uintptr
		SetOption      uintptr // added
	}
	loadOnce sync.Once
	loadErr  error
)

// callFunc invokes a C function at the given address with the provided arguments.
// It supports up to 6 arguments; panics if more are needed.
func callFunc(addr uintptr, args ...uintptr) uintptr {
	if addr == 0 {
		return 0
	}
	switch len(args) {
	case 0:
		ret, _, _ := syscall.Syscall(addr, 0, 0, 0, 0)
		return uintptr(ret)
	case 1:
		ret, _, _ := syscall.Syscall(addr, 1, args[0], 0, 0)
		return uintptr(ret)
	case 2:
		ret, _, _ := syscall.Syscall(addr, 2, args[0], args[1], 0)
		return uintptr(ret)
	case 3:
		ret, _, _ := syscall.Syscall(addr, 3, args[0], args[1], args[2])
		return uintptr(ret)
	case 4:
		ret, _, _ := syscall.Syscall6(addr, 4, args[0], args[1], args[2], args[3], 0, 0)
		return uintptr(ret)
	case 5:
		ret, _, _ := syscall.Syscall6(addr, 5, args[0], args[1], args[2], args[3], args[4], 0)
		return uintptr(ret)
	case 6:
		ret, _, _ := syscall.Syscall6(addr, 6, args[0], args[1], args[2], args[3], args[4], args[5])
		return uintptr(ret)
	default:
		panic("callFunc: too many arguments")
	}
}

// getLibraryName returns the platform‑specific library filename.
func getLibraryName() string {
	switch runtime.GOOS {
	case "windows":
		return "z_api_hub64.dll"
	case "linux":
		return "z_api_hub.so"
	case "darwin":
		return "z_api_hub.dylib"
	default:
		return ""
	}
}

// loadLibrary loads the dynamic library and resolves all symbols.
// It is called once via sync.Once.
func loadLibrary() error {
	loadOnce.Do(func() {
		libName := getLibraryName()
		if libName == "" {
			loadErr = fmt.Errorf("unsupported OS: %s", runtime.GOOS)
			return
		}

		var handle uintptr
		var err error

		switch runtime.GOOS {
		case "windows":
			handle, err = loadWindows(libName)
		case "linux", "darwin":
			handle, err = loadUnix(libName)
		default:
			err = fmt.Errorf("unsupported OS: %s", runtime.GOOS)
		}

		if err != nil {
			loadErr = err
			return
		}
		libHandle = handle

		// Resolve all required functions.
		getProc := func(name string) uintptr {
			addr := getProcAddress(handle, name)
			if addr == 0 {
				loadErr = fmt.Errorf("symbol not found: %s", name)
			}
			return addr
		}

		funcs.CreateDataHnd = getProc("API_Create_DataHnd")
		funcs.FreeDataHnd = getProc("API_Free_DataHnd")
		funcs.GetBuffer = getProc("API_GetBuffer")
		funcs.WriteBuffer = getProc("API_WriteBuffer")
		funcs.ReadBuffer = getProc("API_ReadBuffer")
		funcs.GetPos = getProc("API_GetPos")
		funcs.SetPos = getProc("API_SetPos")
		funcs.GetSize = getProc("API_GetSize")
		funcs.SetSize = getProc("API_SetSize")
		funcs.PrepareClient = getProc("API_Prepare_Client")
		funcs.PrepareService = getProc("API_Prepare_Service")
		funcs.ResetPrepare = getProc("API_Reset_Prepare")
		funcs.PrepareDone = getProc("API_Prepare_Done")
		funcs.Call = getProc("API_Call")
		funcs.Notify = getProc("API_Notify")
		funcs.Shutdown = getProc("API_shutdown")
		funcs.CreateAppHnd = getProc("API_Create_APPHnd")
		funcs.FreeAppHnd = getProc("API_Free_APPHnd")
		funcs.RegCall = getProc("API_Reg_Call")
		funcs.RegNotify = getProc("API_Reg_Notify")
		funcs.UnReg = getProc("API_UnReg") // new
		funcs.LocalAppCall = getProc("API_Local_APP_Call")
		funcs.LocalAppNotify = getProc("API_Local_APP_Notify")
		funcs.ExitMainThread = getProc("API_Exit_MainThread")
		funcs.SetOption = getProc("API_SetOption") // new

		if loadErr != nil {
			unloadLibrary(handle)
			libHandle = 0
		}
	})
	return loadErr
}

// Platform‑specific loading helpers.
func loadWindows(name string) (uintptr, error) {
	ptr, err := syscall.LoadLibrary(name)
	return uintptr(ptr), err
}

func loadUnix(name string) (uintptr, error) {
	handle, err := syscall.LoadLibrary(name) // dlopen
	return uintptr(handle), err
}

func getProcAddress(handle uintptr, name string) uintptr {
	addr, err := syscall.GetProcAddress(syscall.Handle(handle), name)
	if err != nil {
		return 0
	}
	return uintptr(addr)
}

func unloadLibrary(handle uintptr) {
	syscall.FreeLibrary(syscall.Handle(handle))
}

// init automatically loads the library; errors are deferred until use.
func init() {
	_ = loadLibrary()
}
