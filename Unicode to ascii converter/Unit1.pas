{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit Unit1;

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
  Menus,
  Clipbrd,
  StdCtrls,
  clsUnicodeToBijoy2000,
  ComCtrls,
  ExtCtrls,
  Vcl.AppEvnts,
  uRoundedPanel,
  Math,
  StrUtils;

type
  // Interceptor class to stop TRichEdit flicker during live resize
  TRichEdit = class(ComCtrls.TRichEdit)
  private
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  end;

  TForm1 = class(TForm)
    MEMO1: TRichEdit;
    MEMO2: TRichEdit;
    MEMO1Panel: TRoundedPanel;
    MEMO2Panel: TRoundedPanel;
    Label1: TLabel;
    Button1: TButton;
    cbAnsiVersion: TComboBox;
    Progress: TProgressBar;
    Label_OmicronLab: TLabel;
    AppEvents: TApplicationEvents;
    PanelHeader: TPanel;
    PanelButton: TPanel;
    PanelFooter: TPanel;
    Splitter1: TSplitter;
    PopupMenu1: TPopupMenu;
    Cut1: TMenuItem;
    Copy1: TMenuItem;
    Paste1: TMenuItem;
    SelectAll1: TMenuItem;
    Clear1: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure cbAnsiVersionChange(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure Label_OmicronLabClick(Sender: TObject);
    procedure AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
    procedure MemoPanelPaint(Sender: TObject);
    procedure MemoPanelMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MemoFocusChanged(Sender: TObject);
    procedure PopupMenu1Popup(Sender: TObject);
    procedure MenuCutClick(Sender: TObject);
    procedure MenuCopyClick(Sender: TObject);
    procedure MenuPasteClick(Sender: TObject);
    procedure MenuSelectAllClick(Sender: TObject);
    procedure MenuClearClick(Sender: TObject);
    procedure MEMOContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
  private
    FUniToBijoy: TUnicodeToBijoy2000;
    FSplitterRatio: Double;
    FPopupTarget: TRichEdit;

    procedure HandleThemes;
    procedure MakeTextJustified(RE: TRichEdit);
    procedure DrawRoundedFrame(APanel: TPanel; AMemo: TRichEdit);
    function PopupMemo: TRichEdit;
    function CanPasteToMemo: Boolean;
    procedure PopulateAnsiVersionsCombo;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  uFileFolderHandling,
  WindowsDarkMode,
  Winapi.RichEdit,
  Themes;

{ =============================================================================== }

procedure TRichEdit.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Suppress unnecessary background erasing of RichEdit to smooth live resize
  Message.Result := 1;
end;

{ =============================================================================== }

procedure TForm1.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // Set WS_CLIPCHILDREN on the form so child controls stay smooth while resizing
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

{ =============================================================================== }

procedure TForm1.DrawRoundedFrame(APanel: TPanel; AMemo: TRichEdit);
var
  R: TRect;
  Bg, BorderC: TColor;
begin
  if StyleServices.Enabled then
  begin
    Bg := StyleServices.GetSystemColor(clWindow);
    BorderC := StyleServices.GetSystemColor(clBtnShadow);
  end
  else
  begin
    Bg := clWindow;
    BorderC := clBtnShadow;
  end;

  R := APanel.ClientRect;
  InflateRect(R, -4, -4);

  with TRoundedPanel(APanel).Surface do
  begin
    Brush.Color := Bg;
    Brush.Style := bsSolid;
    Pen.Style := psClear;
    RoundRect(R.Left, R.Top, R.Right, R.Bottom, 12, 12);

    Brush.Style := bsClear;
    Pen.Style := psSolid;
    Pen.Color := BorderC;
    Pen.Width := 1;
    RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 12, 12);

    if AMemo.Focused then
    begin
      InflateRect(R, -2, -2);
      Pen.Style := psDot;
      Pen.Color := StyleServices.GetSystemColor(clWindowText);
      RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 8, 8);
    end;
  end;
end;

{ =============================================================================== }

procedure TForm1.MemoPanelPaint(Sender: TObject);
begin
  if Sender = MEMO1Panel then
    DrawRoundedFrame(MEMO1Panel, MEMO1)
  else if Sender = MEMO2Panel then
    DrawRoundedFrame(MEMO2Panel, MEMO2);
end;

{ =============================================================================== }

procedure TForm1.MemoPanelMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Sender = MEMO1Panel then
    MEMO1.SetFocus
  else if Sender = MEMO2Panel then
    MEMO2.SetFocus;
end;

{ =============================================================================== }

procedure TForm1.MemoFocusChanged(Sender: TObject);
begin
  if Sender = MEMO1 then
    MEMO1Panel.Invalidate
  else if Sender = MEMO2 then
    MEMO2Panel.Invalidate;
end;

{ =============================================================================== }

function TForm1.PopupMemo: TRichEdit;
begin
  if FPopupTarget <> nil then
    Result := FPopupTarget
  else if MEMO1.Focused then
    Result := MEMO1
  else if MEMO2.Focused then
    Result := MEMO2
  else
    Result := nil;
end;

{ =============================================================================== }

function TForm1.CanPasteToMemo: Boolean;
begin
  Result := Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT);
end;

{ =============================================================================== }

procedure TForm1.MEMOContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  if Sender is TRichEdit then
    FPopupTarget := TRichEdit(Sender);
end;

{ =============================================================================== }

procedure TForm1.PopupMenu1Popup(Sender: TObject);
var
  M: TRichEdit;
begin
  M := PopupMemo;
  Cut1.Enabled := (M <> nil) and (M.SelLength > 0);
  Copy1.Enabled := Cut1.Enabled;
  Paste1.Enabled := (M <> nil) and CanPasteToMemo;
  SelectAll1.Enabled := (M <> nil) and (Length(M.Text) > 0);
  Clear1.Enabled := SelectAll1.Enabled;
end;

{ =============================================================================== }

procedure TForm1.MenuCutClick(Sender: TObject);
begin
  if PopupMemo <> nil then
    PopupMemo.CutToClipboard;
end;

procedure TForm1.MenuCopyClick(Sender: TObject);
begin
  if PopupMemo <> nil then
    PopupMemo.CopyToClipboard;
end;

procedure TForm1.MenuPasteClick(Sender: TObject);
begin
  if (PopupMemo <> nil) and CanPasteToMemo then
    PopupMemo.PasteFromClipboard;
end;

procedure TForm1.MenuSelectAllClick(Sender: TObject);
begin
  if PopupMemo <> nil then
    PopupMemo.SelectAll;
end;

procedure TForm1.MenuClearClick(Sender: TObject);
begin
  if PopupMemo <> nil then
    PopupMemo.Clear;
end;

{ =============================================================================== }

procedure TForm1.MakeTextJustified(RE: TRichEdit);
var
  ParaFormat: PARAFORMAT2;
begin
  FillChar(ParaFormat, SizeOf(ParaFormat), 0);
  ParaFormat.cbSize := SizeOf(ParaFormat);
  ParaFormat.dwMask := PFM_ALIGNMENT;
  ParaFormat.wAlignment := PFA_JUSTIFY;
  RE.SelectAll;
  SendMessage(RE.Handle, EM_SETPARAFORMAT, 0, LPARAM(@ParaFormat));
  RE.SelLength := 0;
end;

{ =============================================================================== }

procedure TForm1.HandleThemes;
begin
  SetAppropriateThemeMode('Windows10 Dark', 'Windows10');
  MEMO1.Color := StyleServices.GetSystemColor(clWindow);
  MEMO1.Font.Color := StyleServices.GetSystemColor(clWindowText);
  MEMO2.Color := StyleServices.GetSystemColor(clWindow);
  MEMO2.Font.Color := StyleServices.GetSystemColor(clWindowText);
  MEMO1Panel.Invalidate;
  MEMO2Panel.Invalidate;
end;

{ =============================================================================== }

procedure TForm1.AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
begin
  if SameText('ImmersiveColorSet', string(Section)) then
    HandleThemes;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  Src, OutText, EOL, Segment: string;
  P, Q, TotalLen: Integer;
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO2.Clear;
  application.ProcessMessages;

  // NOTE: MEMO1.Lines must NOT be used here. With WordWrap enabled, Windows
  // counts soft-wrapped (visual) lines as separate lines, which would make
  // each wrapped segment a new paragraph in the output. Split the raw text
  // on real line breaks (CR/LF) only, so only Enter-pressed lines become
  // separate paragraphs.
  Src := MEMO1.Text;
  TotalLen := Length(Src);
  OutText := '';
  P := 1;
  while P <= TotalLen do
  begin
    Q := P;
    while (Q <= TotalLen) and not CharInSet(Src[Q], [#13, #10]) do
      Inc(Q);

    Segment := Copy(Src, P, Q - P);
    OutText := OutText + FUniToBijoy.Convert(Segment);

    if Q <= TotalLen then
    begin
      EOL := Src[Q];
      Inc(Q);
      if (EOL = #13) and (Q <= TotalLen) and (Src[Q] = #10) then
      begin
        EOL := EOL + #10;
        Inc(Q);
      end;
      OutText := OutText + EOL;
    end;

    P := Q;
    Progress.Position := (P * 100) div (TotalLen + 1);
    application.ProcessMessages;
  end;
  // Preset the default font for the ANSI preview so that every new
  // run of text starts in Kalpurush ANSI
  MEMO2.DefAttributes.Name := MEMO2.Font.Name;
  MEMO2.DefAttributes.Size := MEMO2.Font.Size;
  MEMO2.DefAttributes.Charset := MEMO2.Font.Charset;

  MEMO2.Text := OutText;

  // Force the selected font (Kalpurush ANSI) over the whole text so that
  // no part is shown in another font (in its English form)
  MEMO2.SelectAll;
  MEMO2.SelAttributes.Name := MEMO2.Font.Name;
  MEMO2.SelAttributes.Size := MEMO2.Font.Size;
  MEMO2.SelAttributes.Charset := MEMO2.Font.Charset;
  MEMO2.SelLength := 0;

  MakeTextJustified(MEMO2);

  Progress.Visible := False;
  MEMO1.Enabled := True;
  MEMO2.Enabled := True;
  Button1.Enabled := True;
end;

{ =============================================================================== }

procedure TForm1.PopulateAnsiVersionsCombo;
var
  SR: TSearchRec;
  FileTitle: string;
begin
  cbAnsiVersion.Items.BeginUpdate;
  try
    cbAnsiVersion.Items.Clear;

    // Always offer the built-in Default mapping first
    cbAnsiVersion.Items.Add('Default');

    if DirectoryExists(AnsiMappingDir) then
      if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0 then
      begin
        try
          repeat
            // Skip directories and the reserved 'Default' name
            if (SR.Attr and faDirectory <> 0) or SameText(SR.Name, 'Default.json') then
              Continue;

            FileTitle := ChangeFileExt(SR.Name, '');
            cbAnsiVersion.Items.Add(FileTitle);
          until FindNext(SR) <> 0;
        finally
          FindClose(SR);
        end;
      end;
  finally
    cbAnsiVersion.Items.EndUpdate;
  end;
end;

{ =============================================================================== }

procedure TForm1.cbAnsiVersionChange(Sender: TObject);
var
  VerName, ErrMsg: string;
begin
  VerName := cbAnsiVersion.Text;
  if VerName = '' then
    Exit;

  if not TrySetAnsiVersion(VerName, ErrMsg) then
    MessageDlg('Failed to load ANSI mapping: ' + ErrMsg, mtError, [mbOK], 0);
end;

{ =============================================================================== }

procedure TForm1.cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Combo: TComboBox;
  Text: string;
  BgColor, TextColor, AccentColor: TColor;
  IsSelected, IsChecked: Boolean;
  RadioRect: TRect;
begin
  Combo := TComboBox(Control);
  Text := Combo.Items[Index];
  IsSelected := odSelected in State;
  IsChecked := SameText(AnsiVersion, Text) or
              ((AnsiVersion = '') and (Text = 'Default'));

  // ১. ডার্ক/লাইট থিম অনুযায়ী কালার সেটআপ
  if StyleServices.Enabled then
  begin
    if IsSelected then
      BgColor := StyleServices.GetSystemColor(clHighlight)
    else
      BgColor := StyleServices.GetSystemColor(clWindow);

    TextColor := StyleServices.GetSystemColor(
      IfThen(IsSelected, clHighlightText, clWindowText));
    AccentColor := StyleServices.GetSystemColor(clHighlight);
  end
  else
  begin
    if IsSelected then
      BgColor := $00E67E22 // Modern Accent Color (Blue/Orange)
    else
      BgColor := clWindow;

    TextColor := IfThen(IsSelected, clWhite, clBlack);
    AccentColor := $00E67E22;
  end;

  // ২. আইটেম ব্যাকগ্রাউন্ড ড্র করা
  Combo.Canvas.Brush.Color := BgColor;
  Combo.Canvas.Brush.Style := bsSolid;
  Combo.Canvas.FillRect(Rect);

  // ৩. রেডিও বাটন সাইন (Circle Indicator) ড্র করা
  RadioRect := System.Classes.Rect(Rect.Left + 6, Rect.Top + (Rect.Height - 12) div 2,
                                   Rect.Left + 18, Rect.Top + (Rect.Height + 12) div 2);

  Combo.Canvas.Pen.Color := IfThen(IsSelected, TextColor, clGray);
  Combo.Canvas.Brush.Style := bsClear;
  Combo.Canvas.Ellipse(RadioRect); // আউটার সার্কেল

  if IsChecked then
  begin
    // ইনার সিলেক্টেড ডট (Radio Dot)
    InflateRect(RadioRect, -3, -3);
    Combo.Canvas.Brush.Color := IfThen(IsSelected, TextColor, AccentColor);
    Combo.Canvas.Brush.Style := bsSolid;
    Combo.Canvas.Pen.Style := psClear;
    Combo.Canvas.Ellipse(RadioRect);
  end;

  // ৪. টেক্সট ড্র করা
  Combo.Canvas.Brush.Style := bsClear;
  Combo.Canvas.Font := Combo.Font;
  Combo.Canvas.Font.Color := TextColor;
  Combo.Canvas.TextOut(Rect.Left + 26, Rect.Top + (Rect.Height - Combo.Canvas.TextHeight(Text)) div 2, Text);
end;

{ =============================================================================== }

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FUniToBijoy.Free;
  Action := caFree;
  Form1 := nil;
end;

{ =============================================================================== }

procedure TForm1.FormDestroy(Sender: TObject);
begin
  // No manual cleanup needed here; cbAnsiVersion is owned by the form.
end;

{ =============================================================================== }

procedure TForm1.FormCreate(Sender: TObject);
begin
  HandleThemes;
  DoubleBuffered := True;
  
  // Keep DoubleBuffered on to stop panel flickering
  PanelHeader.DoubleBuffered := True;
  PanelButton.DoubleBuffered := True;
  PanelFooter.DoubleBuffered := True;

  FSplitterRatio := MEMO1Panel.Height /
    (ClientHeight - PanelHeader.Height - PanelButton.Height - PanelFooter.Height - Splitter1.Height);
  FUniToBijoy := TUnicodeToBijoy2000.Create;

  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiMappingDir);
  PopulateAnsiVersionsCombo;

  // Sync the combo selection with the current AnsiVersion
  cbAnsiVersion.ItemIndex := cbAnsiVersion.Items.IndexOf(AnsiVersion);
  if cbAnsiVersion.ItemIndex < 0 then
    cbAnsiVersion.ItemIndex := 0;

  // DefAttributes is set so that newly pasted/typed text also
  // uses MEMO1 = Siyam Rupali and MEMO2 = Kalpurush ANSI fonts
  MEMO1.DefAttributes.Name := MEMO1.Font.Name;
  MEMO1.DefAttributes.Size := MEMO1.Font.Size;
  MEMO1.DefAttributes.Charset := MEMO1.Font.Charset;
  MEMO2.DefAttributes.Name := MEMO2.Font.Name;
  MEMO2.DefAttributes.Size := MEMO2.Font.Size;
  MEMO2.DefAttributes.Charset := MEMO2.Font.Charset;

  MakeTextJustified(MEMO1);
  MakeTextJustified(MEMO2);

  // Add internal text padding so text doesn't touch the scrollbar or border
  SendMessage(MEMO1.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(6, 6));
  SendMessage(MEMO2.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(6, 6));
  MEMO1.PopupMenu := PopupMenu1;
  MEMO2.PopupMenu := PopupMenu1;
  MEMO1.OnContextPopup := MEMOContextPopup;
  MEMO2.OnContextPopup := MEMOContextPopup;
end;

{ =============================================================================== }

procedure TForm1.FormResize(Sender: TObject);
var
  Available, NewHeight: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height
    - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    NewHeight := Round(Available * FSplitterRatio);
    if NewHeight < 80 then
    begin
      NewHeight := 80;
      FSplitterRatio := NewHeight / Available;
    end;
    if Available - NewHeight - Splitter1.Height < 80 then
    begin
      NewHeight := Available - 80 - Splitter1.Height;
      FSplitterRatio := NewHeight / Available;
    end;

    // Only re-align when the height actually changes, to avoid needless
    // re-layout and repainting on every pixel of a resize
    if MEMO1Panel.Height <> NewHeight then
    begin
      DisableAlign; // Stop extra re-aligning during resize
      try
        MEMO1Panel.Height := NewHeight;
      finally
        EnableAlign;
      end;
    end;
  end;
end;

{ =============================================================================== }

procedure TForm1.SplitterMoved(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height
    - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    FSplitterRatio := MEMO1Panel.Height / Available;
    if MEMO1Panel.Height < 80 then
    begin
      MEMO1Panel.Height := 80;
      FSplitterRatio := MEMO1Panel.Height / Available;
    end;
    if Available - MEMO1Panel.Height - Splitter1.Height < 80 then
    begin
      MEMO1Panel.Height := Available - 80 - Splitter1.Height;
      FSplitterRatio := MEMO1Panel.Height / Available;
    end;
  end;
end;

{ =============================================================================== }

procedure TForm1.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

{ =============================================================================== }

end.