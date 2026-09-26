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

{ Folder a resource type installs into ('' for an unknown type or an
  unresolvable environment).

  Everything except fonts resolves through GetAvroDataDir, which IS the
  edition switch: the portable build returns its own folder, the setup build
  returns %ProgramData%\Avro Keyboard. Fonts split per edition too - see
  ResourceTargetFolder. }
function ResourceTargetFolder(const AResourceType: string): string;

{ Full destination path a file name would land at. }
function ResourceTargetPath(const AResourceType, AFileName: string): string;

function IsResourceInstalled(const AResourceType, AFileName: string): Boolean;

{ Downloads AUrl to a temp file, verifies it against AExpectedSha256 (SHA-256,
  hex, case-insensitive; empty skips the check), then moves it into the target
  folder for its type and runs the post-install step (fonts register with the
  running session - the setup edition persists them in the per-user store;
  everything else is picked up by the existing folder watcher / list
  refreshes).

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

{ The per-user font store (%LOCALAPPDATA%\Microsoft\Windows\Fonts) - the
  setup edition's download target and, in both editions, the "installed"
  check for downloads made before targets became edition-aware. '' when the
  environment does not resolve - never a relative path. }
function PerUserFontFolder: string;
var
  Dir: string;
begin
  Result := '';
  Dir    := GetEnvironmentVariable('LOCALAPPDATA');
  if Dir <> '' then
    Result := IncludeTrailingPathDelimiter(Dir) + 'Microsoft\Windows\Fonts\';
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
  {$IFDEF PortableOn}
    // Portable keeps the whole install self-contained: fonts land in the
    // exe's fonts\ folder (the same one the zip ships) and uForm1 registers
    // that folder on every startup, so they survive a reboot and travel
    // with the folder.
    Result := GetAvroDataDir + 'fonts\'
  {$ELSE}
    // Setup edition: writing to {autofonts} (C:\Windows\Fonts) needs
    // elevation, so downloads go to the per-user store - no admin, no UAC.
    Result := PerUserFontFolder
  {$ENDIF}
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
  Path:     string;
  FileName: string;
  Windir:   string;
  Legacy:   string;
begin
  Result   := False;
  FileName := LastComponent(AFileName);
  if FileName = '' then
    Exit;

  // The download target of the running edition - correct answer on its own
  // for ansimapping/layout/skin/doc (GetAvroDataDir is the edition switch).
  Path   := ResourceTargetPath(AResourceType, AFileName);
  Result := (Path <> '') and FileExists(Path);
  if Result or not SameText(AResourceType, 'font') then
    Exit;

  // Fonts also count when they sit in a store the running edition (or
  // Windows) legitimately uses, so a shipped font never reads as missing
  // and downloads made before targets became edition-aware stay visible:
  //   setup:    C:\Windows\Fonts (installer) and the per-user store
  //   portable: exe's fonts\ (zip) and the old per-user store
  Windir := GetEnvironmentVariable('WINDIR');
  if (Windir <> '') and FileExists(IncludeTrailingPathDelimiter(Windir) + 'Fonts\' + FileName) then
    Exit(True);

  Legacy := PerUserFontFolder;
  if (Legacy <> '') and FileExists(Legacy + FileName) then
    Exit(True);

  Result := FileExists(GetAvroDataDir + 'fonts\' + FileName);
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

{ Activates a downloaded .ttf right away: AddFontResource + WM_FONTCHANGE.
  The setup edition additionally persists it in the CURRENT USER's font
  store (HKCU ...\Fonts) - file under %LOCALAPPDATA%\Microsoft\Windows\Fonts
  - so it survives logoff without needing admin rights. The portable edition
  deliberately skips that write: its file lives in the portable folder, a
  registry pointer would go stale the moment the folder moves, and uForm1
  re-registers exe's fonts\ on every startup instead. GetFontName extracts
  the real typeface name so the font shows up correctly in font pickers. }
procedure InstallDownloadedFont(const AFontPath: string);
{$IFNDEF PortableOn}
var
  FontName: string;
  Reg:      TMyRegistry;
{$ENDIF}
begin
  {$IFNDEF PortableOn}
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
  {$ENDIF}

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
    if SameText(AResourceType, 'font') then
      AError := 'Could not resolve the fonts folder (LOCALAPPDATA is not set).'
    else
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
