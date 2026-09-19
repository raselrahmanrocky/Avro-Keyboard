{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

program kat_enginecache;

{ End-to-end self-test for the in-memory ANSI engine cache
  (uAnsiEngineManager + CaptureEngineState/RestoreEngineState):

    1. preloads every default-key engine from a mapping directory,
    2. switches through all versions and checks that each engine's
       Unicode->ANSI conversion is stable (no state bleed between engines),
    3. verifies re-switching to an engine reproduces its exact output,
    4. checks the warm-vs-cold policy: a batch is committed as asked, the
       first switch enforces MaxWarmEngines (LRU), a switch between the live
       engine and the one it just parked stays ~0 ms (zero disk/crypto/parse),
       and a cold switch costs exactly one decrypt + parse,
    5. exercises InvalidateEngine / RefreshFromDisk / RemoveEngine,
    6. exercises the idle release: time-gated, drops the parked engines and
       the icon bytes, and leaves the LIVE engine (typing) intact.

  Usage: kat_enginecache <mapping-dir> [quiet]
  Exit code: 0 all PASS, 1 FAIL.
}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Generics.Collections,
  System.Diagnostics,
  clsUnicodeToBijoy2000,
  uAnsiEngineManager,
  uAvroEncoManager;

var
  Fails: Integer;

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

var
  MappingDir: string;
  Quiet: Boolean;
  Converter: TUnicodeToBijoy2000;
  EngineList: TStringList;
  OutputOf: TDictionary<string, string>;
  V: string;
  I: Integer;
  Out1, Out2: string;
  SW: TStopwatch;
  SwitchMs: Int64;
  Err: TStringList;
  PreloadItems: TArray<TPreloadItem>;
  PreloadThread: TAnsiPreloadThread;
  ActiveName, WarmName, ColdName: string;
  Ok: Boolean;
  Dropped, Refused, BatchWarm: Integer;

begin
  Fails := 0;
  Quiet := (ParamCount >= 2) and SameText(ParamStr(2), 'quiet');

  if ParamCount < 1 then
  begin
    WriteLn('Usage: kat_enginecache <mapping-dir> [quiet]');
    Halt(1);
  end;
  MappingDir := IncludeTrailingPathDelimiter(ParamStr(1));
  if not DirectoryExists(MappingDir) then
  begin
    WriteLn('FAIL mapping directory does not exist: ' + MappingDir);
    Halt(1);
  end;

  EngineList := TStringList.Create;
  OutputOf := TDictionary<string, string>.Create;
  Converter := TUnicodeToBijoy2000.Create;
  Err := TStringList.Create;
  try
    AnsiMappingDir := MappingDir;
    AnsiVersion := 'Default';

    InitializeEncoManager;
    ScanAvroEncoFiles(MappingDir);
    WriteLn('engines found on disk: ' + IntToStr(AvroEncoFiles.Count));

    // ---- 1. preload (HEAD API: snapshot + worker thread + commit) --------
    SW := TStopwatch.StartNew;
    PreloadItems := AnsiEngineManager.CapturePreloadList;
    WriteLn('preload items: ' + IntToStr(Length(PreloadItems)));
    PreloadThread := TAnsiPreloadThread.Create(PreloadItems);
    try
      PreloadThread.Start;
      PreloadThread.WaitFor;
      if PreloadThread.FatalException <> nil then
        Check('preload thread raised no exception', False,
          Exception(PreloadThread.FatalException).Message)
      else
        Check('preload thread raised no exception', True);
    finally
      PreloadThread.Free;
    end;
    SW.Stop;
    WriteLn('preload took ' + IntToStr(SW.ElapsedMilliseconds) + ' ms');
    Check('preload ran', True);
    // Recorded here, not where it is asserted: the batch is a cache FILL and
    // commits everything it snapshotted, so this is the only moment the warm
    // set is larger than the limit - the ordinary switches below trim it.
    BatchWarm := AnsiEngineManager.WarmEngineCount;
    WriteLn('the batch parked ' + IntToStr(BatchWarm) + ' engine(s)');

    // ---- 2. switch through every engine, capture output -------------------
    EngineList.Add('Default');
    if Assigned(AvroEncoFiles) then
      for V in AvroEncoFiles.Keys do
        EngineList.Add(AvroEncoFiles[V].DisplayName);

    for V in EngineList do
    begin
      if not AnsiEngineManager.SwitchEngine(V, Err) then
      begin
        Check('switch to ' + V, False, Err.Text);
        Continue;
      end;
      Out1 := Converter.Convert(#$0986#$09AE#$09BE#$09B0); // 'আমার'
      Out2 := Converter.Convert(#$0995#$09BF);              // 'কি'
      OutputOf.AddOrSetValue(Lowercase(V), Out1 + '|' + Out2);
      if not Quiet then
        WriteLn('engine ' + V + ' -> ANSI: ' + Out1 + ' / ' + Out2);
    end;
    Check('all engines switched', EngineList.Count > 0);

    // ---- 3. determinism: revisit every engine, output must be identical ----
    for V in EngineList do
    begin
      if not OutputOf.ContainsKey(Lowercase(V)) then
        Continue; // initial switch failed - already reported
      AnsiEngineManager.SwitchEngine(V);
      Out1 := Converter.Convert(#$0986#$09AE#$09BE#$09B0) + '|' +
              Converter.Convert(#$0995#$09BF);
      Check('deterministic ' + V,
        OutputOf[Lowercase(V)] = Out1,
        'expected ' + OutputOf[Lowercase(V)] + ' got ' + Out1);
    end;

    // ---- 4. warm-vs-cold policy -------------------------------------------
    // The batch above deliberately commits everything it snapshotted (a
    // preload batch is not trimmed), so the first ordinary switch is what has
    // to enforce the warm limit. This is the branch's whole memory contract:
    // only the live engine and MaxWarmEngines parked ones may stay resident.
    Check('the preload batch parked more than the live engine',
      BatchWarm >= 2,
      'the batch left ' + IntToStr(BatchWarm) + ' engine(s) parked');
    // ...and the switches in sections 2 and 3 - every one of them an ordinary
    // SwitchEngine, the path a menu click takes - have already trimmed it.
    Check('the ordinary switches trimmed the batch to the warm limit',
      AnsiEngineManager.WarmEngineCount <= MaxWarmEngines,
      'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount) +
      ' limit=' + IntToStr(MaxWarmEngines));

    // Track the active engine by DISPLAY name (CurrentEngineName reports the
    // lowercase slot key).
    ActiveName := '';
    for V in EngineList do
      if OutputOf.ContainsKey(Lowercase(V)) then
        ActiveName := V;

    if ActiveName = '' then
      Check('an active engine exists for the switch policy checks', False)
    else
    begin
      // Ping-pong with the engine the previous switch parked: with
      // MaxWarmEngines = 1 that is exactly the warm one, so not one of these
      // switches may touch the disk, the crypto stack or the parser.
      WarmName := '';
      for V in EngineList do
        if (not SameText(V, ActiveName)) and
          AnsiEngineManager.CachedEngineReady(V) then
        begin
          WarmName := V;
          Break;
        end;

      if WarmName = '' then
        Check('a parked engine is available for the warm-switch check', False)
      else
      begin
        SW := TStopwatch.StartNew;
        for I := 0 to 99 do
        begin
          AnsiEngineManager.SwitchEngine(WarmName);
          AnsiEngineManager.SwitchEngine(ActiveName);
        end;
        SW.Stop;
        SwitchMs := SW.ElapsedMilliseconds;
        WriteLn('200 warm switches took ' + IntToStr(SwitchMs) +
          ' ms total (' + Format('%.3f', [SwitchMs / 200.0]) + ' ms each avg)');
        // 200 warm switches must be nothing but pointer moves. The budget is
        // an absolute one and it is tight on purpose: DebugLog's per-line file
        // append used to measure ~8.5 ms, so a single trace line left on this
        // path would have spent 1700 ms here (which is how it was caught).
        // The sink writes no file any more, so that particular trip-wire is
        // gone and this budget now only judges the cache itself. A
        // parse, a decrypt or a disk read costs 17..60 ms per switch.
        Check('warm switches are ~instant', SwitchMs < 500,
          IntToStr(SwitchMs) + ' ms for 200 switches (' +
          Format('%.3f', [SwitchMs / 200.0]) + ' ms each)');

        // The LRU must have run on every one of those switches.
        Check('the warm limit is enforced by switching',
          AnsiEngineManager.WarmEngineCount <= MaxWarmEngines,
          'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount) +
          ' limit=' + IntToStr(MaxWarmEngines));
      end;

      // Cold path: one engine that no longer sits in RAM must still come back
      // correct, at the cost of exactly one decrypt + parse.
      ColdName := '';
      for V in EngineList do
        if (not SameText(V, ActiveName)) and (not SameText(V, WarmName)) and
          (not AnsiEngineManager.CachedEngineReady(V)) then
        begin
          ColdName := V;
          Break;
        end;

      if ColdName = '' then
        WriteLn('(no cold engine left to time)')
      else
      begin
        SW := TStopwatch.StartNew;
        Ok := AnsiEngineManager.SwitchEngine(ColdName, Err);
        SW.Stop;
        WriteLn('cold switch to ' + ColdName + ' took ' +
          IntToStr(SW.ElapsedMilliseconds) + ' ms (one decrypt + parse)');
        Check('a cold engine still switches', Ok, Err.Text);
        Check('a cold switch is bounded', SW.ElapsedMilliseconds < 3000);
        if OutputOf.ContainsKey(Lowercase(ColdName)) then
          Check('the cold-parsed engine renders identically',
            OutputOf[Lowercase(ColdName)] = Converter.Convert(#$0986#$09AE#$09BE#$09B0)
              + '|' + Converter.Convert(#$0995#$09BF));
      end;
    end;

    // ---- 5. invalidation + refresh + remove --------------------------------
    AnsiEngineManager.InvalidateEngine('Default'); // no file: no-op safety
    AnsiEngineManager.RefreshFromDisk;
    AnsiEngineManager.RemoveEngine('Default');     // no-op (active guard)
    AnsiEngineManager.SwitchEngine('Default');
    Check('invalidate/refresh/remove smoke', True);

    // ---- 6. final active engine is Default --------------------------------
    Check('active engine is Default',
      SameText(AnsiEngineManager.CurrentEngineName, 'default'));

    // ---- 7. idle release --------------------------------------------------
    // Time-gated: a day of "idle" is never reached, so nothing may be dropped.
    Refused := AnsiEngineManager.ReleaseIdleEngines(24 * 60);
    Check('idle release is time-gated', Refused = 0,
      'dropped ' + IntToStr(Refused) + ' engine(s) while the user was active');
    Check('the time-gated release left the cache alone',
      AnsiEngineManager.WarmEngineCount >= 1,
      'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));

    // The unconditional core is what the idle timer reaches, and what this
    // check exercises deterministically (the real GetSystemIdleSeconds cannot
    // be driven from a gate).
    Dropped := AnsiEngineManager.ReleaseWarmEngines;
    WriteLn('idle release dropped ' + IntToStr(Dropped) + ' parked engine(s)');
    Check('the idle release drops the parked engines', Dropped >= 1);
    Check('nothing is parked after the release',
      AnsiEngineManager.WarmEngineCount = 0,
      'warm=' + IntToStr(AnsiEngineManager.WarmEngineCount));
    // The release must never take the engine typing depends on.
    Check('the live engine survived the release',
      AnsiEngineManager.LiveEngineReady);
    Check('the live engine still converts after the release',
      Converter.Convert(#$0995#$09BF) <> '');
    // And the released engine comes back on demand, not as a failure.
    Ok := AnsiEngineManager.SwitchEngine('Default', Err);
    Check('a released engine switches back on demand', Ok, Err.Text);
  finally
    Err.Free;
    Converter.Free;
    OutputOf.Free;
    EngineList.Free;
    FinalizeEncoManager;
    AnsiEngineManager.Free; // standalone harness: release the singleton
    AnsiEngineManager := nil;
  end;

  if Fails = 0 then
    WriteLn('ALL ENGINE CACHE KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT FAILURES');
  if Fails = 0 then
    Halt(0)
  else
    Halt(1);
end.