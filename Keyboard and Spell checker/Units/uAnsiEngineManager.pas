{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAnsiEngineManager;

{ =============================================================================
  uAnsiEngineManager - in-memory ANSI engine cache (instant version switch).

  The ANSI parser in clsUnicodeToBijoy2000 keeps its mapping state in unit
  globals. This manager pre-parses every FILE mapping that can unlock without
  user interaction (default-key .AvroEnco containers, plain .json mappings,
  and password-protected containers whose password was already cached on this
  computer) - once, during application initialization, on a BACKGROUND thread
  while the splash screen is still visible - and parks each engine's complete
  state in a TAnsiEngineState record (CaptureEngineState). There is no
  compiled-in version: a name only becomes an engine when its file parses.

  Switching versions is then O(1): the previously active state is parked back
  and the target state is restored with plain pointer moves
  (RestoreEngineState). Zero disk I/O, zero decryption and zero parsing
  happens during the menu click for any cached engine.

  Threading model: all engine-state mutation (parse/capture/restore/drop)
  happens under FLock, so the startup preload thread can never interleave
  with a main-thread switch, the directory watcher or an import. The
  decryption phase of the preload runs in parallel worker threads; only
  the cheap parse + capture phase takes the lock. (Shield v2 decryption
  is millisecond-level; no slow KDF remains in the project.)

  Ownership invariant (every path in this unit depends on it): either the unit
  globals own the ACTIVE engine's containers - FCurrentKey names its slot and
  that slot is empty - or the globals are empty and every engine sits in its
  slot. A parse must therefore never run on top of a live engine:
  LoadAnsiMappingFromJSON starts with ResetAnsiToDefaults, which frees the
  globals' containers, so parsing while an engine is active used to destroy
  the running engine and leave its slot hollow (an engine with no registry and
  no rule tables: the version looked selected while every kar emitted nothing
  and consonants fell back to the compiled-in default glyph scheme).
  ParkLive enforces the invariant before every parse, EnsureLiveEngine repairs
  an empty global state from a parked file slot or from disk (never from a
  compiled-in Default engine), and a hollow slot is treated as a cache MISS
  (rebuilt from its file) instead of being served.

  Memory: every parked state owns its containers; the manager frees them in
  Destroy (initialization/finalization of this unit), so FastMM reports no
  leaks on application shutdown.
  ============================================================================= }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.SyncObjs,
  clsUnicodeToBijoy2000,
  uAvroEncoIconSection;

const
  { Parked (non-active) engines allowed to stay in RAM beside the live one.

    1 keeps exactly the layout you just left - switchable in O(1) and parses
    everything else on first switch instead of preloading it.
    That is the whole idle-footprint fix: the live engine is the only one
    typing ever reads, so nothing else needs to be resident. Raise it to trade
    RAM back for instant switching between more layouts.

    Declared before the class because EvictToLimit uses it as a default
    argument value. }
  MaxWarmEngines = 1;

type
  { One cached engine: the parked parser state plus the file it was parsed
    from and its last write time (used to detect external file changes so the
    directory watcher can re-parse just that engine).

    LastUseStamp is a per-process sequence number assigned whenever this slot
    is parked or restored, and it drives LRU eviction: a parked engine can be
    dropped when the warm set is over its limit or when the app has gone idle -
    the whole point of not keeping every mapping resident.

    A monotonic counter, NOT GetTickCount: a cold preload parses several engines
    inside one 15.6 ms clock granule, so tick-based ordering ties constantly and
    a tie made the victim depend on dictionary iteration order - a preload that
    had just filled the cache could evict the engine the user had literally just
    switched away from. Stamps are unique, so the least recently USED engine is
    always the one dropped. }
  TEngineSlot = class
    public
      DisplayName:   string;
      FilePath:      string;
      LastWriteTime: TDateTime;
      LastUseStamp:  Cardinal;
      State:         TAnsiEngineState;
      destructor Destroy; override;
  end;

  { One engine to preload at startup. Password is non-empty only for
    password-protected containers that were already unlocked on this
    computer (persisted per-file password cache) - those decrypt silently
    with the cached password, never prompting. }
  TPreloadItem = record
    DisplayName: string;
    FilePath: string;
    Password: AnsiString;
  end;

  { Decrypted/read JSON for one preload item, produced off the UI thread.
    ErrorMsg carries the decrypt failure reason (exception text) so a cold-
    start miss - e.g. Ansi V3 after a full %AppData% cache wipe - is
    diagnosable instead of a bare "decryption" line. }
  TPreloadResult = record
    DisplayName: string;
    FilePath: string;
    JSON: string;
    OK: Boolean;
    ErrorMsg: string;
  end;

  TAnsiEngineManager = class
    private
      FCache:      TDictionary<string, TEngineSlot>; // key: Lowercase(DisplayName)
      FCurrentKey: string;
      FLock:       TCriticalSection; // serializes every engine-state mutation
      { Last value handed out by NextUseStamp; see TEngineSlot.LastUseStamp. }
      FUseStamp: Cardinal;
      { Hands out the next unique LRU stamp. Caller must hold FLock (every caller
        is already inside it). }
      function NextUseStamp: Cardinal;
      function SlotKey(const AName: string): string;
      { True while the unit globals actually hold a parsed engine. Invariant the
        whole cache rests on: either the globals own the active engine's
        containers (FCurrentKey names its slot, which is empty), or the globals
        are empty and every engine sits in its slot. Every parse runs with empty
        globals so it can never destroy the engine that is currently live. }
      function GlobalsHoldEngine: Boolean;
      { Moves the live engine's containers back into its own slot, leaving the
        globals empty (the precondition of every parse). Never hollows a slot:
        with empty globals this is a no-op. Returns True when it parked
        something. Caller must hold FLock. }
      function ParkLive: Boolean;
      { Restores AKey's parked state into the globals. False for a missing or
        hollow slot - the caller then treats it as a cache MISS instead of
        serving an engine that cannot render. Publishes no version name. }
      function RestoreSlotState(const AKey: string): Boolean;
      { RestoreSlotState + publishes AName as the active display name; False when
        the slot is hollow. }
      function TryRestoreSlot(const AKey, AName: string): Boolean;
      { True when AName's parked state is missing or hollow. }
      function IsSlotHollow(const AKey: string): Boolean;
      { Fail-closed safety net: when the globals hold no engine, restore the
        active or last-used parked FILE slot, else parse one file mapping from
        disk. Never builds a compiled-in engine and never changes AnsiVersion -
        callers that genuinely switch publish the name themselves. With zero
        usable files it only logs and leaves the globals empty (Unicode still
        works). }
      procedure EnsureLiveEngine;
      { Puts a live engine the caller just parked by hand back in place after a
        failed parse. }
      procedure RestoreParkedEngine(const AParked: Boolean);
      { Parses AJSON into the globals and parks the result in a new slot added
        to FCache. AFilePath is stored on the slot for the directory watcher.
        Password-protected containers are decrypted by the CALLER (version
        picker / menu / preload thread) before this is reached, so this never
        prompts. Returns False (and fills ErrorLog) when the JSON contains no
        usable mapping rules. Caller must hold FLock. }
      function ParseJSONIntoSlot(const AName, AFilePath, AJSON: string; ErrorLog: TStringList = nil): Boolean;
      { Decrypts AFilePath (Shield/legacy container with APassword, or reads
        plain .json) and parks the parsed result. AFilePath must be a real
        file path - empty is not an engine and returns False. Caller must
        hold FLock. }
      function ParseIntoSlot(const AName, AFilePath: string; ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
      { Moves the currently active engine's globals back into its parked slot.
        Caller must hold FLock. }
      procedure ParkCurrent;
      { Frees and removes a NON-ACTIVE cached engine. Caller must hold FLock. }
      procedure DropSlot(const AKey: string);
      { Lock-free core of InvalidateEngine. Caller must hold FLock. }
      procedure DoInvalidateEngine(const AName: string);
      { Stamps AKey's slot as used now. Every park/restore path calls this, so LRU
        eviction reflects what the user actually switched between. }
      procedure TouchSlot(const AKey: string);
    public
      constructor Create;
      destructor Destroy; override;
      property CurrentEngineName: string read FCurrentKey;
      { True while the active engine is really usable - the UI/tests can use this
        instead of trusting CurrentEngineName alone. }
      function LiveEngineReady: Boolean;
      { True when AName's parked engine is complete (cached and not hollow). }
      function CachedEngineReady(const AName: string): Boolean;
      { Snapshots the file mappings that can unlock without user interaction
        (default-key containers, plain .json mappings and password-protected
        containers with a persisted password). Call on the main thread BEFORE
        starting the preload thread: the snapshot decouples the worker from
        the AvroEncoFiles dictionary, which the folder-change timers clear/
        refill while the worker runs. }
      function CapturePreloadList: TArray<TPreloadItem>;
      { Same snapshot, narrowed to ONE mapping: zero items when it is already
        cached, is not a known file, or is a password container that was never
        unlocked. This is what an explicit single-layout action (unlock in the
        picker, import) warms before the user clicks it - warming the whole
        folder for one unlock is the eager behaviour the cache no longer does. }
      function CapturePreloadItem(const AName: string): TArray<TPreloadItem>;
      { Parses every decrypted snapshot result into the cache. Runs on the
        preload thread; takes FLock, so it can never interleave with a
        main-thread switch. Returns the number of engines committed.

        The warm limit is NOT applied here: a batch commits exactly what it was
        asked for, and the LRU release is what keeps the ordinary session
        bounded (the app no longer batches at startup - the version picker
        commits the ONE engine a password unlock just made available, and
        CapturePreloadItem is what it snapshots with). The next switch or the
        idle release then trims whatever is left over. }
      function CommitPreload(const AResults: TArray<TPreloadResult>): Integer;
      { Makes AName the active engine. For cached engines this is O(1) pointer
        moves with zero disk/crypto/parse work. Uncached engines (password
        protected, never unlocked before) are parsed once here. Returns False
        on failure - the previously active engine stays untouched. }
      function SwitchEngine(const AName: string; ErrorLog: TStringList = nil): Boolean;
      { UI-safe fast path. Never reads/decrypts/parses files and never waits for
        the preload/refresh lock. Returns False immediately if busy/not cached. }
      function TrySwitchCached(const AName: string): Boolean;
      procedure WarmAllEngines(const AReturnTo: string);
      { Re-parses one cached engine from its file (directory watcher /
        auto-refresh on file change / import). If the engine is active it is
        re-activated in place; on re-parse failure EnsureLiveEngine repairs
        from another file mapping or leaves Unicode-only mode. }
      procedure InvalidateEngine(const AName: string);
      { Reconciles the cache with the file system: drops engines whose files
        disappeared (never the active one), re-parses default-key engines whose
        last write time changed, and preloads newly added ones. }
      procedure RefreshFromDisk;
      { Removes a non-active engine from the cache (mapping deleted by user). }
      procedure RemoveEngine(const AName: string);
      { Parked engines currently held in RAM (the live one does not count). }
      function WarmEngineCount: Integer;
      { Drops least-recently-used parked engines until at most ALimit remain.
        Never touches the live engine (its slot is empty by design, so it cannot
        be a candidate anyway). Returns how many were dropped. }
      function EvictToLimit(ALimit: Integer = MaxWarmEngines): Integer;
      { Drops every parked engine and clears the per-mapping icon cache, then
        returns the working set to the OS. Unconditional core of
        ReleaseIdleEngines, exposed separately so the memory gate can exercise it
        without waiting for the real system to go idle. The LIVE engine is
        untouched: typing keeps working, and only a later version switch pays for
        a fresh parse. Returns the number of engines dropped. }
      function ReleaseWarmEngines: Integer;
      { Idle wrapper around ReleaseWarmEngines: does nothing until the user has
        been idle (system-wide, see uAvroEngineStats.GetSystemIdleSeconds) for at
        least AMinIdleMinutes. Returns 0 when it declined to release. }
      function ReleaseIdleEngines(AMinIdleMinutes: Integer): Integer;
  end;

  { Startup preload worker. Decrypts every snapshot item in parallel and
    then commits the parsed engines through
    TAnsiEngineManager.CommitPreload. The
    splash screen keeps painting while this thread runs; nothing here touches
    the UI. }
  TAnsiPreloadThread = class(TThread)
    private
      FItems:      TArray<TPreloadItem>;
      FResults:    TArray<TPreloadResult>;
      FNextJob:    Integer;
      FResultLock: TCriticalSection;
      procedure DecryptItem(Index: Integer);
      procedure ParallelDecrypt;
    protected
      procedure Execute; override;
    public
      constructor Create(const AItems: TArray<TPreloadItem>);
      destructor Destroy; override;
  end;

var
  AnsiEngineManager: TAnsiEngineManager;

implementation

uses
  Winapi.Windows,
  uAvroEncoManager,
  uAvroEncoCrypto,
  uAnsiPersistentCache,
  uRegistrySettings,
  uAvroEngineStats,
  System.IOUtils,
  System.Math,
  DebugLog;

destructor TEngineSlot.Destroy;
begin
  State.Clear; // free every parked container
  inherited Destroy;
end;

constructor TAnsiEngineManager.Create;
begin
  inherited Create;
  FCache := TDictionary<string, TEngineSlot>.Create;
  FLock := TCriticalSection.Create;
  FCurrentKey := '';
  FUseStamp := 0;
end;

destructor TAnsiEngineManager.Destroy;
var
  Slot: TEngineSlot;
begin
  FLock.Enter;
  try
    for Slot in FCache.Values do
      Slot.Free;
    FCache.Free;
    FCache := nil;
  finally
    FLock.Leave;
  end;
  FLock.Free;
  inherited Destroy;
end;

function TAnsiEngineManager.SlotKey(const AName: string): string;
begin
  Result := Lowercase(Trim(AName));
end;

{ Stamps a slot as used now. Every park/restore path calls this, so LRU
  eviction reflects what the user actually switched between - not the order the
  cache happened to be filled in. }
procedure TAnsiEngineManager.TouchSlot(const AKey: string);
var
  Slot: TEngineSlot;
begin
  if FCache.TryGetValue(AKey, Slot) then
    Slot.LastUseStamp := NextUseStamp;
end;

function TAnsiEngineManager.NextUseStamp: Cardinal;
begin
  Inc(FUseStamp);
  Result := FUseStamp;
end;

function TAnsiEngineManager.WarmEngineCount: Integer;
var
  Key: string;
begin
  // A slot holds a PARKED engine only while that engine is not the live one:
  // when it is live, its own slot is explicitly empty (the globals own the
  // containers). Hollow slots therefore cost no engine RAM and are not counted.
  Result := 0;
  for Key in FCache.Keys do
    if not IsSlotHollow(Key) then
      Inc(Result);
end;

function TAnsiEngineManager.EvictToLimit(ALimit: Integer): Integer;
var
  Key, Victim: string;
  Oldest:      Cardinal;
  Slot:        TEngineSlot;
begin
  Result := 0;
  if ALimit < 0 then
    ALimit := 0;
  while WarmEngineCount > ALimit do
  begin
    Victim := '';
    Oldest := high(Cardinal);
    for Key in FCache.Keys do
    begin
      if IsSlotHollow(Key) then
        Continue; // nothing to free
      if Key = FCurrentKey then
        Continue; // never the live engine's name
      Slot := FCache[Key];
      if Slot.LastUseStamp <= Oldest then
      begin
        Oldest := Slot.LastUseStamp;
        Victim := Key;
      end;
    end;
    if Victim = '' then
      Exit; // nothing evictable (only the live engine is resident)
    DropSlot(Victim);
    Inc(Result);
    Log('Engine cache: evicted "' + Victim + '" (warm limit ' + IntToStr(ALimit) + ')');
  end;
end;

function TAnsiEngineManager.ReleaseWarmEngines: Integer;
begin
  FLock.Enter;
  try
    Result := EvictToLimit(0);
  finally
    FLock.Leave;
  end;

  // The icon bytes live INSIDE the mapping payloads, so keeping them is
  // keeping a copy of every decrypted layout icon alive forever. They are
  // regenerable: the next menu build (or the next version switch, for the
  // active layout) resolves them again.
  ClearMappingIcons;
  TrimProcessWorkingSet;
  LogAvroMemStats('idle release (engines dropped: ' + IntToStr(Result) + ')');
end;

function TAnsiEngineManager.ReleaseIdleEngines(AMinIdleMinutes: Integer): Integer;
begin
  if AMinIdleMinutes <= 0 then
    Exit(0);
  // Idle means the USER is idle system-wide, not that this process did
  // nothing: a keyboard utility that trims while the user types in another
  // window would only buy itself the page faults back on the next keystroke.
  if Integer(GetSystemIdleSeconds) < AMinIdleMinutes * 60 then
    Exit(0);
  Result := ReleaseWarmEngines;
end;

function TAnsiEngineManager.GlobalsHoldEngine: Boolean;
begin
  Result := (AnsiRegistry <> nil) and (AnsiRegistry.Count > 0);
end;

function TAnsiEngineManager.LiveEngineReady: Boolean;
begin
  Result := GlobalsHoldEngine;
end;

function TAnsiEngineManager.IsSlotHollow(const AKey: string): Boolean;
var
  Slot: TEngineSlot;
begin
  Result := True; // missing counts as unusable
  if FCache.TryGetValue(AKey, Slot) then
    Result := IsEngineStateHollow(Slot.State);
end;

function TAnsiEngineManager.CachedEngineReady(const AName: string): Boolean;
begin
  Result := not IsSlotHollow(SlotKey(AName));
end;

function TAnsiEngineManager.ParkLive: Boolean;
var
  Slot:   TEngineSlot;
  Orphan: TAnsiEngineState; // owns, then discards, a live engine no slot claims
begin
  Result := False;
  if not GlobalsHoldEngine then
    Exit;

  // A scratch state must be zeroed explicitly: TAnsiEngineState holds class
  // references, which are not managed types and would otherwise be garbage.
  InitEngineState(Orphan);

  if (FCurrentKey <> '') and FCache.TryGetValue(FCurrentKey, Slot) then
  begin
    CaptureEngineState(Slot.State); // globals -> slot; globals become empty
    Slot.LastUseStamp := NextUseStamp;
    Result := True;
    Exit;
  end;

  // Live globals that no slot owns: the engine the active-mapping refresh
  // parsed before CommitPreload ran, or a slot dropped underneath the active
  // engine. Ownership must not leak into the next parse, so take it over and
  // discard it - the owning slot is rebuilt from its file on demand.
  CaptureEngineState(Orphan);
  Orphan.Clear;
  Log('Engine state: discarded un-owned live engine (active slot "' + FCurrentKey + '")');
  Result := True;
end;

function TAnsiEngineManager.RestoreSlotState(const AKey: string): Boolean;
var
  Slot: TEngineSlot;
begin
  Result := False;
  if not FCache.TryGetValue(AKey, Slot) then
    Exit;
  if IsEngineStateHollow(Slot.State) then
    Exit;
  RestoreEngineState(Slot.State);
  FCurrentKey := AKey;
  Slot.LastUseStamp := NextUseStamp;
  Result := True;
end;

function TAnsiEngineManager.TryRestoreSlot(const AKey, AName: string): Boolean;
begin
  Result := RestoreSlotState(AKey);
  if not Result then
    Exit;
  if AName <> '' then
    AnsiVersion := AName;
end;

procedure TAnsiEngineManager.RestoreParkedEngine(const AParked: Boolean);
begin
  if not AParked then
    Exit;
  if (FCurrentKey = '') or (not RestoreSlotState(FCurrentKey)) then
    Exit;
  Log('Engine state: parse failed - kept active engine "' + FCurrentKey + '"');
end;

procedure TAnsiEngineManager.EnsureLiveEngine;
var
  PrevKey, BestKey, FallbackName, Path: string;
  BestStamp: Cardinal;
  Key: string;
  Slot: TEngineSlot;
begin
  if GlobalsHoldEngine then
    Exit;

  PrevKey := FCurrentKey;
  if (PrevKey <> '') and RestoreSlotState(PrevKey) then
  begin
    Log('Engine state repaired: restored active engine "' + PrevKey + '"');
    Exit;
  end;

  // Restore any non-hollow parked FILE slot, preferring the last-used stamp
  // so the layout the user just left comes back first.
  BestKey := '';
  BestStamp := 0;
  for Key in FCache.Keys do
  begin
    if IsSlotHollow(Key) then
      Continue;
    Slot := FCache[Key];
    if (BestKey = '') or (Slot.LastUseStamp > BestStamp) then
    begin
      BestKey := Key;
      BestStamp := Slot.LastUseStamp;
    end;
  end;
  if (BestKey <> '') and RestoreSlotState(BestKey) then
  begin
    Log('Engine state repaired: restored parked engine "' + BestKey + '"');
    Exit;
  end;

  // Nothing parked: parse ONE file mapping from disk (natural-sort first
  // usable name). Never a compiled-in Default - with zero files the app stays
  // on Unicode output.
  FallbackName := FirstAvailableMappingName;
  if FallbackName <> '' then
  begin
    Path := GetActiveEncoFilePath(FallbackName, AnsiMappingDir);
    if (Path <> '') and ParseIntoSlot(FallbackName, Path, nil) and RestoreSlotState(SlotKey(FallbackName)) then
    begin
      Log('Engine state repaired: parsed file mapping "' + FallbackName + '"');
      Exit;
    end;
  end;

  Log('WARNING: no usable ANSI engine available');
end;

function TAnsiEngineManager.ParseJSONIntoSlot(const AName, AFilePath, AJSON: string; ErrorLog: TStringList = nil): Boolean;
var
  JSON:       string;
  Slot:       TEngineSlot;
  LiveParked: Boolean;
begin
  Result := False;
  JSON := AJSON;

  // LoadAnsiMappingFromJSON starts with ResetAnsiToDefaults, which frees the
  // globals' containers. While an engine is ACTIVE those containers belong to
  // it (its slot is empty), so parsing on top of it would destroy the running
  // engine and leave a hollow slot behind. Park it first; every failure path
  // below puts it back, so a failed load never costs the app its engine.
  LiveParked := ParkLive;

  // Strip a leading UTF-8 BOM if one survived.
  if (Length(JSON) >= 3) and (JSON[1] = #$EF) and (JSON[2] = #$BB) and (JSON[3] = #$BF) then
    Delete(JSON, 1, 3);
  if Trim(JSON) = '' then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: Mapping file is empty: ' + AName);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;

  try
    LoadAnsiMappingFromJSON(JSON, ErrorLog);
  except
    on E: Exception do
    begin
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: Mapping parse exception: ' + E.Message);
      RestoreParkedEngine(LiveParked);
      Exit;
    end;
  end;

  // The JSON parser is lenient (unknown sections are silently skipped), so
  // verify a real engine was produced: the registry must exist and at least
  // one mapping section (or an override) must have been loaded.
  if (AnsiRegistry = nil) or (AnsiRegistry.Count = 0) then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: mapping parse produced no engine for ' + AName);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;
  if (Length(CustomFullForms) = 0) and (Length(CustomPreReplacements) = 0) and (Length(CustomPostReplacements) = 0) and (Length(VowelRules) = 0) and
    (Length(RfolaRules) = 0) and (Length(KarCorrections) = 0) and (Length(GroupKarCorrections) = 0) and ((AnsiOverrides = nil) or (AnsiOverrides.Count = 0))
  then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: mapping contains no usable rules for ' + AName);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;

  Slot := TEngineSlot.Create;
  Slot.DisplayName := AName;
  Slot.FilePath := AFilePath;
  Slot.LastWriteTime := 0;
  Slot.LastUseStamp := NextUseStamp;
  if AFilePath <> '' then
    try
      Slot.LastWriteTime := TFile.GetLastWriteTime(AFilePath);
    except
      Slot.LastWriteTime := 0;
    end;
  CaptureEngineState(Slot.State);
  // CaptureEngineState stamps the CURRENT AnsiVersion, which is the name of the
  // engine we just parked (or the one still being requested). The parsed file's
  // own name is authoritative for the slot and for every later restore.
  Slot.State.DisplayName := AName;
  // Never replace a slot that still owns containers: dropping first keeps the
  // one-owner rule (a blind AddOrSetValue would leak the old engine).
  if FCache.ContainsKey(SlotKey(AName)) then
    DropSlot(SlotKey(AName));
  FCache.Add(SlotKey(AName), Slot);

  // The per-layout icon a container carries rides inside the payload, so it is
  // refreshed here - the one place every parse path goes through: the startup
  // preload, the directory watcher's re-parse, an on-demand switch and an
  // import. The cached icon therefore stays in step with the file exactly like
  // the engine's own rules do, and a legacy container simply clears its entry.
  StoreMappingIcon(AName, ExtractIconSection(JSON));

  Result := True;
end;

function TAnsiEngineManager.ParseIntoSlot(const AName, AFilePath: string; ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
var
  JSON:        string;
  UsePassword: AnsiString;
begin
  Result := False;

  // Empty path is not an engine: every successful parse goes through a real
  // .json / .AvroEnco file (the compiled glyph canvas is only the scratch
  // surface LoadAnsiMappingFromJSON resets onto before overlaying that file).
  if AFilePath = '' then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: Mapping file path is empty for ' + AName);
    Exit;
  end;

  if IsEncoFile(AFilePath) then
  begin
    // Default-key containers decrypt transparently (password ignored);
    // password containers decrypt with the caller-supplied password or, on
    // the on-demand path, with the session-wide CachedEncoPassword global,
    // which the caller (version picker / menu) sets BEFORE switching. This
    // never prompts.
    UsePassword := APassword;
    if UsePassword = '' then
      UsePassword := CachedEncoPassword;
    if not LoadAnsiJSONCached(AFilePath, UsePassword, JSON) then
      JSON := '';
    if (JSON = '') or (JSON[1] <> '{') then
    begin
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: Decryption failed for ' + AName);
      Exit;
    end;
  end
  else
  begin
    if not FileExists(AFilePath) then
    begin
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: JSON file not found at: ' + AFilePath);
      Exit;
    end;
    try
      if not LoadAnsiJSONCached(AFilePath, '', JSON) then
        JSON := '';
    except
      on E: Exception do
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Error: Cannot read mapping file: ' + E.Message);
        Exit;
      end;
    end;
  end;

  Result := ParseJSONIntoSlot(AName, AFilePath, JSON, ErrorLog);
end;

procedure TAnsiEngineManager.ParkCurrent;
begin
  // Guarded on purpose: capturing EMPTY globals into a slot would wipe a good
  // parked engine (exactly how a valid slot used to become hollow).
  ParkLive;
end;

procedure TAnsiEngineManager.DropSlot(const AKey: string);
var
  Slot: TEngineSlot;
begin
  if FCache.TryGetValue(AKey, Slot) then
  begin
    FCache.Remove(AKey);
    Slot.Free; // State.Clear inside
  end;
end;

function TAnsiEngineManager.CapturePreloadList: TArray<TPreloadItem>;
var
  Info:  TAvroEncoFileInfo;
  Items: TList<TPreloadItem>;
  Item:  TPreloadItem;
  Flag:  Byte;
begin
  Items := TList<TPreloadItem>.Create;
  try
    FLock.Enter;
    try
      if Assigned(AvroEncoFiles) then
        for Info in AvroEncoFiles.Values do
        begin
          if FCache.ContainsKey(SlotKey(Info.DisplayName)) then
            Continue;
          Item.DisplayName := Info.DisplayName;
          Item.FilePath := Info.FilePath;
          Item.Password := '';
          if Info.IsEncoFile then
          begin
            Flag := GetAvroEncoProtectionFlag(Info.FilePath);
            if Flag = AVROENCO_FLAG_USER_PASSWORD then
            begin
              // Only preload password containers that were already unlocked
              // on this computer - the persisted password decrypts silently.
              Item.Password := GetEncoCachedPassword(Info.FilePath);
              if Item.Password = '' then
                Continue; // never unlocked: stays lazy (first switch prompts)
            end;
          end;
          Items.Add(Item);
        end;
    finally
      FLock.Leave;
    end;
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function TAnsiEngineManager.CapturePreloadItem(const AName: string): TArray<TPreloadItem>;
var
  Info: TAvroEncoFileInfo;
  Item: TPreloadItem;
  Flag: Byte;
begin
  SetLength(Result, 0);
  if AName = '' then
    Exit;

  FLock.Enter;
  try
    if FCache.ContainsKey(SlotKey(AName)) then
      Exit; // already cached: nothing to warm
    if (not Assigned(AvroEncoFiles)) or (not AvroEncoFiles.TryGetValue(SlotKey(AName), Info)) then
      Exit; // not a mapping this process knows about
  finally
    FLock.Leave;
  end;

  Item.DisplayName := Info.DisplayName;
  Item.FilePath := Info.FilePath;
  Item.Password := '';
  if Info.IsEncoFile then
  begin
    Flag := GetAvroEncoProtectionFlag(Info.FilePath);
    if Flag = AVROENCO_FLAG_USER_PASSWORD then
    begin
      Item.Password := GetEncoCachedPassword(Info.FilePath);
      if Item.Password = '' then
        Exit; // never unlocked on this computer: stays lazy until it is
    end;
  end;

  SetLength(Result, 1);
  Result[0] := Item;
end;

function TAnsiEngineManager.CommitPreload(const AResults: TArray<TPreloadResult>): Integer;
var
  R:   TPreloadResult;
  Err: TStringList;
begin
  Result := 0;
  FLock.Enter;
  try
    Err := TStringList.Create;
    try
      // Every decrypted snapshot engine. Each parse parks the engine that
      // is live (mid-session preload) and leaves it parked on success, so
      // EnsureLiveEngine puts it back once the batch is done.
      for R in AResults do
      begin
        if not R.OK then
        begin
          if R.ErrorMsg <> '' then
            Log('Engine preload failed: ' + R.DisplayName + ' - ' + R.ErrorMsg)
          else
            Log('Engine preload failed: ' + R.DisplayName + ' - decryption');
          Continue;
        end;
        if FCache.ContainsKey(SlotKey(R.DisplayName)) then
          Continue;
        Err.Clear;
        if ParseJSONIntoSlot(R.DisplayName, R.FilePath, R.JSON, Err) then
        begin
          Inc(Result);
          Log('Engine preloaded: ' + R.DisplayName);
        end
        else
          Log('Engine preload failed: ' + R.DisplayName + ' - ' + Err.Text);
      end;
      EnsureLiveEngine;
    finally
      Err.Free;
    end;
  finally
    FLock.Leave;
  end;
  LogAvroMemStats('preload commit (' + IntToStr(Result) + ' engine(s))');
end;

function TAnsiEngineManager.SwitchEngine(const AName: string; ErrorLog: TStringList = nil): Boolean;
var
  Key, Path, PrevKey: string;
  OwnErr:             Boolean;
begin
  Result := False;
  Key := SlotKey(AName);
  if Key = '' then
    Exit;

  OwnErr := not Assigned(ErrorLog);
  if OwnErr then
    ErrorLog := TStringList.Create;
  FLock.Enter;
  try
    PrevKey := FCurrentKey;

    // Idempotent: already active AND the globals really hold its state. The
    // ContainsKey check alone used to be a lie: when something had parsed over
    // the live engine the slot stayed in place but empty, so every later click
    // on the same version returned True while typing stayed broken.
    if (Key = FCurrentKey) and FCache.ContainsKey(Key) then
    begin
      if GlobalsHoldEngine then
        Exit(True);
      if RestoreSlotState(Key) then
      begin
        AnsiVersion := AName;
        Log('Engine switch: repaired active engine "' + AName + '"');
        Exit(True);
      end;
      DropSlot(Key); // hollow: rebuild it from disk below
      Log('Engine switch: hollow state for "' + AName + '" - re-parsing from disk');
    end;

    // Load on demand (password-protected engine, file added at runtime, or the
    // hollow-repair case above). ParseIntoSlot parks the live engine first and
    // puts it back when the parse fails, so the active engine survives either
    // way (fail-closed). Empty path is never an engine - no compiled Default.
    if (not FCache.ContainsKey(Key)) or IsSlotHollow(Key) then
    begin
      Path := GetActiveEncoFilePath(AName, AnsiMappingDir);
      if Path = '' then
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Mapping file not found: ' + AName);
        EnsureLiveEngine;
        Exit;
      end;
      DropSlot(Key);
      if not ParseIntoSlot(AName, Path, ErrorLog) then
      begin
        EnsureLiveEngine;
        Exit;
      end;
    end;

    // O(1) engine swap: park current (a no-op right after a parse, which
    // already parked it), then restore the target - never a hollow state.
    ParkCurrent;
    if not TryRestoreSlot(Key, AName) then
    begin
      Log('Engine switch failed: "' + AName + '" state is hollow');
      EnsureLiveEngine;
      Exit;
    end;
    Result := True;
    // The engine just left is parked; anything beyond the warm limit is RAM
    // this app has no use for (typing only ever reads the live one).
    EvictToLimit;
  finally
    FLock.Leave;
    if OwnErr then
      ErrorLog.Free;
  end;
  // NOTHING is logged on a successful switch, here or in TrySwitchCached.
  // DebugLog used to open, append and close a file per line, which measured at
  // ~8.5 ms - an order of magnitude more than the O(1) pointer moves a warm
  // switch actually costs, and this is the path a menu click or a picker
  // selection takes. The sink is file-free now, but the rule stands: what the
  // log keeps is every SHAPE change - parses, evictions, releases, repairs
  // (the Log calls above) and the preload batch. Measured back then by
  // kat_enginecache: 200 warm switches were 1702 ms with the transition line
  // and a few ms without it.
end;

function TAnsiEngineManager.TrySwitchCached(const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  Key := SlotKey(AName);
  if Key = '' then
    Exit;

  // A picker/menu click must never wait behind parser/refresh work.
  if not FLock.TryEnter then
    Exit;
  try
    if not FCache.ContainsKey(Key) then
      Exit; // never cached: caller repairs

    // Already active AND really live: O(1) no-op. This must come before the
    // hollow test - the active engine's slot is empty BY DESIGN (the globals
    // own its containers while it runs), so IsSlotHollow is true here even in
    // the healthy case.
    if (Key = FCurrentKey) and GlobalsHoldEngine then
      Exit(True);

    if Key = FCurrentKey then
    begin
      // Active name but empty globals: the slot may still be valid (restore
      // it in place) or hollow (caller must repair from disk).
      if RestoreSlotState(Key) then
      begin
        AnsiVersion := AName;
        Log('Engine switch (fast path): repaired active engine "' + AName + '"');
        Exit(True);
      end;
      Log('Engine switch (fast path): active engine "' + AName + '" is hollow - repair required');
      Exit;
    end;

    // A hollow slot is a cache MISS, not a switch: serving it would strip
    // every rule/lookup table and silently leave typing broken.
    if IsSlotHollow(Key) then
    begin
      Log('Engine switch (fast path): "' + AName + '" is hollow - repair required');
      Exit;
    end;

    ParkCurrent;
    if not TryRestoreSlot(Key, AName) then
    begin
      Log('Engine switch (fast path) failed: "' + AName + '"');
      Exit;
    end;
    Result := True;
    EvictToLimit;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.WarmAllEngines(const AReturnTo: string);
var
  Keys:           TList<string>;
  Key, ReturnKey: string;
  Warmed:         Integer;
begin
  ReturnKey := SlotKey(AReturnTo);
  FLock.Enter;
  try
    Keys := TList<string>.Create;
    try
      for Key in FCache.Keys do
        Keys.Add(Key);
      Warmed := 0;
      // Exercise every park/restore path before the keyboard hook starts.
      // Hollow slots are skipped: they cannot be restored and would only
      // waste the warm pass (and make it end on a broken engine).
      for Key in Keys do
        if (Key <> FCurrentKey) and (not IsSlotHollow(Key)) then
        begin
          ParkCurrent;
          if RestoreSlotState(Key) then
            Inc(Warmed);
        end;
      if (ReturnKey <> FCurrentKey) and (not IsSlotHollow(ReturnKey)) then
      begin
        ParkCurrent;
        RestoreSlotState(ReturnKey);
      end;

      if GlobalsHoldEngine and (FCurrentKey = ReturnKey) then
        AnsiVersion := AReturnTo
      else
      begin
        // The requested engine could not be restored (hollow or missing).
        // Never advertise it while another engine is live - the next switch
        // repairs it from disk.
        EnsureLiveEngine;
        Log('WARNING: warm pass could not activate "' + AReturnTo + '" - active engine is "' + FCurrentKey + '"');
      end;
      Log('Engine cache warmed: ' + IntToStr(Warmed) + ' engine(s), active="' + FCurrentKey + '"');
    finally
      Keys.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.DoInvalidateEngine(const AName: string);
var
  Key, Path: string;
  WasActive: Boolean;
  Err:       TStringList;
begin
  Key := SlotKey(AName);
  if not FCache.ContainsKey(Key) then
    Exit;
  Path := FCache[Key].FilePath;
  if (Path <> '') and (not FileExists(Path)) then
    Exit; // file is gone - RefreshFromDisk / delete flow handles removal

  WasActive := (Key = FCurrentKey);
  if WasActive then
    ParkCurrent; // globals -> slot, then drop the old engine
  DropSlot(Key);

  Err := TStringList.Create;
  try
    if not ParseIntoSlot(AName, Path, Err) then
    begin
      Log('InvalidateEngine failed for ' + AName + ': ' + Err.Text);
      // Repair from another file mapping or leave Unicode-only - never a
      // silent fall back to a compiled-in engine.
      EnsureLiveEngine;
      Exit;
    end;

    if WasActive then
    begin
      if not TryRestoreSlot(Key, AName) then
        EnsureLiveEngine;
      Log('Engine invalidated (active): ' + AName);
    end
    else
    begin
      // A background file change for a NON-active mapping used to parse on top
      // of the live engine and destroy it. The parse is quarantined now, so
      // the running engine only has to be put back to work.
      EnsureLiveEngine;
      Log('Engine invalidated (background): ' + AName);
    end;
  finally
    Err.Free;
  end;
end;

procedure TAnsiEngineManager.InvalidateEngine(const AName: string);
begin
  FLock.Enter;
  try
    DoInvalidateEngine(AName);
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.RefreshFromDisk;
var
  Key:     string;
  Slot:    TEngineSlot;
  Info:    TAvroEncoFileInfo;
  Name:    string;
  NewTime: TDateTime;
  Keys:    TList<string>;
begin
  FLock.Enter;
  try
    // 1. Drop cached engines whose file disappeared (never the active one).
    Keys := TList<string>.Create;
    try
      for Key in FCache.Keys do
        Keys.Add(Key);
      for Key in Keys do
      begin
        if FCache.TryGetValue(Key, Slot) and (Slot.FilePath <> '') and (not FileExists(Slot.FilePath)) then
        begin
          if Key = FCurrentKey then
            Continue; // active engine: keep; the delete flow switches away
          DropSlot(Key);
        end;
      end;
    finally
      Keys.Free;
    end;

    // 2. Re-parse changed engines, preload newly added ones (default-key /
    // plain .json only; password engines stay lazy).
    if Assigned(AvroEncoFiles) then
      for Info in AvroEncoFiles.Values do
      begin
        if Info.IsEncoFile and (GetAvroEncoProtectionFlag(Info.FilePath) <> AVROENCO_FLAG_DEFAULT_KEY) then
          Continue;
        name := Info.DisplayName;
        Key := SlotKey(name);
        if FCache.TryGetValue(Key, Slot) then
        begin
          try
            NewTime := TFile.GetLastWriteTime(Info.FilePath);
          except
            NewTime := 0;
          end;
          if Abs(NewTime - Slot.LastWriteTime) > 0.000001 then
            DoInvalidateEngine(name);
        end
        else
        begin
          Log('Engine added while running: ' + name);
          ParseIntoSlot(name, Info.FilePath, nil);
        end;
      end;

    // A newly parsed engine parks the live one; put the running engine back.
    EnsureLiveEngine;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.RemoveEngine(const AName: string);
var
  Key: string;
begin
  Key := SlotKey(AName);
  if Key = FCurrentKey then
    Exit; // caller must switch away first (picker does this)
  FLock.Enter;
  try
    DropSlot(Key);
  finally
    FLock.Leave;
  end;
end;

{ =============================================================================
  TAnsiPreloadThread
  ============================================================================= }

constructor TAnsiPreloadThread.Create(const AItems: TArray<TPreloadItem>);
begin
  // Suspended: fields must be set before Start (called by the owner right
  // after Create), so Execute can never observe half-initialized state.
  inherited Create(True);
  FItems := AItems;
  FNextJob := 0;
  FResultLock := TCriticalSection.Create;
  SetLength(FResults, Length(AItems));
end;

destructor TAnsiPreloadThread.Destroy;
begin
  FResultLock.Free;
  inherited Destroy;
end;

procedure TAnsiPreloadThread.DecryptItem(Index: Integer);
var
  R:    TPreloadResult;
  Item: TPreloadItem;
begin
  Item := FItems[index];
  R.DisplayName := Item.DisplayName;
  R.FilePath := Item.FilePath;
  R.JSON := '';
  R.OK := False;
  R.ErrorMsg := '';
  try
    if IsEncoFile(Item.FilePath) then
    begin
      // Shield/legacy containers: pure crypto, no shared state - safe to run
      // on worker threads. Default-key containers ignore the password;
      // cached-password containers decrypt with the persisted password.
      R.OK := LoadAnsiJSONCached(Item.FilePath, Item.Password, R.JSON) and (R.JSON <> '') and (R.JSON[1] = '{');
    end
    else
    begin
      R.OK := LoadAnsiJSONCached(Item.FilePath, '', R.JSON) and (Trim(R.JSON) <> '');
    end;
    if (not R.OK) and (R.ErrorMsg = '') then
      R.ErrorMsg := 'decrypt/cache load returned no usable JSON';
  except
    on E: Exception do
    begin
      R.OK := False;
      R.ErrorMsg := E.ClassName + ': ' + E.Message;
    end;
  end;
  FResultLock.Enter;
  try
    FResults[index] := R;
  finally
    FResultLock.Leave;
  end;
end;

procedure TAnsiPreloadThread.ParallelDecrypt;
var
  WorkerCount, I, Next: Integer;
  Workers:              TArray<TThread>;
begin
  // Shield v2 decryption is millisecond-level with small, short-lived
  // buffers (the 64 MB Argon2 arenas are gone - Argon2 was removed
  // project-wide), so plain CPU-count parallelism is safe again.
  WorkerCount := Min(Length(FItems), TThread.ProcessorCount);
  if WorkerCount < 2 then
  begin
    Next := TInterlocked.Increment(FNextJob) - 1;
    while Next < Length(FItems) do
    begin
      DecryptItem(Next);
      Next := TInterlocked.Increment(FNextJob) - 1;
    end;
    Exit;
  end;

  SetLength(Workers, WorkerCount);
  for I := 0 to WorkerCount - 1 do
  begin
    Workers[I] := TThread.CreateAnonymousThread(
        procedure
      var
        Job: Integer;
      begin
        Job := TInterlocked.Increment(FNextJob) - 1;
        while Job < Length(FItems) do
        begin
          DecryptItem(Job);
          Job := TInterlocked.Increment(FNextJob) - 1;
        end;
      end);
    // CreateAnonymousThread defaults to FreeOnTerminate=True, which makes
    // the worker free itself as soon as Execute ends - then WaitFor/Free on
    // the creator side touch freed memory (nondeterministic EThread errors,
    // heap corruption). Keep explicit ownership: the worker stays alive
    // until the creator waits on it and frees it.
    Workers[I].FreeOnTerminate := False;
  end;
  try
    for I := 0 to WorkerCount - 1 do
      Workers[I].Start;
    for I := 0 to WorkerCount - 1 do
      Workers[I].WaitFor;
  finally
    for I := 0 to WorkerCount - 1 do
      Workers[I].Free;
  end;
end;

procedure TAnsiPreloadThread.Execute;
var
  I, N:      Integer;
  Completed: TArray<TPreloadResult>;
begin
  try
    if Length(FItems) = 0 then
      Exit;
    ParallelDecrypt;

    N := 0;
    for I := 0 to Length(FItems) - 1 do
      if FResults[I].OK then
        Inc(N);
    if N = 0 then
      Exit;

    SetLength(Completed, N);
    N := 0;
    for I := 0 to Length(FItems) - 1 do
      if FResults[I].OK then
      begin
        Completed[N] := FResults[I];
        Inc(N);
      end;
    AnsiEngineManager.CommitPreload(Completed);
  except
    on E: Exception do
      Log('Ansi engine preload thread: ' + E.Message);
  end;
end;

initialization

AnsiEngineManager := TAnsiEngineManager.Create;

finalization

FreeAndNil(AnsiEngineManager);

end.
