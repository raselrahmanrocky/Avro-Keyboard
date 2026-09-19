{

  kat_ansiconvert - conversion + mapping-parser gate for every ANSI mapping.

  Why this exists: "the .AvroEnco file does not work / the letters come out
  wrong" has three completely different causes, and without a test they all look
  the same from outside:

    1. the container pipeline is lossy (decrypt or bytecode round-trip changes
       the mapping),
    2. the mapping parser silently drops or mangles sections, so the engine runs
       on its built-in defaults instead of the mapping's own tables,
    3. the mapping document itself declares very little (an incomplete export):
       the engine then legitimately falls back to the hardcoded V1-tuned
       defaults, and the produced bytes belong to a different font than the one
       in use.

  This program separates them objectively, with no GUI:

    * CONTAINER == JSON: when a folder holds both a container and a plain JSON
      with the same base name, the same corpus must convert to byte-identical
      output through both. Any difference means the crypto/bytecode pipeline is
      lossy - cause 1.
    * PARSER FIDELITY: the loaded engine is serialized back to JSON
      (ExportAnsiMapping) and compared with the source document. Every section
      the source declares must still be there with at least as many entries, and
      every group name must survive verbatim. A section that shrinks or vanishes
      is the silent-drop failure mode - cause 2.
    * CENSUS + CORPUS DUMP: the effective per-section entry counts and the
      conversion of a fixed corpus are printed per mapping, so a document that
      declares almost nothing (cause 3) is visible at a glance instead of being
      guessed at.
    * No output may contain an unresolved-reference placeholder: that would mean
      the mapping referenced a constant the engine could not resolve, leaking
      literal text into typed output. The placeholder is detected as the two
      characters hash and open-brace, so this comment block stays parseable.

  Only the KAT's own temp file is written (inside %TEMP%).

  Usage: kat_ansiconvert <mapping-dir> [source-json-dir] [quiet]
  Exit code: 0 all PASS, 1 FAIL.
}

{$APPTYPE CONSOLE}

program kat_ansiconvert;

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Winapi.Windows,
  uAvroEncoCrypto,
  uAvroEncoManager,
  clsUnicodeToBijoy2000;

const
  // Bengali code points used to build the corpus without embedding any
  // non-ASCII byte in this source file.
  U_HASANTA = $09CD;
  U_AA = $0986; U_II = $0988; U_UU = $098A;
  U_K = $0995; U_G = $0997; U_C = $099A; U_J = $099C; U_NYA = $099E;
  U_T = $09A4; U_N = $09A8; U_P = $09AA; U_B = $09AC; U_BH = $09AD;
  U_M = $09AE; U_R = $09B0; U_L = $09B2; U_SH = $09B6; U_SS = $09B7;
  U_S = $09B8; U_T_KHANDATA = $09CE;
  U_AAKAR = $09BE; U_IKAR = $09BF; U_IIKAR = $09C0; U_UKAR = $09C1;
  U_UUKAR = $09C2; U_RIKAR = $09C3; U_EKAR = $09C7; U_OIKAR = $09C8;
  U_OKAR = $09CB; U_OUKAR = $09CC;
  U_ANUSVARA = $0982; U_VISARGA = $0983; U_CHANDRABINDU = $0981;
  U_DANDA = $0964; U_TAKA = $09F3;

type
  TCorpusCase = record
    Label_: string;
    Text: string;
  end;

var
  Fails: Integer;
  Checks: Integer;
  Quiet: Boolean;
  // Optional reference folder for the authoring JSON. It is assets\, the folder
  // the containers are packed from, so the reference is normally that same
  // folder - passed in explicitly all the same, because a run that names no
  // source at all would skip the byte-for-byte comparison silently, which is
  // the one way a source/container drift could hide from this gate.
  SourceDir: string;
  Corpus: TArray<TCorpusCase>;

{ ---- reporting ----------------------------------------------------------- }

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
  WriteLn('     ' + AText);
end;

function JoinArray(const AItems: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AItems) do
  begin
    if I > 0 then
      Result := Result + ', ';
    Result := Result + AItems[I];
  end;
end;

{ ---- rendering helpers --------------------------------------------------- }

function UniCodes(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + 'U+' + IntToHex(Ord(S[I]), 4);
  end;
end;

function HexBytes(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[I]), 2);
  end;
  if Result = '' then
    Result := '(empty)';
end;

function AnsiEscaped(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (Ord(C) >= 32) and (Ord(C) <= 126) then
      Result := Result + C
    else
      Result := Result + '#$' + IntToHex(Ord(C), 2);
  end;
  if Result = '' then
    Result := '(empty)';
end;

// Non-overlapping occurrence count of a glyph inside converted output.
function Occurrences(const AText, AGlyph: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  if AGlyph = '' then
    Exit;
  I := 1;
  while I <= Length(AText) - Length(AGlyph) + 1 do
    if Copy(AText, I, Length(AGlyph)) = AGlyph then
    begin
      Inc(Result);
      Inc(I, Length(AGlyph));
    end
    else
      Inc(I);
end;

// How many times any of the named vectors' glyphs appears in AText. Kar names
// come from the mapping itself, so this is a data check, not a hardcoded one.
function GlyphSum(const AText: string; const ANames: array of string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(ANames) do
    Result := Result + Occurrences(AText, ResolveValue('#{' + ANames[I] + '}'));
end;

// First of the named vectors' glyphs that actually occurs in AText.
function GlyphHit(const AText: string; const ANames: array of string): string;
var
  I: Integer;
  G: string;
begin
  Result := '';
  for I := 0 to High(ANames) do
  begin
    G := ResolveValue('#{' + ANames[I] + '}');
    if (G <> '') and (Pos(G, AText) > 0) then
      Exit(G);
  end;
end;

{ ---- loading ------------------------------------------------------------- }

function StripBom(const S: string): string;
begin
  Result := S;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

// Returns the mapping JSON for a file, decrypting containers in memory.
// Empty result means the file could not be read or decrypted.
function LoadMappingText(const APath: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(APath), '.AvroEnco') then
    Result := Trim(DecryptAvroEncoToString(APath, ''))
  else
    Result := Trim(StripBom(TFile.ReadAllText(APath, TEncoding.UTF8)));
end;

// Installs a mapping into the engine globals from a clean slate, so mappings
// cannot bleed state into each other (a mapping that omits a constant must not
// inherit the previous document's override). Returns False when the JSON is
// unusable; AParseLog carries whatever the parser logged.
function InstallMapping(const AJsonText: string; out AParseLog: string): Boolean;
var
  Log: TStringList;
  Root: TJSONValue;
begin
  Result := False;
  AParseLog := '';

  if AJsonText = '' then
    Exit;

  Root := TJSONObject.ParseJSONValue(AJsonText);
  if Root = nil then
    Exit;
  Root.Free;

  Log := TStringList.Create;
  try
    ResetAnsiToDefaults;
    LoadAnsiMappingFromJSON(AJsonText, Log);
    AParseLog := Trim(Log.Text);
  finally
    Log.Free;
  end;
  Result := True;
end;

function ConvertAll: TArray<string>;
var
  Conv: TUnicodeToBijoy2000;
  I: Integer;
begin
  SetLength(Result, Length(Corpus));
  Conv := TUnicodeToBijoy2000.Create;
  try
    for I := 0 to High(Corpus) do
      Result[I] := Conv.Convert(Corpus[I].Text);
  finally
    Conv.Free;
  end;
end;

{ ---- section census ------------------------------------------------------ }

// Counts every top-level section of a mapping document (array length or object
// member count), keyed by section name.
function SectionCounts(const AJsonText: string): TDictionary<string, Integer>;
var
  Root: TJSONValue;
  Obj: TJSONObject;
  Pair: TJSONPair;
  Val: TJSONValue;
begin
  Result := TDictionary<string, Integer>.Create;
  Root := TJSONObject.ParseJSONValue(AJsonText);
  if Root = nil then
    Exit;
  try
    if not (Root is TJSONObject) then
      Exit;
    Obj := TJSONObject(Root);
    for Pair in Obj do
    begin
      Val := Pair.JsonValue;
      if Val is TJSONArray then
        Result.AddOrSetValue(Pair.JsonString.Value, TJSONArray(Val).Count)
      else if Val is TJSONObject then
        Result.AddOrSetValue(Pair.JsonString.Value, TJSONObject(Val).Count);
    end;
  finally
    Root.Free;
  end;
end;

function CountOf(const ACounts: TDictionary<string, Integer>; const AName: string): Integer;
begin
  if not ACounts.TryGetValue(AName, Result) then
    Result := -1;
end;

function SortedNames(const ACounts: TDictionary<string, Integer>): TArray<string>;
var
  L: TList<string>;
  Name: string;
begin
  L := TList<string>.Create;
  try
    for Name in ACounts.Keys do
      L.Add(Name);
    L.Sort;
    Result := L.ToArray;
  finally
    L.Free;
  end;
end;

function CensusLine(const ATag: string; const ACounts: TDictionary<string, Integer>): string;
var
  Name: string;
begin
  Result := '';
  for Name in SortedNames(ACounts) do
  begin
    if Result <> '' then
      Result := Result + ' ';
    Result := Result + Name + '=' + IntToStr(CountOf(ACounts, Name));
  end;
  Result := ATag + ': ' + Result;
end;

// Every key present in the source object section must still be present in the
// engine's serialized section. A missing group name is the silent-drop failure
// mode (the parser ignores what it does not understand).
function MissingKeys(const ASourceText, AExportText, ASection: string;
  out AMissing: TArray<string>): Boolean;
var
  SrcRoot, ExpRoot: TJSONValue;
  SrcSection, ExpSection: TJSONObject;
  L: TList<string>;
  I, J: Integer;
  Found: Boolean;
begin
  AMissing := nil;
  Result := False;

  SrcRoot := TJSONObject.ParseJSONValue(ASourceText);
  ExpRoot := TJSONObject.ParseJSONValue(AExportText);
  try
    if (SrcRoot = nil) or (ExpRoot = nil) then
      Exit;
    if not (SrcRoot is TJSONObject) or not (ExpRoot is TJSONObject) then
      Exit;
    if not (TJSONObject(SrcRoot).GetValue(ASection) is TJSONObject) then
      Exit;
    SrcSection := TJSONObject(TJSONObject(SrcRoot).GetValue(ASection));

    if not (TJSONObject(ExpRoot).GetValue(ASection) is TJSONObject) then
    begin
      SetLength(AMissing, SrcSection.Count);
      for I := 0 to SrcSection.Count - 1 do
        AMissing[I] := SrcSection.Pairs[I].JsonString.Value;
      Exit(True);
    end;
    ExpSection := TJSONObject(TJSONObject(ExpRoot).GetValue(ASection));

    L := TList<string>.Create;
    try
      for I := 0 to SrcSection.Count - 1 do
      begin
        Found := False;
        for J := 0 to ExpSection.Count - 1 do
          if ExpSection.Pairs[J].JsonString.Value = SrcSection.Pairs[I].JsonString.Value then
          begin
            Found := True;
            Break;
          end;
        if not Found then
          L.Add(SrcSection.Pairs[I].JsonString.Value);
      end;
      AMissing := L.ToArray;
      Result := Length(AMissing) > 0;
    finally
      L.Free;
    end;
  finally
    SrcRoot.Free;
    ExpRoot.Free;
  end;
end;

{ ---- per-mapping analysis ------------------------------------------------ }

// Outputs per mapping, keyed by tag, for the cross-mapping comparison.
var
  Outputs: TDictionary<string, TArray<string>>;

// Returns the converted output of one corpus case, addressed by its label.
function CaseOut(const AOut: TArray<string>; const ALabel: string; out AText: string): Boolean;
var
  I: Integer;
begin
  AText := '';
  Result := False;
  for I := 0 to High(Corpus) do
    if (Corpus[I].Label_ = ALabel) and (I <= High(AOut)) then
    begin
      AText := AOut[I];
      Exit(True);
    end;
end;

// One kar of a consonant+kar pair is emitted exactly once, before the
// consonant for the pre-base kars (ে / ি / ৈ) and after it for the rest. Two
// glyphs for one kar - or a kar name pointed at a glyph another kar already
// uses - shows up as a doubled or misplaced mark, which is what "the kars do
// not work" looks like on screen. ো/ৌ are judged the same way because the
// engine splits them into ে + া / ে + ৗ and substitutes the e-kar itself.
procedure CheckKarOnce(const ATag, ALabel, AWhat: string; const AOut: TArray<string>;
  const ANames: array of string; APreBase: Boolean);
var
  S, Hit, Cons: string;
  N, HitPos, ConsPos: Integer;
begin
  if not CaseOut(AOut, ALabel, S) then
    Exit;

  N := GlyphSum(S, ANames);
  Check(Format('%s: %s emits one %s glyph', [ATag, ALabel, AWhat]), N = 1,
    Format('found %d in %s', [N, AnsiEscaped(S)]));

  Hit := GlyphHit(S, ANames);
  Cons := ResolveValue('#{A_K}');
  HitPos := Pos(Hit, S);
  ConsPos := Pos(Cons, S);
  if (HitPos = 0) or (ConsPos = 0) then
    Exit;
  if APreBase then
    Check(Format('%s: %s places the %s before the consonant', [ATag, ALabel, AWhat]), HitPos < ConsPos,
      Format('kar at %d, consonant at %d in %s', [HitPos, ConsPos, AnsiEscaped(S)]))
  else
    Check(Format('%s: %s places the %s with the consonant', [ATag, ALabel, AWhat]), HitPos >= ConsPos,
      Format('kar at %d, consonant at %d in %s', [HitPos, ConsPos, AnsiEscaped(S)]));
end;

procedure CheckKarRendering(const ATag: string; const AOut: TArray<string>);
begin
  // Pre-base kars: hoisted in front of the cluster.
  CheckKarOnce(ATag, 'e-kar', 'e-kar', AOut, ['A_EKar1', 'A_EKar2'], True);
  CheckKarOnce(ATag, 'i-kar', 'i-kar', AOut, ['A_IKar'], True);
  CheckKarOnce(ATag, 'oi-kar', 'oi-kar', AOut, ['A_OIKar1', 'A_OIKar2'], True);

  // Post-base kars: emitted with the letters they hang off.
  CheckKarOnce(ATag, 'a-kar', 'a-kar', AOut, ['A_AAKar'], False);
  CheckKarOnce(ATag, 'ii-kar', 'ii-kar', AOut, ['A_IIKar'], False);
  CheckKarOnce(ATag, 'u-kar', 'u-kar', AOut, ['A_UKar1', 'A_UKar2', 'A_UKar3', 'A_UKar4'], False);
  CheckKarOnce(ATag, 'uu-kar', 'uu-kar', AOut, ['A_UUKar1', 'A_UUKar2', 'A_UUKar3'], False);
  CheckKarOnce(ATag, 'ri-kar', 'ri-kar', AOut, ['A_RRIKar1', 'A_RRIKar2'], False);

  // Composed kars. The e-kar of ো/ৌ is supplied by the engine, so a mapping
  // must not fold a second copy into the aa-kar / length-mark glyph.
  CheckKarOnce(ATag, 'o-kar', 'o-kar e-kar', AOut, ['A_EKar1', 'A_EKar2'], True);
  CheckKarOnce(ATag, 'o-kar', 'o-kar aa-kar', AOut, ['A_AAKar'], False);
  CheckKarOnce(ATag, 'ou-kar', 'ou-kar e-kar', AOut, ['A_EKar1', 'A_EKar2'], True);
  CheckKarOnce(ATag, 'ou-kar', 'ou-kar length-mark', AOut, ['A_OUKar'], False);
end;

{ ---- metadata card ------------------------------------------------------- }

{ The value on the card's "<Key>: " line, or '' when the card has no such
  line. The card is one "<Key>: <Value>" line per metadata field. }
function CardValue(const ACard, AKey: string): string;
var
  Lines: TStringList;
  I: Integer;
begin
  Result := '';
  Lines := TStringList.Create;
  try
    Lines.Text := ACard;
    for I := 0 to Lines.Count - 1 do
      if Pos(AKey + ': ', Lines[I]) = 1 then
        Exit(Copy(Lines[I], Length(AKey) + 3, MaxInt));
  finally
    Lines.Free;
  end;
end;

{ The profile name the document itself declares: the same Encoding/Name lookup
  the card performs, so the two can be compared. '' when it declares none. }
function DeclaredEncoding(const AJSON: string): string;
var
  Root, Meta: TJSONValue;
begin
  Result := '';
  Root := TJSONObject.ParseJSONValue(Trim(StripBom(AJSON)));
  if not Assigned(Root) then
    Exit;
  try
    Meta := nil;
    if Root is TJSONObject then
      Meta := TJSONObject(Root).Values['Metadata'];
    if Assigned(Meta) and (Meta is TJSONObject) then
    begin
      Result := GetJSONString(Meta, 'Encoding');
      if Result = '' then
        Result := GetJSONString(Meta, 'Name');
    end;
  finally
    Root.Free;
  end;
end;

procedure AnalyseOneMapping(const APath, ATag: string; const AOut: TArray<string>);
var
  SourceText, ExportText, ParseLog, TmpFile: string;
  SrcCounts, ExpCounts: TDictionary<string, Integer>;
  Name, Card, DeclaredEnc: string;
  CardLines: TStringList;
  SrcN, ExpN, I: Integer;
  Shrunk, Dropped: TList<string>;
  Missing: TArray<string>;
begin
  SourceText := LoadMappingText(APath);
  Check(ATag + ': mapping text loads', SourceText <> '',
    'could not read or decrypt ' + ExtractFileName(APath));
  if SourceText = '' then
    Exit;

  Check(ATag + ': mapping parses', InstallMapping(SourceText, ParseLog),
    'parser rejected the document');
  if ParseLog <> '' then
    Note(ATag + ': parser log: ' + StringReplace(ParseLog, sLineBreak, ' | ', [rfReplaceAll]));

  // Serialize the loaded engine back to JSON and compare with the source.
  TmpFile := TPath.Combine(TPath.GetTempPath, 'kat_ansiconvert_' +
    IntToStr(GetCurrentProcessId) + '.json');
  ExportAnsiMapping(TmpFile);
  ExportText := TFile.ReadAllText(TmpFile, TEncoding.UTF8);
  TFile.Delete(TmpFile);

  SrcCounts := SectionCounts(SourceText);
  ExpCounts := SectionCounts(ExportText);
  try
    Note(CensusLine(ATag + ': source sections', SrcCounts));
    Note(CensusLine(ATag + ': engine sections', ExpCounts));

    Shrunk := TList<string>.Create;
    Dropped := TList<string>.Create;
    try
      for Name in SortedNames(SrcCounts) do
      begin
        // Metadata is documentation, not engine state: the exporter does not
        // serialize it and its absence is not a dropped section.
        if SameText(Name, 'Metadata') then
          Continue;
        SrcN := CountOf(SrcCounts, Name);
        ExpN := CountOf(ExpCounts, Name);
        if SrcN <= 0 then
          Continue;
        if ExpN < 0 then
          Dropped.Add(Name)
        else if ExpN < SrcN then
          Shrunk.Add(Name + ' (' + IntToStr(SrcN) + '->' + IntToStr(ExpN) + ')');
      end;

      Check(ATag + ': parser keeps every declared section', Dropped.Count = 0,
        'sections dropped by the parser: ' + JoinArray(Dropped.ToArray));
      Check(ATag + ': parser keeps every declared entry', Shrunk.Count = 0,
        'sections that lost entries: ' + JoinArray(Shrunk.ToArray));
    finally
      Shrunk.Free;
      Dropped.Free;
    end;

    // Group names are data here, so they must survive verbatim.
    for Name in ['RaPhalaGroups', 'ConsonantGroups'] do
      if MissingKeys(SourceText, ExportText, Name, Missing) then
        Check(ATag + ': group names survive parsing (' + Name + ')', False,
          'missing: ' + JoinArray(Missing))
      else
        Check(ATag + ': group names survive parsing (' + Name + ')', True);
  finally
    SrcCounts.Free;
    ExpCounts.Free;
  end;

  // The metadata card is what a user sees when they inspect a mapping. Its font
  // lines are the explanation for "the letters come out wrong": the engine
  // emits the mapping's own byte values, and only the mapping's suggested font
  // renders them as the intended Bangla.
  Card := ExtractMetadataFromJSON(SourceText, APath);
  CardLines := TStringList.Create;
  try
    CardLines.Text := Card;
    for I := 0 to CardLines.Count - 1 do
      if (Pos('Suggested Font', CardLines[I]) > 0) or
         (Pos('was not found', CardLines[I]) > 0) or
         (Pos('Name: ', CardLines[I]) = 1) or
         (Pos('Encoding: ', CardLines[I]) = 1) then
        Note(ATag + ': card: ' + Trim(CardLines[I]));
  finally
    CardLines.Free;
  end;

  // The card's two identifying lines are a contract with the user:
  //   Name     - the file as it appears in Explorer and in the picker,
  //   Encoding - the profile the DOCUMENT declares.
  // Encoding is never a second copy of the file name: a path-derived value
  // made the card contradict the document, and for a container named after a
  // font (STM-BNT-Arjun.AvroEnco) it reported the font as the encoding. The
  // comparison is deliberately case-sensitive - the shipped containers are
  // named "Ansi V2" while declaring "ANSI V2", so SameText would pass against
  // the path-derived value this gate exists to catch.
  DeclaredEnc := DeclaredEncoding(SourceText);
  Check(ATag + ': card Encoding reports the declared profile',
    (DeclaredEnc <> '') and (CardValue(Card, 'Encoding') = DeclaredEnc),
    'card: "' + CardValue(Card, 'Encoding') + '" declared: "' + DeclaredEnc + '"');
  Check(ATag + ': card Name reports the file',
    CardValue(Card, 'Name') = ExtractFileName(APath),
    'card: "' + CardValue(Card, 'Name') + '" file: "' +
    ExtractFileName(APath) + '"');

  Check(ATag + ': conversion produced output', Length(AOut) = Length(Corpus),
    'the corpus did not convert');
  if Length(AOut) = Length(Corpus) then
    Outputs.AddOrSetValue(ATag, AOut);

  // No conversion may leak an unresolved reference or plain placeholder text.
  for I := 0 to High(AOut) do
    Check(ATag + ': no unresolved reference in output [' + Corpus[I].Label_ + ']',
      Pos('#{', AOut[I]) = 0, 'output: ' + AnsiEscaped(AOut[I]));

  CheckKarRendering(ATag, AOut);

  if not Quiet and (Length(AOut) = Length(Corpus)) then
  begin
    Note(ATag + ': corpus (' + IntToStr(Length(AOut)) + ' cases)');
    for I := 0 to High(AOut) do
      Note(Format('  %-20s %-36s -> %-26s %s',
        [Corpus[I].Label_, UniCodes(Corpus[I].Text),
         HexBytes(AOut[I]), AnsiEscaped(AOut[I])]));
  end;
end;

{ ---- corpus -------------------------------------------------------------- }

procedure BuildCorpus;
  procedure Add(const ALabel, AText: string);
  begin
    SetLength(Corpus, Length(Corpus) + 1);
    Corpus[High(Corpus)].Label_ := ALabel;
    Corpus[High(Corpus)].Text := AText;
  end;
begin
  Add('single consonant',   Chr(U_K));
  Add('a-kar',              Chr(U_K) + Chr(U_AAKAR));
  Add('i-kar',              Chr(U_K) + Chr(U_IKAR));
  Add('ii-kar',             Chr(U_K) + Chr(U_IIKAR));
  Add('u-kar',              Chr(U_K) + Chr(U_UKAR));
  Add('uu-kar',             Chr(U_K) + Chr(U_UUKAR));
  Add('ri-kar',             Chr(U_K) + Chr(U_RIKAR));
  Add('e-kar',              Chr(U_K) + Chr(U_EKAR));
  Add('oi-kar',             Chr(U_K) + Chr(U_OIKAR));
  Add('o-kar',              Chr(U_K) + Chr(U_OKAR));
  Add('ou-kar',             Chr(U_K) + Chr(U_OUKAR));
  Add('k-k conjunct',       Chr(U_K) + Chr(U_HASANTA) + Chr(U_K));
  Add('k-t conjunct',       Chr(U_K) + Chr(U_HASANTA) + Chr(U_T));
  Add('k-ss conjunct',      Chr(U_K) + Chr(U_HASANTA) + Chr(U_SS));
  Add('k-sh conjunct',      Chr(U_K) + Chr(U_HASANTA) + Chr(U_SH));
  Add('kr (ra-phala)',      Chr(U_K) + Chr(U_HASANTA) + Chr(U_R));
  Add('pr (ra-phala)',      Chr(U_P) + Chr(U_HASANTA) + Chr(U_R));
  Add('bhr (ra-phala)',     Chr(U_BH) + Chr(U_HASANTA) + Chr(U_R));
  Add('tr (ra-phala)',      Chr(U_T) + Chr(U_HASANTA) + Chr(U_R));
  Add('gr (ra-phala)',      Chr(U_G) + Chr(U_HASANTA) + Chr(U_R));
  Add('shr (ra-phala)',     Chr(U_SH) + Chr(U_HASANTA) + Chr(U_R));
  Add('mr (ra-phala)',      Chr(U_M) + Chr(U_HASANTA) + Chr(U_R));
  Add('jr (ra-phala)',      Chr(U_J) + Chr(U_HASANTA) + Chr(U_R));
  Add('j-nya conjunct',     Chr(U_J) + Chr(U_HASANTA) + Chr(U_NYA));
  Add('n-ch conjunct',      Chr(U_N) + Chr(U_HASANTA) + Chr(U_C));
  Add('r-k (reph)',         Chr(U_R) + Chr(U_HASANTA) + Chr(U_K));
  Add('r-ki (reph+kar)',    Chr(U_R) + Chr(U_HASANTA) + Chr(U_K) + Chr(U_IKAR));
  Add('anushvara',          Chr(U_K) + Chr(U_ANUSVARA));
  Add('visarga',            Chr(U_K) + Chr(U_VISARGA));
  Add('chandrabindu',       Chr(U_K) + Chr(U_CHANDRABINDU));
  Add('khanda-ta',          Chr(U_K) + Chr(U_HASANTA) + Chr(U_T_KHANDATA));
  Add('k-ss-m (full form)', Chr(U_K) + Chr(U_HASANTA) + Chr(U_SS) + Chr(U_HASANTA) + Chr(U_M));
  Add('digits',             Chr($09E6) + Chr($09E7) + Chr($09E8) + Chr($09E9) + Chr($09EA));
  Add('danda-taka',         Chr(U_K) + Chr(U_DANDA) + Chr(U_TAKA));
  Add('aa (independent)',   Chr(U_AA));
  Add('word bangla',        Chr(U_B) + Chr(U_AAKAR) + Chr(U_N) + Chr(U_HASANTA) +
                            Chr(U_L) + Chr(U_AAKAR));
  Add('word sonar',         Chr(U_S) + Chr(U_OKAR) + Chr(U_N) + Chr(U_AAKAR) + Chr(U_R));
  Add('ascii passthrough',  'abZ 123 !?');
end;

{ ---- container vs JSON --------------------------------------------------- }

// Empty result means the two output sets are identical. Never returns a
// placeholder message: callers treat '' as "equal".
function FirstDifference(const A, B: TArray<string>): string;
var
  I, N: Integer;
begin
  N := Length(A);
  if Length(B) < N then
    N := Length(B);
  for I := 0 to N - 1 do
    if A[I] <> B[I] then
      Exit(Corpus[I].Label_ + ': first="' + AnsiEscaped(A[I]) +
        '" second="' + AnsiEscaped(B[I]) + '"');
  if Length(A) <> Length(B) then
    Exit('lengths differ (' + IntToStr(Length(A)) + ' vs ' + IntToStr(Length(B)) + ')');
  Result := '';
end;

// How many corpus cases two mappings convert to byte-identical output. A
// mapping that declares few rules leans on the engine's hardcoded defaults and
// therefore converges on whichever mapping those defaults were tuned for.
function SameCaseCount(const A, B: TArray<string>): Integer; forward;

// Side-by-side corpus output per mapping. A mapping that declares few rules
// emits the engine's hardcoded default bytes for the clusters it does not
// cover, which shows up here as agreement with the mapping those defaults were
// tuned for - so a supposedly wrong glyph can be traced to "this mapping does
// not declare it" instead of "the file is broken".
procedure ReportCorpusTable;
var
  Tags: TArray<string>;
  Sorted: TList<string>;
  Name, Line: string;
  I, J: Integer;
  AgreesWithFirst: Boolean;
begin
  Sorted := TList<string>.Create;
  try
    for Name in Outputs.Keys do
      Sorted.Add(Name);
    Sorted.Sort;
    Tags := Sorted.ToArray;
  finally
    Sorted.Free;
  end;
  if Length(Tags) = 0 then
    Exit;

  WriteLn('--- corpus output per mapping (first column = case, then one column per mapping)');
  for I := 0 to High(Corpus) do
  begin
    Line := Format('  %-20s', [Corpus[I].Label_]);
    for J := 0 to High(Tags) do
    begin
      if I <= High(Outputs[Tags[J]]) then
        Line := Line + Format(' %-14s', [AnsiEscaped(Outputs[Tags[J]][I])]);
    end;
    AgreesWithFirst := (Length(Tags) > 1) and
      (I <= High(Outputs[Tags[0]])) and (I <= High(Outputs[Tags[High(Tags)]])) and
      (Outputs[Tags[0]][I] = Outputs[Tags[High(Tags)]][I]);
    if AgreesWithFirst then
      Line := Line + '  <= same as ' + Tags[0];
    WriteLn(Line);
  end;
end;

// Prints how much of the corpus each pair of mappings converts identically.
// A mapping whose rules are largely absent converges on the engine's built-in
// defaults, which shows up here as a high agreement with the mapping those
// defaults were tuned for.
procedure ReportCrossMapping;
var
  Tags: TArray<string>;
  Sorted: TList<string>;
  Name: string;
  I, J: Integer;
begin
  Sorted := TList<string>.Create;
  try
    for Name in Outputs.Keys do
      Sorted.Add(Name);
    Sorted.Sort;
    Tags := Sorted.ToArray;
  finally
    Sorted.Free;
  end;

  if Length(Tags) < 2 then
    Exit;
  WriteLn('--- cross-mapping agreement (identical corpus cases out of ' +
    IntToStr(Length(Corpus)) + ')');
  for I := 0 to High(Tags) do
    for J := I + 1 to High(Tags) do
      WriteLn(Format('       %-14s vs %-14s %d/%d',
        [Tags[I], Tags[J], SameCaseCount(Outputs[Tags[I]], Outputs[Tags[J]]),
         Length(Corpus)]));
end;

function SameCaseCount(const A, B: TArray<string>): Integer;
var
  I, N: Integer;
begin
  Result := 0;
  N := Length(A);
  if Length(B) < N then
    N := Length(B);
  for I := 0 to N - 1 do
    if A[I] = B[I] then
      Inc(Result);
end;

procedure RunFolder(const ADir: string);
var
  Conts: TArray<string>;
  FileName, Base, JsonPath, Tag, ParseLog: string;
  ContOut, JsonOut: TArray<string>;
begin
  if not TDirectory.Exists(ADir) then
  begin
    Check('mapping dir exists: ' + ADir, False, 'directory not found');
    Exit;
  end;

  Conts := TDirectory.GetFiles(ADir, '*.AvroEnco');
  Check('mapping dir has .AvroEnco files: ' + ADir, Length(Conts) > 0,
    'no .AvroEnco found');

  for FileName in Conts do
  begin
    Base := ChangeFileExt(ExtractFileName(FileName), '');
    Tag := Base;
    // The authored source is the authority. A same-named mirror sitting next
    // to the container is only a fallback when no source folder was passed:
    // a stale mirror is precisely how a drift between the authored JSON and
    // the shipped container stayed invisible before (the ou-kar value in the
    // V4 mirror was wrong for a whole release while the gate compared the
    // container against that mirror).
    JsonPath := '';
    if SourceDir <> '' then
      JsonPath := TPath.Combine(SourceDir, Base + '.json');
    if (JsonPath = '') or (not TFile.Exists(JsonPath)) then
      JsonPath := TPath.Combine(ADir, Base + '.json');

    // Convert through the container.
    if InstallMapping(LoadMappingText(FileName), ParseLog) then
      ContOut := ConvertAll
    else
      ContOut := nil;

    AnalyseOneMapping(FileName, Tag, ContOut);

    // The very same mapping shipped as plain JSON must convert identically.
    if TFile.Exists(JsonPath) then
    begin
      if InstallMapping(LoadMappingText(JsonPath), ParseLog) then
      begin
        JsonOut := ConvertAll;
        Check(Tag + ': container output matches the plain .json output',
          (Length(ContOut) = Length(JsonOut)) and (FirstDifference(ContOut, JsonOut) = ''),
          FirstDifference(ContOut, JsonOut));
      end
      else
        Check(Tag + ': sibling .json parses', False, JsonPath);
    end;
  end;
end;

var
  DirArg: string;
  I: Integer;

begin
  Fails := 0;
  Checks := 0;
  Quiet := False;
  DirArg := '';
  SourceDir := '';

  for I := 1 to ParamCount do
    if SameText(ParamStr(I), 'quiet') then
      Quiet := True
    else if DirArg = '' then
      DirArg := ParamStr(I)
    else if SourceDir = '' then
      SourceDir := ParamStr(I);

  BuildCorpus;
  Outputs := TDictionary<string, TArray<string>>.Create;

  if DirArg = '' then
  begin
    WriteLn('usage: kat_ansiconvert <mapping-dir> [source-json-dir] [quiet]');
    ExitCode := 2;
    Exit;
  end;

  RunFolder(DirArg);
  if not Quiet then
  begin
    ReportCorpusTable;
    ReportCrossMapping;
  end;

  if Fails = 0 then
    WriteLn(Format('ALL PASS (%d checks)', [Checks]))
  else
    WriteLn(Format('%d of %d checks FAILED', [Fails, Checks]));

  ExitCode := Ord(Fails > 0);
end.
