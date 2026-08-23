library z_api_hub;

{$DEFINE FPC_DELPHI_MODE}
{$I ..\pascal\zNetV2\source\Z.Define.inc}

uses
  mimalloc4p,
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Z.API_HubTool_Export;

// ============================================================================
//  Exported symbols for the API Hub C ABI layer.
//  All functions are declared with cdecl calling convention.
//  See Z.API_HubTool_Export.pas for detailed documentation.
// ============================================================================
exports
  // Data handle operations
  API_Create_DataHnd,       // Creates a new data handle with an API name.
  API_Free_DataHnd,         // Frees a data handle and its internal buffer.
  API_GetBuffer,            // Returns a pointer to the raw data buffer.
  API_WriteBuffer,          // Writes binary data into the handle at current position.
  API_ReadBuffer,           // Reads binary data from the handle at current position.
  API_GetPos,               // Returns the current read/write position.
  API_SetPos,               // Sets the current read/write position.
  API_GetSize,              // Returns the total size of the data buffer.
  API_SetSize,              // Resizes the data buffer.

  // Application handle operations
  API_Create_APPHnd,        // Creates a new application context.
  API_Free_APPHnd,          // Destroys an application context and frees its APIs.

  // API registration
  API_Reg_Call,             // Registers a request-response (Call) API.
  API_Reg_Notify,           // Registers a one-way (Notify) API.
  API_UnReg,                // Unregisters a previously registered API.

  // Local execution
  API_Local_APP_Call,       // Executes a Call API locally within the app.
  API_Local_APP_Notify,     // Executes a Notify API locally within the app.

  // C4 network preparation and startup
  API_Prepare_Service,      // Prepares a C4 service (listener) for the hub.
  API_Prepare_Client,       // Prepares a C4 client (connector) for the hub.
  API_Reset_Prepare,        // Clears all prepared services and clients.
  API_Prepare_Done,         // Starts the C4 framework with all prepared endpoints.

  // Main thread control
  API_Exit_MainThread,      // Signals the simulated main thread to exit gracefully.

  // Remote API invocation
  API_Call,                 // Performs a synchronous remote call (blocks until result).
  API_Notify,               // Sends a one-way notification (does not wait for response).

  // Status and diagnostics
  API_Check_MainThread,     // Checks whether the simulated main thread is running.
  API_Check_App,            // Checks if an application is registered on the network.

  // Runtime configuration
  API_SetOption,            // Dynamically adjusts global runtime options.

  // Log message queue
  API_Get_Status_Num,       // Returns the number of pending log messages.
  API_Get_Status,           // Retrieves the next log message from the queue.
  API_Post_Status,          // Injects a custom log message into the queue.

  // Shutdown
  API_shutdown;             // Gracefully shuts down the entire API Hub framework.

begin
end.
