{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmLayoutPicker;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  System.Types,
  uRegistrySettings,
  uThemeManager,
  uPickerSupport;

const
  WM_FOCUS_LAYOUT_PICKER = WM_APP + 4;

type
  TfrmLayoutPicker = class(TForm)
    ListBox: TListBox;
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListBoxClick(Sender: TObject);
    procedure ListBoxDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure ListBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ListBoxMouseLeave(Sender: TObject);
    private
      FHoverIndex:           Integer;
      FPrevFocusedWindow:    HWND;
      FPrevForegroundWindow: HWND;
      // Resolved once per open (the form is created fresh every time it is
      // shown), so the draw handler never reads the registry.
      FTheme:        TAppThemePalette;
      FLayoutNames:  TStringList;
      FLayoutValues: TStringList;

      { Lifetime. The popup is transient, it can be closed from four places at
        once (its own keys, its own mouse, the hotkey that opened it, clicking
        outside) and its apply path can raise a modal message box, so all of
        them go through BeginClose/FinishClose and the state is explicit. }
      FClosing:      Boolean; // no longer accepts input; unregistered; hidden
      FFinished:     Boolean; // destruction has been asked for
      FApplying:     Boolean; // a selection is being applied on this stack

      { Focus is best effort only - the keyboard hook delivers the navigation
        keys whether or not this popup ever owns the foreground. }
      FShownAt:      DWORD;
      FWasForeground: Boolean;
      FFocusTries:   Integer;

      procedure AutoSizeForm;
      procedure FormPaint(Sender: TObject);
      procedure TryActivateSelf;
      procedure ApplySelection(const ALayoutValue, ALayoutName: string);
      procedure WMNCActivate(var Msg: TWMNCActivate); message WM_NCACTIVATE;
      procedure WMFocusPicker(var Msg: TMessage); message WM_FOCUS_LAYOUT_PICKER;
      procedure WMPickerKey(var Msg: TMessage); message WM_PICKER_KEY;
      procedure WMPickerDismiss(var Msg: TMessage); message WM_PICKER_DISMISS;
      procedure WMTimer(var Msg: TMessage); message WM_TIMER;
    public
      procedure Setup;
      procedure PopulateLayouts;
      procedure PositionFormNearCursor;

      { Snapshot the selection, close, then apply on the main form. }
      procedure ActivateIndex(AIndex: Integer);
      function HandlePickerKey(var AKey: Word): Boolean;
      procedure HandlePickerChar(var AChar: Char);

      { Close with no change. }
      procedure RequestDismiss;
      procedure BeginClose;
      procedure FinishClose;

      property Closing: Boolean read FClosing;
    protected
      procedure CreateParams(var Params: TCreateParams); override;
      destructor Destroy; override;
  end;

procedure ShowLayoutPickerPopup;

var
  CurrentLayoutPicker: TfrmLayoutPicker;

implementation

uses
  uForm1,
  ufrmLayoutToast,
  KeyboardLayoutLoader,
  DebugLog;

procedure ShowLayoutPickerPopup;
var
  Picker: TfrmLayoutPicker;
begin
  // The hotkey that got here has already been swallowed by the hook, so opening
  // the popup is the whole job. Pressing it again while the popup is up closes
  // it: that is the toggle.
  if Assigned(CurrentLayoutPicker) then
  begin
    CurrentLayoutPicker.RequestDismiss;
    Exit;
  end;

  Picker := TfrmLayoutPicker.CreateNew(Application);
  try
    Picker.Setup;
    Picker.PositionFormNearCursor;
    CurrentLayoutPicker := Picker;
    Picker.Show;
  except
    on E: Exception do
    begin
      // A popup that fails to open must not take the process down with it (the
      // hotkey has already been swallowed, so nothing else would report this).
      Log('LayoutPicker: open failed - ' + E.ClassName + ': ' + E.Message);
      if CurrentLayoutPicker = Picker then
        CurrentLayoutPicker := nil;
      Picker.Free;
    end;
  end;
end;

procedure TfrmLayoutPicker.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
  Params.Style := WS_POPUP or WS_CLIPSIBLINGS;
  Params.ExStyle := WS_EX_TOPMOST or WS_EX_TOOLWINDOW;
end;

procedure TfrmLayoutPicker.Setup;
begin
  FHoverIndex := -1;
  FClosing := False;
  FFinished := False;
  FApplying := False;
  FShownAt := GetTickCount;
  FWasForeground := False;
  FFocusTries := 0;
  FPrevFocusedWindow := GetFocus;
  FPrevForegroundWindow := GetForegroundWindow;
  // Resolve the theme palette here, once: the picker is created fresh on every
  // open, so it always shows the current theme.
  FTheme := CurrentPalette;
  FLayoutNames := TStringList.Create;
  FLayoutValues := TStringList.Create;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  PopupMode := pmAuto;
  Color := FTheme.Background;
  ListBox := TListBox.Create(Self);
  ListBox.Parent := Self;
  ListBox.BorderStyle := bsNone;
  ListBox.Color := FTheme.Background;
  ListBox.Font.Name := 'Segoe UI';
  ListBox.Font.Size := 10;
  ListBox.Font.Color := FTheme.Text;
  ListBox.ItemHeight := 26;
  ListBox.Style := lbOwnerDrawFixed;
  ListBox.OnKeyDown := ListBoxKeyDown;
  ListBox.OnClick := ListBoxClick;
  ListBox.OnDrawItem := ListBoxDrawItem;
  ListBox.OnMouseMove := ListBoxMouseMove;
  ListBox.OnMouseLeave := ListBoxMouseLeave;
  ListBox.TabStop := True;

  // The form-level handlers are the fallback for the case where the hook is not
  // installed (it is swapped out around a layout load). While the hook is live
  // it blocks the physical key and posts WM_PICKER_KEY instead, and because
  // both paths run the same HandlePickerKey a key can never be handled twice.
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnKeyPress := FormKeyPress;

  OnShow := FormShow;
  OnClose := FormClose;
  OnPaint := FormPaint;
  PopulateLayouts;
  AutoSizeForm;

  // Borderless popup: nothing to darken here, but the same call is what gives a
  // themed frame when the embedded VCL styles are unavailable.
  ApplyImmersiveDarkMode(Handle, FTheme.IsDark);
end;

procedure TfrmLayoutPicker.FormShow(Sender: TObject);
begin
  FShownAt := GetTickCount;
  FWasForeground := False;
  FFocusTries := 0;
  SetTimer(Handle, 1, 200, nil);
  // Outside clicks have to be noticed even when this popup never becomes the
  // foreground window, which is exactly the case on the machines this fixes.
  PickerMouseHookInstall(Handle);
  PostMessage(Handle, WM_FOCUS_LAYOUT_PICKER, 0, 0);
end;

procedure TfrmLayoutPicker.WMFocusPicker(var Msg: TMessage);
begin
  if FClosing or (not IsWindow(Handle)) then
    Exit;
  TryActivateSelf;
  if ListBox.CanFocus then
    ListBox.SetFocus;
end;

{ Best effort, and never a precondition: if Windows refuses this popup the
  foreground (foreground lock, UIPI, an elevated or fullscreen target), the
  window stays visible and the hook still delivers every navigation key. }
procedure TfrmLayoutPicker.TryActivateSelf;
var
  BecameForeground: Boolean;
begin
  if FClosing or (not IsWindow(Handle)) then
    Exit;
  PickerBringToForeground(Handle, BecameForeground);
  // Only ever set, never cleared: it records that the foreground was granted at
  // least once, which is what makes a later loss of it a real deactivation.
  if BecameForeground then
    FWasForeground := True;
end;

procedure TfrmLayoutPicker.WMTimer(var Msg: TMessage);
begin
  if FClosing then
    Exit;

  // Never touch a popup while one of our own modal dialogs is up: the picker
  // may be the very form whose stack that dialog was raised from (the layout
  // load failure message box), and closing here is what used to free the form
  // under its own click handler.
  if Application.ModalLevel <> 0 then
    Exit;

  if not IsWindowVisible(Handle) then
  begin
    RequestDismiss;
    Exit;
  end;

  // Close on a REAL deactivation only: the popup did hold the foreground at
  // least once and no longer does. A popup that was never granted the
  // foreground must not be closed for it - that rule is what made the popups
  // unusable on those machines.
  if GetForegroundWindow = Handle then
    FWasForeground := True
  else if FWasForeground and (GetTickCount - FShownAt > PICKER_ACTIVATION_GRACE_MS) then
  begin
    RequestDismiss;
    Exit;
  end;

  if (not FWasForeground) and (FFocusTries < PICKER_FOCUS_ATTEMPTS) then
  begin
    Inc(FFocusTries);
    TryActivateSelf;
  end;
end;

procedure TfrmLayoutPicker.WMNCActivate(var Msg: TWMNCActivate);
begin
  inherited;

  if Msg.Active then
  begin
    FWasForeground := True;
    Exit;
  end;

  // Same predicate as the timer: ignoring the first activation flicker is the
  // whole point, because closing on it is what made the popup vanish the
  // instant it appeared.
  if (not FClosing) and FWasForeground and (Application.ModalLevel = 0) and
    (GetTickCount - FShownAt > PICKER_ACTIVATION_GRACE_MS) then
    RequestDismiss;
end;

procedure TfrmLayoutPicker.WMPickerKey(var Msg: TMessage);
var
  Key: Word;
begin
  Key := Word(Msg.WParam);
  HandlePickerKey(Key);
end;

procedure TfrmLayoutPicker.WMPickerDismiss(var Msg: TMessage);
begin
  RequestDismiss;
end;

procedure TfrmLayoutPicker.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if FApplying then
  begin
    // A selection is being applied on this form's stack (and may pump messages
    // in a message box or a toast). Do not destroy the form under it - the
    // caller's FinishClose owns the destruction.
    Action := caHide;
    if CurrentLayoutPicker = Self then
      CurrentLayoutPicker := nil;
    Exit;
  end;

  // Every close route ends here: Escape, a selection, an outside click, the
  // hotkey, or the VCL's own WM_CLOSE handling. Stopping the timer and the
  // mouse hook here as well keeps that single-shot whichever way it arrived.
  FClosing := True;
  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;
  Action := caFree;
  if CurrentLayoutPicker = Self then
    CurrentLayoutPicker := nil;
end;

destructor TfrmLayoutPicker.Destroy;
begin
  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;
  if CurrentLayoutPicker = Self then
    CurrentLayoutPicker := nil;
  FreeAndNil(FLayoutNames);
  FreeAndNil(FLayoutValues);
  inherited;
end;

procedure TfrmLayoutPicker.BeginClose;
begin
  if FClosing then
    Exit;
  FClosing := True;

  // Unregister FIRST, before anything this popup may do from here on. The hook
  // asks IsPickerOpen / RouteKeyToPicker, and the apply path below can raise a
  // modal message box: as long as the popup is still registered the hook would
  // keep swallowing the Enter and letters that message box needs.
  if CurrentLayoutPicker = Self then
    CurrentLayoutPicker := nil;

  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;

  Hide;
end;

procedure TfrmLayoutPicker.FinishClose;
begin
  if FFinished then
    Exit;
  FFinished := True;
  if not FClosing then
    FClosing := True;

  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;

  PickerRestoreForeground(FPrevFocusedWindow, FPrevForegroundWindow);

  // FormClose sets caFree; the VCL defers the destruction (Release) until after
  // the message being processed now returns, so whatever handler is still on
  // this stack finishes on a live object.
  Close;
end;

procedure TfrmLayoutPicker.RequestDismiss;
begin
  // A pending apply owns the lifetime: its own FinishClose will release this
  // form, and closing again from here could destroy it mid-apply.
  if FClosing then
    Exit;
  BeginClose;
  FinishClose;
end;

procedure TfrmLayoutPicker.PopulateLayouts;
var
  I:                                      Integer;
  CurrentLayout, LayoutName, LayoutValue: string;
  ItemFound:                              Boolean;
begin
  CurrentLayout := '';
  if Assigned(AvroMainForm1) then
    CurrentLayout := AvroMainForm1.GetMyCurrentLayout;
  ListBox.Items.BeginUpdate;
  try
    ListBox.Clear;
    FLayoutNames.Clear;
    FLayoutValues.Clear;

    // Add Avro Phonetic as first item
    FLayoutNames.Add('Avro Phonetic (English to Bangla)');
    FLayoutValues.Add('avrophonetic*');
    ListBox.Items.Add('Avro Phonetic (English to Bangla)');

    // Add all fixed layouts from KeyboardLayouts
    if Assigned(KeyboardLayouts) then
    begin
      for I := 0 to KeyboardLayouts.Count - 1 do
      begin
        LayoutName := KeyboardLayouts[I];
        LayoutValue := LayoutName;
        FLayoutNames.Add(LayoutName);
        FLayoutValues.Add(LayoutValue);
        ListBox.Items.Add(LayoutName);
      end;
    end;
  finally
    ListBox.Items.EndUpdate;
  end;

  // Select the current layout
  ItemFound := False;
  for I := 0 to FLayoutValues.Count - 1 do
  begin
    if LowerCase(FLayoutValues[I]) = LowerCase(CurrentLayout) then
    begin
      ListBox.ItemIndex := I;
      ItemFound := True;
      Break;
    end;
  end;

  if (not ItemFound) and (ListBox.Items.Count > 0) then
    ListBox.ItemIndex := 0;
end;

procedure TfrmLayoutPicker.AutoSizeForm;
var
  I, W, MaxW: Integer;
  TempStr:    string;
begin
  MaxW := 0;
  Canvas.Font := ListBox.Font;
  for I := 0 to ListBox.Items.Count - 1 do
  begin
    if I < 9 then
      TempStr := IntToStr(I + 1) + '. ' + ListBox.Items[I]
    else
      TempStr := ListBox.Items[I];
    W := Canvas.TextWidth(TempStr);
    if W > MaxW then
      MaxW := W;
  end;
  Width := MaxW + 45;
  // +8 is the exact item height for the list box plus the 1px themed frame on
  // each side of it (see FormPaint), so no row is clipped.
  Height := ListBox.Items.Count * 26 + 8;
  ListBox.SetBounds(1, 4, Width - 2, Height - 8);
end;

procedure TfrmLayoutPicker.PositionFormNearCursor;
var
  CursorPos: TPoint;
  Monitor:   TMonitor;
begin
  GetCursorPos(CursorPos);
  Monitor := Screen.MonitorFromPoint(CursorPos);
  Left := CursorPos.X;
  Top := CursorPos.Y + 10;
  if Left + Width > Monitor.WorkAreaRect.Right then
    Left := Monitor.WorkAreaRect.Right - Width;
  if Left < Monitor.WorkAreaRect.Left then
    Left := Monitor.WorkAreaRect.Left;
  if Top + Height > Monitor.WorkAreaRect.Bottom then
    Top := Monitor.WorkAreaRect.Bottom - Height;
  if Top < Monitor.WorkAreaRect.Top then
    Top := Monitor.WorkAreaRect.Top;
end;

{ Fills the thin band the list box does not cover and draws the themed 1px
  frame around it; AutoSizeForm insets the list box by one pixel so that frame
  stays visible on all four sides. }
procedure TfrmLayoutPicker.FormPaint(Sender: TObject);
begin
  Canvas.Brush.Color := FTheme.Background;
  Canvas.FillRect(Canvas.ClipRect);
  Canvas.Brush.Color := FTheme.Border;
  Canvas.FrameRect(ClientRect);
end;

procedure TfrmLayoutPicker.ListBoxDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect:          TRect;
  DisplayText:         string;
  CurrentLayout:       string;
begin
  // Both lists are addressed by the same index, so a row that exists in only
  // one of them must not be painted from the other one.
  if (Index < 0) or (Index >= ListBox.Items.Count) or (Index >= FLayoutValues.Count) then
  begin
    ListBox.Canvas.Brush.Color := FTheme.Background;
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;

  CurrentLayout := '';
  if Assigned(AvroMainForm1) then
    CurrentLayout := AvroMainForm1.GetMyCurrentLayout;
  IsActive := LowerCase(FLayoutValues[Index]) = LowerCase(CurrentLayout);
  IsHovered := (Index = FHoverIndex) or (odSelected in State);

  ListBox.Canvas.Brush.Color := FTheme.Background;
  ListBox.Canvas.FillRect(Rect);

  if IsHovered then
  begin
    ListBox.Canvas.Brush.Color := FTheme.HoverFill;
    ListBox.Canvas.FillRect(Rect);
  end;

  GutterRect := Rect;
  GutterRect.Right := Rect.Left + 28;

  if IsActive then
  begin
    ListBox.Canvas.Brush.Color := FTheme.SelectionFill;
    ListBox.Canvas.FillRect(GutterRect);
    ListBox.Canvas.Font.Color := FTheme.SelectionText;
    ListBox.Canvas.Font.Style := [fsBold];
    DrawText(ListBox.Canvas.Handle, #$2713, -1, GutterRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    ListBox.Canvas.Font.Style := [];
  end;

  ListBox.Canvas.Brush.Style := bsClear;
  ListBox.Canvas.Font.Color := FTheme.Text;
  if Index < 9 then
    DisplayText := IntToStr(Index + 1) + '. ' + ListBox.Items[Index]
  else
    DisplayText := ListBox.Items[Index];
  ListBox.Canvas.TextOut(Rect.Left + 35, Rect.Top + 3, DisplayText);
  ListBox.Canvas.Brush.Style := bsSolid;
end;

procedure TfrmLayoutPicker.ListBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  Idx := ListBox.ItemAtPos(Point(X, Y), True);
  if Idx <> FHoverIndex then
  begin
    FHoverIndex := Idx;
    ListBox.Invalidate;
  end;
end;

procedure TfrmLayoutPicker.ListBoxMouseLeave(Sender: TObject);
begin
  FHoverIndex := -1;
  ListBox.Invalidate;
end;

{ Mouse selection is unchanged: a click applies that row and closes. }
procedure TfrmLayoutPicker.ListBoxClick(Sender: TObject);
begin
  ActivateIndex(ListBox.ItemIndex);
end;

{ The one activation path, shared by the mouse, the posted key message and the
  fallback key handlers.

  The selection is snapshotted first and the popup is unregistered and hidden
  before any of the layout work runs, so nothing that work does - including the
  modal message box a failed layout load raises - can come back to a popup that
  has already been released. }
procedure TfrmLayoutPicker.ActivateIndex(AIndex: Integer);
var
  SelectedLayout, SelectedName: string;
begin
  if FClosing then
    Exit;
  if (AIndex < 0) or (AIndex >= ListBox.Items.Count) or (AIndex >= FLayoutValues.Count) or (AIndex >= FLayoutNames.Count) then
    Exit;

  SelectedLayout := FLayoutValues[AIndex];
  SelectedName := FLayoutNames[AIndex];
  if SelectedLayout = '' then
    Exit;

  ListBox.ItemIndex := AIndex;

  BeginClose;
  FApplying := True;
  try
    ApplySelection(SelectedLayout, SelectedName);
  finally
    FApplying := False;
    FinishClose;
  end;
end;

procedure TfrmLayoutPicker.ApplySelection(const ALayoutValue, ALayoutName: string);
begin
  if not Assigned(AvroMainForm1) then
    Exit;

  // Setting this calls TLayout.SetCurrentKeyboardLayout, which unhooks and
  // re-installs the keyboard hook and can show its own modal error box. The
  // popup is already unregistered and hidden at this point, so the hook is no
  // longer stealing the keys that box needs - and this form can not be closed
  // underneath this call.
  if Assigned(AvroMainForm1.KeyLayout) then
    AvroMainForm1.KeyLayout.CurrentKeyboardLayout := ALayoutValue;

  if ShowLayoutSwitchNotification = 'YES' then
    ShowLayoutToastNotification('Layout switched to: ' + ALayoutName);
end;

function TfrmLayoutPicker.HandlePickerKey(var AKey: Word): Boolean;
var
  Consumed:    Boolean;
  ActivateIdx: Integer;
begin
  Result := False;
  if FClosing then
    Exit;

  HandlePickerNavigation(ListBox, AKey, Consumed, ActivateIdx);
  if not Consumed then
    Exit;

  Result := True;
  AKey := 0;

  if ActivateIdx = -2 then
    RequestDismiss
  else if ActivateIdx >= 0 then
    ActivateIndex(ActivateIdx);
end;

procedure TfrmLayoutPicker.HandlePickerChar(var AChar: Char);
var
  Key:         Word;
  Consumed:    Boolean;
  ActivateIdx: Integer;
begin
  // CharInSet, not `in`: a set of Char is a byte set, so a Bangla character
  // whose low byte happens to land in one of these ranges would match.
  if FClosing or (not CharInSet(AChar, ['0' .. '9', 'A' .. 'Z', 'a' .. 'z'])) then
    Exit;

  Key := Ord(UpCase(AChar));
  HandlePickerNavigation(ListBox, Key, Consumed, ActivateIdx);
  if Consumed then
    AChar := #0;

  if ActivateIdx >= 0 then
    ActivateIndex(ActivateIdx);
end;

procedure TfrmLayoutPicker.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  HandlePickerKey(Key);
end;

procedure TfrmLayoutPicker.FormKeyPress(Sender: TObject; var Key: Char);
begin
  HandlePickerChar(Key);
end;

procedure TfrmLayoutPicker.ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Kept for the case where the list box owns the focus and the form-level
  // handler declined the key. Both share one implementation and VCL only ever
  // calls one of them per key.
  HandlePickerKey(Key);
end;

end.
