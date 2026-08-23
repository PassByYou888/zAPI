//go:build cgo
// +build cgo

package api_hub

import "syscall"

// callFunc 调用一个函数指针，传入参数，返回结果。
// 它使用 syscall.SyscallN（Go 1.17+ 支持所有平台）。
func callFunc(addr uintptr, args ...uintptr) uintptr {
	if addr == 0 {
		return 0
	}
	ret, _, _ := syscall.SyscallN(addr, args...)
	return ret
}
