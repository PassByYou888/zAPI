//go:build cgo
// +build cgo

package api_hub

import (
	"os"
	"testing"
	"time"
	"unsafe"
)

var testClient *Client

// TestMain sets up a client connection to a running FuncService.
// If the service is not available, tests are skipped.
func TestMain(m *testing.M) {
	var err error
	testClient, err = NewClient()
	if err != nil {
		println("API Hub library not available:", err.Error())
		os.Exit(0) // skip
	}

	testClient.ResetPrepare()
	_ = testClient.PrepareClient("ipc:func_service")
	ok, err := testClient.PrepareDone()
	if err != nil || !ok {
		// Service not running; skip tests.
		println("PrepareDone failed")
		os.Exit(0)
	}

	code := m.Run()

	testClient.Shutdown()
	testClient.Close()
	os.Exit(code)
}

// TestDataHandle verifies the basic data handle operations.
func TestDataHandle(t *testing.T) {
	h, err := testClient.CreateDataHnd("test")
	if err != nil {
		t.Fatal(err)
	}
	defer testClient.FreeDataHnd(h)

	if err := testClient.WriteInt32(h, 12345); err != nil {
		t.Fatal(err)
	}
	if testClient.GetSize(h) != 4 {
		t.Errorf("size = %d, expected 4", testClient.GetSize(h))
	}

	testClient.SetPos(h, 0)
	val, err := testClient.ReadInt32(h)
	if err != nil {
		t.Fatal(err)
	}
	if val != 12345 {
		t.Errorf("read value = %d, expected 12345", val)
	}

	if err := testClient.WriteString(h, "Hello, Go!"); err != nil {
		t.Fatal(err)
	}
	testClient.SetPos(h, 4)
	readStr, err := testClient.ReadString(h)
	if err != nil {
		t.Fatal(err)
	}
	if readStr != "Hello, Go!" {
		t.Errorf("string = %q, expected %q", readStr, "Hello, Go!")
	}
}

// TestRemoteCall performs two remote calls (add and to_upper) to FuncService.
func TestRemoteCall(t *testing.T) {
	time.Sleep(500 * time.Millisecond)

	param, err := testClient.CreateDataHnd("add")
	if err != nil {
		t.Fatal(err)
	}
	defer testClient.FreeDataHnd(param)

	if err := testClient.WriteInt32(param, 10); err != nil {
		t.Fatal(err)
	}
	if err := testClient.WriteInt32(param, 20); err != nil {
		t.Fatal(err)
	}

	res, err := testClient.Call("FuncService", param, 3000)
	if err != nil {
		t.Fatal(err)
	}
	if res == 0 {
		t.Fatal("Call returned null handle") // should not happen per spec
	}
	defer testClient.FreeDataHnd(res)

	if testClient.GetSize(res) < 4 {
		t.Fatalf("result size %d", testClient.GetSize(res))
	}
	testClient.SetPos(res, 0)
	sum, err := testClient.ReadInt32(res)
	if err != nil {
		t.Fatal(err)
	}
	if sum != 30 {
		t.Errorf("add(10,20) = %d, expected 30", sum)
	}

	// Test to_upper
	param2, err := testClient.CreateDataHnd("to_upper")
	if err != nil {
		t.Fatal(err)
	}
	defer testClient.FreeDataHnd(param2)

	if err := testClient.WriteString(param2, "hello world"); err != nil {
		t.Fatal(err)
	}

	res2, err := testClient.Call("FuncService", param2, 3000)
	if err != nil {
		t.Fatal(err)
	}
	if res2 == 0 {
		t.Fatal("Call to_upper returned null")
	}
	defer testClient.FreeDataHnd(res2)

	testClient.SetPos(res2, 0)
	upper, err := testClient.ReadString(res2)
	if err != nil {
		t.Fatal(err)
	}
	if upper != "HELLO WORLD" {
		t.Errorf("to_upper('hello world') = %q, expected 'HELLO WORLD'", upper)
	}
}

// TestGetBufferGetPosSetSize verifies the newly added functions.
func TestGetBufferGetPosSetSize(t *testing.T) {
	h, err := testClient.CreateDataHnd("buffer_test")
	if err != nil {
		t.Fatal(err)
	}
	defer testClient.FreeDataHnd(h)

	// Write some data
	data := []byte("Hello, Buffer!")
	_, err = testClient.WriteBuffer(h, data)
	if err != nil {
		t.Fatal(err)
	}
	if testClient.GetSize(h) != int64(len(data)) {
		t.Errorf("size = %d, expected %d", testClient.GetSize(h), len(data))
	}

	// Test GetPos
	pos := testClient.GetPos(h)
	if pos != int64(len(data)) {
		t.Errorf("pos = %d, expected %d", pos, len(data))
	}

	// Test SetPos
	testClient.SetPos(h, 3)
	if testClient.GetPos(h) != 3 {
		t.Errorf("after SetPos(3), pos = %d", testClient.GetPos(h))
	}

	// Test GetBuffer
	ptr := testClient.GetBuffer(h)
	if ptr == nil {
		t.Fatal("GetBuffer returned nil")
	}
	// Read from pointer to verify content
	buf := unsafe.Slice((*byte)(ptr), testClient.GetSize(h))
	if string(buf) != "Hello, Buffer!" {
		t.Errorf("buffer content = %q, expected %q", string(buf), "Hello, Buffer!")
	}

	// Test SetSize – truncate to 5 bytes
	testClient.SetSize(h, 5)
	if testClient.GetSize(h) != 5 {
		t.Errorf("after SetSize(5), size = %d", testClient.GetSize(h))
	}
	ptr2 := testClient.GetBuffer(h)
	buf2 := unsafe.Slice((*byte)(ptr2), 5)
	if string(buf2) != "Hello" {
		t.Errorf("after truncation, buffer = %q, expected %q", string(buf2), "Hello")
	}
}

// TestUTF8ChineseAPI registers a Chinese-named API and calls it.
func TestUTF8ChineseAPI(t *testing.T) {
	// Create a server with a Chinese name (app name also UTF-8)
	server, err := NewServer("中文服务", "测试中文API")
	if err != nil {
		t.Fatal(err)
	}
	defer server.Stop()

	// Register a Chinese-named call API
	callCount := 0
	err = server.RegisterCall("加法", "两数相加", func(in DataHnd, out DataHnd) {
		// Read two integers and write sum
		a, err1 := ReadInt32(in)
		b, err2 := ReadInt32(in)
		if err1 != nil || err2 != nil {
			return
		}
		_ = WriteInt32(out, a+b)
		callCount++
	})
	if err != nil {
		t.Fatal(err)
	}

	// Start the server (IPC)
	err = server.Start("ipc:chinese_test")
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(500 * time.Millisecond) // allow registration

	// Create a client that connects to the same IPC
	client, err := NewClient()
	if err != nil {
		t.Fatal(err)
	}
	defer client.Shutdown()
	client.ResetPrepare()
	_ = client.PrepareClient("ipc:chinese_test")
	ok, err := client.PrepareDone()
	if err != nil || !ok {
		t.Fatal("client PrepareDone failed")
	}

	// Call the Chinese-named API
	param, err := client.CreateDataHnd("加法")
	if err != nil {
		t.Fatal(err)
	}
	defer client.FreeDataHnd(param)
	_ = client.WriteInt32(param, 10)
	_ = client.WriteInt32(param, 20)

	res, err := client.Call("中文服务", param, 3000)
	if err != nil {
		t.Fatal(err)
	}
	defer client.FreeDataHnd(res)

	if client.GetSize(res) < 4 {
		t.Fatalf("result size %d", client.GetSize(res))
	}
	client.SetPos(res, 0)
	sum, err := client.ReadInt32(res)
	if err != nil {
		t.Fatal(err)
	}
	if sum != 30 {
		t.Errorf("中文加法(10,20) = %d, expected 30", sum)
	}
	if callCount != 1 {
		t.Errorf("callCount = %d, expected 1", callCount)
	}

	// Also test Chinese notification
	notifyDone := false
	err = server.RegisterNotify("日志", "中文日志", func(in DataHnd) {
		msg, _ := ReadString(in)
		if msg == "测试通知" {
			notifyDone = true
		}
	})
	if err != nil {
		t.Fatal(err)
	}
	// Send a notification
	notifyParam, err := client.CreateDataHnd("日志")
	if err != nil {
		t.Fatal(err)
	}
	defer client.FreeDataHnd(notifyParam)
	_ = client.WriteString(notifyParam, "测试通知")
	client.Notify("中文服务", notifyParam)
	time.Sleep(200 * time.Millisecond)
	if !notifyDone {
		t.Error("Chinese notify was not received")
	}
}

func TestUnregister(t *testing.T) {
	server, err := NewServer("UnregTest", "test")
	if err != nil {
		t.Fatal(err)
	}
	defer server.Stop()

	err = server.RegisterCall("temp", "temp", func(in DataHnd, out DataHnd) {
		// dummy
	})
	if err != nil {
		t.Fatal(err)
	}

	// Unregister
	err = server.Unregister("temp")
	if err != nil {
		t.Fatal(err)
	}

	// Try to call locally – should fail (size 0)
	param, _ := CreateDataHnd("temp")
	defer FreeDataHnd(param)
	res := server.LocalCall(param)
	defer FreeDataHnd(res)
	if GetSize(res) != 0 {
		t.Errorf("expected 0 size after unregister, got %d", GetSize(res))
	}
}

func TestSetOption(t *testing.T) {
	// Set a known option
	SetOption("Quiet", "True")
	// No way to verify, but ensure no panic
	SetOption("unknown", "value") // should be ignored
}
