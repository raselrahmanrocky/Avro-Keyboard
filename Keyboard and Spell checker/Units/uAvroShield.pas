{
  =============================================================================
  uAvroShield - Pure Pascal .AvroShield container reader + bytecode parser
  + deobfuscator, byte-compatible with the AvroShield Python toolchain
  (avroenco\avroshield.py, bytecode.py, bytecode_parser.py, obfuscator.py).

  Data flow (unprotect), all in memory - nothing plain is ever written to
  disk:

    .AvroShield -> verify HMAC-SHA512 -> AES-256-GCM decrypt -> zlib
                -> bytecode -> BytecodeParser -> deobfuscate
                -> in-memory JSON text (returned to the caller)

  Key derivation (matches avroenco/src/crypto.py):

    master = Argon2id(password, salt, t=3, m=65536 KiB, p=4, len=32)
    final  = SHA-512(master || machine_factor(16) || hardware_factor(16))
    enc_key = final[0..31], mac_key = final[32..63]

  Machine factor: SHA-256(Windows MachineGuid UTF-8)[:16] (fallback: primary
  MAC as decimal string), identical to the Python side (D11). The hardware
  factor falls back to the machine-derived value when no token file exists,
  exactly like the Python engine.
  =============================================================================
}

unit uAvroShield;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  { Result codes for AvroShieldLoadFromFile / AvroShieldLoadFromBytes. }
  TAvroShieldResult = (
    asrOk = 0,
    asrFileNotFound,
    asrFileTooShort,
    asrBadMagic,
    asrBadVersion,
    asrMachineMismatch,
    asrMachineBindRequired,
    asrHmacFailed,
    asrDecryptFailed,
    asrDecompressFailed,
    asrBadBytecode,
    asrCorruptPayload,
    asrUnknown
  );

  { In-memory JSON value model shared by the bytecode parser and the
    deobfuscator. Objects keep Keys parallel to Items so key order is
    preserved exactly like Python's dicts. }
  TAvroNodeKind = (nkNull, nkBool, nkInt, nkFloat, nkString, nkArray, nkObject);

  TAvroNode = class
  public
    Kind: TAvroNodeKind;
    BoolVal: Boolean;
    IntVal: Int64;
    FloatVal: Double;
    StrVal: string;
    Items: TObjectList<TAvroNode>;   // array elements / object values
    Keys: TStringList;               // object keys, parallel to Items
    constructor Create;
    destructor Destroy; override;
  end;

  EAvroShieldError = class(Exception);

{ Loads, verifies, decrypts, parses and deobfuscates an .AvroShield file.
  On asrOk, AJSONText holds the deobfuscated mapping JSON (in memory only). }
function AvroShieldLoadFromFile(const AFileName, APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ Same, from raw file bytes (used by tests and in-memory callers). }
function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ 16-byte machine identifier: SHA-256(MachineGuid UTF-8)[:16], MAC fallback. }
function AvroShieldMachineId: TBytes;

{ Parses AvroShield bytecode into a node tree (exposed for the self-test). }
function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;

{ Inverts the obfuscation pipeline on a node tree (exposed for the self-test).
  AValue must be freed by the caller. }
function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;

{ Serializes a node tree to compact JSON text (loader/tests). }
function AvroShieldNodeToJSON(const ANode: TAvroNode): string;

implementation

uses
  System.Hash,
  System.ZLib,
  System.NetEncoding,
  System.JSON,
  System.Math,
  Winapi.Windows,
  Winapi.IpHlpApi,
  Winapi.IpTypes,
  uAvroArgon2,
  uAvroCryptoUtils;

const
  // ---- .AvroShield container ----
  AS_VERSION = 1;
  AS_HEADER_SIZE = 58;
  AS_TRAILER_SIZE = 80;   // auth_tag(16) + hmac(64)
  AS_HMAC_SIZE = 64;

  FLAG_PASSWORD = $01;
  FLAG_HARDWARE = $02;
  FLAG_MACHINE_BIND = $04;
  FLAG_BYTECODE_V1 = $08;

  // ---- Argon2id KDF (matches avroenco/src/constants.py) ----
  ARGON_TIME_COST = 3;
  ARGON_MEMORY_COST = 65536;   // 64 MB
  ARGON_PARALLELISM = 4;
  ARGON_HASH_LEN = 32;

  // ---- bytecode ----
  BC_HEADER_SIZE = 23;
  BC_XOR_SEED = 'AvroShieldBytecodeXORv1';

  TYPE_NULL = $00;
  TYPE_STRING = $01;
  TYPE_NUMBER = $02;
  TYPE_BOOLEAN = $03;
  TYPE_ARRAY = $04;
  TYPE_OBJECT = $05;
  TYPE_REFERENCE = $06;
  TYPE_OBFUSCATED = $07;

  // ---- obfuscation ----
  META_KEY = '_obf_meta';

{ =============================================================================
  Byte helpers
  ============================================================================= }

{ Byte-string builders for the fixed obfuscation seeds (Delphi has no
  dynamic-array typed constants). }
function AsMagic: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROSHLD');
end;

function StrTag: TBytes;
begin
  SetLength(Result, 4);
  Result[0] := $73; // 's'
  Result[1] := $74; // 't'
  Result[2] := $72; // 'r'
  Result[3] := 0;
end;

function MetaSeed: TBytes;
const
  M: array [0 .. 17] of Byte = ($41, $76, $72, $6F, $53, $68, $69, $65,
    $6C, $64, $4D, $65, $74, $61, $56, $31, 0, 1);
begin
  SetLength(Result, Length(M));
  Move(M[0], Result[0], Length(M));
end;

function BE16(const AData: TBytes; AOff: Integer): Word;
begin
  Result := (Word(AData[AOff]) shl 8) or AData[AOff + 1];
end;

function BE32(const AData: TBytes; AOff: Integer): Cardinal;
begin
  Result := (Cardinal(AData[AOff]) shl 24) or (Cardinal(AData[AOff + 1]) shl 16) or
    (Cardinal(AData[AOff + 2]) shl 8) or AData[AOff + 3];
end;

function BcRead(const AData: TBytes; var AOff: Integer; ACount: Integer): TBytes;
begin
  if (AOff < 0) or (ACount < 0) or (AOff + ACount > Length(AData)) then
    raise EAvroShieldError.Create('Truncated bytecode');
  SetLength(Result, ACount);
  if ACount > 0 then
    Move(AData[AOff], Result[0], ACount);
  Inc(AOff, ACount);
end;

function BytesEqualAt(const AData: TBytes; AOff: Integer; const AMagic: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AOff < 0) or (AOff + Length(AMagic) > Length(AData)) then
    Exit;
  for I := 0 to Length(AMagic) - 1 do
    if AData[AOff + I] <> AMagic[I] then
      Exit;
  Result := True;
end;

function ConstTimeEqual(const A, B: TBytes): Boolean;
var
  I, D: Integer;
begin
  D := Length(A) xor Length(B);
  for I := 0 to Min(Length(A), Length(B)) - 1 do
    D := D or (Integer(A[I]) xor Integer(B[I]));
  Result := D = 0;
end;

{ =============================================================================
  Hashing / HMAC
  ============================================================================= }

function Sha256Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

function Sha512Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

{ HMAC-SHA512 (RFC 2104) via System.Hash.GetHMACAsBytes (TBytes overload). }
function HMACSHA512(const AKey, AMessage: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AMessage, AKey, THashSHA2.TSHA2Version.SHA512);
end;

{ =============================================================================
  Machine identity (D11): SHA-256(Windows MachineGuid UTF-8)[:16]
  ============================================================================= }

function ReadMachineGuid: string;
var
  RegKey: HKEY;
  Buf: array [0 .. 127] of WideChar;
  BufSize: DWORD;
begin
  Result := '';
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE,
    'SOFTWARE\Microsoft\Cryptography', 0, KEY_READ or KEY_WOW64_64KEY,
    RegKey) = ERROR_SUCCESS then
  try
    BufSize := SizeOf(Buf);
    if RegQueryValueExW(RegKey, 'MachineGuid', nil, nil, @Buf[0],
      @BufSize) = ERROR_SUCCESS then
      Result := Buf;
  finally
    RegCloseKey(RegKey);
  end;
end;

{ Fallback matching uuid.getnode(): primary MAC rendered as a decimal string
  (Python uses str(uuid.getnode())). Only used when MachineGuid is missing. }
function GetPrimaryMacString: string;
var
  BufSize: DWORD;
  Adapters, P: PIP_ADAPTER_INFO;
  Value: UInt64;
  I: Integer;
begin
  Result := '';
  BufSize := 0;
  Adapters := nil;
  if GetAdaptersInfo(nil, BufSize) = ERROR_BUFFER_OVERFLOW then
  begin
    GetMem(Adapters, BufSize);
    try
      if GetAdaptersInfo(Adapters, BufSize) = NO_ERROR then
      begin
        P := Adapters;
        while Assigned(P) do
        begin
          if P^.Type_ = 6 then   // MIB_IF_TYPE_ETHERNET
          begin
            Value := 0;
            for I := 0 to 5 do
              Value := (Value shl 8) or P^.Address[I];
            Result := IntToStr(Value);
            Break;
          end;
          P := P^.Next;
        end;
      end;
    finally
      FreeMem(Adapters);
    end;
  end;
end;

function AvroShieldMachineId: TBytes;
var
  Guid: string;
begin
  Guid := ReadMachineGuid;
  if Guid = '' then
    Guid := GetPrimaryMacString;
  Result := Sha256Of(TEncoding.UTF8.GetBytes(Guid));
  SetLength(Result, 16);
end;

{ =============================================================================
  Bytecode parser (inverse of avroenco/bytecode.py)
  ============================================================================= }

{ Deterministic XOR mask over string payloads: keystream = SHA-256(
  'AvroShieldBytecodeXORv1' + BE32(len)) repeated. }
function BcMaskString(const AData: TBytes): TBytes;
var
  LenB, Key: TBytes;
  I: Integer;
begin
  SetLength(LenB, 4);
  LenB[0] := Byte(Length(AData) shr 24);
  LenB[1] := Byte(Length(AData) shr 16);
  LenB[2] := Byte(Length(AData) shr 8);
  LenB[3] := Byte(Length(AData));
  Key := Sha256Of(TEncoding.UTF8.GetBytes(BC_XOR_SEED) + LenB);
  SetLength(Result, Length(AData));
  for I := 0 to Length(AData) - 1 do
    Result[I] := AData[I] xor Key[I mod 32];
end;

function BcReadInt64(const AData: TBytes; AOff: Integer): Int64;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Result := Int64(Bits);
end;

function BcReadDouble(const AData: TBytes; AOff: Integer): Double;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Move(Bits, Result, SizeOf(Result));
end;

function ParseNode(const AData: TBytes; var AOff: Integer): TAvroNode;
var
  Typ: Byte;
  Len, Cnt, I, KLen: Integer;
  Masked: TBytes;
begin
  if AOff >= Length(AData) then
    raise EAvroShieldError.Create('Truncated node');
  Typ := AData[AOff];
  Inc(AOff);

  Result := TAvroNode.Create;
  try
    case Typ of
      TYPE_NULL:
        Result.Kind := nkNull;

      TYPE_BOOLEAN:
        begin
          if AOff >= Length(AData) then
            raise EAvroShieldError.Create('Truncated boolean');
          Result.Kind := nkBool;
          Result.BoolVal := AData[AOff] = $01;
          Inc(AOff);
        end;

      TYPE_NUMBER:
        begin
          if AOff + 9 > Length(AData) then
            raise EAvroShieldError.Create('Truncated number');
          if AData[AOff] = 1 then
          begin
            Result.Kind := nkInt;
            Result.IntVal := BcReadInt64(AData, AOff + 1);
          end
          else
          begin
            Result.Kind := nkFloat;
            Result.FloatVal := BcReadDouble(AData, AOff + 1);
          end;
          Inc(AOff, 9);
        end;

      TYPE_STRING:
        begin
          if AOff + 4 > Length(AData) then
            raise EAvroShieldError.Create('Truncated string');
          Len := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          Masked := BcRead(AData, AOff, Len);
          Result.Kind := nkString;
          Result.StrVal := TEncoding.UTF8.GetString(BcMaskString(Masked));
        end;

      TYPE_ARRAY:
        begin
          if AOff + 4 > Length(AData) then
            raise EAvroShieldError.Create('Truncated array');
          Result.Kind := nkArray;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
            Result.Items.Add(ParseNode(AData, AOff));
        end;

      TYPE_OBJECT:
        begin
          if AOff + 4 > Length(AData) then
            raise EAvroShieldError.Create('Truncated object');
          Result.Kind := nkObject;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
          begin
            if AOff + 2 > Length(AData) then
              raise EAvroShieldError.Create('Truncated object key');
            KLen := Integer(BE16(AData, AOff));
            Inc(AOff, 2);
            Result.Keys.Add(TEncoding.UTF8.GetString(BcRead(AData, AOff, KLen)));
            Result.Items.Add(ParseNode(AData, AOff));
          end;
        end;

    else
      raise EAvroShieldError.CreateFmt('Unsupported bytecode node type: %d', [Typ]);
    end;
  except
    Result.Free;
    raise;
  end;
end;

function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
var
  Off, I, TypeCount, EntryCount, KLen, NodeLen, EntryStart, NZero: Integer;
  KeyBytes, NodeBytes, Entry, Calc, BC_MAGIC: TBytes;
  Root: TAvroNode;
  StoredCrc: Cardinal;
begin
  AValue := nil;
  Root := nil;
  Result := False;
  try
    if Length(ABytecode) < BC_HEADER_SIZE + 32 then
      Exit;

    BC_MAGIC := TEncoding.ASCII.GetBytes('AVROBC');
    if not BytesEqualAt(ABytecode, 0, BC_MAGIC) then
      Exit;
    if ABytecode[6] <> 1 then
      Exit;

    // SHA-256 trailer over everything before the last 32 bytes.
    Calc := Sha256Of(Copy(ABytecode, 0, Length(ABytecode) - 32));
    if not ConstTimeEqual(Calc, Copy(ABytecode, Length(ABytecode) - 32, 32)) then
      Exit;

    TypeCount := Integer(BE32(ABytecode, 7));
    EntryCount := Integer(BE32(ABytecode, 11));

    Off := BC_HEADER_SIZE;
    for I := 0 to TypeCount - 1 do
    begin
      Inc(Off, 1);
      if Off + 2 > Length(ABytecode) then
        Exit;
      Inc(Off, 2 + Integer(BE16(ABytecode, Off)));
    end;

    Root := TAvroNode.Create;
    Root.Kind := nkObject;
    for I := 0 to EntryCount - 1 do
    begin
      EntryStart := Off;
      if Off + 2 > Length(ABytecode) then
        raise EAvroShieldError.Create('Truncated entry key');
      KLen := Integer(BE16(ABytecode, Off));
      Inc(Off, 2);
      KeyBytes := BcRead(ABytecode, Off, KLen);
      if Off + 4 > Length(ABytecode) then
        raise EAvroShieldError.Create('Truncated entry node');
      NodeLen := Integer(BE32(ABytecode, Off));
      Inc(Off, 4);
      NodeBytes := BcRead(ABytecode, Off, NodeLen);
      if Off + 4 > Length(ABytecode) then
        raise EAvroShieldError.Create('Truncated entry crc');
      StoredCrc := BE32(ABytecode, Off);
      Inc(Off, 4);

      Entry := Copy(ABytecode, EntryStart, Off - 4 - EntryStart);
      if crc32(0, @Entry[0], Length(Entry)) <> StoredCrc then
        raise EAvroShieldError.Create('Entry checksum mismatch');

      NZero := 0;
      Root.Keys.Add(TEncoding.UTF8.GetString(KeyBytes));
      Root.Items.Add(ParseNode(NodeBytes, NZero));
    end;

    if Off <> Length(ABytecode) - 32 then
      raise EAvroShieldError.Create('Trailing garbage after entries');

    AValue := Root;
    Root := nil;
    Result := True;
    except
    on E: Exception do
      ; // Result stays False
  end;
  Root.Free;
end;

{ =============================================================================
  Deobfuscator (inverse of avroenco/obfuscator.py)
  ============================================================================= }

{ SHA-256 counter-mode keystream: blocks of SHA-256(key + BE32(counter)). }
function DeobfStream(const AKey: TBytes; ALength: Integer): TBytes;
var
  OutB, CounterB, Block: TBytes;
  Counter, I, Take: Integer;
begin
  SetLength(OutB, ALength);
  Counter := 0;
  I := 0;
  while I < ALength do
  begin
    SetLength(CounterB, 4);
    CounterB[0] := Byte(Counter shr 24);
    CounterB[1] := Byte(Counter shr 16);
    CounterB[2] := Byte(Counter shr 8);
    CounterB[3] := Byte(Counter);
    Block := Sha256Of(AKey + CounterB);
    Take := Min(32, ALength - I);
    Move(Block[0], OutB[I], Take);
    Inc(I, 32);
    Inc(Counter);
  end;
  Result := OutB;
end;

{ XOR codec over (seed, ctx): keystream key = SHA-256('str\0' + seed + '\0' +
  UTF-8(ctx)); XOR is its own inverse. }
function DeobfCodec(const ASeed, AData: TBytes; const ACtx: string): TBytes;
var
  Key, Stream: TBytes;
  I: Integer;
begin
  Key := Sha256Of(StrTag + ASeed + TEncoding.UTF8.GetBytes(#0 + ACtx));
  Stream := DeobfStream(Key, Length(AData));
  SetLength(Result, Length(AData));
  for I := 0 to Length(AData) - 1 do
    Result[I] := AData[I] xor Stream[I];
end;

function ChildCtx(const ACtx, AName: string): string;
begin
  if ACtx = '' then
    Result := AName
  else
    Result := ACtx + '/' + AName;
end;

function IndexCtx(const ACtx: string; AIndex: Integer): string;
begin
  Result := ACtx + '#' + IntToStr(AIndex);
end;

function DeobfValue(ANode: TAvroNode; const ACtx: string; const ASeed: TBytes;
  const ARev: TDictionary<string, string>;
  const ASkip: TDictionary<string, Boolean>): TAvroNode;
var
  I: Integer;
  OrigKey, HashedKey: string;
  Child: TAvroNode;
begin
  Result := TAvroNode.Create;
  case ANode.Kind of
    nkObject:
      begin
        Result.Kind := nkObject;
        for I := 0 to ANode.Items.Count - 1 do
        begin
          HashedKey := ANode.Keys[I];
          if ASkip.ContainsKey(HashedKey) then
            Continue;
          if not ARev.TryGetValue(HashedKey, OrigKey) then
            OrigKey := HashedKey;
          Child := DeobfValue(ANode.Items[I], ChildCtx(ACtx, HashedKey), ASeed,
            ARev, ASkip);
          Result.Keys.Add(OrigKey);
          Result.Items.Add(Child);
        end;
      end;
    nkArray:
      begin
        Result.Kind := nkArray;
        for I := 0 to ANode.Items.Count - 1 do
          Result.Items.Add(DeobfValue(ANode.Items[I], IndexCtx(ACtx, I), ASeed,
            ARev, ASkip));
      end;
    nkString:
      begin
        Result.Kind := nkString;
        Result.StrVal := TEncoding.UTF8.GetString(DeobfCodec(ASeed,
          TNetEncoding.Base64.DecodeStringToBytes(ANode.StrVal), ACtx));
      end;
  else
    Result.Kind := ANode.Kind;
    Result.BoolVal := ANode.BoolVal;
    Result.IntVal := ANode.IntVal;
    Result.FloatVal := ANode.FloatVal;
  end;
end;

function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
var
  Seed: TBytes;
  Rev: TDictionary<string, string>;
  Skip: TDictionary<string, Boolean>;
  MetaIdx, I: Integer;
  MetaVal: TAvroNode;
  Json: TJSONValue;
  JObj, KMap: TJSONObject;
  JArr: TJSONArray;
  Pair: TJSONPair;
begin
  AValue := nil;
  Result := False;
  try
    Rev := TDictionary<string, string>.Create;
    Skip := TDictionary<string, Boolean>.Create;
    try
      Skip.Add(META_KEY, True);

      MetaIdx := AObfuscated.Keys.IndexOf(META_KEY);
      if MetaIdx < 0 then
        Exit; // no metadata -> cannot deobfuscate
      MetaVal := AObfuscated.Items[MetaIdx];
      if MetaVal.Kind <> nkString then
        Exit;

      Json := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(DeobfCodec(
        MetaSeed, TNetEncoding.Base64.DecodeStringToBytes(MetaVal.StrVal),
        META_KEY)));
      if not (Json is TJSONObject) then
        Exit;
      try
        JObj := TJSONObject(Json);
        Seed := TNetEncoding.Base64.DecodeStringToBytes(JObj.GetValue('seed').Value);
        KMap := JObj.GetValue('key_map') as TJSONObject;
        if Assigned(KMap) then
          for Pair in KMap do
            Rev.Add(Pair.JsonValue.Value, Pair.JsonString.Value); // hashed -> original
        JArr := JObj.GetValue('dummies') as TJSONArray;
        if Assigned(JArr) then
          for I := 0 to JArr.Count - 1 do
            Skip.Add(JArr.Items[I].Value, True);
      finally
        Json.Free;
      end;

      AValue := DeobfValue(AObfuscated, '', Seed, Rev, Skip);
      Result := True;
    finally
      Rev.Free;
      Skip.Free;
    end;
  except
    on E: Exception do
      Result := False;
  end;
end;

{ =============================================================================
  JSON serialization (loader / tests)
  ============================================================================= }

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
end;

function AvroShieldNodeToJSON(const ANode: TAvroNode): string;
var
  I: Integer;
begin
  case ANode.Kind of
    nkNull: Result := 'null';
    nkBool:
      if ANode.BoolVal then Result := 'true' else Result := 'false';
    nkInt: Result := IntToStr(ANode.IntVal);
    nkFloat: Result := FloatToStr(ANode.FloatVal, TFormatSettings.Invariant);
    nkString: Result := '"' + JsonEscape(ANode.StrVal) + '"';
    nkArray:
      begin
        Result := '[';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + AvroShieldNodeToJSON(ANode.Items[I]);
        end;
        Result := Result + ']';
      end;
    nkObject:
      begin
        Result := '{';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + '"' + JsonEscape(ANode.Keys[I]) + '":' +
            AvroShieldNodeToJSON(ANode.Items[I]);
        end;
        Result := Result + '}';
      end;
  end;
end;

{ =============================================================================
  zlib decompression (Python zlib.compress output)
  ============================================================================= }

function ZlibDecompressBytes(const AData: TBytes): TBytes;
var
  InS, OutS: TMemoryStream;
  Z: TZDecompressionStream;
  Buf: array [0 .. 8191] of Byte;
  N: Integer;
begin
  Result := nil;
  InS := TMemoryStream.Create;
  OutS := TMemoryStream.Create;
  Z := nil;
  try
    try
      if Length(AData) > 0 then
        InS.Write(AData[0], Length(AData));
      InS.Position := 0;
      Z := TZDecompressionStream.Create(InS, 15);
      repeat
        N := Z.Read(Buf, SizeOf(Buf));
        if N > 0 then
          OutS.Write(Buf, N);
      until N < SizeOf(Buf);
      SetLength(Result, OutS.Size);
      if OutS.Size > 0 then
      begin
        OutS.Position := 0;
        OutS.Read(Result[0], OutS.Size);
      end;
    except
      on E: Exception do
        SetLength(Result, 0);
    end;
  finally
    Z.Free;
    OutS.Free;
    InS.Free;
  end;
end;

{ =============================================================================
  Container reader
  ============================================================================= }

function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Flags: Byte;
  Salt, IV, StoredMachine, Master: TBytes;
  MachineF, HardwareF, FinalKey, EncKey, MacKey: TBytes;
  Cipher, Tag, ExpectedMac, HmacData, Compressed, Bytecode: TBytes;
  Root, Deobf: TAvroNode;
begin
  AJSONText := '';
  Result := asrUnknown;

  if Length(AData) < AS_HEADER_SIZE + AS_TRAILER_SIZE + 1 then
    Exit(asrFileTooShort);
  if not BytesEqualAt(AData, 0, AsMagic) then
    Exit(asrBadMagic);
  if AData[8] <> AS_VERSION then
    Exit(asrBadVersion);

  Flags := AData[9];
  Salt := Copy(AData, 10, 16);
  IV := Copy(AData, 26, 16);
  StoredMachine := Copy(AData, 42, 16);

  if (Flags and FLAG_MACHINE_BIND) <> 0 then
  begin
    if not AUseMachineBind then
      Exit(asrMachineBindRequired);
    if not ConstTimeEqual(StoredMachine, AvroShieldMachineId) then
      Exit(asrMachineMismatch);
  end;

  Master := Argon2idHash(TEncoding.UTF8.GetBytes(APassword), Salt,
    ARGON_TIME_COST, ARGON_MEMORY_COST, ARGON_PARALLELISM, ARGON_HASH_LEN);
  try
    SetLength(MachineF, 16);
    FillChar(MachineF[0], 16, 0);
    if (Flags and FLAG_MACHINE_BIND) <> 0 then
      MachineF := AvroShieldMachineId;
    SetLength(HardwareF, 16);
    FillChar(HardwareF[0], 16, 0);
    if (Flags and FLAG_HARDWARE) <> 0 then
      HardwareF := AvroShieldMachineId; // Python falls back to machine id

    FinalKey := Sha512Of(Master + MachineF + HardwareF);
    EncKey := Copy(FinalKey, 0, 32);
    MacKey := Copy(FinalKey, 32, 32);

    Cipher := Copy(AData, AS_HEADER_SIZE,
      Length(AData) - AS_HEADER_SIZE - AS_TRAILER_SIZE);
    Tag := Copy(AData, Length(AData) - AS_TRAILER_SIZE, 16);
    ExpectedMac := Copy(AData, Length(AData) - AS_HMAC_SIZE, AS_HMAC_SIZE);

    HmacData := Copy(AData, 0, AS_HEADER_SIZE) + Cipher + Tag;
    if not ConstTimeEqual(HMACSHA512(MacKey, HmacData), ExpectedMac) then
      Exit(asrHmacFailed);

    if not AES256GCMDecrypt(Cipher + Tag, EncKey, IV, nil, Compressed) then
      Exit(asrDecryptFailed);

    Bytecode := ZlibDecompressBytes(Compressed);
    if Length(Bytecode) = 0 then
      Exit(asrDecompressFailed);

    if not BytesEqualAt(Bytecode, 0, TEncoding.ASCII.GetBytes('AVROBC')) then
      Exit(asrBadBytecode);

    if not AvroShieldParseBytecode(Bytecode, Root) then
      Exit(asrBadBytecode);
    try
      if not AvroShieldDeobfuscate(Root, Deobf) then
        Exit(asrCorruptPayload);
      try
        AJSONText := AvroShieldNodeToJSON(Deobf);
        Result := asrOk;
      finally
        Deobf.Free;
      end;
    finally
      Root.Free;
    end;
  finally
    if Length(Master) > 0 then
      FillChar(Master[0], Length(Master), 0);
    SetLength(Master, 0);
    if Length(FinalKey) > 0 then
      FillChar(FinalKey[0], Length(FinalKey), 0);
    SetLength(FinalKey, 0);
    if Length(Compressed) > 0 then
      FillChar(Compressed[0], Length(Compressed), 0);
    SetLength(Compressed, 0);
  end;
end;

function AvroShieldLoadFromFile(const AFileName, APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
var
  FS: TFileStream;
  Data: TBytes;
begin
  AJSONText := '';
  if not FileExists(AFileName) then
    Exit(asrFileNotFound);
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Data, FS.Size);
    if FS.Size > 0 then
      FS.Read(Data[0], FS.Size);
  finally
    FS.Free;
  end;
  Result := AvroShieldLoadFromBytes(Data, APassword, AJSONText, AUseMachineBind);
end;

constructor TAvroNode.Create;
begin
  inherited Create;
  Items := TObjectList<TAvroNode>.Create(True);
  Keys := TStringList.Create;
  Keys.CaseSensitive := True;
end;

destructor TAvroNode.Destroy;
begin
  Items.Free;
  Keys.Free;
  inherited Destroy;
end;

end.
