{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit uForm1;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Variants,
  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  ImgList,
  ExtCtrls,
  Menus,
  clsLayout,
  Generics.Collections,
  StrUtils,
  clsUpdateInfoDownloader,
  DateUtils,
  System.ImageList,
  Vcl.AppEvnts,
  ShellAPI,
  uLocale;

type
  TMenuItemExtended = class(TMenuItem)
    private
      fValue: string;
    published
      property Value: string read fValue write fValue;
  end;

type
  TWindowRecord = record
    Mode: string;
  end;

type
  TAvroMainForm1 = class(TForm)
    Tray: TTrayIcon;
    ImageList1: TImageList;
    Popup_Web: TPopupMenu;
    Popup_LayoutList: TPopupMenu;
    Popup_Exit: TPopupMenu;
    Popup_Help: TPopupMenu;
    Popup_Main: TPopupMenu;
    Popup_Tools: TPopupMenu;
    AvroPhonetic1: TMenuItem;
    EnableAutoCorrect1: TMenuItem;
    ManageAutoCorrectentries1: TMenuItem;
    LayoutViewerShowactivekeyboardlayout1: TMenuItem;
    AvroMouseClicknType1: TMenuItem;
    KeyboardLayoutEditorBuildcustomlayouts1: TMenuItem;
    SkinDesignerDesignyourownskin1: TMenuItem;
    N3: TMenuItem;
    Options1: TMenuItem;
    N4: TMenuItem;
    N5: TMenuItem;
    CheckupdateforAvroKeyboard1: TMenuItem;
    N6: TMenuItem;
    MoreFreeDownloads1: TMenuItem;
    FreeBanglaFonts1: TMenuItem;
    UsefultoolsforBangla1: TMenuItem;
    AvroKeyboardontheweb1: TMenuItem;
    PortableAvroKeyboardontheweb1: TMenuItem;
    wwwOmicronLabcom1: TMenuItem;
    UserForum1: TMenuItem;
    AvroPhoneticEnglishtoBangla1: TMenuItem;
    N7: TMenuItem;
    Showactivekeyboardlayout1: TMenuItem;
    N8: TMenuItem;
    AvroMouseClicknType2: TMenuItem;
    Jumptosystemtray1: TMenuItem;
    Exit1: TMenuItem;
    Configuringyoursystem1: TMenuItem;
    OTFBanglaFontscamewithAvroKeyboard1: TMenuItem;
    Helponhelp1: TMenuItem;
    N9: TMenuItem;
    BeforeYouStart1: TMenuItem;
    Overview1: TMenuItem;
    CustomizingAvroKeyboard1: TMenuItem;
    BanglaTypingwithAvroPhonetic1: TMenuItem;
    BanglaTypingwithFixedKeyboardLayouts1: TMenuItem;
    BanglaTypingwithAvroMouse1: TMenuItem;
    FrequentlyAskedQuestionsFAQ1: TMenuItem;
    N10: TMenuItem;
    CreatingEditingFixedKeyboardLayouts1: TMenuItem;
    N11: TMenuItem;
    Moredocumentsontheweb1: TMenuItem;
    N15: TMenuItem;
    Aboutcurrentkeyboardlayout1: TMenuItem;
    AboutAvroKeyboard1: TMenuItem;
    ogglekeyboardmode1: TMenuItem;
    Docktotop1: TMenuItem;
    Jumptosystemtray2: TMenuItem;
    N16: TMenuItem;
    Selectkeyboardlayout1: TMenuItem;
    AvroPhoneticEnglishtoBangla2: TMenuItem;
    N17: TMenuItem;
    Showactivekeyboardlayout2: TMenuItem;
    AvroMouseClicknType3: TMenuItem;
    N18: TMenuItem;
    Ontheweb1: TMenuItem;
    CheckupdateforAvroKeyboard2: TMenuItem;
    N19: TMenuItem;
    MoreFreeDownloads2: TMenuItem;
    FreeBanglaFonts2: TMenuItem;
    UsefultoolsforBangla2: TMenuItem;
    AvroKeyboardontheweb2: TMenuItem;
    PortableAvroKeyboardontheweb2: TMenuItem;
    wwwOmicronLabcom2: TMenuItem;
    UserForum2: TMenuItem;
    N20: TMenuItem;
    CustomizeAvroKeyboard1: TMenuItem;
    N21: TMenuItem;
    Helpfiles1: TMenuItem;
    Configuringyoursystem2: TMenuItem;
    OTFBanglaFontscamewithAvroKeyboard2: TMenuItem;
    Helponhelp2: TMenuItem;
    N22: TMenuItem;
    BeforeYouStart2: TMenuItem;
    Overview2: TMenuItem;
    CustomizingAvroKeyboard2: TMenuItem;
    BanglaTypingwithAvroPhonetic2: TMenuItem;
    BanglaTypingwithFixedKeyboardLayouts2: TMenuItem;
    BanglaTypingwithAvroMouse2: TMenuItem;
    FrequentlyAskedQuestionsFAQ2: TMenuItem;
    N23: TMenuItem;
    CreatingEditingFixedKeyboardLayouts2: TMenuItem;
    N24: TMenuItem;
    HowtoBanglaFileFolderName2: TMenuItem;
    HowtoBanglaChat2: TMenuItem;
    HowtoSearchingwebinBangla2: TMenuItem;
    N25: TMenuItem;
    HowtoDevelopBanglaWebPage2: TMenuItem;
    HowtoEmbedBanglaFontinWebPages2: TMenuItem;
    N26: TMenuItem;
    Moredocumentsontheweb2: TMenuItem;
    FreeOnlineSupport2: TMenuItem;
    N27: TMenuItem;
    GetAcrobatReader2: TMenuItem;
    AboutAvroKeyboard2: TMenuItem;
    N28: TMenuItem;
    Exit2: TMenuItem;
    Popup_Tray: TPopupMenu;
    MenuItem26: TMenuItem;
    ogglekeyboardmode2: TMenuItem;
    RestoreAvroTopBar1: TMenuItem;
    N29: TMenuItem;
    Selectkeyboardlayout2: TMenuItem;
    AvroMouseClicknType4: TMenuItem;
    Ontheweb2: TMenuItem;
    N30: TMenuItem;
    N31: TMenuItem;
    Helpfiles2: TMenuItem;
    AboutAvroKeyboard3: TMenuItem;
    N32: TMenuItem;
    Exit3: TMenuItem;
    CheckupdateforAvroKeyboard3: TMenuItem;
    MoreFreeDownloads3: TMenuItem;
    AvroKeyboardontheweb3: TMenuItem;
    PortableAvroKeyboardontheweb3: TMenuItem;
    wwwOmicronLabcom3: TMenuItem;
    UserForum3: TMenuItem;
    N33: TMenuItem;
    FreeBanglaFonts3: TMenuItem;
    UsefultoolsforBangla3: TMenuItem;
    AvroPhoneticEnglishtoBangla3: TMenuItem;
    N34: TMenuItem;
    Showactivekeyboardlayout3: TMenuItem;
    Configuringyoursystem3: TMenuItem;
    OTFBanglaFontscamewithAvroKeyboard3: TMenuItem;
    Helponhelp3: TMenuItem;
    N35: TMenuItem;
    BeforeYouStart3: TMenuItem;
    Overview3: TMenuItem;
    CustomizingAvroKeyboard3: TMenuItem;
    BanglaTypingwithAvroPhonetic3: TMenuItem;
    BanglaTypingwithFixedKeyboardLayouts3: TMenuItem;
    BanglaTypingwithAvroMouse3: TMenuItem;
    FrequentlyAskedQuestionsFAQ3: TMenuItem;
    N36: TMenuItem;
    CreatingEditingFixedKeyboardLayouts3: TMenuItem;
    N37: TMenuItem;
    HowtoBanglaFileFolderName3: TMenuItem;
    HowtoBanglaChat3: TMenuItem;
    HowtoSearchingwebinBangla3: TMenuItem;
    N38: TMenuItem;
    HowtoDevelopBanglaWebPage3: TMenuItem;
    HowtoEmbedBanglaFontinWebPages3: TMenuItem;
    N39: TMenuItem;
    Moredocumentsontheweb3: TMenuItem;
    FreeOnlineSupport3: TMenuItem;
    N40: TMenuItem;
    GetAcrobatReader3: TMenuItem;
    WindowCheck: TTimer;
    InternetCheck: TTimer;
    Spellcheck1: TMenuItem;
    N41: TMenuItem;
    Spellcheck2: TMenuItem;
    Spellcheck3: TMenuItem;
    N43: TMenuItem;
    IdleTimer: TTimer;
    AboutCurrentskin1: TMenuItem;
    N2: TMenuItem;
    Aboutcurrentkeyboardlayout2: TMenuItem;
    Aboutcurrentskin2: TMenuItem;
    UnicodetoBijoytextconverter1: TMenuItem;
    ools1: TMenuItem;
    N46: TMenuItem;
    AvroPhonetic2: TMenuItem;
    EnableAutoCorrect2: TMenuItem;
    ManageAutoCorrectentries2: TMenuItem;
    UnicodetoBijoytextconverter2: TMenuItem;
    KeyboardLayoutEditorBuildcustomlayouts2: TMenuItem;
    SkinDesignerDesignyourownskin2: TMenuItem;
    LayoutViewerShowactivekeyboardlayout2: TMenuItem;
    AvroMouseClicknType5: TMenuItem;
    N48: TMenuItem;
    Options2: TMenuItem;
    FixedKeyboardLayout1: TMenuItem;
    UseModernStyleTyping1: TMenuItem;
    UseOldStyleTyping1: TMenuItem;
    N1: TMenuItem;
    EnableOldStyleRephInModernTypingStyle1: TMenuItem;
    AutomaticVowelFormatingInModernTypingStyle1: TMenuItem;
    AutomaticallyfixChandrapositionInModernTypingStyle1: TMenuItem;
    EnableBanglainNumberPadInFixedkeyboardLayouts1: TMenuItem;
    FixedKeyboardLayout2: TMenuItem;
    UseModernStyleTyping2: TMenuItem;
    UseOldStyleTyping2: TMenuItem;
    N44: TMenuItem;
    EnableOldStyleRephInModernTypingStyle2: TMenuItem;
    AutomaticVowelFormatingInModernTypingStyle2: TMenuItem;
    AutomaticallyfixChandrapositionInModernTypingStyle2: TMenuItem;
    EnableBanglainNumberPadInFixedkeyboardLayouts2: TMenuItem;
    ShowPreviewWindow1: TMenuItem;
    Dictionarymodeisdefault1: TMenuItem;
    Charactermodeisdefault1: TMenuItem;
    Classicphoneticnohint1: TMenuItem;
    UseTabforBrowsingSuggestions1: TMenuItem;
    N45: TMenuItem;
    N47: TMenuItem;
    Remembermychoiceamongsuggestions1: TMenuItem;
    UseVerticalLinePipekeytotypeDot1: TMenuItem;
    TypeJoNuktawithShiftJ1: TMenuItem;
    ShowPreviewWindow2: TMenuItem;
    Dictionarymodeisdefault2: TMenuItem;
    Charactermodeisdefault2: TMenuItem;
    Classicphoneticnohint2: TMenuItem;
    UseTabforbrowsingsuggestions2: TMenuItem;
    Remembermychoiceamongsuggestions2: TMenuItem;
    N42: TMenuItem;
    UseVerticalLinePipekeytotypeDot2: TMenuItem;
    TypeJoNuktawithShiftJ2: TMenuItem;
    N49: TMenuItem;
    OutputasUnicodeRecommended1: TMenuItem;
    OutputasANSIAreyousure1: TMenuItem;
    N50: TMenuItem;
    N51: TMenuItem;
    OutputasUnicodeRecommended2: TMenuItem;
    OutputasANSIAreyousure2: TMenuItem;
    N52: TMenuItem;
    AvroKeyboardonFacebook1: TMenuItem;
    OmicronLabonTwitter1: TMenuItem;
    N53: TMenuItem;
    AvroKeyboardonFacebook2: TMenuItem;
    OmicronLabonTwitter2: TMenuItem;
    N54: TMenuItem;
    AvroKeyboardonFacebook3: TMenuItem;
    OmicronLabonTwitter3: TMenuItem;
    AppEvents: TApplicationEvents;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure AvroPhoneticEnglishtoBangla3Click(Sender: TObject);
    procedure Exit1Click(Sender: TObject);
    procedure ogglekeyboardmode2Click(Sender: TObject);
    procedure Docktotop1Click(Sender: TObject);
    procedure Showactivekeyboardlayout1Click(Sender: TObject);
    procedure AvroMouseClicknType2Click(Sender: TObject);
    procedure PortableAvroKeyboardontheweb1Click(Sender: TObject);
    procedure AvroKeyboardontheweb1Click(Sender: TObject);
    procedure wwwOmicronLabcom1Click(Sender: TObject);
    procedure UserForum1Click(Sender: TObject);
    procedure CheckupdateforAvroKeyboard1Click(Sender: TObject);
    procedure FreeBanglaFonts1Click(Sender: TObject);
    procedure UsefultoolsforBangla1Click(Sender: TObject);
    procedure Jumptosystemtray1Click(Sender: TObject);
    procedure Options1Click(Sender: TObject);
    procedure Configuringyoursystem1Click(Sender: TObject);
    procedure OTFBanglaFontscamewithAvroKeyboard1Click(Sender: TObject);
    procedure Helponhelp1Click(Sender: TObject);
    procedure BeforeYouStart1Click(Sender: TObject);
    procedure Overview1Click(Sender: TObject);
    procedure CustomizingAvroKeyboard1Click(Sender: TObject);
    procedure BanglaTypingwithAvroPhonetic1Click(Sender: TObject);
    procedure BanglaTypingwithFixedKeyboardLayouts1Click(Sender: TObject);
    procedure BanglaTypingwithAvroMouse1Click(Sender: TObject);
    procedure FrequentlyAskedQuestionsFAQ1Click(Sender: TObject);
    procedure CreatingEditingFixedKeyboardLayouts1Click(Sender: TObject);
    procedure Moredocumentsontheweb1Click(Sender: TObject);
    procedure GetAcrobatReader1Click(Sender: TObject);
    procedure Aboutcurrentkeyboardlayout1Click(Sender: TObject);
    procedure AboutAvroKeyboard1Click(Sender: TObject);
    procedure RestoreAvroTopBar1Click(Sender: TObject);
    procedure EnableOldStyleRephInModernTypingStyle1Click(Sender: TObject);
    procedure UseOldStyleTyping1Click(Sender: TObject);
    procedure UseModernStyleTyping1Click(Sender: TObject);
    procedure AutomaticallyfixChandrapositionInModernTypingStyle1Click(Sender: TObject);
    procedure AutomaticVowelFormatingInModernTypingStyle1Click(Sender: TObject);
    procedure EnableBanglainNumberPadInFixedkeyboardLayouts1Click(Sender: TObject);
    procedure EnableAutoCorrect1Click(Sender: TObject);
    procedure ManageAutoCorrectentries1Click(Sender: TObject);
    procedure KeyboardLayoutEditorBuildcustomlayouts1Click(Sender: TObject);
    procedure SkinDesignerDesignyourownskin1Click(Sender: TObject);
    procedure InternetCheckTimer(Sender: TObject);
    procedure TrayDblClick(Sender: TObject);
    procedure TrayClick(Sender: TObject);
    procedure WindowCheckTimer(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Spellcheck1Click(Sender: TObject);
    procedure IdleTimerTimer(Sender: TObject);
    procedure AboutCurrentskin1Click(Sender: TObject);
    procedure UnicodetoBijoytextconverter1Click(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure ShowPreviewWindow1Click(Sender: TObject);
    procedure Dictionarymodeisdefault1Click(Sender: TObject);
    procedure Charactermodeisdefault1Click(Sender: TObject);
    procedure Classicphoneticnohint1Click(Sender: TObject);
    procedure UseTabforBrowsingSuggestions1Click(Sender: TObject);
    procedure Remembermychoiceamongsuggestions1Click(Sender: TObject);
    procedure UseVerticalLinePipekeytotypeDot1Click(Sender: TObject);
    procedure TypeJoNuktawithShiftJ1Click(Sender: TObject);
    procedure OutputasUnicodeRecommended1Click(Sender: TObject);
    procedure OutputasANSIAreyousure1Click(Sender: TObject);
    procedure AvroKeyboardonFacebook1Click(Sender: TObject);
    procedure OmicronLabonTwitter1Click(Sender: TObject);
    procedure AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
    private
      { Private declarations }
      WindowDict:            TDictionary<HWND, TWindowRecord>;
      MyCurrentLayout:       string;
      MyCurrentKeyboardMode: enumMode;
      LastWindow:            HWND;
      PendingANSISwitch:     Boolean;
      PreviousModeBeforeANSISwitch: enumMode;

      procedure ChangeTypingStyle(const sStyle: string);
      function IgnorableWindow(const lngHWND: HWND): Boolean;

      procedure ToggleAutoCorrect;
      procedure ToggleFixChandra;
      procedure ToggleNumPadBangla;
      procedure ToggleOldStyleReph;
      procedure ToggleVowelFormat;
      procedure LoadApp;
      procedure MenuFixedLayoutClick(Sender: TObject);
      procedure KeyLayout_KeyboardLayoutChanged(CurrentKeyboardLayout: string);
      procedure KeyLayout_KeyboardModeChanged(CurrentMode: enumMode);
      procedure UpdateTrayIcon;

      procedure HandleThemes;
      procedure BuildAnsiVersionMenus;
      procedure AnsiVersionMenuClick(Sender: TObject);
      procedure ImportAnsiMappingClick(Sender: TObject);
      procedure ExportAnsiMappingClick(Sender: TObject);
      procedure DeleteAnsiMappingClick(Sender: TObject);
      procedure OpenAnsiMappingDirClick(Sender: TObject);
      procedure IgnoreCapsLockClick(Sender: TObject);

      procedure WMCopyData(var Msg: TWMCopyData); message WM_COPYDATA;
    public
      { Public declarations }
      KeyboardModeChanged: Boolean;
      KeyLayout:           TLayout;
      Updater:             TUpdateCheck;
      AnsiVersionSubmenu1: TMenuItem;
      AnsiVersionSubmenu2: TMenuItem;
      IgnoreCapsLock1: TMenuItem;
      IgnoreCapsLock2: TMenuItem;

      function GetMyCurrentKeyboardMode: enumMode;
      procedure ExitApp;
      function GetMyCurrentLayout: string;
      procedure RefreshSettings;
      procedure SwitchLocaleToMatchMode;
      procedure RestoreFromTray;
      procedure OpenHelpFile(const HelpID: Integer);
      procedure ShowOnTray;
      procedure ToggleMode;
      procedure SetBengaliUnicodeMode;
      procedure SetBengaliANSIMode;
      procedure TopBarDocToTop;
      function TransferKeyDown(const KeyCode: Integer; var Block: Boolean): string;
      procedure TransferKeyUp(const KeyCode: Integer; var Block: Boolean);
      procedure TrimAppMemorySize;
      procedure Initmenu;
      procedure ToggleOutputEncoding;
      procedure ApplyPendingANSISwitchRevert;
      procedure PendingANSISwitchClear;
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  AvroMainForm1: TAvroMainForm1;

implementation

{$R *.dfm}

uses
  uRegistrySettings,
  uProcessHandler,
  uAutoCorrect,
  KeyboardLayoutLoader,
  uFileFolderHandling,
  clsUnicodeToBijoy2000,
  WindowsVersion,
  uWindowHandlers,
  uTopBar,
  uLayoutViewer,
  ufrmAvroMouse,
  ufrmOptions,
  ufrmAboutSkinLayout,
  ufrmAbout,
  ufrmAutoCorrect,
  clsRegistry_XMLSetting,
  KeyboardHook,
  uFrmSplash,
  ufrmPrevW,
  uDBase,
  SkinLoader,
  u_VirtualFontInstall,
  ufrmEncodingWarning,
  DebugLog,
  WindowsDarkMode,
  System.UITypes;

{ =============================================================================== }

procedure TAvroMainForm1.AboutAvroKeyboard1Click(Sender: TObject);
begin
  CheckCreateForm(TfrmAbout, frmAbout, 'frmAbout');
  frmAbout.Show;
end;

procedure TAvroMainForm1.Aboutcurrentkeyboardlayout1Click(Sender: TObject);
var
  KeyboardLayoutPath, KeyboardLayout: string;
begin
  KeyboardLayout := AvroMainForm1.GetMyCurrentLayout;
  if Lowercase(KeyboardLayout) = 'avrophonetic*' then
    KeyboardLayoutPath := KeyboardLayout
  else
    KeyboardLayoutPath := GetAvroDataDir + 'Keyboard Layouts\' + KeyboardLayout + '.avrolayout';

  ShowLayoutDescription(KeyboardLayoutPath);
end;

procedure TAvroMainForm1.AboutCurrentskin1Click(Sender: TObject);
var
  SkinPath: string;
begin
  if Lowercase(InterfaceSkin) = 'internalskin*' then
    SkinPath := InterfaceSkin
  else
    SkinPath := GetAvroDataDir + 'Skin\' + InterfaceSkin + '.avroskin';

  GetSkinDescription(SkinPath);
end;

procedure TAvroMainForm1.AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
begin
  if SameText('ImmersiveColorSet', string(Section)) then
    HandleThemes;
end;

procedure TAvroMainForm1.AutomaticallyfixChandrapositionInModernTypingStyle1Click(Sender: TObject);
begin
  ToggleFixChandra;
end;

procedure TAvroMainForm1.AutomaticVowelFormatingInModernTypingStyle1Click(Sender: TObject);
begin
  ToggleVowelFormat;
end;

procedure TAvroMainForm1.AvroKeyboardonFacebook1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=39');
end;

procedure TAvroMainForm1.AvroKeyboardontheweb1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=1');
end;

procedure TAvroMainForm1.AvroMouseClicknType2Click(Sender: TObject);
begin
  CheckCreateForm(TfrmAvroMouse, frmAvroMouse, 'frmAvroMouse');
  frmAvroMouse.Show;
end;

procedure TAvroMainForm1.AvroPhoneticEnglishtoBangla3Click(Sender: TObject);
begin
  KeyLayout.CurrentKeyboardLayout := 'avrophonetic*';
end;

procedure TAvroMainForm1.BanglaTypingwithAvroMouse1Click(Sender: TObject);
begin
  OpenHelpFile(28);
end;

procedure TAvroMainForm1.BanglaTypingwithAvroPhonetic1Click(Sender: TObject);
begin
  OpenHelpFile(26);
end;

procedure TAvroMainForm1.BanglaTypingwithFixedKeyboardLayouts1Click(Sender: TObject);
begin
  OpenHelpFile(27);
end;

procedure TAvroMainForm1.BeforeYouStart1Click(Sender: TObject);
begin
  OpenHelpFile(23);
end;

procedure TAvroMainForm1.ChangeTypingStyle(const sStyle: string);
begin
  if Lowercase(sStyle) = Lowercase('ModernStyle') then
    FullOldStyleTyping := 'NO'
  else if Lowercase(sStyle) = Lowercase('OldStyle') then
    FullOldStyleTyping := 'YES';
  RefreshSettings;
end;

procedure TAvroMainForm1.Charactermodeisdefault1Click(Sender: TObject);
begin
  PhoneticMode := 'CHAR';
  RefreshSettings;
end;

procedure TAvroMainForm1.CheckupdateforAvroKeyboard1Click(Sender: TObject);
begin
  Updater.Check;
  AvroUpdateLastCheck := Now;
end;

procedure TAvroMainForm1.Classicphoneticnohint1Click(Sender: TObject);
begin
  PhoneticMode := 'ONLYCHAR';
  RefreshSettings;
end;

procedure TAvroMainForm1.Configuringyoursystem1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Configuring_system.htm');
end;

procedure TAvroMainForm1.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.ExStyle := Params.ExStyle or WS_EX_TOOLWINDOW and not WS_EX_APPWINDOW;
end;

procedure TAvroMainForm1.CreatingEditingFixedKeyboardLayouts1Click(Sender: TObject);
begin
  OpenHelpFile(35);
end;

procedure TAvroMainForm1.CustomizingAvroKeyboard1Click(Sender: TObject);
begin
  OpenHelpFile(25);
end;

procedure TAvroMainForm1.Dictionarymodeisdefault1Click(Sender: TObject);
begin
  PhoneticMode := 'DICT';
  RefreshSettings;
end;

procedure TAvroMainForm1.Docktotop1Click(Sender: TObject);
begin
  TopBarDocToTop;
end;

{ =============================================================================== }

procedure TAvroMainForm1.EnableAutoCorrect1Click(Sender: TObject);
begin
  ToggleAutoCorrect;
end;

procedure TAvroMainForm1.EnableBanglainNumberPadInFixedkeyboardLayouts1Click(Sender: TObject);
begin
  ToggleNumPadBangla;
end;

procedure TAvroMainForm1.EnableOldStyleRephInModernTypingStyle1Click(Sender: TObject);
begin
  ToggleOldStyleReph;
end;

procedure TAvroMainForm1.Exit1Click(Sender: TObject);
begin
  Self.Close;
end;

procedure TAvroMainForm1.ExitApp;
begin
  {$IFDEF PortableOn}
  RemoveVirtualFont(ExtractFilePath(Application.ExeName) + 'Virtual Font\Siyamrupali.ttf');
  Log('Portable: RemoveVirtualFont');
  {$ENDIF}
  SaveSettings;
  Log('SaveSettings');

  WindowCheck.Enabled := False;
  InternetCheck.Enabled := False;
  Log('Disabled timers: WindowCheck, InternetCheck');

  Tray.Visible := False;
  Log('Tray invisible');

  FreeAndNil(WindowDict);
  FreeAndNil(KeyLayout);
  Log('FreeAndNil: WindowDict, KeyLayout');
  RemoveHook;
  Log('RemoveHook');
  FreeAndNil(Updater);
  Log('FreeAndNil: Updater');

  DestroyDict;
  Log('DestroyDict');
  Destroy_KeyboardLayoutData;
  Log('Destroy_KeyboardLayoutData');
  FreeAndNil(KeyboardLayouts);
  Log('FreeAndNil: KeyboardLayouts');
  UnloadWordDatabase;
  Log('UnloadWordDatabase');

  Topbar.ApplicationClosing := True;
  Log('Topbar.ApplicationClosing := True');

  if Assigned(Topbar) then
  begin
    Topbar.Close;
    Log('Topbar.Close');
  end;

  if Assigned(frmPrevW) then
  begin
    frmPrevW.Close;
    Log('frmPrevW.Close');
  end;

  Application.Terminate;
  Log('Application.Terminate');

  Application.ProcessMessages;
  Log('Application.ProcessMessages');
  ExitProcess(0);
  Log('ExitProcess');
end;

{ =============================================================================== }

procedure TAvroMainForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;

  AvroMainForm1 := nil;
end;

procedure TAvroMainForm1.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  ExitApp;
  CanClose := True;
end;

procedure TAvroMainForm1.FormCreate(Sender: TObject);
begin
  HandleThemes;

  // Hide the form
  Left := Screen.Width + 5000;
  Show;
  Application.ProcessMessages;

  LoadSettings;

  { TODO :
    If DontShowStartupWizard <> 'YES Then
    ConfigurationWizard.Show;
    End If }

  LoadApp;
end;

{ =============================================================================== }

procedure TAvroMainForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F4) { And (ssAlt In Shift) } then
    Key := 0;
end;

procedure TAvroMainForm1.FreeBanglaFonts1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=4');
end;

procedure TAvroMainForm1.FrequentlyAskedQuestionsFAQ1Click(Sender: TObject);
begin
  OpenHelpFile(29);
end;

{ =============================================================================== }

procedure TAvroMainForm1.GetAcrobatReader1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=13');
end;

function TAvroMainForm1.GetMyCurrentKeyboardMode: enumMode;
begin
  Result := MyCurrentKeyboardMode;
end;

{ =============================================================================== }

function TAvroMainForm1.GetMyCurrentLayout: string;
begin
  Result := MyCurrentLayout;
end;

procedure TAvroMainForm1.Helponhelp1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'help_on_help.htm');
end;

{ =============================================================================== }

{$HINTS Off}

procedure TAvroMainForm1.IdleTimerTimer(Sender: TObject);
var
  liInfo:      TLastInputInfo;
  SecondsIdle: DWord;
begin
  liInfo.cbSize := SizeOf(TLastInputInfo);
  GetLastInputInfo(liInfo);
  SecondsIdle := (GetTickCount - liInfo.dwTime) div 1000;
  if SecondsIdle > 30 then
    TrimAppMemorySize;
end;

function TAvroMainForm1.IgnorableWindow(const lngHWND: HWND): Boolean;
begin
  Result := False;

  // System tray
  if (lngHWND = FindWindow('Shell_TrayWnd', nil)) or (lngHWND = FindWindowEx(FindWindow('Shell_TrayWnd', nil), 0, 'TrayNotifyWnd', nil)) then
    Result := True
  else if lngHWND = Self.Handle then
    Result := True
  else if IsFormLoaded('TopBar') then
  begin
    if lngHWND = Topbar.Handle then
      Result := True;
  end
  else if IsFormLoaded('frmEncodingWarning') then
  begin
    if lngHWND = frmEncodingWarning.Handle then
      Result := True;
  end
  // Photoshop drag window exception
  else if GetWindowClassName(lngHWND) = 'PSDocDragFeedback' then
    Result := True;
end;

{$HINTS ON}
{ =============================================================================== }

procedure TAvroMainForm1.Initmenu;
var
  I, J:                            Integer;
  TempMenu1, TempMenu2, TempMenu3: TMenuItemExtended;
  sCaption:                        string;
  ItemFound:                       Boolean;
begin
  for I := KeyboardLayouts.Count - 1 downto 0 do
  begin

    sCaption := RemoveExtension(KeyboardLayouts[I]);

    /// ////
    ItemFound := False;
    for J := 0 to Selectkeyboardlayout1.Count - 1 do
    begin
      if Selectkeyboardlayout1.Items[J].Tag = 9903 then
        if Lowercase((Selectkeyboardlayout1.Items[J] as TMenuItemExtended).Value) = Lowercase(sCaption) then
          ItemFound := True;
    end;
    if not(ItemFound) then
    begin
      TempMenu1 := TMenuItemExtended.Create(Popup_Tray);
      TempMenu1.Caption := sCaption;
      TempMenu1.Value := sCaption;
      TempMenu1.RadioItem := True;
      TempMenu1.Tag := 9903;
      TempMenu1.OnClick := MenuFixedLayoutClick;
      Selectkeyboardlayout2.Insert(AvroPhoneticEnglishtoBangla3.MenuIndex + 1, TempMenu1);
    end;

    /// ///
    ItemFound := False;
    for J := 0 to Selectkeyboardlayout1.Count - 1 do
    begin
      if Selectkeyboardlayout1.Items[J].Tag = 9903 then
        if Lowercase((Selectkeyboardlayout1.Items[J] as TMenuItemExtended).Value) = Lowercase(sCaption) then
          ItemFound := True;
    end;
    if not(ItemFound) then
    begin
      TempMenu2 := TMenuItemExtended.Create(Popup_Main);
      TempMenu2.Caption := sCaption;
      TempMenu2.Value := sCaption;
      TempMenu2.RadioItem := True;
      TempMenu2.Tag := 9903;
      TempMenu2.OnClick := MenuFixedLayoutClick;
      Selectkeyboardlayout1.Insert(AvroPhoneticEnglishtoBangla2.MenuIndex + 1, TempMenu2);
    end;

    /// ////
    ItemFound := False;
    for J := 0 to Popup_LayoutList.Items.Count - 1 do
    begin
      if Popup_LayoutList.Items.Items[J].Tag = 9903 then
        if Lowercase((Popup_LayoutList.Items.Items[J] as TMenuItemExtended).Value) = Lowercase(sCaption) then
          ItemFound := True;
    end;
    if not(ItemFound) then
    begin
      TempMenu3 := TMenuItemExtended.Create(Popup_LayoutList);
      TempMenu3.Caption := sCaption;
      TempMenu3.Value := sCaption;
      TempMenu3.RadioItem := True;
      TempMenu3.Tag := 9903;
      TempMenu3.OnClick := MenuFixedLayoutClick;
      Popup_LayoutList.Items.Insert(AvroPhoneticEnglishtoBangla1.MenuIndex + 1, TempMenu3);
    end;
  end;

  // Create ANSI Version submenus
  AnsiVersionSubmenu1 := TMenuItem.Create(Popup_Tools);
  AnsiVersionSubmenu1.Caption := 'ANSI Output Version';
  Popup_Tools.Items.Insert(OutputasANSIAreyousure1.MenuIndex + 1, AnsiVersionSubmenu1);

  AnsiVersionSubmenu2 := TMenuItem.Create(ools1);
  AnsiVersionSubmenu2.Caption := 'ANSI Output Version';
  ools1.Insert(OutputasANSIAreyousure2.MenuIndex + 1, AnsiVersionSubmenu2);

  // Create Ignore Caps Lock toggle items
  IgnoreCapsLock1 := TMenuItem.Create(Popup_Tools);
  IgnoreCapsLock1.Caption := 'Ignore Caps Lock for Bangla typing';
  IgnoreCapsLock1.AutoCheck := False;
  IgnoreCapsLock1.Checked := (IgnoreCapsLock = 'YES');
  IgnoreCapsLock1.OnClick := IgnoreCapsLockClick;
  Popup_Tools.Items.Insert(AnsiVersionSubmenu1.MenuIndex + 1, IgnoreCapsLock1);

  IgnoreCapsLock2 := TMenuItem.Create(ools1);
  IgnoreCapsLock2.Caption := 'Ignore Caps Lock for Bangla typing';
  IgnoreCapsLock2.AutoCheck := False;
  IgnoreCapsLock2.Checked := (IgnoreCapsLock = 'YES');
  IgnoreCapsLock2.OnClick := IgnoreCapsLockClick;
  ools1.Insert(AnsiVersionSubmenu2.MenuIndex + 1, IgnoreCapsLock2);
end;

{$HINTS Off}

procedure TAvroMainForm1.InternetCheckTimer(Sender: TObject);
var
  HowMayDay: Integer;
begin
  HowMayDay := 0;
  if AvroUpdateCheck <> 'YES' then
    exit;

  try
    HowMayDay := DaysBetween(Now, AvroUpdateLastCheck);
  except
    HowMayDay := 7;
  end;

  if HowMayDay >= 7 then
  begin
    if Updater.IsConnected = False then
      exit;

    Updater.CheckSilent;
    AvroUpdateLastCheck := Now;
  end;
end;

{$HINTS On}

procedure TAvroMainForm1.Jumptosystemtray1Click(Sender: TObject);
begin
  if Topbar.Visible = True then
  begin
    Topbar.Hide;
    ShowOnTray;
  end;
end;

procedure TAvroMainForm1.KeyboardLayoutEditorBuildcustomlayouts1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Layout Editor.exe');
end;

procedure TAvroMainForm1.KeyLayout_KeyboardLayoutChanged(CurrentKeyboardLayout: string);
var
  I: Integer;
begin
  if Lowercase(CurrentKeyboardLayout) = 'avrophonetic*' then
  begin
    AvroPhoneticEnglishtoBangla3.Checked := True;
    AvroPhoneticEnglishtoBangla2.Checked := True;
    AvroPhoneticEnglishtoBangla1.Checked := True;

  end
  else
  begin
    for I := 0 to Selectkeyboardlayout2.Count - 1 do
    begin
      if Selectkeyboardlayout2.Items[I].Tag = 9903 then
        if Lowercase((Selectkeyboardlayout2.Items[I] as TMenuItemExtended).Value) = Lowercase(CurrentKeyboardLayout) then
          Selectkeyboardlayout2.Items[I].Checked := True;
    end;

    for I := 0 to Selectkeyboardlayout1.Count - 1 do
    begin
      if Selectkeyboardlayout1.Items[I].Tag = 9903 then
        if Lowercase((Selectkeyboardlayout1.Items[I] as TMenuItemExtended).Value) = Lowercase(CurrentKeyboardLayout) then
          Selectkeyboardlayout1.Items[I].Checked := True;
    end;

    for I := 0 to Popup_LayoutList.Items.Count - 1 do
    begin
      if Popup_LayoutList.Items[I].Tag = 9903 then
        if Lowercase((Popup_LayoutList.Items[I] as TMenuItemExtended).Value) = Lowercase(CurrentKeyboardLayout) then
          Popup_LayoutList.Items[I].Checked := True;
    end;

  end;
  MyCurrentLayout := CurrentKeyboardLayout;
  if IsFormLoaded('LayoutViewer') then
    LayoutViewer.UpdateLayout;
  DefaultLayout := CurrentKeyboardLayout;

  RefreshSettings;

end;

procedure TAvroMainForm1.KeyLayout_KeyboardModeChanged(CurrentMode: enumMode);
var
  hforewnd:                                         Integer;
  WindowRecord, NewWindowRecord: TWindowRecord;
begin
  { This is for Top Bar, when Keyboard Mode is changed,
    it removes transparency }
  if CurrentMode <> MyCurrentKeyboardMode then
    KeyboardModeChanged := True;
  hforewnd := GetForegroundWindow;
  SwitchLocaleToMatchMode;

  if hforewnd = 0 then
    exit;
  { Experimental use }
  if IsWindow(hforewnd) = False then
    exit;

  if IgnorableWindow(hforewnd) then
  begin
    hforewnd := LastWindow;
  end;

  if not WindowDict.TryGetValue(hforewnd, WindowRecord) then
  begin

    { This is a new window, so add it in Window collection
      update/add process information }

    if CurrentMode = bangla then
    begin
      NewWindowRecord.Mode := 'B';
      WindowDict.AddOrSetValue(hforewnd, NewWindowRecord);
      MyCurrentKeyboardMode := bangla;
    end
    else if CurrentMode = SysDefault then
    begin
      NewWindowRecord.Mode := 'S';
      WindowDict.AddOrSetValue(hforewnd, NewWindowRecord);

      MyCurrentKeyboardMode := SysDefault;
    end;
  end
  else
  begin
    // The window already exist, so update information
    if CurrentMode = bangla then
    begin
      NewWindowRecord.Mode := 'B';
      WindowDict.AddOrSetValue(hforewnd, NewWindowRecord);

      MyCurrentKeyboardMode := bangla;
    end
    else if CurrentMode = SysDefault then
    begin
      NewWindowRecord.Mode := 'S';
      WindowDict.AddOrSetValue(hforewnd, NewWindowRecord);

      MyCurrentKeyboardMode := SysDefault;

      WindowDict.Remove(hforewnd);
    end;
  end;

  { Update user interface }
  UpdateTrayIcon;

end;

{ =============================================================================== }

procedure TAvroMainForm1.SwitchLocaleToMatchMode;
var
  hforewnd: Integer;
begin
  hforewnd := GetForegroundWindow;
  if (hforewnd = 0) or (not IsWindow(hforewnd)) then
    exit;

  if KeyLayout.KeyboardMode = bangla then
  begin
    if OutputIsBijoy = 'YES' then
      ChangeLocaleToEnglish(hforewnd)
    else if EnableLocaleChange = 'YES' then
      ChangeLocaleToBangla(hforewnd);
  end
  else if KeyLayout.KeyboardMode = SysDefault then
    ChangeLocaleToEnglish(hforewnd);
end;

procedure TAvroMainForm1.LoadApp;
var
  tempLastUIMode: string;
begin
  Set_Process_Priority(HIGH_PRIORITY_CLASS);

  InitDict;
  LoadKeyboardLayoutNames;
  Initmenu;

  Updater := TUpdateCheck.Create;
  WindowDict := TDictionary<HWND, TWindowRecord>.Create;
  WindowCheck.Enabled := True;

  Topbar := TTopBar.Create(Application);
  Topbar.ApplicationClosing := False;

  { To solve focus loosing
    problem of Preview window }
  frmPrevW := TfrmPrevW.Create(Application);

  tempLastUIMode := LastUIMode;
  KeyLayout := TLayout.Create;
  KeyLayout.OnKeyboardLayoutChanged := KeyLayout_KeyboardLayoutChanged;
  KeyLayout.OnKeyboardModeChanged := KeyLayout_KeyboardModeChanged;
  KeyLayout.CurrentKeyboardLayout := DefaultLayout;
  LastUIMode := tempLastUIMode;

  if DefaultUIMode = 'TOP BAR' then
  begin
    Topbar.Visible := True;
    Tray.Visible := False;
  end
  else if DefaultUIMode = 'ICON' then
  begin
    Topbar.Hide;
    ShowOnTray;
  end
  else if DefaultUIMode = 'LASTUI' then
  begin
    if LastUIMode = 'TOP BAR' then
    begin
      Topbar.Visible := True;
      Tray.Visible := False;
    end
    else if LastUIMode = 'ICON' then
    begin
      Topbar.Hide;
      ShowOnTray;
    end
    else
    begin
      Topbar.Visible := True;
      Tray.Visible := False;
    end;
  end
  else
  begin
    Topbar.Visible := True;
    Tray.Visible := False;
  end;

  {$IFDEF PortableOn}
  InstallVirtualFont(ExtractFilePath(Application.ExeName) + 'Virtual Font\Siyamrupali.ttf');

  {$ENDIF}
  if AvroUpdateCheck = 'YES' then
    InternetCheck.Enabled := True
  else
    InternetCheck.Enabled := False;

  if (ShowOutputwarning <> 'NO') and (OutputIsBijoy = 'YES') then
  begin
    CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
    frmEncodingWarning.ShowModal;
    RefreshSettings;
  end;

  Application.ProcessMessages;
  if ShowSplash = 'YES' then
  begin
    frmSplash := TfrmSplash.Create(Application);
    frmSplash.Show;
  end;

end;

procedure TAvroMainForm1.ManageAutoCorrectentries1Click(Sender: TObject);
begin
  CheckCreateForm(TfrmAutoCorrect, frmAutoCorrect, 'frmAutoCorrect');
  frmAutoCorrect.Show;
end;

procedure TAvroMainForm1.MenuFixedLayoutClick(Sender: TObject);
begin
  KeyLayout.CurrentKeyboardLayout := (Sender as TMenuItemExtended).Value;
end;

procedure TAvroMainForm1.Moredocumentsontheweb1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=12');
end;

procedure TAvroMainForm1.ogglekeyboardmode2Click(Sender: TObject);
begin
  KeyLayout.ToggleMode;
end;

{ =============================================================================== }

procedure TAvroMainForm1.OmicronLabonTwitter1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=40');
end;

{ =============================================================================== }

procedure TAvroMainForm1.OpenHelpFile(const HelpID: Integer);
begin
  case HelpID of
    23:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Before You Start.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Before You Start.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    24:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Overview.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Overview.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    25:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Customizing Avro Keyboard.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Customizing Avro Keyboard.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    26:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Avro Phonetic.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Avro Phonetic.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    27:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Fixed Keyboard Layouts.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Fixed Keyboard Layouts.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    28:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Avro Mouse.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Bangla Typing with Avro Mouse.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    29:
      if FileExists(ExtractFilePath(Application.ExeName) + 'faq.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'faq.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));

    35:
      if FileExists(ExtractFilePath(Application.ExeName) + 'Editing Keyboard Layout.pdf') then
        Execute_Something(ExtractFilePath(Application.ExeName) + 'Editing Keyboard Layout.pdf')
      else
        Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));
  end;
end;

procedure TAvroMainForm1.Options1Click(Sender: TObject);
begin
  CheckCreateForm(TfrmOptions, frmOptions, 'frmOptions');
  frmOptions.Show;
end;

procedure TAvroMainForm1.OTFBanglaFontscamewithAvroKeyboard1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'open_type_font_list.htm');
end;

procedure TAvroMainForm1.OutputasANSIAreyousure1Click(Sender: TObject);
begin
  if ShowOutputwarning <> 'NO' then
  begin
    CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
    frmEncodingWarning.Show;
  end
  else
    OutputIsBijoy := 'YES';

  SwitchLocaleToMatchMode;
  RefreshSettings;
end;

procedure TAvroMainForm1.OutputasUnicodeRecommended1Click(Sender: TObject);
begin
  OutputIsBijoy := 'NO';
  RefreshSettings;
end;

procedure TAvroMainForm1.Overview1Click(Sender: TObject);
begin
  OpenHelpFile(24);
end;

{ =============================================================================== }

procedure TAvroMainForm1.PortableAvroKeyboardontheweb1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=22');
end;

{ =============================================================================== }

procedure TAvroMainForm1.RefreshSettings;
begin

  // Update Spell Checker Shortcut in Menu
  Spellcheck1.ShortCut := TextToShortcut('Ctrl+' + SpellerLauncherKey);
  Spellcheck2.ShortCut := TextToShortcut('Ctrl+' + SpellerLauncherKey);
  Spellcheck3.ShortCut := TextToShortcut('Ctrl+' + SpellerLauncherKey);

  if VowelFormating = 'NO' then
  begin
    AutomaticVowelFormatingInModernTypingStyle1.Checked := False;
    AutomaticVowelFormatingInModernTypingStyle2.Checked := False;
  end
  else
  begin
    AutomaticVowelFormatingInModernTypingStyle1.Checked := True;
    AutomaticVowelFormatingInModernTypingStyle2.Checked := True;
  end;

  if OldStyleReph = 'NO' then
  begin
    EnableOldStyleRephInModernTypingStyle1.Checked := False;
    EnableOldStyleRephInModernTypingStyle2.Checked := False;
  end
  else
  begin
    EnableOldStyleRephInModernTypingStyle1.Checked := True;
    EnableOldStyleRephInModernTypingStyle2.Checked := True;
  end;

  if NumPadBangla = 'NO' then
  begin
    EnableBanglainNumberPadInFixedkeyboardLayouts1.Checked := False;
    EnableBanglainNumberPadInFixedkeyboardLayouts2.Checked := False;
  end
  else
  begin
    EnableBanglainNumberPadInFixedkeyboardLayouts1.Checked := True;
    EnableBanglainNumberPadInFixedkeyboardLayouts2.Checked := True;
  end;

  if ShowPrevWindow = 'YES' then
  begin
    ShowPreviewWindow1.Checked := True;
    ShowPreviewWindow2.Checked := True;

    Dictionarymodeisdefault1.Enabled := True;
    Dictionarymodeisdefault2.Enabled := True;
    Charactermodeisdefault1.Enabled := True;
    Charactermodeisdefault2.Enabled := True;
    Classicphoneticnohint1.Enabled := True;
    Classicphoneticnohint2.Enabled := True;
    UseTabforBrowsingSuggestions1.Enabled := True;
    UseTabforbrowsingsuggestions2.Enabled := True;
    Remembermychoiceamongsuggestions1.Enabled := True;
    Remembermychoiceamongsuggestions2.Enabled := True;
  end
  else
  begin
    ShowPreviewWindow1.Checked := False;
    ShowPreviewWindow2.Checked := False;

    Dictionarymodeisdefault1.Enabled := False;
    Dictionarymodeisdefault2.Enabled := False;
    Charactermodeisdefault1.Enabled := False;
    Charactermodeisdefault2.Enabled := False;
    Classicphoneticnohint1.Enabled := False;
    Classicphoneticnohint2.Enabled := False;
    UseTabforBrowsingSuggestions1.Enabled := False;
    UseTabforbrowsingsuggestions2.Enabled := False;
    Remembermychoiceamongsuggestions1.Enabled := False;
    Remembermychoiceamongsuggestions2.Enabled := False;
  end;

  if Lowercase(MyCurrentLayout) = 'avrophonetic*' then
  begin
    UseModernStyleTyping1.Enabled := False;
    UseModernStyleTyping2.Enabled := False;
    UseOldStyleTyping1.Enabled := False;
    UseOldStyleTyping2.Enabled := False;
    EnableOldStyleRephInModernTypingStyle1.Enabled := False;
    EnableOldStyleRephInModernTypingStyle2.Enabled := False;
    AutomaticVowelFormatingInModernTypingStyle1.Enabled := False;
    AutomaticVowelFormatingInModernTypingStyle2.Enabled := False;
    AutomaticallyfixChandrapositionInModernTypingStyle1.Enabled := False;
    AutomaticallyfixChandrapositionInModernTypingStyle2.Enabled := False;
    EnableBanglainNumberPadInFixedkeyboardLayouts1.Enabled := False;
    EnableBanglainNumberPadInFixedkeyboardLayouts2.Enabled := False;

    ShowPreviewWindow1.Enabled := True;
    ShowPreviewWindow2.Enabled := True;
    Dictionarymodeisdefault1.Enabled := True;
    Dictionarymodeisdefault2.Enabled := True;
    Charactermodeisdefault1.Enabled := True;
    Charactermodeisdefault2.Enabled := True;
    Classicphoneticnohint1.Enabled := True;
    Classicphoneticnohint2.Enabled := True;
    UseTabforBrowsingSuggestions1.Enabled := True;
    UseTabforbrowsingsuggestions2.Enabled := True;
    Remembermychoiceamongsuggestions1.Enabled := True;
    Remembermychoiceamongsuggestions2.Enabled := True;
    UseVerticalLinePipekeytotypeDot1.Enabled := True;
    UseVerticalLinePipekeytotypeDot2.Enabled := True;
    TypeJoNuktawithShiftJ1.Enabled := True;
    TypeJoNuktawithShiftJ2.Enabled := True;

    EnableAutoCorrect1.Enabled := True;
    EnableAutoCorrect2.Enabled := True;
    ManageAutoCorrectentries1.Enabled := True;
    ManageAutoCorrectentries2.Enabled := True;

    if ShowPrevWindow = 'NO' then
      UnloadWordDatabase
    else
    begin
      if PhoneticMode = 'ONLYCHAR' then
        UnloadWordDatabase
      else
        LoadWordDatabase;
    end;
  end
  else
  begin
    UseModernStyleTyping1.Enabled := True;
    UseModernStyleTyping2.Enabled := True;
    UseOldStyleTyping1.Enabled := True;
    UseOldStyleTyping2.Enabled := True;

    if FullOldStyleTyping = 'NO' then
    begin
      UseOldStyleTyping1.Checked := False;
      UseOldStyleTyping2.Checked := False;
      UseModernStyleTyping1.Checked := True;
      UseModernStyleTyping2.Checked := True;
      EnableOldStyleRephInModernTypingStyle1.Enabled := True;
      EnableOldStyleRephInModernTypingStyle2.Enabled := True;
      AutomaticVowelFormatingInModernTypingStyle1.Enabled := True;
      AutomaticVowelFormatingInModernTypingStyle2.Enabled := True;
      AutomaticallyfixChandrapositionInModernTypingStyle1.Enabled := True;
      AutomaticallyfixChandrapositionInModernTypingStyle2.Enabled := True;
    end
    else
    begin
      UseOldStyleTyping1.Checked := True;
      UseOldStyleTyping2.Checked := True;
      UseModernStyleTyping1.Checked := False;
      UseModernStyleTyping2.Checked := False;
      EnableOldStyleRephInModernTypingStyle1.Enabled := False;
      EnableOldStyleRephInModernTypingStyle2.Enabled := False;
      AutomaticVowelFormatingInModernTypingStyle1.Enabled := False;
      AutomaticVowelFormatingInModernTypingStyle2.Enabled := False;
      AutomaticallyfixChandrapositionInModernTypingStyle1.Enabled := False;
      AutomaticallyfixChandrapositionInModernTypingStyle2.Enabled := False;
    end;

    EnableBanglainNumberPadInFixedkeyboardLayouts1.Enabled := True;
    EnableBanglainNumberPadInFixedkeyboardLayouts2.Enabled := True;

    ShowPreviewWindow1.Enabled := False;
    ShowPreviewWindow2.Enabled := False;
    Dictionarymodeisdefault1.Enabled := False;
    Dictionarymodeisdefault2.Enabled := False;
    Charactermodeisdefault1.Enabled := False;
    Charactermodeisdefault2.Enabled := False;
    Classicphoneticnohint1.Enabled := False;
    Classicphoneticnohint2.Enabled := False;
    UseTabforBrowsingSuggestions1.Enabled := False;
    UseTabforbrowsingsuggestions2.Enabled := False;
    Remembermychoiceamongsuggestions1.Enabled := False;
    Remembermychoiceamongsuggestions2.Enabled := False;
    UseVerticalLinePipekeytotypeDot1.Enabled := False;
    UseVerticalLinePipekeytotypeDot2.Enabled := False;
    TypeJoNuktawithShiftJ1.Enabled := False;
    TypeJoNuktawithShiftJ2.Enabled := False;

    EnableAutoCorrect1.Enabled := False;
    EnableAutoCorrect2.Enabled := False;
    ManageAutoCorrectentries1.Enabled := False;
    ManageAutoCorrectentries2.Enabled := False;

    UnloadWordDatabase;
  end;

  if PhoneticMode = 'DICT' then
  begin
    Dictionarymodeisdefault1.Checked := True;
    Dictionarymodeisdefault2.Checked := True;
    Charactermodeisdefault1.Checked := False;
    Charactermodeisdefault2.Checked := False;
    Classicphoneticnohint1.Checked := False;
    Classicphoneticnohint2.Checked := False;
  end
  else if PhoneticMode = 'CHAR' then
  begin
    Dictionarymodeisdefault1.Checked := False;
    Dictionarymodeisdefault2.Checked := False;
    Charactermodeisdefault1.Checked := True;
    Charactermodeisdefault2.Checked := True;
    Classicphoneticnohint1.Checked := False;
    Classicphoneticnohint2.Checked := False;
  end
  else if PhoneticMode = 'ONLYCHAR' then
  begin
    Dictionarymodeisdefault1.Checked := False;
    Dictionarymodeisdefault2.Checked := False;
    Charactermodeisdefault1.Checked := False;
    Charactermodeisdefault2.Checked := False;
    Classicphoneticnohint1.Checked := True;
    Classicphoneticnohint2.Checked := True;
  end;

  if SaveCandidate = 'YES' then
  begin
    Remembermychoiceamongsuggestions1.Checked := True;
    Remembermychoiceamongsuggestions2.Checked := True;
  end
  else
  begin
    Remembermychoiceamongsuggestions1.Checked := False;
    Remembermychoiceamongsuggestions2.Checked := False;
  end;

  if TabBrowsing = 'YES' then
  begin
    UseTabforBrowsingSuggestions1.Checked := True;
    UseTabforbrowsingsuggestions2.Checked := True;
  end
  else
  begin
    UseTabforBrowsingSuggestions1.Checked := False;
    UseTabforbrowsingsuggestions2.Checked := False;
  end;

  if PipeToDot = 'YES' then
  begin
    UseVerticalLinePipekeytotypeDot1.Checked := True;
    UseVerticalLinePipekeytotypeDot2.Checked := True;
  end
  else
  begin
    UseVerticalLinePipekeytotypeDot1.Checked := False;
    UseVerticalLinePipekeytotypeDot2.Checked := False;
  end;

  if EnableJoNukta = 'YES' then
  begin
    TypeJoNuktawithShiftJ1.Checked := True;
    TypeJoNuktawithShiftJ2.Checked := True;
  end
  else
  begin
    TypeJoNuktawithShiftJ1.Checked := False;
    TypeJoNuktawithShiftJ2.Checked := False;
  end;

  if AutomaticallyFixChandra = 'NO' then
  begin
    AutomaticallyfixChandrapositionInModernTypingStyle1.Checked := False;
    AutomaticallyfixChandrapositionInModernTypingStyle2.Checked := False;
  end
  else
  begin
    AutomaticallyfixChandrapositionInModernTypingStyle1.Checked := True;
    AutomaticallyfixChandrapositionInModernTypingStyle2.Checked := True;
  end;

  if IsFormLoaded('LayoutViewer') then
    LayoutViewer.SetMyZOrder;

  if PhoneticAutoCorrect = 'YES' then
  begin
    EnableAutoCorrect1.Checked := True;
    EnableAutoCorrect2.Checked := True;
    KeyLayout.AutoCorrectEnabled := True;
  end
  else
  begin
    EnableAutoCorrect1.Checked := False;
    EnableAutoCorrect2.Checked := False;
    KeyLayout.AutoCorrectEnabled := False;
  end;

  Topbar.ApplySkin;

  if TopBarTransparent = 'YES' then
    Topbar.TransparencyTimer.Enabled := True
  else
    Topbar.TransparencyTimer.Enabled := False;

  if AvroUpdateCheck = 'YES' then
    InternetCheck.Enabled := True
  else
    InternetCheck.Enabled := False;

  if OutputIsBijoy = 'YES' then
  begin
    OutputasANSIAreyousure1.Checked := True;
    OutputasANSIAreyousure2.Checked := True;
    OutputasUnicodeRecommended1.Checked := False;
    OutputasUnicodeRecommended2.Checked := False;
  end
  else
  begin
    OutputasUnicodeRecommended1.Checked := True;
    OutputasUnicodeRecommended2.Checked := True;
    OutputasANSIAreyousure1.Checked := False;
    OutputasANSIAreyousure2.Checked := False;
  end;

  // ANSI Mapping version
  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiMappingDir);
  LoadCurrentActiveMapping;
  BuildAnsiVersionMenus;

  IgnoreCapsLock1.Checked := (IgnoreCapsLock = 'YES');
  IgnoreCapsLock2.Checked := (IgnoreCapsLock = 'YES');

  UpdateTrayIcon;
  SaveUISettings;

end;

procedure TAvroMainForm1.Remembermychoiceamongsuggestions1Click(Sender: TObject);
begin
  if SaveCandidate = 'YES' then
    SaveCandidate := 'NO'
  else
    SaveCandidate := 'YES';

  RefreshSettings;
end;

procedure TAvroMainForm1.HandleThemes;
begin
  SetAppropriateThemeMode('Windows10 Dark', 'Windows10');
end;

procedure TAvroMainForm1.RestoreAvroTopBar1Click(Sender: TObject);
begin
  RestoreFromTray;
end;

procedure TAvroMainForm1.RestoreFromTray;
begin
  if Topbar.Visible = False then
  begin

    if KeyLayout.KeyboardMode = bangla then
      Topbar.SetButtonModeState(State2)
    else if KeyLayout.KeyboardMode = SysDefault then
      Topbar.SetButtonModeState(State1);

    Tray.Visible := False;
    { Setasmainform(TopBar); }{ Required to maintain Topbar's Topmost behaviour }
    SaveUISettings;
    Topbar.Visible := True;
    // SetForegroundWindow(TopBar.Handle);

  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.Showactivekeyboardlayout1Click(Sender: TObject);
begin
  CheckCreateForm(TLayoutViewer, LayoutViewer, 'LayoutViewer');
  LayoutViewer.Show;
end;

procedure TAvroMainForm1.UpdateTrayIcon;
var
  ICN: TIcon;
begin
  if IsFormVisible('TopBar') = False then
  begin
    ICN := TIcon.Create;
    if KeyLayout.KeyboardMode = bangla then
    begin
      if IsWin2000 = True then
        ImageList1.GetIcon(14, ICN)
      else
      begin
        if OutputIsBijoy = 'YES' then
          ImageList1.GetIcon(30, ICN)
        else
          ImageList1.GetIcon(20, ICN);
      end;

      if OutputIsBijoy = 'YES' then
        Tray.Hint := 'Avro Keyboard.' + #13 + 'Running Bangla Keyboard Mode (ANSI/Bijoy Output).' + #13 + 'Press ' + ModeSwitchKey + ' to switch to System default.'
      else
        Tray.Hint := 'Avro Keyboard.' + #13 + 'Running Bangla Keyboard Mode.' + #13 + 'Press ' + ModeSwitchKey + ' to switch to System default.';
    end
    else if KeyLayout.KeyboardMode = SysDefault then
    begin
      if IsWin2000 = True then
        ImageList1.GetIcon(19, ICN)
      else
        ImageList1.GetIcon(21, ICN);

      Tray.Hint := 'Avro Keyboard.' + #13 + 'Running System default Keyboard Mode.' + #13 + 'Press ' + ModeSwitchKey + ' to switch to Bangla.';
    end;
    Tray.Icon := ICN;
    ICN.Free;
  end
  else
  begin
    if KeyLayout.KeyboardMode = bangla then
      Topbar.SetButtonModeState(State2)
    else if KeyLayout.KeyboardMode = SysDefault then
      Topbar.SetButtonModeState(State1);
  end;
end;

procedure TAvroMainForm1.ShowOnTray;
begin
  UpdateTrayIcon;
  Tray.Visible := True;

  if StrToInt(TrayHintShowTimes) < NumberOfVisibleHints then
  begin
    Tray.BalloonHint := 'Avro Keyboard is running here.';
    Tray.BalloonTimeout := 5000;
    Tray.BalloonTitle := 'Avro Keyboard';
    Tray.ShowBalloonHint;
    TrayHintShowTimes := IntToStr(StrToInt(TrayHintShowTimes) + 1);
  end;

  SaveUISettings;
end;

procedure TAvroMainForm1.ShowPreviewWindow1Click(Sender: TObject);
begin
  if ShowPrevWindow = 'YES' then
    ShowPrevWindow := 'NO'
  else
    ShowPrevWindow := 'YES';

  RefreshSettings;
end;

procedure TAvroMainForm1.SkinDesignerDesignyourownskin1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Skin Designer.exe');
end;

procedure TAvroMainForm1.Spellcheck1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Avro Spell checker.exe');
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleAutoCorrect;
begin
  if PhoneticAutoCorrect = 'YES' then
    PhoneticAutoCorrect := 'NO'
  else
    PhoneticAutoCorrect := 'YES';
  RefreshSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleFixChandra;
begin
  if AutomaticallyFixChandra = 'YES' then
    AutomaticallyFixChandra := 'NO'
  else
    AutomaticallyFixChandra := 'YES';
  RefreshSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleMode;
begin
  KeyLayout.ToggleMode;
end;

{ =============================================================================== }

procedure TAvroMainForm1.SetBengaliUnicodeMode;
begin
  if (KeyLayout.KeyboardMode = Bangla) and (OutputIsBijoy = 'NO') then
    KeyLayout.KeyboardMode := SysDefault
  else
  begin
    if KeyLayout.KeyboardMode <> Bangla then
      KeyLayout.KeyboardMode := Bangla;
    if OutputIsBijoy = 'YES' then
    begin
      OutputIsBijoy := 'NO';
      RefreshSettings;
    end;
  end;

  SwitchLocaleToMatchMode;
end;

procedure TAvroMainForm1.SetBengaliANSIMode;
begin
  if (KeyLayout.KeyboardMode = Bangla) and (OutputIsBijoy = 'YES') then
  begin
    { Already in Bangla+ANSI: toggle off to English. No warning needed. }
    KeyLayout.KeyboardMode := SysDefault;
  end
  else
  begin
    { Switching to Bangla+ANSI. Remember the previous mode so a cancelled
      warning can restore it (English if the user was in English mode,
      Bangla if they were already typing Bangla in Unicode). }
    PreviousModeBeforeANSISwitch := KeyLayout.KeyboardMode;

    if KeyLayout.KeyboardMode <> Bangla then
      KeyLayout.KeyboardMode := Bangla;

    if ShowOutputwarning <> 'NO' then
    begin
      { Show warning. The user's choice arrives asynchronously in
        frmEncodingWarning.Button1Click / Button2Click / FormClose. }
      PendingANSISwitch := True;
      CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
      frmEncodingWarning.Show;
    end
    else
    begin
      { No warning enabled; commit to ANSI directly. }
      if OutputIsBijoy <> 'YES' then
      begin
        OutputIsBijoy := 'YES';
        RefreshSettings;
      end;
    end;
  end;

  SwitchLocaleToMatchMode;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ApplyPendingANSISwitchRevert;
begin
  if not PendingANSISwitch then
    exit;
  PendingANSISwitch := False;

  { Restore previous mode (English if user was in English, Bangla if they
    were already typing Bangla in Unicode). Setting KeyboardMode back
    fires KeyLayout_KeyboardModeChanged which calls SwitchLocaleToMatchMode,
    so the Windows input locale is also re-synced. }
  if KeyLayout.KeyboardMode <> PreviousModeBeforeANSISwitch then
    KeyLayout.KeyboardMode := PreviousModeBeforeANSISwitch
  else
    SwitchLocaleToMatchMode;
end;

{ =============================================================================== }

procedure TAvroMainForm1.PendingANSISwitchClear;
begin
  PendingANSISwitch := False;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleNumPadBangla;
begin
  if NumPadBangla = 'YES' then
    NumPadBangla := 'NO'
  else
    NumPadBangla := 'YES';
  RefreshSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleOldStyleReph;
begin
  if OldStyleReph = 'YES' then
    OldStyleReph := 'NO'
  else
    OldStyleReph := 'YES';
  RefreshSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleOutputEncoding;
begin
  if OutputIsBijoy = 'YES' then
    OutputasUnicodeRecommended1Click(nil)
  else
    OutputasANSIAreyousure1Click(nil);
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleVowelFormat;
begin
  if VowelFormating = 'YES' then
    VowelFormating := 'NO'
  else
    VowelFormating := 'YES';
  RefreshSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.TopBarDocToTop;
begin
  Topbar.Top := 0;
  if (Topbar.Left + Topbar.Width > Screen.Width) or (Topbar.Left < 0) then
    Topbar.Left := Screen.Width - Topbar.Width - 250;
end;

{ =============================================================================== }

function TAvroMainForm1.TransferKeyDown(const KeyCode: Integer; var Block: Boolean): string;
begin
  Result := KeyLayout.ProcessVKeyDown(KeyCode, Block);
end;

{ =============================================================================== }

procedure TAvroMainForm1.TransferKeyUp(const KeyCode: Integer; var Block: Boolean);
begin
  KeyLayout.ProcessVKeyUP(KeyCode, Block);
end;

procedure TAvroMainForm1.TrayClick(Sender: TObject);
begin
  KeyLayout.ToggleMode;
end;

procedure TAvroMainForm1.TrayDblClick(Sender: TObject);
begin
  KeyLayout.ToggleMode;
  RestoreFromTray;
end;

procedure TAvroMainForm1.TrimAppMemorySize;
var
  MainHandle: THandle;
begin
  try
    MainHandle := OpenProcess(PROCESS_ALL_ACCESS, False, GetCurrentProcessID);
    SetProcessWorkingSetSize(MainHandle, $FFFFFFFF, $FFFFFFFF);
    CloseHandle(MainHandle);
  except
  end;
  Application.ProcessMessages;
end;

procedure TAvroMainForm1.TypeJoNuktawithShiftJ1Click(Sender: TObject);
begin
  if EnableJoNukta = 'YES' then
    EnableJoNukta := 'NO'
  else
    EnableJoNukta := 'YES';
  RefreshSettings;
end;

procedure TAvroMainForm1.UnicodetoBijoytextconverter1Click(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Unicode to Bijoy.exe');
end;

procedure TAvroMainForm1.UsefultoolsforBangla1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=15');
end;

procedure TAvroMainForm1.UseModernStyleTyping1Click(Sender: TObject);
begin
  ChangeTypingStyle('ModernStyle');
end;

procedure TAvroMainForm1.UseOldStyleTyping1Click(Sender: TObject);
begin
  ChangeTypingStyle('OldStyle');
end;

procedure TAvroMainForm1.UserForum1Click(Sender: TObject);
begin
  Execute_Something('https://github.com/mugli/Avro-Keyboard/issues');
end;

procedure TAvroMainForm1.UseTabforBrowsingSuggestions1Click(Sender: TObject);
begin
  if TabBrowsing = 'YES' then
    TabBrowsing := 'NO'
  else
    TabBrowsing := 'YES';
  RefreshSettings;
end;

procedure TAvroMainForm1.UseVerticalLinePipekeytotypeDot1Click(Sender: TObject);
begin
  if PipeToDot = 'YES' then
    PipeToDot := 'NO'
  else
    PipeToDot := 'YES';
  RefreshSettings;
end;

procedure TAvroMainForm1.WindowCheckTimer(Sender: TObject);
var
  WindoRecord: TWindowRecord;
  hforewnd:    HWND;
begin

  hforewnd := GetForegroundWindow;
  if hforewnd = 0 then
    exit;
  if IsWindow(hforewnd) = False then
    exit; { Experimental use }

  if IgnorableWindow(hforewnd) = True then
    exit;
  if hforewnd = LastWindow then
    exit;

  // window z-order has been changed
  // ==================================
  // Aggressive mode
  RemoveHook;
  Sethook;

  if Topbar.Visible = True then
    TOPMOST(Topbar.Handle);
  // ==================================

  if not WindowDict.TryGetValue(hforewnd, WindoRecord) then
  begin
    // This is a new window, make the keyboard mode English Keyboard
    // If DefaultKeyboardMode = 'SYSTEM' Then Begin
    { Highly experimental! }
    if KeyLayout.KeyboardMode <> SysDefault then
      KeyLayout.KeyboardMode := SysDefault;
    // End
    // Else Begin
    { Highly experimental! }
    // If KeyLayout.KeyboardMode <> bangla Then
    // KeyLayout.KeyboardMode := bangla;
    // End;
  end
  else
  begin
    { This window is already being tracked, change keyboard mode
      to the lastly recorded one }
    if (WindoRecord.Mode = 'B') and (KeyLayout.KeyboardMode = SysDefault) then
      KeyLayout.KeyboardMode := bangla;
    if (WindoRecord.Mode = 'S') and (KeyLayout.KeyboardMode = bangla) then
      KeyLayout.KeyboardMode := SysDefault;
  end;
  // A new window came to the top, we must reset dead key now
  KeyLayout.ResetDeadKey;
  LastWindow := hforewnd;

end;

procedure TAvroMainForm1.WMCopyData(var Msg: TWMCopyData);
var
  cmd: string;
begin
  cmd := PChar(Msg.CopyDataStruct.lpData);
  cmd := Lowercase(cmd);

  if cmd = 'refresh_layout' then
  begin
    FreeAndNil(KeyboardLayouts);
    LoadKeyboardLayoutNames;
    Initmenu;

    // Send something back
    Msg.Result := 21;
  end;

  if cmd = 'toggle' then
  begin
    KeyLayout.ToggleMode;

    // Send something back
    Msg.Result := 21;
  end;

  if cmd = 'bn' then
  begin
    KeyLayout.BanglaMode;

    // Send something back
    Msg.Result := 21;
  end;

  if cmd = 'sys' then
  begin
    KeyLayout.SysMode;

    // Send something back
    Msg.Result := 21;
  end;

  if cmd = 'minimize' then
  begin
    Jumptosystemtray1Click(nil);

    // Send something back
    Msg.Result := 21;
  end;

  if cmd = 'restore' then
  begin
    RestoreFromTray;
    Topbar.AlphaBlendValue := 255;

    // Send something back
    Msg.Result := 21;
  end;

end;

procedure TAvroMainForm1.wwwOmicronLabcom1Click(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com/go.php?id=2');
end;

{ =============================================================================== }

procedure TAvroMainForm1.AnsiVersionMenuClick(Sender: TObject);
var
  ClickedItem, PrevCheckedItem: TMenuItem;
  I: Integer;
  SelectedVersion, ErrorMsg: string;
begin
  if not (Sender is TMenuItem) then Exit;
  ClickedItem := TMenuItem(Sender);

  PrevCheckedItem := nil;
  if ClickedItem.Parent <> nil then
  begin
    for I := 0 to ClickedItem.Parent.Count - 1 do
    begin
      if ClickedItem.Parent.Items[I].Checked then
      begin
        PrevCheckedItem := ClickedItem.Parent.Items[I];
        Break;
      end;
    end;
  end;

  SelectedVersion := ClickedItem.Caption;
  SelectedVersion := StringReplace(SelectedVersion, '&', '', [rfReplaceAll]);

  if not TrySetAnsiVersion(SelectedVersion, ErrorMsg) then
  begin
    if PrevCheckedItem <> nil then
      PrevCheckedItem.Checked := True;
    ClickedItem.Checked := False;

    Application.MessageBox(
      PChar('Could not load the selected ANSI mapping.' + sLineBreak +
            'Please check your mapping file.' + sLineBreak + sLineBreak +
            'Error: ' + ErrorMsg),
      'ANSI Mapping Error',
      MB_ICONWARNING or MB_OK
    );
  end
  else
  begin
    if PrevCheckedItem <> nil then
      PrevCheckedItem.Checked := False;
    ClickedItem.Checked := True;
    BuildAnsiVersionMenus;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ImportAnsiMappingClick(Sender: TObject);
var
  OpenDialog: TOpenDialog;
  DestPath, ErrMsg: string;
  ErrorLog: TStringList;
begin
  OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Filter := 'ANSI Mapping JSON|*.json';
    OpenDialog.DefaultExt := 'json';
    if OpenDialog.Execute then
    begin
      if not ValidateAnsiMappingFile(OpenDialog.FileName, ErrMsg) then
      begin
        MessageDlg('ANSI mapping import failed:'#13#10#13#10 + ErrMsg, mtError, [mbOK], 0);
        Exit;
      end;

      ForceDirectories(AnsiMappingDir);
      DestPath := AnsiMappingDir + ExtractFileName(OpenDialog.FileName);
      if not CopyFile(PChar(OpenDialog.FileName), PChar(DestPath), False) then
      begin
        MessageDlg('Failed to copy file to the mapping directory.', mtError, [mbOK], 0);
        Exit;
      end;

      AnsiVersion := ChangeFileExt(ExtractFileName(OpenDialog.FileName), '');
      SaveSettings;

      ErrorLog := TStringList.Create;
      try
        LoadCurrentActiveMapping(ErrorLog);
        if ErrorLog.Count = 0 then
          MessageDlg('Mapping imported successfully.', mtInformation, [mbOK], 0)
        else
          MessageDlg('Mapping loaded with warnings/errors:'#13#10 + ErrorLog.Text, mtWarning, [mbOK], 0);
      finally
        ErrorLog.Free;
      end;

      BuildAnsiVersionMenus;
    end;
  finally
    OpenDialog.Free;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ExportAnsiMappingClick(Sender: TObject);
var
  SaveDialog: TSaveDialog;
begin
  SaveDialog := TSaveDialog.Create(nil);
  try
    SaveDialog.Filter := 'ANSI Mapping JSON|*.json';
    SaveDialog.DefaultExt := 'json';
    SaveDialog.Title := 'Export Current ANSI Mapping';
    SaveDialog.FileName := AnsiVersion + '.json';

    if SaveDialog.Execute then
    begin
      ExportAnsiMapping(SaveDialog.FileName);
      
      MessageDlg('Current mapping successfully exported to:'#13#10 + SaveDialog.FileName, 
                 mtInformation, [mbOK], 0);
    end;
  finally
    SaveDialog.Free;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.OpenAnsiMappingDirClick(Sender: TObject);
begin
  ShellExecute(0, 'open', PChar(AnsiMappingDir), nil, nil, SW_SHOWNORMAL);
end;

{ =============================================================================== }

procedure TAvroMainForm1.DeleteAnsiMappingClick(Sender: TObject);
var
  Name: string;
begin
  Name := (Sender as TMenuItem).Caption;
  if MessageDlg('Delete mapping "' + Name + '"?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    if DeleteFile(AnsiMappingDir + Name + '.json') then
    begin
      if AnsiVersion = Name then
        AnsiVersion := 'Default';
      SaveSettings;
      LoadCurrentActiveMapping;
      BuildAnsiVersionMenus;
    end;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.IgnoreCapsLockClick(Sender: TObject);
var
  Item: TMenuItem;
begin
  Item := Sender as TMenuItem;
  Item.Checked := not Item.Checked;
  if Item.Checked then
    IgnoreCapsLock := 'YES'
  else
    IgnoreCapsLock := 'NO';
  IgnoreCapsLock1.Checked := Item.Checked;
  IgnoreCapsLock2.Checked := Item.Checked;
  SaveSettings;
end;

{ =============================================================================== }

procedure TAvroMainForm1.BuildAnsiVersionMenus;
var
  SearchRec: TSearchRec;
  FileTitle: string;
  Sep: TMenuItem;

  procedure AddVersionItem(ParentMenu: TMenuItem; const ACaption: string; AChecked: Boolean);
  var
    Item: TMenuItem;
  begin
    Item := TMenuItem.Create(ParentMenu);
    Item.Caption := ACaption;
    Item.RadioItem := False;
    Item.OnClick := AnsiVersionMenuClick;
    Item.Checked := AChecked;
    ParentMenu.Add(Item);
  end;

  procedure BuildSingleMenu(AMenu: TMenuItem);
  var
    Item: TMenuItem;
    DeleteMenu: TMenuItem;
    HasFiles: Boolean;
  begin
    AMenu.Clear;
    AddVersionItem(AMenu, 'Default', AnsiVersion = 'Default');
    HasFiles := False;
    if DirectoryExists(AnsiMappingDir) then
    begin
      if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SearchRec) = 0 then
      begin
        HasFiles := True;
        repeat
          FileTitle := ChangeFileExt(SearchRec.Name, '');
          AddVersionItem(AMenu, FileTitle, AnsiVersion = FileTitle);
        until FindNext(SearchRec) <> 0;
        FindClose(SearchRec);
      end;
    end;
    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);
    Item := TMenuItem.Create(AMenu);
    Item.Caption := 'Import Mapping JSON...';
    Item.OnClick := ImportAnsiMappingClick;
    AMenu.Add(Item);
    Item := TMenuItem.Create(AMenu);
    Item.Caption := 'Export Current Mapping JSON...';
    Item.OnClick := ExportAnsiMappingClick;
    AMenu.Add(Item);
    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);
    Item := TMenuItem.Create(AMenu);
    Item.Caption := 'Open Mapping Directory...';
    Item.OnClick := OpenAnsiMappingDirClick;
    AMenu.Add(Item);
    if HasFiles then
    begin
      DeleteMenu := TMenuItem.Create(AMenu);
      DeleteMenu.Caption := 'Delete Mapping';
      if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SearchRec) = 0 then
      begin
        repeat
          FileTitle := ChangeFileExt(SearchRec.Name, '');
          Item := TMenuItem.Create(DeleteMenu);
          Item.Caption := FileTitle;
          Item.OnClick := DeleteAnsiMappingClick;
          DeleteMenu.Add(Item);
        until FindNext(SearchRec) <> 0;
        FindClose(SearchRec);
      end;
      AMenu.Add(DeleteMenu);
    end;
  end;

begin
  BuildSingleMenu(AnsiVersionSubmenu1);
  BuildSingleMenu(AnsiVersionSubmenu2);
end;

{ =============================================================================== }

end.
