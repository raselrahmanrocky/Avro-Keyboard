{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uThemeManager;

{ Central application theme.

  "Theme" covers two things here, and they must never disagree:

  1. the VCL style (APP_STYLE_LIGHT / APP_STYLE_DARK). The top bar popup
  menus, every dialog and the Customize window are not owner-drawn: their
  dark look comes entirely from the active VCL style. That is why the
  theme setting has to drive the style, not only our own painted surfaces.
  2. the palette (TAppThemePalette) for the hand-painted flyouts that do not
  use VCL controls for their visuals - the ANSI version picker and the
  layout picker draw every row themselves and used to be hardcoded light.

  The stored mode is the source of truth: atmSystemDefault follows Windows
  (AppsUseLightTheme), while atmLight / atmDark force the theme even when
  Windows disagrees.

  The registry is read in ApplyAppTheme only, never from a paint handler: the
  resolved theme is cached here, and the pickers are created fresh on every
  open, so they simply resolve the palette when they are shown. }

interface

uses
  Winapi.Windows, // HWND, RGB()
  System.UITypes; // TColor

type
  TAppThemeMode = (atmSystemDefault, atmLight, atmDark);

  { One palette for every hand-painted surface. The first five colours are the
    documented theme contract (and are asserted literally by kat_engineswitch);
    HoverFill is the row tint the flyouts use and has no system equivalent. }
  TAppThemePalette = record
    IsDark: Boolean;
    Background: TColor;
    Text: TColor;
    SelectionFill: TColor;
    SelectionText: TColor;
    Border: TColor;
    HoverFill: TColor;
  end;

const
  { The two VCL styles Avro_Keyboard.dproj embeds (Custom_Styles). }
  APP_STYLE_LIGHT = 'Windows10';
  APP_STYLE_DARK  = 'Windows10 Dark';

  APP_THEME_SETTING_SYSTEM = 'SYSTEM';
  APP_THEME_SETTING_LIGHT  = 'LIGHT';
  APP_THEME_SETTING_DARK   = 'DARK';

  { Section name of the WM_SETTINGCHANGE broadcast sent after the stored
    AppThemeMode changes. Satellite tools listen for it in their
    TApplicationEvents.OnSettingChange and re-read the store, so an open
    Layout Editor / Skin Designer / Avro Pad restyles live. }
  APP_THEME_BROADCAST_SECTION = 'AvroThemeMode';

  { True when Windows itself uses light application mode. Reads
    HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\
    AppsUseLightTheme (0 = dark); a missing value means light, which is also
    Windows' own default. }
function WindowsAppsUseLightTheme: Boolean;

{ The effective theme for a mode. atmSystemDefault follows
  ASystemUsesLightTheme; the locked modes ignore it. }
function ResolveAppTheme(AMode: TAppThemeMode; ASystemUsesLightTheme: Boolean): TAppThemeMode;

{ Stored setting <-> mode. Empty or unknown values mean atmSystemDefault, so a
  hand-edited registry value or XML file can never leave the app themeless. }
function AppThemeModeFromSetting(const AValue: string): TAppThemeMode;
function AppThemeModeToSetting(AMode: TAppThemeMode): string;

{ The captions of the options dropdown, defined once so the settings UI and any
  other surface cannot drift apart. }
function AppThemeModeCaption(AMode: TAppThemeMode): string;

{ Palette of a RESOLVED theme (atmLight / atmDark); anything else is treated as
  light. }
function GetAppThemePalette(AResolved: TAppThemeMode): TAppThemePalette;

{ The theme currently in force, as cached by ApplyAppTheme. Safe to call from
  paint code: no registry access. }
function CurrentAppThemeMode: TAppThemeMode;
function IsDarkAppTheme: Boolean;
function CurrentPalette: TAppThemePalette;

{ Resolves AMode, applies the VCL style and the window frame, and caches the
  result. This is the single entry point for the application. }
procedure ApplyAppTheme(const AMode: TAppThemeMode);

{ Persisted AppThemeMode ('SYSTEM'/'LIGHT'/'DARK') from the same store the
  main app uses: HKCU\Software\OmicronLab\Avro Keyboard (installed) or
  Settings.xml beside the exe (portable). Missing/garbage => atmSystemDefault.
  Satellite tools (Layout Editor, Skin Designer, Avro Pad) use this so every
  Avro window agrees with the Customize dialog, whatever Windows is doing. }
function StoredAppThemeMode: TAppThemeMode;
procedure ApplyStoredAppTheme;

{ Tells every running Avro process (this one included) that the stored
  AppThemeMode changed. Signal only - receivers re-read the store, so the
  broadcast is identical for installed (registry) and portable (XML) builds. }
procedure BroadcastAppThemeChanged;

{ DWMWA_USE_IMMERSIVE_DARK_MODE on one window; True when the attribute was
  accepted. It is a no-op for a borderless window (the flyouts are WS_POPUP
  with no frame) and while a VCL style draws the non-client area - it is the
  safety net for a build where the embedded styles are unavailable. }
function ApplyImmersiveDarkMode(AHandle: HWND; AEnabled: Boolean): Boolean;

implementation

uses
  System.SysUtils,
  System.Variants, // VarToStr on an XML node value
  System.Win.Registry,
  Xml.XMLDoc,  // TXMLDocument: the portable store, read-only
  Xml.XMLIntf, // IXMLNode
  Vcl.Themes,
  Vcl.Forms,
  Winapi.DwmApi,
  Winapi.Messages; // WM_SETTINGCHANGE lives here, not in Winapi.Windows

const
  { Windows 10 17763..18999 shipped the attribute with this pre-release id. }
  DWMWA_USE_IMMERSIVE_DARK_MODE_LEGACY = 19;

  THEME_KEY   = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';
  THEME_VALUE = 'AppsUseLightTheme';

  { The store the Customize dialog writes: the Avro Keyboard registry key when
    installed, Settings.xml beside the exe when portable. Every satellite reads
    THIS one - never its own settings file - so one setting drives them all. }
  AVRO_SETTING_KEY   = 'Software\OmicronLab\Avro Keyboard';
  AVRO_SETTING_VALUE = 'AppThemeMode';
  AVRO_SETTING_FILE  = 'Settings.xml';

var
  // The resolved theme in force; light until ApplyAppTheme says otherwise.
  FResolvedMode: TAppThemeMode = atmLight;
  // False until the first ApplyAppTheme, so the very first call always applies
  // even when its resolved theme happens to be the default light one.
  FApplied: Boolean = False;
  // Attribute id that worked last, so the legacy fallback is probed once.
  FImmersiveAttr: DWORD = DWMWA_USE_IMMERSIVE_DARK_MODE;

  { =============================================================================== }
  { Detection and resolution }
  { =============================================================================== }

function WindowsAppsUseLightTheme: Boolean;
var
  Reg: TRegistry;
begin
  Result := True; // Windows' default when the value is absent
  Reg := nil;
  try
    Reg := TRegistry.Create(KEY_READ);
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.KeyExists(THEME_KEY) and Reg.OpenKey(THEME_KEY, False) then
      try
        if Reg.ValueExists(THEME_VALUE) then
          Result := Reg.ReadInteger(THEME_VALUE) <> 0;
      finally
        Reg.CloseKey;
      end;
  except
    // A locked-down hive must never break theming: stay on light.
    Result := True;
  end;
  Reg.Free;
end;

function ResolveAppTheme(AMode: TAppThemeMode; ASystemUsesLightTheme: Boolean): TAppThemeMode;
begin
  case AMode of
    atmLight:
      Result := atmLight; // forced, whatever Windows is set to
    atmDark:
      Result := atmDark;
    else
      if ASystemUsesLightTheme then
        Result := atmLight
      else
        Result := atmDark;
  end;
end;

function AppThemeModeFromSetting(const AValue: string): TAppThemeMode;
begin
  if SameText(AValue, APP_THEME_SETTING_LIGHT) then
    Result := atmLight
  else if SameText(AValue, APP_THEME_SETTING_DARK) then
    Result := atmDark
  else
    Result := atmSystemDefault;
end;

function AppThemeModeToSetting(AMode: TAppThemeMode): string;
begin
  case AMode of
    atmLight:
      Result := APP_THEME_SETTING_LIGHT;
    atmDark:
      Result := APP_THEME_SETTING_DARK;
    else
      Result := APP_THEME_SETTING_SYSTEM;
  end;
end;

function AppThemeModeCaption(AMode: TAppThemeMode): string;
begin
  case AMode of
    atmLight:
      Result := 'Light Theme';
    atmDark:
      Result := 'Dark Theme';
    else
      Result := 'System Default';
  end;
end;

{ =============================================================================== }
{ Palettes }
{ =============================================================================== }

function GetAppThemePalette(AResolved: TAppThemeMode): TAppThemePalette;
begin
  if AResolved = atmDark then
  begin
    Result.IsDark := True;
    Result.Background := RGB(32, 32, 32);
    Result.Text := RGB(240, 240, 240);
    Result.SelectionFill := RGB(0, 120, 215);
    Result.SelectionText := RGB(255, 255, 255);
    Result.Border := RGB(60, 60, 60);
    Result.HoverFill := RGB(50, 50, 52);
  end
  else
  begin
    Result.IsDark := False;
    Result.Background := RGB(255, 255, 255);
    Result.Text := RGB(0, 0, 0);
    Result.SelectionFill := RGB(0, 120, 215);
    Result.SelectionText := RGB(255, 255, 255);
    Result.Border := RGB(200, 200, 200);
    // Today's flyout hover tint, kept so light mode looks unchanged.
    Result.HoverFill := RGB(218, 236, 255);
  end;
end;

function CurrentAppThemeMode: TAppThemeMode;
begin
  Result := FResolvedMode;
end;

function IsDarkAppTheme: Boolean;
begin
  Result := FResolvedMode = atmDark;
end;

function CurrentPalette: TAppThemePalette;
begin
  Result := GetAppThemePalette(FResolvedMode);
end;

{ =============================================================================== }
{ Application }
{ =============================================================================== }

function ApplyImmersiveDarkMode(AHandle: HWND; AEnabled: Boolean): Boolean;
var
  Value: BOOL;
  Hr:    HRESULT;
begin
  Result := False;
  if (AHandle = 0) or (not IsWindow(AHandle)) then
    Exit;

  Value := BOOL(Ord(AEnabled));
  try
    Hr := DwmSetWindowAttribute(AHandle, FImmersiveAttr, @Value, SizeOf(Value));
    if (Hr <> S_OK) and (FImmersiveAttr <> DWMWA_USE_IMMERSIVE_DARK_MODE_LEGACY) then
    begin
      // Older Windows 10 builds reject the current id; remember the one that
      // works so every later call goes straight to it.
      FImmersiveAttr := DWMWA_USE_IMMERSIVE_DARK_MODE_LEGACY;
      Hr := DwmSetWindowAttribute(AHandle, FImmersiveAttr, @Value, SizeOf(Value));
    end;
    Result := Hr = S_OK;
  except
    // Winapi.DwmApi is imported delayed; a system without dwmapi.dll must not
    // take the theme down with it.
    Result := False;
  end;
end;

procedure ApplyAppTheme(const AMode: TAppThemeMode);
var
  Resolved:  TAppThemeMode;
  StyleName: string;
  Dark:      Boolean;
begin
  Resolved := ResolveAppTheme(AMode, WindowsAppsUseLightTheme);
  if FApplied and (FResolvedMode = Resolved) then
    // RefreshSettings runs after every toggle in the app; re-applying the same
    // VCL style would restyle every form for nothing.
    Exit;
  FResolvedMode := Resolved;
  FApplied := True;
  Dark := Resolved = atmDark;

  if Dark then
    StyleName := APP_STYLE_DARK
  else
    StyleName := APP_STYLE_LIGHT;

  // False = never show the VCL "Style not found" dialog; a build without the
  // embedded styles degrades to the light style instead of failing.
  if not TStyleManager.TrySetStyle(StyleName, False) then
    TStyleManager.TrySetStyle(APP_STYLE_LIGHT, False);

  // Frame of our own windows (the Customize dialog while Apply is pressed).
  // A styled window draws its own caption, so this is invisible there; it is
  // what keeps the frame dark on a build where the styles are unavailable.
  if Assigned(Screen.ActiveForm) then
    ApplyImmersiveDarkMode(Screen.ActiveForm.Handle, Dark);
  if Assigned(Application.MainForm) then
    ApplyImmersiveDarkMode(Application.MainForm.Handle, Dark);
end;

{ =============================================================================== }
{ Stored setting (what the Customize dialog last wrote) }
{ =============================================================================== }

{$IFDEF PortableOn}

{ Settings.xml beside the exe, in the exact layout TXMLSetting writes: a root
  element holding one child element per setting, each with a single CDATA
  payload. Read here instead of through clsRegistry_XMLSetting on purpose:
  every satellite ships its OWN copy of that class pointed at its OWN file
  ('Layout Editor Settings.xml', 'Spell Settings.xml'), so going through the
  class would silently read the wrong document in those projects. This reader
  always opens the main Avro Keyboard settings, whichever project links this
  unit. An absent or malformed file simply yields '' (= SYSTEM). }
function PortableAppThemeSetting: string;
var
  Doc:  TXMLDocument;
  Node: IXMLNode;
begin
  Result := '';
  if not FileExists(ExtractFilePath(Application.ExeName) + AVRO_SETTING_FILE) then
    Exit;
  { Owner must be Application, not nil. With a nil owner FOwnerIsComponent is
    False, and TXMLDocument._Release (Xml.XMLDoc.pas) DESTROYS the document the
    moment the document-element node's transient second reference is released
    (FRefCount 1 -> 0). That happens while DocumentElement/FindNode is still
    being evaluated: the freed shell then answers Active with a stale False and
    the next interface release into the dangling node raises "Invalid pointer
    operation" - the crash all three portable satellites hit at startup. A
    component owner suppresses that self-destruct; Doc.Free below frees it. }
  Doc := TXMLDocument.Create(Application);
  try
    try
      Doc.Active := True;
      Doc.LoadFromFile(ExtractFilePath(Application.ExeName) + AVRO_SETTING_FILE);
      Node := Doc.DocumentElement.ChildNodes.FindNode(AVRO_SETTING_VALUE);
      if Assigned(Node) and (Node.ChildNodes.Count > 0) then
        Result := Trim(VarToStr(Node.ChildNodes.Nodes[0].NodeValue));
    except
      Result := '';
    end;
    // The node interface must be released BEFORE the document: Node is
    // finalized in the function epilogue, after Doc.Free, and touching the
    // already-destroyed DOM there raises "Invalid pointer operation".
    Node := nil;
  finally
    Doc.Free;
  end;
end;
{$ENDIF}

function StoredAppThemeMode: TAppThemeMode;
{$IFDEF PortableOn}
begin
  Result := AppThemeModeFromSetting(PortableAppThemeSetting);
end;
{$ELSE}

var
  Reg: TRegistry;
begin
  Result := atmSystemDefault;
  Reg := nil;
  try
    Reg := TRegistry.Create(KEY_READ);
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(AVRO_SETTING_KEY, False) then
      try
        if Reg.ValueExists(AVRO_SETTING_VALUE) then
          Result := AppThemeModeFromSetting(Reg.ReadString(AVRO_SETTING_VALUE));
      finally
        Reg.CloseKey;
      end;
  except
    // Wrong value type or a locked-down hive must never break theming:
    // fall back to SYSTEM.
    Result := atmSystemDefault;
  end;
  Reg.Free;
end;
{$ENDIF}

procedure ApplyStoredAppTheme;
begin
  ApplyAppTheme(StoredAppThemeMode);
end;

procedure BroadcastAppThemeChanged;
var
  Res: DWORD_PTR;
begin
  { SMTO_ABORTIFHUNG + short timeout: a hung top-level window anywhere in the
    session must not block the Customize dialog. Result intentionally ignored. }
  SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, LPARAM(PChar(APP_THEME_BROADCAST_SECTION)), SMTO_ABORTIFHUNG, 500, @Res);
end;

end.
