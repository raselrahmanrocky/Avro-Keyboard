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

{
  DIAGNOSTIC SINK - touches no file, ever.

  Log() used to AssignFile / Append / Rewrite / WriteLn / CloseFile
  %TEMP%\AvroKeyboard_debug.log on EVERY call (measured at ~8.5 ms, and the
  keyboard hook called it from hot paths), and it left behind a file that
  recorded what the user typed. That disk I/O, the global lock that serialised
  it, and the file itself are all gone: the message now goes to the debugger
  via OutputDebugString, which is free when no debugger is attached.

  The DebugLog define in ProjectDefines.inc is the switch, and it is OFF now -
  with it off the body below compiles away entirely, so every Log() call in the
  project costs one empty call and only the string arguments are built. To see
  the lines live, uncomment that define and attach DebugView; no log file is
  produced either way.
}
procedure Log(const Msg: string); overload;
procedure Log(const Msg: string; i: LongInt); overload;

implementation

uses
  Winapi.Windows,
  System.SysUtils;

procedure Log(const Msg: string);
begin
  {$IFDEF DebugLog}
  OutputDebugString(PChar(Format('[%d.%03d T%d] %s', [GetTickCount div 1000, GetTickCount mod 1000, GetCurrentThreadId, Msg])));
  {$ENDIF}
end;

procedure Log(const Msg: string; i: LongInt);
begin
  Log(Msg + IntToStr(i));
end;

end.
