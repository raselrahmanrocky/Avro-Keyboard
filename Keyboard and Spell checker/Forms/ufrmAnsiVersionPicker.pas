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

  { Trailing layout badge: the same 16 px icon the tray's "Select ANSI
    Encoding" submenu draws on the right of every row that carries one.
    BADGE_RIGHT_GAP + BADGE_SIZE is the badge's inset from the row's right
    edge, and BADGE_COLUMN is what AutoSizeForm adds to the widest caption so
    no name can ever run under a badge. }
  BADGE_SIZE      = 16;
  BADGE_RIGHT_GAP = 6;
  BADGE_COLUMN    = 24;

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
    procedure BuildPopupMenu(const MappingName: string);
    private
      FHoverIndex:           Integer;
      FPopup:                TPopupMenu;
      FPrevFocusedWindow:    HWND;
      FPrevForegroundWindow: HWND;
      // Resolved once per open (the form is created fresh every time it is
      // shown), so the draw handler never reads the registry.
      FTheme: TAppThemePalette;

      { Lifetime. A selection can be applied from four places (its own keys, its
        own mouse, the hotkey, a context-menu command), and the apply path can
        raise a modal password prompt or message box - so every one of them goes
        through BeginClose/FinishClose and the state is explicit. }
      FClosing:      Boolean; // no longer accepts input; unregistered; hidden
      FFinished:     Boolean; // destruction has been asked for
      FApplying:     Boolean; // a selection is being applied on this stack
      FInMenuLoop:   Boolean; // our own popup menu owns the stack right now
      FPendingFree:  Boolean; // FinishClose was requested while the menu was up

      { Focus is best effort only - the keyboard hook delivers the navigation
        keys whether or not this popup ever owns the foreground. }
      FShownAt:       DWORD;
      FWasForeground: Boolean;
      FFocusTries:    Integer;

      function RowIconHandle(const AVersionName: string): HICON;
      procedure AutoSizeForm;
      procedure TryActivateSelf;
      procedure ApplySelection(const ASelectedVersion: string);
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
  // Row badges are drawn from the mapping payloads; resolve them for the rows
  // this popup is about to paint (idempotent - normally all resolved already).
  EnsureMappingIcons;
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
  if (not FClosing) and FWasForeground and (Application.ModalLevel = 0) and
    (GetTickCount - FShownAt > PICKER_ACTIVATION_GRACE_MS) then
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
    ListBox.Items.Add('Default');
    // The name list is cached on the main form and kept fresh by the
    // directory watcher / periodic poll / import / delete flows - opening
    // the picker costs no disk I/O and no duplicate-cleanup side effects.
    if Assigned(AvroMainForm1) and Assigned(AvroMainForm1.AnsiMappingNames) then
      for I := 0 to AvroMainForm1.AnsiMappingNames.Count - 1 do
        ListBox.Items.Add(AvroMainForm1.AnsiMappingNames[I]);
  finally
    ListBox.Items.EndUpdate;
  end;
  for I := 0 to ListBox.Items.Count - 1 do
    if SameText(ListBox.Items[I], AnsiVersion) then
    begin
      ListBox.ItemIndex := I;
      Break;
    end;
end;

procedure TfrmAnsiVersionPicker.AutoSizeForm;
var
  I, W, MaxW: Integer;
  TempStr:    string;
  HasBadge:   Boolean;
begin
  MaxW := 0;
  HasBadge := False;
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
    if not HasBadge then
      HasBadge := RowIconHandle(ListBox.Items[I]) <> 0;
  end;
  // +58 is the gutter, the caption inset and the right margin. When any row
  // draws a trailing badge the column it needs is reserved as well, once for
  // the widest caption - more than the badge's own inset, so a long name can
  // never run under it. A folder of iconless mappings keeps its exact width.
  if HasBadge then
    Width := MaxW + 58 + BADGE_COLUMN
  else
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

{ The row's badge handle, or 0 when that row draws none. The handle is borrowed
  from the main form's icon cache (DPI-keyed, filled by the startup preload and
  released by ReleaseAnsiIconCache), so it must never be destroyed here - there
  is nothing to free, and therefore nothing that can leak.
  'Default' is the built-in mapping with no container of its own, so it has no
  icon, exactly as in the tray's ANSI submenu. }
function TfrmAnsiVersionPicker.RowIconHandle(const AVersionName: string): HICON;
begin
  Result := 0;
  if SameText(AVersionName, 'Default') then
    Exit;
  if Assigned(AvroMainForm1) then
    Result := AvroMainForm1.GetAnsiTrayIcon(AVersionName);
end;

procedure TfrmAnsiVersionPicker.ListBoxDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect:          TRect;
  DisplayText:         string;
  IconHandle:          HICON;
begin
  if (Index < 0) or (Index >= ListBox.Items.Count) then
  begin
    ListBox.Canvas.Brush.Color := FTheme.Background;
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;
  IsActive := SameText(AnsiVersion, ListBox.Items[Index]);
  IsHovered := (Index = FHoverIndex) or (odSelected in State);

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
  if Index < 9 then
    DisplayText := IntToStr(Index + 1) + '. ' + ListBox.Items[Index]
  else
    DisplayText := ListBox.Items[Index];
  ListBox.Canvas.TextOut(Rect.Left + 34, Rect.Top + 4, DisplayText);

  ListBox.Canvas.Brush.Style := bsSolid;

  // 6. Trailing layout badge - the same 16 px icon the tray's "Select ANSI
  // Encoding" submenu shows, so the picker and the menu agree about which
  // encoding carries which icon. Rows without an icon ('Default', or a
  // container whose icon section is missing) stay badge-free.
  IconHandle := RowIconHandle(ListBox.Items[Index]);
  if IconHandle <> 0 then
    DrawIconEx(ListBox.Canvas.Handle, Rect.Right - BADGE_RIGHT_GAP - BADGE_SIZE, Rect.Top + ((Rect.Bottom - Rect.Top - BADGE_SIZE) div 2), IconHandle,
      BADGE_SIZE, BADGE_SIZE, 0, 0, DI_NORMAL);
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
  SelectedVersion: string;
begin
  if FClosing then
    Exit;
  if (AIndex < 0) or (AIndex >= ListBox.Items.Count) then
    Exit;

  SelectedVersion := ListBox.Items[AIndex];
  if SelectedVersion = '' then
    Exit;

  ListBox.ItemIndex := AIndex;

  BeginClose;
  FApplying := True;
  try
    ApplySelection(SelectedVersion);
  finally
    FApplying := False;
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.ApplySelection(const ASelectedVersion: string);
var
  ErrorMsg, TargetPath: string;
  Password:             AnsiString;
  PreloadThread:        TAnsiPreloadThread;
  ErrList:              TStringList;
begin
  if not Assigned(AvroMainForm1) then
    Exit;

  // Default
  if SameText(ASelectedVersion, 'Default') then
  begin
    ErrorMsg := '';
    if not AnsiEngineManager.TrySwitchCached('Default') then
    begin
      Screen.Cursor := crHourGlass;
      ErrList := TStringList.Create;
      try
        if not AnsiEngineManager.SwitchEngine('Default', ErrList) then
          ErrorMsg := 'Encoding is still being prepared. Please select it again.';
      finally
        ErrList.Free;
        Screen.Cursor := crDefault;
      end;
    end;
    if ErrorMsg = '' then
    begin
      AvroMainForm1.SyncActiveMappingTimestamp('Default');
      SaveAnsiVersionOnly;
      AvroMainForm1.UpdateAnsiVersionMenuChecks('Default');
      AvroMainForm1.UpdateTrayIcon;
      if ShowAnsiSwitchNotification = 'YES' then
        ShowAnsiToastNotification('ANSI Version: Default');
    end
    else
      ShowAnsiToastNotification(ErrorMsg);
    Exit;
  end;

  TargetPath := GetActiveEncoFilePath(ASelectedVersion, AnsiMappingDir);
  if TargetPath = '' then
  begin
    Application.MessageBox(PChar('Mapping file not found: ' + ASelectedVersion), 'ANSI Mapping Error', MB_ICONWARNING or MB_OK or MB_TOPMOST or
        MB_SETFOREGROUND);
    Exit;
  end;

  // Only password-protected files (flag $01 / legacy v1) prompt, and only
  // when no usable password is cached yet; TrySetAnsiVersion then reuses
  // CachedEncoPassword and never prompts a second time. Default-key files
  // (flag $00) must NEVER ask for a password - they decrypt transparently.
  // Ask only when THIS encoding was never unlocked on this computer; the
  // per-file cache then unlocks every later switch silently (even after a
  // full restart). Default-key files never prompt.
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
    //
    // It used to warm the whole folder (CapturePreloadList), which is the
    // startup bloat this branch removed: one unlock is one layout, and every
    // other container was being parsed just for the privilege of sitting in
    // RAM. CapturePreloadItem returns a single item - the one the user is
    // about to select.
    PreloadThread := TAnsiPreloadThread.Create(AnsiEngineManager.CapturePreloadItem(ASelectedVersion));
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
  if not AnsiEngineManager.TrySwitchCached(ASelectedVersion) then
  begin
    Screen.Cursor := crHourGlass;
    ErrList := TStringList.Create;
    try
      if not AnsiEngineManager.SwitchEngine(ASelectedVersion, ErrList) then
        ErrorMsg := 'Encoding is still being prepared. Please select it again.';
    finally
      ErrList.Free;
      Screen.Cursor := crDefault;
    end;
  end;
  if ErrorMsg = '' then
  begin
    AnsiVersion := ASelectedVersion;
    AvroMainForm1.SyncActiveMappingTimestamp(ASelectedVersion);
    SaveAnsiVersionOnly;
    AvroMainForm1.UpdateAnsiVersionMenuChecks(ASelectedVersion);
    AvroMainForm1.UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Version: ' + ASelectedVersion);

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

procedure TfrmAnsiVersionPicker.BuildPopupMenu(const MappingName: string);
var
  Item:      TMenuItem;
  IsDefault: Boolean;
begin
  FPopup.Items.Clear;
  IsDefault := SameText(MappingName, 'Default');

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Information';
  Item.Hint := MappingName;
  Item.OnClick := PopupDescriptionClick;
  FPopup.Items.Add(Item);

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Export Mapping...';
  Item.Hint := MappingName;
  Item.OnClick := PopupExportClick;
  FPopup.Items.Add(Item);

  if not IsDefault then
  begin
    Item := TMenuItem.Create(FPopup);
    Item.Caption := 'Delete Mapping';
    Item.Hint := MappingName;
    Item.OnClick := PopupDeleteClick;
    FPopup.Items.Add(Item);
  end;
end;

procedure TfrmAnsiVersionPicker.ListBoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
begin
  if Button <> mbRight then
    Exit;
  Idx := ListBox.ItemAtPos(Point(X, Y), True);
  if (Idx >= 0) and (Idx < ListBox.Items.Count) then
  begin
    ListBox.ItemIndex := Idx;
    BuildPopupMenu(ListBox.Items[Idx]);
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
  MapName, SourcePath: string;
  SaveDlg:             TSaveDialog;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapName := (Sender as TMenuItem).Hint;
  if MapName = '' then
    Exit;

  // Snapshot the name, unregister and hide - then do the work. The save dialog
  // below pumps messages, and no handler may run on a form that has already
  // been freed.
  BeginClose;
  try
    if SameText(MapName, 'Default') then
    begin
      MessageDlg('Built-in Default mapping cannot be exported as a file.' + sLineBreak + 'It is compiled into Avro Keyboard.', mtInformation, [mbOK], 0);
      Exit;
    end;

    SourcePath := AnsiMappingDir + MapName + '.AvroEnco';
    if not FileExists(SourcePath) then
    begin
      MessageDlg('Mapping file not found: ' + MapName, mtError, [mbOK], 0);
      Exit;
    end;

    SaveDlg := TSaveDialog.Create(nil);
    try
      SaveDlg.Filter := 'Avro Encoded Mapping|*.AvroEnco';
      SaveDlg.DefaultExt := 'AvroEnco';
      SaveDlg.Title := 'Export ' + MapName + ' Mapping';
      SaveDlg.FileName := MapName + '.AvroEnco';
      if SaveDlg.Execute then
      begin
        if Windows.CopyFile(PChar(SourcePath), PChar(SaveDlg.FileName), False) then
          MessageDlg('Mapping exported to: '#13#10 + SaveDlg.FileName, mtInformation, [mbOK], 0)
        else
          MessageDlg('Failed to export file: ' + SysErrorMessage(GetLastError), mtError, [mbOK], 0);
      end;
    finally
      SaveDlg.Free;
    end;
  finally
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupDescriptionClick(Sender: TObject);
var
  MapName, FilePath, Content, DescText, MetaText: string;
  Password:                                       AnsiString;
  IsProtected:                                    Boolean;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapName := (Sender as TMenuItem).Hint;
  if MapName = '' then
    Exit;

  // Choosing any context-menu action dismisses the transient popup. The form is
  // unregistered and hidden first so the password prompt below - which is modal
  // and pumps messages - is neither starved of keystrokes by the hook nor able
  // to free the form this handler is still running on.
  BeginClose;
  try
    IsProtected := False;

    if SameText(MapName, 'Default') then
    begin
      MessageDlg('Default Bijoy 2000 compatible ANSI mapping built into Avro Keyboard.', mtInformation, [mbOK], 0);
      Exit;
    end;

    FilePath := AnsiMappingDir + MapName + '.AvroEnco';
    if not FileExists(FilePath) then
      FilePath := AnsiMappingDir + MapName + '.json';
    if FileExists(FilePath) then
    begin
      try
        if IsEncoFile(FilePath) then
        begin
          // Captured here, before the metadata fallback may swap in a same-named
          // .json file below: mark the card when this container is protected by
          // a user password (flag $01 / legacy v1).
          IsProtected := (GetAvroEncoProtectionFlag(FilePath) = AVROENCO_FLAG_USER_PASSWORD);
          // Only password-protected files (flag $01 / legacy v1) prompt, and
          // only the very first time on this computer - the per-file cache
          // decrypts silently afterwards. Default-key files never prompt.
          if (GetEncoCachedPassword(FilePath) = '') and (GetAvroEncoProtectionFlag(FilePath) = AVROENCO_FLAG_USER_PASSWORD) then
          begin
            if not PromptForPasswordAndValidate(FilePath, Password) then
              Exit;
            CachedEncoPassword := Password;
            RememberEncoPassword(FilePath, Password);
            SaveSettings;
          end;
          Content := DecryptAvroEncoToString(FilePath, GetEncoCachedPassword(FilePath));
          if Content = '' then
          begin
            CachedEncoPassword := '';
            ForgetEncoPassword(FilePath);
            MessageDlg('Failed to decrypt mapping. Password may be incorrect.', mtError, [mbOK], 0);
            Exit;
          end;
        end
        else
          Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);

        // Prefer the structured Metadata block (Encoding/Type/Version/Developer/Font);
        MetaText := ExtractMetadataFromJSON(Content, FilePath);
        if (MetaText = '') and SameText(ExtractFileExt(FilePath), '.AvroEnco') then
        begin
          // Old .AvroEnco files (encrypted before Metadata existed) have none;
          // fall back to the same-named .json in the mapping folder or assets.
          FilePath := FindMetadataJsonPath(MapName, AnsiMappingDir);
          if FilePath <> '' then
          begin
            Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
            MetaText := ExtractMetadataFromJSON(Content, FilePath);
          end;
        end;
        if MetaText <> '' then
          DescText := MetaText
        else
          // No Metadata at all - show a raw JSON preview.
          DescText := 'Preview:' + sLineBreak + Copy(Content, 1, 350) + '...';

        // Password-protected .AvroEnco containers get a footer line at the very
        // bottom of the card; plain .json and default-key files do not.
        if IsProtected then
        begin
          DescText := TrimRight(DescText);
          if DescText = '' then
            DescText := 'Encrypted Avro ANSI Encoding'
          else
            DescText := DescText + sLineBreak + sLineBreak + 'Encrypted Avro ANSI Encoding';
        end;
        MessageDlg(DescText, mtInformation, [mbOK], 0);
      except
        on E: Exception do
          MessageDlg('Could not read description: ' + E.Message, mtError, [mbOK], 0);
      end;
    end
    else
      MessageDlg('Mapping file not found.', mtError, [mbOK], 0);
  finally
    FinishClose;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupDeleteClick(Sender: TObject);
var
  MapName: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapName := (Sender as TMenuItem).Hint;
  if MapName = '' then
    Exit;

  // Dismiss the transient popup as soon as the action is chosen, before the
  // confirmation dialog pumps messages.
  BeginClose;
  try
    if MessageDlg('Delete mapping "' + MapName + '"?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      if DeleteFile(AnsiMappingDir + MapName + '.AvroEnco') or DeleteFile(AnsiMappingDir + MapName + '.json') then
      begin
        if SameText(AnsiVersion, MapName) then
        begin
          AnsiVersion := 'Default';
          SaveSettings;
          AnsiEngineManager.SwitchEngine('Default');
        end;
        // Drop the deleted engine from the cache so it cannot be restored.
        AnsiEngineManager.RemoveEngine(MapName);
        if Assigned(AvroMainForm1) then
        begin
          AvroMainForm1.BuildAnsiVersionMenus;
          AvroMainForm1.UpdateTrayIcon;
        end;
        // The row list is deliberately NOT rebuilt here: this popup is closing,
        // and repopulating it is what used to touch a freed form.
      end;
    end;
  finally
    FinishClose;
  end;
end;

end.
