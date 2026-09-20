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
  SyncObjs,
  System.JSON,
  uAvroEncoIconSection;

type
  TAvroEncoFileInfo = record
    FilePath: string;
    DisplayName: string;
    IsEncoFile: Boolean;
    LastWriteTime: TDateTime;
  end;

var
  CachedEncoPassword: AnsiString;
  AvroEncoFiles:      TDictionary<string, TAvroEncoFileInfo>;

procedure InitializeEncoManager;
procedure FinalizeEncoManager;
procedure ScanAvroEncoFiles(const ADirectory: string);
function GetEncoDisplayName(const AFilePath: string): string;
{ True for any protected mapping container (.AvroEnco extension; both the
  legacy CBC and the Shield container format live under this extension). }
function IsEncoFile(const AFilePath: string): Boolean;
{ ============================================================================== }
{ Per-layout icon carried inside the mapping payload }
{ ============================================================================== }

{ Caches the icon a container carries (see uAvroEncoIconSection: it is one
  scalar Base64 member of the decrypted mapping JSON). Keyed by the same
  lowercase display name AvroEncoFiles uses, so the menus and the version
  picker can ask with the name they already hold. Empty bytes clear the entry.

  Written from the startup preload worker as well as the UI thread and read by
  the UI thread while menus are being built, so it is guarded by its own lock
  instead of depending on call order. }
procedure StoreMappingIcon(const ADisplayName: string; const AIconBytes: TBytes);

{ The cached icon, or nil when this mapping has none - a legacy container, a
  plain .json mapping, an icon that failed to decode, or a mapping that has not
  been decrypted yet. }
function GetMappingIconBytes(const ADisplayName: string): TBytes;

{ True once this name has been looked at (icon found OR the file was read and
  carries none), so callers can tell "no icon" from "not extracted yet". }
function MappingIconResolved(const ADisplayName: string): Boolean;

{ Drops every cached icon AND forgets which names were already resolved. The
  bytes are regenerable from the containers, so the idle-memory release uses
  this instead of keeping N decrypted icon blobs alive forever. Callers that
  draw afterwards must call EnsureMappingIcons again. }
procedure ClearMappingIcons;

{ Resolves the icon of ONE mapping from its file (idempotent: a name that is
  already resolved - icon or none - is skipped). Used by the switch path so the
  ACTIVE layout's badge and tray icon always have their bytes without any of
  the other mappings being touched. }
procedure EnsureMappingIcon(const ADisplayName: string);

{ Resolves the icon of every mapping the scan knows about. This is what the
  menus and the version picker call before they draw badges; it replaces the
  eager sweep that used to run inside ScanAvroEncoFiles, so startup no longer
  decrypts and JSON-parses every container just to cache its icon. }
procedure EnsureMappingIcons;

function LoadMappingFromEnco(const AFilePath: string; const APassword: AnsiString; ErrorLog: TStringList = nil): Boolean;
function ExtractMetadataFromJSON(const AJSONContent: string; const AFilePath: string = ''): string;
function GetJSONString(const AObj: TJSONValue; const AKey: string): string;
function FindMetadataJsonPath(const ADisplayName: string; const ADirectory: string): string;
function GetActiveEncoFilePath(const ADisplayName: string; const ADirectory: string): string;

{ ============================================================================== }
{ Mapping list order and picker shortcuts }
{ ============================================================================== }

{ Natural (human) ordering for mapping display names: a digit run compares
  numerically, so "Ansi V2" sorts before "Ansi V10" instead of after it. The
  encoding menus (tray + top bar) and the version picker must all use this,
  otherwise the same three lists can disagree - the menus used to enumerate the
  AvroEncoFiles dictionary, whose bucket order put V4 between V1 and V2 while
  the picker (fed by the sorted AnsiMappingNames) looked correct. }
function CompareMappingDisplayNames(const ALeft, ARight: string): Integer;

{ Sorts ANames in place with CompareMappingDisplayNames. No-op for TStrings
  implementations without CustomSort (only TStringList has it). }
procedure SortMappingDisplayNames(ANames: TStrings);

{ Fills ANames with every mapping display name in the shared natural order,
  excluding 'Default' (which is built into the application and is always listed
  first by the caller). This is the single source of truth for menu and picker
  order. }
procedure GetSortedMappingDisplayNames(ANames: TStrings);

{ Shortcut resolution used by the picker's key handlers (form-level and list
  box level share one implementation). Maps the 1-based number the picker draws
  next to an item back to its index: the main number row (VK_1..VK_9) and the
  numpad (VK_NUMPAD1..VK_NUMPAD9). Returns -1 for any other key, or when the
  number has no item. }
function MappingIndexForKey(const ANames: TStrings; AKey: Word): Integer;

{ Index of the first name whose first character matches AChar,
  case-insensitively. Returns -1 when nothing matches (so the caller can leave
  the key alone and fall through to the list box's own type-ahead). }
function MappingIndexForChar(const ANames: TStrings; AChar: Char): Integer;

{ True when a font family with this name is registered on this computer.
  Matching is intentionally loose (case, spaces and punctuation ignored, with
  either name allowed to be a prefix of the other) so that "Adarsh aLipi" finds
  "AdarshaLipiNormal" and "SutonnyMJ" finds "Sutonny MJ". }
function IsFontFamilyInstalled(const AFontName: string): Boolean;

implementation

uses
  uAvroEncoCrypto,
  clsUnicodeToBijoy2000,
  uFileFolderHandling,
  System.Win.Registry,
  System.IOUtils,
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

var
  { Keyed like AvroEncoFiles: Lowercase(DisplayName). Created in this unit's
    initialization, so no caller has to remember to set it up first. }
  MappingIcons: TDictionary<string, TBytes>;
  { Names whose icon has already been resolved - present in MappingIcons, or
    read from the file and found to carry none. Without this, every menu
    rebuild would re-decrypt every icon-less container in the folder. Also
    keyed by Lowercase(DisplayName). }
  MappingIconsResolved: TDictionary<string, Byte>;
  MappingIconsLock:     TCriticalSection;

procedure StoreMappingIcon(const ADisplayName: string; const AIconBytes: TBytes);
begin
  if ADisplayName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    if Length(AIconBytes) = 0 then
      MappingIcons.Remove(Lowercase(ADisplayName))
    else
      MappingIcons.AddOrSetValue(Lowercase(ADisplayName), AIconBytes);
  finally
    MappingIconsLock.Leave;
  end;
end;

function GetMappingIconBytes(const ADisplayName: string): TBytes;
begin
  Result := nil;
  if ADisplayName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    MappingIcons.TryGetValue(Lowercase(ADisplayName), Result);
  finally
    MappingIconsLock.Leave;
  end;
end;

function MappingIconResolved(const ADisplayName: string): Boolean;
var
  Dummy: Byte;
begin
  Result := False;
  if ADisplayName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    Result := MappingIconsResolved.TryGetValue(Lowercase(ADisplayName), Dummy);
  finally
    MappingIconsLock.Leave;
  end;
end;

procedure ClearMappingIcons;
begin
  MappingIconsLock.Enter;
  try
    MappingIcons.Clear;
    MappingIconsResolved.Clear;
  finally
    MappingIconsLock.Leave;
  end;
end;

function IsEncoFile(const AFilePath: string): Boolean;
begin
  // Any file with the .AvroEnco extension is a protected mapping container:
  // the legacy CBC format and the newer Shield format share this extension
  // and both need the same handling (password prompt, cache, decrypt in
  // RAM). The crypto layer tells the two formats apart by magic bytes.
  Result := SameText(ExtractFileExt(AFilePath), '.AvroEnco');
end;

procedure ScanDirHelper(const ADir: string);
var
  SR:                     TSearchRec;
  FoundPath, DisplayName: string;
  Info:                   TAvroEncoFileInfo;
begin
  if not DirectoryExists(ADir) then
    Exit;

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
  AppDir:  string;
  OldKeys: TList<string>;
  Key:     string;
begin
  InitializeEncoManager;

  // Snapshot current keys so we can prune stale icon entries afterward.
  OldKeys := TList<string>.Create;
  try
    if Assigned(AvroEncoFiles) then
      for Key in AvroEncoFiles.Keys do
        OldKeys.Add(Key);

    AvroEncoFiles.Clear;

    AppDir := ExtractFilePath(ParamStr(0));

    // 1. Scan Primary Directory
    ScanDirHelper(ADirectory);

    // 2. Scan assets/ folder
    ScanDirHelper(AppDir + 'assets\');

    // 3. Scan AnsiMapping/ folder
    ScanDirHelper(AppDir + 'AnsiMapping\');

    // Remove icon entries for files that no longer exist on disk (renamed or
    // deleted).  This prevents stale icon badges lingering in the menu.
    for Key in OldKeys do
      if not AvroEncoFiles.ContainsKey(Key) then
        StoreMappingIcon(Key, nil);

    Log('Scanned AvroEnco files: ' + IntToStr(AvroEncoFiles.Count) + ' found');

    // Icons are NOT extracted here any more. The sweep used to run inside the
    // scan - i.e. on the startup path AND after every folder change - and it
    // decrypted every container and parsed every mapping document just to
    // cache a ~10 KB icon. Menus and the picker now call EnsureMappingIcons
    // when they are about to draw badges, and the switch path calls
    // EnsureMappingIcon for the active layout only.
  finally
    OldKeys.Free;
  end;
end;

{ Reads ONE mapping's file, extracts the icon it carries and records the name
  as resolved either way (so a container without an icon is read once per
  session, not once per menu rebuild).

  Default-key .AvroEnco containers decrypt transparently with an empty
  password. Password-protected containers that have no cached password fail
  decryption here; they are retried on demand when the user enters the
  password (LoadMappingFromEnco stores the icon of the payload it just
  decrypted). Plain .json mappings are read directly. }
procedure ExtractOneFileIcon(const AInfo: TAvroEncoFileInfo);
var
  JSONContent: string;
  Key:         string;
begin
  Key := Lowercase(AInfo.DisplayName);

  // Mark the name resolved up front: converging through every exit below
  // (read error, corrupted container, no icon member) is what keeps a failing
  // mapping from being re-opened by every later menu rebuild.
  MappingIconsLock.Enter;
  try
    MappingIconsResolved.AddOrSetValue(Key, 1);
  finally
    MappingIconsLock.Leave;
  end;

  if AInfo.IsEncoFile then
  begin
    try
      JSONContent := Trim(DecryptAvroEncoToString(AInfo.FilePath, ''));
      if (JSONContent <> '') and (JSONContent[1] = '{') then
        StoreMappingIcon(AInfo.DisplayName, ExtractIconSection(JSONContent));
    except
      // Corrupted or password-protected file - icon will appear on demand.
    end;
  end
  else
  begin
    try
      if FileExists(AInfo.FilePath) then
      begin
        JSONContent := Trim(TFile.ReadAllText(AInfo.FilePath, TEncoding.UTF8));
        if (JSONContent <> '') and (JSONContent[1] = '{') then
          StoreMappingIcon(AInfo.DisplayName, ExtractIconSection(JSONContent));
      end;
    except
      // Read error - icon will appear on demand.
    end;
  end;
end;

{ Resolves the icons of every mapping that has not been looked at yet. This is
  the deferred replacement for the sweep that used to live in
  ScanAvroEncoFiles: the same work, paid when a badge is actually about to be
  drawn instead of on the startup path. }
procedure EnsureMappingIcons;
var
  Info: TAvroEncoFileInfo;
begin
  if not Assigned(AvroEncoFiles) then
    Exit;
  for Info in AvroEncoFiles.Values do
    if not MappingIconResolved(Info.DisplayName) then
      ExtractOneFileIcon(Info);
end;

{ Resolves ONE mapping's icon. The name must be a known mapping (the scan owns
  that knowledge); anything else is ignored rather than guessed by building a
  path here, because the caller's directory is not this unit's business. }
procedure EnsureMappingIcon(const ADisplayName: string);
var
  Info: TAvroEncoFileInfo;
begin
  if (ADisplayName = '') or SameText(ADisplayName, 'Default') then
    Exit;
  if not Assigned(AvroEncoFiles) then
    Exit;
  if MappingIconResolved(ADisplayName) then
    Exit;
  if not AvroEncoFiles.TryGetValue(Lowercase(ADisplayName), Info) then
    Exit;
  ExtractOneFileIcon(Info);
end;

function LoadMappingFromEnco(const AFilePath: string; const APassword: AnsiString; ErrorLog: TStringList = nil): Boolean;
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
    // entirely in RAM (pure Pascal crypto engine) and the leading UTF-8 BOM
    // (decoded as U+FEFF) is stripped, so callers receive clean JSON that
    // starts with '{'. Shield-format containers (magic 'AVROSHLD', also
    // .AvroEnco extension) decrypt through the AvroShield runtime stack
    // (HMAC -> AES-GCM -> zlib -> bytecode -> deobfuscate).
    // Files protected with the Default Application Key (flag $00) decrypt
    // transparently; password-protected files need the right APassword.
    // On any failure the previously active mapping stays untouched -
    // LoadAnsiMappingFromJSON is only reached with valid JSON.
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

    // The per-layout icon rides INSIDE the payload, so it arrives with the
    // decryption that just succeeded: no second file read, no extra key, and
    // it is covered by the same HMAC verdict and AES-GCM tag as the mapping.
    // A legacy container or a plain .json has no such member, which clears the
    // entry rather than serving a stale icon.
    StoreMappingIcon(GetEncoDisplayName(AFilePath), ExtractIconSection(JSONContent));

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
  LContent:                                                                        string;
  LJSON:                                                                           TJSONValue;
  LMeta:                                                                           TJSONValue;
  LFileName, LEncoding, LType, LVersion, LCompany, LDeveloper, LModifiedBy, LFont: string;
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
      if not Assigned(LMeta) or not(LMeta is TJSONObject) then
        Exit;
      // New metadata schema; fall back to the legacy keys (Name/Font) so old
      // .AvroEnco containers and third-party files still render.
      // The metadata block is the document's own documentation, so the card
      // reports it verbatim: "Name" is the file as seen in Explorer and in the
      // picker, "Encoding" is the profile the JSON declares (e.g. "ANSI V1").
      // Deriving Encoding from the path made the two lines say the same thing,
      // and made the card contradict the document for a container named after a
      // font instead of after its profile. When neither key exists the line is
      // left out rather than filled in with the file's base name.
      if AFilePath <> '' then
        LFileName := ExtractFileName(AFilePath);
      LEncoding := GetJSONString(LMeta, 'Encoding');
      if LEncoding = '' then
        LEncoding := GetJSONString(LMeta, 'Name');
      LType := GetJSONString(LMeta, 'Type');
      LVersion := GetJSONString(LMeta, 'Version');
      LCompany := GetJSONString(LMeta, 'Company');
      LDeveloper := GetJSONString(LMeta, 'Developer');
      LModifiedBy := GetJSONString(LMeta, 'Modified By');
      LFont := GetJSONString(LMeta, 'Suggested Font');
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
  begin
    Result := Result + sLineBreak + 'Suggested Font: ' + LFont + sLineBreak;
    // The engine emits exactly the byte values the mapping asks for. Only this
    // font renders those bytes as the intended Bangla; with any other ANSI font
    // active the text looks jumbled - which is easily mistaken for a corrupt
    // .AvroEnco file. Say so in the card instead of letting the file take the
    // blame.
    if not IsFontFamilyInstalled(LFont) then
      Result := Result + 'Note: this font was not found on this computer - ' + 'text encoded with this mapping reads correctly only in ' + LFont + '.' +
        sLineBreak;
  end;
  // Escape '&' for VCL display (MessageDlg treats '&' as accelerator prefix).
  Result := StringReplace(Result, '&', '&&', [rfReplaceAll]);
end;

function NormalizeFontName(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if CharInSet(C, ['A' .. 'Z', 'a' .. 'z', '0' .. '9']) then
      Result := Result + Lowercase(C);
  end;
end;

function FontNameMatches(const ARegistered, AWanted: string): Boolean;
var
  LRegistered, LWanted: string;
begin
  LRegistered := NormalizeFontName(ARegistered);
  LWanted := NormalizeFontName(AWanted);
  Result := (LRegistered <> '') and (LWanted <> '') and ((LRegistered = LWanted) or (Pos(LWanted, LRegistered) = 1) or (Pos(LRegistered, LWanted) = 1));
end;

const
  FONT_REGISTRY_KEY = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts';

  // Windows registers every installed face as a value whose name is the font's
  // display name ("Family (TrueType)" or "Family Style (TrueType)").
function FontKeyHasFamily(ARoot: HKEY; const AWanted: string): Boolean;
var
  Reg:     TRegistry;
  Names:   TStringList;
  I, Cut:  Integer;
  RegName: string;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := ARoot;
    if not Reg.OpenKeyReadOnly(FONT_REGISTRY_KEY) then
      Exit;
    Names := TStringList.Create;
    try
      Reg.GetValueNames(Names);
      for I := 0 to Names.Count - 1 do
      begin
        RegName := Names[I];
        Cut := Pos('(', RegName);
        if Cut > 0 then
          RegName := Trim(Copy(RegName, 1, Cut - 1));
        if FontNameMatches(RegName, AWanted) then
          Exit(True);
      end;
    finally
      Names.Free;
    end;
  finally
    Reg.Free;
  end;
end;

function IsFontFamilyInstalled(const AFontName: string): Boolean;
begin
  Result := (Trim(AFontName) <> '') and (FontKeyHasFamily(HKEY_CURRENT_USER, AFontName) or FontKeyHasFamily(HKEY_LOCAL_MACHINE, AFontName));
end;

function GetJSONString(const AObj: TJSONValue; const AKey: string): string;
var
  LVal: TJSONValue;
begin
  Result := '';
  if not Assigned(AObj) or not(AObj is TJSONObject) then
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
  Info:   TAvroEncoFileInfo;
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

  // 2. Check .AvroEnco in all directories (covers both the legacy CBC and
  // the Shield container format), then .json.
  if FileExists(ADirectory + ADisplayName + '.AvroEnco') then
    Exit(ADirectory + ADisplayName + '.AvroEnco');
  if FileExists(AppDir + 'assets\' + ADisplayName + '.AvroEnco') then
    Exit(AppDir + 'assets\' + ADisplayName + '.AvroEnco');
  if FileExists(AppDir + 'AnsiMapping\' + ADisplayName + '.AvroEnco') then
    Exit(AppDir + 'AnsiMapping\' + ADisplayName + '.AvroEnco');
  if (AppDir <> ADirectory) and FileExists(AppDir + ADisplayName + '.AvroEnco') then
    Exit(AppDir + ADisplayName + '.AvroEnco');
  // 3. Fallback to .json files
  if FileExists(ADirectory + ADisplayName + '.json') then
    Exit(ADirectory + ADisplayName + '.json');
  if FileExists(AppDir + 'assets\' + ADisplayName + '.json') then
    Exit(AppDir + 'assets\' + ADisplayName + '.json');
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

{ ============================================================================== }
{ Mapping list order and picker shortcuts }
{ ============================================================================== }

{ First significant digit of one digit run (the run's end when it is all
  zeros), so leading zeros cannot change the ordering. }
function DigitRunStart(const AText: string; AStart, AStop: Integer): Integer;
begin
  Result := AStart;
  while (Result < AStop) and (AText[Result] = '0') do
    Inc(Result);
end;

function CompareMappingDisplayNames(const ALeft, ARight: string): Integer;
var
  I, J, L1, L2, S1, S2: Integer;
begin
  I := 1;
  J := 1;
  while (I <= Length(ALeft)) and (J <= Length(ARight)) do
  begin
    if CharInSet(ALeft[I], ['0' .. '9']) and CharInSet(ARight[J], ['0' .. '9']) then
    begin
      // Compare the whole digit run numerically: "V2" must come before
      // "V10", which plain ordinal comparison gets backwards.
      L1 := I;
      while (L1 <= Length(ALeft)) and CharInSet(ALeft[L1], ['0' .. '9']) do
        Inc(L1);
      L2 := J;
      while (L2 <= Length(ARight)) and CharInSet(ARight[L2], ['0' .. '9']) do
        Inc(L2);
      S1 := DigitRunStart(ALeft, I, L1);
      S2 := DigitRunStart(ARight, J, L2);
      // Length first, digits second: this stays correct for runs far longer
      // than any integer type could hold. Both runs are never empty, so the
      // loop always advances.
      Result := (L1 - S1) - (L2 - S2);
      if Result = 0 then
        Result := CompareStr(Copy(ALeft, S1, L1 - S1), Copy(ARight, S2, L2 - S2));
      if Result <> 0 then
        Exit;
      I := L1;
      J := L2;
    end
    else
    begin
      Result := Ord(UpCase(ALeft[I])) - Ord(UpCase(ARight[J]));
      if Result <> 0 then
        Exit;
      Inc(I);
      Inc(J);
    end;
  end;
  // A prefix sorts before the string that extends it.
  Result := (Length(ALeft) - I) - (Length(ARight) - J);
end;

function CompareMappingNamesCallback(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareMappingDisplayNames(List[Index1], List[Index2]);
end;

procedure SortMappingDisplayNames(ANames: TStrings);
begin
  if ANames is TStringList then
    TStringList(ANames).CustomSort(CompareMappingNamesCallback);
end;

procedure GetSortedMappingDisplayNames(ANames: TStrings);
var
  Key: string;
begin
  if not Assigned(ANames) then
    Exit;
  ANames.Clear;
  // AvroEncoFiles is a hash table: enumerating its keys is exactly the
  // unordered source the encoding menus used to build themselves from.
  if Assigned(AvroEncoFiles) then
    for Key in AvroEncoFiles.Keys do
      if not SameText(Key, 'default') then
        ANames.Add(AvroEncoFiles[Key].DisplayName);
  SortMappingDisplayNames(ANames);
end;

function MappingIndexForKey(const ANames: TStrings; AKey: Word): Integer;
begin
  Result := -1;
  if not Assigned(ANames) then
    Exit;
  if (AKey >= Ord('1')) and (AKey <= Ord('9')) then
    Result := AKey - Ord('1')
  else if (AKey >= VK_NUMPAD1) and (AKey <= VK_NUMPAD9) then
    Result := AKey - VK_NUMPAD1
  else
    Exit;
  if (Result < 0) or (Result >= ANames.Count) then
    Result := -1;
end;

function MappingIndexForChar(const ANames: TStrings; AChar: Char): Integer;
var
  I: Integer;
begin
  Result := -1;
  if (not Assigned(ANames)) or (AChar = #0) then
    Exit;
  for I := 0 to ANames.Count - 1 do
    if (ANames[I] <> '') and (UpCase(ANames[I][1]) = UpCase(AChar)) then
      Exit(I);
end;

initialization

MappingIcons := TDictionary<string, TBytes>.Create;
MappingIconsResolved := TDictionary<string, Byte>.Create;
MappingIconsLock := TCriticalSection.Create;

finalization

FreeAndNil(MappingIcons);
FreeAndNil(MappingIconsResolved);
FreeAndNil(MappingIconsLock);

end.
