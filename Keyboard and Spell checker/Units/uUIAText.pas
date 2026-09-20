{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uUIAText;

{ =============================================================================
  uUIAText - LAYER B of the caret-context reading: the text in front of the
  caret, read through UI Automation's Text pattern.

  Why this layer exists
  ---------------------
  uCaretContextSniffer's message path (EM_GETSEL + WM_GETTEXT) only reaches a
  standard EDIT / RICHEDIT control. Notepad and WordPad are covered by it, but
  Word, Excel, the browsers, VS Code and LibreOffice expose their text to UI
  Automation instead, and that is exactly where the ANSI backspace would
  otherwise fall back to the host's single character. This layer reads the same
  text without a clipboard round-trip, without injected keys and without
  changing the selection or the focus:

      1. CoCreateInstance(CLSID_CUIAutomation)                    - once, cached
      2. GetFocusedElement, or ElementFromHandle of the focused window
      3. GetCurrentPatternAs(UIA_TextPattern2Id) -> GetCaretRange
         ... or GetCurrentPatternAs(UIA_TextPatternId) -> GetSelection
      4. Clone the caret range and move its START endpoint back by N characters
         with MoveEndpointByUnit(UIA_TextUnit_Character, -N)
      5. GetText(N) - the characters now in front of the caret

  Rules this unit obeys
  ---------------------
  * NEVER called from a keyboard or mouse hook. Chromium enables accessibility
    lazily, so the FIRST call can cost ~100 ms. The caller (uCaretWatch) runs it
    from the application timer, on the main thread, at most once per burst.
  * Fail-safe: every failure returns '' and nothing else. No width is guessed
    here; an empty reading means the caller keeps the pre-feature behaviour.
  * An active selection is never read (the caret is not where the eraser
    assumes), and a password field (UIA_IsPasswordPropertyId) is never read.
  * The reading lives only in the caller's cache: nothing is logged or written
    anywhere, and the text is used for one thing - measuring how many ANSI units
    the last visible character in front of the caret occupies.
  * No exception escapes: every failure is a normal answer.

  Cost control
  ------------
  The element of the focused control is the expensive part of a read: fetching
  it is a cross-process call, and the FIRST one of a session can cost ~100 ms
  while Chromium turns accessibility on. It is therefore CACHED - while the
  focused control does not change, and for UIA_ELEMENT_TTL_MS at most - together
  with the two verdicts that belong to it (whether the control is a password
  field, and which Text pattern it exposes: resolving a pattern is another
  cross-process call and neither answer can change while it is the same
  control). A kept element therefore costs one cross-process call per read
  instead of four. Two budgets bound the rest: at most one probe per
  UIA_PROBE_INTERVAL_MS, so a caret that blinks or a host that raises location
  events on every scroll cannot become a stream of COM calls, and a process
  whose element answered nothing is left alone for UIA_QUIET_MS instead of being
  asked again on every keystroke (keyed by the control, so a password field does
  not silence the rest of its application). Both budgets only ever DECLINE a
  read, and a declined read is the empty answer every caller already handles.

  The interface declarations below are written out because this Delphi
  installation ships no Winapi.UIAutomationClient / Winapi.UIAutomationCore.
  Every IID, every method ORDER and every constant was taken from the Windows
  SDK's uiautomationclient.idl (verified against the header, not remembered):
  the vtable order is what makes a call land on the right slot, so the methods
  that are not needed are declared as well - up to the last one this unit calls.
  ============================================================================= }

interface

uses
  Winapi.Windows;

type
  IUIAutomation = interface;
  IUIAutomationElement = interface;
  IUIAutomationTextPattern = interface;
  IUIAutomationTextPattern2 = interface;
  IUIAutomationTextRange = interface;
  IUIAutomationTextRangeArray = interface;

  { IUIAutomation - the root object: slots 1..6 of the real interface, and the
    two that are called are ElementFromHandle (4) and GetFocusedElement (6). The
    declaration STOPS here on purpose: the real interface continues (cache
    requests, tree walkers, conditions), but a declaration that stops before a
    method cannot shift the slots of the ones it keeps, and nothing below this
    point is called. }
  IUIAutomation = interface(IUnknown)
    ['{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}']
    function CompareElements(const el1, el2: IUIAutomationElement; out areSame: BOOL): HRESULT; stdcall;
    function CompareRuntimeIds(const runtimeId1, runtimeId2: Pointer; out areSame: BOOL): HRESULT; stdcall;
    function GetRootElement(out root: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromHandle(hwnd: HWND; out element: IUIAutomationElement): HRESULT; stdcall;
    function ElementFromPoint(pt: TPoint; out element: IUIAutomationElement): HRESULT; stdcall;
    function GetFocusedElement(out element: IUIAutomationElement): HRESULT; stdcall;
  end;

  { IUIAutomationElement - slots 1..12 of the real interface. The two that are
    called are GetCurrentPropertyValue (8, the password and the diagnostic
    properties) and GetCurrentPatternAs (12, the Text patterns); the rest only
    keep the slots lined up, in the SDK's order (uiautomationclient.h). Slots 13
    and 14 (the cached and the untyped pattern getters) are NOT declared - they
    were measured to answer nothing for the controls this unit reads. }
  IUIAutomationElement = interface(IUnknown)
    ['{D22108AA-8AC5-49A5-837B-37BBB3D7591E}']
    function SetFocus: HRESULT; stdcall;
    function GetRuntimeId(out runtimeId: Pointer): HRESULT; stdcall;
    function FindFirst(scope: Integer; const condition: IUnknown; out found: IUIAutomationElement): HRESULT; stdcall;
    function FindAll(scope: Integer; const condition: IUnknown; out found: Pointer): HRESULT; stdcall;
    function FindFirstBuildCache(scope: Integer; const condition: IUnknown; const cacheRequest: IUnknown;
      out found: IUIAutomationElement): HRESULT; stdcall;
    function FindAllBuildCache(scope: Integer; const condition: IUnknown; const cacheRequest: IUnknown;
      out found: Pointer): HRESULT; stdcall;
    function BuildUpdatedCache(const cacheRequest: IUnknown; out updatedElement: IUIAutomationElement): HRESULT; stdcall;
    function GetCurrentPropertyValue(propertyId: Integer; out retVal: OleVariant): HRESULT; stdcall;
    function GetCurrentPropertyValueEx(propertyId: Integer; ignoreDefaultValue: BOOL; out retVal: OleVariant): HRESULT; stdcall;
    function GetCachedPropertyValue(propertyId: Integer; out retVal: OleVariant): HRESULT; stdcall;
    function GetCachedPropertyValueEx(propertyId: Integer; ignoreDefaultValue: BOOL; out retVal: OleVariant): HRESULT; stdcall;
    function GetCurrentPatternAs(patternId: Integer; const riid: TGUID; out patternObject: Pointer): HRESULT; stdcall;
  end;

  { IUIAutomationTextRangeArray - complete (2 slots). }
  IUIAutomationTextRangeArray = interface(IUnknown)
    ['{CE4AE76A-E717-4C98-81EA-47371D028EB6}']
    function GetLength(out length: Integer): HRESULT; stdcall;
    function GetElement(index: Integer; out element: IUIAutomationTextRange): HRESULT; stdcall;
  end;

  { IUIAutomationTextRange - slots 1..14 of the real interface. Clone, GetText,
    CompareEndpoints, MoveEndpointByUnit and MoveEndpointByRange are the ones
    this unit needs; the rest only keep the slots lined up. }
  IUIAutomationTextRange = interface(IUnknown)
    ['{A543CC6A-F4AE-494B-8239-C814481187A8}']
    function Clone(out clone: IUIAutomationTextRange): HRESULT; stdcall;
    function Compare(const range: IUIAutomationTextRange; out areSame: BOOL): HRESULT; stdcall;
    function CompareEndpoints(endpoint: Integer; const range: IUIAutomationTextRange; endpoint2: Integer;
      out comp: Integer): HRESULT; stdcall;
    function ExpandToEnclosingUnit(unitKind: Integer): HRESULT; stdcall;
    function FindAttribute(attributeId: Integer; const val: OleVariant; backward: BOOL;
      out found: IUIAutomationTextRange): HRESULT; stdcall;
    function FindText(const text: WideString; backward: BOOL; ignoreCase: BOOL; out found: IUIAutomationTextRange): HRESULT; stdcall;
    function GetAttributeValue(attributeId: Integer; out val: OleVariant): HRESULT; stdcall;
    function GetBoundingRectangles(out rectangles: Pointer): HRESULT; stdcall;
    function GetEnclosingElement(out element: IUIAutomationElement): HRESULT; stdcall;
    function GetText(const maxLength: Integer; out text: WideString): HRESULT; stdcall;
    function Move(unitKind: Integer; count: Integer; out moved: Integer): HRESULT; stdcall;
    function MoveEndpointByUnit(endpoint: Integer; unitKind: Integer; count: Integer; out moved: Integer): HRESULT; stdcall;
    function MoveEndpointByRange(endpoint: Integer; const range: IUIAutomationTextRange; endpoint2: Integer): HRESULT; stdcall;
    function Select: HRESULT; stdcall;
  end;

  { IUIAutomationTextPattern - all 6 slots, so a descendant cannot shift them. }
  IUIAutomationTextPattern = interface(IUnknown)
    ['{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}']
    function RangeFromPoint(pt: TPoint; out range: IUIAutomationTextRange): HRESULT; stdcall;
    function RangeFromChild(const child: IUIAutomationElement; out range: IUIAutomationTextRange): HRESULT; stdcall;
    function GetSelection(out ranges: IUIAutomationTextRangeArray): HRESULT; stdcall;
    function GetVisibleRanges(out ranges: IUIAutomationTextRangeArray): HRESULT; stdcall;
    function GetDocumentRange(out range: IUIAutomationTextRange): HRESULT; stdcall;
    function GetSupportedTextSelection(out supported: Integer): HRESULT; stdcall;
  end;

  { IUIAutomationTextPattern2 - the Windows 8 addition that knows where the
    caret is without reading (or disturbing) the selection. }
  IUIAutomationTextPattern2 = interface(IUIAutomationTextPattern)
    ['{506A921A-FCC9-409F-B23B-37EB74106872}']
    function RangeFromAnnotation(const annotation: IUIAutomationElement; out range: IUIAutomationTextRange): HRESULT; stdcall;
    function GetCaretRange(out isActive: BOOL; out range: IUIAutomationTextRange): HRESULT; stdcall;
  end;

  { Which Text pattern the cached element answered: the Windows 8 caret one
    (TextPattern2, preferred), the older selection one, or none (the control
    exposes no text to UI Automation - asking it again will not change that). }
  TUiaPatternKind = (pkNone, pkText, pkText2);

  { Reads the text in front of the caret through UI Automation. One instance is
    kept alive by the caller for the process lifetime, so the COM object, the
    apartment AND the element of the focused control survive and only the first
    read of a session can be slow. }
  TUiaTextReader = class
  private
    FInstance:       IUIAutomation;
    FComInitialized: Boolean; // this class called CoInitializeEx and must undo it
    FTried:          Boolean; // an attempt was made; a failure stays cached
    FLastError:      string;
    FAttempts:       Integer; // COM startup attempts
    FReadings:       Integer;
    FProbes:         Integer;

    { ---- the cached element ------------------------------------------------
      Keyed by the focused control: the same hwnd, younger than
      UIA_ELEMENT_TTL_MS, and nothing has to be fetched to read again. The
      verdicts below belong to that element and go when it goes. }
    FElement:    IUIAutomationElement;
    FElementHwnd: HWND;      // the focused control the cached element is for
    FElementPid: DWORD;      // ... its process, for the per-application budget
    FElementTick: Cardinal;  // when it was fetched (GetTickCount)
    FElementHits: Integer;   // reads answered from the cache
    FPattern:    IUIAutomationTextPattern;  // resolved once per element
    FPattern2:   IUIAutomationTextPattern2; // when the host has the caret pattern
    FPatternKind: TUiaPatternKind;
    FReadable:      Boolean; // the password verdict, cached with the element
    FReadableChecked: Boolean;

    { The two pattern queries of the CURRENT element, and a one-line description
      of what that element is. Kept for the debug trace: "no Text pattern" says
      nothing about WHICH control refused, and the shipped reader has to be able
      to answer that from a log. }
    FPatternHr:  HRESULT;
    FPattern2Hr: HRESULT;

    { Where the range walk stopped, for the same reason: a host that exposes the
      pattern and then refuses a step is a different report from a host with no
      pattern at all. Built only on the path that has already decided it has no
      reading, and folded into LastError. }
    FRangeTrace: string;

    FElementInfo:     string;
    FElementInfoDone: Boolean;

    { ---- the budget ------------------------------------------------------- }
    FLastProbe:  Cardinal; // GetTickCount of the last probe
    FFailRun:    Integer;  // consecutive probes that came back with nothing
    FQuietPid:   DWORD;    // a process left alone for a while ...
    FQuietHwnd:  HWND;     // ... for ONE control of it ...
    FQuietUntil: Cardinal; // ... until this tick
    FThrottled:  Integer;  // probes the interval declined
    FQuietSkips: Integer;  // probes the quiet period declined

    { NOT named Instance: a class field or method called Instance collides with
      the compiler-generated class-instance pointer. }
    function Automation: IUIAutomation;
    function GetAvailable: Boolean;
    function GetHasElement: Boolean;
    function FocusWindow: HWND;
    function ProcessOf(const AHwnd: HWND): DWORD;
    function FocusedElement(out AHwnd: HWND; out APid: DWORD): IUIAutomationElement;
    function ResolvePattern: Boolean;
    function ReadViaCaretRange(const AMaxChars: Integer; out ATail: string): Boolean;
    function ReadViaSelection(const AMaxChars: Integer; out ATail: string): Boolean;
    function TextBefore(const ASpan: IUIAutomationTextRange; const AMaxChars: Integer; out ATail: string): Boolean;
    function ReadFromElement(const AMaxChars: Integer; out ATail: string): Boolean;
    function ElementReadable(const AElement: IUIAutomationElement): Boolean;
    function GetElementInfo: string;
    procedure DropElement;
    procedure Quiet(const AWhy: string);
    procedure Fail(const AWhy: string);
  public
    constructor Create;
    destructor Destroy; override;

    { The text immediately in front of the caret, at most AMaxChars characters.
      '' means "no reading": every caller must read that as the pre-feature
      behaviour, never as a width. }
    function ReadBeforeCaret(const AMaxChars: Integer): string;

    property Available: Boolean read GetAvailable;
    property HasElement: Boolean read GetHasElement; // the element is cached right now
    property LastError: string read FLastError;
    property Attempts: Integer read FAttempts;
    property Probes: Integer read FProbes;
    property Readings: Integer read FReadings;
    property ElementHits: Integer read FElementHits;
    property Throttled: Integer read FThrottled;
    property QuietSkips: Integer read FQuietSkips;

    { What the cached element actually is - its class, window handle and control
      type, plus what the two Text-pattern queries answered. Asked of UI
      Automation the first time it is read and then cached with the element, so
      the shipped press path pays nothing for it; the debug trace and the
      self-test print it. }
    property ElementInfo: string read GetElementInfo;

    { Drops the cached COM object (shutdown, or a test that wants a cold start). }
    procedure Reset;
  end;

implementation

uses
  System.SysUtils,
  System.Variants,
  Winapi.ActiveX; // CoInitializeEx, CoCreateInstance, CoUninitialize, CLSCTX_*

const
  { CLSID_CUIAutomation8 - the coclass CUIAutomation8 in uiautomationclient.h,
    GUID E22AD333-B25F-460C-83D0-0581107395C9 - and NOT the older coclass
    CUIAutomation, GUID FF48DBA4-60EF-4201-AA87-54103EEF594E:
    measured on this machine with both, against the same controls, through the
    classic client a plain Win32 EDIT answers
    UIA_IsTextPatternAvailablePropertyId = 0 and hands back NO Text pattern at
    all, while through CUIAutomation8 the same control answers with the caret
    pattern (TextPattern2) and can be read. CUIAutomation8 is the client for
    Windows 8 and later and is what the feature needs to reach a plain Edit. }
  CLSID_CUIAutomation_: TGUID = '{E22AD333-B25F-460C-83D0-0581107395C9}';
  IID_IUIAutomation_:   TGUID = '{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}';
  IID_IUIAutomationTextPattern_:  TGUID = '{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}';
  IID_IUIAutomationTextPattern2_: TGUID = '{506A921A-FCC9-409F-B23B-37EB74106872}';

  { uiautomationclient.idl: pattern and property identifiers. }
  UIA_TextPatternId_        = 10014;
  UIA_TextPattern2Id_       = 10024;
  UIA_ControlTypePropertyId_           = 30003;
  UIA_ClassNamePropertyId_             = 30012;
  UIA_IsPasswordPropertyId_            = 30019;
  UIA_NativeWindowHandlePropertyId_    = 30020;
  UIA_IsTextPatternAvailablePropertyId_ = 30040;

  { uiautomationcore.h: TextUnit and TextPatternRangeEndpoint. }
  TextUnit_Character_             = 0;
  TextPatternRangeEndpoint_Start_ = 0;
  TextPatternRangeEndpoint_End_   = 1;

  { The apartment this unit asks for. UI Automation clients work from either, and
    MTA is what a client that is not driving a window asks for.

    On the SHIPPED path this call normally changes nothing: the VCL initializes
    the main thread as STA long before the reader exists, so CoInitializeEx
    answers RPC_E_CHANGED_MODE ($80010106 - measured, not assumed) and the reader
    proceeds as the STA client the application already is. The apartment is only
    ever taken over when this class is the FIRST to initialize the thread, and
    only then is it undone again in Reset. Both outcomes are handled as normal. }
  UIA_COM_MODEL = COINIT_MULTITHREADED;

  { ---- the budget --------------------------------------------------------- }
  { How long the element of ONE control may be reused before it is fetched
    again: a control that replaced its document (Word opening a file) must not
    keep an old element in place forever. }
  UIA_ELEMENT_TTL_MS: Cardinal = 2000;
  { At most one probe per this interval. Faster than a person types, and slow
    enough that a caret which blinks, a scroll or an animation - all of which
    raise location events - cannot become a stream of cross-process calls. }
  UIA_PROBE_INTERVAL_MS: Cardinal = 60;
  { A process whose element answered nothing is left alone for this long. }
  UIA_QUIET_MS: Cardinal = 4000;
  { ... but only after this many empty reads in a row: a single failure can be a
    caret that is not active yet, rather than a host without text. }
  UIA_FAILS_BEFORE_QUIET = 3;

{ HRESULT = "not a failure". Written locally instead of the RTL's Succeeded()
  because this file sits in the scope of two RTL units that both export such a
  helper (Winapi.Windows and Winapi.ActiveX), and a silent pick between two
  identical-looking declarations is not worth the risk. }
function UiaOk(const AResult: HRESULT): Boolean;
begin
  Result := AResult >= 0;
end;

{ A pattern object arrives as one OWNED reference in a raw pointer - that is the
  SDK's signature for GetCurrentPatternAs. The cast hands that reference to an
  interface variable (which takes its own) and the raw pointer's reference is
  released here, so the object is owned exactly once. }
function PatternFrom(const APointer: Pointer): IUnknown;
begin
  Result := IUnknown(APointer);
  IUnknown(APointer)._Release;
end;

{ ----------------------------------------------------------------------------- }
{ COM lifetime                                                                  }
{ ----------------------------------------------------------------------------- }

constructor TUiaTextReader.Create;
begin
  inherited Create;
  FInstance := nil;
  FComInitialized := False;
  FTried := False;
  FLastError := '';
  FAttempts := 0;
  FReadings := 0;
  FProbes := 0;
  FElement := nil;
  FElementHwnd := 0;
  FElementPid := 0;
  FElementTick := 0;
  FElementHits := 0;
  FPattern := nil;
  FPattern2 := nil;
  FPatternKind := pkNone;
  FPatternHr := 0;
  FPattern2Hr := 0;
  FRangeTrace := '';
  FElementInfo := '';
  FElementInfoDone := False;
  FReadable := False;
  FReadableChecked := False;
  FLastProbe := 0;
  FFailRun := 0;
  FQuietPid := 0;
  FQuietUntil := 0;
  FThrottled := 0;
  FQuietSkips := 0;
end;

destructor TUiaTextReader.Destroy;
begin
  Reset;
  inherited Destroy;
end;

{ Drops the cached element, its pattern and its verdicts. Releasing a COM
  reference is a call into the object (and, across apartments, into COM itself),
  which is the other reason this reader only ever runs on the main thread:
  nothing in this unit is reachable from a keyboard or mouse hook. }
procedure TUiaTextReader.DropElement;
begin
  FPattern2 := nil;
  FPattern := nil;
  FPatternKind := pkNone;
  FReadable := False;
  FReadableChecked := False;
  FPatternHr := 0;
  FPattern2Hr := 0;
  FRangeTrace := '';
  FElementInfo := '';
  FElementInfoDone := False;
  FElement := nil;
  FElementHwnd := 0;
  FElementPid := 0;
  FElementTick := 0;
end;

procedure TUiaTextReader.Reset;
begin
  DropElement;
  FInstance := nil;
  { The apartment is closed only when THIS class opened it: COM the application
    initialized itself must still be usable after the reader is released. }
  if FComInitialized then
  begin
    CoUninitialize;
    FComInitialized := False;
  end;
  FTried := False;
  FLastProbe := 0;
  FFailRun := 0;
  FQuietPid := 0;
  FQuietHwnd := 0;
  FQuietUntil := 0;
end;

procedure TUiaTextReader.Fail(const AWhy: string);
begin
  FLastError := AWhy;
end;

{ Leaves the control behind the cached element alone for UIA_QUIET_MS: it has
  no text to offer (or is a password field), and asking again on the next
  keystroke would pay a cross-process call for an answer that cannot change yet.
  Only ever DECLINES a read - the empty answer every caller already handles.

  Keyed by the CONTROL, not by its process alone: a password field says nothing
  about the next control the user tabs into, and one application with several
  panes (an editor and its find box, Excel and its formula bar) is the normal
  case. The element cache above is keyed on the same hwnd, so a kept verdict and
  this quiet period always describe the same control. }
procedure TUiaTextReader.Quiet(const AWhy: string);
begin
  if (FElementPid = 0) and (FElementHwnd = 0) then
    Exit;
  FQuietPid := FElementPid;
  FQuietHwnd := FElementHwnd;
  FQuietUntil := GetTickCount + UIA_QUIET_MS;
  Fail('quiet (' + AWhy + ')');
end;

function TUiaTextReader.GetAvailable: Boolean;
begin
  Result := FInstance <> nil;
end;

function TUiaTextReader.GetHasElement: Boolean;
begin
  Result := FElement <> nil;
end;

function TUiaTextReader.Automation: IUIAutomation;
var
  HR:  HRESULT;
  Obj: IUnknown;
begin
  Result := FInstance;
  if Result <> nil then
    Exit;
  if FTried then
    Exit; // one failed attempt is cached; a key press must not pay for it again

  FTried := True;
  Inc(FAttempts);

  HR := CoInitializeEx(nil, UIA_COM_MODEL);
  if HR = S_OK then
    FComInitialized := True
  else if HR = S_FALSE then
    { COM was already initialized on this thread with the same model - nothing
      of ours to undo }
  else if HR = RPC_E_CHANGED_MODE then
    { initialized with another model, which is the application's decision; UI
      Automation clients work from either apartment }
  else
  begin
    Fail(Format('CoInitializeEx failed ($%.8x)', [HR]));
    Exit;
  end;

  Obj := nil;
  HR := CoCreateInstance(CLSID_CUIAutomation_, nil, CLSCTX_INPROC_SERVER, IID_IUIAutomation_, Obj);
  if (not UiaOk(HR)) or (Obj = nil) then
  begin
    Fail(Format('CoCreateInstance(CLSID_CUIAutomation) failed ($%.8x)', [HR]));
    Exit;
  end;

  FInstance := IUIAutomation(Obj);
  Result := FInstance;
end;

function TUiaTextReader.ProcessOf(const AHwnd: HWND): DWORD;
var
  Pid: DWORD;
begin
  Result := 0;
  if AHwnd = 0 then
    Exit;
  Pid := 0;
  GetWindowThreadProcessId(AHwnd, Pid);
  Result := Pid;
end;

{ The control with keyboard focus, from ONE local API call: no cross-process
  message, no wait, nothing a hook could not afford. 0 when the calling thread
  has no focus window of its own. }
function TUiaTextReader.FocusWindow: HWND;
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
      Result := GTI.hwndActive; // some hosts keep the focus on the document child
  end;
end;

{ The element of the focused control - from the cache whenever it still
  describes that control (the same focused hwnd, younger than
  UIA_ELEMENT_TTL_MS), and only otherwise from UI Automation. AHwnd and APid
  come back as what the CACHE was keyed on, so the caller can answer "is this
  application quiet?" and "is this the same control as last time?" without a
  single extra window call. }
function TUiaTextReader.FocusedElement(out AHwnd: HWND; out APid: DWORD): IUIAutomationElement;
var
  Auto: IUIAutomation;
  Hw:   HWND;
  Now:  Cardinal;
begin
  Result := nil;
  AHwnd := 0;
  APid := 0;

  Hw := FocusWindow;
  Now := GetTickCount;

  if (FElement <> nil) and (Hw <> 0) and (Hw = FElementHwnd) and (Now - FElementTick < UIA_ELEMENT_TTL_MS) then
  begin
    Inc(FElementHits);
    AHwnd := FElementHwnd;
    APid := FElementPid;
    Result := FElement;
    Exit;
  end;

  Auto := Automation;
  if Auto = nil then
    Exit;

  { The element with keyboard focus is the control whose text is wanted. }
  if not (UiaOk(Auto.GetFocusedElement(Result)) and (Result <> nil)) then
  begin
    { No focused element (some hosts expose none): ask the focused WINDOW and let
      that element answer for itself - RichEdit hosts and the browsers report the
      document here. }
    Result := nil;
    if (Hw <> 0) and not UiaOk(Auto.ElementFromHandle(Hw, Result)) then
      Result := nil;
  end;

  { A new element: the pattern and the verdicts of the old one describe another
    control now and must not survive it. }
  DropElement;
  FFailRun := 0; // a new control starts with a clean run of empty reads

  if Result = nil then
    Exit;

  FElement := Result;
  FElementHwnd := Hw;
  FElementPid := ProcessOf(Hw);
  FElementTick := Now;
  AHwnd := FElementHwnd;
  APid := FElementPid;
end;

{ A password field is never read. The characters in front of the caret would be
  a secret, and this reader has no business seeing one - a missing reading is a
  normal answer everywhere in this unit. The verdict is cached WITH the element:
  whether a control is a password field cannot change while it is the same
  control, and the property is a cross-process call. }
function TUiaTextReader.ElementReadable(const AElement: IUIAutomationElement): Boolean;
var
  Value: OleVariant;
begin
  if (AElement <> nil) and (AElement = FElement) and FReadableChecked then
  begin
    Result := FReadable;
    Exit;
  end;

  Result := False;
  if AElement = nil then
    Exit;

  Result := True;
  Value := Null;
  if UiaOk(AElement.GetCurrentPropertyValue(UIA_IsPasswordPropertyId_, Value)) then
    if (not VarIsNull(Value)) and (not VarIsEmpty(Value)) and VarIsType(Value, varBoolean) then
      if Value = True then
        Result := False;

  if AElement = FElement then
  begin
    FReadable := Result;
    FReadableChecked := True;
  end;
end;

{ The Text pattern of the cached element, resolved once and then kept: which
  pattern a control exposes cannot change while it is the same control, and
  resolving it is a cross-process call. TextPattern2 is asked for first - it
  knows where the caret is without reading (or disturbing) the selection; a host
  with the older pattern only is served from the selection instead. False = this
  control exposes no text to UI Automation at all.

  Only GetCurrentPatternAs is used. The two other ways into the same pattern -
  GetCurrentPattern (untyped) and GetCachedPatternAs (through a cache request) -
  were both measured against the controls this unit reads (a Win32 Edit, a
  RICHEDIT50W in this test's own child process, and WordPad's RICHEDIT50W): the
  typed call answers S_OK with the object in every case, the untyped one answers
  S_OK with NO object, and the cache route never has anything extra to add. A
  fallback that never runs is a second failure mode with no benefit, so there is
  none here. }
function TUiaTextReader.ResolvePattern: Boolean;
var
  Raw: Pointer;
begin
  if FPatternKind <> pkNone then
  begin
    Result := True;
    Exit;
  end;

  Result := False;
  if FElement = nil then
    Exit;

  Raw := nil;
  FPattern2Hr := FElement.GetCurrentPatternAs(UIA_TextPattern2Id_, IID_IUIAutomationTextPattern2_, Raw);
  if UiaOk(FPattern2Hr) and (Raw <> nil) then
  begin
    FPattern2 := IUIAutomationTextPattern2(PatternFrom(Raw));
    if FPattern2 <> nil then
    begin
      FPattern := FPattern2; // the same object answers the older pattern too
      FPatternKind := pkText2;
      Result := True;
      Exit;
    end;
  end;

  Raw := nil;
  FPatternHr := FElement.GetCurrentPatternAs(UIA_TextPatternId_, IID_IUIAutomationTextPattern_, Raw);
  if UiaOk(FPatternHr) and (Raw <> nil) then
  begin
    FPattern := IUIAutomationTextPattern(PatternFrom(Raw));
    if FPattern <> nil then
      FPatternKind := pkText;
  end;

  Result := FPatternKind <> pkNone;
end;

{ A one-line description of the element a read is about: WHICH control answered,
  and what its two Text-pattern queries said.

  A verdict of "no Text pattern" is only useful if it names the control it was
  reached on, and a host that puts its text somewhere other than the element it
  reports as focused is exactly what this shows. Asked once per element and
  cached with it (a handful of cross-process property reads, on the path that has
  already decided it has no reading), so the shipped press path never pays for
  it - only the debug trace and the self-test read it. }
function TUiaTextReader.GetElementInfo: string;
var
  Value:     OleVariant;
  ClassName: string;
  Handle:    Cardinal;
  Control:   Integer;
  Available: Integer;
begin
  if FElement = nil then
    Exit('(no element)');
  if FElementInfoDone then
    Exit(FElementInfo);

  FElementInfoDone := True;

  ClassName := '?';
  Value := Null;
  if UiaOk(FElement.GetCurrentPropertyValue(UIA_ClassNamePropertyId_, Value)) and (not VarIsNull(Value)) and
    (not VarIsEmpty(Value)) then
    ClassName := VarToStr(Value);

  Handle := 0;
  Value := Null;
  if UiaOk(FElement.GetCurrentPropertyValue(UIA_NativeWindowHandlePropertyId_, Value)) and VarIsType(Value, varInteger) then
    Handle := Cardinal(Integer(Value));

  Control := -1;
  Value := Null;
  if UiaOk(FElement.GetCurrentPropertyValue(UIA_ControlTypePropertyId_, Value)) and VarIsType(Value, varInteger) then
    Control := Integer(Value);

  Available := -1;
  Value := Null;
  if UiaOk(FElement.GetCurrentPropertyValue(UIA_IsTextPatternAvailablePropertyId_, Value)) and VarIsType(Value, varBoolean) then
    Available := Ord(Value = True);

  FElementInfo := Format('element class=[%s] hwnd=%x controlType=%d textPatternAvailable=%d; ' +
    'GetCurrentPatternAs: TextPattern2=$%.8x TextPattern=$%.8x; kind=%d; ranges[%s]',
    [ClassName, Handle, Control, Available, Cardinal(FPattern2Hr), Cardinal(FPatternHr), Ord(FPatternKind), FRangeTrace]);
  Result := FElementInfo;
end;

{ ----------------------------------------------------------------------------- }
{ the reading                                                                   }
{ ----------------------------------------------------------------------------- }

{ The text in front of the caret, taken from a range that already sits at the
  caret: a clone has its START endpoint moved back AMaxChars characters, and
  only what the move actually covered is read. False = nothing in front of the
  caret (start of the document) or the host refused the move. }
function TUiaTextReader.TextBefore(const ASpan: IUIAutomationTextRange; const AMaxChars: Integer; out ATail: string): Boolean;
var
  Span:  IUIAutomationTextRange;
  Moved: Integer;
  Text:  WideString;
  Hr:    HRESULT;
begin
  Result := False;
  ATail := '';
  if ASpan = nil then
    Exit;

  Span := nil;
  Hr := ASpan.Clone(Span);
  if (not UiaOk(Hr)) or (Span = nil) then
  begin
    FRangeTrace := FRangeTrace + Format('; clone=$%.8x', [Cardinal(Hr)]);
    Exit;
  end;

  { MoveEndpointByUnit reports how many units the endpoint ACTUALLY moved, and it
    reports them SIGNED: moving the start endpoint back three characters answers
    -3, not 3 (measured, not assumed: the live probe prints `moved=-3`). A
    `Moved <= 0` test therefore read every backward move as "the caret is at the
    beginning of the document" and this layer never returned a reading on any
    host that does offer a Text pattern. Only 0 means "nothing in front of the
    caret"; the magnitude is what the range now spans and what GetText reads. }
  Moved := 0;
  if not UiaOk(Span.MoveEndpointByUnit(TextPatternRangeEndpoint_Start_, TextUnit_Character_, -AMaxChars, Moved)) then
    Exit;
  if Moved = 0 then
    Exit; // the caret really is at the beginning of the document

  Text := '';
  if not UiaOk(Span.GetText(Abs(Moved), Text)) then
    Exit;

  ATail := Text;
  Result := ATail <> '';
end;

{ Layer B's preferred path (Windows 8+): TextPattern2 knows the caret without
  reading or changing the selection. }
function TUiaTextReader.ReadViaCaretRange(const AMaxChars: Integer; out ATail: string): Boolean;
var
  Active:  BOOL;
  Caret:   IUIAutomationTextRange;
  HrCaret: HRESULT;
begin
  Result := False;
  ATail := '';
  if FPattern2 = nil then
    Exit;

  Active := False;
  Caret := nil;
  HrCaret := FPattern2.GetCaretRange(Active, Caret);
  FRangeTrace := Format('caret=$%.8x active=%s range=%s', [Cardinal(HrCaret), BoolToStr(Active, True), BoolToStr(Caret <> nil, True)]);
  if not UiaOk(HrCaret) then
    Exit;
  if (not Active) or (Caret = nil) then
    Exit; // the control has no active caret: not a place to erase

  Result := TextBefore(Caret, AMaxChars, ATail);
end;

{ The older path (Windows 7 pattern): the selection IS the caret position while
  nothing is selected. An active selection is deliberately NOT read - the press
  would delete the selection first, and erasing a cluster behind it on top of
  that is exactly the over-delete this feature must never cause. }
function TUiaTextReader.ReadViaSelection(const AMaxChars: Integer; out ATail: string): Boolean;
var
  Ranges: IUIAutomationTextRangeArray;
  Count:  Integer;
  Sel:    IUIAutomationTextRange;
  Comp:   Integer;
  Hr:     HRESULT;
begin
  Result := False;
  ATail := '';
  if FPattern = nil then
    Exit;

  Ranges := nil;
  Hr := FPattern.GetSelection(Ranges);
  FRangeTrace := FRangeTrace + Format('; sel=$%.8x ranges=%s', [Cardinal(Hr), BoolToStr(Ranges <> nil, True)]);
  if (not UiaOk(Hr)) or (Ranges = nil) then
    Exit;

  Count := 0;
  if (not UiaOk(Ranges.GetLength(Count))) or (Count < 1) then
    Exit;

  Sel := nil;
  if (not UiaOk(Ranges.GetElement(0, Sel))) or (Sel = nil) then
    Exit;

  Comp := 0;
  if not UiaOk(Sel.CompareEndpoints(TextPatternRangeEndpoint_Start_, Sel, TextPatternRangeEndpoint_End_, Comp)) then
    Exit;
  if Comp <> 0 then
    Exit; // an active selection: the caret is not the only thing a press acts on

  Result := TextBefore(Sel, AMaxChars, ATail);
end;

{ The reading itself, from the CACHED element: its verdicts are already in the
  cache, so this is a password check (cached), a pattern resolution (cached) and
  the range walks. }
function TUiaTextReader.ReadFromElement(const AMaxChars: Integer; out ATail: string): Boolean;
begin
  ATail := '';
  Result := False;
  FRangeTrace := '';

  if not ElementReadable(FElement) then
  begin
    Quiet('the control is a password field');
    Exit;
  end;

  if not ResolvePattern then
  begin
    { Not a transient failure: this host has no text for UI Automation, so its
      process is left alone instead of being asked once per keystroke. }
    Quiet('the control exposes no Text pattern: ' + GetElementInfo);
    Exit;
  end;

  if (FPatternKind = pkText2) and ReadViaCaretRange(AMaxChars, ATail) then
  begin
    Result := True;
    Exit;
  end;

  if ReadViaSelection(AMaxChars, ATail) then
  begin
    Result := True;
    Exit;
  end;

  ATail := '';
  { The pattern was there and the walk still produced nothing: record where it
    stopped, so a debug trace can tell "the caret really is at the start of the
    document" from "this host refused the first step". }
  Fail('no range: ' + FRangeTrace);
  Result := False;
end;

function TUiaTextReader.ReadBeforeCaret(const AMaxChars: Integer): string;
var
  Element: IUIAutomationElement;
  Hw:      HWND;
  Pid:     DWORD;
  Now:     Cardinal;
begin
  Result := '';
  if AMaxChars <= 0 then
    Exit;

  Now := GetTickCount;

  { ---- the budget, before any COM call ------------------------------------ }
  if (FLastProbe <> 0) and (Now - FLastProbe < UIA_PROBE_INTERVAL_MS) then
  begin
    Inc(FThrottled);
    Exit;
  end;

  { A reading layer must never take the engine down: anything unexpected here is
    answered with "no reading", which leaves the press exactly as it was before
    this feature existed. }
  try
    Hw := FocusWindow;
    Pid := ProcessOf(Hw);
    if (Hw <> 0) and (Pid = FQuietPid) and (Hw = FQuietHwnd) and (Now < FQuietUntil) then
    begin
      Inc(FQuietSkips);
      Exit; // this control answered nothing a moment ago
    end;

    FLastProbe := Now;
    Inc(FProbes);

    Element := FocusedElement(Hw, Pid);
    if Element = nil then
      Exit; // no focused control, or no element for it

    if ReadFromElement(AMaxChars, Result) then
    begin
      Inc(FReadings);
      FFailRun := 0;
      FQuietPid := 0; // the control answered: it is not quiet any more
      FQuietHwnd := 0;
    end
    else
    begin
      Result := '';
      Inc(FFailRun);
      { Not every empty read is structural (the caret may simply be inactive),
        so a process is left alone only after a few of them in a row. }
      if (Pid <> 0) and (FFailRun >= UIA_FAILS_BEFORE_QUIET) then
        Quiet('no reading in a row');
    end;
  except
    on E: Exception do
    begin
      Fail(E.ClassName + ': ' + E.Message);
      Result := '';
    end;
  end;
end;

end.
