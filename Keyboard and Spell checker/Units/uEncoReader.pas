unit uEncoReader;

interface

uses
  System.SysUtils,
  System.Classes,
  uAvroShieldTypes,
  uAvroSecureMem;

const
  EncoVersionV2 = 2;
  EncoVersionV3 = 3;
  EncoHeaderSize = 58;
  EncoTrailerSize = 80;
  EncoHmacSize = 64;
  EncoFlagPassword = $01;
  EncoFlagHardware = $02;
  EncoFlagMachineBind = $04;
  EncoFlagBytecodeV1 = $08;
  EncoFlagDefaultKey = $10;

  { Key domain (uAvroShield container flags, bits 5-6).  A container says
    which key family it needs; the reader derives with the matching HKDF info
    string (uKeyBuilder.ShieldHkdfInfoFor) instead of guessing from a filename.
    $60 is reserved and refused, so every future value stays unambiguous. }
  EncoFlagDomainMask        = $60;
  EncoFlagDomainLegacy      = $00; // today's default-key family
  EncoFlagDomainAnsiMapping = $20; // Ansi V*.AvroEnco
  EncoFlagDomainKeyboardRes = $40; // the keyboard's own protected resources

type
  TEncoDomain = (edLegacy, edAnsiMapping, edKeyboardRes);

  TEncoEnvelope = record
    Version: Byte;
    Flags: Byte;
    Domain: TEncoDomain;
    Salt: TBytes;
    IV: TBytes;
    MachineTag: TBytes;
    Cipher: TBytes;
    AuthTag: TBytes;
    Mac: TBytes;
    HmacInput: TBytes;
    Header: TBytes;
  end;

function EncoMagic: TBytes;
function EncoBytecodeMagic: TBytes;
function EncoSupportedVersion(AVersion: Byte): Boolean;
function EncoCurrentVersion: Byte;
function EncoHeaderVersion(const AData: TBytes): Byte;
function EncoDomainOf(AFlags: Byte): TEncoDomain;
function EncoDomainFlags(ADomain: TEncoDomain): Byte;
function EncoDomainReserved(AFlags: Byte): Boolean;
function EncoReadEnvelope(const AData: TBytes; out AEnvelope: TEncoEnvelope): TAvroShieldResult;
function EncoReadDefaultKeyFlag(const AData: TBytes; out ADefaultKey: Boolean): Boolean;
function EncoFileUsesDefaultKey(const AFileName: string; out ADefaultKey: Boolean): Boolean;
procedure EncoWipeEnvelope(var AEnvelope: TEncoEnvelope);

implementation

function EncoMagic: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROSHLD');
end;

function EncoBytecodeMagic: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROBC');
end;

function EncoSupportedVersion(AVersion: Byte): Boolean;
begin
  Result := (AVersion = EncoVersionV2) or (AVersion = EncoVersionV3);
end;

function EncoCurrentVersion: Byte;
begin
  Result := EncoVersionV3;
end;

function EncoHeaderVersion(const AData: TBytes): Byte;
begin
  if Length(AData) < EncoHeaderSize then
    Result := 0
  else
    Result := AData[8];
end;

function EncoDomainOf(AFlags: Byte): TEncoDomain;
begin
  case (AFlags and EncoFlagDomainMask) of
    EncoFlagDomainAnsiMapping:
      Result := edAnsiMapping;
    EncoFlagDomainKeyboardRes:
      Result := edKeyboardRes;
  else
    Result := edLegacy;
  end;
end;

function EncoDomainFlags(ADomain: TEncoDomain): Byte;
begin
  case ADomain of
    edAnsiMapping:
      Result := EncoFlagDomainAnsiMapping;
    edKeyboardRes:
      Result := EncoFlagDomainKeyboardRes;
  else
    Result := EncoFlagDomainLegacy;
  end;
end;

function EncoDomainReserved(AFlags: Byte): Boolean;
begin
  Result := (AFlags and EncoFlagDomainMask) = EncoFlagDomainMask;
end;

function EncoReadEnvelope(const AData: TBytes; out AEnvelope: TEncoEnvelope): TAvroShieldResult;
var
  Magic: TBytes;
  BodyLen: Integer;
begin
  EncoWipeEnvelope(AEnvelope);
  if Length(AData) < EncoHeaderSize + EncoTrailerSize + 1 then
    Exit(asrFileTooShort);
  Magic := EncoMagic;
  try
    if not CompareMem(@AData[0], @Magic[0], Length(Magic)) then
      Exit(asrBadMagic);
  finally
    AvroWipeAndRelease(Magic);
  end;
  if not EncoSupportedVersion(AData[8]) then
    Exit(asrBadVersion);
  // Both domain bits set is reserved: refusing it keeps the meaning of every
  // future flag value unambiguous.
  if EncoDomainReserved(AData[9]) then
    Exit(asrBadVersion);
  BodyLen := Length(AData) - EncoHeaderSize - EncoTrailerSize;
  AEnvelope.Version := AData[8];
  AEnvelope.Flags := AData[9];
  AEnvelope.Domain := EncoDomainOf(AData[9]);
  AEnvelope.Salt := Copy(AData, 10, 16);
  AEnvelope.IV := Copy(AData, 26, 16);
  AEnvelope.MachineTag := Copy(AData, 42, 16);
  AEnvelope.Header := Copy(AData, 0, EncoHeaderSize);
  AEnvelope.Cipher := Copy(AData, EncoHeaderSize, BodyLen);
  AEnvelope.AuthTag := Copy(AData, EncoHeaderSize + BodyLen, 16);
  AEnvelope.Mac := Copy(AData, Length(AData) - EncoHmacSize, EncoHmacSize);
  AEnvelope.HmacInput := Copy(AData, 0, Length(AData) - EncoHmacSize);
  Result := asrOk;
end;

function EncoReadDefaultKeyFlag(const AData: TBytes; out ADefaultKey: Boolean): Boolean;
var
  Magic: TBytes;
begin
  Result := False;
  ADefaultKey := False;
  if Length(AData) < 10 then
    Exit;
  Magic := EncoMagic;
  try
    if not CompareMem(@AData[0], @Magic[0], Length(Magic)) then
      Exit;
  finally
    AvroWipeAndRelease(Magic);
  end;
  if not EncoSupportedVersion(AData[8]) then
    Exit;
  // A reserved flag byte describes no container this build can open, so it is
  // never reported as default-key protected.
  if EncoDomainReserved(AData[9]) then
    Exit;
  ADefaultKey := (AData[9] and EncoFlagDefaultKey) <> 0;
  Result := True;
end;

function EncoFileUsesDefaultKey(const AFileName: string; out ADefaultKey: Boolean): Boolean;
var
  FS: TFileStream;
  Head: TBytes;
begin
  Result := False;
  ADefaultKey := False;
  if not FileExists(AFileName) then
    Exit;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Head, 10);
    if FS.Read(Head[0], 10) <> 10 then
      Exit;
    Result := EncoReadDefaultKeyFlag(Head, ADefaultKey);
  finally
    AvroWipeAndRelease(Head);
    FS.Free;
  end;
end;

procedure EncoWipeEnvelope(var AEnvelope: TEncoEnvelope);
begin
  AvroWipeAndRelease(AEnvelope.Salt);
  AvroWipeAndRelease(AEnvelope.IV);
  AvroWipeAndRelease(AEnvelope.MachineTag);
  AvroWipeAndRelease(AEnvelope.Cipher);
  AvroWipeAndRelease(AEnvelope.AuthTag);
  AvroWipeAndRelease(AEnvelope.Mac);
  AvroWipeAndRelease(AEnvelope.HmacInput);
  AvroWipeAndRelease(AEnvelope.Header);
  AEnvelope.Version := 0;
  AEnvelope.Flags := 0;
  AEnvelope.Domain := edLegacy;
end;

end.
