{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit DebugLog;

interface

uses
  Windows,
  System.SysUtils,
  System.SyncObjs;

procedure Log(const Msg: string); overload;
procedure Log(const Msg: string; i: LongInt); overload;

implementation

var
  LogFileLock: TCriticalSection;

function LogFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    'AvroKeyboard_debug.log';
end;

procedure Log(const Msg: string);
var
  F: TextFile;
  Line: string;
begin
  {$IFDEF DebugLog}
  Line := Format('[%d.%03d T%d] %s',
    [GetTickCount div 1000, GetTickCount mod 1000,
     GetCurrentThreadId, Msg]);
  OutputDebugString(PChar(Line));
  LogFileLock.Enter;
  try
    AssignFile(F, LogFilePath);
    try
      if FileExists(LogFilePath) then
        Append(F)
      else
        Rewrite(F);
      WriteLn(F, Line);
    finally
      CloseFile(F);
    end;
  finally
    LogFileLock.Leave;
  end;
  {$ENDIF}
end;

procedure Log(const Msg: string; i: LongInt);
begin
  Log(Msg + IntToStr(i));
end;

initialization
  LogFileLock := TCriticalSection.Create;

finalization
  FreeAndNil(LogFileLock);

end.
