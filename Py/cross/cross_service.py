#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
CrossService – 服务注册中心（信标）
功能：创建 IPC 端点 ipc:cross，作为 C4 服务网格的控制平面。
不注册任何业务 API。节点和客户端通过此端点发现彼此。
与 Pascal cross_service 完全等价。
"""
import sys
import os

# 将上级目录（Py）加入模块搜索路径，以便导入 api_hub
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from api_hub import _native


def main():
    print("=== CrossService (Python) – Service Registry ===")

    # 注册 Shutdown Hook 确保 Ctrl+C 时优雅释放资源
    import atexit
    def cleanup():
        print("[Shutdown] Exiting main thread and shutting down.")
        _native.API_Exit_MainThread()
        _native.API_shutdown()
    atexit.register(cleanup)

    try:
        # 1. 清空之前的网络配置
        _native.API_Reset_Prepare()

        # 2. 创建 IPC 服务端点，公布地址与监听地址一致
        _native.API_Prepare_Service(b"ipc:cross", b"ipc:cross")

        # 3. 启动 C4 网络框架，阻塞直到服务就绪
        if _native.API_Prepare_Done() != 1:
            print("[ERROR] prepareDone() failed. Check console output for details.")
            return

        print("[OK] Service registry ready on ipc:cross")
        print("[INFO] Press Enter to stop the service...")

        # 4. 阻塞等待用户输入，保持服务运行
        input()

    except KeyboardInterrupt:
        print("\n[INFO] Interrupted by user.")
    except Exception as e:
        print(f"[FATAL] Unexpected error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        cleanup()
        print("[OK] Service shutdown complete.")


if __name__ == "__main__":
    main()