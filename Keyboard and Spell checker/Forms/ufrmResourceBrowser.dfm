object frmResourceBrowser: TfrmResourceBrowser
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Resources Management'
  ClientHeight = 432
  ClientWidth = 676
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnShow = FormShow
  TextHeight = 13
  object lblHint: TLabel
    Left = 8
    Top = 8
    Width = 660
    Height = 32
    AutoSize = False
    Caption =
      'Browse the Avro Keyboard resource library. Downloaded files are ' +
      'installed into the right folder automatically - ANSI mappings a' +
      'nd skins are picked up immediately, fonts register automaticall' +
      'y.'
    WordWrap = True
  end
  object lblDestination: TLabel
    Left = 8
    Top = 409
    Width = 660
    Height = 13
    AutoSize = False
    Caption = ''
  end
  object lblItemDesc: TLabel
    Left = 184
    Top = 326
    Width = 484
    Height = 46
    AutoSize = False
    Caption = ''
    WordWrap = True
  end
  object lblStatus: TLabel
    Left = 8
    Top = 326
    Width = 168
    Height = 46
    AutoSize = False
    Caption = ''
    WordWrap = True
  end
  object lstCategories: TListBox
    Left = 8
    Top = 44
    Width = 168
    Height = 276
    ItemHeight = 13
    TabOrder = 0
    OnClick = lstCategoriesClick
  end
  object lvItems: TListView
    Left = 184
    Top = 44
    Width = 484
    Height = 276
    Checkboxes = True
    Columns = <
      item
        Caption = ''
        Width = 26
      end
      item
        Caption = 'Name'
        Width = 150
      end
      item
        Caption = 'Version'
        Width = 60
      end
      item
        Caption = 'Size'
        Width = 70
      end
      item
        Caption = 'Status'
        Width = 85
      end
      item
        Caption = 'Delete'
        Width = 60
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 1
    ViewStyle = vsReport
    OnColumnClick = lvItemsColumnClick
    OnItemChecked = lvItemsItemChecked
    OnMouseUp = lvItemsMouseUp
    OnSelectItem = lvItemsSelectItem
  end
  object pbProgress: TProgressBar
    Left = 282
    Top = 385
    Width = 306
    Height = 15
    Max = 100
    TabOrder = 2
    Visible = False
  end
  object btnDownload: TButton
    Left = 184
    Top = 380
    Width = 90
    Height = 25
    Caption = '&Download'
    TabOrder = 3
    OnClick = btnDownloadClick
  end
  object btnClose: TButton
    Left = 596
    Top = 380
    Width = 72
    Height = 25
    Cancel = True
    Caption = 'Close'
    TabOrder = 4
    OnClick = btnCloseClick
  end
end
