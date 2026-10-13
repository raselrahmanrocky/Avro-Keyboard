{ =============================================================================
  uAvroEd25519 - pure-Pascal Ed25519 signature verification (verify only).

  WHY PURE PASCAL
  ---------------
  The keyboard engine deliberately has no dependency on bcrypt.dll,
  advapi32.dll or OpenSSL: every primitive it needs (SHA-256/512, HMAC, HKDF,
  PBKDF2, AES-256-GCM) is already hand-rolled in this project so the shipped
  binary imports only kernel32/user32. The signed resource manifest is verified
  at runtime, so its verifier has to obey the same rule - and Windows CNG has
  no stable Ed25519 provider across the supported OS range anyway. (The Qt
  converter under Converter\ does link bcrypt; the keyboard engine does not.)

  This is a faithful port of the VERIFY half of TweetNaCl (public domain,
  Bernstein, Janssen, Lange, Schwabe). Only crypto_sign_open's logic is kept:
  point decompression (unpackneg), scalar multiplication, SHA-512 and the mod-L
  reduction. Key generation and signing are NOT here - the offline signer
  (tools/resource-sync/sign_manifest.py) uses the Python cryptography package.

  Verification equation (RFC 8032, section 5.1.7):

    R = sig[0..31], S = sig[32..63], A = public key
    h = SHA-512(R || A || M) reduced mod L
    accept iff  S*B - h*A == R    (computed as R' = pack(S*B - h*A), R' == R)

  Gf elements are 16 signed 64-bit limbs (radix 2^16), exactly as in TweetNaCl,
  which is why overflow/range checking must stay off in this unit. The unit is
  verify-only on purpose: a verifier that also carried a signing path would be
  a larger attack surface for no benefit in the shipped binary.
  ============================================================================= }

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
{ Inlining OFF: CryptoVerify32 carries a VMProtect marker, and an inlined
  marked routine leaves an unprotected copy of the comparison in its caller. }
{$INLINE OFF}
unit uAvroEd25519;

interface

uses
  System.SysUtils;

const
  AVRO_ED25519_PUBLIC_KEY_LEN = 32;
  AVRO_ED25519_SIGNATURE_LEN  = 64;

{ Verifies an Ed25519 signature. True only when ASignature is a valid signature
  of AMessage under APubKey. The final comparison is constant-time and every
  intermediate buffer is wiped before returning. }
function AvroEd25519Verify(const APubKey, AMessage, ASignature: TBytes): Boolean;

implementation

uses
  System.Hash,
  uAvroSecureMem,
  uAvroShieldVM;

type
  { 16 limbs of 16 bits, signed 64-bit accumulator. }
  TGf      = array [0 .. 15] of Int64;
  { An extended-coordinate point: X, Y, Z, T. }
  TGfPoint = array [0 .. 3] of TGf;
  { A 32-byte fixed buffer. }
  TByte32  = array [0 .. 31] of Byte;

const
  GF0: TGf = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  GF1: TGf = (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

  { Curve constants, transcribed from TweetNaCl. }
  ED_D: TGf = ($78a3, $1359, $4dca, $75eb, $d8ab, $4141, $0a4d, $0070, $e898, $7779, $4079, $8cc7, $fe73, $2b6f, $6cee, $5203);
  ED_D2: TGf = ($f159, $26b2, $9b94, $ebd6, $b156, $8283, $149a, $00e0, $d130, $eef3, $80f2, $198e, $fce7, $56df, $d9dc, $2406);
  ED_X: TGf = ($d51a, $8f25, $2d60, $c956, $a7b2, $9525, $c760, $692c, $dc5c, $fdd6, $e231, $c0a4, $53fe, $cd6e, $36d3, $2169);
  ED_Y: TGf = ($6658, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666, $6666);
  ED_I: TGf = ($a0b0, $4a0e, $1b27, $c4ee, $e478, $ad2f, $1806, $2f43, $d7a7, $3dfb, $0099, $2b4d, $df0b, $4fc1, $2480, $2b83);

  { L = 2^252 + 27742317777372353535851937790883648493, little-endian bytes. }
  ED_L: array [0 .. 31] of Int64 = ($ed, $d3, $f5, $5c, $1a, $63, $12, $58, $d6, $9c, $f7, $a2, $de, $f9, $de, $14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,

    $10);

{ -----------------------------------------------------------------------------
  Field arithmetic (radix 2^16)
  ----------------------------------------------------------------------------- }

{ Arithmetic shift right, which Delphi's shr is NOT: shr always fills with
  zeroes, while TweetNaCl's C code depends on >> sign-extending (limbs go
  negative between operations, and the carry propagation reads that sign).
  For a negative value, ~((~V) shr N) is exactly the sign-extending shift. }
function Sar64(AValue: Int64; ABits: Integer): Int64; inline;
begin
  if AValue >= 0 then
    Result := AValue shr ABits
  else
    Result := not ((not AValue) shr ABits);
end;

procedure GfSet(var R: TGf; const A1: TGf);
var
  I: Integer;
begin
  for I := 0 to 15 do
    R[I] := A1[I];
end;

{ Reduce the limbs modulo 2^255 - 19 by carrying, then folding the top carry
  back in (times 38, i.e. 2*19, because of the 2^256 headroom). }
procedure GfCar(var O: TGf);
var
  I: Integer;
  C: Int64;
begin
  for I := 0 to 15 do
  begin
    O[I] := O[I] + (Int64(1) shl 16);
    C := Sar64(O[I], 16);
    if I < 15 then
      O[I + 1] := O[I + 1] + (C - 1)
    else
      O[0] := O[0] + (C - 1) + 37 * (C - 1);
    O[I] := O[I] - (C shl 16);
  end;
end;

{ Constant-time conditional swap of P and Q when B = 1 (no-op when B = 0). }
procedure GfSel(var P, Q: TGf; B: Integer);
var
  I: Integer;
  T, C: Int64;
begin
  C := not Int64(B - 1);
  for I := 0 to 15 do
  begin
    T := C and (P[I] xor Q[I]);
    P[I] := P[I] xor T;
    Q[I] := Q[I] xor T;
  end;
end;

{ Canonical little-endian encoding of N (fully reduced). }
procedure GfPack(out O: TByte32; const N: TGf);
var
  I, J, B: Integer;
  M, T: TGf;
begin
  for I := 0 to 15 do
    T[I] := N[I];
  GfCar(T);
  GfCar(T);
  GfCar(T);
  for J := 0 to 1 do
  begin
    M[0] := T[0] - $ffed;
    for I := 1 to 14 do
    begin
      M[I] := T[I] - $ffff - (Sar64(M[I - 1], 16) and 1);
      M[I - 1] := M[I - 1] and $ffff;
    end;
    M[15] := T[15] - $7fff - (Sar64(M[14], 16) and 1);
    B := Sar64(M[15], 16) and 1;
    M[14] := M[14] and $ffff;
    GfSel(T, M, 1 - B);
  end;
  for I := 0 to 15 do
  begin
    O[2 * I] := Byte(T[I] and $ff);
    O[2 * I + 1] := Byte(Sar64(T[I], 8) and $ff);
  end;
end;

procedure GfUnpack(var O: TGf; const N: TByte32);
var
  I: Integer;
begin
  for I := 0 to 15 do
    O[I] := Int64(N[2 * I]) + (Int64(N[2 * I + 1]) shl 8);
  O[15] := O[15] and $7fff;
end;

procedure GfAdd(var O: TGf; const A1, B1: TGf);
var
  I: Integer;
begin
  for I := 0 to 15 do
    O[I] := A1[I] + B1[I];
end;

procedure GfSub(var O: TGf; const A1, B1: TGf);
var
  I: Integer;
begin
  for I := 0 to 15 do
    O[I] := A1[I] - B1[I];
end;

procedure GfMul(var O: TGf; const A1, B1: TGf);
var
  I, J: Integer;
  T: array [0 .. 30] of Int64;
begin
  for I := 0 to 30 do
    T[I] := 0;
  for I := 0 to 15 do
    for J := 0 to 15 do
      T[I + J] := T[I + J] + A1[I] * B1[J];
  for I := 0 to 14 do
    T[I] := T[I] + 38 * T[I + 16];
  for I := 0 to 15 do
    O[I] := T[I];
  GfCar(O);
  GfCar(O);
end;

procedure GfSqr(var O: TGf; const A1: TGf);
begin
  GfMul(O, A1, A1);
end;

{ O = A1^-1 via the fixed addition chain (a^(2^255 - 21)). }
procedure GfInv(var O: TGf; const A1: TGf);
var
  C: TGf;
  A: Integer;
begin
  for A := 0 to 15 do
    C[A] := A1[A];
  for A := 253 downto 0 do
  begin
    GfSqr(C, C);
    if (A <> 2) and (A <> 4) then
      GfMul(C, C, A1);
  end;
  for A := 0 to 15 do
    O[A] := C[A];
end;

{ O = A1^((p-5)/8), the square-root helper used by point decompression. }
procedure GfPow2523(var O: TGf; const A1: TGf);
var
  C: TGf;
  A: Integer;
begin
  for A := 0 to 15 do
    C[A] := A1[A];
  for A := 250 downto 0 do
  begin
    GfSqr(C, C);
    if A <> 1 then
      GfMul(C, C, A1);
  end;
  for A := 0 to 15 do
    O[A] := C[A];
end;

{ 0 when the two are equal as field elements, non-zero otherwise. Virtualised:
  this comparison is on the verify path's critical control flow. }
function CryptoVerify32(const X, Y: TByte32): Integer;
var
  I: Integer;
  D: Cardinal;
begin
  VMBeginVirtualization('edv');
  D := 0;
  for I := 0 to 31 do
    D := D or Cardinal(X[I] xor Y[I]);
  Result := Integer(1 and ((D - 1) shr 8)) - 1;
  VMEnd;
end;

function GfNeq(const A1, B1: TGf): Integer;
var
  C, D: TByte32;
begin
  GfPack(C, A1);
  GfPack(D, B1);
  Result := CryptoVerify32(C, D);
end;

function GfPar(const A1: TGf): Byte;
var
  D: TByte32;
begin
  GfPack(D, A1);
  Result := D[0] and 1;
end;

{ -----------------------------------------------------------------------------
  Group arithmetic
  ----------------------------------------------------------------------------- }

{ Extended-coordinate point addition: P += Q. }
procedure PointAdd(var P: TGfPoint; const Q: TGfPoint);
var
  Va, Vb, Vc, Vd, Vt, Ve, Vf, Vg, Vh: TGf;
begin
  GfSub(Va, P[1], P[0]);
  GfSub(Vt, Q[1], Q[0]);
  GfMul(Va, Va, Vt);
  GfAdd(Vb, P[0], P[1]);
  GfAdd(Vt, Q[0], Q[1]);
  GfMul(Vb, Vb, Vt);
  GfMul(Vc, P[3], Q[3]);
  GfMul(Vc, Vc, ED_D2);
  GfMul(Vd, P[2], Q[2]);
  GfAdd(Vd, Vd, Vd);
  GfSub(Ve, Vb, Va);
  GfSub(Vf, Vd, Vc);
  GfAdd(Vg, Vd, Vc);
  GfAdd(Vh, Vb, Va);

  GfMul(P[0], Ve, Vf);
  GfMul(P[1], Vh, Vg);
  GfMul(P[2], Vg, Vf);
  GfMul(P[3], Ve, Vh);
end;

procedure PointCswap(var P, Q: TGfPoint; B: Integer);
var
  I: Integer;
begin
  for I := 0 to 3 do
    GfSel(P[I], Q[I], B);
end;

{ Encodes P into the 32-byte compressed form; the sign bit of x is stored in
  the top bit of y. }
procedure PointPack(out R: TByte32; const P: TGfPoint);
var
  Tx, Ty, Zi: TGf;
begin
  GfInv(Zi, P[2]);
  GfMul(Tx, P[0], Zi);
  GfMul(Ty, P[1], Zi);
  GfPack(R, Ty);
  R[31] := R[31] xor (GfPar(Tx) shl 7);
end;

{ P = S * Q, standard double-and-add-always over the 256 scalar bits. }
procedure ScalarMult(var P: TGfPoint; var Q: TGfPoint; const S: TByte32);
var
  I: Integer;
  B: Byte;
begin
  GfSet(P[0], GF0);
  GfSet(P[1], GF1);
  GfSet(P[2], GF1);
  GfSet(P[3], GF0);
  for I := 255 downto 0 do
  begin
    B := (S[I div 8] shr (I and 7)) and 1;
    PointCswap(P, Q, B);
    PointAdd(Q, P);
    PointAdd(P, P);
    PointCswap(P, Q, B);
  end;
end;

{ P = S * B, B the curve base point. }
procedure ScalarBase(var P: TGfPoint; const S: TByte32);
var
  Q: TGfPoint;
begin
  GfSet(Q[0], ED_X);
  GfSet(Q[1], ED_Y);
  GfSet(Q[2], GF1);
  GfMul(Q[3], ED_X, ED_Y);
  ScalarMult(P, Q, S);
  AvroSecureZero(Q, SizeOf(Q));
end;

{ Scalar reduction modulo L (Barrett-style, as in TweetNaCl). }
procedure ModL(out R: TByte32; var X: array of Int64);
var
  Carry: Int64;
  I, J: Integer;
begin
  for I := 63 downto 32 do
  begin
    Carry := 0;
    for J := I - 32 to I - 13 do
    begin
      X[J] := X[J] + Carry - 16 * X[I] * ED_L[J - (I - 32)];
      Carry := Sar64(X[J] + 128, 8);
      X[J] := X[J] - (Carry shl 8);
    end;
    X[I - 12] := X[I - 12] + Carry;
    X[I] := 0;
  end;
  Carry := 0;
  for J := 0 to 31 do
  begin
    X[J] := X[J] + Carry - Sar64(X[31], 4) * ED_L[J];
    Carry := Sar64(X[J], 8);
    X[J] := X[J] and 255;
  end;
  for J := 0 to 31 do
    X[J] := X[J] - Carry * ED_L[J];
  for I := 0 to 31 do
  begin
    X[I + 1] := X[I + 1] + Sar64(X[I], 8);
    R[I] := Byte(X[I] and 255);
  end;
end;

procedure ScalarReduce(out R: TByte32; const H64: TBytes);
var
  X: array [0 .. 63] of Int64;
  I: Integer;
begin
  for I := 0 to 63 do
    X[I] := Int64(H64[I]);
  ModL(R, X);
  AvroSecureZero(X, SizeOf(X));
end;

{ Decompresses a public key into -A. Returns 0 on success, -1 when the bytes
  are not a valid curve point. }
function UnpackNeg(var R: TGfPoint; const P: TByte32): Integer;
var
  T, Chk, Num, Den, Den2, Den4, Den6: TGf;
begin
  GfSet(R[2], GF1);
  GfUnpack(R[1], P);
  GfSqr(Num, R[1]);
  GfMul(Den, Num, ED_D);
  GfSub(Num, Num, R[2]);
  GfAdd(Den, R[2], Den);

  GfSqr(Den2, Den);
  GfSqr(Den4, Den2);
  GfMul(Den6, Den4, Den2);
  GfMul(T, Den6, Num);
  GfMul(T, T, Den);

  GfPow2523(T, T);
  GfMul(T, T, Num);
  GfMul(T, T, Den);
  GfMul(T, T, Den);
  GfMul(R[0], T, Den);

  GfSqr(Chk, R[0]);
  GfMul(Chk, Chk, Den);
  if GfNeq(Chk, Num) <> 0 then
    GfMul(R[0], R[0], ED_I);

  GfSqr(Chk, R[0]);
  GfMul(Chk, Chk, Den);
  if GfNeq(Chk, Num) <> 0 then
  begin
    AvroSecureZero(T, SizeOf(T));
    AvroSecureZero(Chk, SizeOf(Chk));
    AvroSecureZero(Num, SizeOf(Num));
    AvroSecureZero(Den, SizeOf(Den));
    AvroSecureZero(Den2, SizeOf(Den2));
    AvroSecureZero(Den4, SizeOf(Den4));
    AvroSecureZero(Den6, SizeOf(Den6));
    Exit(-1);
  end;

  if GfPar(R[0]) = (P[31] shr 7) then
    GfSub(R[0], GF0, R[0]);

  GfMul(R[3], R[0], R[1]);
  Result := 0;

  AvroSecureZero(T, SizeOf(T));
  AvroSecureZero(Chk, SizeOf(Chk));
  AvroSecureZero(Num, SizeOf(Num));
  AvroSecureZero(Den, SizeOf(Den));
  AvroSecureZero(Den2, SizeOf(Den2));
  AvroSecureZero(Den4, SizeOf(Den4));
  AvroSecureZero(Den6, SizeOf(Den6));
end;

{ -----------------------------------------------------------------------------
  Public entry point
  ----------------------------------------------------------------------------- }

function AvroEd25519Verify(const APubKey, AMessage, ASignature: TBytes): Boolean;
var
  P, Q: TGfPoint;
  H: TByte32;
  RPart, SPart, PK, Recovered: TByte32;
  HashInput, Digest: TBytes;
  I: Integer;
  Hash: THashSHA2;
begin
  Result := False;
  if Length(APubKey) <> AVRO_ED25519_PUBLIC_KEY_LEN then
    Exit;
  if Length(ASignature) <> AVRO_ED25519_SIGNATURE_LEN then
    Exit;

  for I := 0 to 31 do
    PK[I] := APubKey[I];
  for I := 0 to 31 do
    RPart[I] := ASignature[I];
  for I := 0 to 31 do
    SPart[I] := ASignature[32 + I];

  if UnpackNeg(Q, PK) <> 0 then
  begin
    AvroSecureZero(PK, SizeOf(PK));
    AvroSecureZero(Q, SizeOf(Q));
    Exit;
  end;

  { h = SHA-512(R || A || M) mod L. }
  SetLength(HashInput, 64 + Length(AMessage));
  for I := 0 to 31 do
    HashInput[I] := RPart[I];
  for I := 0 to 31 do
    HashInput[32 + I] := PK[I];
  if Length(AMessage) > 0 then
    Move(AMessage[0], HashInput[64], Length(AMessage));

  Hash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  Hash.Update(HashInput);
  Digest := Hash.HashAsBytes;
  ScalarReduce(H, Digest);

  ScalarMult(P, Q, H);   // P = h * (-A)
  ScalarBase(Q, SPart);  // Q = S * B
  PointAdd(P, Q);        // P = S*B - h*A
  PointPack(Recovered, P);

  Result := CryptoVerify32(RPart, Recovered) = 0;

  AvroWipeAndRelease(HashInput);
  AvroWipeAndRelease(Digest);
  AvroSecureZero(H, SizeOf(H));
  AvroSecureZero(RPart, SizeOf(RPart));
  AvroSecureZero(SPart, SizeOf(SPart));
  AvroSecureZero(PK, SizeOf(PK));
  AvroSecureZero(Recovered, SizeOf(Recovered));
  AvroSecureZero(P, SizeOf(P));
  AvroSecureZero(Q, SizeOf(Q));
end;

end.
