(*
  uAvroMigrationRunner.pas - the ACTING half of migration auto-heal.

  WHAT IT DOES, IN ORDER
  ----------------------
  1. Probes the default-key containers on disk. If every one of them opens, it
     stops here - no network request is made at all, which is the common case.
  2. Fetches manifest.json and verifies its Ed25519 signature. An unverified
     manifest authorises nothing, so a fetch that fails just leaves the local
     containers alone.
  3. For each container that will not open, asks uAvroMigrationPlan for a plan.
     The baseline is activated only for the LIVE engine, and only immediately -
     before any download is attempted - so typing never degrades to Unicode while
     a repair is in flight.
  4. Re-fetches the signed, hash-pinned replacement at most once per item per
     24 hours, then hands the engine cache back the new file.

  WHY NOTHING IS EVER DECRYPTED TO DISK
  -------------------------------------
  The replacement is downloaded to a temp file, checked against the sha256 the
  SIGNED manifest pins, and only then moved into place. It stays an encrypted
  container at every point: this unit never writes, logs or caches plaintext, and
  the only plaintext it ever holds is the decrypted mapping the engine itself
  needs, wiped by the engine. That property is asserted by kat_migration.

  WHAT IT DELIBERATELY DOES NOT DO
  --------------------------------
  No telemetry, no analytics, no "report this failure" call. A repair attempt is
  recorded in a local JSON file so the 24-hour window survives a restart, and
  that file is the only place an attempt is ever written down.
*)

unit uAvroMigrationRunner;

interface

{ Starts the check on a background thread. Returns immediately, and is safe to
  call on every startup: with nothing stale it costs one directory scan and makes
  no network request. Re-entrant calls while a check is already running are
  ignored. }
procedure AvroMigrationCheckAsync;

{ A one-line, user-facing status from the most recent repair (e.g. "Repaired
  Ansi V2 from the signed manifest."). Posted from the background thread and
  TAKEN - that is, cleared - by whoever displays it, so a note is shown once. }
procedure AvroMigrationPostNote(const AText: string);
function AvroMigrationTakeNote: string;

{ The same note, ready to append to a status line: '' when there is nothing to
  say, otherwise the note with a leading space. Lets a caller append without
  needing a local variable inside a closure. }
function AvroMigrationNoteSuffix: string;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  Vcl.Forms,
  uAvroMigrationPlan,
  uAvroManifest,
  uResourceTrust,
  uResourceInstaller,
  uAvroEncoCrypto,
  uAnsiEngineManager,
  uFileFolderHandling,
  clsFileVersion,
  DebugLog;

const
  { The IKM epoch this build was compiled for. tools\secrets\rotate_ikm.ps1 bumps
    it in lockstep with resources.lock.json and the manifest; a mismatch against
    the signed manifest is what tells the planner that a container is stale after
    a rotation rather than corrupt. }
  AVRO_APP_KEY_EPOCH = 2;

  { The manifest's resource type for the ANSI mappings, which is also the key
    uResourceInstaller.ResourceTargetFolder resolves the destination from. }
  ANSI_RESOURCE_TYPE = 'ansimapping';

  STATE_FILE_NAME = 'AvroMigration.json';

var
  NoteLock:     TCriticalSection;
  PendingNote:  string;
  CheckRunning: Boolean;

function StatePath: string;
begin
  Result := '';
  try
    if GetAvroDataDir <> '' then
      Result := GetAvroDataDir + STATE_FILE_NAME;
  except
    Result := '';
  end;
end;

{ The application version a manifest's minAppVersion column is compared against.
  Read from the executable's own version resource, exactly as the resource
  browser does, so the two never disagree. }
function AppVersionString: string;
var
  V: TFileVersion;
begin
  Result := '';
  V := TFileVersion.Create;
  try
    Result := V.AsString;
  finally
    V.Free;
  end;
end;

procedure AvroMigrationPostNote(const AText: string);
begin
  if Trim(AText) = '' then
    Exit;
  NoteLock.Enter;
  try
    PendingNote := AText;
  finally
    NoteLock.Leave;
  end;
end;

function AvroMigrationTakeNote: string;
begin
  NoteLock.Enter;
  try
    Result := PendingNote;
    PendingNote := '';
  finally
    NoteLock.Leave;
  end;
end;

function AvroMigrationNoteSuffix: string;
begin
  Result := AvroMigrationTakeNote;
  if Result <> '' then
    Result := ' ' + Result;
end;

{ True when the container on disk decrypts with the key this build carries. The
  runtime loader collapses a wrong key and a damaged file into the same opaque
  failure - on purpose, see uAvroShield - so both are reported as "not
  decryptable" and the planner falls back to the signed epoch to tell a rotation
  from corruption. }
function ContainerOpens(const APath: string): Boolean;
var
  Json: string;
begin
  Json := '';
  try
    Json := Trim(DecryptAvroEncoToString(APath, ''));
  except
    Json := '';
  end;
  Result := (Json <> '') and (Json[1] = '{');
end;

{ True when this container needs the root secret at all. A password-protected
  container is unaffected by an IKM rotation, so it is never probed and never
  repaired. }
function IsDefaultKeyContainer(const APath: string): Boolean;
begin
  try
    Result := GetAvroEncoProtectionFlag(APath) = AVROENCO_FLAG_DEFAULT_KEY;
  except
    Result := False;
  end;
end;

{ The two main-thread actions below are their own procedures on purpose. An
  anonymous method captures its enclosing variables BY REFERENCE, so queueing a
  closure from inside a loop that reuses one local string would let a later
  iteration change the text of an earlier, not-yet-run note. A parameter of its
  own procedure has one frame per call, so each queued closure keeps the values
  it was created with. }
procedure ActivateBaselineAsync;
begin
  TThread.Queue(nil,
    procedure
    begin
      if not Application.Terminated then
        AnsiEngineManager.ActivateEmbeddedBaseline;
    end);
end;

procedure PostRepairedAsync(const AName: string);
begin
  TThread.Queue(nil,
    procedure
    begin
      if Application.Terminated then
        Exit;
      // Queued to the main thread, like every other engine mutation: the cache
      // is guarded, but the UI reads it too.
      AnsiEngineManager.InvalidateEngine(AName);
      AnsiEngineManager.RefreshFromDisk;
      AvroMigrationPostNote('Repaired ' + AName + ' from the signed manifest.');
    end);
end;

type
  TAvroMigrationThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure TAvroMigrationThread.Execute;
var
  Root, MappingDir, Err: string;
  Files: TArray<string>;
  Trust: TResourceTrust;
  Gate: TAvroRefetchGate;
  Probe: TAvroContainerProbe;
  Plan: TAvroHealPlan;
  Pin: TAvroResource;
  Reason, TargetPath, ItemKey, DisplayName, FileName: string;
  ActiveName, ResourceType, AppVersion: string;
  AppEpoch: Integer;
  StaleFound: Boolean;
  I: Integer;
  NowStamp: TDateTime;
begin
  try
    Root := '';
    try
      Root := GetAvroDataDir;
    except
      Root := '';
    end;
    if Root = '' then
      Exit;
    MappingDir := IncludeTrailingPathDelimiter(Root) + 'AnsiMapping';
    if not TDirectory.Exists(MappingDir) then
      Exit;

    Files := TDirectory.GetFiles(MappingDir, '*.AvroEnco');
    if Length(Files) = 0 then
      Exit;

    // Step 1: probe locally, before touching the network. Only a container that
    // needs the IKM can be affected by a rotation.
    StaleFound := False;
    for I := 0 to Length(Files) - 1 do
    begin
      if Terminated then
        Exit;
      if not IsDefaultKeyContainer(Files[I]) then
        Continue;
      if not ContainerOpens(Files[I]) then
      begin
        StaleFound := True;
        Break;
      end;
    end;

    // Nothing broken: no manifest fetch, no network, no log line, no state write.
    if not StaleFound then
      Exit;

    Trust := TResourceTrust.Create;
    Gate := TAvroRefetchGate.Create;
    try
      Gate.Load(StatePath);

      // Step 2: the trust document. Nothing below runs on an unverified manifest.
      if not Trust.Fetch(TResourceTrust.DefaultManifestUrl, Err) then
      begin
        Log('Migration: manifest not trusted, leaving local containers alone - ' + Err);
        Exit;
      end;

      ActiveName := '';
      try
        ActiveName := AnsiEngineManager.CurrentEngineName;
      except
        ActiveName := '';
      end;
      AppVersion := AppVersionString;
      AppEpoch := AVRO_APP_KEY_EPOCH;
      NowStamp := Now;

      for I := 0 to Length(Files) - 1 do
      begin
        if Terminated then
          Exit;
        if not IsDefaultKeyContainer(Files[I]) then
          Continue;

        FileName := ExtractFileName(Files[I]);
        DisplayName := ChangeFileExt(FileName, '');

        if not AvroProbeFromManifest(Trust.Manifest, FileName, AppEpoch, SameText(DisplayName, ActiveName), True,
          ContainerOpens(Files[I]), False, Probe) then
          Continue; // not managed by the signer - not ours to repair

        Plan := AvroPlanHeal(Probe);
        if Plan.Action = ahaNone then
          Continue;

        Log(Format('Migration: "%s" -> %s (%s)', [FileName, AvroHealActionText(Plan.Action), Plan.Reason]));

        // Step 3: serve ANSI NOW, in the same breath as the diagnosis chain -
        // before the download is even considered.
        if Plan.ActivateBaseline then
          ActivateBaselineAsync;

        if not Plan.EnqueueRefetch then
          Continue;

        // Step 4: the throttled re-fetch.
        ItemKey := LowerCase(FileName);
        if not Gate.ShouldAttempt(ItemKey, NowStamp) then
        begin
          Log('Migration: "' + FileName + '" was already attempted within ' + IntToStr(AVRO_REFETCH_WINDOW_HOURS) + 'h');
          Continue;
        end;

        // The pin comes from the SAME verified manifest that authorised the plan,
        // so both the URL and the hash are signed data. The empty catalog hash
        // means "the catalog makes no claim", which is true on this path - the
        // browser is not involved.
        if not Trust.ResolveItem(FileName, '', AppVersion, ResourceAppFormatVersion, Pin, Reason) then
        begin
          // Recorded either way: a refusal will not heal itself by being retried
          // on every launch.
          Gate.RecordAttempt(ItemKey, NowStamp);
          Log('Migration: refusing to re-fetch "' + FileName + '": ' + Reason);
          Continue;
        end;

        ResourceType := Pin.Category;
        if Trim(ResourceType) = '' then
          ResourceType := ANSI_RESOURCE_TYPE;

        Gate.RecordAttempt(ItemKey, NowStamp);

        if DownloadAndInstallResource(Pin.Url, Pin.FileName, ResourceType, Pin.Sha256, nil, Err, TargetPath) then
        begin
          Log('Migration: repaired "' + FileName + '" from the signed manifest');
          PostRepairedAsync(DisplayName);
        end
        else
          Log('Migration: re-fetch of "' + FileName + '" failed - ' + Err);
      end;

      Gate.Save(StatePath);
    finally
      Gate.Free;
      Trust.Free;
    end;
  except
    // A background repair must never be able to take the application down, and it
    // must never surface an exception dialog: the user did not ask for it.
    on E: Exception do
      Log('Migration: aborted - ' + E.ClassName + ': ' + E.Message);
  end;
end;

procedure AvroMigrationCheckAsync;
var
  WasRunning: Boolean;
  Worker: TAvroMigrationThread;
begin
  NoteLock.Enter;
  try
    WasRunning := CheckRunning;
    CheckRunning := True;
  finally
    NoteLock.Leave;
  end;

  if WasRunning then
    Exit;

  Worker := TAvroMigrationThread.Create(True);
  Worker.FreeOnTerminate := True;
  Worker.Start;
end;

initialization
  NoteLock := TCriticalSection.Create;
  PendingNote := '';
  CheckRunning := False;

finalization
  NoteLock.Free;

end.
