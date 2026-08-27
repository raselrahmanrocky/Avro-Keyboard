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
  TSniffResult = (
    srNone,        // nothing usable before the caret (BOS/unknown app/failure)
    srAnsiGlyph,   // an ANSI (Bijoy font range) character
    srUnicodeChar, // a Unicode Bengali character ($0980..$09FF)
    srDelimiter    // space/tab/newline directly before the caret
  );

var
  SniffingActive: Boolean = False; // reentrancy guard checked by layout engines

// Reads one char left of the caret. Returns True when Chars is meaningful.
function SniffCharBeforeCaret(out Chars: string; out Kind: TSniffResult): Boolean;

implementation

uses
  Windows,
  Messages,
  SysUtils,
  Clipbrd,
  uRegistrySettings;

const
  SNIFF_MSG_TIMEOUT = 100; // ms per SendMessageTimeout
  SNIFF_MAX_TEXTLEN = $F000; // above this EM_GETSEL lo/hi contract is unsafe
  SNIFF_COPY_DELAY = 25;   // ms wait after Ctrl+C
  SNIFF_SEL_DELAY = 12;    // ms wait after Shift+Left

{ =============================================================================== }

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

function TryReadViaMessages(hEdit: HWND; out Ch: string): Boolean;
var
  Res:     LRESULT;
  SelStart, SelEnd: Integer;
  TextLen: Integer;
  Buf:     string;
begin
  Result := False;
  Ch := '';
  if not IsStandardEditClass(hEdit) then
    Exit;

  TextLen := 0;
  if SendMessageTimeout(hEdit, WM_GETTEXTLENGTH, 0, 0, SMTO_ABORTIFHUNG, SNIFF_MSG_TIMEOUT, @Res) <> 0 then
    TextLen := Integer(Res)
  else
    Exit;
  if (TextLen < 1) or (TextLen > SNIFF_MAX_TEXTLEN) then
    Exit; // empty doc, or too large for the EM_GETSEL lo/hi contract

  Res := SendMessageTimeout(hEdit, EM_GETSEL, 0, 0, SMTO_ABORTIFHUNG, SNIFF_MSG_TIMEOUT, nil);
  if Res = 0 then
    Exit;
  SelStart := DWORD(Res) and $FFFF;         // LOWORD = selection start
  SelEnd := (DWORD(Res) shr 16) and $FFFF;  // HIWORD = selection end
  if SelStart <> SelEnd then
    Exit; // user has an active selection - do not disturb
  if SelStart < 1 then
    Exit; // caret at beginning of document

  SetLength(Buf, TextLen);
  if SendMessageTimeout(hEdit, WM_GETTEXT, TextLen + 1, LPARAM(@Buf[1]), SMTO_ABORTIFHUNG, SNIFF_MSG_TIMEOUT, @Res) = 0 then
    Exit;

  Ch := Buf[SelStart];
  Result := Ch <> '';
end;

{ =============================================================================== }
// Layer B: clipboard round-trip (Shift+Left -> Ctrl+C -> read -> Right).

function TryReadViaClipboard(out Ch: string): Boolean;
var
  hEdit: HWND;
  Res: LRESULT;
  SelStart, SelEnd: Integer;
  SavedClip: string;
  HadClip:   Boolean;
begin
  Result := False;
  Ch := '';
  SavedClip := '';
  HadClip := False;

  // Abort if the target has an active selection – the clipboard round-trip
  // (Shift+Left / Ctrl+C / Right) would collapse it, disturbing the user.
  hEdit := GetFocusedEditHandle;
  if hEdit <> 0 then
  begin
    Res := SendMessageTimeout(hEdit, EM_GETSEL, 0, 0, SMTO_ABORTIFHUNG, SNIFF_MSG_TIMEOUT, nil);
    if Res <> 0 then
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
        Ch := Clipboard.AsText;
        if Length(Ch) >= 1 then
        begin
          Ch := Ch[Length(Ch)]; // last copied char = char before original caret
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

function SniffCharBeforeCaret(out Chars: string; out Kind: TSniffResult): Boolean;
var
  hEdit: HWND;
  Ch:    string;
begin
  Kind := srNone;
  Chars := '';
  Result := False;

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

end.
