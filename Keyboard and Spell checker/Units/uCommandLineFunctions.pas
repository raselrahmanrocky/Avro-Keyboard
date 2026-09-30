{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

unit uCommandLineFunctions;

interface

uses

  SysUtils,
  strutils,
  forms,
  windows,
  Messages;

function HandleAllCommandLine: Boolean;
function CheckSkinInstallParam: Boolean;
function CheckLayoutInstallParam: Boolean;
function CheckEncoInstallParam: Boolean;
function CheckSendCommandParam: Boolean;

function SendCommand(cmd: string): Boolean;
{ DONE : More functions like change keyboard, change keyboard mode }

implementation

uses
  uCmdLineHelper,
  u_Admin,
  WindowsVersion,
  uFileFolderHandling,
  SkinLoader,
  KeyboardLayoutLoader,
  uAvroEncoImporter;

{ =============================================================================== }

function CheckSendCommandParam: Boolean;
begin
  result := False;
  if uCmdLineHelper.GetParamCount <= 0 then
    exit;

  if ParamPresent('toggle') then
  begin
    result := True;
    SendCommand('toggle');
  end;

  if ParamPresent('bn') then
  begin
    result := True;
    SendCommand('bn');
  end;

  if ParamPresent('sys') then
  begin
    result := True;
    SendCommand('sys');
  end;

  if ParamPresent('minimize') then
  begin
    result := True;
    SendCommand('minimize');
  end;

  if ParamPresent('restore') then
  begin
    result := True;
    SendCommand('restore');
  end;

end;

{ =============================================================================== }

{ FindWindow('TAvroMainForm1') demonstrably misses the main window on some
  systems (Win10 22H2: the window is a visible top-level owned window and
  EnumWindows reports it, yet FindWindow/FindWindowEx return NULL for the exact
  class name - from any process, the Delphi CLI included). Every command sent
  through SendCommand (toggle, minimize/restore, refresh_layout, refresh_enco)
  therefore died silently. EnumWindows finds it reliably, so it is the
  authoritative lookup; FindWindow stays only as the fast path. }
var
  GEnumFoundMainWnd: THandle;

function EnumFindMainWndProc(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var
  ClassName: array [0 .. 255] of Char;
begin
  result := True;
  if (GetClassName(Wnd, ClassName, Length(ClassName)) > 0) and (StrComp(ClassName, 'TAvroMainForm1') = 0) then
  begin
    GEnumFoundMainWnd := Wnd;
    result := False;
  end;
end;

function SendCommand(cmd: string): Boolean;
var
  copyDataStruct: TCopyDataStruct;
  receiverHandle: THandle;
begin
  result := False;
  copyDataStruct.dwData := 0; // 0=string
  // cbData is the marshaled byte count of the payload. PChar is UTF-16 since
  // Delphi 2009, so the ANSI-era "1 + Length" (chars incl. terminator) sent
  // only half the buffer; the OS copies exactly cbData bytes across processes
  // and the receiver read a truncated, non-terminated garbage string - the
  // command silently did nothing. Count bytes, not characters.
  copyDataStruct.cbData := (1 + Length(cmd)) * SizeOf(Char);
  copyDataStruct.lpData := PChar(cmd);

  receiverHandle := FindWindow(PChar('TAvroMainForm1'), nil);
  if receiverHandle = 0 then
  begin
    GEnumFoundMainWnd := 0;
    EnumWindows(@EnumFindMainWndProc, 0);
    receiverHandle := GEnumFoundMainWnd;
  end;
  if receiverHandle = 0 then
    exit;

  SendMessage(receiverHandle, WM_COPYDATA, 0, Integer(@copyDataStruct));
  result := True;
end;

{ =============================================================================== }

function HandleAllCommandLine: Boolean;
begin
  result := False;
  if CheckSkinInstallParam or CheckLayoutInstallParam or CheckEncoInstallParam or CheckSendCommandParam then
    result := True;
end;

{ =============================================================================== }

function CheckLayoutInstallParam: Boolean;
var
  i:                   Integer;
  FilePath, LayoutDir: string;
begin
  result := False;
  if uCmdLineHelper.GetParamCount <= 0 then
    exit;

  for i := 1 to uCmdLineHelper.GetParamCount do
  begin
    if FileExists(uCmdLineHelper.GetParamStr(i)) then
    begin
      if uppercase(ExtractFileExt(uCmdLineHelper.GetParamStr(i))) = '.AVROLAYOUT' then
      begin
        result := True;

        // Ignore already installed skins
        FilePath := ExtractFilePath(uCmdLineHelper.GetParamStr(i));
        LayoutDir := GetAvroDataDir + 'Keyboard Layouts\';

        if (uppercase(LayoutDir) <> uppercase(FilePath)) then
        begin
          InstallLayout(uCmdLineHelper.GetParamStr(i));
        end;

      end;
    end;
  end;

  // Refresh keyboard layout lists
  // If Result = True Then
  SendCommand('Refresh_Layout');

end;

{ =============================================================================== }

function CheckSkinInstallParam: Boolean;
var
  i:                 Integer;
  FilePath, SkinDir: string;
begin
  result := False;
  if uCmdLineHelper.GetParamCount <= 0 then
    exit;

  for i := 1 to uCmdLineHelper.GetParamCount do
  begin
    if FileExists(uCmdLineHelper.GetParamStr(i)) then
    begin
      if uppercase(ExtractFileExt(uCmdLineHelper.GetParamStr(i))) = '.AVROSKIN' then
      begin
        result := True;

        // Ignore already installed skins
        FilePath := ExtractFilePath(uCmdLineHelper.GetParamStr(i));
        SkinDir := GetAvroDataDir + 'Skin\';

        if (uppercase(SkinDir) <> uppercase(FilePath)) then
        begin
          InstallSkin(uCmdLineHelper.GetParamStr(i));
        end;

      end;
    end;
  end;

end;

{ =============================================================================== }

function CheckEncoInstallParam: Boolean;
var
  i:      Integer;
  ErrMsg: string;
begin
  result := False;
  if uCmdLineHelper.GetParamCount <= 0 then
    exit;

  for i := 1 to uCmdLineHelper.GetParamCount do
  begin
    if FileExists(uCmdLineHelper.GetParamStr(i)) then
    begin
      if uppercase(ExtractFileExt(uCmdLineHelper.GetParamStr(i))) = '.AVROENCO' then
      begin
        result := True;

        // ImportEncoFile: default-key containers import silently, password
        // protected ones prompt (ErrMsg stays empty when the user cancels).
        ErrMsg := '';
        ImportEncoFile(uCmdLineHelper.GetParamStr(i), ErrMsg);
        if ErrMsg <> '' then
          Application.MessageBox(PChar(ErrMsg), 'Avro Keyboard', MB_ICONERROR or MB_OK);
      end;
    end;
  end;

  // A running first instance must reload its active mapping; when no instance
  // is listening SendCommand silently does nothing and the next app start
  // picks the imported file up from disk anyway.
  if result then
    SendCommand('refresh_enco');

end;

{ =============================================================================== }

end.
