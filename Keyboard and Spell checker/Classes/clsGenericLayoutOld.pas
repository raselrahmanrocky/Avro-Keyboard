{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
{ COMPLETE TRANSFERING! }

{ ============================================================================
  OLD STYLE TYPING - METHOD 1: PURE IN-MEMORY DELAYED BUFFERING
  (old Bijoy keyboard behaviour, zero visual side effects)

  Pre-base kars (ে, ি, ৈ) are held ONLY in memory until their consonant
  arrives. NOTHING is emitted for the kar itself - no zero-width
  separators, no dotted circles, no font switching in MS Word:

  * ে/ি/ৈ pressed            -> nothing appears (kar armed in memory)
  * consonant arrives        -> consonant + kar emitted directly, already
  canonical:  ি(mem) + দ -> দি,
  ে(mem) + ক -> কে,  দ + ি(mem) + ত -> দতি
  * same kar pressed AGAIN   -> attaches AT ONCE to the previous letter
  (double press = commit): ক + ি + ি -> কি
  * different kar pressed    -> REPLACES the pending one: nothing was
  visible, so nothing is lost. In ANSI mode every press is ink instead, so
  the earlier mark simply stays on screen (see the ANSI block below)
  * non-consonant key (digit, punctuation, vowel letter/sign) or a
  delimiter (space/enter/tab) -> the pending kar run is COMMITTED: the
  delayed kar is emitted as a standalone character first, then the key is
  processed (ি + '-' -> ি-) and in ANSI not a single backspace is sent -
  the glyphs are already ink and simply stop waiting for a consonant
  * ে(memory) + া -> ো  and  ে(memory) + ৗ -> ৌ  compose on the fly
  * ্ + ও -> ো and ্ + ঔ -> ৌ still work; a chandrabindu before the
  hasanta is re-placed AFTER the vowel sign: ক + ঁ + ্ + ও -> কোঁ
  * ক + ঁ + ৗ (no hasanta) -> কৗঁ - the raw AU mark is reordered in
  front of the chandrabindu (no composition)
  * ী (II-kar) is a POST-base kar: emitted directly to the letter typed
  before it (স+ত+ী+ন -> সতীন); clears any pending kar
  * HASANTA LINK: the kar stays pending across a hasanta - the whole
  conjunct receives the kar at its tail:
  ি -> জ -> ্ -> ব  =  জি -> জি্ -> জ্বি
  * BACKSPACE - Unicode mode (GitHub-style, identical with or without a
  space): exactly ONE unit leaves the buffer per press - one code point,
  or a whole phala / reph tail (্য, র্+বর্ণ). One press never eats a kar
  together with its letter:
  করি -> কর -> ক -> ''    করেছে -> করেছ -> করে -> কর -> ক -> ''
  A kar still pending in memory is simply cancelled - nothing was on
  screen, so the press is swallowed (মন + ে[memory] + BS -> মন).
  A kar hidden behind a VISIBLE hasanta survives: the hasanta is what
  the user sees, so that is what gets deleted.
  * BACKSPACE - ANSI mode = ANSI VISUAL ORDER (Traditional Style): the
  ANSI stream IS the buffer, so backspace is a plain pop() of the LAST
  GLYPH of the visual stream - no reordering, no vowel/consonant lookup:
  কি = [ি][ক]     -> BS -> ি      -> BS -> ''
  কো = [ে][ক][া]   -> BS -> কে     -> BS -> ে -> BS -> ''
  করেছে = K‡v‡Q   -> BS -> K‡v‡   -> BS -> K‡v -> BS -> K‡ -> BS -> K
  A whole ligature that is one glyph (ক্ষ) goes in one press; a pending
  kar glyph is erased on its own (Kv[‡] -> Kv); reph / phala tails keep
  their dedicated rules. See AnsiVisualPop.
  * In Bijoy (ANSI) output mode = TRUE ZERO-FLICKER VISUAL STREAM: the
  kar glyph streams straight onto the screen on its FIRST press with
  the mapping-correct variant (সাধারণ at a word start, ঝুলন্ত after a
  letter; V1..V4 automatically) and the kar NEVER enters the Unicode
  buffer while pending. AnsiMirror keeps the screen truth, so when the
  consonant binds the syllable the diff APPENDS WITHOUT ANY BACKSPACE:
  ক -> K   ে -> K‡   র -> K‡v   ন -> K‡vb ("করেন")
  Each keypress simply appends its glyph - authentic typewriter
  behaviour, no reordering, no erasure. ে+া -> ো and ে+ৗ -> ৌ compose;
  Backspace on a pending kar erases just the glyph (K‡ -> K). The
  conjunct ladder ি জ ্ ব -> জ্বি works. Kar-first typing never
  diverts to the isolated-modifier engine.

  THE INK RECORD (ANSI): every kar press is remembered as ONE entry
  (KarPressUni + KarPressAns) together with the SEAM it was typed at
  (KarAnchor = buffer snapshot, KarAnchorConv = its conversion).
  AnsiSplice() is the only place that decides where that ink sits in a
  stream, so:
  * the diff of a keystroke is an APPEND whenever the ink has not been
  bound yet - a symbol, a digit, a punctuation mark or a vowel after an
  unfinished kar run can never trigger SendBackSpace, and the glyphs
  that were already typed always survive: িি- stays িি- (frozen ink),
  never '-ি'.
  * one press = one glyph on backspace, whatever the seam position is,
  and the ink keeps being poppable after the run was frozen.
  * frozen ink is NOT bindable any more (the sequence was committed by
  the key that ended it); a consonant binds only the LAST press.
  Erase + retype is therefore reserved for what genuinely needs it: a
  conjunct/ligature substitution, a split ো/ৌ, a reph/phala move, and
  Convert's own pre-base reorder when a kar binds mid-word.
  ============================================================================ }

unit clsGenericLayoutOld;

interface

uses
  classes,
  sysutils,
  StrUtils,
  clsUnicodeToBijoy2000;

const
  TrackL = 100;

type
  {
    Lowest-level output sink: EraseCount backspaces, then Text.
    A caller - a regression harness or an embedding - may assign one to capture the
    exact stream; in production it is nil and the real keyboard injection
    runs unchanged.
  }
  TAnsiEmitEvent = procedure(const EraseCount: Integer; const Text: string) of object;

  // Skeleton of Class TGenericLayoutOld
type
  TGenericLayoutOld = class
    private
      Bijoy:                      TUnicodeToBijoy2000;
      LastChar:                   string;
      DetermineZWNJ_ZWJ:          string;
      LastChars:                  array [1 .. TrackL] of string;
      PrevBanglaT, NewBanglaText: string;
      CommittedBanglaT:           string;
      LastCommittedUnicode:       string;  // Unicode text sent before delimiter
      LastCommittedAnsi:          string;  // ANSI text sent before delimiter
      IsAtWordBoundary:           Boolean; // True after Space/Enter until next char
      SpacePendingCount:          Integer; // Delimiters we inserted; modifiers may cross them
      LastIsoContext:             string;  // Virtual Unicode context of last isolated emission
      LastIsoToggleKey:           string;  // '' = last isolated emission is not toggleable

      // Kar Variables for Full Old Style Typing (METHOD 1: in-memory
      // delayed buffering - pre-base kars ে, ি, ৈ are held here until
      // their consonant arrives; NOTHING is emitted for the kar itself.
      // ী is a POST-base kar and attaches directly)
      EKarActive, IKarActive, OIKarActive: Boolean;

      // ---- OLD-STYLE kar presses: ONE entry per kar key press --------------
      // Unicode classic: the ink is invisible (nothing is emitted for the
      // kar) - the record only remembers what an aborted sequence has to
      // flush. ANSI classic: every press ALSO streamed KarPressAns to the
      // screen, so the record IS the screen truth that the Unicode buffer
      // does not own. A key pressed AFTER the ink never rewrites history:
      // the run is frozen, not erased.
      KarPressUni: array [1 .. TrackL] of string; // canonical kar of the press
      KarPressAns: array [1 .. TrackL] of string; // glyph on screen ('' = none)
      KarPressN:   Integer;                       // presses currently live
      KarCanBind:  Boolean;                       // the LAST press may bind
      KarFrozen:   Boolean;                       // ink committed - poppable, not bindable

      // ANSI ZERO-FLICKER VISUAL STREAM: a pending pre-base kar is NOT in
      // the Unicode buffer - its glyph is streamed straight to the screen and
      // AnsiMirror holds the screen truth until the syllable binds.
      // KarAnchor is the buffer snapshot taken when the FIRST ink glyph was
      // streamed: AnsiSplice() puts the ink back at exactly that seam, so
      // every stream is the typed sequence and every diff is append-only.
      AnsiMirrorActive: Boolean; // True while streamed ink is on screen
      AnsiMirror:       string;  // ANSI stream rendered so far (screen mirror)
      KarAnchor:        string;  // buffer snapshot when the ink started
      KarAnchorConv:    string;  // ConvCached(KarAnchor) - cached for the splice

      // TEST / EMBEDDING HOOKS: nil/false in production, so the
      // engine always talks to the real host unless a caller replaces it.
      FOnRawEmit:    TAnsiEmitEvent;
      FModeOverride: Boolean;
      FModeValue:    Integer;

      // PERFORMANCE (hot path): Bijoy.Convert() is by far the most
      // expensive call in the unit and the SAME text is converted several
      // times per keystroke, so the last result is remembered here.
      // Cleared on every word reset (ResetLastChar). See ConvCached.
      FConvSrc, FConvAnsi: string;

      procedure InternalBackspace(KeyRepeat: Integer = 1);
      procedure DoBackspace(var Block: Boolean);
      procedure ParseAndSendNow;
      function InsertKar(const sKar: string): string;
      function InsertReph: string;
      procedure SetLastChar(const wChar: string);
      procedure DeleteLastCharSteps_Ex(StepCount: Integer);
      procedure ResetLastChar;
      procedure ClearIsoState;
      function HandleIsolatedModifier(const ModifierStr: string): Boolean;
      procedure ClearKarRun;
      procedure FreezeKarRun;
      procedure PushKarPress(const UniKar, AnsGlyph: string);
      function PopKarPress: string;
      function KarActive: Boolean;
      function KarBindable: Boolean;
      function KarUniRun(const WithoutLast: Boolean = False): string;
      function AnsiSplice(const ConvText: string): string;
      procedure RawSend(const EraseCount: Integer; const Text: string);
      function IsBanglaMode: Boolean;
      function IsAnsiClassic: Boolean;
      procedure SendAnsiDiff(const PrevAnsi, NewAnsi: string);
      procedure EmitBatch(const EraseCount: Integer; const Text: string);
      procedure CommitContext(const Word: string);
      function ConvCached(const T: string): string;
      function KarInkRun: string;
      function CommonPrefixLen(const A, B: string): Integer;
      function CommonSuffixLen(const A, B: string; const Used: Integer): Integer;
      function AnsiDiffOps(const From, Into: string): Integer;
      function AnsiVisualPop(var Block: Boolean): Boolean;
      function GetActivePreBaseKar: string;
      function PressPreBaseKar(const KarChar: string): string;
      procedure ArmPreBaseFlag(const KarChar: string);
      function ResolveHasantaVowelPrefix(const PendingKar: string): string;
      function MyProcessVKeyDown(const KeyCode: Integer; var Block: Boolean; const var_IsLogicalShift, var_IsTrueShift, var_IsAltGr: Boolean): string;
      procedure MyProcessVKeyUP(const KeyCode: Integer; var Block: Boolean; const var_IsLogicalShift: Boolean; const var_IsTrueShift: Boolean;
        const var_IsAltGr: Boolean);
      procedure ResetAllKarsToInactive;
    public
      constructor Create;           // Initializer
      destructor Destroy; override; // Destructor

      function ProcessVKeyDown(const KeyCode: Integer; var Block: Boolean): string;
      procedure ProcessVKeyUP(const KeyCode: Integer; var Block: Boolean);
      procedure ResetDeadKey;
      procedure FlushEmit;

      { TEST / EMBEDDING HOOKS - see the field comments above. Assigning one
        replaces the real host for the duration. }
      property OnRawEmit: TAnsiEmitEvent read FOnRawEmit write FOnRawEmit;
      procedure SetKeyboardModeOverride(const Enabled: Boolean; const Mode: Integer);
  end;

implementation

uses
  Windows,
  Messages,
  Banglachars,
  KeyboardFunctions,
  uForm1,
  KeyboardLayoutLoader,
  clsLayout,
  VirtualKeycode,
  WindowsVersion,
  uRegistrySettings,
  uCaretContextSniffer;

{ ===============================================================================
  OPTIONAL DEFERRED INJECTION  -  AVRO_DEFER_EMIT
  -------------------------------------------------------------------------------
  LowLevelKeyboardProc runs while the Raw Input Thread (RIT) is blocked waiting
  for it. Calling SendInput from inside it measured ~1.0-1.5 ms per call - 20 to
  200 times the normal 5-50 us - and, worse, the injected events piled up inside
  the RIT and were flushed in bursts after the hook chain unwound. That is the
  "hang, then everything appears at once" effect.

  With this define the emit is only QUEUED here and the actual SendInput runs on
  the main thread AFTER the hook callback returned (RIT free again). Order is
  preserved: the queue is FIFO and the state it was computed from is final.

  Turn it OFF by commenting out the DEFINE line below - behaviour reverts to
  the direct call, nothing else changes.

  Needs 2 tiny additions in other units (see the guide):
  uForm1   : procedure WMAvroEmit(var Msg: TMessage); message WM_APP + 10;
  begin if Assigned(KeyLayout) then KeyLayout.FlushEmit; end;
  clsLayout: procedure TLayout.FlushEmit; begin GenericOldFixed.FlushEmit; end;
  =============================================================================== }
{$DEFINE AVRO_DEFER_EMIT}

const
  WM_AVRO_EMIT = $8000 + 10; // WM_APP + 10

type
  TEmitRec = record
    EraseCount: Integer;
    Text: string;
  end;

var
  {$IFDEF AVRO_DEFER_EMIT}
  FEmitN: Integer;
  FEmitQ: array of TEmitRec;
  {$ENDIF}
  { =============================================================================== }
  { =============================================================================== }

  { TGenericLayoutOld }

constructor TGenericLayoutOld.Create;
begin
  inherited;
  ResetLastChar;

  // If IsWinVistaOrLater Then
  DetermineZWNJ_ZWJ := ZWJ;
  // Else
  // DetermineZWNJ_ZWJ := ZWNJ;

  Bijoy := TUnicodeToBijoy2000.Create;
  LastCommittedUnicode := '';
  LastCommittedAnsi := '';
  IsAtWordBoundary := False;
  SpacePendingCount := 0;
  LastIsoContext := '';
  LastIsoToggleKey := '';
  ClearKarRun;
  FOnRawEmit := nil;
  FModeOverride := False;
  FModeValue := Ord(SysDefault);
  FConvSrc := '';
  FConvAnsi := '';
  {$IFDEF AVRO_DEFER_EMIT}
  FlushEmit; // keep the queue empty across resets (order is never reordered)
  {$ENDIF}
end;

{ =============================================================================== }

{
  OPTIMISED (hot path - runs on every backspace step).
  Shifts the slots in place instead of rebuilding two TrackL-character
  strings (~200 allocations per call before, zero now).
}
procedure TGenericLayoutOld.DeleteLastCharSteps_Ex(StepCount: Integer);
var
  I: Integer;
begin
  if StepCount <= 0 then
    Exit;
  if StepCount > TrackL then
    StepCount := TrackL;

  { the surviving characters move towards the newest end (slot 1) }
  for I := 1 to TrackL - StepCount do
    LastChars[I] := LastChars[I + StepCount];

  { the freed slots at the oldest end become blanks }
  for I := TrackL - StepCount + 1 to TrackL do
    LastChars[I] := ' ';

  LastChar := LastChars[1];
end;

{ =============================================================================== }

destructor TGenericLayoutOld.Destroy;
begin
  FreeAndNil(Bijoy);

  inherited;
end;

{ =============================================================================== }

{
  OLD STYLE: forgets the kar press record - and with it every glyph the
  record still owed the screen. Only for the callers that KNOW the ink is
  gone (a word reset, a consonant that took the whole run, a deletion of the
  ink itself). When the glyphs are still on screen and must stay poppable,
  use FreezeKarRun instead.
}
procedure TGenericLayoutOld.ClearKarRun;
var
  I: Integer;
begin
  for I := 1 to TrackL do
  begin
    KarPressUni[I] := '';
    KarPressAns[I] := '';
  end;
  KarPressN := 0;
  KarCanBind := False;
  KarFrozen := False;
  KarAnchor := '';
  KarAnchorConv := '';
end;

{
  OLD STYLE: the ink stays EXACTLY where it is on screen, it only stops
  waiting for a consonant. Used when a symbol/punctuation/vowel follows an
  unfinished kar run: the sequence is committed as typed, nothing is erased
  and the glyphs can still be popped one press at a time.
}
procedure TGenericLayoutOld.FreezeKarRun;
begin
  KarCanBind := False;
  KarFrozen := True;
end;

{
  Appends one kar key press to the record.
  UniKar      - the canonical kar the press stands for (ে, ি, ৈ ...)
  AnsGlyph    - the glyph that was streamed to the screen ('' in Unicode
                classic mode, where nothing at all is emitted)
}
procedure TGenericLayoutOld.PushKarPress(const UniKar, AnsGlyph: string);
begin
  if KarPressN >= TrackL then
    Exit; // not a sequence a human types - keep the screen exactly as it is
  Inc(KarPressN);
  KarPressUni[KarPressN] := UniKar;
  KarPressAns[KarPressN] := AnsGlyph;
end;

{
  Removes the LAST press and returns the glyph that left the screen.
  One backspace = one press = one glyph, whatever that glyph was.
}
function TGenericLayoutOld.PopKarPress: string;
begin
  Result := '';
  if KarPressN < 1 then
    Exit;

  Result := KarPressAns[KarPressN];
  KarPressUni[KarPressN] := '';
  KarPressAns[KarPressN] := '';
  Dec(KarPressN);

  { the anchor only belongs to a run that still has ink }
  if KarPressN = 0 then
  begin
    KarAnchor := '';
    KarAnchorConv := '';
  end;
end;

{ a kar press is live (either still waiting for its consonant or frozen ink) }
function TGenericLayoutOld.KarActive: Boolean;
begin
  Result := (KarPressN > 0) and (KarPressUni[KarPressN] <> '');
end;

{
  A kar that may still be taken by a coming consonant: it is armed AND the
  run was not frozen by a symbol/punctuation/vowel key in between.
}
function TGenericLayoutOld.KarBindable: Boolean;
begin
  Result := KarCanBind and (not KarFrozen) and KarActive and (GetActivePreBaseKar <> '');
end;

{ the whole run in canonical Unicode order; WithoutLast drops the press a
  consonant is about to take }
function TGenericLayoutOld.KarUniRun(const WithoutLast: Boolean): string;
var
  I, N: Integer;
begin
  Result := '';
  N := KarPressN;
  if WithoutLast then
    Dec(N);
  for I := 1 to N do
    if KarPressUni[I] <> '' then
      Result := Result + KarPressUni[I];
end;

{
  ANSI: every glyph the run streamed, in stream order. A kar key pressed
  three times is THREE glyphs - the old single-glyph bookkeeping is what made
  repeated kars disappear on the next key.
}
function TGenericLayoutOld.KarInkRun: string;
var
  I: Integer;
begin
  Result := '';
  if (KarPressN < 1) or (KarPressN > TrackL) then
    Exit;
  for I := 1 to KarPressN do
    if KarPressAns[I] <> '' then
      Result := Result + KarPressAns[I];
end;

{
  ANSI classic mode: the glyph stream IS the buffer - purely visual, no
  vowel/consonant reordering. Unicode classic mode keeps the reorder machine
  (and the delayed in-memory kar).
}
function TGenericLayoutOld.IsAnsiClassic: Boolean;
begin
  Result := OutputIsBijoy = 'YES';
end;

{
  True in Bangla mode. Reads AvroMainForm1 unless a test/embedding override
  is set, so the engine is never reachable through a nil form.
}
function TGenericLayoutOld.IsBanglaMode: Boolean;
begin
  if FModeOverride then
    Result := FModeValue = Ord(bangla)
  else if Assigned(AvroMainForm1) then
    Result := AvroMainForm1.GetMyCurrentKeyboardMode = bangla
  else
    Result := False;
end;

{ see the fixed anchor note on AnsiSplice }
procedure TGenericLayoutOld.SetKeyboardModeOverride(const Enabled: Boolean; const Mode: Integer);
begin
  FModeOverride := Enabled;
  if Enabled then
    FModeValue := Mode;
end;

{
  Conv(text) with the screen-only ink put back in EXACTLY the place it was
  typed. This is the single place that decides where ink sits, so
  ParseAndSendNow, AnsiVisualPop's candidates and the hasanta paths can never
  disagree about the stream:
  * the ink was streamed right behind Conv(KarAnchor), so it is spliced there
    (KarAnchor = '' means "at the very head of the word")
  * when the anchor is gone (a deletion or a ligature crossed it) the safest
    stream is the ink trailing at the end - never a backspace storm.
}
function TGenericLayoutOld.AnsiSplice(const ConvText: string): string;
var
  Ink, Head: string;
begin
  Ink := KarInkRun;
  if Ink = '' then
    Exit(ConvText);

  Head := Copy(ConvText, 1, Length(KarAnchorConv));
  if (Length(KarAnchorConv) = 0) or (Head = KarAnchorConv) then
    Result := Head + Ink + Copy(ConvText, Length(KarAnchorConv) + 1, MaxInt)
  else
    Result := ConvText + Ink;
end;

{
  The lowest emission point. When a sink is assigned (the regression harness)
  it captures the stream; otherwise the real keyboard injection runs exactly
  as before.
}
procedure TGenericLayoutOld.RawSend(const EraseCount: Integer; const Text: string);
begin
  if Assigned(FOnRawEmit) then
    FOnRawEmit(EraseCount, Text)
  else
    SendInputBatch_BackspaceAndChar(EraseCount, Text);
end;

{ =============================================================================== }

{
  ANSI: re-syncs the screen from PrevAnsi to NewAnsi with the smallest
  possible edit (erase the mismatched tail, then type the remainder).
  Needed when a streamed kar glyph has to survive a deletion.
}
procedure TGenericLayoutOld.SendAnsiDiff(const PrevAnsi, NewAnsi: string);
var
  Matched, UnMatched: Integer;
begin
  Matched := 0;

  { direct character indexing - MidStr allocates a temporary string for
    every single character }
  while (Matched < Length(PrevAnsi)) and (Matched < Length(NewAnsi)) and (PrevAnsi[Matched + 1] = NewAnsi[Matched + 1]) do
    Inc(Matched);

  UnMatched := Length(PrevAnsi) - Matched;

  EmitBatch(UnMatched, Copy(NewAnsi, Matched + 1, MaxInt));
end;

{ =============================================================================== }

{
  Bijoy.Convert with a one-entry memo. Convert() is the most expensive call
  in the unit and the SAME text is converted several times per keystroke
  (ParseAndSendNow, the ANSI stream mirrors, AnsiVisualPop, DoBackspace).
  A string compare is orders of magnitude cheaper than a conversion, so the
  last result is simply remembered. Cleared on every word reset.
}
function TGenericLayoutOld.ConvCached(const T: string): string;
begin
  if (T <> '') and (T = FConvSrc) then
    Result := FConvAnsi
  else
  begin
    Result := Bijoy.Convert(T);
    FConvSrc := T;
    FConvAnsi := Result;
  end;
end;

{ =============================================================================== }

{
  Appends a finished word to the committed (pre-caret) context and keeps only
  its tail.

  DoBackspace never looks further back than 4 characters, so anything older is
  dead weight - and an uncapped buffer made every single backspace copy the
  WHOLE typing session (LeftStr(CommittedBanglaT, L - 3) + SavedChar). That is
  what made Avro crawl slower and slower after a few thousand words. The
  VK_RETURN branch had no cap at all, so it grew without bound.
}
procedure TGenericLayoutOld.CommitContext(const Word: string);
const
  MaxCtx = 24;
begin
  CommittedBanglaT := CommittedBanglaT + Word + ' ';
  if Length(CommittedBanglaT) > MaxCtx then
    Delete(CommittedBanglaT, 1, Length(CommittedBanglaT) - MaxCtx);
end;

{ =============================================================================== }

{
  HOT PATH OUTPUT. One single SendInput batch (SendInputBatch_BackspaceAndChar)
  replaces 4*EraseCount + 4*Length(Text) separate SendInput calls, and it also
  skips the per-character Log() that SendKey_Char does (the disk write per
  character was a large part of the 4.35 ms ParseAndSendNow measurement;
  DebugLog is file-free now, so what is left to avoid is the string).

  A whole "erase + retype" is emitted ATOMICALLY, so fast typing can no longer
  interleave with it - that is what produced the "everything appears at once"
  effect.
}
procedure TGenericLayoutOld.EmitBatch(const EraseCount: Integer; const Text: string);
begin
  if (EraseCount <= 0) and (Text = '') then
    Exit;
  {$IFDEF AVRO_DEFER_EMIT}
  if Assigned(FOnRawEmit) then
    FOnRawEmit(EraseCount, Text) // test sink: no message pump, no main form
  else
  begin
    if FEmitN >= Length(FEmitQ) then
      SetLength(FEmitQ, FEmitN + 32);
    FEmitQ[FEmitN].EraseCount := EraseCount;
    FEmitQ[FEmitN].Text := Text;
    Inc(FEmitN);
    { Runs after the hook callback returned - see the AVRO_DEFER_EMIT note. }
    PostMessage(AvroMainForm1.Handle, WM_AVRO_EMIT, 0, 0);
  end;
  {$ELSE}
  RawSend(EraseCount, Text);
  {$ENDIF}
end;

{ Drains the deferred output queue. Called from the main form's WM_AVRO_EMIT
  handler, i.e. OUTSIDE the low-level keyboard hook callback. }
procedure TGenericLayoutOld.FlushEmit;
var
  I: Integer;
begin
  for I := 0 to FEmitN - 1 do
  begin
    RawSend(FEmitQ[I].EraseCount, FEmitQ[I].Text);
  end;
  FEmitN := 0;
end;

{ =============================================================================== }

{ =============================================================================== }

{ Number of leading characters the two strings share. }
function TGenericLayoutOld.CommonPrefixLen(const A, B: string): Integer;
begin
  Result := 0;
  while (Result < Length(A)) and (Result < Length(B)) and (A[Result + 1] = B[Result + 1]) do
    Inc(Result);
end;

{ =============================================================================== }

{ Number of trailing characters the two strings share. "Used" characters at
  the front (the common prefix) are never counted twice. }
function TGenericLayoutOld.CommonSuffixLen(const A, B: string; const Used: Integer): Integer;
begin
  Result := 0;
  while (Result < Length(A) - Used) and (Result < Length(B) - Used) and (A[Length(A) - Result] = B[Length(B) - Result]) do
    Inc(Result);
end;

{ =============================================================================== }

{ Keystrokes needed to turn the screen string "From" into "Into":
  backspaces for the mismatched tail + the characters retyped. }
function TGenericLayoutOld.AnsiDiffOps(const From, Into: string): Integer;
var
  P: Integer;
begin
  P := CommonPrefixLen(From, Into);
  Result := (Length(From) - P) + (Length(Into) - P);
end;

{ =============================================================================== }

{
  ANSI VISUAL ORDER backspace (Traditional Style).

  In ANSI mode the text buffer IS the visual stream: every glyph sits on
  screen in the order it was typed. Backspace therefore does what an
  ordinary typewriter does - it pops the LAST GLYPH of the stream, with no
  grammatical reordering, no vowel/consonant lookup:

  কি   = [ি][ক]        -> BS -> ি        -> BS -> ''
  কো   = [ে][ক][া]      -> BS -> কে       -> BS -> ে -> BS -> ''
  করি  = K w v          -> BS -> K w      -> BS -> K -> BS -> ''
  করেছে = K ‡ v ‡ Q     -> BS -> K ‡ v ‡   -> BS -> K ‡ v -> BS -> K ‡ -> BS -> K -> BS -> ''
  ক্ষ   (single glyph)  -> BS -> ''      (the whole ligature in one press)

  The Unicode buffer still has to follow the screen, so every candidate edit
  is scored by the number of keystrokes its ANSI diff costs and the CHEAPEST
  one wins - which is exactly "the last glyph disappeared and nothing else
  moved":
  2a  consonant + pre-base kar -> the consonant glyph pops, the kar stays
  on screen as pending ink            (কি -> ি)
  2b  two-part kar ো / ৌ -> loses its right half first: ো -> ে, ৌ -> ে
  2c  conjunct ladder unwind: [C1 ্ C2 কার] -> [C1 কার ্]
  (জ্বি -> জি্)
  2d  plain suffix deletions (1..6 code points) - covers plain letters,
  whole ligatures, post-base kars, pending hasanta ...

  Reph / phala tails keep their own dedicated rules in DoBackspace.
}
function TGenericLayoutOld.AnsiVisualPop(var Block: Boolean): Boolean;
var
  B, S, Ink, InkAll, Cand, CandAnsi, KarGlyph, NoKar: string;
  BestBuf, BestAnsi, BestInk, PeelKar, UnwindKar:     string;
  BestOps, Ops, K, P, Suf:                            Integer;
  HasCand, BestTwoPart:                               Boolean;
begin
  Result := False;
  if Bijoy = nil then
    Exit;

  B := PrevBanglaT;
  if B = '' then
    Exit; // nothing of ours on screen - the normal path decides

  { reph / phala tails: DoBackspace has the dedicated rules for them }
  if (Length(B) >= 3) and (B[Length(B) - 2] = b_R) and (B[Length(B) - 1] = b_Hasanta) and IsPureConsonent(B[Length(B)]) then
    Exit;
  if (Length(B) >= 2) and (B[Length(B) - 1] = b_Hasanta) and ((B[Length(B)] = b_Z) or (B[Length(B)] = b_R)) then
    Exit;

  { the screen truth }
  if AnsiMirrorActive then
    S := AnsiMirror
  else
    S := ConvCached(B);

  { ink of a kar run whose Unicode is NOT in the buffer: either still waiting
    for its consonant or FROZEN by a symbol typed after it - both must stay
    poppable (the frozen case had no backspace handler at all before).
    Ink     = the glyph of the LAST press - step 1 pops exactly that one
    InkAll  = the whole run             - what the candidates must show }
  if KarActive and (KarInkRun <> '') then
  begin
    Ink := KarPressAns[KarPressN];
    InkAll := KarInkRun;
  end
  else
  begin
    Ink := '';
    InkAll := '';
  end;

  { --- 1. the pending kar glyph IS the last glyph on screen: erase one
    copy of it (one press = one glyph, even inside a kar run) --- }
  if (Ink <> '') and (Length(S) >= Length(Ink)) and (RightStr(S, Length(Ink)) = Ink) then
  begin
    SendAnsiDiff(S, LeftStr(S, Length(S) - Length(Ink)));
    NewBanglaText := B;
    PrevBanglaT := B;
    AnsiMirror := LeftStr(S, Length(S) - Length(Ink));
    PopKarPress; // ONE press = ONE glyph
    if KarInkRun <> '' then
    begin
      { earlier presses of the run are still ink on screen, in typed order,
        and may still be taken by a consonant - nothing else changes }
      AnsiMirrorActive := True;
    end
    else
    begin
      AnsiMirrorActive := False;
      ResetAllKarsToInactive;
      ClearKarRun;
    end;
    Block := True;
    Result := True;
    Exit;
  end;

  { --- 1b. FAST PATH (speed) -------------------------------------------------
    The overwhelming majority of backspaces delete a plain letter, a
    post-base kar, a vowel or a digit: one code point IS one glyph and no
    reordering can happen. Skipping the candidate search saves ~10 whole-word
    conversions per press - exactly what made fast repeated backspace crawl.
    Everything "interesting" (pre-base kar, ো/ৌ, hasanta, conjunct, reph,
    phala, pending ink) still goes through the full search below. }
  if (Ink = '') and (GetActivePreBaseKar = '') and (B[Length(B)] <> b_Ekar) and (B[Length(B)] <> b_Ikar) and (B[Length(B)] <> b_OIkar) and
    (B[Length(B)] <> b_Okar) and (B[Length(B)] <> b_OUkar) and (B[Length(B)] <> b_Hasanta) and ((Length(B) < 2) or (B[Length(B) - 1] <> b_Hasanta)) then
  begin
    BestBuf := LeftStr(B, Length(B) - 1);
    if BestBuf = '' then
      Exit; // DoBackspace wipes the word (and does its own bookkeeping)

    BestAnsi := ConvCached(BestBuf); // ONE conversion instead of ~10
    InternalBackspace(1);
    SendAnsiDiff(S, BestAnsi);
    PrevBanglaT := NewBanglaText;
    AnsiMirrorActive := False;
    ResetAllKarsToInactive;
    ClearKarRun;
    Block := True;
    Result := True;
    Exit;
  end;

  { --- 2. cheapest Unicode edit that removes the last visual glyph --- }
  BestOps := MaxInt;
  BestBuf := '';
  BestAnsi := '';
  BestInk := InkAll;
  PeelKar := '';
  UnwindKar := '';
  HasCand := False;
  BestTwoPart := False;

  { 2a. consonant + pre-base kar: the consonant glyph pops, the kar stays
    on screen as pending ink (কি -> ি, করি -> কর + ি) }
  if (Length(B) >= 2) and IsPureConsonent(B[Length(B) - 1]) and ((B[Length(B)] = b_Ekar) or (B[Length(B)] = b_Ikar) or (B[Length(B)] = b_OIkar)) then
  begin
    Cand := LeftStr(B, Length(B) - 2);
    CandAnsi := ConvCached(B);
    NoKar := ConvCached(Cand + B[Length(B) - 1]); // the same text without the kar
    P := CommonPrefixLen(CandAnsi, NoKar);
    Suf := CommonSuffixLen(CandAnsi, NoKar, P);
    KarGlyph := Copy(CandAnsi, P + 1, Length(CandAnsi) - P - Suf);
    if KarGlyph <> '' then
    begin
      CandAnsi := ConvCached(Cand) + KarGlyph;
      Ops := AnsiDiffOps(S, CandAnsi);
      BestOps := Ops;
      BestBuf := Cand;
      BestAnsi := CandAnsi;
      BestInk := KarGlyph;
      PeelKar := B[Length(B)];
      HasCand := True;
    end;
  end;

  { 2b. a two-part kar (ো / ৌ) loses its RIGHT half first: ো -> ে, ৌ -> ে }
  if (BestOps > 1) and (Length(B) >= 1) and ((B[Length(B)] = b_Okar) or (B[Length(B)] = b_OUkar)) then
  begin
    Cand := LeftStr(B, Length(B) - 1) + b_Ekar;
    CandAnsi := AnsiSplice(ConvCached(Cand));
    Ops := AnsiDiffOps(S, CandAnsi);
    if Ops < BestOps then
    begin
      BestOps := Ops;
      BestBuf := Cand;
      BestAnsi := CandAnsi;
      BestInk := InkAll;
      PeelKar := '';
      UnwindKar := '';
      BestTwoPart := True;
      HasCand := True;
    end;
  end;

  { 2c. conjunct ladder unwind: [C1 ্ C2 কার] -> [C1 কার ্]
    (জ্বি -> জি্ : the kar steps back in front of the pending hasanta) }
  if (BestOps > 1) and (Length(B) >= 4) and (B[Length(B) - 2] = b_Hasanta) and IsPureConsonent(B[Length(B) - 1]) and
    ((B[Length(B)] = b_Ekar) or (B[Length(B)] = b_Ikar) or (B[Length(B)] = b_OIkar)) and IsPureConsonent(B[Length(B) - 3]) then
  begin
    Cand := LeftStr(B, Length(B) - 3) + B[Length(B)] + b_Hasanta;
    CandAnsi := AnsiSplice(ConvCached(Cand));
    Ops := AnsiDiffOps(S, CandAnsi);
    if Ops < BestOps then
    begin
      BestOps := Ops;
      BestBuf := Cand;
      BestAnsi := CandAnsi;
      BestInk := InkAll;
      PeelKar := '';
      UnwindKar := B[Length(B)];
      BestTwoPart := False;
      HasCand := True;
    end;
  end;

  { 2d. plain suffix deletions - plain letters, whole ligatures,
    post-base kars, a pending hasanta ... }
  for K := 1 to 6 do
  begin
    if (BestOps <= 1) or (Length(B) - K < 0) then
      Break; // cost 1 = "one glyph gone, nothing retyped" - already optimal
    Cand := LeftStr(B, Length(B) - K);
    CandAnsi := AnsiSplice(ConvCached(Cand));
    Ops := AnsiDiffOps(S, CandAnsi);
    if Ops < BestOps then
    begin
      BestOps := Ops;
      BestBuf := Cand;
      BestAnsi := CandAnsi;
      BestInk := InkAll;
      PeelKar := '';
      UnwindKar := '';
      BestTwoPart := False;
      HasCand := True;
    end;
  end;

  { nothing at all is left on screen -> DoBackspace wipes the word and does
    its own bookkeeping (committed context, ResetDeadKey ...) }
  if (not HasCand) or ((BestBuf = '') and (BestInk = '')) then
    Exit;

  { --- 3. apply the winning edit --- }
  if UnwindKar <> '' then
  begin
    { [C1 ্ C2 কার] -> [C1 কার ্] : the conjunct is taken apart and the kar
      steps back in front of the pending hasanta (জ্বি -> জি্) }
    InternalBackspace(3);
    NewBanglaText := NewBanglaText + UnwindKar + b_Hasanta;
    SetLastChar(UnwindKar + b_Hasanta);
  end
  else if BestTwoPart then
  begin
    { ো -> ে  /  ৌ -> ে : drop the two-part kar, put the E-kar back }
    InternalBackspace(1);
    NewBanglaText := NewBanglaText + b_Ekar;
    SetLastChar(b_Ekar);
  end
  else
    InternalBackspace(Length(B) - Length(BestBuf)); // pure tail deletion

  SendAnsiDiff(S, BestAnsi);
  PrevBanglaT := NewBanglaText;

  { --- 4. rebuild the kar press record so it describes the NEW screen --- }
  if UnwindKar <> '' then
  begin
    { the kar is back inside the buffer, in front of the pending hasanta:
      one press, with no ink of its own (the buffer renders it) }
    ClearKarRun;
    PushKarPress(UnwindKar, '');
    ResetAllKarsToInactive;
    ArmPreBaseFlag(UnwindKar);
    KarCanBind := True;
    KarAnchor := NewBanglaText;
    KarAnchorConv := ConvCached(NewBanglaText);
    AnsiMirror := BestAnsi;
    AnsiMirrorActive := False;
  end
  else if PeelKar <> '' then
  begin
    { a freshly peeled kar: it is screen ink again and sits right behind the
      buffer it was peeled off - the next consonant may take it back }
    ClearKarRun;
    PushKarPress(PeelKar, BestInk);
    ResetAllKarsToInactive;
    ArmPreBaseFlag(PeelKar);
    KarCanBind := True;
    KarAnchor := BestBuf;
    KarAnchorConv := ConvCached(BestBuf);
    AnsiMirror := BestAnsi;
    AnsiMirrorActive := True;
  end
  else if BestInk <> '' then
  begin
    { the ink run survived the deletion untouched: the record already holds
      the per-press glyphs and the splice anchor }
    AnsiMirror := BestAnsi;
    AnsiMirrorActive := True;
  end
  else
  begin
    ClearKarRun;
    AnsiMirrorActive := False;
  end;

  Block := True;
  Result := True;
end;

{ =============================================================================== }

procedure TGenericLayoutOld.DoBackspace(var Block: Boolean);
var
  BijoyNewBanglaText: string;
  SavedChar:          string;
  L:                  Integer;
  DeleteCount:        Integer;
  IsRephTail:         Boolean;
  SavedCommitted:     string;
  ArmedKar:           string;
  PrevAnsi, NewAnsi:  string;
begin

  { === Delimiter / isolated-modifier bookkeeping (ANSI contextual engine) === }
  if (NewBanglaText = '') and (PrevBanglaT = '') then
  begin
    // 1. Deleting the space we just inserted: caret becomes directly adjacent
    // to LastCommittedUnicode, so the next modifier must attach cleanly.
    if SpacePendingCount > 0 then
    begin
      Dec(SpacePendingCount);
      if CommittedBanglaT <> '' then
        Delete(CommittedBanglaT, Length(CommittedBanglaT), 1);
      ClearIsoState;
      Block := False; // native backspace removes the delimiter
      Exit;
    end;
    // 2. Deleting an isolated emission: flip the JSON backspace-toggle state
    // (e.g. রু <-> A_UKar4/A_UKar2) so an immediate retype alternates.
    if (LastIsoToggleKey <> '') or (LastIsoContext <> '') then
    begin
      if (LastIsoToggleKey <> '') and (Bijoy <> nil) then
        Bijoy.FlipIsolatedToggle(LastIsoToggleKey);
      ClearIsoState;
      Block := False; // native backspace removes the glyph
      Exit;
    end;
  end;

  { === ANSI VISUAL ORDER (Traditional Style) ===
    The ANSI stream IS the buffer: one backspace pops the LAST GLYPH of the
    visual stream - a plain pop(), no grammatical reordering. Reph and
    phala tails are left to their dedicated rules further down. }
  if (OutputIsBijoy = 'YES') and AnsiVisualPop(Block) then
    Exit;

  { --------------------------------------------------------------------
    OLD STYLE METHOD 1 - a kar that is armed ONLY IN MEMORY.
    One press cancels the pending kar and NOTHING else:
    Unicode - the kar was never emitted, so the press is swallowed and
    the letter typed before it stays:
    মন + ে(memory) + BS -> মন   (next BS -> ম)
    ANSI    - the kar is a streamed glyph, so exactly that glyph goes:
    Kv + [‡] + BS -> Kv
    A kar hidden behind a VISIBLE hasanta is NOT touched here: the hasanta
    is what the user sees, so the normal deletion below removes it and the
    kar stays armed (handled by the ANSI block right after this one).
    -------------------------------------------------------------------- }
  ArmedKar := GetActivePreBaseKar;
  if ((ArmedKar <> '') or (KarInkRun <> '')) and not((PrevBanglaT <> '') and (RightStr(PrevBanglaT, 1) = b_Hasanta)) then
  begin
    { ANSI: the ink of the LAST press is what the user sees going away - pop
      exactly that one glyph (one press = one glyph), even when the run was
      frozen by an earlier symbol. Runs FORWARD / FROZEN are both handled. }
    if IsAnsiClassic and (KarPressN > 0) and (KarPressAns[KarPressN] <> '') and (Length(AnsiMirror) >= Length(KarPressAns[KarPressN])) and
      (RightStr(AnsiMirror, Length(KarPressAns[KarPressN])) = KarPressAns[KarPressN]) then
    begin
      EmitBatch(Length(KarPressAns[KarPressN]), '');
      AnsiMirror := LeftStr(AnsiMirror, Length(AnsiMirror) - Length(KarPressAns[KarPressN]));
      PopKarPress;
      if KarInkRun <> '' then
      begin
        { earlier presses of the run are still on screen }
        AnsiMirrorActive := True;
        Block := True;
        Exit;
      end;
      { the screen equals Convert(PrevBanglaT) again }
      AnsiMirrorActive := False;
      ResetAllKarsToInactive;
      ClearKarRun;
      Block := True;
      Exit;
    end;

    if KarInkRun = '' then
    begin
      { Unicode classic - the kar was never emitted, so the press is swallowed
        and the letter typed before it stays: মন + ে(memory) + BS -> মন }
      AnsiMirror := '';
      AnsiMirrorActive := False;
      ResetAllKarsToInactive;
      ClearKarRun;
      Block := True;
      Exit;
    end;
  end;

  { ANSI: a pending kar whose glyph is already on screen while the VISIBLE
    hasanta is being deleted. Remove the hasanta and keep the kar ink:
    ক + ে + ্  =  K‡~   ->   K‡   (kar still armed, buffer = 'ক') }
  if IsAnsiClassic and (KarInkRun <> '') and (Length(PrevBanglaT) >= 2) and (RightStr(PrevBanglaT, 1) = b_Hasanta) then
  begin
    if AnsiMirrorActive then
      PrevAnsi := AnsiMirror
    else
      PrevAnsi := AnsiSplice(ConvCached(PrevBanglaT));

    InternalBackspace(1); // drop the visible hasanta only
    NewAnsi := AnsiSplice(ConvCached(NewBanglaText));

    SendAnsiDiff(PrevAnsi, NewAnsi);
    PrevBanglaT := NewBanglaText;
    AnsiMirror := NewAnsi;
    AnsiMirrorActive := True;
    Block := True;
    Exit;
  end;

  { --- Reph / Phala tail detection --- }
  IsRephTail := (Length(PrevBanglaT) >= 3) and (PrevBanglaT[Length(PrevBanglaT) - 2] = b_R) and (PrevBanglaT[Length(PrevBanglaT) - 1] = b_Hasanta) and
    IsPureConsonent(PrevBanglaT[Length(PrevBanglaT)]);

  DeleteCount := 1;
  if not IsRephTail then
  begin
    if (Length(PrevBanglaT) >= 3) and ((PrevBanglaT[Length(PrevBanglaT) - 2] = ZWJ) or (PrevBanglaT[Length(PrevBanglaT) - 2] = ZWNJ)) and
      (PrevBanglaT[Length(PrevBanglaT) - 1] = b_Hasanta) and (PrevBanglaT[Length(PrevBanglaT)] = b_Z) then
      DeleteCount := 3
    else if (Length(PrevBanglaT) >= 2) and (PrevBanglaT[Length(PrevBanglaT) - 1] = b_Hasanta) and (PrevBanglaT[Length(PrevBanglaT)] = b_Z) then
      DeleteCount := 2
    else if (Length(PrevBanglaT) >= 2) and (PrevBanglaT[Length(PrevBanglaT) - 1] = b_Hasanta) and (PrevBanglaT[Length(PrevBanglaT)] = b_R) then
      DeleteCount := 2;
  end;

  if (Length(PrevBanglaT) - DeleteCount) <= 0 then
  begin

    if OutputIsBijoy <> 'YES' then
    begin
      if Length(NewBanglaText) >= 1 then
      begin
        EmitBatch(Length(NewBanglaText), '');
        Block := True;
      end
      else if CommittedBanglaT <> '' then
      begin
        L := Length(CommittedBanglaT);
        if (L >= 3) and (CommittedBanglaT[L - 2] = b_R) and (CommittedBanglaT[L - 1] = b_Hasanta) and IsPureConsonent(CommittedBanglaT[L]) then
        begin
          SavedChar := CommittedBanglaT[L];
          EmitBatch(3, SavedChar);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 3) + SavedChar;
          Block := True;
          Exit;
        end;
        { Check for Ya-phala with explicit joiner in committed text }
        if (L >= 4) and ((CommittedBanglaT[L - 3] = ZWJ) or (CommittedBanglaT[L - 3] = ZWNJ)) and (CommittedBanglaT[L - 2] = b_Hasanta) and
          (CommittedBanglaT[L - 1] = b_Z) then
        begin
          EmitBatch(3, '');
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 3);
          Block := True;
          Exit;
        end;
        { Check for Ya-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L - 1] = b_Hasanta) and (CommittedBanglaT[L] = b_Z) and (CommittedBanglaT[L - 2] <> b_R) then
        begin
          EmitBatch(2, '');
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 2);
          Block := True;
          Exit;
        end;
        { Check for Ra-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L - 1] = b_Hasanta) and (CommittedBanglaT[L] = b_R) then
        begin
          EmitBatch(2, '');
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 2);
          Block := True;
          Exit;
        end;
        EmitBatch(1, '');
        CommittedBanglaT := LeftStr(CommittedBanglaT, L - 1);
        Block := True;
        Exit;
      end
      else
        Block := False;
    end
    else
    begin
      { the streamed ink would be orphaned - erase it together with the rest
        of the word (AnsiSplice keeps it in its typed position) }
      BijoyNewBanglaText := AnsiSplice(ConvCached(NewBanglaText));
      if Length(BijoyNewBanglaText) >= 1 then
      begin
        EmitBatch(Length(BijoyNewBanglaText), '');
        Block := True;
      end
      else
        Block := False;
    end;

    SavedCommitted := CommittedBanglaT;
    ResetDeadKey;
    CommittedBanglaT := SavedCommitted;
  end
  else
  begin
    Block := True;
    if IsRephTail then
    begin
      SavedChar := PrevBanglaT[Length(PrevBanglaT)];
      if OutputIsBijoy = 'YES' then
      begin
        EmitBatch(Length(ConvCached(MidStr(PrevBanglaT, Length(PrevBanglaT) - 2, 3))), ConvCached(SavedChar));
      end
      else
      begin
        EmitBatch(3, SavedChar);
      end;
      PrevBanglaT := LeftStr(PrevBanglaT, Length(PrevBanglaT) - 3) + SavedChar;
      NewBanglaText := PrevBanglaT;
      SetLastChar(SavedChar);
      if KarInkRun = '' then
        ClearKarRun; // the deleted reph/phala took the buffer's kar with it
    end
    else
    begin
      { STEPWISE DELETION (GitHub behaviour, identical to the behaviour
        after a space): exactly ONE unit leaves the buffer - one code
        point, or a whole phala / reph tail. The kar-first bookkeeping
        goes away with the deleted text; a kar that is still PENDING (or
        still ink on screen) is deliberately left alone. }
      InternalBackspace(DeleteCount);
      if (GetActivePreBaseKar = '') and (KarInkRun = '') then
        ClearKarRun;
      ParseAndSendNow;
    end;
  end;
end;

{ =============================================================================== }

function TGenericLayoutOld.InsertKar(const sKar: string): string;
begin
  if AutomaticallyFixChandra = 'YES' then
  begin
    // ===================================================================
    // Rule 2: Chandrabindu Active (LastChar = b_Chandra)
    // ===================================================================
    if LastChar = b_Chandra then
    begin
      // Case B: E-kar Ligature with Chandra
      // E-kar + Chandrabindu + AA-kar -> O-kar + Chandra
      // E-kar + Chandrabindu + OU-kar/LengthMark -> OU-kar + Chandra
      if (TrackL >= 2) and (LastChars[2] = b_Ekar) and ((sKar = b_AAkar) or (sKar = b_OUkar) or (sKar = b_LengthMark)) then
      begin
        InternalBackspace(2);
        if sKar = b_AAkar then
          InsertKar := b_Okar + b_Chandra
        else
          InsertKar := b_OUkar + b_Chandra;
        Exit;
      end

      // Case C: Kar after Chandra on completed syllable
      // A kar follows chandrabindu where a kar already exists before it.
      // Simply append the kar after chandrabindu without backspacing.
      else if (TrackL >= 2) and IsKar(LastChars[2]) then
      begin
        InsertKar := sKar;
        Exit;
      end

      // Case D: First Kar after Consonant + Chandra
      // Insert kar before chandrabindu for canonical Unicode ordering.
      else if (TrackL >= 2) and IsPureConsonent(LastChars[2]) then
      begin
        InternalBackspace(1);
        InsertKar := sKar + b_Chandra;
        Exit;
      end

      // Default: Chandrabindu active but no specific pattern matched
      // Fall back to basic chandrabindu reorder
      else
      begin
        InternalBackspace(1);
        InsertKar := sKar + b_Chandra;
        Exit;
      end;
    end
    else
      InsertKar := sKar;
  end
  else
    InsertKar := sKar;

end;

{ =============================================================================== }
{$HINTS Off}

function TGenericLayoutOld.InsertReph: string;
var
  RephMoveable: Boolean;
  TmpStr:       string;
  I, J:         Integer;
begin
  RephMoveable := False;

  if IsPureConsonent(LastChar) = True then
    RephMoveable := True
  else if IsKar(LastChar) = True then
  begin
    if IsPureConsonent(LastChars[2]) then
      RephMoveable := True
    else
      RephMoveable := False;
  end
  else if LastChar = b_Chandra then
  begin
    if IsPureConsonent(LastChars[2]) = True then
      RephMoveable := True
    else if (IsKar(LastChars[2]) = True) and (IsPureConsonent(LastChars[3]) = True) then
      RephMoveable := True
    else
      RephMoveable := False;
  end
  else
    RephMoveable := False;

  if not RephMoveable then
  begin
    InsertReph := b_R + b_Hasanta;
    Exit;
  end
  else
  begin
    I := 1;

    if (IsKar(LastChar) = True) and (IsPureConsonent(LastChars[I + 1]) = True) then
      I := I + 1
    else if LastChar = b_Chandra then
    begin
      if IsPureConsonent(LastChars[I + 1]) = True then
        I := I + 1
      else if (IsKar(LastChars[I + 1]) = True) and (IsPureConsonent(LastChars[I + 2]) = True) then
        I := I + 2;
    end;

    repeat
      if LastChars[I + 1] = b_Hasanta then
      begin
        if IsPureConsonent(LastChars[I + 2]) then
          I := I + 2
        else
        begin
          for J := I downto 1 do
            TmpStr := TmpStr + LastChars[J];

          InternalBackspace(I);
          InsertReph := b_R + b_Hasanta + TmpStr;
          Exit;
        end;
      end
      else
      begin
        for J := I downto 1 do
          TmpStr := TmpStr + LastChars[J];

        InternalBackspace(I);
        InsertReph := b_R + b_Hasanta + TmpStr;
        Exit;
      end;
    until I >= TrackL;

  end;
end;

{ =============================================================================== }

procedure TGenericLayoutOld.InternalBackspace(KeyRepeat: Integer);
begin
  if KeyRepeat <= 0 then
    KeyRepeat := 1;
  if KeyRepeat > TrackL then
    KeyRepeat := TrackL;

  NewBanglaText := MidStr(PrevBanglaT, 1, Length(PrevBanglaT) - KeyRepeat);
  DeleteLastCharSteps_Ex(KeyRepeat);
end;

{$HINTS ON}
{ =============================================================================== }

{
  OLD STYLE: returns the currently floating (armed) pre-base kar
  (ে, ি or ৈ); '' when no reorder is pending.
}
function TGenericLayoutOld.GetActivePreBaseKar: string;
begin
  if EKarActive then
    GetActivePreBaseKar := b_Ekar
  else if IKarActive then
    GetActivePreBaseKar := b_Ikar
  else if OIKarActive then
    GetActivePreBaseKar := b_OIkar
  else
    GetActivePreBaseKar := '';
end;

{ =============================================================================== }

{
  OLD STYLE - METHOD 1 (pure in-memory delayed buffering):
  * A pre-base kar key (ে/ি/ৈ) is NOT emitted at all. It is only ARMED in
  memory (flags + the kar press record). The document shows nothing -
  no dummy characters, no dotted circles, no font switching.
  * The NEXT pure consonant emits  consonant + kar  directly (canonical):
  ি(memory) + দ -> দি,  দ + ি(memory) + ত -> দতি.
  * The SAME kar pressed AGAIN commits: the kar is emitted immediately and
  renders attached to the letter already on screen: ক + ি + ি -> কি.
  Nothing dummy was ever emitted, so committing needs no cleanup.
  * A different kar replaces the pending one (nothing was visible, so
  nothing is lost).
  * ী (II-kar) is a POST-base kar: it clears any pending pre-base state
  and is emitted directly (স+ত+ী+ন -> সতীন).
}
function TGenericLayoutOld.PressPreBaseKar(const KarChar: string): string;
var
  mGlyph: string;

{ the glyph for the DETACHED visual cell, per the ACTIVE mapping:
  - word start (buffer empty): Convert(kar) = A_EKar1/A_OIKar1 form
  - after a letter: the JHULANTA (attached) form. Probe with TWO
  consonants then the kar: the kar's owner is the LAST one and the
  kar renders right after the FIRST consonant's glyph -
  Convert('কর'+ে) = 'K‡v'  ->  middle = '‡'   (V3: 'Köìv' -> 'öì')
  (A single 'ক'+kar can NOT be used: the kar's owner is ক itself and
  the kar travels to the STREAM HEAD there: '†K'.)
  ি has a single form (A_IKar). }
  function StreamGlyph(const AKar: string): string;
  var
    Mid, First, Last: string;
  begin
    if NewBanglaText = '' then
      Result := Bijoy.Convert(AKar)
    else
    begin
      First := Bijoy.Convert(b_K);
      Last := Bijoy.Convert(b_R);
      Mid := Bijoy.Convert(b_K + b_R + AKar);
      if (Length(Mid) > Length(First) + Length(Last)) and (LeftStr(Mid, Length(First)) = First) and (RightStr(Mid, Length(Last)) = Last) then
        Result := Copy(Mid, Length(First) + 1, Length(Mid) - Length(First) - Length(Last))
      else
        Result := Bijoy.Convert(AKar);
    end;
  end;

{ the screen mirror while kar ink is live = the ANSI stream. The FIRST
    glyph of the run also records the SEAM (anchor) the ink belongs to, so
    every later stream can put it back in exactly the typed position. }
  procedure StreamMirrorAppend(const AGlyph: string);
  begin
    if not AnsiMirrorActive then
    begin
      AnsiMirror := ConvCached(PrevBanglaT);
      KarAnchor := PrevBanglaT;
      KarAnchorConv := ConvCached(PrevBanglaT);
      AnsiMirrorActive := True;
    end;
    AnsiMirror := AnsiMirror + AGlyph;
  end;

  { NOTE: the mirror never SHRINKS its ink any more. The old helper existed
    only for "a different kar erases the streamed glyph" and for the ী key
    wiping the pending run - both are gone: ink is frozen, not erased. A
    deletion path that really must take a glyph off the screen emits the
    backspace itself and pops the press (see DoBackspace / HandleIsolated). }

begin
  if KarChar = b_IIkar then
  begin
    { POST-BASE ী: a normal key - it is emitted and the buffer renders it.
      It NEVER erases a pending pre-base run any more: the run is simply
      frozen (still on screen, still poppable) and the ী is typed after it.
      Erasing here is what made one of the kar signs disappear completely. }
    mGlyph := '';
    if KarActive then
    begin
      if IsAnsiClassic then
        FreezeKarRun // the ink is on screen - keep it there, poppable
      else
      begin
        { Unicode: the delayed run was never emitted. COMMIT it - returning
          it makes it real text in front of the ী, exactly like the
          double-press commit. Dropping it here is what made a typed ি
          vanish when ী followed it. }
        mGlyph := KarUniRun;
        ClearKarRun;
      end;
      ResetAllKarsToInactive;
    end;
    PressPreBaseKar := mGlyph + KarChar;
    Exit;
  end;

  { SAME kar again:
    ANSI mode  - ANSI VISUAL ORDER: every keypress is ink, so a second press
    simply types a second kar glyph (a typewriter never de-duplicates). The
    press is remembered, so ONE backspace removes exactly ONE of them.
    Unicode    - COMMIT: emit the kar right away - it renders attached to
    the letter just typed (ক + ি + ি -> কি). The run is released and
    backspace deletes it normally. }
  if GetActivePreBaseKar = KarChar then
  begin
    if IsAnsiClassic then
    begin
      mGlyph := KarPressAns[KarPressN]; // the glyph of THIS kar (before pushing)
      PushKarPress(KarChar, mGlyph);
      StreamMirrorAppend(mGlyph);
      EmitBatch(0, mGlyph);
      PressPreBaseKar := '';
      Exit;
    end;
    ResetAllKarsToInactive;
    ClearKarRun;
    PressPreBaseKar := KarChar; // Unicode: EMIT now - attaches instantly
    Exit;
  end;

  { a DIFFERENT PRE-BASE kar key while a run is live:
    ANSI    - APPEND. Every press is ink and nothing the user typed may
    disappear; the earlier presses stay on screen as frozen ink
    (ক + ে + ি -> K‡w, two poppable presses).
    Unicode - REPLACE the pending one: it was never visible (the classic
    delayed buffer holds it), so replacing it loses nothing the user can
    see. The POST-BASE ী above is the opposite case and COMMITS instead,
    because it is emitted immediately and cannot take the pending slot. }
  if IsAnsiClassic and KarActive then
    FreezeKarRun
  else
    ClearKarRun;

  ResetAllKarsToInactive;
  if KarChar = b_Ekar then
    EKarActive := True
  else if KarChar = b_Ikar then
    IKarActive := True
  else if KarChar = b_OIkar then
    OIKarActive := True;

  KarCanBind := True; // this press is the one a consonant may take
  KarFrozen := False;

  if IsAnsiClassic then
  begin
    { ANSI ZERO-FLICKER VISUAL STREAM: the kar NEVER enters the Unicode
      buffer. Its glyph goes straight to the screen (typewriter stream, left
      to right) with the mapping-correct variant (সাধারণ at a word start,
      ঝুলন্ত after a letter). AnsiMirror carries the screen truth, so when
      the consonant arrives and the syllable binds (করে -> Convert = K‡v) the
      diff APPENDS ONLY the consonant glyph - zero backspaces, zero visual
      jumping. }
    PushKarPress(KarChar, StreamGlyph(KarChar));
    StreamMirrorAppend(KarPressAns[KarPressN]);
    EmitBatch(0, KarPressAns[KarPressN]);
    PressPreBaseKar := '';
    Exit;
  end;

  PushKarPress(KarChar, ''); // Unicode METHOD 1: emit NOTHING
  PressPreBaseKar := '';
end;

{ =============================================================================== }

{
  OLD STYLE: re-arms the active flag of a floating pre-base kar.
  Used when the kar-first state has to be rebuilt after a deletion.
}
procedure TGenericLayoutOld.ArmPreBaseFlag(const KarChar: string);
begin
  ResetAllKarsToInactive;
  if KarChar = b_Ekar then
    EKarActive := True
  else if KarChar = b_Ikar then
    IKarActive := True
  else if KarChar = b_OIkar then
    OIKarActive := True;
end;

{ =============================================================================== }

{
  OLD STYLE: a kar key arrives while a hasanta is pending. The pending
  hasanta is dropped and the vowel letter emitted. Three situations:
  * kar visibly sits before the hasanta, ATTACHED to a consonant
  (করে + ্): drop ONLY the hasanta, keep the kar on its consonant:
  ি(key) -> করে + ই = করেই
  * kar visibly sits before the hasanta, NOT attached (bare/detached):
  drop kar + hasanta, emit just the vowel:  ে + ্ + ি(key) -> ই
  * no visible kar (legacy hidden state): drop the hasanta and
  re-materialize the pending kar in front of the vowel.
}
function TGenericLayoutOld.ResolveHasantaVowelPrefix(const PendingKar: string): string;
begin
  if KarActive and (NewBanglaText <> '') then
  begin
    // kar run (possibly attached) right before the hasanta
    if (Length(NewBanglaText) >= KarPressN + 1) and (RightStr(NewBanglaText, KarPressN + 1) = KarUniRun + b_Hasanta) then
    begin
      if (Length(NewBanglaText) >= KarPressN + 2) and IsPureConsonent(NewBanglaText[Length(NewBanglaText) - KarPressN - 1]) then
      begin
        // ATTACHED (করে + ্): keep the kar on its consonant, drop the hasanta
        InternalBackspace(1);
        // the kar is a real buffer character now - the screen ink (if any) is
        // rendered by the buffer, so it simply stops being a pending press
        ClearKarRun;
        AnsiMirrorActive := False;
        Result := '';
        Exit;
      end
      else
      begin
        // BARE (ে + ্ at word start): drop the whole run + hasanta
        InternalBackspace(KarPressN + 1);
        ClearKarRun;
        AnsiMirrorActive := False;
        Result := '';
        Exit;
      end;
    end;
    // kar pending IN MEMORY behind the hasanta (nothing was visible):
    // drop the hasanta, emit just the independent vowel
    if RightStr(NewBanglaText, 1) = b_Hasanta then
    begin
      InternalBackspace(1);
      ClearKarRun;
      AnsiMirrorActive := False;
      Result := '';
      Exit;
    end;
  end;
  // no pending kar: just drop the hasanta
  InternalBackspace;
  Result := InsertKar(PendingKar);
end;

{ =============================================================================== }

function TGenericLayoutOld.MyProcessVKeyDown(const KeyCode: Integer; var Block: Boolean;
  const var_IsLogicalShift, var_IsTrueShift, var_IsAltGr: Boolean): string;
var
  CharForKey, tmpString, PendingKar: string;
  ArmedKar, LastKar, mKar:           string;
  KarInBuffer:                       Boolean;
  KeepFrozenInk:                     Boolean;
  IsRephTailCtx:                     Boolean;
begin
  KeepFrozenInk := False;

  if not IsBanglaMode then
  begin
    Block := False;
    MyProcessVKeyDown := '';
    Exit;
  end
  else if IsBanglaMode then
  begin
    CharForKey := GetCharForKey(KeyCode, var_IsLogicalShift, var_IsTrueShift, var_IsAltGr);
    if LastChar = b_Hasanta then
    begin
      { OLD STYLE: after a typed reph (র্) a pre-base kar key still floats
        for the coming consonant (ক + র্ + ে + ম -> কর্মে) - BUT only when
        no kar is HIDDEN behind this hasanta. With a hidden kar
        (ক + ে + র + ্, the ে waiting for the reph's consonant) a kar key
        means the INDEPENDENT VOWEL instead: the hidden kar re-attaches and
        the vowel letter follows: ক + ে + র + ্ + ি(key) -> করেই }
      { a reph needs a letter in FRONT of the র:  ক + র্ + ে + ম -> কর্মে.
        At the very beginning of a word "র + ্" is just a consonant with a
        hasanta, so the ordinary "hasanta + kar -> independent vowel" rule
        must win:  র + ্ + ি -> রই  (and not a floating kar).

        A FLOATING kar is only ever wanted for ে / ৈ (the কর্মে pattern).
        The I-kar must stay out of it: a floating ি after "র + ্" has no
        purpose at all - করি is typed ক + র + ি, with no hasanta - so
        after a hasanta the I-kar ALWAYS means the independent vowel:
        দ + র + ্ + ি -> দরই     ক + র + ্ + ি -> করই     (one press)
        (ক + র্ + ে + ম -> কর্মে and ক + ে + র + ্ + ি -> করেই
        are untouched.) }
      IsRephTailCtx := (LastChars[2] = b_R) and (LastChars[3] <> b_Hasanta) and (LastChars[3] <> ' ') and (CharForKey <> b_Ikar);

      if (not IsRephTailCtx) or KarBindable or ((CharForKey <> b_Ekar) and (CharForKey <> b_Ikar) and (CharForKey <> b_OIkar))
      then
      begin

        { chandrabindu sits right before the hasanta: a vowel SIGN must be
          inserted BETWEEN the consonant and the chandrabindu - the sign
          belongs to the syllable, the chandrabindu stays at the end:
          ক + ঁ + ্ + ও -> কোঁ    ক + ঁ + ্ + ঔ -> কৌঁ
          (never কঁো and never a doubled ঁ) }
        if (LastChars[2] = b_Chandra) and ((CharForKey = b_O) or (CharForKey = b_OU) or (CharForKey = b_Okar) or (CharForKey = b_OUkar) or
            (CharForKey = b_LengthMark)) then
        begin
          InternalBackspace(2); // remove ্ and the chandrabindu
          if (CharForKey = b_O) or (CharForKey = b_Okar) then
            mKar := b_Okar
          else
            mKar := b_OUkar;
          ResetAllKarsToInactive;
          ClearKarRun;
          MyProcessVKeyDown := mKar + b_Chandra;
          Exit;
        end;

        if EKarActive then
          PendingKar := b_Ekar
        else if IKarActive then
          PendingKar := b_Ikar
        else if OIKarActive then
          PendingKar := b_OIkar
        else
          PendingKar := '';

        if CharForKey = b_AAkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_AA;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ikar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_I;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_IIkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_II;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ukar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_U;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_UUkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_UU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_RRIkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_RRI;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ekar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_E;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OIkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_OI;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Okar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_O;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_O then
        begin
          // ্ + ও -> ো-কার: drop the hasanta and attach O-kar to the
          // consonant before it (ক + ্ + ও -> কো). This branch lives in
          // the hasanta block, which old style processes unconditionally,
          // so it works no matter what the vowel-format setting is -
          // exactly like the hasanta + kar -> independent vowel rules
          // around it.
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_Okar;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OU then
        begin
          // ্ + ঔ -> ৌ-কার (twin of the rule above): drop the hasanta
          // and attach OU-kar to the consonant before it
          // (ক + ্ + ঔ -> কৌ).
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_OUkar;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OUkar then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_OU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_LengthMark then
        begin
          MyProcessVKeyDown := ResolveHasantaVowelPrefix(PendingKar) + b_OU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Hasanta then
        begin
          if PendingKar <> '' then
          begin
            { a kar is hidden behind this hasanta: swallow the second
              hasanta so the pending conjunct stays intact
              (ক + র্ + ে + ্ + ম -> কর্মে) }
            Block := True;
            MyProcessVKeyDown := '';
            Exit;
          end;
          MyProcessVKeyDown := ZWNJ; // ্ + ্ escape (no kar pending)
          ResetAllKarsToInactive;
          Exit;
        end;

      end;
    end;

    { =====================================================================
      OLD STYLE METHOD 1 - pre-base kars: ে, ি, ী, ৈ
      * A pre-base kar press arms in memory; in ANSI it ALSO joins the
      buffer at once (first press shows, converter-rendered).
      * The NEXT pure consonant emits consonant + kar directly.
      * The SAME kar AGAIN commits AT ONCE: ক + ি + ি -> কি.
      * ী is post-base and is emitted directly.
      ===================================================================== }
    if (CharForKey = b_Ekar) or (CharForKey = b_Ikar) or (CharForKey = b_IIkar) or (CharForKey = b_OIkar) then
    begin
      { NOTE: never read MyProcessVKeyDown in an expression - the bare
        function name on the right side means a recursive CALL in Pascal
        (E2035). Use a local temp instead. }
      mKar := PressPreBaseKar(CharForKey);
      if mKar = '' then
        Block := True; // kar buffered in memory - nothing to emit
      MyProcessVKeyDown := mKar;
      Exit;
    end;

    if CharForKey = b_AAkar then
    begin
      if LastChar = b_Ekar then
      begin
        { a VISIBLE attached ে (consonant-first typing) - replace with ো }
        ResetAllKarsToInactive;
        InternalBackspace(1);
        MyProcessVKeyDown := InsertKar(b_Okar);
        Exit;
      end;
    end;

    if CharForKey = b_LengthMark then
    begin
      if LastChar = b_Ekar then
      begin
        { a VISIBLE attached ে (consonant-first typing) - replace with ৌ }
        ResetAllKarsToInactive;
        InternalBackspace(1);
        MyProcessVKeyDown := InsertKar(b_OUkar);
        Exit;
      end
      else if LastChar = b_Chandra then
      begin
        { ক + ঁ + ৗ -> কৗঁ : the raw AU length mark is placed BEFORE the
          chandrabindu (reorder only - no composition into ৌ) }
        ResetAllKarsToInactive;
        InternalBackspace(1); // remove the chandrabindu
        MyProcessVKeyDown := b_LengthMark + b_Chandra;
        Exit;
      end;
    end;

    if CharForKey = b_Hasanta then
    begin
      if LastChar = b_Ekar then
      begin
        { OLD STYLE: the kar STAYS VISIBLE (typewriter ink). The hasanta
          only marks a pending conjunct while the kar waits for the next
          consonant: করে + ্ shows করে্, and ম completes it to কর্মে }
        if KarPressN = 0 then
          PushKarPress(b_Ekar, ''); // the BUFFER owns this kar - no ink to stream
        ArmPreBaseFlag(b_Ekar);
        KarCanBind := True;
        KarFrozen := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_Ikar then
      begin
        { OLD STYLE: the kar STAYS VISIBLE (typewriter ink) - see b_Ekar }
        if KarPressN = 0 then
          PushKarPress(b_Ikar, '');
        ArmPreBaseFlag(b_Ikar);
        KarCanBind := True;
        KarFrozen := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_OIkar then
      begin
        { OLD STYLE: the kar STAYS VISIBLE (typewriter ink) - see b_Ekar }
        if KarPressN = 0 then
          PushKarPress(b_OIkar, '');
        ArmPreBaseFlag(b_OIkar);
        KarCanBind := True;
        KarFrozen := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = ZWNJ then
      begin
        Block := True;
        MyProcessVKeyDown := '';
        Exit;
      end
      else
      begin
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end;
    end;

    { METHOD 1: a delimiter flushes the pending kar as a standalone
      character BEFORE the delimiter passes through natively }
    if (KeyCode = VK_RETURN) or (KeyCode = VK_SPACE) or (KeyCode = VK_TAB) then
    begin
      ArmedKar := GetActivePreBaseKar;
      if (ArmedKar <> '') and KarActive then
      begin
        if IsAnsiClassic then
        begin
          { ANSI: the streamed glyphs ARE the typed ink and stay before the
            delimiter. Freeze them - nothing is emitted, nothing is erased,
            the screen already shows exactly what the user typed. }
          FreezeKarRun;
          ResetAllKarsToInactive;
        end
        else
        begin
          mKar := KarUniRun;
          ResetAllKarsToInactive;
          ClearKarRun;
          EmitBatch(0, mKar); // visible before the delimiter
          PrevBanglaT := PrevBanglaT + mKar;
          NewBanglaText := PrevBanglaT;
          SetLastChar(mKar);
        end;
      end;
    end;

    case KeyCode of
      VK_RETURN:
        begin
          Block := False;
          CommitContext(PrevBanglaT);
          ResetLastChar;
          MyProcessVKeyDown := '';
          Exit;
        end;
      VK_SPACE:
        begin
          Block := False;
          CommitContext(PrevBanglaT);
          ResetLastChar;          // soft-saves LastCommitted* context
          Inc(SpacePendingCount); // delimiter now sits between caret & context
          MyProcessVKeyDown := '';
          Exit;
        end;
      VK_TAB:
        begin
          Block := False;
          ResetLastChar;
          MyProcessVKeyDown := '';
          Exit;
        end;
      VK_BACK:
        begin
          DoBackspace(Block);
          MyProcessVKeyDown := '';
          Exit;
        end;
      else
        begin
          ArmedKar := GetActivePreBaseKar;

          { OLD STYLE: a kar typed first sits before a pending hasanta
            (জি্). A consonant now completes the conjunct and the kar
            re-forms AFTER it: জি্ + ব -> জ্বি }
          if KarActive and (Length(NewBanglaText) >= KarPressN + 1) and (RightStr(NewBanglaText, KarPressN + 1) = KarUniRun + b_Hasanta) and
            (Length(CharForKey) = 1) and IsPureConsonent(CharForKey) then
          begin
            { Only the LAST kar of the hidden run goes with the consonant;
              earlier copies stay in the buffer before it, in typed order
              (িি + ্ + ব -> ি + ্বি) }
            LastKar := KarPressUni[KarPressN];
            InternalBackspace(2); // visible kar + hasanta (both were emitted)
            if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
              InternalBackspace(1); // absorb an earlier (reph) hasanta into the new conjunct
            ResetAllKarsToInactive; // the kar is SPENT on this consonant - the next
            // consonant must not pull it again
            // (জ্বি + ত -> জ্বিত, NOT জ্বতি)
            ClearKarRun; // consonant consumed the kar - the buffer owns it now
            MyProcessVKeyDown := b_Hasanta + CharForKey + LastKar;
            Exit;
          end;

          if ArmedKar <> '' then
          begin
            { OLD STYLE METHOD 1: a pre-base kar is pending IN MEMORY
              (nothing was emitted for it). Route the incoming key: }
            KarInBuffer := KarCanBind and (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = ArmedKar);

            { ে(memory) + া -> ো   /   ে(memory) + ৗ -> ৌ :
              compose directly - there is no dummy character to delete }
            if (ArmedKar = b_Ekar) and (CharForKey = b_AAkar) then
            begin
              ResetAllKarsToInactive;
              ClearKarRun; // ে+া -> ো composes the streamed glyph away
              AnsiMirrorActive := False;
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
                InternalBackspace(1); // pending hasanta joins the vowel
              MyProcessVKeyDown := b_Okar;
              Exit;
            end
            else if (ArmedKar = b_Ekar) and (CharForKey = b_LengthMark) then
            begin
              ResetAllKarsToInactive;
              ClearKarRun; // ে+ৗ -> ৌ composes the streamed glyph away
              AnsiMirrorActive := False;
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
                InternalBackspace(1);
              MyProcessVKeyDown := b_OUkar;
              Exit;
            end
            else if (Length(CharForKey) = 1) and IsPureConsonent(CharForKey) then
            begin
              { THE NEXT CONSONANT: only the LAST press binds. Earlier
                presses of the run re-appear through Convert in exactly the
                order they were typed, so the stream is a pure APPEND:
                ি ি + ক -> buffer 'িকি' -> Conv 'ििK' = ink + 'K'  (0 BS)
                ি ে + ক -> buffer 'িকে' -> Conv 'ि‡K' = ink + 'K'  (0 BS) }
              ResetAllKarsToInactive;
              KarCanBind := True;
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
              begin
                { hidden behind a pending hasanta: the hasanta joins the
                  new conjunct (ে + ্ + ম -> ্মে, ি + ্ + ব -> ্বি).
                  ANSI: when the run has no ink of its own it is ALSO in the
                  buffer (visible right before the hasanta, e.g. জি্ after a
                  peel) - it joins the conjunct too: জি্ + ব -> জ্বি }
                if IsAnsiClassic and (KarInkRun = '') and (Length(NewBanglaText) >= KarPressN + 1) and
                  (RightStr(NewBanglaText, KarPressN + 1) = KarUniRun + b_Hasanta) then
                  InternalBackspace(KarPressN + 1)
                else
                  InternalBackspace(1);
                MyProcessVKeyDown := KarUniRun(True) + b_Hasanta + CharForKey + ArmedKar;
              end
              else if KarInBuffer then
              begin
                { the tail is an earlier COMMITTED kar (double-press
                  attach, কি - Unicode). It stays attached to its own
                  letter; the pending kar belongs to the NEW consonant:
                  ক + ি + ি + ত -> কি + তি = কিতি }
                MyProcessVKeyDown := CharForKey + ArmedKar;
              end
              else if IsAnsiClassic and (KarPressN > 1) then
              begin
                { ANSI, run of several presses: the earlier presses are
                  ALREADY ink on screen. Only the LAST press binds - the
                  buffer gets consonant + kar (canonical), the earlier marks
                  stay exactly where the user typed them. Pushing them into
                  the buffer would make Convert() pull them in front of the
                  consonant (ReArrangeKars) and force a whole-head erase +
                  retype of the composition. }
                MyProcessVKeyDown := CharForKey + ArmedKar;
                PopKarPress; // the last press is owned by the buffer now
                KeepFrozenInk := KarPressN > 0;
              end
              else
              begin
                { pure in-memory (Unicode / single ANSI press): nothing to
                  delete, nothing was on screen; earlier presses of the run
                  flush before the consonant }
                MyProcessVKeyDown := KarUniRun(True) + CharForKey + ArmedKar;
              end;
              if not KeepFrozenInk then
                ClearKarRun; // consonant owns the screen now
              Exit;
            end
            else if CharForKey = b_R + b_Hasanta then
            begin
              { reph key: Unicode flushes the pending kar standalone
                first, then the reph; ANSI keeps the (visible) ink as-is and
                never duplicates it - the reph is typed after the ink }
              if IsAnsiClassic then
              begin
                mKar := '';
                FreezeKarRun;
              end
              else
              begin
                mKar := KarUniRun;
                ClearKarRun;
              end;
              ResetAllKarsToInactive;
              MyProcessVKeyDown := mKar + InsertReph;
              Exit;
            end
            else if CharForKey = '' then
            begin
              { unmapped key: the word ends here.
                ANSI    - the ink is already on screen as previous-word ink
                (exactly like after a space): freeze it so it stays there and
                stays poppable, then let the record go with the word instead
                of leaving a stale mirror behind.
                Unicode - the delayed run was never emitted: COMMIT it as
                standalone text first, exactly like a space does, so a kar
                typed before the key does not vanish without a trace. }
              if IsAnsiClassic then
                FreezeKarRun
              else if KarActive then
              begin
                mKar := KarUniRun;
                ClearKarRun;
                ResetAllKarsToInactive;
                EmitBatch(0, mKar);
                PrevBanglaT := PrevBanglaT + mKar;
                NewBanglaText := PrevBanglaT;
              end;
              ResetLastChar;
              Block := False;
              MyProcessVKeyDown := '';
              Exit;
            end
            else
            begin
              { NON-CONSONANT (punctuation, digit, vowel letter/sign ...):
                the pending kar run is COMMITTED here, it is never erased.
                Unicode - the delayed run becomes standalone text first
                (ি + '-' -> ি-).
                ANSI    - the glyphs are already ink on screen; they simply
                stop waiting for a consonant, stay poppable, and the key
                follows them - the stream diff is a pure append, so not a
                single SendBackSpace is issued for the aborted sequence. }
              if IsAnsiClassic then
              begin
                FreezeKarRun;
                mKar := '';
              end
              else
              begin
                mKar := KarUniRun;
                ClearKarRun;
              end;
              ResetAllKarsToInactive;
              MyProcessVKeyDown := mKar + CharForKey;
              Exit;
            end;
          end
          else
          begin
            // Block raw English key for all recognized Bangla layout keys.
            // Unmapped keys (CharForKey = '') override this with Block := False below.
            Block := True;
            if CharForKey = b_R + b_Hasanta then
            begin
              MyProcessVKeyDown := InsertReph;
              Exit;
            end
            else if CharForKey = b_AAkar then
            begin
              if LastChar = b_A then
              begin
                InternalBackspace;
                MyProcessVKeyDown := b_AA;
                Exit;
              end
              else
              begin
                MyProcessVKeyDown := InsertKar(b_AAkar);
                Exit;
              end;
            end
            else if CharForKey = b_Hasanta + b_Z then
            begin

              if (LastChar = b_R) and (LastChars[2] <> b_Hasanta) then
              begin
                MyProcessVKeyDown := DetermineZWNJ_ZWJ + b_Hasanta + b_Z;
                Exit;
              end
              else if IsKar(LastChar) then
              begin
                if (LastChars[2] = b_R) and (LastChars[3] <> b_Hasanta) then
                begin
                  tmpString := LastChar;
                  InternalBackspace;
                  MyProcessVKeyDown := DetermineZWNJ_ZWJ + CharForKey + tmpString;
                  Exit;
                end
                else
                begin
                  tmpString := LastChar;
                  InternalBackspace;
                  MyProcessVKeyDown := CharForKey + tmpString;
                  Exit;
                end;
              end
              else
              begin
                MyProcessVKeyDown := b_Hasanta + b_Z;
                Exit;
              end;

            end
            else if CharForKey = '' then
            begin
              ResetLastChar;
              Block := False;
              MyProcessVKeyDown := '';
              Exit;
            end
            else
            begin
              if (Length(CharForKey) > 1) and (LeftStr(CharForKey, 1) = b_Hasanta) then
              begin
                if IsKar(LastChar) then
                begin
                  tmpString := LastChar;
                  InternalBackspace;
                  MyProcessVKeyDown := CharForKey + tmpString;
                  Exit;
                end;
              end;

              if IsKar(CharForKey) then
              begin
                MyProcessVKeyDown := InsertKar(CharForKey);
                Exit;
              end
              else
              begin
                MyProcessVKeyDown := CharForKey;
                Exit;
              end;
            end;
          end;
        end;
    end;
  end;

end;

{ =============================================================================== }

procedure TGenericLayoutOld.MyProcessVKeyUP(const KeyCode: Integer; var Block: Boolean; const var_IsLogicalShift, var_IsTrueShift, var_IsAltGr: Boolean);
var
  CharForKey: string;
begin
  if not IsBanglaMode then
  begin
    Block := False;
    Exit;
  end
  else if IsBanglaMode then
  begin
    CharForKey := GetCharForKey(KeyCode, var_IsLogicalShift, var_IsTrueShift, var_IsAltGr);

    if CharForKey = '' then
    begin
      Block := False;
      Exit;
    end
    else
    begin
      Block := True;
      Exit;
    end;
  end;

end;

{ =============================================================================== }

procedure TGenericLayoutOld.ParseAndSendNow;
var
  Matched, UnMatched:                   Integer;
  BijoyPrevBanglaT, BijoyNewBanglaText: string;
begin
  Matched := 0;

  if OutputIsBijoy <> 'YES' then
  begin
    { Output to Unicode }
    if PrevBanglaT = '' then
    begin
      EmitBatch(0, NewBanglaText);
      PrevBanglaT := NewBanglaText;
    end
    else
    begin
      { OPTIMISED: direct character indexing - MidStr allocates a
        temporary string for every single character of the word }
      while (Matched < Length(PrevBanglaT)) and (Matched < Length(NewBanglaText)) and (PrevBanglaT[Matched + 1] = NewBanglaText[Matched + 1]) do
        Inc(Matched);
      UnMatched := Length(PrevBanglaT) - Matched;

      EmitBatch(UnMatched, Copy(NewBanglaText, Matched + 1, MaxInt));
      PrevBanglaT := NewBanglaText;
    end;

  end
  else
  begin
    { Output to Bijoy }
    { ZERO-FLICKER STREAM: while kar ink is live, the screen mirror is the
      ANSI stream kept by the kar press - the ink is deliberately NOT in the
      Unicode buffer, so Convert(PrevBanglaT) would NOT describe the screen }
    if AnsiMirrorActive then
      BijoyPrevBanglaT := AnsiMirror
    else
      BijoyPrevBanglaT := ConvCached(PrevBanglaT);

    { EVERY stream the buffer produces goes through the ONE splice point, so
      ink typed before the current key keeps the position it was typed at and
      the diff stays append-only:
      ি(ink) + '-'  ->  ি-   with ZERO backspaces, whatever the buffer holds.
      The previous version spliced ONE glyph at the conversion of the CURRENT
      buffer, which sent the whole tail through erase-and-retype as soon as a
      key had been typed after the ink. }
    BijoyNewBanglaText := AnsiSplice(ConvCached(NewBanglaText));

    if KarInkRun <> '' then
    begin
      AnsiMirror := BijoyNewBanglaText;
      AnsiMirrorActive := True;
    end
    else
      AnsiMirrorActive := False; // the stream window closes when the run is empty

    if BijoyPrevBanglaT = '' then
    begin
      EmitBatch(0, BijoyNewBanglaText);
      PrevBanglaT := NewBanglaText;
    end
    else
    begin
      { OPTIMISED: direct character indexing instead of MidStr }
      while (Matched < Length(BijoyPrevBanglaT)) and (Matched < Length(BijoyNewBanglaText)) and
        (BijoyPrevBanglaT[Matched + 1] = BijoyNewBanglaText[Matched + 1]) do
        Inc(Matched);
      UnMatched := Length(BijoyPrevBanglaT) - Matched;

      EmitBatch(UnMatched, Copy(BijoyNewBanglaText, Matched + 1, MaxInt));
      PrevBanglaT := NewBanglaText;
    end;

  end;
end;

{ =============================================================================== }

function TGenericLayoutOld.ProcessVKeyDown(const KeyCode: Integer; var Block: Boolean): string;
var
  m_Block:      Boolean;
  m_Str:        string;
  IsoChainCont: Boolean;
begin
  m_Block := False;
  if (IsWinKey = True) or (IsOnlyCtrlKey = True) or (IsOnlyLeftAltKey = True) then
  begin
    Block := False;
    CommittedBanglaT := '';
    ResetDeadKey;
    ProcessVKeyDown := '';
    Exit;
  end;

  if IsIgnorableModifierKey(KeyCode) then
  begin
    Block := False;
    ProcessVKeyDown := '';
    Exit;
  end;

  m_Str := MyProcessVKeyDown(KeyCode, m_Block, IsLogicalShift, IsTrueShift, IsAltGr);

  // === Isolated Modifier Interception (ANSI contextual engine) ===
  // Kars/phalas/hasanta typed while the word buffer is empty attach to what
  // sits before the caret: the committed context, across our own pending
  // delimiter(s), or a sniffed glyph at an arbitrary document position.
  // When a chained hasanta is pending (e.g. 'ক'+'্' emitted isolated), any
  // single Bangla char continues the conjunct (ক্ষ, ভ্র, ম্ভ্র ...).
  // OLD STYLE: a floating pre-base kar (ে/ি/ী/ৈ just pressed) belongs to the
  // word being typed - never divert it to the isolated engine, so kar-first
  // typing always starts a fresh word. Other modifiers keep old behaviour.
  //
  // KarInkRun = '' is the same rule one step further: ink that has already
  // been STREAMED to the screen (a frozen kar run, e.g. িিিি) is still the
  // word being typed. Without this guard the isolated engine sniffed our own
  // glyph, resolved "glyph + ী" as a replacement and sent one backspace that
  // ate the last ি.
  IsoChainCont := (LastIsoContext <> '') and (RightStr(LastIsoContext, 1) = b_Hasanta) and (Length(m_Str) = 1) and (Ord(m_Str[1]) >= $0980);

  if (m_Str <> '') and (not uCaretContextSniffer.SniffingActive) and (OutputIsBijoy = 'YES') and (NewBanglaText = '') and (GetActivePreBaseKar = '') and
    (KarInkRun = '') and (IsModifierOrJoiner(m_Str) or IsoChainCont) then
  begin
    if HandleIsolatedModifier(m_Str) then
    begin
      SetLastChar(m_Str);
      Block := True;
      ProcessVKeyDown := '';
      Exit;
    end;
  end;

  if (m_Str <> '') then
  begin
    m_Block := True;
    SetLastChar(m_Str);
    IsAtWordBoundary := False;
    ClearIsoState;
    SpacePendingCount := 0;
  end;

  { a streamed kar press returns '' with the glyph already on screen:
    an empty diff here would backspace it - only send when the key
    actually produced text }
  if m_Str <> '' then
  begin
    NewBanglaText := NewBanglaText + m_Str;
    ParseAndSendNow;
  end;

  Block := m_Block;

  { Block = False hands this key to the host, which inserts its character
    itself. We deliberately do NOT drain the deferred emit queue here even
    though a queued glyph would then reach the screen behind that character:
    FlushEmit calls SendInput, and the AVRO_DEFER_EMIT note above explains why
    that must never happen inside the hook callback. The queue is a FIFO that
    the main loop drains microseconds after we return, so the ink is on screen
    before the next keystroke in every realistically reachable case. }

  ProcessVKeyDown := '';
end;

{ =============================================================================== }

procedure TGenericLayoutOld.ProcessVKeyUP(const KeyCode: Integer; var Block: Boolean);
begin
  if (IsWinKey = True) or (IsOnlyCtrlKey = True) or (IsOnlyLeftAltKey = True) then
  begin
    Block := False;
    Exit;
  end;

  if IsIgnorableModifierKey(KeyCode) = True then
  begin
    Block := False;
    Exit;
  end;

  // If BlockedLast Then
  // Block = True
  // Else
  // Block = False
  // End If

  MyProcessVKeyUP(KeyCode, Block, IsLogicalShift, IsTrueShift, IsAltGr);
end;

{ =============================================================================== }

procedure TGenericLayoutOld.ResetAllKarsToInactive;
begin
  EKarActive := False;
  IKarActive := False;
  OIKarActive := False;
end;

{ =============================================================================== }

procedure TGenericLayoutOld.ResetDeadKey;
begin
  ResetLastChar;
end;

{ =============================================================================== }

procedure TGenericLayoutOld.ResetLastChar;
var
  I: Integer;
begin
  { NOTE: on-screen ANSI ink belongs to the word that just ended; the record
    is dropped here, so the glyphs simply stay as previous-word text (exactly
    like a word typed before a space). Callers that still need them (the
    unmapped-key path) freeze them first. }
  // Save committed context before clearing (soft reset)
  if PrevBanglaT <> '' then
  begin
    LastCommittedUnicode := PrevBanglaT;
    if Bijoy <> nil then
    begin
      if OutputIsBijoy = 'YES' then
        LastCommittedAnsi := ConvCached(PrevBanglaT)
      else
        LastCommittedAnsi := PrevBanglaT;
    end;
  end;
  IsAtWordBoundary := True;
  ClearIsoState;
  SpacePendingCount := 0;
  ClearKarRun;
  AnsiMirrorActive := False;
  AnsiMirror := '';
  FConvSrc := ''; // the conversion memo dies with the word
  FConvAnsi := '';

  for I := 1 to TrackL do
    LastChars[I] := ' ';

  LastChar := ' ';
  ResetAllKarsToInactive;
  PrevBanglaT := '';
  NewBanglaText := '';
end;

{ =============================================================================== }

procedure TGenericLayoutOld.ClearIsoState;
begin
  LastIsoContext := '';
  LastIsoToggleKey := '';
end;

{ =============================================================================== }
{
  Attaches an isolated modifier (kar / phala / hasanta) to whatever sits
  before the caret, resolving the exact contextual ANSI glyph for the active
  JSON mapping version. Returns True when the keystroke was fully handled.
}
function TGenericLayoutOld.HandleIsolatedModifier(const ModifierStr: string): Boolean;
var
  Ctx, Sniffed, ResolvedAnsi, MatchedContext, ChainCtx: string;
  CandArr:                                              TAnsiUniCandidates;
  EraseCount:                                           Integer;
  IsToggle, UsedAlt:                                    Boolean;
  Kind:                                                 TSniffResult;
begin
  Result := False;
  if Bijoy = nil then
    Exit;

  { A delimiter the host just typed is a HARD word boundary: a modifier typed
    after it belongs to the NEW word, so nothing may cross the space. Crossing
    it used to erase the space ("space then ে -> attach to the previous word")
    and pull the kar to the left. The hasanta case already refused to cross -
    that rule now covers every modifier, which is the only consistent reading
    of "space = word boundary". SpacePendingCount survives for the backspace
    bookkeeping in DoBackspace. }
  if SpacePendingCount > 0 then
    Exit;

  { Our own streamed ANSI ink is the word being typed, never a foreign
    context: composing over it is what ate the last pre-base kar when a kar
    followed a kar run. }
  if KarInkRun <> '' then
    Exit;

  { --- 1. Establish PrecedingContext --- }
  if LastIsoContext <> '' then
    Ctx := LastIsoContext // chained isolated emission (ক -> ক্ -> ক্র)
  else
  begin
    if not SniffCharBeforeCaret(Sniffed, Kind) then
      Exit;
    case Kind of
      srDelimiter:
        Exit; // foreign space/newline - leave untouched
      srUnicodeChar, srAnsiGlyph:
        Ctx := Sniffed;
      else
        Exit; // nothing resolvable before the caret
    end;
  end;

  { --- 2. Resolve (precompiled map fast path, generic Convert fallback) --- }
  if not Bijoy.ResolveAnsiSequence(Ctx, ModifierStr, ResolvedAnsi, EraseCount, MatchedContext, IsToggle, UsedAlt) then
    Exit;

  { --- 3. Emit with exact diff counts --- }
  if EraseCount > 0 then
    EmitBatch(EraseCount, ''); // replace the default/context glyph
  EmitBatch(0, ResolvedAnsi);

  { --- 4. Track state for chaining and backspace-toggles --- }
  if IsToggle then
    LastIsoToggleKey := MatchedContext + ModifierStr
  else
    LastIsoToggleKey := '';

  ChainCtx := MatchedContext;
  if (ChainCtx <> '') and (Ord(ChainCtx[1]) < $0980) then
  begin
    // ANSI sniff: pick the first candidate cluster for chain bookkeeping;
    // resolution correctness is already handled inside ResolveAnsiSequence.
    CandArr := Bijoy.UnicodeCandidatesOfAnsi(ChainCtx);
    if Length(CandArr) > 0 then
      ChainCtx := CandArr[0]
    else
      ChainCtx := '';
  end;
  if ChainCtx <> '' then
    LastIsoContext := ChainCtx + ModifierStr
  else
    LastIsoContext := '';

  IsAtWordBoundary := False;
  Result := True;
end;

{ =============================================================================== }

{
  OPTIMISED (hot path - runs on EVERY keystroke).
  The old version rebuilt two TrackL-character strings: ~100 concatenations
  (each one re-allocates and copies) plus ~100 MidStr temporaries - about
  200 heap allocations per keypress. The slots are only SHIFTED here: plain
  reference moves, zero allocations, same result.
  Slot 1 = newest character, slot TrackL = oldest (unchanged).
}
procedure TGenericLayoutOld.SetLastChar(const wChar: string);
var
  I, N: Integer;
begin
  N := Length(wChar);
  if N <= 0 then
    Exit;

  if N >= TrackL then
  begin
    { the new text alone fills the whole window }
    for I := 1 to TrackL do
      LastChars[I] := wChar[N - I + 1];
    LastChar := LastChars[1];
    Exit;
  end;

  { older characters move towards the oldest end (slot TrackL) }
  for I := TrackL downto N + 1 do
    LastChars[I] := LastChars[I - N];

  { the new characters land in slots N .. 1 (the last one in slot 1) }
  for I := 1 to N do
    LastChars[I] := wChar[N - I + 1];

  LastChar := LastChars[1];
end;

{ =============================================================================== }

end.
