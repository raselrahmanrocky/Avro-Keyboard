{=============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================}
{$INCLUDE ../ProjectDefines.inc}
{$O-}
unit clsAnsiSequenceLookup;
{
  Precompiled O(1) sequence map used by ResolveAnsiSequence for isolated
  modifier resolution (kars / phalas / hasanta typed while the word buffer
  is empty).

  Every Unicode-context rule is registered under BOTH key flavors so lookups
  succeed no matter whether the preceding context came from Avro's own buffer
  (Unicode) or from the caret sniffer (raw ANSI glyph):
    - Unicode key :  #$099B#$09CD#$09B0 + modifier   ('ছ' + '্র')
    - ANSI mirror :  Convert(#$099B)     + modifier   ('Q'  + '্র')

  Entries whose group members are already ANSI strings (AnsiGroupMap /
  RaPhalaGroups) are registered ONLY under their ANSI key and never passed
  through Convert again.
}

interface

uses
  System.Generics.Collections,
  clsUnicodeToBijoy2000;

procedure CompileAnsiSequenceMap;

implementation

uses
  BanglaChars;

procedure CompileAnsiSequenceMap;
var
  I, J:         Integer;
  Rule:         TRfolaRule;
  VRule:        TVowelRule;
  Mapping:      TVowelRuleMapping;
  GroupMembers: TArray<string>;
  Member:       string;
  TempBijoy:    TUnicodeToBijoy2000;

  // Records AnsiCtx -> UniCtx in the sniffer reverse map, keeping ALL
  // candidates when distinct clusters share one ANSI rendering.
  procedure AddReverseCandidate(const AnsiCtx, UniCtx: string);
  var
    Arr: TAnsiUniCandidates;
    N:   Integer;
  begin
    if AnsiToUniMap.TryGetValue(AnsiCtx, Arr) then
    begin
      for N := 0 to High(Arr) do
        if Arr[N] = UniCtx then
          Exit; // already present
      SetLength(Arr, Length(Arr) + 1);
      Arr[High(Arr)] := UniCtx;
      AnsiToUniMap.AddOrSetValue(AnsiCtx, Arr);
    end
    else
    begin
      SetLength(Arr, 1);
      Arr[0] := UniCtx;
      AnsiToUniMap.AddOrSetValue(AnsiCtx, Arr);
    end;
  end;

  // Register a rule anchored on a UNICODE cluster. Both the Unicode key and
  // its ANSI mirror get the same entry; the reverse map records ANSI->Unicode
  // so sniffer-derived contexts can be chained. AnsiOutput stores ONLY the
  // suffix not already present in the context rendering (the part the user
  // still has to see appear); EraseCount counts the glyphs it replaces.
  // A toggle-capable entry is never overwritten by a later plain one (the
  // JSON lists specific consonant rules before the broad groups they also
  // belong to - e.g. ra appears explicitly AND inside BaseLineRight).
  procedure RegUni(const UniCtx, Modifier, AltRaw: string; IsToggle: Boolean);
  var
    E, Existing: TAnsiSequenceEntry;
    AnsiCtx: string;
    AnsiOut: string;
    PLen:    Integer;

    function OverwritesToggle(const Key: string): Boolean;
    begin
      Result := AnsiSequenceLookup.TryGetValue(Key, Existing) and Existing.IsToggleEntry and (not IsToggle);
    end;

  begin
    if UniCtx = '' then
      Exit;
    AnsiCtx := TempBijoy.Convert(UniCtx);
    if AnsiCtx = '' then
      Exit;
    AnsiOut := TempBijoy.Convert(UniCtx + Modifier);
    if AnsiOut = '' then
      Exit;

    PLen := CommonPrefixLen(AnsiCtx, AnsiOut);
    E.AnsiOutput := Copy(AnsiOut, PLen + 1, MaxInt);
    E.EraseCount := Length(AnsiCtx) - PLen;
    if (E.AnsiOutput = '') and (E.EraseCount = 0) then
      Exit; // modifier produces no visible change - nothing to register

    E.IsToggleEntry := IsToggle;
    if IsToggle then
      E.AltAnsiOutput := ResolveValue(AltRaw)
    else
      E.AltAnsiOutput := '';

    if not OverwritesToggle(UniCtx + Modifier) then
    begin
      AnsiSequenceLookup.AddOrSetValue(UniCtx + Modifier, E);
      AddReverseCandidate(AnsiCtx, UniCtx);
    end;
    if not OverwritesToggle(AnsiCtx + Modifier) then
      AnsiSequenceLookup.AddOrSetValue(AnsiCtx + Modifier, E);
  end;

  // Register a rule anchored on a pre-converted ANSI member (RaPhalaGroups).
  // These mappings describe a kar rendered AFTER an already-present glyph,
  // so they are strictly append-only (EraseCount = 0).
  procedure RegAnsi(const AnsiCtx, Modifier, ValRaw, AltRaw: string; IsToggle: Boolean);
  var
    E, Existing: TAnsiSequenceEntry;
    OutVal: string;
  begin
    OutVal := ResolveValue(ValRaw);
    if (AnsiCtx = '') or (OutVal = '') then
      Exit;

    E.AnsiOutput := OutVal;
    E.EraseCount := 0;
    E.IsToggleEntry := IsToggle;
    if IsToggle then
      E.AltAnsiOutput := ResolveValue(AltRaw)
    else
      E.AltAnsiOutput := '';

    if AnsiSequenceLookup.TryGetValue(AnsiCtx + Modifier, Existing) and Existing.IsToggleEntry and (not IsToggle) then
      Exit; // never downgrade a toggle-capable entry
    AnsiSequenceLookup.AddOrSetValue(AnsiCtx + Modifier, E);
  end;

begin
  if AnsiToUniMap = nil then
    AnsiToUniMap := TAnsiToUniMap.Create
  else
    AnsiToUniMap.Clear;

  if AnsiSequenceLookup <> nil then
    AnsiSequenceLookup.Clear
  else
    AnsiSequenceLookup := TAnsiSequenceMap.Create;

  TempBijoy := TUnicodeToBijoy2000.Create;
  try
    { === 1. Ra-Phala Rules (modifier = hasanta + ra) === }
    if Length(RfolaRules) > 0 then
      for I := 0 to High(RfolaRules) do
      begin
        Rule := RfolaRules[I];
        if Rule.Consonants = '' then
          Continue;

        GroupMembers := nil;
        if ConsonantGroupMap <> nil then
          ConsonantGroupMap.TryGetValue(Rule.Consonants, GroupMembers);
        if GroupMembers <> nil then
          for Member in GroupMembers do
            RegUni(Member, string(b_Hasanta) + string(b_r), '', False);

        GroupMembers := nil;
        if AnsiGroupMap <> nil then
          AnsiGroupMap.TryGetValue(Rule.Consonants, GroupMembers);
        if GroupMembers <> nil then
          for Member in GroupMembers do
            RegAnsi(Member, string(b_Hasanta) + string(b_r), Rule.Value, '', False);

        if (GroupMembers = nil) and (Length(Rule.Consonants) = 1) and (Ord(Rule.Consonants[1]) >= $0980) then
          RegUni(Rule.Consonants, string(b_Hasanta) + string(b_r), '', False);
      end;

    { === 2. Vowel Kar Rules === }
    if Length(VowelRules) > 0 then
      for I := 0 to High(VowelRules) do
      begin
        VRule := VowelRules[I];
        if VRule.KarChar = '' then
          Continue;
        for J := 0 to High(VRule.Mappings) do
        begin
          Mapping := VRule.Mappings[J];
          if Mapping.Consonants = '' then
            Continue;

          GroupMembers := nil;
          if ConsonantGroupMap <> nil then
            ConsonantGroupMap.TryGetValue(Mapping.Consonants, GroupMembers);
          if GroupMembers <> nil then
            for Member in GroupMembers do
              RegUni(Member, VRule.KarChar, Mapping.Alt, Mapping.ToggleOnBackspace);

          GroupMembers := nil;
          if AnsiGroupMap <> nil then
            AnsiGroupMap.TryGetValue(Mapping.Consonants, GroupMembers);
          if GroupMembers <> nil then
            for Member in GroupMembers do
              RegAnsi(Member, VRule.KarChar, Mapping.Value, Mapping.Alt, Mapping.ToggleOnBackspace);

          // Literal single-consonant mapping (no group)
          if (ConsonantGroupMap = nil) or not ConsonantGroupMap.ContainsKey(Mapping.Consonants) then
            if ((AnsiGroupMap = nil) or not AnsiGroupMap.ContainsKey(Mapping.Consonants)) and
              (Length(Mapping.Consonants) = 1) and (Ord(Mapping.Consonants[1]) >= $0980) then
              RegUni(Mapping.Consonants, VRule.KarChar, Mapping.Alt, Mapping.ToggleOnBackspace);
        end;
      end;

    { === 3. Full Forms (Unicode conjunct -> ANSI) === }
    if Length(ActiveReplacements) > 0 then
      for I := 0 to High(ActiveReplacements) do
        if (ActiveReplacements[I].Key <> '') and (ActiveReplacements[I].Value <> '') then
          RegUni(ActiveReplacements[I].Key, '', '', False);

    if Length(KarInclusiveReplacements) > 0 then
      for I := 0 to High(KarInclusiveReplacements) do
        if (KarInclusiveReplacements[I].Key <> '') and (KarInclusiveReplacements[I].Value <> '') then
          RegUni(KarInclusiveReplacements[I].Key, '', '', False);

  finally
    TempBijoy.Free;
  end;
end;

end.
