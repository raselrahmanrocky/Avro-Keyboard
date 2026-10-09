{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

program Avro_Spell_Checker;

uses
  Forms,
  Windows,
  clsMemoParser in 'clsMemoParser.pas',
  uClipboard in 'uClipboard.pas',
  ufrmSpell in 'ufrmSpell.pas' {frmSpell} ,
  BanglaChars in '..\Units\BanglaChars.pas',
  uFileFolderHandling in '..\Units\uFileFolderHandling.pas',
  KeyboardFunctions in '..\Units\KeyboardFunctions.pas',
  VirtualKeyCode in '..\Units\VirtualKeyCode.pas',
  uRegistrySettings in 'uRegistrySettings.pas',
  uWindowHandlers in '..\Units\uWindowHandlers.pas',
  clsFileVersion in '..\Classes\clsFileVersion.pas',
  clsRegistry_XMLSetting in 'clsRegistry_XMLSetting.pas',
  WindowsVersion in '..\Units\WindowsVersion.pas',
  WindowsDarkMode in '..\Units\WindowsDarkMode.pas',
  uThemeManager in '..\Units\uThemeManager.pas',
  Vcl.Themes,
  Vcl.Styles,
  DebugLog in '..\Units\DebugLog.pas';

{$R *.res}

var
  Mutex: THandle;
  Wnd:   HWND;

begin
  { Single instance: the keyboard's Spell checker hotkey and menu (and the
    Start Menu / desktop shortcuts) ShellExecute this exe on every trigger, so
    a second copy must never open a second window - it activates the running
    one and exits instead.  CreateMutex reports a pre-existing instance
    through ERROR_ALREADY_EXISTS; SetLastError(0) first (as in
    Avro_Keyboard.dpr) so the check does not read a stale last-error.  The
    handle is deliberately not released: the mutex only has to exist for as
    long as this process lives. }
  SetLastError(0);
  Mutex := CreateMutex(nil, True, 'Avro_Spell_Checker');
  if (Mutex <> 0) and (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    // No-op while the first instance has not created its window yet - it
    // will show up on its own as soon as it gets there.
    Wnd := FindWindow('TfrmSpell', nil);
    if Wnd <> 0 then
    begin
      if IsIconic(Wnd) then
        ShowWindow(Wnd, SW_RESTORE);
      uWindowHandlers.ForceForegroundWindow(Wnd);
    end;
    Application.Terminate;
    exit;
  end;

  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  uThemeManager.ApplyStoredAppTheme;
  Application.Title := 'Avro Spell Checker';
  Application.CreateForm(TfrmSpell, frmSpell);
  Application.Run;

end.
