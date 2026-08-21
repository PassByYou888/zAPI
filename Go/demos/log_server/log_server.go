package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"api-hub-go/api_hub"
)

func main() {
	// 创建服务
	srv, err := api_hub.NewServer("LogService", "async logger")
	if err != nil {
		panic(err)
	}
	defer srv.Stop()

	// 注册 notify API
	srv.RegisterNotify("log", "", func(in api_hub.DataHnd) {
		level, _ := api_hub.ReadStringZ(in)
		msg, _ := api_hub.ReadStringZ(in)
		fmt.Printf("[%s] %s: %s\n", time.Now().Format("15:04:05"), level, msg)
	})

	// 启动服务
	if err := srv.Start("ipc:log_service"); err != nil {
		panic(err)
	}
	fmt.Println("LogService started on ipc:log_service")

	// 等待退出信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan
	fmt.Println("Shutting down LogService...")
}
