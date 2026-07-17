{$INCLUDE ../ProjectDefines.inc}

Unit uKeyboardMacro;

Interface

Uses
  Classes,
  Graphics,
  StdCtrls; // For TEdit

Const
  MOD_CTRL  = 1;
  MOD_SHIFT = 2;
  MOD_ALT   = 4;
  MOD_WIN   = 8;

Type
  TUserHotkey = record
    ModifierMask: Byte;
    VirtualKey: Byte;
    ReplacementText: string;
  end;

  TUserHotkeyArray = array of TUserHotkey;

Var
  UserHotkeys: TUserHotkeyArray;

  // Hotkey Recording State
  IsRecordingHotkey: Boolean;
  RecordingTargetEdit: TEdit;

type
  THotkeyFeature = record
    VariablePtr: PString;
    DisplayName: string;
    EditRef: TEdit;
  end;

var
  HotkeyFeatures: array of THotkeyFeature;
  RecordingOldText: string;

procedure RegisterHotkeyFeature(VarPtr: PString; const Name: string; Edit: TEdit);
function  FindConflictingFeature(const Hotkey: string; SourceEdit: TEdit): Integer;
function  ResolveHotkeyConflict(const NewHotkey: string; ConflictingIndex: Integer): Boolean;
function  HotkeysEqual(const A, B: string): Boolean;
procedure ClearConflictByIndex(Idx: Integer);
function  GetConflictDisplayName(Idx: Integer): string;

Procedure AddUserHotkey(Mods: Byte; Key: Byte; const Text: string);
Procedure RemoveUserHotkey(Index: Integer);
Procedure ClearUserHotkeys;
Function MatchUserHotkey(vkCode: Integer; var OutText: string): Boolean;
Function ModifierMaskFromState: Byte;
Function UserHotkeyToString(Index: Integer): string;
Procedure SaveUserHotkeysToXML;
Procedure LoadUserHotkeysFromXML;

// Hotkey string helpers
Function HotkeyStringToModifiers(const S: string): Byte;
Function HotkeyStringToKey(const S: string): Integer;
Function KeyToHotkeyString(Mods: Byte; VK: Integer): string;
Function MatchesHotkeySetting(const Setting: string; vkCode: Integer): Boolean;
Function VirtualKeyToStr(VK: Byte): string;

Implementation

Uses
  Forms,
  SysUtils,
  Windows,
  KeyboardFunctions,
  clsRegistry_XMLSetting;

{ =============================================================================== }

Function ModifierMaskFromState: Byte;
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

Procedure AddUserHotkey(Mods: Byte; Key: Byte; const Text: string);
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

Procedure RemoveUserHotkey(Index: Integer);
var
  I, Count: Integer;
begin
  Count := Length(UserHotkeys);
  if (Index < 0) or (Index >= Count) then
    Exit;

  for I := Index to Count - 2 do
    UserHotkeys[I] := UserHotkeys[I + 1];

  SetLength(UserHotkeys, Count - 1);
end;

{ =============================================================================== }

Procedure ClearUserHotkeys;
begin
  SetLength(UserHotkeys, 0);
end;

{ =============================================================================== }

Function MatchUserHotkey(vkCode: Integer; var OutText: string): Boolean;
var
  I: Integer;
  CurrentMods: Byte;
begin
  Result := False;
  OutText := '';
  CurrentMods := ModifierMaskFromState;

  for I := 0 to Length(UserHotkeys) - 1 do
  begin
    if (UserHotkeys[I].VirtualKey = vkCode) and
       (UserHotkeys[I].ModifierMask = CurrentMods) then
    begin
      OutText := UserHotkeys[I].ReplacementText;
      Result := True;
      Exit;
    end;
  end;
end;

{ =============================================================================== }

Function ModifierMaskToStr(Mask: Byte): string;
begin
  Result := '';
  if (Mask and MOD_CTRL) <> 0 then
  begin
    if Result <> '' then Result := Result + '+';
    Result := Result + 'Ctrl';
  end;
  if (Mask and MOD_SHIFT) <> 0 then
  begin
    if Result <> '' then Result := Result + '+';
    Result := Result + 'Shift';
  end;
  if (Mask and MOD_ALT) <> 0 then
  begin
    if Result <> '' then Result := Result + '+';
    Result := Result + 'Alt';
  end;
  if (Mask and MOD_WIN) <> 0 then
  begin
    if Result <> '' then Result := Result + '+';
    Result := Result + 'Win';
  end;
end;

{ =============================================================================== }

Function VirtualKeyToStr(VK: Byte): string;
begin
  case VK of
    $08: Result := 'Backspace';
    $14: Result := 'CapsLock';
    $20: Result := 'Space';
    $30..$39: Result := Chr(VK);
    $41..$5A: Result := Chr(VK);
    $5D: Result := 'Menu';
    $70: Result := 'F1';
    $71: Result := 'F2';
    $72: Result := 'F3';
    $73: Result := 'F4';
    $74: Result := 'F5';
    $75: Result := 'F6';
    $76: Result := 'F7';
    $77: Result := 'F8';
    $78: Result := 'F9';
    $79: Result := 'F10';
    $7A: Result := 'F11';
    $7B: Result := 'F12';
    $0D: Result := 'Enter';
    $1B: Result := 'Esc';
    $09: Result := 'Tab';
    $2E: Result := 'Delete';
    $2D: Result := 'Insert';
    $24: Result := 'Home';
    $23: Result := 'End';
    $21: Result := 'PageUp';
    $22: Result := 'PageDown';
    $26: Result := 'Up';
    $28: Result := 'Down';
    $25: Result := 'Left';
    $27: Result := 'Right';
    $BA: Result := ';';
    $BB: Result := '=';
    $BC: Result := ',';
    $BD: Result := '-';
    $BE: Result := '.';
    $BF: Result := '/';
    $C0: Result := '`';
    $DB: Result := '[';
    $DC: Result := '\';
    $DD: Result := ']';
    $DE: Result := '''';
  else
    Result := 'VK' + IntToStr(VK);
  end;
end;

{ =============================================================================== }

Function StrToVirtualKey(const S: string): Byte;
var
  Upper: string;
begin
  Upper := UpperCase(S);
  if Upper = 'BACKSPACE' then Result := $08
  else if Upper = 'CAPSLOCK' then Result := $14
  else if Upper = 'SPACE' then Result := $20
  else if Upper = 'MENU' then Result := $5D
  else if Upper = 'ENTER' then Result := $0D
  else if Upper = 'ESC' then Result := $1B
  else if Upper = 'TAB' then Result := $09
  else if Upper = 'DELETE' then Result := $2E
  else if Upper = 'INSERT' then Result := $2D
  else if Upper = 'HOME' then Result := $24
  else if Upper = 'END' then Result := $23
  else if Upper = 'PAGEUP' then Result := $21
  else if Upper = 'PAGEDOWN' then Result := $22
  else if Upper = 'UP' then Result := $26
  else if Upper = 'DOWN' then Result := $28
  else if Upper = 'LEFT' then Result := $25
  else if Upper = 'RIGHT' then Result := $27
  else if (Length(Upper) = 1) and (Upper[1] in ['0'..'9']) then Result := Ord(Upper[1])
  else if (Length(Upper) = 1) and (Upper[1] in ['A'..'Z']) then Result := Ord(Upper[1])
  else if Upper = 'F1' then Result := $70
  else if Upper = 'F2' then Result := $71
  else if Upper = 'F3' then Result := $72
  else if Upper = 'F4' then Result := $73
  else if Upper = 'F5' then Result := $74
  else if Upper = 'F6' then Result := $75
  else if Upper = 'F7' then Result := $76
  else if Upper = 'F8' then Result := $77
  else if Upper = 'F9' then Result := $78
  else if Upper = 'F10' then Result := $79
  else if Upper = 'F11' then Result := $7A
  else if Upper = 'F12' then Result := $7B
  else if Upper = ';' then Result := $BA
  else if Upper = '=' then Result := $BB
  else if Upper = ',' then Result := $BC
  else if Upper = '-' then Result := $BD
  else if Upper = '.' then Result := $BE
  else if Upper = '/' then Result := $BF
  else if Upper = '`' then Result := $C0
  else if Upper = '[' then Result := $DB
  else if Upper = '\' then Result := $DC
  else if Upper = ']' then Result := $DD
  else if Upper = '''' then Result := $DE
  else Result := $20;
end;

{ =============================================================================== }

Function UserHotkeyToString(Index: Integer): string;
begin
  if (Index < 0) or (Index >= Length(UserHotkeys)) then
  begin
    Result := '';
    Exit;
  end;
  Result := ModifierMaskToStr(UserHotkeys[Index].ModifierMask)
    + '+' + VirtualKeyToStr(UserHotkeys[Index].VirtualKey)
    + '  ->  ' + UserHotkeys[Index].ReplacementText;
end;

{ =============================================================================== }

Procedure SaveUserHotkeysToXML;
var
  XML: TXMLSetting;
  I, Count: Integer;
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

Procedure LoadUserHotkeysFromXML;
var
  XML: TXMLSetting;
  I, Count: Integer;
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
Function HotkeyStringToModifiers(const S: string): Byte;
var
  Parts: TStringList;
  I: Integer;
  Part: string;
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
      if Part = 'CTRL' then Result := Result or MOD_CTRL
      else if Part = 'SHIFT' then Result := Result or MOD_SHIFT
      else if Part = 'ALT' then Result := Result or MOD_ALT
      else if Part = 'WIN' then Result := Result or MOD_WIN;
    end;
  finally
    Parts.Free;
  end;
end;

{ =============================================================================== }

// Parse "Ctrl+Shift+F12" into the main key virtual key code
Function HotkeyStringToKey(const S: string): Integer;
var
  Parts: TStringList;
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

// Build "Ctrl+Shift+F12" from modifier mask and VK code
Function KeyToHotkeyString(Mods: Byte; VK: Integer): string;
begin
  Result := ModifierMaskToStr(Mods);
  if Result <> '' then
    Result := Result + '+';
  Result := Result + VirtualKeyToStr(VK);
end;

{ =============================================================================== }

// Check if current key state matches a hotkey setting string
Function MatchesHotkeySetting(const Setting: string; vkCode: Integer): Boolean;
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
  CurrentMods := ModifierMaskFromState;

  Result := (NeedMods = CurrentMods) and (NeedKey = vkCode);
end;

{ =============================================================================== }

function HotkeysEqual(const A, B: string): Boolean;
begin
  Result := (HotkeyStringToModifiers(A) = HotkeyStringToModifiers(B)) and
            (HotkeyStringToKey(A) = HotkeyStringToKey(B));
end;

{ =============================================================================== }

procedure RegisterHotkeyFeature(VarPtr: PString; const Name: string; Edit: TEdit);
var
  Len: Integer;
begin
  Len := Length(HotkeyFeatures);
  SetLength(HotkeyFeatures, Len + 1);
  HotkeyFeatures[Len].VariablePtr := VarPtr;
  HotkeyFeatures[Len].DisplayName := Name;
  HotkeyFeatures[Len].EditRef := Edit;
end;

{ =============================================================================== }

function FindConflictingFeature(const Hotkey: string; SourceEdit: TEdit): Integer;
var
  I: Integer;
  UpperHotkey: string;
  EditTxt: string;
begin
  Result := -1;
  if (Hotkey = '') or (Hotkey = 'NONE') then
    Exit;
  UpperHotkey := UpperCase(Hotkey);
  // Check all registered features — compare against TEdit.Text, not VariablePtr^
  for I := 0 to Length(HotkeyFeatures) - 1 do
  begin
    if HotkeyFeatures[I].EditRef = SourceEdit then
      Continue;
    EditTxt := UpperCase(HotkeyFeatures[I].EditRef.Text);
    if (EditTxt <> '') and (EditTxt <> 'NONE') and (EditTxt <> 'PRESS ANY KEY...') and
       HotkeysEqual(UpperHotkey, EditTxt) then
    begin
      Result := I;
      Exit;
    end;
  end;
  // Also check UserHotkeys array
  for I := 0 to Length(UserHotkeys) - 1 do
  begin
    if HotkeysEqual(UpperHotkey,
       UpperCase(KeyToHotkeyString(UserHotkeys[I].ModifierMask, UserHotkeys[I].VirtualKey))) then
    begin
      Result := Length(HotkeyFeatures) + I;
      Exit;
    end;
  end;
end;

{ =============================================================================== }

function ResolveHotkeyConflict(const NewHotkey: string; ConflictingIndex: Integer): Boolean;
var
  Msg: string;
  Ret: Integer;
  FeatureName: string;
begin
  Result := False;
  FeatureName := GetConflictDisplayName(ConflictingIndex);
  Msg := 'The hotkey "' + NewHotkey + '" conflicts with the hotkey selected for "' +
         FeatureName + '". ' +
         'If you continue, the hotkey for "' + FeatureName +
         '" will be cleared. Continue?';
  Ret := Application.MessageBox(PChar(Msg), 'Hotkey Conflict',
                                MB_YESNOCANCEL or MB_ICONWARNING or MB_DEFBUTTON3);
  if Ret = IDYES then
    Result := True;
end;

{ =============================================================================== }

function GetConflictDisplayName(Idx: Integer): string;
var
  FeatureCount: Integer;
begin
  FeatureCount := Length(HotkeyFeatures);
  if Idx < FeatureCount then
    Result := HotkeyFeatures[Idx].DisplayName
  else
    Result := 'Custom Macro';
end;

{ =============================================================================== }

procedure ClearConflictByIndex(Idx: Integer);
var
  FeatureCount: Integer;
begin
  FeatureCount := Length(HotkeyFeatures);
  if Idx < FeatureCount then
  begin
    // Only update the UI — actual variable cleared by SaveSettings on OK/Apply
    if Assigned(HotkeyFeatures[Idx].EditRef) then
    begin
      HotkeyFeatures[Idx].EditRef.Text := 'None';
      HotkeyFeatures[Idx].EditRef.Color := clWindow;
    end;
  end
  else
  begin
    RemoveUserHotkey(Idx - FeatureCount);
  end;
end;

{ =============================================================================== }

End.
