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
    Label2: TLabel;
    Image1: TImage;
    Label3: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Image2: TImage;
    Image4: TImage;
    Image5: TImage;
    Button1: TButton;
    Button2: TButton;
    CheckBox_ShowWarning: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    private
      { Private declarations }
    public
      { Public declarations }
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
  OutputIsBijoy := 'NO';
  if CheckBox_ShowWarning.Checked then
    ShowOutputwarning := 'YES'
  else
    ShowOutputwarning := 'NO';

  AvroMainForm1.RefreshSettings;

  { If the user cancelled an ANSI switch initiated by a hotkey,
    restore the previous keyboard mode. }
  AvroMainForm1.ApplyPendingANSISwitchRevert;

  Self.Close;
end;

procedure TfrmEncodingWarning.Button2Click(Sender: TObject);
begin
  OutputIsBijoy := 'YES';
  if CheckBox_ShowWarning.Checked then
    ShowOutputwarning := 'YES'
  else
    ShowOutputwarning := 'NO';

  { Confirm the pending ANSI switch (no revert). }
  AvroMainForm1.PendingANSISwitchClear;

  AvroMainForm1.RefreshSettings;
  Self.Close;
end;

procedure TfrmEncodingWarning.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  { If the form is closed via X / Alt-F4 while a pending ANSI switch is
    in progress, treat it as a cancel and revert. }
  AvroMainForm1.ApplyPendingANSISwitchRevert;

  Action := caFree;
  frmEncodingWarning := nil;
end;

procedure TfrmEncodingWarning.FormCreate(Sender: TObject);
begin
  DisableCloseButton(Self.Handle);
  TOPMOST(Self.Handle);
end;

end.
