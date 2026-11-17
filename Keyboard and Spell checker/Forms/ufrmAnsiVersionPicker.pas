{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

unit ufrmAnsiVersionPicker;

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
  Menus,
  StdCtrls,
  Generics.Collections,
  System.Types,
  uRegistrySettings,
  clsUnicodeToBijoy2000,
  uThemeManager,
  uPickerSupport,
  System.IOUtils;

const
  WM_FOCUS_PICKER = WM_APP + 2;

type
  TfrmAnsiVersionPicker = class(TForm)
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
    procedure ListBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PopupExportClick(Sender: TObject);
    procedure PopupDescriptionClick(Sender: TObject);
    procedure PopupDeleteClick(Sender: TObject);
    procedure BuildPopupMenu(const AFileName: string);
    private
      FHoverIndex:           Integer;
      FPopup:                TPopupMenu;
      { Parallel to ListBox.Items: ListBox shows labels only, while every
        check, shortcut and action resolves through this exact-file
        list. A caption is never parsed back into an identity. }
      FMappingFileNames:     TStringList;
      FPrevFocusedWindow:    HWND;
      FPrevForegroundWindow: HWND;
      // Resolved once per open (the form is created fresh every time it is
      // shown), so the draw handler never reads the registry.
      FTheme: TAppThemePalette;

      { Lifetime. A selection can be applied from four places (its own keys, its
        own mouse, the hotkey, a context-menu command), and the apply path can
        raise a modal password prompt or message box - so every one of them goes
        through BeginClose/FinishClose and the state is explicit. }
      FClosing:     Boolean; // no longer accepts input; unregistered; hidden
      FFinished:    Boolean; // destruction has been asked for
      FApplying:    Boolean; // a selection is being applied on this stack
      FInMenuLoop:  Boolean; // our own popup menu owns the stack right now
      FPendingFree: Boolean; // FinishClose was requested while the menu was up

      { Focus is best effort only - the keyboard hook delivers the navigation
        keys whether or not this popup ever owns the foreground. }
      FShownAt:       DWORD;
      FWasForeground: Boolean;
      FFocusTries:    Integer;

      procedure AutoSizeForm;
      procedure TryActivateSelf;
      procedure ApplySelection(const ASelectedFile: string);
      procedure FormPaint(Sender: TObject);
      procedure WMNCActivate(var Msg: TWMNCActivate); message WM_NCACTIVATE;
      procedure WMFocusPicker(var Msg: TMessage); message WM_FOCUS_PICKER;
      procedure WMPickerKey(var Msg: TMessage); message WM_PICKER_KEY;
      procedure WMPickerDismiss(var Msg: TMessage); message WM_PICKER_DISMISS;
      procedure WMTimer(var Msg: TMessage); message WM_TIMER;
    public
      procedure Setup;
      procedure PopulateVersions;
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

procedure ShowAnsiVersionPicker;

var
  CurrentPicker: TfrmAnsiVersionPicker;

implementation

uses
  uForm1,
  ufrmAnsiToast,
  uAvroEncoManager,
  uAvroEncoImporter,
  uAvroEncoCrypto,
  uAnsiEngineManager,
  uAvroLayoutUI,
  DebugLog;

procedure ShowAnsiVersionPicker;
var
  Picker: TfrmAnsiVersionPicker;
begin
  // The hotkey that got here has already been swallowed by the hook, so opening
  // the popup is the whole job. Pressing it again while the popup is up closes
  // it: that is the toggle.
  if Assigned(CurrentPicker) then
  begin
    CurrentPicker.RequestDismiss;
    Exit;
  end;

  Picker := TfrmAnsiVersionPicker.CreateNew(Application);
  try
    Picker.Setup;
    Picker.PositionFormNearCursor;
    CurrentPicker := Picker;
    Picker.Show;
  except
    on E: Exception do
    begin
      // A popup that fails to open must not take the process down with it (the
      // hotkey has already been swallowed, so nothing else would report this).
      Log('AnsiPicker: open failed - ' + E.ClassName + ': ' + E.Message);
      if CurrentPicker = Picker then
        CurrentPicker := nil;
      Picker.Free;
    end;
  end;
end;

{ TfrmAnsiVersionPicker }

procedure TfrmAnsiVersionPicker.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
  Params.Style := WS_POPUP or WS_CLIPSIBLINGS;
  Params.ExStyle := WS_EX_TOPMOST or WS_EX_TOOLWINDOW;
end;

procedure TfrmAnsiVersionPicker.Setup;
begin
  FHoverIndex := -1;
  FClosing := False;
  FFinished := False;
  FApplying := False;
  FInMenuLoop := False;
  FPendingFree := False;
  FShownAt := GetTickCount;
  FWasForeground := False;
  FFocusTries := 0;
  FPrevFocusedWindow := GetFocus;
  FPrevForegroundWindow := GetForegroundWindow;
  // Resolve the theme palette here, once: the picker is created fresh on every
  // open, so it always shows the current theme while the draw handler stays
  // free of registry reads.
  FTheme := CurrentPalette;
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
  ListBox.ItemHeight := 28;
  ListBox.Style := lbOwnerDrawFixed;
  ListBox.OnKeyDown := ListBoxKeyDown;
  ListBox.OnClick := ListBoxClick;
  ListBox.OnDrawItem := ListBoxDrawItem;
  ListBox.OnMouseMove := ListBoxMouseMove;
  ListBox.OnMouseLeave := ListBoxMouseLeave;
  ListBox.TabStop := True;
  ListBox.OnMouseUp := ListBoxMouseUp;

  FPopup := TPopupMenu.Create(Self);
  ListBox.PopupMenu := FPopup;

  // KeyPreview routes every key through the form before the focused control
  // sees it, so the type/number shortcuts work even when the list box never
  // gets real input focus. VCL stops the chain as soon as the form zeroes Key
  // (Vcl.Controls.DoKeyDown/DoKeyPress return True), so a key that the form
  // handles can never reach the list box handlers as well.
  //
  // These are the fallback path: while the keyboard hook is live it blocks the
  // physical key and posts WM_PICKER_KEY instead, and both paths run the same
  // HandlePickerKey - so a key is handled exactly once either way.
  //
  // ActiveControl is deliberately NOT set here: the form is still invisible in
  // Setup, so TWinControl.CanFocus is False and TCustomForm.SetActiveControl
  // would raise EInvalidOperation (SCannotFocus). Focus is established after
  // Show, in WMFocusPicker below.
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnKeyPress := FormKeyPress;

  OnShow := FormShow;
  OnClose := FormClose;
  OnPaint := FormPaint;
  FreeAndNil(FMappingFileNames);
  FMappingFileNames := TStringList.Create;
  PopulateVersions;
  AutoSizeForm;

  // The picker is a borderless popup, so there is no frame to darken - but the
  // same call is what gives a themed frame when the embedded VCL styles are
  // unavailable and the app falls back to native window frames.
  ApplyImmersiveDarkMode(Handle, FTheme.IsDark);
end;

procedure TfrmAnsiVersionPicker.FormShow(Sender: TObject);
begin
  FShownAt := GetTickCount;
  FWasForeground := False;
  FFocusTries := 0;
  SetTimer(Handle, 1, 200, nil);
  // Outside clicks have to be noticed even when this popup never becomes the
  // foreground window, which is exactly the case on the machines this fixes.
  PickerMouseHookInstall(Handle);
  PostMessage(Handle, WM_FOCUS_PICKER, 0, 0);
end;

procedure TfrmAnsiVersionPicker.WMFocusPicker(var Msg: TMessage);
begin
  if FClosing or (not IsWindow(Handle)) then
    Exit;
  TryActivateSelf;
  // CanFocus only walks the visible/enabled chain - it says nothing about who
  // really owns the input focus. Move the focus, then verify - but never make
  // anything depend on it: the fallback is the hook, not this.
  if ListBox.CanFocus then
    ListBox.SetFocus;
end;

{ Best effort, and never a precondition: if Windows refuses this popup the
  foreground (foreground lock, UIPI, an elevated or fullscreen target), the
  window stays visible and the hook still delivers every navigation key. }
procedure TfrmAnsiVersionPicker.TryActivateSelf;
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

procedure TfrmAnsiVersionPicker.WMTimer(var Msg: TMessage);
begin
  if FClosing then
    Exit;

  // Never touch a popup while one of our own modal dialogs is up (the mapping
  // password prompt): closing here is what used to free the form while its own
  // ListBoxClick was still on the stack.
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

procedure TfrmAnsiVersionPicker.WMNCActivate(var Msg: TWMNCActivate);
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
  if (not FClosing) and FWasForeground and (Application.ModalLevel = 0) and (GetTickCount - FShownAt > PICKER_ACTIVATION_GRACE_MS) then
    RequestDismiss;
end;

procedure TfrmAnsiVersionPicker.WMPickerKey(var Msg: TMessage);
var
  Key: Word;
begin
  Key := Word(Msg.WParam);
  HandlePickerKey(Key);
end;

procedure TfrmAnsiVersionPicker.WMPickerDismiss(var Msg: TMessage);
begin
  RequestDismiss;
end;

procedure TfrmAnsiVersionPicker.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if FApplying then
  begin
    // A selection is being applied on this form's stack (and may pump messages
    // in a password prompt or the switch toast). Do not destroy the form under
    // it - the caller's FinishClose owns the destruction.
    Action := caHide;
    if CurrentPicker = Self then
      CurrentPicker := nil;
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
  if CurrentPicker = Self then
    CurrentPicker := nil;
end;

destructor TfrmAnsiVersionPicker.Destroy;
begin
  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;
  if CurrentPicker = Self then
    CurrentPicker := nil;
  FMappingFileNames.Free;
  inherited;
end;

procedure TfrmAnsiVersionPicker.BeginClose;
begin
  if FClosing then
    Exit;
  FClosing := True;

  // Unregister FIRST, before anything this popup may do from here on. The hook
  // asks IsPickerOpen / RouteKeyToPicker, and the apply path below raises a
  // modal password prompt or message box: as long as the popup is still
  // registered the hook would keep swallowing the Enter, letters and digits
  // that prompt needs.
  if CurrentPicker = Self then
    CurrentPicker := nil;

  if HandleAllocated then
  begin
    KillTimer(Handle, 1);
    PickerMouseHookRemove(Handle);
  end;

  Hide;
end;

procedure TfrmAnsiVersionPicker.FinishClose;
begin
  if FFinished then
    Exit;

  if FInMenuLoop then
  begin
    // One of our own popup menus owns the stack: destroying this form now would
    // destroy the very control TrackPopupMenu is going to return into. The
    // command handler that asked for this will be finished when the menu loop
    // unwinds, and ListBoxMouseUp closes the popup then.
    FPendingFree := True;
    Exit;
  end;

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

procedure TfrmAnsiVersionPicker.RequestDismiss;
begin
  // A pending apply owns the lifetime: its own FinishClose will release this
  // form, and closing again from here could destroy it mid-apply.
  if FClosing then
    Exit;
  BeginClose;
  FinishClose;
end;

procedure TfrmAnsiVersionPicker.PopulateVersions;
var
  I: Integer;
begin
  ListBox.Items.BeginUpdate;
  try
    ListBox.Clear;
    FMappingFileNames.Clear;

    if (not Assigned(AvroMainForm1)) or (not Assigned(AvroMainForm1.AnsiMappingNames)) or (not Assigned(AvroMainForm1.AnsiMappingFileNames)) then
      Exit;

    // The two lists are built in one pass and must stay index-parallel. If they
    // ever drift, showing nothing is the only safe choice: pairing a caption
    // with the wrong exact file would activate a sibling the user never picked.
    if AvroMainForm1.AnsiMappingNames.Count <> AvroMainForm1.AnsiMappingFileNames.Count then
    begin
      Log('AnsiPicker: label/file list length mismatch (' + IntToStr(AvroMainForm1.AnsiMappingNames.Count) + ' vs ' +
        IntToStr(AvroMainForm1.AnsiMappingFileNames.Count) + ') - showing no rows');
      Exit;
    end;

    // Full scanned catalog only - no prepended "Default" row. Empty list
    // (zero mapping files) shows an empty picker; Esc still closes.
    for I := 0 to AvroMainForm1.AnsiMappingFileNames.Count - 1 do
    begin
      ListBox.Items.Add(AvroMainForm1.AnsiMappingNames[I]);
      FMappingFileNames.Add(AvroMainForm1.AnsiMappingFileNames[I]);
    end;
  finally
    ListBox.Items.EndUpdate;
  end;

  // The active row is the exact file of the live engine - never a display
  // label, so exactly one of two same-base rows can be highlighted.
  for I := 0 to FMappingFileNames.Count - 1 do
    if SameText(FMappingFileNames[I], AnsiVersionFileName) then
    begin
      ListBox.ItemIndex := I;
      Break;
    end;
end;

procedure TfrmAnsiVersionPicker.AutoSizeForm;
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
  Width := MaxW + 58;
  // +10 is the exact item height for the list box plus the 1px themed frame on
  // each side of it (see FormPaint), so no row is clipped.
  Height := ListBox.Items.Count * 28 + 10;
  ListBox.SetBounds(1, 5, Width - 2, Height - 10);
end;

procedure TfrmAnsiVersionPicker.PositionFormNearCursor;
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
procedure TfrmAnsiVersionPicker.FormPaint(Sender: TObject);
begin
  Canvas.Brush.Color := FTheme.Background;
  Canvas.FillRect(Canvas.ClipRect);
  Canvas.Brush.Color := FTheme.Border;
  Canvas.FrameRect(ClientRect);
end;

procedure TfrmAnsiVersionPicker.ListBoxDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect:          TRect;
  DisplayText:         string;
begin
  if (index < 0) or (index >= ListBox.Items.Count) then
  begin
    ListBox.Canvas.Brush.Color := FTheme.Background;
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;
  IsActive := (Index < FMappingFileNames.Count) and SameText(AnsiVersionFileName, FMappingFileNames[Index]);
  IsHovered := (index = FHoverIndex) or (odSelected in State);

  // 1. Base background
  ListBox.Canvas.Brush.Color := FTheme.Background;
  ListBox.Canvas.FillRect(Rect);

  // 2. Row highlight on Hover / Selected
  if IsHovered then
  begin
    ListBox.Canvas.Brush.Color := FTheme.HoverFill;
    ListBox.Canvas.FillRect(Rect);
  end;

  // 3. Left indicator gutter
  GutterRect := Rect;
  GutterRect.Right := Rect.Left + 26;

  // 4. Active indicator
  if IsActive then
  begin
    ListBox.Canvas.Brush.Color := FTheme.SelectionFill;
    ListBox.Canvas.FillRect(GutterRect);

    ListBox.Canvas.Font.Color := FTheme.SelectionText;
    ListBox.Canvas.Font.Style := [fsBold];
    DrawText(ListBox.Canvas.Handle, #$2713, -1, GutterRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    ListBox.Canvas.Font.Style := [];
  end;

  // 5. Draw item text
  ListBox.Canvas.Brush.Style := bsClear;
  ListBox.Canvas.Font.Color := FTheme.Text;
  if index < 9 then
    DisplayText := IntToStr(index + 1) + '. ' + ListBox.Items[index]
  else
    DisplayText := ListBox.Items[index];
  ListBox.Canvas.TextOut(Rect.Left + 34, Rect.Top + 4, DisplayText);

  ListBox.Canvas.Brush.Style := bsSolid;
end;

procedure TfrmAnsiVersionPicker.ListBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
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

procedure TfrmAnsiVersionPicker.ListBoxMouseLeave(Sender: TObject);
begin
  FHoverIndex := -1;
  ListBox.Invalidate;
end;

{ Mouse selection is unchanged: a click applies that row and closes. }
procedure TfrmAnsiVersionPicker.ListBoxClick(Sender: TObject);
begin
  ActivateIndex(ListBox.ItemIndex);
end;

{ The one activation path, shared by the mouse, the posted key message and the
  fallback key handlers.

  The choice is snapshotted first and the popup is unregistered and hidden
  before any of the engine work runs, so nothing that work does - including the
  modal password prompt and the switch toast - can come back to a popup that has
  already been released. The form is destroyed only after that work returns. }
procedure TfrmAnsiVersionPicker.ActivateIndex(AIndex: Integer);
var
  SelectedFile: string;
begin
  if FClosing then
    Exit;
  if (AIndex < 0) or (AIndex >= FMappingFileNames.Count) or (AIndex >= ListBox.Items.Count) then
    Exit;

  // The exact file at the clicked row's index. The visible caption is a label
  // and is never turned back into an identity.
  SelectedFile := FMappingFileNames[AIndex];
  if SelectedFile = '' then
    Exit;

  ListBox.ItemIndex := AIndex;

  BeginClose;
  FApplying := True;
  try
    ApplySelection(SelectedFile);
  finally
    FApplying := False;
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.ApplySelection(const ASelectedFile: string);
var
  ErrorMsg, TargetPath: string;
  Password:             AnsiString;
  PreloadThread:        TAnsiPreloadThread;
  ErrList:              TStringList;
begin
  if not Assigned(AvroMainForm1) then
    Exit;
  if not IsBareMappingFileName(ASelectedFile) then
    Exit;

  // One path for every selection: resolve only this exact file, prompt for a
  // password if this container needs one and none is cached, then switch.
  // There is no compiled-in Default branch and no same-base fallback.
  TargetPath := GetExactEncoFilePath(ASelectedFile, AnsiMappingDir);
  if TargetPath = '' then
  begin
    Application.MessageBox(PChar('Mapping file not found: ' + ASelectedFile), 'ANSI Encoding Error', MB_ICONWARNING or MB_OK or MB_TOPMOST or
        MB_SETFOREGROUND);
    Exit;
  end;

  // Only password-protected files (flag $01 / legacy v1) prompt, and only
  // when no usable password is cached yet; SwitchEngine then reuses
  // CachedEncoPassword and never prompts a second time. Default-key files
  // (flag $00) must NEVER ask for a password - they decrypt transparently.
  // Ask only when THIS file was never unlocked on this computer; the per-file
  // cache then unlocks every later switch silently (even after a full restart).
  //
  // The prompt is modal and this form is unregistered and hidden by then, so
  // the keyboard hook no longer intercepts the keys the user types into it and
  // the deferred destruction can not run while this stack is still live.
  if IsEncoFile(TargetPath) and (GetEncoCachedPassword(TargetPath) = '') and (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_USER_PASSWORD) then
  begin
    if not PromptForPasswordAndValidate(TargetPath, Password) then
      Exit; // Cancelled - the picker stays closed and the encoding is unchanged.
    CachedEncoPassword := Password;
    RememberEncoPassword(TargetPath, Password);
    SaveSettings;
    // Build exactly THIS newly unlocked engine away from the UI.
    PreloadThread := TAnsiPreloadThread.Create(AnsiEngineManager.CapturePreloadItem(ASelectedFile));
    PreloadThread.FreeOnTerminate := True;
    PreloadThread.Start;
  end;

  // The engine cache makes this switch O(1) for every preloaded (default-key)
  // engine and for any engine unlocked before: no disk I/O, no decryption,
  // no parsing happens here.
  //
  // RAM-cache MISS fallback (cold-start repair): an engine can miss the
  // startup preload - e.g. after wiping %AppData%\AvroKeyboard\Cache, one of
  // the parallel decrypts can fail under memory pressure, and the largest
  // mapping (Ansi V3) is the usual victim. Without a fallback the picker
  // fails forever ("still being prepared") even though a single on-demand
  // parse - usually a fast persistent-cache HIT - repairs it. So: instant
  // path first, blocking repair parse second. The hourglass covers the
  // repair (decrypt + heavy V3 parse can take a moment on cold start).
  ErrorMsg := '';
  if not AnsiEngineManager.TrySwitchCached(ASelectedFile) then
  begin
    Screen.Cursor := crHourGlass;
    ErrList := TStringList.Create;
    try
      if not AnsiEngineManager.SwitchEngine(ASelectedFile, ErrList) then
        ErrorMsg := 'Encoding is still being prepared. Please select it again.';
    finally
      ErrList.Free;
      Screen.Cursor := crDefault;
    end;
  end;
  if ErrorMsg = '' then
  begin
    if Assigned(AvroMainForm1.KeyLayout) then
      AvroMainForm1.KeyLayout.ResetAnsiTypingState;

    // The manager published BOTH globals from the slot that became live; only
    // persist them here. Never assign AnsiVersion alone.
    AvroMainForm1.SyncActiveMappingTimestamp(AnsiVersionFileName);
    SaveAnsiVersionOnly;
    AvroMainForm1.UpdateAnsiVersionMenuChecks(AnsiVersionFileName);
    AvroMainForm1.UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Version: ' + GetMappingDisplayLabel(AnsiVersionFileName));

    Exit;
  end;

  // Both the instant path and the on-demand repair parse failed (corrupt
  // file, wrong password or missing mapping). This is an error, so it is
  // always shown - independent of the routine switch-notification setting -
  // otherwise the picker just closes and the user believes V3 is active
  // while typing still produces the previous engine's output.
  ShowAnsiToastNotification('ANSI encoding failed to load - try again');
end;

{ =============================================================================== }
{ Keyboard shortcuts }
{ =============================================================================== }

{ The single key implementation. Returns True when the key was consumed, and the
  caller is expected to zero it - which is also what makes VCL skip the other
  handler for the same key, so a shortcut can never be handled twice. }
function TfrmAnsiVersionPicker.HandlePickerKey(var AKey: Word): Boolean;
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

{ First-letter navigation for the real-keypress fallback: the hook path maps the
  VK code itself (see PickerIndexForKey), this maps the character it produced.
  Zeroing AChar also suppresses the list box's own type-ahead for the same
  letter, so the selection happens exactly once. }
procedure TfrmAnsiVersionPicker.HandlePickerChar(var AChar: Char);
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

procedure TfrmAnsiVersionPicker.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  HandlePickerKey(Key);
end;

procedure TfrmAnsiVersionPicker.FormKeyPress(Sender: TObject; var Key: Char);
begin
  HandlePickerChar(Key);
end;

procedure TfrmAnsiVersionPicker.ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Kept for the case where the list box owns the focus and the form-level
  // handler declined the key. Both handlers share one implementation, and VCL
  // only ever calls one of them per key.
  HandlePickerKey(Key);
end;

procedure TfrmAnsiVersionPicker.BuildPopupMenu(const AFileName: string);
var
  Item: TMenuItem;
begin
  FPopup.Items.Clear;

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Information';
  Item.Hint := AFileName;
  Item.OnClick := PopupDescriptionClick;
  FPopup.Items.Add(Item);

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Export Mapping...';
  Item.Hint := AFileName;
  Item.OnClick := PopupExportClick;
  FPopup.Items.Add(Item);

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Delete Mapping';
  Item.Hint := AFileName;
  Item.OnClick := PopupDeleteClick;
  FPopup.Items.Add(Item);
end;

procedure TfrmAnsiVersionPicker.ListBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  if Button <> mbRight then
    Exit;
  Idx := ListBox.ItemAtPos(Point(X, Y), True);
  if (Idx >= 0) and (Idx < FMappingFileNames.Count) then
  begin
    ListBox.ItemIndex := Idx;
    BuildPopupMenu(FMappingFileNames[Idx]);
    // The menu is a separate top-level window that is not a child of this form,
    // so a click on it would otherwise look exactly like a click outside and
    // tear the popup down mid-selection.
    PickerMouseHookSuspend;
    FInMenuLoop := True;
    try
      FPopup.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
    finally
      FInMenuLoop := False;
      PickerMouseHookResume;
      // A menu command may have asked to close while this loop was up; that is
      // the only moment it is safe to destroy the form.
      if FPendingFree then
        FinishClose;
    end;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupExportClick(Sender: TObject);
var
  MapFile: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapFile := (Sender as TMenuItem).Hint;
  if MapFile = '' then
    Exit;

  // Snapshot the exact file, unregister and hide - then do the shared work.
  // The save dialog below pumps messages, and no handler may run on a form
  // that has already been freed.
  BeginClose;
  try
    ExportMappingFile(MapFile);
  finally
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupDescriptionClick(Sender: TObject);
var
  MapFile: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapFile := (Sender as TMenuItem).Hint;
  if MapFile = '' then
    Exit;

  // Choosing any context-menu action dismisses the transient popup. The form is
  // unregistered and hidden first so the password prompt inside the shared
  // routine - which is modal and pumps messages - is neither starved of
  // keystrokes by the hook nor able to free the form this handler is still
  // running on.
  BeginClose;
  try
    ShowMappingDescription(MapFile);
  finally
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupDeleteClick(Sender: TObject);
var
  MapFile: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapFile := (Sender as TMenuItem).Hint;
  if MapFile = '' then
    Exit;

  // The single shared delete path - exact file identity, sibling untouched,
  // exact delete ordering. The transient popup is unregistered and hidden
  // before its confirmation dialog pumps messages.
  BeginClose;
  try
    DeleteMappingFile(MapFile);
  finally
    FinishClose;
  end;
end;

end.
