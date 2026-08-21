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
	if err := client.PrepareClient("ipc:pubsub_service"); err != nil {
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

	// 订阅 weather
	h, err := client.CreateDataHnd("subscribe")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h)

	if err := client.WriteStringZ(h, "weather"); err != nil {
		panic(err)
	}
	if err := client.WriteStringZ(h, "client1"); err != nil {
		panic(err)
	}
	client.Notify("PubSubService", h)

	// 发布 weather
	h2, err := client.CreateDataHnd("publish")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h2)

	if err := client.WriteStringZ(h2, "weather"); err != nil {
		panic(err)
	}
	if err := client.WriteStringZ(h2, "Sunny"); err != nil {
		panic(err)
	}
	client.Notify("PubSubService", h2)

	fmt.Println("PubSub messages sent.")
}
