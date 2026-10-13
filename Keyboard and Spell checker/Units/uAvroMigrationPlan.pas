(*
  uAvroMigrationPlan.pas - the DECISION half of migration auto-heal.

  WHY
  ---
  A managed container can stop opening for two very different reasons, and the
  whole point of this unit is to tell them apart without a network, a file handle
  or a running engine - so every branch is a pure function a gate can drive:

    corruption   the on-disk copy is the epoch this build was compiled for, and
                 it still will not open. The bytes are damaged.
    rotation     the signed manifest pins a DIFFERENT epoch, so the copy on disk
                 was written for a key this build no longer has.

  Both heal the same way, but only the second is expected after an IKM rotation,
  and a plan that could not distinguish them would report every corrupt download
  as a rotation. The epoch comes from the signed manifest (uAvroManifest): the
  container format itself carries no key id, which is exactly why the signer has
  to state one.

  WHAT ACTIVATES THE BASELINE
  ---------------------------
  Only when the container in question is the LIVE engine. For any other slot
  another engine is already typing, and dropping the compiled-in baseline into
  the globals would change the user's engine behind their back - the opposite of
  "typing must never degrade". That is also why baseline activation is decided
  here rather than inside the healing code: it is a policy question, and policy
  belongs where it can be tested.

  NO NETWORK, NO PLAINTEXT
  ------------------------
  Nothing here downloads, installs, decrypts or writes. It answers a question;
  uAvroMigrationRunner acts on the answer.
*)

unit uAvroMigrationPlan;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  uAvroManifest;

type
  { Why a managed container is not serving. ascFresh means it is serving. }
  TAvroStaleCause = (
    ascFresh,
    ascAbsent,
    ascDecryptFailed,
    ascMacFailed,
    ascEpochMismatch);

  { What the caller should do about it. }
  TAvroHealAction = (
    ahaNone,              // healthy, unmanaged, or nothing to do
    ahaInstall,           // managed but absent -> fetch it
    ahaBaselineAndRefetch,// stale on disk -> serve now AND fetch a replacement
    ahaBlocked);          // no downloadable replacement exists

  { Everything the decision needs about ONE container, as plain data.

    MacValid is separate from Decryptable on purpose. The RUNTIME loader collapses
    every failure into one opaque result code - a deliberate anti-oracle measure
    documented in uAvroShield - so a runtime probe reports both from the same
    attempt. Keeping the two fields apart means the plan can still model a bearer
    that CAN distinguish them (the builder, a KAT, a future format with a real MAC
    result), instead of hardcoding the runtime's opacity into the policy. }
  TAvroContainerProbe = record
    Managed:         Boolean; // the signed manifest pins this file
    IsActiveEngine:  Boolean; // it is the engine currently typing
    OnDisk:          Boolean;
    Decryptable:     Boolean; // opened with the key this build carries
    MacValid:        Boolean;
    AppEpoch:        Integer; // the epoch this build was compiled for (0 = unknown)
    ManifestEpoch:   Integer; // the epoch the signed manifest pins (0 = unstated)
    RefetchPossible: Boolean; // the manifest pins BOTH a sha256 and a url
  end;

  TAvroHealPlan = record
    Action:           TAvroHealAction;
    Cause:            TAvroStaleCause;
    ActivateBaseline: Boolean;
    EnqueueRefetch:   Boolean;
    ReplaceOnSuccess: Boolean;
    { One line of LOCAL context for the log. Never sent anywhere: the whole point
      of this design is that a repair leaves no trace off the machine. }
    Reason:           string;
  end;

{ The decision. Pure: same probe in, same plan out, with no I/O. }
function AvroPlanHeal(const AProbe: TAvroContainerProbe): TAvroHealPlan;

{ Builds a probe from a VERIFIED manifest plus what the caller already knows
  locally. Returns False when the manifest does not pin AFileName at all, which
  is the caller's signal that this file is not managed and needs no healing.

  Does not verify the signature - the caller must hand in a manifest that came
  from uAvroManifest.AvroManifestLoadAndVerify or TResourceTrust. }
function AvroProbeFromManifest(const AManifest: TAvroManifest; const AFileName: string;
  AAppEpoch: Integer; AIsActiveEngine, AOnDisk, ADecryptable, AMacValid: Boolean;
  out AProbe: TAvroContainerProbe): Boolean;

function AvroHealActionText(const AAction: TAvroHealAction): string;
function AvroStaleCauseText(const ACause: TAvroStaleCause): string;

const
  { At most one refetch attempt per item per window. An offline user must not
    turn every launch into a retry storm, and a resource repository that is down
    must not be hammered by a client that has nothing else to do. }
  AVRO_REFETCH_WINDOW_HOURS = 24;

type
  { The backoff clock. Kept separate from the plan so the throttle is testable
    without waiting a day: the caller passes "now". }
  TAvroRefetchGate = class
  private
    FStamps: TDictionary<string, TDateTime>;
  public
    constructor Create;
    destructor Destroy; override;

    { True when AItemKey may be attempted now. An unknown item is always allowed
      (first attempt); a known one only once the window has passed. }
    function ShouldAttempt(const AItemKey: string; const ANow: TDateTime): Boolean;

    { Records that an attempt HAPPENED, success or failure. Recording attempts,
      not successes, is what makes the window a real throttle: a fetch that keeps
      failing would otherwise retry on every launch. }
    procedure RecordAttempt(const AItemKey: string; const ANow: TDateTime);

    procedure Forget(const AItemKey: string);
    procedure Clear;
    function Count: Integer;

    { State persistence. A corrupt or absent file is a clean slate, never an
      error: losing the throttle must not be able to block a repair. }
    procedure Save(const APath: string);
    procedure Load(const APath: string);
  end;

implementation

uses
  System.JSON,
  System.IOUtils,
  System.DateUtils;

{ ---------------------------------------------------------------------------
  The decision
  --------------------------------------------------------------------------- }

function AvroPlanHeal(const AProbe: TAvroContainerProbe): TAvroHealPlan;
begin
  Result := Default(TAvroHealPlan);
  Result.Action := ahaNone;
  Result.Cause := ascFresh;

  // Not listed by the signer: the application does not manage this file, so it
  // has no opinion about it and must not touch it. A user's own hand-made
  // mapping is the important case.
  if not AProbe.Managed then
  begin
    Result.Reason := 'not managed by the signed manifest';
    Exit;
  end;

  // Opening normally is the end of the question - even if the epochs differ. The
  // epoch is a hint about what SHOULD be there, not a licence to replace a file
  // that demonstrably works.
  if AProbe.OnDisk and AProbe.Decryptable and AProbe.MacValid then
  begin
    Result.Cause := ascFresh;
    Result.Reason := 'opens normally';
    Exit;
  end;

  // Not serving. Classify the cause.
  if not AProbe.OnDisk then
    Result.Cause := ascAbsent
  else if (AProbe.AppEpoch > 0) and (AProbe.ManifestEpoch > 0) and (AProbe.ManifestEpoch <> AProbe.AppEpoch) then
    // The signed manifest says this file belongs to another key epoch, so the
    // expected cause is a rotation rather than damage.
    Result.Cause := ascEpochMismatch
  else if not AProbe.Decryptable then
    Result.Cause := ascDecryptFailed
  else
    Result.Cause := ascMacFailed;

  // Serving ANSI right now only matters when this container IS the live engine.
  Result.ActivateBaseline := AProbe.IsActiveEngine;

  if not AProbe.RefetchPossible then
  begin
    // Nothing to fetch (or no signed URL to fetch it from). Still activate the
    // baseline when this is the live engine: keeping Unicode-only typing out of
    // the user's way is worth it even with no repair available.
    Result.Action := ahaBlocked;
    Result.Reason := AvroStaleCauseText(Result.Cause) + '; no downloadable replacement is pinned';
    Exit;
  end;

  Result.EnqueueRefetch := True;
  Result.ReplaceOnSuccess := True;
  if AProbe.OnDisk then
    Result.Action := ahaBaselineAndRefetch
  else
    Result.Action := ahaInstall;
  Result.Reason := AvroStaleCauseText(Result.Cause) + '; re-fetch enqueued';
end;

function AvroProbeFromManifest(const AManifest: TAvroManifest; const AFileName: string;
  AAppEpoch: Integer; AIsActiveEngine, AOnDisk, ADecryptable, AMacValid: Boolean;
  out AProbe: TAvroContainerProbe): Boolean;
var
  Res: TAvroResource;
begin
  Result := False;
  AProbe := Default(TAvroContainerProbe);

  // Everything the caller already observed, before the manifest is consulted.
  AProbe.IsActiveEngine := AIsActiveEngine;
  AProbe.OnDisk := AOnDisk;
  AProbe.Decryptable := ADecryptable;
  AProbe.MacValid := AMacValid;
  AProbe.AppEpoch := AAppEpoch;
  AProbe.Managed := False;
  AProbe.ManifestEpoch := 0;
  AProbe.RefetchPossible := False;

  if AManifest = nil then
    Exit;

  if not AvroManifestFindByFileName(AManifest, AFileName, Res) then
    Exit;

  AProbe.Managed := True;
  AProbe.ManifestEpoch := Res.KeyEpoch;
  // A pin needs BOTH halves: a hash to verify the bytes against and a signed URL
  // to fetch them from. Either one alone cannot authorise an automatic install.
  AProbe.RefetchPossible := (Trim(Res.Sha256) <> '') and (Trim(Res.Url) <> '');
  Result := True;
end;

function AvroHealActionText(const AAction: TAvroHealAction): string;
begin
  case AAction of
    ahaNone:               Result := 'none';
    ahaInstall:            Result := 'install';
    ahaBaselineAndRefetch: Result := 'baseline+refetch';
    ahaBlocked:            Result := 'blocked';
  else
    Result := 'unknown';
  end;
end;

function AvroStaleCauseText(const ACause: TAvroStaleCause): string;
begin
  case ACause of
    ascFresh:         Result := 'fresh';
    ascAbsent:        Result := 'not installed';
    ascDecryptFailed: Result := 'decryption failed at the current key epoch (corrupt)';
    ascMacFailed:     Result := 'integrity check failed at the current key epoch (corrupt)';
    ascEpochMismatch: Result := 'written for a different key epoch (stale after a rotation)';
  else
    Result := 'unknown';
  end;
end;

{ ---------------------------------------------------------------------------
  Backoff
  --------------------------------------------------------------------------- }

constructor TAvroRefetchGate.Create;
begin
  inherited Create;
  FStamps := TDictionary<string, TDateTime>.Create;
end;

destructor TAvroRefetchGate.Destroy;
begin
  FStamps.Free;
  inherited Destroy;
end;

function TAvroRefetchGate.ShouldAttempt(const AItemKey: string; const ANow: TDateTime): Boolean;
var
  Last: TDateTime;
begin
  Result := False;
  if Trim(AItemKey) = '' then
    Exit;
  if not FStamps.TryGetValue(LowerCase(Trim(AItemKey)), Last) then
    Exit(True); // never attempted
  Result := (ANow - Last) >= (AVRO_REFETCH_WINDOW_HOURS / 24);
end;

procedure TAvroRefetchGate.RecordAttempt(const AItemKey: string; const ANow: TDateTime);
begin
  if Trim(AItemKey) = '' then
    Exit;
  FStamps.AddOrSetValue(LowerCase(Trim(AItemKey)), ANow);
end;

procedure TAvroRefetchGate.Forget(const AItemKey: string);
begin
  if Trim(AItemKey) = '' then
    Exit;
  FStamps.Remove(LowerCase(Trim(AItemKey)));
end;

procedure TAvroRefetchGate.Clear;
begin
  FStamps.Clear;
end;

function TAvroRefetchGate.Count: Integer;
begin
  Result := FStamps.Count;
end;

procedure TAvroRefetchGate.Save(const APath: string);
var
  Obj:  TJSONObject;
  Pair: TPair<string, TDateTime>;
  Text: TStringList;
  Dir:  string;
begin
  if Trim(APath) = '' then
    Exit;
  Obj := TJSONObject.Create;
  try
    for Pair in FStamps do
      Obj.AddPair(Pair.Key, TJSONNumber.Create(DateTimeToUnix(TTimeZone.Local.ToUniversalTime(Pair.Value))));

    Dir := ExtractFilePath(APath);
    if Dir <> '' then
      ForceDirectories(Dir);

    Text := TStringList.Create;
    try
      Text.Add(Obj.ToJSON);
      Text.SaveToFile(APath, TEncoding.UTF8);
    finally
      Text.Free;
    end;
  finally
    Obj.Free;
  end;
end;

procedure TAvroRefetchGate.Load(const APath: string);
var
  Text: string;
  Root: TJSONValue;
  Obj:  TJSONObject;
  P:    TJSONPair;
  Num:  TJSONNumber;
  I:    Integer;
begin
  Clear;
  if (Trim(APath) = '') or not FileExists(APath) then
    Exit;

  Root := nil;
  try
    try
      Text := TFile.ReadAllText(APath, TEncoding.UTF8);
      Root := TJSONObject.ParseJSONValue(Text);
      if not(Root is TJSONObject) then
        Exit;
      Obj := TJSONObject(Root);
      for I := 0 to Obj.Count - 1 do
      begin
        P := Obj.Pairs[I];
        if P.JsonValue is TJSONNumber then
        begin
          Num := TJSONNumber(P.JsonValue);
          FStamps.AddOrSetValue(LowerCase(P.JsonString.Value), TTimeZone.Local.ToLocalTime(UnixToDateTime(Num.AsInt64)));
        end;
      end;
    except
      // A half-written or hand-edited state file is a clean slate. The throttle
      // is an optimisation, so it must never be able to block a repair.
      FStamps.Clear;
    end;
  finally
    Root.Free;
  end;
end;

end.
