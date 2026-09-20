program kat_gcm;

{ AES-256-GCM + AES-256-ECB KAT for the pure-Pascal engine in
  uAvroCryptoUtils. All ciphertext+tag vectors below were produced by
  Python cryptography.hazmat AESGCM / pycryptodome AES-ECB with the exact
  same keys, nonces, AAD and plaintext. Also exercises round-trips and the
  failure modes (tampered ciphertext, wrong key, wrong AAD) that the
  .AvroEnco container relies on. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uAvroCryptoUtils;

var
  Fails: Integer;

function HexOf(const A: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(A) - 1 do
    Result := Result + H[A[I] shr 4] + H[A[I] and 15];
end;

function FromHex(const S: string): TBytes;
var
  I, Hi, Lo: Integer;
begin
  SetLength(Result, Length(S) div 2);
  for I := 0 to Length(S) div 2 - 1 do
  begin
    Hi := Pos(S[I * 2 + 1], '0123456789abcdef') - 1;
    Lo := Pos(S[I * 2 + 2], '0123456789abcdef') - 1;
    Result[I] := Byte((Hi shl 4) or Lo);
  end;
end;

procedure CheckEnc(const AName: string; const APlainHex, AKeyHex, ANonceHex, AAADHex, AExpectedHex: string);
var
  OutB: TBytes;
  Got:  string;
begin
  AES256GCMEncrypt(FromHex(APlainHex), FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), OutB);
  Got := HexOf(OutB);
  if Got = AExpectedHex then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    WriteLn('  expected: ' + AExpectedHex);
    WriteLn('  got     : ' + Got);
    Inc(Fails);
  end;
end;

procedure CheckECB(const AName: string; const AInHex, AKeyHex, AExpectedHex: string);
var
  OutB: TBytes;
  Got:  string;
begin
  AES256EncryptBlocksECB(FromHex(AKeyHex), FromHex(AInHex), OutB);
  Got := HexOf(OutB);
  if Got = AExpectedHex then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    WriteLn('  expected: ' + AExpectedHex);
    WriteLn('  got     : ' + Got);
    Inc(Fails);
  end;
end;

{ Encrypt + decrypt with the same parameters must round-trip; any failure
  in the decrypt path or a plaintext mismatch is a FAIL. }
procedure CheckRoundtrip(const AName: string; const APlainHex, AKeyHex, ANonceHex, AAADHex: string);
var
  Enc, Dec: TBytes;
  Got:      string;
begin
  AES256GCMEncrypt(FromHex(APlainHex), FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Enc);
  if not AES256GCMDecrypt(Enc, FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Dec) then
  begin
    WriteLn('FAIL ' + AName + ' (decrypt rejected a valid ciphertext)');
    Inc(Fails);
    Exit;
  end;
  Got := HexOf(Dec);
  if Got = APlainHex then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    WriteLn('  expected: ' + APlainHex);
    WriteLn('  got     : ' + Got);
    Inc(Fails);
  end;
end;

{ Every tamper variant MUST be rejected. }
procedure CheckReject(const AName: string; const APlainHex, AKeyHex, ANonceHex, AAADHex: string);
var
  Enc, Bad: TBytes;
  Dec:      TBytes;
  Variants: Integer;
begin
  AES256GCMEncrypt(FromHex(APlainHex), FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Enc);

  Variants := 0;

  // 1) Flip a byte in the middle of the ciphertext.
  if Length(Enc) > 16 then
  begin
    Bad := Copy(Enc, 0, Length(Enc));
    Bad[Length(Bad) div 2] := Bad[Length(Bad) div 2] xor $FF;
    if AES256GCMDecrypt(Bad, FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Dec) then
      Inc(Variants)
    else
      Dec := nil;
  end;

  // 2) Flip a byte of the tag.
  if Length(Enc) >= 16 then
  begin
    Bad := Copy(Enc, 0, Length(Enc));
    Bad[Length(Bad) - 1] := Bad[Length(Bad) - 1] xor $01;
    if AES256GCMDecrypt(Bad, FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Dec) then
      Inc(Variants)
    else
      Dec := nil;
  end;

  // 3) Wrong key.
  if AES256GCMDecrypt(Enc, FromHex('ffffffffffffffffffffffffffffffff' + 'ffffffffffffffffffffffffffffffff'), FromHex(ANonceHex), FromHex(AAADHex), Dec) then
    Inc(Variants)
  else
    Dec := nil;

  // 4) Wrong AAD.
  if AES256GCMDecrypt(Enc, FromHex(AKeyHex), FromHex(ANonceHex), FromHex('00'), Dec) then
    Inc(Variants)
  else
    Dec := nil;

  // 5) Wrong nonce.
  if AES256GCMDecrypt(Enc, FromHex(AKeyHex), FromHex('ffffffffffffffffffffffff'), FromHex(AAADHex), Dec) then
    Inc(Variants)
  else
    Dec := nil;

  // 6) Truncated input (ciphertext without its tag).
  if Length(Enc) > 16 then
  begin
    Bad := Copy(Enc, 0, Length(Enc) - 16);
    if AES256GCMDecrypt(Bad, FromHex(AKeyHex), FromHex(ANonceHex), FromHex(AAADHex), Dec) then
      Inc(Variants)
    else
      Dec := nil;
  end;

  if Variants = 0 then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName + ' (' + IntToStr(Variants) + ' tamper variant(s) accepted)');
    Inc(Fails);
  end;
end;

const
  KEY32   = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f';
  NONCE12 = '000102030405060708090a0b';
  NONCE16 = '000102030405060708090a0b0c0d0e0f';

var
  P1K, E1K: TBytes;
  Got, A:   string;
  I:        Integer;

begin
  Fails := 0;

  // ---- AES-256-ECB (raw forward cipher) ----
  CheckECB('AES-ECB single block', '000102030405060708090a0b0c0d0e0f', KEY32, '5a6e045708fb7196f02e553d02c3a692');
  CheckECB('AES-ECB two blocks', '000102030405060708090a0b0c0d0e0f' + '101112131415161718191a1b1c1d1e1f', KEY32,
    '5a6e045708fb7196f02e553d02c3a692e9c3ef8ab23453e6f0749cd636e7a88e');

  // ---- AES-256-GCM vectors (Python AESGCM, same inputs) ----
  CheckEnc('GCM empty plaintext', '', KEY32, NONCE12, '', 'f4c2db1dc38805a37b92171c5d0a81cc');
  CheckEnc('GCM short plaintext', '00010203040506070809', KEY32, NONCE12, '', '4703d418c1e0c41c85488fce6c32cd364c4f746e680fe77a8444');
  CheckEnc('GCM 48 bytes + AAD', '00000000000000000000000000000000' + '00000000000000000000000000000000' + '00000000000000000000000000000000', KEY32, NONCE12,
    'deadbeefcafebabe', '4702d61bc5e5c21b8d41978bb1e9786d83d68734f07b5f7c3867e5851d6900b2' +
      '0110aefcafc1129874a47fed8887283842a10360dfa0c13c6bb28f613e069b04');
  CheckEnc('GCM 16-byte nonce', '00010203', KEY32, NONCE16, '', '676da2750c835f4427c41d14b4e3b7e2a824fc05');

  // ---- Round trips across sizes / nonce lengths ----
  CheckRoundtrip('GCM roundtrip empty', '', KEY32, NONCE12, '');
  CheckRoundtrip('GCM roundtrip 48B + AAD', '00000000000000000000000000000000' + '00000000000000000000000000000000' + '00000000000000000000000000000000', KEY32,
    NONCE12, 'deadbeefcafebabe');
  CheckRoundtrip('GCM roundtrip nonce16 + AAD', '00010203040506070809', KEY32, NONCE16, 'a1b2c3d4');

  // 1 KiB plaintext (exercises multi-block GHASH + GCTR) with AAD.
  SetLength(P1K, 1024);
  for I := 0 to 1023 do
    P1K[I] := Byte((I * 7 + 3) and $FF);
  A := 'a1b2c3d4';
  AES256GCMEncrypt(P1K, FromHex(KEY32), FromHex(NONCE12), FromHex(A), E1K);
  Got := '';
  if AES256GCMDecrypt(E1K, FromHex(KEY32), FromHex(NONCE12), FromHex(A), P1K) and (Length(P1K) = 1024) then
  begin
    Got := 'ok';
    for I := 0 to 1023 do
      if P1K[I] <> Byte((I * 7 + 3) and $FF) then
      begin
        Got := 'bad';
        Break;
      end;
  end;
  if Got = 'ok' then
    WriteLn('PASS GCM roundtrip 1KiB + AAD')
  else
  begin
    WriteLn('FAIL GCM roundtrip 1KiB + AAD');
    Inc(Fails);
  end;

  // ---- Everything malicious MUST be rejected ----
  CheckReject('GCM rejects tampering', '00010203040506070809', KEY32, NONCE12, 'deadbeef');
  CheckReject('GCM rejects tampering (empty pt)', '', KEY32, NONCE12, '');

  if Fails = 0 then
    WriteLn('ALL AES-GCM/ECB KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT(s) FAILED');

  if Fails > 0 then
    Halt(1);

end.
