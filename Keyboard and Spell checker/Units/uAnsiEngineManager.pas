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
  globals. This manager pre-parses every engine that can unlock without user
  interaction (the built-in Default engine, default-key .AvroEnco containers,
  plain .json mappings, and password-protected containers whose password was
  already cached on this computer) - once, during application initialization,
  on a BACKGROUND thread while the splash screen is still visible - and parks
  each engine's complete state in a TAnsiEngineState record
  (CaptureEngineState).

  Switching versions is then O(1): the previously active state is parked back
  and the target state is restored with plain pointer moves
  (RestoreEngineState). Zero disk I/O, zero decryption and zero parsing
  happens during the menu click for any cached engine.

  Threading model: all engine-state mutation (parse/capture/restore/drop)
  happens under FLock, so the startup preload thread can never interleave
  with a main-thread switch, the directory watcher or an import. The
  decryption phase (Argon2 KDF) of the preload runs in parallel worker
  threads; only the cheap parse + capture phase takes the lock.

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
  clsUnicodeToBijoy2000;

type
  { One cached engine: the parked parser state plus the file it was parsed
    from and its last write time (used to detect external file changes so the
    directory watcher can re-parse just that engine). }
  TEngineSlot = class
  public
    DisplayName: string;
    FilePath: string;
    LastWriteTime: TDateTime;
    State: TAnsiEngineState;
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

  { Decrypted/read JSON for one preload item, produced off the UI thread. }
  TPreloadResult = record
    DisplayName: string;
    FilePath: string;
    JSON: string;
    OK: Boolean;
  end;

  { One engine to decrypt/read in the background at runtime. The Argon2 KDF
    of the Shield containers dominates the cost, so it runs on a worker
    thread; the parse + cache commit afterwards happens on the MAIN thread
    (DrainBackgroundResults) because the parser mutates the unit globals
    that the keyboard hook reads - parse must stay on the same thread as
    typing. }
  TBackgroundLoadItem = record
    DisplayName: string;
    FilePath: string;
    Password: AnsiString;
  end;

  { Runtime background decrypt worker (singleton, owned by the manager).
    Decrypts/reads engines requested by RefreshFromDisk / InvalidateEngine /
    SetPendingSwitch and stores the results for DrainBackgroundResults. }
  TAnsiBackgroundLoadThread = class(TThread)
  private
    FQueue: TList<TBackgroundLoadItem>;
    FQueueLock: TCriticalSection;
    FEvent: TEvent;
    FResults: TList<TPreloadResult>;
    FResultsLock: TCriticalSection;
    function PopItem(out Item: TBackgroundLoadItem): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const AItem: TBackgroundLoadItem);
    { Moves ready decrypt results out (main thread). }
    function DrainResults: TArray<TPreloadResult>;
    { Wakes the worker so it can observe Terminate promptly. }
    procedure WakeUp;
  end;

  TAnsiEngineManager = class
  private
    FCache: TDictionary<string, TEngineSlot>; // key: Lowercase(DisplayName)
    FCurrentKey: string;
    FLock: TCriticalSection; // serializes every engine-state mutation
    FPendingSwitch: string;  // lowercased engine name awaiting cached state
    FPendingAttempts: Integer;
    FLoader: TAnsiBackgroundLoadThread; // runtime decrypt worker
    function SlotKey(const AName: string): string;
    { Parses AJSON into the globals and parks the result in a new slot added
      to FCache. AFilePath is stored on the slot for the directory watcher.
      Password-protected containers are decrypted by the CALLER (version
      picker / menu / preload thread) before this is reached, so this never
      prompts. Returns False (and fills ErrorLog) when the JSON contains no
      usable mapping rules. Caller must hold FLock. }
    function ParseJSONIntoSlot(const AName, AFilePath, AJSON: string;
      ErrorLog: TStringList = nil): Boolean;
    { Decrypts AFilePath (Shield/legacy container with APassword, or reads
      plain .json) and parks the parsed result. AFilePath = '' builds the
      built-in Default engine. Caller must hold FLock. }
    function ParseIntoSlot(const AName, AFilePath: string;
      ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
    { Moves the currently active engine's globals back into its parked slot.
      Caller must hold FLock. }
    procedure ParkCurrent;
    { Frees and removes a NON-ACTIVE cached engine. Caller must hold FLock. }
    procedure DropSlot(const AKey: string);
    { Lock-free core of InvalidateEngine. Caller must hold FLock. }
    procedure DoInvalidateEngine(const AName: string);
  public
    constructor Create;
    destructor Destroy; override;
    property CurrentEngineName: string read FCurrentKey;
    { Snapshots the engines that can unlock without user interaction
      (built-in Default, default-key containers, plain .json mappings and
      password-protected containers with a persisted password). Call on the
      main thread BEFORE starting the preload thread: the snapshot decouples
      the worker from the AvroEncoFiles dictionary, which the folder-change
      timers clear/refill while the worker runs. }
    function CapturePreloadList: TArray<TPreloadItem>;
    { Parses the built-in Default engine (if missing) and every decrypted
      snapshot result into the cache. Runs on the preload thread; takes
      FLock, so it can never interleave with a main-thread switch. Returns
      the number of engines committed. }
    function CommitPreload(const AResults: TArray<TPreloadResult>): Integer;
    { Makes AName the active engine. For cached engines this is O(1) pointer
      moves with zero disk/crypto/parse work. Uncached engines (password
      protected, never unlocked before) are parsed once here - pass
      ALoadIfMissing = False to keep this a pure RAM call when the caller
      wants the parse to happen off the UI thread (startup, settings
      refresh). Returns False on failure - the previously active engine
      stays untouched. }
    function SwitchEngine(const AName: string;
      ErrorLog: TStringList = nil; ALoadIfMissing: Boolean = True): Boolean;
    { UI-safe fast path. Never reads/decrypts/parses files and never waits for
      the preload/refresh lock. Returns False immediately if busy/not cached. }
    function TrySwitchCached(const AName: string): Boolean;
    { Records "the user asked for AName, apply it as soon as it is cached".
      Used when TrySwitchCached fails; the auto-refresh (watcher / poll /
      picker unlock thread) eventually caches the engine and the main form's
      timer applies the pending switch - no second click needed. }
    procedure SetPendingSwitch(const AName: string);
    { Attempts to apply the pending switch (RAM-only). Returns True and fills
      AAppliedName when the pending engine is cached and was applied. Fails
      fast when the engine is not cached yet; gives up after ~5 seconds of
      failed attempts so a corrupt engine cannot cause an infinite retry. }
    function TryApplyPendingSwitch(out AAppliedName: string): Boolean;
    property PendingSwitch: string read FPendingSwitch;
    function CachedEngineCount: Integer;
    procedure WarmAllEngines(const AReturnTo: string);
    { Re-parses one cached engine from its file (directory watcher /
      auto-refresh on file change / import). If the engine is active it is
      re-activated in place; on re-parse failure the active engine falls back
      to Default so the app never loses a working engine. }
    procedure InvalidateEngine(const AName: string);
    { Reconciles the cache with the file system: drops engines whose files
      disappeared (never the active one), re-parses default-key engines whose
      last write time changed, and preloads newly added ones. }
    procedure RefreshFromDisk;
    { Removes a non-active engine from the cache (mapping deleted by user). }
    procedure RemoveEngine(const AName: string);
    { Requests a background decrypt/read for one engine (runtime path). The
      caller never blocks; the result is committed by DrainBackgroundResults
      on the main thread. }
    procedure RequestBackgroundLoad(const AName, AFilePath: string;
      const APassword: AnsiString = '');
    { Commits every decrypt result that the background worker produced.
      MUST be called on the main thread (the parser mutates the engine
      globals that the keyboard hook reads). Returns the number of engines
      committed. }
    function DrainBackgroundResults: Integer;
  end;

  { Startup preload worker. Decrypts every snapshot item in parallel (the
    Argon2 KDF of the Shield containers dominates startup cost) and then
    commits the parsed engines through TAnsiEngineManager.CommitPreload. The
    splash screen keeps painting while this thread runs; nothing here touches
    the UI. }
  TAnsiPreloadThread = class(TThread)
  private
    FItems: TArray<TPreloadItem>;
    FResults: TArray<TPreloadResult>;
    FNextJob: Integer;
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
  FLoader := TAnsiBackgroundLoadThread.Create;
end;

destructor TAnsiEngineManager.Destroy;
var
  Slot: TEngineSlot;
begin
  FLoader.Terminate;
  FLoader.WakeUp;
  FLoader.WaitFor;
  FLoader.Free;
  FLock.Enter;
  try
    // Globals may alias a slot. Detach before slot owners are destroyed.
    DetachActiveEngineState;
    FCurrentKey := '';
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

function TAnsiEngineManager.ParseJSONIntoSlot(const AName, AFilePath, AJSON: string;
  ErrorLog: TStringList = nil): Boolean;
var
  JSON: string;
  Slot: TEngineSlot;
begin
  Result := False;
  JSON := AJSON;

  // Strip a leading UTF-8 BOM if one survived.
  if (Length(JSON) >= 3) and (JSON[1] = #$EF) and (JSON[2] = #$BB) and
    (JSON[3] = #$BF) then
    Delete(JSON, 1, 3);
  if Trim(JSON) = '' then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: Mapping file is empty: ' + AName);
    Exit;
  end;

  try
    LoadAnsiMappingFromJSON(JSON, ErrorLog);
  except
    on E: Exception do
    begin
      if Assigned(ErrorLog) then
        ErrorLog.Add('Error: Mapping parse exception: ' + E.Message);
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
    Exit;
  end;
  if (Length(CustomFullForms) = 0) and (Length(CustomPreReplacements) = 0) and
    (Length(CustomPostReplacements) = 0) and (Length(VowelRules) = 0) and
    (Length(RfolaRules) = 0) and (Length(KarCorrections) = 0) and
    (Length(GroupKarCorrections) = 0) and
    ((AnsiOverrides = nil) or (AnsiOverrides.Count = 0)) then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: mapping contains no usable rules for ' + AName);
    Exit;
  end;

  Slot := TEngineSlot.Create;
  Slot.DisplayName := AName;
  Slot.FilePath := AFilePath;
  Slot.LastWriteTime := 0;
  if AFilePath <> '' then
    try
      Slot.LastWriteTime := TFile.GetLastWriteTime(AFilePath);
    except
      Slot.LastWriteTime := 0;
    end;
  CaptureEngineState(Slot.State);
  FCache.AddOrSetValue(SlotKey(AName), Slot);
  Result := True;
end;

function TAnsiEngineManager.ParseIntoSlot(const AName, AFilePath: string;
  ErrorLog: TStringList = nil; const APassword: AnsiString = ''): Boolean;
var
  JSON: string;
  Slot: TEngineSlot;
  UsePassword: AnsiString;
begin
  Result := False;

  // Built-in Default engine: the compiled-in mapping, no file involved.
  if AFilePath = '' then
  begin
    Slot := TEngineSlot.Create;
    Slot.DisplayName := AName;
    ResetAnsiToDefaults;
    CaptureEngineState(Slot.State);
    FCache.AddOrSetValue(SlotKey(AName), Slot);
    Result := True;
    Exit;
  end;

  if IsEncoFile(AFilePath) then
  begin
    // Decryption (Argon2) must never run on the UI thread. File parses
    // happen on the startup preload thread or, at runtime, in the
    // background worker + DrainBackgroundResults (main-thread commit). This
    // guard proves no file decrypt ever blocks the UI thread.
    if GetCurrentThreadId = MainThreadID then
      Log('WARNING: file decrypt on main thread! ' + AName);
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
  if FCurrentKey = '' then Exit;
  // Slots permanently own complete immutable states. Runtime globals are
  // merely aliases, so parking is allocation-free and never rebuilds the
  // ScalarValues dictionary on every switch.
  DetachActiveEngineState;
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
  Info: TAvroEncoFileInfo;
  Items: TList<TPreloadItem>;
  Item: TPreloadItem;
  Flag: Byte;
begin
  Items := TList<TPreloadItem>.Create;
  try
    FLock.Enter;
    try
      // Fallback: if the mapping index is empty (very first launch, folder
      // not yet scanned), build it now so the preload is never skipped.
      if (AvroEncoFiles = nil) or (AvroEncoFiles.Count = 0) then
        ScanAvroEncoFiles(AnsiMappingDir);
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
    Log('CapturePreloadList returned ' + IntToStr(Length(Result)) + ' items');
  finally
    Items.Free;
  end;
end;

function TAnsiEngineManager.CommitPreload(
  const AResults: TArray<TPreloadResult>): Integer;
var
  R: TPreloadResult;
  Err: TStringList;
  SavedKey: string;
  Committed: Integer;

  procedure CommitOne(const R: TPreloadResult);
  begin
    if not R.OK then
    begin
      Log('Engine preload failed: ' + R.DisplayName + ' - decryption');
      Exit;
    end;
    if FCache.ContainsKey(SlotKey(R.DisplayName)) then
      Exit;
    Err.Clear;
    if ParseJSONIntoSlot(R.DisplayName, R.FilePath, R.JSON, Err) then
      Inc(Committed)
    else
      Log('Engine preload failed: ' + R.DisplayName + ' - ' + Err.Text);
  end;

begin
  Result := 0;
  Committed := 0;
  FLock.Enter;
  try
    Err := TStringList.Create;
    try
      // 1. Built-in Default engine - always available, switchable in O(1).
      if not FCache.ContainsKey('default') then
      begin
        Err.Clear;
        ParseIntoSlot('Default', '', Err);
      end;
      // 2. Decrypted snapshot engines - the saved active version FIRST so it
      //    is ready as soon as possible, then the remaining engines.
      SavedKey := SlotKey(AnsiVersion);
      for R in AResults do
        if SlotKey(R.DisplayName) = SavedKey then
          CommitOne(R);
      for R in AResults do
        if SlotKey(R.DisplayName) <> SavedKey then
          CommitOne(R);
    finally
      Err.Free;
    end;
  finally
    FLock.Leave;
  end;
  Result := Committed;
  Log('Ansi preload committed ' + IntToStr(Committed) + ' engine(s), ' +
    IntToStr(Length(AResults)) + ' requested');
end;

function TAnsiEngineManager.SwitchEngine(const AName: string;
  ErrorLog: TStringList = nil; ALoadIfMissing: Boolean = True): Boolean;
var
  Key, Path: string;
  OwnErr: Boolean;
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
    // Idempotent: already active and cached.
    if (Key = FCurrentKey) and FCache.ContainsKey(Key) then
      Exit(True);

    // Load on demand. The built-in Default engine is file-less and cheap
    // (ResetAnsiToDefaults + capture) - safe on this thread. Anything else
    // (password engine never unlocked, or a file added at runtime) must NOT
    // be decrypted here: the Argon2 KDF would freeze the UI for seconds.
    // Defer to the background worker; the caller's pending-switch flow
    // applies it the moment it is cached.
    if not FCache.ContainsKey(Key) then
    begin
      if (Key = 'default') and ALoadIfMissing then
      begin
        if not ParseIntoSlot('Default', '', ErrorLog) then
          Exit;
      end
      else if ALoadIfMissing then
      begin
        // Runtime on-demand load (e.g. import): decrypt in the background
        // worker - the Argon2 KDF must never run on this thread. The caller
        // defers activation to the pending-switch flow.
        Path := GetActiveEncoFilePath(AName, AnsiMappingDir);
        if Path = '' then
        begin
          if Assigned(ErrorLog) then
            ErrorLog.Add('Mapping file not found: ' + AName);
          Exit;
        end;
        RequestBackgroundLoad(AName, Path);
        Exit;
      end
      else
        Exit; // caller defers activation to the pending-switch flow
    end;

    // O(1) engine swap: park current, restore target.
    ParkCurrent;
    ActivateEngineState(FCache[Key].State);
    FCurrentKey := Key;
    AnsiVersion := AName;
    Result := True;
  finally
    FLock.Leave;
    if OwnErr then
      ErrorLog.Free;
  end;
end;

function TAnsiEngineManager.CachedEngineCount: Integer;
begin
  FLock.Enter;
  try
    Result := FCache.Count;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.SetPendingSwitch(const AName: string);
var
  Key: string;
  Path: string;
begin
  Key := SlotKey(AName);
  Path := '';
  FLock.Enter;
  try
    if (FPendingSwitch <> '') and (FPendingSwitch = Key) then
      Exit; // already pending
    FPendingSwitch := Key;
    FPendingAttempts := 0;
    // The engine is not cached yet. Decrypt it in the background worker
    // (the watcher / poll may have missed it) - never on this thread. When
    // the worker's result is committed, the main form's timer applies the
    // switch automatically.
    if not FCache.ContainsKey(Key) then
      Path := GetActiveEncoFilePath(AName, AnsiMappingDir);
  finally
    FLock.Leave;
  end;
  if Path <> '' then
    RequestBackgroundLoad(AName, Path);
end;

function TAnsiEngineManager.TryApplyPendingSwitch(
  out AAppliedName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  AAppliedName := '';
  if not FLock.TryEnter then
    Exit;
  try
    if FPendingSwitch = '' then
      Exit;
    if not FCache.ContainsKey(FPendingSwitch) then
    begin
      Inc(FPendingAttempts);
      if FPendingAttempts > 50 then
        FPendingSwitch := ''; // ~5 s of failures: give up (corrupt engine)
      Exit;
    end;
    Key := FPendingSwitch;
    FPendingSwitch := '';
    FPendingAttempts := 0;
    // O(1) RAM-only switch - identical to TrySwitchCached.
    if Key <> FCurrentKey then
    begin
      ParkCurrent;
      ActivateEngineState(FCache[Key].State);
      FCurrentKey := Key;
    end;
    AnsiVersion := FCache[Key].DisplayName;
    AAppliedName := FCache[Key].DisplayName;
    Result := True;
    Log('Ansi pending switch applied: ' + AAppliedName);
  finally
    FLock.Leave;
  end;
end;

function TAnsiEngineManager.TrySwitchCached(const AName: string): Boolean;
var
  Key: string;
begin
  Result := False;
  Key := SlotKey(AName);
  if Key = '' then Exit;

  // A picker/menu click must never wait behind parser/refresh work.
  if not FLock.TryEnter then Exit;
  try
    if (Key = FCurrentKey) and FCache.ContainsKey(Key) then Exit(True);
    if not FCache.ContainsKey(Key) then
    begin
      Log('Ansi switch MISS (not cached): ' + AName);
      Exit;
    end;
    ParkCurrent;
    ActivateEngineState(FCache[Key].State);
    FCurrentKey := Key;
    AnsiVersion := AName;
    Result := True;
  finally
    FLock.Leave;
  end;
end;

procedure TAnsiEngineManager.WarmAllEngines(const AReturnTo: string);
var
  Keys: TList<string>;
  Key, ReturnKey: string;
begin
  ReturnKey := SlotKey(AReturnTo);
  FLock.Enter;
  try
    Keys := TList<string>.Create;
    try
      for Key in FCache.Keys do Keys.Add(Key);
      // Exercise every park/restore path before the keyboard hook starts.
      for Key in Keys do
        if (Key <> FCurrentKey) and FCache.ContainsKey(Key) then
        begin
          ParkCurrent;
          ActivateEngineState(FCache[Key].State);
          FCurrentKey := Key;
        end;
      if (ReturnKey <> FCurrentKey) and FCache.ContainsKey(ReturnKey) then
      begin
        ParkCurrent;
        ActivateEngineState(FCache[ReturnKey].State);
        FCurrentKey := ReturnKey;
      end;
      AnsiVersion := AReturnTo;
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
  Slot: TEngineSlot;
  WasActive: Boolean;
begin
  Key := SlotKey(AName);
  if not FCache.TryGetValue(Key, Slot) then
  begin
    // Not cached - nothing to invalidate; the file is picked up by the
    // watcher/poll and loaded in the background if it exists.
    Exit;
  end;
  Path := Slot.FilePath;
  if (Path <> '') and (not FileExists(Path)) then
  begin
    DropSlot(Key); // file is gone - treat as removed
    Exit;
  end;

  WasActive := (Key = FCurrentKey);
  DropSlot(Key);

  if WasActive then
  begin
    // Never leave the app without a working engine: fall back to Default
    // NOW (RAM-only) and re-activate automatically once the background
    // worker commits the re-parsed engine (pending-switch flow).
    if FCache.ContainsKey('default') then
    begin
      ActivateEngineState(FCache['default'].State);
      FCurrentKey := 'default';
      AnsiVersion := 'Default';
    end;
    if FPendingSwitch = '' then
    begin
      FPendingSwitch := Key;
      FPendingAttempts := 0;
    end;
  end;
  // Decrypt/parse in the background - never on this thread.
  if Path <> '' then
    RequestBackgroundLoad(AName, Path);
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
  Key, Name: string;
  Slot: TEngineSlot;
  Info: TAvroEncoFileInfo;
  NewTime: TDateTime;
  Keys: TList<string>;
  Loads: TList<TBackgroundLoadItem>;
  Item: TBackgroundLoadItem;
begin
  Loads := TList<TBackgroundLoadItem>.Create;
  FLock.Enter;
  try
    // 1. Drop cached engines whose file disappeared (never the active one).
    Keys := TList<string>.Create;
    try
      for Key in FCache.Keys do
        Keys.Add(Key);
      for Key in Keys do
      begin
        if Key = 'default' then
          Continue;
        if FCache.TryGetValue(Key, Slot) and (Slot.FilePath <> '') and
          (not FileExists(Slot.FilePath)) then
        begin
          if Key = FCurrentKey then
            Continue; // active engine: keep; the delete flow switches away
          DropSlot(Key);
        end;
      end;
    finally
      Keys.Free;
    end;

    // 2. Changed engines are invalidated (dropped + background re-load);
    //    newly added engines (default-key / plain .json only) are queued
    //    for background loading. NO decrypt or parse happens here.
    if Assigned(AvroEncoFiles) then
      for Info in AvroEncoFiles.Values do
      begin
        if Info.IsEncoFile and
          (GetAvroEncoProtectionFlag(Info.FilePath) <> AVROENCO_FLAG_DEFAULT_KEY) then
          Continue;
        Name := Info.DisplayName;
        Key := SlotKey(Name);
        if FCache.TryGetValue(Key, Slot) then
        begin
          try
            NewTime := TFile.GetLastWriteTime(Info.FilePath);
          except
            NewTime := 0;
          end;
          if Abs(NewTime - Slot.LastWriteTime) > 0.000001 then
            DoInvalidateEngine(Name);
        end
        else
        begin
          Item.DisplayName := Name;
          Item.FilePath := Info.FilePath;
          Item.Password := '';
          Loads.Add(Item);
        end;
      end;
  finally
    FLock.Leave;
  end;
  try
    for Item in Loads do
      FLoader.Enqueue(Item);
  finally
    Loads.Free;
  end;
end;

procedure TAnsiEngineManager.RequestBackgroundLoad(const AName, AFilePath: string;
  const APassword: AnsiString = '');
var
  Item: TBackgroundLoadItem;
begin
  Item.DisplayName := AName;
  Item.FilePath := AFilePath;
  Item.Password := APassword;
  FLoader.Enqueue(Item);
end;

function TAnsiEngineManager.DrainBackgroundResults: Integer;
var
  Results: TArray<TPreloadResult>;
  R: TPreloadResult;
  Err: TStringList;
begin
  Result := 0;
  Results := FLoader.DrainResults;
  if Length(Results) = 0 then
    Exit;
  Err := TStringList.Create;
  FLock.Enter;
  try
    for R in Results do
    begin
      if FCache.ContainsKey(SlotKey(R.DisplayName)) then
        Continue; // already committed (preload beat the worker)
      Err.Clear;
      if ParseJSONIntoSlot(R.DisplayName, R.FilePath, R.JSON, Err) then
        Inc(Result)
      else
        Log('Background load failed: ' + R.DisplayName + ' - ' + Err.Text);
    end;
    // Parsing above replaced the globals with the parsed engine's state.
    // The keyboard hook reads those globals directly, so re-activate the
    // CURRENT engine (RAM-only) - this also fixes the historical case where
    // a refresh of a non-active engine left the runtime state clobbered.
    if (FCurrentKey <> '') and FCache.ContainsKey(FCurrentKey) then
      ActivateEngineState(FCache[FCurrentKey].State);
  finally
    FLock.Leave;
    Err.Free;
  end;
  if Result > 0 then
    Log('DrainBackgroundResults committed ' + IntToStr(Result) + ' engine(s)');
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
  TAnsiBackgroundLoadThread - runtime decrypt worker.

  Watcher-triggered re-loads, auto-refreshes and on-demand engine loads all
  decrypt (Argon2 for .AvroEnco containers) HERE, off the UI thread. The
  parsed JSON is queued back; the MAIN thread commits it through
  TAnsiEngineManager.DrainBackgroundResults (the parser mutates the engine
  globals the keyboard hook reads, so parse stays on the typing thread).
  ============================================================================= }

constructor TAnsiBackgroundLoadThread.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FQueue := TList<TBackgroundLoadItem>.Create;
  FQueueLock := TCriticalSection.Create;
  FResults := TList<TPreloadResult>.Create;
  FResultsLock := TCriticalSection.Create;
  FEvent := TEvent.Create(nil, False, False, '');
end;

destructor TAnsiBackgroundLoadThread.Destroy;
begin
  FEvent.Free;
  FQueueLock.Free;
  FQueue.Free;
  FResultsLock.Free;
  FResults.Free;
  inherited Destroy;
end;

procedure TAnsiBackgroundLoadThread.Enqueue(const AItem: TBackgroundLoadItem);
begin
  FQueueLock.Enter;
  try
    FQueue.Add(AItem);
  finally
    FQueueLock.Leave;
  end;
  FEvent.SetEvent;
end;

function TAnsiBackgroundLoadThread.PopItem(
  out Item: TBackgroundLoadItem): Boolean;
begin
  Result := False;
  FQueueLock.Enter;
  try
    if FQueue.Count > 0 then
    begin
      Item := FQueue[0];
      FQueue.Delete(0);
      Result := True;
    end;
  finally
    FQueueLock.Leave;
  end;
end;

function TAnsiBackgroundLoadThread.DrainResults: TArray<TPreloadResult>;
var
  I: Integer;
begin
  Result := nil;
  FResultsLock.Enter;
  try
    if FResults.Count > 0 then
    begin
      SetLength(Result, FResults.Count);
      for I := 0 to FResults.Count - 1 do
        Result[I] := FResults[I];
      FResults.Clear;
    end;
  finally
    FResultsLock.Leave;
  end;
end;

procedure TAnsiBackgroundLoadThread.WakeUp;
begin
  FEvent.SetEvent;
end;

procedure TAnsiBackgroundLoadThread.Execute;
var
  Item: TBackgroundLoadItem;
  R: TPreloadResult;
begin
  while not Terminated do
  begin
    // Wait for work; the 100 ms timeout also covers termination checks.
    FEvent.WaitFor(100);
    while PopItem(Item) do
    begin
      R.DisplayName := Item.DisplayName;
      R.FilePath := Item.FilePath;
      R.JSON := '';
      R.OK := False;
      try
        if IsEncoFile(Item.FilePath) then
          R.OK := LoadAnsiJSONCached(Item.FilePath, Item.Password, R.JSON) and
            (R.JSON <> '') and (R.JSON[1] = '{')
        else
          R.OK := LoadAnsiJSONCached(Item.FilePath, '', R.JSON) and
            (Trim(R.JSON) <> '');
      except
        R.OK := False;
      end;
      FResultsLock.Enter;
      try
        FResults.Add(R);
      finally
        FResultsLock.Leave;
      end;
    end;
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
  R: TPreloadResult;
  Item: TPreloadItem;
begin
  Item := FItems[Index];
  R.DisplayName := Item.DisplayName;
  R.FilePath := Item.FilePath;
  R.JSON := '';
  R.OK := False;
  try
    if IsEncoFile(Item.FilePath) then
    begin
      // Shield/legacy containers: pure crypto, no shared state - safe to run
      // on worker threads. Default-key containers ignore the password;
      // cached-password containers decrypt with the persisted password.
      R.OK := LoadAnsiJSONCached(Item.FilePath, Item.Password, R.JSON) and
        (R.JSON <> '') and (R.JSON[1] = '{');
    end
    else
    begin
      R.OK := LoadAnsiJSONCached(Item.FilePath, '', R.JSON) and
        (Trim(R.JSON) <> '');
    end;
  except
    R.OK := False;
  end;
  FResultLock.Enter;
  try
    FResults[Index] := R;
  finally
    FResultLock.Leave;
  end;
end;

procedure TAnsiPreloadThread.ParallelDecrypt;
var
  WorkerCount, I, Next: Integer;
  Workers: TArray<TThread>;
begin
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
  I, N: Integer;
  Completed: TArray<TPreloadResult>;
begin
  Log('Preload thread started, items=' + IntToStr(Length(FItems)));
  try
    if Length(FItems) = 0 then
      Exit;
    ParallelDecrypt;

    N := 0;
    for I := 0 to Length(FItems) - 1 do
      if FResults[I].OK then
        Inc(N);
    Log('Preload decrypt OK=' + IntToStr(N));
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
    // Warm every parked engine while the hook is still removed: pays all
    // first-use allocations/page faults before the user can open the
    // picker, without ever touching the UI thread.
    AnsiEngineManager.WarmAllEngines(AnsiVersion);
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
