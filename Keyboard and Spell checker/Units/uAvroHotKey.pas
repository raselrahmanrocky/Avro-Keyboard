{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit uAvroHotKey;

interface

uses
  Windows,
  Messages,
  Classes,
  Controls,
  Graphics,
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  uKeyboardMacro;

type
  TAvroHotKey = class;

  { One configurable global hotkey: the registry string it owns, the name the
    conflict dialog shows, and the field that edits it. }
  THotkeyFeature = record
    VariablePtr: PString;
    DisplayName: string;
    Control:     TAvroHotKey;
  end;

  { THotKey as this application needs it.

    The field has to look and behave like a hotkey box - "None" when empty, the
    combination painted by the hot-key control itself, no recording highlight -
    but it must not be the recorder.  The Win32 hot-key control knows only
    Ctrl/Shift/Alt and refuses Enter/Tab/Space/Del/Esc/Backspace, while Avro
    has to be able to record every key, the Windows key included.  That is what
    the low-level keyboard hook already does (Units\KeyboardHook.pas), so the
    hook owns capture: while the field is focused it swallows the session and
    hands the finished combination to CommitCapture through
    HotkeyCaptureCommit.  Validation, the conflict dialog and the revert stay
    here, so the stored setting is still the same canonical registry string the
    hook matches with MatchesHotkeySetting.

    A Win combination has no representation in a TShortCut, so the hot-key
    control cannot paint it.  Such a value (and any key ShortCutToText cannot
    render) is painted by an overlay instead, which keeps it visible and
    - more importantly - keeps it from being silently lost when the dialog is
    saved.  The same overlay shows the modifiers while a combination is being
    pressed. }
  TAvroHotKey = class(THotKey)
  private
    FSetting: string;
    FOverlay: TPaintBox;
    { What the overlay paints while it covers the control ("Ctrl + " or a Win
      combination the native control cannot render). }
    FOverlayText: string;
    { The value the field had when it gained focus: Esc restores it. }
    FCaptureOld: string;
    { True between OnEnter and OnExit, i.e. while the hook may call us. }
    FCaptureArmed: Boolean;
    { True while a pressed-modifier preview is painted over the control. }
    FPreviewing: Boolean;
    { True between a successful CreateCaret and DestroyCaret.  The system caret
      belongs to the thread, not to this window, so it has to be torn down
      again when the field loses the focus. }
    FCaretCreated: Boolean;
    { The caret the overlay paints itself while it covers the field: the
      system caret is painted over by the overlay's text, so the overlay owns
      the caret and its blink while the preview is on screen. }
    FCaretTimer:   TTimer;
    FOverlayCaret: Boolean;
    procedure SetSetting(const Value: string);
    procedure StopCaret;
    procedure UpdateCaret;
    procedure CaretTimerTick(Sender: TObject);
    procedure StartOverlayCaret;
    procedure StopOverlayCaret;
    procedure PaintOverlayCaret;
    function DisplayedText: string;
    procedure UpdateDisplay;
    procedure UpdateOverlayBounds;
    procedure ShowOverlay(const Text: string);
    procedure OverlayPaint(Sender: TObject);
    procedure OverlayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ControlResize(Sender: TObject);
    procedure ControlEnter(Sender: TObject);
    procedure ControlExit(Sender: TObject);
    procedure EndCapture;
  protected
    procedure CreateWnd; override;
    procedure WndProc(var Message: TMessage); override;
    procedure SetParent(AParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Canonical registry string ("CTRL+ALT+T"); '' means "no hotkey". }
    property Setting: string read FSetting write SetSetting;
    { The text the field is painting right now, in the form the user sees it
      ("Ctrl + Up", "None").  Tests use it to prove that a dedicated arrow is
      not shown as its numpad look-alike. }
    property DisplayText: string read DisplayedText;
    { Called by the keyboard hook with a finished combination: '' reverts to
      the value the field had on focus, 'None' clears the field. }
    procedure CommitCapture(const Text: string);
    { Called by the keyboard hook while keys are still held: THotKey paints the
      pressed modifiers ("Ctrl + Alt + ") before a main key completes them.
      '' restores the committed value. }
    procedure PreviewCapture(const Text: string);
  end;

var
  HotkeyFeatures: array of THotkeyFeature;

procedure RegisterHotkeyFeature(VarPtr: PString; const Name: string; Control: TAvroHotKey);
function FindConflictingFeature(const Hotkey: string; Source: TAvroHotKey): Integer;
function ResolveHotkeyConflict(const NewHotkey: string; ConflictingIndex: Integer): Boolean;
procedure ClearConflictByIndex(Idx: Integer);
function GetConflictDisplayName(Idx: Integer): string;

{ True when the setting can be handed to a TShortCut (and therefore painted by
  the hot-key control itself).  An empty setting is "None" and is representable
  as 0; a Win modifier never is. }
function HotkeySettingToShortCut(const Setting: string; out SC: TShortCut): Boolean;

implementation

uses
  SysUtils,
  Menus,
  Forms;

{ =============================================================================== }

constructor TAvroHotKey.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  { The field is the display; the hook is the recorder.  THotKey's own modifier
    rules would still reject Shift+F5 style combinations (its default
    InvalidKeys is [hcNone, hcShift]) if anything ever reached the control.
    Those two properties are applied in CreateWnd: their setters talk to the
    native hot-key window, and touching the handle here would create it before
    the field has a parent - the EInvalidOperation that used to abort
    FormCreate. }
  TabStop := True;
  FSetting := '';

  { Overlay for values a TShortCut cannot hold (WIN+F8 and friends) and for the
    pressed-modifier preview.  It is a TPaintBox because it has to reproduce the
    hot-key control's own text layout exactly (see OverlayPaint); it sits on top
    of the client area, so it must not take the focus away from the control.
    Its parent is assigned in SetParent, not here: parenting a child to this
    control while this control itself still has no parent makes VCL ask for a
    window origin that does not exist yet and raises EInvalidOperation during
    FormCreate. }
  FOverlay := TPaintBox.Create(Self);
  FOverlay.ControlStyle := FOverlay.ControlStyle + [csOpaque];
  FOverlay.Visible := False;
  FOverlay.OnPaint := OverlayPaint;
  FOverlay.OnMouseDown := OverlayMouseDown;

  { While the overlay covers the field it paints the caret, so the blink
    belongs to this timer instead of the system caret. }
  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Enabled := False;
  FCaretTimer.OnTimer := CaretTimerTick;

  OnEnter := ControlEnter;
  OnExit := ControlExit;
  OnResize := ControlResize;
end;

{ =============================================================================== }

destructor TAvroHotKey.Destroy;
begin
  { A caret that is still owned when the dialog closes belongs to a window that
    is about to disappear, and the next control that wants a caret could not
    create one. }
  StopCaret;
  inherited Destroy;
end;

{ =============================================================================== }

procedure TAvroHotKey.ControlEnter(Sender: TObject);
begin
  FCaptureOld := FSetting;
  FCaptureArmed := True;
  HotkeyCaptureCommitted := False;
  HotkeyCaptureActive := True;
  HotkeyCaptureCommit := CommitCapture;
  HotkeyCapturePreview := PreviewCapture;
end;

{ =============================================================================== }

procedure TAvroHotKey.ControlExit(Sender: TObject);
begin
  EndCapture;
end;

{ =============================================================================== }

procedure TAvroHotKey.EndCapture;
begin
  HotkeyCaptureActive := False;
  HotkeyCaptureCommit := nil;
  HotkeyCapturePreview := nil;
  HotkeyCaptureCommitted := False;
  FCaptureArmed := False;
  { Leaving the field with modifiers still held must not leave the preview on
    screen; the committed value comes back. }
  if FPreviewing and not (csDestroying in ComponentState) then
    UpdateDisplay;
end;

{ =============================================================================== }

procedure TAvroHotKey.ControlResize(Sender: TObject);
begin
  if FOverlay.Visible then
    UpdateOverlayBounds;
end;

{ =============================================================================== }

procedure TAvroHotKey.CreateWnd;
begin
  inherited CreateWnd;
  { This setter sends HKM_SETRULES / HKM_SETHOTKEY to the native control.
    Doing it in the constructor would create the handle before the field has a
    parent and raise EInvalidOperation; here the window exists.  Emptying
    InvalidKeys lets a bare F-key be a legal shortcut.  Do not touch Modifiers
    here: in VCL it is the current/fallback modifier mask, and changing it from
    CreateWnd mutates FModifiers after ShortCutToHotKey has already prepared the
    real combination, which paints Ctrl+Alt+T as Ctrl+Shift+Alt+T. }
  InvalidKeys := [];
end;

{ =============================================================================== }

procedure TAvroHotKey.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if AParent = nil then
    Exit;
  { The field now has a parent window, so the overlay may safely join it. }
  if FOverlay.Parent = nil then
    FOverlay.Parent := Self;
  if FSetting <> '' then
    UpdateDisplay;
end;

{ =============================================================================== }
{ The caret

  A THotKey is the native hot-key control, not an edit control: Windows never
  creates a text caret for it, so a focused field gave no sign that it was ready
  for the next combination - Keyman's hotkey box blinks a caret in the same
  place - at the end of the text the field paints, "None" included, which is
  where Keyman's Change Hotkey dialog blinks it.  The caret added here is the
  SYSTEM caret (CreateCaret/ShowCaret): Windows owns the blink rate, the
  appearance, and hiding it while another window has the focus.  No timer and
  no repaint of the field are needed. }
{ =============================================================================== }

{ The canonical setting ("CTRL + SHIFT + NUM 7") as the field paints it
  ("Ctrl + Shift + Num 7").  Used for the values comctl32 cannot render itself,
  including every dedicated arrow: the native renderer drops the extended-key
  bit and would paint "CTRL + UP" as "Ctrl + Num 8". }
function HotkeySettingDisplayText(const Setting: string): string;
var
  Mods: Byte;
  Key:  Integer;
begin
  Key := HotkeyStringToKey(Setting);
  if Key = 0 then
    Exit(Setting);

  Mods := HotkeyStringToModifiers(Setting);
  Result := '';
  if (Mods and MOD_CTRL) <> 0 then
    Result := Result + 'Ctrl + ';
  if (Mods and MOD_SHIFT) <> 0 then
    Result := Result + 'Shift + ';
  if (Mods and MOD_ALT) <> 0 then
    Result := Result + 'Alt + ';
  if (Mods and MOD_WIN) <> 0 then
    Result := Result + 'Win + ';
  Result := Result + VirtualKeyToStr(Byte(Key));
end;

{ =============================================================================== }

function TAvroHotKey.DisplayedText: string;
var
  SC: TShortCut;
begin
  { Whatever the field is painting right now, so the caret lands where the next
    thing the user presses will appear. }
  if FOverlay.Visible then
    Exit(FOverlayText);
  if FSetting = '' then
    Exit('None'); { the hot-key control's placeholder for HotKey = 0 }
  if HotkeySettingToShortCut(FSetting, SC) and
    not HotkeyKeyNeedsOwnPaint(HotkeyStringToKey(FSetting)) then
    { comctl32 joins a combination with " + "; ShortCutToText uses a bare '+',
      so this is the text the native control actually paints (and measures). }
    Result := StringReplace(ShortCutToText(SC), '+', ' + ', [rfReplaceAll])
  else
    Result := HotkeySettingDisplayText(FSetting);
end;

{ =============================================================================== }

function CaretBlinkInterval: Integer;
var
  T: Cardinal;
begin
  T := GetCaretBlinkTime;
  if (T = 0) or (T = $FFFFFFFF) then
    T := 530;
  Result := T;
end;

procedure TAvroHotKey.StopCaret;
begin
  StopOverlayCaret;
  if not FCaretCreated then
    Exit;
  FCaretCreated := False;
  DestroyCaret;
end;

{ =============================================================================== }

procedure TAvroHotKey.CaretTimerTick(Sender: TObject);
begin
  if not (Focused and FOverlay.Visible) then
  begin
    StopOverlayCaret;
    Exit;
  end;
  FOverlayCaret := not FOverlayCaret;
  FOverlay.Invalidate;
end;

{ =============================================================================== }

procedure TAvroHotKey.StartOverlayCaret;
begin
  if not (Focused and FOverlay.Visible) then
    Exit;
  { Solid first, then blink: a value that just changed must not appear during
    the hidden half of the blink. }
  FOverlayCaret := True;
  FCaretTimer.Interval := CaretBlinkInterval;
  FCaretTimer.Enabled := True;
  FOverlay.Invalidate;
end;

{ =============================================================================== }

procedure TAvroHotKey.StopOverlayCaret;
begin
  FCaretTimer.Enabled := False;
  if not FOverlayCaret then
    Exit;
  FOverlayCaret := False;
  if FOverlay.Visible then
    FOverlay.Invalidate;
end;

{ =============================================================================== }

procedure TAvroHotKey.PaintOverlayCaret;
var
  X, Y, W, H: Integer;
begin
  { Same insertion point and text metrics as the text the overlay just painted. }
  X := GetSystemMetrics(SM_CXBORDER) + FOverlay.Canvas.TextWidth(FOverlayText);
  Y := GetSystemMetrics(SM_CYBORDER);
  W := MulDiv(1, Screen.PixelsPerInch, 96);
  if W < 1 then
    W := 1;
  H := FOverlay.Canvas.TextHeight('Wg');
  if X > FOverlay.ClientWidth - W then
    X := FOverlay.ClientWidth - W;
  if X < GetSystemMetrics(SM_CXBORDER) then
    X := GetSystemMetrics(SM_CXBORDER);
  if Y + H > FOverlay.ClientHeight then
    H := FOverlay.ClientHeight - Y;
  if H < 1 then
    H := 1;

  FOverlay.Canvas.Brush.Color := clWindowText;
  FOverlay.Canvas.FillRect(Rect(X, Y, X + W, Y + H));
end;

{ =============================================================================== }

procedure TAvroHotKey.UpdateCaret;
var
  DC:       HDC;
  SaveFont: HGDIOBJ;
  Size:     TSize;
  Text:     string;
  CaretW:   Integer;
  X, Y:     Integer;
begin
  if not (Focused and HandleAllocated and Visible) then
  begin
    StopCaret;
    Exit;
  end;

  { The overlay covers the field while a combination is being pressed and
    paints over the system caret, so the overlay draws and blinks its own
    caret instead.

    The caret to destroy is not necessarily ours: comctl32's own WM_SETFOCUS
    handler (HOTKEY_SetFocus) creates a caret right after the text it painted -
    for a Win combination that is the native "None" hidden under the overlay -
    and it only ever destroys that caret on WM_KILLFOCUS.  FCaretCreated says
    nothing about it, so destroy unconditionally; otherwise that native caret
    keeps blinking inside the overlay text while the overlay blinks its own
    caret at the end, which reads as two carets trading places. }
  if FOverlay.Visible then
  begin
    FCaretCreated := False;
    DestroyCaret;
    StartOverlayCaret;
    Exit;
  end;

  StopOverlayCaret;

  { The insertion point of the text the field is painting.  comctl32 draws that
    text at SM_CXBORDER/SM_CYBORDER from the client edge and clips it there, so
    the caret is one text width after that origin, inside the field. }
  Text := DisplayedText;
  FillChar(Size, SizeOf(Size), 0);
  DC := GetDC(Handle);
  if DC <> 0 then
  begin
    SaveFont := SelectObject(DC, Font.Handle);
    try
      GetTextExtentPoint32(DC, PChar(Text), Length(Text), Size);
    finally
      SelectObject(DC, SaveFont);
    end;
    ReleaseDC(Handle, DC);
  end;

  CaretW := MulDiv(1, Screen.PixelsPerInch, 96);
  if CaretW < 1 then
    CaretW := 1;

  X := GetSystemMetrics(SM_CXBORDER) + Size.cx;
  Y := GetSystemMetrics(SM_CYBORDER);
  if X > ClientWidth - CaretW then
    X := ClientWidth - CaretW;
  if X < GetSystemMetrics(SM_CXBORDER) then
    X := GetSystemMetrics(SM_CXBORDER);
  if Y + Size.cy > ClientHeight then
    Size.cy := ClientHeight - Y;
  if Size.cy < 1 then
    Size.cy := 1;

  { The caret is as tall as the text.  CreateCaret also restarts the blink, so a
    value that just changed is shown solid for one blink interval, exactly like
    an edit control after a keystroke. }
  if CreateCaret(Handle, 0, CaretW, Size.cy) then
  begin
    FCaretCreated := True;
    SetCaretPos(X, Y);
    ShowCaret(Handle);
  end;
end;

{ =============================================================================== }

procedure TAvroHotKey.OverlayMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  { A click anywhere in the field must start a recording session, exactly like
    a click on the hot-key control's own client area. }
  SetFocus;
end;

{ =============================================================================== }

procedure TAvroHotKey.UpdateOverlayBounds;
begin
  { The overlay has to cover the whole client area.  The native hot-key control
    paints "None" whenever HotKey is 0 and cannot paint a combination that is
    still being pressed, so anything smaller than the full client leaves part of
    that text visible under the preview.  OverlayPaint then reproduces the text
    position the control itself uses. }
  FOverlay.Left := 0;
  FOverlay.Top := 0;
  FOverlay.Width := ClientWidth;
  FOverlay.Height := ClientHeight;
  if FOverlay.Width < 1 then
    FOverlay.Width := 1;
  if FOverlay.Height < 1 then
    FOverlay.Height := 1;
end;

{ =============================================================================== }

procedure TAvroHotKey.OverlayPaint(Sender: TObject);
var
  X, Y: Integer;
begin
    { comctl32 paints a hot-key control with HOTKEY_DrawHotKey: window-colour
    background, the control's own font, window text colour, and the text one
    border away from the client edge (SM_CXBORDER/SM_CYBORDER) drawn with
    TextOut - not centred, not inset by any padding.  Painting the same way is
    what keeps a preview or a Win combination exactly where the real value
    sits, so the text does not jump when the keys are released.

    The overlay also paints the caret, because anything the field's window
    paints would cover the system caret until its next blink. }
  FOverlay.Canvas.Brush.Color := clWindow;
  FOverlay.Canvas.FillRect(FOverlay.ClientRect);

  FOverlay.Canvas.Font.Assign(Font);
  FOverlay.Canvas.Font.Color := clWindowText;
  X := GetSystemMetrics(SM_CXBORDER);
  Y := GetSystemMetrics(SM_CYBORDER);
  FOverlay.Canvas.TextOut(X, Y, FOverlayText);
  if FOverlayCaret then
    PaintOverlayCaret;
end;

{ =============================================================================== }

procedure TAvroHotKey.ShowOverlay(const Text: string);
begin
  { A held modifier repeats its key-down with the same preview text.  Showing
    the identical text again would repaint the field and restart the caret's
    blink on every repeat, which reads as a fast flicker instead of a caret;
    the preview is already on screen, so nothing has to change. }
  if FOverlay.Visible and (Text = FOverlayText) then
    Exit;

  FOverlayText := Text;
  UpdateOverlayBounds;
  if not FOverlay.Visible then
    FOverlay.Visible := True;
  FOverlay.Invalidate;
  { The caret follows the text the overlay paints. }
  UpdateCaret;
end;

{ =============================================================================== }

procedure TAvroHotKey.UpdateDisplay;
var
  SC:       TShortCut;
  Repr:     Boolean;
  OwnPaint: Boolean;
begin
  { Any real display refresh ends a pressed-modifier preview. }
  FPreviewing := False;

  if FSetting = '' then
  begin
    HotKey := 0; { the hot-key control paints "None" for 0 }
    FOverlay.Visible := False;
    UpdateCaret;
    Exit;
  end;

  { Keep the native control's state in step for everything a TShortCut can
    hold, but let the field paint itself whenever the native renderer would
    draw a different name than the setting means. }
  Repr := HotkeySettingToShortCut(FSetting, SC);
  if Repr then
    HotKey := SC
  else
    HotKey := 0;
  OwnPaint := (not Repr) or HotkeyKeyNeedsOwnPaint(HotkeyStringToKey(FSetting));

  if OwnPaint then
    { Not representable (a Win combination) or misnamed by comctl32 (every
      dedicated arrow is painted as its numpad twin). }
    ShowOverlay(HotkeySettingDisplayText(FSetting))
  else
  begin
    FOverlay.Visible := False;
    UpdateCaret;
  end;
end;

{ =============================================================================== }

procedure TAvroHotKey.PreviewCapture(const Text: string);
begin
  if Text = '' then
  begin
    { Keys released (or the combination completed): show the real value. }
    if FPreviewing then
      UpdateDisplay;
    Exit;
  end;

  { THotKey shows the held modifiers before a main key completes the
    combination, e.g. "Ctrl + Alt + ".  The native control cannot paint that
    without receiving the keys, and the hook deliberately swallows them, so the
    overlay paints the live text instead.  The committed setting is untouched:
    Esc can still restore it. }
  FPreviewing := True;
  { HKM_SETHOTKEY repaints the native control, so only send it when it would
    actually change - a held modifier repeats this call. }
  if HotKey <> 0 then
    HotKey := 0;
  ShowOverlay(Text);
end;

{ =============================================================================== }

procedure TAvroHotKey.SetSetting(const Value: string);
var
  S: string;
begin
  S := UpperCase(Trim(Value));
  if (S = 'NONE') or (S = 'SET SHORTCUT') or (S = 'PRESS ANY KEY...') then
    S := '';
  FSetting := S;
  UpdateDisplay;
end;

{ =============================================================================== }

procedure TAvroHotKey.CommitCapture(const Text: string);
var
  Old: string;
  Idx: Integer;
begin
  { '' is Esc: give up and restore the value this field had on focus. }
  if Text = '' then
  begin
    if FCaptureArmed then
      SetSetting(FCaptureOld)
    else
      UpdateDisplay;
    Exit;
  end;

  if SameText(Text, 'None') then
  begin
    SetSetting('');
    Exit;
  end;

  Old := FSetting;
  Idx := FindConflictingFeature(Text, Self);
  if Idx >= 0 then
  begin
    if not ResolveHotkeyConflict(Text, Idx) then
    begin
      { Cancelled: the field goes back to the value it had before. }
      SetSetting(Old);
      Exit;
    end;
    ClearConflictByIndex(Idx);
  end;

  SetSetting(Text);
end;

{ =============================================================================== }

{ The keyboard belongs to the hook while a capture session is running; anything
  that still reaches this window must not change the field behind the hook's
  back. }
procedure TAvroHotKey.WndProc(var Message: TMessage);
begin
  { Application deactivation does not always produce a VCL OnExit event.
    Stop consuming global keys as soon as this control loses keyboard focus. }
  if Message.Msg = WM_KILLFOCUS then
    EndCapture;

  if HotkeyCaptureActive then
    case Message.Msg of
      WM_KEYDOWN, WM_SYSKEYDOWN, WM_KEYUP, WM_SYSKEYUP, WM_CHAR, WM_SYSCHAR:
        begin
          Message.Result := 0;
          Exit;
        end;
    end;
  inherited WndProc(Message);

  { The system caret is drawn for the focused window only, and the focus can
    leave and come back without VCL sending OnEnter/OnExit again (a modal
    conflict dialog, a style switch, Alt+Tab).  Tie it to the window messages
    themselves so it is always in step with the real focus. }
  case Message.Msg of
    WM_SETFOCUS:
      UpdateCaret;
    WM_KILLFOCUS:
      StopCaret;
  end;
end;

{ =============================================================================== }

function HotkeySettingToShortCut(const Setting: string; out SC: TShortCut): Boolean;
begin
  SC := 0;
  Result := False;
  if Setting = '' then
    Exit;
  if (HotkeyStringToModifiers(Setting) and MOD_WIN) <> 0 then
    Exit;
  SC := HotkeyStringToShortCut(Setting);
  Result := SC <> 0;
end;

{ =============================================================================== }

procedure RegisterHotkeyFeature(VarPtr: PString; const Name: string; Control: TAvroHotKey);
var
  Len: Integer;
begin
  Len := Length(HotkeyFeatures);
  SetLength(HotkeyFeatures, Len + 1);
  HotkeyFeatures[Len].VariablePtr := VarPtr;
  HotkeyFeatures[Len].DisplayName := Name;
  HotkeyFeatures[Len].Control := Control;
end;

{ =============================================================================== }

function FindConflictingFeature(const Hotkey: string; Source: TAvroHotKey): Integer;
var
  I:           Integer;
  UpperHotkey: string;
  EditTxt:     string;
begin
  Result := -1;
  if (Hotkey = '') or (Hotkey = 'NONE') then
    Exit;
  UpperHotkey := UpperCase(Hotkey);
  // Check all registered features — compare against the fields, not VariablePtr^
  for I := 0 to Length(HotkeyFeatures) - 1 do
  begin
    if (HotkeyFeatures[I].Control = Source) or (HotkeyFeatures[I].Control = nil) then
      Continue;
    EditTxt := UpperCase(HotkeyFeatures[I].Control.Setting);
    if (EditTxt <> '') and HotkeysEqual(UpperHotkey, EditTxt) then
    begin
      Result := I;
      Exit;
    end;
  end;
  // Also check UserHotkeys array
  for I := 0 to Length(UserHotkeys) - 1 do
  begin
    if HotkeysEqual(UpperHotkey, UpperCase(KeyToHotkeyString(UserHotkeys[I].ModifierMask, UserHotkeys[I].VirtualKey))) then
    begin
      Result := Length(HotkeyFeatures) + I;
      Exit;
    end;
  end;
end;

{ =============================================================================== }

function ResolveHotkeyConflict(const NewHotkey: string; ConflictingIndex: Integer): Boolean;
var
  Msg:         string;
  Ret:         Integer;
  FeatureName: string;
begin
  Result := False;
  FeatureName := GetConflictDisplayName(ConflictingIndex);
  Msg := 'The hotkey "' + NewHotkey + '" conflicts with the hotkey selected for "' + FeatureName + '". ' + 'If you continue, the hotkey for "' + FeatureName +
    '" will be cleared. Continue?';
  Ret := Application.MessageBox(PChar(Msg), 'Hotkey Conflict', MB_YESNOCANCEL or MB_ICONWARNING or MB_DEFBUTTON3);
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
    // Only update the field — the variable is written by SaveSettings on OK/Apply
    if Assigned(HotkeyFeatures[Idx].Control) then
      HotkeyFeatures[Idx].Control.Setting := '';
  end
  else
  begin
    RemoveUserHotkey(Idx - FeatureCount);
  end;
end;

{ =============================================================================== }

end.
