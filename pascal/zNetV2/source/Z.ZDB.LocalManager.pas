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
(*
  *  Z.ZDB.LocalManager – Local Database Manager with Query Pipelines
  *
  *  This unit provides a high-level local database management layer built on top
  *  of the legacy ZDB engine (Z.ZDB.Engine). It extends the basic TDBStore with
  *  named database instances (TZDBLMStore) and introduces an asynchronous query
  *  pipeline mechanism (TZDBPipeline) for filtering, transforming, and copying
  *  data between databases or to fragment buffers.
  *
  *  The core components are:
  *
  *  - TZDBLMStore: an extended TDBStore that holds a unique name and tracks the
  *    last modification time. All database instances are managed by a central
  *    TZDBLocalManager.
  *
  *  - TZDBPipeline: an asynchronous query task that iterates over a source
  *    database, applies user-defined filter callbacks (C, M, or P style), and
  *    writes accepted records to an output database and/or a fragment buffer.
  *    Pipelines support progress reporting, pause/play, timeouts, and result
  *    limits. They are automatically destroyed after a configurable delay.
  *
  *  - TZDBLocalManager: the main orchestrator. It owns a pool of named databases
  *    (both file-based and in-memory) and a pool of active pipelines. It provides
  *    methods to create/open/close databases, launch queries, copy or compress
  *    databases (with position transformation tracking), and manage fragment
  *    data exchange. It also implements IDBStoreBaseNotify to receive database
  *    modification events and ICadencerProgressInterface for periodic progress
  *    updates and auto‑flush.
  *
  *  Key Features:
  *  - Multi-database management with file or in-memory storage.
  *  - Asynchronous queries with custom filters and result accumulation.
  *  - Fragment encoding/decoding for efficient data transfer between databases.
  *  - Database copy and compress operations with transformation callbacks.
  *  - Integration with a cadencer for timed maintenance (flush, cache cleanup).
  *  - Support for user data (Values, DataEng, UserPointer, etc.) in pipelines.
  *
  *  Dependencies:
  *  This unit directly depends on:
  *  - Z.ZDB.Engine (TDBStore, TQueryState, etc.) – the underlying object store.
  *  - Z.ZDB.ItemStream_LIB – for item stream handling.
  *  - Z.Cadencer, Z.Notify – for progress and delayed execution.
  *  - Other Z.Core utilities (Z.PascalStrings, Z.UnicodeMixedLib, Z.DFE, etc.)
  *    and standard System.SysUtils, Variants.
  *
  *  Architecture & Data Flow:
  *  1. The manager loads all .OX database files from a root directory on start.
  *  2. Applications can create or open databases by name.
  *  3. A query pipeline is created via QueryDB* methods. It attaches to a source
  *     database and an output database (or memory DB). The pipeline runs in the
  *     background using TDBStore's asynchronous query mechanism (TQueryTask).
  *  4. For each record, the pipeline calls the user's filter callback. If the
  *     record is accepted (Allowed = True), it is written to the output DB and
  *     optionally appended to a fragment buffer.
  *  5. Fragment buffers are flushed periodically (FragmentWaitTime) or when the
  *     query ends, and are passed to the notification interface for external
  *     processing (e.g., sending over network or storing).
  *  6. Copy and compress operations are implemented as special pipelines that
  *     copy all records and generate position transformation maps.
  *  7. Upon completion, the pipeline is delayed-freed, and the output DB can be
  *     automatically destroyed or kept.
  *
  *  Historical Context & Modern Alternatives:
  *  This unit is part of the legacy ZDB stack, which is based on a linked-list
  *  field structure and iterative traversal. It works well for moderate-sized
  *  datasets (up to millions of records) where full scans are acceptable.
  *  However, for high-performance computing, large-scale storage, or random
  *  access patterns, the newer ZDB2 family (Z.ZDB2, Z.ZDB2.Thread.) is
  *  strongly recommended. ZDB2 offers block-oriented storage, parallel I/O,
  *  encryption, and multiple loading modes (full, block, positional) that are
  *  better suited for modern hardware and scalability requirements.
  *
  *  Usage:
  *  - Create a TZDBLocalManager instance, optionally set RootPath.
  *  - Use InitDB/InitMemoryDB to open or create databases.
  *  - Post data using PostData or InsertData methods.
  *  - Launch queries using QueryDB, QueryDBC, QueryDBM, or QueryDBP with
  *    appropriate callback types.
  *  - The manager's Progress method should be called periodically (e.g., in
  *    a main loop) to drive the cadencer and pipeline progress.
  *  - Use the notification interface (IZDBLocalManagerNotify) to receive
  *    fragment data and query completion events.
  *  - Copy and compress databases using CopyDB and CompressDB, which return
  *    pipelines that trigger transformation notifications.
  *
  *  This unit is a convenient tool for local data management in applications
  *  that do not require extreme scalability, but for new projects, migrating to
  *  ZDB2 is advised for future‑proof performance.
*)
unit Z.ZDB.LocalManager;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses SysUtils, Variants,
  Z.Core, Z.PascalStrings, Z.UPascalStrings,
  Z.ListEngine, Z.UnicodeMixedLib, Z.DFE, Z.MemoryStream, Z.TextDataEngine,
  Z.Json,
  Z.Status, Z.Cadencer, Z.Notify,
  Z.Cipher, Z.ZDB.Engine, Z.ZDB.ItemStream_LIB;

type
  // Extended database store with a name and last modification time.
  TZDBLMStore = class(TDBStore)
  protected
    FName: SystemString; // Unique name of this database – set by TZDBLocalManager when creating/opening.
    FLastModifyTime: TTimeTick; // Timestamp of last modification – updated by DoInsertData/DoAddData/DoModifyData/DoDeleteData.
    procedure DoCreateInit; override; // Initializes FName to '' and FLastModifyTime to current time.
  public
    property Name: SystemString read FName; // Name used to reference this database in the manager.
  end;

  TZDBLocalManager = class;
  TZDBPipeline = class;

  // Callback type for filtering data during a pipeline query (C-style).
  TZDBPipelineFilter_C = procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean);
  // Callback type for filtering data during a pipeline query (M-style).
  TZDBPipelineFilter_M = procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean) of object;

  // Callback type for pipeline completion (C-style).
  TZDBPipelineDone_C = procedure(dPipe: TZDBPipeline);
  // Callback type for pipeline completion (M-style).
  TZDBPipelineDone_M = procedure(dPipe: TZDBPipeline) of object;

{$IFDEF FPC}
  // Callback type for filtering data during a pipeline query (P-style – nested).
  TZDBPipelineFilter_P = procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean) is nested;
  // Callback type for pipeline completion (P-style – nested).
  TZDBPipelineDone_P = procedure(dPipe: TZDBPipeline) is nested;
{$ELSE FPC}
  // Callback type for filtering data during a pipeline query (reference).
  TZDBPipelineFilter_P = reference to procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean);
  // Callback type for pipeline completion (reference).
  TZDBPipelineDone_P = reference to procedure(dPipe: TZDBPipeline);
{$ENDIF FPC}

  // Record storing a transformation from an original store position to a new position.
  TZDBStorePosTransform = record
    OriginPos, NewPos: Int64;
  end;

  PZDBStorePosTransform = ^TZDBStorePosTransform;
  TZDBStorePosTransformArray = array of TZDBStorePosTransform; // Array of transformations.
  PZDBStorePosTransformArray = ^TZDBStorePosTransformArray;

  // Notification callback for transformation completion.
  TZDBStorePosTransformNotify = procedure(const Data: Pointer; const TransformBuff: PZDBStorePosTransformArray) of object;

  // TZDBPipeline represents an asynchronous query pipeline that reads from a source database,
  // applies filters, and writes results to an output database and/or fragment buffer.
  TZDBPipeline = class(TCore_InterfacedObject_Intermediate)
  private
    FQueryCounter: Int64; // Number of items processed (compared) – incremented in Query().
    FCurrentFragmentTime: TTimeTick; // Accumulated time since last fragment flush – updated in Query().
    FFragmentBuffer: TMS64; // Buffer for fragment data – created in InitOptions.
    FActivted: Boolean; // True while pipeline is active (not yet done) – set True in constructor, set False in QueryDone.
    FQueryTask: TQueryTask; // Background query task – assigned by QueryDB methods.
    FPerformaceCounter: NativeInt; // Counter for performance measurement – incremented in Query().
    FLastPerformaceTime: TTimeTick; // Last time performance was computed – updated in Query().
    FQueryCounterOfPerSec: Double; // Queries per second – computed in Query().
    FRealTimePostFragmentData: Boolean; // If True, fragment data is sent immediately when available – set by user (default True).
    FQueryResultCounter: Int64; // Number of items that passed the filter – incremented in Query() when allowed.
    FStorePosTransformList: TCore_List; // List of PZDBStorePosTransform records – added by AddStorePosTransform during copy/compress.

    procedure Query(var qState: TQueryState); // Internal query callback for each item.
    procedure QueryDone(); // Called when the query task finishes.
    procedure WriteToOutput(dbEng: TDBStore; StorePos: Int64; ID: Cardinal); // Writes a data item to output DB and/or fragment buffer.
    procedure PostFragmentData(forcePost: Boolean); // Flushes the fragment buffer to the owner's notification handler.
  public
    Owner: TZDBLocalManager; // Owning local manager – set by constructor.
    SourceDB: TZDBLMStore; // Source database being queried – set by constructor.
    OutputDB: TZDBLMStore; // Destination database for results – set by constructor.
    SourceDBName, OutputDBName, PipelineName: SystemString; // Names – set by constructor.

    // Query options – can be set by user before starting.
    WriteResultToOutputDB: Boolean; // If True, write accepted items to OutputDB – default True.
    AutoDestroyDB: Boolean; // If True, OutputDB is destroyed when pipeline ends – default True.
    FragmentWaitTime: Double; // Time (seconds) between fragment flushes – default 0.5.
    MaxWaitTime: Double; // Maximum query time before abort (0 = unlimited) – default 0.
    MaxQueryCompare: Int64; // Maximum number of items to compare before abort (0 = unlimited) – default 0.
    MaxQueryResult: Int64; // Maximum number of accepted results before abort (0 = unlimited) – default 0.
    QueryDoneFreeDelayTime: Double; // Delay (seconds) before freeing the pipeline after completion – default 60.
    WriteFragmentBuffer: Boolean; // If True, write accepted items to fragment buffer – default True.

    // User-defined callbacks.
    OnDataFilter_C: TZDBPipelineFilter_C; // C-style filter – set by user.
    OnDataFilter_M: TZDBPipelineFilter_M; // M-style filter – set by user.
    OnDataDone_C: TZDBPipelineDone_C; // C-style done callback – set by user.
    OnDataDone_M: TZDBPipelineDone_M; // M-style done callback – set by user.
    OnDataFilter_P: TZDBPipelineFilter_P; // P-style filter – set by user.
    OnDataDone_P: TZDBPipelineDone_P; // P-style done callback – set by user.
    OnStorePosTransform: TZDBStorePosTransformNotify; // Transformation notification – set by user.

    // User data fields.
    Values: THashVariantList; // Variant hash list for user data – created in InitOptions.
    DataEng: TDFE; // DFE object for user data – created in InitOptions.
    UserPointer: Pointer; // Free pointer – set by user.
    UserObject: TCore_Object; // Free object – set by user.
    UserVariant: Variant; // Free variant – set by user.

  public
    procedure InitOptions; // Sets default option values and initializes buffers.

    constructor Create(InMem: Boolean; Owner_: TZDBLocalManager; sourDBName_, PipelineName_, OutDBName_: SystemString); virtual;
    destructor Destroy; override;
    procedure Progress(deltaTime: Double); virtual; // Called periodically by the manager.

    procedure ClearStorePosTransform; // Clears all stored transformations.
    procedure AddStorePosTransform(OriginPos, NewPos: Int64); // Adds a transformation entry.
    function StorePosTransformCount: Integer; // Number of transformations.
    function GetStorePosTransform(const index: Integer): PZDBStorePosTransform; // Returns a pointer to a transformation entry.
    property StorePosTransform[const index: Integer]: PZDBStorePosTransform read GetStorePosTransform; // Returns a pointer to a transformation entry.

    procedure stop; // Stops the query task.
    procedure Pause; // Pauses the query task.
    procedure Play; // Resumes a paused query task.
    function Paused: Boolean; // Returns True if the query task is paused.
    function QueryConsumTime: Double; // Returns elapsed time of the query.
    property Activted: Boolean read FActivted; // True while pipeline is active.
    property QueryCounterOfPerSec: Double read FQueryCounterOfPerSec; // Current query rate.
    property RealTimePostFragmentData: Boolean read FRealTimePostFragmentData write FRealTimePostFragmentData; // Set by user.
    property QueryCounter: Int64 read FQueryCounter; // Total items compared.
    property QueryResultCounter: Int64 read FQueryResultCounter; // Total items accepted.
  end;

  TZDBPipelineClass = class of TZDBPipeline; // Meta-class for creating pipeline instances.

  // Notification interface for the local manager to report events.
  IZDBLocalManagerNotify = interface
    procedure CreateQuery(pipe: TZDBPipeline);
    procedure QueryFragmentData(pipe: TZDBPipeline; FragmentSource: TMS64);
    procedure QueryDone(pipe: TZDBPipeline);
    procedure OpenDB(ActiveDB: TZDBLMStore);
    procedure CreateDB(ActiveDB: TZDBLMStore);
    procedure CloseDB(ActiveDB: TZDBLMStore);
    procedure InsertData(Sender: TZDBLMStore; InsertPos: Int64; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64);
    procedure AddData(Sender: TZDBLMStore; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64);
    procedure ModifyData(Sender: TZDBLMStore; const StorePos: Int64; buff: TCore_Stream);
    procedure DeleteData(Sender: TZDBLMStore; const StorePos: Int64);
  end;

  // Record for notifying compression completion.
  TCompressDoneNotify = record
    OnStorePosTransform: TZDBStorePosTransformNotify; // User callback.
    Data: Pointer; // User data.
    TransformBuff: TZDBStorePosTransformArray; // Transformation array.
  end;

  PCompressDoneNotify = ^TCompressDoneNotify;

  // Main local database manager.
  TZDBLocalManager = class(TCore_InterfacedObject_Intermediate, IDBStoreBaseNotify, ICadencerProgressInterface)
  protected
    FRootPath: SystemString; // Root path for file-based databases – set by SetRootPath.
    FDBPool: THashObjectList; // Pool of named TZDBLMStore instances – keyed by database name – created by constructor.
    FQueryPipelinePool: THashObjectList; // Pool of named TZDBPipeline instances – keyed by pipeline name – created by constructor.
    FQueryPipelineList: TCore_ListForObj; // List of active pipelines (for iteration) – created by constructor.
    FTaskSeed: Cardinal; // Seed for generating unique task names – incremented in GenerateNewTaskName.
    FCadencerEng: TCadencer; // Timer engine for progress updates – created by constructor.
    FProgressPost: TN_Progress_Tool; // Tool for delayed execution – created by constructor.
    FPipelineClass: TZDBPipelineClass; // Class type for creating pipelines – set by user (default TZDBPipeline).
    FNotifyIntf: IZDBLocalManagerNotify; // Notification interface – set by user.

  protected
    // Implement IDBStoreBaseNotify.
    procedure DoInsertData(Sender: TDBStore; InsertPos: Int64; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64); virtual;
    procedure DoAddData(Sender: TDBStore; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64); virtual;
    procedure DoModifyData(Sender: TDBStore; const StorePos: Int64; buff: TCore_Stream); virtual;
    procedure DoDeleteData(Sender: TDBStore; const StorePos: Int64); virtual;

    // ICadencerProgressInterface.
    procedure ZDBEngProgress(const Name: PSystemString; Obj: TCore_Object);
    procedure CadencerProgress(const deltaTime, newTime: Double);

    // Internal pipeline event handlers.
    procedure DoQueryFragmentData(pipe: TZDBPipeline; FragmentSour: TMS64); virtual;
    procedure DoQueryDone(pipe: TZDBPipeline); virtual;
    procedure DelayFreePipe(Sender: TN_Post_Execute); virtual;
    procedure DoQueryCopy(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean);
    procedure DoCopyDone(dPipe: TZDBPipeline);
    procedure DoCompressDone(dPipe: TZDBPipeline);
    procedure DelayReplaceDB(Sender: TN_Post_Execute);
  public
    constructor Create;
    destructor Destroy; override;

    property PipelineClass: TZDBPipelineClass read FPipelineClass write FPipelineClass;
    property NotifyIntf: IZDBLocalManagerNotify read FNotifyIntf write FNotifyIntf;
    property NotifyInterface: IZDBLocalManagerNotify read FNotifyIntf write FNotifyIntf;
    property OnNotify: IZDBLocalManagerNotify read FNotifyIntf write FNotifyIntf;

    procedure Clear; // Closes and frees all databases and pipelines.
    procedure LoadDB(ReadOnly: Boolean); // Loads all .OX files from RootPath.
    procedure SetRootPath(const Value: SystemString);
    property RootPath: SystemString read FRootPath write SetRootPath;

    procedure Progress; virtual; // Advances the cadencer.
    property ProgressPost: TN_Progress_Tool read FProgressPost;

    // Database management.
    function InitDB(dataBaseName_: SystemString): TZDBLMStore; overload;
    function InitDB(dataBaseName_: SystemString; ReadOnly: Boolean): TZDBLMStore; overload;
    function InitNewDB(dataBaseName_: SystemString): TZDBLMStore;
    function InitMemoryDB(dataBaseName_: SystemString): TZDBLMStore;
    procedure CloseDB(dataBaseName_: SystemString);
    procedure CloseAndDeleteDB(dataBaseName_: SystemString);

    // Asynchronous copy and compress.
    function CopyDB(SourceDatabaseName_, DestDatabaseName_: SystemString): TZDBPipeline; overload;
    function CopyDB(SourceDatabaseName_, DestDatabaseName_: SystemString; const UserData: Pointer; const OnStorePosTransform: TZDBStorePosTransformNotify): TZDBPipeline; overload;
    function CompressDB(dataBaseName_: SystemString): TZDBPipeline; overload;
    function CompressDB(dataBaseName_: SystemString; const UserData: Pointer; const OnStorePosTransform: TZDBStorePosTransformNotify): TZDBPipeline; overload;

    procedure ReplaceDB(dataBaseName_, replaceN: SystemString); // Replaces a database with another after compression.
    procedure ResetDB(dataBaseName_: SystemString);
    procedure ResetData(dataBaseName_: SystemString); // Alias.

    // Cache and flush.
    procedure Recache; // Clears all caches in all databases.
    procedure Flush; // Forces all databases to update.

    // Container operations.
    function GenerateTaskName: SystemString; // Generates a unique name (e.g., 'Task1').
    function GenerateNewTaskName: SystemString; // Generates and increments seed.
    function GetPipeline(pipeName: SystemString): TZDBPipeline;
    function GetDB(dataBaseName_: SystemString): TZDBLMStore;
    function GetOrCreateDB(dataBaseName_: SystemString): TZDBLMStore;
    function GetDBName(dataBaseName_: SystemString): TZDBLMStore; // Alias to InitMemoryDB.
    property DBName[dataBaseName_: SystemString]: TZDBLMStore read GetDBName; default;
    property PipelineN[pipeName: SystemString]: TZDBPipeline read GetPipeline;
    property QueryPipelineList: TCore_ListForObj read FQueryPipelineList;
    function ExistsDB(dataBaseName_: SystemString): Boolean;
    function ExistsPipeline(pipeName: SystemString): Boolean;
    procedure StopPipeline(pipeName: SystemString);
    procedure GetPipeList(OutputList: TCore_ListForObj);
    procedure GetDBList(OutputList: TCore_ListForObj);
    function Busy(Database_: TZDBLMStore): Boolean; // Checks if a database is being used by any active pipeline.
    function CanDestroy(Database_: TZDBLMStore): Boolean; // Checks if a database can be safely destroyed.

    // Query creation methods – various overloads.
    function QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline; overload;

    function QueryDBC(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64;
      OnDataFilter_C: TZDBPipelineFilter_C; OnDataDone_C: TZDBPipelineDone_C): TZDBPipeline; overload;

    function QueryDBM(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64;
      OnDataFilter_M: TZDBPipelineFilter_M; OnDataDone_M: TZDBPipelineDone_M): TZDBPipeline; overload;

    function QueryDBP(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64;
      OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline; overload;

    function QueryDBP(DataEng: TDFE; UserObj: TCore_Object;
      WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64;
      OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline; overload;

    function QueryDBToMemory(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
      QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
      MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline; overload;

    function QueryDBToMemory(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
      FragmentWaitTime, MaxWaitTime: Double; MaxQueryResult: Int64): TZDBPipeline; overload;

    function QueryDBToMemoryP(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
      QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double; MaxQueryCompare, MaxQueryResult: Int64;
      OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline; overload;

    function QueryDBToFile(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
      FragmentWaitTime, MaxWaitTime: Double; MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline;

    // Fragment operations.
    function ReadDBItemToZDBFragment(dataBaseName_: SystemString; StorePos: Int64; DestStream: TMS64): Boolean;

    // Post/Insert/Delete/Get/Set operations.
    function PostData(dataBaseName_: SystemString; sourDBEng: TZDBLMStore; SourStorePos: Int64): Int64; overload;
    function PostData(dataBaseName_: SystemString; var qState: TQueryState): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: TCore_Stream; ID: Cardinal): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: TDFE): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: THashVariantList): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: THashStringList): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: TSectionTextData): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: TPascalString): Int64; overload;
    function PostData(dataBaseName_: SystemString; dSour: TZ_JsonObject): Int64; overload;

    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TCore_Stream; ID: Cardinal): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TDFE): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: THashVariantList): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: THashStringList): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TSectionTextData): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TPascalString): Int64; overload;
    function InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TZ_JsonObject): Int64; overload;

    procedure DeleteData(dataBaseName_: SystemString; StorePos: Int64);
    function GetData(dataBaseName_: SystemString; StorePos: Int64; ID: Cardinal): TDBCacheStream64;
    function SetData(dataBaseName_: SystemString; StorePos: Int64; dSour: TMS64): Boolean;

    class procedure Test_LM();
  end;

  // Callback types for fragment data processing (C, M, P).
  TFillQueryData_C = procedure(dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64);
  TFillQueryData_M = procedure(dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64) of object;
  TUserFillQueryData_C = procedure(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
    dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64);
  TUserFillQueryData_M = procedure(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
    dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64) of object;

{$IFDEF FPC}
  TFillQueryData_P = procedure(dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64) is nested;
  TUserFillQueryData_P = procedure(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
    dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64) is nested;
{$ELSE FPC}
  TFillQueryData_P = reference to procedure(dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64);
  TUserFillQueryData_P = reference to procedure(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
    dataBaseName_, pipeN: SystemString; StorePos: Int64; ID: Cardinal; DataSour: TMS64);
{$ENDIF FPC}

function GeneratePipeName(const sourDBName_, taskName: SystemString): SystemString;

// Fragment filling and storing.
procedure FillFragmentToZDB(DataSour: TMS64; Database_: TDBStore);

// Fragment source callback dispatchers.
procedure FillFragmentSourceC(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_C); overload;
procedure FillFragmentSourceM(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_M); overload;
procedure FillFragmentSourceP(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_P); overload;
procedure FillFragmentSourceC(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_C); overload;
procedure FillFragmentSourceM(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_M); overload;
procedure FillFragmentSourceP(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_P); overload;

// Fragment encoding/decoding.
function EncodeZDBFragment(Database_: TDBStore; StorePos: Int64; DestStream: TMS64): Boolean;
function DecodeZDBFragment(DataSour: TMS64; var dStorePos: Int64; var ID: Cardinal): TMS64; overload;
function DecodeZDBFragment(DataSour: TMS64): TMS64; overload;
function DecodeZDBNewFragment(DataSour: TMS64; var dStorePos: Int64; var ID: Cardinal): TMS64; overload;
function DecodeZDBNewFragment(DataSour: TMS64): TMS64; overload;

// Encrypt/decrypt a complete buffer with metadata.
function EncodeZDBBuff(const dataBaseName_: TPascalString; const ID: Cardinal; const StorePos: Int64;
  buff: Pointer; buffSiz: nativeUInt; var outputSiz: nativeUInt): Pointer;
procedure DecodeZDBBuff(buff: Pointer; buffSiz: nativeUInt;
  var dataBaseName_: TPascalString; var ID: Cardinal; var StorePos: Int64; var output: Pointer; var outputSiz: nativeUInt);

var
  ZDBLocalManager_SystemRootPath: SystemString; // Global default root path – initialized to current directory.

implementation

function GeneratePipeName(const sourDBName_, taskName: SystemString): SystemString;
begin
  Result := sourDBName_ + '.QueryPipe.' + taskName;
end;

procedure FillFragmentToZDB(DataSour: TMS64; Database_: TDBStore);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Cardinal_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Cardinal_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        Database_.AddData(m64, ID);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceC(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_C);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceM(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_M);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceP(dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TFillQueryData_P);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceC(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_C);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(UserPointer, UserObject, UserVariant, dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceM(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_M);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(UserPointer, UserObject, UserVariant, dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

procedure FillFragmentSourceP(UserPointer: Pointer; UserObject: TCore_Object; UserVariant: Variant;
  dataBaseName_, pipeN: SystemString; DataSour: TMS64; OnResult: TUserFillQueryData_P);
var
  StorePos, siz: Int64;
  ID: Cardinal;
  m64: TMS64;
begin
  if not Assigned(OnResult) then
      Exit;
  if DataSour.Size <= 0 then
      Exit;

  DataSour.Position := 0;

  m64 := TMS64.Create;
  while DataSour.Position < DataSour.Size do
    begin
      if DataSour.ReadPtr(@StorePos, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
          Break;
      if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
          Break;

      if DataSour.Position + siz > DataSour.Size then
          Break;

      try
        m64.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
        OnResult(UserPointer, UserObject, UserVariant, dataBaseName_, pipeN, StorePos, ID, m64);
      except
      end;

      DataSour.Position := DataSour.Position + siz;
    end;
  DisposeObject(m64);
end;

function EncodeZDBFragment(Database_: TDBStore; StorePos: Int64; DestStream: TMS64): Boolean;
var
  itmStream: TDBCacheStream64;
  siz: Int64;
  ID: Cardinal;
begin
  Result := False;
  itmStream := Database_.GetCacheStream(StorePos);
  if itmStream <> nil then
    begin
      siz := itmStream.Size;
      ID := itmStream.CacheID;
      DestStream.Position := DestStream.Size;
      DestStream.WritePtr(@StorePos, C_Int64_Size);
      DestStream.WritePtr(@siz, C_Int64_Size);
      DestStream.WritePtr(@ID, C_Cardinal_Size);
      DestStream.CopyFrom(itmStream, siz);

      DisposeObject(itmStream);
      Result := True;
    end;
end;

function DecodeZDBFragment(DataSour: TMS64; var dStorePos: Int64; var ID: Cardinal): TMS64;
var
  siz: Int64;
begin
  Result := nil;
  if DataSour.ReadPtr(@dStorePos, C_Int64_Size) <> C_Int64_Size then
      Exit;
  if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
      Exit;
  if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
      Exit;

  if DataSour.Position + siz > DataSour.Size then
      Exit;

  Result := TMS64.Create;
  Result.SetPointerWithProtectedMode(DataSour.PositionAsPtr(DataSour.Position), siz);
end;

function DecodeZDBFragment(DataSour: TMS64): TMS64;
var
  dStorePos: Int64;
  ID: Cardinal;
begin
  Result := DecodeZDBFragment(DataSour, dStorePos, ID);
end;

function DecodeZDBNewFragment(DataSour: TMS64; var dStorePos: Int64; var ID: Cardinal): TMS64;
var
  siz: Int64;
begin
  Result := nil;
  if DataSour.ReadPtr(@dStorePos, C_Int64_Size) <> C_Int64_Size then
      Exit;
  if DataSour.ReadPtr(@siz, C_Int64_Size) <> C_Int64_Size then
      Exit;
  if DataSour.ReadPtr(@ID, C_Cardinal_Size) <> C_Cardinal_Size then
      Exit;

  if DataSour.Position + siz > DataSour.Size then
      Exit;

  Result := TMS64.Create;
  Result.CopyFrom(DataSour, siz);
  Result.Position := 0;
end;

function DecodeZDBNewFragment(DataSour: TMS64): TMS64;
var
  dStorePos: Int64;
  ID: Cardinal;
begin
  Result := DecodeZDBNewFragment(DataSour, dStorePos, ID);
end;

function EncodeZDBBuff(const dataBaseName_: TPascalString; const ID: Cardinal; const StorePos: Int64;
  buff: Pointer; buffSiz: nativeUInt; var outputSiz: nativeUInt): Pointer;
var
  nb: TBytes;
  L: Word;
  p: PByteArray;
begin
  dataBaseName_.FastGetBytes(nb);
  L := length(nb);
  outputSiz := 2 + L + 4 + 8 + buffSiz;
  p := GetMemory(outputSiz);
  Result := p;
  PWORD(@p^[0])^ := L;
  CopyPtr(@nb[0], @p^[2], L);
  PCardinal(@(p^[2 + L]))^ := ID;
  PInt64(@(p^[2 + L + 4]))^ := StorePos;
  CopyPtr(buff, @p^[2 + L + 4 + 8], buffSiz);
end;

procedure DecodeZDBBuff(buff: Pointer; buffSiz: nativeUInt;
  var dataBaseName_: TPascalString; var ID: Cardinal; var StorePos: Int64; var output: Pointer; var outputSiz: nativeUInt);
var
  nb: TBytes;
  p: PByteArray;
begin
  p := buff;
  SetLength(nb, PWORD(@p^[0])^);
  CopyPtr(@p^[2], @nb[0], PWORD(@p^[0])^);
  dataBaseName_.Bytes := nb;
  ID := PCardinal(@(p^[2 + PWORD(@p^[0])^]))^;
  StorePos := PInt64(@(p^[2 + PWORD(@p^[0])^ + 4]))^;
  outputSiz := buffSiz - (2 + PWORD(@p^[0])^ + 4 + 8);
  output := @p^[2 + PWORD(@p^[0])^ + 4 + 8];
end;

procedure TZDBLMStore.DoCreateInit;
begin
  inherited DoCreateInit;
  FName := '';
  FLastModifyTime := GetTimeTick;
end;

procedure TZDBPipeline.Query(var qState: TQueryState);
var
  lastTime: TTimeTick;
  AlreadWrite: Boolean;
  Allowed: Boolean;

  procedure DoWrite;
  begin
    if AlreadWrite then
        Exit;

    WriteToOutput(qState.Eng, qState.StorePos, qState.ID);
    AlreadWrite := True;
    inc(FQueryResultCounter);
  end;

begin
  lastTime := GetTimeTick;
  inc(FPerformaceCounter);

  FActivted := True;

  AlreadWrite := False;

  Allowed := False;

  if OutputDB = nil then
      Exit;
  if SourceDB = nil then
      Exit;

  try
    if Assigned(OnDataFilter_C) then
        OnDataFilter_C(Self, qState, Allowed);

    if Allowed then
        DoWrite;
  except
  end;

  Allowed := False;
  try
    if Assigned(OnDataFilter_M) then
        OnDataFilter_M(Self, qState, Allowed);

    if Allowed then
        DoWrite;
  except
  end;

  Allowed := False;
  try
    if Assigned(OnDataFilter_P) then
        OnDataFilter_P(Self, qState, Allowed);

    if Allowed then
        DoWrite;
  except
  end;

  inc(FQueryCounter);

  // delay fragment
  FCurrentFragmentTime := FCurrentFragmentTime + qState.deltaTime;
  if (AlreadWrite) and (FCurrentFragmentTime >= Trunc(FragmentWaitTime * 1000)) then
    begin
      PostFragmentData(False);
      FCurrentFragmentTime := 0;
    end;

  // max query result
  if (MaxQueryResult > 0) and (FQueryResultCounter >= MaxQueryResult) then
    begin
      qState.Aborted := True;
      Exit;
    end;

  // max query compare
  if (MaxQueryCompare > 0) and (FQueryCounter >= MaxQueryCompare) then
    begin
      qState.Aborted := True;
      Exit;
    end;

  // max query wait
  if (MaxWaitTime > 0) and (qState.newTime >= Trunc(MaxWaitTime * 1000)) then
    begin
      qState.Aborted := True;
      Exit;
    end;

  if lastTime - FLastPerformaceTime > 1000 then
    begin
      try
        if FPerformaceCounter > 0 then
            FQueryCounterOfPerSec := FPerformaceCounter / ((lastTime - FLastPerformaceTime) * 0.001)
        else
            FQueryCounterOfPerSec := 0;
      except
          FQueryCounterOfPerSec := 0;
      end;
      FLastPerformaceTime := lastTime;
      FPerformaceCounter := 0;
    end;
end;

procedure TZDBPipeline.QueryDone();
begin
  PostFragmentData(True);

  try
    if Assigned(OnDataDone_C) then
        OnDataDone_C(Self);
  except
  end;

  try
    if Assigned(OnDataDone_M) then
        OnDataDone_M(Self);
  except
  end;

  try
    if Assigned(OnDataDone_P) then
        OnDataDone_P(Self);
  except
  end;

  try
      Owner.DoQueryDone(Self);
  except
  end;

  FActivted := False;
  FQueryTask := nil;

  FPerformaceCounter := 0;
  FLastPerformaceTime := GetTimeTick;
end;

procedure TZDBPipeline.WriteToOutput(dbEng: TDBStore; StorePos: Int64; ID: Cardinal);
var
  itmStream: TMS64;
  siz: Int64;
begin
  if (not WriteResultToOutputDB) and (not WriteFragmentBuffer) then
      Exit;

  itmStream := dbEng.GetCacheStream(StorePos, ID);

  if WriteResultToOutputDB then
    begin
      OutputDB.AddData(itmStream, ID);
    end;

  if WriteFragmentBuffer then
    begin
      itmStream.Position := 0;
      siz := itmStream.Size;
      FFragmentBuffer.Position := FFragmentBuffer.Size;
      FFragmentBuffer.WritePtr(@StorePos, C_Int64_Size);
      FFragmentBuffer.WritePtr(@siz, C_Int64_Size);
      FFragmentBuffer.WritePtr(@ID, C_Cardinal_Size);
      FFragmentBuffer.CopyFrom(itmStream, siz);
    end;
end;

procedure TZDBPipeline.PostFragmentData(forcePost: Boolean);
begin
  if (not forcePost) and (not FRealTimePostFragmentData) then
      Exit;
  if FFragmentBuffer.Size <= 0 then
      Exit;

  FFragmentBuffer.Position := 0;
  Owner.DoQueryFragmentData(Self, FFragmentBuffer);
  FFragmentBuffer.Clear;
end;

procedure TZDBPipeline.InitOptions;
begin
  FQueryCounter := 0;
  FCurrentFragmentTime := 0;
  FFragmentBuffer := TMS64.CustomCreate($FFFF);

  FActivted := True;
  FQueryTask := nil;
  FPerformaceCounter := 0;
  FLastPerformaceTime := GetTimeTick;
  FQueryCounterOfPerSec := 0;
  FRealTimePostFragmentData := True;
  FQueryResultCounter := 0;
  FStorePosTransformList := TCore_List.Create;

  // data query options
  WriteResultToOutputDB := True; // query result write to output
  AutoDestroyDB := True; // complete time destroy Database_
  FragmentWaitTime := 0.5; // fragment time,realtime send to client
  MaxWaitTime := 0; // max wait complete time,query to abort from out time
  MaxQueryCompare := 0; // max query compare
  MaxQueryResult := 0; // max query result
  QueryDoneFreeDelayTime := 60; // query done free delay time
  WriteFragmentBuffer := True; // write fragment

  OnDataFilter_C := nil;
  OnDataFilter_M := nil;
  OnDataFilter_P := nil;
  OnDataDone_C := nil;
  OnDataDone_M := nil;
  OnDataDone_P := nil;
  OnStorePosTransform := nil;

  Values := THashVariantList.CustomCreate($FF);
  DataEng := TDFE.Create;
  UserPointer := nil;
  UserObject := nil;
  UserVariant := Null;

  Owner.FQueryPipelinePool[PipelineName] := Self;
  Owner.FQueryPipelineList.Add(Self);
end;

constructor TZDBPipeline.Create(InMem: Boolean; Owner_: TZDBLocalManager; sourDBName_, PipelineName_, OutDBName_: SystemString);
begin
  inherited Create;
  Owner := Owner_;

  SourceDB := Owner.FDBPool[sourDBName_] as TZDBLMStore;

  PipelineName := PipelineName_;
  SourceDBName := sourDBName_;
  OutputDBName := OutDBName_;

  if InMem then
      OutputDB := Owner.InitMemoryDB(OutDBName_)
  else
      OutputDB := Owner.InitDB(OutDBName_, False);

  InitOptions;
end;

destructor TZDBPipeline.Destroy;
var
  fn: SystemString;
  i: Integer;
  pl: TZDBPipeline;
begin
  i := 0;
  while i < Owner.FQueryPipelineList.Count do
    begin
      if Owner.FQueryPipelineList[i] = Self then
          Owner.FQueryPipelineList.Delete(i)
      else
          inc(i);
    end;

  Owner.FQueryPipelinePool.Delete(PipelineName);

  try
    if (OutputDB <> nil) and (AutoDestroyDB) then
      begin
        for i := 0 to Owner.FQueryPipelineList.Count - 1 do
          begin
            pl := TZDBPipeline(Owner.FQueryPipelineList[i]);
            if pl.OutputDB = OutputDB then
                pl.OutputDB := nil;
            if pl.SourceDB = OutputDB then
                pl.SourceDB := nil;
          end;

        if OutputDB.IsMemoryMode then
          begin
            Owner.CloseDB(OutputDB.Name);
          end
        else
          begin
            Owner.CloseAndDeleteDB(OutputDB.Name);
          end;
      end;
  except
  end;

  DisposeObject([FFragmentBuffer, Values, DataEng]);

  for i := 0 to FStorePosTransformList.Count - 1 do
      Dispose(PZDBStorePosTransform(FStorePosTransformList[i]));
  DisposeObject(FStorePosTransformList);

  inherited Destroy;
end;

procedure TZDBPipeline.Progress(deltaTime: Double);
begin
end;

procedure TZDBPipeline.ClearStorePosTransform;
var
  i: Integer;
begin
  for i := 0 to FStorePosTransformList.Count - 1 do
      Dispose(PZDBStorePosTransform(FStorePosTransformList[i]));
  FStorePosTransformList.Clear;
end;

procedure TZDBPipeline.AddStorePosTransform(OriginPos, NewPos: Int64);
var
  p: PZDBStorePosTransform;
begin
  new(p);
  p^.OriginPos := OriginPos;
  p^.NewPos := NewPos;
  FStorePosTransformList.Add(p);
end;

function TZDBPipeline.StorePosTransformCount: Integer;
begin
  Result := FStorePosTransformList.Count;
end;

function TZDBPipeline.GetStorePosTransform(const index: Integer): PZDBStorePosTransform;
begin
  Result := PZDBStorePosTransform(FStorePosTransformList[index]);
end;

procedure TZDBPipeline.stop;
begin
  if FQueryTask <> nil then
      FQueryTask.stop;
end;

procedure TZDBPipeline.Pause;
begin
  if (FragmentWaitTime > 0) then
      PostFragmentData(True);
  if FQueryTask <> nil then
      FQueryTask.Pause;
end;

procedure TZDBPipeline.Play;
begin
  if FQueryTask <> nil then
      FQueryTask.Play;
end;

function TZDBPipeline.Paused: Boolean;
begin
  if FQueryTask <> nil then
      Result := FQueryTask.Paused
  else
      Result := False;
end;

function TZDBPipeline.QueryConsumTime: Double;
begin
  if FQueryTask <> nil then
      Result := FQueryTask.ConsumTime
  else
      Result := 0;
end;

procedure TZDBLocalManager.DoInsertData(Sender: TDBStore; InsertPos: Int64; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64);
begin
  TZDBLMStore(Sender).FLastModifyTime := GetTimeTick;
  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.InsertData(TZDBLMStore(Sender), InsertPos, buff, ID, CompletePos);
  except
  end;
end;

procedure TZDBLocalManager.DoAddData(Sender: TDBStore; buff: TCore_Stream; ID: Cardinal; CompletePos: Int64);
begin
  TZDBLMStore(Sender).FLastModifyTime := GetTimeTick;
  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.AddData(TZDBLMStore(Sender), buff, ID, CompletePos);
  except
  end;
end;

procedure TZDBLocalManager.DoModifyData(Sender: TDBStore; const StorePos: Int64; buff: TCore_Stream);
begin
  TZDBLMStore(Sender).FLastModifyTime := GetTimeTick;
  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.ModifyData(TZDBLMStore(Sender), StorePos, buff);
  except
  end;
end;

procedure TZDBLocalManager.DoDeleteData(Sender: TDBStore; const StorePos: Int64);
begin
  TZDBLMStore(Sender).FLastModifyTime := GetTimeTick;
  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.DeleteData(TZDBLMStore(Sender), StorePos);
  except
  end;
end;

procedure TZDBLocalManager.ZDBEngProgress(const Name: PSystemString; Obj: TCore_Object);
var
  Database_: TZDBLMStore;
begin
  if Obj = nil then
      Exit;

  Database_ := TZDBLMStore(Obj);
  if (Database_.DBEngine.Modification) and (GetTimeTick - Database_.FLastModifyTime > 1000) then
    begin
      Database_.Update;
      Database_.FLastModifyTime := GetTimeTick;
    end;
end;

procedure TZDBLocalManager.CadencerProgress(const deltaTime, newTime: Double);
var
  i: Integer;
begin
  FProgressPost.Progress(deltaTime);

  for i := 0 to FQueryPipelineList.Count - 1 do
    begin
      try
          TZDBPipeline(FQueryPipelineList[i]).Progress(deltaTime);
      except
      end;
    end;

  FDBPool.ProgressM(ZDBEngProgress);
end;

procedure TZDBLocalManager.DoQueryFragmentData(pipe: TZDBPipeline; FragmentSour: TMS64);
begin
  if not Assigned(FNotifyIntf) then
      Exit;

  FragmentSour.Position := 0;

  try
      FNotifyIntf.QueryFragmentData(pipe, FragmentSour);
  except
  end;
end;

procedure TZDBLocalManager.DoQueryDone(pipe: TZDBPipeline);
begin
  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.QueryDone(pipe);
  except
  end;

  with ProgressPost.PostExecuteM(False, pipe.QueryDoneFreeDelayTime, DelayFreePipe) do
    begin
      Data1 := pipe;
      Ready();
    end;
end;

procedure TZDBLocalManager.DelayFreePipe(Sender: TN_Post_Execute);
var
  i: Integer;
  sour, pl: TZDBPipeline;
begin
  sour := TZDBPipeline(Sender.Data1);

  if sour.AutoDestroyDB then
    for i := 0 to FQueryPipelineList.Count - 1 do
      begin
        pl := TZDBPipeline(FQueryPipelineList[i]);
        if (pl.SourceDB = sour.OutputDB) and (pl.Activted) then
          begin
            with ProgressPost.PostExecuteM(False, 1.0, DelayFreePipe) do
              begin
                Data1 := sour;
                Ready();
              end;
            Exit;
          end;
      end;

  DisposeObject(sour);
end;

procedure TZDBLocalManager.DoQueryCopy(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean);
var
  n: Int64;
begin
  n := PostData(dPipe.UserVariant, qState);
  dPipe.AddStorePosTransform(qState.StorePos, n);
  Allowed := False;
end;

procedure TZDBLocalManager.DoCopyDone(dPipe: TZDBPipeline);
var
  i: Integer;
  TransformBuff: TZDBStorePosTransformArray;
begin
  if Assigned(dPipe.OnStorePosTransform) then
    begin
      SetLength(TransformBuff, dPipe.FStorePosTransformList.Count);
      for i := 0 to dPipe.StorePosTransformCount - 1 do
          TransformBuff[i] := dPipe.StorePosTransform[i]^;

      dPipe.OnStorePosTransform(dPipe.UserPointer, @TransformBuff);
      SetLength(TransformBuff, 0);
    end;
end;

procedure TZDBLocalManager.DoCompressDone(dPipe: TZDBPipeline);
var
  SourceDatabaseName_: SystemString;
  replaceN: SystemString;
  i: Integer;
  Done_Ptr: PCompressDoneNotify;
begin
  Done_Ptr := nil;
  if Assigned(dPipe.OnStorePosTransform) then
    begin
      new(Done_Ptr);
      Done_Ptr^.OnStorePosTransform := dPipe.OnStorePosTransform;
      Done_Ptr^.Data := dPipe.UserPointer;
      SetLength(Done_Ptr^.TransformBuff, dPipe.FStorePosTransformList.Count);
      for i := 0 to dPipe.StorePosTransformCount - 1 do
          Done_Ptr^.TransformBuff[i] := dPipe.StorePosTransform[i]^;
    end;

  SourceDatabaseName_ := dPipe.SourceDB.Name;
  replaceN := dPipe.UserVariant;
  with ProgressPost.PostExecuteM(False, 2.0, DelayReplaceDB) do
    begin
      Data3 := SourceDatabaseName_;
      Data4 := replaceN;
      Data5 := Done_Ptr;
      Ready();
    end;
end;

procedure TZDBLocalManager.DelayReplaceDB(Sender: TN_Post_Execute);
var
  SourceDatabaseName_: SystemString;
  replaceN: SystemString;
  Done_Ptr: PCompressDoneNotify;
  sourDB: TZDBLMStore;
  pl: TZDBPipeline;
  i: Integer;
  dbBusy: Boolean;
begin
  SourceDatabaseName_ := Sender.Data3;
  replaceN := Sender.Data4;
  Done_Ptr := Sender.Data5;

  if not ExistsDB(SourceDatabaseName_) then
      Exit;
  if not ExistsDB(replaceN) then
      Exit;

  sourDB := DBName[SourceDatabaseName_];

  dbBusy := sourDB.QueryProcessing;

  if not dbBusy then
    for i := 0 to FQueryPipelineList.Count - 1 do
      if TZDBPipeline(FQueryPipelineList[i]).SourceDB = sourDB then
        begin
          dbBusy := True;
          Break;
        end;

  if dbBusy then
    begin
      with ProgressPost.PostExecuteM(False, 1.0, DelayReplaceDB) do
        begin
          Data3 := SourceDatabaseName_;
          Data4 := replaceN;
          Data5 := Done_Ptr;
          Ready();
        end;
      Exit;
    end;

  CloseAndDeleteDB(SourceDatabaseName_);

  if DBName[replaceN].RenameDB(SourceDatabaseName_ + '.OX') then
    begin
      CloseDB(replaceN);
      InitDB(SourceDatabaseName_, False);
    end;
  if Done_Ptr <> nil then
    begin
      if Assigned(Done_Ptr^.OnStorePosTransform) then
          Done_Ptr^.OnStorePosTransform(Done_Ptr^.Data, @Done_Ptr^.TransformBuff);
      SetLength(Done_Ptr^.TransformBuff, 0);
      Dispose(Done_Ptr);
    end;
end;

constructor TZDBLocalManager.Create;
begin
  inherited Create;
  FRootPath := ZDBLocalManager_SystemRootPath;
  FDBPool := THashObjectList.CustomCreate(True, 1024);
  FDBPool.AccessOptimization := False;

  FQueryPipelinePool := THashObjectList.CustomCreate(False, 1024);
  FQueryPipelinePool.AccessOptimization := False;

  FQueryPipelineList := TCore_ListForObj.Create;

  FTaskSeed := 1;
  FCadencerEng := TCadencer.Create;
  FCadencerEng.ProgressInterface := Self;
  FProgressPost := TN_Progress_Tool.Create;
  FPipelineClass := TZDBPipeline;
  FNotifyIntf := nil;
end;

destructor TZDBLocalManager.Destroy;
var
  lst: TCore_ListForObj;
  i: Integer;
begin
  Flush;

  FProgressPost.ResetPost;

  lst := TCore_ListForObj.Create;
  FDBPool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
      TZDBLMStore(lst[i]).StopAllQuery;
  DisposeObject(lst);

  lst := TCore_ListForObj.Create;
  FQueryPipelinePool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
      DisposeObject(lst[i]);
  DisposeObject(lst);

  DisposeObject([FDBPool, FQueryPipelinePool, FQueryPipelineList, FCadencerEng, FProgressPost]);
  inherited Destroy;
end;

procedure TZDBLocalManager.Clear;
var
  lst: TCore_ListForObj;
  i: Integer;
begin
  FProgressPost.ResetPost;

  lst := TCore_ListForObj.Create;
  FDBPool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
      TZDBLMStore(lst[i]).StopAllQuery;
  DisposeObject(lst);

  lst := TCore_ListForObj.Create;
  FQueryPipelinePool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
      DisposeObject(lst[i]);
  DisposeObject(lst);

  FDBPool.Clear;
end;

procedure TZDBLocalManager.LoadDB(ReadOnly: Boolean);
var
  Arr: U_StringArray;
  fn, n: SystemString;
begin
  Clear;
  Arr := umlGet_File_Full_Array(RootPath);
  for fn in Arr do
    begin
      n := umlGetFileName(fn);
      if not umlMultipleMatch(True, '*.CompressSwap.*', n) then
        if umlMultipleMatch(True, '*.OX', n) then
            InitDB(umlChangeFileExt(n, '').Text, ReadOnly);
    end;
  SetLength(Arr, 0);
end;

procedure TZDBLocalManager.SetRootPath(const Value: SystemString);
begin
  if TPascalString(FRootPath).Same(Value) then
      Exit;
  FRootPath := Value;
  LoadDB(False);
end;

procedure TZDBLocalManager.Progress;
begin
  FCadencerEng.Progress;
end;

function TZDBLocalManager.InitDB(dataBaseName_: SystemString): TZDBLMStore;
begin
  Result := InitDB(dataBaseName_, False);
end;

function TZDBLocalManager.InitDB(dataBaseName_: SystemString; ReadOnly: Boolean): TZDBLMStore;
var
  fn: U_String;
  isNewDB: Boolean;
begin
  Result := GetDB(dataBaseName_);
  if Result <> nil then
      Exit;

  if not U_String(dataBaseName_).Exists(['/', '\']) then
      fn := umlCombineFileName(FRootPath, dataBaseName_ + '.OX')
  else
    begin
      fn.Text := dataBaseName_;
      dataBaseName_ := umlChangeFileExt(umlGetFileName(dataBaseName_), '');
    end;

  isNewDB := not umlFileExists(fn);

  if isNewDB then
    begin
      Result := TZDBLMStore.CreateNew(fn);
      DoStatus('create new DB file "%s"', [fn.Text]);
    end
  else
    begin
      Result := TZDBLMStore.Create(fn, ReadOnly);
      DoStatus('Open DB file "%s"', [fn.Text]);
    end;

  Result.NotifyIntf := Self;
  Result.FName := dataBaseName_;

  FDBPool[dataBaseName_] := Result;

  try
    if (Assigned(FNotifyIntf)) then
      begin
        if (isNewDB) then
            FNotifyIntf.CreateDB(Result)
        else
            FNotifyIntf.OpenDB(Result);
      end;
  except
  end;
end;

function TZDBLocalManager.InitNewDB(dataBaseName_: SystemString): TZDBLMStore;
var
  fn: U_String;
begin
  if not U_String(dataBaseName_).Exists(['/', '\']) then
      fn := umlCombineFileName(FRootPath, dataBaseName_ + '.OX')
  else
    begin
      fn := dataBaseName_;
      dataBaseName_ := umlChangeFileExt(umlGetFileName(dataBaseName_), '');
    end;

  FDBPool.Delete(dataBaseName_);

  Result := TZDBLMStore.CreateNew(fn);

  Result.NotifyIntf := Self;
  Result.FName := dataBaseName_;

  FDBPool[dataBaseName_] := Result;

  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.CreateDB(Result);
  except
  end;
end;

function TZDBLocalManager.InitMemoryDB(dataBaseName_: SystemString): TZDBLMStore;
begin
  Result := GetDB(dataBaseName_);
  if Result <> nil then
      Exit;
  Result := TZDBLMStore.CreateNewMemory;

  Result.NotifyIntf := Self;
  Result.FName := dataBaseName_;

  FDBPool[dataBaseName_] := Result;

  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.CreateDB(Result);
  except
  end;
end;

procedure TZDBLocalManager.CloseDB(dataBaseName_: SystemString);
var
  Database_: TZDBLMStore;
  i: Integer;
  pl: TZDBPipeline;
begin
  Database_ := GetDB(dataBaseName_);
  if Database_ = nil then
      Exit;

  for i := 0 to FQueryPipelineList.Count - 1 do
    begin
      pl := TZDBPipeline(FQueryPipelineList[i]);
      if pl.OutputDB = Database_ then
          pl.OutputDB := nil;
      if pl.SourceDB = Database_ then
          pl.SourceDB := nil;
    end;

  try
    if Assigned(FNotifyIntf) then
        FNotifyIntf.CloseDB(Database_);
  except
  end;

  FDBPool.Delete(dataBaseName_);
end;

procedure TZDBLocalManager.CloseAndDeleteDB(dataBaseName_: SystemString);
var
  Database_: TZDBLMStore;
  fn: SystemString;
begin
  Database_ := GetDB(dataBaseName_);
  if Database_ = nil then
      Exit;

  if Database_.DBEngine.StreamEngine is TMS64 then
    begin
      CloseDB(Database_.Name);
    end
  else
    begin
      fn := Database_.DBEngine.ObjectName;
      CloseDB(Database_.Name);
      if umlFileExists(fn) then
          umlDeleteFile(fn);
    end;
end;

function TZDBLocalManager.CopyDB(SourceDatabaseName_, DestDatabaseName_: SystemString): TZDBPipeline;
var
  n: SystemString;
  pl: TZDBPipeline;
  Database_: TZDBLMStore;
  nd: TZDBLMStore;
begin
  Result := nil;
  Database_ := GetDB(SourceDatabaseName_);
  if Database_ = nil then
      Exit;

  if Database_.IsReadOnly then
      Exit;

  n := DestDatabaseName_;

  if Database_.IsMemoryMode then
      nd := InitMemoryDB(n)
  else
      nd := InitDB(n, False);

  pl := QueryDB(False, True, False, Database_.Name, 'Copying', True, 0.0, 0, 0, 0, 0);
  pl.OnDataFilter_M := DoQueryCopy;
  pl.OnDataDone_M := DoCopyDone;
  pl.UserVariant := nd.Name;
  pl.ClearStorePosTransform;
  Result := pl;
end;

function TZDBLocalManager.CopyDB(SourceDatabaseName_, DestDatabaseName_: SystemString; const UserData: Pointer; const OnStorePosTransform: TZDBStorePosTransformNotify): TZDBPipeline;
begin
  Result := CopyDB(SourceDatabaseName_, DestDatabaseName_);
  Result.OnStorePosTransform := OnStorePosTransform;
  Result.UserPointer := UserData;
end;

function TZDBLocalManager.CompressDB(dataBaseName_: SystemString): TZDBPipeline;
var
  n: SystemString;
  pl: TZDBPipeline;
  Database_: TZDBLMStore;
  nd: TZDBLMStore;
begin
  Result := nil;
  Database_ := GetDB(dataBaseName_);
  if Database_ = nil then
      Exit;

  if Database_.IsReadOnly then
      Exit;

  if ExistsPipeline(Database_.Name + '.*.Compressing') then
      Exit;

  n := Database_.Name + '.CompressSwap';

  if ExistsDB(n) then
      Exit;

  if Database_.IsMemoryMode then
      nd := InitMemoryDB(n)
  else
      nd := InitNewDB(n);

  pl := QueryDB(False, True, False, Database_.Name, n, False, 0.0, 0, 0, 0, 0);
  pl.OnDataFilter_M := DoQueryCopy;
  pl.OnDataDone_M := DoCompressDone;
  pl.UserVariant := nd.Name;
  pl.ClearStorePosTransform;
  Result := pl;
end;

function TZDBLocalManager.CompressDB(dataBaseName_: SystemString; const UserData: Pointer; const OnStorePosTransform: TZDBStorePosTransformNotify): TZDBPipeline;
begin
  Result := CompressDB(dataBaseName_);
  Result.OnStorePosTransform := OnStorePosTransform;
  Result.UserPointer := UserData;
end;

procedure TZDBLocalManager.ReplaceDB(dataBaseName_, replaceN: SystemString);
begin
  with ProgressPost.PostExecuteM(False, 0, DelayReplaceDB) do
    begin
      Data3 := dataBaseName_;
      Data4 := replaceN;
      Ready();
    end;
end;

procedure TZDBLocalManager.ResetDB(dataBaseName_: SystemString);
var
  Database_: TZDBLMStore;
begin
  Database_ := GetDB(dataBaseName_);
  if Database_ = nil then
      Exit;

  if Database_.IsReadOnly then
      Exit;

  Database_.ResetDB;
end;

procedure TZDBLocalManager.ResetData(dataBaseName_: SystemString);
begin
  ResetDB(dataBaseName_);
end;

procedure TZDBLocalManager.Recache;
var
  lst: TCore_ListForObj;
  i: Integer;
  Database_: TZDBLMStore;
begin
  lst := TCore_ListForObj.Create;
  FDBPool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
    begin
      Database_ := TZDBLMStore(lst[i]);
      Database_.Recache;
    end;
  DisposeObject(lst);
end;

procedure TZDBLocalManager.Flush;
var
  lst: TCore_ListForObj;
  i: Integer;
  Database_: TZDBLMStore;
begin
  lst := TCore_ListForObj.Create;
  FDBPool.GetAsList(lst);
  for i := 0 to lst.Count - 1 do
    begin
      Database_ := TZDBLMStore(lst[i]);
      Database_.Update;
    end;
  DisposeObject(lst);
end;

function TZDBLocalManager.GenerateTaskName: SystemString;
begin
  Result := 'Task' + umlIntToStr(FTaskSeed).Text;
end;

function TZDBLocalManager.GenerateNewTaskName: SystemString;
begin
  Result := GenerateTaskName;
  inc(FTaskSeed);
end;

function TZDBLocalManager.GetPipeline(pipeName: SystemString): TZDBPipeline;
begin
  Result := TZDBPipeline(FQueryPipelinePool[pipeName]);
end;

function TZDBLocalManager.GetDB(dataBaseName_: SystemString): TZDBLMStore;
begin
  Result := TZDBLMStore(FDBPool[dataBaseName_]);
end;

function TZDBLocalManager.GetOrCreateDB(dataBaseName_: SystemString): TZDBLMStore;
begin
  Result := GetDB(dataBaseName_);
  if Result = nil then
      Result := InitDB(dataBaseName_, False);
end;

function TZDBLocalManager.GetDBName(dataBaseName_: SystemString): TZDBLMStore;
begin
  Result := InitMemoryDB(dataBaseName_);
end;

function TZDBLocalManager.ExistsDB(dataBaseName_: SystemString): Boolean;
begin
  Result := FDBPool.Exists(dataBaseName_);
end;

function TZDBLocalManager.ExistsPipeline(pipeName: SystemString): Boolean;
var
  i: Integer;
begin
  Result := FQueryPipelinePool.Exists(pipeName);
  if Result then
      Exit;
  for i := 0 to FQueryPipelineList.Count - 1 do
    if umlMultipleMatch(True, pipeName, TZDBPipeline(FQueryPipelineList[i]).PipelineName) then
      begin
        Result := True;
        Exit;
      end;
end;

procedure TZDBLocalManager.StopPipeline(pipeName: SystemString);
var
  pl: TZDBPipeline;
begin
  pl := GetPipeline(pipeName);
  if pl <> nil then
      pl.stop;
end;

procedure TZDBLocalManager.GetPipeList(OutputList: TCore_ListForObj);
begin
  FQueryPipelinePool.GetAsList(OutputList);
end;

procedure TZDBLocalManager.GetDBList(OutputList: TCore_ListForObj);
begin
  FDBPool.GetAsList(OutputList);
end;

function TZDBLocalManager.Busy(Database_: TZDBLMStore): Boolean;
var
  i: Integer;
  pl: TZDBPipeline;
begin
  Result := False;
  for i := 0 to FQueryPipelineList.Count - 1 do
    begin
      pl := TZDBPipeline(FQueryPipelineList[i]);
      if (pl.Activted) and ((pl.SourceDB = Database_) or (pl.OutputDB = Database_)) then
        begin
          Result := True;
          Exit;
        end;
    end;
end;

function TZDBLocalManager.CanDestroy(Database_: TZDBLMStore): Boolean;
var
  i: Integer;
  pl: TZDBPipeline;
begin
  Result := False;
  if Database_ = nil then
      Exit;

  for i := 0 to FQueryPipelineList.Count - 1 do
    begin
      pl := TZDBPipeline(FQueryPipelineList[i]);
      if (pl.Activted) and (pl.AutoDestroyDB) and ((pl.SourceDB = Database_) or (pl.OutputDB = Database_)) then
          Exit;
    end;

  Result := True;
end;

function TZDBLocalManager.QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline;
var
  tN: SystemString;
  plN: SystemString;
begin
  Result := nil;

  if not ExistsDB(dataBaseName_) then
      Exit;

  tN := GenerateNewTaskName;
  plN := GeneratePipeName(dataBaseName_, tN);
  if OutputDBName_ = '' then
      OutputDBName_ := plN;
  Result := FPipelineClass.Create(InMemory, Self, dataBaseName_, plN, OutputDBName_);

  Result.WriteResultToOutputDB := WriteResultToOutputDB;
  Result.AutoDestroyDB := AutoDestroyDB;
  Result.FragmentWaitTime := FragmentWaitTime;
  Result.MaxWaitTime := MaxWaitTime;
  Result.MaxQueryCompare := MaxQueryCompare;
  Result.MaxQueryResult := MaxQueryResult;
  Result.QueryDoneFreeDelayTime := QueryDoneFreeDelayTime;
  Result.WriteFragmentBuffer := True;

  Result.FQueryTask := Result.SourceDB.QueryM(Result.PipelineName, ReverseQuery, Result.Query, Result.QueryDone);
  try
    if Assigned(NotifyIntf) then
        NotifyIntf.CreateQuery(Result);
  except
  end;
end;

function TZDBLocalManager.QueryDBC(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64;
  OnDataFilter_C: TZDBPipelineFilter_C; OnDataDone_C: TZDBPipelineDone_C): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery, dataBaseName_, OutputDBName_, AutoDestroyDB, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
  Result.OnDataFilter_C := OnDataFilter_C;
  Result.OnDataDone_C := OnDataDone_C;
end;

function TZDBLocalManager.QueryDBM(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64;
  OnDataFilter_M: TZDBPipelineFilter_M; OnDataDone_M: TZDBPipelineDone_M): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery, dataBaseName_, OutputDBName_, AutoDestroyDB, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
  Result.OnDataFilter_M := OnDataFilter_M;
  Result.OnDataDone_M := OnDataDone_M;
end;

function TZDBLocalManager.QueryDBP(WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64;
  OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery, dataBaseName_, OutputDBName_, AutoDestroyDB, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
  Result.OnDataFilter_P := OnDataFilter_P;
  Result.OnDataDone_P := OnDataDone_P;
end;

function TZDBLocalManager.QueryDBP(DataEng: TDFE; UserObj: TCore_Object;
  WriteResultToOutputDB, InMemory, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  AutoDestroyDB: Boolean; QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64;
  OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, InMemory, ReverseQuery, dataBaseName_, OutputDBName_, AutoDestroyDB, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
  Result.OnDataFilter_P := OnDataFilter_P;
  Result.OnDataDone_P := OnDataDone_P;
  if DataEng <> nil then
      Result.DataEng.Assign(DataEng);
  Result.UserObject := UserObj;
end;

function TZDBLocalManager.QueryDBToMemory(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
  QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double;
  MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, True, ReverseQuery, dataBaseName_, 'Temp', True, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
end;

function TZDBLocalManager.QueryDBToMemory(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
  FragmentWaitTime, MaxWaitTime: Double; MaxQueryResult: Int64): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, True, ReverseQuery, dataBaseName_, 'Temp', True, 60 * 5, FragmentWaitTime, MaxWaitTime, 0, MaxQueryResult);
end;

function TZDBLocalManager.QueryDBToMemoryP(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_: SystemString;
  QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime: Double; MaxQueryCompare, MaxQueryResult: Int64;
  OnDataFilter_P: TZDBPipelineFilter_P; OnDataDone_P: TZDBPipelineDone_P): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, True, ReverseQuery, dataBaseName_, 'Temp', True, QueryDoneFreeDelayTime, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
  Result.OnDataFilter_P := OnDataFilter_P;
  Result.OnDataDone_P := OnDataDone_P;
end;

function TZDBLocalManager.QueryDBToFile(WriteResultToOutputDB, ReverseQuery: Boolean; dataBaseName_, OutputDBName_: SystemString;
  FragmentWaitTime, MaxWaitTime: Double; MaxQueryCompare, MaxQueryResult: Int64): TZDBPipeline;
begin
  Result := QueryDB(WriteResultToOutputDB, False, ReverseQuery, dataBaseName_, OutputDBName_, False, 0, FragmentWaitTime, MaxWaitTime, MaxQueryCompare, MaxQueryResult);
end;

function TZDBLocalManager.ReadDBItemToZDBFragment(dataBaseName_: SystemString; StorePos: Int64; DestStream: TMS64): Boolean;
begin
  Result := False;
  if not ExistsDB(dataBaseName_) then
      Exit;

  Result := EncodeZDBFragment(DBName[dataBaseName_], StorePos, DestStream);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; sourDBEng: TZDBLMStore; SourStorePos: Int64): Int64;
var
  d: TZDBLMStore;
  M: TDBCacheStream64;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  M := sourDBEng.GetCacheStream(SourStorePos);
  if M <> nil then
    begin
      Result := d.AddData(M, M.CacheID);
      DisposeObject(M);
    end;
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; var qState: TQueryState): Int64;
var
  d: TZDBLMStore;
  M: TDBCacheStream64;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  M := qState.Eng.GetCacheStream(qState.StorePos, qState.ID);
  if M <> nil then
    begin
      Result := d.AddData(M, M.CacheID);
      DisposeObject(M);
    end;
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: TCore_Stream; ID: Cardinal): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour, ID);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: TDFE): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: THashVariantList): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: THashStringList): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: TSectionTextData): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: TPascalString): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.PostData(dataBaseName_: SystemString; dSour: TZ_JsonObject): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetOrCreateDB(dataBaseName_);
  Result := d.AddData(dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TCore_Stream; ID: Cardinal): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour, ID);
    end
  else
      Result := d.InsertData(InsertPos, dSour, ID);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TDFE): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: THashVariantList): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: THashStringList): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TSectionTextData): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TPascalString): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

function TZDBLocalManager.InsertData(dataBaseName_: SystemString; InsertPos: Int64; dSour: TZ_JsonObject): Int64;
var
  d: TZDBLMStore;
begin
  Result := -1;
  d := GetDB(dataBaseName_);
  if d = nil then
    begin
      d := InitDB(dataBaseName_);
      Result := d.AddData(dSour);
    end
  else
      Result := d.InsertData(InsertPos, dSour);
end;

procedure TZDBLocalManager.DeleteData(dataBaseName_: SystemString; StorePos: Int64);
var
  d: TZDBLMStore;
begin
  d := GetDB(dataBaseName_);
  if d = nil then
      Exit;
  d.DeleteData(StorePos);
end;

function TZDBLocalManager.GetData(dataBaseName_: SystemString; StorePos: Int64; ID: Cardinal): TDBCacheStream64;
var
  d: TZDBLMStore;
begin
  Result := nil;
  d := GetDB(dataBaseName_);
  if d = nil then
      Exit;
  Result := d.GetCacheStream(StorePos, ID);
end;

function TZDBLocalManager.SetData(dataBaseName_: SystemString; StorePos: Int64; dSour: TMS64): Boolean;
var
  d: TZDBLMStore;
begin
  Result := False;
  d := GetDB(dataBaseName_);
  if d = nil then
      Exit;
  Result := d.SetData(StorePos, dSour);
end;

class procedure TZDBLocalManager.Test_LM;
var
  LM: TZDBLocalManager;
  wait_: Boolean;
{$IFDEF FPC}
  procedure do_fpc_Query(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean);
  begin
    if qState.IsString then
      begin
        DoStatus(qState.Eng.GetString(qState));
      end;
  end;

  procedure do_fpc_Query_Done(dPipe: TZDBPipeline);
  begin
    wait_ := False;
  end;
{$ENDIF FPC}


begin
  LM := TZDBLocalManager.Create;
  LM.RootPath := umlGetCurrentPath;
  with LM.InitMemoryDB('test') do
    begin
      DBEngine.HandlePtr^.IOHnd.Cache.UsedWriteCache := True;
      DBEngine.HandlePtr^.IOHnd.Cache.UsedReadCache := True;
    end;
  LM.PostData('test', 'hello world');
  wait_ := True;
{$IFDEF FPC}
  LM.QueryDBP(True, True, False, 'test', 'test_output', True, 1.0, 1, 0, 0, 0, do_fpc_Query, do_fpc_Query_Done);
{$ELSE FPC}
  LM.QueryDBP(True, True, False, 'test', 'test_output', True, 1.0, 1, 0, 0, 0,
      procedure(dPipe: TZDBPipeline; var qState: TQueryState; var Allowed: Boolean)
    begin
      if qState.IsString then
        begin
          DoStatus(qState.Eng.GetString(qState));
        end;
    end,
    procedure(dPipe: TZDBPipeline)
    begin
      wait_ := False;
    end);
{$ENDIF FPC}
  while wait_ do
    begin
      LM.Progress;
      CheckThread(10);
    end;

  DisposeObject(LM);
end;

initialization

ZDBLocalManager_SystemRootPath := umlCurrentPath();

end.
 
