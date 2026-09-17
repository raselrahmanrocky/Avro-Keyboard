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
  Vcl.Forms,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.Graphics,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAvroEncoImporter,
  ufrmAnsiToast,
  uFileFolderHandling,
  uRegistrySettings,
  clsUnicodeToBijoy2000,
  uAnsiEngineManager,
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
    I: Integer;
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
      ActionItem.Caption := 'Information';
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

    // AnsiMappingNames is the shared, naturally sorted list of display names
    // that TAvroMainForm1.BuildAnsiVersionMenus and the version picker both
    // use. Enumerating AvroEncoFiles.Keys here read a hash table, whose bucket
    // order could list V4 between V1 and V2.
    if Assigned(AvroMainForm1.AnsiMappingNames) then
      for I := 0 to AvroMainForm1.AnsiMappingNames.Count - 1 do
      begin
        DisplayName := AvroMainForm1.AnsiMappingNames[I];
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

    if Assigned(AvroMainForm1.AnsiMappingNames) then
      for I := 0 to AvroMainForm1.AnsiMappingNames.Count - 1 do
      begin
        DisplayName := AvroMainForm1.AnsiMappingNames[I];
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
{ Information }
{ =============================================================================== }

procedure ShowMappingDescription(const AMapName: string);
var
  AnsiMappingDir, SourcePath, JsonPath, JSONContent, MetaText, DescText: string;
  Password: AnsiString;
  IsProtected: Boolean;
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

  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  SourcePath := GetActiveEncoFilePath(AMapName, AnsiMappingDir);
  if SourcePath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AMapName, mtError, [mbOK], 0);
    Exit;
  end;

  // Remember whether this mapping lives in a password-protected container so
  // the card can mark it; captured before the fallback may switch to a
  // same-named .json file below.
  IsProtected := IsEncoFile(SourcePath) and
    (GetAvroEncoProtectionFlag(SourcePath) = AVROENCO_FLAG_USER_PASSWORD);
  if IsEncoFile(SourcePath) then
  begin
    // Only password-protected files (flag $01 / legacy v1) prompt, and only
    // the very first time on this computer - the per-file cache decrypts
    // silently afterwards. Default-key files never prompt.
    if (GetEncoCachedPassword(SourcePath) = '') and
      (GetAvroEncoProtectionFlag(SourcePath) = AVROENCO_FLAG_USER_PASSWORD) then
    begin
      if not PromptForPasswordAndValidate(SourcePath, Password) then
        Exit;
      CachedEncoPassword := Password;
      RememberEncoPassword(SourcePath, Password);
      SaveSettings;
    end;

    JSONContent := DecryptAvroEncoToString(SourcePath, GetEncoCachedPassword(SourcePath));
    if JSONContent = '' then
    begin
      CachedEncoPassword := '';
      ForgetEncoPassword(SourcePath);
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

  // Prefer the structured Metadata block (Encoding/Type/Version/Developer/Font).
  MetaText := ExtractMetadataFromJSON(JSONContent, SourcePath);
  if (MetaText = '') and IsEncoFile(SourcePath) then
  begin
    // .AvroEnco files created before Metadata existed decrypt to JSON without
    // one; fall back to the same-named .json (mapping folder or assets) so the
    // description card still shows the Metadata from the JSON file.
    JsonPath := FindMetadataJsonPath(AMapName, AnsiMappingDir);
    if JsonPath <> '' then
    begin
      JSONContent := TFile.ReadAllText(JsonPath, TEncoding.UTF8);
      MetaText := ExtractMetadataFromJSON(JSONContent, JsonPath);
      if MetaText <> '' then
        SourcePath := JsonPath; // Location shows the file the card came from
    end;
  end;
  if MetaText = '' then
    MetaText := 'No metadata available for this mapping.';

  DescText := MetaText;

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

  // Show the description with the standard info dialog. This is the reliable
  // presentation under the app's Windows10 Dark VCL style (a hand-built TForm
  // gets repainted by the style hook and its text can end up invisible); on a
  // light Windows theme the same call renders as the white Picture-3 card.
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
    AnsiEngineManager.SwitchEngine('Default');
  end;
  AnsiEngineManager.RemoveEngine(AMapName);

  ScanAvroEncoFiles(AnsiDir);
  AvroMainForm1.BuildAnsiVersionMenus;
  ShowAnsiToastNotification('Mapping deleted: ' + AMapName);
  Log('Deleted mapping: ' + AMapName);
end;

end.
