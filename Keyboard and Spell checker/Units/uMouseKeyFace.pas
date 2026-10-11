{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================

  The face of one Bangla key on the mouse keyboard ("Avro Mouse - Click 'n' Type").

  Those keys used to carry pre-baked glyph bitmaps: a Kalpurush outline was
  rasterized once with the theme's colours already inside the pixels. That made a
  theme switch leave the previous ink behind (the form re-baked all 105 glyphs so
  the letters would not go white-on-near-white) and it is what made the letters
  look soft, because a raster baked for one box size is drawn at another.

  A key IS its character, so the character is now the button's CAPTION, in the
  first Bangla face this machine can actually draw, and Windows shapes it: Bengali
  conjuncts are GSUB substitutions and kar reordering, which GDI does and Image32's
  own text engine does not. Nothing is baked here - the VCL style paints the caption
  with the live ink on every paint, so a theme switch is correct by construction.

  The DFM's baked bitmaps stay as the last resort for a machine with no Bangla font
  at all (mkfBitmap). They are tinted with the live ink, so they remain visible on
  the dark theme too. That tier is not expected to run - Windows 8 and later ship
  Nirmala UI - it exists so a bare build still shows the keyboard.
}

{$INCLUDE ../../ProjectDefines.inc}

unit uMouseKeyFace;

interface

uses
  Vcl.Graphics,
  Vcl.Buttons;

type
  { Ordered from the bundled faces to the ones Windows ships, ending in the baked
    bitmap that needs no font at all. PickMouseKeyFace returns the first usable
    entry. }
  TMouseKeyFace = (
    mkfKalpurush,
    mkfSiyamRupali,
    mkfNirmalaUI,
    mkfVrinda,
    mkfBitmap);

const
  MouseKeyFaceFamily: array[TMouseKeyFace] of string = (
    'Kalpurush',
    'Siyam Rupali',
    'Nirmala UI',
    'Vrinda',
    '');

  { Caption sizes tried for a key, largest first: the caption is shrunk until it
    fits the key's client box, so the plain keys and the wide conjunct keys both
    come out filled instead of clipped. }
  MOUSE_KEY_MAX_FONT_H = 22;
  MOUSE_KEY_MIN_FONT_H = 8;

  { TextHeight answers with the font's line box, which is taller than the ink a
    Bangla consonant actually covers; this much slack lets the ink reach the key's
    edges the way the packed glyphs did. }
  MOUSE_KEY_LINE_SLACK = 7;

function MouseKeyFaceLabel(const AFace: TMouseKeyFace): string;

{ True when GDI hands the requested family back instead of substituting one.
  Instantiating the family and reading the selected face name is the only test that
  also covers a face this process registered privately (FR_PRIVATE), which is how
  the portable build supplies Siyam Rupali. }
function FontFamilyUsable(const AFamily: string): Boolean;

{ Registers the bundled font file privately, then returns the first usable face.
  ABundledFontFile may be '' when the caller could not find one. }
function PickMouseKeyFace(const ABundledFontFile: string): TMouseKeyFace;

{ Makes one key show AText under AFace. Tiers 1-4 caption the button and clear its
  glyph; mkfBitmap keeps the glyph and clears the caption. Does nothing for an
  empty AText, so the keys that show nothing stay empty. }
procedure ApplyMouseKeyFace(const ABtn: TBitBtn; const AText: string;
  const AFace: TMouseKeyFace);

{ Recolours a key's baked glyph to AInk, keeping its face transparent. A copy is
  tinted and assigned back, so tinting stays idempotent across theme changes. }
procedure TintMouseKeyGlyph(const ABtn: TBitBtn; const AInk: TColor);

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Themes,
  DebugLog;

type
  { Winapi.Windows declares a TBitmap of its own - the Win32 BITMAP record - and a
    unit in an implementation uses clause shadows the interface's Vcl.Graphics
    bitmap with it, so the bitmap this unit builds carries its own name here. }
  TGlyphBitmap = Vcl.Graphics.TBitmap;

function MouseKeyFaceLabel(const AFace: TMouseKeyFace): string;
begin
  if AFace = mkfBitmap then
    Result := 'baked bitmaps (no Bangla font usable)'
  else
    Result := MouseKeyFaceFamily[AFace];
end;

function FontFamilyUsable(const AFamily: string): Boolean;
var
  DC: HDC;
  Font, OldFont: HGDIOBJ;
  LF: TLogFontW;
  Selected: array[0..LF_FACESIZE - 1] of WideChar;
begin
  Result := False;
  if AFamily = '' then
    Exit;

  DC := CreateCompatibleDC(0);
  if DC = 0 then
    Exit;
  try
    FillChar(LF, SizeOf(LF), 0);
    LF.lfHeight := -12;
    LF.lfCharSet := DEFAULT_CHARSET;
    Move(PWideChar(AFamily)^, LF.lfFaceName[0], Length(AFamily) * SizeOf(Char));

    Font := CreateFontIndirectW(LF);
    if Font = 0 then
      Exit;
    try
      OldFont := SelectObject(DC, Font);
      try
        FillChar(Selected, SizeOf(Selected), 0);
        GetTextFaceW(DC, LF_FACESIZE, @Selected[0]);
        Result := SameText(string(Selected), AFamily);
      finally
        SelectObject(DC, OldFont);
      end;
    finally
      DeleteObject(Font);
    end;
  finally
    DeleteDC(DC);
  end;
end;

{ The ink the active VCL style draws text with. ColorToRGB because
  TCustomStyle.GetSystemColor answers with the system-colour CONSTANT when the
  style does not override it, and reading RGB out of such a value gives garbage. }
function StyleInkColor: TColor;
begin
  Result := ColorToRGB(TStyleManager.ActiveStyle.GetSystemColor(clBtnText));
end;

function PickMouseKeyFace(const ABundledFontFile: string): TMouseKeyFace;
var
  Face: TMouseKeyFace;
begin
  { Registering the bundled face first is what makes tier 1 work in a portable
    build: nothing installed it there, and only this process can see it. }
  if (ABundledFontFile <> '') and FileExists(ABundledFontFile) then
    AddFontResourceEx(PChar(ABundledFontFile), FR_PRIVATE, nil);

  for Face := Low(TMouseKeyFace) to High(TMouseKeyFace) do
    if (Face <> mkfBitmap) and FontFamilyUsable(MouseKeyFaceFamily[Face]) then
    begin
      StartupLog('mouse keyboard face: ' + MouseKeyFaceLabel(Face));
      Exit(Face);
    end;

  StartupLog('mouse keyboard face: ' + MouseKeyFaceLabel(mkfBitmap));
  Result := mkfBitmap;
end;

{ Measures the caption on a memory DC rather than through ABtn.Canvas: TWinControl's
  Canvas is protected, and the measurement only has to answer whether the string
  fits, so the control's own paint surface is not needed. Unshaped GDI extents are
  the right answer here - they never come out narrower than the shaped run, so the
  size chosen can only err towards fitting. }
function CaptionFits(const ADC: HDC; const ABtn: TBitBtn; const AText: string): Boolean;
var
  Extent: TSize;
begin
  Result := GetTextExtentPoint32W(ADC, PWideChar(AText), Length(AText), Extent);
  if not Result then
    Exit;
  Result := (Extent.cx <= ABtn.ClientWidth) and
    (Extent.cy <= ABtn.ClientHeight + MOUSE_KEY_LINE_SLACK);
end;

function FittingFontHeight(const ABtn: TBitBtn; const AText: string): Integer;
var
  H: Integer;
  DC: HDC;
  OldFont: HGDIOBJ;
begin
  Result := MOUSE_KEY_MIN_FONT_H;
  DC := CreateCompatibleDC(0);
  if DC = 0 then
    Exit;
  try
    for H := MOUSE_KEY_MAX_FONT_H downto MOUSE_KEY_MIN_FONT_H do
    begin
      ABtn.Font.Height := -H;
      OldFont := SelectObject(DC, ABtn.Font.Handle);
      try
        if CaptionFits(DC, ABtn, AText) then
        begin
          Result := H;
          Exit;
        end;
      finally
        SelectObject(DC, OldFont);
      end;
    end;
  finally
    DeleteDC(DC);
  end;
end;

procedure ClearGlyph(const ABtn: TBitBtn);
begin
  if (ABtn.Glyph <> nil) and (ABtn.Glyph.Width > 0) then
    ABtn.Glyph.SetSize(0, 0);
end;

procedure TintMouseKeyGlyph(const ABtn: TBitBtn; const AInk: TColor);
var
  Src: TGlyphBitmap;
  X, Y: Integer;
  Background: TColor;
begin
  if (ABtn.Glyph = nil) or ABtn.Glyph.Empty then
    Exit;

  Src := TGlyphBitmap.Create;
  try
    Src.Assign(ABtn.Glyph);
    { These baked glyphs carry their face in the top-left corner pixel. }
    Background := Src.Canvas.Pixels[0, 0];
    for Y := 0 to Src.Height - 1 do
      for X := 0 to Src.Width - 1 do
        if Src.Canvas.Pixels[X, Y] <> Background then
          Src.Canvas.Pixels[X, Y] := AInk;

    ABtn.Glyph.Assign(Src);
    ABtn.Glyph.Transparent := True;
    ABtn.Glyph.TransparentColor := Background;
  finally
    Src.Free;
  end;
end;

procedure ApplyMouseKeyFace(const ABtn: TBitBtn; const AText: string;
  const AFace: TMouseKeyFace);
begin
  if (ABtn = nil) or (AText = '') then
    Exit;

  if AFace = mkfBitmap then
  begin
    { Nothing to caption with, so the key keeps its packed bitmap - re-tinted with
      the live ink, or it would vanish on the dark theme. }
    ABtn.Caption := '';
    TintMouseKeyGlyph(ABtn, StyleInkColor);
    Exit;
  end;

  ClearGlyph(ABtn);
  ABtn.Font.Name := MouseKeyFaceFamily[AFace];
  ABtn.Font.Height := -FittingFontHeight(ABtn, AText);
  ABtn.Caption := AText;
end;

end.
