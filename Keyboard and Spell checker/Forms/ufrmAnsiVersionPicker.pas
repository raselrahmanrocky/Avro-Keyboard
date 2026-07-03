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
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, Generics.Collections, uRegistrySettings,
  clsUnicodeToBijoy2000;

type
  TfrmAnsiVersionPicker = class(TForm)
    ListBox: TListBox;
    procedure FormShow(Sender: TObject);
    procedure FormDeactivate(Sender: TObject);
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
    function GetSelectedVersion: string;
    procedure AutoSizeForm;
    procedure WMActivate(var Msg: TWMActivate); message WM_ACTIVATE;
  public
    procedure Setup;
    procedure PopulateVersions;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  frmAnsiVersionPicker: TfrmAnsiVersionPicker;
  AnsiPickerVisible: Boolean;

implementation

uses
  uForm1,
  ufrmAnsiToast;

{ TfrmAnsiVersionPicker }

procedure TfrmAnsiVersionPicker.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TfrmAnsiVersionPicker.WMActivate(var Msg: TWMActivate);
begin
  inherited;
  if Msg.Active = WA_INACTIVE then
    Close;
end;

procedure TfrmAnsiVersionPicker.Setup;
begin
  FHoverIndex := -1;
  FPrevFocusedWindow := GetFocus;
  FPrevForegroundWindow := GetForegroundWindow;
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
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
  OnDeactivate := FormDeactivate;
  OnClose := FormClose;
  PopulateVersions;
  AutoSizeForm;
end;

procedure TfrmAnsiVersionPicker.FormShow(Sender: TObject);
begin
  SetForegroundWindow(Handle);
  ListBox.SetFocus;
end;

procedure TfrmAnsiVersionPicker.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  Action := caFree;
  AnsiPickerVisible := False;
  frmAnsiVersionPicker := nil;
end;

procedure TfrmAnsiVersionPicker.FormDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TfrmAnsiVersionPicker.PopulateVersions;
var
  SearchRec: TSearchRec;
  FileTitle: string;
  I: Integer;
begin
  ListBox.Items.BeginUpdate;
  try
    ListBox.Clear;
    ListBox.Items.Add('Default');
    if DirectoryExists(AnsiMappingDir) then
    begin
      if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SearchRec) = 0 then
      begin
        repeat
          FileTitle := ChangeFileExt(SearchRec.Name, '');
          ListBox.Items.Add(FileTitle);
        until FindNext(SearchRec) <> 0;
        FindClose(SearchRec);
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
begin
  MaxW := 0;
  Canvas.Font := ListBox.Font;
  for I := 0 to ListBox.Items.Count - 1 do
  begin
    W := Canvas.TextWidth(ListBox.Items[I]);
    if W > MaxW then
      MaxW := W;
  end;
  Width := MaxW + 44;
  Height := ListBox.Items.Count * 26 + 6;
  ListBox.SetBounds(0, 3, Width, Height - 6);
end;

function TfrmAnsiVersionPicker.GetSelectedVersion: string;
begin
  if ListBox.ItemIndex < 0 then
    Result := ''
  else
    Result := ListBox.Items[ListBox.ItemIndex];
end;

procedure TfrmAnsiVersionPicker.ListBoxDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  IsActive, IsHovered: Boolean;
  GutterRect: TRect;
begin
  IsActive := (AnsiVersion = ListBox.Items[Index]);
  IsHovered := (Index = FHoverIndex) or (odSelected in State);

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
  ListBox.Canvas.TextOut(Rect.Left + 35, Rect.Top + 3, ListBox.Items[Index]);
  
  // Reset brush style to solid for next draw cycle
  ListBox.Canvas.Brush.Style := bsSolid;
end;

procedure TfrmAnsiVersionPicker.ListBoxMouseMove(Sender: TObject;
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

procedure TfrmAnsiVersionPicker.ListBoxMouseLeave(Sender: TObject);
begin
  FHoverIndex := -1;
  ListBox.Invalidate;
end;

procedure TfrmAnsiVersionPicker.ListBoxClick(Sender: TObject);
var
  SelectedVersion, ErrorMsg: string;
begin
  SelectedVersion := GetSelectedVersion;
  if SelectedVersion = '' then Exit;
  if not TrySetAnsiVersion(SelectedVersion, ErrorMsg) then
  begin
    Application.MessageBox(
      PChar('Could not load the selected ANSI mapping.' + sLineBreak +
            'Error: ' + ErrorMsg),
      'ANSI Mapping Error',
      MB_ICONWARNING or MB_OK
    );
    Exit;
  end;
  AnsiVersion := SelectedVersion;
  SaveSettings;
  if ShowAnsiSwitchNotification = 'YES' then
    ShowAnsiToastNotification('ANSI Version Switched to: ' + SelectedVersion);
  Close;
  if FPrevForegroundWindow <> 0 then
    SetForegroundWindow(FPrevForegroundWindow);
  if FPrevFocusedWindow <> 0 then
    PostMessage(FPrevFocusedWindow, WM_SETFOCUS, 0, 0);
end;

procedure TfrmAnsiVersionPicker.ListBoxKeyDown(Sender: TObject;
  var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      Close;
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
      begin
        ListBox.ItemIndex := Key - Ord('1');
        Key := 0;
      end;
    Ord('0'):
      begin
        if ListBox.Items.Count > 9 then
          ListBox.ItemIndex := 9;
        Key := 0;
      end;
  end;
end;

end.
