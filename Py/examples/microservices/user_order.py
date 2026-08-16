#!/usr/bin/env python
# -*- coding: utf-8 -*-
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from api_hub import Server

print("此示例需要分别启动 UserService 和 OrderService 两个进程。")
print("请参考文档分别运行两个服务，本脚本仅作代码展示。")
