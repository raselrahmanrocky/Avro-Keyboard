{

  kat_engineswitch - engine-cache ownership and version-switch gate.

  The parser gates (kat_ansiconvert, kat_karcall) prove the mapping DATA and the
  conversion engine. This one proves the CACHE around them, because that is
  where the shipped app went wrong:

    "Ansi V4 is selected, but kars (aa/i/ii/u/uu/ri) emit nothing and the
     letters look like the built-in default scheme."

  The container was fine. uAnsiEngineManager parses into the unit globals, and
  LoadAnsiMappingFromJSON starts with ResetAnsiToDefaults - so a parse that runs
  while an engine is ACTIVE (its containers are the globals while it runs, its
  slot is empty) destroyed that engine and left a hollow slot: a state with no
  registry and no rule tables. Serving it strips every kar rule and every lookup
  map while the menu still shows the version as selected, and the fast switch
  answered "already active" without restoring anything, so clicking the version
  again could never repair it.

  This program drives the real TAnsiEngineManager over real containers:

    1. cold preload (nothing live, like a fresh start) then a switch,
    2. the reported order: an engine is live, then a preload batch commits,
    3. version clicks, including clicking the already-active version,
    4. a background re-parse of a NON-active mapping while one is live,
    5. a new container appearing in the folder at runtime,
    6. a corrupt container (must fail closed and keep the live engine),
    7. a deliberately hollowed live engine (must be detected and repaired),
    8. the warm pass,
    9. the encoding-list order the two menus and the picker must share, and the
       picker's number (row + numpad) and first-letter shortcut resolution.

  After every step it fingerprints the LIVE engine - a corpus of kars, clusters
  and conjuncts converted through whatever engine is actually installed - and
  demands an exact match with the fingerprint of the requested mapping loaded
  fresh. A hollow or wrong engine cannot pass that.

  Side effects: a scratch directory under %TEMP% and the app's own persistent
  JSON cache under %APPDATA% (content-addressed, same as running the app).

  Usage: kat_engineswitch <mapping-dir> [quiet]
  Exit code: 0 all scenarios pass, 1 otherwise.
}

{$APPTYPE CONSOLE}

program kat_engineswitch;

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Generics.Collections,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAnsiPersistentCache,
  uAnsiEngineManager,
  clsUnicodeToBijoy2000;

const
  // Unicode code points the probes are built from (avoids non-ASCII literals).
  U_K   = $0995; U_T   = $09A4; U_R   = $09B0; U_S   = $09B7;
  U_AAKAR = $09BE; U_IKAR = $09BF; U_IIKAR = $09C0; U_UKAR = $09C1;
  U_UUKAR = $09C2; U_RIKAR = $09C3; U_EKAR = $09C7; U_OIKAR = $09C8;
  U_OKAR = $09CB; U_OUKAR = $09CC; U_HASANTA = $09CD;
  U_ANUSVARA = $0982; U_CHANDRABINDU = $0981;

  TAG_COLD_A = 'Gate Cold 1';
  TAG_COLD_B = 'Gate Cold 2';
  TAG_COLD_NEW = 'Gate Cold 3';
  TAG_COLD_BAD = 'Gate Cold 4';

var
  Fails: Integer;
  FQuiet: Boolean;
  Goldens: TDictionary<string, string>;
  // Scratch copies carry gate tags ("Gate Cold 1"); this maps them back to the
  // shipped mapping whose golden they must match.
  TagGolden: TDictionary<string, string>;

procedure Say(const AText: string);
begin
  if not FQuiet then
    WriteLn(AText);
end;

procedure Check(ACond: Boolean; const AText: string);
begin
  if ACond then
  begin
    Say('  ok   ' + AText);
    Exit;
  end;
  Inc(Fails);
  WriteLn('FAIL ' + AText);
end;

function HexBytes(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[I]), 2);
  end;
  if Result = '' then
    Result := '..';
end;

// Compact view of a name list, for the order assertions below.
function Joined(AList: TStrings): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to AList.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + AList[I];
  end;
end;

// Where two fingerprints first diverge - the one line that makes a mismatch
// diagnosable instead of just "not equal".
function FirstDiff(const A, B: string): string;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) < N then
    N := Length(B);
  for I := 1 to N do
    if A[I] <> B[I] then
    begin
      Result := Format('at %d: live=%s golden=%s', [I,
        Copy(A, I, 12), Copy(B, I, 12)]);
      Exit;
    end;
  Result := Format('lengths differ: live=%d golden=%d', [Length(A), Length(B)]);
end;

// Kars exactly as the layout's kar keys deliver them (same set as kat_karcall).
function KarList: TArray<TPair<string, string>>;
begin
  Result := TArray<TPair<string, string>>.Create(
    TPair<string, string>.Create('aa-kar', Chr(U_AAKAR)),
    TPair<string, string>.Create('i-kar', Chr(U_IKAR)),
    TPair<string, string>.Create('ii-kar', Chr(U_IIKAR)),
    TPair<string, string>.Create('u-kar', Chr(U_UKAR)),
    TPair<string, string>.Create('uu-kar', Chr(U_UUKAR)),
    TPair<string, string>.Create('ri-kar', Chr(U_RIKAR)),
    TPair<string, string>.Create('e-kar', Chr(U_EKAR)),
    TPair<string, string>.Create('oi-kar', Chr(U_OIKAR)),
    TPair<string, string>.Create('o-kar', Chr(U_OKAR)),
    TPair<string, string>.Create('ou-kar', Chr(U_OUKAR)));
end;

// Consonants, kars, conjuncts and the hasanta+aa ("আ") case the user reported.
function ProbeList: TArray<string>;
var
  K, T_, R_, S_: string;
begin
  K := Chr(U_K);
  T_ := Chr(U_T);
  R_ := Chr(U_R);
  S_ := Chr(U_S);
  Result := TArray<string>.Create(
    K,
    K + Chr(U_AAKAR),
    K + Chr(U_IKAR),
    K + Chr(U_IIKAR),
    K + Chr(U_UKAR),
    K + Chr(U_UUKAR),
    K + Chr(U_RIKAR),
    K + Chr(U_EKAR),
    K + Chr(U_OIKAR),
    K + Chr(U_OKAR),
    K + Chr(U_OUKAR),
    K + Chr(U_HASANTA) + Chr(U_AAKAR),
    K + Chr(U_HASANTA) + T_,
    K + Chr(U_HASANTA) + R_,
    K + Chr(U_HASANTA) + S_,
    K + Chr(U_ANUSVARA),
    K + Chr(U_CHANDRABINDU),
    R_ + Chr(U_HASANTA) + K,
    K + Chr(U_HASANTA) + T_ + Chr(U_HASANTA) + R_);
end;

// One string that describes the engine actually installed right now: what every
// probe converts to, plus what the isolated-kar resolver does with each kar.
function Fingerprint: string;
var
  Conv: TUnicodeToBijoy2000;
  Probes: TArray<string>;
  KarSet: TArray<TPair<string, string>>;
  P, Isolated, Matched: string;
  Kar: TPair<string, string>;
  Erase: Integer;
  IsToggle, UsedAlt: Boolean;
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    Conv := TUnicodeToBijoy2000.Create;
    try
      Probes := ProbeList;
      for P in Probes do
        B.Append(HexBytes(Conv.Convert(P))).Append('|');
      KarSet := KarList;
      for Kar in KarSet do
      begin
        B.Append(Kar.Key).Append('=');
        if Conv.ResolveAnsiSequence(Chr(U_K), Kar.Value, Isolated, Erase, Matched,
          IsToggle, UsedAlt) then
          B.Append(HexBytes(Isolated)).Append('+').Append(IntToStr(Erase))
        else
          B.Append('fallthrough');
        B.Append('|');
      end;
    finally
      Conv.Free;
    end;
    Result := B.ToString;
  finally
    B.Free;
  end;
end;

function GoldenOf(const AName: string): string;
begin
  if not Goldens.TryGetValue(Lowercase(AName), Result) then
    Result := '';
end;

function GoldenNameOf(const AName: string): string;
begin
  if not TagGolden.TryGetValue(Lowercase(AName), Result) then
    Result := AName;
end;

// Loads one mapping from disk the way a cold engine would (decrypt + reset +
// parse) and fingerprints it: this is the reference the live engine must match.
procedure InstallGolden(const AName, APath: string);
var
  JSON: string;
  Log: TStringList;
begin
  if not FileExists(APath) then
  begin
    Check(False, 'golden input missing: ' + APath);
    Exit;
  end;
  if IsEncoFile(APath) then
    JSON := Trim(DecryptAvroEncoToString(APath, ''))
  else
    JSON := Trim(TFile.ReadAllText(APath, TEncoding.UTF8));
  if (JSON <> '') and (JSON[1] = #$FEFF) then
    Delete(JSON, 1, 1);
  if (JSON = '') or (JSON[1] <> '{') then
  begin
    Check(False, 'golden: unusable mapping ' + ExtractFileName(APath));
    Exit;
  end;

  Log := TStringList.Create;
  try
    ResetAnsiToDefaults;
    LoadAnsiMappingFromJSON(JSON, Log);
  finally
    Log.Free;
  end;

  Goldens.AddOrSetValue(Lowercase(AName), Fingerprint);
  Say('  golden ' + AName + ' -> ' + IntToStr(Length(GoldenOf(AName))) + ' chars');
end;

// Builds every golden with the live globals parked, so that "nothing is live"
// (a cold start) is still reachable for the manager scenarios below.
procedure BuildGoldens(const ADir: string; ANames: TStringList);
var
  Saved, Discard: TAnsiEngineState;
  I: Integer;
  P: string;
begin
  InitEngineState(Saved);
  CaptureEngineState(Saved);
  try
    for I := 0 to ANames.Count - 1 do
    begin
      P := ADir + ANames[I] + '.AvroEnco';
      if not FileExists(P) then
        P := ADir + ANames[I] + '.json';
      InstallGolden(ANames[I], P);
    end;
  finally
    InitEngineState(Discard);
    CaptureEngineState(Discard); // drop the last golden's engine
    Discard.Clear;
    RestoreEngineState(Saved);   // put the process's own state back
  end;
end;

function CollectNames(const ADir: string; ANames: TStringList): Integer;
var
  SR: TSearchRec;
begin
  Result := 0;
  if FindFirst(ADir + '*.AvroEnco', faAnyFile, SR) = 0 then
    try
      repeat
        if ((SR.Attr and faDirectory) = 0) and (SR.Name <> '.') and
          (SR.Name <> '..') then
        begin
          ANames.Add(ChangeFileExt(SR.Name, ''));
          Inc(Result);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  ANames.Sort;
end;

// Exactly what TAnsiPreloadThread does off the UI thread (decrypt in RAM), run
// sequentially here because this gate is about ordering, not about threads.
function RunPreload: Integer;
var
  Items: TArray<TPreloadItem>;
  Results: TArray<TPreloadResult>;
  I: Integer;
begin
  Items := AnsiEngineManager.CapturePreloadList;
  SetLength(Results, Length(Items));
  for I := 0 to High(Items) do
  begin
    Results[I].DisplayName := Items[I].DisplayName;
    Results[I].FilePath := Items[I].FilePath;
    Results[I].JSON := '';
    Results[I].OK := False;
    Results[I].ErrorMsg := '';
    try
      Results[I].OK :=
        LoadAnsiJSONCached(Items[I].FilePath, Items[I].Password, Results[I].JSON) and
        (Results[I].JSON <> '') and (Results[I].JSON[1] = '{');
    except
      on E: Exception do
        Results[I].ErrorMsg := E.ClassName + ': ' + E.Message;
    end;
  end;
  Result := AnsiEngineManager.CommitPreload(Results);
end;

// The heart of the gate: the engine that is actually installed must be the
// requested mapping, must be usable, and must match that mapping's fingerprint.
procedure ExpectLive(const AName, AWhere: string);
var
  Want, Got: string;
begin
  Check(AnsiEngineManager.LiveEngineReady, AWhere + ': a live engine is installed');
  Check(AnsiEngineManager.CurrentEngineName = Lowercase(AName),
    AWhere + ': active engine is "' + AName + '" (got "' +
    AnsiEngineManager.CurrentEngineName + '")');
  Want := GoldenOf(GoldenNameOf(AName));
  if Want = '' then
  begin
    Check(False, AWhere + ': no golden for "' + AName + '"');
    Exit;
  end;
  Got := Fingerprint;
  if Got = Want then
    Check(True, AWhere + ': live engine behaves exactly like "' +
      GoldenNameOf(AName) + '"')
  else
    Check(False, AWhere + ': live engine differs from "' +
      GoldenNameOf(AName) + '" (' + FirstDiff(Got, Want) + ')');
end;

function FreshDir(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(
    TPath.Combine(TPath.GetTempPath, AName));
  if DirectoryExists(Result) then
    TDirectory.Delete(Result, True);
  TDirectory.CreateDirectory(Result);
end;

procedure CopyAs(const ASrc, ADir, AName: string);
begin
  TFile.Copy(ASrc, ADir + AName + '.AvroEnco', True);
end;

var
  Dir, Src, TmpCold, PathA, PathB, PathBad: string;
  Names: TStringList;
  AName, BName: string;
  ErrLog: TStringList;
  Scratch: TAnsiEngineState;
  Count: Integer;
  Bytes: TBytes;
  Prev: string;
  Shortcuts: TStringList;
  I: Integer;
  SortedOk, HasDefault: Boolean;
begin
  Fails := 0;
  FQuiet := False;
  Goldens := TDictionary<string, string>.Create;
  TagGolden := TDictionary<string, string>.Create;
  Names := TStringList.Create;
  try
    if ParamCount >= 1 then
      Dir := IncludeTrailingPathDelimiter(ParamStr(1))
    else
      Dir := '';
    if (Dir = '') or (not DirectoryExists(Dir)) then
    begin
      WriteLn('usage: kat_engineswitch <mapping-dir> [quiet]');
      ExitCode := 2;
      Exit;
    end;
    if (ParamCount >= 2) and SameText(ParamStr(2), 'quiet') then
      FQuiet := True;

    Say('kat_engineswitch: ' + Dir);

    // ---- references -----------------------------------------------------
    Say('--- references (each mapping loaded fresh) ---');
    Count := CollectNames(Dir, Names);
    Check(Count >= 2, 'at least two shippable containers in ' + Dir +
      ' (found ' + IntToStr(Count) + ')');
    if Count < 2 then
    begin
      WriteLn('SKIPPED: need two mappings to switch between');
      ExitCode := 1;
      Exit;
    end;
    AName := Names[0];
    BName := Names[Names.Count - 1];
    BuildGoldens(Dir, Names);

    // ---- 1. cold preload, then a switch ---------------------------------
    Say('--- 1. cold start: preload with nothing live, then switch ---');
    TmpCold := FreshDir('kat_engineswitch_cold');
    PathA := Dir + AName + '.AvroEnco';
    PathB := Dir + BName + '.AvroEnco';
    CopyAs(PathA, TmpCold, TAG_COLD_A);
    CopyAs(PathB, TmpCold, TAG_COLD_B);
    TagGolden.AddOrSetValue(Lowercase(TAG_COLD_A), AName);
    TagGolden.AddOrSetValue(Lowercase(TAG_COLD_B), BName);
    TagGolden.AddOrSetValue(Lowercase(TAG_COLD_NEW), AName);
    AnsiMappingDir := TmpCold;
    ScanAvroEncoFiles(TmpCold);
    Count := RunPreload;
    Say('  preloaded ' + IntToStr(Count) + ' engine(s)');
    Check(AnsiEngineManager.SwitchEngine(TAG_COLD_B), '1: first switch parses on demand');
    ExpectLive(TAG_COLD_B, '1 (after cold preload + switch)');
    Check(AnsiEngineManager.CachedEngineReady(TAG_COLD_A), '1: sibling engine is cached');
    Check(AnsiEngineManager.TrySwitchCached(TAG_COLD_A), '1: fast switch to the sibling');
    ExpectLive(TAG_COLD_A, '1 (fast switch to the sibling)');

    // ---- 2. the reported order: live engine, then a preload batch -------
    // This is the shape the app hits at every start: the active mapping is
    // parsed first (auto-refresh), and only then does CommitPreload parse the
    // other engines. Before the invariant that destroyed the live engine.
    Say('--- 2. engine live, then a preload batch commits (the reported order) ---');
    Check(AnsiEngineManager.SwitchEngine(TAG_COLD_B), '2: active engine is live');
    ExpectLive(TAG_COLD_B, '2 (before the batch)');
    CopyAs(PathA, TmpCold, TAG_COLD_NEW);
    ScanAvroEncoFiles(TmpCold);
    Count := RunPreload;
    Say('  preloaded ' + IntToStr(Count) + ' engine(s) while ' + TAG_COLD_B + ' was live');
    ExpectLive(TAG_COLD_B, '2 (after the batch committed)');
    Check(AnsiEngineManager.CachedEngineReady(TAG_COLD_NEW), '2: newly added engine is cached');

    // ---- 3. clicks ------------------------------------------------------
    Say('--- 3. version clicks ---');
    Check(AnsiEngineManager.TrySwitchCached(TAG_COLD_A), '3: click the other version');
    ExpectLive(TAG_COLD_A, '3 (click 1)');
    Check(AnsiEngineManager.TrySwitchCached(TAG_COLD_B), '3: click back');
    ExpectLive(TAG_COLD_B, '3 (click 2)');
    Check(AnsiEngineManager.TrySwitchCached(TAG_COLD_B),
      '3: clicking the already-active version reports success');
    ExpectLive(TAG_COLD_B, '3 (click 3, same version again)');
    Check(AnsiEngineManager.TrySwitchCached(TAG_COLD_A), '3: click once more');
    ExpectLive(TAG_COLD_A, '3 (click 4)');

    // ---- 4. background re-parse of a NON-active mapping ------------------
    Say('--- 4. background re-parse of a non-active mapping ---');
    AnsiEngineManager.InvalidateEngine(TAG_COLD_B);
    ExpectLive(TAG_COLD_A, '4: live engine survived a background re-parse');
    Check(AnsiEngineManager.CachedEngineReady(TAG_COLD_B), '4: re-parsed engine is cached');

    // ---- 5. new container appears at runtime ----------------------------
    Say('--- 5. new container appears while an engine is live ---');
    CopyAs(PathB, TmpCold, 'Gate Cold 9');
    TagGolden.AddOrSetValue(Lowercase('Gate Cold 9'), BName);
    ScanAvroEncoFiles(TmpCold);
    AnsiEngineManager.RefreshFromDisk;
    ExpectLive(TAG_COLD_A, '5: live engine survived RefreshFromDisk');
    Check(AnsiEngineManager.CachedEngineReady('Gate Cold 9'), '5: new engine was preloaded');

    // ---- 6. corrupt container must fail closed --------------------------
    Say('--- 6. corrupt container ---');
    Bytes := TFile.ReadAllBytes(PathB);
    SetLength(Bytes, 128);
    PathBad := TmpCold + TAG_COLD_BAD + '.AvroEnco';
    TFile.WriteAllBytes(PathBad, Bytes);
    ScanAvroEncoFiles(TmpCold);
    ErrLog := TStringList.Create;
    try
      Check(not AnsiEngineManager.SwitchEngine(TAG_COLD_BAD, ErrLog),
        '6: switching to a corrupt container fails');
      Check(Trim(ErrLog.Text) <> '', '6: failure is reported to the caller');
    finally
      ErrLog.Free;
    end;
    ExpectLive(TAG_COLD_A, '6: live engine untouched by the failed switch');

    // ---- 7. hollowed live engine must be detected and repaired ----------
    // Force the exact state the old code produced: the live engine's containers
    // are taken away while the manager still believes it is active.
    Say('--- 7. hollowed live engine (the reported symptom) ---');
    Prev := AnsiEngineManager.CurrentEngineName;
    InitEngineState(Scratch);
    CaptureEngineState(Scratch);
    Scratch.Clear;
    Check(not AnsiEngineManager.LiveEngineReady, '7: hollow state reproduced');
    Check(not AnsiEngineManager.TrySwitchCached(Prev),
      '7: fast switch does not claim success for a hollow engine');
    Check(AnsiEngineManager.SwitchEngine(Prev), '7: switch repairs it from disk');
    ExpectLive(Prev, '7 (repaired)');

    // ---- 8. warm pass ---------------------------------------------------
    Say('--- 8. warm pass ---');
    AnsiEngineManager.WarmAllEngines(Prev);
    ExpectLive(Prev, '8 (after WarmAllEngines)');

    // ---- 9. encoding list order + picker shortcuts -----------------------
    // The two encoding menus and the version picker must present one single
    // order (the shipped bug: the menus enumerated the AvroEncoFiles hash table
    // and showed Default, V1, V4, V2, V3 next to a correctly sorted picker),
    // and the picker's number/letter shortcuts must land on exactly the rows
    // the owner-drawn list numbers.
    Say('--- 9. mapping order + picker shortcut resolution ---');
    Shortcuts := TStringList.Create;
    try
      // No zero-padded duplicate here: names that are numerically equal (V1 /
      // V01) compare equal, so their relative order is unspecified on purpose.
      Shortcuts.Add('Ansi V10');
      Shortcuts.Add('Ansi V2');
      Shortcuts.Add('Default');
      Shortcuts.Add('Ansi V1');
      SortMappingDisplayNames(Shortcuts);
      Check(Joined(Shortcuts) = 'Ansi V1,Ansi V2,Ansi V10,Default',
        '9: natural order puts V2 before V10 (' + Joined(Shortcuts) + ')');
      Check(CompareMappingDisplayNames('Ansi V2', 'Ansi V10') < 0, '9: V2 < V10');
      Check(CompareMappingDisplayNames('Ansi V10', 'Ansi V2') > 0, '9: V10 > V2');
      Check(CompareMappingDisplayNames('Ansi V1', 'Ansi V1') = 0,
        '9: identical names compare equal');
      Check(CompareMappingDisplayNames('ansi v1', 'Ansi V1') = 0,
        '9: comparison ignores case');
      Check(CompareMappingDisplayNames('Ansi V1', 'Ansi V10') < 0,
        '9: a prefix sorts before its extension');
      Check(CompareMappingDisplayNames('Ansi V01', 'Ansi V1') = 0,
        '9: leading zeros do not change the number');
      Check(CompareMappingDisplayNames('Ansi V3', 'Ansi V10') < 0,
        '9: 3 still sorts before 10');

      // Teeth check, on the same list the assertion above used: a plain
      // alphabetical sort puts V10 before V2, so that assertion is not
      // satisfied by the list merely happening to be pre-sorted.
      Names.Assign(Shortcuts);
      Names.Sort;
      Check(Joined(Names) = 'Ansi V1,Ansi V10,Ansi V2,Default',
        '9: the alphabetical sort this replaced really was wrong (' + Joined(Names) + ')');

      // Exactly the list the picker draws: 1. Default, 2. Ansi V1, ...
      Shortcuts.Clear;
      Shortcuts.Add('Default');
      Shortcuts.Add('Ansi V1');
      Shortcuts.Add('Ansi V2');
      Shortcuts.Add('Ansi V3');
      Check(MappingIndexForKey(Shortcuts, Ord('1')) = 0, '9: number row 1 -> Default');
      Check(MappingIndexForKey(Shortcuts, Ord('4')) = 3, '9: number row 4 -> last row');
      Check(MappingIndexForKey(Shortcuts, Ord('9')) = -1,
        '9: a number past the last row is not a shortcut');
      Check(MappingIndexForKey(Shortcuts, Ord('0')) = -1, '9: 0 is not a shortcut');
      Check(MappingIndexForKey(Shortcuts, VK_NUMPAD1) = 0, '9: numpad 1 -> Default');
      Check(MappingIndexForKey(Shortcuts, VK_NUMPAD4) = 3, '9: numpad 4 -> last row');
      Check(MappingIndexForKey(Shortcuts, VK_NUMPAD9) = -1,
        '9: numpad past the last row is not a shortcut');
      Check(MappingIndexForKey(Shortcuts, VK_F1) = -1, '9: function keys are not shortcuts');
      Check(MappingIndexForKey(Shortcuts, VK_ESCAPE) = -1, '9: Escape is not a number shortcut');
      Check(MappingIndexForChar(Shortcuts, 'd') = 0, '9: ''d'' selects Default');
      Check(MappingIndexForChar(Shortcuts, 'D') = 0, '9: ''D'' matches Default as well');
      Check(MappingIndexForChar(Shortcuts, 'a') = 1, '9: ''a'' selects the first Ansi entry');
      Check(MappingIndexForChar(Shortcuts, 'A') = 1, '9: ''A'' matches as well');
      Check(MappingIndexForChar(Shortcuts, 'v') = -1,
        '9: only the first character matches');
      Check(MappingIndexForChar(Shortcuts, #0) = -1, '9: control characters are ignored');
      Shortcuts.Insert(0, '');
      Check(MappingIndexForChar(Shortcuts, 'd') = 1, '9: an empty row is skipped by letter search');
      Check(MappingIndexForKey(Shortcuts, Ord('1')) = 0, '9: numbering still follows the rows');

      // The registry hands out the same order the menus iterate, and never
      // 'Default' - the menus and the picker pin that row at the top themselves.
      GetSortedMappingDisplayNames(Names);
      SortedOk := Names.Count > 0;
      for I := 0 to Names.Count - 2 do
        if CompareMappingDisplayNames(Names[I], Names[I + 1]) > 0 then
          SortedOk := False;
      HasDefault := False;
      for I := 0 to Names.Count - 1 do
        if SameText(Names[I], 'Default') then
          HasDefault := True;
      Check(SortedOk, '9: registry names come back in the shared order (' +
        IntToStr(Names.Count) + ' names)');
      Check(not HasDefault, '9: the registry list excludes Default');
    finally
      Shortcuts.Free;
    end;
  finally
    Goldens.Free;
    TagGolden.Free;
    Names.Free;
  end;

  if Fails = 0 then
    WriteLn('ALL PASS (engine cache keeps the requested engine installed)')
  else
    WriteLn(Format('%d engine-cache check(s) FAILED', [Fails]));
  ExitCode := Ord(Fails > 0);
end.
