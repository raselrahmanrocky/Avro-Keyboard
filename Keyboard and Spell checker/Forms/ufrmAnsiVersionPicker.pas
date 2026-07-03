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
  Variants,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  Generics.Collections,
  uRegistrySettings,
  clsUnicodeToBijoy2000;

  type
  TfrmAnsiVersionPicker = class(TForm)
    ListBox: TListBox;
    procedure FormDeactivate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListBoxDblClick(Sender: TObject);
    procedure ListBoxClick(Sender: TObject);
  private
    function GetSelectedVersion: string;
  public
    procedure Setup;
    procedure PopulateVersions;
  end;

var
  frmAnsiVersionPicker: TfrmAnsiVersionPicker;
  AnsiPickerVisible: Boolean;

implementation

uses
  uForm1,
  ufrmAnsiToast;

procedure TfrmAnsiVersionPicker.Setup;
begin
  BorderStyle := bsNone;
  FormStyle := fsStayOnTop;
  Color := clWhite;
  Width := 320;
  Height := 280;
  ListBox := TListBox.Create(Self);
  ListBox.Parent := Self;
  ListBox.Align := alClient;
  ListBox.Font.Size := 11;
  ListBox.Font.Name := 'Segoe UI';
  ListBox.ItemHeight := 22;
  ListBox.OnKeyDown := ListBoxKeyDown;
  ListBox.OnDblClick := ListBoxDblClick;
  ListBox.OnClick := ListBoxClick;
  OnDeactivate := FormDeactivate;
  OnClose := FormClose;
  PopulateVersions;
end;

procedure TfrmAnsiVersionPicker.PopulateVersions;
var
  SearchRec: TSearchRec;
  FileTitle, ItemText: string;
  Idx: Integer;
begin
  ListBox.Items.BeginUpdate;
  try
    ListBox.Clear;
    ItemText := Format('1. %s', ['Default']);
    Idx := ListBox.Items.Add(ItemText);
    if AnsiVersion = 'Default' then
      ListBox.ItemIndex := Idx;
    if DirectoryExists(AnsiMappingDir) then
    begin
      if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SearchRec) = 0 then
      begin
        repeat
          FileTitle := ChangeFileExt(SearchRec.Name, '');
          ItemText := Format('%d. %s', [ListBox.Items.Count + 1, FileTitle]);
          Idx := ListBox.Items.Add(ItemText);
          if UpperCase(AnsiVersion) = UpperCase(FileTitle) then
            ListBox.ItemIndex := Idx;
        until FindNext(SearchRec) <> 0;
        FindClose(SearchRec);
      end;
    end;
  finally
    ListBox.Items.EndUpdate;
  end;
end;

function TfrmAnsiVersionPicker.GetSelectedVersion: string;
var
  S: string;
  P: Integer;
begin
  if ListBox.ItemIndex < 0 then Exit('');
  S := ListBox.Items[ListBox.ItemIndex];
  P := Pos('. ', S);
  if P > 0 then
    Result := Trim(Copy(S, P + 2, Length(S)))
  else
    Result := S;
end;

procedure TfrmAnsiVersionPicker.ListBoxKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Num: Integer;
begin
  if Key = VK_ESCAPE then
  begin
    Close;
    Exit;
  end;
  if Key = VK_RETURN then
  begin
    if ListBox.ItemIndex >= 0 then
      ListBoxDblClick(nil);
    Exit;
  end;
  if (Key >= Ord('0')) and (Key <= Ord('9')) then
  begin
    if Key = Ord('0') then
      Num := 9
    else
      Num := (Key - Ord('1'));
    if Num < ListBox.Items.Count then
      ListBox.ItemIndex := Num;
    Key := 0;
  end;
end;

procedure TfrmAnsiVersionPicker.ListBoxDblClick(Sender: TObject);
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
end;

procedure TfrmAnsiVersionPicker.ListBoxClick(Sender: TObject);
begin
end;

procedure TfrmAnsiVersionPicker.FormDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TfrmAnsiVersionPicker.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  AnsiPickerVisible := False;
  frmAnsiVersionPicker := nil;
end;

end.
