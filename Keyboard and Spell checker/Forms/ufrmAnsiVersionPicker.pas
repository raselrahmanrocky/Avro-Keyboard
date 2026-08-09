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
  StdCtrls,
  Generics.Collections,
  System.Types,
  uRegistrySettings,
  clsUnicodeToBijoy2000;

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
    private
      FHoverIndex:           Integer;
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

// Force a window to the foreground using AttachThreadInput — the most reliable way
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
  Color := RGB(242, 242, 242);
  ListBox := TListBox.Create(Self);
  ListBox.Parent := Self;
  ListBox.BorderStyle := bsNone;
  ListBox.Color := RGB(242, 242, 242);
  ListBox.Font.Name := 'Segoe UI';
  ListBox.Font.Size := 10;
  ListBox.Font.Color := RGB(0, 0, 0);
  ListBox.ItemHeight := 26;
  ListBox.Style := lbOwnerDrawFixed;
  ListBox.OnKeyDown := ListBoxKeyDown;
  ListBox.OnClick := ListBoxClick;
  ListBox.OnDrawItem := ListBoxDrawItem;
  ListBox.OnMouseMove := ListBoxMouseMove;
  ListBox.OnMouseLeave := ListBoxMouseLeave;
  ListBox.TabStop := True;
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
    if UpperCase(ListBox.Items[I]) = UpperCase(AnsiVersion) then
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
  Width := MaxW + 44;
  Height := ListBox.Items.Count * 26 + 6;
  ListBox.SetBounds(0, 3, Width, Height - 6);
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
    ListBox.Canvas.Brush.Color := RGB(242, 242, 242);
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;
  IsActive := (AnsiVersion = ListBox.Items[index]);
  IsHovered := (index = FHoverIndex) or (odSelected in State);

  // 1. Base background (Always light gray)
  ListBox.Canvas.Brush.Color := RGB(242, 242, 242);
  ListBox.Canvas.FillRect(Rect);

  // 2. Full-row highlight when mouse is hovered or item is selected
  if IsHovered then
  begin
    ListBox.Canvas.Brush.Color := RGB(209, 232, 255); // Light blue highlight
    ListBox.Canvas.FillRect(Rect);
  end;

  // 3. Define the Gutter area (Square box on the far left)
  GutterRect := Rect;
  GutterRect.Right := Rect.Left + 28; // Set box width

  // 4. Handle Active item state (Gutter highlight and icon)
  if IsActive then
  begin
    // Highlight ONLY the gutter background
    ListBox.Canvas.Brush.Color := RGB(153, 209, 245); // Solid blue for active gutter
    ListBox.Canvas.FillRect(GutterRect);

    // Draw the icon (Checkmark or Dot)
    ListBox.Canvas.Font.Color := RGB(51, 51, 51); // Dark gray icon color
    ListBox.Canvas.Font.Style := [fsBold];
    DrawText(ListBox.Canvas.Handle, #$2713, -1, GutterRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);

    // Reset font style for the main text
    ListBox.Canvas.Font.Style := [];
  end;

  // 5. Draw the main item text (Transparent background, offset from gutter)
  ListBox.Canvas.Brush.Style := bsClear;
  ListBox.Canvas.Font.Color := RGB(0, 0, 0);
  if index < 9 then
    DisplayText := IntToStr(index + 1) + '. ' + ListBox.Items[index]
  else
    DisplayText := ListBox.Items[index];
  ListBox.Canvas.TextOut(Rect.Left + 35, Rect.Top + 3, DisplayText);

  // Reset brush style to solid for next draw cycle
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
  if ShowAnsiSwitchNotification = 'YES' then
    ShowAnsiToastNotification('ANSI Version Switched to: ' + SelectedVersion);
  if IsWindow(FPrevFocusedWindow) then
    Windows.SetFocus(FPrevFocusedWindow);
  if FPrevForegroundWindow <> 0 then
    SetForegroundWindow(FPrevForegroundWindow);
  CurrentPicker := nil;
  Release;
  OptimizeMemoryUsage;
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

end.
