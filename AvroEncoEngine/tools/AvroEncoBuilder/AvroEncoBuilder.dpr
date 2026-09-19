{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

program AvroEncoBuilder;

{ =============================================================================
  AvroEncoBuilder - offline .AvroEnco container builder.

  Compiles a raw ANSI mapping JSON document into a protected .AvroEnco
  container using the same pure-Pascal crypto stack the runtime loads:

    shield (default):
      JSON -> obfuscated bytecode -> zlib -> AES-256-GCM -> HMAC-SHA512
      trailer. Protected either with a user password (-p, prompts once at
      load time) or with the default-key secret (--default-key, loads
      transparently - use for shipped built-ins). Default-key builds must
      pass --secret-file: this tool intentionally embeds no secret of its
      own, so the only shipped artifact holding one is the runtime.

    v2:
      AES-256-CBC container (legacy runtime format). Empty password selects
      the default-key mode; -p selects user-password protection.

  After building, the tool ALWAYS loads the container back through the
  runtime reader and verifies the recovered JSON is semantically identical to
  the input (unless --no-verify), so a format regression can never ship. The
  load-back runs with --comments-key-file applied, so a comment-codec
  regression cannot ship either.

  Pack / unpack round trip:
    --pack    Authoring JSON (readable Bengali comments) -> .AvroEnco. This is
              the default mode, spelled out so the pair is symmetric.
    --unpack  .AvroEnco -> authoring JSON with the comments restored, for
              developer review and editing. Needs --secret-file for a
              default-key container and --comments-key-file to recover
              comment text; without the comment key the comment fields are
              dropped rather than written out as opaque tokens.

  The comment key is a developer-side IKM. Comment fields are obfuscated in a
  domain keyed by it, which is never derived from a container key and is never
  linked into the runtime, so a decrypted container does not disclose them.
  See AvroEncoEngine\docs\obfuscation-codec.md.

  Usage:
    AvroEncoBuilder <input.json> <output.avroenco> [options]
    AvroEncoBuilder --unpack <input.avroenco> <output.json> [options]

  Options:
    --pack                Shield/v2 build from authoring JSON (default).
    --unpack              Developer round trip: container -> JSON.
    -p, --password <pw>   User password protection (prompts at load time).
    --default-key         Shield: protect with the default-key secret.
    --secret-file <path>  Raw default-key IKM. Required with --default-key,
                          and required by --unpack for a default-key
                          container (the tool embeds no secret of its own).
    --comments-key-file <path>
                          Raw developer comment IKM. Encodes comment fields
                          on build, decodes them on --unpack.
    --format <fmt>        shield (default) | v2
    --icon <path>         Embed an .ico inside the payload, so the runtime can
                          draw the layout's own tray and menu icon.
    --icon-sizes <list>   Frames to embed, e.g. 16,32,48 (default). Bounded by
                          the unit's AVRO_ICON_MAX_FRAME_SIZE: the authored
                          256 px artwork is what made the section necessary.
    --bind                Shield: bind the container to this machine.
    --hardware            Shield: add the hardware factor to the KDF.
    --no-verify           Skip the load-back round-trip verification.
    --quiet               Only print errors.

  Exit codes: 0 OK, 1 usage, 2 input read failure, 3 invalid JSON,
              4 build failure, 5 output write failure, 6 verification failure,
              7 secret file missing/empty, 8 unpack failed.
  ============================================================================= }

{ The builder is a local offline tool, so it keeps the descriptive parse
  diagnostics that a Release runtime deliberately strips (see the error-text
  policy in uAvroShield). Pass -B when building so this define is not masked
  by a stale DCU of uAvroShield. }
{$DEFINE AVROSHIELD_VERBOSE_ERRORS}

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  uAvroEncoCrypto,
  uAvroEncoIconSection,
  uAvroSecureMem,
  uAvroShield;

const
  EXIT_OK       = 0;
  EXIT_USAGE    = 1;
  EXIT_READ     = 2;
  EXIT_PARSE    = 3;
  EXIT_BUILD    = 4;
  EXIT_WRITE    = 5;
  EXIT_VERIFY   = 6;
  EXIT_KEYFILE  = 7;
  EXIT_UNPACK   = 8;

  { The authoring files are UTF-8 with a BOM and LF line breaks. Emitting
    exactly that is what lets the unpack round trip be checked byte for byte
    against the authored sources instead of only semantically - a much stronger
    gate, and the reason this is not sLineBreak (CRLF on Windows). }
  JSON_BREAK = #10;

  FORMAT_SHIELD = 1;
  FORMAT_V2     = 2;

var
  InputPath, OutputPath, Password, ErrMsg, SecretFilePath: string;
  CommentsKeyPath, IconPath, IconSizesText, BuildJsonText: string;
  IconSectionBase64: string;
  ContainerFormat, IconErrCode: Integer;
  UseDefaultKey, BindMachine, UseHardware, NoVerify, Quiet: Boolean;
  UnpackMode, PackMode: Boolean;
  KeyIKM, CommentsIKM, IconBytes: TBytes;
  IconSizes: TArray<Integer>;

procedure Usage;
begin
  WriteLn('AvroEncoBuilder - offline .AvroEnco container builder');
  WriteLn;
  WriteLn('Usage: AvroEncoBuilder <input.json> <output.avroenco> [options]');
  WriteLn('       AvroEncoBuilder --unpack <input.avroenco> <output.json> [options]');
  WriteLn;
  WriteLn('Modes:');
  WriteLn('  --pack                Build a container from authoring JSON (default).');
  WriteLn('  --unpack              Developer round trip: container -> authoring JSON');
  WriteLn('                        with the Bengali comments restored.');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -p, --password <pw>   User password protection (prompts at load time).');  WriteLn('    --default-key         Shield: protect with the default-key secret.');
  WriteLn('    --comments-key-file <path>');
  WriteLn('                          Raw developer comment IKM: encodes comment');
  WriteLn('                          fields on build, decodes them on --unpack.');
  WriteLn('    --secret-file <path>  Raw default-key IKM file. REQUIRED with');
  WriteLn('                          --default-key: the builder deliberately has no');
  WriteLn('                          embedded secret, so building and running the');
  WriteLn('                          tool never exposes one.');
  WriteLn('  --format <fmt>        shield (default) | v2');
  WriteLn('  --icon <path>         Embed an .ico inside the payload, so the runtime');
  WriteLn('                        can draw the layout''s own tray and menu icon.');
  WriteLn('  --icon-sizes <list>   Frames to embed, e.g. 16,32,48 (default).');
  WriteLn('  --bind                Shield: bind the container to this machine.');
  WriteLn('  --hardware            Shield: add the hardware factor to the KDF.');
  WriteLn('  --no-verify           Skip the load-back round-trip verification.');
  WriteLn('  --quiet               Only print errors.');
  WriteLn;
  WriteLn('Exit codes: 0 OK, 1 usage, 2 input read failure, 3 invalid JSON,');
  WriteLn('            4 build failure, 5 output write failure, 6 verification failure,');
  WriteLn('            7 secret file missing/empty, 8 unpack failed.');
end;

{ Reads a UTF-8 text file, strips a leading BOM. }
function ReadUtf8File(const APath: string; out AText: string): Boolean;
begin
  Result := False;
  AText := '';
  try
    if not FileExists(APath) then
      Exit;
    AText := TFile.ReadAllText(APath, TEncoding.UTF8);
    if (Length(AText) >= 3) and (AText[1] = #$EF) and (AText[2] = #$BB) and
      (AText[3] = #$BF) then
      Delete(AText, 1, 3);
    Result := Trim(AText) <> '';
  except
    on E: Exception do
      AText := '';
  end;
end;

{ Semantic JSON equality: key order is preserved by System.JSON on both
  sides, so objects are compared pairwise; numbers are compared as values
  (string form for integers, double for anything else). }
function JsonTreesEqual(const A, B: TJSONValue): Boolean;
var
  I: Integer;
  NumA, NumB: Double;
begin
  Result := False;
  if (A = nil) or (B = nil) then
    Exit;

  if (A is TJSONNull) and (B is TJSONNull) then
    Exit(True);

  if (A is TJSONBool) and (B is TJSONBool) then
    Exit((A as TJSONBool).AsBoolean = (B as TJSONBool).AsBoolean);

  if (A is TJSONNumber) and (B is TJSONNumber) then
  begin
    if (A as TJSONNumber).Value = (B as TJSONNumber).Value then
      Exit(True);
    NumA := StrToFloat((A as TJSONNumber).Value, TFormatSettings.Invariant);
    NumB := StrToFloat((B as TJSONNumber).Value, TFormatSettings.Invariant);
    Exit(Abs(NumA - NumB) < 1e-9);
  end;

  if (A is TJSONString) and (B is TJSONString) then
    Exit((A as TJSONString).Value = (B as TJSONString).Value);

  if (A is TJSONArray) and (B is TJSONArray) then
  begin
    if (A as TJSONArray).Count <> (B as TJSONArray).Count then
      Exit;
    for I := 0 to (A as TJSONArray).Count - 1 do
      if not JsonTreesEqual((A as TJSONArray).Items[I],
        (B as TJSONArray).Items[I]) then
        Exit;
    Exit(True);
  end;

  if (A is TJSONObject) and (B is TJSONObject) then
  begin
    if (A as TJSONObject).Count <> (B as TJSONObject).Count then
      Exit;
    for I := 0 to (A as TJSONObject).Count - 1 do
    begin
      if (A as TJSONObject).Get(I).JsonString.Value <>
        (B as TJSONObject).Get(I).JsonString.Value then
        Exit;
      if not JsonTreesEqual((A as TJSONObject).Get(I).JsonValue,
        (B as TJSONObject).Get(I).JsonValue) then
        Exit;
    end;
    Exit(True);
  end;

  // Mixed kinds: not equal.
end;

{ Loads AOutBytes back through the runtime loader and compares the recovered
  JSON against the input document. For default-key containers APassword is
  ignored by the loader (it substitutes the built-in secret itself).

  The caller passes the options the build used, with IncludeComments enabled:
  the load-back then also proves that every comment field survives the comment
  domain round trip, not just that the operational fields do. }
function SizesText(const ASizes: TArray<Integer>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(ASizes) do
  begin
    if I > 0 then
      Result := Result + ',';
    Result := Result + IntToStr(ASizes[I]);
  end;
end;

{ The document that will actually be built. Without --icon this is AJsonText
  unchanged. With --icon the ICO is down-selected to IconSizes, Base64'd and
  added as ONE top-level scalar member, so it rides the existing
  obfuscate -> zlib -> AES-256-GCM -> HMAC pipeline and the container format,
  its magic and its version byte stay exactly as they are.

  The member is a scalar on purpose: kat_ansiconvert censuses every top-level
  member whose value is an array or an object and fails when the parser drops
  one, so a scalar keeps the mapping's section accounting untouched. An ICO is
  self-describing (its ICONDIR lists the frame sizes), so nothing is lost.

  False means the caller must not build; the reason has already been printed
  and IconErrCode holds the exit code to report. }
function BuildDocumentText(const AJsonText: string; out AText: string): Boolean;
var
  Root, Repro: TJSONValue;
  Serialized: string;
begin
  Result := False;
  IconErrCode := EXIT_BUILD;
  AText := AJsonText;
  if IconPath = '' then
    Exit(True);

  if not FileExists(IconPath) then
  begin
    WriteLn('ERROR: icon file not found: ' + IconPath);
    IconErrCode := EXIT_READ;
    Exit;
  end;
  try
    IconBytes := TFile.ReadAllBytes(IconPath);
  except
    WriteLn('ERROR: cannot read icon file: ' + IconPath);
    IconErrCode := EXIT_READ;
    Exit;
  end;
  if Length(IconBytes) = 0 then
  begin
    WriteLn('ERROR: icon file is empty: ' + IconPath);
    IconErrCode := EXIT_READ;
    Exit;
  end;

  IconSectionBase64 := EncodeIconSection(IconBytes, IconSizes);
  if IconSectionBase64 = '' then
  begin
    WriteLn('ERROR: no frame of ' + IconPath + ' matches ' + SizesText(IconSizes) +
      '; allowed frame sizes are 8..' + IntToStr(AVRO_ICON_MAX_FRAME_SIZE) +
      ' px square');
    Exit;
  end;

  Root := TJSONObject.ParseJSONValue(Trim(AJsonText));
  if (Root = nil) or not (Root is TJSONObject) then
  begin
    Root.Free;
    WriteLn('ERROR: input is not a valid JSON object: ' + InputPath);
    IconErrCode := EXIT_PARSE;
    Exit;
  end;
  try
    TJSONObject(Root).AddPair(AVRO_ICON_SECTION, IconSectionBase64);
    Serialized := TJSONObject(Root).ToJSON;

    // The build runs on Serialized, so prove the serialize step kept every
    // member before trusting the load-back check: a round trip that dropped a
    // field would otherwise be compared against itself and never noticed.
    Repro := TJSONObject.ParseJSONValue(Serialized);
    if (Repro = nil) or (not JsonTreesEqual(Root, Repro)) then
    begin
      Repro.Free;
      WriteLn('ERROR: the icon-injected document does not survive JSON serialization');
      Exit;
    end;
    Repro.Free;
  finally
    Root.Free;
  end;

  AText := Serialized;
  Result := True;
end;

function VerifyRoundTrip(const AJsonText, APassword: string;
  const ADefaultKey: Boolean; const AOutBytes: TBytes;
  const AOptions: TAvroShieldLoadOptions; out AErr: string): Boolean;
var
  Loaded: string;
  LoadedBytes: TBytes;
  R: TAvroShieldResult;
  JsonA, JsonB: TJSONValue;
begin
  Result := False;
  AErr := '';
  R := AvroShieldLoadFromBytesUtf8Ex(AOutBytes, APassword, AOptions, LoadedBytes);
  if R = asrOk then
  begin
    Loaded := TEncoding.UTF8.GetString(LoadedBytes);
    AvroWipeAndRelease(LoadedBytes);
  end;
  if R <> asrOk then
  begin
    AErr := 'runtime loader rejected the container (code ' + IntToStr(Ord(R)) + ')';
    Exit;
  end;
  if Trim(Loaded) = '' then
  begin
    AErr := 'runtime loader returned empty JSON';
    Exit;
  end;
  JsonA := TJSONObject.ParseJSONValue(Trim(AJsonText));
  JsonB := TJSONObject.ParseJSONValue(Trim(Loaded));
  if (JsonA = nil) or (JsonB = nil) then
  begin
    AErr := 'cannot re-parse the round-tripped JSON';
    JsonA.Free;
    JsonB.Free;
    Exit;
  end;
  try
    Result := JsonTreesEqual(JsonA, JsonB);
    if not Result then
      AErr := 'recovered JSON differs from the input document';
  finally
    JsonA.Free;
    JsonB.Free;
  end;
end;

function ParseArgs: Boolean;
var
  I: Integer;
  Arg: string;
begin
  Result := False;
  ContainerFormat := FORMAT_SHIELD;
  UseDefaultKey := False;
  BindMachine := False;
  UseHardware := False;
  NoVerify := False;
  Quiet := False;
  UnpackMode := False;
  PackMode := False;
  Password := '';
  SecretFilePath := '';
  CommentsKeyPath := '';
  IconPath := '';
  IconSizesText := '';
  InputPath := '';
  OutputPath := '';

  if ParamCount < 2 then
    Exit;

  // Options may appear before or after the two positional paths, so the
  // positional arguments are collected in order rather than assumed to be
  // the first two (--unpack in front of the input is the normal spelling).
  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if Arg = '--unpack' then
      UnpackMode := True
    else if Arg = '--pack' then
      PackMode := True
    else if (Arg = '-p') or (Arg = '--password') then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      Password := ParamStr(I);
    end
    else if Arg = '--default-key' then
      UseDefaultKey := True
    else if Arg = '--bind' then
      BindMachine := True
    else if Arg = '--hardware' then
      UseHardware := True
    else if Arg = '--secret-file' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      SecretFilePath := ParamStr(I);
    end
    else if Arg = '--comments-key-file' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      CommentsKeyPath := ParamStr(I);
    end
    else if Arg = '--icon' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      IconPath := ParamStr(I);
    end
    else if Arg = '--icon-sizes' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      IconSizesText := ParamStr(I);
    end
    else if Arg = '--no-verify' then
      NoVerify := True
    else if Arg = '--quiet' then
      Quiet := True
    else if Arg = '--format' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      if SameText(ParamStr(I), 'v2') then
        ContainerFormat := FORMAT_V2
      else if SameText(ParamStr(I), 'shield') then
        ContainerFormat := FORMAT_SHIELD
      else
        Exit;
    end
    else if (Arg <> '') and (Arg[1] = '-') then
      Exit // unknown argument
    else
    begin
      if InputPath = '' then
        InputPath := Arg
      else if OutputPath = '' then
        OutputPath := Arg
      else
        Exit; // more than two paths
    end;
    Inc(I);
  end;

  if (InputPath = '') or (OutputPath = '') then
    Exit;
  if UnpackMode and PackMode then
    Exit; // contradictory modes

  // Unpack takes its protection mode from the container header, so the
  // build-side rules below do not apply to it.
  if UnpackMode then
  begin
    // --icon is a build input: there is nothing to inject on the way out.
    if UseDefaultKey or BindMachine or UseHardware or (IconPath <> '') then
      Exit;
    Result := True;
    Exit;
  end;

  // Protection-mode validation per format.
  if UseDefaultKey and (Password <> '') then
    Exit; // contradictory: both default-key and password requested
  if (ContainerFormat = FORMAT_SHIELD) and (not UseDefaultKey) and (Password = '') then
    Exit; // shield always needs one of the two
  if (ContainerFormat = FORMAT_V2) and UseDefaultKey then
    Exit; // v2 selects default-key automatically with an empty password

  // Default-key Shield builds must be driven by an external key file. The
  // builder is compiled from the same units as the runtime, so without this
  // rule it would carry its own copy of the secret - a second place to
  // extract it from, in a tool that is easy to overlook during a release.
  if (ContainerFormat = FORMAT_SHIELD) and UseDefaultKey and
    (SecretFilePath = '') then
    Exit;

  // --icon embeds a per-layout icon in the payload. The frame list defaults to
  // the sizes the tray and the menus actually draw (AVRO_ICON_FRAME_SIZES); a
  // mis-typed list is a usage error, never a silently icon-less container.
  if IconSizesText <> '' then
  begin
    if not ParseIconSizes(IconSizesText, IconSizes, ErrMsg) then
    begin
      WriteLn('ERROR: --icon-sizes: ' + ErrMsg);
      Exit;
    end;
  end
  else
  begin
    SetLength(IconSizes, Length(AVRO_ICON_FRAME_SIZES));
    for I := 0 to High(AVRO_ICON_FRAME_SIZES) do
      IconSizes[I] := AVRO_ICON_FRAME_SIZES[I];
  end;

  Result := True;
end;

{ Reads a raw key file (no BOM, no trailing newline) holding the default-key
  IKM. The bytes go straight to HKDF-SHA256, matching what the runtime embeds.
  Returns False when the file is missing or empty; the caller reports the
  reason and exits with EXIT_KEYFILE. }
function ReadKeyFile(const APath: string; out AIKM: TBytes): Boolean;
var
  Raw: TBytes;
begin
  AIKM := nil;
  Result := False;
  try
    if not FileExists(APath) then
      Exit;
    Raw := TFile.ReadAllBytes(APath);
  except
    Exit;
  end;
  if Length(Raw) = 0 then
    Exit;
  AIKM := Raw;
  Result := True;
end;

function WriteOutputBytes(const APath: string; const AData: TBytes): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmCreate);
    try
      if Length(AData) > 0 then
        FS.WriteBuffer(AData[0], Length(AData));
      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

{ Loads the developer comment IKM when --comments-key-file was given. False
  only when a path was supplied but cannot be read: running without the file is
  allowed (comments then fall back to the value domain on build, and are left
  out of an unpack), but a path that does not work is a build error. }
function ReadCommentsKey: Boolean;
begin
  Result := True;
  CommentsIKM := nil;
  if CommentsKeyPath = '' then
    Exit;
  Result := ReadKeyFile(CommentsKeyPath, CommentsIKM);
end;

{ Escapes a string for JSON output, leaving non-ASCII (the Bengali comments)
  as raw UTF-8 so an unpacked file reads like the authoring source. }
function EscapeJsonString(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
end;

{ Developer-shaped JSON: 4-space indent, key order preserved, objects and
  arrays multi-line, empty containers inline. Deliberately the same shape the
  authoring files in assets\ use, so an unpacked
  container can be diffed against them directly. }
function PrettyJson(const AValue: TJSONValue; AIndent: Integer): string;
var
  I: Integer;
  Pad, Inner: string;
  Obj: TJSONObject;
  Arr: TJSONArray;
begin
  Pad := StringOfChar(' ', AIndent);
  Inner := StringOfChar(' ', AIndent + 4);
  if AValue is TJSONObject then
  begin
    Obj := TJSONObject(AValue);
    if Obj.Count = 0 then
      Exit('{}');
    Result := '{' + JSON_BREAK;
    for I := 0 to Obj.Count - 1 do
    begin
      Result := Result + Inner + '"' + Obj.Pairs[I].JsonString.Value + '": ' +
        PrettyJson(Obj.Pairs[I].JsonValue, AIndent + 4);
      if I < Obj.Count - 1 then
        Result := Result + ',';
      Result := Result + JSON_BREAK;
    end;
    Result := Result + Pad + '}';
  end
  else if AValue is TJSONArray then
  begin
    Arr := TJSONArray(AValue);
    if Arr.Count = 0 then
      Exit('[]');
    Result := '[' + JSON_BREAK;
    for I := 0 to Arr.Count - 1 do
    begin
      Result := Result + Inner + PrettyJson(Arr.Items[I], AIndent + 4);
      if I < Arr.Count - 1 then
        Result := Result + ',';
      Result := Result + JSON_BREAK;
    end;
    Result := Result + Pad + ']';
  end
  // Order matters: in System.JSON, TJSONNumber descends from TJSONString, so a
  // number has to be recognised before the string branch - otherwise an
  // integer read back as a number is re-emitted as a quoted string and the
  // unpack output stops matching the authored source.
  else if AValue is TJSONNumber then
    Result := TJSONNumber(AValue).Value
  else if AValue is TJSONString then
    Result := '"' + EscapeJsonString(TJSONString(AValue).Value) + '"'
  else
    Result := AValue.ToString;
end;

{ Writes UTF-8 with a BOM and CRLF breaks, matching the authoring files. }
function WriteTextFileUtf8Bom(const APath, AText: string): Boolean;
var
  Bytes: TBytes;
begin
  Result := False;
  try
    Bytes := TEncoding.UTF8.GetBytes(AText);
    TFile.WriteAllBytes(APath, TEncoding.UTF8.GetPreamble + Bytes);
    Result := True;
  except
    Result := False;
  end;
end;

{ Developer round trip: container -> authoring JSON with the comments restored.
  The comment text is only recoverable with the developer comment key; without
  it the comment fields are dropped instead of written out as opaque tokens. }
function UnpackContainer: Integer;
var
  Data: TBytes;
  Options: TAvroShieldLoadOptions;
  LoadedBytes: TBytes;
  R: TAvroShieldResult;
  Text, Pretty: string;
  Json: TJSONValue;
  Version: Byte;
  CommentKeyFailed, HadIcon: Boolean;
begin
  Result := EXIT_UNPACK;
  if not FileExists(InputPath) then
  begin
    WriteLn('ERROR: container not found: ' + InputPath);
    Exit(EXIT_READ);
  end;
  try
    Data := TFile.ReadAllBytes(InputPath);
  except
    WriteLn('ERROR: cannot read container: ' + InputPath);
    Exit(EXIT_READ);
  end;

  // A default-key container needs the key file. This tool deliberately embeds
  // no secret of its own, so there is nothing to fall back to.
  if AvroShieldContainerUsesDefaultKey(InputPath) then
    if not ReadKeyFile(SecretFilePath, KeyIKM) then
    begin
      WriteLn('ERROR: this is a default-key container and no usable secret ' +
        'file was given.');
      WriteLn('       Pass --secret-file <keys\avroenco.key>.');
      Exit(EXIT_KEYFILE);
    end;

  Options := AvroShieldDefaultLoadOptions;
  Options.IncludeComments := Length(CommentsIKM) > 0;
  Options.DefaultSecretIKM := KeyIKM;
  Options.CommentsIKM := CommentsIKM;

  CommentKeyFailed := False;
  R := AvroShieldLoadFromBytesUtf8Ex(Data, Password, Options, LoadedBytes);
  if (R <> asrOk) and Options.IncludeComments then
  begin
    // The comment domain fails closed on a wrong key: the codec cannot tell a
    // rotated developer key from a damaged container. The operational mapping
    // is keyed by the container key alone, so retry with comments dropped - a
    // wrong comment key must never cost a developer the mapping - and say
    // afterwards which key looks wrong.
    Options.IncludeComments := False;
    R := AvroShieldLoadFromBytesUtf8Ex(Data, Password, Options, LoadedBytes);
    CommentKeyFailed := R = asrOk;
  end;
  if R <> asrOk then
  begin
    WriteLn('ERROR: cannot unpack the container (code ' + IntToStr(Ord(R)) + ')');
    WriteLn('       A wrong --secret-file/--password and a damaged container ' +
      'are indistinguishable here by design; both fail closed.');
    Exit(EXIT_UNPACK);
  end;

  Text := TEncoding.UTF8.GetString(LoadedBytes);
  AvroWipeAndRelease(LoadedBytes);

  Json := TJSONObject.ParseJSONValue(Trim(Text));
  if Json = nil then
  begin
    WriteLn('ERROR: the unpacked payload is not valid JSON');
    Exit(EXIT_UNPACK);
  end;
  try
    // The icon is a build artifact of assets\icons\*.ico, not authoring
    // content. Leaving a multi-kilobyte Base64 blob in the unpacked document
    // would make it undiffable against the authored sources, which is the only
    // reason --unpack exists. The next build's --icon puts it back.
    HadIcon := False;
    if Json is TJSONObject then
    begin
      var IconPair: TJSONPair := TJSONObject(Json).RemovePair(AVRO_ICON_SECTION);
      HadIcon := IconPair <> nil;
      // RemovePair hands ownership to the caller.
      IconPair.Free;
    end;
    Pretty := PrettyJson(Json, 0);
  finally
    Json.Free;
  end;

  // No trailing line break: the authoring files end at '}' and the round trip
  // is checked byte for byte against them.
  if not WriteTextFileUtf8Bom(OutputPath, Pretty) then
  begin
    WriteLn('ERROR: cannot write output file: ' + OutputPath);
    Exit(EXIT_WRITE);
  end;

  if not Quiet then
  begin
    Version := 0;
    if Length(Data) >= 9 then
      Version := Data[8];
    WriteLn('unpack: ' + InputPath);
    WriteLn('format: shield v' + IntToStr(Version));
    if Options.IncludeComments then
      WriteLn('comments: restored (developer comment key applied)')
    else if CommentKeyFailed then
      WriteLn('comments: NOT decoded - this comment key does not match the ' +
        'container (the mapping itself is intact)')
    else
      WriteLn('comments: omitted (no --comments-key-file; add one to see them)');
    if HadIcon then
      WriteLn('icon    : dropped from the output (rebuild with --icon to re-add it)');
    WriteLn('output: ' + OutputPath);
    WriteLn('OK');
  end;
  Result := EXIT_OK;
end;

var
  JsonText: string;
  OutBytes: TBytes;
  ExitCode: Integer;
  SrcSize, OutSize: Integer;

begin
  ExitCode := EXIT_USAGE;

  if not ParseArgs then
  begin
    Usage;
    ExitCode := EXIT_USAGE;
  end
  else if not ReadCommentsKey then
  begin
    WriteLn('ERROR: cannot read comment key file (missing or empty): ' +
      CommentsKeyPath);
    ExitCode := EXIT_KEYFILE;
  end
  else if UnpackMode then
    ExitCode := UnpackContainer
  else if UseDefaultKey and (ContainerFormat = FORMAT_SHIELD) and
    (not ReadKeyFile(SecretFilePath, KeyIKM)) then
  begin
    WriteLn('ERROR: cannot read secret file (missing or empty): ' +
      SecretFilePath);
    WriteLn('       Expected the raw default-key IKM bytes. Generate with:');
    WriteLn('         python AvroEncoEngine\tools\AvroShieldSecretGen\' +
      'gen_shield_secret.py --secret <phrase> --key-file keys\avroenco.key');
    ExitCode := EXIT_KEYFILE;
  end
  else if not ReadUtf8File(InputPath, JsonText) then
  begin
    WriteLn('ERROR: cannot read input file: ' + InputPath);
    ExitCode := EXIT_READ;
  end
  else if not BuildDocumentText(JsonText, BuildJsonText) then
    ExitCode := IconErrCode
  else
  begin
    // Validate the input parses as a JSON object before doing any crypto.
    var RootJson: TJSONValue := TJSONObject.ParseJSONValue(Trim(JsonText));
    if (RootJson = nil) or not (RootJson is TJSONObject) then
    begin
      WriteLn('ERROR: input is not a valid JSON object: ' + InputPath);
      RootJson.Free;
      ExitCode := EXIT_PARSE;
    end
    else
    begin
      RootJson.Free;
      ExitCode := EXIT_BUILD;

      if ContainerFormat = FORMAT_SHIELD then
      begin
        // Without a comment key the comment fields fall back to the value
        // domain, which keeps the runtime able to read them with the container
        // key alone. Shipped builds always pass one (build_avroenco.bat).
        if (Length(CommentsIKM) = 0) and (not Quiet) then
          WriteLn('warning: no --comments-key-file, comments use the value domain');
        var R: TAvroShieldResult := AvroShieldBuildFromJson(BuildJsonText, Password,
          UseDefaultKey, BindMachine, UseHardware, OutBytes, KeyIKM, CommentsIKM);
        if R <> asrOk then
        begin
          WriteLn('ERROR: shield build failed (code ' + IntToStr(Ord(R)) + ')');
          ExitCode := EXIT_BUILD;
        end
        else if not WriteOutputBytes(OutputPath, OutBytes) then
        begin
          WriteLn('ERROR: cannot write output file: ' + OutputPath);
          ExitCode := EXIT_WRITE;
        end
        else
        begin
          ExitCode := EXIT_OK;
          if not NoVerify then
          begin
            // Verify with the same options the build used, comments included:
            // the load-back then covers the comment domain too.
            var VerifyOpts: TAvroShieldLoadOptions := AvroShieldDefaultLoadOptions;
            VerifyOpts.IncludeComments := True;
            VerifyOpts.DefaultSecretIKM := KeyIKM;
            VerifyOpts.CommentsIKM := CommentsIKM;
            if not VerifyRoundTrip(BuildJsonText, Password, UseDefaultKey, OutBytes,
              VerifyOpts, ErrMsg) then
            begin
              WriteLn('ERROR: verification failed - ' + ErrMsg);
              if UseDefaultKey then
              begin
                // The loader always uses the secret embedded in uAvroShield.
                // A key file that differs from it produces a container that
                // only loads once the runtime is rebuilt with the same secret.
                WriteLn('       Hint: the load-back check uses the secret embedded');
                WriteLn('       in uAvroShield. A --secret-file that does not match');
                WriteLn('       it can never round-trip. Rotate with');
                WriteLn('       gen_shield_secret.py --out-pas, then rebuild.');
              end;
              ExitCode := EXIT_VERIFY;
            end
            else if not Quiet then
              WriteLn('verify: PASS (runtime loader round-trip)');
          end;
        end;
      end
      else // FORMAT_V2
      begin
        if not EncryptJsonToAvroEncoFile(BuildJsonText, AnsiString(Password), OutputPath) then
        begin
          WriteLn('ERROR: v2 build failed');
          ExitCode := EXIT_BUILD;
        end
        else
        begin
          ExitCode := EXIT_OK;
          if not NoVerify then
          begin
            // Load the v2 container back through the runtime reader.
            var Loaded: string := Trim(DecryptAvroEncoToString(OutputPath, AnsiString(Password)));
            var JsonA: TJSONValue := TJSONObject.ParseJSONValue(Trim(BuildJsonText));
            var JsonB: TJSONValue := TJSONObject.ParseJSONValue(Loaded);
            if (JsonA = nil) or (JsonB = nil) or (not JsonTreesEqual(JsonA, JsonB)) then
            begin
              WriteLn('ERROR: verification failed - v2 round-trip mismatch');
              ExitCode := EXIT_VERIFY;
            end
            else if not Quiet then
              WriteLn('verify: PASS (v2 runtime loader round-trip)');
            JsonA.Free;
            JsonB.Free;
          end;
        end;
      end;
    end;
  end;

  // The key IKM is no longer needed once the container is built and verified.
  AvroWipeAndRelease(KeyIKM);

  if not Quiet then
  begin
    // UnpackContainer prints its own summary; this block is the build report.
    if (ExitCode = EXIT_OK) and (not UnpackMode) then
    begin
      SrcSize := Length(TEncoding.UTF8.GetBytes(JsonText));
      OutSize := 0;
      if FileExists(OutputPath) then
      begin
        try
          OutSize := Integer(TFile.GetSize(OutputPath));
        except
          OutSize := 0;
        end;
      end;
      if ContainerFormat = FORMAT_SHIELD then
      begin
        Write('format: shield, flags: ');
        if UseDefaultKey then
          Write('default-key')
        else
          Write('password');
        if BindMachine then
          Write(' +machine-bind');
        if UseHardware then
          Write(' +hardware');
        WriteLn;
      end
      else
      begin
        Write('format: v2 (');
        if Password = '' then
          Write('default-key')
        else
          Write('password');
        WriteLn(')');
      end;
      WriteLn('input : ' + IntToStr(SrcSize) + ' bytes');
      Write('output: ' + IntToStr(OutSize) + ' bytes');
      if (SrcSize > 0) and (OutSize > 0) then
        Write(Format(' (%.1f%% of source)', [100.0 * OutSize / SrcSize]));
      WriteLn;
      if IconPath <> '' then
        WriteLn('icon  : ' + ExtractFileName(IconPath) + ', frames ' +
          SizesText(IconSizes) + ', ' + IntToStr(Length(IconSectionBase64)) +
          ' Base64 chars in the payload');
      WriteLn('OK: ' + OutputPath);
    end;
  end;

  Halt(ExitCode);
end.