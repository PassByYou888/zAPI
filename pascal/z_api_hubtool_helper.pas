{******************************************************************************
  z_api_hubtool_helper – 高性能 Pascal RAII 封装 (v2.5.0)
  ═══════════════════════════════════════════════════════════════════════════════
  本单元基于 z_api_hubtool_import 提供面向对象的 RAII 包装，
  自动管理 TDataHnd 和 TAppHnd 的生命周期，避免手动释放。

  ═══════════════════════════════════════════════════════════════════════════════
  设计哲学（AI 必读）
  ═══════════════════════════════════════════════════════════════════════════════
  1.  RAII 资源管理
      • TDataHandle 和 TAppHandle 在构造时自动创建底层句柄，
        析构时自动释放，杜绝内存泄漏。
      • 支持所有权转移（通过构造参数 Owned）和借用（不释放）。

  2.  无异常设计（静默失败）
      • 所有方法均不抛出异常。操作失败时：
        - 数值类型返回 0（或 0.0）
        - 字符串返回 ''
        - 布尔返回 False
      • 这使得代码无需 try..except 包裹，适合高频调用场景。

  3.  线程安全
      • TDataHandle 内部使用 TCriticalSection 保护所有读写操作，
        同一实例可安全并发调用。
      • TAppHandle 为无锁设计（底层函数本身线程安全）。

  4.  字符串协议
      • 所有字符串写入/读取采用 UTF‑8 + 空终止符 (#0)，
        与 z_api_hubtool_import 完全一致。
      • 提供 WriteStringNullTerminated 和 ReadStringNullTerminated
        方法，明确体现协议。

  5.  对象方法回调支持
      • TAppHandle.RegisterCall(OnCall: TAPI_Call_M) 允许直接注册
        对象方法，内部通过桥接函数适配为 cdecl 回调。
      • 同时提供 RegisterCallSync / RegisterNotifySync 版本，
        将回调同步到主线程（需定期调用 API.Sync）。

  6.  与底层 import 的关系
      • 所有方法最终调用 z_api_hubtool_import 中的 external 函数。
      • 静态类 API__ 直接映射所有 import 函数，供高级用户使用。

  ═══════════════════════════════════════════════════════════════════════════════
  使用场景（AI 翻译提示）
  ═══════════════════════════════════════════════════════════════════════════════
  • 编写跨语言服务端：使用 TAppHandle 注册 API，通过 API.PrepareService
    和 API.PrepareClient 启动网络。
  • 编写客户端：使用 TDataHandle 构造请求，调用 API.CallApp 或
    API.NotifyApp 远程调用。
  • 本地测试：使用 TAppHandle.LocalCall 和 LocalNotify 验证逻辑。
  • 热更新：使用 TAppHandle.Unregister 动态移除 API。

  AI 注意：本单元是 Pascal 特有的 RAII 封装，其他语言无需移植这些类，
  但应参考其设计模式提供类似的资源管理方式（如 C++ RAII、Python
  上下文管理器、C# using 等）。
******************************************************************************}

unit z_api_hubtool_helper;

{$ifdef FPC}
  {$mode delphi}{$H+}
  {$modeswitch advancedrecords}
  {$CODEPAGE UTF8}
  {$packrecords c}
  {$PACKENUM 4}
{$endif}

{$R-}
{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  z_api_hubtool_import;

type
  TCritical = TCriticalSection;

{=============================================================================
  API 容器类（高级 RAII 封装，无异常）
  提供静态方法管理网络层和全局操作，同时包含嵌套的 RAII 类。
=============================================================================}

  API = class
  public
    type
      {************************************************************************
        TDataHandle – 数据句柄 RAII 包装器（线程安全，无异常）
        ═════════════════════════════════════════════════════════════════════════
        封装 TDataHnd，自动管理内存。
        所有读写方法内部加锁，可安全并发调用。

        创建：
          • Create(const APIName: string) – 新建句柄，绑定 API 名称。
          • Create(AHandle: TDataHnd; Owned: boolean = True) – 包装已有句柄，
            若 Owned=True 则析构时释放。

        释放：
          析构函数自动释放（若 Owned）。

        位置与大小：
          • GetPos / SetPos – 读写位置（字节偏移）。
          • GetSize / SetSize – 缓冲区总大小。

        原始读写：
          • WriteBuffer / ReadBuffer – 任意二进制数据。

        类型安全读写：
          • WriteInt8/WriteUInt8/... – 写入基本类型（小端序）。
          • ReadInt8/ReadUInt8/... – 读取基本类型（有 out 和直接返回版本）。
          • WriteStringNullTerminated / ReadStringNullTerminated –
            UTF‑8 字符串 + #0 终止符（跨语言标准）。

        零拷贝访问：
          • GetBufferEx – 返回内部指针及大小（慎用）。

        线程安全：是（实例内部锁）。
        AI 翻译提示：其他语言应提供类似的 RAII 包装类（如 C++ unique_ptr，
        Python with 语句）。
      ************************************************************************}
      TDataHandle = class
      private
        FHandle: TDataHnd;
        FOwned: boolean;
        FDisposed: boolean;
        FLock: TCritical;
        function IsValid: boolean; inline;
      public
        { 创建一个新的数据句柄，绑定 API 名称。
          @param APIName API 名称（UTF‑8 字符串，会自动转换为 #0 终止）
          @note 析构时自动释放句柄。
          示例：
            var h: TDataHandle;
            h := TDataHandle.Create('add');
            h.WriteInt32(5).WriteInt32(7);
            // 离开作用域时自动释放
        }
        constructor Create(const APIName: string); overload;

        { 包装一个已有的句柄。
          @param AHandle 已存在的句柄
          @param Owned 是否拥有所有权，若为 True 则析构时释放该句柄
          注意：若 Owned=False，调用者需自行释放原句柄。
        }
        constructor Create(AHandle: TDataHnd; const Owned: boolean = False); overload;

        destructor Destroy; override;

        // ---- 原始字节读写（返回实际读写字节数，失败返回 0） ----
        { 向缓冲区写入原始字节（从当前位置开始）。
          @param Buffer 源数据（任何类型）
          @param Size 要写入的字节数
          @return 实际写入的字节数，失败返回 0
          注意：缓冲区自动扩容，位置自动后移。
        }
        function WriteBuffer(const Buffer; Size: int64): int64;

        { 从当前位置读取原始字节到调用者缓冲区。
          @param Buffer 目标缓冲区（任何类型）
          @param Size 要读取的最大字节数
          @return 实际读取的字节数，失败返回 0
        }
        function ReadBuffer(var Buffer; Size: int64): int64;

        // ---- 类型安全的写方法（链式调用，失败静默） ----
        { 写入 8 位有符号整数，返回 Self 以便链式调用。
          若操作失败，静默忽略（但仍返回 Self）。
        }
        function WriteInt8(Value: int8): TDataHandle;
        function WriteUInt8(Value: uint8): TDataHandle;
        function WriteInt16(Value: int16): TDataHandle;
        function WriteUInt16(Value: uint16): TDataHandle;
        function WriteInt32(Value: int32): TDataHandle;
        function WriteUInt32(Value: uint32): TDataHandle;
        function WriteInt64(Value: int64): TDataHandle;
        function WriteUInt64(Value: uint64): TDataHandle;
        function WriteSingle(Value: single): TDataHandle;
        function WriteDouble(Value: double): TDataHandle;

        { 写入 UTF‑8 字符串并追加 #0 终止符。
          @param Value Pascal 字符串（自动转 UTF‑8）
          @return Self（链式调用）
          注意：空字符串只写入一个 #0。
          这是跨语言标准字符串协议。
        }
        function WriteStringNullTerminated(const Value: string): TDataHandle;

        { 已弃用，请使用 WriteStringNullTerminated }
        procedure WriteString(const Value: string); deprecated 'Use WriteStringNullTerminated instead';

        // ---- 类型安全的读方法（var 参数，返回 Boolean） ----
        { 读取 8 位有符号整数，若成功返回 True，否则 False。
          @param Value 输出变量
        }
        function ReadInt8(var Value: int8): boolean; overload;
        function ReadUInt8(var Value: uint8): boolean; overload;
        function ReadInt16(var Value: int16): boolean; overload;
        function ReadUInt16(var Value: uint16): boolean; overload;
        function ReadInt32(var Value: int32): boolean; overload;
        function ReadUInt32(var Value: uint32): boolean; overload;
        function ReadInt64(var Value: int64): boolean; overload;
        function ReadUInt64(var Value: uint64): boolean; overload;
        function ReadSingle(var Value: single): boolean; overload;
        function ReadDouble(var Value: double): boolean; overload;

        // ---- 类型安全的读方法（直接返回值，失败返回 0 / 0.0） ----
        { 直接读取 8 位有符号整数，失败返回 0。 }
        function ReadInt8: int8; overload;
        function ReadUInt8: uint8; overload;
        function ReadInt16: int16; overload;
        function ReadUInt16: uint16; overload;
        function ReadInt32: int32; overload;
        function ReadUInt32: uint32; overload;
        function ReadInt64: int64; overload;
        function ReadUInt64: uint64; overload;
        function ReadSingle: single; overload;
        function ReadDouble: double; overload;

        // ---- 字符串读取（#0 终止，失败返回空字符串） ----
        { 从当前位置读取一个 UTF‑8 字符串，直到遇到 #0 终止符。
          成功返回字符串，失败返回空字符串。
          注意：位置会移动到终止符之后。若缓冲区无 #0，则返回空字符串。
        }
        function ReadStringNullTerminated: string;

        { 已弃用，请使用 ReadStringNullTerminated: string }
        function ReadString(out Value: string): boolean; overload;
        function ReadString(): string; overload;

        // ---- 位置与大小 ----
        { 获取当前读写位置（字节偏移，从 0 开始） }
        function GetPos: int64;
        { 设置当前读写位置，若超出大小则扩展缓冲区并填充 0 }
        procedure SetPos(Pos_: int64);
        property Pos: int64 read GetPos write SetPos;

        { 获取缓冲区总大小（字节） }
        function GetSize: int64;
        { 调整缓冲区大小（截断或扩展） }
        procedure SetSize(Size_: int64);
        property Size: int64 read GetSize write SetSize;

        // ---- 直接缓冲区访问（慎用） ----
        { 返回内部缓冲区指针及当前大小，用于高性能零拷贝访问。
          调用者不要释放返回的指针，且需确保句柄有效期间内不重新分配大小。
          @param Size 返回当前缓冲区大小
          @return 缓冲区首地址，若无效则返回 nil
        }
        function GetBufferEx(out Size: int64): Pointer;
        function GetBuffer(): Pointer;

        { 原始句柄（只读） }
        property Handle: TDataHnd read FHandle;
      end;

      {************************************************************************
        TAppHandle – 应用句柄 RAII 包装器（无异常）
        ═════════════════════════════════════════════════════════════════════════
        封装 TAppHnd，自动管理应用生命周期。
        提供注册 Call/Notify API、本地调用、动态注销功能。

        创建：
          Create(const AppName, Desc: string) – 新建应用。

        注册 API：
          • RegisterCall(APIName, Desc, Trigger, OnCall: TAPI_Call) – 函数指针版本。
          • RegisterCall(APIName, Desc, OnCall: TAPI_Call_M) – 对象方法版本（非同步）。
          • RegisterCallSync(APIName, Desc, OnCall: TAPI_Call_M) – 对象方法版本（同步到主线程）。
          • RegisterNotify 系列同理。

        注销：
          Unregister(APIName) – 动态移除 API。

        本地调用：
          LocalCall(Param) – 本地同步执行 Call。
          LocalNotify(Param) – 本地发送通知。

        属性：
          Handle – 原始 TAppHnd。
          Name – 应用名。

        线程安全：底层函数线程安全，本类无额外锁。
        AI 翻译提示：其他语言应提供类似的应用句柄封装，但注意对象方法
        回调桥接是 Pascal 特有的，其他语言可直接使用函数指针/委托。
      ************************************************************************}
      TAppHandle = class
      private
        FHandle: TAppHnd;
        FName: string;
      public
        { 创建应用句柄。
          @param AppName 应用名称（网络唯一，区分大小写）
          @param Desc 描述信息（可为空）
          示例：
            var app: TAppHandle;
            app := TAppHandle.Create('MyService', 'My service');
        }
        constructor Create(const AppName, Desc: string);
        destructor Destroy; override;

        // ---- 注册 Call（函数指针） ----
        { 注册一个请求-响应 API，使用传统 cdecl 函数指针。
          @param APIName API 名称（应用内唯一）
          @param Desc 描述信息
          @param Trigger 用户数据，回调时原样传回
          @param OnCall 回调函数指针（TAPI_Call 类型，必须 cdecl）
          @return True 成功，False 失败（名称重复）
          注意：回调运行在 C 线程池，不可阻塞，不可调用 API_Call/Notify
          示例：
            procedure MyAdd(Trigger: Pointer; Input, Output: TDataHnd); cdecl;
            begin ... end;
            app.RegisterCall('add', 'Addition', nil, @MyAdd);
        }
        function RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): boolean; overload;

        // ---- 注册 Call（对象方法，非同步） ----
        { 注册对象方法版本的 Call API（内部自动适配为 cdecl）。
          @param APIName API 名称
          @param Desc 描述
          @param OnCall 对象方法（TAPI_Call_M 类型）
          @return True 成功，False 失败
          注意：对象方法直接在 C 线程池中执行，不要阻塞。
          示例：
            procedure TMyClass.MyAdd(Input, Output: TDataHnd);
            begin ... end;
            app.RegisterCall('add', 'Addition', MyAdd);
        }
        function RegisterCall(const APIName, Desc: string; OnCall: TAPI_Call_M): boolean; overload;

        // ---- 注册 Call（对象方法，同步到主线程） ----
        { 注册对象方法版本的 Call API，并将回调同步到主线程执行。
          注意：需要在主线程中定期调用 API.Sync 以处理队列。
          仅用于特殊场景（如需要访问主线程 UI 等）。
        }
        function RegisterCallSync(const APIName, Desc: string; OnCall: TAPI_Call_M): boolean;

        // ---- 注册 Notify（函数指针） ----
        function RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): boolean; overload;

        // ---- 注册 Notify（对象方法，非同步） ----
        function RegisterNotify(const APIName, Desc: string; OnNotify: TAPI_Notify_M): boolean; overload;

        // ---- 注册 Notify（对象方法，同步到主线程） ----
        function RegisterNotifySync(const APIName, Desc: string; OnNotify: TAPI_Notify_M): boolean;

        // ---- 动态注销 ----
        { 动态注销已注册的 API。
          @param APIName API 名称
          @return True 成功移除，False 名称不存在
          注意：本地立即生效，网络广播约需 3 秒传播。
        }
        function Unregister(const APIName: string): boolean;

        // ---- 本地调用 ----
        { 在本地同步执行 Call API（不经过网络）。
          @param Param 输入数据句柄
          @return 新 TDataHandle 包含结果（需释放），若失败则返回空句柄
        }
        function LocalCall(Param: TDataHandle): TDataHandle;

        { 在本地发送通知（无返回）。 }
        procedure LocalNotify(Param: TDataHandle);

        property Handle: TAppHnd read FHandle;
        property Name: string read FName;
      end;

  public
    // ----- 静态方法（网络和全局操作）-----
    { 清除所有已准备的网络配置（服务/客户端）。 }
    class procedure ResetPrepare;

    { 准备一个服务监听器（可多次调用）。
      @param ListeningAddr 本地绑定地址（如 '0.0.0.0:9898' 或 'ipc:my_service'）
      @param PhysicsAddr 对外公布的地址（客户端连接时使用）
      @return 内部标签（可忽略）
      示例：
        API.PrepareService('0.0.0.0', '127.0.0.1:9898');
        API.PrepareService('ipc:demo', 'ipc:demo');

      调用时机与行为：
        • 在调用 API_Prepare_Done 之前调用：该服务会被加入准备队列，
          等到 API_Prepare_Done 启动时统一创建并开始监听。
        • 在 API_Prepare_Done 已经执行且主线程（C4 事件循环）已启动之后调用：
          该服务会立即被创建并开始监听，无需重启框架或再次调用
          API_Prepare_Done。这允许在运行时动态添加新的服务实例，
          实现热扩展。
    }
    class function PrepareService(const ListeningAddr, PhysicsAddr: string): integer; overload;

    { 准备服务并自动准备客户端（方便快速部署）。
      @param ListeningAddr 服务监听地址
      @param PhysicsAddr 公布的地址
      @param App 要暴露的应用句柄
      @return 内部标签
    }
    class function PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): integer; overload;

    { 准备一个客户端连接。
      @param PhysicsAddr 远程服务地址
      @param App 可选应用句柄（若提供则暴露该应用，否则纯消费）
      @return 内部标签

      调用时机与行为：
        • 在调用 API_Prepare_Done 之前调用：该客户端会被加入准备队列，
          等到 API_Prepare_Done 启动时统一建立连接并注册应用（如果有）。
        • 在 API_Prepare_Done 已经执行且主线程（C4 事件循环）已启动之后调用：
          该客户端会立即尝试连接远程服务，并自动注册应用（如果有）。
          这允许在运行时动态添加新的客户端连接，实现热扩展。
    }
    class function PrepareClient(const PhysicsAddr: string; App: TAppHandle): integer;

    { 启动网络框架，阻塞直到所有准备的服务/客户端就绪。

    调用行为：
      • 当主线程尚未启动时：启动模拟主线程（C4 事件循环），并等待所有准备
        的服务/客户端就绪（取决于 Wait_Connection_ReadyOk 设置）。
      • 当主线程已经启动时（即框架已在运行）：再次调用此函数会立即返回 1
        （不做任何操作），不会产生副作用。
      • 在调用 API_shutdown 之后，框架被完全关闭，此时可以再次调用
        API_Prepare_Done 重新启动框架（需先调用 API_Reset_Prepare 重新配置）。

    设计意图：
      启动网络框架，使远程调用功能可用。

    注意事项：
      • 只能有效启动一次（除非在 shutdown 后重新准备）。
      • 可通过 API_SetOption 控制是否等待客户端就绪（Wait_Connection_ReadyOk）。
      • 该函数只在初始化时生效，选项修改仅在调用前有效。
      • 在应用程序或动态库退出前，必须调用 API_shutdown 释放资源，否则可能导致
        资源泄漏或进程无法正常退出。

      @return True 成功，False 失败（错误信息会打印到控制台）
    }
    class function PrepareDone: boolean;

    { 停止内部事件循环（网络处理）。
      通常与 Shutdown 配合使用。
    }
    class procedure ExitMainThread;

    { 同步远程调用（或本地优化）。
      @param AppName 目标应用名
      @param Param 输入数据句柄（内部克隆，调用者仍负责释放原句柄）
      @param TimeoutMs 超时毫秒数，0 表示无限等待
      @return 新 TDataHandle 包含结果（必须释放），失败时大小为 0
      注意：返回的句柄即使大小为 0 也必须释放。
    }
    class function CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: uint64): TDataHandle;

    { 单向通知（fire-and-forget）。
      @param AppName 目标应用名
      @param Param 输入句柄
    }
    class procedure NotifyApp(const AppName: string; Param: TDataHandle);

    { 动态调整全局配置（与 API_SetOption 等价）。
      @param Option 配置键
      @param Value 新值
      示例：
        API.SetOption('Wait_Connection_ReadyOk', 'False');
        API.SetOption('IPC_Serv_ThreadCount', '8');
    }
    class procedure SetOption(const Option, Value: string);

    { 处理主线程同步队列（用于同步回调）。
      @return 处理的任务数
      主线程应定期调用此函数（如主循环中）。
    }
    class function Sync: integer;

    { 完全关闭框架，释放所有资源。
      调用行为：
        • 如果框架正在运行，会首先停止主线程（相当于调用 API_Exit_MainThread），
          然后释放所有内部资源（网络连接、线程池、内存等）。
        • 如果框架已经停止，再次调用此函数无任何效果，直接返回。
        • 该函数可以安全地多次调用。

      设计意图：
        清理所有资源，使框架恢复到未初始化的状态。之后可以重新调用
        API_Reset_Prepare 和 API_Prepare_Done 重新启动。

      ⚠️ 重要：
        在应用程序退出（或动态库卸载）之前，必须调用此函数！
        否则可能导致：
          • 资源泄漏（内存、套接字、线程等）
          • 进程无法正常退出（线程未终止）
          • 动态库卸载时崩溃（未清理的全局对象）

      建议顺序：
        先调用 API_Exit_MainThread（可选，因为 shutdown 内部会调用），
        然后调用 API_shutdown。
    }
    class procedure Shutdown;

    // ----- 新增的全局辅助函数（与 import 同步）-----
    { 获取状态队列中的下一条日志消息（自动转换为 Pascal string）。
      @return 日志内容，若队列为空则返回空字符串。
      注意：内部自动复制数据，不受缓冲区覆盖影响。
    }
    class function GetStatus: string;
    class function Get_Status_Num: Integer;

    { 向状态队列写入一条自定义日志消息。
      @param Status 要写入的消息（Pascal string）
    }
    class procedure PostStatus(const Status: string);

    { 检查模拟主线程（C4 事件循环）是否正在运行。
      @return True 表示正在运行，False 表示已停止或未启动。
    }
    class function CheckMainThread: Boolean;

    { 检查网络中是否存在指定名称的应用（区分大小写）。
      @param AppName 应用名
      @return True 表示存在至少一个实例，False 表示不存在。
      注意：此函数基于本地缓存，不保证实时性。
      可以在线程里面使用, 也可以高频功率调用, 例如跑大型api的前置条件判断.
      可以支持 while CheckApp do Sleep(10) 这种高频率调用
    }
    class function CheckApp(const AppName: string): Boolean;
  end;

{=============================================================================
  API__ 容器类（底层 import 静态映射）
  ═════════════════════════════════════════════════════════════════════════════
  本类直接映射 z_api_hubtool_import 中的所有 external 函数和 Pascal 辅助函数，
  供需要绕过 RAII 封装的高级用户使用。
  所有方法均为 static，直接转发至 import 单元。

  ⚠️ 注意：常规开发应使用 API 容器类（API.TDataHandle / API.TAppHandle 等），
  它们提供自动资源管理和类型安全。仅当您需要完全控制句柄生命周期或
  直接调用底层 C 函数时，才使用本类。

  AI 翻译提示：本类是 Pascal 对 C 动态库函数的直接映射，其他语言
  的 FFI 绑定应参考本类中的函数签名，但无需移植这些 Pascal 静态方法。
=============================================================================}

  API__ = class
  public
    // ==================== 数据句柄操作 ====================
    {**************************************************************************
      【直接映射】API_Create_DataHnd
      功能：创建数据句柄，绑定 API 名称。
      参数：
        APIName : PAnsiChar – UTF‑8 编码、以 #0 结尾的 API 名称。
      返回：新 TDataHnd，正常情况永不返回 nil。
      设计意图：句柄创建后，API 名称固定，后续所有读写只影响载荷。
      关联：API_Free_DataHnd
      注意事项：名称被内部复制，调用后可立即释放原字符串。
      线程安全：是。
      AI 翻译提示：其他语言应直接 FFI 调用同名 C 函数，
                    并确保传入的字符串为 UTF‑8 + #0。
      示例：
        var d: TDataHnd;
        d := API__.API_Create_DataHnd('add');
        ...
        API__.API_Free_DataHnd(d);
    **************************************************************************}
    class function API_Create_DataHnd(APIName: pansichar): TDataHnd; static;

    {**************************************************************************
      【直接映射】API_Create_DataHnd2 – Pascal 便利重载，自动 UTF‑8 转换。
      仅供 Pascal 便利，其他语言无需实现。
    **************************************************************************}
    class function API_Create_DataHnd2(APIName: string): TDataHnd; static;

    {**************************************************************************
      【直接映射】API_Free_DataHnd
      功能：销毁数据句柄，释放内存。
      参数：Hnd : TDataHnd – 要释放的句柄，传 nil 无操作。
      线程安全：是，但释放后句柄不可再用。
      AI 翻译提示：其他语言应确保每个 Create 都有对应的 Free（或 RAII 自动释放）。
    **************************************************************************}
    class procedure API_Free_DataHnd(Hnd: TDataHnd); static;

    {**************************************************************************
      【直接映射】API_GetBuffer
      功能：返回内部缓冲区的直接指针（零拷贝访问）。
      参数：Hnd : TDataHnd – 数据句柄。
      返回：Pointer – 缓冲区起始地址，若无数据则返回 nil。
      设计意图：高性能场景下直接读写原始内存，避免复制。
      注意事项：
        • 指针有效期至句柄释放或调整大小。
        • 读写范围不得超过 API_GetSize 返回的大小。
        • 不要释放此指针。
      线程安全：读安全，写需串行化。
      AI 翻译提示：其他语言可通过 FFI 获取指针，然后用 Unsafe 操作访问。
    **************************************************************************}
    class function API_GetBuffer(Hnd: TDataHnd): Pointer; static;

    {**************************************************************************
      【直接映射】API_GetBuffer2 – Pascal 便利函数，返回带偏移的缓冲区指针。
    **************************************************************************}
    class function API_GetBuffer2(Hnd: TDataHnd; Offset: nativeint): Pointer; static;

    {**************************************************************************
      【直接映射】API_WriteBuffer
      功能：向句柄缓冲区写入原始字节（从当前位置开始）。
      参数：
        Hnd  : TDataHnd – 数据句柄。
        Buff : Pointer – 源数据指针。
        Size : int64   – 要写入的字节数。
      返回：实际写入字节数（通常等于 Size）。
      设计意图：底层字节写入，所有高级写入函数（如 WriteInt32）均基于此。
      注意事项：缓冲区自动扩容，位置自动后移。
      线程安全：同一句柄的写操作需串行化。
      AI 翻译提示：其他语言应直接调用同名 C 函数，传递字节数组指针。
    **************************************************************************}
    class function API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; static;

    {**************************************************************************
      【直接映射】API_ReadBuffer
      功能：从当前位置读取原始字节到调用者缓冲区。
      参数：
        Hnd  : TDataHnd – 数据句柄。
        Buff : Pointer – 目标缓冲区指针。
        Size : int64   – 最大读取字节数。
      返回：实际读取字节数（可能小于 Size，若到达缓冲区尾部）。
      设计意图：底层字节读取，与 WriteBuffer 对称。
      线程安全：同一句柄的读与写不可并发；多读可并发。
      AI 翻译提示：其他语言直接调用同名 C 函数。
    **************************************************************************}
    class function API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64; static;

    // ==================== 原子写入 ====================
    {**************************************************************************
      【直接映射】API_WriteInt8 – 写入有符号 8 位整数。
    **************************************************************************}
    class function API_WriteInt8(Hnd: TDataHnd; Value: int8): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteUInt8 – 写入无符号 8 位整数。
    **************************************************************************}
    class function API_WriteUInt8(Hnd: TDataHnd; Value: uint8): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteInt16 – 写入有符号 16 位整数（小端）。
    **************************************************************************}
    class function API_WriteInt16(Hnd: TDataHnd; Value: int16): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteUInt16 – 写入无符号 16 位整数（小端）。
    **************************************************************************}
    class function API_WriteUInt16(Hnd: TDataHnd; Value: uint16): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteInt32 – 写入有符号 32 位整数（小端）。
    **************************************************************************}
    class function API_WriteInt32(Hnd: TDataHnd; Value: int32): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteUInt32 – 写入无符号 32 位整数（小端）。
    **************************************************************************}
    class function API_WriteUInt32(Hnd: TDataHnd; Value: uint32): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteInt64 – 写入有符号 64 位整数（小端）。
    **************************************************************************}
    class function API_WriteInt64(Hnd: TDataHnd; Value: int64): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteUInt64 – 写入无符号 64 位整数（小端）。
    **************************************************************************}
    class function API_WriteUInt64(Hnd: TDataHnd; Value: uint64): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteSingle – 写入 32 位浮点数（小端 IEEE 754）。
    **************************************************************************}
    class function API_WriteSingle(Hnd: TDataHnd; Value: single): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteDouble – 写入 64 位浮点数（小端 IEEE 754）。
    **************************************************************************}
    class function API_WriteDouble(Hnd: TDataHnd; Value: double): boolean; static;
    {**************************************************************************
      【直接映射】API_WriteString – 写入 Pascal 字符串，自动转换为 UTF‑8 字节，
      并追加一个 #0 终止符。
      参数：
        Hnd   : TDataHnd – 数据句柄。
        Value : string   – Pascal 字符串（将按 UTF‑8 编码）。
      返回：Boolean – 写入成功（含终止符）返回 True。
      设计意图：统一跨语言字符串协议（UTF‑8 + #0）。
      注意事项：空字符串只写入一个 #0。
      线程安全：同一句柄写操作需串行。
      AI 翻译提示：其他语言应写入 UTF‑8 字节序列后显式追加一个 0 字节。
    **************************************************************************}
    class function API_WriteString(Hnd: TDataHnd; const Value: string): boolean; static;

    // ==================== 原子读取（out 版本） ====================
    {**************************************************************************
      【直接映射】API_ReadInt8 (out 版本) – 读取有符号 8 位整数。
    **************************************************************************}
    class function API_ReadInt8(Hnd: TDataHnd; out Value: int8): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt8 (out 版本) – 读取无符号 8 位整数。
    **************************************************************************}
    class function API_ReadUInt8(Hnd: TDataHnd; out Value: uint8): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt16 (out 版本) – 读取有符号 16 位整数（小端）。
    **************************************************************************}
    class function API_ReadInt16(Hnd: TDataHnd; out Value: int16): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt16 (out 版本) – 读取无符号 16 位整数（小端）。
    **************************************************************************}
    class function API_ReadUInt16(Hnd: TDataHnd; out Value: uint16): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt32 (out 版本) – 读取有符号 32 位整数（小端）。
    **************************************************************************}
    class function API_ReadInt32(Hnd: TDataHnd; out Value: int32): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt32 (out 版本) – 读取无符号 32 位整数（小端）。
    **************************************************************************}
    class function API_ReadUInt32(Hnd: TDataHnd; out Value: uint32): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt64 (out 版本) – 读取有符号 64 位整数（小端）。
    **************************************************************************}
    class function API_ReadInt64(Hnd: TDataHnd; out Value: int64): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt64 (out 版本) – 读取无符号 64 位整数（小端）。
    **************************************************************************}
    class function API_ReadUInt64(Hnd: TDataHnd; out Value: uint64): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadSingle (out 版本) – 读取 32 位浮点数（小端 IEEE 754）。
    **************************************************************************}
    class function API_ReadSingle(Hnd: TDataHnd; out Value: single): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadDouble (out 版本) – 读取 64 位浮点数（小端 IEEE 754）。
    **************************************************************************}
    class function API_ReadDouble(Hnd: TDataHnd; out Value: double): boolean; overload; static;

    // ==================== 原子读取（直接返回版本） ====================
    {**************************************************************************
      【直接映射】API_ReadInt8 (直接返回) – 读取有符号 8 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadInt8(Hnd: TDataHnd): int8; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt8 (直接返回) – 读取无符号 8 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadUInt8(Hnd: TDataHnd): uint8; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt16 (直接返回) – 读取有符号 16 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadInt16(Hnd: TDataHnd): int16; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt16 (直接返回) – 读取无符号 16 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadUInt16(Hnd: TDataHnd): uint16; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt32 (直接返回) – 读取有符号 32 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadInt32(Hnd: TDataHnd): int32; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt32 (直接返回) – 读取无符号 32 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadUInt32(Hnd: TDataHnd): uint32; overload; static;
    {**************************************************************************
      【直接映射】API_ReadInt64 (直接返回) – 读取有符号 64 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadInt64(Hnd: TDataHnd): int64; overload; static;
    {**************************************************************************
      【直接映射】API_ReadUInt64 (直接返回) – 读取无符号 64 位整数，失败返回 0。
    **************************************************************************}
    class function API_ReadUInt64(Hnd: TDataHnd): uint64; overload; static;
    {**************************************************************************
      【直接映射】API_ReadSingle (直接返回) – 读取 32 位浮点数，失败返回 0.0。
    **************************************************************************}
    class function API_ReadSingle(Hnd: TDataHnd): single; overload; static;
    {**************************************************************************
      【直接映射】API_ReadDouble (直接返回) – 读取 64 位浮点数，失败返回 0.0。
    **************************************************************************}
    class function API_ReadDouble(Hnd: TDataHnd): double; overload; static;
    {**************************************************************************
      【直接映射】API_ReadString (out 版本)
      功能：从当前位置读取 UTF‑8 字符串，直到遇到 #0 终止符。
      参数：
        Hnd   : TDataHnd – 数据句柄。
        out Value : string – 返回解码后的 Pascal 字符串。
      返回：Boolean – 成功读取到终止符返回 True，否则 False（Value 置空）。
      设计意图：与 WriteString 对称，实现跨语言字符串传输。
      注意事项：位置将移动到终止符之后。若缓冲区无 #0，则返回 False。
      线程安全：同一句柄读与写不可并发。
      AI 翻译提示：其他语言应实现“逐个字节扫描直到 0”的读取逻辑。
    **************************************************************************}
    class function API_ReadString(Hnd: TDataHnd; out Value: string): boolean; overload; static;
    {**************************************************************************
      【直接映射】API_ReadString (直接返回) – 读取字符串，失败返回空字符串。
    **************************************************************************}
    class function API_ReadString(Hnd: TDataHnd): string; overload; static;

    // ==================== 位置与大小 ====================
    {**************************************************************************
      【直接映射】API_GetPos – 获取当前读写位置（字节偏移，0‑起始）。
    **************************************************************************}
    class function API_GetPos(Hnd: TDataHnd): int64; static;
    {**************************************************************************
      【直接映射】API_SetPos – 设置读写位置，若超出大小则扩展缓冲区（填充零）。
    **************************************************************************}
    class procedure API_SetPos(Hnd: TDataHnd; Pos_: int64); static;
    {**************************************************************************
      【直接映射】API_GetSize – 获取缓冲区总大小（字节）。
    **************************************************************************}
    class function API_GetSize(Hnd: TDataHnd): int64; static;
    {**************************************************************************
      【直接映射】API_SetSize – 调整缓冲区大小（截断或扩展）。
    **************************************************************************}
    class procedure API_SetSize(Hnd: TDataHnd; Size_: int64); static;

    // ==================== 应用句柄操作 ====================
    {**************************************************************************
      【直接映射】API_Create_APPHnd
      功能：创建应用上下文。
      参数：
        appName : PAnsiChar – 应用名称（UTF‑8 + #0，区分大小写，网络唯一）。
        Desc    : PAnsiChar – 描述（UTF‑8 + #0，可为空）。
      返回：新 TAppHnd，正常情况下不返回 nil。
      设计意图：应用是 API 的容器，一个应用可注册多个 API。
      关联：API_Free_APPHnd
      线程安全：是。
      AI 翻译提示：其他语言直接调用 C 函数，应用名需全局唯一。
    **************************************************************************}
    class function API_Create_APPHnd(AppName, Desc: pansichar): TAppHnd; static;
    {**************************************************************************
      【直接映射】API_Create_APPHnd2 – Pascal 便利重载，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_Create_APPHnd2(AppName, Desc: string): TAppHnd; static;
    {**************************************************************************
      【直接映射】API_Free_APPHnd
      功能：销毁应用句柄，释放所有注册的 API 和资源。
      参数：appHnd : TAppHnd – 应用句柄。
      线程安全：是，但确保其他线程不再使用。
    **************************************************************************}
    class procedure API_Free_APPHnd(appHnd: TAppHnd); static;

    // ==================== 注册 Call ====================
    {**************************************************************************
      【直接映射】API_Reg_Call
      功能：在应用中注册一个请求-响应（Call）API。
      参数：
        appHnd   : TAppHnd – 应用句柄。
        APIName  : PAnsiChar – API 名称（UTF‑8 + #0，应用内唯一）。
        Desc     : PAnsiChar – 描述（UTF‑8 + #0，可选）。
        Trigger  : Pointer – 用户数据，回调时原样传回。
        OnCall   : TAPI_Call – 回调函数指针（cdecl）。
      返回：1 成功，0 失败（名称重复）。
      设计意图：暴露业务逻辑给远程调用者。
      线程安全：是。
      回调约束：见 TAPI_Call 说明。
      AI 翻译提示：其他语言使用对应的注册函数，并确保回调函数遵循 C ABI。
    **************************************************************************}
    class function API_Reg_Call(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnCall: TAPI_Call): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Call2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_Reg_Call2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Call_M – Pascal 辅助，注册对象方法（非同步）。
    **************************************************************************}
    class function API_Reg_Call_M(appHnd: TAppHnd; APIName, Desc: string; OnCall: TAPI_Call_M): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Sync_Call_M – Pascal 辅助，注册对象方法（同步到主线程）。
    **************************************************************************}
    class function API_Reg_Sync_Call_M(appHnd: TAppHnd; APIName, Desc: string; OnCall: TAPI_Call_M): integer; static;

    // ==================== 注册 Notify ====================
    {**************************************************************************
      【直接映射】API_Reg_Notify
      功能：注册单向通知（Notify）API。
      参数：同 API_Reg_Call，但回调类型为 TAPI_Notify（无输出）。
      返回：1 成功，0 失败。
      注意事项：回调中可调用 API_Notify，但应避免长时间执行。
      AI 翻译提示：其他语言使用对应的无返回值回调函数。
    **************************************************************************}
    class function API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnNotify: TAPI_Notify): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Notify2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_Reg_Notify2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Notify_M – Pascal 辅助，注册对象方法（非同步）。
    **************************************************************************}
    class function API_Reg_Notify_M(appHnd: TAppHnd; APIName, Desc: string; OnNotify: TAPI_Notify_M): integer; static;
    {**************************************************************************
      【直接映射】API_Reg_Sync_Notify_M – Pascal 辅助，注册对象方法（同步到主线程）。
    **************************************************************************}
    class function API_Reg_Sync_Notify_M(appHnd: TAppHnd; APIName, Desc: string; OnNotify: TAPI_Notify_M): integer; static;

    // ==================== 注销 ====================
    {**************************************************************************
      【直接映射】API_UnReg
      功能：动态注销已注册的 API。
      参数：
        appHnd   : TAppHnd – 应用句柄。
        APIName  : PAnsiChar – 要注销的 API 名称（UTF‑8 + #0）。
      返回：1 成功（API 存在并移除），0 失败（名称不存在）。
      设计意图：支持热更新、插件卸载、权限动态调整。
      注意事项：
        • 本地立即生效，后续本地调用将失败。
        • 网络广播异步传播，约 3 秒后所有对等节点不再路由该 API。
        • 正在执行中的回调不受影响（正常完成）。
      AI 翻译提示：其他语言应提供对应注销函数，并理解最终一致性延迟。
    **************************************************************************}
    class function API_UnReg(appHnd: TAppHnd; APIName: pansichar): integer; static;
    {**************************************************************************
      【直接映射】API_UnReg2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_UnReg2(appHnd: TAppHnd; APIName: string): integer; static;

    // ==================== 本地调用 ====================
    {**************************************************************************
      【直接映射】API_Local_APP_Call
      功能：在本地（同一进程）同步执行 Call API，绕过网络。
      参数：
        appHnd : TAppHnd – 应用句柄。
        Param  : TDataHnd – 输入句柄（包含 API 名称和参数）。
      返回：新 TDataHnd – 结果句柄（需释放）。若 API 未找到或出错，大小 = 0。
      设计意图：用于单元测试、调试或内部调用，无网络开销。
      注意事项：输入句柄不被释放，调用者需负责释放。
      线程安全：是。
      AI 翻译提示：其他语言应提供类似的本地调用方法，用于测试。
    **************************************************************************}
    class function API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd; static;
    {**************************************************************************
      【直接映射】API_Local_APP_Notify
      功能：本地发送通知，无结果。
      参数：同 API_Local_APP_Call，但无返回。
      线程安全：是。
    **************************************************************************}
    class procedure API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd); static;

    // ==================== 网络层 ====================
    {**************************************************************************
      【直接映射】API_Reset_Prepare
      功能：清除所有已准备的服务/客户端配置。
      设计意图：在重新配置前调用，避免旧配置干扰。
      线程安全：是。
    **************************************************************************}
    class procedure API_Reset_Prepare; static;

    {**************************************************************************
      【直接映射】API_Prepare_Service
      功能：准备一个服务监听器（可多次调用启动多个服务）。
      参数：
        ListeningAddr_ : PAnsiChar – 本地绑定地址（UTF‑8 + #0）。
                                      TCP 示例：'0.0.0.0:9898'
                                      IPC 示例：'ipc:my_service'
                                      若只给主机名（无端口），默认使用 9898。
        PhysicsAddr_   : PAnsiChar – 对外公布的地址（UTF‑8 + #0）。
                                      客户端必须使用此地址连接。
      返回：内部标签（可忽略）。
      设计意图：启动服务并广播自身存在，供服务发现。
      线程安全：是。
      AI 翻译提示：其他语言应提供等价方法，地址字符串需为 UTF‑8。
    **************************************************************************}
    class function API_Prepare_Service(ListeningAddr_, PhysicsAddr_: pansichar): integer; static;
    {**************************************************************************
      【直接映射】API_Prepare_Service2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_Prepare_Service2(ListeningAddr_, PhysicsAddr_: string): integer; static;

    {**************************************************************************
      【直接映射】API_Prepare_Client
      功能：准备一个客户端连接。
      参数：
        PhysicsAddr_ : PAnsiChar – 远程服务地址（必须与服务的公布地址一致）。
        appHnd       : TAppHnd – 可选应用句柄。若提供，客户端会将该应用注册
                                  到服务网格（暴露 API）；若为 nil，则纯消费。
      返回：内部标签。
      设计意图：建立连接并自动注册应用，支持断线重连。
      线程安全：是。
    **************************************************************************}
    class function API_Prepare_Client(PhysicsAddr_: pansichar; appHnd: TAppHnd): integer; static;
    {**************************************************************************
      【直接映射】API_Prepare_Client2 (带 appHnd) – Pascal 辅助。
    **************************************************************************}
    class function API_Prepare_Client2(PhysicsAddr_: string; appHnd: TAppHnd): integer; overload; static;
    {**************************************************************************
      【直接映射】API_Prepare_Client2 (不带 appHnd) – 纯消费客户端。
    **************************************************************************}
    class function API_Prepare_Client2(PhysicsAddr_: string): integer; overload; static;

    {**************************************************************************
      【直接映射】API_Prepare_Done
      功能：启动 C4 网络框架，阻塞直到所有准备的服务/客户端初始化完成。
      返回：1 成功，0 失败（错误信息会打印到控制台）。
      设计意图：调用后方可进行远程调用。
      注意事项：
        • 只能调用一次（除非重置）。
        • 可通过 API_SetOption 控制是否等待客户端就绪（Wait_Connection_ReadyOk）。
      线程安全：是，但建议主线程调用。
      AI 翻译提示：其他语言应提供等价的启动函数，通常阻塞。
    **************************************************************************}
    class function API_Prepare_Done: integer; static;

    {**************************************************************************
      【直接映射】API_Exit_MainThread
      功能：通知内部事件循环退出，停止网络处理。
      设计意图：优雅关闭的第一步，通常后接 API_shutdown。
      线程安全：是。
    **************************************************************************}
    class procedure API_Exit_MainThread; static;

    {**************************************************************************
      【直接映射】API_Call
      功能：同步远程调用（或本地优化）。
      参数：
        appName   : PAnsiChar – 目标应用名（UTF‑8 + #0）。
        Param     : TDataHnd – 输入句柄（内部克隆，调用者仍负责释放原句柄）。
        Timeout_  : UInt64 – 超时毫秒数，0 表示无限等待（慎用）。
      返回：新 TDataHnd – 结果句柄，永远非 nil。若超时或失败，大小 = 0。
      设计意图：主要 RPC 入口，自动路由、负载均衡、重试。
      注意事项：
        • 调用者必须释放返回的句柄（即使大小为 0）。
        • 在回调中调用此函数不会死锁，但需防死循环，且不可阻塞。
      线程安全：完全线程安全。
      AI 翻译提示：其他语言应提供同步调用方法，注意超时参数和句柄释放。
    **************************************************************************}
    class function API_Call(AppName: pansichar; Param: TDataHnd; Timeout_: uint64): TDataHnd; static;
    {**************************************************************************
      【直接映射】API_Call2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class function API_Call2(AppName: string; Param: TDataHnd; Timeout_: uint64): TDataHnd; static;

    {**************************************************************************
      【直接映射】API_Notify
      功能：单向通知（fire‑and‑forget）。
      参数：
        appName : PAnsiChar – 目标应用名（UTF‑8 + #0）。
        Param   : TDataHnd – 输入句柄（内部克隆，调用者释放原句柄）。
      设计意图：用于日志、事件等无需响应的场景。
      线程安全：是。
      AI 翻译提示：其他语言提供异步发送方法，无返回值。
    **************************************************************************}
    class procedure API_Notify(AppName: pansichar; Param: TDataHnd); static;
    {**************************************************************************
      【直接映射】API_Notify2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class procedure API_Notify2(AppName: string; Param: TDataHnd); static;

    // ==================== 配置与同步 ====================
    {**************************************************************************
      【直接映射】API_SetOption
      功能：动态调整全局运行时配置。
      参数：
        Option : PAnsiChar – 配置键（UTF‑8 + #0，不区分大小写，支持别名）。
        Value  : PAnsiChar – 新值（UTF‑8 + #0，布尔值接受 True/False, 1/0, Yes/No）。
      设计意图：无需修改 .ini 文件或重启即可调优。
      支持的选项（部分）：
        - 'password' / 'passwd'          : 设置 P2PVM 认证令牌（服务端/客户端需匹配）。
        - 'Wait_Connection_ReadyOk'      : 是否等待客户端就绪（True/False）。
        - 'Wait_Connection_Timeout'      : 等待超时（毫秒，默认 30000）。
        - 'IPC_Serv_ThreadCount'         : IPC 线程池大小。
        - 'ConsoleOutput'                : 是否输出控制台日志。
      注意事项：未知选项被静默忽略，重要选项需在 API_Prepare_Done 前设置。
      线程安全：是。
      AI 翻译提示：其他语言应提供类似配置接口。
    **************************************************************************}
    class procedure API_SetOption(Option, Value: pansichar); static;
    {**************************************************************************
      【直接映射】API_SetOption2 – Pascal 辅助，自动 UTF‑8 转换。
    **************************************************************************}
    class procedure API_SetOption2(Option, Value: string); static;

    {**************************************************************************
      【直接映射】API_Sync
      功能：处理主线程同步队列，用于软同步机制。
      返回值：处理的任务数量。
      设计意图：配合 TSoft_Synchronize_Tool 使用，实现用户态线程同步。
      AI 翻译提示：其他语言若需要类似机制，应使用其平台的原生同步原语。
    **************************************************************************}
    class function API_Sync: integer; static;

    {**************************************************************************
      【直接映射】API_shutdown
      功能：完全关闭框架，停止所有服务、断开客户端、释放资源。
      设计意图：清理后状态重置，可重新初始化。
      建议顺序：先 API_Exit_MainThread，再 API_shutdown。
      线程安全：是，但通常主线程调用。
    **************************************************************************}
    class procedure API_shutdown; static;

    // ==================== 新增的 Pascal 辅助函数映射 ====================
    {**************************************************************************
      【直接映射】API_Get_Status2 – 获取状态队列中的下一条日志消息。
      返回：UTF‑8 字符串（已解码为 Pascal string）。
      注意：内部自动复制数据，不受缓冲区覆盖影响。
    **************************************************************************}
    class function API_Get_Status2: string; static;

    {**************************************************************************
      【直接映射】API_Post_Status2 – 向状态队列写入自定义日志消息。
      参数：status : string – 要写入的消息（Pascal string）。
      线程安全：是。
    **************************************************************************}
    class procedure API_Post_Status2(const status: string); static;

    {**************************************************************************
      【直接映射】API_Check_MainThread2 – 检查模拟主线程是否运行。
      返回：True 表示运行中，False 表示已停止。
    **************************************************************************}
    class function API_Check_MainThread2: Boolean; static;

    {**************************************************************************
      【直接映射】API_Check_App2 – 检查网络中是否存在指定应用。
      参数：appName : string – 应用名。
      返回：True 存在，False 不存在。
      注意：基于本地缓存，不保证实时性。
    **************************************************************************}
    class function API_Check_App2(const appName: string): Boolean; static;
  end;

implementation

{=============================================================================
  API.TDataHandle 实现
=============================================================================}

function API.TDataHandle.IsValid: boolean;
begin
  Result := (FHandle <> nil) and not FDisposed;
end;

constructor API.TDataHandle.Create(const APIName: string);
begin
  inherited Create;
  FHandle := API_Create_DataHnd2(APIName);
  FOwned := True;
  FDisposed := False;
  FLock := TCritical.Create;
end;

constructor API.TDataHandle.Create(AHandle: TDataHnd; const Owned: boolean = False);
begin
  inherited Create;
  FHandle := AHandle;
  FOwned := Owned;
  FDisposed := False;
  FLock := TCritical.Create;
end;

destructor API.TDataHandle.Destroy;
begin
  FLock.Enter;
  try
    if not FDisposed then
    begin
      if FOwned and (FHandle <> nil) then
        API_Free_DataHnd(FHandle);
      FHandle := nil;
      FDisposed := True;
    end;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited;
end;

function API.TDataHandle.WriteBuffer(const Buffer; Size: int64): int64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_WriteBuffer(FHandle, @Buffer, Size);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadBuffer(var Buffer; Size: int64): int64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadBuffer(FHandle, @Buffer, Size);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteInt8(Value: int8): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteInt8(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteUInt8(Value: uint8): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteUInt8(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteInt16(Value: int16): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteInt16(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteUInt16(Value: uint16): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteUInt16(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteInt32(Value: int32): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteInt32(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteUInt32(Value: uint32): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteUInt32(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteInt64(Value: int64): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteInt64(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteUInt64(Value: uint64): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteUInt64(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteSingle(Value: single): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteSingle(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteDouble(Value: double): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteDouble(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.WriteStringNullTerminated(const Value: string): TDataHandle;
begin
  FLock.Enter;
  try
    if IsValid then
      API_WriteString(FHandle, Value);
    Result := Self;
  finally
    FLock.Leave;
  end;
end;

procedure API.TDataHandle.WriteString(const Value: string);
begin
  WriteStringNullTerminated(Value);
end;

function API.TDataHandle.ReadInt8(var Value: int8): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadInt8(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt8(var Value: uint8): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadUInt8(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt16(var Value: int16): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadInt16(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt16(var Value: uint16): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadUInt16(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt32(var Value: int32): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadInt32(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt32(var Value: uint32): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadUInt32(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt64(var Value: int64): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadInt64(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt64(var Value: uint64): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadUInt64(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadSingle(var Value: single): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadSingle(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadDouble(var Value: double): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := False
    else
      Result := API_ReadDouble(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt8: int8;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadInt8(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt8: uint8;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadUInt8(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt16: int16;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadInt16(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt16: uint16;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadUInt16(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt32: int32;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadInt32(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt32: uint32;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadUInt32(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadInt64: int64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadInt64(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadUInt64: uint64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_ReadUInt64(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadSingle: single;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0.0
    else
      Result := API_ReadSingle(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadDouble: double;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0.0
    else
      Result := API_ReadDouble(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadStringNullTerminated: string;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := ''
    else
      Result := API_ReadString(FHandle);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadString(out Value: string): boolean;
begin
  FLock.Enter;
  try
    if not IsValid then
    begin
      Value := '';
      Result := False;
    end
    else
      Result := API_ReadString(FHandle, Value);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.ReadString(): string;
begin
  Result := ReadStringNullTerminated();
end;

function API.TDataHandle.GetPos: int64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_GetPos(FHandle);
  finally
    FLock.Leave;
  end;
end;

procedure API.TDataHandle.SetPos(Pos_: int64);
begin
  FLock.Enter;
  try
    if IsValid then
      API_SetPos(FHandle, Pos_);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.GetSize: int64;
begin
  FLock.Enter;
  try
    if not IsValid then
      Result := 0
    else
      Result := API_GetSize(FHandle);
  finally
    FLock.Leave;
  end;
end;

procedure API.TDataHandle.SetSize(Size_: int64);
begin
  FLock.Enter;
  try
    if IsValid then
      API_SetSize(FHandle, Size_);
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.GetBufferEx(out Size: int64): Pointer;
begin
  FLock.Enter;
  try
    if not IsValid then
    begin
      Size := 0;
      Result := nil;
    end
    else
    begin
      Result := API_GetBuffer(FHandle);
      Size := API_GetSize(FHandle);
    end;
  finally
    FLock.Leave;
  end;
end;

function API.TDataHandle.GetBuffer(): Pointer;
begin
  FLock.Enter;
  try
    if not IsValid then
    begin
      Result := nil;
    end
    else
    begin
      Result := API_GetBuffer(FHandle);
    end;
  finally
    FLock.Leave;
  end;
end;

{=============================================================================
  API.TAppHandle 实现
=============================================================================}

constructor API.TAppHandle.Create(const AppName, Desc: string);
begin
  inherited Create;
  FHandle := API_Create_APPHnd2(AppName, Desc);
  FName := AppName;
end;

destructor API.TAppHandle.Destroy;
begin
  if FHandle <> nil then
    API_Free_APPHnd(FHandle);
  inherited;
end;

function API.TAppHandle.RegisterCall(const APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Call2(FHandle, APIName, Desc, Trigger, OnCall) = 1;
end;

function API.TAppHandle.RegisterCall(const APIName, Desc: string; OnCall: TAPI_Call_M): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Call_M(FHandle, APIName, Desc, OnCall) = 1;
end;

function API.TAppHandle.RegisterCallSync(const APIName, Desc: string; OnCall: TAPI_Call_M): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Sync_Call_M(FHandle, APIName, Desc, OnCall) = 1;
end;

function API.TAppHandle.RegisterNotify(const APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Notify2(FHandle, APIName, Desc, Trigger, OnNotify) = 1;
end;

function API.TAppHandle.RegisterNotify(const APIName, Desc: string; OnNotify: TAPI_Notify_M): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Notify_M(FHandle, APIName, Desc, OnNotify) = 1;
end;

function API.TAppHandle.RegisterNotifySync(const APIName, Desc: string; OnNotify: TAPI_Notify_M): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_Reg_Sync_Notify_M(FHandle, APIName, Desc, OnNotify) = 1;
end;

function API.TAppHandle.Unregister(const APIName: string): boolean;
begin
  if FHandle = nil then
    Result := False
  else
    Result := API_UnReg2(FHandle, APIName) = 1;
end;

function API.TAppHandle.LocalCall(Param: TDataHandle): TDataHandle;
var
  Res: TDataHnd;
begin
  if FHandle = nil then
    Result := TDataHandle.Create(nil, True)
  else
  begin
    Res := API_Local_APP_Call(FHandle, Param.Handle);
    Result := TDataHandle.Create(Res, True);
  end;
end;

procedure API.TAppHandle.LocalNotify(Param: TDataHandle);
begin
  if FHandle <> nil then
    API_Local_APP_Notify(FHandle, Param.Handle);
end;

{=============================================================================
  API 静态方法实现
=============================================================================}

class procedure API.ResetPrepare;
begin
  API_Reset_Prepare;
end;

class function API.PrepareService(const ListeningAddr, PhysicsAddr: string): integer;
begin
  Result := API_Prepare_Service2(ListeningAddr, PhysicsAddr);
end;

class function API.PrepareService(const ListeningAddr, PhysicsAddr: string; App: TAppHandle): integer;
begin
  Result := API_Prepare_Service2(ListeningAddr, PhysicsAddr);
  if Result <> 0 then
    PrepareClient(PhysicsAddr, App);
end;

class function API.PrepareClient(const PhysicsAddr: string; App: TAppHandle): integer;
begin
  if Assigned(App) then
    Result := API_Prepare_Client2(PhysicsAddr, App.Handle)
  else
    Result := API_Prepare_Client2(PhysicsAddr);
end;

class function API.PrepareDone: boolean;
begin
  Result := API_Prepare_Done = 1;
end;

class procedure API.ExitMainThread;
begin
  API_Exit_MainThread;
end;

class function API.CallApp(const AppName: string; Param: TDataHandle; TimeoutMs: uint64): TDataHandle;
var
  Res: TDataHnd;
begin
  Res := API_Call2(AppName, Param.Handle, TimeoutMs);
  Result := TDataHandle.Create(Res, True);
end;

class procedure API.NotifyApp(const AppName: string; Param: TDataHandle);
begin
  API_Notify2(AppName, Param.Handle);
end;

class procedure API.SetOption(const Option, Value: string);
begin
  API_SetOption2(Option, Value);
end;

class function API.Sync: integer;
begin
  Result := API_Sync;
end;

class procedure API.Shutdown;
begin
  API_shutdown;
end;

class function API.GetStatus: string;
begin
  Result := API_Get_Status2;
end;

class function API.Get_Status_Num: Integer;
begin
  Result := API_Get_Status_Num;
end;

class procedure API.PostStatus(const Status: string);
begin
  API_Post_Status2(Status);
end;

class function API.CheckMainThread: Boolean;
begin
  Result := API_Check_MainThread2;
end;

class function API.CheckApp(const AppName: string): Boolean;
begin
  Result := API_Check_App2(AppName);
end;

{=============================================================================
  API__ 静态方法实现 – 直接转发至 import
=============================================================================}

class function API__.API_Create_DataHnd(APIName: pansichar): TDataHnd;
begin
  Result := z_api_hubtool_import.API_Create_DataHnd(APIName);
end;

class function API__.API_Create_DataHnd2(APIName: string): TDataHnd;
begin
  Result := z_api_hubtool_import.API_Create_DataHnd2(APIName);
end;

class procedure API__.API_Free_DataHnd(Hnd: TDataHnd);
begin
  z_api_hubtool_import.API_Free_DataHnd(Hnd);
end;

class function API__.API_GetBuffer(Hnd: TDataHnd): Pointer;
begin
  Result := z_api_hubtool_import.API_GetBuffer(Hnd);
end;

class function API__.API_GetBuffer2(Hnd: TDataHnd; Offset: nativeint): Pointer;
begin
  Result := z_api_hubtool_import.API_GetBuffer2(Hnd, Offset);
end;

class function API__.API_WriteBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64;
begin
  Result := z_api_hubtool_import.API_WriteBuffer(Hnd, Buff, Size);
end;

class function API__.API_ReadBuffer(Hnd: TDataHnd; Buff: Pointer; Size: int64): int64;
begin
  Result := z_api_hubtool_import.API_ReadBuffer(Hnd, Buff, Size);
end;

class function API__.API_WriteInt8(Hnd: TDataHnd; Value: int8): boolean;
begin
  Result := z_api_hubtool_import.API_WriteInt8(Hnd, Value);
end;

class function API__.API_WriteUInt8(Hnd: TDataHnd; Value: uint8): boolean;
begin
  Result := z_api_hubtool_import.API_WriteUInt8(Hnd, Value);
end;

class function API__.API_WriteInt16(Hnd: TDataHnd; Value: int16): boolean;
begin
  Result := z_api_hubtool_import.API_WriteInt16(Hnd, Value);
end;

class function API__.API_WriteUInt16(Hnd: TDataHnd; Value: uint16): boolean;
begin
  Result := z_api_hubtool_import.API_WriteUInt16(Hnd, Value);
end;

class function API__.API_WriteInt32(Hnd: TDataHnd; Value: int32): boolean;
begin
  Result := z_api_hubtool_import.API_WriteInt32(Hnd, Value);
end;

class function API__.API_WriteUInt32(Hnd: TDataHnd; Value: uint32): boolean;
begin
  Result := z_api_hubtool_import.API_WriteUInt32(Hnd, Value);
end;

class function API__.API_WriteInt64(Hnd: TDataHnd; Value: int64): boolean;
begin
  Result := z_api_hubtool_import.API_WriteInt64(Hnd, Value);
end;

class function API__.API_WriteUInt64(Hnd: TDataHnd; Value: uint64): boolean;
begin
  Result := z_api_hubtool_import.API_WriteUInt64(Hnd, Value);
end;

class function API__.API_WriteSingle(Hnd: TDataHnd; Value: single): boolean;
begin
  Result := z_api_hubtool_import.API_WriteSingle(Hnd, Value);
end;

class function API__.API_WriteDouble(Hnd: TDataHnd; Value: double): boolean;
begin
  Result := z_api_hubtool_import.API_WriteDouble(Hnd, Value);
end;

class function API__.API_WriteString(Hnd: TDataHnd; const Value: string): boolean;
begin
  Result := z_api_hubtool_import.API_WriteString(Hnd, Value);
end;

class function API__.API_ReadInt8(Hnd: TDataHnd; out Value: int8): boolean;
begin
  Result := z_api_hubtool_import.API_ReadInt8(Hnd, Value);
end;

class function API__.API_ReadUInt8(Hnd: TDataHnd; out Value: uint8): boolean;
begin
  Result := z_api_hubtool_import.API_ReadUInt8(Hnd, Value);
end;

class function API__.API_ReadInt16(Hnd: TDataHnd; out Value: int16): boolean;
begin
  Result := z_api_hubtool_import.API_ReadInt16(Hnd, Value);
end;

class function API__.API_ReadUInt16(Hnd: TDataHnd; out Value: uint16): boolean;
begin
  Result := z_api_hubtool_import.API_ReadUInt16(Hnd, Value);
end;

class function API__.API_ReadInt32(Hnd: TDataHnd; out Value: int32): boolean;
begin
  Result := z_api_hubtool_import.API_ReadInt32(Hnd, Value);
end;

class function API__.API_ReadUInt32(Hnd: TDataHnd; out Value: uint32): boolean;
begin
  Result := z_api_hubtool_import.API_ReadUInt32(Hnd, Value);
end;

class function API__.API_ReadInt64(Hnd: TDataHnd; out Value: int64): boolean;
begin
  Result := z_api_hubtool_import.API_ReadInt64(Hnd, Value);
end;

class function API__.API_ReadUInt64(Hnd: TDataHnd; out Value: uint64): boolean;
begin
  Result := z_api_hubtool_import.API_ReadUInt64(Hnd, Value);
end;

class function API__.API_ReadSingle(Hnd: TDataHnd; out Value: single): boolean;
begin
  Result := z_api_hubtool_import.API_ReadSingle(Hnd, Value);
end;

class function API__.API_ReadDouble(Hnd: TDataHnd; out Value: double): boolean;
begin
  Result := z_api_hubtool_import.API_ReadDouble(Hnd, Value);
end;

class function API__.API_ReadInt8(Hnd: TDataHnd): int8;
begin
  Result := z_api_hubtool_import.API_ReadInt8(Hnd);
end;

class function API__.API_ReadUInt8(Hnd: TDataHnd): uint8;
begin
  Result := z_api_hubtool_import.API_ReadUInt8(Hnd);
end;

class function API__.API_ReadInt16(Hnd: TDataHnd): int16;
begin
  Result := z_api_hubtool_import.API_ReadInt16(Hnd);
end;

class function API__.API_ReadUInt16(Hnd: TDataHnd): uint16;
begin
  Result := z_api_hubtool_import.API_ReadUInt16(Hnd);
end;

class function API__.API_ReadInt32(Hnd: TDataHnd): int32;
begin
  Result := z_api_hubtool_import.API_ReadInt32(Hnd);
end;

class function API__.API_ReadUInt32(Hnd: TDataHnd): uint32;
begin
  Result := z_api_hubtool_import.API_ReadUInt32(Hnd);
end;

class function API__.API_ReadInt64(Hnd: TDataHnd): int64;
begin
  Result := z_api_hubtool_import.API_ReadInt64(Hnd);
end;

class function API__.API_ReadUInt64(Hnd: TDataHnd): uint64;
begin
  Result := z_api_hubtool_import.API_ReadUInt64(Hnd);
end;

class function API__.API_ReadSingle(Hnd: TDataHnd): single;
begin
  Result := z_api_hubtool_import.API_ReadSingle(Hnd);
end;

class function API__.API_ReadDouble(Hnd: TDataHnd): double;
begin
  Result := z_api_hubtool_import.API_ReadDouble(Hnd);
end;

class function API__.API_ReadString(Hnd: TDataHnd; out Value: string): boolean;
begin
  Result := z_api_hubtool_import.API_ReadString(Hnd, Value);
end;

class function API__.API_ReadString(Hnd: TDataHnd): string;
begin
  Result := z_api_hubtool_import.API_ReadString(Hnd);
end;

class function API__.API_GetPos(Hnd: TDataHnd): int64;
begin
  Result := z_api_hubtool_import.API_GetPos(Hnd);
end;

class procedure API__.API_SetPos(Hnd: TDataHnd; Pos_: int64);
begin
  z_api_hubtool_import.API_SetPos(Hnd, Pos_);
end;

class function API__.API_GetSize(Hnd: TDataHnd): int64;
begin
  Result := z_api_hubtool_import.API_GetSize(Hnd);
end;

class procedure API__.API_SetSize(Hnd: TDataHnd; Size_: int64);
begin
  z_api_hubtool_import.API_SetSize(Hnd, Size_);
end;

class function API__.API_Create_APPHnd(AppName, Desc: pansichar): TAppHnd;
begin
  Result := z_api_hubtool_import.API_Create_APPHnd(AppName, Desc);
end;

class function API__.API_Create_APPHnd2(AppName, Desc: string): TAppHnd;
begin
  Result := z_api_hubtool_import.API_Create_APPHnd2(AppName, Desc);
end;

class procedure API__.API_Free_APPHnd(appHnd: TAppHnd);
begin
  z_api_hubtool_import.API_Free_APPHnd(appHnd);
end;

class function API__.API_Reg_Call(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnCall: TAPI_Call): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Call(appHnd, APIName, Desc, Trigger, OnCall);
end;

class function API__.API_Reg_Call2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnCall: TAPI_Call): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Call2(appHnd, APIName, Desc, Trigger, OnCall);
end;

class function API__.API_Reg_Call_M(appHnd: TAppHnd; APIName, Desc: string; OnCall: TAPI_Call_M): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Call_M(appHnd, APIName, Desc, OnCall);
end;

class function API__.API_Reg_Sync_Call_M(appHnd: TAppHnd; APIName, Desc: string; OnCall: TAPI_Call_M): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Sync_Call_M(appHnd, APIName, Desc, OnCall);
end;

class function API__.API_Reg_Notify(appHnd: TAppHnd; APIName, Desc: pansichar; Trigger: Pointer; OnNotify: TAPI_Notify): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Notify(appHnd, APIName, Desc, Trigger, OnNotify);
end;

class function API__.API_Reg_Notify2(appHnd: TAppHnd; APIName, Desc: string; Trigger: Pointer; OnNotify: TAPI_Notify): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Notify2(appHnd, APIName, Desc, Trigger, OnNotify);
end;

class function API__.API_Reg_Notify_M(appHnd: TAppHnd; APIName, Desc: string; OnNotify: TAPI_Notify_M): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Notify_M(appHnd, APIName, Desc, OnNotify);
end;

class function API__.API_Reg_Sync_Notify_M(appHnd: TAppHnd; APIName, Desc: string; OnNotify: TAPI_Notify_M): integer;
begin
  Result := z_api_hubtool_import.API_Reg_Sync_Notify_M(appHnd, APIName, Desc, OnNotify);
end;

class function API__.API_UnReg(appHnd: TAppHnd; APIName: pansichar): integer;
begin
  Result := z_api_hubtool_import.API_UnReg(appHnd, APIName);
end;

class function API__.API_UnReg2(appHnd: TAppHnd; APIName: string): integer;
begin
  Result := z_api_hubtool_import.API_UnReg2(appHnd, APIName);
end;

class function API__.API_Local_APP_Call(appHnd: TAppHnd; Param: TDataHnd): TDataHnd;
begin
  Result := z_api_hubtool_import.API_Local_APP_Call(appHnd, Param);
end;

class procedure API__.API_Local_APP_Notify(appHnd: TAppHnd; Param: TDataHnd);
begin
  z_api_hubtool_import.API_Local_APP_Notify(appHnd, Param);
end;

class function API__.API_Prepare_Service(ListeningAddr_, PhysicsAddr_: pansichar): integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Service(ListeningAddr_, PhysicsAddr_);
end;

class function API__.API_Prepare_Service2(ListeningAddr_, PhysicsAddr_: string): integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Service2(ListeningAddr_, PhysicsAddr_);
end;

class function API__.API_Prepare_Client(PhysicsAddr_: pansichar; appHnd: TAppHnd): integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Client(PhysicsAddr_, appHnd);
end;

class function API__.API_Prepare_Client2(PhysicsAddr_: string; appHnd: TAppHnd): integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Client2(PhysicsAddr_, appHnd);
end;

class function API__.API_Prepare_Client2(PhysicsAddr_: string): integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Client2(PhysicsAddr_);
end;

class procedure API__.API_Reset_Prepare;
begin
  z_api_hubtool_import.API_Reset_Prepare;
end;

class function API__.API_Prepare_Done: integer;
begin
  Result := z_api_hubtool_import.API_Prepare_Done;
end;

class procedure API__.API_Exit_MainThread;
begin
  z_api_hubtool_import.API_Exit_MainThread;
end;

class function API__.API_Call(AppName: pansichar; Param: TDataHnd; Timeout_: uint64): TDataHnd;
begin
  Result := z_api_hubtool_import.API_Call(AppName, Param, Timeout_);
end;

class function API__.API_Call2(AppName: string; Param: TDataHnd; Timeout_: uint64): TDataHnd;
begin
  Result := z_api_hubtool_import.API_Call2(AppName, Param, Timeout_);
end;

class procedure API__.API_Notify(AppName: pansichar; Param: TDataHnd);
begin
  z_api_hubtool_import.API_Notify(AppName, Param);
end;

class procedure API__.API_Notify2(AppName: string; Param: TDataHnd);
begin
  z_api_hubtool_import.API_Notify2(AppName, Param);
end;

class procedure API__.API_SetOption(Option, Value: pansichar);
begin
  z_api_hubtool_import.API_SetOption(Option, Value);
end;

class procedure API__.API_SetOption2(Option, Value: string);
begin
  z_api_hubtool_import.API_SetOption2(Option, Value);
end;

class function API__.API_Sync: integer;
begin
  Result := z_api_hubtool_import.API_Sync;
end;

class procedure API__.API_shutdown;
begin
  z_api_hubtool_import.API_shutdown;
end;

class function API__.API_Get_Status2: string;
begin
  Result := z_api_hubtool_import.API_Get_Status2;
end;

class procedure API__.API_Post_Status2(const status: string);
begin
  z_api_hubtool_import.API_Post_Status2(status);
end;

class function API__.API_Check_MainThread2: Boolean;
begin
  Result := z_api_hubtool_import.API_Check_MainThread2;
end;

class function API__.API_Check_App2(const appName: string): Boolean;
begin
  Result := z_api_hubtool_import.API_Check_App2(appName);
end;

end.
