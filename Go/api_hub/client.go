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

type DataHnd uintptr
type AppHnd uintptr

// ---------- 基础函数 ----------
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

func FreeDataHnd(h DataHnd) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.FreeDataHnd, uintptr(h))
}

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

func SetPos(h DataHnd, pos int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetPos, uintptr(h), uintptr(pos))
}

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

func SetSize(h DataHnd, size int64) {
	if h == 0 {
		return
	}
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.SetSize, uintptr(h), uintptr(size))
}

// ---------- 原子写入（Go 层实现） ----------
func WriteInt8(h DataHnd, v int8) error {
	_, err := WriteBuffer(h, []byte{byte(v)})
	return err
}
func WriteUInt8(h DataHnd, v uint8) error {
	_, err := WriteBuffer(h, []byte{v})
	return err
}
func WriteInt16(h DataHnd, v int16) error {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, uint16(v))
	_, err := WriteBuffer(h, b)
	return err
}
func WriteUInt16(h DataHnd, v uint16) error {
	b := make([]byte, 2)
	binary.LittleEndian.PutUint16(b, v)
	_, err := WriteBuffer(h, b)
	return err
}
func WriteInt32(h DataHnd, v int32) error {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, uint32(v))
	_, err := WriteBuffer(h, b)
	return err
}
func WriteUInt32(h DataHnd, v uint32) error {
	b := make([]byte, 4)
	binary.LittleEndian.PutUint32(b, v)
	_, err := WriteBuffer(h, b)
	return err
}
func WriteInt64(h DataHnd, v int64) error {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, uint64(v))
	_, err := WriteBuffer(h, b)
	return err
}
func WriteUInt64(h DataHnd, v uint64) error {
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, v)
	_, err := WriteBuffer(h, b)
	return err
}
func WriteSingle(h DataHnd, v float32) error {
	return WriteUInt32(h, math.Float32bits(v))
}
func WriteDouble(h DataHnd, v float64) error {
	return WriteUInt64(h, math.Float64bits(v))
}

// WriteStringZ 写入 UTF‑8 + 空终止（符合 Pascal API_WriteString 行为）
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
func ReadInt8(h DataHnd) (int8, error) {
	b := make([]byte, 1)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int8(b[0]), nil
}
func ReadUInt8(h DataHnd) (uint8, error) {
	b := make([]byte, 1)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return b[0], nil
}
func ReadInt16(h DataHnd) (int16, error) {
	b := make([]byte, 2)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int16(binary.LittleEndian.Uint16(b)), nil
}
func ReadUInt16(h DataHnd) (uint16, error) {
	b := make([]byte, 2)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint16(b), nil
}
func ReadInt32(h DataHnd) (int32, error) {
	b := make([]byte, 4)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int32(binary.LittleEndian.Uint32(b)), nil
}
func ReadUInt32(h DataHnd) (uint32, error) {
	b := make([]byte, 4)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint32(b), nil
}
func ReadInt64(h DataHnd) (int64, error) {
	b := make([]byte, 8)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return int64(binary.LittleEndian.Uint64(b)), nil
}
func ReadUInt64(h DataHnd) (uint64, error) {
	b := make([]byte, 8)
	if _, err := ReadBuffer(h, b); err != nil {
		return 0, err
	}
	return binary.LittleEndian.Uint64(b), nil
}
func ReadSingle(h DataHnd) (float32, error) {
	v, err := ReadUInt32(h)
	if err != nil {
		return 0, err
	}
	return math.Float32frombits(v), nil
}
func ReadDouble(h DataHnd) (float64, error) {
	v, err := ReadUInt64(h)
	if err != nil {
		return 0, err
	}
	return math.Float64frombits(v), nil
}

// ReadStringZ 读取空终止 UTF‑8 字符串（符合 Pascal API_ReadString 行为）
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
func ResetPrepare() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.ResetPrepare)
}

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

func PrepareDone() (bool, error) {
	if err := loadLibrary(); err != nil {
		return false, err
	}
	ret := callFunc(funcs.PrepareDone)
	return ret == 1, nil
}

// ---------- 远程调用 ----------
func Call(appName string, param DataHnd, timeoutMs uint32) (DataHnd, error) {
	if err := loadLibrary(); err != nil {
		return 0, err
	}
	cApp := C.CString(appName)
	defer C.free(unsafe.Pointer(cApp))
	ret := callFunc(funcs.Call, uintptr(unsafe.Pointer(cApp)), uintptr(param), uintptr(timeoutMs))
	return DataHnd(ret), nil
}

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

func Shutdown() {
	if err := loadLibrary(); err != nil {
		return
	}
	callFunc(funcs.Shutdown)
}

// ---------- Client 包装器 ----------
type Client struct{}

func NewClient() (*Client, error) {
	if err := loadLibrary(); err != nil {
		return nil, err
	}
	return &Client{}, nil
}
func (c *Client) Close() {}

// 转发所有函数（原子函数已在包级实现）
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

// ---------- 二进制块辅助函数（长度前缀，仅供二进制数据使用） ----------
func WriteBool(h DataHnd, v bool) error {
	if v {
		return WriteUInt8(h, 1)
	}
	return WriteUInt8(h, 0)
}
func ReadBool(h DataHnd) (bool, error) {
	v, err := ReadUInt8(h)
	if err != nil {
		return false, err
	}
	return v != 0, nil
}
func WriteBytes(h DataHnd, data []byte) error {
	if err := WriteInt32(h, int32(len(data))); err != nil {
		return err
	}
	_, err := WriteBuffer(h, data)
	return err
}
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
