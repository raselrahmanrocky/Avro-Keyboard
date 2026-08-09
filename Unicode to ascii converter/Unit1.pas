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
  Registry,
  StrUtils;

type
  // Interceptor class to stop TRichEdit flicker during live resize
  TRichEdit = class(ComCtrls.TRichEdit)
  private
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  end;

  // Fully custom-painted drop-down used to pick the ANSI mapping version.
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

  // Original window procedure of the combo's inner EDIT control.
  TFontPickerEditWndProc = function(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
    lParam: LPARAM): LRESULT stdcall;

  // Editable combo (csDropDown face) whose drop-down list is owner-drawn with
  // the app's amber design language, supporting live type-to-search filtering,
  // click-to-open, and keyboard navigation (Up/Down/Enter/Escape).
  TFontPickerCombo = class(StdCtrls.TComboBox)
  private
    FFullFontList: TStringList;      // Master list of every installed font
    FActiveFont: string;             // Last committed font
    FSearchText: string;             // Search text kept while navigating
    FCursorIndex: Integer;           // Highlighted suggestion index
    FUpdating: Boolean;              // Re-entrancy guard
    FCommitting: Boolean;            // A selection is being committed
    FOpenByFilter: Boolean;          // List was opened by live filtering
    FEditHandle: HWND;               // Inner EDIT control (keyboard/mouse focus target)
    FDefEditProc: Pointer;           // Original window proc of the inner EDIT
    FClickWasOpen: Boolean;          // Drop-down was open at WM_LBUTTONDOWN
    FHovered: Boolean;
    procedure ApplyEditCentering;    // ES_LEFT + vertical centering of the edit text
    procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
    procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure PaintBorder(DC: HDC);
    procedure DrawDropDownItem(DC: HDC; Index: Integer; Rect: TRect;
      State: TOwnerDrawState);
    function ListHandle: HWND;
    function HasInputFocus: Boolean;
    procedure UpdateListCursor;
    procedure MoveCursor(Delta: Integer);
    function HandleEditKey(uMsg: UINT; wParam: WPARAM; lParam: LPARAM): Boolean;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadFonts;
    function FindFontIndex(const AName: string): Integer;
    procedure SetActiveFont(const AName: string);
    procedure HandleDropDown;
    procedure FilterList(const AText: string);
    procedure RestoreFullList;
    procedure CommitCursor(ACloseDropDown: Boolean = True);
    procedure CancelFilter;
    function FilterAndGetExact: string;
    function FontExists(const AName: string): Boolean;
    property ActiveFont: string read FActiveFont write FActiveFont;
    property IsUpdating: Boolean read FUpdating;
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
    cbFontPicker: TFontPickerCombo;
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
    procedure cbFontPickerChange(Sender: TObject);
    procedure cbFontPickerDropDown(Sender: TObject);
    procedure cbFontPickerCloseUp(Sender: TObject);
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

    procedure AppEventsMessage(var Msg: TMsg; var Handled: Boolean);
    function IsMemo1Target(AHwnd: HWND): Boolean;
    function IsMemo2Target(AHwnd: HWND): Boolean;
    procedure HandleThemes;
    procedure ApplyFontToMemo2(const FontName: string);
    procedure MakeTextJustified(RE: TRichEdit);
    procedure PasteToPopupMemo;
    procedure SaveConverterSetting(const Name, Value: string);
    function ReadConverterSettings(out AnsiVer, FontName: string): Boolean;
    procedure ConvertRtfUnicodeToBijoy(Src, Dst: TStream;
      Conv: TUnicodeToBijoy2000);
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

const
  AccentColor = $00E67E22;
  CB_GETCOMBOBOXINFO = $0164;
  EM_SETCUEBANNER = $1505;

function SysColor(AColor: TColor): TColor;
begin
  if StyleServices.Enabled then
    Result := StyleServices.GetSystemColor(AColor)
  else
    Result := ColorToRGB(AColor);
end;

function MixColor(C1, C2: TColor; Percent2: Integer): TColor;
var
  R1, G1, B1, R2, G2, B2: Integer;
begin
  if Percent2 <= 0 then Exit(C1);
  if Percent2 >= 100 then Exit(C2);
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

function IsCheckedMapping(const AText: string): Boolean;
begin
  Result := SameText(AnsiVersion, AText) or
            ((AnsiVersion = '') and SameText(AText, 'Default'));
end;

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
  R := ARect;
  DrawText(C.Handle, PChar(Glyph), Length(Glyph), R,
    DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
end;

{ =============================================================================== }
{ TAnsiVersionCombo                                                               }
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
  if Message.DC <> 0 then
  begin
    PaintFace(Message.DC);
    Exit;
  end;

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

    C.Brush.Color := Bg;
    C.Brush.Style := bsSolid;
    C.Pen.Style := psClear;
    C.FillRect(R);

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

    GlyphR := Rect(R.Left + 7, R.Top + 3, R.Left + 23, R.Bottom - 3);
    DrawAnsiGlyphBullet(C, GlyphR, BulletC);

    C.Font := Self.Font;
    C.Font.Color := TextC;
    C.Font.Style := [];
    S := Text;
    if S = '' then
      S := 'Default';
    TextR := Rect(R.Left + 27, R.Top, R.Right - 24, R.Bottom);
    DrawText(C.Handle, PChar(S), Length(S), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

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
  Message.Result := 1;
end;

procedure TForm1.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

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

  // Prevent black rectangle painting on startup before theme colors resolve
  if (Bg = clBlack) or (Bg = 0) then
    Bg := clWhite;

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

procedure TForm1.MemoPanelPaint(Sender: TObject);
begin
  if Sender = MEMO1Panel then
    DrawRoundedFrame(MEMO1Panel, MEMO1)
  else if Sender = MEMO2Panel then
    DrawRoundedFrame(MEMO2Panel, MEMO2);
end;

procedure TForm1.MemoPanelMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Sender = MEMO1Panel then
    MEMO1.SetFocus
  else if Sender = MEMO2Panel then
    MEMO2.SetFocus;
end;

procedure TForm1.MemoFocusChanged(Sender: TObject);
begin
  if Sender = MEMO1 then
    MEMO1Panel.Invalidate
  else if Sender = MEMO2 then
    MEMO2Panel.Invalidate;
end;

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

function TForm1.CanPasteToMemo: Boolean;
begin
  Result := Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT);
end;

procedure TForm1.MEMOContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  if Sender is TRichEdit then
    FPopupTarget := TRichEdit(Sender);
end;

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

procedure TForm1.PasteToPopupMemo;
var
  M: TRichEdit;
begin
  M := PopupMemo;
  if (M <> nil) and CanPasteToMemo then
  begin
    M.PasteFromClipboard;
    MakeTextJustified(M);
  end;
end;

procedure TForm1.MenuPasteClick(Sender: TObject);
begin
  PasteToPopupMemo;
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

{ Remember the ANSI mapping version / font the user picked so the next launch
  opens with the same "last used" values. Shares the AnsiVersion value with the
  main Avro Keyboard app (uRegistrySettings), so both stay in sync. }

procedure TForm1.SaveConverterSetting(const Name, Value: string);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\OmicronLab\Avro Keyboard', True) then
      Reg.WriteString(Name, Value);
  finally
    Reg.Free;
  end;
end;

function TForm1.ReadConverterSettings(out AnsiVer, FontName: string): Boolean;
var
  Reg: TRegistry;
begin
  AnsiVer := '';
  FontName := '';
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\OmicronLab\Avro Keyboard') then
    begin
      AnsiVer := Reg.ReadString('AnsiVersion');
      FontName := Reg.ReadString('ConverterAnsiFont');
    end;
  finally
    Reg.Free;
  end;
  Result := (AnsiVer <> '') or (FontName <> '');
end;

{ ---------------------------------------------------------------------------
  ConvertRtfUnicodeToBijoy

  Converts the Unicode text inside an RTF stream to Bijoy (ANSI) while leaving
  every RTF structure word intact - table definitions (\trowd, \cl..., \cellx,
  \cell, \row, \lastcell), fonts, colors, embedded binary (\bin), etc.

  Windows RichEdit stores text that does not fit the ANSI codepage as \uNNNN
  escapes (a signed 16-bit Unicode value plus \ucN fallback characters). Only
  those escapes - and literal runs of plain text - are converted; everything
  else is copied byte-for-byte, so tables pasted from Word/Excel survive the
  conversion with their cell borders and structure intact.
--------------------------------------------------------------------------- }
procedure TForm1.ConvertRtfUnicodeToBijoy(Src, Dst: TStream;
  Conv: TUnicodeToBijoy2000);
const
  // Windows-1252 mappings for bytes $80..$9F (the only range where cp1252
  // differs from the plain Unicode code point of the same value). Literal
  // bytes in an RTF stream are interpreted in the declared \ansicpg.
  Cp1252: array[0..31] of Word = (
    $20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F,
    $0090, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

  // Control words that END a text unit. Everything else (character/run
  // formatting like \f0, \fs22, \lang9, table structure like \trowd,
  // \cellx, \cl..., \tr...) is kept verbatim and does NOT split the text
  // being converted, so a Bengali word that Word splits across font switches
  // still converts as one unit with full conjunct context.
  BoundaryWords: array[0..10] of string = (
    'cell', 'lastcell', 'row', 'par', 'pard', 'line',
    'sect', 'page', 'column', 'bin', 'tab');
var
  InBuf, OutBuf, ConvBuf: TBytes;
  TextBuf: string;
  I, J, Len, UC, Fallback, Bin, WordStart, Code, InsertPos, Depth: Integer;
  B: Byte;
  W: string;
  HasParam, HasDelimSpace, IsBoundary: Boolean;
  Param, Sign: Int64;
  K: Integer;

  procedure EmitByte(B: Byte);
  begin
    SetLength(OutBuf, Length(OutBuf) + 1);
    OutBuf[Length(OutBuf) - 1] := B;
  end;

  procedure EmitStr(const S: string);
  var
    K: Integer;
  begin
    for K := 1 to Length(S) do
      EmitByte(Ord(S[K]));
  end;

  // Append converted text bytes to ConvBuf. ASCII goes out literally;
  // anything above $7F is written back as a \uNNNN escape so the exact code
  // point survives the load (a literal byte would be re-interpreted through
  // \ansicpg).
  procedure EmitConverted(const S: string);
  var
    K, V, F: Integer;
    NumStr: string;
  begin
    for K := 1 to Length(S) do
    begin
      V := Ord(S[K]);
      if V <= 127 then
      begin
        SetLength(ConvBuf, Length(ConvBuf) + 1);
        ConvBuf[Length(ConvBuf) - 1] := V;
      end
      else
      begin
        if V > 32767 then V := V - 65536;  // RTF wants a signed 16-bit value
        NumStr := '\u' + IntToStr(V);
        for F := 1 to Length(NumStr) do
        begin
          SetLength(ConvBuf, Length(ConvBuf) + 1);
          ConvBuf[Length(ConvBuf) - 1] := Ord(NumStr[F]);
        end;
        for F := 1 to UC do
        begin
          SetLength(ConvBuf, Length(ConvBuf) + 1);
          ConvBuf[Length(ConvBuf) - 1] := Ord('?');  // \ucN fallback chars
        end;
      end;
    end;
  end;

  // Convert the pending text unit ONCE and splice it into OutBuf at the
  // position where its first character began. The converter is context
  // sensitive (conjuncts, half forms, kar toggling), so the whole unit
  // - all \uNNNN escapes and literal bytes since the last boundary -
  // must be converted together.
  procedure FlushUnit;
  var
    ConvText: string;
    OldLen, NewLen, Extra, M: Integer;
  begin
    if TextBuf = '' then Exit;
    ConvText := Conv.Convert(TextBuf);
    if ConvText = '' then
    begin
      TextBuf := '';
      InsertPos := 0;
      Exit;
    end;

    SetLength(ConvBuf, 0);
    // If the byte just before the insertion point is alphanumeric (the tail
    // of a control word like \lang1093), emit a delimiter space first so the
    // text cannot merge into that control word.
    if (InsertPos > 0) and (OutBuf[InsertPos - 1] in [Ord('a')..Ord('z'),
      Ord('A')..Ord('Z'), Ord('0')..Ord('9'), Ord('-')]) then
    begin
      SetLength(ConvBuf, 1);
      ConvBuf[0] := Ord(' ');
    end;
    EmitConverted(ConvText);

    // Splice ConvBuf into OutBuf at InsertPos.
    OldLen := Length(OutBuf);
    Extra := Length(ConvBuf);
    NewLen := OldLen + Extra;
    SetLength(OutBuf, NewLen);
    for M := OldLen - 1 downto InsertPos do
      OutBuf[M + Extra] := OutBuf[M];
    for M := 0 to Extra - 1 do
      OutBuf[InsertPos + M] := ConvBuf[M];

    TextBuf := '';
    InsertPos := 0;
  end;

  // Append one decoded Unicode character to the pending text unit.
  procedure AppendChar(C: Char);
  begin
    if TextBuf = '' then
      InsertPos := Length(OutBuf);
    TextBuf := TextBuf + C;
  end;

begin
  Len := Src.Size - Src.Position;
  SetLength(InBuf, Len);
  if Len > 0 then
    Src.ReadBuffer(InBuf[0], Len);

  SetLength(OutBuf, 0);
  TextBuf := '';
  InsertPos := 0;
  UC := 1;        // \ucN - fallback characters after each \uNNNN (default 1)
  Fallback := 0;  // source fallback chars still to be skipped
  Bin := 0;       // remaining raw binary bytes to copy verbatim (\binN)

  I := 0;
  while I < Len do
  begin
    if Bin > 0 then
    begin
      // \binN payload: opaque bytes, never converted.
      EmitByte(InBuf[I]);
      Dec(Bin);
      Inc(I);
      Continue;
    end;
    if Fallback > 0 then
    begin
      // Drop the source's fallback characters - the converted text carries
      // its own \ucN fallback chars.
      Dec(Fallback);
      Inc(I);
      Continue;
    end;

    B := InBuf[I];
    if (B = Ord('{')) or (B = Ord('}')) then
    begin
      FlushUnit;
      if (B = Ord('{')) and (I + 2 < Len) and (InBuf[I + 1] = Ord('\'))
        and (InBuf[I + 2] = Ord('*')) then
      begin
        // {\*...} star destination (metadata like \mmathPr, \listtable, \pn,
        // \generator): copy verbatim - never converted, never split. Word
        // writes camelCase control words here (\mmathPr, \mmathFont13,
        // \mwrapIndent1440) whose uppercase fragments are technically text;
        // converting/splicing them glued them into junk like
        // "PrFont13Indent1440" that RichEdit then showed above the table.
        Depth := 1;
        J := I + 1;
        while (J < Len) and (Depth > 0) do
        begin
          if InBuf[J] = Ord('\') then
          begin
            if (J + 1 < Len) and ((InBuf[J + 1] = Ord('{')) or (InBuf[J + 1] = Ord('}'))) then
              Inc(J, 2)
            else if (J + 5 < Len) and (InBuf[J + 1] = Ord('b')) and (InBuf[J + 2] = Ord('i'))
              and (InBuf[J + 3] = Ord('n')) and (InBuf[J + 4] in [Ord('0')..Ord('9')]) then
            begin
              // skip the digits of a \binN payload length word
              J := J + 5;
              while (J < Len) and (InBuf[J] in [Ord('0')..Ord('9')]) do
                Inc(J);
            end
            else
              Inc(J);
          end
          else if InBuf[J] = Ord('{') then
            Inc(Depth)
          else if InBuf[J] = Ord('}') then
            Dec(Depth);
          Inc(J);
        end;
        while I < J do
        begin
          EmitByte(InBuf[I]);
          Inc(I);
        end;
        Continue;
      end;
      EmitByte(B);
      Inc(I);
      Continue;
    end;

    if (B = Ord(';')) or (B = Ord(#13)) or (B = Ord(#10)) then
    begin
      // Group/section delimiters and source line wrapping of the RTF -
      // pass through verbatim and end the pending text unit so table
      // terminators (\fonttbl/{\colortbl ...;}) cannot be pulled out of
      // place or converted (a ";" must never become an \u8212 em-dash run).
      FlushUnit;
      EmitByte(B);
      Inc(I);
      Continue;
    end;

    if B = Ord('\') then
    begin
      Inc(I);
      if I >= Len then
      begin
        FlushUnit;
        EmitByte(Ord('\'));
        Break;
      end;
      B := InBuf[I];

      if B in [Ord('a')..Ord('z')] then
      begin
        // Control word: read the letters and optional signed numeric parameter.
        WordStart := I;
        while (I < Len) and (InBuf[I] in [Ord('a')..Ord('z')]) do
          Inc(I);
        W := '';
        for J := WordStart to I - 1 do
          W := W + Char(InBuf[J]);
        HasParam := False;
        HasDelimSpace := False;
        Param := 0;
        Sign := 1;
        if (I < Len) and (InBuf[I] = Ord('-')) then
        begin
          Sign := -1;
          Inc(I);
        end;
        while (I < Len) and (InBuf[I] in [Ord('0')..Ord('9')]) do
        begin
          HasParam := True;
          Param := Param * 10 + (InBuf[I] - Ord('0'));
          Inc(I);
        end;
        Param := Param * Sign;
        // A space after a control word is its delimiter, not text - consume
        // it, but re-emit it after the control word: if it were dropped and
        // the next output byte were a letter, '\cell Hello' would collapse
        // into the single control word '\cellHello' and the text would vanish.
        if (I < Len) and (InBuf[I] = Ord(' ')) then
        begin
          Inc(I);
          HasDelimSpace := True;
        end;

        if (W = 'u') and HasParam then
        begin
          // Unicode character escape - the actual text. Queue it for
          // conversion and skip the \ucN fallback chars that follow.
          Code := Integer(Param);
          if Code < 0 then
            Inc(Code, 65536);
          AppendChar(Char(Code));
          Fallback := UC;
        end
        else if (W = 'uc') and HasParam then
          UC := Integer(Param)
        else if (W = 'bin') and HasParam then
        begin
          // Raw binary block follows: copy the payload bytes untouched.
          FlushUnit;
          EmitStr('\bin' + IntToStr(Param));
          Bin := Integer(Param);
        end
        else
        begin
          // Text-unit boundary? Convert and splice what was accumulated,
          // then copy the word itself.
          IsBoundary := False;
          for K := 0 to High(BoundaryWords) do
            if W = BoundaryWords[K] then
            begin
              IsBoundary := True;
              Break;
            end;
          if IsBoundary then
            FlushUnit;
          // Any other control word (\trowd, \cell, \row, \pard, \f0, \fs22,
          // \lang9, \cl..., ...) is structure/formatting - copy it verbatim.
          EmitByte(Ord('\'));
          EmitStr(W);
          if HasParam then
            EmitStr(IntToStr(Param));
          if HasDelimSpace then
            EmitByte(Ord(' '));
        end;
      end
      else
      begin
        // Control symbol. \'hh is a text character (decode it and queue it
        // for conversion); the rest (\*, \{, \}, \\, \~, \-, ...) is
        // structure/formatting copied verbatim.
        if B = Ord('''') then
        begin
          Inc(I);
          Code := 0;
          if (I < Len) and (InBuf[I] in [Ord('0')..Ord('9'), Ord('a')..Ord('f'),
            Ord('A')..Ord('F')]) then
          begin
            if InBuf[I] <= Ord('9') then Code := InBuf[I] - Ord('0')
            else if InBuf[I] <= Ord('F') then Code := InBuf[I] - Ord('A') + 10
            else Code := InBuf[I] - Ord('a') + 10;
            Inc(I);
          end;
          if (I < Len) and (InBuf[I] in [Ord('0')..Ord('9'), Ord('a')..Ord('f'),
            Ord('A')..Ord('F')]) then
          begin
            Code := Code * 16;
            if InBuf[I] <= Ord('9') then Code := Code + InBuf[I] - Ord('0')
            else if InBuf[I] <= Ord('F') then Code := Code + InBuf[I] - Ord('A') + 10
            else Code := Code + InBuf[I] - Ord('a') + 10;
            Inc(I);
          end;
          if Code < $80 then
            AppendChar(Char(Code))
          else if Code < $A0 then
            AppendChar(Char(Cp1252[Code - $80]))
          else
            AppendChar(Char(Code));
        end
        else
        begin
          EmitByte(Ord('\'));
          EmitByte(B);
          Inc(I);
        end;
      end;
      Continue;
    end;

    // Literal text byte - decode from cp1252 and queue for conversion.
    if B < $80 then
      AppendChar(Char(B))
    else if B < $A0 then
      AppendChar(Char(Cp1252[B - $80]))
    else
      AppendChar(Char(B));
    Inc(I);
  end;

  FlushUnit;
  if Length(OutBuf) > 0 then
    Dst.WriteBuffer(OutBuf[0], Length(OutBuf));
end;

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

procedure TForm1.AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
begin
  if SameText('ImmersiveColorSet', string(Section)) then
    HandleThemes;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  ActiveFont: string;
  MS, OutStream: TMemoryStream;
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Button2.Enabled := False;
  cbFontPicker.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO2.Clear;
  Application.ProcessMessages;
  try
    // Convert through RTF instead of plain text so tables, cell borders and
    // other formatting pasted into MEMO1 survive the Unicode-to-Bijoy pass:
    // only the text runs (\uNNNN escapes and literal runs) are converted,
    // every RTF structure word (\trowd, \cell, \row, ...) is kept intact.
    MS := TMemoryStream.Create;
    OutStream := TMemoryStream.Create;
    try
      MEMO1.Lines.SaveToStream(MS);       // SF_RTF - full document, not plain text
      MS.Position := 0;
      ConvertRtfUnicodeToBijoy(MS, OutStream, FUniToBijoy);
      OutStream.Position := 0;
      MEMO2.Lines.LoadFromStream(OutStream);
    finally
      OutStream.Free;
      MS.Free;
    end;
    Progress.Position := 100;
    Application.ProcessMessages;

    ActiveFont := cbFontPicker.ActiveFont;
    if ActiveFont = '' then
      ActiveFont := cbFontPicker.Text;
    if ActiveFont = '' then
      ActiveFont := MEMO2.Font.Name;

    MEMO2.DefAttributes.Name := ActiveFont;
    MEMO2.DefAttributes.Charset := MEMO2.Font.Charset;

    // Apply the picked ANSI font to every text run (including table cells).
    MEMO2.SelectAll;
    MEMO2.SelAttributes.Name := ActiveFont;
    MEMO2.SelAttributes.Charset := MEMO2.Font.Charset;
    MEMO2.SelLength := 0;

    MakeTextJustified(MEMO2);
  finally
    Progress.Visible := False;
    MEMO1.Enabled := True;
    MEMO2.Enabled := True;
    Button1.Enabled := True;
    Button2.Enabled := True;
    cbFontPicker.Enabled := True;
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
var
  Src, OutText, EOL, Segment: string;
  P, Q, TotalLen: Integer;
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Button2.Enabled := False;
  cbFontPicker.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO1.Clear;
  Application.ProcessMessages;
  try
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

    MEMO1.DefAttributes.Name := MEMO1.Font.Name;
    MEMO1.DefAttributes.Charset := MEMO1.Font.Charset;

    MEMO1.Text := OutText;

    MEMO1.SelectAll;
    MEMO1.SelAttributes.Name := MEMO1.Font.Name;
    MEMO1.SelAttributes.Charset := MEMO1.Font.Charset;
    MEMO1.SelLength := 0;

    MakeTextJustified(MEMO1);
  finally
    Progress.Visible := False;
    MEMO1.Enabled := True;
    MEMO2.Enabled := True;
    Button1.Enabled := True;
    Button2.Enabled := True;
    cbFontPicker.Enabled := True;
  end;
end;

procedure TForm1.PopulateAnsiVersionsCombo;
var
  SR: TSearchRec;
  Versions: TStringList;
  I: Integer;
begin
  cbAnsiVersion.Items.BeginUpdate;
  try
    cbAnsiVersion.Items.Clear;
    cbAnsiVersion.Items.Add('Default');

    Versions := TStringList.Create;
    try
      Versions.Sorted := True;
      Versions.Duplicates := dupIgnore;
      Versions.CaseSensitive := False;
      if DirectoryExists(AnsiMappingDir) and
         (FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0) then
      try
        repeat
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

procedure TForm1.cbAnsiVersionChange(Sender: TObject);
var
  VerName, ErrMsg: string;
begin
  VerName := cbAnsiVersion.Text;
  if VerName = '' then Exit;

  if not TrySetAnsiVersion(VerName, ErrMsg) then
    MessageDlg('Failed to load ANSI mapping: ' + ErrMsg, mtError, [mbOK], 0)
  else
    SaveConverterSetting('AnsiVersion', VerName);
end;

procedure TForm1.cbAnsiVersionDropDown(Sender: TObject);
begin
  cbAnsiVersion.SetDropDownActive(True);
end;

procedure TForm1.cbAnsiVersionCloseUp(Sender: TObject);
begin
  cbAnsiVersion.SetDropDownActive(False);
end;

{ =============================================================================== }
{ TFontPickerCombo: editable, owner-drawn, type-to-search font picker            }
{ =============================================================================== }

function FontPickerEditProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM): LRESULT stdcall;
var
  Combo: TFontPickerCombo;
begin
  Combo := TFontPickerCombo(GetProp(hWnd, 'AvroFontPicker'));
  if Combo = nil then
  begin
    Result := DefWindowProc(hWnd, uMsg, wParam, lParam);
    Exit;
  end;

  // Keep the text (I-beam) cursor visible over the edit control - the system
  // may fail to refresh the cursor icon on WM_SETCURSOR while the drop-down
  // list holds mouse capture, which would otherwise hide the cursor.
  if uMsg = WM_SETCURSOR then
  begin
    SetCursor(LoadCursor(0, IDC_IBEAM));
    Result := 1;
    Exit;
  end;

  // The native combo box selects all of the edit text (EM_SETSEL 0,-1) after
  // a font is committed; convert that into a deselection (-1,-1) so the picked
  // font name is never left highlighted in blue.
  if (uMsg = EM_SETSEL) and (wParam = 0) and (lParam <> 0) then
  begin
    if (GetKeyState(VK_LBUTTON) and $8000) = 0 then
    begin
      wParam := $FFFFFFFF; // WPARAM(-1) - deselect
      lParam := -1;        // LPARAM(-1)
    end;
  end;

  // Toggle-on-click state: remember whether the drop-down list was open
  // when a press began, so that same press can toggle it - open while
  // closed, close while open - exactly like the ANSI version combo.
  if (uMsg = WM_LBUTTONDOWN) or (uMsg = WM_LBUTTONDBLCLK) then
    Combo.FClickWasOpen := Combo.DroppedDown;

  if Combo.HandleEditKey(uMsg, wParam, lParam) then
  begin
    Result := 0;
    Exit;
  end;

  // Native handling runs FIRST, while the list is still in its pre-press
  // state: pressing the edit of a dropped-down combo natively closes the
  // list. Only after that, if the press started with the list closed, open
  // it right here on the button-down so the drop-down appears instantly
  // (no waiting for the mouse-up) - the same feel as the ANSI version
  // field. If it was already open, the native logic above just closed it
  // and we must not re-open it.
  Result := TFontPickerEditWndProc(Combo.FDefEditProc)(hWnd, uMsg, wParam, lParam);

  // Keep the text vertically/horizontally centered after the combo moves or
  // resizes the edit, or after its font changes.
  if (uMsg = WM_WINDOWPOSCHANGED) or (uMsg = WM_SETFONT) then
    Combo.ApplyEditCentering;

  if ((uMsg = WM_LBUTTONDOWN) or (uMsg = WM_LBUTTONDBLCLK))
    and not Combo.FClickWasOpen and not Combo.DroppedDown
    and not Combo.IsUpdating then
  begin
    Combo.HandleDropDown;
    Combo.DroppedDown := True;
  end;
end;

function TFontPickerCombo.HandleEditKey(uMsg: UINT; wParam: WPARAM;
  lParam: LPARAM): Boolean;
var
  Key: Word;
begin
  Result := False;
  if uMsg <> WM_KEYDOWN then Exit;
  Key := Word(wParam);
  case Key of
    VK_UP, VK_DOWN:
      begin
        if Items.Count > 0 then
        begin
          if not DroppedDown then
            DroppedDown := True;
          MoveCursor(IfThen(Key = VK_DOWN, 1, -1));
          Result := True;
        end;
      end;
    VK_RETURN:
      begin
        if DroppedDown or (Text <> FActiveFont) then
        begin
          CommitCursor(True);
          Result := True;
        end;
      end;
    VK_ESCAPE:
      begin
        if DroppedDown or (Text <> FActiveFont) then
        begin
          CancelFilter;
          Result := True;
        end;
      end;
  end;
end;

constructor TFontPickerCombo.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FFullFontList := TStringList.Create;
  FFullFontList.Sorted := True;
  FFullFontList.Duplicates := dupIgnore;
  FFullFontList.CaseSensitive := False;
  FCursorIndex := -1;
  AutoComplete := False;
  AutoDropDown := False;
end;

destructor TFontPickerCombo.Destroy;
begin
  FFullFontList.Free;
  inherited Destroy;
end;

procedure TFontPickerCombo.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or CBS_OWNERDRAWFIXED;
end;

procedure TFontPickerCombo.CreateWnd;
var
  Info: TComboBoxInfo;
begin
  inherited CreateWnd;
  SendMessage(Handle, CB_SETITEMHEIGHT, 0, ItemHeight);

  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if SendMessage(Handle, CB_GETCOMBOBOXINFO, 0, LPARAM(@Info)) <> 0 then
    if (Info.hwndItem <> 0) and (Info.hwndItem <> Handle) then
    begin
      FEditHandle := Info.hwndItem;
      RemoveProp(FEditHandle, 'AvroFontPicker');
      SetProp(FEditHandle, 'AvroFontPicker', THandle(Self));
      FDefEditProc := Pointer(SetWindowLongPtr(FEditHandle,
        GWLP_WNDPROC, LONG_PTR(@FontPickerEditProc)));
    end;
  ApplyEditCentering;
end;

procedure TFontPickerCombo.ApplyEditCentering;
var
  DC: HDC;
  TM: TTextMetric;
  HF: HFONT;
  OldFont: HFONT;
  CR, WR: TRect;
  ParentClient: TRect;
  ClientOrigin: TPoint;
  RelTop, NewTop, NewH: Integer;
  Style: LONG_PTR;
begin
  if FEditHandle = 0 then Exit;
  SendMessage(FEditHandle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(8, 8));
  // Horizontal alignment: the inner edit reads ES_LEFT/CENTER/RIGHT from its
  // window style at paint time. Force left alignment (ES_LEFT = 0) by clearing
  // the CENTER/RIGHT bits. The native combo already insets the edit's format
  // rectangle (~14 px on the left), so the text starts clear of the left
  // border without any extra margins.
  Style := GetWindowLongPtr(FEditHandle, GWL_STYLE);
  if (Style and (ES_CENTER or ES_RIGHT)) <> 0 then
  begin
    SetWindowLongPtr(FEditHandle, GWL_STYLE,
      Style and not (ES_CENTER or ES_RIGHT));
    InvalidateRect(FEditHandle, nil, True);
  end;

  // Vertical centering. A borderless single-line EDIT top-aligns its line box
  // and ignores EM_SETRECT/EM_SETRECTNP (those messages only affect multiline
  // edits), so the text cannot be nudged with messages. Instead, shrink the
  // edit window to the text's own bounding box (font height + internal
  // leading) and re-center it inside the combo; the still top-aligned text
  // then sits vertically centered. Re-applied whenever the edit is moved or
  // resized (WM_WINDOWPOSCHANGED) or its font changes (WM_SETFONT).
  HF := HFONT(SendMessage(FEditHandle, WM_GETFONT, 0, 0));
  if HF = 0 then HF := GetStockObject(DEFAULT_GUI_FONT);
  DC := GetDC(FEditHandle);
  try
    OldFont := SelectObject(DC, HF);
    try
      FillChar(TM, SizeOf(TM), 0);
      GetTextMetrics(DC, TM);
    finally
      SelectObject(DC, OldFont);
    end;
  finally
    ReleaseDC(FEditHandle, DC);
  end;

  Windows.GetClientRect(FEditHandle, CR);
  NewH := TM.tmHeight + TM.tmInternalLeading; // visible text box height
  if NewH < 8 then NewH := 8;                 // sanity floor
  if NewH >= CR.Bottom - 2 then Exit;         // already sized to fit the text

  Windows.GetWindowRect(FEditHandle, WR);
  Windows.GetClientRect(Handle, ParentClient);
  ClientOrigin.X := ParentClient.Left;
  ClientOrigin.Y := ParentClient.Top;
  Windows.ClientToScreen(Handle, ClientOrigin);
  RelTop := WR.Top - ClientOrigin.Y;
  NewTop := RelTop + (CR.Bottom - NewH) div 2 + 1;
  SetWindowPos(FEditHandle, 0, WR.Left - ClientOrigin.X, NewTop,
    WR.Right - WR.Left, NewH, SWP_NOZORDER or SWP_NOACTIVATE);
end;

procedure TFontPickerCombo.DestroyWnd;
begin
  if (FEditHandle <> 0) and Assigned(FDefEditProc) then
  begin
    SetWindowLongPtr(FEditHandle, GWLP_WNDPROC, LONG_PTR(FDefEditProc));
    RemoveProp(FEditHandle, 'AvroFontPicker');
    FEditHandle := 0;
    FDefEditProc := nil;
  end;
  inherited DestroyWnd;
end;

procedure TFontPickerCombo.CMMouseEnter(var Message: TMessage);
begin
  FHovered := True;
  Invalidate;
  inherited;
end;

procedure TFontPickerCombo.CMMouseLeave(var Message: TMessage);
begin
  FHovered := False;
  Invalidate;
  inherited;
end;

procedure TFontPickerCombo.WMSetFocus(var Message: TWMSetFocus);
begin
  // Focus alone (startup, Tab) must never auto-open the drop-down.
  // The list opens only on an explicit click (edit sub-class) or when
  // the user actively types a character (FilterList).
  Invalidate;
  inherited;
end;

procedure TFontPickerCombo.WMKillFocus(var Message: TWMKillFocus);
begin
  Invalidate;
  inherited;
  // Restore active font if left half-typed or empty
  if (Text = '') or not FontExists(Text) then
  begin
    FUpdating := True;
    try
      Text := FActiveFont;
      
      // ✅ ফোকাস সরার সময় যেন সিলেক্ট না হয়:
      SelStart := Length(FActiveFont);
      SelLength := 0;
    finally
      FUpdating := False;
    end;
  end;
end;

procedure TFontPickerCombo.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  Message.Result := 1;
end;

function TFontPickerCombo.HasInputFocus: Boolean;
begin
  Result := (GetFocus = Handle) or IsChild(Handle, GetFocus);
end;

procedure TFontPickerCombo.PaintBorder(DC: HDC);
var
  C: TCanvas;
  R: TRect;
  Bg, BorderC: TColor;
begin
  C := TCanvas.Create;
  try
    C.Handle := DC;
    R := ClientRect;

    Bg := SysColor(clWindow);
    if Enabled and (FHovered or Focused or HasInputFocus or DroppedDown) then
      BorderC := AccentColor
    else
      BorderC := SysColor(clBtnShadow);

    C.Brush.Color := Bg;
    C.Brush.Style := bsSolid;
    C.Pen.Style := psClear;
    C.FillRect(R);

    C.Brush.Style := bsClear;
    C.Pen.Style := psSolid;
    C.Pen.Color := BorderC;
    C.Pen.Width := 1;
    C.RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 10, 10);
  finally
    C.Free;
  end;
end;

procedure TFontPickerCombo.WMPaint(var Message: TWMPaint);
var
  DC, MemDC: HDC;
  PS: TPaintStruct;
  Bmp, Old: HBITMAP;
begin
  if Message.DC <> 0 then
  begin
    PaintBorder(Message.DC);
    Exit;
  end;

  DC := BeginPaint(Handle, PS);
  try
    MemDC := CreateCompatibleDC(DC);
    Bmp := CreateCompatibleBitmap(DC, Width, Height);
    Old := SelectObject(MemDC, Bmp);
    try
      PaintBorder(MemDC);
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

procedure TFontPickerCombo.DrawDropDownItem(DC: HDC; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
  Text: string;
  TextR: TRect;
  Bg: TColor;
  IsHover, IsActive: Boolean;
begin
  C := TCanvas.Create;
  try
    C.Handle := DC;
    Text := Items[Index];
    IsHover := odSelected in State;
    IsActive := SameText(Text, FActiveFont);

    with C do
    begin
      if IsHover then
        Bg := MixColor(SysColor(clWindow), AccentColor, 14)
      else if IsActive then
        Bg := MixColor(SysColor(clWindow), AccentColor, 6)
      else
        Bg := SysColor(clWindow);

      Brush.Color := Bg;
      Brush.Style := bsSolid;
      Pen.Style := psClear;
      FillRect(Rect);

      Font := Self.Font;
      Font.Color := SysColor(clWindowText);
      if IsActive then
        Font.Style := [fsBold]
      else
        Font.Style := [];

      TextR := System.Classes.Rect(Rect.Left + 8, Rect.Top,
                                   Rect.Right - 4, Rect.Bottom);
      DrawText(Handle, PChar(Text), Length(Text), TextR,
        DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    end;
  finally
    C.Free;
  end;
end;

function TFontPickerCombo.ListHandle: HWND;
var
  Info: TComboBoxInfo;
begin
  Result := 0;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if SendMessage(Handle, CB_GETCOMBOBOXINFO, 0, LPARAM(@Info)) <> 0 then
    Result := Info.hwndList;
end;

procedure TFontPickerCombo.UpdateListCursor;
var
  LH: HWND;
begin
  if Items.Count = 0 then Exit;
  if FCursorIndex < 0 then FCursorIndex := 0;
  if FCursorIndex >= Items.Count then FCursorIndex := Items.Count - 1;
  LH := ListHandle;
  if LH <> 0 then
    SendMessage(LH, LB_SETCURSEL, FCursorIndex, 0);
end;

procedure TFontPickerCombo.MoveCursor(Delta: Integer);
var
  SaveText: string;
  OldSelStart, OldSelLen: Integer;
begin
  if Items.Count = 0 then Exit;
  SaveText := FSearchText;
  if SaveText = '' then
    SaveText := Text;

  OldSelStart := SelStart;
  OldSelLen := SelLength;

  FCursorIndex := FCursorIndex + Delta;
  if FCursorIndex < 0 then FCursorIndex := 0;
  if FCursorIndex >= Items.Count then FCursorIndex := Items.Count - 1;

  FUpdating := True;
  try
    UpdateListCursor;
    if Text <> SaveText then
      Text := SaveText;
    SelStart := OldSelStart;
    SelLength := OldSelLen;
  finally
    FUpdating := False;
  end;
  Invalidate;
end;

function TFontPickerCombo.FindFontIndex(const AName: string): Integer;
begin
  for Result := 0 to FFullFontList.Count - 1 do
    if SameText(FFullFontList[Result], AName) then
      Exit;
  Result := -1;
end;

procedure TFontPickerCombo.LoadFonts;
begin
  FFullFontList.Assign(Screen.Fonts);
  FUpdating := True;
  try
    Items.Assign(FFullFontList);
  finally
    FUpdating := False;
  end;
end;

procedure TFontPickerCombo.SetActiveFont(const AName: string);
begin
  FActiveFont := AName;
  FUpdating := True;
  try
    Text := AName;
    // Caret at the end, no selection - avoid the blue highlight when the
    // active font is set programmatically.
    SelStart := Length(AName);
    SelLength := 0;
  finally
    FUpdating := False;
  end;
end;

procedure TFontPickerCombo.HandleDropDown;
var
  WasUpdating: Boolean;
begin
  // Always restore full list when opening via mouse click or arrow button,
  // so a previous search filter can never leak into a new open.
  FOpenByFilter := False;
  // Save/restore the guard so a nested call (e.g. FilterList's typed open
  // firing OnDropDown) never clears the caller's FUpdating while it runs.
  WasUpdating := FUpdating;
  FUpdating := True;
  try
    Items.Assign(FFullFontList);
    FSearchText := '';
    FCursorIndex := FindFontIndex(Text);
    UpdateListCursor;
  finally
    FUpdating := WasUpdating;
  end;
end;

procedure TFontPickerCombo.FilterList(const AText: string);
var
  I, OldSelStart, OldSelLen: Integer;
  MatchingFonts: TStringList;
  NeedRefresh: Boolean;
begin
  if FUpdating then Exit;

  FSearchText := AText;
  OldSelStart := SelStart;
  OldSelLen := SelLength;

  MatchingFonts := TStringList.Create;
  try
    MatchingFonts.Sorted := True;
    MatchingFonts.Duplicates := dupIgnore;
    MatchingFonts.CaseSensitive := False;

    if AText = '' then
      MatchingFonts.Assign(FFullFontList)
    else
      for I := 0 to FFullFontList.Count - 1 do
        if ContainsText(FFullFontList[I], AText) then
          MatchingFonts.Add(FFullFontList[I]);

    NeedRefresh := (MatchingFonts.Count <> Items.Count);
    if not NeedRefresh then
      for I := 0 to MatchingFonts.Count - 1 do
        if not SameText(MatchingFonts[I], Items[I]) then
        begin
          NeedRefresh := True;
          Break;
        end;

    FUpdating := True;
    try
      if NeedRefresh then
      begin
        Items.BeginUpdate;
        try
          Items.Assign(MatchingFonts);
        finally
          Items.EndUpdate;
        end;
      end;

      FCursorIndex := MatchingFonts.IndexOf(AText);
      if FCursorIndex < 0 then FCursorIndex := 0;

      if HasInputFocus and (MatchingFonts.Count > 0) and not FCommitting
        and not SameText(AText, FActiveFont) then
        if not DroppedDown then
        begin
          FOpenByFilter := True;
          DroppedDown := True;
          // Opening fires OnDropDown -> HandleDropDown, which (by design)
          // restores the full list for arrow/click opens. When the open was
          // caused by typing, re-apply the filtered subset so the very first
          // keystroke narrows the list too.
          Items.BeginUpdate;
          try
            Items.Assign(MatchingFonts);
          finally
            Items.EndUpdate;
          end;
        end;

      UpdateListCursor;

      // Keep user's exact typed string without inline auto-completing
      if Text <> AText then
        Text := AText;

      if OldSelStart <= Length(Text) then
      begin
        SelStart := OldSelStart;
        SelLength := OldSelLen;
      end;
    finally
      FUpdating := False;
    end;
  finally
    MatchingFonts.Free;
  end;
end;

procedure TFontPickerCombo.RestoreFullList;
var
  SaveText: string;
  Idx: Integer;
begin
  FOpenByFilter := False;
  SaveText := FActiveFont;
  if SaveText = '' then SaveText := Text;

  FUpdating := True;
  try
    Items.Assign(FFullFontList);
    Idx := FindFontIndex(SaveText);
    FCursorIndex := Idx;
    // Keep ItemIndex valid (>= 0) so the native combo never wipes the
    // edit text when the drop-down closes while the control is focused.
    if Idx >= 0 then
      ItemIndex := Idx;
    Text := SaveText;
    // Caret at the end, no selection - avoids the blue highlight flash when
    // the drop-down closes (which previously made the text blink as focus
    // was taken away right after).
    SelStart := Length(SaveText);
    SelLength := 0;
  finally
    FUpdating := False;
  end;
end;

procedure TFontPickerCombo.CommitCursor(ACloseDropDown: Boolean);
var
  LH: HWND;
  N: Integer;
  FontName: string;
begin
  LH := ListHandle;
  N := -1;
  if LH <> 0 then
    N := Integer(SendMessage(LH, LB_GETCURSEL, 0, 0));
  if (N >= 0) and (N < Items.Count) then
    FontName := Items[N]
  else if (FCursorIndex >= 0) and (FCursorIndex < Items.Count) then
    FontName := Items[FCursorIndex]
  else
  begin
    FontName := FSearchText;
    if FontName <> '' then
    begin
      N := FindFontIndex(FontName);
      if N >= 0 then
        FontName := FFullFontList[N];
    end;
  end;

  if FontName = '' then
    FontName := Text;
  if FontName = '' then
    FontName := FActiveFont;
  if FontName = '' then
    Exit;

  FActiveFont := FontName; // Set active font FIRST so Text is always preserved

  FCommitting := True;
  FUpdating := True;
  try
    Text := FontName;
    // Sync ItemIndex with the committed font so the native combo does not
    // clear the edit text on close (ItemIndex = -1 wipes it while focused).
    N := Items.IndexOf(FontName);
    if N >= 0 then
      ItemIndex := N;
    // Leave the caret at the end of the committed name with no selection,
    // so the text is not highlighted in blue after picking a font.
    SelStart := Length(FontName);
    SelLength := 0;
  finally
    FUpdating := False;
  end;

  if Assigned(OnChange) then
    OnChange(Self);

  if ACloseDropDown then
    DroppedDown := False;

  FSearchText := '';
  FOpenByFilter := False;
  FCommitting := False;
  Invalidate;
end;

procedure TFontPickerCombo.CancelFilter;
begin
  FUpdating := True;
  try
    Text := FActiveFont;
    // Caret at the end, no selection - no blue highlight flash.
    SelStart := Length(FActiveFont);
    SelLength := 0;
  finally
    FUpdating := False;
  end;
  if Assigned(OnChange) then
    OnChange(Self);
  DroppedDown := False;
  FSearchText := '';
  FOpenByFilter := False;
  Invalidate;
end;

function TFontPickerCombo.FilterAndGetExact: string;
var
  Idx: Integer;
begin
  Result := '';
  if FUpdating then Exit;
  FilterList(Text);
  Idx := FindFontIndex(Text);
  if (Text <> '') and (Idx >= 0) then
    Result := FFullFontList[Idx];
end;

function TFontPickerCombo.FontExists(const AName: string): Boolean;
begin
  Result := (AName <> '') and (FFullFontList.IndexOf(AName) >= 0);
end;

procedure TFontPickerCombo.WndProc(var Message: TMessage);
var
  Idx: Integer;
begin
  case Message.Msg of
    // Keep the standard arrow cursor visible over the combo face and its
    // dropped-down list - same reason as in FontPickerEditProc: the system
    // may not refresh the cursor while the list holds mouse capture.
    WM_SETCURSOR:
      begin
        SetCursor(LoadCursor(0, IDC_ARROW));
        Message.Result := 1;
        Exit;
      end;
    WM_KEYDOWN:
      begin
        if HandleEditKey(Message.Msg, Message.WParam, Message.LParam) then
        begin
          Message.Result := 0;
          Exit;
        end;
      end;
    CN_COMMAND:
      begin
        case TWMCommand(Message).NotifyCode of
          CBN_SELCHANGE:
            begin
              Message.Result := 0;
              Exit;
            end;
          CBN_SELENDOK:
            begin
              // Single mouse click or Enter key commits immediately
              if not FUpdating then
                CommitCursor(True);
              Message.Result := 0;
              Exit;
            end;
CBN_SELENDCANCEL:
            begin
              if (not FUpdating) and not FCommitting then
              begin
                if (Text = '') or (Text <> FActiveFont) then
                begin
                  FUpdating := True;
                  try
                    Text := FActiveFont;
                    Idx := Items.IndexOf(FActiveFont);
                    if Idx >= 0 then
                      ItemIndex := Idx;
                    SelStart := Length(FActiveFont);
                    SelLength := 0;
                  finally
                    FUpdating := False;
                  end;
                  FSearchText := '';
                  Invalidate;
                end;
              end;
              Message.Result := 0;
              Exit;
            end;
        end;
      end;
    CN_DRAWITEM:
      begin
        with PDrawItemStruct(Message.LParam)^ do
          if Integer(itemID) >= 0 then
            DrawDropDownItem(hDC, Integer(itemID), rcItem,
              TOwnerDrawState(LoWord(itemState)));
        Message.Result := 1;
        Exit;
      end;
    WM_LBUTTONDOWN:
      Invalidate;
    WM_LBUTTONDBLCLK:
      Invalidate;
  end;
  inherited WndProc(Message);
end;

{ =============================================================================== }
{ cbFontPicker form event handlers                                                }
{ =============================================================================== }

procedure TForm1.cbFontPickerChange(Sender: TObject);
begin
  if cbFontPicker.IsUpdating then Exit;

  // ✅ মাউসে ক্লিক বা Enter চেপে ফন্ট নিশ্চিত (Commit) করা হলেই কেবল ফন্ট অ্যাপ্লাই ও ফোকাস আউট হবে:
  if SameText(cbFontPicker.Text, cbFontPicker.ActiveFont) then
  begin
    ApplyFontToMemo2(cbFontPicker.ActiveFont);
    SaveConverterSetting('ConverterAnsiFont', cbFontPicker.ActiveFont);
    ActiveControl := nil; 
  end
  else
  begin
    // ✅ সার্চ বক্সে টাইপ করার সময় কেবল লাইভ লিস্ট ফিল্টার হবে, অটো-সিলেক্ট হবে না:
    cbFontPicker.FilterList(cbFontPicker.Text);
  end;
end;

procedure TForm1.cbFontPickerDropDown(Sender: TObject);
begin
  cbFontPicker.HandleDropDown;
end;

procedure TForm1.cbFontPickerCloseUp(Sender: TObject);
begin
  cbFontPicker.RestoreFullList;
end;

procedure TForm1.ApplyFontToMemo2(const FontName: string);
begin
  MEMO2.Font.Name := FontName;
  MEMO2.DefAttributes.Name := FontName;

  MEMO2.SelectAll;
  MEMO2.SelAttributes.Name := FontName;
  MEMO2.SelAttributes.Size := MEMO2.Font.Size;
  MEMO2.SelAttributes.Charset := MEMO2.Font.Charset;
  MEMO2.SelLength := 0;

  MakeTextJustified(MEMO2);
  cbFontPicker.ActiveFont := FontName;
end;

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

    GlyphR := System.Classes.Rect(Rect.Left + 6, Rect.Top + 2,
                                  Rect.Left + 22, Rect.Bottom - 2);
    DrawAnsiGlyphBullet(Combo.Canvas, GlyphR,
      IfThen(IsChecked, AccentColor, SysColor(clWindowText)));

    Font := Combo.Font;
    Font.Color := SysColor(clWindowText);
    if IsChecked then
      Font.Style := [fsBold];
    TextR := System.Classes.Rect(Rect.Left + 26, Rect.Top,
                                 Rect.Right - 6, Rect.Bottom);
    DrawText(Handle, PChar(Text), Length(Text), TextR,
      DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

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

function TForm1.IsMemo1Target(AHwnd: HWND): Boolean;
begin
  Result := (AHwnd <> 0) and (MEMO1 <> nil) and (MEMO1Panel <> nil) and
    ((AHwnd = MEMO1.Handle) or (AHwnd = MEMO1Panel.Handle) or IsChild(MEMO1Panel.Handle, AHwnd));
end;

function TForm1.IsMemo2Target(AHwnd: HWND): Boolean;
begin
  Result := (AHwnd <> 0) and (MEMO2 <> nil) and (MEMO2Panel <> nil) and
    ((AHwnd = MEMO2.Handle) or (AHwnd = MEMO2Panel.Handle) or IsChild(MEMO2Panel.Handle, AHwnd));
end;

procedure TForm1.AppEventsMessage(var Msg: TMsg; var Handled: Boolean);
var
  TargetWnd: HWND;
  Pt: TPoint;
  IsPickerDropped, IsAnsiDropped: Boolean;
begin
  if (Msg.message = WM_KEYDOWN) and (Msg.wParam = Ord('V'))
    and ((GetKeyState(VK_CONTROL) and $8000) <> 0)
    and (PopupMemo <> nil) and CanPasteToMemo then
  begin
    PasteToPopupMemo;
    Handled := True;
  end
  else if (Msg.message = WM_LBUTTONDOWN) or (Msg.message = WM_NCLBUTTONDOWN) then
  begin
    IsPickerDropped := (cbFontPicker <> nil) and cbFontPicker.DroppedDown;
    IsAnsiDropped := (cbAnsiVersion <> nil) and cbAnsiVersion.DroppedDown;

    if IsPickerDropped or IsAnsiDropped then
    begin
      TargetWnd := WindowFromPoint(Msg.pt);
      if IsMemo1Target(TargetWnd) then
      begin
        if IsPickerDropped then cbFontPicker.DroppedDown := False;
        if IsAnsiDropped then cbAnsiVersion.DroppedDown := False;

        MEMO1.SetFocus;
        Pt := Msg.pt;
        Windows.ScreenToClient(MEMO1.Handle, Pt);
        PostMessage(MEMO1.Handle, WM_LBUTTONDOWN, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        PostMessage(MEMO1.Handle, WM_LBUTTONUP, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        Handled := True;
      end
      else if IsMemo2Target(TargetWnd) then
      begin
        if IsPickerDropped then cbFontPicker.DroppedDown := False;
        if IsAnsiDropped then cbAnsiVersion.DroppedDown := False;

        MEMO2.SetFocus;
        Pt := Msg.pt;
        Windows.ScreenToClient(MEMO2.Handle, Pt);
        PostMessage(MEMO2.Handle, WM_LBUTTONDOWN, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        PostMessage(MEMO2.Handle, WM_LBUTTONUP, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        Handled := True;
      end;
    end;
  end;
end;

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FUniToBijoy.Free;
  FBijoyToUni.Free;
  Action := caFree;
  Form1 := nil;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  // The font list is owned by cbFontPicker (TFontPickerCombo)
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  SavedAnsiVersion, SavedFont, ErrMsg: string;
  Idx: Integer;
begin
  HandleThemes;
  DoubleBuffered := True;
  
  PanelHeader.DoubleBuffered := True;
  PanelButton.DoubleBuffered := True;
  PanelFooter.DoubleBuffered := True;

  AppEvents.OnMessage := AppEventsMessage;

  FSplitterRatio := MEMO1Panel.Height /
    (ClientHeight - PanelHeader.Height - PanelButton.Height - PanelFooter.Height - Splitter1.Height);
  FUniToBijoy := TUnicodeToBijoy2000.Create;
  FBijoyToUni := TBijoy2000ToUnicode.Create;

  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiMappingDir);

  // Populate the combo list first, so ItemIndex can be matched against it
  PopulateAnsiVersionsCombo;

  // Restore the "last used" ANSI mapping version and font from the registry
  // (AnsiVersion is shared with the main Avro Keyboard app).
  ReadConverterSettings(SavedAnsiVersion, SavedFont);
  if SavedAnsiVersion <> '' then
  begin
    TrySetAnsiVersion(SavedAnsiVersion, ErrMsg);
    Idx := cbAnsiVersion.Items.IndexOf(SavedAnsiVersion);
    if Idx >= 0 then
      cbAnsiVersion.ItemIndex := Idx
    else
      cbAnsiVersion.ItemIndex := 0;
  end
  else
    cbAnsiVersion.ItemIndex := 0;

  // Load all system fonts into cbFontPicker
  cbFontPicker.LoadFonts;

  // Set initial active font without triggering OnChange
  cbFontPicker.OnChange := nil;
  try
    if SavedFont <> '' then
    begin
      cbFontPicker.SetActiveFont(SavedFont);
      ApplyFontToMemo2(SavedFont);
    end
    else
      cbFontPicker.SetActiveFont(MEMO2.Font.Name);
  finally
    cbFontPicker.OnChange := cbFontPickerChange;
  end;

  MEMO1.DefAttributes.Name := MEMO1.Font.Name;
  MEMO1.DefAttributes.Size := MEMO1.Font.Size;
  MEMO1.DefAttributes.Charset := MEMO1.Font.Charset;
  MEMO2.DefAttributes.Name := MEMO2.Font.Name;
  MEMO2.DefAttributes.Size := MEMO2.Font.Size;
  MEMO2.DefAttributes.Charset := MEMO2.Font.Charset;

  MakeTextJustified(MEMO1);
  MakeTextJustified(MEMO2);

  SendMessage(MEMO1.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(6, 6));
  SendMessage(MEMO2.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(6, 6));
  MEMO1.PopupMenu := PopupMenu1;
  MEMO2.PopupMenu := PopupMenu1;
  MEMO1.OnContextPopup := MEMOContextPopup;
  MEMO2.OnContextPopup := MEMOContextPopup;
  SendMessage(MEMO1.Handle, EM_SETTARGETDEVICE, 0, 0);
  SendMessage(MEMO2.Handle, EM_SETTARGETDEVICE, 0, 0);

  SendMessage(MEMO1.Handle, EM_SETCUEBANNER, 1, LPARAM(PChar('Type or paste Unicode Bangla text here...')));
  SendMessage(MEMO2.Handle, EM_SETCUEBANNER, 1, LPARAM(PChar('Converted ANSI text will appear here...')));
  ActiveControl := MEMO1;
end;

procedure TForm1.FormResize(Sender: TObject);
var
  Available, NewHeight, AvailWidth: Integer;
begin
  // Dynamically size cbFontPicker with a max width constraint of 280px,
  // so it never stretches too wide in full screen mode, nor overflows
  // the window when it is small.
  if cbFontPicker <> nil then
  begin
    AvailWidth := ClientWidth - cbFontPicker.Left - 20;
    if AvailWidth > 280 then
      cbFontPicker.Width := 280
    else if AvailWidth > 120 then
      cbFontPicker.Width := AvailWidth;
  end;

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

    if MEMO1Panel.Height <> NewHeight then
    begin
      DisableAlign;
      try
        MEMO1Panel.Height := NewHeight;
      finally
        EnableAlign;
      end;
    end;
  end;
end;

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

procedure TForm1.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

end.