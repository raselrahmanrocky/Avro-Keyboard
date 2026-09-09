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

  TAnsiEngineManager = class
  private
    FCache: TDictionary<string, TEngineSlot>; // key: Lowercase(DisplayName)
    FCurrentKey: string;
    FLock: TCriticalSection; // serializes every engine-state mutation
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
      protected, never unlocked before) are parsed once here. Returns False
      on failure - the previously active engine stays untouched. }
    function SwitchEngine(const AName: string;
      ErrorLog: TStringList = nil): Boolean;
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
  uAvroEncoManager,
  uAvroEncoCrypto,
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
    // Default-key containers decrypt transparently (password ignored);
    // password containers decrypt with the caller-supplied password or, on
    // the on-demand path, with the session-wide CachedEncoPassword global,
    // which the caller (version picker / menu) sets BEFORE switching. This
    // never prompts.
    UsePassword := APassword;
    if UsePassword = '' then
      UsePassword := CachedEncoPassword;
    JSON := Trim(DecryptAvroEncoToString(AFilePath, UsePassword));
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
      JSON := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
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
var
  Slot: TEngineSlot;
begin
  if FCurrentKey = '' then
    Exit;
  if FCache.TryGetValue(FCurrentKey, Slot) then
    CaptureEngineState(Slot.State);
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

function TAnsiEngineManager.CommitPreload(
  const AResults: TArray<TPreloadResult>): Integer;
var
  R: TPreloadResult;
  Err: TStringList;
begin
  Result := 0;
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
      // 2. Every decrypted snapshot engine.
      for R in AResults do
      begin
        if not R.OK then
        begin
          Log('Engine preload failed: ' + R.DisplayName + ' - decryption');
          Continue;
        end;
        if FCache.ContainsKey(SlotKey(R.DisplayName)) then
          Continue;
        Err.Clear;
        if ParseJSONIntoSlot(R.DisplayName, R.FilePath, R.JSON, Err) then
          Inc(Result)
        else
          Log('Engine preload failed: ' + R.DisplayName + ' - ' + Err.Text);
      end;
    finally
      Err.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

function TAnsiEngineManager.SwitchEngine(const AName: string;
  ErrorLog: TStringList = nil): Boolean;
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

    // Load on demand (password-protected engine or file added at runtime).
    if not FCache.ContainsKey(Key) then
    begin
      if Key = 'default' then
        Path := ''
      else
        Path := GetActiveEncoFilePath(AName, AnsiMappingDir);
      if (Path = '') and (Key <> 'default') then
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Mapping file not found: ' + AName);
        Exit;
      end;
      if not ParseIntoSlot(AName, Path, ErrorLog) then
        Exit;
    end;

    // O(1) engine swap: park current, restore target.
    ParkCurrent;
    RestoreEngineState(FCache[Key].State);
    FCurrentKey := Key;
    AnsiVersion := AName;
    Result := True;
  finally
    FLock.Leave;
    if OwnErr then
      ErrorLog.Free;
  end;
end;

procedure TAnsiEngineManager.DoInvalidateEngine(const AName: string);
var
  Key, Path: string;
  WasActive: Boolean;
  Err: TStringList;
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
      if WasActive then
      begin
        // Never leave the app without a working engine: fall back to Default.
        if FCache.ContainsKey('default') then
        begin
          RestoreEngineState(FCache['default'].State);
          FCurrentKey := 'default';
          AnsiVersion := 'Default';
        end;
      end;
      Exit;
    end;
    if WasActive then
    begin
      RestoreEngineState(FCache[Key].State);
      AnsiVersion := AName;
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
  Key: string;
  Slot: TEngineSlot;
  Info: TAvroEncoFileInfo;
  Name: string;
  NewTime: TDateTime;
  Keys: TList<string>;
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

    // 2. Re-parse changed engines, preload newly added ones (default-key /
    //    plain .json only; password engines stay lazy).
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
          ParseIntoSlot(Name, Info.FilePath, nil);
      end;
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
      R.JSON := Trim(DecryptAvroEncoToString(Item.FilePath, Item.Password));
      R.OK := (R.JSON <> '') and (R.JSON[1] = '{');
    end
    else
    begin
      R.JSON := TFile.ReadAllText(Item.FilePath, TEncoding.UTF8);
      R.OK := Trim(R.JSON) <> '';
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
