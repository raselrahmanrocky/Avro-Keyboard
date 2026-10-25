unit uBufferTransform;

{$INLINE OFF}

interface

uses
  System.SysUtils,
  System.Hash,
  System.Math,
  uAvroShieldTypes,
  uEncoReader;

function TransformBuffer(const AIn, AKey, ANonce, AAAD: TBytes; out APlain: TBytes): Boolean;
procedure SealBuffer(const APlain, AKey, ANonce, AAAD: TBytes; out ASealed: TBytes);
function VerifySeal(const AKey, AMessage, AExpected: TBytes): Boolean;
function BuildSeal(const AKey, AMessage: TBytes): TBytes;
function OpenAuthenticated(const AEnvelope: TEncoEnvelope; const AEncKey, AMacKey: TBytes; out ACompressed: TBytes): TAvroShieldResult;
function Sha256Of(const AData: TBytes): TBytes;
function ConstTimeEqual(const A, B: TBytes): Boolean;

implementation

uses
  uAvroCryptoUtils,
  uAvroSecureMem,
  uAvroShieldVM;

function Sha256Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

function HmacSha512(const AKey, AMessage: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AMessage, AKey, THashSHA2.TSHA2Version.SHA512);
end;

function ConstTimeEqual(const A, B: TBytes): Boolean;
var
  I, D: Integer;
begin
  VMBeginVirtualization('cte');
  D := Length(A) xor Length(B);
  for I := 0 to Min(Length(A), Length(B)) - 1 do
    D := D or (Integer(A[I]) xor Integer(B[I]));
  Result := D = 0;
  VMEnd;
end;

function TransformBuffer(const AIn, AKey, ANonce, AAAD: TBytes; out APlain: TBytes): Boolean;
begin
  Result := AES256GCMDecrypt(AIn, AKey, ANonce, AAAD, APlain);
end;

procedure SealBuffer(const APlain, AKey, ANonce, AAAD: TBytes; out ASealed: TBytes);
begin
  AES256GCMEncrypt(APlain, AKey, ANonce, AAAD, ASealed);
end;

function BuildSeal(const AKey, AMessage: TBytes): TBytes;
begin
  Result := HmacSha512(AKey, AMessage);
end;

function VerifySeal(const AKey, AMessage, AExpected: TBytes): Boolean;
begin
  Result := ConstTimeEqual(HmacSha512(AKey, AMessage), AExpected);
end;

function OpenAuthenticated(const AEnvelope: TEncoEnvelope; const AEncKey, AMacKey: TBytes; out ACompressed: TBytes): TAvroShieldResult;
var
  MacOk, CryptoOk: Boolean;
  Sealed, Plain: TBytes;
begin
  ACompressed := nil;
  SetLength(Sealed, Length(AEnvelope.Cipher) + Length(AEnvelope.AuthTag));
  if Length(AEnvelope.Cipher) > 0 then
    Move(AEnvelope.Cipher[0], Sealed[0], Length(AEnvelope.Cipher));
  if Length(AEnvelope.AuthTag) > 0 then
    Move(AEnvelope.AuthTag[0], Sealed[Length(AEnvelope.Cipher)], Length(AEnvelope.AuthTag));

  try
    MacOk := ConstTimeEqual(HmacSha512(AMacKey, AEnvelope.HmacInput), AEnvelope.Mac);
    CryptoOk := TransformBuffer(Sealed, AEncKey, AEnvelope.IV, nil, Plain);

    if not AvroFuseOk(AvroFuse(MacOk and CryptoOk)) then
    begin
      AvroWipeAndRelease(Plain);
      if not MacOk then
        Exit(asrHmacFailed);
      Exit(asrDecryptFailed);
    end;

    ACompressed := Plain;
    Plain := nil;
    Result := asrOk;
  finally
    AvroWipeAndRelease(Sealed);
    AvroWipeAndRelease(Plain);
  end;
end;

end.
