unit uDataStream;

interface

uses
  System.SysUtils;

function ExpandStream(const AData: TBytes): TBytes;
function CollapseStream(const AData: TBytes): TBytes;

implementation

uses
  System.Classes,
  System.ZLib;

function ExpandStream(const AData: TBytes): TBytes;
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

function CollapseStream(const AData: TBytes): TBytes;
var
  InS, OutS: TMemoryStream;
  Z: TZCompressionStream;
  Buf: array [0 .. 8191] of Byte;
  N: Integer;
begin
  Result := nil;
  InS := TMemoryStream.Create;
  OutS := TMemoryStream.Create;
  Z := nil;
  try
    if Length(AData) > 0 then
      InS.Write(AData[0], Length(AData));
    InS.Position := 0;
    Z := TZCompressionStream.Create(OutS, zcDefault, 15);
    try
      repeat
        N := InS.Read(Buf, SizeOf(Buf));
        if N > 0 then
          Z.Write(Buf, N);
      until N < SizeOf(Buf);
    finally
      Z.Free;
    end;
    SetLength(Result, OutS.Size);
    if OutS.Size > 0 then
    begin
      OutS.Position := 0;
      OutS.Read(Result[0], OutS.Size);
    end;
  finally
    OutS.Free;
    InS.Free;
  end;
end;

end.
