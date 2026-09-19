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

{ Reads the value of a TOP-LEVEL string member out of AJSON without building a
  DOM.

  System.JSON's TJSONObject.ParseJSONValue materialises one object per member -
  plus a TDictionary, a TJSONPair and a TJSONString/TJSONNumber for each - so
  parsing a 49..114 KB mapping to read ONE scalar cost an order of magnitude
  more memory than the document itself, on every container, at startup. This is
  what replaced that call.

  Strictness is deliberately the same as the DOM lookup it stands in for:
    - only depth-1 members are considered, so a "AnsiLayoutIcon" nested inside
      Metadata (where a hand-edited file could put one) is NOT the section;
    - the value must be a JSON string; an object/array/number/bool/null answer
      is reported as "not a string";
    - string escapes are decoded like the DOM does (\" \\ \/ \b \f \n \r \t
      and \uXXXX). They are not optional: a JSON writer may escape the '/' of a
      Base64 payload as '\/', which is exactly how the shipped containers
      arrived, and a scanner that refused escapes reported "no icon" for every
      one of them. An UNKNOWN escape still reports "no icon" instead of
      guessing.
  Returns False only when the member is absent or malformed. }
function FindTopLevelStringMember(const AJSON, AName: string;
  out AValue: string): Boolean;
var
  I, P, Depth: Integer;
  Key, Text: string;
  NextPos: Integer;

  { Skips whitespace and returns the index of the next non-blank character
    (Len + 1 when the string ends). }
  function SkipBlank(AFrom: Integer): Integer;
  begin
    Result := AFrom;
    while (Result <= Length(AJSON)) and
      CharInSet(AJSON[Result], [' ', #9, #10, #13]) do
      Inc(Result);
  end;

  { Reads the string token whose opening quote is at AStart and decodes its
    escapes. ANext is the index after the closing quote; False when the token
    never closes or contains an escape this reader does not understand.

    One buffer for the whole token: the output is built into a string sized to
    the remaining document and only shrunk at the end, so a 7.6 KB Base64
    payload costs one allocation instead of one per character. }
  function ReadString(AStart: Integer; out ADecoded: string;
    out ANext: Integer): Boolean;
  var
    Q, N, H, V: Integer;
    C: Char;
  begin
    Result := False;
    ADecoded := '';
    ANext := AStart + 1;
    Q := AStart + 1;
    if Q > Length(AJSON) then
      Exit;
    SetLength(ADecoded, Length(AJSON) - Q);
    N := 0;
    while Q <= Length(AJSON) do
    begin
      C := AJSON[Q];
      if C = '"' then
      begin
        SetLength(ADecoded, N);
        ANext := Q + 1;
        Exit(True);
      end;
      if C = '\' then
      begin
        if Q >= Length(AJSON) then
          Exit; // trailing backslash: the token cannot be trusted
        Inc(Q);
        case AJSON[Q] of
          '"', '\', '/': C := AJSON[Q];
          'b': C := #8;
          'f': C := #12;
          'n': C := #10;
          'r': C := #13;
          't': C := #9;
          'u':
            begin
              if Q + 4 > Length(AJSON) then
                Exit;
              V := 0;
              for H := 1 to 4 do
                case AJSON[Q + H] of
                  '0'..'9': V := V * 16 + (Ord(AJSON[Q + H]) - Ord('0'));
                  'a'..'f': V := V * 16 + (Ord(AJSON[Q + H]) - Ord('a') + 10);
                  'A'..'F': V := V * 16 + (Ord(AJSON[Q + H]) - Ord('A') + 10);
                else
                  Exit;
                end;
              // One UTF-16 code unit per \u, so a surrogate pair survives as
              // the two units the document wrote.
              C := Char(V);
              Inc(Q, 4);
            end;
        else
          Exit; // unknown escape: report "no icon" rather than guess
        end;
      end;
      Inc(N);
      ADecoded[N] := C;
      Inc(Q);
    end;
  end;

begin
  Result := False;
  AValue := '';
  // Deliberately no Trim(): a trimmed copy of a 114 KB document is exactly the
  // kind of transient the DOM build was, and leading blanks are already
  // handled by SkipBlank / the scanner's own character walk.
  if (AJSON = '') or (AName = '') then
    Exit;

  I := 1;
  Depth := 0;
  while I <= Length(AJSON) do
  begin
    case AJSON[I] of
      '{', '[':
        begin
          Inc(Depth);
          Inc(I);
        end;
      '}', ']':
        begin
          Dec(Depth);
          Inc(I);
        end;
      '"':
        begin
          if not ReadString(I, Key, NextPos) then
            Exit;
          P := SkipBlank(NextPos);
          if (P <= Length(AJSON)) and (AJSON[P] = ':') then
          begin
            // A member key. Only the root object's own members count.
            if (Depth = 1) and (Key = AName) then
            begin
              P := SkipBlank(P + 1);
              if (P > Length(AJSON)) or (AJSON[P] <> '"') then
                Exit; // present but not a string: same verdict as the DOM
              if not ReadString(P, Text, NextPos) then
                Exit;
              AValue := Text;
              Exit(True);
            end;
            I := NextPos;
          end
          else
            I := NextPos; // a string VALUE (or a key we do not want)
        end;
    else
      Inc(I);
    end;
  end;
end;

function ExtractIconSection(const AJSONContent: string): TBytes;
var
  Encoded: string;
begin
  Result := nil;
  if AJSONContent = '' then
    Exit;
  if not FindTopLevelStringMember(AJSONContent, AVRO_ICON_SECTION, Encoded) then
    Exit;
  try
    Result := TNetEncoding.Base64.DecodeStringToBytes(Encoded);
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
