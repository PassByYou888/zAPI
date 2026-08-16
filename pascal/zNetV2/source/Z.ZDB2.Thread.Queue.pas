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
{ ****************************************************************************** }
{ * ZDB 2.0 Core-Thread Queue for HPC                                          * }
{ * This unit provides a high-performance, thread-safe command queue for       * }
{ * asynchronous and synchronous operations on TZDB2_Core_Space. It allows     * }
{ * enqueuing read/write/modify/remove commands to be executed by a dedicated  * }
{ * background thread, with support for progress callbacks, event bridges,     * }
{ * and extraction between queues. It is designed for heavy concurrent usage.  * }
{ ****************************************************************************** }
unit Z.ZDB2.Thread.Queue;

{$DEFINE FPC_DELPHI_MODE}      // Enable Delphi-compatible mode for Free Pascal
{$I Z.Define.inc}           // Include global project definitions

interface

uses
  Z.Core, // Core utilities and base classes
{$IFDEF FPC}
  Z.FPC.GenericList, // Generic list support for FPC
{$ENDIF FPC}
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,
  Z.MemoryStream, // Memory stream extensions
  Z.Status, Z.Cipher, Z.ZDB2, Z.ListEngine, Z.TextDataEngine, Z.IOThread,
  Z.FragmentBuffer, // For discontinuous memory space handling
  Z.Notify; // Notification interfaces

type
{$REGION 'Command_Queue'}
  // Forward declaration of the thread queue manager
  TZDB2_Th_Queue = class;

  // Command execution state
  TCMD_State = (csDefault, csDone, csError);
  PCMD_State = ^TCMD_State;

  // Structure pairing a command ID with its execution state
  TZDB2_Th_CMD_ID_And_State = record
    ID: Integer; // Command result ID (e.g., new data ID)
    State: TCMD_State; // Execution state
  end;

  PZDB2_Th_CMD_ID_And_State = ^TZDB2_Th_CMD_ID_And_State;
  TZDB2_Th_CMD_ID_And_State_Array = array of TZDB2_Th_CMD_ID_And_State;
  PZDB2_Th_CMD_ID_And_State_Array = ^TZDB2_Th_CMD_ID_And_State_Array;

  // Structure pairing a memory buffer with its execution state
  TZDB2_Th_CMD_Mem64_And_State = record
    Mem64: TMem64; // Memory buffer containing data
    State: TCMD_State; // Execution state
  end;

  PZDB2_Th_CMD_Mem64_And_State = ^TZDB2_Th_CMD_Mem64_And_State;
  TZDB2_Th_CMD_Mem64_And_State_Array = array of TZDB2_Th_CMD_Mem64_And_State;
  PZDB2_Th_CMD_Mem64_And_State_Array = ^TZDB2_Th_CMD_Mem64_And_State_Array;

  // Structure pairing a stream with its execution state
  TZDB2_Th_CMD_Stream_And_State = record
    Stream: TCore_Stream; // Stream containing data
    State: TCMD_State; // Execution state
  end;

  PZDB2_Th_CMD_Stream_And_State = ^TZDB2_Th_CMD_Stream_And_State;
  TZDB2_Th_CMD_Stream_And_State_Array = array of TZDB2_Th_CMD_Stream_And_State;
  PZDB2_Th_CMD_Stream_And_State_Array = ^TZDB2_Th_CMD_Stream_And_State_Array;

  // Callback when a command completes
  TOn_CMD_Done = procedure() of object;

  // Base class for all commands. Commands are queued and executed by the background thread.
  TZDB2_Th_CMD = class(TCore_Object_Intermediate)
  protected
    OnDone: TOn_CMD_Done; // Callback on completion 每 assigned by user
    Engine: TZDB2_Th_Queue; // Reference to the queue that owns this command 每 set by constructor
    State_Ptr: PCMD_State; // Pointer to external state variable 每 set by Ready()
    // Execute the command on the given core space; must be overridden.
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); virtual; abstract;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue);
    destructor Destroy; override;
    procedure Init; virtual; // Optional initialization hook
    procedure Ready(var State_: TCMD_State); // Enqueue the command and link to state variable
    procedure Execute; // Called by the queue thread to run DoExecute
  end;

  // Command: read a portion of a specific block into a TMem64
  TZDB2_Th_CMD_Get_Block_As_Mem64 = class(TZDB2_Th_CMD)
  protected
    Param_M64: TMem64; // Destination memory 每 set by constructor
    Param_ID, Param_Block_Index, Param_Block_Offset, Param_Block_Read_Size: Integer; // Parameters 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID, Block_Index, Block_Offset, Block_Read_Size: Integer);
  end;

  // Command: modify a portion of a block with data from a TMem64
  TZDB2_Th_CMD_Modify_Block_From_Mem64 = class(TZDB2_Th_CMD)
  protected
    Param_M64: TMem64; // Source memory 每 set by constructor
    Param_ID, Param_Block_Index, Param_Block_Offset: Integer; // Parameters 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Param_M64 after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID, Block_Index, Block_Offset: Integer);
  end;

  // Command: read an entire data object (chain) into a TMem64
  TZDB2_Th_CMD_Get_Data_As_Mem64 = class(TZDB2_Th_CMD)
  protected
    Param_M64: TMem64; // Destination memory 每 set by constructor
    Param_ID: Integer; // Data object ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID: Integer);
  end;

  // Command: read an entire data object into a stream
  TZDB2_Th_CMD_Get_Data_As_Stream = class(TZDB2_Th_CMD)
  protected
    Param_Stream: TCore_Stream; // Destination stream 每 set by constructor
    Param_ID: Integer; // Data object ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; const ID: Integer);
  end;

  // Command: read a sub-range of a data object into a stream
  TZDB2_Th_CMD_Get_Position_Data_As_Stream = class(TZDB2_Th_CMD)
  protected
    Param_Stream: TCore_Stream; // Destination stream 每 set by constructor
    Param_ID: Integer; // Data object ID 每 set by constructor
    Param_Begin_Position, Param_Read_Size: Int64; // Range 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; const ID: Integer; Begin_Position, Read_Size: Int64);
  end;

  // Command: replace an existing data object with data from a TMem64 (remove old, write new)
  TZDB2_Th_CMD_Set_Data_From_Mem64 = class(TZDB2_Th_CMD)
  protected
    Param_M64: TMem64; // Source memory 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable holding the target ID (updated) 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Param_M64 after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; var ID: Integer);
  end;

  // Command: replace an existing data object with data from a stream
  TZDB2_Th_CMD_Set_Data_From_Stream = class(TZDB2_Th_CMD)
  protected
    Param_Stream: TCore_Stream; // Source stream 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable holding the target ID (updated) 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Param_Stream after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; var ID: Integer);
  end;

  // Command: append new data from a TMem64 and return the new ID
  TZDB2_Th_CMD_Append_From_Mem64 = class(TZDB2_Th_CMD)
  protected
    Param_M64: TMem64; // Source memory 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable receiving new ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Param_M64 after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; var ID: Integer);
  end;

  // Command: append new data from a stream
  TZDB2_Th_CMD_Append_From_Stream = class(TZDB2_Th_CMD)
  protected
    Param_Stream: TCore_Stream; // Source stream 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable receiving new ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Param_Stream after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; var ID: Integer);
  end;

  // Command: replace existing data with combined data from multiple TMS64 buffers (write-combine)
  TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64 = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size of all buffers 每 computed by constructor
    Param_Arry: TMS64_Array; // Array of source buffers 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to target ID (updated) 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free all buffers after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMS64_Array; var ID: Integer);
  end;

  // Command: append combined data from multiple TMS64 buffers
  TZDB2_Th_CMD_Append_From_Combine_MemoryStream64 = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size 每 computed by constructor
    Param_Arry: TMS64_Array; // Source buffers 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable receiving new ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free buffers after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMS64_Array; var ID: Integer);
  end;

  // Command: replace existing data with combined data from multiple TMem64 buffers
  TZDB2_Th_CMD_Set_Data_From_Combine_Mem64 = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size 每 computed by constructor
    Param_Arry: TMem64_Array; // Source buffers 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to target ID (updated) 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free buffers after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMem64_Array; var ID: Integer);
  end;

  // Command: append combined data from multiple TMem64 buffers
  TZDB2_Th_CMD_Append_From_Combine_Mem64 = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size 每 computed by constructor
    Param_Arry: TMem64_Array; // Source buffers 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable receiving new ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free buffers after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMem64_Array; var ID: Integer);
  end;

  // Command: replace existing data with combined data from multiple streams
  TZDB2_Th_CMD_Set_Data_From_Combine_Stream = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size 每 computed by constructor
    Param_Arry: TStream_Array; // Source streams 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to target ID (updated) 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free streams after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TStream_Array; var ID: Integer);
  end;

  // Command: append combined data from multiple streams
  TZDB2_Th_CMD_Append_From_Combine_Stream = class(TZDB2_Th_CMD)
  protected
    Arry_Size: Int64; // Total size 每 computed by constructor
    Param_Arry: TStream_Array; // Source streams 每 set by constructor
    Param_ID_Ptr: PInteger; // Points to variable receiving new ID 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free streams after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Arry: TStream_Array; var ID: Integer);
  end;

  // Command: remove a data object by ID
  TZDB2_Th_CMD_Remove = class(TZDB2_Th_CMD)
  protected
    Param_ID: Integer; // ID to remove 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const ID: Integer);
  end;

  // Command: signal the queue thread to exit
  TZDB2_Th_CMD_Exit = class(TZDB2_Th_CMD)
  protected
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue);
  end;

  // Command: do nothing (NOP), used for synchronization or counting
  TZDB2_Th_CMD_NOP = class(TZDB2_Th_CMD)
  protected
    NOP_Num: PInteger; // Pointer to integer to decrement 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; NOP_Num_: PInteger);
  end;

  // Command: increment an integer (atomic counter)
  TZDB2_Th_CMD_INC = class(TZDB2_Th_CMD)
  protected
    Inc_Num: PInteger; // Pointer to integer to increment 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; Inc_Num_: PInteger);
  end;

  // Custom callback command types (procedure of object, reference, nested)
  TOn_ZDB2_Th_CMD_Custom_Execute_C = procedure(Sender: TZDB2_Th_Queue; CoreSpace__: TZDB2_Core_Space; Data: Pointer);
  TOn_ZDB2_Th_CMD_Custom_Execute_M = procedure(Sender: TZDB2_Th_Queue; CoreSpace__: TZDB2_Core_Space; Data: Pointer) of object;
{$IFDEF FPC}
  TOn_ZDB2_Th_CMD_Custom_Execute_P = procedure(Sender: TZDB2_Th_Queue; CoreSpace__: TZDB2_Core_Space; Data: Pointer) is nested;
{$ELSE FPC}
  TOn_ZDB2_Th_CMD_Custom_Execute_P = reference to procedure(Sender: TZDB2_Th_Queue; CoreSpace__: TZDB2_Core_Space; Data: Pointer);
{$ENDIF FPC}

  // Command that executes a user-provided callback (C, M, or P)
  TZDB2_Th_CMD_Custom_Execute = class(TZDB2_Th_CMD)
  protected
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    On_Execute_C: TOn_ZDB2_Th_CMD_Custom_Execute_C; // C-style callback 每 set by user
    On_Execute_M: TOn_ZDB2_Th_CMD_Custom_Execute_M; // Method callback 每 set by user
    On_Execute_P: TOn_ZDB2_Th_CMD_Custom_Execute_P; // Nested/reference callback 每 set by user
    Data: Pointer; // User-defined data 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue);
  end;

  // Command: flush the core space (write all cached data to disk)
  TZDB2_Th_CMD_Flush = class(TZDB2_Th_CMD)
  protected
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue);
  end;

  // Header used for storing a sequence table (list of IDs) in the user custom header
  TSequence_Table_Head = packed record
    Identifier: Word; // Magic identifier (C_Sequence_Table_Identifier)
    ID: Integer; // Data object ID storing the table
  end;

  PSequence_Table_Head = ^TSequence_Table_Head;

  // Command: rebuild the sequence table (list of all data object IDs) and return it
  TZDB2_Th_CMD_Rebuild_And_Get_Sequence_Table = class(TZDB2_Th_CMD)
  protected
    Table_Ptr: PZDB2_BlockHandle; // Pointer to handle to receive the table 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle);
  end;

  // Command: get the sequence table from the custom header and clear it (remove from space)
  TZDB2_Th_CMD_Get_And_Clean_Sequence_Table = class(TZDB2_Th_CMD)
  protected
    Table_Ptr: PZDB2_BlockHandle; // Pointer to handle to receive the table 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle);
  end;

  // Buffer for ID and size pairs
  TSequence_Table_ID_Size_Buffer = array of Int64;
  PSequence_Table_ID_Size_Buffer = ^TSequence_Table_ID_Size_Buffer;

  // Command: compute the size of each ID in the sequence table and fill the buffer
  TZDB2_Th_CMD_Get_ID_Size_From_Sequence_Table = class(TZDB2_Th_CMD)
  protected
    Table_Ptr: PZDB2_BlockHandle; // Pointer to table handle 每 set by constructor
    ID_Size_Buffer_Ptr: PSequence_Table_ID_Size_Buffer; // Pointer to output buffer 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle; var ID_Size_Buffer: TSequence_Table_ID_Size_Buffer);
  end;

  // Event callback for flush backcall sequence table
  TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event = procedure(Sender: TZDB2_Th_Queue; var Sequence_Table: TZDB2_BlockHandle) of object;

  // Command: flush a sequence table built from a backcall event (user provides table)
  TZDB2_Th_CMD_Flush_Backcall_Sequence_Table = class(TZDB2_Th_CMD)
  protected
    OnEvent: TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event; // Event to generate table 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const OnEvent_: TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event);
  end;

  // Command: flush a given sequence table (store it in the custom header)
  TZDB2_Th_CMD_Flush_Sequence_Table = class(TZDB2_Th_CMD)
  protected
    Table_Ptr: PZDB2_BlockHandle; // Pointer to table handle to store 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free the handle pointer after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Table_: PZDB2_BlockHandle);
  end;

  // Header for external (user-defined) data stored in the custom header
  TExternal_Head = packed record
    Identifier: Word; // Magic identifier (C_External_Header_Identifier)
    ID: Integer; // Data object ID storing the external data
  end;

  PExternal_Head = ^TExternal_Head;

  // Command: flush external header data (store a TMem64 blob in the space and link it)
  TZDB2_Th_CMD_Flush_External_Header = class(TZDB2_Th_CMD)
  protected
    Header_Data: TMem64; // Data to store 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    AutoFree_Data: Boolean; // If true, free Header_Data after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Header_Data_: TMem64);
  end;

  // Command: get the external header data and reset (clear) it from the space
  TZDB2_Th_CMD_Get_And_Reset_External_Header = class(TZDB2_Th_CMD)
  protected
    Header_Data: TMem64; // Destination memory 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Header_Data_: TMem64);
  end;

  // Command: extract a set of data objects from this space to another thread queue.
  // It reads each object into a TMem64 and asynchronously appends it to the destination queue.
  TZDB2_Th_CMD_Extract_To = class(TZDB2_Th_CMD)
  protected
    Input_Ptr: PZDB2_BlockHandle; // Pointer to handle of objects to extract 每 set by constructor
    Dest_Th_Engine: TZDB2_Th_Queue; // Destination queue 每 set by constructor
    Output_Ptr: PZDB2_Th_CMD_ID_And_State_Array; // Pointer to array to receive resulting IDs and states 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    Max_Queue: Integer; // Maximum queue size before waiting 每 set by user (default 100)
    Wait_Queue: Boolean; // Whether to wait for destination queue to drain 每 set by user (default True)
    Aborted: PBoolean; // Pointer to abort flag 每 set by user
    AutoFree_Data: Boolean; // If true, free Input_Ptr after execution 每 set by user
    constructor Create(const ThEng_: TZDB2_Th_Queue;
      const Input_: PZDB2_BlockHandle;
      const Dest_Th_Engine_: TZDB2_Th_Queue; const Output_: PZDB2_Th_CMD_ID_And_State_Array);
  end;

  // Command: format (build) a new space with zero-filled blocks
  TZDB2_Th_CMD_Format_Custom_Space = class(TZDB2_Th_CMD)
  protected
    Param_Space: Int64; // Total space size 每 set by constructor
    Param_Block: Word; // Block size 每 set by constructor
    Param_OnProgress: TZDB2_OnProgress; // Progress callback 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word; const OnProgress: TZDB2_OnProgress);
  end;

  // Command: fast-format a new space without zero-filling (uses natural data)
  TZDB2_Th_CMD_Fast_Format_Custom_Space = class(TZDB2_Th_CMD)
  protected
    Param_Space: Int64; // Total space size 每 set by constructor
    Param_Block: Word; // Block size 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word);
  end;

  // Command: append space with zero-filled blocks
  TZDB2_Th_CMD_Append_Custom_Space = class(TZDB2_Th_CMD)
  protected
    Param_Space: Int64; // Space to append 每 set by constructor
    Param_Block: Word; // Block size 每 set by constructor
    Param_OnProgress: TZDB2_OnProgress; // Progress callback 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word; const OnProgress: TZDB2_OnProgress);
  end;

  // Command: fast-append space without zero-filling
  TZDB2_Th_CMD_Fast_Append_Custom_Space = class(TZDB2_Th_CMD)
  protected
    Param_Space: Int64; // Space to append 每 set by constructor
    Param_Block: Word; // Block size 每 set by constructor
    procedure DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State); override;
  public
    constructor Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word);
  end;

  // bridge **********************************************************************************
  // Event callbacks for bridge commands (C, M, P)
  TOn_Mem64_And_State_Event_C = procedure(var Sender: TZDB2_Th_CMD_Mem64_And_State);
  TOn_Mem64_And_State_Event_M = procedure(var Sender: TZDB2_Th_CMD_Mem64_And_State) of object;
{$IFDEF FPC}
  TOn_Mem64_And_State_Event_P = procedure(var Sender: TZDB2_Th_CMD_Mem64_And_State) is nested;
{$ELSE FPC}
  TOn_Mem64_And_State_Event_P = reference to procedure(var Sender: TZDB2_Th_CMD_Mem64_And_State);
{$ENDIF FPC}

  // Bridge class for commands that produce a TMem64 result. It links a command with an event
  // that is fired when the command completes.
  TZDB2_Th_CMD_Bridge_Mem64_And_State = class(TCore_Object_Intermediate)
  protected
    OnResult_C: TOn_Mem64_And_State_Event_C; // C-style callback 每 set by user
    OnResult_M: TOn_Mem64_And_State_Event_M; // Method callback 每 set by user
    OnResult_P: TOn_Mem64_And_State_Event_P; // Nested/reference callback 每 set by user
    procedure CMD_Done; // Internal handler called when command finishes
  public
    CMD: TZDB2_Th_CMD; // The command being bridged 每 set by Init
    Mem64_And_State: TZDB2_Th_CMD_Mem64_And_State; // Result structure 每 set by caller before Ready
    constructor Create;
    procedure Init(CMD_: TZDB2_Th_CMD);
    procedure Ready; // Enqueue the command
  end;

  TOn_Stream_And_State_Event_C = procedure(var Sender: TZDB2_Th_CMD_Stream_And_State);
  TOn_Stream_And_State_Event_M = procedure(var Sender: TZDB2_Th_CMD_Stream_And_State) of object;
{$IFDEF FPC}
  TOn_Stream_And_State_Event_P = procedure(var Sender: TZDB2_Th_CMD_Stream_And_State) is nested;
{$ELSE FPC}
  TOn_Stream_And_State_Event_P = reference to procedure(var Sender: TZDB2_Th_CMD_Stream_And_State);
{$ENDIF FPC}

  // Bridge for commands that produce a TCore_Stream result
  TZDB2_Th_CMD_Bridge_Stream_And_State = class(TCore_Object_Intermediate)
  protected
    OnResult_C: TOn_Stream_And_State_Event_C;
    OnResult_M: TOn_Stream_And_State_Event_M;
    OnResult_P: TOn_Stream_And_State_Event_P;
    procedure CMD_Done;
  public
    CMD: TZDB2_Th_CMD;
    Stream_And_State: TZDB2_Th_CMD_Stream_And_State;
    constructor Create;
    procedure Init(CMD_: TZDB2_Th_CMD);
    procedure Ready;
  end;

  TOn_ID_And_State_Event_C = procedure(var Sender: TZDB2_Th_CMD_ID_And_State);
  TOn_ID_And_State_Event_M = procedure(var Sender: TZDB2_Th_CMD_ID_And_State) of object;
{$IFDEF FPC}
  TOn_ID_And_State_Event_P = procedure(var Sender: TZDB2_Th_CMD_ID_And_State) is nested;
{$ELSE FPC}
  TOn_ID_And_State_Event_P = reference to procedure(var Sender: TZDB2_Th_CMD_ID_And_State);
{$ENDIF FPC}

  // Bridge for commands that produce an ID result
  TZDB2_Th_CMD_Bridge_ID_And_State = class(TCore_Object_Intermediate)
  protected
    OnResult_C: TOn_ID_And_State_Event_C;
    OnResult_M: TOn_ID_And_State_Event_M;
    OnResult_P: TOn_ID_And_State_Event_P;
    procedure CMD_Done;
  public
    CMD: TZDB2_Th_CMD;
    ID_And_State: TZDB2_Th_CMD_ID_And_State;
    constructor Create;
    procedure Init(CMD_: TZDB2_Th_CMD);
    procedure Ready;
  end;

  TOn_State_Event_C = procedure(var Sender: TCMD_State);
  TOn_State_Event_M = procedure(var Sender: TCMD_State) of object;
{$IFDEF FPC}
  TOn_State_Event_P = procedure(var Sender: TCMD_State) is nested;
{$ELSE FPC}
  TOn_State_Event_P = reference to procedure(var Sender: TCMD_State);
{$ENDIF FPC}

  // Bridge for commands that only produce a state (no return value)
  TZDB2_Th_CMD_Bridge_State = class(TCore_Object_Intermediate)
  protected
    OnResult_C: TOn_State_Event_C;
    OnResult_M: TOn_State_Event_M;
    OnResult_P: TOn_State_Event_P;
    procedure CMD_Done;
  public
    CMD: TZDB2_Th_CMD;
    State: TCMD_State;
    constructor Create;
    procedure Init(CMD_: TZDB2_Th_CMD);
    procedure Ready;
  end;
  // bridge **********************************************************************************

  // Thread-safe queue that holds pending commands (ordered structure)
  TZDB2_Th_CMD_Queue = TCriticalOrderStruct<TZDB2_Th_CMD>;
{$ENDREGION 'Command_Queue'}
{$REGION 'Command_Dispatch'}

  // Pool of all active TZDB2_Th_Queue instances (for management)
  TZDB2_Th_Queue_Instance_Pool = class(TCritical_BigList<TZDB2_Th_Queue>)
  end;

  // Main thread queue class. Manages a background thread that executes commands on a TZDB2_Core_Space.
  TZDB2_Th_Queue = class(TCore_Object_Intermediate)
  private
    FInstance_Pool_Ptr: TZDB2_Th_Queue_Instance_Pool.PQueueStruct; // Pointer to this instance in the pool 每 set by constructor
    FCMD_Queue: TZDB2_Th_CMD_Queue; // Command queue 每 created by constructor
    FCMD_Execute_Thread_Is_Runing: Boolean; // Flag indicating thread is active 每 set by Do_Th_Queue
    FCMD_Execute_Thread_Is_Exit: Boolean; // Flag indicating thread has exited 每 set by Do_Th_Queue
    FCoreSpace_Fast_Append_Space: Boolean; // If true, use fast append 每 set by user (default True)
    FCoreSpace_Max_File_Size: Int64; // Maximum file size limit (<=0 = infinite) 每 set by user
    FCoreSpace_Auto_Append_Space: Boolean; // If true, auto-append space on no-space 每 set by user (default True)
    FCoreSpace_Mode: TZDB2_SpaceMode; // Operation mode 每 set by constructor
    FCoreSpace_CacheMemory: Int64; // Cache memory limit 每 set by constructor
    FCoreSpace_Delta: Int64; // Size increment when auto-append 每 set by constructor
    CoreSpace_BlockSize: Word; // Block size 每 set by constructor
    FCoreSpace_Cipher: IZDB2_Cipher; // Encryption interface 每 set by constructor
    FCoreSpace_IOHnd: TIOHnd; // I/O handle for the underlying space 每 initialized by constructor
    CoreSpace__: TZDB2_Core_Space; // The actual core space instance 每 created by thread

    // Database state (cached from core space)
    FCoreSpace_State: TZDB2_Atom_SpaceState; // Atomic state of the space 每 updated by thread
    FLast_Modification: TTimeTick; // Last modification time 每 updated by thread
    FIs_Modification: Boolean; // Whether space is modified 每 updated by thread
    FCoreSpace_File_Size: Int64; // Current file size 每 updated by thread
    FCoreSpace_BlockCount: Integer; // Number of blocks 每 updated by thread
    FIs_OnlyRead: Boolean; // True if read-only 每 set by constructor
    FIs_Memory_Database: Boolean; // True if using memory stream 每 set by constructor
    FIs_File_Database: Boolean; // True if using file stream 每 set by constructor
    FDatabase_FileName: U_String; // File name (if file-based) 每 set by constructor
    FFragment_Buffer_Num: Int64; // Number of fragments in safe-flush stream 每 updated by thread
    FFragment_Buffer_Memory: Int64; // Memory used by fragments 每 updated by thread
    FQueue_Write_IO_Size: TAtomInt64; // Total size of pending write commands 每 incremented/decremented by commands

  private
    // Background thread procedure
    procedure Do_Th_Queue(ThSender: TCompute);
    // Called when freeing a command from the queue
    procedure Do_Free_CMD(var p: TZDB2_Th_CMD);
    // Handler for "no space" event from core space 每 attempts auto-append
    procedure Do_No_Space(Trigger: TZDB2_Core_Space; Siz_: Int64; var retry: Boolean);
    // Increment/decrement the write I/O size counter (used for flow control)
    procedure Inc_Queue_Wirte_IO_Size(siz: Int64);
    procedure Dec_Queue_Wirte_IO_Size(siz: Int64);

  public
    // Check if a stream contains a valid ZDB2 space
    class function CheckStream(Stream_: TCore_Stream; Cipher_: IZDB2_Cipher): Boolean;

    // Constructor: creates a thread queue for the given stream.
    // Mode_: operation mode, CacheMemory_: cache limit, Stream_: underlying stream,
    // AutoFree_: whether to free stream on destroy, OnlyRead_: read-only mode,
    // Delta_: auto-append increment, BlockSize_: block size, Cipher_: encryption interface.
    constructor Create(Mode_: TZDB2_SpaceMode; CacheMemory_: Int64;
      Stream_: TCore_Stream; AutoFree_, OnlyRead_: Boolean; Delta_: Int64; BlockSize_: Word; Cipher_: IZDB2_Cipher);
    destructor Destroy; override;

    // Properties for internal thread instance (use with care)
    property CMD_Queue: TZDB2_Th_CMD_Queue read FCMD_Queue;
    property CoreSpace: TZDB2_Core_Space read CoreSpace__;

    // Configuration properties
    property Fast_Append_Space: Boolean read FCoreSpace_Fast_Append_Space write FCoreSpace_Fast_Append_Space; // default true
    property CoreSpace_Max_File_Size: Int64 read FCoreSpace_Max_File_Size write FCoreSpace_Max_File_Size; // <=0 = infinite
    property Auto_Append_Space: Boolean read FCoreSpace_Auto_Append_Space write FCoreSpace_Auto_Append_Space; // default true

    // State properties (read-only, updated by thread)
    property Last_Modification: TTimeTick read FLast_Modification;
    property Is_Modification: Boolean read FIs_Modification;
    property CoreSpace_File_Size: Int64 read FCoreSpace_File_Size;
    property CoreSpace_BlockCount: Integer read FCoreSpace_BlockCount;
    property Is_OnlyRead: Boolean read FIs_OnlyRead;
    property Is_Memory_Database: Boolean read FIs_Memory_Database;
    property Is_File_Database: Boolean read FIs_File_Database;
    property Database_FileName: U_String read FDatabase_FileName;

    // Queue status
    function QueueNum: NativeInt; // Number of pending commands
    function CoreSpace_Size: Int64; // Used data size
    function CoreSpace_Physics_Size: Int64; // Total physical size
    function CoreSpace_Free_Space_Size: Int64; // Free space
    property Fragment_Buffer_Num: Int64 read FFragment_Buffer_Num;
    property Fragment_Buffer_Memory: Int64 read FFragment_Buffer_Memory;
    property Queue_Write_IO_Size: TAtomInt64 read FQueue_Write_IO_Size;
    procedure Wait_Queue; // Wait until queue is empty

    // ============ Synchronous (blocking) operations ============
    // These methods enqueue a command and wait for completion, returning result.

    // Read a portion of a block
    function Sync_Get_Block_Data(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer): Boolean;
    // Modify a portion of a block with data from Mem64
    function Sync_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64): Boolean;
    // Read entire data object into Mem64
    function Sync_GetData(Mem64: TMem64; ID: Integer): Boolean; overload;
    // Write data from Mem64, replacing existing object if ID>=0, else append
    function Sync_SetData(Mem64: TMem64; var ID: Integer): Boolean; overload;
    // Append data from Mem64 and return new ID
    function Sync_Append(Mem64: TMem64; var ID: Integer): Boolean; overload;
    // Read data object into a stream
    function Sync_GetData(Stream: TCore_Stream; ID: Integer): Boolean; overload;
    // Read a sub-range of data into a stream
    function Sync_Get_Position_Data_As_Stream(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64): Boolean;
    // Write from stream (replace or append)
    function Sync_SetData(Stream: TCore_Stream; var ID: Integer): Boolean; overload;
    function Sync_Append(Stream: TCore_Stream; var ID: Integer): Boolean; overload;
    // Write-combine from multiple buffers (replace or append)
    function Sync_SetData_From_Combine_Memory(const Arry: TMS64_Array; var ID: Integer): Boolean; overload;
    function Sync_Append_From_Combine_Memory(const Arry: TMS64_Array; var ID: Integer): Boolean; overload;
    function Sync_SetData_From_Combine_Memory(const Arry: TMem64_Array; var ID: Integer): Boolean; overload;
    function Sync_Append_From_Combine_Memory(const Arry: TMem64_Array; var ID: Integer): Boolean; overload;
    function Sync_SetData_From_Combine_Stream(const Arry: TStream_Array; var ID: Integer): Boolean; overload;
    function Sync_Append_From_Combine_Stream(const Arry: TStream_Array; var ID: Integer): Boolean; overload;
    // Remove data object
    function Sync_Remove(ID: Integer): Boolean;
    // Flush core space
    function Sync_Flush(): Boolean;
    // NOP (no operation)
    function Sync_NOP(): Boolean;
    // Rebuild sequence table and return it
    function Sync_Rebuild_And_Get_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean;
    // Get sequence table from header and clear it
    function Sync_Get_And_Clean_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean;
    // Compute sizes for each ID in sequence table
    function Sync_Get_ID_Size_From_Sequence_Table(var Table_: TZDB2_BlockHandle; var ID_Size_Buffer: TSequence_Table_ID_Size_Buffer): Boolean;
    // Flush (store) a sequence table
    function Sync_Flush_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean; overload;
    function Sync_Flush_Sequence_Table(L: TZDB2_ID_List): Boolean; overload;
    function Sync_Flush_Sequence_Table(L: TZDB2_ID_Pool): Boolean; overload;
    // Flush external header data
    function Sync_Flush_External_Header(Header_Data: TMem64): Boolean; overload;
    // Get and reset external header
    function Sync_Get_And_Reset_External_Header(Header_Data: TMem64): Boolean; overload;

    // Extract a set of objects to another queue (synchronous)
    function Sync_Extract_To(var Input_: TZDB2_BlockHandle; const Dest_Th_Engine_: TZDB2_Th_Queue; var Output_: TZDB2_Th_CMD_ID_And_State_Array): Boolean; overload;
    function Sync_Extract_To(var Input_: TZDB2_BlockHandle; const Dest_Th_Engine_: TZDB2_Th_Queue; var Output_: TZDB2_Th_CMD_ID_And_State_Array; Aborted: PBoolean): Boolean; overload;
    // Extract to a stream (creates a new compacted space)
    function Sync_Extract_To_Stream(var Input_: TZDB2_BlockHandle; const Dest: TCore_Stream; const Cipher_: IZDB2_Cipher): Integer;
    // Extract to a file
    function Sync_Extract_To_File(var Input_: TZDB2_BlockHandle; const Dest: U_String; const Cipher_: IZDB2_Cipher): Integer;
    // Extract to another queue and copy sequence table
    function Sync_Extract_To_Queue_Engine_And_Copy_Sequence_Table(var Input_: TZDB2_BlockHandle; const Dest_Th_Engine_: TZDB2_Th_Queue; Aborted: PBoolean): Integer;

    // Core-space formatting/append operations (synchronous)
    function Sync_Format_Custom_Space(const Space_: Int64; const Block_: Word; const OnProgress_: TZDB2_OnProgress): Boolean;
    function Sync_Fast_Format_Custom_Space(const Space_: Int64; const Block_: Word): Boolean;
    function Sync_Append_Custom_Space(const Space_: Int64; const Block_: Word; const OnProgress_: TZDB2_OnProgress): Boolean;
    function Sync_Fast_Append_Custom_Space(const Space_: Int64; const Block_: Word): Boolean;

    // ============ Asynchronous (non-blocking) operations ============
    // These methods enqueue commands and return immediately. Completion can be signaled via optional state pointer or bridge events.

    // Modify a block (async)
    procedure Async_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64; AutoFree_Data: Boolean); overload;
    procedure Async_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64; AutoFree_Data: Boolean; State: PCMD_State); overload;
    // Read data as Mem64 (async)
    procedure Async_GetData_AsMem64(ID: Integer; Mem64: TMem64; State: PCMD_State);
    // Read data as stream (async)
    procedure Async_GetData_AsStream(ID: Integer; Stream: TCore_Stream; State: PCMD_State);
    // Read position data as stream (async)
    procedure Async_Get_Position_Data_As_Stream(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; State: PCMD_State);
    // Set data from Mem64 (async, replace or append)
    procedure Async_SetData(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer); overload;
    procedure Async_Append(Mem64: TMem64; AutoFree_Data: Boolean); overload;
    procedure Async_Append(Mem64: TMem64; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State); overload;
    // Set data from stream (async)
    procedure Async_SetData(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer); overload;
    procedure Async_Append(Stream: TCore_Stream; AutoFree_Data: Boolean); overload;
    procedure Async_Append(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State); overload;
    // Set data from combined TMS64 array (async)
    procedure Async_SetData_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer); overload;
    procedure Async_Append_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean); overload;
    procedure Async_Append_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State); overload;
    // Set data from combined TMem64 array (async)
    procedure Async_SetData_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer); overload;
    procedure Async_Append_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean); overload;
    procedure Async_Append_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State); overload;
    // Set data from combined stream array (async)
    procedure Async_SetData_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer); overload;
    procedure Async_Append_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean); overload;
    procedure Async_Append_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State); overload;
    // Misc async operations
    procedure Async_Remove(ID: Integer); overload;
    procedure Async_Flush();
    procedure Async_NOP(); overload;
    procedure Async_NOP(var NOP_Num_: Integer); overload;
    procedure Async_INC(var Inc_Num: Integer);
    procedure Async_Execute_C(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_C);
    procedure Async_Execute_M(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_M);
    procedure Async_Execute_P(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_P);
    procedure Async_Flush_Sequence_Table(const Table_: TZDB2_BlockHandle); overload;
    procedure Async_Flush_Sequence_Table(const L: TZDB2_ID_List); overload;
    procedure Async_Flush_External_Header(Header_Data: TMem64; AutoFree_Data: Boolean);
    // Core-space async operations (no progress callback)
    procedure Async_Format_Custom_Space(const Space_: Int64; const Block_: Word);
    procedure Async_Fast_Format_Custom_Space(const Space_: Int64; const Block_: Word);
    procedure Async_Append_Custom_Space(const Space_: Int64; const Block_: Word);
    procedure Async_Fast_Append_Custom_Space(const Space_: Int64; const Block_: Word);

    // ============ Asynchronous with bridge events (callback) ============
    // These methods enqueue commands and call the provided event when complete.

    // Get block data with Mem64 result
    procedure Async_Get_Block_Data_AsMem64_C(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_C);
    procedure Async_Get_Block_Data_AsMem64_M(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_M);
    procedure Async_Get_Block_Data_AsMem64_P(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_P);
    // Get position data as stream with callback
    procedure Async_Get_Position_Data_As_Stream_C(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_C);
    procedure Async_Get_Position_Data_As_Stream_M(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_M);
    procedure Async_Get_Position_Data_As_Stream_P(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_P);
    // Get full data as Mem64 with callback
    procedure Async_GetData_AsMem64_C(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_C);
    procedure Async_GetData_AsMem64_M(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_M);
    procedure Async_GetData_AsMem64_P(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_P);
    // Get full data as stream with callback
    procedure Async_GetData_AsStream_C(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_C);
    procedure Async_GetData_AsStream_M(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_M);
    procedure Async_GetData_AsStream_P(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_P);
    // Set data from Mem64 with ID result callback
    procedure Async_SetData_C(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_SetData_M(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_SetData_P(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P); overload;
    // Append from Mem64 with ID result callback
    procedure Async_Append_C(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_Append_M(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_Append_P(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P); overload;
    // Set data from stream with ID result callback
    procedure Async_SetData_C(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_SetData_M(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_SetData_P(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P); overload;
    // Append from stream with ID result callback
    procedure Async_Append_C(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_Append_M(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_Append_P(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P); overload;
    // Set data from combined TMS64 with ID result callback
    procedure Async_SetData_From_Combine_Memory_C(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_SetData_From_Combine_Memory_M(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_SetData_From_Combine_Memory_P(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P); overload;
    procedure Async_Append_From_Combine_Memory_C(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_Append_From_Combine_Memory_M(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_Append_From_Combine_Memory_P(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P); overload;
    // Set data from combined TMem64 with ID result callback
    procedure Async_SetData_From_Combine_Memory_C(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_SetData_From_Combine_Memory_M(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_SetData_From_Combine_Memory_P(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P); overload;
    procedure Async_Append_From_Combine_Memory_C(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_Append_From_Combine_Memory_M(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_Append_From_Combine_Memory_P(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P); overload;
    // Set data from combined streams with ID result callback
    procedure Async_SetData_From_Combine_Stream_C(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_SetData_From_Combine_Stream_M(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_SetData_From_Combine_Stream_P(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P); overload;
    procedure Async_Append_From_Combine_Stream_C(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C); overload;
    procedure Async_Append_From_Combine_Stream_M(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M); overload;
    procedure Async_Append_From_Combine_Stream_P(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P); overload;

    // Flush sequence table with backcall (user provides table via event)
    procedure Async_Flush_Backcall_Sequence_Table(const OnEvent_: TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event);
    // Flush sequence table with state callback
    procedure Async_Flush_Sequence_Table_C(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_C); overload;
    procedure Async_Flush_Sequence_Table_C(const L: TZDB2_ID_List; OnResult: TOn_State_Event_C); overload;
    procedure Async_Flush_Sequence_Table_M(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_M); overload;
    procedure Async_Flush_Sequence_Table_M(const L: TZDB2_ID_List; OnResult: TOn_State_Event_M); overload;
    procedure Async_Flush_Sequence_Table_P(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_P); overload;
    procedure Async_Flush_Sequence_Table_P(const L: TZDB2_ID_List; OnResult: TOn_State_Event_P); overload;

    // Misc utility: convert an array of ID+State to a plain block handle
    class function Get_Handle(var buff: TZDB2_Th_CMD_ID_And_State_Array): TZDB2_BlockHandle;

    // Test procedure (for development)
    class procedure Test;
  end;
{$ENDREGION 'Command_Dispatch'}


const
  // Magic identifier for sequence table stored in user custom header (first 2 bytes)
  C_Sequence_Table_Identifier: Word = $FFFF;
  // Magic identifier for external header stored in user custom header (bytes 6-7)
  C_External_Header_Identifier: Word = $8888;

var
  // Global pool of all thread queue instances (for debugging or management)
  ZDB2_Th_Queue_Instance_Pool__: TZDB2_Th_Queue_Instance_Pool;

implementation

constructor TZDB2_Th_CMD.Create(const ThEng_: TZDB2_Th_Queue);
begin
  inherited Create;
  OnDone := nil;
  Engine := ThEng_;
  State_Ptr := nil;
  if ThEng_ = nil then
      RaiseInfo('error');
end;

destructor TZDB2_Th_CMD.Destroy;
begin
  inherited Destroy;
end;

procedure TZDB2_Th_CMD.Init;
begin

end;

procedure TZDB2_Th_CMD.Ready(var State_: TCMD_State);
begin
  State_Ptr := @State_;
  State_Ptr^ := TCMD_State.csDefault;
  Engine.FCMD_Queue.Push(self);
end;

procedure TZDB2_Th_CMD.Execute;
begin
  try
    DoExecute(Engine.CoreSpace__, State_Ptr);
    if State_Ptr^ = TCMD_State.csDefault then
        State_Ptr^ := TCMD_State.csDone;
  except
      State_Ptr^ := TCMD_State.csError;
  end;

  if State_Ptr^ = TCMD_State.csError then
      DoStatus('%s error.', [ClassName]);

  try
    if Assigned(OnDone) then
        OnDone();
  except
  end;
end;

procedure TZDB2_Th_CMD_Get_Block_As_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  hnd: TZDB2_BlockHandle;
  id_: Integer;
begin
  hnd := CoreSpace__.GetSpaceHnd(Param_ID);
  if (length(hnd) = 0) or (Param_Block_Index < 0) or (Param_Block_Index >= length(hnd)) then
      State^ := TCMD_State.csError
  else
    begin
      Param_M64.Size := Param_Block_Read_Size;
      if not CoreSpace__.Block_IO_Custom_Read(Param_M64.Memory, hnd[Param_Block_Index], Param_Block_Offset, Param_Block_Read_Size) then
          State^ := TCMD_State.csError;
    end;
end;

constructor TZDB2_Th_CMD_Get_Block_As_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID, Block_Index, Block_Offset, Block_Read_Size: Integer);
begin
  inherited Create(ThEng_);
  Param_M64 := Mem64;
  Param_ID := ID;
  Param_Block_Index := Block_Index;
  Param_Block_Offset := Block_Offset;
  Param_Block_Read_Size := Block_Read_Size;
  Init();
end;

procedure TZDB2_Th_CMD_Modify_Block_From_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  hnd: TZDB2_BlockHandle;
  id_: Integer;
  tmp: TMem64;
  r: Word;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Param_M64.Size);
  if Param_M64.Size > 0 then
    begin
      hnd := CoreSpace__.GetSpaceHnd(Param_ID);
      if (Param_Block_Offset < 0) or (length(hnd) = 0) or (Param_Block_Index < 0) or (Param_Block_Index >= length(hnd)) then
          State^ := TCMD_State.csError
      else
        begin
          tmp := TMem64.Create;
          tmp.Size := $FFFF;
          r := CoreSpace__.Block_IO_Read(tmp.Memory, hnd[Param_Block_Index]);
          if (r >= Param_Block_Offset + Param_M64.Size) then
            begin
              CopyPtr(Param_M64.Memory, tmp.PosAsPtr(Param_Block_Offset), Param_M64.Size);
              if not CoreSpace__.Block_IO_Write(tmp.Memory, hnd[Param_Block_Index]) then
                  State^ := TCMD_State.csError;
            end
          else
              State^ := TCMD_State.csError;
          DisposeObject(tmp);
        end;
      SetLength(hnd, 0);
    end;
  if AutoFree_Data then
      DisposeObject(Param_M64);
end;

constructor TZDB2_Th_CMD_Modify_Block_From_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID, Block_Index, Block_Offset: Integer);
begin
  inherited Create(ThEng_);
  Param_M64 := Mem64;
  Param_ID := ID;
  Param_Block_Index := Block_Index;
  Param_Block_Offset := Block_Offset;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Get_Data_As_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if not CoreSpace__.ReadData(Param_M64, Param_ID) then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Get_Data_As_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; const ID: Integer);
begin
  inherited Create(ThEng_);
  Param_M64 := Mem64;
  Param_ID := ID;
  Init();
end;

procedure TZDB2_Th_CMD_Get_Data_As_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if not CoreSpace__.ReadStream(Param_Stream, Param_ID) then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Get_Data_As_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; const ID: Integer);
begin
  inherited Create(ThEng_);
  Param_Stream := Stream;
  Param_ID := ID;
  Init();
end;

procedure TZDB2_Th_CMD_Get_Position_Data_As_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if CoreSpace__.Read_Position(Param_Stream, Param_ID, Param_Begin_Position, Param_Read_Size) <= 0 then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; const ID: Integer; Begin_Position, Read_Size: Int64);
begin
  inherited Create(ThEng_);
  Param_Stream := Stream;
  Param_ID := ID;
  Param_Begin_Position := Begin_Position;
  Param_Read_Size := Read_Size;
  Init();
end;

procedure TZDB2_Th_CMD_Set_Data_From_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  old_ID: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Param_M64.Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else
    begin
      old_ID := Param_ID_Ptr^;
      if not CoreSpace__.WriteData(Param_M64, Param_ID_Ptr^, not AutoFree_Data) then // write new
          State^ := TCMD_State.csError
      else if not CoreSpace__.RemoveData(old_ID, False) then // remove old
          State^ := TCMD_State.csError;
    end;
  if AutoFree_Data then
      DisposeObject(Param_M64);
end;

constructor TZDB2_Th_CMD_Set_Data_From_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; var ID: Integer);
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  Param_M64 := Mem64;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Set_Data_From_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  old_ID: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Param_Stream.Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else
    begin
      old_ID := Param_ID_Ptr^;
      if not CoreSpace__.WriteStream(Param_Stream, Param_ID_Ptr^) then // write new
          State^ := TCMD_State.csError
      else if not CoreSpace__.RemoveData(old_ID, False) then // remove old
          State^ := TCMD_State.csError;
    end;
  if AutoFree_Data then
      DisposeObject(Param_Stream);
end;

constructor TZDB2_Th_CMD_Set_Data_From_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; var ID: Integer);
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  Param_Stream := Stream;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Append_From_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  Engine.Dec_Queue_Wirte_IO_Size(Param_M64.Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.WriteData(Param_M64, Param_ID_Ptr^, not AutoFree_Data) then
      State^ := TCMD_State.csError;
  if AutoFree_Data then
      DisposeObject(Param_M64);
end;

constructor TZDB2_Th_CMD_Append_From_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Mem64: TMem64; var ID: Integer);
begin
  inherited Create(ThEng_);
  ID := -1;
  Param_ID_Ptr := @ID;
  Param_M64 := Mem64;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Append_From_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  Engine.Dec_Queue_Wirte_IO_Size(Param_Stream.Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.WriteStream(Param_Stream, Param_ID_Ptr^) then
      State^ := TCMD_State.csError;
  if AutoFree_Data then
      DisposeObject(Param_Stream);
end;

constructor TZDB2_Th_CMD_Append_From_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Stream: TCore_Stream; var ID: Integer);
begin
  inherited Create(ThEng_);
  ID := -1;
  Param_ID_Ptr := @ID;
  Param_Stream := Stream;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  old_ID, i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else
    begin
      old_ID := Param_ID_Ptr^;
      if not CoreSpace__.Write_Combine_Memory(Param_Arry, Param_ID_Ptr^) then // write new
          State^ := TCMD_State.csError
      else if not CoreSpace__.RemoveData(old_ID, False) then // remove old
          State^ := TCMD_State.csError;
    end;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMS64_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.Write_Combine_Memory(Param_Arry, Param_ID_Ptr^) then // write new
      State^ := TCMD_State.csError;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMS64_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  old_ID, i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else
    begin
      old_ID := Param_ID_Ptr^;
      if not CoreSpace__.Write_Combine_Memory(Param_Arry, Param_ID_Ptr^) then // write new
          State^ := TCMD_State.csError
      else if not CoreSpace__.RemoveData(old_ID, False) then // remove old
          State^ := TCMD_State.csError;
    end;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMem64_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Append_From_Combine_Mem64.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.Write_Combine_Memory(Param_Arry, Param_ID_Ptr^) then // write new
      State^ := TCMD_State.csError;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TMem64_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Set_Data_From_Combine_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  old_ID, i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else
    begin
      old_ID := Param_ID_Ptr^;
      if not CoreSpace__.Write_Combine_Stream(Param_Arry, Param_ID_Ptr^) then // write new
          State^ := TCMD_State.csError
      else if not CoreSpace__.RemoveData(old_ID, False) then // remove old
          State^ := TCMD_State.csError;
    end;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TStream_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Append_From_Combine_Stream.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  i: Integer;
begin
  Engine.Dec_Queue_Wirte_IO_Size(Arry_Size);
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.Write_Combine_Stream(Param_Arry, Param_ID_Ptr^) then // write new
      State^ := TCMD_State.csError;
  if AutoFree_Data then
    for i := 0 to length(Param_Arry) - 1 do
        DisposeObject(Param_Arry[i]);
  SetLength(Param_Arry, 0);
end;

constructor TZDB2_Th_CMD_Append_From_Combine_Stream.Create(const ThEng_: TZDB2_Th_Queue; const Arry: TStream_Array; var ID: Integer);
var
  L, i: Integer;
begin
  inherited Create(ThEng_);
  Param_ID_Ptr := @ID;
  // prepare array
  Arry_Size := 0;
  L := length(Arry);
  SetLength(Param_Arry, L);
  for i := 0 to L - 1 do
    begin
      Param_Arry[i] := Arry[i];
      inc(Arry_Size, Param_Arry[i].Size);
    end;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Remove.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
      State^ := TCMD_State.csError
  else if not CoreSpace__.RemoveData(Param_ID, False) then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Remove.Create(const ThEng_: TZDB2_Th_Queue; const ID: Integer);
begin
  inherited Create(ThEng_);
  Param_ID := ID;
  Init();
end;

procedure TZDB2_Th_CMD_Exit.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  Engine.FCMD_Execute_Thread_Is_Runing := False;
end;

constructor TZDB2_Th_CMD_Exit.Create(const ThEng_: TZDB2_Th_Queue);
begin
  inherited Create(ThEng_);
  Init();
end;

procedure TZDB2_Th_CMD_NOP.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if NOP_Num <> nil then
      AtomDec(NOP_Num^);
end;

constructor TZDB2_Th_CMD_NOP.Create(const ThEng_: TZDB2_Th_Queue; NOP_Num_: PInteger);
begin
  inherited Create(ThEng_);
  NOP_Num := NOP_Num_;
  if NOP_Num <> nil then
      AtomInc(NOP_Num^);
  Init();
end;

procedure TZDB2_Th_CMD_INC.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if Inc_Num <> nil then
      AtomInc(Inc_Num^);
end;

constructor TZDB2_Th_CMD_INC.Create(const ThEng_: TZDB2_Th_Queue; Inc_Num_: PInteger);
begin
  inherited Create(ThEng_);
  Inc_Num := Inc_Num_;
  Init();
end;

procedure TZDB2_Th_CMD_Custom_Execute.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if Assigned(On_Execute_C) then
      On_Execute_C(Engine, CoreSpace__, Data)
  else if Assigned(On_Execute_M) then
      On_Execute_M(Engine, CoreSpace__, Data)
  else if Assigned(On_Execute_P) then
      On_Execute_P(Engine, CoreSpace__, Data);
end;

constructor TZDB2_Th_CMD_Custom_Execute.Create(const ThEng_: TZDB2_Th_Queue);
begin
  inherited Create(ThEng_);
  On_Execute_C := nil;
  On_Execute_M := nil;
  On_Execute_P := nil;
  Data := nil;
  Init();
end;

procedure TZDB2_Th_CMD_Flush.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  CoreSpace__.Flush;
end;

constructor TZDB2_Th_CMD_Flush.Create(const ThEng_: TZDB2_Th_Queue);
begin
  inherited Create(ThEng_);
  Init();
end;

procedure TZDB2_Th_CMD_Rebuild_And_Get_Sequence_Table.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
begin
  R_ := TCMD_State.csDone;

  if not Engine.FCoreSpace_IOHnd.IsOnlyRead then
    begin
      // remove identifier
      if (PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier = C_Sequence_Table_Identifier) and
        CoreSpace__.Check(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID) then
        begin
          if not CoreSpace__.RemoveData(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, False) then
              R_ := TCMD_State.csError;
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;
    end;

  // rebuild identifier
  Table_Ptr^ := CoreSpace__.BuildTableID;
  State^ := R_;
end;

constructor TZDB2_Th_CMD_Rebuild_And_Get_Sequence_Table.Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle);
begin
  inherited Create(ThEng_);
  Table_Ptr := @Table_;
  Init();
end;

procedure TZDB2_Th_CMD_Get_And_Clean_Sequence_Table.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  Mem64: TMem64;
begin
  R_ := TCMD_State.csDone;
  if (PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier = C_Sequence_Table_Identifier) and
    CoreSpace__.Check(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID) then
    begin
      // read identifier
      Mem64 := TMem64.Create;
      if CoreSpace__.ReadData(Mem64, PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID) then
        begin
          SetLength(Table_Ptr^, Mem64.Size shr 2);
          if length(Table_Ptr^) > 0 then
              CopyPtr(Mem64.Memory, @Table_Ptr^[0], length(Table_Ptr^) shl 2);
          DisposeObject(Mem64);
        end
      else
          R_ := TCMD_State.csError;
      if not Engine.FCoreSpace_IOHnd.IsOnlyRead then
        begin
          // remove identifier
          if not CoreSpace__.RemoveData(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, False) then
              R_ := TCMD_State.csError;
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;
    end
  else
      Table_Ptr^ := CoreSpace__.BuildTableID;
  State^ := R_;
end;

constructor TZDB2_Th_CMD_Get_And_Clean_Sequence_Table.Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle);
begin
  inherited Create(ThEng_);
  Table_Ptr := @Table_;
  Init();
end;

procedure TZDB2_Th_CMD_Get_ID_Size_From_Sequence_Table.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  i: Integer;
begin
  R_ := TCMD_State.csDone;
  for i := Low(Table_Ptr^) to high(Table_Ptr^) do
      ID_Size_Buffer_Ptr^[i] := CoreSpace__.GetDataSize(Table_Ptr^[i]);
  State^ := R_;
end;

constructor TZDB2_Th_CMD_Get_ID_Size_From_Sequence_Table.Create(const ThEng_: TZDB2_Th_Queue; var Table_: TZDB2_BlockHandle; var ID_Size_Buffer: TSequence_Table_ID_Size_Buffer);
begin
  inherited Create(ThEng_);
  Table_Ptr := @Table_;
  SetLength(ID_Size_Buffer, length(Table_));
  ID_Size_Buffer_Ptr := @ID_Size_Buffer;
  Init();
end;

procedure TZDB2_Th_CMD_Flush_Backcall_Sequence_Table.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  Mem64: TMem64;
  i, j: Integer;
  Sequence_Table: TZDB2_BlockHandle;
begin
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
    begin
      State^ := TCMD_State.csError;
    end
  else
    begin
      R_ := TCMD_State.csDone;

      if (PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier = C_Sequence_Table_Identifier) and
        CoreSpace__.Check(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID) then
        begin
          // remove identifier
          if not CoreSpace__.RemoveData(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, False) then
              R_ := TCMD_State.csError;
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;

      SetLength(Sequence_Table, 0);
      if Assigned(OnEvent) then
          OnEvent(Engine, Sequence_Table);

      if length(Sequence_Table) > 0 then
        begin
          // save identifier
          Mem64 := TMem64.Create;
          Mem64.Mapping(@Sequence_Table[0], length(Sequence_Table) shl 2);
          PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier := C_Sequence_Table_Identifier;
          if not CoreSpace__.WriteData(Mem64, PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, True) then
              R_ := TCMD_State.csError;
          DisposeObject(Mem64);
          SetLength(Sequence_Table, 0);
        end
      else
        begin
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;
      State^ := R_;
    end;
end;

constructor TZDB2_Th_CMD_Flush_Backcall_Sequence_Table.Create(const ThEng_: TZDB2_Th_Queue; const OnEvent_: TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event);
begin
  inherited Create(ThEng_);
  OnEvent := OnEvent_;
  Init();
end;

procedure TZDB2_Th_CMD_Flush_Sequence_Table.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  Mem64: TMem64;
  i, j: Integer;
begin
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
    begin
      State^ := TCMD_State.csError;
    end
  else
    begin
      R_ := TCMD_State.csDone;

      if (PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier = C_Sequence_Table_Identifier) and
        CoreSpace__.Check(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID) then
        begin
          // remove identifier
          if not CoreSpace__.RemoveData(PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, False) then
              R_ := TCMD_State.csError;
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;

      if length(Table_Ptr^) > 0 then
        begin
          // save identifier
          Mem64 := TMem64.Create;
          Mem64.Mapping(@Table_Ptr^[0], length(Table_Ptr^) shl 2);
          PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.Identifier := C_Sequence_Table_Identifier;
          if not CoreSpace__.WriteData(Mem64, PSequence_Table_Head(@CoreSpace__.UserCustomHeader^[0])^.ID, True) then
              R_ := TCMD_State.csError;
          DisposeObject(Mem64);
        end
      else
        begin
          FillPtr(@CoreSpace__.UserCustomHeader^[0], SizeOf(TSequence_Table_Head), 0);
        end;
      State^ := R_;
    end;
  if AutoFree_Data then
    begin
      SetLength(Table_Ptr^, 0);
      Dispose(Table_Ptr);
    end;
end;

constructor TZDB2_Th_CMD_Flush_Sequence_Table.Create(const ThEng_: TZDB2_Th_Queue; const Table_: PZDB2_BlockHandle);
begin
  inherited Create(ThEng_);
  Table_Ptr := Table_;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Flush_External_Header.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  i, j: Integer;
begin
  if Engine.FCoreSpace_IOHnd.IsOnlyRead then
    begin
      State^ := TCMD_State.csError;
    end
  else
    begin
      R_ := TCMD_State.csDone;

      if (PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.Identifier = C_External_Header_Identifier) and
        CoreSpace__.Check(PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID) then
        begin
          // remove external header
          if not CoreSpace__.RemoveData(PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID, False) then
              R_ := TCMD_State.csError;
          FillPtr(@CoreSpace__.UserCustomHeader^[6], SizeOf(TExternal_Head), 0);
        end;

      if Header_Data.Size > 0 then
        begin
          // save external header
          PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.Identifier := C_External_Header_Identifier;
          if not CoreSpace__.WriteData(Header_Data, PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID, True) then
              R_ := TCMD_State.csError;
        end
      else
        begin
          FillPtr(@CoreSpace__.UserCustomHeader^[6], SizeOf(TExternal_Head), 0);
        end;
      State^ := R_;
    end;
  if AutoFree_Data then
    begin
      DisposeObject(Header_Data);
    end;
end;

constructor TZDB2_Th_CMD_Flush_External_Header.Create(const ThEng_: TZDB2_Th_Queue; const Header_Data_: TMem64);
begin
  inherited Create(ThEng_);
  Header_Data := Header_Data_;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Get_And_Reset_External_Header.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
begin
  R_ := TCMD_State.csDone;
  Header_Data.Clear;

  if (PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.Identifier = C_External_Header_Identifier) and
    CoreSpace__.Check(PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID) then
    begin
      // read identifier
      if not CoreSpace__.ReadData(Header_Data, PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID) then
        begin
          DoStatus('"%s" no found External Header.', [Engine.FDatabase_FileName.Text]);
        end;
      if not Engine.FCoreSpace_IOHnd.IsOnlyRead then
        begin
          // remove identifier
          if not CoreSpace__.RemoveData(PExternal_Head(@CoreSpace__.UserCustomHeader^[6])^.ID, False) then
              DoStatus('"%s" remove external header failed, safe exception, you can be ignored.', [Engine.FDatabase_FileName.Text]);
          FillPtr(@CoreSpace__.UserCustomHeader^[6], SizeOf(TExternal_Head), 0);
        end;
    end;

  State^ := R_;
end;

constructor TZDB2_Th_CMD_Get_And_Reset_External_Header.Create(const ThEng_: TZDB2_Th_Queue; const Header_Data_: TMem64);
begin
  inherited Create(ThEng_);
  Header_Data := Header_Data_;
  Init();
end;

procedure TZDB2_Th_CMD_Extract_To.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  R_: TCMD_State;
  i: Integer;
  Mem64: TMem64;
  tmp_inst: TZDB2_Th_CMD_Append_From_Mem64;
  p: PZDB2_Th_CMD_ID_And_State;
begin
  R_ := TCMD_State.csDone;
  SetLength(Output_Ptr^, length(Input_Ptr^));

  if Aborted <> nil then
      Aborted^ := False;

  if length(Input_Ptr^) > 0 then
    begin
      for i := low(Input_Ptr^) to high(Input_Ptr^) do
        begin
          Mem64 := TMem64.Create;
          p := @Output_Ptr^[i];
          if CoreSpace__.ReadData(Mem64, Input_Ptr^[i]) then
            begin
              tmp_inst := TZDB2_Th_CMD_Append_From_Mem64.Create(Dest_Th_Engine, Mem64, p^.ID);
              tmp_inst.AutoFree_Data := True;
              tmp_inst.Ready(p^.State);
            end
          else
            begin
              R_ := TCMD_State.csError;
              p^.ID := -1;
              p^.State := TCMD_State.csError;
              DisposeObject(Mem64);
            end;
          // wait queue
          if Wait_Queue and (Max_Queue > 0) then
            while Dest_Th_Engine.QueueNum > Max_Queue do
                TCompute.Sleep(10);
          if Aborted <> nil then
            if Aborted^ then
              begin
                R_ := TCMD_State.csError;
                break;
              end;
        end;
    end;
  if Wait_Queue then
      Dest_Th_Engine.Wait_Queue();
  State^ := R_;
  if AutoFree_Data then
    begin
      SetLength(Input_Ptr^, 0);
      Dispose(Input_Ptr);
    end;
end;

constructor TZDB2_Th_CMD_Extract_To.Create(const ThEng_: TZDB2_Th_Queue;
  const Input_: PZDB2_BlockHandle;
  const Dest_Th_Engine_: TZDB2_Th_Queue; const Output_: PZDB2_Th_CMD_ID_And_State_Array);
begin
  inherited Create(ThEng_);
  Input_Ptr := Input_;
  Dest_Th_Engine := Dest_Th_Engine_;
  Output_Ptr := Output_;
  Max_Queue := 100;
  Wait_Queue := True;
  Aborted := nil;
  AutoFree_Data := False;
  Init();
end;

procedure TZDB2_Th_CMD_Format_Custom_Space.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  backup_: TZDB2_OnProgress;
begin
  backup_ := CoreSpace__.OnProgress;
  CoreSpace__.OnProgress := Param_OnProgress;
  try
    if not CoreSpace__.BuildSpace(Param_Space, Param_Block) then
        State^ := TCMD_State.csError;
  finally
      CoreSpace__.OnProgress := backup_;
  end;
end;

constructor TZDB2_Th_CMD_Format_Custom_Space.Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word; const OnProgress: TZDB2_OnProgress);
begin
  inherited Create(ThEng_);
  Param_Space := Space;
  Param_Block := Block;
  Param_OnProgress := OnProgress;
  Init();
end;

procedure TZDB2_Th_CMD_Fast_Format_Custom_Space.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if not CoreSpace__.Fast_BuildSpace(Param_Space, Param_Block) then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Fast_Format_Custom_Space.Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word);
begin
  inherited Create(ThEng_);
  Param_Space := Space;
  Param_Block := Block;
  Init();
end;

procedure TZDB2_Th_CMD_Append_Custom_Space.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
var
  backup_: TZDB2_OnProgress;
begin
  backup_ := CoreSpace__.OnProgress;
  CoreSpace__.OnProgress := Param_OnProgress;
  try
    if not CoreSpace__.AppendSpace(Param_Space, Param_Block) then
        State^ := TCMD_State.csError;
  finally
      CoreSpace__.OnProgress := backup_;
  end;
end;

constructor TZDB2_Th_CMD_Append_Custom_Space.Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word; const OnProgress: TZDB2_OnProgress);
begin
  inherited Create(ThEng_);
  Param_Space := Space;
  Param_Block := Block;
  Param_OnProgress := OnProgress;
  Init();
end;

procedure TZDB2_Th_CMD_Fast_Append_Custom_Space.DoExecute(CoreSpace__: TZDB2_Core_Space; State: PCMD_State);
begin
  if not CoreSpace__.Fast_AppendSpace(Param_Space, Param_Block) then
      State^ := TCMD_State.csError;
end;

constructor TZDB2_Th_CMD_Fast_Append_Custom_Space.Create(const ThEng_: TZDB2_Th_Queue; const Space: Int64; const Block: Word);
begin
  inherited Create(ThEng_);
  Param_Space := Space;
  Param_Block := Block;
  Init();
end;

procedure TZDB2_Th_CMD_Bridge_Mem64_And_State.CMD_Done;
begin
  if Assigned(OnResult_C) then
      OnResult_C(Mem64_And_State);
  if Assigned(OnResult_M) then
      OnResult_M(Mem64_And_State);
  if Assigned(OnResult_P) then
      OnResult_P(Mem64_And_State);
  DelayFreeObj(1.0, self);
end;

constructor TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
begin
  inherited Create;
  OnResult_C := nil;
  OnResult_M := nil;
  OnResult_P := nil;
  CMD := nil;
  Mem64_And_State.Mem64 := nil;
  Mem64_And_State.State := TCMD_State.csDefault;
end;

procedure TZDB2_Th_CMD_Bridge_Mem64_And_State.Init(CMD_: TZDB2_Th_CMD);
begin
  CMD := CMD_;
  CMD.OnDone := CMD_Done;
end;

procedure TZDB2_Th_CMD_Bridge_Mem64_And_State.Ready;
begin
  CMD.Ready(Mem64_And_State.State);
end;

procedure TZDB2_Th_CMD_Bridge_Stream_And_State.CMD_Done;
begin
  if Assigned(OnResult_C) then
      OnResult_C(Stream_And_State);
  if Assigned(OnResult_M) then
      OnResult_M(Stream_And_State);
  if Assigned(OnResult_P) then
      OnResult_P(Stream_And_State);
  DelayFreeObj(1.0, self);
end;

constructor TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
begin
  inherited Create;
  OnResult_C := nil;
  OnResult_M := nil;
  OnResult_P := nil;
  CMD := nil;
  Stream_And_State.Stream := nil;
  Stream_And_State.State := TCMD_State.csDefault;
end;

procedure TZDB2_Th_CMD_Bridge_Stream_And_State.Init(CMD_: TZDB2_Th_CMD);
begin
  CMD := CMD_;
  CMD.OnDone := CMD_Done;
end;

procedure TZDB2_Th_CMD_Bridge_Stream_And_State.Ready;
begin
  CMD.Ready(Stream_And_State.State);
end;

procedure TZDB2_Th_CMD_Bridge_ID_And_State.CMD_Done;
begin
  if Assigned(OnResult_C) then
      OnResult_C(ID_And_State);
  if Assigned(OnResult_M) then
      OnResult_M(ID_And_State);
  if Assigned(OnResult_P) then
      OnResult_P(ID_And_State);
  DelayFreeObj(1.0, self);
end;

constructor TZDB2_Th_CMD_Bridge_ID_And_State.Create;
begin
  inherited Create;
  OnResult_C := nil;
  OnResult_M := nil;
  OnResult_P := nil;
  CMD := nil;
  ID_And_State.ID := -1;
  ID_And_State.State := TCMD_State.csDefault;
end;

procedure TZDB2_Th_CMD_Bridge_ID_And_State.Init(CMD_: TZDB2_Th_CMD);
begin
  CMD := CMD_;
  CMD.OnDone := CMD_Done;
end;

procedure TZDB2_Th_CMD_Bridge_ID_And_State.Ready;
begin
  CMD.Ready(ID_And_State.State);
end;

procedure TZDB2_Th_CMD_Bridge_State.CMD_Done;
begin
  if Assigned(OnResult_C) then
      OnResult_C(State);
  if Assigned(OnResult_M) then
      OnResult_M(State);
  if Assigned(OnResult_P) then
      OnResult_P(State);
  DelayFreeObj(1.0, self);
end;

constructor TZDB2_Th_CMD_Bridge_State.Create;
begin
  inherited Create;
  OnResult_C := nil;
  OnResult_M := nil;
  OnResult_P := nil;
  CMD := nil;
  State := TCMD_State.csDefault;
end;

procedure TZDB2_Th_CMD_Bridge_State.Init(CMD_: TZDB2_Th_CMD);
begin
  CMD := CMD_;
  CMD.OnDone := CMD_Done;
end;

procedure TZDB2_Th_CMD_Bridge_State.Ready;
begin
  CMD.Ready(State);
end;

procedure TZDB2_Th_Queue.Do_Th_Queue(ThSender: TCompute);
var
  LTK, Tmp_TK, L_State_TK: TTimeTick;
  CMD_: TZDB2_Th_CMD;
  Sleep__: Integer;
begin
  ThSender.Thread_Info := ClassName;

  CoreSpace__ := TZDB2_Core_Space.Create(@FCoreSpace_IOHnd);
  CoreSpace__.Cipher := FCoreSpace_Cipher;
  CoreSpace__.Mode := FCoreSpace_Mode;
  CoreSpace__.MaxCacheMemory := FCoreSpace_CacheMemory;
  CoreSpace__.AutoCloseIOHnd := True;
  CoreSpace__.OnNoSpace := Do_No_Space;
  if umlFileSize(FCoreSpace_IOHnd) > 0 then
    if not CoreSpace__.Open then
      begin
        try
            CoreSpace__.Free;
        except
        end;
        FCMD_Execute_Thread_Is_Runing := False;
        FCMD_Execute_Thread_Is_Exit := True;
        exit;
      end;

  FCMD_Execute_Thread_Is_Runing := True;
  FCMD_Execute_Thread_Is_Exit := False;

  LTK := GetTimeTick();
  L_State_TK := LTK;
  while FCMD_Execute_Thread_Is_Runing do
    begin
      if FCMD_Queue.Num > 0 then
        begin
          CMD_ := FCMD_Queue.First^.Data;
          try
            if CMD_ <> nil then // check exception
                CMD_.Execute();
          except
          end;

          try
              FCMD_Queue.Next();
          except
          end;

          LTK := GetTimeTick();
          if FCMD_Queue.Num > 0 then
              Sleep__ := 0
          else
              Sleep__ := 1;
        end
      else
        begin
          Tmp_TK := GetTimeTick() - LTK;
          if Tmp_TK > 5000 then
              Sleep__ := 100
          else if Tmp_TK > 1000 then
              Sleep__ := 10
          else
              Sleep__ := 1;
        end;

      if GetTimeTick() - L_State_TK > 1000 then
        begin
          if FCoreSpace_IOHnd.Handle is TSafe_Flush_Stream then
            begin
              FFragment_Buffer_Num := TSafe_Flush_Stream(FCoreSpace_IOHnd.Handle).Fragment_Space.Num;
              FFragment_Buffer_Memory := TSafe_Flush_Stream(FCoreSpace_IOHnd.Handle).Fragment_Space.Fragment_Memory;
            end;
          L_State_TK := GetTimeTick();
        end;
      FCoreSpace_State.V := CoreSpace__.State^;
      FLast_Modification := CoreSpace__.Last_Modification;
      FIs_Modification := CoreSpace__.Is_Modification;
      FCoreSpace_File_Size := FCoreSpace_IOHnd.Size;
      FCoreSpace_BlockCount := CoreSpace__.BlockCount;
      if Sleep__ > 0 then
          TCompute.Sleep(Sleep__);
    end;

  DisposeObjectAndNil(CoreSpace__);
  FCMD_Execute_Thread_Is_Runing := False;
  FCMD_Execute_Thread_Is_Exit := True;
end;

procedure TZDB2_Th_Queue.Do_Free_CMD(var p: TZDB2_Th_CMD);
begin
  DisposeObjectAndNil(p);
end;

procedure TZDB2_Th_Queue.Do_No_Space(Trigger: TZDB2_Core_Space; Siz_: Int64; var retry: Boolean);
begin
  if FCoreSpace_Auto_Append_Space and ((FCoreSpace_Max_File_Size <= 0) or (FCoreSpace_Max_File_Size < FCoreSpace_File_Size + FCoreSpace_Delta)) then
    begin
      if FCoreSpace_Fast_Append_Space then
          retry := Trigger.Fast_AppendSpace(FCoreSpace_Delta, CoreSpace_BlockSize)
      else
          retry := Trigger.AppendSpace(FCoreSpace_Delta, CoreSpace_BlockSize);
    end
  else
      retry := False;
end;

procedure TZDB2_Th_Queue.Inc_Queue_Wirte_IO_Size(siz: Int64);
begin
  FQueue_Write_IO_Size.UnLock(FQueue_Write_IO_Size.LockP^ + siz);
end;

procedure TZDB2_Th_Queue.Dec_Queue_Wirte_IO_Size(siz: Int64);
begin
  FQueue_Write_IO_Size.UnLock(FQueue_Write_IO_Size.LockP^ - siz);
end;

class function TZDB2_Th_Queue.CheckStream(Stream_: TCore_Stream; Cipher_: IZDB2_Cipher): Boolean;
begin
  Result := TZDB2_Core_Space.CheckStream(Stream_, Cipher_);
end;

constructor TZDB2_Th_Queue.Create(Mode_: TZDB2_SpaceMode; CacheMemory_: Int64;
  Stream_: TCore_Stream; AutoFree_, OnlyRead_: Boolean; Delta_: Int64; BlockSize_: Word; Cipher_: IZDB2_Cipher);
begin
  inherited Create;
  FInstance_Pool_Ptr := ZDB2_Th_Queue_Instance_Pool__.Add(self);
  FCMD_Queue := TZDB2_Th_CMD_Queue.Create;
  FCMD_Queue.OnFree := Do_Free_CMD;
  FCMD_Execute_Thread_Is_Runing := False;
  FCMD_Execute_Thread_Is_Exit := False;
  FCoreSpace_Fast_Append_Space := True;
  FCoreSpace_Max_File_Size := 0;
  FCoreSpace_Auto_Append_Space := True;
  FCoreSpace_Mode := Mode_;
  FCoreSpace_CacheMemory := CacheMemory_;
  FCoreSpace_Delta := Delta_;
  CoreSpace_BlockSize := BlockSize_;
  FCoreSpace_Cipher := Cipher_;
  InitIOHnd(FCoreSpace_IOHnd);
  umlFileCreateAsStream(Stream_, FCoreSpace_IOHnd, OnlyRead_);
  FCoreSpace_IOHnd.AutoFree := AutoFree_;
  CoreSpace__ := nil;

  // init db state
  FCoreSpace_State := TZDB2_Atom_SpaceState.Create();
  FLast_Modification := GetTimeTick;
  FIs_Modification := False;
  FCoreSpace_File_Size := FCoreSpace_IOHnd.Size;
  FCoreSpace_BlockCount := 0;
  FIs_OnlyRead := OnlyRead_;
  FIs_Memory_Database := (Stream_ is TMS64) or (Stream_ is TCore_MemoryStream);
  FIs_File_Database := (Stream_ is TCore_FileStream) or (Stream_ is TReliableFileStream) or (Stream_ is TSafe_Flush_Stream);
  if Stream_ is TCore_FileStream then
      FDatabase_FileName := TCore_FileStream(Stream_).FileName
  else if Stream_ is TReliableFileStream then
      FDatabase_FileName := TReliableFileStream(Stream_).FileName
  else if Stream_ is TSafe_Flush_Stream then
      FDatabase_FileName := TSafe_Flush_Stream(Stream_).FileName
  else
      FDatabase_FileName := '';
  FFragment_Buffer_Num := 0;
  FFragment_Buffer_Memory := 0;
  FQueue_Write_IO_Size := TAtomInt64.Create(0);

  // thread
  TCompute.RunM(nil, nil, Do_Th_Queue);
  while not FCMD_Execute_Thread_Is_Runing do
      TCompute.Sleep(1);
end;

destructor TZDB2_Th_Queue.Destroy;
var
  tmp: TCMD_State;
begin
  ZDB2_Th_Queue_Instance_Pool__.Remove_P(FInstance_Pool_Ptr);
  Async_Flush;
  TZDB2_Th_CMD_Exit.Create(self).Ready(tmp);
  while not FCMD_Execute_Thread_Is_Exit do
      TCompute.Sleep(1);
  FCMD_Queue.Free;
  DisposeObject(FCoreSpace_State);
  FQueue_Write_IO_Size.Free;
  inherited Destroy;
end;

function TZDB2_Th_Queue.QueueNum: NativeInt;
begin
  if FCMD_Queue <> nil then
      Result := FCMD_Queue.Num
  else
      Result := 0;
end;

function TZDB2_Th_Queue.CoreSpace_Size: Int64;
begin
  with FCoreSpace_State.Lock do
      Result := Physics - FreeSpace;
  FCoreSpace_State.UnLock;
end;

function TZDB2_Th_Queue.CoreSpace_Physics_Size: Int64;
begin
  with FCoreSpace_State.Lock do
      Result := Physics;
  FCoreSpace_State.UnLock;
end;

function TZDB2_Th_Queue.CoreSpace_Free_Space_Size: Int64;
begin
  with FCoreSpace_State.Lock do
      Result := FreeSpace;
  FCoreSpace_State.UnLock;
end;

procedure TZDB2_Th_Queue.Wait_Queue;
begin
  while QueueNum > 0 do
      TCompute.Sleep(1);
end;

function TZDB2_Th_Queue.Sync_Get_Block_Data(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_Block_As_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset, Block_Read_Size).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64): Boolean;
var
  inst_: TZDB2_Th_CMD_Modify_Block_From_Mem64;
  tmp: TCMD_State;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  inst_ := TZDB2_Th_CMD_Modify_Block_From_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset);
  inst_.AutoFree_Data := False;
  inst_.Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_GetData(Mem64: TMem64; ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_Data_As_Mem64.Create(self, Mem64, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_SetData(Mem64: TMem64; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  if ID < 0 then
      exit(Sync_Append(Mem64, ID));
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  TZDB2_Th_CMD_Set_Data_From_Mem64.Create(self, Mem64, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append(Mem64: TMem64; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_GetData(Stream: TCore_Stream; ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_Data_As_Stream.Create(self, Stream, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Get_Position_Data_As_Stream(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(self, Stream, ID, Begin_Position, Read_Size).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_SetData(Stream: TCore_Stream; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  if ID < 0 then
      exit(Sync_Append(Stream, ID));
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  TZDB2_Th_CMD_Set_Data_From_Stream.Create(self, Stream, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append(Stream: TCore_Stream; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_SetData_From_Combine_Memory(const Arry: TMS64_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  if ID < 0 then
      exit(Sync_Append_From_Combine_Memory(Arry, ID));
  with TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append_From_Combine_Memory(const Arry: TMS64_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  with TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_SetData_From_Combine_Memory(const Arry: TMem64_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  if ID < 0 then
      exit(Sync_Append_From_Combine_Memory(Arry, ID));
  with TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append_From_Combine_Memory(const Arry: TMem64_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  with TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_SetData_From_Combine_Stream(const Arry: TStream_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  if ID < 0 then
      exit(Sync_Append_From_Combine_Stream(Arry, ID));
  with TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append_From_Combine_Stream(const Arry: TStream_Array; var ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  with TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, ID) do
    begin
      Inc_Queue_Wirte_IO_Size(Arry_Size);
      Ready(tmp);
    end;
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Remove(ID: Integer): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Remove.Create(self, ID).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Flush(): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Flush.Create(self).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_NOP(): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_NOP.Create(self, nil).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Rebuild_And_Get_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Rebuild_And_Get_Sequence_Table.Create(self, Table_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Get_And_Clean_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_And_Clean_Sequence_Table.Create(self, Table_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Get_ID_Size_From_Sequence_Table(var Table_: TZDB2_BlockHandle; var ID_Size_Buffer: TSequence_Table_ID_Size_Buffer): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_ID_Size_From_Sequence_Table.Create(self, Table_, ID_Size_Buffer).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Flush_Sequence_Table(var Table_: TZDB2_BlockHandle): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Flush_Sequence_Table.Create(self, @Table_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Flush_Sequence_Table(L: TZDB2_ID_List): Boolean;
var
  Table_: TZDB2_BlockHandle;
begin
  Table_ := TZDB2_Core_Space.Get_Handle(L);
  Result := Sync_Flush_Sequence_Table(Table_);
  SetLength(Table_, 0);
end;

function TZDB2_Th_Queue.Sync_Flush_Sequence_Table(L: TZDB2_ID_Pool): Boolean;
var
  Table_: TZDB2_BlockHandle;
begin
  Table_ := TZDB2_Core_Space.Get_Handle(L);
  Result := Sync_Flush_Sequence_Table(Table_);
  SetLength(Table_, 0);
end;

function TZDB2_Th_Queue.Sync_Flush_External_Header(Header_Data: TMem64): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Flush_External_Header.Create(self, Header_Data).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Get_And_Reset_External_Header(Header_Data: TMem64): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Get_And_Reset_External_Header.Create(self, Header_Data).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Extract_To(var Input_: TZDB2_BlockHandle;
  const Dest_Th_Engine_: TZDB2_Th_Queue; var Output_: TZDB2_Th_CMD_ID_And_State_Array): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Extract_To.Create(self, @Input_, Dest_Th_Engine_, @Output_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Extract_To(var Input_: TZDB2_BlockHandle; const Dest_Th_Engine_: TZDB2_Th_Queue; var Output_: TZDB2_Th_CMD_ID_And_State_Array; Aborted: PBoolean): Boolean;
var
  inst_: TZDB2_Th_CMD_Extract_To;
  tmp: TCMD_State;
begin
  inst_ := TZDB2_Th_CMD_Extract_To.Create(self, @Input_, Dest_Th_Engine_, @Output_);
  inst_.Aborted := Aborted;
  inst_.Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Extract_To_Stream(var Input_: TZDB2_BlockHandle; const Dest: TCore_Stream; const Cipher_: IZDB2_Cipher): Integer;
var
  th: TZDB2_Th_Queue;
  Output_: TZDB2_Th_CMD_ID_And_State_Array;
  i: Integer;
  tmp: TZDB2_ID_Pool;
begin
  Result := 0;
  th := TZDB2_Th_Queue.Create(FCoreSpace_Mode, FCoreSpace_CacheMemory, Dest, False, False, FCoreSpace_Delta, CoreSpace_BlockSize, Cipher_);
  th.Sync_Format_Custom_Space(umlMax(CoreSpace_Size, FCoreSpace_Delta), CoreSpace_BlockSize, nil);
  if Sync_Extract_To(Input_, th, Output_) then
    begin
      tmp := TZDB2_ID_Pool.Create;
      for i := 0 to length(Output_) - 1 do
        begin
          if Output_[i].State = TCMD_State.csDone then
              tmp.Add(Output_[i].ID);
        end;
      SetLength(Output_, 0);
      Result := tmp.Num;
      th.Sync_Flush_Sequence_Table(tmp);
      DisposeObject(tmp);
    end;
  DisposeObject(th);
end;

function TZDB2_Th_Queue.Sync_Extract_To_File(var Input_: TZDB2_BlockHandle; const Dest: U_String; const Cipher_: IZDB2_Cipher): Integer;
var
  fs: TCore_FileStream;
  th: TZDB2_Th_Queue;
  Output_: TZDB2_Th_CMD_ID_And_State_Array;
  i: Integer;
  tmp: TZDB2_ID_Pool;
begin
  Result := 0;
  try
    fs := TCore_FileStream.Create(Dest, fmCreate);
    th := TZDB2_Th_Queue.Create(FCoreSpace_Mode, FCoreSpace_CacheMemory, fs, True, False, FCoreSpace_Delta, CoreSpace_BlockSize, Cipher_);
    th.Sync_Format_Custom_Space(umlMax(CoreSpace_Size, FCoreSpace_Delta), CoreSpace_BlockSize, nil);
    if Sync_Extract_To(Input_, th, Output_) then
      begin
        tmp := TZDB2_ID_Pool.Create;
        for i := 0 to length(Output_) - 1 do
          begin
            if Output_[i].State = TCMD_State.csDone then
                tmp.Add(Output_[i].ID);
          end;
        SetLength(Output_, 0);
        Result := tmp.Num;
        th.Sync_Flush_Sequence_Table(tmp);
        DisposeObject(tmp);
      end;
    DisposeObject(th);
  except
  end;
end;

function TZDB2_Th_Queue.Sync_Extract_To_Queue_Engine_And_Copy_Sequence_Table(var Input_: TZDB2_BlockHandle; const Dest_Th_Engine_: TZDB2_Th_Queue; Aborted: PBoolean): Integer;
var
  Output_: TZDB2_Th_CMD_ID_And_State_Array;
  i: Integer;
  tmp: TZDB2_ID_Pool;
begin
  Result := 0;
  try
    if Sync_Extract_To(Input_, Dest_Th_Engine_, Output_, Aborted) then
      begin
        tmp := TZDB2_ID_Pool.Create;
        for i := 0 to length(Output_) - 1 do
          begin
            if Output_[i].State = TCMD_State.csDone then
                tmp.Add(Output_[i].ID);
          end;
        SetLength(Output_, 0);
        Result := tmp.Num;
        Dest_Th_Engine_.Sync_Flush_Sequence_Table(tmp);
        DisposeObject(tmp);
      end;
  except
  end;
end;

function TZDB2_Th_Queue.Sync_Format_Custom_Space(const Space_: Int64; const Block_: Word; const OnProgress_: TZDB2_OnProgress): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Format_Custom_Space.Create(self, Space_, Block_, OnProgress_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Fast_Format_Custom_Space(const Space_: Int64; const Block_: Word): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Fast_Format_Custom_Space.Create(self, Space_, Block_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Append_Custom_Space(const Space_: Int64; const Block_: Word; const OnProgress_: TZDB2_OnProgress): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Append_Custom_Space.Create(self, Space_, Block_, OnProgress_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

function TZDB2_Th_Queue.Sync_Fast_Append_Custom_Space(const Space_: Int64; const Block_: Word): Boolean;
var
  tmp: TCMD_State;
begin
  TZDB2_Th_CMD_Fast_Append_Custom_Space.Create(self, Space_, Block_).Ready(tmp);
  while tmp = TCMD_State.csDefault do
      TCompute.Sleep(1);
  Result := tmp = TCMD_State.csDone;
end;

procedure TZDB2_Th_Queue.Async_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Modify_Block_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Modify_Block_From_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Modify_Block(ID, Block_Index, Block_Offset: Integer; Mem64: TMem64; AutoFree_Data: Boolean; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Modify_Block_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  inst_ := TZDB2_Th_CMD_Modify_Block_From_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_GetData_AsMem64(ID: Integer; Mem64: TMem64; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Get_Data_As_Mem64;
begin
  inst_ := TZDB2_Th_CMD_Get_Data_As_Mem64.Create(self, Mem64, ID);
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_GetData_AsStream(ID: Integer; Stream: TCore_Stream; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Get_Data_As_Stream;
begin
  inst_ := TZDB2_Th_CMD_Get_Data_As_Stream.Create(self, Stream, ID);
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_Get_Position_Data_As_Stream(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Get_Position_Data_As_Stream;
begin
  inst_ := TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(self, Stream, ID, Begin_Position, Read_Size);
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_SetData(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append(Mem64, AutoFree_Data);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append(Mem64: TMem64; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append(Mem64: TMem64; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Append_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  inst_ := TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, ID^);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_SetData(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Stream;
begin
  if ID < 0 then
    begin
      Async_Append(Stream, AutoFree_Data);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append(Stream: TCore_Stream; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Stream;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Append_From_Stream;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  inst_ := TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, ID^);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory(Arry, AutoFree_Data);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_MemoryStream64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Append_From_Combine_MemoryStream64;
begin
  inst_ := TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, ID^);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory(Arry, AutoFree_Data);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Append_From_Combine_Mem64;
begin
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, ID^);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Stream(Arry, AutoFree_Data);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Stream(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: PInteger; State: PCMD_State);
var
  inst_: TZDB2_Th_CMD_Append_From_Combine_Stream;
begin
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, ID^);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  inst_.Ready(State^);
end;

procedure TZDB2_Th_Queue.Async_Remove(ID: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Remove;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Remove.Create(self, tmp.ID_And_State.ID);
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush;
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.Init(TZDB2_Th_CMD_Flush.Create(self));
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_NOP();
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.Init(TZDB2_Th_CMD_NOP.Create(self, nil));
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_NOP(var NOP_Num_: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.Init(TZDB2_Th_CMD_NOP.Create(self, @NOP_Num_));
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_INC(var Inc_Num: Integer);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.Init(TZDB2_Th_CMD_INC.Create(self, @Inc_Num));
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Execute_C(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst: TZDB2_Th_CMD_Custom_Execute;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst := TZDB2_Th_CMD_Custom_Execute.Create(self);
  inst.Data := Data;
  inst.On_Execute_C := On_Execute;
  tmp.Init(inst);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Execute_M(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst: TZDB2_Th_CMD_Custom_Execute;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst := TZDB2_Th_CMD_Custom_Execute.Create(self);
  inst.Data := Data;
  inst.On_Execute_M := On_Execute;
  tmp.Init(inst);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Execute_P(Data: Pointer; On_Execute: TOn_ZDB2_Th_CMD_Custom_Execute_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst: TZDB2_Th_CMD_Custom_Execute;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst := TZDB2_Th_CMD_Custom_Execute.Create(self);
  inst.Data := Data;
  inst.On_Execute_P := On_Execute;
  tmp.Init(inst);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table(const Table_: TZDB2_BlockHandle);
var
  Table_Ptr: PZDB2_BlockHandle;
  i: Integer;
  inst_: TZDB2_Th_CMD_Flush_Sequence_Table;
  tmp: TZDB2_Th_CMD_Bridge_State;
begin
  New(Table_Ptr);
  SetLength(Table_Ptr^, length(Table_));
  for i := 0 to length(Table_) - 1 do
      Table_Ptr^[i] := Table_[i];
  inst_ := TZDB2_Th_CMD_Flush_Sequence_Table.Create(self, Table_Ptr);
  inst_.AutoFree_Data := True;
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table(const L: TZDB2_ID_List);
begin
  Async_Flush_Sequence_Table(TZDB2_Core_Space.Get_Handle(L));
end;

procedure TZDB2_Th_Queue.Async_Flush_External_Header(Header_Data: TMem64; AutoFree_Data: Boolean);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst: TZDB2_Th_CMD_Flush_External_Header;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst := TZDB2_Th_CMD_Flush_External_Header.Create(self, Header_Data);
  inst.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Format_Custom_Space(const Space_: Int64; const Block_: Word);
var
  tmp: TZDB2_Th_CMD_Bridge_State;
  inst_: TZDB2_Th_CMD_Format_Custom_Space;
begin
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  inst_ := TZDB2_Th_CMD_Format_Custom_Space.Create(self, Space_, Block_, nil);
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Fast_Format_Custom_Space(const Space_: Int64; const Block_: Word);
var
  tmp: TZDB2_Th_CMD_Bridge_State;
  inst_: TZDB2_Th_CMD_Fast_Format_Custom_Space;
begin
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  inst_ := TZDB2_Th_CMD_Fast_Format_Custom_Space.Create(self, Space_, Block_);
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_Custom_Space(const Space_: Int64; const Block_: Word);
var
  tmp: TZDB2_Th_CMD_Bridge_State;
  inst_: TZDB2_Th_CMD_Append_Custom_Space;
begin
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  inst_ := TZDB2_Th_CMD_Append_Custom_Space.Create(self, Space_, Block_, nil);
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Fast_Append_Custom_Space(const Space_: Int64; const Block_: Word);
var
  tmp: TZDB2_Th_CMD_Bridge_State;
  inst_: TZDB2_Th_CMD_Fast_Append_Custom_Space;
begin
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  inst_ := TZDB2_Th_CMD_Fast_Append_Custom_Space.Create(self, Space_, Block_);
  tmp.Init(inst_);
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Block_Data_AsMem64_C(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Block_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Block_As_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset, Block_Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Block_Data_AsMem64_M(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Block_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Block_As_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset, Block_Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Block_Data_AsMem64_P(Mem64: TMem64; ID, Block_Index, Block_Offset, Block_Read_Size: Integer; OnResult: TOn_Mem64_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Block_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Block_As_Mem64.Create(self, Mem64, ID, Block_Index, Block_Offset, Block_Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Position_Data_As_Stream_C(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Position_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(self, Stream, ID, Begin_Position, Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Position_Data_As_Stream_M(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Position_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(self, Stream, ID, Begin_Position, Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Get_Position_Data_As_Stream_P(Stream: TCore_Stream; ID: Integer; Begin_Position, Read_Size: Int64; OnResult: TOn_Stream_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Position_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Position_Data_As_Stream.Create(self, Stream, ID, Begin_Position, Read_Size);
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsMem64_C(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Mem64.Create(self, tmp.Mem64_And_State.Mem64, ID);
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsMem64_M(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Mem64.Create(self, tmp.Mem64_And_State.Mem64, ID);
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsMem64_P(ID: Integer; Mem64: TMem64; OnResult: TOn_Mem64_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_Mem64_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_Mem64_And_State.Create;
  tmp.Mem64_And_State.Mem64 := Mem64;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Mem64.Create(self, tmp.Mem64_And_State.Mem64, ID);
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsStream_C(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Stream.Create(self, tmp.Stream_And_State.Stream, ID);
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsStream_M(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Stream.Create(self, tmp.Stream_And_State.Stream, ID);
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_GetData_AsStream_P(ID: Integer; Stream: TCore_Stream; OnResult: TOn_Stream_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_Stream_And_State;
  inst_: TZDB2_Th_CMD_Get_Data_As_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_Stream_And_State.Create;
  tmp.Stream_And_State.Stream := Stream;
  inst_ := TZDB2_Th_CMD_Get_Data_As_Stream.Create(self, tmp.Stream_And_State.Stream, ID);
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_C(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_C(Mem64, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_M(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_M(Mem64, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_P(Mem64: TMem64; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_P(Mem64, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_C(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_M(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_P(Mem64: TMem64; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Mem64;
begin
  Inc_Queue_Wirte_IO_Size(Mem64.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Mem64.Create(self, Mem64, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_C(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_C(Stream, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_M(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_M(Stream, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_P(Stream: TCore_Stream; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_P(Stream, AutoFree_Data, OnResult);
      exit;
    end;
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_C(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Stream;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_M(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Stream;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_P(Stream: TCore_Stream; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Stream;
begin
  Inc_Queue_Wirte_IO_Size(Stream.Size);
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Stream.Create(self, Stream, tmp.ID_And_State.ID);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_C(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_C(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_M(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_M(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_P(const Arry: TMS64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_P(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_C(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_MemoryStream64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_M(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_MemoryStream64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_P(const Arry: TMS64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_MemoryStream64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_MemoryStream64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_C(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_C(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_M(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_M(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Memory_P(const Arry: TMem64_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Mem64;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Memory_P(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_C(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_M(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Memory_P(const Arry: TMem64_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Mem64;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Mem64.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Stream_C(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Stream_C(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Stream_M(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Stream_M(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_SetData_From_Combine_Stream_P(const Arry: TStream_Array; AutoFree_Data: Boolean; ID: Integer; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Set_Data_From_Combine_Stream;
begin
  if ID < 0 then
    begin
      Async_Append_From_Combine_Stream_P(Arry, AutoFree_Data, OnResult);
      exit;
    end;
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.ID_And_State.ID := ID;
  inst_ := TZDB2_Th_CMD_Set_Data_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Stream_C(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_C);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Stream_M(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_M);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Append_From_Combine_Stream_P(const Arry: TStream_Array; AutoFree_Data: Boolean; OnResult: TOn_ID_And_State_Event_P);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
  inst_: TZDB2_Th_CMD_Append_From_Combine_Stream;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  inst_ := TZDB2_Th_CMD_Append_From_Combine_Stream.Create(self, Arry, tmp.ID_And_State.ID);
  Inc_Queue_Wirte_IO_Size(inst_.Arry_Size);
  inst_.AutoFree_Data := AutoFree_Data;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Backcall_Sequence_Table(const OnEvent_: TOn_ZDB2_Th_CMD_Flush_Backcall_Sequence_Table_Event);
var
  tmp: TZDB2_Th_CMD_Bridge_ID_And_State;
begin
  tmp := TZDB2_Th_CMD_Bridge_ID_And_State.Create;
  tmp.Init(TZDB2_Th_CMD_Flush_Backcall_Sequence_Table.Create(self, OnEvent_));
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_C(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_C);
var
  Table_Ptr: PZDB2_BlockHandle;
  i: Integer;
  inst_: TZDB2_Th_CMD_Flush_Sequence_Table;
  tmp: TZDB2_Th_CMD_Bridge_State;
begin
  New(Table_Ptr);
  SetLength(Table_Ptr^, length(Table_));
  for i := 0 to length(Table_) - 1 do
      Table_Ptr^[i] := Table_[i];
  inst_ := TZDB2_Th_CMD_Flush_Sequence_Table.Create(self, Table_Ptr);
  inst_.AutoFree_Data := True;
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  tmp.Init(inst_);
  tmp.OnResult_C := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_C(const L: TZDB2_ID_List; OnResult: TOn_State_Event_C);
begin
  Async_Flush_Sequence_Table_C(TZDB2_Core_Space.Get_Handle(L), OnResult);
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_M(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_M);
var
  Table_Ptr: PZDB2_BlockHandle;
  i: Integer;
  inst_: TZDB2_Th_CMD_Flush_Sequence_Table;
  tmp: TZDB2_Th_CMD_Bridge_State;
begin
  New(Table_Ptr);
  SetLength(Table_Ptr^, length(Table_));
  for i := 0 to length(Table_) - 1 do
      Table_Ptr^[i] := Table_[i];
  inst_ := TZDB2_Th_CMD_Flush_Sequence_Table.Create(self, Table_Ptr);
  inst_.AutoFree_Data := True;
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  tmp.Init(inst_);
  tmp.OnResult_M := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_M(const L: TZDB2_ID_List; OnResult: TOn_State_Event_M);
begin
  Async_Flush_Sequence_Table_M(TZDB2_Core_Space.Get_Handle(L), OnResult);
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_P(const Table_: TZDB2_BlockHandle; OnResult: TOn_State_Event_P);
var
  Table_Ptr: PZDB2_BlockHandle;
  i: Integer;
  inst_: TZDB2_Th_CMD_Flush_Sequence_Table;
  tmp: TZDB2_Th_CMD_Bridge_State;
begin
  New(Table_Ptr);
  SetLength(Table_Ptr^, length(Table_));
  for i := 0 to length(Table_) - 1 do
      Table_Ptr^[i] := Table_[i];
  inst_ := TZDB2_Th_CMD_Flush_Sequence_Table.Create(self, Table_Ptr);
  inst_.AutoFree_Data := True;
  tmp := TZDB2_Th_CMD_Bridge_State.Create;
  tmp.Init(inst_);
  tmp.OnResult_P := OnResult;
  tmp.Ready;
end;

procedure TZDB2_Th_Queue.Async_Flush_Sequence_Table_P(const L: TZDB2_ID_List; OnResult: TOn_State_Event_P);
begin
  Async_Flush_Sequence_Table_P(TZDB2_Core_Space.Get_Handle(L), OnResult);
end;

class function TZDB2_Th_Queue.Get_Handle(var buff: TZDB2_Th_CMD_ID_And_State_Array): TZDB2_BlockHandle;
var
  i: Integer;
begin
  SetLength(Result, length(buff));
  for i := low(buff) to high(buff) do
      Result[i] := buff[i].ID;
end;

class procedure TZDB2_Th_Queue.Test;
var
  tmp_inst1: TZDB2_Th_Queue;
  tmp_inst2: TZDB2_Th_Queue;
  tmp_inst3: TZDB2_Th_Queue;
  tmp_inst4: TZDB2_Th_Queue;
  Mem64: TMS64;
  tmp: TMem64;
  Arry: TZDB2_BlockHandle;
  Output_: TZDB2_Th_CMD_ID_And_State_Array;
  i: Integer;
  tmp_extract_stream: TMS64;
begin
  tmp_inst1 := TZDB2_Th_Queue.Create(smNormal, 64 * 1024 * 1024, TMS64.CustomCreate(1024 * 1024), True, False, 1024 * 1024, 4096, nil);
  tmp_inst2 := TZDB2_Th_Queue.Create(smNormal, 64 * 1024 * 1024, TMS64.CustomCreate(1024 * 1024), True, False, 1024 * 1024, 1000, nil);
  tmp_inst3 := TZDB2_Th_Queue.Create(smNormal, 64 * 1024 * 1024, TMS64.CustomCreate(1024 * 1024), True, False, 1024 * 1024, 500, nil);

  Mem64 := TMS64.Create;
  Mem64.Size := 3992;
  tmp_extract_stream := TMS64.CustomCreate(1024 * 1024);

  SetLength(Arry, 8);
  for i := low(Arry) to high(Arry) do
    begin
      MT19937Rand32(MaxInt, Mem64.Memory, Mem64.Size shr 2);
      tmp_inst1.Sync_Append(Mem64, Arry[i]);
      DoStatus(umlMD5ToStr(Mem64.ToMD5));
    end;
  tmp_inst1.Sync_Flush_Sequence_Table(Arry);

  DoStatus('');

  tmp_inst1.Sync_Extract_To(Arry, tmp_inst2, Output_);
  Arry := Get_Handle(Output_);
  tmp_inst2.Sync_Flush_Sequence_Table(Arry);
  SetLength(Arry, 0);
  tmp_inst2.Sync_Get_And_Clean_Sequence_Table(Arry);
  tmp_inst2.Sync_Flush_Sequence_Table(Arry);
  for i := low(Arry) to high(Arry) do
    begin
      Mem64.Clear;
      tmp_inst2.Sync_GetData(Mem64, Arry[i]);
      DoStatus(umlMD5ToStr(Mem64.ToMD5));
    end;

  DoStatus('');

  tmp_inst2.Sync_Extract_To(Arry, tmp_inst3, Output_);
  Arry := Get_Handle(Output_);
  tmp_inst3.Sync_Flush_Sequence_Table(Arry);
  tmp_inst3.Sync_Extract_To_Stream(Arry, tmp_extract_stream, nil);

  tmp_inst4 := TZDB2_Th_Queue.Create(smNormal, 64 * 1024 * 1024, tmp_extract_stream, True, False, 1024 * 1024, 500, nil);
  tmp_inst4.Sync_Get_And_Clean_Sequence_Table(Arry);

  for i := low(Arry) to high(Arry) do
    begin
      Mem64.Clear;
      tmp_inst4.Sync_GetData(Mem64, Arry[i]);
      DoStatus(umlMD5ToStr(Mem64.ToMD5));

      // test block modify
      tmp := TMem64.Create;
      tmp.WriteBytes([$FF, $FF, $FF, $FF, $FF]);
      tmp_inst4.Sync_Modify_Block(Arry[i], 0, 0, tmp);
      DisposeObject(tmp);
      tmp_inst4.Sync_GetData(Mem64, Arry[i]);
    end;

  Wait_DoStatus_Queue();

  Mem64.Free;
  tmp_inst1.Free;
  tmp_inst2.Free;
  tmp_inst3.Free;
  tmp_inst4.Free;
  SetLength(Arry, 0);
end;

initialization

ZDB2_Th_Queue_Instance_Pool__ := TZDB2_Th_Queue_Instance_Pool.Create;

finalization

DisposeObjectAndNil(ZDB2_Th_Queue_Instance_Pool__);

end.
 
