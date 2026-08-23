//go:build cgo
// +build cgo

package api_hub

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/binary"
	"errors"
	"math"
	"unsafe"
)

// cgoGoString converts a C string (null-terminated) to a Go string.
// This avoids calling C.GoString to work around LSP false positives.
func cgoGoString(s *C.char) string {
	if s == nil {
		return ""
	}
	var buf []byte
	for p := s; *p != 0; p = (*C.char)(unsafe.Pointer(uintptr(unsafe.Pointer(p)) + 1)) {
		buf = append(buf, byte(*p))
	}
	return string(buf)
}

// DataHnd 是不透明的数据句柄，表示一个二进制缓冲区。
// 它存储了 API 名称和载荷数据，必须通过 CreateDataHnd 创建，
// 并通过 FreeDataHnd 释放。
type DataHnd uintptr

// AppHnd 是不透明的应用句柄，表示一个逻辑应用。
// 应用可注册多个 API，在网络中具有唯一名称。
// 由 Server 结构体封装，通常不直接操作。
type AppHnd uintptr

// ---------- 基础函数 ----------

// CreateDataHnd 创建一个新的数据句柄，并关联指定的 API 名称。
// 参数 apiName 必须是 UTF‑8 编码的字符串，内部会复制一份。
// 返回的句柄在使用完毕后必须调用 FreeDataHnd 释放。
func CreateDataHnd(apiName string) (DataHnd, error) {
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	cName := C.CString(apiName)
	defer C.free(unsafe.Pointer(cName))
	ret := callFunc(funcs.CreateDataHnd, uintptr(unsafe.Pointer(cName)))
	if ret == 0 {
		return 0, errors.New("CreateDataHnd failed")
	}
	return DataHnd(ret), nil
}

// FreeDataHnd 销毁数据句柄，释放内部缓冲区。
// 传入 0 或无效句柄时无操作。
func FreeDataHnd(h DataHnd) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.FreeDataHnd, uintptr(h))
}

// GetBuffer 返回内部缓冲区的直接指针（只读）。
// 该指针在句柄释放或调整大小前有效，调用者不得释放它。
// 常用于零拷贝读取。
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

// WriteBuffer 将数据追加到句柄的缓冲区，从当前读写位置开始。
// 缓冲区自动扩容，位置后移。返回实际写入的字节数或错误。
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
	if int64(ret) < 0 {
		return 0, errors.New("WriteBuffer failed")
	}
	return int64(ret), nil
}

// ReadBuffer 从当前位置读取数据到提供的缓冲区。
// 返回实际读取的字节数，可能小于 len(buf)。
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
	if int64(ret) < 0 {
		return 0, errors.New("ReadBuffer failed")
	}
	return int64(ret), nil
}

// GetPos 返回当前读写位置（字节偏移，从 0 开始）。
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

// SetPos 设置当前读写位置。如果 pos 超出缓冲区大小，缓冲区会扩展并填充零。
func SetPos(h DataHnd, pos int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetPos, uintptr(h), uintptr(pos))
}

// GetSize 返回缓冲区总大小（字节）。
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

// SetSize 调整缓冲区大小。若新 size 大于当前，未初始化部分填充零；若小于，截断数据。
func SetSize(h DataHnd, size int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetSize, uintptr(h), uintptr(size))
}

// ---------- 原子写入（Go 层封装） ----------

// WriteInt8 写入有符号 8 位整数（小端序）。
func WriteInt8(h DataHnd, v int8) error {
	_, err := WriteBuffer(h, []byte{byte(v)})
	return err
}

// WriteUInt8 写入无符号 8 位整数。
func WriteUInt8(h DataHnd, v uint8) error {
	_, err := WriteBuffer(h, []byte{v})
	return err
}

// WriteInt16 写入有符号 16 位整数（小端序）。
func WriteInt16(h DataHnd, v int16) error {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, uint16(v))
	_, err := WriteBuffer(h, b)
	return err
}

// WriteUInt16 写入无符号 16 位整数（小端序）。
func WriteUInt16(h DataHnd, v uint16) error {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, v)
	_, err := WriteBuffer(h, b)
	return err
}

// WriteInt32 写入有符号 32 位整数（小端序）。
func WriteInt32(h DataHnd, v int32) error {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, uint32(v))
	_, err := WriteBuffer(h, b)
	return err
}

// WriteUInt32 写入无符号 32 位整数（小端序）。
func WriteUInt32(h DataHnd, v uint32) error {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	_, err := WriteBuffer(h, b)
	return err
}

// WriteInt64 写入有符号 64 位整数（小端序）。
func WriteInt64(h DataHnd, v int64) error {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, uint64(v))
	_, err := WriteBuffer(h, b)
	return err
}

// WriteUInt64 写入无符号 64 位整数（小端序）。
func WriteUInt64(h DataHnd, v uint64) error {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, v)
	_, err := WriteBuffer(h, b)
	return err
}

// WriteSingle 写入 32 位浮点数（IEEE 754 小端序）。
func WriteSingle(h DataHnd, v float32) error {
	return WriteUInt32(h, math.Float32bits(v))
}

// WriteDouble 写入 64 位浮点数（IEEE 754 小端序）。
func WriteDouble(h DataHnd, v float64) error {
	return WriteUInt64(h, math.Float64bits(v))
}

// WriteStringZ 写入 UTF‑8 字符串并追加一个空终止符 (#0)。
// 这符合 C 和 Pascal 的跨语言字符串协议。空字符串只写入一个 #0。
func WriteStringZ(h DataHnd, s string) error {
	utf8 := []byte(s)
	if len(utf8) > 0 {
		if _, err := WriteBuffer(h, utf8); err != nil {
			return err
		}
	}
	_, err := WriteBuffer(h, []byte{0})
	return err
}

// ---------- 原子读取 ----------

// ReadInt8 读取有符号 8 位整数。
func ReadInt8(h DataHnd) (int8, error) {
	b := make([]byte, 1)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int8(b[0]), nil
}

// ReadUInt8 读取无符号 8 位整数。
func ReadUInt8(h DataHnd) (uint8, error) {
	b := make([]byte, 1)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return b[0], nil
}

// ReadInt16 读取有符号 16 位整数（小端序）。
func ReadInt16(h DataHnd) (int16, error) {
	b := make([]byte, 2)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int16(binary.LittleEndian.Uint16(b)), nil
}

// ReadUInt16 读取无符号 16 位整数（小端序）。
func ReadUInt16(h DataHnd) (uint16, error) {
	b := make([]byte, 2)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint16(b), nil
}

// ReadInt32 读取有符号 32 位整数（小端序）。
func ReadInt32(h DataHnd) (int32, error) {
	b := make([]byte, 4)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int32(binary.LittleEndian.Uint32(b)), nil
}

// ReadUInt32 读取无符号 32 位整数（小端序）。
func ReadUInt32(h DataHnd) (uint32, error) {
	b := make([]byte, 4)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint32(b), nil
}

// ReadInt64 读取有符号 64 位整数（小端序）。
func ReadInt64(h DataHnd) (int64, error) {
	b := make([]byte, 8)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int64(binary.LittleEndian.Uint64(b)), nil
}

// ReadUInt64 读取无符号 64 位整数（小端序）。
func ReadUInt64(h DataHnd) (uint64, error) {
	b := make([]byte, 8)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint64(b), nil
}

// ReadSingle 读取 32 位浮点数（小端序）。
func ReadSingle(h DataHnd) (float32, error) {
	v, err := ReadUInt32(h)
	if err != nil {
		return 0, err
	}
	return math.Float32frombits(v), nil
}

// ReadDouble 读取 64 位浮点数（小端序）。
func ReadDouble(h DataHnd) (float64, error) {
	v, err := ReadUInt64(h)
	if err != nil {
		return 0, err
	}
	return math.Float64frombits(v), nil
}

// ReadStringZ 读取一个以空终止符 (#0) 结尾的 UTF‑8 字符串。
// 从当前位置开始扫描，直到遇到 #0 或缓冲区末尾。
// 成功时，位置会移动到终止符之后；若未找到终止符，返回错误。
func ReadStringZ(h DataHnd) (string, error) {
	if h == 0 {
		return "", errors.New("invalid handle")
	}
	if err := loadLibrary(); err != nil {
		return "", err
	}
	start := GetPos(h)
	size := GetSize(h)
	if start >= size {
		return "", errors.New("no data")
	}
	ptr := GetBuffer(h)
	if ptr == nil {
		return "", errors.New("buffer is nil")
	}
	var end int64
	for end = start; end < size; end++ {
		if *(*byte)(unsafe.Pointer(uintptr(ptr) + uintptr(end))) == 0 {
			break
		}
	}
	if end >= size {
		return "", errors.New("no null terminator found")
	}
	length := end - start
	if length == 0 {
		SetPos(h, end+1)
		return "", nil
	}
	buf := make([]byte, length)
	src := uintptr(ptr) + uintptr(start)
	for i := 0; i < int(length); i++ {
		buf[i] = *(*byte)(unsafe.Pointer(src + uintptr(i)))
	}
	SetPos(h, end+1)
	return string(buf), nil
}

// ---------- 网络准备 ----------

// ResetPrepare 清除所有已准备的服务和客户端配置。
// 在重新配置前调用，可多次调用。
func ResetPrepare() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.ResetPrepare)
}

// PrepareClient 准备一个客户端连接。
// addr 必须与服务端的公布地址完全一致（如 "ipc:my_service" 或 "127.0.0.1:9898"）。
// 该客户端不暴露任何 API（纯消费端）。若需暴露 API，请使用 Server.Start。
func PrepareClient(addr string) error {
	if err := loadLibrary(); err != nil {
		return err
	}
	cAddr := C.CString(addr)
	defer C.free(unsafe.Pointer(cAddr))
	ret := callFunc(funcs.PrepareClient, uintptr(unsafe.Pointer(cAddr)), 0)
	if ret == 0 {
		return errors.New("PrepareClient failed")
	}
	return nil
}

// PrepareService 准备一个服务监听器。
// addr 同时作为监听地址和公布地址（通常用于 IPC 或本地测试）。
// 若需分开监听和公布地址，请使用 Server.Start（内部会调用底层 API_Prepare_Service）。
func PrepareService(addr string) error {
	if err := loadLibrary(); err != nil {
		return err
	}
	cAddr := C.CString(addr)
	defer C.free(unsafe.Pointer(cAddr))
	ret := callFunc(funcs.PrepareService, uintptr(unsafe.Pointer(cAddr)), uintptr(unsafe.Pointer(cAddr)))
	if ret == 0 {
		return errors.New("PrepareService failed")
	}
	return nil
}

// PrepareDone 启动网络框架，阻塞直到所有准备的服务/客户端就绪。
// 返回 true 表示成功，false 表示失败（错误信息会输出到控制台或可通过 GetStatus 获取）。
func PrepareDone() (bool, error) {
	if err := loadLibrary(); err != nil {
		return false, err
	}
	ret := callFunc(funcs.PrepareDone)
	return ret == 1, nil
}

// ---------- 远程调用 ----------

// Call 同步调用远程应用。
// appName 是目标应用名（区分大小写），param 是输入数据句柄。
// timeoutMs 为超时毫秒数，0 表示无限等待。
// 返回的结果句柄必须由调用者 FreeDataHnd 释放（即使大小为 0）。
func Call(appName string, param DataHnd, timeoutMs uint32) (DataHnd, error) {
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	cApp := C.CString(appName)
	defer C.free(unsafe.Pointer(cApp))
	ret := callFunc(funcs.Call, uintptr(unsafe.Pointer(cApp)), uintptr(param), uintptr(timeoutMs))
	return DataHnd(ret), nil
}

// Notify 发送单向通知，不等待响应。
func Notify(appName string, param DataHnd) {
	if param == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	cApp := C.CString(appName)
	defer C.free(unsafe.Pointer(cApp))
	callFunc(funcs.Notify, uintptr(unsafe.Pointer(cApp)), uintptr(param))
}

// SetOption 动态调整全局运行时配置。
// 支持的选项包括 "password", "Quiet", "Wait_Connection_ReadyOk" 等。
// 详见 C 语言文档或 API_HubTool.h。
func SetOption(option, value string) {
	if err := loadLibrary(); err != nil {
		return
	}
	cOpt := C.CString(option)
	cVal := C.CString(value)
	defer C.free(unsafe.Pointer(cOpt))
	defer C.free(unsafe.Pointer(cVal))
	callFunc(funcs.SetOption, uintptr(unsafe.Pointer(cOpt)), uintptr(unsafe.Pointer(cVal)))
}

// Shutdown 完全关闭框架，停止所有服务、断开客户端、释放资源。
// 在程序退出前必须调用。
func Shutdown() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.Shutdown)
}

// ---------- v2.1 新增状态与检查 API ----------

// CheckMainThread 检查模拟主线程（C4 事件循环）是否正在运行。
// 返回 1 表示运行中，0 表示已停止或未启动。
func CheckMainThread() int {
	if err := loadLibrary(); err != nil {
		return 0
	}
	ret := callFunc(funcs.CheckMainThread)
	return int(ret)
}

// CheckApp 检查网络中是否存在指定名称的应用（基于本地缓存，可能有短暂滞后）。
// 返回 1 表示存在，0 表示不存在。
func CheckApp(appName string) int {
	if err := loadLibrary(); err != nil {
		return 0
	}
	cApp := C.CString(appName)
	defer C.free(unsafe.Pointer(cApp))
	ret := callFunc(funcs.CheckApp, uintptr(unsafe.Pointer(cApp)))
	return int(ret)
}

// GetStatusNum 返回内部日志队列中待读取的消息数量。
func GetStatusNum() int {
	if err := loadLibrary(); err != nil {
		return 0
	}
	ret := callFunc(funcs.GetStatusNum)
	return int(ret)
}

// GetStatus 从队列中取出下一条日志消息（FIFO 顺序）。
// 返回的字符串是 UTF‑8 编码，内部已复制到 Go 字符串，调用者无需释放。
// 若队列为空，返回空字符串。
// 注意：此函数使用了 cgo 的 C.GoString，这是标准用法，实际编译通过。
func GetStatus() string {
	if err := loadLibrary(); err != nil {
		return ""
	}
	ret := callFunc(funcs.GetStatus)
	if ret == 0 {
		return ""
	}
	// C.GoString 是 cgo 提供的标准转换函数，将 *C.char 转为 Go string。
	return cgoGoString((*C.char)(unsafe.Pointer(ret)))
}

// PostStatus 向日志队列中注入一条自定义消息，与库自身日志混合。
func PostStatus(status string) {
	if err := loadLibrary(); err != nil {
		return
	}
	cStatus := C.CString(status)
	defer C.free(unsafe.Pointer(cStatus))
	callFunc(funcs.PostStatus, uintptr(unsafe.Pointer(cStatus)))
}

// ---------- Client 包装器 ----------

// Client 是一个轻量级客户端，封装了所有包级函数。
// 它主要提供方法调用语法，实际功能与包级函数相同。
type Client struct{}

// NewClient 创建一个新的客户端实例。
// 它不进行网络连接，仅用于调用后续方法。
func NewClient() (*Client, error) {
	if err := loadLibrary(); err != nil {
		return nil, err
	}
	return &Client{}, nil
}

// Close 是一个空操作，仅用于满足 io.Closer 接口。
func (c *Client) Close() {}

// 以下所有方法直接转发至包级函数。

func (c *Client) CreateDataHnd(name string) (DataHnd, error) { return CreateDataHnd(name) }
func (c *Client) FreeDataHnd(h DataHnd)                      { FreeDataHnd(h) }
func (c *Client) GetBuffer(h DataHnd) unsafe.Pointer         { return GetBuffer(h) }
func (c *Client) WriteBuffer(h DataHnd, d []byte) (int64, error) {
	return WriteBuffer(h, d)
}
func (c *Client) ReadBuffer(h DataHnd, d []byte) (int64, error) { return ReadBuffer(h, d) }
func (c *Client) GetPos(h DataHnd) int64                        { return GetPos(h) }
func (c *Client) SetPos(h DataHnd, pos int64)                   { SetPos(h, pos) }
func (c *Client) GetSize(h DataHnd) int64                       { return GetSize(h) }
func (c *Client) SetSize(h DataHnd, size int64)                 { SetSize(h, size) }
func (c *Client) WriteInt8(h DataHnd, v int8) error             { return WriteInt8(h, v) }
func (c *Client) WriteUInt8(h DataHnd, v uint8) error           { return WriteUInt8(h, v) }
func (c *Client) WriteInt16(h DataHnd, v int16) error           { return WriteInt16(h, v) }
func (c *Client) WriteUInt16(h DataHnd, v uint16) error         { return WriteUInt16(h, v) }
func (c *Client) WriteInt32(h DataHnd, v int32) error           { return WriteInt32(h, v) }
func (c *Client) WriteUInt32(h DataHnd, v uint32) error         { return WriteUInt32(h, v) }
func (c *Client) WriteInt64(h DataHnd, v int64) error           { return WriteInt64(h, v) }
func (c *Client) WriteUInt64(h DataHnd, v uint64) error         { return WriteUInt64(h, v) }
func (c *Client) WriteSingle(h DataHnd, v float32) error        { return WriteSingle(h, v) }
func (c *Client) WriteDouble(h DataHnd, v float64) error        { return WriteDouble(h, v) }
func (c *Client) WriteStringZ(h DataHnd, s string) error        { return WriteStringZ(h, s) }
func (c *Client) ReadInt8(h DataHnd) (int8, error)              { return ReadInt8(h) }
func (c *Client) ReadUInt8(h DataHnd) (uint8, error)            { return ReadUInt8(h) }
func (c *Client) ReadInt16(h DataHnd) (int16, error)            { return ReadInt16(h) }
func (c *Client) ReadUInt16(h DataHnd) (uint16, error)          { return ReadUInt16(h) }
func (c *Client) ReadInt32(h DataHnd) (int32, error)            { return ReadInt32(h) }
func (c *Client) ReadUInt32(h DataHnd) (uint32, error)          { return ReadUInt32(h) }
func (c *Client) ReadInt64(h DataHnd) (int64, error)            { return ReadInt64(h) }
func (c *Client) ReadUInt64(h DataHnd) (uint64, error)          { return ReadUInt64(h) }
func (c *Client) ReadSingle(h DataHnd) (float32, error)         { return ReadSingle(h) }
func (c *Client) ReadDouble(h DataHnd) (float64, error)         { return ReadDouble(h) }
func (c *Client) ReadStringZ(h DataHnd) (string, error)         { return ReadStringZ(h) }
func (c *Client) ResetPrepare()                                 { ResetPrepare() }
func (c *Client) PrepareClient(addr string) error               { return PrepareClient(addr) }
func (c *Client) PrepareService(addr string) error              { return PrepareService(addr) }
func (c *Client) PrepareDone() (bool, error)                    { return PrepareDone() }
func (c *Client) Call(app string, param DataHnd, t uint32) (DataHnd, error) {
	return Call(app, param, t)
}
func (c *Client) Notify(app string, param DataHnd) { Notify(app, param) }
func (c *Client) SetOption(opt, val string)        { SetOption(opt, val) }
func (c *Client) Shutdown()                        { Shutdown() }

// v2.1 新增客户端方法
func (c *Client) CheckMainThread() int        { return CheckMainThread() }
func (c *Client) CheckApp(appName string) int { return CheckApp(appName) }
func (c *Client) GetStatusNum() int           { return GetStatusNum() }
func (c *Client) GetStatus() string           { return GetStatus() }
func (c *Client) PostStatus(status string)    { PostStatus(status) }

// ---------- 二进制块辅助函数（长度前缀） ----------

// WriteBool 写入一个布尔值（0 或 1）。
func WriteBool(h DataHnd, v bool) error {
	if v {
		return WriteUInt8(h, 1)
	}
	return WriteUInt8(h, 0)
}

// ReadBool 读取一个布尔值。
func ReadBool(h DataHnd) (bool, error) {
	v, err := ReadUInt8(h)
	if err != nil {
		return false, err
	}
	return v != 0, nil
}

// WriteBytes 以长度前缀写入一个字节切片（先写入 4 字节长度，再写数据）。
func WriteBytes(h DataHnd, data []byte) error {
	if err := WriteInt32(h, int32(len(data))); err != nil {
		return err
	}
	_, err := WriteBuffer(h, data)
	return err
}

// ReadBytes 读取一个长度前缀的字节切片。
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

// 客户端转发二进制辅助函数
func (c *Client) WriteBool(h DataHnd, v bool) error    { return WriteBool(h, v) }
func (c *Client) ReadBool(h DataHnd) (bool, error)     { return ReadBool(h) }
func (c *Client) WriteBytes(h DataHnd, d []byte) error { return WriteBytes(h, d) }
func (c *Client) ReadBytes(h DataHnd) ([]byte, error)  { return ReadBytes(h) }
