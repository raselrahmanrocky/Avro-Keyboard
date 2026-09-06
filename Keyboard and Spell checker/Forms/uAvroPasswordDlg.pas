{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroPasswordDlg;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls;

type
  TfrmAvroPasswordDlg = class(TForm)
    lblPrompt: TLabel;
    edtPassword: TEdit;
    chkShowPassword: TCheckBox;
    btnOK: TButton;
    btnCancel: TButton;
    procedure chkShowPasswordClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

function ShowPasswordDialog(out APassword: AnsiString): Boolean;

var
  frmAvroPasswordDlg: TfrmAvroPasswordDlg;

implementation

{$R *.dfm}

function ShowPasswordDialog(out APassword: AnsiString): Boolean;
var
  Dlg: TfrmAvroPasswordDlg;
begin
  APassword := '';
  Dlg := TfrmAvroPasswordDlg.Create(Application);
  try
    // Stay above the always-on-top TopBar so the prompt is never hidden.
    Dlg.FormStyle := fsStayOnTop;
    // The DFM centers the dialog on the main form, which Avro Keyboard parks
    // far off-screen - center on the screen instead so the prompt is ALWAYS
    // visible (otherwise the modal dialog blocks the whole app invisibly).
    Dlg.Position := poScreenCenter;
    Result := Dlg.ShowModal = mrOk;
    if Result then
      APassword := AnsiString(Dlg.edtPassword.Text);
  finally
    Dlg.Free;
  end;
end;

{ TfrmAvroPasswordDlg }

procedure TfrmAvroPasswordDlg.chkShowPasswordClick(Sender: TObject);
begin
  if chkShowPassword.Checked then
    edtPassword.PasswordChar := #0
  else
    edtPassword.PasswordChar := '*';
end;

procedure TfrmAvroPasswordDlg.FormShow(Sender: TObject);
begin
  edtPassword.SetFocus;
  edtPassword.SelectAll;
end;

end.
