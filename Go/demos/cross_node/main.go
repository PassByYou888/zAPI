package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"api-hub-go/api_hub"
)

func main() {
	fmt.Println("=== Cross Node (Worker) ===")

	srv, err := api_hub.NewServer("demo", "Go worker node")
	if err != nil {
		panic(err)
	}
	defer srv.Stop()

	// 注册 add
	if err := srv.RegisterCall("add", "add(int32 a, int32 b)", func(in, out api_hub.DataHnd) {
		a, err1 := api_hub.ReadInt32(in)
		b, err2 := api_hub.ReadInt32(in)
		if err1 != nil || err2 != nil {
			fmt.Println("[Node] add: read params failed")
			return
		}
		sum := a + b
		if err := api_hub.WriteInt32(out, sum); err != nil {
			fmt.Println("[Node] add: write result failed")
			return
		}
		fmt.Printf("[Node] add(%d, %d) = %d\n", a, b, sum)
	}); err != nil {
		panic(err)
	}

	// 注册 inv_seri
	if err := srv.RegisterCall("inv_seri", "inv_seri()", func(in, out api_hub.DataHnd) {
		b, err1 := api_hub.ReadUInt8(in)
		w, err2 := api_hub.ReadUInt16(in)
		c, err3 := api_hub.ReadUInt32(in)
		u64, err4 := api_hub.ReadUInt64(in)
		s, err5 := api_hub.ReadStringZ(in)
		f, err6 := api_hub.ReadSingle(in)
		if err1 != nil || err2 != nil || err3 != nil || err4 != nil || err5 != nil || err6 != nil {
			fmt.Println("[Node] inv_seri: read failed")
			return
		}
		fmt.Printf("[Node] inv_seri received: [%d, %d, %d, %d, \"%s\", %.2f]\n", b, w, c, u64, s, f)

		// 反向写回
		if err := api_hub.WriteSingle(out, f); err != nil {
			fmt.Println("[Node] inv_seri: write float failed")
			return
		}
		if err := api_hub.WriteStringZ(out, s); err != nil {
			fmt.Println("[Node] inv_seri: write string failed")
			return
		}
		if err := api_hub.WriteUInt64(out, u64); err != nil {
			fmt.Println("[Node] inv_seri: write uint64 failed")
			return
		}
		if err := api_hub.WriteUInt32(out, c); err != nil {
			fmt.Println("[Node] inv_seri: write uint32 failed")
			return
		}
		if err := api_hub.WriteUInt16(out, w); err != nil {
			fmt.Println("[Node] inv_seri: write uint16 failed")
			return
		}
		if err := api_hub.WriteUInt8(out, b); err != nil {
			fmt.Println("[Node] inv_seri: write uint8 failed")
			return
		}
		fmt.Printf("[Node] inv_seri replied: [%.2f, \"%s\", %d, %d, %d, %d]\n", f, s, u64, c, w, b)
	}); err != nil {
		panic(err)
	}

	api_hub.SetOption("Wait_Ready", "False")

	if err := srv.Start("ipc:cross"); err != nil {
		panic(err)
	}

	fmt.Println("Node registered. Press Ctrl+C to exit.")

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)
	<-sigChan

	fmt.Println("Node shutting down...")
}
