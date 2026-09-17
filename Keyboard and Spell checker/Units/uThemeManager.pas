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
  Winapi.Windows,   // HWND, RGB()
  System.UITypes;   // TColor

type
  TAppThemeMode = (atmSystemDefault, atmLight, atmDark);

  { One palette for every hand-painted surface. The first five colours are the
    documented theme contract (and are asserted literally by kat_engineswitch);
    HoverFill is the row tint the flyouts use and has no system equivalent. }
  TAppThemePalette = record
    IsDark:        Boolean;
    Background:    TColor;
    Text:          TColor;
    SelectionFill: TColor;
    SelectionText: TColor;
    Border:        TColor;
    HoverFill:     TColor;
  end;

const
  { The two VCL styles Avro_Keyboard.dproj embeds (Custom_Styles). }
  APP_STYLE_LIGHT = 'Windows10';
  APP_STYLE_DARK  = 'Windows10 Dark';

  APP_THEME_SETTING_SYSTEM = 'SYSTEM';
  APP_THEME_SETTING_LIGHT  = 'LIGHT';
  APP_THEME_SETTING_DARK   = 'DARK';

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

{ DWMWA_USE_IMMERSIVE_DARK_MODE on one window; True when the attribute was
  accepted. It is a no-op for a borderless window (the flyouts are WS_POPUP
  with no frame) and while a VCL style draws the non-client area - it is the
  safety net for a build where the embedded styles are unavailable. }
function ApplyImmersiveDarkMode(AHandle: HWND; AEnabled: Boolean): Boolean;

implementation

uses
  System.SysUtils,
  System.Win.Registry,
  Vcl.Themes,
  Vcl.Forms,
  Winapi.DwmApi;

const
  { Windows 10 17763..18999 shipped the attribute with this pre-release id. }
  DWMWA_USE_IMMERSIVE_DARK_MODE_LEGACY = 19;

  THEME_KEY   = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';
  THEME_VALUE = 'AppsUseLightTheme';

var
  // The resolved theme in force; light until ApplyAppTheme says otherwise.
  FResolvedMode:  TAppThemeMode = atmLight;
  // False until the first ApplyAppTheme, so the very first call always applies
  // even when its resolved theme happens to be the default light one.
  FApplied:       Boolean = False;
  // Attribute id that worked last, so the legacy fallback is probed once.
  FImmersiveAttr: DWORD = DWMWA_USE_IMMERSIVE_DARK_MODE;

{ =============================================================================== }
{ Detection and resolution                                                       }
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
{ Palettes                                                                       }
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
{ Application                                                                    }
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

end.
