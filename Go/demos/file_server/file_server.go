package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	srv, err := api_hub.NewServer("FileService", "file transfer (bulk)")
	if err != nil {
		panic(err)
	}
	defer srv.Stop()

	// upload: 接收文件名 + 整个文件内容（一次性读取）
	srv.RegisterCall("upload", "", func(in, out api_hub.DataHnd) {
		// 1. 读取文件名（字符串）
		name, err := api_hub.ReadString(in)
		if err != nil {
			fmt.Println("upload: read name failed:", err)
			api_hub.WriteBool(out, false)
			return
		}
		fmt.Printf("upload: receiving file '%s'\n", name)

		// 2. 读取整个文件内容（字节数组）
		//    注意：这里直接读取剩余所有字节，因为客户端一次性写入了整个文件数据。
		//    由于数据句柄内部是连续缓冲区，顺序读取即可得到完整数据。
		fileData, err := api_hub.ReadBytes(in)
		if err != nil {
			fmt.Println("upload: read file data failed:", err)
			api_hub.WriteBool(out, false)
			return
		}
		if len(fileData) == 0 {
			fmt.Println("upload: empty file")
			api_hub.WriteBool(out, false)
			return
		}

		// 3. 写入磁盘
		if err := os.WriteFile(name, fileData, 0644); err != nil {
			fmt.Println("upload: write file failed:", err)
			api_hub.WriteBool(out, false)
			return
		}

		fmt.Printf("upload: file %s saved (%d bytes)\n", name, len(fileData))
		api_hub.WriteBool(out, true)
	})

	// download: 读取文件名，返回整个文件内容（一次性写入）
	srv.RegisterCall("download", "", func(in, out api_hub.DataHnd) {
		name, err := api_hub.ReadString(in)
		if err != nil {
			fmt.Println("download: read name failed:", err)
			return
		}
		fmt.Printf("download: reading file '%s'\n", name)

		fileData, err := os.ReadFile(name)
		if err != nil {
			fmt.Println("download: read file failed:", err)
			return
		}

		// 将整个文件内容写入输出句柄（一次性）
		if err := api_hub.WriteBytes(out, fileData); err != nil {
			fmt.Println("download: write bytes failed:", err)
			return
		}
		fmt.Printf("download: file %s sent (%d bytes)\n", name, len(fileData))
	})

	if err := srv.Start("ipc:file_service"); err != nil {
		panic(err)
	}
	fmt.Println("FileService started on ipc:file_service")

	// 等待退出信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan
	fmt.Println("Shutting down FileService...")
}
