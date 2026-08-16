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
  ******************************************************************************
  * ObjectData Library 每 a lightweight embedded database engine with directory *
  * structure, file storage, and block-level data management.                  *
  *                                                                            *
  * What is this?                                                              *
  * This is a small but powerful database that lives inside your application   *
  * files. Think of it as a hierarchical storage system similar to a file      *
  * system, but all data is stored in a single file with fast access.          *
  *                                                                            *
  * How it's structured:                                                       *
  *   每 Field:  Works like a folder or directory 每 it groups and organizes     *
  *              items (files). You can nest fields to create any depth of     *
  *              hierarchy you need.                                           *
  *   每 Item:   Works like a file 每 it holds your actual data (text, binary,   *
  *              whatever you want). Each item has a name, description, and    *
  *              a unique ID that you can use for categorization.              *
  *   每 Block:  Items are split into blocks. Each block holds a chunk of the   *
  *              item's data. Blocks are linked together like a chain, so      *
  *              items can grow as large as you need without fragmentation     *
  *              issues.                                                       *
  *                                                                            *
  * What makes it tick?                                                        *
  *   每 Everything is linked by 64-bit file positions (pointers). This is      *
  *     similar to how filesystems work under the hood.                        *
  *   每 You can traverse forward (Next) and backward (Prev) using doubly       *
  *     linked lists 每 great for iterating through records in any direction.   *
  *   每 Record types are identified by IDs: Field = 21, Item = 22. This makes  *
  *     it easy to tell what kind of record you're dealing with.               *
  *   每 Each list position has a PositionID (First/Medium/Last/1) so you       *
  *     always know where you are in a list.                                   *
  *   每 Fixed-length strings (FixedStringL) make storage more predictable and  *
  *     retrieval faster (no length prefixes to parse).                        *
  *                                                                            *
  * Meet the key players:                                                      *
  *   每 THeader:  The common header every record shares. It holds the links    *
  *               (Next/Prev), ID, name, and timestamps. Think of it as the    *
  *               "business card" of every record.                             *
  *   每 TField:   The folder/directory structure. It keeps track of how many   *
  *               children it has and where they start and end in the list.    *
  *   每 TItem:    The file that holds your data. It tracks the first and       *
  *               last block positions, total size, and block count.           *
  *   每 TItemBlock: A chunk of an item's data. Each block knows where its      *
  *               data lives, how big it is, and where the next/previous       *
  *               blocks are.                                                  *
  *                                                                            *
  * How do you use it? (A typical session)                                     *
  *   1. db_CreateNew / db_Open 每 Create a new database or open an existing    *
  *      one from disk or memory.                                              *
  *   2. db_CreateField 每 Create a folder (field) to organize your data.       *
  *   3. db_ItemCreate / db_ItemOpen 每 Create a new file (item) or open an     *
  *      existing one for reading/writing.                                     *
  *   4. db_ItemWrite / db_ItemRead 每 Write data to or read data from the      *
  *      current position in the item.                                         *
  *   5. db_ItemClose 每 Close the item handle to save changes.                 *
  *   6. db_ClosePack 每 Close the database and flush everything to disk.       *
  *                                                                            *
  * Where would you use this?                                                  *
  *   每 Configuration management: Store application settings in a structured   *
  *     way, with folders for different components.                            *
  *   每 Game saves / user profiles: Keep player data, game progress, and       *
  *     achievements organized in one file.                                    *
  *   每 Embedded systems: When you need a small, fast database with no         *
  *     external dependencies.                                                 *
  *   每 Application metadata: Store indexes, caches, or other metadata that    *
  *     needs to survive restarts.                                             *
  *   每 Database prototypes: Use this as a building block for your own         *
  *     database engine or storage system.                                     *
  *   每 Document management: Store documents and their metadata in a           *
  *     hierarchical structure.                                                *
  *   每 IoT device storage: Lightweight persistent storage for sensor data     *
  *     and device state.                                                      *
  *                                                                            *
  * This library is the foundation of the ZDB2 storage engine and is used      *
  * extensively throughout the Z-framework for metadata and configuration      *
  * storage. It's battle-tested and ready for your next project!               *
  ******************************************************************************
*)
unit Z.ZDB.ObjectData_LIB;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.UnicodeMixedLib;

const
  { * Field sizes in bytes 每 each constant defines the storage size of a        * }
  { * primitive type in the database file. These are used for record layout     * }
  { * calculations.                                                             * }
  DB_Version_Size = C_Word_Size; { Size of version numbers (2 bytes). }
  DB_Time_Size = C_Double_Size; { Size of time stamps (8 bytes, TDateTime). }
  DB_Counter_Size = C_Int64_Size; { Size of counters (8 bytes). }
  DB_DataSize_Size = C_Int64_Size; { Size of data size fields (8 bytes). }
  DB_Position_Size = C_Int64_Size; { Size of position pointers (8 bytes, file offset). }
  DB_ID_Size = C_Byte_Size; { Size of ID fields (1 byte). }
  DB_Property_Size = C_Cardinal_Size; { Size of user property fields (4 bytes). }
  DB_Level_Size = C_Word_Size; { Size of level fields (2 bytes). }
  DB_ReservedData_Size = 64; { Size of reserved data area in database header (64 bytes). }
  DB_FixedStringL_Size = 1; { Size of fixed string length prefix (1 byte). }

  { * Version numbers for the database format. * }
  DB_MajorVersion = 2; { Major version of the database format. }
  DB_MinorVersion = 3; { Minor version of the database format. }
  DB_Max_Secursion_Level = 128; { Maximum recursion depth for nested directory traversal. }

  DB_FileDescription = 'ObjectDataV2.3'; { Human-readable description of the database format. }
  DB_DefaultField = 'Default-Root'; { Name of the default root field created in new databases. }

  DB_Path_Delimiter = '/'; { Path separator for field/item names. }

  { * Header ID constants 每 identify the type of a header record. * }
  DB_Header_Field_ID = 21; { Header ID for a Field (directory). }
  DB_Header_Item_ID = 22; { Header ID for an Item (file). }

  { * Position ID constants 每 identify where a header sits in its linked list. * }
  DB_Header_First = 11; { Position ID for the first node in a linked list. }
  DB_Header_Medium = 12; { Position ID for a middle node in a linked list. }
  DB_Header_Last = 13; { Position ID for the last node in a linked list. }
  DB_Header_1 = 14; { Position ID for a list with exactly one node. }

  { * Item block ID constants. * }
  DB_Item_1 = 33; { Block ID for a list with exactly one block. }
  DB_Item_First = 34; { Block ID for the first block in a linked list. }
  DB_Item_Medium = 35; { Block ID for a middle block in a linked list. }
  DB_Item_Last = 36; { Block ID for the last block in a linked list. }

{$REGION 'State Code'}
  { * Return codes 每 indicate success or specific error conditions for each    * }
  { * operation. Positive values indicate success; negative values indicate    * }
  { * specific errors.                                                         * }
  DB_Header_ok = 300; { Header operation succeeded. }
  DB_Header_SetPosError = -301; { Failed to seek to header position. }
  DB_Header_WritePosError = -303; { Failed to write position field. }
  DB_Header_WriteNextPosError = -304; { Failed to write NextHeader field. }
  DB_Header_WritePrevPosError = -305; { Failed to write PrevHeader field. }
  DB_Header_WritePubMainPosError = -306; { Failed to write DataPosition field. }
  DB_Header_WriteIDError = -307; { Failed to write ID field. }
  DB_Header_WritePositionIDError = -311; { Failed to write PositionID field. }
  DB_Header_WriteNameError = -308; { Failed to write Name field. }
  DB_Header_WriteCreateTimeError = -309; { Failed to write CreateTime field. }
  DB_Header_WriteLastEditTimeError = -310; { Failed to write ModificationTime field. }
  DB_Header_WriteUserPropertyIDError = -332; { Failed to write UserProperty field. }
  DB_Header_ReadPosError = -321; { Failed to read position field. }
  DB_Header_ReadNextPosError = -322; { Failed to read NextHeader field. }
  DB_Header_ReadPrevPosError = -323; { Failed to read PrevHeader field. }
  DB_Header_ReadPubMainPosError = -324; { Failed to read DataPosition field. }
  DB_Header_ReadIDError = -325; { Failed to read ID field. }
  DB_Header_ReadPositionIDError = -312; { Failed to read PositionID field. }
  DB_Header_ReadNameError = -326; { Failed to read Name field. }
  DB_Header_ReadCreateTimeError = -327; { Failed to read CreateTime field. }
  DB_Header_ReadLastEditTimeError = -328; { Failed to read ModificationTime field. }
  DB_Header_ReadUserPropertyIDError = -331; { Failed to read UserProperty field. }
  DB_Header_NotFindHeader = -320; { Requested header was not found. }
  DB_Item_ok = 200; { Item operation succeeded. }
  DB_Item_SetPosError = -201; { Failed to seek to item position. }
  DB_Item_WriteRecDescriptionError = -204; { Failed to write Description field. }
  DB_Item_WriteRecExterIDError = -205; { Failed to write ExtID field. }
  DB_Item_WriteFirstBlockPOSError = -206; { Failed to write FirstBlockPOS field. }
  DB_Item_WriteLastBlockPOSError = -207; { Failed to write LastBlockPOS field. }
  DB_Item_WriteRecBuffSizeError = -208; { Failed to write Size field. }
  DB_Item_WriteBlockCountError = -209; { Failed to write BlockCount field. }
  DB_Item_ReadRecDescriptionError = -214; { Failed to read Description field. }
  DB_Item_ReadRecExterIDError = -215; { Failed to read ExtID field. }
  DB_Item_ReadFirstBlockPOSError = -216; { Failed to read FirstBlockPOS field. }
  DB_Item_ReadLastBlockPOSError = -217; { Failed to read LastBlockPOS field. }
  DB_Item_ReadRecBuffSizeError = -218; { Failed to read Size field. }
  DB_Item_ReadBlockCountError = -219; { Failed to read BlockCount field. }
  DB_Item_WriteItemBlockIDFlagsError = -220; { Failed to write block ID field. }
  DB_Item_WriteCurrentBlockPOSError = -221; { Failed to write CurrentBlockPOS field. }
  DB_Item_WriteNextBlockPOSError = -222; { Failed to write NextBlockPOS field. }
  DB_Item_WritePrevBlockPOSError = -223; { Failed to write PrevBlockPOS field. }
  DB_Item_WriteDataBlockPOSError = -224; { Failed to write DataPosition field. }
  DB_Item_WriteDataBuffSizeError = -225; { Failed to write Size field. }
  DB_Item_ReadItemBlockIDFlagsError = -230; { Failed to read block ID field. }
  DB_Item_ReadCurrentBlockPOSError = -231; { Failed to read CurrentBlockPOS field. }
  DB_Item_ReadNextBlockPOSError = -232; { Failed to read NextBlockPOS field. }
  DB_Item_ReadPrevBlockPOSError = -233; { Failed to read PrevBlockPOS field. }
  DB_Item_ReadDataBlockPOSError = -234; { Failed to read DataPosition field. }
  DB_Item_ReadDataBuffSizeError = -235; { Failed to read Size field. }
  DB_Item_BlockPositionError = -240; { Block position is invalid. }
  DB_Item_BlockOverrate = -241; { Block read/write exceeds block bounds. }
  DB_Item_BlockReadError = -242; { Failed to read block data. }
  DB_Item_BlockWriteError = -243; { Failed to write block data. }
  DB_Field_ok = 100; { Field operation succeeded. }
  DB_Field_SetPosError = -101; { Failed to seek to field position. }
  DB_Field_WriteHeaderFieldPosError = -103; { Failed to write UpFieldPOS field. }
  DB_Field_WriteDescriptionError = -104; { Failed to write Description field. }
  DB_Field_WriteCountError = -106; { Failed to write HeaderCount field. }
  DB_Field_WriteFirstPosError = -107; { Failed to write FirstHeaderPOS field. }
  DB_Field_WriteLastPosError = -108; { Failed to write LastHeaderPOS field. }
  DB_Field_ReadHeaderFieldPosError = -110; { Failed to read UpFieldPOS field. }
  DB_Field_ReadDescriptionError = -111; { Failed to read Description field. }
  DB_Field_ReadCountError = -112; { Failed to read HeaderCount field. }
  DB_Field_ReadFirstPosError = -113; { Failed to read FirstHeaderPOS field. }
  DB_Field_ReadLastPosError = -114; { Failed to read LastHeaderPOS field. }
  DB_Field_NotInitSearch = -121; { Search structure not initialised. }
  DB_Field_DeleteHeaderError = -124; { Failed to delete header from field. }
  DB_ok = 400; { Database operation succeeded. }
  DB_RepOpenPackError = -401; { Database is already open. }
  DB_CreatePackError = -402; { Failed to create database file. }
  DB_WriteReservedDataError = -460; { Failed to write reserved data. }
  DB_WriteNameError = -403; { Failed to write database name. }
  DB_WriteDescriptionError = -404; { Failed to write database description. }
  DB_PositionSeekError = -405; { Failed to seek to database position. }
  DB_WriteMajorVersionError = -406; { Failed to write major version. }
  DB_WriteMinorVersionError = -407; { Failed to write minor version. }
  DB_WriteCreateTimeError = -408; { Failed to write creation time. }
  DB_WriteLastEditTimeError = -409; { Failed to write modification time. }
  DB_WriteHeaderCountError = -410; { Failed to write root header count. }
  DB_WriteDefaultPositionError = -411; { Failed to write default field position. }
  DB_WriteFirstPositionError = -412; { Failed to write first header position. }
  DB_WriteLastPositionError = -413; { Failed to write last header position. }
  DB_WriteFixedStringLError = -462; { Failed to write fixed string length. }
  DB_ReadReservedDataError = -461; { Failed to read reserved data. }
  DB_ReadNameError = -414; { Failed to read database name. }
  DB_ReadDescriptionError = -415; { Failed to read database description. }
  DB_ReadMajorVersionError = -416; { Failed to read major version. }
  DB_ReadMinorVersionError = -417; { Failed to read minor version. }
  DB_ReadCreateTimeError = -418; { Failed to read creation time. }
  DB_ReadLastEditTimeError = -419; { Failed to read modification time. }
  DB_ReadHeaderCountError = -420; { Failed to read root header count. }
  DB_ReadDefaultPositionError = -421; { Failed to read default field position. }
  DB_ReadFirstPositionError = -422; { Failed to read first header position. }
  DB_ReadLastPositionError = -423; { Failed to read last header position. }
  DB_RepCreatePackError = -424; { Database already exists. }
  DB_OpenPackError = -425; { Failed to open database. }
  DB_ClosePackError = -426; { Failed to close database. }
  DB_ReadFixedStringLError = -431; { Failed to read fixed string length. }
  DB_WriteCurrentPositionError = -427; { Failed to write current field position. }
  DB_WriteCurrentLevelError = -428; { Failed to write current field level. }
  DB_ReadCurrentPositionError = -429; { Failed to read current field position. }
  DB_ReadCurrentLevelError = -430; { Failed to read current field level. }
  DB_PathNameError = -440; { Invalid path or name. }
  DB_RepeatCreateItemError = -450; { Item already exists (when overwrite is disabled). }
  DB_OpenItemError = -451; { Failed to open item. }
  DB_ItemNameError = -452; { Invalid item name. }
  DB_RepeatOpenItemError = -453; { Item is already open. }
  DB_CloseItemError = -454; { Item is not open. }
  DB_ItemStructNotFindDescription = -455; { Item description not found. }
  DB_RecursionSearchOver = -456; { Recursion search completed. }
  DB_FileBufferError = -500; { File buffer operation error. }
  DB_CheckIOError = -501; { I/O handle check failed. }
  DB_ExceptionError = -502; { Generic exception occurred. }
{$ENDREGION 'State Code'}


type
  { * THeader 每 common header record for all database entries.                 * }
  { * Every Field and Item has a THeader that stores linking information,      * }
  { * identification, timestamps, and the entry name.                          * }
  THeader = record
    CurrentHeader: Int64; { Position of this header in the file. Set by ReadRec. }
    NextHeader, PrevHeader, DataPosition: Int64; { Next/Prev links and data position. Stored in file. }
    ID: Byte; { Record type: DB_Header_Field_ID or DB_Header_Item_ID. Stored in file. }
    PositionID: Byte; { List position: First/Medium/Last/1. Stored in file. }
    CreateTime, ModificationTime: Double; { Creation and last modification timestamps. Stored in file. }
    UserProperty: Cardinal; { User-defined property field. Stored in file. }
    Name: U_String; { Name of the entry (Field name or Item name). Stored in file. }
    State: Integer; { Operation return code for this header. Set by read/write functions. }
  end;

  PHeader = ^THeader;

  { * TItemBlock 每 a single data block within an Item.                         * }
  { * Items are stored as a linked list of blocks. Each block holds a portion  * }
  { * of the Item's total data.                                                * }
  TItemBlock = record
    ID: Byte; { Block type: DB_Item_1, First, Medium, or Last. Stored in file. }
    CurrentBlockPOS, NextBlockPOS, PrevBlockPOS, DataPosition: Int64; { Position of this block, next/prev links, and actual data. Stored in file. }
    Size: Int64; { Size of the data in this block. Stored in file. }
    State: Integer; { Operation return code for this block. Set by read/write functions. }
  end;

  PItemBlock = ^TItemBlock;

  { * TItem 每 represents a file/data entry in the database.                   * }
  { * Contains the header, description, and block list management fields.     * }
  TItem = record
    RHeader: THeader; { Header for this item. Stored in file. }
    Description: U_String; { Human-readable description. Stored in file. }
    ExtID: Byte; { User-defined external ID. Stored in file. }
    FirstBlockPOS, LastBlockPOS: Int64; { Positions of the first and last data blocks. Stored in file. }
    Size: Int64; { Total data size across all blocks. Stored in file. }
    BlockCount: Int64; { Number of blocks in this item. Stored in file. }
    CurrentBlockSeekPOS: Int64; { Current read/write position within the current block. Set by block operations. }
    CurrentFileSeekPOS: Int64; { Current read/write position in the file. Set by block operations. }
    CurrentItemBlock: TItemBlock; { Currently active block. Set by block operations. }
    DataModification: Boolean; { Indicates if data has been modified. Set by write operations. }
    State: Integer; { Operation return code. Set by read/write functions. }
  end;

  PItem = ^TItem;

  { * TField 每 represents a directory/field in the database.                   * }
  { * Fields contain other Fields and Items, forming a hierarchical structure. * }
  TField = record
    RHeader: THeader; { Header for this field. Stored in file. }
    UpFieldPOS: Int64; { Position of the parent field (0 for root). Stored in file. }
    Description: U_String; { Human-readable description. Stored in file. }
    HeaderCount: Int64; { Number of child entries (Fields + Items). Stored in file. }
    FirstHeaderPOS, LastHeaderPOS: Int64; { Positions of first and last child headers. Stored in file. }
    State: Integer; { Operation return code. Set by read/write functions. }
  end;

  PField = ^TField;

  { * TFieldSearch 每 internal search state for enumerating headers within a   * }
  { * field. Used by the FindFirst/FindNext family of functions.              * }
  TFieldSearch = record
    RHeader: THeader; { Current header during search. Set by search functions. }
    InitFlags: Boolean; { True if search has been initialised. Set by FindFirst functions. }
    Name: U_String; { Name pattern being searched for. Set by FindFirst functions. }
    StartPos, OverPOS: Int64; { Search range boundaries. Set by FindFirst functions. }
    ID: Byte; { Header ID being searched for. Set by FindFirst functions. }
    PositionID: Byte; { Position ID of current header. Set by search functions. }
    State: Integer; { Operation return code. Set by search functions. }
  end;

  PObjectDataHandle = ^TObjectDataHandle;

  { * Callback types 每 event hooks for database operations. * }
  TObjectDataErrorProc = procedure(error: U_String; error_code: Integer) of object; { Error callback. Set by user. }
  TObjectDataHeaderDeleteProc = procedure(fPos: Int64) of object; { Called when a header is deleted. Set by user. }
  TObjectDataHeaderWriteBeforeProc = procedure(fPos: Int64; var wVal: THeader; var Done: Boolean) of object; { Before header write. Set by user. }
  TObjectDataHeaderWriteAfterProc = procedure(fPos: Int64; var wVal: THeader) of object; { After header write. Set by user. }
  TObjectDataHeaderReadProc = procedure(fPos: Int64; var rVal: THeader; var Done: Boolean) of object; { Before header read. Set by user. }
  TObjectDataItemBlockWriteBeforeProc = procedure(fPos: Int64; var wVal: TItemBlock; var Done: Boolean) of object; { Before block write. Set by user. }
  TObjectDataItemBlockWriteAfterProc = procedure(fPos: Int64; var wVal: TItemBlock) of object; { After block write. Set by user. }
  TObjectDataItemBlockReadProc = procedure(fPos: Int64; var rVal: TItemBlock; var Done: Boolean) of object; { Before block read. Set by user. }
  TObjectDataItemWriteBeforeProc = procedure(fPos: Int64; var wVal: TItem; var Done: Boolean) of object; { Before item write. Set by user. }
  TObjectDataItemWriteAfterProc = procedure(fPos: Int64; var wVal: TItem) of object; { After item write. Set by user. }
  TObjectDataItemReadProc = procedure(fPos: Int64; var rVal: TItem; var Done: Boolean) of object; { Before item read. Set by user. }
  TObjectDataFieldWriteBeforeProc = procedure(fPos: Int64; var wVal: TField; var Done: Boolean) of object; { Before field write. Set by user. }
  TObjectDataFieldWriteAfterProc = procedure(fPos: Int64; var wVal: TField) of object; { After field write. Set by user. }
  TObjectDataFieldReadProc = procedure(fPos: Int64; var rVal: TField; var Done: Boolean) of object; { Before field read. Set by user. }
  TObjectDataTMDBWriteBeforeProc = procedure(fPos: Int64; const wVal: PObjectDataHandle; var Done: Boolean) of object; { Before database write. Set by user. }
  TObjectDataTMDBWriteAfterProc = procedure(fPos: Int64; const wVal: PObjectDataHandle) of object; { After database write. Set by user. }
  TObjectDataTMDBReadProc = procedure(fPos: Int64; const rVal: PObjectDataHandle; var Done: Boolean) of object; { Before database read. Set by user. }

  { * TObjectDataHandle 每 the main database handle. Contains file I/O state,  * }
  { * version information, root field management, and all event callbacks.    * }
  TObjectDataHandle_Reserved_Data = array [0 .. DB_ReservedData_Size - 1] of Byte; { Reserved data area in file header. }

  TObjectDataHandle = record
    IOHnd: TIOHnd; { Underlying I/O handle for file operations. Set by Create/Open functions. }
    ReservedData: TObjectDataHandle_Reserved_Data; { Reserved data from file header. Read/written by db_ReadRec/db_WriteRec. }
    FixedStringL: Byte; { Fixed string length for name/description fields. Read from file header. }
    MajorVer, MinorVer: SmallInt; { Database format version. Read from file header. }
    CreateTime, ModificationTime: Double; { Database creation and modification times. Read from file header. }
    RootHeaderCount: Int64; { Total number of root-level headers. Read from file header. }
    DefaultFieldPOS, FirstHeaderPOS, LastHeaderPOS: Int64; { Root field positions. Read from file header. }
    CurrentFieldPOS: Int64; { Current working field position. Read/written by SetCurrentField functions. }
    CurrentFieldLevel: Word; { Current field nesting level. Read/written by SetCurrentField functions. }

    OverWriteItem: Boolean; { If True, overwrite existing items on creation. Default True. Set by user. }
    AllowSameHeaderName: Boolean; { If True, allow duplicate header names. Default False. Set by user. }
    State: Integer; { Overall database operation state. Set by all database functions. }

    OnError: TObjectDataErrorProc; { Error callback. Set by user. }
    OnDeleteHeader: TObjectDataHeaderDeleteProc; { Header deletion callback. Set by user. }
    OnPrepareWriteHeader: TObjectDataHeaderWriteBeforeProc; { Pre-write callback for headers. Set by user. }
    OnWriteHeader: TObjectDataHeaderWriteAfterProc; { Post-write callback for headers. Set by user. }
    OnReadHeader: TObjectDataHeaderReadProc; { Pre-read callback for headers. Set by user. }
    OnPrepareWriteItemBlock: TObjectDataItemBlockWriteBeforeProc; { Pre-write callback for item blocks. Set by user. }
    OnWriteItemBlock: TObjectDataItemBlockWriteAfterProc; { Post-write callback for item blocks. Set by user. }
    OnReadItemBlock: TObjectDataItemBlockReadProc; { Pre-read callback for item blocks. Set by user. }
    OnPrepareWriteItem: TObjectDataItemWriteBeforeProc; { Pre-write callback for items. Set by user. }
    OnWriteItem: TObjectDataItemWriteAfterProc; { Post-write callback for items. Set by user. }
    OnReadItem: TObjectDataItemReadProc; { Pre-read callback for items. Set by user. }
    OnPrepareOnlyWriteItemRec: TObjectDataItemWriteBeforeProc; { Pre-write callback for item record only (no header). Set by user. }
    OnOnlyWriteItemRec: TObjectDataItemWriteAfterProc; { Post-write callback for item record only. Set by user. }
    OnOnlyReadItemRec: TObjectDataItemReadProc; { Pre-read callback for item record only. Set by user. }
    OnPrepareWriteField: TObjectDataFieldWriteBeforeProc; { Pre-write callback for fields. Set by user. }
    OnWriteField: TObjectDataFieldWriteAfterProc; { Post-write callback for fields. Set by user. }
    OnReadField: TObjectDataFieldReadProc; { Pre-read callback for fields. Set by user. }
    OnPrepareOnlyWriteFieldRec: TObjectDataFieldWriteBeforeProc; { Pre-write callback for field record only. Set by user. }
    OnOnlyWriteFieldRec: TObjectDataFieldWriteAfterProc; { Post-write callback for field record only. Set by user. }
    OnOnlyReadFieldRec: TObjectDataFieldReadProc; { Pre-read callback for field record only. Set by user. }
    OnPrepareWriteTMDB: TObjectDataTMDBWriteBeforeProc; { Pre-write callback for database header. Set by user. }
    OnWriteTMDB: TObjectDataTMDBWriteAfterProc; { Post-write callback for database header. Set by user. }
    OnReadTMDB: TObjectDataTMDBReadProc; { Pre-read callback for database header. Set by user. }
  end;

  { * TItemHandle_ 每 runtime handle for an open Item.                        * }
  { * Holds the item data and state for active read/write operations.        * }
  TItemHandle_ = record
    Item: TItem; { The underlying item record. Set by Create/Open. }
    Name: U_String; { Item name. Set by Create/Open. }
    Description: U_String; { Item description. Set by Create/Open. }
    CreateTime, ModificationTime: Double; { Item timestamps. Set by Create/Open. }
    ItemExtID: Byte; { External ID for this item. Set by Create/Open. }
    OpenFlags: Boolean; { True if the item handle is actively open. Set by Create/Open, cleared by Close. }
  end;

  { * TSearchHeader_ 每 search result for a header enumeration. * }
  TSearchHeader_ = record
    Name: U_String; { Name of the found header. Set by FindFirst/Next. }
    ID: Byte; { Header ID (Field or Item). Set by FindFirst/Next. }
    CreateTime, ModificationTime: Double; { Timestamps. Set by FindFirst/Next. }
    HeaderPOS: Int64; { File position of the header. Set by FindFirst/Next. }
    CompleteCount: Int64; { Number of items found so far. Set by FindFirst/Next. }
    FieldSearch: TFieldSearch; { Internal search state. Set by FindFirst/Next. }
  end;

  { * TSearchItem_ 每 search result for an Item enumeration. * }
  TSearchItem_ = record
    Name: U_String; { Item name. Set by FindFirst/Next. }
    Description: U_String; { Item description. Set by FindFirst/Next. }
    ExtID: Byte; { External ID. Set by FindFirst/Next. }
    Size: Int64; { Total data size. Set by FindFirst/Next. }
    HeaderPOS: Int64; { File position of the item header. Set by FindFirst/Next. }
    CompleteCount: Int64; { Number of items found so far. Set by FindFirst/Next. }
    FieldSearch: TFieldSearch; { Internal search state. Set by FindFirst/Next. }
  end;

  { * TSearchField_ 每 search result for a Field enumeration. * }
  TSearchField_ = record
    Name: U_String; { Field name. Set by FindFirst/Next. }
    Description: U_String; { Field description. Set by FindFirst/Next. }
    HeaderCount: Int64; { Number of child entries. Set by FindFirst/Next. }
    HeaderPOS: Int64; { File position of the field header. Set by FindFirst/Next. }
    CompleteCount: Int64; { Number of fields found so far. Set by FindFirst/Next. }
    FieldSearch: TFieldSearch; { Internal search state. Set by FindFirst/Next. }
  end;

  { * TRecursionSearch_ 每 state for recursive traversal of the entire database * }
  { * tree. Used by db_RecursionSearchFirst/Next.                              * }
  TRecursionSearch_ = record
    ReturnHeader: THeader; { Current header found. Set by search functions. }
    CurrentField: TField; { Current field being traversed. Set by search functions. }
    InitPath: U_String; { Starting path for recursion. Set by RecursionSearchFirst. }
    FilterName: U_String; { Filter pattern for names. Set by RecursionSearchFirst. }
    SearchBuffGo: Integer; { Current depth in the recursion stack. Set by search functions. }
    SearchBuff: array [0 .. DB_Max_Secursion_Level] of TFieldSearch; { Stack of search states for each recursion level. Set by search functions. }
  end;

  { * Internal helper functions 每 calculate record sizes and manage low-level * }
  { * I/O operations. These are used internally by the library.               * }
function Get_DB_StringL(var IOHnd: TIOHnd): Integer; { * Returns the fixed string length configured for the I/O handle. * }
function Get_DB_HeaderL(var IOHnd: TIOHnd): Integer; { * Returns the total size in bytes of a THeader record. * }
function Get_DB_ItemL(var IOHnd: TIOHnd): Integer; { * Returns the total size in bytes of a TItem record (without its header). * }
function Get_DB_BlockL(var IOHnd: TIOHnd): Integer; { * Returns the total size in bytes of a TItemBlock record. * }
function Get_DB_FieldL(var IOHnd: TIOHnd): Integer; { * Returns the total size in bytes of a TField record (without its header). * }
function Get_DB_L(var IOHnd: TIOHnd): Integer; { * Returns the total size in bytes of the database header. * }

{ * Utility functions 每 error translation, string/reserved data conversion. * }
function TranslateReturnCode(const ReturnCode: Integer): U_String; { * Translates a numeric return code to a human-readable string. * }
function Test_Reserved_String(S: U_String): Boolean; { * Tests if a string can fit into the reserved data area. * }
function String_To_Reserved(S: U_String): TObjectDataHandle_Reserved_Data; { * Converts a Pascal string to the fixed-size reserved data buffer. * }
function Reserved_To_String(Reserved: TObjectDataHandle_Reserved_Data): U_String; { * Converts the reserved data buffer back to a Pascal string. * }

{ * Initialisation functions 每 set default values for all record types.    * }
procedure Init_THeader(var Header_: THeader); { * Initialises a THeader to default values. * }
procedure Init_TItemBlock(var Block_: TItemBlock); { * Initialises a TItemBlock to default values. * }
procedure Init_TItem(var Item_: TItem); { * Initialises a TItem to default values. * }
procedure Init_TField(var Field_: TField); { * Initialises a TField to default values. * }
procedure Init_TTMDB(var DB_: TObjectDataHandle); overload; { * Initialises a TObjectDataHandle to default values. * }
procedure Init_TTMDB(var DB_: TObjectDataHandle; const FixedStringL: Byte); overload; { * Initialises a TObjectDataHandle with a custom fixed string length. * }

{ * Runtime structure initialisation functions. * }
procedure Init_TFieldSearch(var FieldS_: TFieldSearch); { * Initialises a TFieldSearch state. * }
procedure Init_TTMDBItemHandle(var ItemHnd_: TItemHandle_); { * Initialises a TItemHandle_. * }
procedure Init_TTMDBSearchHeader(var SearchHeader_: TSearchHeader_); { * Initialises a TSearchHeader_. * }
procedure Init_TTMDBSearchItem(var SearchItem_: TSearchItem_); { * Initialises a TSearchItem_. * }
procedure Init_TTMDBSearchField(var SearchField_: TSearchField_); { * Initialises a TSearchField_. * }
procedure Init_TTMDBRecursionSearch(var RecursionSearch_: TRecursionSearch_); { * Initialises a TRecursionSearch_ state. * }

{ * Low-level record I/O functions 每 read/write individual records to/from  * }
{ * the file at specified positions. All these functions are internal and   * }
{ * used by the higher-level API.                                           * }
function dbHeader_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Writes a THeader record at position fPos. * }
function dbHeader_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Reads a THeader record from position fPos. * }
function dbHeader_ReadReservedRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Reads only the basic fields of a header (not the full structure). * }
function dbItem_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Writes a complete TItem record (header + item data) at position fPos. * }
function dbItem_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Reads a complete TItem record from position fPos. * }
function dbField_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Writes a complete TField record (header + field data) at position fPos. * }
function dbField_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Reads a complete TField record from position fPos. * }
function dbItem_OnlyWriteItemBlockRec(const fPos: Int64; var IOHnd: TIOHnd; var Block_: TItemBlock): Boolean; { * Writes a TItemBlock record only (no header). * }
function dbItem_OnlyReadItemBlockRec(const fPos: Int64; var IOHnd: TIOHnd; var Block_: TItemBlock): Boolean; { * Reads a TItemBlock record only. * }
function db_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var DB_: TObjectDataHandle): Boolean; { * Writes the database header record at position fPos. * }
function db_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var DB_: TObjectDataHandle): Boolean; { * Reads the database header record from position fPos. * }
function dbItem_OnlyWriteItemRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Writes the item record data only (without the header). * }
function dbItem_OnlyReadItemRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Reads the item record data only (without the header). * }
function dbField_OnlyWriteFieldRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Writes the field record data only (without the header). * }
function dbField_OnlyReadFieldRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Reads the field record data only (without the header). * }

{ * Search and matching functions 每 internal helpers for finding entries.  * }
function dbMultipleMatch(const SourStr, DestStr: U_String): Boolean; { * Performs wildcard matching on header names. Uses ZDB_Header_Multiple_* globals. * }
function dbHeader_FindNext(const Name: U_String; const FirstHeaderPOS, LastHeaderPOS: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Finds the next header matching a name pattern within a linked list range. * }
function dbHeader_FindPrev(const Name: U_String; const LastHeaderPOS, FirstHeaderPOS: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Finds the previous header matching a name pattern within a linked list range. * }

{ * Item block management 每 low-level block operations. * }
function dbItem_BlockCreate(var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Creates a new block for an item. * }
function dbItem_BlockInit(var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Initialises the block system for an item (reads first block). * }
function dbItem_BlockReadData(var IOHnd: TIOHnd; var Item_: TItem; var Buff_; const _Size: Int64): Boolean; { * Reads data from the current block position. * }
function dbItem_BlockAppendWriteData(var IOHnd: TIOHnd; var Item_: TItem; const Buff_; const Size: Int64): Boolean; { * Appends data to the end of the item, creating new blocks as needed. * }
function dbItem_BlockWriteData(var IOHnd: TIOHnd; var Item_: TItem; const Buff_; const Size: Int64): Boolean; { * Writes data at the current block position. * }
function dbItem_BlockSeekPOS(var IOHnd: TIOHnd; var Item_: TItem; const Position: Int64): Boolean; { * Seeks to a specific position within the item's data. * }
function dbItem_BlockGetPOS(var IOHnd: TIOHnd; var Item_: TItem): Int64; { * Returns the current seek position within the item. * }
function dbItem_BlockSeekStartPOS(var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Seeks to the start of the item's data. * }
function dbItem_BlockSeekLastPOS(var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Seeks to the end of the item's data. * }

{ * Field-level operations 每 internal functions for field and header        * }
{ * management within fields.                                               * }
function dbField_GetPOSField(const fPos: Int64; var IOHnd: TIOHnd): TField; { * Reads a field at a given position. * }
function dbField_GetFirstHeader(const fPos: Int64; var IOHnd: TIOHnd): THeader; { * Reads the first header in a field. * }
function dbField_GetLastHeader(const fPos: Int64; var IOHnd: TIOHnd): THeader; { * Reads the last header in a field. * }
function dbField_OnlyFindFirstName(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the first header matching a name pattern in a field. * }
function dbField_OnlyFindNextName(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the next header in a search. * }
function dbField_OnlyFindLastName(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the last header matching a name pattern in a field. * }
function dbField_OnlyFindPrevName(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the previous header in a search. * }
function dbField_FindFirst(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the first header matching name and ID in a field. * }
function dbField_FindNext(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the next header in a search (with ID filtering). * }
function dbField_FindLast(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the last header matching name and ID in a field. * }
function dbField_FindPrev(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; { * Finds the previous header in a search (with ID filtering). * }

{ * Item search functions 每 find items within fields. * }
function dbField_FindFirstItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean; overload; { * Finds the first item matching a name pattern and ExtID. * }
function dbField_FindNextItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean; overload; { * Finds the next item in a search. * }
function dbField_FindLastItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean; overload; { * Finds the last item matching a name pattern and ExtID. * }
function dbField_FindPrevItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean; overload; { * Finds the previous item in a search. * }
function dbField_FindFirstItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; overload; { * Simplified version of FindFirstItem that does not return the Item. * }
function dbField_FindNextItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; overload; { * Simplified version of FindNextItem that does not return the Item. * }
function dbField_FindLastItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; overload; { * Simplified version of FindLastItem that does not return the Item. * }
function dbField_FindPrevItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean; overload; { * Simplified version of FindPrevItem that does not return the Item. * }
function dbField_ExistItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd): Boolean; { * Checks if an item exists in a field. * }
function dbField_ExistHeader(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd): Boolean; { * Checks if a header (Field or Item) exists in a field. * }

{ * Header creation/deletion/movement functions. * }
function dbField_CreateHeader(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean; { * Creates a new header in a field. * }
function dbField_InsertNewHeader(const Name: U_String; const ID: Byte; const FieldPos, InsertHeaderPos: Int64; var IOHnd: TIOHnd; var NewHeader: THeader): Boolean; { * Inserts a new header at a specific position in a field's linked list. * }
function dbField_DeleteHeader(const HeaderPOS, FieldPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Deletes a header from a field. * }
function dbField_MoveHeader(const HeaderPOS: Int64; const SourcerFieldPOS, TargetFieldPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Moves a header from one field to another. * }
function dbField_CreateField(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Creates a new Field. * }
function dbField_InsertNewField(const Name: U_String; const FieldPos, CurrentInsertPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean; { * Inserts a new Field at a specific position. * }
function dbField_CreateItem(const Name: U_String; const ExterID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Creates a new Item. * }
function dbField_InsertNewItem(const Name: U_String; const ExterID: Byte; const FieldPos, CurrentInsertPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean; { * Inserts a new Item at a specific position. * }
function dbField_CopyItem(var Item_: TItem; var IOHnd: TIOHnd; const DestFieldPos: Int64; var DestIOHnd: TIOHnd): Boolean; { * Copies an Item to a destination field. * }
function dbField_CopyItemBuffer(var Item_: TItem; var IOHnd: TIOHnd; var DestItem_: TItem; var DestIOHnd: TIOHnd): Boolean; { * Copies an Item's data buffer to another Item. * }
function dbField_CopyAllTo(const FilterName: U_String; const FieldPos: Int64; var IOHnd: TIOHnd; const DestFieldPos: Int64; var DestIOHnd: TIOHnd): Boolean; { * Copies all items and sub-fields matching a filter from one field to another. * }

{ * Database API 每 public interface for database management. * }
function db_CreateNew(const FileName: U_String; var DB_: TObjectDataHandle): Boolean; { * Creates a new database file on disk. * }
function db_Open(const FileName: U_String; var DB_: TObjectDataHandle; _OnlyRead: Boolean): Boolean; { * Opens an existing database file. * }
function db_CreateAsStream(stream: U_Stream; const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean; { * Creates a database from an existing stream. * }
function db_OpenAsStream(stream: U_Stream; const Name: U_String; var DB_: TObjectDataHandle; _OnlyRead: Boolean): Boolean; { * Opens a database from an existing stream. * }
function db_ClosePack(var DB_: TObjectDataHandle): Boolean; { * Closes the database and flushes all changes. * }

{ * Database copy functions 每 copy data between databases. * }
function db_CopyFieldTo(const FilterName: U_String; var DB_: TObjectDataHandle; const SourceFieldPos: Int64; var DestTMDB: TObjectDataHandle; const DestFieldPos: Int64): Boolean; { * Copies a filtered set of data from one field to another database. * }
function db_CopyAllTo(var DB_: TObjectDataHandle; var DestTMDB: TObjectDataHandle): Boolean; { * Copies all data from one database to another. * }
function db_CopyAllToDestPath(var DB_: TObjectDataHandle; var DestTMDB: TObjectDataHandle; destPath: U_String): Boolean; { * Copies all data to a specific path in the destination database. * }

{ * Database update and maintenance functions. * }
function db_Update(var DB_: TObjectDataHandle): Boolean; { * Flushes and updates the database header. * }

{ * Name validation. * }
function db_TestName(const Name: U_String): Boolean; { * Tests if a name is valid (non-empty and contains no path separators). * }

{ * Field management API 每 create, delete, rename, and navigate fields.  * }
function db_CheckRootField(const Name: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean; { * Ensures a root field exists, creating it if necessary. * }
function db_CreateRootHeader(const Name: U_String; const ID: Byte; var DB_: TObjectDataHandle; var Header_: THeader): Boolean; { * Creates a root-level header (Field or Item). * }
function db_CreateRootField(const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean; { * Creates a root-level Field. * }
function db_CreateAndSetRootField(const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean; { * Creates and sets the default root field. * }
function db_CreateField(const pathName, Description: U_String; var DB_: TObjectDataHandle): Boolean; { * Creates a Field at a given path. * }
function db_SetFieldName(const pathName, OriginFieldName, NewFieldName, FieldDescription: U_String; var DB_: TObjectDataHandle): Boolean; { * Renames a Field and updates its description. * }
function db_SetItemName(const pathName, OriginItemName, NewItemName, ItemDescription: U_String; var DB_: TObjectDataHandle): Boolean; { * Renames an Item and updates its description. * }
function db_DeleteField(const pathName, FilterName: U_String; var DB_: TObjectDataHandle): Boolean; { * Deletes a Field and all its contents. * }

{ * Header (Field/Item) deletion and movement. * }
function db_DeleteHeader(const pathName, FilterName: U_String; const ID: Byte; var DB_: TObjectDataHandle): Boolean; { * Deletes a header (Field or Item) by path and name. * }
function db_MoveItem(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Moves an Item from one path to another. * }
function db_MoveField(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; var DB_: TObjectDataHandle): Boolean; { * Moves a Field from one path to another. * }
function db_MoveHeader(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; const HeaderID: Byte; var DB_: TObjectDataHandle): Boolean; { * Moves a header (Field or Item) from one path to another. * }

{ * Current field navigation. * }
function db_SetCurrentRootField(const Name: U_String; var DB_: TObjectDataHandle): Boolean; { * Sets the current working field to a root field by name. * }
function db_SetCurrentField(const pathName: U_String; var DB_: TObjectDataHandle): Boolean; { * Sets the current working field by full path. * }

{ * Field retrieval. * }
function db_GetRootField(const Name: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean; { * Retrieves a root Field by name. * }
function db_GetField(const pathName: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean; { * Retrieves a Field by full path. * }
function db_GetPath(const FieldPos, RootFieldPos: Int64; var DB_: TObjectDataHandle; var RetPath: U_String): Boolean; { * Returns the full path of a Field given its position. * }

{ * Easy Item creation and deletion. * }
function db_NewItem(const pathName, ItemName, ItemDescription: U_String; const ItemExtID: Byte; var Item_: TItem; var DB_: TObjectDataHandle): Boolean; { * Creates a new Item (file) at the specified path. * }
function db_DeleteItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Deletes an Item by path and name. * }
function db_DeleteItem2(const FieldPos: Int64; const Item_Name: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Deletes an Item by field position and name. * }
function db_GetItem(const pathName, ItemName: U_String; const ItemExtID: Byte; var Item_: TItem; var DB_: TObjectDataHandle): Boolean; { * Retrieves an Item by path and name. * }

{ * Advanced Item operations 每 create/open/close/read/write with handles. * }
function db_ItemCreate(const pathName, ItemName, ItemDescription: U_String; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Creates an Item and returns a handle for I/O operations. * }
function db_ItemFastCreate(const ItemName, ItemDescription: U_String; const fPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Fast creates an Item directly in a field position (no path traversal). * }
function db_ItemFastInsertNew(const ItemName, ItemDescription: U_String; const FieldPos, InsertHeaderPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Inserts a new Item at a specific position in a field. * }
function db_ItemOpen(const pathName, ItemName: U_String; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Opens an existing Item by path and name, returning a handle. * }
function db_ItemFastOpen(const fPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Fast opens an Item directly by its header position. * }
function db_ItemClose(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Closes an Item handle, flushing any pending changes. * }
function db_ItemUpdate(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Updates an Item's metadata (header and description). * }
function db_ItemBodyReset(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Resets an Item's body data (clears all blocks). * }
function db_ItemReName(const FieldPos: Int64; const NewItemName, NewItemDescription: U_String; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Renames an Item and updates its description. * }

{ * Item I/O operations 每 read/write data from/to an open Item. * }
function db_ItemRead(const Size: Int64; var Buff_; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Reads data from the current position in the Item. * }
function db_ItemWrite(const Size: Int64; const Buff_; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Writes data to the current position in the Item. * }

{ * Item position management 每 seek and size operations. * }
function db_ItemSeekPos(const fPos: Int64; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Seeks to a specific position within the Item. * }
function db_ItemSeekStartPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Seeks to the beginning of the Item. * }
function db_ItemSeekLastPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean; { * Seeks to the end of the Item. * }
function db_ItemGetPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Int64; { * Returns the current seek position within the Item. * }
function db_ItemGetSize(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Int64; { * Returns the total size of the Item's data. * }
function db_AppendItemSize(var ItemHnd_: TItemHandle_; const Size: Int64; var DB_: TObjectDataHandle): Boolean; { * Appends a zero-filled block of the specified size to the Item. * }

{ * Search API 每 find headers, items, and fields with wildcard support. * }
function db_ExistsRootField(const Name: U_String; var DB_: TObjectDataHandle): Boolean; { * Checks if a root field exists. * }
function db_FindFirstHeader(const pathName, FilterName: U_String; const ID: Byte; var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean; { * Finds the first header (Field or Item) matching a filter in a path. * }
function db_FindNextHeader(var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean; { * Finds the next header in a search. * }
function db_FindLastHeader(const pathName, FilterName: U_String; const ID: Byte; var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean; { * Finds the last header matching a filter in a path. * }
function db_FindPrevHeader(var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean; { * Finds the previous header in a search. * }
function db_FindFirstItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean; { * Finds the first Item matching a filter in a path. * }
function db_FindNextItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Finds the next Item in a search. * }
function db_FindLastItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean; { * Finds the last Item matching a filter in a path. * }
function db_FindPrevItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Finds the previous Item in a search. * }
function db_FastFindFirstItem(const FieldPos: Int64; const FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean; { * Fast find first Item 每 searches directly in a field position. * }
function db_FastFindNextItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Fast find next Item. * }
function db_FastFindLastItem(const FieldPos: Int64; const FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean; { * Fast find last Item. * }
function db_FastFindPrevItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean; { * Fast find previous Item. * }
function db_FindFirstField(const pathName, FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Finds the first Field matching a filter in a path. * }
function db_FindNextField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Finds the next Field in a search. * }
function db_FindLastField(const pathName, FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Finds the last Field matching a filter in a path. * }
function db_FindPrevField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Finds the previous Field in a search. * }
function db_FastFindFirstField(const FieldPos: Int64; const FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Fast find first Field 每 searches directly in a field position. * }
function db_FastFindNextField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Fast find next Field. * }
function db_FastFindLastField(const FieldPos: Int64; const FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Fast find last Field. * }
function db_FastFindPrevField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean; { * Fast find previous Field. * }

{ * Recursive search 每 traverse the entire database tree. * }
function db_RecursionSearchFirst(const InitPath, FilterName: U_String; var SenderRecursionSearch: TRecursionSearch_; var DB_: TObjectDataHandle): Boolean; { * Starts a recursive search from a given path, returning the first match. * }
function db_RecursionSearchNext(var SenderRecursionSearch: TRecursionSearch_; var DB_: TObjectDataHandle): Boolean; { * Continues a recursive search, returning the next match. * }

var
  { Global configuration variables for wildcard matching. }
  ZDB_Header_Multiple_Char__: U_String; { Single-character wildcard, default '?'. Set by user. }
  ZDB_Header_Multiple_String__: U_String; { Multi-character wildcard, default '*'. Set by user. }
  ZDB_Field_Separator__: U_String; { Path separator, default '/\'. Set by user. }

implementation

function Get_DB_StringL(var IOHnd: TIOHnd): Integer;
begin
  Result := IOHnd.FixedStringL;
end;

function Get_DB_HeaderL(var IOHnd: TIOHnd): Integer;
begin
  Result := (Get_DB_StringL(IOHnd) * 1) +
    (DB_Position_Size * 3) +
    (DB_Time_Size * 2) +
    (DB_ID_Size * 2) +
    (DB_Property_Size * 1);
end;

function Get_DB_ItemL(var IOHnd: TIOHnd): Integer;
begin
  Result := (Get_DB_StringL(IOHnd) * 1) +
    (DB_ID_Size * 1) +
    (DB_Position_Size * 2) +
    (DB_DataSize_Size * 1) +
    (DB_Counter_Size * 1);
end;

function Get_DB_BlockL(var IOHnd: TIOHnd): Integer;
begin
  Result := (DB_ID_Size * 1) +
    (DB_Position_Size * 4) +
    (DB_DataSize_Size * 1);
end;

function Get_DB_FieldL(var IOHnd: TIOHnd): Integer;
begin
  Result := (Get_DB_StringL(IOHnd) * 1) +
    (DB_Counter_Size * 1) +
    (DB_Position_Size * 3);
end;

function Get_DB_L(var IOHnd: TIOHnd): Integer;
begin
  Result := (DB_ReservedData_Size * 1) +
    (DB_FixedStringL_Size * 1) +
    (DB_Version_Size * 2) +
    (DB_Time_Size * 2) +
    (DB_Counter_Size * 1) +
    (DB_Position_Size * 4) +
    (DB_Level_Size * 1);
end;

function TranslateReturnCode(const ReturnCode: Integer): U_String;
begin
  case ReturnCode of
    DB_Header_ok: Result := 'DB_Header_ok';
    DB_Header_SetPosError: Result := 'DB_Header_SetPosError';
    DB_Header_WritePosError: Result := 'DB_Header_WritePosError';
    DB_Header_WriteNextPosError: Result := 'DB_Header_WriteNextPosError';
    DB_Header_WritePrevPosError: Result := 'DB_Header_WritePrevPosError';
    DB_Header_WritePubMainPosError: Result := 'DB_Header_WritePubMainPosError';
    DB_Header_WriteIDError: Result := 'DB_Header_WriteIDError';
    DB_Header_WritePositionIDError: Result := 'DB_Header_WritePositionIDError';
    DB_Header_WriteNameError: Result := 'DB_Header_WriteNameError';
    DB_Header_WriteCreateTimeError: Result := 'DB_Header_WriteCreateTimeError';
    DB_Header_WriteLastEditTimeError: Result := 'DB_Header_WriteLastEditTimeError';
    DB_Header_WriteUserPropertyIDError: Result := 'DB_Header_WriteUserPropertyIDError';
    DB_Header_ReadPosError: Result := 'DB_Header_ReadPosError';
    DB_Header_ReadNextPosError: Result := 'DB_Header_ReadNextPosError';
    DB_Header_ReadPrevPosError: Result := 'DB_Header_ReadPrevPosError';
    DB_Header_ReadPubMainPosError: Result := 'DB_Header_ReadPubMainPosError';
    DB_Header_ReadIDError: Result := 'DB_Header_ReadIDError';
    DB_Header_ReadPositionIDError: Result := 'DB_Header_ReadPositionIDError';
    DB_Header_ReadNameError: Result := 'DB_Header_ReadNameError';
    DB_Header_ReadCreateTimeError: Result := 'DB_Header_ReadCreateTimeError';
    DB_Header_ReadLastEditTimeError: Result := 'DB_Header_ReadLastEditTimeError';
    DB_Header_ReadUserPropertyIDError: Result := 'DB_Header_ReadUserPropertyIDError';
    DB_Header_NotFindHeader: Result := 'DB_Header_NotFindHeader';
    DB_Item_ok: Result := 'DB_Item_ok';
    DB_Item_SetPosError: Result := 'DB_Item_SetPosError';
    DB_Item_WriteRecDescriptionError: Result := 'DB_Item_WriteRecDescriptionError';
    DB_Item_WriteRecExterIDError: Result := 'DB_Item_WriteRecExterIDError';
    DB_Item_WriteFirstBlockPOSError: Result := 'DB_Item_WriteFirstBlockPOSError';
    DB_Item_WriteLastBlockPOSError: Result := 'DB_Item_WriteLastBlockPOSError';
    DB_Item_WriteRecBuffSizeError: Result := 'DB_Item_WriteRecBuffSizeError';
    DB_Item_WriteBlockCountError: Result := 'DB_Item_WriteBlockCountError';
    DB_Item_ReadRecDescriptionError: Result := 'DB_Item_ReadRecDescriptionError';
    DB_Item_ReadRecExterIDError: Result := 'DB_Item_ReadRecExterIDError';
    DB_Item_ReadFirstBlockPOSError: Result := 'DB_Item_ReadFirstBlockPOSError';
    DB_Item_ReadLastBlockPOSError: Result := 'DB_Item_ReadLastBlockPOSError';
    DB_Item_ReadRecBuffSizeError: Result := 'DB_Item_ReadRecBuffSizeError';
    DB_Item_ReadBlockCountError: Result := 'DB_Item_ReadBlockCountError';
    DB_Item_WriteItemBlockIDFlagsError: Result := 'DB_Item_WriteItemBlockIDFlagsError';
    DB_Item_WriteCurrentBlockPOSError: Result := 'DB_Item_WriteCurrentBlockPOSError';
    DB_Item_WriteNextBlockPOSError: Result := 'DB_Item_WriteNextBlockPOSError';
    DB_Item_WritePrevBlockPOSError: Result := 'DB_Item_WritePrevBlockPOSError';
    DB_Item_WriteDataBlockPOSError: Result := 'DB_Item_WriteDataBlockPOSError';
    DB_Item_WriteDataBuffSizeError: Result := 'DB_Item_WriteDataBuffSizeError';
    DB_Item_ReadItemBlockIDFlagsError: Result := 'DB_Item_ReadItemBlockIDFlagsError';
    DB_Item_ReadCurrentBlockPOSError: Result := 'DB_Item_ReadCurrentBlockPOSError';
    DB_Item_ReadNextBlockPOSError: Result := 'DB_Item_ReadNextBlockPOSError';
    DB_Item_ReadPrevBlockPOSError: Result := 'DB_Item_ReadPrevBlockPOSError';
    DB_Item_ReadDataBlockPOSError: Result := 'DB_Item_ReadDataBlockPOSError';
    DB_Item_ReadDataBuffSizeError: Result := 'DB_Item_ReadDataBuffSizeError';
    DB_Item_BlockPositionError: Result := 'DB_Item_BlockPositionError';
    DB_Item_BlockOverrate: Result := 'DB_Item_BlockOverrate';
    DB_Item_BlockReadError: Result := 'DB_Item_BlockReadError';
    DB_Item_BlockWriteError: Result := 'DB_Item_BlockWriteError';
    DB_Field_ok: Result := 'DB_Field_ok';
    DB_Field_SetPosError: Result := 'DB_Field_SetPosError';
    DB_Field_WriteHeaderFieldPosError: Result := 'DB_Field_WriteHeaderFieldPosError';
    DB_Field_WriteDescriptionError: Result := 'DB_Field_WriteDescriptionError';
    DB_Field_WriteCountError: Result := 'DB_Field_WriteCountError';
    DB_Field_WriteFirstPosError: Result := 'DB_Field_WriteFirstPosError';
    DB_Field_WriteLastPosError: Result := 'DB_Field_WriteLastPosError';
    DB_Field_ReadHeaderFieldPosError: Result := 'DB_Field_ReadHeaderFieldPosError';
    DB_Field_ReadDescriptionError: Result := 'DB_Field_ReadDescriptionError';
    DB_Field_ReadCountError: Result := 'DB_Field_ReadCountError';
    DB_Field_ReadFirstPosError: Result := 'DB_Field_ReadFirstPosError';
    DB_Field_ReadLastPosError: Result := 'DB_Field_ReadLastPosError';
    DB_Field_NotInitSearch: Result := 'DB_Field_NotInitSearch';
    DB_Field_DeleteHeaderError: Result := 'DB_Field_DeleteHeaderError';
    DB_ok: Result := 'DB_ok';
    DB_RepOpenPackError: Result := 'DB_RepOpenPackError';
    DB_CreatePackError: Result := 'DB_CreatePackError';
    DB_WriteReservedDataError: Result := 'DB_WriteReservedDataError';
    DB_WriteNameError: Result := 'DB_WriteNameError';
    DB_WriteDescriptionError: Result := 'DB_WriteDescriptionError';
    DB_PositionSeekError: Result := 'DB_PositionSeekError';
    DB_WriteMajorVersionError: Result := 'DB_WriteMajorVersionError';
    DB_WriteMinorVersionError: Result := 'DB_WriteMinorVersionError';
    DB_WriteCreateTimeError: Result := 'DB_WriteCreateTimeError';
    DB_WriteLastEditTimeError: Result := 'DB_WriteLastEditTimeError';
    DB_WriteHeaderCountError: Result := 'DB_WriteHeaderCountError';
    DB_WriteDefaultPositionError: Result := 'DB_WriteDefaultPositionError';
    DB_WriteFirstPositionError: Result := 'DB_WriteFirstPositionError';
    DB_WriteLastPositionError: Result := 'DB_WriteLastPositionError';
    DB_WriteFixedStringLError: Result := 'DB_WriteFixedStringLError';
    DB_ReadReservedDataError: Result := 'DB_ReadReservedDataError';
    DB_ReadNameError: Result := 'DB_ReadNameError';
    DB_ReadDescriptionError: Result := 'DB_ReadDescriptionError';
    DB_ReadMajorVersionError: Result := 'DB_ReadMajorVersionError';
    DB_ReadMinorVersionError: Result := 'DB_ReadMinorVersionError';
    DB_ReadCreateTimeError: Result := 'DB_ReadCreateTimeError';
    DB_ReadLastEditTimeError: Result := 'DB_ReadLastEditTimeError';
    DB_ReadHeaderCountError: Result := 'DB_ReadHeaderCountError';
    DB_ReadDefaultPositionError: Result := 'DB_ReadDefaultPositionError';
    DB_ReadFirstPositionError: Result := 'DB_ReadFirstPositionError';
    DB_ReadLastPositionError: Result := 'DB_ReadLastPositionError';
    DB_ReadFixedStringLError: Result := 'DB_ReadFixedStringLError';
    DB_RepCreatePackError: Result := 'DB_RepCreatePackError';
    DB_OpenPackError: Result := 'DB_OpenPackError';
    DB_ClosePackError: Result := 'DB_ClosePackError';
    DB_WriteCurrentPositionError: Result := 'DB_WriteCurrentPositionError';
    DB_WriteCurrentLevelError: Result := 'DB_WriteCurrentLevelError';
    DB_ReadCurrentPositionError: Result := 'DB_ReadCurrentPositionError';
    DB_ReadCurrentLevelError: Result := 'DB_ReadCurrentLevelError';
    DB_PathNameError: Result := 'DB_PathNameError';
    DB_RepeatCreateItemError: Result := 'DB_RepeatCreateItemError';
    DB_OpenItemError: Result := 'DB_OpenItemError';
    DB_ItemNameError: Result := 'DB_ItemNameError';
    DB_RepeatOpenItemError: Result := 'DB_RepeatOpenItemError';
    DB_CloseItemError: Result := 'DB_CloseItemError';
    DB_ItemStructNotFindDescription: Result := 'DB_ItemStructNotFindDescription';
    DB_RecursionSearchOver: Result := 'DB_RecursionSearchOver';
    DB_FileBufferError: Result := 'DB_FileBufferError';
    DB_CheckIOError: Result := 'DB_CheckIOError';
    DB_ExceptionError: Result := 'DB_ExceptionError';
    else Result := 'unknow error';
  end;
end;

function db_GetPathCount(const StrName: U_String): Integer;
begin
  Result := umlGetIndexStrCount(StrName, ZDB_Field_Separator__);
end;

function db_DeleteFirstPath(const pathName: U_String): U_String;
begin
  Result := umlDeleteFirstStr(pathName, ZDB_Field_Separator__);
end;

function db_DeleteLastPath(const pathName: U_String): U_String;
begin
  Result := umlDeleteLastStr(pathName, ZDB_Field_Separator__);
end;

function db_GetFirstPath(const pathName: U_String): U_String;
begin
  Result := umlGetFirstStr(pathName, ZDB_Field_Separator__);
end;

function db_GetLastPath(const pathName: U_String): U_String;
begin
  Result := umlGetLastStr(pathName, ZDB_Field_Separator__);
end;

function Test_Reserved_String(S: U_String): Boolean;
var
  buff: TBytes;
  L, RL: Integer;
begin
  RL := sizeOf(TObjectDataHandle_Reserved_Data);
  buff := S.Bytes;
  L := length(buff);
  Result := L < RL - 1;
end;

function String_To_Reserved(S: U_String): TObjectDataHandle_Reserved_Data;
var
  buff: TBytes;
  L, RL: Integer;
begin
  RL := sizeOf(TObjectDataHandle_Reserved_Data);
  FillPtr(@Result[0], RL, 0);
  if S.L <= 0 then
      exit;
  buff := S.Bytes;
  L := length(buff);
  if L < RL - 1 then
      CopyPtr(@buff[0], @Result[0], L)
  else
      CopyPtr(@buff[0], @Result[0], RL - 1);
  SetLength(buff, 0);
end;

function Reserved_To_String(Reserved: TObjectDataHandle_Reserved_Data): U_String;
var
  i: Integer;
  RL: Integer;
  buff: TBytes;
begin
  try
    RL := sizeOf(TObjectDataHandle_Reserved_Data);
    i := 0;
    while i < RL do
      if Reserved[i] > 0 then
          inc(i)
      else
          break;
    SetLength(buff, i);
    if i > 0 then
        CopyPtr(@Reserved[0], @buff[0], i);
    Result.Bytes := buff;
    SetLength(buff, 0);
  except
      Result := '';
  end;
end;

procedure Init_THeader(var Header_: THeader);
begin
  Header_.CurrentHeader := 0;
  Header_.NextHeader := 0;
  Header_.PrevHeader := 0;
  Header_.DataPosition := 0;
  Header_.CreateTime := 0;
  Header_.ModificationTime := 0;
  Header_.ID := 0;
  Header_.PositionID := 0;
  Header_.UserProperty := 0;
  Header_.Name := '';
  Header_.State := DB_Header_ok;
end;

procedure Init_TItemBlock(var Block_: TItemBlock);
begin
  Block_.ID := 0;
  Block_.CurrentBlockPOS := 0;
  Block_.NextBlockPOS := 0;
  Block_.PrevBlockPOS := 0;
  Block_.DataPosition := 0;
  Block_.Size := 0;
  Block_.State := DB_Item_ok;
end;

procedure Init_TItem(var Item_: TItem);
begin
  Init_THeader(Item_.RHeader);
  Item_.Description := '';
  Item_.ExtID := 0;
  Item_.FirstBlockPOS := 0;
  Item_.LastBlockPOS := 0;
  Item_.Size := 0;
  Item_.BlockCount := 0;
  Item_.CurrentBlockSeekPOS := 0;
  Item_.CurrentFileSeekPOS := 0;
  Init_TItemBlock(Item_.CurrentItemBlock);
  Item_.DataModification := False;
  Item_.State := DB_Item_ok;
end;

procedure Init_TField(var Field_: TField);
begin
  Field_.UpFieldPOS := 0;
  Field_.Description := '';
  Field_.HeaderCount := 0;
  Field_.FirstHeaderPOS := 0;
  Field_.LastHeaderPOS := 0;
  Init_THeader(Field_.RHeader);
  Field_.State := DB_Field_ok;
end;

procedure Init_TTMDB(var DB_: TObjectDataHandle);
begin
  Init_TTMDB(DB_, 64 + 1);
end;

procedure Init_TTMDB(var DB_: TObjectDataHandle; const FixedStringL: Byte);
begin
  InitIOHnd(DB_.IOHnd);
  DB_.IOHnd.FixedStringL := FixedStringL;
  FillPtrByte(@DB_.ReservedData[0], DB_ReservedData_Size, 0);
  DB_.FixedStringL := DB_.IOHnd.FixedStringL;
  DB_.MajorVer := 0;
  DB_.MinorVer := 0;
  DB_.CreateTime := 0;
  DB_.ModificationTime := 0;
  DB_.RootHeaderCount := 0;
  DB_.DefaultFieldPOS := 0;
  DB_.FirstHeaderPOS := 0;
  DB_.LastHeaderPOS := 0;
  DB_.CurrentFieldPOS := 0;
  DB_.CurrentFieldLevel := 0;
  DB_.IOHnd.Data := @DB_;
  DB_.OverWriteItem := True;
  DB_.AllowSameHeaderName := False;

  DB_.OnError := nil;

  DB_.OnDeleteHeader := nil;

  DB_.OnPrepareWriteHeader := nil;
  DB_.OnWriteHeader := nil;
  DB_.OnReadHeader := nil;

  DB_.OnPrepareWriteItemBlock := nil;
  DB_.OnWriteItemBlock := nil;
  DB_.OnReadItemBlock := nil;

  DB_.OnPrepareWriteItem := nil;
  DB_.OnWriteItem := nil;
  DB_.OnReadItem := nil;

  DB_.OnPrepareOnlyWriteItemRec := nil;
  DB_.OnOnlyWriteItemRec := nil;
  DB_.OnOnlyReadItemRec := nil;

  DB_.OnPrepareWriteField := nil;
  DB_.OnWriteField := nil;
  DB_.OnReadField := nil;

  DB_.OnPrepareOnlyWriteFieldRec := nil;
  DB_.OnOnlyWriteFieldRec := nil;
  DB_.OnOnlyReadFieldRec := nil;

  DB_.OnPrepareWriteTMDB := nil;
  DB_.OnWriteTMDB := nil;
  DB_.OnReadTMDB := nil;

  DB_.State := DB_ok;
end;

procedure Init_TFieldSearch(var FieldS_: TFieldSearch);
begin
  FieldS_.InitFlags := False;
  FieldS_.StartPos := 0;
  FieldS_.OverPOS := 0;
  FieldS_.Name := '';
  FieldS_.ID := 0;
  FieldS_.PositionID := 0;
  Init_THeader(FieldS_.RHeader);
  FieldS_.State := DB_Field_ok;
end;

procedure Init_TTMDBItemHandle(var ItemHnd_: TItemHandle_);
begin
  Init_TItem(ItemHnd_.Item);
  ItemHnd_.Name := '';
  ItemHnd_.Description := '';
  ItemHnd_.CreateTime := 0;
  ItemHnd_.ModificationTime := 0;
  ItemHnd_.ItemExtID := 0;
  ItemHnd_.OpenFlags := False;
end;

procedure Init_TTMDBSearchHeader(var SearchHeader_: TSearchHeader_);
begin
  SearchHeader_.Name := '';
  SearchHeader_.ID := 0;
  SearchHeader_.CreateTime := 0;
  SearchHeader_.ModificationTime := 0;
  SearchHeader_.HeaderPOS := 0;
  SearchHeader_.CompleteCount := 0;
  Init_TFieldSearch(SearchHeader_.FieldSearch);
end;

procedure Init_TTMDBSearchItem(var SearchItem_: TSearchItem_);
begin
  SearchItem_.Name := '';
  SearchItem_.Description := '';
  SearchItem_.ExtID := 0;
  SearchItem_.Size := 0;
  SearchItem_.HeaderPOS := 0;
  SearchItem_.CompleteCount := 0;
  Init_TFieldSearch(SearchItem_.FieldSearch);
end;

procedure Init_TTMDBSearchField(var SearchField_: TSearchField_);
begin
  SearchField_.Name := '';
  SearchField_.Description := '';
  SearchField_.HeaderCount := 0;
  SearchField_.HeaderPOS := 0;
  SearchField_.CompleteCount := 0;
  Init_TFieldSearch(SearchField_.FieldSearch);
end;

procedure Init_TTMDBRecursionSearch(var RecursionSearch_: TRecursionSearch_);
var
  i: Integer;
begin
  Init_THeader(RecursionSearch_.ReturnHeader);
  Init_TField(RecursionSearch_.CurrentField);
  RecursionSearch_.InitPath := '';
  RecursionSearch_.FilterName := '';
  RecursionSearch_.SearchBuffGo := 0;
  for i := 0 to DB_Max_Secursion_Level do
      Init_TFieldSearch(RecursionSearch_.SearchBuff[i]);
end;

function dbHeader_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
begin
  Result := False;
  Header_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Header_.State := DB_CheckIOError;
        Result := False;
        exit;
      end;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteHeader) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteHeader(fPos, Header_, Result);
          if Result then
            begin
              Header_.State := DB_Header_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteHeader) then
                  PObjectDataHandle(IOHnd.Data)^.OnWriteHeader(fPos, Header_);
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Header_.State := DB_Header_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Header_.NextHeader) = False then
      begin
        Header_.State := DB_Header_WriteNextPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Header_.PrevHeader) = False then
      begin
        Header_.State := DB_Header_WritePrevPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Header_.DataPosition) = False then
      begin
        Header_.State := DB_Header_WritePubMainPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Time_Size, Header_.CreateTime) = False then
      begin
        Header_.State := DB_Header_WriteCreateTimeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Time_Size, Header_.ModificationTime) = False then
      begin
        Header_.State := DB_Header_WriteLastEditTimeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ID_Size, Header_.ID) = False then
      begin
        Header_.State := DB_Header_WriteIDError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ID_Size, Header_.PositionID) = False then
      begin
        Header_.State := DB_Header_WritePositionIDError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Property_Size, Header_.UserProperty) = False then
      begin
        Header_.State := DB_Header_WriteUserPropertyIDError;
        Result := False;
        exit;
      end;
    if umlFileWriteFixedString(IOHnd, Header_.Name) = False then
      begin
        Header_.State := DB_Header_WriteNameError;
        Result := False;
        exit;
      end;

    Header_.State := DB_Header_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteHeader) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteHeader(fPos, Header_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Header_.State), Header_.State);
  end;
end;

function dbHeader_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
begin
  Result := False;
  Header_.State := DB_ExceptionError;
  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnReadHeader) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnReadHeader(fPos, Header_, Result);
          if Result then
              exit;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Header_.State := DB_Header_SetPosError;
        Result := False;
        exit;
      end;

    Header_.CurrentHeader := fPos;

    if umlFileRead(IOHnd, DB_Position_Size, Header_.NextHeader) = False then
      begin
        Header_.State := DB_Header_ReadNextPosError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Header_.NextHeader) then
      begin
        Header_.State := DB_Header_ReadNextPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Header_.PrevHeader) = False then
      begin
        Header_.State := DB_Header_ReadPrevPosError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Header_.PrevHeader) then
      begin
        Header_.State := DB_Header_ReadPrevPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Header_.DataPosition) = False then
      begin
        Header_.State := DB_Header_ReadPubMainPosError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Header_.DataPosition) then
      begin
        Header_.State := DB_Header_ReadPubMainPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Time_Size, Header_.CreateTime) = False then
      begin
        Header_.State := DB_Header_ReadCreateTimeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Time_Size, Header_.ModificationTime) = False then
      begin
        Header_.State := DB_Header_ReadLastEditTimeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ID_Size, Header_.ID) = False then
      begin
        Header_.State := DB_Header_ReadIDError;
        Result := False;
        exit;
      end;
    if not(Header_.ID in [DB_Header_Field_ID, DB_Header_Item_ID]) then
      begin
        Header_.State := DB_Header_ReadIDError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ID_Size, Header_.PositionID) = False then
      begin
        Header_.State := DB_Header_ReadPositionIDError;
        Result := False;
        exit;
      end;
    if not(Header_.PositionID in [DB_Header_First, DB_Header_Medium, DB_Header_Last, DB_Header_1]) then
      begin
        Header_.State := DB_Header_ReadPositionIDError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Property_Size, Header_.UserProperty) = False then
      begin
        Header_.State := DB_Header_ReadUserPropertyIDError;
        Result := False;
        exit;
      end;
    if umlFileReadFixedString(IOHnd, Header_.Name) = False then
      begin
        Header_.State := DB_Header_ReadNameError;
        Result := False;
        exit;
      end;

    Header_.State := DB_Header_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteHeader) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteHeader(fPos, Header_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Header_.State), Header_.State);
  end;
end;

function dbHeader_ReadReservedRec(const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
var
  h: THeader;
begin
  Result := dbHeader_ReadRec(fPos, IOHnd, h);
  Header_.CurrentHeader := h.CurrentHeader;
  Header_.NextHeader := h.NextHeader;
  Header_.PrevHeader := h.PrevHeader;
  Header_.DataPosition := h.DataPosition;
  Header_.ID := h.ID;
  Header_.PositionID := h.PositionID;
end;

function dbItem_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  Result := False;
  Item_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Item_.State := DB_CheckIOError;
        Item_.RHeader.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteItem) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteItem(fPos, Item_, Result);
          if Result then
            begin
              Item_.State := DB_Item_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItem) then
                  PObjectDataHandle(IOHnd.Data)^.OnWriteItem(fPos, Item_);
              exit;
            end;
        end;

    if dbHeader_WriteRec(fPos, IOHnd, Item_.RHeader) = False then
      begin
        Item_.State := Item_.RHeader.State;
        Result := False;
        exit;
      end;
    if umlFileSeek(IOHnd, Item_.RHeader.DataPosition) = False then
      begin
        Item_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWriteFixedString(IOHnd, Item_.Description) = False then
      begin
        Item_.State := DB_Item_WriteRecDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ID_Size, Item_.ExtID) = False then
      begin
        Item_.State := DB_Item_WriteRecExterIDError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Item_.FirstBlockPOS) = False then
      begin
        Item_.State := DB_Item_WriteFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Item_.LastBlockPOS) = False then
      begin
        Item_.State := DB_Item_WriteLastBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_DataSize_Size, Item_.Size) = False then
      begin
        Item_.State := DB_Item_WriteRecBuffSizeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Counter_Size, Item_.BlockCount) = False then
      begin
        Item_.State := DB_Item_WriteBlockCountError;
        Result := False;
        exit;
      end;
    Item_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItem) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteItem(fPos, Item_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Item_.State), Item_.State);
  end;
end;

function dbItem_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  Result := False;
  Item_.State := DB_ExceptionError;
  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnReadItem) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnReadItem(fPos, Item_, Result);
          if Result then
              exit;
        end;

    if dbHeader_ReadRec(fPos, IOHnd, Item_.RHeader) = False then
      begin
        Item_.State := Item_.RHeader.State;
        Result := False;
        exit;
      end;
    if umlFileSeek(IOHnd, Item_.RHeader.DataPosition) = False then
      begin
        Item_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileReadFixedString(IOHnd, Item_.Description) = False then
      begin
        Item_.State := DB_Item_ReadRecDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ID_Size, Item_.ExtID) = False then
      begin
        Item_.State := DB_Item_ReadRecExterIDError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Item_.FirstBlockPOS) = False then
      begin
        Item_.State := DB_Item_ReadFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Item_.FirstBlockPOS) then
      begin
        Item_.State := DB_Item_ReadFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Item_.LastBlockPOS) = False then
      begin
        Item_.State := DB_Item_ReadLastBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Item_.LastBlockPOS) then
      begin
        Item_.State := DB_Item_ReadLastBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_DataSize_Size, Item_.Size) = False then
      begin
        Item_.State := DB_Item_ReadRecBuffSizeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Counter_Size, Item_.BlockCount) = False then
      begin
        Item_.State := DB_Item_ReadBlockCountError;
        Result := False;
        exit;
      end;
    Item_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItem) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteItem(fPos, Item_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Item_.State), Item_.State);
  end;
end;

function dbField_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  Result := False;
  Field_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Field_.State := DB_CheckIOError;
        Field_.RHeader.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteField) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteField(fPos, Field_, Result);
          if Result then
            begin
              Field_.State := DB_Field_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteField) then
                  PObjectDataHandle(IOHnd.Data)^.OnWriteField(fPos, Field_);
              exit;
            end;
        end;

    if dbHeader_WriteRec(fPos, IOHnd, Field_.RHeader) = False then
      begin
        Field_.State := Field_.RHeader.State;
        Result := False;
        exit;
      end;
    if umlFileSeek(IOHnd, Field_.RHeader.DataPosition) = False then
      begin
        Field_.State := DB_Field_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.UpFieldPOS) = False then
      begin
        Field_.State := DB_Field_WriteHeaderFieldPosError;
        Result := False;
        exit;
      end;
    if umlFileWriteFixedString(IOHnd, Field_.Description) = False then
      begin
        Field_.State := DB_Field_WriteDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Counter_Size, Field_.HeaderCount) = False then
      begin
        Field_.State := DB_Field_WriteCountError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.FirstHeaderPOS) = False then
      begin
        Field_.State := DB_Field_WriteFirstPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.LastHeaderPOS) = False then
      begin
        Field_.State := DB_Field_WriteLastPosError;
        Result := False;
        exit;
      end;
    Field_.State := DB_Field_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteField) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteField(fPos, Field_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Field_.State), Field_.State);
  end;
end;

function dbField_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  Result := False;
  Field_.State := DB_ExceptionError;

  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnReadField) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnReadField(fPos, Field_, Result);
          if Result then
              exit;
        end;

    if dbHeader_ReadRec(fPos, IOHnd, Field_.RHeader) = False then
      begin
        Field_.State := Field_.RHeader.State;
        Result := False;
        exit;
      end;
    if umlFileSeek(IOHnd, Field_.RHeader.DataPosition) = False then
      begin
        Field_.State := DB_Field_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.UpFieldPOS) = False then
      begin
        Field_.State := DB_Field_ReadHeaderFieldPosError;
        Result := False;
        exit;
      end;
    if umlFileReadFixedString(IOHnd, Field_.Description) = False then
      begin
        Field_.State := DB_Field_ReadDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Counter_Size, Field_.HeaderCount) = False then
      begin
        Field_.State := DB_Field_ReadCountError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.FirstHeaderPOS) = False then
      begin
        Field_.State := DB_Field_ReadFirstPosError;
        Result := False;
        exit;
      end;
    if (Field_.HeaderCount > 0) and (not umlCheckSeedPos(IOHnd, Field_.FirstHeaderPOS)) then
      begin
        Field_.State := DB_Field_ReadFirstPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.LastHeaderPOS) = False then
      begin
        Field_.State := DB_Field_ReadLastPosError;
        Result := False;
        exit;
      end;
    if (Field_.HeaderCount > 0) and (not umlCheckSeedPos(IOHnd, Field_.LastHeaderPOS)) then
      begin
        Field_.State := DB_Field_ReadLastPosError;
        Result := False;
        exit;
      end;
    Field_.State := DB_Field_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteField) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteField(fPos, Field_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Field_.State), Field_.State);
  end;
end;

function dbItem_OnlyWriteItemBlockRec(const fPos: Int64; var IOHnd: TIOHnd; var Block_: TItemBlock): Boolean;
begin
  Result := False;
  Block_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Block_.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteItemBlock) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteItemBlock(fPos, Block_, Result);
          if Result then
            begin
              Block_.State := DB_Item_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock) then
                  PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock(fPos, Block_);
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Block_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ID_Size, Block_.ID) = False then
      begin
        Block_.State := DB_Item_WriteItemBlockIDFlagsError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Block_.CurrentBlockPOS) = False then
      begin
        Block_.State := DB_Item_WriteCurrentBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Block_.NextBlockPOS) = False then
      begin
        Block_.State := DB_Item_WriteNextBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Block_.PrevBlockPOS) = False then
      begin
        Block_.State := DB_Item_WritePrevBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Block_.DataPosition) = False then
      begin
        Block_.State := DB_Item_WriteDataBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_DataSize_Size, Block_.Size) = False then
      begin
        Block_.State := DB_Item_WriteDataBuffSizeError;
        Result := False;
        exit;
      end;
    Block_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock(fPos, Block_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Block_.State), Block_.State);
  end;
end;

function dbItem_OnlyReadItemBlockRec(const fPos: Int64; var IOHnd: TIOHnd; var Block_: TItemBlock): Boolean;
begin
  Result := False;
  Block_.State := DB_ExceptionError;
  try
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnReadItemBlock) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnReadItemBlock(fPos, Block_, Result);
          if Result then
              exit;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Block_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ID_Size, Block_.ID) = False then
      begin
        Block_.State := DB_Item_ReadItemBlockIDFlagsError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Block_.CurrentBlockPOS) = False then
      begin
        Block_.State := DB_Item_ReadCurrentBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Block_.CurrentBlockPOS) then
      begin
        Block_.State := DB_Item_ReadCurrentBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Block_.NextBlockPOS) = False then
      begin
        Block_.State := DB_Item_ReadNextBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Block_.NextBlockPOS) then
      begin
        Block_.State := DB_Item_ReadNextBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Block_.PrevBlockPOS) = False then
      begin
        Block_.State := DB_Item_ReadPrevBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Block_.PrevBlockPOS) then
      begin
        Block_.State := DB_Item_ReadPrevBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Block_.DataPosition) = False then
      begin
        Block_.State := DB_Item_ReadDataBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Block_.DataPosition) then
      begin
        Block_.State := DB_Item_ReadDataBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_DataSize_Size, Block_.Size) = False then
      begin
        Block_.State := DB_Item_ReadDataBuffSizeError;
        Result := False;
        exit;
      end;
    Block_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteItemBlock(fPos, Block_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Block_.State), Block_.State);
  end;
end;

function db_WriteRec(const fPos: Int64; var IOHnd: TIOHnd; var DB_: TObjectDataHandle): Boolean;
begin
  Result := False;
  DB_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        DB_.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteTMDB) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareWriteTMDB(fPos, @DB_, Result);
          if Result then
            begin
              DB_.State := DB_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteTMDB) then
                  PObjectDataHandle(IOHnd.Data)^.OnWriteTMDB(fPos, @DB_);
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        DB_.State := DB_PositionSeekError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ReservedData_Size, DB_.ReservedData[0]) = False then
      begin
        DB_.State := DB_WriteReservedDataError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_FixedStringL_Size, DB_.FixedStringL) = False then
      begin
        DB_.State := DB_WriteFixedStringLError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Version_Size, DB_.MajorVer) = False then
      begin
        DB_.State := DB_WriteMajorVersionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Version_Size, DB_.MinorVer) = False then
      begin
        DB_.State := DB_WriteMinorVersionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Time_Size, DB_.CreateTime) = False then
      begin
        DB_.State := DB_WriteCreateTimeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Time_Size, DB_.ModificationTime) = False then
      begin
        DB_.State := DB_WriteLastEditTimeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Counter_Size, DB_.RootHeaderCount) = False then
      begin
        DB_.State := DB_WriteHeaderCountError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, DB_.DefaultFieldPOS) = False then
      begin
        DB_.State := DB_WriteDefaultPositionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, DB_.FirstHeaderPOS) = False then
      begin
        DB_.State := DB_WriteFirstPositionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, DB_.LastHeaderPOS) = False then
      begin
        DB_.State := DB_WriteLastPositionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, DB_.CurrentFieldPOS) = False then
      begin
        DB_.State := DB_WriteCurrentPositionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Level_Size, DB_.CurrentFieldLevel) = False then
      begin
        DB_.State := DB_WriteCurrentLevelError;
        Result := False;
        exit;
      end;
    DB_.State := DB_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnWriteTMDB) then
          PObjectDataHandle(IOHnd.Data)^.OnWriteTMDB(fPos, @DB_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(DB_.State), DB_.State);
  end;
end;

function db_ReadRec(const fPos: Int64; var IOHnd: TIOHnd; var DB_: TObjectDataHandle): Boolean;
begin
  Result := False;
  DB_.State := DB_ExceptionError;
  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnReadTMDB) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnReadTMDB(fPos, @DB_, Result);
          if Result then
            begin
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        DB_.State := DB_PositionSeekError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ReservedData_Size, DB_.ReservedData[0]) = False then
      begin
        DB_.State := DB_ReadReservedDataError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_FixedStringL_Size, DB_.FixedStringL) = False then
      begin
        DB_.State := DB_ReadFixedStringLError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Version_Size, DB_.MajorVer) = False then
      begin
        DB_.State := DB_ReadMajorVersionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Version_Size, DB_.MinorVer) = False then
      begin
        DB_.State := DB_ReadMinorVersionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Time_Size, DB_.CreateTime) = False then
      begin
        DB_.State := DB_ReadCreateTimeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Time_Size, DB_.ModificationTime) = False then
      begin
        DB_.State := DB_ReadLastEditTimeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Counter_Size, DB_.RootHeaderCount) = False then
      begin
        DB_.State := DB_ReadHeaderCountError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, DB_.DefaultFieldPOS) = False then
      begin
        DB_.State := DB_ReadDefaultPositionError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, DB_.DefaultFieldPOS) then
      begin
        DB_.State := DB_ReadDefaultPositionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, DB_.FirstHeaderPOS) = False then
      begin
        DB_.State := DB_ReadFirstPositionError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, DB_.FirstHeaderPOS) then
      begin
        DB_.State := DB_ReadFirstPositionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, DB_.LastHeaderPOS) = False then
      begin
        DB_.State := DB_ReadLastPositionError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, DB_.LastHeaderPOS) then
      begin
        DB_.State := DB_ReadLastPositionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, DB_.CurrentFieldPOS) = False then
      begin
        DB_.State := DB_ReadCurrentPositionError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, DB_.CurrentFieldPOS) then
      begin
        DB_.State := DB_ReadCurrentPositionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Level_Size, DB_.CurrentFieldLevel) = False then
      begin
        DB_.State := DB_ReadCurrentLevelError;
        Result := False;
        exit;
      end;
    DB_.State := DB_ok;
    Result := True;
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(DB_.State), DB_.State);
  end;
end;

function dbItem_OnlyWriteItemRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  Result := False;
  Item_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Item_.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareOnlyWriteItemRec) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareOnlyWriteItemRec(fPos, Item_, Result);
          if Result then
            begin
              Item_.State := DB_Item_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec) then
                  PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec(fPos, Item_);
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Item_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWriteFixedString(IOHnd, Item_.Description) = False then
      begin
        Item_.State := DB_Item_WriteRecDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_ID_Size, Item_.ExtID) = False then
      begin
        Item_.State := DB_Item_WriteRecExterIDError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Item_.FirstBlockPOS) = False then
      begin
        Item_.State := DB_Item_WriteFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Item_.LastBlockPOS) = False then
      begin
        Item_.State := DB_Item_WriteLastBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_DataSize_Size, Item_.Size) = False then
      begin
        Item_.State := DB_Item_WriteRecBuffSizeError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Counter_Size, Item_.BlockCount) = False then
      begin
        Item_.State := DB_Item_WriteBlockCountError;
        Result := False;
        exit;
      end;
    Item_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec) then
          PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec(fPos, Item_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Item_.State), Item_.State);
  end;
end;

function dbItem_OnlyReadItemRec(const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  Result := False;
  Item_.State := DB_ExceptionError;
  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyReadItemRec) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnOnlyReadItemRec(fPos, Item_, Result);
          if Result then
              exit;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Item_.State := DB_Item_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileReadFixedString(IOHnd, Item_.Description) = False then
      begin
        Item_.State := DB_Item_ReadRecDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_ID_Size, Item_.ExtID) = False then
      begin
        Item_.State := DB_Item_ReadRecExterIDError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Item_.FirstBlockPOS) = False then
      begin
        Item_.State := DB_Item_ReadFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Item_.FirstBlockPOS) then
      begin
        Item_.State := DB_Item_ReadFirstBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Item_.LastBlockPOS) = False then
      begin
        Item_.State := DB_Item_ReadLastBlockPOSError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Item_.LastBlockPOS) then
      begin
        Item_.State := DB_Item_ReadLastBlockPOSError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_DataSize_Size, Item_.Size) = False then
      begin
        Item_.State := DB_Item_ReadRecBuffSizeError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Counter_Size, Item_.BlockCount) = False then
      begin
        Item_.State := DB_Item_ReadBlockCountError;
        Result := False;
        exit;
      end;
    Item_.State := DB_Item_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec) then
          PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteItemRec(fPos, Item_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Item_.State), Item_.State);
  end;
end;

function dbField_OnlyWriteFieldRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  Result := False;
  Field_.State := DB_ExceptionError;
  try
    if (IOHnd.IsOnlyRead) or (not IOHnd.IsOpen) then
      begin
        Field_.State := DB_CheckIOError;
        Result := False;
        exit;
      end;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnPrepareOnlyWriteFieldRec) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnPrepareOnlyWriteFieldRec(fPos, Field_, Result);
          if Result then
            begin
              Field_.State := DB_Field_ok;
              if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec) then
                  PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec(fPos, Field_);
              exit;
            end;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Field_.State := DB_Field_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.UpFieldPOS) = False then
      begin
        Field_.State := DB_Field_WriteHeaderFieldPosError;
        Result := False;
        exit;
      end;
    if umlFileWriteFixedString(IOHnd, Field_.Description) = False then
      begin
        Field_.State := DB_Field_WriteDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Counter_Size, Field_.HeaderCount) = False then
      begin
        Field_.State := DB_Field_WriteCountError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.FirstHeaderPOS) = False then
      begin
        Field_.State := DB_Field_WriteFirstPosError;
        Result := False;
        exit;
      end;
    if umlFileWrite(IOHnd, DB_Position_Size, Field_.LastHeaderPOS) = False then
      begin
        Field_.State := DB_Field_WriteLastPosError;
        Result := False;
        exit;
      end;
    Field_.State := DB_Field_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec) then
          PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec(fPos, Field_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Field_.State), Field_.State);
  end;
end;

function dbField_OnlyReadFieldRec(const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  Result := False;
  Field_.State := DB_ExceptionError;
  try
    if not umlCheckSeedPos(IOHnd, fPos) then
        exit;
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyReadFieldRec) then
        begin
          Result := False;
          PObjectDataHandle(IOHnd.Data)^.OnOnlyReadFieldRec(fPos, Field_, Result);
          if Result then
              exit;
        end;

    if umlFileSeek(IOHnd, fPos) = False then
      begin
        Field_.State := DB_Field_SetPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.UpFieldPOS) = False then
      begin
        Field_.State := DB_Field_ReadHeaderFieldPosError;
        Result := False;
        exit;
      end;
    if umlFileReadFixedString(IOHnd, Field_.Description) = False then
      begin
        Field_.State := DB_Field_ReadDescriptionError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Counter_Size, Field_.HeaderCount) = False then
      begin
        Field_.State := DB_Field_ReadCountError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.FirstHeaderPOS) = False then
      begin
        Field_.State := DB_Field_ReadFirstPosError;
        Result := False;
        exit;
      end;
    if not umlCheckSeedPos(IOHnd, Field_.FirstHeaderPOS) then
      begin
        Field_.State := DB_Field_ReadFirstPosError;
        Result := False;
        exit;
      end;
    if umlFileRead(IOHnd, DB_Position_Size, Field_.LastHeaderPOS) = False then
      begin
        Field_.State := DB_Field_ReadLastPosError;
        Result := False;
        exit;
      end;
    Field_.State := DB_Field_ok;
    Result := True;

    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec) then
          PObjectDataHandle(IOHnd.Data)^.OnOnlyWriteFieldRec(fPos, Field_);
  finally
    if not Result then
      if IOHnd.Data <> nil then
        if Assigned(PObjectDataHandle(IOHnd.Data)^.OnError) then
            PObjectDataHandle(IOHnd.Data)^.OnError(TranslateReturnCode(Field_.State), Field_.State);
  end;
end;

function dbMultipleMatch(const SourStr, DestStr: U_String): Boolean;
begin
  if SourStr.Len = 0 then
      Result := True
  else if DestStr.Len = 0 then
      Result := False
  else
      Result := umlMultipleMatch(True, SourStr, DestStr, ZDB_Header_Multiple_String__, ZDB_Header_Multiple_Char__);
end;

function dbHeader_FindNext(const Name: U_String; const FirstHeaderPOS, LastHeaderPOS: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
begin
  if dbHeader_ReadRec(FirstHeaderPOS, IOHnd, Header_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbMultipleMatch(Name, Header_.Name) then
    begin
      Result := True;
      exit;
    end;
  if (Header_.PositionID = DB_Header_Last) or (Header_.PositionID = DB_Header_1) then
    begin
      Header_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  while dbHeader_ReadRec(Header_.NextHeader, IOHnd, Header_) do
    begin
      if dbMultipleMatch(Name, Header_.Name) then
        begin
          Result := True;
          exit;
        end;
      if Header_.PositionID = DB_Header_Last then
        begin
          Header_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  Header_.State := DB_Header_ok;
  Result := False;
end;

function dbHeader_FindPrev(const Name: U_String; const LastHeaderPOS, FirstHeaderPOS: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
begin
  if dbHeader_ReadRec(LastHeaderPOS, IOHnd, Header_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbMultipleMatch(Name, Header_.Name) then
    begin
      Result := True;
      exit;
    end;
  if (Header_.PositionID = DB_Header_First) or (Header_.PositionID = DB_Header_1) then
    begin
      Header_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  while dbHeader_ReadRec(Header_.PrevHeader, IOHnd, Header_) do
    begin
      if dbMultipleMatch(Name, Header_.Name) then
        begin
          Result := True;
          exit;
        end;
      if Header_.PositionID = DB_Header_First then
        begin
          Header_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  Header_.State := DB_Header_ok;
  Result := False;
end;

function dbItem_BlockCreate(var IOHnd: TIOHnd; var Item_: TItem): Boolean;
var
  FirstItemBlock, LastItemBlock: TItemBlock;
begin
  case Item_.BlockCount of
    0:
      begin
        LastItemBlock.ID := DB_Item_1;
        LastItemBlock.CurrentBlockPOS := umlFileGetSize(IOHnd);
        LastItemBlock.NextBlockPOS := LastItemBlock.CurrentBlockPOS;
        LastItemBlock.PrevBlockPOS := LastItemBlock.CurrentBlockPOS;
        LastItemBlock.DataPosition := LastItemBlock.CurrentBlockPOS + Get_DB_BlockL(IOHnd);
        LastItemBlock.Size := 0;
        if dbItem_OnlyWriteItemBlockRec(LastItemBlock.CurrentBlockPOS, IOHnd, LastItemBlock) = False then
          begin
            Item_.State := LastItemBlock.State;
            Result := False;
            exit;
          end;
        Item_.BlockCount := 1;
        Item_.FirstBlockPOS := LastItemBlock.CurrentBlockPOS;
        Item_.LastBlockPOS := LastItemBlock.CurrentBlockPOS;
        if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    1:
      begin
        if dbItem_OnlyReadItemBlockRec(Item_.FirstBlockPOS, IOHnd, FirstItemBlock) = False then
          begin
            Item_.State := FirstItemBlock.State;
            Result := False;
            exit;
          end;
        LastItemBlock.ID := DB_Item_Last;
        LastItemBlock.CurrentBlockPOS := umlFileGetSize(IOHnd);
        LastItemBlock.NextBlockPOS := FirstItemBlock.CurrentBlockPOS;
        LastItemBlock.PrevBlockPOS := FirstItemBlock.CurrentBlockPOS;
        LastItemBlock.DataPosition := LastItemBlock.CurrentBlockPOS + Get_DB_BlockL(IOHnd);
        LastItemBlock.Size := 0;
        if dbItem_OnlyWriteItemBlockRec(LastItemBlock.CurrentBlockPOS, IOHnd, LastItemBlock) = False then
          begin
            Item_.State := LastItemBlock.State;
            Result := False;
            exit;
          end;
        FirstItemBlock.ID := DB_Item_First;
        FirstItemBlock.NextBlockPOS := LastItemBlock.CurrentBlockPOS;
        FirstItemBlock.PrevBlockPOS := LastItemBlock.CurrentBlockPOS;
        if dbItem_OnlyWriteItemBlockRec(Item_.FirstBlockPOS, IOHnd, FirstItemBlock) = False then
          begin
            Item_.State := FirstItemBlock.State;
            Result := False;
            exit;
          end;
        Item_.BlockCount := Item_.BlockCount + 1;
        Item_.LastBlockPOS := LastItemBlock.CurrentBlockPOS;
        if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    else
      begin
        if dbItem_OnlyReadItemBlockRec(Item_.FirstBlockPOS, IOHnd, FirstItemBlock) = False then
          begin
            Item_.State := FirstItemBlock.State;
            Result := False;
            exit;
          end;
        FirstItemBlock.PrevBlockPOS := umlFileGetSize(IOHnd);
        if dbItem_OnlyWriteItemBlockRec(Item_.FirstBlockPOS, IOHnd, FirstItemBlock) = False then
          begin
            Item_.State := FirstItemBlock.State;
            Result := False;
            exit;
          end;
        if dbItem_OnlyReadItemBlockRec(Item_.LastBlockPOS, IOHnd, LastItemBlock) = False then
          begin
            Item_.State := LastItemBlock.State;
            Result := False;
            exit;
          end;
        LastItemBlock.ID := DB_Item_Medium;
        LastItemBlock.NextBlockPOS := FirstItemBlock.PrevBlockPOS;
        if dbItem_OnlyWriteItemBlockRec(Item_.LastBlockPOS, IOHnd, LastItemBlock) = False then
          begin
            Item_.State := LastItemBlock.State;
            Result := False;
            exit;
          end;
        LastItemBlock.ID := DB_Item_Last;
        LastItemBlock.CurrentBlockPOS := FirstItemBlock.PrevBlockPOS;
        LastItemBlock.NextBlockPOS := Item_.FirstBlockPOS;
        LastItemBlock.PrevBlockPOS := Item_.LastBlockPOS;
        LastItemBlock.DataPosition := LastItemBlock.CurrentBlockPOS + Get_DB_BlockL(IOHnd);
        LastItemBlock.Size := 0;
        if dbItem_OnlyWriteItemBlockRec(LastItemBlock.CurrentBlockPOS, IOHnd, LastItemBlock) = False then
          begin
            Item_.State := LastItemBlock.State;
            Result := False;
            exit;
          end;
        Item_.BlockCount := Item_.BlockCount + 1;
        Item_.LastBlockPOS := LastItemBlock.CurrentBlockPOS;
        if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
  end;
  Item_.CurrentItemBlock := LastItemBlock;
  Item_.CurrentBlockSeekPOS := 0;
  Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition;
  Item_.DataModification := True;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbItem_BlockInit(var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  if Item_.BlockCount = 0 then
    begin
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;
  if dbItem_OnlyReadItemBlockRec(Item_.FirstBlockPOS, IOHnd, Item_.CurrentItemBlock) = False then
    begin
      Item_.State := Item_.CurrentItemBlock.State;
      Result := False;
      exit;
    end;
  Item_.CurrentBlockSeekPOS := 0;
  Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbItem_BlockReadData(var IOHnd: TIOHnd; var Item_: TItem; var Buff_; const _Size: Int64): Boolean;
label
  Rep_Label;
var
  BuffPointer: Pointer;
  DeformitySize, BlockPOS: Int64;
  ItemBlock: TItemBlock;
  Size: Int64;
begin
  if (_Size <= Item_.Size) then
      Size := _Size
  else
      Size := Item_.Size;

  if Size = 0 then
    begin
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;

  if (Item_.BlockCount = 0) then
    begin
      Item_.State := DB_Item_BlockOverrate;
      Result := False;
      exit;
    end;

  if Item_.CurrentBlockSeekPOS > Item_.CurrentItemBlock.Size then
    begin
      Item_.State := DB_Item_BlockPositionError;
      Result := False;
      exit;
    end;
  ItemBlock := Item_.CurrentItemBlock;
  BlockPOS := Item_.CurrentBlockSeekPOS;
  BuffPointer := @Buff_;
  DeformitySize := Size;
Rep_Label:
  if ItemBlock.Size - BlockPOS = 0 then
    begin
      case ItemBlock.ID of
        DB_Item_Last, DB_Item_1:
          begin
            Item_.State := DB_Item_BlockOverrate;
            Result := False;
            exit;
          end;
      end;
      if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
        begin
          Item_.State := ItemBlock.State;
          Result := False;
          exit;
        end;
      if BlockPOS > 0 then
          BlockPOS := 0;
      while (ItemBlock.Size - BlockPOS) = 0 do
        begin
          case ItemBlock.ID of
            DB_Item_Last:
              begin
                Item_.State := DB_Item_BlockOverrate;
                Result := False;
                exit;
              end;
          end;
          if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
            begin
              Item_.State := ItemBlock.State;
              Result := False;
              exit;
            end;
        end;
    end;

  if umlFileSeek(IOHnd, ItemBlock.DataPosition + BlockPOS) = False then
    begin
      Item_.State := DB_Item_SetPosError;
      Result := False;
      exit;
    end;

  if DeformitySize <= ItemBlock.Size - BlockPOS then
    begin
      if umlFileRead(IOHnd, DeformitySize, BuffPointer^) = False then
        begin
          Item_.State := DB_Item_BlockReadError;
          Result := False;
          exit;
        end;
      Item_.CurrentBlockSeekPOS := BlockPOS + DeformitySize;
      Item_.CurrentFileSeekPOS := ItemBlock.DataPosition + (BlockPOS + DeformitySize);
      Item_.CurrentItemBlock := ItemBlock;
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;

  if umlFileRead(IOHnd, ItemBlock.Size - BlockPOS, BuffPointer^) = False then
    begin
      Item_.State := DB_Item_BlockReadError;
      Result := False;
      exit;
    end;
  case ItemBlock.ID of
    DB_Item_Last, DB_Item_1:
      begin
        Item_.State := DB_Item_BlockOverrate;
        Result := False;
        exit;
      end;
  end;
  BuffPointer := GetOffset(BuffPointer, ItemBlock.Size - BlockPOS);
  DeformitySize := DeformitySize - (ItemBlock.Size - BlockPOS);
  if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
    begin
      Item_.State := ItemBlock.State;
      Result := False;
      exit;
    end;

  if BlockPOS = 0 then
      goto Rep_Label;
  BlockPOS := 0;
  goto Rep_Label;
end;

function dbItem_BlockAppendWriteData(var IOHnd: TIOHnd; var Item_: TItem; const Buff_; const Size: Int64): Boolean;
begin
  if (Item_.BlockCount > 0) and ((Item_.CurrentItemBlock.DataPosition + Item_.CurrentItemBlock.Size) = umlFileGetSize(IOHnd)) then
    begin
      if umlFileSeek(IOHnd, umlFileGetSize(IOHnd)) = False then
        begin
          Item_.State := DB_Item_SetPosError;
          Result := False;
          exit;
        end;
      if umlFileWrite(IOHnd, Size, Buff_) = False then
        begin
          Item_.State := DB_Item_BlockWriteError;
          Result := False;
          exit;
        end;
      Item_.CurrentItemBlock.Size := Item_.CurrentItemBlock.Size + Size;
      if dbItem_OnlyWriteItemBlockRec(Item_.CurrentItemBlock.CurrentBlockPOS, IOHnd, Item_.CurrentItemBlock) = False then
        begin
          Item_.State := Item_.CurrentItemBlock.State;
          Result := False;
          exit;
        end;
      Item_.Size := Item_.Size + Size;
      if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
        begin
          Result := False;
          exit;
        end;
      Item_.CurrentBlockSeekPOS := Item_.CurrentItemBlock.Size;
      Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition + Item_.CurrentItemBlock.Size;
      Item_.DataModification := True;
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;

  if dbItem_BlockCreate(IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;

  if umlFileSeek(IOHnd, Item_.CurrentItemBlock.DataPosition) = False then
    begin
      Item_.State := DB_Item_SetPosError;
      Result := False;
      exit;
    end;

  if umlFileWrite(IOHnd, Size, Buff_) = False then
    begin
      Item_.State := DB_Item_BlockWriteError;
      Result := False;
      exit;
    end;
  Item_.CurrentItemBlock.Size := Size;
  if dbItem_OnlyWriteItemBlockRec(Item_.CurrentItemBlock.CurrentBlockPOS, IOHnd, Item_.CurrentItemBlock) = False then
    begin
      Item_.State := Item_.CurrentItemBlock.State;
      Result := False;
      exit;
    end;
  Item_.Size := Item_.Size + Size;
  if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;
  Item_.CurrentBlockSeekPOS := Item_.CurrentItemBlock.Size;
  Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition + Item_.CurrentItemBlock.Size;
  Item_.DataModification := True;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbItem_BlockWriteData(var IOHnd: TIOHnd; var Item_: TItem; const Buff_; const Size: Int64): Boolean;
label
  Rep_Label;
var
  BuffPointer: Pointer;
  DeformitySize, BlockPOS: Int64;
  ItemBlock: TItemBlock;
begin
  if (Item_.Size = 0) or (Item_.BlockCount = 0) then
    begin
      Result := dbItem_BlockAppendWriteData(IOHnd, Item_, Buff_, Size);
      exit;
    end;
  case Item_.CurrentItemBlock.ID of
    DB_Item_Last, DB_Item_1:
      begin
        if Item_.CurrentBlockSeekPOS = Item_.CurrentItemBlock.Size then
          begin
            Result := dbItem_BlockAppendWriteData(IOHnd, Item_, Buff_, Size);
            exit;
          end;
      end;
  end;

  if Item_.CurrentBlockSeekPOS > Item_.CurrentItemBlock.Size then
    begin
      Item_.State := DB_Item_BlockPositionError;
      Result := False;
      exit;
    end;
  ItemBlock := Item_.CurrentItemBlock;
  BlockPOS := Item_.CurrentBlockSeekPOS;
  BuffPointer := @Buff_;
  DeformitySize := Size;
Rep_Label:
  if ItemBlock.Size - BlockPOS = 0 then
    begin
      case ItemBlock.ID of
        DB_Item_Last, DB_Item_1:
          begin
            Result := dbItem_BlockAppendWriteData(IOHnd, Item_, BuffPointer^, DeformitySize);
            exit;
          end;
      end;
      if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
        begin
          Item_.State := ItemBlock.State;
          Result := False;
          exit;
        end;
      if BlockPOS > 0 then
          BlockPOS := 0;
      while (ItemBlock.Size - BlockPOS) = 0 do
        begin
          case ItemBlock.ID of
            DB_Item_Last:
              begin
                Result := dbItem_BlockAppendWriteData(IOHnd, Item_, BuffPointer^, DeformitySize);
                exit;
              end;
          end;
          if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
            begin
              Item_.State := ItemBlock.State;
              Result := False;
              exit;
            end;
        end;
    end;

  if umlFileSeek(IOHnd, ItemBlock.DataPosition + BlockPOS) = False then
    begin
      Item_.State := DB_Item_SetPosError;
      Result := False;
      exit;
    end;

  if DeformitySize <= ItemBlock.Size - BlockPOS then
    begin
      if umlFileWrite(IOHnd, DeformitySize, BuffPointer^) = False then
        begin
          Item_.State := DB_Item_BlockWriteError;
          Result := False;
          exit;
        end;
      Item_.CurrentBlockSeekPOS := BlockPOS + DeformitySize;
      Item_.CurrentFileSeekPOS := ItemBlock.DataPosition + (BlockPOS + DeformitySize);
      Item_.CurrentItemBlock := ItemBlock;
      Item_.DataModification := True;
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;

  if umlFileWrite(IOHnd, ItemBlock.Size - BlockPOS, BuffPointer^) = False then
    begin
      Item_.State := DB_Item_BlockWriteError;
      Result := False;
      exit;
    end;
  BuffPointer := GetOffset(BuffPointer, ItemBlock.Size - BlockPOS);
  DeformitySize := DeformitySize - (ItemBlock.Size - BlockPOS);
  case ItemBlock.ID of
    DB_Item_Last, DB_Item_1:
      begin
        Result := dbItem_BlockAppendWriteData(IOHnd, Item_, BuffPointer^, DeformitySize);
        exit;
      end;
  end;
  if dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) = False then
    begin
      Item_.State := ItemBlock.State;
      Result := False;
      exit;
    end;

  if BlockPOS = 0 then
      goto Rep_Label;
  BlockPOS := 0;
  goto Rep_Label;
end;

function dbItem_BlockSeekPOS(var IOHnd: TIOHnd; var Item_: TItem; const Position: Int64): Boolean;
var
  ItemBlock: TItemBlock;
  DeformityInt: Int64;
begin
  if (Position = 0) and (Item_.Size = 0) then
    begin
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;

  if (Position > Item_.Size) or (Item_.BlockCount = 0) then
    begin
      Item_.State := DB_Item_BlockOverrate;
      Result := False;
      exit;
    end;
  DeformityInt := Position;
  if dbItem_OnlyReadItemBlockRec(Item_.FirstBlockPOS, IOHnd, ItemBlock) = False then
    begin
      Item_.State := ItemBlock.State;
      Result := False;
      exit;
    end;

  if DeformityInt <= ItemBlock.Size then
    begin
      Item_.CurrentBlockSeekPOS := ItemBlock.Size - (ItemBlock.Size - DeformityInt);
      Item_.CurrentFileSeekPOS := ItemBlock.DataPosition + Item_.CurrentBlockSeekPOS;
      Item_.CurrentItemBlock := ItemBlock;
      Item_.State := DB_Item_ok;
      Result := True;
      exit;
    end;
  case ItemBlock.ID of
    DB_Item_Last, DB_Item_1:
      begin
        Item_.State := DB_Item_BlockOverrate;
        Result := False;
        exit;
      end;
  end;
  DeformityInt := DeformityInt - ItemBlock.Size;
  while dbItem_OnlyReadItemBlockRec(ItemBlock.NextBlockPOS, IOHnd, ItemBlock) do
    begin
      if DeformityInt <= ItemBlock.Size then
        begin
          Item_.CurrentBlockSeekPOS := ItemBlock.Size - (ItemBlock.Size - DeformityInt);
          Item_.CurrentFileSeekPOS := ItemBlock.DataPosition + Item_.CurrentBlockSeekPOS;
          Item_.CurrentItemBlock := ItemBlock;
          Item_.State := DB_Item_ok;
          Result := True;
          exit;
        end;
      case ItemBlock.ID of
        DB_Item_Last:
          begin
            Item_.State := DB_Item_BlockOverrate;
            Result := False;
            exit;
          end;
      end;
      DeformityInt := DeformityInt - ItemBlock.Size;
    end;
  Item_.State := ItemBlock.State;
  Result := False;
end;

function dbItem_BlockGetPOS(var IOHnd: TIOHnd; var Item_: TItem): Int64;
var
  ItemBlock: TItemBlock;
begin
  if (Item_.Size = 0) or (Item_.BlockCount = 0) then
    begin
      Item_.State := DB_Item_BlockOverrate;
      Result := 0;
      exit;
    end;

  if Item_.CurrentBlockSeekPOS > Item_.CurrentItemBlock.Size then
    begin
      Item_.State := DB_Item_BlockPositionError;
      Result := 0;
      exit;
    end;
  Result := Item_.CurrentBlockSeekPOS;
  case Item_.CurrentItemBlock.ID of
    DB_Item_First, DB_Item_1:
      begin
        Item_.State := DB_Item_ok;
        exit;
      end;
  end;
  if dbItem_OnlyReadItemBlockRec(Item_.CurrentItemBlock.PrevBlockPOS, IOHnd, ItemBlock) = False then
    begin
      Item_.State := ItemBlock.State;
      Result := 0;
      exit;
    end;
  Result := Result + ItemBlock.Size;
  case ItemBlock.ID of
    DB_Item_First, DB_Item_1:
      begin
        Item_.State := DB_Item_ok;
        exit;
      end;
  end;
  while dbItem_OnlyReadItemBlockRec(ItemBlock.PrevBlockPOS, IOHnd, ItemBlock) do
    begin
      Result := Result + ItemBlock.Size;
      if ItemBlock.ID = DB_Item_First then
        begin
          Item_.State := DB_Item_ok;
          exit;
        end;
    end;
  Item_.State := ItemBlock.State;
  Result := 0;
end;

function dbItem_BlockSeekStartPOS(var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  if Item_.BlockCount = 0 then
    begin
      Item_.State := DB_Item_BlockOverrate;
      Result := False;
      exit;
    end;
  if dbItem_OnlyReadItemBlockRec(Item_.FirstBlockPOS, IOHnd, Item_.CurrentItemBlock) = False then
    begin
      Item_.State := Item_.CurrentItemBlock.State;
      Result := False;
      exit;
    end;
  Item_.CurrentBlockSeekPOS := 0;
  Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbItem_BlockSeekLastPOS(var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  if Item_.BlockCount = 0 then
    begin
      Item_.State := DB_Item_BlockOverrate;
      Result := False;
      exit;
    end;
  if dbItem_OnlyReadItemBlockRec(Item_.LastBlockPOS, IOHnd, Item_.CurrentItemBlock) = False then
    begin
      Item_.State := Item_.CurrentItemBlock.State;
      Result := False;
      exit;
    end;
  Item_.CurrentBlockSeekPOS := Item_.CurrentItemBlock.Size;
  Item_.CurrentFileSeekPOS := Item_.CurrentItemBlock.DataPosition + Item_.CurrentItemBlock.Size;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbField_GetPOSField(const fPos: Int64; var IOHnd: TIOHnd): TField;
begin
  if not dbField_ReadRec(fPos, IOHnd, Result) then
      Init_TField(Result);
end;

function dbField_GetFirstHeader(const fPos: Int64; var IOHnd: TIOHnd): THeader;
var
  f: TField;
begin
  Init_THeader(Result);
  if dbField_ReadRec(fPos, IOHnd, f) then
      dbHeader_ReadRec(f.FirstHeaderPOS, IOHnd, Result);
end;

function dbField_GetLastHeader(const fPos: Int64; var IOHnd: TIOHnd): THeader;
var
  f: TField;
begin
  Init_THeader(Result);
  if dbField_ReadRec(fPos, IOHnd, f) then
      dbHeader_ReadRec(f.LastHeaderPOS, IOHnd, Result);
end;

function dbField_OnlyFindFirstName(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  f: TField;
begin
  FieldS_.InitFlags := False;
  if dbField_ReadRec(fPos, IOHnd, f) = False then
    begin
      FieldS_.State := f.State;
      Result := False;
      exit;
    end;
  if f.HeaderCount = 0 then
    begin
      FieldS_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  if dbHeader_FindNext(Name, f.FirstHeaderPOS, f.LastHeaderPOS, IOHnd, FieldS_.RHeader) = False then
    begin
      FieldS_.State := FieldS_.RHeader.State;
      Result := False;
      exit;
    end;
  FieldS_.InitFlags := True;
  FieldS_.PositionID := FieldS_.RHeader.PositionID;
  FieldS_.OverPOS := f.LastHeaderPOS;
  FieldS_.StartPos := FieldS_.RHeader.NextHeader;
  FieldS_.Name := Name;
  FieldS_.ID := FieldS_.RHeader.ID;
  FieldS_.State := FieldS_.RHeader.State;
  Result := True;
end;

function dbField_OnlyFindNextName(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
begin
  if FieldS_.InitFlags = False then
    begin
      FieldS_.State := DB_Field_NotInitSearch;
      Result := False;
      exit;
    end;
  case FieldS_.PositionID of
    DB_Header_1, DB_Header_Last:
      begin
        FieldS_.InitFlags := False;
        FieldS_.State := DB_Header_NotFindHeader;
        Result := False;
        exit;
      end;
  end;
  if dbHeader_FindNext(FieldS_.Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) = False then
    begin
      FieldS_.InitFlags := False;
      FieldS_.State := FieldS_.RHeader.State;
      Result := False;
      exit;
    end;
  FieldS_.PositionID := FieldS_.RHeader.PositionID;
  FieldS_.StartPos := FieldS_.RHeader.NextHeader;
  FieldS_.ID := FieldS_.RHeader.ID;
  FieldS_.State := FieldS_.RHeader.State;
  Result := True;
end;

function dbField_OnlyFindLastName(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  f: TField;
begin
  FieldS_.InitFlags := False;
  if dbField_ReadRec(fPos, IOHnd, f) = False then
    begin
      FieldS_.State := f.State;
      Result := False;
      exit;
    end;
  if f.HeaderCount = 0 then
    begin
      FieldS_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  if dbHeader_FindPrev(Name, f.LastHeaderPOS, f.FirstHeaderPOS, IOHnd, FieldS_.RHeader) = False then
    begin
      FieldS_.State := FieldS_.RHeader.State;
      Result := False;
      exit;
    end;
  FieldS_.InitFlags := True;
  FieldS_.PositionID := FieldS_.RHeader.PositionID;
  FieldS_.OverPOS := f.FirstHeaderPOS;
  FieldS_.StartPos := FieldS_.RHeader.PrevHeader;
  FieldS_.Name := Name;
  FieldS_.ID := FieldS_.RHeader.ID;
  FieldS_.State := FieldS_.RHeader.State;
  Result := True;
end;

function dbField_OnlyFindPrevName(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
begin
  if FieldS_.InitFlags = False then
    begin
      FieldS_.State := DB_Field_NotInitSearch;
      Result := False;
      exit;
    end;
  case FieldS_.PositionID of
    DB_Header_1, DB_Header_First:
      begin
        FieldS_.InitFlags := False;
        FieldS_.State := DB_Header_NotFindHeader;
        Result := False;
        exit;
      end;
  end;
  if dbHeader_FindPrev(FieldS_.Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) = False then
    begin
      FieldS_.InitFlags := False;
      FieldS_.State := FieldS_.RHeader.State;
      Result := False;
      exit;
    end;
  FieldS_.PositionID := FieldS_.RHeader.PositionID;
  FieldS_.StartPos := FieldS_.RHeader.PrevHeader;
  FieldS_.ID := FieldS_.RHeader.ID;
  FieldS_.State := FieldS_.RHeader.State;
  Result := True;
end;

function dbField_FindFirst(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  f: TField;
begin
  FieldS_.InitFlags := False;
  if dbField_ReadRec(fPos, IOHnd, f) = False then
    begin
      FieldS_.State := f.State;
      Result := False;
      exit;
    end;
  if f.HeaderCount = 0 then
    begin
      FieldS_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  FieldS_.OverPOS := f.LastHeaderPOS;
  FieldS_.StartPos := f.FirstHeaderPOS;
  while dbHeader_FindNext(Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) do
    begin
      FieldS_.StartPos := FieldS_.RHeader.NextHeader;
      if FieldS_.RHeader.ID = ID then
        begin
          FieldS_.InitFlags := True;
          FieldS_.PositionID := FieldS_.RHeader.PositionID;
          FieldS_.Name := Name;
          FieldS_.ID := ID;
          FieldS_.State := FieldS_.RHeader.State;
          Result := True;
          exit;
        end;
      if (FieldS_.RHeader.PositionID = DB_Header_1) or (FieldS_.RHeader.PositionID = DB_Header_Last) then
        begin
          FieldS_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  FieldS_.State := FieldS_.RHeader.State;
  Result := False;
end;

function dbField_FindNext(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
begin
  if FieldS_.InitFlags = False then
    begin
      FieldS_.State := DB_Field_NotInitSearch;
      Result := False;
      exit;
    end;
  case FieldS_.PositionID of
    DB_Header_1, DB_Header_Last:
      begin
        FieldS_.InitFlags := False;
        FieldS_.State := DB_Header_NotFindHeader;
        Result := False;
        exit;
      end;
  end;
  while dbHeader_FindNext(FieldS_.Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) do
    begin
      FieldS_.StartPos := FieldS_.RHeader.NextHeader;

      if FieldS_.RHeader.ID = FieldS_.ID then
        begin
          FieldS_.PositionID := FieldS_.RHeader.PositionID;
          FieldS_.State := FieldS_.RHeader.State;
          Result := True;
          exit;
        end;

      if FieldS_.RHeader.PositionID = DB_Header_Last then
        begin
          FieldS_.InitFlags := False;
          FieldS_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  FieldS_.InitFlags := False;
  FieldS_.State := FieldS_.RHeader.State;
  Result := False;
end;

function dbField_FindLast(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  f: TField;
begin
  FieldS_.InitFlags := False;
  if dbField_ReadRec(fPos, IOHnd, f) = False then
    begin
      FieldS_.State := f.State;
      Result := False;
      exit;
    end;
  if f.HeaderCount = 0 then
    begin
      FieldS_.State := DB_Header_NotFindHeader;
      Result := False;
      exit;
    end;
  FieldS_.OverPOS := f.FirstHeaderPOS;
  FieldS_.StartPos := f.LastHeaderPOS;
  while dbHeader_FindPrev(Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) do
    begin
      FieldS_.StartPos := FieldS_.RHeader.PrevHeader;
      if FieldS_.RHeader.ID = ID then
        begin
          FieldS_.InitFlags := True;
          FieldS_.PositionID := FieldS_.RHeader.PositionID;
          FieldS_.Name := Name;
          FieldS_.ID := ID;
          FieldS_.State := FieldS_.RHeader.State;
          Result := True;
          exit;
        end;
      if (FieldS_.RHeader.PositionID = DB_Header_1) or (FieldS_.RHeader.PositionID = DB_Header_First) then
        begin
          FieldS_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  FieldS_.State := FieldS_.RHeader.State;
  Result := False;
end;

function dbField_FindPrev(var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
begin
  if FieldS_.InitFlags = False then
    begin
      FieldS_.State := DB_Field_NotInitSearch;
      Result := False;
      exit;
    end;
  case FieldS_.PositionID of
    DB_Header_1, DB_Header_First:
      begin
        FieldS_.InitFlags := False;
        FieldS_.State := DB_Header_NotFindHeader;
        Result := False;
        exit;
      end;
  end;
  while dbHeader_FindPrev(FieldS_.Name, FieldS_.StartPos, FieldS_.OverPOS, IOHnd, FieldS_.RHeader) do
    begin
      FieldS_.StartPos := FieldS_.RHeader.PrevHeader;

      if FieldS_.RHeader.ID = FieldS_.ID then
        begin
          FieldS_.PositionID := FieldS_.RHeader.PositionID;
          FieldS_.State := FieldS_.RHeader.State;
          Result := True;
          exit;
        end;

      if FieldS_.RHeader.PositionID = DB_Header_First then
        begin
          FieldS_.InitFlags := False;
          FieldS_.State := DB_Header_NotFindHeader;
          Result := False;
          exit;
        end;
    end;
  FieldS_.InitFlags := False;
  FieldS_.State := FieldS_.RHeader.State;
  Result := False;
end;

function dbField_FindFirstItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean;
begin
  if dbField_FindFirst(Name, DB_Header_Item_ID, fPos, IOHnd, FieldS_) = False then
    begin
      Result := False;
      exit;
    end;
  Item_.RHeader := FieldS_.RHeader;
  if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
    begin
      FieldS_.State := Item_.State;
      Result := False;
      exit;
    end;

  if Item_.ExtID = ItemExtID then
    begin
      Result := True;
      exit;
    end;

  while dbField_FindNext(IOHnd, FieldS_) do
    begin
      Item_.RHeader := FieldS_.RHeader;
      if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
        begin
          FieldS_.State := Item_.State;
          Result := False;
          exit;
        end;

      if Item_.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindNextItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean;
begin
  while dbField_FindNext(IOHnd, FieldS_) do
    begin
      Item_.RHeader := FieldS_.RHeader;
      if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
        begin
          FieldS_.State := Item_.State;
          Result := False;
          exit;
        end;

      if Item_.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindLastItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean;
begin
  if dbField_FindLast(Name, DB_Header_Item_ID, fPos, IOHnd, FieldS_) = False then
    begin
      Result := False;
      exit;
    end;
  Item_.RHeader := FieldS_.RHeader;
  if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
    begin
      FieldS_.State := Item_.State;
      Result := False;
      exit;
    end;

  if Item_.ExtID = ItemExtID then
    begin
      Result := True;
      exit;
    end;

  while dbField_FindPrev(IOHnd, FieldS_) do
    begin
      Item_.RHeader := FieldS_.RHeader;
      if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
        begin
          FieldS_.State := Item_.State;
          Result := False;
          exit;
        end;

      if Item_.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindPrevItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch; var Item_: TItem): Boolean;
begin
  while dbField_FindPrev(IOHnd, FieldS_) do
    begin
      Item_.RHeader := FieldS_.RHeader;
      if dbItem_OnlyReadItemRec(FieldS_.RHeader.DataPosition, IOHnd, Item_) = False then
        begin
          FieldS_.State := Item_.State;
          Result := False;
          exit;
        end;

      if Item_.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindFirstItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  itm: TItem;
begin
  if dbField_FindFirst(Name, DB_Header_Item_ID, fPos, IOHnd, FieldS_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
    begin
      FieldS_.State := itm.State;
      Result := False;
      exit;
    end;

  if itm.ExtID = ItemExtID then
    begin
      Result := True;
      exit;
    end;

  while dbField_FindNext(IOHnd, FieldS_) do
    begin
      if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
        begin
          FieldS_.State := itm.State;
          Result := False;
          exit;
        end;
      if itm.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindNextItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  itm: TItem;
begin
  while dbField_FindNext(IOHnd, FieldS_) do
    begin
      if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
        begin
          FieldS_.State := itm.State;
          Result := False;
          exit;
        end;
      if itm.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindLastItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  itm: TItem;
begin
  if dbField_FindLast(Name, DB_Header_Item_ID, fPos, IOHnd, FieldS_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
    begin
      FieldS_.State := itm.State;
      Result := False;
      exit;
    end;

  if itm.ExtID = ItemExtID then
    begin
      Result := True;
      exit;
    end;

  while dbField_FindPrev(IOHnd, FieldS_) do
    begin
      if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
        begin
          FieldS_.State := itm.State;
          Result := False;
          exit;
        end;
      if itm.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_FindPrevItem(const ItemExtID: Byte; var IOHnd: TIOHnd; var FieldS_: TFieldSearch): Boolean;
var
  itm: TItem;
begin
  while dbField_FindPrev(IOHnd, FieldS_) do
    begin
      if dbItem_ReadRec(FieldS_.RHeader.CurrentHeader, IOHnd, itm) = False then
        begin
          FieldS_.State := itm.State;
          Result := False;
          exit;
        end;
      if itm.ExtID = ItemExtID then
        begin
          Result := True;
          exit;
        end;
    end;
  Result := False;
end;

function dbField_ExistItem(const Name: U_String; const ItemExtID: Byte; const fPos: Int64; var IOHnd: TIOHnd): Boolean;
var
  fs: TFieldSearch;
begin
  Result := dbField_FindFirstItem(Name, ItemExtID, fPos, IOHnd, fs);
end;

function dbField_ExistHeader(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd): Boolean;
var
  fs: TFieldSearch;
begin
  Result := dbField_FindFirst(Name, ID, fPos, IOHnd, fs);
end;

function dbField_CreateHeader(const Name: U_String; const ID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var Header_: THeader): Boolean;
var
  f: TField;
  Header: THeader;
begin
  if dbField_ReadRec(fPos, IOHnd, f) = False then
    begin
      Header_.State := f.State;
      Result := False;
      exit;
    end;
  Header_.ID := ID;
  Header_.Name := Name;
  case f.HeaderCount of
    0:
      begin
        f.HeaderCount := 1;
        f.FirstHeaderPOS := umlFileGetSize(IOHnd);
        f.LastHeaderPOS := f.FirstHeaderPOS;
        f.RHeader.ModificationTime := umlDefaultTime;
        Header_.PositionID := DB_Header_1;
        Header_.NextHeader := f.LastHeaderPOS;
        Header_.PrevHeader := f.FirstHeaderPOS;
        Header_.CurrentHeader := f.FirstHeaderPOS;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(IOHnd);
        if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
          begin
            Header_.State := f.State;
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(Header_.CurrentHeader, IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    1:
      begin
        Header_.CurrentHeader := umlFileGetSize(IOHnd);
        Header_.NextHeader := f.FirstHeaderPOS;
        Header_.PrevHeader := f.FirstHeaderPOS;

        if dbHeader_ReadRec(f.FirstHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.PrevHeader := Header_.CurrentHeader;
        Header.NextHeader := Header_.CurrentHeader;
        Header.PositionID := DB_Header_First;
        if dbHeader_WriteRec(f.FirstHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        f.HeaderCount := f.HeaderCount + 1;
        f.LastHeaderPOS := Header_.CurrentHeader;
        f.RHeader.ModificationTime := umlDefaultTime;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(IOHnd);
        Header_.PositionID := DB_Header_Last;
        if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
          begin
            Header_.State := f.State;
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(Header_.CurrentHeader, IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    else
      begin
        Header_.CurrentHeader := umlFileGetSize(IOHnd);

        // modify first header
        if dbHeader_ReadRec(f.FirstHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.PrevHeader := Header_.CurrentHeader;
        Header_.NextHeader := Header.CurrentHeader;
        if dbHeader_WriteRec(f.FirstHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;

        // moidfy last header
        if dbHeader_ReadRec(f.LastHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.NextHeader := Header_.CurrentHeader;
        Header_.PrevHeader := f.LastHeaderPOS;
        Header.PositionID := DB_Header_Medium;
        if dbHeader_WriteRec(f.LastHeaderPOS, IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;

        f.HeaderCount := f.HeaderCount + 1;
        f.LastHeaderPOS := Header_.CurrentHeader;
        f.RHeader.ModificationTime := umlDefaultTime;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(IOHnd);
        Header_.PositionID := DB_Header_Last;
        if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
          begin
            Header_.State := f.State;
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(Header_.CurrentHeader, IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
  end;
  Header_.State := DB_Header_ok;
  Result := True;
end;

function dbField_InsertNewHeader(const Name: U_String; const ID: Byte; const FieldPos, InsertHeaderPos: Int64; var IOHnd: TIOHnd; var NewHeader: THeader): Boolean;
var
  f: TField;

  Curr, Prev: THeader;
begin
  if dbField_ReadRec(FieldPos, IOHnd, f) = False then
    begin
      NewHeader.State := f.State;
      Result := False;
      exit;
    end;

  if dbHeader_ReadRec(InsertHeaderPos, IOHnd, Curr) = False then
    begin
      NewHeader.State := Curr.State;
      Result := False;
      exit;
    end;

  f.RHeader.ModificationTime := umlDefaultTime;

  NewHeader.CurrentHeader := umlFileGetSize(IOHnd);
  NewHeader.DataPosition := NewHeader.CurrentHeader + Get_DB_HeaderL(IOHnd);
  NewHeader.CreateTime := umlDefaultTime;
  NewHeader.ModificationTime := umlDefaultTime;
  NewHeader.ID := ID;
  NewHeader.UserProperty := 0;
  NewHeader.Name := Name;
  NewHeader.State := DB_Header_ok;

  case Curr.PositionID of
    DB_Header_First:
      begin
        if f.HeaderCount > 1 then
          begin
            // moidfy field
            f.HeaderCount := f.HeaderCount + 1;
            f.FirstHeaderPOS := NewHeader.CurrentHeader;
            if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
              begin
                NewHeader.State := f.State;
                Result := False;
                exit;
              end;

            // write newheader
            NewHeader.PrevHeader := f.LastHeaderPOS;
            NewHeader.NextHeader := Curr.CurrentHeader;
            NewHeader.PositionID := DB_Header_First;
            if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
              begin
                Result := False;
                exit;
              end;

            // moidfy current
            Curr.PrevHeader := NewHeader.CurrentHeader;
            Curr.PositionID := DB_Header_Medium;
            if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
              begin
                NewHeader.State := Curr.State;
                Result := False;
                exit;
              end;
          end
        else if f.HeaderCount = 1 then
          begin
            // modify field
            f.HeaderCount := f.HeaderCount + 1;
            f.FirstHeaderPOS := NewHeader.CurrentHeader;
            f.LastHeaderPOS := Curr.CurrentHeader;
            if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
              begin
                NewHeader.State := f.State;
                Result := False;
                exit;
              end;

            // write newheader
            NewHeader.PrevHeader := f.LastHeaderPOS;
            NewHeader.NextHeader := Curr.CurrentHeader;
            NewHeader.PositionID := DB_Header_First;
            if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
              begin
                Result := False;
                exit;
              end;

            // modify current header
            Curr.PrevHeader := NewHeader.CurrentHeader;
            Curr.PositionID := DB_Header_Last;
            if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
              begin
                NewHeader.State := Curr.State;
                Result := False;
                exit;
              end;
          end
        else
          begin
            // error
            NewHeader.State := DB_Header_NotFindHeader;
            Result := False;
            exit;
          end
      end;
    DB_Header_Medium:
      begin
        // read prev header
        if dbHeader_ReadRec(Curr.PrevHeader, IOHnd, Prev) = False then
          begin
            NewHeader.State := Prev.State;
            Result := False;
            exit;
          end;

        // modify field
        f.HeaderCount := f.HeaderCount + 1;
        if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
          begin
            NewHeader.State := f.State;
            Result := False;
            exit;
          end;

        // write newheader
        NewHeader.PrevHeader := Prev.CurrentHeader;
        NewHeader.NextHeader := Curr.CurrentHeader;
        NewHeader.PositionID := DB_Header_Medium;
        if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
          begin
            Result := False;
            exit;
          end;

        // modify prev header
        Prev.NextHeader := NewHeader.CurrentHeader;
        if dbHeader_WriteRec(Prev.CurrentHeader, IOHnd, Prev) = False then
          begin
            NewHeader.State := Prev.State;
            Result := False;
            exit;
          end;

        // write current
        Curr.PrevHeader := NewHeader.CurrentHeader;
        Curr.PositionID := DB_Header_Medium;
        if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
          begin
            NewHeader.State := Curr.State;
            Result := False;
            exit;
          end;
      end;
    DB_Header_Last:
      begin
        if f.HeaderCount > 1 then
          begin
            // read prev header
            if dbHeader_ReadRec(Curr.PrevHeader, IOHnd, Prev) = False then
              begin
                NewHeader.State := Prev.State;
                Result := False;
                exit;
              end;

            // modify field
            f.HeaderCount := f.HeaderCount + 1;
            if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
              begin
                NewHeader.State := f.State;
                Result := False;
                exit;
              end;

            // write newheader
            NewHeader.PrevHeader := Prev.CurrentHeader;
            NewHeader.NextHeader := Curr.CurrentHeader;
            NewHeader.PositionID := DB_Header_Medium;
            if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
              begin
                Result := False;
                exit;
              end;

            // modify prev header
            Prev.NextHeader := NewHeader.CurrentHeader;
            if dbHeader_WriteRec(Prev.CurrentHeader, IOHnd, Prev) = False then
              begin
                NewHeader.State := Prev.State;
                Result := False;
                exit;
              end;

            // write current
            Curr.PrevHeader := NewHeader.CurrentHeader;
            Curr.PositionID := DB_Header_Last;
            if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
              begin
                NewHeader.State := Curr.State;
                Result := False;
                exit;
              end;
          end
        else if f.HeaderCount = 1 then
          begin
            // modify field
            f.HeaderCount := f.HeaderCount + 1;
            f.FirstHeaderPOS := NewHeader.CurrentHeader;
            f.LastHeaderPOS := Curr.CurrentHeader;
            if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
              begin
                NewHeader.State := f.State;
                Result := False;
                exit;
              end;

            // write newheader
            NewHeader.PrevHeader := f.LastHeaderPOS;
            NewHeader.NextHeader := Curr.CurrentHeader;
            NewHeader.PositionID := DB_Header_First;
            if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
              begin
                Result := False;
                exit;
              end;

            // modify current header
            Curr.PrevHeader := NewHeader.CurrentHeader;
            Curr.PositionID := DB_Header_Last;
            if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
              begin
                NewHeader.State := Curr.State;
                Result := False;
                exit;
              end;
          end
        else
          begin
            // error
            NewHeader.State := DB_Header_NotFindHeader;
            Result := False;
            exit;
          end;
      end;
    DB_Header_1:
      begin
        // modify field
        f.HeaderCount := f.HeaderCount + 1;
        f.FirstHeaderPOS := NewHeader.CurrentHeader;
        f.LastHeaderPOS := Curr.CurrentHeader;
        if dbField_WriteRec(f.RHeader.CurrentHeader, IOHnd, f) = False then
          begin
            NewHeader.State := f.State;
            Result := False;
            exit;
          end;

        // write newheader
        NewHeader.PrevHeader := f.LastHeaderPOS;
        NewHeader.NextHeader := Curr.CurrentHeader;
        NewHeader.PositionID := DB_Header_First;
        if dbHeader_WriteRec(NewHeader.CurrentHeader, IOHnd, NewHeader) = False then
          begin
            Result := False;
            exit;
          end;

        // modify current header
        Curr.PrevHeader := NewHeader.CurrentHeader;
        Curr.PositionID := DB_Header_Last;
        if dbHeader_WriteRec(Curr.CurrentHeader, IOHnd, Curr) = False then
          begin
            NewHeader.State := Curr.State;
            Result := False;
            exit;
          end;
      end;
  end;

  NewHeader.State := DB_Header_ok;
  Result := True;
end;

function dbField_DeleteHeader_(const HeaderPOS, FieldPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
var
  DeleteHeader, SwapHeader: THeader;
begin
  if dbField_ReadRec(FieldPos, IOHnd, Field_) = False then
    begin
      Result := False;
      exit;
    end;
  case Field_.HeaderCount of
    0:
      begin
        Field_.State := DB_Field_DeleteHeaderError;
        Result := False;
        exit;
      end;
    1:
      begin
        if HeaderPOS = Field_.FirstHeaderPOS then
          begin
            Field_.HeaderCount := 0;
            Field_.FirstHeaderPOS := 0;
            Field_.LastHeaderPOS := 0;
            Field_.RHeader.ModificationTime := umlDefaultTime;
            if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
              begin
                Result := False;
                exit;
              end;
            Result := True;
            Field_.State := DB_Field_ok;
            exit;
          end;
        Result := False;
        Field_.State := DB_Field_DeleteHeaderError;
        exit;
      end;
    2:
      begin
        if dbHeader_ReadRec(HeaderPOS, IOHnd, DeleteHeader) = False then
          begin
            Field_.State := DeleteHeader.State;
            Result := False;
            exit;
          end;
        case DeleteHeader.PositionID of
          DB_Header_First:
            begin
              if dbHeader_ReadRec(Field_.LastHeaderPOS, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := SwapHeader.CurrentHeader;
              SwapHeader.PrevHeader := SwapHeader.CurrentHeader;
              SwapHeader.PositionID := DB_Header_1;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.FirstHeaderPOS := SwapHeader.CurrentHeader;
              Field_.LastHeaderPOS := SwapHeader.CurrentHeader;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          DB_Header_Last:
            begin
              if dbHeader_ReadRec(Field_.FirstHeaderPOS, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := SwapHeader.CurrentHeader;
              SwapHeader.PrevHeader := SwapHeader.CurrentHeader;
              SwapHeader.PositionID := DB_Header_1;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.FirstHeaderPOS := SwapHeader.CurrentHeader;
              Field_.LastHeaderPOS := SwapHeader.CurrentHeader;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          else
            begin
              Field_.State := DB_Field_DeleteHeaderError;
              Result := False;
            end;
        end;
        exit;
      end;
    3:
      begin
        if dbHeader_ReadRec(HeaderPOS, IOHnd, DeleteHeader) = False then
          begin
            Field_.State := DeleteHeader.State;
            Result := False;
            exit;
          end;
        case DeleteHeader.PositionID of
          DB_Header_First:
            begin
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              SwapHeader.PositionID := DB_Header_First;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.FirstHeaderPOS := SwapHeader.CurrentHeader;
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          DB_Header_Medium:
            begin
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          DB_Header_Last:
            begin
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              SwapHeader.PositionID := DB_Header_Last;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.LastHeaderPOS := SwapHeader.CurrentHeader;
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          else
            begin
              Field_.State := DB_Field_DeleteHeaderError;
              Result := False;
            end;
        end;
        exit;
      end;
    else
      begin
        if dbHeader_ReadRec(HeaderPOS, IOHnd, DeleteHeader) = False then
          begin
            Field_.State := DeleteHeader.State;
            Result := False;
            exit;
          end;
        case DeleteHeader.PositionID of
          DB_Header_First:
            begin
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              SwapHeader.PositionID := DB_Header_First;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.FirstHeaderPOS := SwapHeader.CurrentHeader;
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          DB_Header_Medium:
            begin
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          DB_Header_Last:
            begin
              if dbHeader_ReadRec(DeleteHeader.PrevHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.NextHeader := DeleteHeader.NextHeader;
              SwapHeader.PositionID := DB_Header_Last;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.LastHeaderPOS := SwapHeader.CurrentHeader;
              if dbHeader_ReadRec(DeleteHeader.NextHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              SwapHeader.PrevHeader := DeleteHeader.PrevHeader;
              if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
                begin
                  Field_.State := SwapHeader.State;
                  Result := False;
                  exit;
                end;
              Field_.HeaderCount := Field_.HeaderCount - 1;
              Field_.RHeader.ModificationTime := umlDefaultTime;
              if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
                begin
                  Result := False;
                  exit;
                end;
              Field_.State := DB_Field_ok;
              Result := True;
            end;
          else
            begin
              Field_.State := DB_Field_DeleteHeaderError;
              Result := False;
            end;
        end;
        exit;
      end;
  end;
  Result := True;
end;

function dbField_DeleteHeader(const HeaderPOS, FieldPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  Result := dbField_DeleteHeader_(HeaderPOS, FieldPos, IOHnd, Field_);
  if Result then
    if IOHnd.Data <> nil then
      if Assigned(PObjectDataHandle(IOHnd.Data)^.OnDeleteHeader) then
          PObjectDataHandle(IOHnd.Data)^.OnDeleteHeader(HeaderPOS);
end;

function dbField_MoveHeader(const HeaderPOS: Int64; const SourcerFieldPOS, TargetFieldPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
var
  ActiveHeader, SwapHeader: THeader;
begin
  if dbHeader_ReadRec(HeaderPOS, IOHnd, ActiveHeader) = False then
    begin
      Field_.State := ActiveHeader.State;
      Result := False;
      exit;
    end;
  if dbField_DeleteHeader_(ActiveHeader.CurrentHeader, SourcerFieldPOS, IOHnd, Field_) = False then
    begin
      Result := False;
      exit;
    end;

  if dbField_ReadRec(TargetFieldPos, IOHnd, Field_) = False then
    begin
      Result := False;
      exit;
    end;
  case Field_.HeaderCount of
    0:
      begin
        Field_.HeaderCount := 1;
        Field_.FirstHeaderPOS := ActiveHeader.CurrentHeader;
        Field_.LastHeaderPOS := Field_.FirstHeaderPOS;
        ActiveHeader.PositionID := DB_Header_1;
        ActiveHeader.NextHeader := Field_.FirstHeaderPOS;
        ActiveHeader.PrevHeader := Field_.FirstHeaderPOS;
        if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
          begin
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(ActiveHeader.CurrentHeader, IOHnd, ActiveHeader) = False then
          begin
            Field_.State := ActiveHeader.State;
            Result := False;
            exit;
          end;
      end;
    1:
      begin

        if dbHeader_ReadRec(Field_.FirstHeaderPOS, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;
        SwapHeader.PrevHeader := ActiveHeader.CurrentHeader;
        SwapHeader.NextHeader := ActiveHeader.CurrentHeader;
        SwapHeader.PositionID := DB_Header_First;
        ActiveHeader.NextHeader := SwapHeader.CurrentHeader;
        ActiveHeader.PrevHeader := SwapHeader.CurrentHeader;
        ActiveHeader.PositionID := DB_Header_Last;

        if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;
        Field_.HeaderCount := Field_.HeaderCount + 1;
        Field_.LastHeaderPOS := ActiveHeader.CurrentHeader;
        Field_.RHeader.ModificationTime := umlDefaultTime;
        if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
          begin
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(ActiveHeader.CurrentHeader, IOHnd, ActiveHeader) = False then
          begin
            Field_.State := ActiveHeader.State;
            Result := False;
            exit;
          end;
      end;
    else
      begin
        if dbHeader_ReadRec(Field_.FirstHeaderPOS, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;
        SwapHeader.PrevHeader := ActiveHeader.CurrentHeader;
        SwapHeader.PositionID := DB_Header_First;
        ActiveHeader.NextHeader := SwapHeader.CurrentHeader;
        if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;

        if dbHeader_ReadRec(Field_.LastHeaderPOS, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;
        SwapHeader.NextHeader := ActiveHeader.CurrentHeader;
        ActiveHeader.PrevHeader := SwapHeader.CurrentHeader;
        SwapHeader.PositionID := DB_Header_Medium;
        if dbHeader_WriteRec(SwapHeader.CurrentHeader, IOHnd, SwapHeader) = False then
          begin
            Field_.State := SwapHeader.State;
            Result := False;
            exit;
          end;
        Field_.HeaderCount := Field_.HeaderCount + 1;
        Field_.LastHeaderPOS := ActiveHeader.CurrentHeader;
        Field_.RHeader.ModificationTime := umlDefaultTime;
        ActiveHeader.PositionID := DB_Header_Last;
        if dbField_WriteRec(Field_.RHeader.CurrentHeader, IOHnd, Field_) = False then
          begin
            Result := False;
            exit;
          end;
        if dbHeader_WriteRec(ActiveHeader.CurrentHeader, IOHnd, ActiveHeader) = False then
          begin
            Field_.State := ActiveHeader.State;
            Result := False;
            exit;
          end;
      end;
  end;
  Field_.State := DB_Field_ok;
  Result := True;
end;

function dbField_CreateField(const Name: U_String; const fPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  if dbField_CreateHeader(Name, DB_Header_Field_ID, fPos, IOHnd, Field_.RHeader) = False then
    begin
      Field_.State := Field_.RHeader.State;
      Result := False;
      exit;
    end;

  Field_.HeaderCount := 0;
  Field_.UpFieldPOS := fPos;
  Field_.FirstHeaderPOS := 0;
  Field_.LastHeaderPOS := 0;
  if dbField_OnlyWriteFieldRec(Field_.RHeader.DataPosition, IOHnd, Field_) = False then
    begin
      Result := False;
      exit;
    end;
  Field_.State := DB_Field_ok;
  Result := True;
end;

function dbField_InsertNewField(const Name: U_String; const FieldPos, CurrentInsertPos: Int64; var IOHnd: TIOHnd; var Field_: TField): Boolean;
begin
  if dbField_InsertNewHeader(Name, DB_Header_Field_ID, FieldPos, CurrentInsertPos, IOHnd, Field_.RHeader) = False then
    begin
      Field_.State := Field_.RHeader.State;
      Result := False;
      exit;
    end;

  Field_.HeaderCount := 0;
  Field_.UpFieldPOS := FieldPos;
  Field_.FirstHeaderPOS := 0;
  Field_.LastHeaderPOS := 0;
  if dbField_OnlyWriteFieldRec(Field_.RHeader.DataPosition, IOHnd, Field_) = False then
    begin
      Result := False;
      exit;
    end;
  Field_.State := DB_Field_ok;
  Result := True;
end;

function dbField_CreateItem(const Name: U_String; const ExterID: Byte; const fPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  if dbField_CreateHeader(Name, DB_Header_Item_ID, fPos, IOHnd, Item_.RHeader) = False then
    begin
      Item_.State := Item_.RHeader.State;
      Result := False;
      exit;
    end;

  Item_.ExtID := ExterID;
  Item_.FirstBlockPOS := 0;
  Item_.LastBlockPOS := 0;
  Item_.Size := 0;
  Item_.BlockCount := 0;
  Item_.RHeader.ModificationTime := umlDefaultTime;
  if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;
  Item_.DataModification := True;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbField_InsertNewItem(const Name: U_String; const ExterID: Byte; const FieldPos, CurrentInsertPos: Int64; var IOHnd: TIOHnd; var Item_: TItem): Boolean;
begin
  if dbField_InsertNewHeader(Name, DB_Header_Item_ID, FieldPos, CurrentInsertPos, IOHnd, Item_.RHeader) = False then
    begin
      Item_.State := Item_.RHeader.State;
      Result := False;
      exit;
    end;

  Item_.ExtID := ExterID;
  Item_.FirstBlockPOS := 0;
  Item_.LastBlockPOS := 0;
  Item_.Size := 0;
  Item_.BlockCount := 0;
  Item_.RHeader.ModificationTime := umlDefaultTime;
  if dbItem_OnlyWriteItemRec(Item_.RHeader.DataPosition, IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;
  Item_.DataModification := True;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbField_CopyItem(var Item_: TItem; var IOHnd: TIOHnd; const DestFieldPos: Int64; var DestIOHnd: TIOHnd): Boolean;
var
  i: Int64;
  NewItemHnd: TItem;
  buff: array [0 .. C_Buffer_Chunk_Size] of Byte;
begin
  Init_TItem(NewItemHnd);
  NewItemHnd := Item_;
  if dbField_CreateItem(Item_.RHeader.Name, Item_.ExtID, DestFieldPos, DestIOHnd, NewItemHnd) = False then
    begin
      Item_.State := NewItemHnd.State;
      Result := False;
      exit;
    end;
  if dbItem_BlockSeekStartPOS(IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;
  i := Item_.Size;
  while i >= C_Buffer_Chunk_Size do
    begin
      if dbItem_BlockReadData(IOHnd, Item_, buff, C_Buffer_Chunk_Size) = False then
        begin
          Result := False;
          exit;
        end;
      if dbItem_BlockAppendWriteData(DestIOHnd, NewItemHnd, buff, C_Buffer_Chunk_Size) = False then
        begin
          Item_.State := NewItemHnd.State;
          Result := False;
          exit;
        end;
      dec(i, C_Buffer_Chunk_Size);
    end;
  if i > 0 then
    begin
      if dbItem_BlockReadData(IOHnd, Item_, buff, i) = False then
        begin
          Result := False;
          exit;
        end;
      if dbItem_BlockAppendWriteData(DestIOHnd, NewItemHnd, buff, i) = False then
        begin
          Item_.State := NewItemHnd.State;
          Result := False;
          exit;
        end;
    end;

  if dbItem_WriteRec(NewItemHnd.RHeader.CurrentHeader, DestIOHnd, NewItemHnd) = False then
    begin
      Item_.State := NewItemHnd.State;
      Result := False;
      exit;
    end;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbField_CopyItemBuffer(var Item_: TItem; var IOHnd: TIOHnd; var DestItem_: TItem; var DestIOHnd: TIOHnd): Boolean;
var
  i: Int64;
  buff: array [0 .. C_Buffer_Chunk_Size] of Byte;
begin
  if dbItem_BlockSeekStartPOS(IOHnd, Item_) = False then
    begin
      Result := False;
      exit;
    end;
  i := Item_.Size;
  while i >= C_Buffer_Chunk_Size do
    begin
      if dbItem_BlockReadData(IOHnd, Item_, buff, C_Buffer_Chunk_Size) = False then
        begin
          Result := False;
          exit;
        end;
      if dbItem_BlockAppendWriteData(DestIOHnd, DestItem_, buff, C_Buffer_Chunk_Size) = False then
        begin
          Item_.State := DestItem_.State;
          Result := False;
          exit;
        end;
      dec(i, C_Buffer_Chunk_Size);
    end;
  if i > 0 then
    begin
      if dbItem_BlockReadData(IOHnd, Item_, buff, i) = False then
        begin
          Result := False;
          exit;
        end;
      if dbItem_BlockAppendWriteData(DestIOHnd, DestItem_, buff, i) = False then
        begin
          Item_.State := DestItem_.State;
          Result := False;
          exit;
        end;
    end;

  // fixed by qq600585,2018-12
  // Header has a certain chance of being changed by other item operation during the opening of item
  if dbHeader_ReadReservedRec(DestItem_.RHeader.CurrentHeader, DestIOHnd, DestItem_.RHeader) = False then
    begin
      Item_.State := DestItem_.State;
      Result := False;
      exit;
    end;
  if dbItem_WriteRec(DestItem_.RHeader.CurrentHeader, DestIOHnd, DestItem_) = False then
    begin
      Item_.State := DestItem_.State;
      Result := False;
      exit;
    end;
  Item_.State := DB_Item_ok;
  Result := True;
end;

function dbField_CopyAllTo(const FilterName: U_String; const FieldPos: Int64; var IOHnd: TIOHnd; const DestFieldPos: Int64; var DestIOHnd: TIOHnd): Boolean;
var
  fs: TFieldSearch;
  NewField: TField;
  NewItem: TItem;
begin
  Init_TFieldSearch(fs);
  if dbField_OnlyFindFirstName(FilterName, FieldPos, IOHnd, fs) then
    begin
      repeat
        case fs.ID of
          DB_Header_Field_ID:
            begin
              Init_TField(NewField);
              if dbField_ReadRec(fs.RHeader.CurrentHeader, IOHnd, NewField) then
                if dbField_CreateField(fs.RHeader.Name, DestFieldPos, DestIOHnd, NewField) then
                    dbField_CopyAllTo(FilterName, fs.RHeader.CurrentHeader, IOHnd, NewField.RHeader.CurrentHeader, DestIOHnd);
            end;
          DB_Header_Item_ID:
            begin
              if dbItem_ReadRec(fs.RHeader.CurrentHeader, IOHnd, NewItem) then
                begin
                  dbField_CopyItem(NewItem, IOHnd, DestFieldPos, DestIOHnd);
                end;
            end;
        end;
      until not dbField_OnlyFindNextName(IOHnd, fs);
    end;
  Result := True;
end;

function db_CreateNew(const FileName: U_String; var DB_: TObjectDataHandle): Boolean;
begin
  if umlFileTest(DB_.IOHnd) then
    begin
      DB_.State := DB_RepCreatePackError;
      Result := False;
      exit;
    end;
  if umlFileCreate(FileName, DB_.IOHnd) = False then
    begin
      DB_.State := DB_CreatePackError;
      Result := False;
      exit;
    end;
  FillPtrByte(@DB_.ReservedData[0], DB_ReservedData_Size, 0);
  DB_.FixedStringL := DB_.IOHnd.FixedStringL;
  DB_.MajorVer := DB_MajorVersion;
  DB_.MinorVer := DB_MinorVersion;
  DB_.CreateTime := umlDefaultTime;
  DB_.ModificationTime := DB_.CreateTime;
  DB_.RootHeaderCount := 0;
  DB_.DefaultFieldPOS := Get_DB_L(DB_.IOHnd);
  DB_.LastHeaderPOS := DB_.DefaultFieldPOS;
  DB_.FirstHeaderPOS := DB_.DefaultFieldPOS;
  DB_.CurrentFieldPOS := DB_.DefaultFieldPOS;
  if db_WriteRec(0, DB_.IOHnd, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if db_CreateAndSetRootField(DB_DefaultField, DB_FileDescription, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_Open(const FileName: U_String; var DB_: TObjectDataHandle; _OnlyRead: Boolean): Boolean;
begin
  if umlFileTest(DB_.IOHnd) then
    begin
      DB_.State := DB_RepOpenPackError;
      Result := False;
      exit;
    end;

  if umlFileOpen(FileName, DB_.IOHnd, _OnlyRead) = False then
    begin
      DB_.State := DB_OpenPackError;
      Result := False;
      exit;
    end;

  if DB_.IOHnd.Size = 0 then
    begin
      FillPtrByte(@DB_.ReservedData[0], DB_ReservedData_Size, 0);
      DB_.FixedStringL := DB_.IOHnd.FixedStringL;
      DB_.MajorVer := DB_MajorVersion;
      DB_.MinorVer := DB_MinorVersion;
      DB_.CreateTime := umlDefaultTime;
      DB_.ModificationTime := DB_.CreateTime;
      DB_.RootHeaderCount := 0;
      DB_.DefaultFieldPOS := Get_DB_L(DB_.IOHnd);
      DB_.LastHeaderPOS := DB_.DefaultFieldPOS;
      DB_.FirstHeaderPOS := DB_.DefaultFieldPOS;
      DB_.CurrentFieldPOS := DB_.DefaultFieldPOS;
      if db_WriteRec(0, DB_.IOHnd, DB_) = False then
        begin
          Result := False;
          exit;
        end;
      if db_CreateAndSetRootField(DB_DefaultField, DB_FileDescription, DB_) = False then
        begin
          Result := False;
          exit;
        end;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;

  if db_ReadRec(0, DB_.IOHnd, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if DB_.FixedStringL = 0 then
      DB_.FixedStringL := DB_.IOHnd.FixedStringL;
  DB_.IOHnd.FixedStringL := DB_.FixedStringL;

  DB_.State := DB_ok;
  Result := True;
end;

function db_CreateAsStream(stream: U_Stream; const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean;
begin
  if umlFileTest(DB_.IOHnd) then
    begin
      DB_.State := DB_RepCreatePackError;
      Result := False;
      exit;
    end;
  if umlFileCreateAsStream(Name, stream, DB_.IOHnd) = False then
    begin
      DB_.State := DB_CreatePackError;
      Result := False;
      exit;
    end;
  FillPtrByte(@DB_.ReservedData[0], DB_ReservedData_Size, 0);
  DB_.FixedStringL := DB_.IOHnd.FixedStringL;
  DB_.MajorVer := DB_MajorVersion;
  DB_.MinorVer := DB_MinorVersion;
  DB_.CreateTime := umlDefaultTime;
  DB_.ModificationTime := DB_.CreateTime;
  DB_.RootHeaderCount := 0;
  DB_.DefaultFieldPOS := Get_DB_L(DB_.IOHnd);
  DB_.LastHeaderPOS := DB_.DefaultFieldPOS;
  DB_.FirstHeaderPOS := DB_.DefaultFieldPOS;
  DB_.CurrentFieldPOS := DB_.DefaultFieldPOS;
  if db_WriteRec(0, DB_.IOHnd, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if db_CreateAndSetRootField(DB_DefaultField, DB_FileDescription, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_OpenAsStream(stream: U_Stream; const Name: U_String; var DB_: TObjectDataHandle; _OnlyRead: Boolean): Boolean;
begin
  if umlFileTest(DB_.IOHnd) then
    begin
      DB_.State := DB_RepOpenPackError;
      Result := False;
      exit;
    end;

  if umlFileOpenAsStream(Name, stream, DB_.IOHnd, _OnlyRead) = False then
    begin
      DB_.State := DB_OpenPackError;
      Result := False;
      exit;
    end;

  if db_ReadRec(0, DB_.IOHnd, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if DB_.FixedStringL = 0 then
      DB_.FixedStringL := DB_.IOHnd.FixedStringL;
  DB_.IOHnd.FixedStringL := DB_.FixedStringL;

  DB_.State := DB_ok;
  Result := True;
end;

function db_ClosePack(var DB_: TObjectDataHandle): Boolean;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if DB_.IOHnd.ChangeFromWrite then
    begin
      DB_.ModificationTime := umlDefaultTime;
      if db_WriteRec(0, DB_.IOHnd, DB_) = False then
        begin
          Result := False;
          exit;
        end;
    end;
  if umlFileClose(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_Update(var DB_: TObjectDataHandle): Boolean;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if DB_.IOHnd.ChangeFromWrite then
    begin
      DB_.ModificationTime := umlDefaultTime;
      if db_WriteRec(0, DB_.IOHnd, DB_) = False then
        begin
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := umlFileUpdate(DB_.IOHnd);
end;

function db_CopyFieldTo(const FilterName: U_String; var DB_: TObjectDataHandle; const SourceFieldPos: Int64; var DestTMDB: TObjectDataHandle; const DestFieldPos: Int64): Boolean;
begin
  if dbField_CopyAllTo(FilterName, SourceFieldPos, DB_.IOHnd, DestFieldPos, DestTMDB.IOHnd) then
    begin
      DB_.State := DB_ok;
      DestTMDB.State := DB_ok;
      Result := True;
    end
  else
    begin
      DB_.State := DB_CreatePackError;
      DestTMDB.State := DB_CreatePackError;
      Result := False;
    end;
end;

function db_CopyAllTo(var DB_: TObjectDataHandle; var DestTMDB: TObjectDataHandle): Boolean;
begin
  Result := db_CopyFieldTo('*', DB_, DB_.DefaultFieldPOS, DestTMDB, DestTMDB.DefaultFieldPOS);
end;

function db_CopyAllToDestPath(var DB_: TObjectDataHandle; var DestTMDB: TObjectDataHandle; destPath: U_String): Boolean;
var
  f: TField;
begin
  Result := False;
  db_CreateField(destPath, '', DestTMDB);
  if db_GetField(destPath, f, DestTMDB) then
    begin
      Result := db_CopyFieldTo('*', DB_, DB_.DefaultFieldPOS, DestTMDB, f.RHeader.CurrentHeader);
    end;
end;

function db_TestName(const Name: U_String): Boolean;
begin
  Result := Name.DeleteChar(ZDB_Field_Separator__ + #9#32#13#10).L > 0;
end;

function db_CheckRootField(const Name: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_TestName(Name) = False then
    begin
      DB_.State := DB_PathNameError;
      Field_.State := DB_.State;
      Result := False;
      exit;
    end;

  if db_GetRootField(Name, f, DB_) = False then
    begin
      if db_CreateRootHeader(Name, DB_Header_Field_ID, DB_, Field_.RHeader) = False then
        begin
          DB_.State := Field_.RHeader.State;
          Field_.State := DB_.State;
          Result := False;
          exit;
        end;
      Field_.HeaderCount := 0;
      Field_.UpFieldPOS := -1;
      Field_.FirstHeaderPOS := 0;
      Field_.LastHeaderPOS := 0;
      if dbField_OnlyWriteFieldRec(Field_.RHeader.DataPosition, DB_.IOHnd, Field_) = False then
        begin
          DB_.State := Field_.State;
          Field_.State := DB_.State;
          Result := False;
          exit;
        end;
    end
  else
    begin
      Field_ := f;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_CreateRootHeader(const Name: U_String; const ID: Byte; var DB_: TObjectDataHandle; var Header_: THeader): Boolean;
var
  Header: THeader;
begin
  Header_.ID := ID;
  Header_.Name := Name;
  case DB_.RootHeaderCount of
    0:
      begin
        DB_.RootHeaderCount := 1;
        DB_.FirstHeaderPOS := umlFileGetSize(DB_.IOHnd);
        DB_.LastHeaderPOS := DB_.FirstHeaderPOS;
        DB_.ModificationTime := umlDefaultTime;
        Header_.PositionID := DB_Header_1;
        Header_.NextHeader := DB_.LastHeaderPOS;
        Header_.PrevHeader := DB_.FirstHeaderPOS;
        Header_.CurrentHeader := DB_.FirstHeaderPOS;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(DB_.IOHnd);
        if dbHeader_WriteRec(Header_.CurrentHeader, DB_.IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    1:
      begin
        Header_.CurrentHeader := umlFileGetSize(DB_.IOHnd);
        Header_.NextHeader := DB_.FirstHeaderPOS;
        Header_.PrevHeader := DB_.FirstHeaderPOS;
        if dbHeader_ReadRec(DB_.FirstHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.PrevHeader := Header_.CurrentHeader;
        Header.NextHeader := Header_.CurrentHeader;
        Header.PositionID := DB_Header_First;
        if dbHeader_WriteRec(DB_.FirstHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        DB_.RootHeaderCount := DB_.RootHeaderCount + 1;
        DB_.LastHeaderPOS := Header_.CurrentHeader;
        DB_.ModificationTime := umlDefaultTime;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(DB_.IOHnd);
        Header_.PositionID := DB_Header_Last;
        if dbHeader_WriteRec(Header_.CurrentHeader, DB_.IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
    else
      begin
        Header_.CurrentHeader := umlFileGetSize(DB_.IOHnd);
        if dbHeader_ReadRec(DB_.FirstHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.PrevHeader := Header_.CurrentHeader;
        Header_.NextHeader := Header.CurrentHeader;
        if dbHeader_WriteRec(DB_.FirstHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        if dbHeader_ReadRec(DB_.LastHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        Header.NextHeader := Header_.CurrentHeader;
        Header_.PrevHeader := DB_.LastHeaderPOS;
        Header.PositionID := DB_Header_Medium;
        if dbHeader_WriteRec(DB_.LastHeaderPOS, DB_.IOHnd, Header) = False then
          begin
            Header_.State := Header.State;
            Result := False;
            exit;
          end;
        DB_.RootHeaderCount := DB_.RootHeaderCount + 1;
        DB_.LastHeaderPOS := Header_.CurrentHeader;
        DB_.ModificationTime := umlDefaultTime;
        Header_.CreateTime := umlDefaultTime;
        Header_.ModificationTime := umlDefaultTime;
        Header_.DataPosition := Header_.CurrentHeader + Get_DB_HeaderL(DB_.IOHnd);
        Header_.PositionID := DB_Header_Last;
        if dbHeader_WriteRec(Header_.CurrentHeader, DB_.IOHnd, Header_) = False then
          begin
            Result := False;
            exit;
          end;
      end;
  end;

  Header_.State := DB_Header_ok;
  Result := True;
end;

function db_CreateRootField(const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_TestName(Name) = False then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;

  if db_ExistsRootField(Name, DB_) then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if db_CreateRootHeader(Name, DB_Header_Field_ID, DB_, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;
  f.Description := Description;
  f.HeaderCount := 0;
  f.UpFieldPOS := -1;
  f.FirstHeaderPOS := 0;
  f.LastHeaderPOS := 0;
  if dbField_OnlyWriteFieldRec(f.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_CreateAndSetRootField(const Name, Description: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_TestName(Name) = False then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;

  if db_ExistsRootField(Name, DB_) then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if db_CreateRootHeader(Name, DB_Header_Field_ID, DB_, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;
  f.Description := Description;
  f.HeaderCount := 0;
  f.UpFieldPOS := -1;
  f.FirstHeaderPOS := 0;
  f.LastHeaderPOS := 0;
  if dbField_OnlyWriteFieldRec(f.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  DB_.DefaultFieldPOS := f.RHeader.CurrentHeader;
  DB_.State := DB_ok;
  Result := True;
end;

function db_CreateField(const pathName, Description: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  fs: TFieldSearch;
  i, path_num_: Integer;
  TempPathStr, TempPathName: U_String;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if dbField_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;

  if umlGetLength(pathName) = 0 then
    begin
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;
  TempPathName := pathName;
  path_num_ := db_GetPathCount(TempPathName);
  if path_num_ > 0 then
    begin
      for i := 1 to path_num_ do
        begin
          TempPathStr := db_GetFirstPath(TempPathName);
          TempPathName := db_DeleteFirstPath(TempPathName);

          if db_TestName(TempPathStr) = False then
            begin
              DB_.State := DB_PathNameError;
              Result := False;
              exit;
            end;
          case dbField_FindFirst(TempPathStr, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, fs) of
            False:
              begin
                f.Description := Description;
                if dbField_CreateField(TempPathStr, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
                  begin
                    DB_.State := f.State;
                    Result := False;
                    exit;
                  end;
              end;
            True:
              begin
                if dbField_ReadRec(fs.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
                  begin
                    DB_.State := f.State;
                    Result := False;
                    exit;
                  end;
              end;
          end;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_SetFieldName(const pathName, OriginFieldName, NewFieldName, FieldDescription: U_String; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
  OriginField: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(OriginFieldName, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbField_ReadRec(TempSR.RHeader.CurrentHeader, DB_.IOHnd, OriginField) = False then
    begin
      DB_.State := OriginField.RHeader.State;
      Result := False;
      exit;
    end;
  OriginField.RHeader.Name := NewFieldName;
  OriginField.Description := FieldDescription;
  if dbField_WriteRec(OriginField.RHeader.CurrentHeader, DB_.IOHnd, OriginField) = False then
    begin
      DB_.State := OriginField.RHeader.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_SetItemName(const pathName, OriginItemName, NewItemName, ItemDescription: U_String; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
  OriginItem: TItem;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(OriginItemName, DB_Header_Item_ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbItem_ReadRec(TempSR.RHeader.CurrentHeader, DB_.IOHnd, OriginItem) = False then
    begin
      DB_.State := OriginItem.RHeader.State;
      Result := False;
      exit;
    end;
  OriginItem.RHeader.Name := NewItemName;
  OriginItem.Description := ItemDescription;
  if dbItem_WriteRec(OriginItem.RHeader.CurrentHeader, DB_.IOHnd, OriginItem) = False then
    begin
      DB_.State := OriginItem.RHeader.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_DeleteField(const pathName, FilterName: U_String; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirst(FilterName, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
        begin
          DB_.State := f.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_DeleteHeader(const pathName, FilterName: U_String; const ID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirst(FilterName, ID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
        begin
          DB_.State := f.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_MoveItem(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  SourcerField, TargetField: TField;
begin
  if db_GetField(SourcerPathName, SourcerField, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if db_GetField(TargetPathName, TargetField, DB_) = False then
    begin
      Result := False;
      exit;
    end;

  if SourcerField.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(FilterName, ItemExtID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;

  if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False then
    begin
      DB_.State := TargetField.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirstItem(FilterName, ItemExtID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
        begin
          DB_.State := DB_PathNameError;
          Result := False;
          exit;
        end;
      if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False
      then
        begin
          DB_.State := TargetField.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_MoveField(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  SourcerField, TargetField: TField;
begin
  if db_GetField(SourcerPathName, SourcerField, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if db_GetField(TargetPathName, TargetField, DB_) = False then
    begin
      Result := False;
      exit;
    end;

  if SourcerField.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, DB_Header_Field_ID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;

  if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False then
    begin
      DB_.State := TargetField.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirst(FilterName, DB_Header_Field_ID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
        begin
          DB_.State := DB_PathNameError;
          Result := False;
          exit;
        end;
      if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False
      then
        begin
          DB_.State := TargetField.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_MoveHeader(const SourcerPathName, FilterName: U_String; const TargetPathName: U_String; const HeaderID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  SourcerField, TargetField: TField;
begin
  if db_GetField(SourcerPathName, SourcerField, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if db_GetField(TargetPathName, TargetField, DB_) = False then
    begin
      Result := False;
      exit;
    end;

  if SourcerField.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, HeaderID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;

  if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False then
    begin
      DB_.State := TargetField.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirst(FilterName, HeaderID, SourcerField.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if TempSR.RHeader.CurrentHeader = TargetField.RHeader.CurrentHeader then
        begin
          DB_.State := DB_PathNameError;
          Result := False;
          exit;
        end;
      if dbField_MoveHeader(TempSR.RHeader.CurrentHeader, SourcerField.RHeader.CurrentHeader, TargetField.RHeader.CurrentHeader, DB_.IOHnd, TargetField) = False
      then
        begin
          DB_.State := TargetField.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_SetCurrentRootField(const Name: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if DB_.RootHeaderCount = 0 then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.DefaultFieldPOS := f.RHeader.CurrentHeader;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;

  if DB_.RootHeaderCount = 1 then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.DefaultFieldPOS := f.RHeader.CurrentHeader;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;

  while f.RHeader.CurrentHeader <> DB_.DefaultFieldPOS do
    begin
      if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
        begin
          DB_.State := f.RHeader.State;
          Result := False;
          exit;
        end;
      if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
        begin
          DB_.DefaultFieldPOS := f.RHeader.CurrentHeader;
          DB_.State := DB_ok;
          Result := True;
          exit;
        end;
    end;
  DB_.State := DB_PathNameError;
  Result := False;
end;

function db_SetCurrentField(const pathName: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  fs: TFieldSearch;
  i, path_num_: Integer;
  TempPathStr, TempPathName: U_String;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if dbField_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;

  if umlGetLength(pathName) = 0 then
    begin
      DB_.CurrentFieldPOS := f.RHeader.CurrentHeader;
      DB_.CurrentFieldLevel := 1;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;
  TempPathName := pathName;
  path_num_ := db_GetPathCount(TempPathName);
  if path_num_ > 0 then
    begin
      for i := 1 to path_num_ do
        begin
          TempPathStr := db_GetFirstPath(TempPathName);
          TempPathName := db_DeleteFirstPath(TempPathName);

          if db_TestName(TempPathStr) = False then
            begin
              DB_.State := DB_PathNameError;
              Result := False;
              exit;
            end;
          if dbField_FindFirst(TempPathStr, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, fs) = False then
            begin
              DB_.State := fs.State;
              Result := False;
              exit;
            end;
          if dbField_ReadRec(fs.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
            begin
              DB_.State := f.State;
              Result := False;
              exit;
            end;
        end;
    end;
  DB_.CurrentFieldPOS := f.RHeader.CurrentHeader;
  DB_.CurrentFieldLevel := path_num_;
  DB_.State := DB_ok;
  Result := True;
end;

function db_GetRootField(const Name: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  Init_TField(Field_);
  Init_TField(f);

  if DB_.RootHeaderCount = 0 then
    begin
      DB_.State := DB_PathNameError;
      Field_.State := DB_.State;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Field_.State := DB_.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.State := DB_ok;
      Field_ := f;
      Result := True;
      exit;
    end;

  if DB_.RootHeaderCount = 1 then
    begin
      DB_.State := DB_PathNameError;
      Field_.State := DB_.State;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Field_.State := DB_.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.State := DB_ok;
      Field_ := f;
      Result := True;
      exit;
    end;

  while f.RHeader.CurrentHeader <> DB_.DefaultFieldPOS do
    begin
      if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
        begin
          DB_.State := f.RHeader.State;
          Field_.State := DB_.State;
          Result := False;
          exit;
        end;
      if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
        begin
          DB_.State := DB_ok;
          Field_ := f;
          Result := True;
          exit;
        end;
    end;
  DB_.State := DB_PathNameError;
  Field_.State := DB_.State;
  Result := False;
end;

function db_GetField(const pathName: U_String; var Field_: TField; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  fs: TFieldSearch;
  i, path_num_: Integer;
  TempPathStr, TempPathName: U_String;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if dbField_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;

  if umlGetLength(pathName) = 0 then
    begin
      Field_ := f;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;
  TempPathName := pathName;
  path_num_ := db_GetPathCount(TempPathName);

  if path_num_ > 0 then
    begin
      for i := 1 to path_num_ do
        begin
          TempPathStr := db_GetFirstPath(TempPathName);
          TempPathName := db_DeleteFirstPath(TempPathName);

          if db_TestName(TempPathStr) = False then
            begin
              DB_.State := DB_PathNameError;
              Result := False;
              exit;
            end;
          if dbField_FindFirst(TempPathStr, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, fs) = False then
            begin
              DB_.State := fs.State;
              Result := False;
              exit;
            end;
          if dbField_ReadRec(fs.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
            begin
              DB_.State := f.State;
              Result := False;
              exit;
            end;
        end;
    end;
  Field_ := f;
  DB_.State := DB_ok;
  Result := True;
end;

function db_GetPath(const FieldPos, RootFieldPos: Int64; var DB_: TObjectDataHandle; var RetPath: U_String): Boolean;
var
  f: TField;
begin
  if dbHeader_ReadRec(FieldPos, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;

  if f.RHeader.ID <> DB_Header_Field_ID then
    begin
      DB_.State := DB_Field_SetPosError;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(f.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;

  if f.RHeader.CurrentHeader = RootFieldPos then
    begin
      RetPath := DB_Path_Delimiter;
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;
  RetPath := f.RHeader.Name + DB_Path_Delimiter;

  while dbField_ReadRec(f.UpFieldPOS, DB_.IOHnd, f) do
    begin
      if f.RHeader.CurrentHeader = RootFieldPos then
        begin
          RetPath := DB_Path_Delimiter + RetPath;
          DB_.State := DB_ok;
          Result := True;
          exit;
        end;
      RetPath := f.RHeader.Name + DB_Path_Delimiter + RetPath;
    end;
  DB_.State := f.State;
  Result := False;
end;

function db_NewItem(const pathName, ItemName, ItemDescription: U_String; const ItemExtID: Byte; var Item_: TItem; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  fs: TFieldSearch;
  i, path_num_: Integer;
  TempPathStr, TempPathName: U_String;
begin
  if umlFileTest(DB_.IOHnd) = False then
    begin
      DB_.State := DB_ClosePackError;
      Result := False;
      exit;
    end;
  if dbField_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;

  if umlGetLength(pathName) > 0 then
    begin
      TempPathName := pathName;
      path_num_ := db_GetPathCount(TempPathName);
      if path_num_ > 0 then
        begin
          for i := 1 to path_num_ do
            begin
              TempPathStr := db_GetFirstPath(TempPathName);
              TempPathName := db_DeleteFirstPath(TempPathName);

              if db_TestName(TempPathStr) = False then
                begin
                  DB_.State := DB_PathNameError;
                  Result := False;
                  exit;
                end;
              case dbField_FindFirst(TempPathStr, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, fs) of
                False:
                  begin
                    f.Description := DB_FileDescription;
                    if dbField_CreateField(TempPathStr, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
                      begin
                        DB_.State := f.State;
                        Result := False;
                        exit;
                      end;
                  end;
                True:
                  begin
                    if dbField_ReadRec(fs.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
                      begin
                        DB_.State := f.State;
                        Result := False;
                        exit;
                      end;
                  end;
              end;
            end;
        end;
    end;

  if db_TestName(ItemName) = False then
    begin
      DB_.State := DB_ItemNameError;
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(ItemName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, fs) then
    begin
      if DB_.OverWriteItem = False then
        begin
          if DB_.AllowSameHeaderName = False then
            begin
              DB_.State := DB_RepeatCreateItemError;
              Result := False;
              exit;
            end;
        end
      else
        begin
          if dbField_DeleteHeader(fs.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
            begin
              DB_.State := f.State;
              Result := False;
              exit;
            end;
        end;
    end;
  Item_.Description := ItemDescription;
  if dbField_CreateItem(ItemName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, Item_) = False then
    begin
      DB_.State := Item_.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_DeleteItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(FilterName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirstItem(FilterName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
        begin
          DB_.State := f.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_DeleteItem2(const FieldPos: Int64; const Item_Name: U_String; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  TempSR: TFieldSearch;
  f: TField;
begin
  if dbField_ReadRec(FieldPos, DB_.IOHnd, f) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(Item_Name, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) = False then
    begin
      DB_.State := TempSR.State;
      Result := False;
      exit;
    end;
  if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  while dbField_FindFirstItem(Item_Name, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, TempSR) do
    begin
      if dbField_DeleteHeader(TempSR.RHeader.CurrentHeader, f.RHeader.CurrentHeader, DB_.IOHnd, f) = False then
        begin
          DB_.State := f.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_GetItem(const pathName, ItemName: U_String; const ItemExtID: Byte; var Item_: TItem; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  FieldSR__: TFieldSearch;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(ItemName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, FieldSR__) = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_ReadRec(FieldSR__.RHeader.CurrentHeader, DB_.IOHnd, Item_) = False then
    begin
      DB_.State := Item_.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemCreate(const pathName, ItemName, ItemDescription: U_String; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags then
    begin
      DB_.State := DB_RepeatCreateItemError;
      Result := False;
      exit;
    end;
  if db_NewItem(pathName, ItemName, ItemDescription, ItemExtID, ItemHnd_.Item, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_BlockInit(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Name := ItemName;
  ItemHnd_.Description := ItemDescription;
  ItemHnd_.CreateTime := ItemHnd_.Item.RHeader.CreateTime;
  ItemHnd_.ModificationTime := ItemHnd_.Item.RHeader.ModificationTime;
  ItemHnd_.ItemExtID := ItemExtID;
  ItemHnd_.OpenFlags := True;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemFastCreate(const ItemName, ItemDescription: U_String; const fPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_;
  var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags then
    begin
      DB_.State := DB_RepeatCreateItemError;
      Result := False;
      exit;
    end;
  if dbField_CreateItem(ItemName, ItemExtID, fPos, DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_BlockInit(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Name := ItemName;
  ItemHnd_.Description := ItemDescription;
  ItemHnd_.CreateTime := ItemHnd_.Item.RHeader.CreateTime;
  ItemHnd_.ModificationTime := ItemHnd_.Item.RHeader.ModificationTime;
  ItemHnd_.ItemExtID := ItemExtID;
  ItemHnd_.OpenFlags := True;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemFastInsertNew(const ItemName, ItemDescription: U_String; const FieldPos, InsertHeaderPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags then
    begin
      DB_.State := DB_RepeatCreateItemError;
      Result := False;
      exit;
    end;
  if dbField_InsertNewItem(ItemName, ItemExtID, FieldPos, InsertHeaderPos, DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_BlockInit(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Name := ItemName;
  ItemHnd_.Description := ItemDescription;
  ItemHnd_.CreateTime := ItemHnd_.Item.RHeader.CreateTime;
  ItemHnd_.ModificationTime := ItemHnd_.Item.RHeader.ModificationTime;
  ItemHnd_.ItemExtID := ItemExtID;
  ItemHnd_.OpenFlags := True;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemOpen(const pathName, ItemName: U_String; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags then
    begin
      DB_.State := DB_RepeatOpenItemError;
      Result := False;
      exit;
    end;
  if db_GetItem(pathName, ItemName, ItemExtID, ItemHnd_.Item, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbItem_BlockInit(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Name := ItemName;
  ItemHnd_.Description := ItemHnd_.Item.Description;
  ItemHnd_.CreateTime := ItemHnd_.Item.RHeader.CreateTime;
  ItemHnd_.ModificationTime := ItemHnd_.Item.RHeader.ModificationTime;
  ItemHnd_.ItemExtID := ItemExtID;
  ItemHnd_.OpenFlags := True;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemFastOpen(const fPos: Int64; const ItemExtID: Byte; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags then
    begin
      DB_.State := DB_RepeatOpenItemError;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(fPos, DB_.IOHnd, ItemHnd_.Item.RHeader) = False then
    begin
      DB_.State := ItemHnd_.Item.RHeader.State;
      Result := False;
      exit;
    end;
  if ItemHnd_.Item.RHeader.ID <> DB_Header_Item_ID then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_OnlyReadItemRec(ItemHnd_.Item.RHeader.DataPosition, DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  if ItemHnd_.Item.ExtID <> ItemExtID then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockInit(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Name := ItemHnd_.Item.RHeader.Name;
  ItemHnd_.Description := ItemHnd_.Item.Description;
  ItemHnd_.CreateTime := ItemHnd_.Item.RHeader.CreateTime;
  ItemHnd_.ModificationTime := ItemHnd_.Item.RHeader.ModificationTime;
  ItemHnd_.ItemExtID := ItemExtID;
  ItemHnd_.OpenFlags := True;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemUpdate(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_CloseItemError;
      Result := False;
      exit;
    end;
  if ItemHnd_.Item.DataModification then
    begin
      // fixed by qq600585,2018-12
      // Header has a certain chance of being changed by other item operation during the opening of item
      if dbHeader_ReadReservedRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item.RHeader) = False then
        begin
          DB_.State := ItemHnd_.Item.State;
          Result := False;
          exit;
        end;
      ItemHnd_.Item.RHeader.Name := ItemHnd_.Name;
      ItemHnd_.Item.RHeader.CreateTime := ItemHnd_.CreateTime;
      ItemHnd_.Item.RHeader.ModificationTime := ItemHnd_.ModificationTime;
      ItemHnd_.Item.Description := ItemHnd_.Description;
      ItemHnd_.Item.ExtID := ItemHnd_.ItemExtID;
      if dbItem_WriteRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item) = False then
        begin
          DB_.State := ItemHnd_.Item.State;
          Result := False;
          exit;
        end;
      ItemHnd_.Item.DataModification := False;
    end;
  Result := True;
end;

function db_ItemBodyReset(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_CloseItemError;
      Result := False;
      exit;
    end;

  // fixed by qq600585,2018-12
  // Header has a certain chance of being changed by other item operation during the opening of item
  if dbHeader_ReadReservedRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item.RHeader) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;

  ItemHnd_.Item.RHeader.Name := ItemHnd_.Name;
  ItemHnd_.Item.RHeader.CreateTime := ItemHnd_.CreateTime;
  ItemHnd_.Item.RHeader.ModificationTime := ItemHnd_.ModificationTime;
  ItemHnd_.Item.Description := ItemHnd_.Description;
  ItemHnd_.Item.ExtID := ItemHnd_.ItemExtID;

  ItemHnd_.Item.FirstBlockPOS := 0;
  ItemHnd_.Item.LastBlockPOS := 0;
  ItemHnd_.Item.Size := 0;
  ItemHnd_.Item.BlockCount := 0;

  if dbItem_WriteRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  ItemHnd_.Item.DataModification := False;

  Result := True;
end;

function db_ItemClose(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  Result := db_ItemUpdate(ItemHnd_, DB_);
  if Result then
      ItemHnd_.OpenFlags := False;
end;

function db_ItemReName(const FieldPos: Int64; const NewItemName, NewItemDescription: U_String; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
var
  SenderSearchHnd: TSearchItem_;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_CloseItemError;
      Result := False;
      exit;
    end;

  if NewItemName.Same(@ItemHnd_.Name) then
    begin
      DB_.State := DB_ItemNameError;
      Result := False;
      exit;
    end;

  if DB_.OverWriteItem then
    begin
      // easy remove
      db_DeleteItem2(FieldPos, NewItemName, ItemHnd_.ItemExtID, DB_);
    end;

  // fixed by qq600585,2018-12
  // Header has a certain chance of being changed by other item operation during the opening of item
  if dbHeader_ReadReservedRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item.RHeader) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;

  ItemHnd_.Name := NewItemName;
  ItemHnd_.Description := NewItemDescription;
  ItemHnd_.Item.RHeader.Name := ItemHnd_.Name;
  ItemHnd_.Item.Description := ItemHnd_.Description;
  if dbItem_WriteRec(ItemHnd_.Item.RHeader.CurrentHeader, DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemRead(const Size: Int64; var Buff_; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockReadData(DB_.IOHnd, ItemHnd_.Item, Buff_, Size) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemWrite(const Size: Int64; const Buff_; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockWriteData(DB_.IOHnd, ItemHnd_.Item, Buff_, Size) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemSeekPos(const fPos: Int64; var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockSeekPOS(DB_.IOHnd, ItemHnd_.Item, fPos) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemSeekStartPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockSeekStartPOS(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemSeekLastPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Boolean;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockSeekLastPOS(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ItemGetPos(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Int64;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := 0;
      exit;
    end;
  Result := dbItem_BlockGetPOS(DB_.IOHnd, ItemHnd_.Item);
end;

function db_ItemGetSize(var ItemHnd_: TItemHandle_; var DB_: TObjectDataHandle): Int64;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := 0;
      exit;
    end;
  Result := ItemHnd_.Item.Size;
end;

function db_AppendItemSize(var ItemHnd_: TItemHandle_; const Size: Int64; var DB_: TObjectDataHandle): Boolean;
var
  SwapBuffers: array [0 .. C_Buffer_Chunk_Size] of Byte;
  i: Int64;
begin
  if ItemHnd_.OpenFlags = False then
    begin
      DB_.State := DB_OpenItemError;
      Result := False;
      exit;
    end;
  if dbItem_BlockSeekLastPOS(DB_.IOHnd, ItemHnd_.Item) = False then
    begin
      DB_.State := ItemHnd_.Item.State;
      Result := False;
      exit;
    end;
  i := Size;
  while i >= C_Buffer_Chunk_Size do
    begin
      if dbItem_BlockWriteData(DB_.IOHnd, ItemHnd_.Item, SwapBuffers, C_Buffer_Chunk_Size) = False then
        begin
          DB_.State := ItemHnd_.Item.State;
          Result := False;
          exit;
        end;
      dec(i, C_Buffer_Chunk_Size);
    end;
  if i > 0 then
    begin
      if dbItem_BlockWriteData(DB_.IOHnd, ItemHnd_.Item, SwapBuffers, i) = False then
        begin
          DB_.State := ItemHnd_.Item.State;
          Result := False;
          exit;
        end;
    end;
  DB_.State := DB_ok;
  Result := True;
end;

function db_ExistsRootField(const Name: U_String; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if DB_.RootHeaderCount = 0 then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(DB_.DefaultFieldPOS, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;

  if DB_.RootHeaderCount = 1 then
    begin
      DB_.State := DB_PathNameError;
      Result := False;
      exit;
    end;
  if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
    begin
      DB_.State := f.RHeader.State;
      Result := False;
      exit;
    end;

  if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
    begin
      DB_.State := DB_ok;
      Result := True;
      exit;
    end;

  while f.RHeader.CurrentHeader <> DB_.DefaultFieldPOS do
    begin
      if dbHeader_ReadRec(f.RHeader.NextHeader, DB_.IOHnd, f.RHeader) = False then
        begin
          DB_.State := f.RHeader.State;
          Result := False;
          exit;
        end;
      if (dbMultipleMatch(Name, f.RHeader.Name) = True) and (f.RHeader.ID = DB_Header_Field_ID) then
        begin
          DB_.State := DB_ok;
          Result := True;
          exit;
        end;
    end;
  DB_.State := DB_PathNameError;
  Result := False;
end;

function db_FindFirstHeader(const pathName, FilterName: U_String; const ID: Byte; var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, ID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.ID := SenderSearch.FieldSearch.RHeader.ID;
  SenderSearch.CreateTime := SenderSearch.FieldSearch.RHeader.CreateTime;
  SenderSearch.ModificationTime := SenderSearch.FieldSearch.RHeader.ModificationTime;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindNextHeader(var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean;
begin
  if dbField_FindNext(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.ID := SenderSearch.FieldSearch.RHeader.ID;
  SenderSearch.CreateTime := SenderSearch.FieldSearch.RHeader.CreateTime;
  SenderSearch.ModificationTime := SenderSearch.FieldSearch.RHeader.ModificationTime;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindLastHeader(const pathName, FilterName: U_String; const ID: Byte; var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindLast(FilterName, ID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.ID := SenderSearch.FieldSearch.RHeader.ID;
  SenderSearch.CreateTime := SenderSearch.FieldSearch.RHeader.CreateTime;
  SenderSearch.ModificationTime := SenderSearch.FieldSearch.RHeader.ModificationTime;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindPrevHeader(var SenderSearch: TSearchHeader_; var DB_: TObjectDataHandle): Boolean;
begin
  if dbField_FindPrev(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.ID := SenderSearch.FieldSearch.RHeader.ID;
  SenderSearch.CreateTime := SenderSearch.FieldSearch.RHeader.CreateTime;
  SenderSearch.ModificationTime := SenderSearch.FieldSearch.RHeader.ModificationTime;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindFirstItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  itm: TItem;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirstItem(FilterName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindNextItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindNextItem(ItemExtID, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindLastItem(const pathName, FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
  itm: TItem;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindLastItem(FilterName, ItemExtID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindPrevItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindPrevItem(ItemExtID, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindFirstItem(const FieldPos: Int64; const FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindFirstItem(FilterName, ItemExtID, FieldPos, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindNextItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindNextItem(ItemExtID, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindLastItem(const FieldPos: Int64; const FilterName: U_String; const ItemExtID: Byte; var SenderSearch: TSearchItem_; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindLastItem(FilterName, ItemExtID, FieldPos, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindPrevItem(var SenderSearch: TSearchItem_; const ItemExtID: Byte; var DB_: TObjectDataHandle): Boolean;
var
  itm: TItem;
begin
  if dbField_FindPrevItem(ItemExtID, DB_.IOHnd, SenderSearch.FieldSearch, itm) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := itm.Description;
  SenderSearch.ExtID := itm.ExtID;
  SenderSearch.Size := itm.Size;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindFirstField(const pathName, FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindFirst(FilterName, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindNextField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindNext(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindLastField(const pathName, FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if db_GetField(pathName, f, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  if dbField_FindLast(FilterName, DB_Header_Field_ID, f.RHeader.CurrentHeader, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FindPrevField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindPrev(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindFirstField(const FieldPos: Int64; const FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindFirst(FilterName, DB_Header_Field_ID, FieldPos, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindNextField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindNext(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindLastField(const FieldPos: Int64; const FilterName: U_String; var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindLast(FilterName, DB_Header_Field_ID, FieldPos, DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_FastFindPrevField(var SenderSearch: TSearchField_; var DB_: TObjectDataHandle): Boolean;
var
  f: TField;
begin
  if dbField_FindPrev(DB_.IOHnd, SenderSearch.FieldSearch) = False then
    begin
      DB_.State := SenderSearch.FieldSearch.State;
      Result := False;
      exit;
    end;
  if dbField_OnlyReadFieldRec(SenderSearch.FieldSearch.RHeader.DataPosition, DB_.IOHnd, f) = False then
    begin
      DB_.State := f.State;
      Result := False;
      exit;
    end;
  SenderSearch.Name := SenderSearch.FieldSearch.RHeader.Name;
  SenderSearch.Description := f.Description;
  SenderSearch.HeaderCount := f.HeaderCount;
  SenderSearch.HeaderPOS := SenderSearch.FieldSearch.RHeader.CurrentHeader;
  SenderSearch.CompleteCount := SenderSearch.CompleteCount + 1;
  DB_.State := SenderSearch.FieldSearch.State;
  Result := True;
end;

function db_RecursionSearchFirst(const InitPath, FilterName: U_String; var SenderRecursionSearch: TRecursionSearch_; var DB_: TObjectDataHandle): Boolean;
begin
  if db_GetField(InitPath, SenderRecursionSearch.CurrentField, DB_) = False then
    begin
      Result := False;
      exit;
    end;
  SenderRecursionSearch.SearchBuffGo := 0;
  if dbField_FindFirst(FilterName, DB_Header_Item_ID, SenderRecursionSearch.CurrentField.RHeader.CurrentHeader, DB_.IOHnd,
    SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) = False then
    begin
      if dbField_FindFirst('*', DB_Header_Field_ID, SenderRecursionSearch.CurrentField.RHeader.CurrentHeader, DB_.IOHnd,
        SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) = False then
        begin
          DB_.State := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].State;
          Result := False;
          exit;
        end;
      if dbField_OnlyReadFieldRec(SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader.DataPosition, DB_.IOHnd, SenderRecursionSearch.CurrentField) = False
      then
        begin
          DB_.State := SenderRecursionSearch.CurrentField.State;
          Result := False;
          exit;
        end;
      SenderRecursionSearch.CurrentField.RHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
      SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.CurrentField.RHeader;
      SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo + 1;
    end
  else
      SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
  SenderRecursionSearch.InitPath := InitPath;
  SenderRecursionSearch.FilterName := FilterName;
  DB_.State := DB_ok;
  Result := True;
end;

function db_RecursionSearchNext(var SenderRecursionSearch: TRecursionSearch_; var DB_: TObjectDataHandle): Boolean;
begin
  case SenderRecursionSearch.ReturnHeader.ID of
    DB_Header_Field_ID:
      begin
        if dbField_FindFirst(SenderRecursionSearch.FilterName, DB_Header_Item_ID, SenderRecursionSearch.CurrentField.RHeader.CurrentHeader, DB_.IOHnd,
          SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) then
          begin
            SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
            DB_.State := DB_ok;
            Result := True;
            exit;
          end;
        if dbField_FindFirst('*', DB_Header_Field_ID, SenderRecursionSearch.CurrentField.RHeader.CurrentHeader, DB_.IOHnd,
          SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) then
          begin
            if dbField_OnlyReadFieldRec(SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader.DataPosition, DB_.IOHnd,
              SenderRecursionSearch.CurrentField) = False then
              begin
                DB_.State := SenderRecursionSearch.CurrentField.State;
                Result := False;
                exit;
              end;
            SenderRecursionSearch.CurrentField.RHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
            SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.CurrentField.RHeader;
            SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo + 1;
            DB_.State := DB_ok;
            Result := True;
            exit;
          end;

        if SenderRecursionSearch.SearchBuffGo = 0 then
          begin
            DB_.State := DB_RecursionSearchOver;
            Result := False;
            exit;
          end;
        SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo - 1;
        while dbField_FindNext(DB_.IOHnd, SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) = False do
          begin
            if SenderRecursionSearch.SearchBuffGo = 0 then
              begin
                DB_.State := DB_RecursionSearchOver;
                Result := False;
                exit;
              end;
            SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo - 1;
          end;

        if dbField_OnlyReadFieldRec(SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader.DataPosition, DB_.IOHnd, SenderRecursionSearch.CurrentField) = False then
          begin
            DB_.State := SenderRecursionSearch.CurrentField.State;
            Result := False;
            exit;
          end;
        SenderRecursionSearch.CurrentField.RHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
        SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.CurrentField.RHeader;
        SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo + 1;
        DB_.State := DB_ok;
        Result := True;
        exit;
      end;
    DB_Header_Item_ID:
      begin
        if dbField_FindNext(DB_.IOHnd, SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) then
          begin
            SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
            DB_.State := DB_ok;
            Result := True;
            exit;
          end;
        if dbField_FindFirst('*', DB_Header_Field_ID, SenderRecursionSearch.CurrentField.RHeader.CurrentHeader, DB_.IOHnd,
          SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) then
          begin
            if dbField_OnlyReadFieldRec(SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader.DataPosition, DB_.IOHnd,
              SenderRecursionSearch.CurrentField) = False then
              begin
                DB_.State := SenderRecursionSearch.CurrentField.State;
                Result := False;
                exit;
              end;
            SenderRecursionSearch.CurrentField.RHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
            SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.CurrentField.RHeader;
            SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo + 1;
            DB_.State := DB_ok;
            Result := True;
            exit;
          end;

        if SenderRecursionSearch.SearchBuffGo = 0 then
          begin
            DB_.State := DB_RecursionSearchOver;
            Result := False;
            exit;
          end;
        SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo - 1;
        while dbField_FindNext(DB_.IOHnd, SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo]) = False do
          begin
            if SenderRecursionSearch.SearchBuffGo = 0 then
              begin
                DB_.State := DB_RecursionSearchOver;
                Result := False;
                exit;
              end;
            SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo - 1;
          end;

        if dbField_OnlyReadFieldRec(SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader.DataPosition, DB_.IOHnd, SenderRecursionSearch.CurrentField) = False then
          begin
            DB_.State := SenderRecursionSearch.CurrentField.State;
            Result := False;
            exit;
          end;
        SenderRecursionSearch.CurrentField.RHeader := SenderRecursionSearch.SearchBuff[SenderRecursionSearch.SearchBuffGo].RHeader;
        SenderRecursionSearch.ReturnHeader := SenderRecursionSearch.CurrentField.RHeader;
        SenderRecursionSearch.SearchBuffGo := SenderRecursionSearch.SearchBuffGo + 1;
        DB_.State := DB_ok;
        Result := True;
        exit;
      end;
    else
      begin
        Result := False;
      end;
  end;
end;

initialization

ZDB_Header_Multiple_Char__ := '?';
ZDB_Header_Multiple_String__ := '*';
ZDB_Field_Separator__ := '/\';

end.
 
