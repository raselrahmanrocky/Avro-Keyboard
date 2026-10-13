{ =---------------------------------------------------------------------------
  uAvroShieldSecret - PUBLIC STUB for the root-secret accessor.

  THIS FILE IS THE STUB. The real implementation of this unit is secret-bearing,
  lives in a private repository, and is fetched into this folder at build time by
  tools\secrets\fetch_secrets.ps1 - which OVERWRITES THIS FILE IN PLACE and then
  marks it skip-worktree so it can never be committed by accident.

  The public repository deliberately tracks this file so that a clean clone
  builds offline with no token and no key material. In that configuration the
  keyboard runs normally, custom-key and passphrase containers work, and an
  attempt to open a DEFAULT-KEY container fails with
  AVRO_SECRET_UNAVAILABLE_MSG instead of a confusing decode error.

  IsRealSecretUnit is the machine-readable discriminator between the two:
    stub (this file)   -> False
    fetched real unit  -> True

  tools\release\build-installers.ps1 runs `kat_shieldsecret --require-real` and
  HARD-FAILS when it reads False, so a stub-built binary can never be shipped or
  signed. Do not change it to True here; that would defeat the release guard.

  Do not add key material to this file, not even in a comment.
  tools\secrets\check-no-secret-bytes.ps1 fails the build if it appears.
  --------------------------------------------------------------------------- }

unit uAvroShieldSecret;

interface

uses
  System.SysUtils; // TBytes, Exception

const
  { False here; the fetched real unit defines this as True. Read by the release
    guard and by the resource browser's stub-mode banner. }
  IsRealSecretUnit: Boolean = False;

  { Stable text so callers and gates can recognise the condition without
    matching on a formatted message. }
  AVRO_SECRET_UNAVAILABLE_MSG = 'secret extension not loaded';

type
  { Raised by every accessor below. Catching this specific type - rather than
    Exception - is how the resource browser tells "no key material in this
    build" apart from "this container is corrupt". }
  EAvroSecretUnavailable = class(Exception);

{ Decoded root secret IKM, exactly the bytes fed to HKDF-SHA256 for default-key
  containers. Unavailable in a stub build. }
function AvroShieldSecretIKM: TBytes;

{ Legacy accessor: the same IKM interpreted as an ASCII string. Unavailable in
  a stub build. }
function AvroShieldSecretString: string;

{ Length of the decoded IKM, without allocating it. Returns 0 in a stub build
  and never raises, so callers can probe for stub mode without try/except. }
function AvroShieldSecretLength: Integer;

implementation

function AvroShieldSecretIKM: TBytes;
begin
  raise EAvroSecretUnavailable.Create(AVRO_SECRET_UNAVAILABLE_MSG);
end;

function AvroShieldSecretString: string;
begin
  raise EAvroSecretUnavailable.Create(AVRO_SECRET_UNAVAILABLE_MSG);
end;

function AvroShieldSecretLength: Integer;
begin
  { Deliberately does NOT raise: this is the probe callers use to detect stub
    mode without exception handling. }
  Result := 0;
end;

end.
