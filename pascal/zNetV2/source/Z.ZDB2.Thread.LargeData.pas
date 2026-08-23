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
  *  Large Data Templet for HPC – Scalable Three-Tier Hierarchical Database
  *
  *  This unit provides a production-ready, high-performance storage system for
  *  managing data across three distinct size categories: Small, Medium, and Large.
  *  It is built directly on top of Z.ZDB2.Thread and Z.ZDB2.Thread.LiteData,
  *  extending them with a type‑aware, relational‑like model that is ideal for
  *  applications such as face recognition, surveillance, AI training pipelines,
  *  video archives, and any large‑scale data‑intensive system.
  *
  *  Architecture Overview
  *  ---------------------
  *  The system is organized into three independent database pools, each designed
  *  for a specific data size and access pattern:
  *
  *    1. Small Data (S_DB)   – ~1 KB blocks, up to 1.5 TB per library.
  *       Script aliases: 'Small', 'Tiny', 'Little', 'S', 'Lv1', '1'.
  *       Optimized for logs, device status, JSON/XML/INI configurations, DFE
  *       serialized objects, and other lightweight records. Supports full
  *       traversal and high‑speed indexing via Sequence_ID.
  *
  *    2. Medium Data (M_DB)  – ~8 KB blocks, up to 15 TB per library.
  *       Script aliases: 'Default', 'Medium', 'Middle', 'M', 'Lv2', '2'.
  *       Optimized for images, PDFs, office documents, source code, and small
  *       binary files. Uses block‑level pre‑reading to extract Sequence_IDs
  *       without loading the entire data body.
  *
  *    3. Large Data (L_DB)   – ~64 KB blocks, up to 100 TB per library.
  *       Script aliases: 'Large', 'Big', 'Huge', 'L', 'Lv3', '3'.
  *       Optimized for videos, compressed archives, AI datasets, and large
  *       binary blobs. Recommended to split huge files (e.g., 500 MB video) into
  *       segments and reference them via Small‑Data Sequence_IDs.
  *
  *  Each stored record is assigned a unique 64‑bit Sequence_ID (auto‑incremented
  *  per category) and an MD5 checksum of its payload. Both are stored in a fixed
  *  24‑byte header prepended to the data body (8 bytes for Sequence_ID,
  *  16 bytes for MD5). This header is present in the on‑disk representation and
  *  is used for fast reverse lookup via the corresponding Sequence_ID pool.
  *
  *  Loading Modes (Data Extraction)
  *  --------------------------------
  *  All three databases support multiple loading strategies, allowing trade‑offs
  *  between speed, memory, and I/O granularity:
  *
  *    – Full Load   (Extract_*_Full)     : Reads and decodes every data object
  *      entirely in parallel. Suitable for small databases or when full content
  *      is needed immediately.
  *
  *    – Block Load  (Extract_*_Block)    : Reads only a specific block index,
  *      offset, and size from each object. Ideal for partial content retrieval
  *      (e.g., reading a single frame from a video segment).
  *
  *    – Position Load (Extract_*_Position): Reads a contiguous byte range from
  *      each object. Used for range‑based queries.
  *
  *    – Accelerated Header Load (External Header Optimization):
  *      If the corresponding flag (S_DB_Engine_External_Header_Optimzied_Technology,
  *      etc.) is enabled, the system stores a compact external header block
  *      during flush. This block contains Sequence_ID and MD5 for every record
  *      in the pool. On startup, the system first attempts to restore all
  *      Sequence_IDs from this header (Extract_External_Header) – which is much
  *      faster than reading the full data – and falls back to full/block/position
  *      load only if the header is missing or corrupted.
  *
  *  Data Flow and Lifecycle
  *  -----------------------
  *  1. Creation: A new data item is created via Create_Small_Data, Create_Medium_Data,
  *     or Create_Large_Data. A fresh Sequence_ID is allocated, and the instance
  *     is added to the engine pool and the corresponding Sequence_ID pool.
  *
  *  2. Encoding: When posting (Post_Data_To_*_DB), the payload is encoded via
  *     Encode_To_ZDB2_Data, which prepends Sequence_ID and MD5. The encoded
  *     buffer is then asynchronously written to the underlying ZDB2 storage.
  *
  *  3. Flush: During a flush operation, the marshal calls Prepare_Flush_External_Header,
  *     which serializes Sequence_ID and MD5 for all active instances into the
  *     external header block (if optimization is enabled). The header is stored
  *     in the database’s custom header area.
  *
  *  4. Rebuild: After loading (full/block/position), the Rebuild_*_DB_Sequence
  *     methods sort all data by Sequence_ID and rebuild the reverse‑lookup
  *     pools, ensuring that the Sequence_ID pools reflect the current data.
  *
  *  5. Batch Posting: The TZDB2_Custom_Batch_Data_Post_Bridge allows multiple
  *     related records (e.g., a JSON small record referencing several medium and
  *     large blobs) to be posted atomically. The bridge tracks success/failure
  *     and can automatically roll back the entire batch if any error occurs.
  *
  *  6. Modification: Existing data can be replaced using Modify_*_DB_Data, which
  *     updates the payload, recomputes the MD5, and re‑encodes the data.
  *
  *  Script-Driven Configuration
  *  ---------------------------
  *  The TZDB2_Large class can be built from a TTextDataEngine script that defines
  *  one section per engine. Each section specifies the database file, block size,
  *  cipher settings, and a 'Type' field that selects Small/Medium/Large. The
  *  Build_DB_From_Script method creates the appropriate engine and attaches it to
  *  the corresponding marshal. The Make_Script helper generates a ready‑to‑use
  *  script with configurable numbers of sub‑engines for each size category.
  *
  *  Backup, Flush, and Statistics
  *  -----------------------------
  *  – Backup: Backup(Reserve_) creates a point‑in‑time copy of each sub‑engine,
  *    keeping up to Reserve_ historical versions.
  *
  *  – Flush: Flush(WaitQueue_) forces all pending asynchronous writes to disk.
  *    If WaitQueue_ is True, the call blocks until the command queue is empty.
  *
  *  – Statistics: Database_Size, Database_Physics_Size, Total, QueueNum, and
  *    fragment buffer metrics are available for monitoring and capacity planning.
  *
  *  Thread Safety and Performance
  *  -----------------------------
  *  All public methods are thread‑safe thanks to critical sections and atomic
  *  counters. The system is designed for high concurrency: read operations are
  *  lock‑free when using pools, and writes are enqueued as commands to the
  *  underlying TZDB2_Th_Queue instances. The external header optimization
  *  dramatically reduces startup latency on HDDs by minimizing random I/O.
  *
  *  This unit is a cornerstone for building large‑scale, high‑performance
  *  data‑intensive applications in the Z‑Series ecosystem.
*)
unit Z.ZDB2.Thread.LargeData;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses DateUtils, SysUtils,
  Z.Core,
{$IFDEF FPC}
  Z.FPC.GenericList,
{$ELSE FPC}
  System.IOUtils,
{$ENDIF FPC}
  Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib,
  Z.MemoryStream,
  Z.Status, Z.Cipher, Z.ZDB2, Z.ListEngine, Z.TextDataEngine, Z.IOThread,
  Z.HashList.Templet, Z.DFE, Z.Geometry2D, Z.Int128,
  Z.Notify, Z.ZDB2.Thread.Queue, Z.ZDB2.Thread;

type
  { Pre declaration }
  TZDB2_Large = class;
  TZDB2_Custom_Small_Data = class;
  TZDB2_Custom_Medium_Data = class;
  TZDB2_Custom_Large_Data = class;
  TZDB2_Custom_Small_Data_Class = class of TZDB2_Custom_Small_Data;
  TZDB2_Custom_Medium_Data_Class = class of TZDB2_Custom_Medium_Data;
  TZDB2_Custom_Large_Data_Class = class of TZDB2_Custom_Large_Data;

  { Sequence ID pool structure, providing reverse lookup function }
  TZDB2_Custom_Small_Sequence_ID_Pool = TCritical_Big_Hash_Pair_Pool<Int64, TZDB2_Custom_Small_Data>; // Thread-safe hash map: Sequence_ID -> Small data instance – created by TZDB2_Large constructor, populated during Rebuild_S_DB_Sequence and when new small data is created.
  TZDB2_Custom_Medium_Sequence_ID_Pool = TCritical_Big_Hash_Pair_Pool<Int64, TZDB2_Custom_Medium_Data>; // Thread-safe hash map: Sequence_ID -> Medium data instance – created by TZDB2_Large constructor, populated during Rebuild_M_DB_Sequence and when new medium data is created.
  TZDB2_Custom_Large_Sequence_ID_Pool = TCritical_Big_Hash_Pair_Pool<Int64, TZDB2_Custom_Large_Data>; // Thread-safe hash map: Sequence_ID -> Large data instance – created by TZDB2_Large constructor, populated during Rebuild_L_DB_Sequence and when new large data is created.

  { Chain tools, data exchange, caching, batching, computation, classification }
  TZDB2_Custom_Data_Pool = TBigList<TZDB2_Th_Engine_Data>; // Generic pool for temporarily holding engine data instances – used internally by batch bridge and elsewhere.

  TZDB2_Custom_Batch_Data_Post_Bridge = class; // Forward declaration.

  // Event callbacks for batch post completion (C, M, P).
  TZDB2_Custom_Batch_Data_Post_Bridge_Event_C = procedure(Sender: TZDB2_Custom_Batch_Data_Post_Bridge);
  TZDB2_Custom_Batch_Data_Post_Bridge_Event_M = procedure(Sender: TZDB2_Custom_Batch_Data_Post_Bridge) of object;
{$IFDEF FPC}
  TZDB2_Custom_Batch_Data_Post_Bridge_Event_P = procedure(Sender: TZDB2_Custom_Batch_Data_Post_Bridge) is nested;
{$ELSE FPC}
  TZDB2_Custom_Batch_Data_Post_Bridge_Event_P = reference to procedure(Sender: TZDB2_Custom_Batch_Data_Post_Bridge);
{$ENDIF FPC}

  { TZDB2_Custom_Batch_Data_Post_Bridge solves the optimal storage performance of combined data }
  { It supports saving one batch at a time and returning the stored results. This mechanism can be used for data binding, such as one json small data binding multiple medium data or Big data entries }
  TZDB2_Custom_Batch_Data_Post_Bridge = class(TCore_Object_Intermediate)
  private
    FCritical: TCritical; // Lock for thread safety – created by constructor.
    Total_Post: Integer; // Total number of items to be posted – incremented by each Post_Data_To_xxx method.
    Post_Busy: Integer; // Number of posts currently in progress – incremented by Begin_Post, decremented by End_Post/Done_Post.
    procedure Do_Save_Data_Result(Sender: TZDB2_Th_Engine_Data; Successed: Boolean); // Callback when a single data save completes.
    procedure Do_Check_Post_Done; // Checks if all posts are done, triggers Do_All_Post_Done.
    procedure Do_All_Post_Done; // Finalizes the batch, invokes user callback.
  public
    FOwner_Large_Marshal: TZDB2_Large; // Owning TZDB2_Large instance – set by constructor.
    Successed_Num: Integer; // Number of successfully posted items – updated by Do_Save_Data_Result.
    Error_Num: Integer; // Number of failed items – updated by Do_Save_Data_Result.
    Error_Do_Remove_Data: Boolean; // If True, removes all successfully posted data when any error occurs – set by user (default True).
    Post_Pool: TZDB2_Custom_Data_Pool; // Pool of data objects that have been posted (for tracking) – created by constructor.
    Done_Pool: TZDB2_Custom_Data_Pool; // Pool of data objects that finished successfully – created by constructor.
    OnResult_C: TZDB2_Custom_Batch_Data_Post_Bridge_Event_C; // Callback on completion (C-style).
    OnResult_M: TZDB2_Custom_Batch_Data_Post_Bridge_Event_M; // Callback on completion (method).
    OnResult_P: TZDB2_Custom_Batch_Data_Post_Bridge_Event_P; // Callback on completion (nested/reference).
    User_Hash_Variants: THashVariantList; // User-defined variant dictionary – set by user.
    User_Hash_Strings: THashStringList; // User-defined string dictionary – set by user.
    constructor Create(Owner_Large_DB_Engine_: TZDB2_Large);
    destructor Destroy; override;
    procedure Begin_Post; // Marks the start of a batch post (increments Post_Busy).
    function Post_Data_To_S_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Small_Data; // Posts small data, returns the instance.
    function Post_Data_To_M_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Medium_Data; // Posts medium data.
    function Post_Data_To_L_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Large_Data; // Posts large data.
    procedure End_Post; // Marks the end of a batch post (decrements Post_Busy).
    procedure Done_Post; // Alias for End_Post.
  end;

  { TZDB2_Custom_Small_Data storage format }
  { Small data has a storage sequence mechanism that can be automatically preloaded, with full data loading as the preloading method }
  { The following data structure Make your own decision, and when opening the database }
  { The number of small data is unlimited. Individual small data should not be treated as Big data. It is recommended that individuals should not exceed 10kb }
  { Small storage block of approximately 1KB, single library storage limit of 1.5TB }
  { Save DFE, JSON, XML, ini, HTML, logs, running device status, using small data }
  { Type aliases in the script: 'Small', 'Tiny', 'Little', 'S',' Lv1 ',' 1 ' }
  TZDB2_Custom_Small_Data = class(TZDB2_Th_Engine_Data)
  private
    FOwner_Large_Marshal: TZDB2_Large; // Owner large marshal – set by TS_Th_Engine_Marshal.Do_Add_Data.
    { 0-7: Int64, serialization ID, representing the sequence of data entries, and opening the database will automatically restore the sorting order }
    FSequence_ID: Int64; // Sequence ID – assigned by TZDB2_Large.Create_Small_Data or during decoding.
    { 8-24: MD5 of the data body, which represents the data body ending from 24. Providing MD5 here is equivalent to providing reference information for fault recovery }
    FMD5: TMD5; // MD5 checksum of the payload – computed on post/update.
  public
    property Owner_Large_Marshal: TZDB2_Large read FOwner_Large_Marshal;
    property Sequence_ID: Int64 read FSequence_ID write FSequence_ID;
    property MD5: TMD5 read FMD5 write FMD5;
    constructor Create(); override;
    destructor Destroy; override;
    { When data is removed }
    { If a lot of data is bound, it is necessary to delete the binding together }
    procedure Do_Remove(); override; // Removes from sequence pool; override to also remove dependent data if needed.
    { Encoding data body -> Store physical data of inverted database }
    { Programming can be done through external interfaces }
    function Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64; virtual; // Prepends Sequence_ID and MD5, returns TMem64 buffer.
    { Decode the original data from the database and return the original data body, excluding Sequence_ID, MD5 }
    { Decoding returns TMS64 in Mapping mode without copying }
    { Data_Source is always complete data }
    { Programming can be done through external interfaces }
    function Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64; virtual; // Extracts Sequence_ID and MD5 if Update_=True, returns payload.
    { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
    { When the data volume is large, a dataset contains dozens or hundreds of small databases. During disk operation, disk pre reads will be read in blocks, which greatly consumes HDD read time }
    { Expanding the data header is to gather thousands of fragmented databases and read them all at once, thereby improving the startup efficiency of the database. At the same time, pre reading also requires higher memory requirements }
    { Pre reading technology can improve data loading efficiency in the vast majority of hdd systems }
    procedure Encode_External_Header_Data(Data_Source: TMem64); virtual; // Writes Sequence_ID and MD5 to external header buffer.
    procedure Decode_External_Header_Data(Data_Source: TMem64); virtual; // Reads Sequence_ID and MD5 from external header buffer.
  end;

  { TZDB2_Custom_Medium_Data storage format }
  { The middle data sequence mechanism is small block serialization, which does not read the entire data during preloading. It reads the first block data and retrieves the sequence ID from the block. The middle data block defaults to 8kb }
  { The highest efficiency of using block to pre read sequence IDs is in non encrypted mode. If in encrypted mode, the block will decode a large block and read the sequence ID again }
  { Some array systems have a pre read mechanism. If there are too many sub libraries in the data, the pre read mechanism will fail. In this case, please adjust it according to the array system parameters, and it is uncertain if it can improve the performance }
  { Small storage blocks are approximately 8KB, with a single library storage limit of 15TB }
  { Save Piture, PDFs, docs, codes, and other small files, using medium data }
  { Type aliases in the script: 'Default', 'Medium', 'Middle', 'M', 'Lv2', '2' }
  TZDB2_Custom_Medium_Data = class(TZDB2_Th_Engine_Data)
  private
    FOwner_Large_Marshal: TZDB2_Large; // Owner large marshal – set by TM_Th_Engine_Marshal.Do_Add_Data.
    { 0-7: Int64, serialization ID, representing the sequence of data entries. Opening the database will automatically restore the sorting order, and Extract is not supported_Data_Source }
    FSequence_ID: Int64; // Sequence ID – assigned by TZDB2_Large.Create_Medium_Data or during decoding.
    { 8-24: The md5 of the data body represents the data body that ends from 24. Providing md5 here is equivalent to providing a guarantee for fault recovery }
    { Medium Big data will only calculate md5 when submitting and repairing the database. There will be a slight delay in calculating md5 when submitting, but the impact will be slight }
    FMD5: TMD5; // MD5 of the payload – computed on post/update.
  public
    property Owner_Large_Marshal: TZDB2_Large read FOwner_Large_Marshal;
    property Sequence_ID: Int64 read FSequence_ID write FSequence_ID;
    property MD5: TMD5 read FMD5 write FMD5;
    constructor Create(); override;
    destructor Destroy; override;
    { When data is removed }
    { If a lot of data is bound, it is necessary to delete the binding together }
    procedure Do_Remove(); override; // Removes from sequence pool.
    { Encoding data body -> Store physical data of inverted database }
    { Programming can be done through external interfaces }
    function Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64; virtual; // Prepends Sequence_ID and MD5.
    { Decode the original data from the database and return the original data body, excluding Sequence_ID, MD5 }
    { Decoding returns TMS64 in Mapping mode without copying }
    { When data is opened, Data_Source's data is a block block block, while other scenario data_Source is the complete data }
    { Programming can be done through external interfaces }
    function Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64; virtual; // Extracts Sequence_ID and MD5 if Update_=True.
    { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
    procedure Encode_External_Header_Data(Data_Source: TMem64); virtual; // Writes Sequence_ID and MD5 to external header.
    procedure Decode_External_Header_Data(Data_Source: TMem64); virtual; // Reads Sequence_ID and MD5 from external header.
  end;

  { TZDB2_Custom_Large_Data storage format }
  { The Big data sequence mechanism is block read ahead, and the block is 64kb by default }
  { Small storage block 64KB, single library storage limit 100TB }
  { Big data can be used to store videos, compressed packages, AI data sets, single day data packaging, weekly data packaging, and large files }
  { For example, for a 500M video, it is recommended to split it into 500 1M segments and then write the sequence stored in the video into small data_ID, then save }
  { Type aliases in the script: 'Large', 'Big', 'Huge', 'L', 'Lv3', '3' }
  TZDB2_Custom_Large_Data = class(TZDB2_Th_Engine_Data)
  private
    FOwner_Large_Marshal: TZDB2_Large; // Owner large marshal – set by TL_Th_Engine_Marshal.Do_Add_Data.
    { 0-7: Int64, serialization ID, representing the sequence of data entries. Opening the database will automatically restore the sorting order, and Extract is not supported_Data_Source }
    FSequence_ID: Int64; // Sequence ID – assigned by TZDB2_Large.Create_Large_Data or during decoding.
    { 8-24: The md5 of the data body represents the data body that ends from 24. Providing md5 here is equivalent to providing a guarantee for fault recovery }
    { Medium Big data will only calculate md5 when submitting and repairing the database. There will be a slight delay in calculating md5 when submitting, but the impact will be slight }
    FMD5: TMD5; // MD5 of the payload – computed on post/update.
  public
    property Owner_Large_Marshal: TZDB2_Large read FOwner_Large_Marshal;
    property Sequence_ID: Int64 read FSequence_ID write FSequence_ID;
    property MD5: TMD5 read FMD5 write FMD5;
    constructor Create(); override;
    destructor Destroy; override;
    { When data is removed }
    { If a lot of data is bound, it is necessary to delete the binding together }
    procedure Do_Remove(); override; // Removes from sequence pool.
    { Encoding data body -> Store physical data of inverted database }
    { Programming can be done through external interfaces }
    function Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64; virtual; // Prepends Sequence_ID and MD5.
    { Decode the original data from the database and return the original data body, excluding Sequence_ID, MD5 }
    { Decoding returns TMS64 in Mapping mode without copying }
    { When data is opened, Data_Source's data is a block block block, while other scenario data_Source is the complete data }
    { Programming can be done through external interfaces }
    function Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64; virtual; // Extracts Sequence_ID and MD5 if Update_=True.
    { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
    procedure Encode_External_Header_Data(Data_Source: TMem64); virtual; // Writes Sequence_ID and MD5 to external header.
    procedure Decode_External_Header_Data(Data_Source: TMem64); virtual; // Reads Sequence_ID and MD5 from external header.
  end;

  { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
  { When the data volume is large, a dataset contains dozens or hundreds of small databases. During disk operation, disk pre reads will be read in blocks, which greatly consumes HDD read time }
  { Expanding the data header is to gather thousands of fragmented databases and read them all at once, thereby improving the startup efficiency of the database. At the same time, pre reading also requires higher memory requirements }
  { Pre reading technology can improve data loading efficiency in the vast majority of hdd systems }
  TS_Th_Engine_Marshal = class(TZDB2_Th_Engine_Marshal) // Marshal for Small data engine pool.
  public
    Owner_Large_Marshal: TZDB2_Large; // Owning TZDB2_Large – assigned by TZDB2_Large constructor.
    // data event
    procedure Do_Add_Data(Sender: TZDB2_Th_Engine_Data); override; // Sets FOwner_Large_Marshal of the data.
    procedure Do_Remove_Data(Sender: TZDB2_Th_Engine_Data); override; // No-op.
    // flush-build external-header backcall api
    procedure Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64); override; // Writes external header data for all instances in Flush_Instance_Pool.
    // user
    procedure Do_Extract_Th_Eng(ThSender: TCompute); virtual; // Worker thread to decode external header for one engine.
    procedure Extract_External_Header(var Extract_Done: Boolean); virtual; // Extracts external headers from all engines in parallel.
    function Begin_Custom_Build: TZDB2_Th_Engine; virtual; // Creates a new engine instance.
    function End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean; virtual; // Builds the engine with Current_Data_Class.
  end;

  { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
  { When the data volume is large, a dataset contains dozens or hundreds of small databases. During disk operation, disk pre reads will be read in blocks, which greatly consumes HDD read time }
  { Expanding the data header is to gather thousands of fragmented databases and read them all at once, thereby improving the startup efficiency of the database. At the same time, pre reading also requires higher memory requirements }
  { Pre reading technology can improve data loading efficiency in the vast majority of hdd systems }
  TM_Th_Engine_Marshal = class(TZDB2_Th_Engine_Marshal) // Marshal for Medium data engine pool.
  public
    Owner_Large_Marshal: TZDB2_Large; // Owning TZDB2_Large – assigned by TZDB2_Large constructor.
    // data event
    procedure Do_Add_Data(Sender: TZDB2_Th_Engine_Data); override; // Sets FOwner_Large_Marshal.
    procedure Do_Remove_Data(Sender: TZDB2_Th_Engine_Data); override; // No-op.
    // flush-build external-header backcall api
    procedure Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64); override; // Writes external header for medium data.
    // user
    procedure Do_Extract_Th_Eng(ThSender: TCompute); virtual; // Worker thread for medium external header extraction.
    procedure Extract_External_Header(var Extract_Done: Boolean); virtual; // Parallel extraction for medium.
    function Begin_Custom_Build: TZDB2_Th_Engine; virtual; // Creates new engine.
    function End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean; virtual; // Builds engine.
  end;

  { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
  { When the data volume is large, a dataset contains dozens or hundreds of small databases. During disk operation, disk pre reads will be read in blocks, which greatly consumes HDD read time }
  { Expanding the data header is to gather thousands of fragmented databases and read them all at once, thereby improving the startup efficiency of the database. At the same time, pre reading also requires higher memory requirements }
  { Pre reading technology can improve data loading efficiency in the vast majority of hdd systems }
  TL_Th_Engine_Marshal = class(TZDB2_Th_Engine_Marshal) // Marshal for Large data engine pool.
  public
    Owner_Large_Marshal: TZDB2_Large; // Owning TZDB2_Large – assigned by TZDB2_Large constructor.
    // data event
    procedure Do_Add_Data(Sender: TZDB2_Th_Engine_Data); override; // Sets FOwner_Large_Marshal.
    procedure Do_Remove_Data(Sender: TZDB2_Th_Engine_Data); override; // No-op.
    // flush-build external-header backcall api
    procedure Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64); override; // Writes external header for large data.
    // user
    procedure Do_Extract_Th_Eng(ThSender: TCompute); virtual; // Worker thread for large external header extraction.
    procedure Extract_External_Header(var Extract_Done: Boolean); virtual; // Parallel extraction for large.
    function Begin_Custom_Build: TZDB2_Th_Engine; virtual; // Creates new engine.
    function End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean; virtual; // Builds engine.
  end;

  TS_Th_Engine_Marshal_Class = class of TS_Th_Engine_Marshal;
  TM_Th_Engine_Marshal_Class = class of TM_Th_Engine_Marshal;
  TL_Th_Engine_Marshal_Class = class of TL_Th_Engine_Marshal;

  TZDB2_Large = class(TCore_Object_Intermediate) // Main large-scale database manager class.
  private
    { Linear lock }
    FCritical: TCritical; // Lock for thread safety – created by constructor.

    { Active batch Post instances }
    FBatch_Post_Num: Integer; // Number of active batch bridges – incremented/decremented by batch bridge constructor/destructor.

    { Sequence seed }
    FCurrent_S_DB_Sequence_ID: Int64; // Next sequence ID for Small data – initialized to 1, incremented on each new small data creation.
    FCurrent_M_DB_Sequence_ID: Int64; // Next sequence ID for Medium data – initialized to 1, incremented on each new medium data creation.
    FCurrent_L_DB_Sequence_ID: Int64; // Next sequence ID for Large data – initialized to 1, incremented on each new large data creation.

    { Interface data Class }
    FSmall_Data_Class: TZDB2_Custom_Small_Data_Class; // Class type for creating small data instances – set by constructor or Set_Small_Data_Class.
    FMedium_Data_Class: TZDB2_Custom_Medium_Data_Class; // Class type for creating medium data instances – set by constructor or Set_Medium_Data_Class.
    FLarge_Data_Class: TZDB2_Custom_Large_Data_Class; // Class type for creating large data instances – set by constructor or Set_Large_Data_Class.

    { Interface engine Class }
    FS_Th_Engine_Marshal_Class: TS_Th_Engine_Marshal_Class; // Class type for small engine marshal – set by constructor.
    FM_Th_Engine_Marshal_Class: TM_Th_Engine_Marshal_Class; // Class type for medium engine marshal – set by constructor.
    FL_Th_Engine_Marshal_Class: TL_Th_Engine_Marshal_Class; // Class type for large engine marshal – set by constructor.

    { Small data is suitable for traversal, providing indexes for medium to large size data, and preparing for rapid expansion }
    { Small databases can be packaged and run on terminals }
    { A small database usually needs one sub database. If the number of a single database is greater than 10 million, open another database and go through a loop }
    { Small storage block of approximately 1KB, single library storage limit of 1.5TB }
    { Save logs, run device status, and use small data }
    { Type aliases in the script: 'Small', 'Tiny', 'Little', 'S',' Lv1 ',' 1 ' }
    FS_DB: TS_Th_Engine_Marshal; // Marshal instance for small data – created by constructor.
    FS_DB_Sequence_Pool: TZDB2_Custom_Small_Sequence_ID_Pool; // Sequence ID pool for small data – created by constructor, populated during rebuild and on creation.

    { Medium data is not suitable for traversal, usually positioned around 10TB. If traversing 10TB, memory needs to reach 10TB, otherwise the efficiency is extremely low }
    { Chinese databases can be packaged and run on terminals }
    { The size of the medium data sub library should not exceed the number of super threads/2. Based on the access density, if the density is low, such as each read and write volume is not high, then a large number of 100 can be opened }
    { Small storage blocks are approximately 8KB, with a single library storage limit of 15TB }
    { Saving small files such as images, using data }
    { Type aliases in the script: 'Default', 'Medium', 'Middle', 'M', 'Lv2', '2' }
    FM_DB: TM_Th_Engine_Marshal; // Marshal instance for medium data – created by constructor.
    FM_DB_Sequence_Pool: TZDB2_Custom_Medium_Sequence_ID_Pool; // Sequence ID pool for medium data – created by constructor.

    { Large databases support petabyte level up storage, and do not directly support traversal }
    { The database in can only run on the server side }
    { The large database is an infinite sub database support mechanism. The more sub databases, the higher the requirement for CPU }
    { Small storage block 64KB, single library storage limit 100TB }
    { Store video, compressed package, AI data set, and use Big data }
    { Type aliases in the script: 'Large', 'Big', 'Huge', 'L', 'Lv3', '3' }
    FL_DB: TL_Th_Engine_Marshal; // Marshal instance for large data – created by constructor.
    FL_DB_Sequence_Pool: TZDB2_Custom_Large_Sequence_ID_Pool; // Sequence ID pool for large data – created by constructor.

    { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
    { When the data volume is large, a dataset contains dozens or hundreds of small databases. During disk operation, disk pre reads will be read in blocks, which greatly consumes HDD read time }
    { Expanding the data header is to gather thousands of fragmented databases and read them all at once, thereby improving the startup efficiency of the database. At the same time, pre reading also requires higher memory requirements }
    { Pre reading technology can improve data loading efficiency in the vast majority of hdd systems }
    FS_DB_Engine_External_Header_Optimzied_Technology: Boolean; // Enable external header optimization for Small DB – set by user (default False).
    FM_DB_Engine_External_Header_Optimzied_Technology: Boolean; // Enable external header optimization for Medium DB – set by user (default False).
    FL_DB_Engine_External_Header_Optimzied_Technology: Boolean; // Enable external header optimization for Large DB – set by user (default False).

    { Interface Class }
    procedure Set_Small_Data_Class(const Value: TZDB2_Custom_Small_Data_Class); // Sets the small data class and updates the marshal's Current_Data_Class.
    procedure Set_Medium_Data_Class(const Value: TZDB2_Custom_Medium_Data_Class); // Sets the medium data class.
    procedure Set_Large_Data_Class(const Value: TZDB2_Custom_Large_Data_Class); // Sets the large data class.
  public
    { Interface Class }
    property Small_Data_Class: TZDB2_Custom_Small_Data_Class read FSmall_Data_Class write Set_Small_Data_Class;
    property Medium_Data_Class: TZDB2_Custom_Medium_Data_Class read FMedium_Data_Class write Set_Medium_Data_Class;
    property Large_Data_Class: TZDB2_Custom_Large_Data_Class read FLarge_Data_Class write Set_Large_Data_Class;

    { Small data is suitable for traversal, providing indexes for medium to large size data, and preparing for rapid expansion }
    { Small databases can be packaged and run on terminals }
    { A small database usually needs one sub database. If the number of a single database is greater than 10 million, open another database and go through a loop }
    { Small storage block of approximately 1KB, single library storage limit of 1.5TB }
    { Save logs, run device status, and use small data }
    { Type aliases in the script: 'Small', 'Tiny', 'Little', 'S',' Lv1 ',' 1 ' }
    property S_DB: TS_Th_Engine_Marshal read FS_DB; // Access to the Small DB marshal.
    property S_DB_Sequence_Pool: TZDB2_Custom_Small_Sequence_ID_Pool read FS_DB_Sequence_Pool; // Access to Small sequence pool.

    { Medium data is not suitable for traversal, usually positioned around 10TB. If traversing 10TB, memory needs to reach 10TB, otherwise the efficiency is extremely low }
    { Chinese databases can be packaged and run on terminals }
    { The size of the medium data cannot exceed the number of threads/2. Based on the access density, if the density is low, such as each read/write volume is not high, then a large number of threads can be opened, up to 100 can be opened }
    { Small storage blocks are approximately 8KB, with a single library storage limit of 15TB }
    { Saving small files such as images, using data }
    { Type aliases in the script: 'Default', 'Medium', 'Middle', 'M', 'Lv2', '2' }
    property M_DB: TM_Th_Engine_Marshal read FM_DB; // Access to the Medium DB marshal.
    property M_DB_Sequence_Pool: TZDB2_Custom_Medium_Sequence_ID_Pool read FM_DB_Sequence_Pool; // Access to Medium sequence pool.

    { Large databases support petabyte level up storage, and do not directly support traversal }
    { The database in can only run on the server side }
    { The large database is an infinite sub database support mechanism. The more sub databases, the higher the requirement for CPU }
    { Small storage block 64KB, single library storage limit 100TB }
    { Store video, compressed package, AI data set, and use Big data }
    { Type aliases in the script: 'Large', 'Big', 'Huge', 'L', 'Lv3', '3' }
    property L_DB: TL_Th_Engine_Marshal read FL_DB; // Access to the Large DB marshal.
    property L_DB_Sequence_Pool: TZDB2_Custom_Large_Sequence_ID_Pool read FL_DB_Sequence_Pool; // Access to Large sequence pool.

    { Active batch Post instances }
    property Batch_Post_Num: Integer read FBatch_Post_Num; // Number of active batch bridges.
    property Post_Batch_Num: Integer read FBatch_Post_Num; // Alias.

    constructor Create(); overload; // Default constructor with standard data classes.
    constructor Create(
      Small_Data_Class_: TZDB2_Custom_Small_Data_Class;
      Medium_Data_Class_: TZDB2_Custom_Medium_Data_Class;
      Large_Data_Class_: TZDB2_Custom_Large_Data_Class
      ); overload; // Constructor with custom data classes.
    constructor Create(
      Small_Data_Class_: TZDB2_Custom_Small_Data_Class;
      Medium_Data_Class_: TZDB2_Custom_Medium_Data_Class;
      Large_Data_Class_: TZDB2_Custom_Large_Data_Class;
      S_Th_Engine_Marshal_Class_: TS_Th_Engine_Marshal_Class;
      M_Th_Engine_Marshal_Class_: TM_Th_Engine_Marshal_Class;
      L_Th_Engine_Marshal_Class_: TL_Th_Engine_Marshal_Class
      ); overload; // Constructor with custom data classes and marshal classes.
    destructor Destroy; override;

    { Creating or opening a database using a script }
    { Root_Path stores the root directory of the database, where many database files will be stored }
    { If the database 'database' value does not specify a drive+directory, the root directory will be used to place }
    { If the database 'database' value specifies a drive+directory, the data will be stored in a specific location }
    { If the database 'database' value is empty, it will be stored directly in memory }
    procedure Build_DB_From_Script(Root_Path_: U_String; te: TTextDataEngine; OnlyRead_: Boolean); virtual; // Builds the three DBs from a configuration script.
    { Generate Script Template }
    class function Make_Script(Name_: U_String; S_DB_Num, M_DB_Num, L_DB_Num: Integer; Cipher_Security_: TCipherSecurity): TTextDataEngine; // Creates a script for a multi-engine setup.
    { Automated API: Opening a Database from a Script File }
    function Open_DB(script_conf_: U_String): Boolean; overload; // Opens database from a script file (read-write).
    function Open_DB(script_conf_: U_String; OnlyRead_: Boolean): Boolean; overload; // Opens database from a script file with optional read-only.
    { Automated API: Closing Database }
    procedure Close_DB; virtual; // Closes all three databases, flushes, and releases resources.

    { Extended Data Header Technology for Solving the Decentralized performance Problem of hdd }
    { TZDB2_Custom_Small_Data }
    property S_DB_Engine_External_Header_Optimzied_Technology: Boolean read FS_DB_Engine_External_Header_Optimzied_Technology write FS_DB_Engine_External_Header_Optimzied_Technology; // Enable/disable external header optimization for Small DB.
    procedure Do_Th_S_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for full-load of small data.
    procedure Extract_S_DB_Full(ThNum_: Integer); virtual; // Extracts all small data (full).
    procedure Do_Th_S_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64); virtual; // Callback for block-load of small data.
    procedure Extract_S_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer); virtual; // Extracts small data by block.
    procedure Do_Th_S_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for position-load of small data.
    procedure Extract_S_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64); virtual; // Extracts small data by position range.
    function Do_S_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer; virtual; // Sort comparator for small data by Sequence_ID.
    procedure Rebuild_S_DB_Requence; virtual; // Rebuilds small data sequence pool (sort by Sequence_ID).

    { TZDB2_Custom_Medium_Data }
    property M_DB_Engine_External_Header_Optimzied_Technology: Boolean read FM_DB_Engine_External_Header_Optimzied_Technology write FM_DB_Engine_External_Header_Optimzied_Technology; // Enable/disable external header optimization for Medium DB.
    procedure Do_Th_M_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for full-load of medium data.
    procedure Extract_M_DB_Full(ThNum_: Integer); virtual; // Extracts all medium data.
    procedure Do_Th_M_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64); virtual; // Callback for block-load of medium data.
    procedure Extract_M_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer); virtual; // Extracts medium data by block.
    procedure Do_Th_M_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for position-load of medium data.
    procedure Extract_M_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64); virtual; // Extracts medium data by position range.
    function Do_M_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer; virtual; // Sort comparator for medium data by Sequence_ID.
    procedure Rebuild_M_DB_Requence; virtual; // Rebuilds medium data sequence pool.

    { TZDB2_Custom_Large_Data }
    property L_DB_Engine_External_Header_Optimzied_Technology: Boolean read FL_DB_Engine_External_Header_Optimzied_Technology write FL_DB_Engine_External_Header_Optimzied_Technology; // Enable/disable external header optimization for Large DB.
    procedure Do_Th_L_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for full-load of large data.
    procedure Extract_L_DB_Full(ThNum_: Integer); virtual; // Extracts all large data.
    procedure Do_Th_L_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64); virtual; // Callback for block-load of large data.
    procedure Extract_L_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer); virtual; // Extracts large data by block.
    procedure Do_Th_L_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64); virtual; // Callback for position-load of large data.
    procedure Extract_L_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64); virtual; // Extracts large data by position range.
    function Do_L_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer; virtual; // Sort comparator for large data by Sequence_ID.
    procedure Rebuild_L_DB_Requence; virtual; // Rebuilds large data sequence pool.

    { Create a small data instance and generate an associated Sequence after creation_ID, data is empty and will not be immediately posted. Here, some custom programs can be made }
    { After completing the processing, manually post: Don't forget that each data requires MD5, refer to Post_Data_The internal implementation of methods like xxx is sufficient }
    function Create_Small_Data(): TZDB2_Custom_Small_Data; virtual; // Creates a small data instance with a new Sequence_ID (not yet saved).
    function Create_Medium_Data(): TZDB2_Custom_Medium_Data; virtual; // Creates a medium data instance.
    function Create_Large_Data(): TZDB2_Custom_Large_Data; virtual; // Creates a large data instance.

    { Save small data. each post will automatically add a sequence ID+MD5 header (24 bytes) to the data }
    function Post_Data_To_S_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Small_Data; virtual; // Posts small data asynchronously, returns instance.
    function Post_Data_To_S_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Small_Data; virtual; // Posts with C-style callback.
    function Post_Data_To_S_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Small_Data; virtual; // Posts with method callback.
    function Post_Data_To_S_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Small_Data; virtual; // Posts with nested/reference callback.
    { In storage data, each post will automatically add a sequence ID+MD5 header (24 bytes) to the data }
    function Post_Data_To_M_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Medium_Data; virtual; // Posts medium data.
    function Post_Data_To_M_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Medium_Data; virtual; // Posts with C callback.
    function Post_Data_To_M_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Medium_Data; virtual; // Posts with method callback.
    function Post_Data_To_M_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Medium_Data; virtual; // Posts with nested callback.
    { To store Big data, each post will automatically add a sequence id+md5 header (24 byte) to the data }
    function Post_Data_To_L_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Large_Data; virtual; // Posts large data.
    function Post_Data_To_L_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Large_Data; virtual; // Posts with C callback.
    function Post_Data_To_L_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Large_Data; virtual; // Posts with method callback.
    function Post_Data_To_L_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Large_Data; virtual; // Posts with nested callback.
    { Batch submission of data: Batch submission ensures integrity. If one of the batch data is incorrect, the current batch data will be deleted }
    { Batch submission of data is also the most efficient way to submit correlated data, without using waiting threads or blocking TZDB2_Th_Queue }
    function Batch_Post(): TZDB2_Custom_Batch_Data_Post_Bridge; virtual; // Creates a batch bridge (no callback).
    function Batch_Post_C(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_C): TZDB2_Custom_Batch_Data_Post_Bridge; virtual; // Creates a batch bridge with C callback.
    function Batch_Post_M(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_M): TZDB2_Custom_Batch_Data_Post_Bridge; virtual; // Creates a batch bridge with method callback.
    function Batch_Post_P(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_P): TZDB2_Custom_Batch_Data_Post_Bridge; virtual; // Creates a batch bridge with nested callback.
    procedure Wait_Batch_Post(); virtual; // Waits until all active batch bridges finish.

    { Modify data, }
    { Wait_Modify_: Waiting for modification to return }
    { AutoFree_: Whether the modification is successful or not, release the data after completion }
    procedure Modify_S_DB_Data(Inst_: TZDB2_Custom_Small_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean); virtual; // Modifies small data (synchronous or async).
    procedure Modify_M_DB_Data(Inst_: TZDB2_Custom_Medium_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean); virtual; // Modifies medium data.
    procedure Modify_L_DB_Data(Inst_: TZDB2_Custom_Large_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean); virtual; // Modifies large data.

    { Processing the recycling system, which can be executed at a high frequency }
    procedure Check_Recycle_Pool; virtual; // Calls Check_Recycle_Pool on all three marashals.
    { To handle the main loop, this method should avoid frequent execution. It is recommended to run it every 5 minutes and start a thread to run it, as the main loop may get stuck after too many entries }
    function Progress: Integer; virtual; // Calls Progress on all three marashals and returns number of engines that progressed.
    { Perform backup }
    procedure Backup(Reserve_: Word); virtual; // Backs up all three databases, keeping Reserve_ copies.
    procedure Backup_If_No_Exists(); virtual; // Creates backup only if no backup exists.
    { Clear cache }
    procedure Flush(WaitQueue_: Boolean); virtual; // Flushes all three databases.
    function Flush_Is_Busy: Boolean; // Returns True if any of the three DBs is busy flushing.
    { database space state }
    function Database_Size: Int64; // Total data size of all three databases.
    function Database_Physics_Size: Int64; // Total physical size of all three databases.
    { data num }
    function Total: NativeInt; // Total number of data objects across all three databases.
    { task queue }
    function QueueNum: NativeInt; // Total number of pending commands across all engines.
    { solved for discontinuous space. }
    function Fragment_Buffer_Num: Int64; // Total fragment buffer count.
    function Fragment_Buffer_Memory: Int64; // Total fragment buffer memory usage.

    { test case }
    class procedure Do_Test_Batch_Post(Eng_: TZDB2_Large);
    class procedure Do_Test_Post(Eng_: TZDB2_Large);
    class procedure Do_Test_Get_Data(Eng_: TZDB2_Large);
    class procedure Test();
  end;

implementation

procedure TZDB2_Custom_Batch_Data_Post_Bridge.Do_Save_Data_Result(Sender: TZDB2_Th_Engine_Data; Successed: Boolean);
begin
  FCritical.Lock;
  if Successed then
    begin
      Inc(Successed_Num);
      Done_Pool.Add(Sender);
    end
  else
    begin
      Inc(Error_Num);
      if Sender.SaveFailed_Do_Remove then
          Post_Pool.Remove_T(Sender);
    end;
  FCritical.UnLock;
  Do_Check_Post_Done();
end;

procedure TZDB2_Custom_Batch_Data_Post_Bridge.Do_Check_Post_Done;
begin
  FCritical.Lock;
  if (Post_Busy <= 0) and (Successed_Num + Error_Num >= Total_Post) then
      TCompute.RunM_NP(Do_All_Post_Done);
  FCritical.UnLock;
end;

procedure TZDB2_Custom_Batch_Data_Post_Bridge.Do_All_Post_Done;
begin
  try
    if Assigned(OnResult_C) then
        OnResult_C(Self);
    if Assigned(OnResult_M) then
        OnResult_M(Self);
    if Assigned(OnResult_P) then
        OnResult_P(Self);
  except
  end;

  if (Error_Do_Remove_Data) and (Error_Num > 0) then
    begin
      if Done_Pool.Num > 0 then
        begin
          with Done_Pool.Repeat_ do
            repeat
                Queue^.data.Remove(True);
            until not Next;
        end;
    end;

  DelayFreeObj(1.0, Self);
end;

constructor TZDB2_Custom_Batch_Data_Post_Bridge.Create(Owner_Large_DB_Engine_: TZDB2_Large);
begin
  if Owner_Large_DB_Engine_ = nil then
      RaiseInfo('error');
  inherited Create;
  Owner_Large_DB_Engine_.FCritical.Inc_(Owner_Large_DB_Engine_.FBatch_Post_Num);
  FCritical := TCritical.Create(ClassName + '.Critical');
  Total_Post := 0;
  Post_Busy := 0;
  FOwner_Large_Marshal := Owner_Large_DB_Engine_;
  Successed_Num := 0;
  Error_Num := 0;
  Error_Do_Remove_Data := True;
  Post_Pool := TZDB2_Custom_Data_Pool.Create;
  Done_Pool := TZDB2_Custom_Data_Pool.Create;
  OnResult_C := nil;
  OnResult_M := nil;
  OnResult_P := nil;
  User_Hash_Variants := THashVariantList.Create;
  User_Hash_Strings := THashStringList.Create;
end;

destructor TZDB2_Custom_Batch_Data_Post_Bridge.Destroy;
begin
  FOwner_Large_Marshal.FCritical.Dec_(FOwner_Large_Marshal.FBatch_Post_Num);
  DisposeObject(FCritical);
  DisposeObject(Post_Pool);
  DisposeObject(Done_Pool);
  DisposeObject(User_Hash_Variants);
  DisposeObject(User_Hash_Strings);
  inherited Destroy;
end;

procedure TZDB2_Custom_Batch_Data_Post_Bridge.Begin_Post;
begin
  FCritical.Inc_(Post_Busy);
end;

function TZDB2_Custom_Batch_Data_Post_Bridge.Post_Data_To_S_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Small_Data;
begin
  FCritical.Inc_(Total_Post);
  Result := FOwner_Large_Marshal.Post_Data_To_S_DB_M(data, AutoFree_, Do_Save_Data_Result);
end;

function TZDB2_Custom_Batch_Data_Post_Bridge.Post_Data_To_M_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Medium_Data;
begin
  FCritical.Inc_(Total_Post);
  Result := FOwner_Large_Marshal.Post_Data_To_M_DB_M(data, AutoFree_, Do_Save_Data_Result);
end;

function TZDB2_Custom_Batch_Data_Post_Bridge.Post_Data_To_L_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Large_Data;
begin
  FCritical.Inc_(Total_Post);
  Result := FOwner_Large_Marshal.Post_Data_To_L_DB_M(data, AutoFree_, Do_Save_Data_Result);
end;

procedure TZDB2_Custom_Batch_Data_Post_Bridge.End_Post;
begin
  FCritical.Dec_(Post_Busy);
  Do_Check_Post_Done();
end;

procedure TZDB2_Custom_Batch_Data_Post_Bridge.Done_Post;
begin
  FCritical.Dec_(Post_Busy);
  Do_Check_Post_Done();
end;

constructor TZDB2_Custom_Small_Data.Create;
begin
  inherited Create;
  FSequence_ID := 0;
  FMD5 := Null_MD5;
  FOwner_Large_Marshal := nil;
end;

destructor TZDB2_Custom_Small_Data.Destroy;
begin
  if FOwner_Large_Marshal <> nil then
    begin
      FOwner_Large_Marshal.FS_DB_Sequence_Pool.Delete(FSequence_ID);
    end;
  inherited Destroy;
end;

procedure TZDB2_Custom_Small_Data.Do_Remove();
begin
  { Remove reverse lookup structure }
  FOwner_Large_Marshal.S_DB_Sequence_Pool.Delete(FSequence_ID);
  { Remove associated medium Big data }
  inherited Do_Remove();
end;

function TZDB2_Custom_Small_Data.Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64;
begin
  Result := TMem64.Create;
  Result.Size := Data_Source.Size + 24;
  Result.Position := 0;
  Result.WriteInt64(FSequence_ID);
  Result.WriteMD5(FMD5);
  Result.WritePtr(Data_Source.Memory, Data_Source.Size);
  if AutoFree_ then
      DisposeObject(Data_Source);
end;

function TZDB2_Custom_Small_Data.Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64;
begin
  if Update_ then
    begin
      Data_Source.Position := 0;
      FSequence_ID := Data_Source.ReadInt64;
      FMD5 := Data_Source.ReadMD5;
    end
  else
      Data_Source.Position := 24;
  Result := TMS64.Create;
  Result.Mapping(Data_Source.PosAsPtr, Data_Source.Size - Data_Source.Position);
  Do_Ready;
end;

procedure TZDB2_Custom_Small_Data.Encode_External_Header_Data(Data_Source: TMem64);
begin
  Data_Source.WriteInt64(Sequence_ID);
  Data_Source.WriteMD5(MD5);
end;

procedure TZDB2_Custom_Small_Data.Decode_External_Header_Data(Data_Source: TMem64);
begin
  Sequence_ID := Data_Source.ReadInt64;
  MD5 := Data_Source.ReadMD5;
  Do_Ready;
end;

constructor TZDB2_Custom_Medium_Data.Create;
begin
  inherited Create;
  FSequence_ID := 0;
  FMD5 := Null_MD5;
  FOwner_Large_Marshal := nil;
end;

destructor TZDB2_Custom_Medium_Data.Destroy;
begin
  if FOwner_Large_Marshal <> nil then
    begin
      FOwner_Large_Marshal.FM_DB_Sequence_Pool.Delete(FSequence_ID);
    end;
  inherited Destroy;
end;

procedure TZDB2_Custom_Medium_Data.Do_Remove;
begin
  { Remove reverse lookup structure }
  FOwner_Large_Marshal.M_DB_Sequence_Pool.Delete(FSequence_ID);
  { Remove associated data }
  inherited Do_Remove();
end;

function TZDB2_Custom_Medium_Data.Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64;
begin
  Result := TMem64.Create;
  Result.Size := Data_Source.Size + 24;
  Result.Position := 0;
  Result.WriteInt64(FSequence_ID);
  Result.WriteMD5(FMD5);
  Result.WritePtr(Data_Source.Memory, Data_Source.Size);
  if AutoFree_ then
      DisposeObject(Data_Source);
end;

function TZDB2_Custom_Medium_Data.Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64;
begin
  if Update_ then
    begin
      Data_Source.Position := 0;
      FSequence_ID := Data_Source.ReadInt64;
      FMD5 := Data_Source.ReadMD5;
    end
  else
      Data_Source.Position := 24;
  Result := TMS64.Create;
  Result.Mapping(Data_Source.PosAsPtr, Data_Source.Size - Data_Source.Position);
  Do_Ready;
end;

procedure TZDB2_Custom_Medium_Data.Encode_External_Header_Data(Data_Source: TMem64);
begin
  Data_Source.WriteInt64(Sequence_ID);
  Data_Source.WriteMD5(MD5);
end;

procedure TZDB2_Custom_Medium_Data.Decode_External_Header_Data(Data_Source: TMem64);
begin
  Sequence_ID := Data_Source.ReadInt64;
  MD5 := Data_Source.ReadMD5;
  Do_Ready;
end;

constructor TZDB2_Custom_Large_Data.Create;
begin
  inherited Create;
  FSequence_ID := 0;
  FMD5 := Null_MD5;
  FOwner_Large_Marshal := nil;
end;

destructor TZDB2_Custom_Large_Data.Destroy;
begin
  if FOwner_Large_Marshal <> nil then
    begin
      FOwner_Large_Marshal.FL_DB_Sequence_Pool.Delete(FSequence_ID);
    end;
  inherited Destroy;
end;

procedure TZDB2_Custom_Large_Data.Do_Remove;
begin
  { Remove reverse lookup structure }
  FOwner_Large_Marshal.L_DB_Sequence_Pool.Delete(FSequence_ID);
  { Remove associated data }
  inherited Do_Remove();
end;

function TZDB2_Custom_Large_Data.Encode_To_ZDB2_Data(Data_Source: TMS64; AutoFree_: Boolean): TMem64;
begin
  Result := TMem64.Create;
  Result.Size := Data_Source.Size + 24;
  Result.Position := 0;
  Result.WriteInt64(FSequence_ID);
  Result.WriteMD5(FMD5);
  Result.WritePtr(Data_Source.Memory, Data_Source.Size);
  if AutoFree_ then
      DisposeObject(Data_Source);
end;

function TZDB2_Custom_Large_Data.Decode_From_ZDB2_Data(Data_Source: TMem64; Update_: Boolean): TMS64;
begin
  if Update_ then
    begin
      Data_Source.Position := 0;
      FSequence_ID := Data_Source.ReadInt64;
      FMD5 := Data_Source.ReadMD5;
    end
  else
      Data_Source.Position := 24;
  Result := TMS64.Create;
  Result.Mapping(Data_Source.PosAsPtr, Data_Source.Size - Data_Source.Position);
  Do_Ready;
end;

procedure TZDB2_Custom_Large_Data.Encode_External_Header_Data(Data_Source: TMem64);
begin
  Data_Source.WriteInt64(Sequence_ID);
  Data_Source.WriteMD5(MD5);
end;

procedure TZDB2_Custom_Large_Data.Decode_External_Header_Data(Data_Source: TMem64);
begin
  Sequence_ID := Data_Source.ReadInt64;
  MD5 := Data_Source.ReadMD5;
  Do_Ready;
end;

procedure TS_Th_Engine_Marshal.Do_Add_Data(Sender: TZDB2_Th_Engine_Data);
begin
  TZDB2_Custom_Small_Data(Sender).FOwner_Large_Marshal := Owner_Large_Marshal;
end;

procedure TS_Th_Engine_Marshal.Do_Remove_Data(Sender: TZDB2_Th_Engine_Data);
begin
end;

procedure TS_Th_Engine_Marshal.Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64);
var
  tmp: TMem64;
begin
  if Flush_Instance_Pool.Num <= 0 then
      exit;
  if not TZDB2_Large(Owner).S_DB_Engine_External_Header_Optimzied_Technology then
      exit;

  External_Header_Data_.Clear;
  External_Header_Data_.WriteInt64(Flush_Instance_Pool.Num);
  with Flush_Instance_Pool.Repeat_ do
    repeat
      External_Header_Data_.WriteInt32(Queue^.data.ID);
      tmp := TMem64.CustomCreate(1536);
      TZDB2_Custom_Small_Data(Queue^.data).Encode_External_Header_Data(tmp);
      External_Header_Data_.WriteInt32(tmp.Size);
      External_Header_Data_.WritePtr(tmp.Memory, tmp.Size);
      DisposeObject(tmp);
    until not Next;
end;

procedure TS_Th_Engine_Marshal.Do_Extract_Th_Eng(ThSender: TCompute);
var
  Eng_: TZDB2_Th_Engine;
  Error_Num: PInt64;
  num_: Int64;
  ID_: Integer;
  siz_: Integer;
  Inst_: TZDB2_Custom_Small_Data;
  tmp: TMem64;
begin
  Eng_ := ThSender.UserObject as TZDB2_Th_Engine;
  Error_Num := ThSender.UserData;

  Eng_.External_Header_Data.Position := 0;
  num_ := Eng_.External_Header_Data.ReadInt64;

  while num_ > 0 do
    begin
      ID_ := Eng_.External_Header_Data.ReadInt32;
      Inst_ := TZDB2_Custom_Small_Data(Eng_.Th_Engine_ID_Data_Pool[ID_]);
      if Inst_ = nil then
        begin
          AtomInc(Error_Num^);
          break;
        end;
      try
        siz_ := Eng_.External_Header_Data.ReadInt32;
        tmp := TMem64.Create;
        tmp.Mapping(Eng_.External_Header_Data.PosAsPtr, siz_);
        Inst_.Decode_External_Header_Data(tmp);
        DisposeObject(tmp);
        Eng_.External_Header_Data.Position := Eng_.External_Header_Data.Position + siz_;
      except
        AtomInc(Error_Num^);
        break;
      end;
      dec(num_);
    end;
end;

procedure TS_Th_Engine_Marshal.Extract_External_Header(var Extract_Done: Boolean);
var
  Error_Num: Int64;

  function Check_External_Header: NativeInt;
  begin
    { external-header optimize tech }
    Result := 0;
    if Engine_Pool.Num > 0 then
      with Engine_Pool.Repeat_ do
        repeat
          if Queue^.data.External_Header_Data.Size >= 8 then
              Inc(Result);
        until not Next;
  end;

var
  Signal_: TBool_Signal_Array;
begin
  Extract_Done := False;
  if not TZDB2_Large(Owner).S_DB_Engine_External_Header_Optimzied_Technology then
      exit;
  Error_Num := 0;
  if Check_External_Header <> Engine_Pool.Num then
      exit;
  if Engine_Pool.Num > 0 then
    begin
      SetLength(Signal_, Engine_Pool.Num);
      with Engine_Pool.Repeat_ do
        repeat
            TCompute.RunM(@Error_Num, Queue^.data, Do_Extract_Th_Eng, @Signal_[I__], nil);
        until not Next;
      Wait_All_Signal(Signal_, False);
    end;
  Extract_Done := Error_Num = 0;
end;

function TS_Th_Engine_Marshal.Begin_Custom_Build: TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(Self);
end;

function TS_Th_Engine_Marshal.End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean;
begin
  Eng_.Build(Current_Data_Class);
  Result := Eng_.Ready;
end;

procedure TM_Th_Engine_Marshal.Do_Add_Data(Sender: TZDB2_Th_Engine_Data);
begin
  TZDB2_Custom_Medium_Data(Sender).FOwner_Large_Marshal := Owner_Large_Marshal;
end;

procedure TM_Th_Engine_Marshal.Do_Remove_Data(Sender: TZDB2_Th_Engine_Data);
begin
end;

procedure TM_Th_Engine_Marshal.Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64);
var
  tmp: TMem64;
begin
  if Flush_Instance_Pool.Num <= 0 then
      exit;
  if not TZDB2_Large(Owner).M_DB_Engine_External_Header_Optimzied_Technology then
      exit;

  External_Header_Data_.Clear;
  External_Header_Data_.WriteInt64(Flush_Instance_Pool.Num);
  with Flush_Instance_Pool.Repeat_ do
    repeat
      External_Header_Data_.WriteInt32(Queue^.data.ID);
      tmp := TMem64.CustomCreate(1536);
      TZDB2_Custom_Medium_Data(Queue^.data).Encode_External_Header_Data(tmp);
      External_Header_Data_.WriteInt32(tmp.Size);
      External_Header_Data_.WritePtr(tmp.Memory, tmp.Size);
      DisposeObject(tmp);
    until not Next;
end;

procedure TM_Th_Engine_Marshal.Do_Extract_Th_Eng(ThSender: TCompute);
var
  Eng_: TZDB2_Th_Engine;
  Error_Num: PInt64;
  num_: Int64;
  ID_: Integer;
  siz_: Integer;
  Inst_: TZDB2_Custom_Medium_Data;
  tmp: TMem64;
begin
  Eng_ := ThSender.UserObject as TZDB2_Th_Engine;
  Error_Num := ThSender.UserData;

  Eng_.External_Header_Data.Position := 0;
  num_ := Eng_.External_Header_Data.ReadInt64;

  while num_ > 0 do
    begin
      ID_ := Eng_.External_Header_Data.ReadInt32;
      Inst_ := TZDB2_Custom_Medium_Data(Eng_.Th_Engine_ID_Data_Pool[ID_]);
      if Inst_ = nil then
        begin
          AtomInc(Error_Num^);
          break;
        end;
      try
        siz_ := Eng_.External_Header_Data.ReadInt32;
        tmp := TMem64.Create;
        tmp.Mapping(Eng_.External_Header_Data.PosAsPtr, siz_);
        Inst_.Decode_External_Header_Data(tmp);
        DisposeObject(tmp);
        Eng_.External_Header_Data.Position := Eng_.External_Header_Data.Position + siz_;
      except
        AtomInc(Error_Num^);
        break;
      end;
      dec(num_);
    end;
end;

procedure TM_Th_Engine_Marshal.Extract_External_Header(var Extract_Done: Boolean);
var
  Error_Num: Int64;

  function Check_External_Header: NativeInt;
  begin
    { external-header optimize tech }
    Result := 0;
    if Engine_Pool.Num > 0 then
      with Engine_Pool.Repeat_ do
        repeat
          if Queue^.data.External_Header_Data.Size >= 8 then
              Inc(Result);
        until not Next;
  end;

var
  Signal_: TBool_Signal_Array;
begin
  Extract_Done := False;
  if not TZDB2_Large(Owner).M_DB_Engine_External_Header_Optimzied_Technology then
      exit;
  Error_Num := 0;
  if Check_External_Header <> Engine_Pool.Num then
      exit;
  if Engine_Pool.Num > 0 then
    begin
      SetLength(Signal_, Engine_Pool.Num);
      with Engine_Pool.Repeat_ do
        repeat
            TCompute.RunM(@Error_Num, Queue^.data, Do_Extract_Th_Eng, @Signal_[I__], nil);
        until not Next;
      Wait_All_Signal(Signal_, False);
    end;
  Extract_Done := Error_Num = 0;
end;

function TM_Th_Engine_Marshal.Begin_Custom_Build: TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(Self);
end;

function TM_Th_Engine_Marshal.End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean;
begin
  Eng_.Build(Current_Data_Class);
  Result := Eng_.Ready;
end;

procedure TL_Th_Engine_Marshal.Do_Add_Data(Sender: TZDB2_Th_Engine_Data);
begin
  TZDB2_Custom_Large_Data(Sender).FOwner_Large_Marshal := Owner_Large_Marshal;
end;

procedure TL_Th_Engine_Marshal.Do_Remove_Data(Sender: TZDB2_Th_Engine_Data);
begin
end;

procedure TL_Th_Engine_Marshal.Prepare_Flush_External_Header(Th_Engine_: TZDB2_Th_Engine; var Sequence_Table: TZDB2_BlockHandle; Flush_Instance_Pool: TZDB2_Th_Engine_Data_Instance_Pool; External_Header_Data_: TMem64);
var
  tmp: TMem64;
begin
  if Flush_Instance_Pool.Num <= 0 then
      exit;
  if not TZDB2_Large(Owner).L_DB_Engine_External_Header_Optimzied_Technology then
      exit;

  External_Header_Data_.Clear;
  External_Header_Data_.WriteInt64(Flush_Instance_Pool.Num);
  with Flush_Instance_Pool.Repeat_ do
    repeat
      External_Header_Data_.WriteInt32(Queue^.data.ID);
      tmp := TMem64.CustomCreate(1536);
      TZDB2_Custom_Large_Data(Queue^.data).Encode_External_Header_Data(tmp);
      External_Header_Data_.WriteInt32(tmp.Size);
      External_Header_Data_.WritePtr(tmp.Memory, tmp.Size);
      DisposeObject(tmp);
    until not Next;
end;

procedure TL_Th_Engine_Marshal.Do_Extract_Th_Eng(ThSender: TCompute);
var
  Eng_: TZDB2_Th_Engine;
  Error_Num: PInt64;
  num_: Int64;
  ID_: Integer;
  siz_: Integer;
  Inst_: TZDB2_Custom_Large_Data;
  tmp: TMem64;
begin
  Eng_ := ThSender.UserObject as TZDB2_Th_Engine;
  Error_Num := ThSender.UserData;

  Eng_.External_Header_Data.Position := 0;
  num_ := Eng_.External_Header_Data.ReadInt64;

  while num_ > 0 do
    begin
      ID_ := Eng_.External_Header_Data.ReadInt32;
      Inst_ := TZDB2_Custom_Large_Data(Eng_.Th_Engine_ID_Data_Pool[ID_]);
      if Inst_ = nil then
        begin
          AtomInc(Error_Num^);
          break;
        end;
      try
        siz_ := Eng_.External_Header_Data.ReadInt32;
        tmp := TMem64.Create;
        tmp.Mapping(Eng_.External_Header_Data.PosAsPtr, siz_);
        Inst_.Decode_External_Header_Data(tmp);
        DisposeObject(tmp);
        Eng_.External_Header_Data.Position := Eng_.External_Header_Data.Position + siz_;
      except
        AtomInc(Error_Num^);
        break;
      end;
      dec(num_);
    end;
end;

procedure TL_Th_Engine_Marshal.Extract_External_Header(var Extract_Done: Boolean);
var
  Error_Num: Int64;

  function Check_External_Header: NativeInt;
  begin
    { external-header optimize tech }
    Result := 0;
    if Engine_Pool.Num > 0 then
      with Engine_Pool.Repeat_ do
        repeat
          if Queue^.data.External_Header_Data.Size >= 8 then
              Inc(Result);
        until not Next;
  end;

var
  Signal_: TBool_Signal_Array;
begin
  Extract_Done := False;
  if not TZDB2_Large(Owner).L_DB_Engine_External_Header_Optimzied_Technology then
      exit;
  Error_Num := 0;
  if Check_External_Header <> Engine_Pool.Num then
      exit;
  if Engine_Pool.Num > 0 then
    begin
      SetLength(Signal_, Engine_Pool.Num);
      with Engine_Pool.Repeat_ do
        repeat
            TCompute.RunM(@Error_Num, Queue^.data, Do_Extract_Th_Eng, @Signal_[I__], nil);
        until not Next;
      Wait_All_Signal(Signal_, False);
    end;
  Extract_Done := Error_Num = 0;
end;

function TL_Th_Engine_Marshal.Begin_Custom_Build: TZDB2_Th_Engine;
begin
  Result := TZDB2_Th_Engine.Create(Self);
end;

function TL_Th_Engine_Marshal.End_Custom_Build(Eng_: TZDB2_Th_Engine): Boolean;
begin
  Eng_.Build(Current_Data_Class);
  Result := Eng_.Ready;
end;

procedure TZDB2_Large.Set_Small_Data_Class(const Value: TZDB2_Custom_Small_Data_Class);
begin
  FSmall_Data_Class := Value;
  FS_DB.Current_Data_Class := FSmall_Data_Class;
end;

procedure TZDB2_Large.Set_Medium_Data_Class(const Value: TZDB2_Custom_Medium_Data_Class);
begin
  FMedium_Data_Class := Value;
  FM_DB.Current_Data_Class := FMedium_Data_Class;
end;

procedure TZDB2_Large.Set_Large_Data_Class(const Value: TZDB2_Custom_Large_Data_Class);
begin
  FLarge_Data_Class := Value;
  FL_DB.Current_Data_Class := FLarge_Data_Class;
end;

constructor TZDB2_Large.Create();
begin
  inherited Create;
  FBatch_Post_Num := 0;
  FCurrent_S_DB_Sequence_ID := 1;
  FCurrent_M_DB_Sequence_ID := 1;
  FCurrent_L_DB_Sequence_ID := 1;
  FCritical := TCritical.Create(ClassName + '.Critical');

  FSmall_Data_Class := TZDB2_Custom_Small_Data;
  FMedium_Data_Class := TZDB2_Custom_Medium_Data;
  FLarge_Data_Class := TZDB2_Custom_Large_Data;

  FS_Th_Engine_Marshal_Class := TS_Th_Engine_Marshal;
  FM_Th_Engine_Marshal_Class := TM_Th_Engine_Marshal;
  FL_Th_Engine_Marshal_Class := TL_Th_Engine_Marshal;

  FS_DB := FS_Th_Engine_Marshal_Class.Create(Self);
  FS_DB.Current_Data_Class := FSmall_Data_Class;
  FS_DB.Owner_Large_Marshal := Self;
  FS_DB_Sequence_Pool := TZDB2_Custom_Small_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FM_DB := FM_Th_Engine_Marshal_Class.Create(Self);
  FM_DB.Current_Data_Class := FMedium_Data_Class;
  FM_DB.Owner_Large_Marshal := Self;
  FM_DB_Sequence_Pool := TZDB2_Custom_Medium_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FL_DB := FL_Th_Engine_Marshal_Class.Create(Self);
  FL_DB.Current_Data_Class := FLarge_Data_Class;
  FL_DB.Owner_Large_Marshal := Self;
  FL_DB_Sequence_Pool := TZDB2_Custom_Large_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FS_DB_Engine_External_Header_Optimzied_Technology := False;
  FM_DB_Engine_External_Header_Optimzied_Technology := False;
  FL_DB_Engine_External_Header_Optimzied_Technology := False;
end;

constructor TZDB2_Large.Create(
  Small_Data_Class_: TZDB2_Custom_Small_Data_Class;
  Medium_Data_Class_: TZDB2_Custom_Medium_Data_Class;
  Large_Data_Class_: TZDB2_Custom_Large_Data_Class);
begin
  inherited Create;
  FBatch_Post_Num := 0;
  FCurrent_S_DB_Sequence_ID := 1;
  FCurrent_M_DB_Sequence_ID := 1;
  FCurrent_L_DB_Sequence_ID := 1;
  FCritical := TCritical.Create(ClassName + '.Critical');

  FSmall_Data_Class := Small_Data_Class_;
  FMedium_Data_Class := Medium_Data_Class_;
  FLarge_Data_Class := Large_Data_Class_;

  FS_Th_Engine_Marshal_Class := TS_Th_Engine_Marshal;
  FM_Th_Engine_Marshal_Class := TM_Th_Engine_Marshal;
  FL_Th_Engine_Marshal_Class := TL_Th_Engine_Marshal;

  FS_DB := FS_Th_Engine_Marshal_Class.Create(Self);
  FS_DB.Current_Data_Class := FSmall_Data_Class;
  FS_DB.Owner_Large_Marshal := Self;
  FS_DB_Sequence_Pool := TZDB2_Custom_Small_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FM_DB := FM_Th_Engine_Marshal_Class.Create(Self);
  FM_DB.Current_Data_Class := FMedium_Data_Class;
  FM_DB.Owner_Large_Marshal := Self;
  FM_DB_Sequence_Pool := TZDB2_Custom_Medium_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FL_DB := FL_Th_Engine_Marshal_Class.Create(Self);
  FL_DB.Current_Data_Class := FLarge_Data_Class;
  FL_DB.Owner_Large_Marshal := Self;
  FL_DB_Sequence_Pool := TZDB2_Custom_Large_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FS_DB_Engine_External_Header_Optimzied_Technology := False;
  FM_DB_Engine_External_Header_Optimzied_Technology := False;
  FL_DB_Engine_External_Header_Optimzied_Technology := False;
end;

constructor TZDB2_Large.Create(
  Small_Data_Class_: TZDB2_Custom_Small_Data_Class;
  Medium_Data_Class_: TZDB2_Custom_Medium_Data_Class;
  Large_Data_Class_: TZDB2_Custom_Large_Data_Class;
  S_Th_Engine_Marshal_Class_: TS_Th_Engine_Marshal_Class;
  M_Th_Engine_Marshal_Class_: TM_Th_Engine_Marshal_Class;
  L_Th_Engine_Marshal_Class_: TL_Th_Engine_Marshal_Class);
begin
  inherited Create;
  FBatch_Post_Num := 0;
  FCurrent_S_DB_Sequence_ID := 1;
  FCurrent_M_DB_Sequence_ID := 1;
  FCurrent_L_DB_Sequence_ID := 1;
  FCritical := TCritical.Create(ClassName + '.Critical');

  FSmall_Data_Class := Small_Data_Class_;
  FMedium_Data_Class := Medium_Data_Class_;
  FLarge_Data_Class := Large_Data_Class_;

  FS_Th_Engine_Marshal_Class := S_Th_Engine_Marshal_Class_;
  FM_Th_Engine_Marshal_Class := M_Th_Engine_Marshal_Class_;
  FL_Th_Engine_Marshal_Class := L_Th_Engine_Marshal_Class_;

  FS_DB := FS_Th_Engine_Marshal_Class.Create(Self);
  FS_DB.Current_Data_Class := FSmall_Data_Class;
  FS_DB.Owner_Large_Marshal := Self;
  FS_DB_Sequence_Pool := TZDB2_Custom_Small_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FM_DB := FM_Th_Engine_Marshal_Class.Create(Self);
  FM_DB.Current_Data_Class := FMedium_Data_Class;
  FM_DB.Owner_Large_Marshal := Self;
  FM_DB_Sequence_Pool := TZDB2_Custom_Medium_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FL_DB := FL_Th_Engine_Marshal_Class.Create(Self);
  FL_DB.Current_Data_Class := FLarge_Data_Class;
  FL_DB.Owner_Large_Marshal := Self;
  FL_DB_Sequence_Pool := TZDB2_Custom_Large_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FS_DB_Engine_External_Header_Optimzied_Technology := False;
  FM_DB_Engine_External_Header_Optimzied_Technology := False;
  FL_DB_Engine_External_Header_Optimzied_Technology := False;
end;

destructor TZDB2_Large.Destroy;
begin
  { stop copy }
  FS_DB.Stop_Copy;
  FM_DB.Stop_Copy;
  FL_DB.Stop_Copy;

  { safe flush }
  FS_DB.Flush(False);
  FM_DB.Flush(False);
  FL_DB.Flush(False);

  { wait post bridge }
  Wait_Batch_Post;

  { reset owner }
  if FS_DB.Data_Marshal.Num > 0 then
    with FS_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Small_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { reset owner }
  if FM_DB.Data_Marshal.Num > 0 then
    with FM_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Medium_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { reset owner }
  if FL_DB.Data_Marshal.Num > 0 then
    with FL_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Large_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { free db }
  DisposeObjectAndNil(FS_DB);
  DisposeObjectAndNil(FS_DB_Sequence_Pool);
  DisposeObjectAndNil(FM_DB);
  DisposeObjectAndNil(FM_DB_Sequence_Pool);
  DisposeObjectAndNil(FL_DB);
  DisposeObjectAndNil(FL_DB_Sequence_Pool);

  DisposeObjectAndNil(FCritical);
  inherited Destroy;
end;

procedure TZDB2_Large.Build_DB_From_Script(Root_Path_: U_String; te: TTextDataEngine; OnlyRead_: Boolean);
var
  L: TPascalStringList;
  i: Integer;
  HL: THashStringList;
  n: U_String;
  Eng_: TZDB2_Th_Engine;
begin
  umlCreateDirectory(Root_Path_);
  L := TPascalStringList.Create;
  te.GetSectionList(L);

  if L.Count > 0 then
    begin
      for i := 0 to L.Count - 1 do
        begin
          HL := te.HStringList[L[i]];
          { prepare database file }
          n := umlTrimSpace(HL.GetDefaultValue('database', ''));
          if (n <> '') and (not n.Exists(['/', '\'])) then
              HL.SetDefaultValue('database', umlCombineFileName(Root_Path_, n));

          { update OnlyRead }
          HL.SetDefaultText_Bool('OnlyRead', OnlyRead_);

          { extract database type }
          n := HL.GetDefaultValue('Type', '');
          if n.Same('Small', 'Tiny', 'Little', 'S', 'Lv1', '1') then
            begin
              Eng_ := TZDB2_Th_Engine.Create(FS_DB);
              Eng_.ReadConfig(L[i], HL);
              if Eng_.BlockSize < 1024 then
                  Eng_.BlockSize := 1024;
            end
          else if n.Same('Default', 'Medium', 'Middle', 'M', 'Lv2', '2') then
            begin
              Eng_ := TZDB2_Th_Engine.Create(FM_DB);
              Eng_.ReadConfig(L[i], HL);
              if Eng_.BlockSize < 4 * 1024 then
                  Eng_.BlockSize := 4 * 1024;
            end
          else if n.Same('Large', 'Big', 'Huge', 'L', 'Lv3', '3') then
            begin
              Eng_ := TZDB2_Th_Engine.Create(FL_DB);
              Eng_.ReadConfig(L[i], HL);
              if Eng_.BlockSize < 16 * 1024 then
                  Eng_.BlockSize := 16 * 1024;
            end
          else
              RaiseInfo('script error %s -> %s', [L[i].Text, n.Text]);
        end;
    end;
  { free temp }
  DisposeObject(L);

  { create or open datgabase }
  FS_DB.Build();
  FM_DB.Build();
  FL_DB.Build();
end;

class function TZDB2_Large.Make_Script(Name_: U_String; S_DB_Num, M_DB_Num, L_DB_Num: Integer; Cipher_Security_: TCipherSecurity): TTextDataEngine;
var
  tmp: TZDB2_Th_Engine_Marshal;
  i: Integer;
  Eng_: TZDB2_Th_Engine;
  HL: THashStringList;
begin
  Result := TTextDataEngine.Create;
  tmp := TZDB2_Th_Engine_Marshal.Create(nil);
  for i := 0 to S_DB_Num - 1 do
    begin
      Eng_ := TZDB2_Th_Engine.Create(tmp);
      Eng_.Name := PFormat('%s_S(%d)', [Name_.Text, i + 1]);
      Eng_.Database_File := PFormat('%s_S(%d).ZDB2', [Name_.Text, i + 1]);
      Eng_.Fast_Alloc_Space := True;
      Eng_.First_Inited_Physics_Space := 10 * 1024 * 1024;
      Eng_.Auto_Append_Space := True;
      Eng_.Delta := 10 * 1024 * 1024;
      Eng_.BlockSize := 1024;
      Eng_.Cipher_Security := Cipher_Security_;
      HL := Result.HStringList[Eng_.Name];
      HL['Type'] := 'Small';
      Eng_.WriteConfig(HL);
    end;

  for i := 0 to M_DB_Num - 1 do
    begin
      Eng_ := TZDB2_Th_Engine.Create(tmp);
      Eng_.Name := PFormat('%s_M(%d)', [Name_.Text, i + 1]);
      Eng_.Database_File := PFormat('%s_M(%d).ZDB2', [Name_.Text, i + 1]);
      Eng_.Fast_Alloc_Space := True;
      Eng_.First_Inited_Physics_Space := Int64(200) * 1024 * 1024;
      Eng_.Auto_Append_Space := True;
      Eng_.Delta := Int64(200) * 1024 * 1024;
      Eng_.BlockSize := 8 * 1024;
      Eng_.Cipher_Security := Cipher_Security_;
      HL := Result.HStringList[Eng_.Name];
      HL['Type'] := 'Medium';
      Eng_.WriteConfig(HL);
    end;

  for i := 0 to L_DB_Num - 1 do
    begin
      Eng_ := TZDB2_Th_Engine.Create(tmp);
      Eng_.Name := PFormat('%s_L(%d)', [Name_.Text, i + 1]);
      Eng_.Database_File := PFormat('%s_L(%d).ZDB2', [Name_.Text, i + 1]);
      Eng_.Fast_Alloc_Space := True;
      Eng_.First_Inited_Physics_Space := Int64(1024) * 1024 * 1024;
      Eng_.Auto_Append_Space := True;
      Eng_.Delta := Int64(1024) * 1024 * 1024;
      Eng_.BlockSize := $FFFF;
      Eng_.Cipher_Security := Cipher_Security_;
      HL := Result.HStringList[Eng_.Name];
      HL['Type'] := 'Large';
      Eng_.WriteConfig(HL);
    end;

  DisposeObject(tmp);
end;

function TZDB2_Large.Open_DB(script_conf_: U_String): Boolean;
begin
  Result := Open_DB(script_conf_, False);
end;

function TZDB2_Large.Open_DB(script_conf_: U_String; OnlyRead_: Boolean): Boolean;
var
  te: TTextDataEngine;
begin
  Result := False;
  if not umlFileExists(script_conf_) then
      exit;
  te := TTextDataEngine.Create;
  try
    te.LoadFromFile(script_conf_);
    Build_DB_From_Script(umlGetFilePath(script_conf_), te, OnlyRead_);
    Result := True;
  except
      Close_DB;
  end;
  DisposeObject(te);
end;

procedure TZDB2_Large.Close_DB;
begin
  { stop copy }
  FS_DB.Stop_Copy;
  FM_DB.Stop_Copy;
  FL_DB.Stop_Copy;

  { safe flush }
  FS_DB.Flush(False);
  FM_DB.Flush(False);
  FL_DB.Flush(False);

  { wait post bridge }
  Wait_Batch_Post;

  { reset owner }
  if FS_DB.Data_Marshal.Num > 0 then
    with FS_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Small_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { reset owner }
  if FM_DB.Data_Marshal.Num > 0 then
    with FM_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Medium_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { reset owner }
  if FL_DB.Data_Marshal.Num > 0 then
    with FL_DB.Data_Marshal.Repeat_ do
      repeat
          TZDB2_Custom_Large_Data(Queue^.data).FOwner_Large_Marshal := nil;
      until not Next;

  { free db }
  DisposeObjectAndNil(FS_DB);
  DisposeObjectAndNil(FS_DB_Sequence_Pool);
  DisposeObjectAndNil(FM_DB);
  DisposeObjectAndNil(FM_DB_Sequence_Pool);
  DisposeObjectAndNil(FL_DB);
  DisposeObjectAndNil(FL_DB_Sequence_Pool);

  { rebuild }
  FCurrent_S_DB_Sequence_ID := 1;
  FCurrent_M_DB_Sequence_ID := 1;
  FCurrent_L_DB_Sequence_ID := 1;

  FS_DB := FS_Th_Engine_Marshal_Class.Create(Self);
  FS_DB.Current_Data_Class := FSmall_Data_Class;
  FS_DB.Owner_Large_Marshal := Self;
  FS_DB_Sequence_Pool := TZDB2_Custom_Small_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FM_DB := FM_Th_Engine_Marshal_Class.Create(Self);
  FM_DB.Current_Data_Class := FMedium_Data_Class;
  FM_DB.Owner_Large_Marshal := Self;
  FM_DB_Sequence_Pool := TZDB2_Custom_Medium_Sequence_ID_Pool.Create(1024 * 1024, nil);

  FL_DB := FL_Th_Engine_Marshal_Class.Create(Self);
  FL_DB.Current_Data_Class := FLarge_Data_Class;
  FL_DB.Owner_Large_Marshal := Self;
  FL_DB_Sequence_Pool := TZDB2_Custom_Large_Sequence_ID_Pool.Create(1024 * 1024, nil);
end;

procedure TZDB2_Large.Do_Th_S_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Small_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Small_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_S_DB_Full(ThNum_: Integer);
var
  Extract_Done: Boolean;
begin
  FS_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FS_DB_Engine_External_Header_Optimzied_Technology then
      FS_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FS_DB.Parallel_Load_M(ThNum_, Do_Th_S_DB_Data_Full_Loaded, nil);
    end;

  Rebuild_S_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_S_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64);
var
  Inst_: TZDB2_Custom_Small_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Small_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_, True));
end;

procedure TZDB2_Large.Extract_S_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer);
var
  Extract_Done: Boolean;
begin
  FS_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FS_DB_Engine_External_Header_Optimzied_Technology then
      FS_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FS_DB.Parallel_Block_Load_M(ThNum_, Block_Index, Block_Offset, Block_Read_Size, Do_Th_S_DB_Data_Block_Loaded, nil);
    end;

  Rebuild_S_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_S_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Small_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Small_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_S_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64);
var
  Extract_Done: Boolean;
begin
  FS_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FS_DB_Engine_External_Header_Optimzied_Technology then
      FS_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FS_DB.Parallel_Position_Load_M(ThNum_, Position_Offset, Position_Read_Size, Do_Th_S_DB_Data_Position_Loaded, nil);
    end;

  Rebuild_S_DB_Requence();
end;

function TZDB2_Large.Do_S_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer;
begin
  Result := CompareInt64(TZDB2_Custom_Small_Data(L).FSequence_ID, TZDB2_Custom_Small_Data(R).FSequence_ID);
end;

procedure TZDB2_Large.Rebuild_S_DB_Requence;
begin
  FCurrent_S_DB_Sequence_ID := 1;
  if FS_DB.Data_Marshal.Num > 0 then
    begin
      { Restore structure pools in order }
      DoStatus('Rebuild Small Sequence..');
      FS_DB.Sort_M(Do_S_DB_Data_Sort_By_Sequence_ID);
      FCurrent_S_DB_Sequence_ID := TZDB2_Custom_Small_Data(FS_DB.Data_Marshal.Last^.data).FSequence_ID + 1;
      { Build Sequence_ID reverse lookup structure }
      with FS_DB.Data_Marshal.Repeat_ do
        repeat
            FS_DB_Sequence_Pool.Add(TZDB2_Custom_Small_Data(Queue^.data).FSequence_ID, TZDB2_Custom_Small_Data(Queue^.data), False);
        until not Next;
    end;
end;

procedure TZDB2_Large.Do_Th_M_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Medium_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Medium_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_M_DB_Full(ThNum_: Integer);
var
  Extract_Done: Boolean;
begin
  FM_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FM_DB_Engine_External_Header_Optimzied_Technology then
      FM_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FM_DB.Parallel_Load_M(ThNum_, Do_Th_M_DB_Data_Full_Loaded, nil);
    end;

  Rebuild_M_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_M_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64);
var
  Inst_: TZDB2_Custom_Medium_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Medium_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_, True));
end;

procedure TZDB2_Large.Extract_M_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer);
var
  Extract_Done: Boolean;
begin
  FM_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FM_DB_Engine_External_Header_Optimzied_Technology then
      FM_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FM_DB.Parallel_Block_Load_M(ThNum_, Block_Index, Block_Offset, Block_Read_Size, Do_Th_M_DB_Data_Block_Loaded, nil);
    end;

  Rebuild_M_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_M_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Medium_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Medium_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_M_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64);
var
  Extract_Done: Boolean;
begin
  FM_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FM_DB_Engine_External_Header_Optimzied_Technology then
      FM_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FM_DB.Parallel_Position_Load_M(ThNum_, Position_Offset, Position_Read_Size, Do_Th_M_DB_Data_Position_Loaded, nil);
    end;

  Rebuild_M_DB_Requence();
end;

function TZDB2_Large.Do_M_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer;
begin
  Result := CompareInt64(TZDB2_Custom_Medium_Data(L).FSequence_ID, TZDB2_Custom_Medium_Data(R).FSequence_ID);
end;

procedure TZDB2_Large.Rebuild_M_DB_Requence;
begin
  FCurrent_M_DB_Sequence_ID := 1;
  if FM_DB.Data_Marshal.Num > 0 then
    begin
      { Restore structure pools in order }
      DoStatus('Rebuild Medium Sequence..');
      FM_DB.Sort_M(Do_M_DB_Data_Sort_By_Sequence_ID);
      FCurrent_M_DB_Sequence_ID := TZDB2_Custom_Medium_Data(FM_DB.Data_Marshal.Last^.data).FSequence_ID + 1;
      { Build Sequence_ID reverse lookup structure }
      with FM_DB.Data_Marshal.Repeat_ do
        repeat
            FM_DB_Sequence_Pool.Add(TZDB2_Custom_Medium_Data(Queue^.data).FSequence_ID, TZDB2_Custom_Medium_Data(Queue^.data), False);
        until not Next;
    end;
end;

procedure TZDB2_Large.Do_Th_L_DB_Data_Full_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Large_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Large_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_L_DB_Full(ThNum_: Integer);
var
  Extract_Done: Boolean;
begin
  FL_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FL_DB_Engine_External_Header_Optimzied_Technology then
      FL_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FL_DB.Parallel_Load_M(ThNum_, Do_Th_L_DB_Data_Full_Loaded, nil);
    end;

  Rebuild_L_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_L_DB_Data_Block_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMem64);
var
  Inst_: TZDB2_Custom_Large_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Large_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_, True));
end;

procedure TZDB2_Large.Extract_L_DB_Block(ThNum_: Integer; Block_Index, Block_Offset, Block_Read_Size: Integer);
var
  Extract_Done: Boolean;
begin
  FL_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FL_DB_Engine_External_Header_Optimzied_Technology then
      FL_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FL_DB.Parallel_Block_Load_M(ThNum_, Block_Index, Block_Offset, Block_Read_Size, Do_Th_L_DB_Data_Block_Loaded, nil);
    end;

  Rebuild_L_DB_Requence();
end;

procedure TZDB2_Large.Do_Th_L_DB_Data_Position_Loaded(Sender: TZDB2_Th_Engine_Data; IO_: TMS64);
var
  Inst_: TZDB2_Custom_Large_Data;
begin
  Inst_ := Sender as TZDB2_Custom_Large_Data;
  DisposeObject(Inst_.Decode_From_ZDB2_Data(IO_.Mem64, True));
end;

procedure TZDB2_Large.Extract_L_DB_Position(ThNum_: Integer; Position_Offset, Position_Read_Size: Int64);
var
  Extract_Done: Boolean;
begin
  FL_DB_Sequence_Pool.Clear;

  Extract_Done := False;
  if FL_DB_Engine_External_Header_Optimzied_Technology then
      FL_DB.Extract_External_Header(Extract_Done); { external-header optimize tech }
  if not Extract_Done then
    begin
      FL_DB.Parallel_Position_Load_M(ThNum_, Position_Offset, Position_Read_Size, Do_Th_L_DB_Data_Position_Loaded, nil);
    end;

  Rebuild_L_DB_Requence();
end;

function TZDB2_Large.Do_L_DB_Data_Sort_By_Sequence_ID(var L, R: TZDB2_Th_Engine_Data): Integer;
begin
  Result := CompareInt64(TZDB2_Custom_Large_Data(L).FSequence_ID, TZDB2_Custom_Large_Data(R).FSequence_ID);
end;

procedure TZDB2_Large.Rebuild_L_DB_Requence;
begin
  FCurrent_L_DB_Sequence_ID := 1;
  if FL_DB.Data_Marshal.Num > 0 then
    begin
      { Restore structure pools in order }
      DoStatus('Rebuild Large Sequence..');
      FL_DB.Sort_M(Do_L_DB_Data_Sort_By_Sequence_ID);
      FCurrent_L_DB_Sequence_ID := TZDB2_Custom_Large_Data(FL_DB.Data_Marshal.Last^.data).FSequence_ID + 1;
      { Build Sequence_ID reverse lookup structure }
      with FL_DB.Data_Marshal.Repeat_ do
        repeat
            FL_DB_Sequence_Pool.Add(TZDB2_Custom_Large_Data(Queue^.data).FSequence_ID, TZDB2_Custom_Large_Data(Queue^.data), False);
        until not Next;
    end;
end;

function TZDB2_Large.Create_Small_Data: TZDB2_Custom_Small_Data;
var
  data_inst_: TZDB2_Custom_Small_Data;
begin
  FCritical.Lock;
  data_inst_ := FS_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Small_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_S_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_S_DB_Sequence_ID);
      FS_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Create_Medium_Data: TZDB2_Custom_Medium_Data;
var
  data_inst_: TZDB2_Custom_Medium_Data;
begin
  FCritical.Lock;
  data_inst_ := FM_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Medium_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_M_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_M_DB_Sequence_ID);
      FM_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Create_Large_Data: TZDB2_Custom_Large_Data;
var
  data_inst_: TZDB2_Custom_Large_Data;
begin
  FCritical.Lock;
  data_inst_ := FL_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Large_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_L_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_L_DB_Sequence_ID);
      FL_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_S_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Small_Data;
var
  data_inst_: TZDB2_Custom_Small_Data;
begin
  FCritical.Lock;
  data_inst_ := FS_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Small_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_S_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_S_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data(data_inst_.Encode_To_ZDB2_Data(data, False));
      FS_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_S_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Small_Data;
var
  data_inst_: TZDB2_Custom_Small_Data;
begin
  FCritical.Lock;
  data_inst_ := FS_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Small_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_S_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_S_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_C(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FS_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_S_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Small_Data;
var
  data_inst_: TZDB2_Custom_Small_Data;
begin
  FCritical.Lock;
  data_inst_ := FS_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Small_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_S_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_S_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_M(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FS_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_S_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Small_Data;
var
  data_inst_: TZDB2_Custom_Small_Data;
begin
  FCritical.Lock;
  data_inst_ := FS_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Small_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_S_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_S_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_P(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FS_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_M_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Medium_Data;
var
  data_inst_: TZDB2_Custom_Medium_Data;
begin
  FCritical.Lock;
  data_inst_ := FM_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Medium_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_M_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_M_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data(data_inst_.Encode_To_ZDB2_Data(data, False));
      FM_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_M_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Medium_Data;
var
  data_inst_: TZDB2_Custom_Medium_Data;
begin
  FCritical.Lock;
  data_inst_ := FM_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Medium_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_M_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_M_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_C(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FM_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_M_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Medium_Data;
var
  data_inst_: TZDB2_Custom_Medium_Data;
begin
  FCritical.Lock;
  data_inst_ := FM_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Medium_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_M_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_M_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_M(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FM_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_M_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Medium_Data;
var
  data_inst_: TZDB2_Custom_Medium_Data;
begin
  FCritical.Lock;
  data_inst_ := FM_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Medium_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_M_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_M_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_P(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FM_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_L_DB(data: TMS64; AutoFree_: Boolean): TZDB2_Custom_Large_Data;
var
  data_inst_: TZDB2_Custom_Large_Data;
begin
  FCritical.Lock;
  data_inst_ := FL_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Large_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_L_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_L_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data(data_inst_.Encode_To_ZDB2_Data(data, False));
      FL_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_L_DB_C(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_C): TZDB2_Custom_Large_Data;
var
  data_inst_: TZDB2_Custom_Large_Data;
begin
  FCritical.Lock;
  data_inst_ := FL_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Large_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_L_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_L_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_C(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FL_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_L_DB_M(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_M): TZDB2_Custom_Large_Data;
var
  data_inst_: TZDB2_Custom_Large_Data;
begin
  FCritical.Lock;
  data_inst_ := FL_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Large_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_L_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_L_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_M(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FL_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Post_Data_To_L_DB_P(data: TMS64; AutoFree_: Boolean; OnResult: TOn_ZDB2_Th_Engine_Save_Data_Event_P): TZDB2_Custom_Large_Data;
var
  data_inst_: TZDB2_Custom_Large_Data;
begin
  FCritical.Lock;
  data_inst_ := FL_DB.Add_Data_To_Minimize_Size_Engine as TZDB2_Custom_Large_Data;
  FCritical.UnLock;
  if data_inst_ <> nil then
    begin
      data_inst_.FSequence_ID := FCurrent_L_DB_Sequence_ID;
      FCritical.Inc_(FCurrent_L_DB_Sequence_ID);
      data_inst_.FMD5 := data.ToMD5;

      { rebuild sequence memory }
      data_inst_.Async_Save_And_Free_Data_P(data_inst_.Encode_To_ZDB2_Data(data, False), OnResult);
      FL_DB_Sequence_Pool.Add(data_inst_.FSequence_ID, data_inst_, False);

      if AutoFree_ then
          DisposeObject(data);
    end;
  Result := data_inst_;
end;

function TZDB2_Large.Batch_Post(): TZDB2_Custom_Batch_Data_Post_Bridge;
begin
  Result := TZDB2_Custom_Batch_Data_Post_Bridge.Create(Self);
end;

function TZDB2_Large.Batch_Post_C(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_C): TZDB2_Custom_Batch_Data_Post_Bridge;
begin
  Result := TZDB2_Custom_Batch_Data_Post_Bridge.Create(Self);
  Result.OnResult_C := OnResult;
end;

function TZDB2_Large.Batch_Post_M(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_M): TZDB2_Custom_Batch_Data_Post_Bridge;
begin
  Result := TZDB2_Custom_Batch_Data_Post_Bridge.Create(Self);
  Result.OnResult_M := OnResult;
end;

function TZDB2_Large.Batch_Post_P(OnResult: TZDB2_Custom_Batch_Data_Post_Bridge_Event_P): TZDB2_Custom_Batch_Data_Post_Bridge;
begin
  Result := TZDB2_Custom_Batch_Data_Post_Bridge.Create(Self);
  Result.OnResult_P := OnResult;
end;

procedure TZDB2_Large.Wait_Batch_Post;
begin
  while FBatch_Post_Num > 0 do
      TCompute.Sleep(10);
end;

procedure TZDB2_Large.Modify_S_DB_Data(Inst_: TZDB2_Custom_Small_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean);
var
  tmp: TMem64;
begin
  if Inst_.FOwner_Large_Marshal <> Self then
      RaiseInfo('error.');
  Inst_.FMD5 := data.ToMD5;
  tmp := Inst_.Encode_To_ZDB2_Data(data, False);
  if Wait_Modify_ then
    begin
      Inst_.Save_Data(tmp);
      DisposeObject(tmp);
    end
  else
    begin
      Inst_.Async_Save_And_Free_Data(tmp);
    end;
  if AutoFree_ then
      DisposeObject(data);
end;

procedure TZDB2_Large.Modify_M_DB_Data(Inst_: TZDB2_Custom_Medium_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean);
var
  tmp: TMem64;
begin
  if Inst_.FOwner_Large_Marshal <> Self then
      RaiseInfo('error.');
  Inst_.FMD5 := data.ToMD5;
  tmp := Inst_.Encode_To_ZDB2_Data(data, False);
  if Wait_Modify_ then
    begin
      Inst_.Save_Data(tmp);
      DisposeObject(tmp);
    end
  else
    begin
      Inst_.Async_Save_And_Free_Data(tmp);
    end;
  if AutoFree_ then
      DisposeObject(data);
end;

procedure TZDB2_Large.Modify_L_DB_Data(Inst_: TZDB2_Custom_Large_Data; data: TMS64; Wait_Modify_, AutoFree_: Boolean);
var
  tmp: TMem64;
begin
  if Inst_.FOwner_Large_Marshal <> Self then
      RaiseInfo('error.');
  Inst_.FMD5 := data.ToMD5;
  tmp := Inst_.Encode_To_ZDB2_Data(data, False);
  if Wait_Modify_ then
    begin
      Inst_.Save_Data(tmp);
      DisposeObject(tmp);
    end
  else
    begin
      Inst_.Async_Save_And_Free_Data(tmp);
    end;
  if AutoFree_ then
      DisposeObject(data);
end;

procedure TZDB2_Large.Check_Recycle_Pool;
begin
  FS_DB.Check_Recycle_Pool;
  FM_DB.Check_Recycle_Pool;
  FL_DB.Check_Recycle_Pool;
end;

function TZDB2_Large.Progress: Integer;
begin
  Result := 0;
  if FS_DB.Progress then
      Inc(Result);
  if FM_DB.Progress then
      Inc(Result);
  if FL_DB.Progress then
      Inc(Result);
end;

procedure TZDB2_Large.Backup(Reserve_: Word);
begin
  FS_DB.Backup(Reserve_);
  FM_DB.Backup(Reserve_);
  FL_DB.Backup(Reserve_);
end;

procedure TZDB2_Large.Backup_If_No_Exists;
begin
  FS_DB.Backup_If_No_Exists();
  FM_DB.Backup_If_No_Exists();
  FL_DB.Backup_If_No_Exists();
end;

procedure TZDB2_Large.Flush(WaitQueue_: Boolean);
begin
  FS_DB.Flush(WaitQueue_);
  FM_DB.Flush(WaitQueue_);
  FL_DB.Flush(WaitQueue_);
end;

function TZDB2_Large.Flush_Is_Busy: Boolean;
begin
  Result :=
    FS_DB.Flush_Is_Busy or
    FM_DB.Flush_Is_Busy or
    FL_DB.Flush_Is_Busy;
end;

function TZDB2_Large.Database_Size: Int64;
begin
  Result :=
    FS_DB.Database_Size +
    FM_DB.Database_Size +
    FL_DB.Database_Size;
end;

function TZDB2_Large.Database_Physics_Size: Int64;
begin
  Result :=
    FS_DB.Database_Physics_Size +
    FM_DB.Database_Physics_Size +
    FL_DB.Database_Physics_Size;
end;

function TZDB2_Large.Total: NativeInt;
begin
  Result :=
    FS_DB.Total +
    FM_DB.Total +
    FL_DB.Total;
end;

function TZDB2_Large.QueueNum: NativeInt;
begin
  Result :=
    FS_DB.QueueNum +
    FM_DB.QueueNum +
    FL_DB.QueueNum;
end;

function TZDB2_Large.Fragment_Buffer_Num: Int64;
begin
  Result :=
    FS_DB.Fragment_Buffer_Num +
    FM_DB.Fragment_Buffer_Num +
    FL_DB.Fragment_Buffer_Num;
end;

function TZDB2_Large.Fragment_Buffer_Memory: Int64;
begin
  Result :=
    FS_DB.Fragment_Buffer_Memory +
    FM_DB.Fragment_Buffer_Memory +
    FL_DB.Fragment_Buffer_Memory;
end;

class procedure TZDB2_Large.Do_Test_Batch_Post(Eng_: TZDB2_Large);
var
  batch: TZDB2_Custom_Batch_Data_Post_Bridge;
  M64: TMS64;
  i: Integer;
begin
{$IFDEF DELPHI}
  for i := 0 to 10 do
    begin
      batch := Eng_.Batch_Post_P(procedure(Sender: TZDB2_Custom_Batch_Data_Post_Bridge)
        var
          d: TDFE;
          tmp_m64: TMS64;
        begin
          if Sender.Error_Num > 0 then
              exit;
          d := TDFE.Create;
          d.WriteInt64(Sender.User_Hash_Variants.GetDefaultValue('m_id', 0));
          d.WriteString(Sender.User_Hash_Strings.GetDefaultValue('m_md5', ''));
          d.WriteInt64(Sender.User_Hash_Variants.GetDefaultValue('l_id', 0));
          d.WriteString(Sender.User_Hash_Strings.GetDefaultValue('l_md5', ''));
          tmp_m64 := TMS64.Create;
          d.FastEncodeTo(tmp_m64);
          DisposeObject(d);
          Eng_.Post_Data_To_S_DB(tmp_m64, True);
        end);

      batch.Begin_Post;
      M64 := TMS64.Create;
      M64.Size := umlRR(8192, 500 * 1024);
      batch.User_Hash_Strings['m_md5'] := umlMD5ToStr(M64.ToMD5);
      batch.User_Hash_Variants['m_id'] := batch.Post_Data_To_M_DB(M64, True).FSequence_ID;

      M64 := TMS64.Create;
      M64.Size := umlRR(1048576, 1024 * 1024 * 8);
      batch.User_Hash_Strings['l_md5'] := umlMD5ToStr(M64.ToMD5);
      batch.User_Hash_Variants['l_id'] := batch.Post_Data_To_L_DB(M64, True).FSequence_ID;
      batch.End_Post;
    end;
{$ENDIF DELPHI}
  Eng_.Wait_Batch_Post;
end;

class procedure TZDB2_Large.Do_Test_Post(Eng_: TZDB2_Large);
var
  i: Integer;
  d: TDFE;
  M64: TMS64;
  tmp_m64: TMS64;
begin
  for i := 0 to 300 do
    begin
      d := TDFE.Create;

      M64 := TMS64.Create;
      M64.Size := umlRR(8192, 500 * 1024);
      d.WriteInt64(Eng_.Post_Data_To_M_DB(M64, False).FSequence_ID);
      d.WriteString(umlMD5ToStr(M64.ToMD5));
      DisposeObject(M64);

      M64 := TMS64.Create;
      M64.Size := umlRR(1048576, 1024 * 1024 * 8);
      d.WriteInt64(Eng_.Post_Data_To_L_DB(M64, False).FSequence_ID);
      d.WriteString(umlMD5ToStr(M64.ToMD5));
      DisposeObject(M64);

      tmp_m64 := TMS64.Create;
      d.FastEncodeTo(tmp_m64);
      DisposeObject(d);
      Eng_.Post_Data_To_S_DB(tmp_m64, True);

      if i mod 10 = 0 then
          Eng_.Flush(True);
    end;
  Eng_.Flush(True);
end;

class procedure TZDB2_Large.Do_Test_Get_Data(Eng_: TZDB2_Large);
var
  num_: Integer;
begin
  num_ := 0;
{$IFDEF DELPHI}
  Eng_.S_DB.Begin_Loop;
  if Eng_.S_DB.Data_Marshal.Num > 0 then
    with Eng_.S_DB.Repeat_ do
      repeat
        while num_ > 10 do
            TCompute.Sleep(1);
        AtomInc(num_);
        Queue^.data.Async_Load_Stream_P(procedure(Sender: TZDB2_Th_Engine_Data; stream: TMS64; Successed: Boolean)
          var
            tmp: TMS64;
            Inst_: TZDB2_Custom_Small_Data;
          begin
            if not Successed then
                exit;
            Inst_ := Sender as TZDB2_Custom_Small_Data;
            tmp := Inst_.Decode_From_ZDB2_Data(stream.Mem64, False);
            if not umlCompareMD5(tmp.ToMD5, Inst_.FMD5) then
                DoStatus('md5 error.');
            DisposeObject(tmp);
            AtomDec(num_);
          end);
      until not Next;
  Eng_.S_DB.End_Loop;
  while num_ > 0 do
      TCompute.Sleep(1);

  Eng_.M_DB.Begin_Loop;
  if Eng_.M_DB.Data_Marshal.Num > 0 then
    with Eng_.M_DB.Repeat_ do
      repeat
        while num_ > 10 do
            TCompute.Sleep(1);
        AtomInc(num_);
        Queue^.data.Async_Load_Stream_P(procedure(Sender: TZDB2_Th_Engine_Data; stream: TMS64; Successed: Boolean)
          var
            tmp: TMS64;
            Inst_: TZDB2_Custom_Medium_Data;
          begin
            if not Successed then
                exit;
            Inst_ := Sender as TZDB2_Custom_Medium_Data;
            tmp := Inst_.Decode_From_ZDB2_Data(stream.Mem64, False);
            if not umlCompareMD5(tmp.ToMD5, Inst_.FMD5) then
                DoStatus('md5 error.');
            DisposeObject(tmp);
            AtomDec(num_);
          end);
      until not Next;
  Eng_.M_DB.End_Loop;
  while num_ > 0 do
      TCompute.Sleep(1);

  Eng_.L_DB.Begin_Loop;
  if Eng_.L_DB.Data_Marshal.Num > 0 then
    with Eng_.L_DB.Repeat_ do
      repeat
        while num_ > 10 do
            TCompute.Sleep(1);
        AtomInc(num_);
        Queue^.data.Async_Load_Stream_P(procedure(Sender: TZDB2_Th_Engine_Data; stream: TMS64; Successed: Boolean)
          var
            tmp: TMS64;
            Inst_: TZDB2_Custom_Large_Data;
          begin
            if not Successed then
                exit;
            Inst_ := Sender as TZDB2_Custom_Large_Data;
            tmp := Inst_.Decode_From_ZDB2_Data(stream.Mem64, False);
            if not umlCompareMD5(tmp.ToMD5, Inst_.FMD5) then
                DoStatus('md5 error.');
            DisposeObject(tmp);
            AtomDec(num_);
          end);
      until not Next;
  Eng_.L_DB.End_Loop;
  while num_ > 0 do
      TCompute.Sleep(1);
{$ENDIF DELPHI}
end;

class procedure TZDB2_Large.Test;
var
  Eng_: TZDB2_Large;
  te: TTextDataEngine;
begin
  Eng_ := TZDB2_Large.Create;
  { make script templet }
  te := Eng_.Make_Script('test', 2, 2, 2, TCipherSecurity.csNone);
  Eng_.Build_DB_From_Script(umlCombinePath(umlCurrentPath, 'ZDB2_large_DB_Test'), te, False);
  DisposeObject(te);
  Eng_.S_DB_Engine_External_Header_Optimzied_Technology := True;
  Eng_.M_DB_Engine_External_Header_Optimzied_Technology := True;
  Eng_.L_DB_Engine_External_Header_Optimzied_Technology := True;

  Eng_.Extract_S_DB_Full(10);
  Eng_.Extract_M_DB_Full(10);
  Eng_.Extract_L_DB_Full(10);

  if True then
      Do_Test_Batch_Post(Eng_);

  if True then
      Do_Test_Post(Eng_);

  if True then
      Do_Test_Get_Data(Eng_);

  DisposeObject(Eng_);
end;

end.
 
