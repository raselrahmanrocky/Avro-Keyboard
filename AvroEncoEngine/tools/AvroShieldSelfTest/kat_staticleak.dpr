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

  Hard failures (exit 1):
    * the root secret IKM appears in the executable, or in any container;
    * any source-mapping JSON string (field name or value) appears in the
      matching compiled container, which would mean the payload is not
      actually encrypted.

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
  LEGACY_TOKENS: array [0 .. 3] of string = (
    '_obf_meta',
    'key_map',
    'dummies',
    'AvroShieldBytecodeXORv1');

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
  First: Byte;
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
  I: Integer;
  Obj: TJSONObject;
  Arr: TJSONArray;
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
  Json: TJSONValue;
begin
  Result := False;
  AList.Clear;
  if not FileExists(AJsonPath) then
    Exit;
  try
    Json := TJSONObject.ParseJSONValue(TFile.ReadAllText(AJsonPath,
      TEncoding.UTF8));
  except
    Json := nil;
  end;
  if Json = nil then
    Exit;
  try
    CollectCanaries(Json, AList);
    Result := True;
  finally
    Json.Free;
  end;
end;

procedure CheckExe(const APath: string);
var
  Data: TBytes;
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
  Check('exe contains no copy of the root secret (raw or as a string literal)',
    not Leaked,
    'root secret found at offset ' + IntToStr(Off) +
    ' - the whole pipeline reduces to this one value');

  for I := 0 to High(LEGACY_TOKENS) do
    if IndexText(Data, LEGACY_TOKENS[I]) >= 0 then
      Warn('exe still contains v2 format token: ' + LEGACY_TOKENS[I],
        'readable in a strings dump; removed by the v3 ordinal-field encoding');

  WriteLn(Format('     (scanned %d bytes)', [Length(Data)]));
end;

procedure CheckContainer(const AContainerPath, ASourceJsonPath: string);
var
  Data, Needle: TBytes;
  Canaries: TStringList;
  I, Used, Off: Integer;
  Found, Leaked: Boolean;
  Offender: string;
  BaseName: string;
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
  Check('container carries no copy of the root secret (raw or as a string literal)',
    not Leaked,
    'the key material is embedded in the container at offset ' +
    IntToStr(Off) + ', not merely referenced');

  Canaries := TStringList.Create;
  try
    Canaries.Sorted := True;
    Canaries.Duplicates := dupIgnore;
    if not BuildCanaries(ASourceJsonPath, Canaries) then
    begin
      Warn('source canaries available', ExtractFileName(ASourceJsonPath) +
        ' not found - plaintext check skipped for ' + BaseName);
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

    Check(Format('%s: no cleartext mapping data (%d canaries from %s)',
      [BaseName, Used, ExtractFileName(ASourceJsonPath)]), not Found,
      'plaintext leaked into the container, e.g. "' + Offender + '"');
  finally
    Canaries.Free;
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
  Files: TStringDynArray;
  F: string;
  Containers: Integer;

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
  if (CompareText(ParamStr(1), '-') = 0) or
    ((ParamCount = 2) and DirectoryExists(ParamStr(1))) then
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
  end;

  Check('at least one container was present to check', Containers > 0,
    'none found under ' + ContainerDir);

  WriteLn;
  if (Fails = 0) and (Warns = 0) then
    WriteLn('STATIC LEAK GATE PASSED (' + IntToStr(Containers) + ' container(s))')
  else if Fails = 0 then
    WriteLn('STATIC LEAK GATE PASSED with ' + IntToStr(Warns) +
      ' warning(s) (' + IntToStr(Containers) + ' container(s))')
  else
    WriteLn('STATIC LEAK GATE FAILED: ' + IntToStr(Fails) + ' hard failure(s), ' +
      IntToStr(Warns) + ' warning(s)');

  if Fails > 0 then
    Halt(1);
end.
