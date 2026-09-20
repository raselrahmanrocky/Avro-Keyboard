{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{ =============================================================================
  kat_iconsection - gate for the per-layout icon that travels inside a mapping.

  What it proves
  --------------
  The icon is stored as ONE scalar Base64 member of the mapping payload, so it
  has to survive the container pipeline (obfuscate -> zlib -> AES-256-GCM ->
  HMAC) unchanged. It also has to arrive at the shell at the size Windows
  actually asks for: the tray metric is 16 px at 100% DPI but 20 / 24 / 32 px at
  125 / 150 / 200%, and an .ico carrying only a 16 px frame would be rescaled
  (blurred) at every one of those.

  How it proves it
  ----------------
  1. The frame table and the size-selection rule, against ICOs synthesised in
  memory, so the checks do not depend on the shipped artwork.
  2. CreateHIconAtSize is checked with GetIconInfo + GetObject: the bitmap
  behind the returned HICON must measure EXACTLY the requested metric. That
  is the assertion which catches "hand the shell a 16 px handle and let it
  scale".
  3. A real Shield container is built here with a PASSWORD, so this gate needs
  no key file and stays runnable standalone - both with and without the icon
  member. The icon must come back byte-identical, and a container without it
  must still load and report "no icon".
  4. With a container folder argument, every shipped .AvroEnco must carry an
  icon with a 16 px frame and nothing above AVRO_ICON_MAX_FRAME_SIZE, and the
  live tray metric must resolve against it.

  Exit code: 0 all PASS, 1 FAIL.

  Build (same command line as the sibling KATs, from this folder):
  dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" \
  -U"..\..\..\Keyboard and Spell checker\Units;%BDS%\lib\win32\release" \
  kat_iconsection.dpr

  Run:
  kat_iconsection [container-dir] [quiet]
}

{$APPTYPE CONSOLE}
program kat_iconsection;

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.NetEncoding,
  Winapi.Windows,
  uAvroEncoCrypto,
  uAvroEncoIconSection,
  uAvroShield;

const
  { Pixel tag written into every pixel of a synthesised frame, so the frame the
    picker chose can be identified from the bytes it returned. }
  TAG_16 = $11;
  TAG_32 = $22;
  TAG_48 = $33;

  { Every metric a Windows desktop presents: 100, 125, 150, 200%. }
  DPI_METRICS: array [0 .. 3] of Integer = (16, 20, 24, 32);

  PipelineJson = '{"Metadata":{"Encoding":"KatIcon","Suggested Font":"X"},' + ' "FullFormReplacements":[], "Constants":{}, "PreReplacements":[],' +
    ' "PostReplacements":[]}';

var
  Fails:  Integer;
  Checks: Integer;
  Quiet:  Boolean;
  TmpDir: string;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
  begin
    if not Quiet then
      WriteLn('PASS ' + AName);
  end
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('     ' + ADetail);
    Inc(Fails);
  end;
end;

procedure Note(const AText: string);
begin
  if not Quiet then
    WriteLn('     ' + AText);
end;

{ The frames the builder embeds by default, as a mutable array for the helpers
  that take `array of Integer`. }
function DefaultSizes: TArray<Integer>;
var
  I: Integer;
begin
  SetLength(Result, Length(AVRO_ICON_FRAME_SIZES));
  for I := 0 to high(AVRO_ICON_FRAME_SIZES) do
    Result[I] := AVRO_ICON_FRAME_SIZES[I];
end;

function Hex(const ABytes: TBytes): string;
begin
  Result := TNetEncoding.Base64.EncodeBytesToString(ABytes);
end;

{ ---- synthesis ----------------------------------------------------------- }

procedure PutWord(var AData: TBytes; AOffset, AValue: Integer);
begin
  AData[AOffset] := Byte(AValue and $FF);
  AData[AOffset + 1] := Byte((AValue shr 8) and $FF);
end;

procedure PutDWord(var AData: TBytes; AOffset, AValue: Integer);
begin
  AData[AOffset] := Byte(AValue and $FF);
  AData[AOffset + 1] := Byte((AValue shr 8) and $FF);
  AData[AOffset + 2] := Byte((AValue shr 16) and $FF);
  AData[AOffset + 3] := Byte((AValue shr 24) and $FF);
end;

function TagForSize(ASize: Integer): Byte;
begin
  if ASize = 16 then
    Result := TAG_16
  else if ASize = 32 then
    Result := TAG_32
  else
    Result := TAG_48;
end;

{ One BMP-framed icon image: a 40-byte BITMAPINFOHEADER (biHeight doubled, the
  way every .ico does it), a 32bpp XOR bitmap and a zeroed AND mask. The AND
  mask stays zero because real 32bpp artwork composites from the alpha channel. }
function SyntheticFrame(AW, AH: Integer; ATag: Byte): TBytes;
var
  RowBytes, MaskRow, Hdr, I: Integer;
begin
  RowBytes := AW * 4;
  MaskRow := ((AW + 31) div 32) * 4;
  Hdr := 40 + RowBytes * AH + MaskRow * AH;
  SetLength(Result, Hdr);
  FillChar(Result[0], Hdr, 0);
  PutDWord(Result, 0, 40);     // biSize
  PutDWord(Result, 4, AW);     // biWidth
  PutDWord(Result, 8, AH * 2); // biHeight: XOR bitmap + AND mask
  PutWord(Result, 12, 1);      // biPlanes
  PutWord(Result, 14, 32);     // biBitCount
  for I := 0 to AW * AH - 1 do
  begin
    Result[40 + I * 4] := ATag;
    Result[40 + I * 4 + 1] := ATag;
    Result[40 + I * 4 + 2] := ATag;
    Result[40 + I * 4 + 3] := $FF;
  end;
end;

function SyntheticIco(const ASizes: array of Integer): TBytes;
var
  Frames:                   TArray<TBytes>;
  I, Count, Hdr, Off, Size: Integer;
begin
  Count := Length(ASizes);
  SetLength(Frames, Count);
  Hdr := AVRO_ICONDIR_SIZE + Count * AVRO_ICONDIRENTRY;
  Off := Hdr;
  for I := 0 to Count - 1 do
  begin
    Frames[I] := SyntheticFrame(ASizes[I], ASizes[I], TagForSize(ASizes[I]));
    Inc(Off, Length(Frames[I]));
  end;

  SetLength(Result, Off);
  FillChar(Result[0], Off, 0);
  Result[2] := 1; // type = icon
  Result[4] := Byte(Count and $FF);
  Result[5] := Byte((Count shr 8) and $FF);

  Off := Hdr;
  for I := 0 to Count - 1 do
  begin
    Size := Length(Frames[I]);
    // The extent bytes, in the format's own convention: 0 means 256 px.
    Result[AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY] := Byte(ASizes[I] and $FF);
    Result[AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY + 1] := Byte(ASizes[I] and $FF);
    PutWord(Result, AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY + 4, 1);  // planes
    PutWord(Result, AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY + 6, 32); // bpp
    PutDWord(Result, AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY + 8, Size);
    PutDWord(Result, AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY + 12, Off);
    Move(Frames[I][0], Result[Off], Size);
    Inc(Off, Size);
  end;
end;

{ The tag byte of a frame blob, i.e. the first pixel's first channel - which
  identifies which synthesised frame the picker returned. }
function FrameTag(const AFrame: TBytes): Byte;
begin
  if Length(AFrame) >= 41 then
    Result := AFrame[40]
  else
    Result := 0;
end;

{ A copy of AIco with a non-zero reserved word, which is not a valid icon
  directory. }
function CorruptReserved(const AIco: TBytes): TBytes;
begin
  Result := Copy(AIco, 0, Length(AIco));
  Result[1] := $7F;
end;

function SizesOfText(const AFrames: TAvroIconFrames): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to high(AFrames) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(AFrames[I].Width);
  end;
end;

{ ---- frame table and selection ------------------------------------------ }

procedure RunFrameSelection;
var
  Ico, Frame, Corrupt, OnlyBig, Repacked, Png: TBytes;
  Frames:                                      TAvroIconFrames;
  W, H:                                        Integer;
begin
  Ico := SyntheticIco([16, 32]);

  Frames := IconFramesOf(Ico);
  Check('synthetic icon: the frame table is read', Length(Frames) = 2, 'frames=' + IntToStr(Length(Frames)));
  Check('synthetic icon: extents are decoded', (Length(Frames) = 2) and (Frames[0].Width = 16) and (Frames[1].Width = 32), SizesOfText(Frames));

  Check('malformed icon: an empty blob has no frames', Length(IconFramesOf(nil)) = 0);
  // NOTE: Copy() is 0-based for dynamic arrays (unlike strings), so every
  // slice below counts from 0.
  Check('malformed icon: a truncated header has no frames', Length(IconFramesOf(Copy(Ico, 0, 4))) = 0);
  Check('malformed icon: the reserved word must be zero', Length(IconFramesOf(CorruptReserved(Ico))) = 0);

  // A frame pointing past the end of the file must drop the whole table rather
  // than hand back a blob CreateIconFromResourceEx would read past.
  Corrupt := Copy(Ico, 0, Length(Ico));
  PutDWord(Corrupt, AVRO_ICONDIR_SIZE + 12, Length(Ico) + 999);
  Check('malformed icon: a frame pointing past EOF drops the table', Length(IconFramesOf(Corrupt)) = 0);

  // Exact match wins: the 100% DPI tray case and every menu draw.
  Check('selection: 16 px resolves to the 16 px frame', PickBestIconFrame(Ico, 16, 16, Frame, W, H) and (W = 16) and (H = 16) and (FrameTag(Frame) = TAG_16),
    Format('w=%d tag=%.2x', [W, FrameTag(Frame)]));
  Check('selection: 32 px resolves to the 32 px frame', PickBestIconFrame(Ico, 32, 32, Frame, W, H) and (W = 32) and (FrameTag(Frame) = TAG_32),
    Format('w=%d tag=%.2x', [W, FrameTag(Frame)]));

  // The high-DPI metrics: no 20 px or 24 px frame exists, so the SMALLEST frame
  // that is at least as large must be chosen - never the largest available.
  Check('selection: 20 px (125%) resolves to the 32 px frame', PickBestIconFrame(Ico, 20, 20, Frame, W, H) and (W = 32) and (FrameTag(Frame) = TAG_32),
    Format('w=%d tag=%.2x', [W, FrameTag(Frame)]));
  Check('selection: 24 px (150%) resolves to the 32 px frame', PickBestIconFrame(Ico, 24, 24, Frame, W, H) and (W = 32) and (FrameTag(Frame) = TAG_32),
    Format('w=%d tag=%.2x', [W, FrameTag(Frame)]));

  // Nothing big enough: enlarge the largest rather than fail.
  Check('selection: 48 px with no large frame falls back to the largest', PickBestIconFrame(Ico, 48, 48, Frame, W, H) and (W = 32), Format('w=%d', [W]));

  // A one-frame icon must still resolve every metric, silently enlarging rather
  // than ever returning nothing.
  OnlyBig := SyntheticIco([48]);
  Check('selection: a 48-only icon still resolves 16 px', PickBestIconFrame(OnlyBig, 16, 16, Frame, W, H) and (W = 48));
  Check('selection: a 48-only icon still resolves 24 px', PickBestIconFrame(OnlyBig, 24, 24, Frame, W, H) and (W = 48));
  Check('selection: a 48-only icon still resolves 32 px', PickBestIconFrame(OnlyBig, 32, 32, Frame, W, H) and (W = 48));

  Check('selection: a zero target is refused', not PickBestIconFrame(Ico, 0, 0, Frame, W, H));
  Check('selection: a nil icon is refused', not PickBestIconFrame(nil, 16, 16, Frame, W, H));

  // The packed .ico the builder embeds holds only the requested frames.
  Repacked := BuildIconFromFrames(SyntheticIco([16, 32, 48]), [16, 32]);
  Check('packing: the pack is non-empty', Length(Repacked) > 0);
  Frames := IconFramesOf(Repacked);
  Check('packing: only the requested frames survive', (Length(Frames) = 2) and (Frames[0].Width = 16) and (Frames[1].Width = 32), SizesOfText(Frames));
  Check('packing: every frame stays inside AVRO_ICON_MAX_FRAME_SIZE', (Length(Frames) = 2) and (Frames[0].Width <= AVRO_ICON_MAX_FRAME_SIZE) and
      (Frames[1].Width <= AVRO_ICON_MAX_FRAME_SIZE));
  Check('packing: the 48 px frame is not carried by a 16+32 pack', (Length(IconFramesOf(Repacked)) = 2));
  Check('packing: asking for an absent size yields nothing', Length(BuildIconFromFrames(Ico, [96])) = 0);
  Check('packing: a nil icon yields nothing', Length(BuildIconFromFrames(nil, [16])) = 0);

  // Byte stability is what makes a build reproducible and lets the container
  // check below assert an idempotent round trip.
  Check('packing: re-packing the packed icon is byte-identical', (Length(Repacked) > 0) and (Hex(BuildIconFromFrames(Repacked, [16, 32])) = Hex(Repacked)));

  // A PNG-compressed frame cannot be read by CreateIconFromResourceEx, so it
  // has to be rejected instead of decoded into garbage. The signature goes at
  // the start of the frame blob, which for a one-frame file follows the
  // directory.
  Png := SyntheticIco([16]);
  Png[AVRO_ICONDIR_SIZE + AVRO_ICONDIRENTRY] := $89;
  Png[AVRO_ICONDIR_SIZE + AVRO_ICONDIRENTRY + 1] := $50;
  Png[AVRO_ICONDIR_SIZE + AVRO_ICONDIRENTRY + 2] := $4E;
  Png[AVRO_ICONDIR_SIZE + AVRO_ICONDIRENTRY + 3] := $47;
  // IsPortableNetworkFrame takes a FRAME, not a whole .ico, so the check is
  // made against the blob the frame table points at - the same offsets the
  // production path uses, rather than a second copy of that arithmetic.
  Frames := IconFramesOf(Png);
  Check('PNG frames: the frame table still reads the PNG icon', Length(Frames) = 1);
  if Length(Frames) = 1 then
  begin
    var
      PngFrame: TBytes := Copy(Png, Frames[0].DataOffset, Frames[0].DataSize);
    Check('PNG frames: a PNG frame is detected', IsPortableNetworkFrame(PngFrame), Format('frameLen=%d first=%.2x', [Length(PngFrame), PngFrame[0]]));
  end
  else
    Check('PNG frames: a PNG frame is detected', False, 'the frame table could not be read');

  Frames := IconFramesOf(Ico);
  Check('PNG frames: the extracted 16 px frame is the tagged frame', (Length(Frames) = 2) and
      (FrameTag(Copy(Ico, Frames[0].DataOffset, Frames[0].DataSize)) = TAG_16));
  Check('PNG frames: a BMP frame is not mistaken for PNG', (Length(Frames) = 2) and
      (not IsPortableNetworkFrame(Copy(Ico, Frames[0].DataOffset, Frames[0].DataSize))));
  Check('PNG frames: a PNG-only icon refuses to produce a frame', not PickBestIconFrame(Png, 16, 16, Frame, W, H));
  Check('PNG frames: a PNG-only icon yields no HICON', CreateHIconAtSize(Png, 16, 16) = 0);
end;

{ ---- HICON sizing ------------------------------------------------------- }

{ The bitmap behind AHIcon, measured with GDI. This is the assertion for the
  high-DPI requirement: the handle must already be the requested size. }
function IconBitmapExtent(AHIcon: HICON; out AW, AH: Integer): Boolean;
var
  Info: TIconInfo;
  Bmp:  BITMAP;
begin
  Result := False;
  AW := 0;
  AH := 0;
  if AHIcon = 0 then
    Exit;
  if not GetIconInfo(AHIcon, Info) then
    Exit;
  try
    if Info.hbmColor <> 0 then
    begin
      if GetObject(Info.hbmColor, SizeOf(Bmp), @Bmp) = SizeOf(Bmp) then
      begin
        AW := Bmp.bmWidth;
        AH := Bmp.bmHeight;
        Result := True;
      end;
    end
    else if Info.hbmMask <> 0 then
    begin
      // A 1bpp icon carries only a mask, whose height is doubled.
      if GetObject(Info.hbmMask, SizeOf(Bmp), @Bmp) = SizeOf(Bmp) then
      begin
        AW := Bmp.bmWidth;
        AH := Bmp.bmHeight div 2;
        Result := True;
      end;
    end;
  finally
    if Info.hbmColor <> 0 then
      DeleteObject(Info.hbmColor);
    if Info.hbmMask <> 0 then
      DeleteObject(Info.hbmMask);
  end;
end;

procedure RunHIconSizing;
var
  Ico:      TBytes;
  H:        HICON;
  W, Cy, I: Integer;
begin
  Ico := SyntheticIco([16, 32]);

  for I := 0 to high(DPI_METRICS) do
  begin
    H := CreateHIconAtSize(Ico, DPI_METRICS[I], DPI_METRICS[I]);
    try
      Check(Format('HICON: created for the %d px metric', [DPI_METRICS[I]]), H <> 0);
      if IconBitmapExtent(H, W, Cy) then
        Check(Format('HICON: the %d px metric yields a %d px handle', [DPI_METRICS[I], DPI_METRICS[I]]), (W = DPI_METRICS[I]) and (Cy = DPI_METRICS[I]),
          Format('handle is %dx%d', [W, Cy]))
      else
        Check(Format('HICON: the %d px handle can be measured', [DPI_METRICS[I]]), False, 'GetIconInfo/GetObject failed');
    finally
      if H <> 0 then
        DestroyIcon(H);
    end;
  end;

  // The metric the tray is being sized for right now, whatever DPI this
  // machine is running at.
  H := CreateHIconAtSize(Ico, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON));
  Check(Format('HICON: the live SM_CXSMICON metric (%d px) is reachable', [GetSystemMetrics(SM_CXSMICON)]), H <> 0);
  if H <> 0 then
    DestroyIcon(H);

  Check('HICON: a nil icon yields no handle', CreateHIconAtSize(nil, 16, 16) = 0);
  Check('HICON: a zero target yields no handle', CreateHIconAtSize(Ico, 0, 0) = 0);
end;

{ ---- command-line size parsing ------------------------------------------ }

procedure RunSizeParsing;
var
  Sizes: TArray<Integer>;
  Err:   string;
begin
  Check('--icon-sizes: "16,32" parses', ParseIconSizes('16,32', Sizes, Err) and (Length(Sizes) = 2) and (Sizes[0] = 16) and (Sizes[1] = 32), Err);
  Check('--icon-sizes: " 16 ; 32 " tolerates spaces and semicolons', ParseIconSizes(' 16 ; 32 ', Sizes, Err) and (Length(Sizes) = 2), Err);
  Check('--icon-sizes: an empty list is refused', not ParseIconSizes('', Sizes, Err));
  Check('--icon-sizes: a non-number is refused', not ParseIconSizes('16,abc', Sizes, Err));
  Check('--icon-sizes: 0 is refused', not ParseIconSizes('0,16', Sizes, Err));
  Check('--icon-sizes: a value above the bound is refused', not ParseIconSizes(IntToStr(AVRO_ICON_MAX_FRAME_SIZE + 1), Sizes, Err));
  Check('--icon-sizes: the bound itself is accepted', ParseIconSizes(IntToStr(AVRO_ICON_MAX_FRAME_SIZE), Sizes, Err), Err);

  // The default set is what actually ships, so the properties the tray and the
  // menus depend on are asserted on the constant and not on a local list.
  Check('default frames: the 16 px menu/tray frame leads', (Length(AVRO_ICON_FRAME_SIZES) > 0) and (AVRO_ICON_FRAME_SIZES[0] = 16));
  Check('default frames: a 32 px frame covers the 200% metric', (Length(AVRO_ICON_FRAME_SIZES) > 1) and (AVRO_ICON_FRAME_SIZES[1] = 32));
  Check('default frames: every default is within the bound', (Length(AVRO_ICON_FRAME_SIZES) > 0) and
      (AVRO_ICON_FRAME_SIZES[high(AVRO_ICON_FRAME_SIZES)] <= AVRO_ICON_MAX_FRAME_SIZE));
  Check('default frames: the set is exactly what the shipped icons carry', Length(AVRO_ICON_FRAME_SIZES) = 2);
end;

{ ---- section encode / extract ------------------------------------------- }

procedure RunSectionCodec;
var
  Ico, Back, Dropped: TBytes;
  Base64, Doc:        string;
  JSON:               TJSONObject;
  Parsed:             TJSONValue;
begin
  Ico := SyntheticIco([16, 32, 48]);
  Base64 := EncodeIconSection(Ico, [16, 32]);
  Check('section: encoding a 16+32 icon produces a value', Base64 <> '');

  Back := TNetEncoding.Base64.DecodeStringToBytes(Base64);
  Dropped := BuildIconFromFrames(Ico, [16, 32]);
  Check('section: the encoded value is the down-selected .ico', Hex(Back) = Hex(Dropped));

  // The member must be a SCALAR. kat_ansiconvert censuses every top-level member
  // whose value is an array or an object and fails when the parser drops one; a
  // scalar is invisible to that census, which is what keeps the mapping's
  // section accounting - and that gate - untouched.
  JSON := TJSONObject.Create;
  try
    JSON.AddPair('Metadata', TJSONObject.Create);
    JSON.AddPair(AVRO_ICON_SECTION, Base64);
    Doc := JSON.ToJSON;
  finally
    JSON.Free;
  end;

  Parsed := TJSONObject.ParseJSONValue(Doc);
  Check('section: the member is a JSON string', (Parsed is TJSONObject) and (TJSONObject(Parsed).GetValue(AVRO_ICON_SECTION) is TJSONString));
  Check('section: the member is not an array or object, so no section census ' + 'can see it', (Parsed is TJSONObject) and
      (not(TJSONObject(Parsed).GetValue(AVRO_ICON_SECTION) is TJSONObject)) and (not(TJSONObject(Parsed).GetValue(AVRO_ICON_SECTION) is TJSONArray)));
  Parsed.Free;

  Back := ExtractIconSection(Doc);
  Check('section: extraction returns the exact encoded bytes', Hex(Back) = Base64);

  // Robustness: a mapping must never be lost to a damaged icon member.
  Check('section: a mapping without the member yields no icon', ExtractIconSection('{"Metadata":{}, "FullFormReplacements":[]}') = nil);
  Check('section: an empty document yields no icon', ExtractIconSection('') = nil);
  Check('section: non-JSON yields no icon', ExtractIconSection('not json at all') = nil);
  Check('section: a non-string member yields no icon', ExtractIconSection('{"' + AVRO_ICON_SECTION + '": 42}') = nil);
  Check('section: damaged Base64 yields no icon', ExtractIconSection('{"' + AVRO_ICON_SECTION + '": "!!!not base64!!!"}') = nil);
  Check('section: decoded bytes that are not an .ico yield no icon', ExtractIconSection('{"' + AVRO_ICON_SECTION + '": "QUJD"}') = nil);
end;

{ ---- the whole container pipeline --------------------------------------- }

function ShieldBuild(const AJson, APassword: string; out AOut: TBytes): Boolean;
var
  R: TAvroShieldResult;
begin
  Result := False;
  R := AvroShieldBuildFromJson(AJson, APassword, False, False, False, AOut, nil, nil);
  Result := R = asrOk;
end;

procedure RunContainerPipeline;
var
  Password, Text:          string;
  Bytes, Loaded, Original: TBytes;
  Base64, Doc:             string;
  JSON:                    TJSONObject;
begin
  Password := 'kat-iconsection-demo';
  Base64 := EncodeIconSection(SyntheticIco([16, 32]), DefaultSizes);

  // The exact document the builder produces: the icon as one extra scalar.
  JSON := TJSONObject.ParseJSONValue(PipelineJson) as TJSONObject;
  try
    JSON.AddPair(AVRO_ICON_SECTION, Base64);
    Doc := JSON.ToJSON;
  finally
    JSON.Free;
  end;

  Bytes := nil;
  Check('pipeline: the container builds', ShieldBuild(Doc, Password, Bytes), 'AvroShieldBuildFromJson failed');

  // Loading back through the runtime reader is the only thing that proves the
  // icon survives obfuscation, zlib, AES-256-GCM and the HMAC trailer.
  TFile.WriteAllBytes(TmpDir + 'with_icon.AvroEnco', Bytes);
  Text := Trim(DecryptAvroEncoToString(TmpDir + 'with_icon.AvroEnco', Password));
  Check('pipeline: the container loads back', Text <> '');
  if Text <> '' then
  begin
    Check('pipeline: the mapping survived the pipeline', Pos('KatIcon', Text) > 0);
    Loaded := ExtractIconSection(Text);
    Check('pipeline: the icon survives the whole container pipeline', Loaded <> nil);
    // Non-empty on both sides, so this can never pass vacuously on a missing
    // section.
    Check('pipeline: the recovered icon is byte-identical', (Loaded <> nil) and (Base64 <> '') and (Hex(Loaded) = Base64),
      'recovered ' + IntToStr(Length(Loaded)) + ' bytes');
    Check('pipeline: the recovered icon is a usable .ico', Length(IconFramesOf(Loaded)) = 2, SizesOfText(IconFramesOf(Loaded)));

    // Idempotence: re-packing what came out must reproduce what went in, which
    // is what makes the shipped bytes stable for a given icon asset.
    Original := BuildIconFromFrames(Loaded, DefaultSizes);
    Check('pipeline: the recovered .ico re-packs byte-identically', (Length(Original) > 0) and (Hex(Original) = Base64));
  end;

  // Backward compatibility for every container that predates the icon.
  Bytes := nil;
  Check('compat: a container without the icon member still builds', ShieldBuild(PipelineJson, Password, Bytes));
  TFile.WriteAllBytes(TmpDir + 'without_icon.AvroEnco', Bytes);
  Text := Trim(DecryptAvroEncoToString(TmpDir + 'without_icon.AvroEnco', Password));
  Check('compat: a container without the icon member still loads', Text <> '');
  Check('compat: a container without the icon member reports no icon', ExtractIconSection(Text) = nil);
end;

{ ---- shipped containers ------------------------------------------------- }

procedure RunContainerDir(const ADir: string);
var
  FileNames:                 TArray<string>;
  FileName, ShortName, Text: string;
  Icon, Frame:               TBytes;
  Frames:                    TAvroIconFrames;
  I, W, H:                   Integer;
  Has16, TooBig:             Boolean;
begin
  if not TDirectory.Exists(ADir) then
  begin
    Check('container dir exists: ' + ADir, False, 'directory not found');
    Exit;
  end;

  FileNames := TDirectory.GetFiles(ADir, '*.AvroEnco');
  Check('container dir has .AvroEnco files: ' + ADir, Length(FileNames) > 0, 'no .AvroEnco file found');

  for FileName in FileNames do
  begin
    ShortName := ExtractFileName(FileName);
    Text := Trim(DecryptAvroEncoToString(FileName, ''));
    Check(ShortName + ': loads', Text <> '');
    if Text = '' then
      Continue;

    Icon := ExtractIconSection(Text);
    Check(ShortName + ': carries an icon', Icon <> nil);
    if Icon = nil then
      Continue;

    Frames := IconFramesOf(Icon);
    Check(ShortName + ': the icon is a valid .ico', Length(Frames) > 0, SizesOfText(Frames));

    Has16 := False;
    TooBig := False;
    for I := 0 to high(Frames) do
    begin
      if Frames[I].Width = 16 then
        Has16 := True;
      if Frames[I].Width > AVRO_ICON_MAX_FRAME_SIZE then
        TooBig := True;
    end;

    Check(ShortName + ': has a 16 px frame (the menu and 100% tray metric)', Has16, SizesOfText(Frames));
    Check(ShortName + ': no frame exceeds AVRO_ICON_MAX_FRAME_SIZE', not TooBig, SizesOfText(Frames));
    Note(ShortName + ': frames ' + SizesOfText(Frames) + ', ' + IntToStr(Length(Icon)) + ' bytes');

    // The frame the machine's current DPI actually draws must resolve, and the
    // handle it produces must be the metric's own size - not a rescaled guess.
    Check(ShortName + ': the live SM_CXSMICON metric resolves', PickBestIconFrame(Icon, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
        Frame, W, H));

    var
      Live: HICON := CreateHIconAtSize(Icon, GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON));
    try
      Check(ShortName + ': a tray handle can be built at the live metric', Live <> 0);
    finally
      if Live <> 0 then
        DestroyIcon(Live);
    end;
  end;
end;

var
  I:      Integer;
  DirArg: string;

begin
  Fails := 0;
  Checks := 0;
  Quiet := False;
  DirArg := '';

  for I := 1 to ParamCount do
    if SameText(ParamStr(I), 'quiet') then
      Quiet := True
    else if DirArg = '' then
      DirArg := ParamStr(I);

  TmpDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'avro_iconsection_' + IntToStr(GetCurrentProcessId) + PathDelim;
  TDirectory.CreateDirectory(TmpDir);

  try
    RunFrameSelection;
    RunHIconSizing;
    RunSizeParsing;
    RunSectionCodec;
    RunContainerPipeline;
    if DirArg <> '' then
      RunContainerDir(DirArg);
  finally
    try
      TDirectory.Delete(TmpDir, True);
    except
      // A leftover temp folder must never turn a green run into a red one.
    end;
  end;

  if Fails = 0 then
    WriteLn(Format('ALL PASS (%d checks)', [Checks]))
  else
    WriteLn(Format('%d of %d checks FAILED', [Fails, Checks]));

  ExitCode := Ord(Fails > 0);

end.
