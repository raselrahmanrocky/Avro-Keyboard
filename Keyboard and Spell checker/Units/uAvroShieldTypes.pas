unit uAvroShieldTypes;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  TAvroShieldResult = (asrOk = 0, asrFileNotFound, asrFileTooShort, asrBadMagic, asrBadVersion, asrMachineMismatch, asrMachineBindRequired, asrHmacFailed,
    asrDecryptFailed, asrDecompressFailed, asrBadBytecode, asrCorruptPayload, asrEmptyPassword, asrNotJsonObject, asrUnknown);

  TAvroShieldLoadOptions = record
    UseMachineBind: Boolean;
    IncludeComments: Boolean;
    DefaultSecretIKM: TBytes;
    CommentsIKM: TBytes;
  end;

  TAvroNodeKind = (nkNull, nkBool, nkInt, nkFloat, nkString, nkArray, nkObject);

  TAvroNode = class
    public
      Kind:     TAvroNodeKind;
      BoolVal:  Boolean;
      IntVal:   Int64;
      FloatVal: Double;
      StrVal:   string;
      Items:    TObjectList<TAvroNode>;
      Keys:     TStringList;
      constructor Create;
      destructor Destroy; override;
  end;

  EAvroShieldError = class(Exception);

function ShieldOpaqueError(const AMessage: string): EAvroShieldError;
function ShieldWriterError(const AMessage: string): EAvroShieldError;

implementation

const
  SHIELD_OPAQUE_ERROR_TEXT = 'AvroShield: invalid container';

function ShieldOpaqueError(const AMessage: string): EAvroShieldError;
begin
  {$IFDEF AVROSHIELD_VERBOSE_ERRORS}
  Result := EAvroShieldError.Create(AMessage);
  {$ELSE}
  Result := EAvroShieldError.Create(SHIELD_OPAQUE_ERROR_TEXT);
  {$ENDIF}
end;

function ShieldWriterError(const AMessage: string): EAvroShieldError;
begin
  Result := EAvroShieldError.Create(AMessage);
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
