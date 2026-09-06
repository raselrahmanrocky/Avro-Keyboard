{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

unit uAvroCryptoUtils;

{ =============================================================================
  uAvroCryptoUtils - 100% Pure Pascal AES-256-CBC cryptographic engine.

  PURPOSE
    Provides a self-contained Rijndael AES-256 (128-bit block, 14 rounds)
    engine with CBC chaining and PKCS#7 padding/validation for the protected
    ".AvroEnco" ANSI mapping loader. The engine has ZERO external DLL
    dependencies: no bcrypt.dll, no advapi32.dll, no OpenSSL. Only the
    System.Hash RTL unit is used, for SHA-256 key derivation.

  SECURITY / MEMORY CONTRACT
    * The engine is stateless: every key schedule and block buffer is a local
      stack/heap variable, so it is re-entrant and safe from any thread.
    * Working buffers holding decrypted (plaintext) data are zero-filled
      before they are released.
    * No plaintext is ever written to disk by this unit.
    * Encrypt/decrypt behavior is identical on Win32 and Win64.

  ============================================================================= }

interface

uses
  System.SysUtils,
  System.Hash;

const
  AES_BLOCK_SIZE = 16; // 128-bit Rijndael block

{ PKCS#7-pads APlain and CBC-encrypts it with a 256-bit key (32 bytes).
  AKey must be 32 bytes and AIV 16 bytes, otherwise EArgumentException is
  raised. The ciphertext is always a multiple of AES_BLOCK_SIZE. }
procedure AES256CBCEncryptBytes(const APlain, AKey, AIV: TBytes; out ACipher: TBytes);

{ CBC-decrypts ACipher with a 256-bit key (32 bytes) and strictly validates
  the PKCS#7 padding. Returns False when the key is wrong, the data is
  corrupted, or lengths are invalid - the caller must treat False as
  "wrong password / corrupted file". On success APlain holds exactly the
  unpadded plaintext. }
function AES256CBCDecryptBytes(const ACipher, AKey, AIV: TBytes; out APlain: TBytes): Boolean;

{ Key derivation used by the .AvroEnco v2 container:
      key := SHA-256( UTF-8(ASecretString) + ASalt )
  Matching helper for Tools/build_avroenco.py (password.encode('utf-8') + salt). }
function DeriveKeySHA256FromString(const ASecretString: string; const ASalt: TBytes): TBytes;

{ Key derivation used by the legacy .AvroEnco v1 container (raw bytes + salt):
      key := SHA-256( ARawSecret + ASalt ) }
function DeriveKeySHA256FromRawBytes(const ARawSecret: TBytes; const ASalt: TBytes): TBytes;

implementation

type
  TBlock         = array [0 .. 15] of Byte;
  TAesKeySchedule = array [0 .. 239] of Byte; // 60 words x 4 bytes (AES-256)

const
  AES_NK = 8;  // 32-byte key
  AES_NR = 14; // rounds for AES-256

  { Rijndael substitution box (FIPS-197, appendix A) }
  SBOX: array [0 .. 255] of Byte = (
    $63, $7C, $77, $7B, $F2, $6B, $6F, $C5, $30, $01, $67, $2B, $FE, $D7, $AB, $76,
    $CA, $82, $C9, $7D, $FA, $59, $47, $F0, $AD, $D4, $A2, $AF, $9C, $A4, $72, $C0,
    $B7, $FD, $93, $26, $36, $3F, $F7, $CC, $34, $A5, $E5, $F1, $71, $D8, $31, $15,
    $04, $C7, $23, $C3, $18, $96, $05, $9A, $07, $12, $80, $E2, $EB, $27, $B2, $75,
    $09, $83, $2C, $1A, $1B, $6E, $5A, $A0, $52, $3B, $D6, $B3, $29, $E3, $2F, $84,
    $53, $D1, $00, $ED, $20, $FC, $B1, $5B, $6A, $CB, $BE, $39, $4A, $4C, $58, $CF,
    $D0, $EF, $AA, $FB, $43, $4D, $33, $85, $45, $F9, $02, $7F, $50, $3C, $9F, $A8,
    $51, $A3, $40, $8F, $92, $9D, $38, $F5, $BC, $B6, $DA, $21, $10, $FF, $F3, $D2,
    $CD, $0C, $13, $EC, $5F, $97, $44, $17, $C4, $A7, $7E, $3D, $64, $5D, $19, $73,
    $60, $81, $4F, $DC, $22, $2A, $90, $88, $46, $EE, $B8, $14, $DE, $5E, $0B, $DB,
    $E0, $32, $3A, $0A, $49, $06, $24, $5C, $C2, $D3, $AC, $62, $91, $95, $E4, $79,
    $E7, $C8, $37, $6D, $8D, $D5, $4E, $A9, $6C, $56, $F4, $EA, $65, $7A, $AE, $08,
    $BA, $78, $25, $2E, $1C, $A6, $B4, $C6, $E8, $DD, $74, $1F, $4B, $BD, $8B, $8A,
    $70, $3E, $B5, $66, $48, $03, $F6, $0E, $61, $35, $57, $B9, $86, $C1, $1D, $9E,
    $E1, $F8, $98, $11, $69, $D9, $8E, $94, $9B, $1E, $87, $E9, $CE, $55, $28, $DF,
    $8C, $A1, $89, $0D, $BF, $E6, $42, $68, $41, $99, $2D, $0F, $B0, $54, $BB, $16
  );

  { Inverse substitution box }
  INV_SBOX: array [0 .. 255] of Byte = (
    $52, $09, $6A, $D5, $30, $36, $A5, $38, $BF, $40, $A3, $9E, $81, $F3, $D7, $FB,
    $7C, $E3, $39, $82, $9B, $2F, $FF, $87, $34, $8E, $43, $44, $C4, $DE, $E9, $CB,
    $54, $7B, $94, $32, $A6, $C2, $23, $3D, $EE, $4C, $95, $0B, $42, $FA, $C3, $4E,
    $08, $2E, $A1, $66, $28, $D9, $24, $B2, $76, $5B, $A2, $49, $6D, $8B, $D1, $25,
    $72, $F8, $F6, $64, $86, $68, $98, $16, $D4, $A4, $5C, $CC, $5D, $65, $B6, $92,
    $6C, $70, $48, $50, $FD, $ED, $B9, $DA, $5E, $15, $46, $57, $A7, $8D, $9D, $84,
    $90, $D8, $AB, $00, $8C, $BC, $D3, $0A, $F7, $E4, $58, $05, $B8, $B3, $45, $06,
    $D0, $2C, $1E, $8F, $CA, $3F, $0F, $02, $C1, $AF, $BD, $03, $01, $13, $8A, $6B,
    $3A, $91, $11, $41, $4F, $67, $DC, $EA, $97, $F2, $CF, $CE, $F0, $B4, $E6, $73,
    $96, $AC, $74, $22, $E7, $AD, $35, $85, $E2, $F9, $37, $E8, $1C, $75, $DF, $6E,
    $47, $F1, $1A, $71, $1D, $29, $C5, $89, $6F, $B7, $62, $0E, $AA, $18, $BE, $1B,
    $FC, $56, $3E, $4B, $C6, $D2, $79, $20, $9A, $DB, $C0, $FE, $78, $CD, $5A, $F4,
    $1F, $DD, $A8, $33, $88, $07, $C7, $31, $B1, $12, $10, $59, $27, $80, $EC, $5F,
    $60, $51, $7F, $A9, $19, $B5, $4A, $0D, $2D, $E5, $7A, $9F, $93, $C9, $9C, $EF,
    $A0, $E0, $3B, $4D, $AE, $2A, $F5, $B0, $C8, $EB, $BB, $3C, $83, $53, $99, $61,
    $17, $2B, $04, $7E, $BA, $77, $D6, $26, $E1, $69, $14, $63, $55, $21, $0C, $7D
  );

  { Round constants used by the key schedule (x^8+x^4+x^3+x+1 reduction) }
  RCON: array [0 .. 9] of Byte = ($01, $02, $04, $08, $10, $20, $40, $80, $1B, $36);

{ Multiply by x in GF(2^8) modulo x^8+x^4+x^3+x+1 }
function XTimes(const A: Byte): Byte;
begin
  if (A and $80) <> 0 then
    Result := Byte((A shl 1) xor $1B)
  else
    Result := Byte(A shl 1);
end;

{ General GF(2^8) multiply (used by InvMixColumns) }
function GMul(A, B: Byte): Byte;
var
  R: Byte;
  I: Integer;
begin
  R := 0;
  for I := 0 to 7 do
  begin
    if (B and 1) <> 0 then
      R := R xor A;
    A := XTimes(A);
    B := B shr 1;
  end;
  Result := R;
end;

{ =============================================================================
  AES-256 key expansion (FIPS-197 section 5.2). Produces a 240-byte schedule
  laid out so that the round key for 'Round' is:
      ASchedule[16*Round + 4*Col + Row]
  (column-major, matching the state layout below). }
procedure ExpandKey(const AKey: TBytes; out ASchedule: TAesKeySchedule);
var
  Words: array [0 .. 59] of Cardinal;
  I:     Integer;
  Temp:  Cardinal;
  B:     array [0 .. 3] of Byte;
begin
  if Length(AKey) < 32 then
    raise EArgumentException.Create('AES-256 requires a 32-byte key.');

  for I := 0 to 7 do
    Words[I] := (Cardinal(AKey[I * 4]) shl 24) or (Cardinal(AKey[I * 4 + 1]) shl 16) or
      (Cardinal(AKey[I * 4 + 2]) shl 8) or Cardinal(AKey[I * 4 + 3]);

  for I := 8 to 59 do
  begin
    Temp := Words[I - 1];

    if (I mod AES_NK) = 0 then
    begin
      // RotWord + SubWord, then XOR with Rcon on the top byte.
      B[0] := Byte(Temp shr 24);
      B[1] := Byte(Temp shr 16);
      B[2] := Byte(Temp shr 8);
      B[3] := Byte(Temp);
      Temp := (Cardinal(SBOX[B[1]]) shl 24) or (Cardinal(SBOX[B[2]]) shl 16) or
        (Cardinal(SBOX[B[3]]) shl 8) or Cardinal(SBOX[B[0]]);
      Temp := Temp xor (Cardinal(RCON[(I div AES_NK) - 1]) shl 24);
    end
    else if (I mod AES_NK) = 4 then
    begin
      // SubWord only (AES-256 rule, FIPS-197 5.2)
      B[0] := Byte(Temp shr 24);
      B[1] := Byte(Temp shr 16);
      B[2] := Byte(Temp shr 8);
      B[3] := Byte(Temp);
      Temp := (Cardinal(SBOX[B[0]]) shl 24) or (Cardinal(SBOX[B[1]]) shl 16) or
        (Cardinal(SBOX[B[2]]) shl 8) or Cardinal(SBOX[B[3]]);
    end;

    Words[I] := Words[I - AES_NK] xor Temp;
  end;

  for I := 0 to 59 do
  begin
    ASchedule[I * 4]     := Byte(Words[I] shr 24);
    ASchedule[I * 4 + 1] := Byte(Words[I] shr 16);
    ASchedule[I * 4 + 2] := Byte(Words[I] shr 8);
    ASchedule[I * 4 + 3] := Byte(Words[I]);
  end;
end;

{ Add round key 'ARound' to the state (column-major). }
procedure AddRoundKey(var AState: TBlock; const ASchedule: TAesKeySchedule; ARound: Integer);
var
  Col, Row: Integer;
begin
  for Col := 0 to 3 do
    for Row := 0 to 3 do
      AState[4 * Col + Row] := AState[4 * Col + Row] xor ASchedule[16 * ARound + 4 * Col + Row];
end;

procedure SubBytes(var AState: TBlock);
var
  I: Integer;
begin
  for I := 0 to 15 do
    AState[I] := SBOX[AState[I]];
end;

procedure InvSubBytes(var AState: TBlock);
var
  I: Integer;
begin
  for I := 0 to 15 do
    AState[I] := INV_SBOX[AState[I]];
end;

procedure ShiftRows(var AState: TBlock);
var
  T: Byte;
begin
  // Row 1: rotate left 1
  T            := AState[1];
  AState[1]    := AState[5];
  AState[5]    := AState[9];
  AState[9]    := AState[13];
  AState[13]   := T;
  // Row 2: rotate left 2
  T            := AState[2];
  AState[2]    := AState[10];
  AState[10]   := T;
  T            := AState[6];
  AState[6]    := AState[14];
  AState[14]   := T;
  // Row 3: rotate left 3
  T            := AState[15];
  AState[15]   := AState[11];
  AState[11]   := AState[7];
  AState[7]    := AState[3];
  AState[3]    := T;
end;

procedure InvShiftRows(var AState: TBlock);
var
  T: Byte;
begin
  // Row 1: rotate right 1
  T            := AState[13];
  AState[13]   := AState[9];
  AState[9]    := AState[5];
  AState[5]    := AState[1];
  AState[1]    := T;
  // Row 2: rotate right 2 (same as left 2)
  T            := AState[2];
  AState[2]    := AState[10];
  AState[10]   := T;
  T            := AState[6];
  AState[6]    := AState[14];
  AState[14]   := T;
  // Row 3: rotate right 3
  T            := AState[3];
  AState[3]    := AState[7];
  AState[7]    := AState[11];
  AState[11]   := AState[15];
  AState[15]   := T;
end;

procedure MixColumns(var AState: TBlock);
var
  Col: Integer;
  A0, A1, A2, A3, Tmp, Tm: Byte;
begin
  for Col := 0 to 3 do
  begin
    A0 := AState[4 * Col];
    A1 := AState[4 * Col + 1];
    A2 := AState[4 * Col + 2];
    A3 := AState[4 * Col + 3];

    Tmp := A0 xor A1 xor A2 xor A3;

    Tm        := A0 xor A1;
    Tm        := XTimes(Tm);
    AState[4 * Col]     := A0 xor Tm xor Tmp;

    Tm        := A1 xor A2;
    Tm        := XTimes(Tm);
    AState[4 * Col + 1] := A1 xor Tm xor Tmp;

    Tm        := A2 xor A3;
    Tm        := XTimes(Tm);
    AState[4 * Col + 2] := A2 xor Tm xor Tmp;

    Tm        := A3 xor A0;
    Tm        := XTimes(Tm);
    AState[4 * Col + 3] := A3 xor Tm xor Tmp;
  end;
end;

procedure InvMixColumns(var AState: TBlock);
var
  Col: Integer;
  A0, A1, A2, A3: Byte;
begin
  for Col := 0 to 3 do
  begin
    A0 := AState[4 * Col];
    A1 := AState[4 * Col + 1];
    A2 := AState[4 * Col + 2];
    A3 := AState[4 * Col + 3];

    AState[4 * Col]     := GMul(A0, $0E) xor GMul(A1, $0B) xor GMul(A2, $0D) xor GMul(A3, $09);
    AState[4 * Col + 1] := GMul(A0, $09) xor GMul(A1, $0E) xor GMul(A2, $0B) xor GMul(A3, $0D);
    AState[4 * Col + 2] := GMul(A0, $0D) xor GMul(A1, $09) xor GMul(A2, $0E) xor GMul(A3, $0B);
    AState[4 * Col + 3] := GMul(A0, $0B) xor GMul(A1, $0D) xor GMul(A2, $09) xor GMul(A3, $0E);
  end;
end;

{ Encrypt a single 128-bit block. }
procedure AesEncryptBlock(const ASchedule: TAesKeySchedule; const AIn: TBlock; var AOut: TBlock);
var
  State: TBlock;
  Round: Integer;
  I:     Integer;
begin
  State := AIn;
  AddRoundKey(State, ASchedule, 0);

  for Round := 1 to AES_NR - 1 do
  begin
    SubBytes(State);
    ShiftRows(State);
    MixColumns(State);
    AddRoundKey(State, ASchedule, Round);
  end;

  SubBytes(State);
  ShiftRows(State);
  AddRoundKey(State, ASchedule, AES_NR);

  for I := 0 to 15 do
    AOut[I] := State[I];
end;

{ Decrypt a single 128-bit block. }
procedure AesDecryptBlock(const ASchedule: TAesKeySchedule; const AIn: TBlock; var AOut: TBlock);
var
  State: TBlock;
  Round: Integer;
  I:     Integer;
begin
  State := AIn;
  AddRoundKey(State, ASchedule, AES_NR);

  for Round := AES_NR - 1 downto 1 do
  begin
    InvShiftRows(State);
    InvSubBytes(State);
    AddRoundKey(State, ASchedule, Round);
    InvMixColumns(State);
  end;

  InvShiftRows(State);
  InvSubBytes(State);
  AddRoundKey(State, ASchedule, 0);

  for I := 0 to 15 do
    AOut[I] := State[I];
end;

{ =============================================================================
  Public API
  ============================================================================= }

procedure AES256CBCEncryptBytes(const APlain, AKey, AIV: TBytes; out ACipher: TBytes);
var
  Schedule: TAesKeySchedule;
  InBlk, OutBlk, PrevBlk: TBlock;
  Padded:   TBytes;
  PadLen:   Integer;
  I, Off:   Integer;
  Index:    Integer;
begin
  ACipher := nil;
  if (Length(AKey) <> 32) then
    raise EArgumentException.Create('AES-256 requires a 32-byte key.');
  if (Length(AIV) <> AES_BLOCK_SIZE) then
    raise EArgumentException.Create('AES-CBC requires a 16-byte IV.');

  ExpandKey(AKey, Schedule);

  // PKCS#7 pad
  PadLen := AES_BLOCK_SIZE - (Length(APlain) mod AES_BLOCK_SIZE);
  SetLength(Padded, Length(APlain) + PadLen);
  if Length(APlain) > 0 then
    Move(APlain[0], Padded[0], Length(APlain));
  for I := 0 to PadLen - 1 do
    Padded[Length(APlain) + I] := Byte(PadLen);

  SetLength(ACipher, Length(Padded));
  FillChar(PrevBlk, AES_BLOCK_SIZE, 0);
  Move(AIV[0], PrevBlk[0], AES_BLOCK_SIZE);

  Off := 0;
  while Off < Length(Padded) do
  begin
    for Index := 0 to 15 do
      InBlk[Index] := Padded[Off + Index] xor PrevBlk[Index];
    AesEncryptBlock(Schedule, InBlk, OutBlk);
    Move(OutBlk[0], ACipher[Off], AES_BLOCK_SIZE);
    PrevBlk := OutBlk;
    Inc(Off, AES_BLOCK_SIZE);
  end;

  FillChar(Padded[0], Length(Padded), 0);
  SetLength(Padded, 0);
end;

function AES256CBCDecryptBytes(const ACipher, AKey, AIV: TBytes; out APlain: TBytes): Boolean;
var
  Schedule: TAesKeySchedule;
  InBlk, OutBlk, PrevBlk: TBlock;
  Padded:   TBytes;
  PadLen:   Integer;
  I, Off:   Integer;
  Index:    Integer;
begin
  APlain := nil;
  Result := False;

  if (Length(AKey) <> 32) or (Length(AIV) <> AES_BLOCK_SIZE) then
    Exit;
  if (Length(ACipher) = 0) or ((Length(ACipher) mod AES_BLOCK_SIZE) <> 0) then
    Exit;

  ExpandKey(AKey, Schedule);

  SetLength(Padded, Length(ACipher));
  FillChar(PrevBlk, AES_BLOCK_SIZE, 0);
  Move(AIV[0], PrevBlk[0], AES_BLOCK_SIZE);

  Off := 0;
  while Off < Length(ACipher) do
  begin
    Move(ACipher[Off], InBlk[0], AES_BLOCK_SIZE);
    AesDecryptBlock(Schedule, InBlk, OutBlk);
    for Index := 0 to 15 do
      Padded[Off + Index] := OutBlk[Index] xor PrevBlk[Index];
    PrevBlk := InBlk;
    Inc(Off, AES_BLOCK_SIZE);
  end;

  // Strict PKCS#7 validation: last byte 1..16, all pad bytes identical.
  PadLen := Padded[Length(Padded) - 1];
  if (PadLen < 1) or (PadLen > AES_BLOCK_SIZE) then
  begin
    FillChar(Padded[0], Length(Padded), 0);
    SetLength(Padded, 0);
    Exit;
  end;
  for I := Length(Padded) - PadLen to Length(Padded) - 1 do
    if Padded[I] <> Byte(PadLen) then
    begin
      FillChar(Padded[0], Length(Padded), 0);
      SetLength(Padded, 0);
      Exit;
    end;

  SetLength(APlain, Length(Padded) - PadLen);
  if Length(APlain) > 0 then
    Move(Padded[0], APlain[0], Length(APlain));

  FillChar(Padded[0], Length(Padded), 0);
  SetLength(Padded, 0);
  Result := True;
end;

function DeriveKeySHA256FromString(const ASecretString: string; const ASalt: TBytes): TBytes;
var
  H: THashSHA2;
  SecretBytes: TBytes;
begin
  SecretBytes := TEncoding.UTF8.GetBytes(ASecretString);
  try
    // key := SHA-256( UTF-8(secret) + salt )
    H := THashSHA2.Create; // initializes the hash state machine (SHA-256)
    H.Update(SecretBytes);
    H.Update(ASalt);
    Result := H.HashAsBytes;
  finally
    FillChar(SecretBytes[0], Length(SecretBytes), 0);
    SetLength(SecretBytes, 0);
  end;
end;

function DeriveKeySHA256FromRawBytes(const ARawSecret: TBytes; const ASalt: TBytes): TBytes;
var
  H: THashSHA2;
begin
  // key := SHA-256( raw secret bytes + salt )  [legacy v1 semantics]
  H := THashSHA2.Create; // initializes the hash state machine (SHA-256)
  H.Update(ARawSecret);
  H.Update(ASalt);
  Result := H.HashAsBytes;
end;

end.
