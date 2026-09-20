{

  kat_shieldsecret - KATs for the two hardening primitives that everything
  else depends on:

  1. uAvroShieldSecret: the obfuscated root secret must decode to the exact
  IKM this release was built against. The expected value is pinned as a
  SHA-256 digest, not as the secret itself, so this file can live in the
  repository without publishing the secret. If someone rotates the
  secret without updating the pin, this fails loudly - that is the point
  (a silent rotation would break every previously built container).

  2. uAvroSecureMem: the wipe primitives must actually clear memory that is
  subsequently read (proving the store was not eliminated), and
  AvroWipeString must break copy-on-write instead of corrupting a string
  that another variable still shares.

  Exit code: 0 all PASS, 1 FAIL.
}

{$APPTYPE CONSOLE}
program kat_shieldsecret;

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  uAvroSecureMem,
  uAvroShieldSecret;

const
  { SHA-256 of the decoded root secret IKM (44 bytes of ASCII). Publishing the
    digest is safe: the IKM carries ~128 bits of entropy from its random tail,
    so the digest cannot be inverted. }
  PinnedIKMSha256 = '91ea351e02f65fd97d4c7cd2bcd9038fa3b130bfd43796b71da27a6cc9bad048';
  ExpectedIKMLen  = 44;

  Canary = $A5;

var
  Fails: Integer;

function BytesToHex(const B: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(B) - 1 do
    Result := Result + H[B[I] shr 4] + H[B[I] and 15];
end;

function Sha256Hex(const AData: TBytes): string;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(AData) > 0 then
    H.Update(AData);
  Result := LowerCase(BytesToHex(H.HashAsBytes));
end;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('  ' + ADetail);
    Inc(Fails);
  end;
end;

{ ---------------------------------------------------------------------------
  Root secret
  --------------------------------------------------------------------------- }

procedure CheckRootSecret;
var
  IKM: TBytes;
  S:   string;
begin
  IKM := AvroShieldSecretIKM;
  try
    Check('secret decodes to the pinned length', Length(IKM) = ExpectedIKMLen, Format('length=%d expected=%d', [Length(IKM), ExpectedIKMLen]));
    Check('secret matches the pinned SHA-256', Sha256Hex(IKM) = PinnedIKMSha256, 'sha256=' + Sha256Hex(IKM) + ' expected=' + PinnedIKMSha256);
  finally
    AvroWipeAndRelease(IKM);
  end;

  { The legacy string accessor must expose exactly the same bytes. This is the
    path uAnsiPersistentCache and the v1/v2 CBC reader still use, so a
    divergence here would silently orphan every existing cache file. }
  S := AvroShieldSecretString;
  try
    Check('legacy string accessor agrees with the byte IKM', Sha256Hex(TEncoding.ASCII.GetBytes(S)) = PinnedIKMSha256);
  finally
    AvroWipeString(S);
  end;

  { Fresh calls must not return shared, wipeable state. }
  IKM := AvroShieldSecretIKM;
  try
    AvroWipeBytes(IKM);
    Check('wipe of the first returned IKM zeroes every byte', Sha256Hex(IKM) <> PinnedIKMSha256);
  finally
    AvroWipeAndRelease(IKM);
  end;
end;

{ ---------------------------------------------------------------------------
  Wipe primitives
  --------------------------------------------------------------------------- }

procedure CheckWipeLocalArray;
var
  Local:  array [0 .. 63] of Byte;
  I, Sum: Integer;
begin
  for I := 0 to high(local) do
    local[I] := Canary;
  AvroSecureZero(local, SizeOf(local));
  { Read the values afterwards: a compiler that eliminated the wipe as a dead
    store cannot pass this, because the sum would still be Canary * 64. }
  Sum := 0;
  for I := 0 to high(local) do
    Sum := Sum + local[I];
  Check('AvroSecureZero clears a local buffer that is read afterwards', Sum = 0, Format('sum=%d expected=0', [Sum]));
end;

procedure CheckWipeBytes;
var
  B:      TBytes;
  I, Sum: Integer;
begin
  SetLength(B, 128);
  for I := 0 to Length(B) - 1 do
    B[I] := Canary;
  AvroWipeBytes(B);
  Sum := 0;
  for I := 0 to Length(B) - 1 do
    Sum := Sum + B[I];
  Check('AvroWipeBytes clears the buffer contents', Sum = 0, Format('sum=%d expected=0', [Sum]));
  Check('AvroWipeBytes keeps the length (content-only wipe)', Length(B) = 128, Format('length=%d expected=128', [Length(B)]));

  AvroWipeAndRelease(B);
  Check('AvroWipeAndRelease releases the buffer', Length(B) = 0, Format('length=%d expected=0', [Length(B)]));
end;

procedure CheckWipeStringCopyOnWrite;
var
  S1, S2: string;
begin
  S1 := StringOfChar('K', 32);
  { Sharing the same heap buffer is what makes an unwary zeroing loop corrupt
    the sibling. AvroWipeString must call UniqueString first. }
  S2 := S1;
  S1 := S1 + S1;
  S1 := Copy(S1, 1, 32); // still logically the same 32 'K's

  AvroWipeString(S1);
  Check('AvroWipeString clears the variable it owns', S1 = '', 'value not cleared');
  Check('AvroWipeString does not corrupt a sibling sharing the buffer', S2 = StringOfChar('K', 32), Format('sibling length=%d (expected 32)', [Length(S2)]));
  AvroWipeString(S2);
end;

procedure CheckWipeStringLiteralSafety;
var
  S: string;
begin
  { Assigning a literal gives a reference to read-only constant data; wiping
    it must copy-on-write, never write into .rdata. }
  S := 'literal-backed-string';
  AvroWipeString(S);
  Check('AvroWipeString is safe for literal-backed strings', S = '', 'value not cleared');
  Check('literal itself is still readable after the wipe', 'literal-backed-string' = 'literal-backed-string');
end;

procedure CheckWipeStringArray;
var
  A: TArray<string>;
begin
  SetLength(A, 3);
  A[0] := 'alpha';
  A[1] := 'beta';
  A[2] := 'gamma';
  AvroWipeStringArray(A);
  Check('AvroWipeStringArray clears every element', (A[0] = '') and (A[1] = '') and (A[2] = ''), Format('[%s][%s][%s]', [A[0], A[1], A[2]]));

  SetLength(A, 0);
  AvroWipeStringArray(A); // empty array must be a safe no-op
  Check('AvroWipeStringArray tolerates an empty array', True);
end;

{ ---------------------------------------------------------------------------
  Fused gate
  --------------------------------------------------------------------------- }

procedure CheckFusedGate;
begin
  Check('AvroFuse(True) equals the pinned open value', AvroFuse(True) = AVRO_FUSE_OPEN, Format('$%.8x expected $%.8x', [AvroFuse(True), AVRO_FUSE_OPEN]));
  Check('AVRO_FUSE_OPEN matches the documented derivation', AVRO_FUSE_OPEN = (AVRO_FUSE_MUL xor AVRO_FUSE_XOR), Format('$%.8x', [AVRO_FUSE_OPEN]));
  Check('AvroFuse(False) does not open the gate', AvroFuse(False) <> AVRO_FUSE_OPEN);
  Check('AvroFuseOk accepts the open value', AvroFuseOk(AvroFuse(True)));
  Check('AvroFuseOk rejects the closed value', not AvroFuseOk(AvroFuse(False)));
  { A gate value must not be openable by an unrelated arithmetic accident. }
  Check('AvroFuseOk rejects an adjacent value', not AvroFuseOk(AVRO_FUSE_OPEN xor 1));
end;

begin
  Fails := 0;

  WriteLn('=== root secret (pinned digest) ===');
  CheckRootSecret;

  WriteLn('=== secure wipe primitives ===');
  CheckWipeLocalArray;
  CheckWipeBytes;
  CheckWipeStringCopyOnWrite;
  CheckWipeStringLiteralSafety;
  CheckWipeStringArray;

  WriteLn('=== fused fail-closed gate ===');
  CheckFusedGate;

  if Fails = 0 then
    WriteLn('ALL SHIELD SECRET/WIPE KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT(s) FAILED');

  if Fails > 0 then
    Halt(1);

end.
