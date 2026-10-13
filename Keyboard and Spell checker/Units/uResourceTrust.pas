(*
  uResourceTrust.pas - authenticates what the resource browser downloads.

  THE HOLE THIS CLOSES
  --------------------
  The browser reads its catalog from index.json, fetched over HTTPS with no
  signature, and every item carries a sha256 that the installer verifies the
  download against. That check is real but it proves only that the bytes
  arrived intact: the hash and the file come from the same unauthenticated
  source, so whoever can serve index.json can serve a matching hash for a
  matching container. Integrity, not authenticity.

  The signed manifest is the missing half. It is a small JSON document whose
  canonical payload pins each resource's sha256, size, version, format version,
  minimum app version and status, and it is signed with an Ed25519 key compiled
  into Avro Keyboard.exe (uAvroManifestKey). An attacker must therefore forge a
  signature over the payload, not merely serve different bytes.

  WHAT THIS UNIT IS
  -----------------
  Exactly one decision, in one place: given a catalog item, may it be installed,
  and if so what are its authoritative download facts. Every install path goes
  through ResolveItem, so there is no second opinion to keep in step.

  The catalog keeps its job (naming and describing items for the UI) because a
  resource that is merely LISTED harms nothing - only installing it does. That
  is why browsing still works from an unsigned catalog while installing does
  not, and it is what makes this change adoptable before the resource repository
  publishes its first signed manifest.

  A NOTE ON THE TWO HASHES
  ------------------------
  When the catalog states a sha256 too, it must AGREE with the manifest. A
  disagreement is the exact shape of an attack - a rewritten catalog pointing at
  a different container - so it is refused loudly rather than resolved in the
  manifest's favour. The manifest's value is what gets downloaded against, and
  the catalog's copy is never used as the expectation.

  All evaluation happens in memory and needs no network, which is why the
  decision itself is what the KAT gate exercises.
*)

unit uResourceTrust;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Net.HttpClient,
  System.Net.HttpClientComponent,
  System.Net.URLClient,
  uAvroManifest;

type
  { Where the trust document stands. Distinguishing rtsFailed from rtsNotLoaded
    matters: a dialog that never fetched the manifest should say so, not claim
    that a download was tampered with. }
  TResourceTrustStatus = (rtsNotLoaded, rtsVerified, rtsFailed);

  TResourceTrust = class
  private
    FManifest:  TAvroManifest;
    FStatus:    TResourceTrustStatus;
    FError:     string;
    FSourceUrl: string;

    procedure Clear;
  public
    destructor Destroy; override;

    { Verifies already-fetched manifest text and adopts it. No network - this is
      the whole trust decision, so it is what the gate drives. Returns False and
      leaves the object in rtsFailed with nothing adoptable when the signature,
      the keyId or the payload is unacceptable. }
    function AdoptManifestText(const AJsonText: string; out AError: string): Boolean;

    { Fetches AUrl, then adopts it. Synchronous on purpose: the caller runs this
      inside its own TTask and marshals the result back to the UI thread, the
      same shape as TResourceCatalog.Fetch. }
    function Fetch(const AUrl: string; out AError: string): Boolean;

    { THE INSTALL GATE. True only when all of these hold: a verified manifest is
      loaded; it pins AFileName; that resource is usable for this application
      (not revoked, not deprecated, format and minimum version satisfied); and
      every value the catalog also states agrees with the manifest.

      On success APin carries the authenticated sha256, size and URL to download
      with - never the catalog's copies. On False AError is a caller-displayable
      sentence that names the reason, because a refusal the user cannot
      understand is indistinguishable from a broken button. }
    function ResolveItem(const AFileName, ACatalogSha256, AAppVersion: string; AAppFormatVersion: Integer; out APin: TAvroResource;
      out AError: string): Boolean;

    { The manifest URL for a catalog base URL. Derived from the catalog rather
      than hardcoded twice, so a fork that retargets the catalog retargets the
      manifest with it. }
    class function ManifestUrlForBase(const ABaseUrl: string): string;

    { The default resource repository's manifest. }
    class function DefaultManifestUrl: string;

    property Status: TResourceTrustStatus read FStatus;
    property Error: string read FError;
    property SourceUrl: string read FSourceUrl;
    property Manifest: TAvroManifest read FManifest;
  end;

const
  { Name of the trust document inside the resource repository. }
  RESOURCE_MANIFEST_FILE = 'manifest.json';

(* The application's supported RESOURCE CONTAINER format version, for the
  FormatVersion column of a signed manifest.

  This is deliberately the AvroShield container version this build can read,
  taken from the shield unit rather than written down here: uAvroShield owns
  that number so tooling and the header writer cannot drift from the reader,
  and a second copy in the browser would reintroduce exactly the drift that
  AvroShieldCurrentVersion was made public to prevent. A manifest that lists a
  resource in a newer format than this is refused by AvroManifestResourceUsable
  rather than downloaded into a loader that cannot open it. *)
function ResourceAppFormatVersion: Integer;

implementation

uses
  uAvroShield,
  DebugLog;

const
  RESOURCE_RAW_ROOT = 'https://raw.githubusercontent.com/';
  RESOURCE_REPO     = 'raselrahmanrocky/Avro-Keyboard-Resource';
  RESOURCE_BRANCH   = 'main';

{ Last path component, so 'AnsiMapping/Ansi V1.AvroEnco' and
  'Ansi V1.AvroEnco' both answer to the same resource. Mirrors
  uResourceInstaller.LastComponent, which is what decides the on-disk name. }
function LastComponent(const AFileName: string): string;
begin
  Result := ExtractFileName(StringReplace(AFileName, '/', '\', [rfReplaceAll]));
end;

{ True when the two hashes are equal, treating an empty statement as no
  statement at all (the catalog is allowed to omit the hash). }
function HashesAgree(const AFromCatalog, AFromManifest: string): Boolean;
begin
  if Trim(AFromCatalog) = '' then
    Result := True
  else
    Result := SameText(Trim(AFromCatalog), Trim(AFromManifest));
end;

class function TResourceTrust.ManifestUrlForBase(const ABaseUrl: string): string;
begin
  Result := '';
  if Trim(ABaseUrl) = '' then
    Exit;
  Result := IncludeTrailingPathDelimiter(Trim(ABaseUrl)) + RESOURCE_MANIFEST_FILE;
end;

class function TResourceTrust.DefaultManifestUrl: string;
begin
  Result := RESOURCE_RAW_ROOT + RESOURCE_REPO + '/' + RESOURCE_BRANCH + '/' + RESOURCE_MANIFEST_FILE;
end;

function ResourceAppFormatVersion: Integer;
begin
  Result := AvroShieldCurrentVersion;
end;

procedure TResourceTrust.Clear;
begin
  FreeAndNil(FManifest);
  FStatus := rtsNotLoaded;
  FError := '';
  FSourceUrl := '';
end;

destructor TResourceTrust.Destroy;
begin
  FreeAndNil(FManifest);
  inherited Destroy;
end;

function TResourceTrust.AdoptManifestText(const AJsonText: string; out AError: string): Boolean;
var
  Loaded: TAvroManifest;
  VerifyErr: string;
begin
  Result := False;
  AError := '';
  Clear;

  if Trim(AJsonText) = '' then
  begin
    FStatus := rtsFailed;
    FError := 'The resource manifest is empty.';
    AError := FError;
    Exit;
  end;

  Loaded := nil;
  // AvroManifestLoadAndVerify parses, checks the payload's keyId against the
  // embedded key, and verifies the Ed25519 signature. Nothing below is reached
  // with an unverified document, so a caller cannot accidentally use one.
  if not AvroManifestLoadAndVerify(AJsonText, Loaded, VerifyErr) then
  begin
    FStatus := rtsFailed;
    FError := 'The resource manifest could not be trusted: ' + VerifyErr;
    AError := FError;
    Exit;
  end;

  // A signed LOCK is a valid trust document, but it is not a catalog: it pins
  // the containers committed to the repository and carries no download URLs or
  // statuses. Accepting one here would silently resolve nothing.
  if Loaded.Kind <> amkManifest then
  begin
    Loaded.Free;
    FStatus := rtsFailed;
    FError := 'The resource manifest is not a catalog (it is a lock file).';
    AError := FError;
    Exit;
  end;

  FManifest := Loaded;
  FStatus := rtsVerified;
  Log(Format('Resource manifest verified (keyId=%s, %d resource(s))', [FManifest.KeyId, Length(FManifest.Resources)]));
  Result := True;
end;

function TResourceTrust.Fetch(const AUrl: string; out AError: string): Boolean;
var
  Http:     TNetHTTPClient;
  Response: IHTTPResponse;
  Text:     string;
begin
  Result := False;
  AError := '';
  Clear;
  FSourceUrl := AUrl;

  if Trim(AUrl) = '' then
  begin
    FStatus := rtsFailed;
    FError := 'No resource manifest URL.';
    AError := FError;
    Exit;
  end;

  Http := TNetHTTPClient.Create(nil);
  try
    Http.UserAgent := 'Avro Keyboard';
    Http.AllowCookies := False;
    Http.ConnectionTimeout := 8000;
    Http.ResponseTimeout := 15000;
    try
      Response := Http.Get(AUrl);
    except
      // Offline is the ordinary case here, so it reads as a plain statement
      // rather than an error: browsing keeps working, installing does not.
      on E: Exception do
      begin
        FStatus := rtsFailed;
        FError := 'Could not download the resource manifest: ' + E.Message;
        AError := FError;
        Exit;
      end;
    end;

    if Response.StatusCode <> 200 then
    begin
      FStatus := rtsFailed;
      FError := 'The resource manifest is unavailable (HTTP ' + IntToStr(Response.StatusCode) + ').';
      AError := FError;
      Exit;
    end;

    Text := Response.ContentAsString;
  finally
    Http.Free;
  end;

  Result := AdoptManifestText(Text, AError);
end;

function TResourceTrust.ResolveItem(const AFileName, ACatalogSha256, AAppVersion: string; AAppFormatVersion: Integer; out APin: TAvroResource;
  out AError: string): Boolean;
var
  Res:    TAvroResource;
  Reason: string;
begin
  Result := False;
  AError := '';
  FillChar(APin, SizeOf(APin), 0);

  if FStatus = rtsNotLoaded then
  begin
    AError := 'The signed resource manifest has not been loaded yet.';
    Exit;
  end;
  if (FStatus = rtsFailed) or (FManifest = nil) then
  begin
    AError := 'Downloads are disabled because the signed resource manifest could not be verified.';
    if FError <> '' then
      AError := AError + ' ' + FError;
    Exit;
  end;

  if LastComponent(AFileName) = '' then
  begin
    AError := 'The catalog entry has no file name.';
    Exit;
  end;

  // Matching on the file name (not the id) is deliberate: the installer keys
  // the on-disk name off the same component, so the file that lands on disk is
  // exactly the one the manifest pinned.
  if not AvroManifestFindByFileName(FManifest, AFileName, Res) then
  begin
    AError := 'This file is not listed in the signed resource manifest, so it cannot be installed.';
    Exit;
  end;

  if not AvroManifestResourceUsable(Res, AAppFormatVersion, AAppVersion, Reason) then
  begin
    if SameText(Reason, 'revoked') then
      AError := 'This resource has been revoked and cannot be installed.'
    else if SameText(Reason, 'deprecated') then
      AError := 'This resource is deprecated and cannot be installed.'
    else
      AError := 'This resource cannot be installed: ' + Reason + '.';
    Exit;
  end;

  // The manifest must actually pin the bytes. A manifest entry with no hash is
  // not a pin, and treating it as one would make the signature decorative.
  if Trim(Res.Sha256) = '' then
  begin
    AError := 'The signed manifest does not pin a SHA-256 for this file.';
    Exit;
  end;

  if not HashesAgree(ACatalogSha256, Res.Sha256) then
  begin
    AError := 'The catalog and the signed manifest disagree about this file''s SHA-256. The catalog may have been altered.';
    Exit;
  end;

  // The download URL is signed too, so an absent one is a refusal rather than
  // an excuse to fall back to the catalog's own (unsigned) idea of where the
  // file lives. The sha256 is what actually protects the bytes - a hijacked URL
  // still cannot deliver a file that matches the signed hash - but silently
  // substituting an unauthenticated URL would defeat the point of signing it.
  if Trim(Res.Url) = '' then
  begin
    AError := 'The signed manifest does not say where to download this file from.';
    Exit;
  end;

  APin := Res;
  Result := True;
end;

end.
