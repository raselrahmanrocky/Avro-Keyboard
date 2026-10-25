unit uAvroShieldCodec;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
{$INLINE OFF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.NetEncoding,
  System.ZLib,
  uAvroShieldTypes;

function ParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
function Deobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
function DeobfuscateEx(const AObfuscated: TAvroNode; const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AValue: TAvroNode): Boolean;
function NodeToJSON(const ANode: TAvroNode): string;
function IsCommentField(const AName: string): Boolean;
function CommentCtx(const ACtx, AName: string): string;
function MetaMask(const AMaster: TBytes): TBytes;
function CommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;
function DecodeBytecodeToJson(const ABytecode, AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AJsonUtf8: TBytes): TAvroShieldResult;
function EncodeJsonToBytecode(const AJSONText: string; const AMaster, ACommentsIKM: TBytes; ATargetVersion: Byte; out ABytecode: TBytes): TAvroShieldResult;

implementation

uses
  System.Math,
  uKeyBuilder,
  uBufferTransform,
  uAvroSecureMem,
  uAvroCryptoUtils;

const
  BC_HEADER_SIZE = 23;
  BC_XOR_SEED    = 'AvroShieldBytecodeXORv1';

  TYPE_NULL       = $00;
  TYPE_STRING     = $01;
  TYPE_NUMBER     = $02;
  TYPE_BOOLEAN    = $03;
  TYPE_ARRAY      = $04;
  TYPE_OBJECT     = $05;
  TYPE_REFERENCE  = $06;
  TYPE_OBFUSCATED = $07;

  META_KEY = '_obf_meta';

  OBF_INFO_META     = 'AvroShield-v3/obf-meta';
  OBF_INFO_COMMENTS = 'AvroShield-v3/comments';

  OBF_COMMENT_FIELDS: array [0 .. 2] of string = ('Comment', 'comment', '_comment');


function AsMagic: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROSHLD');
end;

function AsMagicBC: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROBC');
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
  M: array [0 .. 17] of Byte = ($41, $76, $72, $6F, $53, $68, $69, $65, $6C, $64, $4D, $65, $74, $61, $56, $31, 0, 1);
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
  Result := (Cardinal(AData[AOff]) shl 24) or (Cardinal(AData[AOff + 1]) shl 16) or (Cardinal(AData[AOff + 2]) shl 8) or AData[AOff + 3];
end;

function BcRead(const AData: TBytes; var AOff: Integer; ACount: Integer): TBytes;
begin
  if (AOff < 0) or (ACount < 0) or (AOff + ACount > Length(AData)) then
    raise ShieldOpaqueError('Truncated bytecode');
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


function BcMaskString(const AData: TBytes): TBytes;
var
  LenB, Key: TBytes;
  I:         Integer;
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
  I:    Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Result := Int64(Bits);
end;

function BcReadDouble(const AData: TBytes; AOff: Integer): Double;
var
  Bits: UInt64;
  I:    Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Move(Bits, Result, SizeOf(Result));
end;

function ParseNode(const AData: TBytes; var AOff: Integer): TAvroNode;
var
  Typ:               Byte;
  Len, Cnt, I, KLen: Integer;
  Masked:            TBytes;
begin
  if AOff >= Length(AData) then
    raise ShieldOpaqueError('Truncated node');
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
            raise ShieldOpaqueError('Truncated boolean');
          Result.Kind := nkBool;
          Result.BoolVal := AData[AOff] = $01;
          Inc(AOff);
        end;

      TYPE_NUMBER:
        begin
          if AOff + 9 > Length(AData) then
            raise ShieldOpaqueError('Truncated number');
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
            raise ShieldOpaqueError('Truncated string');
          Len := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          Masked := BcRead(AData, AOff, Len);
          Result.Kind := nkString;
          Result.StrVal := TEncoding.UTF8.GetString(BcMaskString(Masked));
        end;

      TYPE_ARRAY:
        begin
          if AOff + 4 > Length(AData) then
            raise ShieldOpaqueError('Truncated array');
          Result.Kind := nkArray;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
            Result.Items.Add(ParseNode(AData, AOff));
        end;

      TYPE_OBJECT:
        begin
          if AOff + 4 > Length(AData) then
            raise ShieldOpaqueError('Truncated object');
          Result.Kind := nkObject;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
          begin
            if AOff + 2 > Length(AData) then
              raise ShieldOpaqueError('Truncated object key');
            KLen := Integer(BE16(AData, AOff));
            Inc(AOff, 2);
            Result.Keys.Add(TEncoding.UTF8.GetString(BcRead(AData, AOff, KLen)));
            Result.Items.Add(ParseNode(AData, AOff));
          end;
        end;

      else
        raise ShieldOpaqueError(Format('Unsupported bytecode node type: %d', [Typ]));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function ParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
var
  Off, I, TypeCount, EntryCount, KLen, NodeLen, EntryStart, NZero: Integer;
  KeyBytes, NodeBytes, Entry, Calc, BC_MAGIC:                      TBytes;
  Root:                                                            TAvroNode;
  StoredCrc:                                                       Cardinal;
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
        raise ShieldOpaqueError('Truncated entry key');
      KLen := Integer(BE16(ABytecode, Off));
      Inc(Off, 2);
      KeyBytes := BcRead(ABytecode, Off, KLen);
      if Off + 4 > Length(ABytecode) then
        raise ShieldOpaqueError('Truncated entry node');
      NodeLen := Integer(BE32(ABytecode, Off));
      Inc(Off, 4);
      NodeBytes := BcRead(ABytecode, Off, NodeLen);
      if Off + 4 > Length(ABytecode) then
        raise ShieldOpaqueError('Truncated entry crc');
      StoredCrc := BE32(ABytecode, Off);
      Inc(Off, 4);

      Entry := Copy(ABytecode, EntryStart, Off - 4 - EntryStart);
      if crc32(0, @Entry[0], Length(Entry)) <> StoredCrc then
        raise ShieldOpaqueError('Entry checksum mismatch');

      NZero := 0;
      Root.Keys.Add(TEncoding.UTF8.GetString(KeyBytes));
      Root.Items.Add(ParseNode(NodeBytes, NZero));
    end;

    if Off <> Length(ABytecode) - 32 then
      raise ShieldOpaqueError('Trailing garbage after entries');

    AValue := Root;
    Root := nil;
    Result := True;
  except
    on E: Exception do; // Result stays False
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
  Counter, I, Take:      Integer;
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
  I:           Integer;
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

{ =============================================================================
  Obfuscation key domains (format v3)
  ============================================================================= }

{ Generic HKDF-SHA256 (RFC 5869) over arbitrary info. The KDF helpers above are
  bound to the container key schedule; this is the one the obfuscation domains
  use, with an explicit info label so two derivations can never collide. }
{ True when AName is one of the developer-documentation fields. Matched as an
  exact name: 'Comment' and 'comment' are distinct keys in the mapping schema
  and both are documentation, but a value field that merely contains the word
  must not be swept into the comment domain. }
function IsCommentField(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := low(OBF_COMMENT_FIELDS) to high(OBF_COMMENT_FIELDS) do
    if AName = OBF_COMMENT_FIELDS[I] then
      Exit(True);
end;

{ Context of a comment field: the ordinary child path under a distinct prefix.
  The prefix matters even though the comment domain already uses a different
  key - it keeps the two keystream namespaces disjoint by construction, so no
  pair of (key, ctx) inputs can ever coincide across domains. }
function CommentCtx(const ACtx, AName: string): string;
begin
  Result := 'cmt/' + ChildCtx(ACtx, AName);
end;

{ Metadata mask for a container the caller has already opened:

  KeyMeta = HKDF-SHA256(IKM = master, info = OBF_INFO_META)

  Master is already a per-container salted secret, so the mask needs no second
  salt. Before this existed the mask was a constant compiled into the unit, so
  anyone could unmask the metadata - and therefore the value seed and the whole
  obfuscation - without any key at all. }
function MetaMask(const AMaster: TBytes): TBytes;
var
  InfoMeta: TBytes;
begin
  Result := nil;
  if Length(AMaster) = 0 then
    Exit;
  InfoMeta := TEncoding.ASCII.GetBytes(OBF_INFO_META);
  try
    Result := uKeyBuilder.HkdfSha256(nil, AMaster, InfoMeta, 32);
  finally
    AvroWipeAndRelease(InfoMeta);
  end;
end;

{ Comment domain key:

  KeyComments = HKDF-SHA256(IKM = comment IKM, salt = value seed,
  info = OBF_INFO_COMMENTS)

  The developer IKM is what the runtime never has, and the value seed is only
  reachable through the keyed metadata blob, so comment text needs both the
  container key and the developer key. Salting with the per-build seed also
  keeps a comment token from being replayed into another container that used
  the same comment key. }
function CommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;
var
  InfoCmt: TBytes;
begin
  Result := nil;
  if (Length(ACommentsIKM) = 0) or (Length(ASeed) = 0) then
    Exit;
  InfoCmt := TEncoding.ASCII.GetBytes(OBF_INFO_COMMENTS);
  try
    Result := uKeyBuilder.HkdfSha256(ASeed, ACommentsIKM, InfoCmt, 32);
  finally
    AvroWipeAndRelease(InfoCmt);
  end;
end;

{ Recursive deobfuscator.

  AEffSeed is the obfuscation key in force for this subtree: the value seed by
  default, the comment key inside a comment field. ACommentSeed is the comment
  domain key; empty means the domain falls back to the value seed, which is
  what a container built without a comment key used (mirror of the writer).

  ACommentDomain distinguishes the two container formats. Format v3 gives
  comment fields their own context path and key; format v2 had no comment
  domain at all, so its comment fields are ordinary strings and must be decoded
  with the plain child context and the value seed - decoding them at the v3
  comment context produces garbage and, because that garbage is invalid UTF-8,
  used to fail the whole load of every existing v2 container.

  AIncludeComments=False is the runtime behaviour and the reason comments cost
  nothing to load: a comment field is skipped here, before the Base64 decode,
  before the keystream and before the UTF-16 allocation, instead of being
  decoded and then thrown away by the mapping parser. }
function DeobfValue(ANode: TAvroNode; const ACtx: string; const AEffSeed, ACommentSeed: TBytes; AIncludeComments, ACommentDomain: Boolean;
  const ARev: TDictionary<string, string>; const ASkip: TDictionary<string, Boolean>): TAvroNode;
var
  I:                     Integer;
  OrigKey, HashedKey:    string;
  Child:                 TAvroNode;
  ChildSeed, EffCmtSeed: TBytes;
  ChildCtxPath:          string;
  IsComment:             Boolean;
begin
  EffCmtSeed := ACommentSeed;
  if Length(EffCmtSeed) = 0 then
    EffCmtSeed := AEffSeed;

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
          IsComment := IsCommentField(OrigKey);
          if IsComment and (not AIncludeComments) then
            Continue;
          if IsComment and ACommentDomain then
          begin
            ChildSeed := EffCmtSeed;
            ChildCtxPath := CommentCtx(ACtx, HashedKey);
          end
          else
          begin
            // Value fields, and every comment field in a v2 container, which
            // has no separate comment domain.
            ChildSeed := AEffSeed;
            ChildCtxPath := ChildCtx(ACtx, HashedKey);
          end;
          Child := DeobfValue(ANode.Items[I], ChildCtxPath, ChildSeed, EffCmtSeed, AIncludeComments, ACommentDomain, ARev, ASkip);
          Result.Keys.Add(OrigKey);
          Result.Items.Add(Child);
        end;
      end;
    nkArray:
      begin
        Result.Kind := nkArray;
        for I := 0 to ANode.Items.Count - 1 do
          Result.Items.Add(DeobfValue(ANode.Items[I], IndexCtx(ACtx, I), AEffSeed, EffCmtSeed, AIncludeComments, ACommentDomain, ARev, ASkip));
      end;
    nkString:
      begin
        Result.Kind := nkString;
        Result.StrVal := TEncoding.UTF8.GetString(DeobfCodec(AEffSeed, TNetEncoding.Base64.DecodeStringToBytes(ANode.StrVal), ACtx));
      end;
    else
      Result.Kind := ANode.Kind;
      Result.BoolVal := ANode.BoolVal;
      Result.IntVal := ANode.IntVal;
      Result.FloatVal := ANode.FloatVal;
  end;
end;

{ The shared deobfuscation core: unmasks the metadata blob with AKeyMeta, then
  walks the tree with AKeyComments as the comment-domain key.

  AKeyMeta=nil selects the format-v2 constant mask (MetaSeed), which is what a
  v2 container carries; v3 passes its derived key. An empty ACommentsIKM means
  the comment domain is not separable from the value domain (v2), so comments
  are decoded with the value seed exactly as before. }
function DeobfuscateCore(const AObfuscated: TAvroNode; const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AValue: TAvroNode): Boolean;
var
  Seed, CommentKeyBytes: TBytes;
  MetaMaskBytes:         TBytes;
  Rev:              TDictionary<string, string>;
  Skip:             TDictionary<string, Boolean>;
  MetaIdx, I:       Integer;
  MetaVal:          TAvroNode;
  JSON:             TJSONValue;
  JObj, KMap:       TJSONObject;
  JArr:             TJSONArray;
  Pair:             TJSONPair;
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

      if Length(AKeyMeta) > 0 then
        MetaMaskBytes := AKeyMeta
      else
        MetaMaskBytes := MetaSeed;

      JSON := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(DeobfCodec(MetaMaskBytes, TNetEncoding.Base64.DecodeStringToBytes(MetaVal.StrVal), META_KEY)));
      if not(JSON is TJSONObject) then
        Exit;
      try
        JObj := TJSONObject(JSON);
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
        JSON.Free;
      end;

      // The comment key is derived only now, after the metadata blob has been
      // unmasked: the comment domain is layered on top of the container key
      // rather than sitting beside it.
      CommentKeyBytes := CommentKey(ACommentsIKM, Seed);
      // A keyed metadata mask is exactly the marker of format v3, and format
      // v3 is the only format with a separate comment domain. The legacy entry
      // point passes no mask, which keeps its v2 semantics.
      AValue := DeobfValue(AObfuscated, '', Seed, CommentKeyBytes, AIncludeComments, Length(AKeyMeta) > 0, Rev, Skip);
      Result := True;
    finally
      AvroWipeAndRelease(CommentKeyBytes);
      AvroWipeAndRelease(Seed);
      AvroWipeAndRelease(MetaMaskBytes);
      Rev.Free;
      Skip.Free;
    end;
  except
    on E: Exception do
      Result := False;
  end;
end;

function Deobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
begin
  // Format v2: constant metadata mask, comments in the value domain, and the
  // caller decides what to do with them (this entry point always keeps them).
  Result := DeobfuscateCore(AObfuscated, nil, nil, True, AValue);
end;

function DeobfuscateEx(const AObfuscated: TAvroNode; const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AValue: TAvroNode): Boolean;
begin
  Result := DeobfuscateCore(AObfuscated, AKeyMeta, ACommentsIKM, AIncludeComments, AValue);
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
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
      else
        if Ord(C) < 32 then
          Result := Result + Format('\u%.4x', [Ord(C)])
        else
          Result := Result + C;
    end;
  end;
end;

function NodeToJSON(const ANode: TAvroNode): string;
var
  I: Integer;
begin
  case ANode.Kind of
    nkNull:
      Result := 'null';
    nkBool:
      if ANode.BoolVal then
        Result := 'true'
      else
        Result := 'false';
    nkInt:
      Result := IntToStr(ANode.IntVal);
    nkFloat:
      Result := FloatToStr(ANode.FloatVal, TFormatSettings.Invariant);
    nkString:
      Result := '"' + JsonEscape(ANode.StrVal) + '"';
    nkArray:
      begin
        Result := '[';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then
            Result := Result + ',';
          Result := Result + NodeToJSON(ANode.Items[I]);
        end;
        Result := Result + ']';
      end;
    nkObject:
      begin
        Result := '{';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then
            Result := Result + ',';
          Result := Result + '"' + JsonEscape(ANode.Keys[I]) + '":' + NodeToJSON(ANode.Items[I]);
        end;
        Result := Result + '}';
      end;
  end;
end;

{ =============================================================================
  zlib decompression (Python zlib.compress output)
  ============================================================================= }


function JsonValueToNode(const AJson: TJSONValue): TAvroNode;
var
  I:   Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Num: TJSONNumber;
begin
  Result := TAvroNode.Create;
  try
    if AJson is TJSONNull then
      Result.Kind := nkNull
    else if AJson is TJSONBool then
    begin
      Result.Kind := nkBool;
      Result.BoolVal := (AJson as TJSONBool).AsBoolean;
    end
    else if AJson is TJSONNumber then
    begin
      Num := AJson as TJSONNumber;
      // Integers stay integers (bytecode TYPE_NUMBER flag 1); anything else
      // becomes a double (flag 0). Mapping documents use small integers only.
      if TryStrToInt64(Num.Value, Result.IntVal) then
        Result.Kind := nkInt
      else
      begin
        Result.Kind := nkFloat;
        Result.FloatVal := StrToFloat(Num.Value, TFormatSettings.Invariant);
      end;
    end
    else if AJson is TJSONString then
    begin
      Result.Kind := nkString;
      Result.StrVal := (AJson as TJSONString).Value;
    end
    else if AJson is TJSONArray then
    begin
      Result.Kind := nkArray;
      Arr := AJson as TJSONArray;
      for I := 0 to Arr.Count - 1 do
        Result.Items.Add(JsonValueToNode(Arr.Items[I]));
    end
    else if AJson is TJSONObject then
    begin
      Result.Kind := nkObject;
      Obj := AJson as TJSONObject;
      for I := 0 to Obj.Count - 1 do
      begin
        Result.Keys.Add(Obj.Get(I).JsonString.Value);
        Result.Items.Add(JsonValueToNode(Obj.Get(I).JsonValue));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ ---- Obfuscation (mirror of DeobfValue with the same ctx semantics) ------- }

function HexOfSha256(const AData: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  D: TBytes;
  I: Integer;
begin
  D := Sha256Of(AData);
  Result := '';
  for I := 0 to Length(D) - 1 do
    Result := Result + H[D[I] shr 4] + H[D[I] and 15];
end;

{ Recursively transforms a plain node tree into the obfuscated tree:
  object keys -> SHA-256 hex (original kept in ARev for the key_map), string
  values -> Base64(DeobfCodec(seed, UTF-8(value), ctx)) with the exact same
  ChildCtx/IndexCtx path semantics the deobfuscator walks, so the round trip
  is exact. Keys present in ASkip are dropped (META_KEY + dummies).

  Developer documentation fields (OBF_COMMENT_FIELDS) are encoded in their own
  domain under CommentCtx, with a key derived from the developer
  comment IKM - which is never derived from anything the runtime holds. }
function ObfuscateTree(ANode: TAvroNode; const ACtx: string; const ASeed, ACommentSeed: TBytes; ACommentDomain: Boolean;
  ARev: TDictionary<string, string>; const ASkip: TDictionary<string, Boolean>): TAvroNode;
var
  I:                         Integer;
  OrigKey, HashedKey:        string;
  Child:                     TAvroNode;
  ChildSeed, EffCommentSeed: TBytes;
  ChildCtxPath:              string;
  IsComment:                 Boolean;
begin
  // A container built without a comment key keeps comments in the value domain,
  // exactly like format v2, so the reader's fallback matches on both sides.
  EffCommentSeed := ACommentSeed;
  if Length(EffCommentSeed) = 0 then
    EffCommentSeed := ASeed;

  Result := TAvroNode.Create;
  case ANode.Kind of
    nkObject:
      begin
        Result.Kind := nkObject;
        for I := 0 to ANode.Items.Count - 1 do
        begin
          OrigKey := ANode.Keys[I];
          HashedKey := HexOfSha256(TEncoding.UTF8.GetBytes(OrigKey));
          if ASkip.ContainsKey(HashedKey) then
            Continue;
          if not ARev.ContainsKey(HashedKey) then
            ARev.Add(HashedKey, OrigKey);
          IsComment := IsCommentField(OrigKey);
          if IsComment and ACommentDomain then
          begin
            ChildSeed := EffCommentSeed;
            ChildCtxPath := CommentCtx(ACtx, HashedKey);
          end
          else
          begin
            // Value fields, and every comment field in a format-v2 container,
            // which has no separate comment domain: plain child context and
            // the value seed - the exact mirror of DeobfValue's
            // ACommentDomain=False path.
            ChildSeed := ASeed;
            ChildCtxPath := ChildCtx(ACtx, HashedKey);
          end;
          Child := ObfuscateTree(ANode.Items[I], ChildCtxPath, ChildSeed, EffCommentSeed, ACommentDomain, ARev, ASkip);
          Result.Keys.Add(HashedKey);
          Result.Items.Add(Child);
        end;
      end;
    nkArray:
      begin
        Result.Kind := nkArray;
        for I := 0 to ANode.Items.Count - 1 do
          Result.Items.Add(ObfuscateTree(ANode.Items[I], IndexCtx(ACtx, I), ASeed, EffCommentSeed, ACommentDomain, ARev, ASkip));
      end;
    nkString:
      begin
        Result.Kind := nkString;
        // XOR codec is symmetric: encode == decode.
        Result.StrVal := TNetEncoding.Base64.EncodeBytesToString(DeobfCodec(ASeed, TEncoding.UTF8.GetBytes(ANode.StrVal), ACtx));
      end;
    else
      Result.Kind := ANode.Kind;
      Result.BoolVal := ANode.BoolVal;
      Result.IntVal := ANode.IntVal;
      Result.FloatVal := ANode.FloatVal;
  end;
end;

{ Injects 4-8 decoy root keys with obfuscated random string values. The decoys
  are listed in ADummies and ASkip, so the deobfuscator drops them while the
  raw bytecode still looks like a larger, non-obvious document. }
procedure AddDummyEntries(ARoot: TAvroNode; const ASeed: TBytes; ASkip: TDictionary<string, Boolean>; ADummies: TStringList);
var
  I, N, Guard:    Integer;
  KeyBytes, Rand: TBytes;
  Key:            string;
  Node:           TAvroNode;
begin
  FillRandomBytes(Rand, 4);
  N := 4 + (Integer(Rand[0]) mod 5); // 4..8 decoys
  for I := 0 to N - 1 do
  begin
    Guard := 0;
    repeat
      FillRandomBytes(KeyBytes, 16);
      Key := 'd' + HexOfSha256(KeyBytes);
      Inc(Guard);
    until (not ASkip.ContainsKey(Key)) and (ARoot.Keys.IndexOf(Key) < 0) and (Guard < 16);
    if Guard >= 16 then
      Break;
    Node := TAvroNode.Create;
    Node.Kind := nkString;
    FillRandomBytes(Rand, 24);
    Node.StrVal := TNetEncoding.Base64.EncodeBytesToString(DeobfCodec(ASeed, Rand, Key));
    ARoot.Keys.Add(Key);
    ARoot.Items.Add(Node);
    ASkip.Add(Key, True);
    ADummies.Add(Key);
  end;
end;

{ _obf_meta JSON carries: seed (base64), key_map and dummies. NOTE the
  inverted key_map order - the deobfuscator reads
  Rev[JsonValue.Value] := JsonString.Value, i.e. hashed <- orig. }
function BuildMetaJson(const ASeed: TBytes; const ARev: TDictionary<string, string>; const ADummies: TStringList): string;
var
  Obj, KMap: TJSONObject;
  JArr:      TJSONArray;
  Pair:      TPair<string, string>;
  I:         Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('seed', TNetEncoding.Base64.EncodeBytesToString(ASeed));
    KMap := TJSONObject.Create;
    for Pair in ARev do
      KMap.AddPair(Pair.Value, Pair.Key); // orig -> hashed (inverted)
    Obj.AddPair('key_map', KMap);
    JArr := TJSONArray.Create;
    for I := 0 to ADummies.Count - 1 do
      JArr.Add(ADummies[I]);
    Obj.AddPair('dummies', JArr);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

{ ---- Bytecode serialization (mirror of ParseNode / ParseBytecode) - }

procedure StreamWriteBE16(AStrm: TStream; V: Word);
var
  B: array [0 .. 1] of Byte;
begin
  B[0] := Byte(V shr 8);
  B[1] := Byte(V);
  AStrm.WriteBuffer(B, 2);
end;

procedure StreamWriteBE32(AStrm: TStream; V: Cardinal);
var
  B: array [0 .. 3] of Byte;
begin
  B[0] := Byte(V shr 24);
  B[1] := Byte(V shr 16);
  B[2] := Byte(V shr 8);
  B[3] := Byte(V);
  AStrm.WriteBuffer(B, 4);
end;

procedure BcWriteNode(AStrm: TStream; ANode: TAvroNode);
var
  Typ, B: Byte;
  Bytes:  TBytes;
  Bits:   UInt64;
  I, Cnt: Integer;
begin
  case ANode.Kind of
    nkNull:
      Typ := TYPE_NULL;
    nkBool:
      Typ := TYPE_BOOLEAN;
    nkInt, nkFloat:
      Typ := TYPE_NUMBER;
    nkString:
      Typ := TYPE_STRING;
    nkArray:
      Typ := TYPE_ARRAY;
    nkObject:
      Typ := TYPE_OBJECT;
    else
      raise ShieldWriterError('Cannot serialize node kind');
  end;
  AStrm.WriteBuffer(Typ, 1);

  case ANode.Kind of
    nkBool:
      begin
        B := 0;
        if ANode.BoolVal then
          B := 1;
        AStrm.WriteBuffer(B, 1);
      end;
    nkInt, nkFloat:
      begin
        if ANode.Kind = nkInt then
        begin
          B := 1;
          Bits := UInt64(ANode.IntVal);
        end
        else
        begin
          B := 0;
          Move(ANode.FloatVal, Bits, 8);
        end;
        AStrm.WriteBuffer(B, 1);
        for I := 7 downto 0 do
        begin
          B := Byte(Bits shr (I * 8));
          AStrm.WriteBuffer(B, 1);
        end;
      end;
    nkString:
      begin
        // String payloads are XOR-masked with the deterministic length-keyed
        // keystream; the reader unmasks with the same function.
        Bytes := BcMaskString(TEncoding.UTF8.GetBytes(ANode.StrVal));
        StreamWriteBE32(AStrm, Cardinal(Length(Bytes)));
        if Length(Bytes) > 0 then
          AStrm.WriteBuffer(Bytes[0], Length(Bytes));
      end;
    nkArray:
      begin
        Cnt := ANode.Items.Count;
        StreamWriteBE32(AStrm, Cardinal(Cnt));
        for I := 0 to Cnt - 1 do
          BcWriteNode(AStrm, ANode.Items[I]);
      end;
    nkObject:
      begin
        Cnt := ANode.Items.Count;
        StreamWriteBE32(AStrm, Cardinal(Cnt));
        for I := 0 to Cnt - 1 do
        begin
          Bytes := TEncoding.UTF8.GetBytes(ANode.Keys[I]);
          StreamWriteBE16(AStrm, Word(Length(Bytes)));
          if Length(Bytes) > 0 then
            AStrm.WriteBuffer(Bytes[0], Length(Bytes));
          BcWriteNode(AStrm, ANode.Items[I]);
        end;
      end;
  end;
end;

{ 'AVROBC' + ver + BE32(TypeCount=0) + BE32(EntryCount) + 8 reserved bytes
  (= 23-byte header) + per-entry: BE16 keyLen, key, BE32 nodeLen, node,
  BE32 crc32 + SHA-256 trailer over everything before the last 32 bytes. }
function AssembleBytecode(ARoot: TAvroNode): TBytes;
var
  MS, EntryMS, NodeMS:           TMemoryStream;
  B:                             Byte;
  I:                             Integer;
  Crc:                           Cardinal;
  Trailer, TrailerSrc, KeyBytes: TBytes;
begin
  Result := nil;
  MS := TMemoryStream.Create;
  EntryMS := TMemoryStream.Create;
  NodeMS := TMemoryStream.Create;
  try
    // Magic + version
    MS.WriteBuffer(AsMagicBC[0], 6);
    B := 1;
    MS.WriteBuffer(B, 1);
    // TypeCount = 0 (no type table)
    StreamWriteBE32(MS, 0);
    // EntryCount
    StreamWriteBE32(MS, Cardinal(ARoot.Items.Count));
    // 8 reserved bytes -> 23-byte header (reader does not validate them)
    B := 0;
    for I := 0 to 7 do
      MS.WriteBuffer(B, 1);
    // Entries
    for I := 0 to ARoot.Items.Count - 1 do
    begin
      EntryMS.Size := 0;
      EntryMS.Position := 0;
      // BE16 keyLen + raw key bytes (object keys are stored unmasked)
      KeyBytes := TEncoding.UTF8.GetBytes(ARoot.Keys[I]);
      StreamWriteBE16(EntryMS, Word(Length(KeyBytes)));
      if Length(KeyBytes) > 0 then
        EntryMS.WriteBuffer(KeyBytes[0], Length(KeyBytes));
      // BE32 nodeLen + node bytes
      NodeMS.Size := 0;
      NodeMS.Position := 0;
      BcWriteNode(NodeMS, ARoot.Items[I]);
      StreamWriteBE32(EntryMS, Cardinal(NodeMS.Size));
      if NodeMS.Size > 0 then
        EntryMS.WriteBuffer(NodeMS.Memory^, NodeMS.Size);
      // crc32 over keyLen+key+nodeLen+node
      Crc := crc32(0, PByte(EntryMS.Memory), EntryMS.Size);
      // Append entry + stored crc to the bytecode stream
      MS.WriteBuffer(EntryMS.Memory^, EntryMS.Size);
      StreamWriteBE32(MS, Crc);
    end;
    // SHA-256 trailer over everything written so far
    SetLength(TrailerSrc, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(TrailerSrc[0], MS.Size);
      MS.Position := MS.Size;
    end;
    Trailer := Sha256Of(TrailerSrc);
    FillChar(TrailerSrc[0], Length(TrailerSrc), 0);
    SetLength(TrailerSrc, 0);
    MS.WriteBuffer(Trailer[0], Length(Trailer));
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(Result[0], MS.Size);
    end;
  finally
    NodeMS.Free;
    EntryMS.Free;
    MS.Free;
  end;
end;

function DecodeBytecodeToJson(const ABytecode, AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AJsonUtf8: TBytes): TAvroShieldResult;
var
  Root, Deobf: TAvroNode;
  JsonText: string;
begin
  AJsonUtf8 := nil;
  Root := nil;
  Deobf := nil;
  try
    try
      if not ParseBytecode(ABytecode, Root) then
        Exit(asrBadBytecode);
      if not DeobfuscateEx(Root, AKeyMeta, ACommentsIKM, AIncludeComments, Deobf) then
        Exit(asrCorruptPayload);
      JsonText := NodeToJSON(Deobf);
      try
        AJsonUtf8 := TEncoding.UTF8.GetBytes(JsonText);
        Result := asrOk;
      finally
        AvroWipeString(JsonText);
      end;
    finally
      Deobf.Free;
      Root.Free;
    end;
  except
    AvroWipeAndRelease(AJsonUtf8);
    Result := asrCorruptPayload;
  end;
end;

function EncodeJsonToBytecode(const AJSONText: string; const AMaster, ACommentsIKM: TBytes; ATargetVersion: Byte; out ABytecode: TBytes): TAvroShieldResult;
var
  JSON: TJSONValue;
  Root, Obf, MetaNode: TAvroNode;
  Rev: TDictionary<string, string>;
  Skip: TDictionary<string, Boolean>;
  Dummies: TStringList;
  Seed, CommentSeed, Mask: TBytes;
  MetaJson: string;
begin
  ABytecode := nil;
  if (ATargetVersion <> 2) and (ATargetVersion <> 3) then
    Exit(asrBadVersion);
  JSON := TJSONObject.ParseJSONValue(Trim(AJSONText));
  if JSON = nil then
    Exit(asrCorruptPayload);
  if not (JSON is TJSONObject) then
  begin
    JSON.Free;
    Exit(asrNotJsonObject);
  end;
  try
    Root := JsonValueToNode(JSON);
  finally
    JSON.Free;
  end;
  Obf := nil;
  Rev := nil;
  Skip := nil;
  Dummies := nil;
  try
    try
      FillRandomBytes(Seed, 32);
      CommentSeed := CommentKey(ACommentsIKM, Seed);
      if ATargetVersion = 3 then
        Mask := MetaMask(AMaster)
      else
        Mask := MetaSeed;
      Rev := TDictionary<string, string>.Create;
      Skip := TDictionary<string, Boolean>.Create;
      Dummies := TStringList.Create;
      Skip.Add(META_KEY, True);
      Obf := ObfuscateTree(Root, '', Seed, CommentSeed, ATargetVersion = 3, Rev, Skip);
      AddDummyEntries(Obf, Seed, Skip, Dummies);
      MetaJson := BuildMetaJson(Seed, Rev, Dummies);
      try
        MetaNode := TAvroNode.Create;
        MetaNode.Kind := nkString;
        MetaNode.StrVal := TNetEncoding.Base64.EncodeBytesToString(DeobfCodec(Mask, TEncoding.UTF8.GetBytes(MetaJson), META_KEY));
        Obf.Keys.Add(META_KEY);
        Obf.Items.Add(MetaNode);
        ABytecode := AssembleBytecode(Obf);
      finally
        AvroWipeString(MetaJson);
      end;
      if Length(ABytecode) = 0 then
      begin
        ABytecode := nil;
        Result := asrCorruptPayload;
      end
      else
        Result := asrOk;
    finally
      Obf.Free;
      Dummies.Free;
      Skip.Free;
      Rev.Free;
      AvroWipeAndRelease(Seed);
      AvroWipeAndRelease(CommentSeed);
      AvroWipeAndRelease(Mask);
    end;
  finally
    Root.Free;
  end;
end;

end.
