{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uForm1;

interface

uses
  Windows,
  Messages,
  SysUtils,

  Classes,
  Graphics,
  Controls,
  Forms,
  Dialogs,
  StdCtrls,
  ImgList,
  ExtCtrls,
  Vcl.Menus,
  Math,
  clsLayout,
  Generics.Collections,
  StrUtils,
  clsUpdateInfoDownloader,
  DateUtils,
  System.ImageList,
  Vcl.AppEvnts,
  ShellAPI,
  Winapi.CommCtrl,
  uAvroDirectoryWatcher;

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
    GetAcrobatReader2: TMenuItem;
    AboutAvroKeyboard2: TMenuItem;
    N28: TMenuItem;
    Exit2: TMenuItem;
    Popup_Tray: TPopupMenu;
    ogglekeyboardmode2: TMenuItem;
    RestoreAvroTopBar1: TMenuItem;
    N29: TMenuItem;
    Selectkeyboardlayout2: TMenuItem;
    // Tray copy of the ANSI encoding menu, designed in the DFM directly under
    // "Select keyboard layout"; its items are built by BuildAnsiVersionMenus.
    mnuTraySelectAnsiEncoding: TMenuItem;
    AvroMouseClicknType4: TMenuItem;
    N31: TMenuItem;
    Exit3: TMenuItem;
    AvroPhoneticEnglishtoBangla3: TMenuItem;
    N34: TMenuItem;
    Showactivekeyboardlayout3: TMenuItem;
    WindowCheck: TTimer;
    InternetCheck: TTimer;
    Spellcheck1: TMenuItem;
    N41: TMenuItem;
    Spellcheck2: TMenuItem;
    Spellcheck3: TMenuItem;
    Spellcheck4: TMenuItem;
    N43: TMenuItem;
    IdleTimer: TTimer;
    UnicodetoBijoytextconverter1: TMenuItem;
    ools1: TMenuItem;
    N46: TMenuItem;
    AvroPhonetic2: TMenuItem;
    EnableAutoCorrect2: TMenuItem;
    ManageAutoCorrectentries2: TMenuItem;
    KeyboardLayoutEditorBuildcustomlayouts2: TMenuItem;
    SkinDesignerDesignyourownskin2: TMenuItem;
    N48: TMenuItem;
    Helpfiles2: TMenuItem;
    BeforeYouStart3: TMenuItem;
    Overview3: TMenuItem;
    CustomizingAvroKeyboard3: TMenuItem;
    BanglaTypingwithAvroPhonetic3: TMenuItem;
    BanglaTypingwithFixedKeyboardLayouts3: TMenuItem;
    BanglaTypingwithAvroMouse3: TMenuItem;
    N36: TMenuItem;
    CreatingEditingFixedKeyboardLayouts3: TMenuItem;
    N39: TMenuItem;
    GetAcrobatReader3: TMenuItem;
    N2: TMenuItem;
    Aboutcurrentkeyboardlayout2: TMenuItem;
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
    procedure BeforeYouStart1Click(Sender: TObject);
    procedure Overview1Click(Sender: TObject);
    procedure CustomizingAvroKeyboard1Click(Sender: TObject);
    procedure BanglaTypingwithAvroPhonetic1Click(Sender: TObject);
    procedure BanglaTypingwithFixedKeyboardLayouts1Click(Sender: TObject);
    procedure BanglaTypingwithAvroMouse1Click(Sender: TObject);
    procedure FrequentlyAskedQuestionsFAQ1Click(Sender: TObject);
    procedure CreatingEditingFixedKeyboardLayouts1Click(Sender: TObject);
    procedure JoinTelegramCommunity(Sender: TObject);
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
    procedure WMAvroEmit(var Msg: TMessage); message WM_APP + 10;
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
      WindowDict:                   TDictionary<HWND, TWindowRecord>;
      MyCurrentLayout:              string;
      MyCurrentKeyboardMode:        enumMode;
      LastWindow:                   HWND;
      PendingANSISwitch:            Boolean;
      PreviousModeBeforeANSISwitch: enumMode;
      FActiveMappingLastWriteTime:  TDateTime;
      FMappingCheckCountdown:       Integer; // throttles the ANSI mapping disk check
      FMappingListCheckCountdown:   Integer; // throttles the ANSI mapping folder-list poll
      FAnsiMappingSnapshot:         string;  // last seen file-name list of AnsiMappingDir
      FDirectoryWatcher:            TAvroDirectoryWatcher;

      { Per-layout icons, decoded from the payload each container carries.

        The tray needs its own HICON at the metric Windows asks for, and that
        metric changes with the display DPI, so AnsiIconHandles is keyed
        'name@size' - a DPI change then builds a second handle at the new size
        instead of handing the shell a stale one to rescale.

        The two "Select ANSI Encoding" parent items need an ImageList1 slot
        instead, and that slot is built at ImageList1's OWN metric rather than
        at the DPI-scaled tray metric - a 20/24/32 px handle does not belong in
        a 16x16 list, and the fallback it used to trigger is what drew the
        generic icon. See AnsiRootIconSlot.

        Handles here are handed to the tray through CopyIcon, so the tray owns a
        private copy and this cache stays valid across tray updates. Everything
        is released by ReleaseAnsiIconCache. }
      AnsiIconHandles: TDictionary<string, HICON>;
      FAnsiRootIconIndex: Integer; // ImageList1 slot appended for the active layout icon (-1 = none yet)
      FAnsiRootIconName:  string;  // the layout whose artwork occupies that slot ('' = unused)

      function AnsiRootIconSlot(const AName: string): Integer;
      procedure ReleaseAnsiIconCache;
      procedure ReplaceAnsiMenuParentIcon;

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

      procedure HandleThemes;
      procedure HandleLayoutDirectoryChanged(Sender: TObject);
      function BuildAnsiMappingFolderList: string;
      procedure RefreshAnsiMappingList;
      procedure RefreshAnsiMappingNames;
      procedure IgnoreCapsLockClick(Sender: TObject);
      procedure PopupToolsPopup(Sender: TObject);
      procedure PopupTrayPopup(Sender: TObject);

      procedure WMCopyData(var Msg: TWMCopyData); message WM_COPYDATA;
      procedure WMShowAnsiPicker(var Msg: TMessage); message WM_APP + 1;
      procedure WMShowLayoutPicker(var Msg: TMessage); message WM_APP + 3;

    public
      { Public declarations }
      KeyboardModeChanged: Boolean;
      KeyLayout:           TLayout;
      Updater:             TUpdateCheck;
      AnsiVersionSubmenu1: TMenuItem;
      { Cached, sorted list of mapping display names (excluding 'Default'),
        kept fresh by the directory watcher / periodic poll. The ANSI picker
        opens from this list with zero disk I/O. }
      AnsiMappingNames:    TStringList;
      IgnoreCapsLock1:     TMenuItem;
      IgnoreCapsLock2:     TMenuItem;
      procedure AnsiVersionMenuClick(Sender: TObject);
      procedure ReadAnsiDescriptionClick(Sender: TObject);
      procedure ExportSpecificMappingClick(Sender: TObject);
      procedure DeleteAnsiMappingClick(Sender: TObject);
      procedure ImportAnsiMappingClick(Sender: TObject);
      procedure OpenAnsiMappingDirClick(Sender: TObject);
      procedure AnsiVersionItemAdvancedDrawItem(Sender: TObject;
        ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
      procedure AnsiVersionItemMeasureItem(Sender: TObject;
        ACanvas: TCanvas; var Width, Height: Integer);
      { The cached HICON for a mapping at the CURRENT small-icon metric, or 0
        when that mapping carries no icon ('Default', a legacy container, a
        plain .json, or one whose icon failed to decode).

        The handle is BORROWED: it belongs to the DPI-keyed cache filled by the
        startup preload and is freed by ReleaseAnsiIconCache, so a caller must
        never destroy it. Public so the ANSI version picker can draw the very
        same trailing badge the tray's "Select ANSI Encoding" submenu draws
        (AnsiVersionItemAdvancedDrawItem above). }
      function GetAnsiTrayIcon(const AName: string): HICON;

      procedure BuildAnsiVersionMenus;
      procedure UpdateAnsiVersionMenuChecks(const AName: string);
      procedure SyncAnsiVersionChecks(AMenu: TMenuItem);
      procedure SyncActiveMappingTimestamp(const AName: string);
      function GetMyCurrentKeyboardMode: enumMode;
      procedure ExitApp;
      function GetMyCurrentLayout: string;
      procedure RefreshSettings;
      procedure UpdateTrayIcon;

      procedure RestoreFromTray;
      procedure OpenHelpFile(const HelpID: Integer);
      procedure ShowOnTray;
      procedure ToggleMode;
      procedure SetBengaliUnicodeMode;
      procedure SetBengaliANSIMode;
      procedure ToggleAnsiVersionPicker;
      procedure ToggleLayoutPicker;
      procedure TopBarDocToTop;
      function TransferKeyDown(const KeyCode: Integer; var Block: Boolean): string;
      procedure TransferKeyUp(const KeyCode: Integer; var Block: Boolean);
      function IsPickerOpen: Boolean;
      procedure TrimAppMemorySize;
      procedure Initmenu;
      procedure ToggleOutputEncoding;
      procedure ApplyPendingANSISwitchRevert;
      procedure PendingANSISwitchClear;
      procedure CleanupDuplicateMappings;
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  AvroMainForm1: TAvroMainForm1;

implementation

{$R *.dfm}

uses
  uRegistrySettings,
  ufrmAnsiVersionPicker,
  ufrmLayoutPicker,
  uAvroPasswordDlg,
  ufrmAnsiToast,
  uProcessHandler,
  uAutoCorrect,
  KeyboardLayoutLoader,
  uFileFolderHandling,
  clsUnicodeToBijoy2000,
  System.IOUtils,
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
  uThemeManager,
  System.UITypes,
  uKeyboardMacro,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAvroEncoImporter,
  uAvroEncoIconSection,
  uAvroLayoutUI,
  uAnsiEngineManager;

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

  FreeAndNil(FDirectoryWatcher);
  Log('FreeAndNil: FDirectoryWatcher');
  FinalizeEncoManager;
  Log('FinalizeEncoManager');
  ReleaseAnsiIconCache;
  // The caches themselves go too - ReleaseAnsiIconCache only empties them,
  // because a re-scan reuses the same dictionaries.
  FreeAndNil(AnsiIconHandles);
  Log('ReleaseAnsiIconCache');

  FreeAndNil(WindowDict);
  FreeAndNil(AnsiMappingNames);
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

  AnsiMappingNames := TStringList.Create;
  AnsiIconHandles := TDictionary<string, HICON>.Create;
  LoadSettings;
  // The call above only covered the built-in default - AppThemeMode is read
  // here, so the stored theme has to be applied once more.
  HandleThemes;
  LoadApp;
end;

{ =============================================================================== }

procedure TAvroMainForm1.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_F4) then
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

procedure TAvroMainForm1.JoinTelegramCommunity(Sender: TObject);
begin
  ShellExecute(0, 'open', PChar('https://t.me/AvroUsersCommunity'), nil, nil, SW_SHOWNORMAL);
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

procedure TAvroMainForm1.WMAvroEmit(var Msg: TMessage);
begin
  { Deferred output: clsGenericLayoutOld.EmitBatch queues the output and posts
    WM_AVRO_EMIT (WM_APP + 10) instead of calling SendInput from inside the
    low-level keyboard hook. Draining the queue here - on the main thread,
    after the hook returned - keeps the Raw Input Thread unblocked. }
  if Assigned(KeyLayout) then
    KeyLayout.FlushEmit;
end;

function TAvroMainForm1.IgnorableWindow(const lngHWND: HWND): Boolean;
var
  ClsName: string;
begin
  Result := False;
  if lngHWND = 0 then Exit(True);

  // ১. নিজস্ব ফর্ম ও সিস্টেম ট্রে
  if (lngHWND = FindWindow('Shell_TrayWnd', nil)) or
     (lngHWND = FindWindowEx(FindWindow('Shell_TrayWnd', nil), 0, 'TrayNotifyWnd', nil)) or
     (lngHWND = Self.Handle) then
    Exit(True);

  if IsFormLoaded('TopBar') and (lngHWND = Topbar.Handle) then Exit(True);
  if IsFormLoaded('frmEncodingWarning') and (lngHWND = frmEncodingWarning.Handle) then Exit(True);
  if (CurrentPicker <> nil) and (lngHWND = CurrentPicker.Handle) then Exit(True);
  if (CurrentLayoutPicker <> nil) and (lngHWND = CurrentLayoutPicker.Handle) then Exit(True);
  if IsFormLoaded('frmAvroPasswordDlg') and (frmAvroPasswordDlg <> nil) and (lngHWND = frmAvroPasswordDlg.Handle) then Exit(True);
  if IsFormLoaded('TfrmAnsiToast') or IsFormLoaded('TfrmLayoutToast') then Exit(True);

  // ২. 🛡️ অত্যন্ত গুরুত্বপূর্ণ: মেনু এবং পপআপ ক্লাস (#32768) যাতে টপবারকে সামনে এনে ক্লিক ব্লক না করে
  ClsName := GetWindowClassName(lngHWND);
  if (ClsName = '#32768') or (ClsName = 'PSDocDragFeedback') or (ClsName = 'ComboLBox') then
    Exit(True);
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
  AnsiVersionSubmenu1.Caption := 'Select ANSI Encoding';
  Popup_Tools.Items.Insert(OutputasANSIAreyousure1.MenuIndex + 1, AnsiVersionSubmenu1);

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
  ools1.Insert(OutputasANSIAreyousure2.MenuIndex + 1, IgnoreCapsLock2);
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
  hforewnd:                      Integer;
  WindowRecord, NewWindowRecord: TWindowRecord;
begin
  { This is for Top Bar, when Keyboard Mode is changed,
    it removes transparency }
  if CurrentMode <> MyCurrentKeyboardMode then
    KeyboardModeChanged := True;
  hforewnd := GetForegroundWindow;

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

function HandleLoadEncoMapping(const AFilePath: string): Boolean;
var
  ErrorLog: TStringList;
  Password: AnsiString;
begin
  Result := False;
  ErrorLog := TStringList.Create;
  try
    // Try with this file's remembered password first - this never prompts
    // (each encoding asks for its password only once per computer).
    Result := LoadMappingFromEnco(AFilePath, GetEncoCachedPassword(AFilePath), ErrorLog);
    if Result and IsEncoFile(AFilePath) then
      CachedEncoPassword := GetEncoCachedPassword(AFilePath);

    // Failed? A stale or wrong cached password must never silently keep the
    // previous mapping active - clear it and ask the user for the right one.
    // Only password-protected files (flag $01 / legacy v1) ever prompt:
    // default-key files (flag $00) decrypt transparently, so a failure there
    // means the file itself is corrupt and a password prompt would be wrong.
    if (not Result) and IsEncoFile(AFilePath) and
      (GetAvroEncoProtectionFlag(AFilePath) = AVROENCO_FLAG_USER_PASSWORD) then
    begin
      CachedEncoPassword := '';
      ForgetEncoPassword(AFilePath);
      ErrorLog.Clear;
      if PromptForPasswordAndValidate(AFilePath, Password) then
      begin
        CachedEncoPassword := Password;
        RememberEncoPassword(AFilePath, Password);
        SaveSettings;
        Result := LoadMappingFromEnco(AFilePath, CachedEncoPassword, ErrorLog);
      end;
    end;

    if not Result then
    begin
      if IsEncoFile(AFilePath) and
        (GetAvroEncoProtectionFlag(AFilePath) = AVROENCO_FLAG_USER_PASSWORD) then
      begin
        CachedEncoPassword := '';
        ForgetEncoPassword(AFilePath);
      end;
      Log('HandleLoadEncoMapping FAILED: ' + AFilePath + ' - ' + ErrorLog.Text);
    end
    else
      Log('HandleLoadEncoMapping OK: ' + AFilePath);
  finally
    ErrorLog.Free;
  end;
end;

procedure TAvroMainForm1.LoadApp;
var
  tempLastUIMode: string;
  MappingPath: string;
  PreloadThread: TAnsiPreloadThread;
  DesiredVersion: string;
begin
  Set_Process_Priority(HIGH_PRIORITY_CLASS);
  FAnsiRootIconIndex := -1;

  InitDict;
  LoadKeyboardLayoutNames;
  Initmenu;
  LoadUserHotkeysFromXML;

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
    // Paint the splash synchronously RIGHT NOW: the heavy initialization
    // below (dictionary load, mapping scan, ...) blocks the message loop for
    // seconds, so without this the splash window would stay unpainted
    // (rendered as a solid black box by DWM) until the 2s timer closes it.
    frmSplash.Update;
  end;

  // --- Record initial file write time for auto-refresh ---
  if (AnsiVersion <> 'Default') and (AnsiMappingDir <> '') then
  begin
    FActiveMappingLastWriteTime := 0;
    if TFile.Exists(AnsiMappingDir + AnsiVersion + '.AvroEnco') then
      FActiveMappingLastWriteTime := TFile.GetLastWriteTime(AnsiMappingDir + AnsiVersion + '.AvroEnco')
    else if TFile.Exists(AnsiMappingDir + AnsiVersion + '.json') then
      FActiveMappingLastWriteTime := TFile.GetLastWriteTime(AnsiMappingDir + AnsiVersion + '.json');
  end
  else
    FActiveMappingLastWriteTime := 0;

  // Apply the loaded ANSI mapping
  if AnsiMappingDir = '' then
  begin
    AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
    ForceDirectories(AnsiMappingDir);
  end;
  InitializeEncoManager;
  ScanAvroEncoFiles(AnsiMappingDir);
  // Wire up the .AvroEnco loader BEFORE the first engine switch: otherwise
  // an active .AvroEnco mapping (e.g. a password-protected one persisted
  // from the previous session) is silently skipped at startup and ANSI
  // typing falls back to the built-in defaults.
  OnLoadEncoMapping := HandleLoadEncoMapping;
  // Prime the session password for a password-protected ACTIVE version from
  // the persisted per-file cache (never prompts), so SwitchEngine below can
  // parse it on demand without user interaction.
  if (AnsiVersion <> 'Default') and (AnsiMappingDir <> '') then
  begin
    MappingPath := GetActiveEncoFilePath(AnsiVersion, AnsiMappingDir);
    if (MappingPath <> '') and IsEncoFile(MappingPath) and
      (GetAvroEncoProtectionFlag(MappingPath) = AVROENCO_FLAG_USER_PASSWORD) then
      CachedEncoPassword := GetEncoCachedPassword(MappingPath);
  end;
  // Parse every engine that unlocks without user interaction on a
  // BACKGROUND thread: cold decrypt + parse of the shipped Shield
  // containers is the heaviest startup work, and doing all of it on this
  // thread would block the message loop - the splash would freeze instead
  // of closing after its normal 2 s. (v2 containers use an instant
  // HKDF-based schedule - no slow KDF remains anywhere in the project.)
  // The keyboard hook is paused while the worker builds the engine globals
  // (typing must never read a half-built engine), and the pump below keeps
  // the splash painting and its 2 s timer running, so the splash behaves
  // exactly as before while the heavy work happens off the UI thread.
  PreloadThread := TAnsiPreloadThread.Create(AnsiEngineManager.CapturePreloadList);
  PreloadThread.Start;
  WindowCheck.Enabled := False; // never re-install the hook mid-preload
  RemoveHook;
  try
    while (not PreloadThread.Finished) and (not Application.Terminated) do
    begin
      Application.ProcessMessages;
      Sleep(5);
    end;
    FreeAndNil(PreloadThread);
    // O(1): the worker parked every engine; restore the saved version. If it
    // is missing (its decrypt failed on the first pass - possible right
    // after wiping %AppData%\AvroKeyboard\Cache, when every container
    // decrypts at once and the largest mapping, Ansi V3, is most exposed),
    // run ONE more
    // background pass for just the missing engines while the hook is still
    // removed (typing can never read a half-built engine), then switch again.
    // DesiredVersion is captured BEFORE the Default fallback, because the
    // fallback itself overwrites the AnsiVersion global.
    DesiredVersion := AnsiVersion;
    if (not Application.Terminated) and
      (not AnsiEngineManager.SwitchEngine(DesiredVersion)) then
    begin
      AnsiEngineManager.SwitchEngine('Default');
      if (not Application.Terminated) and
        (Length(AnsiEngineManager.CapturePreloadList) > 0) then
      begin
        PreloadThread := TAnsiPreloadThread.Create(
          AnsiEngineManager.CapturePreloadList);
        PreloadThread.Start;
        while (not PreloadThread.Finished) and (not Application.Terminated) do
        begin
          Application.ProcessMessages;
          Sleep(5);
        end;
        FreeAndNil(PreloadThread);
        if not AnsiEngineManager.SwitchEngine(DesiredVersion) then
          AnsiEngineManager.SwitchEngine('Default');
      end;
    end;
    // Warm every cached engine while hook is still removed. This pays all
    // first-use allocations/page faults before the user can open the picker.
    AnsiEngineManager.WarmAllEngines(AnsiVersion);
    SyncActiveMappingTimestamp(AnsiVersion);
  finally
    FreeAndNil(PreloadThread);
    Sethook;
    WindowCheck.Enabled := True;
  end;
  BuildAnsiVersionMenus;

  // The preload block above is what caches every layout's icon, and the tray
  // was already shown before it ran (the UI-mode restore earlier in this
  // procedure calls ShowOnTray). Re-apply the tray icon now, so a cold start in
  // tray mode shows the ACTIVE layout's icon straight away instead of the
  // built-in one until the user next toggles the keyboard mode.
  UpdateTrayIcon;
  ReplaceAnsiMenuParentIcon;

  FDirectoryWatcher := TAvroDirectoryWatcher.Create(AnsiMappingDir);
  FDirectoryWatcher.OnChanged := HandleLayoutDirectoryChanged;
  FDirectoryWatcher.Active := True;

  // Snapshot the current mapping folder so the periodic poll below only reacts
  // to real changes (files copied/removed while Avro Keyboard is running).
  FMappingListCheckCountdown := 5;
  FAnsiMappingSnapshot := BuildAnsiMappingFolderList;
end;

procedure TAvroMainForm1.HandleLayoutDirectoryChanged(Sender: TObject);
var
  TargetPath: string;
begin
  ScanAvroEncoFiles(AnsiMappingDir);

  if (AnsiVersion <> 'Default') and (AnsiMappingDir <> '') then
  begin
    TargetPath := GetActiveEncoFilePath(AnsiVersion, AnsiMappingDir);
    if TargetPath <> '' then
    begin
      // Default-key files (flag $00) reload transparently; password
      // protected files reload only when a usable password is cached. The
      // engine cache re-parses the changed file in place, so the active
      // engine stays fresh AND later switches keep using the cached copy.
      if IsEncoFile(TargetPath) then
      begin
        if (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_DEFAULT_KEY) or
          (GetEncoCachedPassword(TargetPath) <> '') then
          AnsiEngineManager.InvalidateEngine(AnsiVersion);
      end
      else
        AnsiEngineManager.InvalidateEngine(AnsiVersion);
    end;
  end;

  // New/changed/removed engines are reconciled with the cache as well.
  AnsiEngineManager.RefreshFromDisk;

  // Folders were scanned above, so refresh the snapshot BEFORE the menu
  // rebuild - BuildAnsiVersionMenus skips its own re-scan when nothing
  // changed since this snapshot.
  FAnsiMappingSnapshot := BuildAnsiMappingFolderList;
  BuildAnsiVersionMenus;
  ShowAnsiToastNotification('ANSI mappings refreshed');
end;

{ =============================================================================== }
{ Snapshot + fallback poll: the FindFirstChangeNotification watcher can lose }
{ events fired while the watch handle is being re-armed (e.g. when a file is }
{ copied into AnsiMappingDir from Explorer), so every ~1.5 s we also compare }
{ the folder's current file-name list with the last one we acted on. }
{ =============================================================================== }

function TAvroMainForm1.BuildAnsiMappingFolderList: string;
var
  NameList: TStringList;
  SR: TSearchRec;
begin
  Result := '';
  if (AnsiMappingDir = '') or (not DirectoryExists(AnsiMappingDir)) then
    Exit;

  NameList := TStringList.Create;
  try
    if FindFirst(AnsiMappingDir + '*.AvroEnco', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Name <> '.') and (SR.Name <> '..') then
            NameList.Add(Lowercase(SR.Name));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;

    if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Name <> '.') and (SR.Name <> '..') then
            NameList.Add(Lowercase(SR.Name));
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;

    NameList.Sort;
    Result := NameList.Text;
  finally
    NameList.Free;
  end;
end;

procedure TAvroMainForm1.RefreshAnsiMappingNames;
begin
  if AnsiMappingNames = nil then
    AnsiMappingNames := TStringList.Create;
  // AvroEncoFiles is kept fresh by the watcher / periodic poll / import /
  // delete flows, so this is pure memory work - no disk scan. The natural
  // ordering lives in uAvroEncoManager, shared with the encoding menus, so
  // this list and both menus can never disagree again.
  GetSortedMappingDisplayNames(AnsiMappingNames);
end;

procedure TAvroMainForm1.RefreshAnsiMappingList;
var
  Snap: string;
begin
  if (AnsiMappingDir = '') or (not DirectoryExists(AnsiMappingDir)) then
    Exit;

  Snap := BuildAnsiMappingFolderList;
  if Snap = FAnsiMappingSnapshot then
    Exit; // nothing new added / removed since the last refresh

  FAnsiMappingSnapshot := Snap;
  ScanAvroEncoFiles(AnsiMappingDir);
  BuildAnsiVersionMenus;
  Log('ANSI mapping folder changed - encoding list refreshed');
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

procedure TAvroMainForm1.OutputasANSIAreyousure1Click(Sender: TObject);
begin
  if ShowOutputwarning <> 'NO' then
  begin
    CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
    frmEncodingWarning.Show;
  end
  else
    OutputIsBijoy := 'YES';

  RefreshSettings;
end;

procedure TAvroMainForm1.OutputasUnicodeRecommended1Click(Sender: TObject);
begin
  OutputIsBijoy := 'NO';
  OptimizeMemoryUsage;
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
  Spellcheck4.ShortCut := TextToShortcut('Ctrl+' + SpellerLauncherKey);

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

  // ANSI Mapping version (engines are already preloaded; this switch is O(1))
  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiMappingDir);
  if not AnsiEngineManager.SwitchEngine(AnsiVersion) then
    AnsiEngineManager.SwitchEngine('Default');
  BuildAnsiVersionMenus;
  Popup_Tools.OnPopup := PopupToolsPopup;
  Popup_Tray.OnPopup := PopupTrayPopup;

  IgnoreCapsLock1.Checked := (IgnoreCapsLock = 'YES');
  IgnoreCapsLock2.Checked := (IgnoreCapsLock = 'YES');

  UpdateTrayIcon;

  // Apply the stored theme here as well: the Customize dialog saves its
  // settings and then calls RefreshSettings, so a theme change takes effect
  // immediately (the no-op guard inside ApplyAppTheme keeps every other
  // RefreshSettings caller free).
  HandleThemes;

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
  // The stored theme setting is the source of truth: SYSTEM follows Windows,
  // LIGHT / DARK force the theme even when Windows disagrees. ApplyAppTheme
  // also switches the VCL style (which is what makes the top bar popup menus
  // and every dialog match) and caches the resolved theme for the hand-painted
  // flyouts. Re-applying an unchanged theme is a no-op, because this runs after
  // every settings change in the app.
  ApplyAppTheme(AppThemeModeFromSetting(AppThemeMode));
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
    SaveUISettings;
    Topbar.Visible := True;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.Showactivekeyboardlayout1Click(Sender: TObject);
begin
  CheckCreateForm(TLayoutViewer, LayoutViewer, 'LayoutViewer');
  LayoutViewer.Show;
end;

{ Marks the version item of AMenu that is currently in force. Only the items
  BuildAnsiVersionMenus tagged with GroupIndex = 10 are considered, so the
  separator and the "More Options" submenu are never touched; nothing is
  cleared or rebuilt here - this runs inside OnPopup. }
procedure TAvroMainForm1.SyncAnsiVersionChecks(AMenu: TMenuItem);
var
  I: Integer;
  M: TMenuItem;
begin
  if not Assigned(AMenu) then
    Exit;
  for I := 0 to AMenu.Count - 1 do
  begin
    M := AMenu.Items[I];
    if M.GroupIndex = 10 then
      M.Checked := SameText(M.Hint, AnsiVersion);
  end;
end;

procedure TAvroMainForm1.PopupToolsPopup(Sender: TObject);
begin
  // Only update checkmarks on existing items -- do NOT Clear/rebuild during popup
  SyncAnsiVersionChecks(AnsiVersionSubmenu1);
  // The TopBar's tools menu holds its OWN "Select ANSI Encoding" parent item
  // (AnsiVersionSubmenu1), so its left-gutter badge has to be refreshed here
  // too - this popup used to sync only the checkmarks.
  ReplaceAnsiMenuParentIcon;
end;

procedure TAvroMainForm1.PopupTrayPopup(Sender: TObject);
begin
  SyncAnsiVersionChecks(mnuTraySelectAnsiEncoding);
  ReplaceAnsiMenuParentIcon;
end;

{ =============================================================================== }
{ Per-layout icons (system tray + encoding menus)                               }
{ =============================================================================== }

{ The ImageList1 slot holding AName's layout badge, adding it on first use and
  overwriting it in place when the active layout changes.

  -1 means "no badge for this name": an empty name, 'Default', an unassigned
  list, or a mapping that carries no icon (a legacy container, a plain .json, a
  damaged one, or a password-protected container that has not been unlocked
  yet). The caller then falls back to the built-in ANSI icon deliberately -
  never by accident.

  The frame is decoded at ImageList1's OWN metric, not at the tray's
  SM_CXSMICON one. GetAnsiTrayIcon answers with a 20/24/32 px handle on a
  scaled display, and ImageList1 is a 16x16 list: TImageList.AddIcon wants a
  bitmap matching the list, so putting the tray handle in there returned -1,
  FAnsiRootIconIndex stayed -1, and the parent item drew built-in slot 30 while
  the very same layout's badge looked right in the submenu (DrawIconEx on the
  raw HICON) and in the tray (handed to TIcon directly). CreateHIconAtSize
  picks a frame the container really carries, so this is the authored artwork
  at its own size rather than a rescaled copy.

  An image-list entry rather than a per-item TBitmap for the same reason the
  submenu rows use one: the renderer draws it with correct alpha, whereas a
  TBitmap assigned to TMenuItem.Bitmap left a dark background behind the
  transparent pixels.

  Exactly one slot is appended, on first use, and reused from then on: the list
  grows by one entry however often the user switches layouts, and slot 30 keeps
  its meaning as the built-in ANSI icon. }
function TAvroMainForm1.AnsiRootIconSlot(const AName: string): Integer;
var
  IconBytes: TBytes;
  H: HICON;
  Ico: TIcon;
  Cols, Rows, R: Integer;
begin
  Result := -1;
  if (AName = '') or SameText(AName, 'Default') then
    Exit;
  if not Assigned(ImageList1) then
    Exit;

  Cols := ImageList1.Width;
  Rows := ImageList1.Height;
  if (Cols <= 0) or (Rows <= 0) then
    Exit;

  // A cached slot describes the layout that put it there, so it is only reused
  // for that same name - and only while the list still holds it, because a
  // recreated image-list handle drops the appended entry.
  if SameText(AName, FAnsiRootIconName) and (FAnsiRootIconIndex >= 0) and
    (FAnsiRootIconIndex < ImageList1.Count) then
  begin
    Result := FAnsiRootIconIndex;
    Exit;
  end;

  // The one lookup the submenu badges resolve through as well: the icon cache
  // is keyed by the mapping's display name, which is what the menu item's Hint
  // carries and what AnsiVersion holds.
  IconBytes := GetMappingIconBytes(AName);
  if Length(IconBytes) = 0 then
    Exit;

  H := CreateHIconAtSize(IconBytes, Cols, Rows);
  if H = 0 then
  begin
    Log('AnsiRootIconSlot: could not decode a ' + IntToStr(Cols) + 'x' +
      IntToStr(Rows) + ' frame for the layout icon of "' + AName + '"');
    Exit;
  end;

  Ico := TIcon.Create;
  try
    // TIcon adopts the handle, and the list copies the image into its own
    // bitmap during AddIcon / ReplaceIcon, so freeing the wrapper is safe.
    Ico.Handle := H;
    H := 0;

    if (FAnsiRootIconIndex >= 0) and (FAnsiRootIconIndex < ImageList1.Count) then
    begin
      if ImageList_ReplaceIcon(ImageList1.Handle, FAnsiRootIconIndex, Ico.Handle) >= 0 then
        Result := FAnsiRootIconIndex
      else
        FAnsiRootIconIndex := -1;
    end;

    if (Result < 0) and (FAnsiRootIconIndex < 0) then
    begin
      R := ImageList1.AddIcon(Ico);
      if R >= 0 then
      begin
        FAnsiRootIconIndex := R;
        Result := R;
      end;
    end;
  finally
    Ico.Free;
    if H <> 0 then
      DestroyIcon(H);
  end;

  if Result >= 0 then
    FAnsiRootIconName := AName
  else
    Log('AnsiRootIconSlot: ImageList1 refused the ' + IntToStr(Cols) + 'x' +
      IntToStr(Rows) + ' icon of "' + AName + '"');
end;

{ A cached HICON for the tray at the CURRENT small-icon metric, or 0 when this
  layout has no icon.

  The metric is part of the cache key because it follows the display DPI: 16 px
  at 100%, 20 at 125%, 24 at 150%, 32 at 200%. Asking the icon library for
  exactly that size means Windows is never handed a mismatched handle to
  rescale, which is what made the tray icon look soft on a scaled display. }
function TAvroMainForm1.GetAnsiTrayIcon(const AName: string): HICON;
var
  IconBytes: TBytes;
  Cx, Cy: Integer;
  Key: string;
begin
  Result := 0;
  if (AName = '') or SameText(AName, 'Default') then
    Exit;
  if not Assigned(AnsiIconHandles) then
    Exit;

  Cx := GetSystemMetrics(SM_CXSMICON);
  Cy := GetSystemMetrics(SM_CYSMICON);
  if (Cx <= 0) or (Cy <= 0) then
    Exit;

  Key := Lowercase(AName) + '@' + IntToStr(Cx);
  if AnsiIconHandles.TryGetValue(Key, Result) then
    Exit;
  Result := 0; // TryGetValue leaves 0 behind on a miss

  IconBytes := GetMappingIconBytes(AName);
  if Length(IconBytes) = 0 then
    Exit;

  Result := CreateHIconAtSize(IconBytes, Cx, Cy);
  if Result <> 0 then
    AnsiIconHandles.AddOrSetValue(Key, Result);
end;

{ Frees every cached tray handle and invalidates the parent-badge slot. Called
  when the mapping folders are re-scanned (the icons belong to files that may be
  gone) and on the way out. The menu objects are left pointing at no image list,
  so a rebuild cannot draw from a freed one. }
procedure TAvroMainForm1.ReleaseAnsiIconCache;
var
  H: HICON;
begin
  // The appended ImageList1 slot itself is kept - appending a fresh one per
  // re-scan would grow the list without bound - but FAnsiRootIconName is
  // cleared so the next resolve rewrites that slot: the icon bytes behind it
  // are gone, and a renamed or deleted mapping must not keep drawing its old
  // badge.
  FAnsiRootIconName := '';
  // SubMenuImages, not Images: TMenuItem has no Images. VCL resolves an
  // item's image list by walking its parents for SubMenuImages and only then
  // falling back to the owning TMenu's Images, so setting it on these two
  // items gives their version lists the icons without giving every unrelated
  // item of Popup_Tools and Popup_Tray an image list they never had.
  if Assigned(AnsiVersionSubmenu1) then
    AnsiVersionSubmenu1.SubMenuImages := nil;
  if Assigned(mnuTraySelectAnsiEncoding) then
    mnuTraySelectAnsiEncoding.SubMenuImages := nil;

  if Assigned(AnsiIconHandles) then
  begin
    for H in AnsiIconHandles.Values do
      if H <> 0 then
        DestroyIcon(H);
    AnsiIconHandles.Clear;
  end;
end;

{ Gives BOTH "Select ANSI Encoding" parent items the badge of the active
  layout, so the root item's gutter and the checked submenu row can never
  disagree.

  There are two items with that caption - mnuTraySelectAnsiEncoding in
  Popup_Tray and AnsiVersionSubmenu1 in Popup_Tools - and only the tray one was
  assigned here, so the TopBar's tools menu showed no badge at all. A single
  slot serves both, because each popup carries Images = ImageList1.

  The badge follows AnsiVersion alone, exactly like the checkmark
  SyncAnsiVersionChecks draws: it identifies WHICH encoding is selected, not
  whether ANSI output happens to be switched on right now. Slot 30, the
  built-in ANSI icon, is the deliberate fallback when nothing is selected (an
  empty name or 'Default') or when the mapping carries no icon. }
procedure TAvroMainForm1.ReplaceAnsiMenuParentIcon;
const
  ANSI_ROOT_IMAGE_INDEX = 30;
var
  Slot: Integer;
begin
  if not Assigned(ImageList1) then Exit;

  Slot := AnsiRootIconSlot(AnsiVersion);
  if Slot < 0 then
    Slot := ANSI_ROOT_IMAGE_INDEX;

  if Assigned(mnuTraySelectAnsiEncoding) then
    mnuTraySelectAnsiEncoding.ImageIndex := Slot;
  if Assigned(AnsiVersionSubmenu1) then
    AnsiVersionSubmenu1.ImageIndex := Slot;
end;

{ Owner-draw handler for ANSI version submenu items.  Renders the gutter
  checkmark matching the AnsiVersionPicker style and the layout icon badge
  on the right side. }
procedure TAvroMainForm1.AnsiVersionItemAdvancedDrawItem(Sender: TObject;
  ACanvas: TCanvas; ARect: TRect; AState: TOwnerDrawState);
var
  Item: TMenuItem;
  IconHandle: HICON;
  X, Y: Integer;
  CapStr: string;
  TextH: Integer;
  GutterRect, TextRect: TRect;
const
  GUTTER_W = 26;
  ICON_SZ  = 16;
  ICON_PAD = 4;
begin
  Item := Sender as TMenuItem;

  { 1. Full background }
  ACanvas.Brush.Color := CurrentPalette.Background;
  ACanvas.FillRect(ARect);

  { 2. Hover highlight for non-checked items }
  if (not Item.Checked) and ((odSelected in AState) or (odHotLight in AState)) then
  begin
    ACanvas.Brush.Color := CurrentPalette.HoverFill;
    ACanvas.FillRect(ARect);
  end;

  { 3. Left indicator gutter }
  GutterRect := Rect(ARect.Left, ARect.Top, ARect.Left + GUTTER_W, ARect.Bottom);
  TextRect := Rect(ARect.Left + GUTTER_W, ARect.Top, ARect.Right, ARect.Bottom);

  if Item.Checked then
  begin
    { Checked: dark gutter + lighter text area }
    ACanvas.Brush.Color := CurrentPalette.SelectionFill;
    ACanvas.FillRect(GutterRect);

    ACanvas.Brush.Color := CurrentPalette.HoverFill;
    ACanvas.FillRect(TextRect);

    { Restore gutter brush before drawing the checkmark }
    ACanvas.Brush.Color := CurrentPalette.SelectionFill;
    ACanvas.Font.Color := CurrentPalette.SelectionText;
    ACanvas.Font.Style := [fsBold];
    DrawText(ACanvas.Handle, #$2713, -1, GutterRect,
      DT_CENTER or DT_VCENTER or DT_SINGLELINE);
    ACanvas.Font.Style := [];

    ACanvas.Font.Color := CurrentPalette.Text;
  end
  else
    ACanvas.Font.Color := CurrentPalette.Text;

  { 4. Caption text }
  CapStr := Item.Caption;
  TextH := ACanvas.TextHeight(CapStr);
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(ARect.Left + GUTTER_W + 4,
    ARect.Top + ((ARect.Bottom - ARect.Top - TextH) div 2), CapStr);
  ACanvas.Brush.Style := bsSolid;

  { 5. Right-side icon badge }
  IconHandle := 0;
  if (Item.Hint <> '') and (not SameText(Item.Hint, 'Default')) then
    IconHandle := GetAnsiTrayIcon(Item.Hint);
  if IconHandle <> 0 then
  begin
    X := ARect.Right - ICON_SZ - ICON_PAD;
    Y := ARect.Top + ((ARect.Bottom - ARect.Top - ICON_SZ) div 2);
    DrawIconEx(ACanvas.Handle, X, Y, IconHandle, ICON_SZ, ICON_SZ, 0, 0, DI_NORMAL);
  end;
end;

{ Owner-draw measure handler: accounts for the trailing icon badge width. }
procedure TAvroMainForm1.AnsiVersionItemMeasureItem(Sender: TObject;
  ACanvas: TCanvas; var Width, Height: Integer);
const
  GUTTER_W = 26;
  ICON_SZ  = 16;
  ICON_PAD = 4;
var
  Item: TMenuItem;
  HasIcon: Boolean;
begin
  Item := Sender as TMenuItem;
  HasIcon := (Item.Hint <> '') and (not SameText(Item.Hint, 'Default'));

  Width := GUTTER_W + 4 + ACanvas.TextWidth(Item.Caption) + 12;
  if HasIcon then
    Width := Width + ICON_SZ + ICON_PAD;
  Height := Max(GUTTER_W, ACanvas.TextHeight(Item.Caption) + 4);
end;

procedure TAvroMainForm1.UpdateTrayIcon;
var
  ICN: TIcon;
  AnsiHIcon, IconCopy: HICON;
begin
  // Both parent "Select ANSI Encoding" items are refreshed here, ABOVE the tray
  // / TopBar split: those menus are reachable while the TopBar is visible too,
  // and that branch used to return without touching the badge at all.
  ReplaceAnsiMenuParentIcon;

  if IsFormVisible('TopBar') = False then
  begin
    // try/finally: this runs on every mode change and on startup, so a failure
    // part-way through must not leak the TIcon.
    ICN := TIcon.Create;
    try
      if KeyLayout.KeyboardMode = bangla then
      begin
        if IsWin2000 = True then
          ImageList1.GetIcon(14, ICN)
        else
        begin
          if OutputIsBijoy = 'YES' then
          begin
            // The active layout's own icon, so the tray shows WHICH ANSI
            // encoding is running. CopyIcon is required: TIcon adopts and
            // destroys whatever handle it is given, and the cached handle has
            // to stay valid for the next tray update.
            AnsiHIcon := GetAnsiTrayIcon(AnsiVersion);
            IconCopy := 0;
            if AnsiHIcon <> 0 then
              IconCopy := CopyIcon(AnsiHIcon);
            if IconCopy <> 0 then
              ICN.Handle := IconCopy
            else
              ImageList1.GetIcon(30, ICN); // built-in ANSI icon
          end
          else
            ImageList1.GetIcon(20, ICN);
        end;

        if OutputIsBijoy = 'YES' then
          Tray.Hint := 'Avro Keyboard.' + #13 + 'Running Bangla Keyboard Mode (ANSI Version).' + #13 + 'Press ' + ModeSwitchKey + ' to switch to System default.'
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
    finally
      ICN.Free;
    end;
  end
  else
  begin
    // The floating TopBar is visible, which means the tray icon is hidden
    // (RestoreFromTray sets Tray.Visible := False before showing it), so there
    // is no tray icon to refresh here. The per-layout icon swap is deliberately
    // tray-only: the TopBar's own skinned "ANSI" badge stays its indicator.
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
  if (KeyLayout.KeyboardMode = bangla) and (OutputIsBijoy = 'NO') then
    KeyLayout.KeyboardMode := SysDefault
  else
  begin
    if KeyLayout.KeyboardMode <> bangla then
      KeyLayout.KeyboardMode := bangla;
    if OutputIsBijoy = 'YES' then
    begin
      OutputIsBijoy := 'NO';
      OptimizeMemoryUsage;
      RefreshSettings;
    end;
  end;
end;

procedure TAvroMainForm1.SetBengaliANSIMode;
begin
  if (KeyLayout.KeyboardMode = bangla) and (OutputIsBijoy = 'YES') then
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

    if KeyLayout.KeyboardMode <> bangla then
      KeyLayout.KeyboardMode := bangla;

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
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleAnsiVersionPicker;
begin
  ShowAnsiVersionPicker;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleLayoutPicker;
begin
  ShowLayoutPickerPopup;
end;

{ =============================================================================== }

procedure TAvroMainForm1.WMShowLayoutPicker(var Msg: TMessage);
begin
  ToggleLayoutPicker;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ApplyPendingANSISwitchRevert;
begin
  if not PendingANSISwitch then
    exit;
  PendingANSISwitch := False;

  if KeyLayout.KeyboardMode <> PreviousModeBeforeANSISwitch then
    KeyLayout.KeyboardMode := PreviousModeBeforeANSISwitch;
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
  if KeyLayout.KeyboardMode = SysDefault then
    exit;
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

function TAvroMainForm1.IsPickerOpen: Boolean;
begin
  Result := CurrentPicker <> nil;
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
  Execute_Something(ExtractFilePath(Application.ExeName) + 'Avro Text Converter.exe');
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
  WindoRecord:  TWindowRecord;
  hforewnd:     HWND;
  MapPath:      string;    // cached: this path used to be rebuilt 3x per tick
  MapWriteTime: TDateTime; // one disk stat per throttled tick
begin
  if (AnsiVersion <> 'Default') and (AnsiMappingDir <> '') then
  begin
    Dec(FMappingCheckCountdown);
    if FMappingCheckCountdown <= 0 then
    begin
      FMappingCheckCountdown := 10; // ~1 second at Interval = 100 ms
      try
        MapPath := AnsiMappingDir + AnsiVersion + '.AvroEnco';
        if not FileExists(MapPath) then
          MapPath := AnsiMappingDir + AnsiVersion + '.json';
        MapWriteTime := TFile.GetLastWriteTime(MapPath);
        if (MapWriteTime <> 0) and (MapWriteTime <> FActiveMappingLastWriteTime) then
        begin
          FActiveMappingLastWriteTime := MapWriteTime;
          AnsiEngineManager.InvalidateEngine(AnsiVersion);
          Log('ANSI Mapping Auto-Refreshed: ' + AnsiVersion);
        end;
      except
        // file missing or locked - the next throttled tick simply retries
      end;
    end;
  end;

  // Fallback poll: keep the encoding list in sync even if the directory
  // watcher misses the change notification (common when copying files in).
  Dec(FMappingListCheckCountdown);
  if FMappingListCheckCountdown <= 0 then
  begin
    FMappingListCheckCountdown := 15; // ~1.5 seconds at Interval = 100 ms
    RefreshAnsiMappingList;
  end;

  if Assigned(FDirectoryWatcher) then
    FDirectoryWatcher.CheckForChanges;

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
    if KeyLayout.KeyboardMode <> SysDefault then
      KeyLayout.KeyboardMode := SysDefault;
  end
  else
  begin
    if (WindoRecord.Mode = 'B') and (KeyLayout.KeyboardMode = SysDefault) then
      KeyLayout.KeyboardMode := bangla;
    if (WindoRecord.Mode = 'S') and (KeyLayout.KeyboardMode = bangla) then
      KeyLayout.KeyboardMode := SysDefault;
  end;
  KeyLayout.ResetDeadKey;
  LastWindow := hforewnd;
end;

procedure TAvroMainForm1.WMShowAnsiPicker(var Msg: TMessage);
begin
  ToggleAnsiVersionPicker;
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
  ClickedItem: TMenuItem;
  SelectedVersion, ErrorMsg, TargetPath: string;
  Password: AnsiString;
  ErrorLog: TStringList;
begin
  if not (Sender is TMenuItem) then Exit;
  ClickedItem := TMenuItem(Sender);

  SelectedVersion := ClickedItem.Hint;
  if SelectedVersion = '' then
  begin
    SelectedVersion := ClickedItem.Caption;
    SelectedVersion := StringReplace(SelectedVersion, '&', '', [rfReplaceAll]);
  end;

  // Default সিলেকশন
  if SameText(SelectedVersion, 'Default') then
  begin
    if not AnsiEngineManager.TrySwitchCached('Default') then
      Exit;
    AnsiVersion := 'Default';
    SyncActiveMappingTimestamp('Default');
    SaveAnsiVersionOnly;
    UpdateAnsiVersionMenuChecks('Default');
    // 'Default' has no container of its own, so this restores the built-in
    // icon rather than a layout's. AnsiVersion is committed above, so the
    // parent badge is resolved from it in this same event cycle instead of
    // lagging one click behind the checkmark.
    ReplaceAnsiMenuParentIcon;
    UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Encoding: Default');
    Exit;
  end;

  TargetPath := GetActiveEncoFilePath(SelectedVersion, AnsiMappingDir);
  if TargetPath = '' then
  begin
    Application.MessageBox(PChar('Mapping file not found: ' + SelectedVersion), 'Error',
      MB_ICONWARNING or MB_OK or MB_TOPMOST or MB_SETFOREGROUND);
    Exit;
  end;

  // For a password-protected encrypted file without a usable cached
  // password, ask for the password once up front; TrySetAnsiVersion then
  // reuses CachedEncoPassword and never prompts a second time.
  // Default-key files (flag $00) load transparently and never prompt.
  // Ask only when THIS encoding was never unlocked on this computer; the
  // per-file cache then unlocks every later switch silently (even after a
  // full restart). Default-key files never prompt.
  if IsEncoFile(TargetPath) and (GetEncoCachedPassword(TargetPath) = '') and
    (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_USER_PASSWORD) then
  begin
    if not PromptForPasswordAndValidate(TargetPath, Password) then
      Exit;
    CachedEncoPassword := Password;
    RememberEncoPassword(TargetPath, Password);
    SaveSettings;
  end;

  // Instant path first; on a RAM-cache MISS fall back to a blocking
  // on-demand repair parse (see the picker for why: an engine - usually the
  // largest, Ansi V3 - can miss the startup preload after a full
  // %AppData% cache wipe, and without this fallback the menu fails forever).
  ErrorMsg := '';
  if not AnsiEngineManager.TrySwitchCached(SelectedVersion) then
  begin
    Screen.Cursor := crHourGlass;
    ErrorLog := TStringList.Create;
    try
      if not AnsiEngineManager.SwitchEngine(SelectedVersion, ErrorLog) then
        ErrorMsg := 'Encoding is still being prepared. Please select it again.';
    finally
      ErrorLog.Free;
      Screen.Cursor := crDefault;
    end;
  end;
  if ErrorMsg = '' then
  begin
    AnsiVersion := SelectedVersion;
    SyncActiveMappingTimestamp(SelectedVersion);
    SaveAnsiVersionOnly;
    UpdateAnsiVersionMenuChecks(SelectedVersion);
    // AnsiVersion now holds the new selection, so the parent item's badge is
    // re-resolved right here, and the tray shows the icon of the layout that
    // is now in force.
    ReplaceAnsiMenuParentIcon;
    UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Encoding: ' + SelectedVersion);
    Exit;
  end;

  // Both the instant path and the on-demand repair parse failed. Always
  // shown (error, not a routine switch) so a failed V3 click can never look
  // like a success while typing still produces the previous engine's output.
  ShowAnsiToastNotification('ANSI encoding failed to load - try again');
end;

{ =============================================================================== }

{ View the description of a specific mapping }
procedure TAvroMainForm1.ReadAnsiDescriptionClick(Sender: TObject);
var
  MapName: string;
begin
  if not (Sender is TMenuItem) then Exit;
  MapName := (Sender as TMenuItem).Hint;
  if MapName = '' then
    MapName := (Sender as TMenuItem).Caption;
  ShowMappingDescription(MapName);
end;

{ =============================================================================== }

{ Exporting specific mappings }
procedure TAvroMainForm1.ExportSpecificMappingClick(Sender: TObject);
var
  MapName: string;
begin
  if not (Sender is TMenuItem) then Exit;
  MapName := (Sender as TMenuItem).Hint;
  if MapName = '' then
    MapName := (Sender as TMenuItem).Caption;
  ExportMappingFile(MapName);
end;

{ =============================================================================== }

procedure TAvroMainForm1.ImportAnsiMappingClick(Sender: TObject);
var
  OpenDialog: TOpenDialog;
  ErrMsg, ErrorMessages: string;
  I: Integer;

  procedure AddError(const AFileName, AMessage: string);
  begin
    if ErrorMessages <> '' then
      ErrorMessages := ErrorMessages + sLineBreak;
    ErrorMessages := ErrorMessages + ExtractFileName(AFileName) + ': ' + AMessage;
  end;

begin
  OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Filter := 'ANSI Mapping|*.AvroEnco';
    OpenDialog.DefaultExt := 'AvroEnco';
    OpenDialog.Title := 'Import ANSI Mapping';
    OpenDialog.Options := OpenDialog.Options + [ofAllowMultiSelect, ofFileMustExist];

    if OpenDialog.Execute then
    begin
      ErrorMessages := '';

      // Each selected file is imported independently; .json and .AvroEnco
      // files may be mixed freely inside one multi-select.
      for I := 0 to OpenDialog.Files.Count - 1 do
      begin
        ErrMsg := '';

        if SameText(ExtractFileExt(OpenDialog.Files[I]), '.AvroEnco') then
        begin
          // Flag-driven import (uAvroEncoImporter): header/flag inspection,
          // password prompt only for password-protected files, copy, menu
          // scan, per-file "Mapping imported: <name>" toast, and activation
          // for password-protected imports (default-key imports stay silent).
          if not ImportEncoFile(OpenDialog.Files[I], ErrMsg) and (ErrMsg <> '') then
            AddError(OpenDialog.Files[I], ErrMsg);
        end;
      end;

      // Refresh the ANSI version menus once after the batch.
      BuildAnsiVersionMenus;

      if ErrorMessages <> '' then
        MessageDlg('Import failed:'#13#10#13#10 + ErrorMessages, mtError, [mbOK], 0);
    end;
  finally
    OpenDialog.Free;
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
  MapName: string;
begin
  if Sender is TMenuItem then
  begin
    MapName := (Sender as TMenuItem).Hint;
    if MapName = '' then
      MapName := (Sender as TMenuItem).Caption;
    DeleteMappingFile(MapName);
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

procedure TAvroMainForm1.CleanupDuplicateMappings;
var
  SearchRec: TSearchRec;
  NameMap:   TDictionary<string, string>;
  FileTitle: string;
begin
  if not DirectoryExists(AnsiMappingDir) then
    exit;
  NameMap := TDictionary<string, string>.Create;
  try
    if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SearchRec) = 0 then
    begin
      repeat
        FileTitle := ChangeFileExt(SearchRec.Name, '');
        if NameMap.ContainsKey(Lowercase(FileTitle)) then
          DeleteFile(AnsiMappingDir + SearchRec.Name)
        else
          NameMap.Add(Lowercase(FileTitle), SearchRec.Name);
      until FindNext(SearchRec) <> 0;
      FindClose(SearchRec);
    end;
  finally
    NameMap.Free;
  end;
end;

{ =============================================================================== }

{ Fast switch UI update: never scans the directory and never destroys/rebuilds
  menu objects. Full BuildAnsiVersionMenus remains reserved for file changes. }
procedure TAvroMainForm1.SyncActiveMappingTimestamp(const AName: string);
var
  P: string;
begin
  FActiveMappingLastWriteTime := 0;
  if SameText(AName, 'Default') or (AnsiMappingDir = '') then Exit;
  P := GetActiveEncoFilePath(AName, AnsiMappingDir);
  if P = '' then Exit;
  try
    FActiveMappingLastWriteTime := TFile.GetLastWriteTime(P);
  except
    FActiveMappingLastWriteTime := 0;
  end;
end;

procedure TAvroMainForm1.UpdateAnsiVersionMenuChecks(const AName: string);
  procedure UpdateOne(AMenu: TMenuItem);
  var
    I: Integer;
    M: TMenuItem;
  begin
    if not Assigned(AMenu) then Exit;
    for I := 0 to AMenu.Count - 1 do
    begin
      M := AMenu.Items[I];
      if M.Hint <> '' then
        M.Checked := SameText(M.Hint, AName);
    end;
  end;
begin
  UpdateOne(AnsiVersionSubmenu1);
  UpdateOne(mnuTraySelectAnsiEncoding);
end;

{ =============================================================================== }
{ Build ANSI Version Menus (Fixed) }
{ =============================================================================== }

procedure TAvroMainForm1.BuildAnsiVersionMenus;
var
  Sep, MoreOptMenu, Item: TMenuItem;
  Snap: string;

  procedure AddDirectItem(ParentMenu: TMenuItem; const AName: string; AChecked: Boolean);
  var
    MItem: TMenuItem;
  begin
    MItem := TMenuItem.Create(ParentMenu);
    MItem.Caption := AName;
    MItem.Hint := AName;
    MItem.GroupIndex := 10;
    MItem.RadioItem := True;
    MItem.Checked := AChecked;
    // Owner-draw: icon badge rendered on the RIGHT side via OnAdvancedDrawItem,
    // leaving the LEFT gutter free for the native radio checkmark.
    MItem.OnAdvancedDrawItem := AnsiVersionItemAdvancedDrawItem;
    MItem.OnMeasureItem := AnsiVersionItemMeasureItem;
    MItem.OnClick := AnsiVersionMenuClick;
    ParentMenu.Add(MItem);
  end;

  procedure AddMappingActionSubmenu(ParentMore: TMenuItem; const AName: string; IsDefault: Boolean);
  var
    MSub, ActionItem: TMenuItem;
  begin
    MSub := TMenuItem.Create(ParentMore);
    MSub.Caption := AName;
    MSub.Hint := AName;
    ParentMore.Add(MSub);

    ActionItem := TMenuItem.Create(MSub);
    ActionItem.Caption := 'Information';
    ActionItem.Hint := AName;
    ActionItem.OnClick := ReadAnsiDescriptionClick;
    MSub.Add(ActionItem);

    ActionItem := TMenuItem.Create(MSub);
    ActionItem.Caption := 'Export Mapping...';
    ActionItem.Hint := AName;
    ActionItem.OnClick := ExportSpecificMappingClick;
    MSub.Add(ActionItem);

    if not IsDefault then
    begin
      ActionItem := TMenuItem.Create(MSub);
      ActionItem.Caption := 'Delete Mapping';
      ActionItem.Hint := AName;
      ActionItem.OnClick := DeleteAnsiMappingClick;
      MSub.Add(ActionItem);
    end;
  end;

  procedure BuildSingleMenu(AMenu: TMenuItem);
  var
    I: Integer;
    DisplayName: string;
  begin
    if not Assigned(AMenu) then Exit;
    AMenu.Clear;

    // ১. Default
    AddDirectItem(AMenu, 'Default', SameText(AnsiVersion, 'Default'));

    // ২. স্ক্যান করা সব ফাইল
    // AnsiMappingNames is sorted in the shared natural order by
    // RefreshAnsiMappingNames (called just before this) and is the very same
    // list the version picker shows. Enumerating AvroEncoFiles.Keys instead
    // meant reading a hash table, which is why this menu could show
    // Default, V1, V4, V2, V3 while the picker looked sorted.
    if Assigned(AnsiMappingNames) then
      for I := 0 to AnsiMappingNames.Count - 1 do
      begin
        DisplayName := AnsiMappingNames[I];
        if not SameText(DisplayName, 'Default') then
          AddDirectItem(AMenu, DisplayName, SameText(AnsiVersion, DisplayName));
      end;

    // Separator
    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);

    // ৩. More Options
    MoreOptMenu := TMenuItem.Create(AMenu);
    MoreOptMenu.Caption := 'More Options';
    AMenu.Add(MoreOptMenu);

    AddMappingActionSubmenu(MoreOptMenu, 'Default', True);

    // Same sorted order as the submenu above (and as the picker).
    if Assigned(AnsiMappingNames) then
      for I := 0 to AnsiMappingNames.Count - 1 do
      begin
        DisplayName := AnsiMappingNames[I];
        if not SameText(DisplayName, 'Default') then
          AddMappingActionSubmenu(MoreOptMenu, DisplayName, False);
      end;

    // Separator
    Sep := TMenuItem.Create(MoreOptMenu);
    Sep.Caption := '-';
    MoreOptMenu.Add(Sep);

    Item := TMenuItem.Create(MoreOptMenu);
    Item.Caption := 'Import Mapping...';
    Item.OnClick := ImportAnsiMappingClick;
    MoreOptMenu.Add(Item);

    Item := TMenuItem.Create(MoreOptMenu);
    Item.Caption := 'Locate Mapping...';
    Item.OnClick := OpenAnsiMappingDirClick;
    MoreOptMenu.Add(Item);
  end;

begin
  // Full disk re-scan only when the mapping folder actually changed: this
  // runs on every version switch and picker refresh, and the scan + menu
  // rebuild is the visible latency after a click. Folder-change paths
  // (watcher / poll) scan first and refresh the snapshot themselves.
  Snap := BuildAnsiMappingFolderList;
  if Snap <> FAnsiMappingSnapshot then
  begin
    FAnsiMappingSnapshot := Snap;
    CleanupDuplicateMappings;
    // ScanAvroEncoFiles drops the per-mapping icon bytes; the GDI handles and
    // the parent-badge slot derived from them have to be invalidated with them,
    // or a renamed or deleted mapping would keep drawing its old icon.
    ReleaseAnsiIconCache;
    ScanAvroEncoFiles(AnsiMappingDir);
  end;
  RefreshAnsiMappingNames;
  BuildSingleMenu(AnsiVersionSubmenu1);
  BuildSingleMenu(mnuTraySelectAnsiEncoding);

  // Child items now use OnAdvancedDrawItem for trailing icon badges, so
  // SubMenuImages is no longer needed for them.  Both root parent items -
  // mnuTraySelectAnsiEncoding and AnsiVersionSubmenu1 - get their left-gutter
  // icon from ImageList1 in ReplaceAnsiMenuParentIcon.
end;

end.
