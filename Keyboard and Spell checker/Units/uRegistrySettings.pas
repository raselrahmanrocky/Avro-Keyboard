{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
{ COMPLETE TRANSFERING! }

unit uRegistrySettings;

interface

uses
  Classes,
  Sysutils,
  clsRegistry_XMLSetting,
  uWindowHandlers,
  Windows,
  Forms,
  StrUtils;

const
  NumberOfVisibleHints: Integer = 2;

var
  DontShowComplexLNotification: string;
  DontShowStartupWizard:        string;

  // General settings
  StartWithWindows: string;
  ShowSplash:       string;
  DefaultUIMode:    string;
  LastUIMode:       string;
  TopBarPosX:       string;
  TopBarXButton:    string;

  // Inteface Settings
  TopBarTransparent:       string;
  TopBarTransparencyLevel: string;
  InterfaceSkin:           string;
  TrayHintShowTimes:       string;
  TopHintShowTimes:        string;

  // Webbuddy Options
  AvroUpdateCheck:     string;
  AvroUpdateLastCheck: TDateTime;

  // Hotkey settings
  ModeSwitchKey:                string;
  ToggleOutputModeKey:          string;
  SpellerLauncherKey:           string;
  LayoutSwitchKey:              string;
  ShowLayoutSwitchNotification: string;
  AnsiVersionSwitchKey:         string;
  ShowAnsiSwitchNotification:   string;

  // Avro Mouse Settings
  AvroMousePosX: string;
  AvroMousePosY: string;

  // Avro Phonetic Settings
  PhoneticAutoCorrect:  string;
  ShowPrevWindow:       string;
  FollowCaretByDefault: string;
  PhoneticMode:         string;
  SaveCandidate:        string;
  AddToPhoneticDict:    string;
  TabBrowsing:          string;
  PipeToDot:            string;
  EnableJoNukta:        string;

  // Fixed Layout Settings
  DefaultLayout:           string; // NOT A Fixed Layout SETTING!
  OldStyleReph:            string;
  VowelFormating:          string;
  NumPadBangla:            string;
  FullOldStyleTyping:      string;
  AutomaticallyFixChandra: string;
  EnableCaretSniffer:      string;

  // Keyboard Layout Viewer Settings
  ShowLayoutOnTop:     string;
  SavePosLayoutViewer: string;
  LayoutViewerPosX:    string;
  LayoutViewerPosY:    string;
  LayoutViewerSize:    string;

  // Global Output settings
  OutputIsBijoy:         string;
  ShowOutputwarning:     string;
  UnicodeToggleShortcut: string;
  ANSIToggleShortcut:    string;
  IgnoreCapsLock:        string;

var
  // Per-encoding password memory (key = lowercase full file path). A protected
  // encoding asks for its password ONCE on this computer; every later load
  // (even after restarting the app or the PC) decrypts silently from here.
  EncoPasswordCache: TStringList;

procedure InitEncoPasswordCache;
procedure FreeEncoPasswordCache;
function GetEncoCachedPassword(const AFilePath: string): AnsiString;
procedure RememberEncoPassword(const AFilePath: string; const APassword: AnsiString);
procedure ForgetEncoPassword(const AFilePath: string);

procedure SaveUISettings;
procedure LoadSettings;
procedure ValidateSettings;
procedure SaveSettings;
procedure SaveAnsiVersionOnly;

procedure LoadSettingsFromFile;
procedure SaveSettingsInXML;

procedure LoadSettingsFromRegistry;
procedure SaveSettingsInRegistry;

implementation

uses
  uForm1,
  uTopBar,
  WindowsVersion,
  clsUnicodeToBijoy2000,
  uKeyboardMacro,
  uAvroEncoManager;

{ =============================================================================== }
{ Per-encoding password memory (helpers)                                        }
{ =============================================================================== }

const
  EncoCacheSep = #9; // TAB separates file path from password (never typed in a
                     // single-line edit, and never part of an NTFS file name)

procedure InitEncoPasswordCache;
begin
  if not Assigned(EncoPasswordCache) then
  begin
    EncoPasswordCache := TStringList.Create;
    EncoPasswordCache.NameValueSeparator := EncoCacheSep;
  end;
end;

procedure FreeEncoPasswordCache;
begin
  FreeAndNil(EncoPasswordCache);
end;

function EncodeEncoCache: string;
var
  I: Integer;
begin
  Result := '';
  if not Assigned(EncoPasswordCache) or (EncoPasswordCache.Count = 0) then
    Exit;
  for I := 0 to EncoPasswordCache.Count - 1 do
  begin
    if I > 0 then
      Result := Result + #13#10;
    Result := Result + EncoPasswordCache.Names[I] + EncoCacheSep +
      EncoPasswordCache.ValueFromIndex[I];
  end;
end;

procedure DecodeEncoCache(const ABlob: string);
var
  Lines: TStringList;
  I, Sep: Integer;
  Line: string;
begin
  InitEncoPasswordCache;
  EncoPasswordCache.Clear;
  if Trim(ABlob) = '' then
    Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := ABlob;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then
        Continue;
      Sep := Pos(EncoCacheSep, Line);
      if (Sep > 1) and (Sep < Length(Line)) then
        EncoPasswordCache.Add(Line);
    end;
  finally
    Lines.Free;
  end;
end;

function GetEncoCachedPassword(const AFilePath: string): AnsiString;
var
  Key: string;
  I: Integer;
begin
  Result := '';
  Key := LowerCase(Trim(AFilePath));
  if Key = '' then
    Exit;
  InitEncoPasswordCache;
  for I := 0 to EncoPasswordCache.Count - 1 do
    if EncoPasswordCache.Names[I] = Key then
    begin
      Result := AnsiString(EncoPasswordCache.ValueFromIndex[I]);
      Exit;
    end;
end;

procedure RememberEncoPassword(const AFilePath: string; const APassword: AnsiString);
var
  Key: string;
  I: Integer;
  Found: Boolean;
begin
  if (Trim(AFilePath) = '') or (APassword = '') then
    Exit;
  InitEncoPasswordCache;
  Key := LowerCase(Trim(AFilePath));
  Found := False;
  for I := 0 to EncoPasswordCache.Count - 1 do
    if EncoPasswordCache.Names[I] = Key then
    begin
      EncoPasswordCache[I] := Key + EncoCacheSep + string(APassword);
      Found := True;
      Break;
    end;
  if not Found then
    EncoPasswordCache.Add(Key + EncoCacheSep + string(APassword));
end;

procedure ForgetEncoPassword(const AFilePath: string);
var
  Key: string;
  I: Integer;
begin
  if not Assigned(EncoPasswordCache) then
    Exit;
  Key := LowerCase(Trim(AFilePath));
  for I := EncoPasswordCache.Count - 1 downto 0 do
    if EncoPasswordCache.Names[I] = Key then
      EncoPasswordCache.Delete(I);
end;

{ =============================================================================== }

procedure LoadSettingsFromFile;
var
  Reg: TMyRegistry;
  XML: TXMLSetting;
begin
  Reg := TMyRegistry.create;
  Reg.RootKey := HKEY_CURRENT_USER;

  if Reg.OpenKey('Control Panel\Desktop', True) = True then
  begin
    Reg.WriteInteger('LowLevelHooksTimeout', 5000);
  end;

  Reg.Free;

  XML := TXMLSetting.create;
  XML.LoadXMLData;

  DontShowComplexLNotification := UpperCase(XML.GetValue('DontShowComplexLNotification', 'NO'));
  DontShowStartupWizard := UpperCase(XML.GetValue('DontShowStartupWizard', 'NO'));

  // General settings
  StartWithWindows := UpperCase(XML.GetValue('StartWithWindows', 'Yes'));
  DefaultUIMode := UpperCase(XML.GetValue('DefaultUIMode', 'LastUI'));
  ShowSplash := UpperCase(XML.GetValue('ShowSplash', 'YES'));
  LastUIMode := UpperCase(XML.GetValue('LastUIMode', 'Top Bar'));
  TopBarPosX := UpperCase(XML.GetValue('TopBarPosX', '1000000'));
  TopBarXButton := UpperCase(XML.GetValue('TopBarXButton', 'Show Menu'));
  TopBarTransparent := UpperCase(XML.GetValue('TopBarTransparent', 'Yes'));

  // Inteface Settings
  InterfaceSkin := XML.GetValue('InterfaceSkin', 'internalskin*');
  TopBarTransparencyLevel := XML.GetValue('TopBarTransparencyLevel', '80');
  TopBarTransparent := XML.GetValue('TopBarTransparent', 'YES');
  TrayHintShowTimes := XML.GetValue('TrayHintShowTimes', '0');
  TopHintShowTimes := XML.GetValue('TopHintShowTimes', '0');

  // Webbuddy Options
  AvroUpdateCheck := UpperCase(XML.GetValue('AvroUpdateCheck', 'Yes'));
  AvroUpdateLastCheck := XML.GetValue('AvroUpdateLastCheck', Now);

  // Hotkey settings
  ModeSwitchKey := UpperCase(XML.GetValue('ModeSwitchKey', 'F12'));
  ToggleOutputModeKey := UpperCase(XML.GetValue('ToggleOutputModeKey', 'F12'));
  SpellerLauncherKey := UpperCase(XML.GetValue('SpellerLauncherKey', 'F7'));
  LayoutSwitchKey := UpperCase(XML.GetValue('LayoutSwitchKey', 'CTRL+SHIFT+F11'));
  ShowLayoutSwitchNotification := UpperCase(XML.GetValue('ShowLayoutSwitchNotification', 'YES'));
  AnsiVersionSwitchKey := UpperCase(XML.GetValue('AnsiVersionSwitchKey', 'F12'));
  ShowAnsiSwitchNotification := UpperCase(XML.GetValue('ShowAnsiSwitchNotification', 'YES'));

  // Avro Mouse Settings
  AvroMousePosX := UpperCase(XML.GetValue('AvroMousePosX', '0'));
  AvroMousePosY := UpperCase(XML.GetValue('AvroMousePosY', '0'));

  // Avro Phonetic Settings
  PhoneticAutoCorrect := UpperCase(XML.GetValue('PhoneticAutoCorrect', 'Yes'));
  ShowPrevWindow := UpperCase(XML.GetValue('ShowPrevWindow', 'Yes'));
  FollowCaretByDefault := UpperCase(XML.GetValue('FollowCaretByDefault', 'Yes'));
  PhoneticMode := UpperCase(XML.GetValue('PhoneticMode', 'CHAR'));
  SaveCandidate := UpperCase(XML.GetValue('SaveCandidate', 'YES'));
  AddToPhoneticDict := UpperCase(XML.GetValue('AddToPhoneticDict', 'YES'));
  TabBrowsing := UpperCase(XML.GetValue('TabBrowsing', 'YES'));
  PipeToDot := UpperCase(XML.GetValue('PipeToDot', 'YES'));
  EnableJoNukta := UpperCase(XML.GetValue('EnableJoNukta', 'NO'));

  // Tools Settings
  OldStyleReph := UpperCase(XML.GetValue('OldStyleReph', 'Yes'));
  VowelFormating := UpperCase(XML.GetValue('VowelFormating', 'Yes'));
  NumPadBangla := UpperCase(XML.GetValue('NumPadBangla', 'Yes'));
  FullOldStyleTyping := UpperCase(XML.GetValue('FullOldStyleTyping', 'No'));
  AutomaticallyFixChandra := UpperCase(XML.GetValue('AutomaticallyFixChandra', 'Yes'));
  EnableCaretSniffer := UpperCase(XML.GetValue('EnableCaretSniffer', 'Yes'));

  // Keyboard Layout Viewer Settings
  DefaultLayout := XML.GetValue('DefaultLayout', 'avrophonetic*');
  ShowLayoutOnTop := UpperCase(XML.GetValue('ShowLayoutOnTop', 'Yes'));
  SavePosLayoutViewer := UpperCase(XML.GetValue('SavePosLayoutViewer', 'Yes'));
  LayoutViewerPosX := UpperCase(XML.GetValue('LayoutViewerPosX', '0'));
  LayoutViewerPosY := UpperCase(XML.GetValue('LayoutViewerPosY', '0'));
  LayoutViewerSize := UpperCase(XML.GetValue('LayoutViewerSize', '60%'));

  // Global Output settings
  OutputIsBijoy := UpperCase(XML.GetValue('OutputIsBijoy', 'No'));
  ShowOutputwarning := UpperCase(XML.GetValue('ShowOutputwarning', 'Yes'));
  UnicodeToggleShortcut := UpperCase(XML.GetValue('UnicodeToggleShortcut', 'YES'));
  ANSIToggleShortcut := UpperCase(XML.GetValue('ANSIToggleShortcut', 'YES'));
  IgnoreCapsLock := UpperCase(XML.GetValue('IgnoreCapsLock', 'NO'));

  clsUnicodeToBijoy2000.AnsiVersion := XML.GetValue('AnsiVersion', 'Default');

  // AvroEnco Settings
  CachedEncoPassword := AnsiString(XML.GetValue('CachedEncoPassword', ''));
  DecodeEncoCache(XML.GetValue('EncoPasswordCache', ''));

  XML.Free;

end;

{ =============================================================================== }

procedure SaveSettingsInXML;
var
  XML: TXMLSetting;
begin
  XML := TXMLSetting.create;
  XML.CreateNewXMLData;

  XML.SetValue('DontShowComplexLNotification', DontShowComplexLNotification);
  XML.SetValue('DontShowStartupWizard', DontShowStartupWizard);

  // General settings
  XML.SetValue('StartWithWindows', StartWithWindows);
  XML.SetValue('ShowSplash', ShowSplash);
  XML.SetValue('DefaultUIMode', DefaultUIMode);
  XML.SetValue('LastUIMode', LastUIMode);
  XML.SetValue('TopBarPosX', TopBarPosX);
  XML.SetValue('TopBarXButton', TopBarXButton);
  XML.SetValue('TopBarTransparent', TopBarTransparent);

  // Inteface Settings
  XML.SetValue('InterfaceSkin', InterfaceSkin);
  XML.SetValue('TopBarTransparencyLevel', TopBarTransparencyLevel);
  XML.SetValue('TopBarTransparent', TopBarTransparent);
  XML.SetValue('TrayHintShowTimes', TrayHintShowTimes);
  XML.SetValue('TopHintShowTimes', TopHintShowTimes);

  // Webbuddy Options
  XML.SetValue('AvroUpdateCheck', AvroUpdateCheck);
  XML.SetValue('AvroUpdateLastCheck', AvroUpdateLastCheck);

  // Hotkey settings
  XML.SetValue('ModeSwitchKey', ModeSwitchKey);
  XML.SetValue('ToggleOutputModeKey', ToggleOutputModeKey);
  XML.SetValue('SpellerLauncherKey', SpellerLauncherKey);
  XML.SetValue('LayoutSwitchKey', LayoutSwitchKey);
  XML.SetValue('ShowLayoutSwitchNotification', ShowLayoutSwitchNotification);
  XML.SetValue('AnsiVersionSwitchKey', AnsiVersionSwitchKey);
  XML.SetValue('ShowAnsiSwitchNotification', ShowAnsiSwitchNotification);

  // Avro Mouse Settings
  XML.SetValue('AvroMousePosX', AvroMousePosX);
  XML.SetValue('AvroMousePosY', AvroMousePosY);
  // XML.SetValue('AvroMouseSavePos', AvroMouseSavePos);

  // Avro Phonetic Settings
  XML.SetValue('PhoneticAutoCorrect', PhoneticAutoCorrect);
  XML.SetValue('ShowPrevWindow', ShowPrevWindow);
  XML.SetValue('FollowCaretByDefault', FollowCaretByDefault);
  XML.SetValue('PhoneticMode', PhoneticMode);
  XML.SetValue('SaveCandidate', SaveCandidate);
  XML.SetValue('AddToPhoneticDict', AddToPhoneticDict);
  XML.SetValue('TabBrowsing', TabBrowsing);
  XML.SetValue('PipeToDot', PipeToDot);
  XML.SetValue('EnableJoNukta', EnableJoNukta);

  // Tools Settings
  XML.SetValue('OldStyleReph', OldStyleReph);
  XML.SetValue('VowelFormating', VowelFormating);
  XML.SetValue('NumPadBangla', NumPadBangla);
  XML.SetValue('AutomaticallyFixChandra', AutomaticallyFixChandra);
  XML.SetValue('FullOldStyleTyping', FullOldStyleTyping);
  XML.SetValue('EnableCaretSniffer', EnableCaretSniffer);

  // Keyboard Layout Viewer Settings
  XML.SetValue('DefaultLayout', DefaultLayout);
  XML.SetValue('ShowLayoutOnTop', ShowLayoutOnTop);
  XML.SetValue('SavePosLayoutViewer', SavePosLayoutViewer);
  XML.SetValue('LayoutViewerPosX', LayoutViewerPosX);
  XML.SetValue('LayoutViewerPosY', LayoutViewerPosY);
  XML.SetValue('LayoutViewerSize', LayoutViewerSize);

  // Global Output settings
  XML.SetValue('OutputIsBijoy', OutputIsBijoy);
  XML.SetValue('ShowOutputwarning', ShowOutputwarning);
  XML.SetValue('UnicodeToggleShortcut', UnicodeToggleShortcut);
  XML.SetValue('ANSIToggleShortcut', ANSIToggleShortcut);
  XML.SetValue('IgnoreCapsLock', IgnoreCapsLock);
  XML.SetValue('AnsiVersion', clsUnicodeToBijoy2000.AnsiVersion);

  // AvroEnco Settings
  XML.SetValue('CachedEncoPassword', string(CachedEncoPassword));
  XML.SetValue('EncoPasswordCache', EncodeEncoCache);

  XML.SaveXMLData;
  XML.Free;

end;

{ =============================================================================== }

procedure LoadSettingsFromRegistry;
var
  Reg: TMyRegistry;
begin
  Reg := TMyRegistry.create;
  Reg.RootKey := HKEY_CURRENT_USER;

  if Reg.OpenKey('Control Panel\Desktop', True) = True then
  begin
    Reg.WriteInteger('LowLevelHooksTimeout', 5000);
  end;
  Reg.CloseKey;

  Reg.RootKey := HKEY_CURRENT_USER;
  if Reg.OpenKey('Software\OmicronLab\Avro Keyboard', True) = True then
  begin
    DontShowComplexLNotification := UpperCase(Reg.ReadStringDef('DontShowComplexLNotification', 'NO'));
    DontShowStartupWizard := UpperCase(Reg.ReadStringDef('DontShowStartupWizard', 'NO'));

    // General settings
    StartWithWindows := UpperCase(Reg.ReadStringDef('StartWithWindows', 'Yes'));
    ShowSplash := UpperCase(Reg.ReadStringDef('ShowSplash', 'Yes'));
    DefaultUIMode := UpperCase(Reg.ReadStringDef('DefaultUIMode', 'LastUI'));
    LastUIMode := UpperCase(Reg.ReadStringDef('LastUIMode', 'Top Bar'));
    TopBarPosX := UpperCase(Reg.ReadStringDef('TopBarPosX', '1000000'));
    TopBarXButton := UpperCase(Reg.ReadStringDef('TopBarXButton', 'Show Menu'));
    TopBarTransparent := UpperCase(Reg.ReadStringDef('TopBarTransparent', 'Yes'));
    AvroUpdateCheck := UpperCase(Reg.ReadStringDef('AvroUpdateCheck', 'Yes'));
    AvroUpdateLastCheck := Reg.ReadDateDef('AvroUpdateLastCheck', Now);

    // Inteface Settings
    InterfaceSkin := Reg.ReadStringDef('InterfaceSkin', 'internalskin*');
    TopBarTransparencyLevel := Reg.ReadStringDef('TopBarTransparencyLevel', '80');
    TopBarTransparent := Reg.ReadStringDef('TopBarTransparent', 'YES');
    TrayHintShowTimes := Reg.ReadStringDef('TrayHintShowTimes', '0');
    TopHintShowTimes := Reg.ReadStringDef('TopHintShowTimes', '0');

    // Hotkey settings
    ModeSwitchKey := UpperCase(Reg.ReadStringDef('ModeSwitchKey', 'F12'));
    ToggleOutputModeKey := UpperCase(Reg.ReadStringDef('ToggleOutputModeKey', 'F12'));
    SpellerLauncherKey := UpperCase(Reg.ReadStringDef('SpellerLauncherKey', 'F7'));
    LayoutSwitchKey := UpperCase(Reg.ReadStringDef('LayoutSwitchKey', 'CTRL+SHIFT+F11'));
    ShowLayoutSwitchNotification := UpperCase(Reg.ReadStringDef('ShowLayoutSwitchNotification', 'YES'));
    AnsiVersionSwitchKey := UpperCase(Reg.ReadStringDef('AnsiVersionSwitchKey', 'F12'));
    ShowAnsiSwitchNotification := UpperCase(Reg.ReadStringDef('ShowAnsiSwitchNotification', 'YES'));

    // Avro Mouse Settings
    AvroMousePosX := UpperCase(Reg.ReadStringDef('AvroMousePosX', '0'));
    AvroMousePosY := UpperCase(Reg.ReadStringDef('AvroMousePosY', '0'));

    // Avro Phonetic Settings
    PhoneticAutoCorrect := UpperCase(Reg.ReadStringDef('PhoneticAutoCorrect', 'Yes'));
    ShowPrevWindow := UpperCase(Reg.ReadStringDef('ShowPrevWindow', 'Yes'));
    FollowCaretByDefault := UpperCase(Reg.ReadStringDef('FollowCaretByDefault', 'Yes'));
    PhoneticMode := UpperCase(Reg.ReadStringDef('PhoneticMode', 'CHAR'));
    SaveCandidate := UpperCase(Reg.ReadStringDef('SaveCandidate', 'YES'));
    AddToPhoneticDict := UpperCase(Reg.ReadStringDef('AddToPhoneticDict', 'YES'));
    TabBrowsing := UpperCase(Reg.ReadStringDef('TabBrowsing', 'YES'));
    PipeToDot := UpperCase(Reg.ReadStringDef('PipeToDot', 'YES'));
    EnableJoNukta := UpperCase(Reg.ReadStringDef('EnableJoNukta', 'NO'));

    // Tools Settings
    OldStyleReph := UpperCase(Reg.ReadStringDef('OldStyleReph', 'Yes'));
    VowelFormating := UpperCase(Reg.ReadStringDef('VowelFormating', 'Yes'));
    NumPadBangla := UpperCase(Reg.ReadStringDef('NumPadBangla', 'Yes'));
    FullOldStyleTyping := UpperCase(Reg.ReadStringDef('FullOldStyleTyping', 'No'));
    AutomaticallyFixChandra := UpperCase(Reg.ReadStringDef('AutomaticallyFixChandra', 'Yes'));
    EnableCaretSniffer := UpperCase(Reg.ReadStringDef('EnableCaretSniffer', 'Yes'));

    // Keyboard Layout Viewer Settings
    DefaultLayout := Reg.ReadStringDef('DefaultLayout', 'avrophonetic*');
    ShowLayoutOnTop := UpperCase(Reg.ReadStringDef('ShowLayoutOnTop', 'Yes'));
    SavePosLayoutViewer := UpperCase(Reg.ReadStringDef('SavePosLayoutViewer', 'Yes'));
    LayoutViewerPosX := UpperCase(Reg.ReadStringDef('LayoutViewerPosX', '0'));
    LayoutViewerPosY := UpperCase(Reg.ReadStringDef('LayoutViewerPosY', '0'));
    LayoutViewerSize := UpperCase(Reg.ReadStringDef('LayoutViewerSize', '60%'));

    // Global Output settings
    OutputIsBijoy := UpperCase(Reg.ReadStringDef('OutputIsBijoy', 'No'));
    ShowOutputwarning := UpperCase(Reg.ReadStringDef('ShowOutputwarning', 'Yes'));
    UnicodeToggleShortcut := UpperCase(Reg.ReadStringDef('UnicodeToggleShortcut', 'YES'));
    ANSIToggleShortcut := UpperCase(Reg.ReadStringDef('ANSIToggleShortcut', 'YES'));
    IgnoreCapsLock := UpperCase(Reg.ReadStringDef('IgnoreCapsLock', 'NO'));
    clsUnicodeToBijoy2000.AnsiVersion := Reg.ReadStringDef('AnsiVersion', 'Default');

    // AvroEnco Settings
    CachedEncoPassword := AnsiString(Reg.ReadStringDef('CachedEncoPassword', ''));
    DecodeEncoCache(Reg.ReadStringDef('EncoPasswordCache', ''));

  end;

  Reg.Free;

end;

{ =============================================================================== }

procedure SaveSettingsInRegistry;
var
  Reg: TMyRegistry;
begin
  Reg := TMyRegistry.create;
  Reg.RootKey := HKEY_CURRENT_USER;

  if Reg.OpenKey('Software\OmicronLab\Avro Keyboard', True) = True then
  begin
    Reg.WriteString('AppPath', ExtractFileDir(Application.ExeName));
    Reg.WriteString('AppExeName', ExtractFileName(Application.ExeName));

    Reg.WriteString('DontShowComplexLNotification', DontShowComplexLNotification);
    Reg.WriteString('DontShowStartupWizard', DontShowStartupWizard);

    // General settings
    Reg.WriteString('StartWithWindows', StartWithWindows);
    Reg.WriteString('ShowSplash', ShowSplash);
    Reg.WriteString('DefaultUIMode', DefaultUIMode);
    Reg.WriteString('LastUIMode', LastUIMode);
    Reg.WriteString('TopBarPosX', TopBarPosX);
    Reg.WriteString('TopBarXButton', TopBarXButton);
    Reg.WriteString('TopBarTransparent', TopBarTransparent);

    // Inteface Settings
    Reg.WriteString('InterfaceSkin', InterfaceSkin);
    Reg.WriteString('TopBarTransparencyLevel', TopBarTransparencyLevel);
    Reg.WriteString('TopBarTransparent', TopBarTransparent);
    Reg.WriteString('TrayHintShowTimes', TrayHintShowTimes);
    Reg.WriteString('TopHintShowTimes', TopHintShowTimes);

    // Webbuddy Options
    Reg.WriteString('AvroUpdateCheck', AvroUpdateCheck);
    Reg.WriteDateTime('AvroUpdateLastCheck', AvroUpdateLastCheck);

    // Hotkeys settings
    Reg.WriteString('ModeSwitchKey', ModeSwitchKey);
    Reg.WriteString('ToggleOutputModeKey', ToggleOutputModeKey);
    Reg.WriteString('SpellerLauncherKey', SpellerLauncherKey);
    Reg.WriteString('LayoutSwitchKey', LayoutSwitchKey);
    Reg.WriteString('ShowLayoutSwitchNotification', ShowLayoutSwitchNotification);
    Reg.WriteString('AnsiVersionSwitchKey', AnsiVersionSwitchKey);
    Reg.WriteString('ShowAnsiSwitchNotification', ShowAnsiSwitchNotification);

    // Avro Mouse Settings
    Reg.WriteString('AvroMousePosX', AvroMousePosX);
    Reg.WriteString('AvroMousePosY', AvroMousePosY);

    // Avro Phonetic Settings
    Reg.WriteString('PhoneticAutoCorrect', PhoneticAutoCorrect);
    Reg.WriteString('ShowPrevWindow', ShowPrevWindow);
    Reg.WriteString('FollowCaretByDefault', FollowCaretByDefault);
    Reg.WriteString('PhoneticMode', PhoneticMode);
    Reg.WriteString('SaveCandidate', SaveCandidate);
    Reg.WriteString('AddToPhoneticDict', AddToPhoneticDict);
    Reg.WriteString('TabBrowsing', TabBrowsing);
    Reg.WriteString('PipeToDot', PipeToDot);
    Reg.WriteString('EnableJoNukta', EnableJoNukta);

    // Tools Settings
    Reg.WriteString('OldStyleReph', OldStyleReph);
    Reg.WriteString('VowelFormating', VowelFormating);
    Reg.WriteString('NumPadBangla', NumPadBangla);
    Reg.WriteString('AutomaticallyFixChandra', AutomaticallyFixChandra);
    Reg.WriteString('FullOldStyleTyping', FullOldStyleTyping);
    Reg.WriteString('EnableCaretSniffer', EnableCaretSniffer);

    // Keyboard Layout Viewer Settings
    Reg.WriteString('DefaultLayout', DefaultLayout);
    Reg.WriteString('ShowLayoutOnTop', ShowLayoutOnTop);
    Reg.WriteString('SavePosLayoutViewer', SavePosLayoutViewer);
    Reg.WriteString('LayoutViewerPosX', LayoutViewerPosX);
    Reg.WriteString('LayoutViewerPosY', LayoutViewerPosY);
    Reg.WriteString('LayoutViewerSize', LayoutViewerSize);

    // Global Output settings
    Reg.WriteString('OutputIsBijoy', OutputIsBijoy);
    Reg.WriteString('ShowOutputwarning', ShowOutputwarning);
    Reg.WriteString('UnicodeToggleShortcut', UnicodeToggleShortcut);
    Reg.WriteString('ANSIToggleShortcut', ANSIToggleShortcut);
    Reg.WriteString('IgnoreCapsLock', IgnoreCapsLock);
    Reg.WriteString('AnsiVersion', clsUnicodeToBijoy2000.AnsiVersion);

    // AvroEnco Settings
    Reg.WriteString('CachedEncoPassword', string(CachedEncoPassword));
    Reg.WriteString('EncoPasswordCache', EncodeEncoCache);

  end;

  Reg.CloseKey;
  Reg.RootKey := HKEY_CURRENT_USER;

  if Reg.OpenKey('Software\Microsoft\Windows\CurrentVersion\Run', True) = True then
  begin
    if StartWithWindows = 'NO' then
      Reg.DeleteValue('Avro Keyboard')
    else
      Reg.WriteString('Avro Keyboard', Application.ExeName);
  end;

  Reg.Free;

end;

{ =============================================================================== }

procedure SaveUISettings;
begin
  if IsFormVisible('TopBar') = True then
  begin
    LastUIMode := 'TOP BAR';
    TopBarPosX := IntToStr(TopBar.Left);
  end
  else
  begin
    LastUIMode := 'ICON';
  end;

  DefaultLayout := AvroMainForm1.GetMyCurrentLayout;

  SaveSettings;
end;

procedure LoadSettings;
begin

  {$IFDEF PortableOn}
  LoadSettingsFromFile;

  {$ELSE}
  LoadSettingsFromRegistry;

  {$ENDIF}
  ValidateSettings;
end;

{ =============================================================================== }

procedure DeduplicateHotkeys;
var
  Keys: array [0 .. 4] of ^string;
  I, J: Integer;
begin
  // Priority: ModeSwitch > ToggleOutput > SpellerLauncher > LayoutSwitch > AnsiVersion
  Keys[0] := @ModeSwitchKey;
  Keys[1] := @ToggleOutputModeKey;
  Keys[2] := @SpellerLauncherKey;
  Keys[3] := @LayoutSwitchKey;
  Keys[4] := @AnsiVersionSwitchKey;

  // For each higher-priority key, clear any lower-priority key with the same value
  for I := 0 to 3 do
  begin
    if (Keys[I]^ = '') or (Keys[I]^ = 'NONE') then
      Continue;
    for J := I + 1 to 4 do
    begin
      if (Keys[J]^ <> '') and (Keys[J]^ <> 'NONE') and (HotkeyStringToModifiers(Keys[I]^) = HotkeyStringToModifiers(Keys[J]^)) and
        (HotkeyStringToKey(Keys[I]^) = HotkeyStringToKey(Keys[J]^)) then
        Keys[J]^ := '';
    end;
  end;
end;

{ =============================================================================== }

procedure ValidateSettings;
begin
  // General settings
  if not((StartWithWindows = 'YES') or (StartWithWindows = 'NO')) then
    StartWithWindows := 'YES';
  if not((DefaultUIMode = 'TOP BAR') or (DefaultUIMode = 'ICON') or (DefaultUIMode = 'LASTUI')) then
    DefaultUIMode := 'LASTUI';
  if not((LastUIMode = 'ICON') or (LastUIMode = 'TOP BAR')) then
    LastUIMode := 'TOP BAR';
  if not(StrToInt(TopBarPosX) > 0) then
    TopBarPosX := '1000000';
  if not((TopBarXButton = 'MINIMIZE') or (TopBarXButton = 'EXIT') or (TopBarXButton = 'SHOW MENU')) then
    TopBarXButton := 'SHOW MENU';
  if not((TopBarTransparent = 'YES') or (TopBarTransparent = 'NO')) then
    TopBarTransparent := 'YES';

  // Keyboard Mode settings
  // No restrictive validation - the hotkey recording UI ensures only valid
  // strings are saved, and MatchesHotkeySetting handles any well-formed
  // hotkey string (e.g., 'Ctrl+F10', 'Alt+Shift+F7', 'Win+Space').
  // Empty string or 'NONE' means the feature is disabled.
  if not((ShowLayoutSwitchNotification = 'YES') or (ShowLayoutSwitchNotification = 'NO')) then
    ShowLayoutSwitchNotification := 'YES';
  if not((ShowAnsiSwitchNotification = 'YES') or (ShowAnsiSwitchNotification = 'NO')) then
    ShowAnsiSwitchNotification := 'YES';

  // Avro Mouse Settings
  if not(StrToInt(AvroMousePosX) > 0) then
    AvroMousePosX := '0';
  if not(StrToInt(AvroMousePosY) > 0) then
    AvroMousePosY := '0';

  // Avro Phonetic Settings
  if not((PhoneticAutoCorrect = 'YES') or (PhoneticAutoCorrect = 'NO')) then
    PhoneticAutoCorrect := 'YES';
  if not((ShowPrevWindow = 'YES') or (ShowPrevWindow = 'NO')) then
    ShowPrevWindow := 'YES';
  if not((FollowCaretByDefault = 'YES') or (FollowCaretByDefault = 'NO')) then
    FollowCaretByDefault := 'YES';
  if not((TabBrowsing = 'YES') or (TabBrowsing = 'NO')) then
    TabBrowsing := 'YES';
  if not((PipeToDot = 'YES') or (PipeToDot = 'NO')) then
    PipeToDot := 'YES';
  if not((EnableJoNukta = 'YES') or (EnableJoNukta = 'NO')) then
    EnableJoNukta := 'NO';

  // Tools Settings
  if not((OldStyleReph = 'YES') or (OldStyleReph = 'NO')) then
    OldStyleReph := 'YES';
  if not((VowelFormating = 'YES') or (VowelFormating = 'NO')) then
    VowelFormating := 'YES';
  if not((NumPadBangla = 'YES') or (NumPadBangla = 'NO')) then
    NumPadBangla := 'YES';
  if not((FullOldStyleTyping = 'YES') or (FullOldStyleTyping = 'NO')) then
    FullOldStyleTyping := 'No';
  if not((AutomaticallyFixChandra = 'YES') or (AutomaticallyFixChandra = 'NO')) then
    AutomaticallyFixChandra := 'YES';
  if not((EnableCaretSniffer = 'YES') or (EnableCaretSniffer = 'NO')) then
    EnableCaretSniffer := 'YES';

  // Keyboard Layout Viewer Settings
  if not((ShowLayoutOnTop = 'YES') or (ShowLayoutOnTop = 'NO')) then
    ShowLayoutOnTop := 'YES';
  if not((SavePosLayoutViewer = 'YES') or (SavePosLayoutViewer = 'NO')) then
    SavePosLayoutViewer := 'YES';
  if not(StrToInt(LayoutViewerPosX) > 0) then
    LayoutViewerPosX := '0';
  if not(StrToInt(LayoutViewerPosY) > 0) then
    LayoutViewerPosX := '0';
  // If Not ((StrToInt(LayoutViewerSize) > 50) And (RightStr(LayoutViewerSize, 1) = '%')) Then LayoutViewerSize := '60%';

  // Global Output settings
  if not((OutputIsBijoy = 'YES') or (OutputIsBijoy = 'NO')) then
    OutputIsBijoy := 'NO';
  if not((ShowOutputwarning = 'YES') or (ShowOutputwarning = 'NO')) then
    ShowOutputwarning := 'YES';
  if not((UnicodeToggleShortcut = 'YES') or (UnicodeToggleShortcut = 'NO')) then
    UnicodeToggleShortcut := 'YES';
  if not((ANSIToggleShortcut = 'YES') or (ANSIToggleShortcut = 'NO')) then
    ANSIToggleShortcut := 'YES';
  if not((IgnoreCapsLock = 'YES') or (IgnoreCapsLock = 'NO')) then
    IgnoreCapsLock := 'NO';

  // Hotkey deduplication: reset lower-priority hotkeys that
  // duplicate a higher-priority one.
  DeduplicateHotkeys;

  // ANSI Mapping Version
  if clsUnicodeToBijoy2000.AnsiVersion = '' then
    clsUnicodeToBijoy2000.AnsiVersion := 'Default';
end;

{ =============================================================================== }

procedure SaveSettings;
begin

  {$IFDEF PortableOn}
  SaveSettingsInXML;

  {$ELSE}
  SaveSettingsInRegistry;

  {$ENDIF}
end;

{ =============================================================================== }

{ Saves only the value changed by an ANSI picker/menu click. The previous
  SaveSettings call rewrote every application setting synchronously. }
procedure SaveAnsiVersionOnly;
{$IFNDEF PortableOn}
var
  Reg: TMyRegistry;
{$ENDIF}
begin
  {$IFDEF PortableOn}
  // Portable settings share one XML file; keep compatibility.
  SaveSettingsInXML;
  {$ELSE}
  Reg := TMyRegistry.Create;
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey('Software\OmicronLab\Avro Keyboard', True) then
      Reg.WriteString('AnsiVersion', clsUnicodeToBijoy2000.AnsiVersion);
  finally
    Reg.Free;
  end;
  {$ENDIF}
end;

initialization
finalization
  FreeEncoPasswordCache;

end.
