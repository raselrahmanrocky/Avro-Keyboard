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
  Buttons,
  clsUnicodeToBijoy2000,
  clsBijoy2000ToUnicode,
  ComCtrls,
  ExtCtrls,
  Vcl.AppEvnts,
  uRoundedPanel,
  Math,
  Registry,
  StrUtils,
  System.RegularExpressions;

type
  // Interceptor class to stop TRichEdit flicker during live resize
  TRichEdit = class(ComCtrls.TRichEdit)
    private
      procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
    protected
      // Use the Msftedit.dll control (RichEdit 3.0) instead of Riched20.dll
      // (RichEdit 2.0) so the native EM_SETZOOM/EM_GETZOOM messages work.
      procedure CreateParams(var Params: TCreateParams); override;
  end;

  // Interceptor class for TComboBox (same name as the VCL base class, so the
  // .dfm only needs the standard "TComboBox" class name the IDE knows).  It
  // merges the two custom combos of this form:
  //   * ANSI version combo (Style = csOwnerDrawFixed) - fully custom-painted
  //     face (amber design language) and owner-drawn drop-down list.
  //   * Font picker (Style = csDropDown) - searchable font picker with live
  //     type-to-search filtering, click-to-open and keyboard navigation.
  // FFontPickerMode is set by the form in FormCreate to select the behaviour.
  TComboBox = class(StdCtrls.TComboBox)
    private
      // Shared face state
      FHovered:      Boolean;
      FPressed:      Boolean;
      FActive:       Boolean; // ANSI version combo: drop-down list is open
      FFontPickerMode: Boolean; // this instance is the searchable font picker
      // Font-picker state
      FFullFontList: TStringList; // Master list of every installed font
      FActiveFont:   string;      // Last committed font
      FSearchText:   string;      // Search text kept while navigating
      FCursorIndex:  Integer;     // Highlighted suggestion index
      FUpdating:     Boolean;     // Re-entrancy guard
      FCommitting:   Boolean;     // A selection is being committed
      FOpenByFilter: Boolean;     // List was opened by live filtering
      FEditHandle:   hWnd;        // Inner EDIT control (keyboard/mouse focus target)
      FDefEditProc:  Pointer;     // Original window proc of the inner EDIT
      FClickWasOpen: Boolean;     // Drop-down was open at WM_LBUTTONDOWN
      procedure ApplyEditCentering; // ES_LEFT + vertical centering of the edit text
      procedure CMMouseEnter(var Message: TMessage); message CM_MOUSEENTER;
      procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
      procedure WMLButtonDown(var Message: TWMLButtonDown); message WM_LBUTTONDOWN;
      procedure WMLButtonUp(var Message: TWMLButtonUp); message WM_LBUTTONUP;
      procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
      procedure WMKillFocus(var Message: TWMKillFocus); message WM_KILLFOCUS;
      procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
      procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
      procedure PaintFace(DC: HDC);
      procedure PaintBorder(DC: HDC);
      procedure DrawDropDownItem(DC: HDC; Index: Integer; Rect: TRect; State: TOwnerDrawState);
      function ListHandle: hWnd;
      function HasInputFocus: Boolean;
      procedure UpdateListCursor;
      procedure MoveCursor(Delta: Integer);
      function HandleEditKey(uMsg: UINT; wParam: wParam; lParam: lParam): Boolean;
    protected
      procedure CreateParams(var Params: TCreateParams); override;
      procedure CreateWnd; override;
      procedure DestroyWnd; override;
      procedure WndProc(var Message: TMessage); override;
    public
      constructor Create(AOwner: TComponent); override;
      destructor Destroy; override;
      procedure SetDropDownActive(const Value: Boolean);
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
      property FontPickerMode: Boolean read FFontPickerMode write FFontPickerMode;
  end;

  // Original window procedure of the combo's inner EDIT control.
  TFontPickerEditWndProc = function(hWnd: hWnd; uMsg: UINT; wParam: wParam; lParam: lParam): LRESULT stdcall;

  // Theme modes offered by the settings gear menu.
  TThemeMode = (tmSystem, tmLight, tmDark);

  TForm1 = class(TForm)
    MEMO1: TRichEdit;
    MEMO2: TRichEdit;
    MEMO1Panel: TPanel;
    MEMO2Panel: TPanel;
    Button1: TButton;
    Button2: TButton;
    LabelAnsi: TLabel;
    cbAnsiVersion: TComboBox;
    cbFontPicker: TComboBox;
    Progress: TProgressBar;
    Label_OmicronLab: TLabel;
    AppEvents: TApplicationEvents;
    PanelButton: TPanel;
    PanelFooter: TPanel;
    LblFooter: TLabel;
    Splitter1: TSplitter;
    PopupMenu1: TPopupMenu;
    btnSettings: TSpeedButton;
    pmSettings: TPopupMenu;
    miThemeSystem: TMenuItem;
    miThemeLight: TMenuItem;
    miThemeDark: TMenuItem;
    Cut1: TMenuItem;
    Copy1: TMenuItem;
    Paste1: TMenuItem;
    SelectAll1: TMenuItem;
    Clear1: TMenuItem;
    miZoomHint: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure cbAnsiVersionChange(Sender: TObject);
    procedure cbAnsiVersionDropDown(Sender: TObject);
    procedure cbAnsiVersionCloseUp(Sender: TObject);
    procedure cbFontPickerChange(Sender: TObject);
    procedure cbFontPickerDropDown(Sender: TObject);
    procedure cbFontPickerCloseUp(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure Label_OmicronLabClick(Sender: TObject);
    procedure btnSettingsClick(Sender: TObject);
    procedure MenuThemeClick(Sender: TObject);
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
      FUniToBijoy:       TUnicodeToBijoy2000;
      FBijoyToUni:       TBijoy2000ToUnicode;
      FSplitterRatio:    Double;
      FPopupTarget:      TRichEdit;
      FCurrentThemeMode: TThemeMode;
      // Non-nil while a background conversion (TConversionWorker) is running.
      // The worker nils it via Synchronize once its work has been applied.
      FConvThread:       TThread;
      // Guards FormClose against re-entry while it waits for a running
      // conversion to finish (a second WM_CLOSE during the wait loop).
      FClosing:          Boolean;

      procedure ApplySelectedTheme(Mode: TThemeMode);
      function ReadConverterThemeMode: TThemeMode;
      procedure StartConversion(UnicodeToAnsi: Boolean);
      procedure CompleteConversion(UnicodeToAnsi: Boolean; const OutText, ErrMsg: string);
      procedure LoadMemoText(RE: TRichEdit; const Text, FontName: string; FontSize: Integer; Charset: Byte; RestoreCaret: Integer = -1);

      procedure AppEventsMessage(var Msg: TMsg; var Handled: Boolean);
      procedure WMFocusMemo(var Message: TMessage); message WM_APP + 1;
      function IsMemo1Target(AHwnd: hWnd): Boolean;
      function IsMemo2Target(AHwnd: hWnd): Boolean;
      procedure HandleThemes;
      procedure ApplyFontToMemo2(const FontName: string);
      procedure MakeTextJustified(RE: TRichEdit);
      // Applies PFA_JUSTIFY to a range (ASelEnd = -1 means to end of text).
      procedure SetMemoJustify(RE: TRichEdit; ASelStart, ASelEnd: Integer);
      // Re-asserts margins + EM_SETTARGETDEVICE so wrapping tracks the width.
      procedure RefreshMemoWrap(RE: TRichEdit);
      // Applies a colour to every character in one SCF_ALL pass (theme switch).
      procedure ApplyMemoTextColor(RE: TRichEdit; AColor: TColor);
      procedure Splitter1CanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
      procedure PasteToPopupMemo(Target: TRichEdit = nil);
      procedure SaveConverterSetting(const Name, Value: string);
      function ReadConverterSettings(out AnsiVer, FontName: string): Boolean;
      procedure ConvertRtfUnicodeToBijoy(Src, Dst: TStream; Conv: TUnicodeToBijoy2000);
      procedure DrawRoundedFrame(APanel: TPanel; AMemo: TRichEdit);
      function PopupMemo: TRichEdit;
      function MemoAtPoint(const Pt: TPoint): TRichEdit;
      function CurrentMemoZoomPercent(RE: TRichEdit): Integer;
      procedure SetMemoZoom(RE: TRichEdit; TargetPercent: Integer);
      procedure CopyMemoWithFont(M: TRichEdit);
      procedure UpdateFooterTip;
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

type
  // Runs the Unicode<->ANSI conversion on a worker thread so the UI stays
  // responsive on very large texts.  Progress is pushed back through the
  // converters' OnProgress callback and applied to the Progress bar via
  // Synchronize; the final Synchronize applies the result to the memo and
  // lets the thread free itself (FreeOnTerminate).
  TConversionWorker = class(TThread)
    private
      FOwner:         TForm1;
      FUnicodeToAnsi: Boolean;
      FSrc:           string;
      FResult:        string;
      FError:         string;
      FPercent:       Integer;
      FStage:         string;
      procedure WorkerProgress(Sender: TObject; Percent: Integer; const Stage: string);
      procedure SyncProgress;
      procedure SyncFinished;
    protected
      procedure Execute; override;
    public
      constructor Create(AOwner: TForm1; UnicodeToAnsi: Boolean; const Src: string);
  end;

  // Replaces VCL's TRichEditStyleHook so the style engine stops forcing its
  // own colors (e.g. pure black) into the memos; every message is passed
  // straight back to the control, which paints the colors we assign.
  TPassThroughRichEditStyleHook = class(TStyleHook)
    function HandleMessage(var Message: TMessage): Boolean; override;
  end;

function TPassThroughRichEditStyleHook.HandleMessage(var Message: TMessage): Boolean;
begin
  // Never consume the message - let the control handle it normally.
  Result := False;
end;

{ =============================================================================== }
{ Small colour helpers shared by the mapping picker }
{ =============================================================================== }

const
  AccentColor        = $00E67E22;
  CB_GETCOMBOBOXINFO = $0164;
  EM_SETCUEBANNER    = $1505;

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
  Result := RGB(R1 + (R2 - R1) * Percent2 div 100, G1 + (G2 - G1) * Percent2 div 100, B1 + (B2 - B1) * Percent2 div 100);
end;

function IsCheckedMapping(const AText: string): Boolean;
begin
  Result := SameText(AnsiVersion, AText) or ((AnsiVersion = '') and SameText(AText, 'Default'));
end;

procedure DrawAnsiGlyphBullet(C: TCanvas; const ARect: TRect; AColor: TColor);
var
  Glyph: string;
  R:     TRect;
begin
  Glyph := #$0995; // Bengali 'ka' (U+0995)
  C.Font.Name := 'Kalpurush ANSI';
  C.Font.Charset := ANSI_CHARSET;
  C.Font.Size := 10;
  C.Font.Style := [];
  C.Font.Color := AColor;
  C.Brush.Style := bsClear;
  R := ARect;
  DrawText(C.Handle, PChar(Glyph), Length(Glyph), R, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
end;

{ =============================================================================== }
{ TComboBox: ANSI version combo face painting }
{ =============================================================================== }

procedure TComboBox.CMMouseEnter(var Message: TMessage);
begin
  FHovered := True;
  Invalidate;
  inherited;
end;

procedure TComboBox.CMMouseLeave(var Message: TMessage);
begin
  FHovered := False;
  Invalidate;
  inherited;
end;

procedure TComboBox.WMLButtonDown(var Message: TWMLButtonDown);
begin
  FPressed := True;
  Invalidate;
  inherited;
end;

procedure TComboBox.WMLButtonUp(var Message: TWMLButtonUp);
begin
  FPressed := False;
  Invalidate;
  inherited;
end;

procedure TComboBox.WMSetFocus(var Message: TWMSetFocus);
begin
  Invalidate;
  inherited;
end;

procedure TComboBox.WMKillFocus(var Message: TWMKillFocus);
begin
  Invalidate;
  inherited;
  // Font picker only: restore the active font when the user leaves the
  // search box half-typed or empty.
  if FFontPickerMode and ((Text = '') or not FontExists(Text)) then
  begin
    FUpdating := True;
    try
      Text := FActiveFont;

      // ফোকাস সরার সময় যেন সিলেক্ট না হয়:
      SelStart := Length(FActiveFont);
      SelLength := 0;
    finally
      FUpdating := False;
    end;
  end;
end;

procedure TComboBox.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  message.Result := 1;
end;

procedure TComboBox.SetDropDownActive(const Value: Boolean);
begin
  FActive := Value;
  if not Value then
    FPressed := False;
  Invalidate;
end;

procedure TComboBox.PaintFace(DC: HDC);
var
  C:                                    TCanvas;
  R, TextR, GlyphR:                     TRect;
  Bg, PanelBg, BorderC, TextC, BulletC: TColor;
  S:                                    string;
  Cx, Cy:                               Integer;
  Pts:                                  array [0 .. 2] of TPoint;
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
    DrawText(C.Handle, PChar(S), Length(S), TextR, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

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
  message.Result := 1;
end;

procedure TRichEdit.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // RICHEDIT50W (Msftedit.dll) implements RichEdit 3.0, which is required for
  // the instant EM_SETZOOM zoom used by Ctrl + mouse wheel.
  CreateSubClass(Params, 'RICHEDIT50W');
end;

procedure TForm1.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or WS_CLIPCHILDREN;
end;

procedure TForm1.DrawRoundedFrame(APanel: TPanel; AMemo: TRichEdit);
var
  R, FullR:              TRect;
  Bg, ParentBg, BorderC: TColor;
  PenW:                  Integer;
  IsDark:                Boolean;
begin
  IsDark := (GetRValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace))) + GetGValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace))) +
      GetBValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace)))) < 384;

  if IsDark then
  begin
    ParentBg := RGB(31, 31, 31); // #1f1f1f
    Bg := RGB(31, 31, 31);       // #1f1f1f
  end
  else
  begin
    ParentBg := StyleServices.GetSystemColor(clBtnFace);
    Bg := AMemo.Color;
  end;

  if AMemo.Focused then
  begin
    PenW := 1;
    if StyleServices.Enabled then
      BorderC := StyleServices.GetSystemColor(clHighlight)
    else
      BorderC := clHighlight;
  end
  else
  begin
    PenW := 1;
    if IsDark then
      BorderC := RGB(80, 85, 95) // দৃশ্যমান সফট ডার্ক-গ্রে বর্ডার আউটলাইন
    else
      BorderC := RGB(200, 200, 200);
  end;

  FullR := APanel.ClientRect;
  R := FullR;
  InflateRect(R, -4, -4);

  with TPanel(APanel).Surface do
  begin
    // ১. প্যানেল মার্জিন
    Brush.Color := ParentBg;
    Brush.Style := bsSolid;
    Pen.Style := psClear;
    FillRect(FullR);

    // ২. মেমো ব্যাকগ্রাউন্ড
    Brush.Color := Bg;
    Brush.Style := bsSolid;
    Pen.Style := psClear;
    RoundRect(R.Left, R.Top, R.Right, R.Bottom, 12, 12);

    // ৩. আউটলাইন বর্ডার
    InflateRect(R, -PenW div 2, -PenW div 2);
    Brush.Style := bsClear;
    Pen.Style := psSolid;
    Pen.Width := PenW;
    Pen.Color := BorderC;
    RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 12, 12);
  end;
end;

procedure TForm1.MemoPanelPaint(Sender: TObject);
begin
  if Sender = MEMO1Panel then
    DrawRoundedFrame(MEMO1Panel, MEMO1)
  else if Sender = MEMO2Panel then
    DrawRoundedFrame(MEMO2Panel, MEMO2);
end;

procedure TForm1.MemoPanelMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
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
  UpdateFooterTip;
end;

// The memo under the mouse cursor (or the focused one) - used to decide which
// box the Ctrl + mouse wheel zoom applies to.
function TForm1.MemoAtPoint(const Pt: TPoint): TRichEdit;
var
  Wnd: hWnd;
begin
  Result := nil;
  Wnd := WindowFromPoint(Pt);
  if IsMemo1Target(Wnd) then
    Result := MEMO1
  else if IsMemo2Target(Wnd) then
    Result := MEMO2
  else if MEMO1.Focused then
    Result := MEMO1
  else if MEMO2.Focused then
    Result := MEMO2;
end;

// Permanently changes the ACTUAL font size of a memo (the text itself).
// Applies the size to the base font, the default attributes (newly typed
// text) and the selected text, then restores the caret/selection.  Clamped
// to 10pt..72pt.
// Returns the memo's current zoom as a percentage (defaults to 100% when the
// control reports no zoom).  EM_SETZOOM stores the zoom as a numerator/
// denominator fraction; SetMemoZoom always writes a denominator of 100, so
// the numerator read back here is already the percentage.
function TForm1.CurrentMemoZoomPercent(RE: TRichEdit): Integer;
var
  ZoomNum, ZoomDen: Cardinal;
begin
  if SendMessage(RE.Handle, EM_GETZOOM, WPARAM(@ZoomNum), LPARAM(@ZoomDen)) = 0 then
  begin
    ZoomNum := 100;
    ZoomDen := 100;
  end;
  if ZoomDen = 0 then
    ZoomDen := 100;
  Result := Round(ZoomNum * 100 / ZoomDen);
  if Result < 1 then
    Result := 100;
end;

// Applies a display-only zoom (50%..300%) with the RichEdit's native
// EM_SETZOOM: the control scales its rendering instantly without re-formatting
// every run or re-shaping complex-script text, so it is equally fast on the
// Unicode memo (MEMO1) and the ANSI memo (MEMO2) no matter how much text they
// hold.  The stored font size is untouched, so the converted output keeps the
// user's chosen size.
procedure TForm1.SetMemoZoom(RE: TRichEdit; TargetPercent: Integer);
begin
  if TargetPercent < 50 then
    TargetPercent := 50;
  if TargetPercent > 300 then
    TargetPercent := 300;
  SendMessage(RE.Handle, EM_SETZOOM, TargetPercent, 100);
end;

// Context-sensitive guidance shown in the footer bar, driven by which memo
// currently has the focus.
procedure TForm1.UpdateFooterTip;
begin
  if LblFooter = nil then
    Exit;
  if MEMO1.Focused then
    LblFooter.Caption := 'Unicode input - type or paste Bengali text, then press "Unicode to ANSI". ' +
      'Right-click for edit options. Ctrl + mouse wheel to zoom.'
  else if MEMO2.Focused then
    LblFooter.Caption := 'ANSI preview - pick a font above, or press "ANSI to Unicode" to convert back. ' +
      'Right-click for edit options. Ctrl + mouse wheel to zoom.'
  else
    LblFooter.Caption := 'Right-click a box for edit options. Ctrl + mouse wheel to zoom in/out.';
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

procedure TForm1.MEMOContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
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

// Stream-out callback for EM_STREAMOUT (SF_RTF): appends the RTF bytes the
// rich edit produces into the TBytesStream passed as dwCookie.
function RtfStreamOutCallback(dwCookie: DWORD_PTR; pbBuff: PByte; cb: Longint; var pcb: Longint): Longint; stdcall;
begin
  Result := 0;
  try
    pcb := TBytesStream(dwCookie).Write(pbBuff^, cb);
  except
    Result := 1; // signal the error back to the rich edit
    pcb := 0;
  end;
end;

// Stream-in callback for EM_STREAMIN (SF_TEXT or SF_UNICODE): feeds the
// bytes of a TStringStream to the rich edit control.
function RtfStreamInCallback(dwCookie: DWORD_PTR; pbBuff: PByte; cb: Longint; var pcb: Longint): Longint; stdcall;
begin
  Result := 0;
  try
    pcb := TStringStream(dwCookie).Read(pbBuff^, cb);
  except
    Result := 1; // signal the error back to the rich edit
    pcb := 0;
  end;
end;

// Copy exports the selection as RTF so the active font name (SutonnyMJ etc.)
// travels with the text into MS Word, but strips the explicit font SIZE
// (\fsN) and COLOR (\cfN / {\colortbl ...}) control words first - Word then
// uses its own document font size and Automatic text color instead of the
// app's 18pt preview size / dark-theme white.  Both the cleaned RTF and a
// plain CF_UNICODETEXT copy are placed on the clipboard, so any consumer
// (Word, browsers, editors) gets a usable format.
procedure TForm1.CopyMemoWithFont(M: TRichEdit);
var
  SavedStart, SavedLength: Integer;
  WasSelected:            Boolean;
  Stream:                 TBytesStream;
  EditStream:             TEditStream;
  RtfBytes:               TBytes;
  RtfStr, UniText:        string;
  Enc:                    TEncoding;
  H:                      HGLOBAL;
  P:                      Pointer;
  ByteCount:              Integer;
  RtfFmt:                 UINT;
begin
  if M = nil then
    Exit;

  SavedStart := M.SelStart;
  SavedLength := M.SelLength;
  WasSelected := SavedLength > 0;

  // Lock redraws so an auto "Select All" (when nothing was selected) is
  // never visible on screen.
  SendMessage(M.Handle, WM_SETREDRAW, 0, 0);
  try
    if not WasSelected then
      M.SelectAll;

    // 1. Stream the selection out as raw RTF bytes.
    Stream := TBytesStream.Create;
    try
      FillChar(EditStream, SizeOf(EditStream), 0);
      EditStream.dwCookie := DWORD_PTR(Stream);
      EditStream.pfnCallback := RtfStreamOutCallback;
      SendMessage(M.Handle, EM_STREAMOUT, SFF_SELECTION or SF_RTF, LPARAM(@EditStream));
      RtfBytes := Stream.Bytes;
      SetLength(RtfBytes, Stream.Size);
    finally
      Stream.Free;
    end;

    UniText := M.SelText;

    // 2. Strip \fsN (size) and \cfN / {\colortbl ...} (color) control words.
    // The RTF bytes are bridged through ISO-8859-1 so every byte round-trips
    // losslessly (the stripped patterns are pure ASCII, so they match
    // identically whatever codepage the RTF header declares).
    Enc := TEncoding.GetEncoding(28591);
    RtfStr := Enc.GetString(RtfBytes);
    RtfStr := TRegEx.Replace(RtfStr, '\\fs\d+\s?', '');
    RtfStr := TRegEx.Replace(RtfStr, '\\cf\d+\s?', '');
    RtfStr := TRegEx.Replace(RtfStr, '\{\\colortbl[^}]*\}', '');
    RtfBytes := Enc.GetBytes(RtfStr);

    // 3. Place both formats on the Windows clipboard.
    RtfFmt := RegisterClipboardFormat('Rich Text Format');
    if OpenClipboard(Handle) then
      try
        EmptyClipboard;

        // CF_UNICODETEXT: the plain Unicode text of the selection.
        ByteCount := (Length(UniText) + 1) * SizeOf(WideChar);
        H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, ByteCount);
        if H <> 0 then
        begin
          P := GlobalLock(H);
          if P <> nil then
          begin
            Move(PWideChar(UniText)^, P^, ByteCount);
            GlobalUnlock(H);
            if SetClipboardData(CF_UNICODETEXT, H) = 0 then
              GlobalFree(H); // clipboard did not take ownership
          end
          else
            GlobalFree(H);
        end;

        // Rich Text Format: the cleaned RTF (font name kept, size/color gone).
        ByteCount := Length(RtfBytes) + 1;
        H := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, ByteCount);
        if H <> 0 then
        begin
          P := GlobalLock(H);
          if P <> nil then
          begin
            if Length(RtfBytes) > 0 then
              Move(RtfBytes[0], P^, Length(RtfBytes));
            GlobalUnlock(H);
            if SetClipboardData(RtfFmt, H) = 0 then
              GlobalFree(H);
          end
          else
            GlobalFree(H);
        end;
      finally
        CloseClipboard;
      end;

    // 4. Restore the original selection (still under the redraw lock).
    M.SelStart := SavedStart;
    M.SelLength := SavedLength;
  finally
    SendMessage(M.Handle, WM_SETREDRAW, 1, 0);
    M.Invalidate;
  end;
end;

procedure TForm1.MenuCutClick(Sender: TObject);
var
  M: TRichEdit;
begin
  M := PopupMemo;
  if (M <> nil) and (M.SelLength > 0) then
  begin
    CopyMemoWithFont(M);
    // Undoable deletion of the selection (wParam = 1 enables undo/redo).
    SendMessage(M.Handle, EM_REPLACESEL, 1, lParam(PChar('')));
  end;
end;

procedure TForm1.MenuCopyClick(Sender: TObject);
begin
  CopyMemoWithFont(PopupMemo);
end;

{ Applies PFA_JUSTIFY to the given range only - the single place paragraph
  alignment is set, so LoadMemoText, MakeTextJustified and the paste path all
  agree.  ASelEnd = -1 extends the selection to the end of the document. }
procedure TForm1.SetMemoJustify(RE: TRichEdit; ASelStart, ASelEnd: Integer);
var
  ParaFormat: PARAFORMAT2;
begin
  if not RE.HandleAllocated then
    Exit;
  FillChar(ParaFormat, SizeOf(ParaFormat), 0);
  ParaFormat.cbSize := SizeOf(ParaFormat);
  ParaFormat.dwMask := PFM_ALIGNMENT;
  ParaFormat.wAlignment := PFA_JUSTIFY;

  SendMessage(RE.Handle, EM_SETSEL, WPARAM(ASelStart), WPARAM(ASelEnd));
  SendMessage(RE.Handle, EM_SETPARAFORMAT, 0, LPARAM(@ParaFormat));
end;

{ Re-asserts the word-wrap boundary: EM_SETMARGINS keeps the format rectangle
  inset constant (6 px each side, matching FormCreate) and EM_SETTARGETDEVICE
  with a nil DC makes the control re-wrap to its current client width - this
  tracks the vertical scrollbar exactly.  Call after any resize or content
  change that alters the available width; otherwise the wrap boundary stays at
  an old/narrower width and text wraps early, leaving an uneven gap on the
  right edge. }
procedure TForm1.RefreshMemoWrap(RE: TRichEdit);
begin
  if not RE.HandleAllocated then
    Exit;
  SendMessage(RE.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(6, 6));
  SendMessage(RE.Handle, EM_SETTARGETDEVICE, 0, 0);
end;

{ Applies the given colour to every character of the document with a single
  EM_SETCHARFORMAT SCF_ALL pass - no SelectAll/SelAttributes round-trips, so
  a live theme switch stays instant even on very large documents. }
procedure TForm1.ApplyMemoTextColor(RE: TRichEdit; AColor: TColor);
var
  CF: TCharFormat2;
begin
  if not RE.HandleAllocated then
    Exit;
  FillChar(CF, SizeOf(CF), 0);
  CF.cbSize := SizeOf(CF);
  CF.dwMask := CFM_COLOR;
  CF.crTextColor := ColorToRGB(AColor);
  SendMessage(RE.Handle, EM_SETCHARFORMAT, SCF_ALL, LPARAM(@CF));
end;

procedure TForm1.PasteToPopupMemo(Target: TRichEdit = nil);
var
  M:                   TRichEdit;
  ClipText:            string;
  InsertAt, InsertEnd: Integer;
begin
  // An explicit Target (Ctrl+V resolves it from the keyboard focus) is used
  // as-is; a nil Target resolves via PopupMemo, which prefers the memo the
  // popup was opened on (FPopupTarget) - correct for the context menu, where
  // the first right-click on an inactive window may not move the focus.
  if Target <> nil then
    M := Target
  else
    M := PopupMemo;
  if (M <> nil) and CanPasteToMemo then
  begin
    // ক্লিপবোর্ড থেকে প্লেইন ইউনিকোড টেক্সট নেওয়া
    if Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT) then
      ClipText := Clipboard.AsText
    else
      Exit;

    if ClipText = '' then
      Exit;

    SendMessage(M.Handle, WM_SETREDRAW, 0, 0);
    try
      // Where the insertion starts (caret, or the start of the selection it
      // replaces) - the pasted range is justified without touching the rest.
      InsertAt := M.SelStart;

      // ১. কার্সার পজিশনে বর্তমান ফন্ট সাইজ ও সঠিক কালার নিশ্চিত করা
      M.SelAttributes.Name := M.Font.Name;
      M.SelAttributes.Size := M.Font.Size;
      M.SelAttributes.Color := StyleServices.GetSystemColor(clWindowText);
      M.SelAttributes.Charset := M.Font.Charset;

      // ২. wParam = 1 দিয়ে টেক্সট ইনসার্ট করা (wParam = 1 দিলে এটি Undo/Redo করা যায়)
      SendMessage(M.Handle, EM_REPLACESEL, 1, lParam(PChar(ClipText)));

      // After EM_REPLACESEL the caret sits at the end of the inserted text:
      // justify exactly that range (same PFA_JUSTIFY as the rest of the memo)
      // and re-assert the wrap boundary to the current client width.
      InsertEnd := M.SelStart;
      SetMemoJustify(M, InsertAt, InsertEnd);
      M.SelStart := InsertEnd;
      M.SelLength := 0;
      RefreshMemoWrap(M);
    finally
      SendMessage(M.Handle, WM_SETREDRAW, 1, 0);
      M.Invalidate;
      SendMessage(M.Handle, EM_SCROLLCARET, 0, 0);
    end;
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
  TextColor:               TColor;
  CF:                      TCharFormat2;
  SavedStart, SavedLength: Integer;
begin
  // ১. সিলেকশন হাইলাইট লুকানো এবং স্ক্রিন রিড্র সাময়িক বন্ধ রাখা
  SendMessage(RE.Handle, EM_HIDESELECTION, 1, 0);
  SendMessage(RE.Handle, WM_SETREDRAW, 0, 0);
  try
    SavedStart := RE.SelStart;
    SavedLength := RE.SelLength;

    // Whole-document justification via the shared routine - EM_SETSEL(0, -1)
    // selects everything without the VCL SelectAll overhead; restored below.
    SetMemoJustify(RE, 0, -1);

    TextColor := StyleServices.GetSystemColor(clWindowText);

    // Font attributes across the whole document in one SCF_ALL pass - no
    // SelectAll/SelAttributes round-trips (keeps the current size).
    FillChar(CF, SizeOf(CF), 0);
    CF.cbSize := SizeOf(CF);
    CF.dwMask := CFM_COLOR or CFM_FACE or CFM_SIZE;
    CF.crTextColor := ColorToRGB(TextColor);
    CF.yHeight := RE.Font.Size * 20;
    StrPLCopy(@CF.szFaceName[0], RE.Font.Name, LF_FACESIZE - 1);
    SendMessage(RE.Handle, EM_SETCHARFORMAT, SCF_ALL, LPARAM(@CF));

    RE.DefAttributes.Color := TextColor;
    RE.DefAttributes.Name := RE.Font.Name;
    RE.DefAttributes.Size := RE.Font.Size;

    // কার্সারকে পেস্ট করা পজিশনে ফিরিয়ে দেওয়া
    RE.SelStart := SavedStart;
    RE.SelLength := SavedLength;

    RefreshMemoWrap(RE);
  finally
    // ২. রিড্র চালু ও সিলেকশন আনহাইড করা
    SendMessage(RE.Handle, WM_SETREDRAW, 1, 0);
    SendMessage(RE.Handle, EM_HIDESELECTION, 0, 0);
    RE.Invalidate;
    SendMessage(RE.Handle, EM_SCROLLCARET, 0, 0);
  end;
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
      Reg.WriteString(name, Value);
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

  Converts the Unicode text inside an RTF stream to (ANSI) while leaving
  every RTF structure word intact - table definitions (\trowd, \cl..., \cellx,
  \cell, \row, \lastcell), fonts, colors, embedded binary (\bin), etc.

  Windows RichEdit stores text that does not fit the ANSI codepage as \uNNNN
  escapes (a signed 16-bit Unicode value plus \ucN fallback characters). Only
  those escapes - and literal runs of plain text - are converted; everything
  else is copied byte-for-byte, so tables pasted from Word/Excel survive the
  conversion with their cell borders and structure intact.
  --------------------------------------------------------------------------- }
procedure TForm1.ConvertRtfUnicodeToBijoy(Src, Dst: TStream; Conv: TUnicodeToBijoy2000);
const
  // Windows-1252 mappings for bytes $80..$9F (the only range where cp1252
  // differs from the plain Unicode code point of the same value). Literal
  // bytes in an RTF stream are interpreted in the declared \ansicpg.
  Cp1252: array [0 .. 31] of Word = ($20AC, $0081, $201A, $0192, $201E, $2026, $2020, $2021, $02C6, $2030, $0160, $2039, $0152, $008D, $017D, $008F, $0090,
    $2018, $2019, $201C, $201D, $2022, $2013, $2014, $02DC, $2122, $0161, $203A, $0153, $009D, $017E, $0178);

  // Control words that END a text unit. Everything else (character/run
  // formatting like \f0, \fs22, \lang9, table structure like \trowd,
  // \cellx, \cl..., \tr...) is kept verbatim and does NOT split the text
  // being converted, so a Bengali word that Word splits across font switches
  // still converts as one unit with full conjunct context.
  BoundaryWords: array [0 .. 10] of string = ('cell', 'lastcell', 'row', 'par', 'pard', 'line', 'sect', 'page', 'column', 'bin', 'tab');
var
  InBuf, OutBuf, ConvBuf:                                          TBytes;
  TextBuf:                                                         string;
  I, J, Len, UC, Fallback, Bin, WordStart, Code, InsertPos, Depth: Integer;
  B:                                                               Byte;
  W:                                                               string;
  HasParam, HasDelimSpace, IsBoundary:                             Boolean;
  Param, Sign:                                                     Int64;
  K:                                                               Integer;

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

// Append converted text bytes to ConvBuf. ASCII goes out literally; bytes
// above $7F (Bijoy conjuncts in the ANSI font) go out as \'hh hex escapes,
// which RTF treats exactly like the literal byte: RichEdit maps it through
// the ANSI codepage (\ansicpg) and the 8-bit font renders its own glyph.
// A \uNNNN escape must NOT be used here - it would store NNNN as a plain
// Unicode code point, bypassing the codepage mapping, so a Bijoy byte like
// $8C would be stored as U+008C (a control character) and the conjunct
// would never render.
  procedure EmitConverted(const S: string);
  var
    K, V, F: Integer;
    HexStr:  string;
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
        HexStr := '\''' + LowerCase(IntToHex(V, 2));
        for F := 1 to Length(HexStr) do
        begin
          SetLength(ConvBuf, Length(ConvBuf) + 1);
          ConvBuf[Length(ConvBuf) - 1] := Ord(HexStr[F]);
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
    ConvText:                 string;
    OldLen, NewLen, Extra, M: Integer;
  begin
    if TextBuf = '' then
      Exit;
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
    if (InsertPos > 0) and (OutBuf[InsertPos - 1] in [Ord('a') .. Ord('z'), Ord('A') .. Ord('Z'), Ord('0') .. Ord('9'), Ord('-')]) then
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
  UC := 1;       // \ucN - fallback characters after each \uNNNN (default 1)
  Fallback := 0; // source fallback chars still to be skipped
  Bin := 0;      // remaining raw binary bytes to copy verbatim (\binN)

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
      if (B = Ord('{')) and (I + 2 < Len) and (InBuf[I + 1] = Ord('\')) and (InBuf[I + 2] = Ord('*')) then
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
            else if (J + 5 < Len) and (InBuf[J + 1] = Ord('b')) and (InBuf[J + 2] = Ord('i')) and (InBuf[J + 3] = Ord('n')) and
              (InBuf[J + 4] in [Ord('0') .. Ord('9')]) then
            begin
              // skip the digits of a \binN payload length word
              J := J + 5;
              while (J < Len) and (InBuf[J] in [Ord('0') .. Ord('9')]) do
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

      if B in [Ord('a') .. Ord('z')] then
      begin
        // Control word: read the letters and optional signed numeric parameter.
        WordStart := I;
        while (I < Len) and (InBuf[I] in [Ord('a') .. Ord('z')]) do
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
        while (I < Len) and (InBuf[I] in [Ord('0') .. Ord('9')]) do
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
          for K := 0 to high(BoundaryWords) do
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
          if (I < Len) and (InBuf[I] in [Ord('0') .. Ord('9'), Ord('a') .. Ord('f'), Ord('A') .. Ord('F')]) then
          begin
            if InBuf[I] <= Ord('9') then
              Code := InBuf[I] - Ord('0')
            else if InBuf[I] <= Ord('F') then
              Code := InBuf[I] - Ord('A') + 10
            else
              Code := InBuf[I] - Ord('a') + 10;
            Inc(I);
          end;
          if (I < Len) and (InBuf[I] in [Ord('0') .. Ord('9'), Ord('a') .. Ord('f'), Ord('A') .. Ord('F')]) then
          begin
            Code := Code * 16;
            if InBuf[I] <= Ord('9') then
              Code := Code + InBuf[I] - Ord('0')
            else if InBuf[I] <= Ord('F') then
              Code := Code + InBuf[I] - Ord('A') + 10
            else
              Code := Code + InBuf[I] - Ord('a') + 10;
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
var
  TextColor, FaceColor, WindowColor, DarkBg: TColor;
  IsDark:                                    Boolean;
begin
  case FCurrentThemeMode of
    tmSystem:
      SetAppropriateThemeMode('Windows10 Dark', 'Windows10', 'Windows');
    tmLight:
      TStyleManager.TrySetStyle('Windows10', False);
    tmDark:
      TStyleManager.TrySetStyle('Windows10 Dark', False);
  end;

  // Detect dark mode by the effective face colour: a dark theme resolves
  // clBtnFace to a dark grey, a light theme to a light grey. (IsSystemStyle
  // cannot be used here - it is only True for the native system style, while
  // this app always activates a custom style such as 'Windows10 Dark'.)
  IsDark := StyleServices.Enabled and
    ((GetRValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace))) + GetGValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace))) +
        GetBValue(ColorToRGB(StyleServices.GetSystemColor(clBtnFace)))) < 384);

  // Resolve the theme palette once - every control below uses these values,
  // so the whole form switches colours in one consistent pass.
  TextColor := StyleServices.GetSystemColor(clWindowText);
  FaceColor := StyleServices.GetSystemColor(clBtnFace);
  WindowColor := StyleServices.GetSystemColor(clWindow);

  if IsDark then
  begin
    DarkBg := RGB(31, 31, 31); // #1f1f1f

    // মেমোর VCL Style Client override বন্ধ
    MEMO1.StyleElements := MEMO1.StyleElements - [seClient];
    MEMO2.StyleElements := MEMO2.StyleElements - [seClient];

    // ফর্ম এবং সব প্যানেলের ব্যাকগ্রাউন্ড কালার #1f1f1f সেট করা
    Self.Color := DarkBg;

    PanelButton.ParentBackground := False;
    PanelButton.Color := DarkBg;

    PanelFooter.ParentBackground := False;
    PanelFooter.Color := DarkBg;

    MEMO1Panel.ParentBackground := False;
    MEMO1Panel.Color := DarkBg;

    MEMO2Panel.ParentBackground := False;
    MEMO2Panel.Color := DarkBg;

    MEMO1.Color := DarkBg;
    MEMO2.Color := DarkBg;

    // দৃশ্যমান গ্রে শেড, যা #1f1f1f ব্যাকগ্রাউন্ডের সাথে কনট্রাস্ট তৈরি করে
    Splitter1.Color := RGB(60, 60, 65);
  end
  else
  begin
    MEMO1.StyleElements := [seFont, seClient, seBorder];
    MEMO2.StyleElements := [seFont, seClient, seBorder];

    Self.Color := FaceColor;

    // Explicitly reset the Color each panel was given in dark mode.
    // ParentBackground := True alone is not enough here: the rounded-panel
    // interceptor swallows WM_ERASEBKGND and the buffered paint can keep
    // the stale #1f1f1f colour otherwise.
    PanelButton.ParentBackground := True;
    PanelButton.Color := FaceColor;

    PanelFooter.ParentBackground := True;
    PanelFooter.Color := FaceColor;

    MEMO1Panel.ParentBackground := True;
    MEMO1Panel.Color := FaceColor;

    MEMO2Panel.ParentBackground := True;
    MEMO2Panel.Color := FaceColor;

    MEMO1.Color := WindowColor;
    MEMO2.Color := WindowColor;

    // লাইট মোডে হালকা গ্রে স্প্লিটার বর্ডার
    Splitter1.Color := RGB(220, 220, 220);
  end;

  // RichEdit নেটিভ ব্যাকগ্রাউন্ড ওয়াশ আপডেট
  SendMessage(MEMO1.Handle, EM_SETBKGNDCOLOR, 0, ColorToRGB(MEMO1.Color));
  SendMessage(MEMO2.Handle, EM_SETBKGNDCOLOR, 0, ColorToRGB(MEMO2.Color));

  // Control font and the default for newly typed text follow the theme too.
  MEMO1.Font.Color := TextColor;
  MEMO2.Font.Color := TextColor;
  MEMO1.DefAttributes.Color := TextColor;
  MEMO2.DefAttributes.Color := TextColor;

  // Whole-document text colour in one SCF_ALL pass per memo - no
  // SelectAll/SelAttributes round-trips, so the switch stays instant.
  ApplyMemoTextColor(MEMO1, TextColor);
  ApplyMemoTextColor(MEMO2, TextColor);

  // Re-assert the wrap boundary (target device + margins) to the current
  // client width after the style change.
  RefreshMemoWrap(MEMO1);
  RefreshMemoWrap(MEMO2);

  MEMO1Panel.Invalidate;
  MEMO2Panel.Invalidate;
  cbAnsiVersion.Invalidate;

  // Force every child to repaint now so no stale buffered background (e.g.
  // the dark #1f1f1f) survives the switch - RDW_ERASE re-sends
  // WM_ERASEBKGND to the whole window hierarchy.
  RedrawWindow(Handle, nil, 0, RDW_INVALIDATE or RDW_ALLCHILDREN or RDW_UPDATENOW or RDW_ERASE);
end;

{ Applies the selected theme, refreshes the UI colours and persists the
  choice so the next launch opens with the same mode. }
procedure TForm1.ApplySelectedTheme(Mode: TThemeMode);
const
  ModeNames: array [TThemeMode] of string = ('System', 'Light', 'Dark');
begin
  FCurrentThemeMode := Mode;
  HandleThemes;
  SaveConverterSetting('ThemeMode', ModeNames[Mode]);
end;

{ Reads the last selected theme mode from the registry; defaults to System. }
function TForm1.ReadConverterThemeMode: TThemeMode;
var
  Reg: TRegistry;
  S:   string;
begin
  Result := tmSystem;
  Reg := TRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly('Software\OmicronLab\Avro Keyboard') then
    begin
      S := Reg.ReadString('ThemeMode');
      if SameText(S, 'Light') then
        Result := tmLight
      else if SameText(S, 'Dark') then
        Result := tmDark;
    end;
  finally
    Reg.Free;
  end;
end;

{ Shows the theme popup menu under the gear button with the active mode
  checked. }
procedure TForm1.btnSettingsClick(Sender: TObject);
var
  Pt: TPoint;
begin
  miThemeSystem.Checked := (FCurrentThemeMode = tmSystem);
  miThemeLight.Checked := (FCurrentThemeMode = tmLight);
  miThemeDark.Checked := (FCurrentThemeMode = tmDark);
  Pt := btnSettings.ClientToScreen(Point(0, btnSettings.Height));
  pmSettings.Popup(Pt.X, Pt.Y);
end;

procedure TForm1.MenuThemeClick(Sender: TObject);
begin
  if Sender is TMenuItem then
    ApplySelectedTheme(TThemeMode(TMenuItem(Sender).Tag));
end;

procedure TForm1.AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
begin
  if SameText('ImmersiveColorSet', string(Section)) then
    HandleThemes;
end;

procedure TForm1.StartConversion(UnicodeToAnsi: Boolean);
var
  Src: string;
begin
  // One conversion at a time - the worker uses the shared converter
  // instances (FUniToBijoy / FBijoyToUni), which must not run concurrently.
  if FConvThread <> nil then
    Exit;

  if UnicodeToAnsi then
    Src := MEMO1.Text
  else
    Src := MEMO2.Text;
  if Src = '' then
    Exit;

  // Keep the UI live: the actual Convert runs on a background thread, so a
  // huge text no longer freezes the window.  The controls that could race
  // with the worker (the second convert button, the ANSI-mapping combo that
  // can InvalidateTables mid-flight) are disabled until it finishes.
  Button1.Enabled := False;
  Button2.Enabled := False;
  cbAnsiVersion.Enabled := False;
  LblFooter.Visible := False;
  Progress.Position := 0;
  Progress.Visible := True;

  FConvThread := TConversionWorker.Create(Self, UnicodeToAnsi, Src);
  FConvThread.Start;
end;

// Loads a large converted document into a memo without freezing the UI.
// The old `Memo.Text :=` + SCF_ALL + paragraph passes forced RichEdit to
// re-format and re-shape the whole complex-script document on the main
// thread several times - measured in the tens of seconds on big texts.  Here
// the character/paragraph defaults are applied BEFORE loading, so the
// streamed text inherits font/size/color and justification automatically;
// one EM_STREAMIN (SF_UNICODE) then replaces the whole document in a single
// pass (~5x faster than Text :=, and no post-load formatting passes at all).
procedure TForm1.LoadMemoText(RE: TRichEdit; const Text, FontName: string; FontSize: Integer; Charset: Byte; RestoreCaret: Integer = -1);
var
  Stream:   TStringStream;
  ES:       TEditStream;
  PF:       PARAFORMAT2;
  CaretPos: Integer;
begin
  // Select everything - EM_STREAMIN replaces the current selection, so this
  // swaps the whole document in one pass (no separate Clear).
  SendMessage(RE.Handle, EM_SETSEL, 0, -1);

  RE.Font.Name := FontName;
  RE.Font.Charset := Charset;
  RE.Font.Size := FontSize;
  RE.DefAttributes.Name := FontName;
  RE.DefAttributes.Size := FontSize;
  RE.DefAttributes.Charset := Charset;
  RE.DefAttributes.Color := StyleServices.GetSystemColor(clWindowText);

  // Default paragraph format = justified (the streamed text picks it up).
  FillChar(PF, SizeOf(PF), 0);
  PF.cbSize := SizeOf(PF);
  PF.dwMask := PFM_ALIGNMENT;
  PF.wAlignment := PFA_JUSTIFY;
  SendMessage(RE.Handle, EM_SETPARAFORMAT, 0, LPARAM(@PF));

  Stream := TStringStream.Create(Text, TEncoding.Unicode, False);
  try
    FillChar(ES, SizeOf(ES), 0);
    ES.dwCookie := DWORD_PTR(Stream);
    ES.pfnCallback := @RtfStreamInCallback;
    SendMessage(RE.Handle, EM_STREAMIN, SF_TEXT or SF_UNICODE, LPARAM(@ES));
  finally
    Stream.Free;
  end;

  // Make justification explicit on the streamed document (idempotent - the
  // default set above is what new text inherits) and refresh the wrap
  // boundary so the text re-wraps edge-to-edge at the current client width.
  SetMemoJustify(RE, 0, -1);
  RefreshMemoWrap(RE);

  // Restore the caret to its pre-conversion position, clamped to the new
  // document length (the converted text may be shorter than what was there
  // before) so EM_SETSEL can never point past the buffer.  EM_SETSEL(x, x)
  // also clears any selection, so no blue highlight survives the conversion,
  // and EM_SCROLLCARET keeps the caret visible.  Runs inside the caller's
  // WM_SETREDRAW-off window, so there is no flicker.
  if RestoreCaret >= 0 then
  begin
    CaretPos := Math.Min(RestoreCaret, Length(Text));
    SendMessage(RE.Handle, EM_SETSEL, CaretPos, CaretPos);
    SendMessage(RE.Handle, EM_SCROLLCARET, 0, 0);
  end;
end;

procedure TForm1.CompleteConversion(UnicodeToAnsi: Boolean; const OutText, ErrMsg: string);
var
  Target:     TRichEdit;
  ActiveFont: string;
  SavedCaret: Integer;
begin
  Progress.Visible := False;
  LblFooter.Visible := True;
  Button1.Enabled := True;
  Button2.Enabled := True;
  cbAnsiVersion.Enabled := True;
  FConvThread := nil;

  if ErrMsg <> '' then
  begin
    MessageDlg('Conversion failed: ' + ErrMsg, mtError, [mbOK], 0);
    Exit;
  end;

  if UnicodeToAnsi then
  begin
    Target := MEMO2;
    ActiveFont := cbFontPicker.ActiveFont;
    if ActiveFont = '' then
      ActiveFont := cbFontPicker.Text;
    if ActiveFont = '' then
      ActiveFont := Target.Font.Name;

    // Remember where the caret is in the output memo before the whole
    // document is replaced, so it can be restored after the conversion.
    SavedCaret := Target.SelStart;

    SendMessage(Target.Handle, WM_SETREDRAW, 0, 0);
    try
      LoadMemoText(Target, OutText, ActiveFont, Target.Font.Size, ANSI_CHARSET, SavedCaret);
      cbFontPicker.ActiveFont := ActiveFont;
    finally
      SendMessage(Target.Handle, WM_SETREDRAW, 1, 0);
      Target.Invalidate;
    end;
  end
  else
  begin
    Target := MEMO1;
    // Remember where the caret is in the output memo before the whole
    // document is replaced, so it can be restored after the conversion.
    SavedCaret := Target.SelStart;

    SendMessage(Target.Handle, WM_SETREDRAW, 0, 0);
    try
      LoadMemoText(Target, OutText, Target.Font.Name, Target.Font.Size, Target.Font.Charset, SavedCaret);
    finally
      SendMessage(Target.Handle, WM_SETREDRAW, 1, 0);
      Target.Invalidate;
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  TConversionWorker

  Runs FUniToBijoy.Convert / FBijoyToUni.Convert on a worker thread.  The
  converters keep their own per-instance state (fToggleStates etc.) and only
  touch read-only global mapping tables, so using the form's shared instances
  from this single worker is safe - the buttons and the ANSI-version combo are
  disabled while it runs, so no other code path touches them concurrently.
  --------------------------------------------------------------------------- }
constructor TConversionWorker.Create(AOwner: TForm1; UnicodeToAnsi: Boolean; const Src: string);
begin
  inherited Create(True); // suspended - the form starts it explicitly
  FreeOnTerminate := True;
  FOwner := AOwner;
  FUnicodeToAnsi := UnicodeToAnsi;
  FSrc := Src;
end;

procedure TConversionWorker.Execute;
begin
  try
    if FUnicodeToAnsi then
    begin
      // A real method reference (not an anonymous method) so the assignment
      // compiles against the converters' TConverterProgress (of object) type.
      FOwner.FUniToBijoy.OnProgress := WorkerProgress;
      try
        FResult := FOwner.FUniToBijoy.Convert(FSrc);
      finally
        // Drop the callback so the converter never holds a reference to this
        // worker after it has been freed (FreeOnTerminate).
        FOwner.FUniToBijoy.OnProgress := nil;
      end;
    end
    else
    begin
      FOwner.FBijoyToUni.OnProgress := WorkerProgress;
      try
        FResult := FOwner.FBijoyToUni.Convert(FSrc);
      finally
        FOwner.FBijoyToUni.OnProgress := nil;
      end;
    end;
  except
    on E: Exception do
      FError := E.Message;
  end;

  Synchronize(SyncFinished);
end;

procedure TConversionWorker.WorkerProgress(Sender: TObject; Percent: Integer; const Stage: string);
begin
  // Fired from the converters' OnProgress while Convert runs on this worker.
  FPercent := Percent;
  FStage := Stage;
  Synchronize(SyncProgress);
end;

procedure TConversionWorker.SyncProgress;
begin
  // Runs on the main thread; the form may be closing, so guard the control.
  if FOwner.Progress <> nil then
    FOwner.Progress.Position := FPercent;
end;

procedure TConversionWorker.SyncFinished;
begin
  // Runs on the main thread after the conversion finished (or failed).
  FOwner.CompleteConversion(FUnicodeToAnsi, FResult, FError);
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  StartConversion(True);
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  StartConversion(False);
end;

procedure TForm1.PopulateAnsiVersionsCombo;
var
  SR:       TSearchRec;
  Versions: TStringList;
  I:        Integer;
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
      if DirectoryExists(AnsiMappingDir) and (FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0) then
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
  if VerName = '' then
    Exit;

  if not TrySetAnsiVersion(VerName, ErrMsg) then
    MessageDlg('Failed to load ANSI mapping: ' + ErrMsg, mtError, [mbOK], 0)
  else
  begin
    // রিভার্স কনভার্টারের লুকআপ টেবিল ক্যাশ করা থাকে; ম্যাপিং বদলেছে, তাই
    // সেগুলো স্টেল চিহ্নিত করুন - পরের Convert-এ একবারই রিবিল্ড হবে।
    FBijoyToUni.InvalidateTables;
    SaveConverterSetting('AnsiVersion', VerName);
  end;
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
{ TComboBox: editable, owner-drawn, type-to-search font picker }
{ =============================================================================== }

function FontPickerEditProc(hWnd: hWnd; uMsg: UINT; wParam: wParam; lParam: lParam): LRESULT stdcall;
var
  Combo: TComboBox;
begin
  Combo := TComboBox(GetProp(hWnd, 'AvroFontPicker'));
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

  // The native combo selects the whole edit text when the edit gains focus
  // via keyboard/Tab or programmatically at startup. Clear that selection so
  // the font name is never left highlighted in blue - unless the user is
  // actively clicking into the field (the click itself places the caret).
  if uMsg = WM_SETFOCUS then
  begin
    if (GetKeyState(VK_LBUTTON) and $8000) = 0 then
      SendMessage(hWnd, EM_SETSEL, -1, -1);
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

  if ((uMsg = WM_LBUTTONDOWN) or (uMsg = WM_LBUTTONDBLCLK)) and not Combo.FClickWasOpen and not Combo.DroppedDown and not Combo.IsUpdating then
  begin
    Combo.HandleDropDown;
    Combo.DroppedDown := True;
  end;
end;

function TComboBox.HandleEditKey(uMsg: UINT; wParam: wParam; lParam: lParam): Boolean;
var
  Key: Word;
begin
  Result := False;
  if uMsg <> WM_KEYDOWN then
    Exit;
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

constructor TComboBox.Create(AOwner: TComponent);
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

destructor TComboBox.Destroy;
begin
  FFullFontList.Free;
  inherited Destroy;
end;

procedure TComboBox.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // The font picker is a csDropDown combo in the .dfm but owner-drawn at
  // runtime; the ANSI version combo is already csOwnerDrawFixed from the .dfm.
  if FFontPickerMode then
    Params.Style := Params.Style or CBS_OWNERDRAWFIXED;
end;

procedure TComboBox.CreateWnd;
var
  Info: TComboBoxInfo;
begin
  inherited CreateWnd;
  // Sub-classing the inner edit is only meaningful for the searchable font
  // picker; the ANSI version combo paints its own face and has no edit text.
  if not FFontPickerMode then
    Exit;
  SendMessage(Handle, CB_SETITEMHEIGHT, 0, ItemHeight);

  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if SendMessage(Handle, CB_GETCOMBOBOXINFO, 0, lParam(@Info)) <> 0 then
    if (Info.hwndItem <> 0) and (Info.hwndItem <> Handle) then
    begin
      FEditHandle := Info.hwndItem;
      RemoveProp(FEditHandle, 'AvroFontPicker');
      SetProp(FEditHandle, 'AvroFontPicker', THandle(Self));
      FDefEditProc := Pointer(SetWindowLongPtr(FEditHandle, GWLP_WNDPROC, LONG_PTR(@FontPickerEditProc)));
    end;
  ApplyEditCentering;
end;

procedure TComboBox.ApplyEditCentering;
var
  DC:                   HDC;
  TM:                   TTextMetric;
  HF:                   HFONT;
  OldFont:              HFONT;
  CR, WR:               TRect;
  ParentClient:         TRect;
  ClientOrigin:         TPoint;
  RelTop, NewTop, NewH: Integer;
  Style:                LONG_PTR;
begin
  if FEditHandle = 0 then
    Exit;
  SendMessage(FEditHandle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN, MakeLParam(8, 8));
  // Horizontal alignment: the inner edit reads ES_LEFT/CENTER/RIGHT from its
  // window style at paint time. Force left alignment (ES_LEFT = 0) by clearing
  // the CENTER/RIGHT bits. The native combo already insets the edit's format
  // rectangle (~14 px on the left), so the text starts clear of the left
  // border without any extra margins.
  Style := GetWindowLongPtr(FEditHandle, GWL_STYLE);
  if (Style and (ES_CENTER or ES_RIGHT)) <> 0 then
  begin
    SetWindowLongPtr(FEditHandle, GWL_STYLE, Style and not(ES_CENTER or ES_RIGHT));
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
  if HF = 0 then
    HF := GetStockObject(DEFAULT_GUI_FONT);
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
  if NewH < 8 then
    NewH := 8; // sanity floor
  if NewH >= CR.Bottom - 2 then
    Exit; // already sized to fit the text

  Windows.GetWindowRect(FEditHandle, WR);
  Windows.GetClientRect(Handle, ParentClient);
  ClientOrigin.X := ParentClient.Left;
  ClientOrigin.Y := ParentClient.Top;
  Windows.ClientToScreen(Handle, ClientOrigin);
  RelTop := WR.Top - ClientOrigin.Y;
  NewTop := RelTop + (CR.Bottom - NewH) div 2 + 1;
  SetWindowPos(FEditHandle, 0, WR.Left - ClientOrigin.X, NewTop, WR.Right - WR.Left, NewH, SWP_NOZORDER or SWP_NOACTIVATE);
end;

procedure TComboBox.DestroyWnd;
begin
  if FFontPickerMode and (FEditHandle <> 0) and Assigned(FDefEditProc) then
  begin
    SetWindowLongPtr(FEditHandle, GWLP_WNDPROC, LONG_PTR(FDefEditProc));
    RemoveProp(FEditHandle, 'AvroFontPicker');
    FEditHandle := 0;
    FDefEditProc := nil;
  end;
  inherited DestroyWnd;
end;

function TComboBox.HasInputFocus: Boolean;
begin
  Result := (GetFocus = Handle) or IsChild(Handle, GetFocus);
end;

procedure TComboBox.PaintBorder(DC: HDC);
var
  C:           TCanvas;
  R:           TRect;
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

procedure TComboBox.WMPaint(var Message: TWMPaint);
var
  DC, MemDC: HDC;
  PS:        TPaintStruct;
  Bmp, Old:  HBITMAP;
begin
  if message.DC <> 0 then
  begin
    if FFontPickerMode then
      PaintBorder(message.DC)
    else
      PaintFace(message.DC);
    Exit;
  end;

  DC := BeginPaint(Handle, PS);
  try
    MemDC := CreateCompatibleDC(DC);
    Bmp := CreateCompatibleBitmap(DC, Width, Height);
    Old := SelectObject(MemDC, Bmp);
    try
      if FFontPickerMode then
        PaintBorder(MemDC)
      else
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

procedure TComboBox.DrawDropDownItem(DC: HDC; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  C:                 TCanvas;
  Text:              string;
  TextR:             TRect;
  Bg:                TColor;
  IsHover, IsActive: Boolean;
begin
  C := TCanvas.Create;
  try
    C.Handle := DC;
    Text := Items[index];
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

      TextR := System.Classes.Rect(Rect.Left + 8, Rect.Top, Rect.Right - 4, Rect.Bottom);
      DrawText(Handle, PChar(Text), Length(Text), TextR, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
    end;
  finally
    C.Free;
  end;
end;

function TComboBox.ListHandle: hWnd;
var
  Info: TComboBoxInfo;
begin
  Result := 0;
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if SendMessage(Handle, CB_GETCOMBOBOXINFO, 0, lParam(@Info)) <> 0 then
    Result := Info.hwndList;
end;

procedure TComboBox.UpdateListCursor;
var
  LH: hWnd;
begin
  if Items.Count = 0 then
    Exit;
  if FCursorIndex < 0 then
    FCursorIndex := 0;
  if FCursorIndex >= Items.Count then
    FCursorIndex := Items.Count - 1;
  LH := ListHandle;
  if LH <> 0 then
    SendMessage(LH, LB_SETCURSEL, FCursorIndex, 0);
end;

procedure TComboBox.MoveCursor(Delta: Integer);
var
  SaveText:               string;
  OldSelStart, OldSelLen: Integer;
begin
  if Items.Count = 0 then
    Exit;
  SaveText := FSearchText;
  if SaveText = '' then
    SaveText := Text;

  OldSelStart := SelStart;
  OldSelLen := SelLength;

  FCursorIndex := FCursorIndex + Delta;
  if FCursorIndex < 0 then
    FCursorIndex := 0;
  if FCursorIndex >= Items.Count then
    FCursorIndex := Items.Count - 1;

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

function TComboBox.FindFontIndex(const AName: string): Integer;
begin
  for Result := 0 to FFullFontList.Count - 1 do
    if SameText(FFullFontList[Result], AName) then
      Exit;
  Result := -1;
end;

procedure TComboBox.LoadFonts;
begin
  FFullFontList.Assign(Screen.Fonts);
  FUpdating := True;
  try
    Items.Assign(FFullFontList);
  finally
    FUpdating := False;
  end;
end;

procedure TComboBox.SetActiveFont(const AName: string);
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

procedure TComboBox.HandleDropDown;
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

procedure TComboBox.FilterList(const AText: string);
var
  I, OldSelStart, OldSelLen: Integer;
  MatchingFonts:             TStringList;
  NeedRefresh:               Boolean;
begin
  if FUpdating then
    Exit;

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
      if FCursorIndex < 0 then
        FCursorIndex := 0;

      if HasInputFocus and (MatchingFonts.Count > 0) and not FCommitting and not SameText(AText, FActiveFont) then
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

procedure TComboBox.RestoreFullList;
var
  SaveText: string;
  Idx:      Integer;
begin
  FOpenByFilter := False;
  SaveText := FActiveFont;
  if SaveText = '' then
    SaveText := Text;

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

procedure TComboBox.CommitCursor(ACloseDropDown: Boolean);
var
  LH:       hWnd;
  N:        Integer;
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

procedure TComboBox.CancelFilter;
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

function TComboBox.FilterAndGetExact: string;
var
  Idx: Integer;
begin
  Result := '';
  if FUpdating then
    Exit;
  FilterList(Text);
  Idx := FindFontIndex(Text);
  if (Text <> '') and (Idx >= 0) then
    Result := FFullFontList[Idx];
end;

function TComboBox.FontExists(const AName: string): Boolean;
begin
  Result := (AName <> '') and (FFullFontList.IndexOf(AName) >= 0);
end;

procedure TComboBox.WndProc(var Message: TMessage);
var
  Idx: Integer;
begin
  // The font picker's custom handling (search filtering, keyboard navigation,
  // commit-on-click, owner-drawn list) must not affect the ANSI version combo,
  // which relies on the native combo behaviour and its own OnDrawItem event.
  if FFontPickerMode then
  begin
    case message.Msg of
      // Keep the standard arrow cursor visible over the combo face and its
      // dropped-down list - same reason as in FontPickerEditProc: the system
      // may not refresh the cursor while the list holds mouse capture.
      WM_SETCURSOR:
        begin
          SetCursor(LoadCursor(0, IDC_ARROW));
          message.Result := 1;
          Exit;
        end;
      WM_KEYDOWN:
        begin
          if HandleEditKey(message.Msg, message.wParam, message.lParam) then
          begin
            message.Result := 0;
            Exit;
          end;
        end;
      CN_COMMAND:
        begin
          case TWMCommand(message).NotifyCode of
            CBN_SELCHANGE:
              begin
                message.Result := 0;
                Exit;
              end;
            CBN_SELENDOK:
              begin
                // Single mouse click or Enter key commits immediately
                if not FUpdating then
                  CommitCursor(True);
                message.Result := 0;
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
                message.Result := 0;
                Exit;
              end;
          end;
        end;
      CN_DRAWITEM:
        begin
          with PDrawItemStruct(message.lParam)^ do
            if Integer(itemID) >= 0 then
              DrawDropDownItem(HDC, Integer(itemID), rcItem, TOwnerDrawState(LoWord(itemState)));
          message.Result := 1;
          Exit;
        end;
    end;
  end;

  case message.Msg of
    WM_LBUTTONDOWN:
      Invalidate;
    WM_LBUTTONDBLCLK:
      Invalidate;
  end;
  inherited WndProc(message);
end;

{ =============================================================================== }
{ cbFontPicker form event handlers }
{ =============================================================================== }

procedure TForm1.cbFontPickerChange(Sender: TObject);
begin
  if cbFontPicker.IsUpdating then
    Exit;

  // ✅ Apply the font and move focus out only after it is confirmed via mouse click or Enter:
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
var
  CF: TCharFormat2;
begin
  // Change the font while redraws are suspended
  SendMessage(MEMO2.Handle, WM_SETREDRAW, 0, 0);
  try
    MEMO2.Font.Name := FontName;
    // Only the font FACE changes here - the user's current font size is kept.
    MEMO2.Font.Charset := ANSI_CHARSET;

    MEMO2.DefAttributes.Name := FontName;
    MEMO2.DefAttributes.Size := MEMO2.Font.Size;
    MEMO2.DefAttributes.Charset := ANSI_CHARSET;

    // SCF_ALL applies the face/size/charset to the whole document in one pass,
    // without SelectAll (which re-formats every run and freezes the UI on
    // large texts) and without touching the selection/caret.
    FillChar(CF, SizeOf(CF), 0);
    CF.cbSize := SizeOf(CF);
    CF.dwMask := CFM_FACE or CFM_SIZE or CFM_CHARSET;
    CF.bCharSet := ANSI_CHARSET;
    CF.yHeight := MEMO2.Font.Size * 20;
    StrPLCopy(@CF.szFaceName[0], FontName, LF_FACESIZE - 1);
    SendMessage(MEMO2.Handle, EM_SETCHARFORMAT, SCF_ALL, LPARAM(@CF));

    MakeTextJustified(MEMO2);
    // Explicitly re-apply word wrap to the window width after the font change
    SendMessage(MEMO2.Handle, EM_SETTARGETDEVICE, 0, 0);
    cbFontPicker.ActiveFont := FontName;
  finally
    // Re-enable redraws and refresh the screen at once
    SendMessage(MEMO2.Handle, WM_SETREDRAW, 1, 0);
    MEMO2.Invalidate;
  end;
end;

procedure TForm1.cbAnsiVersionDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Combo:                         TComboBox;
  Text:                          string;
  GlyphR, TextR:                 TRect;
  Bg:                            TColor;
  IsHover, IsChecked, IsDefault: Boolean;
begin
  Combo := TComboBox(Control);
  Text := Combo.Items[index];
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

    GlyphR := System.Classes.Rect(Rect.Left + 6, Rect.Top + 2, Rect.Left + 22, Rect.Bottom - 2);
    DrawAnsiGlyphBullet(Combo.Canvas, GlyphR, IfThen(IsChecked, AccentColor, SysColor(clWindowText)));

    Font := Combo.Font;
    Font.Color := SysColor(clWindowText);
    if IsChecked then
      Font.Style := [fsBold];
    TextR := System.Classes.Rect(Rect.Left + 26, Rect.Top, Rect.Right - 6, Rect.Bottom);
    DrawText(Handle, PChar(Text), Length(Text), TextR, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);

    if IsDefault and (index < Combo.Items.Count - 1) then
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

function TForm1.IsMemo1Target(AHwnd: hWnd): Boolean;
begin
  Result := (AHwnd <> 0) and (MEMO1 <> nil) and (MEMO1Panel <> nil) and
    ((AHwnd = MEMO1.Handle) or (AHwnd = MEMO1Panel.Handle) or IsChild(MEMO1Panel.Handle, AHwnd));
end;

function TForm1.IsMemo2Target(AHwnd: hWnd): Boolean;
begin
  Result := (AHwnd <> 0) and (MEMO2 <> nil) and (MEMO2Panel <> nil) and
    ((AHwnd = MEMO2.Handle) or (AHwnd = MEMO2Panel.Handle) or IsChild(MEMO2Panel.Handle, AHwnd));
end;

procedure TForm1.AppEventsMessage(var Msg: TMsg; var Handled: Boolean);
var
  TargetWnd:                      hWnd;
  Pt:                             TPoint;
  RE:                             TRichEdit;
  IsPickerDropped, IsAnsiDropped: Boolean;
begin
  // Ctrl + / Ctrl - / Ctrl 0 zoom the memo that currently has the keyboard
  // focus, using the same instant EM_SETZOOM as the mouse wheel (display-only
  // scaling - no per-run re-formatting, no complex-script re-shaping).  Note:
  // we resolve the target from the active focus directly (not via PopupMemo)
  // because PopupMemo prefers the stale FPopupTarget remembered from a
  // right-click, which would keep resizing MEMO1 after focus has moved to
  // MEMO2.  Works with both the Number Row and the Number Pad; the message is
  // marked handled so the +/-/0 character is never typed into the memo.
  if (Msg.Message = WM_KEYDOWN) and ((GetKeyState(VK_CONTROL) and $8000) <> 0) then
  begin
    // Directly target the currently focused memo control
    if MEMO2.Focused or (ActiveControl = MEMO2) then
      RE := MEMO2
    else if MEMO1.Focused or (ActiveControl = MEMO1) then
      RE := MEMO1
    else
      RE := nil;

    if RE <> nil then
    begin
      case Msg.wParam of
        // Zoom in 10%: Number Pad (+) or Number Row (=/+)
        VK_ADD, VK_OEM_PLUS:
          begin
            SetMemoZoom(RE, CurrentMemoZoomPercent(RE) + 10);
            Handled := True;
            Exit;
          end;

        // Zoom out 10%: Number Pad (-) or Number Row (-/_)
        VK_SUBTRACT, VK_OEM_MINUS:
          begin
            SetMemoZoom(RE, CurrentMemoZoomPercent(RE) - 10);
            Handled := True;
            Exit;
          end;

        // Reset zoom to 100%: Number Pad (0) or Number Row (0)
        VK_NUMPAD0, Ord('0'):
          begin
            SetMemoZoom(RE, 100);
            Handled := True;
            Exit;
          end;

        // Ctrl + C / Ctrl + X: copy/cut as clean plain text (no RTF with
        // theme colors - same reason as MenuCopyClick/MenuCutClick above).
        // Ctrl + C / Ctrl + X: copy/cut keeps the font name via RTF but
        // temporarily forces black color (see CopyMemoWithFont).
        Ord('C'):
          begin
            CopyMemoWithFont(RE);
            Handled := True;
            Exit;
          end;
        Ord('X'):
          begin
            if RE.SelLength > 0 then
            begin
              CopyMemoWithFont(RE);
              // Undoable deletion of the selection.
              SendMessage(RE.Handle, EM_REPLACESEL, 1, lParam(PChar('')));
            end;
            Handled := True;
            Exit;
          end;
      end;
    end;
  end;

  if (Msg.Message = WM_KEYDOWN) and (Msg.wParam = Ord('V')) and ((GetKeyState(VK_CONTROL) and $8000) <> 0) and CanPasteToMemo then
  begin
    // Ctrl+V pastes into the memo that has the keyboard focus, NOT into
    // PopupMemo - PopupMemo prefers the stale FPopupTarget remembered from an
    // earlier right-click and would paste into the other box after the focus
    // has moved (the same reason the font-size shortcuts resolve the target
    // from the focus directly).
    if MEMO2.Focused or (ActiveControl = MEMO2) then
      RE := MEMO2
    else if MEMO1.Focused or (ActiveControl = MEMO1) then
      RE := MEMO1
    else
      RE := nil;

    if RE <> nil then
    begin
      PasteToPopupMemo(RE);
      Handled := True;
    end;
  end
  else if (Msg.Message = WM_MOUSEWHEEL) and ((GetKeyState(VK_CONTROL) and $8000) <> 0) then
  begin
    // Ctrl + mouse wheel zooms the memo under the cursor with the RichEdit's
    // native EM_SETZOOM: display-only zoom applied instantly by the control
    // itself - no SelectAll, no per-run re-formatting, no UI freeze even on
    // huge documents, and equally fast on the Unicode and ANSI memos.
    RE := MemoAtPoint(Msg.Pt);
    if RE <> nil then
    begin
      // Wheel up = zoom in (+10%), wheel down = zoom out (-10%)
      if SmallInt(Msg.wParam shr 16) > 0 then
        SetMemoZoom(RE, CurrentMemoZoomPercent(RE) + 10)
      else
        SetMemoZoom(RE, CurrentMemoZoomPercent(RE) - 10);
      Handled := True; // don't let the wheel also scroll the control
    end;
  end
  else if (Msg.Message = WM_LBUTTONDOWN) or (Msg.Message = WM_NCLBUTTONDOWN) then
  begin
    IsPickerDropped := (cbFontPicker <> nil) and cbFontPicker.DroppedDown;
    IsAnsiDropped := (cbAnsiVersion <> nil) and cbAnsiVersion.DroppedDown;

    if IsPickerDropped or IsAnsiDropped then
    begin
      TargetWnd := WindowFromPoint(Msg.Pt);
      if IsMemo1Target(TargetWnd) then
      begin
        if IsPickerDropped then
          cbFontPicker.DroppedDown := False;
        if IsAnsiDropped then
          cbAnsiVersion.DroppedDown := False;

        MEMO1.SetFocus;
        Pt := Msg.Pt;
        Windows.ScreenToClient(MEMO1.Handle, Pt);
        PostMessage(MEMO1.Handle, WM_LBUTTONDOWN, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        PostMessage(MEMO1.Handle, WM_LBUTTONUP, Msg.wParam, MakeLParam(Pt.X, Pt.Y));
        Handled := True;
      end
      else if IsMemo2Target(TargetWnd) then
      begin
        if IsPickerDropped then
          cbFontPicker.DroppedDown := False;
        if IsAnsiDropped then
          cbAnsiVersion.DroppedDown := False;

        MEMO2.SetFocus;
        Pt := Msg.Pt;
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
  if not FClosing then
  begin
    FClosing := True;

    // Let any in-flight background conversion finish before freeing the
    // converters it may still be using.  The worker signals completion
    // through Synchronize, so pumping the queue lets it land; conversion is
    // fast (linear passes), so this loop is short.  The FClosing guard stops
    // a second WM_CLOSE delivered during the wait from re-entering.
    while FConvThread <> nil do
      Application.ProcessMessages;

    FUniToBijoy.Free;
    FBijoyToUni.Free;
  end;
  Action := caFree;
  Form1 := nil;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  // The font list is owned by cbFontPicker (the TComboBox font picker)
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  SavedAnsiVersion, SavedFont, ErrMsg: string;
  Idx:                                 Integer;
begin
  // Replace the VCL style hook for TRichEdit with a pass-through hook so the
  // style engine can no longer paint its own (pure black) background inside
  // the memos - the pass-through leaves every message to the control itself.
  TStyleManager.Engine.UnRegisterStyleHook(ComCtrls.TRichEdit, TRichEditStyleHook);
  TStyleManager.Engine.RegisterStyleHook(ComCtrls.TRichEdit, TPassThroughRichEditStyleHook);

  // Restore the last selected theme before the first paint. In tmSystem the
  // app follows the Windows dark/light mode (re-evaluated on setting changes).
  FCurrentThemeMode := ReadConverterThemeMode;
  HandleThemes;
  DoubleBuffered := True;

  // Splitter: টানার সময় ড্যাশড/প্যাটার্ন প্রিভিউ লাইন না দেখিয়ে মসৃণ লাইভ রিসাইজ
  Splitter1.ResizeStyle := rsUpdate;
  Splitter1.Height := 5;
  // সর্বনিম্ন ৮০ পিক্সেল সীমা - VCL নিজেই মাউসকে এর বেশি যেতে দেবে না
  Splitter1.MinSize := 80;
  // AutoSnap ডিফল্ট True হলে MinSize-এ পৌঁছালে প্যানেল ০-তে collapse হয় - বন্ধ করছি
  Splitter1.AutoSnap := False;
  Splitter1.OnCanResize := Splitter1CanResize;

  PanelButton.DoubleBuffered := True;
  PanelFooter.DoubleBuffered := True;

  AppEvents.OnMessage := AppEventsMessage;

  // The merged combo interceptor needs to know which instance is the
  // searchable font picker and which is the ANSI mapping version picker.
  cbFontPicker.FontPickerMode := True;
  cbAnsiVersion.FontPickerMode := False;

  // The rounded panels draw their frames through OnDraw.  The .dfm uses the
  // standard TPanel class name (so the IDE can open it), which has no OnDraw
  // property, so the event is wired up here instead of in the .dfm.
  MEMO1Panel.OnDraw := MemoPanelPaint;
  MEMO2Panel.OnDraw := MemoPanelPaint;

  FSplitterRatio := 0.48;
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

  MEMO1.Font.Size := 18;
  MEMO2.Font.Size := 18;

  // DefAttributes for new text insertion
  MEMO1.DefAttributes.Name := MEMO1.Font.Name;
  MEMO1.DefAttributes.Size := 18;
  MEMO1.DefAttributes.Charset := MEMO1.Font.Charset;
  MEMO2.DefAttributes.Name := MEMO2.Font.Name;
  MEMO2.DefAttributes.Size := 18;
  MEMO2.DefAttributes.Charset := MEMO2.Font.Charset;

  // SelAttributes for initial empty cursor caret position
  MEMO1.SelAttributes.Name := MEMO1.Font.Name;
  MEMO1.SelAttributes.Size := 18;
  MEMO1.SelAttributes.Charset := MEMO1.Font.Charset;
  MEMO2.SelAttributes.Name := MEMO2.Font.Name;
  MEMO2.SelAttributes.Size := 18;
  MEMO2.SelAttributes.Charset := MEMO2.Font.Charset;

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

  SendMessage(MEMO1.Handle, EM_SETCUEBANNER, 1, lParam(PChar('Type or paste Unicode Bangla text here...')));
  SendMessage(MEMO2.Handle, EM_SETCUEBANNER, 1, lParam(PChar('Converted ANSI text will appear here...')));
  ActiveControl := MEMO1;

  // Gear glyph and emoji captions are set here (the .dfm file is ANSI-only).
  btnSettings.Font.Name := 'Segoe UI Symbol';
  btnSettings.Font.Height := -16;
  btnSettings.Caption := Char($2699);
  miThemeSystem.Caption := Char($25D0) + ' System Default'; // ◐ Half circle
  miThemeLight.Caption := Char($2600) + ' Light Theme';     // ☀ Sun
  miThemeDark.Caption := Char($263D) + ' Dark Theme';       // ☽ Moon

  // Multi-line hints on both memos (the .dfm file is ANSI-only, so the hint
  // text with its line break is set here at runtime).
  Self.ShowHint := True;
  MEMO1.Hint := 'Right-click for Edit options (Cut/Copy/Paste)'#13#10 + 'Ctrl + Mouse Scroll Up/Down to Increase/Decrease Font Size';
  MEMO2.Hint := MEMO1.Hint;

  UpdateFooterTip;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  // Post (not send) so the input caret lands in MEMO1 only after the window
  // is fully created and shown - otherwise the native combo box reclaims
  // focus and highlights its text on launch.
  PostMessage(Handle, WM_APP + 1, 0, 0);
end;

procedure TForm1.WMFocusMemo(var Message: TMessage);
begin
  MEMO1.SetFocus;
end;

procedure TForm1.FormResize(Sender: TObject);
var
  Available, NewHeight, AvailWidth: Integer;
begin
  // Dynamically size cbFontPicker with a max width constraint of 280px,
  // so it never stretches too wide in full screen mode, nor overflows
  // the window when it is small. Reserve room for btnSettings on the right.
  if cbFontPicker <> nil then
  begin
    AvailWidth := btnSettings.Left - cbFontPicker.Left - 16;
    if AvailWidth > 280 then
      cbFontPicker.Width := 280
    else if AvailWidth > 120 then
      cbFontPicker.Width := AvailWidth;
  end;

  Available := ClientHeight - PanelButton.Height - PanelFooter.Height - Splitter1.Height;
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

  // Re-wrap both memos to the new client width - without this the RichEdit
  // target-device boundary stays at the old (narrower) width and text wraps
  // early, leaving an uneven gap on the right edge.  Handles may not exist
  // yet while the form is still being constructed; RefreshMemoWrap checks.
  RefreshMemoWrap(MEMO1);
  RefreshMemoWrap(MEMO2);
end;

procedure TForm1.Splitter1CanResize(Sender: TObject; var NewSize: Integer; var Accept: Boolean);
var
  Available: Integer;
begin
  // লাইভ ড্র্যাগ চলাকালেই দুই প্যানেলকে ৮০..(Available-৮০) সীমায় লক করুন -
  // এতে SplitterMoved-এ আর ম্যানুয়ালি Height রি-সেট করতে হয় না (ব্লিংকিং এড়ায়)
  Available := ClientHeight - PanelButton.Height - PanelFooter.Height - Splitter1.Height;
  if NewSize < 80 then
    NewSize := 80
  else if Available - NewSize < 80 then
    NewSize := Available - 80;
end;

procedure TForm1.SplitterMoved(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelButton.Height - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    // কেবল নতুন রেশিও সংরক্ষণ করুন - Height সরাসরি বদলানোর দরকার নেই
    FSplitterRatio := MEMO1Panel.Height / Available;
  end;
end;

procedure TForm1.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

end.
