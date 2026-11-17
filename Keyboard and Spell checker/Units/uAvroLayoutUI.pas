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
procedure ExportMappingFile(const AFileName: string);
procedure ShowMappingDescription(const AFileName: string);
procedure DeleteMappingFile(const AFileName: string);

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

  procedure BuildSingleMenu(AMenu: TMenuItem; AFileNames: TStringList);
  var
    Sep, MoreOptMenu, Item: TMenuItem;
    I:                      Integer;
    FileName, LabelText:    string;
    Checked:                Boolean;

    procedure AddDirectItem(AParentMenu: TMenuItem; const ALabel, AFileName: string; AChecked: Boolean);
    var
      MItem: TMenuItemExtended;
    begin
      MItem := TMenuItemExtended.Create(AParentMenu);
      MItem.Caption := EscapeAmpersandsForMenu(ALabel);
      MItem.Value := AFileName;
      MItem.Checked := AChecked;
      MItem.RadioItem := True;
      MItem.Tag := 9903;
      // Exact identity for the click handler: a display label is never parsed
      // back into a file name.
      MItem.Hint := AFileName;
      MItem.OnClick := AvroMainForm1.AnsiVersionMenuClick;
      AParentMenu.Add(MItem);
    end;

    procedure AddMappingActionSubmenu(ParentMore: TMenuItem; const ALabel, AFileName: string);
    var
      MSub, ActionItem: TMenuItem;
    begin
      MSub := TMenuItem.Create(ParentMore);
      MSub.Caption := EscapeAmpersandsForMenu(ALabel);
      MSub.Hint := AFileName;
      ParentMore.Add(MSub);

      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Information';
      ActionItem.Hint := AFileName;
      ActionItem.OnClick := AvroMainForm1.ReadAnsiDescriptionClick;
      MSub.Add(ActionItem);

      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Export Mapping...';
      ActionItem.Hint := AFileName;
      ActionItem.OnClick := AvroMainForm1.ExportSpecificMappingClick;
      MSub.Add(ActionItem);

      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Delete Mapping';
      ActionItem.Hint := AFileName;
      ActionItem.OnClick := AvroMainForm1.DeleteAnsiMappingClick;
      MSub.Add(ActionItem);
    end;

  begin
    AMenu.Clear;

    // Full scanned catalog only - no prepended "Default" row. The caller hands
    // in the exact-file list for this rebuild; labels are derived from the same
    // index so a caption can never be paired with a sibling file.
    if Assigned(AFileNames) then
      for I := 0 to AFileNames.Count - 1 do
      begin
        FileName := AFileNames[I];
        LabelText := GetMappingDisplayLabel(FileName);
        Checked := SameText(AnsiVersionFileName, FileName);
        AddDirectItem(AMenu, LabelText, FileName, Checked);
      end;

    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);

    MoreOptMenu := TMenuItem.Create(AMenu);
    MoreOptMenu.Caption := 'More Options';
    AMenu.Add(MoreOptMenu);

    if Assigned(AFileNames) then
      for I := 0 to AFileNames.Count - 1 do
      begin
        FileName := AFileNames[I];
        AddMappingActionSubmenu(MoreOptMenu, GetMappingDisplayLabel(FileName), FileName);
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
  AnsiDir:   string;
  FileNames: TStringList;
begin
  AnsiDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiDir);
  ScanAvroEncoFiles(AnsiDir);

  // Local exact-filename list for THIS rebuild. The shared lists may be one
  // folder change behind, and the spec forbids relying on a stale label list.
  // Captions are derived from the same index, so a label can never be paired
  // with the wrong file.
  FileNames := TStringList.Create;
  try
    GetSortedMappingFileNames(FileNames);

    if Assigned(AvroMainForm1.AnsiVersionSubmenu1) then
      BuildSingleMenu(AvroMainForm1.AnsiVersionSubmenu1, FileNames);
    if Assigned(AvroMainForm1.mnuTraySelectAnsiEncoding) then
      BuildSingleMenu(AvroMainForm1.mnuTraySelectAnsiEncoding, FileNames);
  finally
    FileNames.Free;
  end;
end;

{ =============================================================================== }
{ Export Mapping }
{ =============================================================================== }

procedure ExportMappingFile(const AFileName: string);
var
  SaveDialog: TSaveDialog;
  SourcePath: string;
  LabelText:  string;
begin
  if not IsBareMappingFileName(AFileName) then
    Exit;
  SourcePath := GetExactEncoFilePath(AFileName, GetAvroDataDir + 'AnsiMapping\');
  if SourcePath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AFileName, mtError, [mbOK], 0);
    Exit;
  end;
  LabelText := GetMappingDisplayLabel(AFileName);

  SaveDialog := TSaveDialog.Create(nil);
  try
    // Export mirrors the source format: an .AvroEnco container is saved as
    // .AvroEnco, a plain JSON mapping as .json - whatever extension the
    // mapping file has is the one it keeps on the way out.
    if IsEncoFile(SourcePath) then
    begin
      SaveDialog.Filter := 'Avro Encoded Mapping|*.AvroEnco';
      SaveDialog.DefaultExt := 'AvroEnco';
    end
    else
    begin
      SaveDialog.Filter := 'ANSI Encoding JSON|*.json';
      SaveDialog.DefaultExt := 'json';
    end;
    SaveDialog.Title := 'Export ' + LabelText + ' Mapping';
    // The exact file name, extension included. Building the base name plus an
    // extension would turn an exact one.json into one.json.json.
    SaveDialog.FileName := ExtractFileName(SourcePath);

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

procedure ShowMappingDescription(const AFileName: string);
var
  AnsiMappingDir, SourcePath, JsonPath, JSONContent, MetaText, DescText: string;
  Password:                                                              AnsiString;
  IsProtected:                                                           Boolean;
begin
  if not IsBareMappingFileName(AFileName) then
    Exit;
  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  SourcePath := GetExactEncoFilePath(AFileName, AnsiMappingDir);
  if SourcePath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AFileName, mtError, [mbOK], 0);
    Exit;
  end;

  // Remember whether this mapping lives in a password-protected container so
  // the card can mark it; captured before the fallback may switch to a
  // same-named .json file below.
  IsProtected := IsEncoFile(SourcePath) and (GetAvroEncoProtectionFlag(SourcePath) = AVROENCO_FLAG_USER_PASSWORD);
  if IsEncoFile(SourcePath) then
  begin
    // Only password-protected files (flag $01 / legacy v1) prompt, and only
    // the very first time on this computer - the per-file cache decrypts
    // silently afterwards. Default-key files never prompt.
    if (GetEncoCachedPassword(SourcePath) = '') and (GetAvroEncoProtectionFlag(SourcePath) = AVROENCO_FLAG_USER_PASSWORD) then
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
      MessageDlg(AvroEncoOpenFailureMessage(SourcePath), mtError, [mbOK], 0);
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
    // one; fall back to the same-base .json in the mapping directory so the
    // description card still shows the Metadata from the JSON file. This is a
    // READ-ONLY metadata source: the exact selected file stays the identity,
    // nothing is activated and the card's Name line still names SourcePath.
    JsonPath := FindMetadataJsonPath(ChangeFileExt(AFileName, ''), AnsiMappingDir);
    if JsonPath <> '' then
    begin
      JSONContent := TFile.ReadAllText(JsonPath, TEncoding.UTF8);
      MetaText := ExtractMetadataFromJSON(JSONContent, SourcePath);
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

  // Use the native information dialog so MB_TOPMOST keeps it visible above
  // other applications until the user dismisses it.
  Application.MessageBox(PChar(DescText), 'Information',
    MB_OK or MB_ICONINFORMATION or MB_TOPMOST);
end;

{ =============================================================================== }
{ Delete Mapping }
{ =============================================================================== }

procedure DeleteMappingFile(const AFileName: string);
var
  AnsiDir, TargetPath, Replacement: string;
  WasActive:                        Boolean;
begin
  // The row's exact file name is the only accepted identity. A path-bearing or
  // empty value is rejected before any confirmation dialog.
  if not IsBareMappingFileName(AFileName) then
    Exit;

  AnsiDir := GetAvroDataDir + 'AnsiMapping\';
  TargetPath := GetExactEncoFilePath(AFileName, AnsiDir);
  if TargetPath = '' then
  begin
    MessageDlg('Mapping file not found: ' + AFileName, mtError, [mbOK], 0);
    Exit;
  end;

  if MessageDlg('Are you sure you want to delete the mapping "' + AFileName + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;

  WasActive := SameText(AnsiVersionFileName, AFileName);

  // Only the selected exact file. A same-base sibling is a different mapping
  // and stays in the catalog.
  if not DeleteFile(TargetPath) then
  begin
    MessageDlg('Failed to delete mapping: ' + SysErrorMessage(GetLastError), mtError, [mbOK], 0);
    Exit;
  end;

  // The catalog must be rescanned BEFORE choosing a replacement, so the
  // deleted file can never be selected again.
  ScanAvroEncoFiles(AnsiDir);

  if not WasActive then
  begin
    // Not live: dropping its parked engine is safe immediately.
    AnsiEngineManager.RemoveEngine(AFileName);
    AvroMainForm1.BuildAnsiVersionMenus;
    AvroMainForm1.UpdateAnsiVersionMenuChecks(AnsiVersionFileName);
    AvroMainForm1.UpdateTrayIcon;
    ShowAnsiToastNotification('Mapping deleted: ' + GetMappingDisplayLabel(AFileName));
    Log('Deleted mapping: ' + AFileName);
    Exit;
  end;

  // Active file deleted: this is the one explicit action allowed to move the
  // user to another mapping. Switch away FIRST (the switch publishes the new
  // exact pair), then remove the old cache key; RemoveEngine refuses the active
  // key, so the ordering is enforced by the manager as well.
  Replacement := FirstAvailableMappingFileName;
  if Replacement <> '' then
  begin
    if not AnsiEngineManager.SwitchEngine(Replacement) then
      Log('Delete: could not activate replacement "' + Replacement + '"');
  end
  else
  begin
    PublishActiveSelection('', '');
    SaveAnsiVersionOnly;
    AvroMainForm1.SyncActiveMappingTimestamp('');
    Log('Delete: no mapping files left - Unicode only');
  end;

  // Only now is the old exact key guaranteed not to be the live engine.
  AnsiEngineManager.RemoveEngine(AFileName);

  if Replacement <> '' then
  begin
    SaveAnsiVersionOnly;
    AvroMainForm1.SyncActiveMappingTimestamp(AnsiVersionFileName);
  end;
  AvroMainForm1.BuildAnsiVersionMenus;
  AvroMainForm1.UpdateAnsiVersionMenuChecks(AnsiVersionFileName);
  AvroMainForm1.UpdateTrayIcon;
  ShowAnsiToastNotification('Mapping deleted: ' + AFileName);
  Log('Deleted active mapping: ' + AFileName);
end;

end.
