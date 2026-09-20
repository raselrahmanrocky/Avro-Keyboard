program kat_shieldkdf;

{ Known-answer tests for the Shield v2 key schedule (uAvroShield.pas),
  which replaced the removed Argon2id KDF:
  - HKDF-SHA256 verified against RFC 5869 Appendix A (Test Cases 1 & 3)
  - PBKDF2-HMAC-SHA256 verified against vectors produced by CPython
  hashlib.pbkdf2_hmac (authoritative implementation), including the
  widely published password/salt/c=1 vector
  Exit code: 0 all PASS, 1 FAIL. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  uAvroShield;

var
  Fails: Integer;

function HexVal(C: Char): Integer;
begin
  case C of
    '0' .. '9':
      Result := Ord(C) - Ord('0');
    'a' .. 'f':
      Result := Ord(C) - Ord('a') + 10;
    'A' .. 'F':
      Result := Ord(C) - Ord('A') + 10;
    else
      Result := 0;
  end;
end;

function HexToBytes(const H: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(H) div 2);
  for I := 0 to Length(Result) - 1 do
    Result[I] := Byte(HexVal(H[I * 2 + 1]) * 16 + HexVal(H[I * 2 + 2]));
end;

function BytesToHex(const B: TBytes): string;
const
  Digits: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  SetLength(Result, Length(B) * 2);
  for I := 0 to Length(B) - 1 do
  begin
    Result[I * 2 + 1] := Digits[B[I] shr 4];
    Result[I * 2 + 2] := Digits[B[I] and $0F];
  end;
end;

function RepByte(B: Byte; Count: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Count);
  for I := 0 to Count - 1 do
    Result[I] := B;
end;

function RangeBytes(Lo, Hi: Integer): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Hi - Lo + 1);
  for I := 0 to Length(Result) - 1 do
    Result[I] := Byte(Lo + I);
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

procedure CheckBytes(const AName: string; const Actual: TBytes; const ExpectedHex: string);
begin
  Check(AName, BytesToHex(Actual) = LowerCase(ExpectedHex), 'got ' + BytesToHex(Actual));
end;

var
  PRK, OKM, DK: TBytes;

begin
  Fails := 0;

  WriteLn('=== HKDF-SHA256 RFC 5869 A.1 (basic) ===');
  PRK := HkdfExtractSHA256(RangeBytes($00, $0C), RepByte($0B, 22));
  CheckBytes('A.1 PRK', PRK, '077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5');
  OKM := HkdfExpandSHA256(PRK, RangeBytes($F0, $F9), 42);
  CheckBytes('A.1 OKM', OKM, '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf' + '34007208d5b887185865');

  WriteLn('=== HKDF-SHA256 RFC 5869 A.3 (empty salt/info) ===');
  PRK := HkdfExtractSHA256(nil, RepByte($0B, 22));
  CheckBytes('A.3 PRK', PRK, '19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04');
  OKM := HkdfExpandSHA256(PRK, nil, 42);
  CheckBytes('A.3 OKM', OKM, '8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d' + '9d201395faa4b61a96c8');

  WriteLn('=== PBKDF2-HMAC-SHA256 (hashlib cross-checked) ===');
  DK := Pbkdf2HMACSHA256(TEncoding.UTF8.GetBytes('password'), TEncoding.UTF8.GetBytes('salt'), 1, 32);
  CheckBytes('PBKDF2 c=1', DK, '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
  DK := Pbkdf2HMACSHA256(TEncoding.UTF8.GetBytes('password'), TEncoding.UTF8.GetBytes('salt'), 2, 32);
  CheckBytes('PBKDF2 c=2', DK, 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
  DK := Pbkdf2HMACSHA256(TEncoding.UTF8.GetBytes('passwordPASSWORDpassword'), TEncoding.UTF8.GetBytes('saltSALTsaltSALTsaltSALTsaltSALTsalt'), 4096, 32);
  CheckBytes('PBKDF2 c=4096', DK, '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1');

  if Fails = 0 then
    WriteLn('ALL SHIELD KDF KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT(s) FAILED');

  if Fails > 0 then
    Halt(1);

end.
