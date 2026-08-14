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
  // Interceptor class for TPanel (same name as the VCL base class, so the
  // .dfm only needs the standard "TPanel" class name the IDE knows).  The
  // form designer instantiates the plain VCL TPanel; at runtime this
  // interceptor is used instead and provides the rounded-frame drawing
  // (OnDraw) and flicker-free resize behaviour.
  TPanel = class(ExtCtrls.TPanel)
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

procedure TPanel.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // Panel must not over-paint its children (RichEdit) during live resize
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

{ =============================================================================== }

procedure TPanel.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Prevent background erasing to stop flicker during resize
  message.Result := 1;
end;

{ =============================================================================== }

procedure TPanel.Paint;
begin
  inherited Paint;
  if Assigned(FOnDraw) then
    FOnDraw(Self);
end;

{ =============================================================================== }

function TPanel.Surface: TCanvas;
begin
  Result := Canvas;
end;

end.
