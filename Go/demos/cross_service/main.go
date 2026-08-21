package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	fmt.Println("=== Cross Service (Coordinator) ===")

	api_hub.ResetPrepare()

	if err := api_hub.PrepareService("ipc:cross"); err != nil {
		panic(fmt.Errorf("PrepareService failed: %w", err))
	}

	ok, err := api_hub.PrepareDone()
	if err != nil || !ok {
		panic("Prepare_Done failed")
	}

	fmt.Println("IPC service 'ipc:cross' is running. Press Ctrl+C to exit.")

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	// 直接调用 Shutdown（内部已包含退出主线程）
	api_hub.Shutdown()
	fmt.Println("Service stopped.")
}
