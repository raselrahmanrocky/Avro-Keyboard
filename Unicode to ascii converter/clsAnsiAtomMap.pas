{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsAnsiAtomMap;

{
  clsAnsiAtomMap - "one press = one visible character" for the text the
  committed ledger does NOT own.

  The engines answer for what they typed themselves: the screen behind the
  caret IS Convert(CommittedBanglaT), so clsAnsiGrapheme can segment that
  Unicode text and the mapping's own Convert decides the ANSI width. That
  answer is gone the moment the caret moves somewhere the ledger does not
  describe - a mouse click, an arrow key, another application editing the
  document, text that predates Avro. Then the only truth is what actually sits
  in front of the caret, and the width has to be derived from the ACTIVE
  mapping's own glyphs.

  This unit turns a mapping into an ATOM table. An atom is one glyph the mapping
  can emit (one or more ANSI units: Ansi V3 K = 201E FE, I = A3 7A, the full
  form ka+hasanta+ka = 45 FE), and every atom carries

  * a ROLE - what it is inside a cluster, and
  * a BIND  - which way it merges with its neighbour,

  so a run of atoms segments into clusters by the same UAX#29-analogue rules
  clsAnsiGrapheme applies on the Unicode side. Nothing is hardcoded per version:
  the table is compiled from whatever mapping is active, so a mapping added
  later behaves exactly like the four shipped today.

  ROLE DERIVATION ORDER (getting this wrong is the classic failure):
  1. When the atom has a Unicode source, UNICODE decides - the grapheme-break
     class of its first code point: linker -> arJoiner, Mn / Mc / ZWJ / ZWNJ ->
     arMark, Bengali consonant -> arBase, digit -> arDigit, an independent vowel
     or a Bengali symbol -> arBase.
  2. Only without a Unicode source the mapping's own group and name are used:
     FirstHalfForms -> arHalfForm, SecondHalfForms -> arSecondHalf,
     "hasanta" in the name -> arJoiner, Numbers -> arDigit, Symbols -> arPunct,
     otherwise arUnknown (which still counts as exactly one unit).
  Either way an unrecognised glyph occupies ONE unit, so it can never make a
  press erase more than one character.

  Two real traps this order avoids:
  * The mapping's own group name lies. In all four shipped mappings the anusvara
    and visarga sit in the Consonants group while Unicode calls them Mc
    (SpacingMark): they bind BACKWARDS, which is what makes "bangla" cost two
    presses instead of three.
  * "Kar" in a name is not always a kar. A constant named A_SH_UKar is the whole
    syllable "shu" (arBase); calling it a kar would glue two visible characters
    together and destroy text on one press.

  AMBIGUITY: the same unit string can appear with two roles (verified in Ansi
  V3: D6 is both a ra-phala second half and the syllable "shu"). The tie-break
  keeps the reading that STARTS a new cluster: the worst case is one extra
  press, while the opposite choice erases two glyphs at once. Every conflict is
  recorded, so tests and logs can see exactly which mapping needed the rule.
}

interface

uses
  System.Generics.Collections;

type
  { What an atom is inside a cluster. }
  TAnsiRole = (arBase, arMark, arJoiner, arHalfForm, arSecondHalf, arDigit, arPunct, arUnknown);

  { How an atom merges with its neighbour:
    abSelf - starts and ends its own cluster,
    abBack - binds to what precedes it (a kar, an anusvara, a second half),
    abFwd  - binds to what follows it (a reph / first half, a hasanta). }
  TAnsiBind = (abSelf, abBack, abFwd);

  { The longest atom the table keeps, and the default cap on how many units one
    press may erase. Both are deliberately small: the longest glyph in the
    shipped mappings is three units (Ansi V3 U = 76 FE 7A), and no mapping needs
    a longer run than this to describe one visible character. }
const
  MAX_ATOM_UNITS = 8;

type
  TAnsiAtom = record
    Units: string; // the ANSI units this glyph occupies, exactly as the mapping emits them
    Role:  TAnsiRole;
    Bind:  TAnsiBind;
    Src:   string; // where the atom came from, e.g. 'Constant.Consonants' - for conflict logs
    Name:  string; // the mapping's own name for it
    Uni:   string; // the Unicode source the mapping gives it ('' = none), for tests and logs
  end;

  { The atom table of ONE mapping. Add every glyph the mapping can emit (Add
    derives role and bind), call Index, then ask how wide the last cluster is.

    Ownership: like the mapping's other containers this object is moved between
    a parked engine slot and the unit globals by pointer assignment, never
    copied. }
  TAnsiAtomMap = class
  private
    FByUnits:   TDictionary<string, TAnsiAtom>;
    FAtoms:     TArray<TAnsiAtom>;
    FConflicts: TArray<string>;
    procedure LogConflict(const AKept, ADropped: TAnsiAtom);
  public
    constructor Create;
    destructor Destroy; override;

    { Adds one glyph. AUnicodeSide is the mapping's Unicode source for it (a
      constant's key, a replacement pair's key, ...) or '' when the mapping
      gives none - see the derivation order in the unit header. ACategory is the
      mapping's own group ('Consonants', 'FirstHalfForms', ...), used only as
      the fallback. AUnits is ignored when empty or longer than MAX_ATOM_UNITS. }
    procedure Add(const AUnits, AUnicodeSide, ACategory, AName, ASrc: string);

    { Finishes the table. A later Add is still visible without a re-index (the
      lookup is a dictionary), so an index can never hide the atom a rewrite
      just added. }
    procedure Index;

    { The glyph whose LAST unit is AText[AEnd]. False when no atom ends there:
      unknown text, whose unit counts as one character. }
    function MatchEndingAt(const AText: string; const AEnd: Integer; out AAtom: TAnsiAtom): Boolean;

    { How many ANSI units at the tail of AText form the last visible cluster.
      0 for empty text. Never more than AMaxUnits, never more than the text
      itself, and 1 for anything the table does not recognise: under-deleting
      costs one keypress, over-deleting costs text. }
    function TailClusterUnits(const AText: string; const AMaxUnits: Integer = MAX_ATOM_UNITS): Integer;

    function Count: Integer;
    property Atoms: TArray<TAnsiAtom> read FAtoms;
    property Conflicts: TArray<string> read FConflicts;
  end;

{ The role of an atom whose Unicode source is known. '' means arUnknown. }
function UnicodeAtomRole(const AUnicodeSide: string): TAnsiRole;

{ The role of an atom the mapping describes only by group and name. }
function NameFallbackRole(const ACategory, AName: string): TAnsiRole;

{ The binding a role implies. A hasanta binds both ways: arJoiner is what
  ClusterBoundary uses to keep the following consonant attached, and a joiner
  itself never starts a cluster. }
function BindOfRole(const ARole: TAnsiRole): TAnsiBind;

{ True when a role and a bind are a legal pair. BindOfRole gives the default,
  and a PRE-BASE vowel sign is the one legal exception: Unicode calls it a mark
  while the mapping writes it in front of its consonant, so it binds forward. }
function IsLegalRoleBind(const ARole: TAnsiRole; const ABind: TAnsiBind): Boolean;

{ May a cluster boundary sit between ALeft and ARight? False = one cluster. }
function ClusterBoundary(const ALeft, ARight: TAnsiAtom): Boolean;

{ The first Bengali code point of a mapping text field. The A_* constants store
  "a (aa-kar)" style descriptions rather than plain keys, so the first code
  point in the Bengali block (or a joiner) is the Unicode source; #0 means the
  field carries none. }
function FirstBengaliCodePoint(const S: string): Char;

{ The mapping's description fields carry prose beside the key ("ra (reph)", a
  trailing word with no separator, ...). Only the LEADING run of Bengali / joiner
  code points is the Unicode source of the glyph; prose is dropped, so it can
  never take part in a role decision, a report or a test expectation. }
function TrimToUnicodeSource(const S: string): string;

function RoleName(const ARole: TAnsiRole): string;
function BindName(const ABind: TAnsiBind): string;

{ The code points of S as hex, so logs and test output stay readable for
  ANSI units above U+00FF. }
function HexUnits(const S: string): string;

implementation

uses
  System.SysUtils,
  BanglaChars,
  clsAnsiGrapheme;

const
  BENGALI_FIRST = $0980;
  BENGALI_LAST  = $09FF;

function FirstBengaliCodePoint(const S: string): Char;
var
  I, P: Integer;
begin
  Result := #0;
  for I := 1 to Length(S) do
  begin
    P := Ord(S[I]);
    if ((P >= BENGALI_FIRST) and (P <= BENGALI_LAST)) or (S[I] = ZWJ) or (S[I] = ZWNJ) then
    begin
      Result := S[I];
      Exit;
    end;
  end;
end;

function TrimToUnicodeSource(const S: string): string;
var
  I, P: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    P := Ord(S[I]);
    if ((P >= BENGALI_FIRST) and (P <= BENGALI_LAST)) or (S[I] = ZWJ) or (S[I] = ZWNJ) then
      Result := Result + S[I]
    else
      Break;
  end;
end;

function UnicodeAtomRole(const AUnicodeSide: string): TAnsiRole;
var
  C: Char;
begin
  C := FirstBengaliCodePoint(AUnicodeSide);
  if C = #0 then
  begin
    Result := arUnknown;
    Exit;
  end;

  // Unicode decides, from the FIRST code point, so a syllable whose name says
  // "kar" and an anusvara filed under consonants both come out right.
  if IsLinkerPoint(C) then
    Result := arJoiner
  else if IsMarkPoint(C) or IsSpacingMarkPoint(C) then
    Result := arMark
  else if IsConsonantPoint(C) then
    Result := arBase
  else if IsDigitPoint(C) then
    Result := arDigit
  else
    Result := arBase;
end;

function NameFallbackRole(const ACategory, AName: string): TAnsiRole;
var
  Cat, Nm: string;
begin
  Cat := UpperCase(Trim(ACategory));
  Nm := LowerCase(Trim(AName));

  if Cat = 'FIRSTHALFFORMS' then
    Result := arHalfForm
  else if Cat = 'SECONDHALFFORMS' then
    Result := arSecondHalf
  else if Cat = 'NUMBERS' then
    Result := arDigit
  else if Cat = 'SYMBOLS' then
    Result := arPunct
  else if Pos('hasanta', Nm) > 0 then
    Result := arJoiner
  else
    // Consonants, vowels-and-kars, full forms: a visible character of its own.
    // Without a Unicode source nothing here may claim to bind backwards, so the
    // safe reading (a new cluster) is the answer.
    Result := arUnknown;
end;

function BindOfRole(const ARole: TAnsiRole): TAnsiBind;
begin
  case ARole of
    arMark, arSecondHalf: Result := abBack;
    arHalfForm, arJoiner: Result := abFwd;
  else
    Result := abSelf;
  end;
end;

function IsLegalRoleBind(const ARole: TAnsiRole; const ABind: TAnsiBind): Boolean;
begin
  Result := (ABind = BindOfRole(ARole)) or ((ARole = arMark) and (ABind = abFwd));
end;

function ClusterBoundary(const ALeft, ARight: TAnsiAtom): Boolean;
begin
  // GB9 / GB9a: a mark, a joiner or a second half never starts a cluster.
  if (ARight.Role = arJoiner) or (ARight.Bind = abBack) then
  begin
    Result := False;
    Exit;
  end;

  // GB9c: a hasanta links the consonant that follows it.
  if ALeft.Role = arJoiner then
  begin
    Result := not((ARight.Role = arBase) or (ARight.Role = arHalfForm) or (ARight.Role = arSecondHalf) or (ARight.Role = arJoiner));
    Exit;
  end;


  // GB9c from the other side: a reph / first half / PRE-BASE sign binds
  // FORWARD - but only to the consonant it is written against. A half form in
  // front of a space or a digit is still its own character.
  if (ALeft.Bind = abFwd) and ((ARight.Role = arBase) or (ARight.Role = arHalfForm) or (ARight.Role = arSecondHalf) or
    (ARight.Role = arJoiner)) then
  begin
    Result := False;
    Exit;
  end;

  Result := True;
end;

function RoleName(const ARole: TAnsiRole): string;
begin
  case ARole of
    arBase:       Result := 'base';
    arMark:       Result := 'mark';
    arJoiner:     Result := 'joiner';
    arHalfForm:   Result := 'halfForm';
    arSecondHalf: Result := 'secondHalf';
    arDigit:      Result := 'digit';
    arPunct:      Result := 'punct';
  else
    Result := 'unknown';
  end;
end;

function HexUnits(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[I]), 4);
  end;
end;

function BindName(const ABind: TAnsiBind): string;
begin
  case ABind of
    abBack: Result := 'back';
    abFwd:  Result := 'fwd';
  else
    Result := 'self';
  end;
end;

{ ============================================================================== }

constructor TAnsiAtomMap.Create;
begin
  inherited;
  FByUnits := TDictionary<string, TAnsiAtom>.Create;
  FAtoms := nil;
  FConflicts := nil;
end;

destructor TAnsiAtomMap.Destroy;
begin
  FreeAndNil(FByUnits);
  inherited;
end;

procedure TAnsiAtomMap.LogConflict(const AKept, ADropped: TAnsiAtom);
begin
  SetLength(FConflicts, Length(FConflicts) + 1);
  FConflicts[high(FConflicts)] := Format('[%s] for [%s]: kept %s/%s (from %s) over %s/%s (from %s)', [HexUnits(AKept.Units), HexUnits(AKept.Uni),
    RoleName(AKept.Role), BindName(AKept.Bind), AKept.Src, RoleName(ADropped.Role), BindName(ADropped.Bind), ADropped.Src]);
end;

procedure TAnsiAtomMap.Add(const AUnits, AUnicodeSide, ACategory, AName, ASrc: string);
var
  NewAtom, Old: TAnsiAtom;
  NewRole: TAnsiRole;
  Cat:     string;
begin
  if (AUnits = '') or (Length(AUnits) > MAX_ATOM_UNITS) then
    Exit;

  NewRole := UnicodeAtomRole(AUnicodeSide);
  if NewRole = arUnknown then
    NewRole := NameFallbackRole(ACategory, AName)
  else if NewRole = arBase then
  begin
    // Unicode says "a letter", but a glyph the mapping files as the FIRST or
    // SECOND HALF of a conjunct carries information Unicode does not: its key is
    // just the letter, while the group exists precisely because the glyph is a
    // half. Ansi Default 203A is 'na' and is the first half of "ntra", so it has
    // to bind the consonant that follows, or one press would need two on a
    // conjunct. A mark, a linker, a digit or a symbol keeps what Unicode said.
    Cat := UpperCase(Trim(ACategory));
    if Cat = 'FIRSTHALFFORMS' then
      NewRole := arHalfForm
    else if Cat = 'SECONDHALFFORMS' then
      NewRole := arSecondHalf;
  end;

  NewAtom.Units := AUnits;
  NewAtom.Role := NewRole;
  NewAtom.Bind := BindOfRole(NewRole);

  // A PRE-BASE vowel sign is written in FRONT of its consonant in a Bijoy-style
  // mapping (Ansi V1: "ki" is 'w' then 'K'). Unicode calls it a mark, but here
  // the mark belongs to the glyph to its RIGHT, so it binds forward. Without
  // this one press would need two on 'ki' - and with a blanket "mark binds to
  // the next consonant" instead, the trailing aa-kar of "bangla" would be
  // swallowed into the following consonant and one press would erase two
  // visible characters.
  if (NewRole = arMark) and IsPreBaseSignPoint(FirstBengaliCodePoint(AUnicodeSide)) then
    NewAtom.Bind := abFwd;
  NewAtom.Src := ASrc;
  NewAtom.Name := AName;
  // Only the leading Bengali run is a Unicode SOURCE. A field that names no
  // Bengali character - some constants carry an ASCII description such as '</'
  // rather than a key - is recorded as "none": the role came from the mapping's
  // own group and name then, and a reader must not believe the text.
  NewAtom.Uni := TrimToUnicodeSource(AUnicodeSide);

  if FByUnits.TryGetValue(AUnits, Old) then
  begin
    if (Old.Role = NewAtom.Role) and (Old.Bind = NewAtom.Bind) then
      Exit; // the same reading reached from another source - nothing to decide

    // Ambiguity. Keep the reading that starts a NEW cluster: an extra press is
    // recoverable, erasing two glyphs at once is not.
    if (Old.Bind = abSelf) or (Old.Role = arBase) then
    begin
      LogConflict(Old, NewAtom);
      Exit;
    end;

    LogConflict(NewAtom, Old);
    FByUnits.AddOrSetValue(AUnits, NewAtom);
    Exit;
  end;

  FByUnits.Add(AUnits, NewAtom);
end;

procedure TAnsiAtomMap.Index;
var
  Pair: TPair<string, TAnsiAtom>;
  I, J: Integer;
  Tmp:  TAnsiAtom;
begin
  SetLength(FAtoms, FByUnits.Count);
  I := 0;
  for Pair in FByUnits do
  begin
    FAtoms[I] := Pair.Value;
    Inc(I);
  end;

  // The dictionary has no order; tests and logs want a stable one.
  for I := 1 to high(FAtoms) do
  begin
    Tmp := FAtoms[I];
    J := I - 1;
    while (J >= 0) and (FAtoms[J].Units > Tmp.Units) do
    begin
      FAtoms[J + 1] := FAtoms[J];
      Dec(J);
    end;
    FAtoms[J + 1] := Tmp;
  end;
end;

function TAnsiAtomMap.Count: Integer;
begin
  Result := FByUnits.Count;
end;

function TAnsiAtomMap.MatchEndingAt(const AText: string; const AEnd: Integer; out AAtom: TAnsiAtom): Boolean;
var
  Len, Longest: Integer;
begin
  Result := False;
  AAtom.Units := '';
  AAtom.Role := arUnknown;
  AAtom.Bind := abSelf;
  AAtom.Src := '';
  AAtom.Name := '';
  AAtom.Uni := '';

  if (AEnd < 1) or (AEnd > Length(AText)) then
    Exit;

  // Longest match first. The step is bounded by MAX_ATOM_UNITS, so a trie would
  // only trade this loop for pointers nothing here is short of.
  Longest := AEnd;
  if Longest > MAX_ATOM_UNITS then
    Longest := MAX_ATOM_UNITS;

  for Len := Longest downto 1 do
  begin
    if FByUnits.TryGetValue(Copy(AText, AEnd - Len + 1, Len), AAtom) then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function TAnsiAtomMap.TailClusterUnits(const AText: string; const AMaxUnits: Integer): Integer;
var
  N, Head, Capped: Integer;
  Atom, HeadAtom, Prev: TAnsiAtom;
begin
  Result := 0;
  N := Length(AText);
  if N = 0 then
    Exit;

  Capped := AMaxUnits;
  if Capped < 1 then
    Capped := 1;
  if Capped > MAX_ATOM_UNITS then
    Capped := MAX_ATOM_UNITS;

  // The glyph that ends at the caret. Unknown text is ONE character.
  if not MatchEndingAt(AText, N, Atom) then
  begin
    Result := 1;
    Exit;
  end;

  Head := N - Length(Atom.Units) + 1;
  HeadAtom := Atom;

  // Walk leftwards while the boundary between the atom before the cluster and
  // the cluster's own first atom is suppressed: that is one visible character.
  while Head > 1 do
  begin
    if (N - Head + 1) >= Capped then
      Break;
    if not MatchEndingAt(AText, Head - 1, Prev) then
      Break; // the unit before the cluster is unknown - do not guess past it
    if Length(Prev.Units) >= Head then
      Break; // only a hand-built table can do this; never run off the text
    if ClusterBoundary(Prev, HeadAtom) then
      Break;

    Head := Head - Length(Prev.Units);
    HeadAtom := Prev;
  end;

  Result := N - Head + 1;
  if Result > Capped then
    Result := Capped;
end;

end.
