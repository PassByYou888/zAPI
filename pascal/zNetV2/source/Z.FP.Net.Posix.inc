{ *
  * Posix.inc – helper function for sending data on POSIX systems.
  * This function wraps the send() system call and handles partial sends,
  * EINTR, and EAGAIN gracefully. It also sets MSG_NOSIGNAL on Linux to
  * avoid SIGPIPE, while on macOS it uses the SO_NOSIGPIPE socket option
  * (set elsewhere). The function returns the total number of bytes sent,
  * or -1 on error.
  *
  * The loop continues until either all bytes are sent, or a non‑recoverable
  * error occurs, or the socket would block (returns partial count).
}
function PosixSend(ASocket: THandle; ABuf: Pointer; ALen: Integer): Integer;
var
  LBuf: PByte;
  LSent, LError: Integer;
  LFlags: Integer;
begin
  Result := 0;

  // Choose flags: on Linux/Android/FreeBSD we use MSG_NOSIGNAL to avoid SIGPIPE.
  // On macOS, SIGPIPE is suppressed by SO_NOSIGPIPE, so we use 0.
  {$IF defined(MACOS)}
  LFlags := 0;
  {$ELSE}
  LFlags := MSG_NOSIGNAL;
  {$ENDIF}

  LBuf := ABuf;
  while (Result < ALen) do
  begin
    LSent := TSocketAPI.Send(ASocket, LBuf^, ALen - Result, LFlags);

    if (LSent < 0) then
    begin
      LError := GetLastError;

      if (LError = EINTR) then
        Continue
      else if (LError = EAGAIN) or (LError = EWOULDBLOCK) then
        Break
      else
        Exit(-1);
    end;

    Inc(Result, LSent);
    Inc(LBuf, LSent);
  end;
end;
