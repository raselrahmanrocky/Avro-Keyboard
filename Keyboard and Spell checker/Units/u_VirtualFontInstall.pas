{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit u_VirtualFontInstall;

interface

uses
  Windows,
  SysUtils,
  classes,
  Messages;

procedure InstallVirtualFont(FontFilePath: string);
procedure RemoveVirtualFont(FontFilePath: string);

{ Registers every .ttf in AFolder with GDI for this session and broadcasts
  WM_FONTCHANGE once. The portable edition calls it on startup for its own
  fonts\ folder (shipped set plus anything the Download Resources dialog
  placed there): that folder carries no registry entries, so each session
  re-activates the fonts without touching the registry. }
procedure RegisterFontFolder(const AFolder: string);

{ Releases every .ttf RegisterFontFolder added from AFolder and broadcasts
  WM_FONTCHANGE once. The portable edition calls it in ExitApp so the fonts\
  folder can be deleted after use: an AddFontResource that is never balanced
  keeps the file mapped by the font driver - the OS shows it as "open in
  System" and every delete/rename fails - until sign-out. }
procedure UnregisterFontFolder(const AFolder: string);

// Privately used
function GetTempDirectory: string;
function GetFontName(TTF_Path: string): string;
procedure CheckDeleteTempFile(fname: string);

implementation

uses
  clsRegistry_XMLSetting,
  DebugLog;

{ =============================================================================== }

function GetTempDirectory: string;
var
  tempFolder: array [0 .. MAX_PATH] of Char;
begin
  GetTempPath(MAX_PATH, @tempFolder);
  result := StrPas(tempFolder);
end;

{ =============================================================================== }

procedure CheckDeleteTempFile(fname: string);
begin
  if fileexists(fname) then
    DeleteFile(fname);

end;

{ =============================================================================== }

function GetFontName(TTF_Path: string): string;
var
  TempName, FontName, AInfo: string;
  S:                         TFileStream;
  APos:                      Integer;
begin
  result := '';
  FontName := '';
  TempName := GetTempDirectory + 'tmpfntavro.tmp';
  CheckDeleteTempFile(TempName);
  S := nil;

  { CreateScalableFontResource returns 0 when it cannot build the temporary
    .FON container (missing/corrupt TTF, unwritable temp folder). The old code
    ignored that result and then opened the file it had just failed to create,
    raising an exception - and in the portable edition this runs on every
    launch, so the failure landed in the middle of the startup sequence. }
  if not fileexists(TTF_Path) then
    Exit;
  if not CreateScalableFontResource(0, PChar(TempName), PChar(TTF_Path), nil) then
  begin
    CheckDeleteTempFile(TempName);
    Exit;
  end;

  try
    try
      S := TFileStream.Create(TempName, fmOpenRead or fmShareDenyWrite);
      if S.Size > 0 then
      begin
        // Copy resource to string
        SetLength(AInfo, S.Size);
        S.Read(AInfo[1], S.Size);
        // Find FONTRES:
        APos := Pos('FONTRES:', AInfo);
        // This is followed by the font typeface name (null terminated)
        if APos > 0 then
          FontName := PChar(@AInfo[APos + 8]);
      end;
    except
      on E: Exception do
        FontName := '';
    end;
  finally
    if S <> nil then
      S.Free;
    CheckDeleteTempFile(TempName);
  end;
  result := FontName;
end;

{ =============================================================================== }

procedure InstallVirtualFont(FontFilePath: string);
var
  PrevDefaultFixedFont, PrevDefaultPropFont, VirtualFontName: string;
  Reg:                                                        TMyRegistry;
begin
  { Called from the startup path of the portable edition, before the keyboard
    hook exists. It is cosmetic work (register a font for this session + point
    IE's script font at it), so nothing in here may abort or hang startup: the
    registry part is contained and the WM_FONTCHANGE broadcast is asynchronous
    (SendMessage to HWND_BROADCAST blocks this thread on every top-level window
    - including a hung one; RegisterFontFolder below was fixed the same way). }
  if not fileexists(FontFilePath) then
  begin
    StartupLog('InstallVirtualFont: font not found, skipped: ' + FontFilePath);
    Exit;
  end;

  Reg := nil;
  try
    try
      Reg := TMyRegistry.Create;
      { Reconcile first: a crashed previous run of this same folder can leave
        the file registered (mapping it undeletable), and RemoveFontResource
        at count 0 is a harmless no-op. }
      RemoveFontResource(PChar(FontFilePath));
      AddFontResource(PChar(FontFilePath));
      VirtualFontName := GetFontName(FontFilePath);

      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey('Software\Microsoft\Internet Explorer\International\Scripts\11', True) = True then
      begin
        PrevDefaultFixedFont := trim(Reg.ReadString('IEFixedFontName'));
        PrevDefaultPropFont := trim(Reg.ReadString('IEPropFontName'));

        if PrevDefaultFixedFont = '' then
          PrevDefaultFixedFont := 'none';
        if PrevDefaultPropFont = '' then
          PrevDefaultPropFont := 'none';

        if trim(Reg.ReadString('IEFixedFontName_Prev')) = '' then
          Reg.WriteString('IEFixedFontName_Prev', PrevDefaultFixedFont);

        if trim(Reg.ReadString('IEPropFontName_Prev')) = '' then
          Reg.WriteString('IEPropFontName_Prev', PrevDefaultPropFont);

        Reg.WriteString('IEFixedFontName', VirtualFontName);
        Reg.WriteString('IEPropFontName', VirtualFontName);

      end;
    except
      on E: Exception do
        StartupLogException('InstallVirtualFont', E);
    end;
  finally
    if Reg <> nil then
      Reg.Free;
    SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
  end;
end;

{ =============================================================================== }

procedure RemoveVirtualFont(FontFilePath: string);
var
  PrevDefaultFixedFont, PrevDefaultPropFont: string;
  Reg:                                       TMyRegistry;
begin
  Reg := nil;
  try
    try
      Reg := TMyRegistry.Create;
      RemoveFontResource(PChar(FontFilePath));

      Reg.RootKey := HKEY_CURRENT_USER;
      if Reg.OpenKey('Software\Microsoft\Internet Explorer\International\Scripts\11', True) = True then
      begin
        PrevDefaultFixedFont := trim(Reg.ReadString('IEFixedFontName_Prev'));
        PrevDefaultPropFont := trim(Reg.ReadString('IEPropFontName_Prev'));

        if PrevDefaultFixedFont = 'none' then
          PrevDefaultFixedFont := '';
        if PrevDefaultPropFont = 'none' then
          PrevDefaultPropFont := '';

        Reg.DeleteValue('IEFixedFontName_Prev');
        Reg.DeleteValue('IEPropFontName_Prev');

        Reg.WriteString('IEFixedFontName', PrevDefaultFixedFont);
        Reg.WriteString('IEPropFontName', PrevDefaultPropFont);

      end;
    except
      on E: Exception do
        StartupLogException('RemoveVirtualFont', E);
    end;
  finally
    if Reg <> nil then
      Reg.Free;
    SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
  end;
end;

procedure RegisterFontFolder(const AFolder: string);
var
  Sr:     TSearchRec;
  Folder: string;
  Added:  Boolean;
begin
  Folder := IncludeTrailingPathDelimiter(AFolder);
  if not DirectoryExists(Folder) then
    Exit;

  Added := False;
  if FindFirst(Folder + '*.ttf', faAnyFile, Sr) = 0 then
    try
      repeat
        if (Sr.Attr and faDirectory) = 0 then
        begin
          // Reconcile first (see InstallVirtualFont): clear a stale session
          // count from a crashed previous run before registering for this one.
          RemoveFontResource(PChar(Folder + Sr.Name));
          AddFontResource(PChar(Folder + Sr.Name));
          Added := True;
        end;
      until FindNext(Sr) <> 0;
    finally
      FindClose(Sr);
    end;

  if Added then
    // SendNotifyMessage, NOT SendMessage: broadcast must never block the
    // startup path on some hung top-level window.
    SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
end;

{ =============================================================================== }

procedure UnregisterFontFolder(const AFolder: string);
var
  Sr:      TSearchRec;
  Folder:  string;
  Removed: Boolean;
begin
  Folder := IncludeTrailingPathDelimiter(AFolder);
  if not DirectoryExists(Folder) then
    Exit;

  Removed := False;
  if FindFirst(Folder + '*.ttf', faAnyFile, Sr) = 0 then
    try
      repeat
        if (Sr.Attr and faDirectory) = 0 then
        begin
          RemoveFontResource(PChar(Folder + Sr.Name));
          Removed := True;
        end;
      until FindNext(Sr) <> 0;
    finally
      FindClose(Sr);
    end;

  if Removed then
    // SendNotifyMessage, NOT SendMessage: never block the exit path on some
    // hung top-level window - same rule as RegisterFontFolder.
    SendNotifyMessage(HWND_BROADCAST, WM_FONTCHANGE, 0, 0);
end;

end.
