{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}

{ The AES/PKCS#7 and Shield-decryption arithmetic is ported from Python and
  intentionally wraps (unbounded ints). With the IDE Debug configuration
  (overflow/range checks ON) those wrap-arounds raise EIntOverflow and every
  container fails to decrypt. Keep checks off here - the arithmetic is
  deliberately modular. }
{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

unit uAvroEncoCrypto;

{ =============================================================================
  uAvroEncoCrypto - .AvroEnco container reader/writer.

  The container is a binary blob that is always decrypted ENTIRELY IN RAM:

    v2 (current):
      [0..8]   9 bytes  'AVROENCO' + $02
      [9]      1 byte   Protection flag:
                           $00 = Default Application Key (no prompt)
                           $01 = User Password
      [10..25] 16 bytes Salt
      [26..41] 16 bytes IV
      [42..N]  AES-256-CBC ciphertext, PKCS#7 padded

    v1 (legacy, read-only):
      [0..8]   9 bytes  'AVROENCO' + $01
      [9..24] 16 bytes Salt
      [25..40]16 bytes IV
      [41..N]  AES-256-CBC ciphertext, PKCS#7 padded
      (password-only, key = SHA-256(raw password bytes + salt))

  Key derivation (v2):
      key = SHA-256( UTF-8(secret) + salt )
      where secret = the built-in default application secret, reconstructed
      at runtime from two XOR-masked byte arrays via
      uAvroCryptoUtils.GetAvroEncoDefaultSecret (flag $00), or the user
      password (flag $01). SHA-256 comes from System.Hash (pure RTL).

  Cryptographic engine: uAvroCryptoUtils - a 100% Pure Pascal AES-256-CBC
  engine with ZERO external DLL dependencies. No bcrypt.dll / advapi32.dll /
  OpenSSL is used anywhere in this unit.

  SECURITY CONTRACT
    * Decrypted plaintext lives only in private TBytes buffers / strings in
      RAM. It is NEVER written to a file or temporary file.
    * Plaintext TBytes buffers are zero-filled before being released.
    * Wrong password / corrupted data fails decryption (PKCS#7 validation);
      callers must treat an empty result as "cannot load" and keep the
      previously active mapping.
    * Files protected with the default application key (flag $00) decrypt
      transparently without any password.
  ============================================================================= }

interface

uses
  SysUtils,
  Classes;

const
  // Container version markers: 'AVROENCO' + version byte.
  AVROENCO_MAGIC_BASE: array [0 .. 7] of Byte = (
    $41, $56, $52, $4F, $45, $4E, $43, $4F
  );
  AVROENCO_MAGIC_TAIL_V1 = $01; // legacy (read-only support)
  AVROENCO_MAGIC_TAIL_V2 = $02; // current container

  AVROENCO_FLAG_DEFAULT_KEY     = $00; // protected with the built-in app secret
  AVROENCO_FLAG_USER_PASSWORD   = $01; // protected with a user password
  AVROENCO_FLAG_INVALID         = $FF; // header could not be read

  SALT_SIZE  = 16;
  IV_SIZE    = 16;
  MAGIC_SIZE = 9; // 8 base bytes + version byte

  V1_HEADER_SIZE = MAGIC_SIZE + SALT_SIZE + IV_SIZE; // 41 bytes
  V2_HEADER_SIZE = V1_HEADER_SIZE + 1;               // 42 bytes (flag byte)

  // Shield-format container markers: 'AVROSHLD' + version byte. The Shield
  // container shares the .AvroEnco extension with the legacy CBC format;
  // detection is by magic bytes, so both formats coexist under one extension.
  AVROSHLD_MAGIC: array [0 .. 7] of Byte = (
    $41, $56, $52, $4F, $53, $48, $4C, $44
  );
  AVROSHLD_VERSION = $01;
  // Shield layout: header(58) + ciphertext + auth_tag(16) + hmac(64).
  AVROSHLD_HEADER_SIZE = 58;
  AVROSHLD_TRAILER_SIZE = 80; // auth_tag(16) + hmac(64)
  AVROSHLD_MIN_SIZE = AVROSHLD_HEADER_SIZE + AVROSHLD_TRAILER_SIZE + 1;

  // Default Application Key secret. NOT stored as a plain string: it is
  // reconstructed at runtime from two XOR-masked byte arrays in
  // uAvroCryptoUtils.GetAvroEncoDefaultSecret, so a 'strings' dump of the
  // binary reveals only random-looking tables. The builder shares this unit,
  // so runtime and offline tooling stay in sync automatically.

function ValidateAvroEncoHeader(const AFilePath: string): Boolean;
// Protection mode of the file:
//   AVROENCO_FLAG_USER_PASSWORD for v1 legacy files and v2 flag $01 files,
//   AVROENCO_FLAG_DEFAULT_KEY for v2 flag $00 files,
//   AVROENCO_FLAG_INVALID when the header is unreadable.
function GetAvroEncoProtectionFlag(const AFilePath: string): Byte;
// Decrypts the file in RAM and returns the clean UTF-8 JSON text
// (leading U+FEFF / UTF-8 BOM stripped). Returns '' when decryption fails
// (wrong password, corrupted data, missing file).
// For flag $00 files APassword is ignored.
function DecryptAvroEncoToString(const AFilePath: string; const APassword: AnsiString): string;
// True only when the decrypted content looks like a valid mapping JSON
// (starts with '{' after trimming).
function ValidateAvroEncoPassword(const AFilePath: string; const APassword: AnsiString): Boolean;
// True when the file is a Shield-format container (magic 'AVROSHLD' + $01).
// Both container formats share the .AvroEnco extension; the crypto layer
// tells them apart by these magic bytes.
function IsAvroShieldContainer(const AFilePath: string): Boolean;
// Writes a v2 container. APassword = '' produces a default-key protected
// file (flag $00, loads without prompting); a non-empty APassword produces
// a password protected file (flag $01).
function EncryptJsonToAvroEncoFile(const AJsonText: string; const APassword: AnsiString; const AOutFilePath: string): Boolean;

implementation

uses
  uAvroCryptoUtils,
  uAvroShield,
  DebugLog;

type
  TAvroEncoFormat = (aefInvalid, aefV1, aefV2);

// Reads the raw bytes of a small binary file (header + ciphertext only).
function ReadFileBytes(const AFilePath: string; out ABytes: TBytes): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  ABytes := nil;
  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(ABytes, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(ABytes[0], FS.Size);
    finally
      FS.Free;
    end;
    Result := True;
  except
    ABytes := nil;
  end;
end;

function DetectFormat(const AFileBytes: TBytes): TAvroEncoFormat;
begin
  Result := aefInvalid;
  if Length(AFileBytes) < MAGIC_SIZE then
    Exit;
  if not CompareMem(@AFileBytes[0], @AVROENCO_MAGIC_BASE[0], 8) then
    Exit;
  case AFileBytes[8] of
    AVROENCO_MAGIC_TAIL_V1: Result := aefV1;
    AVROENCO_MAGIC_TAIL_V2: Result := aefV2;
  end;
end;

function HasAvroShieldMagic(const AFileBytes: TBytes): Boolean;
begin
  Result := (Length(AFileBytes) >= MAGIC_SIZE) and
    CompareMem(@AFileBytes[0], @AVROSHLD_MAGIC[0], 8) and
    (AFileBytes[8] = AVROSHLD_VERSION);
end;

function IsAvroShieldContainer(const AFilePath: string): Boolean;
var
  FileBytes: TBytes;
begin
  Result := False;
  if not FileExists(AFilePath) then
    Exit;
  if not ReadFileBytes(AFilePath, FileBytes) then
    Exit;
  try
    Result := HasAvroShieldMagic(FileBytes);
  finally
    FillChar(FileBytes[0], Length(FileBytes), 0);
    SetLength(FileBytes, 0);
  end;
end;

function ValidateAvroEncoHeader(const AFilePath: string): Boolean;
var
  FileBytes: TBytes;
  Format:    TAvroEncoFormat;
  MinSize:   Integer;
begin
  Result := False;
  if not FileExists(AFilePath) then
    Exit;
  if not ReadFileBytes(AFilePath, FileBytes) then
    Exit;
  try
    // Shield-format container (magic 'AVROSHLD'): valid shape is header +
    // at least one cipher byte + auth tag + HMAC trailer.
    if HasAvroShieldMagic(FileBytes) then
      Exit(Length(FileBytes) >= AVROSHLD_MIN_SIZE);

    Format := DetectFormat(FileBytes);
    case Format of
      aefV1: MinSize := V1_HEADER_SIZE + AES_BLOCK_SIZE;
      aefV2: MinSize := V2_HEADER_SIZE + AES_BLOCK_SIZE;
    else
      MinSize := MaxInt;
    end;
    Result := Length(FileBytes) >= MinSize;
  finally
    FillChar(FileBytes[0], Length(FileBytes), 0);
    SetLength(FileBytes, 0);
  end;
end;

function GetAvroEncoProtectionFlag(const AFilePath: string): Byte;
var
  FileBytes: TBytes;
begin
  // Shield-format containers (magic 'AVROSHLD') are password protected UNLESS
  // they carry the default-key flag (AVROSHLD_FLAG_DEFAULT_KEY), in which case
  // they unlock transparently with the built-in obfuscated secret, exactly
  // like v2 flag $00 files. Detection is by magic bytes, not extension - both
  // container formats share the .AvroEnco extension.
  if IsAvroShieldContainer(AFilePath) then
  begin
    if AvroShieldContainerUsesDefaultKey(AFilePath) then
      Exit(AVROENCO_FLAG_DEFAULT_KEY)
    else
      Exit(AVROENCO_FLAG_USER_PASSWORD);
  end;

  Result := AVROENCO_FLAG_INVALID;
  if not FileExists(AFilePath) then
    Exit;
  if not ReadFileBytes(AFilePath, FileBytes) then
    Exit;
  try
    case DetectFormat(FileBytes) of
      aefV1:
        // Legacy containers are always password protected.
        Result := AVROENCO_FLAG_USER_PASSWORD;
      aefV2:
        begin
          if Length(FileBytes) >= V2_HEADER_SIZE then
            Result := FileBytes[9];
        end;
    end;
  finally
    FillChar(FileBytes[0], Length(FileBytes), 0);
    SetLength(FileBytes, 0);
  end;
end;

// Converts an AnsiString to raw (code-page) bytes - used only by the legacy
// v1 derivation so existing v1 files keep decrypting exactly as before.
function AnsiStringToRawBytes(const AValue: AnsiString): TBytes;
var
  L: Integer;
begin
  L := Length(AValue);
  SetLength(Result, L);
  if L > 0 then
    Move(AValue[1], Result[0], L);
end;

// Core decrypt: reads the file into RAM, decrypts into a private TBytes
// buffer, converts to a UTF-8 string (BOM stripped) and zeroes the plaintext
// buffer. Nothing is ever written to disk.
function DecryptAvroEncoToContent(const AFilePath: string; const APassword: AnsiString; out AContent: string): Boolean;
var
  FileBytes, Salt, IV, KeyBytes, Cipher, PlainBuf: TBytes;
  Format: TAvroEncoFormat;
  Flag:   Byte;
  Off:    Integer;
  I:      Integer;
begin
  Result := False;
  AContent := '';

  if not FileExists(AFilePath) then
    Exit;

  FileBytes := nil;
  if not ReadFileBytes(AFilePath, FileBytes) then
    Exit;

  try
    Format := DetectFormat(FileBytes);
    case Format of
      aefV1:
        begin
          if Length(FileBytes) < V1_HEADER_SIZE + AES_BLOCK_SIZE then
            Exit;
          SetLength(Salt, SALT_SIZE);
          Move(FileBytes[MAGIC_SIZE], Salt[0], SALT_SIZE);
          SetLength(IV, IV_SIZE);
          Move(FileBytes[MAGIC_SIZE + SALT_SIZE], IV[0], IV_SIZE);
          Off := V1_HEADER_SIZE;
          KeyBytes := DeriveKeySHA256FromRawBytes(AnsiStringToRawBytes(APassword), Salt);
        end;
      aefV2:
        begin
          if Length(FileBytes) < V2_HEADER_SIZE + AES_BLOCK_SIZE then
            Exit;
          Flag := FileBytes[9];
          SetLength(Salt, SALT_SIZE);
          Move(FileBytes[10], Salt[0], SALT_SIZE);
          SetLength(IV, IV_SIZE);
          Move(FileBytes[26], IV[0], IV_SIZE);
          Off := V2_HEADER_SIZE;
          if Flag = AVROENCO_FLAG_DEFAULT_KEY then
            KeyBytes := DeriveKeySHA256FromString(GetAvroEncoDefaultSecret, Salt)
          else
            KeyBytes := DeriveKeySHA256FromString(string(APassword), Salt);
        end;
    else
      Exit; // unknown / corrupt header
    end;

    SetLength(Cipher, Length(FileBytes) - Off);
    if Length(Cipher) > 0 then
      Move(FileBytes[Off], Cipher[0], Length(Cipher));

    if not AES256CBCDecryptBytes(Cipher, KeyBytes, IV, PlainBuf) then
    begin
      // Wrong key / corrupt data. Zero everything sensitive.
      FillChar(KeyBytes[0], Length(KeyBytes), 0);
      SetLength(KeyBytes, 0);
      FillChar(Cipher[0], Length(Cipher), 0);
      SetLength(Cipher, 0);
      Exit;
    end;

    FillChar(KeyBytes[0], Length(KeyBytes), 0);
    SetLength(KeyBytes, 0);

    if Length(PlainBuf) > 0 then
    begin
      try
        // A lucky-padding corruption can yield bytes that are not valid UTF-8;
        // conversion must never raise - treat it as a failed decrypt.
        AContent := TEncoding.UTF8.GetString(PlainBuf);
        // TEncoding.UTF8.GetString does NOT consume a leading UTF-8 BOM - it
        // decodes it to U+FEFF as the first character. The mapping JSON files
        // are saved with a BOM, so strip it here so callers always receive
        // clean JSON starting with '{'.
        if (AContent <> '') and (AContent[1] = #$FEFF) then
          Delete(AContent, 1, 1);
        Result := (AContent <> '');
      except
        Result := False;
        AContent := '';
      end;
      // Erase the intermediate plaintext buffer immediately.
      for I := 0 to Length(PlainBuf) - 1 do
        PlainBuf[I] := 0;
      SetLength(PlainBuf, 0);
    end;

    FillChar(Cipher[0], Length(Cipher), 0);
    SetLength(Cipher, 0);
  finally
    FillChar(FileBytes[0], Length(FileBytes), 0);
    SetLength(FileBytes, 0);
  end;
end;

function DecryptAvroEncoToString(const AFilePath: string; const APassword: AnsiString): string;
var
  R: TAvroShieldResult;
begin
  Result := '';

  // Shield-format containers (magic 'AVROSHLD') decrypt through the
  // AvroShield runtime stack (HMAC verify -> AES-GCM decrypt -> zlib ->
  // bytecode -> deobfuscate), entirely in RAM. Password is mandatory; machine
  // binding is enabled so machine-bound files load on this machine while
  // portable files load too. Detection is by container magic, not extension:
  // both the legacy CBC format and the Shield format share the .AvroEnco
  // extension.
  if IsAvroShieldContainer(AFilePath) then
  begin
    try
      R := AvroShieldLoadFromFile(AFilePath, string(APassword), Result, True);
      Log('AvroShieldLoadFromFile(' + ExtractFileName(AFilePath) +
        ') -> asr=' + IntToStr(Ord(R)) + ' len=' + IntToStr(Length(Result)));
      if R <> asrOk then
        Result := '';
      Result := Trim(Result);
    except
      on E: Exception do
      begin
        Log('AvroShieldLoadFromFile exception: ' + E.Message);
        Result := '';
      end;
    end;
    Exit;
  end;

  // This API never raises: every failure (missing/corrupt file, wrong
  // password, encoding problems) surfaces as an empty result so callers can
  // keep the previously active mapping without crashing.
  try
    DecryptAvroEncoToContent(AFilePath, APassword, Result);
  except
    Result := '';
  end;
end;

function ValidateAvroEncoPassword(const AFilePath: string; const APassword: AnsiString): Boolean;
var
  JsonStr: string;
begin
  JsonStr := Trim(DecryptAvroEncoToString(AFilePath, APassword));
  Result := (JsonStr <> '') and (JsonStr[1] = '{');
end;

function EncryptJsonToAvroEncoFile(const AJsonText: string; const APassword: AnsiString; const AOutFilePath: string): Boolean;
var
  FS: TFileStream;
  Salt, IV, PlainBytes, CipherBuf, KeyBytes: TBytes;
  Flag: Byte;
  L:    Integer;
begin
  Result := False;
  if AJsonText = '' then
    Exit;

  // Empty password => Default Application Key protection (flag $00);
  // non-empty password => user password protection (flag $01).
  Flag := AVROENCO_FLAG_USER_PASSWORD;
  if APassword = '' then
    Flag := AVROENCO_FLAG_DEFAULT_KEY;

  // Entropy for salt/IV comes from the CSPRNG (RtlGenRandom) in
  // uAvroCryptoUtils - never the RTL PRNG, which is not a CSPRNG.
  FillRandomBytes(Salt, SALT_SIZE);
  FillRandomBytes(IV, IV_SIZE);

  KeyBytes := nil;
  try
    if APassword = '' then
      KeyBytes := DeriveKeySHA256FromString(GetAvroEncoDefaultSecret, Salt)
    else
      KeyBytes := DeriveKeySHA256FromString(string(APassword), Salt);

    PlainBytes := TEncoding.UTF8.GetBytes(AJsonText);
    try
      AES256CBCEncryptBytes(PlainBytes, KeyBytes, IV, CipherBuf);

      FS := TFileStream.Create(AOutFilePath, fmCreate);
      try
        FS.WriteBuffer(AVROENCO_MAGIC_BASE[0], 8);
        L := AVROENCO_MAGIC_TAIL_V2;
        FS.WriteBuffer(L, 1);
        FS.WriteBuffer(Flag, 1);
        FS.WriteBuffer(Salt[0], SALT_SIZE);
        FS.WriteBuffer(IV[0], IV_SIZE);
        FS.WriteBuffer(CipherBuf[0], Length(CipherBuf));
        Result := True;
      finally
        FS.Free;
      end;

      FillChar(CipherBuf[0], Length(CipherBuf), 0);
      SetLength(CipherBuf, 0);
    finally
      FillChar(PlainBytes[0], Length(PlainBytes), 0);
      SetLength(PlainBytes, 0);
    end;
  finally
    if Length(KeyBytes) > 0 then
    begin
      FillChar(KeyBytes[0], Length(KeyBytes), 0);
      SetLength(KeyBytes, 0);
    end;
  end;
end;

end.
