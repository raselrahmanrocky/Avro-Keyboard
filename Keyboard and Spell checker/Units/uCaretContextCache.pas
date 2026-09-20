{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uCaretContextCache;

{ =============================================================================
  uCaretContextCache - what is on screen in FRONT of the caret?

  The engines' backspace works from their own committed-text ledger, because
  that is the only text whose units they know exactly. As soon as the caret
  moves - a mouse click, an arrow key, another application, a window that was
  already full of text when Avro started - the ledger describes nothing and a
  press has to fall back to the host's native backspace, which removes exactly
  ONE character. For an ANSI mapping a Bangla letter is often several
  characters (Ansi V3: i-kar = '\xA3z', u-kar = 'v\xFEz'), so the hook of the letter
  stays behind and the letter needs a second press.

  This unit holds the OTHER source of truth: a cached reading of the text
  immediately before the caret, taken by a reading layer that this unit does
  not implement. The reading layer is INJECTED, so the same cache serves the
  message-path reader (uCaretContextSniffer's SniffTextBeforeCaret), the UI
  Automation reader (uUIAText, which reaches Word, Excel, the browsers and
  other custom controls), the clipboard fallback and a head-less test. uCaretWatch
  installs that provider and drives one reading per burst from the application
  timer. Two rules decide the design:

  * The reading layer (UI Automation, clipboard) may block, allocate and take
    tens of milliseconds - Chromium enables accessibility lazily, so the first
    UIA call can cost ~100 ms. It therefore NEVER runs inside a keyboard hook.
    It runs from a timer / WinEvent context, and only through
    AnsiCaretContextRefresh.
  * Everything a hook touches is a cache read: no host call, no allocation, no
    wait. AnsiCaretContextTail / AnsiCaretContextVerify / Invalidate are O(1)
    and safe from WH_KEYBOARD_LL.

  Correctness stance: every function here answers "no reading" by default.
  A missing provider, a failed read, a stale cache or a moved caret all end in
  the caller falling back to the behaviour that shipped before this feature.
  Nothing in this unit ever guesses a width.
  ============================================================================= }

interface

uses
  Winapi.Windows;

type
  { Where a reading came from. A layer that failed is not believed later. }
  TAnsiContextSource = (csNone, csWindowText, csUIA, csClipboard, csInjected);

  { Everything that has to still be true when the press happens. A caret that
    moved, a different window, a changed text length - any difference means the
    cached tail does not describe what is on screen any more. }
  TCaretFingerprint = record
    Window:     HWND;
    CaretX:     Integer;
    CaretY:     Integer;
    TextLength: Integer; // characters before the caret in the focused control
  end;
  PCaretFingerprint = ^TCaretFingerprint;

  { One reading. Ok = False is a normal answer (a control that exposes no text,
    a denied UIA query, an empty caret context) and never an error. }
  TAnsiContextReading = record
    Ok:          Boolean;
    Tail:        string; // the text immediately before the caret, up to the budget
    Fingerprint: TCaretFingerprint;
    Source:      TAnsiContextSource;
  end;

  { The reading layer. Production installs the UI Automation reader first and
    the clipboard reader as the fallback; a head-less harness installs its own
    and needs no host at all. AMaxChars is the probe budget: a reader returns
    AT MOST that many characters, and may return fewer. }
  TAnsiContextProvider = function(const AMaxChars: Integer): TAnsiContextReading of object;

  { The cheap half of a reading layer: where the caret is right now. It must not
    block (the UIA reader caches its element) and exists so a destructive press
    can re-check its assumption. Optional: without it the cache is invalidated
    by events instead. }
  TAnsiFingerprintReader = function: TCaretFingerprint of object;

{ Turns the sniffer on/off and records whether decisions should be traced. The
  caller passes the registry settings; with AEnabled False every function here
  answers "no reading", so the press path is the pre-feature one. }
procedure AnsiCaretSnifferConfigure(const AEnabled, ADebugLog: Boolean);
function AnsiCaretSnifferEnabled: Boolean;
function AnsiCaretSnifferDebugLog: Boolean;

{ Installs the reading layer. Passing nil removes it (every read then fails),
  which is how production behaves before the UIA/clipboard readers exist. }
procedure AnsiCaretSnifferSetProvider(const AProvider: TAnsiContextProvider); overload;
procedure AnsiCaretSnifferSetProvider(const AProvider: TAnsiContextProvider; const AFingerprint: TAnsiFingerprintReader); overload;
procedure AnsiCaretSnifferClearProvider;
function AnsiCaretSnifferHasProvider: Boolean;

{ ---- burst accounting -------------------------------------------------------
  A burst is one user action's worth of work (a key press and what it triggers).
  Typing moves the caret on every keystroke, so without this a caret-move driven
  reader would run constantly. At most ONE reading is taken per burst; further
  refreshes answer from the cache. A refresh outside any burst (the caret watch's
  own tick) is always allowed.

  Opening a burst does NOT drop the cached reading: the press that needs it
  (Backspace) opens its burst first and must still see what the watch read
  before it. Dropping a reading is the watch's job - a caret move, a click or a
  focus change raises it - and the key handler drops it for every key except
  Backspace, after which nothing can be stale. }
procedure AnsiCaretBurstBegin;
procedure AnsiCaretBurstEnd;

{ The one expensive step. MUST NOT be called from a keyboard hook. Returns True
  only when the cache now holds a reading taken in this burst. }
function AnsiCaretContextRefresh(const AMaxChars: Integer): Boolean;
function AnsiCaretBurstRefreshed: Boolean;

{ ---- what a hook may call -------------------------------------------------- }

{ The cached text before the caret. False when there is no usable reading. }
function AnsiCaretContextTail(out ATail: string): Boolean;
function AnsiCaretContextSource: TAnsiContextSource;
function AnsiCaretContextFingerprint(out AFingerprint: TCaretFingerprint): Boolean;

{ Dropped when anything about the caret may have changed: another key, a mouse
  click, a WinEvent caret event, focus change, mapping switch, shutdown. O(1). }
procedure AnsiCaretContextInvalidate;
procedure AnsiCaretContextDrop(const AWhy: string);

{ True when the reading that is cached can still be trusted for a destructive
  press. With a fingerprint reader installed this re-reads the caret (cheap) and
  compares; without one it trusts the cache, whose invalidation is the
  guarantee. A failed check clears the cache, so the next press cannot use it. }
function AnsiCaretContextVerify: Boolean;

{ A fingerprint comparison that callers can use on their own readings. }
function AnsiFingerprintSame(const A, B: TCaretFingerprint): Boolean;

{ ---- test / embedding only ------------------------------------------------- }

{ Fills the cache as a reading layer would, so a harness can drive the whole
  path without a host window, a caret or a clipboard. }
procedure AnsiCaretContextInjectForTest(const ATail: string; const AFingerprint: TCaretFingerprint;
  const ASource: TAnsiContextSource = csInjected);
function AnsiCaretContextRefreshes: Integer; // how many readings were taken

{ ---- who the reading belongs to -------------------------------------------- }

{ The class names of the focused control and of the foreground window, as the
  watch's tick last saw them. Filled on the main thread (two GetClassName calls
  - no cross-process message, no blocking) so a PRESS can answer "may the host
  text be erased in this application?" from the cache, without a window query
  inside a keyboard hook. Case preserved; '' when unknown. }
procedure AnsiHostContextSet(const AFocusClass, AForegroundClass: string);
function AnsiHostFocusClass: string;
function AnsiHostForegroundClass: string;

implementation

uses
  System.SysUtils;

const
  { How much text a probe may read. Enough for the widest cluster any shipped
    mapping draws (Ansi V3 reaches four units) with room to spare, and short
    enough that a clipboard read stays a single cheap copy. }
  DEFAULT_PROBE_BUDGET = 32;

var
  FEnabled:       Boolean;
  FDebugLog:      Boolean;
  FProvider:      TAnsiContextProvider;
  FFingerprint:   TAnsiFingerprintReader;

  FHasReading:    Boolean;
  FTail:          string;
  FReadingFP:     TCaretFingerprint;
  FSource:        TAnsiContextSource;

  FInBurst:       Boolean;
  FBurstRefreshed: Boolean; // this burst already took its one reading
  FRefreshes:     Integer;

  FFocusClass:      string; // GetClassName of the focused control
  FForegroundClass: string; // GetClassName of the foreground window

function SourceName(const ASource: TAnsiContextSource): string;
begin
  case ASource of
    csWindowText:
      Result := 'the window text (messages)';
    csUIA:
      Result := 'UIA';
    csClipboard:
      Result := 'clipboard';
    csInjected:
      Result := 'injected';
  else
    Result := 'no reading layer';
  end;
end;

procedure AnsiTrace(const AText: string);
begin
  if FDebugLog then
    OutputDebugString(PChar('[AvroCaret] ' + AText));
end;

procedure AnsiCaretSnifferConfigure(const AEnabled, ADebugLog: Boolean);
begin
  FEnabled := AEnabled;
  FDebugLog := ADebugLog;
  if not AEnabled then
    AnsiCaretContextDrop('sniffer disabled');
end;

function AnsiCaretSnifferEnabled: Boolean;
begin
  Result := FEnabled;
end;

function AnsiCaretSnifferDebugLog: Boolean;
begin
  Result := FDebugLog;
end;

procedure AnsiCaretSnifferSetProvider(const AProvider: TAnsiContextProvider);
begin
  AnsiCaretSnifferSetProvider(AProvider, nil);
end;

procedure AnsiCaretSnifferSetProvider(const AProvider: TAnsiContextProvider; const AFingerprint: TAnsiFingerprintReader);
begin
  FProvider := AProvider;
  FFingerprint := AFingerprint;
  AnsiCaretContextDrop('provider changed');
end;

procedure AnsiCaretSnifferClearProvider;
begin
  FProvider := nil;
  FFingerprint := nil;
  AnsiCaretContextInvalidate;
end;

function AnsiCaretSnifferHasProvider: Boolean;
begin
  Result := Assigned(FProvider);
end;

procedure AnsiCaretContextInvalidate;
begin
  FHasReading := False;
  FTail := '';
  FSource := csNone;
  FillChar(FReadingFP, SizeOf(FReadingFP), 0);
end;

procedure AnsiCaretContextDrop(const AWhy: string);
begin
  if FHasReading and FDebugLog then
    AnsiTrace('context dropped (' + AWhy + ')');
  AnsiCaretContextInvalidate;
end;

procedure AnsiCaretBurstBegin;
begin
  FInBurst := True;
  FBurstRefreshed := False;
end;

procedure AnsiCaretBurstEnd;
begin
  FInBurst := False;
end;

function AnsiCaretBurstRefreshed: Boolean;
begin
  Result := FBurstRefreshed;
end;

function AnsiFingerprintSame(const A, B: TCaretFingerprint): Boolean;
begin
  Result := (A.Window = B.Window) and (A.CaretX = B.CaretX) and (A.CaretY = B.CaretY) and (A.TextLength = B.TextLength);
end;

function AnsiCaretContextRefresh(const AMaxChars: Integer): Boolean;
var
  Reading: TAnsiContextReading;
  Budget:  Integer;
begin
  Result := False;

  if not FEnabled then
    Exit;

  if not Assigned(FProvider) then
  begin
    AnsiCaretContextInvalidate;
    Exit;
  end;

  { One reading per burst. The caller may ask again after a new burst. }
  if FInBurst and FBurstRefreshed then
  begin
    Result := FHasReading;
    Exit;
  end;

  Budget := AMaxChars;
  if Budget <= 0 then
    Budget := DEFAULT_PROBE_BUDGET;

  try
    Reading := FProvider(Budget);
  except
    { A reading layer must never take the engine down: a failed probe is a
      normal outcome and simply leaves the pre-feature behaviour in place. }
    on E: Exception do
    begin
      AnsiTrace('provider raised ' + E.ClassName + ': ' + E.Message);
      AnsiCaretContextInvalidate;
      Exit;
    end;
  end;

  FBurstRefreshed := True;

  if not Reading.Ok then
  begin
    AnsiCaretContextDrop('provider has no reading');
    Exit;
  end;

  FHasReading := Reading.Tail <> '';
  FTail := Reading.Tail;
  FReadingFP := Reading.Fingerprint;
  FSource := Reading.Source;
  Inc(FRefreshes);

  AnsiTrace(Format('reading %d chars from %s before the caret', [Length(FTail), SourceName(FSource)]));
  Result := FHasReading;
end;

function AnsiCaretContextTail(out ATail: string): Boolean;
begin
  ATail := FTail;
  Result := FEnabled and FHasReading and (FTail <> '');
end;

function AnsiCaretContextSource: TAnsiContextSource;
begin
  if FEnabled and FHasReading then
    Result := FSource
  else
    Result := csNone;
end;

function AnsiCaretContextFingerprint(out AFingerprint: TCaretFingerprint): Boolean;
begin
  AFingerprint := FReadingFP;
  Result := FEnabled and FHasReading;
end;

function AnsiCaretContextVerify: Boolean;
var
  Now: TCaretFingerprint;
begin
  Result := False;

  if not FEnabled then
    Exit;
  if not FHasReading then
    Exit;

  { No fingerprint reader: the cache's own invalidation (any key, a caret
    event, a focus change) is the guarantee, and it is the one the reading
    layer's accuracy depends on anyway. }
  if not Assigned(FFingerprint) then
  begin
    Result := True;
    Exit;
  end;

  try
    Now := FFingerprint();
  except
    on E: Exception do
    begin
      AnsiCaretContextDrop('fingerprint reader raised ' + E.ClassName);
      Exit;
    end;
  end;

  if not AnsiFingerprintSame(Now, FReadingFP) then
  begin
    AnsiCaretContextDrop('caret moved since the reading');
    Exit;
  end;

  Result := True;
end;

function AnsiCaretContextRefreshes: Integer;
begin
  Result := FRefreshes;
end;

procedure AnsiHostContextSet(const AFocusClass, AForegroundClass: string);
begin
  FFocusClass := AFocusClass;
  FForegroundClass := AForegroundClass;
end;

function AnsiHostFocusClass: string;
begin
  Result := FFocusClass;
end;

function AnsiHostForegroundClass: string;
begin
  Result := FForegroundClass;
end;

procedure AnsiCaretContextInjectForTest(const ATail: string; const AFingerprint: TCaretFingerprint;
  const ASource: TAnsiContextSource);
begin
  FHasReading := ATail <> '';
  FTail := ATail;
  FReadingFP := AFingerprint;
  FSource := ASource;
  FBurstRefreshed := True;
end;

initialization
  FEnabled := False;
  FDebugLog := False;
  FProvider := nil;
  FFingerprint := nil;
  FRefreshes := 0;
  AnsiCaretContextInvalidate;

finalization
  AnsiCaretContextInvalidate;
end.
