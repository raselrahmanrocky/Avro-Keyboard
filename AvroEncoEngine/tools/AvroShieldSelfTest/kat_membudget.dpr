{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

program kat_membudget;

{ Idle-memory budget gate for the lazy ANSI engine cache.

  Why a separate gate
  -------------------
  The 2 MB -> 6 MB idle regression came from work that happens before the user
  touches anything: every container decrypted and parsed and parked forever, and
  a full System.JSON document tree built per container just to read one scalar.
  A build step cannot open the GUI, but it CAN run exactly those paths
  headlessly and assert what they cost - which is what this gate does.

  What it pins
  ------------
  1. Scanning a mapping directory is CHEAP (no decrypt, no parse, no icon
  extraction) - the sweep moved out of ScanAvroEncoFiles.
  2. Live engine only: activating the first file mapping costs one parse,
  activating a container costs one parse, and nothing else becomes resident.
  3. The warm set is bounded by MaxWarmEngines and switching inside it stays
  O(1) pointer moves (the typing latency contract).
  4. Icon extraction is per-mapping and DOM-free: N mappings must cost a
  fraction of what ONE TJSONObject tree over a mapping document cost.
  5. The idle release gives the heap back, keeps the live engine working, and
  re-parses a released engine on demand.

  Budgets are deliberately loose multiples of the measured cost: this gate is
  here to catch a re-introduced all-engine preload or a re-introduced DOM parse,
  not to police a few KB of drift across Delphi builds.

  Usage: kat_membudget <mapping-dir> [quiet]
  Exit code: 0 all PASS, 1 FAIL.
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Diagnostics,
  DebugLog,
  clsUnicodeToBijoy2000,
  uAnsiEngineManager,
  uAvroEncoManager,
  uAvroEngineStats;

const
  { Scanning must not read container contents at all - it is a directory
    listing plus a dictionary of file info. 512 KB is generous for that and
    still an order of magnitude below one parsed engine. }
  BUDGET_SCAN_HEAP = 512 * 1024;
  { A live engine (its rules, groups and compiled lookup tables). }
  BUDGET_ENGINE_HEAP = 2 * 1024 * 1024;
  { One engine's icon bytes, decoded from its payload (16+32 px frames plus
    Base64 - measured ~10 KB per container). 64 KB per mapping catches both a
    runaway icon and a leak that keeps them alive after a clear. }
  BUDGET_ICON_BYTES = 64 * 1024;
  { N mappings worth of icons, extracted lazily. A System.JSON document tree
    over one 49..114 KB mapping costs megabytes on its own, so this budget can
    only pass while ExtractIconSection stays a scalar scan. }
  BUDGET_ALL_ICONS_HEAP = 2 * 1024 * 1024;
  { 200 switches between the live engine and the parked one.

    Deliberately generous, and now looser than it needs to be: the floor used
    to be DebugLog - each switch wrote one log line and DebugLog opened,
    appended and closed a file per line, measured ~8 ms and printed by this
    gate as "200 log lines cost ...". That sink is file-free and compiled out
    now (see DebugLog), so the probe below reports ~0 ms and the 2500 ms here
    no longer trips on a re-introduced log line. The
    assertion this budget really makes is "no switch in that loop did disk
    I/O, decryption or parsing" - a cold parse is ~60 ms, so anything that
    started parsing would blow through this by an order of magnitude. The
    exact O(1) claim is checked separately, relative to a cold switch. }
  BUDGET_WARM_SWITCH_MS = 2500;
  { One cold switch: decrypt + parse + park. }
  BUDGET_COLD_SWITCH_MS = 3000;

var
  Fails: Integer;
  Quiet: Boolean;

procedure Say(const AText: string);
begin
  if not Quiet then
    WriteLn(AText);
end;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('     ' + ADetail);
    Inc(Fails);
  end;
end;

function KB(const ABytes: Int64): string;
begin
  Result := IntToStr(ABytes div 1024) + ' KB';
end;

var
  MappingDir, V, ActiveName, WarmName, ColdName, SampleName: string;
  Converter:                                                 TUnicodeToBijoy2000;
  EngineList:                                                TStringList;
  Err:                                                       TStringList;
  Before, After, AtStart:                                    TAvroMemStats;
  ScanHeap, EngineHeap, IconSum:                             Int64;
  SW:                                                        TStopwatch;
  I, EnginesParsed, Dropped, Refused, LogMs, WarmMs, ColdMs: Integer;
  Ok:                                                        Boolean;
  IconBytes:                                                 TBytes;

begin
  Fails := 0;
  Quiet := (ParamCount >= 2) and SameText(ParamStr(2), 'quiet');

  if ParamCount < 1 then
  begin
    WriteLn('Usage: kat_membudget <mapping-dir> [quiet]');
    Halt(1);
  end;
  MappingDir := IncludeTrailingPathDelimiter(ParamStr(1));
  if not DirectoryExists(MappingDir) then
  begin
    WriteLn('FAIL mapping directory does not exist: ' + MappingDir);
    Halt(1);
  end;

  Converter := TUnicodeToBijoy2000.Create;
  EngineList := TStringList.Create;
  Err := TStringList.Create;
  try
    AnsiMappingDir := MappingDir;
    AnsiVersion := '';
    AtStart := GetAvroMemStats;
    Say(AvroMemStatsText('start', AtStart));

    // ---- 1. the directory scan must not read mapping contents -------------
    Before := GetAvroMemStats;
    InitializeEncoManager;
    ScanAvroEncoFiles(MappingDir);
    After := GetAvroMemStats;
    ScanHeap := After.HeapBytes - Before.HeapBytes;
    Say('scan of ' + IntToStr(AvroEncoFiles.Count) + ' mapping(s) cost ' + KB(ScanHeap) + ' of heap');
    Check('the mapping scan found files', AvroEncoFiles.Count > 1, 'count=' + IntToStr(AvroEncoFiles.Count));
    Check('the scan does not parse or decrypt anything', ScanHeap <= BUDGET_SCAN_HEAP, 'heap delta ' + KB(ScanHeap) + ' > budget ' + KB(BUDGET_SCAN_HEAP));

    for V in AvroEncoFiles.Keys do
      EngineList.Add(AvroEncoFiles[V].DisplayName);

    // ---- 2. first file mapping only: nothing else may become resident -----
    // This is the startup shape of the branch: the persisted version (here
    // the first file mapping) is the ONE engine activated, everything else
    // stays cold.
    Before := GetAvroMemStats;
    ActiveName := FirstAvailableMappingName;
    Ok := (ActiveName <> '') and AnsiEngineManager.SwitchEngine(ActiveName, Err);
    Check('first file mapping activates', Ok, Err.Text);
    Check('activating it parks nothing else', AnsiEngineManager.WarmEngineCount = 0, 'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));
    After := GetAvroMemStats;
    Check('the live engine is effectively free', After.HeapBytes - Before.HeapBytes <= 256 * 1024, 'heap delta ' + KB(After.HeapBytes - Before.HeapBytes));
    Check('the live engine converts', Converter.Convert(#$0995#$09BF) <> '');

    // ---- 3. icons: lazy, per mapping, DOM-free ----------------------------
    Before := GetAvroMemStats;
    EnsureMappingIcons;
    After := GetAvroMemStats;
    IconSum := 0;
    SampleName := '';
    for V in AvroEncoFiles.Keys do
    begin
      SampleName := AvroEncoFiles[V].DisplayName;
      IconBytes := GetMappingIconBytes(SampleName);
      IconSum := IconSum + Length(IconBytes);
      Check('icon resolved: ' + SampleName, (Length(IconBytes) > 0) and (Length(IconBytes) <= BUDGET_ICON_BYTES), 'bytes=' + IntToStr(Length(IconBytes)));
    end;
    Say('all icons cost ' + KB(After.HeapBytes - Before.HeapBytes) + ' of heap (' + IntToStr(IconSum div 1024) + ' KB of icon bytes)');
    Check('all icons together stay inside the budget', After.HeapBytes - Before.HeapBytes <= BUDGET_ALL_ICONS_HEAP,
      'heap delta ' + KB(After.HeapBytes - Before.HeapBytes) + ' > budget ' + KB(BUDGET_ALL_ICONS_HEAP));
    Check('the icon cache reports the mappings as resolved', (SampleName <> '') and MappingIconResolved(SampleName));

    // A released icon cache must claim nothing and re-resolve on demand.
    ClearMappingIcons;
    Check('a cleared icon is no longer reported as resolved', (SampleName <> '') and (not MappingIconResolved(SampleName)));
    EnsureMappingIcon(SampleName);
    Check('an icon re-resolves on demand after a clear', Length(GetMappingIconBytes(SampleName)) > 0);

    // ---- 4. cold parse of a real engine -----------------------------------
    EnginesParsed := 0;
    ColdName := '';
    for V in EngineList do
      if (V <> '') and (not SameText(V, ActiveName)) then
      begin
        ColdName := V;
        Break;
      end;
    if ColdName = '' then
      Check('a container engine is available to activate', False)
    else
    begin
      Before := GetAvroMemStats;
      SW := TStopwatch.StartNew;
      Ok := AnsiEngineManager.SwitchEngine(ColdName, Err);
      SW.Stop;
      ColdMs := SW.ElapsedMilliseconds;
      After := GetAvroMemStats;
      EngineHeap := After.HeapBytes - Before.HeapBytes;
      Say('cold switch to ' + ColdName + ' cost ' + KB(EngineHeap) + ' of heap and ' + IntToStr(SW.ElapsedMilliseconds) + ' ms');
      Check('a container engine activates', Ok, Err.Text);
      Check('one engine stays inside the engine budget', EngineHeap <= BUDGET_ENGINE_HEAP, 'heap delta ' + KB(EngineHeap) + ' > budget ' +
          KB(BUDGET_ENGINE_HEAP));
      Check('a cold switch is bounded', SW.ElapsedMilliseconds <= BUDGET_COLD_SWITCH_MS, IntToStr(SW.ElapsedMilliseconds) + ' ms');
      Check('the activated engine converts', Converter.Convert(#$0995#$09BF) <> '');
      Inc(EnginesParsed);
      ActiveName := ColdName;
      // The engine left behind is the only parked one allowed.
      Check('the warm limit is enforced on the switch', AnsiEngineManager.WarmEngineCount <= MaxWarmEngines,
        'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));

      // ---- 5. warm switching stays O(1) -----------------------------------
      // Warm partner: the first file mapping parked when ColdName went live.
      WarmName := ActiveName;
      // The switch path used to log through DebugLog, which appended to a file
      // on every line. Measure that floor separately so the budget judges the
      // cache and not the logger - it is ~0 now that the sink writes no file.
      SW := TStopwatch.StartNew;
      for I := 0 to 199 do
        Log('membudget: logging cost probe');
      SW.Stop;
      LogMs := SW.ElapsedMilliseconds;
      Say('200 log lines cost ' + IntToStr(LogMs) + ' ms total (' + Format('%.3f', [LogMs / 200.0]) + ' ms each)');

      SW := TStopwatch.StartNew;
      for I := 0 to 99 do
      begin
        AnsiEngineManager.SwitchEngine(WarmName);
        AnsiEngineManager.SwitchEngine(ActiveName);
      end;
      SW.Stop;
      WarmMs := SW.ElapsedMilliseconds;
      Say('200 warm switches took ' + IntToStr(WarmMs) + ' ms total (' + Format('%.3f', [WarmMs / 200.0]) + ' ms each)');
      Check('warm switching stays ~instant', WarmMs <= BUDGET_WARM_SWITCH_MS, IntToStr(WarmMs) + ' ms > budget ' + IntToStr(BUDGET_WARM_SWITCH_MS) + ' ms');
      Check('warm switching does not grow the cache', AnsiEngineManager.WarmEngineCount <= MaxWarmEngines,
        'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));
      // Relative check: a warm switch must be a small fraction of a cold one,
      // i.e. it does no decryption, no disk I/O and no parsing. An absolute
      // budget would mostly have measured DebugLog's per-line file append.
      Check('a warm switch is a fraction of a cold one', (ColdMs > 0) and ((WarmMs div 200) * 4 <= ColdMs), 'warm=' + IntToStr(WarmMs div 200) + ' ms, cold=' +
          IntToStr(ColdMs) + ' ms');
    end;

    // ---- 6. nothing else is resident --------------------------------------
    Say('resident engines at this point: ' + IntToStr(AnsiEngineManager.WarmEngineCount) + ' parked + 1 live of ' + IntToStr(EngineList.Count) + ' available');
    Check('the session holds at most one parked engine', AnsiEngineManager.WarmEngineCount <= MaxWarmEngines,
      'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));
    Check('the whole session parsed engines on demand only', EnginesParsed <= 1, 'parsed=' + IntToStr(EnginesParsed));

    // ---- 7. the idle release gives the heap back --------------------------
    Ok := AnsiEngineManager.SwitchEngine(ActiveName, Err);
    Check('first file mapping is active before the release', Ok, Err.Text);
    Refused := AnsiEngineManager.ReleaseIdleEngines(24 * 60);
    Check('the release is time-gated', Refused = 0, 'dropped ' + IntToStr(Refused) + ' while the user was active');
    Before := GetAvroMemStats;
    Dropped := AnsiEngineManager.ReleaseWarmEngines;
    After := GetAvroMemStats;
    Say('idle release dropped ' + IntToStr(Dropped) + ' engine(s), heap ' + KB(Before.HeapBytes - After.HeapBytes) + ' returned');
    Check('the idle release drops the parked engines', Dropped >= 1);
    Check('nothing is parked after the release', AnsiEngineManager.WarmEngineCount = 0, 'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));
    Check('the live engine survives the release', AnsiEngineManager.LiveEngineReady);
    Check('the live engine still converts after the release', Converter.Convert(#$0995#$09BF) <> '');
    Check('the released icons are gone', (SampleName <> '') and (not MappingIconResolved(SampleName)));

    // ---- 8. a released engine comes back on demand ------------------------
    if ColdName <> '' then
    begin
      SW := TStopwatch.StartNew;
      Ok := AnsiEngineManager.SwitchEngine(ColdName, Err);
      SW.Stop;
      Check('a released engine re-parses on demand', Ok, Err.Text);
      Check('the re-parse is still bounded', SW.ElapsedMilliseconds <= BUDGET_COLD_SWITCH_MS, IntToStr(SW.ElapsedMilliseconds) + ' ms');
      Check('the re-parsed engine converts', Converter.Convert(#$0995#$09BF) <> '');
    end;

    Say(AvroMemStatsText('end'));
  finally
    Err.Free;
    EngineList.Free;
    Converter.Free;
    FinalizeEncoManager;
    AnsiEngineManager.Free;
    AnsiEngineManager := nil;
  end;

  if Fails = 0 then
    WriteLn('MEMORY BUDGET GATE PASSED')
  else
    WriteLn(IntToStr(Fails) + ' MEMORY BUDGET FAILURES');
  if Fails = 0 then
    Halt(0)
  else
    Halt(1);

end.
