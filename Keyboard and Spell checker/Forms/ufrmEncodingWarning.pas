{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmEncodingWarning;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Variants,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  ExtCtrls;

type
  TfrmEncodingWarning = class(TForm)
    Panel1: TPanel;
    Label1: TLabel;
    Image1: TImage;
    Label7: TLabel;
    Image2: TImage;
    TextWarning1: TLabel;
    TextWarning2: TLabel;
    TextConverterWarning: TLabel;
    Button1: TButton;
    Button2: TButton;
    CheckBox_ShowWarning: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FTopmostTimer: TTimer;
    procedure KeepTopmost(Sender: TObject);
  protected
    procedure WndProc(var Message: TMessage); override;
  end;

var
  frmEncodingWarning: TfrmEncodingWarning;

implementation

{$R *.dfm}

uses
  uWindowHandlers,
  uRegistrySettings,
  uform1;

procedure TfrmEncodingWarning.Button1Click(Sender: TObject);
begin
  if CheckBox_ShowWarning.Checked then
    ShowOutputwarning := 'YES'
  else
    ShowOutputwarning := 'NO';

  AvroMainForm1.RefreshSettings;

  { Restore the prior per-window state when any pending ANSI change is cancelled. }
  AvroMainForm1.ApplyPendingANSISwitchRevert;

  Self.Close;
end;

procedure TfrmEncodingWarning.Button2Click(Sender: TObject);
begin
  if CheckBox_ShowWarning.Checked then
    ShowOutputwarning := 'YES'
  else
    ShowOutputwarning := 'NO';

  { Confirm the pending ANSI switch (no revert). }
  AvroMainForm1.CommitPendingANSISwitch;

  AvroMainForm1.RefreshSettings;
  Self.Close;
end;

procedure TfrmEncodingWarning.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FTopmostTimer.Enabled := False;

  { If the form is closed via X / Alt-F4 while a pending ANSI switch is
    in progress, treat it as a cancel and revert. }
  AvroMainForm1.ApplyPendingANSISwitchRevert;

  Action := caFree;
  frmEncodingWarning := nil;
end;

procedure TfrmEncodingWarning.FormCreate(Sender: TObject);
begin
  TOPMOST(Self.Handle);

  FTopmostTimer := TTimer.Create(Self);
  FTopmostTimer.Interval := 100;
  FTopmostTimer.Enabled := False;
  FTopmostTimer.OnTimer := KeepTopmost;
end;

procedure TfrmEncodingWarning.FormShow(Sender: TObject);
begin
  TOPMOST(Self.Handle);
  FTopmostTimer.Enabled := True;
end;

procedure TfrmEncodingWarning.WndProc(var Message: TMessage);
var
  WindowPos: PWindowPos;
begin
  if (Message.Msg = WM_WINDOWPOSCHANGING) and Visible then
  begin
    WindowPos := PWindowPos(Message.LParam);
    if (WindowPos^.flags and SWP_NOZORDER) = 0 then
      WindowPos^.hwndInsertAfter := HWND_TOPMOST;
  end;

  inherited WndProc(Message);
  if (Message.Msg = WM_ACTIVATEAPP) and (Message.WParam = 0) and Visible then
    TOPMOST(Handle);
end;

procedure TfrmEncodingWarning.KeepTopmost(Sender: TObject);
begin
  if Visible then
    TOPMOST(Handle);
end;

end.
