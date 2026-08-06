object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Avro Unicode to Bijoy Converter'
  ClientHeight = 398
  ClientWidth = 665
  Color = clBtnFace
  DoubleBuffered = True
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Icon.Data = {
    0000010001001010000001002000680400001600000028000000100000002000
    0000010020000000000000040000120B0000120B000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    000070CA768F80D690BF80D690BF81D691BF80D690BF81D791BF66C063965EBC
    5700000000000000000000000000000000000000000000000000000000005DBB
    540070CE7CC37CDD99FF7CDD99FF7CDD99FF7CDD9AFF77D184DE60BB56240000
    00000000000000000000000000000000000000000000000000000000000059B6
    4A006AC76DC374D488FF74D488FF74D488FF6FCB77FC59B54929000000000000
    00000000000000000000000000000000000000000000000000000000000053B0
    3E0066C161C374CE7EFF76CF7FFF74CE7EFF74CE7EFE67BE5CA54DAA310B0000
    00000000000000000000000000000000000000000000000000009ED08F094EAB
    330068BD5CC37CCC7DFF8ACF86FD81CE81FF7CCC7DFF75CA76FE69BF5FD154AC
    385148A42506000000000000000048A4240048A4241265B9547B88C6767F49A5
    26006DBB59C374BF63DE4DA62B2F73BD5FC889CD81FF83CA7BFF78C670FF68BF
    5FFE5DB64CF15CB448C75DB449BB5DB54AD060B952F95FB54CCF47A3230F44A0
    1C0086C16E9947A01F2400000000459F1B1370B754B38FCB80FE86C878FF7AC3
    6BFF5FB64DFF54B140FF54B141FF5FB54BFE59AD3BB9439E1A170000000083BE
    6600000000000000000000000000000000003F9A100057A62E4C7EBD62AC7EBE
    64DF77BB5DE861AF41DB61AE3FA7479D19493F990F0100000000000000000000
    000000000000000000000000000000000000000000003C960900369303003A95
    05033A9505073A95050200000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    0000000000000000000000000000000000000000000000000000000000000000
    000000000000000000000000000000000000000000000000000000000000FFFF
    0000FFFF0000FFFF0000FFFF0000FFFF000080FF000080FF000081FF000080FE
    0000803800008000000090010000FC030000FF1F0000FFFF0000FFFF0000}
  Position = poScreenCenter
  Constraints.MinHeight = 346
  Constraints.MinWidth = 520
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 80
  OnResize = FormResize
  TextHeight = 13
  object PanelHeader: TPanel
    Left = 0
    Top = 0
    Width = 665
    Height = 24
    Align = alTop
    BevelOuter = bvNone
    DoubleBuffered = True
    FullRepaint = False
    ParentDoubleBuffered = False
    TabOrder = 0
    object Label1: TLabel
      Left = 8
      Top = 5
      Width = 195
      Height = 13
      Caption = 'Type or Paste Unicode Bangla text here:'
    end
  end
  object MEMO1Panel: TRoundedPanel
    Left = 8
    Top = 24
    Width = 649
    Height = 125
    Align = alTop
    AlignWithMargins = True
    Margins.Left = 8
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 0
    BevelOuter = bvNone
    DoubleBuffered = True
    FullRepaint = True
    ParentDoubleBuffered = False
    TabOrder = 1
    OnDraw = MemoPanelPaint
    OnMouseDown = MemoPanelMouseDown
    object MEMO1: TRichEdit
      Left = 10
      Top = 10
      Width = 629
      Height = 105
      Align = alClient
      AlignWithMargins = True
      Margins.Left = 10
      Margins.Top = 10
      Margins.Right = 10
      Margins.Bottom = 10
      BorderStyle = bsNone
      Font.Charset = ANSI_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Siyam Rupali'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssVertical
      TabOrder = 0
      OnEnter = MemoFocusChanged
      OnExit = MemoFocusChanged
    end
  end
  object Splitter1: TSplitter
    Left = 8
    Top = 129
    Width = 649
    Height = 5
    Cursor = crVSplit
    Align = alTop
    AlignWithMargins = True
    Margins.Left = 8
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 0
    OnMoved = SplitterMoved
  end
  object PanelButton: TPanel
    Left = 0
    Top = 134
    Width = 665
    Height = 32
    Align = alTop
    BevelOuter = bvNone
    DoubleBuffered = True
    FullRepaint = False
    ParentDoubleBuffered = False
    TabOrder = 2
    object Button1: TButton
      Left = 20
      Top = 3
      Width = 100
      Height = 25
      Caption = 'Convert'
      Default = True
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
      TabOrder = 0
      OnClick = Button1Click
    end
    object cbAnsiVersion: TComboBox
      Left = 197
      Top = 3
      Width = 160
      Height = 25
      Style = csOwnerDrawFixed
      ItemHeight = 22
      TabOrder = 1
      OnDrawItem = cbAnsiVersionDrawItem
      OnChange = cbAnsiVersionChange
    end
  end
  object MEMO2Panel: TRoundedPanel
    Left = 8
    Top = 166
    Width = 649
    Height = 207
    Align = alClient
    AlignWithMargins = True
    Margins.Left = 8
    Margins.Top = 0
    Margins.Right = 8
    Margins.Bottom = 0
    BevelOuter = bvNone
    DoubleBuffered = True
    FullRepaint = True
    ParentDoubleBuffered = False
    TabOrder = 3
    OnDraw = MemoPanelPaint
    OnMouseDown = MemoPanelMouseDown
    object MEMO2: TRichEdit
      Left = 10
      Top = 10
      Width = 629
      Height = 187
      Align = alClient
      AlignWithMargins = True
      Margins.Left = 10
      Margins.Top = 10
      Margins.Right = 10
      Margins.Bottom = 10
      BorderStyle = bsNone
      Font.Charset = ANSI_CHARSET
      Font.Color = clWindowText
      Font.Height = -21
      Font.Name = 'Kalpurush ANSI'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssVertical
      TabOrder = 0
      OnEnter = MemoFocusChanged
      OnExit = MemoFocusChanged
    end
  end
  object PanelFooter: TPanel
    Left = 0
    Top = 373
    Width = 665
    Height = 25
    Align = alBottom
    BevelOuter = bvNone
    DoubleBuffered = True
    FullRepaint = False
    ParentDoubleBuffered = False
    TabOrder = 4

    object Progress: TProgressBar
      Left = 12
      Top = 6
      Width = 645
      Height = 13
      Anchors = [akLeft, akRight, akTop]
      TabOrder = 0
      Visible = False
    end
  end
  object AppEvents: TApplicationEvents
    OnSettingChange = AppEventsSettingChange
    Left = 720
    Top = 192
  end
  object PopupMenu1: TPopupMenu
    Left = 664
    Top = 192
    OnPopup = PopupMenu1Popup
    object Cut1: TMenuItem
      Caption = 'Cut'
      OnClick = MenuCutClick
    end
    object Copy1: TMenuItem
      Caption = 'Copy'
      OnClick = MenuCopyClick
    end
    object Paste1: TMenuItem
      Caption = 'Paste'
      OnClick = MenuPasteClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object SelectAll1: TMenuItem
      Caption = 'Select All'
      OnClick = MenuSelectAllClick
    end
    object Clear1: TMenuItem
      Caption = 'Clear'
      OnClick = MenuClearClick
    end
  end
end