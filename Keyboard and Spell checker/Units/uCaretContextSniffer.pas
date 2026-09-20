{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uCaretContextSniffer;
{
  Transparent active-caret lookbehind sniffer.

  Reads the single character immediately before the caret of the currently
  focused target application so isolated modifiers (kars/phalas/hasanta typed
  while the in-memory word buffer is empty) can resolve contextually anywhere
  in a document.

  Layered strategy:
  A) Message-based fast path - EM_GETSEL + WM_GETTEXT on standard Edit /
  RichEdit controls. Zero side effects.
  B) Clipboard round-trip fallback - select one char left (Shift+Left),
  copy (Ctrl+C), read CF_UNICODETEXT, restore caret (Right), restore the
  previous clipboard text. Used for Word/browsers/custom controls.

  Every synthetic key event is stamped with AVRO_SNIFF_TAG in dwExtraInfo so
  our own WH_KEYBOARD_LL hook passes them straight through without layout
  processing. The injected events traverse the hook only after this call
  stack returns (Sleep() never pumps messages).
}

interface

const
  AVRO_SNIFF_TAG = $A09E5701; // dwExtraInfo marker for sniffer input

type
  TSniffResult = (srNone, // nothing usable before the caret (BOS/unknown app/failure)
    srAnsiGlyph,          // an ANSI (Bijoy font range) character
    srUnicodeChar,        // a Unicode Bengali character ($0980..$09FF)
    srDelimiter           // space/tab/newline directly before the caret
    );

type
  { Where an N-character lookback was read, and how much text stood before the
    caret there: enough for a caller to keep its own staleness bookkeeping.

    The handle is a NativeUInt (what HWND is) so this unit's INTERFACE keeps its
    empty uses clause - a HWND here would drag Windows into every unit that only
    wants to read the text in front of the caret. }
  TSniffReading = record
    Window:     NativeUInt; // the control the text came from (0 = no window)
    CaretIndex: Integer;    // characters before the caret
    TextLength: Integer;
  end;

var
  SniffingActive: Boolean = False; // reentrancy guard checked by layout engines

  { TEST / EMBEDDING HOOK. While the override is
    active the sniffer never touches a window or the clipboard: it reports
    exactly the context the caller asked for, so the isolated-modifier engine
    can be driven - and pinned - from a head-less test. Nothing in the shipped
    application sets these. }
  SniffOverrideActive: Boolean = False;
  SniffOverride:       string  = '';

  // Reads one char left of the caret. Returns True when Chars is meaningful.
function SniffCharBeforeCaret(out Chars: string; out Kind: TSniffResult): Boolean;

  { Reads up to AMaxChars characters IMMEDIATELY BEFORE the caret through the
    message path ONLY (Layer A: EM_GETSEL + WM_GETTEXT on a standard Edit /
    RichEdit) and reports where it read them.

    This is the reader a multi-unit erase uses: it sends no synthetic key,
    touches no clipboard and changes no focus, so it cannot disturb the
    document, and a failure is a normal answer ("not a standard edit", "the
    caret is at the start", "the control is busy"). The clipboard round-trip of
    SniffCharBeforeCaret stays what it was - a ONE character read for the
    live-word path - and must never justify erasing more than one unit, because
    it moves the caret and the selection to get its answer. }
function SniffTextBeforeCaret(const AMaxChars: Integer; out AText: string; out AReading: TSniffReading): Boolean;

{ LAYER C, the N-character form: select AMaxChars characters to the LEFT of the
  caret with Shift+Left, copy them (Ctrl+C), read the clipboard, collapse the
  selection again (one Right returns the caret to where it was) and put the
  previous clipboard text back. Refused outright when the control already has an
  active selection - that selection is the user's, not this reader's, and it is
  exactly what the caret-context path must not disturb.

  This is the most invasive layer, so it is used only when the caller asks for it
  (AnsiBackspaceClipboard = 'YES', default NO) and only after the message path and
  UI Automation both came back empty. AText is '' when nothing could be read;
  that is a normal answer. }
function SniffTextViaClipboard(const AMaxChars: Integer; out AText: string): Boolean;

implementation

uses
  Windows,
  Messages,
  SysUtils,
  Clipbrd,
  uRegistrySettings,
  uCaretContextCache; // AnsiTrace (the debug log) and the sniffer's own switch

const
  SNIFF_MSG_TIMEOUT = 100;   // ms per SendMessageTimeout
  SNIFF_MAX_TEXTLEN = $F000; // above this EM_GETSEL lo/hi contract is unsafe
  SNIFF_COPY_DELAY  = 25;    // ms wait after Ctrl+C
  SNIFF_SEL_DELAY   = 12;    // ms wait after Shift+Left

  { =============================================================================== }

{ One SendMessageTimeout call, reporting the MESSAGE's result the way the callers
  below need it.

  SendMessageTimeout's own return value only says whether the call succeeded and
  timed out or not - it is NOT the message result, which arrives in the last
  parameter. Reading EM_GETSEL's packed selection out of the return value yields
  1 for every control (start = 1, end = 0), which every caller below reads as
  "the user has an active selection": the message path then refuses every control
  and the clipboard round-trip never runs. AResult is 0 when the call failed or
  timed out, which all of them already treat as "no reading". }
function SendTimed(hEdit: HWND; const AMsg: UINT; const AW: WPARAM; const AL: LPARAM; out AResult: LRESULT): Boolean;
begin
  AResult := 0;
  Result := SendMessageTimeout(hEdit, AMsg, AW, AL, SMTO_ABORTIFHUNG, SNIFF_MSG_TIMEOUT, PDWORD_PTR(@AResult)) <> 0;
end;

function GetFocusedEditHandle: HWND;
var
  GTI: TGUITHREADINFO;
begin
  Result := 0;
  FillChar(GTI, SizeOf(GTI), 0);
  GTI.cbSize := SizeOf(GTI);
  if GetGUIThreadInfo(0, GTI) then
  begin
    if GTI.hwndCaret <> 0 then
      Result := GTI.hwndCaret
    else if GTI.hwndFocus <> 0 then
      Result := GTI.hwndFocus;
  end;
end;

{ =============================================================================== }
// All sniffer input carries AVRO_SNIFF_TAG so the LL keyboard hook ignores it.

procedure SniffKeyEvent(bKey: Integer; bKeyUp: Boolean);
var
  KInput: TInput;
begin
  KInput.Itype := INPUT_KEYBOARD;
  KInput.ki.wVk := bKey;
  KInput.ki.wScan := MapVirtualKey(bKey, 0);
  if bKeyUp then
    KInput.ki.dwFlags := KEYEVENTF_KEYUP
  else
    KInput.ki.dwFlags := 0;
  KInput.ki.time := 0;
  KInput.ki.dwExtraInfo := AVRO_SNIFF_TAG;
  SendInput(1, KInput, SizeOf(KInput));
end;

{ =============================================================================== }
{ The injected modifiers are never taken on trust.

  SendInput goes through the whole input stack, and that stack is not always
  neutral: a machine was measured where an injected Shift down is followed by a
  Shift up the sender never sent, so the arrow keys arrive with the modifier
  released. Unchecked, that turns the round-trip into something the user did not
  ask for - Shift+Left becomes a bare caret move - and, worse, an unmodified
  Ctrl+C is a typed 'c' in the middle of their document.

  So every modifier this unit presses is confirmed against the DESKTOP
  (GetAsyncKeyState, not our own queue) before the key that depends on it is
  pressed, and confirmed released again before the next key. Nothing else in
  this unit changes: a modifier that does not take effect means no reading, and
  no reading is the pre-feature behaviour. }

{ True while the desktop considers the key held. }
function KeyHeld(const AVk: Integer): Boolean;
begin
  Result := (GetAsyncKeyState(AVk) and $8000) <> 0;
end;

{ Presses a modifier and waits for the desktop to agree that it is down. False
  means it never took effect (or was taken away again at once), and the caller
  must NOT press the key that depends on it. }
function ModifierDown(const AVk: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  SniffKeyEvent(AVk, False);

  { Twice: a stack that eats the modifier takes it away a moment AFTER the
    press, so one look immediately afterwards is not enough to see it. }
  for I := 1 to 2 do
  begin
    Sleep(SNIFF_SEL_DELAY);
    if not KeyHeld(AVk) then
    begin
      SniffKeyEvent(AVk, True); // release what little there was
      Exit;
    end;
  end;

  Result := True;
end;

{ Releases a modifier and waits for the desktop to agree, so that the NEXT key is
  not silently modified - a Shift the desktop still holds turns the collapse of
  the selection into an extension of it. False = it could not be released, and
  the caller must leave the keyboard alone. }
function ModifierUp(const AVk: Integer; const AAlso: Integer = 0): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to 3 do
  begin
    SniffKeyEvent(AVk, True);
    if AAlso <> 0 then
      SniffKeyEvent(AAlso, True); // a stack may only know the named left/right key
    Sleep(SNIFF_SEL_DELAY);
    if (not KeyHeld(AVk)) and ((AAlso = 0) or (not KeyHeld(AAlso))) then
      Exit(True);
  end;
end;

{ Ctrl+C. False = the Ctrl never took effect, in which case 'C' was NOT pressed:
  a bare 'c' would be typed into the user's document. }
function CopySelection: Boolean;
begin
  Result := False;
  if not ModifierDown(VK_CONTROL) then
  begin
    AnsiTrace('clipboard: the desktop did not hold the injected Ctrl - nothing was typed');
    Exit;
  end;

  SniffKeyEvent(Ord('C'), False);
  SniffKeyEvent(Ord('C'), True);
  Sleep(SNIFF_COPY_DELAY);

  Result := True;
  if not ModifierUp(VK_CONTROL, VK_LCONTROL) then
    AnsiTrace('clipboard: the desktop kept the injected Ctrl down');
end;

{ Selection was [caret-ACount..caret]; ONE Right collapses back to the caret the
  round-trip started from. Only ever called when a selection was really created
  and the Shift was really released. }
procedure CollapseSelection;
begin
  SniffKeyEvent(VK_RIGHT, False);
  SniffKeyEvent(VK_RIGHT, True);
end;

{ =============================================================================== }
// Layer A: zero-side-effect read from standard EDIT / RICHEDIT* controls.

function IsStandardEditClass(hEdit: HWND): Boolean;
var
  ClsName: array [0 .. 63] of Char;
  Cls:     string;
begin
  Result := False;
  if GetClassName(hEdit, ClsName, 64) = 0 then
    Exit;
  Cls := string(ClsName);
  Result := (UpperCase(Cls) = 'EDIT') or (Pos('RICHEDIT', UpperCase(Cls)) = 1);
end;

{ A password field is never read: the characters in front of the caret are a
  secret, and no reader in this unit has any business seeing one. Every caller
  already treats a missing reading as the pre-feature behaviour, so refusing
  here costs nothing and cannot erase anything. }
function IsPasswordEdit(hEdit: HWND): Boolean;
begin
  Result := (hEdit <> 0) and ((GetWindowLong(hEdit, GWL_STYLE) and ES_PASSWORD) <> 0);
end;

{ What the CONTROL says its selection is - the only reliable account of what the
  injected keys actually did, because the desktop's own modifier state is not
  enough: a stack that reshapes keys can report the modifier as held right up to
  the moment the next key is pressed (measured). False = this control cannot
  answer (it is not a standard EDIT/RICHEDIT, or the window is hung). }
function TargetSelection(hEdit: HWND; out AStart, AEnd: Integer): Boolean;
var
  Res: LRESULT;
begin
  Result := False;
  AStart := 0;
  AEnd := 0;
  if not IsStandardEditClass(hEdit) then
    Exit;
  if not SendTimed(hEdit, EM_GETSEL, 0, 0, Res) then
    Exit;
  AStart := Integer(DWORD(Res) and $FFFF);        // LOWORD = selection start
  AEnd := Integer((DWORD(Res) shr 16) and $FFFF); // HIWORD = selection end
  Result := True;
end;

function TryReadViaMessages(hEdit: HWND; out Ch: string): Boolean;
var
  Res:              LRESULT;
  SelStart, SelEnd: Integer;
  TextLen:          Integer;
  Buf:              string;
begin
  Result := False;
  Ch := '';
  if not IsStandardEditClass(hEdit) then
    Exit;
  if IsPasswordEdit(hEdit) then
    Exit;

  if not SendTimed(hEdit, WM_GETTEXTLENGTH, 0, 0, Res) then
    Exit;
  TextLen := Integer(Res);
  if (TextLen < 1) or (TextLen > SNIFF_MAX_TEXTLEN) then
    Exit; // empty doc, or too large for the EM_GETSEL lo/hi contract

  if not SendTimed(hEdit, EM_GETSEL, 0, 0, Res) then
    Exit;
  SelStart := DWORD(Res) and $FFFF;        // LOWORD = selection start
  SelEnd := (DWORD(Res) shr 16) and $FFFF; // HIWORD = selection end
  if SelStart <> SelEnd then
    Exit; // user has an active selection - do not disturb
  if SelStart < 1 then
    Exit; // caret at beginning of document

  SetLength(Buf, TextLen);
  if not SendTimed(hEdit, WM_GETTEXT, TextLen + 1, LPARAM(@Buf[1]), Res) then
    Exit;

  Ch := Buf[SelStart];
  Result := Ch <> '';
end;

{ =============================================================================== }
{ Layer B: the clipboard round-trip - Shift+Left x N, Ctrl+C, read, Right.

  Why the implementation looks the way it does
  --------------------------------------------
  The keys are injected, and injected keys are not private to this process: the
  whole desktop sees them, and the desktop does not always deliver them the way
  they were sent. A real machine was measured where an injected Shift down is
  answered by a Shift up nobody sent, so the arrow keys arrive UNMODIFIED - and
  the desktop's own modifier state (GetAsyncKeyState) reports the Shift as held
  right up to the moment the next key is pressed, so a modifier check alone
  cannot catch it. An unmodified Left MOVES THE CARET, and an unmodified 'C'
  TYPES A LETTER into the user's document.

  This layer promises that a failed read is invisible. It cannot keep that
  promise by trusting its own input, so it asks the CONTROL what happened and
  undoes exactly that:

    1. the caret/selection is read before anything is pressed (EM_GETSEL - a
       standard EDIT/RICHEDIT is the only kind of control that can answer);
    2. the modifier is confirmed against the desktop before its key is pressed,
       and released again with confirmation;
    3. after the arrow keys the control is asked again:
         * a selection of exactly the asked width, ending where the caret was
           -> the round-trip copies it, and ONE Right collapses it back;
         * no selection (the modifier was lost), or any other shape
           -> the caret is walked back to where it started, key by key, and
              NOTHING is copied - there is nothing to copy;
    4. the collapse only ever happens when a selection was really made, and the
       caret is re-read afterwards so a mis-undo is visible instead of silent.

  A host that cannot answer (Chrome, Office and everything else this layer exists
  for) keeps the older best-effort shape: select, copy, collapse with one Right -
  there is nothing else to go on there, and the layer stays off by default. }

{ The whole round-trip for ACount characters. False - with an empty AText - means
  no reading, and every path that answers False leaves the document, the caret
  and the clipboard as they were (or says in the debug log that it could not). }
function ClipboardRoundTrip(const ACount: Integer; out AText: string): Boolean;
var
  hEdit:            HWND;
  SelStart, SelEnd: Integer;
  Before:           Integer;
  Measured:         Boolean;
  Selected:         Boolean;
  Releasable:       Boolean;
  I:                Integer;
  SavedClip:        string;
  HadClip:          Boolean;
  Copied:           string;
begin
  Result := False;
  AText := '';
  Selected := False;
  Releasable := True;
  SelStart := 0;
  SelEnd := 0;

  hEdit := GetFocusedEditHandle;

  { A password field is never read, and an active selection belongs to the user:
    the round-trip would collapse it. Both are checked before any key is sent. }
  Measured := (hEdit <> 0) and TargetSelection(hEdit, SelStart, SelEnd);
  if hEdit <> 0 then
  begin
    if IsPasswordEdit(hEdit) then
      Exit;
    if Measured and (SelStart <> SelEnd) then
      Exit;
  end;

  Before := SelEnd; // = SelStart: nothing is selected at this point

  try
    SavedClip := Clipboard.AsText;
    HadClip := True;
  except
    HadClip := False;
  end;

  try
    { ---- 1. the modifier, then the arrow keys --------------------------- }
    if not ModifierDown(VK_SHIFT) then
      Exit; // nothing was pressed, so there is nothing to undo

    for I := 1 to ACount do
    begin
      SniffKeyEvent(VK_LEFT, False);
      SniffKeyEvent(VK_LEFT, True);
    end;
    Sleep(SNIFF_SEL_DELAY);

    Releasable := ModifierUp(VK_SHIFT, VK_LSHIFT);
    if not Releasable then
      AnsiTrace('clipboard: the desktop kept the injected Shift down; the keyboard is left alone');

    { ---- 2. what did the control actually do? --------------------------- }
    Selected := True; // a host that cannot answer keeps the best-effort shape
    if Measured then
    begin
      if not (TargetSelection(hEdit, SelStart, SelEnd) and (SelStart = Before - ACount) and (SelEnd = Before)) then
      begin
        Selected := False;
        AnsiTrace('clipboard: the arrows selected nothing - the caret is put back and nothing is copied');
        { Walk the caret home, re-reading after every key: one Right collapses a
          selection without moving it, and only the control can say which of the
          two each key just did. Bounded, and it stops as soon as it is home. }
        for I := 1 to (ACount * 2) + 2 do
        begin
          if TargetSelection(hEdit, SelStart, SelEnd) and (SelStart >= Before) and (SelEnd >= Before) then
            Break;
          SniffKeyEvent(VK_RIGHT, False);
          SniffKeyEvent(VK_RIGHT, True);
          Sleep(SNIFF_SEL_DELAY);
        end;
        if TargetSelection(hEdit, SelStart, SelEnd) and ((SelStart <> Before) or (SelEnd <> Before)) then
          AnsiTrace(Format('clipboard: the caret could not be put back (%d..%d, wanted %d)', [SelStart, SelEnd, Before]))
        else
          AnsiTrace('clipboard: the caret is back where it was');
      end;
    end;

    if not Releasable then
      Exit; // a stuck modifier: pressing anything more would make it worse
    if not Selected then
      Exit;

    { ---- 3. copy what is selected, and read it -------------------------- }
    if not CopySelection then
      Exit; // no verified Ctrl, so no 'C' was pressed either

    if Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT) then
    begin
      Copied := Clipboard.AsText;
      { NOTHING WAS COPIED when the clipboard still holds exactly what it held
        before the round-trip: an empty selection (the caret at the start of the
        document, a control that ignores Shift+Left, or a password field that
        refuses to copy) leaves the old content in place, and reporting its last
        character would be a reading of the CLIPBOARD, not of the caret.
        Refusing costs one missed character; accepting would erase text nobody
        readable ever read. }
      if (Copied <> '') and (not HadClip or (Copied <> SavedClip)) then
      begin
        AText := Copied;
        Result := True;
      end;
    end;
  finally
    { ---- 4. undo, and only what was really done ------------------------- }
    if Selected and Releasable then
    begin
      CollapseSelection; // the selection is [caret-ACount..caret]: ONE Right holds it
      if Measured and TargetSelection(hEdit, SelStart, SelEnd) and ((SelStart <> Before) or (SelEnd <> Before)) then
        AnsiTrace(Format('clipboard: the collapse left the caret at %d..%d instead of %d', [SelStart, SelEnd, Before]));
    end;

    if HadClip then
      try
        Clipboard.AsText := SavedClip;
      except
      end;
  end;
end;

{ The one-character form, kept for the legacy path (see the interface comment). }
function TryReadViaClipboard(out Ch: string): Boolean;
var
  Full: string;
begin
  Result := ClipboardRoundTrip(1, Full);
  if Result then
    Ch := Full[Length(Full)] // the character immediately before the caret
  else
    Ch := '';
end;

{ The width form: up to AMaxChars characters before the caret, for the glyphs
  that are several ANSI units wide. }
function SniffTextViaClipboard(const AMaxChars: Integer; out AText: string): Boolean;
begin
  AText := '';
  { Wider than any shipped glyph and narrower than the fixtures: a bigger
    selection is a bigger disturbance for no benefit. }
  if (AMaxChars < 1) or (AMaxChars > 64) then
    Exit(False);
  Result := ClipboardRoundTrip(AMaxChars, AText);
end;

{ =============================================================================== }

function SniffCharBeforeCaret(out Chars: string; out Kind: TSniffResult): Boolean;
var
  hEdit: HWND;
  Ch:    string;
begin
  Kind := srNone;
  Chars := '';
  Result := False;

  if SniffOverrideActive then
  begin
    { head-less test: no window, no clipboard, no reentrancy - just the
      context the case asked for ('' = nothing usable before the caret) }
    if SniffOverride = '' then
      Exit;
    Chars := SniffOverride;
    case Chars[1] of
      ' ', #9, #13, #10:
        Kind := srDelimiter;
      else
        if (Ord(Chars[1]) >= $0980) and (Ord(Chars[1]) <= $09FF) then
          Kind := srUnicodeChar
        else
          Kind := srAnsiGlyph;
    end;
    Result := True;
    Exit;
  end;

  if SniffingActive then
    Exit; // never reenter

  SniffingActive := True;
  try
    hEdit := GetFocusedEditHandle;
    if (hEdit <> 0) and TryReadViaMessages(hEdit, Ch) then
      // fast path succeeded
    else if EnableCaretSniffer = 'YES' then
      TryReadViaClipboard(Ch);
  finally
    SniffingActive := False;
  end;

  if (not Result) and (Ch <> '') then
    Result := True;
  if (not Result) or (Ch = '') then
    Exit;

  Chars := Ch;
  case Ch[1] of
    ' ', #9, #13, #10:
      Kind := srDelimiter;
    else
      if (Ord(Ch[1]) >= $0980) and (Ord(Ch[1]) <= $09FF) then
        Kind := srUnicodeChar
      else
        Kind := srAnsiGlyph;
  end;
end;

{ =============================================================================== }

function SniffTextBeforeCaret(const AMaxChars: Integer; out AText: string; out AReading: TSniffReading): Boolean;
var
  hEdit:                    HWND;
  Res:                      LRESULT;
  SelStart, SelEnd:         Integer;
  TextLen:                  Integer;
  Buf:                      string;
  Want:                     Integer;
begin
  AText := '';
  FillChar(AReading, SizeOf(AReading), 0);
  Result := False;

  { The head-less test hook: report exactly the context the case asked for, with
    no window and no message at all. }
  if SniffOverrideActive then
  begin
    if SniffOverride = '' then
      Exit;
    AText := SniffOverride;
    AReading.CaretIndex := Length(SniffOverride);
    AReading.TextLength := Length(SniffOverride);
    Result := True;
    Exit;
  end;

  hEdit := GetFocusedEditHandle;
  if (hEdit = 0) or (not IsStandardEditClass(hEdit)) then
    Exit;
  if IsPasswordEdit(hEdit) then
    Exit;

  if not SendTimed(hEdit, WM_GETTEXTLENGTH, 0, 0, Res) then
    Exit;
  TextLen := Integer(Res);
  if (TextLen < 1) or (TextLen > SNIFF_MAX_TEXTLEN) then
    Exit; // empty document, or too large for the EM_GETSEL lo/hi contract

  if not SendTimed(hEdit, EM_GETSEL, 0, 0, Res) then
    Exit;
  SelStart := DWORD(Res) and $FFFF;        // LOWORD = selection start
  SelEnd := (DWORD(Res) shr 16) and $FFFF; // HIWORD = selection end
  if SelStart <> SelEnd then
    Exit; // the user has an active selection - do not disturb
  if SelStart < 1 then
    Exit; // caret at the beginning of the document

  SetLength(Buf, TextLen);
  if not SendTimed(hEdit, WM_GETTEXT, TextLen + 1, LPARAM(@Buf[1]), Res) then
    Exit;

  Want := AMaxChars;
  if Want < 1 then
    Want := 1;
  if Want > SelStart then
    Want := SelStart;

  AText := Copy(Buf, SelStart - Want + 1, Want);
  AReading.Window := hEdit;
  AReading.CaretIndex := SelStart;
  AReading.TextLength := TextLen;
  Result := AText <> '';
end;

{ =============================================================================== }

end.
