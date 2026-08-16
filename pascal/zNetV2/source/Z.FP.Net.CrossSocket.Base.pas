(*
MIT License

Copyright (c) 2026 by.LaoZhang qq600585

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*)
unit Z.FP.Net.CrossSocket.Base;

{ *
  * CrossSocket.Base – Abstract foundation for cross‑platform asynchronous I/O.
  * Defines interfaces and base classes for listening, connection, and socket
  * management, along with threading and event handling infrastructure.
  *
  * This unit is the core abstraction layer upon which IOCP, epoll, and kqueue
  * implementations are built. It provides:
  *   - ICrossData, ICrossListen, ICrossConnection, ICrossSocket interfaces
  *   - TAbstractCrossSocket with connection/listen dictionaries, event triggers
  *   - TIoEventThread for running the I/O loop
  *   - Utility functions for UID tagging and logging
  *
  * All platform‑specific details are hidden behind these interfaces.
  * Usage example (server):
  *   var
  *     sock: ICrossSocket;
  *   begin
  *     sock := TCrossSocket.Create(4); // 4 I/O threads
  *     sock.OnConnected := MyConnectHandler;
  *     sock.Listen('0.0.0.0', 8080);
  *     while Running do
  *       CheckThreadSynchronize(10);
  *   end;
}

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses
  SysUtils,
  Classes,
  Math,
  Generics.Collections,
  Z.FP.Net.SocketAPI,
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status;

const
  INVALID_HANDLE_VALUE__ = THandle(-1);

  // UID categories: high 2 bits indicate the object type
  UID_RAW        = $0;
  UID_LISTEN     = $1;
  UID_CONNECTION = $2;

  // Mask for the lower 62 bits (the actual counter)
  UID_MASK       = UInt64($3FFFFFFFFFFFFFFF);

  // Convenience constants for common IPv4/IPv6 addresses
  IPv4_ALL   = '0.0.0.0';
  IPv6_ALL   = '::';
  IPv4v6_ALL = '';            // empty means bind to both families
  IPv4_LOCAL = '127.0.0.1';
  IPv6_LOCAL = '::1';

type
  ECrossSocket = class(Exception);

  ICrossSocket = interface;

  /// <summary>
  ///   How the connection was established.
  /// </summary>
  TConnectType = (
    ctUnknown,   // not yet determined
    ctAccept,    // accepted from a listening socket
    ctConnect    // initiated by a Connect() call
  );

  /// <summary>
  ///   Current state of a connection.
  /// </summary>
  TConnectStatus = (
    csUnknown,      // initial state
    csConnecting,   // TCP handshake in progress
    csHandshaking,  // TLS/SSL negotiation (not used in this base)
    csConnected,    // fully established
    csDisconnected, // gracefully shut down
    csClosed        // forcibly closed
  );

  /// <summary>
  ///   Common interface for any socket‑based object (listen or connection).
  /// </summary>
  ICrossData = interface
  ['{41416836-6448-48CE-9FCC-0AFBB2A3A283}']
    function GetOwner: ICrossSocket;
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: SystemString;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean;
    function GetUserData: Pointer;
    function GetUserObject: TCore_Object;
    function GetUserInterface: IInterface;

    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TCore_Object);
    procedure SetUserInterface(const AValue: IInterface);

    /// <summary>
    ///   Refresh cached local address/port from the underlying socket.
    ///   Called internally when the socket becomes bound or connected.
    /// </summary>
    procedure UpdateAddr;

    /// <summary>
    ///   Close the socket and release associated resources.
    ///   After this, IsClosed returns True.
    /// </summary>
    procedure Close;

    property Owner: ICrossSocket read GetOwner;
    property UID: UInt64 read GetUID;
    property Socket: THandle read GetSocket;
    property LocalAddr: SystemString read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserObject: TCore_Object read GetUserObject write SetUserObject;
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;

  TCrossDatas = TDictionary<UInt64, ICrossData>;

  /// <summary>
  ///   Interface for a listening socket.
  /// </summary>
  ICrossListen = interface(ICrossData)
  ['{F4E7DC40-03FA-4161-ADC6-B3CC10DBB16D}']
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;

    property Family: Integer read GetFamily;
    property SockType: Integer read GetSockType;
    property Protocol: Integer read GetProtocol;
  end;

  TCrossListens = TDictionary<UInt64, ICrossListen>;

  ICrossConnection = Interface;

  TProc_ICrossConnection_Boolean = procedure(AConnection: ICrossConnection; ASuccessed: Boolean) of object;
  TProc_ICrossListen_Boolean = procedure(AListen: ICrossListen; ASuccessed: Boolean) of object;

  /// <summary>
  ///   Interface for a connected socket (client or accepted).
  /// </summary>
  ICrossConnection = interface(ICrossData)
  ['{3C2F05EB-706E-47E7-9D5A-D0AF026615AB}']
    function GetPeerAddr: SystemString;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    procedure SetConnectStatus(const Value: TConnectStatus);
    function ConnectionIntf: TCore_Object;

    /// <summary>
    ///   Gracefully disconnect (send FIN, then close). Data in flight is delivered.
    /// </summary>
    procedure Disconnect;

    /// <summary>
    ///   Send a buffer asynchronously.
    ///   @param ABuffer  pointer to the data to send
    ///   @param ACount   number of bytes to send
    ///   @param ACallback called when the send completes (or fails); can be nil
    /// </summary>
    procedure SendBuf(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); overload;

    property PeerAddr: SystemString read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property ConnectType: TConnectType read GetConnectType;
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;

  TCrossConnections = TDictionary<UInt64, ICrossConnection>;

  // Event handler types for the socket engine
  TCrossAcceptEvent = procedure(Sender: TCore_Object; AListen: ICrossListen; var Accept:Boolean) of object;
  TCrossListenEvent = procedure(Sender: TCore_Object; AListen: ICrossListen) of object;
  TCrossConnectEvent = procedure(Sender: TCore_Object; AConnection: ICrossConnection) of object;
  TCrossDataEvent = procedure(Sender: TCore_Object; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer) of object;

  /// <summary>
  ///   Main interface for the cross‑platform socket engine.
  ///   All I/O operations are asynchronous; events are fired on the I/O threads.
  /// </summary>
  ICrossSocket = interface
  ['{52DBB95B-2AAB-4369-ADE6-FD61F080B94F}']
    function GetIoThreads: Integer;
    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    procedure SetOnConnected(const Value: TCrossConnectEvent);
    procedure SetOnDisconnected(const Value: TCrossConnectEvent);
    procedure SetOnListened(const Value: TCrossListenEvent);
    procedure SetOnListenEnd(const Value: TCrossListenEvent);
    procedure SetOnReceived(const Value: TCrossDataEvent);
    procedure SetOnSent(const Value: TCrossDataEvent);

    /// <summary>
    ///   Start the I/O threads and begin processing events.
    ///   Called automatically in AfterConstruction if using TAbstractCrossSocket.
    /// </summary>
    procedure StartLoop;

    /// <summary>
    ///   Stop all I/O threads and close all sockets. Called in BeforeDestruction.
    /// </summary>
    procedure StopLoop;

    /// <summary>
    ///   Process one I/O event (blocking). Returns False when the loop should exit.
    ///   Called repeatedly by each I/O thread.
    /// </summary>
    function ProcessIoEvent: Boolean;

    /// <summary>
    ///   Start listening on the given address/port.
    ///   @param AHost  IP or hostname; empty for all interfaces (IPv4+IPv6)
    ///   @param APort  port number; 0 to let the system choose a free port
    ///   @param ACallback called when the listen operation completes (success or failure)
    /// </summary>
    procedure Listen(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossListen_Boolean = nil);

    /// <summary>
    ///   Initiate an outbound connection.
    ///   @param AHost  remote host (IP or name)
    ///   @param APort  remote port
    ///   @param ACallback called when the connection is established (or fails)
    /// </summary>
    procedure Connect(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossConnection_Boolean = nil);

    /// <summary>
    ///   Send data on a connection. The buffer must remain valid until the callback fires.
    ///   @param AConnection the target connection
    ///   @param ABuf       data pointer
    ///   @param ALen       bytes to send
    ///   @param ACallback  called on completion (or error)
    /// </summary>
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil);

    /// <summary>
    ///   Close all connections immediately (data may be lost).
    /// </summary>
    procedure CloseAllConnections;

    /// <summary>
    ///   Close all listening sockets.
    /// </summary>
    procedure CloseAllListens;

    /// <summary>
    ///   Close everything (listens and connections).
    /// </summary>
    procedure CloseAll;

    /// <summary>
    ///   Disconnect all connections gracefully (data is sent before closing).
    /// </summary>
    procedure DisconnectAll;

    // --- Thread‑safe access to internal collections ---
    function LockConnections: TCrossConnections;
    procedure UnlockConnections;
    function LockListens: TCrossListens;
    procedure UnlockListens;

    // --- Factory methods (overridden by platform implementations) ---
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection;
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen;

    // --- Internal event triggers (used by platform code) ---
    procedure TriggerListened(AListen: ICrossListen);
    procedure TriggerListenEnd(AListen: ICrossListen);
    procedure TriggerConnecting(AConnection: ICrossConnection);
    procedure TriggerConnected(AConnection: ICrossConnection);
    procedure TriggerDisconnected(AConnection: ICrossConnection);

    property IoThreads: Integer read GetIoThreads;
    property ConnectionsCount: Integer read GetConnectionsCount;
    property ListensCount: Integer read GetListensCount;

    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  { *
    * TCrossData – base implementation of ICrossData.
    * Manages a unique 64‑bit identifier (UID) and the socket handle.
    * The UID's high 2 bits identify the type (listener/connection).
  }
  TCrossData = class abstract(TInterfacedObject, ICrossData)
  private
    class var FCrossUID: UInt64;   // global counter for unique IDs (62 bits)
  private
    FOwner: ICrossSocket;
    FUID: UInt64;
    FSocket: THandle;
    FLocalAddr: SystemString;
    FLocalPort: Word;
    FUserData: Pointer;
    FUserObject: TCore_Object;
    FUserInterface: IInterface;
  protected
    function GetOwner: ICrossSocket;
    function GetUIDTag: Byte; virtual;   // returns UID_LISTEN or UID_CONNECTION
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: SystemString;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean; virtual; abstract;
    function GetUserData: Pointer;
    function GetUserObject: TCore_Object;
    function GetUserInterface: IInterface;

    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TCore_Object);
    procedure SetUserInterface(const AValue: IInterface);
  public
    constructor Create(AOwner: ICrossSocket; ASocket: THandle); virtual;
    destructor Destroy; override;

    procedure UpdateAddr; virtual;
    procedure Close; virtual; abstract;

    property Owner: ICrossSocket read GetOwner;
    property UID: UInt64 read GetUID;
    property Socket: THandle read GetSocket;
    property LocalAddr: SystemString read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserObject: TCore_Object read GetUserObject write SetUserObject;
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;

  { *
    * Abstract implementation of ICrossListen.
    * Stores the address family, socket type, and protocol.
  }
  TAbstractCrossListen = class(TCrossData, ICrossListen)
  private
    FFamily: Integer;
    FSockType: Integer;
    FProtocol: Integer;
    FClosed: Integer;          // 0 = open, 1 = closed
  protected
    function GetUIDTag: Byte; override;
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;
    function GetIsClosed: Boolean; override;
  public
    constructor Create(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer); reintroduce; virtual;

    procedure Close; override;

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: SystemString read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
  end;

  { *
    * Abstract implementation of ICrossConnection.
    * Holds peer address, port, connection type, and status.
    * Provides a default DirectSend that wraps the platform‑specific Send.
  }
  TAbstractCrossConnection = class(TCrossData, ICrossConnection)
  public const
    SND_BUF_SIZE = 16384;      // default send chunk size (not used in all platforms)
  private
    FPeerAddr: SystemString;
    FPeerPort: Word;
    FConnectType: TConnectType;
    FConnectStatus: Integer;   // stored as TConnectStatus
  protected
    function GetUIDTag: Byte; override;
    function GetPeerAddr: SystemString;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    function GetIsClosed: Boolean; override;

    function _SetConnectStatus(const AStatus: TConnectStatus): TConnectStatus; inline;
    procedure SetConnectStatus(const Value: TConnectStatus);

    function ConnectionIntf: TCore_Object;

    /// <summary>
    ///   Actually send the buffer using the engine's Send method.
    ///   This is called by SendBuf; can be overridden for SSL etc.
    /// </summary>
    procedure DirectSend(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); virtual;
  public
    constructor Create(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType); reintroduce; virtual;

    procedure UpdateAddr; override;
    procedure Close; override;
    procedure Disconnect; virtual;

    procedure SendBuf(ABuffer: Pointer; ACount: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil);

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: SystemString read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;

    property PeerAddr: SystemString read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property ConnectType: TConnectType read GetConnectType;
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;


  { *
    * Bridge class used by DirectSend to wrap the callback and trigger Sent event.
  }
  TDirectSend_Bridge_ = class
  public
    FOwner: ICrossSocket;
    LBuffer: Pointer;
    ACount: Integer;
    ACallback: TProc_ICrossConnection_Boolean;
    procedure Do_CallBack(AConnection: ICrossConnection; ASuccess: Boolean);
  end;

  { *
    * Worker thread that continuously calls ProcessIoEvent.
    * Each instance runs its own loop on a separate thread.
  }
  TIoEventThread = class(TThread)
  private
    FCrossSocket: ICrossSocket;
  protected
    procedure Execute; override;
  public
    IO_Is_Busy: Boolean;       // True while the thread is alive
    constructor Create(ACrossSocket: ICrossSocket); reintroduce;
  end;

  { *
    * Abstract base for the main socket engine.
    * Manages connection/listen dictionaries, event callbacks, and threading.
    * All platform implementations (IOCP, Epoll, Kqueue) inherit from this.
  }
  TAbstractCrossSocket = class abstract(TCore_InterfacedObject_Intermediate, ICrossSocket)
  protected const
    RCV_BUF_SIZE = 32768;      // per‑thread receive buffer size
  protected class threadvar
    FRecvBuf: array [0..RCV_BUF_SIZE-1] of Byte; // thread‑local receive buffer
  protected
    FIoThreads: Integer;       // number of I/O threads requested

    /// <summary>
    ///   Set TCP keep‑alive parameters on a new socket.
    ///   Default: 2s idle, 1s interval, 2 probes.
    /// </summary>
    function SetKeepAlive(ASocket: THandle): Integer;
  private
    FConnections: TCrossConnections;
    FConnectionsLock: TCritical;

    FListens: TCrossListens;
    FListensLock: TCritical;

    FOnListened: TCrossListenEvent;
    FOnListenEnd: TCrossListenEvent;
    FOnAccept: TCrossAcceptEvent;
    FOnConnected: TCrossConnectEvent;
    FOnDisconnected: TCrossConnectEvent;
    FOnReceived: TCrossDataEvent;
    FOnSent: TCrossDataEvent;

    procedure _LockConnections; inline;
    procedure _UnlockConnections; inline;
    procedure _LockListens; inline;
    procedure _UnlockListens; inline;

    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnAccept: TCrossAcceptEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    procedure SetOnConnected(const Value: TCrossConnectEvent);
    procedure SetOnDisconnected(const Value: TCrossConnectEvent);
    procedure SetOnListened(const Value: TCrossListenEvent);
    procedure SetOnListenEnd(const Value: TCrossListenEvent);
    procedure SetOnAccept(const Value: TCrossAcceptEvent);
    procedure SetOnReceived(const Value: TCrossDataEvent);
    procedure SetOnSent(const Value: TCrossDataEvent);
  protected
    FConnectionsCount: Integer;
    FListensCount: Integer;

    function ProcessIoEvent: Boolean; virtual; abstract;
    function GetIoThreads: Integer; virtual;

    // Factory methods (must be implemented in descendants)
    function CreateConnection(AOwner: ICrossSocket; AClientSocket: THandle;
      AConnectType: TConnectType): ICrossConnection; virtual; abstract;
    function CreateListen(AOwner: ICrossSocket; AListenSocket: THandle;
      AFamily, ASockType, AProtocol: Integer): ICrossListen; virtual; abstract;

    // Event triggers (can be overridden for logging or custom behaviour)
    procedure TriggerListened(AListen: ICrossListen); virtual;
    procedure TriggerListenEnd(AListen: ICrossListen); virtual;
    function TriggerAccept(AListen: ICrossListen): Boolean; virtual;
    procedure TriggerConnecting(AConnection: ICrossConnection); virtual;
    procedure TriggerConnected(AConnection: ICrossConnection); virtual;
    procedure TriggerDisconnected(AConnection: ICrossConnection); virtual;
    procedure TriggerReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure TriggerSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;

    // Logic events (for SSL etc. – not used in base)
    procedure LogicConnected(AConnection: ICrossConnection); virtual;
    procedure LogicDisconnected(AConnection: ICrossConnection); virtual;
    procedure LogicReceived(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure LogicSent(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;

    procedure StartLoop; virtual; abstract;
    procedure StopLoop; virtual; abstract;

    procedure Listen(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossListen_Boolean = nil); virtual; abstract;
    procedure Connect(const AHost: SystemString; APort: Word;
      const ACallback: TProc_ICrossConnection_Boolean = nil); virtual; abstract;
    procedure Send(AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer;
      const ACallback: TProc_ICrossConnection_Boolean = nil); virtual; abstract;

    procedure CloseAllConnections; virtual;
    procedure CloseAllListens; virtual;
    procedure CloseAll; virtual;
    procedure DisconnectAll; virtual;
  public
    constructor Create(AIoThreads: Integer); virtual;
    destructor Destroy; override;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    function LockConnections: TCrossConnections;
    procedure UnlockConnections;
    function LockListens: TCrossListens;
    procedure UnlockListens;

    property IoThreads: Integer read GetIoThreads;
    property ConnectionsCount: Integer read GetConnectionsCount;
    property ListensCount: Integer read GetListensCount;

    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;
    property OnAccept: TCrossAcceptEvent read GetOnAccept write SetOnAccept;
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  { *
    * Utility: extract the high 2 bits of a UID to get the object type.
  }
  function GetTagByUID(const AUID: UInt64): Byte;

  { *
    * Logging helpers (only active in DEBUG builds).
  }
  procedure _LogLastOsError(const ATag: SystemString);
  procedure _Log(const S: SystemString); overload;
  procedure _Log(const Fmt: SystemString; const Args: array of const); overload;

implementation
{$IFDEF MSWINDOWS}
{$IFDEF DEBUG}
  uses windows;
{$ENDIF}
{$ENDIF MSWINDOWS}

{ *
  * GetTagByUID – extract the high two bits.
}
function GetTagByUID(const AUID: UInt64): Byte;
begin
  Result := (AUID shr 62) and $03;
end;

{ *
  * _Log – output a SystemString for debugging (only if DEBUG defined).
}
procedure _Log(const S: SystemString); overload;
begin
  {$IFDEF DEBUG}
  DoStatus(s);
  {$ENDIF}
end;

{ *
  * _Log – formatted debug output.
}
procedure _Log(const Fmt: SystemString; const Args: array of const); overload;
begin
  _Log(Format(Fmt, Args));
end;

{ *
  * _LogLastOsError – prints the last OS error with an optional tag.
}
procedure _LogLastOsError(const ATag: SystemString);
{$IFDEF MSWINDOWS}
{$IFDEF DEBUG}
var
  LError: Integer;
  LErrMsg: TPascalString;
{$ENDIF}
{$ENDIF MSWINDOWS}
begin
  {$IFDEF MSWINDOWS}
  {$IFDEF DEBUG}
  LError := GetLastError;
  if (ATag <> '') then
    LErrMsg := ATag + ' : '
  else
    LErrMsg := '';
  LErrMsg := LErrMsg + Format('System Error.  Code: %0:d(%0:.4x), %1:s', [LError, SysErrorMessage(LError)]);
  _Log(LErrMsg);
  {$ENDIF}
  {$ENDIF MSWINDOWS}
end;

{ *
  * TIoEventThread – constructor: starts suspended, sets flag.
}
constructor TIoEventThread.Create(ACrossSocket: ICrossSocket);
begin
  inherited Create(True);
  FCrossSocket := ACrossSocket;
  FreeOnTerminate := False;
  IO_Is_Busy := True;
  Suspended := False;
end;

{ *
  * TIoEventThread.Execute – main loop: call ProcessIoEvent until it returns False.
}
procedure TIoEventThread.Execute;
begin
  while not Terminated do
  begin
    try
      if not FCrossSocket.ProcessIoEvent then Break;
    except
    end;
  end;
  IO_Is_Busy := False;
end;

{ *
  * TAbstractCrossSocket – constructor: initialises dictionaries and locks.
}
constructor TAbstractCrossSocket.Create(AIoThreads: Integer);
begin
  FIoThreads := AIoThreads;

  FListens := TCrossListens.Create;
  FListensLock := TCritical.Create;

  FConnections := TCrossConnections.Create;
  FConnectionsLock := TCritical.Create;
end;

{ *
  * Destructor: free dictionaries and locks.
}
destructor TAbstractCrossSocket.Destroy;
begin
  DisposeObjectAndNil(FListens);
  DisposeObjectAndNil(FListensLock);

  DisposeObjectAndNil(FConnections);
  DisposeObjectAndNil(FConnectionsLock);

  inherited;
end;

{ *
  * AfterConstruction – starts the I/O loop.
}
procedure TAbstractCrossSocket.AfterConstruction;
begin
  inherited AfterConstruction;
  StartLoop;
end;

{ *
  * BeforeDestruction – stops the I/O loop.
}
procedure TAbstractCrossSocket.BeforeDestruction;
begin
  StopLoop;
  inherited BeforeDestruction;
end;

{ *
  * CloseAll – close listens and connections.
}
procedure TAbstractCrossSocket.CloseAll;
begin
  CloseAllListens;
  CloseAllConnections;
end;

{ *
  * CloseAllConnections – iterate through a snapshot and close each.
}
procedure TAbstractCrossSocket.CloseAllConnections;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Close;
end;

{ *
  * CloseAllListens – iterate through a snapshot and close each.
}
procedure TAbstractCrossSocket.CloseAllListens;
var
  LListenArr: TArray<ICrossListen>;
  LListen: ICrossListen;
begin
  _LockListens;
  try
    LListenArr := FListens.Values.ToArray;
  finally
    _UnlockListens;
  end;

  for LListen in LListenArr do
    LListen.Close;
end;

{ *
  * DisconnectAll – gracefully disconnect each connection.
}
procedure TAbstractCrossSocket.DisconnectAll;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Disconnect;
end;

// -- Getters for properties --

function TAbstractCrossSocket.GetConnectionsCount: Integer;
begin
  Result := FConnectionsCount;
end;

function TAbstractCrossSocket.GetIoThreads: Integer;
begin
  if (FIoThreads > 0) then
    Result := FIoThreads
  else
    Result := CPUCount * 2 + 1; // default heuristic
end;

function TAbstractCrossSocket.GetListensCount: Integer;
begin
  Result := FListensCount;
end;

function TAbstractCrossSocket.GetOnConnected: TCrossConnectEvent;
begin
  Result := FOnConnected;
end;

function TAbstractCrossSocket.GetOnDisconnected: TCrossConnectEvent;
begin
  Result := FOnDisconnected;
end;

function TAbstractCrossSocket.GetOnListened: TCrossListenEvent;
begin
  Result := FOnListened;
end;

function TAbstractCrossSocket.GetOnListenEnd: TCrossListenEvent;
begin
  Result := FOnListenEnd;
end;

function TAbstractCrossSocket.GetOnAccept: TCrossAcceptEvent;
begin
  Result := FOnAccept;
end;

function TAbstractCrossSocket.GetOnReceived: TCrossDataEvent;
begin
  Result := FOnReceived;
end;

function TAbstractCrossSocket.GetOnSent: TCrossDataEvent;
begin
  Result := FOnSent;
end;

// -- Setters --

procedure TAbstractCrossSocket.SetOnConnected(const Value: TCrossConnectEvent);
begin
  FOnConnected := Value;
end;

procedure TAbstractCrossSocket.SetOnDisconnected(const Value: TCrossConnectEvent);
begin
  FOnDisconnected := Value;
end;

procedure TAbstractCrossSocket.SetOnListened(const Value: TCrossListenEvent);
begin
  FOnListened := Value;
end;

procedure TAbstractCrossSocket.SetOnListenEnd(const Value: TCrossListenEvent);
begin
  FOnListenEnd := Value;
end;

procedure TAbstractCrossSocket.SetOnAccept(const Value: TCrossAcceptEvent);
begin
  FOnAccept := Value;
end;

procedure TAbstractCrossSocket.SetOnReceived(const Value: TCrossDataEvent);
begin
  FOnReceived := Value;
end;

procedure TAbstractCrossSocket.SetOnSent(const Value: TCrossDataEvent);
begin
  FOnSent := Value;
end;

// -- Lock/unlock methods --

function TAbstractCrossSocket.LockConnections: TCrossConnections;
begin
  _LockConnections;
  Result := FConnections;
end;

function TAbstractCrossSocket.LockListens: TCrossListens;
begin
  _LockListens;
  Result := FListens;
end;

procedure TAbstractCrossSocket.UnlockConnections;
begin
  _UnlockConnections;
end;

procedure TAbstractCrossSocket.UnlockListens;
begin
  _UnlockListens;
end;

procedure TAbstractCrossSocket._LockConnections;
begin
  FConnectionsLock.Lock;
end;

procedure TAbstractCrossSocket._LockListens;
begin
  FListensLock.Lock;
end;

procedure TAbstractCrossSocket._UnlockConnections;
begin
  FConnectionsLock.UnLock;
end;

procedure TAbstractCrossSocket._UnlockListens;
begin
  FListensLock.UnLock;
end;

// -- SetKeepAlive --

function TAbstractCrossSocket.SetKeepAlive(ASocket: THandle): Integer;
begin
  Result := TSocketAPI.SetKeepAlive(ASocket, 2, 1, 2);
end;

// -- Trigger methods (called by platform code) --

procedure TAbstractCrossSocket.TriggerConnecting(AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csConnecting;

  _LockConnections;
  try
    FConnections.AddOrSetValue(AConnection.UID, AConnection);
    FConnectionsCount := FConnections.Count;
  finally
    _UnlockConnections;
  end;
end;

procedure TAbstractCrossSocket.TriggerConnected(AConnection: ICrossConnection);
begin
  AConnection.UpdateAddr;
  AConnection.ConnectStatus := csConnected;

  LogicConnected(AConnection);

  if Assigned(FOnConnected) then
    FOnConnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerDisconnected(AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csClosed;

  _LockConnections;
  try
    if not FConnections.ContainsKey(AConnection.UID) then Exit;
    FConnections.Remove(AConnection.UID);
    FConnectionsCount := FConnections.Count;
  finally
    _UnlockConnections;
  end;

  LogicDisconnected(AConnection);

  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerListened(AListen: ICrossListen);
begin
  AListen.UpdateAddr;

  _LockListens;
  try
    FListens.AddOrSetValue(AListen.UID, AListen);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListened) then
    FOnListened(Self, AListen);
end;

procedure TAbstractCrossSocket.TriggerListenEnd(AListen: ICrossListen);
begin
  _LockListens;
  try
    if not FListens.ContainsKey(AListen.UID) then Exit;
    FListens.Remove(AListen.UID);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListenEnd) then
    FOnListenEnd(Self, AListen);
end;

function TAbstractCrossSocket.TriggerAccept(AListen: ICrossListen): Boolean;
begin
  Result := True;
  if Assigned(FOnAccept) then
   FOnAccept(Self, AListen, Result);
end;

procedure TAbstractCrossSocket.TriggerReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicReceived(AConnection, ABuf, ALen);

  if Assigned(FOnReceived) then
    FOnReceived(Self, AConnection, ABuf, ALen);
end;

procedure TAbstractCrossSocket.TriggerSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
  LogicSent(AConnection, ABuf, ALen);

  if Assigned(FOnSent) then
    FOnSent(Self, AConnection, ABuf, ALen);
end;

// -- Logic event stubs (do nothing in base) --

procedure TAbstractCrossSocket.LogicConnected(AConnection: ICrossConnection);
begin
end;

procedure TAbstractCrossSocket.LogicDisconnected(AConnection: ICrossConnection);
begin
end;

procedure TAbstractCrossSocket.LogicReceived(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
end;

procedure TAbstractCrossSocket.LogicSent(AConnection: ICrossConnection;
  ABuf: Pointer; ALen: Integer);
begin
end;

{ *
  * TCrossData – constructor: generate a new unique ID with the appropriate tag.
}
constructor TCrossData.Create(AOwner: ICrossSocket; ASocket: THandle);
begin
  FUID :=
    (UInt64(GetUIDTag and $03) shl 62) or
    (UID_MASK and AtomInc(FCrossUID));

  FOwner := AOwner;
  FSocket := ASocket;
end;

{ *
  * Destructor: close the socket if still open.
}
destructor TCrossData.Destroy;
begin
  if (FSocket <> INVALID_HANDLE_VALUE__) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FSocket := THandle(INVALID_HANDLE_VALUE__);
  end;
  inherited;
end;

function TCrossData.GetLocalAddr: SystemString;
begin
  Result := FLocalAddr;
end;

function TCrossData.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TCrossData.GetOwner: ICrossSocket;
begin
  Result := FOwner;
end;

function TCrossData.GetSocket: THandle;
begin
  Result := FSocket;
end;

function TCrossData.GetUID: UInt64;
begin
  Result := FUID;
end;

function TCrossData.GetUIDTag: Byte;
begin
  Result := UID_RAW;
end;

function TCrossData.GetUserData: Pointer;
begin
  Result := FUserData;
end;

function TCrossData.GetUserInterface: IInterface;
begin
  Result := FUserInterface;
end;

function TCrossData.GetUserObject: TCore_Object;
begin
  Result := FUserObject;
end;

procedure TCrossData.SetUserData(const AValue: Pointer);
begin
  FUserData := AValue;
end;

procedure TCrossData.SetUserInterface(const AValue: IInterface);
begin
  FUserInterface := AValue;
end;

procedure TCrossData.SetUserObject(const AValue: TCore_Object);
begin
  FUserObject := AValue;
end;

{ *
  * UpdateAddr – fills LocalAddr and LocalPort by calling getsockname.
}
procedure TCrossData.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetSockName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen,
      FLocalAddr, FLocalPort);
end;

{ *
  * TAbstractCrossListen – constructor: store family/type/protocol.
}
constructor TAbstractCrossListen.Create(AOwner: ICrossSocket; AListenSocket: THandle;
  AFamily, ASockType, AProtocol: Integer);
begin
  inherited Create(AOwner, AListenSocket);

  FFamily := AFamily;
  FSockType := ASockType;
  FProtocol := AProtocol;
  FClosed := 0;
end;

{ *
  * Close – mark closed and close the underlying socket.
}
procedure TAbstractCrossListen.Close;
begin
  if FClosed = 1 then Exit;
  FClosed := 1;

  if (FSocket <> INVALID_HANDLE_VALUE__) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerListenEnd(Self);
    FSocket := INVALID_HANDLE_VALUE__;
  end;
end;

function TAbstractCrossListen.GetFamily: Integer;
begin
  Result := FFamily;
end;

function TAbstractCrossListen.GetIsClosed: Boolean;
begin
  Result := (FClosed = 1);
end;

function TAbstractCrossListen.GetProtocol: Integer;
begin
  Result := FProtocol;
end;

function TAbstractCrossListen.GetSockType: Integer;
begin
  Result := FSockType;
end;

function TAbstractCrossListen.GetUIDTag: Byte;
begin
  Result := UID_LISTEN;
end;

{ *
  * TAbstractCrossConnection – constructor: set connect type and status.
}
constructor TAbstractCrossConnection.Create(AOwner: ICrossSocket;
  AClientSocket: THandle; AConnectType: TConnectType);
begin
  inherited Create(AOwner, AClientSocket);

  FConnectType := AConnectType;
  ConnectStatus := csUnknown;
end;

procedure TAbstractCrossConnection.SetConnectStatus(const Value: TConnectStatus);
begin
  _SetConnectStatus(Value);
end;

function TAbstractCrossConnection.ConnectionIntf: TCore_Object;
begin
  Result := Self;
end;

{ *
  * Close – immediately close socket and trigger disconnect.
}
procedure TAbstractCrossConnection.Close;
begin
  if TConnectStatus(FConnectStatus) = csClosed then exit;
  _SetConnectStatus(csClosed);

  if (FSocket <> INVALID_HANDLE_VALUE__) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerDisconnected(Self);
    FSocket := INVALID_HANDLE_VALUE__;
  end;
end;

{ *
  * Disconnect – gracefully shutdown the socket (send FIN).
}
procedure TAbstractCrossConnection.Disconnect;
begin
  if (ConnectStatus in [csDisconnected, csClosed]) then Exit;
  _SetConnectStatus(csDisconnected);

  TSocketAPI.Shutdown(FSocket, 2);
end;

function TAbstractCrossConnection.GetConnectStatus: TConnectStatus;
begin
  Result := TConnectStatus(FConnectStatus);
end;

function TAbstractCrossConnection.GetConnectType: TConnectType;
begin
  Result := FConnectType;
end;

function TAbstractCrossConnection.GetIsClosed: Boolean;
begin
  Result := (GetConnectStatus = csClosed);
end;

function TAbstractCrossConnection.GetPeerAddr: SystemString;
begin
  Result := FPeerAddr;
end;

function TAbstractCrossConnection.GetPeerPort: Word;
begin
  Result := FPeerPort;
end;

function TAbstractCrossConnection.GetUIDTag: Byte;
begin
  Result := UID_CONNECTION;
end;

{ *
  * SendBuf – public entry point; calls DirectSend.
}
procedure TAbstractCrossConnection.SendBuf(ABuffer: Pointer; ACount: Integer;
  const ACallback: TProc_ICrossConnection_Boolean);
begin
  DirectSend(ABuffer, ACount, ACallback);
end;

{ *
  * UpdateAddr – also fetch peer address/port via getpeername.
}
procedure TAbstractCrossConnection.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  inherited;

  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetPeerName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen, FPeerAddr, FPeerPort);
end;

function TAbstractCrossConnection._SetConnectStatus(
  const AStatus: TConnectStatus): TConnectStatus;
begin
  FConnectStatus := Integer(AStatus);
  Result := TConnectStatus(FConnectStatus);
end;

{ *
  * DirectSend – wraps the engine's Send method with a bridge callback.
  * The bridge releases itself after the callback fires.
}
procedure TAbstractCrossConnection.DirectSend(ABuffer: Pointer; ACount: Integer;
  const ACallback: TProc_ICrossConnection_Boolean);
var
  LConnection: ICrossConnection;
  bridge_: TDirectSend_Bridge_;
begin
  LConnection := Self as ICrossConnection;

  if (FSocket = INVALID_HANDLE_VALUE__)
    or IsClosed then
    begin
      if Assigned(ACallback) then
          ACallback(LConnection, False);
      Exit;
    end;

  bridge_ := TDirectSend_Bridge_.Create;
  bridge_.FOwner := FOwner;
  bridge_.LBuffer := ABuffer;
  bridge_.ACount := ACount;
  bridge_.ACallback := ACallback;
  FOwner.Send(LConnection, bridge_.LBuffer, bridge_.ACount, bridge_.Do_CallBack);
end;

procedure TDirectSend_Bridge_.Do_CallBack(AConnection: ICrossConnection; ASuccess: Boolean);
begin
  if ASuccess then
    (FOwner as TAbstractCrossSocket).TriggerSent(AConnection, LBuffer, ACount);

 if Assigned(ACallback) then
   begin
     try
       ACallback(AConnection, ASuccess);
     except
     end;
   end;
  DisposeObject(Self);
end;

end.
 
