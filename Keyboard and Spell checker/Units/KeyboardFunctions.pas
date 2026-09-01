{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================

  PERFORMANCE PATCH  (drop-in replacement - the interface is unchanged)
  ---------------------------------------------------------------------
  1. IsAltGr no longer calls Log().  It is called once per keystroke by the
  layout engine, so that Log() ran on EVERY key press and appended to a
  growing log file - the cause of "it gets slower and slower after a few
  thousand words".

  2. SendKey_Char no longer calls Log() either (same problem, once per
  emitted character).

  3. Backspace() and SendKey_Char() now emit ONE batched SendInput instead
  of 4 separate SendInput calls per unit.

  4. USE_NONAME_HACK switches the "unused key" (VK_NONAME) on/off in the
  batch builders.  Batched SendInput already keeps an erase+retype
  atomic, so the hack is usually unnecessary - and it DOUBLES the number
  of events, which is what makes fast typing / fast backspacing crawl in
  heavy editors (Word).  Flip it to False and test.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit KeyboardFunctions;

interface

uses
  Windows,
  SysUtils;

procedure Backspace(KeyRepeat: Integer = 1);
procedure SendKey_Char(const Keytext: string);
procedure SendKey_SendInput(const bKey: Integer);
procedure SendInput_UP(const bKey: Integer);
procedure SendInput_Down(const bKey: Integer);
procedure SendKey_Basic(const Unikey: Integer);
procedure SendInputBatch_BackspaceAndChar(KeyRepeat: Integer; const CharToSend: string);
procedure SendInputBatch_Backspace(KeyRepeat: Integer);
function IsLogicalShift: Boolean;
function IsTrueShift: Boolean;
function IsOnlyShift: Boolean;
function IsTrueShift_R: Boolean;
function IsTrueShift_L: Boolean;
function IsAltGr: Boolean;
function IsControl: Boolean;
function IsAlter: Boolean;
function IsWinKey: Boolean;
function IsOnlyLeftAltKey: Boolean;
function IsOnlyCtrlKey: Boolean;
function IsIgnorableModifierKey(const KeyCode: Integer): Boolean;

implementation

uses
  DebugLog,
  uRegistrySettings;

{ =============================================================================== }

const
  KEYEVENTF_UNICODE: Integer = $4;
  SENDKEY_DELAY_MS: Integer  = 1;

  { The "unused key" (VK_NONAME) was injected after every key to work around
    key buffering (deleting too much).  Batched SendInput already keeps a whole
    erase+retype atomic, so it is normally NOT needed - and it doubles the
    event count.  Set to False to halve the work per key.

    Measured: the input queue backs up ("characters appear seconds later")
    because every character costs 4 injected events.  With the flag off it is
    2 - the minimum possible for a Unicode character.  Batched SendInput
    already keeps erase+retype atomic, so the work-around is not needed.
    Flip it back to True ONLY if "backspace deletes too much" reappears. }
  USE_NONAME_HACK: Boolean = False;

  { =========================================================================== }

function IsIgnorableModifierKey(const KeyCode: Integer): Boolean;
begin
  case KeyCode of
    VK_LWIN, VK_RWIN:
      Result := True;
    VK_PACKET, VK_NUMLOCK, VK_CAPITAL:
      Result := True;
    VK_LSHIFT, VK_SHIFT, VK_RSHIFT:
      Result := True;
    VK_CONTROL, VK_RCONTROL, VK_LCONTROL:
      Result := True;
    VK_LMENU, VK_MENU, VK_RMENU:
      Result := True;
    else
      Result := False;
  end;
end;

{ =============================================================================== }

function IsKeyDown(aVKCode: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(aVKCode) and $8000) <> 0;
end;

{ =============================================================================== }

function IsKeyToggledOn(aVKCode: Integer): Boolean;
var
  keyState: SmallInt;
begin
  keyState := GetKeyState(aVKCode);
  Result := (keyState and $0001) <> 0; // Check the low-order bit for toggle state
end;

{ =============================================================================== }

function IsOnlyCtrlKey: Boolean;
begin
  Result := IsKeyDown(VK_CONTROL) and (not IsKeyDown(VK_MENU));
end;

{ =============================================================================== }

function IsOnlyLeftAltKey: Boolean;
begin
  Result := (not IsKeyDown(VK_CONTROL)) and IsKeyDown(VK_LMENU);
end;

{ =============================================================================== }

function IsWinKey: Boolean;
begin
  Result := IsKeyDown(VK_LWIN) or IsKeyDown(VK_RWIN);
end;

{ =============================================================================== }

function IsAlter: Boolean;
begin
  Result := IsKeyDown(VK_MENU);
end;

{ =============================================================================== }

function IsControl: Boolean;
begin
  Result := IsKeyDown(VK_CONTROL);
end;

{ =============================================================================== }

function IsAltGr: Boolean;
begin
  Result := (IsKeyDown(VK_LCONTROL) and IsKeyDown(VK_LMENU)) or IsKeyDown(VK_RMENU);
  // PERF: no Log() here - this runs on EVERY keystroke (see header).
end;

{ =============================================================================== }

function IsOnlyShift: Boolean;
begin
  Result := IsKeyDown(VK_SHIFT);
end;

{ =============================================================================== }

function IsTrueShift_L: Boolean;
begin
  Result := IsKeyDown(VK_LSHIFT);
end;

{ =============================================================================== }

function IsTrueShift_R: Boolean;
begin
  Result := IsKeyDown(VK_RSHIFT);
end;

{ =============================================================================== }

function IsTrueShift: Boolean;
begin
  Result := IsKeyDown(VK_SHIFT);
end;

{ =============================================================================== }

function IsLogicalShift: Boolean;
var
  isPhysicalShiftPressed, isCapsToggledActuallyOn: Boolean;
begin
  isPhysicalShiftPressed := IsTrueShift;

  if IgnoreCapsLock = 'YES' then
    Result := isPhysicalShiftPressed
  else
  begin
    isCapsToggledActuallyOn := IsKeyToggledOn(VK_CAPITAL);
    Result := isPhysicalShiftPressed xor isCapsToggledActuallyOn;
  end;
end;

{ =============================================================================== }
{ Single SendInput calls (kept for compatibility - the layout engine now uses
  the batched versions for everything on the hot path). }
{ =============================================================================== }

procedure Backspace(KeyRepeat: Integer = 1);
begin
  if KeyRepeat <= 0 then
    Exit;
  { One batched SendInput instead of 4 * KeyRepeat separate calls. }
  SendInputBatch_Backspace(KeyRepeat);
end;

{ =============================================================================== }

procedure SendKey_Char(const Keytext: string);
begin
  // PERF: no Log() here - this ran once per emitted character (see header).
  if Keytext = '' then
    Exit;
  { One batched SendInput instead of 4 * Length(Keytext) separate calls. }
  SendInputBatch_BackspaceAndChar(0, Keytext);
end;

{ =============================================================================== }

procedure SendKey_SendInput(const bKey: Integer);
begin
  SendInput_Down(bKey);
  SendInput_UP(bKey);
end;

{ =============================================================================== }

procedure SendInput_UP(const bKey: Integer);
var
  KInput: TInput;
begin
  KInput.Itype := INPUT_KEYBOARD;
  with KInput.ki do
  begin
    wVk := bKey;
    wScan := MapVirtualKey(wVk, 0);
    dwFlags := KEYEVENTF_KEYUP;
    time := 0;
    dwExtraInfo := 0;
  end;
  SendInput(1, KInput, SizeOf(KInput));
end;

{ =============================================================================== }

procedure SendInput_Down(const bKey: Integer);
var
  KInput: TInput;
begin
  KInput.Itype := INPUT_KEYBOARD;
  with KInput.ki do
  begin
    wVk := bKey;
    wScan := MapVirtualKey(wVk, 0);
    dwFlags := 0;
    time := 0;
    dwExtraInfo := 0;
  end;
  SendInput(1, KInput, SizeOf(KInput));
end;

{ =============================================================================== }

procedure SendKey_Basic(const Unikey: Integer);
var
  KInput: array of TInput;
begin
  SetLength(KInput, 2);
  KInput[0].Itype := INPUT_KEYBOARD;
  with KInput[0].ki do
  begin
    wVk := 0;
    wScan := Unikey;
    dwFlags := KEYEVENTF_UNICODE;
    time := 0;
    dwExtraInfo := 0;
  end;

  KInput[1].Itype := INPUT_KEYBOARD;
  with KInput[1].ki do
  begin
    wVk := 0;
    wScan := Unikey;
    dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
    time := 0;
    dwExtraInfo := 0;
  end;

  SendInput(2, KInput[0], SizeOf(KInput[0]));
end;

{ =============================================================================== }

{ Number of INPUT events one backspace costs (2 without the NONAME hack, 4
  with it). }
function BackspaceEventCount: Integer;
begin
  if USE_NONAME_HACK then
    Result := 4
  else
    Result := 2;
end;

{ Number of INPUT events one character costs (2 without the NONAME hack, 4
  with it). }
function CharEventCount: Integer;
begin
  if USE_NONAME_HACK then
    Result := 4
  else
    Result := 2;
end;

{ =============================================================================== }

procedure SendInputBatch_BackspaceAndChar(KeyRepeat: Integer; const CharToSend: string);
var
  Inputs:                array of TInput;
  TotalEvents, Index, I: Integer;
  J:                     Integer;
begin
  if KeyRepeat < 0 then
    KeyRepeat := 0;

  TotalEvents := (KeyRepeat * BackspaceEventCount) + (Length(CharToSend) * CharEventCount);
  if TotalEvents = 0 then
    Exit; // nothing to send - never touch Inputs[0] of an empty array

  SetLength(Inputs, TotalEvents);
  index := 0;

  for I := 1 to KeyRepeat do
  begin
    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := VK_Back;
    Inputs[index].ki.wScan := MapVirtualKey(VK_Back, 0);
    Inputs[index].ki.dwFlags := 0;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := VK_Back;
    Inputs[index].ki.wScan := MapVirtualKey(VK_Back, 0);
    Inputs[index].ki.dwFlags := KEYEVENTF_KEYUP;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    if USE_NONAME_HACK then
    begin
      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := 0;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);

      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := KEYEVENTF_KEYUP;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);
    end;
  end;

  for J := 1 to Length(CharToSend) do
  begin
    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := 0;
    Inputs[index].ki.wScan := Ord(CharToSend[J]);
    Inputs[index].ki.dwFlags := KEYEVENTF_UNICODE;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := 0;
    Inputs[index].ki.wScan := Ord(CharToSend[J]);
    Inputs[index].ki.dwFlags := KEYEVENTF_UNICODE or KEYEVENTF_KEYUP;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    if USE_NONAME_HACK then
    begin
      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := 0;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);

      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := KEYEVENTF_KEYUP;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);
    end;
  end;

  SendInput(TotalEvents, Inputs[0], SizeOf(Inputs[0]));
end;

{ =============================================================================== }

procedure SendInputBatch_Backspace(KeyRepeat: Integer);
var
  Inputs:                array of TInput;
  TotalEvents, Index, I: Integer;
begin
  if KeyRepeat <= 0 then
    Exit;

  TotalEvents := KeyRepeat * BackspaceEventCount;
  SetLength(Inputs, TotalEvents);
  index := 0;

  for I := 1 to KeyRepeat do
  begin
    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := VK_Back;
    Inputs[index].ki.wScan := MapVirtualKey(VK_Back, 0);
    Inputs[index].ki.dwFlags := 0;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    Inputs[index].Itype := INPUT_KEYBOARD;
    Inputs[index].ki.wVk := VK_Back;
    Inputs[index].ki.wScan := MapVirtualKey(VK_Back, 0);
    Inputs[index].ki.dwFlags := KEYEVENTF_KEYUP;
    Inputs[index].ki.time := 0;
    Inputs[index].ki.dwExtraInfo := 0;
    Inc(index);

    if USE_NONAME_HACK then
    begin
      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := 0;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);

      Inputs[index].Itype := INPUT_KEYBOARD;
      Inputs[index].ki.wVk := VK_NONAME;
      Inputs[index].ki.wScan := MapVirtualKey(VK_NONAME, 0);
      Inputs[index].ki.dwFlags := KEYEVENTF_KEYUP;
      Inputs[index].ki.time := 0;
      Inputs[index].ki.dwExtraInfo := 0;
      Inc(index);
    end;
  end;

  SendInput(TotalEvents, Inputs[0], SizeOf(Inputs[0]));
end;

end.
