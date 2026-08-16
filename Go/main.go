package main

import (
	"api-hub-go/api_hub"
	"fmt"
)

func main() {
	// 1. 创建服务端（本地应用，不启动网络）
	srv, err := api_hub.NewServer("HelloApp", "Local demo")
	if err != nil {
		panic(err)
	}
	defer srv.Stop()

	// 2. 注册一个简单的加法 API
	err = srv.RegisterCall("add", "a+b", func(in, out api_hub.DataHnd) {
		a, _ := api_hub.ReadInt32(in)
		b, _ := api_hub.ReadInt32(in)
		api_hub.WriteInt32(out, a+b)
	})
	if err != nil {
		panic(err)
	}

	// 3. 构造请求参数
	param, err := api_hub.CreateDataHnd("add")
	if err != nil {
		panic(err)
	}
	defer api_hub.FreeDataHnd(param)

	if err := api_hub.WriteInt32(param, 10); err != nil {
		panic(err)
	}
	if err := api_hub.WriteInt32(param, 20); err != nil {
		panic(err)
	}

	// 4. 本地调用（同步，不经过网络）
	res := srv.LocalCall(param)
	if res == 0 {
		panic("LocalCall failed")
	}
	defer api_hub.FreeDataHnd(res)

	// 5. 读取结果
	sum, err := api_hub.ReadInt32(res)
	if err != nil {
		panic(err)
	}
	fmt.Printf("10 + 20 = %d\n", sum)
}
