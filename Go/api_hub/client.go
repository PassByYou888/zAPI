//go:build cgo
// +build cgo

package api_hub

import (
	"encoding/binary"
	"errors"
	"syscall"
	"unsafe"
)

// DataHnd is an opaque handle to a data buffer containing an API name and payload.
// It must be freed with FreeDataHnd. The underlying C handle is never nil,
// but its size may be 0 to indicate failure or timeout.
type DataHnd uintptr

// AppHnd is an opaque handle to an application context.
type AppHnd uintptr

// ---------- Core Data Handle Functions ----------

// CreateDataHnd creates a new data handle with the given API name.
// The handle’s internal buffer is initially empty (size = 0).
// The caller must free it with FreeDataHnd.
// Thread‑safe.
func CreateDataHnd(apiName string) (DataHnd, error) {
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	cName := syscall.StringBytePtr(apiName)
	ret := callFunc(funcs.CreateDataHnd, uintptr(unsafe.Pointer(cName))) //nolint:unsafeptr
	if ret == 0 {
		return 0, errors.New("CreateDataHnd failed")
	}
	return DataHnd(ret), nil
}

// FreeDataHnd destroys a data handle and releases its memory.
// Does nothing if h is 0.
// Thread‑safe (but the handle must not be used concurrently after freeing).
func FreeDataHnd(h DataHnd) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.FreeDataHnd, uintptr(h))
}

// GetBuffer returns a direct pointer to the raw binary data held in the handle.
// The pointer is valid until the handle is freed or the buffer is resized.
// The caller must not free this pointer.
// Use GetSize to know the buffer length.
// Thread‑safe for read‑only access; do not write beyond the allocated size.
func GetBuffer(h DataHnd) unsafe.Pointer {
	if h == 0 {
		return nil
	}
	if err := loadLibrary(); err != nil {
		return nil
	}
	ret := callFunc(funcs.GetBuffer, uintptr(h))
	return unsafe.Pointer(ret)
}

// WriteBuffer writes binary data into the handle at the current position.
// The buffer is automatically enlarged if needed. Returns the number of bytes written.
// For a given handle, write operations should be serialised across threads.
// Thread‑safe for different handles.
func WriteBuffer(h DataHnd, data []byte) (int64, error) {
	if h == 0 {
		return 0, errors.New("invalid handle")
	}
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	var ptr uintptr
	if len(data) > 0 {
		ptr = uintptr(unsafe.Pointer(&data[0]))
	}
	ret := callFunc(funcs.WriteBuffer, uintptr(h), ptr, uintptr(len(data)))
	return int64(ret), nil
}

// ReadBuffer reads data from the handle into the provided buffer, starting at the current position.
// Returns the number of bytes actually read (may be less than len(buf) if EOF).
// Read operations are safe concurrently with other reads, but not with writes.
func ReadBuffer(h DataHnd, buf []byte) (int64, error) {
	if h == 0 {
		return 0, errors.New("invalid handle")
	}
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	var ptr uintptr
	if len(buf) > 0 {
		ptr = uintptr(unsafe.Pointer(&buf[0]))
	}
	ret := callFunc(funcs.ReadBuffer, uintptr(h), ptr, uintptr(len(buf)))
	return int64(ret), nil
}

// GetPos returns the current read/write position within the handle.
// Thread‑safe for read‑only access.
func GetPos(h DataHnd) int64 {
	if h == 0 {
		return 0
	}
	if err := loadLibrary(); err != nil {
		return 0
	}
	ret := callFunc(funcs.GetPos, uintptr(h))
	return int64(ret)
}

// SetPos sets the current read/write position within the handle.
// If the new position exceeds the current size, the buffer is extended with zeros.
// Thread‑safety: should be serialised on the same handle.
func SetPos(h DataHnd, pos int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetPos, uintptr(h), uintptr(pos))
}

// GetSize returns the total size (in bytes) of the data stored in the handle.
// Thread‑safe for read‑only access.
func GetSize(h DataHnd) int64 {
	if h == 0 {
		return 0
	}
	if err := loadLibrary(); err != nil {
		return 0
	}
	ret := callFunc(funcs.GetSize, uintptr(h))
	return int64(ret)
}

// SetSize resizes the internal buffer of the data handle.
// If the new size is larger, the added space is uninitialised. If smaller,
// data beyond the new size is discarded.
// Thread‑safe: should be serialised on the same handle.
func SetSize(h DataHnd, size int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetSize, uintptr(h), uintptr(size))
}

// ---------- Network Preparation ----------

// ResetPrepare clears all previously prepared services and clients.
// Call before preparing a new set.
// Thread‑safe.
func ResetPrepare() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.ResetPrepare)
}

// PrepareClient adds a client connection to the preparation list.
// The client will connect to the given address when PrepareDone is called.
// If you want to expose an application, use Server.Start instead.
// Thread‑safe.
func PrepareClient(addr string) error {
	if err := loadLibrary(); err != nil {
		return err
	}
	cAddr := syscall.StringBytePtr(addr)
	ret := callFunc(funcs.PrepareClient, uintptr(unsafe.Pointer(cAddr)), 0)
	if ret == 0 {
		return errors.New("PrepareClient failed")
	}
	return nil
}

// PrepareService adds a service listener to the preparation list.
// The service will listen on the given address (e.g., "0.0.0.0:9898" or "ipc:my_service").
// Use the same address for both listening and publishing (or separate).
// Thread‑safe.
func PrepareService(addr string) error {
	if err := loadLibrary(); err != nil {
		return err
	}
	cAddr := syscall.StringBytePtr(addr)
	ret := callFunc(funcs.PrepareService, uintptr(unsafe.Pointer(cAddr)), uintptr(unsafe.Pointer(cAddr)))
	if ret == 0 {
		return errors.New("PrepareService failed")
	}
	return nil
}

// PrepareDone starts the network framework with all prepared services and clients.
// It blocks until the framework is ready. Returns true on success.
// Must be called only once per preparation session.
// Thread‑safe (but should be called from the main thread for status logging).
func PrepareDone() (bool, error) {
	if err := loadLibrary(); err != nil {
		return false, err
	}
	ret := callFunc(funcs.PrepareDone)
	return ret == 1, nil
}

// ---------- Remote Calls and Notifications ----------

// Call invokes a remote (or local) API synchronously.
// appName: target application name (case‑sensitive).
// param: input data handle (the library clones it; caller still must free param).
// timeoutMs: maximum wait in milliseconds (0 means infinite).
// Returns a new DataHnd that the caller MUST free with FreeDataHnd, even if its size is 0.
// The handle is never nil; a size of 0 indicates a timeout or failure.
// Thread‑safe. Concurrent calls are load‑balanced and may execute out‑of‑order.
func Call(appName string, param DataHnd, timeoutMs uint32) (DataHnd, error) {
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	cApp := syscall.StringBytePtr(appName)
	ret := callFunc(funcs.Call, uintptr(unsafe.Pointer(cApp)), uintptr(param), uintptr(timeoutMs))
	if ret == 0 {
		return 0, errors.New("API_Call returned a null handle (should not happen)")
	}
	return DataHnd(ret), nil
}

// Notify sends a one‑way notification to the target application.
// Delivery is best‑effort and out‑of‑order.
// The param handle is cloned internally; caller must still free it.
// Thread‑safe.
func Notify(appName string, param DataHnd) {
	if param == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	cApp := syscall.StringBytePtr(appName)
	callFunc(funcs.Notify, uintptr(unsafe.Pointer(cApp)), uintptr(param))
}

// ---------- Runtime Options ----------

// SetOption dynamically adjusts global runtime options of the API Hub framework.
// All changes take effect immediately for subsequent operations (except where noted).
// Unknown options are silently ignored.
//
// Supported Option keys (case‑insensitive, aliases accepted):
//   - "password" / "passwd" : Sets the C4 P2PVM authentication token.
//     Must match on both service and client sides for successful handshake.
//   - "Quiet" : Enable/disable quiet mode (True/False). Suppresses debug logs.
//   - "External_Conf_Auto_Save" / "Conf_Auto_Save" : Auto‑save .ini on exit (True/False).
//   - "Wait_Connection_ReadyOk" / "Wait_API_Prepare_Done" / ... :
//     Controls whether PrepareDone blocks until all clients are connected.
//     When False, clients auto‑connect later (important for deployment).
//   - "Wait_Connection_Timeout" / "Wait_TimeOut" : Max wait (ms) when the above is True.
//   - "ShowThreadID" / "ShowThread" / "Show_Thread" : Show thread IDs in logs.
//   - "ConsoleOutput" / "Console_Output" : Enable/disable console logging.
//   - "IPC_Serv_ThreadCount" / "IPC_ThreadCount" / "IPC_Server_ThreadCount" :
//     Number of threads in the IPC service thread pool.
//   - "IPC_Serv_MaxQueueLength" / "IPC_MaxQueueLength" / "IPC_Server_MaxQueueLength" :
//     Max IPC queue length.
//   - "IPC_Serv_MaxMsgSize" / "IPC_MaxMsgSize" / "IPC_Server_MaxMsgSize" :
//     Max IPC message size (bytes).
//
// For boolean options, accepted values: "True"/"False", "1"/"0", "Yes"/"No".
//
// Thread‑safe. This function has no return value.
//
// Example:
//
//	SetOption("password", "my_secret_token")
//	SetOption("Wait_Connection_ReadyOk", "False")
func SetOption(option, value string) {
	if err := loadLibrary(); err != nil {
		return
	}
	cOpt := syscall.StringBytePtr(option)
	cVal := syscall.StringBytePtr(value)
	callFunc(funcs.SetOption, uintptr(unsafe.Pointer(cOpt)), uintptr(unsafe.Pointer(cVal)))
}

// ---------- Shutdown ----------

// Shutdown gracefully shuts down the entire API Hub framework.
// It releases all resources and stops services. After this, you can re‑initialise.
// Thread‑safe, but typically called from the main thread.
func Shutdown() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.Shutdown)
}

// ---------- Client Wrapper for Convenience ----------

// Client is a lightweight wrapper providing all client‑side functions.
type Client struct{}

// NewClient creates a new Client instance (loads the library).
// Thread‑safe.
func NewClient() (*Client, error) {
	if err := loadLibrary(); err != nil {
		return nil, err
	}
	return &Client{}, nil
}

// Close is a no‑op; resources are freed via Shutdown.
func (c *Client) Close() {}

// All client methods simply forward to the package functions.
func (c *Client) CreateDataHnd(apiName string) (DataHnd, error) { return CreateDataHnd(apiName) }
func (c *Client) FreeDataHnd(h DataHnd)                         { FreeDataHnd(h) }
func (c *Client) GetBuffer(h DataHnd) unsafe.Pointer            { return GetBuffer(h) }
func (c *Client) WriteBuffer(h DataHnd, data []byte) (int64, error) {
	return WriteBuffer(h, data)
}
func (c *Client) ReadBuffer(h DataHnd, buf []byte) (int64, error) { return ReadBuffer(h, buf) }
func (c *Client) GetPos(h DataHnd) int64                          { return GetPos(h) }
func (c *Client) SetPos(h DataHnd, pos int64)                     { SetPos(h, pos) }
func (c *Client) GetSize(h DataHnd) int64                         { return GetSize(h) }
func (c *Client) SetSize(h DataHnd, size int64)                   { SetSize(h, size) }
func (c *Client) ResetPrepare()                                   { ResetPrepare() }
func (c *Client) PrepareClient(addr string) error                 { return PrepareClient(addr) }
func (c *Client) PrepareService(addr string) error                { return PrepareService(addr) }
func (c *Client) PrepareDone() (bool, error)                      { return PrepareDone() }
func (c *Client) Call(appName string, param DataHnd, timeoutMs uint32) (DataHnd, error) {
	return Call(appName, param, timeoutMs)
}
func (c *Client) Notify(appName string, param DataHnd) { Notify(appName, param) }
func (c *Client) SetOption(option, value string)       { SetOption(option, value) }
func (c *Client) Shutdown()                            { Shutdown() }

// ---------- Convenience Serialisation Helpers ----------
// All helpers use little‑endian encoding for integers.
// They are thread‑safe if the handle is not concurrently written.

// WriteInt32 writes a 32‑bit integer.
func WriteInt32(h DataHnd, v int32) error {
	buf := make([]byte, 4)
	binary.LittleEndian.PutUint32(buf, uint32(v))
	_, err := WriteBuffer(h, buf)
	return err
}

// ReadInt32 reads a 32‑bit integer.
func ReadInt32(h DataHnd) (int32, error) {
	buf := make([]byte, 4)
	_, err := ReadBuffer(h, buf)
	if err != nil {
		return 0, err
	}
	return int32(binary.LittleEndian.Uint32(buf)), nil
}

// WriteString writes a length‑prefixed string (int32 length + UTF‑8 bytes).
func WriteString(h DataHnd, s string) error {
	data := []byte(s)
	if err := WriteInt32(h, int32(len(data))); err != nil {
		return err
	}
	if len(data) > 0 {
		_, err := WriteBuffer(h, data)
		return err
	}
	return nil
}

// ReadString reads a length‑prefixed string.
func ReadString(h DataHnd) (string, error) {
	length, err := ReadInt32(h)
	if err != nil {
		return "", err
	}
	if length == 0 {
		return "", nil
	}
	buf := make([]byte, length)
	_, err = ReadBuffer(h, buf)
	if err != nil {
		return "", err
	}
	return string(buf), nil
}

// WriteBool writes a single byte (1 for true, 0 for false).
func WriteBool(h DataHnd, v bool) error {
	b := byte(0)
	if v {
		b = 1
	}
	_, err := WriteBuffer(h, []byte{b})
	return err
}

// ReadBool reads a boolean byte.
func ReadBool(h DataHnd) (bool, error) {
	buf := make([]byte, 1)
	_, err := ReadBuffer(h, buf)
	if err != nil {
		return false, err
	}
	return buf[0] != 0, nil
}

// WriteBytes writes a length‑prefixed byte slice.
func WriteBytes(h DataHnd, data []byte) error {
	if err := WriteInt32(h, int32(len(data))); err != nil {
		return err
	}
	if len(data) > 0 {
		_, err := WriteBuffer(h, data)
		return err
	}
	return nil
}

// ReadBytes reads a length‑prefixed byte slice.
func ReadBytes(h DataHnd) ([]byte, error) {
	length, err := ReadInt32(h)
	if err != nil {
		return nil, err
	}
	if length == 0 {
		return []byte{}, nil
	}
	buf := make([]byte, length)
	_, err = ReadBuffer(h, buf)
	if err != nil {
		return nil, err
	}
	return buf, nil
}

// Client convenience methods.
func (c *Client) WriteInt32(h DataHnd, v int32) error     { return WriteInt32(h, v) }
func (c *Client) ReadInt32(h DataHnd) (int32, error)      { return ReadInt32(h) }
func (c *Client) WriteString(h DataHnd, s string) error   { return WriteString(h, s) }
func (c *Client) ReadString(h DataHnd) (string, error)    { return ReadString(h) }
func (c *Client) WriteBool(h DataHnd, v bool) error       { return WriteBool(h, v) }
func (c *Client) ReadBool(h DataHnd) (bool, error)        { return ReadBool(h) }
func (c *Client) WriteBytes(h DataHnd, data []byte) error { return WriteBytes(h, data) }
func (c *Client) ReadBytes(h DataHnd) ([]byte, error)     { return ReadBytes(h) }
