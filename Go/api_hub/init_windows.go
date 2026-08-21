//go:build windows && cgo
// +build windows,cgo

package api_hub

import (
	"fmt"
	"sync"
	"syscall"
)

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
		UnReg          uintptr
		LocalAppCall   uintptr
		LocalAppNotify uintptr
		ExitMainThread uintptr
		SetOption      uintptr
	}
	loadOnce sync.Once
	loadErr  error
)

func getLibraryName() string {
	return "z_api_hub64.dll"
}

func loadLibrary() error {
	loadOnce.Do(func() {
		libName := getLibraryName()
		handle, err := syscall.LoadLibrary(libName)
		if err != nil {
			loadErr = fmt.Errorf("failed to load %s: %w", libName, err)
			return
		}
		libHandle = uintptr(handle)

		getProc := func(name string) uintptr {
			addr, err := syscall.GetProcAddress(syscall.Handle(handle), name)
			if err != nil {
				loadErr = fmt.Errorf("symbol not found: %s", name)
				return 0
			}
			return uintptr(addr)
		}

		// 解析 25 个导出函数
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
		funcs.UnReg = getProc("API_UnReg")
		funcs.LocalAppCall = getProc("API_Local_APP_Call")
		funcs.LocalAppNotify = getProc("API_Local_APP_Notify")
		funcs.ExitMainThread = getProc("API_Exit_MainThread")
		funcs.SetOption = getProc("API_SetOption")

		if loadErr != nil {
			syscall.FreeLibrary(syscall.Handle(handle))
			libHandle = 0
		}
	})
	return loadErr
}

func init() { _ = loadLibrary() }
