program kat_argon2;

{ Argon2 KAT + block-level trace: prints per-pass B00[0..3] and B31[124..127]
  so the Pascal fill can be diffed block-by-block against the RFC-validated
  reference values, then checks final tags against argon2-cffi. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  uAvroArgon2;

type
  PBlockArr = ^TBlockArr;
  TBlockArr = array [0 .. 8191] of UInt64;

function HexW(const V: UInt64): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
  B: array [0 .. 7] of Byte;
begin
  for I := 0 to 7 do
    B[I] := Byte(V shr (I * 8));
  Result := '';
  for I := 7 downto 0 do
    Result := Result + H[B[I] shr 4] + H[B[I] and 15];
end;

var
  Pwd, Salt: TBytes;
  Got: string;
  Fails: Integer;

  procedure Trace(APass: Cardinal; const AMemory: Pointer;
    AMemoryBlocks, ALaneLength: Cardinal);
  var
    M: PBlockArr;
    GOut: array [0 .. 127] of UInt64;
  begin
    M := PBlockArr(AMemory);
    WriteLn(Format('  p%d B00 %s %s %s %s | B02 %s %s %s %s | B03 %s %s %s %s | B31 %s %s %s %s',
      [APass,
       HexW(M[0 * 128 + 0]), HexW(M[0 * 128 + 1]),
       HexW(M[0 * 128 + 2]), HexW(M[0 * 128 + 3]),
       HexW(M[2 * 128 + 0]), HexW(M[2 * 128 + 1]),
       HexW(M[2 * 128 + 2]), HexW(M[2 * 128 + 3]),
       HexW(M[3 * 128 + 0]), HexW(M[3 * 128 + 1]),
       HexW(M[3 * 128 + 2]), HexW(M[3 * 128 + 3]),
       HexW(M[31 * 128 + 124]), HexW(M[31 * 128 + 125]),
       HexW(M[31 * 128 + 126]), HexW(M[31 * 128 + 127])]));
    if APass = 0 then
    begin
      // G(prev=block1, ref=block0) should equal block 2's true value.
      Argon2DebugG(@M[1 * 128], @M[0 * 128], @GOut);
      WriteLn(Format('      G(B1,B0) = %s %s %s %s',
        [HexW(GOut[0]), HexW(GOut[1]), HexW(GOut[2]), HexW(GOut[3])]));
    end;
  end;

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

  procedure Check(const AName: string; AType: TArgon2Type;
    const AExpected: string);
  begin
    Got := HexOf(Argon2Hash(Pwd, Salt, AType, 3, 32, 4, 32));
    if Got = AExpected then
      WriteLn('PASS Argon2' + AName)
    else
    begin
      WriteLn('FAIL Argon2' + AName);
      WriteLn('  expected: ' + AExpected);
      WriteLn('  got     : ' + Got);
      Inc(Fails);
    end;
  end;

  { Extended vector: explicit params + password + salt, so different code
    paths get covered (lane-wrap prev_offset, multi-lane XOR, long tags). }
  procedure CheckV(const AName: string; AType: TArgon2Type;
    ATimeCost, AMemoryKib, AParallelism, ATagLen: Cardinal;
    const APwd, ASalt, AExpected: string);
  var
    P, S: TBytes;
  begin
    P := TEncoding.UTF8.GetBytes(APwd);
    S := TEncoding.ASCII.GetBytes(ASalt);
    Got := HexOf(Argon2Hash(P, S, AType, ATimeCost, AMemoryKib,
      AParallelism, ATagLen));
    if Got = AExpected then
      WriteLn('PASS ' + AName)
    else
    begin
      WriteLn('FAIL ' + AName);
      WriteLn('  expected: ' + AExpected);
      WriteLn('  got     : ' + Got);
      Inc(Fails);
    end;
  end;

begin
  Fails := 0;
  Pwd := TEncoding.UTF8.GetBytes('AvroShieldKAT');
  Salt := TEncoding.ASCII.GetBytes('somesalt');

  WriteLn('=== trace Argon2d ===');
  Argon2Hash(Pwd, Salt, atArgon2d, 1, 32, 1, 32, Trace);
  WriteLn('=== trace Argon2i ===');
  Argon2Hash(Pwd, Salt, atArgon2i, 1, 32, 1, 32, Trace);
  WriteLn('=== trace Argon2id ===');
  Argon2Hash(Pwd, Salt, atArgon2id, 1, 32, 1, 32, Trace);

  // Byte-exact vectors produced by argon2-cffi 25.x for the inputs above
  // (m=32, t=3, p=4, v=0x13), cross-checked against the RFC 9106 / phc
  // per-pass block oracles.
  Check('2d', atArgon2d, '5d956b4b79446ff2728028c956fbbd4c032702ae7cddd0d042a34793f9f684e5');
  Check('2i', atArgon2i, 'ff8af0fe4112e0685a127d0f9b15763bcc3828a75e56909b161bb03d0a0ade27');
  Check('2id', atArgon2id, '0065302a636090e1d1d692b6cdbfa94993100ff4b868e8c580ba2161d4bbc1d1');

  // Vectors produced by argon2-cffi 25.1.0 for the exact inputs below.
  CheckV('Argon2id t=4 m=16 p=1 tag=16', atArgon2id, 4, 16, 1, 16,
    'AvroShieldKAT', 'somesalt', 'f6cec1a9af1a563b2a079638c59b8481');
  CheckV('Argon2d t=2 m=64 p=2 tag=64', atArgon2d, 2, 64, 2, 64,
    'password', 'somesalt',
    'b08c1cf069953a887e2dce212bbebce2ee7e7d46a76347452d7f2ab21974d236' +
    'bd8e3324bdaa3fdefba18baf32c3dbad0c77bc21410d476c72da8bfde1735fc1');
  CheckV('Argon2i t=1 m=256 p=8 tag=32', atArgon2i, 1, 256, 8, 32,
    'longer password string here', '0123456789abcdef',
    '1522c9d02c68cc9d492cfc167e56f244573b424090c5d94c7330665292843eb2');
  CheckV('Argon2d t=1 m=256 p=8 tag=32', atArgon2d, 1, 256, 8, 32,
    'longer password string here', '0123456789abcdef',
    'd6251a239e0524984b1d67fbd40cccae02b1a1357ae3b88193e1a04bd5d6adee');
  CheckV('Argon2id t=2 m=64 p=2 tag=32', atArgon2id, 2, 64, 2, 32,
    'password', 'somesalt',
    '94387415dfb84ed1977465a1e8626073adf42bd4eeae1faa1dd4e23a1ff6859f');

  if Fails = 0 then
    WriteLn('ALL ARGON2 KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT(s) FAILED');

  if Fails > 0 then
    Halt(1);
end.
