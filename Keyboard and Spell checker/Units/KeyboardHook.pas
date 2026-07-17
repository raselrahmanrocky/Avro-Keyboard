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
function LowLevelKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): longword; stdcall;

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
  HookRetVal: Integer;

const
  LLKHF_INJECTED = $10;

implementation

uses
  uForm1,
  KeyboardFunctions,
  VirtualKeycode,
  clsLayout,
  uRegistrySettings,
  uWindowHandlers,
  uKeyboardMacro;

{ =============================================================================== }

var
  IsHook: Boolean;

var
  // Manually tracked modifier key state (more reliable than GetAsyncKeyState inside WH_KEYBOARD_LL hook)
  TrackedCtrl: Boolean = False;
  TrackedShift: Boolean = False;
  TrackedAlt: Boolean = False;
  TrackedWin: Boolean = False;

var
  // Win key blocking: tracks whether Win was blocked to prevent Start Menu
  // so Win-based hotkeys (e.g. Win+Space) can work cleanly.
  WinBlockedForHotkey: Boolean = False;
  NonModifierPressedAfterWin: Boolean = False;

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
      Result := HookRetVal;
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
  UnhookWindowsHookEx(HookRetVal);
end;

{ =============================================================================== }

// Returns True when at least one system hotkey uses the Win modifier
function HasWinBasedHotkey: Boolean;
begin
  Result := ((HotkeyStringToModifiers(ModeSwitchKey) and MOD_WIN) <> 0) or
            ((HotkeyStringToModifiers(ToggleOutputModeKey) and MOD_WIN) <> 0) or
            ((HotkeyStringToModifiers(SpellerLauncherKey) and MOD_WIN) <> 0) or
            ((HotkeyStringToModifiers(AnsiVersionSwitchKey) and MOD_WIN) <> 0);
end;

{ =============================================================================== }

// Version of MatchesHotkeySetting that uses tracked modifier state instead of
// GetAsyncKeyState. Required when a modifier keydown has been blocked by the hook
// (e.g. Win key blocked to prevent Start Menu), because GetAsyncKeyState won't
// report it as pressed.
function MatchesHotkeySettingTracked(const Setting: string; vkCode: Integer): Boolean;
var
  NeedMods: Byte;
  NeedKey: Integer;
  CurrentMods: Byte;
begin
  Result := False;
  if (Setting = '') or (Setting = 'NONE') then
    Exit;

  NeedMods := HotkeyStringToModifiers(Setting);
  NeedKey := HotkeyStringToKey(Setting);

  CurrentMods := 0;
  if TrackedCtrl then CurrentMods := CurrentMods or MOD_CTRL;
  if TrackedShift then CurrentMods := CurrentMods or MOD_SHIFT;
  if TrackedAlt then CurrentMods := CurrentMods or MOD_ALT;
  if TrackedWin then CurrentMods := CurrentMods or MOD_WIN;

  Result := (NeedMods = CurrentMods) and (NeedKey = vkCode);
end;

{ =============================================================================== }

function LowLevelKeyboardProc(nCode: Integer; wParam: wParam; lParam: lParam): longword; stdcall;
var
  kbdllhs:     pKBDLLHOOKSTRUCT;
  ShouldBlock: Boolean;
  T:           string;
  ShortcutText: string;
  ConflictIdx: Integer;

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
      LowLevelKeyboardProc := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    // ----------------------------------------------
    // Don't Process VK_Packet
    // ----------------------------------------------
    if kbdllhs.vkCode = VK_PACKET then
    begin
      LowLevelKeyboardProc := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    // ----------------------------------------------
    // Track modifier key state manually (reliable even when hook blocks key events)
    // ----------------------------------------------
    if (wParam = 256) or (wParam = 260) then // KeyDown
    begin
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then TrackedCtrl := True
      else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then TrackedShift := True
      else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then TrackedAlt := True
      else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
      begin
        TrackedWin := True;
        // Block Win keydown if any hotkey uses the Win modifier,
        // so Start Menu is not triggered when a Win-based hotkey is pressed.
        if HasWinBasedHotkey then
        begin
          WinBlockedForHotkey := True;
          NonModifierPressedAfterWin := False;
          LowLevelKeyboardProc := 1;
          Exit;
        end;
      end;
      // Track if a non-modifier key was pressed while Win is blocked,
      // so we know whether to re-send Win on keyup.
      if WinBlockedForHotkey then
      begin
        if not (kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
                                   VK_SHIFT, VK_LSHIFT, VK_RSHIFT,
                                   VK_MENU, VK_LMENU, VK_RMENU,
                                   VK_LWIN, VK_RWIN]) then
          NonModifierPressedAfterWin := True;
      end;
    end
    else if (wParam = 257) or (wParam = 261) then // KeyUp
    begin
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then TrackedCtrl := False
      else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then TrackedShift := False
      else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then TrackedAlt := False
      else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
      begin
        TrackedWin := False;
        // If Win was blocked but no hotkey key was pressed,
        // re-send Win to open Start Menu.
        if WinBlockedForHotkey then
        begin
          WinBlockedForHotkey := False;
          if not NonModifierPressedAfterWin then
          begin
            SendInput_Down(VK_LWIN);
            SendInput_UP(VK_LWIN);
          end;
          NonModifierPressedAfterWin := False;
        end;
      end;
    end;

    // ----------------------------------------------
    // Block F10 syskey if it's a configured hotkey
    // (prevents WM_SYSCOMMAND/SC_KEYMENU menu bar activation)
    // ----------------------------------------------
    if (kbdllhs.vkCode = VK_F10) and ((wParam = 260) or (wParam = 261)) then
    begin
      if MatchesHotkeySettingTracked(ModeSwitchKey, kbdllhs.vkCode) or
         MatchesHotkeySettingTracked(ToggleOutputModeKey, kbdllhs.vkCode) or
         MatchesHotkeySettingTracked(SpellerLauncherKey, kbdllhs.vkCode) or
         MatchesHotkeySettingTracked(AnsiVersionSwitchKey, kbdllhs.vkCode) then
      begin
        LowLevelKeyboardProc := 1;
        Exit;
      end;
    end;


    // ----------------------------------------------
    // Hotkey Recording Mode
    // ----------------------------------------------
    if IsRecordingHotkey and ((wParam = 256) or (wParam = 260)) then
    begin
      // Skip pure modifier presses (wait for main key)
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
                            VK_SHIFT, VK_LSHIFT, VK_RSHIFT,
                            VK_MENU, VK_LMENU, VK_RMENU,
                            VK_LWIN, VK_RWIN] then
      begin
        LowLevelKeyboardProc := 1;
        Exit;
      end;

      // Build shortcut string from tracked modifier state
      ShortcutText := '';
      if TrackedCtrl then
        ShortcutText := ShortcutText + 'Ctrl+';
      if TrackedShift then
        ShortcutText := ShortcutText + 'Shift+';
      if TrackedAlt then
        ShortcutText := ShortcutText + 'Alt+';
      if TrackedWin then
        ShortcutText := ShortcutText + 'Win+';
      ShortcutText := ShortcutText + VirtualKeyToStr(kbdllhs.vkCode);

      // Conflict detection
      ConflictIdx := FindConflictingFeature(ShortcutText, RecordingTargetEdit);
      if ConflictIdx >= 0 then
      begin
        if not ResolveHotkeyConflict(ShortcutText, ConflictIdx) then
        begin
          if Assigned(RecordingTargetEdit) then
          begin
            RecordingTargetEdit.Text := RecordingOldText;
            RecordingTargetEdit.Color := clWindow;
          end;
          IsRecordingHotkey := False;
          RecordingTargetEdit := nil;
          LowLevelKeyboardProc := 1;
          Exit;
        end;
        ClearConflictByIndex(ConflictIdx);
      end;

      // Update the TEdit
      if Assigned(RecordingTargetEdit) then
      begin
        RecordingTargetEdit.Text := ShortcutText;
        RecordingTargetEdit.Color := clWindow;
      end;
      // Sync the underlying variable
      for var FeatIdx := 0 to Length(HotkeyFeatures) - 1 do
      begin
        if HotkeyFeatures[FeatIdx].EditRef = RecordingTargetEdit then
        begin
          HotkeyFeatures[FeatIdx].VariablePtr^ := ShortcutText;
          Break;
        end;
      end;
      IsRecordingHotkey := False;
      RecordingTargetEdit := nil;

      LowLevelKeyboardProc := 1; // Block the key
      Exit;
    end;

    // ----------------------------------------------
    // Vista Error Fix: Ghost 144 (Dec) key is coming
    // ----------------------------------------------
    if kbdllhs.vkCode = 144 then
    begin
      LowLevelKeyboardProc := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      Exit;
    end;

    {$ENDREGION}
    {$REGION 'Keyboard layout management'}
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

    {$ENDREGION}
    {$REGION 'Keyboard mode management'}
    if ((wParam = 256) or (wParam = 260)) then
    begin // Keydown
      // Mode Switch
      if MatchesHotkeySettingTracked(ModeSwitchKey, kbdllhs.vkCode) then
      begin
        AvroMainForm1.ToggleMode;
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Output Mode Toggle
      if MatchesHotkeySettingTracked(ToggleOutputModeKey, kbdllhs.vkCode) then
      begin
        AvroMainForm1.ToggleOutputEncoding;
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Speller Launcher
      if MatchesHotkeySettingTracked(SpellerLauncherKey, kbdllhs.vkCode) then
      begin
        AvroMainForm1.Spellcheck1Click(nil);
        ShouldBlock := True;
        goto ExitHere;
      end;
      // ANSI Version Switch
      if MatchesHotkeySettingTracked(AnsiVersionSwitchKey, kbdllhs.vkCode) then
      begin
        PostMessage(AvroMainForm1.Handle, WM_APP + 1, 0, 0);
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Unicode/ANSI Toggle Shortcuts
      if UnicodeToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (kbdllhs.vkCode = Ord('V')) then
        begin
          AvroMainForm1.SetBengaliUnicodeMode;
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      if ANSIToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (kbdllhs.vkCode = Ord('B')) then
        begin
          AvroMainForm1.SetBengaliANSIMode;
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      // Custom user hotkey check
      if MatchUserHotkey(kbdllhs.vkCode, T) then
      begin
        SendKey_Char(T);
        ShouldBlock := True;
        goto ExitHere;
      end;
    end

    else if ((wParam = 257) or (wParam = 261)) then
    begin // Keyup
      // Block KeyUp for all hotkeys
      if MatchesHotkeySettingTracked(ModeSwitchKey, kbdllhs.vkCode) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
      if MatchesHotkeySettingTracked(ToggleOutputModeKey, kbdllhs.vkCode) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
      if MatchesHotkeySettingTracked(SpellerLauncherKey, kbdllhs.vkCode) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
      if MatchesHotkeySettingTracked(AnsiVersionSwitchKey, kbdllhs.vkCode) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Unicode/ANSI Toggle Shortcuts
      if UnicodeToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (kbdllhs.vkCode = Ord('V')) then
        begin
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      if ANSIToggleShortcut = 'YES' then
      begin
        if (IsTrueShift = False) and IsControl and IsAlter and (kbdllhs.vkCode = Ord('B')) then
        begin
          ShouldBlock := True;
          goto ExitHere;
        end;
      end;
      // Block KeyUp for custom hotkeys
      T := '';
      if MatchUserHotkey(kbdllhs.vkCode, T) then
      begin
        ShouldBlock := True;
        goto ExitHere;
      end;
    end;
    {$ENDREGION}

  end; { nCode = HC_ACTION }

ExitHere:
  if ShouldBlock = True then
    LowLevelKeyboardProc := 1
  else
  begin
    LowLevelKeyboardProc := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
  end;

end;

end.
