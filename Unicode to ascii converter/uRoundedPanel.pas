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
  ExtCtrls,
  Messages,
  Controls,
  Windows;

type
  TRoundedPanel = class(TPanel)
  private
    FOnDraw: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
    procedure CreateParams(var Params: TCreateParams); override;
  public
    function Surface: TCanvas;
  published
    property OnDraw: TNotifyEvent read FOnDraw write FOnDraw;
  end;

implementation

{ =============================================================================== }

procedure TRoundedPanel.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // Panel must not over-paint its children (RichEdit) during live resize
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

{ =============================================================================== }

procedure TRoundedPanel.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Prevent background erasing to stop flicker during resize
  Message.Result := 1;
end;

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
  Classes.RegisterClass(TRoundedPanel);

end.
