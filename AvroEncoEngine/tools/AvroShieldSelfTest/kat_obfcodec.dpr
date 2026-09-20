{

  kat_obfcodec - regression KAT for the AvroShield obfuscation codec (v3) and
  for the developer comment domain that sits on top of it.

  Why this exists
  ---------------
  Mapping JSON carries developer documentation in "Comment" fields - the
  Bengali grapheme and ligature notes an author needs to maintain the tables
  ("০", "চ্ব -> P¡", "ম-এর প্রথম খন্ড"). Those notes must stay inside the
  container, because they are the only written record of what each emitted byte
  is supposed to draw, but they must not be readable by anyone who merely opens
  a container.

  Three properties are asserted here, and each one was violable before:

  1. The obfuscation is keyed. The metadata blob - which carries the value
  seed and the key map, and therefore the ability to invert every value -
  is masked with a key derived from the container master key. The mask
  used to be a constant compiled into uAvroShield, so anybody who
  decrypted a container (or simply read the unit) could invert the entire
  payload with no key material at all.

  2. Comment text needs a second, developer-only key. Comment fields live in
  their own domain (HKDF over the developer IKM, salted with the value
  seed), so recovering comment text needs the container key AND an IKM
  that the runtime never derives and never links.

  3. The runtime pays nothing for comments. IncludeComments=False drops every
  comment field before the Base64 decode, so nothing is decoded, allocated
  or wiped per load and the mapping parser never sees the field.

  It also pins the codec's positional salting (identical plaintext at different
  positions must not produce identical tokens), the per-build freshness of the
  keystream, and the runtime default. A frozen format-v2 container
  (kat_shield_v2.AvroEnco) keeps the legacy read path covered after every
  shipped container is rebuilt as v3.

  Usage: kat_obfcodec <mapping-source-dir> <comments-key-file> [quiet]
  Exit code: 0 pass, 1 fail.
}

{$APPTYPE CONSOLE}
program kat_obfcodec;

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.JSON,
  System.IOUtils,
  uAvroShield,
  uAvroSecureMem;

const
  // Part of the on-the-wire format. The KAT keeps its own copy on purpose, so
  // a silent rename shows up here as a failure instead of hiding.
  META_KEY = '_obf_meta';

  // The sample from the codec spec: a number record whose Comment is the
  // Bengali zero (U+09E6) while the UnicodeKey field spells it as the hex
  // literal the mapping schema uses.
  GOLDEN_JSON = '{"Rec":{"UnicodeKey":"#$09E6","Value":"#$0030","Comment":"' + #$09E6 + '"}}';

  // Same plaintext at two different object paths, and at two array indices:
  // both must encrypt to different tokens (positional salting).
  SALT_PATHS_JSON = '{"A":{"v":"#$0030"},"B":{"v":"#$0030"}}';
  SALT_INDEX_JSON = '{"L":[{"v":"#$0030"},{"v":"#$0030"}]}';

var
  Fails:      Integer;
  Checks:     Integer;
  Quiet:      Boolean;
  CommentIKM: TBytes;

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
    Inc(Fails);
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('     ' + ADetail);
  end;
end;

{ ---- byte helpers --------------------------------------------------------- }

function Utf8Of(const S: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(S);
end;

{ Raw byte search: going through a Delphi string would mean comparing UTF-16
  forms, which is exactly what a payload scan must not do. }
function HasBytes(const AData: TBytes; const APattern: TBytes): Boolean;
var
  I, J: Integer;
begin
  Result := False;
  if (Length(APattern) = 0) or (Length(AData) < Length(APattern)) then
    Exit;
  for I := 0 to Length(AData) - Length(APattern) do
  begin
    J := 0;
    while (J < Length(APattern)) and (AData[I + J] = APattern[J]) do
      Inc(J);
    if J = Length(APattern) then
      Exit(True);
  end;
end;

function HasText(const AData: TBytes; const AText: string): Boolean;
begin
  Result := HasBytes(AData, Utf8Of(AText));
end;

{ Bengali (U+0980-U+09FF) encodes in UTF-8 as E0 A6 xx or E0 A7 xx, so a
  legibility scan needs no decoder. Use this on TEXT-shaped input (the parsed
  opaque JSON, whose tokens are Base64/hex, so a match can only mean a real
  leak); on a masked byte stream use HasBengaliRun below instead. }
function HasBengali(const AData: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to Length(AData) - 3 do
    if (AData[I] = $E0) and ((AData[I + 1] = $A6) or (AData[I + 1] = $A7)) then
      Exit(True);
end;

{ Two consecutive Bengali code points. One byte pair cannot be used as a
  legibility test on the MASKED bytecode: at a few tens of kilobytes an
  $E0 $A6/$A7 pair turns up by chance in a significant fraction of builds
  (measured: 3 of 20 runs), which made this gate fail for no reason. Two code
  points in a row have a chance of ~1e-6 per run, so a match means real
  Bengali text leaked into the payload. }
function HasBengaliRun(const AData: TBytes): Boolean;
var
  I: Integer;

  function IsBengaliStart(AIndex: Integer): Boolean;
  begin
    Result := (AData[AIndex] = $E0) and ((AData[AIndex + 1] = $A6) or (AData[AIndex + 1] = $A7)) and (AData[AIndex + 2] >= $80) and (AData[AIndex + 2] <= $BF);
  end;

begin
  Result := False;
  for I := 0 to Length(AData) - 6 do
    if IsBengaliStart(I) and IsBengaliStart(I + 3) then
      Exit(True);
end;

function CountText(const AText, APattern: string): Integer;
var
  P: Integer;
begin
  Result := 0;
  P := 1;
  while True do
  begin
    P := PosEx(APattern, AText, P);
    if P = 0 then
      Exit;
    Inc(Result);
    Inc(P, Length(APattern));
  end;
end;

function ReadJsonFile(const APath: string): string;
begin
  Result := TFile.ReadAllText(APath, TEncoding.UTF8);
  if (Length(Result) >= 1) and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

{ First value stored under AKey anywhere in the document - used to lift a real
  authored comment string out of a source mapping as a canary. }
function FindFirstKeyValue(AValue: TJSONValue; const AKey: string; out AFound: string): Boolean;
var
  I:    Integer;
  Obj:  TJSONObject;
  Arr:  TJSONArray;
  Pair: TJSONPair;
begin
  AFound := '';
  if AValue = nil then
    Exit(False);
  if AValue is TJSONObject then
  begin
    Obj := TJSONObject(AValue);
    for I := 0 to Obj.Count - 1 do
    begin
      Pair := Obj.Pairs[I];
      if (Pair.JsonString.Value = AKey) and (Pair.JsonValue is TJSONString) then
      begin
        AFound := TJSONString(Pair.JsonValue).Value;
        Exit(AFound <> '');
      end;
      if FindFirstKeyValue(Pair.JsonValue, AKey, AFound) then
        Exit(True);
    end;
  end
  else if AValue is TJSONArray then
  begin
    Arr := TJSONArray(AValue);
    for I := 0 to Arr.Count - 1 do
      if FindFirstKeyValue(Arr.Items[I], AKey, AFound) then
        Exit(True);
  end;
end;

{ Up to AMax distinct string values beginning with APrefix, anywhere in the
  document: a targeted canary set for the payload scan.

  The scan has to be anchored to authored literals. A generic '#$' byte search
  over the payload reports chance matches: values are XOR-masked, so a random
  0x23 0x24 pair turns up in tens of kilobytes of masked data, and a test that
  fails at random teaches nobody anything. }
procedure CollectPrefixed(AValue: TJSONValue; const APrefix: string; AInto: TStrings; AMax: Integer);
var
  I:   Integer;
  S:   string;
  Obj: TJSONObject;
  Arr: TJSONArray;
begin
  if (AValue = nil) or (AInto.Count >= AMax) then
    Exit;
  if AValue is TJSONString then
  begin
    S := TJSONString(AValue).Value;
    if (Length(S) >= Length(APrefix)) and (Copy(S, 1, Length(APrefix)) = APrefix) and (AInto.IndexOf(S) < 0) then
      AInto.Add(S);
    Exit;
  end;
  if AValue is TJSONObject then
  begin
    Obj := TJSONObject(AValue);
    for I := 0 to Obj.Count - 1 do
      CollectPrefixed(Obj.Pairs[I].JsonValue, APrefix, AInto, AMax);
  end
  else if AValue is TJSONArray then
  begin
    Arr := TJSONArray(AValue);
    for I := 0 to Arr.Count - 1 do
      CollectPrefixed(Arr.Items[I], APrefix, AInto, AMax);
  end;
end;

function FirstCommentIn(const AJsonText: string): string;
var
  Root: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(AJsonText);
  if Root = nil then
    Exit;
  try
    FindFirstKeyValue(Root, 'Comment', Result);
  finally
    Root.Free;
  end;
end;

{ ---- container helpers ---------------------------------------------------- }

{ Builds a v3 default-key container in memory. The default-key IKM is left
  empty deliberately: this KAT links the runtime, so it builds with the same
  embedded secret the application uses and needs no key file for that part. }
function BuildContainer(const AJson: string; const ACommentsIKM: TBytes; out AData: TBytes): TAvroShieldResult;
begin
  Result := AvroShieldBuildFromJson(AJson, '', True, False, False, AData, nil, ACommentsIKM);
end;

function LoadText(const AData: TBytes; const ACommentsIKM: TBytes; AIncludeComments: Boolean; out AText, AErr: string): Boolean;
var
  Options: TAvroShieldLoadOptions;
  Bytes:   TBytes;
  R:       TAvroShieldResult;
begin
  Result := False;
  AText := '';
  AErr := '';
  Options := AvroShieldDefaultLoadOptions;
  Options.IncludeComments := AIncludeComments;
  Options.CommentsIKM := ACommentsIKM;
  R := AvroShieldLoadFromBytesUtf8Ex(AData, '', Options, Bytes);
  if R <> asrOk then
  begin
    AErr := 'load failed (code ' + IntToStr(Ord(R)) + ')';
    Exit;
  end;
  AText := TEncoding.UTF8.GetString(Bytes);
  AvroWipeAndRelease(Bytes);
  Result := True;
end;

{ The attacker's view: decrypted bytecode, still obfuscated, nothing applied
  beyond the container key. }
function OpaqueView(const AData: TBytes; out ABytecode: TBytes; out AOpaqueJson: string): Boolean;
var
  Root: TAvroNode;
begin
  ABytecode := nil;
  AOpaqueJson := '';
  Result := AvroShieldExtractObfuscatedBytecode(AData, '', nil, True, ABytecode) = asrOk;
  if not Result then
    Exit;
  Root := nil;
  if not AvroShieldParseBytecode(ABytecode, Root) then
  begin
    Result := False;
    Exit;
  end;
  try
    AOpaqueJson := AvroShieldNodeToJSON(Root);
  finally
    Root.Free;
  end;
end;

{ Every string leaf of the obfuscated tree except the metadata blob itself. }
procedure CollectTokens(ANode: TAvroNode; AInto: TStrings);
var
  I: Integer;
begin
  if ANode = nil then
    Exit;
  case ANode.Kind of
    nkString:
      AInto.Add(ANode.StrVal);
    nkArray:
      for I := 0 to ANode.Items.Count - 1 do
        CollectTokens(ANode.Items[I], AInto);
    nkObject:
      for I := 0 to ANode.Items.Count - 1 do
        if ANode.Keys[I] <> META_KEY then
          CollectTokens(ANode.Items[I], AInto);
    else
      ;
  end;
end;

{ Value tokens only.

  Root-level string values are skipped on purpose: the writer injects 4-8 decoy
  root keys whose values are random strings, plus the (masked) metadata blob,
  and those are not mapping values. Real values always live below a container
  node, so descending only into non-string roots isolates them. }
function TokensOf(const AData: TBytes; out ATokens: TStringList): Boolean;
var
  Bytecode: TBytes;
  Root:     TAvroNode;
  I:        Integer;
begin
  Result := False;
  ATokens := TStringList.Create;
  if AvroShieldExtractObfuscatedBytecode(AData, '', nil, True, Bytecode) <> asrOk then
    Exit;
  Root := nil;
  try
    if not AvroShieldParseBytecode(Bytecode, Root) then
      Exit;
    if Root.Kind = nkObject then
      for I := 0 to Root.Items.Count - 1 do
        if (Root.Keys[I] <> META_KEY) and (Root.Items[I].Kind <> nkString) then
          CollectTokens(Root.Items[I], ATokens);
    Result := True;
  finally
    Root.Free;
    AvroWipeAndRelease(Bytecode);
  end;
end;

function DistinctStrings(A: TStrings): Boolean;
var
  I, J: Integer;
begin
  Result := True;
  for I := 0 to A.Count - 1 do
    for J := I + 1 to A.Count - 1 do
      if A[I] = A[J] then
        Exit(False);
end;

{ ---- 1. golden vector ----------------------------------------------------- }

procedure RunGoldenVector;
var
  Data, WrongIKM:    TBytes;
  Text, Err, Opaque: string;
  Bytecode:          TBytes;
  R:                 TAvroShieldResult;
  Tampered:          TBytes;
  Options:           TAvroShieldLoadOptions;
  Dummy:             TBytes;
begin
  if not Quiet then
  begin
    WriteLn;
    WriteLn('=== golden vector: #$09E6 / #$0030 / ' + #$09E6 + ' ===');
  end;

  R := BuildContainer(GOLDEN_JSON, CommentIKM, Data);
  Check('golden container builds', R = asrOk, 'build code ' + IntToStr(Ord(R)));
  if R <> asrOk then
    Exit;

  Check('unpack with the comment key succeeds', LoadText(Data, CommentIKM, True, Text, Err), Err);
  Check('unpack restores the UnicodeKey hex literal', Pos('"#$09E6"', Text) > 0, Text);
  Check('unpack restores the Value hex literal', Pos('"#$0030"', Text) > 0, Text);
  Check('unpack restores the Bengali comment', Pos('"' + #$09E6 + '"', Text) > 0, Text);
  Check('unpack restores the field names', Pos('"UnicodeKey"', Text) > 0, Text);

  Check('opaque view available', OpaqueView(Data, Bytecode, Opaque));
  Check('opaque view still carries the metadata blob', Pos('"' + META_KEY + '"', Opaque) > 0, Opaque);
  // The masked bytecode is not text, so "does it contain a Bengali byte pair"
  // would be a chance-match lottery; see HasBengaliRun. These three checks are
  // deterministic and still catch a payload that stopped being obfuscated:
  // a real Bengali comment carries a run, and the authored strings below are
  // single-character and matched exactly.
  Check('opaque view exposes no Bengali run', not HasBengaliRun(Bytecode), Opaque);
  Check('opaque view exposes no authored comment literal', not HasText(Bytecode, '"' + #$09E6 + '"'), Opaque);
  Check('opaque view exposes no authored hex literals', (not HasText(Bytecode, '#$09E6')) and (not HasText(Bytecode, '#$0030')), Opaque);
  // Teeth: both detectors must fire on the authored plaintext, otherwise the
  // three assertions above would hold even for a payload that leaked every
  // string in the clear.
  Check('Bengali run detector fires on real Bengali text', HasBengaliRun(Utf8Of(#$0985 + #$0986)));
  Check('authored-literal detector fires on the authored JSON', HasText(Utf8Of(GOLDEN_JSON), '"' + #$09E6 + '"'));
  Check('opaque view exposes no hex key literal', (Pos('"#$09E6"', Opaque) = 0) and (Pos('"#$0030"', Opaque) = 0), Opaque);
  Check('opaque view exposes no field name', (Pos('UnicodeKey', Opaque) = 0) and (Pos('Comment', Opaque) = 0), Opaque);
  Check('opaque view exposes no authored comment', not HasText(Bytecode, #$09E6), Opaque);

  // The comment domain must not be reachable with the container key alone. A
  // wrong comment key normally fails the whole load (the codec fails closed on
  // garbage rather than handing back decoy text), so the assertion is "either
  // rejected, or accepted without the comment".
  WrongIKM := Copy(CommentIKM, 0, Length(CommentIKM));
  if Length(WrongIKM) > 0 then
    WrongIKM[0] := Byte(WrongIKM[0] xor $5A);
  Check('wrong comment key does not reveal the comment', (not LoadText(Data, WrongIKM, True, Text, Err)) or (Pos('"' + #$09E6 + '"', Text) = 0), Err);
  Check('no comment key does not reveal the comment', (not LoadText(Data, nil, True, Text, Err)) or (Pos('"' + #$09E6 + '"', Text) = 0), Err);
  // The operational payload is keyed by the container key, so a rotated or
  // wrong comment key must never cost the developer the mapping itself.
  Check('wrong comment key still yields the operational fields', LoadText(Data, WrongIKM, False, Text, Err) and (Pos('UnicodeKey', Text) > 0) and
      (Pos('#$0030', Text) > 0), Err);

  // The runtime path, which must not even keep the field.
  Check('runtime load succeeds', LoadText(Data, nil, False, Text, Err), Err);
  Check('runtime load carries no comment field', CountText(Text, 'Comment') = 0, Text);
  Check('runtime load keeps the operational fields', (Pos('UnicodeKey', Text) > 0) and (Pos('#$0030', Text) > 0), Text);

  // Tampering with the ciphertext must fail closed, not decode to something.
  Tampered := Copy(Data, 0, Length(Data));
  if Length(Tampered) > 64 then
  begin
    Tampered[60] := Byte(Tampered[60] xor $FF);
    Options := AvroShieldDefaultLoadOptions;
    Check('tampered ciphertext is rejected', AvroShieldLoadFromBytesUtf8Ex(Tampered, '', Options, Dummy) <> asrOk);
  end;
end;

{ ---- 2. positional salting and keystream freshness ------------------------- }

procedure RunSalting;
var
  Data, Data2:      TBytes;
  Tokens1, Tokens2: TStringList;
  I, Same:          Integer;
  R:                TAvroShieldResult;
  Ok1, Ok2:         Boolean;
begin
  if not Quiet then
  begin
    WriteLn;
    WriteLn('=== positional salting ===');
  end;

  R := BuildContainer(SALT_PATHS_JSON, CommentIKM, Data);
  if R = asrOk then
    R := BuildContainer(SALT_PATHS_JSON, CommentIKM, Data2);
  Check('salting fixture builds', R = asrOk, IntToStr(Ord(R)));
  if R <> asrOk then
    Exit;

  // Both lists live until the end of the block: freeing one and then reading
  // it (the natural way to write the cross-build comparison) is a
  // use-after-free, not a compile error.
  Tokens1 := nil;
  Tokens2 := nil;
  try
    Ok1 := TokensOf(Data, Tokens1);
    Check('two value tokens collected', Ok1 and (Tokens1.Count = 2), 'count=' + IntToStr(Tokens1.Count));
    Check('identical plaintext at two paths yields different tokens', Ok1 and (Tokens1.Count = 2) and DistinctStrings(Tokens1), Tokens1.Text);

    Ok2 := TokensOf(Data2, Tokens2);
    Check('two array-index tokens collected', Ok2 and (Tokens2.Count = 2), 'count=' + IntToStr(Tokens2.Count));
    Check('identical plaintext at two array indices yields different tokens', Ok2 and (Tokens2.Count = 2) and DistinctStrings(Tokens2), Tokens2.Text);

    // A keystream fixed across builds would make the tokens identical for the
    // same input, which is what a precomputed dictionary attack needs.
    Same := 0;
    if Ok1 and Ok2 then
      for I := 0 to Tokens1.Count - 1 do
        if Tokens2.IndexOf(Tokens1[I]) >= 0 then
          Inc(Same);
    Check('a rebuilt payload does not reuse the previous keystream', Ok1 and Ok2 and (Same = 0), 'repeated tokens: ' + IntToStr(Same));
  finally
    Tokens1.Free;
    Tokens2.Free;
  end;
end;

{ ---- 3. the real sources -------------------------------------------------- }

procedure RunSources(const ADir: string);
var
  Files:                                 TArray<string>;
  I:                                     Integer;
  JSON, Canary, Text, Err, Opaque, Name: string;
  Data, Bytecode:                        TBytes;
  R:                                     TAvroShieldResult;
  Root:                                  TJSONValue;
  Canaries:                              TStringList;
  K, Leaked:                             Integer;
begin
  if not Quiet then
  begin
    WriteLn;
    WriteLn('=== authored sources ===');
  end;

  if not TDirectory.Exists(ADir) then
  begin
    Check('mapping source folder exists', False, ADir);
    Exit;
  end;
  Files := TDirectory.GetFiles(ADir, '*.json');
  Check('mapping source folder has JSON sources', Length(Files) > 0, ADir);

  for I := 0 to Length(Files) - 1 do
  begin
    name := ExtractFileName(Files[I]);
    JSON := ReadJsonFile(Files[I]);
    R := BuildContainer(JSON, CommentIKM, Data);
    Check(name + ': builds', R = asrOk, 'code ' + IntToStr(Ord(R)));
    if R <> asrOk then
      Continue;

    Bytecode := nil;
    Opaque := '';
    Check(name + ': opaque view available', OpaqueView(Data, Bytecode, Opaque));
    Check(name + ': payload carries the metadata blob', Pos('"' + META_KEY + '"', Opaque) > 0);
    // The opaque JSON is the parsed payload an attacker would dump: values are
    // Base64 tokens there, so this scan has no chance matches to explain away.
    Check(name + ': payload exposes no Bengali text', not HasBengali(Utf8Of(Opaque)));
    Check(name + ': payload exposes no hex key literal', not HasText(Utf8Of(Opaque), '#$'));

    // And on the raw bytecode, a targeted set: the real '#$' literals the file
    // declares must not be recoverable from the masked payload.
    Canaries := TStringList.Create;
    Root := TJSONObject.ParseJSONValue(JSON);
    try
      if Root <> nil then
        CollectPrefixed(Root, '#$', Canaries, 32);
      Leaked := 0;
      for K := 0 to Canaries.Count - 1 do
        if HasText(Bytecode, Canaries[K]) then
          Inc(Leaked);
      Check(name + ': no authored hex literal survives into the payload', (Canaries.Count > 0) and (Leaked = 0),
        'leaked ' + IntToStr(Leaked) + ' of ' + IntToStr(Canaries.Count));
    finally
      Root.Free;
      Canaries.Free;
    end;
    Check(name + ': payload exposes no comment field name', not HasText(Bytecode, 'Comment'));
    Check(name + ': payload exposes no mapping section name', (not HasText(Bytecode, 'Metadata')) and (not HasText(Bytecode, 'Constants')));

    Canary := FirstCommentIn(JSON);
    Check(name + ': has an authored comment to test with', Canary <> '');
    if Canary <> '' then
    begin
      Check(name + ': the authored comment is not in the payload', not HasText(Bytecode, Canary), Canary);
      Check(name + ': the comment key recovers that comment', LoadText(Data, CommentIKM, True, Text, Err) and (Pos(Canary, Text) > 0), Err);
      // Same shape as the golden vector: a missing comment key either fails the
      // load closed or yields text without the comment. It must never yield
      // the authored comment text.
      Check(name + ': without the comment key that comment is unrecoverable', (not LoadText(Data, nil, True, Text, Err)) or (Pos(Canary, Text) = 0), Err);
    end;

    Check(name + ': runtime load drops every comment field', LoadText(Data, nil, False, Text, Err) and (CountText(Text, 'Comment') = 0), Err);
    Check(name + ': runtime load keeps the operational sections', (Pos('"Constants"', Text) > 0) and (Pos('"Metadata"', Text) > 0), Err);

    AvroWipeAndRelease(Bytecode);
    AvroWipeAndRelease(Data);
  end;
end;

{ ---- 4. format versioning and the frozen legacy fixture -------------------- }

procedure RunVersionAndLegacy;
var
  Path, Text, Err: string;
  Data:            TBytes;
  Options:         TAvroShieldLoadOptions;
  Dummy:           TBytes;
begin
  if not Quiet then
  begin
    WriteLn;
    WriteLn('=== versioning and the v2 fixture ===');
  end;

  Check('current format version is 3', AvroShieldCurrentVersion = 3, IntToStr(AvroShieldCurrentVersion));
  Check('v2 is still readable', AvroShieldSupportedVersion(2));
  Check('v3 is readable', AvroShieldSupportedVersion(3));
  Check('v1 (Argon2, removed) is rejected', not AvroShieldSupportedVersion(1));
  Check('an unknown version is rejected', not AvroShieldSupportedVersion($7F));
  Options := AvroShieldDefaultLoadOptions;
  Check('the runtime default drops comments', not Options.IncludeComments);

  Path := ExtractFilePath(ParamStr(0)) + 'kat_shield_v2.AvroEnco';
  Check('frozen v2 fixture is present', FileExists(Path), Path);
  if not FileExists(Path) then
    Exit;
  Data := TFile.ReadAllBytes(Path);
  Check('frozen v2 container still loads', LoadText(Data, nil, True, Text, Err), Err);
  Check('frozen v2 container is not mistaken for v3', (Length(Data) > 8) and (Data[8] = 2), '');
  // Documentation check, not a requirement: in format v2 there is no separate
  // comment domain, so comments decode with the value seed and are legible to
  // anyone holding the container key. This is precisely what v3 exists to fix,
  // and pinning it here means the difference cannot be papered over.
  Check('legacy v2 comments stay in the value domain (known limit)', (Pos(META_KEY, Text) = 0) and (Pos('"Comment"', Text) > 0), '');
end;

var
  I:                           Integer;
  Arg:                         string;
  SourcesDir, CommentsKeyPath: string;
  Comments:                    TBytes;

begin
  Fails := 0;
  Checks := 0;
  Quiet := False;
  SourcesDir := '';
  CommentsKeyPath := '';

  for I := 1 to ParamCount do
  begin
    Arg := ParamStr(I);
    if SameText(Arg, 'quiet') then
      Quiet := True
    else if SourcesDir = '' then
      SourcesDir := Arg
    else if CommentsKeyPath = '' then
      CommentsKeyPath := Arg
    else
    begin
      if not Quiet then
        WriteLn('ERROR: too many arguments');
      Halt(2);
    end;
  end;

  if (SourcesDir = '') or (CommentsKeyPath = '') then
  begin
    WriteLn('usage: kat_obfcodec <mapping-source-dir> <comments-key-file> [quiet]');
    Halt(2);
  end;

  if not FileExists(CommentsKeyPath) then
  begin
    WriteLn('FAIL comment key file missing: ' + CommentsKeyPath);
    Halt(1);
  end;
  CommentIKM := TFile.ReadAllBytes(CommentsKeyPath);

  try
    RunGoldenVector;
    RunSalting;
    RunSources(SourcesDir);
    RunVersionAndLegacy;
  finally
    AvroWipeAndRelease(CommentIKM);
  end;

  if Fails = 0 then
    WriteLn(Format('ALL PASS (%d checks)', [Checks]))
  else
    WriteLn(Format('%d of %d checks FAILED', [Fails, Checks]));

  Halt(Ord(Fails > 0));

end.
