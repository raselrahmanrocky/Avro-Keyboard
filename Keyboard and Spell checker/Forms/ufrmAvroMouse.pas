{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
{ COMPLETE TRANSFERING! }

unit ufrmAvroMouse;

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
  StdCtrls,
  Buttons,
  ExtCtrls,
  System.Skia;

type
  TfrmAvroMouse = class(TForm)
    Panel1: TPanel;
    BitBtn3: TBitBtn;
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    BitBtn4: TBitBtn;
    BitBtn5: TBitBtn;
    BitBtn6: TBitBtn;
    BitBtn7: TBitBtn;
    BitBtn8: TBitBtn;
    BitBtn9: TBitBtn;
    BitBtn10: TBitBtn;
    BitBtn11: TBitBtn;
    BitBtn12: TBitBtn;
    BitBtn13: TBitBtn;
    BitBtn14: TBitBtn;
    BitBtn15: TBitBtn;
    BitBtn16: TBitBtn;
    BitBtn17: TBitBtn;
    BitBtn18: TBitBtn;
    BitBtn19: TBitBtn;
    BitBtn20: TBitBtn;
    BitBtn21: TBitBtn;
    BitBtn24: TBitBtn;
    BitBtn25: TBitBtn;
    BitBtn28: TBitBtn;
    BitBtn29: TBitBtn;
    BitBtn22: TBitBtn;
    BitBtn23: TBitBtn;
    BitBtn26: TBitBtn;
    BitBtn27: TBitBtn;
    BitBtn30: TBitBtn;
    BitBtn31: TBitBtn;
    BitBtn32: TBitBtn;
    BitBtn33: TBitBtn;
    BitBtn34: TBitBtn;
    BitBtn35: TBitBtn;
    BitBtn36: TBitBtn;
    BitBtn37: TBitBtn;
    BitBtn38: TBitBtn;
    BitBtn39: TBitBtn;
    BitBtn41: TBitBtn;
    Panel2: TPanel;
    BitBtn40: TBitBtn;
    BitBtn42: TBitBtn;
    BitBtn43: TBitBtn;
    BitBtn44: TBitBtn;
    BitBtn45: TBitBtn;
    BitBtn46: TBitBtn;
    BitBtn47: TBitBtn;
    BitBtn48: TBitBtn;
    BitBtn49: TBitBtn;
    BitBtn50: TBitBtn;
    BitBtn51: TBitBtn;
    BitBtn52: TBitBtn;
    BitBtn53: TBitBtn;
    BitBtn54: TBitBtn;
    BitBtn55: TBitBtn;
    BitBtn56: TBitBtn;
    BitBtn57: TBitBtn;
    BitBtn58: TBitBtn;
    BitBtn59: TBitBtn;
    BitBtn60: TBitBtn;
    BitBtn61: TBitBtn;
    Panel3: TPanel;
    BitBtn62: TBitBtn;
    BitBtn63: TBitBtn;
    BitBtn64: TBitBtn;
    BitBtn65: TBitBtn;
    BitBtn66: TBitBtn;
    BitBtn67: TBitBtn;
    BitBtn68: TBitBtn;
    BitBtn69: TBitBtn;
    BitBtn70: TBitBtn;
    BitBtn71: TBitBtn;
    GroupBox1: TGroupBox;
    BitBtn72: TBitBtn;
    BitBtn73: TBitBtn;
    BitBtn74: TBitBtn;
    BitBtn75: TBitBtn;
    BitBtn76: TBitBtn;
    BitBtn77: TBitBtn;
    BitBtn78: TBitBtn;
    BitBtn79: TBitBtn;
    BitBtn80: TBitBtn;
    BitBtn81: TBitBtn;
    BitBtn82: TBitBtn;
    BitBtn83: TBitBtn;
    BitBtn84: TBitBtn;
    BitBtn85: TBitBtn;
    BitBtn86: TBitBtn;
    BitBtn87: TBitBtn;
    BitBtn88: TBitBtn;
    GroupBox2: TGroupBox;
    But_KSs: TBitBtn;
    But_NGK: TBitBtn;
    But_NgG: TBitBtn;
    But_JNYA: TBitBtn;
    But_NYAC: TBitBtn;
    But_NYACh: TBitBtn;
    But_NYAJ: TBitBtn;
    But_T_T: TBitBtn;
    But_SsNYA: TBitBtn;
    But_HM: TBitBtn;
    But_ND: TBitBtn;
    But_ZFola: TBitBtn;
    But_RFola: TBitBtn;
    BitBtn102: TBitBtn;
    BitBtn103: TBitBtn;
    BitBtn104: TBitBtn;
    BitBtn105: TBitBtn;
    BitBtn106: TBitBtn;
    btnTab: TButton;
    btnBackspace: TButton;
    btnSpace: TButton;
    btnEnter: TButton;
    BitBtn89: TBitBtn;
    BitBtn90: TBitBtn;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure BitBtn1Click(Sender: TObject);
    procedure btnTabClick(Sender: TObject);
    procedure But_KSsClick(Sender: TObject);
    procedure But_NGKClick(Sender: TObject);
    procedure But_NgGClick(Sender: TObject);
    procedure But_JNYAClick(Sender: TObject);
    procedure But_NYACClick(Sender: TObject);
    procedure But_NYAChClick(Sender: TObject);
    procedure But_NYAJClick(Sender: TObject);
    procedure But_T_TClick(Sender: TObject);
    procedure But_SsNYAClick(Sender: TObject);
    procedure But_HMClick(Sender: TObject);
    procedure But_NDClick(Sender: TObject);
    procedure But_RFolaClick(Sender: TObject);
    procedure But_ZFolaClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    private
      { Private declarations }
      { The colours the glyph bitmaps of this window were last baked with.
        Kept so a style change is detected by COLOUR rather than by style name:
        a Windows theme change delivers CM_STYLECHANGED to every window even
        when our forced LIGHT/DARK theme ignores it, and a build without the
        embedded styles draws from Windows' own colours. Recorded in
        RegenerateGlyphs, read in EnsureGlyphsMatchTheme. }
      FBakedInk: TColor;
      FBakedFace: TColor;
      procedure TypeIt(const tStr: string);
      procedure DetectLeftClickOnTitleBar(var Msg: TWMNCLButtonDown); message WM_NCLBUTTONDOWN;
      procedure DetectRightClickOnTitleBar(var Msg: TWMNCLButtonDown); message WM_NCRBUTTONDOWN;
      procedure RegenerateGlyphs;
      procedure RenderGlyph(const ABtn: TBitBtn; const AText: string);
      procedure BakeSvgGlyph(const ABtn: TBitBtn; const AText: string);
      procedure AssignSvgGlyph(const ABtn: TBitBtn; const ASvgPath: string);
      function DisplayTextOf(const ABtn: TBitBtn): string;
      function ThemeColor(const ASysColor: TColor): TColor;
      function GlyphInkColor: TColor;
      function GlyphFaceColor: TColor;
      procedure EnsureGlyphsMatchTheme;
      function MouseGlyphDir: string;
      function AssetMouseGlyphDir: string;
      procedure EnsureBanglaFont;
      function BanglaFontFile: string;
    public
      { Public declarations }
    protected
      procedure CreateParams(var Params: TCreateParams); override;
      { Delivered whenever the active VCL style changes - the Customize dialog's
        theme setting (LIGHT / DARK / SYSTEM) and Windows' own theme change both
        end up here. The Bangla characters are bitmaps with the style's button
        colours baked in, so they have to be baked again or they keep the
        previous theme's ink. Same hook, for the same reason, as
        TfrmOptions.CMStyleChanged. }
      procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  end;

var
  frmAvroMouse: TfrmAvroMouse;

implementation

{$R *.dfm}

uses
  uForm1,
  BanglaChars,
  KeyboardFunctions,
  uWindowHandlers,
  uRegistrySettings,
  clsLayout,
  WindowsDarkMode,
  uFileFolderHandling,
  Vcl.Themes,
  System.Types,
  System.RegularExpressions,
  System.IOUtils;

const
  Show_Window_in_Taskbar = True;

procedure TfrmAvroMouse.BitBtn1Click(Sender: TObject);
var
  WC: Char;
begin
  WC := Char((Sender as TBitBtn).Tag);
  TypeIt(WC);
end;

procedure TfrmAvroMouse.btnTabClick(Sender: TObject);
begin
  SendKey_SendInput((Sender as TButton).Tag);
end;

procedure TfrmAvroMouse.But_HMClick(Sender: TObject);
begin
  TypeIt(b_H + b_Hasanta + b_M);
end;

procedure TfrmAvroMouse.But_JNYAClick(Sender: TObject);
begin
  TypeIt(b_J + b_Hasanta + b_NYA);
end;

procedure TfrmAvroMouse.But_KSsClick(Sender: TObject);
begin
  TypeIt(b_K + b_Hasanta + b_Ss);
end;

procedure TfrmAvroMouse.But_NDClick(Sender: TObject);
begin
  TypeIt(b_Nn + b_Hasanta + b_Dd);
end;

procedure TfrmAvroMouse.But_NgGClick(Sender: TObject);
begin
  TypeIt(b_NGA + b_Hasanta + b_G);
end;

procedure TfrmAvroMouse.But_NGKClick(Sender: TObject);
begin
  TypeIt(b_NGA + b_Hasanta + b_K);
end;

procedure TfrmAvroMouse.But_NYACClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_C);
end;

procedure TfrmAvroMouse.But_NYAChClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_CH);
end;

procedure TfrmAvroMouse.But_NYAJClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_J);
end;

procedure TfrmAvroMouse.But_RFolaClick(Sender: TObject);
begin
  TypeIt(b_Hasanta + b_R);
end;

procedure TfrmAvroMouse.But_SsNYAClick(Sender: TObject);
begin
  TypeIt(b_Ss + b_Hasanta + b_Nn);
end;

procedure TfrmAvroMouse.But_T_TClick(Sender: TObject);
begin
  TypeIt(b_T + b_Hasanta + b_T);
end;

procedure TfrmAvroMouse.But_ZFolaClick(Sender: TObject);
begin
  TypeIt(b_Hasanta + b_Z);
end;

procedure TfrmAvroMouse.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  with Params do
  begin
    if Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle or WS_EX_APPWINDOW and not WS_EX_TOOLWINDOW;
      ExStyle := ExStyle or WS_EX_TOPMOST or WS_EX_NOACTIVATE;
      WndParent := GetDesktopwindow;
    end
    else if not Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle and not WS_EX_APPWINDOW;
    end;
  end;
end;

procedure TfrmAvroMouse.DetectLeftClickOnTitleBar(var Msg: TWMNCLButtonDown);
begin
  if (Msg.HitTest = htCaption) then
    SetForegroundWindow(Self.Handle);
  inherited;
end;

procedure TfrmAvroMouse.DetectRightClickOnTitleBar(var Msg: TWMNCLButtonDown);
begin
  if (Msg.HitTest = htCaption) then
    SetForegroundWindow(Self.Handle);
  inherited;
end;

procedure TfrmAvroMouse.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if Self.Top >= 0 then
    AvroMousePosX := intToStr(Self.Top);
  if Self.Left >= 0 then
    AvroMousePosY := intToStr(Self.Left);

  Action := caFree;

  frmAvroMouse := nil;
end;

procedure TfrmAvroMouse.FormCreate(Sender: TObject);
begin
  try
    if (StrToInt(AvroMousePosX) > Screen.Width) or (StrToInt(AvroMousePosX) < 0) then
      AvroMousePosX := '0';
    if (StrToInt(AvroMousePosY) > Screen.Height) or (StrToInt(AvroMousePosY) < 0) then
      AvroMousePosY := '0';

    Self.Top := StrToInt(AvroMousePosX);
    Self.Left := StrToInt(AvroMousePosY);
  except
    on E: Exception do
    begin
      AvroMousePosX := '0';
      AvroMousePosY := '0';
      Self.Top := 0;
      Self.Left := 0;
    end;
  end;

  { Once per window: the runtime glyph path only reads the pre-baked SVGs, but
    the font still has to be registered before the first bake, and registering
    it from RegenerateGlyphs would add a font reference on every theme switch. }
  EnsureBanglaFont;
  RegenerateGlyphs;
end;

procedure TfrmAvroMouse.EnsureBanglaFont;
var
  Path: string;
begin
  Path := BanglaFontFile;
  if Path <> '' then
    AddFontResourceEx(PChar(Path), FR_PRIVATE, nil);
end;

function TfrmAvroMouse.BanglaFontFile: string;
var
  ExeDir: string;
  I: Integer;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  for I := 0 to 3 do
  begin
    case I of
      0: Result := ExeDir + 'kalpurush.ttf';
      1: Result := ExeDir + 'fonts\kalpurush.ttf';
      2: Result := ExeDir + '..\assets\fonts\kalpurush.ttf';
      3: Result := GetAvroDataDir + 'fonts\kalpurush.ttf';
    end;
    if FileExists(Result) then
      Exit;
  end;
  Result := '';
end;

function TfrmAvroMouse.DisplayTextOf(const ABtn: TBitBtn): string;
begin
  if (ABtn.Tag = $200C) or (ABtn.Tag = $200D) then
    Result := ''
  else if ABtn.Tag <> 0 then
    Result := WideChar(ABtn.Tag)
  else if ABtn.Name = 'But_KSs' then
    Result := b_K + b_Hasanta + b_Ss
  else if ABtn.Name = 'But_NGK' then
    Result := b_NGA + b_Hasanta + b_K
  else if ABtn.Name = 'But_NgG' then
    Result := b_NGA + b_Hasanta + b_G
  else if ABtn.Name = 'But_JNYA' then
    Result := b_J + b_Hasanta + b_NYA
  else if ABtn.Name = 'But_NYAC' then
    Result := b_NYA + b_Hasanta + b_C
  else if ABtn.Name = 'But_NYACh' then
    Result := b_NYA + b_Hasanta + b_CH
  else if ABtn.Name = 'But_NYAJ' then
    Result := b_NYA + b_Hasanta + b_J
  else if ABtn.Name = 'But_T_T' then
    Result := b_T + b_Hasanta + b_T
  else if ABtn.Name = 'But_SsNYA' then
    Result := b_Ss + b_Hasanta + b_Nn
  else if ABtn.Name = 'But_HM' then
    Result := b_H + b_Hasanta + b_M
  else if ABtn.Name = 'But_ND' then
    Result := b_Nn + b_Hasanta + b_Dd
  else if ABtn.Name = 'But_ZFola' then
    Result := b_Hasanta + b_Z
  else if ABtn.Name = 'But_RFola' then
    Result := b_Hasanta + b_R
  else
    Result := '';
end;

function TfrmAvroMouse.ThemeColor(const ASysColor: TColor): TColor;
begin
  { ColorToRGB, because GetSystemColor answers with the system-colour CONSTANT
    itself when the active style does not override it (Vcl.Styles
    TCustomStyle.DoGetSystemColor: SysColors[Color], and the constant when that
    is clNone) - and GetRValue/GetGValue/GetBValue on such a value (clBtnText is
    $80000012) read garbage, which would tint every glyph black. Both embedded
    styles define clBtnText and clBtnFace, so today this only guards the
    platform-default fallback; it costs nothing and removes the trap. }
  Result := ColorToRGB(TStyleManager.ActiveStyle.GetSystemColor(ASysColor));
end;

{ The ink and the antialiasing colour every glyph bitmap is made of, resolved
  through ThemeColor so the colour rules live in exactly one place. }
function TfrmAvroMouse.GlyphInkColor: TColor;
begin
  Result := ThemeColor(clBtnText);
end;

function TfrmAvroMouse.GlyphFaceColor: TColor;
begin
  Result := ThemeColor(clBtnFace);
end;

{ Bakes the glyphs again when the colours they are made of have changed.
  Nothing else about them depends on the theme, and re-baking 105 SVG files is
  the expensive part of a style switch, so this must not run for a
  CM_STYLECHANGED that left the colours alone (a Windows theme change announces
  itself to every window even while a forced LIGHT/DARK theme ignores it). }
procedure TfrmAvroMouse.EnsureGlyphsMatchTheme;
begin
  if (FBakedInk = GlyphInkColor) and (FBakedFace = GlyphFaceColor) then
    Exit;
  RegenerateGlyphs;
end;

procedure TfrmAvroMouse.CMStyleChanged(var Message: TMessage);
begin
  { The Bangla characters are bitmaps with the style's button colours baked in
    (AssignSvgGlyph), assigned once in FormCreate. Without this handler a style
    switch repaints the button FACES in the new style while the bitmaps keep the
    old theme's ink: white characters on the light style's near-white buttons,
    i.e. invisible - the bug this exists for.

    Timing follows TfrmOptions.CMStyleChanged: this message reaches the form
    after the style engine has recreated the form's window and broadcast
    CM_STYLECHANGED to every child, so re-baking here and then forcing one
    erased repaint of the whole window puts the keyboard in the new style in a
    single pass instead of control by control. }
  EnsureGlyphsMatchTheme;
  if HandleAllocated then
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

function TfrmAvroMouse.MouseGlyphDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'mouse-glyphs\';
end;

function TfrmAvroMouse.AssetMouseGlyphDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..\assets\mouse-glyphs\';
end;

procedure TfrmAvroMouse.BakeSvgGlyph(const ABtn: TBitBtn; const AText: string);
var
  W, H: Integer;
  FontFile: string;
  Typeface: ISkTypeface;
  Provider: ISkTypefaceFontProvider;
  ParStyle: ISkParagraphStyle;
  TextStyle: ISkTextStyle;
  Builder: ISkParagraphBuilder;
  Par: ISkParagraph;
  SizePx: Single;
  S: string;
  NeedBase: Boolean;
  Stream: TMemoryStream;
  SvgCanvas: ISkCanvas;
  Metrics: TSkMetrics;
  OffsetX, OffsetY: Single;
  Buf: TBytes;
  SvgStr: string;

  function IsCombiningMark(C: WideChar): Boolean;
  begin
    Result := (C = #$0981) or (C = #$09BC) or
      ((C >= #$09BE) and (C <= #$09C4)) or
      (C = #$09C7) or (C = #$09C8) or
      (C = #$09CB) or (C = #$09CC) or
      (C = #$09CD) or (C = #$09D7) or
      (C = #$09E2) or (C = #$09E3);
  end;

begin
  if (AText = '') or (ABtn.ClientWidth <= 0) or (ABtn.ClientHeight <= 0) then
    Exit;
  W := ABtn.ClientWidth;
  H := ABtn.ClientHeight;

  FontFile := BanglaFontFile;
  if FontFile = '' then
    Exit;

  Typeface := TSkTypeface.MakeFromFile(FontFile, 0);
  if Typeface = nil then
    Exit;

  Provider := TSkTypefaceFontProvider.Create;
  Provider.RegisterTypeface(Typeface, 'Kalpurush');

  NeedBase := IsCombiningMark(AText[1]);
  if NeedBase then
    S := b_K + AText
  else
    S := AText;

  ParStyle := TSkParagraphStyle.Create;
  TextStyle := TSkTextStyle.Create;
  TextStyle.SetFontFamilies(['Kalpurush']);
  TextStyle.SetColor($FF000000);

  { Find the largest font size whose shaped text fits inside the button box. }
  SizePx := H;
  Par := nil;
  while SizePx >= 5 do
  begin
    TextStyle.SetFontSize(SizePx);
    Builder := TSkParagraphBuilder.Create(ParStyle, Provider, True);
    Builder.PushStyle(TextStyle);
    Builder.AddText(S);
    Builder.Pop;
    Par := Builder.Build;
    Par.Layout(W);
    if (Par.LongestLine <= W) and (Par.Height <= H) then
      Break;
    SizePx := SizePx - 1;
  end;

  if (Par = nil) or (Length(Par.LineMetrics) = 0) then
    Exit;
  Metrics := Par.LineMetrics[0];

  { Center the single line inside the button box. Paint(AX, AY) places the
    paragraph layout origin at (AX, AY), so we offset by half the slack. }
  OffsetX := (W - Metrics.Width) / 2 - Metrics.Left;
  OffsetY := (H - Metrics.Height) / 2;

  Stream := TMemoryStream.Create;
  try
    SvgCanvas := TSkSVGCanvas.Make(RectF(0, 0, W, H), Stream,
      [TSkSVGCanvasFlag.ConvertTextToPaths, TSkSVGCanvasFlag.NoPrettyXML,
       TSkSVGCanvasFlag.RelativePathEncoding]);
    try
      Par.Paint(SvgCanvas, OffsetX, OffsetY);
    finally
      SvgCanvas := nil;
    end;
    ForceDirectories(AssetMouseGlyphDir);

    { Round path coordinates to 2 decimal places - Skia emits full float32
      precision (~17 chars per number) which bloats the SVG for no visual
      benefit at these small viewBox sizes. }
    Stream.Position := 0;
    SetLength(Buf, Stream.Size);
    Stream.ReadBuffer(Pointer(Buf)^, Stream.Size);
    SvgStr := TEncoding.UTF8.GetString(Buf);
    SvgStr := TRegEx.Replace(SvgStr, '(\d+\.\d{2})\d+', '$1');
    TFile.WriteAllText(AssetMouseGlyphDir + ABtn.Name + '.svg', SvgStr, TEncoding.UTF8);
  finally
    Stream.Free;
  end;
end;

procedure TfrmAvroMouse.AssignSvgGlyph(const ABtn: TBitBtn; const ASvgPath: string);
const
  MaskColor = clFuchsia;
var
  W, H: Integer;
  InkC, FaceC: TColor;
  InR, InG, InB: Byte;
  FaR, FaG, FaB: Byte;
  DOM: ISkSVGDOM;
  Surface: ISkSurface;
  Pixmap: ISkPixmap;
  X, Y, Alpha: Integer;
  Px: PByte;
  KP: PByteArray;
  Key: TBitmap;
begin
  W := ABtn.ClientWidth;
  H := ABtn.ClientHeight;
  if (W <= 0) or (H <= 0) then
    Exit;

  DOM := TSkSVGDOM.MakeFromFile(ASvgPath);
  if DOM = nil then
    Exit;

  InkC := GlyphInkColor;
  InR := GetRValue(InkC);  InG := GetGValue(InkC);  InB := GetBValue(InkC);
  FaceC := GlyphFaceColor;
  FaR := GetRValue(FaceC);  FaG := GetGValue(FaceC);  FaB := GetBValue(FaceC);

  Surface := TSkSurface.MakeRaster(W, H);
  Surface.Canvas.Clear($00000000);
  DOM.SetContainerSize(TSizeF.Create(W, H));
  DOM.Render(Surface.Canvas);
  Pixmap := Surface.PeekPixels;
  if Pixmap = nil then
    Exit;

  Key := TBitmap.Create;
  try
    Key.PixelFormat := pf32bit;
    Key.Width       := W;
    Key.Height      := H;
    Key.Canvas.Brush.Color := MaskColor;
    Key.Canvas.FillRect(Rect(0, 0, W, H));

    for Y := 0 to H - 1 do
    begin
      KP := Key.ScanLine[Y];
      for X := 0 to W - 1 do
      begin
        Px := PByte(Pixmap.GetPixelAddr(X, Y));
        Alpha := PByte(NativeUInt(Px) + 3)^;
        if Alpha = 0 then
        begin
          KP[X * 4]     := $FF;
          KP[X * 4 + 1] := 0;
          KP[X * 4 + 2] := $FF;
        end
        else
        begin
          KP[X * 4]     := (Alpha * InB + (255 - Alpha) * FaB) div 255;
          KP[X * 4 + 1] := (Alpha * InG + (255 - Alpha) * FaG) div 255;
          KP[X * 4 + 2] := (Alpha * InR + (255 - Alpha) * FaR) div 255;
        end;
      end;
    end;

    Key.Canvas.Pixels[0, H - 1]     := MaskColor;
    Key.Canvas.Pixels[W - 1, H - 1] := MaskColor;
    Key.Canvas.Pixels[0, 0]         := MaskColor;

    ABtn.Glyph.Assign(Key);
    ABtn.Glyph.Transparent      := True;
    ABtn.Glyph.TransparentColor := MaskColor;
  finally
    Key.Free;
  end;
end;

procedure TfrmAvroMouse.RenderGlyph(const ABtn: TBitBtn; const AText: string);
var
  Path: string;
begin
  if (AText = '') or (ABtn.ClientWidth <= 0) or (ABtn.ClientHeight <= 0) then
    Exit;

  Path := MouseGlyphDir + ABtn.Name + '.svg';
  if not FileExists(Path) then
    Path := AssetMouseGlyphDir + ABtn.Name + '.svg';
  if FileExists(Path) then
    AssignSvgGlyph(ABtn, Path);
end;


procedure TfrmAvroMouse.RegenerateGlyphs;
var
  I: Integer;
  Btn:  TBitBtn;
  Display: string;
begin
  { What the bitmaps below are baked with, so EnsureGlyphsMatchTheme can tell a
    real colour change from a CM_STYLECHANGED that changed nothing. }
  FBakedInk  := GlyphInkColor;
  FBakedFace := GlyphFaceColor;

  for I := 0 to ComponentCount - 1 do
    if Components[I] is TBitBtn then
    begin
      Btn     := TBitBtn(Components[I]);
      Display := DisplayTextOf(Btn);
      if Display <> '' then
        RenderGlyph(Btn, Display);
    end;
end;

procedure TfrmAvroMouse.TypeIt(const tStr: string);
begin
  SendKey_Char(tStr);
end;

end.
