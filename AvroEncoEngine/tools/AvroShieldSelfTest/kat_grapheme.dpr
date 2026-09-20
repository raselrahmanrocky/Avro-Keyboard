{

  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================

  kat_grapheme - head-less gate for the universal ANSI backspace width.

  ONE press of Backspace must erase ONE visible character - a letter, a kar, a
  conjunct, a reph cluster - for EVERY ANSI mapping the engine can load, the
  way Unicode deletes one grapheme cluster. This program proves G1 rows 1..7
  against the real mappings in a real container folder, without a GUI.

  How it drives the engine
  ------------------------
  Every ANSI engine keeps a ledger of the text it committed to the host
  (CommittedBanglaT): the screen behind the caret IS Convert(CommittedBanglaT).
  The harness
    1. loads each mapping through the shipping path (AnsiMappingDir +
       ScanAvroEncoFiles + TAnsiEngineManager.SwitchEngine - the same the app
       uses, so containers are decrypted exactly as at run time),
    2. seeds the ledger with a word (SeedCommittedForTest - the state a typed
       word leaves behind: nothing live, the caret right behind the text),
    3. substitutes the host with OnRawEmit, so every erase/type the engine
       would inject is captured as (EraseCount, Text) instead of being sent,
    4. calls BackspaceForTest (the backspace path itself, so no main form, no
       keyboard layout and no hook are needed),
  and checks, after every single press:
    A. the surviving ledger equals the expected text. The expectations below
       are the hand-derived UAX#29 answer, written independently of the code
       under test - this is the oracle.
    B. the press was consumed (Block = True), so the host's own single
       character backspace never ran behind our back.
    C. what reached the host is the mapping's own smallest ANSI diff: the
       erase count must equal the mismatched tail of Convert(before) and the
       typed text must complete Convert(after). Convert comes from the engine's
       OWN converter (ConverterForTest), because a second instance could carry
       different toggle state.
    D. once the ledger is empty the next press is handed back to the host
       (Block = False, nothing emitted) - the "never over-delete" invariant.

  Bengali literals are written as #$XXXX so this file stays pure ASCII.

  G1 rows covered here: 1 (single letters and the reported I+space case),
  2 (multi-unit letters), 3 (conjuncts typed with hasanta), 4 (base + kar),
  5 (bangla = 2 presses), 6 (songsod = 3 presses), 7 (reph: one press by
  default, the pre-existing two-press behaviour under AnsiBackspaceLegacy),
  8 (delimiters and commit points), 9 (repeated presses over one reading),
  10 (caret moves: the ledger and the reading go stale), 11 (host characters
  between the caret and the ledger - Modern engine only), 12 (the mapping's own
  atom table), 13 (the host-text eraser over the cached reading) and 14 (English
  mode: the press stays the host's, and a layout / mode switch takes the ledger
  and the reading with it). The hook/host layers themselves (the OS hook's own
  delivery, the UIA and clipboard reading layers) still need a real desktop.

  Usage: kat_grapheme <mapping-dir> [quiet] [trace]
  Exit code: 0 all PASS, 1 FAIL.
}

{$APPTYPE CONSOLE}
program kat_grapheme;

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Generics.Collections,
  uRegistrySettings,
  uAvroEncoManager,
  uAnsiEngineManager,
  clsUnicodeToBijoy2000,
  BanglaChars,
  clsAnsiGrapheme,
  clsAnsiAtomMap,
  clsLayout,
  clsGenericLayoutModern,
  clsGenericLayoutOld,
  clsE2BCharBased,
  uCaretContextCache,
  uCaretContextSniffer,
  uCaretWatch,
  uAnsiBackspace;

type
  TEngineKind = (ekModern, ekOld, ekE2B);

  { One ledger state and the ledgers it must become, press by press. The last
    expectation is always the empty string: a word of N clusters costs exactly
    N presses. }
  TCase = record
    Row:     Integer;
    Name:    string;
    Ledger:  string;
    Legacy:  Boolean;
    Pending: Integer; // host characters between the caret and the ledger (unmapped keys)
    Expects: TArray<string>;
  end;

  { Stands in for the host: captures what the engine would have injected. }
  TRecorder = class
  public
    EraseCount: Integer;
    Text:       string;
    Emits:      Integer;
    procedure Reset;
    procedure Sink(const AEraseCount: Integer; const AText: string);
  end;

  { Stands in for a caret-context READING LAYER (uCaretContextSniffer in the
    app, UI Automation later): a canned reading plus a canned fingerprint, so
    the provider -> cache -> decision chain runs with no window, no caret and
    no clipboard. }
  TFakeCaretReader = class
  public
    Tail:            string;
    Fingerprint:     TCaretFingerprint;
    Now:             TCaretFingerprint; // what a fresh fingerprint read returns
    Calls:           Integer;
    function Provide(const AMaxChars: Integer): TAnsiContextReading;
    function Current: TCaretFingerprint;
  end;

  { Records the last host-erase decision so a case can assert the REASON and
    not only the outcome. A method, because that is what the engine-side trace
    hook takes (a class may want to log its own decisions too). }
  TTraceSink = class
  public
    procedure Backspace(const AMapping: string; const AUnits: Integer; const ADecision: TAnsiEraseDecision;
      const AReason: string);
  end;

const
  { Rows 1..7 are the backspace widths. Rows 8..11 are the layers that surround
    them, all proven head-lessly by GateLayerChecks: the delimiters that commit
    a word, repeated presses over one reading, the caret moves that make the
    ledger and the reading stale, and the host characters that sit between the
    caret and the ledger. The mapping-derived atom table (chunk 3), the
    host-text gate (chunk 4) and English mode are reported under their own
    names. }
  MAX_ROW     = 14;
  DELIM_ROW   = 8;  // delimiters and commit points
  REPEAT_ROW  = 9;  // repeated presses: one reading, one erase, then the host
  CARET_ROW   = 10; // the caret moved: the ledger and the reading go stale
  PENDING_ROW = 11; // host characters between the caret and the ledger
  ATOM_ROW    = 12;
  HOST_ROW    = 13;
  ENGLISH_ROW = 14; // English mode: the host keeps the press

  { Representative SINGLE clusters: every shape one press has to erase - a plain
    letter, the letters whose rendering is several ANSI units, conjuncts typed
    with hasanta, a base with a kar (including a pre-base one), the anusvara, a
    reph and a joiner form. Multi-cluster words are not here: they belong to the
    erase plan below, which counts how many presses a whole word costs. }
  PROBE_CLUSTERS: array [0 .. 11] of string = (#$0995, #$0987, #$0989, #$0995#$09CD#$0995, #$0995#$09CD#$09B7, #$09A3#$09CD#$099F,
    #$09A8#$09CD#$09A4#$09CD#$09B0, #$0995#$09BF, #$0995#$09BE, #$09AC#$09BE#$0982, #$09B0#$09CD#$0995, #$0995#$200D#$09CD#$09B7);

  PROBE_NAMES: array [0 .. 11] of string = ('ka', 'i', 'u', 'kka', 'kkha', 'ntta', 'ntra', 'ki', 'kaa', 'bang', 'rka', 'ZWJ form');

  { Multi-cluster words for the erase plan: how many presses a word really
    costs, and whether any single press ever erased two of its clusters. }
  PLAN_WORDS: array [0 .. 4] of string = (#$09AC#$09BE#$0982#$09B2#$09BE, #$09B8#$0982#$09B8#$09A6, #$09AC#$09BE#$0982#$09B2#$09BE' '#$09B8#$0982,
    #$0995#$09CD#$0995' '#$0995#$09BF, #$09B0#$09CD#$0995);

  PLAN_NAMES: array [0 .. 4] of string = ('bangla (2)', 'songsod (3)', 'bangla + sang (4)', 'kka + ki (2)', 'rka (1)');

var
  Fails:     Integer;
  Checks:    Integer;
  Skipped:   Integer;
  FQuiet:    Boolean;
  FTrace:    Boolean;
  RowFails:  array [1 .. MAX_ROW] of Integer;
  RowChecks: array [1 .. MAX_ROW] of Integer;
  Cases:     TArray<TCase>;
  CaseCount: Integer;
  Recorder:  TRecorder;
  Modern:    TGenericLayoutModern;
  Old:       TGenericLayoutOld;
  CharBased: TE2BCharBased;

  // the last host-erase decision, as uAnsiBackspace reported it
  TraceUnits:    Integer;
  TraceDecision: TAnsiEraseDecision;
  TraceText:     string;
  TraceCalls:    Integer; // how often the decision point ran at all (English mode: never)

  // the caret watch's own counters
  WatchEvents:    Integer;
  WatchRefreshes: Integer;
  BaseRefreshes:  Integer;
  BaseEvents:     Integer;

{ ============================================================================== }
{ reporting                                                                      }
{ ============================================================================== }

procedure Say(const AText: string);
begin
  if not FQuiet then
    WriteLn(AText);
end;

{ Step-by-step trace of the harness itself (never of the engine), so a crash
  inside one of the four calls a case makes can be located exactly. }
procedure Trace(const AText: string);
begin
  if FTrace then
    WriteLn('TRACE ' + AText);
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

procedure Check(const ARow: Integer; const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  Inc(RowChecks[ARow]);
  if ACond then
  begin
    Say('  ok   ' + AWhat);
    Exit;
  end;

  Inc(Fails);
  Inc(RowFails[ARow]);
  WriteLn('FAIL [G1 row ' + IntToStr(ARow) + '] ' + AWhat);
  if ADetail <> '' then
    WriteLn('       ' + ADetail);
end;

procedure TRecorder.Reset;
begin
  EraseCount := 0;
  Text := '';
  Emits := 0;
end;

procedure TRecorder.Sink(const AEraseCount: Integer; const AText: string);
begin
  EraseCount := AEraseCount;
  Text := AText;
  Inc(Emits);
end;

function TFakeCaretReader.Provide(const AMaxChars: Integer): TAnsiContextReading;
var
  N: Integer;
begin
  Inc(Calls);
  Result.Ok := Tail <> '';
  Result.Source := csInjected;
  Result.Fingerprint := Fingerprint;

  // a reading layer returns the text IMMEDIATELY before the caret: the last
  // characters of what it can see, never the first ones
  N := Length(Tail);
  if (AMaxChars > 0) and (N > AMaxChars) then
    N := AMaxChars;
  Result.Tail := Copy(Tail, Length(Tail) - N + 1, N);
end;

function TFakeCaretReader.Current: TCaretFingerprint;
begin
  Result := Now;
end;

procedure TTraceSink.Backspace(const AMapping: string; const AUnits: Integer; const ADecision: TAnsiEraseDecision;
  const AReason: string);
begin
  Inc(TraceCalls);
  TraceUnits := AUnits;
  TraceDecision := ADecision;
  TraceText := Format('%s: %d units, %s (%s)', [AMapping, AUnits, AnsiDecisionName(ADecision), AReason]);
end;

{ ============================================================================== }
{ the expectation oracle: the engine's own conversion, minus the matched prefix  }
{ ============================================================================== }

{ The same cluster with its joiners and hasanta removed: a mapping may render
  "ka ZWJ hasanta ssa" exactly like "ka ssa", in which case the ANSI text alone
  cannot tell the two apart and no table can decide the width from it. }
function WithoutJoiners(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C = ZWJ) or (C = ZWNJ) or (C = #$09CD) then
      Continue;
    Result := Result + C;
  end;
end;

function CommonPrefixLen(const A, B: string): Integer;
begin
  Result := 0;
  while (Result < Length(A)) and (Result < Length(B)) and (A[Result + 1] = B[Result + 1]) do
    Inc(Result);
end;

{ The smallest edit that turns PrevAnsi into NewAnsi: erase the mismatched
  tail, then type the remainder. This is the rule the engines document and use
  (SendAnsiDiff / CommonPrefixLen + RawSend), computed here from Convert alone
  so the expectation never comes from the backspace code under test. }
procedure ExpectedDiff(const AConverter: TUnicodeToBijoy2000; const APrev, ANew: string; out AErase: Integer; out AText: string);
var
  PrevAnsi, NewAnsi: string;
  Matched:           Integer;
begin
  PrevAnsi := AConverter.Convert(APrev);
  NewAnsi := AConverter.Convert(ANew);
  Matched := CommonPrefixLen(PrevAnsi, NewAnsi);

  AErase := Length(PrevAnsi) - Matched;
  AText := Copy(NewAnsi, Matched + 1, MaxInt);
end;

{ ============================================================================== }
{ case table: the hand-derived UAX#29 answers, independent of the code under test}
{ ============================================================================== }

{ As AddCase, with the pending-host-characters count the commit point leaves
  behind (an unmapped key typed after the word). The pending presses go to the
  HOST first and only then does the word itself go, cluster by cluster. }
procedure AddCaseEx(const ARow: Integer; const AName, ALedger: string; const APending: Integer;
  const AExpects: array of string);
var
  I: Integer;
begin
  SetLength(Cases, CaseCount + 1);
  Cases[CaseCount].Row := ARow;
  Cases[CaseCount].Name := AName;
  Cases[CaseCount].Ledger := ALedger;
  Cases[CaseCount].Legacy := False;
  Cases[CaseCount].Pending := APending;
  SetLength(Cases[CaseCount].Expects, Length(AExpects));
  for I := 0 to High(AExpects) do
    Cases[CaseCount].Expects[I] := AExpects[I];
  Inc(CaseCount);
end;

procedure AddCase(const ARow: Integer; const AName, ALedger: string; const AExpects: array of string);
begin
  AddCaseEx(ARow, AName, ALedger, 0, AExpects);
end;

procedure AddLegacyCase(const ARow: Integer; const AName, ALedger: string; const AExpects: array of string);
begin
  AddCase(ARow, AName + ' [legacy]', ALedger, AExpects);
  Cases[CaseCount - 1].Legacy := True;
end;

procedure BuildCases;
begin
  SetLength(Cases, 0);
  CaseCount := 0;

  // ---- row 1: one visible character costs exactly one press -----------------
  AddCase(1, 'ka', #$0995, ['']);
  AddCase(1, 'tta', #$099F, ['']);
  AddCase(1, 'aa', #$0986, ['']);
  AddCase(1, 'chha', #$099B, ['']);
  AddCase(1, 'rra', #$09DC, ['']);
  AddCase(1, 'i (reported bug, alone)', #$0987, ['']);
  // the reported sequence: i, Space, Backspace, Backspace - the space goes
  // first (the host's own press, still in the ledger) and then i in ONE press
  AddCase(1, 'i + trailing space', #$0987' ', [#$0987, '']);

  // ---- row 2: a letter that is SEVERAL ANSI units --------------------------
  AddCase(2, 'u (three ANSI units)', #$0989, ['']);
  AddCase(2, 'u + trailing space', #$0989' ', [#$0989, '']);

  // ---- row 3: conjuncts typed as consonant + hasanta + consonant -----------
  AddCase(3, 'kka (ka+hasanta+ka)', #$0995#$09CD#$0995, ['']);
  AddCase(3, 'kkha (ka+hasanta+ssa)', #$0995#$09CD#$09B7, ['']);
  AddCase(3, 'ntta (nna+hasanta+tta)', #$09A3#$09CD#$099F, ['']);
  AddCase(3, 'kra (ka+hasanta+ra)', #$0995#$09CD#$09B0, ['']);
  AddCase(3, 'ntra (na+hasanta+ta+hasanta+ra)', #$09A8#$09CD#$09A4#$09CD#$09B0, ['']);
  AddCase(3, 'ssna (ssa+hasanta+nna)', #$09B7#$09CD#$09A3, ['']);
  AddCase(3, 'ZWJ + hasanta + ssa', #$0995#$200D#$09CD#$09B7, ['']);
  AddCase(3, 'ZWNJ + hasanta + ja', #$0995#$200C#$09CD#$09AF, ['']);
  AddLegacyCase(3, 'ZWJ + hasanta + ssa', #$0995#$200D#$09CD#$09B7, [#$0995, '']);
  AddLegacyCase(3, 'ZWNJ + hasanta + ja', #$0995#$200C#$09CD#$09AF, [#$0995, '']);

  // ---- row 4: base letter + kar - the kar never costs its own press --------
  AddCase(4, 'ki (ka+i-kar)', #$0995#$09BF, ['']);
  AddCase(4, 'kaa (ka+aa-kar)', #$0995#$09BE, ['']);
  AddCase(4, 'ku (ka+u-kar)', #$0995#$09C1, ['']);
  AddCase(4, 'kri (ka+vocalic-r-kar)', #$0995#$09C3, ['']);
  AddCase(4, 'kii (ka+ii-kar)', #$0995#$09C0, ['']);
  AddCase(4, 'ke (ka+e-kar)', #$0995#$09C7, ['']);
  AddCase(4, 'ko (ka+o-kar)', #$0995#$09CB, ['']);
  AddCase(4, 'ki + trailing space', #$0995#$09BF' ', [#$0995#$09BF, '']);

  // ---- row 5: bangla = bang|la -> two presses ------------------------------
  AddCase(5, 'bangla (bang|la)', #$09AC#$09BE#$0982#$09B2#$09BE, [#$09AC#$09BE#$0982, '']);
  AddCase(5, 'bangla + space', #$09AC#$09BE#$0982#$09B2#$09BE' ', [#$09AC#$09BE#$0982#$09B2#$09BE, #$09AC#$09BE#$0982, '']);

  // ---- row 6: songsod = song|so|do -> three presses -----------------------
  AddCase(6, 'songsod (song|so|do)', #$09B8#$0982#$09B8#$09A6, [#$09B8#$0982#$09B8, #$09B8#$0982, '']);
  AddCase(6, 'two words', #$09AC#$09BE#$0982#$09B2#$09BE' '#$09B8#$0982, [#$09AC#$09BE#$0982#$09B2#$09BE' ', #$09AC#$09BE#$0982#$09B2#$09BE, #$09AC#$09BE#$0982, '']);

  // ---- row 7: reph. Unicode says one cluster, so one press is the default;
  //      the pre-existing "the letter itself survives" stays available ------
  AddCase(7, 'rka (ra+hasanta+ka)', #$09B0#$09CD#$0995, ['']);
  AddCase(7, 'rka + space', #$09B0#$09CD#$0995' ', [#$09B0#$09CD#$0995, '']);
  AddLegacyCase(7, 'rka (ra+hasanta+ka)', #$09B0#$09CD#$0995, [#$0995, '']);
  AddLegacyCase(7, 'word then rka', #$09B0#$09CD#$0995#$0995, [#$09B0#$09CD#$0995, #$0995, '']);

  // ---- row 8 (commit points): the word boundary the press must respect ------
  // A Space KEEPS the word in the ledger (the space goes first, then the word,
  // cluster by cluster); an unmapped key after the word goes to the host first
  // (a pending host character) and only then does the word itself go. Tab and
  // Enter DROP the ledger: what is behind the caret after them is not the text
  // this engine typed, so the word costs its clusters like any other word and
  // the host answers before it. Only the Modern engine tracks pending host
  // characters, so those cases run against it alone.
  AddCase(DELIM_ROW, 'space keeps the word in the ledger', #$0995#$09BF' ', [#$0995#$09BF, '']);
  { The pending press hands the word's TRAILING SPACE to the host too (the
    space is the host's delimiter, and the ledger drops it with the count), so
    the seed is the committed word INCLUDING its space - exactly the state an
    unmapped key typed after "ki " leaves behind. }
  AddCaseEx(DELIM_ROW, 'an unmapped key goes to the host first', #$0995#$09BF' ', 1, [#$0995#$09BF, '']);
  AddCaseEx(DELIM_ROW, 'two unmapped keys go to the host first', #$0995#$09BF' ', 2, [#$0995#$09BF, #$0995#$09BF, '']);
  { The same commit point WITHOUT a space before the unmapped key: the ledger
    holds the word alone, so nothing may be dropped from it while the host's own
    character is still in front of the caret. }
  AddCaseEx(DELIM_ROW, 'an unmapped key with no space yet goes to the host', #$0995#$09BF, 1, [#$0995#$09BF, '']);
  AddCaseEx(DELIM_ROW, 'two unmapped keys with no space then the word', #$0995#$09BF, 2, [#$0995#$09BF, #$0995#$09BF, '']);
end;
{ ============================================================================== }
{ driving one engine                                                             }
{ ============================================================================== }

procedure SeedEngine(const AKind: TEngineKind; const AText: string; const APending: Integer = 0);
begin
  case AKind of
    ekModern:
      Modern.SeedCommittedForTest(AText, APending);
    ekOld:
      begin
        { Only the Modern engine tracks pending host characters. }
        if APending > 0 then
          raise Exception.Create('pending host characters are a Modern-only state');
        Old.SeedCommittedForTest(AText);
      end;
    ekE2B:
      begin
        if APending > 0 then
          raise Exception.Create('pending host characters are a Modern-only state');
        CharBased.SeedCommittedForTest(AText);
      end;
  end;
end;

function EngineLedger(const AKind: TEngineKind): string;
begin
  case AKind of
    ekModern: Result := Modern.CommittedForTest;
    ekOld: Result := Old.CommittedForTest;
    ekE2B: Result := CharBased.CommittedForTest;
  end;
end;

function EngineConverter(const AKind: TEngineKind): TUnicodeToBijoy2000;
begin
  case AKind of
    ekModern: Result := Modern.ConverterForTest;
    ekOld: Result := Old.ConverterForTest;
  else
    Result := CharBased.ConverterForTest;
  end;
end;

procedure DriveBackspace(const AKind: TEngineKind; var Block: Boolean);
begin
  case AKind of
    ekModern: Modern.BackspaceForTest(Block);
    ekOld: Old.BackspaceForTest(Block);
    ekE2B: CharBased.BackspaceForTest(Block);
  end;
end;

{ The engine's REAL entry point - the one the low-level hook reaches through
  TLayout.ProcessVKeyDown (clsLayout.pas:184). The keyboard-mode gate lives
  there and not in DoBackspace (clsGenericLayoutModern.pas:616,
  clsGenericLayoutOld.pas:1791, clsE2BCharBased.pas:1605), so a harness that
  only ever calls BackspaceForTest cannot see it: this is that gate's probe. }
procedure DriveKey(const AKind: TEngineKind; const AKey: Integer; var Block: Boolean);
begin
  case AKind of
    ekModern: Modern.ProcessVKeyDown(AKey, Block);
    ekOld: Old.ProcessVKeyDown(AKey, Block);
    ekE2B: CharBased.ProcessVKeyDown(AKey, Block);
  end;
end;

{ Pins one engine's keyboard mode through its own test/embedding hook. The
  engines read AvroMainForm1 when no override is set and a harness has no main
  form, so with the override OFF every engine answers as English (SysDefault) -
  which is exactly the production fallback for a nil form. }
procedure SetEngineMode(const AKind: TEngineKind; const AEnglish: Boolean);
var
  Mode: Integer;
begin
  if AEnglish then
    Mode := Ord(SysDefault)
  else
    Mode := Ord(bangla);

  case AKind of
    ekModern: Modern.SetKeyboardModeOverride(True, Mode);
    ekOld: Old.SetKeyboardModeOverride(True, Mode);
    ekE2B: CharBased.SetKeyboardModeOverride(True, Mode);
  end;
end;

procedure ClearEngineModes;
begin
  Modern.SetKeyboardModeOverride(False, Ord(SysDefault));
  Old.SetKeyboardModeOverride(False, Ord(SysDefault));
  CharBased.SetKeyboardModeOverride(False, Ord(SysDefault));
end;

procedure RunCases(const AMapping, AEngineName: string; const AKind: TEngineKind);
var
  I, P:      Integer;
  C:         TCase;
  Before, After, Expected: string;
  WantErase: Integer;
  WantText:  string;
  Block:     Boolean;
  What:      string;
  Detail:    string;
begin
  Say(Format('=== %s / %s: %d cases', [AMapping, AEngineName, CaseCount]));

  for I := 0 to CaseCount - 1 do
  begin
    C := Cases[I];
    Trace(Format('%s/%s case %d %s legacy=%s', [AMapping, AEngineName, I, C.Name, BoolToStr(C.Legacy, True)]));

    { Pending host characters are a Modern-only state (the old-style engines
      keep no such count): that case is exercised against the Modern engine
      only. }
    if (C.Pending > 0) and (AKind <> ekModern) then
      Continue;

    AnsiBackspaceLegacy := IfThen(C.Legacy, 'YES', 'NO');

    Trace('  seed');
    SeedEngine(AKind, C.Ledger, C.Pending);

    for P := 0 to High(C.Expects) do
    begin
      Trace(Format('  press %d: read ledger', [P + 1]));
      Before := EngineLedger(AKind);
      Expected := C.Expects[P];

      Trace('  press ' + IntToStr(P + 1) + ': expected diff');
      ExpectedDiff(EngineConverter(AKind), Before, Expected, WantErase, WantText);

      Recorder.Reset;
      Block := False;
      Trace('  press ' + IntToStr(P + 1) + ': drive backspace');
      DriveBackspace(AKind, Block);
      Trace('  press ' + IntToStr(P + 1) + ': read ledger back');
      After := EngineLedger(AKind);
      Trace('  press ' + IntToStr(P + 1) + ': checks');

      What := Format('%s %s %s press %d', [AMapping, AEngineName, C.Name, P + 1]);

      if P < C.Pending then
      begin
        { A pending host character: the press goes to the host untouched. The
          ledger is NOT touched by it, except that a trailing space belongs to
          the host's delimiter and goes with the count. }
        Detail := Format('Block=%s emits=%d ledger [%s] (was [%s]): a pending host character must be the host''s press',
          [BoolToStr(Block, True), Recorder.Emits, HexUnits(After), HexUnits(Before)]);
        Check(C.Row, What + ' goes to the host', (not Block) and (Recorder.Emits = 0) and
          ((After = Before) or ((Length(Before) > 0) and (After = LeftStr(Before, Length(Before) - 1)) and (Before[Length(Before)] = ' '))),
          Detail);
        Continue;
      end;

      // A. the surviving ledger is the expected one
      Detail := Format('ledger [%s] -> [%s], want [%s]', [HexUnits(Before), HexUnits(After), HexUnits(Expected)]);
      Check(C.Row, What + ' ledger', After = Expected, Detail);

      // B. the press was consumed - the host never ran its own backspace
      Check(C.Row, What + ' blocked', Block, 'Block = False: the press went to the host, so the width is the host''s, not ours');

      // C. the erase width is the mapping's own smallest diff
      Detail := Format('host got erase=%d text=[%s] (emits=%d), want erase=%d text=[%s]', [Recorder.EraseCount, HexUnits(Recorder.Text),
        Recorder.Emits, WantErase, HexUnits(WantText)]);
      Check(C.Row, What + ' erase width', (Recorder.EraseCount = WantErase) and (Recorder.Text = WantText), Detail);
      Check(C.Row, What + ' single emission', Recorder.Emits <= 1, Format('emits=%d', [Recorder.Emits]));

      // the screen really lands on Convert(after)
      Detail := 'erase+type does not reproduce Convert(after)';
      Check(C.Row, What + ' screen lands right', Copy(EngineConverter(AKind).Convert(Before), 1, Length(EngineConverter(AKind).Convert(Before)) - Recorder.EraseCount) +
        Recorder.Text = EngineConverter(AKind).Convert(After), Detail);
    end;

    // D. the empty ledger hands the next press back to the host untouched
    Recorder.Reset;
    Block := True;
    Trace('  after empty: drive backspace');
    DriveBackspace(AKind, Block);
    What := Format('%s %s %s after empty', [AMapping, AEngineName, C.Name]);
    Check(C.Row, What + ' hands over', (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d: an empty ledger must not erase anything', [BoolToStr(Block, True), Recorder.Emits]));
  end;
end;

{ ============================================================================== }
{ the unit itself (no mapping): the rules the engines rely on                    }
{ ============================================================================== }

procedure CheckDrop(const AText, AWant: string; const ARephSurvives: Boolean);
var
  Got:      string;
  Removed:  Boolean;
  Label1:   string;
begin
  Removed := DropLastGraphemeCluster(AText, Got, ARephSurvives);
  Label1 := Format('clsAnsiGrapheme: drop [%s] legacy=%s -> [%s]', [HexUnits(AText), BoolToStr(ARephSurvives, True), HexUnits(Got)]);
  Check(1, Label1, Removed and (Got = AWant), Format('got [%s], want [%s]', [HexUnits(Got), HexUnits(AWant)]));
end;

procedure UnitLevelChecks;
var
  Count: Integer;
  Empty: string;
begin
  Say('');
  Say('--- clsAnsiGrapheme (pure rules, no mapping)');

  Count := GraphemeClusterCount(#$0995);
  Check(1, 'clsAnsiGrapheme: ka is one cluster', Count = 1, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$0995#$09CD#$0995);
  Check(3, 'clsAnsiGrapheme: ka+hasanta+ka is one cluster', Count = 1, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$0995#$09BF);
  Check(4, 'clsAnsiGrapheme: ka+i-kar is one cluster', Count = 1, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$09AC#$09BE#$0982#$09B2#$09BE);
  Check(5, 'clsAnsiGrapheme: bangla is two clusters', Count = 2, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$09B8#$0982#$09B8#$09A6);
  Check(6, 'clsAnsiGrapheme: songsod is three clusters', Count = 3, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$09B0#$09CD#$0995);
  Check(7, 'clsAnsiGrapheme: rka is one cluster', Count = 1, Format('count=%d', [Count]));

  Count := GraphemeClusterCount(#$0987' ');
  Check(1, 'clsAnsiGrapheme: i + space is two clusters', Count = 2, Format('count=%d', [Count]));

  CheckDrop(#$0995, '', False);
  CheckDrop(#$0987, '', False);
  CheckDrop(#$0995#$09CD#$0995, '', False);
  CheckDrop(#$0995#$09BF, '', False);
  CheckDrop(#$09AC#$09BE#$0982#$09B2#$09BE, #$09AC#$09BE#$0982, False);
  CheckDrop(#$09B8#$0982#$09B8#$09A6, #$09B8#$0982#$09B8, False);
  CheckDrop(#$09B0#$09CD#$0995, '', False);
  CheckDrop(#$09B0#$09CD#$0995, #$0995, True);
  CheckDrop(#$0995#$200D#$09CD#$09B7, '', False);
  CheckDrop(#$0995#$200D#$09CD#$09B7, #$0995, True);

  // nothing is ever removed when there is nothing to remove
  Empty := 'sentinel';
  Check(1, 'clsAnsiGrapheme: empty string is not a drop',
    (not DropLastGraphemeCluster('', Empty, False)) and (Empty = ''), 'an empty ledger must report False and leave NewS empty');
end;

{ ============================================================================== }
{ chunk 3: the mapping-derived atom table (Source 2)                            }
{ ============================================================================== }

{
  Gates for the ANSI atom table (clsAnsiAtomMap) of the ACTIVE mapping.

  The table answers the question the engines' committed ledger cannot: how wide
  is the last visible character when the text in front of the caret was not
  typed by us (a mouse click, an arrow key, another application, text from
  before Avro). Every property below is checked against the mapping's OWN
  Convert, so no expectation here is baked into the harness.
}
procedure AtomMapChecks(const AMapping: string);
var
  Map:     TAnsiAtomMap;
  Atoms:   TArray<TAnsiAtom>;
  Conv:    TUnicodeToBijoy2000;
  I, W:    Integer;
  Ans:     string;
  Bad:     string;
  BadCount, NoUni, OneUni: Integer;
  NoUniBad:                Integer;
  NoUniSample:             string;
  Cand:                    TAnsiUniCandidates;
  RevChecks, N:            Integer;
  Found:                   Boolean;
  Presses, Clusters:       Integer;
  Over, Stepped:           Boolean;
  R:       TAnsiRole;
  Counts:  array [TAnsiRole] of Integer;
  Ambiguous:       Integer;
  AmbiguousSample: string;
  TailAtom, PrevAtom: TAnsiAtom;
  Reduced: string;

  { The candidate clusters of one rendering, as hex, so a failure names exactly
    which pair the two tables disagree about. }
  function CandText(const ACand: TAnsiUniCandidates): string;
  var
    K: Integer;
  begin
    Result := '';
    for K := 0 to high(ACand) do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + HexUnits(ACand[K]);
    end;
  end;

begin
  Map := AnsiAtomMap;
  Conv := Modern.ConverterForTest;

  Say('');
  if Map = nil then
  begin
    Say('=== ' + AMapping + ' / atom map: MISSING');
    Check(ATOM_ROW, AMapping + ': the atom table was compiled with the mapping', False, 'AnsiAtomMap is nil although a mapping is active');
    Exit;
  end;

  Atoms := Map.Atoms;
  Say(Format('=== %s / atom map: %d atoms, %d role conflicts', [AMapping, Map.Count, Length(Map.Conflicts)]));
  for I := 0 to high(Map.Conflicts) do
    Say('    conflict: ' + Map.Conflicts[I]);

  Check(ATOM_ROW, Format('%s: the table covers the mapping (%d atoms)', [AMapping, Length(Atoms)]), Length(Atoms) >= 100,
    Format('only %d atoms', [Length(Atoms)]));

  // ---- every atom is a bounded run, and its role and bind agree -----------
  Bad := '';
  BadCount := 0;
  for I := 0 to high(Atoms) do
  begin
    if (Length(Atoms[I].Units) < 1) or (Length(Atoms[I].Units) > MAX_ATOM_UNITS) then
    begin
      Inc(BadCount);
      if Bad = '' then
        Bad := Format('[%s] is %d units', [HexUnits(Atoms[I].Units), Length(Atoms[I].Units)]);
    end;
    if not IsLegalRoleBind(Atoms[I].Role, Atoms[I].Bind) then
    begin
      Inc(BadCount);
      if Bad = '' then
        Bad := Format('[%s] role %s with bind %s', [HexUnits(Atoms[I].Units), RoleName(Atoms[I].Role), BindName(Atoms[I].Bind)]);
    end;
  end;
  Check(ATOM_ROW, AMapping + ': every atom is a bounded run of units with a matching bind', BadCount = 0,
    Format('%d bad atoms, first: %s', [BadCount, Bad]));

  // ---- a glyph the mapping calls one cluster is ONE press -----------------
  Bad := '';
  BadCount := 0;
  NoUni := 0;
  OneUni := 0;
  Ambiguous := 0;
  AmbiguousSample := '';
  for I := 0 to high(Atoms) do
  begin
    if Atoms[I].Uni = '' then
    begin
      Inc(NoUni);
      Continue;
    end;
    Inc(OneUni);

    // A FRAGMENT is not a cluster: a reph constant's Unicode source is
    // "hasanta + ra", which only becomes one character in front of the
    // consonant it rides on (that is exactly what its forward bind says).
    // Only real clusters are held to the one-cluster rule.
    if IsLinkerPoint(FirstBengaliCodePoint(Atoms[I].Uni)) then
      Continue;

    if GraphemeClusterCount(Atoms[I].Uni) <> 1 then
    begin
      // The mapping's own metadata names more than one character for a glyph it
      // draws as one. That is the mapping format's ambiguity (the same glyph
      // covers several letters in that font), exactly the case the reference
      // notes say to REPORT rather than gate - so it is counted, named once,
      // and the atom stays (it is one glyph on screen).
      Inc(Ambiguous);
      if AmbiguousSample = '' then
        AmbiguousSample := Format('[%s] names %s (%d clusters)', [HexUnits(Atoms[I].Units), HexUnits(Atoms[I].Uni),
          GraphemeClusterCount(Atoms[I].Uni)]);
      Continue;
    end;

    W := AnsiTailClusterUnits(Atoms[I].Units);
    if W <> Length(Atoms[I].Units) then
    begin
      Inc(BadCount);
      if Bad = '' then
        Bad := Format('[%s] is %d units but one press erases %d', [HexUnits(Atoms[I].Units), Length(Atoms[I].Units), W]);
    end;
  end;
  Say(Format('    atoms with a Unicode source: %d, without: %d', [OneUni, NoUni]));

  // ---- the reverse table knows every pair the atom table knows -----------
  // Both tables are compiled from the same globals, so anything the atom table
  // can name must be a candidate of the reverse table: a disagreement means the
  // sniffer (which reads the reverse side) would see a different mapping than
  // the backspace path does.
  Bad := '';
  BadCount := 0;
  RevChecks := 0;
  for I := 0 to high(Atoms) do
  begin
    if (Atoms[I].Uni = '') or (Atoms[I].Units = '') then
      Continue;
    Inc(RevChecks);
    Cand := Conv.UnicodeCandidatesOfAnsi(Atoms[I].Units);
    Found := False;
    for N := 0 to high(Cand) do
      if Cand[N] = Atoms[I].Uni then
      begin
        Found := True;
        Break;
      end;
    if not Found then
    begin
      Inc(BadCount);
      if Bad = '' then
        Bad := Format('[%s] (%s) is not a candidate of [%s] (candidates: %s)', [HexUnits(Atoms[I].Uni), Atoms[I].Src, HexUnits(Atoms[I].Units),
          CandText(Cand)]);
    end;
  end;
  Check(ATOM_ROW, Format('%s: the reverse table knows every pair the atom table knows (%d pairs)', [AMapping, RevChecks]), BadCount = 0,
    Format('%d missing, first: %s', [BadCount, Bad]));

  // ---- atoms the mapping gives no Unicode source --------------------------
  // They are still real glyphs on screen (a repair table, a symbol), so the
  // hard invariant applies to them too: the width lookup may never claim MORE
  // units than the glyph occupies, or one press would eat the glyph beside it.
  // Whether such an atom is rediscovered WHOLE (its own length) is reported
  // rather than gated: an atom that loses that race under-deletes by design.
  Bad := '';
  BadCount := 0;
  NoUniBad := 0;
  NoUniSample := '';
  for I := 0 to high(Atoms) do
    if Atoms[I].Uni = '' then
    begin
      W := AnsiTailClusterUnits(Atoms[I].Units);
      if (W < 1) or (W > Length(Atoms[I].Units)) then
      begin
        Inc(BadCount);
        if Bad = '' then
          Bad := Format('[%s] is %d units but one press erases %d', [HexUnits(Atoms[I].Units), Length(Atoms[I].Units), W]);
      end
      else if W <> Length(Atoms[I].Units) then
      begin
        Inc(NoUniBad);
        if NoUniSample = '' then
          NoUniSample := Format('[%s] is %d units, one press erases %d', [HexUnits(Atoms[I].Units), Length(Atoms[I].Units), W]);
      end;
    end;
  Check(ATOM_ROW, Format('%s: no atom claims more units than it occupies (%d without a source)', [AMapping, NoUni]), BadCount = 0,
    Format('%d bad atoms, first: %s', [BadCount, Bad]));
  if NoUniBad > 0 then
    Say(Format('    note: %d of %d atoms without a Unicode source are not rediscovered whole at their own tail (under-delete, not gated), first: %s',
      [NoUniBad, NoUni, NoUniSample]));
  if Ambiguous > 0 then
    Say(Format('    note: %d atoms name more than one character for one glyph (mapping metadata ambiguity, not gated), first: %s',
      [Ambiguous, AmbiguousSample]));
  Check(ATOM_ROW, Format('%s: every atom with a Unicode source is one cluster and one press (%d atoms)', [AMapping, OneUni]), BadCount = 0,
    Format('%d bad atoms, first: %s', [BadCount, Bad]));

  // ---- the table agrees with Convert: one cluster renders as one cluster ---
  BadCount := 0;
  for I := 0 to high(PROBE_CLUSTERS) do
  begin
    Ans := Conv.Convert(PROBE_CLUSTERS[I]);
    if Ans = '' then
      Continue;
    W := AnsiTailClusterUnits(Ans);
    if W <> Length(Ans) then
    begin
      // A joiner form can be INDISTINGUISHABLE in ANSI: when the mapping draws
      // "ka ZWJ hasanta ssa" exactly like "ka ssa", no reader of the glyph
      // stream can tell them apart, so the width is reported and not gated.
      Reduced := WithoutJoiners(PROBE_CLUSTERS[I]);
      if (Reduced <> PROBE_CLUSTERS[I]) and (Conv.Convert(Reduced) = Ans) then
      begin
        WriteLn(Format('       probe %s renders exactly like %s - not decidable from ANSI text (reported, not gated)',
          [PROBE_NAMES[I], HexUnits(Reduced)]));
        Continue;
      end;

      Inc(BadCount);
      // name EVERY offender: the first one alone hides how the mapping renders
      // the rest, and each shape has its own reason
      // written even in quiet mode: this is the detail of a FAILURE
      WriteLn(Format('       probe %s renders [%s] = %d units but one press erases %d', [PROBE_NAMES[I], HexUnits(Ans), Length(Ans), W]));
      if Map.MatchEndingAt(Ans, Length(Ans), TailAtom) then
        WriteLn(Format('         tail atom [%s] %s/%s %s from %s', [HexUnits(TailAtom.Units), RoleName(TailAtom.Role),
          BindName(TailAtom.Bind), HexUnits(TailAtom.Uni), TailAtom.Src]));
      if Map.MatchEndingAt(Ans, Length(Ans) - W, PrevAtom) then
        WriteLn(Format('         atom before it [%s] %s/%s %s from %s', [HexUnits(PrevAtom.Units), RoleName(PrevAtom.Role),
          BindName(PrevAtom.Bind), HexUnits(PrevAtom.Uni), PrevAtom.Src]))
      else
        WriteLn(Format('         no atom ENDS at unit %d of the rendering', [Length(Ans) - W]));
    end;
  end;
  Check(ATOM_ROW, Format('%s: the rendering of a single cluster is ONE cluster (%d probes)', [AMapping, Length(PROBE_CLUSTERS)]),
    BadCount = 0, Format('%d probes disagree (listed above)', [BadCount]));

  // ---- roles actually present (a missing shape shows up here first) --------
  for R := Low(TAnsiRole) to High(TAnsiRole) do
    Counts[R] := 0;
  for I := 0 to high(Atoms) do
    Inc(Counts[Atoms[I].Role]);
  Say(Format('    roles: base=%d mark=%d joiner=%d half=%d second=%d digit=%d punct=%d unknown=%d', [Counts[arBase], Counts[arMark],
    Counts[arJoiner], Counts[arHalfForm], Counts[arSecondHalf], Counts[arDigit], Counts[arPunct], Counts[arUnknown]]));

  // ---- the erase plan: never two clusters in one press, and how many ----
  for I := 0 to high(PLAN_WORDS) do
  begin
    Ans := Conv.Convert(PLAN_WORDS[I]);
    Presses := 0;
    Over := False;
    Stepped := True;
    while Ans <> '' do
    begin
      W := AnsiTailClusterUnits(Ans);
      if (W < 1) or (W > Length(Ans)) then
      begin
        Over := True;
        Break;
      end;
      Ans := Copy(Ans, 1, Length(Ans) - W);
      Inc(Presses);
      if Presses > 64 then
      begin
        Stepped := False; // the table failed to shrink the text
        Break;
      end;
    end;

    Clusters := GraphemeClusterCount(PLAN_WORDS[I]);
    Check(ATOM_ROW, Format('%s: %s never loses a whole cluster in one press', [AMapping, PLAN_NAMES[I]]),
      (not Over) and Stepped and (Presses >= Clusters),
      Format('%d presses for %d clusters (over=%s, stepped=%s)', [Presses, Clusters, BoolToStr(Over, True), BoolToStr(Stepped, True)]));
    if Presses <> Clusters then
      Say(Format('    note: %s needs %d presses for %d clusters with this mapping', [PLAN_NAMES[I], Presses, Clusters]));
  end;
end;

{
  Chunk 3 state lifecycle: the atom table belongs to the engine state, so a
  mapping switch parks it and a restore brings it back. Two properties matter
  and neither is observable from the backspace cases:

    * without a table the answer is ONE unit - under-delete, never text loss;
    * a state whose table is missing still restores a WORKING table, because
      the table is derived from the registry the state carries.
}
procedure StateLifecycleChecks(const AMapping: string);
var
  Atoms:    TArray<TAnsiAtom>;
  Probe:    string;
  I, Working, Without, Restored: Integer;
  Empty:    TAnsiEngineState;
  Park:     TAnsiEngineState;
begin
  Say('');
  Say('=== ' + AMapping + ' / state lifecycle');

  // A state that was never filled carries nothing, so a caller that only asks
  // this question never tries to restore an empty engine over a good one.
  InitEngineState(Empty);
  Check(ATOM_ROW, AMapping + ': a fresh state is hollow', IsEngineStateHollow(Empty));

  // A glyph the table calls one visible character drawn with several units:
  // its one-press width is exactly its length (the gate above holds that for
  // every atom, so one example is enough to show the width path is live).
  Probe := '';
  Atoms := AnsiAtomMap.Atoms;
  for I := 0 to high(Atoms) do
    if (Length(Atoms[I].Units) > 1) and (Atoms[I].Bind = abSelf) then
    begin
      Probe := Atoms[I].Units;
      Break;
    end;
  if Probe = '' then
  begin
    Say('    note: this mapping draws every cluster with a single unit - nothing to probe');
    Exit;
  end;

  Working := AnsiTailClusterUnits(Probe);
  Check(ATOM_ROW, Format('%s: the table knows the width of [%s]', [AMapping, HexUnits(Probe)]), Working = Length(Probe),
    Format('one press erases %d of %d units', [Working, Length(Probe)]));

  // Fail-safe: no table at all means one unit per press, whatever the glyph is.
  FreeAndNil(AnsiAtomMap);
  Without := AnsiTailClusterUnits(Probe);
  Check(ATOM_ROW, AMapping + ': without a table a press erases one unit, never more', Without = 1, Format('got %d', [Without]));

  // The table is derived data: a capture taken while it was missing, restored
  // over an intact registry, must be usable again.
  CaptureEngineState(Park);
  RestoreEngineState(Park);
  Restored := AnsiTailClusterUnits(Probe);
  Check(ATOM_ROW, AMapping + ': a restored state rebuilds a missing table', (Restored = Working) and (AnsiAtomMap <> nil),
    Format('restored width %d, wanted %d, table nil=%s', [Restored, Working, BoolToStr(AnsiAtomMap = nil, True)]));

  // And the plain round trip: capture takes the table out of the globals, the
  // restore puts the very same table back, unchanged.
  CaptureEngineState(Park);
  Check(ATOM_ROW, AMapping + ': capture parks the table with the state', (Park.AnsiAtomMap <> nil) and (AnsiAtomMap = nil),
    Format('state holds %s, globals hold %s', [BoolToStr(Park.AnsiAtomMap <> nil, True), BoolToStr(AnsiAtomMap <> nil, True)]));
  RestoreEngineState(Park);
  Restored := AnsiTailClusterUnits(Probe);
  Check(ATOM_ROW, AMapping + ': restore puts the table back unchanged', Restored = Working,
    Format('width %d, wanted %d', [Restored, Working]));
end;

{
  Chunk 4 gate: the press behind text that is NOT ours.

  The ledger describes only text the engine typed. Everything else - a click, an
  arrow key, another application, text from before Avro - reaches the press as a
  caret-context READING plus the active mapping's glyph table. Every case below
  is a hard invariant of that path:

    * with the feature off, the press goes to the host and NOTHING is emitted:
      behaviour identical to before the feature existed;
    * with a reading, ONE emission erases exactly the units the mapping's own
      table gives for the last visible character, so the whole character goes;
    * one unit, an unknown glyph, a stale caret, no reading at all, or a width
      above the cap all end in the host's single character - never in more;
    * the reading layer is consulted at most ONCE per burst, so typing (which
      moves the caret constantly) cannot become a stream of probes;
    * with the feature off the reading is not even looked at;
    * an application listed as host-erase off (AnsiBackspaceApps) hands the
      press over BEFORE the reading is consulted, from the class names the
      watch cached on the main thread - a hook never queries a window.

  The reading layer and the caret are fakes, so the whole path is proven with no
  host, no window and no clipboard.
}
procedure HostTextChecks(const AMapping: string);
var
  Reader:     TFakeCaretReader;
  Sink:       TTraceSink;
  Conv:       TUnicodeToBijoy2000;
  Cluster:    string;
  HostTail:   string;
  OneUnit:    string;
  Atoms:      TArray<TAnsiAtom>;
  WantUnits:  Integer;
  I:          Integer;
  Block:      Boolean;
  FP, Moved:  TCaretFingerprint;
  Kind:       TEngineKind;
  Name:       string;
  Left:       string;

  { The press falls back untouched: the host erases one character, nothing of
    ours reached the host. }
  procedure ExpectHandover(const ALabel: string);
  begin
    Recorder.Reset;
    Block := False;
    DriveBackspace(ekModern, Block);
    Check(HOST_ROW, Format('%s: %s', [AMapping, ALabel]), (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d (%s): the press must fall back untouched', [BoolToStr(Block, True), Recorder.Emits, TraceText]));
  end;

  { One engine's host-text press: the whole visible character must go in one
    emission. }
  procedure ExpectClusterErase(const AKind: TEngineKind; const AName: string);
  begin
    SeedEngine(AKind, '');
    AnsiCaretContextInjectForTest(HostTail, FP);
    Recorder.Reset;
    Block := False;
    DriveBackspace(AKind, Block);
    Check(HOST_ROW, Format('%s: %s erases the whole host character in one emission', [AMapping, AName]),
      Block and (Recorder.Emits = 1) and (Recorder.EraseCount = WantUnits) and (Recorder.Text = '') and (TraceDecision = edCluster),
      Format('Block=%s emits=%d erase=%d text=[%s] want erase=%d (%s)', [BoolToStr(Block, True), Recorder.Emits, Recorder.EraseCount,
        HexUnits(Recorder.Text), WantUnits, TraceText]));

    // the screen really loses exactly that character and nothing else
    Left := Copy(HostTail, 1, Length(HostTail) - Recorder.EraseCount);
    Check(HOST_ROW, Format('%s: %s leaves the text before it alone', [AMapping, AName]), (Left = '') or (Left = Copy(HostTail, 1, Length(HostTail) - WantUnits)),
      Format('host text [%s] minus %d units = [%s]', [HexUnits(HostTail), Recorder.EraseCount, HexUnits(Left)]));
  end;

begin
  Conv := Modern.ConverterForTest;
  Say('');
  Say('=== ' + AMapping + ' / host text (chunk 4)');

  Cluster := #$0995 + string(b_Hasanta) + #$0995;

  { The text in front of the caret is chosen from the mapping's OWN table: the
    widest glyph it can put on screen that STARTS a cluster. A mapping is free
    to draw a conjunct with one unit (Default draws ka+hasanta+ka as one), and
    then there is nothing multi-unit to erase - the case must come from the
    mapping, not from an assumption here. }
  HostTail := '';
  Atoms := AnsiAtomMap.Atoms;
  for I := 0 to high(Atoms) do
    if (Atoms[I].Bind = abSelf) and (Length(Atoms[I].Units) > 1) and ((HostTail = '') or (Length(Atoms[I].Units) > Length(HostTail))) then
      HostTail := Atoms[I].Units;

  if HostTail = '' then
    HostTail := Conv.Convert(Cluster);
  WantUnits := AnsiTailClusterUnits(HostTail);

  FillChar(FP, SizeOf(FP), 0);
  FP.Window := HWND($1234);
  FP.CaretX := 100;
  FP.CaretY := 200;
  FP.TextLength := Length(HostTail);
  Moved := FP;
  Inc(Moved.CaretX); // the caret the reading was NOT taken at

  Reader := TFakeCaretReader.Create;
  Sink := TTraceSink.Create;
  try
    Reader.Tail := HostTail;
    Reader.Fingerprint := FP;
    Reader.Now := FP;

    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    AnsiBackspaceSetTrace(Sink.Backspace);
    AnsiCaretSnifferConfigure(True, False);
    AnsiCaretSnifferSetProvider(Reader.Provide, Reader.Current);

    // ---- the reading layer is consulted once per burst ---------------------
    AnsiCaretBurstBegin;
    Check(HOST_ROW, AMapping + ': the reading layer fills the cache', AnsiCaretContextRefresh(32) and (Reader.Calls = 1),
      Format('refresh=%s calls=%d', [BoolToStr(AnsiCaretContextRefresh(32), True), Reader.Calls]));
    Check(HOST_ROW, AMapping + ': a second ask in the same burst takes no new reading', Reader.Calls = 1,
      Format('calls=%d', [Reader.Calls]));
    AnsiCaretBurstEnd;

    AnsiCaretBurstBegin;
    AnsiCaretContextRefresh(32);
    Check(HOST_ROW, AMapping + ': a new burst may take a new reading', Reader.Calls = 2, Format('calls=%d', [Reader.Calls]));
    AnsiCaretBurstEnd;

    // ---- the reading really is the text before the caret -------------------
    Check(HOST_ROW, AMapping + ': the cache hands the tail to the press', AnsiCaretContextTail(Name) and (Name = HostTail),
      Format('tail=[%s] want [%s]', [HexUnits(Name), HexUnits(HostTail)]));

    Check(HOST_ROW, Format('%s: the probe is one visible character of this mapping', [AMapping]), WantUnits = Length(HostTail),
      Format('probe [%s] is %d units but one press erases %d', [HexUnits(HostTail), Length(HostTail), WantUnits]));

    if WantUnits > 1 then
    begin
      for Kind in [ekModern, ekOld, ekE2B] do
      begin
        case Kind of
          ekOld:
            Name := 'Old';
          ekE2B:
            Name := 'E2B';
        else
          Name := 'Modern';
        end;
        ExpectClusterErase(Kind, Name);
      end;
    end
    else
      Say('    note: this mapping draws every cluster with one unit - nothing multi-unit to erase');

    // ---- every doubt falls back to the host's single character -------------
    AnsiBackspaceHostErase := 'NO';
    AnsiCaretContextInjectForTest(HostTail, FP);
    ExpectHandover('the feature off hands the press over (and never reads the cache)');
    Check(HOST_ROW, AMapping + ': the feature off is not even a decision', (TraceDecision = edNotMine) and (TraceUnits = 1),
      Format('decision=%s units=%d', [AnsiDecisionName(TraceDecision), TraceUnits]));
    AnsiBackspaceHostErase := 'YES';

    AnsiCaretContextDrop('no reading for the press');
    ExpectHandover('no reading at all falls back');

    AnsiCaretContextInjectForTest(HostTail, FP);
    AnsiBackspaceUnitCap := '1';
    ExpectHandover('a width above the cap falls back');
    Check(HOST_ROW, AMapping + ': the cap is reported as the reason', TraceDecision <> edCluster,
      Format('decision=%s (%s)', [AnsiDecisionName(TraceDecision), TraceText]));
    AnsiBackspaceUnitCap := '8';

    { One unit: pick a cluster THIS mapping really draws with a single unit -
      Ansi V3 draws even a plain ka with two, and the width of the probe must
      come from the mapping, not from an assumption here. }
    OneUnit := '';
    for I := 0 to high(Atoms) do
      if Length(Atoms[I].Units) = 1 then
      begin
        OneUnit := Atoms[I].Units;
        Break;
      end;

    if OneUnit <> '' then
    begin
      AnsiCaretContextInjectForTest(OneUnit, FP);
      ExpectHandover('one unit is left to the host');
      Check(HOST_ROW, AMapping + ': one unit is reported as such', TraceDecision = edOneUnit,
        Format('decision=%s (%s)', [AnsiDecisionName(TraceDecision), TraceText]));
    end
    else
      Say('    note: every probe cluster is multi-unit in this mapping - the one-unit case is skipped');

    AnsiCaretContextInjectForTest(#$00AB, FP);
    ExpectHandover('an unknown glyph falls back');
    Check(HOST_ROW, AMapping + ': an unknown glyph is never erased as a cluster', TraceDecision <> edCluster,
      Format('decision=%s (%s)', [AnsiDecisionName(TraceDecision), TraceText]));

    // the caret moved after the reading: the reading describes another screen
    AnsiCaretContextInjectForTest(HostTail, FP);
    Reader.Now := Moved;
    ExpectHandover('a stale reading falls back (verify before delete)');
    Check(HOST_ROW, AMapping + ': a stale reading is reported as stale', TraceDecision = edStale,
      Format('decision=%s (%s)', [AnsiDecisionName(TraceDecision), TraceText]));
    Reader.Now := FP;

    // ---- the per-application override --------------------------------------
    // Some hosts delete clusters their own way or not at all, so the host erase
    // is switchable per application: a ';'-separated list of 'class-name=value'
    // pairs in AnsiBackspaceApps, where only an explicit on / yes / 1 / all /
    // default leaves the eraser on. The press must answer from the CACHE - the
    // class names are filled by the watch's tick (AnsiHostContextSet), never by
    // a window query inside the keyboard hook.
    AnsiBackspaceApps := '';
    AnsiHostContextSet('Chrome_RenderWidgetHostHWND', 'Chrome_WidgetWin_1');

    Check(HOST_ROW, AMapping + ': an empty override list allows every application',
      AnsiAppAllowsHostErase('', 'Chrome_WidgetWin_1', 'Notepad') and AnsiHostEraseAllowed,
      Format('allowed=%s for focus=[%s] foreground=[%s]', [BoolToStr(AnsiHostEraseAllowed, True), AnsiHostFocusClass,
        AnsiHostForegroundClass]));

    // A class that is not listed stays allowed, whatever else the list names.
    AnsiBackspaceApps := 'Notepad=off';
    Check(HOST_ROW, AMapping + ': an unlisted application is still allowed', AnsiHostEraseAllowed,
      Format('apps=[%s] blocked an unlisted host', [AnsiBackspaceApps]));

    // A partial name matches, case-insensitively: one entry then covers a
    // browser and its widget classes.
    AnsiBackspaceApps := 'CHROME=off';
    Check(HOST_ROW, AMapping + ': a partial class name matches case-insensitively', not AnsiHostEraseAllowed,
      Format('apps=[%s] focus=[%s] foreground=[%s]', [AnsiBackspaceApps, AnsiHostFocusClass, AnsiHostForegroundClass]));

    // The LAST matching entry wins, so a general rule can be narrowed by a more
    // specific one behind it.
    AnsiBackspaceApps := 'chrome=off;Chrome_WidgetWin_1=on';
    Check(HOST_ROW, AMapping + ': a later entry overrides an earlier one', AnsiHostEraseAllowed,
      Format('apps=[%s] is still blocked', [AnsiBackspaceApps]));

    // A value that is not an explicit on counts as OFF: a typo must never make
    // the eraser more aggressive than the setting says.
    AnsiBackspaceApps := 'Chrome_WidgetWin_1=maybe';
    Check(HOST_ROW, AMapping + ': a value that is not on counts as off', not AnsiHostEraseAllowed,
      Format('apps=[%s] is still allowed', [AnsiBackspaceApps]));

    // And the blocked press really hands over: nothing of ours is emitted, and
    // the reason names the application.
    AnsiCaretContextInjectForTest(HostTail, FP);
    ExpectHandover('a blocked application hands the press over');
    Check(HOST_ROW, AMapping + ': the blocked application is the reported reason', TraceDecision = edAppBlocked,
      Format('decision=%s (%s)', [AnsiDecisionName(TraceDecision), TraceText]));

    AnsiBackspaceApps := '';
    AnsiHostContextSet('', '');

    // ---- the WATCH: the provider the application installs ------------------
    // uCaretWatch is started/stopped by the form and its events are raised by
    // the WinEvent and mouse hooks; both are exercised here through the same
    // entry points they call, with the sniffer's own override standing in for a
    // real edit control (no window, no message, no clipboard).
    AnsiCaretSnifferClearProvider;
    AnsiCaretSnifferConfigure(False, False);

    // The real thing once: the OS hooks must install and uninstall cleanly.
    AnsiCaretWatchStart;
    AnsiCaretWatchStart; // idempotent
    Check(HOST_ROW, AMapping + ': the watch installs once and stays installed', AnsiCaretWatchActive, 'the watch reports itself inactive');
    AnsiCaretWatchStop;
    AnsiCaretWatchStop; // idempotent
    Check(HOST_ROW, AMapping + ': stopping the watch clears it', not AnsiCaretWatchActive, 'the watch still reports itself active');

    { From here on the HEAD-LESS start: the same provider, the same budget, the
      same "an event asked for a refresh" flag - but no OS hook, because this
      program runs on a live desktop where another application''s caret would
      raise a real WinEvent between the tick and the check. }
    AnsiCaretWatchStartHeadless;

    SniffOverrideActive := True;
    SniffOverride := HostTail;
    try
      // Starting takes one reading right away (the caret context it starts in
      // is unknown): absorb it, then measure the cases against that.
      AnsiCaretWatchTick;
      AnsiCaretWatchStats(WatchEvents, WatchRefreshes);
      BaseRefreshes := WatchRefreshes;
      BaseEvents := WatchEvents;

      // nothing asked for a reading: a tick must do nothing at all
      AnsiCaretContextDrop('before the watch cases');
      AnsiCaretWatchTick;
      AnsiCaretWatchStats(WatchEvents, WatchRefreshes);
      Check(HOST_ROW, AMapping + ': a tick with no caret event reads nothing',
        (WatchRefreshes = BaseRefreshes) and (not AnsiCaretContextTail(Name)),
        Format('refreshes=%d (base %d) tail=[%s]', [WatchRefreshes, BaseRefreshes, HexUnits(Name)]));

      // a caret event asks for one, the tick takes it through the real provider
      AnsiCaretWatchNoteCaretEvent('harness: caret moved');
      AnsiCaretWatchTick;
      AnsiCaretWatchStats(WatchEvents, WatchRefreshes);
      Check(HOST_ROW, AMapping + ': a caret event makes the tick take one reading',
        (WatchEvents = BaseEvents + 1) and (WatchRefreshes = BaseRefreshes + 1) and AnsiCaretContextTail(Name) and (Name = HostTail),
        Format('events=%d (base %d) refreshes=%d (base %d) tail=[%s] want [%s]', [WatchEvents, BaseEvents, WatchRefreshes, BaseRefreshes,
          HexUnits(Name), HexUnits(HostTail)]));
      Check(HOST_ROW, AMapping + ': the reading is attributed to the window-text layer',
        AnsiCaretContextSource = csWindowText, 'the cache does not name the layer it read from');

      // and the press behind that reading erases the whole character
      if WantUnits > 1 then
      begin
        SeedEngine(ekModern, '');
        Recorder.Reset;
        Block := False;
        DriveBackspace(ekModern, Block);
        Check(HOST_ROW, AMapping + ': the watch''s own reading drives the multi-unit erase',
          Block and (Recorder.Emits = 1) and (Recorder.EraseCount = WantUnits) and (TraceDecision = edCluster),
          Format('Block=%s emits=%d erase=%d want %d (%s)', [BoolToStr(Block, True), Recorder.Emits, Recorder.EraseCount, WantUnits, TraceText]));
      end;
    finally
      SniffOverrideActive := False;
      SniffOverride := '';
    end;

    AnsiCaretWatchStop;
    AnsiCaretWatchStop; // idempotent
    Check(HOST_ROW, AMapping + ': stopping the watch drops the reading', not AnsiCaretContextTail(Name),
      Format('tail=[%s] after stop', [HexUnits(Name)]));
  finally
    AnsiCaretContextDrop('harness cleanup');
    AnsiCaretSnifferClearProvider;
    AnsiCaretSnifferConfigure(False, False);
    AnsiBackspaceSetTrace(nil);
    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    AnsiBackspaceApps := '';
    AnsiHostContextSet('', '');
    Sink.Free;
    Reader.Free;
  end;
end;

{ ============================================================================== }
{ rows 8..11: the layers around the width                                        }
{ ============================================================================== }

{
  G1 rows 8..11: the layers the width rows cannot see.

  Rows 1..7 prove the WIDTH of one press against a ledger this engine typed.
  The rows below prove the three things that surround it, with no host at all:

    row 8  - DELIMITERS. A space is stored WITH the word it follows (it goes
             first, then the word, cluster by cluster); a character the HOST
             inserted (an unmapped key) is not in the ledger at all. Once a
             delimiter committed the word the ledger is gone, so the press can
             only hand over or use a reading.
    row 9  - REPEATED PRESSES. A press that erased host text consumed its
             reading, so the next press cannot erase the same area twice; a
             sequence of presses walks the tail one visible character per
             press, each off a fresh reading; inside ONE burst - the shape the
             keyboard hook opens for every key - the reading layer is asked
             exactly once, however many presses follow.
    row 10 - CARET MOVES. A foreground change, a layout or a mode switch
             reaches the engines as InvalidateAnsiTail and the cache as
             AnsiBackspaceInvalidate (the pair clsLayout publishes). Both the
             ledger and the reading must go, so the press hands over instead of
             erasing in a document this ledger never typed into - while a fresh
             reading at the NEW caret keeps the eraser working.
    row 11 - PENDING HOST CHARACTERS. Characters the host inserted sit between
             the caret and the ledger. The presses behind them are the host's:
             they never erase our text, our text behind them is untouched, and
             the count comes off one character per press.

  Every case drives the same entry points the hook does (BackspaceForTest, the
  caret-context cache, the watch's event flag), so all four rows are proven
  without a host window, a clipboard or a single injected key. Only the OS
  hook's own delivery and the reading layers themselves (message / UIA /
  clipboard) still need a real desktop.
}
procedure GateLayerChecks(const AMapping: string);
var
  Reader:  TFakeCaretReader;
  Sink:    TTraceSink;
  Conv:    TUnicodeToBijoy2000;
  Atoms:   TArray<TAnsiAtom>;
  Wide:    string; // the widest single cluster this mapping draws
  Base:    string; // one further visible character in front of it
  TwoTail: string; // Base + Wide: two visible characters before the caret
  Glyph:   string; // one visible character, as the engine's own ledger holds it
  Want:     Integer;
  BaseWant: Integer;
  Got:     Integer;
  Block:   Boolean;
  Again:   Boolean;
  Tail:    string;
  FP:      TCaretFingerprint;
  Moved:   TCaretFingerprint;
  I:       Integer;

  { One press of the Modern engine. Our side of it: ABlocked means the press
    was ours, AErase what our own emission erased (0 when the host took it). }
  procedure Press(out AErase: Integer; out ABlocked: Boolean);
  var
    B: Boolean;
  begin
    Recorder.Reset;
    B := False;
    DriveBackspace(ekModern, B);
    ABlocked := B;
    AErase := Recorder.EraseCount;
  end;

begin
  Say('');
  Say('=== ' + AMapping + ' / rows 8..11: delimiters, repeats, caret moves, pending chars');

  Conv := Modern.ConverterForTest;
  Reader := TFakeCaretReader.Create;
  Sink := TTraceSink.Create;

  AnsiBackspaceHostErase := 'YES';
  AnsiBackspaceUnitCap := '8';
  AnsiBackspaceLegacy := 'NO';
  AnsiBackspaceApps := '';
  AnsiBackspaceSetTrace(Sink.Backspace);
  AnsiCaretSnifferClearProvider;
  AnsiCaretSnifferConfigure(True, False);

  FillChar(FP, SizeOf(FP), 0);
  FP.Window := HWND($4321);
  FP.CaretX := 30;
  FP.CaretY := 40;
  Moved := FP;
  Moved.Window := HWND($8765); // another window took the caret
  Inc(Moved.CaretX);
  Reader.Fingerprint := FP;
  Reader.Now := FP;

  { The widest cluster the mapping's OWN table draws, and one more character in
    front of it: the tail the repeated presses below walk. Both come from the
    table, never from an assumption here. }
  Wide := '';
  Base := '';
  Atoms := AnsiAtomMap.Atoms;
  for I := 0 to high(Atoms) do
    if (Atoms[I].Bind = abSelf) and (Length(Atoms[I].Units) > 1) and ((Wide = '') or (Length(Atoms[I].Units) > Length(Wide))) then
      Wide := Atoms[I].Units;

  { A second visible character in front of it. Another multi-unit cluster is the
    interesting case (one press each); a mapping that has none gets a one-unit
    character, and then the press may only be handed over - asserted below,
    never assumed. }
  for I := 0 to high(Atoms) do
  begin
    if (Atoms[I].Bind <> abSelf) or (Atoms[I].Units = '') or (Atoms[I].Units = Wide) then
      Continue;
    if (Base = '') or ((Length(Atoms[I].Units) > 1) and (Length(Base) = 1)) then
      Base := Atoms[I].Units;
  end;
  if Wide = '' then
    Wide := Conv.Convert(#$0995 + string(b_Hasanta) + #$0995);
  if Base = '' then
    Base := Conv.Convert(#$0995);
  TwoTail := Base + Wide;
  Glyph := #$0995#$09BF; // ki: one visible character for every shipped mapping

  try
    if Length(Wide) <= 1 then
      Say('    note: this mapping draws every cluster with a single unit - the multi-unit tail cases are reported, not gated');

    // ---- row 8: delimiters -------------------------------------------------
    { The key handler drops the ledger the moment a delimiter commits the word,
      so what stays behind the caret is plain host text. }
    SeedEngine(ekModern, '');
    AnsiCaretContextDrop('the delimiter cases start with no reading');
    Press(Got, Block);
    Check(DELIM_ROW, AMapping + ': after a delimiter, with no reading, the host keeps the press',
      (not Block) and (Recorder.Emits = 0) and (TraceDecision = edNotMine),
      Format('Block=%s emits=%d decision=%s (%s)', [BoolToStr(Block, True), Recorder.Emits, AnsiDecisionName(TraceDecision), TraceText]));

    { ... and with a reading it erases ONE visible character of what is left,
      which is the only thing after a delimiter that is still ours to act on. }
    AnsiCaretContextInjectForTest(Wide, FP);
    Press(Got, Block);
    Check(DELIM_ROW, AMapping + ': after a delimiter the reading erases one character of the host text',
      Block and (Recorder.Emits = 1) and (Got = AnsiTailClusterUnits(Wide)) and (TraceDecision = edCluster),
      Format('Block=%s emits=%d erase=%d want %d (%s)', [BoolToStr(Block, True), Recorder.Emits, Got,
        AnsiTailClusterUnits(Wide), TraceText]));

    // ---- row 9: repeated presses -------------------------------------------
    { A press that erased host text consumed its reading, so the same tail can
      never be erased twice; and a tail of N visible characters costs N
      presses, each off a fresh reading. A mapping may draw a character with a
      SINGLE unit, and then the press is the host's - exactly one unit is what
      its own backspace removes (the host-text row proves that case as well). }
    Want := AnsiTailClusterUnits(Wide);
    SeedEngine(ekModern, '');
    AnsiCaretContextInjectForTest(Wide, FP);
    Press(Got, Block);
    if Want > 1 then
    begin
      Check(REPEAT_ROW, AMapping + ': the press erases the whole character in front of the caret', Block and (Got = Want),
        Format('Block=%s erase=%d want %d (%s)', [BoolToStr(Block, True), Got, Want, TraceText]));
      Check(REPEAT_ROW, AMapping + ': the reading that erased it is consumed', not AnsiCaretContextTail(Tail),
        Format('tail=[%s] survived the erase', [HexUnits(Tail)]));
    end
    else
      Check(REPEAT_ROW, AMapping + ': a one-unit character is left to the host',
        (not Block) and (TraceDecision = edOneUnit),
        Format('Block=%s decision=%s (%s)', [BoolToStr(Block, True), AnsiDecisionName(TraceDecision), TraceText]));
    Press(Got, Block);
    Check(REPEAT_ROW, AMapping + ': the next press with no reading erases nothing of ours',
      (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d: the same tail was erased twice', [BoolToStr(Block, True), Recorder.Emits]));

    { A sequence: each press takes the LAST visible character, off a fresh
      reading, so a tail of two characters costs exactly two presses. }
    if Want > 1 then
    begin
      BaseWant := AnsiTailClusterUnits(Base);
      Check(REPEAT_ROW, AMapping + ': a two-character tail ends in the wide cluster', AnsiTailClusterUnits(TwoTail) = Want,
        Format('tail [%s] is %d units, its last character %d', [HexUnits(TwoTail), AnsiTailClusterUnits(TwoTail), Want]));
      AnsiCaretContextInjectForTest(TwoTail, FP);
      Press(Got, Block);
      Check(REPEAT_ROW, AMapping + ': the first press takes the last character only', Block and (Got = Want),
        Format('Block=%s erase=%d want %d (%s)', [BoolToStr(Block, True), Got, Want, TraceText]));
      AnsiCaretContextInjectForTest(Base, FP); // what the next reading returns
      Press(Got, Block);
      if BaseWant > 1 then
        Check(REPEAT_ROW, AMapping + ': the next press takes the character before it', Block and (Got = BaseWant),
          Format('Block=%s erase=%d want %d (%s)', [BoolToStr(Block, True), Got, BaseWant, TraceText]))
      else
        Check(REPEAT_ROW, AMapping + ': a one-unit character in front of it is left to the host',
          (not Block) and (TraceDecision = edOneUnit),
          Format('Block=%s decision=%s (%s)', [BoolToStr(Block, True), AnsiDecisionName(TraceDecision), TraceText]));
    end;

    { Inside ONE burst the reading layer is asked once, and a second press in
      the same burst can neither take a new reading nor erase anything. }
    SeedEngine(ekModern, '');
    Reader.Tail := Wide;
    Reader.Calls := 0;
    AnsiCaretSnifferSetProvider(Reader.Provide, Reader.Current);
    AnsiCaretBurstBegin;
    try
      AnsiCaretContextRefresh(32);
      Press(Got, Block);
      Press(Got, Again);
    finally
      AnsiCaretBurstEnd;
      AnsiCaretSnifferClearProvider;
    end;
    Check(REPEAT_ROW, AMapping + ': one burst takes one reading for its presses', Reader.Calls = 1,
      Format('calls=%d', [Reader.Calls]));
    Check(REPEAT_ROW, AMapping + ': the second press in a burst erases nothing',
      (not Again) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d (%s)', [BoolToStr(Again, True), Recorder.Emits, TraceText]));

    // ---- row 10: the caret moved -------------------------------------------
    { While the caret has not moved the ledger answers for the press ... }
    SeedEngine(ekModern, Glyph, 0);
    Press(Got, Block);
    Check(CARET_ROW, AMapping + ': the ledger answers while the caret has not moved', Block and (Got > 0),
      Format('Block=%s erase=%d (%s)', [BoolToStr(Block, True), Got, TraceText]));

    { ... and a foreground change or a layout / mode switch takes the ledger AND
      the reading away, so the press can no longer erase in a document this
      ledger never typed into. }
    SeedEngine(ekModern, Glyph, 0);
    AnsiCaretContextInjectForTest(Wide, FP);
    Modern.InvalidateAnsiTail;
    AnsiBackspaceInvalidate;
    Check(CARET_ROW, AMapping + ': a caret move drops the ledger', Modern.CommittedForTest = '',
      Format('ledger=[%s] after the invalidate', [HexUnits(Modern.CommittedForTest)]));
    Check(CARET_ROW, AMapping + ': a caret move drops the reading', not AnsiCaretContextTail(Tail),
      Format('tail=[%s] after the invalidate', [HexUnits(Tail)]));
    Press(Got, Block);
    Check(CARET_ROW, AMapping + ': the press after a caret move is the host''s',
      (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d (%s)', [BoolToStr(Block, True), Recorder.Emits, TraceText]));

    { The move does not disable the eraser: a reading taken at the NEW caret is
      all it needs. }
    AnsiCaretContextInjectForTest(Wide, FP);
    Press(Got, Block);
    Check(CARET_ROW, AMapping + ': a fresh reading after the move erases at the new caret',
      Block and (Got = AnsiTailClusterUnits(Wide)),
      Format('Block=%s erase=%d want %d (%s)', [BoolToStr(Block, True), Got, AnsiTailClusterUnits(Wide), TraceText]));

    { A caret that moved into ANOTHER window: the reading's own fingerprint says
      so, and verify drops it before anything is erased. }
    Reader.Tail := Wide;
    AnsiCaretSnifferSetProvider(Reader.Provide, Reader.Current);
    AnsiCaretContextInjectForTest(Wide, FP);
    Reader.Now := Moved;
    Press(Got, Block);
    Check(CARET_ROW, AMapping + ': a reading from another window is dropped before the erase',
      (not Block) and (Recorder.Emits = 0) and (TraceDecision = edStale),
      Format('Block=%s emits=%d decision=%s (%s)', [BoolToStr(Block, True), Recorder.Emits, AnsiDecisionName(TraceDecision),
        TraceText]));
    Reader.Now := FP;
    AnsiCaretSnifferClearProvider;

    // ---- row 11: host characters between the caret and the ledger ----------
    SeedEngine(ekModern, Glyph, 1);
    AnsiCaretContextDrop('the pending cases start with no reading');
    Press(Got, Block);
    Check(PENDING_ROW, AMapping + ': a pending host character is the host''s press', (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d (%s)', [BoolToStr(Block, True), Recorder.Emits, TraceText]));
    Check(PENDING_ROW, AMapping + ': the pending character is counted off', Modern.PendingHostCharsForTest = 0,
      Format('pending=%d', [Modern.PendingHostCharsForTest]));
    Check(PENDING_ROW, AMapping + ': the word behind it is untouched', Modern.CommittedForTest = Glyph,
      Format('ledger=[%s] want [%s]', [HexUnits(Modern.CommittedForTest), HexUnits(Glyph)]));
    Press(Got, Block);
    Check(PENDING_ROW, AMapping + ': the press after it takes the word', Block and (Got > 0),
      Format('Block=%s erase=%d (%s)', [BoolToStr(Block, True), Got, TraceText]));

    { Even when a reading covers the host's character, ours must not erase it:
      that character is the host's, and our word behind it stays where it is. }
    SeedEngine(ekModern, Glyph, 1);
    AnsiCaretContextInjectForTest(Wide, FP);
    Press(Got, Block);
    Check(PENDING_ROW, AMapping + ': a pending character is never erased by our own emission',
      (not Block) and (Recorder.Emits = 0),
      Format('Block=%s emits=%d (%s)', [BoolToStr(Block, True), Recorder.Emits, TraceText]));
    Check(PENDING_ROW, AMapping + ': our word survives the press that was the host''s', Modern.CommittedForTest = Glyph,
      Format('ledger=[%s] want [%s]', [HexUnits(Modern.CommittedForTest), HexUnits(Glyph)]));

    { Two of them, behind the delimiter space a committed word carries: the
      space is the host's as well, so each press takes one character off and the
      word is only reached once both are gone. }
    SeedEngine(ekModern, Glyph + ' ', 2);
    Press(Got, Block); // the space goes with the count
    Check(PENDING_ROW, AMapping + ': the first pending character takes the trailing space with it',
      (not Block) and (Modern.PendingHostCharsForTest = 1) and (Modern.CommittedForTest = Glyph),
      Format('Block=%s pending=%d ledger=[%s] want [%s]', [BoolToStr(Block, True), Modern.PendingHostCharsForTest,
        HexUnits(Modern.CommittedForTest), HexUnits(Glyph)]));
    Press(Got, Block);
    Check(PENDING_ROW, AMapping + ': the second pending character is the host''s and the ledger is clean',
      (not Block) and (Modern.PendingHostCharsForTest = 0) and (Modern.CommittedForTest = Glyph),
      Format('Block=%s pending=%d ledger=[%s]', [BoolToStr(Block, True), Modern.PendingHostCharsForTest,
        HexUnits(Modern.CommittedForTest)]));
    Press(Got, Block);
    Check(PENDING_ROW, AMapping + ': and only then does the word itself go',
      Block and (Got > 0) and (Modern.CommittedForTest = ''),
      Format('Block=%s erase=%d ledger=[%s] (%s)', [BoolToStr(Block, True), Got, HexUnits(Modern.CommittedForTest), TraceText]));
  finally
    AnsiCaretContextDrop('rows 8..11 done');
    AnsiCaretSnifferClearProvider;
    AnsiCaretSnifferConfigure(False, False);
    AnsiBackspaceSetTrace(nil);
    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    AnsiBackspaceApps := '';
    AnsiHostContextSet('', '');
    Sink.Free;
    Reader.Free;
  end;
end;

{ ============================================================================== }
{ G1 row 14: English mode                                                        }
{ ============================================================================== }

{
  What happens when the user is NOT in Bangla mode. The invariant is that the
  press stays the host's: nothing of ours is emitted, the ledger is not fed, no
  reading is taken and the eraser is never even asked - for Backspace and for a
  typing key alike. The gate that keeps it that way sits at each engine's ENTRY
  point (see DriveKey), not in DoBackspace, which is why these cases drive
  ProcessVKeyDown and not BackspaceForTest.

  The gate also has to survive a mode switch. A reading taken while English was
  active describes a document the next Bangla press may not be looking at, so
  the switch - TLayout.ResetDeadKey -> InvalidateAnsiTail -> AnsiBackspaceInvalidate
  (clsLayout.pas:242) - drops the ledger and the reading together, and the first
  Bangla press after it measures fresh instead of answering from the English-era
  cache. One reading taken at the NEW caret is all the press after that needs.
}
procedure EnglishModeChecks(const AMapping: string);
const
  { The typing key a harness can really press. A LETTER goes through
    KeyboardLayoutLoader.GetCharForKey, which reads the loaded keyboard layout's
    key table - something a head-less container has no reason to load, and which
    is why the letter path is probed on a real desktop instead. The space key is
    handled by the engines themselves, and it passes the very same mode gate. }
  TYPING_KEY = VK_SPACE;
var
  Reader:     TFakeCaretReader;
  Sink:       TTraceSink;
  Conv:       TUnicodeToBijoy2000;
  Block:      Boolean;
  Wide, Word: string;
  Name, Tail: string;
  FP:         TCaretFingerprint;
  Kind:       TEngineKind;
  Atoms:      TArray<TAnsiAtom>;
  I:          Integer;

  function KindName(const AKind: TEngineKind): string;
  begin
    case AKind of
      ekOld: Result := 'Old';
      ekE2B: Result := 'E2B';
    else
      Result := 'Modern';
    end;
  end;

  { A reading that is there for the taking: if any engine consulted the eraser
    in English mode, THIS is the glyph the press would have erased. }
  procedure ArmReading;
  begin
    AnsiCaretContextInjectForTest(Wide, FP);
    Reader.Calls := 0;
  end;

begin
  Say('');
  Say('=== ' + AMapping + ' / English mode (row 14)');

  Conv := Modern.ConverterForTest;
  Word := #$09AC#$09BE#$0982#$09B2#$09BE; // "bangla": two clusters, one word

  { The widest glyph this mapping can put on screen that STARTS a cluster - the
    same probe the host-text row uses, so a mapping that draws every cluster
    with one unit still gets a reading wide enough to matter. }
  Wide := '';
  Atoms := AnsiAtomMap.Atoms;
  for I := 0 to high(Atoms) do
    if (Atoms[I].Bind = abSelf) and (Length(Atoms[I].Units) > 1) and ((Wide = '') or (Length(Atoms[I].Units) > Length(Wide))) then
      Wide := Atoms[I].Units;
  if Wide = '' then
    Wide := Conv.Convert(#$0995 + string(b_Hasanta) + #$0995);

  FillChar(FP, SizeOf(FP), 0);
  FP.Window := HWND($1234);
  FP.CaretX := 100;
  FP.CaretY := 200;
  FP.TextLength := Length(Wide);

  Reader := TFakeCaretReader.Create;
  Sink := TTraceSink.Create;
  try
    Reader.Tail := Wide;
    Reader.Fingerprint := FP;
    Reader.Now := FP;

    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    AnsiBackspaceSetTrace(Sink.Backspace);
    AnsiCaretSnifferConfigure(True, False);
    AnsiCaretSnifferSetProvider(Reader.Provide, Reader.Current);

    // ---- English: the press is the host's, in every engine ----------------
    for Kind in [ekModern, ekOld, ekE2B] do
    begin
      Name := KindName(Kind);

      SeedEngine(Kind, Word);
      SetEngineMode(Kind, True);
      ArmReading;
      TraceCalls := 0;
      Recorder.Reset;
      Block := True; // deliberately wrong: the engine has to set it

      DriveKey(Kind, VK_BACK, Block);

      Check(ENGLISH_ROW, Format('%s: %s Backspace in English mode stays the host''s press', [AMapping, Name]),
        (not Block) and (Recorder.Emits = 0),
        Format('Block=%s emits=%d (%s)', [BoolToStr(Block, True), Recorder.Emits, TraceText]));
      Check(ENGLISH_ROW, Format('%s: %s English mode never feeds the ledger', [AMapping, Name]), EngineLedger(Kind) = Word,
        Format('ledger=[%s] want [%s]', [HexUnits(EngineLedger(Kind)), HexUnits(Word)]));
      Check(ENGLISH_ROW, Format('%s: %s English mode never asks the eraser', [AMapping, Name]), TraceCalls = 0,
        Format('the decision point ran %d time(s) (%s)', [TraceCalls, TraceText]));
      Check(ENGLISH_ROW, Format('%s: %s English mode leaves the reading alone', [AMapping, Name]),
        AnsiCaretContextTail(Tail) and (Tail = Wide) and (Reader.Calls = 0),
        Format('tail=[%s] want [%s], reading layers asked %d time(s)', [HexUnits(Tail), HexUnits(Wide), Reader.Calls]));

      // ---- the same press in Bangla mode: the control -----------------------
      SeedEngine(Kind, Word);
      SetEngineMode(Kind, False);
      AnsiCaretContextDrop('the control case starts with no reading');
      TraceCalls := 0;
      Recorder.Reset;
      Block := False;

      DriveKey(Kind, VK_BACK, Block);

      Check(ENGLISH_ROW, Format('%s: %s in Bangla mode the same press takes the word (control)', [AMapping, Name]),
        Block and (Recorder.Emits >= 1) and (EngineLedger(Kind) <> Word),
        Format('Block=%s emits=%d ledger=[%s] want shorter than [%s]', [BoolToStr(Block, True), Recorder.Emits,
          HexUnits(EngineLedger(Kind)), HexUnits(Word)]));

      // ---- a typing key: English does not reach the tracker either ---------
      SeedEngine(Kind, '');
      SetEngineMode(Kind, True);
      TraceCalls := 0;
      Recorder.Reset;
      Block := True;

      DriveKey(Kind, TYPING_KEY, Block);

      Check(ENGLISH_ROW, Format('%s: %s a typing key in English mode types nothing of ours', [AMapping, Name]),
        (not Block) and (Recorder.Emits = 0), Format('Block=%s emits=%d', [BoolToStr(Block, True), Recorder.Emits]));
      Check(ENGLISH_ROW, Format('%s: %s a typing key in English mode leaves no ledger and no decision', [AMapping, Name]),
        (EngineLedger(Kind) = '') and (TraceCalls = 0),
        Format('ledger=[%s] decisions=%d', [HexUnits(EngineLedger(Kind)), TraceCalls]));

      { The control: in Bangla mode the SAME key does reach the tracker, so the
        assertion above cannot pass by the typing path being dead. Only the
        Modern engine can be driven here - the other two route a space through
        the preview form (E2B) or keep their delimiter state private (Old). }
      if Kind = ekModern then
      begin
        SeedEngine(Kind, '');
        SetEngineMode(Kind, False);
        Recorder.Reset;
        Block := False;

        DriveKey(Kind, TYPING_KEY, Block);

        Check(ENGLISH_ROW, Format('%s: %s the same key in Bangla mode IS ours (control)', [AMapping, Name]),
          EngineLedger(Kind) <> '', Format('ledger=[%s] after the key, want the committed tail', [HexUnits(EngineLedger(Kind))]));
      end
      else
        Say('    note: ' + Name + '''s typing path needs the preview form or keeps its state private; it passes the same mode gate Modern is probed on');
    end;

    // ---- the switch: the ledger and the reading go together ---------------
    SeedEngine(ekModern, Word);
    SetEngineMode(ekModern, True);
    ArmReading;
    Modern.InvalidateAnsiTail; // TLayout.InvalidateAnsiTail does this for all three engines
    AnsiBackspaceInvalidate;   // ... and this for the reading (clsLayout.pas:242)

    Check(ENGLISH_ROW, AMapping + ': the switch drops the ledger', Modern.CommittedForTest = '',
      Format('ledger=[%s] after the switch', [HexUnits(Modern.CommittedForTest)]));
    Check(ENGLISH_ROW, AMapping + ': the switch drops the reading', not AnsiCaretContextTail(Tail),
      Format('tail=[%s] after the switch', [HexUnits(Tail)]));

    SetEngineMode(ekModern, False);
    TraceCalls := 0;
    Recorder.Reset;
    Block := False;

    DriveKey(ekModern, VK_BACK, Block); // the first Bangla press after the switch

    Check(ENGLISH_ROW, AMapping + ': the first press after the switch measures fresh, never the English-era cache',
      (not Block) and (Recorder.Emits = 0) and (TraceCalls = 1) and (TraceDecision = edNotMine),
      Format('Block=%s emits=%d decisions=%d decision=%s (%s)', [BoolToStr(Block, True), Recorder.Emits, TraceCalls,
        AnsiDecisionName(TraceDecision), TraceText]));

    { ... and one reading taken at the NEW caret is all the press after it needs:
      the switch costs one press, it does not disable the eraser. }
    ArmReading;
    Recorder.Reset;
    Block := False;
    DriveKey(ekModern, VK_BACK, Block);
    Check(ENGLISH_ROW, AMapping + ': a reading taken after the switch erases at the new caret',
      Block and (Recorder.EraseCount = AnsiTailClusterUnits(Wide)) and (TraceDecision = edCluster),
      Format('Block=%s erase=%d want %d (%s)', [BoolToStr(Block, True), Recorder.EraseCount, AnsiTailClusterUnits(Wide), TraceText]));

    // ---- back to English: the host gets the press again -------------------
    SeedEngine(ekModern, Word);
    SetEngineMode(ekModern, True);
    ArmReading;
    TraceCalls := 0;
    Recorder.Reset;
    Block := True;

    DriveKey(ekModern, VK_BACK, Block);

    Check(ENGLISH_ROW, AMapping + ': switching back to English restores the host''s press',
      (not Block) and (Recorder.Emits = 0) and (TraceCalls = 0) and (Modern.CommittedForTest = Word),
      Format('Block=%s emits=%d decisions=%d ledger=[%s]', [BoolToStr(Block, True), Recorder.Emits, TraceCalls,
        HexUnits(Modern.CommittedForTest)]));

    // ---- no override and no form: the production fallback is English ------ 
    ClearEngineModes;
    for Kind in [ekModern, ekOld, ekE2B] do
    begin
      SeedEngine(Kind, Word);
      ArmReading;
      TraceCalls := 0;
      Recorder.Reset;
      Block := True;

      DriveKey(Kind, VK_BACK, Block);

      Check(ENGLISH_ROW, Format('%s: %s with no form and no override answers as English (the production fallback)',
        [AMapping, KindName(Kind)]), (not Block) and (Recorder.Emits = 0) and (TraceCalls = 0),
        Format('Block=%s emits=%d decisions=%d', [BoolToStr(Block, True), Recorder.Emits, TraceCalls]));
    end;
  finally
    ClearEngineModes;
    SeedEngine(ekModern, '');
    SeedEngine(ekOld, '');
    SeedEngine(ekE2B, '');
    AnsiCaretContextDrop('row 14 done');
    AnsiCaretSnifferClearProvider;
    AnsiCaretSnifferConfigure(False, False);
    AnsiBackspaceSetTrace(nil);
    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    Sink.Free;
    Reader.Free;
  end;
end;

{ The name of one row in the summary. Rows 1..7 are the width rows of the G1
  plan, rows 8..11 the layers above, and the last three are the chunk 3 / chunk
  4 / English-mode sections, reported under their own names. }
function RowLabel(const ARow: Integer): string;
begin
  case ARow of
    DELIM_ROW:
      Result := 'G1 row 8 (delimiters and commit points)';
    REPEAT_ROW:
      Result := 'G1 row 9 (repeated presses)';
    CARET_ROW:
      Result := 'G1 row 10 (caret moves and staleness)';
    PENDING_ROW:
      Result := 'G1 row 11 (pending host characters)';
    ATOM_ROW:
      Result := 'atom map (chunk 3)';
    HOST_ROW:
      Result := 'host text (chunk 4)';
    ENGLISH_ROW:
      Result := 'G1 row 14 (English mode and the mode switch)';
  else
    Result := Format('G1 row %d (one press, one visible character)', [ARow]);
  end;
end;

{ ============================================================================== }
{ entry point                                                                   }
{ ============================================================================== }

var
  MappingDir: string;
  Names:      TStringList;
  ErrLog:     TStringList;
  I, Row:     Integer;
  Loaded:     Integer;

begin
  Fails := 0;
  Checks := 0;
  Skipped := 0;
  FQuiet := False;
  for Row := 1 to MAX_ROW do
  begin
    RowFails[Row] := 0;
    RowChecks[Row] := 0;
  end;

  if ParamCount < 1 then
  begin
    WriteLn('Usage: kat_grapheme <mapping-dir> [quiet] [trace]');
    Halt(1);
  end;
  if ParamCount >= 2 then
    FQuiet := SameText(ParamStr(2), 'quiet');
  FTrace := (ParamCount >= 3) and SameText(ParamStr(3), 'trace');

  MappingDir := IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
  if not DirectoryExists(MappingDir) then
  begin
    WriteLn('FAIL mapping directory does not exist: ' + MappingDir);
    Halt(1);
  end;

  BuildCases;
  WriteLn(Format('kat_grapheme: %d cases x 3 engines, over every mapping in the folder', [CaseCount]));

  UnitLevelChecks;

  // The settings this harness depends on. A console process starts with the
  // settings globals empty, i.e. NOT the app's defaults, and driving the
  // backspace path while they are empty would test a configuration nobody
  // runs: OutputIsBijoy <> 'YES' is Unicode output, whose committed-text rules
  // are the old per-engine ones and whose emission does not go through the
  // test sink. ShowPrevWindow = 'NO' keeps the phonetic engine away from its
  // preview FORM, which a harness has no reason to create.
  OutputIsBijoy := 'YES';
  ShowPrevWindow := 'NO';
  AnsiBackspaceLegacy := 'NO';

  // the shipping load path: the folder, the container scan, then a switch
  AnsiMappingDir := MappingDir;
  InitializeEncoManager;
  ScanAvroEncoFiles(MappingDir);

  Recorder := TRecorder.Create;
  Names := TStringList.Create;
  ErrLog := TStringList.Create;
  try
    GetSortedMappingDisplayNames(Names);
    Say(Format('mappings found: %d [%s]', [Names.Count, Names.CommaText]));

    // the built-in engine always exists, so the engines are constructed once,
    // against a ready mapping, and then driven mapping by mapping
    if not AnsiEngineManager.SwitchEngine('Default', ErrLog) then
    begin
      WriteLn('FAIL cannot activate the built-in Default engine');
      Halt(1);
    end;

    Modern := TGenericLayoutModern.Create;
    Old := TGenericLayoutOld.Create;
    CharBased := TE2BCharBased.Create;
    try
      Modern.OnRawEmit := Recorder.Sink;
      Old.OnRawEmit := Recorder.Sink;
      CharBased.OnRawEmit := Recorder.Sink;

      Say('');
      Say('=== mapping: Default');
      RunCases('Default', 'Modern', ekModern);
      RunCases('Default', 'Old', ekOld);
      RunCases('Default', 'E2B', ekE2B);
      AtomMapChecks('Default');
      StateLifecycleChecks('Default');
      HostTextChecks('Default');
      GateLayerChecks('Default');
      EnglishModeChecks('Default');

      Loaded := 1;
      for I := 0 to Names.Count - 1 do
      begin
        ErrLog.Clear;
        if not AnsiEngineManager.SwitchEngine(Names[I], ErrLog) then
        begin
          Inc(Skipped);
          WriteLn('SKIP ' + Names[I] + ' (cannot unlock: ' + Trim(ErrLog.Text) + ')');
          Continue;
        end;
        Inc(Loaded);

        Say('');
        Say('=== mapping: ' + Names[I]);
        RunCases(Names[I], 'Modern', ekModern);
        RunCases(Names[I], 'Old', ekOld);
        RunCases(Names[I], 'E2B', ekE2B);
        AtomMapChecks(Names[I]);
        StateLifecycleChecks(Names[I]);
        HostTextChecks(Names[I]);
        GateLayerChecks(Names[I]);
        EnglishModeChecks(Names[I]);
      end;
    finally
      CharBased.Free;
      Old.Free;
      Modern.Free;
    end;
  finally
    ErrLog.Free;
    Names.Free;
    Recorder.Free;
  end;

  WriteLn('');
  WriteLn('=== summary');
  for Row := 1 to MAX_ROW do
    WriteLn(Format('  %s: %d checks, %s', [RowLabel(Row), RowChecks[Row], IfThen(RowFails[Row] = 0, 'PASS', IntToStr(RowFails[Row]) + ' FAIL')]));
  WriteLn(Format('  mappings loaded: %d, skipped: %d', [Loaded, Skipped]));
  WriteLn(Format('  total: %d checks, %d failures', [Checks, Fails]));

  if Fails = 0 then
  begin
    WriteLn('kat_grapheme: ALL PASS');
    Halt(0);
  end;

  WriteLn('kat_grapheme: FAIL');
  Halt(1);
end.
