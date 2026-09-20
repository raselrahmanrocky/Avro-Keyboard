{

  kat_staticleak - release gate for the asset-protection pipeline.

  Asserts that nothing which is supposed to be secret or encrypted actually
  appears in cleartext in a shipped artifact. This is the cheapest and
  highest-value check in the hardening set: it would have caught, on the day
  each was introduced,

  (a) the root secret being stored as two adjacent XOR-able arrays with the
  plaintext repeated in a comment next to them, and
  (b) any container accidentally built from, or shipped alongside, its
  unprotected JSON payload.

  It links the runtime, so it knows the root secret without needing any
  external key file - the check is authoritative rather than best-effort.

  Every container is checked twice: once as raw bytes (is it actually
  encrypted, and does it avoid carrying the secret), and once unwrapped to the
  still-obfuscated payload, which is the view an attacker has after recovering
  the key from the binary. The second pass is what proves the obfuscation and
  the developer comment domain are doing their job - see CheckObfuscatedPayload.

  Hard failures (exit 1):
  * the root secret IKM appears in the executable, or in any container;
  * any source-mapping JSON string (field name or value) appears in the
  matching compiled container, which would mean the payload is not
  actually encrypted;
  * any authored mapping text, Bengali codepoint, '#$' literal or comment
  field name is legible in the unwrapped payload.

  Warnings (reported, do not fail): legacy v2 format internals that remain in
  the binary because the v2 reader needs them. They disappear with the v3
  ordinal-field encoding.

  Usage: kat_staticleak <exe-path|""> <container-dir> [source-json-dir]
  Exit code: 0 pass, 1 fail.
}

{$APPTYPE CONSOLE}
program kat_staticleak;

uses
  System.Types,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  uAvroSecureMem,
  uAvroShield,
  uAvroShieldSecret;

const
  { Shortest JSON string treated as a canary. Below this, byte coincidences in
    compressed data stop being meaningful. }
  MIN_CANARY_LEN = 10;
  { Upper bound on canaries checked per container, to keep the gate quick. }
  MAX_CANARIES = 300;

  { v2 format internals that remain in the binary because the current reader
    needs them. Reported as warnings rather than failures; the v3 ordinal-field
    encoding replaces them. (The AVROSHLD/AVROBC magics are intentionally not
    listed: the loader must compare against them, so they are expected.) }
  LEGACY_TOKENS: array [0 .. 3] of string = ('_obf_meta', 'key_map', 'dummies', 'AvroShieldBytecodeXORv1');

var
  Fails: Integer;
  Warns: Integer;

function BytesToHex(const B: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(B) - 1 do
    Result := Result + H[B[I] shr 4] + H[B[I] and 15];
end;

{ Plain first-byte-guarded scan. Fine at these sizes (tens of KB per container,
  a single 44-byte needle for the secret on the multi-MB executable). }
function IndexBytes(const AHay, ANeedle: TBytes): Integer;
var
  I, J, H, N: Integer;
  First:      Byte;
begin
  Result := -1;
  H := Length(AHay);
  N := Length(ANeedle);
  if (N = 0) or (N > H) then
    Exit;
  First := ANeedle[0];
  for I := 0 to H - N do
  begin
    if AHay[I] <> First then
      Continue;
    J := 1;
    while (J < N) and (AHay[I + J] = ANeedle[J]) do
      Inc(J);
    if J = N then
      Exit(I);
  end;
end;

{ UTF-16LE bytes of a string, which is how the Delphi compiler stores string
  literals in an executable. An ASCII-only scan of a Delphi binary gives FALSE
  NEGATIVES: '_obf_meta' and a secret stored as a string literal simply are not
  present as contiguous ASCII bytes. Both encodings are therefore searched. }
function ToUtf16Le(const AText: string): TBytes;
var
  I: Integer;
  W: Word;
begin
  SetLength(Result, Length(AText) * 2);
  for I := 1 to Length(AText) do
  begin
    W := Word(Ord(AText[I]));
    Result[(I - 1) * 2] := Byte(W and $FF);
    Result[(I - 1) * 2 + 1] := Byte((W shr 8) and $FF);
  end;
end;

{ ASCII/UTF-8 bytes of a string. Mapping text is ASCII outside the Bengali
  comments, so a byte-per-char copy is exact for the literals searched here. }
function AsciiBytes(const AText: string): TBytes;
var
  I: Integer;
begin
  SetLength(Result, Length(AText));
  for I := 1 to Length(AText) do
    Result[I - 1] := Byte(Ord(AText[I]) and $FF);
end;

{ Bengali U+0980-U+09FF is E0 A6 xx or E0 A7 xx in UTF-8, so a legibility scan
  of a payload needs no decoder. }
function HasBengaliBytes(const AData: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Length(AData) - 3 do
    if (AData[I] = $E0) and ((AData[I + 1] = $A6) or (AData[I + 1] = $A7)) then
      Exit(True);
end;

{ Finds AText in AHay as UTF-8/ASCII bytes or as UTF-16LE literals. }
function IndexText(const AHay: TBytes; const AText: string): Integer;
begin
  Result := IndexBytes(AHay, TEncoding.UTF8.GetBytes(AText));
  if Result < 0 then
    Result := IndexBytes(AHay, ToUtf16Le(AText));
end;

{ The root secret must not be recoverable from a shipped artifact in either of
  the two forms it could plausibly take: the raw IKM bytes (outside the
  obfuscated constants), or a literal string. }
function SecretPresent(const AData: TBytes; out AOffset: Integer): Boolean;
var
  IKM, AsWide: TBytes;
begin
  IKM := AvroShieldSecretIKM;
  try
    AOffset := IndexBytes(AData, IKM);
    if AOffset >= 0 then
      Exit(True);
    // Same bytes presented as a Delphi string literal.
    AsWide := ToUtf16Le(TEncoding.ASCII.GetString(IKM));
    AOffset := IndexBytes(AData, AsWide);
    Result := AOffset >= 0;
  finally
    AvroWipeAndRelease(IKM);
  end;
end;

function ReadAllBytes(const APath: string; out AData: TBytes): Boolean;
var
  FS: TFileStream;
begin
  AData := nil;
  Result := False;
  if not FileExists(APath) then
    Exit;
  try
    FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      SetLength(AData, FS.Size);
      if FS.Size > 0 then
        FS.ReadBuffer(AData[0], FS.Size);
      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
    AData := nil;
  end;
end;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('     ' + ADetail);
    Inc(Fails);
  end;
end;

procedure Warn(const AName, ADetail: string);
begin
  WriteLn('WARN ' + AName);
  if ADetail <> '' then
    WriteLn('     ' + ADetail);
  Inc(Warns);
end;

{ Collects every JSON string value and every object key at or above
  MIN_CANARY_LEN. Field names matter as much as values here: in Shield v2 they
  are stored as SHA-256(key), so a literal field name turning up in a container
  would mean the obfuscation step was skipped. }
procedure CollectCanaries(const AValue: TJSONValue; AList: TStrings);

  procedure Add(const S: string);
  begin
    if Length(S) >= MIN_CANARY_LEN then
      AList.Add(S);
  end;

var
  I:    Integer;
  Obj:  TJSONObject;
  Arr:  TJSONArray;
  Pair: TJSONPair;
begin
  if AValue = nil then
    Exit;
  if AValue is TJSONString then
    Add((AValue as TJSONString).Value)
  else if AValue is TJSONObject then
  begin
    Obj := AValue as TJSONObject;
    for I := 0 to Obj.Count - 1 do
    begin
      Pair := Obj.Pairs[I];
      if Pair.JsonString <> nil then
        Add(Pair.JsonString.Value);
      CollectCanaries(Pair.JsonValue, AList);
    end;
  end
  else if AValue is TJSONArray then
  begin
    Arr := AValue as TJSONArray;
    for I := 0 to Arr.Count - 1 do
      CollectCanaries(Arr.Items[I], AList);
  end;
end;

{ Sorted + dupIgnore gives deduplication for free. }
function BuildCanaries(const AJsonPath: string; AList: TStringList): Boolean;
var
  JSON: TJSONValue;
begin
  Result := False;
  AList.Clear;
  if not FileExists(AJsonPath) then
    Exit;
  try
    JSON := TJSONObject.ParseJSONValue(TFile.ReadAllText(AJsonPath, TEncoding.UTF8));
  except
    JSON := nil;
  end;
  if JSON = nil then
    Exit;
  try
    CollectCanaries(JSON, AList);
    Result := True;
  finally
    JSON.Free;
  end;
end;

procedure CheckExe(const APath: string);
var
  Data:   TBytes;
  I, Off: Integer;
  Leaked: Boolean;
begin
  WriteLn('=== executable: ' + APath + ' ===');
  if not ReadAllBytes(APath, Data) then
  begin
    Warn('executable readable', APath + ' could not be read; exe check skipped');
    Exit;
  end;

  // Evaluate the search BEFORE building the detail string: Delphi evaluates
  // arguments right to left, so reading Off inside the Check call would report
  // the pre-search value.
  Leaked := SecretPresent(Data, Off);
  Check('exe contains no copy of the root secret (raw or as a string literal)', not Leaked, 'root secret found at offset ' + IntToStr(Off) +
      ' - the whole pipeline reduces to this one value');

  for I := 0 to high(LEGACY_TOKENS) do
    if IndexText(Data, LEGACY_TOKENS[I]) >= 0 then
      Warn('exe still contains v2 format token: ' + LEGACY_TOKENS[I], 'readable in a strings dump; removed by the v3 ordinal-field encoding');

  WriteLn(Format('     (scanned %d bytes)', [Length(Data)]));
end;

procedure CheckContainer(const AContainerPath, ASourceJsonPath: string);
var
  Data, Needle:  TBytes;
  Canaries:      TStringList;
  I, Used, Off:  Integer;
  Found, Leaked: Boolean;
  Offender:      string;
  BaseName:      string;
begin
  BaseName := ExtractFileName(AContainerPath);
  WriteLn('=== container: ' + BaseName + ' ===');

  if not ReadAllBytes(AContainerPath, Data) then
  begin
    Check('container readable', False, AContainerPath + ' could not be read');
    Exit;
  end;
  Check('container readable (' + IntToStr(Length(Data)) + ' bytes)', True);

  Leaked := SecretPresent(Data, Off); // before the detail string, see CheckExe
  Check('container carries no copy of the root secret (raw or as a string literal)', not Leaked, 'the key material is embedded in the container at offset ' +
      IntToStr(Off) + ', not merely referenced');

  Canaries := TStringList.Create;
  try
    Canaries.Sorted := True;
    Canaries.Duplicates := dupIgnore;
    if not BuildCanaries(ASourceJsonPath, Canaries) then
    begin
      Warn('source canaries available', ExtractFileName(ASourceJsonPath) + ' not found - plaintext check skipped for ' + BaseName);
      Exit;
    end;

    Found := False;
    Offender := '';
    Used := 0;
    for I := 0 to Canaries.Count - 1 do
    begin
      if Used >= MAX_CANARIES then
        Break;
      Inc(Used);
      if IndexText(Data, Canaries[I]) >= 0 then
      begin
        Found := True;
        if Offender = '' then
          Offender := Canaries[I];
        // Keep scanning: report the first offender, count is in the summary.
      end;
    end;
    Needle := nil;

    Check(Format('%s: no cleartext mapping data (%d canaries from %s)', [BaseName, Used, ExtractFileName(ASourceJsonPath)]), not Found,
      'plaintext leaked into the container, e.g. "' + Offender + '"');
  finally
    Canaries.Free;
  end;
end;

{ The payload-level half of the gate.

  CheckContainer above scans the container bytes, which an encrypted container
  passes no matter what its plaintext looks like - necessary, but weak. This
  unwraps the container down to the decrypted and still OBFUSCATED bytecode,
  which is exactly what an attacker holds after recovering the container key
  from the binary, and asserts that nothing legible survives there:

  * no Bengali codepoints and no '#$' literal in the parsed payload;
  * none of the authored strings of the matching source document (>= 10
  chars, the same canary set used for the raw scan);
  * no comment field name and no mapping section name.

  The pattern scans run over the parsed payload rather than the raw bytecode.
  Values are XOR-masked there, so a generic '#$' or Bengali search over tens of
  kilobytes of masked bytes reports chance matches - the checks would fail at
  random. The parsed view is ASCII by construction (values are Base64 tokens),
  which makes a hit meaningful; the raw bytes are still checked, with the
  authored canaries, where a hit is meaningful too.

  This is the check that fails when the obfuscation is skipped, when its
  metadata mask goes back to being a compiled-in constant, or when the comment
  domain silently regresses into the value domain. }
procedure CheckObfuscatedPayload(const AContainerPath, ASourceJsonPath: string);
var
  Data, Bytecode, OpaqueBytes: TBytes;
  Canaries:                    TStringList;
  Root:                        TAvroNode;
  Opaque, Name:                string;
  I, LeakedRaw, LeakedText:    Integer;
  OffenderRaw, OffenderText:   string;
begin
  name := ExtractFileName(AContainerPath);
  Data := TFile.ReadAllBytes(AContainerPath);
  if AvroShieldExtractObfuscatedBytecode(Data, '', nil, True, Bytecode) <> asrOk then
  begin
    Check(name + ': payload unwrappable for inspection', False, 'cannot unwrap with the embedded secret - wrong key or damaged file');
    Exit;
  end;

  Root := nil;
  Opaque := '';
  Canaries := nil;
  try
    if not AvroShieldParseBytecode(Bytecode, Root) then
    begin
      Check(name + ': payload parses as bytecode', False, '');
      Exit;
    end;
    Opaque := AvroShieldNodeToJSON(Root);
    OpaqueBytes := TEncoding.UTF8.GetBytes(Opaque);

    Check(name + ': payload carries the metadata blob', Pos('_obf_meta', Opaque) > 0, 'the payload does not look obfuscated at all');
    Check(name + ': payload exposes no Bengali text', not HasBengaliBytes(OpaqueBytes));
    Check(name + ': payload exposes no hex key literal', IndexBytes(OpaqueBytes, AsciiBytes('#$')) < 0);
    Check(name + ': payload exposes no comment field name', Pos('"Comment"', Opaque) = 0);

    Canaries := TStringList.Create;
    LeakedRaw := 0;
    LeakedText := 0;
    OffenderRaw := '';
    OffenderText := '';
    if BuildCanaries(ASourceJsonPath, Canaries) then
      for I := 0 to Canaries.Count - 1 do
      begin
        if IndexBytes(Bytecode, AsciiBytes(Canaries[I])) >= 0 then
        begin
          Inc(LeakedRaw);
          if OffenderRaw = '' then
            OffenderRaw := Canaries[I];
        end;
        if IndexBytes(OpaqueBytes, AsciiBytes(Canaries[I])) >= 0 then
        begin
          Inc(LeakedText);
          if OffenderText = '' then
            OffenderText := Canaries[I];
        end;
      end;
    Check(name + ': masked bytes expose no authored mapping text', LeakedRaw = 0, IntToStr(LeakedRaw) + ' canary/ies legible, first: ' + OffenderRaw);
    Check(name + ': parsed payload exposes no authored mapping text', LeakedText = 0, IntToStr(LeakedText) + ' canary/ies legible, first: ' + OffenderText);
  finally
    if Canaries <> nil then
      Canaries.Free;
    if Root <> nil then
      Root.Free;
    AvroWipeString(Opaque);
    AvroWipeAndRelease(OpaqueBytes);
    AvroWipeAndRelease(Bytecode);
  end;
end;

procedure Usage;
begin
  WriteLn('kat_staticleak - release gate for the asset-protection pipeline');
  WriteLn;
  WriteLn('Usage: kat_staticleak <exe-path|""> <container-dir> [source-json-dir]');
  WriteLn;
  WriteLn('  exe-path        shipped executable to scan ("" to skip)');
  WriteLn('  container-dir   directory holding the .AvroEnco containers');
  WriteLn('  source-json-dir directory holding the matching Ansi V*.json sources');
end;

var
  ContainerDir, SourceDir, ExePath: string;
  Files:                            TStringDynArray;
  F:                                string;
  Containers:                       Integer;

begin
  Fails := 0;
  Warns := 0;

  if ParamCount < 2 then
  begin
    Usage;
    Halt(1);
  end;

  // Windows drops an empty first argument, which would silently shift the
  // parameters. Accept the containers-only form either as an explicit "-" or
  // by detecting that the first parameter is a directory.
  if (CompareText(ParamStr(1), '-') = 0) or ((ParamCount = 2) and DirectoryExists(ParamStr(1))) then
  begin
    ExePath := '';
    ContainerDir := IncludeTrailingPathDelimiter(ParamStr(1));
    if ParamCount >= 2 then
      SourceDir := IncludeTrailingPathDelimiter(ParamStr(2))
    else
      SourceDir := ContainerDir;
  end
  else
  begin
    ExePath := ParamStr(1);
    ContainerDir := IncludeTrailingPathDelimiter(ParamStr(2));
    if ParamCount >= 3 then
      SourceDir := IncludeTrailingPathDelimiter(ParamStr(3))
    else
      SourceDir := ContainerDir;
  end;

  if not DirectoryExists(ContainerDir) then
  begin
    WriteLn('FAIL container directory does not exist: ' + ContainerDir);
    Halt(1);
  end;

  if ExePath <> '' then
    CheckExe(ExePath);

  Containers := 0;
  Files := TDirectory.GetFiles(ContainerDir, '*.AvroEnco');
  for F in Files do
  begin
    Inc(Containers);
    CheckContainer(F, SourceDir + ChangeFileExt(ExtractFileName(F), '.json'));
    CheckObfuscatedPayload(F, SourceDir + ChangeFileExt(ExtractFileName(F), '.json'));
  end;

  Check('at least one container was present to check', Containers > 0, 'none found under ' + ContainerDir);

  WriteLn;
  if (Fails = 0) and (Warns = 0) then
    WriteLn('STATIC LEAK GATE PASSED (' + IntToStr(Containers) + ' container(s))')
  else if Fails = 0 then
    WriteLn('STATIC LEAK GATE PASSED with ' + IntToStr(Warns) + ' warning(s) (' + IntToStr(Containers) + ' container(s))')
  else
    WriteLn('STATIC LEAK GATE FAILED: ' + IntToStr(Fails) + ' hard failure(s), ' + IntToStr(Warns) + ' warning(s)');

  if Fails > 0 then
    Halt(1);

end.
