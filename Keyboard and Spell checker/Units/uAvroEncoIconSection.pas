{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}

unit uAvroEncoIconSection;

{ =============================================================================
  uAvroEncoIconSection - the per-layout icon that travels INSIDE a mapping.

  Why it lives in the payload and not in the container
  ----------------------------------------------------
  A mapping container is already JSON -> obfuscated bytecode -> zlib ->
  AES-256-GCM -> HMAC trailer (uAvroShield). The icon is therefore stored as
  one more member of that JSON document, which means it inherits the HMAC
  verdict, the AES-GCM tag and the obfuscation for free. This is deliberately
  NOT a new container format: DecryptAvroEncoToString in uAvroEncoCrypto is the
  single read path for the runtime, the importer, the version picker and four
  build gates, and every one of them would have had to learn a second magic,
  a second KDF and a second shape contract.

  Why the value is a bare Base64 STRING and not an object
  ------------------------------------------------------
  kat_ansiconvert censuses every top-level member of a mapping and fails when
  the parser drops one ("parser keeps every declared section"). That census
  (SectionCounts) only counts members whose value is an ARRAY or an OBJECT -
  a scalar member is invisible to it. Storing the icon as a scalar string
  therefore keeps the mapping's section accounting, and the gate that asserts
  it, exactly as they are. An ICO is self-describing (ICONDIR lists its own
  frame sizes), so nothing is lost by not wrapping it in metadata fields.

  Sizes
  -----
  A shipped .ico carries 6 frames including a 256x256 one. Embedding it whole
  would add ~370 KB to a ~57 KB container for an icon the shell draws at 16 px.
  The builder therefore embeds a REBUILT .ico holding only the frames below.
  16 px is what the tray and the menus actually draw at 100% DPI; 32 px is the
  200% metric; 48 px gives an exact 2:1 downscale to the 24 px metric. Windows
  itself is never asked to rescale, because CreateHIconAtSize builds the handle
  at exactly the metric it is asked for.

  Windows support
  ---------------
  CreateIconFromResourceEx cannot read a PNG-compressed frame, so a frame that
  starts with the PNG signature is rejected explicitly (IsPortableNetworkFrame)
  rather than decoded into garbage. The shipped artwork is BMP-framed, which is
  asserted by the kat_iconsection gate.

  This unit is deliberately free of Vcl.Graphics: the console builder, the
  static-leak gate and the engine-cache gate all link it.
  ============================================================================= }

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.NetEncoding,
  Winapi.Windows;

const
  { Top-level member name inside the mapping JSON. }
  AVRO_ICON_SECTION = 'AnsiLayoutIcon';

  { The frame sizes a built container carries by default.

    16 px is what the tray draws at 100% DPI and what every menu item draws at
    any DPI, so it is the frame that must be exact. 32 px is the 200% tray
    metric and is also the frame PickBestIconFrame resolves 20 px (125%) and
    24 px (150%) to, since it takes the SMALLEST frame that is at least as
    large as the target.

    The authored artwork's 48 px frame is deliberately NOT in this list: with
    32 px present, the smallest-larger rule resolves every real metric to 16 or
    32, so a 48 px frame would be embedded, encrypted and shipped without ever
    being drawn. Measured cost of the two frames that are here is ~10 KB per
    container; adding 48 px would have cost ~29 KB, because the value codec
    Base64s the value once and then obfuscates it into incompressible text, so
    zlib cannot recover either expansion. }
  AVRO_ICON_FRAME_SIZES: array [0 .. 1] of Integer = (16, 32);

  { Hard bound on what --icon-sizes accepts. The authored 256/128/96/64 px
    frames are outside the tray/menu use case and are the whole reason this
    section exists (one 256 px frame is 270 KB, i.e. 5x a container);
    kat_iconsection fails the build if anything bigger ships. }
  AVRO_ICON_MAX_FRAME_SIZE = 48;

  { ICONDIR header: reserved(2) + type(2) + count(2), then 16 bytes per entry. }
  AVRO_ICONDIR_SIZE   = 6;
  AVRO_ICONDIRENTRY   = 16;

  { A frame whose width byte is 0 means 256 px. }
  AVRO_ICON_SIZE_256  = 256;

type
  { One ICONDIRENTRY, already decoded. Width/Height are expressed in pixels
    (0 in the file is normalised to 256 here). }
  TAvroIconFrame = record
    Width: Integer;
    Height: Integer;
    BitCount: Integer;
    DataOffset: Integer;
    DataSize: Integer;
  end;

  TAvroIconFrames = TArray<TAvroIconFrame>;

{ Every frame the .ico declares, in file order. Empty for a malformed file. }
function IconFramesOf(const AIcoBytes: TBytes): TAvroIconFrames;

{ True when AFrame starts with the PNG signature, i.e. CreateIconFromResourceEx
  cannot consume it. }
function IsPortableNetworkFrame(const AFrame: TBytes): Boolean;

{ The frame blobs (not a whole .ico) chosen for a target size: an exact match
  wins, otherwise the smallest frame that is at least as large as the target,
  otherwise the largest frame that exists. False when there is nothing usable.
  AFrameWidth/Height report the chosen frame's own size, which is what a caller
  needs to know whether Windows will have to rescale. }
function PickBestIconFrame(const AIcoBytes: TBytes; ADesiredCX, ADesiredCY: Integer;
  out AFrame: TBytes; out AFrameWidth, AFrameHeight: Integer): Boolean;

{ A new .ico holding only the frames whose width matches one of ASizes, packed
  with a rebuilt directory. Nil when none match, so a mis-specified --icon-sizes
  is a build error instead of a silently icon-less container. }
function BuildIconFromFrames(const AIcoBytes: TBytes;
  const ASizes: array of Integer): TBytes;

{ The Base64 payload value for a mapping document. }
function EncodeIconSection(const AIcoBytes: TBytes;
  const ASizes: array of Integer): string;

{ The icon carried by a decrypted mapping document, or nil when it has none
  (legacy containers). Never raises: a damaged section reads as "no icon" so a
  layout still loads. }
function ExtractIconSection(const AJSONContent: string): TBytes;

{ An HICON built at EXACTLY ACX x ACY. The best frame is selected first, then
  handed to CreateIconFromResourceEx with that explicit size, so the shell is
  never given a mismatched handle to rescale. 0 on failure, in which case the
  caller falls back to its built-in icon. The caller owns the handle and must
  release it with DestroyIcon. }
function CreateHIconAtSize(const AIcoBytes: TBytes; ACX, ACY: Integer): HICON;

{ Parsers for the --icon-sizes command line value, e.g. '16,32,48'. }
function ParseIconSizes(const AText: string; out ASizes: TArray<Integer>;
  out AErr: string): Boolean;

implementation

{ Little-endian readers. An .ico is a little-endian format. }
function ReadWord(const AData: TBytes; AOffset: Integer): Integer;
begin
  Result := Integer(AData[AOffset]) or (Integer(AData[AOffset + 1]) shl 8);
end;

function ReadDWord(const AData: TBytes; AOffset: Integer): Integer;
begin
  Result := Integer(AData[AOffset]) or (Integer(AData[AOffset + 1]) shl 8) or
    (Integer(AData[AOffset + 2]) shl 16) or (Integer(AData[AOffset + 3]) shl 24);
end;

function IconFramesOf(const AIcoBytes: TBytes): TAvroIconFrames;
var
  Count, I, Entry, Offset, Size: Integer;
  W, H: Integer;
begin
  Result := nil;
  if Length(AIcoBytes) < AVRO_ICONDIR_SIZE then
    Exit;
  // reserved must be 0 and the resource type must be 1 (icon, not cursor).
  if (ReadWord(AIcoBytes, 0) <> 0) or (ReadWord(AIcoBytes, 2) <> 1) then
    Exit;
  Count := ReadWord(AIcoBytes, 4);
  if (Count <= 0) or (AVRO_ICONDIR_SIZE + Count * AVRO_ICONDIRENTRY > Length(AIcoBytes)) then
    Exit;

  SetLength(Result, Count);
  for I := 0 to Count - 1 do
  begin
    Entry := AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY;
    // A zero extent byte encodes 256 px; the directory cannot express more.
    W := AIcoBytes[Entry];
    H := AIcoBytes[Entry + 1];
    if W = 0 then
      W := AVRO_ICON_SIZE_256;
    if H = 0 then
      H := AVRO_ICON_SIZE_256;
    Offset := ReadDWord(AIcoBytes, Entry + 12);
    Size := ReadDWord(AIcoBytes, Entry + 8);
    // A frame that points outside the file is corrupt: drop the whole table
    // rather than hand out a blob that CreateIconFromResourceEx would read
    // past.
    if (Offset < 0) or (Size <= 0) or (Offset + Size > Length(AIcoBytes)) then
    begin
      Result := nil;
      Exit;
    end;
    Result[I].Width := W;
    Result[I].Height := H;
    Result[I].BitCount := ReadWord(AIcoBytes, Entry + 6);
    Result[I].DataOffset := Offset;
    Result[I].DataSize := Size;
  end;
end;

function FrameBytesOf(const AIcoBytes: TBytes; const AFrame: TAvroIconFrame): TBytes;
begin
  Result := Copy(AIcoBytes, AFrame.DataOffset, AFrame.DataSize);
end;

function IsPortableNetworkFrame(const AFrame: TBytes): Boolean;
begin
  Result := (Length(AFrame) >= 8) and (AFrame[0] = $89) and (AFrame[1] = $50) and
    (AFrame[2] = $4E) and (AFrame[3] = $47);
end;

function PickBestIconFrame(const AIcoBytes: TBytes; ADesiredCX, ADesiredCY: Integer;
  out AFrame: TBytes; out AFrameWidth, AFrameHeight: Integer): Boolean;
var
  Frames: TAvroIconFrames;
  I, BestIdx, BestExtent: Integer;
begin
  Result := False;
  AFrame := nil;
  AFrameWidth := 0;
  AFrameHeight := 0;
  if (ADesiredCX <= 0) or (ADesiredCY <= 0) then
    Exit;

  Frames := IconFramesOf(AIcoBytes);
  if Length(Frames) = 0 then
    Exit;

  // Pass 1: exact extent. This is the case the tray hits at 100% DPI and the
  // menus hit always, and it is why no scaling is needed there.
  for I := 0 to High(Frames) do
    if (Frames[I].Width = ADesiredCX) and (Frames[I].Height = ADesiredCY) then
    begin
      AFrame := FrameBytesOf(AIcoBytes, Frames[I]);
      AFrameWidth := Frames[I].Width;
      AFrameHeight := Frames[I].Height;
      Exit(not IsPortableNetworkFrame(AFrame));
    end;

  // Pass 2: smallest frame that is at least as large as the target on both
  // axes - shrinking a real frame beats enlarging a smaller one.
  BestIdx := -1;
  BestExtent := MaxInt;
  for I := 0 to High(Frames) do
    if (Frames[I].Width >= ADesiredCX) and (Frames[I].Height >= ADesiredCY) and
      (Frames[I].Width < BestExtent) then
    begin
      BestIdx := I;
      BestExtent := Frames[I].Width;
    end;

  // Pass 3: nothing big enough, so the largest frame available is the best
  // source and Windows enlarges it.
  if BestIdx < 0 then
  begin
    BestExtent := -1;
    for I := 0 to High(Frames) do
      if Frames[I].Width > BestExtent then
      begin
        BestIdx := I;
        BestExtent := Frames[I].Width;
      end;
  end;

  if BestIdx < 0 then
    Exit;
  AFrame := FrameBytesOf(AIcoBytes, Frames[BestIdx]);
  AFrameWidth := Frames[BestIdx].Width;
  AFrameHeight := Frames[BestIdx].Height;
  Result := not IsPortableNetworkFrame(AFrame);
end;

function BuildIconFromFrames(const AIcoBytes: TBytes;
  const ASizes: array of Integer): TBytes;
var
  Frames: TAvroIconFrames;
  Keep: array of Integer;
  I, J, Count, Size, DataSize, Hdr, Off: Integer;
  Want: Boolean;
begin
  Result := nil;
  Frames := IconFramesOf(AIcoBytes);
  if Length(Frames) = 0 then
    Exit;

  // Preserve the source order so the rebuilt file is stable for a given input,
  // which is what makes the build reproducible and the gate's byte compare
  // meaningful.
  SetLength(Keep, Length(Frames));
  Count := 0;
  for I := 0 to High(Frames) do
  begin
    Want := False;
    for Size in ASizes do
      if (Size > 0) and (Frames[I].Width = Size) and (Frames[I].Height = Size) then
      begin
        Want := True;
        Break;
      end;
    if Want then
    begin
      Keep[Count] := I;
      Inc(Count);
    end;
  end;
  if Count = 0 then
    Exit;

  DataSize := 0;
  for I := 0 to Count - 1 do
    Inc(DataSize, Frames[Keep[I]].DataSize);
  Hdr := AVRO_ICONDIR_SIZE + Count * AVRO_ICONDIRENTRY;
  SetLength(Result, Hdr + DataSize);
  FillChar(Result[0], Length(Result), 0);

  Result[0] := 0; // reserved
  Result[1] := 0;
  Result[2] := 1; // type = icon
  Result[3] := 0;
  Result[4] := Byte(Count and $FF);
  Result[5] := Byte((Count shr 8) and $FF);

  Off := Hdr;
  for I := 0 to Count - 1 do
  begin
    J := AVRO_ICONDIR_SIZE + I * AVRO_ICONDIRENTRY;
    // 256 px is written back as the 0 extent byte, the only way the directory
    // can express it.
    if Frames[Keep[I]].Width >= AVRO_ICON_SIZE_256 then
      Result[J] := 0
    else
      Result[J] := Byte(Frames[Keep[I]].Width);
    if Frames[Keep[I]].Height >= AVRO_ICON_SIZE_256 then
      Result[J + 1] := 0
    else
      Result[J + 1] := Byte(Frames[Keep[I]].Height);
    Result[J + 2] := 0; // colour count: 0 for 32bpp
    Result[J + 3] := 0; // reserved
    Result[J + 4] := 1; // planes
    Result[J + 5] := 0;
    Result[J + 6] := Byte(Frames[Keep[I]].BitCount and $FF);
    Result[J + 7] := Byte((Frames[Keep[I]].BitCount shr 8) and $FF);
    Result[J + 8] := Byte(Frames[Keep[I]].DataSize and $FF);
    Result[J + 9] := Byte((Frames[Keep[I]].DataSize shr 8) and $FF);
    Result[J + 10] := Byte((Frames[Keep[I]].DataSize shr 16) and $FF);
    Result[J + 11] := Byte((Frames[Keep[I]].DataSize shr 24) and $FF);
    Result[J + 12] := Byte(Off and $FF);
    Result[J + 13] := Byte((Off shr 8) and $FF);
    Result[J + 14] := Byte((Off shr 16) and $FF);
    Result[J + 15] := Byte((Off shr 24) and $FF);

    Move(AIcoBytes[Frames[Keep[I]].DataOffset], Result[Off], Frames[Keep[I]].DataSize);
    Inc(Off, Frames[Keep[I]].DataSize);
  end;
end;

function EncodeIconSection(const AIcoBytes: TBytes;
  const ASizes: array of Integer): string;
var
  Trimmed: TBytes;
begin
  Result := '';
  Trimmed := BuildIconFromFrames(AIcoBytes, ASizes);
  if Length(Trimmed) = 0 then
    Exit;
  Result := TNetEncoding.Base64.EncodeBytesToString(Trimmed);
end;

function ExtractIconSection(const AJSONContent: string): TBytes;
var
  Root: TJSONValue;
  Value: TJSONValue;
begin
  Result := nil;
  if Trim(AJSONContent) = '' then
    Exit;
  Root := nil;
  try
    try
      Root := TJSONObject.ParseJSONValue(AJSONContent);
    except
      Root := nil;
    end;
    if (Root = nil) or not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue(AVRO_ICON_SECTION);
    if not (Value is TJSONString) then
      Exit;
    try
      Result := TNetEncoding.Base64.DecodeStringToBytes(TJSONString(Value).Value);
    except
      // A damaged section must never cost the user a working layout: it reads
      // as "this mapping has no icon" and the caller falls back.
      Result := nil;
      Exit;
    end;
    // Decoded bytes that are not an .ico are as useless as no icon at all, and
    // rejecting them here means the UI never has to reason about a blob it
    // cannot draw.
    if Length(IconFramesOf(Result)) = 0 then
      Result := nil;
  finally
    Root.Free;
  end;
end;

function CreateHIconAtSize(const AIcoBytes: TBytes; ACX, ACY: Integer): HICON;
var
  Frame: TBytes;
  FW, FH: Integer;
begin
  Result := 0;
  if not PickBestIconFrame(AIcoBytes, ACX, ACY, Frame, FW, FH) then
    Exit;
  // dwVer 3.0 ($00030000) is the version every 32bpp alpha icon uses. The
  // explicit cx/cy is the whole point: the shell receives a handle that is
  // already the size its metric asked for.
  Result := CreateIconFromResourceEx(@Frame[0], DWORD(Length(Frame)), True,
    $00030000, ACX, ACY, LR_DEFAULTCOLOR);
end;

function ParseIconSizes(const AText: string; out ASizes: TArray<Integer>;
  out AErr: string): Boolean;
var
  Parts: TArray<string>;
  I, N, Seen: Integer;
  Part: string;
  Vals: TArray<Integer>;
begin
  Result := False;
  ASizes := nil;
  AErr := '';
  if Trim(AText) = '' then
  begin
    AErr := 'empty size list';
    Exit;
  end;

  Parts := AText.Split([',', ';']);
  SetLength(Vals, Length(Parts));
  Seen := 0;
  for I := 0 to High(Parts) do
  begin
    Part := Trim(Parts[I]);
    if Part = '' then
      Continue;
    if not TryStrToInt(Part, N) then
    begin
      AErr := 'not a number: ' + Part;
      Exit;
    end;
    if (N < 8) or (N > AVRO_ICON_MAX_FRAME_SIZE) then
    begin
      // Above AVRO_ICON_MAX_FRAME_SIZE the frame is a size the tray and the
      // menus never draw, and the whole reason the payload section exists is
      // that embedding the 256 px artwork made a 57 KB container 10x bigger.
      AErr := Format('size %d is outside 8..%d', [N, AVRO_ICON_MAX_FRAME_SIZE]);
      Exit;
    end;
    Vals[Seen] := N;
    Inc(Seen);
  end;
  if Seen = 0 then
  begin
    AErr := 'empty size list';
    Exit;
  end;
  ASizes := Copy(Vals, 0, Seen);
  Result := True;
end;

end.
