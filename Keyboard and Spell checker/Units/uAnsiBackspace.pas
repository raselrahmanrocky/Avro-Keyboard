{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAnsiBackspace;

{ =============================================================================
  uAnsiBackspace - one press, one visible character, even for text the ledger
  does not describe.

  The engines erase text they typed themselves from their committed-text ledger.
  When the caret sits behind text they did NOT type, the press falls back to the
  host's native backspace, which removes exactly one character - and one Bangla
  letter of an ANSI mapping is often several characters. This unit is the
  decision point for that case:

    1. kill switch      - uRegistrySettings.AnsiSmartBackspace (plus the key it
                          replaced, AnsiBackspaceHostErase). Off means the
                          press behaves exactly as it did before this feature,
                          and - since 26f1507's follow-up - that no reading is
                          taken either: the timer does nothing at all.
    2. a reading        - uCaretContextCache's cached text before the caret,
                          filled by uCaretWatch outside every hook: the
                          message path first (uCaretContextSniffer), then UI
                          Automation (uUIAText), then the clipboard.
    3. the width        - clsUnicodeToBijoy2000.AnsiTailClusterUnits, i.e. the
                          active mapping's own compiled glyph table, so the
                          answer is right for every mapping, not just the four
                          shipped ones.
    4. verify           - the reading is re-checked against the caret right
                          before anything is erased.
    5. the cap          - AnsiBackspaceMaxUnits. A width above it is not erased;
                          the press falls back (never over-delete).

  Every step answers "no" by default. The unit erases nothing itself: it returns
  the width and the caller emits it through the engine's OWN atomic batch
  (RawSend / EmitBatch), so there is still exactly one emission path per engine.

  The decision is observable without a host through AnsiBackspaceSetTrace, which
  a harness uses to read the units and the reason for every press.
  ============================================================================= }

interface

type
  { Why a press was answered the way it was. Kept as an enum (not a string) so a
    harness can assert on the reason and the log stays out of the hot path. }
  TAnsiEraseDecision = (
    edNotMine,   // no reading, or the feature is off: the host keeps the press
    edOneUnit,   // the reading is one unit wide: the host does it, as before
    edCluster,   // a multi-unit cluster: erase it with our own emission
    edCapped,    // wider than AnsiBackspaceMaxUnits: fall back
    edStale,     // the caret moved / the reading cannot be trusted: fall back
    edUnknown,   // no glyph table for the active mapping: fall back
    edAppBlocked // the active application is excluded by AnsiBackspaceApps
    );

  { The engine's own emission: erase AEraseCount units and type AText. Every
    engine already has this method (RawSend). }
  TAnsiEmitProc = procedure(const EraseCount: Integer; const Text: string) of object;

  TAnsiBackspaceTraceProc = procedure(const AMapping: string; const AUnits: Integer;
    const ADecision: TAnsiEraseDecision; const AReason: string) of object;

{ ---- configuration (read from the registry settings by the callers) -------- }

{ The master answer: is the host-text erase on at all? Two keys decide, and both
  follow the "an empty string is the documented default" rule:

    * AnsiSmartBackspace     - the user-facing master switch;
    * AnsiBackspaceHostErase - the key it replaced, kept because it is what older
      builds, the harnesses and the Options dialog write, and because its name
      still says something true (host-side erase permitted).

  An empty value means YES for either of them, so a caller that only ever set the
  old key - every harness case written before the master switch existed - keeps
  the feature ON instead of switching it off by accident. }
function AnsiBackspaceEnabled: Boolean;
function AnsiBackspaceMaxUnits: Integer;
procedure AnsiBackspaceConfigureForTest(const AEnabled: Boolean; const AMaxUnits: Integer);
procedure AnsiBackspaceSetTrace(const AProc: TAnsiBackspaceTraceProc);

{ ---- the decision ---------------------------------------------------------- }

{ How many units one press has to erase for the host text in front of the caret,
  and why. Pure: reads the sniffer's cache and the mapping's glyph table, calls
  nothing on the host, erases nothing. }
function AnsiHostClusterUnits(out AUnits: Integer; out ADecision: TAnsiEraseDecision;
  out AReason: string): Boolean;

{ The host-text path, as the engines call it: when this returns True the press
  was handled here (the caller blocks the host's own backspace). It has already
  emitted through AEmit with the engine's own single atomic batch.

  Returns False - and emits nothing - when the feature is off, there is no usable
  reading, the caret moved, the mapping does not know the glyph, the press is a
  single unit (the host does it exactly as before), or the width is above the
  cap. }
function AnsiEraseHostCluster(const AEmit: TAnsiEmitProc): Boolean;

{ Drops the cached reading of the text in front of the caret. Called when the
  document under the reading changed without an event this process saw (a
  layout / mode switch, a foreground change noticed by the timer): the next
  press reads again instead of trusting a description that may be obsolete. }
procedure AnsiBackspaceInvalidate;

{ ---- per-application override ---------------------------------------------- }

{ The pure half of the per-app gate: does AAppList - a ';' separated list of
  'class-name=value' pairs, e.g. 'Chrome_WidgetWin_1=off;wordpad=off' - allow
  erasing host text in a window whose focused control class is AFocusClass and
  whose foreground window class is AForegroundClass?

  No list, or no matching entry: True, so an installation that never touches the
  setting behaves exactly like the default. Matching is case-insensitive and a
  partial class name matches; the LAST matching entry wins; a value that is not
  on / yes / 1 / all / default counts as OFF, so a typo can never make the eraser
  more aggressive than the setting says. }
function AnsiAppAllowsHostErase(const AAppList, AFocusClass, AForegroundClass: string): Boolean;

{ The same question for the host the last reading saw: the setting plus the
  class names the watch cached on the main thread. O(1), hook-safe. }
function AnsiHostEraseAllowed: Boolean;

function AnsiDecisionName(const ADecision: TAnsiEraseDecision): string;

implementation

uses
  System.SysUtils,
  uRegistrySettings,
  uCaretContextCache,
  clsUnicodeToBijoy2000;

const
  { The cap is a safety bound, not a policy: a reading that claims more units
    than this is not believed. clsAnsiAtomMap.MAX_ATOM_UNITS bounds a single
    glyph far below it, so the cap only fires on a corrupt reading. }
  DEFAULT_MAX_UNITS = 8;
  HARD_MAX_UNITS    = 64;

var
  FEnabled:  Boolean;
  FMaxUnits: Integer;
  FTrace:    TAnsiBackspaceTraceProc;
  FOverride: Boolean; // a test configured the unit directly

function AnsiBackspaceEnabled: Boolean;

  { '' is not "off": it is a key that was never written, and its documented
    default is YES. }
  function SettingOn(const AValue: string): Boolean;
  begin
    Result := (AValue = '') or (AValue = 'YES');
  end;

begin
  if FOverride then
    Result := FEnabled
  else
    Result := SettingOn(AnsiSmartBackspace) and SettingOn(AnsiBackspaceHostErase);
end;

function AnsiBackspaceMaxUnits: Integer;
var
  N: Integer;
begin
  if FOverride then
  begin
    Result := FMaxUnits;
    Exit;
  end;

  N := StrToIntDef(AnsiBackspaceUnitCap, DEFAULT_MAX_UNITS);
  if (N < 1) or (N > HARD_MAX_UNITS) then
    N := DEFAULT_MAX_UNITS;
  Result := N;
end;

procedure AnsiBackspaceConfigureForTest(const AEnabled: Boolean; const AMaxUnits: Integer);
begin
  FOverride := True;
  FEnabled := AEnabled;
  FMaxUnits := AMaxUnits;
end;

procedure AnsiBackspaceSetTrace(const AProc: TAnsiBackspaceTraceProc);
begin
  FTrace := AProc;
end;

function AnsiDecisionName(const ADecision: TAnsiEraseDecision): string;
begin
  case ADecision of
    edNotMine:
      Result := 'not ours';
    edOneUnit:
      Result := 'one unit';
    edCluster:
      Result := 'cluster';
    edCapped:
      Result := 'above the cap';
    edStale:
      Result := 'stale reading';
    edUnknown:
      Result := 'unknown glyph';
    edAppBlocked:
      Result := 'this application is excluded';
  else
    Result := '?';
  end;
end;

procedure AnsiBackspaceInvalidate;
begin
  AnsiCaretContextDrop('the document changed under the reading');
end;

{ One class name against one pattern: case-insensitive, and a pattern may be a
  fragment ('chrome' matches Chrome_WidgetWin_1). }
function ClassMatches(const APattern, AClass: string): Boolean;
begin
  Result := False;
  if (APattern = '') or (AClass = '') then
    Exit;
  Result := Pos(UpperCase(APattern), UpperCase(AClass)) > 0;
end;

{ The value half of one override entry. Everything that is not an explicit
  "on" counts as off: an unknown word must never widen what may be erased. }
function ValueAllows(const AValue: string): Boolean;
var
  V: string;
begin
  V := UpperCase(Trim(AValue));
  Result := (V = '') or (V = 'ON') or (V = 'YES') or (V = '1') or (V = 'ALL') or (V = 'DEFAULT') or (V = 'CLUSTER');
end;

function AnsiAppAllowsHostErase(const AAppList, AFocusClass, AForegroundClass: string): Boolean;
var
  Token: string;
  Cls:   string;
  Val:   string;
  Eq:    Integer;
  P:     Integer;
begin
  Result := True; // the documented default: not listed means allowed
  if Trim(AAppList) = '' then
    Exit;

  Token := '';
  P := 1;
  while P <= Length(AAppList) + 1 do
  begin
    if (P > Length(AAppList)) or (AAppList[P] = ';') then
    begin
      Token := Trim(Token);
      if Token <> '' then
      begin
        Eq := Pos('=', Token);
        if Eq = 0 then
          Eq := Pos(':', Token);
        if Eq > 0 then
        begin
          Cls := Trim(Copy(Token, 1, Eq - 1));
          Val := Trim(Copy(Token, Eq + 1, MaxInt));
          if ClassMatches(Cls, AFocusClass) or ClassMatches(Cls, AForegroundClass) then
            Result := ValueAllows(Val); // the LAST matching entry wins
        end;
      end;
      Token := '';
    end
    else
      Token := Token + AAppList[P];
    Inc(P);
  end;
end;

function AnsiHostEraseAllowed: Boolean;
begin
  Result := AnsiAppAllowsHostErase(AnsiBackspaceApps, AnsiHostFocusClass, AnsiHostForegroundClass);
end;

function AnsiHostClusterUnits(out AUnits: Integer; out ADecision: TAnsiEraseDecision;
  out AReason: string): Boolean;
var
  Tail:   string;
  MaxU:   Integer;
begin
  AUnits := 1;
  ADecision := edNotMine;
  AReason := 'the feature is off';
  Result := False;

  if not AnsiBackspaceEnabled then
    Exit;

  if not AnsiCaretSnifferEnabled then
  begin
    AReason := 'the caret sniffer is off';
    Exit;
  end;

  { Some hosts do their own cluster deletion or none at all: the per-app
    override can exclude them, and then the press is left to the host exactly
    as it was before this feature. }
  if not AnsiHostEraseAllowed then
  begin
    ADecision := edAppBlocked;
    AReason := 'the active application is listed as host-erase off';
    Exit;
  end;

  if not AnsiCaretContextTail(Tail) then
  begin
    AReason := 'no reading of the text before the caret';
    Exit;
  end;

  { The reading is only usable while the caret still is where it was taken. }
  if not AnsiCaretContextVerify then
  begin
    ADecision := edStale;
    AReason := 'the caret moved since the reading';
    Exit;
  end;

  { A mapping whose table could not be compiled has no width to offer: the
    fail-safe is the host's single character, never a guess. }
  if AnsiAtomMap = nil then
  begin
    ADecision := edUnknown;
    AReason := 'the active mapping has no glyph table';
    Exit;
  end;

  { The mapping's own compiled table decides, never a table baked in here. }
  AUnits := AnsiTailClusterUnits(Tail);

  if AUnits <= 1 then
  begin
    { One unit: the host's native backspace erases exactly that, and blocking it
      would cost a second emission for the same effect. Behaviour unchanged. }
    ADecision := edOneUnit;
    AReason := 'one unit: the host erases it';
    AUnits := 1;
    Exit;
  end;

  MaxU := AnsiBackspaceMaxUnits;
  if AUnits > MaxU then
  begin
    ADecision := edCapped;
    AReason := Format('%d units is above the %d unit cap', [AUnits, MaxU]);
    AUnits := 1;
    Exit;
  end;

  ADecision := edCluster;
  AReason := Format('%d units of one visible character', [AUnits]);
  Result := True;
end;

function AnsiEraseHostCluster(const AEmit: TAnsiEmitProc): Boolean;
var
  Units:    Integer;
  Decision: TAnsiEraseDecision;
  Reason:   string;
  Mapping:  string;
begin
  Units := 1;
  Decision := edNotMine;
  Reason := '';
  Result := False;

  { Cheap first: with the feature off (the default answer on a fresh install of
    a build whose reading layer is not installed yet) nothing below runs, so the
    press path cannot change by accident. }
  if not AnsiBackspaceEnabled then
  begin
    if Assigned(FTrace) then
      FTrace(AnsiVersion, 1, edNotMine, 'the feature is off');
    Exit;
  end;

  if not Assigned(AEmit) then
    Exit;

  Result := AnsiHostClusterUnits(Units, Decision, Reason);
  Mapping := AnsiVersion;

  if Assigned(FTrace) then
    FTrace(Mapping, Units, Decision, Reason);

  if Result then
  begin
    AEmit(Units, '');
    { The reading described the text BEFORE this erase, so it is consumed here:
      the next press reads again instead of erasing the same area twice. O(1),
      no host call - the watch takes the next reading on its own tick. }
    AnsiCaretContextDrop('the tail was erased');
  end;
end;

initialization
  FEnabled := True;
  FMaxUnits := DEFAULT_MAX_UNITS;
  FOverride := False; // the registry settings decide
  FTrace := nil;
end.
