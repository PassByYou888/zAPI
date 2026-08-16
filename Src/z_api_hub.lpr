library z_api_hub;

{$I ..\pascal\zNetV2\source\Z.Define.inc}

uses
  {$IFDEF MSWINDOWS}
  mimalloc4p,
  {$ENDIF MSWINDOWS}
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Z.API_HubTool_Export;

// symbol export
exports
  API_Create_DataHnd,
  API_Free_DataHnd,
  API_GetBuffer,
  API_WriteBuffer,
  API_ReadBuffer,
  API_GetPos,
  API_SetPos,
  API_GetSize,
  API_SetSize,
  API_Create_APPHnd,
  API_Free_APPHnd,
  API_Reg_Call,
  API_Reg_Notify,
  API_UnReg,
  API_Local_APP_Call,
  API_Local_APP_Notify,
  API_Prepare_Service,
  API_Prepare_Client,
  API_Reset_Prepare,
  API_Prepare_Done,
  API_Exit_MainThread,
  API_Call,
  API_Notify,
  API_SetOption,
  API_shutdown;

initialization
finalization
end.


