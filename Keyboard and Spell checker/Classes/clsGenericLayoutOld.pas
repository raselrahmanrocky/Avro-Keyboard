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
  * different kar pressed    -> replaces the pending one (nothing was
  visible, so nothing is lost)
  * non-consonant key (digit, punctuation, vowel letter/sign) or a
  delimiter (space/enter/tab) -> the pending kar is flushed as a
  standalone character first, then the key is processed (ি + '-' -> ি-)
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

      // OLD STYLE backspace un-reorder state:
      KarFirstKar:    string;  // pre-base kar that was typed BEFORE its consonant
      UnwindConjunct: Boolean; // last join completed a conjunct after [kar ্] (জি্ + ব -> জ্বি)
      KarConsumed:    Boolean; // KarFirstKar was reordered onto its consonant (True) vs still floating (False)
      KarRunCount:    Integer; // copies in the current kar-first run (floating OR consumed)

      // ANSI ZERO-FLICKER VISUAL STREAM: a pending pre-base kar is NOT in
      // the Unicode buffer - its glyph is streamed straight to the screen
      // and AnsiMirror holds the screen truth until the syllable binds
      AnsiMirrorActive: Boolean; // True while a streamed kar is pending
      AnsiMirror:       string;  // ANSI stream rendered so far (screen mirror)
      KarAnsiGlyph:     string;  // the glyph(s) streamed for the pending kar

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
      procedure ClearKarFirstState;
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
  end;

implementation

uses
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
  OPTIONAL PERFORMANCE PROFILER
  -------------------------------------------------------------------------------
  The lag is NOT necessarily in this unit, so measure instead of guessing.
  Every keystroke is timed and split into:

  GetCharForKey   - layout lookup            (KeyboardLayoutLoader)
  Bijoy.Convert  - Unicode -> ANSI          (clsUnicodeToBijoy2000)
  ParseAndSendNow- full output step (includes its own send calls)
  send+other     - the rest: SendKey_Char / Backspace (synthetic input),
  caret sniffing, ...

  Results go to the debugger (OutputDebugString - read them with SysInternals
  DebugView, or in the Delphi IDE's "Event Log" while debugging), dumped after
  every 100 keystrokes.

  Turn it OFF for the release build by commenting out the AVRO_PROFILE
  DEFINE line below.
  =============================================================================== }
{$DEFINE AVRO_PROFILE}
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
  {$IFDEF AVRO_PROFILE}
function QueryPerformanceCounter(var lpPerformanceCount: Int64): LongBool; stdcall; external 'kernel32.dll' name 'QueryPerformanceCounter';
function QueryPerformanceFrequency(var lpFrequency: Int64): LongBool; stdcall; external 'kernel32.dll' name 'QueryPerformanceFrequency';
procedure OutputDebugStringA(lpOutputString: PAnsiChar); stdcall; external 'kernel32.dll' name 'OutputDebugStringA';
function PostMessageW(hWnd: NativeUInt; Msg: Cardinal; wParam: NativeUInt; lParam: NativeInt): LongBool; stdcall; external 'user32.dll' name 'PostMessageW';

var
  ProfFreq:      Int64   = 0;
  ProfKeys:      Integer = 0;
  ProfTickTotal: Int64   = 0;
  ProfTickKey:   Int64   = 0;
  ProfTickConv:  Int64   = 0;
  ProfTickParse: Int64   = 0;
  ProfCallsConv: Integer = 0;
  ProfEmitted:   Integer = 0; // backspaces + characters pushed into the queue
  ProfMaxErase:  Integer = 0; // worst single erase (big = retyping churn)
  ProfTickSend:  Int64   = 0; // time spent INSIDE SendInput
  ProfSendCalls: Integer = 0; // how many SendInput calls per keystroke

function ProfTicks: Int64;
begin
  QueryPerformanceCounter(Result);
end;

{ average milliseconds per keystroke for every counter }
procedure ProfDump;
var
  K, MS: Double;

  procedure Say(const Line: string);
  begin
    OutputDebugStringA(PAnsiChar(AnsiString(Line)));
  end;

begin
  if ProfFreq = 0 then
    QueryPerformanceFrequency(ProfFreq);
  if (ProfFreq = 0) or (ProfKeys = 0) then
    Exit;

  K := ProfKeys;
  Say('=== Avro profile: ' + IntToStr(ProfKeys) + ' keys ===');
  MS := ProfTickTotal / ProfFreq * 1000.0 / K;
  Say(Format('  TOTAL per key     : %8.3f ms', [MS]));
  MS := ProfTickKey / ProfFreq * 1000.0 / K;
  Say(Format('  GetCharForKey     : %8.3f ms', [MS]));
  MS := ProfTickParse / ProfFreq * 1000.0 / K;
  Say(Format('  ParseAndSendNow   : %8.3f ms', [MS]));
  MS := ProfTickConv / ProfFreq * 1000.0 / K;
  Say(Format('  Bijoy.Convert     : %8.3f ms   (%d calls/key)', [MS, Round(ProfCallsConv / K)]));
  MS := (ProfTickTotal - ProfTickKey - ProfTickParse) / ProfFreq * 1000.0 / K;
  Say(Format('  send + everything : %8.3f ms', [MS]));
  Say(Format('  INJECTED events   : %6.2f per key   (worst erase = %d)', [ProfEmitted / K, ProfMaxErase]));
  MS := ProfTickSend / ProfFreq * 1000.0 / K;
  Say(Format('  SendInput         : %8.3f ms   (%.2f calls/key, %.3f ms each) DEFERRED', [MS, ProfSendCalls / K, MS / (ProfSendCalls / K)]));
  { SendInput no longer runs inside ParseAndSendNow (AVRO_DEFER_EMIT), so it
    must NOT be subtracted here - that produced a negative number. }
  MS := ProfTickParse / ProfFreq * 1000.0 / K;
  Say(Format('  diff + string ops : %8.3f ms   (queue fill only)', [MS]));

  ProfKeys := 0;
  ProfTickTotal := 0;
  ProfTickKey := 0;
  ProfTickConv := 0;
  ProfTickParse := 0;
  ProfCallsConv := 0;
  ProfEmitted := 0;
  ProfMaxErase := 0;
  ProfTickSend := 0;
  ProfSendCalls := 0;
end;
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
  KarFirstKar := '';
  UnwindConjunct := False;
  KarConsumed := False;
  KarRunCount := 0;
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
  OLD STYLE: drops the kar-first bookkeeping only (the armed kar flags are
  kept separately, so a kar that is still pending is never lost by a
  deletion).
}
procedure TGenericLayoutOld.ClearKarFirstState;
begin
  KarFirstKar := '';
  UnwindConjunct := False;
  KarConsumed := False;
  KarRunCount := 0;
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
{$IFDEF AVRO_PROFILE}
var
  tProf: Int64;
  {$ENDIF}
begin
  {$IFDEF AVRO_PROFILE}
  tProf := ProfTicks;
  Inc(ProfCallsConv);
  {$ENDIF}
  if (T <> '') and (T = FConvSrc) then
    Result := FConvAnsi
  else
  begin
    Result := Bijoy.Convert(T);
    FConvSrc := T;
    FConvAnsi := Result;
  end;
  {$IFDEF AVRO_PROFILE}
  Inc(ProfTickConv, ProfTicks - tProf);
  {$ENDIF}
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
  skips the per-character Log() that SendKey_Char does (disk I/O on every
  character was a large part of the 4.35 ms ParseAndSendNow measurement).

  A whole "erase + retype" is emitted ATOMICALLY, so fast typing can no longer
  interleave with it - that is what produced the "everything appears at once"
  effect.
}
procedure TGenericLayoutOld.EmitBatch(const EraseCount: Integer; const Text: string);
{$IFDEF AVRO_PROFILE}
var
  tProf: Int64;
  {$ENDIF}
begin
  if (EraseCount <= 0) and (Text = '') then
    Exit;
  {$IFDEF AVRO_PROFILE}
  Inc(ProfEmitted, EraseCount + Length(Text));
  if EraseCount > ProfMaxErase then
    ProfMaxErase := EraseCount;
  {$ENDIF}
  {$IFDEF AVRO_DEFER_EMIT}
  if FEmitN >= Length(FEmitQ) then
    SetLength(FEmitQ, FEmitN + 32);
  FEmitQ[FEmitN].EraseCount := EraseCount;
  FEmitQ[FEmitN].Text := Text;
  Inc(FEmitN);
  { Runs after the hook callback returned - see the AVRO_DEFER_EMIT note. }
  PostMessageW(NativeUInt(AvroMainForm1.Handle), WM_AVRO_EMIT, 0, 0);
  {$ELSE}
  {$IFDEF AVRO_PROFILE}
  tProf := ProfTicks;
  Inc(ProfSendCalls);
  {$ENDIF}
  SendInputBatch_BackspaceAndChar(EraseCount, Text);
  {$IFDEF AVRO_PROFILE}
  Inc(ProfTickSend, ProfTicks - tProf);
  {$ENDIF}
  {$ENDIF}
end;

{ Drains the deferred output queue. Called from the main form's WM_AVRO_EMIT
  handler, i.e. OUTSIDE the low-level keyboard hook callback. }
procedure TGenericLayoutOld.FlushEmit;
var
  I: Integer;
  {$IFDEF AVRO_PROFILE}
  tProf: Int64;
  {$ENDIF}
begin
  for I := 0 to FEmitN - 1 do
  begin
    {$IFDEF AVRO_PROFILE}
    tProf := ProfTicks;
    Inc(ProfSendCalls);
    {$ENDIF}
    SendInputBatch_BackspaceAndChar(FEmitQ[I].EraseCount, FEmitQ[I].Text);
    {$IFDEF AVRO_PROFILE}
    Inc(ProfTickSend, ProfTicks - tProf);
    {$ENDIF}
  end;
  FEmitN := 0;
end;

{ =============================================================================== }

{ ANSI: the whole pending kar run exactly as it sits on screen - the glyph
  of one copy repeated KarRunCount times (a kar key may be pressed several
  times in a row: every press is ink). }
function TGenericLayoutOld.KarInkRun: string;
begin
  if (KarAnsiGlyph = '') or (KarRunCount < 1) then
    Result := ''
  else
    Result := DupeString(KarAnsiGlyph, KarRunCount);
end;

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

  { ink of a kar that is still pending (its Unicode is NOT in the buffer).
    Ink     = the glyph of ONE copy  - step 1 pops exactly one glyph
    InkAll  = the whole run          - what the candidate streams must show }
  if (GetActivePreBaseKar <> '') and (not KarConsumed) then
  begin
    Ink := KarAnsiGlyph;
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
    if KarRunCount > 1 then
    begin
      Dec(KarRunCount); // one copy is gone - the kar stays armed
      AnsiMirrorActive := True;
    end
    else
    begin
      KarAnsiGlyph := '';
      AnsiMirrorActive := False;
      ResetAllKarsToInactive;
      ClearKarFirstState;
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
    KarAnsiGlyph := '';
    AnsiMirrorActive := False;
    ClearKarFirstState;
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
    CandAnsi := ConvCached(Cand) + InkAll;
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
    CandAnsi := ConvCached(Cand) + InkAll;
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
    CandAnsi := ConvCached(Cand) + InkAll;
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

  if BestInk <> '' then
  begin
    if (PeelKar = '') and (UnwindKar = '') then
      { the pending kar run survives untouched: KarAnsiGlyph still holds
        the glyph of ONE copy and KarRunCount the number of copies }
    else
      KarAnsiGlyph := BestInk; // a freshly peeled kar = a single copy
    AnsiMirror := BestAnsi;
    AnsiMirrorActive := True;
  end
  else
  begin
    KarAnsiGlyph := '';
    AnsiMirrorActive := False;
  end;

  if PeelKar <> '' then
  begin
    { the kar is pending again - the next consonant takes it back }
    ResetAllKarsToInactive;
    ArmPreBaseFlag(PeelKar);
    KarFirstKar := PeelKar;
    KarConsumed := False;
    KarRunCount := 1;
  end
  else if UnwindKar <> '' then
  begin
    { the kar is back inside the buffer, in front of the pending hasanta }
    ResetAllKarsToInactive;
    ArmPreBaseFlag(UnwindKar);
    KarFirstKar := UnwindKar;
    KarConsumed := False;
    KarRunCount := 1;
    KarAnsiGlyph := '';
  end
  else if BestInk = '' then
    ClearKarFirstState;

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
  if (ArmedKar <> '') and (not KarConsumed) and not((PrevBanglaT <> '') and (RightStr(PrevBanglaT, 1) = b_Hasanta)) then
  begin
    if (OutputIsBijoy = 'YES') and (KarAnsiGlyph <> '') then
    begin
      EmitBatch(Length(KarAnsiGlyph), ''); // one glyph of the run
      if KarRunCount > 1 then
      begin
        Dec(KarRunCount); // kar stays armed - one copy left
        if (AnsiMirror <> '') and (Length(AnsiMirror) >= Length(KarAnsiGlyph)) then
          AnsiMirror := LeftStr(AnsiMirror, Length(AnsiMirror) - Length(KarAnsiGlyph));
        Block := True;
        Exit;
      end;
      KarAnsiGlyph := '';
    end;
    { the screen now equals Convert(PrevBanglaT) again - no mirror needed }
    AnsiMirror := '';
    AnsiMirrorActive := False;
    ResetAllKarsToInactive;
    ClearKarFirstState;
    Block := True;
    Exit;
  end;

  { ANSI: a pending kar whose glyph is already on screen while the VISIBLE
    hasanta is being deleted. Remove the hasanta and keep the kar ink:
    ক + ে + ্  =  K‡~   ->   K‡   (kar still armed, buffer = 'ক') }
  if (OutputIsBijoy = 'YES') and (KarAnsiGlyph <> '') and (Length(PrevBanglaT) >= 2) and (RightStr(PrevBanglaT, 1) = b_Hasanta) then
  begin
    if AnsiMirrorActive then
      PrevAnsi := AnsiMirror
    else
      PrevAnsi := ConvCached(PrevBanglaT) + KarAnsiGlyph;

    InternalBackspace(1); // drop the visible hasanta only
    NewAnsi := Bijoy.Convert(NewBanglaText) + KarAnsiGlyph;

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
      BijoyNewBanglaText := ConvCached(NewBanglaText);
      { a streamed kar glyph would be orphaned - erase it together with
        the last letter of the word }
      if KarAnsiGlyph <> '' then
        BijoyNewBanglaText := BijoyNewBanglaText + KarAnsiGlyph;
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
      ClearKarFirstState;
    end
    else
    begin
      { STEPWISE DELETION (GitHub behaviour, identical to the behaviour
        after a space): exactly ONE unit leaves the buffer - one code
        point, or a whole phala / reph tail. The kar-first bookkeeping
        goes away with the deleted text; a kar that is still PENDING is
        deliberately left alone. }
      InternalBackspace(DeleteCount);
      if GetActivePreBaseKar = '' then
        ClearKarFirstState;
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
  memory (flags + KarFirstKar/KarRunCount). The document shows nothing -
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

{ the screen mirror while the kar is pending = the ANSI stream }
  procedure StreamMirrorAppend(const AGlyph: string);
  begin
    if not AnsiMirrorActive then
    begin
      AnsiMirror := ConvCached(PrevBanglaT);
      AnsiMirrorActive := True;
    end;
    AnsiMirror := AnsiMirror + AGlyph;
  end;

  procedure StreamMirrorShrink(const AGlyph: string);
  begin
    if AnsiMirrorActive and (Length(AnsiMirror) >= Length(AGlyph)) then
    begin
      AnsiMirror := LeftStr(AnsiMirror, Length(AnsiMirror) - Length(AGlyph));
      if AnsiMirror = ConvCached(PrevBanglaT) then
        AnsiMirrorActive := False;
    end;
  end;

begin
  if KarChar = b_IIkar then
  begin
    { POST-BASE ী: direct emit; erase a pending STREAMED kar glyph first
      or it orphans on screen before ী }
    if (OutputIsBijoy = 'YES') and (GetActivePreBaseKar <> '') and (not KarConsumed) and (KarAnsiGlyph <> '') then
    begin
      EmitBatch(Length(KarInkRun), ''); // the WHOLE run is on screen
      StreamMirrorShrink(KarInkRun);
      KarAnsiGlyph := '';
    end;
    ResetAllKarsToInactive;
    ClearKarFirstState;
    PressPreBaseKar := KarChar;
    Exit;
  end;

  { SAME kar again:
    ANSI mode  - ANSI VISUAL ORDER: every keypress is ink, so a second
    press simply types a second kar glyph (a typewriter never
    de-duplicates). The run is remembered (KarRunCount) - the next
    consonant takes the LAST copy and the earlier ones stay in the
    stream exactly where they were typed.
    Unicode    - COMMIT: emit the kar right away - it renders attached to
    the letter just typed (ক + ি + ি -> কি). ALL kar-first
    state is cleared and backspace deletes it normally. }
  if GetActivePreBaseKar = KarChar then
  begin
    if OutputIsBijoy = 'YES' then
    begin
      Inc(KarRunCount);                 // one more copy is on screen
      StreamMirrorAppend(KarAnsiGlyph); // same glyph - typed again
      EmitBatch(0, KarAnsiGlyph);
      PressPreBaseKar := '';
      Exit;
    end;
    ResetAllKarsToInactive;
    ClearKarFirstState;
    PressPreBaseKar := KarChar; // Unicode: EMIT now - attaches instantly
    Exit;
  end;

  ResetAllKarsToInactive;
  if KarChar = b_Ekar then
    EKarActive := True
  else if KarChar = b_Ikar then
    IKarActive := True
  else if KarChar = b_OIkar then
    OIKarActive := True;

  KarFirstKar := KarChar; // remembered for backspace un-reorder
  UnwindConjunct := False;
  KarConsumed := False; // pending - no consonant took it yet
  KarRunCount := 1;     // one copy

  if OutputIsBijoy = 'YES' then
  begin
    { ANSI ZERO-FLICKER VISUAL STREAM: the kar NEVER enters the Unicode
      buffer. Its glyph goes straight to the screen (typewriter stream,
      left to right) with the mapping-correct variant (সাধারণ at a word
      start, ঝুলন্ত after a letter). A DIFFERENT pending kar first erases
      its streamed glyph in place (ক [ে] -> ক [ি]). AnsiMirror carries
      the screen truth, so when the consonant arrives and the syllable
      binds (করে -> Convert = K‡v), the diff against K‡ appends ONLY the
      consonant glyph - zero backspaces, zero visual jumping. }
    if KarAnsiGlyph <> '' then
    begin
      EmitBatch(Length(KarInkRun), ''); // wipe every copy of the other kar
      StreamMirrorShrink(KarInkRun);
    end;
    KarAnsiGlyph := StreamGlyph(KarChar);
    StreamMirrorAppend(KarAnsiGlyph);
    EmitBatch(0, KarAnsiGlyph);
    PressPreBaseKar := '';
    Exit;
  end;
  PressPreBaseKar := ''; // Unicode METHOD 1: emit NOTHING
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
  if (KarFirstKar <> '') and (not KarConsumed) and (NewBanglaText <> '') then
  begin
    // kar run (possibly attached) right before the hasanta
    if (Length(NewBanglaText) >= KarRunCount + 1) and (RightStr(NewBanglaText, KarRunCount + 1) = DupeString(KarFirstKar, KarRunCount) + b_Hasanta) then
    begin
      if (Length(NewBanglaText) >= KarRunCount + 2) and IsPureConsonent(NewBanglaText[Length(NewBanglaText) - KarRunCount - 1]) then
      begin
        // ATTACHED (করে + ্): keep the kar on its consonant, drop the hasanta
        InternalBackspace(1);
        KarConsumed := True;
        KarAnsiGlyph := ''; // reset so next kar won't issue false backspace
        KarRunCount := 1;
        UnwindConjunct := False;
        Result := '';
        Exit;
      end
      else
      begin
        // BARE (ে + ্ at word start): drop the whole run + hasanta
        InternalBackspace(KarRunCount + 1);
        ClearKarFirstState;
        Result := '';
        Exit;
      end;
    end;
    // kar pending IN MEMORY behind the hasanta (nothing was visible):
    // drop the hasanta, emit just the independent vowel
    if RightStr(NewBanglaText, 1) = b_Hasanta then
    begin
      InternalBackspace(1);
      ClearKarFirstState;
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
  ArmedKar, mKar:                    string;
  KarInBuffer:                       Boolean;
  IsRephTailCtx:                     Boolean;
  {$IFDEF AVRO_PROFILE}
  tProf: Int64;
  {$ENDIF}
begin

  if AvroMainForm1.GetMyCurrentKeyboardMode = SysDefault then
  begin

    Block := False;
    MyProcessVKeyDown := '';
    Exit;
  end
  else if AvroMainForm1.GetMyCurrentKeyboardMode = bangla then
  begin
    {$IFDEF AVRO_PROFILE}
    tProf := ProfTicks;
    {$ENDIF}
    CharForKey := GetCharForKey(KeyCode, var_IsLogicalShift, var_IsTrueShift, var_IsAltGr);
    {$IFDEF AVRO_PROFILE}
    Inc(ProfTickKey, ProfTicks - tProf);
    {$ENDIF}
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

      if (not IsRephTailCtx) or ((KarFirstKar <> '') and (not KarConsumed)) or ((CharForKey <> b_Ekar) and (CharForKey <> b_Ikar) and (CharForKey <> b_OIkar))
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
          ClearKarFirstState;
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
        EKarActive := True;
        KarFirstKar := b_Ekar;
        UnwindConjunct := False;
        KarConsumed := False; // reserved for the next consonant
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_Ikar then
      begin
        { OLD STYLE: the kar STAYS VISIBLE (typewriter ink) - see b_Ekar }
        IKarActive := True;
        KarFirstKar := b_Ikar;
        UnwindConjunct := False;
        KarConsumed := False; // reserved for the next consonant
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_OIkar then
      begin
        { OLD STYLE: the kar STAYS VISIBLE (typewriter ink) - see b_Ekar }
        OIKarActive := True;
        KarFirstKar := b_OIkar;
        UnwindConjunct := False;
        KarConsumed := False; // reserved for the next consonant
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
      if (ArmedKar <> '') and (not KarConsumed) then
      begin
        if OutputIsBijoy = 'YES' then
        begin
          { ANSI: the streamed kar glyph stays as typed ink before the
            delimiter - just disarm (the mirrors reset with the word) }
          ResetAllKarsToInactive;
          ClearKarFirstState;
          KarAnsiGlyph := '';
        end
        else
        begin
          mKar := DupeString(ArmedKar, KarRunCount);
          ResetAllKarsToInactive;
          ClearKarFirstState;
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
          if (KarFirstKar <> '') and (KarRunCount >= 1) and (Length(NewBanglaText) >= KarRunCount + 1) and
            (RightStr(NewBanglaText, KarRunCount + 1) = DupeString(KarFirstKar, KarRunCount) + b_Hasanta) and (Length(CharForKey) = 1) and
            IsPureConsonent(CharForKey) then
          begin
            { Only the LAST kar of the hidden run goes with the consonant;
              earlier copies stay in the buffer before it, in typed order
              (িি + ্ + ব -> ি + ্বি) }
            InternalBackspace(2); // visible kar + hasanta (both were emitted)
            if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
              InternalBackspace(1); // absorb an earlier (reph) hasanta into the new conjunct
            ResetAllKarsToInactive; // the kar is SPENT on this consonant - the next
            // consonant must not pull it again
            // (জ্বি + ত -> জ্বিত, NOT জ্বতি)
            UnwindConjunct := True;
            KarConsumed := True;
            KarRunCount := 1;
            KarAnsiGlyph := ''; // reset: consonant consumed the kar
            MyProcessVKeyDown := b_Hasanta + CharForKey + KarFirstKar;
            Exit;
          end;

          if ArmedKar <> '' then
          begin
            { OLD STYLE METHOD 1: a pre-base kar is pending IN MEMORY
              (nothing was emitted for it). Route the incoming key: }
            KarInBuffer := (not KarConsumed) and (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = ArmedKar);

            { ে(memory) + া -> ো   /   ে(memory) + ৗ -> ৌ :
              compose directly - there is no dummy character to delete }
            if (ArmedKar = b_Ekar) and (CharForKey = b_AAkar) then
            begin
              ResetAllKarsToInactive;
              ClearKarFirstState;
              KarAnsiGlyph := ''; // ে+া -> ো composes the streamed glyph away
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
                InternalBackspace(1); // pending hasanta joins the vowel
              MyProcessVKeyDown := b_Okar;
              Exit;
            end
            else if (ArmedKar = b_Ekar) and (CharForKey = b_LengthMark) then
            begin
              ResetAllKarsToInactive;
              ClearKarFirstState;
              KarAnsiGlyph := ''; // ে+ৗ -> ৌ composes the streamed glyph away
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
                InternalBackspace(1);
              MyProcessVKeyDown := b_OUkar;
              Exit;
            end
            else if (Length(CharForKey) = 1) and IsPureConsonent(CharForKey) then
            begin
              { THE NEXT CONSONANT: emit consonant + kar in canonical order.
                The kar becomes visible for the first time, already attached. }
              ResetAllKarsToInactive;
              KarFirstKar := ArmedKar; { consumed by this reorder - remembered for un-reorder }
              KarConsumed := True;
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
              begin
                { hidden behind a pending hasanta: the hasanta joins the
                  new conjunct (ে + ্ + ম -> ্মে, ি + ্ + ব -> ্বি).
                  ANSI: the kar is ALSO in the buffer (visible ink right
                  before the hasanta, e.g. জি্ after a peel) - it joins
                  the conjunct too: জি্ + ব -> জ্বি }
                if (OutputIsBijoy = 'YES') and (Length(NewBanglaText) >= KarRunCount + 1) and
                  (RightStr(NewBanglaText, KarRunCount + 1) = DupeString(ArmedKar, KarRunCount) + b_Hasanta) then
                  InternalBackspace(KarRunCount + 1)
                else
                  InternalBackspace(1);
                UnwindConjunct := True;
                MyProcessVKeyDown := DupeString(ArmedKar, KarRunCount - 1) + b_Hasanta + CharForKey + ArmedKar;
              end
              else if KarInBuffer then
              begin
                { the tail is an earlier COMMITTED kar (double-press
                  attach, কি - Unicode). It stays attached to its own
                  letter; the pending kar belongs to the NEW consonant:
                  ক + ি + ি + ত -> কি + তি = কিতি }
                UnwindConjunct := False;
                MyProcessVKeyDown := CharForKey + ArmedKar;
              end
              else
              begin
                { pure in-memory: nothing to delete, nothing was on screen;
                  earlier copies of the run flush before the consonant }
                UnwindConjunct := False;
                MyProcessVKeyDown := DupeString(ArmedKar, KarRunCount - 1) + CharForKey + ArmedKar;
              end;
              KarAnsiGlyph := ''; // reset: consonant owns the screen now
              KarRunCount := 1;
              Exit;
            end
            else if CharForKey = b_R + b_Hasanta then
            begin
              { reph key: Unicode flushes the pending kar standalone
                first, then the reph; ANSI keeps the buffered (visible)
                kar as-is and never duplicates it }
              if OutputIsBijoy = 'YES' then
                mKar := ''
              else
                mKar := DupeString(ArmedKar, KarRunCount);
              ResetAllKarsToInactive;
              ClearKarFirstState;
              MyProcessVKeyDown := mKar + InsertReph;
              Exit;
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
              { NON-CONSONANT (punctuation, digit, vowel letter/sign ...):
                Unicode flushes the pending kar as a standalone character
                first (ি + '-' -> ি-). ANSI: the kar is ALREADY in the
                buffer (visible ink) - never duplicate it, just the key }
              if OutputIsBijoy = 'YES' then
                mKar := ''
              else
                mKar := DupeString(ArmedKar, KarRunCount);
              ResetAllKarsToInactive;
              ClearKarFirstState;
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
  if AvroMainForm1.GetMyCurrentKeyboardMode = SysDefault then
  begin
    Block := False;
    Exit;
  end
  else if AvroMainForm1.GetMyCurrentKeyboardMode = bangla then
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
  PrevConv:                             string;
  {$IFDEF AVRO_PROFILE}
  tProf: Int64;
  {$ENDIF}
begin
  {$IFDEF AVRO_PROFILE}
  tProf := ProfTicks;
  {$ENDIF}
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
    { ZERO-FLICKER STREAM: while a streamed kar is pending, the screen
      mirror is the ANSI STREAM kept by the kar press - the pending kar
      is deliberately NOT in the Unicode buffer, so Convert(PrevBanglaT)
      would NOT describe the screen }
    if AnsiMirrorActive then
      BijoyPrevBanglaT := AnsiMirror
    else
      BijoyPrevBanglaT := ConvCached(PrevBanglaT);
    BijoyNewBanglaText := ConvCached(NewBanglaText);

    { a kar glyph is STILL pending on screen: keep it inside the stream so
      that typing after it (্, a vowel sign, a digit ...) does not erase
      it, and a later backspace can remove exactly that one glyph.
      * text appended -> the ink keeps the position it was streamed at
      * text shrank   -> the ink trails at the end of the stream }
    if KarAnsiGlyph <> '' then
    begin
      { OPTIMISED: one conversion instead of three identical ones }
      PrevConv := ConvCached(PrevBanglaT);
      if (PrevBanglaT <> '') and (Pos(PrevConv, BijoyNewBanglaText) = 1) then
        BijoyNewBanglaText := PrevConv + KarAnsiGlyph + Copy(BijoyNewBanglaText, Length(PrevConv) + 1, MaxInt)
      else
        BijoyNewBanglaText := BijoyNewBanglaText + KarAnsiGlyph;
      AnsiMirror := BijoyNewBanglaText;
      AnsiMirrorActive := True;
    end
    else
      AnsiMirrorActive := False; // the stream window closes on every send

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
  {$IFDEF AVRO_PROFILE}
  Inc(ProfTickParse, ProfTicks - tProf);
  {$ENDIF}
end;

{ =============================================================================== }

function TGenericLayoutOld.ProcessVKeyDown(const KeyCode: Integer; var Block: Boolean): string;
var
  m_Block:      Boolean;
  m_Str:        string;
  IsoChainCont: Boolean;
  {$IFDEF AVRO_PROFILE}
  tProf: Int64;
  {$ENDIF}
begin
  m_Block := False;
  {$IFDEF AVRO_PROFILE}
  tProf := ProfTicks;
  {$ENDIF}
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
  IsoChainCont := (LastIsoContext <> '') and (RightStr(LastIsoContext, 1) = b_Hasanta) and (Length(m_Str) = 1) and (Ord(m_Str[1]) >= $0980);

  if (m_Str <> '') and (not uCaretContextSniffer.SniffingActive) and (OutputIsBijoy = 'YES') and (NewBanglaText = '') and (GetActivePreBaseKar = '') and
    (IsModifierOrJoiner(m_Str) or IsoChainCont) then
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
  ProcessVKeyDown := '';

  {$IFDEF AVRO_PROFILE}
  Inc(ProfTickTotal, ProfTicks - tProf);
  Inc(ProfKeys);
  if ProfKeys >= 100 then
    ProfDump;
  {$ENDIF}
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
  ClearKarFirstState;
  AnsiMirrorActive := False;
  AnsiMirror := '';
  KarAnsiGlyph := '';
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

  { Hasanta after a space starts a new word — don't treat as isolated modifier }
  if (SpacePendingCount > 0) and (Length(ModifierStr) = 1) and (ModifierStr[1] = b_Hasanta) then
    Exit;

  { --- 1. Establish PrecedingContext --- }
  if LastIsoContext <> '' then
    Ctx := LastIsoContext // chained isolated emission (ক -> ক্ -> ক্র)
  else if (SpacePendingCount > 0) and (LastCommittedUnicode <> '') then
    Ctx := LastCommittedUnicode // cross our own delimiter(s)
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
  if SpacePendingCount > 0 then
    EmitBatch(SpacePendingCount, ''); // remove only our delimiter(s)
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

  SpacePendingCount := 0;
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
