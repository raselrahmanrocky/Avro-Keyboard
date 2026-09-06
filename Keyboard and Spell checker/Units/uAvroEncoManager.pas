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
  Generics.Collections;

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
function ExtractMetadataFromJSON(const AJSONContent: string): string;
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

function ExtractMetadataFromJSON(const AJSONContent: string): string;
begin
  Result := 'Encrypted Avro ANSI Encoding Mapping.';
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

end.