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
  { One cached engine: the parked parser state plus the exact file it was
    parsed from, its legacy base name, its size and its last write time (used to
    detect external file changes so the directory watcher can re-parse just that
    engine). A same-base sibling is a different slot: the exact file name is the
    cache identity.

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
      FileName:      string; // exact file name; '' for the embedded baseline
      BaseName:      string; // legacy AnsiVersion base name
      FilePath:      string;
      LastWriteTime: TDateTime;
      FileSize:      Int64;
      LastUseStamp:  Cardinal;
      State:         TAnsiEngineState;
      destructor Destroy; override;
  end;

  { One engine to preload at startup. Password is non-empty only for
    password-protected containers that were already unlocked on this
    computer (persisted per-file password cache) - those decrypt silently
    with the cached password, never prompting. }
  TPreloadItem = record
    FileName: string;
    BaseName: string;
    FilePath: string;
    Password: AnsiString;
  end;

  { Decrypted/read JSON for one preload item, produced off the UI thread.
    ErrorMsg carries the decrypt failure reason (exception text) so a cold-
    start miss - e.g. Ansi V3 after a full %AppData% cache wipe - is
    diagnosable instead of a bare "decryption" line. }
  TPreloadResult = record
    FileName: string;
    BaseName: string;
    FilePath: string;
    JSON: string;
    OK: Boolean;
    ErrorMsg: string;
  end;

  TAnsiEngineManager = class
    private
      FCache:      TDictionary<string, TEngineSlot>; // key: Lowercase(FileName)
      FCurrentKey: string;
      FLock:       TCriticalSection; // serializes every engine-state mutation
      { Last value handed out by NextUseStamp; see TEngineSlot.LastUseStamp. }
      FUseStamp: Cardinal;
      { GetTickCount of the last RepairSelectedEngine attempt; 0 = never. }
      FLastRepairTick: Cardinal;
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
      { Restores AKey's parked state into the globals and publishes both
        selection globals from that slot. False for a missing or hollow slot -
        the caller then treats it as a cache MISS instead of serving an engine
        that cannot render. }
      function RestoreSlotState(const AKey: string): Boolean;
      { True when AName's parked state is missing or hollow. }
      function IsSlotHollow(const AKey: string): Boolean;
      { Fail-closed safety net: when the globals hold no engine, restore the
        active or last-used parked FILE slot, else (when AAllowDiskFallback)
        parse one exact file mapping from disk. Never builds a compiled-in
        engine. Every successful repair publishes the restored slot's exact
        selection. With zero usable files it only logs and leaves the globals
        empty (Unicode still works). A caller that must fail without changing
        the selection passes False: an explicit exact-file switch that missed
        may not quietly activate some other mapping. }
      procedure EnsureLiveEngine(AAllowDiskFallback: Boolean = True);
      { Puts a live engine the caller just parked by hand back in place after a
        failed parse. }
      procedure RestoreParkedEngine(const AParked: Boolean);
      { Parses AJSON into the globals and parks the result in a new slot added
        to FCache. AFileName is the exact file name ('' for the embedded
        baseline), ABaseName is the legacy AnsiVersion value, and AFilePath is
        stored on the slot for the directory watcher. Password-protected
        containers are decrypted by the CALLER (version picker / menu / preload
        thread) before this is reached, so this never prompts. Returns False
        (and fills ErrorLog) when the JSON contains no usable mapping rules.
        Caller must hold FLock. }
      function ParseJSONIntoSlot(const AFileName, ABaseName, AFilePath, AJSON: string; ErrorLog: TStringList = nil): Boolean;
      { Decrypts AFilePath (Shield/legacy container with APassword, or reads
        plain .json) and parks the parsed result under the exact file identity.
        AFilePath must be a real file path - empty is not an engine and returns
        False. Caller must hold FLock. }
      function ParseIntoSlot(const AFileName, ABaseName, AFilePath: string; ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
      { Moves the currently active engine's globals back into its parked slot.
        Caller must hold FLock. }
      procedure ParkCurrent;
      { Frees and removes a NON-ACTIVE cached engine. Caller must hold FLock. }
      procedure DropSlot(const AKey: string);
      { Lock-free core of InvalidateEngine. Caller must hold FLock. }
      procedure DoInvalidateEngine(const AFileName: string);
      { Stamps AKey's slot as used now. Every park/restore path calls this, so LRU
        eviction reflects what the user actually switched between. }
      procedure TouchSlot(const AKey: string);
    public
      constructor Create;
      destructor Destroy; override;
      { Lowercase exact file name of the live engine; the baseline key when the
        embedded baseline is active. }
      property CurrentEngineName: string read FCurrentKey;
      { True while the active engine is really usable - the UI/tests can use this
        instead of trusting CurrentEngineName alone. }
      function LiveEngineReady: Boolean;
      { True only when the globals hold a REAL parsed engine. LiveEngineReady
        is not enough for that: the unit starts with the compiled-in canvas
        (registry + A_* initial values) and ResetAnsiToDefaults rebuilds it
        before every parse, so a parse that never ran - or a cold start whose
        activation failed on a locked container - leaves a registry with no
        rule tables at all. Typing through that canvas is what emits the
        built-in Avro/V1 glyphs while the menu shows the user's version, so
        every caller that converts must test THIS instead. }
      function EnginePrepared: Boolean;
      { Puts the persisted selection back in place when the globals do not hold
        a real engine (the cold-start failure above). A no-op while an engine
        is prepared, and throttled so a mapping that stays unreadable is not
        re-decrypted on every keystroke. Returns True when a real engine is
        live afterwards. Must be called on the thread that owns the globals. }
      function RepairSelectedEngine: Boolean;
      { True when AFileName's parked engine is complete (cached and not
        hollow). }
      function CachedEngineReady(const AFileName: string): Boolean;
      { Snapshots the file mappings that can unlock without user interaction
        (default-key containers, plain .json mappings and password-protected
        containers with a persisted password). Call on the main thread BEFORE
        starting the preload thread: the snapshot decouples the worker from
        the AvroEncoFiles dictionary, which the folder-change timers clear/
        refill while the worker runs. }
      function CapturePreloadList: TArray<TPreloadItem>;
      { Same snapshot, narrowed to ONE exact mapping file: zero items when it is
        already cached, is not a known file, or is a password container that was
        never unlocked. This is what an explicit single-layout action (unlock in
        the picker, import) warms before the user clicks it - warming the whole
        folder for one unlock is the eager behaviour the cache no longer does. }
      function CapturePreloadItem(const AFileName: string): TArray<TPreloadItem>;
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
      { Makes AFileName the active engine. For cached engines this is O(1)
        pointer moves with zero disk/crypto/parse work. Uncached engines
        (password protected, never unlocked before) are parsed once here. The
        exact file name and its base name are published together on success.
        Returns False on failure - the previously active engine stays
        untouched. }
      function SwitchEngine(const AFileName: string; ErrorLog: TStringList = nil): Boolean;
      { LAST-RESORT activation of the compiled-in baseline mapping (uAvroBaseline).

        Used only when NOTHING on disk can serve as an engine - a fresh, wiped or
        portable install with an empty AnsiMapping folder. It decrypts the
        embedded container in memory (never writes a file), installs it as the
        active engine and publishes AVRO_BASELINE_NAME as the display name, so a
        first run types ANSI instead of silently falling back to Unicode.

        Ordering contract: callers must have already failed to resolve a file
        mapping. A user mapping always outranks this, because anything on disk is
        tried first. Returns False when the resource is missing or broken, which
        leaves the app exactly as it behaves today - Unicode output, no engine. }
      function ActivateEmbeddedBaseline(ErrorLog: TStringList = nil): Boolean;
      { UI-safe fast path. Never reads/decrypts/parses files and never waits for
        the preload/refresh lock. Returns False immediately if busy/not cached. }
      function TrySwitchCached(const AFileName: string): Boolean;
      procedure WarmAllEngines(const AReturnTo: string);
      { Re-parses one cached engine from its exact file (directory watcher /
        auto-refresh on file change / import). If the engine is active it is
        re-activated in place; on re-parse failure EnsureLiveEngine repairs
        from another file mapping or leaves Unicode-only mode. }
      procedure InvalidateEngine(const AFileName: string);
      { Reconciles the cache with the file system: drops engines whose exact
        files disappeared (never the active one), re-parses default-key engines
        whose size or last write time changed, and preloads newly added ones. }
      procedure RefreshFromDisk;
      { Removes a non-active engine from the cache (mapping deleted by user). }
      procedure RemoveEngine(const AFileName: string);
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
  uAvroBaseline,
  uAvroSecureMem,
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

function TAnsiEngineManager.EnginePrepared: Boolean;
begin
  Result := GlobalsHoldEngine and ((Length(VowelRules) > 0) or (Length(RfolaRules) > 0) or (Length(CustomFullForms) > 0) or
    (Length(CustomPreReplacements) > 0) or (Length(CustomPostReplacements) > 0) or ((AnsiOverrides <> nil) and (AnsiOverrides.Count > 0)));
end;

function TAnsiEngineManager.RepairSelectedEngine: Boolean;
const
  REPAIR_THROTTLE_MS = 2000;
var
  FileName, Path: string;
begin
  Result := EnginePrepared;
  if Result then
    Exit;

  if (FLastRepairTick <> 0) and (GetTickCount - FLastRepairTick < REPAIR_THROTTLE_MS) then
    Exit;
  FLastRepairTick := GetTickCount;

  // The selection - never a different file: repair must not change which
  // encoding the user chose, so there is no fallback to another mapping here.
  FileName := AnsiVersionFileName;
  if FileName = '' then
    Exit;
  Path := GetExactEncoFilePath(FileName, AnsiMappingDir);
  if Path = '' then
  begin
    Log('Engine repair: selected mapping file is missing: ' + FileName);
    Exit;
  end;

  if not SwitchEngine(FileName) then
  begin
    Log('Engine repair: could not activate "' + FileName + '"');
    Exit;
  end;

  Log('Engine repair: activated "' + FileName + '" on first use (startup activation had not run)');
  Result := EnginePrepared;
end;

function TAnsiEngineManager.IsSlotHollow(const AKey: string): Boolean;
var
  Slot: TEngineSlot;
begin
  Result := True; // missing counts as unusable
  if FCache.TryGetValue(AKey, Slot) then
    Result := IsEngineStateHollow(Slot.State);
end;

function TAnsiEngineManager.CachedEngineReady(const AFileName: string): Boolean;
begin
  Result := not IsSlotHollow(SlotKey(AFileName));
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
  // The slot that becomes live is the only authority for the selection: publish
  // the exact file and its base name together, so no path can leave a stale
  // companion behind. The baseline publishes ('', AVRO_BASELINE_NAME).
  PublishActiveSelection(Slot.FileName, Slot.BaseName);
  Result := True;
end;

procedure TAnsiEngineManager.RestoreParkedEngine(const AParked: Boolean);
begin
  if not AParked then
    Exit;
  if (FCurrentKey = '') or (not RestoreSlotState(FCurrentKey)) then
    Exit;
  Log('Engine state: parse failed - kept active engine "' + FCurrentKey + '"');
end;

procedure TAnsiEngineManager.EnsureLiveEngine(AAllowDiskFallback: Boolean = True);
var
  PrevKey, BestKey, FallbackFileName, Path: string;
  BestStamp:                                Cardinal;
  Key:                                      string;
  Slot:                                     TEngineSlot;
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
  // so the layout the user just left comes back first. RestoreSlotState
  // publishes that slot's exact selection.
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

  // Nothing parked: parse ONE exact file mapping from disk (natural-sort first
  // usable file). Never a compiled-in Default - with zero files the app stays
  // on Unicode output. Explicit exact-file switches opt out: a failed selection
  // must not silently activate a different mapping.
  if AAllowDiskFallback then
  begin
    FallbackFileName := FirstAvailableMappingFileName;
    if FallbackFileName <> '' then
    begin
      Path := GetExactEncoFilePath(FallbackFileName, AnsiMappingDir);
      if (Path <> '') and ParseIntoSlot(FallbackFileName, ChangeFileExt(FallbackFileName, ''), Path, nil) and
        RestoreSlotState(SlotKey(FallbackFileName)) then
      begin
        Log('Engine state repaired: parsed file mapping "' + FallbackFileName + '"');
        Exit;
      end;
    end;
  end;

  Log('WARNING: no usable ANSI engine available');
end;

function TAnsiEngineManager.ParseJSONIntoSlot(const AFileName, ABaseName, AFilePath, AJSON: string; ErrorLog: TStringList = nil): Boolean;
var
  JSON:       string;
  Slot:       TEngineSlot;
  LiveParked: Boolean;
  Key, LabelText: string;
begin
  Result := False;
  JSON := AJSON;
  LabelText := AFileName;
  if LabelText = '' then
    LabelText := ABaseName;

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
      ErrorLog.Add('Error: Mapping file is empty: ' + LabelText);
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
      ErrorLog.Add('Error: mapping parse produced no engine for ' + LabelText);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;
  if (Length(CustomFullForms) = 0) and (Length(CustomPreReplacements) = 0) and (Length(CustomPostReplacements) = 0) and (Length(VowelRules) = 0) and
    (Length(RfolaRules) = 0) and (Length(KarCorrections) = 0) and (Length(GroupKarCorrections) = 0) and ((AnsiOverrides = nil) or (AnsiOverrides.Count = 0))
  then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: mapping contains no usable rules for ' + LabelText);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;

  Slot := TEngineSlot.Create;
  Slot.FileName := AFileName;
  Slot.BaseName := ABaseName;
  if Slot.BaseName = '' then
    Slot.BaseName := ChangeFileExt(AFileName, '');
  Slot.FilePath := AFilePath;
  Slot.LastWriteTime := 0;
  Slot.FileSize := 0;
  Slot.LastUseStamp := NextUseStamp;
  if AFilePath <> '' then
    try
      Slot.LastWriteTime := TFile.GetLastWriteTime(AFilePath);
      Slot.FileSize := TFile.GetSize(AFilePath);
    except
      Slot.LastWriteTime := 0;
      Slot.FileSize := 0;
    end;
  CaptureEngineState(Slot.State);
  // CaptureEngineState stamps the CURRENT AnsiVersion, which is the name of the
  // engine we just parked (or the one still being requested). The parsed file's
  // own base name is authoritative for the slot and for every later restore.
  Slot.State.DisplayName := Slot.BaseName;
  // A file slot is keyed by its exact file name; the embedded baseline has no
  // file and keeps the legacy baseline key.
  Key := SlotKey(AFileName);
  if (Key = '') and (Slot.BaseName <> '') then
    Key := SlotKey(Slot.BaseName);
  // Never replace a slot that still owns containers: dropping first keeps the
  // one-owner rule (a blind AddOrSetValue would leak the old engine).
  if (Key <> '') and FCache.ContainsKey(Key) then
    DropSlot(Key);
  if Key <> '' then
    FCache.Add(Key, Slot)
  else
  begin
    Slot.Free;
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: mapping has no identity: ' + LabelText);
    RestoreParkedEngine(LiveParked);
    Exit;
  end;

  // The per-layout icon a container carries rides inside the payload, so it is
  // refreshed here - the one place every parse path goes through: the startup
  // preload, the directory watcher's re-parse, an on-demand switch and an
  // import. The cached icon therefore stays in step with the file exactly like
  // the engine's own rules do, and a legacy container simply clears its entry.
  if AFilePath <> '' then
    StoreMappingIcon(ExtractFileName(AFilePath), ExtractIconSection(JSON));

  Result := True;
end;

function TAnsiEngineManager.ParseIntoSlot(const AFileName, ABaseName, AFilePath: string; ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
var
  JSON:        string;
  UsePassword: AnsiString;
  LabelText:   string;
begin
  Result := False;
  LabelText := AFileName;
  if LabelText = '' then
    LabelText := ABaseName;

  // Empty path is not an engine: every successful parse goes through a real
  // .json / .AvroEnco file (the compiled glyph canvas is only the scratch
  // surface LoadAnsiMappingFromJSON resets onto before overlaying that file).
  if AFilePath = '' then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: Mapping file path is empty for ' + LabelText);
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
        ErrorLog.Add('Error: Decryption failed for ' + LabelText);
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

  Result := ParseJSONIntoSlot(AFileName, ABaseName, AFilePath, JSON, ErrorLog);
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
          if FCache.ContainsKey(SlotKey(Info.FileName)) then
            Continue;
          Item.FileName := Info.FileName;
          Item.BaseName := Info.BaseName;
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

function TAnsiEngineManager.CapturePreloadItem(const AFileName: string): TArray<TPreloadItem>;
var
  Info: TAvroEncoFileInfo;
  Item: TPreloadItem;
  Flag: Byte;
begin
  SetLength(Result, 0);
  if AFileName = '' then
    Exit;

  FLock.Enter;
  try
    if FCache.ContainsKey(SlotKey(AFileName)) then
      Exit; // already cached: nothing to warm
    if (not Assigned(AvroEncoFiles)) or (not AvroEncoFiles.TryGetValue(SlotKey(AFileName), Info)) then
      Exit; // not a mapping this process knows about
  finally
    FLock.Leave;
  end;

  Item.FileName := Info.FileName;
  Item.BaseName := Info.BaseName;
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
            Log('Engine preload failed: ' + R.FileName + ' - ' + R.ErrorMsg)
          else
            Log('Engine preload failed: ' + R.FileName + ' - decryption');
          Continue;
        end;
        if FCache.ContainsKey(SlotKey(R.FileName)) then
          Continue;
        Err.Clear;
        if ParseJSONIntoSlot(R.FileName, R.BaseName, R.FilePath, R.JSON, Err) then
        begin
          Inc(Result);
          Log('Engine preloaded: ' + R.FileName);
        end
        else
          Log('Engine preload failed: ' + R.FileName + ' - ' + Err.Text);
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

function TAnsiEngineManager.ActivateEmbeddedBaseline(ErrorLog: TStringList = nil): Boolean;
var
  JsonUtf8: TBytes;
  JSON:     string;
  Key, Err: string;
begin
  Result := False;

  // Defense in depth for the asynchronous migration runner and future callers:
  // the baseline is only for a completely empty catalog. Locked, corrupt or
  // unreadable files still count as rows, so they block it exactly as required.
  if Assigned(AvroEncoFiles) and (AvroEncoFiles.Count > 0) then
  begin
    Log('Baseline: not activated - mapping catalog is not empty (' + IntToStr(AvroEncoFiles.Count) + ' file(s))');
    Exit;
  end;

  // Read + decrypt OUTSIDE the lock: AvroBaselineLoad does AES-GCM and zlib
  // work, and holding FLock across it would stall a concurrent switch/repair.
  if not AvroBaselineLoad(JsonUtf8, Err) then
  begin
    Log('Baseline: not activated - ' + Err);
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: ' + Err);
    Exit;
  end;

  try
    JSON := TEncoding.UTF8.GetString(JsonUtf8);
    if (JSON = '') or (JSON[1] <> '{') then
    begin
      Log('Baseline: decrypted payload is not mapping JSON');
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: embedded baseline is not valid mapping JSON');
      Exit;
    end;

    Key := SlotKey(AVRO_BASELINE_NAME);
    if Key = '' then
      Exit;

    FLock.Enter;
    try
      // '' as the file path is correct and deliberate: the baseline has no file,
      // so there is nothing for the directory watcher to re-parse and nothing to
      // invalidate. A later import of a real "Ansi V1" simply replaces the slot.
      DropSlot(Key);
      if not ParseJSONIntoSlot('', AVRO_BASELINE_NAME, '', JSON, ErrorLog) then
      begin
        // ParseJSONIntoSlot restores whatever was parked, so a failure here
        // cannot cost the app an engine it already had.
        Log('Baseline: embedded payload produced no engine');
        Exit;
      end;
      ParkCurrent;
      if not RestoreSlotState(Key) then
      begin
        Log('Baseline: state is hollow after parse');
        EnsureLiveEngine;
        Exit;
      end;
      Result := True;
      EvictToLimit;
    finally
      FLock.Leave;
    end;
    Log('Baseline: activated embedded "' + AVRO_BASELINE_NAME + '" (no mapping file on disk)');
  finally
    // The decrypted mapping is the most sensitive buffer in the process; wipe it
    // here rather than leaving it for the string manager to free later.
    AvroWipeString(JSON);
    AvroWipeAndRelease(JsonUtf8);
  end;
end;

function TAnsiEngineManager.SwitchEngine(const AFileName: string; ErrorLog: TStringList = nil): Boolean;
var
  Key, Path, BaseName: string;
  Slot: TEngineSlot;
  OwnErr: Boolean;
begin
  Result := False;
  Key := SlotKey(AFileName);
  if Key = '' then
    Exit;
  BaseName := ChangeFileExt(AFileName, '');

  OwnErr := not Assigned(ErrorLog);
  if OwnErr then
    ErrorLog := TStringList.Create;
  FLock.Enter;
  try
    // Idempotent: already active AND the globals really hold its state. The
    // ContainsKey check alone used to be a lie: when something had parsed over
    // the live engine the slot stayed in place but empty, so every later click
    // on the same version returned True while typing stayed broken.
    if (Key = FCurrentKey) and FCache.ContainsKey(Key) then
    begin
      if GlobalsHoldEngine then
      begin
        // Republish from the live slot so both selection values are always the
        // exact pair of the engine that is actually active.
        Slot := FCache[Key];
        PublishActiveSelection(Slot.FileName, Slot.BaseName);
        Exit(True);
      end;
      if RestoreSlotState(Key) then
      begin
        Log('Engine switch: repaired active engine "' + AFileName + '"');
        Exit(True);
      end;
      DropSlot(Key); // hollow: rebuild it from disk below
      Log('Engine switch: hollow state for "' + AFileName + '" - re-parsing from disk');
    end;

    // Load on demand (password-protected engine, file added at runtime, or the
    // hollow-repair case above). ParseIntoSlot parks the live engine first and
    // puts it back when the parse fails, so the active engine survives either
    // way (fail-closed). Empty path is never an engine - no compiled Default.
    if (not FCache.ContainsKey(Key)) or IsSlotHollow(Key) then
    begin
      Path := GetExactEncoFilePath(AFileName, AnsiMappingDir);
      if Path = '' then
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Mapping file not found: ' + AFileName);
        // An explicit exact-file switch that missed must not activate a
        // different mapping: repair only what was already live/parked.
        EnsureLiveEngine(False);
        Exit;
      end;
      DropSlot(Key);
      if not ParseIntoSlot(AFileName, BaseName, Path, ErrorLog) then
      begin
        EnsureLiveEngine(False);
        Exit;
      end;
    end;

    // O(1) engine swap: park current (a no-op right after a parse, which
    // already parked it), then restore the target - never a hollow state.
    ParkCurrent;
    if not RestoreSlotState(Key) then
    begin
      Log('Engine switch failed: "' + AFileName + '" state is hollow');
      EnsureLiveEngine(False);
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

function TAnsiEngineManager.TrySwitchCached(const AFileName: string): Boolean;
var
  Key: string;
  Slot: TEngineSlot;
begin
  Result := False;
  Key := SlotKey(AFileName);
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
    begin
      Slot := FCache[Key];
      PublishActiveSelection(Slot.FileName, Slot.BaseName);
      Exit(True);
    end;

    if Key = FCurrentKey then
    begin
      // Active name but empty globals: the slot may still be valid (restore
      // it in place) or hollow (caller must repair from disk).
      if RestoreSlotState(Key) then
      begin
        Log('Engine switch (fast path): repaired active engine "' + AFileName + '"');
        Exit(True);
      end;
      Log('Engine switch (fast path): active engine "' + AFileName + '" is hollow - repair required');
      Exit;
    end;

    // A hollow slot is a cache MISS, not a switch: serving it would strip
    // every rule/lookup table and silently leave typing broken.
    if IsSlotHollow(Key) then
    begin
      Log('Engine switch (fast path): "' + AFileName + '" is hollow - repair required');
      Exit;
    end;

    ParkCurrent;
    if not RestoreSlotState(Key) then
    begin
      Log('Engine switch (fast path) failed: "' + AFileName + '"');
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
      // waste the warm pass (and make it end on a broken engine). Each restore
      // publishes its slot's exact selection.
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

      if not (GlobalsHoldEngine and (FCurrentKey = ReturnKey)) then
      begin
        // The requested engine could not be restored (hollow or missing).
        // Never advertise it while another engine is live - the next switch
        // repairs it from disk. EnsureLiveEngine publishes whatever it repairs.
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

procedure TAnsiEngineManager.DoInvalidateEngine(const AFileName: string);
var
  Key, Path, BaseName: string;
  WasActive: Boolean;
  Err:       TStringList;
begin
  Key := SlotKey(AFileName);
  if not FCache.ContainsKey(Key) then
    Exit;
  Path := FCache[Key].FilePath;
  if Path = '' then
    Exit; // embedded baseline: no file to re-parse
  if not FileExists(Path) then
    Exit; // file is gone - RefreshFromDisk / delete flow handles removal

  BaseName := ChangeFileExt(AFileName, '');
  WasActive := (Key = FCurrentKey);
  if WasActive then
    ParkCurrent; // globals -> slot, then drop the old engine
  DropSlot(Key);

  Err := TStringList.Create;
  try
    if not ParseIntoSlot(AFileName, BaseName, Path, Err) then
    begin
      Log('InvalidateEngine failed for ' + AFileName + ': ' + Err.Text);
      // Repair from another file mapping or leave Unicode-only - never a
      // silent fall back to a compiled-in engine.
      EnsureLiveEngine;
      Exit;
    end;

    if WasActive then
    begin
      if not RestoreSlotState(Key) then
        EnsureLiveEngine;
      Log('Engine invalidated (active): ' + AFileName);
    end
    else
    begin
      // A background file change for a NON-active mapping used to parse on top
      // of the live engine and destroy it. The parse is quarantined now, so
      // the running engine only has to be put back to work.
      EnsureLiveEngine;
      Log('Engine invalidated (background): ' + AFileName);
    end;
  finally
    Err.Free;
  end;
end;

procedure TAnsiEngineManager.InvalidateEngine(const AFileName: string);
begin
  FLock.Enter;
  try
    DoInvalidateEngine(AFileName);
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.RefreshFromDisk;
var
  Key:     string;
  Slot:    TEngineSlot;
  Info:    TAvroEncoFileInfo;
  FileName: string;
  NewTime: TDateTime;
  NewSize: Int64;
  Keys:    TList<string>;
begin
  FLock.Enter;
  try
    // 1. Drop cached engines whose exact file disappeared (never the active
    // one). A same-base sibling is never treated as the same engine.
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
    // plain .json only; password engines stay lazy). Identity is the exact
    // file name, so one.json and one.AvroEnco are independent engines.
    if Assigned(AvroEncoFiles) then
      for Info in AvroEncoFiles.Values do
      begin
        if Info.IsEncoFile and (GetAvroEncoProtectionFlag(Info.FilePath) <> AVROENCO_FLAG_DEFAULT_KEY) then
          Continue;
        FileName := Info.FileName;
        Key := SlotKey(FileName);
        if FCache.TryGetValue(Key, Slot) then
        begin
          try
            NewTime := TFile.GetLastWriteTime(Info.FilePath);
            NewSize := TFile.GetSize(Info.FilePath);
          except
            NewTime := 0;
            NewSize := 0;
          end;
          if (Abs(NewTime - Slot.LastWriteTime) > 0.000001) or (NewSize <> Slot.FileSize) then
            DoInvalidateEngine(FileName);
        end
        else
        begin
          Log('Engine added while running: ' + FileName);
          ParseIntoSlot(FileName, Info.BaseName, Info.FilePath, nil);
        end;
      end;

    // A newly parsed engine parks the live one; put the running engine back.
    EnsureLiveEngine;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.RemoveEngine(const AFileName: string);
var
  Key: string;
begin
  Key := SlotKey(AFileName);
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
  R.FileName := Item.FileName;
  R.BaseName := Item.BaseName;
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
