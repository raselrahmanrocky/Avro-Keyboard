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
  uRoundedPanel;

type
  TForm1 = class(TForm)
    MEMO1: TRichEdit;
    MEMO2: TRichEdit;
    MEMO1Panel: TRoundedPanel;
    MEMO2Panel: TRoundedPanel;
    Label1: TLabel;
    Button1: TButton;
    Progress: TProgressBar;
    Label8: TLabel;
    Label_OmicronLab: TLabel;
    Label4: TLabel;
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
  MEMO2.Text := OutText;
  MakeTextJustified(MEMO2);

  Progress.Visible := False;
  MEMO1.Enabled := True;
  MEMO2.Enabled := True;
  Button1.Enabled := True;
end;

{ =============================================================================== }

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FUniToBijoy.Free;
  Action := caFree;
  Form1 := nil;
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
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height
    - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    DisableAlign; // Stop extra re-aligning during resize
    try
      MEMO1Panel.Height := Round(Available * FSplitterRatio);
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
    finally
      EnableAlign;
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