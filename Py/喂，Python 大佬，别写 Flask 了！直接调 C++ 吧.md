# 🐍 喂，Python 大佬，别写 Flask 了！直接调 C++ 吧！

> 以前你要调个 C++ 库：`subprocess` + 解析 stdout，或者写个 Cython 编译到怀疑人生。现在？**把 `api_hub` 文件夹放进项目，然后 `@expose` 一下**，完事儿。
>
> **版本**：2.0（与 ZAPI Bridge v2.0 同步）

## 讲道理，这玩意儿解决了啥大问题？
你在 Jupyter Notebook 里训练了个 PyTorch 模型，想把它部署成服务。以前你要：
1. 写个 `app.py` 挂 Flask。
2. 处理 JSON 序列化。
3. 担心 GIL 锁。
4. 被 Go 的同事吐槽"你的接口响应太慢了"。

现在你用 zAPI：

```python
from api_hub import Server

app = Server("PyTorchModel")

@app.expose("predict")
def predict(data: list) -> float:
    return model.predict(data).item()

app.start("ipc:ai_service")  # 就这一行，你的模型变成微服务了！
```

然后，你的 C++ 同事、Go 同事、甚至写单片机 C 的同事，都能直接调用你的 `predict` 函数。**这就叫"降维打击"**。

> **v2.0 新特性：** 现在不仅 C++/Go 能调，PHP 和 Node.js 也能通过 [ZAPI Bridge](../bridge/📖%20ZAPI%20Bridge%20完整使用手册.md) 调用你的 Python 服务了。

## 别废话，快不快？
- **IPC 调用**：延迟 0.8 毫秒，比你 `print()` 一下还快。
- **序列化**：默认支持 JSON 和 Pickle，你要是高兴，传个 numpy 数组进去也行。
- **吞吐量**：单核轻松 3000+ QPS，比 Flask + Gunicorn 不知道高到哪里去了。

## Python 特有的甜头
### 🍬 装饰器式注册
不用写繁琐的 `register_call` 回调，一个 `@expose` 搞定所有。函数签名是什么，远程调用的接口就是什么。

### 🍬 自动类型转换
你传 `int`，对方收到 `int`。你传 `dict`，对方收到 JSON 对象。底层二进制协议帮你打理好一切。

### 🍬 热更新支持（动态注销）
修改完 Python 逻辑后，如果想不重启服务就切换新版本，可以通过 `app.unregister('predict')` 注销旧 API，再注册新 API。客户端会自动感知（约 3 秒传播延迟），从而实现**不停服热更新**。当然，如果只是修改了函数内部实现而保持 API 签名不变，则无需重新注册，直接重启服务进程即可。

### 🍬 多语言客户端无需编写代码（v2.0 新增）
你的 Python 服务注册后，C++、Go、Rust、Java、C#、PHP、Node.js 客户端都能直接调用——**这些语言的绑定库已经为你准备好了所有调用逻辑，你只需要传入参数即可**。

## 那些让你头大的坑（过来人血泪）
- **回调别阻塞**：你的 `predict` 函数如果跑太久（比如 > 100ms），记得用 `asyncio.to_thread` 丢到线程池，不然会卡住 C4 的线程池，导致其他请求超时。**别问我是怎么知道的。**
- **IPC 地址不要带空格**：`ipc:ai service` 这种写法会报错，用下划线 `ipc:ai_service`。
- **DataHandle 记得释放**：虽然 Python 有 GC，但高并发下建议显式 `h.free()`，避免内存积压。
- **动态注销记得用**：如果服务要热更新，先 `app.unregister('predict')` 再重新注册，客户端会自动感知（约 3 秒传播）。

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../../pascal/API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
- [ZAPI 桥接开发踩坑记录](bridge/ZAPI%20桥接开发踩坑记录.md)

## 总结
> **"以前是 Python 调一切（慢），现在是一切调 Python（快）。"**

zAPI 让 Python 从"胶水语言"升级为"核心服务语言"。你的模型、算法、数据处理逻辑，都能成为整个分布式系统的第一等公民。现在就去试试吧，你的 C++ 同事会感谢你的。
