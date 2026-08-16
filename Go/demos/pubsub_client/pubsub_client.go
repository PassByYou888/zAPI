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

	// 1. 订阅主题 weather
	h, err := client.CreateDataHnd("subscribe")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h)

	if err := client.WriteString(h, "weather"); err != nil {
		panic(err)
	}
	if err := client.WriteString(h, "client1"); err != nil {
		panic(err)
	}
	client.Notify("PubSubService", h)
	fmt.Println("Subscribed to weather")

	// 2. 发布消息到 weather
	h2, err := client.CreateDataHnd("publish")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h2)

	if err := client.WriteString(h2, "weather"); err != nil {
		panic(err)
	}
	if err := client.WriteString(h2, "Sunny day!"); err != nil {
		panic(err)
	}
	client.Notify("PubSubService", h2)
	fmt.Println("Published message: Sunny day!")

	// 再发一条
	h3, err := client.CreateDataHnd("publish")
	if err != nil {
		panic(err)
	}
	defer client.FreeDataHnd(h3)

	if err := client.WriteString(h3, "weather"); err != nil {
		panic(err)
	}
	if err := client.WriteString(h3, "Rainy afternoon"); err != nil {
		panic(err)
	}
	client.Notify("PubSubService", h3)
	fmt.Println("Published message: Rainy afternoon")

	fmt.Println("All pub/sub operations completed.")
}
