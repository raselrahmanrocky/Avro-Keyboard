{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
{ COMPLETE TRANSFERING! }

unit clsLayout;

interface

uses
  classes,
  sysutils,
  StrUtils,
  clsAvroPhonetic,
  clsGenericLayoutModern,
  clsGenericLayoutOld,
  Forms,
  Windows;

// --------------------------------------------------------------
// Enumarated types
type
  enumMode = (SysDefault, Bangla);

type
  // Event types
  // --------------------------------------------------------------
  TKeyboardModeChanged   = procedure(CurrentMode: enumMode) of object;
  TWordTrackingLost      = procedure of object; // Special for Avro phonetic
  TKeyboardLayoutChanged = procedure(CurrentKeyboardLayout: string) of object;
  THookSet               = procedure of object;
  THookSettingFailed     = procedure of object;
  // --------------------------------------------------------------

type
  // Skeleton of TLayout class
  // --------------------------------------------------------------
  TLayout = class
    private
      AvroPhonetic:       TAvroPhonetic;
      GenericModernFixed: TGenericLayoutModern;
      GenericOldFixed:    TGenericLayoutOld;

      k_Layout: string;
      k_Mode:   enumMode;

      // --------------------------------------------------------------
      // Event types
      FKeyboardModeChanged:   TKeyboardModeChanged;
      FWordTrackingLost:      TWordTrackingLost;
      FKeyboardLayoutChanged: TKeyboardLayoutChanged;
      FHookSet:               THookSet;
      FHookSettingFailed:     THookSettingFailed;
      // --------------------------------------------------------------

      procedure SetAutoCorrectEnabled(const Value: Boolean);
      function GetAutoCorrectEnabled: Boolean;
      procedure SetCurrentKeyboardLayout(Value: string);
      function GetCurrentKeyboardLayout: string;
      procedure SetKeyboardMode(const Value: enumMode);
      function GetKeyboardMode: enumMode;
    public
      constructor Create;           // Initializer
      destructor Destroy; override; // Destructor

      function ProcessVKeyDown(const KeyCode: Integer; var Block: Boolean): string;
      procedure ProcessVKeyUP(const KeyCode: Integer; var Block: Boolean);
      procedure ResetDeadKey;
      { Tells every engine that the text in front of the caret is no longer
        theirs to describe (a foreground change, a layout or mode switch, the
        engine being parked): their committed ledgers are dropped and the cached
        caret reading is dropped with them, so the next Backspace reads again
        instead of erasing in a document the ledger never typed into. }
      procedure InvalidateAnsiTail;
      procedure FlushEmit; // Deferred output: drains the old-style layout emit queue
      procedure ToggleMode;
      procedure BanglaMode;
      procedure SysMode;
      procedure SelectCandidate(const Item: string); // For Phonetic

      // Published
      // --------------------------------------------------------------
      // event properties
      property OnKeyboardModeChanged: TKeyboardModeChanged read FKeyboardModeChanged write FKeyboardModeChanged;
      property OnWordTrackingLost: TWordTrackingLost read FWordTrackingLost write FWordTrackingLost;
      property OnKeyboardLayoutChanged: TKeyboardLayoutChanged read FKeyboardLayoutChanged write FKeyboardLayoutChanged;
      property OnHookSet: THookSet read FHookSet write FHookSet;
      property OnHookSettingFailed: THookSettingFailed read FHookSettingFailed write FHookSettingFailed;
      // --------------------------------------------------------------

      property AutoCorrectEnabled: Boolean read GetAutoCorrectEnabled write SetAutoCorrectEnabled;
      property CurrentKeyboardLayout: string read GetCurrentKeyboardLayout write SetCurrentKeyboardLayout;
      property KeyboardMode: enumMode read GetKeyboardMode write SetKeyboardMode;

  end;

implementation

uses
  KeyboardHook,
  KeyboardLayoutLoader,
  uAnsiBackspace,
  uRegistrySettings;

{ TLayout }

{ =============================================================================== }

procedure TLayout.BanglaMode;
begin
  Self.KeyboardMode := Bangla;
end;

{ =============================================================================== }

constructor TLayout.Create;
var
  RetVal: Integer;
begin
  inherited;
  RetVal := Sethook;

  if RetVal > 0 then
  begin
    if Assigned(FHookSet) then
      FHookSet;
  end
  else
  begin
    if Assigned(FHookSettingFailed) then
      FHookSettingFailed;
  end;

  AvroPhonetic := TAvroPhonetic.Create;
  GenericModernFixed := TGenericLayoutModern.Create;
  GenericOldFixed := TGenericLayoutOld.Create;

  Self.KeyboardMode := SysDefault;
  k_Layout := 'avrophonetic*';
end;

{ =============================================================================== }

destructor TLayout.Destroy;
begin

  Removehook;

  FreeAndNil(AvroPhonetic);
  FreeAndNil(GenericModernFixed);
  FreeAndNil(GenericOldFixed);
  inherited;
end;

{ =============================================================================== }

function TLayout.GetAutoCorrectEnabled: Boolean;
begin
  Result := AvroPhonetic.AutoCorrectEnabled;
end;

{ =============================================================================== }

function TLayout.GetCurrentKeyboardLayout: string;
begin
  Result := k_Layout;
end;

{ =============================================================================== }

function TLayout.GetKeyboardMode: enumMode;
begin
  Result := k_Mode;
end;

{ =============================================================================== }

function TLayout.ProcessVKeyDown(const KeyCode: Integer; var Block: Boolean): string;
begin
  if Lowercase(k_Layout) = 'avrophonetic*' then
    ProcessVKeyDown := AvroPhonetic.ProcessVKeyDown(KeyCode, Block)
  else
  begin
    if FullOldStyleTyping <> 'YES' then
      ProcessVKeyDown := GenericModernFixed.ProcessVKeyDown(KeyCode, Block)
    else
      ProcessVKeyDown := GenericOldFixed.ProcessVKeyDown(KeyCode, Block);
  end;
end;

{ =============================================================================== }

procedure TLayout.ProcessVKeyUP(const KeyCode: Integer; var Block: Boolean);
begin
  if Lowercase(k_Layout) = 'avrophonetic*' then
    AvroPhonetic.ProcessVKeyUP(KeyCode, Block)
  else
  begin
    if FullOldStyleTyping <> 'YES' then
      GenericModernFixed.ProcessVKeyUP(KeyCode, Block)
    else
      GenericOldFixed.ProcessVKeyUP(KeyCode, Block);
  end;
end;

{ =============================================================================== }

procedure TLayout.ResetDeadKey;
begin
  AvroPhonetic.ResetDeadKey;
  GenericModernFixed.ResetDeadKey;
  GenericOldFixed.ResetDeadKey;

  { A layout / mode switch or a foreground change reaches the engines here, so
    the tail that no longer describes the caret goes with it - the next
    Backspace reads again instead of trusting a ledger from another window. }
  InvalidateAnsiTail;
end;

{ =============================================================================== }

procedure TLayout.InvalidateAnsiTail;
begin
  { Every engine gets the message, whether or not it currently answers keys -
    the engine that was active a moment ago is exactly the one whose ledger
    would be stale. }
  if Assigned(GenericModernFixed) then
    GenericModernFixed.InvalidateAnsiTail;
  if Assigned(GenericOldFixed) then
    GenericOldFixed.InvalidateAnsiTail;
  if Assigned(AvroPhonetic) then
    AvroPhonetic.InvalidateAnsiTail;

  { The cached reading of the host text goes too: it described a document the
    press may no longer be looking at. }
  AnsiBackspaceInvalidate;
end;

{ =============================================================================== }

{ Deferred output (see clsGenericLayoutOld / AVRO_DEFER_EMIT).
  The old-style layout queues its SendInput work and posts WM_AVRO_EMIT; the
  main form forwards that message here, and the queue is drained OUTSIDE the
  low-level keyboard hook callback (the Raw Input Thread is blocked in there).
  The modern layout emits directly, so there is nothing to flush for it. }
procedure TLayout.FlushEmit;
begin
  if Assigned(GenericOldFixed) then
    GenericOldFixed.FlushEmit;
end;

{ =============================================================================== }

procedure TLayout.SelectCandidate(const Item: string);
begin
  AvroPhonetic.SelectCandidate(Item);
end;

procedure TLayout.SetAutoCorrectEnabled(const Value: Boolean);
begin
  AvroPhonetic.AutoCorrectEnabled := Value;
end;

{ =============================================================================== }

procedure TLayout.SetCurrentKeyboardLayout(Value: string);
var
  RetVal: Integer;
begin
  Removehook;

  if Lowercase(Value) <> 'avrophonetic*' then
  begin
    if Init_KeyboardLayout(Value) = False then
    begin
      Application.MessageBox(PChar('Error Loading ' + Value + ' keyboard layout!' + #10 + '' + #10 + 'Layout switched back to Avro Phonetic.'), 'Avro Keyboard',
        MB_OK + MB_ICONHAND + MB_DEFBUTTON1 + MB_APPLMODAL);
      Value := 'AvroPhonetic*';
    end;
  end;

  ResetDeadKey;
  k_Layout := Value;

  if Assigned(FKeyboardLayoutChanged) then
    FKeyboardLayoutChanged(k_Layout);

  RetVal := Sethook;

  if RetVal > 0 then
  begin
    if Assigned(FHookSet) then
      FHookSet;
  end
  else
  begin
    if Assigned(FHookSettingFailed) then
      FHookSettingFailed;
  end;
end;

{ =============================================================================== }

procedure TLayout.SetKeyboardMode(const Value: enumMode);
begin
  k_Mode := Value;
  if Assigned(FKeyboardModeChanged) then
    FKeyboardModeChanged(k_Mode);
  ResetDeadKey;
end;

{ =============================================================================== }

procedure TLayout.SysMode;
begin
  Self.KeyboardMode := SysDefault;
end;

{ =============================================================================== }

procedure TLayout.ToggleMode;
begin
  if Self.KeyboardMode = SysDefault then
    Self.KeyboardMode := Bangla
  else
    Self.KeyboardMode := SysDefault;
end;

{ =============================================================================== }

end.
