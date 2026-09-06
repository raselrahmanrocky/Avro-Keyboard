{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroLayoutUI;

interface

uses
  Windows,
  SysUtils,
  Classes,
  Dialogs,
  Menus,
  Generics.Collections,
  System.UITypes;

procedure RebuildAnviVersionMenus;
procedure ExportMappingFile(const AMapName: string);
procedure ShowMappingDescription(const AMapName: string);
procedure DeleteMappingFile(const AMapName: string);

implementation

uses
  uForm1,
  System.IOUtils,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAvroEncoImporter,
  ufrmAnsiToast,
  uFileFolderHandling,
  uRegistrySettings,
  clsUnicodeToBijoy2000,
  DebugLog;

{ =============================================================================== }
{ Rebuild ANSI Version Menus }
{ =============================================================================== }

procedure RebuildAnviVersionMenus;

  procedure BuildSingleMenu(AMenu: TMenuItem; const ASearchDir: string);
  var
    SR: TSearchRec;
    FileTitle: string;
    Sep, MoreOptMenu, Item: TMenuItem;
    Info: TAvroEncoFileInfo;
    Key: string;
    DisplayName: string;
    Checked: Boolean;

    procedure AddDirectItem(AParentMenu: TMenuItem; const AName: string; AChecked: Boolean);
    var
      MItem: TMenuItemExtended;
    begin
      MItem := TMenuItemExtended.Create(AParentMenu);
      MItem.Caption := AName;
      MItem.Value := AName;
      MItem.Checked := AChecked;
      MItem.RadioItem := True;
      MItem.Tag := 9903;
      MItem.OnClick := AvroMainForm1.AnsiVersionMenuClick;
      AParentMenu.Add(MItem);
    end;

    procedure AddMappingActionSubmenu(ParentMore: TMenuItem; const AName: string; IsDefault: Boolean);
    var
      MSub, ActionItem: TMenuItem;
    begin
      MSub := TMenuItem.Create(ParentMore);
      MSub.Caption := AName;
      MSub.Hint := AName;
      ParentMore.Add(MSub);

      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Read Description';
      ActionItem.Hint := AName;
      ActionItem.OnClick := AvroMainForm1.ReadAnsiDescriptionClick;
      MSub.Add(ActionItem);

      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Export Mapping...';
      ActionItem.Hint := AName;
      ActionItem.OnClick := AvroMainForm1.ExportSpecificMappingClick;
      MSub.Add(ActionItem);

      if not IsDefault then
      begin
        ActionItem := TMenuItem.Create(MSub);
        ActionItem.Caption := 'Delete Mapping';
        ActionItem.Hint := AName;
        ActionItem.OnClick := AvroMainForm1.DeleteAnsiMappingClick;
        MSub.Add(ActionItem);
      end;
    end;

  begin
    AMenu.Clear;

    AddDirectItem(AMenu, 'Default', SameText(AnsiVersion, 'Default'));

    for Key in AvroEncoFiles.Keys do
    begin
      Info := AvroEncoFiles[Key];
      DisplayName := Info.DisplayName;
      if not SameText(DisplayName, 'Default') then
      begin
        Checked := SameText(AnsiVersion, DisplayName);
        AddDirectItem(AMenu, DisplayName, Checked);
      end;
    end;

    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);

    MoreOptMenu := TMenuItem.Create(AMenu);
    MoreOptMenu.Caption := 'More Options';
    AMenu.Add(MoreOptMenu);

    AddMappingActionSubmenu(MoreOptMenu, 'Default', True);

    for Key in AvroEncoFiles.Keys do
    begin
      Info := AvroEncoFiles[Key];
      DisplayName := Info.DisplayName;
      if not SameText(DisplayName, 'Default') then
        AddMappingActionSubmenu(MoreOptMenu, DisplayName, False);
    end;

    Sep := TMenuItem.Create(MoreOptMenu);
    Sep.Caption := '-';
    MoreOptMenu.Add(Sep);

    Item := TMenuItem.Create(MoreOptMenu);
    Item.Caption := 'Import Mapping...';
    Item.OnClick := AvroMainForm1.ImportAnsiMappingClick;
    MoreOptMenu.Add(Item);

    Item := TMenuItem.Create(MoreOptMenu);
    Item.Caption := 'Locate Mapping...';
    Item.OnClick := AvroMainForm1.OpenAnsiMappingDirClick;
    MoreOptMenu.Add(Item);
  end;

var
  AnsiDir: string;
begin
  AnsiDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiDir);
  ScanAvroEncoFiles(AnsiDir);

  if Assigned(AvroMainForm1.AnsiVersionSubmenu1) then
    BuildSingleMenu(AvroMainForm1.AnsiVersionSubmenu1, AnsiDir);
  if Assigned(AvroMainForm1.AnsiVersionSubmenu2) then
    BuildSingleMenu(AvroMainForm1.AnsiVersionSubmenu2, AnsiDir);
end;

{ =============================================================================== }
{ Export Mapping }
{ =============================================================================== }

procedure ExportMappingFile(const AMapName: string);
var
  SaveDialog: TSaveDialog;
  SourcePath: string;
begin
  if SameText(AMapName, 'Default') then
  begin
    MessageDlg(
      'Built-in Default mapping cannot be exported as a file.' + sLineBreak +
      'It is compiled into Avro Keyboard.',
      mtInformation, [mbOK], 0
    );
    Exit;
  end;

  SourcePath := GetActiveEncoFilePath(AMapName, GetAvroDataDir + 'AnsiMapping\');
  if SourcePath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AMapName, mtError, [mbOK], 0);
    Exit;
  end;

  SaveDialog := TSaveDialog.Create(nil);
  try
    if IsEncoFile(SourcePath) then
    begin
      SaveDialog.Filter := 'Avro Encoded Mapping|*.AvroEnco';
      SaveDialog.DefaultExt := 'AvroEnco';
    end
    else
    begin
      SaveDialog.Filter := 'ANSI Mapping JSON|*.json';
      SaveDialog.DefaultExt := 'json';
    end;
    SaveDialog.Title := 'Export ' + AMapName + ' Mapping';
    SaveDialog.FileName := AMapName + ExtractFileExt(SourcePath);

    if SaveDialog.Execute then
    begin
      if Windows.CopyFile(PChar(SourcePath), PChar(SaveDialog.FileName), False) then
        ShowAnsiToastNotification('Exported: ' + SaveDialog.FileName)
      else
        MessageDlg('Failed to export file: ' + SysErrorMessage(GetLastError), mtError, [mbOK], 0);
    end;
  finally
    SaveDialog.Free;
  end;
end;

{ =============================================================================== }
{ Read Description }
{ =============================================================================== }

procedure ShowMappingDescription(const AMapName: string);
var
  SourcePath, JSONContent, DescText: string;
  Password: AnsiString;
begin
  if SameText(AMapName, 'Default') then
  begin
    MessageDlg(
      'Mapping: Default' + sLineBreak +
      'Built-in Bijoy 2000 compatible ANSI mapping.' + sLineBreak + sLineBreak +
      'Features automatic contextual post-base & pre-base kar mapping.',
      mtInformation, [mbOK], 0
    );
    Exit;
  end;

  SourcePath := GetActiveEncoFilePath(AMapName, GetAvroDataDir + 'AnsiMapping\');
  if SourcePath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AMapName, mtError, [mbOK], 0);
    Exit;
  end;

  if IsEncoFile(SourcePath) then
  begin
    // Only password-protected files (flag $01 / legacy v1) prompt;
    // default-key files (flag $00) decrypt transparently with no cache.
    if (CachedEncoPassword = '') and
      (GetAvroEncoProtectionFlag(SourcePath) = AVROENCO_FLAG_USER_PASSWORD) then
    begin
      if not PromptForPasswordAndValidate(SourcePath, Password) then
        Exit;
      CachedEncoPassword := Password;
    end;

    JSONContent := DecryptAvroEncoToString(SourcePath, CachedEncoPassword);
    if JSONContent = '' then
    begin
      CachedEncoPassword := '';
      MessageDlg('Failed to decrypt mapping. Password may be incorrect.', mtError, [mbOK], 0);
      Exit;
    end;
  end
  else
  begin
    try
      JSONContent := TFile.ReadAllText(SourcePath, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        MessageDlg('Failed to read file: ' + E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
  end;

  DescText := 'Mapping: ' + AMapName + sLineBreak +
    'Location: ' + SourcePath + sLineBreak + sLineBreak +
    ExtractMetadataFromJSON(JSONContent);
  MessageDlg(DescText, mtInformation, [mbOK], 0);
end;

{ =============================================================================== }
{ Delete Mapping }
{ =============================================================================== }

procedure DeleteMappingFile(const AMapName: string);
var
  AnsiDir, EncPath, JsonPath: string;
begin
  if SameText(AMapName, 'Default') then
  begin
    MessageDlg('Built-in Default mapping cannot be deleted.', mtInformation, [mbOK], 0);
    Exit;
  end;

  if MessageDlg(
    'Are you sure you want to delete the mapping "' + AMapName + '"?',
    mtConfirmation, [mbYes, mbNo], 0
  ) <> mrYes then
    Exit;

  AnsiDir := GetAvroDataDir + 'AnsiMapping\';
  EncPath := AnsiDir + AMapName + '.AvroEnco';
  JsonPath := AnsiDir + AMapName + '.json';

  if FileExists(EncPath) then
    DeleteFile(EncPath);
  if FileExists(JsonPath) then
    DeleteFile(JsonPath);

  if SameText(AnsiVersion, AMapName) then
  begin
    AnsiVersion := 'Default';
    SaveSettings;
    LoadCurrentActiveMapping;
  end;

  ScanAvroEncoFiles(AnsiDir);
  AvroMainForm1.BuildAnsiVersionMenus;
  ShowAnsiToastNotification('Mapping deleted: ' + AMapName);
  Log('Deleted mapping: ' + AMapName);
end;

end.
