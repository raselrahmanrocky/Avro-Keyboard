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

{ The one hook procedure Windows ever calls. It is a thin, total wrapper around
  LLHookBody below: nothing may escape a WH_KEYBOARD_LL callback, and the real
  body keeps its own goto-based structure untouched. }
function LowLevelKeyboardProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;

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

// Matches a hotkey setting using a combination of manual tracker state and
// hardware-level GetAsyncKeyState. The OR logic ensures modifier tracking
// is handled by the tracked state, while GetAsyncKeyState acts as an
// auto-recovery failsafe for stuck trackers.
function MatchesHotkeySettingTracked(const Setting: string; vkCode: Integer): Boolean;
var
  NeedMods:                              Byte;
  NeedKey:                               Integer;
  CurrentMods:                           Byte;
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
  RealWin := ((GetAsyncKeyState(VK_LWIN) and $8000) <> 0) or ((GetAsyncKeyState(VK_RWIN) and $8000) <> 0);

  // Auto-recovery: If key is physically up, force-reset stuck manual trackers
  if not RealCtrl then
    TrackedCtrl := False;
  if not RealShift then
    TrackedShift := False;
  if not RealAlt then
    TrackedAlt := False;
  if not RealWin then
    TrackedWin := False;

  // Build current modifier mask from both sources (OR = belt-and-suspenders)
  CurrentMods := 0;
  if TrackedCtrl or RealCtrl then
    CurrentMods := CurrentMods or MOD_CTRL;
  if TrackedShift or RealShift then
    CurrentMods := CurrentMods or MOD_SHIFT;
  if TrackedAlt or RealAlt then
    CurrentMods := CurrentMods or MOD_ALT;
  if TrackedWin or RealWin then
    CurrentMods := CurrentMods or MOD_WIN;

  Result := (NeedMods = CurrentMods) and (NeedKey = vkCode);
end;

{ =============================================================================== }

function LLHookBody(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  kbdllhs:         pKBDLLHOOKSTRUCT;
  ShouldBlock:     Boolean;
  T:               string;
  ShortcutText:    string;
  ConflictIdx:     Integer;
  IsModifier:      Boolean;
  PickerOpen:      Boolean;
  CommandModifier: Boolean;
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
    // Clean state reset: After a hotkey was finalized, reset all tracked
    // modifiers on the NEXT KeyDown so the new recording starts fresh.
    // Must run BEFORE the modifier tracking section below.
    // ----------------------------------------------
    if RecordingFinalized and ((wParam = 256) or (wParam = 260)) then
    begin
      TrackedCtrl := False;
      TrackedShift := False;
      TrackedAlt := False;
      TrackedWin := False;
      RecordingFinalized := False;
    end;

    // ----------------------------------------------
    // Track modifier key state manually (reliable even when hook blocks key events)
    // ----------------------------------------------
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
      if kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL] then
        TrackedCtrl := False
      else if kbdllhs.vkCode in [VK_SHIFT, VK_LSHIFT, VK_RSHIFT] then
        TrackedShift := False
      else if kbdllhs.vkCode in [VK_MENU, VK_LMENU, VK_RMENU] then
        TrackedAlt := False
      else if kbdllhs.vkCode in [VK_LWIN, VK_RWIN] then
        TrackedWin := False;
    end;

    // ----------------------------------------------
    // Block F10 syskey if it's a configured hotkey
    // (prevents WM_SYSCOMMAND/SC_KEYMENU menu bar activation)
    // ----------------------------------------------
    if (kbdllhs.vkCode = VK_F10) and ((wParam = 260) or (wParam = 261)) then
    begin
      if MatchesHotkeySettingTracked(ModeSwitchKey, kbdllhs.vkCode) or MatchesHotkeySettingTracked(ToggleOutputModeKey, kbdllhs.vkCode) or
        MatchesHotkeySettingTracked(SpellerLauncherKey, kbdllhs.vkCode) or MatchesHotkeySettingTracked(AnsiVersionSwitchKey, kbdllhs.vkCode) then
      begin
        Result := 1;
        Exit;
      end;
    end;

    // ----------------------------------------------
    // Hotkey Recording Mode (with live preview)
    // ----------------------------------------------
    if IsRecordingHotkey and ((wParam = 256) or (wParam = 257) or (wParam = 260) or (wParam = 261)) then
    begin
      // Determine if current key is a modifier
      IsModifier := kbdllhs.vkCode in [VK_CONTROL, VK_LCONTROL, VK_RCONTROL, VK_SHIFT, VK_LSHIFT, VK_RSHIFT, VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN];

      // Build preview string from tracked modifier state
      ShortcutText := '';
      if TrackedCtrl then
        ShortcutText := ShortcutText + 'Ctrl + ';
      if TrackedShift then
        ShortcutText := ShortcutText + 'Shift + ';
      if TrackedAlt then
        ShortcutText := ShortcutText + 'Alt + ';
      if TrackedWin then
        ShortcutText := ShortcutText + 'Win + ';

      // CASE A: KeyDown of non-modifier = finalize recording
      if ((wParam = 256) or (wParam = 260)) and (not IsModifier) then
      begin
        // Append the final key to the shortcut
        ShortcutText := ShortcutText + VirtualKeyToStr(kbdllhs.vkCode);

        // Treat bare modifier-only or empty as "None"
        if (Trim(ShortcutText) = '') or (ShortcutText = 'None') then
          ShortcutText := 'None';

        // Validate: non-F keys require at least one modifier
        if (not TrackedCtrl) and (not TrackedShift) and (not TrackedAlt) and (not TrackedWin) and ((kbdllhs.vkCode < $70) or (kbdllhs.vkCode > $7B)) then
        begin
          // Reject this keypress but keep recording session alive
          Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
          Exit;
        end;

        // Conflict detection
        ConflictIdx := FindConflictingFeature(ShortcutText, RecordingTargetEdit);
        if ConflictIdx >= 0 then
        begin
          if not ResolveHotkeyConflict(ShortcutText, ConflictIdx) then
          begin
            // User cancelled - restore old text, stop recording
            if Assigned(RecordingTargetEdit) then
            begin
              RecordingTargetEdit.Text := RecordingOldText;
              RecordingTargetEdit.Color := clWindow;
            end;
            IsRecordingHotkey := False;
            RecordingTargetEdit := nil;
            RecordingFinalized := False;
            Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
            Exit;
          end;
          ClearConflictByIndex(ConflictIdx);
        end;

        // Update the TEdit with final shortcut (keep yellow to show recording is still active)
        if Assigned(RecordingTargetEdit) then
          RecordingTargetEdit.Text := ShortcutText;

        // Keep recording active for continuous reconfiguration
        RecordingOldText := ShortcutText;
        RecordingFinalized := True;
        // Do NOT set IsRecordingHotkey := False
        // Do NOT set RecordingTargetEdit := nil
      end
      // CASE B: KeyUp of any key = block but do NOT update display if just finalized
      else if ((wParam = 257) or (wParam = 261)) then
      begin
        if not RecordingFinalized then
        begin
          // Normal live preview during initial recording
          if Assigned(RecordingTargetEdit) then
          begin
            if ShortcutText = '' then
              RecordingTargetEdit.Text := 'None'
            else
              RecordingTargetEdit.Text := ShortcutText;
          end;
        end;
        // When RecordingFinalized is True: silently block the KeyUp,
        // keep showing the previously finalized shortcut text
      end
      // CASE C: KeyDown of modifier = show live preview (new recording cycle)
      else if ((wParam = 256) or (wParam = 260)) and IsModifier then
      begin
        // Clear finalized flag since user started a new combination
        RecordingFinalized := False;

        if Assigned(RecordingTargetEdit) then
        begin
          if ShortcutText = '' then
            RecordingTargetEdit.Text := 'None'
          else
            RecordingTargetEdit.Text := ShortcutText;
        end;
      end;

      Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
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
        application shortcuts or the configured hotkeys, which the region below
        still handles, and that is what keeps the very hotkey that opened the
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
      // Layout Switch
      if MatchesHotkeySettingTracked(LayoutSwitchKey, kbdllhs.vkCode) then
      begin
        PostMessage(AvroMainForm1.Handle, WM_APP + 3, 0, 0);
        if SettingUsesWinModifier(LayoutSwitchKey) then
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
      if MatchesHotkeySettingTracked(LayoutSwitchKey, kbdllhs.vkCode) then
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
function LowLevelKeyboardProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  try
    Result := LLHookBody(nCode, wParam, lParam);
  except
    on E: Exception do
    begin
      Log('KeyboardHook: ' + E.ClassName + ': ' + E.Message);
      try
        Result := CallNextHookEx(HookRetVal, nCode, wParam, lParam);
      except
        Result := 0;
      end;
    end;
  end;
end;

end.
