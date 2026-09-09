unit ufrmAnsiToast;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, ExtCtrls,
  StdCtrls;

type
  TfrmAnsiToast = class(TForm)
  private
    FLabel: TLabel;
    FTimer: TTimer;
    procedure TimerHandler(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure WMMouseActivate(var Msg: TWMMouseActivate); message WM_MOUSEACTIVATE;
  public
    procedure Setup;
    procedure ShowToast(const AText: string);
  end;

procedure ShowAnsiToastNotification(const AText: string);

implementation

var
  CurrentToast: TfrmAnsiToast;

procedure ShowAnsiToastNotification(const AText: string);
begin
  if not Assigned(CurrentToast) then
  begin
    CurrentToast := TfrmAnsiToast.CreateNew(Application);
    CurrentToast.Setup;
  end;
  CurrentToast.ShowToast(AText);
end;

procedure TfrmAnsiToast.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.Style := WS_POPUP;
  Params.ExStyle := Params.ExStyle or WS_EX_TOPMOST or WS_EX_NOACTIVATE or
    WS_EX_TOOLWINDOW;
  Params.WndParent := GetDesktopWindow;
end;

procedure TfrmAnsiToast.WMMouseActivate(var Msg: TWMMouseActivate);
begin
  Msg.Result := MA_NOACTIVATE;
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

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 1200;
  FTimer.OnTimer := TimerHandler;
  FTimer.Enabled := False;
  OnClose := FormClose;
end;

procedure TfrmAnsiToast.ShowToast(const AText: string);
begin
  FTimer.Enabled := False;
  FLabel.Caption := AText;
  FLabel.Canvas.Font := FLabel.Font;
  Width := FLabel.Canvas.TextWidth(AText) + 40;
  Left := Screen.WorkAreaRect.Right - Width - 20;
  Top := Screen.WorkAreaRect.Bottom - Height - 20;
  SetWindowPos(Handle, HWND_TOPMOST, Left, Top, Width, Height,
    SWP_NOACTIVATE or SWP_SHOWWINDOW);
  ShowWindow(Handle, SW_SHOWNOACTIVATE);
  FTimer.Enabled := True;
end;

procedure TfrmAnsiToast.TimerHandler(Sender: TObject);
begin
  FTimer.Enabled := False;
  ShowWindow(Handle, SW_HIDE);
end;

procedure TfrmAnsiToast.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FTimer.Enabled := False;
  ShowWindow(Handle, SW_HIDE);
  Action := caNone;
end;

initialization
  CurrentToast := nil;

finalization
  FreeAndNil(CurrentToast);

end.
