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
  ufrmAnsiToast;

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
  if IsWindow(Handle) then
  begin
    ForceForegroundWindow(Handle);
    if ListBox.CanFocus then
      ListBox.SetFocus;
  end;
end;

procedure TfrmAnsiVersionPicker.WMTimer(var Msg: TMessage);
begin
  if GetForegroundWindow <> Handle then
  begin
    KillTimer(Handle, 1);
    Close;
  end;
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
  SearchRec: TSearchRec;
  FileTitle: string;
  I:         Integer;
begin
  AvroMainForm1.CleanupDuplicateMappings;
  ListBox.Items.BeginUpdate;
  try
    ListBox.Clear;
    ListBox.Items.Add('Default');
    if DirectoryExists(AnsiMappingDir) then
    begin
      if System.SysUtils.FindFirst(AnsiMappingDir + '*.json', System.SysUtils.faAnyFile, SearchRec) = 0 then
      begin
        repeat
          FileTitle := ChangeFileExt(SearchRec.Name, '');
          if not SameText(FileTitle, 'Default') then
            ListBox.Items.Add(FileTitle);
        until System.SysUtils.FindNext(SearchRec) <> 0;
        System.SysUtils.FindClose(SearchRec);
      end;
    end;
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

procedure TfrmAnsiVersionPicker.ListBoxClick(Sender: TObject);
var
  SelectedVersion, ErrorMsg: string;
begin
  if not Assigned(CurrentPicker) then
    Exit;
  SelectedVersion := GetSelectedVersion;
  if SelectedVersion = '' then
    Exit;
  if not TrySetAnsiVersion(SelectedVersion, ErrorMsg) then
  begin
    Application.MessageBox(PChar('Could not load the selected ANSI mapping.' + sLineBreak + 'Error: ' + ErrorMsg), 'ANSI Mapping Error',
      MB_ICONWARNING or MB_OK);
    Exit;
  end;
  AnsiVersion := SelectedVersion;
  SaveSettings;
  AvroMainForm1.BuildAnsiVersionMenus;
  if ShowAnsiSwitchNotification = 'YES' then
    ShowAnsiToastNotification('ANSI Version: ' + SelectedVersion);
  if IsWindow(FPrevFocusedWindow) then
    Windows.SetFocus(FPrevFocusedWindow);
  if FPrevForegroundWindow <> 0 then
    SetForegroundWindow(FPrevForegroundWindow);
  CurrentPicker := nil;
  Release;
end;

procedure TfrmAnsiVersionPicker.ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  TargetIdx: Integer;
begin
  TargetIdx := -1;

  case Key of
    VK_ESCAPE:
      begin
        if Assigned(CurrentPicker) then
          Close;
      end;
    VK_RETURN:
      if ListBox.ItemIndex >= 0 then
        ListBoxClick(nil);
    VK_UP:
      begin
        if ListBox.ItemIndex <= 0 then
          ListBox.ItemIndex := ListBox.Items.Count - 1
        else
          ListBox.ItemIndex := ListBox.ItemIndex - 1;
        Key := 0;
      end;
    VK_DOWN:
      begin
        if ListBox.ItemIndex >= ListBox.Items.Count - 1 then
          ListBox.ItemIndex := 0
        else
          ListBox.ItemIndex := ListBox.ItemIndex + 1;
        Key := 0;
      end;
    Ord('1') .. Ord('9'):
      TargetIdx := Key - Ord('1');
    VK_NUMPAD1 .. VK_NUMPAD9:
      TargetIdx := Key - VK_NUMPAD1;
  end;

  if (TargetIdx >= 0) and (TargetIdx < ListBox.Items.Count) then
  begin
    ListBox.ItemIndex := TargetIdx;
    ListBoxClick(nil);
    Key := 0;
  end;
end;

procedure TfrmAnsiVersionPicker.BuildPopupMenu(const MappingName: string);
var
  Item: TMenuItem;
  IsDefault: Boolean;
begin
  FPopup.Items.Clear;
  IsDefault := SameText(MappingName, 'Default');

  Item := TMenuItem.Create(FPopup);
  Item.Caption := 'Read Description';
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
  MapName := (Sender as TMenuItem).Hint;

  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.Filter := 'ANSI Mapping JSON|*.json';
    SaveDlg.DefaultExt := 'json';
    SaveDlg.Title := 'Export ' + MapName + ' Mapping';
    SaveDlg.FileName := MapName + '.json';
    if SaveDlg.Execute then
    begin
      if SameText(MapName, 'Default') then
        ExportAnsiMapping(SaveDlg.FileName)
      else
      begin
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
  MapName, FilePath, Content, DescText: string;
begin
  if not (Sender is TMenuItem) then Exit;
  MapName := (Sender as TMenuItem).Hint;

  if SameText(MapName, 'Default') then
  begin
    MessageDlg('Default Bijoy 2000 compatible ANSI mapping built into Avro Keyboard.', mtInformation, [mbOK], 0);
    Exit;
  end;

  FilePath := AnsiMappingDir + MapName + '.json';
  if FileExists(FilePath) then
  begin
    try
      Content := TFile.ReadAllText(FilePath, TEncoding.UTF8);
      DescText := 'Mapping: ' + MapName + sLineBreak +
                  'Location: ' + FilePath + sLineBreak + sLineBreak +
                  'Preview:' + sLineBreak +
                  Copy(Content, 1, 350) + '...';
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
  MapName := (Sender as TMenuItem).Hint;

  if MessageDlg('Delete mapping "' + MapName + '"?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    if DeleteFile(AnsiMappingDir + MapName + '.json') then
    begin
      if SameText(AnsiVersion, MapName) then
      begin
        AnsiVersion := 'Default';
        SaveSettings;
      end;
      AvroMainForm1.BuildAnsiVersionMenus;
      PopulateVersions;
      AutoSizeForm;
    end;
  end;
end;

end.