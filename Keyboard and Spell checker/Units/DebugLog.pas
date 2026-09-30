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
  System.SysUtils; // Exception, for StartupLogException

{
  DIAGNOSTIC SINK - Log() touches no file, ever.

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

{
  STARTUP LOG - the one deliberate exception to "no file, ever".

  When Avro refuses to start on a user's machine there is nothing to go on:
  DebugLog.Log compiles away, the tray balloon needs a tray that may not exist
  yet, and in top-bar mode a balloon is invisible anyway. So the startup
  sequence (and only the startup sequence) writes AvroStartup.log beside the
  data files: phases, paths, sizes, and exception class/message. Nothing a user
  types ever reaches it - the keyboard hook still calls Log() only.

  The file is capped (StartupLogMaxBytes): once it is bigger it rotates to
  AvroStartup.log.old, so the failing run is always the last one and the file
  cannot grow without bound. Every call is exception-proof by construction -
  a logger that raises would be worse than the fault it reports.

  If the data folder cannot be written to (a portable copy extracted into
  Program Files, a network share, a locked-down profile) the log falls back to
  %LOCALAPPDATA%\AvroKeyboard\ and then %TEMP%\AvroKeyboard\, and with nothing
  writable at all it is skipped silently - startup never depends on it.
}
const
  StartupLogFileName: string = 'AvroStartup.log';
  StartupLogMaxBytes: Int64  = 256 * 1024;

procedure StartupLog(const Msg: string); overload;
procedure StartupLog(const Section, Msg: string); overload;
procedure StartupLogSection(const Section: string);
{ Records the exception class AND its message. For the startup steps only:
  nothing has been typed yet, and the message is what makes a bug report
  actionable. }
procedure StartupLogException(const Section: string; E: Exception);
{ Same, but records the class only - for the runtime catch-all
  (Application.OnException), whose message can quote what the user was typing. }
procedure StartupLogExceptionClass(const Section: string; E: Exception);
function StartupLogPath: string;
{ 'Details were written to:' + the path actually in use, or a sentence saying
  no log could be written. Dialog text must never name a file that was not
  written. }
function StartupLogHint: string;
{ Environment snapshot: edition, exe/data paths, writability, database file,
  settings source. Only ever called once per run, from FormCreate. }
procedure StartupLogEnvironment;

implementation

uses
  Winapi.Windows,
  System.Classes, // TFileStream
  Vcl.Forms,
  uFileFolderHandling;

{ =============================================================================== }

procedure Log(const Msg: string);
begin
  {$IFDEF DebugLog}
  OutputDebugString(PChar(Format('[%d.%03d T%d] %s', [GetTickCount div 1000, GetTickCount mod 1000, GetCurrentThreadId, Msg])));
  {$ENDIF}
end;

{ =============================================================================== }

procedure Log(const Msg: string; i: LongInt);
begin
  Log(Msg + IntToStr(i));
end;

{ =============================================================================== }
{ STARTUP LOG }
{ =============================================================================== }

const
  { Fallback folder under LOCALAPPDATA / TEMP. }
  StartupLogFallbackDir = 'AvroKeyboard';

var
  { Resolved once per process: the first candidate this process can actually
    write to. Empty until resolved, and cleared again when a write to it fails
    so the next call walks the chain afresh. }
  CachedStartupLogPath:   string;
  StartupLogPathResolved: Boolean;

  { The candidates, in order: beside the data files, then - for a data folder the
    user cannot write to (a portable copy in Program Files, a network share, a
    locked-down profile) - LOCALAPPDATA and finally TEMP. A candidate whose base
    folder is unset is skipped; nothing is ever resolved relative to the current
    directory. }
function StartupLogCandidate(Index: Integer): string;
var
  Base: string;
begin
  Result := '';
  try
    case index of
      0:
        Result := GetAvroDataDir + StartupLogFileName;
      1:
        begin
          Base := GetEnvironmentVariable('LOCALAPPDATA');
          if Base <> '' then
            Result := IncludeTrailingPathDelimiter(Base) + StartupLogFallbackDir + PathDelim + StartupLogFileName;
        end;
      2:
        begin
          Base := GetEnvironmentVariable('TEMP');
          if Base <> '' then
            Result := IncludeTrailingPathDelimiter(Base) + StartupLogFallbackDir + PathDelim + StartupLogFileName;
        end;
    end;
  except
    Result := '';
  end;
end;

{ Creates the folder when needed and opens the file for append, creating it
  when it does not exist. fmCreate is used only for a file that is not there,
  so probing can never truncate a real log. }
function CanWriteStartupLog(const AName: string): Boolean;
var
  S:   TFileStream;
  Dir: string;
begin
  Result := False;
  if AName = '' then
    Exit;
  try
    Dir := ExtractFilePath(AName);
    if (Dir <> '') and (not DirectoryExists(Dir)) then
      ForceDirectories(Dir);
    if FileExists(AName) then
      S := TFileStream.Create(AName, fmOpenReadWrite or fmShareDenyNone)
    else
      S := TFileStream.Create(AName, fmCreate);
    try
      Result := True;
    finally
      S.Free;
    end;
  except
    { Not writable: try the next candidate. }
    Result := False;
  end;
end;

function ResolveStartupLogPath: string;
var
  i:         Integer;
  Candidate: string;
begin
  if StartupLogPathResolved then
    Exit(CachedStartupLogPath);

  Result := '';
  for i := 0 to 2 do
  begin
    Candidate := StartupLogCandidate(i);
    if CanWriteStartupLog(Candidate) then
    begin
      Result := Candidate;
      Break;
    end;
  end;

  CachedStartupLogPath := Result;
  StartupLogPathResolved := True;
end;

function StartupLogPath: string;
begin
  Result := ResolveStartupLogPath;
end;

function StartupLogHint: string;
begin
  Result := ResolveStartupLogPath;
  if Result = '' then
    Result := 'No startup log could be written - the Avro data folder is not writable.'
  else
    Result := 'Details were written to:' + sLineBreak + Result;
end;

{ =============================================================================== }

{ Size of an existing file, or False when it cannot be opened. }
function StartupFileSize(const AName: string; out ASize: Int64): Boolean;
var
  S: TFileStream;
begin
  Result := False;
  ASize := 0;
  try
    S := TFileStream.Create(AName, fmOpenRead or fmShareDenyNone);
    try
      ASize := S.Size;
      Result := True;
    finally
      S.Free;
    end;
  except
    { A file we cannot read is one we cannot rotate either. }
  end;
end;

{ =============================================================================== }

procedure RotateStartupLog(const AFileName: string);
var
  OldName: string;
  Size:    Int64;
begin
  if not FileExists(AFileName) then
    Exit;
  if not StartupFileSize(AFileName, Size) then
    Exit;
  if Size < StartupLogMaxBytes then
    Exit;
  OldName := AFileName + '.old';
  if FileExists(OldName) then
    System.SysUtils.DeleteFile(OldName);
  System.SysUtils.RenameFile(AFileName, OldName);
end;

{ =============================================================================== }

procedure StartupLog(const Section, Msg: string);
begin
  StartupLog(Section + ': ' + Msg);
end;

{ =============================================================================== }

{ One line, or False when the file could not be written at all. Never raises. }
function WriteStartupLogLine(const AName, Msg: string): Boolean;
var
  F: TextFile;
begin
  Result := False;
  if AName = '' then
    Exit;
  try
    RotateStartupLog(AName);
    AssignFile(F, AName);
    if FileExists(AName) then
      Append(F)
    else
      Rewrite(F);
    try
      Writeln(F, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), '  [pid ', GetCurrentProcessId, '] ', Msg);
      Result := True;
    finally
      CloseFile(F);
    end;
  except
    Result := False;
  end;
end;

procedure StartupLog(const Msg: string);
var
  Attempt: Integer;
begin
  for Attempt := 1 to 2 do
  begin
    if WriteStartupLogLine(ResolveStartupLogPath, Msg) then
      Exit;

    { The path that worked a moment ago can stop working (the folder was
      locked or removed, a drive went away). Forget it and let the next pass
      walk the chain again - the failure itself is still swallowed, because a
      logger that raises would be worse than the fault it reports. }
    StartupLogPathResolved := False;
    CachedStartupLogPath := '';
  end;
end;

{ =============================================================================== }

procedure StartupLogSection(const Section: string);
begin
  StartupLog('--- ' + Section + ' ---');
end;

{ =============================================================================== }

procedure StartupLogException(const Section: string; E: Exception);
begin
  if E = nil then
    StartupLog(Section + ': <nil exception>')
  else
    StartupLog(Section + ': EXCEPTION ' + E.ClassName + ': ' + E.Message);
end;

{ =============================================================================== }

procedure StartupLogExceptionClass(const Section: string; E: Exception);
begin
  if E = nil then
    StartupLog(Section + ': <nil exception>')
  else
    StartupLog(Section + ': EXCEPTION ' + E.ClassName + ' (message withheld: it can quote what the user typed)');
end;

{ =============================================================================== }

function DataDirWritable(const ADir: string): string;
var
  Probe: string;
  S:     TFileStream;
begin
  Probe := ADir + 'AvroWriteTest.tmp';
  try
    S := TFileStream.Create(Probe, fmCreate);
    S.Free;
    System.SysUtils.DeleteFile(Probe);
    Result := 'yes';
  except
    Result := 'NO';
  end;
end;

{ =============================================================================== }

function DataFileInfo(const APath: string): string;
var
  Size: Int64;
  Dt:   TDateTime;
begin
  if not FileExists(APath) then
    Exit('missing');
  if not StartupFileSize(APath, Size) then
    Exit('present, not readable');
  Result := IntToStr(Size) + ' bytes';
  try
    if FileAge(APath, Dt) then
      Result := Result + ', modified ' + FormatDateTime('yyyy-mm-dd hh:nn', Dt);
  except
  end;
end;

{ =============================================================================== }

procedure StartupLogEnvironment;
var
  DataDir: string;
begin
  DataDir := '';
  try
    DataDir := GetAvroDataDir;
  except
  end;

  try
    StartupLog('edition: ' + {$IFDEF PortableOn}'portable (data next to the exe)'{$ELSE}'installed (data in ProgramData, settings in HKCU)'{$ENDIF});
  except
  end;
  try
    StartupLog('exe: ' + Application.ExeName);
  except
  end;
  try
    StartupLog('data dir: ' + DataDir + ' (writable: ' + DataDirWritable(DataDir) + ')');
  except
  end;
  try
    StartupLog('database: ' + DataDir + 'Database.db3 -> ' + DataFileInfo(DataDir + 'Database.db3'));
  except
  end;
  try
    StartupLog('os: ' + TOSVersion.ToString);
  except
  end;
  try
    if StartupLogPath = '' then
      StartupLog('startup log: none - neither the data folder nor LOCALAPPDATA/TEMP is writable')
    else
      StartupLog('startup log: ' + StartupLogPath + ' (previous run: ' + DataFileInfo(StartupLogPath + '.old') + ')');
  except
  end;
end;

end.
