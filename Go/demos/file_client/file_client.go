package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	client, err := api_hub.NewClient()
	if err != nil {
		panic(err)
	}
	defer client.Close()

	client.ResetPrepare()
	if err := client.PrepareClient("ipc:file_service"); err != nil {
		panic(err)
	}
	if ok, _ := client.PrepareDone(); !ok {
		panic("PrepareDone failed")
	}
	defer client.Shutdown()

	// 信号处理
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\nReceived interrupt, shutting down...")
		client.Shutdown()
		os.Exit(0)
	}()

	// 准备上传数据（整个文件内容）
	content := []byte("Hello API Hub from Go! This is a test file for bulk transfer.")

	// 1. 上传
	h, err := client.CreateDataHnd("upload")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h)

	// 写入文件名
	if err := client.WriteString(h, "test.txt"); err != nil {
		panic(err)
	}
	// 一次性写入整个文件内容（而不是分块）
	if err := client.WriteBytes(h, content); err != nil {
		panic(err)
	}

	res, err := client.Call("FileService", h, 10000) // 10秒超时
	if err != nil {
		fmt.Println("upload call error:", err)
		return
	}
	defer client.FreeDataHnd(res)

	ok, err := api_hub.ReadBool(res)
	if err != nil || !ok {
		fmt.Println("Upload failed:", err)
		os.Exit(1)
	}
	fmt.Println("Upload success:", ok)

	// 2. 下载
	h2, err := client.CreateDataHnd("download")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h2)

	if err := client.WriteString(h2, "test.txt"); err != nil {
		panic(err)
	}

	res2, err := client.Call("FileService", h2, 10000)
	if err != nil {
		fmt.Println("download call error:", err)
		return
	}
	defer client.FreeDataHnd(res2)

	// 一次性读取整个文件内容
	downloaded, err := api_hub.ReadBytes(res2)
	if err != nil {
		fmt.Println("download read bytes error:", err)
		return
	}
	fmt.Println("Downloaded:", string(downloaded))
	fmt.Printf("Downloaded size: %d bytes\n", len(downloaded))

	fmt.Println("All operations completed successfully.")
}
