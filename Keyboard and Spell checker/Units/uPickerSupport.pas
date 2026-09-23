{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uPickerSupport;

{
  Shared pieces of the two transient popups (the keyboard-layout switcher and
  the ANSI-encoding switcher).

  The popups can not rely on owning the Win32 foreground: on many machines
  SetForegroundWindow is refused for a WS_EX_TOOLWINDOW popup (foreground lock,
  UIPI, a fullscreen game, an elevated or UWP target), and when it is refused
  the keys the user presses go to the previous application - or are eaten by the
  Bangla layout engine - while the popup sits there looking alive.

  So the low-level keyboard hook - which runs in this process no matter who owns
  the foreground - is the source of truth. While a popup is visible it blocks
  the navigation keys and posts WM_PICKER_KEY to the popup's own HWND, and the
  popup acts on that message. Win32 focus is only ever best effort after that.

  This unit must never use uForm1 or KeyboardHook: the hook unit uses it and a
  circular reference between a hook and a form unit is what turns a small bug
  into a startup crash.
}

interface

uses
  Windows,
  Messages,
  Classes,
  Vcl.StdCtrls;

const
  { Posted by the keyboard hook to a visible popup: wParam is the VK code of a
    key the user pressed while that popup was up. The hook blocks the physical
    key, so the popup would never see a WM_KEYDOWN for it - this message is the
    only keyboard input the popup gets on a machine where it is not focused,
    and it is deliberately not a WM_KEY* so it can not be confused with one. }
  WM_PICKER_KEY = WM_APP + 5;

  { Posted by the mouse dismiss hook to a visible popup. Kept separate from
    WM_CLOSE because the VCL handles WM_CLOSE itself (TControl.WndProc calls
    Form.Close), which would bypass any message method declared here. }
  WM_PICKER_DISMISS = WM_APP + 6;

  { How long a popup must have been up before losing the foreground is treated
    as a real deactivation. Activation can flicker for the first frames of a
    WS_EX_TOPMOST popup, and closing on that first flicker is what made the
    popups unusable on machines where taking the foreground is slow. }
  PICKER_ACTIVATION_GRACE_MS = 400;

  { Best-effort focus re-assertions after Show, ~1 s at the popup's 200 ms
    timer. Giving up is fine: the hook drives the keys either way. }
  PICKER_FOCUS_ATTEMPTS = 5;

{ True for the keys a visible popup navigates with: the number row, the numpad
  (with NumLock on - the numpad keys report VK_HOME/VK_END/... with it off and
  are then indistinguishable from the real cursor keys), latin letters, and
  Up/Down/Enter/Escape.

  Letters are matched by VK code, not by the character produced: VK_A..VK_Z are
  layout independent, so the first-letter shortcut means "the A key" even while
  a Bangla or Dvorak layout is active. }
function IsPickerNavigableKey(AVk: Integer): Boolean;

{ The row a key activates, or -1 when that key is not a row shortcut.

  1-based numbers, exactly the numbers the rows draw: '1' and numpad 1 select
  the first row, ... '9' selects the ninth. Anything past the last row is -1.

  Letters select the first row whose caption starts with that letter, compared
  case-insensitively - the same rule the ANSI mapping menus use. }
function PickerIndexForKey(const ANames: TStrings; AKey: Word): Integer;

{ The one key implementation, shared by the posted-message path and by the
  popup's own OnKeyDown/OnKeyPress fallback so a shortcut can never behave
  differently depending on which one handled it.

  AConsumed is True for every navigable key - including one that matched no row,
  so the caller always swallows it and nothing is typed into the application
  underneath.
  AActivateIndex: >= 0 apply that row, -1 nothing, -2 cancel (Escape).
  Up/Down move the highlight only; nothing is applied until Enter or a
  number/letter shortcut. }
procedure HandlePickerNavigation(AListBox: TListBox; AKey: Word;
  out AConsumed: Boolean; out AActivateIndex: Integer);

{ Best-effort activation. Never a precondition for anything: the hook delivers
  the navigation keys whether or not this succeeds.

  SetForegroundWindow is tried first because the process that received the last
  input event may take the foreground, and attaching to another thread's input
  queue is the operation that can hang (and that leaves queues attached if it is
  not undone). AttachThreadInput is therefore only a fallback, it skips thread 0
  and a hung foreground window, and it always detaches in a finally block. }
procedure PickerBringToForeground(AWnd: HWND; out ABecameForeground: Boolean);

{ Hands the caret back to where the popup was opened from. }
procedure PickerRestoreForeground(APrevFocus, APrevForeground: HWND);

{ Temporary WH_MOUSE_LL, installed only while a popup is visible.

  A popup that never got the foreground can not notice a click outside any other
  way (the foreground-timer rule was exactly what had to be deleted), and on the
  machines this fixes that is the normal case, not the exception.

  The callback never swallows the click (it always chains to CallNextHookEx) and
  never touches the form object - it posts WM_PICKER_DISMISS to the owner HWND. }
procedure PickerMouseHookInstall(AOwnerWnd: HWND);
procedure PickerMouseHookRemove(AOwnerWnd: HWND);

{ Suspend dismissal while one of our own popup menus is up: the menu is a
  different window than the popup, so a click on it would otherwise look like an
  outside click and tear the popup down mid-selection. }
procedure PickerMouseHookSuspend;
procedure PickerMouseHookResume;

implementation

uses
  SysUtils,
  Vcl.Forms;

{ Winapi.Windows does not declare this one. A hung foreground window has to be
  skipped before attaching to its input queue: AttachThreadInput to a hung
  thread is exactly how a popup turns into a frozen application. }
function IsHungAppWindow(AWnd: HWND): BOOL; stdcall; external 'user32.dll' name 'IsHungAppWindow';

var
  MouseHook:          HHOOK = 0;
  MouseHookOwner:     HWND = 0;
  MouseHookSuspended: Boolean = False;

{ =============================================================================== }

function IsPickerNavigableKey(AVk: Integer): Boolean;
begin
  Result := ((AVk >= Ord('0')) and (AVk <= Ord('9'))) or
    ((AVk >= VK_NUMPAD0) and (AVk <= VK_NUMPAD9)) or
    ((AVk >= Ord('A')) and (AVk <= Ord('Z'))) or
    (AVk = VK_UP) or (AVk = VK_DOWN) or (AVk = VK_RETURN) or (AVk = VK_ESCAPE);
end;

{ =============================================================================== }

function PickerIndexForKey(const ANames: TStrings; AKey: Word): Integer;
var
  I:  Integer;
  Ch: Char;
begin
  Result := -1;
  if not Assigned(ANames) then
    Exit;

  if (AKey >= Ord('1')) and (AKey <= Ord('9')) then
    Result := AKey - Ord('1')
  else if (AKey >= VK_NUMPAD1) and (AKey <= VK_NUMPAD9) then
    Result := AKey - VK_NUMPAD1
  else if (AKey >= Ord('A')) and (AKey <= Ord('Z')) then
  begin
    Ch := Chr(AKey);
    for I := 0 to ANames.Count - 1 do
      if (ANames[I] <> '') and (UpCase(ANames[I][1]) = Ch) then
        Exit(I);
    Exit;
  end
  else
    { Up/Down/Enter/Escape (and '0') are handled by the caller, not by a row
      lookup. }
    Exit;

  { A number past the last row is not an activation and must be ignored, not
    clamped onto the last row. }
  if (Result < 0) or (Result >= ANames.Count) then
    Result := -1;
end;

{ =============================================================================== }

procedure HandlePickerNavigation(AListBox: TListBox; AKey: Word;
  out AConsumed: Boolean; out AActivateIndex: Integer);
var
  Idx: Integer;
begin
  AConsumed := IsPickerNavigableKey(AKey);
  AActivateIndex := -1;
  if (not AConsumed) or (AListBox = nil) then
    Exit;

  case AKey of
    VK_ESCAPE:
      AActivateIndex := -2;
    VK_RETURN:
      if (AListBox.ItemIndex >= 0) and (AListBox.ItemIndex < AListBox.Items.Count) then
        AActivateIndex := AListBox.ItemIndex;
    VK_UP, VK_DOWN:
      { Wrapping selection move. Nothing is applied: the highlight only moves,
        exactly like hovering a row with the mouse. }
      if AListBox.Items.Count > 0 then
      begin
        if AListBox.ItemIndex < 0 then
          AListBox.ItemIndex := 0
        else if AKey = VK_UP then
          AListBox.ItemIndex := (AListBox.ItemIndex - 1 + AListBox.Items.Count) mod AListBox.Items.Count
        else
          AListBox.ItemIndex := (AListBox.ItemIndex + 1) mod AListBox.Items.Count;
      end;
    else
      begin
        Idx := PickerIndexForKey(AListBox.Items, AKey);
        if Idx >= 0 then
          AActivateIndex := Idx;
      end;
  end;
end;

{ =============================================================================== }

procedure PickerBringToForeground(AWnd: HWND; out ABecameForeground: Boolean);
var
  ForeWnd:                HWND;
  ForeThread, ThisThread: DWORD;
begin
  ABecameForeground := False;
  if not IsWindow(AWnd) then
    Exit;
  if GetForegroundWindow = AWnd then
  begin
    ABecameForeground := True;
    Exit;
  end;

  SetForegroundWindow(AWnd);
  BringWindowToTop(AWnd);

  if GetForegroundWindow <> AWnd then
  begin
    ForeWnd := GetForegroundWindow;
    if (ForeWnd <> 0) and (not IsHungAppWindow(ForeWnd)) then
    begin
      ForeThread := GetWindowThreadProcessId(ForeWnd, nil);
      ThisThread := GetCurrentThreadId;
      if (ForeThread <> 0) and (ForeThread <> ThisThread) then
        if AttachThreadInput(ForeThread, ThisThread, True) then
          try
            SetForegroundWindow(AWnd);
            BringWindowToTop(AWnd);
            Windows.SetFocus(AWnd);
          finally
            { Always detach, on every path: two input queues left attached
              outlive this popup and break activation for the whole process. }
            AttachThreadInput(ForeThread, ThisThread, False);
          end;
    end;
  end;

  ABecameForeground := GetForegroundWindow = AWnd;
end;

{ =============================================================================== }

procedure PickerRestoreForeground(APrevFocus, APrevForeground: HWND);
begin
  if IsWindow(APrevFocus) then
    Windows.SetFocus(APrevFocus);
  if IsWindow(APrevForeground) and (GetForegroundWindow <> APrevForeground) then
    SetForegroundWindow(APrevForeground);
end;

{ =============================================================================== }

{ True when ATarget is the popup or one of its child controls (the list box). }
function IsOwnedByPicker(AOwnerWnd, ATarget: HWND): Boolean;
begin
  Result := (ATarget = AOwnerWnd) or IsChild(AOwnerWnd, ATarget);
end;

{ Our own popup menus and combo drop-downs are class #32768 / ComboLBox and are
  NOT children of the popup, so a click on them would otherwise look exactly
  like a click outside. }
function IsOwnMenuClass(ATarget: HWND): Boolean;
var
  ClsName: array [0 .. 63] of Char;
begin
  Result := False;
  if GetClassName(ATarget, ClsName, SizeOf(ClsName) div SizeOf(Char)) = 0 then
    Exit;
  Result := (StrComp(ClsName, '#32768') = 0) or (StrComp(ClsName, 'ComboLBox') = 0);
end;

function LowLevelMouseProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  Info:   PMouseHookStruct;
  Target: HWND;
begin
  try
    if (nCode = HC_ACTION) and (not MouseHookSuspended) and IsWindow(MouseHookOwner) and (Application.ModalLevel = 0) then
      case wParam of
        WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_XBUTTONDOWN, WM_NCLBUTTONDOWN, WM_NCRBUTTONDOWN, WM_NCMBUTTONDOWN:
          begin
            Info := PMouseHookStruct(lParam);
            Target := WindowFromPoint(Info.pt);
            if (Target <> 0) and (not IsOwnedByPicker(MouseHookOwner, Target)) and (not IsOwnMenuClass(Target)) then
              { Dismiss, do not swallow: the user's click still reaches whatever
                they clicked, exactly like a menu that closes itself. Closing is
                the popup's own business - only its HWND crosses this boundary. }
              PostMessage(MouseHookOwner, WM_PICKER_DISMISS, 0, 0);
          end;
      end;
  except
    { A hook procedure must never let an exception escape. }
  end;

  Result := CallNextHookEx(MouseHook, nCode, wParam, lParam);
end;

procedure PickerMouseHookInstall(AOwnerWnd: HWND);
begin
  if not IsWindow(AOwnerWnd) then
    Exit;

  { One popup at a time (the two toggles exclude each other), but never leave an
    older hook behind if that ever stops being true. }
  if MouseHook <> 0 then
  begin
    UnhookWindowsHookEx(MouseHook);
    MouseHook := 0;
  end;

  MouseHookOwner := AOwnerWnd;
  MouseHookSuspended := False;
  MouseHook := SetWindowsHookEx(WH_MOUSE_LL, @LowLevelMouseProc, HInstance, 0);
end;

procedure PickerMouseHookRemove(AOwnerWnd: HWND);
begin
  if (MouseHook <> 0) and ((MouseHookOwner = AOwnerWnd) or (AOwnerWnd = 0)) then
  begin
    UnhookWindowsHookEx(MouseHook);
    MouseHook := 0;
    MouseHookOwner := 0;
  end;
  MouseHookSuspended := False;
end;

procedure PickerMouseHookSuspend;
begin
  MouseHookSuspended := True;
end;

procedure PickerMouseHookResume;
begin
  MouseHookSuspended := False;
end;

initialization

finalization

  { A hook left installed past the lifetime of the window it reports to would
    outlive the message loop that pumps it. }
  if MouseHook <> 0 then
  begin
    UnhookWindowsHookEx(MouseHook);
    MouseHook := 0;
    MouseHookOwner := 0;
  end;

end.
