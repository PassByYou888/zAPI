//go:build cgo
// +build cgo

package api_hub

import "syscall"

// callFunc calls a function pointer with the given arguments.
// It uses syscall.SyscallN, which works on all platforms (Go 1.17+).
func callFunc(addr uintptr, args ...uintptr) uintptr {
	if addr == 0 {
		return 0
	}
	ret, _, _ := syscall.SyscallN(addr, args...)
	return ret
}
