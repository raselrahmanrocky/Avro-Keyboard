{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uCaretWatch;

{ =============================================================================
  uCaretWatch - keeps uCaretContextCache's reading of the text in front of the
  caret honest, without ever doing real work inside a hook.

  Three jobs:

  1. KNOW WHEN THE READING IS WRONG. A WinEvent hook (caret moved, focus
     changed, another window came to the front) and a low-level mouse hook (a
     click may move the caret without the target raising a caret event at all -
     a native edit control usually does not) both do nothing but this:

         AnsiCaretContextInvalidate;   // O(1), no host call, no allocation
         FPending := True;             // a refresh is wanted

     Both callbacks are allocation free, call no window API that can block and
     always fall through (CallNextHookEx). Callbacks raised by Avro's own
     synthetic input are ignored: the message-path reader sends none, and the
     clipboard round-trip of uCaretContextSniffer stamps its key events with
     AVRO_SNIFF_TAG, so it can never invalidate a reading it is about to take.

  2. TAKE THE READING - OUTSIDE EVERY HOOK. AnsiCaretWatchTick runs on the
     application's timer, on the main thread: it opens one burst and asks the
     cache for a reading, which calls the provider installed below. The provider
     is SniffTextBeforeCaret, the MESSAGE-path reader (EM_GETSEL + WM_GETTEXT on
     a standard Edit / RichEdit): no synthetic keys, no clipboard, no focus
     change. Only a refresh can cost milliseconds, and only a timer calls it.

  3. INSTALL ITSELF. AnsiCaretWatchStart/Stop are idempotent and safe to call
     from the form's startup and shutdown. With the feature switched off
     (uAnsiBackspace.AnsiBackspaceEnabled = False) the two hooks still install -
     they are two OS callbacks that set a flag, and that part is cheap - but the
     TICK then does nothing at all: no burst, no provider, and above all no
     reading. That distinction is the point of this unit: the clipboard layer
     injects keys into whatever application is in the foreground and rewrites
     the user's clipboard, and doing that for a description the press path will
     discard is not acceptable, whatever it costs. Stopping is what a shutdown
     must do: both hooks belong to this process only.
  ============================================================================= }

interface

uses
  Winapi.Windows;

type
  { The low-level mouse hook structure (MSLLHOOKSTRUCT). This Delphi's
    Winapi.Windows has no declaration for it, and the TMouseHookStruct that it
    DOES declare has a different layout (no mouseData / flags), so reading
    flags out of that one would read the wrong field. Field order and natural
    alignment here match the Win32 structure. }
  TMsllHookStruct = record
    pt:           TPoint;
    mouseData:    DWORD;
    flags:        DWORD; // LLMHF_INJECTED lives here
    time:         DWORD;
    dwExtraInfo:  NativeUInt;
  end;
  PMsllHookStruct = ^TMsllHookStruct;

{ Installs the hooks and the reading provider. Idempotent. }
procedure AnsiCaretWatchStart;

{ The same provider, the same budget and the same "an event asked for a refresh"
  machinery, but WITHOUT the OS hooks - for a head-less harness, where the live
  desktop would raise real WinEvents (any other application's caret) between the
  tick and the assertion. Production always uses AnsiCaretWatchStart. }
procedure AnsiCaretWatchStartHeadless;
{ Removes both hooks and drops any reading. Idempotent; call it at shutdown. }
procedure AnsiCaretWatchStop;
function AnsiCaretWatchActive: Boolean;
function AnsiCaretWatchWindow: HWND; // the window the WinEvent hook is attached to (0 = process wide)

{ Main thread, from the application timer: takes ONE reading when something
  raised a refresh request, and nothing at all otherwise. Never call it from a
  hook. }
procedure AnsiCaretWatchTick;

{ The event half, exposed so a caller (or a head-less test) can raise the same
  request the hooks raise. O(1). }
procedure AnsiCaretWatchNoteCaretEvent(const AWhat: string);

{ How many events were seen and how many refreshes were taken. Diagnostics. }
procedure AnsiCaretWatchStats(out AEvents, ARefreshes: Integer);
function AnsiCaretWatchHostReadable: Boolean; // the message-path reader found a standard edit

implementation

uses
  System.SysUtils,
  Winapi.Messages,
  uCaretContextCache,
  uCaretContextSniffer,
  uRegistrySettings,
  uUIAText,
  uAnsiBackspace; // AnsiBackspaceEnabled: the master switch the tick honours

const
  { How much text one reading may hold. Wider than any glyph the shipped
    mappings draw (Ansi V3 reaches four units), narrow enough to stay a single
    short copy out of the control. }
  WATCH_PROBE_CHARS = 32;

  { LLMHF_INJECTED: set in MSLLHOOKSTRUCT.flags for input this process (or any
    automation) injected. This Delphi's Winapi.Windows declares no such
    constant, so it is named here - the same way KeyboardHook.pas names
    LLKHF_INJECTED for the keyboard side. }
  LLMHF_INJECTED_FLAG = $00000001;

type
  { The reading layer this unit installs. A class, because the cache takes
    method pointers: production code (anything with state of its own) can then
    replace it without changing the cache. }
  TCaretReader = class
  public
    { The message-path reader plus the cheap caret probe. }
    function ReadContext(const AMaxChars: Integer): TAnsiContextReading;
    function ReadFingerprint: TCaretFingerprint;
  end;

const
  { The three events the watch subscribes to. All must be unhooked at stop, or
    the OS keeps calling into this process after the form is gone. }
  WATCH_EVENTS: array [0 .. 2] of DWORD = (EVENT_OBJECT_LOCATIONCHANGE, EVENT_OBJECT_FOCUS, EVENT_SYSTEM_FOREGROUND);

var
  { Handles, not HWINEVENTHOOK: this Delphi's Winapi.Windows declares
    SetWinEventHook / UnhookWinEvent but not the handle type name, and a handle
    is what they take and return either way. }
  FWinHooks:      array [0 .. 2] of THandle;
  FMouseHook:     HHOOK;
  FActive:        Boolean;
  FReader:        TCaretReader;
  FUia:           TUiaTextReader; // LAYER B: created on first need, freed at shutdown

  FPending:       Boolean; // an event asked for a refresh; the timer will take it
  FEvents:        Integer;
  FRefreshes:     Integer;
  FHostReadable:  Boolean;
  FOffTraced:     Boolean; // the "switched off" line is written once, not per tick

{ ------------------------------------------------------------------------------ }
{ the cheap caret probe: one local API call, no cross-process message, no wait.
  It is used for BOTH the reading's fingerprint and the verification, so the two
  describe the same kind of moment. }

function CaretFingerprint: TCaretFingerprint;
var
  GTI: TGUITHREADINFO;
begin
  FillChar(Result, SizeOf(Result), 0);
  FillChar(GTI, SizeOf(GTI), 0);
  GTI.cbSize := SizeOf(GTI);
  if GetGUIThreadInfo(0, GTI) then
  begin
    if GTI.hwndCaret <> 0 then
      Result.Window := GTI.hwndCaret
    else
      Result.Window := GTI.hwndFocus;
    Result.CaretX := GTI.rcCaret.Left;
    Result.CaretY := GTI.rcCaret.Top;
  end;
end;

{ ------------------------------------------------------------------------------ }
{ the reading provider the cache calls }

function TCaretReader.ReadContext(const AMaxChars: Integer): TAnsiContextReading;
var
  Text:    string;
  Reading: TSniffReading;
begin
  Result.Ok := False;
  Result.Tail := '';
  Result.Source := csNone;
  Result.Fingerprint := CaretFingerprint;

  { The readers report where they read, but the cache compares only what
    CaretFingerprint can re-read cheaply at press time. TextLength is therefore
    declared as 0 on BOTH sides: a length comparison would need the
    cross-process message the press path must not send. What catches "the text
    changed" is the caret geometry plus the event-driven invalidation - every
    keystroke we make moves the caret, and the watch sees it. }
  Result.Fingerprint.TextLength := 0;

  { LAYER A - the message path (EM_GETSEL + WM_GETTEXT on a standard EDIT or
    RICHEDIT): no COM, no clipboard, no injected key, no focus change. }
  if SniffTextBeforeCaret(AMaxChars, Text, Reading) then
  begin
    FHostReadable := True;
    Result.Ok := Text <> '';
    Result.Tail := Text;
    Result.Source := csWindowText;
    Exit;
  end;

  FHostReadable := False;

  { LAYER B - UI Automation, for the hosts the message path cannot reach (Word,
    Excel, the browsers, VS Code, LibreOffice). One read per burst, on the main
    thread, outside every hook; a missing or refused pattern is a normal answer
    and simply falls through. The reader itself caches the element of the focused
    control (with its pattern and its password verdict) and budgets its probes,
    so neither a blinking caret nor a host with no text to offer can turn this
    into a stream of cross-process calls.

    The master switch is asked here as well as in the tick: a reader that is
    switched off is not INSTALLED - the UI Automation client is never created,
    nothing is probed, and no clipboard round-trip can start. }
  if AnsiBackspaceEnabled and (AnsiBackspaceUIA = 'YES') then
  begin
    if FUia = nil then
      FUia := TUiaTextReader.Create;
    Text := FUia.ReadBeforeCaret(AMaxChars);
    if Text <> '' then
    begin
      Result.Ok := True;
      Result.Tail := Text;
      Result.Source := csUIA;
      Exit;
    end;
  end;

  { LAYER C - the clipboard round-trip, the most invasive layer: only when it is
    switched on, and only after A and B both came back empty. }
  if AnsiBackspaceEnabled and (AnsiBackspaceClipboard = 'YES') then
    if SniffTextViaClipboard(AMaxChars, Text) and (Text <> '') then
    begin
      Result.Ok := True;
      Result.Tail := Text;
      Result.Source := csClipboard;
    end;
end;

function TCaretReader.ReadFingerprint: TCaretFingerprint;
begin
  Result := CaretFingerprint;
  Result.TextLength := 0; // see ReadContext
end;

{ ------------------------------------------------------------------------------ }
{ the hooks: nothing but an invalidation, a flag and CallNextHookEx }

procedure AnsiCaretWatchNoteCaretEvent(const AWhat: string);
begin
  Inc(FEvents);
  AnsiCaretContextDrop(AWhat);
  FPending := True;
end;

procedure WinEventProc(hWinEventHook: THandle; event: DWORD; hwnd: HWND; idObject: LongInt; idChild: LongInt;
  dwEventThread: DWORD; dwmsEventTime: DWORD); stdcall;
begin
  { Deliberately minimal: no window text, no UIA, no allocation. The reading is
    taken later, by the timer, on the main thread. Wrapped because a WinEvent
    callback that raises would be swallowed by the OS anyway and leave the flag
    half set. }
  try
    case event of
      EVENT_SYSTEM_FOREGROUND:
        AnsiCaretWatchNoteCaretEvent('foreground window changed');
      EVENT_OBJECT_FOCUS:
        AnsiCaretWatchNoteCaretEvent('focus changed');
    else
      { EVENT_OBJECT_LOCATIONCHANGE for the caret (idObject = OBJID_CARET), and
        for a text control whose text grew or shrank. Both mean the screen in
        front of the caret is not what the reading describes. LongInt() because
        OBJID_CARET / OBJID_CLIENT are unsigned $FFFFFFF8 / $FFFFFFFC: without
        the cast the comparison widens and is always False. }
      if (idObject = LongInt(OBJID_CARET)) or (idObject = LongInt(OBJID_CLIENT)) then
        AnsiCaretWatchNoteCaretEvent('caret or text moved');
    end;
  except
    // never let a callback die into the message queue
  end;
end;

function MouseHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  Info: PMsllHookStruct;
begin
  if nCode = HC_ACTION then
  begin
    Info := PMsllHookStruct(lParam);
    { An injected click is Avro's own (or a test's) and must not invalidate a
      reading this process is about to take. A real click moves the caret in
      most hosts without raising a caret WinEvent, which is exactly the gap this
      hook closes. A case, not a set: the button messages reach $20D, above the
      255 a Pascal set can hold. }
    if (Info <> nil) and (Info^.flags and LLMHF_INJECTED_FLAG = 0) then
    begin
      case wParam of
        WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MBUTTONDOWN, WM_MBUTTONUP, WM_RBUTTONDOWN, WM_RBUTTONUP, WM_XBUTTONDOWN,
          WM_XBUTTONUP, WM_XBUTTONDBLCLK:
          try
            AnsiCaretWatchNoteCaretEvent('mouse click');
          except
          end;
      end;
    end;
  end;

  Result := CallNextHookEx(FMouseHook, nCode, wParam, lParam);
end;

{ ------------------------------------------------------------------------------ }

{ Installs the reading layer: the provider and the cache's on/off switch. Shared
  by both starts, so a head-less start reads exactly like the production one. }
procedure InstallReader;
begin
  if FReader = nil then
    FReader := TCaretReader.Create;
  AnsiCaretSnifferSetProvider(FReader.ReadContext, FReader.ReadFingerprint);
  { The cache's switch and its debug flag come from the settings, so the trace
    of every reading / dropped context is one registry value away (AnsiBackspaceLog). }
  AnsiCaretSnifferConfigure(True, AnsiBackspaceLog = 'YES');
end;

{ The class names of the focused control and of the foreground window are cached
  here (two GetClassName calls on the main thread - no cross-process message, no
  wait) so the PER-APP override can be answered from the cache when a press
  happens inside the keyboard hook. }
procedure NoteHostIdentity;
var
  GTI:   TGUITHREADINFO;
  Buf:   array [0 .. 255] of Char;
  Focus: string;
  Fore:  string;
  hFore: HWND;
begin
  Focus := '';
  Fore := '';

  FillChar(GTI, SizeOf(GTI), 0);
  GTI.cbSize := SizeOf(GTI);
  if GetGUIThreadInfo(0, GTI) and (GTI.hwndFocus <> 0) then
    if GetClassName(GTI.hwndFocus, Buf, Length(Buf)) > 0 then
      Focus := Buf;

  hFore := GetForegroundWindow;
  if hFore <> 0 then
    if GetClassName(hFore, Buf, Length(Buf)) > 0 then
      Fore := Buf;

  AnsiHostContextSet(Focus, Fore);
end;

procedure AnsiCaretWatchStart;
var
  I: Integer;
begin
  if FActive then
    Exit;

  InstallReader;

  { Process wide (thread 0), delivered to this thread's queue, and OUTOFCONTEXT
    so the OS never waits for us. The flag is what the callback sets; the timer
    does the work. }
  for I := Low(WATCH_EVENTS) to High(WATCH_EVENTS) do
    FWinHooks[I] := SetWinEventHook(WATCH_EVENTS[I], WATCH_EVENTS[I], 0, @WinEventProc, 0, 0,
      WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);

  FMouseHook := SetWindowsHookEx(WH_MOUSE_LL, @MouseHookProc, hInstance, 0);
  FPending := True; // take one reading right away

  FActive := False;
  for I := Low(WATCH_EVENTS) to High(WATCH_EVENTS) do
    if FWinHooks[I] <> 0 then
      FActive := True;
  if FMouseHook <> 0 then
    FActive := True;

  if not FActive then
    AnsiCaretContextDrop('the watch could not install');
end;

procedure AnsiCaretWatchStartHeadless;
begin
  if FActive then
    Exit;

  InstallReader;
  FPending := True;
  FActive := True; // the tick path, without any OS hook
end;

procedure AnsiCaretWatchStop;
var
  I: Integer;
begin
  if FMouseHook <> 0 then
  begin
    UnhookWindowsHookEx(FMouseHook);
    FMouseHook := 0;
  end;

  for I := Low(WATCH_EVENTS) to High(WATCH_EVENTS) do
    if FWinHooks[I] <> 0 then
    begin
      UnhookWinEvent(FWinHooks[I]);
      FWinHooks[I] := 0;
    end;

  AnsiCaretSnifferClearProvider;
  AnsiCaretSnifferConfigure(False, False);
  FPending := False;
  FActive := False;
end;

{ The reader is kept for the unit's lifetime once created: a start/stop cycle
  during a version switch must not drop the class an installed provider points
  at. The UI Automation reader goes with it - it owns a cached COM object and,
  only if it opened one itself, an apartment. }
procedure AnsiCaretWatchReleaseReader;
begin
  FreeAndNil(FReader);
  FreeAndNil(FUia);
end;

function AnsiCaretWatchActive: Boolean;
begin
  Result := FActive;
end;

function AnsiCaretWatchWindow: HWND;
begin
  Result := 0;
end;

procedure AnsiCaretWatchTick;
begin
  if not FActive then
    Exit;
  if not FPending then
    Exit;

  FPending := False;

  { Switched off: the feature takes no reading at all. The hooks stay installed -
    they only set a flag - but nothing below this line runs, so a user who turned
    smart backspace off cannot have keys injected into the application they are
    typing in, and cannot have their clipboard rewritten, for a reading that
    uAnsiBackspace would discard unread. Traced once per off period, not per
    tick: the log says why there is nothing to see instead of flooding it. }
  if not AnsiBackspaceEnabled then
  begin
    if not FOffTraced then
    begin
      FOffTraced := True;
      AnsiTrace('watch: smart backspace is switched off, so nothing is read');
    end;
    Exit;
  end;
  FOffTraced := False; // a later switch-on reads again

  NoteHostIdentity;

  { One burst, one reading: the budget in the cache makes a second ask in the
    same tick free, so a timer that fires while a control is busy cannot turn
    into a stream of probes. }
  AnsiCaretBurstBegin;
  try
    if AnsiCaretContextRefresh(WATCH_PROBE_CHARS) then
      Inc(FRefreshes);
  finally
    AnsiCaretBurstEnd;
  end;
end;

procedure AnsiCaretWatchStats(out AEvents, ARefreshes: Integer);
begin
  AEvents := FEvents;
  ARefreshes := FRefreshes;
end;

function AnsiCaretWatchHostReadable: Boolean;
begin
  Result := FHostReadable;
end;

initialization
  FWinHooks[0] := 0;
  FWinHooks[1] := 0;
  FWinHooks[2] := 0;
  FMouseHook := 0;
  FActive := False;
  FReader := nil;
  FPending := False;
  FEvents := 0;
  FRefreshes := 0;
  FHostReadable := False;
  FOffTraced := False;

finalization
  AnsiCaretWatchStop;
  AnsiCaretWatchReleaseReader;
end.
