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

// Returns True when the given hotkey setting uses the Win modifier
function SettingUsesWinModifier(const Setting: string): Boolean;
begin
  Result := (HotkeyStringToModifiers(Setting) and MOD_WIN) <> 0;
end;

{ =============================================================================== }

// Matches a hotkey setting using a combination of manual tracker state and
// hardware-level GetAsyncKeyState. The OR logic ensures modifier tracking
// is handled by the tracked state, while GetAsyncKeyState acts as an
// auto-recovery failsafe for stuck trackers.
function MatchesHotkeySettingTracked(const Setting: string; vkCode: Integer): Boolean;
var
  NeedMods: Byte;
  NeedKey: Integer;
  CurrentMods: Byte;
  RealCtrl, RealShift, RealAlt, RealWin: Boolean;
begin
  Result := False;
  if (Setting = '') or (Setting = 'NONE') then
    Exit;

  NeedMods := HotkeyStringToModifiers(Setting);
  NeedKey := HotkeyStringToKey(Setting);

  // Failsafe: Query physical hardware states
  RealCtrl := (GetAsyncKeyState(VK_CONTROL) and $8000) <> 0;
  RealShift := (GetAsyncKeyState(VK_SHIFT) and $8000) <> 0;
  RealAlt := (GetAsyncKeyState(VK_MENU) and $8000) <> 0;
  RealWin := ((GetAsyncKeyState(VK_LWIN) and $8000) <> 0) or
             ((GetAsyncKeyState(VK_RWIN) and $8000) <> 0);

  // Auto-recovery: If key is physically up, force-reset stuck manual trackers
  if not RealCtrl then TrackedCtrl := False;
  if not RealShift then TrackedShift := False;
  if not RealAlt then TrackedAlt := False;
  if not RealWin then TrackedWin := False;

  // Build current modifier mask from both sources (OR = belt-and-suspenders)
  CurrentMods := 0;
  if TrackedCtrl or RealCtrl then CurrentMods := CurrentMods or MOD_CTRL;
  if TrackedShift or RealShift then CurrentMods := CurrentMods or MOD_SHIFT;
  if TrackedAlt or RealAlt then CurrentMods := CurrentMods or MOD_ALT;
  if TrackedWin or RealWin then CurrentMods := CurrentMods or MOD_WIN;

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
  IsModifier:  Boolean;
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
        TrackedWin := True;
    end
    else if (wParam = 257) or (wParam = 261) then // KeyUp
    begin
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then TrackedCtrl := False
      else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then TrackedShift := False
      else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then TrackedAlt := False
      else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
        TrackedWin := False;
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
    // Hotkey Recording Mode (with live preview)
    // ----------------------------------------------
    if IsRecordingHotkey and ((wParam = 256) or (wParam = 257) or (wParam = 260) or (wParam = 261)) then
    begin
      // Determine if current key is a modifier
      IsModifier := kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL,
                                        VK_SHIFT, VK_LSHIFT, VK_RSHIFT,
                                        VK_MENU, VK_LMENU, VK_RMENU,
                                        VK_LWIN, VK_RWIN];

      // Build preview string from tracked modifier state
      ShortcutText := '';
      if TrackedCtrl then
        ShortcutText := ShortcutText + 'Ctrl+';
      if TrackedShift then
        ShortcutText := ShortcutText + 'Shift+';
      if TrackedAlt then
        ShortcutText := ShortcutText + 'Alt+';
      if TrackedWin then
        ShortcutText := ShortcutText + 'Win+';

      // CASE A: KeyDown of non-modifier = finalize recording
      if ((wParam = 256) or (wParam = 260)) and (not IsModifier) then
      begin
        // Append the final key to the shortcut
        ShortcutText := ShortcutText + VirtualKeyToStr(kbdllhs.vkCode);

        // Conflict detection
        ConflictIdx := FindConflictingFeature(ShortcutText, RecordingTargetEdit);
        if ConflictIdx >= 0 then
        begin
          if not ResolveHotkeyConflict(ShortcutText, ConflictIdx) then
          begin
            // User cancelled - restore old text
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

        // Update the TEdit with final shortcut
        if Assigned(RecordingTargetEdit) then
        begin
          RecordingTargetEdit.Text := ShortcutText;
          RecordingTargetEdit.Color := clWindow;
        end;

        IsRecordingHotkey := False;
        RecordingTargetEdit := nil;
      end
      // CASE B: KeyUp of any key, or KeyDown of modifier = show live preview
      else
      begin
        if Assigned(RecordingTargetEdit) then
        begin
          if ShortcutText = '' then
            RecordingTargetEdit.Text := 'None'
          else
            RecordingTargetEdit.Text := ShortcutText;
        end;
      end;

      LowLevelKeyboardProc := 1;
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
        if SettingUsesWinModifier(ModeSwitchKey) then
        begin
          SendInput_Down(VK_MENU_MASK);
          SendInput_UP(VK_MENU_MASK);
        end;
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Output Mode Toggle
      if MatchesHotkeySettingTracked(ToggleOutputModeKey, kbdllhs.vkCode) then
      begin
        AvroMainForm1.ToggleOutputEncoding;
        if SettingUsesWinModifier(ToggleOutputModeKey) then
        begin
          SendInput_Down(VK_MENU_MASK);
          SendInput_UP(VK_MENU_MASK);
        end;
        ShouldBlock := True;
        goto ExitHere;
      end;
      // Speller Launcher
      if MatchesHotkeySettingTracked(SpellerLauncherKey, kbdllhs.vkCode) then
      begin
        AvroMainForm1.Spellcheck1Click(nil);
        if SettingUsesWinModifier(SpellerLauncherKey) then
        begin
          SendInput_Down(VK_MENU_MASK);
          SendInput_UP(VK_MENU_MASK);
        end;
        ShouldBlock := True;
        goto ExitHere;
      end;
      // ANSI Version Switch
      if MatchesHotkeySettingTracked(AnsiVersionSwitchKey, kbdllhs.vkCode) then
      begin
        PostMessage(AvroMainForm1.Handle, WM_APP + 1, 0, 0);
        if SettingUsesWinModifier(AnsiVersionSwitchKey) then
        begin
          SendInput_Down(VK_MENU_MASK);
          SendInput_UP(VK_MENU_MASK);
        end;
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
