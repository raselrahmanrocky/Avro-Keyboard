unit uResourceDataProvider;

interface

uses
  System.SysUtils;

type
  EResourceUnavailable = class(Exception);

const
  IsResourceProviderAvailable: Boolean = False;
  IsProductionResource: Boolean = False;

function LoadResourceBlock: TBytes;
function LoadResourceBlockText: string;
function ResourceBlockAvailable: Boolean;

implementation

function ResourceBlockAvailable: Boolean;
begin
  Result := False;
end;

function LoadResourceBlock: TBytes;
begin
  raise EResourceUnavailable.Create('resource unavailable');
end;

function LoadResourceBlockText: string;
begin
  Result := '';
end;

end.
