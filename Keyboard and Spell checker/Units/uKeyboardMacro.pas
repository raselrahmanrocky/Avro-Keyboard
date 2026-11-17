{$INCLUDE ../ProjectDefines.inc}
unit uKeyboardMacro;

interface

uses
  Classes,
  Graphics,
  Menus,
  StdCtrls; // For TEdit

const
  MOD_CTRL  = 1;
  MOD_SHIFT = 2;
  MOD_ALT   = 4;
  MOD_WIN   = 8;

type
  TUserHotkey = record
    ModifierMask: Byte;
    VirtualKey: Byte;
    ReplacementText: string;
  end;

  TUserHotkeyArray = array of TUserHotkey;

var
  UserHotkeys: TUserHotkeyArray;

  // Hotkey capture state: owned by the focused TAvroHotKey (Units\uAvroHotKey.pas)
  HotkeyCaptureActive: Boolean;
  // True once the current gesture produced a main key.  Modifier-only input must
  // end on "None" (THotKey behaviour), but the modifier key-ups that follow a
  // real combination must not clear it again.
  HotkeyCaptureCommitted: Boolean;
  // The keyboard hook commits a finished combination here; '' reverts, 'None'
  // clears.  The dialog answers with validation, the conflict dialog and the
  // revert, so this unit stays free of the field's class.
  HotkeyCaptureCommit: procedure(const Text: string) of object;
  // Live "pressed" state, e.g. 'Ctrl + Alt + ', painted by the focused field
  // while the keys are still held.  '' restores the committed value.
  HotkeyCapturePreview: procedure(const Text: string) of object;

function HotkeysEqual(const A, B: string): Boolean;

procedure AddUserHotkey(Mods: Byte; Key: Byte; const Text: string);
procedure RemoveUserHotkey(Index: Integer);
procedure ClearUserHotkeys;
function MatchUserHotkey(vkCode: Integer; var OutText: string): Boolean;
function MatchUserHotkeyWithMods(vkCode: Integer; Mods: Byte; var OutText: string): Boolean;
function ModifierMaskFromState: Byte;
function UserHotkeyToString(Index: Integer): string;
procedure SaveUserHotkeysToXML;
procedure LoadUserHotkeysFromXML;

// Hotkey string helpers
function HotkeyStringToModifiers(const S: string): Byte;
function HotkeyStringToKey(const S: string): Integer;
function KeyToHotkeyString(Mods: Byte; VK: Integer): string;
function MatchesHotkeySetting(const Setting: string; vkCode: Integer): Boolean;
function HotkeySettingMatchesVk(const Setting: string; AKey: Integer; Mods: Byte): Boolean;
function NormalizeHotkeyVk(AKey, ScanCode: Integer; Extended: Boolean): Integer;
function HotkeyStringToShortCut(const Setting: string): TShortCut;
function VirtualKeyToStr(VK: Byte): string;

{ True when the comctl32 hot-key control would paint a different name than the
  setting means.  Its renderer maps the virtual key to a scan code without the
  extended-key bit, so a dedicated arrow is painted with the name of the numpad
  key that shares its scan code ("Up" -> "Num 8"); the keypad decimal, divide
  and separator keys lose their "Num" prefix the same way.  Such values are
  painted by TAvroHotKey itself. }
function HotkeyKeyNeedsOwnPaint(VK: Integer): Boolean;

{ True for the keys that may be recorded as a hotkey with no modifier held.
  The field is a THotKey whose InvalidKeys is empty, so the native control
  accepts a bare key; F-keys, the navigation block and the numeric keypad are
  the ones that are safe to give away.  Letters and the top-row digits are
  deliberately absent: a global hotkey that swallows ordinary typing would
  make the keyboard unusable everywhere, not just in Avro. }
function IsBareHotkeyKey(VK: Integer): Boolean;

implementation

uses
  Forms,
  SysUtils,
  Windows,
  KeyboardFunctions,
  clsRegistry_XMLSetting;

{ =============================================================================== }

function ModifierMaskFromState: Byte;
begin
  Result := 0;
  if IsControl then
    Result := Result or MOD_CTRL;
  if IsTrueShift then
    Result := Result or MOD_SHIFT;
  if IsAlter then
    Result := Result or MOD_ALT;
  if IsWinKey then
    Result := Result or MOD_WIN;
end;

{ =============================================================================== }

procedure AddUserHotkey(Mods: Byte; Key: Byte; const Text: string);
var
  Len: Integer;
begin
  Len := Length(UserHotkeys);
  SetLength(UserHotkeys, Len + 1);
  UserHotkeys[Len].ModifierMask := Mods;
  UserHotkeys[Len].VirtualKey := Key;
  UserHotkeys[Len].ReplacementText := Text;
end;

{ =============================================================================== }

procedure RemoveUserHotkey(Index: Integer);
var
  I, Count: Integer;
begin
  Count := Length(UserHotkeys);
  if (index < 0) or (index >= Count) then
    Exit;

  for I := index to Count - 2 do
    UserHotkeys[I] := UserHotkeys[I + 1];

  SetLength(UserHotkeys, Count - 1);
end;

{ =============================================================================== }

procedure ClearUserHotkeys;
begin
  SetLength(UserHotkeys, 0);
end;

{ =============================================================================== }

function MatchUserHotkey(vkCode: Integer; var OutText: string): Boolean;
begin
  Result := MatchUserHotkeyWithMods(vkCode, ModifierMaskFromState, OutText);
end;

{ =============================================================================== }

function MatchUserHotkeyWithMods(vkCode: Integer; Mods: Byte; var OutText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  OutText := '';

  for I := 0 to Length(UserHotkeys) - 1 do
  begin
    if (UserHotkeys[I].VirtualKey = vkCode) and (UserHotkeys[I].ModifierMask = Mods) then
    begin
      OutText := UserHotkeys[I].ReplacementText;
      Result := True;
      Exit;
    end;
  end;
end;

{ =============================================================================== }

function ModifierMaskToStr(Mask: Byte): string;
begin
  Result := '';
  if (Mask and MOD_CTRL) <> 0 then
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + 'Ctrl';
  end;
  if (Mask and MOD_SHIFT) <> 0 then
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + 'Shift';
  end;
  if (Mask and MOD_ALT) <> 0 then
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + 'Alt';
  end;
  if (Mask and MOD_WIN) <> 0 then
  begin
    if Result <> '' then
      Result := Result + '+';
    Result := Result + 'Win';
  end;
end;

{ =============================================================================== }

function VirtualKeyToStr(VK: Byte): string;
begin
  case VK of
    $08:
      Result := 'Backspace';
    $14:
      Result := 'CapsLock';
    $20:
      Result := 'Space';
    $30 .. $39:
      Result := Chr(VK);
    $41 .. $5A:
      Result := Chr(VK);
    $5D:
      Result := 'Menu';
    $70:
      Result := 'F1';
    $71:
      Result := 'F2';
    $72:
      Result := 'F3';
    $73:
      Result := 'F4';
    $74:
      Result := 'F5';
    $75:
      Result := 'F6';
    $76:
      Result := 'F7';
    $77:
      Result := 'F8';
    $78:
      Result := 'F9';
    $79:
      Result := 'F10';
    $7A:
      Result := 'F11';
    $7B:
      Result := 'F12';
    $0D:
      Result := 'Enter';
    $1B:
      Result := 'Esc';
    $09:
      Result := 'Tab';
    $2E:
      Result := 'Delete';
    $2D:
      Result := 'Insert';
    $24:
      Result := 'Home';
    $23:
      Result := 'End';
    $21:
      Result := 'PageUp';
    $22:
      Result := 'PageDown';
    $26:
      Result := 'Up';
    $28:
      Result := 'Down';
    $25:
      Result := 'Left';
    $27:
      Result := 'Right';
    { The numeric keypad.  A digit there is VK_NUMPAD0..VK_NUMPAD9, not
      VK_0..VK_9, so it needs its own names or the setting cannot be parsed
      back (it used to be stored as "VK97", which StrToVirtualKey read as
      Space).  "+" is the modifier delimiter of the setting string, hence
      "Num Plus" instead of "Num +". }
    $60 .. $69:
      Result := 'Num ' + Chr(VK - $60 + Ord('0'));
    $6A:
      Result := 'Num *';
    $6B:
      Result := 'Num Plus';
    $6C:
      Result := 'Num Sep';
    $6D:
      Result := 'Num -';
    $6E:
      Result := 'Num .';
    $6F:
      Result := 'Num /';
    $BA:
      Result := ';';
    $BB:
      Result := '=';
    $BC:
      Result := ',';
    $BD:
      Result := '-';
    $BE:
      Result := '.';
    $BF:
      Result := '/';
    $C0:
      Result := '`';
    $DB:
      Result := '[';
    $DC:
      Result := '\';
    $DD:
      Result := ']';
    $DE:
      Result := '''';
    else
      Result := 'VK' + IntToStr(VK);
  end;
end;

{ =============================================================================== }

function StrToVirtualKey(const S: string): Byte;
var
  Upper: string;
begin
  Upper := UpperCase(S);
  if Upper = 'BACKSPACE' then
    Result := $08
  else if Upper = 'CAPSLOCK' then
    Result := $14
  else if Upper = 'SPACE' then
    Result := $20
  else if Upper = 'MENU' then
    Result := $5D
  else if Upper = 'ENTER' then
    Result := $0D
  else if Upper = 'ESC' then
    Result := $1B
  else if Upper = 'TAB' then
    Result := $09
  else if Upper = 'DELETE' then
    Result := $2E
  else if Upper = 'INSERT' then
    Result := $2D
  else if Upper = 'HOME' then
    Result := $24
  else if Upper = 'END' then
    Result := $23
  else if Upper = 'PAGEUP' then
    Result := $21
  else if Upper = 'PAGEDOWN' then
    Result := $22
  else if Upper = 'UP' then
    Result := $26
  else if Upper = 'DOWN' then
    Result := $28
  else if Upper = 'LEFT' then
    Result := $25
  else if Upper = 'RIGHT' then
    Result := $27
  else if (Length(Upper) = 5) and (Copy(Upper, 1, 4) = 'NUM ') and (Upper[5] in ['0' .. '9']) then
    Result := $60 + Ord(Upper[5]) - Ord('0')
  else if Upper = 'NUM *' then
    Result := $6A
  else if (Upper = 'NUM PLUS') or (Upper = 'NUM +') then
    Result := $6B
  else if (Upper = 'NUM SEP') or (Upper = 'NUM SEPARATOR') then
    Result := $6C
  else if (Upper = 'NUM -') or (Upper = 'NUM SUBTRACT') then
    Result := $6D
  else if (Upper = 'NUM .') or (Upper = 'NUM DECIMAL') then
    Result := $6E
  else if (Upper = 'NUM /') or (Upper = 'NUM DIVIDE') then
    Result := $6F
  else if (Length(Upper) = 1) and (Upper[1] in ['0' .. '9']) then
    Result := Ord(Upper[1])
  else if (Length(Upper) = 1) and (Upper[1] in ['A' .. 'Z']) then
    Result := Ord(Upper[1])
  else if Upper = 'F1' then
    Result := $70
  else if Upper = 'F2' then
    Result := $71
  else if Upper = 'F3' then
    Result := $72
  else if Upper = 'F4' then
    Result := $73
  else if Upper = 'F5' then
    Result := $74
  else if Upper = 'F6' then
    Result := $75
  else if Upper = 'F7' then
    Result := $76
  else if Upper = 'F8' then
    Result := $77
  else if Upper = 'F9' then
    Result := $78
  else if Upper = 'F10' then
    Result := $79
  else if Upper = 'F11' then
    Result := $7A
  else if Upper = 'F12' then
    Result := $7B
  else if Upper = ';' then
    Result := $BA
  else if Upper = '=' then
    Result := $BB
  else if Upper = ',' then
    Result := $BC
  else if Upper = '-' then
    Result := $BD
  else if Upper = '.' then
    Result := $BE
  else if Upper = '/' then
    Result := $BF
  else if Upper = '`' then
    Result := $C0
  else if Upper = '[' then
    Result := $DB
  else if Upper = '\' then
    Result := $DC
  else if Upper = ']' then
    Result := $DD
  else if Upper = '''' then
    Result := $DE
  else
    { Unknown text is not Space: that fallback used to make any unparseable
      setting ("VK97", a typo) match the space bar.  Zero never equals a real
      key code, so an unreadable setting simply never fires. }
    Result := 0;
end;

{ =============================================================================== }

function UserHotkeyToString(Index: Integer): string;
begin
  if (index < 0) or (index >= Length(UserHotkeys)) then
  begin
    Result := '';
    Exit;
  end;
  Result := ModifierMaskToStr(UserHotkeys[index].ModifierMask) + '+' + VirtualKeyToStr(UserHotkeys[index].VirtualKey) + '  ->  ' +
    UserHotkeys[index].ReplacementText;
end;

{ =============================================================================== }

procedure SaveUserHotkeysToXML;
var
  XML:             TXMLSetting;
  I, Count:        Integer;
  ModsStr, KeyStr: string;
begin
  XML := TXMLSetting.Create;
  XML.LoadXMLData;

  Count := Length(UserHotkeys);
  XML.SetValue('UserHotkeyCount', Count);

  for I := 0 to Count - 1 do
  begin
    ModsStr := IntToStr(UserHotkeys[I].ModifierMask);
    KeyStr := VirtualKeyToStr(UserHotkeys[I].VirtualKey);
    XML.SetValue('UserHotkey_' + IntToStr(I) + '_Mods', ModsStr);
    XML.SetValue('UserHotkey_' + IntToStr(I) + '_Key', KeyStr);
    XML.SetValue('UserHotkey_' + IntToStr(I) + '_Text', UserHotkeys[I].ReplacementText);
  end;

  XML.SaveXMLData;
  XML.Free;
end;

{ =============================================================================== }

procedure LoadUserHotkeysFromXML;
var
  XML:                      TXMLSetting;
  I, Count:                 Integer;
  ModsStr, KeyStr, TextStr: string;
begin
  ClearUserHotkeys;

  XML := TXMLSetting.Create;
  XML.LoadXMLData;

  Count := StrToIntDef(XML.GetValue('UserHotkeyCount', '0'), 0);

  for I := 0 to Count - 1 do
  begin
    ModsStr := XML.GetValue('UserHotkey_' + IntToStr(I) + '_Mods', '0');
    KeyStr := XML.GetValue('UserHotkey_' + IntToStr(I) + '_Key', 'Space');
    TextStr := XML.GetValue('UserHotkey_' + IntToStr(I) + '_Text', '');
    AddUserHotkey(StrToIntDef(ModsStr, 0), StrToVirtualKey(KeyStr), TextStr);
  end;

  XML.Free;
end;

{ =============================================================================== }

// Parse "Ctrl+Shift+F12" into modifier bitmask
function HotkeyStringToModifiers(const S: string): Byte;
var
  Parts: TStringList;
  I:     Integer;
  Part:  string;
begin
  Result := 0;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '+';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;

    for I := 0 to Parts.Count - 1 do
    begin
      Part := Trim(UpperCase(Parts[I]));
      if Part = 'CTRL' then
        Result := Result or MOD_CTRL
      else if Part = 'SHIFT' then
        Result := Result or MOD_SHIFT
      else if Part = 'ALT' then
        Result := Result or MOD_ALT
      else if Part = 'WIN' then
        Result := Result or MOD_WIN;
    end;
  finally
    Parts.Free;
  end;
end;

{ =============================================================================== }

// Parse "Ctrl+Shift+F12" into the main key virtual key code
function HotkeyStringToKey(const S: string): Integer;
var
  Parts:    TStringList;
  LastPart: string;
begin
  Result := 0;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '+';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;

    if Parts.Count > 0 then
    begin
      LastPart := Trim(Parts[Parts.Count - 1]);
      Result := StrToVirtualKey(LastPart);
    end;
  finally
    Parts.Free;
  end;
end;

{ =============================================================================== }

// Parse a hotkey setting string ("SHIFT + F5", "CTRL+ALT+T", "F7") into a VCL
// menu TShortCut so RefreshSettings can show it next to the matching menu
// item.  Vcl.Menus.TextToShortCut cannot read what the recorder and the
// registry actually store (uppercase, " + " spacing) and answers 0, leaving
// the menu blank - so this reuses the same two parsers the low-level hook
// fires with, which are Trim/UpperCase tolerant by construction.  A Win
// modifier has no bit in a TShortCut (VCL knows only Ctrl/Shift/Alt), so
// those settings return 0: a menu must not advertise a shortcut it cannot
// render.
function HotkeyStringToShortCut(const Setting: string): TShortCut;
var
  Mods:  Byte;
  Key:   Integer;
  Shift: TShiftState;
begin
  Result := 0;
  if (Setting = '') or (UpperCase(Setting) = 'NONE') then
    Exit;

  Mods := HotkeyStringToModifiers(Setting);
  if (Mods and MOD_WIN) <> 0 then
    Exit;

  Key := HotkeyStringToKey(Setting);
  if Key = 0 then
    Exit;

  Shift := [];
  if (Mods and MOD_CTRL) <> 0 then
    Include(Shift, ssCtrl);
  if (Mods and MOD_SHIFT) <> 0 then
    Include(Shift, ssShift);
  if (Mods and MOD_ALT) <> 0 then
    Include(Shift, ssAlt);

  Result := ShortCut(Key, Shift);
end;

{ =============================================================================== }

// Build "Ctrl+Shift+F12" from modifier mask and VK code
function KeyToHotkeyString(Mods: Byte; VK: Integer): string;
begin
  Result := ModifierMaskToStr(Mods);
  if Result <> '' then
    Result := Result + '+';
  Result := Result + VirtualKeyToStr(VK);
end;

{ =============================================================================== }

// Check if current key state matches a hotkey setting string
function MatchesHotkeySetting(const Setting: string; vkCode: Integer): Boolean;
begin
  Result := HotkeySettingMatchesVk(Setting, vkCode, ModifierMaskFromState);
end;

function HotkeySettingMatchesVk(const Setting: string; AKey: Integer; Mods: Byte): Boolean;
var
  NeedMods: Byte;
  NeedKey:  Integer;
begin
  Result := False;
  if (Setting = '') or (Setting = 'NONE') then
    Exit;

  NeedMods := HotkeyStringToModifiers(Setting);
  NeedKey := HotkeyStringToKey(Setting);
  Result := (NeedKey <> 0) and (NeedMods = Mods) and (NeedKey = AKey);
end;

function NormalizeHotkeyVk(AKey, ScanCode: Integer; Extended: Boolean): Integer;
begin
  Result := AKey;

  { A keypad key always reports a non-extended scan code, while every dedicated
    arrow/navigation key is extended.  Windows turns the keypad into the shared
    navigation VKs whenever NumLock is off - and also while Shift is held, even
    though GetKeyState still reports NumLock as on (Shift overrides NumLock).
    The scan code is therefore the only reliable way to tell "Num 8" from "Up";
    do not consult the NumLock toggle here. }
  if Extended then
    Exit;

  // Already a keypad VK: Windows already reported the keypad key itself.
  if (AKey >= VK_NUMPAD0) and (AKey <= VK_DIVIDE) then
    Exit;

  case ScanCode of
    $47: Result := VK_NUMPAD7;
    $48: Result := VK_NUMPAD8;
    $49: Result := VK_NUMPAD9;
    $4B: Result := VK_NUMPAD4;
    $4C: Result := VK_NUMPAD5;
    $4D: Result := VK_NUMPAD6;
    $4F: Result := VK_NUMPAD1;
    $50: Result := VK_NUMPAD2;
    $51: Result := VK_NUMPAD3;
    $52: Result := VK_NUMPAD0;
    $53: Result := VK_DECIMAL;
  end;
end;

{ =============================================================================== }

function HotkeyKeyNeedsOwnPaint(VK: Integer): Boolean;
begin
  Result := VK in [
    VK_INSERT, VK_DELETE, VK_HOME, VK_END, VK_PRIOR, VK_NEXT,
    VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN,
    VK_SEPARATOR, VK_DECIMAL, VK_DIVIDE];
end;

{ =============================================================================== }

function HotkeysEqual(const A, B: string): Boolean;
begin
  Result := (HotkeyStringToModifiers(A) = HotkeyStringToModifiers(B)) and (HotkeyStringToKey(A) = HotkeyStringToKey(B));
end;

{ =============================================================================== }

function IsBareHotkeyKey(VK: Integer): Boolean;
begin
  Result := ((VK >= VK_F1) and (VK <= VK_F12)) or { F1..F12 }
    ((VK >= VK_PRIOR) and (VK <= VK_DOWN)) or { PgUp, PgDn, End, Home, arrows }
    (VK = VK_INSERT) or
    ((VK >= VK_NUMPAD0) and (VK <= VK_DIVIDE)); { the numeric keypad }
end;

end.
