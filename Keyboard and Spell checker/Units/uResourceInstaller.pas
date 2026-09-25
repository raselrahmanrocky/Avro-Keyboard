{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit uResourceInstaller;

interface

uses
  Windows,
  SysUtils,
  Classes;

type
  { Called from the downloading worker thread - the caller marshals to the UI
    thread itself (TThread.Queue), exactly like the rest of the app's tasks. }
  TResourceProgressProc = reference to procedure(const AContentLength, AReadCount: Int64);

{ Folder a resource type installs into ('' for an unknown type).
  Fonts live in the per-user font store so no admin rights are ever needed. }
function ResourceTargetFolder(const AResourceType: string): string;

{ Full destination path a file name would land at. }
function ResourceTargetPath(const AResourceType, AFileName: string): string;

function IsResourceInstalled(const AResourceType, AFileName: string): Boolean;

{ Downloads AUrl to a temp file, verifies it against AExpectedSha256 (SHA-256,
  hex, case-insensitive; empty skips the check), then moves it into the target
  folder for its type and runs the post-install step (fonts register with the
  per-user font store; everything else is picked up by the existing folder
  watcher / list refreshes).

  AFileName is the repo-relative path from index.json - only its final
  component decides the on-disk name. }
function DownloadAndInstallResource(const AUrl, AFileName, AResourceType, AExpectedSha256: string;
  AOnProgress: TResourceProgressProc; out AError, ATargetPath: string): Boolean;

implementation

uses
  Winapi.Messages,
  System.Hash,
  System.IOUtils,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
  System.Win.Registry,
  uFileFolderHandling,
  u_VirtualFontInstall,
  clsRegistry_XMLSetting,
  DebugLog;

{ ---------------------------------------------------------------------------- }
{ Helpers                                                                      }
{ ---------------------------------------------------------------------------- }

function LastComponent(const AFileName: string): string;
begin
  // index.json uses forward slashes ('AnsiMapping/Ansi V1.AvroEnco'); normalize
  // before ExtractFileName so the Windows-only splitter sees a backslash.
  Result := ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
end;

function ResourceTargetFolder(const AResourceType: string): string;
begin
  if SameText(AResourceType, 'ansimapping') then
    Result := GetAvroDataDir + 'AnsiMapping\'
  else if SameText(AResourceType, 'layout') then
    Result := GetAvroDataDir + 'Keyboard Layouts\'
  else if SameText(AResourceType, 'skin') then
    Result := GetAvroDataDir + 'Skin\'
  else if SameText(AResourceType, 'doc') then
    Result := GetAvroDataDir + 'Docs\'
  else if SameText(AResourceType, 'font') then
    // Per-user font store: installing here needs no elevation, and Windows
    // picks registered HKCU fonts up for every app on next logon (plus the
    // WM_FONTCHANGE broadcast below makes them usable right away).
    Result := GetEnvironmentVariable('LOCALAPPDATA') + '\Microsoft\Windows\Fonts\'
  else
    Result := '';
end;

function ResourceTargetPath(const AResourceType, AFileName: string): string;
var
  Folder: string;
begin
  Result  := '';
  Folder  := ResourceTargetFolder(AResourceType);
  if (Folder = '') or (LastComponent(AFileName) = '') then
    Exit;
  Result := Folder + LastComponent(AFileName);
end;

function IsResourceInstalled(const AResourceType, AFileName: string): Boolean;
var
  Path: string;
begin
  Path   := ResourceTargetPath(AResourceType, AFileName);
  Result := (Path <> '') and FileExists(Path);
end;

function ComputeFileSha256(const APath: string): string;
var
  FS:     TFileStream;
  Hash:   THashSHA2;
  Buffer: TBytes;
  Read:   Integer;
begin
  Result := '';
  Hash   := THashSHA2.Create;
  FS     := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Buffer, 64 * 1024);
    repeat
      Read := FS.Read(Buffer[0], Length(Buffer));
      if Read > 0 then
        Hash.Update(Buffer, Read);
    until Read = 0;
    Result := LowerCase(Hash.HashAsString);
  finally
    FS.Free;
  end;
end;

{ TNetHTTPClient's TReceiveDataEvent is a method pointer, so an anonymous
  progress callback cannot be wired directly - this relay bridges the two. }
type
  TProgressRelay = class
    private
      FProc: TResourceProgressProc;
    public
      constructor Create(const AProc: TResourceProgressProc);
      procedure Handle(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
  end;

constructor TProgressRelay.Create(const AProc: TResourceProgressProc);
begin
  inherited Create;
  FProc := AProc;
end;

procedure TProgressRelay.Handle(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
begin
  if Assigned(FProc) then
    FProc(AContentLength, AReadCount);
end;

{ Registers a downloaded .ttf in the CURRENT USER's font store - no admin
  rights, no UAC. Mirrors what the per-user font install does on Windows 10+:
  file under %LOCALAPPDATA%\Microsoft\Windows\Fonts plus the HKCU
  ...\CurrentVersion\Fonts value. GetFontName extracts the real typeface name
  so the font shows up correctly in font pickers. }
procedure InstallDownloadedFont(const AFontPath: string);
var
  FontName: string;
  Reg:      TMyRegistry;
begin
  FontName := GetFontName(AFontPath);
  if FontName = '' then
    FontName := ChangeFileExt(ExtractFileName(AFontPath), '');

  Reg := TMyRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\Microsoft\Windows NT\CurrentVersion\Fonts', True) then
      Reg.WriteString(FontName + ' (TrueType)', AFontPath);
  finally
    Reg.Free;
  end;

  AddFontResource(PChar(AFontPath));
  // SendNotifyMessage, NOT SendMessage: a synchronous broadcast from this
  // worker thread waits for every top-level window on the system, and one
  // hung application would block the install forever (UI stays "Downloading"
  // with the buttons disabled). The notify variant posts and returns.
  SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
end;

{ ---------------------------------------------------------------------------- }
{ Download + install                                                          }
{ ---------------------------------------------------------------------------- }

function DownloadAndInstallResource(const AUrl, AFileName, AResourceType, AExpectedSha256: string;
  AOnProgress: TResourceProgressProc; out AError, ATargetPath: string): Boolean;
var
  Folder:     string;
  TargetPath: string;
  TempPath:   string;
  FileName:   string;
  Http:       TNetHTTPClient;
  Stream:     TFileStream;
  Relay:      TProgressRelay;
  Response:   IHTTPResponse;
  ActualHash: string;
begin
  Result      := False;
  AError      := '';
  ATargetPath := '';

  FileName := LastComponent(AFileName);
  if FileName = '' then
  begin
    AError := 'The catalog entry has no file name.';
    Exit;
  end;

  Folder := ResourceTargetFolder(AResourceType);
  if Folder = '' then
  begin
    AError := 'Unknown resource type: ' + AResourceType;
    Exit;
  end;

  TargetPath := Folder + FileName;
  TempPath   := TPath.Combine(TPath.GetTempPath, 'avrores_' + FileName);

  // Download to a temp file first: a half-finished transfer must never sit in
  // the live folder where the watcher / list refreshes could see it.
  Stream := nil;
  Http   := TNetHTTPClient.Create(nil);
  Relay  := TProgressRelay.Create(AOnProgress);
  try
    // A stale temp file from a crashed attempt must never block this run.
    DeleteFile(TempPath);
    try
      Stream := TFileStream.Create(TempPath, fmCreate);
      Http.UserAgent         := 'Avro Keyboard';
      Http.AllowCookies      := False;
      Http.ConnectionTimeout := 10000;
      Http.ResponseTimeout   := 60000;
      if Assigned(AOnProgress) then
        Http.OnReceiveData := Relay.Handle;

      Response := Http.Get(AUrl, Stream);
      if Response.StatusCode <> 200 then
      begin
        AError := 'Download failed (HTTP ' + IntToStr(Response.StatusCode) + ').';
        Exit;
      end;
    except
      // Nothing may escape into the caller's TTask: an unhandled exception
      // there would skip the queued completion and leave the UI stuck busy.
      on E: Exception do
      begin
        AError := 'Download failed: ' + E.Message;
        Exit;
      end;
    end;
  finally
    Http.Free;
    Stream.Free;
    Relay.Free;
  end;

  try
    // Checksum first - a truncated or tampered file never reaches the folder.
    if (AExpectedSha256 <> '') and FileExists(TempPath) then
    begin
      ActualHash := ComputeFileSha256(TempPath);
      if not SameText(ActualHash, AExpectedSha256) then
      begin
        AError := 'Downloaded file failed the SHA-256 check and was discarded.';
        DeleteFile(TempPath);
        Exit;
      end;
    end;

    if not FileExists(TempPath) then
    begin
      AError := 'Download produced no file.';
      Exit;
    end;

    ForceDirectories(Folder);
    if FileExists(TargetPath) then
      DeleteFile(TargetPath);
    if not MyCopyFile(TempPath, TargetPath, True) then
    begin
      AError := 'Could not write to ' + TargetPath;
      DeleteFile(TempPath);
      Exit;
    end;
    DeleteFile(TempPath);

    if SameText(AResourceType, 'font') then
      InstallDownloadedFont(TargetPath);

    ATargetPath := TargetPath;
    Result      := True;
    Log('Resource installed: ' + FileName + ' -> ' + TargetPath);
  except
    on E: Exception do
    begin
      AError := 'Install failed: ' + E.Message;
      DeleteFile(TempPath);
    end;
  end;
end;

end.
