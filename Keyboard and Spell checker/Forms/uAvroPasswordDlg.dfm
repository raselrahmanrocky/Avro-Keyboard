object frmAvroPasswordDlg: TfrmAvroPasswordDlg
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Enter Encryption Password'
  ClientHeight = 130
  ClientWidth = 360
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnShow = FormShow
  TextHeight = 15
  object lblPrompt: TLabel
    Left = 16
    Top = 16
    Width = 184
    Height = 15
    Caption = 'Password:'
  end
  object edtPassword: TEdit
    Left = 16
    Top = 36
    Width = 328
    Height = 23
    PasswordChar = '*'
    TabOrder = 0
  end
  object chkShowPassword: TCheckBox
    Left = 16
    Top = 66
    Width = 120
    Height = 17
    Caption = 'Show password'
    TabOrder = 1
    OnClick = chkShowPasswordClick
  end
  object btnOK: TButton
    Left = 160
    Top = 94
    Width = 90
    Height = 25
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 2
  end
  object btnCancel: TButton
    Left = 260
    Top = 94
    Width = 90
    Height = 25
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 3
  end
end
