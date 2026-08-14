{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsBijoy2000ToUnicode;

{ =============================================================================
  ANSI (Bijoy 2000) -> Unicode reverse conversion.

  This is the exact inverse of TUnicodeToBijoy2000's data model: instead of
  hard-coding any glyph table, it *reads the current ANSI registry state* the
  same way the forward converter does. That means it automatically honours the
  selected mapping (Default, Ansi V3, SutonnyMJ, ...) and never drifts from
  the glyphs the forward pass actually emits, including multi-character
  glyphs (Ansi V3 renders আ as 'xy' and ক as '„þ') and JSON-driven overrides.

  Reverse pipeline (mirror of the forward Convert):
  1. Undo the JSON "PostReplacements" (the forward pass applies them last).
  2. Undo the FinalTouch glyph swaps (reph/z-fola/r-fola with u-kars).
  3. One combined glyph -> Unicode sweep: quotes (highest priority), half
  forms, second-half forms, folas, full forms, consonants, vowels,
  symbols and digits.  Kars and the reph glyph are left untouched.
  4. Move the reph glyph to the start of its preceding cluster, expand it
  to র্ (the forward pass places reph AFTER the cluster it marks).
  5. Move pre-base kars (ে/ৈ/ি) back after their conjunct-chain clusters,
  recognising both the raw ANSI glyphs and the already-unicode forms.
  6. Map the remaining kar glyphs to Unicode kars.
  7. Rejoin ো (ে+া) and ৌ (ে+ৗ) which the forward pass splits.

  The conversion is inherently lossy for ZWNJ/ZWJ and some half-form detail,
  exactly like Bijoy text itself.
  ============================================================================= }

interface

uses
  System.Generics.Collections,
  clsUnicodeToBijoy2000;

type
  TBijoy2000ToUnicode = class
    private
      FOnProgress: TConverterProgress;

      // glyph sequence -> glyph sequence (undo PostReplacements, last-first)
      FPostInverse: TArray<TReplacementPair>;
      // glyph sequence -> glyph sequence (undo FinalTouch swaps)
      FSwapBacks: TArray<TReplacementPair>;
      // combined glyph -> Unicode sweep table, sorted longest-glyph first
      FMain: TArray<TReplacementPair>;
      // pre-base kar glyphs (ে/ৈ/ি), sorted longest first
      FPreBaseKars: TArray<TReplacementPair>;
      // all other kar glyphs (া/ী/ু/ূ/ৃ/ৗ), for cluster detection
      FOtherKars: TArray<TReplacementPair>;
      // kar glyph -> Unicode kar, sorted longest first
      FKarMap: TArray<TReplacementPair>;
      // True once BuildTables has populated the arrays for the currently
      // loaded ANSI mapping.  Convert skips the rebuild (dictionary fills +
      // sorts) on every call; InvalidateTables resets it when the mapping
      // changes so the next Convert rebuilds exactly once.
      FTablesBuilt: Boolean;

      // Fast longest-match lookup tables for the single-pass sweeps (see
      // SweepReplace): every glyph key in a dictionary plus the longest key
      // length to try at each position.  Built alongside FMain/FKarMap.
      FMainLookup: TDictionary<string, string>;
      FMainMaxLen: Integer;
      FKarLookup:  TDictionary<string, string>;
      FKarMaxLen:  Integer;

      procedure ReportProgress(Percent: Integer; const Stage: string);
      procedure BuildTables;
      function VarGlyph(const AName: string): string;
      function CleanKey(const S: string): string;
      function IsSingleAsciiPunct(const S: string): Boolean;
      function HasNonHalfFormOwner(const Glyph: string): Boolean;
      function HasFirstHalfOwner(const Glyph: string): Boolean;
      function IsPreBaseKarAt(const Text: string; P: Integer; out GLen: Integer): Boolean;
      function IsConsonantChar(const C: Char): Boolean;
      function IsClusterMember(const Text: string; P: Integer; IsFirst: Boolean): Boolean;
      function GetPrecedingClusterStart(const Text: string; P: Integer): Integer;
      procedure ReorderReph(var Text: string);
      procedure ReorderPreBaseKars(var Text: string);
    public
      destructor Destroy; override;
      function Convert(const AnsiText: string): string;
      // Call after the ANSI mapping changes (JSON re-loaded / defaults
      // restored) so the cached lookup tables are rebuilt on the next call.
      procedure InvalidateTables;
      // Optional progress callback fired by Convert between pipeline stages.
      property OnProgress: TConverterProgress read FOnProgress write FOnProgress;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults,
  BanglaChars;

{ ============================================================================= }

// Reads the current glyph for a registry variable, honouring JSON overrides
// (mirror of GetAnsiVarValue in the forward unit).
function TBijoy2000ToUnicode.VarGlyph(const AName: string): string;
var
  Rec: TAnsiVarRec;
begin
  if AnsiOverrides <> nil then
    if AnsiOverrides.TryGetValue(AName, Result) then
      Exit;
  if (AnsiRegistryMap <> nil) and AnsiRegistryMap.TryGetValue(AName, Rec) then
  begin
    if Rec.VarType = avChar then
      Result := string(PChar(Rec.Ptr)^)
    else
      Result := PString(Rec.Ptr)^;
  end
  else
    Result := '';
end;

// Same cleaning the forward pass applies to BengaliChar registry values.
function TBijoy2000ToUnicode.CleanKey(const S: string): string;
var
  Idx: Integer;
begin
  Result := S;
  Idx := Pos(' ', Result);
  if Idx > 0 then
    Result := Copy(Result, 1, Idx - 1);
  Idx := Pos('(', Result);
  if Idx > 0 then
    Result := Copy(Result, 1, Idx - 1);
  Idx := Pos('-', Result);
  if Idx > 0 then
    Result := Copy(Result, 1, Idx - 1);
  Result := Trim(Result);
end;

// True for the single ASCII bracket/hyphen characters.  A custom full-form
// glyph that is a bracket or a hyphen (Ansi V3: ণ্ণ = ']', ঙ্ম = '-') is
// indistinguishable from the literal punctuation the forward pass passes
// through - brackets frame citations/numbers ([৫]) and hyphens join year
// ranges (১৯৪৭-১৯৪৮) in prose, so those keep their literal meaning.
// Quotation marks and letters keep their conjunct claim (ক্ষ্ম = '"'),
// since the conjunct is the common meaning there.
function TBijoy2000ToUnicode.IsSingleAsciiPunct(const S: string): Boolean;
begin
  Result := False;
  if Length(S) <> 1 then
    Exit;
  case S[1] of
    '[', ']', '{', '}', '(', ')', '<', '>', '-':
      Result := True;
  end;
end;

// True when some registry entry OTHER than the four quote vars and other than
// the half-form categories (FirstHalfForms / SecondHalfForms) uses Glyph as
// its glyph.  Used to decide whether a raw Unicode quote codepoint may claim
// that value: quotes beat SECOND-half forms (the user's explicit priority,
// e.g. a pasted U+2019 must not come back as the default ্+থ conjunct), but
// never a real letter (Ansi V3 maps ণ to U+2019 - that meaning must survive)
// and never a first-half form (A_C_1H owns U+201D in the default mapping -
// see HasFirstHalfOwner).  The half-form meanings are preserved anyway:
// first-half forms always keep a trailing হসন্ত glyph in forward output, and
// BuildTables claims those pairs contextually (longest key wins over the
// single quote codepoint).
function TBijoy2000ToUnicode.HasFirstHalfOwner(const Glyph: string): Boolean;
var
  R: TAnsiVarRec;
begin
  Result := False;
  if AnsiRegistryMap = nil then
    Exit;
  for R in AnsiRegistryMap.Values do
    if (R.Category = 'FirstHalfForms') and (VarGlyph(R.Name) = Glyph) then
    begin
      Result := True;
      Exit;
    end;
end;

function TBijoy2000ToUnicode.HasNonHalfFormOwner(const Glyph: string): Boolean;
var
  R: TAnsiVarRec;
begin
  Result := False;
  if AnsiRegistryMap = nil then
    Exit;
  for R in AnsiRegistryMap.Values do
    if (R.Name <> 'A_StartSingleQuote') and (R.Name <> 'A_EndSingleQuote') and (R.Name <> 'A_StartDoubleQuote') and (R.Name <> 'A_EndDoubleQuote') and
      (R.Category <> 'FirstHalfForms') and (R.Category <> 'SecondHalfForms') and (VarGlyph(R.Name) = Glyph) then
    begin
      Result := True;
      Exit;
    end;
end;

{ ============================================================================= }

procedure TBijoy2000ToUnicode.BuildTables;
var
  Dict:       TDictionary<string, string>;
  Rec:        TAnsiVarRec;
  Glyph, Uni: string;
  I:          Integer;

  // Adds only when the glyph is not yet claimed (first claim wins).
  procedure Add(const AKey, AValue: string);
  begin
    if (AKey <> '') and (AValue <> '') and not Dict.ContainsKey(AKey) then
      Dict.Add(AKey, AValue);
  end;

// Appends a glyph-sequence -> glyph-sequence swap (skips empty sides).
  procedure AddSwap(const AKey, AValue: string);
  var
    N: Integer;
  begin
    if (AKey = '') or (AValue = '') then
      Exit;
    N := Length(FSwapBacks);
    SetLength(FSwapBacks, N + 1);
    FSwapBacks[N].Key := AKey;
    FSwapBacks[N].Value := AValue;
  end;

begin
  Dict := TDictionary<string, string>.Create;
  try
    // ------------------------------------------------------------------
    // Quotes FIRST: in some mappings (BanglaPedia) the quote glyphs are the
    // raw Unicode codepoints U+2018/2019/201C/201D, which collide with the
    // default second-half glyph A_Th_2H = U+2019.  The quote meaning must
    // win, otherwise a closing quote comes back as the conjunct ্+থ.
    // ------------------------------------------------------------------
    Add(VarGlyph('A_StartSingleQuote'), b_StartSingleQuote);
    Add(VarGlyph('A_EndSingleQuote'), b_EndSingleQuote);
    Add(VarGlyph('A_StartDoubleQuote'), b_StartDoubleQuote);
    Add(VarGlyph('A_EndDoubleQuote'), b_EndDoubleQuote);

    // Raw Unicode quote codepoints win over SECOND-half-form conjunct
    // glyphs (in the default mapping A_Th_2H is U+2019, so a pasted '
    // would come back as ্+থ), but a codepoint owned by a FIRST-half form
    // keeps its conjunct meaning - in the default/SutonnyMJ mappings the
    // glyph of A_C_1H IS U+201D, and a bare " there is the half-form of
    // চ (চ্), not a quote.  Quotes never beat a real letter either
    // (Ansi V3: ণ = U+2019 keeps its letter meaning).
    if not HasNonHalfFormOwner(b_StartSingleQuote) and not HasFirstHalfOwner(b_StartSingleQuote) then
      Add(b_StartSingleQuote, b_StartSingleQuote);
    if not HasNonHalfFormOwner(b_EndSingleQuote) and not HasFirstHalfOwner(b_EndSingleQuote) then
      Add(b_EndSingleQuote, b_EndSingleQuote);
    if not HasNonHalfFormOwner(b_StartDoubleQuote) and not HasFirstHalfOwner(b_StartDoubleQuote) then
      Add(b_StartDoubleQuote, b_StartDoubleQuote);
    if not HasNonHalfFormOwner(b_EndDoubleQuote) and not HasFirstHalfOwner(b_EndDoubleQuote) then
      Add(b_EndDoubleQuote, b_EndDoubleQuote);

    // ------------------------------------------------------------------
    // Base LETTERS first.  A glyph shared by a letter and a conjunct
    // half-form keeps its LETTER meaning: several mappings reuse plain
    // glyphs for both - Ansi V3 maps ত and ্+ত to the same '‡þ' glyph,
    // ণ to the default ্+থ glyph, and হ to the default ভ্র-২য় খন্ড glyph
    // (Ansi V3 disables that half-form with an empty Value, which the
    // loader leaves at its stale default).  If the half-forms claimed those
    // glyphs first, every ত would come back as ্+ত and every হ as ভ্র -
    // exactly the corruption reported for Ansi V3.  Conjunct full forms
    // (FullForms category) are claimed AFTER the half-forms so that a
    // half-form wins over a full-form clash (SutonnyMJ maps both ত্ম and
    // ্+ত to the same 'Í' glyph; ্+ত is the common meaning there).  Kars
    // are handled by their own later passes.
    if AnsiRegistryMap <> nil then
      for Rec in AnsiRegistryMap.Values do
      begin
        if Rec.BengaliChar = '' then
          Continue;
        if (Rec.Category = 'FirstHalfForms') or (Rec.Category = 'SecondHalfForms') or (Rec.Category = 'FullForms') then
          Continue;
        // Vowel-sign kars are mapped after the reordering pass.
        if (Rec.Category = 'VowelsAndKars') and (Length(Rec.Name) >= 3) and SameText(Copy(Rec.Name, Length(Rec.Name) - 2, 3), 'Kar') then
          Continue;

        Glyph := VarGlyph(Rec.Name);
        if Glyph = '' then
          Continue;

        // The four quote vars are handled first (they win any glyph clash
        // with half-form conjuncts); skip them here.
        if (Rec.Name = 'A_StartSingleQuote') or (Rec.Name = 'A_EndSingleQuote') or (Rec.Name = 'A_StartDoubleQuote') or (Rec.Name = 'A_EndDoubleQuote') then
          Continue;
        Uni := CleanKey(Rec.BengaliChar);
        if Uni = '' then
          Continue;
        Add(Glyph, Uni);
      end;

    // ------------------------------------------------------------------
    // Half-form glyphs.  First-half forms stand for the consonant alone
    // (the forward pass keeps its hasanta in the following glyph), while
    // second-half forms bring their own leading hasanta (্+consonant).
    // A_C_1H is the exception: its default/SutonnyMJ glyph is U+201D, which
    // real Bijoy text writes as the complete চ্ (the next consonant follows
    // directly, with no separate হসন্ত glyph), so its bare form expands
    // with a hasanta below.
    // ------------------------------------------------------------------
    // Special pair: ঙ + ্ + ম is encoded as NGA_1H + plain ম (no hasanta).
    // Guarded: a mapping may blank either glyph (Ansi V3 blanks A_T_R_2H),
    // and a concatenation with one empty side would wrongly claim the
    // remaining single glyph.
    if (VarGlyph('A_NGA_1H') <> '') and (VarGlyph('A_M') <> '') then
      Add(VarGlyph('A_NGA_1H') + VarGlyph('A_M'), b_NGA + b_Hasanta + b_M);

    // Conjunct-with-r second halves decode to consonant + ্ + র.
    // In Ansi V3, A_T_R_2H is BLANK (ত্র 2H disabled) while A_M_2H_2 = #$BF
    // (default #$A7) - so a bare #$BF is ম্ম's second half there.  They are
    // contextually distinct: ত্র's second half always follows the hasanta
    // glyph left behind by a first-half form (ন্ত্র = [1H][্][ত্র-2H]), so
    // the longer contextual key below wins first and A_M_2H_2 claims the
    // bare #$BF.  Both sides of the key must be non-empty (see above).
    if (VarGlyph('A_Hasanta') <> '') and (VarGlyph('A_T_R_2H') <> '') then
      Add(VarGlyph('A_Hasanta') + VarGlyph('A_T_R_2H'), b_Hasanta + b_t + b_Hasanta + b_R); // ্ + ত্ + র
    Add(VarGlyph('A_M_2H_1'), b_Hasanta + b_M);
    Add(VarGlyph('A_M_2H_2'), b_Hasanta + b_M);
    Add(VarGlyph('A_T_R_2H'), b_t + b_Hasanta + b_R);   // ত্র ২য় খন্ড
    Add(VarGlyph('A_K_R_2H'), b_K + b_Hasanta + b_R);   // ক্র ২য় খন্ড
    Add(VarGlyph('A_BH_R_2H'), b_Bh + b_Hasanta + b_R); // ভ্র ২য় খন্ড

    Add(VarGlyph('A_B_2H_1'), b_Hasanta + b_B);
    Add(VarGlyph('A_B_2H_2'), b_Hasanta + b_B);
    Add(VarGlyph('A_B_2H_3'), b_Hasanta + b_B);
    Add(VarGlyph('A_B_2H_4'), b_Hasanta + b_B);
    Add(VarGlyph('A_BH_2H'), b_Hasanta + b_Bh);
    Add(VarGlyph('A_L_2H_1'), b_Hasanta + b_L);
    Add(VarGlyph('A_L_2H_2'), b_Hasanta + b_L);
    Add(VarGlyph('A_L_2H_3'), b_Hasanta + b_L);
    Add(VarGlyph('A_Nn_2H_1'), b_Hasanta + b_Nn);
    Add(VarGlyph('A_Nn_2H_2'), b_Hasanta + b_Nn);
    Add(VarGlyph('A_T_2H'), b_Hasanta + b_t);
    Add(VarGlyph('A_Th_2H'), b_Hasanta + b_Th);
    Add(VarGlyph('A_K_2H'), b_Hasanta + b_K);

    // First-half forms in forward output ALWAYS keep a trailing হসন্ত glyph
    // (FirstHalfForms replaces consonant+্ with [1H]+্, never swallows the
    // hasanta).  Claim the pair contextually so a forward-produced conjunct
    // like ্-চ (default A_C_1H = U+201D = ") still reverses to চ্ via the
    // longer key.  A BARE U+201D is also the half-form there (see
    // HasFirstHalfOwner), so it expands to চ্ by the single-glyph claim.
    if VarGlyph('A_Hasanta') <> '' then
    begin
      if VarGlyph('A_M_1H') <> '' then
        Add(VarGlyph('A_M_1H') + VarGlyph('A_Hasanta'), b_M + b_Hasanta);
      if VarGlyph('A_Ss_1H') <> '' then
        Add(VarGlyph('A_Ss_1H') + VarGlyph('A_Hasanta'), b_Ss + b_Hasanta);
      if VarGlyph('A_C_1H') <> '' then
        Add(VarGlyph('A_C_1H') + VarGlyph('A_Hasanta'), b_C + b_Hasanta);
      if VarGlyph('A_NGA_1H') <> '' then
        Add(VarGlyph('A_NGA_1H') + VarGlyph('A_Hasanta'), b_NGA + b_Hasanta);
      if VarGlyph('A_S_1H_1') <> '' then
        Add(VarGlyph('A_S_1H_1') + VarGlyph('A_Hasanta'), b_s + b_Hasanta);
      if VarGlyph('A_N_1H_1') <> '' then
        Add(VarGlyph('A_N_1H_1') + VarGlyph('A_Hasanta'), b_n + b_Hasanta);
      if VarGlyph('A_N_1H_2') <> '' then
        Add(VarGlyph('A_N_1H_2') + VarGlyph('A_Hasanta'), b_n + b_Hasanta);
      if VarGlyph('A_D_1H_1') <> '' then
        Add(VarGlyph('A_D_1H_1') + VarGlyph('A_Hasanta'), b_d + b_Hasanta);
      if VarGlyph('A_D_1H_2') <> '' then
        Add(VarGlyph('A_D_1H_2') + VarGlyph('A_Hasanta'), b_d + b_Hasanta);
    end;

    // Second-half forms that share their glyph with a quote codepoint
    // (default/SutonnyMJ: A_Th_2H = U+2019 = closing single quote) lose their
    // BARE claim to the quote identity above, so a conjunct written as
    // [1st-half][2nd-half] - exactly what the forward pass emits for স্থ and
    // ন্থ - must be claimed as an explicit multi-glyph pair.  The 2-char key
    // always beats the 1-char quote claim in the longest-first sweep, and a
    // quote never directly follows a half-form glyph in real text, so the
    // pair is unambiguous.
    if VarGlyph('A_Th_2H') <> '' then
    begin
      if VarGlyph('A_S_1H_1') <> '' then
        Add(VarGlyph('A_S_1H_1') + VarGlyph('A_Th_2H'), b_s + b_Hasanta + b_Th); // ¯' -> স্থ
      if VarGlyph('A_N_1H_1') <> '' then
        Add(VarGlyph('A_N_1H_1') + VarGlyph('A_Th_2H'), b_n + b_Hasanta + b_Th); // š' -> ন্থ
    end;

    Add(VarGlyph('A_M_1H'), b_M + b_Hasanta);
    Add(VarGlyph('A_Ss_1H'), b_Ss + b_Hasanta);
    Add(VarGlyph('A_C_1H'), b_C + b_Hasanta);
    Add(VarGlyph('A_NGA_1H'), b_NGA + b_Hasanta);
    Add(VarGlyph('A_S_1H_1'), b_s + b_Hasanta);
    Add(VarGlyph('A_N_1H_1'), b_n + b_Hasanta);
    Add(VarGlyph('A_N_1H_2'), b_n + b_Hasanta);
    Add(VarGlyph('A_D_1H_1'), b_d + b_Hasanta);
    Add(VarGlyph('A_D_1H_2'), b_d + b_Hasanta);

    // Folas.  (The reph glyph is deliberately NOT expanded here: it needs its
    // own re-ordering pass in Convert, and in BanglaPedia it shares a glyph
    // with A_Th_2H, so expanding it blindly would corrupt ্+থ conjuncts.)
    Add(VarGlyph('A_ZFola'), b_Hasanta + b_z);
    Add(VarGlyph('A_RFola_1'), b_Hasanta + b_R);
    Add(VarGlyph('A_RFola_2'), b_Hasanta + b_R);
    Add(VarGlyph('A_RFola_3'), b_Hasanta + b_R);

    // Registry conjunct full forms (extra glyphs like ত্ম in SutonnyMJ).
    // Claimed after the half-forms so a half-form clash wins there.
    if AnsiRegistryMap <> nil then
      for Rec in AnsiRegistryMap.Values do
      begin
        if Rec.BengaliChar = '' then
          Continue;
        if Rec.Category <> 'FullForms' then
          Continue;
        Glyph := VarGlyph(Rec.Name);
        if Glyph = '' then
          Continue;
        Uni := CleanKey(Rec.BengaliChar);
        if Uni = '' then
          Continue;
        Add(Glyph, Uni);
      end;

    // JSON-driven custom full forms (extra conjuncts).  A key that is a
    // single printable ASCII punctuation character is skipped: the forward
    // pass leaves ASCII text untouched, so a literal ']' or '-' in the
    // source (e.g. Ansi V3 maps ণ্ণ to ']' and ঙ্ম to '-') is
    // indistinguishable from the conjunct it stands for, and prose keeps
    // the punctuation.  Multi-char keys (স্ত = 'hßþ') cannot occur in
    // ordinary ASCII text, so they stay.
    for I := 0 to high(CustomFullForms) do
      if not IsSingleAsciiPunct(CustomFullForms[I].Value) then
        Add(CustomFullForms[I].Value, CustomFullForms[I].Key);

    // Invert the PreReplacements as a gap-fill: glyphs that have no other
    // meaning (e.g. Ansi V3's '!' -> ম্ন glyph, '*' -> A_B_2H glyph) come
    // back to the character the user actually typed.  Glyphs that DO have a
    // real conjunct meaning keep that meaning.
    for I := 0 to high(CustomPreReplacements) do
      Add(CustomPreReplacements[I].Value, CustomPreReplacements[I].Key);

    // Flatten + sort the sweep table longest-glyph-first so that multi-char
    // glyphs (আ = 'xy', ক = '„þ', ে2 = #$F6#$EC, ...) always win over the
    // shorter glyphs they contain.
    SetLength(FMain, Dict.Count);
    I := 0;
    for Glyph in Dict.Keys do
    begin
      FMain[I].Key := Glyph;
      FMain[I].Value := Dict[Glyph];
      Inc(I);
    end;
    TArray.Sort<TReplacementPair>(FMain, TComparer<TReplacementPair>.Construct(
          function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));

    // Fast lookup for the single-pass sweep (SweepReplace): every key plus
    // the longest key length to try at each position.  Rebuilt (not reused)
    // when the mapping changes and BuildTables runs again.
    FreeAndNil(FMainLookup);
    FMainLookup := TDictionary<string, string>.Create;
    FMainMaxLen := 0;
    for I := 0 to high(FMain) do
    begin
      FMainLookup.Add(FMain[I].Key, FMain[I].Value);
      if Length(FMain[I].Key) > FMainMaxLen then
        FMainMaxLen := Length(FMain[I].Key);
    end;

    // ------------------------------------------------------------------
    // Kar tables.
    // ------------------------------------------------------------------
    Dict.Clear;

    // Pre-base kars: the forward pass hoists these in front of the cluster.
    Add(VarGlyph('A_EKar1'), b_Ekar);
    Add(VarGlyph('A_EKar2'), b_Ekar);
    Add(VarGlyph('A_IKar'), b_Ikar);
    Add(VarGlyph('A_OIKar1'), b_OIkar);
    Add(VarGlyph('A_OIKar2'), b_OIkar);

    SetLength(FPreBaseKars, Dict.Count);
    I := 0;
    for Glyph in Dict.Keys do
    begin
      FPreBaseKars[I].Key := Glyph;
      FPreBaseKars[I].Value := Dict[Glyph];
      Inc(I);
    end;
    TArray.Sort<TReplacementPair>(FPreBaseKars, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));

    Dict.Clear;

    Add(VarGlyph('A_AAKar'), b_AAKar);
    Add(VarGlyph('A_IIKar'), b_IIkar);
    Add(VarGlyph('A_UKar1'), b_Ukar);
    Add(VarGlyph('A_UKar2'), b_Ukar);
    Add(VarGlyph('A_UKar3'), b_Ukar);
    Add(VarGlyph('A_UKar4'), b_Ukar);
    Add(VarGlyph('A_UUKar1'), b_UUkar);
    Add(VarGlyph('A_UUKar2'), b_UUkar);
    Add(VarGlyph('A_UUKar3'), b_UUkar);
    Add(VarGlyph('A_RRIKar1'), b_RRIkar);
    Add(VarGlyph('A_RRIKar2'), b_RRIkar);
    Add(VarGlyph('A_OUKar'), b_LengthMark);

    SetLength(FOtherKars, Dict.Count);
    I := 0;
    for Glyph in Dict.Keys do
    begin
      FOtherKars[I].Key := Glyph;
      FOtherKars[I].Value := Dict[Glyph];
      Inc(I);
    end;
    TArray.Sort<TReplacementPair>(FOtherKars, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));

    // Combined kar map (pre-base + others), longest first.
    SetLength(FKarMap, Length(FPreBaseKars) + Length(FOtherKars));
    for I := 0 to high(FPreBaseKars) do
      FKarMap[I] := FPreBaseKars[I];
    for I := 0 to high(FOtherKars) do
      FKarMap[Length(FPreBaseKars) + I] := FOtherKars[I];
    TArray.Sort<TReplacementPair>(FKarMap, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));

    // Fast lookup for the single-pass kar sweep (SweepReplace).
    FreeAndNil(FKarLookup);
    FKarLookup := TDictionary<string, string>.Create;
    FKarMaxLen := 0;
    for I := 0 to high(FKarMap) do
    begin
      FKarLookup.Add(FKarMap[I].Key, FKarMap[I].Value);
      if Length(FKarMap[I].Key) > FKarMaxLen then
        FKarMaxLen := Length(FKarMap[I].Key);
    end;

    // ------------------------------------------------------------------
    // FinalTouch swap inversions (glyph sequence -> glyph sequence).
    // The forward pass swaps reph/z-fola/r-fola around the u-kar glyphs at
    // the very end; the reverse swaps them back before anything expands.
    // ------------------------------------------------------------------
    SetLength(FSwapBacks, 0);

    // Last forward op first: [UKar1][Reph] -> [UKar2][Reph] nets out to
    // [UKar2][Reph] meaning the original [Reph][UKar1].  This is inherently
    // lossy: forward also produces [UKar2][Reph] from [Reph][UKar2], which
    // cannot be told apart afterwards.
    AddSwap(VarGlyph('A_UKar2') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UKar1'));
    AddSwap(VarGlyph('A_UKar3') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UKar3'));
    AddSwap(VarGlyph('A_UKar4') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UKar4'));
    AddSwap(VarGlyph('A_UUKar1') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UUKar1'));
    AddSwap(VarGlyph('A_UUKar2') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UUKar2'));
    AddSwap(VarGlyph('A_UUKar3') + VarGlyph('A_Reph'), VarGlyph('A_Reph') + VarGlyph('A_UUKar3'));

    AddSwap(VarGlyph('A_UKar1') + VarGlyph('A_RFola_1'), VarGlyph('A_RFola_1') + VarGlyph('A_UKar1'));
    AddSwap(VarGlyph('A_UUKar1') + VarGlyph('A_RFola_1'), VarGlyph('A_RFola_1') + VarGlyph('A_UUKar1'));
    AddSwap(VarGlyph('A_UKar1') + VarGlyph('A_RFola_2'), VarGlyph('A_RFola_2') + VarGlyph('A_UKar1'));
    AddSwap(VarGlyph('A_UUKar1') + VarGlyph('A_RFola_2'), VarGlyph('A_RFola_2') + VarGlyph('A_UUKar1'));

    AddSwap(VarGlyph('A_UKar1') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UKar1'));
    AddSwap(VarGlyph('A_UKar2') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UKar2'));
    AddSwap(VarGlyph('A_UKar3') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UKar3'));
    AddSwap(VarGlyph('A_UKar4') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UKar4'));
    AddSwap(VarGlyph('A_UUKar1') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UUKar1'));
    AddSwap(VarGlyph('A_UUKar2') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UUKar2'));
    AddSwap(VarGlyph('A_UUKar3') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_UUKar3'));

    AddSwap(VarGlyph('A_Reph') + VarGlyph('A_ZFola'), VarGlyph('A_ZFola') + VarGlyph('A_Reph'));

    // ------------------------------------------------------------------
    // PostReplacement inversions (undo, last applied first).
    // ------------------------------------------------------------------
    SetLength(FPostInverse, Length(CustomPostReplacements));
    for I := 0 to high(CustomPostReplacements) do
    begin
      FPostInverse[I].Key := CustomPostReplacements[I].Value;
      FPostInverse[I].Value := CustomPostReplacements[I].Key;
    end;

    // Everything is built and sorted - cache it until the mapping changes.
    FTablesBuilt := True;
  finally
    Dict.Free;
  end;
end;

procedure TBijoy2000ToUnicode.InvalidateTables;
begin
  FTablesBuilt := False;
end;

{ ============================================================================= }

function TBijoy2000ToUnicode.IsPreBaseKarAt(const Text: string; P: Integer; out GLen: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  GLen := 0;
  if (P >= 1) and (P <= Length(Text)) then
  begin
    // Already-unicode pre-base kars: some text reaches this pass with the
    // kar glyphs already converted (pasted Unicode, or a sweep that resolved
    // them early).  Detect the Unicode forms directly - U+09C7/U+09C8/U+09BF.
    if (Text[P] = b_Ekar) or (Text[P] = b_OIkar) or (Text[P] = b_Ikar) then
    begin
      Result := True;
      GLen := 1;
      Exit;
    end;
  end;
  for I := 0 to high(FPreBaseKars) do
    if (Length(FPreBaseKars[I].Key) <= Length(Text) - P + 1) and (Copy(Text, P, Length(FPreBaseKars[I].Key)) = FPreBaseKars[I].Key) then
    begin
      Result := True;
      GLen := Length(FPreBaseKars[I].Key);
      Exit; // sorted longest-first, so this is the longest match
    end;
end;

// Bengali consonant (or ৎ / ড় / ঢ় / য়)?
function TBijoy2000ToUnicode.IsConsonantChar(const C: Char): Boolean;
var
  O: Integer;
begin
  O := Ord(C);
  Result := (O = $09CE) or ((O >= $0995) and (O <= $09B9)) or (O = $09DC) or (O = $09DD) or (O = $09DF);
end;

// Cluster membership for the kar re-ordering pass.  A cluster is a conjunct
// chain: a first consonant, then only consonants that are PRECEDED by a
// হসন্ত (plus the হসন্ত themselves, and a nukta).  A consonant that is not
// preceded by a হসন্ত starts a fresh syllable, so the kar must stop there -
// e.g. in ি+দ্+ব+ত the ি belongs to দ্ব only, and ত starts a new syllable
// (দ্বিতীয়, not দ্বতিীয়).  Folas (্য/্র/্ব/্ম/্ল) are already ্+consonant
// after the sweep, so the same rule covers them.
function TBijoy2000ToUnicode.IsClusterMember(const Text: string; P: Integer; IsFirst: Boolean): Boolean;
begin
  if IsFirst then
    Result := IsConsonantChar(Text[P])
  else if (Text[P] = b_Hasanta) or (Text[P] = b_Nukta) then
    Result := True
  else
    Result := IsConsonantChar(Text[P]) and (P > 1) and (Text[P - 1] = b_Hasanta);
end;

// Scans backwards from P (a consonant) across the conjunct chain
// [consonant (্ consonant)*] that ends at P, returning the index of its
// first character (0 when P is not a consonant).
function TBijoy2000ToUnicode.GetPrecedingClusterStart(const Text: string; P: Integer): Integer;
begin
  Result := 0;
  if (P < 1) or (P > Length(Text)) or not IsConsonantChar(Text[P]) then
    Exit;
  Result := P;
  while (Result - 2 >= 1) and (Text[Result - 1] = b_Hasanta) and IsConsonantChar(Text[Result - 2]) do
    Result := Result - 2;
end;

// The forward pass (ReArrangeReph) places the reph glyph right AFTER the
// consonant cluster it belongs to - the reph mark sits over the preceding
// glyph in Bijoy.  In Unicode the র্ must LEAD the cluster, so move each
// reph glyph to the start of the cluster immediately before it, then expand
// it to র্ (র + হসন্ত).  This restores কার্যকর (not কাযর্কর) and
// পূর্ববঙ্গ (not পূবর্বঙ্গ).
procedure TBijoy2000ToUnicode.ReorderReph(var Text: string);
var
  RephGlyph:    string;
  ClusterStart: Integer;
  I:            Integer;
begin
  RephGlyph := VarGlyph('A_Reph');
  if RephGlyph = '' then
    Exit;
  I := 1;
  while I <= Length(Text) do
  begin
    if (I + Length(RephGlyph) - 1 <= Length(Text)) and (Copy(Text, I, Length(RephGlyph)) = RephGlyph) then
    begin
      ClusterStart := GetPrecedingClusterStart(Text, I - 1);
      if ClusterStart > 0 then
      begin
        Text := Copy(Text, 1, ClusterStart - 1) + RephGlyph + Copy(Text, ClusterStart, I - ClusterStart) + Copy(Text, I + Length(RephGlyph), MaxInt);
        I := ClusterStart + Length(RephGlyph);
      end
      else
        Inc(I, Length(RephGlyph));
    end
    else
      Inc(I);
  end;
  // Expand every remaining reph glyph to র্ (র + হসন্ত).
  Text := ReplaceStr(Text, RephGlyph, b_R + b_Hasanta);
end;

// Reverse of ReArrangeKars: pre-base kars (ে/ৈ/ি) were hoisted in front of
// their consonant cluster by the forward pass; move each one back to just
// after that cluster.  The kar is recognised in BOTH forms - the raw ANSI
// glyph and the already-unicode U+09C7/U+09C8/U+09BF - so the pass works no
// matter when the kars were resolved.  NOTE: the Unicode detection is
// unconditional (per spec) - an already-correct pre-base kar in valid
// Unicode is locally indistinguishable from a Bijoy-ordered one (both are
// "consonant, kar, consonant"), so text pasted in valid Unicode order is
// treated as Bijoy-ordered.  The tool's input is expected to be Bijoy
// glyphs, so this is acceptable.  The scan is left-to-right and continues
// right after a moved kar (never re-processing it), so consecutive kars
// (িতে -> ি+ে+য়) still reorder correctly.
procedure TBijoy2000ToUnicode.ReorderPreBaseKars(var Text: string);
var
  I, J, GLen: Integer;
  IsFirst:    Boolean;
  SB:         TStringBuilder;
begin
  if Text = '' then
    Exit;

  // The old code rebuilt the whole string (four Copy concatenations) for
  // every pre-base kar it moved - O(N^2) on kar-heavy Bengali text.  Build
  // the output once in a single left-to-right pass: when a kar is followed
  // by a conjunct chain, emit the chain first and the kar right after it
  // (exactly the move the in-place version performed), then keep scanning
  // the original input from after the cluster - the suffix the in-place
  // version scanned next is byte-identical to the original input there.
  SB := TStringBuilder.Create(Length(Text) + 16);
  try
    I := 1;
    while I <= Length(Text) do
    begin
      if IsPreBaseKarAt(Text, I, GLen) then
      begin
        J := I + GLen;
        IsFirst := True;
        while (J <= Length(Text)) and IsClusterMember(Text, J, IsFirst) do
        begin
          Inc(J);
          IsFirst := False;
        end;
        if J > I + GLen then
        begin
          // Cluster [I+GLen .. J-1] first, then the kar moved after it.
          SB.Append(Copy(Text, I + GLen, J - I - GLen));
          SB.Append(Copy(Text, I, GLen));
          I := J; // continue right after the moved kar
        end
        else
        begin
          SB.Append(Copy(Text, I, GLen));
          Inc(I, GLen);
        end;
      end
      else
      begin
        SB.Append(Text[I]);
        Inc(I);
      end;
    end;
    Text := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ ============================================================================= }

// Single-pass equivalent of "run one full ReplaceStr pass per table entry,
// longest key first": at each position take the LONGEST key that matches and
// emit its value, otherwise copy the character.  This is exactly what the
// old sequential sweep produced - a longer key always ran before a shorter
// one, and every replacement value here is a Unicode-range string that can
// never match another (ANSI-range) glyph key, so no value is ever re-scanned.
// Cost: O(N * longest-key-length) instead of O(N * entry count) with a full
// string rebuild per entry.
function SweepReplace(const S: string; const Lookup: TDictionary<string, string>; MaxLen: Integer): string;
var
  SB: TStringBuilder;
  N, I, L: Integer;
  V:  string;
begin
  if (S = '') or (Lookup = nil) or (Lookup.Count = 0) then
    Exit(S);
  SB := TStringBuilder.Create(Length(S) + 16);
  try
    N := Length(S);
    I := 1;
    while I <= N do
    begin
      L := MaxLen;
      if L > N - I + 1 then
        L := N - I + 1;
      V := '';
      while L >= 1 do
      begin
        if Lookup.TryGetValue(Copy(S, I, L), V) then
          Break;
        Dec(L);
      end;
      if L >= 1 then
      begin
        SB.Append(V);
        Inc(I, L);
      end
      else
      begin
        SB.Append(S[I]);
        Inc(I);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TBijoy2000ToUnicode.ReportProgress(Percent: Integer; const Stage: string);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, Percent, Stage);
end;

destructor TBijoy2000ToUnicode.Destroy;
begin
  FMainLookup.Free;
  FKarLookup.Free;
  inherited Destroy;
end;

function TBijoy2000ToUnicode.Convert(const AnsiText: string): string;
const
  TotalStages = 8;
var
  Text:    string;
  I:       Integer;
  StageNo: Integer;
  SB:      TStringBuilder;
begin
  if AnsiText = '' then
    Exit('');

  StageNo := 0;

  // Tables depend on the currently selected ANSI mapping.  They are built
  // once and cached (InvalidateTables marks them stale when the mapping
  // changes), so repeated Convert calls no longer rebuild and re-sort
  // hundreds of dictionary entries on every single invocation.
  if not FTablesBuilt then
    BuildTables;
  Text := AnsiText;

  // 1. Undo the JSON PostReplacements (forward applies them last).
  for I := high(FPostInverse) downto 0 do
    Text := ReplaceStr(Text, FPostInverse[I].Key, FPostInverse[I].Value);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'post-inverse');

  // 2. Undo the FinalTouch glyph swaps.
  for I := 0 to high(FSwapBacks) do
    Text := ReplaceStr(Text, FSwapBacks[I].Key, FSwapBacks[I].Value);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'swap-backs');

  // 3. Combined glyph -> Unicode sweep (longest glyph first).  Kars and the
  // reph glyph survive this pass on purpose.  Single pass: the old code ran
  // one full ReplaceStr scan + rebuild per table entry (hundreds of passes),
  // which dominated the conversion time on large texts.
  Text := SweepReplace(Text, FMainLookup, FMainMaxLen);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'main-sweep');

  // 3.5 A conjunct written as [first-half][second-half] - exactly what the
  // forward pass emits (¯ + ‹ for স্ক) - decodes to consonant+্ from the
  // first half and ্+consonant from the second half, yielding a doubled
  // হসন্ত that breaks the conjunct (স্্‌ক instead of স্‌ক).  The forward
  // pass only ever produces a doubled হসন্ত from a doubled হসন্ত input
  // (DeNormalize just reduces runs), which real Bijoy text does not
  // contain, so collapsing runs back to a single ্ is safe and restores
  // the joining form.  One left-to-right pass collapsing every run of 2+
  // hasantas to a single hasanta - the old repeat Pos + Delete loop was
  // O(N^2) on dense runs (k hasantas collapse to 1 either way).
  SB := TStringBuilder.Create(Length(Text) + 8);
  try
    I := 1;
    while I <= Length(Text) do
    begin
      if Text[I] = b_Hasanta then
      begin
        SB.Append(b_Hasanta);
        while (I <= Length(Text)) and (Text[I] = b_Hasanta) do
          Inc(I);
      end
      else
      begin
        SB.Append(Text[I]);
        Inc(I);
      end;
    end;
    Text := SB.ToString;
  finally
    SB.Free;
  end;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'hasanta-collapse');

  // 4. Move the reph glyph to the start of its cluster, then expand to র্.
  ReorderReph(Text);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'reorder-reph');

  // 5. Put ে/ৈ/ি back after their conjunct-chain clusters.
  ReorderPreBaseKars(Text);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'reorder-prebase');

  // 6. Remaining kar glyphs -> Unicode kars.  Single pass (same reasoning
  // as the main sweep; values are Unicode-range so never re-matched).
  Text := SweepReplace(Text, FKarLookup, FKarMaxLen);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'kar-map');

  // 7. Rejoin the split ো and ৌ.
  Text := ReplaceStr(Text, b_Ekar + b_AAKar, b_Okar);
  Text := ReplaceStr(Text, b_Ekar + b_LengthMark, b_OUkar);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rejoin');

  Result := Text;
end;

end.
