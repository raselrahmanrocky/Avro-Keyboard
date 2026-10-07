object frmPhoneticOptions: TfrmPhoneticOptions
  Left = 0
  Top = 0
  BorderStyle = bsNone
  Caption = 'Avro Phonetic Options'
  ClientHeight = 511
  ClientWidth = 602
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -17
  Font.Name = 'Tahoma'
  Font.Style = []
  ParentFont = False
  PixelsPerInch = 144
  TextHeight = 21
  object Label_PhoneticTypingMode: TLabel
    Left = 24
    Top = 72
    Width = 173
    Height = 21
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Suggestion options:'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object Label1: TLabel
    Left = 84
    Top = 125
    Width = 485
    Height = 42
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      '(Avro selects first dictionary suggestion automatically. Charact' +
      'er mode is still available as option)'
    WordWrap = True
  end
  object Label4: TLabel
    Left = 84
    Top = 201
    Width = 483
    Height = 42
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      '(Avro selects character mode automatically. Dictionary hints are' +
      ' also shown if available)'
    WordWrap = True
  end
  object Label9: TLabel
    Left = 72
    Top = 384
    Width = 487
    Height = 84
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      '(Quick Tip: If you use Tab key for other purposes like moving be' +
      'tween cells in a spreadsheet program or in a table or in a datab' +
      'ase application and still want to enable this option, you can pr' +
      'ess Esc key first to close preview window.)'
    WordWrap = True
  end
  object Label12: TLabel
    Left = 84
    Top = 298
    Width = 474
    Height = 42
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      '(Note: If any autocorrect entry is found, suggestion list will s' +
      'till show up)'
    WordWrap = True
  end
  object CheckShowPrevWindow: TCheckBox
    Left = 24
    Top = 35
    Width = 218
    Height = 25
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Show Preview Window'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Tahoma'
    Font.Style = []
    ParentFont = False
    TabOrder = 0
  end
  object optPhoneticMode_Dict: TRadioButton
    Left = 48
    Top = 101
    Width = 549
    Height = 28
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Dictionary Mode is Default in suggestions'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 1
    WordWrap = True
  end
  object optPhoneticMode_Char: TRadioButton
    Left = 48
    Top = 174
    Width = 549
    Height = 30
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Character Mode is Default in suggestions'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 2
    WordWrap = True
  end
  object optPhoneticMode_OnlyChar: TRadioButton
    Left = 48
    Top = 251
    Width = 518
    Height = 37
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      'Use classic Avro Phonetic only, don'#39't show any dictionary sugges' +
      'tion'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -17
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 3
    WordWrap = True
  end
  object CheckRememberCandidate: TCheckBox
    Left = 24
    Top = 485
    Width = 573
    Height = 25
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 'Remember my choice when multiple hints are available.'
    TabOrder = 4
  end
  object CheckTabBrowsing: TCheckBox
    Left = 24
    Top = 354
    Width = 573
    Height = 26
    Margins.Left = 5
    Margins.Top = 5
    Margins.Right = 5
    Margins.Bottom = 5
    Caption = 
      'Use Tab key to browse through suggestions just like Down Arrow k' +
      'ey.'
    TabOrder = 5
  end
end
