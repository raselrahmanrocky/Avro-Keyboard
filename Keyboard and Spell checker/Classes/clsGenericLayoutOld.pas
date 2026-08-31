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
  * BACKSPACE: a kar armed only in memory is discarded silently (nothing
  was on screen, so no synthetic backspace is sent). A kar-first typed
  syllable un-reorders: the consonant peels off and the kar returns to
  memory -  কতি -> ক,  জ্বি -> জ  - and the next consonant re-builds it.
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
end;

{ =============================================================================== }

procedure TGenericLayoutOld.DeleteLastCharSteps_Ex(StepCount: Integer);
var
  I, J: Integer;
  t1:   string;
begin
  for I := TrackL downto 1 do
    t1 := t1 + LastChars[I];

  if StepCount > TrackL then
    StepCount := TrackL;

  t1 := StringOfChar(' ', StepCount) + LeftStr(t1, Length(t1) - StepCount);

  for I := TrackL downto 1 do
  begin
    J := TrackL + 1 - I;
    LastChars[I] := MidStr(t1, J, 1);
  end;
  LastChar := LastChars[1];

end;

{ =============================================================================== }

destructor TGenericLayoutOld.Destroy;
begin
  FreeAndNil(Bijoy);

  inherited;
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

  { OLD STYLE METHOD 1 - un-reorder on backspace: a kar that was typed
    BEFORE its consonant peels the consonant back off, and the kar returns
    to the IN-MEMORY buffer (invisible again - nothing is re-emitted):
    কতি -> ক    (ি armed in memory)
    জ্বি -> জ   (ি armed in memory)
    Typing the consonant again re-creates the syllable. }
  if (KarFirstKar <> '') and KarConsumed and (Length(PrevBanglaT) >= KarRunCount + 1) and (RightStr(PrevBanglaT, 1) = KarFirstKar) then
  begin
    if UnwindConjunct and (Length(PrevBanglaT) >= KarRunCount + 2) and (PrevBanglaT[Length(PrevBanglaT) - KarRunCount - 1] = b_Hasanta) and
      IsPureConsonent(PrevBanglaT[Length(PrevBanglaT) - KarRunCount]) then
    begin
      InternalBackspace(KarRunCount + 2); // remove ্ + consonant + kar run
      { the pending-conjunct hasanta stays VISIBLE so the conjunct can be
        re-completed:  জ্বি -> জ্  and  ব completes it back to জ্বি }
      NewBanglaText := NewBanglaText + b_Hasanta;
      SetLastChar(b_Hasanta);
      UnwindConjunct := False;
      KarConsumed := False; // kar is pending in memory again (behind ্)
      ArmPreBaseFlag(KarFirstKar);
      ParseAndSendNow;
      Block := True;
      Exit;
    end
    else if (not UnwindConjunct) and IsPureConsonent(PrevBanglaT[Length(PrevBanglaT) - KarRunCount]) then
    begin
      InternalBackspace(KarRunCount + 1); // remove consonant + kar run
      KarConsumed := False;               // kar is pending again
      ArmPreBaseFlag(KarFirstKar);
      ParseAndSendNow;
      Block := True;
      Exit;
    end;
  end;

  { OLD STYLE METHOD 1: a kar armed ONLY in memory (nothing was emitted
    for it). Backspace clears it WITHOUT sending any synthetic backspace:
    - a pending run loses ONE invisible copy per press
    - the last copy disarms the state completely
    - hidden behind a VISIBLE pending hasanta: the hasanta is what the
    user sees, so the normal deletion below removes it and the kar
    stays armed
    - right after an un-reorder peel (other visible text exists): the
    state is disarmed here and the normal deletion below removes the
    peeled-off consonant }
  ArmedKar := GetActivePreBaseKar;
  if (ArmedKar <> '') and (not KarConsumed) and not((PrevBanglaT <> '') and (RightStr(PrevBanglaT, 1) = b_Hasanta)) then
  begin
    { ANSI: the kar is a STREAMED visual glyph on screen (its Unicode is
      deliberately NOT in the buffer). One real backspace erases the
      glyph; the buffer is untouched - K + [‡] + BS -> K }
    if (OutputIsBijoy = 'YES') and (KarAnsiGlyph <> '') and ((NewBanglaText = '') or (RightStr(NewBanglaText, 1) <> ArmedKar)) then
    begin
      Backspace(Length(KarAnsiGlyph));
      if AnsiMirrorActive and (Length(AnsiMirror) >= Length(KarAnsiGlyph)) then
      begin
        AnsiMirror := LeftStr(AnsiMirror, Length(AnsiMirror) - Length(KarAnsiGlyph));
        if AnsiMirror = Bijoy.Convert(PrevBanglaT) then
          AnsiMirrorActive := False;
      end;
      KarAnsiGlyph := '';
      ResetAllKarsToInactive;
      KarFirstKar := '';
      UnwindConjunct := False;
      KarConsumed := False;
      KarRunCount := 0;
      Block := True;
      Exit;
    end;
    { Unicode floating kar: one press loses ONE copy;
      the last copy disarms the state completely }
    if KarRunCount > 1 then
    begin
      Dec(KarRunCount); // one copy of the run is gone
      Block := True;
      Exit;
    end;
    ResetAllKarsToInactive;
    KarFirstKar := '';
    UnwindConjunct := False;
    KarConsumed := False;
    KarRunCount := 0;
    if NewBanglaText = '' then
    begin
      Block := True; // nothing on screen to delete
      Exit;
    end;
    // else: disarmed - the visible character is deleted by the normal path
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
        Backspace(Length(NewBanglaText));
        Block := True;
      end
      else if CommittedBanglaT <> '' then
      begin
        L := Length(CommittedBanglaT);
        if (L >= 3) and (CommittedBanglaT[L - 2] = b_R) and (CommittedBanglaT[L - 1] = b_Hasanta) and IsPureConsonent(CommittedBanglaT[L]) then
        begin
          SavedChar := CommittedBanglaT[L];
          Backspace(3);
          SendKey_Char(SavedChar);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 3) + SavedChar;
          Block := True;
          Exit;
        end;
        { Check for Ya-phala with explicit joiner in committed text }
        if (L >= 4) and ((CommittedBanglaT[L - 3] = ZWJ) or (CommittedBanglaT[L - 3] = ZWNJ)) and (CommittedBanglaT[L - 2] = b_Hasanta) and
          (CommittedBanglaT[L - 1] = b_Z) then
        begin
          Backspace(3);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 3);
          Block := True;
          Exit;
        end;
        { Check for Ya-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L - 1] = b_Hasanta) and (CommittedBanglaT[L] = b_Z) and (CommittedBanglaT[L - 2] <> b_R) then
        begin
          Backspace(2);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 2);
          Block := True;
          Exit;
        end;
        { Check for Ra-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L - 1] = b_Hasanta) and (CommittedBanglaT[L] = b_R) then
        begin
          Backspace(2);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 2);
          Block := True;
          Exit;
        end;
        Backspace(1);
        CommittedBanglaT := LeftStr(CommittedBanglaT, L - 1);
        Block := True;
        Exit;
      end
      else
        Block := False;
    end
    else
    begin
      BijoyNewBanglaText := Bijoy.Convert(NewBanglaText);
      if Length(BijoyNewBanglaText) >= 1 then
      begin
        Backspace(Length(BijoyNewBanglaText));
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
        Backspace(Length(Bijoy.Convert(MidStr(PrevBanglaT, Length(PrevBanglaT) - 2, 3))));
        SendKey_Char(Bijoy.Convert(SavedChar));
      end
      else
      begin
        Backspace(3);
        SendKey_Char(SavedChar);
      end;
      PrevBanglaT := LeftStr(PrevBanglaT, Length(PrevBanglaT) - 3) + SavedChar;
      NewBanglaText := PrevBanglaT;
      SetLastChar(SavedChar);
    end
    else
    begin
      InternalBackspace(DeleteCount);
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
      AnsiMirror := Bijoy.Convert(PrevBanglaT);
      AnsiMirrorActive := True;
    end;
    AnsiMirror := AnsiMirror + AGlyph;
  end;

  procedure StreamMirrorShrink(const AGlyph: string);
  begin
    if AnsiMirrorActive and (Length(AnsiMirror) >= Length(AGlyph)) then
    begin
      AnsiMirror := LeftStr(AnsiMirror, Length(AnsiMirror) - Length(AGlyph));
      if AnsiMirror = Bijoy.Convert(PrevBanglaT) then
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
      Backspace(Length(KarAnsiGlyph));
      StreamMirrorShrink(KarAnsiGlyph);
      KarAnsiGlyph := '';
    end;
    ResetAllKarsToInactive;
    KarFirstKar := '';
    UnwindConjunct := False;
    KarConsumed := False;
    KarRunCount := 0;
    PressPreBaseKar := KarChar;
    Exit;
  end;

  { SAME kar again:
    ANSI mode  - the glyph already streamed once: swallow the repeat and
    STAY armed so the next consonant still takes it.
    Unicode    - COMMIT: emit the kar right away - it renders attached to
    the letter just typed (ক + ি + ি -> কি). ALL kar-first
    state is cleared and backspace deletes it normally. }
  if GetActivePreBaseKar = KarChar then
  begin
    if OutputIsBijoy = 'YES' then
    begin
      PressPreBaseKar := ''; // ANSI: already streamed once - swallow
      Exit;
    end;
    ResetAllKarsToInactive;
    KarFirstKar := '';
    UnwindConjunct := False;
    KarConsumed := False;
    KarRunCount := 0;
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
      Backspace(Length(KarAnsiGlyph));
      StreamMirrorShrink(KarAnsiGlyph);
    end;
    KarAnsiGlyph := StreamGlyph(KarChar);
    StreamMirrorAppend(KarAnsiGlyph);
    SendKey_Char(KarAnsiGlyph);
    PressPreBaseKar := '';
    Exit;
  end;
  PressPreBaseKar := ''; // Unicode METHOD 1: emit NOTHING
end;

{ =============================================================================== }

{
  OLD STYLE: re-arms the active flag of a floating pre-base kar.
  Used when backspace peels a consonant back off a kar-first typed kar
  (কে -> ে) so the kar is floating/armed again.
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
        KarAnsiGlyph := '' ; // reset so next kar won't issue false backspace
        KarRunCount := 1;
        UnwindConjunct := False;
        Result := '';
        Exit;
      end
      else
      begin
        // BARE (ে + ্ at word start): drop the whole run + hasanta
        InternalBackspace(KarRunCount + 1);
        KarFirstKar := '';
        UnwindConjunct := False;
        KarConsumed := False;
        KarRunCount := 0;
        Result := '';
        Exit;
      end;
    end;
    // kar pending IN MEMORY behind the hasanta (nothing was visible):
    // drop the hasanta, emit just the independent vowel
    if RightStr(NewBanglaText, 1) = b_Hasanta then
    begin
      InternalBackspace(1);
      KarFirstKar := '';
      UnwindConjunct := False;
      KarConsumed := False;
      KarRunCount := 0;
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
begin

  if AvroMainForm1.GetMyCurrentKeyboardMode = SysDefault then
  begin

    Block := False;
    MyProcessVKeyDown := '';
    Exit;
  end
  else if AvroMainForm1.GetMyCurrentKeyboardMode = bangla then
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
      IsRephTailCtx := (LastChars[2] = b_R) and (LastChars[3] <> b_Hasanta);

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
          KarFirstKar := '';
          UnwindConjunct := False;
          KarConsumed := False;
          KarRunCount := 0;
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
          KarFirstKar := '';
          UnwindConjunct := False;
          KarConsumed := False;
          KarRunCount := 0;
          KarAnsiGlyph := '';
        end
        else
        begin
          mKar := DupeString(ArmedKar, KarRunCount);
          ResetAllKarsToInactive;
          KarFirstKar := '';
          UnwindConjunct := False;
          KarConsumed := False;
          KarRunCount := 0;
          SendKey_Char(mKar); // visible before the delimiter
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
          CommittedBanglaT := CommittedBanglaT + PrevBanglaT + ' ';
          ResetLastChar;
          MyProcessVKeyDown := '';
          Exit;
        end;
      VK_SPACE:
        begin
          Block := False;
          CommittedBanglaT := CommittedBanglaT + PrevBanglaT + ' ';
          if Length(CommittedBanglaT) > 500 then
            Delete(CommittedBanglaT, 1, Length(CommittedBanglaT) - 500);
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
              KarFirstKar := '';
              UnwindConjunct := False;
              KarConsumed := False;
              KarRunCount := 0;
              if (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta) then
                InternalBackspace(1); // pending hasanta joins the vowel
              MyProcessVKeyDown := b_Okar;
              Exit;
            end
            else if (ArmedKar = b_Ekar) and (CharForKey = b_LengthMark) then
            begin
              ResetAllKarsToInactive;
              KarFirstKar := '';
              UnwindConjunct := False;
              KarConsumed := False;
              KarRunCount := 0;
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
              KarFirstKar := '';
              UnwindConjunct := False;
              KarConsumed := False;
              KarRunCount := 0;
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
              KarFirstKar := '';
              UnwindConjunct := False;
              KarConsumed := False;
              KarRunCount := 0;
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
  I, Matched, UnMatched:                Integer;
  BijoyPrevBanglaT, BijoyNewBanglaText: string;
begin
  Matched := 0;

  if OutputIsBijoy <> 'YES' then
  begin
    { Output to Unicode }
    if PrevBanglaT = '' then
    begin
      SendKey_Char(NewBanglaText);
      PrevBanglaT := NewBanglaText;
    end
    else
    begin
      for I := 1 to Length(PrevBanglaT) do
      begin
        if MidStr(PrevBanglaT, I, 1) = MidStr(NewBanglaText, I, 1) then
          Matched := Matched + 1
        else
          Break;
      end;
      UnMatched := Length(PrevBanglaT) - Matched;

      if UnMatched >= 1 then
        Backspace(UnMatched);
      SendKey_Char(MidStr(NewBanglaText, Matched + 1, Length(NewBanglaText)));
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
      BijoyPrevBanglaT := Bijoy.Convert(PrevBanglaT);
    BijoyNewBanglaText := Bijoy.Convert(NewBanglaText);
    AnsiMirrorActive := False; // the stream window closes on every send

    if BijoyPrevBanglaT = '' then
    begin
      SendKey_Char(BijoyNewBanglaText);
      PrevBanglaT := NewBanglaText;
    end
    else
    begin
      for I := 1 to Length(BijoyPrevBanglaT) do
      begin
        if MidStr(BijoyPrevBanglaT, I, 1) = MidStr(BijoyNewBanglaText, I, 1) then
          Matched := Matched + 1
        else
          Break;
      end;
      UnMatched := Length(BijoyPrevBanglaT) - Matched;

      if UnMatched >= 1 then
        Backspace(UnMatched);
      SendKey_Char(MidStr(BijoyNewBanglaText, Matched + 1, Length(BijoyNewBanglaText)));
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
        LastCommittedAnsi := Bijoy.Convert(PrevBanglaT)
      else
        LastCommittedAnsi := PrevBanglaT;
    end;
  end;
  IsAtWordBoundary := True;
  ClearIsoState;
  SpacePendingCount := 0;
  KarFirstKar := '';
  UnwindConjunct := False;
  KarConsumed := False;
  KarRunCount := 0;
  AnsiMirrorActive := False;
  AnsiMirror := '';
  KarAnsiGlyph := '';

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
    Backspace(SpacePendingCount); // remove only our delimiter(s)
  if EraseCount > 0 then
    Backspace(EraseCount); // replace the default/context glyph
  SendKey_Char(ResolvedAnsi);

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

procedure TGenericLayoutOld.SetLastChar(const wChar: string);
var
  t1, t2: string;
  I, J:   Integer;
begin
  for I := TrackL downto 1 do
    t1 := t1 + LastChars[I];

  t1 := t1 + wChar;
  t2 := RightStr(t1, TrackL);

  for I := TrackL downto 1 do
  begin
    J := TrackL + 1 - I;
    LastChars[I] := MidStr(t2, J, 1);
  end;
  LastChar := LastChars[1];
end;

{ =============================================================================== }

end.
