{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

unit ufrmAnsiToast;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  ExtCtrls,
  StdCtrls;

type
  TfrmAnsiToast = class(TForm)
    private
      FLabel: TLabel;
      FTimer: TTimer;
      procedure TimerHandler(Sender: TObject);
      procedure FormDeactivate(Sender: TObject);
      procedure FormClose(Sender: TObject; var Action: TCloseAction);
      procedure ClickHandler(Sender: TObject);
    protected
      procedure CreateParams(var Params: TCreateParams); override;
    public
      procedure Setup;
      procedure ShowToast(const AText: string);
  end;

procedure ShowAnsiToastNotification(const AText: string);

implementation

uses
  clsUnicodeToBijoy2000;

procedure ShowAnsiToastNotification(const AText: string);
var
  Toast: TfrmAnsiToast;
begin
  Toast := TfrmAnsiToast.CreateNew(Application);
  Toast.Setup;
  Toast.ShowToast(AText);
end;

{ TfrmAnsiToast }

procedure TfrmAnsiToast.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.ExStyle := Params.ExStyle or WS_EX_TOPMOST or WS_EX_NOACTIVATE or WS_EX_TOOLWINDOW;
  Params.WndParent := GetDesktopWindow;
end;

procedure TfrmAnsiToast.Setup;
begin
  BorderStyle := bsNone;
  AlphaBlend := True;
  AlphaBlendValue := 220;
  Color := $404040;
  Height := 42;

  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.Align := alClient;
  FLabel.Alignment := taCenter;
  FLabel.Layout := tlCenter;
  FLabel.Transparent := True;
  FLabel.Font.Color := clWhite;
  FLabel.Font.Size := 11;
  FLabel.Font.Name := 'Segoe UI';
  FLabel.OnClick := ClickHandler;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 3000;
  FTimer.OnTimer := TimerHandler;
  FTimer.Enabled := False;

  OnDeactivate := FormDeactivate;
  OnClose := FormClose;
  OnClick := ClickHandler;
end;

procedure TfrmAnsiToast.ShowToast(const AText: string);
begin
  FLabel.Caption := AText;
  FLabel.Canvas.Font := FLabel.Font;
  Width := FLabel.Canvas.TextWidth(AText) + 40;

  Left := Screen.Width - Width - 20;
  Top := Screen.Height - Height - 50;

  SetWindowPos(Handle, HWND_TOPMOST, Left, Top, Width, Height, SWP_NOACTIVATE or SWP_SHOWWINDOW);
  FTimer.Enabled := True;
end;

procedure TfrmAnsiToast.TimerHandler(Sender: TObject);
begin
  FTimer.Enabled := False;
  Close;
end;

procedure TfrmAnsiToast.FormDeactivate(Sender: TObject);
begin
  Close;
end;

procedure TfrmAnsiToast.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  OptimizeMemoryUsage;
end;

procedure TfrmAnsiToast.ClickHandler(Sender: TObject);
begin
  Close;
end;

end.
