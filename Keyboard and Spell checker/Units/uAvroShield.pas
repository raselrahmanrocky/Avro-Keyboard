unit uAvroShield;

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}
{$INLINE OFF}

interface

uses
  System.SysUtils,
  uAvroShieldTypes;

type
  TAvroShieldResult = uAvroShieldTypes.TAvroShieldResult;
  TAvroShieldLoadOptions = uAvroShieldTypes.TAvroShieldLoadOptions;
  TAvroNodeKind = uAvroShieldTypes.TAvroNodeKind;
  TAvroNode = uAvroShieldTypes.TAvroNode;
  EAvroShieldError = uAvroShieldTypes.EAvroShieldError;

const
  asrOk = uAvroShieldTypes.asrOk;
  asrFileNotFound = uAvroShieldTypes.asrFileNotFound;
  asrFileTooShort = uAvroShieldTypes.asrFileTooShort;
  asrBadMagic = uAvroShieldTypes.asrBadMagic;
  asrBadVersion = uAvroShieldTypes.asrBadVersion;
  asrMachineMismatch = uAvroShieldTypes.asrMachineMismatch;
  asrMachineBindRequired = uAvroShieldTypes.asrMachineBindRequired;
  asrHmacFailed = uAvroShieldTypes.asrHmacFailed;
  asrDecryptFailed = uAvroShieldTypes.asrDecryptFailed;
  asrDecompressFailed = uAvroShieldTypes.asrDecompressFailed;
  asrBadBytecode = uAvroShieldTypes.asrBadBytecode;
  asrCorruptPayload = uAvroShieldTypes.asrCorruptPayload;
  asrEmptyPassword = uAvroShieldTypes.asrEmptyPassword;
  asrNotJsonObject = uAvroShieldTypes.asrNotJsonObject;
  asrUnknown = uAvroShieldTypes.asrUnknown;

  nkNull = uAvroShieldTypes.nkNull;
  nkBool = uAvroShieldTypes.nkBool;
  nkInt = uAvroShieldTypes.nkInt;
  nkFloat = uAvroShieldTypes.nkFloat;
  nkString = uAvroShieldTypes.nkString;
  nkArray = uAvroShieldTypes.nkArray;
  nkObject = uAvroShieldTypes.nkObject;

function AvroShieldDefaultLoadOptions: TAvroShieldLoadOptions;
function AvroShieldLoadFromFile(const AFileName, APassword: string; out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;
function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string; out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;
function AvroShieldLoadFromBytesUtf8(const AData: TBytes; const APassword: string; out AJsonUtf8: TBytes; AUseMachineBind: Boolean = True): TAvroShieldResult;
function AvroShieldLoadFromBytesUtf8Ex(const AData: TBytes; const APassword: string; const AOptions: TAvroShieldLoadOptions; out AJsonUtf8: TBytes)
  : TAvroShieldResult;
function AvroShieldExtractObfuscatedBytecode(const AData: TBytes; const APassword: string; const ADefaultSecretIKM: TBytes; AUseMachineBind: Boolean;
  out ABytecode: TBytes): TAvroShieldResult;
function AvroShieldSupportedVersion(AVer: Byte): Boolean;
function AvroShieldCurrentVersion: Byte;
function AvroShieldIsCommentField(const AName: string): Boolean;
function AvroShieldCommentCtx(const ACtx, AName: string): string;
function AvroShieldMetaMask(const AMaster: TBytes): TBytes;
function AvroShieldCommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;
function AvroShieldLoadForRuntime(const AData: TBytes; const APassword: string; out AJsonUtf8: TBytes; AUseMachineBind: Boolean = True): TAvroShieldResult;
function AvroShieldMachineId: TBytes;
function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
function AvroShieldDeobfuscateEx(const AObfuscated: TAvroNode; const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AValue: TAvroNode): Boolean;
function AvroShieldNodeToJSON(const ANode: TAvroNode): string;
function AvroShieldContainerUsesDefaultKey(const AFilePath: string): Boolean;
function HkdfExtractSHA256(const ASalt, AIKM: TBytes): TBytes;
function HkdfExpandSHA256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
function Pbkdf2HMACSHA256(const APassword, ASalt: TBytes; AIterations, ADkLen: Integer): TBytes;
function AvroShieldBuildFromJson(const AJSONText, APassword: string; const ADefaultKey, ABindToMachine, AUseHardwareFactor: Boolean; out AOutBytes: TBytes;
  const ADefaultSecretIKM: TBytes = nil; const ACommentsIKM: TBytes = nil; const ATargetVersion: Byte = 3): TAvroShieldResult;

implementation

uses
  System.Classes,
  uEncoReader,
  uKeyBuilder,
  uBufferTransform,
  uDataStream,
  uAvroShieldCodec,
  uResourceDataProvider,
  uAvroSecureMem,
  uAvroCryptoUtils;

function DecodeContainer(const AData: TBytes; const APassword: string; const ADefaultSecretIKM: TBytes; AUseMachineBind: Boolean;
  out ABytecode, AMaster, ASalt: TBytes): TAvroShieldResult;
var
  Envelope: TEncoEnvelope;
  Secret, EncKey, MacKey, Compressed, Bytecode, Master, Tag, BCMagic: TBytes;
  Flags: Byte;
begin
  ABytecode := nil;
  AMaster := nil;
  ASalt := nil;
  Result := EncoReadEnvelope(AData, Envelope);
  if Result <> asrOk then
    Exit;
  try
    Flags := Envelope.Flags;
    if (Flags and EncoFlagMachineBind) <> 0 then
    begin
      if not AUseMachineBind then
        Exit(asrMachineBindRequired);
      Tag := HostTag;
      try
        if not ConstTimeEqual(Envelope.MachineTag, Tag) then
          Exit(asrMachineMismatch);
      finally
        AvroWipeAndRelease(Tag);
      end;
    end;

    try
      if (Flags and EncoFlagDefaultKey) <> 0 then
      begin
        if Length(ADefaultSecretIKM) > 0 then
          Secret := Copy(ADefaultSecretIKM, 0, Length(ADefaultSecretIKM))
        else
          Secret := LoadResourceBlock;
      end
      else
        Secret := TEncoding.UTF8.GetBytes(APassword);

      if not BuildSessionKeys(Secret, Envelope.Salt, (Flags and EncoFlagDefaultKey) <> 0, Flags, Master, EncKey, MacKey) then
        Exit(asrUnknown);

      Result := OpenAuthenticated(Envelope, EncKey, MacKey, Compressed);
      if Result <> asrOk then
        Exit;

      Bytecode := ExpandStream(Compressed);
      if Length(Bytecode) = 0 then
        Exit(asrDecompressFailed);

      BCMagic := EncoBytecodeMagic;
      try
        if not CompareMem(@Bytecode[0], @BCMagic[0], Length(BCMagic)) then
          Exit(asrBadBytecode);
      finally
        AvroWipeAndRelease(BCMagic);
      end;

      ABytecode := Bytecode;
      Bytecode := nil;
      AMaster := Master;
      Master := nil;
      ASalt := Envelope.Salt;
      Envelope.Salt := nil;
      Result := asrOk;
    finally
      AvroWipeAndRelease(Secret);
      AvroWipeAndRelease(Master);
      AvroWipeAndRelease(EncKey);
      AvroWipeAndRelease(MacKey);
      AvroWipeAndRelease(Compressed);
      AvroWipeAndRelease(Bytecode);
    end;
  finally
    EncoWipeEnvelope(Envelope);
  end;
end;

function AvroShieldExtractObfuscatedBytecode(const AData: TBytes; const APassword: string; const ADefaultSecretIKM: TBytes; AUseMachineBind: Boolean;
  out ABytecode: TBytes): TAvroShieldResult;
var
  Master, Salt: TBytes;
begin
  ABytecode := nil;
  Result := DecodeContainer(AData, APassword, ADefaultSecretIKM, AUseMachineBind, ABytecode, Master, Salt);
  AvroWipeAndRelease(Master);
  AvroWipeAndRelease(Salt);
  if Result <> asrOk then
    AvroWipeAndRelease(ABytecode);
end;

function AvroShieldDefaultLoadOptions: TAvroShieldLoadOptions;
begin
  Result.UseMachineBind := True;
  Result.IncludeComments := False;
  Result.DefaultSecretIKM := nil;
  Result.CommentsIKM := nil;
end;

function AvroShieldSupportedVersion(AVer: Byte): Boolean;
begin
  Result := EncoSupportedVersion(AVer);
end;

function AvroShieldCurrentVersion: Byte;
begin
  Result := EncoCurrentVersion;
end;

function AvroShieldLoadFromBytesUtf8Ex(const AData: TBytes; const APassword: string; const AOptions: TAvroShieldLoadOptions; out AJsonUtf8: TBytes)
  : TAvroShieldResult;
var
  Bytecode, Master, Salt, KeyMeta: TBytes;
begin
  AJsonUtf8 := nil;
  Result := DecodeContainer(AData, APassword, AOptions.DefaultSecretIKM, AOptions.UseMachineBind, Bytecode, Master, Salt);
  if Result <> asrOk then
    Exit;
  try
    if EncoHeaderVersion(AData) = EncoVersionV3 then
      KeyMeta := uAvroShieldCodec.MetaMask(Master);
    try
      Result := uAvroShieldCodec.DecodeBytecodeToJson(Bytecode, KeyMeta, AOptions.CommentsIKM, AOptions.IncludeComments, AJsonUtf8);
    finally
      AvroWipeAndRelease(KeyMeta);
    end;
  finally
    AvroWipeAndRelease(Master);
    AvroWipeAndRelease(Salt);
    AvroWipeAndRelease(Bytecode);
  end;
end;

function AvroShieldLoadFromBytesUtf8(const AData: TBytes; const APassword: string; out AJsonUtf8: TBytes; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Options: TAvroShieldLoadOptions;
begin
  Options := AvroShieldDefaultLoadOptions;
  Options.UseMachineBind := AUseMachineBind;
  Result := AvroShieldLoadFromBytesUtf8Ex(AData, APassword, Options, AJsonUtf8);
end;

function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string; out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
var
  UTF8: TBytes;
begin
  AJSONText := '';
  Result := AvroShieldLoadFromBytesUtf8(AData, APassword, UTF8, AUseMachineBind);
  if Result = asrOk then
  begin
    AJSONText := TEncoding.UTF8.GetString(UTF8);
    AvroWipeAndRelease(UTF8);
  end;
end;

function AvroShieldLoadForRuntime(const AData: TBytes; const APassword: string; out AJsonUtf8: TBytes; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Raw: TAvroShieldResult;
begin
  Raw := AvroShieldLoadFromBytesUtf8(AData, APassword, AJsonUtf8, AUseMachineBind);
  if AvroFuseOk(AvroFuse(Raw = asrOk)) then
    Result := asrOk
  else
  begin
    AvroWipeAndRelease(AJsonUtf8);
    Result := asrHmacFailed;
  end;
end;

function AvroShieldLoadFromFile(const AFileName, APassword: string; out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
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
  try
    Result := AvroShieldLoadFromBytes(Data, APassword, AJSONText, AUseMachineBind);
  finally
    AvroWipeAndRelease(Data);
  end;
end;

function AvroShieldContainerUsesDefaultKey(const AFilePath: string): Boolean;
begin
  if not EncoFileUsesDefaultKey(AFilePath, Result) then
    Result := False;
end;

function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
begin
  Result := uAvroShieldCodec.ParseBytecode(ABytecode, AValue);
end;

function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
begin
  Result := uAvroShieldCodec.Deobfuscate(AObfuscated, AValue);
end;

function AvroShieldDeobfuscateEx(const AObfuscated: TAvroNode; const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean; out AValue: TAvroNode): Boolean;
begin
  Result := uAvroShieldCodec.DeobfuscateEx(AObfuscated, AKeyMeta, ACommentsIKM, AIncludeComments, AValue);
end;

function AvroShieldNodeToJSON(const ANode: TAvroNode): string;
begin
  Result := uAvroShieldCodec.NodeToJSON(ANode);
end;

function AvroShieldIsCommentField(const AName: string): Boolean;
begin
  Result := uAvroShieldCodec.IsCommentField(AName);
end;

function AvroShieldCommentCtx(const ACtx, AName: string): string;
begin
  Result := uAvroShieldCodec.CommentCtx(ACtx, AName);
end;

function AvroShieldMetaMask(const AMaster: TBytes): TBytes;
begin
  Result := uAvroShieldCodec.MetaMask(AMaster);
end;

function AvroShieldCommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;
begin
  Result := uAvroShieldCodec.CommentKey(ACommentsIKM, ASeed);
end;

function AvroShieldMachineId: TBytes;
begin
  Result := HostTag;
end;

function HkdfExtractSHA256(const ASalt, AIKM: TBytes): TBytes;
begin
  Result := uKeyBuilder.HkdfExtractSha256(ASalt, AIKM);
end;

function HkdfExpandSHA256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
begin
  Result := uKeyBuilder.HkdfExpandSha256(APRK, AInfo, ALen);
end;

function Pbkdf2HMACSHA256(const APassword, ASalt: TBytes; AIterations, ADkLen: Integer): TBytes;
begin
  Result := uKeyBuilder.Pbkdf2HmacSha256(APassword, ASalt, AIterations, ADkLen);
end;

function AvroShieldBuildFromJson(const AJSONText, APassword: string; const ADefaultKey, ABindToMachine, AUseHardwareFactor: Boolean; out AOutBytes: TBytes;
  const ADefaultSecretIKM: TBytes = nil; const ACommentsIKM: TBytes = nil; const ATargetVersion: Byte = 3): TAvroShieldResult;
var
  Salt, IV, Machine, Secret, Master, EncKey, MacKey, Compressed, Bytecode, Sealed, Header, HmacData, Hmac: TBytes;
  Flags: Byte;
  Magic: TBytes;
begin
  AOutBytes := nil;
  if (not ADefaultKey) and (APassword = '') then
    Exit(asrEmptyPassword);
  if (ATargetVersion <> EncoVersionV2) and (ATargetVersion <> EncoVersionV3) then
    Exit(asrBadVersion);

  FillRandomBytes(Salt, 16);
  Flags := EncoFlagPassword or EncoFlagBytecodeV1;
  if ADefaultKey then
    Flags := Flags or EncoFlagDefaultKey;
  if ABindToMachine then
    Flags := Flags or EncoFlagMachineBind;
  if AUseHardwareFactor then
    Flags := Flags or EncoFlagHardware;

  try
    try
      if ADefaultKey then
      begin
        if Length(ADefaultSecretIKM) > 0 then
          Secret := Copy(ADefaultSecretIKM, 0, Length(ADefaultSecretIKM))
        else
          Secret := LoadResourceBlock;
      end
      else
        Secret := TEncoding.UTF8.GetBytes(APassword);

      if not BuildSessionKeys(Secret, Salt, ADefaultKey, Flags, Master, EncKey, MacKey) then
        Exit(asrUnknown);

      Result := uAvroShieldCodec.EncodeJsonToBytecode(AJSONText, Master, ACommentsIKM, ATargetVersion, Bytecode);
      if Result <> asrOk then
        Exit;

      Compressed := CollapseStream(Bytecode);
      AvroWipeAndRelease(Bytecode);
      if Length(Compressed) = 0 then
        Exit(asrCorruptPayload);

      FillRandomBytes(IV, 16);
      if ABindToMachine then
        Machine := HostTag
      else
      begin
        SetLength(Machine, 16);
        FillChar(Machine[0], 16, 0);
      end;

      SealBuffer(Compressed, EncKey, IV, nil, Sealed);
      AvroWipeAndRelease(Compressed);

      Magic := EncoMagic;
      try
        SetLength(Header, EncoHeaderSize);
        Move(Magic[0], Header[0], Length(Magic));
        Header[8] := ATargetVersion;
        Header[9] := Flags;
        Move(Salt[0], Header[10], 16);
        Move(IV[0], Header[26], 16);
        Move(Machine[0], Header[42], 16);
      finally
        AvroWipeAndRelease(Magic);
      end;

      HmacData := Header + Sealed;
      Hmac := BuildSeal(MacKey, HmacData);
      SetLength(AOutBytes, Length(Header) + Length(Sealed) + Length(Hmac));
      Move(Header[0], AOutBytes[0], Length(Header));
      Move(Sealed[0], AOutBytes[Length(Header)], Length(Sealed));
      Move(Hmac[0], AOutBytes[Length(Header) + Length(Sealed)], Length(Hmac));
      Result := asrOk;
    finally
      AvroWipeAndRelease(Secret);
      AvroWipeAndRelease(Master);
      AvroWipeAndRelease(EncKey);
      AvroWipeAndRelease(MacKey);
      AvroWipeAndRelease(Compressed);
      AvroWipeAndRelease(Bytecode);
      AvroWipeAndRelease(Sealed);
      AvroWipeAndRelease(Salt);
      AvroWipeAndRelease(IV);
      AvroWipeAndRelease(Machine);
      AvroWipeAndRelease(Header);
      AvroWipeAndRelease(HmacData);
      AvroWipeAndRelease(Hmac);
    end;
  except
    AvroWipeAndRelease(AOutBytes);
    raise;
  end;
end;

end.
