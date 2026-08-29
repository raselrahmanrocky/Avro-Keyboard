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
  OLD STYLE TYPING MODIFICATION (Bijoy keyboard behaviour):

  Pre-base kars (ে, ি, ী, ৈ) now behave like the old Bijoy typewriter:
  * A SINGLE press shows the kar immediately at the caret (floating kar).
  * To attach a kar to a letter, the kar MUST be typed first; the next
    consonant reorders it automatically (consonant first, kar after), so
    the stored Unicode is always canonical:  ে+ক -> কে,  ি+ক -> কি ...
  * ে + া -> ো  and  ে + ৗ -> ৌ  still compose on the fly.
  * A repeated press of the same kar key is swallowed (it is already
    visible); another pre-base kar replaces the floating one.
  * Right after a consonant the kar simply attaches in normal order
    (ক + ি -> কি), so mixed/modern typing keeps working untouched.
  * Backspacing the visible floating kar also disarms the reorder state.
  * BACKSPACE UN-REORDER: a kar typed BEFORE its consonant peels the
    consonant back off on backspace, walking back through the typing
    steps: কে -> ে -> (clear)  and  জ্বি -> জি্ -> জি -> ি -> (clear).
    From the জি্ state, typing a consonant again completes the conjunct
    (জি্ + ব -> জ্বি). Kars attached in normal order (consonant first)
    delete normally.
  * In Bijoy (ANSI) output mode the pre-base kars are excluded from the
    isolated-modifier engine while floating, so kar-first typing always
    starts a fresh word instead of touching the previous committed word.
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

      // Kar Variables for Full Old Style Typing
      // (pre-base kars: ে, ি, ী, ৈ - visible on a single press; they float
      //  until the consonant arrives and are then reordered after it)
      EKarActive, IKarActive, IIKarActive, OIKarActive: Boolean;

      // OLD STYLE backspace un-reorder state:
      KarFirstKar:    string;  // pre-base kar that was typed BEFORE its consonant
      UnwindConjunct: Boolean; // last join completed a conjunct after [kar ্] (জি্ + ব -> জ্বি)

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
    //    to LastCommittedUnicode, so the next modifier must attach cleanly.
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
    //    (e.g. রু <-> A_UKar4/A_UKar2) so an immediate retype alternates.
    if (LastIsoToggleKey <> '') or (LastIsoContext <> '') then
    begin
      if (LastIsoToggleKey <> '') and (Bijoy <> nil) then
        Bijoy.FlipIsolatedToggle(LastIsoToggleKey);
      ClearIsoState;
      Block := False; // native backspace removes the glyph
      Exit;
    end;
  end;

  { OLD STYLE: un-reorder on backspace - a kar that was typed BEFORE its
    consonant peels the consonant back off, step by step:
      কে   -> ে     (consonant removed, kar floats/armed again)
      জি   -> ি
      জ্বি -> জি্   (half-consonant removed, kar shows before hasanta) }
  if (KarFirstKar <> '') and (Length(PrevBanglaT) >= 2) and (RightStr(PrevBanglaT, 1) = KarFirstKar) then
  begin
    if UnwindConjunct and (Length(PrevBanglaT) >= 3) and
       (PrevBanglaT[Length(PrevBanglaT) - 2] = b_Hasanta) and
       IsPureConsonent(PrevBanglaT[Length(PrevBanglaT) - 1]) then
    begin
      InternalBackspace(3);
      NewBanglaText := NewBanglaText + KarFirstKar + b_Hasanta;
      SetLastChar(KarFirstKar);
      SetLastChar(b_Hasanta);
      UnwindConjunct := False;
      ParseAndSendNow;
      Block := True;
      Exit;
    end
    else if (not UnwindConjunct) and IsPureConsonent(PrevBanglaT[Length(PrevBanglaT) - 1]) then
    begin
      InternalBackspace(2);
      NewBanglaText := NewBanglaText + KarFirstKar;
      SetLastChar(KarFirstKar);
      UnwindConjunct := False;
      ArmPreBaseFlag(KarFirstKar);
      ParseAndSendNow;
      Block := True;
      Exit;
    end;
  end;

  { OLD STYLE: deleting the visible floating pre-base kar also disarms it,
    so a backspaced ে/ি/ী/ৈ cannot re-attach to the next consonant }
  ArmedKar := GetActivePreBaseKar;
  if (ArmedKar <> '') and (PrevBanglaT <> '') and (RightStr(PrevBanglaT, 1) = ArmedKar) then
  begin
    ResetAllKarsToInactive;
    KarFirstKar := '';
    UnwindConjunct := False;
  end;

  { --- Reph / Phala tail detection --- }
  IsRephTail := (Length(PrevBanglaT) >= 3) and
                (PrevBanglaT[Length(PrevBanglaT) - 2] = b_R) and
                (PrevBanglaT[Length(PrevBanglaT) - 1] = b_Hasanta) and
                IsPureConsonent(PrevBanglaT[Length(PrevBanglaT)]);

  DeleteCount := 1;
  if not IsRephTail then
  begin
    if (Length(PrevBanglaT) >= 3) and
       ((PrevBanglaT[Length(PrevBanglaT)-2] = ZWJ) or (PrevBanglaT[Length(PrevBanglaT)-2] = ZWNJ)) and
       (PrevBanglaT[Length(PrevBanglaT)-1] = b_Hasanta) and
       (PrevBanglaT[Length(PrevBanglaT)] = b_Z) then
      DeleteCount := 3
    else if (Length(PrevBanglaT) >= 2) and
            (PrevBanglaT[Length(PrevBanglaT)-1] = b_Hasanta) and
            (PrevBanglaT[Length(PrevBanglaT)] = b_Z) then
      DeleteCount := 2
    else if (Length(PrevBanglaT) >= 2) and
            (PrevBanglaT[Length(PrevBanglaT)-1] = b_Hasanta) and
            (PrevBanglaT[Length(PrevBanglaT)] = b_R) then
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
        if (L >= 4) and
           ((CommittedBanglaT[L-3] = ZWJ) or (CommittedBanglaT[L-3] = ZWNJ)) and
           (CommittedBanglaT[L-2] = b_Hasanta) and (CommittedBanglaT[L-1] = b_Z) then
        begin
          Backspace(3);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 3);
          Block := True;
          Exit;
        end;
        { Check for Ya-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L-1] = b_Hasanta) and (CommittedBanglaT[L] = b_Z) and
           (CommittedBanglaT[L-2] <> b_R) then
        begin
          Backspace(2);
          CommittedBanglaT := LeftStr(CommittedBanglaT, L - 2);
          Block := True;
          Exit;
        end;
        { Check for Ra-phala in committed text }
        if (L >= 3) and (CommittedBanglaT[L-1] = b_Hasanta) and (CommittedBanglaT[L] = b_R) then
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
      if (TrackL >= 2) and (LastChars[2] = b_Ekar) and
              ((sKar = b_AAkar) or (sKar = b_OUkar) or (sKar = b_LengthMark)) then
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
  (ে, ি, ী or ৈ); '' when no reorder is pending.
}
function TGenericLayoutOld.GetActivePreBaseKar: string;
begin
  if EKarActive then
    GetActivePreBaseKar := b_Ekar
  else if IKarActive then
    GetActivePreBaseKar := b_Ikar
  else if IIKarActive then
    GetActivePreBaseKar := b_IIkar
  else if OIKarActive then
    GetActivePreBaseKar := b_OIkar
  else
    GetActivePreBaseKar := '';
end;

{ =============================================================================== }

{
  OLD STYLE (Bijoy behaviour) handling of a pre-base kar key press:
  * The kar is emitted immediately, so it becomes visible with a single press.
  * It stays "floating" (armed): the next consonant reorders it
    (consonant first in the buffer, kar reordered after it).
  * Pressing the SAME kar again is swallowed (it is already visible).
  * Pressing a DIFFERENT pre-base kar replaces the floating one.
  * Directly after a consonant there is nothing to reorder, so the kar
    attaches in normal order (ক + ি -> কি) and no state is armed.
}
function TGenericLayoutOld.PressPreBaseKar(const KarChar: string): string;
begin
  // Same kar already floating and shown - swallow the repeat press
  if GetActivePreBaseKar = KarChar then
  begin
    PressPreBaseKar := '';
    Exit;
  end;

  // A different pre-base kar is floating - replace it with the new one
  if (GetActivePreBaseKar <> '') and (RightStr(NewBanglaText, 1) = GetActivePreBaseKar) then
    InternalBackspace(1);

  ResetAllKarsToInactive;

  // Right after a consonant the kar attaches normally - nothing to reorder
  if IsPureConsonent(LastChar) then
  begin
    KarFirstKar := '';      // consonant-first typing: normal single delete on backspace
    UnwindConjunct := False;
    PressPreBaseKar := KarChar;
    Exit;
  end;

  // Otherwise the kar floats visibly and awaits its consonant
  if KarChar = b_Ekar then
    EKarActive := True
  else if KarChar = b_Ikar then
    IKarActive := True
  else if KarChar = b_IIkar then
    IIKarActive := True
  else if KarChar = b_OIkar then
    OIKarActive := True;

  KarFirstKar := KarChar;   // kar-first typing: remember for backspace un-reorder
  UnwindConjunct := False;
  PressPreBaseKar := KarChar;
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
  else if KarChar = b_IIkar then
    IIKarActive := True
  else if KarChar = b_OIkar then
    OIKarActive := True;
end;

{ =============================================================================== }

function TGenericLayoutOld.MyProcessVKeyDown(const KeyCode: Integer; var Block: Boolean;
  const var_IsLogicalShift, var_IsTrueShift, var_IsAltGr: Boolean): string;
var
  CharForKey, tmpString, PendingKar: string;
  ArmedKar, mKar: string;
  KarInBuffer:   Boolean;
  IsRephTailCtx: Boolean;
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
      { OLD STYLE: after a typed reph (র্) the pre-base kars must keep
        floating for the coming consonant instead of turning into a vowel
        letter (needed for e.g. ক + র্ + ে + ম -> কর্মে) }
      IsRephTailCtx := (LastChars[2] = b_R) and (LastChars[3] <> b_Hasanta);

      if (not IsRephTailCtx) or
         ((CharForKey <> b_Ekar) and (CharForKey <> b_Ikar) and
          (CharForKey <> b_IIkar) and (CharForKey <> b_OIkar)) then
      begin

        if EKarActive then
          PendingKar := b_Ekar
        else if IKarActive then
          PendingKar := b_Ikar
        else if IIKarActive then
          PendingKar := b_IIkar
        else if OIKarActive then
          PendingKar := b_OIkar
        else
          PendingKar := '';

        if CharForKey = b_AAkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_AA;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ikar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_I;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_IIkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_II;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ukar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_U;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_UUkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_UU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_RRIkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_RRI;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Ekar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_E;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OIkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_OI;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Okar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_O;
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
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_Okar;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OU then
        begin
          // ্ + ঔ -> ৌ-কার (twin of the rule above): drop the hasanta
          // and attach OU-kar to the consonant before it
          // (ক + ্ + ঔ -> কৌ).
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_OUkar;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_OUkar then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_OU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_LengthMark then
        begin
          InternalBackspace;
          MyProcessVKeyDown := InsertKar(PendingKar) + b_OU;
          ResetAllKarsToInactive;
          Exit;
        end
        else if CharForKey = b_Hasanta then
        begin
          MyProcessVKeyDown := ZWNJ;
          ResetAllKarsToInactive;
          Exit;
        end;

      end;
    end;

    { =====================================================================
      OLD STYLE (Bijoy behaviour) - pre-base kars: ে, ি, ী, ৈ
      * Single press shows the kar immediately (it floats at the caret).
      * The NEXT consonant reorders it: consonant first, kar after.
      * Same kar pressed again: swallowed (already visible).
      * Another pre-base kar pressed: replaces the floating one.
      * Right after a consonant it attaches normally (ক + ি -> কি).
      ===================================================================== }
    if (CharForKey = b_Ekar) or (CharForKey = b_Ikar) or (CharForKey = b_IIkar) or (CharForKey = b_OIkar) then
    begin
      { NOTE: never read MyProcessVKeyDown in an expression - the bare
        function name on the right side means a recursive CALL in Pascal
        (E2035). Use a local temp instead. }
      mKar := PressPreBaseKar(CharForKey);
      if mKar = '' then
        Block := True; // repeat press - kar already visible, nothing to emit
      MyProcessVKeyDown := mKar;
      Exit;
    end;

    if CharForKey = b_AAkar then
    begin
      if LastChar = b_Ekar then
      begin
        ResetAllKarsToInactive;
        InternalBackspace;
        MyProcessVKeyDown := InsertKar(b_Okar);
        Exit;
      end;
    end;

    if CharForKey = b_LengthMark then
    begin
      if LastChar = b_Ekar then
      begin
        ResetAllKarsToInactive;
        InternalBackspace;
        MyProcessVKeyDown := InsertKar(b_OUkar);
        Exit;
      end;
    end;

    if CharForKey = b_Hasanta then
    begin
      if LastChar = b_Ekar then
      begin
        InternalBackspace;
        EKarActive := True;
        KarFirstKar := b_Ekar;
        UnwindConjunct := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_Ikar then
      begin
        InternalBackspace;
        IKarActive := True;
        KarFirstKar := b_Ikar;
        UnwindConjunct := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_IIkar then
      begin
        InternalBackspace;
        IIKarActive := True;
        KarFirstKar := b_IIkar;
        UnwindConjunct := False;
        MyProcessVKeyDown := b_Hasanta;
        Exit;
      end
      else if LastChar = b_OIkar then
      begin
        InternalBackspace;
        OIKarActive := True;
        KarFirstKar := b_OIkar;
        UnwindConjunct := False;
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
          ResetLastChar;            // soft-saves LastCommitted* context
          Inc(SpacePendingCount);   // delimiter now sits between caret & context
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
          if (KarFirstKar <> '') and (Length(NewBanglaText) >= 2) and
             (RightStr(NewBanglaText, 2) = KarFirstKar + b_Hasanta) and
             (Length(CharForKey) = 1) and IsPureConsonent(CharForKey) then
          begin
            InternalBackspace(2);
            UnwindConjunct := True;
            MyProcessVKeyDown := b_Hasanta + CharForKey + KarFirstKar;
            Exit;
          end;

          if ArmedKar <> '' then
          begin
            { OLD STYLE: a pre-base kar is floating. The visible kar sits at
              the end of the buffer; a re-armed one (after hasanta-cancel)
              does not. Attach the kar to whatever is being typed now. }
            KarInBuffer := (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = ArmedKar);
            ResetAllKarsToInactive;
            KarFirstKar := ArmedKar;   { consumed by this reorder - remember for un-reorder }
            { A consonant joined straight after a pending hasanta (hidden kar)
              completed a conjunct: জ্ + ব -> জ্বি. Mark it so backspace
              unwinds the conjunct (জ্বি -> জি্) instead of just revealing
              the floating kar. }
            UnwindConjunct := (not KarInBuffer) and (NewBanglaText <> '') and (RightStr(NewBanglaText, 1) = b_Hasanta);

            if CharForKey = b_R + b_Hasanta then
            begin
              if KarInBuffer then
                MyProcessVKeyDown := InsertReph // visible kar folds into the moved cluster
              else
                MyProcessVKeyDown := InsertReph + ArmedKar;
              Exit;
            end
            else if CharForKey = b_AAkar then
            begin
              if KarInBuffer then
                InternalBackspace(1);
              MyProcessVKeyDown := b_Okar; // ে + া -> ো
              Exit;
            end
            else if CharForKey = b_LengthMark then
            begin
              if KarInBuffer then
                InternalBackspace(1);
              MyProcessVKeyDown := b_OUkar; // ে + ৗ -> ৌ
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
              if KarInBuffer then
                InternalBackspace(1);
              MyProcessVKeyDown := CharForKey + ArmedKar; // reorder: key first, kar after
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
    BijoyPrevBanglaT := Bijoy.Convert(PrevBanglaT);
    BijoyNewBanglaText := Bijoy.Convert(NewBanglaText);

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
  IsoChainCont := (LastIsoContext <> '') and (RightStr(LastIsoContext, 1) = b_Hasanta) and
    (Length(m_Str) = 1) and (Ord(m_Str[1]) >= $0980);

  if (m_Str <> '') and (not uCaretContextSniffer.SniffingActive) and (OutputIsBijoy = 'YES') and (NewBanglaText = '') and
    (GetActivePreBaseKar = '') and (IsModifierOrJoiner(m_Str) or IsoChainCont) then
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

  NewBanglaText := NewBanglaText + m_Str;
  ParseAndSendNow;

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
  IIKarActive := False;
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
  CandArr:            TAnsiUniCandidates;
  EraseCount:         Integer;
  IsToggle, UsedAlt:  Boolean;
  Kind:               TSniffResult;
begin
  Result := False;
  if Bijoy = nil then
    Exit;

  { Hasanta after a space starts a new word — don't treat as isolated modifier }
  if (SpacePendingCount > 0) and (Length(ModifierStr) = 1) and
     (ModifierStr[1] = b_Hasanta) then
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
    Backspace(EraseCount);        // replace the default/context glyph
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
