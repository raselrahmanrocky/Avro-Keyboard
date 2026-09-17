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
    procedure ListBoxMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PopupExportClick(Sender: TObject);
    procedure PopupDescriptionClick(Sender: TObject);
    procedure PopupDeleteClick(Sender: TObject);
    procedure BuildPopupMenu(const MappingName: string);
    private
      FHoverIndex:           Integer;
      FPopup:                TPopupMenu;
      FPrevFocusedWindow:    HWND;
      FPrevForegroundWindow: HWND;
      function GetSelectedVersion: string;
      procedure AutoSizeForm;
      procedure CloseAndRestoreTarget;
      function HandlePickerKey(var AKey: Word): Boolean;
      function HandlePickerChar(var AChar: Char): Boolean;
      procedure MoveSelection(ADelta: Integer);
      procedure ActivateIndex(AIndex: Integer);
      procedure WMNCActivate(var Msg: TWMNCActivate); message WM_NCACTIVATE;
      procedure WMFocusPicker(var Msg: TMessage); message WM_FOCUS_PICKER;
      procedure WMTimer(var Msg: TMessage); message WM_TIMER;
    public
      procedure Setup;
      procedure PopulateVersions;
      procedure PositionFormNearCursor;
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
  uAnsiEngineManager;

procedure ForceForegroundWindow(HWND: HWND);
var
  ForeThread, ThisThread: DWORD;
begin
  if not IsWindow(HWND) then
    Exit;
  ForeThread := GetWindowThreadProcessId(GetForegroundWindow, nil);
  ThisThread := GetCurrentThreadId;
  if ForeThread <> ThisThread then
  begin
    AttachThreadInput(ForeThread, ThisThread, True);
    try
      SetForegroundWindow(HWND);
      BringWindowToTop(HWND);
      Windows.SetFocus(HWND);
    finally
      AttachThreadInput(ForeThread, ThisThread, False);
    end;
  end
  else
  begin
    SetForegroundWindow(HWND);
    BringWindowToTop(HWND);
    Windows.SetFocus(HWND);
  end;
end;

procedure ShowAnsiVersionPicker;
var
  Picker: TfrmAnsiVersionPicker;
begin
  if Assigned(CurrentPicker) then
  begin
    CurrentPicker.Close;
    CurrentPicker := nil;
    Exit;
  end;
  Picker := TfrmAnsiVersionPicker.CreateNew(Application);
  try
    Picker.Setup;
    Picker.PositionFormNearCursor;
    CurrentPicker := Picker;
    Picker.Show;
    ForceForegroundWindow(Picker.Handle);
  except
    Picker.Free;
    if CurrentPicker = Picker then
      CurrentPicker := nil;
    raise;
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

procedure TfrmAnsiVersionPicker.WMNCActivate(var Msg: TWMNCActivate);
begin
  inherited;
  if not Msg.Active then
    PostMessage(Handle, WM_CLOSE, 0, 0);
end;

procedure TfrmAnsiVersionPicker.Setup;
begin
  FHoverIndex := -1;
  FPrevFocusedWindow := GetFocus;
  FPrevForegroundWindow := GetForegroundWindow;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  PopupMode := pmAuto;
  Color := RGB(246, 246, 246);
  ListBox := TListBox.Create(Self);
  ListBox.Parent := Self;
  ListBox.BorderStyle := bsNone;
  ListBox.Color := RGB(246, 246, 246);
  ListBox.Font.Name := 'Segoe UI';
  ListBox.Font.Size := 10;
  ListBox.Font.Color := RGB(20, 20, 20);
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
  // ActiveControl is deliberately NOT set here: the form is still invisible in
  // Setup, so TWinControl.CanFocus is False and TCustomForm.SetActiveControl
  // would raise EInvalidOperation (SCannotFocus). Focus is established after
  // Show, in WMFocusPicker below.
  KeyPreview := True;
  OnKeyDown := FormKeyDown;
  OnKeyPress := FormKeyPress;

  OnShow := FormShow;
  OnClose := FormClose;
  PopulateVersions;
  AutoSizeForm;
end;

procedure TfrmAnsiVersionPicker.FormShow(Sender: TObject);
begin
  SetTimer(Handle, 1, 200, nil);
  PostMessage(Handle, WM_FOCUS_PICKER, 0, 0);
end;

procedure TfrmAnsiVersionPicker.WMFocusPicker(var Msg: TMessage);
begin
  if not IsWindow(Handle) then
    Exit;
  ForceForegroundWindow(Handle);
  // CanFocus only walks the visible/enabled chain - it says nothing about who
  // really owns the input focus, which is why this check made the shortcuts go
  // dead while mouse clicks kept working. Move the focus, then verify.
  if ListBox.CanFocus then
    ListBox.SetFocus;
  if GetFocus <> ListBox.Handle then
    // The pre-08d48cd build handed the list box this message directly and its
    // keyboard shortcuts worked. Kept as the fallback for when
    // SetForegroundWindow loses the activation race with the menu/popup the
    // picker was opened from.
    PostMessage(ListBox.Handle, WM_SETFOCUS, 0, 0);
end;

procedure TfrmAnsiVersionPicker.WMTimer(var Msg: TMessage);
begin
  // Never close the picker while an app-modal dialog (e.g. the password
  // prompt) is up: closing+freeing the picker from the timer during
  // ListBoxClick's ShowModal would continue executing on a freed form.
  if Application.ModalLevel <> 0 then
    Exit;

  if GetForegroundWindow <> Handle then
  begin
    KillTimer(Handle, 1);
    Close;
    Exit;
  end;

  // Foreground, but the focus went elsewhere (activation raced with the menu
  // that opened the picker): the window looks alive and simply ignores the
  // keyboard. Re-assert the focus; SetFocus is idempotent once it holds.
  if (GetFocus <> ListBox.Handle) and ListBox.CanFocus then
    ListBox.SetFocus;
end;

procedure TfrmAnsiVersionPicker.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  KillTimer(Handle, 1);
  Action := caFree;
  if CurrentPicker = Self then
    CurrentPicker := nil;
end;

destructor TfrmAnsiVersionPicker.Destroy;
begin
  if CurrentPicker = Self then
    CurrentPicker := nil;
  inherited;
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
    if Assigned(AvroMainForm1.AnsiMappingNames) then
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
  Width := MaxW + 56;
  Height := ListBox.Items.Count * 28 + 8;
  ListBox.SetBounds(0, 4, Width, Height - 8);
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

function TfrmAnsiVersionPicker.GetSelectedVersion: string;
begin
  if ListBox.ItemIndex < 0 then
    Result := ''
  else
    Result := ListBox.Items[ListBox.ItemIndex];
end;

procedure TfrmAnsiVersionPicker.ListBoxDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect:          TRect;
  DisplayText:         string;
begin
  if (index < 0) or (index >= ListBox.Items.Count) then
  begin
    ListBox.Canvas.Brush.Color := RGB(246, 246, 246);
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;
  IsActive := SameText(AnsiVersion, ListBox.Items[index]);
  IsHovered := (index = FHoverIndex) or (odSelected in State);

  // 1. Base background
  ListBox.Canvas.Brush.Color := RGB(246, 246, 246);
  ListBox.Canvas.FillRect(Rect);

  // 2. Row highlight on Hover / Selected
  if IsHovered then
  begin
    ListBox.Canvas.Brush.Color := RGB(218, 236, 255);
    ListBox.Canvas.FillRect(Rect);
  end;

  // 3. Left indicator gutter
  GutterRect := Rect;
  GutterRect.Right := Rect.Left + 26;

  // 4. Active indicator
  if IsActive then
  begin
    ListBox.Canvas.Brush.Color := RGB(0, 120, 215);
    ListBox.Canvas.FillRect(GutterRect);

    ListBox.Canvas.Font.Color := RGB(255, 255, 255);
    ListBox.Canvas.Font.Style := [fsBold];
    DrawText(ListBox.Canvas.Handle, #$2713, -1, GutterRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    ListBox.Canvas.Font.Style := [];
  end;

  // 5. Draw item text
  ListBox.Canvas.Brush.Style := bsClear;
  ListBox.Canvas.Font.Color := RGB(20, 20, 20);
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

procedure TfrmAnsiVersionPicker.CloseAndRestoreTarget;
begin
  KillTimer(Handle, 1);
  Hide;
  if CurrentPicker = Self then CurrentPicker := nil;
  if IsWindow(FPrevForegroundWindow) then
    ForceForegroundWindow(FPrevForegroundWindow)
  else if IsWindow(FPrevFocusedWindow) then
    ForceForegroundWindow(FPrevFocusedWindow);
  Release;
end;

procedure TfrmAnsiVersionPicker.ListBoxClick(Sender: TObject);
var
  SelectedVersion, ErrorMsg, TargetPath: string;
  Password: AnsiString;
  PreloadThread: TAnsiPreloadThread;
  ErrList: TStringList;
begin
  if not Assigned(CurrentPicker) then
    Exit;

  SelectedVersion := GetSelectedVersion;
  if SelectedVersion = '' then
    Exit;

  // End the popup/focus lifetime before any engine/settings operation.
  CloseAndRestoreTarget;

  // Default: fast-path
  if SameText(SelectedVersion, 'Default') then
  begin
    if AnsiEngineManager.TrySwitchCached('Default') then
    begin
      AvroMainForm1.SyncActiveMappingTimestamp('Default');
      SaveAnsiVersionOnly;
      AvroMainForm1.UpdateAnsiVersionMenuChecks('Default');
      if ShowAnsiSwitchNotification = 'YES' then
        ShowAnsiToastNotification('ANSI Version: Default');
    end;
    Exit;
  end;

  TargetPath := GetActiveEncoFilePath(SelectedVersion, AnsiMappingDir);
  if TargetPath = '' then
  begin
    Application.MessageBox(PChar('Mapping file not found: ' + SelectedVersion),
      'ANSI Mapping Error', MB_ICONWARNING or MB_OK or MB_TOPMOST or MB_SETFOREGROUND);
    Exit;
  end;

  // Only password-protected files (flag $01 / legacy v1) prompt, and only
  // when no usable password is cached yet; TrySetAnsiVersion then reuses
  // CachedEncoPassword and never prompts a second time. Default-key files
  // (flag $00) must NEVER ask for a password - they decrypt transparently.
  // Ask only when THIS encoding was never unlocked on this computer; the
  // per-file cache then unlocks every later switch silently (even after a
  // full restart). Default-key files never prompt.
  if IsEncoFile(TargetPath) and (GetEncoCachedPassword(TargetPath) = '') and
    (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_USER_PASSWORD) then
  begin
    if not PromptForPasswordAndValidate(TargetPath, Password) then
      Exit; // Cancelled - keep the picker open so another version can be chosen.
    CachedEncoPassword := Password;
    RememberEncoPassword(TargetPath, Password);
    SaveSettings;
    // Build this newly unlocked engine away from the UI. The first click
    // returns immediately; a subsequent click performs a RAM-only switch.
    PreloadThread := TAnsiPreloadThread.Create(
      AnsiEngineManager.CapturePreloadList);
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
  if not AnsiEngineManager.TrySwitchCached(SelectedVersion) then
  begin
    Screen.Cursor := crHourGlass;
    ErrList := TStringList.Create;
    try
      if not AnsiEngineManager.SwitchEngine(SelectedVersion, ErrList) then
        ErrorMsg := 'Encoding is still being prepared. Please select it again.';
    finally
      ErrList.Free;
      Screen.Cursor := crDefault;
    end;
  end;
  if ErrorMsg = '' then
  begin
    AnsiVersion := SelectedVersion;
    AvroMainForm1.SyncActiveMappingTimestamp(SelectedVersion);
    SaveAnsiVersionOnly;
    AvroMainForm1.UpdateAnsiVersionMenuChecks(SelectedVersion);
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Version: ' + SelectedVersion);

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

{ Confirms AIndex exactly like a mouse click does: select the row, switch the
  engine, persist the setting and close the picker. }
procedure TfrmAnsiVersionPicker.ActivateIndex(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= ListBox.Items.Count) then
    Exit;
  ListBox.ItemIndex := AIndex;
  ListBoxClick(nil);
end;

{ Wrapping selection move. Needed at form level too: when the form window holds
  the focus, the list box never sees VK_UP / VK_DOWN at all. }
procedure TfrmAnsiVersionPicker.MoveSelection(ADelta: Integer);
begin
  if ListBox.Items.Count = 0 then
    Exit;
  if ListBox.ItemIndex < 0 then
    ListBox.ItemIndex := 0
  else
    ListBox.ItemIndex := (ListBox.ItemIndex + ADelta + ListBox.Items.Count)
      mod ListBox.Items.Count;
end;

{ The single key implementation. Returns True when the key was consumed, and the
  caller is expected to zero it - which is also what makes VCL skip the other
  handler for the same key, so a shortcut can never be handled twice. }
function TfrmAnsiVersionPicker.HandlePickerKey(var AKey: Word): Boolean;
var
  TargetIdx: Integer;
begin
  Result := True;
  case AKey of
    VK_ESCAPE:
      if Assigned(CurrentPicker) then
        Close;
    VK_RETURN:
      if ListBox.ItemIndex >= 0 then
        ListBoxClick(nil);
    VK_UP:
      MoveSelection(-1);
    VK_DOWN:
      MoveSelection(1);
  else
    begin
      // Number row (VK_1..VK_9) and numpad (VK_NUMPAD1..VK_NUMPAD9), mapping
      // to the very numbers the list draws next to the rows.
      TargetIdx := MappingIndexForKey(ListBox.Items, AKey);
      if TargetIdx < 0 then
        Result := False
      else
        ActivateIndex(TargetIdx);
    end;
  end;
  if Result then
    AKey := 0;
end;

{ First-letter navigation. Zeroing AChar also suppresses the list box's own
  type-ahead for the same letter, so the selection happens exactly once. }
function TfrmAnsiVersionPicker.HandlePickerChar(var AChar: Char): Boolean;
var
  TargetIdx: Integer;
begin
  Result := False;
  if AChar < ' ' then
    Exit;
  TargetIdx := MappingIndexForChar(ListBox.Items, AChar);
  if TargetIdx < 0 then
    Exit;
  AChar := #0;
  Result := True;
  ActivateIndex(TargetIdx);
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
  Item: TMenuItem;
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

procedure TfrmAnsiVersionPicker.ListBoxMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
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
    FPopup.Popup(Mouse.CursorPos.X, Mouse.CursorPos.Y);
  end;
end;

procedure TfrmAnsiVersionPicker.PopupExportClick(Sender: TObject);
var
  MapName, SourcePath: string;
  SaveDlg: TSaveDialog;
begin
  if not (Sender is TMenuItem) then Exit;
  // Dismiss the transient picker as soon as the action is chosen.
  Close;
  MapName := (Sender as TMenuItem).Hint;

  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.Filter := 'Avro Encoded Mapping|*.AvroEnco|ANSI Mapping JSON|*.json';
    SaveDlg.Title := 'Export ' + MapName + ' Mapping';
    if FileExists(AnsiMappingDir + MapName + '.AvroEnco') then
      SaveDlg.DefaultExt := 'AvroEnco'
    else
      SaveDlg.DefaultExt := 'json';
    SaveDlg.FileName := MapName + '.' + SaveDlg.DefaultExt;
    if SaveDlg.Execute then
    begin
      if SameText(MapName, 'Default') then
        ExportAnsiMapping(SaveDlg.FileName)
      else
      begin
        SourcePath := AnsiMappingDir + MapName + '.AvroEnco';
        if not FileExists(SourcePath) then
          SourcePath := AnsiMappingDir + MapName + '.json';
        if FileExists(SourcePath) then
          Windows.CopyFile(PChar(SourcePath), PChar(SaveDlg.FileName), False)
        else
          ExportAnsiMapping(SaveDlg.FileName);
      end;
      MessageDlg('Mapping exported to: '#13#10 + SaveDlg.FileName, mtInformation, [mbOK], 0);
    end;
  finally
    SaveDlg.Free;
  end;
end;

procedure TfrmAnsiVersionPicker.PopupDescriptionClick(Sender: TObject);
var
  MapName, FilePath, Content, DescText, MetaText: string;
  Password: AnsiString;
  IsProtected: Boolean;
begin
  if not (Sender is TMenuItem) then Exit;
  // The picker is a transient popup: choosing any context-menu action
  // dismisses it (Close -> FormClose -> caFree; the form is released
  // asynchronously, so the rest of this handler keeps running safely).
  Close;
  MapName := (Sender as TMenuItem).Hint;
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
        if (GetEncoCachedPassword(FilePath) = '') and
          (GetAvroEncoProtectionFlag(FilePath) = AVROENCO_FLAG_USER_PASSWORD) then
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
        DescText := 'Preview:' + sLineBreak +
                    Copy(Content, 1, 350) + '...';

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
end;

procedure TfrmAnsiVersionPicker.PopupDeleteClick(Sender: TObject);
var
  MapName: string;
begin
  if not (Sender is TMenuItem) then Exit;
  // Dismiss the transient picker as soon as the action is chosen.
  Close;
  MapName := (Sender as TMenuItem).Hint;

  if MessageDlg('Delete mapping "' + MapName + '"?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    if DeleteFile(AnsiMappingDir + MapName + '.AvroEnco') or
       DeleteFile(AnsiMappingDir + MapName + '.json') then
    begin
      if SameText(AnsiVersion, MapName) then
      begin
        AnsiVersion := 'Default';
        SaveSettings;
        AnsiEngineManager.SwitchEngine('Default');
      end;
      // Drop the deleted engine from the cache so it cannot be restored.
      AnsiEngineManager.RemoveEngine(MapName);
      AvroMainForm1.BuildAnsiVersionMenus;
      PopulateVersions;
      AutoSizeForm;
    end;
  end;
end;

end.