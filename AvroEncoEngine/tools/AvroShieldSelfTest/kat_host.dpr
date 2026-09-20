{

  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================

  kat_host - the reading layers against REAL controls in a REAL other process.

  kat_grapheme proves the WIDTH of one press with fakes: a fake reading layer, a
  fake ledger, no window at all. This program proves the three REAL readers - and
  the hook layer above them - against controls it creates itself:

    A. THE MESSAGE PATH (uCaretContextSniffer.SniffTextBeforeCaret): EM_GETSEL +
       WM_GETTEXT on a standard EDIT and on a RICHEDIT. This is what a multi-unit
       erase uses, and the only layer with no side effects at all.
    B. UI AUTOMATION (uUIAText.TUiaTextReader): a real COM client against the
       same controls - the layer that reaches Word, Excel, the browsers and any
       other custom control. The element/pattern cache and the probe budget are
       observed through its own counters.
    C. THE CLIPBOARD ROUND-TRIP (uCaretContextSniffer.SniffTextViaClipboard):
       Shift+Left / Ctrl+C / Right, with the previous clipboard put back and the
       caret restored - the most invasive layer, used only when switched on.
    D. THE HOOK LAYER: a real WH_KEYBOARD_LL hook that does what the shipped
       `KeyboardHook` does for the caret context (one burst per key, the reading
       dropped for every key except the one that needs it), driven by a REAL key
       press sent with SendInput, with the application's OWN watch
       (uCaretWatch - the same WinEvent and mouse hooks it installs) taking the
       reading at the caret that press moved to. The press is then carried
       through to ONE emission of the mapping's own width, captured instead of
       injected.

  What this proves that the head-less gate cannot: the readers really read the
  caret through the real APIs, a password field is refused by every layer, an
  unchanged clipboard is not mistaken for a reading, the element cache and the
  probe budget behave as documented, and a real key press reaches a real hook and
  leaves the caret context in exactly the state the press path expects.

  HOW IT RUNS, AND WHY THE WINDOW LIVES IN A CHILD PROCESS
  --------------------------------------------------------
  * The program starts a SECOND COPY OF ITSELF with `--serve`. That copy creates
    the window - an Edit, a second Edit rendered by the RichEdit class, a
    multi-line Edit and a password Edit - and sits in its own message loop; this
    copy drives it through window messages and reads it through the layers.

  * Why a child process and not a window of our own: every reading layer has to
    reach ANOTHER PROCESS, and UI Automation makes the difference measurable. A
    UIA client gets a control pattern object for a control of another process,
    but a control in the CLIENT's OWN process is served by the in-process
    provider path: it answers the cheap properties (class, handle, control type,
    "text pattern available") and then hands back NO pattern object at all, so
    GetCurrentPatternAs returns S_OK with a null pointer and the reader looks
    broken while the host is perfectly readable by the shipped application. The
    same is true of the caret events the watch subscribes to: its WinEvent hook
    skips its own process by design, so a caret moved inside this process could
    never reach it. Wrapping the controls in a child process removes both
    artifacts: what is tested is what the product does.

  * A real desktop and a real clipboard are still needed. Every reading layer
    describes the ACTIVE window (GetGUIThreadInfo(0) is the FOREGROUND thread's
    info - the documentation is explicit about the 0), so the child's window has
    to hold the foreground: without it there is nothing to read, and the program
    says so and exits with 2 instead of reporting imaginary failures.

  * The CLIPBOARD cases are the only ones that inject keys, and injected keys go
    to the FOREGROUND window of the whole desktop. Two things can take that away
    from them and neither is the layer's fault: another application grabbing the
    foreground mid-sequence (this run takes it back and retries, and names the
    window that did it), and a desktop that RESHAPES an injected modifier -
    measured on the machine this was written on, where an injected Shift down is
    followed by a Shift up the run never sent, so the Left key arrives unshifted
    and selects nothing. When the keys do not take effect, the run says which
    step failed and SKIPS the round-trip cases rather than reporting a broken
    layer. What the control received, and who held the foreground when each key
    was sent, is written to %TEMP%\kat_host.child.log for exactly that case.

  * Nothing is typed into another application: the only foreign window is the
    copy of this program that this run started, and it is closed at the end. The
    emission of the last case is captured, never sent.

  What a SKIP means
  -----------------
  A skipped case is a case the arrangement could not put the layer into - the
  foreground could not be taken, the rich edit class is missing, or the desktop
  reshapes an injected key (see above). It is reported SEPARATELY from a failed
  check and does not make the run fail: the summary prints "N checks, F
  failures, S skipped", and only F makes the exit code 1. The reason is printed
  with it, so a skip is never silent.

  E. THE HOST MATRIX (`--matrix`) and F. THE PROBE (`--probe`) answer the two
     questions the cases above cannot. The matrix measures the hosts this program
     created AND names the real ones it can only find (Notepad, WordPad, Word,
     Excel, Chrome/Edge, VS Code, LibreOffice Writer) - a harness never types into
     somebody's document, so a real host is a row saying what was found and what
     to run instead. The probe describes whatever window is in the FOREGROUND at
     that moment through the same layers and prints one line, without typing,
     without selecting and without touching the clipboard: run it with Word in
     front and paste the line into a bug report.

  Usage: kat_host [quiet] [--matrix]
         kat_host --probe [quiet]                (no child process: the window in front)
         kat_host --serve <parent-pid> [quiet]   (started by the line above)
  Exit code: 0 all PASS, 1 FAIL, 2 the window could not get the foreground.

  Build (same command line as the sibling KATs, from this folder):
  dcc32 -CC -Q -B -NS"System;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Xml;Web;Soap" \
  -I"..\..\..\Keyboard and Spell checker" \
  -U"..\..\..\Keyboard and Spell checker\Units;..\..\..\Keyboard and Spell checker\Classes;\
  ..\..\..\Keyboard and Spell checker\Forms;..\..\..\Keyboard and Spell checker\Layout;\
  ..\..\..\Keyboard and Spell checker\SpellChecker;..\..\..\Unicode to ascii converter;\
  %BDS%\lib\win32\release" kat_host.dpr
}

{$APPTYPE CONSOLE}

program kat_host;

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  Vcl.Clipbrd,
  Vcl.Graphics, // TBitmap: the non-text content the clipboard case puts there
  uRegistrySettings,
  uAnsiEngineManager,
  clsUnicodeToBijoy2000,
  clsAnsiAtomMap,
  uCaretContextSniffer,
  uCaretContextCache,
  uCaretWatch,
  uUIAText,
  uAnsiBackspace;

const
  { How many timer ticks a switch case gives the watch to produce a reading. The
    product's tick is 100 ms and uCaretWatch retries a request that came back
    empty up to WATCH_RETRY_LIMIT (5) times, so this is that bound: a real host
    that is still activating answers within it, and the case does not flake on a
    single declined read. }
  SWITCH_TICKS = 5;

  HOST_CLASS  = 'AvroKatHostWindow';
  HOST_TITLE  = 'kat_host - Avro host-layer self test (safe to close)';
  { A window of THIS process for the switch case. A CI desktop has no console
    window (and a mintty-launched run has none either), so the hand-off needs a
    real window that always exists - and it must not be the host window. }
  AWAY_CLASS  = 'AvroKatHostAwayWindow';
  EDIT_ID     = 101;
  MULTI_ID    = 102;
  RICH_ID     = 103;
  PASS_ID     = 104;

  { The child hands the focus to one of its own controls on request. Only this
    program ever sends it, and only to the copy it started: a foreign process
    cannot SetFocus a control it does not own, and the parent must be able to
    decide WHICH control the readers are pointed at. }
  WM_APP_FOCUS = WM_APP + 1;

  { How long the child is allowed to live without a parent ask: a parent that is
    killed outright must not leave a window behind forever. }
  SERVE_MAX_MS = 10 * 60 * 1000;

  { The text the message-path and the hook cases run against: short, so the
    character offsets are obvious, and long enough for a lookback wider than one
    character. }
  HOST_TEXT   = 'abcdef';

  { Proves that what came back is the CLIPBOARD and not the caret if a layer ever
    reported it: no control here ever holds this text. }
  CLIP_SENTINEL = 'kat_host sentinel';

  { How many characters the readers below ask for. Wider than the widest glyph
    any shipped mapping draws (four units) and narrower than the fixtures. }
  PROBE_CHARS = 8;

  { What the matrix puts in front of the cluster it measures: two characters the
    caret offset can be read off, so every row's evidence names the same place. }
  MATRIX_FILLER = 'ab';

  { The clusters the matrix measures, as Unicode: the two glyphs users report
    most (i and u), the two conjuncts (ka+hasanta+ka and the reph form
    ra+hasanta+ka), the ka+hasanta+ssa form and the two joiner spellings. The ANSI
    units for each one come from the ACTIVE mapping's own converter at run time,
    never from a literal here - a literal would only be true for one mapping. }
  MATRIX_CORPUS: array [0 .. 6] of string = (#$0987, #$0989, #$0995#$09CD#$0995, #$09B0#$09CD#$0995,
    #$0995#$09CD#$09B7, #$0995#$200D#$09CD#$09B7, #$0995#$200C#$09CD#$09B7);
  MATRIX_LABELS: array [0 .. 6] of string = ('i', 'u', 'kka', 'rka', 'kkha', 'ZWJ kkha', 'ZWNJ kkha');

type
  { The low-level keyboard hook structure (KBDLLHOOKSTRUCT). This Delphi's
    Winapi.Windows declares no such type, so - exactly like KeyboardHook.pas,
    which declares its own for the shipped hook - it is written out here. Field
    order and natural alignment are the Win32 ones; that is what makes vkCode
    land on the right field of the struct the hook is handed. }
  TKbdllHookStruct = record
    vkCode:      DWORD;
    scanCode:    DWORD;
    flags:       DWORD;
    time:        DWORD;
    dwExtraInfo: NativeUInt;
  end;
  PKbdllHookStruct = ^TKbdllHookStruct;

  { Captures an emission instead of injecting it: the last case checks the width
    the mapping's own table gives, against a real control full of that glyph. }
  TEraseSink = class
  public
    EraseCount: Integer;
    Text: string;
    Emits: Integer;
    procedure Emit(const AEraseCount: Integer; const AText: string);
  end;

var
  FHost:    HWND;   // in --serve: this copy's own window; otherwise the child's
  FEdit:    HWND;
  FMulti:   HWND;
  FRich:    HWND;
  FPass:    HWND;
  FRichCls: string;
  FHostTitle: string; // unique per run: the child's window is found by it
  FAway:     HWND;    // the "other application" the switch case hands the front to

  FChild:        THandle; // the started copy (--serve), and its thread handle
  FChildThread:  THandle;
  FChildPid:     DWORD;   // ... and the process the layers below must read
  FServe:        Boolean; // this copy IS the target
  FServeQuit:    Boolean;

  FKbHook:  HHOOK;
  FKeyDown: Integer;
  FKeyUp:   Integer;

  FSink:    TEraseSink;
  FQuiet:   Boolean;
  FMatrix:  Boolean; // --matrix: also record the host matrix
  FProbe:   Boolean; // --probe: describe the window in front and stop
  FChecks:  Integer;
  FFails:   Integer;
  FSkipped: Integer;

{ ============================================================================== }
{ reporting                                                                      }
{ ============================================================================== }

procedure Say(const AText: string);
begin
  if not FQuiet then
    WriteLn(AText);
end;

{ Where the diagnostic goes: the two processes that write it share one value,
  and it does NOT belong next to the executable - a KAT is built into whatever
  folder it is run from, and a log dropped there is noise in the repository. }
function LogPath: string;
begin
  Result := GetEnvironmentVariable('TEMP');
  if Result <> '' then
    Result := IncludeTrailingPathDelimiter(Result) + 'kat_host.child.log'
  else
    Result := ChangeFileExt(ParamStr(0), '.child.log');
end;

{ Appends one line to a file that TWO processes write: this one and the child
  that hosts the windows. AssignFile/Append takes the file exclusively, so the
  two writers collided (I/O error 32) the moment their lines overlapped - a
  handle opened with FILE_SHARE_READ or FILE_SHARE_WRITE does not. }
procedure AppendLine(const APath, ALine: string);
var
  H:       THandle;
  S:       AnsiString;
  Written: DWORD;
begin
  H := CreateFile(PChar(APath), GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetFilePointer(H, 0, nil, FILE_END);
    S := AnsiString(ALine + sLineBreak);
    WriteFile(H, S[1], Length(S), Written, nil);
  finally
    CloseHandle(H);
  end;
end;

{ "class[title] pid of <handle>": who holds the foreground is half the story
  when injected keys go missing, and a bare handle says nothing. }
function Described(const AWin: HWND): string;
var
  Buf:   array [0 .. 255] of Char;
  Title: array [0 .. 255] of Char;
  Cls:   string;
  Pid:   DWORD;
begin
  if AWin = 0 then
    Exit('none');
  Cls := '?';
  if GetClassName(AWin, Buf, Length(Buf)) > 0 then
    Cls := Buf;
  Title := '';
  GetWindowText(AWin, Title, Length(Title));
  Pid := 0;
  GetWindowThreadProcessId(AWin, @Pid);
  Result := Format('%s[%s] pid=%d', [Cls, Title, Pid]);
end;

{ The parent's half of the diagnostic file the child writes: the order in which
  the control received the injected keys and the order in which they were sent
  are two different things, and only the interleaving of the two shows it. }
{ The control the READING layers see: GetGUIThreadInfo(0) describes the ACTIVE
  window's thread, which is exactly the window the shipped application types
  into. }
function FocusedControl: HWND;
var
  GTI: TGUITHREADINFO;
begin
  Result := 0;
  FillChar(GTI, SizeOf(GTI), 0);
  GTI.cbSize := SizeOf(GTI);
  if GetGUIThreadInfo(0, GTI) then
  begin
    if GTI.hwndFocus <> 0 then
      Result := GTI.hwndFocus
    else
      Result := GTI.hwndCaret;
  end;
end;
procedure Mark(const AText: string);
begin
  { The modifier state of the machine is part of the record: a shift the desktop
    believes is held down changes what a plain key types and what a Shift+Left
    selects, which is exactly the sort of thing a reader of this log has to tell
    apart from the layer under test misbehaving. }
  AppendLine(LogPath, Format('  -- parent t=%d fg=%s focus=%x shift=%x caps=%x %s', [GetTickCount,
    Described(GetForegroundWindow), NativeUInt(FocusedControl), Word(GetAsyncKeyState(VK_SHIFT)),
    Word(GetAsyncKeyState(VK_CAPITAL)), AText]));
end;

procedure Check(const AWhat: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(FChecks);
  if ACond then
  begin
    Say('  ok   ' + AWhat);
    Exit;
  end;

  Inc(FFails);
  WriteLn('FAIL ' + AWhat);
  if ADetail <> '' then
    WriteLn('       ' + ADetail);
end;

procedure Skip(const AWhat: string);
begin
  Inc(FSkipped);
  WriteLn('SKIP ' + AWhat);
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

procedure TEraseSink.Emit(const AEraseCount: Integer; const AText: string);
begin
  EraseCount := AEraseCount;
  Text := AText;
  Inc(Emits);
end;

{ ============================================================================== }
{ the window, the controls and the messages                                      }

{ --- what the CHILD's own control receives (a diagnostic, and the only place
  the view from inside the target can be seen at all: the child has no console,
  so it writes lines to a file beside the executable) }
var
  FEditOldProc: Pointer;
  FKeyOrdinal:  Integer;

procedure ChildLog(const AText: string);
begin
  { The file is truncated ONCE, by Serve, before the parent's first line can be
    written into it: truncating on the first line here would race with the
    parent and could drop marks that had already been written. }
  AppendLine(LogPath, AText);
end;

{ Subclasses the control under test so the run can see whether the injected keys
  reach it at ALL and what the modifier state is when they do: a key that the
  layer injects and the control never receives, and a key it receives with the
  modifier unset, look identical from the outside. }
function ChildEditProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  if (Msg = WM_KEYDOWN) or (Msg = WM_KEYUP) or (Msg = WM_SYSKEYDOWN) or (Msg = WM_SYSKEYUP) or (Msg = WM_CHAR) then
  begin
    Inc(FKeyOrdinal);
    ChildLog(Format('[%d] t=%d edit msg=%x wparam=%x scan=%x ext=%d shift=%x ctrl=%x', [FKeyOrdinal, GetTickCount, Msg, wParam,
      (DWORD(lParam) shr 16) and $FF, Ord((DWORD(lParam) and $01000000) <> 0), Word(GetKeyState(VK_SHIFT)),
      Word(GetKeyState(VK_CONTROL))]));
  end;
  Result := CallWindowProc(FEditOldProc, hWnd, Msg, wParam, lParam);
end;

{ ============================================================================== }

function ControlById(const AId: Integer): HWND;
begin
  case AId of
    EDIT_ID:
      Result := FEdit;
    MULTI_ID:
      Result := FMulti;
    RICH_ID:
      Result := FRich;
    PASS_ID:
      Result := FPass;
  else
    Result := 0;
  end;
end;

{ Answers a focus request from the parent: names the control, focuses it - only
  this thread may - and reports whether it exists.

  A separate function because a window handle cannot be DECLARED in the window
  procedure that receives it: Delphi is case-insensitive, the parameter `hWnd`
  hides the `HWND` TYPE for everything inside that function, and `Target: HWND`
  there does not compile. }
function ServeFocusRequest(const AId: Integer): Boolean;
var
  Target: HWND;
begin
  Target := ControlById(AId);
  Result := Target <> 0;
  if Result then
    SetFocus(Target);
end;

function HostWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  { The parent's host window is subclassed too: a key that the child's EDIT
    never saw may still have been delivered to this window when the focus was
    not where the run believes it is, and the two cases need telling apart. }
  if (Msg = WM_KEYDOWN) or (Msg = WM_KEYUP) or (Msg = WM_CHAR) or (Msg = WM_SETFOCUS) or (Msg = WM_KILLFOCUS) then
    ChildLog(Format('HOST msg=%x wparam=%x', [Msg, wParam]));
  if Msg = WM_APP_FOCUS then
  begin
    { The parent asks for one of OUR controls to be the focused one. }
    Result := Ord(ServeFocusRequest(Integer(wParam)));
    Exit;
  end;
  if Msg = WM_CLOSE then
  begin
    DestroyWindow(hWnd);
    PostQuitMessage(0);
    Result := 0;
    Exit;
  end;
  if Msg = WM_DESTROY then
  begin
    FServeQuit := True;
    Result := 0;
    Exit;
  end;
  Result := DefWindowProc(hWnd, Msg, wParam, lParam);
end;

{ The RichEdit class lives in a DLL that must stay loaded for as long as one of
  its windows exists, so nothing here frees it. The shipped application edits its
  documents with the same family of classes, which is why the message path has to
  accept them - and why this program renders a second edit with one. }
function LoadRichEditClass: string;
begin
  Result := '';
  if LoadLibrary('msftedit.dll') <> 0 then
    Result := 'RICHEDIT50W' // RichEdit 4.1 (Vista and later)
  else if LoadLibrary('riched20.dll') <> 0 then
    Result := 'RichEdit20W';
end;

procedure CreateHost;
var
  Wc: TWndClass;
begin
  FillChar(Wc, SizeOf(Wc), 0);
  Wc.lpfnWndProc := @HostWndProc;
  Wc.hInstance := HInstance;
  Wc.hCursor := LoadCursor(0, IDC_IBEAM);
  Wc.hbrBackground := HBRUSH(COLOR_WINDOW + 1);
  Wc.lpszClassName := PChar(HOST_CLASS);
  { Qualified: System.Classes declares a RegisterClass of its own (the VCL form
    registration), and this file uses both. }
  if Winapi.Windows.RegisterClass(Wc) = 0 then
    raise Exception.Create('RegisterClass failed');

  FHost := CreateWindowEx(0, PChar(HOST_CLASS), PChar(FHostTitle), WS_OVERLAPPEDWINDOW or WS_VISIBLE, 160, 140, 620, 260, 0, 0,
    HInstance, nil);
  if FHost = 0 then
    raise Exception.Create('CreateWindowEx failed');

  FEdit := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '', WS_CHILD or WS_VISIBLE or ES_AUTOHSCROLL or WS_TABSTOP, 12, 12, 580, 26,
    FHost, EDIT_ID, HInstance, nil);
  FMulti := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '', WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL or WS_VSCROLL,
    12, 46, 580, 60, FHost, MULTI_ID, HInstance, nil);

  FRichCls := LoadRichEditClass;
  if FRichCls <> '' then
    FRich := CreateWindowEx(WS_EX_CLIENTEDGE, PChar(FRichCls), '', WS_CHILD or WS_VISIBLE or ES_MULTILINE or ES_AUTOVSCROLL,
      12, 114, 580, 60, FHost, RICH_ID, HInstance, nil);
  { ... and one that stays focused unless a request says otherwise. }
  SetFocus(FEdit);

  FPass := CreateWindowEx(WS_EX_CLIENTEDGE, 'EDIT', '', WS_CHILD or WS_VISIBLE or ES_PASSWORD or ES_AUTOHSCROLL, 12, 182, 580, 26,
    FHost, PASS_ID, HInstance, nil);

  if (FEdit = 0) or (FMulti = 0) or (FPass = 0) then
    raise Exception.Create('a control could not be created');

  ShowWindow(FHost, SW_SHOW);
  UpdateWindow(FHost);
end;

procedure DestroyHost;
begin
  if FHost <> 0 then
  begin
    DestroyWindow(FHost);
    FHost := 0;
  end;
  Winapi.Windows.UnregisterClass(PChar(HOST_CLASS), HInstance); // see CreateHost
end;

{ Pumps the queue for AMs milliseconds. Injected input, WinEvent callbacks and
  hook callbacks are all delivered through it, so everything that waits for them
  waits here - including the child-process helpers below, which must pump while
  the child starts up and answers. }
procedure Pump(const AMs: Cardinal);
var
  Msg: TMsg;
  T0:  Cardinal;
begin
  T0 := GetTickCount;
  repeat
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(1);
  until GetTickCount - T0 >= AMs;
end;

{ The title both copies agree on: the parent's process id makes this run's
  window findable even when another kat_host is on the desktop. }
function TitleFor(const AParentPid: Cardinal): string;
begin
  Result := Format('%s -- run %d', [HOST_TITLE, AParentPid]);
end;

{ Starts a second copy of THIS program, which creates the window and pumps its
  own queue while this one drives and reads it. That child process is what makes
  every layer below test the arrangement the shipped application actually runs
  in: UI Automation hands a client a Text pattern only for a control of ANOTHER
  process, and the watch's WinEvent hook skips its own process by design. }
procedure StartChild;
var
  Si:  TStartupInfo;
  Pi:  TProcessInformation;
  Cmd: string;
  T0:  Cardinal;
begin
  FillChar(Si, SizeOf(Si), 0);
  Si.cb := SizeOf(Si);
  FillChar(Pi, SizeOf(Pi), 0);

  { A WRITEABLE command line: CreateProcessW is allowed to modify the buffer it
    is handed, and a literal's is read-only. }
  Cmd := '"' + ParamStr(0) + '" --serve ' + IntToStr(GetCurrentProcessId());
  if not CreateProcess(nil, PChar(Cmd), nil, nil, False, 0, nil, nil, Si, Pi) then
    raise Exception.CreateFmt('the child process could not be started (%s)', [ParamStr(0)]);

  FChild := Pi.hProcess;
  FChildThread := Pi.hThread;
  FChildPid := GetProcessId(FChild);

  { The child's top-level window exists a moment before its controls do, so the
    lookup below is part of the wait: FindWindow can succeed while GetDlgItem
    still answers 0. }
  FHostTitle := TitleFor(GetCurrentProcessId());
  T0 := GetTickCount;
  repeat
    Pump(20);
    FHost := FindWindow(PChar(HOST_CLASS), PChar(FHostTitle));
    if FHost <> 0 then
    begin
      FEdit := GetDlgItem(FHost, EDIT_ID);
      FMulti := GetDlgItem(FHost, MULTI_ID);
      FRich := GetDlgItem(FHost, RICH_ID);
      FPass := GetDlgItem(FHost, PASS_ID);
    end;
  until ((FHost <> 0) and (FEdit <> 0) and (FMulti <> 0) and (FPass <> 0)) or (GetTickCount - T0 > 10000);

  if FHost = 0 then
    raise Exception.Create('the child created no window in time');
  if (FEdit = 0) or (FMulti = 0) or (FPass = 0) then
    raise Exception.Create('the child''s controls could not be found');
end;

procedure StopChild;
begin
  if FHost <> 0 then
  begin
    SendMessage(FHost, WM_CLOSE, 0, 0);
    if FChild <> 0 then
      WaitForSingleObject(FChild, 3000);
    FHost := 0;
    FEdit := 0;
    FMulti := 0;
    FRich := 0;
    FPass := 0;
  end;

  if FChild <> 0 then
  begin
    { A child that ignored WM_CLOSE (or was never found) must not linger. }
    TerminateProcess(FChild, 0);
    CloseHandle(FChild);
    FChild := 0;
    FChildPid := 0;
  end;

  if FChildThread <> 0 then
  begin
    CloseHandle(FChildThread);
    FChildThread := 0;
  end;

  if FAway <> 0 then
  begin
    DestroyWindow(FAway);
    FAway := 0;
  end;
end;

{ The child's whole job: own the window, answer the focus requests, and keep its
  own queue pumped - which is what lets the injected keys of the clipboard case
  and every cross-process message the readers send be processed at all. }
procedure Serve(const AParentPid: Cardinal);
var
  Msg: TMsg;
  T0:  Cardinal;
begin
  { NO CONSOLE: this copy exists only to host windows and to pump its queue, and
    a console attached to the process takes part in keyboard handling - the
    modifier keys of an injected Shift+Left / Ctrl+C never reached the control
    while one was attached (the harness's own by-hand probe is what showed it:
    the caret moved, the selection never grew, and Ctrl+A did nothing), which
    makes the most invasive reading layer untestable for reasons that have
    nothing to do with it. Nothing in this mode writes to the console. }
  FreeConsole;
  DeleteFile(LogPath);

  FHostTitle := TitleFor(AParentPid);
  CreateHost;

  FEditOldProc := Pointer(SetWindowLongPtr(FEdit, GWLP_WNDPROC, LONG_PTR(@ChildEditProc)));

  T0 := GetTickCount;
  while (not FServeQuit) and (GetTickCount - T0 < SERVE_MAX_MS) do
  begin
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      TranslateMessage(Msg);
      DispatchMessage(Msg);
    end;
    Sleep(1);
  end;

  DestroyHost;
end;



{ Takes the foreground for a window of ANOTHER process, which plain
  SetForegroundWindow refuses to do unless the caller happens to hold it already
  (the foreground lock): attaching to the input queue of whoever holds it now
  makes the call legal, and the queues are detached again immediately.

  A reading layer describes the FOREGROUND window, and the keys the clipboard
  layer injects go to it, so anything that steals the foreground mid-case - the
  terminal hosting this run does exactly that whenever it repaints - moves the
  whole arrangement out from under the case. }
function ForceForeground(const AWin: HWND): Boolean;
var
  Their: DWORD;
begin
  Their := GetWindowThreadProcessId(GetForegroundWindow, nil);
  if Their = GetCurrentThreadId then
    Their := 0;
  if Their <> 0 then
    AttachThreadInput(Their, GetCurrentThreadId, True);
  try
    BringWindowToTop(AWin);
    SetForegroundWindow(AWin);
  finally
    if Their <> 0 then
      AttachThreadInput(Their, GetCurrentThreadId, False);
  end;
  Result := GetForegroundWindow = AWin;
end;

{ Hands the foreground to the CHILD's window and asks the child to focus one of
  its own controls: a process cannot SetFocus a window it does not own, so the
  child answers a WM_APP_FOCUS request itself. That request is what points every
  reader below at the control under test. }
function TakeFocus(const ACtl: HWND; const AId: Integer): Boolean;
var
  T0: Cardinal;
begin
  ForceForeground(FHost);
  T0 := GetTickCount;
  repeat
    Pump(10);
    if GetForegroundWindow <> FHost then
      ForceForeground(FHost) // something else took it back
    else
      SendMessage(FHost, WM_APP_FOCUS, WPARAM(AId), 0);
    if (GetForegroundWindow = FHost) and (FocusedControl = ACtl) then
      Exit(True);
  until GetTickCount - T0 > 3000;
  Result := False;
end;

procedure SetText(const ACtl: HWND; const AText: string);
begin
  SendMessage(ACtl, WM_SETTEXT, 0, LPARAM(PChar(AText)));
end;

{ How long the control thinks its text is, without asking for the TEXT.

  This is the only way to measure a PASSWORD field from here: Windows answers
  WM_GETTEXTLENGTH for a password edit but deliberately hands out no characters
  to a caller from another process, so TextOf returns whatever was in the buffer
  (measured: the length is right and the text comes back empty). }
function TextLenOf(const ACtl: HWND): Integer;
var
  Res: LRESULT;
begin
  Res := 0;
  SendMessageTimeout(ACtl, WM_GETTEXTLENGTH, 0, 0, SMTO_ABORTIFHUNG, 250, @Res);
  Result := Integer(Res);
end;

function TextOf(const ACtl: HWND): string;
var
  Len: Integer;
  Res: LRESULT;
begin
  Result := '';
  SendMessageTimeout(ACtl, WM_GETTEXTLENGTH, 0, 0, SMTO_ABORTIFHUNG, 250, @Res);
  Len := Integer(Res);
  if Len <= 0 then
    Exit;
  SetLength(Result, Len);
  SendMessageTimeout(ACtl, WM_GETTEXT, Len + 1, LPARAM(@Result[1]), SMTO_ABORTIFHUNG, 250, @Res);
end;

procedure SetCaret(const ACtl: HWND; const APos: Integer);
begin
  SendMessage(ACtl, EM_SETSEL, APos, APos);
end;

procedure SetSelection(const ACtl: HWND; const AFrom, ATo: Integer);
begin
  SendMessage(ACtl, EM_SETSEL, AFrom, ATo);
end;

function SelectionStartOf(const ACtl: HWND): Integer;
var
  Res: LRESULT;
begin
  Res := SendMessage(ACtl, EM_GETSEL, 0, 0);
  Result := Integer(DWORD(Res) and $FFFF);
end;

function SelectionEndOf(const ACtl: HWND): Integer;
var
  Res: LRESULT;
begin
  Res := SendMessage(ACtl, EM_GETSEL, 0, 0);
  Result := Integer((DWORD(Res) shr 16) and $FFFF);
end;

function ClassOf(const ACtl: HWND): string;
var
  Buf: array [0 .. 127] of Char;
begin
  Result := '';
  if (ACtl <> 0) and (GetClassName(ACtl, Buf, Length(Buf)) > 0) then
    Result := Buf;
end;

{ ============================================================================== }
{ one real key press, and what a real hook does with it                          }
{ ============================================================================== }

{ Both return whether the injection was ACCEPTED (SendInput answers 0 when the
  desktop refuses it - a blocked injection and a modifier the target never
  applies look the same from the outside, and the diagnostic below has to tell
  them apart). }
function SendVk(const AVk: Word; const AUp: Boolean): Boolean;
var
  Inp: TInput;
begin
  FillChar(Inp, SizeOf(Inp), 0);
  Inp.Itype := INPUT_KEYBOARD;
  Inp.ki.wVk := AVk;
  Inp.ki.wScan := Word(MapVirtualKey(AVk, 0));
  if AUp then
    Inp.ki.dwFlags := KEYEVENTF_KEYUP;
  Result := SendInput(1, Inp, SizeOf(Inp)) = 1;
end;

{ The same key through SendInput, optionally with the SCAN code as well - the
  style a modifier is sometimes found to need (KEYEVENTF_SCANCODE, wVk = 0). }
function SendVkStyle(const AVk: Word; const AUp: Boolean; const AScancode: Boolean): Boolean;
var
  Inp: TInput;
begin
  if not AScancode then
  begin
    Result := SendVk(AVk, AUp);
    Exit;
  end;

  FillChar(Inp, SizeOf(Inp), 0);
  Inp.Itype := INPUT_KEYBOARD;
  Inp.ki.wScan := Word(MapVirtualKey(AVk, 0));
  Inp.ki.dwFlags := KEYEVENTF_SCANCODE;
  if AUp then
    Inp.ki.dwFlags := Inp.ki.dwFlags or KEYEVENTF_KEYUP;
  Result := SendInput(1, Inp, SizeOf(Inp)) = 1;
end;

procedure PressVk(const AVk: Word);
begin
  SendVk(AVk, False);
  SendVk(AVk, True);
end;

{ The SHIPPED keyboard hook's caret-context lines, verbatim: every key opens one
  burst, and the reading is dropped for every key except the one that needs it.
  The rest of `KeyboardHook` (hotkeys, layout processing, modifiers) has nothing
  to do with the caret context and is not reproduced here. }
function KbHookProc(nCode: Integer; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  Info: PKbdllhookstruct;
begin
  if nCode = HC_ACTION then
  begin
    Info := PKbdllhookstruct(lParam);
    if (wParam = WM_KEYDOWN) or (wParam = WM_SYSKEYDOWN) then
    begin
      Inc(FKeyDown);
      AnsiCaretBurstBegin;
      if Info.vkCode <> VK_BACK then
        AnsiCaretContextDrop('another key is about to change the text');
    end
    else if (wParam = WM_KEYUP) or (wParam = WM_SYSKEYUP) then
    begin
      Inc(FKeyUp);
      AnsiCaretContextDrop('the press was processed');
      AnsiCaretBurstEnd;
    end;
  end;

  Result := CallNextHookEx(FKbHook, nCode, wParam, lParam);
end;

{ ============================================================================== }
{ A. the message path                                                            }
{ ============================================================================== }

function GtiText: string;
var
  GTI: TGUITHREADINFO;
  Ok:  Boolean;
begin
  FillChar(GTI, SizeOf(GTI), 0);
  GTI.cbSize := SizeOf(GTI);
  Ok := GetGUIThreadInfo(0, GTI);
  Result := Format('GetGUIThreadInfo(0)=%s focus=%x caret=%x active=%x', [BoolToStr(Ok, True), NativeUInt(GTI.hwndFocus),
    NativeUInt(GTI.hwndCaret), NativeUInt(GTI.hwndActive)]);
end;

function TimedMsg(const ACtl: HWND; const AMsg: UINT; const AW: WPARAM; const AL: LPARAM; out AResult: LRESULT): LRESULT;
begin
  AResult := 0;
  Result := SendMessageTimeout(ACtl, AMsg, AW, AL, SMTO_ABORTIFHUNG, 250, @AResult);
end;

{ What the reading layers see, printed because everything below depends on the
  desktop and a diagnostic here is worth more than a guess. }
procedure SayHostState(const AName: string; const ACtl: HWND);
var
  Res:     LRESULT;
  TextLen: Integer;
  Buf:     string;
  RetVal:  LRESULT;
begin
  Say(Format('    %s: host=%x foreground=%x focused-control=%x | %s', [AName, NativeUInt(FHost),
    NativeUInt(GetForegroundWindow), NativeUInt(FocusedControl), GtiText]));
  Say(Format('    %s: the control itself is %x, class=%s', [AName, NativeUInt(ACtl), ClassOf(ACtl)]));

  RetVal := TimedMsg(ACtl, WM_GETTEXTLENGTH, 0, 0, Res);
  TextLen := Integer(Res);
  Say(Format('    %s: WM_GETTEXTLENGTH returned %d (text length %d)', [AName, RetVal, TextLen]));
  RetVal := TimedMsg(ACtl, EM_GETSEL, 0, 0, Res);
  Say(Format('    %s: EM_GETSEL returned %d (result $%.8x: %d..%d)', [AName, RetVal, Res, DWORD(Res) and $FFFF,
    (DWORD(Res) shr 16) and $FFFF]));
  SetLength(Buf, TextLen);
  RetVal := TimedMsg(ACtl, WM_GETTEXT, TextLen + 1, LPARAM(@Buf[1]), Res);
  Say(Format('    %s: WM_GETTEXT returned %d (result %d) -> [%s]', [AName, RetVal, Integer(Res), Buf]));
  Say(Format('    %s: window style is $%.8x (ES_PASSWORD is $%.4x)', [AName, GetWindowLong(ACtl, GWL_STYLE), ES_PASSWORD]));
end;

procedure MessagePathChecks(const AName: string; const ACtl: HWND; const AId: Integer);
var
  Text:    string;
  Reading: TSniffReading;
begin
  if not TakeFocus(ACtl, AId) then
  begin
    Skip(AName + ': the window could not take the foreground');
    Exit;
  end;

  SetText(ACtl, HOST_TEXT);
  SetCaret(ACtl, 6);
  { The FIRST control after the child was created was measured once answering no
    reading at all: the parent's messages had been queued but the child's message
    loop had not drained them yet, so its own probe read the text while the reader
    that followed saw an empty control. One pump removes that startup race - a
    check that fails on a cold start and passes on a rerun is worse than no
    check. }
  Pump(60);
  SayHostState(AName, ACtl);

  Reading.Window := 0;
  Check(Format('%s: the message path reads the characters before the caret', [AName]),
    SniffTextBeforeCaret(3, Text, Reading) and (Text = 'def'), Format('tail=[%s] want [def]', [Text]));
  Check(Format('%s: the reading says where it read', [AName]),
    (Reading.Window = NativeUInt(ACtl)) and (Reading.CaretIndex = 6) and (Reading.TextLength = 6),
    Format('window=%x want %x, caret=%d, length=%d', [Reading.Window, NativeUInt(ACtl), Reading.CaretIndex, Reading.TextLength]));

  SetCaret(ACtl, 4);
  Pump(30);
  Check(Format('%s: the characters read are the ones IMMEDIATELY before the caret', [AName]),
    SniffTextBeforeCaret(3, Text, Reading) and (Text = 'bcd'),
    Format('tail=[%s] want [bcd] (the first three characters of the text would be [abc])', [Text]));

  SetCaret(ACtl, 0);
  Check(Format('%s: a caret at the start of the document has nothing in front of it', [AName]),
    not SniffTextBeforeCaret(3, Text, Reading), Format('tail=[%s]', [Text]));

  SetSelection(ACtl, 2, 4);
  Check(Format('%s: an active selection is not read and not disturbed', [AName]),
    (not SniffTextBeforeCaret(3, Text, Reading)) and (SelectionStartOf(ACtl) = 2) and (SelectionEndOf(ACtl) = 4),
    Format('tail=[%s] selection=%d..%d want 2..4', [Text, SelectionStartOf(ACtl), SelectionEndOf(ACtl)]));

  SetText(ACtl, '');
  SetCaret(ACtl, 0);
  Check(Format('%s: an empty control has no reading', [AName]), not SniffTextBeforeCaret(3, Text, Reading),
    Format('tail=[%s]', [Text]));
end;

{ ============================================================================== }
{ B. UI Automation                                                               }
{ ============================================================================== }

procedure UiaChecks;
var
  Reader: TUiaTextReader;
  Text:   string;
  T0, T1: Cardinal;
  { NOT named Hwnd: a local called Hwnd would hide the HWND type (Delphi is
    case-insensitive), and the declaration of the variable itself would then
    fail to resolve its own type. }
  Focused: HWND;
  Pid:     DWORD;
begin
  Reader := TUiaTextReader.Create;
  try
    if not TakeFocus(FEdit, EDIT_ID) then
    begin
      Skip('UI Automation: the window could not take the foreground');
      Exit;
    end;

    SetText(FEdit, HOST_TEXT);
    SetCaret(FEdit, 6);
    T0 := GetTickCount;
    Text := Reader.ReadBeforeCaret(3);
    T1 := GetTickCount;

    Check('UIA: the reader starts up and reads the control in front of the caret', Text = 'def',
      Format('tail=[%s] want [def]; Available=%s LastError=[%s] %s', [Text, BoolToStr(Reader.Available, True), Reader.LastError,
        Reader.ElementInfo]));

    { WHICH control answered: the class, the handle and the control type of the
      element the reading came from, and what its two Text-pattern queries said.
      This is what makes a passing run mean something - an element belonging to
      the wrong window would read the right text by accident. }
    Say('    note: the element that answered: ' + Reader.ElementInfo);

    { The element of the focused control is the expensive part of a read and is
      kept: a read a moment later must be served without fetching it again. }
    Sleep(120); // past the probe interval, well inside the element's lifetime
    Text := Reader.ReadBeforeCaret(3);
    Check('UIA: the element of the focused control is reused for the next read',
      (Text = 'def') and (Reader.ElementHits > 0),
      Format('tail=[%s] ElementHits=%d Probes=%d element cached=%s', [Text, Reader.ElementHits, Reader.Probes,
        BoolToStr(Reader.HasElement, True)]));

    { The TEXT is not cached, only the element: the same element answers for the
      caret wherever it now is. }
    SetCaret(FEdit, 3);
    Sleep(120);
    Text := Reader.ReadBeforeCaret(3);
    Check('UIA: the cached element still describes the caret, not the old text', Text = 'abc',
      Format('tail=[%s] want [abc]', [Text]));

    { The probe budget declines a read that comes too fast behind another. }
    if (T1 - T0) < 45 then
    begin
      Text := Reader.ReadBeforeCaret(3);
      Text := Reader.ReadBeforeCaret(3);
      Check('UIA: a probe inside the interval is declined, not queued', (Text = '') and (Reader.Throttled > 0),
        Format('tail=[%s] Throttled=%d', [Text, Reader.Throttled]));
    end
    else
      Say(Format('    note: the first read took %d ms, so the probe interval was already open', [T1 - T0]));

    { A password field is never read - and staying away from it must not silence
      the rest of the same process: the quiet period is keyed by the control. }
    if TakeFocus(FPass, PASS_ID) then
    begin
      SetText(FPass, 'hunter2');
      SetCaret(FPass, 7);
      Sleep(120);
      Text := Reader.ReadBeforeCaret(3);
      Check('UIA: a password field is never read', Text = '',
        Format('tail=[%s] want [] (LastError=[%s])', [Text, Reader.LastError]));

      if TakeFocus(FEdit, EDIT_ID) then
      begin
        SetText(FEdit, HOST_TEXT);
        SetCaret(FEdit, 6);
        Sleep(120);
        Text := Reader.ReadBeforeCaret(3);
        Check('UIA: the quiet period belongs to the control that answered nothing', Text = 'def',
          Format('tail=[%s] want [def]; QuietSkips=%d', [Text, Reader.QuietSkips]));
      end
      else
        Skip('UIA: the edit could not take the foreground back');
    end
    else
      Skip('UIA: the password control could not take the foreground');

    { The RichEdit family is what the message path also accepts, so the SAME
      control has to be readable by both layers. }
    if FRich = 0 then
      Skip('UI Automation: no rich edit class on this machine')
    else if not TakeFocus(FRich, RICH_ID) then
      Skip('UI Automation: the rich edit could not take the foreground')
    else
    begin
      SetText(FRich, HOST_TEXT);
      SetCaret(FRich, 6);
      Sleep(120);
      Text := Reader.ReadBeforeCaret(3);
      Check(Format('UIA: the rich edit (%s) is read through UI Automation', [FRichCls]), Text = 'def',
        Format('tail=[%s] want [def] (LastError=[%s] %s)', [Text, Reader.LastError, Reader.ElementInfo]));
    end;

    Focused := FocusedControl;
    Pid := 0;
    if Focused <> 0 then
      GetWindowThreadProcessId(Focused, Pid);
    Check('UIA: the element read belongs to the CHILD process, not to this one',
      (Pid = FChildPid) and (Pid <> GetCurrentProcessId()) and
      ((Focused = FEdit) or (Focused = FMulti) or (Focused = FRich) or (Focused = FPass)),
      Format('focused=%x pid=%d (the child: %d, this process: %d; controls %x/%x/%x/%x)', [NativeUInt(Focused), Pid, FChildPid,
      GetCurrentProcessId(), NativeUInt(FEdit), NativeUInt(FMulti), NativeUInt(FRich), NativeUInt(FPass)]));
  finally
    { Released on the thread that opened its apartment - the main thread here,
      which is also the thread the application's timer reads from. }
    Reader.Reset;
    Reader.Free;
  end;
end;

{ ============================================================================== }
{ C. the clipboard round-trip                                                    }
{ ============================================================================== }

{ The clipboard belongs to the whole DESKTOP: another application can hold it
  open for a moment, in which case even reading it raises. A fixture that cannot
  take the clipboard is skipped rather than failed - the layer under test is what
  is being judged, and it refuses cleanly when it cannot open the clipboard
  itself. }
function TrySetClip(const AText: string): Boolean;
var
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to 5 do
  begin
    try
      Clipboard.AsText := AText;
      Exit(True);
    except
      on E: Exception do
        Sleep(20); // somebody else holds it open - wait and ask again
    end;
  end;
end;

{ The same, for content that is NOT text: what a screenshot or a copied file puts
  on the clipboard, and exactly what a "restore" that can only write text would
  destroy. }
function TrySetClipBitmap(const ABitmap: TBitmap): Boolean;
var
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to 5 do
  begin
    try
      Clipboard.Assign(ABitmap);
      Exit(True);
    except
      on E: Exception do
        Sleep(20);
    end;
  end;
end;

{ How many key lines the CHILD has written so far. The child subclasses its
  control and logs every key it receives, so this count is the harness's only
  view from inside the target process - and the only honest way to assert that
  something DID NOT PRESS A KEY. }
function ChildKeyLines: Integer;
var
  Lines: TStringList;
  I:     Integer;
begin
  Result := 0;
  Lines := TStringList.Create;
  try
    if not FileExists(LogPath) then
      Exit;
    try
      Lines.LoadFromFile(LogPath);
    except
      Exit; // a writer holds it momentarily: report no lines rather than raise
    end;
    for I := 0 to Lines.Count - 1 do
      if (Lines[I] <> '') and (Lines[I][1] = '[') then
        Inc(Result);
  finally
    Lines.Free;
  end;
end;

function ClipAsText(out AText: string): Boolean;
begin
  AText := '';
  try
    AText := Clipboard.AsText;
    Result := True;
  except
    on E: Exception do
      Result := False;
  end;
end;

{ Focus is already where the cases expect it (see TakeFocus), and the target is
  the CHILD process: the keys injected here go to the child's focused control and
  the child processes them in its own message loop, which is exactly what the
  shipped application relies on. Nothing in this copy has to pump for it. }
{ The round-trip itself: needs the injected keys to take effect on this desktop
  (that is what SelectionMechanismWorks is asked first). }
procedure ClipboardJobOnEdit;
var
  Text:    string;
  OnClip:  string;
  ClipOk:  Boolean;
begin
  SetText(FEdit, HOST_TEXT);
  SetCaret(FEdit, 6);
  if not TrySetClip(CLIP_SENTINEL) then
  begin
    Skip('clipboard: another application holds the clipboard; the round-trip was not exercised');
    Exit;
  end;

  Check('clipboard: the layer reports the characters before the caret',
    SniffTextViaClipboard(3, Text) and (Text = 'def'), Format('tail=[%s] want [def]', [Text]));
  Check('clipboard: the caret is exactly where it was', (SelectionStartOf(FEdit) = 6) and (SelectionEndOf(FEdit) = 6),
    Format('caret=%d..%d want 6..6', [SelectionStartOf(FEdit), SelectionEndOf(FEdit)]));
  ClipOk := ClipAsText(OnClip);
  Check('clipboard: the previous clipboard content is put back', ClipOk and (OnClip = CLIP_SENTINEL),
    Format('clipboard=[%s] want [%s]', [OnClip, CLIP_SENTINEL]));
end;

{ The one side effect the layer must never have, whatever the desktop does.

  Every key it injects is only meaningful together with its modifier, and an
  unmodified one is a real edit: a bare Left moves the caret and a bare 'c' types
  a letter into the document. The layer therefore confirms each modifier against
  the DESKTOP before pressing the key that needs it, and this case holds it to
  that: after a read, the text and the caret are exactly where they were.

  It does not care whether the keys WORK - on the desktop this was written on
  they do not, which is exactly when the guard has to hold - so it always runs. }
procedure ClipboardJobNoSideEffects;
var
  Before: string;
  Text:   string;
begin
  SetText(FEdit, HOST_TEXT);
  SetCaret(FEdit, 6);
  Pump(60);
  Before := TextOf(FEdit);

  SniffTextViaClipboard(3, Text); // what it reads is not what this case judges

  Check('clipboard: a read leaves the document and the caret untouched',
    (TextOf(FEdit) = Before) and (Before = HOST_TEXT) and (SelectionStartOf(FEdit) = 6) and (SelectionEndOf(FEdit) = 6),
    Format('text=[%s] want [%s]; caret=%d..%d want 6..6; reading=[%s]', [TextOf(FEdit), HOST_TEXT, SelectionStartOf(FEdit),
      SelectionEndOf(FEdit), Text]));
end;

{ The refusals. None of them needs the injected keys to take effect: an active
  selection is refused before anything is pressed, and an unchanged clipboard is
  what a copy with nothing to copy leaves behind. }
procedure ClipboardJobRefusals;
var
  Text:   string;
  T0:     Cardinal;
begin
  { An active selection belongs to the user: the round-trip would collapse it. }
  SetText(FEdit, HOST_TEXT);
  SetSelection(FEdit, 2, 4);
  Check('clipboard: an active selection is refused, not collapsed',
    (not SniffTextViaClipboard(3, Text)) and (SelectionStartOf(FEdit) = 2) and (SelectionEndOf(FEdit) = 4),
    Format('reading=[%s] selection=%d..%d want 2..4', [Text, SelectionStartOf(FEdit), SelectionEndOf(FEdit)]));

  { Nothing to the left: the copy produces nothing and the clipboard still holds
    the sentinel. Its characters are not a reading of the caret, so the layer
    must refuse instead of reporting the CLIPBOARD. }
  SetCaret(FEdit, 0);
  TrySetClip(CLIP_SENTINEL);
  T0 := GetTickCount;
  Check('clipboard: an unchanged clipboard is not mistaken for a reading', not SniffTextViaClipboard(3, Text),
    Format('reading=[%s] after %d ms, with the sentinel still on the clipboard', [Text, GetTickCount - T0]));
  Check('clipboard: the caret is still where it was after that refusal', SelectionStartOf(FEdit) = 0,
    Format('caret=%d want 0', [SelectionStartOf(FEdit)]));
end;

{ A clipboard that holds something this layer cannot put back.

  A screenshot (Win+Shift+S) or a file list from Explorer has NO text format at
  all, and TClipboard.SetAsText empties the clipboard before writing one - so the
  "restore" would destroy it, silently: Clipboard.AsText answers '' for a bitmap
  WITHOUT raising, so no caller could even tell. The layer therefore has to look
  at the FORMATS and refuse before pressing or reading anything. Runs on any
  desktop: the refusal is the whole point, and a half-executed round-trip is most
  likely exactly where injected keys do not work. }
procedure ClipboardJobNonText;
var
  Bmp:    TBitmap;
  Text:   string;
  Before: string;
  Keys:   Integer;
begin
  SetText(FEdit, HOST_TEXT);
  SetCaret(FEdit, 6);
  Pump(60);
  Before := TextOf(FEdit);

  Bmp := TBitmap.Create;
  try
    Bmp.Width := 1;
    Bmp.Height := 1;
    Bmp.Canvas.Pixels[0, 0] := clRed;
    if not TrySetClipBitmap(Bmp) then
    begin
      Skip('clipboard: the clipboard could not be given a bitmap (another application holds it)');
      Exit;
    end;

    Keys := ChildKeyLines;
    Check('clipboard: a non-text clipboard is refused', not SniffTextViaClipboard(3, Text),
      Format('reading=[%s]', [Text]));
    Check('clipboard: the refusal left the document and the caret alone',
      (TextOf(FEdit) = Before) and (SelectionStartOf(FEdit) = 6) and (SelectionEndOf(FEdit) = 6),
      Format('text=[%s] want [%s]; caret=%d..%d want 6..6', [TextOf(FEdit), Before, SelectionStartOf(FEdit), SelectionEndOf(FEdit)]));
    Check('clipboard: the refusal pressed no key at all', ChildKeyLines = Keys,
      Format('the control received %d key messages during the refusal', [ChildKeyLines - Keys]));
    Check('clipboard: the non-text content is still on the clipboard', Clipboard.HasFormat(CF_BITMAP),
      'CF_BITMAP is gone: the refusal did not come before the restore');
  finally
    Bmp.Free;
  end;

  TrySetClip(CLIP_SENTINEL); // leave the clipboard as the cases after this one expect
end;

{ The quarantine: what happens when a modifier cannot be released.

  A desktop cannot be asked to hold a Shift down on demand, so the state is
  declared through the unit's own test hook - the same shape
  AnsiBackspaceConfigureForTest already uses in uAnsiBackspace. What the case
  judges is the CONTRACT: while the latch is set and the desktop reports Shift
  held, nothing at all happens; and the latch clears ITSELF as soon as the
  keyboard is clean, so a one-off glitch does not disable the layer for the
  session (which it would if the sniffer were switched off instead). }
procedure ClipboardJobQuarantine;
var
  Text:   string;
  Before: string;
  Keys:   Integer;
begin
  SetText(FEdit, HOST_TEXT);
  SetCaret(FEdit, 6);
  TrySetClip(CLIP_SENTINEL);
  Pump(60);
  Before := TextOf(FEdit);

  AnsiClipboardConfigureForTest(True, True);
  try
    Keys := ChildKeyLines;
    Check('clipboard: while quarantined and Shift is held, an attempt refuses', not SniffTextViaClipboard(3, Text),
      Format('reading=[%s]', [Text]));
    Check('clipboard: the quarantine pressed nothing and moved nothing',
      (ChildKeyLines = Keys) and (TextOf(FEdit) = Before) and (SelectionStartOf(FEdit) = 6) and (SelectionEndOf(FEdit) = 6),
      Format('keys=%d (was %d) text=[%s] caret=%d..%d want 6..6', [ChildKeyLines, Keys, TextOf(FEdit), SelectionStartOf(FEdit),
        SelectionEndOf(FEdit)]));
    Check('clipboard: the quarantine is still in force', AnsiClipboardQuarantined, 'the latch cleared while Shift was held');

    { A clean keyboard lifts it by itself, and the layer is usable again. }
    AnsiClipboardConfigureForTest(True, False);
    SniffTextViaClipboard(3, Text);
    Check('clipboard: a clean keyboard clears the quarantine by itself', not AnsiClipboardQuarantined,
      'the latch survived a clean keyboard');
  finally
    AnsiClipboardConfigureForTest(False, False);
  end;
end;

{ A password field refuses to copy, so the same guard has to answer for it. }
procedure ClipboardJobOnPassword;
var
  Text:   string;
  OnClip: string;
begin
  SetText(FPass, 'hunter2');
  SetCaret(FPass, 7);
  if not TrySetClip(CLIP_SENTINEL) then
  begin
    Skip('clipboard: another application holds the clipboard; the password refusal was not exercised');
    Exit;
  end;

  Check('clipboard: a password field is never read', not SniffTextViaClipboard(3, Text), Format('reading=[%s]', [Text]));
  Check('clipboard: the sentinel is left alone by the refusal', ClipAsText(OnClip) and (OnClip = CLIP_SENTINEL),
    Format('clipboard=[%s] want [%s]', [OnClip, CLIP_SENTINEL]));
end;

{ The keys the clipboard layer injects, driven by hand: a plain key must TYPE
  into the control (the simplest proof that injected input arrives at all), and
  Shift+Left must select exactly one character, and ONE Right must collapse it
  again - the contract the layer's round-trip is built out of.

  This is a precondition of the cases below, not a result. Injected keys go to
  the FOREGROUND window and are open to the whole desktop, so the check records
  the step that did not hold and the window that held the foreground instead; an
  attempt broken that way is retried, never counted. THE most common outcome on
  a busy desktop is not a broken layer but a reshaped key: some input layer (an
  IME, a remapper, this project's own running build) turns the injected Shift
  down into a down/up pair, so the Left key arrives while the desktop believes
  Shift is released - measurable, named here, and NOT the layer's fault. The run
  says which of those it saw and skips the layer's cases. }
function SelectionMechanismWorks(const ACtl: HWND; const AId: Integer; out AWhy: string): Boolean;
const
  MECH_ATTEMPTS = 4;
var
  I:     Integer;
  Typed: Boolean;

  function Refocus: Boolean;
  begin
    ForceForeground(FHost);
    SendMessage(FHost, WM_APP_FOCUS, WPARAM(AId), 0);
    Pump(10);
    Result := (GetForegroundWindow = FHost) and (FocusedControl = ACtl);
    if not Result then
      AWhy := Format('the target could not keep the foreground (it is %s)', [Described(GetForegroundWindow)]);
  end;

  { True only when the target kept the foreground for the whole attempt. }
  function Held: Boolean;
  begin
    Result := GetForegroundWindow = FHost;
    if not Result then
      AWhy := Format('another window took the foreground mid-sequence (it is %s)', [Described(GetForegroundWindow)]);
  end;

  function Attempt: Boolean;
  begin
    Result := False;

    SetText(ACtl, '');
    SetCaret(ACtl, 0);
    if not Refocus then
      Exit;
    Mark('attempt: plain key');
    PressVk(Ord('B'));
    Pump(60);
    if not Held then
      Exit;
    Typed := SameText(TextOf(ACtl), 'b');
    if not Typed then
    begin
      AWhy := 'a plain injected key never reached the control';
      Exit;
    end;

    SetText(ACtl, HOST_TEXT);
    SetCaret(ACtl, 6);
    Pump(20);
    if not Refocus then
      Exit;
    Mark('attempt: shift down');
    SendVk(VK_SHIFT, False);
    Pump(20);
    Mark('attempt: shift+left');
    PressVk(VK_LEFT);
    Pump(20);
    Mark('attempt: shift up');
    SendVk(VK_SHIFT, True);
    Pump(60);
    if not Held then
      Exit;
    if (SelectionStartOf(ACtl) <> 5) or (SelectionEndOf(ACtl) <> 6) then
    begin
      AWhy := Format('Shift+Left left the selection at %d..%d instead of 5..6, so the injected Shift did not take ' +
        'effect while the Left key did (a desktop that reshapes an injected modifier does this)', [SelectionStartOf(ACtl),
        SelectionEndOf(ACtl)]);
      Exit;
    end;

    { ... and the collapse the layer ends every round-trip with: with the shift
      released, ONE Right must leave no selection at the caret it started from. }
    Mark('attempt: right');
    PressVk(VK_RIGHT);
    Pump(60);
    if not Held then
      Exit;
    if (SelectionStartOf(ACtl) <> 6) or (SelectionEndOf(ACtl) <> 6) then
    begin
      AWhy := Format('the collapse after Shift+Left left %d..%d instead of 6..6', [SelectionStartOf(ACtl), SelectionEndOf(ACtl)]);
      Exit;
    end;

    Result := True;
  end;

begin
  Result := False;
  Typed := False;
  AWhy := 'the mechanism was not exercised';
  for I := 1 to MECH_ATTEMPTS do
    if Attempt then
    begin
      Result := True;
      Break;
    end;

  { Whatever the answer, the caret is left in the place every case below starts
    from. }
  SetText(ACtl, HOST_TEXT);
  SetCaret(ACtl, 6);
  Pump(40);

  if Result then
    Say(Format('    note: the keys take effect (a plain key typed=%s; Shift+Left selects one character and Right collapses it)', [BoolToStr(Typed, True)]))
  else
    Say(Format('    note: no pair of keys took effect in %d attempts: %s%s', [MECH_ATTEMPTS, AWhy, '  (what the control received, and who held the foreground, is in ' + LogPath + ')']));
end;

{ A job that raises is reported as a failure instead of taking the rest of the
  run down: a clipboard another application holds open is a harness problem, and
  the sections after this one still have something to prove. }
procedure RunJob(const AWhat: string; const AJob: TProc);
begin
  try
    AJob;
  except
    on E: Exception do
    begin
      Check(AWhat + ': the case raised ' + E.ClassName, False, E.Message);
    end;
  end;
end;

procedure ClipboardChecks;
var
  Why: string;
begin
  if not TakeFocus(FEdit, EDIT_ID) then
  begin
    Skip('clipboard: the window could not take the foreground');
    Exit;
  end;

  { These two do not need the injected keys to take effect - one is about what
    happens when they do NOT - so they run on any desktop. }
  RunJob('clipboard: an attempted read', ClipboardJobNoSideEffects);
  RunJob('clipboard: the refusals', ClipboardJobRefusals);
  RunJob('clipboard: a non-text clipboard', ClipboardJobNonText);
  RunJob('clipboard: the quarantine', ClipboardJobQuarantine);

  { The round-trip reading itself does need them. }
  if not SelectionMechanismWorks(FEdit, EDIT_ID, Why) then
  begin
    Skip('clipboard: this desktop does not deliver the keys the layer injects, so the round-trip cases cannot judge it');
    Say('       ' + Why);
  end
  else
    RunJob('clipboard: the round-trip', ClipboardJobOnEdit);

  { The password control is the one refusal that needs its own window focused. }
  if not TakeFocus(FPass, PASS_ID) then
    Skip('clipboard: the password control could not take the foreground')
  else
    RunJob('clipboard: the password refusal', ClipboardJobOnPassword);
end;

{ ============================================================================== }
{ C2. the surgical erase: one edit instead of N backspaces                        }
{ ============================================================================== }

{ What a reading of THIS control looks like: the case has to hold a FRESH one, or
  the erase would be refused for the wrong reason and prove nothing. }
procedure ReadHere(const AWhat: string);
begin
  AnsiCaretWatchNoteCaretEvent('harness: ' + AWhat);
  AnsiCaretWatchTick;
end;

{ One control, three units, one edit.

  The three cases differ only in the control: a standard single-line EDIT, a
  multi-line EDIT and a RICHEDIT - the classes that answer EM_GETSEL / EM_SETSEL /
  WM_CLEAR. Each asserts the TEXT and the CARET, not just the return value, and
  then that the control received no key message at all: the whole point of the
  surgical route is that nothing is injected. }
procedure SurgicalControlJob(const AName: string; const ACtl: HWND; const AId: Integer);
var
  Remaining: Integer;
  Reason:    string;
  Keys:      Integer;
begin
  if not TakeFocus(ACtl, AId) then
  begin
    Skip('surgical: ' + AName + ' could not take the foreground');
    Exit;
  end;

  SetText(ACtl, HOST_TEXT);
  SetCaret(ACtl, 6);
  Pump(60);
  ReadHere('the surgical case starts with a fresh reading');
  Keys := ChildKeyLines;

  Check(Format('surgical: %s: one edit erases the cluster', [AName]),
    AnsiSurgicalHostErase(3, Remaining, Reason) and (Remaining = 0),
    Format('remaining=%d (%s)', [Remaining, Reason]));
  Check(Format('surgical: %s: exactly the three characters are gone', [AName]), TextOf(ACtl) = 'abc',
    Format('text=[%s] want [abc]', [TextOf(ACtl)]));
  Check(Format('surgical: %s: the caret sits where the cluster started', [AName]),
    (SelectionStartOf(ACtl) = 3) and (SelectionEndOf(ACtl) = 3),
    Format('caret=%d..%d want 3..3', [SelectionStartOf(ACtl), SelectionEndOf(ACtl)]));
  Check(Format('surgical: %s: not one key was injected', [AName]), ChildKeyLines = Keys,
    Format('the control received %d key messages', [ChildKeyLines - Keys]));
end;

{ The refusals. Each one is asserted by the REASON it gives, so a case cannot
  pass for the wrong guard: `selection` is the user's own selection, `stand
  before` is a cluster longer than the text in front of the caret, and the last
  one is the window the reading describes. }
procedure SurgicalRefusalChecks;
var
  Remaining: Integer;
  Reason:    string;
  Text:      string;
  Keys:      Integer;
  LenBefore: Integer;
begin
  { A selection the user made is never the surgery's target. The reading is
    taken FIRST (the message path refuses to read over a selection, so the
    fingerprint must exist before the selection does) and then the user's
    selection is created. }
  if TakeFocus(FEdit, EDIT_ID) then
  begin
    SetText(FEdit, HOST_TEXT);
    SetCaret(FEdit, 6);
    Pump(60);
    ReadHere('the refusal cases start with a fresh reading');
    SetSelection(FEdit, 2, 4);
    Text := TextOf(FEdit);
    Keys := ChildKeyLines;

    Check('surgical: an active selection is refused, by name', (not AnsiSurgicalHostErase(3, Remaining, Reason)) and
      (Remaining = 3) and (Pos('selection', Reason) > 0), Format('remaining=%d reason=[%s] want the selection refusal', [Remaining, Reason]));
    Check('surgical: ... and the selection is left exactly where it was',
      (TextOf(FEdit) = Text) and (SelectionStartOf(FEdit) = 2) and (SelectionEndOf(FEdit) = 4) and (ChildKeyLines = Keys),
      Format('text=[%s] selection=%d..%d keys=%d', [TextOf(FEdit), SelectionStartOf(FEdit), SelectionEndOf(FEdit),
      ChildKeyLines - Keys]));

    { Wider than the text in front of the caret: the cap above the text length. }
    SetCaret(FEdit, 2);
    Pump(40);
    Check('surgical: a cluster longer than the text before the caret is refused',
      (not AnsiSurgicalHostErase(5, Remaining, Reason)) and (Remaining = 5) and (Pos('stand before', Reason) > 0),
      Format('remaining=%d reason=[%s] want the length refusal', [Remaining, Reason]));
    Check('surgical: ... and the text is untouched by that refusal', TextOf(FEdit) = Text,
      Format('text=[%s] want [%s]', [TextOf(FEdit), Text]));
  end
  else
    Skip('surgical: the edit control could not take the foreground');

  { A password field has no reading at all, so the surgery has nothing that
    describes it - and it refuses windows the reading does not describe before it
    looks at anything else. Stated that way rather than as "the password check
    fired": with this guard in place the password branch is unreachable while the
    fingerprint is honest, which is defence in depth, not a gap. }
  if not TakeFocus(FPass, PASS_ID) then
    Skip('surgical: the password control could not take the foreground')
  else
  begin
    SetText(FPass, 'hunter2');
    SetCaret(FPass, 7);
    Pump(40);
    LenBefore := TextLenOf(FPass);
    Keys := ChildKeyLines;
    Check('surgical: a window the reading does not describe is never edited',
      (not AnsiSurgicalHostErase(3, Remaining, Reason)) and (Remaining = 3) and (Pos('does not describe', Reason) > 0),
      Format('remaining=%d reason=[%s]', [Remaining, Reason]));
    { The field's TEXT cannot be read from this process at all (see TextLenOf) -
      which is the very protection the password branch of every reader leans on -
      so the assertion here is the length, the caret and the absence of keys. }
    Check('surgical: ... and the password field is untouched',
      (LenBefore = 7) and (TextLenOf(FPass) = LenBefore) and (SelectionStartOf(FPass) = 7) and (ChildKeyLines = Keys),
      Format('length %d -> %d, caret=%d keys=%d', [LenBefore, TextLenOf(FPass), SelectionStartOf(FPass),
      ChildKeyLines - Keys]));
  end;
end;

procedure SurgicalJobEdit;
begin
  SurgicalControlJob('edit', FEdit, EDIT_ID);
end;

procedure SurgicalJobMulti;
begin
  SurgicalControlJob('multi-line edit', FMulti, MULTI_ID);
end;

procedure SurgicalJobRich;
begin
  SurgicalControlJob(Format('rich edit (%s)', [FRichCls]), FRich, RICH_ID);
end;

procedure SurgicalChecks;
begin
  if not TakeFocus(FEdit, EDIT_ID) then
  begin
    Skip('surgical: the window could not take the foreground');
    Exit;
  end;

  { The head-less watch: the real provider chain and the real fingerprint, no OS
    hooks - the reading is what the surgery is verified against, and the cases
    must not depend on the desktop's event delivery. }
  AnsiBackspaceSurgical := 'AUTO';
  AnsiBackspaceUIA := 'NO';
  AnsiBackspaceClipboard := 'NO';
  AnsiCaretWatchStartHeadless;
  try
    RunJob('surgical: a standard edit', SurgicalJobEdit);
    RunJob('surgical: a multi-line edit', SurgicalJobMulti);

    if FRich = 0 then
      Skip('surgical: no rich edit class on this machine')
    else
      RunJob('surgical: a rich edit', SurgicalJobRich);

    RunJob('surgical: the refusals', SurgicalRefusalChecks);
  finally
    AnsiCaretWatchStop;
    AnsiBackspaceSurgical := 'AUTO';
    AnsiBackspaceUIA := 'YES';
  end;
end;

{ ============================================================================== }
{ D. the watch, a real key press and one emission                                }
{ ============================================================================== }

{ The widest single cluster the ACTIVE mapping draws, taken from its own table:
  the character one press has to erase whole. }
function WidestCluster: string;
var
  Atoms: TArray<TAnsiAtom>;
  I:     Integer;
begin
  Result := '';
  if AnsiAtomMap = nil then
    Exit;
  Atoms := AnsiAtomMap.Atoms;
  for I := 0 to high(Atoms) do
    if (Atoms[I].Bind = abSelf) and (Length(Atoms[I].Units) > Length(Result)) then
      Result := Atoms[I].Units;
end;

procedure HookChecks;
var
  Text:     string;
  Wide:     string;
  Tail:     string;
  Events:     Integer;
  Refs:       Integer;
  RefsBase:   Integer;
  KeyLines:   Integer;
  KeysBefore: Integer;
  Base:       Integer;
  T0:         Cardinal;
  Watched:    Boolean;
begin
  if not TakeFocus(FEdit, EDIT_ID) then
  begin
    Skip('hooks: the window could not take the foreground');
    Exit;
  end;

  { The application's OWN watch: the same WinEvent and mouse hooks it installs,
    with the real provider chain behind them (message path first, then UI
    Automation, then the clipboard - the last one off by default). }
  AnsiBackspaceUIA := 'YES';
  AnsiBackspaceClipboard := 'NO';
  AnsiCaretWatchStart;
  Check('hooks: the watch installs its hooks', AnsiCaretWatchActive, 'AnsiCaretWatchActive = False');
  Check('hooks: its WinEvent hook is process wide', AnsiCaretWatchWindow = 0, 'the watch reports a window');

  FKbHook := SetWindowsHookEx(WH_KEYBOARD_LL, @KbHookProc, HInstance, 0);
  Check('hooks: the keyboard hook installs', FKbHook <> 0, 'SetWindowsHookEx(WH_KEYBOARD_LL) failed');

  try
    SetText(FEdit, HOST_TEXT);
    SetCaret(FEdit, 6);
    Pump(60); // the child must have processed the text and the caret it was sent

    { Starting the watch asked for one reading; the timer's tick takes it through
      the real layers. }
    AnsiCaretWatchTick;
    Check('hooks: the tick reads the text before the caret through the real layers',
      AnsiCaretContextTail(Tail) and (Tail = HOST_TEXT), Format('tail=[%s] want [%s]', [HexUnits(Tail), HexUnits(HOST_TEXT)]));
    Check('hooks: the reading is attributed to the message path', AnsiCaretContextSource = csWindowText,
      'the reading does not name the window-text layer');
    Check('hooks: the reading the watch took is fresh enough to erase behind', AnsiCaretContextVerify,
      'verify refused the reading the watch had just taken');

    { ---- the MASTER SWITCH ------------------------------------------------ }

    { The hooks are live, the provider is installed and the most invasive layer
      is switched ON here, so a reading taken with the master switch off would
      inject keys into the foreground window and the child would log them. The
      master switch must therefore stop the READING, not just the erase: a user
      who turns smart backspace off must not have their clipboard rewritten and
      their document typed into for a description the press path discards. }
    AnsiCaretWatchStats(Events, RefsBase);
    AnsiSmartBackspace := 'NO';
    AnsiBackspaceClipboard := 'YES';
    try
      Check('hooks: the master switch really turns the feature off', not AnsiBackspaceEnabled,
        'AnsiBackspaceEnabled still reports on');

      SetText(FEdit, HOST_TEXT);
      SetCaret(FEdit, 6);
      Pump(60);
      KeyLines := ChildKeyLines;

      AnsiCaretWatchNoteCaretEvent('harness: a caret event while the feature is switched off');
      AnsiCaretWatchTick;
      Check('hooks: with the master switch off the tick takes no reading', not AnsiCaretContextTail(Tail),
        Format('tail=[%s] was cached even though the feature is off', [HexUnits(Tail)]));
      AnsiCaretWatchStats(Events, Refs);
      Check('hooks: ... so it counted no refresh either', Refs = RefsBase, Format('refreshes=%d (was %d)', [Refs, RefsBase]));
      Check('hooks: ... and no key reached the application, so the clipboard layer never ran', ChildKeyLines = KeyLines,
        Format('the control received %d key messages while the feature was off', [ChildKeyLines - KeyLines]));

      { ... and it is the switch that did that: the same tick reads again the
        moment it goes back on, with the same settings and the same layer. }
      AnsiSmartBackspace := 'YES';
      AnsiCaretWatchNoteCaretEvent('harness: a caret event after the feature came back');
      AnsiCaretWatchTick;
      AnsiCaretWatchStats(Events, Refs);
      Check('hooks: switching it back on reads again', (Refs > RefsBase) and AnsiCaretContextTail(Tail) and (Tail = HOST_TEXT),
        Format('refreshes=%d (was %d) tail=[%s] want [%s]', [Refs, RefsBase, HexUnits(Tail), HexUnits(HOST_TEXT)]));
    finally
      AnsiSmartBackspace := 'YES';
      AnsiBackspaceClipboard := 'NO';
    end;

    { ONE REAL KEY PRESS: injected the way a user's key arrives, seen by a real
      low-level hook, which does what the shipped hook does - open a burst and
      drop the reading, because the key that follows may change the text. The
      caret it moves belongs to the CHILD process. }
    AnsiCaretWatchStats(Events, Refs);
    Base := Events;
    FKeyDown := 0; // the clipboard cases injected keys of their own earlier
    FKeyUp := 0;
    PressVk(VK_LEFT); // moves the child's real caret one character to the left
    T0 := GetTickCount;
    while (GetTickCount - T0 < 1500) and (FKeyDown = 0) do
      Pump(5);
    Pump(80); // the key-up travels through the queue as well

    Check('hooks: a real key press reaches a real keyboard hook', (FKeyDown >= 1) and (FKeyUp >= 1),
      Format('keydowns=%d keyups=%d', [FKeyDown, FKeyUp]));
    Check('hooks: another key drops the reading, exactly as the shipped hook does', not AnsiCaretContextTail(Tail),
      Format('tail=[%s] survived a key press', [HexUnits(Tail)]));

    { The caret move the watch exists for. WINEVENT_SKIPOWNPROCESS skips only its
      OWN process, and the caret that just moved belongs to the child, so the
      real EVENT_OBJECT_LOCATIONCHANGE the press raised really reaches the watch.
      A host that raises none at all for a plain edit is still driven through the
      very entry point the hook calls, and the run says so instead of reporting a
      reading layer as broken. }
    T0 := GetTickCount;
    repeat
      Pump(20);
      AnsiCaretWatchStats(Events, Refs);
    until (Events > Base) or (GetTickCount - T0 > 800);
    Watched := Events > Base;
    if not Watched then
      AnsiCaretWatchNoteCaretEvent('harness: this host raised no caret event for the press');

    AnsiCaretWatchTick;
    AnsiCaretWatchStats(Events, Refs);
    Check('hooks: the caret move in the child reaches the watch through WinEvent', Watched,
      Format('no caret event within %d ms; the tick had to be driven through the hook''s own entry point', [GetTickCount - T0]));
    Check('hooks: the event makes the tick read again, at the NEW caret',
      (Events > Base) and AnsiCaretContextTail(Tail) and (Tail = 'abcde'),
      Format('events=%d (was %d) tail=[%s] want [abcde]', [Events, Base, HexUnits(Tail)]));

    { ... and the press path behind that reading erases exactly one visible
      character, with the mapping's own table deciding how wide it is. }
    Wide := WidestCluster;
    if (Wide = '') or (AnsiAtomMap = nil) then
      Skip('hooks: no ANSI mapping is active, so the erase width cannot be checked')
    else if AnsiTailClusterUnits(Wide) < 2 then
      Skip('hooks: the active mapping draws every cluster with one unit, so a host erase has nothing to prove')
    else
    begin
      SetText(FEdit, 'xy' + Wide);
      SetCaret(FEdit, Length('xy' + Wide));
      AnsiCaretWatchNoteCaretEvent('harness: the text before the caret changed');
      AnsiCaretWatchTick;
      Check('hooks: the reading describes the mapping''s own glyph in the real control',
        AnsiCaretContextTail(Tail) and (Tail = 'xy' + Wide), Format('tail=[%s] want [%s]', [HexUnits(Tail), HexUnits('xy' + Wide)]));
      Check('hooks: the probe is a multi-unit character of the active mapping', Length(Wide) > 1,
        Format('the widest cluster [%s] is %d units', [HexUnits(Wide), Length(Wide)]));

      { THE SURGICAL ROUTE, end to end, in the real control: the press erases the
        whole cluster with ONE edit (no emission at all) and the text and the
        caret end up exactly where they would after the backspace emission. }
      KeysBefore := ChildKeyLines;
      FSink.EraseCount := 0;
      FSink.Text := '';
      FSink.Emits := 0;
      Check('hooks: the press erases the whole character with ONE edit and nothing emitted',
        AnsiEraseHostCluster(FSink.Emit) and (FSink.Emits = 0) and (AnsiBackspaceSurgical <> 'NO'),
        Format('emits=%d erase=%d want 0 emissions through the single-edit route', [FSink.Emits, FSink.EraseCount]));
      Check('hooks: ... and the control lost exactly the cluster', TextOf(FEdit) = 'xy',
        Format('text=[%s] want [xy]', [HexUnits(TextOf(FEdit))]));
      Check('hooks: ... with the caret left where the cluster started',
        (SelectionStartOf(FEdit) = 2) and (SelectionEndOf(FEdit) = 2),
        Format('caret=%d..%d want 2..2', [SelectionStartOf(FEdit), SelectionEndOf(FEdit)]));
      Check('hooks: ... and not one key message reached the control', ChildKeyLines = KeysBefore,
        Format('the control received %d key messages', [ChildKeyLines - KeysBefore]));

      Text := '';
      Check('hooks: the reading that erased it is consumed', not AnsiCaretContextTail(Text),
        Format('tail=[%s] after the press', [HexUnits(Text)]));
      Check('hooks: a second press erases nothing', not AnsiEraseHostCluster(FSink.Emit),
        Format('emits=%d after the second press', [FSink.Emits]));

      { The control: with the single-edit route switched off the SAME press is the
        one that shipped - one emission of the mapping's own width - so the case
        above cannot pass by the erase having stopped working altogether. }
      AnsiBackspaceSurgical := 'NO';
      try
        SetText(FEdit, 'xy' + Wide);
        SetCaret(FEdit, Length('xy' + Wide));
        AnsiCaretWatchNoteCaretEvent('harness: the text before the caret changed again');
        AnsiCaretWatchTick;
        FSink.EraseCount := 0;
        FSink.Text := '';
        FSink.Emits := 0;
        KeysBefore := ChildKeyLines;
        Check('hooks: with the single-edit route off the press is the emission it was',
          AnsiEraseHostCluster(FSink.Emit) and (FSink.Emits = 1) and (FSink.EraseCount = AnsiTailClusterUnits(Wide)) and
          (FSink.Text = ''),
          Format('emits=%d erase=%d want %d text=[%s]', [FSink.Emits, FSink.EraseCount, AnsiTailClusterUnits(Wide),
          HexUnits(FSink.Text)]));
        Check('hooks: ... and the control keeps the whole glyph (nothing was edited)', TextOf(FEdit) = 'xy' + Wide,
          Format('text=[%s] want [%s]', [HexUnits(TextOf(FEdit)), HexUnits('xy' + Wide)]));
      finally
        AnsiBackspaceSurgical := 'AUTO';
      end;
    end;
  finally
    if FKbHook <> 0 then
    begin
      UnhookWindowsHookEx(FKbHook);
      FKbHook := 0;
    end;
    AnsiCaretWatchStop;
  end;

  Check('hooks: stopping the watch drops the reading', not AnsiCaretContextTail(Tail),
    Format('tail=[%s] after the stop', [HexUnits(Tail)]));
end;

function AwayWndProc(hWnd: HWND; Msg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
begin
  Result := DefWindowProc(hWnd, Msg, wParam, lParam);
end;

{ Creates (once) the window the foreground is handed to during the switch case. }
function MakeAwayWindow: HWND;
var
  Wc: TWndClass;
begin
  if FAway = 0 then
  begin
    FillChar(Wc, SizeOf(Wc), 0);
    Wc.lpfnWndProc := @AwayWndProc;
    Wc.hInstance := HInstance;
    Wc.hbrBackground := HBRUSH(COLOR_WINDOW + 1);
    Wc.lpszClassName := PChar(AWAY_CLASS);
    Winapi.Windows.RegisterClass(Wc); // 0 == already registered; fine either way
    FAway := CreateWindowEx(0, PChar(AWAY_CLASS), 'kat_host: another application', WS_OVERLAPPEDWINDOW or WS_VISIBLE,
      40, 40, 320, 120, 0, 0, HInstance, nil);
  end;
  Result := FAway;
end;

{ ============================================================================== }
{ D2. the reported switch: foreground away and back, no click, one Backspace       }
{ ============================================================================== }

{ The report this case exists for: switch away from the application and back
  (an Alt-Tab), do NOT click anywhere, then press Backspace once. The caret is
  already where the user wants it, so no further caret event arrives. In the
  product the window-check timer's tick has already read the new window by then,
  and the mode / dead-key work it does for the change drops that reading
  (TLayout.ResetDeadKey -> InvalidateAnsiTail -> AnsiBackspaceInvalidate), so the
  same handler has to re-arm and read again (AnsiCaretWatchForegroundChanged,
  uForm1.WindowCheckTimer). Without that call the cache stays empty, the first
  press answers "not ours", and the host erases ONE ANSI unit - the defect.

  This drives that exact order against the real child control with the real
  message-path reader: the forearm goes AWAY and BACK for real, nothing is
  clicked, the tick reads, the drop happens, the re-arm reads again, and then one
  press has to take the whole visible cluster. }
procedure ForegroundRoundTripChecks;
var
  Wide:   string;
  Tail:   string;
  Want:   string;
  Before: string;
  Keys:   Integer;
  Away:   HWND;

  { TRUE when the watch produces the reading the press needs, within the ticks a
    real timer would take. A read that comes back empty is retried by the watch
    on the NEXT tick (F9), so a warm-up here measures what the product does
    instead of asserting on one read the way a flaky case would. It stays a
    regression: nothing below injects a reading, and without the re-arm in
    uForm1.WindowCheckTimer there is no pending request at all, so no number of
    ticks produces one. }
  function ReadingAppears: Boolean;
  var
    I: Integer;
  begin
    for I := 1 to SWITCH_TICKS do
    begin
      if AnsiCaretContextVerify and AnsiCaretContextTail(Tail) and (Tail = Want) then
        Exit(True);
      AnsiCaretWatchTick;
    end;
    Result := AnsiCaretContextVerify and AnsiCaretContextTail(Tail) and (Tail = Want);
  end;
begin
  if not TakeFocus(FEdit, EDIT_ID) then
  begin
    Skip('switch: the test window could not take the foreground');
    Exit;
  end;

  AnsiSmartBackspace := 'YES';
  AnsiBackspaceHostErase := 'YES';
  AnsiBackspaceUIA := 'YES';
  AnsiBackspaceClipboard := 'NO';
  AnsiBackspaceSurgical := 'AUTO';

  Wide := WidestCluster;
  if (Wide = '') or (AnsiAtomMap = nil) or (AnsiTailClusterUnits(Wide) < 2) then
  begin
    Skip('switch: no multi-unit ANSI cluster in the active mapping to erase');
    Exit;
  end;

  { Where the foreground goes while the user is "in another application": the
    console that runs this harness. A head-less watch keeps the live desktop's
    own carets out of the measurement; the events are raised through the same
    entry point the WinEvent hook uses. }
  Away := GetConsoleWindow;
  if Away = 0 then
    Away := MakeAwayWindow;
  if Away = 0 then
  begin
    Skip('switch: no window to hand the foreground to');
    Exit;
  end;

  Want := 'xy' + Wide;
  AnsiCaretWatchStartHeadless;
  try
    SetText(FEdit, 'xy' + Wide);
    SetCaret(FEdit, Length('xy' + Wide));
    Pump(80);

    { The reading the timer takes before the switch: the control really holds
      the mapping's own glyph. }
    AnsiCaretWatchNoteCaretEvent('harness: the reading before the switch');
    Check('switch: the watch reads the control before the switch', ReadingAppears,
      Format('tail=[%s] want [%s]', [HexUnits(Tail), HexUnits(Want)]));

    { ---- the user's sequence ------------------------------------------------- }
    ForceForeground(Away); // ... away ...
    Pump(80);
    Check('switch: the foreground really left the host', GetForegroundWindow <> FHost,
      Format('the foreground is still %s', [Described(GetForegroundWindow)]));
    if not TakeFocus(FEdit, EDIT_ID) then // ... and back, without a click
    begin
      Skip('switch: the host could not take the foreground back');
      Exit;
    end;
    Pump(80);

    { The timer interval that notices the change: its tick reads the window in
      front, and then the mode / dead-key work the same handler does for the
      change drops what it read. }
    AnsiCaretWatchNoteCaretEvent('harness: the interval that notices the change');
    Check('switch: the tick that notices the change reads the window in front', ReadingAppears,
      Format('tail=[%s] want [%s]', [HexUnits(Tail), HexUnits(Want)]));
    AnsiBackspaceInvalidate; // == TLayout.ResetDeadKey, for the reading
    Check('switch: the switch handling dropped the reading that tick had taken',
      not AnsiCaretContextTail(Tail), Format('tail=[%s] survived the drop', [HexUnits(Tail)]));

    { ... and the same handler re-arms the request and reads a second time. THIS is
      the fix; a reading is REQUIRED here, and nothing below injects one. }
    AnsiCaretWatchForegroundChanged;
    Check('switch: the re-armed tick leaves a usable reading without a click', ReadingAppears,
      Format('tail=[%s] want [%s]: the first press would answer "not ours"', [HexUnits(Tail), HexUnits(Want)]));
    Check('switch: ... and the reading is fresh enough for the press to accept it', AnsiCaretContextVerify,
      Format('tail=[%s]: a stale or absent reading means the press answers "not ours"', [HexUnits(Tail)]));

    { ---- ONE press, the whole cluster --------------------------------------- }
    Before := TextOf(FEdit);
    Keys := ChildKeyLines;
    FSink.EraseCount := 0;
    FSink.Text := '';
    FSink.Emits := 0;
    Check('switch: the first Backspace erases the whole cluster in one action',
      AnsiEraseHostCluster(FSink.Emit) and (TextOf(FEdit) = 'xy') and (SelectionStartOf(FEdit) = 2) and
      (SelectionEndOf(FEdit) = 2),
      Format('text [%s] -> [%s] caret=%d..%d', [HexUnits(Before), HexUnits(TextOf(FEdit)), SelectionStartOf(FEdit),
      SelectionEndOf(FEdit)]));
    Check('switch: the text in front of the cluster is untouched', TextOf(FEdit) = Copy(Before, 1, 2),
      Format('text=[%s] want [%s]', [HexUnits(TextOf(FEdit)), HexUnits(Copy(Before, 1, 2))]));
    Check('switch: and no key message was needed for it', ChildKeyLines = Keys,
      Format('the control received %d key messages', [ChildKeyLines - Keys]));
  finally
    AnsiCaretWatchStop;
  end;
end;

{ ============================================================================== }
{ E. the host matrix: what each host answers, what it costs, what it touches      }
{ ============================================================================== }

{ Why this section exists at all: every case above runs against a window THIS
  program created, and the hosts users report against are Word, Excel, Chrome, VS
  Code, WordPad and LibreOffice. A harness cannot type into a real document, so
  the matrix MEASURES the hosts it owns and, for the ones it can only FIND, emits
  a row naming the window it found and the command that produces the real row.
  Evidence instead of a guess. }

{ The layer that served a reading, for the table's own column: the enum is the
  product's, this is only how a person reads it. }
function SourceName(const ASource: TAnsiContextSource): string;
begin
  case ASource of
    csWindowText:
      Result := 'window-text';
    csUIA:
      Result := 'uia';
    csClipboard:
      Result := 'clipboard';
    csInjected:
      Result := 'injected';
  else
    Result := 'none';
  end;
end;

function YesNo(const AValue: Boolean): string;
begin
  if AValue then
    Result := 'ok'
  else
    Result := 'NO';
end;

{ What the CLIPBOARD holds right now, in one string: its text, how many formats
  it offers and whether a bitmap is one of them. The matrix asserts the value is
  the same before and after a reading, and a fingerprint that looked only at the
  text would call a wiped image-only clipboard "unchanged" - which is exactly the
  data loss the clipboard layer's own format check exists to prevent. }
function ClipboardFingerprint: string;
var
  Text:   string;
  Fmt:    UINT;
  Fmts:   Integer;
  Bitmap: Boolean;
begin
  if ClipAsText(Text) then
    Result := Format('text=[%s]', [Text])
  else
    Result := 'text=<unreadable>';
  try
    Bitmap := Clipboard.HasFormat(CF_BITMAP);
  except
    on E: Exception do
      Bitmap := False; // another application holds it open: report what is known
  end;
  Fmts := 0;
  if OpenClipboard(0) then
  begin
    Fmt := EnumClipboardFormats(0);
    while Fmt <> 0 do
    begin
      Inc(Fmts);
      Fmt := EnumClipboardFormats(Fmt);
    end;
    CloseClipboard;
  end;
  Result := Format('%s formats=%d bitmap=%s', [Result, Fmts, BoolToStr(Bitmap, True)]);
end;

{ One control, the whole corpus.

  For every item the control is filled with the ACTIVE mapping's own ANSI units
  for that cluster and the caret is put behind them, one reading is taken through
  the REAL layer chain, and the row records which layer answered, how long it
  took, what it read and how wide the press path thinks the cluster is - together
  with whether the document, the caret and the clipboard came out untouched. The
  last column is asserted by code, not observed by eye.

  AExpectRead is False for the password field: there the row of interest is the
  refusal, and what is asserted is that the field is untouched and that the width
  is the one-unit safety answer the invariants demand. }
procedure MatrixControl(const AName: string; const ACtl: HWND; const AId: Integer; const AExpectRead: Boolean);
var
  Conv:     TUnicodeToBijoy2000;
  I:        Integer;
  Units:    string;
  Fill:     string;
  Tail:     string;
  Reason:   string;
  Layer:    string;
  Decision: TAnsiEraseDecision;
  Width:    Integer;
  Ms:       Integer;
  T0:       Cardinal;
  ClipWas:  string;
  Keys:     Integer;
  CaretWas: Integer;
  LenWas:   Integer;
  ReadOk:   Boolean;
  TextOk:   Boolean;
  CaretOk:  Boolean;
  ClipOk:   Boolean;
begin
  if not TakeFocus(ACtl, AId) then
  begin
    Skip(Format('matrix: %s could not take the foreground', [AName]));
    Exit;
  end;

  Conv := TUnicodeToBijoy2000.Create;
  try
    for I := 0 to high(MATRIX_CORPUS) do
    begin
      Units := Conv.Convert(MATRIX_CORPUS[I]);
      if Units = '' then
      begin
        Skip(Format('matrix: %s / %s: the active mapping draws no ANSI units for it', [AName, MATRIX_LABELS[I]]));
        Continue;
      end;

      Fill := MATRIX_FILLER + Units;
      SetText(ACtl, Fill);
      SetCaret(ACtl, Length(Fill));
      Pump(60);
      if not TakeFocus(ACtl, AId) then
      begin
        Skip(Format('matrix: %s / %s: the foreground was taken by %s', [AName, MATRIX_LABELS[I],
          Described(GetForegroundWindow)]));
        Continue;
      end;

      ClipWas := ClipboardFingerprint;
      Keys := ChildKeyLines;
      CaretWas := SelectionStartOf(ACtl);
      LenWas := TextLenOf(ACtl);

      T0 := GetTickCount;
      ReadHere(Format('matrix: %s / %s', [AName, MATRIX_LABELS[I]]));
      Ms := Integer(GetTickCount - T0);

      ReadOk := AnsiCaretContextTail(Tail);
      if not ReadOk then
        Tail := '';
      Layer := SourceName(AnsiCaretContextSource);

      { The Boolean only says whether the press path would erase; the width and the
        decision the row exists for are set on every path. }
      AnsiHostClusterUnits(Width, Decision, Reason);

      if AExpectRead then
        TextOk := TextOf(ACtl) = Fill
      else
        TextOk := TextLenOf(ACtl) = LenWas; // a password field's text is not readable from here
      CaretOk := (SelectionStartOf(ACtl) = CaretWas) and (SelectionEndOf(ACtl) = CaretWas);
      ClipOk := ClipboardFingerprint = ClipWas;

      Say(Format('  %-16s %-10s %-12s %4d  %5d  %-20s text=%-3s caret=%-3s clip=%-3s tail=[%s]',
        [AName, MATRIX_LABELS[I], Layer, Ms, Width, AnsiDecisionName(Decision), YesNo(TextOk), YesNo(CaretOk),
        YesNo(ClipOk), HexUnits(Tail)]));

      Check(Format('matrix: %s / %s: the reading describes the text before the caret', [AName, MATRIX_LABELS[I]]),
        (ReadOk = AExpectRead) and ((not AExpectRead) or (Tail = Fill)),
        Format('layer=%s tail=[%s] want [%s] (%s)', [Layer, HexUnits(Tail), HexUnits(Fill), Reason]));
      Check(Format('matrix: %s / %s: the document, the caret and the clipboard are untouched', [AName, MATRIX_LABELS[I]]),
        TextOk and CaretOk and ClipOk,
        Format('text=%s caret=%s clipboard=%s (%s)', [BoolToStr(TextOk, True), BoolToStr(CaretOk, True),
        BoolToStr(ClipOk, True), ClipWas]));
      Check(Format('matrix: %s / %s: the reading pressed no key', [AName, MATRIX_LABELS[I]]), ChildKeyLines = Keys,
        Format('the control received %d key messages while it was read', [ChildKeyLines - Keys]));
      if not AExpectRead then
        Check(Format('matrix: %s / %s: with no reading the width is the one-unit safety answer', [AName, MATRIX_LABELS[I]]),
          (Width = 1) and (Decision = edNotMine), Format('units=%d decision=%s', [Width, AnsiDecisionName(Decision)]));
    end;
  finally
    Conv.Free;
  end;
end;

type
  { One real host the reviewers ask about. Klass is a '|'-separated list of window
    class substrings (any of them matches, case-insensitively - the same partial
    match idea the per-application override uses) and Title is a substring the
    window's TITLE must contain, because a frame class alone does not name an
    application: 'Chrome_WidgetWin_1' is Chrome, Edge and every Electron app at
    once, and 'ApplicationFrameWindow' is half the Store. }
  TMatrixHost = record
    Name:  string;
    Klass: string;
    Title: string;
    Note:  string;
  end;

const
  FOREIGN_HOSTS: array [0 .. 6] of TMatrixHost = (
    (Name: 'Notepad'; Klass: 'NOTEPAD|APPLICATIONFRAMEWINDOW'; Title: 'NOTEPAD'; Note: 'the frame; its editor is an Edit control'),
    (Name: 'WordPad'; Klass: 'WORDPADCLASS'; Title: 'WORDPAD'; Note: 'the frame; its editor is a RICHEDIT control'),
    (Name: 'MS Word'; Klass: 'OPUSAPP'; Title: 'WORD'; Note: 'the frame; the editing surface is a _WwG child window'),
    (Name: 'Excel'; Klass: 'XLMAIN'; Title: 'EXCEL'; Note: 'the frame; the grid is an EXCEL7 child window'),
    (Name: 'Chrome/Edge'; Klass: 'CHROME_WIDGETWIN_1'; Title: ''; Note: 'any Chromium host - an Electron application matches this too'),
    (Name: 'VS Code'; Klass: 'CHROME_WIDGETWIN_1'; Title: 'VISUAL STUDIO CODE'; Note: 'the frame; the editor itself is a second window'),
    (Name: 'LibreOffice Writer'; Klass: 'SALFRAME'; Title: 'LIBREOFFICE'; Note: 'the document frame'));

var
  FFindClass: string;
  FFindTitle: string;
  FFindFound: HWND;

{ Does a window carry this class, and this much of its title? }
function WindowMatches(const AWin: HWND; const APatterns, ATitleHint: string): Boolean;
var
  Buf:    array [0 .. 255] of Char;
  Title:  array [0 .. 255] of Char;
  Cls:    string;
  Seen:   string;
  Parts:  TStringList;
  I:      Integer;
begin
  Result := False;
  if AWin = 0 then
    Exit;
  Cls := '';
  if GetClassName(AWin, Buf, Length(Buf)) > 0 then
    Cls := Buf;
  Cls := UpperCase(Cls);

  if ATitleHint <> '' then
  begin
    Title := '';
    GetWindowText(AWin, Title, Length(Title));
    Seen := Title;
    if (Seen = '') or (Pos(UpperCase(ATitleHint), UpperCase(Seen)) = 0) then
      Exit;
  end;

  Parts := TStringList.Create;
  try
    Parts.Delimiter := '|';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := APatterns;
    for I := 0 to Parts.Count - 1 do
      if (Parts[I] <> '') and (Pos(UpperCase(Parts[I]), Cls) > 0) then
        Exit(True);
  finally
    Parts.Free;
  end;
end;

function EnumHostProc(AWin: HWND; AParam: LPARAM): BOOL; stdcall;
begin
  Result := True; // keep enumerating: a later window may be the one looked for
  if (FFindFound <> 0) or (not IsWindowVisible(AWin)) then
    Exit;
  if WindowMatches(AWin, FFindClass, FFindTitle) then
    FFindFound := AWin;
end;

function FindHostWindow(const APatterns, ATitleHint: string; out AWin: HWND): Boolean;
begin
  FFindClass := APatterns;
  FFindTitle := ATitleHint;
  FFindFound := 0;
  EnumWindows(@EnumHostProc, 0);
  AWin := FFindFound;
  Result := AWin <> 0;
end;

function TitleHintText(const AHint: string): string;
begin
  if AHint = '' then
    Result := ''
  else
    Result := Format(' and a title containing [%s]', [AHint]);
end;

{ The hosts this run cannot measure. This is the honest half of a host matrix: a
  row that says the application was FOUND (class and pid, so anyone can repeat
  the measurement) and names the one command that produces its real row - rather
  than a harness that opens the user's document to score a point. }
procedure MatrixForeignHosts;
var
  I:   Integer;
  Win: HWND;
begin
  Say('');
  Say('  the hosts this run cannot measure - a harness never types into a real document:');
  for I := 0 to high(FOREIGN_HOSTS) do
  begin
    if not FindHostWindow(FOREIGN_HOSTS[I].Klass, FOREIGN_HOSTS[I].Title, Win) then
      Skip(Format('matrix: %s: not running (looked for class [%s]%s)', [FOREIGN_HOSTS[I].Name, FOREIGN_HOSTS[I].Klass,
        TitleHintText(FOREIGN_HOSTS[I].Title)]))
    else
      Skip(Format('matrix: %s: running as %s - put it in the foreground and run `kat_host --probe` for its real row (%s)',
        [FOREIGN_HOSTS[I].Name, Described(Win), FOREIGN_HOSTS[I].Note]));
  end;
end;

{ The whole matrix: the controls this program owns, then the hosts it can only
  find. The head-less watch is used again - the real provider chain and the real
  fingerprint, no OS hooks - because the rows are about WHICH layer answers and
  what it reads, not about whether this desktop delivers caret events. }
procedure MatrixChecks;
var
  Tail: string;
begin
  AnsiSmartBackspace := 'YES';
  AnsiBackspaceHostErase := 'YES';
  AnsiBackspaceSurgical := 'AUTO';
  AnsiBackspaceUIA := 'YES';
  AnsiBackspaceClipboard := 'NO'; // the matrix never injects a key
  AnsiCaretWatchStartHeadless;
  try
    Say('');
    Say('  host              cluster     layer          ms  units decision              text caret clip tail');
    MatrixControl('edit', FEdit, EDIT_ID, True);
    MatrixControl('multi-line edit', FMulti, MULTI_ID, True);
    if FRich = 0 then
      Skip('matrix: no rich edit class on this machine, so the rich-edit row is missing')
    else
      MatrixControl('rich edit', FRich, RICH_ID, True);
    MatrixControl('password edit', FPass, PASS_ID, False);
  finally
    AnsiCaretWatchStop;
    AnsiBackspaceUIA := 'YES';
  end;

  MatrixForeignHosts;

  Tail := '';
  Check('matrix: the matrix leaves no reading behind', not AnsiCaretContextTail(Tail), Format('tail=[%s]', [HexUnits(Tail)]));
end;

{ ============================================================================== }
{ F. the probe: one line of evidence for the window in front                      }
{ ============================================================================== }

{ For a host this program cannot drive - Word, Excel, a browser, a terminal - the
  only honest measurement is taken while the USER has it in front. `kat_host
  --probe` describes the foreground window through the same layers and prints one
  line: which layer answered, how long it took, the tail, the width the press path
  would erase, the decision and the caret fingerprint. It never types, never
  selects, never takes the foreground and never touches the clipboard - the
  clipboard layer is forced OFF here by construction, because a diagnostic that
  injects keys into somebody's document is not a diagnostic. }
procedure ProbeForeground;
var
  Fg:       HWND;
  Focused:  HWND;
  Reader:   TUiaTextReader;
  Tail:     string;
  UiaTail:  string;
  Reason:   string;
  Layer:    string;
  Decision: TAnsiEraseDecision;
  Units:    Integer;
  Ms:       Integer;
  T0:       Cardinal;
  Events:   Integer;
  Refs:     Integer;
  Fp:       TCaretFingerprint;
  HaveFp:   Boolean;
  Erase:    Boolean;
begin
  Fg := GetForegroundWindow;
  Focused := FocusedControl;

  Say('  the clipboard layer is switched OFF for a probe: nothing below injects a key');
  Say('');
  Say(Format('  foreground : %s', [Described(Fg)]));
  Say(Format('  focus      : %s', [Described(Focused)]));

  AnsiSmartBackspace := 'YES';
  AnsiBackspaceHostErase := 'YES';
  AnsiBackspaceUIA := 'YES';
  AnsiBackspaceClipboard := 'NO';
  SniffOverrideActive := False; // the REAL readers

  Tail := '';
  Layer := 'none';
  Units := 1;
  Decision := edNotMine;
  Reason := 'the probe did not run';
  Events := 0;
  Refs := 0;

  { Everything that needs a reading is measured BEFORE the watch stops: stopping
    it drops the reading, which is asserted in section D and is the behaviour the
    press path relies on. }
  AnsiCaretWatchStartHeadless;
  try
    AnsiCaretWatchNoteCaretEvent('probe: describe the window in front');
    T0 := GetTickCount;
    AnsiCaretWatchTick;
    Ms := Integer(GetTickCount - T0);
    AnsiCaretWatchStats(Events, Refs);

    if AnsiCaretContextTail(Tail) then
      Layer := SourceName(AnsiCaretContextSource)
    else
    begin
      Tail := '';
      Layer := 'none';
    end;
    HaveFp := AnsiCaretContextFingerprint(Fp);
    Erase := AnsiHostClusterUnits(Units, Decision, Reason);
  finally
    AnsiCaretWatchStop;
  end;

  { The UIA half, taken directly and after the fact: it costs a COM client and can
    block in a browser that is only just waking its accessibility support, so it is
    reported separately from the layer chain above. }
  Reader := TUiaTextReader.Create;
  try
    UiaTail := Reader.ReadBeforeCaret(PROBE_CHARS);
    Say(Format('  uia        : read=%s available=%s', [BoolToStr(UiaTail <> '', True), BoolToStr(Reader.Available, True)]));
    Say(Format('  uia element: %s', [Reader.ElementInfo]));
    Say(Format('  uia tail   : [%s]', [HexUnits(UiaTail)]));
  finally
    Reader.Reset;
    Reader.Free;
  end;

  Say('');
  Say(Format('PROBE layer=%s ms=%d tail=[%s] units=%d decision=%s erase=%s reason=[%s]',
    [Layer, Ms, HexUnits(Tail), Units, AnsiDecisionName(Decision), BoolToStr(Erase, True), Reason]));
  if HaveFp then
    Say(Format('PROBE fingerprint window=%x caret=%d,%d %s', [NativeUInt(Fp.Window), Fp.CaretX, Fp.CaretY,
      Format('chars before the caret=%d', [Fp.TextLength])]))
  else
    Say('PROBE fingerprint: none - no reading describes this window');
  Say(Format('PROBE watches: events=%d refreshes=%d', [Events, Refs]));
end;

{ ============================================================================== }
{ entry point                                                                    }
{ ============================================================================== }

var
  ErrLog:    TStringList;
  Mapping:   string;
  I:         Integer;
  ParentPid: Cardinal;

begin
  FQuiet := False;
  FChecks := 0;
  FFails := 0;
  FSkipped := 0;
  FKeyDown := 0;
  FKeyUp := 0;
  FKbHook := 0;
  FHost := 0;
  FRich := 0;
  FChild := 0;
  FChildThread := 0;
  FChildPid := 0;
  FServe := False;
  FServeQuit := False;
  FMatrix := False;
  FProbe := False;
  ParentPid := 0;

  for I := 1 to ParamCount do
    if SameText(ParamStr(I), 'quiet') then
      FQuiet := True
    else if SameText(ParamStr(I), '--serve') then
      FServe := True
    else if SameText(ParamStr(I), '--matrix') then
      FMatrix := True
    else if SameText(ParamStr(I), '--probe') then
      FProbe := True;

  if FServe then
  begin
    { THE TARGET: create the window, answer the focus requests and pump. The
      parent's process id is the second argument, and it names the window so two
      runs on one desktop never find each other's. }
    if ParamCount >= 2 then
      ParentPid := Cardinal(StrToIntDef(ParamStr(2), 0));
    try
      Serve(ParentPid);
    except
      on E: Exception do
      begin
        // Nothing is read from here: the parent reports what went wrong.
        Halt(1);
      end;
    end;
    Halt(0);
  end;

  try
    if FProbe then
      Say('kat_host --probe: one line for the window in the foreground')
    else
      Say('kat_host: the reading layers against real controls of a child process');

    { A console process starts with the settings globals EMPTY, i.e. NOT the
      application's defaults, and the ANSI host-text path is only reachable in
      ANSI output mode. ShowPrevWindow = 'NO' keeps the phonetic engine away from
      its preview form, which a harness has no reason to create. }
    OutputIsBijoy := 'YES';
    ShowPrevWindow := 'NO';
    EnableCaretSniffer := 'YES';
    AnsiBackspaceLegacy := 'NO';
    AnsiSmartBackspace := 'YES';
    AnsiBackspaceHostErase := 'YES';
    AnsiBackspaceUnitCap := '8';
    AnsiBackspaceSurgical := 'AUTO';
    AnsiBackspaceUIA := 'YES';
    AnsiBackspaceClipboard := 'NO';
    AnsiBackspaceApps := '';
    AnsiBackspaceLog := 'NO';
    SniffOverrideActive := False; // the REAL readers, not the head-less hook

    FSink := TEraseSink.Create;
    { The probe describes a window that is already in front, so it starts nothing
      and takes no foreground: a diagnostic that steals the foreground measures
      itself instead of the host the user cares about. }
    if not FProbe then
      StartChild;
  except
    on E: Exception do
    begin
      WriteLn('FAIL the test host could not be created: ' + E.ClassName + ': ' + E.Message);
      StopChild; // a child that was started before the failure must not linger
      Halt(1);
    end;
  end;

  { The engine's own glyph table: the width of the last case comes from it. The
    readers below do not care which mapping is active. }
  ErrLog := TStringList.Create;
  try
    if not AnsiEngineManager.SwitchEngine('Default', ErrLog) then
    begin
      WriteLn('FAIL the built-in Default mapping could not be activated: ' + Trim(ErrLog.Text));
      StopChild;
      Halt(1);
    end;
  finally
    ErrLog.Free;
  end;
  Mapping := AnsiVersion;

  if FProbe then
  begin
    ProbeForeground;
    FSink.Free;
    Halt(0);
  end;

  if not TakeFocus(FEdit, EDIT_ID) then
  begin
    Say('');
    Say('SKIP the desktop did not hand the foreground to the test window.');
    Say('     Every reading layer describes the ACTIVE window, so there is nothing to read.');
    Say('     Close whatever holds the foreground and run this again.');
    StopChild;
    FSink.Free;
    Halt(2);
  end;

  try
    Say('');
    Say('=== the controls');
    Check('the first control is a standard EDIT', UpperCase(ClassOf(FEdit)) = 'EDIT', Format('class=[%s]', [ClassOf(FEdit)]));

    { The class the child ended up rendering its rich edit with: every rich-edit
      case below names it. }
    FRichCls := ClassOf(FRich);
    if FRich = 0 then
      Skip('no rich edit class on this machine (msftedit.dll / riched20.dll)')
    else
      Check('the second control reports a RICHEDIT class', Pos('RICHEDIT', UpperCase(ClassOf(FRich))) = 1,
        Format('class=[%s]', [ClassOf(FRich)]));
    Check('the password control really is one', (GetWindowLong(FPass, GWL_STYLE) and ES_PASSWORD) <> 0,
      Format('style=$%.8x', [GetWindowLong(FPass, GWL_STYLE)]));
    Check(Format('an ANSI mapping is active and has a glyph table (%s)', [Mapping]), AnsiAtomMap <> nil,
      'AnsiAtomMap is nil: the host-text width would be unknown');

    Say('');
    Say('=== A. the message path (EM_GETSEL + WM_GETTEXT, no side effects)');
    MessagePathChecks('edit', FEdit, EDIT_ID);
    MessagePathChecks('multi-line edit', FMulti, MULTI_ID);
    if FRich = 0 then
      Skip('message path: no rich edit class on this machine')
    else
      MessagePathChecks(Format('rich edit (%s)', [FRichCls]), FRich, RICH_ID);

    Say('');
    Say('=== B. UI Automation (a real client against the same controls)');
    UiaChecks;

    Say('');
    Say('=== B2. the surgical erase (one edit, no injected key)');
    SurgicalChecks;

    Say('');
    Say('=== C. the clipboard round-trip (keys injected, clipboard and caret restored)');
    ClipboardChecks;

    Say('');
    Say('=== D. the watch, a real key press and one emission');
    HookChecks;

    Say('');
    Say('=== D2. the reported switch: foreground away and back, no click, one Backspace');
    ForegroundRoundTripChecks;

    if FMatrix then
    begin
      Say('');
      Say('=== E. the host matrix (every host this run measures, and every host it cannot)');
      MatrixChecks;
    end;

    Say('');
    Say('=== summary');
    Say(Format('  %d checks, %d failures, %d skipped', [FChecks, FFails, FSkipped]));
  except
    on E: Exception do
    begin
      WriteLn('FAIL exception: ' + E.ClassName + ': ' + E.Message);
      Inc(FFails);
    end;
  end;

  StopChild;
  FSink.Free;

  if FFails = 0 then
  begin
    WriteLn('kat_host: ALL PASS');
    Halt(0);
  end;

  WriteLn('kat_host: FAIL');
  Halt(1);
end.
