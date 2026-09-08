{
  =============================================================================
  uAvroArgon2 - 100% Pure Pascal Argon2 (Blake2b based), RFC 9106 compatible.

  Faithful port of the reference phc-winner-argon2 v20190702 semantics so
  results are byte-identical with argon2-cffi (used by the AvroShield Python
  toolchain):
    - Argon2 version 0x13
    - Blake2b (RFC 7693) with 64-bit words, little endian
    - BlaMka compression G (multiplication based) inside fill_block
    - data-independent addressing blocks for Argon2i / Argon2id (first half
      of the first pass)
    - final tag = Blake2b-<taglen>( XOR of the lanes' last blocks )

  ZERO external DLLs. Memory cost is allocated and zeroed inside the call.
  All integers are UInt64 so overflows wrap modulo 2^64 exactly like C.
  =============================================================================
}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
unit uAvroArgon2;

interface

uses
  System.SysUtils;

type
  TArgon2Type = (atArgon2d = 0, atArgon2i = 1, atArgon2id = 2);

  { Optional per-pass callback (self-test only): AMemory points at the first
    of AMemoryBlocks TBlock values; ALaneLength blocks form one lane. }
  TArgon2TraceProc = reference to procedure(APass: Cardinal;
    const AMemory: Pointer; AMemoryBlocks, ALaneLength: Cardinal);

  { Self-test: G(prev, ref) compression on raw 1024-byte buffers. }
  procedure Argon2DebugG(const APrev, ARef: Pointer; AOut: Pointer);

{ Argon2 KDF. ATimeCost = passes, AMemoryKib = memory in KiB (block size
  1024 bytes), AParallelism = lanes, ATagLen = output length in bytes. }
function Argon2Hash(const APassword, ASalt: TBytes; AType: TArgon2Type;
  ATimeCost, AMemoryKib, AParallelism, ATagLen: Cardinal;
  ATrace: TArgon2TraceProc = nil): TBytes;

{ Argon2id shortcut used by the AvroShield container. }
function Argon2idHash(const APassword, ASalt: TBytes; ATimeCost, AMemoryKib,
  AParallelism, ATagLen: Cardinal): TBytes;

{ Blake2b (RFC 7693), exposed for the self-test KATs. }
function Blake2bHash(const AMessage: TBytes; AOutLen: Cardinal): TBytes;

// Debug / self-test helpers (kept exported: the self-test uses them).
function Argon2H0(const APassword, ASalt: TBytes; AType: TArgon2Type;
  ATimeCost, AMemoryKib, AParallelism, ATagLen: Cardinal): TBytes;
function Blake2bLong(const AInput: TBytes; AOutLen: Cardinal): TBytes;
function Blake2bKeyedHash(const AKey, AMessage: TBytes; AOutLen: Cardinal): TBytes;

implementation

const
  ARGON2_VERSION_NUMBER    = $13;
  ARGON2_SYNC_POINTS       = 4;
  ARGON2_QWORDS_IN_BLOCK   = 128;   // block = 128 x UInt64 = 1024 bytes
  ARGON2_ADDRESSES_IN_BLOCK = ARGON2_QWORDS_IN_BLOCK;
  ARGON2_BLOCK_SIZE        = 1024;

  BLAKE2B_OUTBYTES  = 64;
  BLAKE2B_BLOCKBYTES = 128;

  BB_F0: UInt64 = UInt64($FFFFFFFFFFFFFFFF);

type
  TBlock = array [0 .. ARGON2_QWORDS_IN_BLOCK - 1] of UInt64;
  PBlock = ^TBlock;
  TU64Vec16 = array [0 .. 15] of UInt64;

{ =============================================================================
  Blake2b
  ============================================================================= }

const
  bbIV: array [0 .. 7] of UInt64 = (
    $6A09E667F3BCC908, $BB67AE8584CAA73B, $3C6EF372FE94F82B, $A54FF53A5F1D36F1,
    $510E527FADE682D1, $9B05688C2B3E6C1F, $1F83D9ABFB41BD6B, $5BE0CD19137E2179);

  bbSigma: array [0 .. 9, 0 .. 15] of Byte = (
    (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15),
    (14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3),
    (11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4),
    (7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8),
    (9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13),
    (2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9),
    (12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11),
    (13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10),
    (6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5),
    (10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0));

type
  TBlake2bState = record
    h: array [0 .. 7] of UInt64;
    t: array [0 .. 1] of UInt64;
    buf: array [0 .. BLAKE2B_BLOCKBYTES - 1] of Byte;
    buflen: Cardinal;
    outlen: Cardinal;
  end;

function Rotr64(const X: UInt64; const N: Byte): UInt64;
begin
  if N = 0 then
    Result := X
  else
    Result := (X shr N) or (X shl (64 - N));
end;

{ Blake2b mixing G with message words x, y (RFC 7693). }
procedure bbG(var A, B, C, D: UInt64; const X, Y: UInt64);
begin
  A := A + B + X;
  D := Rotr64(D xor A, 32);
  C := C + D;
  B := Rotr64(B xor C, 24);
  A := A + B + Y;
  D := Rotr64(D xor A, 16);
  C := C + D;
  B := Rotr64(B xor C, 63);
end;

procedure bbRound(var V: TU64Vec16; const M: TU64Vec16; const R: Integer);
var
  S: Byte;
begin
  // Blake2b has 12 rounds but only 10 message-schedule rows: rows repeat
  // modulo 10 (rounds 10 and 11 reuse rows 0 and 1).
  S := Byte(R mod 10);
  bbG(V[0], V[4], V[8], V[12], M[bbSigma[S, 0]], M[bbSigma[S, 1]]);
  bbG(V[1], V[5], V[9], V[13], M[bbSigma[S, 2]], M[bbSigma[S, 3]]);
  bbG(V[2], V[6], V[10], V[14], M[bbSigma[S, 4]], M[bbSigma[S, 5]]);
  bbG(V[3], V[7], V[11], V[15], M[bbSigma[S, 6]], M[bbSigma[S, 7]]);
  bbG(V[0], V[5], V[10], V[15], M[bbSigma[S, 8]], M[bbSigma[S, 9]]);
  bbG(V[1], V[6], V[11], V[12], M[bbSigma[S, 10]], M[bbSigma[S, 11]]);
  bbG(V[2], V[7], V[8], V[13], M[bbSigma[S, 12]], M[bbSigma[S, 13]]);
  bbG(V[3], V[4], V[9], V[14], M[bbSigma[S, 14]], M[bbSigma[S, 15]]);
end;

procedure bbCompress(var S: TBlake2bState; const ABlock: PByte; ALast: Boolean);
var
  V: TU64Vec16;
  M: TU64Vec16;
  I: Integer;
begin
  for I := 0 to 15 do
    M[I] := UInt64(ABlock[I * 8]) or (UInt64(ABlock[I * 8 + 1]) shl 8) or
      (UInt64(ABlock[I * 8 + 2]) shl 16) or (UInt64(ABlock[I * 8 + 3]) shl 24) or
      (UInt64(ABlock[I * 8 + 4]) shl 32) or (UInt64(ABlock[I * 8 + 5]) shl 40) or
      (UInt64(ABlock[I * 8 + 6]) shl 48) or (UInt64(ABlock[I * 8 + 7]) shl 56);

  for I := 0 to 7 do
    V[I] := S.h[I];
  for I := 0 to 7 do
    V[I + 8] := bbIV[I];
  V[12] := V[12] xor S.t[0];
  V[13] := V[13] xor S.t[1];
  if ALast then
    V[14] := V[14] xor BB_F0;

  for I := 0 to 11 do
    bbRound(V, M, I);

  for I := 0 to 7 do
    S.h[I] := S.h[I] xor V[I] xor V[I + 8];
end;

procedure bbIncrementCounter(var S: TBlake2bState; const AInc: UInt64);
begin
  S.t[0] := S.t[0] + AInc;
  if S.t[0] < AInc then
    Inc(S.t[1]);
end;

procedure bbInit(var S: TBlake2bState; AOutLen, AKeyLen: Cardinal);
var
  I: Integer;
begin
  FillChar(S, SizeOf(S), 0);
  S.outlen := AOutLen;
  for I := 0 to 7 do
    S.h[I] := bbIV[I];
  // Parameter block: digest_length | key_length | fanout=1 | depth=1 ...
  S.h[0] := S.h[0] xor $01010000 xor (AKeyLen shl 8) xor UInt64(AOutLen);
end;

procedure bbUpdate(var S: TBlake2bState; const AData: TBytes);
var
  Off, Left, Fill: Integer;
begin
  Off := 0;
  Left := Length(AData);
  while Left > 0 do
  begin
    if S.buflen = BLAKE2B_BLOCKBYTES then
    begin
      bbIncrementCounter(S, BLAKE2B_BLOCKBYTES);
      bbCompress(S, @S.buf[0], False);
      S.buflen := 0;
    end;
    Fill := BLAKE2B_BLOCKBYTES - S.buflen;
    if Fill > Left then
      Fill := Left;
    Move(AData[Off], S.buf[S.buflen], Fill);
    Inc(S.buflen, Fill);
    Inc(Off, Fill);
    Dec(Left, Fill);
  end;
end;

function bbFinal(var S: TBlake2bState): TBytes;
var
  I: Integer;
begin
  bbIncrementCounter(S, S.buflen);
  for I := S.buflen to BLAKE2B_BLOCKBYTES - 1 do
    S.buf[I] := 0;
  bbCompress(S, @S.buf[0], True);

  SetLength(Result, S.outlen);
  for I := 0 to S.outlen - 1 do
    Result[I] := Byte(S.h[I div 8] shr ((I mod 8) * 8));
end;

function Blake2bHash(const AMessage: TBytes; AOutLen: Cardinal): TBytes;
var
  S: TBlake2bState;
begin
  bbInit(S, AOutLen, 0);
  bbUpdate(S, AMessage);
  Result := bbFinal(S);
end;

function Blake2bKeyedHash(const AKey, AMessage: TBytes; AOutLen: Cardinal): TBytes;
var
  S: TBlake2bState;
  KeyPad: TBytes;
  I: Integer;
begin
  if Length(AKey) > 64 then
    raise EArgumentException.Create('Blake2b key too long');
  bbInit(S, AOutLen, Cardinal(Length(AKey)));
  if Length(AKey) > 0 then
  begin
    SetLength(KeyPad, BLAKE2B_BLOCKBYTES);
    for I := 0 to BLAKE2B_BLOCKBYTES - 1 do
      KeyPad[I] := 0;
    Move(AKey[0], KeyPad[0], Length(AKey));
    bbUpdate(S, KeyPad);
  end;
  bbUpdate(S, AMessage);
  Result := bbFinal(S);
end;

{ Blake2b long hash used for Argon2 initial blocks (1024 bytes) and the
  final tag. Mirrors the reference blake2b_long() exactly:
    outlen <= 64 : blake2b(outlen) over (LE32(outlen) || in)
    outlen >  64 : chain of UNKEYED blake2b blocks, first 32 bytes emitted
                   per step, the last step over the remaining length. The
                   previous block is the MESSAGE of the next hash (not a
                   key!), matching phc-winner-argon2 v20190702
                   blake2/blake2b.c blake2b_long().
}
function Blake2bLong(const AInput: TBytes; AOutLen: Cardinal): TBytes;
var
  OutLenBytes: TBytes;
  S: TBlake2bState;
  Buf: TBytes;
  ToProduce: Integer;
  Partial: TBytes;
begin
  SetLength(OutLenBytes, 4);
  OutLenBytes[0] := Byte(AOutLen);
  OutLenBytes[1] := Byte(AOutLen shr 8);
  OutLenBytes[2] := Byte(AOutLen shr 16);
  OutLenBytes[3] := Byte(AOutLen shr 24);

  if AOutLen <= BLAKE2B_OUTBYTES then
  begin
    bbInit(S, AOutLen, 0);
    bbUpdate(S, OutLenBytes);
    bbUpdate(S, AInput);
    Result := bbFinal(S);
    Exit;
  end;

  // First 64-byte block over (LE32(outlen) || input); emit its first half.
  bbInit(S, BLAKE2B_OUTBYTES, 0);
  bbUpdate(S, OutLenBytes);
  bbUpdate(S, AInput);
  Buf := bbFinal(S);

  SetLength(Partial, BLAKE2B_OUTBYTES div 2);
  Move(Buf[0], Partial[0], BLAKE2B_OUTBYTES div 2);
  Result := Partial;

  ToProduce := Integer(AOutLen) - BLAKE2B_OUTBYTES div 2;
  while ToProduce > BLAKE2B_OUTBYTES do
  begin
    // Unkeyed blake2b-64 over the previous block (reference: NULL key).
    Buf := Blake2bHash(Buf, BLAKE2B_OUTBYTES);
    SetLength(Partial, BLAKE2B_OUTBYTES div 2);
    Move(Buf[0], Partial[0], BLAKE2B_OUTBYTES div 2);
    Result := Result + Partial;
    Dec(ToProduce, BLAKE2B_OUTBYTES div 2);
  end;

  Buf := Blake2bHash(Buf, Cardinal(ToProduce));
  SetLength(Partial, ToProduce);
  Move(Buf[0], Partial[0], ToProduce);
  Result := Result + Partial;
end;

{ =============================================================================
  Argon2 core
  ============================================================================= }

function BlaMka(const X, Y: UInt64): UInt64;
begin
  // x + y + 2 * trunc32(x) * trunc32(y)  (wraps modulo 2^64)
  Result := X + Y + 2 * ((X and $FFFFFFFF) * (Y and $FFFFFFFF));
end;

procedure GBlk(var A, B, C, D: UInt64);
begin
  A := BlaMka(A, B);
  D := Rotr64(D xor A, 32);
  C := BlaMka(C, D);
  B := Rotr64(B xor C, 24);
  A := BlaMka(A, B);
  D := Rotr64(D xor A, 16);
  C := BlaMka(C, D);
  B := Rotr64(B xor C, 63);
end;

procedure Blake2RoundVec(var V: TU64Vec16);
begin
  GBlk(V[0], V[4], V[8], V[12]);
  GBlk(V[1], V[5], V[9], V[13]);
  GBlk(V[2], V[6], V[10], V[14]);
  GBlk(V[3], V[7], V[11], V[15]);
  GBlk(V[0], V[5], V[10], V[15]);
  GBlk(V[1], V[6], V[11], V[12]);
  GBlk(V[2], V[7], V[8], V[13]);
  GBlk(V[3], V[4], V[9], V[14]);
end;

procedure Blake2Round16Cols(var R: TBlock; const ABase: Integer);
var
  V: TU64Vec16;
  I: Integer;
begin
  for I := 0 to 15 do
    V[I] := R[ABase + I];
  Blake2RoundVec(V);
  for I := 0 to 15 do
    R[ABase + I] := V[I];
end;

procedure Blake2Round16Rows(var R: TBlock; const ABase: Integer);
var
  V: TU64Vec16;
  K: Integer;
begin
  // Row arrangement: (2i, 2i+1, 16+2i, 17+2i, 32+2i, ... 112+2i, 113+2i)
  for K := 0 to 15 do
    V[K] := R[16 * (K shr 1) + 2 * ABase + (K and 1)];
  Blake2RoundVec(V);
  for K := 0 to 15 do
    R[16 * (K shr 1) + 2 * ABase + (K and 1)] := V[K];
end;

procedure FillBlock(const Prev, Ref: PBlock; var Next: TBlock; WithXor: Boolean);
var
  R, Tmp: TBlock;
  I: Integer;
begin
  R := Ref^;
  for I := 0 to ARGON2_QWORDS_IN_BLOCK - 1 do
    R[I] := R[I] xor Prev^[I];       // R = ref xor prev
  Tmp := R;
  if WithXor then
    for I := 0 to ARGON2_QWORDS_IN_BLOCK - 1 do
      Tmp[I] := Tmp[I] xor Next[I];

  // Apply the Blake2 round function on columns of 16 64-bit words...
  for I := 0 to 7 do
    Blake2Round16Cols(R, 16 * I);
  // ...then on rows of 16 words strided by two.
  for I := 0 to 7 do
    Blake2Round16Rows(R, I);

  for I := 0 to ARGON2_QWORDS_IN_BLOCK - 1 do
    Next[I] := Tmp[I] xor R[I];
end;

procedure NextAddresses(var AAddr, AInput: TBlock; const AZero: PBlock);
begin
  Inc(AInput[6]);
  FillBlock(AZero, @AInput, AAddr, False);
  FillBlock(AZero, @AAddr, AAddr, False);
end;

function IndexAlpha(const ALaneLength, ASegmentLength, APass, ASlice,
  AIndex: Cardinal; APseudoRand: Cardinal; ASameLane: Boolean): Cardinal;
var
  RefAreaSize: Cardinal;
  RelPos: UInt64;
  StartPos: Cardinal;
begin
  if APass = 0 then
  begin
    if ASlice = 0 then
      RefAreaSize := AIndex - 1
    else if ASameLane then
      RefAreaSize := ASlice * ASegmentLength + AIndex - 1
    else if AIndex = 0 then
      RefAreaSize := ASlice * ASegmentLength - 1
    else
      RefAreaSize := ASlice * ASegmentLength;
  end
  else
  begin
    if ASameLane then
      RefAreaSize := ALaneLength - ASegmentLength + AIndex - 1
    else if AIndex = 0 then
      RefAreaSize := ALaneLength - ASegmentLength - 1
    else
      RefAreaSize := ALaneLength - ASegmentLength;
  end;

  RelPos := APseudoRand;
  RelPos := (RelPos * RelPos) shr 32;
  RelPos := RefAreaSize - 1 - ((UInt64(RefAreaSize) * RelPos) shr 32);

  StartPos := 0;
  if APass <> 0 then
  begin
    if ASlice <> ARGON2_SYNC_POINTS - 1 then
      StartPos := (ASlice + 1) * ASegmentLength;
  end;
  Result := (StartPos + Cardinal(RelPos)) mod ALaneLength;
end;

procedure Argon2DebugG(const APrev, ARef: Pointer; AOut: Pointer);
var
  N: TBlock;
begin
  FillBlock(PBlock(APrev), PBlock(ARef), N, False);
  Move(N, AOut^, SizeOf(N));
  FillChar(N, SizeOf(N), 0);
end;

function Argon2H0(const APassword, ASalt: TBytes; AType: TArgon2Type;
  ATimeCost, AMemoryKib, AParallelism, ATagLen: Cardinal): TBytes;

  procedure AppendLE32(var ABuf: TBytes; const AValue: Cardinal);
  var
    Old: Integer;
  begin
    Old := Length(ABuf);
    SetLength(ABuf, Old + 4);
    ABuf[Old] := Byte(AValue);
    ABuf[Old + 1] := Byte(AValue shr 8);
    ABuf[Old + 2] := Byte(AValue shr 16);
    ABuf[Old + 3] := Byte(AValue shr 24);
  end;

var
  Msg: TBytes;
begin
  // H0 = Blake2b-64(p, taglen, m, T, v, y, |P|, P, |S|, S, |K|, |X|)
  Msg := nil;
  AppendLE32(Msg, AParallelism);
  AppendLE32(Msg, ATagLen);
  AppendLE32(Msg, AMemoryKib);
  AppendLE32(Msg, ATimeCost);
  AppendLE32(Msg, ARGON2_VERSION_NUMBER);
  AppendLE32(Msg, Cardinal(AType));
  AppendLE32(Msg, Cardinal(Length(APassword)));
  Msg := Msg + APassword;
  AppendLE32(Msg, Cardinal(Length(ASalt)));
  Msg := Msg + ASalt;
  AppendLE32(Msg, 0);
  AppendLE32(Msg, 0);
  Result := Blake2bHash(Msg, 64);
end;

function Argon2Hash(const APassword, ASalt: TBytes; AType: TArgon2Type;
  ATimeCost, AMemoryKib, AParallelism, ATagLen: Cardinal;
  ATrace: TArgon2TraceProc): TBytes;

  procedure AppendLE32(var ABuf: TBytes; const AValue: Cardinal);
  var
    Old: Integer;
  begin
    Old := Length(ABuf);
    SetLength(ABuf, Old + 4);
    ABuf[Old] := Byte(AValue);
    ABuf[Old + 1] := Byte(AValue shr 8);
    ABuf[Old + 2] := Byte(AValue shr 16);
    ABuf[Old + 3] := Byte(AValue shr 24);
  end;

var
  Lanes, Passes, MemBlocks, TagLen, V, Typ: Cardinal;
  Memory: array of TBlock;
  MPrime, LaneLength, SegLength: Cardinal;
  Lane, Pass, Slice, I, J: Cardinal;
  H0: TBytes;
  BlockHash: TBytes;
  B: TBlock;
  ZeroBlk: TBlock;
  AddrBlk, InputBlk: TBlock;
  DataIndependent: Boolean;
  WithXor: Boolean;
  PseudoRand, RefIndex, RefLane: UInt64;
  CurrOffset, PrevOffset, StartIndex: Cardinal;
  SameLane: Boolean;
  FinalMsg: TBytes;
begin
  Result := nil;
  if (AParallelism = 0) or (AParallelism > $FFFFFF) or
    (AMemoryKib < 8 * AParallelism) or (AMemoryKib > $FFFFFF) or
    (ATimeCost = 0) then
    raise EArgumentException.Create('Invalid Argon2 parameters');

  Lanes := AParallelism;
  Passes := ATimeCost;
  MemBlocks := AMemoryKib;      // each block is 1 KiB
  TagLen := ATagLen;
  V := ARGON2_VERSION_NUMBER;
  Typ := Cardinal(AType);

  // m' = 4 * lanes * floor(memory / (4 * lanes))
  MPrime := 4 * Lanes * (MemBlocks div (4 * Lanes));
  LaneLength := MPrime div Lanes;
  SegLength := LaneLength div ARGON2_SYNC_POINTS;

  H0 := Argon2H0(APassword, ASalt, AType, ATimeCost, AMemoryKib,
    AParallelism, ATagLen);

  // ---- allocate memory ----
  SetLength(Memory, MPrime);

  // ---- first two blocks of each lane ----
  for Lane := 0 to Lanes - 1 do
  begin
    BlockHash := H0;
    AppendLE32(BlockHash, 0);
    AppendLE32(BlockHash, Lane);
    FillChar(B, SizeOf(B), 0);
    Move(Blake2bLong(BlockHash, ARGON2_BLOCK_SIZE)[0], B, ARGON2_BLOCK_SIZE);
    Memory[Lane * LaneLength] := B;

    BlockHash := H0;
    AppendLE32(BlockHash, 1);
    AppendLE32(BlockHash, Lane);
    FillChar(B, SizeOf(B), 0);
    Move(Blake2bLong(BlockHash, ARGON2_BLOCK_SIZE)[0], B, ARGON2_BLOCK_SIZE);
    Memory[Lane * LaneLength + 1] := B;
  end;

  FillChar(ZeroBlk, SizeOf(ZeroBlk), 0);

  // ---- fill segments ----
  for Pass := 0 to Passes - 1 do
  begin
    for Slice := 0 to ARGON2_SYNC_POINTS - 1 do
      for Lane := 0 to Lanes - 1 do
      begin
        DataIndependent := (AType = atArgon2i) or
          ((AType = atArgon2id) and (Pass = 0) and (Slice < ARGON2_SYNC_POINTS div 2));
        WithXor := (Pass <> 0);

        if DataIndependent then
        begin
          FillChar(InputBlk, SizeOf(InputBlk), 0);
          InputBlk[0] := Pass;
          InputBlk[1] := Lane;
          InputBlk[2] := Slice;
          InputBlk[3] := MPrime;
          InputBlk[4] := Passes;
          InputBlk[5] := Typ;
        end;

        StartIndex := 0;
        if (Pass = 0) and (Slice = 0) then
        begin
          StartIndex := 2;  // first two blocks already generated
          if DataIndependent then
            NextAddresses(AddrBlk, InputBlk, @ZeroBlk);
        end;

        CurrOffset := Lane * LaneLength + Slice * SegLength + StartIndex;
        if (CurrOffset mod LaneLength) = 0 then
          PrevOffset := CurrOffset + LaneLength - 1
        else
          PrevOffset := CurrOffset - 1;

        I := StartIndex;
        while I < SegLength do
        begin
          // Rotate prev_offset back to curr-1 right after a lane start.
          if (CurrOffset mod LaneLength) = 1 then
            PrevOffset := CurrOffset - 1;

          if DataIndependent then
          begin
            if (I mod ARGON2_ADDRESSES_IN_BLOCK) = 0 then
              NextAddresses(AddrBlk, InputBlk, @ZeroBlk);
            PseudoRand := AddrBlk[I mod ARGON2_ADDRESSES_IN_BLOCK];
          end
          else
            PseudoRand := Memory[PrevOffset][0];

          if (Pass = 0) and (Slice = 0) then
            RefLane := Lane
          else
            RefLane := (PseudoRand shr 32) mod Lanes;
          SameLane := (RefLane = Lane);

          RefIndex := IndexAlpha(LaneLength, SegLength, Pass, Slice, I,
            Cardinal(PseudoRand and $FFFFFFFF), SameLane);

          FillBlock(@Memory[PrevOffset],
            @Memory[Cardinal(RefLane) * LaneLength + RefIndex],
            Memory[CurrOffset], WithXor);

          Inc(I);
          Inc(CurrOffset);
          Inc(PrevOffset);
        end;
      end;
    if Assigned(ATrace) then
      ATrace(Pass, @Memory[0], MPrime, LaneLength);
  end;

  // ---- final tag: Blake2b-<taglen>( XOR of lanes' last blocks ) ----
  FinalMsg := nil;
  try
    B := Memory[LaneLength - 1];
    for Lane := 1 to Lanes - 1 do
      for J := 0 to ARGON2_QWORDS_IN_BLOCK - 1 do
        B[J] := B[J] xor Memory[Lane * LaneLength + (LaneLength - 1)][J];
    SetLength(FinalMsg, ARGON2_BLOCK_SIZE);
    Move(B, FinalMsg[0], ARGON2_BLOCK_SIZE);
    Result := Blake2bLong(FinalMsg, TagLen);
  finally
    FillChar(B, SizeOf(B), 0);
    FillChar(FinalMsg[0], Length(FinalMsg), 0);
    SetLength(FinalMsg, 0);
    FillChar(ZeroBlk, SizeOf(ZeroBlk), 0);
  end;

  // Wipe the whole memory arena.
  FillChar(Memory[0], Length(Memory) * SizeOf(TBlock), 0);
  SetLength(Memory, 0);
end;

function Argon2idHash(const APassword, ASalt: TBytes; ATimeCost, AMemoryKib,
  AParallelism, ATagLen: Cardinal): TBytes;
begin
  Result := Argon2Hash(APassword, ASalt, atArgon2id, ATimeCost, AMemoryKib,
    AParallelism, ATagLen);
end;

end.
