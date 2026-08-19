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
{
  * ****************************************************************************
  * Z.Net - High-performance, cross-platform network communication framework
  *
  * ============================================================================
  * DEPENDENCIES (uses clause)
  * ============================================================================
  * This unit relies on the following core libraries from the Z framework:
  *
  *   Z.Core                                      - base object model, threading primitives
  *   Z.PascalStrings, Z.UPascalStrings           - string types and manipulation
  *   Z.HashList.Templet                          - generic hash/list templates
  *   Z.ListEngine                                - advanced list containers
  *   Z.UnicodeMixedLib                           - mixed-encoding string helpers
  *   Z.Status                                    - global debug/status logging
  *   Z.DFE                                       - Data Frame Exchange (binary serialisation)
  *   Z.MemoryStream                              - memory stream enhancements
  *   Z.Cipher                                    - encryption, hashing, key management
  *   Z.Notify                                    - notification / callback infrastructure
  *   Z.Cadencer                                  - time-based event scheduler
  *   Z.ZDB2                                      - ZDB2 database engine (used for swap space)
  *
  * ============================================================================
  * KEY FUNCTIONALITY
  * ============================================================================
  * This unit provides a complete, scalable, and secure networking stack suitable
  * for client-server and peer-to-peer applications. It supports multiple data
  * carriers and is optimised for high throughput and low latency.
  *
  * Core features:
  *   - Rich command-based protocol with synchronous, asynchronous,
  *     and fire-and-forget variants.
  *   - Multiple data payload types:
  *       - Console strings (plain text / UTF-8)
  *       - DFE streams (structured binary data)
  *       - Direct (no-reply) commands for one-way messaging
  *       - Big streams (e.g., file transfers) with fragmentation
  *         and flow control
  *       - Complete buffers (atomic blocks) with optional compression
  *         and disk swapping
  *   - Built-in encryption (multiple ciphers, CBC mode, fast instance reuse)
  *   - Built-in compression (ZLib) for payloads and complete buffers
  *   - Reliable ordered packet layer (Sequence Packet model) over
  *     unreliable transports (e.g., UDP) with automatic retransmission
  *     and acknowledgment
  *   - P2P Virtual Machine (P2PVM) overlay for NAT traversal and logical
  *     tunnelling over existing connections
  *   - StableIO - persistent session layer that survives reconnections
  *   - HPC (High-Performance Computing) - thread-pool based command execution
  *     for CPU-intensive tasks without blocking the main loop
  *   - Automated P2PVM service discovery and tunnel establishment
  *   - Extensive statistics, monitoring, and debugging hooks
  *
  * ============================================================================
  * CRITICAL SUBSYSTEMS (key classes)
  * ============================================================================
  *   TPeerIO              - per-connection state machine; handles send/receive
  *                          queues, big-stream reassembly, complete-buffer
  *                          assembly, and sequence-packet reliability.
  *   TZNet                - base framework; command registration, IO management,
  *                          progress engine, P2PVM integration.
  *   TZNet_Server         - concrete server implementation; manages incoming
  *                          connections, broadcasting, and per-IO sends.
  *   TZNet_Client         - concrete client implementation; manages single
  *                          connection, synchronous/asynchronous connect, and
  *                          server state synchronisation.
  *   TZNet_P2PVM          - virtual network overlay; provides P2P connectivity
  *                          over an existing IO, with authentication, listening,
  *                          and virtual IO routing.
  *   TZNet_WithP2PVM_Server - server variant that can be exposed over P2PVM.
  *   TZNet_WithP2PVM_Client - client variant that connects over P2PVM; supports
  *                            cloning to create multiple virtual channels.
  *   TZNet_StableServer/Client - stable session layer; maintains connection
  *                               state across physical disconnections.
  *   THPC_Stream / THPC_Console etc. - task objects for thread-pool execution.
  *
  * ============================================================================
  * DESIGN PHILOSOPHY
  * ============================================================================
  *   - Asynchronous, non-blocking I/O with a single-threaded progress loop
  *     (all operations are driven by repeated calls to Progress()).
  *   - Zero-copy buffer handling where possible.
  *   - Modular architecture with clear separation between physical transport,
  *     reliable framing, command protocol, and application logic.
  *   - Extensible via callbacks (C-style, methods, anonymous/nested) and
  *     user-definable objects attached to each IO.
  *   - Secure by default - authentication, encryption, and hash verification
  *     are built into the protocol.
  *
  * ============================================================================
  * NOTES
  * ============================================================================
  *   - The framework is used in game servers, real-time data distribution,
  *     file transfer, and distributed computing systems.
  *   - It is designed to run on both FPC (Free Pascal) and Delphi, with
  *     conditionals for platform-specific features.
  *   - Many constants and defaults can be overridden at runtime via the
  *     properties of TZNet and its derivatives.
  *   - The implementation is highly performant but also memory-conscious,
  *     offering optional disk swapping for large data items.
  *
  * ****************************************************************************
}
unit Z.Net;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Classes, SysUtils, Variants, TypInfo,
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ELSE FPC}
  System.IOUtils,
{$ENDIF FPC}
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.HashList.Templet, Z.ListEngine, Z.UnicodeMixedLib, Z.Status,
  Z.DFE, Z.MemoryStream, Z.Cipher, Z.Notify, Z.Cadencer, Z.ZDB2;

{$REGION 'base Decl'}


{
  * Forward declarations of core classes and interfaces used throughout the unit.
  * These allow circular references to be resolved at compile time.
}
type
  TPeerIO = class; { Core per-connection state machine. }
  TZNet = class; { Base network framework class. }
  TStream_Event_Bridge = class; { Stream-oriented event bridge for command callbacks. }
  TConsole_Event_Bridge = class; { Console-oriented event bridge for command callbacks. }
  TZNet_WithP2PVM_Server = class; { Server that can be exposed over a P2PVM tunnel. }
  TZNet_WithP2PVM_Client = class; { Client that connects over a P2PVM tunnel. }
  TZNet_Progress = class; { Progress event attached to a TZNet instance. }
  TZNet_Progress_Class = class of TZNet_Progress;
  TCommandCompleteBuffer_NoWait_Bridge = class; { Bridge for no-wait complete-buffer commands. }
  TCompleteBuffer_Stream_Event_Bridge = class; { Event bridge for complete-buffer stream commands. }

  TIPV4 = array [0 .. 3] of Byte; { IPv4 address as 4 bytes. }
  PIPV4 = ^TIPV4;
  TIPV6 = array [0 .. 7] of Word; { IPv6 address as 8 words (16 bytes). }
  PIPV6 = ^TIPV6;

  {
    * Callback type: Method-style console command result handler.
    * Triggered by TZNet Command Dispatcher on response.
    * Purpose: Handle successful console command result and access instance state.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Result_: The response string from the remote peer.
  }
  TOnConsole_M = procedure(Sender: TPeerIO; Result_: SystemString) of object;

  {
    * Callback type: Method-style console command result handler with parameters.
    * Triggered by TZNet Command Dispatcher on response.
    * Purpose: Process console command result with custom parameters for complex business context.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Param1: User-defined pointer parameter passed during send.
    * @Param Param2: User-defined object parameter passed during send.
    * @Param SendData: The original data that was sent.
    * @Param Result_: The response string from the remote peer.
  }
  TOnConsoleParam_M = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString) of object;

  {
    * Callback type: Method-style console command failure handler.
    * Triggered by TZNet Command Dispatcher on timeout or error.
    * Purpose: Notify console command failure and carry original sent data for retry logic.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Param1: User-defined pointer parameter passed during send.
    * @Param Param2: User-defined object parameter passed during send.
    * @Param SendData: The original data that was sent.
  }
  TOnConsoleFailed_M = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString) of object;

  {
    * Callback type: Method-style stream command result handler.
    * Triggered by TZNet Command Dispatcher on response.
    * Purpose: Handle successful stream command result and parse received payload.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Result_: The response DFE (Data Frame Exchange) containing structured data.
  }
  TOnStream_M = procedure(Sender: TPeerIO; Result_: TDFE) of object;

  {
    * Callback type: Method-style stream command result handler with parameters.
    * Triggered by TZNet Command Dispatcher on response.
    * Purpose: Process stream command result with parameters for large or chunked data transfers.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Param1: User-defined pointer parameter passed during send.
    * @Param Param2: User-defined object parameter passed during send.
    * @Param SendData: The original data that was sent.
    * @Param Result_: The response DFE containing structured data.
  }
  TOnStreamParam_M = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE) of object;

  {
    * Callback type: Method-style stream command failure handler.
    * Triggered by TZNet Command Dispatcher on timeout or error.
    * Purpose: Notify stream command failure and carry original payload for recovery.
    * @Param Sender: The IO connection that initiated the command.
    * @Param Param1: User-defined pointer parameter passed during send.
    * @Param Param2: User-defined object parameter passed during send.
    * @Param SendData: The original DFE that was sent.
  }
  TOnStreamFailed_M = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE) of object;

  {
    * Callback type: C-style simple state change handler (no object).
    * Triggered by Connection Manager (TZNet/TPeerIO).
    * Purpose: Monitor global or basic connection state transitions such as online/offline.
    * @Param State: True if connected/active, False if disconnected/inactive.
  }
  TOnState_C = procedure(const State: Boolean);

  {
    * Callback type: Method-style state change handler (with object).
    * Triggered by Connection Manager (TZNet/TPeerIO).
    * Purpose: Notify object-level state change and update UI or business logic accordingly.
    * @Param State: True if connected/active, False if disconnected/inactive.
  }
  TOnState_M = procedure(const State: Boolean) of object;

  {
    * Callback type: C-style IO state change handler.
    * Triggered by TPeerIO State Machine.
    * Purpose: Monitor specific connection IO state transitions including handshake completion,
    *          disconnect, or keepalive heartbeat.
    * @Param P_IO: The IO connection whose state changed.
    * @Param State: True if connected/active, False if disconnected/inactive.
  }
  TOnIOState_C = procedure(P_IO: TPeerIO; State: Boolean);

  {
    * Callback type: Method-style IO state change handler.
    * Triggered by TPeerIO State Machine.
    * Purpose: Notify object-level IO state change for multi-connection context management.
    * @Param P_IO: The IO connection whose state changed.
    * @Param State: True if connected/active, False if disconnected/inactive.
  }
  TOnIOState_M = procedure(P_IO: TPeerIO; State: Boolean) of object;

  {
    * Callback type: C-style parameterized state handler.
    * Triggered by Custom State Manager or Bridge Engine.
    * Purpose: Pass dual-parameter context alongside state change for cross-module event routing.
    * @Param Param1: First user-defined parameter.
    * @Param Param2: Second user-defined parameter.
    * @Param State: The state value (True/False).
  }
  TOnParamState_C = procedure(Param1: Pointer; Param2: TObject; const State: Boolean);

  {
    * Callback type: Method-style parameterized state handler.
    * Triggered by Custom State Manager or Bridge Engine.
    * Purpose: Object-level parameterized state change for plugin or modular architecture integration.
    * @Param Param1: First user-defined parameter.
    * @Param Param2: Second user-defined parameter.
    * @Param State: The state value (True/False).
  }
  TOnParamState_M = procedure(Param1: Pointer; Param2: TObject; const State: Boolean) of object;

  {
    * Callback type: C-style simple notification (no parameters, no object).
    * Triggered by Framework Async Task Queue or Background Thread.
    * Purpose: Deliver lightweight parameterless notification to decouple heavy operations from main IO thread.
  }
  TOnNotify_C = procedure();

  {
    * Callback type: Method-style simple notification.
    * Triggered by Framework Async Task Queue or Background Thread.
    * Purpose: Object-level parameterless notification allowing safe access to instance members during async execution.
  }
  TOnNotify_M = procedure() of object;

  {
    * Callback type: C-style data notification.
    * Triggered by Data Distributor or Message Bus.
    * Purpose: Notify arrival of generic raw data for non-command stream processing.
    * @Param data: The data object being delivered.
  }
  TOnDataNotify_C = procedure(data: TCore_Object);

  {
    * Callback type: Method-style data notification.
    * Triggered by Data Distributor or Message Bus.
    * Purpose: Object-level data arrival notification enabling in-class aggregation or routing logic.
    * @Param data: The data object being delivered.
  }
  TOnDataNotify_M = procedure(data: TCore_Object) of object;

  {
    * Callback type: C-style IO notification.
    * Triggered by TPeerIO Connection Manager.
    * Purpose: Notify activity or idle state of specific connection for heartbeat detection or keepalive scheduling.
    * @Param P_IO: The IO connection that triggered the notification.
  }
  TOnIONotify_C = procedure(P_IO: TPeerIO);

  {
    * Callback type: Method-style IO notification.
    * Triggered by TPeerIO Connection Manager.
    * Purpose: Object-level IO activity notification supporting concurrent multi-connection management.
    * @Param P_IO: The IO connection that triggered the notification.
  }
  TOnIONotify_M = procedure(P_IO: TPeerIO) of object;

  {
    * Callback type: C-style progress background notification.
    * Triggered by HPC Background Progress Engine or Timer.
    * Purpose: Provide periodic background progress polling for non-blocking task status updates.
  }
  TOnProgressBackground_C = procedure();

  {
    * Callback type: Method-style progress background notification.
    * Triggered by HPC Background Progress Engine or Timer.
    * Purpose: Object-level periodic progress polling to check instance task state and advance logic.
  }
  TOnProgressBackground_M = procedure() of object;

  {
    * Callback type: C-style stream event bridge event handler.
    * Triggered by Stream Event Bridge Engine.
    * Purpose: Intercept or route stream data between two connections and process bridged payload.
    * @Param Sender: The bridge instance that triggered the event.
    * @Param SourceIO: The IO connection where the data originated.
    * @Param BridgeIO: The IO connection where the data is being bridged to.
    * @Param Result_: The DFE data being bridged.
  }
  TOnStream_Event_Bridge_Event_C = procedure(Sender: TStream_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: TDFE);

  {
    * Callback type: Method-style stream event bridge event handler.
    * Triggered by Stream Event Bridge Engine.
    * Purpose: Object-level stream routing interception allowing dynamic modification of bridge behavior via instance config.
    * @Param Sender: The bridge instance that triggered the event.
    * @Param SourceIO: The IO connection where the data originated.
    * @Param BridgeIO: The IO connection where the data is being bridged to.
    * @Param Result_: The DFE data being bridged.
  }
  TOnStream_Event_Bridge_Event_M = procedure(Sender: TStream_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: TDFE) of object;

  {
    * Callback type: C-style console event bridge event handler.
    * Triggered by Console Event Bridge Engine.
    * Purpose: Intercept or route console string commands between two connections for protocol translation or forwarding.
    * @Param Sender: The bridge instance that triggered the event.
    * @Param SourceIO: The IO connection where the command originated.
    * @Param BridgeIO: The IO connection where the command is being bridged to.
    * @Param Result_: The console string being bridged.
  }
  TOnConsole_Event_Bridge_Event_C = procedure(Sender: TConsole_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: SystemString);

  {
    * Callback type: Method-style console event bridge event handler.
    * Triggered by Console Event Bridge Engine.
    * Purpose: Object-level console command routing interception supporting instance-based filtering or logging.
    * @Param Sender: The bridge instance that triggered the event.
    * @Param SourceIO: The IO connection where the command originated.
    * @Param BridgeIO: The IO connection where the command is being bridged to.
    * @Param Result_: The console string being bridged.
  }
  TOnConsole_Event_Bridge_Event_M = procedure(Sender: TConsole_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: SystemString) of object;

  {
    * Callback type: C-style P2PVM clone connection event handler.
    * Triggered by P2P Virtual Network Overlay Manager.
    * Purpose: Notify successful NAT traversal and tunnel establishment for virtual channel initialization.
    * @Param Sender: The cloned client instance that successfully connected.
  }
  TOnP2PVM_CloneConnectEvent_C = procedure(Sender: TZNet_WithP2PVM_Client);

  {
    * Callback type: Method-style P2PVM clone connection event handler.
    * Triggered by P2P Virtual Network Overlay Manager.
    * Purpose: Object-level P2P tunnel connection notification enabling multi-channel state maintenance in class.
    * @Param Sender: The cloned client instance that successfully connected.
  }
  TOnP2PVM_CloneConnectEvent_M = procedure(Sender: TZNet_WithP2PVM_Client) of object;

  {
    * Callback type: C-style stream command handler.
    * Triggered by TPeerIO Protocol Parser on stream command packet arrival.
    * Purpose: Execute stream command business logic and populate response payload via OutData parameter.
    * @Param Sender: The IO connection that received the command.
    * @Param InData: The input DFE containing the command payload.
    * @Param OutData: The output DFE to be filled with the response data.
  }
  TOnCommandStream_C = procedure(Sender: TPeerIO; InData, OutData: TDFE);

  {
    * Callback type: C-style console command handler.
    * Triggered by TPeerIO Protocol Parser on console command packet arrival.
    * Purpose: Execute console command business logic and return synchronous response string.
    * @Param Sender: The IO connection that received the command.
    * @Param InData: The input string containing the command data.
    * @Param OutData: The output string to be filled with the response (var parameter).
  }
  TOnCommandConsole_C = procedure(Sender: TPeerIO; InData: SystemString; var OutData: SystemString);

  {
    * Callback type: C-style direct stream notification handler (no reply).
    * Triggered by TPeerIO Protocol Parser on direct stream packet arrival.
    * Purpose: Process one-way stream data push without reply, suitable for real-time video or telemetry feeds.
    * @Param Sender: The IO connection that received the data.
    * @Param InData: The input DFE containing the data.
  }
  TOnCommandStreamNotify_C = procedure(Sender: TPeerIO; InData: TDFE);

  {
    * Callback type: C-style direct console notification handler (no reply).
    * Triggered by TPeerIO Protocol Parser on direct console packet arrival.
    * Purpose: Process one-way string command without reply, suitable for live logs or status broadcasts.
    * @Param Sender: The IO connection that received the data.
    * @Param InData: The input string containing the data.
  }
  TOnCommandConsoleNotify_C = procedure(Sender: TPeerIO; InData: SystemString);

  {
    * Callback type: C-style big-stream handler.
    * Triggered by TPeerIO Big Stream Handler on chunk or complete packet arrival.
    * Purpose: Handle large file or data stream reception progress and completion state for resume logic.
    * @Param Sender: The IO connection that received the stream.
    * @Param InData: The stream data being received.
    * @Param BigStreamTotal: The total size of the stream in bytes.
    * @Param BigStreamCompleteSize: The number of bytes received so far.
  }
  TOnCommandBigStream_C = procedure(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);

  {
    * Callback type: C-style complete-buffer handler.
    * Triggered by TPeerIO Complete Buffer Reassembler after sequence validation passes.
    * Purpose: Process fully reassembled complete data block after network fragmentation and ordering.
    * @Param Sender: The IO connection that received the buffer.
    * @Param InData: Pointer to the reassembled data buffer.
    * @Param DataSize: The size of the data buffer in bytes.
  }
  TOnCommandCompleteBuffer_C = procedure(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);

  {
    * Callback type: Method-style stream command handler.
    * Triggered by TPeerIO Protocol Parser on stream command packet arrival.
    * Purpose: Object-level stream command processing enabling multi-stream state management via instance fields.
    * @Param Sender: The IO connection that received the command.
    * @Param InData: The input DFE containing the command payload.
    * @Param OutData: The output DFE to be filled with the response data.
  }
  TOnCommandStream_M = procedure(Sender: TPeerIO; InData, OutData: TDFE) of object;

  {
    * Callback type: Method-style console command handler.
    * Triggered by TPeerIO Protocol Parser on console command packet arrival.
    * Purpose: Object-level console command processing allowing command context and response cache maintenance in class.
    * @Param Sender: The IO connection that received the command.
    * @Param InData: The input string containing the command data.
    * @Param OutData: The output string to be filled with the response (var parameter).
  }
  TOnCommandConsole_M = procedure(Sender: TPeerIO; InData: SystemString; var OutData: SystemString) of object;

  {
    * Callback type: Method-style direct stream notification handler (no reply).
    * Triggered by TPeerIO Protocol Parser on direct stream packet arrival.
    * Purpose: Object-level one-way stream processing for real-time data aggregation or state machine updates.
    * @Param Sender: The IO connection that received the data.
    * @Param InData: The input DFE containing the data.
  }
  TOnCommandStreamNotify_M = procedure(Sender: TPeerIO; InData: TDFE) of object;

  {
    * Callback type: Method-style direct console notification handler (no reply).
    * Triggered by TPeerIO Protocol Parser on direct console packet arrival.
    * Purpose: Object-level one-way command processing for event dispatching or broadcast log recording.
    * @Param Sender: The IO connection that received the data.
    * @Param InData: The input string containing the data.
  }
  TOnCommandConsoleNotify_M = procedure(Sender: TPeerIO; InData: SystemString) of object;

  {
    * Callback type: Method-style big-stream handler.
    * Triggered by TPeerIO Big Stream Handler on chunk or complete packet arrival.
    * Purpose: Object-level big stream processing for transfer state management with progress tracking or cache pools.
    * @Param Sender: The IO connection that received the stream.
    * @Param InData: The stream data being received.
    * @Param BigStreamTotal: The total size of the stream in bytes.
    * @Param BigStreamCompleteSize: The number of bytes received so far.
  }
  TOnCommandBigStream_M = procedure(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64) of object;

  {
    * Callback type: Method-style complete-buffer handler.
    * Triggered by TPeerIO Complete Buffer Reassembler after sequence validation passes.
    * Purpose: Object-level complete block processing for routing reassembled business data within class scope.
    * @Param Sender: The IO connection that received the buffer.
    * @Param InData: Pointer to the reassembled data buffer.
    * @Param DataSize: The size of the data buffer in bytes.
  }
  TOnCommandCompleteBuffer_M = procedure(Sender: TPeerIO; InData: PByte; DataSize: NativeInt) of object;

  {
    * Callback type: C-style progress event handler.
    * Triggered by TZNet Progress Engine Instance.
    * Purpose: Deliver async task progress update event for UI refresh or background synchronization.
    * @Param Sender: The TZNet_Progress instance that triggered the event.
  }
  TZNet_Progress_OnEvent_C = procedure(Sender: TZNet_Progress);

  {
    * Callback type: Method-style progress event handler.
    * Triggered by TZNet Progress Engine Instance.
    * Purpose: Object-level progress update allowing safe access to task context and configuration in class.
    * @Param Sender: The TZNet_Progress instance that triggered the event.
  }
  TZNet_Progress_OnEvent_M = procedure(Sender: TZNet_Progress) of object;

  {
    * Callback type: C-style automated P2PVM client connection done handler.
    * Triggered by Automated P2PVM Discovery Module on tunnel ready or timeout.
    * Purpose: Notify client virtual network channel is operational and pass connection handle for subsequent communication.
    * @Param Sender: The TZNet instance that initiated the P2PVM connection.
    * @Param P_IO: The IO connection that was established.
  }
  TOnAutomatedP2PVMClientConnectionDone_C = procedure(Sender: TZNet; P_IO: TPeerIO);

  {
    * Callback type: Method-style automated P2PVM client connection done handler.
    * Triggered by Automated P2PVM Discovery Module on tunnel ready or timeout.
    * Purpose: Object-level P2P channel ready notification supporting auto-tunnel state maintenance in class.
    * @Param Sender: The TZNet instance that initiated the P2PVM connection.
    * @Param P_IO: The IO connection that was established.
  }
  TOnAutomatedP2PVMClientConnectionDone_M = procedure(Sender: TZNet; P_IO: TPeerIO) of object;

  {
    * Callback type: Progress free event.
    * Triggered by TZNet Progress Engine during destruction or release.
    * Purpose: Notify resource cleanup and garbage collection for associated async tasks or memory caches.
    * @Param Sender: The TZNet_Progress instance being freed.
  }
  TZNet_Progress_Free_OnEvent = procedure(Sender: TZNet_Progress) of object;

  {
    * Callback type: C-style complete-buffer bridge stream command handler.
    * Triggered by Non-blocking Complete Buffer Bridge Component.
    * Purpose: Process stream bridging data without waiting for reassembly and handle in/out payloads.
    * @Param Sender: The bridge component that triggered the event.
    * @Param InData: The input DFE.
    * @Param OutData: The output DFE to be filled with response data.
  }
  TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_C = procedure(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);

  {
    * Callback type: Method-style complete-buffer bridge stream command handler.
    * Triggered by Non-blocking Complete Buffer Bridge Component.
    * Purpose: Object-level non-blocking stream bridge processing enabling instance-based routing or flow control.
    * @Param Sender: The bridge component that triggered the event.
    * @Param InData: The input DFE.
    * @Param OutData: The output DFE to be filled with response data.
  }
  TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_M = procedure(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE) of object;

  {
    * Callback type: C-style complete-buffer stream bridge completion handler.
    * Triggered by Complete Buffer Stream Event Bridge after reassembly completes.
    * Purpose: Notify underlying bridge component that data is fully ordered and pass final payload for consumption.
    * @Param Sender: The event bridge that triggered the event.
    * @Param Source_Bridge: The underlying no-wait bridge that provided the data.
    * @Param BridgeIO: The IO connection where the data is being bridged to.
    * @Param Result_: The fully reassembled DFE data.
  }
  TOnCompleteBuffer_Stream_Event_Bridge_C = procedure(Sender: TCompleteBuffer_Stream_Event_Bridge; Source_Bridge: TCommandCompleteBuffer_NoWait_Bridge; BridgeIO: TPeerIO; Result_: TDFE);

  {
    * Callback type: Method-style complete-buffer stream bridge completion handler.
    * Triggered by Complete Buffer Stream Event Bridge after reassembly completes.
    * Purpose: Object-level reassembly completion notification triggering downstream business logic or state machine transition.
    * @Param Sender: The event bridge that triggered the event.
    * @Param Source_Bridge: The underlying no-wait bridge that provided the data.
    * @Param BridgeIO: The IO connection where the data is being bridged to.
    * @Param Result_: The fully reassembled DFE data.
  }
  TOnCompleteBuffer_Stream_Event_Bridge_M = procedure(Sender: TCompleteBuffer_Stream_Event_Bridge; Source_Bridge: TCommandCompleteBuffer_NoWait_Bridge; BridgeIO: TPeerIO; Result_: TDFE) of object;

{$IFDEF FPC}
  {
    * Nested procedure equivalents for all callback types (FPC only).
    * These allow callbacks to capture local variables from the enclosing scope.
    * Triggered by the same events as their C/M counterparts.
    * Purpose: Same as C/M versions, but with nested/local variable capture support.
  }
  TOnConsole_P = procedure(Sender: TPeerIO; Result_: SystemString) is nested;
  TOnConsoleParam_P = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString) is nested;
  TOnConsoleFailed_P = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString) is nested;
  TOnStream_P = procedure(Sender: TPeerIO; Result_: TDFE) is nested;
  TOnStreamParam_P = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE) is nested;
  TOnStreamFailed_P = procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE) is nested;
  TOnState_P = procedure(const State: Boolean) is nested;
  TOnIOState_P = procedure(P_IO: TPeerIO; State: Boolean) is nested;
  TOnParamState_P = procedure(Param1: Pointer; Param2: TObject; const State: Boolean) is nested;
  TOnNotify_P = procedure() is nested;
  TOnDataNotify_P = procedure(data: TCore_Object) is nested;
  TOnIONotify_P = procedure(P_IO: TPeerIO) is nested;
  TOnStream_Event_Bridge_Event_P = procedure(Sender: TStream_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: TDFE) is nested;
  TOnConsole_Event_Bridge_Event_P = procedure(Sender: TConsole_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: SystemString) is nested;
  TOnP2PVM_CloneConnectEvent_P = procedure(Sender: TZNet_WithP2PVM_Client) is nested;
  TOnCommandStream_P = procedure(Sender: TPeerIO; InData, OutData: TDFE) is nested;
  TOnCommandConsole_P = procedure(Sender: TPeerIO; InData: SystemString; var OutData: SystemString) is nested;
  TOnCommandStreamNotify_P = procedure(Sender: TPeerIO; InData: TDFE) is nested;
  TOnCommandConsoleNotify_P = procedure(Sender: TPeerIO; InData: SystemString) is nested;
  TOnCommandBigStream_P = procedure(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64) is nested;
  TOnCommandCompleteBuffer_P = procedure(Sender: TPeerIO; InData: PByte; DataSize: NativeInt) is nested;
  TZNet_Progress_OnEvent_P = procedure(Sender: TZNet_Progress) is nested;
  TOnAutomatedP2PVMClientConnectionDone_P = procedure(Sender: TZNet; P_IO: TPeerIO) is nested;
  TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_P = procedure(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE) is nested;
  TOnCompleteBuffer_Stream_Event_Bridge_P = procedure(Sender: TCompleteBuffer_Stream_Event_Bridge; Source_Bridge: TCommandCompleteBuffer_NoWait_Bridge; BridgeIO: TPeerIO; Result_: TDFE) is nested;
{$ELSE FPC}
  {
    * Reference-to-procedure equivalents for all callback types (Delphi only).
    * These are anonymous methods that can capture local variables.
    * Triggered by the same events as their C/M counterparts.
    * Purpose: Same as C/M versions, with anonymous method capture support.
  }
  TOnConsole_P = reference to procedure(Sender: TPeerIO; Result_: SystemString);
  TOnConsoleParam_P = reference to procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString);
  TOnConsoleFailed_P = reference to procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString);
  TOnStream_P = reference to procedure(Sender: TPeerIO; Result_: TDFE);
  TOnStreamParam_P = reference to procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
  TOnStreamFailed_P = reference to procedure(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
  TOnState_P = reference to procedure(const State: Boolean);
  TOnIOState_P = reference to procedure(P_IO: TPeerIO; State: Boolean);
  TOnParamState_P = reference to procedure(Param1: Pointer; Param2: TObject; const State: Boolean);
  TOnNotify_P = reference to procedure();
  TOnDataNotify_P = reference to procedure(data: TCore_Object);
  TOnIONotify_P = reference to procedure(P_IO: TPeerIO);
  TOnStream_Event_Bridge_Event_P = reference to procedure(Sender: TStream_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: TDFE);
  TOnConsole_Event_Bridge_Event_P = reference to procedure(Sender: TConsole_Event_Bridge; SourceIO, BridgeIO: TPeerIO; Result_: SystemString);
  TOnP2PVM_CloneConnectEvent_P = reference to procedure(Sender: TZNet_WithP2PVM_Client);
  TOnCommandStream_P = reference to procedure(Sender: TPeerIO; InData, OutData: TDFE);
  TOnCommandConsole_P = reference to procedure(Sender: TPeerIO; InData: SystemString; var OutData: SystemString);
  TOnCommandStreamNotify_P = reference to procedure(Sender: TPeerIO; InData: TDFE);
  TOnCommandConsoleNotify_P = reference to procedure(Sender: TPeerIO; InData: SystemString);
  TOnCommandBigStream_P = reference to procedure(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64);
  TOnCommandCompleteBuffer_P = reference to procedure(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
  TZNet_Progress_OnEvent_P = reference to procedure(Sender: TZNet_Progress);
  TOnAutomatedP2PVMClientConnectionDone_P = reference to procedure(Sender: TZNet; P_IO: TPeerIO);
  TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_P = reference to procedure(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);
  TOnCompleteBuffer_Stream_Event_Bridge_P = reference to procedure(Sender: TCompleteBuffer_Stream_Event_Bridge; Source_Bridge: TCommandCompleteBuffer_NoWait_Bridge; BridgeIO: TPeerIO; Result_: TDFE);
{$ENDIF FPC}

  {
    * TIO_ID_Pool: Pool of IO IDs (Cardinals).
    * Uses TBigList to store and manage connection IDs with recycling capability.
    * Each TPeerIO instance is assigned a unique ID from this pool or a generator.
  }
  TIO_ID_Pool = class(TBigList<Cardinal>)
  end;

  {
    * TIO_ID_List: Simple list of IO IDs.
    * Uses TGenericsList for basic storage and iteration of connection identifiers.
  }
  TIO_ID_List = class(TGenericsList<Cardinal>)
  end;

  {
    * TOnStateStruct: Structure holding three styles of state callback.
    * Allows a single event to be handled by C-style, method, or nested procedure.
    * This provides flexibility for different programming styles and scoping needs.
    * @Field On_C: C-style callback.
    * @Field On_M: Method-style callback.
    * @Field On_P: Nested/reference callback.
  }
  TOnStateStruct = record
    On_C: TOnState_C;
    On_M: TOnState_M;
    On_P: TOnState_P;
    procedure Init;
  end;

  POnStateStruct = ^TOnStateStruct;

  {
    * TOnResult_Bridge_Templet: Base class for bridging callbacks.
    * Provides virtual methods for console, stream, and complete-buffer result handling.
    * Subclasses override these to implement custom behaviour.
    * This is the foundation for the bridge pattern used throughout the framework.
    * @Example:
    *   type
    *     TMyBridge = class(TOnResult_Bridge_Templet)
    *       procedure DoStreamEvent(Sender: TPeerIO; Result_: TDFE); override;
    *     end;
    *   // Then:
    *   Bridge := TMyBridge.Create;
    *   // The bridge will automatically receive and process stream results.
  }
  TOnResult_Bridge_Templet = class(TCore_Object_Intermediate)
  public
    procedure DoConsoleEvent(Sender: TPeerIO; Result_: SystemString); virtual;
    procedure DoConsoleParamEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString); virtual;
    procedure DoConsoleFailedEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString); virtual;
    procedure DoStreamEvent(Sender: TPeerIO; Result_: TDFE); virtual;
    procedure DoStreamParamEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE); virtual;
    procedure DoStreamFailedEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE); virtual;
    procedure DoCompleteBufferStreamEvent(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE); virtual;
  end;

  {
    * TOnResult_Bridge: Concrete bridge implementation.
    * Provides a ready-to-use bridge instance. Can be extended or used directly.
  }
  TOnResult_Bridge = class(TOnResult_Bridge_Templet)
  public
    constructor Create;
    destructor Destroy; override;
  end;

  TOnResultBridge = TOnResult_Bridge;

  {
    * TProgress_Bridge: Bridge that attaches a progress callback to a TZNet instance.
    * Used to receive periodic progress notifications from the framework.
    * @Example:
    *   var Bridge: TProgress_Bridge;
    *   begin
    *     Bridge := TProgress_Bridge.Create(MyNet);
    *     // Override Progress method to handle progress events.
    *   end;
  }
  TProgress_Bridge = class(TCore_Object_Intermediate)
  private
    procedure DoFree(Sender: TZNet_Progress);
  public
    Framework: TZNet; { Target framework. Assigned by constructor. }
    ProgressInstance: TZNet_Progress; { Progress event instance. Created by constructor. }
    constructor Create(Framework_: TZNet); virtual;
    destructor Destroy; override;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  {
    * TState_Param_Bridge: Bridges a parameterised state callback.
    * Holds user parameters and invokes the appropriate callback when the state changes.
    * Automatically frees itself after delivery.
    * @Example:
    *   Bridge := TState_Param_Bridge.Create;
    *   Bridge.Param1 := MyPointer;
    *   Bridge.Param2 := MyObject;
    *   Bridge.OnNotifyC := MyStateHandler;
    *   // When the state changes, DoStateResult is called with the parameters.
  }
  TState_Param_Bridge = class(TCore_Object_Intermediate)
  public
    OnNotifyC: TOnParamState_C; { C-style callback. Set by caller. }
    OnNotifyM: TOnParamState_M; { Method callback. Set by caller. }
    OnNotifyP: TOnParamState_P; { Nested/reference callback. Set by caller. }
    Param1: Pointer; { User parameter 1. Set by caller. }
    Param2: TObject; { User parameter 2. Set by caller. }
    OnStateMethod: TOnState_M; { Internal state method. Set by constructor. }
    constructor Create; virtual;
    destructor Destroy; override;
    procedure DoStateResult(const State: Boolean);
  end;

  {
    * TCustom_Event_Bridge: Base class for event bridges attached to a specific IO.
    * Monitors a single IO connection and provides a progress hook.
    * @Example:
    *   Bridge := TCustom_Event_Bridge.Create(MyIO);
    *   // Override Progress method to handle IO-specific events.
  }
  TCustom_Event_Bridge = class(TCore_Object_Intermediate)
  private
    procedure DoFree(Sender: TZNet_Progress);
  public
    Framework_: TZNet; { Parent framework. Set by constructor. }
    ID_: Cardinal; { IO identifier. Set by constructor. }
    ProgressInstance: TZNet_Progress; { Progress event. Created by constructor. }
    constructor Create(IO_: TPeerIO); virtual;
    destructor Destroy; override;
    function CheckIO: Boolean; virtual;
    function IO: TPeerIO; virtual;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  TCustomEventBridge = TCustom_Event_Bridge;

  {
    * TStream_Event_Bridge: Stream-oriented event bridge.
    * Attaches to a stream command and provides a callback when the result is received.
    * Supports pause/resume of the result send.
    * @Example:
    *   var Bridge: TStream_Event_Bridge;
    *   begin
    *     Bridge := TStream_Event_Bridge.Create(MyIO);
    *     Bridge.OnResultC := MyStreamHandler;  // Handle the result
    *     // Data will be processed when the response arrives.
    *   end;
  }
  TStream_Event_Bridge = class(TCore_Object_Intermediate)
  private
    procedure Init(IO_: TPeerIO; AutoPause_: Boolean);
    procedure DoFree(Sender: TZNet_Progress);
  public
    Framework_: TZNet; { Parent framework. Set by Init. }
    ID_: Cardinal; { IO identifier. Set by Init. }
    LCMD_: SystemString; { Command name. Set by Init. }
    ProgressInstance: TZNet_Progress; { Progress event. Created by Init. }
    OnResultC: TOnStream_Event_Bridge_Event_C; { C-style callback. Set by user. }
    OnResultM: TOnStream_Event_Bridge_Event_M; { Method callback. Set by user. }
    OnResultP: TOnStream_Event_Bridge_Event_P; { Nested/reference callback. Set by user. }
    AutoPause: Boolean; { Whether to auto-pause result sending. Set by constructor. }
    AutoFree: Boolean; { Whether to auto-free after completion. Set by constructor. }
    constructor Create(IO_: TPeerIO; AutoPause_: Boolean); overload;
    constructor Create(IO_: TPeerIO); overload;
    destructor Destroy; override;
    procedure Pause;
    procedure Play(ResultData_: TDFE);
    procedure DoStreamParamEvent(Sender_: TPeerIO; Param1_: Pointer; Param2_: TObject; SendData_, ResultData_: TDFE); virtual;
    procedure DoStreamFailed(Sender_: TPeerIO; Param1: Pointer; Param2: TObject; SendData_: TDFE); virtual;
    procedure DoStreamEvent(Sender_: TPeerIO; ResultData_: TDFE); virtual;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  {
    * TConsole_Event_Bridge: Console-oriented event bridge.
    * Similar to TStream_Event_Bridge but for console (string) commands.
    * @Example:
    *   var Bridge: TConsole_Event_Bridge;
    *   begin
    *     Bridge := TConsole_Event_Bridge.Create(MyIO);
    *     Bridge.OnResultC := MyConsoleHandler;
    *     // String response will be delivered to the handler.
    *   end;
  }
  TConsole_Event_Bridge = class(TCore_Object_Intermediate)
  private
    procedure Init(IO_: TPeerIO; AutoPause_: Boolean);
    procedure DoFree(Sender: TZNet_Progress);
  public
    Framework_: TZNet; { Parent framework. Set by Init. }
    ID_: Cardinal; { IO identifier. Set by Init. }
    LCMD_: SystemString; { Command name. Set by Init. }
    ProgressInstance: TZNet_Progress; { Progress event. Created by Init. }
    OnResultC: TOnConsole_Event_Bridge_Event_C; { C-style callback. Set by user. }
    OnResultM: TOnConsole_Event_Bridge_Event_M; { Method callback. Set by user. }
    OnResultP: TOnConsole_Event_Bridge_Event_P; { Nested/reference callback. Set by user. }
    AutoPause: Boolean; { Whether to auto-pause result sending. Set by constructor. }
    AutoFree: Boolean; { Whether to auto-free after completion. Set by constructor. }
    constructor Create(IO_: TPeerIO; AutoPause_: Boolean); overload;
    constructor Create(IO_: TPeerIO); overload;
    destructor Destroy; override;
    procedure Pause;
    procedure Play(ResultData_: SystemString);
    procedure DoConsoleParamEvent(Sender_: TPeerIO; Param1_: Pointer; Param2_: TObject; SendData_, ResultData_: SystemString); virtual;
    procedure DoStreamFailed(Sender_: TPeerIO; Param1: Pointer; Param2: TObject; SendData_: SystemString);
    procedure DoConsoleEvent(Sender_: TPeerIO; ResultData_: SystemString); virtual;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  {
    * TCustom_CompleteBuffer_Stream_Bridge: Base bridge for complete-buffer streams.
    * Provides progress monitoring for no-wait complete-buffer operations.
  }
  TCustom_CompleteBuffer_Stream_Bridge = class(TCore_Object_Intermediate)
  private
    procedure DoFree(Sender: TZNet_Progress);
  public
    Bridge: TCommandCompleteBuffer_NoWait_Bridge; { Associated bridge. Set by constructor. }
    ProgressInstance: TZNet_Progress; { Progress event. Created by constructor. }
    constructor Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge); virtual;
    destructor Destroy; override;
    function CheckIO: Boolean; virtual;
    function IO: TPeerIO; virtual;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  {
    * TCompleteBuffer_Stream_Event_Bridge: Event bridge for complete-buffer commands.
    * Handles callbacks for commands registered with RegisterCompleteBuffer_NoWait_Bridge_Stream.
    * @Example:
    *   // Register a bridge command:
    *   Net.RegisterCompleteBuffer_NoWait_Bridge_Stream('myBridgeCmd').OnExecute := MyBridgeHandler;
    *   // Then create a bridge event:
    *   Bridge := TCompleteBuffer_Stream_Event_Bridge.Create(MyBridge);
    *   Bridge.OnResultC := MyCompletionHandler;
  }
  TCompleteBuffer_Stream_Event_Bridge = class(TCore_Object_Intermediate)
  private
    procedure Init(Bridge_: TCommandCompleteBuffer_NoWait_Bridge; AutoPause_: Boolean);
    procedure DoFree(Sender: TZNet_Progress);
  public
    Framework_: TZNet; { Parent framework. Set by Init. }
    Bridge: TCommandCompleteBuffer_NoWait_Bridge; { Source bridge. Set by Init. }
    LCMD_: SystemString; { Command name. Set by Init. }
    ProgressInstance: TZNet_Progress; { Progress event. Created by Init. }
    OnResultC: TOnCompleteBuffer_Stream_Event_Bridge_C; { C-style callback. Set by user. }
    OnResultM: TOnCompleteBuffer_Stream_Event_Bridge_M; { Method callback. Set by user. }
    OnResultP: TOnCompleteBuffer_Stream_Event_Bridge_P; { Nested/reference callback. Set by user. }
    AutoPause: Boolean; { Whether to auto-pause result sending. Set by constructor. }
    AutoFree: Boolean; { Whether to auto-free after completion. Set by constructor. }
    constructor Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge; AutoPause_: Boolean); overload;
    constructor Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge); overload;
    destructor Destroy; override;
    procedure Pause;
    procedure Play(ResultData_: TDFE);
    procedure DoStreamEvent(Sender_: TPeerIO; ResultData_: TDFE); virtual;
    procedure Progress(Sender: TZNet_Progress); virtual;
  end;

  {
    * TP2PVM_CloneConnectEventBridge: Bridges clone connection events for P2PVM.
    * Used when creating a clone client via TZNet_WithP2PVM_Client.CloneConnect*.
    * @Example:
    *   var Bridge: TP2PVM_CloneConnectEventBridge;
    *   begin
    *     Bridge := SourceClient.CloneConnectM(MyCloneHandler);
    *     // The handler receives the new clone client when connection is ready.
    *   end;
  }
  TP2PVM_CloneConnectEventBridge = class(TCore_Object_Intermediate)
  private
    OnResultC: TOnP2PVM_CloneConnectEvent_C; { C-style callback. Set by caller. }
    OnResultM: TOnP2PVM_CloneConnectEvent_M; { Method callback. Set by caller. }
    OnResultP: TOnP2PVM_CloneConnectEvent_P; { Nested/reference callback. Set by caller. }
    procedure DoAsyncConnectState(const State: Boolean);
  public
    Source: TZNet_WithP2PVM_Client; { Source client for cloning. Set by constructor. }
    NewClient: TZNet_WithP2PVM_Client; { Newly created clone client. Set during connection. }
    constructor Create(Source_: TZNet_WithP2PVM_Client);
    destructor Destroy; override;
  end;

  {
    * TDoubleTunnel_IO_ID: Record for double-tunnel IO identification.
    * Contains both receive (R) and send (S) tunnel IDs for a single logical connection.
    * Used in double-tunnel scenarios where send and receive use separate channels.
    * @Field R: Receive tunnel ID.
    * @Field S: Send tunnel ID.
  }
  TDoubleTunnel_IO_ID = record
    R, S: Cardinal;
  end;

  TDoubleTunnel_IO_ID_Big_List = class(TBigList<TDoubleTunnel_IO_ID>); { Big list for double-tunnel IO IDs. }

  TDoubleTunnel_IO_ID_List = class(TGenericsList<TDoubleTunnel_IO_ID>) { Generic list for double-tunnel IO IDs with helper. }
  public
    procedure Add_DT_ID(R, S: Cardinal);
  end;
{$ENDREGION 'base Decl'}
{$REGION 'CacheTechnology'}

  TFile_Swap_Space_Stream = class; { A file stream that uses a swap space pool for temporary storage of large data. }

  {
    * TFile_Swap_Space_Pool: Pool managing TFile_Swap_Space_Stream instances.
    * All streams in the pool share a common working directory and are automatically cleaned up.
    * @Field WorkPath: Working directory for swap files. Set by user.
    * @Example:
    *   var Pool: TFile_Swap_Space_Pool;
    *   begin
    *     Pool := TFile_Swap_Space_Pool.Create;
    *     Pool.WorkPath := './temp';
    *     // Streams created using this pool will store temporary files in './temp'.
    *   end;
  }
  TFile_Swap_Space_Pool = class(TCritical_BigList<TFile_Swap_Space_Stream>)
  public
    WorkPath: U_String; { Working directory for swap files. Set by user. }
    constructor Create;
    destructor Destroy; override;
    procedure DoFree(var data: TFile_Swap_Space_Stream); override;
    function CompareData(const Data_1, Data_2: TFile_Swap_Space_Stream): Boolean; override;
    class function RunTime_Pool(): TFile_Swap_Space_Pool;
  end;

  {
    * TFile_Swap_Space_Stream: A file stream that belongs to a swap space pool.
    * Created by Create_BigStream to store large data in temporary files.
    * @Field FOwnerSwapSpace: Owner pool. Set by Create_BigStream.
    * @Field FPoolPtr: Pointer in owner pool. Set by Create_BigStream.
    * @Example:
    *   var Stream: TFile_Swap_Space_Stream;
    *   begin
    *     Stream := TFile_Swap_Space_Stream.Create_BigStream(MyLargeData, MyPool);
    *     // The stream is automatically managed and cleaned up when freed.
    *   end;
  }
  TFile_Swap_Space_Stream = class(TCore_FileStream)
  private
    FOwnerSwapSpace: TFile_Swap_Space_Pool; { Owner pool. Set by Create_BigStream. }
    FPoolPtr: TFile_Swap_Space_Pool.PQueueStruct; { Pointer in owner pool. Set by Create_BigStream. }
  public
    class function Create_BigStream(stream_: TCore_Stream; OwnerSwapSpace_: TFile_Swap_Space_Pool): TFile_Swap_Space_Stream;
    destructor Destroy; override;
  end;

  TZDB2_Swap_Space_Technology_Memory = class; { Forward declaration for ZDB2 swap memory. }

  {
    * TZDB2_Swap_Space_Technology: A ZDB2-based swap space for complete buffers.
    * Uses a ZDB2 database to store large buffers on disk with optional encryption.
    * Provides a persistent, transactional swap area.
    * @Example:
    *   var Swap: TZDB2_Swap_Space_Technology;
    *   begin
    *     Swap := TZDB2_Swap_Space_Technology.RunTime_Pool;
    *     Mem := Swap.Create_Memory(Data, DataSize, False);
    *     // Mem can be used as a persistent memory object backed by the database.
    *   end;
  }
  TZDB2_Swap_Space_Technology = class(TZDB2_Core_Space)
  public
    class var ZDB2_Swap_Space_Pool___: TZDB2_Swap_Space_Technology;
    class var ZDB2_Swap_Space_Pool_Cipher___: TZDB2_Cipher;
  private
    tmp_swap_space_file: U_String; { Temporary database file. Set by constructor. }
    procedure DoNoSpace(Trigger: TZDB2_Core_Space; Siz_: Int64; var retry: Boolean);
  public
    Critical: TCritical; { Synchronisation lock. Created by constructor. }
    constructor Create();
    destructor Destroy; override;
    function Create_Memory(buff: PByte; BuffSiz: NativeInt; BuffProtected_: Boolean): TZDB2_Swap_Space_Technology_Memory;
    class function RunTime_Pool(): TZDB2_Swap_Space_Technology;
  end;

  {
    * TZDB2_Swap_Space_Technology_Memory: A memory view into a ZDB2 swap entry.
    * Allows a large buffer to be stored in the ZDB2 swap space and later retrieved as a TMem64.
    * @Field FOwner: Owner swap space. Set by constructor.
    * @Field FID: Database entry ID. Set by constructor.
    * @Example:
    *   var Mem: TZDB2_Swap_Space_Technology_Memory;
    *   begin
    *     Mem := TZDB2_Swap_Space_Technology_Memory.Create(MySwap, 123);
    *     if Mem.Prepare then  // Load data from the database
    *       UseData(Mem.Memory, Mem.Size);
    *   end;
  }
  TZDB2_Swap_Space_Technology_Memory = class(TMem64)
  private
    FOwner: TZDB2_Swap_Space_Technology; { Owner swap space. Set by constructor. }
    FID: Integer; { Database entry ID. Set by constructor. }
  public
    constructor Create(); overload;
    constructor Create(Owner_: TZDB2_Swap_Space_Technology; ID_: Integer); overload;
    destructor Destroy; override;
    function Prepare: Boolean;
  end;
{$ENDREGION 'CacheTechnology'}
{$REGION 'Queue'}

  {
    * TQueueState: Possible states for a queued command.
    * Determines how the command will be processed and sent.
    * @Enum qsUnknow: Unknown state.
    * @Enum qsSendConsoleCMD: Send a console command and expect a result.
    * @Enum qsSendStreamCMD: Send a stream command and expect a result.
    * @Enum qsSendConsoleNotifyCMD: Send a console notification (no reply expected).
    * @Enum qsSendStreamNotifyCMD: Send a stream notification (no reply expected).
    * @Enum qsSendBigStream: Send a large stream (file transfer).
    * @Enum qsSendCompleteBuffer: Send a complete buffer (atomic data block).
  }
  TQueueState = (
    qsUnknow,
    qsSendConsoleCMD,
    qsSendStreamCMD,
    qsSendConsoleNotifyCMD,
    qsSendStreamNotifyCMD,
    qsSendBigStream,
    qsSendCompleteBuffer
    );

  {
    * TQueueData: A complete command to be sent to a remote peer.
    * Contains all information needed to send a command, including the command name,
    * payload (console string, stream, or buffer), cipher settings, and callback handlers.
    * @Field IP: Remote IP address. Set by NewQueueData.
    * @Field State: Command type. Set by sender.
    * @Field IO_ID: Target IO identifier. Set by NewQueueData.
    * @Field Cmd: Command name. Set by sender.
    * @Field Cipher: Cipher for this command. Set by sender.
    * @Field ConsoleData: Payload for console commands. Set by sender.
    * @Field StreamData: Payload for stream commands. Set by sender.
    * @Field BigStream: Payload for big-stream commands. Set by sender.
    * @Field Buffer: Raw buffer for complete-buffer commands. Set by sender.
    * @Field BufferSize: Size of Buffer. Set by sender.
    * @Field Buffer_Swap_Memory: Swap memory for large buffers. Set by sender.
    * @Field DoneAutoFree: Whether to auto-free payload after send. Set by sender.
    * @Field Param1: User parameter 1. Set by sender.
    * @Field Param2: User parameter 2. Set by sender.
    * @Example:
    *   var Q: PQueueData;
    *   begin
    *     Q := NewQueueData(MyIO);
    *     Q^.State := qsSendConsoleCMD;
    *     Q^.Cmd := 'ping';
    *     Q^.ConsoleData := 'hello';
    *     Q^.OnConsoleM := MyResultHandler;
    *     MyIO.PostQueueData(Q);  // Sends asynchronously
    *   end;
  }
  TQueueData = record
    IP: SystemString;
    State: TQueueState;
    IO_ID: Cardinal;
    Cmd: SystemString;
    Cipher: TCipherSecurity;
    ConsoleData: SystemString;
    OnConsoleM: TOnConsole_M;
    OnConsoleParamM: TOnConsoleParam_M;
    OnConsoleFailedM: TOnConsoleFailed_M;
    OnConsoleP: TOnConsole_P;
    OnConsoleParamP: TOnConsoleParam_P;
    OnConsoleFailedP: TOnConsoleFailed_P;
    StreamData: TMS64;
    OnStreamM: TOnStream_M;
    OnStreamParamM: TOnStreamParam_M;
    OnStreamFailedM: TOnStreamFailed_M;
    OnStreamP: TOnStream_P;
    OnStreamParamP: TOnStreamParam_P;
    OnStreamFailedP: TOnStreamFailed_P;
    BigStreamStartPos: Int64;
    BigStream: TCore_Stream;
    Buffer: PByte;
    BufferSize: NativeInt;
    Buffer_Swap_Memory: TZDB2_Swap_Space_Technology_Memory;
    DoneAutoFree: Boolean;
    Param1: Pointer;
    Param2: TObject;
  end;

  PQueueData = ^TQueueData;

  TQueueData_Pool = class(TOrderStruct<PQueueData>); { FIFO queue for queue data items (non-thread-safe). }
  TCritical_QueueData_Pool = class(TCritical_BigList<PQueueData>); { Thread-safe version of TQueueData_Pool. }
{$ENDREGION 'Queue'}
{$REGION 'Command_Instance'}

  TCommand_base = class(TCore_Object_Intermediate) { Abstract base class for all registered commands. }
  public
  end;

  {
    * TCommandStream: Command that receives and returns a DFE (stream) payload.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   // Register a stream command:
    *   var Cmd: TCommandStream;
    *   begin
    *     Cmd := MyNet.RegisterStream('myStreamCmd');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData, OutData: TDFE)
    *     begin
    *       // Process InData and fill OutData with response
    *       OutData.WriteString('response');
    *     end;
    *   end;
    *   // Then send from client:
    *   MyClient.SendStreamCmd('myStreamCmd', MyData);
  }
  TCommandStream = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandStream_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandStream_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandStream_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData, OutData: TDFE): Boolean;
    function Execute_Complete_Stream(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
    property OnExecute: TOnCommandStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandStream_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandStream_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandConsole: Command that receives and returns a string (console) payload.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandConsole;
    *   begin
    *     Cmd := MyNet.RegisterConsole('ping');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: string; var OutData: string)
    *     begin
    *       OutData := 'pong: ' + InData;
    *     end;
    *   end;
    *   // Send from client:
    *   var Response := MyClient.SendConsoleCmd('ping', 'hello');
  }
  TCommandConsole = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandConsole_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandConsole_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandConsole_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: SystemString; var OutData: SystemString): Boolean;
    property OnExecute: TOnCommandConsole_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandConsole_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandConsole_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandConsole_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandStreamNotify: Command that receives a DFE but sends no reply (fire-and-forget).
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandStreamNotify;
    *   begin
    *     Cmd := MyNet.RegisterStreamNotify('log');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: TDFE)
    *     begin
    *       // Log the data, no reply needed
    *     end;
    *   end;
    *   // Send from client (no response expected):
    *   MyClient.SendStreamNotifyCmd('log', MyData);
  }
  TCommandStreamNotify = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandStreamNotify_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandStreamNotify_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandStreamNotify_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: TDFE): Boolean;
    property OnExecute: TOnCommandStreamNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandStreamNotify_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandStreamNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandStreamNotify_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandConsoleNotify: Command that receives a string but sends no reply (fire-and-forget).
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandConsoleNotify;
    *   begin
    *     Cmd := MyNet.RegisterConsoleNotify('status');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: string)
    *     begin
    *       // Update status, no reply needed
    *     end;
    *   end;
  }
  TCommandConsoleNotify = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandConsoleNotify_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandConsoleNotify_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandConsoleNotify_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: SystemString): Boolean;
    property OnExecute: TOnCommandConsoleNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandConsoleNotify_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandConsoleNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandConsoleNotify_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandBigStream: Command that receives a stream (big data) with progress tracking.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandBigStream;
    *   begin
    *     Cmd := MyNet.RegisterBigStream('upload');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: TCore_Stream; Total, Complete: Int64)
    *     begin
    *       // Stream the file to disk or database
    *       MyFileStream.CopyFrom(InData, Total - Complete);
    *     end;
    *   end;
    *   // Send a large file:
    *   MyClient.SendBigStream('upload', MyFileStream);
  }
  TCommandBigStream = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandBigStream_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandBigStream_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandBigStream_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64): Boolean;
    property OnExecute: TOnCommandBigStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandBigStream_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandBigStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandBigStream_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandCompleteBuffer: Command that receives a raw complete buffer (pre-assembled).
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandCompleteBuffer;
    *   begin
    *     Cmd := MyNet.RegisterCompleteBuffer('rawData');
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: PByte; DataSize: NativeInt)
    *     begin
    *       // Process raw data block
    *       ProcessMyData(InData, DataSize);
    *     end;
    *   end;
  }
  TCommandCompleteBuffer = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandCompleteBuffer_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandCompleteBuffer_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandCompleteBuffer_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
    property OnExecute: TOnCommandCompleteBuffer_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandCompleteBuffer_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandCompleteBuffer_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandCompleteBuffer_P read FOnExecute_P write FOnExecute_P;
  end;

  TCommandCompleteBuffer_StreamNotify = class; { Internal thread class for async decryption of complete buffers. }

  {
    * TCommandCompleteBuffer_StreamNotify_Thread: Thread for asynchronous decryption of complete buffers.
    * Processes data in the background to avoid blocking the main thread.
  }
  TCommandCompleteBuffer_StreamNotify_Thread = class(TCore_Object_Intermediate)
  protected
    Owner: TCommandCompleteBuffer_StreamNotify; { Owner command. Set by constructor. }
    Framework: TZNet; { Parent framework. Set by constructor. }
    ID: Cardinal; { IO identifier. Set by constructor. }
    buff: TMS64; { Buffer to decrypt. Set by constructor. }
    procedure Do_Run_Decrypt_Thread(thSender: TCompute);
    procedure Do_Post_Run(Sender: TN_Post_Execute);
  public
    constructor Create;
    destructor Destroy; override;
  end;

  {
    * TCommandCompleteBuffer_StreamNotify: Variant that decodes the complete buffer into a DFE.
    * Executes synchronously or asynchronously depending on Sync_Decrypt flag.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Field FSync_Decrypt: Whether to decrypt synchronously. Set by user.
    * @Field FDecript_Activted_Thread_Num: Active decryption threads. Managed internally.
    * @Example:
    *   var Cmd: TCommandCompleteBuffer_StreamNotify;
    *   begin
    *     Cmd := MyNet.RegisterCompleteBuffer_StreamNotify('decryptData');
    *     Cmd.Sync_Decrypt := False;  // Process asynchronously
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData: TDFE)
    *     begin
    *       // Process the decrypted data
    *     end;
    *   end;
  }
  TCommandCompleteBuffer_StreamNotify = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandStreamNotify_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandStreamNotify_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandStreamNotify_P; { Nested/reference handler. Set by user. }
    FSync_Decrypt: Boolean; { Whether to decrypt synchronously. Set by user. }
    FDecript_Activted_Thread_Num: Integer; { Active decryption threads. Managed internally. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
    property OnExecute: TOnCommandStreamNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandStreamNotify_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandStreamNotify_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandStreamNotify_P read FOnExecute_P write FOnExecute_P;
    property Sync_Decrypt: Boolean read FSync_Decrypt write FSync_Decrypt;
  end;

  TCommandCompleteBuffer_NoWait_Stream = class; { Data record for no-wait stream commands. }

  {
    * TCommandCompleteBuffer_NoWait_Stream_Data: Data record for no-wait stream commands.
    * Holds callback references and ID for the response handler.
    * @Field ID: IO identifier. Set by sender.
    * @Field OnStreamM: Method callback. Set by sender.
    * @Field OnStreamP: Nested callback. Set by sender.
  }
  TCommandCompleteBuffer_NoWait_Stream_Data = record
    ID: Cardinal;
    OnStreamM: TOnStream_M;
    OnStreamP: TOnStream_P;
    procedure Init();
  end;

  PCommandCompleteBuffer_NoWait_Stream_Data = ^TCommandCompleteBuffer_NoWait_Stream_Data;

  {
    * TCommandCompleteBuffer_NoWait_Stream_Execute_Thread: Thread for executing no-wait stream commands.
    * Runs the command in a background thread to avoid blocking the main loop.
  }
  TCommandCompleteBuffer_NoWait_Stream_Execute_Thread = class(TCore_Object_Intermediate)
  protected
    Owner: TCommandCompleteBuffer_NoWait_Stream; { Owner command. Set by constructor. }
    R_Framework: TZNet; { Receive framework. Set by constructor. }
    R_ID: Cardinal; { Receive IO ID. Set by constructor. }
    S_Framework: TZNet; { Send framework. Set by constructor. }
    S_ID: Cardinal; { Send IO ID. Set by constructor. }
    buff: TMS64; { Buffer to process. Set by constructor. }
    procedure Do_Execute_Thread(thSender: TCompute);
  public
    constructor Create;
    destructor Destroy; override;
  end;

  {
    * TCommandCompleteBuffer_NoWait_Stream: High-speed, non-blocking stream command.
    * Executes without waiting for a reply. Can be run on the main thread or in a background thread.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Field FExecute_In_Thread: Whether to execute in a background thread. Set by user.
    * @Field FExecute_Activted_Thread_Num: Active execution threads. Managed internally.
    * @Example:
    *   var Cmd: TCommandCompleteBuffer_NoWait_Stream;
    *   begin
    *     Cmd := MyNet.RegisterCompleteBuffer_NoWait_Stream('fastData');
    *     Cmd.Execute_In_Thread := True;  // Run in background thread
    *     Cmd.OnExecute := procedure(Sender: TPeerIO; InData, OutData: TDFE)
    *     begin
    *       // Process data, no wait for response
    *     end;
    *   end;
  }
  TCommandCompleteBuffer_NoWait_Stream = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommandStream_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommandStream_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommandStream_P; { Nested/reference handler. Set by user. }
    FExecute_In_Thread: Boolean; { Whether to execute in a background thread. Set by user. }
    FExecute_Activted_Thread_Num: Integer; { Active execution threads. Managed internally. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
    property OnExecute: TOnCommandStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommandStream_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommandStream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommandStream_P read FOnExecute_P write FOnExecute_P;
    property Execute_In_Thread: Boolean read FExecute_In_Thread write FExecute_In_Thread;
  end;

  {
    * TCommandCompleteBuffer_NoWait_Bridge_Stream: Advanced bridge command.
    * Provides pause/resume capability for the result send, allowing the command handler to delay its response.
    * @Field FOnExecute_C: C-style handler. Set by user.
    * @Field FOnExecute_M: Method handler. Set by user.
    * @Field FOnExecute_P: Nested/reference handler. Set by user.
    * @Example:
    *   var Cmd: TCommandCompleteBuffer_NoWait_Bridge_Stream;
    *   begin
    *     Cmd := MyNet.RegisterCompleteBuffer_NoWait_Bridge_Stream('bridgeCmd');
    *     Cmd.OnExecute := procedure(Bridge: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE)
    *     begin
    *       // Process data
    *       Bridge.Pause;  // Pause response sending
    *       // ... later ...
    *       Bridge.Resume; // Send the response
    *     end;
    *   end;
  }
  TCommandCompleteBuffer_NoWait_Bridge_Stream = class(TCommand_base)
  protected
    FOnExecute_C: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_C; { C-style handler. Set by user. }
    FOnExecute_M: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_M; { Method handler. Set by user. }
    FOnExecute_P: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_P; { Nested/reference handler. Set by user. }
  public
    constructor Create;
    destructor Destroy; override;
    function Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
    property OnExecute: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_C: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_C read FOnExecute_C write FOnExecute_C;
    property OnExecute_M: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_M read FOnExecute_M write FOnExecute_M;
    property OnExecute_P: TOnCommand_CompleteBuffer_NoWait_Bridge_Stream_P read FOnExecute_P write FOnExecute_P;
  end;

  {
    * TCommandCompleteBuffer_NoWait_Bridge: Bridge instance for no-wait commands.
    * Holds the incoming and outgoing DFE data, and allows the command handler to pause result sending.
    * @Field Pause_Result_Send: Whether result send is paused. Set by Pause/Resume.
    * @Field Owner: Owner command. Set by Execute.
    * @Field Cmd: Command name. Set by Execute.
    * @Field R_Framework: Receive framework. Set by Execute.
    * @Field R_ID: Receive IO ID. Set by Execute.
    * @Field S_Framework: Send framework. Set by Execute.
    * @Field S_ID: Send IO ID. Set by Execute.
    * @Field UserData: User data token. Set by Execute.
    * @Field InData, OutData: Input and output data frames. Created by constructor.
    * @Example:
    *   // Inside a bridge command handler:
    *   Bridge.Pause;                  // Delay the response
    *   // ... perform async operation ...
    *   Bridge.OutData.WriteString('result');
    *   Bridge.Resume;                 // Send the response
  }
  TCommandCompleteBuffer_NoWait_Bridge = class(TCore_Object_Intermediate)
  private
    Pause_Result_Send: Boolean; { Whether result send is paused. Set by Pause/Resume. }
  public
    Owner: TCommandCompleteBuffer_NoWait_Bridge_Stream; { Owner command. Set by Execute. }
    Cmd: SystemString; { Command name. Set by Execute. }
    R_Framework: TZNet; { Receive framework. Set by Execute. }
    R_ID: Cardinal; { Receive IO ID. Set by Execute. }
    S_Framework: TZNet; { Send framework. Set by Execute. }
    S_ID: Cardinal; { Send IO ID. Set by Execute. }
    UserData: UInt64; { User data token. Set by Execute. }
    InData, OutData: TDFE; { Input and output data frames. Created by constructor. }
    constructor Create;
    destructor Destroy; override;
    function R_IO: TPeerIO;
    function S_IO: TPeerIO;
    procedure Pause;
    procedure PauseResultSend;
    procedure BreakResultSend;
    procedure SkipResultSend;
    procedure NoResultSend;
    procedure StopResultSend;
    procedure Resume;
    procedure ContinueResultSend;
    procedure Continue_Send_Result;
    procedure ResumeResultSend;
    procedure NowResultSend;
    property InDataFrame: TDFE read InData;
    property InDFE: TDFE read InData;
    property OutDataFrame: TDFE read OutData;
    property OutDFE: TDFE read OutData;
    property ResultSendIsPaused: Boolean read Pause_Result_Send;
    property ResultIsPaused: Boolean read Pause_Result_Send;
  end;
{$ENDREGION 'Command_Instance'}
{$REGION 'IO_MISC'}

  PBigStreamBatchPostData = ^TBigStreamBatchPostData; { Data for a big-stream batch post operation. }

  {
    * TBigStreamBatchPostData: Data for a big-stream batch post operation.
    * Manages the state of a single large file transfer in a batch.
    * @Field Source: Source data. Created by NewPostData.
    * @Field CompletedBackcallPtr: Pointer to completion callback. Set by sender.
    * @Field RemoteMD5: MD5 of remote data. Set by sender.
    * @Field SourceMD5: MD5 of source data. Computed during processing.
    * @Field index: Index in list. Set by NewPostData.
    * @Field DBStorePos: Database storage position. Set by storage layer.
  }
  TBigStreamBatchPostData = record
    Source: TMS64;
    CompletedBackcallPtr: UInt64;
    RemoteMD5: TMD5;
    SourceMD5: TMD5;
    index: Integer;
    DBStorePos: Int64;
    procedure Init;
    procedure Encode(d: TDFE);
    procedure Decode(d: TDFE);
  end;

  TBigStreamBatchPostData_List = class(TGenericsList<PBigStreamBatchPostData>); { List of big-stream batch post data pointers. }

  {
    * TBigStreamBatch: Manages a batch of big-stream posts.
    * Used to queue multiple file transfers or large data blocks for sequential or parallel processing.
    * @Field FOwner: Owner IO. Set by constructor.
    * @Field FList: Internal list. Created by constructor.
    * @Example:
    *   var Batch: TBigStreamBatch;
    *   var Data: PBigStreamBatchPostData;
    *   begin
    *     Batch := MyIO.BigStreamBatch;
    *     Data := Batch.NewPostData;
    *     Data.Source := MyData;  // Set the data to transfer
    *     // The batch manages multiple transfers
    *   end;
  }
  TBigStreamBatch = class(TCore_Object_Intermediate)
  protected
    FOwner: TPeerIO; { Owner IO. Set by constructor. }
    FList: TBigStreamBatchPostData_List; { Internal list. Created by constructor. }
    function GetItems(const index: Integer): PBigStreamBatchPostData;
  public
    constructor Create(Owner_: TPeerIO);
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    property Items[const index: Integer]: PBigStreamBatchPostData read GetItems; default;
    function NewPostData: PBigStreamBatchPostData;
    function First: PBigStreamBatchPostData;
    function Last: PBigStreamBatchPostData;
    procedure DeleteLast;
    procedure Delete(const index: Integer);
  end;

  {
    * TPeer_IO_User_Define: User-extensible per-IO object.
    * Each TPeerIO can have an associated user-defined instance that persists for the lifetime of the connection.
    * @Field FOwner: Owner IO. Set by constructor.
    * @Field FWorkPlatform: Execution platform. Set by user.
    * @Field FBigStreamBatch: Batch stream list. Created by constructor.
    * @Field FBusy: Busy flag. Set by user.
    * @Field FBusyNum: Busy counter. Managed internally.
    * @Example:
    *   type
    *     TMyIOData = class(TPeer_IO_User_Define)
    *       MyCustomData: Integer;
    *     end;
    *   // Then in the server:
    *   Net.UserDefineClass := TMyIOData;
    *   // Each connection now has MyCustomData available via IO.UserDefine
  }
  TPeer_IO_User_Define = class(TCore_InterfacedObject_Intermediate)
  protected
    FOwner: TPeerIO; { Owner IO. Set by constructor. }
    FWorkPlatform: TExecutePlatform; { Execution platform. Set by user. }
    FBigStreamBatch: TBigStreamBatch; { Batch stream list. Created by constructor. }
    FBusy: Boolean; { Busy flag. Set by user. }
    FBusyNum: Integer; { Busy counter. Managed internally. }
    procedure DelayFreeOnBusy;
  public
    constructor Create(Owner_: TPeerIO); virtual;
    destructor Destroy; override;
    procedure Progress; virtual;
    property Owner: TPeerIO read FOwner;
    property WorkPlatform: TExecutePlatform read FWorkPlatform write FWorkPlatform;
    property BigStreamBatchList: TBigStreamBatch read FBigStreamBatch;
    property BigStreamBatch: TBigStreamBatch read FBigStreamBatch;
    property BatchStream: TBigStreamBatch read FBigStreamBatch;
    property BatchList: TBigStreamBatch read FBigStreamBatch;
    property Busy: Boolean read FBusy write FBusy;
    function BusyNum: PInteger;
  end;

  TPeer_IO_User_Define_Class = class of TPeer_IO_User_Define;

  {
    * TPeer_IO_User_Special: A second user-extensible per-IO object.
    * Allows two separate user objects to be attached to the same IO.
    * Similar to UserDefine but provides a second independent storage slot.
    * @Field FOwner: Owner IO. Set by constructor.
    * @Field FBusy: Busy flag. Set by user.
    * @Field FBusyNum: Busy counter. Managed internally.
  }
  TPeer_IO_User_Special = class(TCore_InterfacedObject_Intermediate)
  protected
    FOwner: TPeerIO; { Owner IO. Set by constructor. }
    FBusy: Boolean; { Busy flag. Set by user. }
    FBusyNum: Integer; { Busy counter. Managed internally. }
    procedure DelayFreeOnBusy;
  public
    constructor Create(Owner_: TPeerIO); virtual;
    destructor Destroy; override;
    procedure Progress; virtual;
    property Owner: TPeerIO read FOwner;
    property Busy: Boolean read FBusy write FBusy;
    function BusyNum: PInteger;
  end;

  TPeer_IO_User_Special_Class = class of TPeer_IO_User_Special;

  TPeerClientUserDefine = TPeer_IO_User_Define; { Aliases for convenience. }
  TPeerClientUserSpecial = TPeer_IO_User_Special;

  PSequencePacket = ^TSequencePacket; { Sequence packet structure used in the reliable packet model. }

  {
    * TSequencePacket: Sequence packet structure used in the reliable ordered packet model.
    * Each packet has a unique sequence number, payload size, hash for verification, and timestamp.
    * @Field SequenceNumber: Packet sequence number. Set by sender.
    * @Field Size: Data size. Set by sender.
    * @Field hash: Data hash. Computed by sender.
    * @Field data: Packet payload. Set by sender.
    * @Field tick: Timestamp. Set by sender.
  }
  TSequencePacket = record
    SequenceNumber: Cardinal;
    Size: Word;
    hash: TMD5;
    data: TMS64;
    tick: TTimeTick;
  end;

  PIDLE_Trace = ^TIDLE_Trace; { IDLE trace data for delayed execution when IO becomes idle. }

  {
    * TIDLE_Trace: IDLE trace data for delayed execution when IO becomes idle.
    * Stores a callback to be executed when the IO is no longer busy.
    * @Field ID: IO identifier. Set by tracer.
    * @Field data: User data. Set by tracer.
    * @Field OnNotifyC: C-style callback. Set by tracer.
    * @Field OnNotifyM: Method callback. Set by tracer.
    * @Field OnNotifyP: Nested/reference callback. Set by tracer.
  }
  TIDLE_Trace = record
    ID: Cardinal;
    data: TCore_Object;
    OnNotifyC: TOnDataNotify_C;
    OnNotifyM: TOnDataNotify_M;
    OnNotifyP: TOnDataNotify_P;
  end;

  PP2PVM_ECHO = ^TP2PVM_ECHO; { P2PVM echo record for keep-alive and latency measurement. }
  TP2PVM_ECHO_List = TGenericsList<PP2PVM_ECHO>;

  {
    * TP2PVM_ECHO: P2PVM echo record for keep-alive and latency measurement.
    * Used for ping-like functionality over the P2PVM tunnel.
    * @Field OnEcho_C: C-style echo callback. Set by caller.
    * @Field OnEcho_M: Method echo callback. Set by caller.
    * @Field OnEcho_P: Nested/reference echo callback. Set by caller.
    * @Field TimeOut_: Timeout tick. Set by caller.
  }
  TP2PVM_ECHO = record
    OnEcho_C: TOnState_C;
    OnEcho_M: TOnState_M;
    OnEcho_P: TOnState_P;
    TimeOut_: TTimeTick;
  end;

  {
    * TBigStreamFragmentHead: Header for a big-stream fragment.
    * Contains the fragment size and compression flag.
    * @Field Size: Fragment size. Set by sender.
    * @Field Compressed: Whether fragment is compressed. Set by sender.
  }
  TBigStreamFragmentHead = packed record
    Size: Integer;
    Compressed: Boolean;
  end;

  PBigStreamFragmentHead = ^TBigStreamFragmentHead;
{$ENDREGION 'IO_MISC'}
{$REGION 'IO'}
  TInternalSendByteBuffer = procedure(const Sender: TPeerIO; const buff: PByte; siz: NativeInt) of object;
  TInternalSaveReceiveBuffer = procedure(const Sender: TPeerIO; const buff: Pointer; siz: Int64) of object;
  TInternalProcessReceiveBuffer = procedure(const Sender: TPeerIO) of object;
  TInternalProcessSendBuffer = procedure(const Sender: TPeerIO) of object;
  TInternal_IO_Create = procedure(const Sender: TPeerIO) of object;
  TInternal_IO_Destory = procedure(const Sender: TPeerIO) of object;

  TSequence_Packet_Hash_Pool = TBig_Hash_Pair_Pool<Cardinal, PSequencePacket>; { Hash pool for sequence packets keyed by sequence number. }

  TPhysics_Fragment_Pool_Decl = TOrderStruct<TMem64>; { FIFO pool for physics fragments (raw received data). }

  {
    * TPhysics_Fragment_Pool: FIFO pool for physics fragments.
    * Automatically frees data when removed from the pool.
  }
  TPhysics_Fragment_Pool = class(TPhysics_Fragment_Pool_Decl)
  public
    procedure DoFree(var data: TMem64); override;
  end;

  TZNet_P2PVM = class;

  {
    * TPeerIO: Core per-connection state machine.
    * This class manages all aspects of a single network connection, including:
    * - Send and receive queues
    * - Command parsing and execution
    * - Big-stream and complete-buffer reassembly
    * - Sequence-packet reliability
    * - P2P virtual machine (P2PVM) tunnelling
    * - Encryption/decryption
    * - User-defined data storage
    * It is the fundamental building block of the Z.Net framework.
    * @Field FOwnerFramework: Parent framework. Set by constructor.
    * @Field FIOInterface: External interface object. Set by constructor.
    * @Field FDisable_Progress: Disable progress flag.
    * @Field FID: Unique IO identifier. Assigned by OwnerFramework.
    * @Field FIO_Create_TimeTick: Creation timestamp. Set by constructor.
    * @Field FHeadToken: Protocol head token. Set by constructor.
    * @Field FTailToken: Protocol tail token. Set by constructor.
    * @Field FConsoleToken: Console command token. Set by constructor.
    * @Field FStreamToken: Stream command token. Set by constructor.
    * @Field FConsoleNotifyToken: Direct console token. Set by constructor.
    * @Field FStreamNotifyToken: Direct stream token. Set by constructor.
    * @Field FBigStreamToken: Big-stream command token. Set by constructor.
    * @Field FBigStreamReceiveFragmentSignal: Fragment signal token. Set by constructor.
    * @Field FBigStreamReceiveDoneSignal: Done signal token. Set by constructor.
    * @Field FCompleteBufferToken: Complete-buffer token. Set by constructor.
    * @Field FReceived_Physics_Critical: Lock for fragment pool. Created by constructor.
    * @Field FReceived_Physics_Fragment_Pool: Incoming fragment pool. Created by constructor.
    * @Field FReceivedBuffer: Primary receive buffer. Created by constructor.
    * @Field FReceivedBuffer_Busy: Secondary buffer for busy state. Created by constructor.
    * @Field FBigStreamReceiveProcessing: Whether a big-stream is being received.
    * @Field FBigStreamTotal: Total size of receiving big-stream.
    * @Field FBigStreamCompleted: Bytes completed for receiving big-stream.
    * @Field FBigStreamCmd: Command name of receiving big-stream.
    * @Field FSyncBigStreamReceive: Stream being received synchronously.
    * @Field FBigStreamSending: Stream currently being sent.
    * @Field FCompleteBufferReceiveProcessing: Whether a complete-buffer is being received.
    * @Field FCompleteBufferTotal: Total size of receiving buffer.
    * @Field FCompleteBufferCompressedSize: Compressed size (0 if not compressed).
    * @Field FCompleteBufferCompleted: Bytes completed.
    * @Field FCompleteBufferCmd: Command name.
    * @Field FCompleteBufferReceivedStream: Stream being assembled.
    * @Field FCompleteBuffer_Current_Trigger: Current trigger buffer.
    * @Field FCurrentQueueData: Currently processed queue item.
    * @Field FWaitOnResult: Waiting for a result.
    * @Field FPause_Result_Send: Whether result send is paused.
    * @Field FReceiveTriggerRuning: Receive trigger running flag.
    * @Field FReceiveDataCipherSecurity: Cipher for received data.
    * @Field FResultDataBuffer: Buffer for result data.
    * @Field FSendDataCipherSecurity: Cipher for sent data.
    * @Field FCipherKey: Cipher key. Generated by constructor.
    * @Field FDecryptInstance: Decryption instance. Created on demand.
    * @Field FEncryptInstance: Encryption instance. Created on demand.
    * @Field FSend_Queue_Critical: Lock for send queue. Created by constructor.
    * @Field FSend_Queue_Pool: Send queue. Created by constructor.
    * @Field FLastCommunicationTick: Last communication timestamp. Updated by writes.
    * @Field FRemoteExecutedForConnectInit: Whether remote init is done.
    * @Field FInCmd: Current incoming command.
    * @Field FInText: Incoming console data.
    * @Field FOutText: Outgoing console data.
    * @Field FInDataFrame: Incoming stream data.
    * @Field FOutDataFrame: Outgoing stream data.
    * @Field FResult_Text: Result text for console.
    * @Field FResult_DFE: Result stream data.
    * @Field FSyncPick: Queue item being processed synchronously.
    * @Field FWaitSendBusy: Wait-send busy flag.
    * @Field FReceiveCommandRuning: Command execution flag.
    * @Field FReceiveResultRuning: Result execution flag.
    * @Field FProgressRunning: Progress re-entry guard.
    * @Field FTimeOutProcessDone: Timeout processing done flag.
    * @Field FLast_IO_Is_IDLE: Last idle state.
    * @Field FLast_IO_IDLE_Time: Last idle timestamp.
    * @Example:
    *   // TPeerIO is created by the framework when a connection is established.
    *   // Users typically interact with it through TZNet methods.
    *   MyIO.SendConsoleCmd('ping', 'hello');  // Send a command
    *   MyIO.UserDefine.MyCustomData := 123;   // Store custom data
  }
  TPeerIO = class(TCore_InterfacedObject_Intermediate)
  private
    FOwnerFramework: TZNet; { Parent framework. Set by constructor. }

    FIOInterface: TCore_Object; { External interface object. Set by constructor. }

    FDisable_Progress: Boolean; { disable progress }

    FID: Cardinal; { Unique IO identifier. Assigned by OwnerFramework. }
    FIO_Create_TimeTick: TTimeTick; { Creation timestamp. Set by constructor. }

    FHeadToken: Cardinal; { Protocol head token. Set by constructor. }
    FTailToken: Cardinal; { Protocol tail token. Set by constructor. }

    FConsoleToken: Byte; { Console command token. Set by constructor. }
    FStreamToken: Byte; { Stream command token. Set by constructor. }
    FConsoleNotifyToken: Byte; { Direct console token. Set by constructor. }
    FStreamNotifyToken: Byte; { Direct stream token. Set by constructor. }
    FBigStreamToken: Byte; { Big-stream command token. Set by constructor. }
    FBigStreamReceiveFragmentSignal: Byte; { Fragment signal token. Set by constructor. }
    FBigStreamReceiveDoneSignal: Byte; { Done signal token. Set by constructor. }
    FCompleteBufferToken: Byte; { Complete-buffer token. Set by constructor. }

    FReceived_Physics_Critical: TCritical; { Lock for fragment pool. Created by constructor. }
    FReceived_Physics_Fragment_Pool: TPhysics_Fragment_Pool; { Incoming fragment pool. Created by constructor. }
    FLast_Process_Receive_Buffer_CPU_Is_Full: Boolean; { Whether last receive loop hit limit. Set by Internal_Process_Receive_Buffer. }
    FReceivedAbort: Boolean; { Abort flag. Set by Internal_Process_Receive_Buffer. }
    FReceivedBuffer: TMS64; { Primary receive buffer. Created by constructor. }
    FReceivedBuffer_Busy: TMS64; { Secondary buffer for busy state. Created by constructor. }

    FBigStreamReceiveProcessing: Boolean; { Whether a big-stream is being received. Set by protocol parser. }
    FBigStreamTotal: Int64; { Total size of receiving big-stream. Set by protocol parser. }
    FBigStreamCompleted: Int64; { Bytes completed for receiving big-stream. Set by protocol parser. }
    FBigStream_Current_Received: Int64; { Current received bytes. Set by protocol parser. }
    FBigStreamFragmentSignal_SendedState: Boolean; { True if the "request next fragment" signal has already been sent for the current fragment, preventing duplicate requests while waiting for remaining data. }
    FBigStreamCmd: SystemString; { Command name of receiving big-stream. Set by protocol parser. }
    FSyncBigStreamReceive: TCore_Stream; { Stream being received synchronously. Set by protocol parser. }
    FBigStreamSending: TCore_Stream; { Stream currently being sent. Set by Internal_Send_BigStream_Cmd. }
    FBigStreamSendCurrentPos: Int64; { Current send position. Set by Internal_Send_BigStream_Cmd. }
    FBigStreamSendDoneTimeFree: Boolean; { Whether to free stream after send. Set by Internal_Send_BigStream_Cmd. }
    FWaitBigStreamReceiveDoneSignal: Boolean; { Waiting for done signal. Set by Internal_Send_BigStream_Cmd. }

    FCompleteBufferReceiveProcessing: Boolean; { Whether a complete-buffer is being received. Set by protocol parser. }
    FCompleteBufferTotal: Cardinal; { Total size of receiving buffer. Set by protocol parser. }
    FCompleteBufferCompressedSize: Cardinal; { Compressed size (0 if not compressed). Set by protocol parser. }
    FCompleteBufferCompleted: Cardinal; { Bytes completed. Set by protocol parser. }
    FCompleteBufferCmd: SystemString; { Command name. Set by protocol parser. }
    FCompleteBufferReceivedStream: TMS64; { Stream being assembled. Created by constructor. }
    FCompleteBuffer_Current_Trigger: TMS64; { Current trigger buffer. Set by Internal_Execute_CompleteBuffer. }

    FCurrentQueueData: PQueueData; { Currently processed queue item. Set by Internal_Process_Send_Buffer. }
    FWaitOnResult: Boolean; { Waiting for a result. Set by Internal_Process_Send_Buffer. }
    FCurrentPauseResultSend_CommDataType: Byte; { Data type of paused result. Set by ExecuteDataFrame. }
    FCanPauseResultSend: Boolean; { Whether result send can be paused. Set by ExecuteDataFrame. }
    FPause_Result_Send: Boolean; { Whether result send is paused. Set by Pause/Resume. }
    FReceiveTriggerRuning: Boolean; { Receive trigger running flag. Set by ExecuteDataFrame. }
    FReceiveDataCipherSecurity: TCipherSecurity; { Cipher for received data. Set by protocol parser. }
    FResultDataBuffer: TMS64; { Buffer for result data. Created by constructor. }
    FSendDataCipherSecurity: TCipherSecurity; { Cipher for sent data. Set by constructor. }
    FCipherKey: TCipherKeyBuffer; { Cipher key. Generated by constructor. }
    FDecryptInstance: TCipher_Base; { Decryption instance. Created on demand. }
    FEncryptInstance: TCipher_Base; { Encryption instance. Created on demand. }
    FAllSendProcessing: Boolean; { Send processing flag. Set by Internal_Process_Send_Buffer. }
    FReceiveProcessing: Boolean; { Receive processing flag. Set by Internal_Process_Receive_Buffer. }
    FSend_Queue_Critical: TCritical; { Lock for send queue. Created by constructor. }
    FSend_Queue_Pool: TQueueData_Pool; { Send queue. Created by constructor. }
    FLastCommunicationTick: TTimeTick; { Last communication timestamp. Updated by writes. }
    LastCommunicationTick_Received: TTimeTick; { Last receive timestamp. Updated on receive. }
    LastCommunicationTick_KeepAlive: TTimeTick; { Last keep-alive timestamp. Updated by keep-alive. }
    LastCommunicationTick_Sending: TTimeTick; { Last send timestamp. Updated on send. }
    FRemoteExecutedForConnectInit: Boolean; { Whether remote init is done. Set by cipher model. }
    FInCmd: SystemString; { Current incoming command. Set by ExecuteDataFrame. }
    FInText, FOutText: SystemString; { Incoming/outgoing console data. Set by ExecuteDataFrame. }
    FInDataFrame, FOutDataFrame: TDFE; { Incoming/outgoing stream data. Created by constructor. }
    FResult_Text: SystemString; { Result text for console. Set by FillWaitOnResultBuffer. }
    FResult_DFE: TDFE; { Result stream data. Created by constructor. }
    FSyncPick: PQueueData; { Queue item being processed synchronously. Set by Internal_Process_Send_Buffer. }
    FWaitSendBusy: Boolean; { Wait-send busy flag. Set by WaitSend methods. }
    FReceiveCommandRuning: Boolean; { Command execution flag. Set by Internal_Execute_*. }
    FReceiveResultRuning: Boolean; { Result execution flag. Set by DoExecuteResult. }
    FProgressRunning: Boolean; { Progress re-entry guard. Set by Progress. }
    FTimeOutProcessDone: Boolean; { Timeout processing done flag. Set by Progress. }
    FLast_IO_Is_IDLE: Boolean; { Last idle state. Set by IOBusy. }
    FLast_IO_IDLE_Time: TTimeTick; { Last idle timestamp. Set by IOBusy. }
  public
    function Connected: Boolean; virtual; // Returns True if the connection is established and active.
    procedure Disconnect; virtual; // Closes the connection and releases associated resources.
    procedure Write_IO_Buffer(const buff: PByte; const Size: NativeInt); virtual; // Writes raw data to the underlying transport; must be thread-safe.
    procedure WriteBufferOpen; virtual; // Called before a batch of writes; starts a write transaction.
    procedure WriteBufferFlush; virtual; // Flushes any buffered writes to the transport.
    procedure WriteBufferClose; virtual; // Called after a batch of writes; ends the write transaction.
    function GetPeerIP: SystemString; virtual; // Returns the remote peer's IP address as a string, or 'offline' if not connected.
    function WriteBuffer_is_NULL: Boolean; virtual; // Returns True if the write buffer is empty and no data is pending for transmission.
    function WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean; virtual; // Returns buffer state (queue count and total size); True if pending writes exist.
  protected
    { Sequence Packet Model }
    FSequencePacketActivted, FSequencePacketSignal: Boolean;
    SequenceNumberOnSendCounter, SequenceNumberOnReceivedCounter: Cardinal;
    SendingSequencePacketHistory: TSequence_Packet_Hash_Pool;
    SequencePacketReceivedPool: TSequence_Packet_Hash_Pool;
    SendingSequencePacketHistoryMemory, SequencePacketReceivedPoolMemory: Int64;
    IOSendBuffer, SequencePacketSendBuffer, SequencePacketReceivedBuffer: TMS64;
    FSequencePacketMTU: Word;
    FSequencePacketLimitPhysicsMemory: Int64;
    SequencePacketCloseDone: Boolean;
    SequencePacketVerifyTick: TTimeTick;
    procedure InitSequencePacketModel(const hashSize, MemoryDelta: Integer); // Initialises the reliable sequence-packet engine with hash pool and buffers.
    procedure FreeSequencePacketModel; // Releases all sequence-packet resources and clears history pools.
    procedure ResetSequencePacketBuffer; // Clears all sequence-packet send/receive buffers without freeing the model.
    procedure ProcessSequencePacketModel; // Drives sequence-packet retransmission and acknowledgment processing.
    function GetSequencePacketState: SystemString; // Returns a string describing current sequence-packet stats (history, pool, memory).
    function GetSequencePacketUsagePhysicsMemory: Int64; // Returns total memory used by all sequence-packet buffers.
    function ComputeSequencePacketHash(const p: PByte; const Count: nativeUInt): TMD5; // Calculates MD5 hash for a packet payload.
    function IsSequencePacketModel: Boolean; // Returns True if sequence-packet mode is active and protocol is ZServer.
    procedure FlushIOSendBuffer; // Sends all accumulated data in the internal IO send buffer.
    procedure SendSequencePacketBegin; // Starts a new sequence-packet assembly session.
    procedure SendSequencePacket(const buff: PByte; siz: NativeInt); // Appends data to the current sequence-packet assembly.
    procedure SendSequencePacketEnd; // Finalises and sends the assembled sequence packets (fragments if needed).
    procedure SendSequencePacketKeepAlive(p: Pointer; siz: Word); // Sends a keep-alive packet with optional user data.
    procedure DoSequencePacketEchoKeepAlive(p: Pointer; siz: Word); virtual; // Called when a keep-alive echo is received; override for custom handling.
    procedure WriteSequencePacket(p: PSequencePacket); // Writes a single sequence packet (header + data) to the send buffer.
    procedure ResendSequencePacket(SequenceNumber: Cardinal); // Forces retransmission of a specific packet by sequence number.
    function FillSequencePacketTo(const buff: Pointer; siz: Int64; ExtractDest: TMS64): Boolean; // Processes raw incoming data through sequence‑packet reassembly.
    procedure Send_Free_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket); // Callback to free a sending-history packet when acknowledged.
    procedure Send_Add_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket); // Callback to track a newly added sending-history packet.
    procedure Received_Free_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket); // Callback to free a received-pool packet when delivered.
    procedure Received_Add_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket); // Callback to track a newly added received-pool packet.
  protected
    { P2P Virtual Machine (P2PVM) support }
    FP2PVMTunnel: TZNet_P2PVM; { P2PVM tunnel instance. Created by OpenP2PVMTunnel. }
    FP2PVM_Auth_Token: TBytes; { Authentication token. Set by BuildP2PAuthToken. }
    FP2PVM_Cipher_Key: TCipherKeyBuffer; { P2PVM cipher key. Set by BuildP2PAuthToken. }
    FP2PVM_Cipher: TCipher_Base; { P2PVM cipher instance. Set by BuildP2PAuthToken. }
    On_Internal_Send_Byte_Buffer: TInternalSendByteBuffer; { Internal send hook. Set by constructor. }
    On_Internal_Save_Receive_Buffer: TInternalSaveReceiveBuffer; { Internal receive hook. Set by constructor. }
    On_Internal_Process_Receive_Buffer: TInternalProcessReceiveBuffer; { Internal receive process hook. Set by constructor. }
    On_Internal_Process_Send_Buffer: TInternalProcessSendBuffer; { Internal send process hook. Set by constructor. }
    OnCreate: TInternal_IO_Create; { Creation callback. Set by constructor. }
    OnDestroy: TInternal_IO_Destory; { Destruction callback. Set by constructor. }
    OnVMBuildAuthModelResult_C: TOnNotify_C; { VM auth build result callback (C). Set by caller. }
    OnVMBuildAuthModelResult_M: TOnNotify_M; { VM auth build result callback (method). Set by caller. }
    OnVMBuildAuthModelResult_P: TOnNotify_P; { VM auth build result callback (nested). Set by caller. }
    OnVMBuildAuthModelResultIO_C: TOnIONotify_C; { VM auth build result with IO (C). Set by caller. }
    OnVMBuildAuthModelResultIO_M: TOnIONotify_M; { VM auth build result with IO (method). Set by caller. }
    OnVMBuildAuthModelResultIO_P: TOnIONotify_P; { VM auth build result with IO (nested). Set by caller. }
    OnVMAuthResult_C: TOnState_C; { VM auth result (C). Set by caller. }
    OnVMAuthResult_M: TOnState_M; { VM auth result (method). Set by caller. }
    OnVMAuthResult_P: TOnState_P; { VM auth result (nested). Set by caller. }
    OnVMAuthResultIO_C: TOnIOState_C; { VM auth result with IO (C). Set by caller. }
    OnVMAuthResultIO_M: TOnIOState_M; { VM auth result with IO (method). Set by caller. }
    OnVMAuthResultIO_P: TOnIOState_P; { VM auth result with IO (nested). Set by caller. }
    procedure P2PVMAuthSuccess(Sender: TZNet_P2PVM);
  protected
    { Automated P2PVM }
    FOnAutomatedP2PVMClientConnectionDone_C: TOnIOState_C; { Automated P2PVM done (C). Set by caller. }
    FOnAutomatedP2PVMClientConnectionDone_M: TOnIOState_M; { Automated P2PVM done (method). Set by caller. }
    FOnAutomatedP2PVMClientConnectionDone_P: TOnIOState_P; { Automated P2PVM done (nested). Set by caller. }
  protected
    { User custom data }
    FUserData: Pointer; { Generic user pointer. Set by user. }
    FUserValue: Variant; { Generic user variant. Set by user. }
    FUserVariants: THashVariantList; { Key-value variant storage. Created on demand. }
    FUserObjects: THashObjectList; { Key-value object storage (not auto-freed). Created on demand. }
    FUserAutoFreeObjects: THashObjectList; { Key-value object storage (auto-freed). Created on demand. }
    FUser_Define: TPeer_IO_User_Define; { Primary user-defined object. Created by constructor. }
    FUser_Special: TPeer_IO_User_Special; { Secondary user-defined object. Created by constructor. }
    function GetUserVariants: THashVariantList;
    function GetUserObjects: THashObjectList;
    function GetUserAutoFreeObjects: THashObjectList;
  protected
    BeginSendState: Boolean; { Send state guard. Set by BeginSend/EndSend. }
    procedure BeginSend; // Begins a new send sequence; call before sending raw data.
    procedure Send(const buff: PByte; siz: NativeInt); // Appends raw binary data to the current send buffer.
    procedure EndSend; // Flushes the send buffer and transmits all queued data.
    procedure SendInteger(v: Integer); // Sends a 32‑bit signed integer.
    procedure SendCardinal(v: Cardinal); // Sends a 32‑bit unsigned integer.
    procedure SendInt64(v: Int64); // Sends a 64‑bit signed integer.
    procedure SendByte(v: Byte); // Sends a single unsigned byte.
    procedure SendWord(v: Word); // Sends a 16‑bit unsigned word.
    procedure SendVerifyCode(buff: Pointer; siz: NativeInt); // Sends a hash/checksum of the buffer for integrity verification.
    procedure SendEncryptBuffer(buff: PByte; siz: NativeInt; CS: TCipherSecurity); // Encrypts and sends the buffer using the specified cipher.
    procedure SendEncryptMemoryStream(Stream: TMS64; CS: TCipherSecurity); // Encrypts and sends the entire TMS64 stream.
    procedure Internal_Send_Console_Buff(buff: TMS64; CS: TCipherSecurity); // Sends a complete console‑command packet (header + encrypted payload).
    procedure Internal_Send_Stream_Buff(buff: TMS64; CS: TCipherSecurity); // Sends a complete stream‑command packet.
    procedure Internal_Send_ConsoleNotify_Buff(buff: TMS64; CS: TCipherSecurity); // Sends a fire‑and‑forget console notification packet.
    procedure Internal_Send_StreamNotify_Buff(buff: TMS64; CS: TCipherSecurity); // Sends a fire‑and‑forget stream notification packet.
    procedure Internal_Send_Big_Stream_Header(const Cmd: SystemString; streamSiz: Int64); // Sends the header for a big‑stream transfer.
    procedure Internal_Send_BigStream_Buff(var Queue: TQueueData); // Sends big‑stream data in chunks, with flow‑control signalling.
    procedure Internal_Send_Complete_Buffer_Header(const Cmd: SystemString; BuffSiz, compSiz: Cardinal); // Sends the header for a complete‑buffer command.
    procedure Internal_Send_CompleteBuffer_Buff(var Queue: TQueueData); // Sends the complete‑buffer payload, optionally compressed.
    procedure Internal_Send_BigStream_Fragment_Signal; // Sends a signal to request the next big‑stream fragment.
    procedure Internal_Send_BigStream_Done_Signal; // Sends a signal indicating the big‑stream transfer is complete.
    procedure SendBigStreamMiniPacket(buff: PByte; Size: NativeInt); // Sends a single fragment of a big‑stream, with compression header.
    procedure Internal_Send_Result_Data; // Flushes the pending result buffer (response after a pause).
    procedure Internal_Send_Console_Cmd; // Serialises and sends a console command from the queue.
    procedure Internal_Send_Stream_Cmd; // Serialises and sends a stream command from the queue.
    procedure Internal_Send_ConsoleNotify_Cmd; // Sends a console notification command (no reply expected).
    procedure Internal_Send_StreamNotify_Cmd; // Sends a stream notification command (no reply expected).
    procedure Internal_Send_BigStream_Cmd; // Sends a big‑stream command from the queue.
    procedure Internal_Send_CompleteBuffer_Cmd; // Sends a complete‑buffer command from the queue.
    procedure Internal_Execute_Console; // Executes a console command and populates the result string.
    procedure Internal_Execute_Stream; // Executes a stream command and populates the result DFE.
    procedure Internal_Execute_ConsoleNotify; // Executes a console notification (no result sent).
    procedure Internal_Execute_StreamNotify; // Executes a stream notification (no result sent).
    procedure SendConsoleResult; // Sends the result of a console command back to the caller.
    procedure SendStreamResult; // Sends the result of a stream command back to the caller.
    procedure ExecuteDataFrame(CommDataType: Byte; DFE_: TDFE); // Dispatches a parsed DFE command to the appropriate handler.
    procedure Internal_Execute_BigStream; // Executes a big‑stream command and triggers progress callbacks.
    function ReceivedBigStreamFragment(Source_: TMS64): Int64; // Processes an incoming big‑stream fragment; returns bytes consumed.
    procedure Internal_Execute_CompleteBuffer; // Executes a complete‑buffer command (sync or async).
    function FillCompleteBufferBuffer(Source_: TMS64): Int64; // Reassembles a complete‑buffer from fragments; returns bytes consumed.
    procedure Internal_ExecuteResult; // Triggers the result callback for a pending request.
    function FillWaitOnResultBuffer(Source_: TMS64): Int64; // Parses an incoming response packet and delivers the result.
    procedure Internal_Save_Receive_Buffer(const buff: Pointer; siz: Int64); // Appends raw received data to the receive buffer.
    function Internal_Process_Receive_Buffer(): Integer; // Parses all complete packets from the receive buffer.
    procedure Internal_Process_Send_Buffer(); // Drains the send queue and sends queued commands.
    procedure CheckAndTriggerFailedWaitResult; // Notifies failure for a pending request and cleans up.
    procedure Internal_Close_P2PVMTunnel; // Closes and frees the P2P virtual machine tunnel.
  public
    constructor Create(OwnerFramework_: TZNet; IOInterface_: TCore_Object);
    procedure CreateAfter; virtual;
    destructor Destroy; override;
    { IO state and idle tracing. }
    function IOBusy: Boolean;
    property IO_Create_TimeTick: TTimeTick read FIO_Create_TimeTick;
    procedure IO_IDLE_TraceC(data: TCore_Object; OnNotify: TOnDataNotify_C);
    procedure IO_IDLE_TraceM(data: TCore_Object; OnNotify: TOnDataNotify_M);
    procedure IO_IDLE_TraceP(data: TCore_Object; OnNotify: TOnDataNotify_P);
    { Double-tunnel support (separate receive/send channels). }
    function Is_Double_Tunnel: Boolean;
    function Is_Recveive_Tunnel: Boolean;
    function Is_Send_Tunnel: Boolean;
    function Is_Link_OK: Boolean;
    function Get_Send_Tunnel_IO: TPeerIO;
    function Get_Send_Tunnel(var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean;
    function Get_Recv_Tunnel_IO: TPeerIO;
    function Get_Recv_Tunnel(var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean;
    { Sequence Packet model support. }
    property SequencePacketSignal: Boolean read FSequencePacketSignal;
    property SequencePacketMTU: Word read FSequencePacketMTU write FSequencePacketMTU;
    property SequencePacketLimitOwnerIOMemory: Int64 read FSequencePacketLimitPhysicsMemory write FSequencePacketLimitPhysicsMemory;
    property SequencePacketUsagePhysicsMemory: Int64 read GetSequencePacketUsagePhysicsMemory;
    property SequencePacketState: SystemString read GetSequencePacketState;
    { P2PVM Tunnel support. }
    property P2PVM: TZNet_P2PVM read FP2PVMTunnel;
    property P2PVMTunnel: TZNet_P2PVM read FP2PVMTunnel;
    property P2PVM_Auth_Token: TBytes read FP2PVM_Auth_Token;
    property P2PVM_Cipher_Key: TCipherKeyBuffer read FP2PVM_Cipher_Key;
    property P2PVM_Cipher: TCipher_Base read FP2PVM_Cipher;
    function p2pVMTunnelReadyOk: Boolean;
    { Build P2P auth token (calls remote to exchange security credentials). }
    procedure BuildP2PAuthToken; overload;
    procedure BuildP2PAuthTokenC(const OnResult: TOnNotify_C);
    procedure BuildP2PAuthTokenM(const OnResult: TOnNotify_M);
    procedure BuildP2PAuthTokenP(const OnResult: TOnNotify_P);
    procedure BuildP2PAuthTokenIO_C(const OnResult: TOnIONotify_C);
    procedure BuildP2PAuthTokenIO_M(const OnResult: TOnIONotify_M);
    procedure BuildP2PAuthTokenIO_P(const OnResult: TOnIONotify_P);
    { Open P2PVM tunnel. }
    procedure DoP2PVM_Created(Sender: TZNet_P2PVM); virtual;
    procedure DoP2PVM_InstallLogicFramework(Inst: TZNet); virtual;
    procedure DoP2PVM_UninstallLogicFramework(Inst: TZNet); virtual;
    procedure OpenP2PVMTunnel(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString); overload;
    procedure OpenP2PVMTunnel(SendRemoteRequest: Boolean; const AuthToken: SystemString); overload;
    procedure OpenP2PVMTunnelC(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_C); overload;
    procedure OpenP2PVMTunnelM(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_M); overload;
    procedure OpenP2PVMTunnelP(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_P); overload;
    procedure OpenP2PVMTunnelC(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_C); overload;
    procedure OpenP2PVMTunnelM(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_M); overload;
    procedure OpenP2PVMTunnelP(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_P); overload;
    procedure OpenP2PVMTunnelIO_C(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_C); overload;
    procedure OpenP2PVMTunnelIO_M(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_M); overload;
    procedure OpenP2PVMTunnelIO_P(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_P); overload;
    procedure OpenP2PVMTunnelIO_C(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_C); overload;
    procedure OpenP2PVMTunnelIO_M(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_M); overload;
    procedure OpenP2PVMTunnelIO_P(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_P); overload;
    procedure OpenP2PVMTunnel; overload;
    { Close P2PVM tunnel. }
    procedure CloseP2PVMTunnel;
    { Print diagnostic messages. }
    procedure Print(const v: SystemString); overload;
    procedure Print(const v: SystemString; const Args: array of const); overload;
    procedure PrintCommand(const v, Args: SystemString);
    procedure PrintParam(const v, Args: SystemString);
    procedure PrintError(const v: SystemString); overload;
    procedure PrintError(const v: SystemString; const Args: array of const); overload;
    procedure PrintWarning(const v: SystemString); overload;
    procedure PrintWarning(const v: SystemString; const Args: array of const); overload;

    { Progress the IO state machine. }
    property Disable_Progress: Boolean read FDisable_Progress; { disable progress }
    procedure Progress; virtual;

    { Delay close/free operations. }
    procedure DelayClose; overload;
    procedure DelayClose(const t: Double); overload;
    procedure DelayFree; overload;
    procedure DelayFree(const t: Double); overload;
    { Packet buffer operations. }
    procedure Write_Physics_Fragment(const p: Pointer; siz: Int64);
    function Extract_Physics_Fragment_To_Receive_Buffer(): Int64;
    procedure Process_Receive_Buffer();
    procedure Process_Send_Buffer();
    procedure PostQueueData(p: PQueueData);
    { Custom protocol buffer writing. }
    procedure BeginWriteCustomBuffer;
    procedure EndWriteCustomBuffer;
    procedure WriteCustomBuffer(const Buffer: PByte; const Size: NativeInt); overload; virtual;
    procedure WriteCustomBuffer(const Buffer: TMS64); overload;
    procedure WriteCustomBuffer(const Buffer: TMem64); overload;
    procedure WriteCustomBuffer(const Buffer: TMS64; const doneFreeBuffer: Boolean); overload;
    procedure WriteCustomBuffer(const Buffer: TMem64; const doneFreeBuffer: Boolean); overload;
    { Pause/Resume result sending. }
    procedure Pause; virtual;
    procedure PauseResultSend;
    procedure BreakResultSend;
    procedure SkipResultSend;
    procedure NoResultSend;
    procedure StopResultSend;
    procedure Resume; virtual;
    procedure ContinueResultSend;
    procedure Continue_Send_Result;
    procedure ResumeResultSend;
    procedure NowResultSend;
    { Incoming/outgoing data access. }
    property InText: SystemString read FInText;
    property InConsole: SystemString read FInText;
    property OutText: SystemString read FOutText write FOutText;
    property OutConsole: SystemString read FOutText write FOutText;
    property InDataFrame: TDFE read FInDataFrame;
    property InDFE: TDFE read FInDataFrame;
    property OutDataFrame: TDFE read FOutDataFrame;
    property OutDFE: TDFE read FOutDataFrame;
    function ResultSendIsPaused: Boolean;
    property ResultIsPaused: Boolean read ResultSendIsPaused;
    { State access. }
    property CurrentBigStreamCommand: SystemString read FBigStreamCmd;
    property CurrentCommand: SystemString read FInCmd;
    property CurrentCmd: SystemString read FInCmd;
    property CompleteBufferCmd: SystemString read FCompleteBufferCmd;
    property WaitOnResult: Boolean read FWaitOnResult;
    property AllSendProcessing: Boolean read FAllSendProcessing;
    property BigStreamReceiveing: Boolean read FBigStreamReceiveProcessing;
    property WaitSendBusy: Boolean read FWaitSendBusy;
    property ReceiveProcessing: Boolean read FReceiveProcessing;
    property ReceiveCommandRuning: Boolean read FReceiveCommandRuning;
    property ReceiveResultRuning: Boolean read FReceiveResultRuning;
    function GetBigStreamReceiveState(var Total, Complete: Int64): Boolean;
    function GetBigStreamSendingState(var Total, Complete: Int64): Boolean;
    function GetBigStreamBatch: TBigStreamBatch;
    property BigStreamBatchList: TBigStreamBatch read GetBigStreamBatch;
    property BigStreamBatch: TBigStreamBatch read GetBigStreamBatch;
    property CompleteBufferReceivedStream: TMS64 read FCompleteBufferReceivedStream;
    property CompleteBuffer_Current_Trigger: TMS64 read FCompleteBuffer_Current_Trigger;
    function Get_Last_IO_IDLE_Time: TTimeTick;
    property Last_IO_IDLE_Time: TTimeTick read Get_Last_IO_IDLE_Time;
    { Framework and identity. }
    property OwnerFramework: TZNet read FOwnerFramework;
    property IOInterface: TCore_Object read FIOInterface write FIOInterface;
    procedure SetID(const Value: Cardinal);
    property ID: Cardinal read FID write SetID;
    property CipherKey: TCipherKeyBuffer read FCipherKey;
    function CipherKeyPtr: PCipherKeyBuffer;
    property SendCipherSecurity: TCipherSecurity read FSendDataCipherSecurity write FSendDataCipherSecurity;
    property RemoteExecutedForConnectInit: Boolean read FRemoteExecutedForConnectInit write FRemoteExecutedForConnectInit;
    property PeerIP: SystemString read GetPeerIP;
    { User data. }
    property UserVariants: THashVariantList read GetUserVariants;
    property UserObjects: THashObjectList read GetUserObjects;
    property UserAutoFreeObjects: THashObjectList read GetUserAutoFreeObjects;
    property UserData: Pointer read FUserData write FUserData;
    property UserValue: Variant read FUserValue write FUserValue;
    property UserDefine: TPeer_IO_User_Define read FUser_Define;
    property IODefine: TPeer_IO_User_Define read FUser_Define;
    property Define: TPeer_IO_User_Define read FUser_Define;
    property UserSpecial: TPeer_IO_User_Special read FUser_Special;
    property IOSpecial: TPeer_IO_User_Special read FUser_Special;
    property Special: TPeer_IO_User_Special read FUser_Special;
    { Hash and encryption utilities. }
    procedure GenerateHashCode(const hs: THashSecurity; buff: Pointer; siz: Integer; var output: TBytes);
    function VerifyHashCode(const hs: THashSecurity; buff: Pointer; siz: Integer; var Code: TBytes): Boolean;
    procedure Encrypt(CS: TCipherSecurity; DataPtr: Pointer; Size: Cardinal; var k: TCipherKeyBuffer; enc: Boolean);
    { Timeout tracking. }
    function NoneCommunicationTime: TTimeTick;
    property StopCommunicationTime: TTimeTick read NoneCommunicationTime;
    procedure UpdateLastCommunicationTime;
    property LastCommunicationTime: TTimeTick read FLastCommunicationTick;
    property LastCommunicationTimeTick: TTimeTick read FLastCommunicationTick;
    { Queue data access. }
    property CurrentQueueData: PQueueData read FCurrentQueueData;

    { ===========================================================================
      Send command methods – with and without result callbacks.
      ===========================================================================
      These methods queue a command for transmission to the remote peer.
      The command will be sent asynchronously during the next Progress() cycle.
      The caller must ensure the IO is connected before sending.

      All methods support three callback styles:
      - No suffix: fire-and-forget (no response expected).
      - M suffix: method-style callback (of object).
      - P suffix: nested or reference (anonymous) callback.
      Additionally, some methods accept custom parameters (Param1/Param2)
      that are passed back to the callback, and an optional OnFailed callback
      for timeout or error handling.

      For stream commands, the payload is a TDFE (Data Frame Exchange) which
      can contain structured binary data. For console commands, the payload
      is a string. BigStream and CompleteBuffer commands handle large data
      blocks with specialized mechanisms.

      WaitSendXXX methods block the caller until a response is received or a
      timeout occurs – use with caution as they suspend the calling thread.
    }

    // --- Console commands (request-response) ------------------------------------
    {
      * Sends a console command without expecting a response.
      * The command is queued and sent asynchronously. No callback is invoked.
      * @Param Cmd: Name of the command registered on the remote side.
      * @Param ConsoleData: String payload to send.
    }
    procedure SendConsoleCmd(const Cmd, ConsoleData: SystemString);

    {
      * Sends a console command and invokes a method callback when the response arrives.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload string.
      * @Param OnResult: Method-style callback receiving the response string.
    }
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M); overload;

    {
      * Sends a console command with custom parameters; callback receives them.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload string.
      * @Param Param1, Param2: User-defined pointers/objects passed back.
      * @Param OnResult: Callback receiving the response and the parameters.
    }
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M); overload;

    {
      * Sends a console command with parameters and an explicit failure handler.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload string.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback.
      * @Param OnFailed: Failure callback (timeout or error).
    }
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M); overload;

    // --- Console commands with nested/reference callbacks ----------------------
    {
      * Sends a console command with a nested (reference) callback.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload.
      * @Param OnResult: Nested/reference callback receiving the response.
    }
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P); overload;

    {
      * Sends a console command with parameters and a nested callback.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback with parameters.
    }
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P); overload;

    {
      * Sends a console command with parameters and both success/failure nested callbacks.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback.
      * @Param OnFailed: Failure callback.
    }
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P); overload;

    // --- Stream commands (request-response) ------------------------------------
    {
      * Sends a stream command without expecting a response.
      * The StreamData buffer is automatically freed after sending if DoneAutoFree=True.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TMS64 (memory stream).
      * @Param DoneAutoFree: If True, the stream object is freed after send.
    }
    procedure SendStreamCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;

    {
      * Sends a stream command with a TDFE payload (no response expected).
      * The TDFE is encoded and sent asynchronously.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
    }
    procedure SendStreamCmd(const Cmd: SystemString; StreamData: TDFE); overload;

    {
      * Sends a stream command expecting a response via a method callback.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TMS64.
      * @Param OnResult: Method callback receiving the response TDFE.
      * @Param DoneAutoFree: Whether to auto-free StreamData.
    }
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean); overload;

    {
      * Sends a stream command with a TDFE payload and method callback.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param OnResult: Method callback receiving the response.
    }
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M); overload;

    {
      * Sends a stream command with parameters and method callback.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback with parameters.
    }
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M); overload;

    {
      * Sends a stream command with parameters and both success/failure method callbacks.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback.
      * @Param OnFailed: Failure callback.
    }
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M); overload;

    // --- Stream commands with nested/reference callbacks -----------------------
    {
      * Sends a stream command with a nested callback for the response.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TMS64.
      * @Param OnResult: Nested callback.
      * @Param DoneAutoFree: Whether to auto-free StreamData.
    }
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean); overload;

    {
      * Sends a stream command with a TDFE payload and nested callback.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param OnResult: Nested callback.
    }
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P); overload;

    {
      * Sends a stream command with parameters and nested callback.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback with parameters.
    }
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P); overload;

    {
      * Sends a stream command with parameters and both nested success/failure callbacks.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
      * @Param Param1, Param2: User parameters.
      * @Param OnResult: Success callback.
      * @Param OnFailed: Failure callback.
    }
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P); overload;

    // --- Notification commands (no response) ------------------------------------
    {
      * Sends a console notification (fire-and-forget) with payload.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload string.
    }
    procedure SendConsoleNotifyCmd(const Cmd, ConsoleData: SystemString); overload;

    {
      * Sends a console notification with an empty payload.
      * @Param Cmd: Command name.
    }
    procedure SendConsoleNotifyCmd(const Cmd: SystemString); overload;

    {
      * Sends a stream notification (fire-and-forget) with a TMS64 payload.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TMS64.
      * @Param DoneAutoFree: Whether to auto-free StreamData.
    }
    procedure SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;

    {
      * Sends a stream notification with a TDFE payload.
      * @Param Cmd: Command name.
      * @Param StreamData: Payload as TDFE.
    }
    procedure SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE); overload;

    {
      * Sends a stream notification with an empty payload (TDFE is built).
      * @Param Cmd: Command name.
    }
    procedure SendStreamNotifyCmd(const Cmd: SystemString); overload;

    // --- Synchronous (blocking) send methods ------------------------------------
    {
      * Sends a console command and waits for a response.
      * The caller blocks until the response is received or the timeout expires.
      * @Param Cmd: Command name.
      * @Param ConsoleData: Payload string.
      * @Param TimeOut_: Timeout in milliseconds (0 means no timeout, but may block indefinitely).
      * @Returns: The response string, or empty string on failure/timeout.
    }
    function WaitSendConsoleCmd(Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;

    {
      * Sends a stream command and waits for a response.
      * The caller blocks until the response arrives or the timeout expires.
      * @Param Cmd: Command name.
      * @Param StreamData: Input TDFE payload.
      * @Param Result_: Output TDFE that receives the response.
      * @Param TimeOut_: Timeout in milliseconds.
    }
    procedure WaitSendStreamCmd(const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);

    // --- Big-stream (large file/data) send -------------------------------------
    {
      * Sends a large stream (big-stream) starting from a specified position.
      * The stream is sent in chunks with flow control. The remote side must
      * have a matching big-stream command handler.
      * @Param Cmd: Command name.
      * @Param BigStream: The stream object containing the data.
      * @Param StartPos: Byte offset from which to start sending.
      * @Param DoneAutoFree: Whether to auto-free BigStream after send.
    }
    procedure SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean); overload;

    {
      * Sends a large stream from the beginning (StartPos = 0).
      * @Param Cmd: Command name.
      * @Param BigStream: The stream object.
      * @Param DoneAutoFree: Whether to auto-free BigStream.
    }
    procedure SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean); overload;

    // --- Complete-buffer (atomic data block) send ------------------------------
    {
      * Sends a raw buffer as a complete-buffer command.
      * The buffer is sent atomically; the remote side must have a matching
      * complete-buffer command registered.
      * @Param Cmd: Command name.
      * @Param buff: Pointer to the data buffer.
      * @Param BuffSize: Size of the buffer in bytes.
      * @Param DoneAutoFree: Whether to auto-free the buffer after send.
    }
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean); overload;

    {
      * Sends a TMS64 stream as a complete-buffer command.
      * @Param Cmd: Command name.
      * @Param buff: TMS64 containing the data.
      * @Param DoneAutoFree: Whether to auto-free the stream.
    }
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean); overload;

    {
      * Sends a TMem64 buffer as a complete-buffer command.
      * @Param Cmd: Command name.
      * @Param buff: TMem64 containing the data.
      * @Param DoneAutoFree: Whether to auto-free the buffer.
    }
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean); overload;

    {
      * Sends a TDFE as a complete-buffer command.
      * The TDFE is encoded into a buffer and sent.
      * @Param Cmd: Command name.
      * @Param buff: TDFE payload.
    }
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TDFE); overload;

    // --- Complete-buffer optimized variants ------------------------------------
    {
      * Sends a TDFE as a complete-buffer command using the stream-notify model.
      * The handler on the remote side receives a TDFE (decoded from the buffer).
      * This is an optimized replacement for classic stream-notify.
      * @Param Cmd: Command name.
      * @Param buff: TDFE payload.
    }
    procedure SendCompleteBuffer_StreamNotify(const Cmd: SystemString; buff: TDFE);

    {
      * Sends a complete-buffer stream command expecting a response via a method callback.
      * Uses the no-wait model: the command is sent and the response is delivered
      * asynchronously without blocking the caller.
      * @Param Cmd: Command name.
      * @Param buff: TDFE payload.
      * @Param OnResult: Method callback receiving the response TDFE.
    }
    procedure SendCompleteBuffer_NoWait_StreamM(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);

    {
      * Sends a complete-buffer stream command with a nested callback.
      * @Param Cmd: Command name.
      * @Param buff: TDFE payload.
      * @Param OnResult: Nested callback receiving the response.
    }
    procedure SendCompleteBuffer_NoWait_StreamP(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);

    // --- NULL (keep-alive) command ---------------------------------------------
    {
      * Sends a special NULL command that does nothing but acts as a keep-alive.
      * It can also be used to force the remote side to process pending queue items.
    }
    procedure Send_NULL();
    procedure SendNULL();
  end;

  TPeerIOClass = class of TPeerIO;
  TPeerClient = TPeerIO;
  TPeerClientClass = TPeerIOClass;
{$ENDREGION 'IO'}
{$REGION 'Z-Net'}
  TPeerIOCMDNotify = procedure(Sender: TPeerIO; const Cmd: SystemString; var Allow: Boolean) of object; { Command notify callback. }

  {
    * TStatisticsType: Statistics types for performance monitoring.
    * Each statistic tracks a specific aspect of network activity.
    * @Enum stReceiveSize: Bytes received.
    * @Enum stSendSize: Bytes sent.
    * @Enum stPhysicsFragmentCache: Fragments cached.
    * @Enum stRequest: Requests received.
    * @Enum stResponse: Responses sent.
    * @Enum stConsole: Console commands sent.
    * @Enum stStream: Stream commands sent.
    * @Enum stDirestConsole: Direct console commands sent.
    * @Enum stDirestStream: Direct stream commands sent.
    * @Enum stReceiveBigStream: Big streams received.
    * @Enum stSendBigStream: Big streams sent.
    * @Enum stReceiveCompleteBuffer: Complete buffers received.
    * @Enum stSendCompleteBuffer: Complete buffers sent.
    * @Enum stExecConsole: Console commands executed.
    * @Enum stExecStream: Stream commands executed.
    * @Enum stExecDirestConsole: Direct console commands executed.
    * @Enum stExecDirestStream: Direct stream commands executed.
    * @Enum stExecBigStream: Big stream commands executed.
    * @Enum stExecCompleteBuffer: Complete buffer commands executed.
    * @Enum stConnected: Connections established.
    * @Enum stDisconnect: Connections closed.
    * @Enum stCommandExecute_Sum: Total commands executed.
    * @Enum stCommand_Send_Sum: Total commands sent.
    * @Enum stCommand_Reg_Sum: Total commands registered.
    * @Enum stEncrypt: Encryption operations.
    * @Enum stCompress: Compression operations.
    * @Enum stGenerateHash: Hash generation operations.
    * @Enum stSequencePacketMemoryOnSending: Memory used for sending sequence packets.
    * @Enum stSequencePacketMemoryOnReceived: Memory used for received sequence packets.
    * @Enum stSequencePacketReceived: Sequence packets received.
    * @Enum stSequencePacketEcho: Sequence packet echoes.
    * @Enum stSequencePacketRequestResend: Resend requests.
    * @Enum stSequencePacketMatched: Matched sequence packets.
    * @Enum stSequencePacketPlan: Planned sequence packets.
    * @Enum stSequencePacketDiscard: Discarded sequence packets.
    * @Enum stSequencePacketDiscardSize: Discarded sequence packet data size.
    * @Enum stPause: Pause operations.
    * @Enum stContinue: Continue/resume operations.
    * @Enum stTimeOutDisconnect: Timeout disconnections.
  }
  TStatisticsType = (
    stReceiveSize, stSendSize,
    stPhysicsFragmentCache,
    stRequest, stResponse,
    stConsole, stStream, stDirestConsole, stDirestStream, stReceiveBigStream, stSendBigStream, stReceiveCompleteBuffer, stSendCompleteBuffer,
    stExecConsole, stExecStream, stExecDirestConsole, stExecDirestStream, stExecBigStream, stExecCompleteBuffer,
    stConnected, stDisconnect,
    stCommandExecute_Sum, stCommand_Send_Sum, stCommand_Reg_Sum,
    stEncrypt, stCompress, stGenerateHash,
    stSequencePacketMemoryOnSending, stSequencePacketMemoryOnReceived,
    stSequencePacketReceived, stSequencePacketEcho, stSequencePacketRequestResend,
    stSequencePacketMatched, stSequencePacketPlan, stSequencePacketDiscard, stSequencePacketDiscardSize,
    stPause, stContinue,
    stTimeOutDisconnect
    );

  TPeerIOList_C = procedure(P_IO: TPeerIO); { Callback types for iterating over IO lists. }
  TPeerIOList_M = procedure(P_IO: TPeerIO) of object;
{$IFDEF FPC}
  TPeerIOList_P = procedure(P_IO: TPeerIO) is nested;
{$ELSE FPC}
  TPeerIOList_P = reference to procedure(P_IO: TPeerIO);
{$ENDIF FPC}

  {
    * IIOInterface: Interface for IO creation/destruction notifications.
    * Implement this interface to receive callbacks when connections are created or destroyed.
    * @Method PeerIO_Create: Called when a new connection is established.
    * @Method PeerIO_Destroy: Called when a connection is closed.
    * @Example:
    *   type
    *     TMyHandler = class(TInterfacedObject, IIOInterface)
    *       procedure PeerIO_Create(const Sender: TPeerIO);
    *       procedure PeerIO_Destroy(const Sender: TPeerIO);
    *     end;
  }
  IIOInterface = interface
    procedure PeerIO_Create(const Sender: TPeerIO);
    procedure PeerIO_Destroy(const Sender: TPeerIO);
  end;

  TIO_Array = array of Cardinal; { Array of IO IDs. }
  TIO_Order = class(TOrderStruct<Cardinal>); { Ordered FIFO of IO IDs. }

  {
    * IZNet_VMInterface: Interface for P2PVM tunnel events.
    * Implement this to handle P2PVM authentication and tunnel lifecycle events.
    * @Method p2pVMTunnelAuth: Called when authentication is requested.
    * @Method p2pVMTunnelOpenBefore: Called before the tunnel opens.
    * @Method p2pVMTunnelOpen: Called when the tunnel opens.
    * @Method p2pVMTunnelOpenAfter: Called after the tunnel opens.
    * @Method p2pVMTunnelClose: Called when the tunnel closes.
  }
  IZNet_VMInterface = interface
    procedure p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean);
    procedure p2pVMTunnelOpenBefore(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelOpen(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelOpenAfter(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
    procedure p2pVMTunnelClose(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
  end;

  {
    * IOnBigStreamInterface: Interface for big-stream progress notifications.
    * Implement this to receive progress updates during large file transfers.
    * @Method BeginStream: Called when a big-stream transfer begins.
    * @Method Process: Called during the transfer with progress updates.
    * @Method EndStream: Called when the transfer completes.
    * @Example:
    *   type
    *     TMyProgress = class(TInterfacedObject, IOnBigStreamInterface)
    *       procedure BeginStream(Sender: TPeerIO; Total: Int64);
    *       procedure Process(Sender: TPeerIO; Total, current: Int64);
    *       procedure EndStream(Sender: TPeerIO; Total: Int64);
    *     end;
  }
  IOnBigStreamInterface = interface
    procedure BeginStream(Sender: TPeerIO; Total: Int64);
    procedure Process(Sender: TPeerIO; Total, current: Int64);
    procedure EndStream(Sender: TPeerIO; Total: Int64);
  end;

  TCommunicationProtocol = (cpZServer, cpCustom); { Communication protocol type. }
  TProgressOnZNet = procedure(Sender: TZNet) of object; { Progress callback for TZNet. }

  {
    * TAutomatedP2PVMServiceData: Data for automated P2PVM service binding.
    * @Field Service: P2PVM server instance. Set by AddService.
  }
  TAutomatedP2PVMServiceData = record
    Service: TZNet_WithP2PVM_Server; { P2PVM server instance. Set by AddService. }
  end;

  PAutomatedP2PVMServiceData = ^TAutomatedP2PVMServiceData;

  {
    * TAutomatedP2PVMServiceBind: Collection of automated P2PVM service bindings.
    * Manages multiple P2PVM servers that should be automatically exposed.
    * @Example:
    *   Bind := TAutomatedP2PVMServiceBind.Create;
    *   Bind.AddService(MyServer, '::1', 12345);  // Expose MyServer over P2PVM
  }
  TAutomatedP2PVMServiceBind = class(TGenericsList<PAutomatedP2PVMServiceData>)
  public
    procedure AddService(Service: TZNet_WithP2PVM_Server; IPV6: SystemString; Port: Word); overload;
    procedure AddService(Service: TZNet_WithP2PVM_Server); overload;
    procedure RemoveService(Service: TZNet_WithP2PVM_Server);
    procedure Clean;
    function FoundService(Service: TZNet_WithP2PVM_Server): PAutomatedP2PVMServiceData;
  end;

  {
    * TAutomatedP2PVMClientData: Data for automated P2PVM client binding.
    * @Field Client: P2PVM client instance. Set by AddClient.
    * @Field IPV6: IPv6 address for connection. Set by AddClient.
    * @Field Port: Port for connection. Set by AddClient.
    * @Field RequestConnecting: Whether a connection request is in progress. Set internally.
  }
  TAutomatedP2PVMClientData = record
    Client: TZNet_WithP2PVM_Client; { P2PVM client instance. Set by AddClient. }
    IPV6: SystemString; { IPv6 address for connection. Set by AddClient. }
    Port: Word; { Port for connection. Set by AddClient. }
    RequestConnecting: Boolean; { Whether a connection request is in progress. Set internally. }
  end;

  PAutomatedP2PVMClientData = ^TAutomatedP2PVMClientData;

  {
    * TAutomatedP2PVMClientBind: Collection of automated P2PVM client bindings.
    * Manages multiple P2PVM clients that should be automatically connected.
    * @Example:
    *   Bind := TAutomatedP2PVMClientBind.Create;
    *   Bind.AddClient(MyClient, '::1', 12345);  // Auto-connect MyClient over P2PVM
  }
  TAutomatedP2PVMClientBind = class(TGenericsList<PAutomatedP2PVMClientData>)
  public
    procedure AddClient(Client: TZNet_WithP2PVM_Client; IPV6: SystemString; Port: Word);
    procedure RemoveClient(Client: TZNet_WithP2PVM_Client);
    procedure Clean;
    function FoundClient(Client: TZNet_WithP2PVM_Client): PAutomatedP2PVMClientData;
  end;

  TZNet_Progress_Pool_ = TBigList<TZNet_Progress>; { Pool of progress objects. }

  {
    * TZNet_Progress_Pool: Pool for TZNet_Progress objects with automatic cleanup.
  }
  TZNet_Progress_Pool = class(TZNet_Progress_Pool_)
  public
    procedure DoFree(var data: TZNet_Progress); override;
  end;

  {
    * TZNet_Progress: A progress event attached to a TZNet instance.
    * This is the main event handler for periodic operations on the network framework.
    * @Field FPool_Ptr: Pointer in pool. Set by constructor.
    * @Field FOwnerFramework: Parent framework. Set by constructor.
    * @Field OnFree: Free callback. Set by user.
    * @Field OnProgress_C: C-style progress callback. Set by user.
    * @Field OnProgress_M: Method progress callback. Set by user.
    * @Field OnProgress_P: Nested/reference progress callback. Set by user.
    * @Field NextProgressDoFree: Whether to free on next progress. Set by user.
    * @Example:
    *   var Progress: TZNet_Progress;
    *   begin
    *     Progress := MyNet.AddProgresss;
    *     Progress.OnProgress_M := MyProgressHandler;
    *     // Progress() is called automatically during MyNet.Progress()
    *   end;
  }
  TZNet_Progress = class(TCore_Object_Intermediate)
  private
    FPool_Ptr: TZNet_Progress_Pool_.PQueueStruct; { Pointer in pool. Set by constructor. }
    FOwnerFramework: TZNet; { Parent framework. Set by constructor. }
  public
    OnFree: TZNet_Progress_Free_OnEvent; { Free callback. Set by user. }
    OnProgress_C: TZNet_Progress_OnEvent_C; { C-style progress callback. Set by user. }
    OnProgress_M: TZNet_Progress_OnEvent_M; { Method progress callback. Set by user. }
    OnProgress_P: TZNet_Progress_OnEvent_P; { Nested/reference progress callback. Set by user. }
    NextProgressDoFree: Boolean; { Whether to free on next progress. Set by user. }
    property OwnerFramework: TZNet read FOwnerFramework;
    constructor Create(OwnerFramework_: TZNet);
    destructor Destroy; override;
    procedure Progress; virtual;
    procedure ResetEvent;
  end;

  TPrint_Param_Hash_Pool = class(TCritical_String_Big_Hash_Pair_Pool<Boolean>); { Hash pool for print parameters (used to filter verbose output). }
  TPeer_IO_Hash_Pool = class(TCritical_Big_Hash_Pair_Pool<Cardinal, TPeerIO>); { Hash pool mapping IO ID to TPeerIO. }

  {
    * TZNet_Instance_Pool: Global pool of all TZNet instances (for debugging and status).
    * Tracks every active network framework instance.
  }
  TZNet_Instance_Pool = class(TCritical_BigList<TZNet>)
  public
    procedure Print_Status;
    procedure Print_Service_Statistics_Info;
    procedure Print_Service_CMD_Info;
    procedure Print_Client_Statistics_Info;
    procedure Print_Client_CMD_Info;
  end;

  TCommand_Tick_Hash_Pool = class(TCritical_String_Big_Hash_Pair_Pool<TTimeTick>) { Statistics for command execution times. }
  public
    procedure SetMax(Key_: SystemString; Value_: TTimeTick); overload;
    procedure SetMax(Source: TCommand_Tick_Hash_Pool); overload;
    procedure GetKeyList(output: TPascalStringList);
  end;

  TCommand_Num_Hash_Pool = class(TCritical_String_Big_Hash_Pair_Pool<Integer>) { Statistics for command counts. }
  public
    procedure IncValue(Key_: SystemString; Value_: Integer); overload;
    procedure IncValue(Source: TCommand_Num_Hash_Pool); overload;
    procedure GetKeyList(output: TPascalStringList);
  end;

  {
    * TCommand_Hash_Pool: Pool of registered commands.
    * Maps command names to their TCommand_base instances.
  }
  TCommand_Hash_Pool = class(TCritical_String_Big_Hash_Pair_Pool<TCommand_base>)
  public
    procedure DoFree(var Key: SystemString; var Value: TCommand_base); override;
  end;

  {
    * TZNet: Base network framework class.
    * Manages command registration, IO connections, progress callbacks, statistics,
    * security settings, and P2PVM integration. Both server and client implementations
    * inherit from this class.
    * @Field FCritical: Global lock for IO operations. Created by constructor.
    * @Field FZNet_Instance_Ptr__: Pointer in global instance pool. Set by constructor.
    * @Field FCommand_Hash_Pool: Registered command pool. Created by constructor.
    * @Field FPeerIO_HashPool: IO hash pool. Created by constructor.
    * @Field FIDSeed: ID generator seed. Initialised by constructor.
    * @Field FProgress_CPS: Progress CPS meter. Created by constructor.
    * @Field FProgress_Pool: Progress event pool. Created by constructor.
    * @Field FOnExecuteCommand: Command execution hook. Set by user.
    * @Field FOnSendCommand: Command send hook. Set by user.
    * @Field FIdleTimeOut: Idle timeout. Set by user.
    * @Field FSendDataCompressed: Whether to compress sent data. Set by user.
    * @Field FCompleteBufferCompressed: Whether to compress complete buffers. Set by user.
    * @Field FFastEncrypt: Whether to use fast encryption. Set by user.
    * @Field FUsedParallelEncrypt: Whether to use parallel encryption. Set by user.
    * @Field FSyncOnResult: Whether results are synchronously processed. Set by user.
    * @Field FSyncOnCompleteBuffer: Whether complete buffers are synchronously processed. Set by user.
    * @Field FBigStreamMemorySwapSpace: Whether to use memory swap for big streams. Set by user.
    * @Field FEnabledAtomicLockAndMultiThread: Whether atomic locking is enabled. Set by user.
    * @Field FTimeOutKeepAlive: Whether to send keep-alive on timeout. Set by user.
    * @Field FQuietMode: Quiet mode flag. Set by user.
    * @Field FPer_Progress_Loop_Limit: Max commands per progress loop. Set by constructor.
    * @Field FMaxCompleteBufferSize: Max complete-buffer size. Set by constructor.
    * @Field FCompleteBufferSwapSpace: Whether to use swap for complete buffers. Set by user.
    * @Field FFrameworkIsServer: Whether this framework is a server. Set by constructor.
    * @Field FFrameworkIsClient: Whether this framework is a client. Set by constructor.
    * @Field FProgressEnabled: Whether progress is enabled. Set by Enabled_Progress/Disable_Progress.
    * @Field FOnProgress: Progress callback. Set by user.
    * @Field FProtocol: Communication protocol. Set by user.
    * @Field FSequencePacketActivted: Whether sequence packet model is active. Set by user.
    * @Field FName: Name for logging. Set by user.
    * @Example:
    *   // TZNet is the base class for all network frameworks.
    *   // Typically you use TZNet_Server or TZNet_Client directly.
    *   var Net: TZNet_Server;
    *   begin
    *     Net := TZNet_Server.Create;
    *     Net.RegisterConsole('ping').OnExecute := MyPingHandler;
    *     Net.StartService('0.0.0.0', 8080);
    *     while Running do
    *       Net.Progress;  // Drive the network
    *   end;
  }
  TZNet = class(TCore_InterfacedObject_Intermediate)
  private
    FCritical, FSend_Critical: TCritical; { Global lock for IO operations. Created by constructor. }
    FZNet_Instance_Ptr__: TZNet_Instance_Pool.PQueueStruct; { Pointer in global instance pool. Set by constructor. }
    FCommand_Hash_Pool: TCommand_Hash_Pool; { Registered command pool. Created by constructor. }
    FPeerIO_HashPool: TPeer_IO_Hash_Pool; { IO hash pool. Created by constructor. }
    FIDSeed: Cardinal; { ID generator seed. Initialised by constructor. }
    FProgress_CPS: TCPS_Tool; { Progress CPS meter. Created by constructor. }
    FProgress_Pool: TZNet_Progress_Pool; { Progress event pool. Created by constructor. }
    FOnExecuteCommand: TPeerIOCMDNotify; { Command execution hook. Set by user. }
    FOnSendCommand: TPeerIOCMDNotify; { Command send hook. Set by user. }
    FPeerIOUserDefineClass: TPeer_IO_User_Define_Class; { Factory class for UserDefine. Set by constructor/property. }
    FPeerIOUserSpecialClass: TPeer_IO_User_Special_Class; { Factory class for UserSpecial. Set by constructor/property. }
    FIdleTimeOut: TTimeTick; { Idle timeout. Set by user. }
    FPhysicsFragmentSwapSpaceTechnology: Boolean; { Whether to use swap space for fragments. Set by user. }
    FPhysicsFragmentSwapSpaceTrigger: NativeInt; { Trigger size for fragment swap. Set by user. }
    FSend_Queue_Swap_Pool: TCritical_QueueData_Pool; { Global send queue swap pool. Created by constructor. }
    FSendFlushSize: NativeInt; { default ZNet_Def_SendFlushSize }
    FSendDataCompressed: Boolean; { Whether to compress sent data. Set by user. }
    FCompleteBufferCompressed: Boolean; { Whether to compress complete buffers. Set by user. }
    FFastEncrypt: Boolean; { Whether to use fast encryption. Set by user. }
    FUsedParallelEncrypt: Boolean; { Whether to use parallel encryption. Set by user. }
    FSyncOnResult: Boolean; { Whether results are synchronously processed. Set by user. }
    FSyncOnCompleteBuffer: Boolean; { Whether complete buffers are synchronously processed. Set by user. }
    FBigStreamMemorySwapSpace: Boolean; { Whether to use memory swap for big streams. Set by user. }
    FBigStreamSwapSpaceTriggerSize: Int64; { Trigger size for big-stream swap. Set by user. }
    FEnabledAtomicLockAndMultiThread: Boolean; { Whether atomic locking is enabled. Set by user. }
    FTimeOutKeepAlive: Boolean; { Whether to send keep-alive on timeout. Set by user. }
    FQuietMode: Boolean; { Quiet mode flag. Set by user. }
    FCipherSecurityArray: TCipherSecurityArray; { Available cipher list. Set by constructor. }
    FHashSecurity: THashSecurity; { Hash security level. Set by constructor. }
    FPer_Progress_Loop_Limit: Integer; { Max commands per progress loop. Set by constructor. }
    FExtract_Physics_Fragment_Max_Size: Int64; { Max fragment extraction size. Set by constructor. }
    FMaxCompleteBufferSize: Cardinal; { Max complete-buffer size. Set by constructor. }
    FCompleteBufferCompressionCondition: Cardinal; { Minimum size for compression. Set by constructor. }
    FCompleteBufferSwapSpace: Boolean; { Whether to use swap for complete buffers. Set by user. }
    FCompleteBufferSwapSpaceTriggerSize: Int64; { Trigger size for complete-buffer swap. Set by user. }
    FAutomaticWaitRemoteReponse: Boolean; { Whether to auto-wait for remote responses. Set by user. }
    FEncrypt_P2PVM_Packet: Boolean; { Whether to encrypt P2PVM packets. Set by user. }
    FPrintParams: TPrint_Param_Hash_Pool; { Print parameter filter. Created by constructor. }
    FPostProgress: TN_Progress_ToolWithCadencer; { Post-progress tool. Created by constructor. }
    FFrameworkIsServer: Boolean; { Whether this framework is a server. Set by constructor. }
    FFrameworkIsClient: Boolean; { Whether this framework is a client. Set by constructor. }
    FFrameworkInfo: SystemString; { Framework info string. Set by constructor. }
    FProgressRuning: Boolean; { Progress re-entry guard. Set by Progress. }
    FProgressEnabled: Boolean; { Whether progress is enabled. Set by Enabled_Progress/Disable_Progress. }
    FProgressWaitRuning: Boolean; { Progress-wait re-entry guard. Set by ProgressWaitSend. }
    FOnProgress: TProgressOnZNet; { Progress callback. Set by user. }
    FCMD_Thread_Runing_Num: Integer; { Number of running command threads. Managed internally. }
    FIOInterface: IIOInterface; { IO interface. Set by user. }
    FVMInterface: IZNet_VMInterface; { P2PVM interface. Set by user. }
    FOnBigStreamInterface: IOnBigStreamInterface; { Big-stream interface. Set by user. }
    FProtocol: TCommunicationProtocol; { Communication protocol. Set by user. }
    FSequencePacketActivted: Boolean; { Whether sequence packet model is active. Set by user. }
    FPrefixName: SystemString; { Prefix for logging. Set by user. }
    FName: SystemString; { Name for logging. Set by user. }
    FInitedTimeMD5: TMD5; { MD5 of init time. Set by constructor. }
    FDoubleChannelFramework: TCore_Object; { Double-tunnel framework reference. Set by user. }
    FCustomUserData: Pointer; { Custom user pointer. Set by user. }
    FCustomUserObject: TCore_Object; { Custom user object. Set by user. }
  protected
    procedure DoPrint(const v: SystemString); virtual;
    procedure DoError(const v: SystemString); virtual;
    procedure DoWarning(const v: SystemString); virtual;
    function GetIdleTimeOut: TTimeTick; virtual;
    procedure SetIdleTimeOut(const Value: TTimeTick); virtual;
    function CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; virtual;
    function CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; virtual;
    function CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean; virtual;
    procedure DelayClose(Sender: TN_Post_Execute);
    procedure DelayFree(Sender: TN_Post_Execute);
    procedure DelayExecuteOnResultState(Sender: TN_Post_Execute);
    procedure DelayExecuteOnCompleteBufferState(Sender: TN_Post_Execute);
    procedure IDLE_Trace_Execute(Sender: TN_Post_Execute);
    procedure cmd_Complete_Buffer_Stream_Reponse(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
    function MakeID: Cardinal;
    procedure FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean); virtual;
    procedure Framework_Internal_Send_Byte_Buffer(const Sender: TPeerIO; const buff: PByte; siz: NativeInt);
    procedure Framework_Internal_Save_Receive_Buffer(const Sender: TPeerIO; const buff: Pointer; siz: Int64);
    procedure Framework_Internal_Process_Receive_Buffer(const Sender: TPeerIO);
    procedure Framework_Internal_Process_Send_Buffer(const Sender: TPeerIO);
    procedure Framework_Internal_IO_Create(const Sender: TPeerIO); virtual;
    procedure Framework_Internal_IO_Destroy(const Sender: TPeerIO); virtual;
    procedure Build_P2PAuth_Token_Result_On_IO_IDLE(Sender: TCore_Object);
    procedure Do_CMD_Result_BuildP2PAuthToken(Sender: TPeerIO; Result_: TDFE);
    procedure CMD_BuildP2PAuthToken(Sender: TPeerIO; InData, OutData: TDFE);
    procedure CMD_InitP2PTunnel(Sender: TPeerIO; InData: SystemString);
    procedure CMD_CloseP2PTunnel(Sender: TPeerIO; InData: SystemString);
    procedure VMAuthSuccessAfterDelayExecute(Sender: TN_Post_Execute);
    procedure VMAuthSuccessDelayExecute(Sender: TN_Post_Execute);
    procedure VMAuthFailedDelayExecute(Sender: TN_Post_Execute);
    procedure CMD_NULL(Sender: TPeerIO; InData: SystemString; var OutData: SystemString);
    { Command execution. }
    function ExecuteConsole(Sender: TPeerIO; const Cmd: SystemString; const InData: SystemString; var OutData: SystemString): Boolean; virtual;
    function ExecuteStream(Sender: TPeerIO; const Cmd: SystemString; InData, OutData: TDFE): Boolean; virtual;
    function ExecuteStreamNotify(Sender: TPeerIO; const Cmd: SystemString; InData: TDFE): Boolean; virtual;
    function ExecuteConsoleNotify(Sender: TPeerIO; const Cmd: SystemString; const InData: SystemString): Boolean; virtual;
    function ExecuteBigStream(Sender: TPeerIO; const Cmd: SystemString; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64): Boolean; virtual;
    function ExecuteCompleteBuffer(Sender: TPeerIO; const Cmd: SystemString; InData: PByte; DataSize: NativeInt): Boolean; virtual;
  protected
    { Automated P2PVM }
    FAutomatedP2PVMServiceBind: TAutomatedP2PVMServiceBind; { Automated P2PVM service bindings. Created by InitAutomatedP2PVM. }
    FAutomatedP2PVMService: Boolean; { Whether automated P2PVM service is enabled. Set by user. }
    FAutomatedP2PVMClientBind: TAutomatedP2PVMClientBind; { Automated P2PVM client bindings. Created by InitAutomatedP2PVM. }
    FAutomatedP2PVMClient: Boolean; { Whether automated P2PVM client is enabled. Set by user. }
    FAutomatedP2PVMClientDelayBoot: Double; { Delay before booting automated P2PVM client. Set by user. }
    FAutomatedP2PVMAuthToken: SystemString; { Authentication token for automated P2PVM. Set by user. }
    FOnAutomatedP2PVMClientConnectionDone_C: TOnAutomatedP2PVMClientConnectionDone_C; { Automated P2PVM done (C). Set by user. }
    FOnAutomatedP2PVMClientConnectionDone_M: TOnAutomatedP2PVMClientConnectionDone_M; { Automated P2PVM done (method). Set by user. }
    FOnAutomatedP2PVMClientConnectionDone_P: TOnAutomatedP2PVMClientConnectionDone_P; { Automated P2PVM done (nested). Set by user. }
    procedure InitAutomatedP2PVM;
    procedure FreeAutomatedP2PVM;
    procedure DoAutomatedP2PVMClient_DelayRequest(Sender: TN_Post_Execute);
    procedure DoAutomatedP2PVMClient_Request(IO_ID: Cardinal);
    procedure AutomatedP2PVMClient_BuildP2PAuthTokenResult(P_IO: TPeerIO);
    procedure AutomatedP2PVMClient_OpenP2PVMTunnelResult(P_IO: TPeerIO; VMauthState: Boolean);
    procedure AutomatedP2PVMClient_ConnectionResult(Param1: Pointer; Param2: TObject; const ConnectionState: Boolean);
    procedure AutomatedP2PVMClient_Delay_Done(Sender: TN_Post_Execute);
    procedure AutomatedP2PVMClient_Done(P_IO: TPeerIO);
  protected
    { Large-scale IO support }
    FProgress_LargeScale_IO_Pool: TIO_Order; { Large-scale IO progress order. Created by InitLargeScaleIOPool. }
    FProgressMaxDelay: TTimeTick; { Max delay for large-scale progress. Set by user. }
    procedure InitLargeScaleIOPool;
    procedure FreeLargeScaleIOPool;
    procedure ProgressLargeScaleIOPool;
  public
    Statistics: array [TStatisticsType] of Int64; { Performance statistics. }
    CmdRecvStatistics: TCommand_Num_Hash_Pool; { Received command statistics. Created by constructor. }
    CmdSendStatistics: TCommand_Num_Hash_Pool; { Sent command statistics. Created by constructor. }
    CmdMaxExecuteConsumeStatistics: TCommand_Tick_Hash_Pool; { Command execution time statistics. Created by constructor. }
  public
    constructor Create(HashPoolSize: Integer);
    procedure CreateAfter; virtual;
    destructor Destroy; override;
    property Send_Critical: TCritical read FSend_Critical;
    { Sequence packet activation. }
    property SequencePacketActivted: Boolean read FSequencePacketActivted write FSequencePacketActivted;
    { Queue swap technology. }
    procedure Post_Queue_Data_To_Swap_Queue(p: PQueueData);
    { Progress event pool. }
    property Progress_Pool: TZNet_Progress_Pool read FProgress_Pool;
    function AddProgresss(Progress_: TZNet_Progress_Class): TZNet_Progress; overload;
    function AddProgresss(): TZNet_Progress; overload;
    { User protocol support. }
    property Protocol: TCommunicationProtocol read FProtocol write FProtocol;
    procedure BeginWriteCustomBuffer(P_IO: TPeerIO);
    procedure EndWriteCustomBuffer(P_IO: TPeerIO);
    procedure WriteCustomBuffer(P_IO: TPeerIO; const Buffer: PByte; const Size: NativeInt);
    { debug support. }
    property PrefixName: SystemString read FPrefixName write FPrefixName;
    property name: SystemString read FName write FName;
    { IO backcall interface. }
    property IOInterface: IIOInterface read FIOInterface write FIOInterface;
    { P2PVM backcall interface. }
    property VMInterface: IZNet_VMInterface read FVMInterface write FVMInterface;
    property OnVMInterface: IZNet_VMInterface read FVMInterface write FVMInterface;
    property OnVM: IZNet_VMInterface read FVMInterface write FVMInterface;
    procedure p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean); virtual;
    procedure p2pVMTunnelOpenBefore(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM); virtual;
    procedure p2pVMTunnelOpen(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM); virtual;
    procedure p2pVMTunnelOpenAfter(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM); virtual;
    procedure p2pVMTunnelClose(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM); virtual;
    { Automated P2PVM service support. }
    property AutomatedP2PVMServiceBind: TAutomatedP2PVMServiceBind read FAutomatedP2PVMServiceBind;
    property AutomatedP2PVMBindService: TAutomatedP2PVMServiceBind read FAutomatedP2PVMServiceBind;
    property AutomatedP2PVMService: Boolean read FAutomatedP2PVMService write FAutomatedP2PVMService;
    { Automated P2PVM client support. }
    property AutomatedP2PVMClientBind: TAutomatedP2PVMClientBind read FAutomatedP2PVMClientBind;
    property AutomatedP2PVMBindClient: TAutomatedP2PVMClientBind read FAutomatedP2PVMClientBind;
    property AutomatedP2PVMClient: Boolean read FAutomatedP2PVMClient write FAutomatedP2PVMClient;
    property AutomatedP2PVMClientDelayBoot: Double read FAutomatedP2PVMClientDelayBoot write FAutomatedP2PVMClientDelayBoot;
    property AutomatedP2PVMAuthToken: SystemString read FAutomatedP2PVMAuthToken write FAutomatedP2PVMAuthToken;
    property OnAutomatedP2PVMClientConnectionDone_C: TOnAutomatedP2PVMClientConnectionDone_C read FOnAutomatedP2PVMClientConnectionDone_C write FOnAutomatedP2PVMClientConnectionDone_C;
    property OnAutomatedP2PVMClientConnectionDone_M: TOnAutomatedP2PVMClientConnectionDone_M read FOnAutomatedP2PVMClientConnectionDone_M write FOnAutomatedP2PVMClientConnectionDone_M;
    property OnAutomatedP2PVMClientConnectionDone_P: TOnAutomatedP2PVMClientConnectionDone_P read FOnAutomatedP2PVMClientConnectionDone_P write FOnAutomatedP2PVMClientConnectionDone_P;
    function AutomatedP2PVMClientConnectionDone(P_IO: TPeerIO): Boolean; overload;
    function AutomatedP2PVMClientConnectionDone(): Boolean; overload;
    procedure AutomatedP2PVM_Open(P_IO: TPeerIO); overload;
    procedure AutomatedP2PVM_Open(); overload;
    procedure AutomatedP2PVM_Open_C(P_IO: TPeerIO; const OnResult: TOnIOState_C);
    procedure AutomatedP2PVM_Open_M(P_IO: TPeerIO; const OnResult: TOnIOState_M);
    procedure AutomatedP2PVM_Open_P(P_IO: TPeerIO; const OnResult: TOnIOState_P);
    procedure AutomatedP2PVM_Close(P_IO: TPeerIO); overload;
    procedure AutomatedP2PVM_Close(); overload;
    function p2pVMTunnelReadyOk(P_IO: TPeerIO): Boolean; overload;
    function p2pVMTunnelReadyOk(): Boolean; overload;
    { IO Big Stream interface. }
    property OnBigStreamInterface: IOnBigStreamInterface read FOnBigStreamInterface write FOnBigStreamInterface;
    property OnBigStream: IOnBigStreamInterface read FOnBigStreamInterface write FOnBigStreamInterface;
    { Security support. }
    procedure SwitchMaxPerformance; virtual;
    procedure SwitchMaxSecurity; virtual;
    procedure SwitchDefaultPerformance; virtual;
    { Atomic lock for send. }
    procedure LockSend;
    procedure UnLockSend;
    { Atomic lock for all IO. }
    procedure Lock_All_IO; virtual;
    procedure UnLock_All_IO; virtual;
    { Delay run support. }
    property ProgressEngine: TN_Progress_ToolWithCadencer read FPostProgress;
    property ProgressPost: TN_Progress_ToolWithCadencer read FPostProgress;
    property PostProgress: TN_Progress_ToolWithCadencer read FPostProgress;
    property PostRun: TN_Progress_ToolWithCadencer read FPostProgress;
    property PostExecute: TN_Progress_ToolWithCadencer read FPostProgress;
    { Framework identity. }
    property FrameworkIsServer: Boolean read FFrameworkIsServer;
    property FrameworkIsClient: Boolean read FFrameworkIsClient;
    property FrameworkInfo: SystemString read FFrameworkInfo;
    function IOBusy(): Boolean;
    { Main progress loop. }
    property Progress_CPS: TCPS_Tool read FProgress_CPS;
    procedure Enabled_Progress;
    procedure Disable_Progress;
    procedure Progress; virtual;
    property OnProgress: TProgressOnZNet read FOnProgress write FOnProgress;
    procedure Progress_IO_Now_Send(IO_: TPeerIO);
    { Progress all IO with callbacks. }
    procedure ProgressPeerIOC(const OnBackcall: TPeerIOList_C); overload;
    procedure ProgressPeerIOM(const OnBackcall: TPeerIOList_M); overload;
    procedure ProgressPeerIOP(const OnBackcall: TPeerIOList_P); overload;
    procedure FastProgressPeerIOC(const OnBackcall: TPeerIOList_C); overload;
    procedure FastProgressPeerIOM(const OnBackcall: TPeerIOList_M); overload;
    procedure FastProgressPeerIOP(const OnBackcall: TPeerIOList_P); overload;
    { IO array and order. }
    procedure GetIO_Array(out IO_Array: TIO_Array); overload;
    procedure GetIO_Order(Order_: TIO_Order); overload;
    { Block progress for wait-send. }
    procedure ProgressWaitSend(P_IO: TPeerIO); overload; virtual;
    function ProgressWaitSend(IO_ID: Cardinal): Boolean; overload;

    { Print diagnostics. }
    procedure Print(const v: SystemString; const Args: array of const); overload;
    procedure Print(const v: SystemString); overload;
    procedure PrintParam(const v, Args: SystemString);
    procedure Error(const v: SystemString; const Args: array of const); overload;
    procedure Error(const v: SystemString); overload;
    procedure ErrorParam(const v, Args: SystemString);
    procedure PrintError(const v: SystemString; const Args: array of const); overload;
    procedure PrintError(const v: SystemString); overload;
    procedure PrintErrorParam(const v, Args: SystemString);
    procedure Warning(const v: SystemString);
    procedure WarningParam(const v, Args: SystemString);
    procedure PrintWarning(const v: SystemString);
    procedure PrintWarningParam(const v, Args: SystemString);
    procedure PrintRegistedCMD; overload;
    procedure PrintRegistedCMD(prefix: SystemString; incl_internalCMD: Boolean); overload;
    procedure PrintRegistedCMD(prefix: SystemString); overload;

    { Command registration. }
    function RemoveRegistedCMD(const Cmd: SystemString): Boolean;
    function DeleteRegistedCMD(const Cmd: SystemString): Boolean;
    function UnRegisted(const Cmd: SystemString): Boolean;
    function ExistsRegistedCmd(const Cmd: SystemString): Boolean;

    {
      * Registers a console (string-based) command that expects a response.
      * The command handler receives the incoming string and can modify an
      * output string variable to send back a reply. This is the standard
      * synchronous request-response model for text-based commands.
      * @Param Cmd: The name of the command to register.
      * @Returns: A TCommandConsole instance. Assign its OnExecute event
      *           to implement the command logic.
      * @Example:
      *   var Cmd: TCommandConsole;
      *   begin
      *     Cmd := MyNet.RegisterConsole('ping');
      *     Cmd.OnExecute := procedure(S: TPeerIO; In: string; var Out: string)
      *     begin
      *       Out := 'pong: ' + In;
      *     end;
      *   end;
    }
    function RegisterConsole(const Cmd: SystemString): TCommandConsole;

    {
      * Registers a stream (DFE-based) command that expects a response.
      * The handler receives an input TDFE and fills an output TDFE with the
      * structured result. Suitable for binary or complex data exchanges.
      * @Param Cmd: The command name.
      * @Returns: A TCommandStream instance for setting the handler.
      * @Example:
      *   var Cmd: TCommandStream;
      *   begin
      *     Cmd := MyNet.RegisterStream('getData');
      *     Cmd.OnExecute := procedure(S: TPeerIO; In, Out: TDFE)
      *     begin
      *       Out.WriteString('data');
      *     end;
      *   end;
    }
    function RegisterStream(const Cmd: SystemString): TCommandStream;

    {
      * Registers a stream notification command (no response expected).
      * The handler receives an input TDFE but does not send a reply. Ideal
      * for one-way data pushes, logging, or telemetry.
      * @Param Cmd: The command name.
      * @Returns: A TCommandStreamNotify instance.
    }
    function RegisterStreamNotify(const Cmd: SystemString): TCommandStreamNotify;

    {
      * Registers a console notification command (no response expected).
      * The handler receives a string input without sending a reply. Used
      * for fire-and-forget text commands.
      * @Param Cmd: The command name.
      * @Returns: A TCommandConsoleNotify instance.
    }
    function RegisterConsoleNotify(const Cmd: SystemString): TCommandConsoleNotify;

    {
      * Registers a big-stream command for handling large data transfers.
      * The handler receives a TCore_Stream (e.g., file stream) and progress
      * information (total and completed bytes). Supports chunked reception.
      * @Param Cmd: The command name.
      * @Returns: A TCommandBigStream instance.
    }
    function RegisterBigStream(const Cmd: SystemString): TCommandBigStream;

    {
      * Registers a complete-buffer command. The handler receives a raw
      * memory block (PByte + size) that has been fully reassembled. Suitable
      * for atomic data blocks with guaranteed ordering and integrity.
      * @Param Cmd: The command name.
      * @Returns: A TCommandCompleteBuffer instance.
    }
    function RegisterCompleteBuffer(const Cmd: SystemString): TCommandCompleteBuffer;

    { Optimized replacement for StreamNotify using complete-buffer technology.
      This variant decodes the complete buffer into a DFE and executes the
      handler synchronously (on the main thread). It provides better
      performance than the classic StreamNotify model by reducing protocol
      overhead and simplifying buffer assembly. To use, register the command
      and assign its OnExecute event (which receives a TDFE).
    }
    function RegisterCompleteBuffer_StreamNotify(const Cmd: SystemString): TCommandCompleteBuffer_StreamNotify;

    { Optimized replacement for StreamNotify using complete-buffer + threading.
      Similar to RegisterCompleteBuffer_StreamNotify, but the decoding and
      handler execution are performed in a background thread (asynchronous).
      This avoids blocking the main loop and is ideal for heavy processing.
      Set Sync_Decrypt = False to enable threading mode; the handler will be
      invoked on the main thread after the background work completes.
    }
    function RegisterCompleteBuffer_Asynchronous_StreamNotify(const Cmd: SystemString): TCommandCompleteBuffer_StreamNotify;

    { Optimized replacement for Stream (request-response) using complete-buffer.
      This variant uses the complete-buffer protocol to send a stream command
      that expects a response, but without waiting for the reply (non-blocking).
      The response is delivered asynchronously via a callback. This model
      reduces latency and improves throughput for high-frequency requests.
      @Param Cmd: The command name.
      @Returns: A TCommandCompleteBuffer_NoWait_Stream instance.
      Set Execute_In_Thread = True to offload processing to a background thread.
    }
    function RegisterCompleteBuffer_NoWait_Stream(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Stream;

    { Optimized replacement for Stream using complete-buffer + threading.
      This is the threaded version of RegisterCompleteBuffer_NoWait_Stream:
      the handler always runs in a background thread, and the result is sent
      asynchronously. It is suitable for CPU-intensive tasks that should not
      block the main network loop. Simply assign the OnExecute event and
      the framework will dispatch it to the thread pool.
    }
    function RegisterCompleteBuffer_NoWait_Stream_Thread(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Stream;

    { New independent complete-buffer bridge model.
      This registers a command that uses the TCommandCompleteBuffer_NoWait_Bridge
      interface, which provides advanced control over result sending. The handler
      can pause, resume, or cancel the response delivery, and can work with
      separate receive and send tunnels. This is the most flexible complete-buffer
      command type, supporting complex asynchronous workflows and integration
      with TCompleteBuffer_Stream_Event_Bridge and HPC execution.
      @Param Cmd: The command name.
      @Returns: A TCommandCompleteBuffer_NoWait_Bridge_Stream instance.
      In the handler, you receive a TCommandCompleteBuffer_NoWait_Bridge object
      that holds InData and OutData TDFEs. Call Bridge.Pause() to delay the
      response, and Bridge.Resume() to send it later.
    }
    function RegisterCompleteBuffer_NoWait_Bridge_Stream(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Bridge_Stream;

    { IO access. }
    function FirstIO: TPeerIO;
    function LastIO: TPeerIO;
    property OnExecuteCommand: TPeerIOCMDNotify read FOnExecuteCommand write FOnExecuteCommand;
    property OnSendCommand: TPeerIOCMDNotify read FOnSendCommand write FOnSendCommand;
    function ExistsID(IO_ID: Cardinal): Boolean;
    { Security configuration. }
    property HashSecurity: THashSecurity read FHashSecurity;
    property CipherSecurityArray: TCipherSecurityArray read FCipherSecurityArray;
    function GetRandomCipherSecurity: TCipherSecurity;
    property RandomCipherSecurity: TCipherSecurity read GetRandomCipherSecurity;
    { Options. }
    property IdleTimeOut: TTimeTick read GetIdleTimeOut write SetIdleTimeOut;
    property TimeOutIDLE: TTimeTick read GetIdleTimeOut write SetIdleTimeOut;
    property FastEncrypt: Boolean read FFastEncrypt write FFastEncrypt;
    property UsedParallelEncrypt: Boolean read FUsedParallelEncrypt write FUsedParallelEncrypt;
    property SyncOnResult: Boolean read FSyncOnResult write FSyncOnResult;
    property SyncOnCompleteBuffer: Boolean read FSyncOnCompleteBuffer write FSyncOnCompleteBuffer;
    property BigStreamMemorySwapSpace: Boolean read FBigStreamMemorySwapSpace write FBigStreamMemorySwapSpace;
    property BigStreamSwapSpaceTriggerSize: Int64 read FBigStreamSwapSpaceTriggerSize write FBigStreamSwapSpaceTriggerSize;
    property EnabledAtomicLockAndMultiThread: Boolean read FEnabledAtomicLockAndMultiThread write FEnabledAtomicLockAndMultiThread;
    property TimeOutKeepAlive: Boolean read FTimeOutKeepAlive write FTimeOutKeepAlive;
    property QuietMode: Boolean read FQuietMode write FQuietMode;
    property TimeOut: TTimeTick read GetIdleTimeOut write SetIdleTimeOut;
    property PhysicsFragmentSwapSpaceTechnology: Boolean read FPhysicsFragmentSwapSpaceTechnology write FPhysicsFragmentSwapSpaceTechnology;
    property PhysicsFragmentSwapSpaceTrigger: NativeInt read FPhysicsFragmentSwapSpaceTrigger write FPhysicsFragmentSwapSpaceTrigger;
    property SendFlushSize: NativeInt read FSendFlushSize write FSendFlushSize;
    property SendDataCompressed: Boolean read FSendDataCompressed write FSendDataCompressed;
    property CompleteBufferCompressed: Boolean read FCompleteBufferCompressed write FCompleteBufferCompressed;
    property Per_Progress_Loop_Limit: Integer read FPer_Progress_Loop_Limit write FPer_Progress_Loop_Limit;
    property Extract_Physics_Fragment_Max_Size: Int64 read FExtract_Physics_Fragment_Max_Size write FExtract_Physics_Fragment_Max_Size;
    property MaxCompleteBufferSize: Cardinal read FMaxCompleteBufferSize write FMaxCompleteBufferSize;
    property CompleteBufferCompressionCondition: Cardinal read FCompleteBufferCompressionCondition write FCompleteBufferCompressionCondition;
    property CompleteBufferSwapSpace: Boolean read FCompleteBufferSwapSpace write FCompleteBufferSwapSpace;
    property CompleteBufferSwapSpaceTriggerSize: Int64 read FCompleteBufferSwapSpaceTriggerSize write FCompleteBufferSwapSpaceTriggerSize;
    property AutomaticWaitRemoteReponse: Boolean read FAutomaticWaitRemoteReponse write FAutomaticWaitRemoteReponse;
    property Encrypt_P2PVM_Packet: Boolean read FEncrypt_P2PVM_Packet write FEncrypt_P2PVM_Packet;
    property ProgressMaxDelay: TTimeTick read FProgressMaxDelay write FProgressMaxDelay;
    { copy options }
    procedure CopyParamFrom(Source: TZNet);
    procedure CopyParamTo(Dest: TZNet);
    { State. }
    property CMD_Thread_Runing_Num: Integer read FCMD_Thread_Runing_Num;
    property InitedTimeMD5: TMD5 read FInitedTimeMD5;
    { Double channel framework. }
    property DoubleChannelFramework: TCore_Object read FDoubleChannelFramework write FDoubleChannelFramework;
    { User custom. }
    property CustomUserData: Pointer read FCustomUserData write FCustomUserData;
    property CustomUserObject: TCore_Object read FCustomUserObject write FCustomUserObject;
    { Hash pool. }
    property PeerIO_HashPool: TPeer_IO_Hash_Pool read FPeerIO_HashPool;
    property IOPool: TPeer_IO_Hash_Pool read FPeerIO_HashPool;
    { User-definable class factories. }
    procedure SetPeerIOUserDefineClass(const Value: TPeer_IO_User_Define_Class);
    property PeerClientUserDefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    property PeerIOUserDefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    property IOUserDefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    property IODefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    property UserDefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    property ExternalDefineClass: TPeer_IO_User_Define_Class read FPeerIOUserDefineClass write SetPeerIOUserDefineClass;
    { User-Special class factories. }
    procedure SetPeerIOUserSpecialClass(const Value: TPeer_IO_User_Special_Class);
    property PeerClientUserSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write SetPeerIOUserSpecialClass;
    property PeerIOUserSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write FPeerIOUserSpecialClass;
    property IOUserSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write FPeerIOUserSpecialClass;
    property IOSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write FPeerIOUserSpecialClass;
    property UserSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write FPeerIOUserSpecialClass;
    property ExternalSpecialClass: TPeer_IO_User_Special_Class read FPeerIOUserSpecialClass write FPeerIOUserSpecialClass;
    { Misc. }
    property IDCounter: Cardinal read FIDSeed write FIDSeed;
    property IDSeed: Cardinal read FIDSeed write FIDSeed;
    property PrintParams: TPrint_Param_Hash_Pool read FPrintParams;
  end;
{$ENDREGION 'Z-Net'}
{$REGION 'ZNetServer'}

  TOnServerCustomProtocolReceiveBufferNotify = procedure(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean) of object; { Server-side custom protocol receive callback. }
  TZNet_StableServer = class;

  {
    * TZNet_Server: Server-side network framework.
    * Manages incoming connections, handles command execution, and provides
    * broadcast and per-IO send methods. Supports both ZServer protocol and custom protocols.
    * @Field FOnServerCustomProtocolReceiveBufferNotify: Custom protocol receive callback. Set by user.
    * @Field FStableIO: Stable IO server instance. Created on demand.
    * @Example:
    *   var Server: TZNet_Server;
    *   begin
    *     Server := TZNet_Server.Create;
    *     Server.RegisterConsole('hello').OnExecute := procedure(S: TPeerIO; I: string; var O: string)
    *     begin
    *       O := 'Hello, ' + I;
    *     end;
    *     Server.StartService('0.0.0.0', 8080);
    *     while True do
    *     begin
    *       Server.Progress;
    *       Sleep(10);
    *     end;
    *   end;
  }
  TZNet_Server = class(TZNet)
  protected
    function CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; override;
    function CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; override;
    function CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean; override;
    procedure Command_CipherModel(Sender: TPeerIO; InData, OutData: TDFE); virtual;
    procedure Command_Wait(Sender: TPeerIO; InData: SystemString; var OutData: SystemString); virtual;
    procedure Framework_Internal_IO_Create(const Sender: TPeerIO); override;
    procedure Framework_Internal_IO_Destroy(const Sender: TPeerIO); override;
  protected
    FOnServerCustomProtocolReceiveBufferNotify: TOnServerCustomProtocolReceiveBufferNotify; { Custom protocol receive callback. Set by user. }
    procedure FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean); override;
  protected
    FStableIOProgressing: Boolean; { Stable IO progress guard. Set by Progress. }
    FStableIO: TZNet_StableServer; { Stable IO server instance. Created on demand. }
  public
    constructor Create; virtual;
    constructor CreateCustomHashPool(HashPoolSize: Integer); virtual;
    destructor Destroy; override;
    procedure Progress; override;
    function StableIO: TZNet_StableServer;
    procedure Disconnect(ID: Cardinal); overload;
    procedure Disconnect(ID: Cardinal; delay: Double); overload;
    procedure OnReceiveBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean); virtual;
    procedure BeginWriteBuffer(P_IO: TPeerIO);
    procedure EndWriteBuffer(P_IO: TPeerIO);
    procedure WriteBuffer(P_IO: TPeerIO; const Buffer: PByte; const Size: NativeInt); overload; virtual;
    procedure WriteBuffer(P_IO: TPeerIO; const Buffer: TMS64); overload;
    procedure WriteBuffer(P_IO: TPeerIO; const Buffer: TMem64); overload;
    procedure WriteBuffer(P_IO: TPeerIO; const Buffer: TMS64; const doneFreeBuffer: Boolean); overload;
    procedure WriteBuffer(P_IO: TPeerIO; const Buffer: TMem64; const doneFreeBuffer: Boolean); overload;
    procedure StopService; virtual;
    function StartService(Host: SystemString; Port: Word): Boolean; virtual;
    procedure DoIOConnectBefore(Sender: TPeerIO); virtual;
    procedure DoIOConnectAfter(Sender: TPeerIO); virtual;
    procedure DoIODisconnect(Sender: TPeerIO); virtual;
    { Send console commands to a specific IO. }
    procedure SendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M); overload;
    procedure SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M); overload;
    procedure SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M); overload;
    procedure SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P); overload;
    procedure SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P); overload;
    procedure SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P); overload;
    procedure SendConsoleCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M); overload;
    procedure SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M); overload;
    procedure SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M); overload;
    procedure SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P); overload;
    procedure SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P); overload;
    procedure SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P); overload;
    { Send stream commands to a specific IO. }
    procedure SendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M); overload;
    procedure SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M); overload;
    procedure SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M); overload;
    procedure SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P); overload;
    procedure SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P); overload;
    procedure SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P); overload;
    procedure SendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M); overload;
    procedure SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M); overload;
    procedure SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M); overload;
    procedure SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P); overload;
    procedure SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P); overload;
    procedure SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P); overload;
    { Send direct commands. }
    procedure SendConsoleNotifyCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString); overload;
    procedure SendConsoleNotifyCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString); overload;
    procedure SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString); overload;
    procedure SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString); overload;
    { Send big-stream commands. }
    procedure SendBigStream(P_IO: TPeerIO; const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean); overload;
    procedure SendBigStream(P_IO: TPeerIO; const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean); overload;
    procedure SendBigStream(IO_ID: Cardinal; const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean); overload;
    procedure SendBigStream(IO_ID: Cardinal; const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean); overload;
    { Send complete-buffer commands. }
    procedure SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE); overload;
    procedure SendCompleteBuffer_StreamNotify(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE); overload;
    procedure SendCompleteBuffer_NoWait_StreamM(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M); overload;
    procedure SendCompleteBuffer_NoWait_StreamP(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P); overload;
    procedure SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE); overload;
    procedure SendCompleteBuffer_NoWait_StreamM(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M); overload;
    procedure SendCompleteBuffer_NoWait_StreamP(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P); overload;
    procedure SendCompleteBuffer_StreamNotify(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE); overload;
    { Send NULL command (keep-alive). }
    procedure Send_NULL(P_IO: TPeerIO); overload;
    procedure SendNULL(P_IO: TPeerIO); overload;
    { wait send }
    function WaitSendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; overload; virtual;
    procedure WaitSendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); overload; virtual;
    function WaitSendConsoleCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; overload;
    procedure WaitSendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); overload;
    procedure Send_NULL(IO_ID: Cardinal); overload;
    { Broadcast commands to all connected clients. }
    procedure BroadcastConsoleNotifyCmd(const Cmd, ConsoleData: SystemString);
    procedure BroadcastStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE);
    procedure BroadcastCompleteBufferCmd(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt); overload;
    procedure BroadcastCompleteBufferCmd(const Cmd: SystemString; StreamData: TDFE); overload;
    { IO enumeration. }
    function GetCount: Integer;
    property Count: Integer read GetCount;
    function Exists(P_IO: TPeerIO): Boolean; overload;
    function Exists(P_IO: TPeer_IO_User_Define): Boolean; overload;
    function Exists(P_IO: TPeer_IO_User_Special): Boolean; overload;
    function Exists(IO_ID: Cardinal): Boolean; overload;
    function GetPeerIO(ID: Cardinal): TPeerIO;
    property IO[ID: Cardinal]: TPeerIO read GetPeerIO; default;
    property PeerIO[ID: Cardinal]: TPeerIO read GetPeerIO;
  end;

  TZNet_ServerClass = class of TZNet_Server;
{$ENDREGION 'ZNetServer'}
{$REGION 'ZNetClient'}
  TZNet_Client = class;

  IZNet_ClientInterface = interface { Client interface for connection events. }
    procedure ClientConnected(Sender: TZNet_Client);
    procedure ClientDisconnect(Sender: TZNet_Client);
  end;

  TOnClientCustomProtocolReceiveBufferNotify = procedure(Sender: TZNet_Client; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean) of object; { Client-side custom protocol receive callback. }
  TOnCipherModelDone = procedure(Sender: TZNet_Client) of object; { Cipher model done callback. }
  TZNet_StableClient = class;

  PZNet_ServerState = ^TZNet_ServerState; { Server state snapshot (copied from the server during handshake). }

  {
    * TZNet_ServerState: Server state snapshot.
    * Copied from the server during handshake to synchronize client configuration.
    * @Field UsedParallelEncrypt: Whether parallel encryption is used.
    * @Field SyncOnResult: Whether results are synchronous.
    * @Field SyncOnCompleteBuffer: Whether complete buffers are synchronous.
    * @Field EnabledAtomicLockAndMultiThread: Whether atomic locking is enabled.
    * @Field TimeOutKeepAlive: Whether keep-alive is enabled.
    * @Field QuietMode: Quiet mode flag.
    * @Field IdleTimeOut: Idle timeout value.
    * @Field SendDataCompressed: Whether send data is compressed.
    * @Field CompleteBufferCompressed: Whether complete buffers are compressed.
    * @Field MaxCompleteBufferSize: Maximum complete buffer size.
    * @Field ProgressMaxDelay: Maximum progress delay.
  }
  TZNet_ServerState = record
    UsedParallelEncrypt, SyncOnResult, SyncOnCompleteBuffer, EnabledAtomicLockAndMultiThread, TimeOutKeepAlive, QuietMode: Boolean;
    IdleTimeOut: TTimeTick;
    SendDataCompressed, CompleteBufferCompressed: Boolean;
    MaxCompleteBufferSize: Cardinal;
    ProgressMaxDelay: TTimeTick;
    procedure Reset;
  end;

  {
    * TZNet_Client: Client-side network framework.
    * Manages a single connection to a server. Supports synchronous and
    * asynchronous connection, command sending, and receives callbacks for
    * connection events. Also provides P2PVM client functionality.
    * @Field FOnInterface: Client event interface. Set by user.
    * @Field FConnectInitWaiting: Whether waiting for connection initialisation.
    * @Field FAsyncConnectTimeout: Async connect timeout. Set by user.
    * @Field FOnCipherModelDone: Cipher model done callback. Set by user.
    * @Field FServerState: Server state snapshot. Set by Do_CipherModel_Result.
    * @Field FIgnoreProcessConnectedAndDisconnect: Whether to ignore connect/disconnect events.
    * @Field FLastConnectIsSuccessed: Last connect success flag.
    * @Field FStableIO: Stable IO client instance. Created on demand.
    * @Example:
    *   var Client: TZNet_Client;
    *   begin
    *     Client := TZNet_Client.Create;
    *     Client.Connect('127.0.0.1', 8080);
    *     Client.SendConsoleCmd('hello', 'world');
    *     while Client.Connected do
    *     begin
    *       Client.Progress;
    *       Sleep(10);
    *     end;
    *   end;
  }
  TZNet_Client = class(TZNet)
  protected
    FOnInterface: IZNet_ClientInterface; { Client event interface. Set by user. }
    FConnectInitWaiting: Boolean; { Whether waiting for connection initialisation. Set by DoConnected. }
    FConnectInitWaitingTimeout: TTimeTick; { Timeout for connection init. Set by DoConnected. }
    FAsyncConnectTimeout: TTimeTick; { Async connect timeout. Set by user. }
    FOnCipherModelDone: TOnCipherModelDone; { Cipher model done callback. Set by user. }
    FServerState: TZNet_ServerState; { Server state snapshot. Set by Do_CipherModel_Result. }
    FIgnoreProcessConnectedAndDisconnect: Boolean; { Whether to ignore connect/disconnect events. Set by user. }
    FLastConnectIsSuccessed: Boolean; { Last connect success flag. Set by DoConnected. }
    FRequestTime: TTimeTick; { Request timestamp. Set by DoConnected. }
    FReponseTime: TTimeTick; { Response timestamp. Set by Do_CipherModel_Result. }
    procedure Do_CipherModel_Result(Sender: TPeerIO; Result_: TDFE);
    procedure DoConnected(Sender: TPeerIO); virtual;
    procedure DoDisconnect(Sender: TPeerIO); virtual;
    function CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; override;
    function CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean; override;
    function CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean; override;
  protected
    FOnClientCustomProtocolReceiveBufferNotify: TOnClientCustomProtocolReceiveBufferNotify; { Custom protocol callback. Set by user. }
    procedure FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean); override;
  protected
    FStableIOProgressing: Boolean; { Stable IO progress guard. Set by Progress. }
    FStableIO: TZNet_StableClient; { Stable IO client instance. Created on demand. }
  private
    FWaiting: Boolean; { Waiting for response flag. Set by WaitC/M/P. }
    FWaitingTimeOut: TTimeTick; { Waiting timeout. Set by WaitC/M/P. }
    FOnWaitResult_C: TOnState_C; { Wait result callback (C). Set by WaitC. }
    FOnWaitResult_M: TOnState_M; { Wait result callback (method). Set by WaitM. }
    FOnWaitResult_P: TOnState_P; { Wait result callback (nested). Set by WaitP. }
    procedure ConsoleResult_Wait(Sender: TPeerIO; Result_: SystemString);
    function GetWaitTimeout(const t: TTimeTick): TTimeTick;
  private
    procedure Do_IO_IDLE_FreeSelf(Data_: TCore_Object);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure DelayFreeSelf;
    { P2PVM tunnel access. }
    function GetP2PVMTunnel: TZNet_P2PVM;
    property P2PVM: TZNet_P2PVM read GetP2PVMTunnel;
    property P2PVMTunnel: TZNet_P2PVM read GetP2PVMTunnel;
    { IO IDLE trace. }
    procedure IO_IDLE_TraceC(data: TCore_Object; const OnNotify: TOnDataNotify_C);
    procedure IO_IDLE_TraceM(data: TCore_Object; const OnNotify: TOnDataNotify_M);
    procedure IO_IDLE_TraceP(data: TCore_Object; const OnNotify: TOnDataNotify_P);
    procedure IO_IDLE_Trace_And_FreeSelf(Additional_Object_: TCore_Object);
    { Custom protocol receive. }
    procedure OnReceiveBuffer(const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean); virtual;
    procedure BeginWriteBuffer();
    procedure EndWriteBuffer();
    procedure WriteBuffer(const Buffer: PByte; const Size: NativeInt); overload; virtual;
    procedure WriteBuffer(const Buffer: TMS64); overload;
    procedure WriteBuffer(const Buffer: TMem64); overload;
    procedure WriteBuffer(const Buffer: TMS64; const doneFreeBuffer: Boolean); overload;
    procedure WriteBuffer(const Buffer: TMem64; const doneFreeBuffer: Boolean); overload;
    { Server state. }
    function ServerState: PZNet_ServerState;
    { Network delay. }
    property ReponseTime: TTimeTick read FReponseTime;
    { Main progress. }
    procedure Progress; override;
    function StableIO: TZNet_StableClient;
    procedure TriggerDoDisconnect;
    { Connection state. }
    function Connected: Boolean; virtual;
    property LastConnectIsSuccessed: Boolean read FLastConnectIsSuccessed;
    function ClientIO: TPeerIO; virtual;
    procedure TriggerDoConnectFailed; virtual;
    procedure TriggerDoConnectFinished; virtual;
    procedure CipherModelDone; virtual;
    property OnCipherModelDone: TOnCipherModelDone read FOnCipherModelDone write FOnCipherModelDone;
    { Asynchronous connection. }
    property AsyncConnectTimeout: TTimeTick read FAsyncConnectTimeout write FAsyncConnectTimeout;
    procedure AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C); overload; virtual;
    procedure AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M); overload; virtual;
    procedure AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P); overload; virtual;
    procedure AsyncConnectC(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_C); overload;
    procedure AsyncConnectM(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_M); overload;
    procedure AsyncConnectP(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_P); overload;
    { Synchronous connection. }
    function Connect(addr: SystemString; Port: Word): Boolean; virtual;
    { Disconnect. }
    procedure Disconnect; virtual;
    procedure DelayCloseIO; overload;
    procedure DelayCloseIO(const t: Double); overload;
    { Wait for a response (synchronous). }
    function Wait(TimeOut_: TTimeTick): SystemString; overload;
    { Wait for a response (asynchronous). }
    function WaitC(TimeOut_: TTimeTick; const OnResult: TOnState_C): Boolean;
    function WaitM(TimeOut_: TTimeTick; const OnResult: TOnState_M): Boolean;
    function WaitP(TimeOut_: TTimeTick; const OnResult: TOnState_P): Boolean;
    { IO state. }
    function WaitSendBusy: Boolean;
    function LastQueueData: PQueueData;
    function LastQueueCmd: SystemString;
    function QueueCmdCount: Integer;
    function Last_IO_IDLE_Time: TTimeTick;
    function Client_ID: Cardinal;
    { Send console commands. }
    procedure SendConsoleCmd(const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M); overload;
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M); overload;
    procedure SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M); overload;
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P); overload;
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P); overload;
    procedure SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P); overload;
    { Send stream commands. }
    procedure SendStreamCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmd(const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M); overload;
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M); overload;
    procedure SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M); overload;
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean); overload;
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P); overload;
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P); overload;
    procedure SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P); overload;
    { Send direct commands. }
    procedure SendConsoleNotifyCmd(const Cmd, ConsoleData: SystemString); overload;
    procedure SendConsoleNotifyCmd(const Cmd: SystemString); overload;
    procedure SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE); overload;
    procedure SendStreamNotifyCmd(const Cmd: SystemString); overload;
    { Send big-stream commands. }
    procedure SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean); overload;
    procedure SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean); overload;
    { Send complete-buffer commands. }
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean); overload;
    procedure SendCompleteBuffer(const Cmd: SystemString; buff: TDFE); overload;
    procedure SendCompleteBuffer_StreamNotify(const Cmd: SystemString; buff: TDFE);
    procedure SendCompleteBuffer_NoWait_StreamM(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);
    procedure SendCompleteBuffer_NoWait_StreamP(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);
    { Send NULL (keep-alive). }
    procedure Send_NULL();
    procedure SendNULL();
    { Wait send (synchronous with timeout). }
    function WaitSendConsoleCmd(const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; virtual;
    procedure WaitSendStreamCmd(const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); virtual;
    { Client interface. }
    property OnInterface: IZNet_ClientInterface read FOnInterface write FOnInterface;
    property NotyifyInterface: IZNet_ClientInterface read FOnInterface write FOnInterface;
    property OnNotyifyInterface: IZNet_ClientInterface read FOnInterface write FOnInterface;
    { Remote server info. }
    function RemoteID: Cardinal;
    function RemoteKey: TCipherKeyBuffer;
    function RemoteInited: Boolean;
  end;

  TZNet_ClientClass = class of TZNet_Client;
{$ENDREGION 'ZNetClient'}
{$REGION 'P2pVM_IO'}
  PP2PVMFragmentPacket = ^TP2PVMFragmentPacket; { P2PVM fragment packet structure. }

  {
    * TP2PVMFragmentPacket: P2PVM fragment packet structure.
    * Used for sending data fragments over the P2PVM tunnel.
    * @Field BuffSiz: Payload size. Set by Build_P2PVM_Packet.
    * @Field FrameworkID: Target framework ID. Set by Build_P2PVM_Packet.
    * @Field p2pID: Target IO ID. Set by Build_P2PVM_Packet.
    * @Field pkType: Packet type. Set by Build_P2PVM_Packet.
    * @Field buff: Payload buffer. Set by Build_P2PVM_Packet.
  }
  TP2PVMFragmentPacket = record
    BuffSiz: Cardinal;
    FrameworkID: Cardinal;
    p2pID: Cardinal;
    pkType: Byte;
    buff: PByte;
    procedure Init;
    procedure Build_P2PVM_Send_Buffer(Stream: TMem64);
  end;

  TP2P_VM_Fragment_Packet_Pool = class(TOrderStruct<PP2PVMFragmentPacket>); { FIFO pool for P2PVM fragment packets. }

  {
    * TP2PVM_PeerIO: Virtual IO over a P2PVM tunnel.
    * This IO represents a remote peer connected via the P2PVM overlay.
    * It forwards writes to the P2PVM tunnel and receives data from it.
    * @Field FLinkVM: Parent P2PVM tunnel. Set by creator.
    * @Field FRealSendBuff: Send buffer. Created by constructor.
    * @Field FSendQueue: Fragment queue. Created by constructor.
    * @Field FRemote_frameworkID: Remote framework ID. Set by VMConnectSuccessed/Connecting.
    * @Field FRemote_p2pID: Remote IO ID. Set by VMConnectSuccessed/Connecting.
    * @Field FIP: Remote IPv6 address. Set by creator.
    * @Field FPort: Remote port. Set by creator.
    * @Field FDestroySyncRemote: Whether to sync remote disconnect. Set by creator.
  }
  TP2PVM_PeerIO = class(TPeerIO)
  private
    FLinkVM: TZNet_P2PVM; { Parent P2PVM tunnel. Set by creator. }
    FRealSendBuff: TMem64; { Send buffer. Created by constructor. }
    FSendQueue: TP2P_VM_Fragment_Packet_Pool; { Fragment queue. Created by constructor. }
    FRemote_frameworkID: Cardinal; { Remote framework ID. Set by VMConnectSuccessed/Connecting. }
    FRemote_p2pID: Cardinal; { Remote IO ID. Set by VMConnectSuccessed/Connecting. }
    FIP: TIPV6; { Remote IPv6 address. Set by creator. }
    FPort: Word; { Remote port. Set by creator. }
    FDestroySyncRemote: Boolean; { Whether to sync remote disconnect. Set by creator. }
  public
    procedure CreateAfter; override;
    destructor Destroy; override;
    function Connected: Boolean; override;
    procedure Disconnect; override;
    procedure Write_IO_Buffer(const buff: PByte; const Size: NativeInt); override;
    procedure WriteBufferOpen; override;
    procedure WriteBufferFlush; override;
    procedure WriteBufferClose; override;
    function GetPeerIP: SystemString; override;
    function WriteBuffer_is_NULL: Boolean; override;
    function WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean; override;
    procedure Progress; override;
    property LinkVM: TZNet_P2PVM read FLinkVM;
    property Remote_frameworkID: Cardinal read FRemote_frameworkID;
    property Remote_p2pID: Cardinal read FRemote_p2pID;
  end;
{$ENDREGION 'P2pVM_IO'}
{$REGION 'P2pVM_Server'}

  {
    * TP2PVMListen: P2PVM listen record.
    * @Field FrameworkID: Framework that owns this listen. Set by StartService.
    * @Field ListenHost: IPv6 address being listened on. Set by StartService.
    * @Field ListenPort: Port being listened on. Set by StartService.
    * @Field Listening: Whether listen is active. Set by StartService/StopService.
  }
  TP2PVMListen = record
    FrameworkID: Cardinal;
    ListenHost: TIPV6;
    ListenPort: Word;
    Listening: Boolean;
  end;

  PP2PVMListen = ^TP2PVMListen;

  TP2PVM_Listen_List = class(TGenericsList<PP2PVMListen>)

    {
      * TZNet_WithP2PVM_Server: Server that can be exposed over P2PVM.
      * When installed into a P2PVM tunnel, this server becomes reachable
      * from remote peers through the virtual network.
      * @Field FFrameworkListenPool: Listen records. Created by constructor.
      * @Field FLinkVMPool: Linked P2PVM instances. Created by constructor.
      * @Field FFrameworkWithVM_ID: Framework ID in P2PVM. Set by user or auto-assigned.
      * @Example:
      *   var Server: TZNet_WithP2PVM_Server;
      *   begin
      *     Server := TZNet_WithP2PVM_Server.Create;
      *     Server.StartService('::1', 12345);  // Listen on P2PVM
      *     // Install the server into a P2PVM tunnel:
      *     P2PVM.InstallLogicFramework(Server);
      *   end;
    }
  end;

  TZNet_WithP2PVM_Server = class(TZNet_Server)
  protected
    procedure Connecting(SenderVM: TZNet_P2PVM;
      const Remote_frameworkID, FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; var Allowed: Boolean); virtual;
    procedure ListenState(SenderVM: TZNet_P2PVM; const IPV6: TIPV6; const Port: Word; const State: Boolean); virtual;
  protected
    FFrameworkListenPool: TCore_List; { Listen records. Created by constructor. }
    FLinkVMPool: TUInt32HashObjectList; { Linked P2PVM instances. Created by constructor. }
    FFrameworkWithVM_ID: Cardinal; { Framework ID in P2PVM. Set by user or auto-assigned. }
    procedure ProgressDisconnectClient(P_IO: TPeerIO);
    function ListenCount: Integer;
    function GetListen(const index: Integer): PP2PVMListen;
    function FindListen(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
    function FindListening(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
    procedure DeleteListen(const IPV6: TIPV6; const Port: Word);
    procedure ClearListen;
  public
    constructor Create; override;
    constructor CustomCreate(HashPoolSize: Integer; FrameworkID: Cardinal);
    destructor Destroy; override;
    procedure Progress; override;
    procedure CloseAllClient;
    procedure ProgressStopServiceWithPerVM(SenderVM: TZNet_P2PVM);
    procedure StopService; override;
    function StartService(Host_: SystemString; Port: Word): Boolean; override;
    function WaitSendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override;
    procedure WaitSendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); override;
  end;
{$ENDREGION 'P2pVM_Server'}
{$REGION 'P2pVM_Client'}

  TZNet_WithP2PVM_Client_Clone_Pool = class(TBigList<TZNet_WithP2PVM_Client>) { Pool of P2PVM client clones. }

    {
      * TZNet_WithP2PVM_Client: Client that connects over P2PVM.
      * This client establishes a connection through a P2PVM tunnel to a remote
      * server exposed via P2PVM. It can also create clones (additional virtual
      * connections) over the same tunnel.
      * @Field FLinkVM: Parent P2PVM tunnel. Set by InstallLogicFramework.
      * @Field FFrameworkWithVM_ID: Framework ID in P2PVM. Set by user or auto-assigned.
      * @Field FVMClientIO: Virtual IO for this client. Created by Connect/AsyncConnect.
      * @Field FVMConnected: Whether the virtual connection is established.
      * @Field FP2PVM_ClonePool: Pool of clone clients. Created by constructor.
      * @Field FP2PVM_CloneOwner: Owner of this clone (if this is a clone).
      * @Example:
      *   var Client: TZNet_WithP2PVM_Client;
      *   begin
      *     Client := TZNet_WithP2PVM_Client.Create;
      *     // Install the client into a P2PVM tunnel:
      *     P2PVM.InstallLogicFramework(Client);
      *     Client.AsyncConnect('::1', 12345, MyHandler);
      *     // Create a clone:
      *     Client.CloneConnectM(MyCloneHandler);
      *   end;
    }
  end;

  TZNet_WithP2PVM_Client = class(TZNet_Client)
  protected
    procedure Framework_Internal_IO_Create(const Sender: TPeerIO); override;
    procedure Framework_Internal_IO_Destroy(const Sender: TPeerIO); override;
    procedure VMConnectSuccessed(SenderVM: TZNet_P2PVM; Remote_frameworkID, Remote_p2pID, FrameworkID: Cardinal); virtual;
    procedure VMDisconnect(SenderVM: TZNet_P2PVM); virtual;
  protected
    FLinkVM: TZNet_P2PVM; { Parent P2PVM tunnel. Set by InstallLogicFramework. }
    FFrameworkWithVM_ID: Cardinal; { Framework ID in P2PVM. Set by user or auto-assigned. }
    FVMClientIO: TP2PVM_PeerIO; { Virtual IO for this client. Created by Connect/AsyncConnect. }
    FVMConnected: Boolean; { Whether the virtual connection is established. Set by VMConnectSuccessed. }
    FP2PVM_ClonePool: TZNet_WithP2PVM_Client_Clone_Pool; { Pool of clone clients. Created by constructor. }
    FP2PVM_ClonePool_Ptr: TZNet_WithP2PVM_Client_Clone_Pool.PQueueStruct; { Pointer in clone pool (if this is a clone). Set by CloneConnect. }
    FP2PVM_CloneOwner: TZNet_WithP2PVM_Client; { Owner of this clone (if this is a clone). Set by CloneConnect. }
    FP2PVM_Clone_NextProgressDoFreeSelf: Boolean; { Whether to free self on next progress. Set by user. }
    FP2PVM_ProgressWaitSend_Busy: Boolean; { Progress-wait re-entry guard. Set by ProgressWaitSend. }
  private
    FOnP2PVMAsyncConnectNotify_C: TOnState_C; { Async connect result (C). Set by AsyncConnectC. }
    FOnP2PVMAsyncConnectNotify_M: TOnState_M; { Async connect result (method). Set by AsyncConnectM. }
    FOnP2PVMAsyncConnectNotify_P: TOnState_P; { Async connect result (nested). Set by AsyncConnectP. }
  public
    constructor Create; overload; override;
    constructor CustomCreate(FrameworkID: Cardinal); overload;
    destructor Destroy; override;
    property ClonePool: TZNet_WithP2PVM_Client_Clone_Pool read FP2PVM_ClonePool;
    function CloneConnectC(OnResult: TOnP2PVM_CloneConnectEvent_C): TP2PVM_CloneConnectEventBridge;
    function CloneConnectM(OnResult: TOnP2PVM_CloneConnectEvent_M): TP2PVM_CloneConnectEventBridge;
    function CloneConnectP(OnResult: TOnP2PVM_CloneConnectEvent_P): TP2PVM_CloneConnectEventBridge;
    property P2PVM_Clone_NextProgressDoFreeSelf: Boolean read FP2PVM_Clone_NextProgressDoFreeSelf write FP2PVM_Clone_NextProgressDoFreeSelf;
    procedure TriggerDoConnectFailed; override;
    procedure TriggerDoConnectFinished; override;
    function Connected: Boolean; override;
    function ClientIO: TPeerIO; override;
    procedure Progress; override;
    procedure AsyncConnect(addr: SystemString; Port: Word);
    procedure AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C); override;
    procedure AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M); override;
    procedure AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P); override;
    function Connect(addr: SystemString; Port: Word): Boolean; override;
    procedure AsyncConnectC(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_C); overload;
    procedure AsyncConnectM(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_M); overload;
    procedure AsyncConnectP(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_P); overload;
    procedure Disconnect; override;
    procedure DoBackCall_Progress(Sender: TZNet);
    procedure ProgressWaitSend(P_IO: TPeerIO); override;
    property LinkVM: TZNet_P2PVM read FLinkVM;
    property FrameworkWithVM_ID: Cardinal read FFrameworkWithVM_ID;
    property VMClientIO: TP2PVM_PeerIO read FVMClientIO;
  end;
{$ENDREGION 'P2pVM_Client'}
{$REGION 'P2pVM'}

  TZNet_List_C = procedure(Sender: TZNet); { Callback types for iterating over ZNet instances in a P2PVM. }
  TZNet_List_M = procedure(Sender: TZNet) of object;
{$IFDEF FPC}
  TZNet_List_P = procedure(Sender: TZNet) is nested;
{$ELSE FPC}
  TZNet_List_P = reference to procedure(Sender: TZNet);
{$ENDIF FPC}
  TP2PVMAuthSuccessMethod = procedure(Sender: TZNet_P2PVM) of object; { Method for P2PVM auth success. }

  {
    * TZNet_P2PVM: Peer-to-Peer Virtual Machine overlay network.
    * This class establishes a virtual network over an existing TPeerIO connection.
    * It provides:
    * - Authentication (handshake with auth token)
    * - Virtual listening and connecting (NAT-traversal)
    * - Fragmented and encrypted data transfer
    * - Echo/keep-alive for latency and liveness
    * - Management of virtual framework instances
    * The P2PVM can host multiple logical ZNet frameworks (both server and client)
    * over a single physical connection.
    * @Field FOwner_IO: Underlying physical IO. Set by OpenP2PVMTunnel.
    * @Field FAuthWaiting: Whether authentication is waiting. Set by AuthWaiting.
    * @Field FAuthed: Whether authentication succeeded. Set by Hook_ProcessReceiveBuffer.
    * @Field FAuthSending: Whether authentication token is being sent. Set by AuthVM.
    * @Field FFrameworkPool: Installed frameworks. Created by constructor.
    * @Field FFrameworkListenPool: Listen records. Created by constructor.
    * @Field FMaxVMFragmentSize: Max fragment size. Set by user.
    * @Field FProgress_Send_Size: Max bytes to send per progress. Set by user.
    * @Field FQuietMode: Quiet mode. Set by user.
    * @Field FReceiveStream: Receive buffer. Created by constructor.
    * @Field FSendStream: Send buffer. Created by constructor.
    * @Field FWaitEchoList: Outstanding echo requests. Created by constructor.
    * @Field FVMID: Virtual machine ID. Set by OpenP2PVMTunnel.
    * @Field OnAuthSuccessOnesNotify: One-time auth success callback. Set by caller.
    * @Example:
    *   var VM: TZNet_P2PVM;
    *   begin
    *     VM := TZNet_P2PVM.Create(16384);
    *     VM.OpenP2PVMTunnel(MyIO);  // Establish tunnel over existing connection
    *     VM.AuthWaiting;            // Wait for auth
    *     VM.AuthVM;                 // Authenticate
    *     // Install frameworks into the VM
    *     VM.InstallLogicFramework(MyServer);
    *     VM.InstallLogicFramework(MyClient);
    *     while Running do
    *       VM.Progress;  // Drive the virtual network
    *   end;
  }
  TZNet_P2PVM = class(TCore_Object_Intermediate)
  protected
    FOwner_IO: TPeerIO; { Underlying physical IO. Set by OpenP2PVMTunnel. }
    FAuthWaiting: Boolean; { Whether authentication is waiting. Set by AuthWaiting. }
    FAuthed: Boolean; { Whether authentication succeeded. Set by Hook_ProcessReceiveBuffer. }
    FAuthSending: Boolean; { Whether authentication token is being sent. Set by AuthVM. }
    FFrameworkPool: TUInt32HashObjectList; { Installed frameworks. Created by constructor. }
    FFrameworkListenPool: TP2PVM_Listen_List; { Listen records. Created by constructor. }
    FMaxVMFragmentSize: Cardinal; { Max fragment size. Set by user. }
    FProgress_Send_Size: Int64; { Max bytes to send per progress. Set by user. }
    FQuietMode: Boolean; { Quiet mode. Set by user. }
    FReceiveStream: TMem64; { Receive buffer. Created by constructor. }
    FSendStream: TMem64; { Send buffer. Created by constructor. }
    FWaitEchoList: TP2PVM_ECHO_List; { Outstanding echo requests. Created by constructor. }
    FVMID: Cardinal; { Virtual machine ID. Set by OpenP2PVMTunnel. }
    OnAuthSuccessOnesNotify: TP2PVMAuthSuccessMethod; { One-time auth success callback. Set by caller. }
  protected
    procedure Hook_SendByteBuffer(const Sender: TPeerIO; const buff: PByte; siz: NativeInt);
    procedure Hook_SaveReceiveBuffer(const Sender: TPeerIO; const buff: Pointer; siz: Int64);
    procedure Hook_ProcessReceiveBuffer(const Sender: TPeerIO);
    procedure Hook_ClientDestroy(const Sender: TPeerIO);
    procedure SendVMBuffer(const buff: Pointer; const siz: NativeInt);
    procedure ReceivedEchoing(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedEcho(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedListen(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedListenState(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedConnecting(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedConnectedReponse(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedDisconnect(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedLogicFragmentData(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure ReceivedOwnerIOFragmentData(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
    procedure DoProcessPerClientFragmentSend(P_IO: TPeerIO);
    procedure DoPerClientClose(P_IO: TPeerIO);
  public
    constructor Create(HashPoolSize: Integer);
    destructor Destroy; override;
    function Build_P2PVM_Packet(BuffSiz, FrameworkID, p2pID: Cardinal; pkType: Byte; buff: PByte): PP2PVMFragmentPacket;
    class procedure FreeP2PVMPacket(p: PP2PVMFragmentPacket);
    property Owner_IO: TPeerIO read FOwner_IO;
    procedure Progress;
    procedure ProgressZNet_C(const OnBackcall: TZNet_List_C);
    procedure ProgressZNet_M(const OnBackcall: TZNet_List_M);
    procedure ProgressZNet_P(const OnBackcall: TZNet_List_P);
    procedure OpenP2PVMTunnel(c: TPeerIO);
    procedure CloseP2PVMTunnel;
    property FrameworkPool: TUInt32HashObjectList read FFrameworkPool;
    procedure InstallLogicFramework(Inst: TZNet);
    procedure UninstallLogicFramework(Inst: TZNet);
    property MaxVMFragmentSize: Cardinal read FMaxVMFragmentSize write FMaxVMFragmentSize;
    property Progress_Send_Size: Int64 read FProgress_Send_Size write FProgress_Send_Size;
    property QuietMode: Boolean read FQuietMode write FQuietMode;
    procedure AuthWaiting;
    procedure AuthVM; overload;
    property WasAuthed: Boolean read FAuthed;
    procedure AuthSuccessed;
    procedure echoing(const OnEchoPtr: PP2PVM_ECHO; TimeOut_: TTimeTick);
    procedure echoingC(const OnResult: TOnState_C; TimeOut_: TTimeTick);
    procedure echoingM(const OnResult: TOnState_M; TimeOut_: TTimeTick);
    procedure echoingP(const OnResult: TOnState_P; TimeOut_: TTimeTick);
    procedure echoBuffer(const buff: Pointer; const siz: NativeInt);
    procedure SendListen(const FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; const Listening: Boolean);
    procedure SendListenState(const FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; const Listening: Boolean);
    procedure SendConnecting(const Remote_frameworkID, FrameworkID, p2pID: Cardinal; const IPV6: TIPV6; const Port: Word);
    procedure SendConnectedReponse(const Remote_frameworkID, Remote_p2pID, FrameworkID, p2pID: Cardinal);
    procedure SendDisconnect(const Remote_frameworkID, Remote_p2pID: Cardinal);
    function ListenCount: Integer;
    function GetListen(const index: Integer): PP2PVMListen;
    function FindListen(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
    function FindListening(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
    procedure DeleteListen(const IPV6: TIPV6; const Port: Word);
    procedure ClearListen;
  end;
{$ENDREGION 'P2pVM'}
{$REGION 'StableIO'}

  TStableServer_PeerIO = class; { User define for stable server owner IO. }

  {
    * TStableServer_OwnerIO_UserDefine: User define for stable server owner IO.
    * Holds a reference to the stable IO associated with this physical connection.
    * @Field BindStableIO: Associated stable IO. Set by cmd_BuildStableIO/cmd_OpenStableIO.
  }
  TStableServer_OwnerIO_UserDefine = class(TPeer_IO_User_Define)
  public
    BindStableIO: TStableServer_PeerIO; { Associated stable IO. Set by cmd_BuildStableIO/cmd_OpenStableIO. }
    constructor Create(Owner_: TPeerIO); override;
    destructor Destroy; override;
  end;

  {
    * TStableServer_PeerIO: Stable IO for server side.
    * This is a virtual peer that can survive reconnections of the underlying
    * physical IO. It maintains its state and buffer even if the physical
    * connection is lost and re-established.
    * @Field Activted: Whether stable IO is active. Set by cmd_BuildStableIO.
    * @Field DestroyRecycleOwnerIO: Whether to recycle owner IO on destroy. Set by user.
    * @Field Connection_Token: Unique connection token. Set by cmd_BuildStableIO.
    * @Field Internal_Bind_Owner_IO: Underlying physical IO. Set by cmd_BuildStableIO/cmd_OpenStableIO.
    * @Field OfflineTick: Offline timestamp. Updated by Progress.
    * @Example:
    *   // StableIO is managed automatically by TZNet_CustomStableServer.
    *   // Clients can reconnect and resume their session.
  }
  TStableServer_PeerIO = class(TPeerIO)
  public
    Activted: Boolean; { Whether stable IO is active. Set by cmd_BuildStableIO. }
    DestroyRecycleOwnerIO: Boolean; { Whether to recycle owner IO on destroy. Set by user. }
    Connection_Token: Cardinal; { Unique connection token. Set by cmd_BuildStableIO. }
    Internal_Bind_Owner_IO: TPeerIO; { Underlying physical IO. Set by cmd_BuildStableIO/cmd_OpenStableIO. }
    OfflineTick: TTimeTick; { Offline timestamp. Updated by Progress. }
    property BindOwnerIO: TPeerIO read Internal_Bind_Owner_IO write Internal_Bind_Owner_IO;
    procedure CreateAfter; override;
    destructor Destroy; override;
    function Connected: Boolean; override;
    procedure Disconnect; override;
    procedure Write_IO_Buffer(const buff: PByte; const Size: NativeInt); override;
    procedure WriteBufferOpen; override;
    procedure WriteBufferFlush; override;
    procedure WriteBufferClose; override;
    function GetPeerIP: SystemString; override;
    function WriteBuffer_is_NULL: Boolean; override;
    function WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean; override;
    procedure Progress; override;
  end;

  {
    * TZNet_CustomStableServer: Server that provides stable IO sessions.
    * Stable IO allows clients to reconnect and resume their sessions without
    * losing state. This is useful for long-lived connections that may
    * experience temporary network interruptions.
    * @Field Connection_Token_Counter: Token generator counter. Incremented by cmd_BuildStableIO.
    * @Field FOwnerIOServer: Underlying physics server. Set by SetOwnerIOServer.
    * @Field FOfflineTimeout: Offline timeout. Set by user.
    * @Field FLimitSequencePacketMemoryUsage: Memory limit for sequence packets. Set by user.
    * @Field FAutoFreeOwnerIOServer: Whether to auto-free owner server. Set by user.
    * @Field FAutoProgressOwnerIOServer: Whether to auto-progress owner server. Set by user.
    * @Example:
    *   var Server: TZNet_CustomStableServer;
    *   begin
    *     Server := TZNet_CustomStableServer.Create;
    *     Server.OwnerIOServer := MyPhysicsServer;  // Wraps a physical server
    *     Server.StartService('0.0.0.0', 8080);
    *     // Clients can now reconnect and resume their sessions.
    *   end;
  }
  TZNet_CustomStableServer = class(TZNet_Server)
  protected
    Connection_Token_Counter: Cardinal; { Token generator counter. Incremented by cmd_BuildStableIO. }
    FOwnerIOServer: TZNet_Server; { Underlying physics server. Set by SetOwnerIOServer. }
    FOfflineTimeout: TTimeTick; { Offline timeout. Set by user. }
    FLimitSequencePacketMemoryUsage: Int64; { Memory limit for sequence packets. Set by user. }
    FAutoFreeOwnerIOServer: Boolean; { Whether to auto-free owner server. Set by user. }
    FAutoProgressOwnerIOServer: Boolean; { Whether to auto-progress owner server. Set by user. }
    CustomStableServerProgressing: Boolean; { Progress re-entry guard. Set by Progress. }
    procedure ServerCustomProtocolReceiveBufferNotify(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
    procedure SetOwnerIOServer(const Value: TZNet_Server);
    procedure cmd_BuildStableIO(Sender: TPeerIO; InData, OutData: TDFE);
    procedure cmd_OpenStableIO(Sender: TPeerIO; InData, OutData: TDFE);
    procedure cmd_CloseStableIO(Sender: TPeerIO; InData: SystemString);
  public
    constructor Create; override;
    destructor Destroy; override;
    property OwnerIOServer: TZNet_Server read FOwnerIOServer write SetOwnerIOServer;
    property OfflineTimeout: TTimeTick read FOfflineTimeout write FOfflineTimeout;
    property LimitSequencePacketMemoryUsage: Int64 read FLimitSequencePacketMemoryUsage write FLimitSequencePacketMemoryUsage;
    property AutoFreeOwnerIOServer: Boolean read FAutoFreeOwnerIOServer write FAutoFreeOwnerIOServer;
    property AutoProgressOwnerIOServer: Boolean read FAutoProgressOwnerIOServer write FAutoProgressOwnerIOServer;
    function StartService(Host: SystemString; Port: Word): Boolean; override;
    procedure StopService; override;
    procedure Progress; override;
    function WaitSendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString; override;
    procedure WaitSendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick); override;
  end;

  TZNet_StableServer = class(TZNet_CustomStableServer);

  {
    * TStableClient_PeerIO: Stable IO for client side.
    * Maintains session state across reconnections.
    * @Field Activted: Whether stable IO is active. Set by BuildStableIO_Result/OpenStableIO_Result.
    * @Field WaitConnecting: Whether waiting for connection. Set by PostConnection/PostReconnection.
    * @Field OwnerIO_LastConnectTick: Last connect attempt timestamp. Set by PostReconnection.
    * @Field Connection_Token: Unique connection token. Set by BuildStableIO_Result/OpenStableIO_Result.
    * @Field BindOwnerIO: Underlying physical IO. Set by BuildStableIO_Result/OpenStableIO_Result.
  }
  TStableClient_PeerIO = class(TPeerIO)
  public
    Activted: Boolean; { Whether stable IO is active. Set by BuildStableIO_Result/OpenStableIO_Result. }
    WaitConnecting: Boolean; { Whether waiting for connection. Set by PostConnection/PostReconnection. }
    OwnerIO_LastConnectTick: TTimeTick; { Last connect attempt timestamp. Set by PostReconnection. }
    Connection_Token: Cardinal; { Unique connection token. Set by BuildStableIO_Result/OpenStableIO_Result. }
    BindOwnerIO: TPeerIO; { Underlying physical IO. Set by BuildStableIO_Result/OpenStableIO_Result. }
    procedure CreateAfter; override;
    destructor Destroy; override;
    function Connected: Boolean; override;
    procedure Disconnect; override;
    procedure Write_IO_Buffer(const buff: PByte; const Size: NativeInt); override;
    procedure WriteBufferOpen; override;
    procedure WriteBufferFlush; override;
    procedure WriteBufferClose; override;
    function GetPeerIP: SystemString; override;
    function WriteBuffer_is_NULL: Boolean; override;
    function WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean; override;
    procedure Progress; override;
  end;

  {
    * TZNet_CustomStableClient: Client that provides stable IO sessions.
    * Automatically reconnects when the physical connection is lost and
    * re-establishes the stable session with the same state.
    * @Field FOwnerIOClient: Underlying physics client. Set by SetOwnerIOClient.
    * @Field FStableClientIO: Stable IO instance. Created by constructor.
    * @Field FConnection_Addr: Connection address. Set by Connect/AsyncConnect.
    * @Field FConnection_Port: Connection port. Set by Connect/AsyncConnect.
    * @Field FAutomatedConnection: Whether automated reconnection is enabled. Set by user.
    * @Field FLimitSequencePacketMemoryUsage: Memory limit for sequence packets. Set by user.
    * @Field FAutoFreeOwnerIOClient: Whether to auto-free owner client. Set by user.
    * @Field FAutoProgressOwnerIOClient: Whether to auto-progress owner client. Set by user.
    * @Example:
    *   var Client: TZNet_CustomStableClient;
    *   begin
    *     Client := TZNet_CustomStableClient.Create;
    *     Client.OwnerIOClient := MyPhysicsClient;  // Wraps a physical client
    *     Client.Connect('127.0.0.1', 8080);
    *     // If the connection drops, Client will automatically reconnect.
    *   end;
  }
  TZNet_CustomStableClient = class(TZNet_Client)
  protected
    FOwnerIOClient: TZNet_Client; { Underlying physics client. Set by SetOwnerIOClient. }
    FStableClientIO: TStableClient_PeerIO; { Stable IO instance. Created by constructor. }
    FConnection_Addr: SystemString; { Connection address. Set by Connect/AsyncConnect. }
    FConnection_Port: Word; { Connection port. Set by Connect/AsyncConnect. }
    FAutomatedConnection: Boolean; { Whether automated reconnection is enabled. Set by user. }
    FLimitSequencePacketMemoryUsage: Int64; { Memory limit for sequence packets. Set by user. }
    FAutoFreeOwnerIOClient: Boolean; { Whether to auto-free owner client. Set by user. }
    FAutoProgressOwnerIOClient: Boolean; { Whether to auto-progress owner client. Set by user. }
    CustomStableClientProgressing: Boolean; { Progress re-entry guard. Set by Progress. }
    KeepAliveChecking: Boolean; { Whether keep-alive check is in progress. Set by Progress. }
    SaveLastCommunicationTick_Received: TTimeTick; { Saved receive tick for keep-alive. Set by Progress. }
    FOnAsyncConnectNotify_C: TOnState_C; { Async connect result (C). Set by AsyncConnectC. }
    FOnAsyncConnectNotify_M: TOnState_M; { Async connect result (method). Set by AsyncConnectM. }
    FOnAsyncConnectNotify_P: TOnState_P; { Async connect result (nested). Set by AsyncConnectP. }
    procedure ClientCustomProtocolReceiveBufferNotify(Sender: TZNet_Client; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
    procedure SetOwnerIOClient(const Value: TZNet_Client);
    procedure BuildStableIO_Result(Sender: TPeerIO; Result_: TDFE);
    procedure AsyncConnectResult(const cState: Boolean);
    procedure PostConnection(Sender: TN_Post_Execute);
    procedure OpenStableIO_Result(Sender: TPeerIO; Result_: TDFE);
    procedure AsyncReconnectionResult(const cState: Boolean);
    procedure PostReconnection(Sender: TN_Post_Execute);
    procedure Reconnection;
    function GetStopCommunicationTimeTick: TTimeTick;
  public
    constructor Create; override;
    destructor Destroy; override;
    property OwnerIOClient: TZNet_Client read FOwnerIOClient write SetOwnerIOClient;
    property LimitSequencePacketMemoryUsage: Int64 read FLimitSequencePacketMemoryUsage write FLimitSequencePacketMemoryUsage;
    property AutoFreeOwnerIOClient: Boolean read FAutoFreeOwnerIOClient write FAutoFreeOwnerIOClient;
    property AutoProgressOwnerIOClient: Boolean read FAutoProgressOwnerIOClient write FAutoProgressOwnerIOClient;
    property AutomatedConnection: Boolean read FAutomatedConnection write FAutomatedConnection;
    property StopCommunicationTimeTick: TTimeTick read GetStopCommunicationTimeTick;
    property StableClientIO: TStableClient_PeerIO read FStableClientIO;
    procedure TriggerDoConnectFailed; override;
    procedure TriggerDoConnectFinished; override;
    procedure AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C); override;
    procedure AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M); override;
    procedure AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P); override;
    function Connect(addr: SystemString; Port: Word): Boolean; override;
    function Connected: Boolean; override;
    procedure Disconnect; override;
    function ClientIO: TPeerIO; override;
    procedure Progress; override;
  end;

  TZNet_StableClient = class(TZNet_CustomStableClient);
{$ENDREGION 'StableIO'}
{$REGION 'HPC Support Base'}
  THPC_Base = class; { Base class for HPC (High-Performance Computing) job objects. }

  THPC_Instance_Pool = class(TCritical_BigList<THPC_Base>) { Pool of HPC base objects. }
  public
    procedure DoFree(var data: THPC_Base); override;
  end;

  {
    * THPC_Base: Base class for thread-pool executed tasks.
    * All HPC task objects derive from this class. They are automatically
    * added to the global instance pool for lifecycle management.
    * @Field Instance_Ptr: Pointer in global instance pool. Set by constructor.
    * @Example:
    *   type
    *     TMyHPCTask = class(THPC_Base)
    *       procedure Execute;
    *     end;
    *   // The task will be automatically tracked in HPC_Instance_Pool.
  }
  THPC_Base = class(TCore_Object_Intermediate)
  public
    Instance_Ptr: THPC_Instance_Pool.PQueueStruct; { Pointer in global instance pool. Set by constructor. }
    constructor Create;
    procedure Do_Free_Instance_Ptr; virtual;
    destructor Destroy; override;
  end;
{$ENDREGION 'HPC Support Base'}
{$REGION 'HPC Stream Support'}

  THPC_Stream = class;
  TOnHPC_Stream_C = procedure(thSender: THPC_Stream; ThInData, ThOutData: TDFE);
  TOnHPC_Stream_M = procedure(thSender: THPC_Stream; ThInData, ThOutData: TDFE) of object;
  TOnHPC_Stream_Done_C = procedure(thSender: THPC_Stream; IO: TPeerIO; ThInData, ThOutData: TDFE);
  TOnHPC_Stream_Done_M = procedure(thSender: THPC_Stream; IO: TPeerIO; ThInData, ThOutData: TDFE) of object;
{$IFDEF FPC}
  TOnHPC_Stream_P = procedure(thSender: THPC_Stream; ThInData, ThOutData: TDFE) is nested;
  TOnHPC_Stream_Done_P = procedure(thSender: THPC_Stream; IO: TPeerIO; ThInData, ThOutData: TDFE) is nested;
{$ELSE FPC}
  TOnHPC_Stream_P = reference to procedure(thSender: THPC_Stream; ThInData, ThOutData: TDFE);
  TOnHPC_Stream_Done_P = reference to procedure(thSender: THPC_Stream; IO: TPeerIO; ThInData, ThOutData: TDFE);
{$ENDIF FPC}

  {
    * THPC_Stream: HPC task that executes a stream-style command in a thread.
    * The input and output are TDFE (data frame exchange) objects. The task
    * runs in a thread pool and delivers the result back to the main thread
    * via the OnDone callback.
    * @Field Thread: Worker thread. Set during execution.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData, OutData: Input and output data. Set by caller.
    * @Field OnDone_C: Done callback (C). Set by caller.
    * @Field OnDone_M: Done callback (method). Set by caller.
    * @Field OnDone_P: Done callback (nested). Set by caller.
    * @Example:
    *   // In a stream command handler:
    *   RunHPC_StreamM(Sender, MyData, MyObject, InData, OutData,
    *     procedure(thSender: THPC_Stream; ThInData, ThOutData: TDFE)
    *     begin
    *       // Process ThInData in a background thread
    *       ThOutData.WriteString('processed');
    *     end
    *   );
  }
  THPC_Stream = class(THPC_Base)
  protected
    On_C: TOnHPC_Stream_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_Stream_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_Stream_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
    procedure RunDone();
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData, OutData: TDFE; { Input and output data. Set by caller. }
    OnDone_C: TOnHPC_Stream_Done_C; { Done callback (C). Set by caller. }
    OnDone_M: TOnHPC_Stream_Done_M; { Done callback (method). Set by caller. }
    OnDone_P: TOnHPC_Stream_Done_P; { Done callback (nested). Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_StreamC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_C); overload;
procedure RunHPC_StreamC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_C); overload;
procedure RunHPC_StreamM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_M); overload;
procedure RunHPC_StreamM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_M); overload;
procedure RunHPC_StreamP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_P); overload;
procedure RunHPC_StreamP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_P); overload;
{$ENDREGION 'HPC Stream Support'}
{$REGION 'HPC StreamNotify Support'}


type
  THPC_StreamNotify = class;
  TOnHPC_StreamNotify_C = procedure(thSender: THPC_StreamNotify; ThInData: TDFE);
  TOnHPC_StreamNotify_M = procedure(thSender: THPC_StreamNotify; ThInData: TDFE) of object;
{$IFDEF FPC}
  TOnHPC_StreamNotify_P = procedure(thSender: THPC_StreamNotify; ThInData: TDFE) is nested;
{$ELSE FPC}
  TOnHPC_StreamNotify_P = reference to procedure(thSender: THPC_StreamNotify; ThInData: TDFE);
{$ENDIF FPC}

  {
    * THPC_StreamNotify: HPC task that executes a direct-stream command in a thread.
    * Unlike THPC_Stream, this task does not produce an output; it only processes
    * the incoming data.
    * @Field Thread: Worker thread. Set during execution.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData: Input data. Set by caller.
    * @Example:
    *   // In a stream notify command handler:
    *   RunHPC_StreamNotifyM(Sender, MyData, MyObject, InData,
    *     procedure(thSender: THPC_StreamNotify; ThInData: TDFE)
    *     begin
    *       // Process ThInData in a background thread
    *     end
    *   );
  }
  THPC_StreamNotify = class(THPC_Base)
  protected
    On_C: TOnHPC_StreamNotify_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_StreamNotify_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_StreamNotify_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData: TDFE; { Input data. Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_StreamNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_C); overload;
procedure RunHPC_StreamNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_C); overload;
procedure RunHPC_StreamNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_M); overload;
procedure RunHPC_StreamNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_M); overload;
procedure RunHPC_StreamNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_P); overload;
procedure RunHPC_StreamNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_P); overload;
{$ENDREGION 'HPC StreamNotify Support'}
{$REGION 'HPC Console Support'}


type
  THPC_Console = class;
  TOnHPC_Console_C = procedure(thSender: THPC_Console; ThInData: SystemString; var ThOutData: SystemString);
  TOnHPC_Console_M = procedure(thSender: THPC_Console; ThInData: SystemString; var ThOutData: SystemString) of object;
  TOnHPC_Console_Done_C = procedure(thSender: THPC_Console; IO: TPeerIO; ThInData: SystemString; var ThOutData: SystemString);
  TOnHPC_Console_Done_M = procedure(thSender: THPC_Console; IO: TPeerIO; ThInData: SystemString; var ThOutData: SystemString) of object;
{$IFDEF FPC}
  TOnHPC_Console_P = procedure(thSender: THPC_Console; ThInData: SystemString; var ThOutData: SystemString) is nested;
  TOnHPC_Console_Done_P = procedure(thSender: THPC_Console; IO: TPeerIO; ThInData: SystemString; var ThOutData: SystemString) is nested;
{$ELSE FPC}
  TOnHPC_Console_P = reference to procedure(thSender: THPC_Console; ThInData: SystemString; var ThOutData: SystemString);
  TOnHPC_Console_Done_P = reference to procedure(thSender: THPC_Console; IO: TPeerIO; ThInData: SystemString; var ThOutData: SystemString);
{$ENDIF FPC}

  {
    * THPC_Console: HPC task that executes a console command in a thread.
    * The input and output are strings. The task runs in a thread pool and
    * delivers the result back to the main thread.
    * @Field Thread: Worker thread. Set during execution.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData, OutData: Input and output strings. Set by caller.
    * @Field OnDone_C: Done callback (C). Set by caller.
    * @Field OnDone_M: Done callback (method). Set by caller.
    * @Field OnDone_P: Done callback (nested). Set by caller.
    * @Example:
    *   // In a console command handler:
    *   RunHPC_ConsoleM(Sender, MyData, MyObject, InData, OutData,
    *     procedure(thSender: THPC_Console; ThInData: string; var ThOutData: string)
    *     begin
    *       ThOutData := 'Processed: ' + ThInData;
    *     end
    *   );
  }
  THPC_Console = class(THPC_Base)
  protected
    On_C: TOnHPC_Console_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_Console_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_Console_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
    procedure RunDone();
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData, OutData: SystemString; { Input and output strings. Set by caller. }
    OnDone_C: TOnHPC_Console_Done_C; { Done callback (C). Set by caller. }
    OnDone_M: TOnHPC_Console_Done_M; { Done callback (method). Set by caller. }
    OnDone_P: TOnHPC_Console_Done_P; { Done callback (nested). Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_ConsoleC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_C); overload;
procedure RunHPC_ConsoleC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_C); overload;
procedure RunHPC_ConsoleM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_M); overload;
procedure RunHPC_ConsoleM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_M); overload;
procedure RunHPC_ConsoleP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_P); overload;
procedure RunHPC_ConsoleP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_P); overload;
{$ENDREGION 'HPC Console Support'}
{$REGION 'HPC ConsoleNotify Support'}


type
  THPC_ConsoleNotify = class;
  TOnHPC_ConsoleNotify_C = procedure(thSender: THPC_ConsoleNotify; ThInData: SystemString);
  TOnHPC_ConsoleNotify_M = procedure(thSender: THPC_ConsoleNotify; ThInData: SystemString) of object;
{$IFDEF FPC}
  TOnHPC_ConsoleNotify_P = procedure(thSender: THPC_ConsoleNotify; ThInData: SystemString) is nested;
{$ELSE FPC}
  TOnHPC_ConsoleNotify_P = reference to procedure(thSender: THPC_ConsoleNotify; ThInData: SystemString);
{$ENDIF FPC}

  {
    * THPC_ConsoleNotify: HPC task that executes a direct console command in a thread (no output).
    * @Field Thread: Worker thread. Set during execution.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData: Input string. Set by caller.
    * @Example:
    *   // In a console notify command handler:
    *   RunHPC_ConsoleNotifyM(Sender, MyData, MyObject, InData,
    *     procedure(thSender: THPC_ConsoleNotify; ThInData: string)
    *     begin
    *       // Process ThInData in a background thread
    *     end
    *   );
  }
  THPC_ConsoleNotify = class(THPC_Base)
  protected
    On_C: TOnHPC_ConsoleNotify_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_ConsoleNotify_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_ConsoleNotify_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData: SystemString; { Input string. Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_ConsoleNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_C); overload;
procedure RunHPC_ConsoleNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_C); overload;
procedure RunHPC_ConsoleNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_M); overload;
procedure RunHPC_ConsoleNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_M); overload;
procedure RunHPC_ConsoleNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_P); overload;
procedure RunHPC_ConsoleNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_P); overload;
{$ENDREGION 'HPC ConsoleNotify Support'}
{$REGION 'HPC CompleteBuffer Support'}


type
  THPC_CompleteBuffer = class;
  TOnHPC_CompleteBuffer_C = procedure(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt);
  TOnHPC_CompleteBuffer_M = procedure(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt) of object;
{$IFDEF FPC}
  TOnHPC_CompleteBuffer_P = procedure(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt) is nested;
{$ELSE FPC}
  TOnHPC_CompleteBuffer_P = reference to procedure(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt);
{$ENDIF FPC}

  {
    * THPC_CompleteBuffer: HPC task that processes a complete buffer in a thread.
    * The input is a raw memory block. The task runs in a thread pool.
    * @Field Thread: Worker thread. Set during execution.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData: Input buffer. Set by caller.
    * @Example:
    *   // In a complete buffer command handler:
    *   RunHPC_CompleteBufferM(Sender, MyData, MyObject, InData, DataSize,
    *     procedure(thSender: THPC_CompleteBuffer; ThInData: PByte; ThDataSize: NativeInt)
    *     begin
    *       // Process ThInData in a background thread
    *     end
    *   );
  }
  THPC_CompleteBuffer = class(THPC_Base)
  protected
    On_C: TOnHPC_CompleteBuffer_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_CompleteBuffer_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_CompleteBuffer_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData: TMS64; { Input buffer. Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_CompleteBufferC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_C); overload;
procedure RunHPC_CompleteBufferC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_C); overload;
procedure RunHPC_CompleteBufferM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_M); overload;
procedure RunHPC_CompleteBufferM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_M); overload;
procedure RunHPC_CompleteBufferP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_P); overload;
procedure RunHPC_CompleteBufferP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_P); overload;
{$ENDREGION 'HPC CompleteBuffer Support'}
{$REGION 'HPC CompleteBuffer_Stream Support'}


type
  THPC_CompleteBuffer_Stream = class;
  TOnHPC_CompleteBuffer_Stream_C = procedure(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE);
  TOnHPC_CompleteBuffer_Stream_M = procedure(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE) of object;
{$IFDEF FPC}
  TOnHPC_CompleteBuffer_Stream_P = procedure(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE) is nested;
{$ELSE FPC}
  TOnHPC_CompleteBuffer_Stream_P = reference to procedure(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE);
{$ENDIF FPC}

  {
    * THPC_CompleteBuffer_Stream: HPC task that processes a complete-buffer
    * stream command in a thread. Uses the no-wait bridge for asynchronous
    * response delivery.
    * @Field Thread: Worker thread. Set during execution.
    * @Field Bridge: Associated bridge. Set by caller.
    * @Field Framework: Parent framework. Set by caller.
    * @Field Cmd: Command name. Set by caller.
    * @Field TriggerTime: Creation timestamp. Set by constructor.
    * @Field WorkID: IO identifier. Set by caller.
    * @Field Send_Tunnel: Send tunnel framework. Set by caller.
    * @Field Send_Tunnel_ID: Send tunnel IO ID. Set by caller.
    * @Field UserData: User pointer. Set by caller.
    * @Field UserObject: User object. Set by caller.
    * @Field UserVariant: User variant. Set by caller.
    * @Field InData, OutData: Input and output data. Set by caller.
    * @Example:
    *   // In a complete buffer bridge command handler:
    *   RunHPC_CompleteBuffer_StreamM(Bridge, MyData, MyObject, InData, OutData,
    *     procedure(thSender: THPC_CompleteBuffer_Stream; ThInData, ThOutData: TDFE)
    *     begin
    *       // Process ThInData in a background thread
    *       ThOutData.WriteString('processed');
    *     end
    *   );
  }
  THPC_CompleteBuffer_Stream = class(THPC_Base)
  protected
    On_C: TOnHPC_CompleteBuffer_Stream_C; { C-style execution callback. Set by caller. }
    On_M: TOnHPC_CompleteBuffer_Stream_M; { Method execution callback. Set by caller. }
    On_P: TOnHPC_CompleteBuffer_Stream_P; { Nested/reference execution callback. Set by caller. }
    procedure Run(Sender: TCompute);
  public
    Thread: TCompute; { Worker thread. Set during execution. }
    Bridge: TCommandCompleteBuffer_NoWait_Bridge; { Associated bridge. Set by caller. }
    Framework: TZNet; { Parent framework. Set by caller. }
    Cmd: SystemString; { Command name. Set by caller. }
    TriggerTime: TTimeTick; { Creation timestamp. Set by constructor. }
    WorkID: Cardinal; { IO identifier. Set by caller. }
    Send_Tunnel: TZNet; { Send tunnel framework. Set by caller. }
    Send_Tunnel_ID: Cardinal; { Send tunnel IO ID. Set by caller. }
    UserData: Pointer; { User pointer. Set by caller. }
    UserObject: TCore_Object; { User object. Set by caller. }
    UserVariant: Variant; { User variant. Set by caller. }
    InData, OutData: TDFE; { Input and output data. Set by caller. }
    property ID: Cardinal read WorkID;
    constructor Create;
    destructor Destroy; override;
    function IsOnline: Boolean;
    function IO: TPeerIO;
  end;

procedure RunHPC_CompleteBuffer_StreamC(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_C); overload;
procedure RunHPC_CompleteBuffer_StreamC(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_C); overload;
procedure RunHPC_CompleteBuffer_StreamM(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_M); overload;
procedure RunHPC_CompleteBuffer_StreamM(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_M); overload;
procedure RunHPC_CompleteBuffer_StreamP(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_P); overload;
procedure RunHPC_CompleteBuffer_StreamP(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_P); overload;
{$ENDREGION 'HPC CompleteBuffer_Stream Support'}
{$REGION 'api'}

procedure DisposeQueueData(const v: PQueueData); { Utility procedures for queue data lifecycle. }
procedure InitQueueData(var v: TQueueData);
function NewQueueData(IO: TPeerIO): PQueueData;
function IsSystemCMD(const Cmd: U_String): Boolean; { Check if a command is an internal system command. }
function StrToIPv4(const S: U_String; var Success: Boolean): TIPV4; { IPv4/IPv6 conversion utilities. }
function IPv4ToStr(const IPv4Addr_: TIPV4): U_String;
function StrToIPv6(const S: U_String; var Success: Boolean; var ScopeID: Cardinal): TIPV6; overload;
function StrToIPv6(const S: U_String; var Success: Boolean): TIPV6; overload;
function IPv6ToStr(const IPv6Addr: TIPV6): U_String;
function IsIPv4(const S: U_String): Boolean;
function IsIPV6(const S: U_String): Boolean;
function MakeRandomIPV6(): TIPV6;
function IsLocalNetworkIPV4(const S: U_String): Boolean;
function IsLoopbackIPV4(const S: U_String): Boolean;
function IsLoopbackIPV6(const S: U_String): Boolean;
function CompareIPV4(const IP1, IP2: TIPV4): Boolean;
function CompareIPV6(const IP1, IP2: TIPV6): Boolean;
function TranslateBindAddr(addr: SystemString): SystemString; { Host address parsing. }
procedure ExtractHostAddress(var Host: U_String; var Port: Word); overload;
procedure ExtractHostAddress(var Host, Port: U_String); overload;
function Build_Host_URL(Host, Port: SystemString): SystemString; overload;
function Build_Host_URL(Host: SystemString; Port: Word): SystemString; overload;
function Get_Link_OK_Send_Tunnel(IO_: TPeerIO; var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean; overload; { Double-tunnel helper functions. }
function Get_Link_OK_Send_Tunnel(Framework_: TZNet; ID_: Cardinal; var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean; overload;
function Get_Link_OK_Recv_Tunnel(IO_: TPeerIO; var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean; overload;
function Get_Link_OK_Recv_Tunnel(Framework_: TZNet; ID_: Cardinal; var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean; overload;
procedure DoExecuteResult(IO: TPeerIO; const QueuePtr: PQueueData; const Result_Text: SystemString; Result_DF: TDFE); { Execute a result callback. }
procedure Set_Instance_QuietMode(Inst: TZNet; QuietMode_: Boolean); { Set quiet mode for an entire instance (including clones). }
{$ENDREGION 'api'}
{$REGION 'ConstAndVariant'}


{
  ===========================================================================
  Global variables and constants - define protocol tokens, default sizes,
  and global state for the Z.Net communication framework.
  ===========================================================================
}
var
  {
    * ZNet_Instance_Pool: Global pool that tracks every TZNet instance.
    * Each instance registers itself upon construction and unregisters on destruction.
    * Used primarily for debugging, monitoring, and global operations such as
    * broadcasting progress or collecting statistics across all active frameworks.
    * Scenarios: server admin tools, status dashboards, forced shutdown cleanup,
    * and cross-instance event coordination.
  }
  ZNet_Instance_Pool: TZNet_Instance_Pool;
  {
    * HPC_Instance_Pool: Global pool of all active HPC task objects.
    * Each background thread task registers itself here to allow lifecycle tracking,
    * enumeration, and safe termination. Useful for debugging thread pools,
    * monitoring task completion, and ensuring all tasks are properly freed
    * when the application shuts down.
  }
  HPC_Instance_Pool: THPC_Instance_Pool;
  {
    * ZNet_Def_Sequence_Packet_HeadSize: Fixed size of the header for a sequence packet.
    * Excludes the type byte. Used when parsing or constructing sequence packets.
    * Value: $16 (22 decimal).
  }
  ZNet_Def_Sequence_Packet_HeadSize: Byte = $16;
  {
    * ZNet_Def_Sequence_QuietPacket: Token for a sequence packet sent without expecting acknowledgment.
    * Used when the reliable feature is disabled temporarily.
    * Value: $01.
  }
  ZNet_Def_Sequence_QuietPacket: Byte = $01;
  {
    * ZNet_Def_Sequence_Packet: Token for a normal sequence packet that carries data and requires acknowledgment.
    * The receiver will send back an echo packet when this is processed.
    * Value: $02.
  }
  ZNet_Def_Sequence_Packet: Byte = $02;
  {
    * ZNet_Def_Sequence_EchoPacket: Token for an acknowledgment packet sent by the receiver.
    * The sender uses it to discard the corresponding packet from its resend history.
    * Value: $03.
  }
  ZNet_Def_Sequence_EchoPacket: Byte = $03;
  {
    * ZNet_Def_Sequence_KeepAlive: Token for a keep-alive packet sent periodically to test connection liveliness.
    * The receiver replies with ZNet_Def_Sequence_EchoKeepAlive.
    * Value: $04.
  }
  ZNet_Def_Sequence_KeepAlive: Byte = $04;
  {
    * ZNet_Def_Sequence_EchoKeepAlive: Token for the reply to a keep-alive packet.
    * Indicates that the peer is still responsive and that the connection is healthy.
    * Value: $05.
  }
  ZNet_Def_Sequence_EchoKeepAlive: Byte = $05;
  {
    * ZNet_Def_Sequence_RequestResend: Token for a request to resend a specific sequence packet.
    * Sent when the receiver detects a gap in the expected sequence numbers.
    * Value: $06.
  }
  ZNet_Def_Sequence_RequestResend: Byte = $06;
  {
    * ZNet_Def_p2pVM_echoing: Token for a P2PVM echo request frame.
    * The sender requests a round-trip time measurement; the receiver must reply with ZNet_Def_p2pVM_echo.
    * Value: $01.
  }
  ZNet_Def_p2pVM_echoing: Byte = $01;
  {
    * ZNet_Def_p2pVM_echo: Token for a P2PVM echo reply frame.
    * Sent in response to an echoing request to complete the latency measurement.
    * Value: $02.
  }
  ZNet_Def_p2pVM_echo: Byte = $02;
  {
    * ZNet_Def_p2pVM_AuthSuccessed: Token for a frame that indicates successful authentication.
    * Once this is sent/received, the virtual network is considered established and ready for data exchange.
    * Value: $09.
  }
  ZNet_Def_p2pVM_AuthSuccessed: Byte = $09;
  {
    * ZNet_Def_p2pVM_Listen: Token for a frame that announces a listening endpoint on a P2PVM node.
    * Used to publish services so that other peers can connect virtually.
    * Value: $10.
  }
  ZNet_Def_p2pVM_Listen: Byte = $10;
  {
    * ZNet_Def_p2pVM_ListenState: Token for a frame that updates the status of a previously announced listener.
    * Allows peers to know when a service becomes available or unavailable.
    * Value: $11.
  }
  ZNet_Def_p2pVM_ListenState: Byte = $11;
  {
    * ZNet_Def_p2pVM_Connecting: Token for a connection request frame sent by a client.
    * Initiates a virtual connection to a remote listening endpoint.
    * Value: $20.
  }
  ZNet_Def_p2pVM_Connecting: Byte = $20;
  {
    * ZNet_Def_p2pVM_ConnectedReponse: Token for a connection response frame sent by the server.
    * Accepts or rejects a virtual connection request and contains the assigned virtual IDs.
    * Value: $21.
  }
  ZNet_Def_p2pVM_ConnectedReponse: Byte = $21;
  {
    * ZNet_Def_p2pVM_Disconnect: Token for a frame that gracefully closes a virtual connection.
    * Both peers can send this to terminate the virtual channel.
    * Value: $40.
  }
  ZNet_Def_p2pVM_Disconnect: Byte = $40;
  {
    * ZNet_Def_p2pVM_LogicFragmentData: Token for a data frame that carries application-level payload over the virtual network.
    * The primary data carrier for logical channels.
    * Value: $54.
  }
  ZNet_Def_p2pVM_LogicFragmentData: Byte = $54;
  {
    * ZNet_Def_p2pVM_OwnerIOFragmentData: Token for a data frame that carries raw physical-layer data forwarded through the P2PVM tunnel.
    * Used when the virtual network is layered on top of an existing connection.
    * Value: $64.
  }
  ZNet_Def_p2pVM_OwnerIOFragmentData: Byte = $64;
  {
    * ZNet_Def_DefaultConsoleToken: Token for a console command that expects a response.
    * Value: $F1.
  }
  ZNet_Def_DefaultConsoleToken: Byte = $F1;
  {
    * ZNet_Def_DefaultStreamToken: Token for a stream command that expects a response.
    * Value: $2F.
  }
  ZNet_Def_DefaultStreamToken: Byte = $2F;
  {
    * ZNet_Def_DefaultConsoleNotifyToken: Token for a console command that does NOT expect a response.
    * Fire-and-forget console command.
    * Value: $F3.
  }
  ZNet_Def_DefaultConsoleNotifyToken: Byte = $F3;
  {
    * ZNet_Def_DefaultStreamNotifyToken: Token for a stream command that does NOT expect a response.
    * Fire-and-forget stream command.
    * Value: $4F.
  }
  ZNet_Def_DefaultStreamNotifyToken: Byte = $4F;
  {
    * ZNet_Def_DefaultBigStreamToken: Token for a big-stream command.
    * Initiates the transfer of a large data block.
    * Value: $F5.
  }
  ZNet_Def_DefaultBigStreamToken: Byte = $F5;
  {
    * ZNet_Def_DefaultBigStreamReceiveFragmentSignal: Token for a signal sent by the receiver to request the next fragment.
    * Used for flow control during big-stream transfers.
    * Value: $F6.
  }
  ZNet_Def_DefaultBigStreamReceiveFragmentSignal: Byte = $F6;
  {
    * ZNet_Def_DefaultBigStreamReceiveDoneSignal: Token for a signal indicating the entire big-stream has been received.
    * Value: $F7.
  }
  ZNet_Def_DefaultBigStreamReceiveDoneSignal: Byte = $F7;
  {
    * ZNet_Def_DefaultCompleteBufferToken: Token for a complete-buffer command.
    * Used for small-to-medium sized transfers that must be processed as a whole.
    * Value: $6F.
  }
  ZNet_Def_DefaultCompleteBufferToken: Byte = $6F;
  {
    * ZNet_Def_DataHeadToken: Fixed 4-byte marker at the start of every command packet.
    * If this value is not found, the packet is considered corrupt and the connection is closed.
    * Value: $F0F0F0F0.
  }
  ZNet_Def_DataHeadToken: Cardinal = $F0F0F0F0;
  {
    * ZNet_Def_DataTailToken: Fixed 4-byte marker at the end of every command packet.
    * Verifies that the packet was fully received and not truncated.
    * Value: $F1F1F1F1.
  }
  ZNet_Def_DataTailToken: Cardinal = $F1F1F1F1;
  {
    * ZNet_Progress_Max_Delay: Maximum time the large-scale IO progress loop may spend processing a single batch.
    * Prevents the main loop from blocking too long when many connections are active.
    * Default: 1000 ms.
  }
  ZNet_Progress_Max_Delay: TTimeTick = 1000;
  {
    * ZNet_Def_SendFlushSize: Size of each chunk when flushing the send buffer.
    * Larger values may improve throughput but increase latency.
    * Default: 32 KB.
  }
  ZNet_Def_SendFlushSize: NativeInt = 32 * 1024;
  {
    * ZNet_Def_Extract_Physics_Fragment_Max_Size: Maximum total bytes extracted from the physical fragment pool per cycle.
    * Limits CPU usage during heavy receive bursts.
    * Default: 1 MB.
  }
  ZNet_Def_Extract_Physics_Fragment_Max_Size: Int64 = 1024 * 1024;
  {
    * ZNet_Def_Per_Progress_Loop_Limit: Maximum number of commands processed in one Progress() call for a given IO.
    * Prevents the loop from starving other IOs or the UI.
    * Default: 500.
  }
  ZNet_Def_Per_Progress_Loop_Limit: Integer = 500;
  {
    * ZNet_Def_MaxCompleteBufferSize: Maximum allowed size for a complete-buffer command.
    * If a received buffer exceeds this limit, the connection is closed to prevent memory exhaustion.
    * Default: 64 MB.
  }
  ZNet_Def_MaxCompleteBufferSize: Cardinal = 64 * 1024 * 1024;
  {
    * ZNet_Def_CompleteBufferCompressionCondition: Minimum buffer size for compression.
    * Smaller buffers are sent uncompressed to avoid overhead.
    * Default: 1024 bytes.
  }
  ZNet_Def_CompleteBufferCompressionCondition: Cardinal = 1024;
  {
    * ZNet_Def_CompleteBuffer_SwapSpace_Activted: Whether complete-buffer data may be swapped to disk when busy or large.
    * Reduces memory pressure.
    * Default: False.
  }
  ZNet_Def_CompleteBuffer_SwapSpace_Activted: Boolean = False;
  {
    * ZNet_Def_CompleteBuffer_SwapSpace_Trigger: Minimum buffer size that triggers swapping to disk.
    * Only effective if swap space is activated.
    * Default: 1024 bytes.
  }
  ZNet_Def_CompleteBuffer_SwapSpace_Trigger: Int64 = 1024;
  {
    * ZNet_Def_SequencePacketMTU: Maximum Transmission Unit for sequence packets.
    * Maximum payload size of each individual packet fragment.
    * Default: 1536 bytes.
  }
  ZNet_Def_SequencePacketMTU: Word = 1536;
  {
    * ZNet_Def_P2PVM_MaxVMFragmentSize: Maximum payload size for a single P2PVM fragment packet.
    * Default: 1536 bytes.
  }
  ZNet_Def_P2PVM_MaxVMFragmentSize: Cardinal = 1536;
  {
    * ZNet_Def_P2PVM_Progress_Send_Size: Maximum total bytes sent in one Progress() cycle for P2PVM.
    * Default: 500 KB.
  }
  ZNet_Def_P2PVM_Progress_Send_Size: Int64 = 500 * 1024;
  {
    * ZNet_Def_DoStatusID: Identifier used when printing debug status messages via DoStatus().
    * Helps filter or route log messages.
    * Default: $0FFFFFFF.
  }
  ZNet_Def_DoStatusID: Integer = $0FFFFFFF;
  {
    * ZNet_Def_VMAuthSize: Number of random 32-bit integers used to build the P2PVM authentication token.
    * Larger values increase security but also increase handshake size.
    * Default: 16 (64 bytes total).
  }
  ZNet_Def_VMAuthSize: Integer = 16;
  {
    * ZNet_Def_BigStream_ChunkSize: Size of each data chunk when sending a big-stream.
    * Default: 1 MB.
  }
  ZNet_Def_BigStream_ChunkSize: NativeInt = 1024 * 1024;
  {
    * ZNet_Def_BigStream_Memory_SwapSpace_Activted: Whether big-stream data may be swapped to disk for large streams.
    * Default: False.
  }
  ZNet_Def_BigStream_Memory_SwapSpace_Activted: Boolean = False;
  {
    * ZNet_Def_BigStream_SwapSpace_Trigger: Minimum size of a big-stream that triggers swapping to disk.
    * Only effective if swap space is activated.
    * Default: 1 MB.
  }
  ZNet_Def_BigStream_SwapSpace_Trigger: Int64 = 1024 * 1024;
  {
    * ZNet_Def_Physics_Fragment_Cache_Activted: Whether received physical fragments are cached before processing.
    * Helps smooth burst traffic.
    * Default: False.
  }
  ZNet_Def_Physics_Fragment_Cache_Activted: Boolean = False;
  {
    * ZNet_Def_Physics_Fragment_Cache_Trigger: Maximum number of fragments kept in the in-memory pool before swapping.
    * Default: 10000.
  }
  ZNet_Def_Physics_Fragment_Cache_Trigger: NativeInt = 10000;
  {
    * ZNet_Def_Swap_Space_Technology_Security_Model: Whether the ZDB2 swap space should be encrypted.
    * Enabling adds security but reduces performance.
    * Default: False.
  }
  ZNet_Def_Swap_Space_Technology_Security_Model: Boolean = False;
  {
    * ZNet_Def_Swap_Space_Technology_Delta: Space to add to the ZDB2 swap database when it runs out of free space.
    * Default: 64 MB.
  }
  ZNet_Def_Swap_Space_Technology_Delta: Int64 = 64 * 1024 * 1024;
  {
    * ZNet_Def_Swap_Space_Technology_Block: Block size used when expanding the ZDB2 swap database.
    * Value $FFFF means the database uses the maximum possible block size (65535).
    * Default: $FFFF.
  }
  ZNet_Def_Swap_Space_Technology_Block: Word = $FFFF;
  {
    * ZNet_Def_IPV6_Seed: Monotonically increasing seed used when generating random IPv6 addresses.
    * Ensures each generated address is unique across the process.
    * Default: 0.
  }
  ZNet_Def_IPV6_Seed: UInt64 = 0;
  {
    * ProgressBackgroundProc: Global procedure called every progress cycle.
    * Use for lightweight background tasks that should run alongside the network engine.
    * Default: nil (disabled).
  }
  ProgressBackgroundProc: TOnProgressBackground_C = nil;
  {
    * ProgressBackgroundMethod: Global method called every progress cycle.
    * Allows stateful object methods for background tasks.
    * Default: nil (disabled).
  }
  ProgressBackgroundMethod: TOnProgressBackground_M = nil;

const
  { Internal system command names. }
  C_CipherModel: SystemString = '__@CipherModel';
  C_Wait: SystemString = '__@Wait';
  C_BuildP2PAuthToken: SystemString = '__@BuildP2PAuthToken';
  C_InitP2PTunnel: SystemString = '__@InitP2PTunnel';
  C_CloseP2PTunnel: SystemString = '__@CloseP2PTunnel';
  C_NULL: SystemString = '__@NULL';
  C_Complete_Buffer_Stream_Reponse: SystemString = '__@Complete_Buffer_Stream_Reponse';
  C_BuildStableIO: SystemString = '__@BuildStableIO';
  C_OpenStableIO: SystemString = '__@OpenStableIO';
  C_CloseStableIO: SystemString = '__@CloseStableIO';

  { Double-tunnel / data store command names. }
  C_FileInfo: SystemString = '__@FileInfo';
  C_PostFile: SystemString = '__@PostFile';
  C_PostFileOver: SystemString = '__@PostFileOver';
  C_PostBatchStreamDone: SystemString = '__@PostBatchStreamDone';
  C_UserDB: SystemString = 'UserDB';
  C_UserLogin: SystemString = '__@UserLogin';
  C_RegisterUser: SystemString = '__@RegisterUser';
  C_TunnelLink: SystemString = '__@TunnelLink';
  C_ChangePasswd: SystemString = '__@ChangePasswd';
  C_CustomNewUser: SystemString = '__@CustomNewUser';
  C_ProcessStoreQueueCMD: SystemString = '__@ProcessStoreQueueCMD';
  C_GetPublicFileList: SystemString = '__@GetPublicFileList';
  C_GetPrivateFileList: SystemString = '__@GetPrivateFileList';
  C_GetPrivateDirectoryList: SystemString = '__@GetPrivateDirectoryList';
  C_CreatePrivateDirectory: SystemString = '__@CreatePrivateDirectory';
  C_GetPublicFileInfo: SystemString = '__@GetPublicFileInfo';
  C_GetPrivateFileInfo: SystemString = '__@GetPrivateFileInfo';
  C_GetPublicFileMD5: SystemString = '__@GetPublicFileMD5';
  C_GetPrivateFileMD5: SystemString = '__@GetPrivateFileMD5';
  C_GetPublicFile: SystemString = '__@GetPublicFile';
  C_GetPrivateFile: SystemString = '__@GetPrivateFile';
  C_GetUserPrivateFile: SystemString = '__@GetUserPrivateFile';
  C_GetPublicFileAs: SystemString = '__@GetPublicFileAs';
  C_GetPrivateFileAs: SystemString = '__@GetPrivateFileAs';
  C_GetUserPrivateFileAs: SystemString = '__@GetUserPrivateFileAs';
  C_PostPublicFileInfo: SystemString = '__@PostPublicFileInfo';
  C_PostPrivateFileInfo: SystemString = '__@PostPrivateFileInfo';
  C_GetCurrentCadencer: SystemString = '__@GetCurrentCadencer';
  C_NewBatchStream: SystemString = '__@NewBatchStream';
  C_PostBatchStream: SystemString = '__@PostBatchStream';
  C_ClearBatchStream: SystemString = '__@ClearBatchStream';
  C_GetBatchStreamState: SystemString = '__@GetBatchStreamState';
  C_GetUserPrivateFileList: SystemString = '__@GetUserPrivateFileList';
  C_GetUserPrivateDirectoryList: SystemString = '__@GetUserPrivateDirectoryList';
  C_GetFileTime: SystemString = '__@GetFileTime';
  C_GetFileInfo: SystemString = '__@GetFileInfo';
  C_GetFileMD5: SystemString = '__@GetFileMD5';
  C_GetFile: SystemString = '__@GetFile';
  C_GetFileAs: SystemString = '__@GetFileAs';
  C_PostFileInfo: SystemString = '__@PostFileInfo';
  C_GetPublicFileFragmentData: SystemString = '__@GetPublicFileFragmentData';
  C_GetPrivateFileFragmentData: SystemString = '__@GetPrivateFileFragmentData';
  C_GetFileFragmentData: SystemString = '__@GetFileFragmentData';
  C_PostFileFragmentData: SystemString = '__@PostFileFragmentData';

  { Data store commands. }
  C_DataStoreSecurity: SystemString = '__@DataStoreSecurity';
  C_CompletedFragmentBigStream: SystemString = '__@CompletedFragmentBigStream';
  C_CompletedQuery: SystemString = '__@CompletedQuery';
  C_CompletedDownloadAssemble: SystemString = '__@CompletedDownloadAssemble';
  C_CompletedFastDownloadAssemble: SystemString = '__@CompletedFastDownloadAssemble';
  C_CompletedStorePosTransform: SystemString = '__@CompletedStorePosTransform';
  C_InitDB: SystemString = '__@InitDB';
  C_CloseDB: SystemString = '__@CloseDB';
  C_CopyDB: SystemString = '__@CopyDB';
  C_CompressDB: SystemString = '__@CompressDB';
  C_ReplaceDB: SystemString = '__@ReplaceDB';
  C_ResetData: SystemString = '__@ResetData';
  C_QueryDB: SystemString = '__@QueryDB';
  C_DownloadDB: SystemString = '__@DownloadDB';
  C_DownloadDBWithID: SystemString = '__@DownloadDBWithID';
  C_RequestDownloadAssembleStream: SystemString = '__@RequestDownloadAssembleStream';
  C_RequestFastDownloadAssembleStrea: SystemString = '__@RequestFastDownloadAssembleStream';
  C_FastPostCompleteBuffer: SystemString = '__@FastPostCompleteBuffer';
  C_FastInsertCompleteBuffer: SystemString = '__@FastInsertCompleteBuffer';
  C_FastModifyCompleteBuffer: SystemString = '__@FastModifyCompleteBuffer';
  C_CompletedPostAssembleStream: SystemString = '__@CompletedPostAssembleStream';
  C_CompletedInsertAssembleStream: SystemString = '__@CompletedInsertAssembleStream';
  C_CompletedModifyAssembleStream: SystemString = '__@CompletedModifyAssembleStream';
  C_DeleteData: SystemString = '__@DeleteData';
  C_GetDBList: SystemString = '__@GetDBList';
  C_GetQueryList: SystemString = '__@GetQueryList';
  C_GetQueryState: SystemString = '__@GetQueryState';
  C_QueryStop: SystemString = '__@QueryStop';
  C_QueryPause: SystemString = '__@QueryPause';
  C_QueryPlay: SystemString = '__@QueryPlay';
{$ENDREGION 'ConstAndVariant'}

implementation

uses Z.Net.DoubleTunnelIO, Z.Net.DoubleTunnelIO.VirtualAuth, Z.Net.DoubleTunnelIO.NoAuth;

procedure Init_ZNet_Instance_Pool;
begin
  ZNet_Instance_Pool := TZNet_Instance_Pool.Create;
end;

procedure Free_ZNet_Instance_Pool;
begin
  while ZNet_Instance_Pool.Num > 0 do
      DisposeObjectAndNil(ZNet_Instance_Pool.First^.data);
  DisposeObjectAndNil(ZNet_Instance_Pool);
end;

var
  BigStream_Swap_Space_Pool__: TFile_Swap_Space_Pool;

procedure Init_SwapSpace_Tech;
begin
  BigStream_Swap_Space_Pool__ := TFile_Swap_Space_Pool.Create;

{$IFDEF MSWINDOWS}
  BigStream_Swap_Space_Pool__.WorkPath := umlGetFilePath(ParamStr(0));
{$ELSE MSWINDOWS}
  BigStream_Swap_Space_Pool__.WorkPath := umlCurrentPath;
{$ENDIF MSWINDOWS}
  TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___ := nil;
  TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool_Cipher___ := nil;
end;

procedure Free_SwapSpace_Tech;
begin
  DisposeObjectAndNil(BigStream_Swap_Space_Pool__);
  DisposeObjectAndNil(TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___);
  DisposeObjectAndNil(TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool_Cipher___);
end;

procedure TZDB2_Swap_Space_Technology.DoNoSpace(Trigger: TZDB2_Core_Space; Siz_: Int64; var retry: Boolean);
begin
  retry := AppendSpace(ZNet_Def_Swap_Space_Technology_Delta, ZNet_Def_Swap_Space_Technology_Block);
end;

constructor TZDB2_Swap_Space_Technology.Create();
var
  p: PIOHnd;
  path_: U_String;
  prefix: U_String;
  i: Integer;
begin
  Critical := TCritical.Create;
{$IFDEF MSWINDOWS}
  path_ := umlGetFilePath(ParamStr(0));
  prefix := umlChangeFileExt(umlGetFileName(ParamStr(0)), '');
{$ELSE MSWINDOWS}
  path_ := BigStream_Swap_Space_Pool__.WorkPath;
  prefix := 'ZNet_Space_Technology_' + umlDecodeTimeToStr(umlNow);
{$ENDIF MSWINDOWS}
  if TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool_Cipher___ = nil then
      TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool_Cipher___ := TZDB2_Cipher.Create(TCipherSecurity.csRijndael, prefix, 1, True, False);

  tmp_swap_space_file := umlCombineFileName(path_, prefix + '.~tmp');
  i := 1;
  while umlFileExists(tmp_swap_space_file) do
    begin
      tmp_swap_space_file := umlCombineFileName(path_, prefix + PFormat('(%d).~tmp', [i]));
      inc(i);
    end;

  New(p);
  InitIOHnd(p^);
  umlFileCreate(tmp_swap_space_file, p^);
  inherited Create(p);
  if ZNet_Def_Swap_Space_Technology_Security_Model then
      Cipher := TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool_Cipher___;
  Mode := smNormal;
  AutoCloseIOHnd := True;
  AutoFreeIOHnd := True;
  OnNoSpace := DoNoSpace;
end;

destructor TZDB2_Swap_Space_Technology.Destroy;
var
  tmp: U_String;
begin
  DisposeObject(Critical);
  tmp := tmp_swap_space_file;
  try
    inherited Destroy;
    umlDeleteFile(tmp);
  except
  end;
end;

function TZDB2_Swap_Space_Technology.Create_Memory(buff: PByte; BuffSiz: NativeInt; BuffProtected_: Boolean): TZDB2_Swap_Space_Technology_Memory;
var
  tmp: TMem64;
  ID_: Integer;
begin
  tmp := TMem64.Create;
  tmp.Mapping(buff, BuffSiz);
  Critical.Lock;
  if WriteData(tmp, ID_, BuffProtected_) then
      Result := TZDB2_Swap_Space_Technology_Memory.Create(self, ID_)
  else
      Result := nil;
  Critical.UnLock;
  DisposeObject(tmp);
end;

class function TZDB2_Swap_Space_Technology.RunTime_Pool(): TZDB2_Swap_Space_Technology;
begin
  if TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___ = nil then
      TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___ := TZDB2_Swap_Space_Technology.Create;
  Result := TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___;
end;

constructor TZDB2_Swap_Space_Technology_Memory.Create();
begin
  Create(nil, -1);
end;

constructor TZDB2_Swap_Space_Technology_Memory.Create(Owner_: TZDB2_Swap_Space_Technology; ID_: Integer);
begin
  inherited Create;
  FOwner := Owner_;
  FID := ID_;
end;

destructor TZDB2_Swap_Space_Technology_Memory.Destroy;
begin
  if (FOwner <> nil) and (FID >= 0) then
    begin
      FOwner.Critical.Lock;
      FOwner.RemoveData(FID, True);
      FOwner.Critical.UnLock;
      if FOwner.State^.FreeSpace >= FOwner.State^.Physics then
          DisposeObjectAndNil(TZDB2_Swap_Space_Technology.ZDB2_Swap_Space_Pool___);
    end;
  inherited Destroy;
end;

function TZDB2_Swap_Space_Technology_Memory.Prepare: Boolean;
begin
  Result := False;
  if (FOwner <> nil) and (FID >= 0) then
    begin
      FOwner.Critical.Lock;
      Result := FOwner.ReadData(self, FID);
      FOwner.Critical.UnLock;
    end
end;

type
  TWaitSendConsoleCmdIntf = class(TCore_Object_Intermediate)
  public
    NewResult: SystemString;
    Done: Boolean;
    Failed: Boolean;
    constructor Create;
    procedure DoConsoleFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString);
    procedure DoConsoleParam(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString);
  end;

  TWaitSendStreamCmdIntf = class(TCore_Object_Intermediate)
  public
    NewResult: TDFE;
    Done: Boolean;
    Failed: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure DoStreamFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
    procedure DoStreamParam(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
  end;

constructor TWaitSendConsoleCmdIntf.Create;
begin
  inherited Create;
  NewResult := '';
  Done := False;
  Failed := False;
end;

procedure TWaitSendConsoleCmdIntf.DoConsoleFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString);
begin
  Done := True;
  Failed := True;
end;

procedure TWaitSendConsoleCmdIntf.DoConsoleParam(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString);
begin
  NewResult := Result_;
  Done := True;
  Failed := False;
end;

constructor TWaitSendStreamCmdIntf.Create;
begin
  inherited Create;
  NewResult := TDFE.Create;
  Done := False;
  Failed := False;
end;

destructor TWaitSendStreamCmdIntf.Destroy;
begin
  DisposeObject(NewResult);
  inherited Destroy;
end;

procedure TWaitSendStreamCmdIntf.DoStreamFailed(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
begin
  Done := True;
  Failed := True;
end;

procedure TWaitSendStreamCmdIntf.DoStreamParam(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
begin
  NewResult.Assign(Result_);
  Done := True;
  Failed := False;
end;

procedure DisposeQueueData(const v: PQueueData);
begin
  if v = nil then
      exit;
  if v^.DoneAutoFree then
    begin
      try
        if v^.StreamData <> nil then
            DisposeObject(v^.StreamData);

        if v^.BigStream <> nil then
            DisposeObject(v^.BigStream);

        if v^.Buffer <> nil then
            System.FreeMemory(v^.Buffer);

        if v^.Buffer_Swap_Memory <> nil then
            DisposeObject(v^.Buffer_Swap_Memory);
      except
      end;
    end;

  Dispose(v);
end;

procedure InitQueueData(var v: TQueueData);
begin
  v.IP := '';
  v.State := qsUnknow;
  v.IO_ID := 0;
  v.Cmd := '';
  v.Cipher := TCipherSecurity.csNone;
  v.ConsoleData := '';
  v.OnConsoleM := nil;
  v.OnConsoleParamM := nil;
  v.OnConsoleFailedM := nil;
  v.OnConsoleP := nil;
  v.OnConsoleParamP := nil;
  v.OnConsoleFailedP := nil;
  v.StreamData := nil;
  v.OnStreamM := nil;
  v.OnStreamParamM := nil;
  v.OnStreamFailedM := nil;
  v.OnStreamP := nil;
  v.OnStreamParamP := nil;
  v.OnStreamFailedP := nil;
  v.BigStreamStartPos := 0;
  v.BigStream := nil;
  v.Buffer := nil;
  v.BufferSize := 0;
  v.Buffer_Swap_Memory := nil;
  v.DoneAutoFree := True;
  v.Param1 := nil;
  v.Param2 := nil;
end;

function NewQueueData(IO: TPeerIO): PQueueData;
begin
  New(Result);
  InitQueueData(Result^);
  Result^.IP := IO.GetPeerIP;
  Result^.IO_ID := IO.ID;
end;

function IsSystemCMD(const Cmd: U_String): Boolean;
begin
  Result := Cmd.Same(C_CipherModel, C_BuildP2PAuthToken, C_InitP2PTunnel, C_CloseP2PTunnel, C_Wait) or
    Cmd.Same(C_NULL, C_Complete_Buffer_Stream_Reponse, C_BuildStableIO, C_OpenStableIO, C_CloseStableIO);
end;

function StrToIPv4(const S: U_String; var Success: Boolean): TIPV4;
var
  n: U_String;
  i: Integer;
  dotCount: Integer;
  NumVal: Integer;
  Len: Integer;
  CH: SystemChar;
begin
  FillPtrByte(@Result[0], SizeOf(Result), 0);
  Success := False;
  n := umlDeleteChar(S, [#32, #0, #9, #13, #10]);
  Len := n.Len;
  if Len < 6 then
      exit;
  dotCount := 0;
  NumVal := -1;
  for i := 1 to Len do
    begin
      CH := n[i];
      if CharIn(CH, c0to9) then
        begin
          if NumVal < 0 then
              NumVal := Ord(CH) - Ord('0')
          else
              NumVal := NumVal * 10 + Ord(CH) - Ord('0');
          if NumVal > 255 then
              exit;
        end
      else if CH = '.' then
        begin
          if (NumVal > -1) and (dotCount < 3) then
              Result[dotCount] := NumVal
          else
              exit;
          inc(dotCount);
          NumVal := -1;
        end
      else
          exit;
    end;

  if (NumVal > -1) and (dotCount = 3) then
    begin
      Result[dotCount] := NumVal;
      Success := True;
    end;
end;

function IPv4ToStr(const IPv4Addr_: TIPV4): U_String;
begin
  Result.Text := IntToStr(IPv4Addr_[0]) + '.' + IntToStr(IPv4Addr_[1]) + '.' + IntToStr(IPv4Addr_[2]) + '.' + IntToStr(IPv4Addr_[3]);
end;

function StrToIPv6(const S: U_String; var Success: Boolean; var ScopeID: Cardinal): TIPV6;
const
  Colon = ':';
  Percent = '%';
var
  n: U_String;
  ColonCnt: Integer;
  i: Integer;
  NumVal: Integer;
  CH: SystemChar;
  SLen: Integer;
  OmitPos: Integer;
  OmitCnt: Integer;
  PartCnt: Byte;
  ScopeFlag: Boolean;
begin
  FillPtrByte(@Result[0], SizeOf(Result), 0);
  Success := False;
  n := umlDeleteChar(S, [#32, #0, #9, #13, #10]);
  SLen := n.Len;
  if (SLen < 1) or (SLen > (4 * 8) + 7) then
      exit;
  ColonCnt := 0;
  for i := 1 to SLen do
    if (n[i] = Colon) then
        inc(ColonCnt);
  if ColonCnt > 7 then
      exit;
  OmitPos := n.GetPos('::') - 1;
  if OmitPos > -1 then
      OmitCnt := 8 - ColonCnt
  else
    begin
      OmitCnt := 0; { Make the compiler happy }
      if (n.First = Colon) or (n.Last = Colon) then
          exit;
    end;
  NumVal := -1;
  ColonCnt := 0;
  PartCnt := 0;
  i := 0;
  ScopeID := 0;
  ScopeFlag := False;
  while i < SLen do
    begin
      CH := n.buff[i];

      if CH = Percent then
        begin
          if ScopeFlag then
              exit
          else
              ScopeFlag := True;

          PartCnt := 0;
          if NumVal > -1 then
            begin
              Result[ColonCnt] := NumVal;
              NumVal := -1;
            end;
        end
      else if CH = Colon then
        begin
          if ScopeFlag then
              exit;
          PartCnt := 0;
          if NumVal > -1 then
            begin
              Result[ColonCnt] := NumVal;
              NumVal := -1;
            end;
          if (OmitPos = i) then
            begin
              inc(ColonCnt, OmitCnt);
              inc(i);
            end;
          inc(ColonCnt);
          if ColonCnt > 7 then
              exit;
        end
      else if CharIn(CH, c0to9) then
        begin
          inc(PartCnt);
          if NumVal < 0 then
              NumVal := (Ord(CH) - Ord('0'))
          else if ScopeFlag then
              NumVal := NumVal * 10 + (Ord(CH) - Ord('0'))
          else
              NumVal := NumVal * 16 + (Ord(CH) - Ord('0'));
          if (NumVal > high(Word)) or (PartCnt > 4) then
              exit;
        end
      else if CharIn(CH, cAtoZ) then
        begin
          if ScopeFlag then
              exit;
          inc(PartCnt);
          if NumVal < 0 then
              NumVal := ((Ord(CH) and 15) + 9)
          else
              NumVal := NumVal * 16 + ((Ord(CH) and 15) + 9);
          if (NumVal > high(Word)) or (PartCnt > 4) then
              exit;
        end
      else
          exit;

      inc(i);
    end;

  if (NumVal > -1) and (ColonCnt > 1) then
    begin
      if not ScopeFlag then
        begin
          Result[ColonCnt] := NumVal;
        end
      else
          ScopeID := NumVal;
    end;
  Success := ColonCnt > 1;
end;

function StrToIPv6(const S: U_String; var Success: Boolean): TIPV6;
var
  SI: Cardinal;
begin
  Result := StrToIPv6(S, Success, SI);
end;

function IPv6ToStr(const IPv6Addr: TIPV6): U_String;
var
  i: Integer;
  Zeros1, Zeros2: set of Byte;
  Zeros1Cnt, Zeros2Cnt: Byte;
  OmitFlag: Boolean;
  ipv: SystemString;
begin
  ipv := '';
  Zeros1 := [];
  Zeros2 := [];
  Zeros1Cnt := 0;
  Zeros2Cnt := 0;
  for i := low(IPv6Addr) to high(IPv6Addr) do
    begin
      if IPv6Addr[i] = 0 then
        begin
          Include(Zeros1, i);
          inc(Zeros1Cnt);
        end
      else if Zeros1Cnt > Zeros2Cnt then
        begin
          Zeros2Cnt := Zeros1Cnt;
          Zeros2 := Zeros1;
          Zeros1 := [];
          Zeros1Cnt := 0;
        end;
    end;
  if Zeros1Cnt > Zeros2Cnt then
    begin
      Zeros2 := Zeros1;
      Zeros2Cnt := Zeros1Cnt;
    end;

  if Zeros2Cnt = 0 then
    begin
      for i := low(IPv6Addr) to high(IPv6Addr) do
        begin
          if i = 0 then
              ipv := IntToHex(IPv6Addr[i], 1)
          else
              ipv := ipv + ':' + IntToHex(IPv6Addr[i], 1);
        end;
    end
  else
    begin
      OmitFlag := False;
      for i := low(IPv6Addr) to high(IPv6Addr) do
        begin
          if not(i in Zeros2) then
            begin
              if OmitFlag then
                begin
                  if ipv = '' then
                      ipv := '::'
                  else
                      ipv := ipv + ':';
                  OmitFlag := False;
                end;
              if i < high(IPv6Addr) then
                  ipv := ipv + IntToHex(IPv6Addr[i], 1) + ':'
              else
                  ipv := ipv + IntToHex(IPv6Addr[i], 1);
            end
          else
              OmitFlag := True;
        end;
      if OmitFlag then
        begin
          if ipv = '' then
              ipv := '::'
          else
              ipv := ipv + ':';
        end;
      if ipv = '' then
          ipv := '::';
    end;
  Result.Text := LowerCase(ipv);
end;

function IsIPv4(const S: U_String): Boolean;
var
  n: U_String;
  i: Integer;
  DotCnt: Integer;
  NumVal: Integer;
  CH: SystemChar;
begin
  n := umlDeleteChar(S, [#32, #0, #9, #13, #10]);
  Result := False;
  DotCnt := 0;
  NumVal := -1;
  for i := 1 to n.Len do
    begin
      CH := n[i];
      if CharIn(CH, c0to9) then
        begin
          if NumVal = -1 then
              NumVal := Ord(CH) - Ord('0')
          else
              NumVal := NumVal * 10 + Ord(CH) - Ord('0');
          if NumVal > 255 then
              exit;
        end
      else if CH = '.' then
        begin
          inc(DotCnt);
          if (DotCnt > 3) or (NumVal = -1) then
              exit;
          NumVal := -1;
        end
      else
          exit;
    end;

  Result := DotCnt = 3;
end;

function IsIPV6(const S: U_String): Boolean;
var
  ScopeID: Cardinal;
begin
  StrToIPv6(S, Result, ScopeID);
end;

function MakeRandomIPV6(): TIPV6;
var
  tmp: array [0 .. 31] of Byte;
begin
  PTimeTick(@tmp[0])^ := GetTimeTick();
  PInt64(@tmp[8])^ := MT19937Rand64($7FFFFFFFFFFFFFFF);
  PDouble(@tmp[16])^ := umlNow();
  PInt64(@tmp[24])^ := ZNet_Def_IPV6_Seed;
  AtomInc(ZNet_Def_IPV6_Seed);
  PMD5(@Result)^ := umlMD5(@tmp[0], 32);
end;

function IsLocalNetworkIPV4(const S: U_String): Boolean;
var
  n: U_String;
begin
  Result := False;
  n := S.DeleteChar(#32#0#9#13#10);
  if not IsIPv4(n) then
      exit;
  Result := umlMultipleMatch(['192.168.*.*', '10.*.*.*',
      '172.16.*.*', '172.17.*.*', '172.18.*.*', '172.19.*.*', '172.2?.*.*', '172.30.*.*', '172.31.*.*'], n);
end;

function IsLoopbackIPV4(const S: U_String): Boolean;
var
  n: U_String;
begin
  Result := False;
  n := S.DeleteChar(#32#0#9#13#10);
  Result := umlMultipleMatch(['127.0.0.1', 'localhost'], n);
end;

function IsLoopbackIPV6(const S: U_String): Boolean;
var
  n: U_String;
begin
  Result := False;
  n := S.DeleteChar(#32#0#9#13#10);
  Result := umlMultipleMatch(['::1', '::1/*'], n);
end;

function CompareIPV4(const IP1, IP2: TIPV4): Boolean;
begin
  Result := PCardinal(@IP1[0])^ = PCardinal(@IP2[0])^;
end;

function CompareIPV6(const IP1, IP2: TIPV6): Boolean;
begin
  Result := (PUInt64(@IP1[0])^ = PUInt64(@IP2[0])^) and (PUInt64(@IP1[4])^ = PUInt64(@IP2[4])^);
end;

function TranslateBindAddr(addr: SystemString): SystemString;
begin
  addr := umlTrimSpace(addr);
  if addr = '' then
      Result := 'IPv4+IPv6'
  else if addr = '127.0.0.1' then
      Result := 'Local IPv4'
  else if addr = '::1' then
      Result := 'Local IPv6'
  else if addr = '0.0.0.0' then
      Result := 'All IPv4'
  else if addr = '::' then
      Result := 'All IPv6'
  else if IsIPv4(addr) then
      Result := PFormat('Custom IPv4(%s)', [addr])
  else if IsIPV6(addr) then
      Result := PFormat('Custom IPv6(%s)', [addr])
  else
      Result := addr;
end;

procedure ExtractHostAddress(var Host: U_String; var Port: Word);
begin
  Host := Host.TrimChar(#32#10#13#9);
  if Host.GetCharCount(':') = 1 then
    begin
      Port := umlStrToInt(umlGetLastStr(Host, ':'), Port);
      Host := umlDeleteLastStr(Host, ':');
    end
  else if umlMultipleMatch(False, '[*]:*', Host) then
    begin
      Port := umlStrToInt(umlGetLastStr(Host, ':'), Port);
      Host := umlGetFirstStr(Host, '[]');
    end
  else if IsIPV6(Host) and (Host.GetCharCount('|') = 1) then
    begin
      Port := umlStrToInt(umlGetLastStr(Host, '|'), Port);
      Host := umlDeleteLastStr(Host, '|');
    end;
end;

procedure ExtractHostAddress(var Host, Port: U_String);
begin
  Host := Host.TrimChar(#32#10#13#9);
  if Host.GetCharCount(':') = 1 then
    begin
      Port := umlGetLastStr(Host, ':');
      Host := umlDeleteLastStr(Host, ':');
    end
  else if umlMultipleMatch(False, '[*]:*', Host) then
    begin
      Port := umlGetLastStr(Host, ':');
      Host := umlGetFirstStr(Host, '[]');
    end
  else if IsIPV6(Host) and (Host.GetCharCount('|') = 1) then
    begin
      Port := umlGetLastStr(Host, '|');
      Host := umlDeleteLastStr(Host, '|');
    end;
end;

function Build_Host_URL(Host, Port: SystemString): SystemString;
begin
  if IsIPV6(Host) then
      Result := Format('[%s]:%s', [Host, Port])
  else
      Result := Format('%s:%s', [Host, Port]);
end;

function Build_Host_URL(Host: SystemString; Port: Word): SystemString;
begin
  if IsIPV6(Host) then
      Result := Format('[%s]:%d', [Host, Port])
  else
      Result := Format('%s:%d', [Host, Port]);
end;

function Get_Link_OK_Send_Tunnel(IO_: TPeerIO; var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean;
begin
  Result := False;
  if IO_ = nil then
      exit;
  if IO_.UserDefine = nil then
      exit;
  if IO_.UserDefine is TService_RecvTunnel_UserDefine_NoAuth then
    begin
      if not TService_RecvTunnel_UserDefine_NoAuth(IO_.UserDefine).LinkOk then
          exit;
      Send_Tunnel := TService_RecvTunnel_UserDefine_NoAuth(IO_.UserDefine).SendTunnel.Owner.OwnerFramework;
      Send_Tunnel_ID := TService_RecvTunnel_UserDefine_NoAuth(IO_.UserDefine).SendTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_RecvTunnel_NoAuth then
    begin
      if TClient_RecvTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
        if TDTClient_NoAuth(TClient_RecvTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO <> nil then
          begin
            Send_Tunnel := TDTClient_NoAuth(TClient_RecvTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel;
            Send_Tunnel_ID := TDTClient_NoAuth(TClient_RecvTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO.ID;
            Result := True;
          end;
    end
  else if IO_.UserDefine is TService_RecvTunnel_UserDefine_VirtualAuth then
    begin
      if not TService_RecvTunnel_UserDefine_VirtualAuth(IO_.UserDefine).LinkOk then
          exit;
      Send_Tunnel := TService_RecvTunnel_UserDefine_VirtualAuth(IO_.UserDefine).SendTunnel.Owner.OwnerFramework;
      Send_Tunnel_ID := TService_RecvTunnel_UserDefine_VirtualAuth(IO_.UserDefine).SendTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_RecvTunnel_VirtualAuth then
    begin
      if TClient_RecvTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
        if TDTClient_VirtualAuth(TClient_RecvTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO <> nil then
          begin
            Send_Tunnel := TDTClient_VirtualAuth(TClient_RecvTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel;
            Send_Tunnel_ID := TDTClient_VirtualAuth(TClient_RecvTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO.ID;
            Result := True;
          end;
    end
  else if IO_.UserDefine is TService_RecvTunnel_UserDefine then
    begin
      if not TService_RecvTunnel_UserDefine(IO_.UserDefine).LinkOk then
          exit;
      Send_Tunnel := TService_RecvTunnel_UserDefine(IO_.UserDefine).SendTunnel.Owner.OwnerFramework;
      Send_Tunnel_ID := TService_RecvTunnel_UserDefine(IO_.UserDefine).SendTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_RecvTunnel then
    begin
      if TClient_RecvTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient then
        if TDTClient(TClient_RecvTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO <> nil then
          begin
            Send_Tunnel := TDTClient(TClient_RecvTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel;
            Send_Tunnel_ID := TDTClient(TClient_RecvTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).SendTunnel.ClientIO.ID;
            Result := True;
          end;
    end;
end;

function Get_Link_OK_Send_Tunnel(Framework_: TZNet; ID_: Cardinal; var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean;
begin
  Result := Get_Link_OK_Send_Tunnel(Framework_.PeerIO_HashPool[ID_], Send_Tunnel, Send_Tunnel_ID);
end;

function Get_Link_OK_Recv_Tunnel(IO_: TPeerIO; var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean;
begin
  Result := False;
  if IO_ = nil then
      exit;
  if IO_.UserDefine = nil then
      exit;
  if IO_.UserDefine is TService_SendTunnel_UserDefine_NoAuth then
    begin
      if not TService_SendTunnel_UserDefine_NoAuth(IO_.UserDefine).LinkOk then
          exit;
      Recv_Tunnel := TService_SendTunnel_UserDefine_NoAuth(IO_.UserDefine).RecvTunnel.Owner.OwnerFramework;
      Recv_Tunnel_ID := TService_SendTunnel_UserDefine_NoAuth(IO_.UserDefine).RecvTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_SendTunnel_NoAuth then
    begin
      if TClient_SendTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
        if TDTClient_NoAuth(TClient_SendTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO <> nil then
          begin
            Recv_Tunnel := TDTClient_NoAuth(TClient_SendTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel;
            Recv_Tunnel_ID := TDTClient_NoAuth(TClient_SendTunnel_NoAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO.ID;
            Result := True;
          end;
    end
  else if IO_.UserDefine is TService_SendTunnel_UserDefine_VirtualAuth then
    begin
      if not TService_SendTunnel_UserDefine_VirtualAuth(IO_.UserDefine).LinkOk then
          exit;
      Recv_Tunnel := TService_SendTunnel_UserDefine_VirtualAuth(IO_.UserDefine).RecvTunnel.Owner.OwnerFramework;
      Recv_Tunnel_ID := TService_SendTunnel_UserDefine_VirtualAuth(IO_.UserDefine).RecvTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_SendTunnel_VirtualAuth then
    begin
      if TClient_SendTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
        if TDTClient_VirtualAuth(TClient_SendTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO <> nil then
          begin
            Recv_Tunnel := TDTClient_VirtualAuth(TClient_SendTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel;
            Recv_Tunnel_ID := TDTClient_VirtualAuth(TClient_SendTunnel_VirtualAuth(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO.ID;
            Result := True;
          end;
    end
  else if IO_.UserDefine is TService_SendTunnel_UserDefine then
    begin
      if not TService_SendTunnel_UserDefine(IO_.UserDefine).LinkOk then
          exit;
      Recv_Tunnel := TService_SendTunnel_UserDefine(IO_.UserDefine).RecvTunnel.Owner.OwnerFramework;
      Recv_Tunnel_ID := TService_SendTunnel_UserDefine(IO_.UserDefine).RecvTunnelID;
      Result := True;
    end
  else if IO_.UserDefine is TClient_SendTunnel then
    begin
      if TClient_SendTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework is TDTClient then
        if TDTClient(TClient_SendTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO <> nil then
          begin
            Recv_Tunnel := TDTClient(TClient_SendTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel;
            Recv_Tunnel_ID := TDTClient(TClient_SendTunnel(IO_.UserDefine).Owner.OwnerFramework.DoubleChannelFramework).RecvTunnel.ClientIO.ID;
            Result := True;
          end;
    end;
end;

function Get_Link_OK_Recv_Tunnel(Framework_: TZNet; ID_: Cardinal; var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean;
begin
  Result := Get_Link_OK_Recv_Tunnel(Framework_.PeerIO_HashPool[ID_], Recv_Tunnel, Recv_Tunnel_ID);
end;

procedure DoExecuteResult(IO: TPeerIO; const QueuePtr: PQueueData; const Result_Text: SystemString; Result_DF: TDFE);
var
  InData: TDFE;
begin
  if QueuePtr = nil then
      exit;

  IO.FReceiveResultRuning := True;

  try
    if Assigned(QueuePtr^.OnConsoleM) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('console on result: %s', QueuePtr^.Cmd);
        try
            QueuePtr^.OnConsoleM(IO, Result_Text);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnConsoleParamM) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('console on param result: %s', QueuePtr^.Cmd);
        try
            QueuePtr^.OnConsoleParamM(IO, QueuePtr^.Param1, QueuePtr^.Param2, QueuePtr^.ConsoleData, Result_Text);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnConsoleP) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('console on result(proc): %s', QueuePtr^.Cmd);
        try
            QueuePtr^.OnConsoleP(IO, Result_Text);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnConsoleParamP) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('console on param result(proc): %s', QueuePtr^.Cmd);
        try
            QueuePtr^.OnConsoleParamP(IO, QueuePtr^.Param1, QueuePtr^.Param2, QueuePtr^.ConsoleData, Result_Text);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnStreamM) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('stream on result: %s', QueuePtr^.Cmd);
        try
          Result_DF.Reader.index := 0;
          QueuePtr^.OnStreamM(IO, Result_DF);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnStreamParamM) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('stream on param result: %s', QueuePtr^.Cmd);
        try
          Result_DF.Reader.index := 0;
          InData := TDFE.Create;
          QueuePtr^.StreamData.Position := 0;
          InData.DecodeFrom(QueuePtr^.StreamData, True);
          QueuePtr^.OnStreamParamM(IO, QueuePtr^.Param1, QueuePtr^.Param2, InData, Result_DF);
          DisposeObject(InData);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnStreamP) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('stream on result(proc): %s', QueuePtr^.Cmd);
        try
          Result_DF.Reader.index := 0;
          QueuePtr^.OnStreamP(IO, Result_DF);
        except
        end;
      end
    else if Assigned(QueuePtr^.OnStreamParamP) then
      begin
        if not IO.OwnerFramework.QuietMode then
            IO.PrintCommand('stream on result(parameter + proc): %s', QueuePtr^.Cmd);
        try
          Result_DF.Reader.index := 0;
          InData := TDFE.Create;
          QueuePtr^.StreamData.Position := 0;
          InData.DecodeFrom(QueuePtr^.StreamData, True);
          QueuePtr^.OnStreamParamP(IO, QueuePtr^.Param1, QueuePtr^.Param2, InData, Result_DF);
          DisposeObject(InData);
        except
        end;
      end;
  except
  end;
  IO.FReceiveResultRuning := False;
end;

procedure Set_Instance_QuietMode(Inst: TZNet; QuietMode_: Boolean);
var
  p2p_: TZNet_WithP2PVM_Client;
  i: Integer;
begin
  Inst.QuietMode := QuietMode_;
  if Inst is TZNet_Server then
    begin
    end
  else if Inst is TZNet_WithP2PVM_Client then
    begin
      p2p_ := TZNet_WithP2PVM_Client(Inst);
      for i := 0 to p2p_.ClonePool.Count - 1 do
          Set_Instance_QuietMode(p2p_.ClonePool[i], QuietMode_);
    end;
end;

procedure THPC_Instance_Pool.DoFree(var data: THPC_Base);
begin
  if data <> nil then
    begin
      if data.Instance_Ptr <> nil then
          data.Instance_Ptr^.data := nil;
      data.Instance_Ptr := nil;
    end;
end;

constructor THPC_Base.Create;
begin
  inherited Create;
  if HPC_Instance_Pool <> nil then
      Instance_Ptr := HPC_Instance_Pool.Add(self)
  else
      Instance_Ptr := nil;
end;

procedure THPC_Base.Do_Free_Instance_Ptr;
var
  p: THPC_Instance_Pool.PQueueStruct;
begin
  if Instance_Ptr <> nil then
    begin
      Instance_Ptr^.data := nil;
      p := Instance_Ptr;
      Instance_Ptr := nil;
      if HPC_Instance_Pool <> nil then
          HPC_Instance_Pool.Remove_P(p);
    end;
end;

destructor THPC_Base.Destroy;
begin
  Do_Free_Instance_Ptr();
  inherited Destroy;
end;

procedure THPC_Stream.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData, OutData)
    else if Assigned(On_M) then
        On_M(self, InData, OutData)
    else if Assigned(On_P) then
        On_P(self, InData, OutData);
  except
  end;
  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  with Framework.PostProgress.PostExecuteM_NP(False, 0, RunDone) do
    begin
      Auto_Free_Pool.Add(self);
      Ready;
    end;
  AtomDec(Framework.FCMD_Thread_Runing_Num);
end;

procedure THPC_Stream.RunDone();
var
  P_IO: TPeerIO;
begin
  try
    if Framework <> nil then
      begin
        P_IO := Framework.FPeerIO_HashPool[WorkID];
        if P_IO <> nil then
          begin
            try
              if Assigned(OnDone_C) then
                  OnDone_C(self, P_IO, InData, OutData)
              else if Assigned(OnDone_M) then
                  OnDone_M(self, P_IO, InData, OutData)
              else if Assigned(OnDone_P) then
                  OnDone_P(self, P_IO, InData, OutData);
            except
            end;
            P_IO.OutDataFrame.Append(OutData);
            P_IO.Resume;
          end;
      end;
  except
  end;
end;

constructor THPC_Stream.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := nil; // fixed memory leak. by.qq600585, 2023-9-30
  OutData := nil; // fixed memory leak. by.qq600585, 2023-9-30
  OnDone_C := nil;
  OnDone_M := nil;
  OnDone_P := nil;
end;

destructor THPC_Stream.Destroy;
begin
  Do_Free_Instance_Ptr();
  DisposeObject(InData);
  DisposeObject(OutData);
  inherited Destroy;
end;

function THPC_Stream.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_Stream.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_StreamC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_C);
var
  t: THPC_Stream;
begin
  Sender.Pause;
  t := THPC_Stream.Create;

  t.On_C := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_C);
begin
  RunHPC_StreamC(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_StreamM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_M);
var
  t: THPC_Stream;
begin
  Sender.Pause;
  t := THPC_Stream.Create;

  t.On_M := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_M);
begin
  RunHPC_StreamM(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_StreamP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_P);
var
  t: THPC_Stream;
begin
  Sender.Pause;
  t := THPC_Stream.Create;

  t.On_P := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_Stream_P);
begin
  RunHPC_StreamP(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure THPC_StreamNotify.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData)
    else if Assigned(On_M) then
        On_M(self, InData)
    else if Assigned(On_P) then
        On_P(self, InData);
  except
  end;
  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  AtomDec(Framework.FCMD_Thread_Runing_Num);
  DelayFreeObj(1.0, self);
end;

constructor THPC_StreamNotify.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := nil; // fixed memory leak. by.qq600585, 2023-9-30
end;

destructor THPC_StreamNotify.Destroy;
begin
  Do_Free_Instance_Ptr();
  DisposeObject(InData);
  inherited Destroy;
end;

function THPC_StreamNotify.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_StreamNotify.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_StreamNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_C);
var
  t: THPC_StreamNotify;
begin
  t := THPC_StreamNotify.Create;

  t.On_C := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_C);
begin
  RunHPC_StreamNotifyC(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure RunHPC_StreamNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_M);
var
  t: THPC_StreamNotify;
begin
  t := THPC_StreamNotify.Create;

  t.On_M := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_M);
begin
  RunHPC_StreamNotifyM(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure RunHPC_StreamNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_P);
var
  t: THPC_StreamNotify;
begin
  t := THPC_StreamNotify.Create;

  t.On_P := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_StreamNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: TDFE; const OnRun: TOnHPC_StreamNotify_P);
begin
  RunHPC_StreamNotifyP(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure THPC_Console.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData, OutData)
    else if Assigned(On_M) then
        On_M(self, InData, OutData)
    else if Assigned(On_P) then
        On_P(self, InData, OutData);
  except
  end;

  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  with Framework.PostProgress.PostExecuteM_NP(False, 0, RunDone) do
    begin
      Auto_Free_Pool.Add(self);
      Ready;
    end;
  AtomDec(Framework.FCMD_Thread_Runing_Num);
end;

procedure THPC_Console.RunDone();
var
  P_IO: TPeerIO;
begin
  try
    if Framework <> nil then
      begin
        P_IO := Framework.FPeerIO_HashPool[WorkID];
        if P_IO <> nil then
          begin
            try
              if Assigned(OnDone_C) then
                  OnDone_C(self, P_IO, InData, OutData)
              else if Assigned(OnDone_M) then
                  OnDone_M(self, P_IO, InData, OutData)
              else if Assigned(OnDone_P) then
                  OnDone_P(self, P_IO, InData, OutData);
            except
            end;

            P_IO.OutText := P_IO.OutText + OutData;
            P_IO.Resume;
          end;
      end;
  except
  end;
end;

constructor THPC_Console.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := '';
  OutData := '';
  OnDone_C := nil;
  OnDone_M := nil;
  OnDone_P := nil;
end;

destructor THPC_Console.Destroy;
begin
  Do_Free_Instance_Ptr();
  inherited Destroy;
end;

function THPC_Console.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_Console.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_ConsoleC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_C);
var
  t: THPC_Console;
begin
  Sender.Pause;
  t := THPC_Console.Create;

  t.On_C := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;
  t.OutData := OutData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_C);
begin
  RunHPC_ConsoleC(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_ConsoleM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_M);
var
  t: THPC_Console;
begin
  Sender.Pause;
  t := THPC_Console.Create;

  t.On_M := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;
  t.OutData := OutData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_M);
begin
  RunHPC_ConsoleM(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_ConsoleP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_P);
var
  t: THPC_Console;
begin
  Sender.Pause;
  t := THPC_Console.Create;

  t.On_P := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;
  t.OutData := OutData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: SystemString; const OnRun: TOnHPC_Console_P);
begin
  RunHPC_ConsoleP(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure THPC_ConsoleNotify.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData)
    else if Assigned(On_M) then
        On_M(self, InData)
    else if Assigned(On_P) then
        On_P(self, InData);
  except
  end;
  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  AtomDec(Framework.FCMD_Thread_Runing_Num);
  DelayFreeObj(1.0, self);
end;

constructor THPC_ConsoleNotify.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := '';
end;

destructor THPC_ConsoleNotify.Destroy;
begin
  Do_Free_Instance_Ptr();
  inherited Destroy;
end;

function THPC_ConsoleNotify.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_ConsoleNotify.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_ConsoleNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_C);
var
  t: THPC_ConsoleNotify;
begin
  t := THPC_ConsoleNotify.Create;

  t.On_C := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleNotifyC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_C);
begin
  RunHPC_ConsoleNotifyC(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure RunHPC_ConsoleNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_M);
var
  t: THPC_ConsoleNotify;
begin
  t := THPC_ConsoleNotify.Create;

  t.On_M := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleNotifyM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_M);
begin
  RunHPC_ConsoleNotifyM(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure RunHPC_ConsoleNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_P);
var
  t: THPC_ConsoleNotify;
begin
  t := THPC_ConsoleNotify.Create;

  t.On_P := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CurrentCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := InData;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_ConsoleNotifyP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: SystemString; const OnRun: TOnHPC_ConsoleNotify_P);
begin
  RunHPC_ConsoleNotifyP(Sender, UserData, UserObject, NULL, InData, OnRun);
end;

procedure THPC_CompleteBuffer.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData.Memory, InData.Size)
    else if Assigned(On_M) then
        On_M(self, InData.Memory, InData.Size)
    else if Assigned(On_P) then
        On_P(self, InData.Memory, InData.Size);
  except
  end;
  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  AtomDec(Framework.FCMD_Thread_Runing_Num);
  DelayFreeObj(1.0, self);
end;

constructor THPC_CompleteBuffer.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := nil;
end;

destructor THPC_CompleteBuffer.Destroy;
begin
  Do_Free_Instance_Ptr();
  DisposeObject(InData);
  inherited Destroy;
end;

function THPC_CompleteBuffer.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_CompleteBuffer.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_CompleteBufferC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_C);
var
  t: THPC_CompleteBuffer;
begin
  t := THPC_CompleteBuffer.Create;

  t.On_C := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CompleteBufferCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := Sender.CompleteBuffer_Current_Trigger.Swap_To_New_Instance;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBufferC(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_C);
begin
  RunHPC_CompleteBufferC(Sender, UserData, UserObject, NULL, InData, DataSize, OnRun);
end;

procedure RunHPC_CompleteBufferM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_M);
var
  t: THPC_CompleteBuffer;
begin
  t := THPC_CompleteBuffer.Create;

  t.On_M := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CompleteBufferCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := Sender.CompleteBuffer_Current_Trigger.Swap_To_New_Instance;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBufferM(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_M);
begin
  RunHPC_CompleteBufferM(Sender, UserData, UserObject, NULL, InData, DataSize, OnRun);
end;

procedure RunHPC_CompleteBufferP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_P);
var
  t: THPC_CompleteBuffer;
begin
  t := THPC_CompleteBuffer.Create;

  t.On_P := OnRun;

  t.Framework := Sender.OwnerFramework;
  t.Cmd := Sender.CompleteBufferCmd;
  t.WorkID := Sender.ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := Sender.CompleteBuffer_Current_Trigger.Swap_To_New_Instance;

  Get_Link_OK_Send_Tunnel(Sender, t.Send_Tunnel, t.Send_Tunnel_ID);

  AtomInc(Sender.OwnerFramework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBufferP(Sender: TPeerIO;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData: PByte; const DataSize: NativeInt; const OnRun: TOnHPC_CompleteBuffer_P);
begin
  RunHPC_CompleteBufferP(Sender, UserData, UserObject, NULL, InData, DataSize, OnRun);
end;

procedure THPC_CompleteBuffer_Stream.Run(Sender: TCompute);
var
  tk: TTimeTick;
begin
  tk := GetTimeTick();
  TCompute.Set_Thread_Info(PFormat('%s cmd:%s', [ClassName, Cmd]));
  Thread := Sender;
  try
    if Assigned(On_C) then
        On_C(self, InData, OutData)
    else if Assigned(On_M) then
        On_M(self, InData, OutData)
    else if Assigned(On_P) then
        On_P(self, InData, OutData);
  except
  end;
  Bridge.OutData.SwapInstance(OutData);
  Bridge.Resume;
  Framework.CmdMaxExecuteConsumeStatistics.SetMax(Cmd + ':HPC Thread', GetTimeTick - tk);
  AtomDec(Framework.FCMD_Thread_Runing_Num);
  DelayFreeObj(1.0, self);
end;

constructor THPC_CompleteBuffer_Stream.Create;
begin
  inherited Create;
  Thread := nil;
  On_C := nil;
  On_M := nil;
  On_P := nil;
  Bridge := nil;
  Framework := nil;
  Cmd := '';
  TriggerTime := GetTimeTick();
  WorkID := 0;
  Send_Tunnel := nil;
  Send_Tunnel_ID := 0;
  UserData := nil;
  UserObject := nil;
  UserVariant := NULL;
  InData := nil; // fixed memory leak. by.qq600585, 2023-9-30
  OutData := nil; // fixed memory leak. by.qq600585, 2023-9-30
end;

destructor THPC_CompleteBuffer_Stream.Destroy;
begin
  Do_Free_Instance_Ptr();
  DisposeObject(InData);
  DisposeObject(OutData);
  inherited Destroy;
end;

function THPC_CompleteBuffer_Stream.IsOnline: Boolean;
begin
  Result := (Framework <> nil) and (Framework.ExistsID(WorkID));
end;

function THPC_CompleteBuffer_Stream.IO: TPeerIO;
begin
  Result := nil;
  if Framework <> nil then
      Result := Framework.FPeerIO_HashPool[WorkID];
end;

procedure RunHPC_CompleteBuffer_StreamC(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_C);
var
  t: THPC_CompleteBuffer_Stream;
begin
  Sender.Pause;
  t := THPC_CompleteBuffer_Stream.Create;

  t.On_C := OnRun;

  t.Bridge := Sender;
  t.Framework := Sender.R_Framework;
  t.Cmd := Sender.Cmd;
  t.WorkID := Sender.R_ID;
  t.Send_Tunnel := Sender.S_Framework;
  t.Send_Tunnel_ID := Sender.S_ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  AtomInc(t.Framework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBuffer_StreamC(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_C);
begin
  RunHPC_CompleteBuffer_StreamC(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_CompleteBuffer_StreamM(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_M);
var
  t: THPC_CompleteBuffer_Stream;
begin
  Sender.Pause;
  t := THPC_CompleteBuffer_Stream.Create;

  t.On_M := OnRun;

  t.Bridge := Sender;
  t.Framework := Sender.R_Framework;
  t.Cmd := Sender.Cmd;
  t.WorkID := Sender.R_ID;
  t.Send_Tunnel := Sender.S_Framework;
  t.Send_Tunnel_ID := Sender.S_ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  AtomInc(t.Framework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBuffer_StreamM(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_M);
begin
  RunHPC_CompleteBuffer_StreamM(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure RunHPC_CompleteBuffer_StreamP(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object; const UserVariant: Variant;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_P);
var
  t: THPC_CompleteBuffer_Stream;
begin
  Sender.Pause;
  t := THPC_CompleteBuffer_Stream.Create;

  t.On_P := OnRun;

  t.Bridge := Sender;
  t.Framework := Sender.R_Framework;
  t.Cmd := Sender.Cmd;
  t.WorkID := Sender.R_ID;
  t.Send_Tunnel := Sender.S_Framework;
  t.Send_Tunnel_ID := Sender.S_ID;
  t.UserData := UserData;
  t.UserObject := UserObject;
  t.UserVariant := UserVariant;
  t.InData := TDFE.Create;
  if InData <> nil then
      t.InData.SwapInstance(InData);
  t.InData.R.index := 0;
  t.OutData := TDFE.Create;
  if OutData <> nil then
      t.OutData.SwapInstance(OutData);
  t.OutData.R.index := 0;

  AtomInc(t.Framework.FCMD_Thread_Runing_Num);

  TCompute.RunM(UserData, UserObject, t.Run);
end;

procedure RunHPC_CompleteBuffer_StreamP(Sender: TCommandCompleteBuffer_NoWait_Bridge;
  const UserData: Pointer; const UserObject: TCore_Object;
  const InData, OutData: TDFE; const OnRun: TOnHPC_CompleteBuffer_Stream_P);
begin
  RunHPC_CompleteBuffer_StreamP(Sender, UserData, UserObject, NULL, InData, OutData, OnRun);
end;

procedure TOnStateStruct.Init;
begin
  On_C := nil;
  On_M := nil;
  On_P := nil;
end;

procedure TOnResult_Bridge_Templet.DoConsoleEvent(Sender: TPeerIO; Result_: SystemString);
begin

end;

procedure TOnResult_Bridge_Templet.DoConsoleParamEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: SystemString);
begin

end;

procedure TOnResult_Bridge_Templet.DoConsoleFailedEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: SystemString);
begin

end;

procedure TOnResult_Bridge_Templet.DoStreamEvent(Sender: TPeerIO; Result_: TDFE);
begin

end;

procedure TOnResult_Bridge_Templet.DoStreamParamEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData, Result_: TDFE);
begin

end;

procedure TOnResult_Bridge_Templet.DoStreamFailedEvent(Sender: TPeerIO; Param1: Pointer; Param2: TObject; SendData: TDFE);
begin

end;

procedure TOnResult_Bridge_Templet.DoCompleteBufferStreamEvent(Sender: TCommandCompleteBuffer_NoWait_Bridge; InData, OutData: TDFE);
begin

end;

constructor TOnResult_Bridge.Create;
begin
  inherited Create;
end;

destructor TOnResult_Bridge.Destroy;
begin
  inherited Destroy;
end;

procedure TProgress_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TProgress_Bridge.Create(Framework_: TZNet);
begin
  inherited Create;
  Framework := Framework_;
  ProgressInstance := Framework.AddProgresss;
  ProgressInstance.OnFree := DoFree;
  ProgressInstance.OnProgress_M := Progress;
end;

destructor TProgress_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

procedure TProgress_Bridge.Progress(Sender: TZNet_Progress);
begin

end;

constructor TState_Param_Bridge.Create;
begin
  inherited Create;
  OnNotifyC := nil;
  OnNotifyM := nil;
  OnNotifyP := nil;
  Param1 := nil;
  Param2 := nil;
  OnStateMethod := DoStateResult;
end;

destructor TState_Param_Bridge.Destroy;
begin
  inherited Destroy;
end;

procedure TState_Param_Bridge.DoStateResult(const State: Boolean);
begin
  if Assigned(OnNotifyC) then
      OnNotifyC(Param1, Param2, State)
  else if Assigned(OnNotifyM) then
      OnNotifyM(Param1, Param2, State)
  else if Assigned(OnNotifyP) then
      OnNotifyP(Param1, Param2, State);
  DelayFreeObj(1.0, self);
end;

procedure TCustom_Event_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TCustom_Event_Bridge.Create(IO_: TPeerIO);
begin
  inherited Create;
  if IO_ <> nil then
    begin
      Framework_ := IO_.OwnerFramework;
      ID_ := IO_.ID;
      ProgressInstance := IO_.OwnerFramework.AddProgresss;
      ProgressInstance.OnFree := DoFree;
      ProgressInstance.OnProgress_M := Progress;
    end
  else
    begin
      Framework_ := nil;
      ID_ := 0;
      ProgressInstance := nil;
    end;
end;

destructor TCustom_Event_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

function TCustom_Event_Bridge.CheckIO: Boolean;
begin
  try
      Result := (Framework_ <> nil) and (Framework_.ExistsID(ID_));
  except
      Result := False;
  end;
end;

function TCustom_Event_Bridge.IO: TPeerIO;
begin
  if not CheckIO then
      Result := nil
  else
      Result := Framework_.PeerIO_HashPool[ID_] as TPeerIO;
end;

procedure TCustom_Event_Bridge.Progress(Sender: TZNet_Progress);
begin
end;

procedure TStream_Event_Bridge.Init(IO_: TPeerIO; AutoPause_: Boolean);
begin
  if not IO_.ReceiveCommandRuning then
      RaiseInfo('Need in Stream Event.');
  AutoPause := AutoPause_;
  if AutoPause then
      IO_.Pause;
  Framework_ := IO_.OwnerFramework;
  ID_ := IO_.ID;
  LCMD_ := IO_.CurrentCommand;
  OnResultC := nil;
  OnResultM := nil;
  OnResultP := nil;
  if not IO_.OwnerFramework.QuietMode then
      IO_.Print('Create CMD "%s" Bridge Event.', [LCMD_]);
  AutoFree := AutoPause_;
  ProgressInstance := IO_.OwnerFramework.AddProgresss;
  ProgressInstance.OnFree := DoFree;
  ProgressInstance.OnProgress_M := Progress;
end;

procedure TStream_Event_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TStream_Event_Bridge.Create(IO_: TPeerIO; AutoPause_: Boolean);
begin
  inherited Create;
  Init(IO_, AutoPause_);
end;

constructor TStream_Event_Bridge.Create(IO_: TPeerIO);
begin
  inherited Create;
  Init(IO_, True);
end;

destructor TStream_Event_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

procedure TStream_Event_Bridge.Pause;
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      IO_.Pause;
    end;
end;

procedure TStream_Event_Bridge.Play(ResultData_: TDFE);
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      IO_.OutDataFrame.Append(ResultData_);
      IO_.Resume;
    end;
  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TStream_Event_Bridge.DoStreamParamEvent(Sender_: TPeerIO; Param1_: Pointer; Param2_: TObject; SendData_, ResultData_: TDFE);
begin
  DoStreamEvent(Sender_, ResultData_);
end;

procedure TStream_Event_Bridge.DoStreamFailed(Sender_: TPeerIO; Param1: Pointer; Param2: TObject; SendData_: TDFE);
var
  de: TDFE;
begin
  de := TDFE.Create;
  DoStreamEvent(Sender_, de);
  DisposeObject(de);
end;

procedure TStream_Event_Bridge.DoStreamEvent(Sender_: TPeerIO; ResultData_: TDFE);
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      if Assigned(OnResultC) then
          OnResultC(self, IO_, Sender_, ResultData_)
      else if Assigned(OnResultM) then
          OnResultM(self, IO_, Sender_, ResultData_)
      else if Assigned(OnResultP) then
          OnResultP(self, IO_, Sender_, ResultData_);
      if AutoPause then
        begin
          IO_.OutDataFrame.Append(ResultData_);
          IO_.Resume;
        end;
      if not IO_.OwnerFramework.QuietMode then
          IO_.Print('Finish CMD "%s" Bridge Event.', [LCMD_]);
    end
  else
      DoStatus('Loss CMD "%s" Bridge Event..', [LCMD_]);

  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TStream_Event_Bridge.Progress(Sender: TZNet_Progress);
begin

end;

procedure TConsole_Event_Bridge.Init(IO_: TPeerIO; AutoPause_: Boolean);
begin
  if not IO_.ReceiveCommandRuning then
      RaiseInfo('Need in Stream Event.');
  AutoPause := AutoPause_;
  if AutoPause then
      IO_.Pause;
  Framework_ := IO_.OwnerFramework;
  ID_ := IO_.ID;
  LCMD_ := IO_.CurrentCommand;
  OnResultC := nil;
  OnResultM := nil;
  OnResultP := nil;
  if not IO_.OwnerFramework.QuietMode then
      IO_.Print('Create CMD "%s" Bridge Event.', [LCMD_]);
  AutoFree := AutoPause_;
  ProgressInstance := IO_.OwnerFramework.AddProgresss;
  ProgressInstance.OnFree := DoFree;
  ProgressInstance.OnProgress_M := Progress;
end;

procedure TConsole_Event_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TConsole_Event_Bridge.Create(IO_: TPeerIO; AutoPause_: Boolean);
begin
  inherited Create;
  Init(IO_, AutoPause_);
end;

constructor TConsole_Event_Bridge.Create(IO_: TPeerIO);
begin
  inherited Create;
  Init(IO_, True);
end;

destructor TConsole_Event_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

procedure TConsole_Event_Bridge.Pause;
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      IO_.Pause;
    end;
end;

procedure TConsole_Event_Bridge.Play(ResultData_: SystemString);
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      IO_.OutText := IO_.OutText + ResultData_;
      IO_.Resume;
    end;
  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TConsole_Event_Bridge.DoConsoleParamEvent(Sender_: TPeerIO; Param1_: Pointer; Param2_: TObject; SendData_, ResultData_: SystemString);
begin
  DoConsoleEvent(Sender_, ResultData_);
end;

procedure TConsole_Event_Bridge.DoStreamFailed(Sender_: TPeerIO; Param1: Pointer; Param2: TObject; SendData_: SystemString);
begin
  DoConsoleEvent(Sender_, '');
end;

procedure TConsole_Event_Bridge.DoConsoleEvent(Sender_: TPeerIO; ResultData_: SystemString);
var
  IO_: TPeerIO;
begin
  if Framework_.ExistsID(ID_) then
    begin
      IO_ := TPeerIO(Framework_.PeerIO_HashPool[ID_]);
      if Assigned(OnResultC) then
          OnResultC(self, IO_, Sender_, ResultData_)
      else if Assigned(OnResultM) then
          OnResultM(self, IO_, Sender_, ResultData_)
      else if Assigned(OnResultP) then
          OnResultP(self, IO_, Sender_, ResultData_);
      if AutoPause then
        begin
          IO_.OutText := IO_.OutText + ResultData_;
          IO_.Resume;
        end;
      if not IO_.OwnerFramework.QuietMode then
          IO_.Print('Finish CMD "%s" Bridge Event.', [LCMD_]);
    end
  else
      DoStatus('Loss CMD "%s" Bridge Event..', [LCMD_]);

  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TConsole_Event_Bridge.Progress(Sender: TZNet_Progress);
begin

end;

procedure TCustom_CompleteBuffer_Stream_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TCustom_CompleteBuffer_Stream_Bridge.Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge);
begin
  inherited Create;
  if Bridge_ <> nil then
    begin
      Bridge := Bridge_;
      ProgressInstance := Bridge.R_Framework.AddProgresss;
      ProgressInstance.OnFree := DoFree;
      ProgressInstance.OnProgress_M := Progress;
    end
  else
    begin
      Bridge := nil;
      ProgressInstance := nil;
    end;
end;

destructor TCustom_CompleteBuffer_Stream_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

function TCustom_CompleteBuffer_Stream_Bridge.CheckIO: Boolean;
begin
  try
      Result := (Bridge <> nil) and (Bridge.R_Framework <> nil) and (Bridge.R_Framework.ExistsID(Bridge.R_ID));
  except
      Result := False;
  end;
end;

function TCustom_CompleteBuffer_Stream_Bridge.IO: TPeerIO;
begin
  try
      Result := Bridge.R_Framework.PeerIO_HashPool[Bridge.R_ID];
  except
      Result := nil;
  end;
end;

procedure TCustom_CompleteBuffer_Stream_Bridge.Progress(Sender: TZNet_Progress);
begin

end;

procedure TCompleteBuffer_Stream_Event_Bridge.Init(Bridge_: TCommandCompleteBuffer_NoWait_Bridge; AutoPause_: Boolean);
begin
  Bridge := Bridge_;
  LCMD_ := Bridge_.Cmd;
  AutoPause := AutoPause_;
  if AutoPause then
      Bridge.Pause;
  Framework_ := Bridge.R_Framework;
  OnResultC := nil;
  OnResultM := nil;
  OnResultP := nil;
  if not Framework_.QuietMode then
      Framework_.PrintParam('Create Complete Buffer CMD "%s" Bridge Event.', LCMD_);
  AutoFree := AutoPause_;
  ProgressInstance := Framework_.AddProgresss;
  ProgressInstance.OnFree := DoFree;
  ProgressInstance.OnProgress_M := Progress;
end;

procedure TCompleteBuffer_Stream_Event_Bridge.DoFree(Sender: TZNet_Progress);
begin
  ProgressInstance := nil;
end;

constructor TCompleteBuffer_Stream_Event_Bridge.Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge; AutoPause_: Boolean);
begin
  inherited Create;
  Init(Bridge_, AutoPause_);
end;

constructor TCompleteBuffer_Stream_Event_Bridge.Create(Bridge_: TCommandCompleteBuffer_NoWait_Bridge);
begin
  inherited Create;
  Init(Bridge_, True);
end;

destructor TCompleteBuffer_Stream_Event_Bridge.Destroy;
begin
  if ProgressInstance <> nil then
    begin
      ProgressInstance.ResetEvent;
      ProgressInstance.NextProgressDoFree := True;
      ProgressInstance := nil;
    end;
  inherited Destroy;
end;

procedure TCompleteBuffer_Stream_Event_Bridge.Pause;
begin
  Bridge.Pause;
end;

procedure TCompleteBuffer_Stream_Event_Bridge.Play(ResultData_: TDFE);
begin
  Bridge.OutData.SwapInstance(ResultData_);
  Bridge.Resume;
  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TCompleteBuffer_Stream_Event_Bridge.DoStreamEvent(Sender_: TPeerIO; ResultData_: TDFE);
begin
  if Assigned(OnResultC) then
      OnResultC(self, Bridge, Sender_, ResultData_)
  else if Assigned(OnResultM) then
      OnResultM(self, Bridge, Sender_, ResultData_)
  else if Assigned(OnResultP) then
      OnResultP(self, Bridge, Sender_, ResultData_);
  if not Bridge.R_Framework.QuietMode then
      Bridge.R_Framework.PrintParam('Finish CMD "%s" Bridge Event.', LCMD_);
  if AutoPause then
    begin
      Bridge.OutData.SwapInstance(ResultData_);
      Bridge.Resume;
    end;
  if AutoFree then
      DelayFreeObject(1.0, self);
end;

procedure TCompleteBuffer_Stream_Event_Bridge.Progress(Sender: TZNet_Progress);
begin

end;

procedure TP2PVM_CloneConnectEventBridge.DoAsyncConnectState(const State: Boolean);
begin
  if not State then
      DisposeObjectAndNil(NewClient);

  try
    if Assigned(OnResultC) then
        OnResultC(NewClient)
    else if Assigned(OnResultM) then
        OnResultM(NewClient)
    else if Assigned(OnResultP) then
        OnResultP(NewClient);
  except
  end;

  DelayFreeObj(1.0, self);
end;

constructor TP2PVM_CloneConnectEventBridge.Create(Source_: TZNet_WithP2PVM_Client);
begin
  inherited Create;
  Source := Source_;
  NewClient := nil;
  OnResultC := nil;
  OnResultM := nil;
  OnResultP := nil;
end;

destructor TP2PVM_CloneConnectEventBridge.Destroy;
begin
  inherited Destroy;
end;

procedure TDoubleTunnel_IO_ID_List.Add_DT_ID(R, S: Cardinal);
var
  tmp: TDoubleTunnel_IO_ID;
begin
  tmp.R := R;
  tmp.S := S;
  Add(tmp);
end;

constructor TFile_Swap_Space_Pool.Create;
begin
  inherited Create;
  WorkPath := umlCurrentPath;
end;

destructor TFile_Swap_Space_Pool.Destroy;
begin
  inherited Destroy;
end;

procedure TFile_Swap_Space_Pool.DoFree(var data: TFile_Swap_Space_Stream);
begin
  if data = nil then
      exit;
  data.FOwnerSwapSpace := nil;
  data.FPoolPtr := nil;
  DisposeObjectAndNil(data);
end;

function TFile_Swap_Space_Pool.CompareData(const Data_1, Data_2: TFile_Swap_Space_Stream): Boolean;
begin
  Result := Data_1 = Data_2;
end;

class function TFile_Swap_Space_Pool.RunTime_Pool(): TFile_Swap_Space_Pool;
begin
  Result := BigStream_Swap_Space_Pool__;
end;

class function TFile_Swap_Space_Stream.Create_BigStream(stream_: TCore_Stream; OwnerSwapSpace_: TFile_Swap_Space_Pool): TFile_Swap_Space_Stream;
var
  MD5Name: U_String;
  tmpFileName: U_String;
  i: Integer;
begin
  Result := nil;
  if not umlDirectoryExists(OwnerSwapSpace_.WorkPath) then
      exit;
  try
    MD5Name := umlStreamMD5String(stream_);
    tmpFileName := umlCombineFileName(OwnerSwapSpace_.WorkPath, 'ZNet_' + MD5Name.Text + '.~tmp');
    i := 1;
    while umlFileExists(tmpFileName) do
      begin
        tmpFileName := umlCombineFileName(OwnerSwapSpace_.WorkPath, 'ZNet_' + MD5Name.Text + PFormat('(%d).~tmp', [i]));
        inc(i);
      end;
    Result := TFile_Swap_Space_Stream.Create(tmpFileName, fmCreate);
    MD5Name := '';
    tmpFileName := '';
    stream_.Position := 0;
    Result.CopyFrom(stream_, stream_.Size);
    Result.Position := 0;
    Result.FOwnerSwapSpace := OwnerSwapSpace_;
    Result.FPoolPtr := OwnerSwapSpace_.Add(Result);
  except
      Result := nil;
  end;
end;

destructor TFile_Swap_Space_Stream.Destroy;
var
  tmpFileName: U_String;
begin
  try
    tmpFileName := FileName;
    if (FOwnerSwapSpace <> nil) and (FPoolPtr <> nil) then
      begin
        FPoolPtr^.data := nil;
        FOwnerSwapSpace.Remove_P(FPoolPtr);
      end;
    inherited Destroy;
    umlDeleteFile(tmpFileName);
  except
  end;
end;

constructor TCommandStream.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandStream.Destroy;
begin
  inherited Destroy;
end;

function TCommandStream.Execute(Sender: TPeerIO; InData, OutData: TDFE): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData, OutData)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData, OutData)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData, OutData)
    else
        Result := False;
  except
      Result := False;
  end;
end;

function TCommandStream.Execute_Complete_Stream(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
var
  UserData: UInt64;
  InDFE, OutDFE: TDFE;
  m64: TMS64;
  S_IO: TPeerIO;
begin
  InDFE := TDFE.Create;
  OutDFE := TDFE.Create;
  UserData := PUInt64(InData)^;
  InDFE.DecodeFromMemory(GetOffset(InData, 8), DataSize - 8, True);

  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InDFE, OutDFE)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InDFE, OutDFE)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InDFE, OutDFE)
    else
        Result := False;
  except
      Result := False;
  end;

  m64 := TMS64.Create;
  m64.WriteUInt64(UserData);
  OutDFE.FastEncodeTo(m64);

  if Sender.Is_Double_Tunnel and Sender.Is_Recveive_Tunnel then
    begin
      S_IO := Sender.Get_Send_Tunnel_IO;
      if S_IO <> nil then
          S_IO.SendCompleteBuffer(C_Complete_Buffer_Stream_Reponse, m64, True)
      else
          DisposeObject(m64);
    end;

  DisposeObject(InDFE);
  DisposeObject(OutDFE);
end;

constructor TCommandConsole.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandConsole.Destroy;
begin
  inherited Destroy;
end;

function TCommandConsole.Execute(Sender: TPeerIO; InData: SystemString; var OutData: SystemString): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData, OutData)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData, OutData)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData, OutData)
    else
        Result := False;
  except
      Result := False;
  end;
end;

constructor TCommandStreamNotify.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandStreamNotify.Destroy;
begin
  inherited Destroy;
end;

function TCommandStreamNotify.Execute(Sender: TPeerIO; InData: TDFE): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData)
    else
        Result := False;
  except
      Result := False;
  end;
end;

constructor TCommandConsoleNotify.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandConsoleNotify.Destroy;
begin
  inherited Destroy;
end;

function TCommandConsoleNotify.Execute(Sender: TPeerIO; InData: SystemString): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData)
    else
        Result := False;
  except
      Result := False;
  end;
end;

constructor TCommandBigStream.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandBigStream.Destroy;
begin
  inherited Destroy;
end;

function TCommandBigStream.Execute(Sender: TPeerIO; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData, BigStreamTotal, BigStreamCompleteSize)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData, BigStreamTotal, BigStreamCompleteSize)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData, BigStreamTotal, BigStreamCompleteSize)
    else
        Result := False;
  except
      Result := False;
  end;
end;

constructor TCommandCompleteBuffer.Create;
begin
  inherited Create;

  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandCompleteBuffer.Destroy;
begin
  inherited Destroy;
end;

function TCommandCompleteBuffer.Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
begin
  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Sender, InData, DataSize)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Sender, InData, DataSize)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Sender, InData, DataSize)
    else
        Result := False;
  except
      Result := False;
  end;
end;

procedure TCommandCompleteBuffer_StreamNotify_Thread.Do_Run_Decrypt_Thread(thSender: TCompute);
begin
  if Framework.ExistsID(ID) then
    begin
      with Framework.PostExecute.PostExecute(False) do
        begin
          DataEng.DecodeFrom(buff, True);
          Auto_Free_Pool.Add(self);
          OnExecute_M := Do_Post_Run;
          Ready;
        end;
    end
  else
    begin
      DelayFreeObj(1.0, self);
    end;
  AtomDec(Owner.FDecript_Activted_Thread_Num);
end;

procedure TCommandCompleteBuffer_StreamNotify_Thread.Do_Post_Run(Sender: TN_Post_Execute);
var
  IO_: TPeerIO;
begin
  IO_ := Framework.IOPool[ID];
  if IO_ <> nil then
    begin
      try
        if Assigned(Owner.FOnExecute_C) then
            Owner.FOnExecute_C(IO_, Sender.DataEng)
        else if Assigned(Owner.FOnExecute_M) then
            Owner.FOnExecute_M(IO_, Sender.DataEng)
        else if Assigned(Owner.FOnExecute_P) then
            Owner.FOnExecute_P(IO_, Sender.DataEng);
      except
      end;
    end;
end;

constructor TCommandCompleteBuffer_StreamNotify_Thread.Create;
begin
  inherited Create;
  Owner := nil;
  Framework := nil;
  ID := 0;
  buff := nil;
end;

destructor TCommandCompleteBuffer_StreamNotify_Thread.Destroy;
begin
  DisposeObjectAndNil(buff);
  inherited Destroy;
end;

constructor TCommandCompleteBuffer_StreamNotify.Create;
begin
  inherited Create;
  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
  FSync_Decrypt := True;
  FDecript_Activted_Thread_Num := 0;
end;

destructor TCommandCompleteBuffer_StreamNotify.Destroy;
begin
  while FDecript_Activted_Thread_Num > 0 do
      TCompute.Sleep(1);
  inherited Destroy;
end;

function TCommandCompleteBuffer_StreamNotify.Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
var
  tmp: TDFE;
  Bridge: TCommandCompleteBuffer_StreamNotify_Thread;
begin
  if FSync_Decrypt then
    begin
      tmp := TDFE.Create;
      tmp.DecodeFromMemory(InData, DataSize);

      Result := True;
      try
        if Assigned(FOnExecute_C) then
            FOnExecute_C(Sender, tmp)
        else if Assigned(FOnExecute_M) then
            FOnExecute_M(Sender, tmp)
        else if Assigned(FOnExecute_P) then
            FOnExecute_P(Sender, tmp)
        else
            Result := False;
      except
          Result := False;
      end;

      DisposeObject(tmp);
    end
  else
    begin
      AtomInc(FDecript_Activted_Thread_Num);
      Bridge := TCommandCompleteBuffer_StreamNotify_Thread.Create;
      Bridge.Owner := self;
      Bridge.Framework := Sender.OwnerFramework;
      Bridge.ID := Sender.ID;
      Bridge.buff := Sender.CompleteBuffer_Current_Trigger.Swap_To_New_Instance;
      TCompute.RunM(nil, Bridge, Bridge.Do_Run_Decrypt_Thread);
      Result := True;
    end;
end;

procedure TCommandCompleteBuffer_NoWait_Stream_Data.Init;
begin
  ID := 0;
  OnStreamM := nil;
  OnStreamP := nil;
end;

procedure TCommandCompleteBuffer_NoWait_Stream_Execute_Thread.Do_Execute_Thread(thSender: TCompute);
var
  UserData: UInt64;
  InDFE, OutDFE: TDFE;
  m64: TMS64;
begin
  InDFE := TDFE.Create;
  OutDFE := TDFE.Create;
  try
    UserData := PUInt64(buff.PosAsPtr(0))^;
    InDFE.DecodeFromMemory(buff.PosAsPtr(8), buff.Size - 8, True);

    try
      if Assigned(Owner.FOnExecute_C) then
          Owner.FOnExecute_C(R_Framework.PeerIO_HashPool[R_ID], InDFE, OutDFE)
      else if Assigned(Owner.FOnExecute_M) then
          Owner.FOnExecute_M(R_Framework.PeerIO_HashPool[R_ID], InDFE, OutDFE)
      else if Assigned(Owner.FOnExecute_P) then
          Owner.FOnExecute_P(R_Framework.PeerIO_HashPool[R_ID], InDFE, OutDFE)
    except
    end;

    m64 := TMS64.Create;
    m64.WriteUInt64(UserData);
    OutDFE.FastEncodeTo(m64);

    if S_Framework is TZNet_Server then
        TZNet_Server(S_Framework).SendCompleteBuffer(S_ID, C_Complete_Buffer_Stream_Reponse, m64, True)
    else if S_Framework is TZNet_Client then
        TZNet_Client(S_Framework).SendCompleteBuffer(C_Complete_Buffer_Stream_Reponse, m64, True);
  except
  end;
  DisposeObject(InDFE);
  DisposeObject(OutDFE);

  DelayFreeObj(1.0, self);
  AtomDec(Owner.FExecute_Activted_Thread_Num);
end;

constructor TCommandCompleteBuffer_NoWait_Stream_Execute_Thread.Create;
begin
  inherited Create;
  Owner := nil;
  R_Framework := nil;
  R_ID := 0;
  S_Framework := nil;
  S_ID := 0;
  buff := nil;
end;

destructor TCommandCompleteBuffer_NoWait_Stream_Execute_Thread.Destroy;
begin
  DisposeObjectAndNil(buff);
  inherited Destroy;
end;

constructor TCommandCompleteBuffer_NoWait_Stream.Create;
begin
  inherited Create;
  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
  FExecute_In_Thread := False;
  FExecute_Activted_Thread_Num := 0;
end;

destructor TCommandCompleteBuffer_NoWait_Stream.Destroy;
begin
  while FExecute_Activted_Thread_Num > 0 do
      TCompute.Sleep(1);
  inherited Destroy;
end;

function TCommandCompleteBuffer_NoWait_Stream.Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
var
  th: TCommandCompleteBuffer_NoWait_Stream_Execute_Thread;
  UserData: UInt64;
  InDFE, OutDFE: TDFE;
  m64: TMS64;
  S_IO: TPeerIO;
begin
  if FExecute_In_Thread then
    begin
      Result := False;
      if Sender.Is_Double_Tunnel and Sender.Is_Recveive_Tunnel then
        begin
          th := TCommandCompleteBuffer_NoWait_Stream_Execute_Thread.Create;
          th.Owner := self;
          th.R_Framework := Sender.OwnerFramework;
          th.R_ID := Sender.ID;
          if Sender.Get_Send_Tunnel(th.S_Framework, th.S_ID) then
            begin
              th.buff := Sender.CompleteBuffer_Current_Trigger.Swap_To_New_Instance;
              AtomInc(FExecute_Activted_Thread_Num);
              TCompute.RunM(nil, th, th.Do_Execute_Thread);
              Result := True;
            end
          else
            begin
              DisposeObject(th);
            end;
        end;
    end
  else
    begin
      InDFE := TDFE.Create;
      OutDFE := TDFE.Create;
      UserData := PUInt64(InData)^;
      InDFE.DecodeFromMemory(GetOffset(InData, 8), DataSize - 8, True);

      Result := True;
      try
        if Assigned(FOnExecute_C) then
            FOnExecute_C(Sender, InDFE, OutDFE)
        else if Assigned(FOnExecute_M) then
            FOnExecute_M(Sender, InDFE, OutDFE)
        else if Assigned(FOnExecute_P) then
            FOnExecute_P(Sender, InDFE, OutDFE)
        else
            Result := False;
      except
          Result := False;
      end;

      m64 := TMS64.Create;
      m64.WriteUInt64(UserData);
      OutDFE.FastEncodeTo(m64);

      if Sender.Is_Double_Tunnel and Sender.Is_Recveive_Tunnel then
        begin
          S_IO := Sender.Get_Send_Tunnel_IO;
          if S_IO <> nil then
              S_IO.SendCompleteBuffer(C_Complete_Buffer_Stream_Reponse, m64, True)
          else
              DisposeObject(m64);
        end;

      DisposeObject(InDFE);
      DisposeObject(OutDFE);
    end;
end;

constructor TCommandCompleteBuffer_NoWait_Bridge_Stream.Create;
begin
  inherited Create;
  FOnExecute_C := nil;
  FOnExecute_M := nil;
  FOnExecute_P := nil;
end;

destructor TCommandCompleteBuffer_NoWait_Bridge_Stream.Destroy;
begin
  inherited Destroy;
end;

function TCommandCompleteBuffer_NoWait_Bridge_Stream.Execute(Sender: TPeerIO; InData: PByte; DataSize: NativeInt): Boolean;
var
  Bridge: TCommandCompleteBuffer_NoWait_Bridge;
begin
  Result := False;

  Bridge := TCommandCompleteBuffer_NoWait_Bridge.Create;
  Bridge.Owner := self;
  Bridge.Cmd := Sender.CompleteBufferCmd;
  Bridge.R_Framework := Sender.OwnerFramework;
  Bridge.R_ID := Sender.ID;
  if not Sender.Get_Send_Tunnel(Bridge.S_Framework, Bridge.S_ID) then
    begin
      DisposeObject(Bridge);
      exit;
    end;

  Bridge.UserData := PUInt64(InData)^;
  Bridge.InData.DecodeFromMemory(GetOffset(InData, 8), DataSize - 8, True);

  Result := True;
  try
    if Assigned(FOnExecute_C) then
        FOnExecute_C(Bridge, Bridge.InData, Bridge.OutData)
    else if Assigned(FOnExecute_M) then
        FOnExecute_M(Bridge, Bridge.InData, Bridge.OutData)
    else if Assigned(FOnExecute_P) then
        FOnExecute_P(Bridge, Bridge.InData, Bridge.OutData)
    else
        Result := False;
  except
      Result := False;
  end;

  if not Bridge.Pause_Result_Send then
      Bridge.Resume;
end;

constructor TCommandCompleteBuffer_NoWait_Bridge.Create;
begin
  inherited Create;
  Pause_Result_Send := False;
  Owner := nil;
  R_Framework := nil;
  R_ID := 0;
  S_Framework := nil;
  S_ID := 0;
  UserData := 0;
  InData := TDFE.Create;
  OutData := TDFE.Create;
end;

destructor TCommandCompleteBuffer_NoWait_Bridge.Destroy;
begin
  DisposeObject(InData);
  DisposeObject(OutData);
  inherited Destroy;
end;

function TCommandCompleteBuffer_NoWait_Bridge.R_IO: TPeerIO;
begin
  Result := R_Framework.PeerIO_HashPool[R_ID];
end;

function TCommandCompleteBuffer_NoWait_Bridge.S_IO: TPeerIO;
begin
  Result := S_Framework.PeerIO_HashPool[S_ID];
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.Pause;
begin
  Pause_Result_Send := True;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.PauseResultSend;
begin
  Pause;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.BreakResultSend;
begin
  Pause;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.SkipResultSend;
begin
  Pause;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.NoResultSend;
begin
  Pause;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.StopResultSend;
begin
  Pause;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.Resume;
var
  m64: TMS64;
begin
  m64 := TMS64.Create;
  m64.WriteUInt64(UserData);
  OutData.FastEncodeTo(m64);

  if S_Framework is TZNet_Server then
      TZNet_Server(S_Framework).SendCompleteBuffer(S_ID, C_Complete_Buffer_Stream_Reponse, m64, True)
  else if S_Framework is TZNet_Client then
      TZNet_Client(S_Framework).SendCompleteBuffer(C_Complete_Buffer_Stream_Reponse, m64, True);

  DelayFreeObj(1.0, self);
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.ContinueResultSend;
begin
  Resume;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.Continue_Send_Result;
begin
  Resume;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.ResumeResultSend;
begin
  Resume;
end;

procedure TCommandCompleteBuffer_NoWait_Bridge.NowResultSend;
begin
  Resume;
end;

procedure TBigStreamBatchPostData.Init;
begin
  Source := nil;
  CompletedBackcallPtr := 0;
  RemoteMD5 := NullMD5;
  SourceMD5 := NullMD5;
  index := -1;
  DBStorePos := 0;
end;

procedure TBigStreamBatchPostData.Encode(d: TDFE);
begin
  d.WriteMD5(RemoteMD5);
  d.WriteMD5(SourceMD5);
  d.WriteInteger(index);
  d.WriteInt64(DBStorePos);
end;

procedure TBigStreamBatchPostData.Decode(d: TDFE);
begin
  Source := nil;
  CompletedBackcallPtr := 0;
  RemoteMD5 := d.Reader.ReadMD5;
  SourceMD5 := d.Reader.ReadMD5;
  index := d.Reader.ReadInteger;
  DBStorePos := d.Reader.ReadInt64;
end;

function TBigStreamBatch.GetItems(const index: Integer): PBigStreamBatchPostData;
begin
  Result := FList[index];
end;

constructor TBigStreamBatch.Create(Owner_: TPeerIO);
begin
  inherited Create;
  FOwner := Owner_;
  FList := TBigStreamBatchPostData_List.Create;
end;

destructor TBigStreamBatch.Destroy;
begin
  Clear;
  DisposeObject(FList);
  inherited Destroy;
end;

procedure TBigStreamBatch.Clear;
var
  i: Integer;
  p: PBigStreamBatchPostData;
begin
  for i := 0 to FList.Count - 1 do
    begin
      p := PBigStreamBatchPostData(FList[i]);
      DisposeObject(p^.Source);
      Dispose(p);
    end;

  FList.Clear;
end;

function TBigStreamBatch.Count: Integer;
begin
  Result := FList.Count;
end;

function TBigStreamBatch.NewPostData: PBigStreamBatchPostData;
begin
  New(Result);
  Result^.Init;
  Result^.Source := TMS64.Create;
  Result^.index := FList.Add(Result);
end;

function TBigStreamBatch.First: PBigStreamBatchPostData;
begin
  Result := FList[0];
end;

function TBigStreamBatch.Last: PBigStreamBatchPostData;
begin
  Result := FList[FList.Count - 1];
end;

procedure TBigStreamBatch.DeleteLast;
begin
  if FList.Count > 0 then
      Delete(FList.Count - 1);
end;

procedure TBigStreamBatch.Delete(const index: Integer);
var
  p: PBigStreamBatchPostData;
  i: Integer;
begin
  p := FList[index];
  DisposeObject(p^.Source);
  Dispose(p);
  FList.Delete(index);

  for i := 0 to FList.Count - 1 do
    begin
      p := PBigStreamBatchPostData(FList[i]);
      p^.index := i;
    end;
end;

procedure TPeer_IO_User_Define.DelayFreeOnBusy;
begin
  FOwner := nil;
  while FBusy or (FBusyNum > 0) do
      TCompute.Sleep(100);

  DelayFreeObj(1.0, self);
end;

constructor TPeer_IO_User_Define.Create(Owner_: TPeerIO);
begin
  inherited Create;
  FOwner := Owner_;
  FWorkPlatform := TExecutePlatform.epUnknow;
  FBigStreamBatch := TBigStreamBatch.Create(Owner);
  FBusy := False;
end;

destructor TPeer_IO_User_Define.Destroy;
begin
  DisposeObject(FBigStreamBatch);
  inherited Destroy;
end;

procedure TPeer_IO_User_Define.Progress;
begin
end;

function TPeer_IO_User_Define.BusyNum: PInteger;
begin
  Result := @FBusyNum;
end;

procedure TPeer_IO_User_Special.DelayFreeOnBusy;
begin
  FOwner := nil;
  while FBusy or (FBusyNum > 0) do
      TCompute.Sleep(100);
  DelayFreeObj(1.0, self);
end;

constructor TPeer_IO_User_Special.Create(Owner_: TPeerIO);
begin
  inherited Create;
  FOwner := Owner_;
  FBusy := False;
end;

destructor TPeer_IO_User_Special.Destroy;
begin
  inherited Destroy;
end;

procedure TPeer_IO_User_Special.Progress;
begin
end;

function TPeer_IO_User_Special.BusyNum: PInteger;
begin
  Result := @FBusyNum;
end;

procedure TPhysics_Fragment_Pool.DoFree(var data: TMem64);
begin
  DisposeObjectAndNil(data);
end;

function TPeerIO.Connected: Boolean;
begin
  Result := False;
end;

procedure TPeerIO.Disconnect;
begin
  CheckAndTriggerFailedWaitResult();
end;

procedure TPeerIO.Write_IO_Buffer(const buff: PByte; const Size: NativeInt);
begin
end;

procedure TPeerIO.WriteBufferOpen;
begin
end;

procedure TPeerIO.WriteBufferFlush;
begin
end;

procedure TPeerIO.WriteBufferClose;
begin
end;

function TPeerIO.GetPeerIP: SystemString;
begin
  Result := 'offline';
end;

function TPeerIO.WriteBuffer_is_NULL: Boolean;
begin
  Result := True;
end;

function TPeerIO.WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean;
begin
  WriteBuffer_Queue_Num := 0;
  WriteBuffer_Size := 0;
  Result := False;
end;

procedure TPeerIO.InitSequencePacketModel(const hashSize, MemoryDelta: Integer);
begin
  FSequencePacketActivted := OwnerFramework.FSequencePacketActivted;
  FSequencePacketSignal := True;

  SequenceNumberOnSendCounter := 0;
  SequenceNumberOnReceivedCounter := 0;

  SendingSequencePacketHistory := TSequence_Packet_Hash_Pool.Create(hashSize, nil);
  SendingSequencePacketHistory.OnFree := Send_Free_OnPtr;
  SendingSequencePacketHistory.OnAdd := Send_Add_OnPtr;

  SequencePacketReceivedPool := TSequence_Packet_Hash_Pool.Create(hashSize, nil);
  SequencePacketReceivedPool.OnFree := Received_Free_OnPtr;
  SequencePacketReceivedPool.OnAdd := Received_Add_OnPtr;

  SendingSequencePacketHistoryMemory := 0;
  SequencePacketReceivedPoolMemory := 0;

  IOSendBuffer := TMS64.CustomCreate(MemoryDelta);
  SequencePacketSendBuffer := TMS64.CustomCreate(MemoryDelta);
  SequencePacketReceivedBuffer := TMS64.CustomCreate(MemoryDelta);

  FSequencePacketMTU := ZNet_Def_SequencePacketMTU;

  FSequencePacketLimitPhysicsMemory := 0;
  SequencePacketCloseDone := False;

  SequencePacketVerifyTick := GetTimeTick;
end;

procedure TPeerIO.FreeSequencePacketModel;
begin
  DisposeObject(SendingSequencePacketHistory);
  SendingSequencePacketHistory := nil;

  DisposeObject(SequencePacketReceivedPool);
  SequencePacketReceivedPool := nil;

  DisposeObject(IOSendBuffer);
  IOSendBuffer := nil;

  DisposeObject(SequencePacketSendBuffer);
  SequencePacketSendBuffer := nil;

  DisposeObject(SequencePacketReceivedBuffer);
  SequencePacketReceivedBuffer := nil;
end;

procedure TPeerIO.ResetSequencePacketBuffer;
begin
  IOSendBuffer.Clear;
  SequencePacketSendBuffer.Clear;
  SequencePacketReceivedBuffer.Clear;
end;

procedure TPeerIO.ProcessSequencePacketModel;
var
  p: PSequencePacket;
  siz: NativeInt;
begin
  if not IsSequencePacketModel then
      exit;

  if SequencePacketCloseDone then
      exit;

  if FDisable_Progress then
      exit;

  if (FSequencePacketLimitPhysicsMemory <> 0) and
    (SendingSequencePacketHistoryMemory + SequencePacketReceivedPoolMemory > FSequencePacketLimitPhysicsMemory) then
    begin
      PrintError('memory exceeds security limit for Sequence Packet signal buffer.');
      SequencePacketCloseDone := True;
      DelayClose;
      exit;
    end;

  if (FSequencePacketSignal)
    and (SendingSequencePacketHistory.Count > 0)
    and (WriteBuffer_is_NULL)
    and (GetTimeTick - SequencePacketVerifyTick > 1000) then
    begin
      IOSendBuffer.Position := IOSendBuffer.Size;

      siz := 0;
      with SendingSequencePacketHistory.Repeat_ do
        begin
          repeat
            p := Queue^.data^.data.Second;
            if (GetTimeTick - p^.tick > 3000) then
              begin
                WriteSequencePacket(p);
                p^.tick := GetTimeTick;
                inc(siz, p^.Size);
              end;
          until (not Next) or (siz > 1024 * 1024);
        end;

      SequencePacketVerifyTick := GetTimeTick;
    end;

  FlushIOSendBuffer;
end;

function TPeerIO.GetSequencePacketState: SystemString;
begin
  Result := PFormat('History: %s (block: %d) Received Pool: %s (block: %d) Total Memory: %s',
    [umlSizeToStr(SendingSequencePacketHistoryMemory).Text,
      SendingSequencePacketHistory.Count,
      umlSizeToStr(SequencePacketReceivedPoolMemory).Text,
      SequencePacketReceivedPool.Count,
      umlSizeToStr(SendingSequencePacketHistoryMemory + SequencePacketReceivedPoolMemory).Text
      ]);
end;

function TPeerIO.GetSequencePacketUsagePhysicsMemory: Int64;
begin
  Result := SendingSequencePacketHistoryMemory + SequencePacketReceivedPoolMemory;
end;

function TPeerIO.ComputeSequencePacketHash(const p: PByte; const Count: nativeUInt): TMD5;
begin
  Result := umlMD5(p, Count);
end;

function TPeerIO.IsSequencePacketModel: Boolean;
begin
  Result := (FSequencePacketActivted) and (OwnerFramework.Protocol = TCommunicationProtocol.cpZServer);
end;

procedure TPeerIO.FlushIOSendBuffer;
begin
  if (IOSendBuffer.Size > 0) then
    begin
      WriteBufferOpen;
      On_Internal_Send_Byte_Buffer(self, IOSendBuffer.Memory, IOSendBuffer.Size);
      IOSendBuffer.Clear;
      WriteBufferFlush;
      WriteBufferClose;
    end;
end;

procedure TPeerIO.SendSequencePacketBegin;
begin
  SequencePacketSendBuffer.Clear;
end;

procedure TPeerIO.SendSequencePacket(const buff: PByte; siz: NativeInt);
begin
  SequencePacketSendBuffer.WritePtr(buff, siz);
end;

procedure TPeerIO.SendSequencePacketEnd;
var
  pBuff: PByte;
  p: PSequencePacket;
  siz: NativeInt;
  FlushBuffSize: Word;
begin
  if SequencePacketSendBuffer.Size <= 0 then
      exit;

  if not IsSequencePacketModel then
    begin
      WriteBufferOpen;
      On_Internal_Send_Byte_Buffer(self, SequencePacketSendBuffer.Memory, SequencePacketSendBuffer.Size);
      SequencePacketSendBuffer.Clear;
      WriteBufferFlush;
      WriteBufferClose;
      exit;
    end;

  FlushBuffSize := umlMax(FSequencePacketMTU, 1024) - (ZNet_Def_Sequence_Packet_HeadSize + 1);

  siz := SequencePacketSendBuffer.Size;
  pBuff := SequencePacketSendBuffer.Memory;

  IOSendBuffer.Position := IOSendBuffer.Size;

  { fragment build to sending }
  while siz > FlushBuffSize do
    begin
      New(p);
      p^.SequenceNumber := SequenceNumberOnSendCounter;
      p^.data := TMS64.Create;
      p^.data.Size := FlushBuffSize;
      p^.Size := p^.data.Size;
      CopyPtr(pBuff, p^.data.Memory, p^.data.Size);
      p^.hash := ComputeSequencePacketHash(p^.data.Memory, p^.data.Size);
      p^.tick := GetTimeTick;

      inc(pBuff, FlushBuffSize);
      dec(siz, FlushBuffSize);

      WriteSequencePacket(p);
      inc(SequenceNumberOnSendCounter);

      if FSequencePacketSignal then
          SendingSequencePacketHistory.Add(p^.SequenceNumber, p, False)
      else
        begin
          DisposeObject(p^.data);
          Dispose(p);
        end;
    end;

  if siz > 0 then
    begin
      New(p);
      p^.SequenceNumber := SequenceNumberOnSendCounter;
      p^.data := TMS64.Create;
      p^.data.Size := siz;
      p^.Size := p^.data.Size;
      CopyPtr(pBuff, p^.data.Memory, p^.data.Size);
      p^.hash := ComputeSequencePacketHash(p^.data.Memory, p^.data.Size);
      p^.tick := GetTimeTick;

      WriteSequencePacket(p);
      inc(SequenceNumberOnSendCounter);

      if FSequencePacketSignal then
          SendingSequencePacketHistory.Add(p^.SequenceNumber, p, False)
      else
        begin
          DisposeObject(p^.data);
          Dispose(p);
        end;
    end;
  SequencePacketSendBuffer.Clear;

  FlushIOSendBuffer;
end;

procedure TPeerIO.SendSequencePacketKeepAlive(p: Pointer; siz: Word);
begin
  if FSequencePacketSignal and IsSequencePacketModel then
    begin
      IOSendBuffer.Position := IOSendBuffer.Size;

      IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_KeepAlive);
      IOSendBuffer.WriteUInt16(siz);
      if siz > 0 then
          IOSendBuffer.WritePtr(p, siz);
    end;
end;

procedure TPeerIO.DoSequencePacketEchoKeepAlive(p: Pointer; siz: Word);
begin
end;

procedure TPeerIO.WriteSequencePacket(p: PSequencePacket);
begin
  if FSequencePacketSignal then
      IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_Packet)
  else
      IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_QuietPacket);
  IOSendBuffer.WriteUInt16(p^.Size);
  IOSendBuffer.WriteUInt32(p^.SequenceNumber);
  IOSendBuffer.WriteMD5(p^.hash);
  IOSendBuffer.WritePtr(p^.data.Memory, p^.data.Size);
end;

procedure TPeerIO.ResendSequencePacket(SequenceNumber: Cardinal);
var
  p: PSequencePacket;
begin
  p := SendingSequencePacketHistory[SequenceNumber];
  if p <> nil then
    begin
      WriteSequencePacket(p);
      p^.tick := GetTimeTick();
    end
  else
      PrintError('resend error, invalid Sequence Packet ' + IntToHex(SequenceNumber, 8));
end;

function TPeerIO.FillSequencePacketTo(const buff: Pointer; siz: Int64; ExtractDest: TMS64): Boolean;
var
  ErrorState: Boolean;
  p: PSequencePacket;
  head: Byte;
  echoSiz: Word;
  ResendNumber, DoneNumber: Cardinal;
  fastSwap, n: TMS64;
  hashMatched: Boolean;
begin
  Result := True;

  if not IsSequencePacketModel then
    begin
      ExtractDest.Position := ExtractDest.Size;
      if (buff <> nil) and (siz > 0) then
          ExtractDest.WritePtr(buff, siz);
      exit;
    end;

{$IFDEF OverflowCheck}{$Q-}{$ENDIF}
{$IFDEF RangeCheck}{$R-}{$ENDIF}
  SequencePacketReceivedBuffer.Position := SequencePacketReceivedBuffer.Size;
  if (buff <> nil) and (siz > 0) then
      SequencePacketReceivedBuffer.WritePtr(buff, siz);

  fastSwap := TMS64.Create;
  fastSwap.SetPointerWithProtectedMode(SequencePacketReceivedBuffer.Memory, SequencePacketReceivedBuffer.Size);

  IOSendBuffer.Position := IOSendBuffer.Size;
  ExtractDest.Position := ExtractDest.Size;

  ErrorState := False;
  New(p);

  while fastSwap.Size > 0 do
    begin
      if fastSwap.Position + 1 > fastSwap.Size then
          Break;

      head := fastSwap.ReadUInt8;

      if head = ZNet_Def_Sequence_KeepAlive then
        begin
          if fastSwap.Position + 2 > fastSwap.Size then
              Break;
          echoSiz := fastSwap.ReadUInt16;
          if fastSwap.Position + echoSiz > fastSwap.Size then
              Break;

          if FSequencePacketSignal then
            begin
              IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_EchoKeepAlive);
              IOSendBuffer.WriteUInt16(echoSiz);
              if echoSiz > 0 then
                  IOSendBuffer.CopyFrom(fastSwap, echoSiz);
            end
          else
              fastSwap.Position := fastSwap.Position + echoSiz;
        end
      else if head = ZNet_Def_Sequence_EchoKeepAlive then
        begin
          if fastSwap.Position + 2 > fastSwap.Size then
              Break;
          echoSiz := fastSwap.ReadUInt16;
          if fastSwap.Position + echoSiz > fastSwap.Size then
              Break;

          DoSequencePacketEchoKeepAlive(fastSwap.PositionAsPtr(), echoSiz);
          if echoSiz > 0 then
              fastSwap.Position := fastSwap.Position + echoSiz;
        end
      else if head = ZNet_Def_Sequence_RequestResend then
        begin
          if fastSwap.Position + 4 > fastSwap.Size then
              Break;
          ResendNumber := fastSwap.ReadUInt32;
          { resend Packet }
          if FSequencePacketSignal then
              ResendSequencePacket(ResendNumber);
          AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketRequestResend]);
        end
      else if head = ZNet_Def_Sequence_EchoPacket then
        begin
          if fastSwap.Position + 4 > fastSwap.Size then
              Break;
          DoneNumber := fastSwap.ReadUInt32;
          { recycle Packet }
          SendingSequencePacketHistory.Delete(DoneNumber);
          AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketEcho]);
        end
      else if head in [ZNet_Def_Sequence_QuietPacket, ZNet_Def_Sequence_Packet] then
        begin
          if fastSwap.Position + ZNet_Def_Sequence_Packet_HeadSize > fastSwap.Size then
              Break;

          p^.Size := fastSwap.ReadUInt16;
          p^.SequenceNumber := fastSwap.ReadUInt32;
          p^.hash := fastSwap.ReadMD5;

          if fastSwap.Position + p^.Size > fastSwap.Size then
              Break;

          hashMatched := umlMD5Compare(p^.hash, NULL_MD5) or
            umlMD5Compare(p^.hash, ComputeSequencePacketHash(fastSwap.PositionAsPtr(), p^.Size));

          if hashMatched then
            begin
              if (FSequencePacketSignal) and (head = ZNet_Def_Sequence_Packet) then
                begin
                  IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_EchoPacket);
                  IOSendBuffer.WriteUInt32(p^.SequenceNumber);
                end;

              AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketReceived]);

              if p^.SequenceNumber = SequenceNumberOnReceivedCounter then
                begin
                  ExtractDest.CopyFrom(fastSwap, p^.Size);
                  SequencePacketReceivedPool.Delete(p^.SequenceNumber);
                  inc(SequenceNumberOnReceivedCounter);
                  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketMatched]);
                end
              else if (FSequencePacketSignal) and ((p^.SequenceNumber > SequenceNumberOnReceivedCounter) or
                  (Cardinal(p^.SequenceNumber + Cardinal($7FFFFFFF)) > Cardinal(SequenceNumberOnReceivedCounter + Cardinal($7FFFFFFF)))) then
                begin
                  p^.data := TMS64.Create;
                  p^.data.CopyFrom(fastSwap, p^.Size);
                  p^.tick := GetTimeTick;
                  SequencePacketReceivedPool.Add(p^.SequenceNumber, p, True);

                  New(p);
                  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketPlan]);
                end
              else
                begin
                  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketDiscard]);
                  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketDiscardSize], p^.Size);
                  fastSwap.Position := fastSwap.Position + p^.Size;
                end;
            end
          else
            begin
              fastSwap.Position := fastSwap.Position + p^.Size;
              if FSequencePacketSignal then
                begin
                  IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_RequestResend);
                  IOSendBuffer.WriteUInt32(p^.SequenceNumber);
                end;
            end;
        end
      else
        begin
          if FRemoteExecutedForConnectInit then // fixed safe check, by.qq600585
            begin
              PrintError('sequence packet: error head');
              DoStatus('error buffer: ', buff, umlMin(siz, 200), 60);
            end;
          ErrorState := True;
          Break;
        end;

      n := TMS64.Create;
      n.SetPointerWithProtectedMode(fastSwap.PositionAsPtr(), fastSwap.Size - fastSwap.Position);
      DisposeObject(fastSwap);
      fastSwap := n;
    end;
  Dispose(p);

  if ErrorState then
    begin
      DisposeObject(fastSwap);
      Result := False;
      exit;
    end;

  { strip buffer }
  n := TMS64.CustomCreate(SequencePacketReceivedBuffer.Delta);
  if fastSwap.Size > 0 then
    begin
      n.WritePtr(fastSwap.Memory, fastSwap.Size);
      n.Position := 0;
    end;
  DisposeObject(SequencePacketReceivedBuffer);
  SequencePacketReceivedBuffer := n;
  DisposeObject(fastSwap);

  { extract buffer }
  while SequencePacketReceivedPool.Count > 0 do
    begin
      p := SequencePacketReceivedPool[SequenceNumberOnReceivedCounter];
      if p = nil then
        begin
          if FSequencePacketSignal then
            begin
              IOSendBuffer.WriteUInt8(ZNet_Def_Sequence_RequestResend);
              IOSendBuffer.WriteUInt32(SequenceNumberOnReceivedCounter);
            end;
          Break;
        end;
      ExtractDest.WritePtr(p^.data.Memory, p^.Size);
      SequencePacketReceivedPool.Delete(SequenceNumberOnReceivedCounter);
      inc(SequenceNumberOnReceivedCounter);
    end;
{$IFDEF OverflowCheck}{$Q+}{$ENDIF}
{$IFDEF RangeCheck}{$R+}{$ENDIF}
end;

procedure TPeerIO.Send_Free_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket);
begin
  AtomDec(OwnerFramework.Statistics[TStatisticsType.stSequencePacketMemoryOnSending], p^.Size);
  dec(SendingSequencePacketHistoryMemory, p^.Size);
  if SendingSequencePacketHistoryMemory < 0 then
      PrintError('SendingSequencePacketHistoryMemory overflow');
  DisposeObject(p^.data);
  Dispose(p);
end;

procedure TPeerIO.Send_Add_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket);
begin
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketMemoryOnSending], p^.Size);
  inc(SendingSequencePacketHistoryMemory, p^.Size);
  if SendingSequencePacketHistoryMemory < 0 then
      PrintError('SendingSequencePacketHistoryMemory overflow');
end;

procedure TPeerIO.Received_Free_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket);
begin
  AtomDec(OwnerFramework.Statistics[TStatisticsType.stSequencePacketMemoryOnReceived], p^.Size);
  dec(SequencePacketReceivedPoolMemory, p^.Size);
  if SequencePacketReceivedPoolMemory < 0 then
      PrintError('SequencePacketReceivedPoolMemory overflow');

  DisposeObject(p^.data);
  Dispose(p);
end;

procedure TPeerIO.Received_Add_OnPtr(var Sequence_ID_: Cardinal; var p: PSequencePacket);
begin
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stSequencePacketMemoryOnReceived], p^.Size);
  inc(SequencePacketReceivedPoolMemory, p^.Size);
  if SequencePacketReceivedPoolMemory < 0 then
      PrintError('SequencePacketReceivedPoolMemory overflow');
end;

procedure TPeerIO.P2PVMAuthSuccess(Sender: TZNet_P2PVM);
begin
  with OwnerFramework.ProgressPost.PostExecuteM(False, 0, OwnerFramework.VMAuthSuccessDelayExecute) do
    begin
      Data3 := ID;
      Ready();
    end;
end;

function TPeerIO.GetUserVariants: THashVariantList;
begin
  if FUserVariants = nil then
      FUserVariants := THashVariantList.Create;

  Result := FUserVariants;
end;

function TPeerIO.GetUserObjects: THashObjectList;
begin
  if FUserObjects = nil then
      FUserObjects := THashObjectList.Create(False);

  Result := FUserObjects;
end;

function TPeerIO.GetUserAutoFreeObjects: THashObjectList;
begin
  if FUserAutoFreeObjects = nil then
      FUserAutoFreeObjects := THashObjectList.Create(True);

  Result := FUserAutoFreeObjects;
end;

procedure TPeerIO.BeginSend;
begin
  if BeginSendState then
      PrintError('illegal BeginSend!');
  BeginSendState := True;
  SendSequencePacketBegin;
end;

procedure TPeerIO.Send(const buff: PByte; siz: NativeInt);
begin
  SendSequencePacket(buff, siz);
end;

procedure TPeerIO.EndSend;
begin
  if not BeginSendState then
      PrintError('illegal EndSend!');
  BeginSendState := False;
  SendSequencePacketEnd;
end;

procedure TPeerIO.SendInteger(v: Integer);
begin
  Send(@v, C_Integer_Size);
end;

procedure TPeerIO.SendCardinal(v: Cardinal);
begin
  Send(@v, C_Cardinal_Size);
end;

procedure TPeerIO.SendInt64(v: Int64);
begin
  Send(@v, C_Int64_Size);
end;

procedure TPeerIO.SendByte(v: Byte);
begin
  Send(@v, C_Byte_Size);
end;

procedure TPeerIO.SendWord(v: Word);
begin
  Send(@v, C_Word_Size);
end;

procedure TPeerIO.SendVerifyCode(buff: Pointer; siz: NativeInt);
var
  headBuff: array [0 .. 2] of Byte;
  Code: TBytes;
begin
  GenerateHashCode(OwnerFramework.FHashSecurity, buff, siz, Code);
  headBuff[0] := Byte(OwnerFramework.FHashSecurity);
  PWORD(@headBuff[1])^ := Length(Code);
  Send(@headBuff[0], 3);
  if Length(Code) > 0 then
      Send(@Code[0], Length(Code));
end;

procedure TPeerIO.SendEncryptBuffer(buff: PByte; siz: NativeInt; CS: TCipherSecurity);
begin
  SendByte(Byte(CS));
  Encrypt(CS, buff, siz, FCipherKey, True);
  Send(buff, siz);
end;

procedure TPeerIO.SendEncryptMemoryStream(Stream: TMS64; CS: TCipherSecurity);
begin
  SendEncryptBuffer(Stream.Memory, Stream.Size, CS);
end;

procedure TPeerIO.Internal_Send_Console_Buff(buff: TMS64; CS: TCipherSecurity);
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(Byte(FConsoleToken));
  SendCardinal(Cardinal(buff.Size));

  SendVerifyCode(buff.Memory, buff.Size);
  SendEncryptMemoryStream(buff, CS);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_Stream_Buff(buff: TMS64; CS: TCipherSecurity);
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(Byte(FStreamToken));
  SendCardinal(Cardinal(buff.Size));

  SendVerifyCode(buff.Memory, buff.Size);
  SendEncryptMemoryStream(buff, CS);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_ConsoleNotify_Buff(buff: TMS64; CS: TCipherSecurity);
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(Byte(FConsoleNotifyToken));
  SendCardinal(Cardinal(buff.Size));

  SendVerifyCode(buff.Memory, buff.Size);
  SendEncryptMemoryStream(buff, CS);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_StreamNotify_Buff(buff: TMS64; CS: TCipherSecurity);
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(Byte(FStreamNotifyToken));
  SendCardinal(Cardinal(buff.Size));

  SendVerifyCode(buff.Memory, buff.Size);
  SendEncryptMemoryStream(buff, CS);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_Big_Stream_Header(const Cmd: SystemString; streamSiz: Int64);
var
  buff: TBytes;
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(FBigStreamToken);
  SendInt64(streamSiz);
  buff := TPascalString(Cmd).Bytes;
  SendCardinal(Cardinal(Length(buff)));
  Send(@buff[0], Length(buff));
  SetLength(buff, 0);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_BigStream_Buff(var Queue: TQueueData);
var
  StartPos, EndPos: Int64;
  tmpPos: Int64;
  j: Int64;
  Num: Int64;
  Rest: Int64;
  BigStream_Chunk: PByte;
begin
  Internal_Send_Big_Stream_Header(Queue.Cmd, Queue.BigStream.Size - Queue.BigStreamStartPos);

  StartPos := Queue.BigStreamStartPos;
  EndPos := Queue.BigStream.Size;
  tmpPos := StartPos;
  { Calculate number of full chunks that will fit into the buffer }
  Num := (EndPos - StartPos) div ZNet_Def_BigStream_ChunkSize;
  { Calculate remaining bytes }
  Rest := (EndPos - StartPos) mod ZNet_Def_BigStream_ChunkSize;
  { init buffer }
  BigStream_Chunk := GetMemory(ZNet_Def_BigStream_ChunkSize);
  { Process full chunks }
  j := 0;
  while j < Num do
    begin
      if not Connected then
          exit;

      Queue.BigStream.Position := tmpPos;
      Queue.BigStream.read(BigStream_Chunk^, ZNet_Def_BigStream_ChunkSize);
      inc(tmpPos, ZNet_Def_BigStream_ChunkSize);

      SendBigStreamMiniPacket(BigStream_Chunk, ZNet_Def_BigStream_ChunkSize);

      { peer fragment > C_BigStream_ChunkSize }
      if Queue.BigStream.Size - tmpPos > ZNet_Def_BigStream_ChunkSize then
        begin
          FBigStreamSending := Queue.BigStream;
          FBigStreamSendCurrentPos := tmpPos;
          FBigStreamSendDoneTimeFree := Queue.DoneAutoFree;
          Queue.BigStream := nil;
          FreeMemory(BigStream_Chunk);

          if Assigned(OwnerFramework.FOnBigStreamInterface) then
            begin
              OwnerFramework.FOnBigStreamInterface.BeginStream(self, FBigStreamSending.Size);
              OwnerFramework.FOnBigStreamInterface.Process(self, FBigStreamSending.Size, FBigStreamSendCurrentPos);
            end;

          exit;
        end;
      inc(j);
    end;

  { Process remaining bytes }
  if Rest > 0 then
    begin
      Queue.BigStream.Position := tmpPos;
      Queue.BigStream.read(BigStream_Chunk^, Rest);
      tmpPos := tmpPos + Rest;

      SendBigStreamMiniPacket(BigStream_Chunk, Rest);
    end;
  FreeMemory(BigStream_Chunk);
end;

procedure TPeerIO.Internal_Send_Complete_Buffer_Header(const Cmd: SystemString; BuffSiz, compSiz: Cardinal);
var
  buff: TBytes;
begin
  SendCardinal(FHeadToken);
  SendByte(FCompleteBufferToken);
  SendCardinal(BuffSiz);
  SendCardinal(compSiz);
  buff := TPascalString(Cmd).Bytes;
  SendCardinal(Cardinal(Length(buff)));
  Send(@buff[0], Length(buff));
  SetLength(buff, 0);
  SendCardinal(FTailToken);
end;

procedure TPeerIO.Internal_Send_CompleteBuffer_Buff(var Queue: TQueueData);
var
  Sour, Dest: TMS64;
begin
  BeginSend;
  if OwnerFramework.FCompleteBufferCompressed and (Queue.BufferSize > OwnerFramework.FCompleteBufferCompressionCondition) then
    begin
      Sour := TMS64.Create;
      if (Queue.Buffer <> nil) and (Queue.Buffer_Swap_Memory = nil) then
          Sour.SetPointerWithProtectedMode(Queue.Buffer, Queue.BufferSize)
      else if (Queue.Buffer = nil) and (Queue.Buffer_Swap_Memory <> nil) then
        begin
          Queue.Buffer_Swap_Memory.Prepare;
          Sour.SwapInstance(Queue.Buffer_Swap_Memory);
          DisposeObject(Queue.Buffer_Swap_Memory);
          Queue.Buffer_Swap_Memory := nil;
        end
      else
          PrintError('illegal CompleteBuffer Queue.');

      Dest := TMS64.Create;
      ParallelCompressMemory(scmZLIB_Fast, Sour, Dest);
      DisposeObject(Sour);
      Internal_Send_Complete_Buffer_Header(Queue.Cmd, Queue.BufferSize, Dest.Size);
      Send(Dest.Memory, Dest.Size);
      DisposeObject(Dest);
    end
  else
    begin
      Internal_Send_Complete_Buffer_Header(Queue.Cmd, Queue.BufferSize, 0);
      if (Queue.Buffer <> nil) and (Queue.Buffer_Swap_Memory = nil) then
          Send(Queue.Buffer, Queue.BufferSize)
      else if (Queue.Buffer = nil) and (Queue.Buffer_Swap_Memory <> nil) then
        begin
          Queue.Buffer_Swap_Memory.Prepare;
          Send(Queue.Buffer_Swap_Memory.Memory, Queue.BufferSize);
          DisposeObject(Queue.Buffer_Swap_Memory);
          Queue.Buffer_Swap_Memory := nil;
        end
      else
          PrintError('illegal CompleteBuffer Queue.');
    end;
  EndSend;
end;

procedure TPeerIO.Internal_Send_BigStream_Fragment_Signal;
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(FBigStreamReceiveFragmentSignal);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.Internal_Send_BigStream_Done_Signal;
begin
  BeginSend;
  SendCardinal(FHeadToken);
  SendByte(FBigStreamReceiveDoneSignal);
  SendCardinal(FTailToken);
  EndSend;
end;

procedure TPeerIO.SendBigStreamMiniPacket(buff: PByte; Size: NativeInt);
var
  head: TBigStreamFragmentHead;
  sourStream, destStream: TMS64;
begin
  BeginSend;

  if OwnerFramework.SendDataCompressed then
    begin
      sourStream := TMS64.Create;
      sourStream.SetPointerWithProtectedMode(buff, Size);
      destStream := TMS64.CustomCreate(8192);
      ParallelCompressMemory(scmZLIB_Fast, sourStream, destStream);

      head.Size := destStream.Size;
      head.Compressed := True;

      Send(@head, SizeOf(head));
      Send(destStream.Memory, destStream.Size);

      DisposeObject(sourStream);
      DisposeObject(destStream);
    end
  else
    begin
      head.Size := Size;
      head.Compressed := False;

      Send(@head, SizeOf(head));
      Send(buff, Size);
    end;

  EndSend;
end;

procedure TPeerIO.Internal_Send_Result_Data;
begin
  if FResultDataBuffer.Size > 0 then
    begin
      BeginSend;
      Send(FResultDataBuffer.Memory, FResultDataBuffer.Size);
      FResultDataBuffer.Clear;
      EndSend;
    end;
end;

procedure TPeerIO.Internal_Send_Console_Cmd;
var
  d: TDFE;
  EnSiz: Int64;
  Stream: TMS64;
begin
  d := TDFE.Create;

  d.WriteString(FSyncPick^.Cmd);
  d.WriteString(FSyncPick^.ConsoleData);

  EnSiz := d.ComputeEncodeSize;
  Stream := TMS64.CustomCreate(umlClamp(EnSiz, 8192, 64 * 1024));

  if OwnerFramework.FSendDataCompressed then
    begin
      if EnSiz > 1024 * 1024 then
          d.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, Stream, True)
      else
          d.EncodeAsZLib(Stream, True, False);
    end
  else if OwnerFramework.FFastEncrypt then
    begin
      // fast send, fixed by.qq600585
      d.FastEncode32To(Stream, EnSiz);
    end
  else
    begin
      // fast send, fixed by.qq600585
      d.EncodeTo(Stream, True, False);
    end;

  Internal_Send_Console_Buff(Stream, FSyncPick^.Cipher);

  DisposeObject(d);
  DisposeObject(Stream);

  if OwnerFramework.FSendDataCompressed then
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stCompress]);
end;

procedure TPeerIO.Internal_Send_Stream_Cmd;
var
  d: TDFE;
  EnSiz: Int64;
  Stream: TMS64;
begin
  d := TDFE.Create;

  d.WriteString(FSyncPick^.Cmd);
  d.WriteStream(FSyncPick^.StreamData);

  EnSiz := d.ComputeEncodeSize;
  Stream := TMS64.CustomCreate(umlClamp(EnSiz, 8192, 64 * 1024));

  if OwnerFramework.FSendDataCompressed then
    begin
      if EnSiz > 1024 * 1024 then
          d.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, Stream, True)
      else
          d.EncodeAsZLib(Stream, True, False);
    end
  else if OwnerFramework.FFastEncrypt then
    begin
      // fast send, fixed by.qq600585
      d.FastEncode32To(Stream, EnSiz);
    end
  else
    begin
      // fast send, fixed by.qq600585
      d.EncodeTo(Stream, True, False);
    end;

  Internal_Send_Stream_Buff(Stream, FSyncPick^.Cipher);

  DisposeObject(d);
  DisposeObject(Stream);

  if OwnerFramework.FSendDataCompressed then
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stCompress]);
end;

procedure TPeerIO.Internal_Send_ConsoleNotify_Cmd;
var
  d: TDFE;
  EnSiz: Int64;
  Stream: TMS64;
begin
  d := TDFE.Create;

  d.WriteString(FSyncPick^.Cmd);
  d.WriteString(FSyncPick^.ConsoleData);

  EnSiz := d.ComputeEncodeSize;
  Stream := TMS64.CustomCreate(umlClamp(EnSiz, 8192, 64 * 1024));

  if OwnerFramework.FSendDataCompressed then
    begin
      if EnSiz > 1024 * 1024 then
          d.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, Stream, True)
      else
          d.EncodeAsZLib(Stream, True, False);
    end
  else if OwnerFramework.FFastEncrypt then
    begin
      // fast send, fixed by.qq600585
      d.FastEncode32To(Stream, EnSiz);
    end
  else
    begin
      // fast send, fixed by.qq600585
      d.EncodeTo(Stream, True, False);
    end;

  Internal_Send_ConsoleNotify_Buff(Stream, FSyncPick^.Cipher);

  DisposeObject(d);
  DisposeObject(Stream);

  if OwnerFramework.FSendDataCompressed then
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stCompress]);
end;

procedure TPeerIO.Internal_Send_StreamNotify_Cmd;
var
  d: TDFE;
  EnSiz: Int64;
  Stream: TMS64;
begin
  d := TDFE.Create;

  d.WriteString(FSyncPick^.Cmd);
  d.WriteStream(FSyncPick^.StreamData);

  EnSiz := d.ComputeEncodeSize;
  Stream := TMS64.CustomCreate(umlClamp(EnSiz, 8192, 64 * 1024));

  if OwnerFramework.FSendDataCompressed then
    begin
      if EnSiz > 1024 * 1024 then
          d.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, Stream, True)
      else
          d.EncodeAsZLib(Stream, True, False);
    end
  else if OwnerFramework.FFastEncrypt then
    begin
      // fast send, fixed by.qq600585
      d.FastEncode32To(Stream, EnSiz);
    end
  else
    begin
      // fast send, fixed by.qq600585
      d.EncodeTo(Stream, True, False);
    end;

  Internal_Send_StreamNotify_Buff(Stream, FSyncPick^.Cipher);

  DisposeObject(d);
  DisposeObject(Stream);

  if OwnerFramework.FSendDataCompressed then
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stCompress]);
end;

procedure TPeerIO.Internal_Send_BigStream_Cmd;
begin
  Internal_Send_BigStream_Buff(FSyncPick^);
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecBigStream]);
end;

procedure TPeerIO.Internal_Send_CompleteBuffer_Cmd;
begin
  Internal_Send_CompleteBuffer_Buff(FSyncPick^);
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecCompleteBuffer]);
end;

procedure TPeerIO.Internal_Execute_Console;
var
  Tick_: TTimeTick;
begin
  FReceiveCommandRuning := True;
  if not OwnerFramework.QuietMode then
      PrintCommand('execute console: %s', FInCmd);

  Tick_ := GetTimeTick;
  OwnerFramework.ExecuteConsole(self, FInCmd, FInText, FOutText);
  FReceiveCommandRuning := False;

  OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FInCmd, GetTimeTick - Tick_);

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecConsole]);
  OwnerFramework.CmdRecvStatistics.IncValue(FInCmd, 1);
end;

procedure TPeerIO.Internal_Execute_Stream;
var
  Tick_: TTimeTick;
begin
  FReceiveCommandRuning := True;
  if not OwnerFramework.QuietMode then
      PrintCommand('execute stream: %s', FInCmd);

  Tick_ := GetTimeTick;
  OwnerFramework.ExecuteStream(self, FInCmd, FInDataFrame, FOutDataFrame);
  FReceiveCommandRuning := False;

  OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FInCmd, GetTimeTick - Tick_);

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecStream]);
  OwnerFramework.CmdRecvStatistics.IncValue(FInCmd, 1);
end;

procedure TPeerIO.Internal_Execute_ConsoleNotify;
var
  Tick_: TTimeTick;
begin
  FReceiveCommandRuning := True;
  if not OwnerFramework.QuietMode then
      PrintCommand('execute direct console: %s', FInCmd);

  Tick_ := GetTimeTick;
  OwnerFramework.ExecuteConsoleNotify(self, FInCmd, FInText);
  FReceiveCommandRuning := False;

  OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FInCmd, GetTimeTick - Tick_);

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecDirestConsole]);
  OwnerFramework.CmdRecvStatistics.IncValue(FInCmd, 1);
end;

procedure TPeerIO.Internal_Execute_StreamNotify;
var
  Tick_: TTimeTick;
begin
  FReceiveCommandRuning := True;
  if not OwnerFramework.QuietMode then
      PrintCommand('execute direct stream: %s', FInCmd);

  Tick_ := GetTimeTick;
  OwnerFramework.ExecuteStreamNotify(self, FInCmd, FInDataFrame);
  FReceiveCommandRuning := False;

  OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FInCmd, GetTimeTick - Tick_);

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stExecDirestStream]);
  OwnerFramework.CmdRecvStatistics.IncValue(FInCmd, 1);
end;

procedure TPeerIO.SendConsoleResult;
var
  buff: TBytes;
begin
  BeginSend;
  buff := TPascalString(FOutText).Bytes;

  { safe check. fixed by qq600585,2022-4-19 }
  if Length(buff) = 0 then
    begin
      SetLength(buff, 1);
      buff[0] := 0;
    end;

  SendCardinal(FHeadToken);
  SendInteger(Length(buff));

  SendVerifyCode(@buff[0], Length(buff));

  SendEncryptBuffer(@buff[0], Length(buff), FReceiveDataCipherSecurity);
  SendCardinal(FTailToken);

  EndSend;

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stResponse]);
end;

procedure TPeerIO.SendStreamResult;
var
  EnSiz: Int64;
  m64: TMS64;
begin
  BeginSend;
  EnSiz := FOutDataFrame.ComputeEncodeSize;
  m64 := TMS64.CustomCreate(umlClamp(EnSiz, 8192, 64 * 1024));

  if OwnerFramework.FSendDataCompressed then
    begin
      if EnSiz > 1024 * 1024 then
          FOutDataFrame.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, m64, True)
      else
          FOutDataFrame.EncodeAsZLib(m64, True, False);
    end
  else if OwnerFramework.FFastEncrypt then
    begin
      // fast send, fixed by.qq600585
      FOutDataFrame.FastEncode32To(m64, EnSiz);
    end
  else
    begin
      // fast send, fixed by.qq600585
      FOutDataFrame.EncodeTo(m64, True, False);
    end;

  SendCardinal(FHeadToken);
  SendInteger(m64.Size);

  SendVerifyCode(m64.Memory, m64.Size);

  SendEncryptBuffer(m64.Memory, m64.Size, FReceiveDataCipherSecurity);
  SendCardinal(FTailToken);
  DisposeObject(m64);
  EndSend;
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stResponse]);
end;

procedure TPeerIO.ExecuteDataFrame(CommDataType: Byte; DFE_: TDFE);
begin
  FInCmd := DFE_.Reader.ReadString;

  if CommDataType = FConsoleToken then
    begin
      FInText := DFE_.Reader.ReadString;
      FOutText := '';

      FCanPauseResultSend := True;
      FReceiveTriggerRuning := True;
      Internal_Execute_Console();
      FReceiveTriggerRuning := False;
      FCanPauseResultSend := False;

      if FPause_Result_Send then
        begin
          if not OwnerFramework.QuietMode then
              PrintCommand('pause console cmd %s Result', FInCmd);
          FCurrentPauseResultSend_CommDataType := CommDataType;
          exit;
        end;
      if not Connected then
          exit;

      if not OwnerFramework.QuietMode then
          PrintCommand('send console cmd %s Result data', FInCmd);
      SendConsoleResult();
    end
  else if CommDataType = FStreamToken then
    begin
      FInDataFrame.Clear;
      FOutDataFrame.Clear;
      DFE_.Reader.ReadDataFrame(FInDataFrame);

      FCanPauseResultSend := True;
      FReceiveTriggerRuning := True;
      Internal_Execute_Stream();
      FReceiveTriggerRuning := False;
      FCanPauseResultSend := False;

      if FPause_Result_Send then
        begin
          if not OwnerFramework.QuietMode then
              PrintCommand('pause stream cmd %s Result', FInCmd);
          FCurrentPauseResultSend_CommDataType := CommDataType;
          exit;
        end;

      if not Connected then
          exit;

      if not OwnerFramework.QuietMode then
          PrintCommand('send stream cmd %s Result data', FInCmd);
      SendStreamResult();
    end
  else if CommDataType = FConsoleNotifyToken then
    begin
      FInText := DFE_.Reader.ReadString;

      FReceiveTriggerRuning := True;
      Internal_Execute_ConsoleNotify();
      FReceiveTriggerRuning := False;
    end
  else if CommDataType = FStreamNotifyToken then
    begin
      FInDataFrame.Clear;
      FOutDataFrame.Clear;
      DFE_.Reader.ReadDataFrame(FInDataFrame);

      FReceiveTriggerRuning := True;
      Internal_Execute_StreamNotify();
      FReceiveTriggerRuning := False;
    end;
end;

procedure TPeerIO.Internal_Execute_BigStream;
var
  d: TTimeTick;
begin
  FReceiveCommandRuning := True;
  d := GetTimeTick;
  OwnerFramework.ExecuteBigStream(self, FBigStreamCmd, FSyncBigStreamReceive, FBigStreamTotal, FBigStreamCompleted);
  FReceiveCommandRuning := False;
  OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FInCmd, GetTimeTick - d);

  if FBigStreamTotal = FBigStreamCompleted then
    begin
      Internal_Send_BigStream_Done_Signal();
      { do stream state }
      if Assigned(OwnerFramework.FOnBigStreamInterface) then
          OwnerFramework.FOnBigStreamInterface.EndStream(self, FBigStreamTotal);

      OwnerFramework.CmdRecvStatistics.IncValue(FBigStreamCmd, 1);
      if not OwnerFramework.QuietMode then
          PrintCommand('Big Stream complete: %s', FBigStreamCmd);
    end
  else
    begin
      { do stream state }
      if Assigned(OwnerFramework.FOnBigStreamInterface) then
          OwnerFramework.FOnBigStreamInterface.Process(self, FBigStreamTotal, FBigStreamCompleted);
    end;
end;

function TPeerIO.ReceivedBigStreamFragment(Source_: TMS64): Int64;
var
  head: TBigStreamFragmentHead;
  np: Int64;
  buff, destBuff: TMS64;
  leftSize: Int64;
begin
  Result := -1; // Default return: incomplete fragment
  if (Source_.Size - Source_.Position < SizeOf(head)) then
      exit; // Not enough data to read fragment header
  Source_.ReadPtr(@head, SizeOf(head)); // Read fragment header (size + compression flag)

  if (Source_.Size - Source_.Position < head.Size) then
    begin
      FBigStream_Current_Received := FBigStreamCompleted + (Source_.Size - Source_.Position); // Partial fragment received, update progress

      if (not head.Compressed) and (FBigStreamCompleted + head.Size < FBigStreamTotal) then
        if (Source_.Size - Source_.Position > head.Size div 2) then
          if not FBigStreamFragmentSignal_SendedState then
            begin
              Internal_Send_BigStream_Fragment_Signal; // Request next fragment from sender
              FBigStreamFragmentSignal_SendedState := True;
            end;
      exit;
    end;

  np := Source_.Position + head.Size; // Calculate new position after consuming this fragment
  { change stripped state }
  Result := np; // Return bytes consumed from input buffer

  buff := TMS64.Create; // Create temporary stream to hold fragment payload
  buff.Mapping(Source_.PositionAsPtr, head.Size); // Zero-copy map fragment data
  buff.Position := 0;

  if head.Compressed then // If fragment was compressed on sender side
    begin
      destBuff := TMS64.CustomCreate(8192); // Target buffer for decompressed data
      ParallelDecompressStream(buff, destBuff); // Decompress using parallel engine
      DisposeObject(buff); // Free compressed buffer
      buff := destBuff; // Switch to decompressed data
      buff.Position := 0;
    end;

  leftSize := FBigStreamTotal - FBigStreamCompleted; // Remaining bytes to complete the full stream

  if leftSize > buff.Size then // Fragment does not complete the stream
    begin
      { fragment }
      if not FBigStreamFragmentSignal_SendedState then
        begin
          Internal_Send_BigStream_Fragment_Signal; // Request next fragment from sender
          FBigStreamFragmentSignal_SendedState := True;
        end;

      FBigStreamCompleted := FBigStreamCompleted + buff.Size; // Accumulate received bytes
      FBigStream_Current_Received := FBigStreamCompleted; // Update progress
      FSyncBigStreamReceive := buff; // Pass buffer to execution handler

      Internal_Execute_BigStream(); // Invoke user callback with current progress
      FBigStreamFragmentSignal_SendedState := False;
    end
  else // This fragment completes the entire stream
    begin
      { done }
      FBigStreamCompleted := FBigStreamTotal; // Mark as fully received
      FBigStream_Current_Received := FBigStreamCompleted;
      FSyncBigStreamReceive := buff; // Pass final buffer
      Internal_Execute_BigStream(); // Call user callback for completion
      FBigStreamTotal := 0; // Reset stream state
      FBigStreamCompleted := 0;
      FBigStream_Current_Received := 0;
      FBigStreamFragmentSignal_SendedState := False;
      FBigStreamCmd := '';
      FBigStreamReceiveProcessing := False; // No longer receiving a big stream
    end;

  FSyncBigStreamReceive := nil; // Clear reference to avoid double-free
  DisposeObject(buff); // Free the fragment buffer (now consumed)
end;

procedure TPeerIO.Internal_Execute_CompleteBuffer;
var
  d: TTimeTick;
begin
  if OwnerFramework.FSyncOnCompleteBuffer then
    begin
      FReceiveCommandRuning := True;
      d := GetTimeTick;

      if not OwnerFramework.QuietMode then
          PrintCommand('execute complete buffer: %s', FCompleteBufferCmd);

      FCompleteBuffer_Current_Trigger := FCompleteBufferReceivedStream;
      OwnerFramework.ExecuteCompleteBuffer(self, FCompleteBufferCmd, FCompleteBuffer_Current_Trigger.Memory, FCompleteBuffer_Current_Trigger.Size);

      FReceiveCommandRuning := False;
      OwnerFramework.CmdMaxExecuteConsumeStatistics.SetMax(FCompleteBufferCmd, GetTimeTick - d);

      OwnerFramework.CmdRecvStatistics.IncValue(FCompleteBufferCmd, 1);
    end
  else
    begin
      FCompleteBufferReceivedStream.Position := 0;
      with OwnerFramework.ProgressPost.PostExecute(False) do
        begin
          Data3 := FID;
          Data4 := FCompleteBufferCmd;
          Data1 := FCompleteBufferReceivedStream;
          OnExecute_M := OwnerFramework.DelayExecuteOnCompleteBufferState;
          Ready();
        end;

      FCompleteBufferReceivedStream := TMS64.Create
    end;
end;

function TPeerIO.FillCompleteBufferBuffer(Source_: TMS64): Int64;
var
  leftSize: Cardinal;
  Dest: TMS64;
begin
  leftSize := FCompleteBufferTotal - FCompleteBufferCompleted;
  if leftSize > Source_.Size then
    begin
      FCompleteBufferCompleted := FCompleteBufferCompleted + Source_.Size;
      Source_.Position := 0;
      FCompleteBufferReceivedStream.Position := FCompleteBufferReceivedStream.Size;
      FCompleteBufferReceivedStream.WritePtr(Source_.Memory, Source_.Size);
      { change stripped state }
      Result := Source_.Size;
    end
  else
    begin
      Source_.Position := 0;
      FCompleteBufferReceivedStream.Position := FCompleteBufferReceivedStream.Size;
      FCompleteBufferReceivedStream.WritePtr(Source_.Memory, leftSize);
      FCompleteBufferReceivedStream.Position := 0;

      { change stripped state }
      Result := leftSize;

      if FCompleteBufferCompressedSize > 0 then
        begin
          Dest := TMS64.CustomCreate(FCompleteBufferReceivedStream.Delta);
          ParallelDecompressStream(FCompleteBufferReceivedStream, Dest);
          DisposeObject(FCompleteBufferReceivedStream);
          Dest.Position := 0;
          FCompleteBufferReceivedStream := Dest;
        end;

      Internal_Execute_CompleteBuffer();
      FCompleteBufferReceivedStream.Clear;

      FCompleteBufferTotal := 0;
      FCompleteBufferCompressedSize := 0;
      FCompleteBufferCompleted := 0;
      FCompleteBufferCmd := '';
      FCompleteBufferReceiveProcessing := False;
    end;
end;

procedure TPeerIO.Internal_ExecuteResult;
begin
  if FCurrentQueueData = nil then
      exit;

  if (OwnerFramework.FSyncOnResult) then
    begin
      DoExecuteResult(self, FCurrentQueueData, FResult_Text, FResult_DFE);
      exit;
    end;

  with OwnerFramework.ProgressPost.PostExecute(False) do
    begin
      DataEng.Assign(FResult_DFE);
      Data4 := FID;
      Data5 := FCurrentQueueData;
      Data3 := FResult_Text;
      OnExecute_M := OwnerFramework.DelayExecuteOnResultState;
      Ready();
    end;
  FCurrentQueueData := nil;
end;

function TPeerIO.FillWaitOnResultBuffer(Source_: TMS64): Int64;
var
  dHead, dTail: Cardinal;
  dSize: Integer;
  dHashSecurity: Byte;
  dHashSiz: Word;
  dHash: TBytes;
  dCipherSecurity: Byte;
  buff: TBytes;
begin
  Result := -1;
  if not FWaitOnResult then
      exit;
  if FCurrentQueueData = nil then
      exit;

  Source_.Position := 0;

  { 0: head token }
  if (Source_.Size - Source_.Position < C_Cardinal_Size) then
      exit;
  Source_.read(dHead, C_Cardinal_Size);
  if dHead <> FHeadToken then
    begin
      PrintError('Header Illegal');
      DelayClose();
      exit;
    end;

  { 1: data len }
  if (Source_.Size - Source_.Position < C_Integer_Size) then
      exit;
  Source_.read(dSize, C_Integer_Size);

  { 2:verify code header }
  if (Source_.Size - Source_.Position < 3) then
      exit;
  Source_.read(dHashSecurity, C_Byte_Size);
  Source_.read(dHashSiz, C_Word_Size);

  { 3:verify code body }
  if (Source_.Size - Source_.Position < dHashSiz) then
      exit;
  SetLength(dHash, dHashSiz);
  if Length(dHash) > 0 then
      Source_.read(dHash[0], dHashSiz);

  { 4: use Encrypt state }
  if (Source_.Size - Source_.Position < C_Byte_Size) then
      exit;
  Source_.read(dCipherSecurity, C_Byte_Size);

  { 5:process buff and tail token }
  if (Source_.Size - Source_.Position < dSize + C_Cardinal_Size) then
      exit;
  SetLength(buff, dSize);
  if Length(buff) > 0 then
      Source_.read(buff[0], dSize);

  { 6: tail token }
  Source_.read(dTail, C_Cardinal_Size);
  if dTail <> FTailToken then
    begin
      PrintError('tail token error!');
      DelayClose();
      exit;
    end;

  FReceiveDataCipherSecurity := TCipherSecurity(dCipherSecurity);

  // decrypt reponse
  try
    if Length(buff) > 0 then
      begin
        Encrypt(FReceiveDataCipherSecurity, @buff[0], dSize, FCipherKey, False);
        if not VerifyHashCode(THashSecurity(dHashSecurity), @buff[0], dSize, dHash) then
          begin
            PrintError('verify data error!');
            DelayClose();
            exit;
          end;
      end;
  except
    PrintError('Encrypt error!');
    DelayClose();
    exit;
  end;

  { change stripped state }
  Result := Source_.Position;

  { trigger }
  if (FCurrentQueueData^.State = TQueueState.qsSendConsoleCMD) then // safe check. fixed by.qq600585 2023-9-8
    begin
      { safe check. fixed by qq600585,2022-4-19 }
      if (Length(buff) = 0) or ((Length(buff) = 1) and (buff[0] = 0)) then
        begin
          FResult_Text := '';
        end
      else
        begin
          try
            FResult_Text := umlStringOf(buff).Text;
            SetLength(buff, 0);
            FResult_DFE.Clear;
          except
            PrintError('WaitOnResultBuffer console data error!');
            DelayClose();
            exit;
          end;
        end;
      Internal_ExecuteResult();
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stResponse]);
    end
  else if (FCurrentQueueData^.State = TQueueState.qsSendStreamCMD) then // safe check. fixed by.qq600585 2023-9-8
    begin
      FResult_DFE.Clear;
      try
        FResult_DFE.DecodeFromBytes(buff, True);
        SetLength(buff, 0);
        FResult_Text := '';
      except
        PrintError('WaitOnResultBuffer stream error!');
        DelayClose();
        exit;
      end;
      Internal_ExecuteResult();
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stResponse]);
    end;

  SetLength(buff, 0);
  FWaitOnResult := False;

  if FCurrentQueueData <> nil then
    begin
      DisposeQueueData(FCurrentQueueData);
      FCurrentQueueData := nil;
    end;
end;

procedure TPeerIO.Internal_Save_Receive_Buffer(const buff: Pointer; siz: Int64);
begin
  if not Connected then
      exit;
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stReceiveSize], siz);

  if FReceiveProcessing or FAllSendProcessing then
      FReceivedAbort := not FillSequencePacketTo(buff, siz, FReceivedBuffer_Busy)
  else
    begin
      FReceivedBuffer.Position := FReceivedBuffer.Size;
      if FReceivedBuffer_Busy.Size > 0 then
        begin
          FReceivedBuffer.WritePtr(FReceivedBuffer_Busy.Memory, FReceivedBuffer_Busy.Size);
          FReceivedBuffer_Busy.Clear;
        end;
      FReceivedAbort := not FillSequencePacketTo(buff, siz, FReceivedBuffer);
    end;
end;

function TPeerIO.Internal_Process_Receive_Buffer(): Integer;
var
  Mapped_Received_Buffer: TMS64;
  Mapped_Position: Int64;
  rPos: Int64;
  rState: Boolean;
  dHead, dTail: Cardinal;
  dID: Byte;
  dSize: Cardinal;
  dHashSecurity: Byte;
  dHashSiz: Word;
  dHash: TBytes;
  dCipherSecurity: Byte;
  tmpStream: TMS64;
  d: TDFE;
  buff: TBytes;
  Total: Int64;
  sourSiz, compSiz: Cardinal;
  BreakAndDisconnect: Boolean;

  { continue send }
  BigStream_Chunk: PByte;
  BigStream_RealChunkSize: Integer;
  BigStream_SendDone: Boolean;
begin
  Result := 0;
  if FReceivedAbort then
    begin
      DelayClose;
      exit;
    end; // Abort flag set: close connection and exit.
  if FAllSendProcessing or
    FReceiveProcessing or
    FPause_Result_Send or
    (FResultDataBuffer.Size > 0) or
    FReceiveTriggerRuning then
    begin
      exit;
    end; // Prevent re‑entry while other operations are in progress.

  FReceiveProcessing := True; // Mark receive processing as active.

  BreakAndDisconnect := False;
  Mapped_Received_Buffer := TMS64.Create;

  if (FReceivedBuffer.Size > 0) or (FReceivedBuffer_Busy.Size > 0) then
    begin
      if FReceivedBuffer_Busy.Size > 0 then
        begin
          FReceivedBuffer.Position := FReceivedBuffer.Size;
          FReceivedBuffer.WritePtr(FReceivedBuffer_Busy.Memory, FReceivedBuffer_Busy.Size);
          FReceivedBuffer_Busy.Clear;
        end;
    end; // Merge busy buffer into main receive buffer.
  Mapped_Position := 0;
  Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position); // Zero‑copy map of current receive buffer.

  try
    while ((OwnerFramework.FPer_Progress_Loop_Limit <= 0) or (Result < OwnerFramework.FPer_Progress_Loop_Limit)) and (Mapped_Received_Buffer.Size > 0) and Connected do
      begin
        inc(Result); // Count commands processed in this cycle.

        Mapped_Received_Buffer.Position := 0;

        if FWaitOnResult then
          begin
            rPos := FillWaitOnResultBuffer(Mapped_Received_Buffer);
            rState := rPos > 0;

            if rState then
              begin
                inc(Mapped_Position, rPos);
                Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);
                Continue;
              end
            else
                Break;
          end; // Handle pending result response first.

        if FBigStreamReceiveProcessing then
          begin
            rPos := ReceivedBigStreamFragment(Mapped_Received_Buffer);
            rState := rPos > 0;

            if rState then
              begin
                inc(Mapped_Position, rPos);
                Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);
                Continue;
              end
            else
                Break;
          end; // Process big‑stream fragments if active.

        if FCompleteBufferReceiveProcessing then
          begin
            rPos := FillCompleteBufferBuffer(Mapped_Received_Buffer);
            rState := rPos > 0;

            if rState then
              begin
                inc(Mapped_Position, rPos);
                Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);
                Continue;
              end
            else
                Break;
          end; // Assemble complete‑buffer if active.

        { 0: head token }
        if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Cardinal_Size + C_Byte_Size) then
            Break; // Not enough data for header.
        Mapped_Received_Buffer.read(dHead, C_Cardinal_Size);
        if dHead <> FHeadToken then
          begin
            BreakAndDisconnect := True;
            Break;
          end; // Invalid header: disconnect.
        { 1: data type }
        Mapped_Received_Buffer.read(dID, C_Byte_Size); // Read command type token.

        { done signal }
        if dID = FBigStreamReceiveDoneSignal then
          begin
            { 2: process tail token }
            Mapped_Received_Buffer.read(dTail, C_Cardinal_Size);
            if dTail <> FTailToken then
              begin
                PrintError('tail error!');
                BreakAndDisconnect := True;
                Break;
              end; // Verify tail token.

            { stripped stream }
            inc(Mapped_Position, Mapped_Received_Buffer.Position);
            Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);

            { done }
            FWaitBigStreamReceiveDoneSignal := False; // Big‑stream send done flag cleared.
          end
        else if dID = FBigStreamReceiveFragmentSignal then
          begin
            { 2: process tail token }
            Mapped_Received_Buffer.read(dTail, C_Cardinal_Size);
            if dTail <> FTailToken then
              begin
                PrintError('tail error!');
                BreakAndDisconnect := True;
                Break;
              end; // Verify tail.

            { stripped stream }
            inc(Mapped_Position, Mapped_Received_Buffer.Position);
            Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);

            { save }
            if (FBigStreamSending <> nil) then // If we are actively sending a big‑stream, send next chunk.
              begin
                BigStream_RealChunkSize := ZNet_Def_BigStream_ChunkSize;

                BigStream_SendDone := FBigStreamSending.Size - FBigStreamSendCurrentPos <= BigStream_RealChunkSize;

                if BigStream_SendDone then
                    BigStream_RealChunkSize := FBigStreamSending.Size - FBigStreamSendCurrentPos;

                BigStream_Chunk := GetMemory(BigStream_RealChunkSize);

                try
                  FBigStreamSending.Position := FBigStreamSendCurrentPos;
                  FBigStreamSending.read(BigStream_Chunk^, BigStream_RealChunkSize);
                except
                  FreeMemory(BigStream_Chunk);
                  PrintError('BigStream IO read error!');
                  BreakAndDisconnect := True;
                  Break;
                end; // Read next chunk from source stream.

                try
                  SendBigStreamMiniPacket(BigStream_Chunk, BigStream_RealChunkSize);
                  FreeMemory(BigStream_Chunk);
                  AtomInc(FBigStreamSendCurrentPos, BigStream_RealChunkSize);
                except
                  PrintError('BigStream send error!');
                  BreakAndDisconnect := True;
                  Break;
                end; // Send the chunk and advance position.

                if BigStream_SendDone then
                  begin
                    if Assigned(OwnerFramework.FOnBigStreamInterface) then
                        OwnerFramework.FOnBigStreamInterface.EndStream(self, FBigStreamSending.Size);

                    if FBigStreamSendDoneTimeFree then
                        DisposeObject(FBigStreamSending);
                    FBigStreamSending := nil;
                    FBigStreamSendCurrentPos := -1;
                    FBigStreamSendDoneTimeFree := False;
                  end // Transfer complete: cleanup.
                else
                  begin
                    if Assigned(OwnerFramework.FOnBigStreamInterface) then
                        OwnerFramework.FOnBigStreamInterface.Process(self, FBigStreamSending.Size, FBigStreamSendCurrentPos);
                  end; // Notify progress.
              end;
          end
        else if FWaitBigStreamReceiveDoneSignal then
          begin
            PrintError('BigStream error: FWaitBigStreamReceiveDoneSignal is True');
            BreakAndDisconnect := True;
            Break;
          end // Unexpected state: disconnect.
        else if dID = FBigStreamToken then // New big‑stream header received.
          begin
            { 2:stream size }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Int64_Size) then
                Break;
            Mapped_Received_Buffer.read(Total, C_Int64_Size); // Total stream size.

            { 3:command len }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Cardinal_Size) then
                Break;
            Mapped_Received_Buffer.read(dSize, C_Cardinal_Size); // Command name length.

            { 4:command and tial token }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < dSize + C_Cardinal_Size) then
                Break;
            SetLength(buff, dSize);
            if dSize > 0 then
                Mapped_Received_Buffer.read(buff[0], dSize); // Read command name.

            { 5: process tail token }
            Mapped_Received_Buffer.read(dTail, C_Cardinal_Size);
            if dTail <> FTailToken then
              begin
                PrintError('tail error!');
                BreakAndDisconnect := True;
                Break;
              end; // Verify tail.

            FBigStreamTotal := Total;
            FBigStreamCompleted := 0;
            FBigStream_Current_Received := 0;
            FBigStreamFragmentSignal_SendedState := False;
            FBigStreamCmd := umlStringOf(buff).Text;
            FBigStreamReceiveProcessing := True; // Start receiving big‑stream.
            SetLength(buff, 0);

            { stripped stream }
            inc(Mapped_Position, Mapped_Received_Buffer.Position);
            Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);

            { do stream state }
            if Assigned(OwnerFramework.FOnBigStreamInterface) then
                OwnerFramework.FOnBigStreamInterface.BeginStream(self, FBigStreamTotal);

            AtomInc(OwnerFramework.Statistics[TStatisticsType.stReceiveBigStream]);
          end
        else if dID = FCompleteBufferToken then // Complete‑buffer header.
          begin
            { 2:complete buff size }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Cardinal_Size * 3) then
                Break;
            Mapped_Received_Buffer.read(sourSiz, C_Cardinal_Size); // Original size.
            Mapped_Received_Buffer.read(compSiz, C_Cardinal_Size); // Compressed size (0 if none).
            Mapped_Received_Buffer.read(dSize, C_Cardinal_Size); // Command name length.

            { 3:command and tial token }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < dSize + C_Cardinal_Size) then
                Break;
            SetLength(buff, dSize);
            if Length(buff) > 0 then
                Mapped_Received_Buffer.read(buff[0], dSize); // Read command name.

            { 4: process tail token }
            Mapped_Received_Buffer.read(dTail, C_Cardinal_Size);
            if dTail <> FTailToken then
              begin
                PrintError('tail error!');
                BreakAndDisconnect := True;
                Break;
              end; // Verify tail.

            if (OwnerFramework.FMaxCompleteBufferSize > 0) and (sourSiz > OwnerFramework.FMaxCompleteBufferSize) then
              begin
                PrintError('Oversize of CompleteBuffer cmd: ' + umlStringOf(buff).Text);
                BreakAndDisconnect := True;
                Break;
              end; // Security check: reject oversized buffers.

            if compSiz > 0 then
                FCompleteBufferTotal := compSiz
            else
                FCompleteBufferTotal := sourSiz; // Total data to receive.
            FCompleteBufferCompressedSize := compSiz;
            FCompleteBufferCompleted := 0;
            FCompleteBufferCmd := umlStringOf(buff).Text;
            FCompleteBufferReceiveProcessing := True; // Start complete‑buffer assembly.
            FCompleteBufferReceivedStream.Clear;
            FCompleteBufferReceivedStream.Delta := umlMax(FCompleteBufferTotal, 1024 * 64);
            SetLength(buff, 0);

            { stripped stream }
            inc(Mapped_Position, Mapped_Received_Buffer.Position);
            Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);

            AtomInc(OwnerFramework.Statistics[TStatisticsType.stReceiveCompleteBuffer]);
          end
        else if dID in [FConsoleToken, FStreamToken, FConsoleNotifyToken, FStreamNotifyToken] then // Regular command.
          begin
            { 2: size }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Cardinal_Size) then
                Break;
            Mapped_Received_Buffer.read(dSize, C_Cardinal_Size); // Payload size.

            { 3:verify code header }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < 3) then
                Break;
            Mapped_Received_Buffer.read(dHashSecurity, C_Byte_Size); // Hash algorithm.
            Mapped_Received_Buffer.read(dHashSiz, C_Word_Size); // Hash length.

            { 4:verify code body }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < dHashSiz) then
                Break;
            SetLength(dHash, dHashSiz);
            if Length(dHash) > 0 then
                Mapped_Received_Buffer.read(dHash[0], dHashSiz); // Hash data.

            { 5: Encrypt style }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < C_Byte_Size) then
                Break;
            Mapped_Received_Buffer.read(dCipherSecurity, C_Byte_Size); // Cipher used.

            { 6: process stream }
            if (Mapped_Received_Buffer.Size - Mapped_Received_Buffer.Position < dSize + C_Cardinal_Size) then
                Break;
            tmpStream := TMS64.Create;
            tmpStream.SetPointerWithProtectedMode(Mapped_Received_Buffer.PositionAsPtr, dSize); // Zero‑copy map payload.
            Mapped_Received_Buffer.Position := Mapped_Received_Buffer.Position + dSize;

            { 7: process tail token }
            Mapped_Received_Buffer.read(dTail, C_Cardinal_Size);
            if dTail <> FTailToken then
              begin
                PrintError('tail error!');
                BreakAndDisconnect := True;
                Break;
              end; // Verify tail.

            FReceiveDataCipherSecurity := TCipherSecurity(dCipherSecurity);

            try
                Encrypt(FReceiveDataCipherSecurity, tmpStream.Memory, tmpStream.Size, FCipherKey, False);
            except
              PrintError('Encrypt error!');
              DisposeObject(tmpStream);
              BreakAndDisconnect := True;
              Break;
            end; // Decrypt payload.

            if not VerifyHashCode(THashSecurity(dHashSecurity), tmpStream.Memory, tmpStream.Size, dHash) then
              begin
                PrintError('verify error!');
                DisposeObject(tmpStream);
                BreakAndDisconnect := True;
                Break;
              end; // Verify integrity.

            d := TDFE.Create;
            tmpStream.Position := 0;
            try
              if d.DecodeFrom(tmpStream, True) < 0 then
                begin
                  PrintError('decrypt error!');
                  DisposeObject(tmpStream);
                  DisposeObject(d);
                  BreakAndDisconnect := True;
                  Break;
                end;
            except
              PrintError('decrypt error!');
              DisposeObject(tmpStream);
              DisposeObject(d);
              BreakAndDisconnect := True;
              Break;
            end; // Deserialise DFE.
            DisposeObject(tmpStream);

            { stripped stream }
            inc(Mapped_Position, Mapped_Received_Buffer.Position);
            Mapped_Received_Buffer.Mapping(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);

            try
                ExecuteDataFrame(dID, d); // Dispatch to command handler.
            except
              PrintError('Execute error!');
              DisposeObject(d);
              BreakAndDisconnect := True;
              Break;
            end;
            DisposeObject(d);

            AtomInc(OwnerFramework.Statistics[TStatisticsType.stRequest]); // Count request.
          end
        else
          begin
            BreakAndDisconnect := True;
            Break;
          end; // Unknown token: disconnect.
      end;
  finally
    { rebuild stream }
    DisposeObject(Mapped_Received_Buffer);
    if Mapped_Position > 0 then
      begin
        tmpStream := TMS64.CustomCreate(FReceivedBuffer.Delta);
        if FReceivedBuffer.Size - Mapped_Position > 0 then
            tmpStream.WritePtr(FReceivedBuffer.PositionAsPtr(Mapped_Position), FReceivedBuffer.Size - Mapped_Position);
        DisposeObject(FReceivedBuffer);
        FReceivedBuffer := tmpStream;
      end; // Trim consumed data from receive buffer.

    FReceivedBuffer.Position := FReceivedBuffer.Size;
    FReceiveProcessing := False; // Clear processing flag.

    FLast_Process_Receive_Buffer_CPU_Is_Full := (OwnerFramework.FPer_Progress_Loop_Limit > 0) and (Result >= OwnerFramework.FPer_Progress_Loop_Limit);

    if not BreakAndDisconnect then
      begin
        Process_Send_Buffer(); // After receive, attempt to send queued data.
      end
    else
        DelayClose() // On error, close connection.
  end;
end;

procedure TPeerIO.Internal_Process_Send_Buffer();
var
  p: PQueueData;
begin
  if FAllSendProcessing or
    FReceiveProcessing or
    FWaitOnResult or
    FBigStreamReceiveProcessing or
    (FBigStreamSending <> nil) or
    FReceiveTriggerRuning or
    FWaitBigStreamReceiveDoneSignal then
    begin
      exit;
    end;

  FAllSendProcessing := True;

  if FResultDataBuffer.Size > 0 then
    begin
      Internal_Send_Result_Data();
      FAllSendProcessing := False;
      exit;
    end;

  FSend_Queue_Critical.Lock;
  try
    while FSend_Queue_Pool.Num > 0 do
      begin
        if not Connected then
            Break;
        if FWaitOnResult then
            Break;
        p := FSend_Queue_Pool.current^.data;
        FCurrentQueueData := p;
        case p^.State of
          qsSendConsoleCMD:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stConsole]);
              FSyncPick := p;
              FWaitOnResult := True;
              Internal_Send_Console_Cmd();
              FSyncPick := nil;
              FSend_Queue_Pool.Next;
              Break;
            end;
          qsSendStreamCMD:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stStream]);
              FSyncPick := p;
              FWaitOnResult := True;
              Internal_Send_Stream_Cmd();
              FSyncPick := nil;
              FSend_Queue_Pool.Next;
              Break;
            end;
          qsSendConsoleNotifyCMD:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stDirestConsole]);
              FSyncPick := p;
              Internal_Send_ConsoleNotify_Cmd();
              FSyncPick := nil;
              DisposeQueueData(p);
              FSend_Queue_Pool.Next;
            end;
          qsSendStreamNotifyCMD:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stDirestStream]);
              FSyncPick := p;
              Internal_Send_StreamNotify_Cmd();
              FSyncPick := nil;
              DisposeQueueData(p);
              FSend_Queue_Pool.Next;
            end;
          qsSendBigStream:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stSendBigStream]);
              FSyncPick := p;
              FWaitBigStreamReceiveDoneSignal := True;
              Internal_Send_BigStream_Cmd();
              FSyncPick := nil;
              DisposeQueueData(p);
              FSend_Queue_Pool.Next;
              Break;
            end;
          qsSendCompleteBuffer:
            begin
              AtomInc(OwnerFramework.Statistics[TStatisticsType.stSendCompleteBuffer]);
              FSyncPick := p;
              Internal_Send_CompleteBuffer_Cmd();
              FSyncPick := nil;
              DisposeQueueData(p);
              FSend_Queue_Pool.Next;
            end;
          else PrintError('IO Queue state error.');
        end;
      end;
  finally
    FAllSendProcessing := False;
    FSend_Queue_Critical.UnLock;
  end;
end;

procedure TPeerIO.CheckAndTriggerFailedWaitResult;
var
  tmp: TDFE;
begin
  if (FCurrentQueueData <> nil) and (FWaitOnResult) then
    begin
      try
        if FCurrentQueueData^.State = qsSendConsoleCMD then
          begin
            if Assigned(FCurrentQueueData^.OnConsoleFailedM) then
                FCurrentQueueData^.OnConsoleFailedM(self, FCurrentQueueData^.Param1, FCurrentQueueData^.Param2, FCurrentQueueData^.ConsoleData)
            else if Assigned(FCurrentQueueData^.OnConsoleFailedP) then
                FCurrentQueueData^.OnConsoleFailedP(self, FCurrentQueueData^.Param1, FCurrentQueueData^.Param2, FCurrentQueueData^.ConsoleData);
          end
        else if FCurrentQueueData^.State = qsSendStreamCMD then
          begin
            tmp := TDFE.Create;
            FCurrentQueueData^.StreamData.Position := 0;
            tmp.DecodeFrom(FCurrentQueueData^.StreamData, True);
            if Assigned(FCurrentQueueData^.OnStreamFailedM) then
                FCurrentQueueData^.OnStreamFailedM(self, FCurrentQueueData^.Param1, FCurrentQueueData^.Param2, tmp)
            else if Assigned(FCurrentQueueData^.OnStreamFailedP) then
                FCurrentQueueData^.OnStreamFailedP(self, FCurrentQueueData^.Param1, FCurrentQueueData^.Param2, tmp);
            DisposeObject(tmp);
          end;
        DisposeQueueData(FCurrentQueueData);
      except
      end;
      FCurrentQueueData := nil;
    end;
end;

procedure TPeerIO.Internal_Close_P2PVMTunnel;
begin
  if FP2PVMTunnel <> nil then
    begin
      OwnerFramework.p2pVMTunnelClose(self, FP2PVMTunnel);
      FP2PVMTunnel.CloseP2PVMTunnel;
      DisposeObjectAndNil(FP2PVMTunnel);
    end;
  SetLength(FP2PVM_Auth_Token, 0);
  SetLength(FP2PVM_Cipher_Key, 0);
  DisposeObjectAndNil(FP2PVM_Cipher);
end;

constructor TPeerIO.Create(OwnerFramework_: TZNet; IOInterface_: TCore_Object);
var
  kref: TInt64;
begin
  inherited Create;

  FOwnerFramework := OwnerFramework_;
  FIOInterface := IOInterface_;

  OwnerFramework.Lock_All_IO;

  FDisable_Progress := False;

  FID := OwnerFramework_.MakeID;
  FIO_Create_TimeTick := GetTimeTick();

  FHeadToken := ZNet_Def_DataHeadToken;
  FTailToken := ZNet_Def_DataTailToken;

  FConsoleToken := ZNet_Def_DefaultConsoleToken;
  FStreamToken := ZNet_Def_DefaultStreamToken;
  FConsoleNotifyToken := ZNet_Def_DefaultConsoleNotifyToken;
  FStreamNotifyToken := ZNet_Def_DefaultStreamNotifyToken;
  FBigStreamToken := ZNet_Def_DefaultBigStreamToken;
  FBigStreamReceiveFragmentSignal := ZNet_Def_DefaultBigStreamReceiveFragmentSignal;
  FBigStreamReceiveDoneSignal := ZNet_Def_DefaultBigStreamReceiveDoneSignal;
  FCompleteBufferToken := ZNet_Def_DefaultCompleteBufferToken;

  FReceived_Physics_Critical := TCritical.Create;
  FReceived_Physics_Fragment_Pool := TPhysics_Fragment_Pool.Create;

  FLast_Process_Receive_Buffer_CPU_Is_Full := False;
  FReceivedAbort := False;
  FReceivedBuffer := TMS64.CustomCreate(8192);
  FReceivedBuffer_Busy := TMS64.CustomCreate(8192);

  FBigStreamReceiveProcessing := False;
  FBigStreamTotal := 0;
  FBigStreamCompleted := 0;
  FBigStream_Current_Received := 0;
  FBigStreamFragmentSignal_SendedState := False;
  FBigStreamCmd := '';
  FSyncBigStreamReceive := nil;
  FBigStreamSending := nil;
  FBigStreamSendCurrentPos := -1;
  FBigStreamSendDoneTimeFree := False;
  FWaitBigStreamReceiveDoneSignal := False;

  FCompleteBufferReceiveProcessing := False;
  FCompleteBufferTotal := 0;
  FCompleteBufferCompressedSize := 0;
  FCompleteBufferCompleted := 0;
  FCompleteBufferCmd := '';
  FCompleteBufferReceivedStream := TMS64.CustomCreate(umlMin(OwnerFramework.FMaxCompleteBufferSize, 64 * 1024));
  FCompleteBuffer_Current_Trigger := nil;

  FCurrentQueueData := nil;
  FWaitOnResult := False;
  FPause_Result_Send := False;
  FReceiveTriggerRuning := False;
  FReceiveDataCipherSecurity := TCipherSecurity.csNone;
  FResultDataBuffer := TMS64.Create;
  FSendDataCipherSecurity := OwnerFramework.RandomCipherSecurity;
  FCanPauseResultSend := False;

  FSend_Queue_Critical := TCritical.Create;
  FSend_Queue_Pool := TQueueData_Pool.Create;

  UpdateLastCommunicationTime;
  LastCommunicationTick_Received := FLastCommunicationTick;
  LastCommunicationTick_KeepAlive := LastCommunicationTick_Received;
  LastCommunicationTick_Sending := FLastCommunicationTick;

  { generate random key }
  TMISC.GenerateRandomKey(kref, C_Int64_Size);
  TCipher.GenerateKey(FSendDataCipherSecurity, @kref, C_Int64_Size, FCipherKey);
  FDecryptInstance := nil;
  FEncryptInstance := nil;

  FRemoteExecutedForConnectInit := False;

  FAllSendProcessing := False;
  FReceiveProcessing := False;

  FInCmd := '';
  FInText := '';
  FOutText := '';
  FInDataFrame := TDFE.Create;
  FOutDataFrame := TDFE.Create;
  FResult_Text := '';
  FResult_DFE := TDFE.Create;
  FSyncPick := nil;

  FWaitSendBusy := False;
  FReceiveCommandRuning := False;
  FReceiveResultRuning := False;

  FProgressRunning := False;
  FTimeOutProcessDone := False;
  FLast_IO_Is_IDLE := True;
  FLast_IO_IDLE_Time := FIO_Create_TimeTick;

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stConnected]);

  InitSequencePacketModel(64, $FFFF);

  FP2PVMTunnel := nil;
  SetLength(FP2PVM_Auth_Token, 0);
  SetLength(FP2PVM_Cipher_Key, 0);
  FP2PVM_Cipher := nil;

  On_Internal_Send_Byte_Buffer := OwnerFramework.Framework_Internal_Send_Byte_Buffer;
  On_Internal_Save_Receive_Buffer := OwnerFramework.Framework_Internal_Save_Receive_Buffer;
  On_Internal_Process_Receive_Buffer := OwnerFramework.Framework_Internal_Process_Receive_Buffer;
  On_Internal_Process_Send_Buffer := OwnerFramework.Framework_Internal_Process_Send_Buffer;
  OnCreate := OwnerFramework.Framework_Internal_IO_Create;
  OnDestroy := OwnerFramework.Framework_Internal_IO_Destroy;

  OnVMBuildAuthModelResult_C := nil;
  OnVMBuildAuthModelResult_M := nil;
  OnVMBuildAuthModelResult_P := nil;
  OnVMBuildAuthModelResultIO_C := nil;
  OnVMBuildAuthModelResultIO_M := nil;
  OnVMBuildAuthModelResultIO_P := nil;
  OnVMAuthResult_C := nil;
  OnVMAuthResult_M := nil;
  OnVMAuthResult_P := nil;
  OnVMAuthResultIO_C := nil;
  OnVMAuthResultIO_M := nil;
  OnVMAuthResultIO_P := nil;

  FOnAutomatedP2PVMClientConnectionDone_C := nil;
  FOnAutomatedP2PVMClientConnectionDone_M := nil;
  FOnAutomatedP2PVMClientConnectionDone_P := nil;

  FUserData := nil;
  FUserValue := NULL;
  FUserVariants := nil;
  FUserObjects := nil;
  FUserAutoFreeObjects := nil;

  FUser_Define := OwnerFramework.FPeerIOUserDefineClass.Create(self);
  FUser_Special := OwnerFramework.FPeerIOUserSpecialClass.Create(self);
  BeginSendState := False;

  OnCreate(self);
  CreateAfter;

  OwnerFramework.FPeerIO_HashPool.Add(FID, self, False);
  OwnerFramework.UnLock_All_IO;
end;

procedure TPeerIO.CreateAfter;
begin
end;

destructor TPeerIO.Destroy;
var
  i: Integer;
begin
  CheckAndTriggerFailedWaitResult();

  try
      OnDestroy(self);
  except
  end;

  FreeSequencePacketModel();
  Internal_Close_P2PVMTunnel;

  if (FBigStreamSending <> nil) and (FBigStreamSendDoneTimeFree) then
    begin
      DisposeObject(FBigStreamSending);
      FBigStreamSending := nil;
    end;

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stDisconnect]);

  OwnerFramework.Lock_All_IO;
  OwnerFramework.FPeerIO_HashPool.Delete(FID);
  OwnerFramework.UnLock_All_IO;

  FSend_Queue_Critical.Lock;
  while FSend_Queue_Pool.Num > 0 do
    begin
      DisposeQueueData(FSend_Queue_Pool.current^.data);
      FSend_Queue_Pool.Next;
    end;
  FSend_Queue_Critical.UnLock;

  if (FUser_Define.FBusy) or (FUser_Define.FBusyNum > 0) then
    begin
      FUser_Define.FOwner := nil;
      TCompute.RunM_NP(FUser_Define.DelayFreeOnBusy);
    end
  else
      DisposeObject(FUser_Define);

  if (FUser_Special.FBusy) or (FUser_Special.FBusyNum > 0) then
    begin
      FUser_Special.FOwner := nil;
      TCompute.RunM_NP(FUser_Special.DelayFreeOnBusy);
    end
  else
      DisposeObject(FUser_Special);

  { free buffer }
  DisposeObject(FSend_Queue_Pool);
  DisposeObject(FSend_Queue_Critical);
  DisposeObject(FReceived_Physics_Critical);
  DisposeObject(FReceived_Physics_Fragment_Pool);
  DisposeObject(FReceivedBuffer);
  DisposeObject(FReceivedBuffer_Busy);
  DisposeObject(FCompleteBufferReceivedStream);
  DisposeObject(FResultDataBuffer);
  DisposeObject(FInDataFrame);
  DisposeObject(FOutDataFrame);
  DisposeObject(FResult_DFE);

  { free cipher instance }
  DisposeObjectAndNil(FDecryptInstance);
  DisposeObjectAndNil(FEncryptInstance);

  if FUserVariants <> nil then
      DisposeObject(FUserVariants);
  if FUserObjects <> nil then
      DisposeObject(FUserObjects);
  if FUserAutoFreeObjects <> nil then
      DisposeObject(FUserAutoFreeObjects);
  inherited Destroy;
end;

function TPeerIO.IOBusy: Boolean;
var
  io_idle_: Boolean;
begin
  FReceived_Physics_Critical.Lock;
  try
    Result :=
      (IOSendBuffer.Size > 0) or
      (SendingSequencePacketHistory.Count > 0) or
      (SequencePacketReceivedPool.Count > 0) or
      (FSend_Queue_Pool.Num > 0) or
      (FReceivedBuffer.Size > 0) or
      (FReceivedBuffer_Busy.Size > 0) or
      (FWaitOnResult) or
      (FBigStreamReceiveProcessing) or
      (FCompleteBufferReceiveProcessing) or
      (FPause_Result_Send) or
      (FReceiveTriggerRuning) or
      (FReceived_Physics_Fragment_Pool.Num > 0);

    if not Result then
      if FOwnerFramework.InheritsFrom(TZNet_Client) then
          Result := FOwnerFramework.FSend_Queue_Swap_Pool.Num > 0;

    { update io state }
    io_idle_ := not Result;
    if io_idle_ and (io_idle_ <> FLast_IO_Is_IDLE) then
        FLast_IO_IDLE_Time := GetTimeTick;
    FLast_IO_Is_IDLE := io_idle_;
  finally
      FReceived_Physics_Critical.UnLock;
  end;
end;

procedure TPeerIO.IO_IDLE_TraceC(data: TCore_Object; OnNotify: TOnDataNotify_C);
var
  p: PIDLE_Trace;
begin
  if not IOBusy then
    begin
      OnNotify(data);
      exit;
    end;

  New(p);
  p^.ID := ID;
  p^.data := data;
  p^.OnNotifyC := OnNotify;
  p^.OnNotifyM := nil;
  p^.OnNotifyP := nil;
  with OwnerFramework.ProgressEngine.PostExecuteM(False, 0.1, OwnerFramework.IDLE_Trace_Execute) do
    begin
      Data5 := p;
      Ready();
    end;
end;

procedure TPeerIO.IO_IDLE_TraceM(data: TCore_Object; OnNotify: TOnDataNotify_M);
var
  p: PIDLE_Trace;
begin
  if not IOBusy then
    begin
      OnNotify(data);
      exit;
    end;

  New(p);
  p^.ID := ID;
  p^.data := data;
  p^.OnNotifyC := nil;
  p^.OnNotifyM := OnNotify;
  p^.OnNotifyP := nil;
  with OwnerFramework.ProgressEngine.PostExecuteM(False, 0.1, OwnerFramework.IDLE_Trace_Execute) do
    begin
      Data5 := p;
      Ready();
    end;
end;

procedure TPeerIO.IO_IDLE_TraceP(data: TCore_Object; OnNotify: TOnDataNotify_P);
var
  p: PIDLE_Trace;
begin
  if not IOBusy then
    begin
      OnNotify(data);
      exit;
    end;

  New(p);
  p^.ID := ID;
  p^.data := data;
  p^.OnNotifyC := nil;
  p^.OnNotifyM := nil;
  p^.OnNotifyP := OnNotify;
  with OwnerFramework.ProgressEngine.PostExecuteM(False, 0.1, OwnerFramework.IDLE_Trace_Execute) do
    begin
      Data5 := p;
      Ready();
    end;
end;

function TPeerIO.Is_Double_Tunnel: Boolean;
begin
  Result := False;
  if OwnerFramework = nil then
      exit;

  if OwnerFramework.DoubleChannelFramework is TDTService_NoAuth then
      Result := True
  else if OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
      Result := True
  else if OwnerFramework.DoubleChannelFramework is TDTService_VirtualAuth then
      Result := True
  else if OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
      Result := True
  else if OwnerFramework.DoubleChannelFramework is TDTService then
      Result := True
  else if OwnerFramework.DoubleChannelFramework is TDTClient then
      Result := True;
end;

function TPeerIO.Is_Recveive_Tunnel: Boolean;
begin
  Result := False;
  if OwnerFramework = nil then
      exit;

  if OwnerFramework.DoubleChannelFramework is TDTService_NoAuth then
      Result := TDTService_NoAuth(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
      Result := TDTClient_NoAuth(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTService_VirtualAuth then
      Result := TDTService_VirtualAuth(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
      Result := TDTClient_VirtualAuth(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTService then
      Result := TDTService(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient then
      Result := TDTClient(OwnerFramework.DoubleChannelFramework).RecvTunnel = OwnerFramework;
end;

function TPeerIO.Is_Send_Tunnel: Boolean;
begin
  Result := False;
  if OwnerFramework = nil then
      exit;

  if OwnerFramework.DoubleChannelFramework is TDTService_NoAuth then
      Result := TDTService_NoAuth(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
      Result := TDTClient_NoAuth(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTService_VirtualAuth then
      Result := TDTService_VirtualAuth(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
      Result := TDTClient_VirtualAuth(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTService then
      Result := TDTService(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework
  else if OwnerFramework.DoubleChannelFramework is TDTClient then
      Result := TDTClient(OwnerFramework.DoubleChannelFramework).SendTunnel = OwnerFramework;
end;

function TPeerIO.Is_Link_OK: Boolean;
begin
  Result := False;
  if OwnerFramework = nil then
      exit;

  if UserDefine is TService_RecvTunnel_UserDefine_NoAuth then
    begin
      Result := TService_RecvTunnel_UserDefine_NoAuth(UserDefine).LinkOk;
    end
  else if UserDefine is TClient_RecvTunnel_NoAuth then
    begin
      if OwnerFramework.DoubleChannelFramework is TDTClient_NoAuth then
          Result := TDTClient_NoAuth(OwnerFramework.DoubleChannelFramework).LinkOk;
    end
  else if UserDefine is TService_RecvTunnel_UserDefine_VirtualAuth then
    begin
      Result := TService_RecvTunnel_UserDefine_VirtualAuth(UserDefine).LinkOk;
    end
  else if UserDefine is TClient_RecvTunnel_VirtualAuth then
    begin
      if OwnerFramework.DoubleChannelFramework is TDTClient_VirtualAuth then
          Result := TDTClient_VirtualAuth(OwnerFramework.DoubleChannelFramework).LinkOk;
    end
  else if UserDefine is TService_RecvTunnel_UserDefine then
    begin
      Result := TService_RecvTunnel_UserDefine(UserDefine).LinkOk;
    end
  else if UserDefine is TClient_RecvTunnel then
    begin
      if OwnerFramework.DoubleChannelFramework is TDTClient then
          Result := TDTClient(OwnerFramework.DoubleChannelFramework).LinkOk;
    end;
end;

function TPeerIO.Get_Send_Tunnel_IO: TPeerIO;
var
  Send_Tunnel: TZNet;
  Send_Tunnel_ID: Cardinal;
begin
  Result := nil;
  if not Get_Link_OK_Send_Tunnel(self, Send_Tunnel, Send_Tunnel_ID) then
      exit;
  Result := Send_Tunnel.PeerIO_HashPool[Send_Tunnel_ID];
end;

function TPeerIO.Get_Send_Tunnel(var Send_Tunnel: TZNet; var Send_Tunnel_ID: Cardinal): Boolean;
begin
  Result := Get_Link_OK_Send_Tunnel(self, Send_Tunnel, Send_Tunnel_ID);
end;

function TPeerIO.Get_Recv_Tunnel_IO: TPeerIO;
var
  Recv_Tunnel: TZNet;
  Recv_Tunnel_ID: Cardinal;
begin
  Result := nil;
  if not Get_Link_OK_Recv_Tunnel(self, Recv_Tunnel, Recv_Tunnel_ID) then
      exit;
  Result := Recv_Tunnel.PeerIO_HashPool[Recv_Tunnel_ID];
end;

function TPeerIO.Get_Recv_Tunnel(var Recv_Tunnel: TZNet; var Recv_Tunnel_ID: Cardinal): Boolean;
begin
  Result := Get_Link_OK_Recv_Tunnel(self, Recv_Tunnel, Recv_Tunnel_ID);
end;

function TPeerIO.p2pVMTunnelReadyOk: Boolean;
begin
  Result := (FP2PVMTunnel <> nil) and (FP2PVMTunnel.WasAuthed);
end;

procedure TPeerIO.BuildP2PAuthToken;
var
  d: TDFE;
begin
  ResetSequencePacketBuffer;
  FSequencePacketSignal := False;

  d := TDFE.Create;
  d.WriteInteger(umlRandomRange64(-MaxInt, MaxInt));
  SendStreamCmdM(C_BuildP2PAuthToken, d, OwnerFramework.Do_CMD_Result_BuildP2PAuthToken);
  DisposeObject(d);
  Internal_Process_Send_Buffer();

  OnVMBuildAuthModelResult_C := nil;
  OnVMBuildAuthModelResult_M := nil;
  OnVMBuildAuthModelResult_P := nil;
  OnVMBuildAuthModelResultIO_C := nil;
  OnVMBuildAuthModelResultIO_M := nil;
  OnVMBuildAuthModelResultIO_P := nil;
end;

procedure TPeerIO.BuildP2PAuthTokenC(const OnResult: TOnNotify_C);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResult_C := OnResult;
end;

procedure TPeerIO.BuildP2PAuthTokenM(const OnResult: TOnNotify_M);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResult_M := OnResult;
end;

procedure TPeerIO.BuildP2PAuthTokenP(const OnResult: TOnNotify_P);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResult_P := OnResult;
end;

procedure TPeerIO.BuildP2PAuthTokenIO_C(const OnResult: TOnIONotify_C);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResultIO_C := OnResult;
end;

procedure TPeerIO.BuildP2PAuthTokenIO_M(const OnResult: TOnIONotify_M);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResultIO_M := OnResult;
end;

procedure TPeerIO.BuildP2PAuthTokenIO_P(const OnResult: TOnIONotify_P);
begin
  BuildP2PAuthToken;
  OnVMBuildAuthModelResultIO_P := OnResult;
end;

procedure TPeerIO.DoP2PVM_Created(Sender: TZNet_P2PVM);
begin
end;

procedure TPeerIO.DoP2PVM_InstallLogicFramework(Inst: TZNet);
begin
end;

procedure TPeerIO.DoP2PVM_UninstallLogicFramework(Inst: TZNet);
begin
end;

procedure TPeerIO.OpenP2PVMTunnel(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString);
begin
  if FP2PVMTunnel = nil then
    begin
      ResetSequencePacketBuffer;
      FSequencePacketSignal := False;

      OnVMAuthResult_C := nil;
      OnVMAuthResult_M := nil;
      OnVMAuthResult_P := nil;
      OnVMAuthResultIO_C := nil;
      OnVMAuthResultIO_M := nil;
      OnVMAuthResultIO_P := nil;

      if SendRemoteRequest then
        begin
          if IOBusy then
            begin
              PrintError('OpenP2PVMTunnel failed: IO Busy.');
              exit;
            end;
          SendConsoleNotifyCmd(C_InitP2PTunnel, AuthToken);
          Process_Send_Buffer();
        end;

      FP2PVMTunnel := TZNet_P2PVM.Create(vmHashPoolSize);
      FP2PVMTunnel.QuietMode := OwnerFramework.QuietMode;
      FP2PVMTunnel.FVMID := FID;
      DoP2PVM_Created(FP2PVMTunnel);

      FP2PVMTunnel.OpenP2PVMTunnel(self);
      FP2PVMTunnel.AuthWaiting;

      FP2PVMTunnel.OnAuthSuccessOnesNotify := P2PVMAuthSuccess;
    end;
end;

procedure TPeerIO.OpenP2PVMTunnel(SendRemoteRequest: Boolean; const AuthToken: SystemString);
begin
  if OwnerFramework.FFrameworkIsClient then
      OpenP2PVMTunnel(16384, SendRemoteRequest, AuthToken)
  else
      OpenP2PVMTunnel(64, SendRemoteRequest, AuthToken);
end;

procedure TPeerIO.OpenP2PVMTunnelC(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_C);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResult_C := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelM(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_M);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResult_M := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelP(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_P);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResult_P := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelC(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_C);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResult_C := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelM(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_M);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResult_M := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelP(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnState_P);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResult_P := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_C(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_C);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_C := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_M(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_M);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_M := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_P(SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_P);
begin
  OpenP2PVMTunnel(SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_P := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_C(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_C);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_C := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_M(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_M);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_M := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnelIO_P(vmHashPoolSize: Integer; SendRemoteRequest: Boolean; const AuthToken: SystemString; const OnResult: TOnIOState_P);
begin
  OpenP2PVMTunnel(vmHashPoolSize, SendRemoteRequest, AuthToken);
  OnVMAuthResultIO_P := OnResult;
  with OwnerFramework.ProgressPost.PostExecuteM(False, 10.0, OwnerFramework.VMAuthFailedDelayExecute) do
    begin
      Data3 := FID;
      Ready();
    end;
end;

procedure TPeerIO.OpenP2PVMTunnel;
begin
  OpenP2PVMTunnel(False, '');
end;

procedure TPeerIO.CloseP2PVMTunnel;
begin
  if IOBusy then
    begin
      PrintError('CloseP2PVMTunnel failed: IO Busy.');
      exit;
    end;
  SendConsoleNotifyCmd(C_CloseP2PTunnel, '');
  Process_Send_Buffer();
end;

procedure TPeerIO.Print(const v: SystemString);
var
  n: SystemString;
begin
  if not OwnerFramework.QuietMode then
    begin
      n := GetPeerIP;
      if n <> '' then
          OwnerFramework.DoPrint(PFormat('%s %s', [n, v]))
      else
          OwnerFramework.DoPrint(PFormat('%s', [v]));
    end;
end;

procedure TPeerIO.Print(const v: SystemString; const Args: array of const);
begin
  if not OwnerFramework.QuietMode then
      Print(PFormat(v, Args));
end;

procedure TPeerIO.PrintCommand(const v, Args: SystemString);
begin
  if OwnerFramework.QuietMode then
      exit;
  try
    if (not IsSystemCMD(Args)) and OwnerFramework.FPrintParams.Get_Default_Value(Args, True) then
        Print(PFormat(v, [Args]));
  except
      Print(PFormat(v, [Args]));
  end;
end;

procedure TPeerIO.PrintParam(const v, Args: SystemString);
begin
  if OwnerFramework.QuietMode then
      exit;
  try
    if (not IsSystemCMD(Args)) and OwnerFramework.FPrintParams.Get_Default_Value(Args, True) then
        Print(PFormat(v, [Args]));
  except
      Print(PFormat(v, [Args]));
  end;
end;

procedure TPeerIO.PrintError(const v: SystemString);
var
  n: SystemString;
begin
  n := GetPeerIP;
  if n <> '' then
      OwnerFramework.DoError(PFormat('error: %s %s', [n, v]))
  else
      OwnerFramework.DoError(PFormat('error: %s', [v]));
end;

procedure TPeerIO.PrintError(const v: SystemString; const Args: array of const);
begin
  PrintError(PFormat(v, Args));
end;

procedure TPeerIO.PrintWarning(const v: SystemString);
var
  n: SystemString;
begin
  n := GetPeerIP;
  if n <> '' then
      OwnerFramework.DoWarning(PFormat('Warning: %s %s', [n, v]))
  else
      OwnerFramework.DoWarning(PFormat('Warning: %s', [v]));
end;

procedure TPeerIO.PrintWarning(const v: SystemString; const Args: array of const);
begin
  PrintWarning(PFormat(v, Args));
end;

procedure TPeerIO.Progress;
begin
  if FDisable_Progress then
      exit;

  { anti dead loop }
  if FProgressRunning then
      exit;

  FProgressRunning := True;

  IOBusy();

  { send buffer }
  Process_Send_Buffer;

  { optimize physics model }
  try
    if not FLast_Process_Receive_Buffer_CPU_Is_Full then
        Extract_Physics_Fragment_To_Receive_Buffer;
    Process_Receive_Buffer;
  except
  end;

  { sequence packet model }
  try
      ProcessSequencePacketModel();
  except
  end;

  if FP2PVMTunnel <> nil then
    begin
      try
          FP2PVMTunnel.Progress;
      except
      end;
    end;

  try
      FUser_Define.Progress;
  except
  end;

  try
      FUser_Special.Progress;
  except
  end;

  if (not FTimeOutProcessDone) and (OwnerFramework.FIdleTimeOut > 0) and (StopCommunicationTime > OwnerFramework.FIdleTimeOut) then
    begin
      PrintWarning('IO "%s" Timeout %ss do Close', [ClassName, umlFloatToStr(StopCommunicationTime / 1000).Text]);
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stTimeOutDisconnect]);
      FTimeOutProcessDone := True;
      DelayClose(1.0);
    end;

  if (not FTimeOutProcessDone) and (OwnerFramework.FTimeOutKeepAlive) and (IsSequencePacketModel) and (FSequencePacketSignal) and
    ((OwnerFramework.Protocol = TCommunicationProtocol.cpZServer) and (FRemoteExecutedForConnectInit)) and
    (GetTimeTick() - LastCommunicationTick_KeepAlive > 1000) and (WriteBuffer_is_NULL) then
    begin
      SendSequencePacketKeepAlive(nil, 0);
      FlushIOSendBuffer;
      LastCommunicationTick_KeepAlive := GetTimeTick();
    end;

  { anti dead loop }
  FProgressRunning := False;
end;

procedure TPeerIO.DelayClose;
begin
  DelayClose(0);
end;

procedure TPeerIO.DelayClose(const t: Double);
begin
{$IFDEF DEBUG}
  PrintWarning('IO "%s" Delay do Close', [ClassName]);
{$ENDIF DEBUG}
  with OwnerFramework.ProgressPost.PostExecuteM(False, t, OwnerFramework.DelayClose) do
    begin
      Data3 := ID;
      Ready();
    end;
  FDisable_Progress := True;
end;

procedure TPeerIO.DelayFree;
begin
  DelayFree(0);
end;

procedure TPeerIO.DelayFree(const t: Double);
begin
{$IFDEF DEBUG}
  PrintWarning('IO "%s" Delay do Free', [ClassName]);
{$ENDIF DEBUG}
  with OwnerFramework.ProgressPost.PostExecuteM(False, t, OwnerFramework.DelayFree) do
    begin
      Data3 := ID;
      Ready();
    end;
  FDisable_Progress := True;
end;

procedure TPeerIO.Write_Physics_Fragment(const p: Pointer; siz: Int64);
var
  m64: TMem64;
begin
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stPhysicsFragmentCache], siz);
  FReceived_Physics_Critical.Lock;
  if OwnerFramework.FPhysicsFragmentSwapSpaceTechnology and (FReceived_Physics_Fragment_Pool.Num > OwnerFramework.FPhysicsFragmentSwapSpaceTrigger) then
      m64 := TZDB2_Swap_Space_Technology.RunTime_Pool.Create_Memory(p, siz, True)
  else
      m64 := TMem64.Create;
  m64.WritePtr(p, siz);
  FReceived_Physics_Fragment_Pool.Push(m64);
  FReceived_Physics_Critical.UnLock;
  UpdateLastCommunicationTime;
end;

function TPeerIO.Extract_Physics_Fragment_To_Receive_Buffer(): Int64;
begin
  Result := 0;
  FReceived_Physics_Critical.Lock;
  if FReceived_Physics_Fragment_Pool.Num > 0 then
    begin
      repeat
        if OwnerFramework.FPhysicsFragmentSwapSpaceTechnology and (FReceived_Physics_Fragment_Pool.First^.data is TZDB2_Swap_Space_Technology_Memory) then
            TZDB2_Swap_Space_Technology_Memory(FReceived_Physics_Fragment_Pool.First^.data).Prepare;
        if FReceived_Physics_Fragment_Pool.First^.data.Size > 0 then
          begin
            try
                On_Internal_Save_Receive_Buffer(self, FReceived_Physics_Fragment_Pool.First^.data.Memory, FReceived_Physics_Fragment_Pool.First^.data.Size);
            except
                Break; // loop to next time attempt
            end;
            AtomDec(OwnerFramework.Statistics[TStatisticsType.stPhysicsFragmentCache], FReceived_Physics_Fragment_Pool.First^.data.Size);
          end;
        inc(Result, FReceived_Physics_Fragment_Pool.First^.data.Size);
        FReceived_Physics_Fragment_Pool.Next;
      until (Result > OwnerFramework.FExtract_Physics_Fragment_Max_Size) or (FReceived_Physics_Fragment_Pool.Num <= 0);
      UpdateLastCommunicationTime;
      LastCommunicationTick_Received := FLastCommunicationTick;
      LastCommunicationTick_KeepAlive := LastCommunicationTick_Received;
    end;
  FReceived_Physics_Critical.UnLock;
end;

procedure TPeerIO.Process_Receive_Buffer();
begin
  On_Internal_Process_Receive_Buffer(self);
end;

procedure TPeerIO.Process_Send_Buffer();
begin
  On_Internal_Process_Send_Buffer(self);
end;

procedure TPeerIO.PostQueueData(p: PQueueData);
begin
  OwnerFramework.CmdSendStatistics.IncValue(p^.Cmd, 1);
  FSend_Queue_Critical.Lock;
  FSend_Queue_Pool.Push(p);
  FSend_Queue_Critical.UnLock;
end;

procedure TPeerIO.BeginWriteCustomBuffer;
begin
  WriteBufferOpen;
end;

procedure TPeerIO.EndWriteCustomBuffer;
begin
  WriteBufferFlush;
  WriteBufferClose;
end;

procedure TPeerIO.WriteCustomBuffer(const Buffer: PByte; const Size: NativeInt);
begin
  On_Internal_Send_Byte_Buffer(self, Buffer, Size);
end;

procedure TPeerIO.WriteCustomBuffer(const Buffer: TMS64);
begin
  WriteCustomBuffer(Buffer.Memory, Buffer.Size);
end;

procedure TPeerIO.WriteCustomBuffer(const Buffer: TMem64);
begin
  WriteCustomBuffer(Buffer.Memory, Buffer.Size);
end;

procedure TPeerIO.WriteCustomBuffer(const Buffer: TMS64; const doneFreeBuffer: Boolean);
begin
  WriteCustomBuffer(Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

procedure TPeerIO.WriteCustomBuffer(const Buffer: TMem64; const doneFreeBuffer: Boolean);
begin
  WriteCustomBuffer(Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

procedure TPeerIO.Pause;
begin
  if FCanPauseResultSend then
    begin
      FPause_Result_Send := True;
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stPause]);
    end
  else
      RaiseInfo('No Supported.');
end;

procedure TPeerIO.PauseResultSend;
begin
  Pause;
end;

procedure TPeerIO.BreakResultSend;
begin
  Pause;
end;

procedure TPeerIO.SkipResultSend;
begin
  Pause;
end;

procedure TPeerIO.NoResultSend;
begin
  Pause;
end;

procedure TPeerIO.StopResultSend;
begin
  Pause;
end;

procedure TPeerIO.Resume;
var
  headBuff: array [0 .. 2] of Byte;
  console_buff: TBytes;
  buff: TMS64;
  EnSiz: Int64;
  dHead, dTail: Cardinal;
  Len: Integer;
  Code: TBytes;
  bCipherSecurity: Byte;
begin
  if not FPause_Result_Send then
      exit;
  if FResultDataBuffer.Size > 0 then
      exit;

  AtomInc(OwnerFramework.Statistics[TStatisticsType.stContinue]);

  if FCurrentPauseResultSend_CommDataType in [FConsoleToken, FStreamToken] then
    begin
      buff := TMS64.Create;

      if FCurrentPauseResultSend_CommDataType = FConsoleToken then
        begin
          console_buff := TPascalString(FOutText).Bytes;
          { safe check. fixed by qq600585,2022-4-19 }
          if Length(console_buff) = 0 then
            begin
              SetLength(console_buff, 1);
              console_buff[0] := 0;
            end;
          buff.WritePtr(@console_buff[0], Length(console_buff));
        end
      else if OwnerFramework.FSendDataCompressed then
        begin
          if FOutDataFrame.ComputeEncodeSize > 1024 * 1024 then
              FOutDataFrame.EncodeAsSelectCompressor(TSelectCompressionMethod.scmZLIB_Max, buff, True)
          else
              FOutDataFrame.EncodeAsZLib(buff, True, False);
        end
      else if OwnerFramework.FFastEncrypt then
        begin
          EnSiz := FOutDataFrame.ComputeEncodeSize;
          // fast send, fixed by.qq600585
          FOutDataFrame.FastEncode32To(buff, EnSiz);
        end
      else
        begin
          // fast send, fixed by.qq600585
          FOutDataFrame.EncodeTo(buff, True, False);
        end;

      dHead := FHeadToken;
      dTail := FTailToken;
      Len := buff.Size;

      { generate hash source }
      GenerateHashCode(OwnerFramework.FHashSecurity, buff.Memory, buff.Size, Code);
      headBuff[0] := Byte(OwnerFramework.FHashSecurity);
      PWORD(@headBuff[1])^ := Length(Code);

      { generate encrypt data body }
      bCipherSecurity := Byte(FReceiveDataCipherSecurity);
      Encrypt(FReceiveDataCipherSecurity, buff.Memory, buff.Size, FCipherKey, True);

      { result data header }
      FResultDataBuffer.WritePtr(@dHead, C_Cardinal_Size);
      FResultDataBuffer.WritePtr(@Len, C_Integer_Size);

      { verify code }
      FResultDataBuffer.WritePtr(@headBuff[0], 3);
      if Length(Code) > 0 then
          FResultDataBuffer.WritePtr(@Code[0], Length(Code));

      { data body }
      FResultDataBuffer.WritePtr(@bCipherSecurity, C_Byte_Size);
      FResultDataBuffer.WritePtr(buff.Memory, Len);

      { data tail }
      FResultDataBuffer.WritePtr(@dTail, C_Cardinal_Size);

      DisposeObject(buff);

      AtomInc(OwnerFramework.Statistics[TStatisticsType.stResponse]);
    end;
  FPause_Result_Send := False;
end;

procedure TPeerIO.ContinueResultSend;
begin
  Resume;
end;

procedure TPeerIO.Continue_Send_Result;
begin
  Resume;
end;

procedure TPeerIO.ResumeResultSend;
begin
  Resume;
end;

procedure TPeerIO.NowResultSend;
begin
  Resume;
end;

function TPeerIO.ResultSendIsPaused: Boolean;
begin
  Result := FPause_Result_Send;
end;

function TPeerIO.GetBigStreamReceiveState(var Total, Complete: Int64): Boolean;
begin
  Result := FBigStreamReceiveProcessing;
  Total := FBigStreamTotal;
  Complete := FBigStream_Current_Received;
end;

function TPeerIO.GetBigStreamSendingState(var Total, Complete: Int64): Boolean;
begin
  if FBigStreamSending <> nil then
    begin
      Total := FBigStreamSending.Size;
      Result := True;
    end
  else
    begin
      Total := 0;
      Result := False;
    end;
  Complete := FBigStreamSendCurrentPos;
end;

function TPeerIO.GetBigStreamBatch: TBigStreamBatch;
begin
  Result := FUser_Define.FBigStreamBatch;
end;

function TPeerIO.Get_Last_IO_IDLE_Time: TTimeTick;
begin
  if not IOBusy() then
      Result := FLast_IO_IDLE_Time
  else
      Result := GetTimeTick();
end;

procedure TPeerIO.SetID(const Value: Cardinal);
begin
  if OwnerFramework is TZNet_Server then
    begin
      if Value = FID then
          exit;
      if not OwnerFramework.FPeerIO_HashPool.Exists_Key(FID) then
          PrintError('old ID illegal');
      if OwnerFramework.FPeerIO_HashPool.Exists_Key(Value) then
          PrintError('new ID illegal');
      OwnerFramework.Lock_All_IO;
      try
        OwnerFramework.FPeerIO_HashPool.Delete(FID);
        FID := Value;
        OwnerFramework.FPeerIO_HashPool.Add(FID, self, False);
      finally
          OwnerFramework.UnLock_All_IO;
      end;
    end
  else
    begin
      OwnerFramework.FPeerIO_HashPool.Delete(FID);
      FID := Value;
      OwnerFramework.FPeerIO_HashPool.Add(FID, self, True);
    end;
end;

function TPeerIO.CipherKeyPtr: PCipherKeyBuffer;
begin
  Result := @FCipherKey;
end;

procedure TPeerIO.GenerateHashCode(const hs: THashSecurity; buff: Pointer; siz: Integer; var output: TBytes);
begin
  TCipher.GenerateHashByte(hs, buff, siz, output);
  AtomInc(OwnerFramework.Statistics[TStatisticsType.stGenerateHash]);
end;

function TPeerIO.VerifyHashCode(const hs: THashSecurity; buff: Pointer; siz: Integer; var Code: TBytes): Boolean;
var
  buffCode: TBytes;
begin
  try
    GenerateHashCode(hs, buff, siz, buffCode);
    Result := TCipher.CompareHash(buffCode, Code);
  except
      Result := False;
  end;
end;

procedure TPeerIO.Encrypt(CS: TCipherSecurity; DataPtr: Pointer; Size: Cardinal; var k: TCipherKeyBuffer; enc: Boolean);
begin
  if Size = 0 then
      exit;

  if OwnerFramework.FFastEncrypt then
    begin
      if enc then
        begin
          if FEncryptInstance <> nil then
            if (FEncryptInstance.CipherSecurity <> CS) or (not TCipher.CompareKey(FEncryptInstance.LastGenerateKey, k)) then
                DisposeObjectAndNil(FEncryptInstance);
          if FEncryptInstance = nil then
            begin
              FEncryptInstance := CreateCipherClassFromBuffer(CS, k);
              FEncryptInstance.CBC := True;
              FEncryptInstance.ProcessTail := True;
            end;
          FEncryptInstance.Encrypt(DataPtr, Size);
        end
      else
        begin
          if FDecryptInstance <> nil then
            if (FDecryptInstance.CipherSecurity <> CS) or (not TCipher.CompareKey(FDecryptInstance.LastGenerateKey, k)) then
                DisposeObjectAndNil(FDecryptInstance);
          if FDecryptInstance = nil then
            begin
              FDecryptInstance := CreateCipherClassFromBuffer(CS, k);
              FDecryptInstance.CBC := True;
              FDecryptInstance.ProcessTail := True;
            end;
          FDecryptInstance.Decrypt(DataPtr, Size);
        end;
    end
  else if OwnerFramework.FUsedParallelEncrypt then
      SequEncryptCBC(CS, DataPtr, Size, k, enc, True)
  else
      SequEncryptCBCWithDirect(CS, DataPtr, Size, k, enc, True);

  if CS <> TCipherSecurity.csNone then
      AtomInc(OwnerFramework.Statistics[TStatisticsType.stEncrypt]);
end;

function TPeerIO.NoneCommunicationTime: TTimeTick;
begin
  Result := GetTimeTick - LastCommunicationTick_Received;
end;

procedure TPeerIO.UpdateLastCommunicationTime;
begin
  FLastCommunicationTick := GetTimeTick;
end;

procedure TPeerIO.SendConsoleCmd(const Cmd, ConsoleData: SystemString);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmd(self, Cmd, ConsoleData)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmd(Cmd, ConsoleData);
end;

procedure TPeerIO.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdM(self, Cmd, ConsoleData, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdM(Cmd, ConsoleData, OnResult);
end;

procedure TPeerIO.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdM(self, Cmd, ConsoleData, Param1, Param2, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdM(Cmd, ConsoleData, Param1, Param2, OnResult);
end;

procedure TPeerIO.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdM(self, Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdM(Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed);
end;

procedure TPeerIO.SendStreamCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmd(self, Cmd, StreamData, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmd(Cmd, StreamData, DoneAutoFree);
end;

procedure TPeerIO.SendStreamCmd(const Cmd: SystemString; StreamData: TDFE);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmd(self, Cmd, StreamData)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmd(Cmd, StreamData);
end;

procedure TPeerIO.SendStreamCmdM(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdM(self, Cmd, StreamData, OnResult, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdM(Cmd, StreamData, OnResult, DoneAutoFree);
end;

procedure TPeerIO.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdM(self, Cmd, StreamData, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdM(Cmd, StreamData, OnResult);
end;

procedure TPeerIO.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdM(self, Cmd, StreamData, Param1, Param2, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdM(Cmd, StreamData, Param1, Param2, OnResult);
end;

procedure TPeerIO.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdM(self, Cmd, StreamData, Param1, Param2, OnResult, OnFailed)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdM(Cmd, StreamData, Param1, Param2, OnResult, OnFailed);
end;

procedure TPeerIO.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdP(self, Cmd, ConsoleData, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdP(Cmd, ConsoleData, OnResult);
end;

procedure TPeerIO.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdP(self, Cmd, ConsoleData, Param1, Param2, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdP(Cmd, ConsoleData, Param1, Param2, OnResult);
end;

procedure TPeerIO.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleCmdP(self, Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleCmdP(Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed);
end;

procedure TPeerIO.SendStreamCmdP(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdP(self, Cmd, StreamData, OnResult, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdP(Cmd, StreamData, OnResult, DoneAutoFree);
end;

procedure TPeerIO.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdP(self, Cmd, StreamData, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdP(Cmd, StreamData, OnResult);
end;

procedure TPeerIO.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdP(self, Cmd, StreamData, Param1, Param2, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdP(Cmd, StreamData, Param1, Param2, OnResult);
end;

procedure TPeerIO.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamCmdP(self, Cmd, StreamData, Param1, Param2, OnResult, OnFailed)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamCmdP(Cmd, StreamData, Param1, Param2, OnResult, OnFailed);
end;

procedure TPeerIO.SendConsoleNotifyCmd(const Cmd, ConsoleData: SystemString);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleNotifyCmd(self, Cmd, ConsoleData)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleNotifyCmd(Cmd, ConsoleData);
end;

procedure TPeerIO.SendConsoleNotifyCmd(const Cmd: SystemString);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendConsoleNotifyCmd(self, Cmd)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendConsoleNotifyCmd(Cmd);
end;

procedure TPeerIO.SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamNotifyCmd(self, Cmd, StreamData, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamNotifyCmd(Cmd, StreamData, DoneAutoFree);
end;

procedure TPeerIO.SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamNotifyCmd(self, Cmd, StreamData)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamNotifyCmd(Cmd, StreamData);
end;

procedure TPeerIO.SendStreamNotifyCmd(const Cmd: SystemString);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendStreamNotifyCmd(self, Cmd)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendStreamNotifyCmd(Cmd);
end;

function TPeerIO.WaitSendConsoleCmd(Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      Result := TZNet_Server(OwnerFramework).WaitSendConsoleCmd(self, Cmd, ConsoleData, TimeOut_)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      Result := TZNet_Client(OwnerFramework).WaitSendConsoleCmd(Cmd, ConsoleData, TimeOut_)
  else
      Result := '';
end;

procedure TPeerIO.WaitSendStreamCmd(const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).WaitSendStreamCmd(self, Cmd, StreamData, Result_, TimeOut_)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).WaitSendStreamCmd(Cmd, StreamData, Result_, TimeOut_);
end;

procedure TPeerIO.SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendBigStream(self, Cmd, BigStream, StartPos, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendBigStream(Cmd, BigStream, StartPos, DoneAutoFree);
end;

procedure TPeerIO.SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendBigStream(self, Cmd, BigStream, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendBigStream(Cmd, BigStream, DoneAutoFree);
end;

procedure TPeerIO.SendCompleteBuffer(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer(self, Cmd, buff, BuffSize, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer(Cmd, buff, BuffSize, DoneAutoFree);
end;

procedure TPeerIO.SendCompleteBuffer(const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer(self, Cmd, buff, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer(Cmd, buff, DoneAutoFree);
end;

procedure TPeerIO.SendCompleteBuffer(const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer(self, Cmd, buff, DoneAutoFree)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer(Cmd, buff, DoneAutoFree);
end;

procedure TPeerIO.SendCompleteBuffer(const Cmd: SystemString; buff: TDFE);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer(self, Cmd, buff)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer(Cmd, buff);
end;

procedure TPeerIO.SendCompleteBuffer_StreamNotify(const Cmd: SystemString; buff: TDFE);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer_StreamNotify(self, Cmd, buff)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer_StreamNotify(Cmd, buff);
end;

procedure TPeerIO.SendCompleteBuffer_NoWait_StreamM(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer_NoWait_StreamM(self, Cmd, buff, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer_NoWait_StreamM(Cmd, buff, OnResult);
end;

procedure TPeerIO.SendCompleteBuffer_NoWait_StreamP(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendCompleteBuffer_NoWait_StreamP(self, Cmd, buff, OnResult)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendCompleteBuffer_NoWait_StreamP(Cmd, buff, OnResult);
end;

procedure TPeerIO.Send_NULL();
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).Send_NULL(self)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).Send_NULL;
end;

procedure TPeerIO.SendNULL();
begin
  if OwnerFramework.InheritsFrom(TZNet_Server) then
      TZNet_Server(OwnerFramework).SendNULL(self)
  else if OwnerFramework.InheritsFrom(TZNet_Client) then
      TZNet_Client(OwnerFramework).SendNULL;
end;

procedure TAutomatedP2PVMServiceBind.AddService(Service: TZNet_WithP2PVM_Server; IPV6: SystemString; Port: Word);
var
  p: PAutomatedP2PVMServiceData;
begin
  New(p);
  p^.Service := Service;
  p^.Service.StartService(IPV6, Port);
  Add(p);
end;

procedure TAutomatedP2PVMServiceBind.AddService(Service: TZNet_WithP2PVM_Server);
var
  p: PAutomatedP2PVMServiceData;
begin
  New(p);
  p^.Service := Service;
  Add(p);
end;

procedure TAutomatedP2PVMServiceBind.RemoveService(Service: TZNet_WithP2PVM_Server);
var
  i: Integer;
begin
  for i := Count - 1 downto 0 do
    if Items[i]^.Service = Service then
      begin
        Dispose(Items[i]);
        Delete(i);
      end;
end;

procedure TAutomatedP2PVMServiceBind.Clean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
      Dispose(Items[i]);
  Clear;
end;

function TAutomatedP2PVMServiceBind.FoundService(Service: TZNet_WithP2PVM_Server): PAutomatedP2PVMServiceData;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to Count - 1 do
    if Items[i]^.Service = Service then
      begin
        Result := Items[i];
        exit;
      end;
end;

procedure TAutomatedP2PVMClientBind.AddClient(Client: TZNet_WithP2PVM_Client; IPV6: SystemString; Port: Word);
var
  p: PAutomatedP2PVMClientData;
begin
  New(p);
  p^.Client := Client;
  p^.IPV6 := IPV6;
  p^.Port := Port;
  p^.RequestConnecting := False;
  Add(p);
end;

procedure TAutomatedP2PVMClientBind.RemoveClient(Client: TZNet_WithP2PVM_Client);
var
  i: Integer;
begin
  for i := Count - 1 downto 0 do
    if Items[i]^.Client = Client then
      begin
        Dispose(Items[i]);
        Delete(i);
      end;
end;

procedure TAutomatedP2PVMClientBind.Clean;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
      Dispose(Items[i]);
  Clear;
end;

function TAutomatedP2PVMClientBind.FoundClient(Client: TZNet_WithP2PVM_Client): PAutomatedP2PVMClientData;
var
  i: Integer;
begin
  Result := nil;
  for i := 0 to Count - 1 do
    if Items[i]^.Client = Client then
      begin
        Result := Items[i];
        exit;
      end;
end;

procedure TZNet_Progress_Pool.DoFree(var data: TZNet_Progress);
begin
  if data = nil then
      exit;
  data.FPool_Ptr := nil;
  DisposeObjectAndNil(data);
end;

constructor TZNet_Progress.Create(OwnerFramework_: TZNet);
begin
  inherited Create;
  FOwnerFramework := OwnerFramework_;
  ResetEvent();
  NextProgressDoFree := False;
end;

destructor TZNet_Progress.Destroy;
var
  i: Integer;
begin
  i := 0;
  try
    if FPool_Ptr <> nil then
      begin
        FPool_Ptr^.data := nil;
        OwnerFramework.FProgress_Pool.Remove_P(FPool_Ptr);
      end;
    if Assigned(OnFree) then
        OnFree(self);
  except
  end;

  inherited Destroy;
end;

procedure TZNet_Progress.Progress;
begin
  try
    if Assigned(OnProgress_C) then
        OnProgress_C(self)
    else if Assigned(OnProgress_M) then
        OnProgress_M(self)
    else if Assigned(OnProgress_P) then
        OnProgress_P(self);
  except
  end;
end;

procedure TZNet_Progress.ResetEvent;
begin
  OnFree := nil;
  OnProgress_C := nil;
  OnProgress_M := nil;
  OnProgress_P := nil;
end;

procedure TZNet_Instance_Pool.Print_Status;
  procedure do_print_io_info(prefix_: SystemString; Net: TZNet);
  var
    p2p_info: SystemString;
    p2p_VM_Num: NativeInt;
    L: TCore_List;
    p: PUInt32HashListObjectStruct;
    i: Integer;
  begin
    if Net.IOPool.Num > 0 then
      with Net.IOPool.Repeat_ do
        repeat
          if Queue^.data^.data.Second.P2PVM = nil then
              p2p_VM_Num := 0
          else
              p2p_VM_Num := Queue^.data^.data.Second.P2PVM.FrameworkPool.Count;
          DoStatus(prefix_ + 'io:%d ip:%s p2pVM:%d', [Queue^.data^.data.Primary, Queue^.data^.data.Second.GetPeerIP, p2p_VM_Num]);
          if Queue^.data^.data.Second.P2PVM <> nil then
            begin
              L := TCore_List.Create;
              Queue^.data^.data.Second.P2PVM.FrameworkPool.GetListData(L);
              for i := 0 to L.Count - 1 do
                begin
                  p := L[i];
                  if (p <> nil) and (p^.data <> nil) and (p^.data is TZNet) then
                    begin
                      DoStatus(prefix_ + #9'pspVM:%s <%s> IO:%d', [p^.data.ClassName, TZNet(p^.data).name, TZNet(p^.data).IOPool.Num]);
                    end;
                end;
              DisposeObject(L);
            end;
        until not Next;
  end;

begin
  Lock;
  try
    if Num > 0 then
      begin
        with Repeat_ do
          repeat
            DoStatus('%s <%s> IO:%d, PPS:%f PCPU:%dms',
              [Queue^.data.ClassName, Queue^.data.name, Queue^.data.IOPool.Num, Queue^.data.Progress_CPS.CPS, Queue^.data.Progress_CPS.CPU_Time]);
            do_print_io_info(#9, Queue^.data);
          until not Next;
      end;
  finally
      UnLock;
  end;
end;

procedure TZNet_Instance_Pool.Print_Service_Statistics_Info;
  procedure do_print_statistics_info(prefix_: SystemString; Net: TZNet);
  var
    st: TStatisticsType;
  begin
    for st := low(TStatisticsType) to high(TStatisticsType) do
        DoStatus(prefix_ + '%s (state) = %d (Num)', [GetEnumName(TypeInfo(TStatisticsType), Ord(st)), Net.Statistics[st]]);

    if Net.CmdRecvStatistics.Num > 0 then
      begin
        Net.CmdRecvStatistics.Critical__.Lock;
        try
          with Net.CmdRecvStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + '%s (received cmd) = %d (Num)', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdRecvStatistics.Critical__.UnLock;
        end
      end;

    if Net.CmdSendStatistics.Num > 0 then
      begin
        Net.CmdSendStatistics.Critical__.Lock;
        try
          with Net.CmdSendStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + '%s (send cmd) = %d (Num)', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdSendStatistics.Critical__.UnLock;
        end
      end;
  end;

begin
  Lock;
  try
    if Num > 0 then
      begin
        with Repeat_ do
          repeat
            if Queue^.data is TZNet_Server then
              begin
                DoStatus('%s <%s> connected:%d, PPS:%f, PCPU:%dms, statistics:',
                  [Queue^.data.ClassName, Queue^.data.name, Queue^.data.IOPool.Num, Queue^.data.Progress_CPS.CPS, Queue^.data.Progress_CPS.CPU_Time]);
                do_print_statistics_info(#9, Queue^.data);
              end;
          until not Next;
      end;
  finally
      UnLock;
  end;
end;

procedure TZNet_Instance_Pool.Print_Service_CMD_Info;
  procedure do_print_cmd_info(prefix_: SystemString; Net: TZNet);
  begin
    if Net.CmdMaxExecuteConsumeStatistics.Num > 0 then
      begin
        Net.CmdMaxExecuteConsumeStatistics.Critical__.Lock;
        try
          with Net.CmdMaxExecuteConsumeStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + 'received cmd "%s": time %dms', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdMaxExecuteConsumeStatistics.Critical__.UnLock;
        end;
      end;
    if Net.CmdSendStatistics.Num > 0 then
      begin
        Net.CmdSendStatistics.Critical__.Lock;
        try
          with Net.CmdSendStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + 'send cmd "%s" =%d', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdSendStatistics.Critical__.UnLock;
        end;
      end;
  end;

begin
  Lock;
  try
    if Num > 0 then
      begin
        with Repeat_ do
          repeat
            if Queue^.data is TZNet_Server then
              begin
                DoStatus('%s <%s> connected: %d', [Queue^.data.ClassName, Queue^.data.name, Queue^.data.IOPool.Num]);
                do_print_cmd_info(#9, Queue^.data);
              end;
          until not Next;
      end;
  finally
      UnLock;
  end;
end;

procedure TZNet_Instance_Pool.Print_Client_Statistics_Info;
  procedure do_print_statistics_info(prefix_: SystemString; Net: TZNet);
  var
    st: TStatisticsType;
  begin
    for st := low(TStatisticsType) to high(TStatisticsType) do
        DoStatus(prefix_ + '%s (state) = %d (Num)', [GetEnumName(TypeInfo(TStatisticsType), Ord(st)), Net.Statistics[st]]);

    if Net.CmdRecvStatistics.Num > 0 then
      begin
        Net.CmdRecvStatistics.Critical__.Lock;
        try
          with Net.CmdRecvStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + '%s (received cmd) = %d (Num)', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdRecvStatistics.Critical__.UnLock;
        end
      end;

    if Net.CmdSendStatistics.Num > 0 then
      begin
        Net.CmdSendStatistics.Critical__.Lock;
        try
          with Net.CmdSendStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + '%s (send cmd) = %d (Num)', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdSendStatistics.Critical__.UnLock;
        end
      end;
  end;

var
  addr: SystemString;
begin
  Lock;
  try
    if Num > 0 then
      begin
        with Repeat_ do
          repeat
            if Queue^.data is TZNet_Client then
              begin
                if (TZNet_Client(Queue^.data).ClientIO <> nil) and (TZNet_Client(Queue^.data).Connected) then
                    addr := TZNet_Client(Queue^.data).ClientIO.GetPeerIP
                else
                    addr := '';
                DoStatus('%s <%s> connected:"%s", PPS:%f, PCPU:%dms, statistics:',
                  [Queue^.data.ClassName, Queue^.data.name, addr, Queue^.data.Progress_CPS.CPS, Queue^.data.Progress_CPS.CPU_Time]);
                do_print_statistics_info(#9, Queue^.data);
              end;
          until not Next;
      end;
  finally
      UnLock;
  end;
end;

procedure TZNet_Instance_Pool.Print_Client_CMD_Info;
  procedure do_print_cmd_info(prefix_: SystemString; Net: TZNet);
  begin
    if Net.CmdMaxExecuteConsumeStatistics.Num > 0 then
      begin
        Net.CmdMaxExecuteConsumeStatistics.Critical__.Lock;
        try
          with Net.CmdMaxExecuteConsumeStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + '"%s": time %dms', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdMaxExecuteConsumeStatistics.Critical__.UnLock;
        end;
      end;
    if Net.CmdSendStatistics.Num > 0 then
      begin
        Net.CmdSendStatistics.Critical__.Lock;
        try
          with Net.CmdSendStatistics.Repeat_ do
            repeat
                DoStatus(prefix_ + 'send cmd "%s" =%d', [Queue^.data^.data.Primary, Queue^.data^.data.Second]);
            until not Next;
        finally
            Net.CmdSendStatistics.Critical__.UnLock;
        end;
      end;
  end;

var
  addr: SystemString;
begin
  Lock;
  try
    if Num > 0 then
      begin
        with Repeat_ do
          repeat
            if Queue^.data is TZNet_Client then
              begin
                if (TZNet_Client(Queue^.data).ClientIO <> nil) and (TZNet_Client(Queue^.data).Connected) then
                    addr := TZNet_Client(Queue^.data).ClientIO.GetPeerIP
                else
                    addr := '';
                DoStatus('%s <%s> connected: "%s"', [Queue^.data.ClassName, Queue^.data.name, addr]);
                do_print_cmd_info(#9, Queue^.data);
              end;
          until not Next;
      end;
  finally
      UnLock;
  end;
end;

procedure TCommand_Tick_Hash_Pool.SetMax(Key_: SystemString; Value_: TTimeTick);
var
  p: TCommand_Tick_Hash_Pool.PValue;
begin
  p := Get_Value_Ptr(Key_, 0);
  if Value_ > p^ then
      p^ := Value_;
end;

procedure TCommand_Tick_Hash_Pool.SetMax(Source: TCommand_Tick_Hash_Pool);
var
  __repeat__: TCommand_Tick_Hash_Pool.TRepeat___;
begin
  if Source.Num <= 0 then
      exit;
  __repeat__ := Source.Repeat_;
  repeat
      SetMax(__repeat__.Queue^.data^.data.Primary, __repeat__.Queue^.data^.data.Second);
  until not __repeat__.Next;
end;

procedure TCommand_Tick_Hash_Pool.GetKeyList(output: TPascalStringList);
var
  __repeat__: TCommand_Tick_Hash_Pool.TRepeat___;
begin
  if Num <= 0 then
      exit;
  __repeat__ := Repeat_;
  repeat
      output.Add(__repeat__.Queue^.data^.data.Primary);
  until not __repeat__.Next;
end;

procedure TCommand_Num_Hash_Pool.IncValue(Key_: SystemString; Value_: Integer);
var
  p: TCommand_Num_Hash_Pool.PValue;
begin
  p := Get_Value_Ptr(Key_, 0);
  inc(p^, Value_);
end;

procedure TCommand_Num_Hash_Pool.IncValue(Source: TCommand_Num_Hash_Pool);
var
  __repeat__: TCommand_Num_Hash_Pool.TRepeat___;
begin
  if Source.Num <= 0 then
      exit;
  __repeat__ := Source.Repeat_;
  repeat
      IncValue(__repeat__.Queue^.data^.data.Primary, __repeat__.Queue^.data^.data.Second);
  until not __repeat__.Next;
end;

procedure TCommand_Num_Hash_Pool.GetKeyList(output: TPascalStringList);
var
  __repeat__: TCommand_Num_Hash_Pool.TRepeat___;
begin
  if Num <= 0 then
      exit;
  __repeat__ := Repeat_;
  repeat
      output.Add(__repeat__.Queue^.data^.data.Primary);
  until not __repeat__.Next;
end;

procedure TCommand_Hash_Pool.DoFree(var Key: SystemString; var Value: TCommand_base);
begin
  DisposeObjectAndNil(Value);
  inherited DoFree(Key, Value);
end;

procedure TZNet.DoPrint(const v: SystemString);
var
  n1, n2: SystemString;
begin
  if not FQuietMode then
    begin
      if FPrefixName <> '' then
          n1 := FPrefixName
      else
          n1 := '';
      if FName <> '' then
        begin
          if n1 <> '' then
              n1 := n1 + '.';
          n2 := FName + ' ';
        end
      else
          n2 := '';
      DoStatus(n1 + n2 + v, ZNet_Def_DoStatusID);
    end;
end;

procedure TZNet.DoError(const v: SystemString);
var
  n1, n2: SystemString;
begin
  if FPrefixName <> '' then
      n1 := FPrefixName
  else
      n1 := '';
  if FName <> '' then
    begin
      if n1 <> '' then
          n1 := n1 + '.';
      n2 := FName + ' ';
    end
  else
      n2 := '';
  DoStatus(n1 + n2 + v, ZNet_Def_DoStatusID);
end;

procedure TZNet.DoWarning(const v: SystemString);
var
  n1, n2: SystemString;
begin
  if FPrefixName <> '' then
      n1 := FPrefixName
  else
      n1 := '';
  if FName <> '' then
    begin
      if n1 <> '' then
          n1 := n1 + '.';
      n2 := FName + ' ';
    end
  else
      n2 := '';
  DoStatus(n1 + n2 + v, ZNet_Def_DoStatusID);
end;

function TZNet.GetIdleTimeOut: TTimeTick;
begin
  Result := FIdleTimeOut;
end;

procedure TZNet.SetIdleTimeOut(const Value: TTimeTick);
begin
  FIdleTimeOut := Value;
end;

function TZNet.CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  Result := True;
  if Assigned(FOnExecuteCommand) then
    begin
      try
          FOnExecuteCommand(Sender, Cmd, Result);
      except
      end;
    end;
  if Result then
      AtomInc(Statistics[TStatisticsType.stCommandExecute_Sum]);
end;

function TZNet.CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  Result := True;
  if Assigned(FOnSendCommand) then
    begin
      try
          FOnSendCommand(Sender, Cmd, Result);
      except
      end;
    end;
  if Result then
      AtomInc(Statistics[TStatisticsType.stCommand_Send_Sum]);
end;

function TZNet.CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean;
begin
  Result := True;
  AtomInc(Statistics[TStatisticsType.stCommand_Reg_Sum]);
end;

procedure TZNet.DelayClose(Sender: TN_Post_Execute);
var
  IO_ID: Cardinal;
  c_IO: TPeerIO;
begin
  IO_ID := Sender.Data3;
  c_IO := FPeerIO_HashPool[IO_ID];
  if c_IO <> nil then
    begin
      c_IO.Disconnect;
    end;
end;

procedure TZNet.DelayFree(Sender: TN_Post_Execute);
var
  IO_ID: Cardinal;
  c_IO: TPeerIO;
begin
  IO_ID := Sender.Data3;
  c_IO := FPeerIO_HashPool[IO_ID];
  if c_IO <> nil then
      DisposeObject(c_IO);
end;

procedure TZNet.DelayExecuteOnResultState(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
  nQueue: PQueueData;
begin
  P_IO := FPeerIO_HashPool[Sender.Data4];
  nQueue := PQueueData(Sender.Data5);

  if P_IO <> nil then
    begin
      DoExecuteResult(P_IO, nQueue, Sender.Data3, Sender.DataEng);
    end;

  DisposeQueueData(nQueue);
end;

procedure TZNet.DelayExecuteOnCompleteBufferState(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
  Cmd: SystemString;
  CompleteBuff: TMS64;
begin
  P_IO := FPeerIO_HashPool[Sender.Data3];
  Cmd := Sender.Data4;

  if P_IO <> nil then
    begin
      CompleteBuff := TMS64(Sender.Data1);
      if not QuietMode then
          P_IO.PrintCommand('execute complete buffer(delay): %s', Cmd);

      P_IO.FCompleteBuffer_Current_Trigger := CompleteBuff;
      ExecuteCompleteBuffer(P_IO, Cmd, CompleteBuff.Memory, CompleteBuff.Size);
      DisposeObject(CompleteBuff);

      CmdRecvStatistics.IncValue(Cmd, 1);
    end;
end;

procedure TZNet.IDLE_Trace_Execute(Sender: TN_Post_Execute);
var
  p: PIDLE_Trace;
  p_id: Cardinal;
  P_IO: TPeerIO;
begin
  p := Sender.Data5;
  p_id := p^.ID;

  P_IO := FPeerIO_HashPool[p_id];

  if P_IO <> nil then
    begin
      if P_IO.IOBusy then
        begin
          with ProgressEngine.PostExecuteM(False, 0.1, IDLE_Trace_Execute) do
            begin
              Data4 := p_id;
              Data5 := p;
              Ready();
            end;
        end
      else
        begin
          if Assigned(p^.OnNotifyC) then
              p^.OnNotifyC(p^.data)
          else if Assigned(p^.OnNotifyM) then
              p^.OnNotifyM(p^.data)
          else if Assigned(p^.OnNotifyP) then
              p^.OnNotifyP(p^.data);
          Dispose(p);
        end;
    end
  else
    begin
      Dispose(p);
    end;
end;

procedure TZNet.cmd_Complete_Buffer_Stream_Reponse(Sender: TPeerIO; InData: PByte; DataSize: NativeInt);
var
  u64: UInt64;
  p: PCommandCompleteBuffer_NoWait_Stream_Data;
  In_DFE: TDFE;
  P_IO: TPeerIO;
begin
  u64 := PUInt64(InData)^;
  p := PCommandCompleteBuffer_NoWait_Stream_Data(u64);
  P_IO := FPeerIO_HashPool[p^.ID];

  if P_IO <> nil then
    begin
      In_DFE := TDFE.Create;
      In_DFE.DecodeFromMemory(GetOffset(InData, 8), DataSize - 8, True);
      try
        if Assigned(p^.OnStreamM) then
            p^.OnStreamM(P_IO, In_DFE)
        else if Assigned(p^.OnStreamP) then
            p^.OnStreamP(P_IO, In_DFE);
      except
      end;
      DisposeObject(In_DFE);
    end;

  Dispose(p);
end;

function TZNet.MakeID: Cardinal;
begin
  repeat
    Result := FIDSeed;
    AtomInc(FIDSeed);
  until not FPeerIO_HashPool.Exists_Key(Result);
end;

procedure TZNet.FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
end;

procedure TZNet.Framework_Internal_Send_Byte_Buffer(const Sender: TPeerIO; const buff: PByte; siz: NativeInt);
var
  p: PByte;
begin
  if siz <= 0 then
      exit;

  AtomInc(Statistics[TStatisticsType.stSendSize], siz);

  p := buff;

  { fill fragment }
  while siz > FSendFlushSize do
    begin
      Sender.Write_IO_Buffer(p, FSendFlushSize);
      inc(p, FSendFlushSize);
      dec(siz, FSendFlushSize);
    end;

  if siz > 0 then
    begin
      Sender.Write_IO_Buffer(p, siz);
    end;

  Sender.UpdateLastCommunicationTime;
  Sender.LastCommunicationTick_Sending := Sender.FLastCommunicationTick;
end;

procedure TZNet.Framework_Internal_Save_Receive_Buffer(const Sender: TPeerIO; const buff: Pointer; siz: Int64);
begin
  if siz > 0 then
    begin
      Sender.Internal_Save_Receive_Buffer(buff, siz);
    end;
end;

procedure TZNet.Framework_Internal_Process_Receive_Buffer(const Sender: TPeerIO);
var
  FillDone: Boolean;
begin
  if FProtocol = cpCustom then
    begin
      if Sender.FReceivedBuffer.Size > 0 then
        begin
          FillDone := True;
          FillCustomBuffer(Sender, Sender.FReceivedBuffer.Memory, Sender.FReceivedBuffer.Size, FillDone);

          if FillDone then
              Sender.FReceivedBuffer.Clear
          else
              Sender.Internal_Process_Receive_Buffer();
        end;
    end
  else
      Sender.Internal_Process_Receive_Buffer();
end;

procedure TZNet.Framework_Internal_Process_Send_Buffer(const Sender: TPeerIO);
begin
  Sender.Internal_Process_Send_Buffer();
end;

procedure TZNet.Framework_Internal_IO_Create(const Sender: TPeerIO);
begin
  if FIOInterface <> nil then
      FIOInterface.PeerIO_Create(Sender);
end;

procedure TZNet.Framework_Internal_IO_Destroy(const Sender: TPeerIO);
begin
  if FIOInterface <> nil then
      FIOInterface.PeerIO_Destroy(Sender);
end;

procedure TZNet.Build_P2PAuth_Token_Result_On_IO_IDLE(Sender: TCore_Object);
var
  P_IO: TPeerIO;
begin
  P_IO := TPeerIO(Sender);

  try
    if Assigned(P_IO.OnVMBuildAuthModelResult_C) then
        P_IO.OnVMBuildAuthModelResult_C()
    else if Assigned(P_IO.OnVMBuildAuthModelResult_M) then
        P_IO.OnVMBuildAuthModelResult_M()
    else if Assigned(P_IO.OnVMBuildAuthModelResult_P) then
        P_IO.OnVMBuildAuthModelResult_P()
    else if Assigned(P_IO.OnVMBuildAuthModelResultIO_C) then
        P_IO.OnVMBuildAuthModelResultIO_C(P_IO)
    else if Assigned(P_IO.OnVMBuildAuthModelResultIO_M) then
        P_IO.OnVMBuildAuthModelResultIO_M(P_IO)
    else if Assigned(P_IO.OnVMBuildAuthModelResultIO_P) then
        P_IO.OnVMBuildAuthModelResultIO_P(P_IO);
  except
  end;

  P_IO.OnVMBuildAuthModelResult_C := nil;
  P_IO.OnVMBuildAuthModelResult_M := nil;
  P_IO.OnVMBuildAuthModelResult_P := nil;
  P_IO.OnVMBuildAuthModelResultIO_C := nil;
  P_IO.OnVMBuildAuthModelResultIO_M := nil;
  P_IO.OnVMBuildAuthModelResultIO_P := nil;
end;

procedure TZNet.Do_CMD_Result_BuildP2PAuthToken(Sender: TPeerIO; Result_: TDFE);
var
  i: Integer;
  arr32: TDF_ArrayInteger;
  CS: TCipherSecurity;
  arr8: TDF_ArrayByte;
begin
  { read auth buffer }
  arr32 := Result_.R.ReadArrayInteger;
  SetLength(Sender.FP2PVM_Auth_Token, arr32.Count * 4);
  for i := 0 to arr32.Count - 1 do
      PInteger(@Sender.FP2PVM_Auth_Token[i * 4])^ := arr32[i];

  { read p2pVM cipher style }
  CS := TCipherSecurity(Result_.R.ReadByte);

  { read p2pVM cipher key }
  arr8 := Result_.R.ReadArrayByte;
  SetLength(Sender.FP2PVM_Cipher_Key, arr8.Count);
  arr8.GetBuff(@Sender.FP2PVM_Cipher_Key[0]);

  { build p2pVM cipher instance }
  Sender.FP2PVM_Cipher := CreateCipherClassFromBuffer(CS, Sender.FP2PVM_Cipher_Key);

  Sender.IO_IDLE_TraceM(Sender, Build_P2PAuth_Token_Result_On_IO_IDLE);
end;

procedure TZNet.CMD_BuildP2PAuthToken(Sender: TPeerIO; InData, OutData: TDFE);
var
  i: Integer;
  seed: Integer;
  arry32: TDF_ArrayInteger;
  CS: TCipherSecurity;
begin
  Sender.ResetSequencePacketBuffer;
  Sender.FSequencePacketSignal := False;

  { build auth buffer }
  seed := InData.Reader.ReadInteger;
  arry32 := OutData.WriteArrayInteger;
  for i := ZNet_Def_VMAuthSize - 1 downto 0 do
      arry32.Add(TMISC.Ran03(seed));
  SetLength(Sender.FP2PVM_Auth_Token, arry32.Count * 4);
  for i := 0 to arry32.Count - 1 do
      PInteger(@Sender.FP2PVM_Auth_Token[i * 4])^ := arry32[i];

  { build p2pVM cipher style }
  if FEncrypt_P2PVM_Packet then
      CS := TCipher.Random_Select_Cipher([csRC6, csSerpent, csMars, csRijndael, csTwoFish, csAES128])
  else
      CS := csNone;
  OutData.WriteByte(Byte(CS));

  { build p2pVM cipher key }
  SetLength(Sender.FP2PVM_Cipher_Key, 256);
  TMT19937.Rand32(MaxInt, @Sender.FP2PVM_Cipher_Key[0], 256 div 4);
  OutData.WriteArrayByte.SetBuff(@Sender.FP2PVM_Cipher_Key[0], 256);

  { build p2pVM cipher instance }
  Sender.FP2PVM_Cipher := CreateCipherClassFromBuffer(CS, Sender.FP2PVM_Cipher_Key);
end;

procedure TZNet.CMD_InitP2PTunnel(Sender: TPeerIO; InData: SystemString);
var
  Accept: Boolean;
begin
  if Sender.FP2PVMTunnel <> nil then
      exit;

  Accept := False;
  p2pVMTunnelAuth(Sender, InData, Accept);
  if not Accept then
      exit;

  Sender.ResetSequencePacketBuffer;
  Sender.FSequencePacketSignal := False;

  Sender.OpenP2PVMTunnel(16, False, '');
  Sender.P2PVMTunnel.AuthVM;
  p2pVMTunnelOpenBefore(Sender, Sender.P2PVMTunnel);
end;

procedure TZNet.CMD_CloseP2PTunnel(Sender: TPeerIO; InData: SystemString);
begin
  Sender.Internal_Close_P2PVMTunnel;
  Sender.ResetSequencePacketBuffer;
end;

procedure TZNet.VMAuthSuccessAfterDelayExecute(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
begin
  P_IO := FPeerIO_HashPool[Sender.Data3];
  if P_IO = nil then
      exit;

  try
    if Assigned(P_IO.OnVMAuthResult_C) then
        P_IO.OnVMAuthResult_C(True)
    else if Assigned(P_IO.OnVMAuthResult_M) then
        P_IO.OnVMAuthResult_M(True)
    else if Assigned(P_IO.OnVMAuthResult_P) then
        P_IO.OnVMAuthResult_P(True)
    else if Assigned(P_IO.OnVMAuthResultIO_C) then
        P_IO.OnVMAuthResultIO_C(P_IO, True)
    else if Assigned(P_IO.OnVMAuthResultIO_M) then
        P_IO.OnVMAuthResultIO_M(P_IO, True)
    else if Assigned(P_IO.OnVMAuthResultIO_P) then
        P_IO.OnVMAuthResultIO_P(P_IO, True);
  except
  end;

  P_IO.OnVMAuthResult_C := nil;
  P_IO.OnVMAuthResult_M := nil;
  P_IO.OnVMAuthResult_P := nil;
  P_IO.OnVMAuthResultIO_C := nil;
  P_IO.OnVMAuthResultIO_M := nil;
  P_IO.OnVMAuthResultIO_P := nil;
  p2pVMTunnelOpenAfter(P_IO, P_IO.P2PVMTunnel);
end;

procedure TZNet.VMAuthSuccessDelayExecute(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
begin
  P_IO := FPeerIO_HashPool[Sender.Data3];
  if P_IO = nil then
      exit;

  with ProgressPost.PostExecuteM(False, 0.5, VMAuthSuccessAfterDelayExecute) do
    begin
      Data3 := P_IO.FID;
      Ready();
    end;
  p2pVMTunnelOpen(P_IO, P_IO.P2PVMTunnel);
end;

procedure TZNet.VMAuthFailedDelayExecute(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
begin
  P_IO := FPeerIO_HashPool[Sender.Data3];
  if P_IO = nil then
      exit;

  try
    if Assigned(P_IO.OnVMAuthResult_C) then
        P_IO.OnVMAuthResult_C(False)
    else if Assigned(P_IO.OnVMAuthResult_M) then
        P_IO.OnVMAuthResult_M(False)
    else if Assigned(P_IO.OnVMAuthResult_P) then
        P_IO.OnVMAuthResult_P(False)
    else if Assigned(P_IO.OnVMAuthResultIO_C) then
        P_IO.OnVMAuthResultIO_C(P_IO, False)
    else if Assigned(P_IO.OnVMAuthResultIO_M) then
        P_IO.OnVMAuthResultIO_M(P_IO, False)
    else if Assigned(P_IO.OnVMAuthResultIO_P) then
        P_IO.OnVMAuthResultIO_P(P_IO, False);
  except
  end;

  P_IO.OnVMAuthResult_C := nil;
  P_IO.OnVMAuthResult_M := nil;
  P_IO.OnVMAuthResult_P := nil;
  P_IO.OnVMAuthResultIO_C := nil;
  P_IO.OnVMAuthResultIO_M := nil;
  P_IO.OnVMAuthResultIO_P := nil;
end;

procedure TZNet.CMD_NULL(Sender: TPeerIO; InData: SystemString; var OutData: SystemString);
begin
end;

function TZNet.ExecuteConsole(Sender: TPeerIO; const Cmd: SystemString; const InData: SystemString; var OutData: SystemString): Boolean;
var
  cmd_instance_: TCommand_base;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists console cmd: %s', Cmd);
      exit;
    end;
  if not cmd_instance_.InheritsFrom(TCommandConsole) then
    begin
      if cmd_instance_.InheritsFrom(TCommandConsoleNotify) then // compatible fixed, by.qq600585
        begin
          Result := TCommandConsoleNotify(cmd_instance_).Execute(Sender, InData);
          if not Result then
              ErrorParam('exception from cmd: %s', Cmd);
        end
      else ErrorParam('Illegal interface in cmd: %s', Cmd);
      exit;
    end;
  Result := TCommandConsole(cmd_instance_).Execute(Sender, InData, OutData);
  if not Result then
      ErrorParam('exception from cmd: %s', Cmd);
end;

function TZNet.ExecuteStream(Sender: TPeerIO; const Cmd: SystemString; InData, OutData: TDFE): Boolean;
var
  cmd_instance_: TCommand_base;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists stream cmd: %s', Cmd);
      exit;
    end;
  if not cmd_instance_.InheritsFrom(TCommandStream) then
    begin
      ErrorParam('Illegal interface in cmd: %s', Cmd);
      exit;
    end;
  InData.Reader.index := 0;
  Result := TCommandStream(cmd_instance_).Execute(Sender, InData, OutData);
  if not Result then
      ErrorParam('exception from cmd: %s', Cmd);
end;

function TZNet.ExecuteStreamNotify(Sender: TPeerIO; const Cmd: SystemString; InData: TDFE): Boolean;
var
  cmd_instance_: TCommand_base;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists direct stream cmd: %s', Cmd);
      exit;
    end;
  if not cmd_instance_.InheritsFrom(TCommandStreamNotify) then
    begin
      ErrorParam('Illegal interface in cmd: %s', Cmd);
      exit;
    end;
  InData.Reader.index := 0;
  Result := TCommandStreamNotify(cmd_instance_).Execute(Sender, InData);
  if not Result then
      ErrorParam('exception from cmd: %s', Cmd);
end;

function TZNet.ExecuteConsoleNotify(Sender: TPeerIO; const Cmd: SystemString; const InData: SystemString): Boolean;
var
  cmd_instance_: TCommand_base;
  tmp: SystemString;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists direct console cmd: %s', Cmd);
      exit;
    end;
  if not cmd_instance_.InheritsFrom(TCommandConsoleNotify) then
    begin
      if cmd_instance_.InheritsFrom(TCommandConsole) then // compatible fixed, by.qq600585
        begin
          tmp := '';
          Result := TCommandConsole(cmd_instance_).Execute(Sender, InData, tmp);
          if not Result then
              ErrorParam('exception from cmd: %s', Cmd);
        end
      else ErrorParam('Illegal interface in cmd: %s', Cmd);
      exit;
    end;
  Result := TCommandConsoleNotify(cmd_instance_).Execute(Sender, InData);
  if not Result then
      ErrorParam('exception from cmd: %s', Cmd);
end;

function TZNet.ExecuteBigStream(Sender: TPeerIO; const Cmd: SystemString; InData: TCore_Stream; BigStreamTotal, BigStreamCompleteSize: Int64): Boolean;
var
  cmd_instance_: TCommand_base;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists Big Stream cmd: %s', Cmd);
      exit;
    end;
  if not cmd_instance_.InheritsFrom(TCommandBigStream) then
    begin
      ErrorParam('Illegal interface in cmd: %s', Cmd);
      exit;
    end;
  Result := TCommandBigStream(cmd_instance_).Execute(Sender, InData, BigStreamTotal, BigStreamCompleteSize);
  if not Result then
      ErrorParam('exception from cmd: %s', Cmd);
end;

function TZNet.ExecuteCompleteBuffer(Sender: TPeerIO; const Cmd: SystemString; InData: PByte; DataSize: NativeInt): Boolean;
var
  cmd_instance_: TCommand_base;
  tmp: TDFE;
begin
  Result := False;
  if not CanExecuteCommand(Sender, Cmd) then
      exit;
  cmd_instance_ := FCommand_Hash_Pool[Cmd];
  if cmd_instance_ = nil then
    begin
      ErrorParam('no exists complete buffer cmd: %s', Cmd);
      exit;
    end;
  if cmd_instance_.InheritsFrom(TCommandCompleteBuffer) then
    begin
      Result := TCommandCompleteBuffer(cmd_instance_).Execute(Sender, InData, DataSize);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else if cmd_instance_.InheritsFrom(TCommandCompleteBuffer_StreamNotify) then
    begin
      Result := TCommandCompleteBuffer_StreamNotify(cmd_instance_).Execute(Sender, InData, DataSize);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else if cmd_instance_.InheritsFrom(TCommandCompleteBuffer_NoWait_Stream) then
    begin
      Result := TCommandCompleteBuffer_NoWait_Stream(cmd_instance_).Execute(Sender, InData, DataSize);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else if cmd_instance_.InheritsFrom(TCommandCompleteBuffer_NoWait_Bridge_Stream) then
    begin
      Result := TCommandCompleteBuffer_NoWait_Bridge_Stream(cmd_instance_).Execute(Sender, InData, DataSize);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else if cmd_instance_.InheritsFrom(TCommandStreamNotify) then
    begin
      tmp := TDFE.Create;
      try
        tmp.DecodeFromMemory(InData, DataSize, True);
        Result := TCommandStreamNotify(cmd_instance_).Execute(Sender, tmp);
      except
          Result := False;
      end;
      DisposeObject(tmp);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else if cmd_instance_.InheritsFrom(TCommandStream) then
    begin
      Result := TCommandStream(cmd_instance_).Execute_Complete_Stream(Sender, InData, DataSize);
      if not Result then
          ErrorParam('exception from cmd: %s', Cmd);
    end
  else
      ErrorParam('Illegal interface in cmd: %s', Cmd);
end;

procedure TZNet.InitAutomatedP2PVM;
begin
  FAutomatedP2PVMServiceBind := TAutomatedP2PVMServiceBind.Create;
  FAutomatedP2PVMService := True;
  FAutomatedP2PVMClientBind := TAutomatedP2PVMClientBind.Create;
  FAutomatedP2PVMClient := True;
  FAutomatedP2PVMClientDelayBoot := 0.5;
  FAutomatedP2PVMAuthToken := 'AutomatedP2PVM for ZServer';
  FOnAutomatedP2PVMClientConnectionDone_C := nil;
  FOnAutomatedP2PVMClientConnectionDone_M := nil;
  FOnAutomatedP2PVMClientConnectionDone_P := nil;
end;

procedure TZNet.FreeAutomatedP2PVM;
begin
  FAutomatedP2PVMServiceBind.Clean;
  DisposeObject(FAutomatedP2PVMServiceBind);
  FAutomatedP2PVMClientBind.Clean;
  DisposeObject(FAutomatedP2PVMClientBind);
end;

procedure TZNet.DoAutomatedP2PVMClient_DelayRequest(Sender: TN_Post_Execute);
var
  IO_ID: Cardinal;
begin
  IO_ID := Sender.Data3;
  DoAutomatedP2PVMClient_Request(IO_ID);
end;

procedure TZNet.DoAutomatedP2PVMClient_Request(IO_ID: Cardinal);
var
  P_IO: TPeerIO;
begin
  P_IO := FPeerIO_HashPool[IO_ID];
  if P_IO = nil then
    begin
      Error('AutomatedP2PVMClient_Request request fialed: loss IO');
      exit;
    end;
  if P_IO.OwnerFramework <> self then
      RaiseInfo('illegal.');

  if FAutomatedP2PVMClient then
    begin
      if P_IO.p2pVMTunnelReadyOk then
          AutomatedP2PVMClient_OpenP2PVMTunnelResult(P_IO, True)
      else
          P_IO.BuildP2PAuthTokenIO_M(AutomatedP2PVMClient_BuildP2PAuthTokenResult);
    end
  else
      Error('AutomatedP2PVMClient is false, on do AutomatedP2PVMClient_Request dont work.');
end;

procedure TZNet.AutomatedP2PVMClient_BuildP2PAuthTokenResult(P_IO: TPeerIO);
begin
  if P_IO <> nil then
      P_IO.OpenP2PVMTunnelIO_M(True, GenerateQuantumCryptographyPassword(FAutomatedP2PVMAuthToken), AutomatedP2PVMClient_OpenP2PVMTunnelResult);
end;

procedure TZNet.AutomatedP2PVMClient_OpenP2PVMTunnelResult(P_IO: TPeerIO; VMauthState: Boolean);
var
  p: PAutomatedP2PVMClientData;
  i: Integer;
  IsRequestConnecting_: Boolean;
begin
  if not VMauthState then
    begin
      Error('Automated P2PVM Auth failed!');
      if P_IO <> nil then
          P_IO.DelayClose(1.0);
      exit;
    end;

  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
      P_IO.P2PVMTunnel.InstallLogicFramework(FAutomatedP2PVMClientBind[i]^.Client);

  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
    begin
      p := FAutomatedP2PVMClientBind[i];
      if (not p^.Client.Connected) and (not p^.RequestConnecting) then
        begin
          p^.Client.AsyncConnectM(p^.IPV6, p^.Port, p, P_IO, AutomatedP2PVMClient_ConnectionResult);
          p^.RequestConnecting := True;
        end;
    end;

  { check all connection done. }
  IsRequestConnecting_ := False;
  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
    begin
      p := FAutomatedP2PVMClientBind[i];
      if (p^.RequestConnecting) or (not p^.Client.Connected) then
          IsRequestConnecting_ := True;
    end;

  if not IsRequestConnecting_ then
      AutomatedP2PVMClient_Done(P_IO);
end;

procedure TZNet.AutomatedP2PVMClient_ConnectionResult(Param1: Pointer; Param2: TObject; const ConnectionState: Boolean);
var
  P_IO: TPeerIO;
  p: PAutomatedP2PVMClientData;
  i: Integer;
  IsRequestConnecting_: Boolean;
begin
  p := Param1;
  p^.RequestConnecting := False;
  if not ConnectionState then
    begin
      Error('Automated P2PVM connection failed.');
      exit;
    end;

  P_IO := TPeerIO(Param2);
  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
    begin
      p := FAutomatedP2PVMClientBind[i];
      if (not p^.Client.Connected) and (not p^.RequestConnecting) then
        begin
          p^.Client.AsyncConnectM(p^.IPV6, p^.Port, p, P_IO, AutomatedP2PVMClient_ConnectionResult);
          p^.RequestConnecting := True;
        end;
    end;

  { check all connection done. }
  IsRequestConnecting_ := False;
  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
    begin
      p := FAutomatedP2PVMClientBind[i];
      if (p^.RequestConnecting) or (not p^.Client.Connected) then
          IsRequestConnecting_ := True;
    end;

  if not IsRequestConnecting_ then
      AutomatedP2PVMClient_Done(P_IO);
end;

procedure TZNet.AutomatedP2PVMClient_Delay_Done(Sender: TN_Post_Execute);
var
  P_IO: TPeerIO;
begin
  P_IO := FPeerIO_HashPool[Sender.Data3];
  if P_IO = nil then
    begin
      PrintError('Async Loss IO.');
      exit;
    end;

  if not QuietMode then
      Print('Automated P2PVM client connection done.');
  try
    if Assigned(FOnAutomatedP2PVMClientConnectionDone_C) then
        FOnAutomatedP2PVMClientConnectionDone_C(self, P_IO)
    else if Assigned(FOnAutomatedP2PVMClientConnectionDone_M) then
        FOnAutomatedP2PVMClientConnectionDone_M(self, P_IO)
    else if Assigned(FOnAutomatedP2PVMClientConnectionDone_P) then
        FOnAutomatedP2PVMClientConnectionDone_P(self, P_IO);
  except
  end;
  FOnAutomatedP2PVMClientConnectionDone_C := nil;
  FOnAutomatedP2PVMClientConnectionDone_M := nil;
  FOnAutomatedP2PVMClientConnectionDone_P := nil;

  try
    if Assigned(P_IO.FOnAutomatedP2PVMClientConnectionDone_C) then
        P_IO.FOnAutomatedP2PVMClientConnectionDone_C(P_IO, AutomatedP2PVMClientConnectionDone(P_IO))
    else if Assigned(P_IO.FOnAutomatedP2PVMClientConnectionDone_M) then
        P_IO.FOnAutomatedP2PVMClientConnectionDone_M(P_IO, AutomatedP2PVMClientConnectionDone(P_IO))
    else if Assigned(P_IO.FOnAutomatedP2PVMClientConnectionDone_P) then
        P_IO.FOnAutomatedP2PVMClientConnectionDone_P(P_IO, AutomatedP2PVMClientConnectionDone(P_IO));
  except
  end;

  P_IO.FOnAutomatedP2PVMClientConnectionDone_C := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_M := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_P := nil;
end;

procedure TZNet.AutomatedP2PVMClient_Done(P_IO: TPeerIO);
begin
  with FPostProgress.PostExecuteM(False, 0, AutomatedP2PVMClient_Delay_Done) do
    begin
      Data3 := P_IO.ID;
      Ready();
    end;
end;

procedure TZNet.InitLargeScaleIOPool;
begin
  FProgress_LargeScale_IO_Pool := TIO_Order.Create;
  FProgressMaxDelay := ZNet_Progress_Max_Delay;
end;

procedure TZNet.FreeLargeScaleIOPool;
begin
  DisposeObject(FProgress_LargeScale_IO_Pool);
end;

procedure TZNet.ProgressLargeScaleIOPool;
var
  tk: TTimeTick;
  P_IO: TPeerIO;
begin
  if FPeerIO_HashPool.Num <= 0 then
    begin
      while FSend_Queue_Swap_Pool.Num > 0 do
        begin
          PrintError('loss send queue dest ip %s cmd %s', [FSend_Queue_Swap_Pool.First^.data^.IP, FSend_Queue_Swap_Pool.First^.data^.Cmd]);
          DisposeQueueData(FSend_Queue_Swap_Pool.First^.data);
          FSend_Queue_Swap_Pool.Next;
        end;
      exit;
    end;

  tk := GetTimeTick();
  if (FProgress_LargeScale_IO_Pool.Num <= 0) or (FProgressMaxDelay = 0) then
    begin
      { queue swap technology }
      while (FSend_Queue_Swap_Pool.Num > 0) do
        begin
          if self is TZNet_Client then
            begin
              if TZNet_Client(self).ClientIO <> nil then
                  TZNet_Client(self).ClientIO.PostQueueData(FSend_Queue_Swap_Pool.First^.data)
              else
                begin
                  PrintError('loss send queue cmd %s', [FSend_Queue_Swap_Pool.First^.data^.Cmd]);
                  DisposeQueueData(FSend_Queue_Swap_Pool.First^.data);
                end;
            end
          else if self is TZNet_Server then
            begin
              P_IO := FPeerIO_HashPool[FSend_Queue_Swap_Pool.First^.data^.IO_ID];
              if P_IO <> nil then
                  P_IO.PostQueueData(FSend_Queue_Swap_Pool.First^.data)
              else
                begin
                  PrintError('loss send queue dest ip %s cmd %s', [FSend_Queue_Swap_Pool.First^.data^.IP, FSend_Queue_Swap_Pool.First^.data^.Cmd]);
                  DisposeQueueData(FSend_Queue_Swap_Pool.First^.data);
                end;
            end
          else
            begin
              PrintError('illegal ZNet class: %s, loss send queue dest ip %s cmd %s', [ClassName, FSend_Queue_Swap_Pool.First^.data^.IP, FSend_Queue_Swap_Pool.First^.data^.Cmd]);
              DisposeQueueData(FSend_Queue_Swap_Pool.First^.data);
            end;
          FSend_Queue_Swap_Pool.Next;
        end;

      GetIO_Order(FProgress_LargeScale_IO_Pool);
    end;

  while FProgress_LargeScale_IO_Pool.Num > 0 do
    begin
      P_IO := FPeerIO_HashPool[FProgress_LargeScale_IO_Pool.First^.data];
      FProgress_LargeScale_IO_Pool.Next;

      if P_IO <> nil then
        begin
          try
              P_IO.Progress;
          except
          end;
        end;

      if (FProgressMaxDelay > 0) and (GetTimeTick() - tk > FProgressMaxDelay) then
          Break;
    end;
end;

constructor TZNet.Create(HashPoolSize: Integer);
var
  st: TStatisticsType;
  d: Double;
begin
  inherited Create;
  FCritical := TCritical.Create;
  FSend_Critical := TCritical.Create;
  FZNet_Instance_Ptr__ := ZNet_Instance_Pool.Add(self);
  FCommand_Hash_Pool := TCommand_Hash_Pool.Create(1024, nil);
  FIDSeed := 1;
  FProgress_CPS.Reset;
  FPeerIO_HashPool := TPeer_IO_Hash_Pool.Create(HashPoolSize, nil);
  FProgress_Pool := TZNet_Progress_Pool.Create;
  FOnExecuteCommand := nil;
  FOnSendCommand := nil;
  FIdleTimeOut := 0;
  FFastEncrypt := True;
  FUsedParallelEncrypt := True;
  FSyncOnResult := True;
  FSyncOnCompleteBuffer := True;
  FBigStreamMemorySwapSpace := ZNet_Def_BigStream_Memory_SwapSpace_Activted;
  FBigStreamSwapSpaceTriggerSize := ZNet_Def_BigStream_SwapSpace_Trigger;

  FEnabledAtomicLockAndMultiThread := True;
  FTimeOutKeepAlive := True;
  FQuietMode := {$IFDEF Communication_QuietMode}True{$ELSE Communication_QuietMode}False{$ENDIF Communication_QuietMode};
  SetLength(FCipherSecurityArray, 0);
  FPhysicsFragmentSwapSpaceTechnology := ZNet_Def_Physics_Fragment_Cache_Activted;
  FPhysicsFragmentSwapSpaceTrigger := ZNet_Def_Physics_Fragment_Cache_Trigger;

  FSend_Queue_Swap_Pool := TCritical_QueueData_Pool.Create;
  FSendFlushSize := ZNet_Def_SendFlushSize;
  FSendDataCompressed := False;
  FCompleteBufferCompressed := False;
  FHashSecurity := THashSecurity.hsNone;
  FPer_Progress_Loop_Limit := ZNet_Def_Per_Progress_Loop_Limit;
  FExtract_Physics_Fragment_Max_Size := ZNet_Def_Extract_Physics_Fragment_Max_Size;
  FMaxCompleteBufferSize := ZNet_Def_MaxCompleteBufferSize;
  FCompleteBufferCompressionCondition := ZNet_Def_CompleteBufferCompressionCondition;
  FCompleteBufferSwapSpace := ZNet_Def_CompleteBuffer_SwapSpace_Activted;
  FCompleteBufferSwapSpaceTriggerSize := ZNet_Def_CompleteBuffer_SwapSpace_Trigger;
  FAutomaticWaitRemoteReponse := False;
{$IFDEF Encrypt_P2PVM_Packet}
  FEncrypt_P2PVM_Packet := True;
{$ELSE Encrypt_P2PVM_Packet}
  FEncrypt_P2PVM_Packet := False;
{$ENDIF Encrypt_P2PVM_Packet}
  FPeerIOUserDefineClass := TPeer_IO_User_Define;
  FPeerIOUserSpecialClass := TPeer_IO_User_Special;

  FPostProgress := TN_Progress_ToolWithCadencer.Create;

  FFrameworkIsServer := True;
  FFrameworkIsClient := True;
  FFrameworkInfo := ClassName;

  FProgressRuning := False;
  FProgressEnabled := True;
  FProgressWaitRuning := False;
  FOnProgress := nil;

  FCMD_Thread_Runing_Num := 0;

  FIOInterface := nil;
  FVMInterface := nil;
  FOnBigStreamInterface := nil;

  FProtocol := cpZServer;
  FSequencePacketActivted := {$IFDEF UsedSequencePacket}True{$ELSE UsedSequencePacket}False{$ENDIF UsedSequencePacket};

  FPrefixName := '';
  FName := '';

  d := umlNow();
  FInitedTimeMD5 := umlMD5(@d, C_Double_Size);

  FDoubleChannelFramework := nil;
  FCustomUserData := nil;
  FCustomUserObject := nil;

  InitAutomatedP2PVM();

  InitLargeScaleIOPool();

  for st := low(TStatisticsType) to high(TStatisticsType) do
      Statistics[st] := 0;
  CmdRecvStatistics := TCommand_Num_Hash_Pool.Create(128, 0);
  CmdSendStatistics := TCommand_Num_Hash_Pool.Create(128, 0);
  CmdMaxExecuteConsumeStatistics := TCommand_Tick_Hash_Pool.Create(128, 0);

  RegisterStream(C_BuildP2PAuthToken).OnExecute := CMD_BuildP2PAuthToken;
  RegisterConsoleNotify(C_InitP2PTunnel).OnExecute := CMD_InitP2PTunnel;
  RegisterConsoleNotify(C_CloseP2PTunnel).OnExecute := CMD_CloseP2PTunnel;
  RegisterConsole(C_NULL).OnExecute := CMD_NULL;
  RegisterCompleteBuffer(C_Complete_Buffer_Stream_Reponse).OnExecute := cmd_Complete_Buffer_Stream_Reponse;

  FPrintParams := TPrint_Param_Hash_Pool.Create(100, False);
  FPrintParams.Add(C_CipherModel, False, False);
  FPrintParams.Add(C_Wait, False, False);
  FPrintParams.Add(C_NULL, False, False);
  FPrintParams.Add(C_Complete_Buffer_Stream_Reponse, False, False);

  SwitchDefaultPerformance;

  CreateAfter;
end;

procedure TZNet.CreateAfter;
begin
end;

destructor TZNet.Destroy;
begin
  try
    if FZNet_Instance_Ptr__ <> nil then
        ZNet_Instance_Pool.Remove_P(FZNet_Instance_Ptr__);
    while FSend_Queue_Swap_Pool.Num > 0 do
      begin
        DisposeQueueData(FSend_Queue_Swap_Pool.First^.data);
        FSend_Queue_Swap_Pool.Next;
      end;
    DisposeObject(FSend_Queue_Swap_Pool);
    DisposeObject(FProgress_Pool);
    FreeAutomatedP2PVM();
    SetLength(FCipherSecurityArray, 0);
    DeleteRegistedCMD(C_BuildP2PAuthToken);
    DeleteRegistedCMD(C_InitP2PTunnel);
    DeleteRegistedCMD(C_CloseP2PTunnel);
    DeleteRegistedCMD(C_NULL);
    DeleteRegistedCMD(C_Complete_Buffer_Stream_Reponse);

    DisposeObject(FCommand_Hash_Pool);
    DisposeObject(FPeerIO_HashPool);
    DisposeObject(FPrintParams);
    DisposeObject(FPostProgress);
    DisposeObject([CmdRecvStatistics, CmdSendStatistics, CmdMaxExecuteConsumeStatistics]);
    FreeLargeScaleIOPool();
    FIOInterface := nil;
    FVMInterface := nil;
    FOnBigStreamInterface := nil;
    DisposeObject(FSend_Critical);
    DisposeObject(FCritical);
  except
  end;
  inherited Destroy;
end;

procedure TZNet.Post_Queue_Data_To_Swap_Queue(p: PQueueData);
begin
  FSend_Queue_Swap_Pool.Add(p);
end;

function TZNet.AddProgresss(Progress_: TZNet_Progress_Class): TZNet_Progress;
begin
  Result := TZNet_Progress_Class.Create(self);
  Result.FPool_Ptr := FProgress_Pool.Add(Result);
end;

function TZNet.AddProgresss: TZNet_Progress;
begin
  Result := TZNet_Progress.Create(self);
  Result.FPool_Ptr := FProgress_Pool.Add(Result);
end;

procedure TZNet.BeginWriteCustomBuffer(P_IO: TPeerIO);
begin
  P_IO.BeginWriteCustomBuffer;
end;

procedure TZNet.EndWriteCustomBuffer(P_IO: TPeerIO);
begin
  P_IO.EndWriteCustomBuffer;
end;

procedure TZNet.WriteCustomBuffer(P_IO: TPeerIO; const Buffer: PByte; const Size: NativeInt);
begin
  P_IO.WriteCustomBuffer(Buffer, Size);
end;

procedure TZNet.p2pVMTunnelAuth(Sender: TPeerIO; const Token: SystemString; var Accept: Boolean);
begin
  if FVMInterface <> nil then
      FVMInterface.p2pVMTunnelAuth(Sender, Token, Accept);
  if (not Accept) and (FAutomatedP2PVMService) then
      Accept := CompareQuantumCryptographyPassword(FAutomatedP2PVMAuthToken, Token);
end;

procedure TZNet.p2pVMTunnelOpenBefore(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
var
  i: Integer;
begin
  if FVMInterface <> nil then
      FVMInterface.p2pVMTunnelOpenBefore(Sender, P2PVMTunnel);

  if FAutomatedP2PVMService then
    for i := 0 to FAutomatedP2PVMServiceBind.Count - 1 do
        P2PVMTunnel.InstallLogicFramework(FAutomatedP2PVMServiceBind[i]^.Service);
end;

procedure TZNet.p2pVMTunnelOpen(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
begin
  if FVMInterface <> nil then
      FVMInterface.p2pVMTunnelOpen(Sender, P2PVMTunnel);
end;

procedure TZNet.p2pVMTunnelOpenAfter(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
begin
  Sender.ResetSequencePacketBuffer;
  Sender.FSequencePacketSignal := True;
  Sender.SequencePacketVerifyTick := GetTimeTick;
  if FVMInterface <> nil then
      FVMInterface.p2pVMTunnelOpenAfter(Sender, P2PVMTunnel);
end;

procedure TZNet.p2pVMTunnelClose(Sender: TPeerIO; P2PVMTunnel: TZNet_P2PVM);
begin
  if FVMInterface <> nil then
      FVMInterface.p2pVMTunnelClose(Sender, P2PVMTunnel);
end;

function TZNet.AutomatedP2PVMClientConnectionDone(P_IO: TPeerIO): Boolean;
var
  i: Integer;
  p: PAutomatedP2PVMClientData;
begin
  Result := False;
  if P_IO = nil then
      exit;
  if not P_IO.p2pVMTunnelReadyOk then
      exit;
  { check all connection done. }
  for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
    begin
      p := FAutomatedP2PVMClientBind[i];
      if (p^.RequestConnecting) or (not p^.Client.Connected) then
          exit;
    end;
  Result := True;
end;

function TZNet.AutomatedP2PVMClientConnectionDone(): Boolean;
begin
  if FFrameworkIsClient and (TZNet_Client(self).ClientIO <> nil) then
      Result := AutomatedP2PVMClientConnectionDone(TZNet_Client(self).ClientIO)
  else
      Result := False;
end;

procedure TZNet.AutomatedP2PVM_Open(P_IO: TPeerIO);
begin
  with FPostProgress.PostExecuteM(False, FAutomatedP2PVMClientDelayBoot, DoAutomatedP2PVMClient_DelayRequest) do
    begin
      Data3 := P_IO.ID;
      Ready();
    end;
end;

procedure TZNet.AutomatedP2PVM_Open();
begin
  if FFrameworkIsClient and (TZNet_Client(self).ClientIO <> nil) then
      AutomatedP2PVM_Open(TZNet_Client(self).ClientIO);
end;

procedure TZNet.AutomatedP2PVM_Open_C(P_IO: TPeerIO; const OnResult: TOnIOState_C);
begin
  P_IO.FOnAutomatedP2PVMClientConnectionDone_C := OnResult;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_M := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_P := nil;
  AutomatedP2PVM_Open(P_IO);
end;

procedure TZNet.AutomatedP2PVM_Open_M(P_IO: TPeerIO; const OnResult: TOnIOState_M);
begin
  P_IO.FOnAutomatedP2PVMClientConnectionDone_C := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_M := OnResult;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_P := nil;
  AutomatedP2PVM_Open(P_IO);
end;

procedure TZNet.AutomatedP2PVM_Open_P(P_IO: TPeerIO; const OnResult: TOnIOState_P);
begin
  P_IO.FOnAutomatedP2PVMClientConnectionDone_C := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_M := nil;
  P_IO.FOnAutomatedP2PVMClientConnectionDone_P := OnResult;
  AutomatedP2PVM_Open(P_IO);
end;

procedure TZNet.AutomatedP2PVM_Close(P_IO: TPeerIO);
var
  i: Integer;
  p: PAutomatedP2PVMClientData;
begin
  if P_IO = nil then
      exit;

  if FAutomatedP2PVMClient then
    for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
      begin
        p := FAutomatedP2PVMClientBind[i];
        if p^.Client.Connected then
          begin
            p^.Client.Disconnect;
            P_IO.P2PVMTunnel.UninstallLogicFramework(p^.Client);
          end;
      end;
  P_IO.CloseP2PVMTunnel;
end;

procedure TZNet.AutomatedP2PVM_Close();
begin
  if FFrameworkIsClient and (TZNet_Client(self).ClientIO <> nil) then
      AutomatedP2PVM_Close(TZNet_Client(self).ClientIO);
end;

function TZNet.p2pVMTunnelReadyOk(P_IO: TPeerIO): Boolean;
begin
  Result := (P_IO <> nil) and P_IO.p2pVMTunnelReadyOk;
end;

function TZNet.p2pVMTunnelReadyOk(): Boolean;
begin
  if FFrameworkIsClient and (TZNet_Client(self).ClientIO <> nil) then
      Result := p2pVMTunnelReadyOk(TZNet_Client(self).ClientIO)
  else
      Result := False;
end;

procedure TZNet.SwitchMaxPerformance;
begin
  FFastEncrypt := True;
  FUsedParallelEncrypt := False;
  FHashSecurity := THashSecurity.hsNone;
  FSendDataCompressed := False;
  FCompleteBufferCompressed := False;
  SetLength(FCipherSecurityArray, 1);
  FCipherSecurityArray[0] := csNone;
end;

procedure TZNet.SwitchMaxSecurity;
const
  C_CipherSecurity: array [0 .. 7] of TCipherSecurity = (csRC6, csSerpent, csMars, csRijndael, csTwoFish, csAES128, csAES192, csAES256);
var
  i: Integer;
begin
  FFastEncrypt := False;
  FUsedParallelEncrypt := True;
  FHashSecurity := THashSecurity.hsFastMD5;
  FSendDataCompressed := True;
  FCompleteBufferCompressed := False;
  SetLength(FCipherSecurityArray, Length(C_CipherSecurity));
  for i := low(C_CipherSecurity) to high(C_CipherSecurity) do
      FCipherSecurityArray[i] := C_CipherSecurity[i];
end;

procedure TZNet.SwitchDefaultPerformance;
const
  C_CipherSecurity: array [0 .. 14] of TCipherSecurity =
    (csDES64, csDES128, csDES192, csBlowfish, csLBC, csLQC, csXXTea512, csRC6, csSerpent, csMars, csRijndael, csTwoFish, csAES128, csAES192, csAES256);
var
  i: Integer;
begin
  FFastEncrypt := True;
  FUsedParallelEncrypt := True;
  FHashSecurity := THashSecurity.hsNone;
  FSendDataCompressed := False;
  FCompleteBufferCompressed := False;
  SetLength(FCipherSecurityArray, Length(C_CipherSecurity));
  for i := low(C_CipherSecurity) to high(C_CipherSecurity) do
      FCipherSecurityArray[i] := C_CipherSecurity[i];
end;

procedure TZNet.LockSend;
begin
  if FEnabledAtomicLockAndMultiThread then
      FSend_Critical.Lock;
end;

procedure TZNet.UnLockSend;
begin
  if FEnabledAtomicLockAndMultiThread then
      FSend_Critical.UnLock;
end;

procedure TZNet.Lock_All_IO;
begin
  if FEnabledAtomicLockAndMultiThread then
      FCritical.Lock;
end;

procedure TZNet.UnLock_All_IO;
begin
  if FEnabledAtomicLockAndMultiThread then
      FCritical.UnLock;
end;

function TZNet.IOBusy(): Boolean;
begin
  Result := False;
  if FPeerIO_HashPool.Count <= 0 then
      exit;

  with FPeerIO_HashPool.Repeat_ do
    repeat
      if Queue^.data^.data.Second.IOBusy() then
        begin
          Result := True;
          exit;
        end;
    until not Next;
end;

procedure TZNet.Enabled_Progress;
var
  i: Integer;
begin
  FProgressEnabled := True;
  for i := AutomatedP2PVMServiceBind.Count - 1 downto 0 do
      AutomatedP2PVMServiceBind[i].Service.Enabled_Progress;
  for i := AutomatedP2PVMClientBind.Count - 1 downto 0 do
      AutomatedP2PVMClientBind[i].Client.Enabled_Progress;
end;

procedure TZNet.Disable_Progress;
var
  i: Integer;
begin
  FProgressEnabled := False;
  for i := AutomatedP2PVMServiceBind.Count - 1 downto 0 do
      AutomatedP2PVMServiceBind[i].Service.Disable_Progress;
  for i := AutomatedP2PVMClientBind.Count - 1 downto 0 do
      AutomatedP2PVMClientBind[i].Client.Disable_Progress;
end;

procedure TZNet.Progress;
var
  i: Integer;
begin
  if FProgressRuning then // anti dead loop
      exit;
  if not FProgressEnabled then // enabled progress
      exit;

  { anti Dead loop }
  FProgressRuning := True;

  FProgress_CPS.Begin_Caller;

  try
    if Assigned(ProgressBackgroundProc) then
        ProgressBackgroundProc()
    else if Assigned(ProgressBackgroundMethod) then
        ProgressBackgroundMethod();
  except
  end;

  { large-scale Progress }
  ProgressLargeScaleIOPool();

  { AutomatedP2PVMService }
  try
    if FAutomatedP2PVMService and (FAutomatedP2PVMServiceBind.Count > 0) then
      for i := 0 to FAutomatedP2PVMServiceBind.Count - 1 do
          FAutomatedP2PVMServiceBind[i]^.Service.Progress;
  except
  end;

  { AutomatedP2PVMClient }
  try
    if FAutomatedP2PVMClient and (FAutomatedP2PVMClientBind.Count > 0) then
      for i := 0 to FAutomatedP2PVMClientBind.Count - 1 do
          FAutomatedP2PVMClientBind[i]^.Client.Progress;
  except
  end;

  try
      ProgressPost.Progress;
  except
  end;

  try
    if Assigned(FOnProgress) then
        FOnProgress(self);
  except
  end;

  { progress event pool }
  try
    if FProgress_Pool.Num > 0 then
      begin
        with FProgress_Pool.Repeat_ do
          repeat
            Queue^.data.Progress;
            if Queue^.data.NextProgressDoFree then
                FProgress_Pool.Push_To_Recycle_Pool(Queue);
          until not Next;
        FProgress_Pool.Free_Recycle_Pool;
      end;
  except
  end;

  FProgress_CPS.End_Caller;

  { anti Dead loop }
  FProgressRuning := False;
end;

procedure TZNet.Progress_IO_Now_Send(IO_: TPeerIO);
begin
  if FSend_Queue_Swap_Pool.Num > 0 then
    begin
      FSend_Queue_Swap_Pool.Lock;
      try
        with FSend_Queue_Swap_Pool.Repeat_ do
          repeat
            if Queue^.data^.IO_ID = IO_.ID then
              begin
                IO_.PostQueueData(Queue^.data);
                Discard();
              end;
          until not Next;
      finally
          FSend_Queue_Swap_Pool.UnLock;
      end;
    end;
end;

procedure TZNet.ProgressPeerIOC(const OnBackcall: TPeerIOList_C);
var
  IO_Array: TIO_Array;
  pframeworkID: Cardinal;
  c: TPeerIO;
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      GetIO_Array(IO_Array);
      for pframeworkID in IO_Array do
        begin
          c := FPeerIO_HashPool[pframeworkID];
          if c <> nil then
            begin
              try
                  OnBackcall(c);
              except
              end;
            end;
        end;
    end;
end;

procedure TZNet.ProgressPeerIOM(const OnBackcall: TPeerIOList_M);
var
  IO_Array: TIO_Array;
  pframeworkID: Cardinal;
  c: TPeerIO;
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      GetIO_Array(IO_Array);
      for pframeworkID in IO_Array do
        begin
          c := FPeerIO_HashPool[pframeworkID];
          if c <> nil then
            begin
              try
                  OnBackcall(c);
              except
              end;
            end;
        end;
    end;
end;

procedure TZNet.ProgressPeerIOP(const OnBackcall: TPeerIOList_P);
var
  IO_Array: TIO_Array;
  pframeworkID: Cardinal;
  c: TPeerIO;
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      GetIO_Array(IO_Array);
      for pframeworkID in IO_Array do
        begin
          c := FPeerIO_HashPool[pframeworkID];
          if c <> nil then
            begin
              try
                  OnBackcall(c);
              except
              end;
            end;
        end;
    end;
end;

procedure TZNet.FastProgressPeerIOC(const OnBackcall: TPeerIOList_C);
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      with FPeerIO_HashPool.Repeat_ do
        repeat
            OnBackcall(Queue^.data^.data.Second);
        until not Next;
    end;
end;

procedure TZNet.FastProgressPeerIOM(const OnBackcall: TPeerIOList_M);
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      with FPeerIO_HashPool.Repeat_ do
        repeat
            OnBackcall(Queue^.data^.data.Second);
        until not Next;
    end;
end;

procedure TZNet.FastProgressPeerIOP(const OnBackcall: TPeerIOList_P);
begin
  if (FPeerIO_HashPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      with FPeerIO_HashPool.Repeat_ do
        repeat
            OnBackcall(Queue^.data^.data.Second);
        until not Next;
    end;
end;

procedure TZNet.GetIO_Array(out IO_Array: TIO_Array);
begin
  Lock_All_IO;
  try
    SetLength(IO_Array, FPeerIO_HashPool.Count);
    if FPeerIO_HashPool.Count > 0 then
      with FPeerIO_HashPool.Repeat_ do
        repeat
            IO_Array[I__] := Queue^.data^.data.Primary;
        until not Next;
  finally
      UnLock_All_IO;
  end;
end;

procedure TZNet.GetIO_Order(Order_: TIO_Order);
begin
  Order_.Clear;
  Lock_All_IO;
  try
    if FPeerIO_HashPool.Count > 0 then
      with FPeerIO_HashPool.Repeat_ do
        repeat
            Order_.Push(Queue^.data^.data.Primary);
        until not Next;
  finally
      UnLock_All_IO;
  end;
end;

procedure TZNet.ProgressWaitSend(P_IO: TPeerIO);
var
  state_: Boolean;
begin
  if FProgressWaitRuning then
      exit;
  if not FProgressEnabled then
      exit;
  if P_IO = nil then
      exit;
  if FProgressWaitRuning then
    begin
      P_IO.PrintError('ProgressWaitSend: dead loop');
      P_IO.Disconnect; // anti dead loop.
      try
        { progress local instance }
        Progress;
        { progress global instance }
        if ZNet_Instance_Pool.Num > 0 then
          with ZNet_Instance_Pool.Repeat_ do
            repeat
              try
                if (Queue^.data <> self) and (Queue^.data <> nil) then
                    Queue^.data.Progress;
              except
              end;
            until not Next;
      except
      end;
      exit;
    end;

  FProgressWaitRuning := True;

  try
    { progress local instance }
    Progress;
    { progress global instance }
    if ZNet_Instance_Pool.Num > 0 then
      with ZNet_Instance_Pool.Repeat_ do
        repeat
          try
            if (Queue^.data <> self) and (Queue^.data <> nil) then
                Queue^.data.Progress;
          except
          end;
        until not Next;
  except
  end;

  { check thread synchronize }
  try
      Check_Soft_Thread_Synchronize(0);
  except
  end;

  FProgressWaitRuning := False;
end;

function TZNet.ProgressWaitSend(IO_ID: Cardinal): Boolean;
var
  P_IO: TPeerIO;
begin
  Result := False;
  P_IO := FPeerIO_HashPool[IO_ID];
  if P_IO <> nil then
    begin
      ProgressWaitSend(P_IO);
      Result := True;
    end;
end;

procedure TZNet.Print(const v: SystemString; const Args: array of const);
begin
  try
      Print(PFormat(v, Args));
  except
      Error('print error. ' + v);
  end;
end;

procedure TZNet.Print(const v: SystemString);
begin
  DoPrint(v);
end;

procedure TZNet.PrintParam(const v, Args: SystemString);
begin
  try
    if (not IsSystemCMD(Args)) and FPrintParams.Get_Default_Value(Args, True) then
        Print(PFormat(v, [Args]));
  except
      Error('print error. ' + v);
  end;
end;

procedure TZNet.Error(const v: SystemString; const Args: array of const);
begin
  try
      Error(PFormat(v, Args));
  except
      Error('print error. ' + v);
  end;
end;

procedure TZNet.Error(const v: SystemString);
begin
  DoError(v);
end;

procedure TZNet.ErrorParam(const v, Args: SystemString);
begin
  DoError(PFormat(v, [Args]));
end;

procedure TZNet.PrintError(const v: SystemString; const Args: array of const);
begin
  try
      Error(PFormat(v, Args));
  except
      Error('print error. ' + v);
  end;
end;

procedure TZNet.PrintError(const v: SystemString);
begin
  DoError(v);
end;

procedure TZNet.PrintErrorParam(const v, Args: SystemString);
begin
  DoError(PFormat(v, [Args]));
end;

procedure TZNet.Warning(const v: SystemString);
begin
  DoWarning(v);
end;

procedure TZNet.WarningParam(const v, Args: SystemString);
begin
  DoWarning(PFormat(v, [Args]));
end;

procedure TZNet.PrintWarning(const v: SystemString);
begin
  DoWarning(v);
end;

procedure TZNet.PrintWarningParam(const v, Args: SystemString);
begin
  DoWarning(PFormat(v, [Args]));
end;

procedure TZNet.PrintRegistedCMD;
begin
  PrintRegistedCMD('', True);
end;

procedure TZNet.PrintRegistedCMD(prefix: SystemString; incl_internalCMD: Boolean);
begin
  if FCommand_Hash_Pool.Num > 0 then
    with FCommand_Hash_Pool.Queue_Pool.Repeat_ do
      repeat
        if incl_internalCMD or (not umlMultipleMatch('__@*', Queue^.data^.data.Primary)) then
            Print(prefix + Queue^.data^.data.Second.ClassName + ': ' + Queue^.data^.data.Primary);
      until not Next;
end;

procedure TZNet.PrintRegistedCMD(prefix: SystemString);
begin
  PrintRegistedCMD(prefix, True);
end;

function TZNet.RemoveRegistedCMD(const Cmd: SystemString): Boolean;
begin
  Result := FCommand_Hash_Pool.Exists(Cmd);
  FCommand_Hash_Pool.Delete(Cmd);
end;

function TZNet.DeleteRegistedCMD(const Cmd: SystemString): Boolean;
begin
  Result := RemoveRegistedCMD(Cmd);
end;

function TZNet.UnRegisted(const Cmd: SystemString): Boolean;
begin
  Result := RemoveRegistedCMD(Cmd);
end;

function TZNet.ExistsRegistedCmd(const Cmd: SystemString): Boolean;
begin
  Result := FCommand_Hash_Pool.Exists(Cmd);
end;

function TZNet.RegisterConsole(const Cmd: SystemString): TCommandConsole;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandConsole.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterStream(const Cmd: SystemString): TCommandStream;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandStream.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterStreamNotify(const Cmd: SystemString): TCommandStreamNotify;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandStreamNotify.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterConsoleNotify(const Cmd: SystemString): TCommandConsoleNotify;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandConsoleNotify.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterBigStream(const Cmd: SystemString): TCommandBigStream;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandBigStream.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer(const Cmd: SystemString): TCommandCompleteBuffer;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer_StreamNotify(const Cmd: SystemString): TCommandCompleteBuffer_StreamNotify;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer_StreamNotify.Create;
  Result.Sync_Decrypt := True;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer_Asynchronous_StreamNotify(const Cmd: SystemString): TCommandCompleteBuffer_StreamNotify;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer_StreamNotify.Create;
  Result.Sync_Decrypt := False;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer_NoWait_Stream(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Stream;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer_NoWait_Stream.Create;
  Result.FExecute_In_Thread := False;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer_NoWait_Stream_Thread(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Stream;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer_NoWait_Stream.Create;
  Result.FExecute_In_Thread := True;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.RegisterCompleteBuffer_NoWait_Bridge_Stream(const Cmd: SystemString): TCommandCompleteBuffer_NoWait_Bridge_Stream;
begin
  if not CanRegCommand(self, Cmd) then
    begin
      RaiseInfo(PFormat('Illegal Register', []));
      Result := nil;
      exit;
    end;

  if FCommand_Hash_Pool.Exists(Cmd) then
    begin
      RaiseInfo(PFormat('exists cmd: %s', [Cmd]));
      Result := nil;
      exit;
    end;

  Result := TCommandCompleteBuffer_NoWait_Bridge_Stream.Create;
  FCommand_Hash_Pool.Add(Cmd, Result, False);

  CmdRecvStatistics.IncValue(Cmd, 0);
  CmdMaxExecuteConsumeStatistics[Cmd] := 0;
end;

function TZNet.FirstIO: TPeerIO;
begin
  Result := nil;
  if FPeerIO_HashPool.Queue_Pool.First <> nil then
      Result := FPeerIO_HashPool.Queue_Pool.First^.data^.data.Second;
end;

function TZNet.LastIO: TPeerIO;
begin
  Result := nil;
  if FPeerIO_HashPool.Queue_Pool.Last <> nil then
      Result := FPeerIO_HashPool.Queue_Pool.Last^.data^.data.Second;
end;

function TZNet.ExistsID(IO_ID: Cardinal): Boolean;
begin
  Result := FPeerIO_HashPool.Exists_Key(IO_ID);
end;

function TZNet.GetRandomCipherSecurity: TCipherSecurity;
begin
  if Length(FCipherSecurityArray) > 0 then
      Result := TCipher.Random_Select_Cipher(FCipherSecurityArray)
  else
      Result := csNone;
end;

procedure TZNet.CopyParamFrom(Source: TZNet);
begin
  FastEncrypt := Source.FastEncrypt;
  UsedParallelEncrypt := Source.UsedParallelEncrypt;
  SyncOnResult := Source.SyncOnResult;
  SyncOnCompleteBuffer := Source.SyncOnCompleteBuffer;
  BigStreamMemorySwapSpace := Source.BigStreamMemorySwapSpace;
  BigStreamSwapSpaceTriggerSize := Source.BigStreamSwapSpaceTriggerSize;
  EnabledAtomicLockAndMultiThread := Source.EnabledAtomicLockAndMultiThread;
  TimeOut := Source.TimeOut;
  QuietMode := Source.QuietMode;
  PhysicsFragmentSwapSpaceTechnology := Source.PhysicsFragmentSwapSpaceTechnology;
  PhysicsFragmentSwapSpaceTrigger := Source.PhysicsFragmentSwapSpaceTrigger;
  SendDataCompressed := Source.SendDataCompressed;
  CompleteBufferCompressed := Source.CompleteBufferCompressed;
  Per_Progress_Loop_Limit := Source.Per_Progress_Loop_Limit;
  Extract_Physics_Fragment_Max_Size := Source.Extract_Physics_Fragment_Max_Size;
  MaxCompleteBufferSize := Source.MaxCompleteBufferSize;
  CompleteBufferCompressionCondition := Source.CompleteBufferCompressionCondition;
  CompleteBufferSwapSpace := Source.CompleteBufferSwapSpace;
  CompleteBufferSwapSpaceTriggerSize := Source.CompleteBufferSwapSpaceTriggerSize;
  AutomaticWaitRemoteReponse := Source.AutomaticWaitRemoteReponse;
  Encrypt_P2PVM_Packet := Source.Encrypt_P2PVM_Packet;
  ProgressMaxDelay := Source.ProgressMaxDelay;
  SendFlushSize := Source.SendFlushSize;

  PrefixName := Source.PrefixName;
  name := Source.name;
end;

procedure TZNet.CopyParamTo(Dest: TZNet);
begin
  Dest.CopyParamFrom(self);
end;

procedure TZNet.SetPeerIOUserDefineClass(const Value: TPeer_IO_User_Define_Class);
begin
  { safe }
  if FPeerIOUserDefineClass <> nil then
    if (not Value.InheritsFrom(FPeerIOUserDefineClass)) and (Value <> TPeer_IO_User_Define) then
        RaiseInfo('%s no inherited from %s', [Value.ClassName, FPeerIOUserDefineClass.ClassName]);
  { update }
  FPeerIOUserDefineClass := Value;
end;

procedure TZNet.SetPeerIOUserSpecialClass(const Value: TPeer_IO_User_Special_Class);
begin
  { safe }
  if FPeerIOUserSpecialClass <> nil then
    if (not Value.InheritsFrom(FPeerIOUserSpecialClass)) and (Value <> TPeer_IO_User_Special) then
        RaiseInfo('%s no inherited from %s', [Value.ClassName, FPeerIOUserSpecialClass.ClassName]);
  { update }
  FPeerIOUserSpecialClass := Value;
end;

function TZNet_Server.CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  if IsSystemCMD(Cmd) then
      Result := True
  else
      Result := inherited CanExecuteCommand(Sender, Cmd);
end;

function TZNet_Server.CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  Result := inherited CanSendCommand(Sender, Cmd);
end;

function TZNet_Server.CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean;
begin
  if IsSystemCMD(Cmd) then
      Result := True
  else
      Result := inherited CanRegCommand(Sender, Cmd);
end;

procedure TZNet_Server.Command_CipherModel(Sender: TPeerIO; InData, OutData: TDFE);
begin
  try
      Sender.UserDefine.FWorkPlatform := TExecutePlatform(InData.Reader.ReadInteger);
  except
  end;

  OutData.WriteCardinal(Sender.ID);
  OutData.WriteByte(Byte(Sender.FSendDataCipherSecurity));
  OutData.WriteArrayByte.SetBuff(@Sender.FCipherKey[0], Length(Sender.FCipherKey));
  OutData.WriteMD5(FInitedTimeMD5);
  { service state }
  OutData.WriteBool(UsedParallelEncrypt);
  OutData.WriteBool(SyncOnResult);
  OutData.WriteBool(SyncOnCompleteBuffer);
  OutData.WriteBool(EnabledAtomicLockAndMultiThread);
  OutData.WriteBool(TimeOutKeepAlive);
  OutData.WriteBool(QuietMode);
  OutData.WriteUInt64(IdleTimeOut);
  OutData.WriteBool(SendDataCompressed);
  OutData.WriteBool(CompleteBufferCompressed);
  OutData.WriteCardinal(MaxCompleteBufferSize);
  OutData.WriteUInt64(ProgressMaxDelay);

  Sender.FRemoteExecutedForConnectInit := True;

  DoIOConnectAfter(Sender);

  if FAutomatedP2PVMClient and (FAutomatedP2PVMClientBind.Count > 0) then
      AutomatedP2PVM_Open(Sender);
end;

procedure TZNet_Server.Command_Wait(Sender: TPeerIO; InData: SystemString; var OutData: SystemString);
begin
  OutData := IntToHex(GetTimeTick, SizeOf(TTimeTick) * 2);
end;

procedure TZNet_Server.Framework_Internal_IO_Create(const Sender: TPeerIO);
begin
  DoIOConnectBefore(Sender);
  inherited Framework_Internal_IO_Create(Sender);
  if FProtocol = cpCustom then
      DoIOConnectAfter(Sender);
end;

procedure TZNet_Server.Framework_Internal_IO_Destroy(const Sender: TPeerIO);
begin
  DoIODisconnect(Sender);
  inherited Framework_Internal_IO_Destroy(Sender);
end;

procedure TZNet_Server.FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
  if (Protocol = cpCustom) then
    begin
      if Assigned(FOnServerCustomProtocolReceiveBufferNotify) then
        begin
          FOnServerCustomProtocolReceiveBufferNotify(Sender, Buffer, Size, FillDone);
          if FillDone then
              exit;
        end;
      OnReceiveBuffer(Sender, Buffer, Size, FillDone);
    end;
end;

constructor TZNet_Server.Create;
begin
  CreateCustomHashPool(10 * 10000);
end;

constructor TZNet_Server.CreateCustomHashPool(HashPoolSize: Integer);
begin
  inherited Create(HashPoolSize);
  FOnServerCustomProtocolReceiveBufferNotify := nil;

  FStableIOProgressing := False;
  FStableIO := nil;

  FSyncOnResult := True;
  FSyncOnCompleteBuffer := True;

  RegisterStream(C_CipherModel).OnExecute := Command_CipherModel;
  RegisterConsole(C_Wait).OnExecute := Command_Wait;

  FFrameworkIsServer := True;
  FFrameworkIsClient := False;

  name := '';
end;

destructor TZNet_Server.Destroy;
var
  tk: TTimeTick;
begin
  if (FStableIO <> nil) and (not FStableIO.AutoFreeOwnerIOServer) then
    begin
      FStableIO.OwnerIOServer := nil;
      DisposeObject(FStableIO);
      FStableIO := nil;
    end;

  tk := GetTimeTick();
  while (FCMD_Thread_Runing_Num > 0) and (GetTimeTick() - tk < 5000) do // fixed long wait, by.qq600585,
      Check_Soft_Thread_Synchronize(100, False);

  DeleteRegistedCMD(C_CipherModel);
  DeleteRegistedCMD(C_Wait);
  inherited Destroy;
end;

procedure TZNet_Server.Progress;
begin
  inherited Progress;

  if (FStableIO <> nil) and (not FStableIOProgressing) then
    begin
      FStableIOProgressing := True;
      FStableIO.Progress;
      FStableIOProgressing := False;
    end;
end;

function TZNet_Server.StableIO: TZNet_StableServer;
begin
  if FStableIO = nil then
    begin
      FStableIO := TZNet_StableServer.Create;
      FStableIO.AutoFreeOwnerIOServer := False;
      FStableIO.AutoProgressOwnerIOServer := True;
      FStableIO.OwnerIOServer := self;
    end;

  Result := FStableIO;
end;

procedure TZNet_Server.Disconnect(ID: Cardinal);
begin
  Disconnect(ID, 0);
end;

procedure TZNet_Server.Disconnect(ID: Cardinal; delay: Double);
var
  io_cli: TPeerIO;
begin
  io_cli := PeerIO[ID];
  if io_cli <> nil then
      io_cli.DelayClose(delay);
end;

procedure TZNet_Server.OnReceiveBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
end;

procedure TZNet_Server.BeginWriteBuffer(P_IO: TPeerIO);
begin
  BeginWriteCustomBuffer(P_IO);
end;

procedure TZNet_Server.EndWriteBuffer(P_IO: TPeerIO);
begin
  EndWriteCustomBuffer(P_IO);
end;

procedure TZNet_Server.WriteBuffer(P_IO: TPeerIO; const Buffer: PByte; const Size: NativeInt);
begin
  WriteCustomBuffer(P_IO, Buffer, Size);
end;

procedure TZNet_Server.WriteBuffer(P_IO: TPeerIO; const Buffer: TMS64);
begin
  WriteBuffer(P_IO, Buffer.Memory, Buffer.Size);
end;

procedure TZNet_Server.WriteBuffer(P_IO: TPeerIO; const Buffer: TMem64);
begin
  WriteBuffer(P_IO, Buffer.Memory, Buffer.Size);
end;

procedure TZNet_Server.WriteBuffer(P_IO: TPeerIO; const Buffer: TMS64; const doneFreeBuffer: Boolean);
begin
  WriteBuffer(P_IO, Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

procedure TZNet_Server.WriteBuffer(P_IO: TPeerIO; const Buffer: TMem64; const doneFreeBuffer: Boolean);
begin
  WriteBuffer(P_IO, Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

procedure TZNet_Server.StopService;
begin
end;

function TZNet_Server.StartService(Host: SystemString; Port: Word): Boolean;
begin
  Result := False;
end;

procedure TZNet_Server.DoIOConnectBefore(Sender: TPeerIO);
begin
end;

procedure TZNet_Server.DoIOConnectAfter(Sender: TPeerIO);
begin
end;

procedure TZNet_Server.DoIODisconnect(Sender: TPeerIO);
begin
end;

procedure TZNet_Server.SendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;
  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;
  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamM := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdM(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamM := OnResult;
  p^.OnConsoleFailedM := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamP := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmdP(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Console cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamP := OnResult;
  p^.OnConsoleFailedP := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendConsoleCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString);
begin
  SendConsoleCmd(PeerIO[IO_ID], Cmd, ConsoleData);
end;

procedure TZNet_Server.SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M);
begin
  SendConsoleCmdM(PeerIO[IO_ID], Cmd, ConsoleData, OnResult);
end;

procedure TZNet_Server.SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M);
begin
  SendConsoleCmdM(PeerIO[IO_ID], Cmd, ConsoleData, Param1, Param2, OnResult);
end;

procedure TZNet_Server.SendConsoleCmdM(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M);
begin
  SendConsoleCmdM(PeerIO[IO_ID], Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed);
end;

procedure TZNet_Server.SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P);
begin
  SendConsoleCmdP(PeerIO[IO_ID], Cmd, ConsoleData, OnResult);
end;

procedure TZNet_Server.SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P);
begin
  SendConsoleCmdP(PeerIO[IO_ID], Cmd, ConsoleData, Param1, Param2, OnResult);
end;

procedure TZNet_Server.SendConsoleCmdP(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P);
begin
  SendConsoleCmdP(PeerIO[IO_ID], Cmd, ConsoleData, Param1, Param2, OnResult, OnFailed);
end;

procedure TZNet_Server.SendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  p^.OnStreamM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamM := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdM(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamM := OnResult;
  p^.OnStreamFailedM := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  p^.OnStreamP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamP := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmdP(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send Stream cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamP := OnResult;
  p^.OnStreamFailedP := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Server.SendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
begin
  SendStreamCmd(PeerIO[IO_ID], Cmd, StreamData, DoneAutoFree);
end;

procedure TZNet_Server.SendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE);
begin
  SendStreamCmd(PeerIO[IO_ID], Cmd, StreamData);
end;

procedure TZNet_Server.SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean);
begin
  SendStreamCmdM(PeerIO[IO_ID], Cmd, StreamData, OnResult, DoneAutoFree);
end;

procedure TZNet_Server.SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M);
begin
  SendStreamCmdM(PeerIO[IO_ID], Cmd, StreamData, OnResult);
end;

procedure TZNet_Server.SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M);
begin
  SendStreamCmdM(PeerIO[IO_ID], Cmd, StreamData, Param1, Param2, OnResult);
end;

procedure TZNet_Server.SendStreamCmdM(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M);
begin
  SendStreamCmdM(PeerIO[IO_ID], Cmd, StreamData, Param1, Param2, OnResult, OnFailed);
end;

procedure TZNet_Server.SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean);
begin
  SendStreamCmdP(PeerIO[IO_ID], Cmd, StreamData, OnResult, DoneAutoFree);
end;

procedure TZNet_Server.SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P);
begin
  SendStreamCmdP(PeerIO[IO_ID], Cmd, StreamData, OnResult);
end;

procedure TZNet_Server.SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P);
begin
  SendStreamCmdP(PeerIO[IO_ID], Cmd, StreamData, Param1, Param2, OnResult);
end;

procedure TZNet_Server.SendStreamCmdP(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P);
begin
  SendStreamCmdP(PeerIO[IO_ID], Cmd, StreamData, Param1, Param2, OnResult, OnFailed);
end;

procedure TZNet_Server.SendConsoleNotifyCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;
  if not QuietMode then
      P_IO.PrintCommand('Send ConsoleNotify cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendConsoleNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL(P_IO);
end;

procedure TZNet_Server.SendConsoleNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString);
begin
  SendConsoleNotifyCmd(P_IO, Cmd, '');
end;

procedure TZNet_Server.SendConsoleNotifyCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString);
begin
  SendConsoleNotifyCmd(PeerIO[IO_ID], Cmd, ConsoleData);
end;

procedure TZNet_Server.SendConsoleNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString);
begin
  SendConsoleNotifyCmd(PeerIO[IO_ID], Cmd, '');
end;

procedure TZNet_Server.SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not QuietMode then
      P_IO.PrintCommand('Send StreamNotify cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL(P_IO);
end;

procedure TZNet_Server.SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData: TDFE);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Send StreamNotify cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendStreamNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL(P_IO);
end;

procedure TZNet_Server.SendStreamNotifyCmd(P_IO: TPeerIO; const Cmd: SystemString);
var
  d: TDFE;
begin
  d := TDFE.Create;
  SendStreamNotifyCmd(P_IO, Cmd, d);
  DisposeObject(d);
end;

procedure TZNet_Server.SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
begin
  SendStreamNotifyCmd(PeerIO[IO_ID], Cmd, StreamData, DoneAutoFree);
end;

procedure TZNet_Server.SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData: TDFE);
begin
  SendStreamNotifyCmd(PeerIO[IO_ID], Cmd, StreamData);
end;

procedure TZNet_Server.SendStreamNotifyCmd(IO_ID: Cardinal; const Cmd: SystemString);
begin
  SendStreamNotifyCmd(PeerIO[IO_ID], Cmd);
end;

procedure TZNet_Server.SendBigStream(P_IO: TPeerIO; const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) then
    begin
      if DoneAutoFree then
          DisposeObject(BigStream);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(BigStream);
      exit;
    end;
  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendBigStream;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;
  p^.BigStreamStartPos := StartPos;

  LockSend;
  try
    if FBigStreamMemorySwapSpace and DoneAutoFree and P_IO.IOBusy and (BigStream.Size > FBigStreamSwapSpaceTriggerSize)
      and ((BigStream is TMS64) or (BigStream is TMemoryStream)) then
      begin
        if not QuietMode then
            P_IO.PrintCommand('swap space technology cache for "%s"', Cmd);
        p^.BigStream := TFile_Swap_Space_Stream.Create_BigStream(BigStream, BigStream_Swap_Space_Pool__);
        if p^.BigStream <> nil then
          begin
            if DoneAutoFree then
                DisposeObject(BigStream);
            p^.DoneAutoFree := True;
          end
        else
          begin
            p^.BigStream := BigStream;
            p^.DoneAutoFree := DoneAutoFree;
          end;
      end
    else
      begin
        p^.BigStream := BigStream;
        p^.DoneAutoFree := DoneAutoFree;
      end;
  finally
      UnLockSend;
  end;

  Post_Queue_Data_To_Swap_Queue(p);
  if not QuietMode then
      P_IO.PrintCommand('Send BigStream cmd: %s', Cmd);
end;

procedure TZNet_Server.SendBigStream(P_IO: TPeerIO; const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean);
begin
  SendBigStream(P_IO, Cmd, BigStream, 0, DoneAutoFree);
end;

procedure TZNet_Server.SendBigStream(IO_ID: Cardinal; const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean);
begin
  SendBigStream(PeerIO[IO_ID], Cmd, BigStream, StartPos, DoneAutoFree);
end;

procedure TZNet_Server.SendBigStream(IO_ID: Cardinal; const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean);
begin
  SendBigStream(PeerIO[IO_ID], Cmd, BigStream, DoneAutoFree);
end;

procedure TZNet_Server.SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  { init queue data }
  if (P_IO = nil) or (not P_IO.Connected) or (P_IO.Disable_Progress) then
    begin
      if DoneAutoFree then
          System.FreeMemory(buff);
      exit;
    end;
  if not CanSendCommand(P_IO, Cmd) then
    begin
      if DoneAutoFree then
          System.FreeMemory(buff);
      exit;
    end;
  if not QuietMode then
      P_IO.PrintCommand('Send complete buffer cmd: %s', Cmd);

  p := NewQueueData(P_IO);
  p^.State := TQueueState.qsSendCompleteBuffer;
  p^.Cmd := Cmd;
  p^.Cipher := P_IO.FSendDataCipherSecurity;

  LockSend;
  try
    if FCompleteBufferSwapSpace and DoneAutoFree
      and ((FCompleteBufferSwapSpaceTriggerSize <= 0) or (BuffSize.Size > FCompleteBufferSwapSpaceTriggerSize))
      and P_IO.IOBusy() then
      begin
        if not QuietMode then
            P_IO.PrintCommand('ZDB2 swap space technology cache for "%s"', Cmd);
        P_IO.FReceived_Physics_Critical.Lock;
        p^.Buffer_Swap_Memory := TZDB2_Swap_Space_Technology.RunTime_Pool.Create_Memory(buff, BuffSize, False);
        P_IO.FReceived_Physics_Critical.UnLock;
        if p^.Buffer_Swap_Memory <> nil then
          begin
            System.FreeMemory(buff);
            p^.Buffer := nil;
          end
        else
          begin
            p^.Buffer := buff;
            p^.Buffer_Swap_Memory := nil;
          end;
      end
    else
      begin
        p^.Buffer := buff;
        p^.Buffer_Swap_Memory := nil;
      end;
  finally
      UnLockSend;
  end;

  p^.BufferSize := BuffSize;
  p^.DoneAutoFree := DoneAutoFree;
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL(P_IO);
end;

procedure TZNet_Server.SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(P_IO, Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Server.SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(P_IO, Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Server.SendCompleteBuffer(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE);
begin
  SendCompleteBuffer_StreamNotify(P_IO, Cmd, buff);
end;

procedure TZNet_Server.SendCompleteBuffer_StreamNotify(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE);
var
  tmp: TMS64;
begin
  tmp := TMS64.CustomCreate(64 * 1024);
  buff.FastEncodeTo(tmp);
  SendCompleteBuffer(P_IO, Cmd, tmp, True);
end;

procedure TZNet_Server.SendCompleteBuffer_NoWait_StreamM(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);
var
  p: PCommandCompleteBuffer_NoWait_Stream_Data;
  m64: TMS64;
begin
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;
  if not P_IO.Is_Double_Tunnel then
    begin
      P_IO.PrintError('cmd %s only work in double tunnel', [Cmd]);
      exit;
    end;
  if not P_IO.Is_Send_Tunnel then
    begin
      P_IO.PrintError('cmd %s only work in send tunnel', [Cmd]);
      exit;
    end;
  if not QuietMode then
      P_IO.PrintCommand('Send complete buffer cmd: %s', Cmd);

  New(p);
  p^.Init;
  p^.ID := P_IO.ID;
  p^.OnStreamM := OnResult;

  m64 := TMS64.CustomCreate(64 * 1024);
  m64.WriteUInt64(UInt64(p));
  buff.FastEncodeTo(m64);

  SendCompleteBuffer(P_IO, Cmd, m64, True);
end;

procedure TZNet_Server.SendCompleteBuffer_NoWait_StreamP(P_IO: TPeerIO; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);
var
  p: PCommandCompleteBuffer_NoWait_Stream_Data;
  m64: TMS64;
begin
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;
  if not P_IO.Is_Double_Tunnel then
    begin
      P_IO.PrintError('cmd %s only work in double tunnel', [Cmd]);
      exit;
    end;
  if not P_IO.Is_Send_Tunnel then
    begin
      P_IO.PrintError('cmd %s only work in send tunnel', [Cmd]);
      exit;
    end;
  if not QuietMode then
      P_IO.PrintCommand('Send complete buffer cmd: %s', Cmd);

  New(p);
  p^.Init;
  p^.ID := P_IO.ID;
  p^.OnStreamP := OnResult;

  m64 := TMS64.CustomCreate(64 * 1024);
  m64.WriteUInt64(UInt64(p));
  buff.FastEncodeTo(m64);

  SendCompleteBuffer(P_IO, Cmd, m64, True);
end;

procedure TZNet_Server.SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(PeerIO[IO_ID], Cmd, buff, BuffSize, DoneAutoFree);
end;

procedure TZNet_Server.SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(IO_ID, Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Server.SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(IO_ID, Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Server.SendCompleteBuffer(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE);
var
  tmp: TMS64;
begin
  tmp := TMS64.CustomCreate(64 * 1024);
  buff.FastEncodeTo(tmp);
  SendCompleteBuffer(IO_ID, Cmd, tmp, True);
end;

procedure TZNet_Server.SendCompleteBuffer_NoWait_StreamM(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);
begin
  SendCompleteBuffer_NoWait_StreamM(PeerIO[IO_ID], Cmd, buff, OnResult);
end;

procedure TZNet_Server.SendCompleteBuffer_NoWait_StreamP(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);
begin
  SendCompleteBuffer_NoWait_StreamP(PeerIO[IO_ID], Cmd, buff, OnResult);
end;

procedure TZNet_Server.SendCompleteBuffer_StreamNotify(IO_ID: Cardinal; const Cmd: SystemString; buff: TDFE);
begin
  SendCompleteBuffer_StreamNotify(PeerIO[IO_ID], Cmd, buff);
end;

procedure TZNet_Server.Send_NULL(P_IO: TPeerIO);
begin
  SendConsoleCmd(P_IO, C_NULL, '');
end;

procedure TZNet_Server.SendNULL(P_IO: TPeerIO);
begin
  SendConsoleCmd(P_IO, C_NULL, '');
end;

function TZNet_Server.WaitSendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
var
  waitIntf: TWaitSendConsoleCmdIntf;
  timetick: TTimeTick;
  IO_ID: Cardinal;
begin
  Result := '';
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Begin Wait Console cmd: %s', Cmd);

  IO_ID := P_IO.ID;

  timetick := GetTimeTick + TimeOut_;

  while ExistsID(IO_ID) and (P_IO.WaitOnResult or P_IO.BigStreamReceiveing or P_IO.FWaitSendBusy) do
    begin
      ProgressWaitSend(P_IO);
      if not Exists(P_IO) then
          exit;
      if (TimeOut_ > 0) and (GetTimeTick > timetick) then
          exit;
    end;

  if not ExistsID(IO_ID) then
      exit;

  P_IO.FWaitSendBusy := True;

  try
    waitIntf := TWaitSendConsoleCmdIntf.Create;
    waitIntf.Done := False;
    waitIntf.NewResult := '';
    SendConsoleCmdM(P_IO, Cmd, ConsoleData, nil, nil, waitIntf.DoConsoleParam, waitIntf.DoConsoleFailed);
    while ExistsID(IO_ID) and (not waitIntf.Done) do
      begin
        ProgressWaitSend(IO_ID);
        TCompute.Sleep(1);
        if (TimeOut_ > 0) and (GetTimeTick > timetick) then
            Break;
      end;
    if not waitIntf.Failed then
        Result := waitIntf.NewResult
    else
        Result := '';
    if waitIntf.Done then
        DisposeObject(waitIntf);
    if not QuietMode then
      if ExistsID(IO_ID) then
          P_IO.PrintCommand('End Wait Console cmd: %s', Cmd);
  except
      Result := '';
  end;

  if ExistsID(IO_ID) then
      P_IO.FWaitSendBusy := False;
end;

procedure TZNet_Server.WaitSendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
var
  waitIntf: TWaitSendStreamCmdIntf;
  timetick: TTimeTick;
  IO_ID: Cardinal;
begin
  if (P_IO = nil) or (not P_IO.Connected) then
      exit;
  if not CanSendCommand(P_IO, Cmd) then
      exit;

  if not QuietMode then
      P_IO.PrintCommand('Begin Wait Stream cmd: %s', Cmd);

  IO_ID := P_IO.ID;

  timetick := GetTimeTick + TimeOut_;

  while ExistsID(IO_ID) and (P_IO.WaitOnResult or P_IO.BigStreamReceiveing or P_IO.FWaitSendBusy) do
    begin
      ProgressWaitSend(P_IO);
      if not Exists(P_IO) then
          exit;
      if (TimeOut_ > 0) and (GetTimeTick > timetick) then
          exit;
    end;

  if not ExistsID(IO_ID) then
      exit;

  P_IO.FWaitSendBusy := True;

  try
    waitIntf := TWaitSendStreamCmdIntf.Create;
    waitIntf.Done := False;
    SendStreamCmdM(P_IO, Cmd, StreamData, nil, nil, waitIntf.DoStreamParam, waitIntf.DoStreamFailed);
    while ExistsID(IO_ID) and (not waitIntf.Done) do
      begin
        ProgressWaitSend(IO_ID);
        TCompute.Sleep(1);
        if (TimeOut_ > 0) and (GetTimeTick > timetick) then
            Break;
      end;

    if waitIntf.Done then
      begin
        if (Result_ <> nil) and (not waitIntf.Failed) then
          begin
            Result_.Assign(waitIntf.NewResult);
            Result_.Reader.index := 0;
          end;
        DisposeObject(waitIntf);
      end;

    if not QuietMode then
      if ExistsID(IO_ID) then
          P_IO.PrintCommand('End Wait Stream cmd: %s', Cmd);
  except
  end;

  if ExistsID(IO_ID) then
      P_IO.FWaitSendBusy := False;
end;

function TZNet_Server.WaitSendConsoleCmd(IO_ID: Cardinal; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  Result := WaitSendConsoleCmd(PeerIO[IO_ID], Cmd, ConsoleData, TimeOut_);
end;

procedure TZNet_Server.WaitSendStreamCmd(IO_ID: Cardinal; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
begin
  WaitSendStreamCmd(PeerIO[IO_ID], Cmd, StreamData, Result_, TimeOut_);
end;

procedure TZNet_Server.Send_NULL(IO_ID: Cardinal);
begin
  Send_NULL(PeerIO[IO_ID]);
end;

procedure TZNet_Server.BroadcastConsoleNotifyCmd(const Cmd, ConsoleData: SystemString);
var
  IO_ID: Cardinal;
  IO_Array: TIO_Array;
  P_IO: TPeerIO;
begin
  GetIO_Array(IO_Array);
  for IO_ID in IO_Array do
    begin
      P_IO := PeerIO[IO_ID];
      if P_IO <> nil then
          SendConsoleNotifyCmd(P_IO, Cmd, ConsoleData);
    end;
end;

procedure TZNet_Server.BroadcastStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE);
var
  IO_ID: Cardinal;
  IO_Array: TIO_Array;
  P_IO: TPeerIO;
begin
  GetIO_Array(IO_Array);
  for IO_ID in IO_Array do
    begin
      P_IO := PeerIO[IO_ID];
      if P_IO <> nil then
          SendStreamNotifyCmd(P_IO, Cmd, StreamData);
    end;
end;

procedure TZNet_Server.BroadcastCompleteBufferCmd(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt);
var
  IO_ID: Cardinal;
  IO_Array: TIO_Array;
  m64: TMem64;
begin
  GetIO_Array(IO_Array);
  for IO_ID in IO_Array do
    begin
      m64 := TMem64.Create;
      m64.WritePtr(buff, BuffSize);
      SendCompleteBuffer(IO_ID, Cmd, m64, True);
    end;
end;

procedure TZNet_Server.BroadcastCompleteBufferCmd(const Cmd: SystemString; StreamData: TDFE);
var
  IO_ID: Cardinal;
  IO_Array: TIO_Array;
begin
  GetIO_Array(IO_Array);
  for IO_ID in IO_Array do
      SendCompleteBuffer(IO_ID, Cmd, StreamData);
end;

function TZNet_Server.GetCount: Integer;
begin
  Result := FPeerIO_HashPool.Count;
end;

function TZNet_Server.Exists(P_IO: TPeerIO): Boolean;
begin
  Result := FPeerIO_HashPool.Exists_Value(P_IO);
end;

function TZNet_Server.Exists(P_IO: TPeer_IO_User_Define): Boolean;
begin
  Result := Exists(P_IO.Owner);
end;

function TZNet_Server.Exists(P_IO: TPeer_IO_User_Special): Boolean;
begin
  Result := Exists(P_IO.Owner);
end;

function TZNet_Server.Exists(IO_ID: Cardinal): Boolean;
begin
  Result := FPeerIO_HashPool.Exists_Key(IO_ID);
end;

function TZNet_Server.GetPeerIO(ID: Cardinal): TPeerIO;
begin
  Result := FPeerIO_HashPool[ID];
end;

procedure TZNet_ServerState.Reset;
begin
  UsedParallelEncrypt := False;
  SyncOnResult := False;
  SyncOnCompleteBuffer := False;
  EnabledAtomicLockAndMultiThread := False;
  TimeOutKeepAlive := False;
  QuietMode := False;
  IdleTimeOut := 0;
  SendDataCompressed := False;
  CompleteBufferCompressed := False;
  MaxCompleteBufferSize := 0;
  ProgressMaxDelay := 0;
end;

procedure TZNet_Client.Do_CipherModel_Result(Sender: TPeerIO; Result_: TDFE);
var
  arr: TDF_ArrayByte;
begin
  if Result_.Count > 0 then
    begin
      FReponseTime := GetTimeTick - FRequestTime;
      { index 0: my remote id }
      Sender.ID := Result_.Reader.ReadCardinal;

      { index 1: Encrypt }
      Sender.SendCipherSecurity := TCipherSecurity(Result_.Reader.ReadByte);

      { index 2: Encrypt CipherKey }
      arr := Result_.Reader.ReadArrayByte;
      SetLength(Sender.FCipherKey, arr.Count);
      arr.GetBuff(@Sender.FCipherKey[0]);

      { index 3: remote inited time md5 }
      FServerState.Reset();
      if Result_.Reader.IsEnd then
        begin
          Warning('protocol version upgrade ZNet from https://github.com/PassByYou888/ZNet');
        end
      else
        begin
          FInitedTimeMD5 := Result_.Reader.ReadMD5();
          if Result_.Reader.IsEnd then
            begin
              Warning('protocol version upgrade ZNet from https://github.com/PassByYou888/ZNet');
            end
          else
            begin
              FServerState.UsedParallelEncrypt := Result_.Reader.ReadBool();
              FServerState.SyncOnResult := Result_.Reader.ReadBool();
              FServerState.SyncOnCompleteBuffer := Result_.Reader.ReadBool();
              FServerState.EnabledAtomicLockAndMultiThread := Result_.Reader.ReadBool();
              FServerState.TimeOutKeepAlive := Result_.Reader.ReadBool();
              FServerState.QuietMode := Result_.Reader.ReadBool();
              FServerState.IdleTimeOut := Result_.Reader.ReadUInt64();
              FServerState.SendDataCompressed := Result_.Reader.ReadBool();
              FServerState.CompleteBufferCompressed := Result_.Reader.ReadBool();
              FServerState.MaxCompleteBufferSize := Result_.Reader.ReadCardinal();
              FServerState.ProgressMaxDelay := Result_.Reader.ReadUInt64();
            end
        end;

      Sender.RemoteExecutedForConnectInit := True;

      if FConnectInitWaiting then
          TriggerDoConnectFinished;

      CipherModelDone;

      if (FAutomatedP2PVMClient and (FAutomatedP2PVMClientBind.Count > 0)) or
        (FAutomatedP2PVMService and (FAutomatedP2PVMServiceBind.Count > 0)) then
          AutomatedP2PVM_Open(Sender);
    end
  else
    begin
      if FConnectInitWaiting then
          TriggerDoConnectFailed;
    end;

  FConnectInitWaiting := False;
end;

procedure TZNet_Client.DoConnected(Sender: TPeerIO);
var
  d: TDFE;
begin
  FLastConnectIsSuccessed := True;
  if FIgnoreProcessConnectedAndDisconnect then
    begin
      if FOnInterface <> nil then
        begin
          try
              FOnInterface.ClientConnected(self);
          except
          end;
        end;

      Sender.RemoteExecutedForConnectInit := True;
      CipherModelDone;
      FConnectInitWaiting := False;
    end
  else
    begin
      FConnectInitWaiting := True;
      if Protocol = cpZServer then
        begin
          FConnectInitWaitingTimeout := GetTimeTick + FAsyncConnectTimeout;

          ClientIO.SendCipherSecurity := TCipherSecurity.csNone;
          FServerState.Reset();
          d := TDFE.Create;
          d.WriteInteger(Integer(CurrentPlatform));
          SendStreamCmdM(C_CipherModel, d, Do_CipherModel_Result);
          DisposeObject(d);

          if FOnInterface <> nil then
            begin
              try
                  FOnInterface.ClientConnected(self);
              except
              end;
            end;
          FRequestTime := GetTimeTick;
        end
      else
        begin
          ClientIO.SendCipherSecurity := TCipherSecurity.csNone;
          if FOnInterface <> nil then
            begin
              try
                  FOnInterface.ClientConnected(self);
              except
              end;
            end;

          Sender.RemoteExecutedForConnectInit := True;
          TriggerDoConnectFinished;
          CipherModelDone;
          FConnectInitWaiting := False;
        end;
    end;
end;

procedure TZNet_Client.DoDisconnect(Sender: TPeerIO);
begin
  if not FIgnoreProcessConnectedAndDisconnect then
    begin
      FPeerIO_HashPool.Delete(Sender.FID);
      Sender.FID := 0;
      Sender.FRemoteExecutedForConnectInit := False;
    end;

  if (FLastConnectIsSuccessed) and (FOnInterface <> nil) then
      FOnInterface.ClientDisconnect(self);
  FLastConnectIsSuccessed := False;
  FServerState.Reset();
end;

function TZNet_Client.CanExecuteCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  Result := inherited CanExecuteCommand(Sender, Cmd);
end;

function TZNet_Client.CanSendCommand(Sender: TPeerIO; const Cmd: SystemString): Boolean;
begin
  if IsSystemCMD(Cmd) then
      Result := True
  else
      Result := inherited CanSendCommand(Sender, Cmd);
end;

function TZNet_Client.CanRegCommand(Sender: TZNet; const Cmd: SystemString): Boolean;
begin
  Result := inherited CanRegCommand(Sender, Cmd);
end;

procedure TZNet_Client.FillCustomBuffer(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
  if (Protocol = cpCustom) then
    begin
      if Assigned(FOnClientCustomProtocolReceiveBufferNotify) then
        begin
          FOnClientCustomProtocolReceiveBufferNotify(self, Buffer, Size, FillDone);
          if FillDone then
              exit;
        end;
      OnReceiveBuffer(Buffer, Size, FillDone);
    end;
end;

procedure TZNet_Client.ConsoleResult_Wait(Sender: TPeerIO; Result_: SystemString);
begin
  if FWaiting then
    begin
      FWaiting := False;
      FWaitingTimeOut := 0;
      try
        if Assigned(FOnWaitResult_C) then
            FOnWaitResult_C(True)
        else if Assigned(FOnWaitResult_M) then
            FOnWaitResult_M(True)
        else if Assigned(FOnWaitResult_P) then
            FOnWaitResult_P(True);
      except
      end;

      FOnWaitResult_C := nil;
      FOnWaitResult_M := nil;
      FOnWaitResult_P := nil;
    end;
end;

function TZNet_Client.GetWaitTimeout(const t: TTimeTick): TTimeTick;
begin
  if t = 0 then
      Result := 1000 * 60 * 30
  else
      Result := t;
end;

procedure TZNet_Client.Do_IO_IDLE_FreeSelf(Data_: TCore_Object);
begin
  if self is TZNet_WithP2PVM_Client then
      TZNet_WithP2PVM_Client(self).P2PVM_Clone_NextProgressDoFreeSelf := True
  else
      DelayFreeObject(1.0, self, Data_);
end;

constructor TZNet_Client.Create;
begin
  inherited Create(1);
  FMaxCompleteBufferSize := 0; { 0 = infinity }
  FOnClientCustomProtocolReceiveBufferNotify := nil;

  FStableIOProgressing := False;
  FStableIO := nil;

  FOnInterface := nil;
  FConnectInitWaiting := False;
  FConnectInitWaitingTimeout := 0;

  FWaiting := False;
  FWaitingTimeOut := 0;
  FAsyncConnectTimeout := 60 * 1000;
  FOnCipherModelDone := nil;

  FServerState.Reset();

  FIgnoreProcessConnectedAndDisconnect := False;
  FLastConnectIsSuccessed := False;
  FRequestTime := 0;
  FReponseTime := 0;

  FOnWaitResult_C := nil;
  FOnWaitResult_M := nil;
  FOnWaitResult_P := nil;
  FFrameworkIsServer := False;
  FFrameworkIsClient := True;

  name := '';
end;

destructor TZNet_Client.Destroy;
begin
  try
    if (FStableIO <> nil) and (not FStableIO.AutoFreeOwnerIOClient) then
      begin
        DisposeObject(FStableIO);
        FStableIO := nil;
      end;
    FOnInterface := nil;
  except
  end;
  inherited Destroy;
end;

procedure TZNet_Client.DelayFreeSelf;
begin
  DelayFreeObject(1.0, self, nil);
end;

function TZNet_Client.GetP2PVMTunnel: TZNet_P2PVM;
begin
  if ClientIO <> nil then
      Result := ClientIO.P2PVM
  else
      Result := nil;
end;

procedure TZNet_Client.IO_IDLE_TraceC(data: TCore_Object; const OnNotify: TOnDataNotify_C);
begin
  if ClientIO = nil then
      OnNotify(data)
  else
      ClientIO.IO_IDLE_TraceC(data, OnNotify);
end;

procedure TZNet_Client.IO_IDLE_TraceM(data: TCore_Object; const OnNotify: TOnDataNotify_M);
begin
  if ClientIO = nil then
      OnNotify(data)
  else
      ClientIO.IO_IDLE_TraceM(data, OnNotify);
end;

procedure TZNet_Client.IO_IDLE_TraceP(data: TCore_Object; const OnNotify: TOnDataNotify_P);
begin
  if ClientIO = nil then
      OnNotify(data)
  else
      ClientIO.IO_IDLE_TraceP(data, OnNotify);
end;

procedure TZNet_Client.IO_IDLE_Trace_And_FreeSelf(Additional_Object_: TCore_Object);
begin
  IO_IDLE_TraceM(Additional_Object_, Do_IO_IDLE_FreeSelf);
end;

procedure TZNet_Client.OnReceiveBuffer(const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
end;

procedure TZNet_Client.BeginWriteBuffer();
begin
  BeginWriteCustomBuffer(ClientIO);
end;

procedure TZNet_Client.EndWriteBuffer();
begin
  EndWriteCustomBuffer(ClientIO);
end;

procedure TZNet_Client.WriteBuffer(const Buffer: PByte; const Size: NativeInt);
begin
  WriteCustomBuffer(ClientIO, Buffer, Size);
end;

procedure TZNet_Client.WriteBuffer(const Buffer: TMS64);
begin
  WriteBuffer(Buffer.Memory, Buffer.Size);
end;

procedure TZNet_Client.WriteBuffer(const Buffer: TMem64);
begin
  WriteBuffer(Buffer.Memory, Buffer.Size);
end;

procedure TZNet_Client.WriteBuffer(const Buffer: TMS64; const doneFreeBuffer: Boolean);
begin
  WriteBuffer(Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

procedure TZNet_Client.WriteBuffer(const Buffer: TMem64; const doneFreeBuffer: Boolean);
begin
  WriteBuffer(Buffer);
  if doneFreeBuffer then
      DisposeObject(Buffer);
end;

function TZNet_Client.ServerState: PZNet_ServerState;
begin
  Result := @FServerState;
end;

procedure TZNet_Client.Progress;
begin
  inherited Progress;

  if not FProgressEnabled then
      exit;

  if (FConnectInitWaiting) and (GetTimeTick > FConnectInitWaitingTimeout) then
    begin
      FConnectInitWaiting := False;

      try
          TriggerDoConnectFailed;
      except
      end;

      try
        if Connected then
            Disconnect;
      except
      end;
    end;

  if (FWaiting) and ((GetTimeTick > FWaitingTimeOut) or (not Connected)) then
    begin
      FWaiting := False;
      FWaitingTimeOut := 0;
      try
        if Assigned(FOnWaitResult_C) then
            FOnWaitResult_C(False)
        else if Assigned(FOnWaitResult_M) then
            FOnWaitResult_M(False)
        else if Assigned(FOnWaitResult_P) then
            FOnWaitResult_P(False);
      except
      end;

      FOnWaitResult_C := nil;
      FOnWaitResult_M := nil;
      FOnWaitResult_P := nil;
    end;

  if (FStableIO <> nil) and (not FStableIOProgressing) then
    begin
      FStableIOProgressing := True;
      FStableIO.Progress;
      FStableIOProgressing := False;
    end;
end;

function TZNet_Client.StableIO: TZNet_StableClient;
begin
  if FStableIO = nil then
    begin
      FStableIO := TZNet_StableClient.Create;
      FStableIO.AutoFreeOwnerIOClient := False;
      FStableIO.AutoProgressOwnerIOClient := True;
      FStableIO.OwnerIOClient := self;
    end;

  Result := FStableIO;
end;

procedure TZNet_Client.TriggerDoDisconnect;
begin
  DoDisconnect(ClientIO);
end;

function TZNet_Client.Connected: Boolean;
begin
  Result := False;
end;

function TZNet_Client.ClientIO: TPeerIO;
begin
  Result := nil;
end;

procedure TZNet_Client.TriggerDoConnectFailed;
begin
  FConnectInitWaiting := False;
end;

procedure TZNet_Client.TriggerDoConnectFinished;
begin
  FConnectInitWaiting := False;
end;

procedure TZNet_Client.CipherModelDone;
begin
  try
    if Assigned(FOnCipherModelDone) then
        FOnCipherModelDone(self);
  except
  end;
end;

procedure TZNet_Client.AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C);
var
  R: Boolean;
begin
  R := Connect(addr, Port);
  if Assigned(OnResult) then
      OnResult(R);
end;

procedure TZNet_Client.AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M);
var
  R: Boolean;
begin
  R := Connect(addr, Port);
  if Assigned(OnResult) then
      OnResult(R);
end;

procedure TZNet_Client.AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P);
var
  R: Boolean;
begin
  R := Connect(addr, Port);
  if Assigned(OnResult) then
      OnResult(R);
end;

procedure TZNet_Client.AsyncConnectC(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_C);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyC := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

procedure TZNet_Client.AsyncConnectM(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_M);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyM := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

procedure TZNet_Client.AsyncConnectP(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_P);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyP := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

function TZNet_Client.Connect(addr: SystemString; Port: Word): Boolean;
begin
  Result := False;
end;

procedure TZNet_Client.Disconnect;
begin
end;

procedure TZNet_Client.DelayCloseIO;
begin
  try
    if ClientIO <> nil then
        ClientIO.DelayClose;
  except
  end;
end;

procedure TZNet_Client.DelayCloseIO(const t: Double);
begin
  try
    if ClientIO <> nil then
        ClientIO.DelayClose(t);
  except
  end;
end;

function TZNet_Client.Wait(TimeOut_: TTimeTick): SystemString;
begin
  Result := '';
  if (ClientIO = nil) then
      exit;
  if (not Connected) then
      exit;

  Result := WaitSendConsoleCmd(C_Wait, '', GetWaitTimeout(TimeOut_));
end;

function TZNet_Client.WaitC(TimeOut_: TTimeTick; const OnResult: TOnState_C): Boolean;
begin
  Result := False;
  if (ClientIO = nil) then
      exit;
  if (FWaiting) then
      exit;
  if (not Connected) then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FWaiting := True;
  FWaitingTimeOut := GetTimeTick + GetWaitTimeout(TimeOut_);
  FOnWaitResult_C := OnResult;
  FOnWaitResult_M := nil;
  FOnWaitResult_P := nil;
  SendConsoleCmdM(C_Wait, '', ConsoleResult_Wait);
  Result := True;
end;

function TZNet_Client.WaitM(TimeOut_: TTimeTick; const OnResult: TOnState_M): Boolean;
begin
  Result := False;
  if (ClientIO = nil) then
      exit;
  if (FWaiting) then
      exit;
  if (not Connected) then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FWaiting := True;
  FWaitingTimeOut := GetTimeTick + GetWaitTimeout(TimeOut_);
  FOnWaitResult_C := nil;
  FOnWaitResult_M := OnResult;
  FOnWaitResult_P := nil;
  SendConsoleCmdM(C_Wait, '', ConsoleResult_Wait);

  Result := True;
end;

function TZNet_Client.WaitP(TimeOut_: TTimeTick; const OnResult: TOnState_P): Boolean;
begin
  Result := False;
  if (ClientIO = nil) then
      exit;
  if (FWaiting) then
      exit;
  if (not Connected) then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FWaiting := True;
  FWaitingTimeOut := GetTimeTick + GetWaitTimeout(TimeOut_);
  FOnWaitResult_C := nil;
  FOnWaitResult_M := nil;
  FOnWaitResult_P := OnResult;
  SendConsoleCmdM(C_Wait, '', ConsoleResult_Wait);
  Result := True;
end;

function TZNet_Client.WaitSendBusy: Boolean;
begin
  Result := (ClientIO <> nil) and (ClientIO.WaitSendBusy);
end;

function TZNet_Client.LastQueueData: PQueueData;
begin
  Result := nil;
  if ClientIO = nil then
      exit;
  ClientIO.FSend_Queue_Critical.Lock;
  if ClientIO.FSend_Queue_Pool.Num > 0 then
      Result := PQueueData(ClientIO.FSend_Queue_Pool.Last^.data);
  ClientIO.FSend_Queue_Critical.UnLock;
end;

function TZNet_Client.LastQueueCmd: SystemString;
var
  p: PQueueData;
begin
  p := LastQueueData;
  if p <> nil then
      Result := p^.Cmd
  else
      Result := '';
end;

function TZNet_Client.QueueCmdCount: Integer;
begin
  Result := 0;
  if ClientIO = nil then
      exit;
  ClientIO.FSend_Queue_Critical.Lock;
  Result := ClientIO.FSend_Queue_Pool.Num;
  ClientIO.FSend_Queue_Critical.UnLock;
end;

function TZNet_Client.Last_IO_IDLE_Time: TTimeTick;
begin
  if ClientIO = nil then
      Result := GetTimeTick()
  else
      Result := ClientIO.Last_IO_IDLE_Time;
end;

function TZNet_Client.Client_ID: Cardinal;
begin
  if ClientIO = nil then
      Result := 0
  else
      Result := ClientIO.ID;
end;

procedure TZNet_Client.SendConsoleCmd(const Cmd, ConsoleData: SystemString);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamM := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdM(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_M; const OnFailed: TOnConsoleFailed_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamM := OnResult;
  p^.OnConsoleFailedM := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; const OnResult: TOnConsole_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamP := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleCmdP(const Cmd, ConsoleData: SystemString; Param1: Pointer; Param2: TObject; const OnResult: TOnConsoleParam_P; const OnFailed: TOnConsoleFailed_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Console cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  p^.OnConsoleParamP := OnResult;
  p^.OnConsoleFailedP := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if ClientIO = nil then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not Connected then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmd(const Cmd: SystemString; StreamData: TDFE);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdM(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_M; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if ClientIO = nil then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not Connected then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  p^.OnStreamM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamM := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamM := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdM(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_M; const OnFailed: TOnStreamFailed_M);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamM := OnResult;
  p^.OnStreamFailedM := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdP(const Cmd: SystemString; StreamData: TMS64; const OnResult: TOnStream_P; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if ClientIO = nil then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not Connected then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  p^.OnStreamP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; const OnResult: TOnStream_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamP := OnResult;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamP := OnResult;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendStreamCmdP(const Cmd: SystemString; StreamData: TDFE; Param1: Pointer; Param2: TObject; const OnResult: TOnStreamParam_P; const OnFailed: TOnStreamFailed_P);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send Stream cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  p^.OnStreamParamP := OnResult;
  p^.OnStreamFailedP := OnFailed;
  p^.Param1 := Param1;
  p^.Param2 := Param2;
  Post_Queue_Data_To_Swap_Queue(p);
end;

procedure TZNet_Client.SendConsoleNotifyCmd(const Cmd, ConsoleData: SystemString);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send ConsoleNotify cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendConsoleNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.ConsoleData := ConsoleData;
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL();
end;

procedure TZNet_Client.SendConsoleNotifyCmd(const Cmd: SystemString);
begin
  SendConsoleNotifyCmd(Cmd, '');
end;

procedure TZNet_Client.SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TMS64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if ClientIO = nil then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not Connected then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(StreamData);
      exit;
    end;
  if not QuietMode then
      ClientIO.PrintCommand('Send StreamNotify cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := DoneAutoFree;
  p^.StreamData := StreamData;
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL();
end;

procedure TZNet_Client.SendStreamNotifyCmd(const Cmd: SystemString; StreamData: TDFE);
var
  p: PQueueData;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Send StreamNotify cmd: %s', Cmd);

  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendStreamNotifyCMD;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.DoneAutoFree := True;
  p^.StreamData := TMS64.Create;
  if StreamData <> nil then
      StreamData.FastEncodeTo(p^.StreamData)
  else
      TDFE.BuildEmptyStream(p^.StreamData);
  Post_Queue_Data_To_Swap_Queue(p);
  if FAutomaticWaitRemoteReponse then
      Send_NULL();
end;

procedure TZNet_Client.SendStreamNotifyCmd(const Cmd: SystemString);
var
  d: TDFE;
begin
  d := TDFE.Create;
  SendStreamNotifyCmd(Cmd, d);
  DisposeObject(d);
end;

procedure TZNet_Client.SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; StartPos: Int64; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if ClientIO = nil then
    begin
      if DoneAutoFree then
          DisposeObject(BigStream);
      exit;
    end;
  if not Connected then
    begin
      if DoneAutoFree then
          DisposeObject(BigStream);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      if DoneAutoFree then
          DisposeObject(BigStream);
      exit;
    end;
  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendBigStream;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;
  p^.BigStreamStartPos := StartPos;

  LockSend;
  try
    if FBigStreamMemorySwapSpace and DoneAutoFree and IOBusy and (BigStream.Size > FBigStreamSwapSpaceTriggerSize)
      and ((BigStream is TMS64) or (BigStream is TMemoryStream)) then
      begin
        if not QuietMode then
            ClientIO.PrintCommand('swap space technology cache for "%s"', Cmd);
        p^.BigStream := TFile_Swap_Space_Stream.Create_BigStream(BigStream, BigStream_Swap_Space_Pool__);
        if p^.BigStream <> nil then
          begin
            if DoneAutoFree then
                DisposeObject(BigStream);
            p^.DoneAutoFree := True;
          end
        else
          begin
            p^.BigStream := BigStream;
            p^.DoneAutoFree := DoneAutoFree;
          end;
      end
    else
      begin
        p^.BigStream := BigStream;
        p^.DoneAutoFree := DoneAutoFree;
      end;
  except
      UnLockSend;
  end;

  Post_Queue_Data_To_Swap_Queue(p);
  if not QuietMode then
      ClientIO.PrintCommand('Send BigStream cmd: %s', Cmd);
end;

procedure TZNet_Client.SendBigStream(const Cmd: SystemString; BigStream: TCore_Stream; DoneAutoFree: Boolean);
begin
  SendBigStream(Cmd, BigStream, 0, DoneAutoFree);
end;

procedure TZNet_Client.SendCompleteBuffer(const Cmd: SystemString; buff: PByte; BuffSize: NativeInt; DoneAutoFree: Boolean);
var
  p: PQueueData;
begin
  if (ClientIO = nil) or (ClientIO.Disable_Progress) then
    begin
      PrintErrorParam('IO error', Cmd);
      if DoneAutoFree then
          System.FreeMemory(buff);
      exit;
    end;
  if not Connected then
    begin
      PrintErrorParam('not connect', Cmd);
      if DoneAutoFree then
          System.FreeMemory(buff);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      PrintErrorParam('Illegal cmd', Cmd);
      if DoneAutoFree then
          System.FreeMemory(buff);
      exit;
    end;
  { init queue data }
  p := NewQueueData(ClientIO);
  p^.State := TQueueState.qsSendCompleteBuffer;
  p^.Cmd := Cmd;
  p^.Cipher := ClientIO.FSendDataCipherSecurity;

  LockSend;
  try
    if FCompleteBufferSwapSpace and DoneAutoFree
      and ((FCompleteBufferSwapSpaceTriggerSize <= 0) or (BuffSize.Size > FCompleteBufferSwapSpaceTriggerSize))
      and IOBusy() then
      begin
        if not QuietMode then
            ClientIO.PrintCommand('ZDB2 swap space technology cache for "%s"', Cmd);
        ClientIO.FReceived_Physics_Critical.Lock;
        p^.Buffer_Swap_Memory := TZDB2_Swap_Space_Technology.RunTime_Pool.Create_Memory(buff, BuffSize, False);
        ClientIO.FReceived_Physics_Critical.UnLock;
        if p^.Buffer_Swap_Memory <> nil then
          begin
            System.FreeMemory(buff);
            p^.Buffer := nil;
          end
        else
          begin
            p^.Buffer := buff;
            p^.Buffer_Swap_Memory := nil;
          end;
      end
    else
      begin
        p^.Buffer := buff;
        p^.Buffer_Swap_Memory := nil;
      end;
  finally
      UnLockSend;
  end;

  p^.BufferSize := BuffSize;
  p^.DoneAutoFree := DoneAutoFree;
  Post_Queue_Data_To_Swap_Queue(p);
  if not QuietMode then
      ClientIO.PrintCommand('Send complete buffer cmd: %s', Cmd);
  if FAutomaticWaitRemoteReponse then
      Send_NULL();
end;

procedure TZNet_Client.SendCompleteBuffer(const Cmd: SystemString; buff: TMS64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Client.SendCompleteBuffer(const Cmd: SystemString; buff: TMem64; DoneAutoFree: Boolean);
begin
  SendCompleteBuffer(Cmd, buff.Memory, buff.Size, DoneAutoFree);
  if DoneAutoFree then
    begin
      buff.DiscardMemory;
      DisposeObject(buff);
    end;
end;

procedure TZNet_Client.SendCompleteBuffer(const Cmd: SystemString; buff: TDFE);
begin
  SendCompleteBuffer_StreamNotify(Cmd, buff);
end;

procedure TZNet_Client.SendCompleteBuffer_StreamNotify(const Cmd: SystemString; buff: TDFE);
var
  tmp: TMS64;
begin
  tmp := TMS64.CustomCreate(64 * 1024);
  buff.FastEncodeTo(tmp);
  SendCompleteBuffer(Cmd, tmp, True);
end;

procedure TZNet_Client.SendCompleteBuffer_NoWait_StreamM(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_M);
var
  p: PCommandCompleteBuffer_NoWait_Stream_Data;
  m64: TMS64;
begin
  if ClientIO = nil then
    begin
      PrintErrorParam('IO is NULL', Cmd);
      exit;
    end;
  if not Connected then
    begin
      PrintErrorParam('no connected', Cmd);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      PrintErrorParam('Illegal cmd', Cmd);
      exit;
    end;
  if not ClientIO.Is_Double_Tunnel then
    begin
      ClientIO.PrintError('cmd %s only work in double tunnel', [Cmd]);
      exit;
    end;
  if not ClientIO.Is_Send_Tunnel then
    begin
      ClientIO.PrintError('cmd %s only work in send tunnel', [Cmd]);
      exit;
    end;

  New(p);
  p^.Init;
  p^.ID := ClientIO.ID;
  p^.OnStreamM := OnResult;

  m64 := TMS64.CustomCreate(64 * 1024);
  m64.WriteUInt64(UInt64(p));
  buff.FastEncodeTo(m64);

  SendCompleteBuffer(Cmd, m64, True);
end;

procedure TZNet_Client.SendCompleteBuffer_NoWait_StreamP(const Cmd: SystemString; buff: TDFE; OnResult: TOnStream_P);
var
  p: PCommandCompleteBuffer_NoWait_Stream_Data;
  m64: TMS64;
begin
  if ClientIO = nil then
    begin
      PrintErrorParam('IO is NULL', Cmd);
      exit;
    end;
  if not Connected then
    begin
      PrintErrorParam('no connected', Cmd);
      exit;
    end;
  if not CanSendCommand(ClientIO, Cmd) then
    begin
      PrintErrorParam('Illegal cmd', Cmd);
      exit;
    end;
  if not ClientIO.Is_Double_Tunnel then
    begin
      ClientIO.PrintError('cmd %s only work in double tunnel', [Cmd]);
      exit;
    end;
  if not ClientIO.Is_Send_Tunnel then
    begin
      ClientIO.PrintError('cmd %s only work in send tunnel', [Cmd]);
      exit;
    end;

  New(p);
  p^.Init;
  p^.ID := ClientIO.ID;
  p^.OnStreamP := OnResult;

  m64 := TMS64.CustomCreate(64 * 1024);
  m64.WriteUInt64(UInt64(p));
  buff.FastEncodeTo(m64);

  SendCompleteBuffer(Cmd, m64, True);
end;

procedure TZNet_Client.Send_NULL;
begin
  SendConsoleCmd(C_NULL, '');
end;

procedure TZNet_Client.SendNULL;
begin
  SendConsoleCmd(C_NULL, '');
end;

function TZNet_Client.WaitSendConsoleCmd(const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
var
  waitIntf: TWaitSendConsoleCmdIntf;
  timetick: TTimeTick;
  IO_ID: Cardinal;
begin
  Result := '';
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;
  if not QuietMode then
      ClientIO.PrintCommand('Begin Wait console cmd: %s', Cmd);

  IO_ID := ClientIO.ID;

  timetick := GetTimeTick + TimeOut_;

  while ExistsID(IO_ID) and (ClientIO.WaitOnResult or ClientIO.BigStreamReceiveing or ClientIO.FWaitSendBusy) do
    begin
      ProgressWaitSend(ClientIO);
      if not Connected then
          exit;
      if (TimeOut_ > 0) and (GetTimeTick > timetick) then
          exit;
    end;

  if not ExistsID(IO_ID) then
      exit;

  ClientIO.FWaitSendBusy := True;

  try
    waitIntf := TWaitSendConsoleCmdIntf.Create;
    waitIntf.Done := False;
    waitIntf.NewResult := '';
    SendConsoleCmdM(Cmd, ConsoleData, nil, nil, waitIntf.DoConsoleParam, waitIntf.DoConsoleFailed);
    while ExistsID(IO_ID) and (not waitIntf.Done) do
      begin
        TCompute.Sleep(1);
        ProgressWaitSend(IO_ID);
        if not Connected then
            Break;
        if (TimeOut_ > 0) and (GetTimeTick > timetick) then
            Break;
      end;
    if ExistsID(IO_ID) and (not waitIntf.Failed) and waitIntf.Done then
        Result := waitIntf.NewResult
    else
        Result := '';

    try
      if not QuietMode then
        if ExistsID(IO_ID) then
            ClientIO.PrintCommand('End Wait console cmd: %s', Cmd);
    except
    end;

    if waitIntf.Done then
        DisposeObject(waitIntf);
  except
      Result := '';
  end;

  if ExistsID(IO_ID) and Connected then
      ClientIO.FWaitSendBusy := False;
end;

procedure TZNet_Client.WaitSendStreamCmd(const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
var
  waitIntf: TWaitSendStreamCmdIntf;
  timetick: TTimeTick;
  IO_ID: Cardinal;
begin
  if ClientIO = nil then
      exit;
  if not Connected then
      exit;
  if not CanSendCommand(ClientIO, Cmd) then
      exit;

  if not QuietMode then
      ClientIO.PrintCommand('Begin Wait Stream cmd: %s', Cmd);

  IO_ID := ClientIO.ID;

  timetick := GetTimeTick + TimeOut_;

  while ExistsID(IO_ID) and (ClientIO.WaitOnResult or ClientIO.BigStreamReceiveing or ClientIO.FWaitSendBusy) do
    begin
      ProgressWaitSend(ClientIO);
      if not Connected then
          exit;
      if (TimeOut_ > 0) and (GetTimeTick > timetick) then
          exit;
    end;

  if not ExistsID(IO_ID) then
      exit;

  ClientIO.FWaitSendBusy := True;

  try
    waitIntf := TWaitSendStreamCmdIntf.Create;
    waitIntf.Done := False;
    SendStreamCmdM(Cmd, StreamData, nil, nil, waitIntf.DoStreamParam, waitIntf.DoStreamFailed);
    while ExistsID(IO_ID) and (not waitIntf.Done) do
      begin
        TCompute.Sleep(1);
        ProgressWaitSend(IO_ID);
        if not Connected then
            Break;
        if (TimeOut_ > 0) and (GetTimeTick > timetick) then
            Break;
      end;
    try
      if not QuietMode then
        if ExistsID(IO_ID) then
            ClientIO.PrintCommand('End Wait Stream cmd: %s', Cmd);
    except
    end;

    if waitIntf.Done then
      begin
        if (Result_ <> nil) and (not waitIntf.Failed) then
          begin
            Result_.Assign(waitIntf.NewResult);
            Result_.Reader.index := 0;
          end;
        DisposeObject(waitIntf);
      end;
  except
  end;

  if ExistsID(IO_ID) and Connected then
      ClientIO.FWaitSendBusy := False;
end;

function TZNet_Client.RemoteID: Cardinal;
begin
  if ClientIO <> nil then
      Result := ClientIO.FID
  else
      Result := 0;
end;

function TZNet_Client.RemoteKey: TCipherKeyBuffer;
begin
  Result := ClientIO.CipherKey;
end;

function TZNet_Client.RemoteInited: Boolean;
begin
  if ClientIO <> nil then
      Result := ClientIO.FRemoteExecutedForConnectInit
  else
      Result := False;
end;

procedure TP2PVMFragmentPacket.Init;
begin
  BuffSiz := 0;
  FrameworkID := 0;
  p2pID := 0;
  pkType := 0;
  buff := nil;
end;

procedure TP2PVMFragmentPacket.Build_P2PVM_Send_Buffer(Stream: TMem64);
begin
  Stream.WritePtr(@BuffSiz, 4);
  Stream.WritePtr(@FrameworkID, 4);
  Stream.WritePtr(@p2pID, 4);
  Stream.WritePtr(@pkType, 1);
  if BuffSiz > 0 then
      Stream.WritePtr(buff, BuffSiz);
end;

procedure TP2PVM_PeerIO.CreateAfter;
begin
  inherited CreateAfter;
  FLinkVM := nil;
  FRealSendBuff := TMem64.CustomCreate(64 * 1024);
  FSendQueue := TP2P_VM_Fragment_Packet_Pool.Create;
  FRemote_frameworkID := 0;
  FRemote_p2pID := 0;
  FillPtrByte(@FIP, SizeOf(FIP), 0);
  FPort := 0;
  FDestroySyncRemote := True;

  if not OwnerFramework.FQuietMode then
      OwnerFramework.Print('VM-IO Create %d', [ID]);
end;

destructor TP2PVM_PeerIO.Destroy;
var
  i: Integer;
  c_: TZNet_WithP2PVM_Client;
  LID: Cardinal;
begin
  LID := 0;
  if Connected then
    begin
      if (FDestroySyncRemote) and (FLinkVM <> nil) then
          FLinkVM.SendDisconnect(Remote_frameworkID, Remote_p2pID);

      LID := ID;
      if not OwnerFramework.FQuietMode then
          OwnerFramework.Print('VMClientIO %d disconnect', [LID]);
      if OwnerFramework is TZNet_WithP2PVM_Client then
        begin
          c_ := TZNet_WithP2PVM_Client(OwnerFramework);
          c_.DoDisconnect(self);
          c_.FVMClientIO := nil;
          c_.FVMConnected := False;
        end;
    end;

  while FSendQueue.Num > 0 do
    begin
      TZNet_P2PVM.FreeP2PVMPacket(FSendQueue.current^.data);
      FSendQueue.Next;
    end;
  DisposeObject(FSendQueue);
  DisposeObject(FRealSendBuff);

  if not OwnerFramework.FQuietMode then
      OwnerFramework.Print('VM-IO Destroy %d', [LID]);
  inherited Destroy;
end;

function TP2PVM_PeerIO.Connected: Boolean;
begin
  if FLinkVM = nil then
      Result := False
  else if OwnerFramework is TZNet_WithP2PVM_Server then
      Result := (FLinkVM.FOwner_IO <> nil)
  else if OwnerFramework is TZNet_WithP2PVM_Client then
      Result := TZNet_WithP2PVM_Client(OwnerFramework).Connected
  else
      Result := False;
end;

procedure TP2PVM_PeerIO.Disconnect;
begin
  Free;
end;

procedure TP2PVM_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: NativeInt);
begin
  if Size <= 0 then
      exit;
  FRealSendBuff.Position := FRealSendBuff.Size;
  FRealSendBuff.WritePtr(buff, Size);
end;

procedure TP2PVM_PeerIO.WriteBufferOpen;
begin
  FRealSendBuff.Clear;
end;

procedure TP2PVM_PeerIO.WriteBufferFlush;
var
  p: PByte;
  siz: Int64;
begin
  if FRealSendBuff.Size <= 0 then
      exit;

  if (FLinkVM <> nil) and (Connected) then
    begin
      p := FRealSendBuff.Memory;
      siz := FRealSendBuff.Size;

      { send fragment }
      while siz > FLinkVM.FMaxVMFragmentSize do
        begin
          FSendQueue.Push(FLinkVM.Build_P2PVM_Packet(FLinkVM.FMaxVMFragmentSize, FRemote_frameworkID, FRemote_p2pID, ZNet_Def_p2pVM_LogicFragmentData, p));
          inc(p, FLinkVM.FMaxVMFragmentSize);
          dec(siz, FLinkVM.FMaxVMFragmentSize);
        end;

      if siz > 0 then
          FSendQueue.Push(FLinkVM.Build_P2PVM_Packet(siz, FRemote_frameworkID, FRemote_p2pID, ZNet_Def_p2pVM_LogicFragmentData, p));
    end;

  FRealSendBuff.Clear;
end;

procedure TP2PVM_PeerIO.WriteBufferClose;
begin
  WriteBufferFlush;
end;

function TP2PVM_PeerIO.GetPeerIP: SystemString;
begin
  Result := IPv6ToStr(FIP).Text;
  if (FLinkVM <> nil) and (FLinkVM.FOwner_IO <> nil) then
      Result := FLinkVM.FOwner_IO.PeerIP + '-Virtual(' + Result + ')';
end;

function TP2PVM_PeerIO.WriteBuffer_is_NULL: Boolean;
begin
  Result := (FRealSendBuff.Size <= 0) and (FSendQueue.Num <= 0);
end;

function TP2PVM_PeerIO.WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean;
var
  p: TP2P_VM_Fragment_Packet_Pool.POrderStruct;
  i: NativeInt;
begin
  Result := not WriteBuffer_is_NULL;
  WriteBuffer_Queue_Num := FSendQueue.Num;
  WriteBuffer_Size := 0;

  if FSendQueue.Num > 0 then
    begin
      i := FSendQueue.Num;
      p := FSendQueue.First;
      while True do
        begin
          inc(WriteBuffer_Size, p^.data^.BuffSiz);
          dec(i);
          if i > 0 then
              p := p^.Next
          else
              Break;
        end;
    end;
end;

procedure TP2PVM_PeerIO.Progress;
begin
  inherited Progress;
  Process_Send_Buffer();
end;

procedure TZNet_WithP2PVM_Server.Connecting(SenderVM: TZNet_P2PVM;
  const Remote_frameworkID, FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; var Allowed: Boolean);
var
  p: PP2PVMListen;
  LocalVMc: TP2PVM_PeerIO;
begin
  if FLinkVMPool.Count = 0 then
    begin
      Allowed := False;
      exit;
    end;

  p := SenderVM.FindListen(IPV6, Port);
  Allowed := (p <> nil) and (p^.FrameworkID = FrameworkID);

  if Allowed then
    begin
      { build io }
      LocalVMc := TP2PVM_PeerIO.Create(self, nil);
      LocalVMc.FLinkVM := SenderVM;
      LocalVMc.FRemote_frameworkID := Remote_frameworkID;
      LocalVMc.FRemote_p2pID := 0;
      LocalVMc.FIP := IPV6;
      LocalVMc.FPort := Port;

      { connected reponse }
      SenderVM.SendConnectedReponse(LocalVMc.FRemote_frameworkID, LocalVMc.FRemote_p2pID, FrameworkID, LocalVMc.ID);

      if not FQuietMode then
          Print('Virtual connecting with "%s port:%d"', [IPv6ToStr(IPV6).Text, Port]);
    end;
end;

procedure TZNet_WithP2PVM_Server.ListenState(SenderVM: TZNet_P2PVM; const IPV6: TIPV6; const Port: Word; const State: Boolean);
begin
  if not FQuietMode then
    begin
      if State then
          Print('Virtual Addr: "%s Port:%d" Listen is open', [IPv6ToStr(IPV6).Text, Port])
      else
          Print('Virtual Addr: "%s Port:%d" Listen close!', [IPv6ToStr(IPV6).Text, Port]);
    end;
end;

procedure TZNet_WithP2PVM_Server.ProgressDisconnectClient(P_IO: TPeerIO);
begin
  DisposeObject(P_IO);
end;

function TZNet_WithP2PVM_Server.ListenCount: Integer;
begin
  Result := FFrameworkListenPool.Count;
end;

function TZNet_WithP2PVM_Server.GetListen(const index: Integer): PP2PVMListen;
begin
  Result := FFrameworkListenPool[index];
end;

function TZNet_WithP2PVM_Server.FindListen(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
var
  i: Integer;
  p: PP2PVMListen;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
    begin
      p := FFrameworkListenPool[i];
      if (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Result := p;
          exit;
        end;
    end;
  Result := nil;
end;

function TZNet_WithP2PVM_Server.FindListening(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
var
  i: Integer;
  p: PP2PVMListen;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
    begin
      p := FFrameworkListenPool[i];
      if (p^.Listening) and (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Result := p;
          exit;
        end;
    end;
  Result := nil;
end;

procedure TZNet_WithP2PVM_Server.DeleteListen(const IPV6: TIPV6; const Port: Word);
var
  i: Integer;
  p: PP2PVMListen;
begin
  i := 0;
  while i < FFrameworkListenPool.Count do
    begin
      p := FFrameworkListenPool[i];
      if (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Dispose(p);
          FFrameworkListenPool.Delete(i);
        end
      else
          inc(i);
    end;
end;

procedure TZNet_WithP2PVM_Server.ClearListen;
var
  i: Integer;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
      Dispose(PP2PVMListen(FFrameworkListenPool[i]));
  FFrameworkListenPool.Clear;
end;

constructor TZNet_WithP2PVM_Server.Create;
begin
  CustomCreate(20 * 10000, 0);
end;

constructor TZNet_WithP2PVM_Server.CustomCreate(HashPoolSize: Integer; FrameworkID: Cardinal);
begin
  inherited CreateCustomHashPool(HashPoolSize);
  EnabledAtomicLockAndMultiThread := False;
  SequencePacketActivted := {$IFDEF UsedSequencePacketOnP2PVM}True{$ELSE UsedSequencePacketOnP2PVM}False{$ENDIF UsedSequencePacketOnP2PVM};

  FFrameworkListenPool := TCore_List.Create;
  FLinkVMPool := TUInt32HashObjectList.Create;
  FFrameworkWithVM_ID := FrameworkID;
  StopService;
  name := 'VMServer';
end;

destructor TZNet_WithP2PVM_Server.Destroy;
var
  i: Integer;
  L: TCore_List;
  p: PUInt32HashListObjectStruct;
begin
  CloseAllClient;
  ClearListen;

  if (FLinkVMPool.Count > 0) then
    begin
      L := TCore_List.Create;
      try
        FLinkVMPool.GetListData(L);
        for i := 0 to L.Count - 1 do
          begin
            p := L[i];
            (TZNet_P2PVM(p^.data)).UninstallLogicFramework(self);
          end;
      except
      end;
      DisposeObject(L);
    end;

  DisposeObject(FLinkVMPool);
  DisposeObject(FFrameworkListenPool);
  inherited Destroy;
end;

procedure TZNet_WithP2PVM_Server.Progress;
begin
  inherited Progress;
end;

procedure TZNet_WithP2PVM_Server.CloseAllClient;
begin
  ProgressPeerIOM(ProgressDisconnectClient);
end;

procedure TZNet_WithP2PVM_Server.ProgressStopServiceWithPerVM(SenderVM: TZNet_P2PVM);
var
  i: Integer;
  p: PP2PVMListen;
  lst: TCore_List;
begin
  lst := TCore_List.Create;

  for i := 0 to SenderVM.ListenCount - 1 do
    begin
      p := SenderVM.GetListen(i);
      if SenderVM.FFrameworkPool[p^.FrameworkID] = self then
          lst.Add(p);
    end;

  for i := 0 to lst.Count - 1 do
    begin
      p := lst[i];
      SenderVM.SendListen(p^.FrameworkID, p^.ListenHost, p^.ListenPort, False);
    end;
  DisposeObject(lst);
end;

procedure TZNet_WithP2PVM_Server.StopService;
var
  i: Integer;
  p: PUInt32HashListObjectStruct;
begin
  if (FLinkVMPool.Count > 0) then
    begin
      i := 0;
      p := FLinkVMPool.FirstPtr;
      while i < FLinkVMPool.Count do
        begin
          try
              ProgressStopServiceWithPerVM(TZNet_P2PVM(p^.data));
          except
          end;
          inc(i);
          p := p^.Next;
        end;
    end;

  ClearListen;

  CloseAllClient;
end;

function TZNet_WithP2PVM_Server.StartService(Host_: SystemString; Port: Word): Boolean;
var
  IPV6: TIPV6;
  SI: Cardinal;
  i: Integer;
  p: PUInt32HashListObjectStruct;
  LP: PP2PVMListen;
begin
  Result := False;

  if umlTrimSpace(Host_).L = 0 then
      IPV6 := MakeRandomIPV6()
  else
    begin
      IPV6 := StrToIPv6(Host_, Result, SI);
      if not Result then
          exit;
    end;

  LP := FindListen(IPV6, Port);
  if LP = nil then
    begin
      New(LP);
      LP^.FrameworkID := FFrameworkWithVM_ID;
      LP^.ListenHost := IPV6;
      LP^.ListenPort := Port;
      LP^.Listening := True;
      FFrameworkListenPool.Add(LP);
    end
  else
      LP^.Listening := True;

  if (FLinkVMPool.Count > 0) then
    begin
      i := 0;
      p := FLinkVMPool.FirstPtr;
      while i < FLinkVMPool.Count do
        begin
          try
              TZNet_P2PVM(p^.data).SendListen(FFrameworkWithVM_ID, IPV6, Port, True);
          except
          end;
          inc(i);
          p := p^.Next;
        end;
    end
  else
    begin
      ListenState(nil, IPV6, Port, True);
    end;
  Result := True;
end;

function TZNet_WithP2PVM_Server.WaitSendConsoleCmd(P_IO: TPeerIO; const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport VM server');
end;

procedure TZNet_WithP2PVM_Server.WaitSendStreamCmd(P_IO: TPeerIO; const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
begin
  RaiseInfo('WaitSend no Suppport VM server');
end;

procedure TZNet_WithP2PVM_Client.Framework_Internal_IO_Create(const Sender: TPeerIO);
begin
  inherited Framework_Internal_IO_Create(Sender);
end;

procedure TZNet_WithP2PVM_Client.Framework_Internal_IO_Destroy(const Sender: TPeerIO);
begin
  FVMClientIO := nil;
  FVMConnected := False;
  inherited Framework_Internal_IO_Destroy(Sender);
end;

procedure TZNet_WithP2PVM_Client.VMConnectSuccessed(SenderVM: TZNet_P2PVM; Remote_frameworkID, Remote_p2pID, FrameworkID: Cardinal);
begin
  FVMClientIO.FRemote_frameworkID := Remote_frameworkID;
  FVMClientIO.FRemote_p2pID := Remote_p2pID;

  FVMConnected := True;
  DoConnected(FVMClientIO);
end;

procedure TZNet_WithP2PVM_Client.VMDisconnect(SenderVM: TZNet_P2PVM);
begin
  FVMConnected := False;
  TriggerDoConnectFailed;
  if FVMClientIO <> nil then
      FVMClientIO.Disconnect;
end;

constructor TZNet_WithP2PVM_Client.Create;
begin
  CustomCreate(0);
end;

constructor TZNet_WithP2PVM_Client.CustomCreate(FrameworkID: Cardinal);
begin
  inherited Create;
  EnabledAtomicLockAndMultiThread := False;
  SequencePacketActivted := {$IFDEF UsedSequencePacketOnP2PVM}True{$ELSE UsedSequencePacketOnP2PVM}False{$ENDIF UsedSequencePacketOnP2PVM};
  FLinkVM := nil;
  FFrameworkWithVM_ID := FrameworkID;
  FVMClientIO := nil;
  FVMConnected := False;
  FP2PVM_ClonePool := TZNet_WithP2PVM_Client_Clone_Pool.Create;
  FP2PVM_ClonePool_Ptr := nil;
  FP2PVM_CloneOwner := nil;
  FP2PVM_Clone_NextProgressDoFreeSelf := False;
  FP2PVM_ProgressWaitSend_Busy := False;
  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
  name := 'VMClientIO';
end;

destructor TZNet_WithP2PVM_Client.Destroy;
begin
  try
    if (FP2PVM_CloneOwner <> nil) and (FP2PVM_ClonePool_Ptr <> nil) then
        FP2PVM_CloneOwner.FP2PVM_ClonePool.Remove_P(FP2PVM_ClonePool_Ptr);

    FP2PVM_CloneOwner := nil;
    FP2PVM_ClonePool_Ptr := nil;

    while FP2PVM_ClonePool.Num > 0 do
      begin
        FP2PVM_ClonePool.First^.data.FP2PVM_CloneOwner := nil;
        FP2PVM_ClonePool.First^.data.FP2PVM_ClonePool_Ptr := nil;
        DisposeObjectAndNil(FP2PVM_ClonePool.First^.data);
        FP2PVM_ClonePool.Next;
      end;
  except
  end;

  if FVMClientIO <> nil then
      DisposeObjectAndNil(FVMClientIO);
  if FLinkVM <> nil then
      FLinkVM.UninstallLogicFramework(self);
  DisposeObjectAndNil(FP2PVM_ClonePool);
  inherited Destroy;
end;

function TZNet_WithP2PVM_Client.CloneConnectC(OnResult: TOnP2PVM_CloneConnectEvent_C): TP2PVM_CloneConnectEventBridge;
var
  Bridge_: TP2PVM_CloneConnectEventBridge;
begin
  Result := nil;
  if not Assigned(OnResult) then
      exit;
  if (FLinkVM = nil) or (not Connected) then
      exit;
  Bridge_ := TP2PVM_CloneConnectEventBridge.Create(self);
  Bridge_.NewClient := TZNet_WithP2PVM_Client.Create;
  { copy parameter }
  Bridge_.NewClient.CopyParamFrom(self);
  Bridge_.NewClient.name := Bridge_.NewClient.name + '.Clone';
  { init event }
  Bridge_.OnResultC := OnResult;
  Bridge_.NewClient.FP2PVM_CloneOwner := self;
  LinkVM.InstallLogicFramework(Bridge_.NewClient);
  Bridge_.NewClient.FP2PVM_ClonePool_Ptr := FP2PVM_ClonePool.Add(Bridge_.NewClient);
  Bridge_.NewClient.AsyncConnectM(IPv6ToStr(FVMClientIO.FIP), FVMClientIO.FPort, Bridge_.DoAsyncConnectState);
  Result := Bridge_;
end;

function TZNet_WithP2PVM_Client.CloneConnectM(OnResult: TOnP2PVM_CloneConnectEvent_M): TP2PVM_CloneConnectEventBridge;
var
  Bridge_: TP2PVM_CloneConnectEventBridge;
begin
  Result := nil;
  if not Assigned(OnResult) then
      exit;
  if (FLinkVM = nil) or (not Connected) then
      exit;
  Bridge_ := TP2PVM_CloneConnectEventBridge.Create(self);
  Bridge_.NewClient := TZNet_WithP2PVM_Client.Create;
  { copy parameter }
  Bridge_.NewClient.CopyParamFrom(self);
  Bridge_.NewClient.name := name + '.Clone';
  { init event }
  Bridge_.OnResultM := OnResult;
  Bridge_.NewClient.FP2PVM_CloneOwner := self;
  LinkVM.InstallLogicFramework(Bridge_.NewClient);
  Bridge_.NewClient.FP2PVM_ClonePool_Ptr := FP2PVM_ClonePool.Add(Bridge_.NewClient);
  Bridge_.NewClient.AsyncConnectM(IPv6ToStr(FVMClientIO.FIP), FVMClientIO.FPort, Bridge_.DoAsyncConnectState);
  Result := Bridge_;
end;

function TZNet_WithP2PVM_Client.CloneConnectP(OnResult: TOnP2PVM_CloneConnectEvent_P): TP2PVM_CloneConnectEventBridge;
var
  Bridge_: TP2PVM_CloneConnectEventBridge;
begin
  Result := nil;
  if not Assigned(OnResult) then
      exit;
  if (FLinkVM = nil) or (not Connected) then
      exit;
  Bridge_ := TP2PVM_CloneConnectEventBridge.Create(self);
  Bridge_.NewClient := TZNet_WithP2PVM_Client.Create;
  { copy parameter }
  Bridge_.NewClient.CopyParamFrom(self);
  Bridge_.NewClient.name := Bridge_.NewClient.name + '.Clone';
  { init event }
  Bridge_.OnResultP := OnResult;
  Bridge_.NewClient.FP2PVM_CloneOwner := self;
  LinkVM.InstallLogicFramework(Bridge_.NewClient);
  Bridge_.NewClient.FP2PVM_ClonePool_Ptr := FP2PVM_ClonePool.Add(Bridge_.NewClient);
  Bridge_.NewClient.AsyncConnectM(IPv6ToStr(FVMClientIO.FIP), FVMClientIO.FPort, Bridge_.DoAsyncConnectState);
  Result := Bridge_;
end;

procedure TZNet_WithP2PVM_Client.TriggerDoConnectFailed;
begin
  inherited TriggerDoConnectFailed;

  try
    if Assigned(FOnP2PVMAsyncConnectNotify_C) then
        FOnP2PVMAsyncConnectNotify_C(False)
    else if Assigned(FOnP2PVMAsyncConnectNotify_M) then
        FOnP2PVMAsyncConnectNotify_M(False)
    else if Assigned(FOnP2PVMAsyncConnectNotify_P) then
        FOnP2PVMAsyncConnectNotify_P(False);
  except
  end;

  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
end;

procedure TZNet_WithP2PVM_Client.TriggerDoConnectFinished;
begin
  inherited TriggerDoConnectFinished;

  try
    if Assigned(FOnP2PVMAsyncConnectNotify_C) then
        FOnP2PVMAsyncConnectNotify_C(True)
    else if Assigned(FOnP2PVMAsyncConnectNotify_M) then
        FOnP2PVMAsyncConnectNotify_M(True)
    else if Assigned(FOnP2PVMAsyncConnectNotify_P) then
        FOnP2PVMAsyncConnectNotify_P(True);
  except
  end;

  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
end;

function TZNet_WithP2PVM_Client.Connected: Boolean;
begin
  Result := (FVMConnected) and (FVMClientIO <> nil);
end;

function TZNet_WithP2PVM_Client.ClientIO: TPeerIO;
begin
  Result := FVMClientIO;
end;

procedure TZNet_WithP2PVM_Client.Progress;
var
  __repeat__: TZNet_WithP2PVM_Client_Clone_Pool.TRepeat___;
begin
  inherited Progress;
  if not FProgressEnabled then
      exit;
  if FP2PVM_ClonePool.Num > 0 then
    begin
      __repeat__ := FP2PVM_ClonePool.Repeat_();
      repeat
        if __repeat__.Queue^.data.FP2PVM_Clone_NextProgressDoFreeSelf then
          begin
            __repeat__.Queue^.data.FP2PVM_CloneOwner := nil;
            __repeat__.Queue^.data.FP2PVM_ClonePool_Ptr := nil;
            FP2PVM_ClonePool.Push_To_Recycle_Pool(__repeat__.Queue);
            PostProgress.PostDelayFreeObject(0.1, __repeat__.Queue^.data);
          end
        else
            __repeat__.Queue^.data.Progress;
      until not __repeat__.Next;
      FP2PVM_ClonePool.Free_Recycle_Pool;
    end;
end;

procedure TZNet_WithP2PVM_Client.AsyncConnect(addr: SystemString; Port: Word);
var
  R: Boolean;
  IPV6: TIPV6;
  p: PP2PVMListen;
begin
  Disconnect;
  if FLinkVM = nil then
      RaiseInfo('no vm reference');
  FVMClientIO := TP2PVM_PeerIO.Create(self, nil);
  FVMClientIO.FLinkVM := FLinkVM;

  FVMConnected := False;

  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
  if (FLinkVM = nil) or (FLinkVM.FOwner_IO = nil) then
    begin
      Error('no VM connect');
      TriggerDoConnectFailed;
      exit;
    end;

  if not FLinkVM.WasAuthed then
    begin
      Error('VM no auth');
      TriggerDoConnectFailed;
      exit;
    end;

  IPV6 := StrToIPv6(addr, R);

  if not R then
    begin
      Error('ipv6 format error! %s', [addr]);
      TriggerDoConnectFailed;
      exit;
    end;

  p := FLinkVM.FindListen(IPV6, Port);
  if p = nil then
    begin
      Error('no remote listen %s port:%d', [IPv6ToStr(IPV6).Text, Port]);
      TriggerDoConnectFailed;
      exit;
    end;

  FVMClientIO.FIP := IPV6;
  FVMClientIO.FPort := Port;

  FLinkVM.SendConnecting(p^.FrameworkID, FFrameworkWithVM_ID, FVMClientIO.ID, IPV6, Port);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C);
var
  R: Boolean;
  IPV6: TIPV6;
  p: PP2PVMListen;
begin
  Disconnect;
  if FLinkVM = nil then
      RaiseInfo('no vm reference');
  FVMClientIO := TP2PVM_PeerIO.Create(self, nil);
  FVMClientIO.FLinkVM := FLinkVM;

  FVMConnected := False;

  FOnP2PVMAsyncConnectNotify_C := OnResult;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
  if (FLinkVM = nil) or (FLinkVM.FOwner_IO = nil) then
    begin
      Error('no VM connect');
      TriggerDoConnectFailed;
      exit;
    end;

  if not FLinkVM.WasAuthed then
    begin
      Error('VM no auth');
      TriggerDoConnectFailed;
      exit;
    end;

  IPV6 := StrToIPv6(addr, R);

  if not R then
    begin
      Error('ipv6 format error! %s', [addr]);
      TriggerDoConnectFailed;
      exit;
    end;

  p := FLinkVM.FindListen(IPV6, Port);
  if p = nil then
    begin
      Error('no remote listen %s port:%d', [IPv6ToStr(IPV6).Text, Port]);
      TriggerDoConnectFailed;
      exit;
    end;

  FVMClientIO.FIP := IPV6;
  FVMClientIO.FPort := Port;

  FLinkVM.SendConnecting(p^.FrameworkID, FFrameworkWithVM_ID, FVMClientIO.ID, IPV6, Port);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M);
var
  R: Boolean;
  IPV6: TIPV6;
  p: PP2PVMListen;
begin
  Disconnect;
  if FLinkVM = nil then
      RaiseInfo('no vm reference');
  FVMClientIO := TP2PVM_PeerIO.Create(self, nil);
  FVMClientIO.FLinkVM := FLinkVM;

  FVMConnected := False;

  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := OnResult;
  FOnP2PVMAsyncConnectNotify_P := nil;

  if (FLinkVM = nil) or (FLinkVM.FOwner_IO = nil) then
    begin
      Error('no VM connect');
      TriggerDoConnectFailed;
      exit;
    end;

  if not FLinkVM.WasAuthed then
    begin
      Error('VM no auth');
      TriggerDoConnectFailed;
      exit;
    end;

  IPV6 := StrToIPv6(addr, R);

  if not R then
    begin
      Error('ipv6 format error! %s', [addr]);
      TriggerDoConnectFailed;
      exit;
    end;

  p := FLinkVM.FindListen(IPV6, Port);
  if p = nil then
    begin
      Error('no remote listen %s port:%d', [IPv6ToStr(IPV6).Text, Port]);
      TriggerDoConnectFailed;
      exit;
    end;

  FVMClientIO.FIP := IPV6;
  FVMClientIO.FPort := Port;

  FLinkVM.SendConnecting(p^.FrameworkID, FFrameworkWithVM_ID, FVMClientIO.ID, IPV6, Port);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P);
var
  R: Boolean;
  IPV6: TIPV6;
  p: PP2PVMListen;
begin
  Disconnect;
  if FLinkVM = nil then
      RaiseInfo('no vm reference');
  FVMClientIO := TP2PVM_PeerIO.Create(self, nil);
  FVMClientIO.FLinkVM := FLinkVM;

  FVMConnected := False;

  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := OnResult;

  if (FLinkVM = nil) or (FLinkVM.FOwner_IO = nil) then
    begin
      Error('no VM connect');
      TriggerDoConnectFailed;
      exit;
    end;

  if not FLinkVM.WasAuthed then
    begin
      Error('VM no auth');
      TriggerDoConnectFailed;
      exit;
    end;

  IPV6 := StrToIPv6(addr, R);

  if not R then
    begin
      Error('ipv6 format error! %s', [addr]);
      TriggerDoConnectFailed;
      exit;
    end;

  p := FLinkVM.FindListen(IPV6, Port);
  if p = nil then
    begin
      Error('no remote listen %s port:%d', [IPv6ToStr(IPV6).Text, Port]);
      TriggerDoConnectFailed;
      exit;
    end;

  FVMClientIO.FIP := IPV6;
  FVMClientIO.FPort := Port;

  FLinkVM.SendConnecting(p^.FrameworkID, FFrameworkWithVM_ID, FVMClientIO.ID, IPV6, Port);
end;

function TZNet_WithP2PVM_Client.Connect(addr: SystemString; Port: Word): Boolean;
var
  IPV6: TIPV6;
  p: PP2PVMListen;
  t: TTimeTick;
begin
  Disconnect;
  if FLinkVM = nil then
      RaiseInfo('no vm reference');
  FVMClientIO := TP2PVM_PeerIO.Create(self, nil);
  FVMClientIO.FLinkVM := FLinkVM;

  Result := False;

  FVMConnected := False;
  FOnP2PVMAsyncConnectNotify_C := nil;
  FOnP2PVMAsyncConnectNotify_M := nil;
  FOnP2PVMAsyncConnectNotify_P := nil;
  if (FLinkVM = nil) or (FLinkVM.FOwner_IO = nil) then
    begin
      Error('no VM connect');
      exit;
    end;

  if not FLinkVM.WasAuthed then
    begin
      Error('VM no auth');
      exit;
    end;

  IPV6 := StrToIPv6(addr, Result);

  if not Result then
    begin
      Error('ipv6 format error! %s', [addr]);
      exit;
    end;

  p := FLinkVM.FindListen(IPV6, Port);
  if p = nil then
    begin
      Error('no remote listen %s port:%d', [IPv6ToStr(IPV6).Text, Port]);
      exit;
    end;

  FVMClientIO.FIP := IPV6;
  FVMClientIO.FPort := Port;
  FLinkVM.SendConnecting(p^.FrameworkID, FFrameworkWithVM_ID, FVMClientIO.ID, IPV6, Port);

  t := GetTimeTick + 1000;
  while not FVMConnected do
    begin
      ProgressWaitSend(FVMClientIO);
      if GetTimeTick > t then
          Break;
    end;

  t := GetTimeTick + 2000;
  while (FVMConnected) and (not RemoteInited) do
    begin
      ProgressWaitSend(FVMClientIO);
      if GetTimeTick > t then
          Break;
    end;

  Result := (FVMConnected) and (RemoteInited);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectC(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_C);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyC := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectM(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_M);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyM := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

procedure TZNet_WithP2PVM_Client.AsyncConnectP(addr: SystemString; Port: Word; Param1: Pointer; Param2: TObject; const OnResult: TOnParamState_P);
var
  ParamBridge: TState_Param_Bridge;
begin
  ParamBridge := TState_Param_Bridge.Create;
  ParamBridge.Param1 := Param1;
  ParamBridge.Param2 := Param2;
  ParamBridge.OnNotifyP := OnResult;
  AsyncConnectM(addr, Port, ParamBridge.OnStateMethod);
end;

procedure TZNet_WithP2PVM_Client.Disconnect;
var
  __repeat__: TZNet_WithP2PVM_Client_Clone_Pool.TRepeat___;
begin
  if FP2PVM_ClonePool.Num > 0 then
    begin
      __repeat__ := FP2PVM_ClonePool.Repeat_();
      repeat
          __repeat__.Queue^.data.Disconnect;
      until not __repeat__.Next;
    end;

  if FVMClientIO <> nil then
      FVMClientIO.Disconnect;
end;

procedure TZNet_WithP2PVM_Client.DoBackCall_Progress(Sender: TZNet);
begin
  Sender.Progress;
end;

procedure TZNet_WithP2PVM_Client.ProgressWaitSend(P_IO: TPeerIO);
begin
  if FP2PVM_ProgressWaitSend_Busy then
      exit;

  FP2PVM_ProgressWaitSend_Busy := True;
  try
    if FLinkVM <> nil then
      begin
        if FLinkVM.FOwner_IO <> nil then
            FLinkVM.FOwner_IO.OwnerFramework.ProgressWaitSend(FLinkVM.FOwner_IO);
        FLinkVM.Progress;
        FLinkVM.ProgressZNet_M(DoBackCall_Progress);
      end;
    inherited ProgressWaitSend(P_IO);
  finally
      FP2PVM_ProgressWaitSend_Busy := False;
  end;
end;

procedure TZNet_P2PVM.Hook_SendByteBuffer(const Sender: TPeerIO; const buff: PByte; siz: NativeInt);
var
  p: PP2PVMFragmentPacket;
begin
  if siz <= 0 then
      exit;

  if FAuthed then
    begin
      p := Build_P2PVM_Packet(siz, 0, 0, ZNet_Def_p2pVM_OwnerIOFragmentData, buff);
      p^.Build_P2PVM_Send_Buffer(FSendStream);
      FreeP2PVMPacket(p);
    end
  else
    begin
      FSendStream.WritePtr(buff, siz);
    end;
end;

procedure TZNet_P2PVM.Hook_SaveReceiveBuffer(const Sender: TPeerIO; const buff: Pointer; siz: Int64);
begin
  if siz <= 0 then
      exit;

  FReceiveStream.Position := FReceiveStream.Size;
  FReceiveStream.WritePtr(buff, siz);
end;

procedure TZNet_P2PVM.Hook_ProcessReceiveBuffer(const Sender: TPeerIO);
  function Extract_P2PVM_Receive_Buffer(var fPk: TP2PVMFragmentPacket; const Stream: TMem64): Integer;
  begin
    Result := 0;
    if Stream.Size < 13 then
      begin
        fPk.Init;
        exit;
      end;
    if Stream.Size < PCardinal(Stream.PositionAsPtr(0))^ + 13 then
      begin
        fPk.Init;
        exit;
      end;
    fPk.BuffSiz := PCardinal(Stream.PositionAsPtr(0))^;
    fPk.FrameworkID := PCardinal(Stream.PositionAsPtr(4))^;
    fPk.p2pID := PCardinal(Stream.PositionAsPtr(8))^;
    fPk.pkType := PByte(Stream.PositionAsPtr(12))^;
    if fPk.BuffSiz > 0 then
        fPk.buff := Stream.PositionAsPtr(13)
    else
        fPk.buff := nil;
    Result := fPk.BuffSiz + 13;
  end;

var
  i: Integer;
  LP: PP2PVMListen;
  p64: Int64;
  sourStream: TMem64;
  fPk: TP2PVMFragmentPacket;
  rPos: Integer;
begin
  if FReceiveStream.Size <= 0 then
      exit;

  if FOwner_IO <> nil then
    begin
      FOwner_IO.UpdateLastCommunicationTime;
      FOwner_IO.LastCommunicationTick_Received := FOwner_IO.FLastCommunicationTick;
      FOwner_IO.LastCommunicationTick_KeepAlive := FOwner_IO.LastCommunicationTick_Received;
    end;

  { p2p auth }
  if not FAuthed then
    begin
      if (FAuthWaiting) and (FReceiveStream.Size >= Length(FOwner_IO.FP2PVM_Auth_Token)) and
        (CompareMemory(@FOwner_IO.FP2PVM_Auth_Token[0], FReceiveStream.Memory, Length(FOwner_IO.FP2PVM_Auth_Token))) then
        begin
          FSendStream.Clear;

          if not FAuthSending then
              AuthVM;

          FAuthWaiting := False;
          FAuthed := True;
          FAuthSending := False;

          { sync listen state }
          for i := 0 to FFrameworkListenPool.Count - 1 do
            begin
              LP := FFrameworkListenPool[i];
              SendListenState(LP^.FrameworkID, LP^.ListenHost, LP^.ListenPort, LP^.Listening);
            end;

          { send auth successed token }
          AuthSuccessed;

          { fill fragment buffer }
          p64 := Length(FOwner_IO.FP2PVM_Auth_Token);
          sourStream := TMem64.Create;
          FReceiveStream.Position := p64;
          if FReceiveStream.Size - FReceiveStream.Position > 0 then
              sourStream.CopyFrom(FReceiveStream, FReceiveStream.Size - FReceiveStream.Position);
          DisposeObject(FReceiveStream);
          FReceiveStream := sourStream;

          if not FQuietMode then
              FOwner_IO.Print('VM Authentication Success');
        end
      else if FAuthWaiting then
          exit
      else
        begin
          { safe process fragment }
          if FReceiveStream.Size >= Length(FOwner_IO.FP2PVM_Auth_Token) then
            begin
              FOwner_IO.OwnerFramework.Framework_Internal_Save_Receive_Buffer(FOwner_IO, FReceiveStream.Memory, FReceiveStream.Size);
              FReceiveStream.Clear;
              FOwner_IO.OwnerFramework.Framework_Internal_Process_Receive_Buffer(FOwner_IO);
            end;
          exit;
        end;
    end;

  if FReceiveStream.Size < 13 then
      exit;

  sourStream := TMem64.Create;
  p64 := 0;
  sourStream.SetPointerWithProtectedMode(FReceiveStream.PositionAsPtr(p64), FReceiveStream.Size - p64);

  while sourStream.Size > 0 do
    begin
      fPk.Init;
      rPos := Extract_P2PVM_Receive_Buffer(fPk, sourStream);
      if rPos > 0 then
        begin
          { decrypt p2pVM packet data }
          if fPk.BuffSiz > 0 then
              FOwner_IO.FP2PVM_Cipher.Decrypt(fPk.buff, fPk.BuffSiz);
          { protocol support }
          if fPk.pkType = ZNet_Def_p2pVM_echoing then
              ReceivedEchoing(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_echo then
              ReceivedEcho(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_AuthSuccessed then
            begin
              if Assigned(OnAuthSuccessOnesNotify) then
                begin
                  try
                      OnAuthSuccessOnesNotify(self);
                  except
                  end;
                  OnAuthSuccessOnesNotify := nil;
                end;
            end
          else if fPk.pkType = ZNet_Def_p2pVM_Listen then
              ReceivedListen(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_ListenState then
              ReceivedListenState(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_Connecting then
              ReceivedConnecting(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_ConnectedReponse then
              ReceivedConnectedReponse(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_Disconnect then
              ReceivedDisconnect(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_LogicFragmentData then
              ReceivedLogicFragmentData(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else if fPk.pkType = ZNet_Def_p2pVM_OwnerIOFragmentData then
              ReceivedOwnerIOFragmentData(fPk.FrameworkID, fPk.p2pID, fPk.buff, fPk.BuffSiz)
          else
            begin
              FOwner_IO.PrintError('VM protocol header errror');
              DoStatus(@fPk, SizeOf(fPk), 40);
            end;

          { fill buffer }
          inc(p64, rPos);
          if FReceiveStream.Size - p64 >= 13 then
              sourStream.SetPointerWithProtectedMode(FReceiveStream.PositionAsPtr(p64), FReceiveStream.Size - p64)
          else
              Break;
        end
      else
          Break;
    end;

  DisposeObject(sourStream);

  if p64 > 0 then
    begin
      sourStream := TMem64.CustomCreate(64 * 1024);
      FReceiveStream.Position := p64;
      if FReceiveStream.Size - FReceiveStream.Position > 0 then
          sourStream.CopyFrom(FReceiveStream, FReceiveStream.Size - FReceiveStream.Position);
      DisposeObject(FReceiveStream);
      FReceiveStream := sourStream;
    end;
end;

procedure TZNet_P2PVM.Hook_ClientDestroy(const Sender: TPeerIO);
begin
  CloseP2PVMTunnel;
  Sender.OwnerFramework.Framework_Internal_IO_Destroy(Sender);
end;

procedure TZNet_P2PVM.SendVMBuffer(const buff: Pointer; const siz: NativeInt);
begin
  FOwner_IO.WriteBufferOpen;
  FOwner_IO.OwnerFramework.Framework_Internal_Send_Byte_Buffer(FOwner_IO, buff, siz);
  FOwner_IO.WriteBufferFlush;
  FOwner_IO.WriteBufferClose;
end;

procedure TZNet_P2PVM.ReceivedEchoing(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
begin
  echoBuffer(buff, siz);
end;

procedure TZNet_P2PVM.ReceivedEcho(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
type
  TBuf = array [0 .. 7] of Byte;
  PBuf = ^TBuf;
var
  p: PBuf;
  u64ptr: UInt64;
  echoPtr: PP2PVM_ECHO;
  i: Integer;
begin
  if siz <> SizeOf(TBuf) then
    begin
      FOwner_IO.PrintError('echoing protocol with buffer error!');
      if buff <> nil then
        if not FQuietMode then
            DoStatus(buff, siz, 40);
      exit;
    end;
  p := @buff^;
  u64ptr := PUInt64(@p^[0])^;
  echoPtr := Pointer(u64ptr);
  if echoPtr = nil then
      exit;

  i := 0;
  while i < FWaitEchoList.Count do
    begin
      if FWaitEchoList[i] = echoPtr then
        begin
          FWaitEchoList.Delete(i);
          try
            if Assigned(echoPtr^.OnEcho_C) then
                echoPtr^.OnEcho_C(True)
            else if Assigned(echoPtr^.OnEcho_M) then
                echoPtr^.OnEcho_M(True)
            else if Assigned(echoPtr^.OnEcho_P) then
                echoPtr^.OnEcho_P(True);
          except
          end;

          try
              Dispose(echoPtr);
          except
          end;
        end
      else
          inc(i);
    end;
end;

procedure TZNet_P2PVM.ReceivedListen(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
type
  TBuf = array [0 .. 18] of Byte;
  PBuf = ^TBuf;
var
  p: PBuf;
  IPV6: TIPV6;
  Port: Word;
  Listening: Boolean;
  LP: PP2PVMListen;
begin
  if siz <> SizeOf(TBuf) then
    begin
      FOwner_IO.PrintError('listen protocol with buffer error!');
      if buff <> nil then
        if not FQuietMode then
            DoStatus(buff, siz, 40);
      exit;
    end;
  p := @buff^;
  IPV6 := PIPV6(@p^[0])^;
  Port := PWORD(@p^[16])^;
  Listening := PBoolean(@p^[18])^;

  if p2pID <> 0 then
    begin
      FOwner_IO.PrintError('listen protocol error! IO ID:%d', [p2pID]);
      exit;
    end;

  LP := FindListen(IPV6, Port);
  if Listening then
    begin
      if LP = nil then
        begin
          New(LP);
          LP^.FrameworkID := FrameworkID;
          LP^.ListenHost := IPV6;
          LP^.ListenPort := Port;
          LP^.Listening := True;
          FFrameworkListenPool.Add(LP);
          SendListenState(FrameworkID, IPV6, Port, True);
        end
      else
        begin
          LP^.Listening := True;
          SendListenState(FrameworkID, IPV6, Port, True);
        end;
    end
  else
    begin
      DeleteListen(IPV6, Port);
      SendListenState(FrameworkID, IPV6, Port, False);
    end;
end;

procedure TZNet_P2PVM.ReceivedListenState(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
type
  TBuf = array [0 .. 18] of Byte;
  PBuf = ^TBuf;
var
  c: TZNet;
  p: PBuf;
  IPV6: TIPV6;
  Port: Word;
  Listening: Boolean;
  LP: PP2PVMListen;
begin
  if siz <> SizeOf(TBuf) then
    begin
      FOwner_IO.PrintError('Virtual listen state protocol with buffer error!');
      if buff <> nil then
        if not FQuietMode then
            DoStatus(buff, siz, 40);
      exit;
    end;
  p := @buff^;
  IPV6 := PIPV6(@p^[0])^;
  Port := PWORD(@p^[16])^;
  Listening := PBoolean(@p^[18])^;

  if p2pID <> 0 then
    begin
      FOwner_IO.PrintError('Virtual listen state protocol error! IO ID:%d', [p2pID]);
      exit;
    end;

  LP := FindListen(IPV6, Port);
  if Listening then
    begin
      if LP = nil then
        begin
          New(LP);
          LP^.FrameworkID := FrameworkID;
          LP^.ListenHost := IPV6;
          LP^.ListenPort := Port;
          LP^.Listening := True;
          FFrameworkListenPool.Add(LP);
        end
      else
        begin
          LP^.Listening := True;
        end;
      if not FQuietMode then
          FOwner_IO.Print('Virtual Remote Listen state Activted "%s port:%d"', [IPv6ToStr(IPV6).Text, Port]);
    end
  else
    begin
      DeleteListen(IPV6, Port);
      if not FQuietMode then
          FOwner_IO.Print('Virtual Remote Listen state Close "%s port:%d"', [IPv6ToStr(IPV6).Text, Port]);
    end;

  c := TZNet(FFrameworkPool[FrameworkID]);
  if c is TZNet_WithP2PVM_Server then
    begin
      TZNet_WithP2PVM_Server(c).ListenState(self, IPV6, Port, Listening);
      SendListenState(TZNet_WithP2PVM_Server(c).FFrameworkWithVM_ID, IPV6, Port, Listening);
    end;
end;

procedure TZNet_P2PVM.ReceivedConnecting(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
type
  TBuf = array [0 .. 25] of Byte;
  PBuf = ^TBuf;
var
  c: TZNet;
  p: PBuf;
  Remote_frameworkID: Cardinal;
  Remote_p2pID: Cardinal;
  IPV6: TIPV6;
  Port: Word;
  Allowed: Boolean;
begin
  if siz <> SizeOf(TBuf) then
    begin
      FOwner_IO.PrintError('connect request with buffer error!');
      if buff <> nil then
          DoStatus(buff, siz, 40);
      exit;
    end;
  p := @buff^;
  Remote_frameworkID := PCardinal(@p^[0])^;
  Remote_p2pID := PCardinal(@p^[4])^;
  IPV6 := PIPV6(@p^[8])^;
  Port := PWORD(@p^[24])^;

  if p2pID <> 0 then
    begin
      SendDisconnect(Remote_frameworkID, Remote_p2pID);
      FOwner_IO.PrintError('connect request with protocol error! IO ID:%d', [p2pID]);
      exit;
    end;

  c := TZNet(FFrameworkPool[FrameworkID]);
  if c is TZNet_WithP2PVM_Server then
    begin
      Allowed := True;
      TZNet_WithP2PVM_Server(c).Connecting(self, Remote_frameworkID, FrameworkID, IPV6, Port, Allowed);

      if not Allowed then
        begin
          SendDisconnect(Remote_frameworkID, 0);
          exit;
        end;
    end
  else
    begin
      SendDisconnect(Remote_frameworkID, Remote_p2pID);
    end;
end;

procedure TZNet_P2PVM.ReceivedConnectedReponse(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
type
  TBuf = array [0 .. 7] of Byte;
  PBuf = ^TBuf;
var
  c: TZNet;
  p: PBuf;
  Remote_frameworkID: Cardinal;
  Remote_p2pID: Cardinal;
begin
  if siz <> SizeOf(TBuf) then
    begin
      FOwner_IO.PrintError('connect request with buffer error!');
      if buff <> nil then
          DoStatus(buff, siz, 40);
      exit;
    end;

  c := TZNet(FFrameworkPool[FrameworkID]);
  if c is TZNet_WithP2PVM_Client then
    begin
      p := @buff^;
      Remote_frameworkID := PCardinal(@p^[0])^;
      Remote_p2pID := PCardinal(@p^[4])^;

      { trigger connect reponse }
      TZNet_WithP2PVM_Client(c).VMConnectSuccessed(self, Remote_frameworkID, Remote_p2pID, FrameworkID);

      if not FQuietMode then
          FOwner_IO.Print('connecting reponse from frameworkID: %d p2pID: %d', [Remote_frameworkID, Remote_p2pID]);
    end;
end;

procedure TZNet_P2PVM.ReceivedDisconnect(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
var
  c: TZNet;
  LocalVMc: TP2PVM_PeerIO;
begin
  c := TZNet(FFrameworkPool[FrameworkID]);
  if c is TZNet_WithP2PVM_Client then
    begin
      if TZNet_WithP2PVM_Client(c).FVMClientIO <> nil then
          TZNet_WithP2PVM_Client(c).FVMClientIO.FDestroySyncRemote := False;
      TZNet_WithP2PVM_Client(c).VMDisconnect(self);
    end
  else if c is TZNet_WithP2PVM_Server then
    begin
      LocalVMc := TP2PVM_PeerIO(c.FPeerIO_HashPool[p2pID]);
      if LocalVMc = nil then
        begin
          if not FQuietMode then
              FOwner_IO.Print('disconnect protocol no p2pID:%d', [p2pID]);
          exit;
        end;
      LocalVMc.FDestroySyncRemote := False;
      LocalVMc.Disconnect;
    end
  else if not FQuietMode then
      FOwner_IO.Print('disconnect protocol no frameworkID: %d', [FrameworkID]);
end;

procedure TZNet_P2PVM.ReceivedLogicFragmentData(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
var
  c: TZNet;
  LocalVMc: TPeerIO;
begin
  AtomInc(FOwner_IO.OwnerFramework.Statistics[TStatisticsType.stReceiveSize], siz);
  c := TZNet(FFrameworkPool[FrameworkID]);
  if c is TZNet_WithP2PVM_Server then
    begin
      LocalVMc := c.FPeerIO_HashPool[p2pID];
      if LocalVMc <> nil then
        begin
          LocalVMc.Write_Physics_Fragment(buff, siz);
        end
      else
        begin
          FOwner_IO.PrintError('fragment Data p2pID error: p2pID:%d buffer size:%d', [p2pID, siz]);
          DoStatus(buff, umlMin(siz, 164), 40);
        end;
    end
  else if c is TZNet_WithP2PVM_Client then
    begin
      LocalVMc := TZNet_WithP2PVM_Client(c).FVMClientIO;
      if LocalVMc <> nil then
        begin
          LocalVMc.Write_Physics_Fragment(buff, siz);
        end
      else
        begin
          FOwner_IO.PrintError('LocalVM [%d] error: no interface', [FrameworkID]);
        end;
    end
  else
    begin
      FOwner_IO.PrintError('fragment Data frameworkID error: frameworkID:%d buffer size:%d', [FrameworkID, siz]);
      DoStatus(buff, umlMin(siz, 164), 40);
    end;
end;

procedure TZNet_P2PVM.ReceivedOwnerIOFragmentData(const FrameworkID, p2pID: Cardinal; const buff: PByte; const siz: Cardinal);
begin
  if FOwner_IO = nil then
      exit;
  FOwner_IO.OwnerFramework.Framework_Internal_Save_Receive_Buffer(FOwner_IO, buff, siz);
  FOwner_IO.OwnerFramework.Framework_Internal_Process_Receive_Buffer(FOwner_IO);
end;

procedure TZNet_P2PVM.DoProcessPerClientFragmentSend(P_IO: TPeerIO);
var
  p: PP2PVMFragmentPacket;
begin
  if TP2PVM_PeerIO(P_IO).FLinkVM <> self then
      exit;

  if TP2PVM_PeerIO(P_IO).FSendQueue.Num > 0 then
    begin
      p := TP2PVM_PeerIO(P_IO).FSendQueue.current^.data;
      TP2PVM_PeerIO(P_IO).FSendQueue.Next;
      p^.Build_P2PVM_Send_Buffer(FSendStream);
      FreeP2PVMPacket(p);
    end;
end;

procedure TZNet_P2PVM.DoPerClientClose(P_IO: TPeerIO);
begin
  if TP2PVM_PeerIO(P_IO).FLinkVM = self then
    begin
      P_IO.Disconnect;
    end;
end;

constructor TZNet_P2PVM.Create(HashPoolSize: Integer);
begin
  inherited Create;
  FOwner_IO := nil;
  FAuthWaiting := False;
  FAuthed := False;
  FAuthSending := False;
  FFrameworkPool := TUInt32HashObjectList.CustomCreate(HashPoolSize);
  FFrameworkPool.AutoFreeData := False;
  FFrameworkPool.AccessOptimization := False;
  FFrameworkListenPool := TP2PVM_Listen_List.Create;
  FMaxVMFragmentSize := ZNet_Def_P2PVM_MaxVMFragmentSize;
  FProgress_Send_Size := ZNet_Def_P2PVM_Progress_Send_Size;
  FQuietMode := {$IFDEF Communication_QuietMode}True{$ELSE Communication_QuietMode}False{$ENDIF Communication_QuietMode};
  FReceiveStream := TMem64.CustomCreate(64 * 1024);
  FSendStream := TMem64.CustomCreate(64 * 1024);
  FWaitEchoList := TP2PVM_ECHO_List.Create;
  FVMID := 0;
  OnAuthSuccessOnesNotify := nil;
end;

destructor TZNet_P2PVM.Destroy;
var
  L: TCore_List;
  i: Integer;
  p: PUInt32HashListObjectStruct;
  OnEchoPtr: PP2PVM_ECHO;
begin
  // safe remove LinkVM
  L := TCore_List.Create;
  FFrameworkPool.GetListData(L);
  try
    for i := 0 to L.Count - 1 do
      begin
        p := L[i];
        if p^.data is TZNet_WithP2PVM_Server then
            TZNet_WithP2PVM_Server(p^.data).FLinkVMPool.Delete(FVMID)
        else if p^.data is TZNet_WithP2PVM_Client then
          begin
            TZNet_WithP2PVM_Client(p^.data).FLinkVM := nil;
            TZNet_WithP2PVM_Client(p^.data).Disconnect;
          end;
      end;
  except
  end;
  DisposeObject(L);
  FFrameworkPool.Clear;

  // remove echo data
  try
    for i := 0 to FWaitEchoList.Count - 1 do
      begin
        OnEchoPtr := FWaitEchoList[i];
        Dispose(OnEchoPtr);
      end;
  except
  end;
  FWaitEchoList.Clear;

  // close Owner-IO
  if FOwner_IO <> nil then
      CloseP2PVMTunnel;

  // clear listen
  ClearListen;

  // free
  DisposeObject(FWaitEchoList);
  DisposeObject(FReceiveStream);
  DisposeObject(FSendStream);
  DisposeObject(FFrameworkPool);
  DisposeObject(FFrameworkListenPool);
  inherited Destroy;
end;

function TZNet_P2PVM.Build_P2PVM_Packet(BuffSiz, FrameworkID, p2pID: Cardinal; pkType: Byte; buff: PByte): PP2PVMFragmentPacket;
var
  p: PP2PVMFragmentPacket;
begin
  New(p);
  p^.BuffSiz := BuffSiz;
  p^.FrameworkID := FrameworkID;
  p^.p2pID := p2pID;
  p^.pkType := pkType;
  if (buff <> nil) and (p^.BuffSiz > 0) then
    begin
      p^.buff := System.GetMemory(p^.BuffSiz);
      CopyPtr(buff, p^.buff, p^.BuffSiz);
      { encrypt p2pVM packet data }
      if p^.BuffSiz > 0 then
          FOwner_IO.FP2PVM_Cipher.Encrypt(p^.buff, p^.BuffSiz);
    end
  else
      p^.buff := nil;

  Result := p;
end;

class procedure TZNet_P2PVM.FreeP2PVMPacket(p: PP2PVMFragmentPacket);
begin
  if (p^.buff <> nil) and (p^.BuffSiz > 0) then
      System.FreeMemory(p^.buff);
  Dispose(p);
end;

procedure TZNet_P2PVM.Progress;
var
  i: Integer;
  p: PUInt32HashListObjectStruct;
  lsiz: Int64;
  OnEchoPtr: PP2PVM_ECHO;
begin
  if FOwner_IO = nil then
      exit;

  if FOwner_IO.Disable_Progress then
      exit;

  { echo and keepalive simulate }
  i := 0;
  while i < FWaitEchoList.Count do
    begin
      OnEchoPtr := FWaitEchoList[i];
      if OnEchoPtr^.TimeOut_ < GetTimeTick then
        begin
          FWaitEchoList.Delete(i);

          try
            if Assigned(OnEchoPtr^.OnEcho_C) then
                OnEchoPtr^.OnEcho_C(False)
            else if Assigned(OnEchoPtr^.OnEcho_M) then
                OnEchoPtr^.OnEcho_M(False)
            else if Assigned(OnEchoPtr^.OnEcho_P) then
                OnEchoPtr^.OnEcho_P(False);
          except
          end;

          try
              Dispose(OnEchoPtr);
          except
          end;
        end
      else
          inc(i);
    end;

  if (FOwner_IO = nil) or FOwner_IO.Disable_Progress or (not FOwner_IO.WriteBuffer_is_NULL) then
      exit;

  { real send buffer }
  try
    if FSendStream.Size > 0 then
      begin
        SendVMBuffer(FSendStream.Memory, FSendStream.Size);
        FSendStream.Clear;
      end;
  except
  end;

  if not FAuthed then
      exit;

  { fragment Packet }
  while True do
    begin
      repeat
        lsiz := FSendStream.Size;
        if (FFrameworkPool.Count > 0) then
          begin
            i := 0;
            p := FFrameworkPool.FirstPtr;
            while i < FFrameworkPool.Count do
              begin
                TZNet(p^.data).FastProgressPeerIOM(DoProcessPerClientFragmentSend);
                inc(i);
                p := p^.Next;
              end;
          end;
      until (FSendStream.Size = lsiz) or (FSendStream.Size >= lsiz + FProgress_Send_Size);

      if FSendStream.Size > 0 then
        begin
          SendVMBuffer(FSendStream.Memory, FSendStream.Size);
          FSendStream.Clear;
        end
      else
          Break;
    end;
end;

procedure TZNet_P2PVM.ProgressZNet_C(const OnBackcall: TZNet_List_C);
var
  i: Integer;
  p: PUInt32HashListObjectStruct;
begin
  if (FFrameworkPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      i := 0;
      p := FFrameworkPool.FirstPtr;
      while i < FFrameworkPool.Count do
        begin
          try
              OnBackcall(TZNet(p^.data));
          except
          end;
          inc(i);
          p := p^.Next;
        end;
    end;
end;

procedure TZNet_P2PVM.ProgressZNet_M(const OnBackcall: TZNet_List_M);
var
  i: Integer;
  p: PUInt32HashListObjectStruct;
begin
  if (FFrameworkPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      i := 0;
      p := FFrameworkPool.FirstPtr;
      while i < FFrameworkPool.Count do
        begin
          try
              OnBackcall(TZNet(p^.data));
          except
          end;
          inc(i);
          p := p^.Next;
        end;
    end;
end;

procedure TZNet_P2PVM.ProgressZNet_P(const OnBackcall: TZNet_List_P);
var
  i: Integer;
  p: PUInt32HashListObjectStruct;
begin
  if (FFrameworkPool.Count > 0) and (Assigned(OnBackcall)) then
    begin
      i := 0;
      p := FFrameworkPool.FirstPtr;
      while i < FFrameworkPool.Count do
        begin
          try
              OnBackcall(TZNet(p^.data));
          except
          end;
          inc(i);
          p := p^.Next;
        end;
    end;
end;

procedure TZNet_P2PVM.OpenP2PVMTunnel(c: TPeerIO);
begin
  FOwner_IO := c;
  FAuthWaiting := False;
  FAuthed := False;
  FAuthSending := False;
  FReceiveStream.Clear;
  FSendStream.Clear;

  { install tunnel driver }
  try
    FOwner_IO.On_Internal_Send_Byte_Buffer := Hook_SendByteBuffer;
    FOwner_IO.On_Internal_Save_Receive_Buffer := Hook_SaveReceiveBuffer;
    FOwner_IO.On_Internal_Process_Receive_Buffer := Hook_ProcessReceiveBuffer;
    FOwner_IO.OnDestroy := Hook_ClientDestroy;
  except
  end;

  if not FQuietMode then
      FOwner_IO.Print('Open VM P2P Tunnel ' + FOwner_IO.PeerIP);
end;

procedure TZNet_P2PVM.CloseP2PVMTunnel;
var
  i: Integer;
  OnEchoPtr: PP2PVM_ECHO;
  p: PUInt32HashListObjectStruct;
begin
  for i := 0 to FWaitEchoList.Count - 1 do
    begin
      OnEchoPtr := FWaitEchoList[i];
      Dispose(OnEchoPtr);
    end;
  FWaitEchoList.Clear;

  OnAuthSuccessOnesNotify := nil;

  if (FFrameworkPool.Count > 0) then
    begin
      i := 0;
      p := FFrameworkPool.FirstPtr;
      while i < FFrameworkPool.Count do
        begin
          if p^.data is TZNet_WithP2PVM_Server then
            begin
              TZNet_WithP2PVM_Server(p^.data).ProgressPeerIOM(DoPerClientClose);
              TZNet_WithP2PVM_Server(p^.data).FLinkVMPool.Delete(FVMID);
            end
          else if p^.data is TZNet_WithP2PVM_Client then
            begin
              TZNet_WithP2PVM_Client(p^.data).ProgressPeerIOM(DoPerClientClose);
              TZNet_WithP2PVM_Client(p^.data).FLinkVM := nil;
            end;
          inc(i);
          p := p^.Next;
        end;
    end;

  FAuthWaiting := False;
  FAuthed := False;
  FAuthSending := False;
  FReceiveStream.Clear;
  FSendStream.Clear;

  if FOwner_IO = nil then
      exit;

  try
    FOwner_IO.On_Internal_Send_Byte_Buffer := FOwner_IO.OwnerFramework.Framework_Internal_Send_Byte_Buffer;
    FOwner_IO.On_Internal_Save_Receive_Buffer := FOwner_IO.OwnerFramework.Framework_Internal_Save_Receive_Buffer;
    FOwner_IO.On_Internal_Process_Receive_Buffer := FOwner_IO.OwnerFramework.Framework_Internal_Process_Receive_Buffer;
    FOwner_IO.OnDestroy := FOwner_IO.OwnerFramework.Framework_Internal_IO_Destroy;
  except
  end;

  if not FQuietMode then
      FOwner_IO.Print('Close VM P2P Tunnel ' + FOwner_IO.PeerIP);

  FOwner_IO := nil;
end;

procedure TZNet_P2PVM.InstallLogicFramework(Inst: TZNet);
var
  i: Integer;
  LP: PP2PVMListen;
begin
  Owner_IO.DoP2PVM_InstallLogicFramework(Inst);

  if (Inst is TZNet_CustomStableServer) then
    begin
      InstallLogicFramework(TZNet_CustomStableServer(Inst).OwnerIOServer);
      exit;
    end;
  if (Inst is TZNet_CustomStableClient) then
    begin
      InstallLogicFramework(TZNet_CustomStableClient(Inst).OwnerIOClient);
      exit;
    end;

  if Inst is TZNet_WithP2PVM_Server then
    begin
      if TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID <> 0 then
        begin
          if FFrameworkPool.Exists(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID) then
              exit;
        end
      else
        begin
          if FFrameworkPool.Count > 0 then
              TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID := FFrameworkPool.LastPtr^.u32
          else
              TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID := 1;
          while FFrameworkPool.Exists(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID) do
              inc(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID);
        end;

      TZNet_WithP2PVM_Server(Inst).FLinkVMPool.Add(FVMID, self, True);
      FFrameworkPool.Add(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID, Inst, True);
      for i := 0 to TZNet_WithP2PVM_Server(Inst).ListenCount - 1 do
        begin
          LP := TZNet_WithP2PVM_Server(Inst).GetListen(i);
          SendListen(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID, LP^.ListenHost, LP^.ListenPort, LP^.Listening);
        end;
    end
  else if Inst is TZNet_WithP2PVM_Client then
    begin
      if TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID <> 0 then
        begin
          if FFrameworkPool.Exists(TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID) then
              exit;
        end
      else
        begin
          if FFrameworkPool.Count > 0 then
              TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID := FFrameworkPool.LastPtr^.u32
          else
              TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID := 1;
          while FFrameworkPool.Exists(TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID) do
              inc(TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID);
        end;

      TZNet_WithP2PVM_Client(Inst).FLinkVM := self;
      FFrameworkPool.Add(TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID, Inst, True);
    end
  else
      RaiseInfo('illegal p2pVM.');
end;

procedure TZNet_P2PVM.UninstallLogicFramework(Inst: TZNet);
var
  i: Integer;
  LP: PP2PVMListen;
begin
  Owner_IO.DoP2PVM_UninstallLogicFramework(Inst);

  if (Inst is TZNet_CustomStableServer) then
    begin
      UninstallLogicFramework(TZNet_CustomStableServer(Inst).OwnerIOServer);
      exit;
    end;
  if (Inst is TZNet_CustomStableClient) then
    begin
      UninstallLogicFramework(TZNet_CustomStableClient(Inst).OwnerIOClient);
      exit;
    end;

  if Inst is TZNet_WithP2PVM_Server then
    begin
      TZNet_WithP2PVM_Server(Inst).FLinkVMPool.Delete(FVMID);
      FFrameworkPool.Delete(TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID);

      i := 0;
      while i < FFrameworkListenPool.Count do
        begin
          LP := FFrameworkListenPool[i];
          if LP^.FrameworkID = TZNet_WithP2PVM_Server(Inst).FFrameworkWithVM_ID then
            begin
              Dispose(LP);
              FFrameworkListenPool.Delete(i);
            end
          else
              inc(i);
        end;
    end
  else if Inst is TZNet_WithP2PVM_Client then
    begin
      TZNet_WithP2PVM_Client(Inst).Disconnect;
      TZNet_WithP2PVM_Client(Inst).FLinkVM := nil;
      FFrameworkPool.Delete(TZNet_WithP2PVM_Client(Inst).FFrameworkWithVM_ID);
    end
  else
      RaiseInfo('illegal p2pVM.');
end;

procedure TZNet_P2PVM.AuthWaiting;
begin
  if FOwner_IO = nil then
      exit;
  FAuthWaiting := True;
end;

procedure TZNet_P2PVM.AuthVM;
begin
  if FOwner_IO = nil then
      exit;
  if not FAuthed then
    if not FAuthSending then
      begin
        FSendStream.WritePtr(@FOwner_IO.FP2PVM_Auth_Token[0], Length(FOwner_IO.FP2PVM_Auth_Token));
        FAuthSending := True;
        FAuthWaiting := True;
      end;
end;

procedure TZNet_P2PVM.AuthSuccessed;
var
  p: PP2PVMFragmentPacket;
begin
  p := Build_P2PVM_Packet(0, 0, 0, ZNet_Def_p2pVM_AuthSuccessed, nil);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

procedure TZNet_P2PVM.echoing(const OnEchoPtr: PP2PVM_ECHO; TimeOut_: TTimeTick);
var
  u64ptr: UInt64;
  p: PP2PVMFragmentPacket;
  i: Integer;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
    begin
      if OnEchoPtr <> nil then
        begin
          i := 0;
          while i < FWaitEchoList.Count do
            begin
              if FWaitEchoList[i] = OnEchoPtr then
                  FWaitEchoList.Delete(i)
              else
                  inc(i);
            end;

          try
            if Assigned(OnEchoPtr^.OnEcho_C) then
                OnEchoPtr^.OnEcho_C(False)
            else if Assigned(OnEchoPtr^.OnEcho_M) then
                OnEchoPtr^.OnEcho_M(False)
            else if Assigned(OnEchoPtr^.OnEcho_P) then
                OnEchoPtr^.OnEcho_P(False);
          except
          end;

          Dispose(OnEchoPtr);
        end;
      exit;
    end;

  u64ptr := UInt64(OnEchoPtr);
  p := Build_P2PVM_Packet(8, 0, 0, ZNet_Def_p2pVM_echoing, @u64ptr);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);

  FWaitEchoList.Add(OnEchoPtr);
end;

procedure TZNet_P2PVM.echoingC(const OnResult: TOnState_C; TimeOut_: TTimeTick);
var
  p: PP2PVM_ECHO;
begin
  New(p);
  p^.OnEcho_C := OnResult;
  p^.OnEcho_M := nil;
  p^.OnEcho_P := nil;
  p^.TimeOut_ := GetTimeTick + TimeOut_;
  echoing(p, TimeOut_);
end;

procedure TZNet_P2PVM.echoingM(const OnResult: TOnState_M; TimeOut_: TTimeTick);
var
  p: PP2PVM_ECHO;
begin
  New(p);
  p^.OnEcho_C := nil;
  p^.OnEcho_M := OnResult;
  p^.OnEcho_P := nil;
  p^.TimeOut_ := GetTimeTick + TimeOut_;
  echoing(p, TimeOut_);
end;

procedure TZNet_P2PVM.echoingP(const OnResult: TOnState_P; TimeOut_: TTimeTick);
var
  p: PP2PVM_ECHO;
begin
  New(p);
  p^.OnEcho_C := nil;
  p^.OnEcho_M := nil;
  p^.OnEcho_P := OnResult;
  p^.TimeOut_ := GetTimeTick + TimeOut_;
  echoing(p, TimeOut_);
end;

procedure TZNet_P2PVM.echoBuffer(const buff: Pointer; const siz: NativeInt);
var
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
      exit;
  p := Build_P2PVM_Packet(siz, 0, 0, ZNet_Def_p2pVM_echo, buff);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

procedure TZNet_P2PVM.SendListen(const FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; const Listening: Boolean);
var
  LP: PP2PVMListen;
  c: TZNet;
  RBuf: array [0 .. 18] of Byte;
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
    begin
      LP := FindListen(IPV6, Port);
      if Listening then
        begin
          if LP = nil then
            begin
              New(LP);
              LP^.FrameworkID := FrameworkID;
              LP^.ListenHost := IPV6;
              LP^.ListenPort := Port;
              LP^.Listening := True;
              FFrameworkListenPool.Add(LP);
            end
          else
              LP^.Listening := True;
        end
      else
          DeleteListen(IPV6, Port);

      c := TZNet(FFrameworkPool[FrameworkID]);
      if c is TZNet_WithP2PVM_Server then
        begin
          TZNet_WithP2PVM_Server(c).ListenState(self, IPV6, Port, Listening);
          SendListenState(TZNet_WithP2PVM_Server(c).FFrameworkWithVM_ID, IPV6, Port, Listening);
        end;
    end
  else
    begin
      PIPV6(@RBuf[0])^ := IPV6;
      PWORD(@RBuf[16])^ := Port;
      PBoolean(@RBuf[18])^ := Listening;
      p := Build_P2PVM_Packet(SizeOf(RBuf), FrameworkID, 0, ZNet_Def_p2pVM_Listen, @RBuf[0]);

      FSendStream.Position := FSendStream.Size;
      p^.Build_P2PVM_Send_Buffer(FSendStream);
      FreeP2PVMPacket(p);
    end;
end;

procedure TZNet_P2PVM.SendListenState(const FrameworkID: Cardinal; const IPV6: TIPV6; const Port: Word; const Listening: Boolean);
var
  RBuf: array [0 .. 18] of Byte;
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
      exit;
  PIPV6(@RBuf[0])^ := IPV6;
  PWORD(@RBuf[16])^ := Port;
  PBoolean(@RBuf[18])^ := Listening;
  p := Build_P2PVM_Packet(SizeOf(RBuf), FrameworkID, 0, ZNet_Def_p2pVM_ListenState, @RBuf[0]);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

procedure TZNet_P2PVM.SendConnecting(const Remote_frameworkID, FrameworkID, p2pID: Cardinal; const IPV6: TIPV6; const Port: Word);
var
  RBuf: array [0 .. 25] of Byte;
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
      exit;
  PCardinal(@RBuf[0])^ := FrameworkID;
  PCardinal(@RBuf[4])^ := p2pID;
  PIPV6(@RBuf[8])^ := IPV6;
  PWORD(@RBuf[24])^ := Port;

  p := Build_P2PVM_Packet(SizeOf(RBuf), Remote_frameworkID, 0, ZNet_Def_p2pVM_Connecting, @RBuf[0]);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

procedure TZNet_P2PVM.SendConnectedReponse(const Remote_frameworkID, Remote_p2pID, FrameworkID, p2pID: Cardinal);
var
  RBuf: array [0 .. 7] of Byte;
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
      exit;
  PCardinal(@RBuf[0])^ := FrameworkID;
  PCardinal(@RBuf[4])^ := p2pID;

  p := Build_P2PVM_Packet(SizeOf(RBuf), Remote_frameworkID, Remote_p2pID, ZNet_Def_p2pVM_ConnectedReponse, @RBuf[0]);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

procedure TZNet_P2PVM.SendDisconnect(const Remote_frameworkID, Remote_p2pID: Cardinal);
var
  p: PP2PVMFragmentPacket;
begin
  if (FOwner_IO = nil) or (not WasAuthed) then
      exit;
  p := Build_P2PVM_Packet(0, Remote_frameworkID, Remote_p2pID, ZNet_Def_p2pVM_Disconnect, nil);

  FSendStream.Position := FSendStream.Size;
  p^.Build_P2PVM_Send_Buffer(FSendStream);
  FreeP2PVMPacket(p);
end;

function TZNet_P2PVM.ListenCount: Integer;
begin
  Result := FFrameworkListenPool.Count;
end;

function TZNet_P2PVM.GetListen(const index: Integer): PP2PVMListen;
begin
  Result := FFrameworkListenPool[index];
end;

function TZNet_P2PVM.FindListen(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
var
  i: Integer;
  p: PP2PVMListen;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
    begin
      p := FFrameworkListenPool[i];
      if (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Result := p;
          exit;
        end;
    end;
  Result := nil;
end;

function TZNet_P2PVM.FindListening(const IPV6: TIPV6; const Port: Word): PP2PVMListen;
var
  i: Integer;
  p: PP2PVMListen;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
    begin
      p := FFrameworkListenPool[i];
      if (p^.Listening) and (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Result := p;
          exit;
        end;
    end;
  Result := nil;
end;

procedure TZNet_P2PVM.DeleteListen(const IPV6: TIPV6; const Port: Word);
var
  i: Integer;
  p: PP2PVMListen;
begin
  i := 0;
  while i < FFrameworkListenPool.Count do
    begin
      p := FFrameworkListenPool[i];
      if (p^.ListenPort = Port) and (CompareIPV6(p^.ListenHost, IPV6)) then
        begin
          Dispose(p);
          FFrameworkListenPool.Delete(i);
        end
      else
          inc(i);
    end;
end;

procedure TZNet_P2PVM.ClearListen;
var
  i: Integer;
begin
  for i := 0 to FFrameworkListenPool.Count - 1 do
      Dispose(PP2PVMListen(FFrameworkListenPool[i]));
  FFrameworkListenPool.Clear;
end;

constructor TStableServer_OwnerIO_UserDefine.Create(Owner_: TPeerIO);
begin
  inherited Create(Owner_);
  BindStableIO := nil;
end;

destructor TStableServer_OwnerIO_UserDefine.Destroy;
begin
  if BindStableIO <> nil then
    begin
      BindStableIO.BindOwnerIO := nil;
      if not BindStableIO.Activted then
          BindStableIO.DelayClose(2.0);
      BindStableIO := nil;
    end;
  inherited Destroy;
end;

procedure TStableServer_PeerIO.CreateAfter;
begin
  inherited CreateAfter;
  Activted := False;
  DestroyRecycleOwnerIO := True;
  Connection_Token := 0;
  Internal_Bind_Owner_IO := nil;
  OfflineTick := GetTimeTick;
end;

destructor TStableServer_PeerIO.Destroy;
begin
  if (DestroyRecycleOwnerIO) and (BindOwnerIO <> nil) then
    begin
      TStableServer_OwnerIO_UserDefine(BindOwnerIO.UserDefine).BindStableIO := nil;
      BindOwnerIO.DelayClose;
      BindOwnerIO := nil;
    end;

  inherited Destroy;
end;

function TStableServer_PeerIO.Connected: Boolean;
begin
  Result := True;
end;

procedure TStableServer_PeerIO.Disconnect;
begin
  DelayFree();
end;

procedure TStableServer_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: NativeInt);
begin
  if BindOwnerIO = nil then
      AtomDec(OwnerFramework.Statistics[TStatisticsType.stSendSize], Size)
  else
      BindOwnerIO.Write_IO_Buffer(buff, Size);
end;

procedure TStableServer_PeerIO.WriteBufferOpen;
begin
  if BindOwnerIO <> nil then
      BindOwnerIO.WriteBufferOpen;
end;

procedure TStableServer_PeerIO.WriteBufferFlush;
begin
  if BindOwnerIO <> nil then
      BindOwnerIO.WriteBufferFlush;
end;

procedure TStableServer_PeerIO.WriteBufferClose;
begin
  if BindOwnerIO <> nil then
      BindOwnerIO.WriteBufferClose;
end;

function TStableServer_PeerIO.GetPeerIP: SystemString;
begin
  if BindOwnerIO <> nil then
      Result := BindOwnerIO.GetPeerIP
  else
      Result := 'StableIO - offline';
end;

function TStableServer_PeerIO.WriteBuffer_is_NULL: Boolean;
begin
  if (BindOwnerIO <> nil) and (not BindOwnerIO.Disable_Progress) then
      Result := BindOwnerIO.WriteBuffer_is_NULL
  else
      Result := False;
end;

function TStableServer_PeerIO.WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean;
begin
  if (BindOwnerIO <> nil) and (not BindOwnerIO.Disable_Progress) then
      Result := BindOwnerIO.WriteBuffer_State(WriteBuffer_Queue_Num, WriteBuffer_Size)
  else
      Result := inherited WriteBuffer_State(WriteBuffer_Queue_Num, WriteBuffer_Size);
end;

procedure TStableServer_PeerIO.Progress;
var
  t, offline_t: TTimeTick;
begin
  if (Activted) then
    begin
      t := GetTimeTick;

      if (BindOwnerIO = nil) then
        begin
          offline_t := TZNet_CustomStableServer(OwnerFramework).OfflineTimeout;
          if (offline_t > 0) and (t - OfflineTick > offline_t) then
            begin
              DelayClose;
              exit;
            end;
        end
      else
          OfflineTick := t;
    end;

  inherited Progress;
  Process_Send_Buffer();
end;

procedure TZNet_CustomStableServer.ServerCustomProtocolReceiveBufferNotify(Sender: TPeerIO; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
var
  io_def: TStableServer_OwnerIO_UserDefine;
begin
  io_def := Sender.UserDefine as TStableServer_OwnerIO_UserDefine;
  FillDone := (io_def.BindStableIO <> nil);
  if FillDone then
    begin
      io_def.BindStableIO.Write_Physics_Fragment(Buffer, Size);
    end;
end;

procedure TZNet_CustomStableServer.SetOwnerIOServer(const Value: TZNet_Server);
begin
  if FOwnerIOServer <> nil then
    begin
      FOwnerIOServer.FOnServerCustomProtocolReceiveBufferNotify := nil;
      FOwnerIOServer.Protocol := TCommunicationProtocol.cpZServer;
      FOwnerIOServer.UserDefineClass := TPeer_IO_User_Define;
      FOwnerIOServer.QuietMode := False;

      UnRegisted(C_BuildStableIO);
      UnRegisted(C_OpenStableIO);
    end;

  FOwnerIOServer := Value;

  if FOwnerIOServer <> nil then
    begin
      FOwnerIOServer.FOnServerCustomProtocolReceiveBufferNotify := ServerCustomProtocolReceiveBufferNotify;
      FOwnerIOServer.Protocol := TCommunicationProtocol.cpCustom;
      FOwnerIOServer.UserDefineClass := TStableServer_OwnerIO_UserDefine;
      FOwnerIOServer.SyncOnResult := True;
      FOwnerIOServer.SyncOnCompleteBuffer := True;
      FOwnerIOServer.QuietMode := False;
      FOwnerIOServer.TimeOutIDLE := 60 * 1000;

      FOwnerIOServer.RegisterStream(C_BuildStableIO).OnExecute := cmd_BuildStableIO;
      FOwnerIOServer.RegisterStream(C_OpenStableIO).OnExecute := cmd_OpenStableIO;
    end;
end;

procedure TZNet_CustomStableServer.cmd_BuildStableIO(Sender: TPeerIO; InData, OutData: TDFE);
var
  io_def: TStableServer_OwnerIO_UserDefine;
  S_IO: TStableServer_PeerIO;
begin
  io_def := Sender.UserDefine as TStableServer_OwnerIO_UserDefine;
  S_IO := TStableServer_PeerIO.Create(self, nil);
  S_IO.Activted := True;
  S_IO.FSequencePacketActivted := True;
  S_IO.FSequencePacketSignal := True;
  S_IO.SequencePacketLimitOwnerIOMemory := FLimitSequencePacketMemoryUsage;
  S_IO.DestroyRecycleOwnerIO := True;
  S_IO.BindOwnerIO := Sender;
  S_IO.Connection_Token := Connection_Token_Counter;
  inc(Connection_Token_Counter);
  io_def.BindStableIO := S_IO;

  OutData.WriteBool(True);
  OutData.WriteCardinal(S_IO.Connection_Token);
  OutData.WriteCardinal(S_IO.FID);
  OutData.WriteByte(Byte(S_IO.FSendDataCipherSecurity));
  OutData.WriteArrayByte.SetBuff(@S_IO.FCipherKey[0], Length(S_IO.FCipherKey));
end;

procedure TZNet_CustomStableServer.cmd_OpenStableIO(Sender: TPeerIO; InData, OutData: TDFE);
var
  io_def: TStableServer_OwnerIO_UserDefine;
  connToken: Cardinal;
  arry: TDF_ArrayByte;
  connKey: TBytes;
  IO_Array: TIO_Array;
  IO_ID: Cardinal;
  io_temp, io_picked: TStableServer_PeerIO;
begin
  io_def := Sender.UserDefine as TStableServer_OwnerIO_UserDefine;

  io_picked := nil;
  connToken := InData.Reader.ReadCardinal;
  arry := InData.Reader.ReadArrayByte;
  SetLength(connKey, arry.Count);
  arry.GetBuff(@connKey[0]);

  GetIO_Array(IO_Array);
  for IO_ID in IO_Array do
    begin
      io_temp := TStableServer_PeerIO(PeerIO[IO_ID]);
      if (io_temp <> nil) and (io_temp.Activted) and
        (io_temp.Connection_Token = connToken) and (TCipher.CompareKey(connKey, io_temp.FCipherKey)) then
        begin
          io_picked := io_temp;
          Break;
        end;
    end;

  if io_picked = nil then
    begin
      OutData.WriteBool(False);
      OutData.WriteString(PFormat('illegal Request Token: maybe you cant use StableIO again after server is restarted.', []));
      exit;
    end;

  io_picked.BindOwnerIO := Sender;
  io_picked.Activted := True;
  io_picked.DestroyRecycleOwnerIO := True;
  io_picked.UserDefine.WorkPlatform := io_def.WorkPlatform;
  io_def.BindStableIO := io_picked;
  io_picked.ResetSequencePacketBuffer;
  io_picked.SequencePacketVerifyTick := GetTimeTick;
  io_picked.OfflineTick := GetTimeTick;

  OutData.WriteBool(True);
  OutData.WriteCardinal(io_picked.Connection_Token);
  OutData.WriteCardinal(io_picked.ID);
  OutData.WriteByte(Byte(io_picked.FSendDataCipherSecurity));
  OutData.WriteArrayByte.SetBuff(@io_picked.FCipherKey[0], Length(io_picked.FCipherKey));
end;

procedure TZNet_CustomStableServer.cmd_CloseStableIO(Sender: TPeerIO; InData: SystemString);
var
  S_IO: TStableServer_PeerIO;
begin
  S_IO := Sender as TStableServer_PeerIO;
  S_IO.Disconnect;
end;

constructor TZNet_CustomStableServer.Create;
begin
  inherited Create;
  EnabledAtomicLockAndMultiThread := False;
  PhysicsFragmentSwapSpaceTechnology := False;
  SwitchMaxSecurity;

  RegisterConsoleNotify(C_CloseStableIO).OnExecute := cmd_CloseStableIO;

  Connection_Token_Counter := 1;
  FOwnerIOServer := nil;
  FOfflineTimeout := 1000 * 60 * 5;
  FLimitSequencePacketMemoryUsage := 0;
  FAutoFreeOwnerIOServer := False;
  FAutoProgressOwnerIOServer := True;
  CustomStableServerProgressing := False;

  name := 'StableServer';
end;

destructor TZNet_CustomStableServer.Destroy;
var
  phyServ: TZNet_Server;
begin
  UnRegisted(C_CloseStableIO);

  while Count > 0 do
      DisposeObject(FirstIO);

  StopService;
  phyServ := FOwnerIOServer;
  SetOwnerIOServer(nil);
  if FAutoFreeOwnerIOServer and (phyServ <> nil) then
      DisposeObject(phyServ);
  inherited Destroy;
end;

function TZNet_CustomStableServer.StartService(Host: SystemString; Port: Word): Boolean;
begin
  Result := False;
  if FOwnerIOServer <> nil then
      Result := FOwnerIOServer.StartService(Host, Port);
end;

procedure TZNet_CustomStableServer.StopService;
begin
  if FOwnerIOServer <> nil then
      FOwnerIOServer.StopService;
end;

procedure TZNet_CustomStableServer.Progress;
begin
  if not FProgressEnabled then
      exit;
  if CustomStableServerProgressing then
      exit;

  CustomStableServerProgressing := True;
  if (FOwnerIOServer <> nil) and (FAutoProgressOwnerIOServer) then
      FOwnerIOServer.Progress;
  inherited Progress;
  CustomStableServerProgressing := False;
end;

function TZNet_CustomStableServer.WaitSendConsoleCmd(P_IO: TPeerIO;
  const Cmd, ConsoleData: SystemString; TimeOut_: TTimeTick): SystemString;
begin
  Result := '';
  RaiseInfo('WaitSend no Suppport');
end;

procedure TZNet_CustomStableServer.WaitSendStreamCmd(P_IO: TPeerIO;
  const Cmd: SystemString; StreamData, Result_: TDFE; TimeOut_: TTimeTick);
begin
  RaiseInfo('WaitSend no Suppport');
end;

procedure TStableClient_PeerIO.CreateAfter;
begin
  inherited CreateAfter;
  Activted := False;
  WaitConnecting := False;
  OwnerIO_LastConnectTick := GetTimeTick;
  Connection_Token := 0;
  BindOwnerIO := nil;
end;

destructor TStableClient_PeerIO.Destroy;
begin
  TZNet_CustomStableClient(OwnerFramework).DoDisconnect(self);

  if (BindOwnerIO <> nil) then
      BindOwnerIO.DelayClose;

  inherited Destroy;
end;

function TStableClient_PeerIO.Connected: Boolean;
begin
  Result := True;
end;

procedure TStableClient_PeerIO.Disconnect;
begin
  if (BindOwnerIO <> nil) then
      BindOwnerIO.Disconnect;

  TZNet_CustomStableClient(OwnerFramework).Disconnect;
end;

procedure TStableClient_PeerIO.Write_IO_Buffer(const buff: PByte; const Size: NativeInt);
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) then
    begin
      AtomDec(OwnerFramework.Statistics[TStatisticsType.stSendSize], Size);
      exit;
    end;

  BindOwnerIO.Write_IO_Buffer(buff, Size);
end;

procedure TStableClient_PeerIO.WriteBufferOpen;
begin
  if BindOwnerIO <> nil then
      BindOwnerIO.WriteBufferOpen;
end;

procedure TStableClient_PeerIO.WriteBufferFlush;
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) then
      exit;
  BindOwnerIO.WriteBufferFlush;
end;

procedure TStableClient_PeerIO.WriteBufferClose;
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) then
      exit;
  BindOwnerIO.WriteBufferClose;
end;

function TStableClient_PeerIO.GetPeerIP: SystemString;
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) then
      Result := 'offline'
  else
      Result := BindOwnerIO.GetPeerIP;
end;

function TStableClient_PeerIO.WriteBuffer_is_NULL: Boolean;
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) or (BindOwnerIO.Disable_Progress) then
      Result := False
  else
      Result := BindOwnerIO.WriteBuffer_is_NULL;
end;

function TStableClient_PeerIO.WriteBuffer_State(var WriteBuffer_Queue_Num, WriteBuffer_Size: Int64): Boolean;
begin
  if (BindOwnerIO = nil) or (not Activted) or (WaitConnecting) or (BindOwnerIO.Disable_Progress) then
      Result := inherited WriteBuffer_State(WriteBuffer_Queue_Num, WriteBuffer_Size)
  else
      Result := BindOwnerIO.WriteBuffer_State(WriteBuffer_Queue_Num, WriteBuffer_Size);
end;

procedure TStableClient_PeerIO.Progress;
begin
  Process_Send_Buffer();
  inherited Progress;
end;

procedure TZNet_CustomStableClient.ClientCustomProtocolReceiveBufferNotify(Sender: TZNet_Client; const Buffer: PByte; const Size: NativeInt; var FillDone: Boolean);
begin
  KeepAliveChecking := False;

  FillDone := FStableClientIO.Activted and (not FStableClientIO.WaitConnecting) and (FStableClientIO.BindOwnerIO <> nil);
  if FillDone then
    begin
      FStableClientIO.Write_Physics_Fragment(Buffer, Size);
    end;
end;

procedure TZNet_CustomStableClient.SetOwnerIOClient(const Value: TZNet_Client);
begin
  if FOwnerIOClient <> nil then
    begin
      Disconnect;
      FOwnerIOClient.FOnClientCustomProtocolReceiveBufferNotify := nil;
      FOwnerIOClient.Protocol := TCommunicationProtocol.cpZServer;
      FOwnerIOClient.TimeOutIDLE := 0;
      FOwnerIOClient.QuietMode := False;
    end;

  FOwnerIOClient := Value;

  if FOwnerIOClient <> nil then
    begin
      FOwnerIOClient.FOnClientCustomProtocolReceiveBufferNotify := ClientCustomProtocolReceiveBufferNotify;
      FOwnerIOClient.Protocol := TCommunicationProtocol.cpCustom;
      FOwnerIOClient.TimeOutIDLE := 0;
      FOwnerIOClient.QuietMode := False;
    end;
end;

procedure TZNet_CustomStableClient.BuildStableIO_Result(Sender: TPeerIO; Result_: TDFE);
var
  r_token, R_ID: Cardinal;
  cSec: TCipherSecurity;
  arry: TDF_ArrayByte;
  i: Integer;
  k: TCipherKeyBuffer;
begin
  if Result_.Reader.ReadBool then
    begin
      r_token := Result_.Reader.ReadCardinal;
      R_ID := Result_.Reader.ReadCardinal;
      cSec := TCipherSecurity(Result_.Reader.ReadByte);
      arry := Result_.Reader.ReadArrayByte;
      SetLength(k, arry.Count);
      for i := 0 to arry.Count - 1 do
          k[i] := arry[i];

      { connection token }
      FStableClientIO.Connection_Token := r_token;
      { bind physics IO }
      FStableClientIO.BindOwnerIO := Sender;
      { remote id }
      FStableClientIO.ID := R_ID;
      { Encrypt }
      FStableClientIO.FSendDataCipherSecurity := cSec;
      FStableClientIO.FCipherKey := TCipher.CopyKey(k);
      { switch state }
      FStableClientIO.Activted := True;
      FStableClientIO.WaitConnecting := False;
      { replace encrypt for physics IO }
      Sender.FSendDataCipherSecurity := cSec;
      Sender.FCipherKey := TCipher.CopyKey(k);
      { open sequence packet model }
      FStableClientIO.FSequencePacketActivted := True;
      FStableClientIO.FSequencePacketSignal := True;
      FStableClientIO.SequencePacketLimitOwnerIOMemory := FLimitSequencePacketMemoryUsage;

      { triger }
      TriggerDoConnectFinished;
      DoConnected(FStableClientIO);
      FStableClientIO.LastCommunicationTick_Received := GetTimeTick;
      FStableClientIO.LastCommunicationTick_KeepAlive := FStableClientIO.LastCommunicationTick_Received;

      if not FOwnerIOClient.QuietMode then
          FOwnerIOClient.ClientIO.Print('StableIO connection %s port:%d Success.', [FConnection_Addr, FConnection_Port]);
    end
  else
    begin
      Sender.PrintError(Result_.Reader.ReadString);
      TriggerDoConnectFailed;
    end;
end;

procedure TZNet_CustomStableClient.AsyncConnectResult(const cState: Boolean);
var
  d: TDFE;
begin
  if cState then
    begin
      d := TDFE.Create;
      FOwnerIOClient.SendStreamCmdM(C_BuildStableIO, d, BuildStableIO_Result);
      DisposeObject(d);
    end
  else
    begin
      FStableClientIO.WaitConnecting := False;

      if FAutomatedConnection then
          PostProgress.PostExecuteM(1.0, PostConnection)
      else
          TriggerDoConnectFailed;
    end;
end;

procedure TZNet_CustomStableClient.PostConnection(Sender: TN_Post_Execute);
begin
  if FStableClientIO.WaitConnecting then
      exit;

  FStableClientIO.WaitConnecting := True;
  FOwnerIOClient.AsyncConnectM(FConnection_Addr, FConnection_Port, AsyncConnectResult);
end;

procedure TZNet_CustomStableClient.OpenStableIO_Result(Sender: TPeerIO; Result_: TDFE);
var
  r_token, R_ID: Cardinal;
  cSec: TCipherSecurity;
  arry: TDF_ArrayByte;
  k: TCipherKeyBuffer;
begin
  if Result_.Reader.ReadBool then
    begin
      r_token := Result_.Reader.ReadCardinal;
      R_ID := Result_.Reader.ReadCardinal;
      cSec := TCipherSecurity(Result_.Reader.ReadByte);
      arry := Result_.Reader.ReadArrayByte;
      SetLength(k, arry.Count);
      arry.GetBuff(@k[0]);

      { connection token }
      FStableClientIO.Connection_Token := r_token;
      { bind physics IO }
      FStableClientIO.BindOwnerIO := Sender;
      { remote id }
      FStableClientIO.ID := R_ID;
      { Encrypt }
      FStableClientIO.FSendDataCipherSecurity := cSec;
      FStableClientIO.FCipherKey := TCipher.CopyKey(k);
      { remote inited }
      FStableClientIO.RemoteExecutedForConnectInit := True;
      { switch state }
      FStableClientIO.Activted := True;
      FStableClientIO.WaitConnecting := False;
      { replace encrypt for physics IO }
      Sender.FSendDataCipherSecurity := cSec;
      Sender.FCipherKey := TCipher.CopyKey(k);
      { sequence packet model }
      FStableClientIO.FSequencePacketActivted := True;
      FStableClientIO.FSequencePacketSignal := True;
      FStableClientIO.SequencePacketLimitOwnerIOMemory := FLimitSequencePacketMemoryUsage;
      FStableClientIO.ResetSequencePacketBuffer;
      FStableClientIO.SequencePacketVerifyTick := GetTimeTick;
      if not FStableClientIO.OwnerFramework.QuietMode then
          FStableClientIO.Print('StableIO calibrate session.', []);
    end
  else
    begin
      Sender.PrintError(Result_.Reader.ReadString);

      FStableClientIO.WaitConnecting := False;

      FStableClientIO.Activted := False;
      FStableClientIO.BindOwnerIO := nil;

      FOnAsyncConnectNotify_C := nil;
      FOnAsyncConnectNotify_M := nil;
      FOnAsyncConnectNotify_P := nil;
      FStableClientIO.DelayClose();

      if AutomatedConnection then
          PostProgress.PostExecuteM(1.0, PostConnection);
    end;
end;

procedure TZNet_CustomStableClient.AsyncReconnectionResult(const cState: Boolean);
var
  d: TDFE;
begin
  if not FStableClientIO.WaitConnecting then
      exit;

  if cState then
    begin
      d := TDFE.Create;
      d.WriteCardinal(FStableClientIO.Connection_Token);
      d.WriteArrayByte.SetBuff(@FStableClientIO.FCipherKey[0], Length(FStableClientIO.FCipherKey));
      FOwnerIOClient.SendStreamCmdM(C_OpenStableIO, d, OpenStableIO_Result);
      DisposeObject(d);
    end
  else
    begin
      FStableClientIO.WaitConnecting := False;
    end;
end;

procedure TZNet_CustomStableClient.PostReconnection(Sender: TN_Post_Execute);
begin
  if not FStableClientIO.Activted then
      exit;
  if FOwnerIOClient = nil then
      exit;
  if not FStableClientIO.WaitConnecting then
      exit;

  FOwnerIOClient.AsyncConnectM(FConnection_Addr, FConnection_Port, AsyncReconnectionResult);
end;

procedure TZNet_CustomStableClient.Reconnection;
begin
  if not FStableClientIO.Activted then
      exit;
  if FOwnerIOClient = nil then
      exit;
  if FStableClientIO.WaitConnecting then
      exit;

  FStableClientIO.WaitConnecting := True;
  FStableClientIO.OwnerIO_LastConnectTick := GetTimeTick;
  FStableClientIO.BindOwnerIO := nil;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
  PostProgress.PostExecuteM(1.0, PostReconnection);
end;

function TZNet_CustomStableClient.GetStopCommunicationTimeTick: TTimeTick;
begin
  if KeepAliveChecking then
      Result := GetTimeTick - SaveLastCommunicationTick_Received
  else
      Result := GetTimeTick - FStableClientIO.LastCommunicationTick_Received;
end;

constructor TZNet_CustomStableClient.Create;
begin
  inherited Create;
  EnabledAtomicLockAndMultiThread := False;
  PhysicsFragmentSwapSpaceTechnology := False;
  FIgnoreProcessConnectedAndDisconnect := True;

  FOwnerIOClient := nil;
  FStableClientIO := TStableClient_PeerIO.Create(self, nil);

  FConnection_Addr := '';
  FConnection_Port := 0;
  FAutomatedConnection := True;
  FLimitSequencePacketMemoryUsage := 0;
  FAutoFreeOwnerIOClient := False;
  FAutoProgressOwnerIOClient := True;
  CustomStableClientProgressing := False;
  KeepAliveChecking := False;
  SaveLastCommunicationTick_Received := FStableClientIO.LastCommunicationTick_Received;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
  name := 'StableClient';
end;

destructor TZNet_CustomStableClient.Destroy;
var
  phyCli: TZNet_Client;
begin
  Disconnect;

  phyCli := FOwnerIOClient;
  SetOwnerIOClient(nil);
  if (phyCli <> nil) and (FAutoFreeOwnerIOClient) then
      DisposeObject(phyCli);
  inherited Destroy;
end;

procedure TZNet_CustomStableClient.TriggerDoConnectFailed;
begin
  inherited TriggerDoConnectFailed;

  try
    if Assigned(FOnAsyncConnectNotify_C) then
        FOnAsyncConnectNotify_C(False)
    else if Assigned(FOnAsyncConnectNotify_M) then
        FOnAsyncConnectNotify_M(False)
    else if Assigned(FOnAsyncConnectNotify_P) then
        FOnAsyncConnectNotify_P(False);
  except
  end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
end;

procedure TZNet_CustomStableClient.TriggerDoConnectFinished;
begin
  inherited TriggerDoConnectFinished;

  try
    if Assigned(FOnAsyncConnectNotify_C) then
        FOnAsyncConnectNotify_C(True)
    else if Assigned(FOnAsyncConnectNotify_M) then
        FOnAsyncConnectNotify_M(True)
    else if Assigned(FOnAsyncConnectNotify_P) then
        FOnAsyncConnectNotify_P(True);
  except
  end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
end;

procedure TZNet_CustomStableClient.AsyncConnectC(addr: SystemString; Port: Word; const OnResult: TOnState_C);
begin
  Disconnect;

  FStableClientIO.Activted := False;
  FStableClientIO.BindOwnerIO := nil;

  FConnection_Addr := addr;
  FConnection_Port := Port;

  if FOwnerIOClient = nil then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FOnAsyncConnectNotify_C := OnResult;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := nil;
  PostProgress.PostExecuteM(0.0, PostConnection);
end;

procedure TZNet_CustomStableClient.AsyncConnectM(addr: SystemString; Port: Word; const OnResult: TOnState_M);
begin
  Disconnect;

  FStableClientIO.Activted := False;
  FStableClientIO.BindOwnerIO := nil;

  FConnection_Addr := addr;
  FConnection_Port := Port;

  if FOwnerIOClient = nil then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := OnResult;
  FOnAsyncConnectNotify_P := nil;
  PostProgress.PostExecuteM(0.0, PostConnection);
end;

procedure TZNet_CustomStableClient.AsyncConnectP(addr: SystemString; Port: Word; const OnResult: TOnState_P);
begin
  Disconnect;

  FStableClientIO.Activted := False;
  FStableClientIO.BindOwnerIO := nil;

  FConnection_Addr := addr;
  FConnection_Port := Port;

  if FOwnerIOClient = nil then
    begin
      if Assigned(OnResult) then
          OnResult(False);
      exit;
    end;

  FOnAsyncConnectNotify_C := nil;
  FOnAsyncConnectNotify_M := nil;
  FOnAsyncConnectNotify_P := OnResult;

  PostProgress.PostExecuteM(0.0, PostConnection);
end;

function TZNet_CustomStableClient.Connect(addr: SystemString; Port: Word): Boolean;
var
  t: TTimeTick;
begin
  Disconnect;

  FStableClientIO.Activted := False;
  FStableClientIO.BindOwnerIO := nil;

  FConnection_Addr := addr;
  FConnection_Port := Port;

  Result := False;

  if FOwnerIOClient = nil then
      exit;

  if FOwnerIOClient.Connect(addr, Port) then
    begin
      AsyncConnectResult(True);

      t := GetTimeTick;
      while (not FStableClientIO.Activted) and (GetTimeTick - t < 5000) do
          Progress;
      Result := FStableClientIO.Activted;
    end;
end;

function TZNet_CustomStableClient.Connected: Boolean;
begin
  Result := FStableClientIO.Activted;
end;

procedure TZNet_CustomStableClient.Disconnect;
var
  tk: TTimeTick;
begin
  KeepAliveChecking := False;
  if (FOwnerIOClient <> nil) and (FOwnerIOClient.Connected) and (FStableClientIO.Activted) then
    begin
      FStableClientIO.FSequencePacketSignal := False;
      while FStableClientIO.IOBusy do
          ProgressWaitSend(FStableClientIO);
      FStableClientIO.SendConsoleNotifyCmd(C_CloseStableIO);
      FStableClientIO.Progress;
      tk := GetTimeTick() + 1000;
      while FOwnerIOClient.Connected and (not FOwnerIOClient.ClientIO.WriteBuffer_is_NULL) and (GetTimeTick() < tk) do
          FOwnerIOClient.ProgressWaitSend(FOwnerIOClient.ClientIO);
      FStableClientIO.FSequencePacketSignal := True;
    end;

  DisposeObject(FStableClientIO);
  FStableClientIO := TStableClient_PeerIO.Create(self, nil);
end;

function TZNet_CustomStableClient.ClientIO: TPeerIO;
begin
  Result := FStableClientIO;
end;

procedure TZNet_CustomStableClient.Progress;
var
  t: TTimeTick;
begin
  if CustomStableClientProgressing then
      exit;

  CustomStableClientProgressing := True;
  if (FOwnerIOClient <> nil) and (FAutoProgressOwnerIOClient) then
    begin
      FOwnerIOClient.Progress;
    end;
  inherited Progress;

  if FOwnerIOClient <> nil then
    if (FStableClientIO.Activted) and (FStableClientIO.IsSequencePacketModel) then
      begin
        t := GetTimeTick;
        if FStableClientIO.WaitConnecting then
          begin
            if t - FStableClientIO.OwnerIO_LastConnectTick > 5000 then
              begin
                KeepAliveChecking := False;
                FStableClientIO.WaitConnecting := False;
                FOwnerIOClient.Disconnect;
                Reconnection;
              end;
          end
        else if not FOwnerIOClient.Connected then
          begin
            KeepAliveChecking := False;
            Reconnection;
          end
        else if (FStableClientIO.FSequencePacketSignal) and (t - FStableClientIO.LastCommunicationTick_Received > 5000) then
          begin
            if (KeepAliveChecking) then
              begin
                FStableClientIO.LastCommunicationTick_Received := SaveLastCommunicationTick_Received;
                FStableClientIO.LastCommunicationTick_KeepAlive := FStableClientIO.LastCommunicationTick_Received;
                Reconnection;
                KeepAliveChecking := False;
              end
            else
              begin
                FStableClientIO.SendSequencePacketKeepAlive(nil, 0);
                SaveLastCommunicationTick_Received := FStableClientIO.LastCommunicationTick_Received;
                FStableClientIO.LastCommunicationTick_Received := GetTimeTick;
                FStableClientIO.LastCommunicationTick_KeepAlive := FStableClientIO.LastCommunicationTick_Received;
                KeepAliveChecking := True;
              end;
          end;
      end;

  CustomStableClientProgressing := False;
end;

initialization

ProgressBackgroundProc := nil;
ProgressBackgroundMethod := nil;
HPC_Instance_Pool := THPC_Instance_Pool.Create;
Init_ZNet_Instance_Pool();
Init_SwapSpace_Tech();

finalization

DisposeObjectAndNil(HPC_Instance_Pool);
Free_SwapSpace_Tech();
Free_ZNet_Instance_Pool();

end.
 
