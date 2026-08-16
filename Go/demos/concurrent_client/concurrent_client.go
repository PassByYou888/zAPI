package main

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"api-hub-go/api_hub"
)

func main() {
	// 1. 创建客户端
	client, err := api_hub.NewClient()
	if err != nil {
		panic(err)
	}
	defer client.Close()

	// 2. 准备连接
	client.ResetPrepare()
	if err := client.PrepareClient("ipc:calc_service"); err != nil {
		panic(err)
	}
	if ok, _ := client.PrepareDone(); !ok {
		panic("PrepareDone failed")
	}
	// 正常退出时调用 Shutdown
	defer client.Shutdown()

	// 3. 信号处理：捕获 Ctrl+C 和 SIGTERM，强制退出时也调用 Shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigChan
		fmt.Println("\nReceived interrupt, shutting down...")
		client.Shutdown()
		os.Exit(0)
	}()

	// 4. 并发压测
	const N = 1000
	var wg sync.WaitGroup
	start := time.Now()

	for i := 0; i < N; i++ {
		wg.Add(1)
		go func(a, b int) {
			defer wg.Done()

			h, err := client.CreateDataHnd("add")
			if err != nil {
				return
			}
			defer client.FreeDataHnd(h)

			if err := client.WriteInt32(h, int32(a)); err != nil {
				return
			}
			if err := client.WriteInt32(h, int32(b)); err != nil {
				return
			}

			res, err := client.Call("CalcService", h, 3000)
			if err != nil || res == 0 {
				return
			}
			defer client.FreeDataHnd(res)
			// 忽略结果，只做压测
		}(i, i*2)
	}

	// 5. 等待所有 goroutine 完成
	wg.Wait()
	elapsed := time.Since(start)
	fmt.Printf("%d calls in %v, QPS=%.2f\n", N, elapsed, float64(N)/elapsed.Seconds())

	// 6. 正常退出，defer client.Shutdown() 会执行
	fmt.Println("All calls completed, exiting normally.")
}
