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
  uRegistrySettings;

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

procedure SelectOneCharLeft;
begin
  SniffKeyEvent(VK_SHIFT, False);
  Sleep(SNIFF_SEL_DELAY);
  SniffKeyEvent(VK_LEFT, False);
  SniffKeyEvent(VK_LEFT, True);
  Sleep(SNIFF_SEL_DELAY);
  SniffKeyEvent(VK_SHIFT, True);
  Sleep(SNIFF_SEL_DELAY);
end;

procedure CopySelection;
begin
  SniffKeyEvent(VK_CONTROL, False);
  Sleep(SNIFF_SEL_DELAY);
  SniffKeyEvent(Ord('C'), False);
  SniffKeyEvent(Ord('C'), True);
  Sleep(SNIFF_SEL_DELAY);
  SniffKeyEvent(VK_CONTROL, True);
end;

procedure CollapseSelection;
begin
  // Selection was [(caret-1)..caret]; Right collapses back to the original pos
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
// Layer B: clipboard round-trip (Shift+Left -> Ctrl+C -> read -> Right).

function TryReadViaClipboard(out Ch: string): Boolean;
var
  hEdit:            HWND;
  Res:              LRESULT;
  SelStart, SelEnd: Integer;
  SavedClip:        string;
  HadClip:          Boolean;
  Full:             string;
begin
  Result := False;
  Ch := '';
  SavedClip := '';
  HadClip := False;

  // Abort if the target is a password field (a secret is never a caret
  // context), or if it has an active selection – the round-trip
  // (Shift+Left / Ctrl+C / Right) would collapse that selection, disturbing
  // the user.
  hEdit := GetFocusedEditHandle;
  if hEdit <> 0 then
  begin
    if IsPasswordEdit(hEdit) then
      Exit;
    if SendTimed(hEdit, EM_GETSEL, 0, 0, Res) and (Res <> 0) then
    begin
      SelStart := DWORD(Res) and $FFFF;
      SelEnd := (DWORD(Res) shr 16) and $FFFF;
      if SelStart <> SelEnd then
        Exit; // active selection – do not disturb
    end;
  end;

  // Snapshot the existing clipboard text (best effort)
  try
    SavedClip := Clipboard.AsText;
    HadClip := True;
  except
    HadClip := False;
  end;

  try
    SelectOneCharLeft;
    CopySelection;

    try
      if Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT) then
      begin
        Full := Clipboard.AsText;
        { NOTHING WAS COPIED when the clipboard still holds exactly what it held
          before the round-trip: an empty selection (the caret at the start of
          the document, a control that ignores Shift+Left, or a password field
          that refuses to copy) leaves the old content in place, and reporting
          its last character would be a reading of the CLIPBOARD, not of the
          caret. Refusing costs one missed character; accepting would erase
          text of a document nobody ever read. }
        if (Full <> '') and (not HadClip or (Full <> SavedClip)) then
        begin
          Ch := Full[Length(Full)]; // last copied char = char before original caret
          Result := True;
        end;
      end;
    except
      Result := False;
    end;
  finally
    CollapseSelection;
    // Restore previous clipboard content (CF_UNICODETEXT snapshot only -
    // other formats are lost during a sniff; gated by EnableCaretSniffer)
    if HadClip then
      try
        Clipboard.AsText := SavedClip;
      except
      end;
  end;
end;

{ =============================================================================== }
// Layer C (N characters): see the interface comment for the contract.

function SniffTextViaClipboard(const AMaxChars: Integer; out AText: string): Boolean;
var
  hEdit:            HWND;
  Res:              LRESULT;
  SelStart, SelEnd: Integer;
  SavedClip:        string;
  HadClip:          Boolean;
  I:                Integer;
  Copied:           string;
begin
  Result := False;
  AText := '';

  // A wider selection is a bigger disturbance for no benefit: no glyph any
  // shipped mapping draws is longer than a handful of units.
  if (AMaxChars < 1) or (AMaxChars > 64) then
    Exit;

  // A password field is never read, and an active selection belongs to the
  // user: the collapse below would destroy it, and the caret would not be where
  // the eraser assumes either.
  hEdit := GetFocusedEditHandle;
  if hEdit <> 0 then
  begin
    if IsPasswordEdit(hEdit) then
      Exit;
    if SendTimed(hEdit, EM_GETSEL, 0, 0, Res) and (Res <> 0) then
    begin
      SelStart := DWORD(Res) and $FFFF;
      SelEnd := (DWORD(Res) shr 16) and $FFFF;
      if SelStart <> SelEnd then
        Exit;
    end;
  end;

  try
    SavedClip := Clipboard.AsText;
    HadClip := True;
  except
    HadClip := False;
  end;

  try
    try
      // Select AMaxChars characters to the LEFT of the caret. The anchor stays
      // at the caret, so ONE Right collapses back to it (that is the same
      // contract CollapseSelection relies on).
      SniffKeyEvent(VK_SHIFT, False);
      Sleep(SNIFF_SEL_DELAY);
      for I := 1 to AMaxChars do
      begin
        SniffKeyEvent(VK_LEFT, False);
        SniffKeyEvent(VK_LEFT, True);
      end;
      Sleep(SNIFF_SEL_DELAY);
      SniffKeyEvent(VK_SHIFT, True);
      Sleep(SNIFF_SEL_DELAY);

      CopySelection;

      if Clipboard.HasFormat(CF_UNICODETEXT) or Clipboard.HasFormat(CF_TEXT) then
      begin
        Copied := Clipboard.AsText;
        { The same guard as the one-character form: an unchanged clipboard means
          the copy produced nothing (the caret was already at the start, or the
          control refused), and the old clipboard text is not a reading of the
          document. }
        if (Copied <> '') and (not HadClip or (Copied <> SavedClip)) then
        begin
          AText := Copied;
          Result := True;
        end;
      end;
    except
      Result := False;
      AText := '';
    end;
  finally
    CollapseSelection;
    if HadClip then
      try
        Clipboard.AsText := SavedClip;
      except
      end;
  end;
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
