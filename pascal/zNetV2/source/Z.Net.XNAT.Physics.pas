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
{ ******************************************************************************
  * XNAT Physics Layer
  * Defines the physical transport classes (TXPhysicsServer, TXPhysicsClient)
  * as aliases to Z.Net.PhysicsIO, and provides protocol command constants and
  * header‑packing helpers for XNAT’s custom binary protocol.
  *
  * This unit is the lowest‑level dependency of the XNAT stack.
  ****************************************************************************** }
unit Z.Net.XNAT.Physics;

{$DEFINE FPC_DELPHI_MODE}
{$I Z.Define.inc}

interface

uses Z.Core, Z.PascalStrings, Z.UPascalStrings, Z.Net.PhysicsIO;

type
  TXPhysicsServer = TPhysicsServer;
  TXPhysicsClient = TPhysicsClient;

  TXNAT_PHYSICS_MODEL = (XNAT_PHYSICS_SERVICE, XNAT_PHYSICS_CLIENT);

procedure Build_XNAT_Buff(buff: PByte; siz: NativeInt; local_id, remote_id: Cardinal; var NewSiz: NativeInt; var NewBuff: PByte);
procedure Extract_XNAT_Buff(sour: PByte; siz: NativeInt; var local_id, remote_id: Cardinal; var destSiz: NativeInt; var destBuff: PByte);

const
  C_RequestListen: SystemString = '__@RequestListen';
  C_Connect_request: SystemString = '__@connect_request';
  C_Disconnect_request: SystemString = '__@disconnect_request';
  C_Data: SystemString = '__@data';
  C_Connect_reponse: SystemString = '__@connect_reponse';
  C_Disconnect_reponse: SystemString = '__@disconnect_reponse';
  C_Workload: SystemString = '__@workload';
  C_IPV6Listen: SystemString = '__@IPv6Listen';

implementation

procedure Build_XNAT_Buff(buff: PByte; siz: NativeInt; local_id, remote_id: Cardinal; var NewSiz: NativeInt; var NewBuff: PByte);
var
  nb: PByte;
begin
  NewSiz := siz + 8;
  nb := System.GetMemory(NewSiz);
  NewBuff := nb;
  PCardinal(nb)^ := local_id;
  inc(nb, 4);
  PCardinal(nb)^ := remote_id;
  inc(nb, 4);
  CopyPtr(buff, nb, siz);
end;

procedure Extract_XNAT_Buff(sour: PByte; siz: NativeInt; var local_id, remote_id: Cardinal; var destSiz: NativeInt; var destBuff: PByte);
begin
  destSiz := siz - 8;
  local_id := PCardinal(sour)^;
  inc(sour, 4);
  remote_id := PCardinal(sour)^;
  inc(sour, 4);
  destBuff := sour;
end;

end.
 
