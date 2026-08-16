package main

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"

	"api-hub-go/api_hub"
)

var (
	subsMu sync.Mutex
	subs   = make(map[string][]string)
)

func main() {
	srv, err := api_hub.NewServer("PubSubService", "pubsub")
	if err != nil {
		panic(err)
	}
	defer srv.Stop()

	// 订阅
	srv.RegisterNotify("subscribe", "", func(in api_hub.DataHnd) {
		topic, _ := api_hub.ReadString(in)
		clientID, _ := api_hub.ReadString(in)
		subsMu.Lock()
		subs[topic] = append(subs[topic], clientID)
		subsMu.Unlock()
		fmt.Printf("Subscribed %s to %s\n", clientID, topic)
	})

	// 发布
	srv.RegisterNotify("publish", "", func(in api_hub.DataHnd) {
		topic, _ := api_hub.ReadString(in)
		msg, _ := api_hub.ReadString(in)
		subsMu.Lock()
		list := subs[topic]
		subsMu.Unlock()
		for _, cid := range list {
			fmt.Printf("Notifying %s: %s\n", cid, msg)
		}
	})

	if err := srv.Start("ipc:pubsub_service"); err != nil {
		panic(err)
	}
	fmt.Println("PubSubService started on ipc:pubsub_service")

	// 等待退出信号
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan
	fmt.Println("Shutting down PubSubService...")
}
