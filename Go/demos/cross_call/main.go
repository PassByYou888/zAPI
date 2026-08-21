package main

import (
	"fmt"
	"math/rand"
	"sync"
	"time"

	"api-hub-go/api_hub"
)

func main() {
	fmt.Println("=== Cross Call (Client) ===")

	client, err := api_hub.NewClient()
	if err != nil {
		panic(err)
	}
	defer client.Close()

	client.ResetPrepare()
	if err := client.PrepareClient("ipc:cross"); err != nil {
		panic(err)
	}
	ok, err := client.PrepareDone()
	if err != nil || !ok {
		panic("Prepare_Done failed")
	}
	defer client.Shutdown()

	fmt.Println("Connected to ipc:cross. Starting 10-second load test...")

	const (
		threads   = 10
		duration  = 10 * time.Second
		timeoutMs = 1000
	)

	var wg sync.WaitGroup
	stopFlag := false

	for i := 0; i < threads; i++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			rng := rand.New(rand.NewSource(time.Now().UnixNano() + int64(id)))

			for !stopFlag {
				if rng.Intn(2) == 0 {
					a := rng.Int31n(1000) + 1
					b := rng.Int31n(1000) + 1
					param, err := client.CreateDataHnd("add")
					if err != nil {
						continue
					}
					if err := client.WriteInt32(param, a); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteInt32(param, b); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					res, err := client.Call("demo", param, timeoutMs)
					client.FreeDataHnd(param)
					if err != nil || res == 0 {
						fmt.Printf("[Client %d] add(%d,%d) timed out or failed\n", id, a, b)
						continue
					}
					sum, err := client.ReadInt32(res)
					client.FreeDataHnd(res)
					if err != nil {
						fmt.Printf("[Client %d] add(%d,%d) read result failed\n", id, a, b)
					} else {
						fmt.Printf("[Client %d] add(%d,%d) = %d\n", id, a, b, sum)
					}
				} else {
					param, err := client.CreateDataHnd("inv_seri")
					if err != nil {
						continue
					}
					bVal := uint8(200)
					wVal := uint16(0x10)
					cVal := uint32(0x2F)
					u64Val := uint64(0x3F)
					sVal := "hello world"
					fVal := float32(3.14)

					if err := client.WriteUInt8(param, bVal); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteUInt16(param, wVal); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteUInt32(param, cVal); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteUInt64(param, u64Val); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteStringZ(param, sVal); err != nil {
						client.FreeDataHnd(param)
						continue
					}
					if err := client.WriteSingle(param, fVal); err != nil {
						client.FreeDataHnd(param)
						continue
					}

					res, err := client.Call("demo", param, timeoutMs)
					client.FreeDataHnd(param)
					if err != nil || res == 0 {
						fmt.Printf("[Client %d] inv_seri timed out or failed\n", id)
						continue
					}

					f2, err1 := client.ReadSingle(res)
					s2, err2 := client.ReadStringZ(res)
					u64_2, err3 := client.ReadUInt64(res)
					c2, err4 := client.ReadUInt32(res)
					w2, err5 := client.ReadUInt16(res)
					b2, err6 := client.ReadUInt8(res)
					client.FreeDataHnd(res)

					if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil || err6 != nil {
						fmt.Printf("[Client %d] inv_seri read reply failed\n", id)
						continue
					}
					fmt.Printf("[Client %d] inv_seri reply: [%d, %d, %d, %d, \"%s\", %.2f]  original: [%d, %d, %d, %d, \"%s\", %.2f]\n",
						id, b2, w2, c2, u64_2, s2, f2, bVal, wVal, cVal, u64Val, sVal, fVal)
				}
				time.Sleep(50 * time.Millisecond)
			}
		}(i)
	}

	time.Sleep(duration)
	stopFlag = true
	wg.Wait()

	fmt.Println("Load test finished. Press Enter to exit.")
	fmt.Scanln()
}
