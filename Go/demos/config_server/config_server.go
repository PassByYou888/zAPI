package main

import (
	"sync"
	"api-hub-go/api_hub"

	"time"
)

var (
	cfgMu sync.RWMutex
	cfg   = make(map[string]string)
)

func main() {
	srv, _ := api_hub.NewServer("ConfigService", "config center")
	defer srv.Stop()
	srv.RegisterNotify("set", "", func(in api_hub.DataHnd) {
		key, _ := api_hub.ReadString(in)
		val, _ := api_hub.ReadString(in)
		cfgMu.Lock()
		cfg[key] = val
		cfgMu.Unlock()
	})
	srv.RegisterCall("get", "", func(in, out api_hub.DataHnd) {
		key, _ := api_hub.ReadString(in)
		cfgMu.RLock()
		val := cfg[key]
		cfgMu.RUnlock()
		api_hub.WriteString(out, val)
	})
	srv.Start("ipc:config_service")
	for { time.Sleep(time.Hour) }
}


