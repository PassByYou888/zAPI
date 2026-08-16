package main

import (
	"fmt"
	"api-hub-go/api_hub"
)

func main() {
	client, _ := api_hub.NewClient()
	defer client.Close()
	client.ResetPrepare()
	client.PrepareClient("ipc:func_service")
	ok, _ := client.PrepareDone()
	if !ok {
		panic("FuncService not running?")
	}
	defer client.Shutdown()

	h, _ := client.CreateDataHnd("add")
	client.WriteInt32(h, 100)
	client.WriteInt32(h, 200)
	res, _ := client.Call("FuncService", h, 3000)
	sum, _ := client.ReadInt32(res)
	fmt.Println("add(100,200) =", sum)
	client.FreeDataHnd(res)
	client.FreeDataHnd(h)

	h2, _ := client.CreateDataHnd("to_upper")
	client.WriteString(h2, "go language")
	res2, _ := client.Call("FuncService", h2, 3000)
	s, _ := api_hub.ReadString(res2)
	fmt.Println("to_upper('go language') =", s)
	client.FreeDataHnd(res2)
	client.FreeDataHnd(h2)

	h3, _ := client.CreateDataHnd("sha3")
	client.WriteString(h3, "hello")
	res3, _ := client.Call("FuncService", h3, 5000)
	hash, _ := api_hub.ReadString(res3)
	fmt.Println("SHA3('hello') =", hash)
	client.FreeDataHnd(res3)
	client.FreeDataHnd(h3)
}
