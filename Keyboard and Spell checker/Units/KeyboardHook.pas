{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit KeyboardHook;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Dialogs,
  Graphics;

function Sethook(): Integer;
procedure Removehook();

{ True while this thread is inside the WH_KEYBOARD_LL callback.

  A low-level hook is always called on the thread that installed it, so a plain
  depth counter is exact. Anything that could raise a modal dialog - or simply
  take longer than LowLevelHooksTimeout (5000 ms, which this app sets) - must
  check this and defer itself with PostMessage: a hook callback that overruns
  is removed by Windows silently, and typing Bangla stops working with no error
  anywhere. See TAvroMainForm1.RefreshSettings, the one caller that can reach a
  dialog (the corrupt-database notice) from in here. }
function InHookContext: Boolean;

{ The one hook procedure Windows ever calls. It is a thin, total wrapper around
  LLHookBody below: nothing may escape a WH_KEYBOARD_LL callback, and the real
  body keeps its own goto-based structure untouched. }
function LowLevelKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;

type
  pKBDLLHOOKSTRUCT = ^TKBDLLHOOKSTRUCT;

  TKBDLLHOOKSTRUCT = record
    vkCode: Integer;
    scancode: Integer;
    flags: Integer;
    time: Integer;
    dwExtraInfo: Integer;
  end;

var
  { HHOOK, not Integer. On Win64 a hook handle is a pointer, and a truncated one
    makes UnhookWindowsHookEx fail - so Removehook would not actually remove
    anything, and every Removehook/Sethook pair (a layout switch, every window
    z-order change) would stack another live copy of this hook. }
  HookRetVal: HHOOK;

  { Nesting depth of LowLevelKeyboardProc on the hook's thread: >0 means "called
    from inside the hook callback". Not threadvar: the callback always runs on
    the thread that installed the hook. }
  HookContextDepth: Integer = 0;

const
  LLKHF_EXTENDED = $01;
  LLKHF_INJECTED = $10;

implementation

uses
  uForm1,
  KeyboardFunctions,
  VirtualKeycode,
  clsLayout,
  uRegistrySettings,
  uWindowHandlers,
  uKeyboardMacro,
  DebugLog,
  uPickerSupport;

{ =============================================================================== }

var
  IsHook: Boolean;

var
  // Manually tracked modifier key state (more reliable than GetAsyncKeyState inside WH_KEYBOARD_LL hook)
  TrackedCtrl:  Boolean = False;
  TrackedShift: Boolean = False;
  TrackedAlt:   Boolean = False;
  TrackedWin:   Boolean = False;

const
  // Unassigned VK code used to suppress Start Menu when a Win-based hotkey fires
  // (AutoHotkey-style MenuMaskKey technique)
  VK_MENU_MASK = $E8;

  { =============================================================================== }

function Sethook(): Integer;
var
  WH_KEYBOARD_LL: Integer;
begin
  try
    if IsHook = True then
      Removehook;

    WH_KEYBOARD_LL := 13;
    HookRetVal := SetWindowsHookEx(WH_KEYBOARD_LL, @LowLevelKeyboardProc, hInstance, 0);
    if HookRetVal <> 0 then
    begin
      { Every caller only tests "> 0". A hook handle is a pointer and must not
        travel through an Integer. }
      Result := 1;
      IsHook := True;
    end
    else
    begin
      Result := 0;
      IsHook := False;
    end;
  except
    on e: exception do
    begin
      // A ghost range check error is coming
      IsHook := False;
      Result := 0;
    end;
  end;
end;

{ =============================================================================== }

procedure Removehook();
begin
  { Idempotent, and safe when nothing was ever installed: Sethook calls it
    before every install, and so do a layout switch and each window z-order
    change. }
  if HookRetVal <> 0 then
    UnhookWindowsHookEx(HookRetVal);
  HookRetVal := 0;
  IsHook := False;
end;

{ =============================================================================== }

// Returns True when the given hotkey setting uses the Win modifier
function SettingUsesWinModifier(const Setting: string): Boolean;
begin
  Result := (HotkeyStringToModifiers(Setting) and MOD_WIN) <> 0;
end;

{ =============================================================================== }

// Shift overrides NumLock on the numeric keypad: Shift+Num7 is reported as the
// navigation key VK_HOME.  To do that, Windows synthesizes a Shift key-up
// immediately before the key and puts Shift back with a Shift key-down after
// it.  Both events reach a low-level hook like real ones; the synthetic ones
// carry a scan code above $FF (e.g. $22A for left Shift).  If that synthetic
// release cleared TrackedShift, "Shift + Num 7" would be recorded (and matched)
// as "Num 7" - exactly the combination this hook has to support - so only a
// real release may clear the tracker.
function IsSyntheticModifierEvent(const Kbd: pKBDLLHOOKSTRUCT): Boolean;
begin
  Result := (Kbd.scancode and $FF00) <> 0;
end;

{ =============================================================================== }

// Build the current modifier mask from the manual tracker plus the hardware
// state.  The OR keeps a missed keydown from losing a modifier, while the
// tracker keeps a modifier that GetAsyncKeyState has not caught up with yet.
// Do not clear the tracker from GetAsyncKeyState here: inside a low-level hook
// the async state can lag the event that just set the tracker, and clearing it
// would make fast Shift+Numpad combinations fail.
function CurrentModifierMask: Byte;
var
  RealCtrl, RealShift, RealAlt, RealWin: Boolean;
begin
  RealCtrl := (GetAsyncKeyState(VK_CONTROL) and $8000) <> 0;
  RealShift := (GetAsyncKeyState(VK_SHIFT) and $8000) <> 0;
  RealAlt := (GetAsyncKeyState(VK_MENU) and $8000) <> 0;
  RealWin := ((GetAsyncKeyState(VK_LWIN) and $8000) <> 0) or ((GetAsyncKeyState(VK_RWIN) and $8000) <> 0);

  Result := 0;
  if TrackedCtrl or RealCtrl then
    Result := Result or MOD_CTRL;
  if TrackedShift or RealShift then
    Result := Result or MOD_SHIFT;
  if TrackedAlt or RealAlt then
    Result := Result or MOD_ALT;
  if TrackedWin or RealWin then
    Result := Result or MOD_WIN;
end;

{ =============================================================================== }

// Matches a hotkey setting using the tracked/hardware modifier mask.
function MatchesHotkeySettingTracked(const Setting: string; vkCode: Integer): Boolean;
begin
  Result := False;
  if (Setting = '') or (Setting = 'NONE') then
    Exit;

  Result := HotkeySettingMatchesVk(Setting, vkCode, CurrentModifierMask);
end;

{ =============================================================================== }

type
  THotkeyAction = (haNone, haModeSwitch, haOutputMode, haSpeller, haConverter, haAnsiVersion, haLayoutSwitch);

function MatchConfiguredHotkey(AKey: Integer): THotkeyAction;
begin
  if MatchesHotkeySettingTracked(ModeSwitchKey, AKey) then
    Exit(haModeSwitch);
  if MatchesHotkeySettingTracked(ToggleOutputModeKey, AKey) then
    Exit(haOutputMode);
  if MatchesHotkeySettingTracked(SpellerLauncherKey, AKey) then
    Exit(haSpeller);
  if MatchesHotkeySettingTracked(ConverterLauncherKey, AKey) then
    Exit(haConverter);
  if MatchesHotkeySettingTracked(AnsiVersionSwitchKey, AKey) then
    Exit(haAnsiVersion);
  if MatchesHotkeySettingTracked(LayoutSwitchKey, AKey) then
    Exit(haLayoutSwitch);
  Result := haNone;
end;

function ConfiguredHotkeySetting(Action: THotkeyAction): string;
begin
  case Action of
    haModeSwitch: Result := ModeSwitchKey;
    haOutputMode: Result := ToggleOutputModeKey;
    haSpeller: Result := SpellerLauncherKey;
    haConverter: Result := ConverterLauncherKey;
    haAnsiVersion: Result := AnsiVersionSwitchKey;
    haLayoutSwitch: Result := LayoutSwitchKey;
  else
    Result := '';
  end;
end;

procedure ExecuteConfiguredHotkey(Action: THotkeyAction);
begin
  case Action of
    haModeSwitch:
      AvroMainForm1.ToggleMode;
    haOutputMode:
      AvroMainForm1.ToggleOutputEncoding;
    haSpeller:
      AvroMainForm1.Spellcheck1Click(nil);
    haConverter:
      PostMessage(AvroMainForm1.Handle, WM_APP + 7, 0, 0);
    haAnsiVersion:
      PostMessage(AvroMainForm1.Handle, WM_APP + 1, 0, 0);
    haLayoutSwitch:
      PostMessage(AvroMainForm1.Handle, WM_APP + 3, 0, 0);
  end;

  if SettingUsesWinModifier(ConfiguredHotkeySetting(Action)) then
  begin
    SendInput_Down(VK_MENU_MASK);
    SendInput_UP(VK_MENU_MASK);
  end;
end;

{ =============================================================================== }

function LLHookBody(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;
var
  kbdllhs:         pKBDLLHOOKSTRUCT;
  ShouldBlock:     Boolean;
  T:               string;
  ShortcutText:    string;
  IsModifier:      Boolean;
  PickerOpen:      Boolean;
  CommandModifier: Boolean;
  HotkeyVk:        Integer;
  HadModifier:     Boolean;
  Action:          THotkeyAction;
label
  ExitHere;

begin

  ShouldBlock := False;
  T := '';

  kbdllhs := Ptr(lParam);

  if nCode = HC_ACTION then
  begin

    {$REGION 'Error fixes'}
    // ----------------------------------------------
    // Ignore injected keys
    // ----------------------------------------------
    if kbdllhs.flags and LLKHF_INJECTED <> 0 then
    begin
      Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    // ----------------------------------------------
    // Don't Process VK_Packet
    // ----------------------------------------------
    if kbdllhs.vkCode = VK_PACKET then
    begin
      Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    // ----------------------------------------------
    // The main form owns every path below: the layout engine, the hotkeys and
    // both popups. FormClose nils it before the form is freed, so a key that
    // arrives in that window must pass straight through rather than touch a
    // freed form - or a layout engine that was just freed with it.
    // ----------------------------------------------
    if not Assigned(AvroMainForm1) then
      goto ExitHere;

    // ----------------------------------------------
    // Track modifier key state manually (reliable even when hook blocks key events)
    // ----------------------------------------------
    { State before this event: used to tell a real modifier press that starts a
      new combination from the synthetic Shift restore Windows sends around a
      numpad key. }
    HadModifier := TrackedCtrl or TrackedShift or TrackedAlt or TrackedWin;

    if (wParam = 256) or (wParam = 260) then // KeyDown
    begin
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then
        TrackedCtrl := True
      else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then
        TrackedShift := True
      else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then
        TrackedAlt := True
      else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
        TrackedWin := True;
    end
    else if (wParam = 257) or (wParam = 261) then // KeyUp
    begin
      { Shift overriding NumLock produces a synthetic Shift release (see
        IsSyntheticModifierEvent); it is not the user letting go of Shift. }
      if not IsSyntheticModifierEvent(kbdllhs) then
      begin
        if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then
          TrackedCtrl := False
        else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then
          TrackedShift := False
        else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then
          TrackedAlt := False
        else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
          TrackedWin := False;
      end;
    end;

    // Numpad keys are recorded as "Num 7", but with NumLock off Windows reports
    // them as their navigation VK (VK_END, VK_NEXT, ...).  Normalize only for
    // hotkey capture/matching; the layout engine keeps the VK it already gets.
    HotkeyVk := NormalizeHotkeyVk(kbdllhs.vkCode, kbdllhs.scancode,
      (kbdllhs.flags and LLKHF_EXTENDED) <> 0);

    // Hotkey capture
    //
    // The Options dialog shows a THotKey per global hotkey, but a THotKey can
    // not be the recorder: the Win32 hot-key control knows only Ctrl/Shift/Alt
    // and refuses Enter/Tab/Space/Del/Esc/Backspace, while Avro has to record
    // any key - the Windows key included - and this hook already sees them all.
    // So the hook still owns capture and reproduces the THotKey choreography:
    //
    //   * every key-down starts a fresh combination.  A modifier key-down
    //     drops the previous value and previews the held modifiers
    //     ("Ctrl + Alt + "), exactly like the native control;
    //   * a main key-down completes the combination and commits it at once,
    //     so it is already set while the keys are held and survives their
    //     release;
    //   * releasing all modifiers without a main key ends on "None" - no
    //     combination was formed;
    //   * Esc alone restores the value from before the field was focused,
    //     Backspace/Delete alone clear it.
    //
    // Every key of the session is swallowed: nothing lands in the dialog
    // behind the field, and the Start menu never opens on Win.
    // ----------------------------------------------
    if HotkeyCaptureActive and ((wParam = 256) or (wParam = 257) or (wParam = 260) or (wParam = 261)) then
    begin
      IsModifier := HotkeyVk in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN];

      // Live modifier text, built from the state the tracking block just updated
      ShortcutText := '';
      if TrackedCtrl then
        ShortcutText := ShortcutText + 'Ctrl + ';
      if TrackedShift then
        ShortcutText := ShortcutText + 'Shift + ';
      if TrackedAlt then
        ShortcutText := ShortcutText + 'Alt + ';
      if TrackedWin then
        ShortcutText := ShortcutText + 'Win + ';

      if ((wParam = 256) or (wParam = 260)) and IsModifier then
      begin
        { A modifier starts a new combination: the old value is replaced by
          the pressed modifiers, and releasing without a main key gives None.
          The exception is the synthetic Shift restore Windows sends right
          after a numpad key (Shift overrides NumLock): the numpad key has
          already committed, and the restore must not replace that value with
          a bare "Shift + ". }
        if not (HotkeyCaptureCommitted and HadModifier) then
        begin
          HotkeyCaptureCommitted := False;
          if Assigned(HotkeyCapturePreview) then
            HotkeyCapturePreview(ShortcutText);
        end;
      end
      else if ((wParam = 257) or (wParam = 261)) and IsModifier then
      begin
        // After a completed combination the stored hotkey stays painted while
        // the modifiers are released; only an unfinished one changes.
        if not HotkeyCaptureCommitted then
        begin
          if ShortcutText = '' then
          begin
            if Assigned(HotkeyCaptureCommit) then
              HotkeyCaptureCommit('None');
          end;
          if Assigned(HotkeyCapturePreview) then
            HotkeyCapturePreview(ShortcutText);
        end;
      end
      else if ((wParam = 256) or (wParam = 260)) and (not IsModifier) then
      begin
        if (ShortcutText = '') and (HotkeyVk = VK_ESCAPE) then
          // Esc alone: give up and restore the value from before the capture
          ShortcutText := ''
        else if (ShortcutText = '') and ((HotkeyVk = VK_BACK) or (HotkeyVk = VK_DELETE)) then
          ShortcutText := 'None'
        else if (ShortcutText = '') and (not IsBareHotkeyKey(HotkeyVk)) then
          // No modifier and not a key that may stand alone: no combination
          ShortcutText := 'None'
        else
          ShortcutText := ShortcutText + VirtualKeyToStr(HotkeyVk);

        if Assigned(HotkeyCaptureCommit) then
          HotkeyCaptureCommit(ShortcutText);
        HotkeyCaptureCommitted := True;
      end;

      // Modifier down/up, main key up and refused keys all end here.
      Result := 1;
      Exit;
    end;

    // ----------------------------------------------
    // Vista Error Fix: Ghost 144 (Dec) key is coming
    // ----------------------------------------------
    if kbdllhs.vkCode = 144 then
    begin
      Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    {$ENDREGION}

    // Configured global hotkeys must be checked before the layout engine and the
    // picker.  A layout engine can consume an arrow/numpad key (or a picker can
    // route it), which used to make a hotkey such as Shift+Up or Ctrl+Shift+Num3
    // never reach the hotkey code below.
    if ((wParam = 256) or (wParam = 260)) then
    begin // KeyDown
      Action := MatchConfiguredHotkey(HotkeyVk);
      if Action <> haNone then
      begin
        ExecuteConfiguredHotkey(Action);
        ShouldBlock := True;
        goto ExitHere;
      end;

      if UnicodeToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (HotkeyVk = Ord('V')) then
        begin
          AvroMainForm1.SetBengaliUnicodeMode;
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      if ANSIToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (HotkeyVk = Ord('B')) then
        begin
          PostMessage(AvroMainForm1.Handle, WM_APP + 12, 0, 0);
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;

      T := '';
      if MatchUserHotkeyWithMods(HotkeyVk, CurrentModifierMask, T) then
      begin
        SendKey_Char(T);
        if TrackedWin then
        begin
          SendInput_Down(VK_MENU_MASK);
          SendInput_UP(VK_MENU_MASK);
        end;
        ShouldBlock := True;
        goto ExitHere;
      end;
    end
    else if ((wParam = 257) or (wParam = 261)) then
    begin // KeyUp
      if MatchConfiguredHotkey(HotkeyVk) <> haNone then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;

      if UnicodeToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (HotkeyVk = Ord('V')) then
        begin
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      if ANSIToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (HotkeyVk = Ord('B')) then
        begin
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;

      T := '';
      if MatchUserHotkeyWithMods(HotkeyVk, CurrentModifierMask, T) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
    end;

    {$REGION 'Keyboard layout management'}
    // A visible picker owns the keyboard: it is the only surface the user is
    // meant to be typing into, so neither the Bangla engine nor the application
    // underneath may see the keys that are pressed while it is up.
    //
    // IsPickerOpen covers BOTH popups and goes False the instant one starts
    // closing - before any modal dialog its own apply path raises (a mapping
    // password, a layout-load failure) - so those dialogs still get their keys.
    PickerOpen := AvroMainForm1.IsPickerOpen;

    if not PickerOpen then
    begin
      if (wParam = 257) or (wParam = 261) then
      begin // Key Up
        AvroMainForm1.TransferKeyUp(kbdllhs.vkCode, ShouldBlock);
        if ShouldBlock = True then
          goto ExitHere;
      end
      else if (wParam = 256) or (wParam = 260) then
      begin // KeyDown
        T := AvroMainForm1.TransferKeyDown(kbdllhs.vkCode, ShouldBlock);
        if T <> '' then
          SendKey_Char(T);
        if ShouldBlock = True then
          goto ExitHere;
      end;
    end
    else
    begin
      { The picker has no Win32 focus on the machines this exists for, so the
        key is swallowed here and handed to it by PostMessage instead. Blocking
        the physical key is also what guarantees a key is never handled twice:
        the popup can not receive it through the window manager as well.

        Keys pressed with Ctrl/Alt/Win are deliberately left alone - they are
        application shortcuts or configured hotkeys, which are handled before
        this region, and that is what keeps the very hotkey that opened the
        popup working as the toggle that closes it. Shift is allowed, so `B`
        and `b` both reach the first-letter shortcut. }
      CommandModifier := TrackedCtrl or TrackedAlt or TrackedWin or ((GetAsyncKeyState(VK_CONTROL) and $8000) <> 0) or
        ((GetAsyncKeyState(VK_MENU) and $8000) <> 0) or ((GetAsyncKeyState(VK_LWIN) and $8000) <> 0) or ((GetAsyncKeyState(VK_RWIN) and $8000) <> 0);

      if (not CommandModifier) and IsPickerNavigableKey(kbdllhs.vkCode) then
      begin
        if (wParam = 256) or (wParam = 260) then
        begin // KeyDown
          if AvroMainForm1.RouteKeyToPicker(kbdllhs.vkCode) then
          begin
            ShouldBlock := True;
            goto ExitHere;
          end;
        end
        else if (wParam = 257) or (wParam = 261) then
        begin // KeyUp for a KeyDown that was swallowed above
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
    end;

    {$ENDREGION}
  end; { nCode = HC_ACTION }

ExitHere:
  if ShouldBlock = True then
    Result := 1
  else
  begin
    Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
  end;

end;

{ =============================================================================== }

{ The exported hook procedure, and the only function Windows ever calls into.

  Nothing may escape a WH_KEYBOARD_LL callback. It runs on the message-loop
  thread for every keystroke on the machine, so an exception raised here is
  raised inside GetMessage/DispatchMessage - and inside the modal loops of the
  popups' own prompts - which on some Windows builds ends the process with no
  dialog and no tray icon. So: swallow it, note the class and message (never the
  key that was pressed), and let the key through untouched. }
function InHookContext: Boolean;
begin
  Result := HookContextDepth > 0;
end;

function LowLevelKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): LRESULT; stdcall;
begin
  { Published before the body runs and cleared after it, so a callee can ask
    "am I inside the hook?" and defer its UI work to the main loop instead of
    blocking this callback on a modal dialog (see InHookContext above). }
  Inc(HookContextDepth);
  try
    try
      Result := LLHookBody(nCode, wParam, lParam);
    except
      on e: exception do
      begin
        Log('KeyboardHook: ' + e.ClassName + ': ' + e.Message);
        try
          Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
        except
          Result := 0;
        end;
      end;
    end;
  finally
    Dec(HookContextDepth);
  end;
end;

end.
