package main

import (
	"fmt"
	"api-hub-go/api_hub"
)

func main() {
	client, _ := api_hub.NewClient()
	defer client.Close()
	client.ResetPrepare()
	client.PrepareClient("ipc:config_service")
	client.PrepareDone()
	defer client.Shutdown()

	h, _ := client.CreateDataHnd("set")
	client.WriteStringZ(h, "db_url")
	client.WriteStringZ(h, "postgres://localhost")
	client.Notify("ConfigService", h)
	client.FreeDataHnd(h)

	h2, _ := client.CreateDataHnd("get")
	client.WriteStringZ(h2, "db_url")
	res, _ := client.Call("ConfigService", h2, 3000)
	val, _ := api_hub.ReadStringZ(res)
	fmt.Println("db_url =", val)
	client.FreeDataHnd(res)
	client.FreeDataHnd(h2)
}
