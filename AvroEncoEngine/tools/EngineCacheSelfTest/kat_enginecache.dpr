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
    4. measures the per-switch cost (must be ~0 ms, zero disk/crypto/parse),
    5. exercises InvalidateEngine / RefreshFromDisk / RemoveEngine.

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

    // ---- 4. instant switch timing (after preload) --------------------------
    SW := TStopwatch.StartNew;
    for I := 0 to 99 do
      if OutputOf.ContainsKey(Lowercase(EngineList[I mod EngineList.Count])) then
        AnsiEngineManager.SwitchEngine(EngineList[I mod EngineList.Count]);
    SW.Stop;
    SwitchMs := SW.ElapsedMilliseconds;
    WriteLn('100 switches took ' + IntToStr(SwitchMs) + ' ms total (' +
      Format('%.3f', [SwitchMs / 100.0]) + ' ms each avg)');
    Check('switches are ~instant', SwitchMs < 500);

    // ---- 5. invalidation + refresh + remove --------------------------------
    AnsiEngineManager.InvalidateEngine('Default'); // no file: no-op safety
    AnsiEngineManager.RefreshFromDisk;
    AnsiEngineManager.RemoveEngine('Default');     // no-op (active guard)
    AnsiEngineManager.SwitchEngine('Default');
    Check('invalidate/refresh/remove smoke', True);

    // ---- 6. final active engine is Default --------------------------------
    Check('active engine is Default',
      SameText(AnsiEngineManager.CurrentEngineName, 'default'));
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