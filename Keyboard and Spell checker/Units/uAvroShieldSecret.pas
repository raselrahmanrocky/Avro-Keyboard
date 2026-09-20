{ =---------------------------------------------------------------------------
  uAvroShieldSecret - obfuscated root secret for default-key containers.

  GENERATED FILE - do not edit by hand. Regenerate with
  AvroEncoEngine\tools\AvroShieldSecretGen\gen_shield_secret.py

  The IKM is a 44-byte secret masked with a rotl-indexed xorshift32
  keystream. It is NOT two complementary arrays: recovering the plaintext
  requires reproducing AVRO_SECRET_KS, and that routine is the one marked
  VMProtectBeginUltra in Phase 2 of the hardening plan.

  AvroShieldSecretIKM returns raw bytes and never builds a Delphi string, so
  the secret never exists as a UTF-16 heap allocation on the default-key load
  path. AvroShieldSecretString exists only for the deprecated legacy CBC
  reader and the persistent-cache key, and is documented as such.

  ROTATION: run the generator with --random N and regenerate every shipped
  container with AvroEncoBuilder. Until containers are rebuilt, old and new
  secrets do not interoperate (by design - that is what rotation means). The
  pinned digest in kat_shieldsecret.dpr intentionally fails on rotation so a
  new secret cannot be adopted by accident.
  --------------------------------------------------------------------------- }

unit uAvroShieldSecret;

{ Inlining OFF for this unit only. The secret expansion below is the
  VMProtectBeginUltra region; if Delphi inlines a marked routine into its
  caller, the identical logic survives unprotected in the caller as well, so
  the virtualised copy is not the only copy an analyst can reach. This costs
  nothing measurable on the load path, which is the only path that uses it.
  (Units without markers keep inlining - notably uAvroCryptoUtils, whose AES
  and GCM round functions are genuinely hot.) }
{$INLINE OFF}

interface

uses
  System.SysUtils; // TBytes

{ Decoded root secret IKM, exactly the bytes fed to HKDF-SHA256 for
  default-key containers. Terminated at the first decoded NUL byte. }
function AvroShieldSecretIKM: TBytes;

{ Legacy accessor: the same IKM interpreted as an ASCII string. Deprecated -
  used only by uAvroEncoCrypto's v1/v2 CBC reader and uAnsiPersistentCache's
  cache-key derivation. Do not use on the Shield load path. }
function AvroShieldSecretString: string;

{ Length of the decoded IKM, without allocating it. Used by self-checks. }
function AvroShieldSecretLength: Integer;

implementation

uses
  uAvroSecureMem,
  uAvroShieldVM;

const
  { xorshift32 seed. Not a secret; the only free parameter of the mask. }
  AVRO_SECRET_SEED = $5F3A17C9;

  { Decoded IKM length (excludes the NUL terminator). }
  AVRO_SECRET_LEN = 44;

  { Masked secret. blob[i] XOR rotl8(keystream(i), i mod 8) == ikm[i]. }
  AVRO_SECRET_BLOB: array [0 .. 47] of Byte = ($69, $4E, $E0, $42, $C6, $73, $63, $1E, $8D, $F2, $ED, $C2, $AE, $BA, $7B, $5F, $97, $B6, $91, $8C, $9D, $E9,
    $37, $A2, $3D, $AB, $CD, $F7, $3A, $80, $C3, $6E, $AA, $63, $37, $02, $43, $40, $57, $E9, $2F, $02, $B1, $B6, $8D, $BA, $4A, $06);

  { One xorshift32 step (Marsaglia). Kept trivial on purpose: this function and
    its caller are the VMProtectBeginUltra region. }
function AvroSecretXorShift32(AState: Cardinal): Cardinal; inline;
begin
  AState := AState xor (AState shl 13);
  AState := AState xor (AState shr 17);
  AState := AState xor (AState shl 5);
  Result := AState;
end;

{ Rotate-left within a byte. ARot of 0 must return the value unchanged, so the
  right-shift by (8 - ARot) has to be evaluated on a promoted Integer (a Byte
  shifted right by 8 is 0, and Delphi promotes before shifting). }
function AvroSecretRotl8(AValue: Byte; ARot: Integer): Byte; inline;
begin
  ARot := ARot and 7;
  Result := Byte(((Integer(AValue) shl ARot) or (Integer(AValue) shr (8 - ARot))) and $FF);
end;

function AvroShieldSecretIKM: TBytes;
var
  I:     Integer;
  State: Cardinal;
  Plain: Byte;
begin
  { The single highest-value VMProtect region in the project: every
    container's confidentiality reduces to these bytes. Marker pair without
    try/finally on purpose - VMProtect handles the plain form reliably, while
    SEH inside a virtualised block is a known source of protection-time
    breakage, and nothing here raises in normal operation. }
  VMBeginUltra('sk');
  SetLength(Result, Length(AVRO_SECRET_BLOB));
  State := AVRO_SECRET_SEED;
  I := 0;
  while I < Length(AVRO_SECRET_BLOB) do
  begin
    if (I mod 4) = 0 then
      State := AvroSecretXorShift32(State);
    Plain := AVRO_SECRET_BLOB[I] xor AvroSecretRotl8(Byte(State shr (8 * (I mod 4))), I);
    Result[I] := Plain;
    if Plain = 0 then
    begin
      // Terminator: trim to the declared length and stop.
      SetLength(Result, I);
      Break;
    end;
    Inc(I);
  end;
  if Length(Result) > AVRO_SECRET_LEN then
    SetLength(Result, AVRO_SECRET_LEN);
  VMEnd;
end;

function AvroShieldSecretLength: Integer;
begin
  Result := Length(AvroShieldSecretIKM);
end;

function AvroShieldSecretString: string;
var
  IKM: TBytes;
begin
  IKM := AvroShieldSecretIKM;
  try
    Result := TEncoding.ASCII.GetString(IKM);
  finally
    // The caller keeps the string (legacy contract); only the raw byte copy
    // is wiped here.
    AvroWipeAndRelease(IKM);
  end;
end;

end.
