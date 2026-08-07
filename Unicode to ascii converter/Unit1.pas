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
  clsBijoy2000ToUnicode,
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

  // Fully custom-painted drop-down used to pick the ANSI mapping version.
  // The face (rounded border, Bangla glyph bullet, chevron arrow and live
  // hover / press / focus states) is drawn from scratch in PaintFace so it
  // matches the rounded-panel look of the rest of the form.
  TAnsiVersionCombo = class(StdCtrls.TComboBox)
  private
    FHovered: Boolean;
    FPressed: Boolean;
    FActive: Boolean;  // drop-down list is open
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMLButtonDown(var Message: TWMLButtonDown); message WM_LBUTTONDOWN;
    procedure WMLButtonUp(var Message: TWMLButtonUp); message WM_LBUTTONUP;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure PaintFace(DC: HDC);
  public
    procedure SetDropDownActive(const Value: Boolean);
  end;

  TForm1 = class(TForm)
    MEMO1: TRichEdit;
    MEMO2: TRichEdit;
    MEMO1Panel: TRoundedPanel;
    MEMO2Panel: TRoundedPanel;
    Label1: TLabel;
    Button1: TButton;
    Button2: TButton;
    LabelAnsi: TLabel;
    cbAnsiVersion: TAnsiVersionCombo;
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
    procedure Button2Click(Sender: TObject);
    procedure cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure cbAnsiVersionChange(Sender: TObject);
    procedure cbAnsiVersionDropDown(Sender: TObject);
    procedure cbAnsiVersionCloseUp(Sender: TObject);
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
    FBijoyToUni: TBijoy2000ToUnicode;
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
{ Small colour helpers shared by the mapping picker                             }
{ =============================================================================== }

// Accent colour used across the mapping picker (warm amber, matches the app)
const
  AccentColor = $00E67E22;

// Returns the effective colour for the current Windows theme
function SysColor(AColor: TColor): TColor;
begin
  if StyleServices.Enabled then
    Result := StyleServices.GetSystemColor(AColor)
  else
    Result := ColorToRGB(AColor);
end;

// Blends Percent2% (0..100) of C2 into C1
function MixColor(C1, C2: TColor; Percent2: Integer): TColor;
var
  R1, G1, B1, R2, G2, B2: Integer;
begin
  if Percent2 <= 0 then
    Exit(C1);
  if Percent2 >= 100 then
    Exit(C2);
  R1 := GetRValue(ColorToRGB(C1));
  G1 := GetGValue(ColorToRGB(C1));
  B1 := GetBValue(ColorToRGB(C1));
  R2 := GetRValue(ColorToRGB(C2));
  G2 := GetGValue(ColorToRGB(C2));
  B2 := GetBValue(ColorToRGB(C2));
  Result := RGB(R1 + (R2 - R1) * Percent2 div 100,
                G1 + (G2 - G1) * Percent2 div 100,
                B1 + (B2 - B1) * Percent2 div 100);
end;

// True when AText is the mapping currently in effect
function IsCheckedMapping(const AText: string): Boolean;
begin
  Result := SameText(AnsiVersion, AText) or
            ((AnsiVersion = '') and SameText(AText, 'Default'));
end;

// Draws the Bangla glyph bullet (the letter "ক" in the app's own ANSI font)
// centred inside ARect. NOTE: the font is selected into the DC eagerly by
// TCanvas whenever a font property changes, so the raw DrawText call below
// always uses the freshly configured font - keep the two together.
procedure DrawAnsiGlyphBullet(C: TCanvas; const ARect: TRect; AColor: TColor);
var
  Glyph: string;
  R: TRect;
begin
  Glyph := #$0995; // ক
  C.Font.Name := 'Kalpurush ANSI';
  C.Font.Charset := ANSI_CHARSET;
  C.Font.Size := 10;
  C.Font.Style := [];
  C.Font.Color := AColor;
  C.Brush.Style := bsClear;
  R := ARect; // DrawText needs a var rect
  DrawText(C.Handle, PChar(Glyph), Length(Glyph), R,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
end;

{ =============================================================================== }
{ TAnsiVersionCombo - custom-painted mapping picker face                        }
{ =============================================================================== }

procedure TAnsiVersionCombo.CMMouseEnter(var Message: TMessage);
begin
  FHovered := True;
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.CMMouseLeave(var Message: TMessage);
begin
  FHovered := False;
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.WMLButtonDown(var Message: TWMLButtonDown);
begin
  FPressed := True;
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.WMLButtonUp(var Message: TWMLButtonUp);
begin
  FPressed := False;
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.WMSetFocus(var Message: TWMSetFocus);
begin
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.WMKillFocus(var Message: TWMKillFocus);
begin
  Invalidate;
  inherited;
end;

procedure TAnsiVersionCombo.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // The whole face is repainted every time - no background erasing needed
  Message.Result := 1;
end;

procedure TAnsiVersionCombo.SetDropDownActive(const Value: Boolean);
begin
  FActive := Value;
  if not Value then
    FPressed := False;
  Invalidate;
end;

procedure TAnsiVersionCombo.WMPaint(var Message: TWMPaint);
var
  DC, MemDC: HDC;
  PS: TPaintStruct;
  Bmp, Old: HBITMAP;
begin
  // Paint requests that carry an explicit DC (e.g. WM_PRINT) get the same
  // custom face, drawn straight into the supplied DC.
  if Message.DC <> 0 then
  begin
    PaintFace(Message.DC);
    Exit;
  end;

  // Double-buffered: draw the whole face into a memory bitmap, then blit,
  // so the hover / focus repaints never flicker.
  DC := BeginPaint(Handle, PS);
  try
    MemDC := CreateCompatibleDC(DC);
    Bmp := CreateCompatibleBitmap(DC, Width, Height);
    Old := SelectObject(MemDC, Bmp);
    try
      PaintFace(MemDC);
      BitBlt(DC, 0, 0, Width, Height, MemDC, 0, 0, SRCCOPY);
    finally
      SelectObject(MemDC, Old);
      DeleteObject(Bmp);
      DeleteDC(MemDC);
    end;
  finally
    EndPaint(Handle, PS);
  end;
end;

procedure TAnsiVersionCombo.PaintFace(DC: HDC);
var
  C: TCanvas;
  R, TextR, GlyphR: TRect;
  Bg, PanelBg, BorderC, TextC, BulletC: TColor;
  S: string;
  Cx, Cy: Integer;
  Pts: array[0..2] of TPoint;
begin
  C := TCanvas.Create;
  try
    C.Handle := DC;
    R := ClientRect;

    // ---- palette -------------------------------------------------------------
    Bg := SysColor(clWindow);
    if Enabled and (FHovered or FPressed or FActive) then
      Bg := MixColor(Bg, AccentColor, IfThen(FPressed or FActive, 16, 9));

    if Enabled and (FHovered or FPressed or FActive or Focused) then
      BorderC := AccentColor
    else
      BorderC := SysColor(clBtnShadow);

    TextC := SysColor(clWindowText);
    BulletC := AccentColor;
    if not Enabled then
    begin
      Bg := SysColor(clBtnFace);
      BorderC := SysColor(clBtnShadow);
      TextC := SysColor(clGrayText);
      BulletC := SysColor(clGrayText);
    end;
    PanelBg := SysColor(clBtnFace);

    // ---- rounded face --------------------------------------------------------
    C.Brush.Color := Bg;
    C.Brush.Style := bsSolid;
    C.Pen.Style := psClear;
    C.FillRect(R);

    // Fake the rounded corners: paint the four corner squares with the colour
    // of the panel behind, so the round-rect outline reads as the control shape.
    C.Brush.Color := PanelBg;
    C.FillRect(Rect(R.Left, R.Top, R.Left + 6, R.Top + 6));
    C.FillRect(Rect(R.Right - 6, R.Top, R.Right, R.Top + 6));
    C.FillRect(Rect(R.Left, R.Bottom - 6, R.Left + 6, R.Bottom));
    C.FillRect(Rect(R.Right - 6, R.Bottom - 6, R.Right, R.Bottom));

    C.Brush.Style := bsClear;
    C.Pen.Style := psSolid;
    C.Pen.Color := BorderC;
    C.Pen.Width := 1;
    C.RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 10, 10);

    // ---- Bangla glyph bullet (the letter "ক" in the app's own ANSI font) -----
    GlyphR := Rect(R.Left + 7, R.Top + 3, R.Left + 23, R.Bottom - 3);
    DrawAnsiGlyphBullet(C, GlyphR, BulletC);

    // ---- mapping name ----------------------------------------------------------
    C.Font := Self.Font;
    C.Font.Color := TextC;
    C.Font.Style := [];
    S := Text;
    if S = '' then
      S := 'Default';
    TextR := Rect(R.Left + 27, R.Top, R.Right - 24, R.Bottom);
    DrawText(C.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

    // ---- chevron arrow (flips up while the list is open) ------------------------
    Cx := R.Right - 16;
    Cy := R.Top + R.Height div 2;
    C.Pen.Color := AccentColor;
    C.Pen.Width := 1;
    C.Pen.Style := psSolid;
    C.Brush.Color := AccentColor;
    C.Brush.Style := bsSolid;
    if FActive then
    begin
      Pts[0] := Point(Cx - 4, Cy + 2);
      Pts[1] := Point(Cx + 4, Cy + 2);
      Pts[2] := Point(Cx, Cy - 3);
    end
    else
    begin
      Pts[0] := Point(Cx - 4, Cy - 2);
      Pts[1] := Point(Cx + 4, Cy - 2);
      Pts[2] := Point(Cx, Cy + 3);
    end;
    C.Polygon(Pts);
  finally
    C.Free;
  end;
end;

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
  cbAnsiVersion.Invalidate;
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
  Button2.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO2.Clear;
  Application.ProcessMessages;
  try
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
      Application.ProcessMessages;
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
  finally
    Progress.Visible := False;
    MEMO1.Enabled := True;
    MEMO2.Enabled := True;
    Button1.Enabled := True;
    Button2.Enabled := True;
  end;
end;

{ =============================================================================== }

procedure TForm1.Button2Click(Sender: TObject);
var
  Src, OutText, EOL, Segment: string;
  P, Q, TotalLen: Integer;
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Button2.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO1.Clear;
  Application.ProcessMessages;
  try
    // Same segment splitting as Button1Click (see the note there): only
    // real CR/LF line breaks become separate paragraphs.
    Src := MEMO2.Text;
    TotalLen := Length(Src);
    OutText := '';
    P := 1;
    while P <= TotalLen do
    begin
      Q := P;
      while (Q <= TotalLen) and not CharInSet(Src[Q], [#13, #10]) do
        Inc(Q);

      Segment := Copy(Src, P, Q - P);
      OutText := OutText + FBijoyToUni.Convert(Segment);

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
      Application.ProcessMessages;
    end;
    // Unicode output starts in Siyam Rupali
    MEMO1.DefAttributes.Name := MEMO1.Font.Name;
    MEMO1.DefAttributes.Size := MEMO1.Font.Size;
    MEMO1.DefAttributes.Charset := MEMO1.Font.Charset;

    MEMO1.Text := OutText;

    // Force Siyam Rupali over the whole text
    MEMO1.SelectAll;
    MEMO1.SelAttributes.Name := MEMO1.Font.Name;
    MEMO1.SelAttributes.Size := MEMO1.Font.Size;
    MEMO1.SelAttributes.Charset := MEMO1.Font.Charset;
    MEMO1.SelLength := 0;

    MakeTextJustified(MEMO1);
  finally
    Progress.Visible := False;
    MEMO1.Enabled := True;
    MEMO2.Enabled := True;
    Button1.Enabled := True;
    Button2.Enabled := True;
  end;
end;

{ =============================================================================== }

procedure TForm1.PopulateAnsiVersionsCombo;
var
  SR: TSearchRec;
  Versions: TStringList;
  I: Integer;
begin
  cbAnsiVersion.Items.BeginUpdate;
  try
    cbAnsiVersion.Items.Clear;

    // Built-in mapping always stays first
    cbAnsiVersion.Items.Add('Default');

    // Custom mappings, collected and sorted alphabetically
    Versions := TStringList.Create;
    try
      Versions.Sorted := True;
      Versions.Duplicates := dupIgnore;
      Versions.CaseSensitive := False;
      if DirectoryExists(AnsiMappingDir) and
         (FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0) then
      try
        repeat
          // Skip directories and the reserved 'Default' name
          if (SR.Attr and faDirectory <> 0) or SameText(SR.Name, 'Default.json') then
            Continue;
          Versions.Add(ChangeFileExt(SR.Name, ''));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
      for I := 0 to Versions.Count - 1 do
        cbAnsiVersion.Items.Add(Versions[I]);
    finally
      Versions.Free;
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

procedure TForm1.cbAnsiVersionDropDown(Sender: TObject);
begin
  cbAnsiVersion.SetDropDownActive(True);
end;

{ =============================================================================== }

procedure TForm1.cbAnsiVersionCloseUp(Sender: TObject);
begin
  cbAnsiVersion.SetDropDownActive(False);
end;

{ =============================================================================== }

procedure TForm1.cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Combo: TComboBox;
  Text: string;
  GlyphR, TextR: TRect;
  Bg: TColor;
  IsHover, IsChecked, IsDefault: Boolean;
begin
  Combo := TComboBox(Control);
  Text := Combo.Items[Index];
  IsHover := odSelected in State;
  IsChecked := IsCheckedMapping(Text);
  IsDefault := SameText(Text, 'Default');

  with Combo.Canvas do
  begin
    // Background: soft amber tint on hover, lighter tint on the active mapping
    if IsHover then
      Bg := MixColor(SysColor(clWindow), AccentColor, 14)
    else if IsChecked then
      Bg := MixColor(SysColor(clWindow), AccentColor, 6)
    else
      Bg := SysColor(clWindow);

    Brush.Color := Bg;
    Brush.Style := bsSolid;
    Pen.Style := psClear;
    FillRect(Rect);

    // Bangla glyph bullet (the letter "ক" in the app's own ANSI font)
    GlyphR := System.Classes.Rect(Rect.Left + 6, Rect.Top + 2,
                                  Rect.Left + 22, Rect.Bottom - 2);
    DrawAnsiGlyphBullet(Combo.Canvas, GlyphR,
      IfThen(IsChecked, AccentColor, SysColor(clWindowText)));

    // Mapping name, bold when it is the active mapping
    Font := Combo.Font;
    Font.Color := SysColor(clWindowText);
    if IsChecked then
      Font.Style := [fsBold];
    TextR := System.Classes.Rect(Rect.Left + 26, Rect.Top,
                                 Rect.Right - 6, Rect.Bottom);
    DrawText(Handle, PChar(Text), Length(Text), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

    // Hairline separator below the built-in Default entry
    if IsDefault and (Index < Combo.Items.Count - 1) then
    begin
      Pen.Color := MixColor(SysColor(clBtnShadow), SysColor(clWindow), 45);
      Pen.Style := psSolid;
      Pen.Width := 1;
      MoveTo(Rect.Left + 8, Rect.Bottom - 1);
      LineTo(Rect.Right - 8, Rect.Bottom - 1);
    end;
  end;
end;

{ =============================================================================== }

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FUniToBijoy.Free;
  FBijoyToUni.Free;
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
  FBijoyToUni := TBijoy2000ToUnicode.Create;

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