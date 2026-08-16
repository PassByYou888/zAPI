# 序列化通信技术指南：Call 与 Notify 的选型与实现

> **“数据有序到达，是分布式系统中最朴素也最棘手的需求之一。”**  
> 本文以 zAPI 框架下的 `Sequence_Serv` / `Sequence_Cli` 为例，深入剖析两种通信模式——**同步 Call** 与**单向 Notify**——在保证数据序列化（顺序）方面的差异、取舍与实现技巧。

---

## 1. 什么是“序列化通信”？

在分布式系统中，“序列化”在这里并非指数据编码（如 JSON、Protobuf），而是指**消息到达处理端的顺序与发送端发出的顺序一致**。

典型场景：
- 大文件分块上传（Block 0, Block 1, … Block N）
- 日志流按时间戳有序写入
- 视频帧的连续传输
- 分布式事务中的操作顺序

如果顺序错乱，可能导致文件损坏、逻辑错误或状态不一致。

---

## 2. 方案一：纯 Call 模式 —— 天然有序，但效率受限

### 🔹 原理
每个数据块通过**同步 Call**（请求-响应）发送，**只有前一个 Call 完成并收到响应后，才发送下一个 Call**。这意味着网络层天然保证消息的发送顺序与处理顺序一致。

```pascal
// 伪代码：纯 Call 方式发送文件块
for i := 0 to BlockCount - 1 do
begin
  Param := TDataHandle.Create('UploadBlock');
  Param.WriteInt64(i);
  Param.WriteBuffer(BlockData[i], BlockSize);
  Res := CallApp('FileService', Param, 5000);  // 同步等待
  // 检查 Res，确认服务端已处理完成
  Free(Param); Free(Res);
end;
```

### 🔹 优点
- **实现极其简单**：无需会话管理、无需序号、无需服务端排序。
- **顺序绝对可靠**：底层网络层（TCP）保证有序，且上层同步等待确保前一个已完成。
- **错误处理直观**：若某个块失败，可以立即重试或中止，不影响后续块。

### 🔹 缺点
- **吞吐量低**：每个块需要等待网络 RTT + 服务端处理时间，串行化严重。
- **资源利用率差**：客户端和服务端在等待期间闲置，无法充分利用并发。
- **不适合大块数据或高频小包**：延迟叠加效应明显。

---

## 3. 方案二：Notify 模式 + 序列化补偿机制 —— 高性能，但需自行维护顺序

### 🔹 原理
使用**单向 Notify**（即 fire-and-forget）发送数据块，发送方无需等待响应，可以**并发或连续**发送多个块。但 Notify 本身**不保证顺序**（因网络乱序、负载均衡、多线程处理），因此需要应用层自行设计**序列化补偿机制**。

典型补偿手段：
- **会话（Session）管理**：每个传输任务分配唯一 SessionID。
- **块序号（Index）**：每个数据块携带递增序号。
- **服务端收集与重排**：服务端按 SessionID 分组，按 Index 排序后顺序处理。

这正是 `Sequence_Serv` / `Sequence_Cli` 所做的。

```pascal
// 客户端：使用 Notify 发送块，无需等待
procedure SendBlock(SessionID: UInt64; Index: Int64; Data: Pointer; Size: Int64);
var
  Param: TDataHandle;
begin
  Param := TDataHandle.Create('Data');
  Param.WriteUInt64(SessionID);
  Param.WriteInt64(Index);
  Param.WriteBuffer(Data^, Size);
  NotifyApp('FileService', Param);   // 立即返回，不阻塞
  Param.Free;
end;

// 客户端循环发送所有块，不等待响应
for i := 0 to BlockCount - 1 do
  SendBlock(SessionID, i, BlockData[i], BlockSize);
NotifyApp('FileService', EndParam);  // 发送结束通知
```

### 🔹 优点
- **极高吞吐量**：发送方可以满速推送，无需等待。
- **充分利用并发**：多个块可并行传输（若采用多线程或异步IO）。
- **适合大文件/流式数据**：网络带宽利用率高。

### 🔹 缺点
- **实现复杂度高**：需要管理会话、序号、超时、重排、异常回收。
- **需处理乱序**：服务端必须缓存乱序到达的块，直到全部收齐。
- **需处理丢包/重复**：Notify 无确认，需应用层自行设计丢包检测（如超时重传）和去重。

---

## 4. 案例剖析：Sequence 示例的序列化实现

### 4.1 整体流程

```text
客户端 (Cli)                              服务端 (Serv)
   |                                           |
   |---- Call(BeginData) --------------------> |
   |<--- SessionID (UInt64) ------------------ |
   |                                           | 创建 TSequPool 对象
   |                                           | 注册到 Safe_Pointer 哈希表
   |---- Notify(Data, Index=0, Payload) -----> |
   |---- Notify(Data, Index=1, Payload) -----> |
   |---- Notify(Data, Index=2, Payload) -----> |
   |       ...                                 | 按 Index 存入列表
   |---- Notify(EndData, TotalCount=N) ------> |
   |                                           | 从 Safe_Pointer 移除
   |                                           | 后台线程等待所有块收齐
   |                                           | 按 Index 排序
   |                                           | 顺序处理（如计算 MD5）
   |                                           | 延迟释放 TSequPool
```

### 4.2 客户端关键代码（带注释）

- **开始会话**：同步 Call 获取 SessionID。
- **发送数据块**：使用 Notify，携带序号。
- **结束会话**：使用 Notify，携带总块数，**但不等待服务端处理完成**。

客户端不关心服务端何时处理完，只负责“投递”，这正是 Notify 的特点。

### 4.3 服务端关键实现

#### ① 会话管理：TSequPool
每个会话对应一个 `TSequPool` 对象，内部维护一个 `TBigList<TSequ_Data>`，用于存储收到的块（无序）。

#### ② 安全指针池：Safe_Pointer
```pascal
Safe_Pointer := TSequPool_Safe_Pointer.Create($FF, nil);
```
- 以 `SessionID`（即 `TSequPool` 对象的指针值）为键，存储对象引用。
- 所有 `Data` 和 `EndData` 回调首先检查该 ID 是否存在于池中，防止伪造指针。

#### ③ 数据接收：Data 回调
```pascal
procedure Data_Notify(Trigger: Pointer; Input: TDataHnd);
var
  u64: UInt64;
  dataQueue: TSequPool;
begin
  // 1. 读取 SessionID 和 Index
  // 2. 检查 Safe_Pointer 是否存在
  // 3. 将数据块插入到 TSequPool 中
  dataQueue.Add_Null.Data.index := Index;
  dataQueue.Add_Null.Data.Mem := TMem64.Create;
  dataQueue.Add_Null.Data.Mem.WritePtr(数据指针, 数据大小);
  dataQueue.FLast_Update := GetTimeTick();  // 更新活跃时间
end;
```

#### ④ 结束与后台处理：EndData 回调
```pascal
procedure EndData_Notify(...);
begin
  // 1. 读取 SessionID 和 TotalCount
  // 2. 从 Safe_Pointer 中删除该键（此后该会话不再接受新块）
  Safe_Pointer.Delete(u64);
  // 3. 设置 TotalCount，触发后台线程
  dataQueue.FMax_recv_Num := TotalCount;
  TCompute.RunM_NP(dataQueue.Sequence_End);   // 异步处理
end;
```

#### ⑤ 后台处理：Sequence_End
```pascal
procedure TSequPool.Sequence_End;
begin
  // 1. 忙等待直到 Count >= TotalCount
  repeat Lock; all_done := num >= FMax_recv_Num; UnLock; Sleep(10); until all_done;
  // 2. 按 Index 排序
  Sort_M(DoSortSequ);
  // 3. 顺序处理所有块（此处示例为计算整体 MD5）
  m5tool := TMD5_Tool.Create;
  for each block in list do m5tool.Update(block.Mem);
  DoStatus('最终指纹: %s', [umlMD5ToStr(m5tool.FinalizeMD5).Text]);
  // 4. 延迟释放自身
  DelayFreeObj(5.0, Self);
end;
```

#### ⑥ 超时回收：Fixed_Lose_SequPool（定时器调用）
```pascal
procedure Fixed_Lose_SequPool;
begin
  // 扫描 Safe_Pointer，若某个 Session 的 FLast_Update 距今 > 5s
  // 则认为客户端已断开，强制删除并释放 TSequPool
  // 防止僵尸会话占用内存
end;
```

---

## 5. 野指针防护与资源回收（安全设计要点）

在使用指针值作为 SessionID 时，**必须严格防范野指针攻击**：

- **注册与校验**：服务端仅在 `BeginData` 时注册有效 ID，后续所有操作必须先校验存在性。
- **立即注销**：`EndData` 后立即从哈希表中删除，后续即使收到该 ID 的数据也会被拒绝。
- **自动超时回收**：若客户端未发送 `EndData`（如崩溃），定时器会回收超时会话，避免内存泄漏。

这套机制保障了系统的健壮性，即使面对恶意或异常客户端也不会崩溃。

---

## 6. 选型建议：何时用 Call，何时用 Notify + 序列化补偿？

| 场景特征 | 推荐方案 | 理由 |
|---------|---------|------|
| 数据块数量少（< 100） | **Call** | 实现简单，顺序天然保证，延迟可接受 |
| 数据块数量多，但要求严格按序处理 | **Call**（若性能允许）或 **Notify + 补偿** | 若并发要求高，则使用 Notify 方案 |
| 数据块数量巨大（如文件传输） | **Notify + 补偿** | 高吞吐，充分利用网络带宽 |
| 需要实时反馈每个块的处理状态 | **Call** | 每个 Call 的响应可携带状态码 |
| 允许最终一致性，可接受短暂乱序 | **Notify + 补偿** | 客户端无需等待，服务端异步重排 |

**经验法则：**  
- 若业务逻辑简单、数据量小、对延迟不敏感 → 直接用 Call，省心。  
- 若追求极致性能、数据量大、网络环境良好 → 选用 Notify 并实现 Session + Index 机制。

---

## 7. 总结

- **Call 模式**：以“串行化”换“顺序”，简单可靠，适合低并发、小数据场景。
- **Notify 模式**：以“应用层补偿”换“高性能”，适合大吞吐、流式场景。
- **序列化补偿的核心四要素**：
  1. **SessionID**：区分不同传输任务。
  2. **Index**：标记块内序号。
  3. **服务端缓存与排序**：等待全部收齐后按 Index 处理。
  4. **超时与野指针防护**：保证系统健壮性。

`Sequence_Serv` / `Sequence_Cli` 是一个标准、可复用的样板，你只需替换业务处理逻辑（如 MD5 计算改为文件写入），即可实现任意大数据的可靠有序传输。

---

**附：如果追求更高的可靠性**，可在 Notify 基础上增加客户端超时重传机制（例如，定期检查服务端是否已确认所有块），但这会进一步增加复杂度。在大多数局域网或稳定网络环境下，Notify + 超时回收已足够。

---

## 📚 相关资源（其他语言指南）

- [API Hub Tool C++ 使用指南](../../C++/API%20Hub%20Tool%20C++%20使用指南.md)
- [API Hub Tool C 语言使用指南](../../C++/API%20Hub%20Tool%20C%20语言使用指南.md)
- [从零到一，掌握多语言互调](../../Py/从零到一，掌握多语言互调.md)
- [API Hub for Go 从零到一掌握多语言互调](../../Go/API%20Hub%20for%20Go%20从零到一掌握多语言互调.md)
- [zAPI Rust 使用指南](../../rust/zAPI%20Rust%20使用指南.md)
- [API Hub Java 使用指南](../../java/API%20Hub%20Java%20使用指南.md)
- [API Hub Tool for C# — 完整使用指南](../../C%23/API%20Hub%20Tool%20for%20C%23%20—%20完整使用指南.md)
- [API Hub Tool for Pascal](../API%20Hub%20Tool%20for%20Pascal.md)
- [Node.js 跨语言调用方案选型：为什么我们选择 Python 网关而非 npm 原生包](../../node/Node.js%20跨语言调用方案选型：为什么我们选择%20Python%20网关而非%20npm%20原生包.md)
- [老哥别卷了,你的 VB.NET 代码今天开始全栈通杀](../../VB.NET/老哥别卷了,%20你的%20VB.NET%20代码今天开始全栈通杀.md)
- [浏览器调用 C++ 的三种方案对比：为什么我们选择了 zAPI 网关](../../Py/web/浏览器调用%20C++%20的三种方案对比：为什么我们选择了%20zAPI%20网关.md)
- [js_api.py 使用指南](../../Py/web/js_api.py%20使用指南.md)
- [📖 ZAPI Bridge 完整使用手册](../../Py/bridge/📖%20ZAPI%20Bridge%20完整使用手册.md)
