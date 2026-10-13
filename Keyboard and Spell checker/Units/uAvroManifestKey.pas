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
  AVRO_MANIFEST_KEY_ID = 'ed25519-2026-1';

  AVRO_MANIFEST_PUBLIC_KEY_LEN = 32;

  AVRO_MANIFEST_PUBLIC_KEY: array [0 .. 31] of Byte = (
        $BF, $2A, $54, $C1, $01, $37, $F4, $FC, $D4, $71, $1D, $6E,
        $64, $09, $E8, $F4, $3B, $6C, $EB, $87, $5D, $06, $44, $32,
        $BB, $55, $4A, $DE, $03, $1B, $85, $FA
  );

{ The pinned public key as a TBytes, ready for AvroEd25519Verify. }
function AvroManifestPublicKey: TBytes;

function AvroManifestKeyId: string;

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

end.
