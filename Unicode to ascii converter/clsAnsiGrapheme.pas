{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsAnsiGrapheme;

{
  clsAnsiGrapheme - ONE backspace = ONE visible character, for every ANSI
  mapping (Ansi V1..V4 and any mapping added later). The caller keeps a ledger
  of the text it committed to the host, and this unit removes the last GRAPHEME
  CLUSTER from that text. The mapping takes part only through Convert(), so a
  mapping added tomorrow behaves exactly like the four shipped today.

  Why the ledger text needs segmentation at all
  ---------------------------------------------
  One Bangla letter is several Unicode code points and several ANSI units
  (Ansi V3: the letter I is 'A3 7A', U is '76 FE 7A', K is '201E FE').
  Removing the last code point of ka + hasanta + ka leaves a half drawn letter
  that needs a second press, and removing the last code point of ka + i-kar
  leaves the letter and drops its kar. Both questions are answered by the
  grapheme rules below.

  Implemented UAX#29 subset (each rule sits next to its code below)
  -----------------------------------------------------------------
  GB9   x (Extend | ZWJ)   - a nonspacing mark or a joiner never starts a
  cluster (Bengali Mn, ZWJ, ZWNJ)
  GB9a  x SpacingMark      - a spacing mark (Bengali Mc) binds BACKWARDS,
  so an anusvara stays with the letter it follows
  GB9c  Consonant (Extend | Linker)* Linker (Extend | Linker)* x Consonant
  - the hasanta links a conjunct: ka + hasanta + ssa
  is ONE cluster, and so is ra + hasanta + ka
  GB4/GB5 (default break)  - everything else starts a new cluster
  Hangul (GB6..GB8), emoji ZWJ (GB11) and regional indicators (GB12/GB13) are
  not implemented: a Bengali ANSI mapping cannot emit those clusters.

  Two deliberate deviations, both under ARephSurvives = True (legacy mode)
  -----------------------------------------------------------------------
  ARephSurvives = False (default, "like Unicode"):
  * ra + hasanta + consonant and ZWJ/ZWNJ + hasanta + consonant are single
  clusters under GB9c, so ONE press erases the whole cluster.
  ARephSurvives = True (the pre-existing behaviour, kept for a setting):
  * reph: erase ra + hasanta and KEEP the consonant ("the letter itself
  survives") - two presses for that cluster;
  * joiner form: erase ZWJ/ZWNJ + hasanta + consonant and keep the base.

  LIMITATION: text is indexed in UTF-16 code units. Bengali (U+0980..U+09FF),
  ZWJ and ZWNJ are all in the BMP, so for Bengali one code point is one Char;
  an astral code point (a surrogate pair) is counted as two.
}

interface

type
  { What a code unit is, for the cluster rules above. }
  TGraphemeClass = (gcOther, gcExtend, gcLinker, gcSpacingMark, gcConsonant);

  { Removes the last grapheme cluster from S.
    Returns True when a cluster (at least one code unit) was removed and NewS is
    the remaining text; False when S was empty, in which case NewS = S. }
function DropLastGraphemeCluster(const S: string; out NewS: string; ARephSurvives: Boolean = False): Boolean;

{ The last grapheme cluster of S, or an empty string when S is empty. }
function LastGraphemeCluster(const S: string): string;

{ Number of grapheme clusters in S. }
function GraphemeClusterCount(const S: string): Integer;

{ Cluster-level classification of ONE code point. Shared with the ANSI atom map
  (clsAnsiAtomMap), so the Unicode side of a cluster and the mapping side can
  never disagree about what binds to what. }
function IsLinkerPoint(const C: Char): Boolean;      // the virama / hasanta
function IsMarkPoint(const C: Char): Boolean;        // Mn, plus ZWJ / ZWNJ
function IsSpacingMarkPoint(const C: Char): Boolean; // Mc: kars, anusvara, visarga
function IsConsonantPoint(const C: Char): Boolean;   // Bengali consonants
function IsDigitPoint(const C: Char): Boolean;       // Bengali and ASCII digits

{ A PRE-BASE vowel sign: written in FRONT of the consonant it belongs to. In
  the Unicode text the sign follows its consonant, but a Bijoy-style ANSI
  mapping emits it first (Ansi V1: "ki" is 'w' then 'K'), so an ANSI reader has
  to treat this one mark as binding FORWARD - otherwise the rendering of one
  character would look like two. }
function IsPreBaseSignPoint(const C: Char): Boolean;

implementation

uses
  BanglaChars;

{ GCB = Extend / ZWJ, plus the Bengali Mn marks. The common combining ranges
  are included so mixed text (a Latin letter with a combining accent) does not
  split either. }
function IsExtendChar(const C: Char): Boolean;
var
  P: Integer;
begin
  if (C = ZWJ) or (C = ZWNJ) then
  begin
    Result := True;
    Exit;
  end;

  P := Ord(C);

  // Bengali nonspacing marks (Mn): candrabindu, nukta, vocalic RR, hasanta,
  // vocalic L / LL, sandhi mark
  if (P = $0981) or (P = $09BC) or (P = $09C4) or (P = $09CD) or (P = $09E2) or (P = $09E3) or (P = $09FE) then
  begin
    Result := True;
    Exit;
  end;

  Result := ((P >= $0300) and (P <= $036F)) or ((P >= $0483) and (P <= $0489)) or ((P >= $0591) and (P <= $05BD)) or ((P >= $0610) and (P <= $061A)) or
    ((P >= $064B) and (P <= $065F)) or ((P >= $1AB0) and (P <= $1AFF)) or ((P >= $1DC0) and (P <= $1DFF)) or ((P >= $20D0) and (P <= $20FF)) or
    ((P >= $FE00) and (P <= $FE0F)) or ((P >= $FE20) and (P <= $FE2F));
end;

{ InCB = Linker: the virama of the Indic scripts. Every one of them is also a
  nonspacing mark, so linkers are checked before IsExtendChar. }
function IsLinkerChar(const C: Char): Boolean;
var
  P: Integer;
begin
  P := Ord(C);

  Result := (P = $094D) or (P = $09CD) or (P = $0A4D) or (P = $0ACD) or (P = $0B4D) or (P = $0BCD) or (P = $0C4D) or (P = $0CCD) or (P = $0D4D);
end;

{ GCB = SpacingMark (Bengali Mc). ANUSVARA and VISARGA sit in the mapping's
  Consonants group, but Unicode decides the cluster: they bind backwards. }
function IsSpacingMarkChar(const C: Char): Boolean;
var
  P: Integer;
begin
  P := Ord(C);

  Result := (P = $0982) or (P = $0983) or ((P >= $09BE) and (P <= $09C3)) or (P = $09C7) or (P = $09C8) or (P = $09CB) or (P = $09CC) or (P = $09D7);
end;

{ InCB = Consonant, Bengali: ka..ha, khanda ta, rra / rha / yya, ra / va. The
  independent vowels (U+0985..U+0994) are deliberately not consonants here. }
function IsConsonantChar(const C: Char): Boolean;
var
  P: Integer;
begin
  P := Ord(C);

  Result := ((P >= $0995) and (P <= $09B9)) or (P = $09CE) or ((P >= $09DC) and (P <= $09DF)) or (P = $09F0) or (P = $09F1);
end;

function GraphemeClassOf(const C: Char): TGraphemeClass;
begin
  if IsLinkerChar(C) then
    Result := gcLinker
  else if IsSpacingMarkChar(C) then
    Result := gcSpacingMark
  else if IsExtendChar(C) then
    Result := gcExtend
  else if IsConsonantChar(C) then
    Result := gcConsonant
  else
    Result := gcOther;
end;

{ GB9c, read backwards: S[APos] is the code unit right before a consonant.
  Skip every Extend / Linker code unit; the skipped run must contain at least
  one Linker (the hasanta) and the code unit before the run must be a
  consonant - that is exactly ka + hasanta + ssa. }
function LinkedConsonantBefore(const S: string; const APos: Integer): Boolean;
var
  I:         Integer;
  SawLinker: Boolean;
begin
  SawLinker := False;
  I := APos;

  while I >= 1 do
  begin
    if GraphemeClassOf(S[I]) = gcLinker then
      SawLinker := True
    else if GraphemeClassOf(S[I]) <> gcExtend then
      Break;
    Dec(I);
  end;

  Result := SawLinker and (I >= 1) and (GraphemeClassOf(S[I]) = gcConsonant);
end;

{ May a cluster boundary sit between S[APos] and S[APos + 1]?
  APos must be in the range 1 .. Length(S) - 1. }
function IsClusterBreakAt(const S: string; const APos: Integer): Boolean;
var
  Right: TGraphemeClass;
begin
  Right := GraphemeClassOf(S[APos + 1]);

  // GB9 and GB9a: a mark, a joiner or a spacing mark never starts a cluster.
  if Right in [gcExtend, gcLinker, gcSpacingMark] then
  begin
    Result := False;
    Exit;
  end;

  // GB9c: a virama linked conjunct stays one cluster.
  if (Right = gcConsonant) and LinkedConsonantBefore(S, APos) then
  begin
    Result := False;
    Exit;
  end;

  // GB4 / GB5 and the default rule: everything else starts a new cluster.
  Result := True;
end;

{ Index of the first code unit of the last cluster. Always >= 1 for S <> ''. }
function ClusterStartOfLast(const S: string): Integer;
begin
  Result := Length(S);

  while (Result > 1) and (not IsClusterBreakAt(S, Result - 1)) do
    Dec(Result);
end;

function DropLastGraphemeCluster(const S: string; out NewS: string; ARephSurvives: Boolean = False): Boolean;
var
  L: Integer;
begin
  NewS := S;
  Result := False;

  L := Length(S);
  if L = 0 then
    Exit;

  if ARephSurvives then
  begin
    // Legacy reph: ra + hasanta + consonant -> erase ra + hasanta and keep the
    // consonant on screen.
    if (L >= 3) and (S[L - 2] = b_R) and (S[L - 1] = b_Hasanta) and (GraphemeClassOf(S[L]) = gcConsonant) then
    begin
      NewS := Copy(S, 1, L - 3) + S[L];
      Result := True;
      Exit;
    end;

    // Legacy joiner form: base + ZWJ / ZWNJ + hasanta + consonant -> erase the
    // joiner form (ZWJ/ZWNJ + hasanta + consonant) and keep the base it hangs
    // on. S[L] is the LAST code unit, so the joiner sits at L - 2.
    if (L >= 3) and ((S[L - 2] = ZWJ) or (S[L - 2] = ZWNJ)) and (S[L - 1] = b_Hasanta) and (GraphemeClassOf(S[L]) = gcConsonant) then
    begin
      NewS := Copy(S, 1, L - 3);
      Result := True;
      Exit;
    end;
  end;

  NewS := Copy(S, 1, ClusterStartOfLast(S) - 1);
  Result := True;
end;

function LastGraphemeCluster(const S: string): string;
begin
  if S = '' then
  begin
    Result := '';
    Exit;
  end;

  Result := Copy(S, ClusterStartOfLast(S), MaxInt);
end;

function IsLinkerPoint(const C: Char): Boolean;
begin
  Result := IsLinkerChar(C);
end;

function IsMarkPoint(const C: Char): Boolean;
begin
  Result := IsExtendChar(C);
end;

function IsSpacingMarkPoint(const C: Char): Boolean;
begin
  Result := IsSpacingMarkChar(C);
end;

function IsConsonantPoint(const C: Char): Boolean;
begin
  Result := IsConsonantChar(C);
end;

function IsDigitPoint(const C: Char): Boolean;
var
  P: Integer;
begin
  P := Ord(C);
  Result := ((P >= $09E6) and (P <= $09EF)) or ((P >= Ord('0')) and (P <= Ord('9')));
end;

function IsPreBaseSignPoint(const C: Char): Boolean;
begin
  // i, e, ai, o, au - the Bengali vowel signs that sit before the consonant
  Result := (C = #$09BF) or (C = #$09C7) or (C = #$09C8) or (C = #$09CB) or (C = #$09CC);
end;

function GraphemeClusterCount(const S: string): Integer;
var
  I, L: Integer;
begin
  Result := 0;
  L := Length(S);
  I := 1;

  while I <= L do
  begin
    Inc(Result);

    while (I < L) and (not IsClusterBreakAt(S, I)) do
      Inc(I);

    Inc(I);
  end;
end;

end.
