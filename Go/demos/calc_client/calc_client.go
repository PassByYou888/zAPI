package main

import (
	"fmt"
	"api-hub-go/api_hub"
)

func main() {
	client, err := api_hub.NewClient()
	if err != nil {
		panic(err)
	}
	defer client.Close()
	client.ResetPrepare()
	client.PrepareClient("ipc:calc_service")
	ok, _ := client.PrepareDone()
	if !ok {
		panic("prepare failed")
	}
	defer client.Shutdown()

	h, _ := client.CreateDataHnd("add")
	client.WriteInt32(h, 10)
	client.WriteInt32(h, 20)
	res, _ := client.Call("CalcService", h, 3000)
	sum, _ := client.ReadInt32(res)
	fmt.Printf("10 + 20 = %d\n", sum)
	client.FreeDataHnd(res)
	client.FreeDataHnd(h)

	h2, _ := client.CreateDataHnd("mul")
	client.WriteInt32(h2, 7)
	client.WriteInt32(h2, 6)
	res2, _ := client.Call("CalcService", h2, 3000)
	mul, _ := client.ReadInt32(res2)
	fmt.Printf("7 * 6 = %d\n", mul)
	client.FreeDataHnd(res2)
	client.FreeDataHnd(h2)
}
