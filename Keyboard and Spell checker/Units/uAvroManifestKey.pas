{=---------------------------------------------------------------------------
  uAvroManifestKey - Ed25519 public key for the signed resource trust chain.

  GENERATED FILE - do not edit by hand. Regenerate with
  tools\resource-sync\sign_manifest.py keygen --out-pas <this file>.

  This public key verifies manifest.json (the resource catalog) and
  resources.lock.json (the pinned container inventory). The matching PRIVATE
  key is never in the repository. Rotating the key means regenerating this
  unit AND re-signing both files; the keyId lets a client detect the change.

  Verification lives in uAvroEd25519.pas (pure Pascal - the engine links no
  crypto DLL).
  ---------------------------------------------------------------------------}

unit uAvroManifestKey;

interface

uses
  System.SysUtils;

const
  { Identifier of the signing key. A manifest whose signed payload names a
    different keyId must be refused rather than verified against this key. }
  AVRO_MANIFEST_KEY_ID = 'ed25519-2026-2';

  AVRO_MANIFEST_PUBLIC_KEY_LEN = 32;

  AVRO_MANIFEST_PUBLIC_KEY: array [0 .. 31] of Byte = (
        $91, $B3, $80, $D6, $31, $D0, $E5, $9D, $CC, $63, $A8, $1F,
        $6E, $B3, $C3, $6D, $1A, $9F, $D9, $F8, $1E, $9A, $45, $81,
        $64, $36, $96, $9F, $51, $23, $BD, $3D
  );

  { The key this build replaces, present ONLY while the transition window is
    open: a manifest whose payload names this keyId still verifies against the
    public key below, so a document published before the rotation is not
    refused the moment the client updates. The matching PRIVATE key no longer
    exists, so this entry can sign nothing new. Regenerate the unit WITHOUT
    --previous-pas to close the window. }
  AVRO_MANIFEST_PREVIOUS_KEY_ID = 'ed25519-2026-1';

  AVRO_MANIFEST_PREVIOUS_PUBLIC_KEY_LEN = 32;

  AVRO_MANIFEST_PREVIOUS_PUBLIC_KEY: array [0 .. 31] of Byte = (
        $BF, $2A, $54, $C1, $01, $37, $F4, $FC, $D4, $71, $1D, $6E,
        $64, $09, $E8, $F4, $3B, $6C, $EB, $87, $5D, $06, $44, $32,
        $BB, $55, $4A, $DE, $03, $1B, $85, $FA
  );

{ The pinned public key as a TBytes, ready for AvroEd25519Verify. }
function AvroManifestPublicKey: TBytes;

function AvroManifestKeyId: string;

{ The previous public key as a TBytes - empty when this build trusts no
  predecessor. Wipe it like any other key material once used. }
function AvroManifestPreviousPublicKey: TBytes;

function AvroManifestPreviousKeyId: string;

implementation

function AvroManifestPublicKey: TBytes;
var
  I: Integer;
begin
  SetLength(Result, AVRO_MANIFEST_PUBLIC_KEY_LEN);
  for I := 0 to AVRO_MANIFEST_PUBLIC_KEY_LEN - 1 do
    Result[I] := AVRO_MANIFEST_PUBLIC_KEY[I];
end;

function AvroManifestKeyId: string;
begin
  Result := AVRO_MANIFEST_KEY_ID;
end;

function AvroManifestPreviousPublicKey: TBytes;
var
  I: Integer;
begin
  SetLength(Result, AVRO_MANIFEST_PREVIOUS_PUBLIC_KEY_LEN);
  for I := 0 to AVRO_MANIFEST_PREVIOUS_PUBLIC_KEY_LEN - 1 do
    Result[I] := AVRO_MANIFEST_PREVIOUS_PUBLIC_KEY[I];
end;

function AvroManifestPreviousKeyId: string;
begin
  Result := AVRO_MANIFEST_PREVIOUS_KEY_ID;
end;

end.
