{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroEncoManager;

interface

uses
  Windows,
  SysUtils,
  Classes,
  Generics.Collections,
  System.JSON;

type
  TAvroEncoFileInfo = record
    FilePath: string;
    DisplayName: string;
    IsEncoFile: Boolean;
    LastWriteTime: TDateTime;
  end;

var
  CachedEncoPassword: AnsiString;
  AvroEncoFiles: TDictionary<string, TAvroEncoFileInfo>;

procedure InitializeEncoManager;
procedure FinalizeEncoManager;
procedure ScanAvroEncoFiles(const ADirectory: string);
function GetEncoDisplayName(const AFilePath: string): string;
function IsEncoFile(const AFilePath: string): Boolean;
function LoadMappingFromEnco(const AFilePath: string; const APassword: AnsiString; ErrorLog: TStringList = nil): Boolean;
function ExtractMetadataFromJSON(const AJSONContent: string; const AFilePath: string = ''): string;
function GetJSONString(const AObj: TJSONValue; const AKey: string): string;
function FindMetadataJsonPath(const ADisplayName: string; const ADirectory: string): string;
function GetActiveEncoFilePath(const ADisplayName: string; const ADirectory: string): string;

implementation

uses
  uAvroEncoCrypto,
  clsUnicodeToBijoy2000,
  uFileFolderHandling,
  DebugLog;

procedure InitializeEncoManager;
begin
  if not Assigned(AvroEncoFiles) then
    AvroEncoFiles := TDictionary<string, TAvroEncoFileInfo>.Create;
end;

procedure FinalizeEncoManager;
begin
  FreeAndNil(AvroEncoFiles);
end;

function GetEncoDisplayName(const AFilePath: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFilePath), '');
end;

function IsEncoFile(const AFilePath: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFilePath), '.AvroEnco');
end;

procedure ScanDirHelper(const ADir: string);
var
  SR: TSearchRec;
  FoundPath, DisplayName: string;
  Info: TAvroEncoFileInfo;
begin
  if not DirectoryExists(ADir) then Exit;

  // Scan .AvroEnco
  if FindFirst(ADir + '*.AvroEnco', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          FoundPath := ADir + SR.Name;
          DisplayName := ChangeFileExt(SR.Name, '');
          Info.FilePath := FoundPath;
          Info.DisplayName := DisplayName;
          Info.IsEncoFile := True;
          Info.LastWriteTime := SR.TimeStamp;
          AvroEncoFiles.AddOrSetValue(Lowercase(DisplayName), Info);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

  // Scan .json
  if FindFirst(ADir + '*.json', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') then
        begin
          DisplayName := ChangeFileExt(SR.Name, '');
          if not AvroEncoFiles.ContainsKey(Lowercase(DisplayName)) then
          begin
            FoundPath := ADir + SR.Name;
            Info.FilePath := FoundPath;
            Info.DisplayName := DisplayName;
            Info.IsEncoFile := False;
            Info.LastWriteTime := SR.TimeStamp;
            AvroEncoFiles.AddOrSetValue(Lowercase(DisplayName), Info);
          end;
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure ScanAvroEncoFiles(const ADirectory: string);
var
  AppDir: string;
begin
  InitializeEncoManager;
  AvroEncoFiles.Clear;

  AppDir := ExtractFilePath(ParamStr(0));

  // 1. Scan Primary Directory
  ScanDirHelper(ADirectory);

  // 2. Scan assets/ folder
  ScanDirHelper(AppDir + 'assets\');

  // 3. Scan AnsiMapping/ folder
  ScanDirHelper(AppDir + 'AnsiMapping\');

  Log('Scanned AvroEnco files: ' + IntToStr(AvroEncoFiles.Count) + ' found');
end;

function LoadMappingFromEnco(
  const AFilePath: string;
  const APassword: AnsiString;
  ErrorLog: TStringList = nil
): Boolean;
var
  JSONContent: string;
begin
  Result := False;

  if not FileExists(AFilePath) then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: File not found: ' + AFilePath);
    Exit;
  end;

  if IsEncoFile(AFilePath) then
  begin
    // DecryptAvroEncoToString returns clean text: the container is decrypted
    // entirely in RAM (pure Pascal AES engine) and the leading UTF-8 BOM
    // (decoded as U+FEFF) is stripped, so callers receive clean JSON that
    // starts with '{'. Files protected with the Default Application Key
    // (flag $00) decrypt transparently; password-protected files need the
    // right APassword. On any failure the previously active mapping stays
    // untouched - LoadAnsiMappingFromJSON is only reached with valid JSON.
    JSONContent := Trim(DecryptAvroEncoToString(AFilePath, APassword));
    if JSONContent = '' then
    begin
      Log('LoadMappingFromEnco: decryption failed (wrong password / corrupted file): ' + AFilePath);
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: Decryption failed. Invalid password or corrupted file.');
      Exit;
    end;

    // Guard against garbage output: a wrong password or corrupted file can
    // produce decrypted bytes that are not valid JSON. The mapping parser
    // silently ignores malformed input, which would leave the previously
    // active mapping in place and make every .AvroEnco file behave alike.
    if JSONContent[1] <> '{' then
    begin
      Log('LoadMappingFromEnco: decrypted content is not valid mapping JSON: ' + AFilePath);
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: Decrypted content is not a valid ANSI mapping. Wrong password or corrupted file.');
      Exit;
    end;

    LoadAnsiMappingFromJSON(JSONContent, ErrorLog);
    Result := True;
  end
  else
  begin
    LoadAnsiMapping(AFilePath, ErrorLog);
    Result := True;
  end;
end;

function ExtractMetadataFromJSON(const AJSONContent: string; const AFilePath: string): string;
var
  LContent: string;
  LJSON: TJSONValue;
  LMeta: TJSONValue;
  LFileBase, LFileName, LEncoding, LType, LVersion, LCompany, LDeveloper, LModifiedBy, LFont: string;
begin
  Result := '';
  LContent := AJSONContent;
  // Drop a leading UTF-8 BOM if one survived into the string, otherwise
  // ParseJSONValue rejects the document and no Metadata is found.
  if (LContent <> '') and (LContent[1] = #$FEFF) then
    Delete(LContent, 1, 1);
  LContent := Trim(LContent);
  if LContent = '' then
    Exit;

  LJSON := nil;
  try
    LJSON := TJSONObject.ParseJSONValue(LContent);
    if not Assigned(LJSON) then
      Exit;
    LMeta := nil;
    try
      if LJSON is TJSONObject then
        LMeta := TJSONObject(LJSON).Values['Metadata'];
      if not Assigned(LMeta) or not (LMeta is TJSONObject) then
        Exit;
      // New metadata schema; fall back to the legacy keys (Name/Font) so old
      // .AvroEnco containers and third-party files still render.
      // The card shows the mapping's file name (as seen in Explorer/picker):
      // "Name" gets the full file name, "Encoding" the name without the
      // extension. The JSON Encoding/Name keys are only a fallback for
      // callers that pass no file path.
      if AFilePath <> '' then
      begin
        LFileName := ExtractFileName(AFilePath);
        LFileBase := GetEncoDisplayName(AFilePath);
      end;
      LEncoding := LFileBase;
      if LEncoding = '' then
      begin
        LEncoding := GetJSONString(LMeta, 'Encoding');
        if LEncoding = '' then
          LEncoding := GetJSONString(LMeta, 'Name');
      end;
      LType      := GetJSONString(LMeta, 'Type');
      LVersion   := GetJSONString(LMeta, 'Version');
      LCompany   := GetJSONString(LMeta, 'Company');
      LDeveloper := GetJSONString(LMeta, 'Developer');
      LModifiedBy := GetJSONString(LMeta, 'Modified By');
      LFont      := GetJSONString(LMeta, 'Suggested Font');
      if LFont = '' then
        LFont := GetJSONString(LMeta, 'Font');
    finally
      LMeta := nil;
    end;
  finally
    LJSON.Free;
  end;
  // Build metadata text
  if LFileName <> '' then
    Result := Result + 'Name: ' + LFileName + sLineBreak;
  if LEncoding <> '' then
    Result := Result + 'Encoding: ' + LEncoding + sLineBreak;
  if LType <> '' then
    Result := Result + 'Type: ' + LType + sLineBreak;
  if LVersion <> '' then
    Result := Result + 'Version: ' + LVersion + sLineBreak;
  if LCompany <> '' then
    Result := Result + 'Company: ' + LCompany + sLineBreak;
  if LDeveloper <> '' then
    Result := Result + 'Developer: ' + LDeveloper + sLineBreak;
  if LModifiedBy <> '' then
    Result := Result + 'Modified By: ' + LModifiedBy + sLineBreak;
  if LFont <> '' then
    Result := Result + sLineBreak + 'Suggested Font: ' + LFont + sLineBreak;
end;

function GetJSONString(const AObj: TJSONValue; const AKey: string): string;
var
  LVal: TJSONValue;
begin
  Result := '';
  if not Assigned(AObj) or not (AObj is TJSONObject) then
    Exit;
  LVal := TJSONObject(AObj).Values[AKey];
  if Assigned(LVal) then
  begin
    if LVal is TJSONString then
      Result := TJSONString(LVal).Value
    else if LVal is TJSONNumber then
      Result := TJSONNumber(LVal).Value
    else
      Result := LVal.Value;
  end;
end;
function GetActiveEncoFilePath(const ADisplayName: string; const ADirectory: string): string;
var
  Info: TAvroEncoFileInfo;
  AppDir: string;
begin
  Result := '';
  // 1. Check dictionary cache first
  if Assigned(AvroEncoFiles) and AvroEncoFiles.TryGetValue(Lowercase(ADisplayName), Info) then
  begin
    if FileExists(Info.FilePath) then
      Exit(Info.FilePath);
  end;

  AppDir := ExtractFilePath(ParamStr(0));

  // 2. Check .AvroEnco in all directories (priority: .AvroEnco over .json)
  if FileExists(ADirectory + ADisplayName + '.AvroEnco') then Exit(ADirectory + ADisplayName + '.AvroEnco');
  if FileExists(AppDir + 'assets\' + ADisplayName + '.AvroEnco') then Exit(AppDir + 'assets\' + ADisplayName + '.AvroEnco');
  if FileExists(AppDir + 'AnsiMapping\' + ADisplayName + '.AvroEnco') then Exit(AppDir + 'AnsiMapping\' + ADisplayName + '.AvroEnco');
  if (AppDir <> ADirectory) and FileExists(AppDir + ADisplayName + '.AvroEnco') then Exit(AppDir + ADisplayName + '.AvroEnco');

  // 3. Fallback to .json files
  if FileExists(ADirectory + ADisplayName + '.json') then Exit(ADirectory + ADisplayName + '.json');
  if FileExists(AppDir + 'assets\' + ADisplayName + '.json') then Exit(AppDir + 'assets\' + ADisplayName + '.json');
end;

{ Returns the first existing, same-named .json for ADisplayName, used as a
  Metadata source when an old .AvroEnco file (encrypted before Metadata
  existed) decrypts to JSON without a Metadata block. }
function FindMetadataJsonPath(const ADisplayName: string; const ADirectory: string): string;
var
  AppDir: string;
begin
  Result := '';
  if ADisplayName = '' then
    Exit;
  AppDir := ExtractFilePath(ParamStr(0));
  if (ADirectory <> '') and FileExists(ADirectory + ADisplayName + '.json') then
    Exit(ADirectory + ADisplayName + '.json');
  if FileExists(AppDir + 'assets\' + ADisplayName + '.json') then
    Exit(AppDir + 'assets\' + ADisplayName + '.json');
  if FileExists(AppDir + 'AnsiMapping\' + ADisplayName + '.json') then
    Exit(AppDir + 'AnsiMapping\' + ADisplayName + '.json');
end;

end.