unit Z.API_HubTool_Export_Test;

{******************************************************************************
 *  API_HubTool_Export_Test - Unit test for the API Hub export layer.
 *
 *  This unit demonstrates the basic usage of the API Hub C export functions
 *  (API_HubTool_Export) without involving any network communication. It shows
 *  how to create an application context, register local APIs (both call and
 *  notify), and invoke them locally using API_Local_APP_Call and
 *  API_Local_APP_Notify.
 *
 *  The test is self-contained and does not require a running server or
 *  network. It is intended to verify that the C ABI functions work correctly
 *  and that callbacks are properly invoked with the expected data.
 *
 *  =========================================================================
 *  TEST FLOW
 *  =========================================================================
 *  1. Create an application handle named 'test'.
 *  2. Register a call API 'Test_Call' with a callback that echoes input and
 *     returns a fixed response.
 *  3. Register a notify API 'Test_Notify' with a callback that prints the input.
 *  4. Create input data handles for each API and write a small payload.
 *  5. Call API_Local_APP_Call to execute 'Test_Call' synchronously and
 *     display the result.
 *  6. Call API_Local_APP_Notify to send a notification to 'Test_Notify'.
 *  7. Free all handles and the application context.
 *
 *  =========================================================================
 *  EXPECTED OUTPUT (via DoStatus)
 *  =========================================================================
 *  - "call cdecl input buffer size:4"
 *  - "input buff: 01 02 03 04 ..."
 *  - "Test_Call Result: 01 02 03 04 05 06 07 08"
 *  - "notify cdecl input buffer size:4"
 *  - "input buff: 01 02 03 04 ..."
 *
 *  No network is used; all calls are local.
 ******************************************************************************}

{$DEFINE FPC_DELPHI_MODE}
{$I ..\pascal\zNetV2\source\Z.Define.inc}

interface

uses
  Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Status, Z.UnicodeMixedLib,
  Z.MemoryStream, Z.API_HubTool_Export;

{ Do_API_HubTool_Export_Test: Main entry point to execute the test. }
procedure Do_API_HubTool_Export_Test;

implementation

{ ----------------------------------------------------------------------------
  Callback: Do_Test_Call
  Implements the 'Test_Call' API. It reads the input buffer, logs its size
  and content, and writes a fixed response [1..8] to the output.
  Parameters:
    Trigger - User-supplied pointer (unused here).
    Input   - TDataHnd containing the input data.
    Output  - TDataHnd to write the result into.
  ---------------------------------------------------------------------------- }
procedure Do_Test_Call(Trigger: Pointer; Input: Pointer; Output: Pointer); cdecl;
var
  tmp: TBytes;
begin
  // Log the size of the incoming data.
  DoStatus('call cdecl input buffer size:%d', [API_GetSize(Input)]);

  // Log the raw data as a hex dump (first 80 bytes).
  DoStatus('input buff:', API_GetBuffer(Input), API_GetSize(Input), 80);

  // Prepare a fixed response: bytes 1 through 8.
  tmp := [1, 2, 3, 4, 5, 6, 7, 8];

  // Write the response into the output handle.
  API_WriteBuffer(Output, @tmp[0], length(tmp));
end;

{ ----------------------------------------------------------------------------
  Callback: Do_Test_Notify
  Implements the 'Test_Notify' API. It reads the input buffer and logs its
  size and content. No output is produced.
  ---------------------------------------------------------------------------- }
procedure Do_Test_Notify(Trigger: Pointer; Input: Pointer); cdecl;
var
  tmp: TBytes;
begin
  DoStatus('notify cdecl input buffer size:%d', [API_GetSize(Input)]);
  DoStatus('input buff:', API_GetBuffer(Input), API_GetSize(Input), 80);
end;

{ ----------------------------------------------------------------------------
  Do_API_HubTool_Export_Test: Main test procedure.
  Steps:
  1. Create an application handle for 'test'.
  2. Register 'Test_Call' and 'Test_Notify' with their callbacks.
  3. Prepare a small binary payload [1,2,3,4].
  4. Create an input handle for 'Test_Call', write the payload, and call it
     locally. Display the result.
  5. Create an input handle for 'Test_Notify', write the payload, and send
     the notification locally.
  6. Free all handles and the application.
  ---------------------------------------------------------------------------- }
procedure Do_API_HubTool_Export_Test;
var
  app_hnd: TAppHnd;
  tmp: TBytes;
  input_, output_: TDataHnd;
begin
  // 1. Create an application context with name 'test' and empty description.
  app_hnd := API_Create_APPHnd(PAnsiChar('test'), nil);

  // 2. Register the APIs.
  API_Reg_Call(app_hnd, PAnsiChar('Test_Call'), nil, nil, Do_Test_Call);
  API_Reg_Notify(app_hnd, PAnsiChar('Test_Notify'), nil, nil, Do_Test_Notify);

  // 3. Prepare a common payload: [1, 2, 3, 4]
  tmp := [1, 2, 3, 4];

  // ---- Test 'Test_Call' ----
  // Create a data handle for the call API.
  input_ := API_Create_DataHnd(PAnsiChar('Test_Call'));
  // Write the payload into the handle.
  API_WriteBuffer(input_, @tmp[0], length(tmp));

  // Execute the call locally (synchronous). The result is a new data handle.
  output_ := API_Local_APP_Call(app_hnd, input_);

  // Log the result (as hex dump).
  DoStatus('Test_Call Result:', API_GetBuffer(output_), API_GetSize(output_), 80);

  // Free both handles.
  API_Free_DataHnd(input_);
  API_Free_DataHnd(output_);

  // ---- Test 'Test_Notify' ----
  // Create a data handle for the notify API.
  input_ := API_Create_DataHnd(PAnsiChar('Test_Notify'));
  API_WriteBuffer(input_, @tmp[0], length(tmp));

  // Send the notification locally (synchronous, no result).
  API_Local_APP_Notify(app_hnd, input_);

  // Free the input handle.
  API_Free_DataHnd(input_);

  // 7. Free the application context and all registered APIs.
  API_Free_APPHnd(app_hnd);
end;

end.

