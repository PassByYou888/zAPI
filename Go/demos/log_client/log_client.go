package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	// 创建客户端
	client, err := api_hub.NewClient()
	if err != nil {
		panic(err)
	}
	defer client.Close()

	// 准备连接
	client.ResetPrepare()
	if err := client.PrepareClient("ipc:log_service"); err != nil {
		panic(err)
	}
	if ok, _ := client.PrepareDone(); !ok {
		panic("PrepareDone failed")
	}
	defer client.Shutdown()

	// 信号处理（Ctrl+C 优雅退出）
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\nReceived interrupt, shutting down...")
		client.Shutdown()
		os.Exit(0)
	}()

	// 发送第一条日志（INFO）
	h, err := client.CreateDataHnd("log")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h)

	if err := client.WriteString(h, "INFO"); err != nil {
		panic(err)
	}
	if err := client.WriteString(h, "Hello from Go client (INFO)"); err != nil {
		panic(err)
	}
	client.Notify("LogService", h)

	// 发送第二条日志（ERROR）
	h2, err := client.CreateDataHnd("log")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h2)

	if err := client.WriteString(h2, "ERROR"); err != nil {
		panic(err)
	}
	if err := client.WriteString(h2, "Something went wrong (ERROR)"); err != nil {
		panic(err)
	}
	client.Notify("LogService", h2)

	fmt.Println("Logs sent successfully.")
}
