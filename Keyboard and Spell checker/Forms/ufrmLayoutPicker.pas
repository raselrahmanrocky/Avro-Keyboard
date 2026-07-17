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
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, System.Types, uRegistrySettings;

const
  WM_FOCUS_LAYOUT_PICKER = WM_APP + 4;

type
  TfrmLayoutPicker = class(TForm)
    ListBox: TListBox;
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListBoxClick(Sender: TObject);
    procedure ListBoxDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure ListBoxMouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure ListBoxMouseLeave(Sender: TObject);
  private
    FHoverIndex: Integer;
    FPrevFocusedWindow: HWND;
    FPrevForegroundWindow: HWND;
    FLayoutNames: TStringList;
    FLayoutValues: TStringList;
    function GetSelectedLayoutValue: string;
    procedure AutoSizeForm;
    procedure WMNCActivate(var Msg: TWMNCActivate); message WM_NCACTIVATE;
    procedure WMFocusPicker(var Msg: TMessage); message WM_FOCUS_LAYOUT_PICKER;
    procedure WMTimer(var Msg: TMessage); message WM_TIMER;
  public
    procedure Setup;
    procedure PopulateLayouts;
    procedure PositionFormNearCursor;
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
  KeyboardLayoutLoader;

procedure ForceForegroundWindow(hWnd: HWND);
var
  ForeThread, ThisThread: DWORD;
begin
  if not IsWindow(hWnd) then Exit;
  ForeThread := GetWindowThreadProcessId(GetForegroundWindow, nil);
  ThisThread := GetCurrentThreadId;
  if ForeThread <> ThisThread then
  begin
    AttachThreadInput(ForeThread, ThisThread, True);
    try
      SetForegroundWindow(hWnd);
      BringWindowToTop(hWnd);
      Windows.SetFocus(hWnd);
    finally
      AttachThreadInput(ForeThread, ThisThread, False);
    end;
  end
  else
  begin
    SetForegroundWindow(hWnd);
    BringWindowToTop(hWnd);
    Windows.SetFocus(hWnd);
  end;
end;

procedure ShowLayoutPickerPopup;
var
  Picker: TfrmLayoutPicker;
begin
  if Assigned(CurrentLayoutPicker) then
  begin
    CurrentLayoutPicker.Close;
    CurrentLayoutPicker := nil;
    Exit;
  end;
  Picker := TfrmLayoutPicker.CreateNew(Application);
  try
    Picker.Setup;
    Picker.PositionFormNearCursor;
    CurrentLayoutPicker := Picker;
    Picker.Show;
    ForceForegroundWindow(Picker.Handle);
  except
    Picker.Free;
    if CurrentLayoutPicker = Picker then
      CurrentLayoutPicker := nil;
    raise;
  end;
end;

procedure TfrmLayoutPicker.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
  Params.Style := WS_POPUP or WS_CLIPSIBLINGS;
  Params.ExStyle := WS_EX_TOPMOST or WS_EX_TOOLWINDOW;
end;

procedure TfrmLayoutPicker.WMNCActivate(var Msg: TWMNCActivate);
begin
  inherited;
  if not Msg.Active then
    PostMessage(Handle, WM_CLOSE, 0, 0);
end;

procedure TfrmLayoutPicker.Setup;
begin
  FHoverIndex := -1;
  FPrevFocusedWindow := GetFocus;
  FPrevForegroundWindow := GetForegroundWindow;
  FLayoutNames := TStringList.Create;
  FLayoutValues := TStringList.Create;
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
  PopulateLayouts;
  AutoSizeForm;
end;

procedure TfrmLayoutPicker.FormShow(Sender: TObject);
begin
  SetTimer(Handle, 1, 200, nil);
  PostMessage(Handle, WM_FOCUS_LAYOUT_PICKER, 0, 0);
end;

procedure TfrmLayoutPicker.WMFocusPicker(var Msg: TMessage);
begin
  if IsWindow(Handle) then
  begin
    ForceForegroundWindow(Handle);
    if ListBox.CanFocus then
      ListBox.SetFocus;
  end;
end;

procedure TfrmLayoutPicker.WMTimer(var Msg: TMessage);
begin
  if GetForegroundWindow <> Handle then
  begin
    KillTimer(Handle, 1);
    Close;
  end;
end;

procedure TfrmLayoutPicker.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  KillTimer(Handle, 1);
  Action := caFree;
  if CurrentLayoutPicker = Self then
    CurrentLayoutPicker := nil;
end;

destructor TfrmLayoutPicker.Destroy;
begin
  if CurrentLayoutPicker = Self then
    CurrentLayoutPicker := nil;
  FreeAndNil(FLayoutNames);
  FreeAndNil(FLayoutValues);
  inherited;
end;

procedure TfrmLayoutPicker.PopulateLayouts;
var
  I: Integer;
  CurrentLayout, LayoutName, LayoutValue: string;
  ItemFound: Boolean;
begin
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
  TempStr: string;
begin
  MaxW := 0;
  Canvas.Font := ListBox.Font;
  for I := 0 to ListBox.Items.Count - 1 do
  begin
    if I < 9 then TempStr := IntToStr(I + 1) + '. ' + ListBox.Items[I]
    else TempStr := ListBox.Items[I];
    W := Canvas.TextWidth(TempStr);
    if W > MaxW then
      MaxW := W;
  end;
  Width := MaxW + 44;
  Height := ListBox.Items.Count * 26 + 6;
  ListBox.SetBounds(0, 3, Width, Height - 6);
end;

procedure TfrmLayoutPicker.PositionFormNearCursor;
var
  CursorPos: TPoint;
  Monitor: TMonitor;
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

function TfrmLayoutPicker.GetSelectedLayoutValue: string;
begin
  if ListBox.ItemIndex < 0 then
    Result := ''
  else
    Result := FLayoutValues[ListBox.ItemIndex];
end;

procedure TfrmLayoutPicker.ListBoxDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect: TRect;
  DisplayText: string;
  CurrentLayout: string;
begin
  if (Index < 0) or (Index >= ListBox.Items.Count) then
  begin
    ListBox.Canvas.Brush.Color := RGB(242, 242, 242);
    ListBox.Canvas.FillRect(Rect);
    Exit;
  end;

  CurrentLayout := AvroMainForm1.GetMyCurrentLayout;
  IsActive := (LowerCase(FLayoutValues[Index]) = LowerCase(CurrentLayout));
  IsHovered := (Index = FHoverIndex) or (odSelected in State);

  ListBox.Canvas.Brush.Color := RGB(242, 242, 242);
  ListBox.Canvas.FillRect(Rect);

  if IsHovered then
  begin
    ListBox.Canvas.Brush.Color := RGB(209, 232, 255);
    ListBox.Canvas.FillRect(Rect);
  end;

  GutterRect := Rect;
  GutterRect.Right := Rect.Left + 28;

  if IsActive then
  begin
    ListBox.Canvas.Brush.Color := RGB(153, 209, 245);
    ListBox.Canvas.FillRect(GutterRect);
    ListBox.Canvas.Font.Color := RGB(51, 51, 51);
    ListBox.Canvas.Font.Style := [fsBold];
      DrawText(ListBox.Canvas.Handle, #$2713, -1, GutterRect, DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    ListBox.Canvas.Font.Style := [];
  end;

  ListBox.Canvas.Brush.Style := bsClear;
  ListBox.Canvas.Font.Color := RGB(0, 0, 0);
  if Index < 9 then
    DisplayText := IntToStr(Index + 1) + '. ' + ListBox.Items[Index]
  else
    DisplayText := ListBox.Items[Index];
  ListBox.Canvas.TextOut(Rect.Left + 35, Rect.Top + 3, DisplayText);
  ListBox.Canvas.Brush.Style := bsSolid;
end;

procedure TfrmLayoutPicker.ListBoxMouseMove(Sender: TObject;
  Shift: TShiftState; X, Y: Integer);
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

procedure TfrmLayoutPicker.ListBoxClick(Sender: TObject);
var
  SelectedLayout: string;
begin
  if not Assigned(CurrentLayoutPicker) then Exit;
  SelectedLayout := GetSelectedLayoutValue;
  if SelectedLayout = '' then Exit;

  AvroMainForm1.KeyLayout.CurrentKeyboardLayout := SelectedLayout;

  if ShowLayoutSwitchNotification = 'YES' then
    ShowLayoutToastNotification('Layout switched to: ' + FLayoutNames[ListBox.ItemIndex]);

  if IsWindow(FPrevFocusedWindow) then
    Windows.SetFocus(FPrevFocusedWindow);
  if FPrevForegroundWindow <> 0 then
    SetForegroundWindow(FPrevForegroundWindow);
  CurrentLayoutPicker := nil;
  Release;
end;

procedure TfrmLayoutPicker.ListBoxKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
var
  TargetIdx: Integer;
begin
  TargetIdx := -1;
  case Key of
    VK_ESCAPE:
      begin
        if Assigned(CurrentLayoutPicker) then Close;
      end;
    VK_RETURN:
      if ListBox.ItemIndex >= 0 then ListBoxClick(nil);
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
    Ord('1')..Ord('9'):
      TargetIdx := Key - Ord('1');
    VK_NUMPAD1..VK_NUMPAD9:
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
