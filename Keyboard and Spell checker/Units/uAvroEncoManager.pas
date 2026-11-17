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
    FileName:      string; // exact on-disk file name, e.g. 'one.AvroEnco'
    BaseName:      string; // 'one'
    DisplayName:   string; // menu label: 'one' or 'one.AvroEnco'
    FilePath:      string;
    IsEncoFile:    Boolean;
    LastWriteTime: TDateTime;
    FileSize:      Int64;
  end;

var
  CachedEncoPassword: AnsiString;
  AvroEncoFiles:      TDictionary<string, TAvroEncoFileInfo>;

  { Exact file selected by the user, stored beside the legacy base-name
    AnsiVersion. Empty for the embedded baseline and for a legacy selection
    that has not migrated yet. Declared here, not in clsUnicodeToBijoy2000, so
    the Converter source and build stay untouched. }
  AnsiVersionFileName: string;

  { ============================================================================== }
  { Per-encoding password memory (key = lowercase full file path) }
  { ============================================================================== }

  { A protected encoding asks for its password ONCE on this computer; every later
    load (even after restarting the app or the PC) decrypts silently from here.

    The memory lives with the engine rather than with uRegistrySettings on
    purpose: this unit is linked by code that must stay clear of the application's
    settings and UI (the Text Converter and the gate tools reach the engine
    through clsUnicodeToBijoy2000), while uRegistrySettings pulls in uForm1 and
    uTopBar. The engine owns the memory; uRegistrySettings only persists the blob
    it produces with its EncodeEncoCache/DecodeEncoCache helpers. }

const
  EncoCacheSep = #9; // TAB separates file path from password (never typed in a
  // single-line edit, and never part of an NTFS file name)

var
  EncoPasswordCache: TStringList;

procedure InitEncoPasswordCache;
procedure FreeEncoPasswordCache;
function GetEncoCachedPassword(const AFilePath: string): AnsiString;
procedure RememberEncoPassword(const AFilePath: string; const APassword: AnsiString);
procedure ForgetEncoPassword(const AFilePath: string);

procedure InitializeEncoManager;
procedure FinalizeEncoManager;
procedure ScanAvroEncoFiles(const ADirectory: string);
function GetEncoDisplayName(const AFilePath: string): string;
{ True for any protected mapping container (.AvroEnco extension; both the
  legacy CBC and the Shield container format live under this extension). }
function IsEncoFile(const AFilePath: string): Boolean;
{ True for files the ANSI mapping catalog may list: .AvroEnco containers and
  .json mappings. settings.json and *.meta.json sidecars are not mappings. }
function IsAnsiMappingFileName(const AFileName: string): Boolean;
{ ============================================================================== }
{ Per-layout icon carried inside the mapping payload }
{ ============================================================================== }

{ Caches the icon a container carries (see uAvroEncoIconSection: it is one
  scalar Base64 member of the decrypted mapping JSON). Keyed by the lowercase
  exact file name AvroEncoFiles uses. Empty bytes clear the entry.

  Written from the startup preload worker as well as the UI thread and read by
  the UI thread while menus are being built, so it is guarded by its own lock
  instead of depending on call order. }
procedure StoreMappingIcon(const AFileName: string; const AIconBytes: TBytes);

{ The cached icon, or nil when this mapping has none - a legacy container, a
  plain .json mapping, an icon that failed to decode, or a mapping that has not
  been decrypted yet. }
function GetMappingIconBytes(const AFileName: string): TBytes;

{ True once this exact file has been looked at (icon found OR the file was read
  and carries none), so callers can tell "no icon" from "not extracted yet". }
function MappingIconResolved(const AFileName: string): Boolean;

{ Drops every cached icon AND forgets which names were already resolved. The
  bytes are regenerable from the containers, so the idle-memory release uses
  this instead of keeping N decrypted icon blobs alive forever. Callers that
  draw one icon afterwards must call EnsureMappingIcon; bulk consumers can use
  EnsureMappingIcons. }
procedure ClearMappingIcons;

{ Resolves the icon of ONE exact mapping file (idempotent: a name that is
  already resolved - icon or none - is skipped). Used by the switch path so the
  ACTIVE layout's tray and parent-menu icons always have their bytes without
  touching any of the other mappings. }
procedure EnsureMappingIcon(const AFileName: string);

{ Resolves the icons of every mapping the scan knows about. Most UI paths should
  use EnsureMappingIcon for the active mapping instead, so unrelated containers
  are not decrypted just to populate the icon cache. }
procedure EnsureMappingIcons;

function LoadMappingFromEnco(const AFilePath: string; const APassword: AnsiString; ErrorLog: TStringList = nil): Boolean;
function ExtractMetadataFromJSON(const AJSONContent: string; const AFilePath: string = ''): string;
function GetJSONString(const AObj: TJSONValue; const AKey: string): string;
function FindMetadataJsonPath(const ADisplayName: string; const ADirectory: string): string;

{ Exact-file resolvers and selection publication. }
function IsBareMappingFileName(const AFileName: string): Boolean;
function GetExactEncoFilePath(const AFileName, ADirectory: string): string;
function GetActiveEncoFilePath(const AName, ADirectory: string): string;
function ResolveAnsiSelectionFile(
  const ABaseName, AFileName, ADirectory: string;
  out AMissingExact: Boolean): string;
procedure PublishActiveSelection(const AFileName, ABaseName: string);
function GetMappingDisplayLabel(const AFileName: string): string;
function EscapeAmpersandsForMenu(const ACaption: string): string;

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

{ Fills ANames with every distinct base name in the shared natural order.
  This is the Converter-facing list; the Keyboard uses
  GetSortedMappingFileNames so it can represent both members of a same-base
  pair. }
procedure GetSortedMappingDisplayNames(ANames: TStrings);

{ Every exact mapping file name, ordered by its display label and then by the
  exact file name. This is the Keyboard's menu/picker list. }
procedure GetSortedMappingFileNames(ANames: TStrings);

{ Name of the first mapping that can be activated without a user prompt:
  natural-sorted from GetSortedMappingDisplayNames, skipping password-protected
  .AvroEnco containers that have no cached password on this computer. Returns
  '' when nothing is usable (empty folder / only locked containers). This keeps
  the legacy base-name contract used by the Converter and its gates. }
function FirstAvailableMappingName: string;

{ Exact-file equivalent of FirstAvailableMappingName, used by the Keyboard. }
function FirstAvailableMappingFileName: string;

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

implementation

uses
  uAvroEncoCrypto,
  clsUnicodeToBijoy2000,
  uFileFolderHandling,
  System.IOUtils,
  DebugLog;

{ =============================================================================== }
{ Per-encoding password memory (helpers) }
{ =============================================================================== }

procedure InitEncoPasswordCache;
begin
  if not Assigned(EncoPasswordCache) then
  begin
    EncoPasswordCache := TStringList.Create;
    EncoPasswordCache.NameValueSeparator := EncoCacheSep;
  end;
end;

procedure FreeEncoPasswordCache;
begin
  FreeAndNil(EncoPasswordCache);
end;

function GetEncoCachedPassword(const AFilePath: string): AnsiString;
var
  Key: string;
  I:   Integer;
begin
  Result := '';
  Key := LowerCase(Trim(AFilePath));
  if Key = '' then
    Exit;
  InitEncoPasswordCache;
  for I := 0 to EncoPasswordCache.Count - 1 do
    if EncoPasswordCache.Names[I] = Key then
    begin
      Result := AnsiString(EncoPasswordCache.ValueFromIndex[I]);
      Exit;
    end;
end;

procedure RememberEncoPassword(const AFilePath: string; const APassword: AnsiString);
var
  Key:   string;
  I:     Integer;
  Found: Boolean;
begin
  if (Trim(AFilePath) = '') or (APassword = '') then
    Exit;
  InitEncoPasswordCache;
  Key := LowerCase(Trim(AFilePath));
  Found := False;
  for I := 0 to EncoPasswordCache.Count - 1 do
    if EncoPasswordCache.Names[I] = Key then
    begin
      EncoPasswordCache[I] := Key + EncoCacheSep + string(APassword);
      Found := True;
      Break;
    end;
  if not Found then
    EncoPasswordCache.Add(Key + EncoCacheSep + string(APassword));
end;

procedure ForgetEncoPassword(const AFilePath: string);
var
  Key: string;
  I:   Integer;
begin
  if not Assigned(EncoPasswordCache) then
    Exit;
  Key := LowerCase(Trim(AFilePath));
  for I := EncoPasswordCache.Count - 1 downto 0 do
    if EncoPasswordCache.Names[I] = Key then
      EncoPasswordCache.Delete(I);
end;

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
  { Keyed by Lowercase(FileName) - the exact mapping identity, never the base
    name. Created in this unit's initialization, so no caller has to remember
    to set it up first. }
  MappingIcons: TDictionary<string, TBytes>;
  { File names whose icon has already been resolved - present in MappingIcons,
    or read from the file and found to carry none. Without this, every menu
    rebuild would re-decrypt every icon-less container in the folder. Also
    keyed by Lowercase(FileName). }
  MappingIconsResolved: TDictionary<string, Byte>;
  MappingIconsLock:     TCriticalSection;

procedure StoreMappingIcon(const AFileName: string; const AIconBytes: TBytes);
begin
  if AFileName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    if Length(AIconBytes) = 0 then
      MappingIcons.Remove(LowerCase(AFileName))
    else
      MappingIcons.AddOrSetValue(LowerCase(AFileName), AIconBytes);
  finally
    MappingIconsLock.Leave;
  end;
end;

function GetMappingIconBytes(const AFileName: string): TBytes;
begin
  Result := nil;
  if AFileName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    MappingIcons.TryGetValue(LowerCase(AFileName), Result);
  finally
    MappingIconsLock.Leave;
  end;
end;

function MappingIconResolved(const AFileName: string): Boolean;
var
  Dummy: Byte;
begin
  Result := False;
  if AFileName = '' then
    Exit;
  MappingIconsLock.Enter;
  try
    Result := MappingIconsResolved.TryGetValue(LowerCase(AFileName), Dummy);
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

function IsAnsiMappingFileName(const AFileName: string): Boolean;
var
  Name: string;
begin
  Name := ExtractFileName(AFileName);
  Result := SameText(ExtractFileExt(Name), '.AvroEnco') or
            SameText(ExtractFileExt(Name), '.json');
  if not Result then
    Exit;
  if SameText(Name, 'settings.json') then
    Exit(False);
  if SameText(ExtractFileExt(ChangeFileExt(Name, '')), '.meta') then
    Exit(False);
end;

procedure ScanDirHelper(const ADir: string);
var
  SR:       TSearchRec;
  Info:     TAvroEncoFileInfo;
  Counts:   TDictionary<string, Integer>;
  Keys:     TList<string>;
  Key, Base: string;
  Count:    Integer;

  procedure AddFile(const AName: string; AIsEnco: Boolean);
  begin
    Info.FileName := AName;
    Info.BaseName := ChangeFileExt(AName, '');
    Info.DisplayName := Info.BaseName; // replaced after all files are counted
    Info.FilePath := ADir + AName;
    Info.IsEncoFile := AIsEnco;
    Info.LastWriteTime := SR.TimeStamp;
    Info.FileSize := SR.Size;
    AvroEncoFiles.AddOrSetValue(LowerCase(AName), Info);
  end;

begin
  if not DirectoryExists(ADir) then
    Exit;

  // Scan .AvroEnco
  if FindFirst(ADir + '*.AvroEnco', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and IsAnsiMappingFileName(SR.Name) then
          AddFile(SR.Name, True);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

  // Scan .json. Every mapping file is added, including a .json that shares its
  // base name with an .AvroEnco container.
  if FindFirst(ADir + '*.json', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name <> '.') and (SR.Name <> '..') and IsAnsiMappingFileName(SR.Name) then
          AddFile(SR.Name, False);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;

  // Count files per base name so a unique mapping keeps the short label.
  Counts := TDictionary<string, Integer>.Create;
  try
    for Key in AvroEncoFiles.Keys do
    begin
      Base := LowerCase(AvroEncoFiles[Key].BaseName);
      if Counts.TryGetValue(Base, Count) then
        Counts[Base] := Count + 1
      else
        Counts.Add(Base, 1);
    end;

    Keys := TList<string>.Create;
    try
      for Key in AvroEncoFiles.Keys do
        Keys.Add(Key);
      for Key in Keys do
      begin
        Info := AvroEncoFiles[Key];
        Count := 0;
        if (Info.BaseName <> '') and Counts.TryGetValue(LowerCase(Info.BaseName), Count) and (Count = 1) then
          Info.DisplayName := Info.BaseName
        else
          Info.DisplayName := Info.FileName;
        AvroEncoFiles[Key] := Info;
      end;
    finally
      Keys.Free;
    end;
  finally
    Counts.Free;
  end;
end;

procedure ScanAvroEncoFiles(const ADirectory: string);
var
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

    // The configured mapping directory is the sole catalog source. Bundled
    // mappings beside the executable must never shadow the user's files.
    ScanDirHelper(ADirectory);

    // Remove icon entries for files that no longer exist on disk (renamed or
    // deleted). This prevents the parent menu from retaining a stale mapping icon.
    for Key in OldKeys do
      if not AvroEncoFiles.ContainsKey(Key) then
        StoreMappingIcon(Key, nil);

    Log('Scanned AvroEnco files: ' + IntToStr(AvroEncoFiles.Count) + ' found');

    // Icons are NOT extracted here any more. The sweep used to run inside the
    // scan - i.e. on the startup path AND after every folder change - and it
    // decrypted every container and parsed every mapping document just to
    // cache a ~10 KB icon. UI paths resolve only the active layout on demand.
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
  Key := LowerCase(AInfo.FileName);

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
        StoreMappingIcon(AInfo.FileName, ExtractIconSection(JSONContent));
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
          StoreMappingIcon(AInfo.FileName, ExtractIconSection(JSONContent));
      end;
    except
      // Read error - icon will appear on demand.
    end;
  end;
end;

{ Resolves the icons of every mapping that has not been looked at yet. This is
  an explicit bulk operation; normal UI paths resolve only the active mapping. }
procedure EnsureMappingIcons;
var
  Info: TAvroEncoFileInfo;
begin
  if not Assigned(AvroEncoFiles) then
    Exit;
  for Info in AvroEncoFiles.Values do
    if not MappingIconResolved(Info.FileName) then
      ExtractOneFileIcon(Info);
end;

{ Resolves ONE mapping's icon. The name must be an exact known mapping file
  (the scan owns that knowledge); anything else is ignored rather than guessed
  by building a path here, because the caller's directory is not this unit's
  business. }
procedure EnsureMappingIcon(const AFileName: string);
var
  Info: TAvroEncoFileInfo;
begin
  if AFileName = '' then
    Exit;
  if not Assigned(AvroEncoFiles) then
    Exit;
  if MappingIconResolved(AFileName) then
    Exit;
  if not AvroEncoFiles.TryGetValue(LowerCase(AFileName), Info) then
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
        ErrorLog.Add('Error: ' + AvroEncoOpenFailureMessage(AFilePath));
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
    StoreMappingIcon(ExtractFileName(AFilePath), ExtractIconSection(JSONContent));

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
    Result := Result + sLineBreak + 'Suggested Font: ' + LFont + sLineBreak;
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

function IsBareMappingFileName(const AFileName: string): Boolean;
begin
  Result := (AFileName <> '') and (ExtractFileName(AFileName) = AFileName) and (Pos(':', AFileName) = 0);
end;

function GetExactEncoFilePath(const AFileName, ADirectory: string): string;
var
  Info: TAvroEncoFileInfo;
begin
  Result := '';
  if (not IsBareMappingFileName(AFileName)) or (not IsAnsiMappingFileName(AFileName)) then
    Exit;

  if Assigned(AvroEncoFiles) and AvroEncoFiles.TryGetValue(LowerCase(AFileName), Info) and FileExists(Info.FilePath) then
    Exit(Info.FilePath);

  // The catalog can be one scan behind (a file copied a moment ago). Check the
  // configured directory only; never a sibling extension or another folder.
  if (ADirectory <> '') and FileExists(ADirectory + AFileName) then
    Exit(ADirectory + AFileName);
end;

function GetActiveEncoFilePath(const AName, ADirectory: string): string;
begin
  Result := '';
  if not IsBareMappingFileName(AName) then
    Exit;

  // New exact-file form: used by Keyboard callers that pass a file name.
  if IsAnsiMappingFileName(AName) then
    Exit(GetExactEncoFilePath(AName, ADirectory));

  // Legacy base-name form, still used by the Converter. Keep the old
  // .AvroEnco -> .json priority and the configured-directory-only rule.
  if FileExists(ADirectory + AName + '.AvroEnco') then
    Exit(ADirectory + AName + '.AvroEnco');
  if FileExists(ADirectory + AName + '.json') then
    Exit(ADirectory + AName + '.json');
end;

function ResolveAnsiSelectionFile(const ABaseName, AFileName, ADirectory: string; out AMissingExact: Boolean): string;
var
  Companion, Base: string;
begin
  Result := '';
  AMissingExact := False;
  Base := Trim(ABaseName);
  if Base = '' then
    Exit;

  Companion := ExtractFileName(Trim(AFileName));
  if (Companion <> '') and (Pos(':', Companion) = 0) and IsAnsiMappingFileName(Companion) then
  begin
    if SameText(ChangeFileExt(Companion, ''), Base) then
    begin
      Result := GetExactEncoFilePath(Companion, ADirectory);
      if Result = '' then
        AMissingExact := True;
      Exit;
    end;
  end;

  // Companion absent/invalid/mismatched: a legacy base-name setting. Resolve
  // once through the old priority, then the caller persists the exact result.
  Result := GetActiveEncoFilePath(Base, ADirectory);
end;

procedure PublishActiveSelection(const AFileName, ABaseName: string);
begin
  AnsiVersion := ABaseName;
  AnsiVersionFileName := AFileName;
end;

function GetMappingDisplayLabel(const AFileName: string): string;
var
  Info: TAvroEncoFileInfo;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
  if AFileName = '' then
    Exit;
  if Assigned(AvroEncoFiles) and AvroEncoFiles.TryGetValue(LowerCase(AFileName), Info) then
    Result := Info.DisplayName;
end;

function EscapeAmpersandsForMenu(const ACaption: string): string;
begin
  Result := StringReplace(ACaption, '&', '&&', [rfReplaceAll]);
end;

{ Returns the same-named .json in the configured mapping directory, used as a
  Metadata source when an old .AvroEnco file (encrypted before Metadata
  existed) decrypts to JSON without a Metadata block. }
function FindMetadataJsonPath(const ADisplayName: string; const ADirectory: string): string;
begin
  Result := '';
  if (ADisplayName = '') or (ADirectory = '') then
    Exit;
  if FileExists(ADirectory + ADisplayName + '.json') then
    Exit(ADirectory + ADisplayName + '.json');
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
  Key, Base: string;
begin
  if not Assigned(ANames) then
    Exit;
  ANames.Clear;
  // Converter-facing list: each base name once, even when the folder contains
  // both one.AvroEnco and one.json. The Keyboard uses the exact list below.
  if Assigned(AvroEncoFiles) then
    for Key in AvroEncoFiles.Keys do
    begin
      Base := AvroEncoFiles[Key].BaseName;
      if ANames.IndexOf(Base) < 0 then
        ANames.Add(Base);
    end;
  SortMappingDisplayNames(ANames);
end;

function CompareMappingFileNamesCallback(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result := CompareMappingDisplayNames(GetMappingDisplayLabel(List[Index1]), GetMappingDisplayLabel(List[Index2]));
  if Result = 0 then
    Result := CompareText(List[Index1], List[Index2]);
end;

procedure GetSortedMappingFileNames(ANames: TStrings);
var
  Key: string;
begin
  if not Assigned(ANames) then
    Exit;
  ANames.Clear;
  if Assigned(AvroEncoFiles) then
    for Key in AvroEncoFiles.Keys do
      ANames.Add(AvroEncoFiles[Key].FileName);
  if ANames is TStringList then
    TStringList(ANames).CustomSort(CompareMappingFileNamesCallback);
end;

function FirstAvailableMappingName: string;
var
  Names: TStringList;
  I:     Integer;
  Path:  string;
begin
  Result := '';
  Names := TStringList.Create;
  try
    GetSortedMappingDisplayNames(Names);
    for I := 0 to Names.Count - 1 do
    begin
      Path := GetActiveEncoFilePath(Names[I], AnsiMappingDir);
      if Path = '' then
        Continue;
      // A password container with no cached password cannot be activated at
      // startup without a prompt - skip it; the picker still lists it.
      if IsEncoFile(Path) and (GetAvroEncoProtectionFlag(Path) = AVROENCO_FLAG_USER_PASSWORD) and (GetEncoCachedPassword(Path) = '') then
        Continue;
      Exit(Names[I]);
    end;
  finally
    Names.Free;
  end;
end;

function FirstAvailableMappingFileName: string;
var
  Names: TStringList;
  I:     Integer;
  Path:  string;
begin
  Result := '';
  Names := TStringList.Create;
  try
    GetSortedMappingFileNames(Names);
    for I := 0 to Names.Count - 1 do
    begin
      Path := GetExactEncoFilePath(Names[I], AnsiMappingDir);
      if Path = '' then
        Continue;
      // A password container with no cached password cannot be activated at
      // startup without a prompt - skip it; the picker still lists it.
      if IsEncoFile(Path) and (GetAvroEncoProtectionFlag(Path) = AVROENCO_FLAG_USER_PASSWORD) and (GetEncoCachedPassword(Path) = '') then
        Continue;
      Exit(Names[I]);
    end;
  finally
    Names.Free;
  end;
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
FreeEncoPasswordCache; // the memory this unit owns (see the interface section)

end.
