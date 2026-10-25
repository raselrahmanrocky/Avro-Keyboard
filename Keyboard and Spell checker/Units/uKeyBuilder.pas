unit uKeyBuilder;

{$INLINE OFF}

interface

uses
  System.SysUtils,
  System.Hash,
  uAvroShieldTypes;

const
  ShieldMasterLen = 32;
  ShieldHkdfInfoDefault = 'AvroShield-v2/hkdf-sha256/default-key';
  ShieldPbkdf2Iterations = 100000;

function HkdfExtractSha256(const ASalt, AIKM: TBytes): TBytes;
function HkdfExpandSha256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
function HkdfSha256(const ASalt, AIKM, AInfo: TBytes; ALen: Integer): TBytes;
function Pbkdf2HmacSha256(const APassword, ASalt: TBytes; AIterations, ADkLen: Integer): TBytes;
function Hash512Of(const AData: TBytes): TBytes;
function HostTag: TBytes;
function BuildSessionKeys(const ASecret, ASalt: TBytes; ADefaultKey: Boolean; AFlags: Byte; out AMaster, AEncKey, AMacKey: TBytes): Boolean;

implementation

uses
  Winapi.Windows,
  Winapi.IpHlpApi,
  Winapi.IpTypes,
  uEncoReader,
  uAvroSecureMem,
  uAvroShieldVM;

function HmacSha256(const AKey, AMessage: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AMessage, AKey, THashSHA2.TSHA2Version.SHA256);
end;

function HkdfExtractSha256(const ASalt, AIKM: TBytes): TBytes;
var
  ZeroSalt: TBytes;
begin
  if Length(ASalt) = 0 then
  begin
    SetLength(ZeroSalt, 32);
    try
      Result := HmacSha256(ZeroSalt, AIKM);
    finally
      AvroWipeAndRelease(ZeroSalt);
    end;
  end
  else
    Result := HmacSha256(ASalt, AIKM);
end;

function HkdfExpandSha256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
var
  T, Block: TBytes;
  N, Pos, Take: Integer;
begin
  SetLength(Result, ALen);
  SetLength(T, 0);
  N := 1;
  Pos := 0;
  try
    while Pos < ALen do
    begin
      if N > 255 then
        Break;
      SetLength(Block, Length(T) + Length(AInfo) + 1);
      if Length(T) > 0 then
        Move(T[0], Block[0], Length(T));
      if Length(AInfo) > 0 then
        Move(AInfo[0], Block[Length(T)], Length(AInfo));
      Block[Length(Block) - 1] := Byte(N);
      AvroWipeAndRelease(T);
      T := HmacSha256(APRK, Block);
      AvroWipeAndRelease(Block);
      Take := ALen - Pos;
      if Take > Length(T) then
        Take := Length(T);
      Move(T[0], Result[Pos], Take);
      Inc(Pos, Take);
      Inc(N);
    end;
  finally
    AvroWipeAndRelease(T);
  end;
end;

function HkdfSha256(const ASalt, AIKM, AInfo: TBytes; ALen: Integer): TBytes;
var
  PRK: TBytes;
begin
  PRK := HkdfExtractSha256(ASalt, AIKM);
  try
    Result := HkdfExpandSha256(PRK, AInfo, ALen);
  finally
    AvroWipeAndRelease(PRK);
  end;
end;

function Pbkdf2HmacSha256(const APassword, ASalt: TBytes; AIterations, ADkLen: Integer): TBytes;
var
  U, Acc, SaltBlock: TBytes;
  BlockNo, I, J, Pos, Take: Integer;
begin
  SetLength(Result, ADkLen);
  if ADkLen > 0 then
    FillChar(Result[0], ADkLen, 0);
  BlockNo := 1;
  Pos := 0;
  while Pos < ADkLen do
  begin
    SetLength(SaltBlock, Length(ASalt) + 4);
    if Length(ASalt) > 0 then
      Move(ASalt[0], SaltBlock[0], Length(ASalt));
    SaltBlock[Length(SaltBlock) - 4] := Byte((Cardinal(BlockNo) shr 24) and $FF);
    SaltBlock[Length(SaltBlock) - 3] := Byte((Cardinal(BlockNo) shr 16) and $FF);
    SaltBlock[Length(SaltBlock) - 2] := Byte((Cardinal(BlockNo) shr 8) and $FF);
    SaltBlock[Length(SaltBlock) - 1] := Byte(Cardinal(BlockNo) and $FF);
    U := HmacSha256(APassword, SaltBlock);
    AvroWipeAndRelease(SaltBlock);
    Acc := Copy(U, 0, Length(U));
    for I := 2 to AIterations do
    begin
      U := HmacSha256(APassword, U);
      for J := 0 to Length(Acc) - 1 do
        Acc[J] := Acc[J] xor U[J];
    end;
    Take := ADkLen - Pos;
    if Take > Length(Acc) then
      Take := Length(Acc);
    Move(Acc[0], Result[Pos], Take);
    Inc(Pos, Take);
    Inc(BlockNo);
    AvroWipeAndRelease(U);
    AvroWipeAndRelease(Acc);
  end;
end;

function Hash512Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

function Sha256Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

function ReadMachineGuid: string;
var
  RegKey: HKEY;
  Buf: array [0 .. 127] of WideChar;
  BufSize: DWORD;
begin
  Result := '';
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Cryptography', 0, KEY_READ or KEY_WOW64_64KEY, RegKey) = ERROR_SUCCESS then
    try
      BufSize := SizeOf(Buf);
      if RegQueryValueExW(RegKey, 'MachineGuid', nil, nil, @Buf[0], @BufSize) = ERROR_SUCCESS then
        Result := Buf;
    finally
      RegCloseKey(RegKey);
    end;
end;

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
          if P^.Type_ = 6 then
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

function HostTag: TBytes;
var
  Guid: string;
  Raw: TBytes;
begin
  Guid := ReadMachineGuid;
  if Guid = '' then
    Guid := GetPrimaryMacString;
  Raw := TEncoding.UTF8.GetBytes(Guid);
  try
    Result := Sha256Of(Raw);
    SetLength(Result, 16);
  finally
    AvroWipeAndRelease(Raw);
  end;
end;

function BuildSessionKeys(const ASecret, ASalt: TBytes; ADefaultKey: Boolean; AFlags: Byte; out AMaster, AEncKey, AMacKey: TBytes): Boolean;
var
  FinalKey, Raw, MachineF, HardwareF, Info: TBytes;
  Tag: TBytes;
begin
  AMaster := nil;
  AEncKey := nil;
  AMacKey := nil;
  try
    if ADefaultKey then
    begin
      Info := TEncoding.UTF8.GetBytes(ShieldHkdfInfoDefault);
      AMaster := HkdfSha256(ASalt, ASecret, Info, ShieldMasterLen);
    end
    else
    begin
      VMBeginVirtualization('kdfp');
      AMaster := Pbkdf2HmacSha256(ASecret, ASalt, ShieldPbkdf2Iterations, ShieldMasterLen);
      VMEnd;
    end;

    SetLength(MachineF, 16);
    SetLength(HardwareF, 16);
    if (AFlags and EncoFlagMachineBind) <> 0 then
    begin
      Tag := HostTag;
      Move(Tag[0], MachineF[0], 16);
      AvroWipeAndRelease(Tag);
    end;
    if (AFlags and EncoFlagHardware) <> 0 then
    begin
      Tag := HostTag;
      Move(Tag[0], HardwareF[0], 16);
      AvroWipeAndRelease(Tag);
    end;

    SetLength(Raw, Length(AMaster) + 32);
    Move(AMaster[0], Raw[0], Length(AMaster));
    Move(MachineF[0], Raw[Length(AMaster)], 16);
    Move(HardwareF[0], Raw[Length(AMaster) + 16], 16);
    FinalKey := Hash512Of(Raw);
    AEncKey := Copy(FinalKey, 0, 32);
    AMacKey := Copy(FinalKey, 32, 32);
    Result := True;
  finally
    AvroWipeAndRelease(Raw);
    AvroWipeAndRelease(FinalKey);
    AvroWipeAndRelease(MachineF);
    AvroWipeAndRelease(HardwareF);
    AvroWipeAndRelease(Info);
  end;
end;

end.
