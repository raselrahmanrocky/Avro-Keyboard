{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit uRoundedPanel;

interface

uses
  Classes,
  Graphics,
  ExtCtrls;

type
  TRoundedPanel = class(TPanel)
  private
    FOnDraw: TNotifyEvent;
  protected
    procedure Paint; override;
  public
    function Surface: TCanvas;
  published
    property OnDraw: TNotifyEvent read FOnDraw write FOnDraw;
  end;

implementation

{ =============================================================================== }

procedure TRoundedPanel.Paint;
begin
  inherited Paint;
  if Assigned(FOnDraw) then
    FOnDraw(Self);
end;

{ =============================================================================== }

function TRoundedPanel.Surface: TCanvas;
begin
  Result := Canvas;
end;

initialization
  RegisterClass(TRoundedPanel);

end.
