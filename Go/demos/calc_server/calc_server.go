package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	// 1. 创建服务
	srv, err := api_hub.NewServer("CalcService", "Calculator")
	if err != nil {
		panic(err)
	}
	defer srv.Stop() // 正常退出时清理

	// 2. 注册 API
	srv.RegisterCall("add", "a+b", func(in, out api_hub.DataHnd) {
		a, _ := api_hub.ReadInt32(in)
		b, _ := api_hub.ReadInt32(in)
		api_hub.WriteInt32(out, a+b)
	})
	srv.RegisterCall("sub", "a-b", func(in, out api_hub.DataHnd) {
		a, _ := api_hub.ReadInt32(in)
		b, _ := api_hub.ReadInt32(in)
		api_hub.WriteInt32(out, a-b)
	})
	srv.RegisterCall("mul", "a*b", func(in, out api_hub.DataHnd) {
		a, _ := api_hub.ReadInt32(in)
		b, _ := api_hub.ReadInt32(in)
		api_hub.WriteInt32(out, a*b)
	})
	srv.RegisterCall("div", "a/b", func(in, out api_hub.DataHnd) {
		a, _ := api_hub.ReadInt32(in)
		b, _ := api_hub.ReadInt32(in)
		if b == 0 {
			api_hub.WriteInt32(out, 0)
			return
		}
		api_hub.WriteInt32(out, a/b)
	})

	// 3. 启动服务
	if err := srv.Start("ipc:calc_service"); err != nil {
		panic(err)
	}
	fmt.Println("CalcService started on ipc:calc_service")

	// 4. 等待退出信号（Ctrl+C 或 kill）
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	// 5. 收到信号，执行 defer srv.Stop()
	fmt.Println("Shutting down CalcService...")
}
