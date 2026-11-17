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
  Vcl.Themes,
  uAvroDirectoryWatcher,
  uAvroEngineStats;

const
  { How long the user must be idle (no input ANYWHERE on the system) before the
    idle timer drops the parked ANSI engines and the per-mapping icon bytes.

    Both are regenerable: the engine comes back from its container on the next
    switch (tens of ms, one time), the icons from the next menu build. Keeping
    them resident for a user who has walked away is what the 2 MB -> 6 MB
    report was measuring, so the release is the point - the delay only decides
    how much instant switching this session gets to keep. }
  IdleEngineReleaseMinutes = 10;

type
  TMenuItemExtended = class(TMenuItem)
    private
      fValue: string;
    published
      property Value: string read fValue write fValue;
  end;

type
  TWindowInputMode = (wimEnglish, wimBanglaUnicode, wimBanglaANSI);
  TWindowBanglaMode = (wbmUnicode, wbmANSI);

  TWindowRecord = record
    Mode: TWindowInputMode;
    LastBanglaMode: TWindowBanglaMode;
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
    KeyboardLayoutEditorBuildcustomlayouts1: TMenuItem;
    SkinDesignerDesignyourownskin1: TMenuItem;
    Options1: TMenuItem;
    N4: TMenuItem;
    N5: TMenuItem;
    CheckupdateforAvroKeyboard1: TMenuItem;
    N6: TMenuItem;
    FreeBanglaFonts1: TMenuItem;
    DownloadMoreResources1: TMenuItem;
    wwwOmicronLabcom1: TMenuItem;
    UserForum1: TMenuItem;
    AvroPhoneticEnglishtoBangla1: TMenuItem;
    N7: TMenuItem;
    Showactivekeyboardlayout1: TMenuItem;
    Jumptosystemtray1: TMenuItem;
    Exit1: TMenuItem;
    N11: TMenuItem;
    Aboutcurrentkeyboardlayout1: TMenuItem;
    AboutAvroKeyboard1: TMenuItem;
    ogglekeyboardmode1: TMenuItem;
    Jumptotop1: TMenuItem;
    Jumptosystemtray2: TMenuItem;
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
    AboutAvroKeyboard3: TMenuItem;
    N32: TMenuItem;
    Exit3: TMenuItem;
    AvroPhoneticEnglishtoBangla3: TMenuItem;
    N34: TMenuItem;
    Showactivekeyboardlayout3: TMenuItem;
    LocateKeyboardLayout2: TMenuItem;
    WindowCheck: TTimer;
    InternetCheck: TTimer;
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
    N39: TMenuItem;
    GetAcrobatReader3: TMenuItem;
    AvroKeyboardonFacebook2: TMenuItem;
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
    AppEvents: TApplicationEvents;
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCreate(Sender: TObject);
    procedure AvroPhoneticEnglishtoBangla3Click(Sender: TObject);
    procedure Exit1Click(Sender: TObject);
    procedure ogglekeyboardmode2Click(Sender: TObject);
    procedure Jumptotop1Click(Sender: TObject);
    procedure Showactivekeyboardlayout1Click(Sender: TObject);
    procedure LocateKeyboardLayoutClick(Sender: TObject);
    procedure AvroMouseClicknType2Click(Sender: TObject);
    procedure wwwOmicronLabcom1Click(Sender: TObject);
    procedure UserForum1Click(Sender: TObject);
    procedure CheckupdateforAvroKeyboard1Click(Sender: TObject);
    procedure FreeBanglaFonts1Click(Sender: TObject);
    procedure DownloadMoreResourcesClick(Sender: TObject);
    procedure Jumptosystemtray1Click(Sender: TObject);
    procedure Options1Click(Sender: TObject);
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
    procedure AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
    procedure AppEventsException(Sender: TObject; E: Exception);
    private
      { Private declarations }
      WindowDict:                   TDictionary<HWND, TWindowRecord>;
      MyCurrentLayout:              string;
      MyCurrentKeyboardMode:        enumMode;
      LastWindow:                   HWND;
      PendingANSISwitch:            Boolean;
      PreviousModeBeforeANSISwitch: enumMode;
      PreviousOutputBeforeANSISwitch: string;
      PendingANSISwitchWindow:        HWND;
      PendingANSISwitchRecord:        TWindowRecord;
      PendingANSISwitchHadRecord:     Boolean;
      PendingANSISwitchEnablesBangla: Boolean;
      FApplyingWindowMode:            Boolean;
      FActiveMappingLastWriteTime:  TDateTime;
      FMappingCheckCountdown:       Integer; // throttles the ANSI mapping disk check
      FMappingListCheckCountdown:   Integer; // throttles the ANSI mapping folder-list poll
      FAnsiMappingSnapshot:         string;  // last seen file/size/time list of AnsiMappingDir
      FLayoutSnapshot:              string;  // last seen file-name list of the layouts folder
      FLayoutCheckCountdown:        Integer; // throttles the keyboard-layouts folder-list poll
      { >0 while a menu that carries dynamic items is being tracked by Windows:
        Popup_Tray's "Select keyboard layout" / "Select ANSI Encoding" submenus,
        Popup_LayoutList, and Popup_Tools' AnsiVersionSubmenu1.  Freeing or
        clearing a TMenuItem calls RebuildHandle (Vcl.Menus), which destroys and
        rebuilds the HMENU that menu's own track loop is still displaying, so a
        timer-driven rebuild has to wait for it to close. }
      FTrackedMenusOpen: Integer;
      FDirectoryWatcher: TAvroDirectoryWatcher;
      { Application.OnException reports once per session, not once per fault. }
      FUnhandledReported: Boolean;
      { One-shot tray balloon when the mapping folder is empty at startup. }
      FNoMappingBalloonShown: Boolean;
      { One-shot tray balloon when autodict.dct could not be loaded (the load
        itself is silent - see uAutoCorrect). }
      FNoDictBalloonShown: Boolean;
      { One-shot tray balloon when Database.db3 is absent at startup - the
        failure is just as silent (see uDBase), and just as fatal to phonetic
        candidates. }
      FNoDatabaseBalloonShown: Boolean;

      { Per-layout icons, decoded from the payload each container carries.

        The tray needs its own HICON at the metric Windows asks for, and that
        metric changes with the display DPI, so AnsiIconHandles is keyed
        'name@size' - a DPI change then builds a second handle at the new size
        instead of handing the shell a stale one to rescale.

        Handles here are handed to the tray through CopyIcon, so the tray owns a
        private copy and this cache stays valid across tray updates. The active
        menu icon uses one reusable ImageList1 slot. }
      AnsiIconHandles:    TDictionary<string, HICON>;
      FAnsiRootIconIndex: Integer;
      FAnsiRootIconName:  string;
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
      procedure HandleRemoteEncoRefresh;
      function BuildAnsiMappingFolderList: string;
      procedure RefreshAnsiMappingList;
      function BuildLayoutFolderList: string;
      procedure RefreshLayoutMenuItems;
      procedure RefreshAnsiMappingNames;
      { Resolves and activates the persisted ANSI selection with the startup
        rules (baseline only for an empty catalog, exact companion first,
        one-time legacy migration, missing exact file never falls back).
        AContext is only used in the debug log. }
      function ApplyPersistedAnsiSelection(const AContext: string): Boolean;
      procedure IgnoreCapsLockClick(Sender: TObject);
      procedure PopupToolsPopup(Sender: TObject);
      procedure PopupTrayPopup(Sender: TObject);
      procedure TrackedMenusPopup(Sender: TObject);
      procedure TrackedMenusClose(Sender: TObject);

      procedure WMCopyData(var Msg: TWMCopyData); message WM_COPYDATA;
      procedure WMShowAnsiPicker(var Msg: TMessage); message WM_APP + 1;
      procedure WMShowLayoutPicker(var Msg: TMessage); message WM_APP + 3;
      { The Text Converter Launcher hotkey (KeyboardHook) lands here. Posted
        rather than called so LaunchAvroTextConverter's missing-exe MessageDlg
        never runs inside the hook callback (see its note there). }
      procedure WMLaunchTextConverter(var Msg: TMessage); message WM_APP + 7;
      { RefreshSettings asked for from inside the keyboard hook (see its own
        comment): the work runs here, on the main loop, instead. }
      procedure WMDeferredRefresh(var Msg: TMessage); message WM_APP + 11;
      { ANSI mode may open a warning form, so the hook posts this to the main
        loop instead of creating UI inside the low-level callback. }
      procedure WMSwitchToAnsiMode(var Msg: TMessage); message WM_APP + 12;

    public
      { Public declarations }
      KeyboardModeChanged: Boolean;
      KeyLayout:           TLayout;
      Updater:             TUpdateCheck;
      AnsiVersionSubmenu1: TMenuItem;
      { Cached, sorted list of mapping display names (labels), parallel to
        AnsiMappingFileNames. Kept fresh by the directory watcher / periodic
        poll. The ANSI picker opens from this list with zero disk I/O. }
      AnsiMappingNames: TStringList;
      { Every exact mapping file name in the same order as AnsiMappingNames.
        This - never a caption - is the menu and picker identity. }
      AnsiMappingFileNames: TStringList;
      IgnoreCapsLock1:  TMenuItem;
      IgnoreCapsLock2:  TMenuItem;
      procedure AnsiVersionMenuClick(Sender: TObject);
      procedure ReadAnsiDescriptionClick(Sender: TObject);
      procedure ExportSpecificMappingClick(Sender: TObject);
      procedure DeleteAnsiMappingClick(Sender: TObject);
      procedure ImportAnsiMappingClick(Sender: TObject);
      procedure OpenAnsiMappingDirClick(Sender: TObject);
      procedure NoMappingBalloonClick(Sender: TObject);
      procedure NoDictBalloonClick(Sender: TObject);
      procedure ShowAutoCorrectMissingBalloon;
      procedure CheckWordDatabasePresence;
      procedure ShowMissingDatabaseBalloon;
      procedure MissingDatabaseBalloonClick(Sender: TObject);
      { Reloads the word database after the resource downloader installed it -
        the load already failed silently once this session (uDBase), and
        RefreshSettings is the only other place that retries it. }
      procedure ReloadWordDatabaseIfUsed;

      { Re-scans the layouts folder and rewrites both menus' dynamic layout items
        when the folder's contents changed.  Public because the resource
        downloader calls it after installing a layout: the layouts folder has no
        directory watcher (only AnsiMappingDir does), so nothing else would put a
        freshly downloaded layout into the menus before the next restart. }
      procedure RefreshLayoutList;
      { The cached HICON for a mapping at the CURRENT small-icon metric, or 0
        when that mapping carries no icon (empty name, a legacy container, a
        plain .json, or one whose icon failed to decode).

        The handle is BORROWED: it belongs to the DPI-keyed cache filled by the
        startup preload and is freed by ReleaseAnsiIconCache, so a caller must
        never destroy it. It supplies the active mapping's tray icon. }
      function GetAnsiTrayIcon(const AName: string): HICON;

      procedure BuildAnsiVersionMenus;
      procedure UpdateAnsiVersionMenuChecks(const AFileName: string);
      procedure SyncAnsiVersionChecks(AMenu: TMenuItem);
      procedure SyncActiveMappingTimestamp(const AFileName: string);
      function GetMyCurrentKeyboardMode: enumMode;
      procedure ExitApp;
      function GetMyCurrentLayout: string;
      procedure RefreshSettings;
      procedure SyncCurrentWindowMode;
      procedure UpdateTrayIcon;
      function GetModeWindow: HWND;
      procedure RecordCurrentWindowMode;
      procedure SetCurrentWindowBanglaPreference(const IsAnsi: Boolean);
      procedure ApplyWindowMode(const AWindow: HWND; const ARecord: TWindowRecord);
      procedure BeginPendingANSISwitch(const EnablesBangla: Boolean);

      procedure RestoreFromTray;
      procedure OpenHelpFile(const HelpID: Integer);
      function ResolveHelpPdf(const AFileName: string): string;
      procedure CollectHelpPdfs(AList: TStringList);
      procedure RebuildDynamicHelp(AParent: TMenuItem; AInsertIndex: Integer);
      procedure DynamicHelpPopup(Sender: TObject);
      procedure DynamicHelpClick(Sender: TObject);
      procedure ShowOnTray;
      procedure ToggleMode;
      procedure SetBengaliUnicodeMode;
      procedure SetBengaliANSIMode;
      procedure ToggleAnsiVersionPicker;
      procedure ToggleLayoutPicker;
      procedure TopBarDocToTop;
      function RouteKeyToPicker(AVkCode: Integer): Boolean;
      procedure ReportUnhandledException(E: Exception);
      function TransferKeyDown(const KeyCode: Integer; var Block: Boolean): string;
      procedure TransferKeyUp(const KeyCode: Integer; var Block: Boolean);
      function IsPickerOpen: Boolean;
      procedure TrimAppMemorySize;
      procedure Initmenu;
      procedure ToggleOutputEncoding;
      procedure ApplyPendingANSISwitchRevert;
      procedure CommitPendingANSISwitch;
      procedure LaunchAvroTextConverter;
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  AvroMainForm1: TAvroMainForm1;

implementation

{$R *.dfm}

uses
  uRegistrySettings,
  uPickerSupport,
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
  uStyledMenuBorder,
  System.UITypes,
  uKeyboardMacro,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAvroEncoImporter,
  uAvroEncoIconSection,
  uAvroLayoutUI,
  ufrmResourceBrowser,
  uAvroBaseline,
  uAnsiEngineManager,
  uAvroMigrationRunner;

var
  { At most one visible startup-failure report per session - see
    ReportStartupFailure. }
  FStartupFailureReported: Boolean;

  { =============================================================================== }

  { One visible report per session for a startup step that raised, plus the
    startup-log line that makes the failure debuggable from a bug report. A tray
    balloon cannot be used here: the tray is created inside LoadApp, so it may not
    exist yet, and in top-bar mode a balloon is invisible anyway - which is
    exactly how this class of failure used to stay silent. }
procedure ReportStartupFailure(const AStep: string; E: Exception);
var
  Msg: string;
begin
  StartupLogException('startup step failed: ' + AStep, E);
  if FStartupFailureReported then
    Exit;
  FStartupFailureReported := True;

  Msg := 'Avro Keyboard could not complete the startup step "' + AStep + '".' + sLineBreak + sLineBreak;
  if Assigned(E) then
    Msg := Msg + E.ClassName + ': ' + E.Message + sLineBreak + sLineBreak;
  Msg := Msg + 'Avro keeps running with the parts that did load.' + sLineBreak + StartupLogHint;

  MessageBox(0, PChar(Msg), 'Avro Keyboard', MB_OK or MB_ICONWARNING or MB_SETFOREGROUND);
end;

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

{ Application.OnException, through the AppEvents component the form already
  hosts (Vcl.AppEvnts' multi-caster routes Application.OnException here).

  It exists because an unhandled VCL exception in this application - a hidden
  owner window with MainFormOnTaskBar = False - can end the process with no
  dialog and no tray icon at all, which is what "Avro Keyboard just
  disappeared" looks like from the outside. }
procedure TAvroMainForm1.AppEventsException(Sender: TObject; E: Exception);
begin
  ReportUnhandledException(E);
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
  Execute_Something('https://www.facebook.com/AvroCommunity');
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

procedure TAvroMainForm1.Dictionarymodeisdefault1Click(Sender: TObject);
begin
  PhoneticMode := 'DICT';
  RefreshSettings;
end;

procedure TAvroMainForm1.Jumptotop1Click(Sender: TObject);
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
  UnregisterFontFolder(ExtractFilePath(Application.ExeName) + 'fonts\');
  Log('Portable: UnregisterFontFolder');
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
  FreeAndNil(AnsiMappingFileNames);
  { Unhook BEFORE the engine goes: the callback dereferences KeyLayout
    (TransferKeyDown/Up), so a keystroke arriving in that window would land on a
    freed TLayout. RemoveHook is idempotent now, and TLayout.Destroy unhooks
    again harmlessly. }
  RemoveHook;
  Log('RemoveHook');
  FreeAndNil(KeyLayout);
  Log('FreeAndNil: WindowDict, KeyLayout');
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
  { From here until the keyboard hook is live this form is the only thing
    running, and an exception that escapes FormCreate never reaches the message
    loop: the user gets a process they cannot see - no top bar, no tray, no
    hook - while the app still shows up in Task Manager. Every step that can
    plausibly fail is therefore contained and reported (see
    ReportStartupFailure) and the ones that matter are logged. }
  StartupLogSection('FormCreate enter');
  StartupLogEnvironment;

  HandleThemes;

  // Hide the form
  Left := Screen.Width + 5000;
  Show;
  Application.ProcessMessages;

  AnsiMappingNames := TStringList.Create;
  AnsiMappingFileNames := TStringList.Create;
  AnsiIconHandles := TDictionary<string, HICON>.Create;
  FAnsiRootIconIndex := -1;

  { Settings: a corrupted value used to raise out of ValidateSettings here,
    before any window existed. LoadSettings now repairs what it can
    (FillSafeDefaults) and this guard keeps the rest of startup alive. }
  try
    LoadSettings;
  except
    on E: Exception do
      ReportStartupFailure('LoadSettings', E);
  end;

  // The call above only covered the built-in default - AppThemeMode is read
  // here, so the stored theme has to be applied once more.
  try
    HandleThemes;
  except
    on E: Exception do
      ReportStartupFailure('HandleThemes', E);
  end;

  StartupLog('FormCreate: LoadApp starting');
  try
    LoadApp;
    StartupLog('FormCreate: LoadApp returned');
  except
    on E: Exception do
      ReportStartupFailure('LoadApp', E);
  end;

  Popup_Help.OnPopup := DynamicHelpPopup;
  { Popup_Tray's real handler is PopupTrayPopup (icon badges + checkmarks).  It
    was wired to DynamicHelpPopup here - a copy of the line above - and
    RefreshSettings later overwrote it, so until the first settings refresh the
    tray popup ran the help handler.  Wire it once, correctly, right now. }
  Popup_Tray.OnPopup := PopupTrayPopup;
  { Timer-driven menu rebuilds are held off while a menu carrying dynamic items
    is tracked: freeing or clearing a TMenuItem calls RebuildHandle (Vcl.Menus),
    which destroys and rebuilds the HMENU Windows is still displaying.
    TPopupMenu.Popup fires OnPopup (DoPopup) and OnClose (DoClose, right after
    TrackPopupMenu returns), so the pair is balanced for every route into these
    menus - including the tray icon, whose TTrayIcon calls FPopupMenu.Popup
    directly.  Submenus are tracked inside the same Popup call and need no hooks
    of their own.  RefreshSettings re-assigns Popup_Tray/Popup_Tools.OnPopup, so
    the open half of the count lives inside PopupTrayPopup/PopupToolsPopup;
    every OnClose is assigned here once and never overwritten. }
  Popup_Tray.OnClose := TrackedMenusClose;
  Popup_LayoutList.OnPopup := TrackedMenusPopup;
  Popup_LayoutList.OnClose := TrackedMenusClose;
  Popup_Tools.OnClose := TrackedMenusClose;

  StartupLogSection('FormCreate end');
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
  begin
    // Drop the parked engines and the per-mapping icon bytes BEFORE trimming:
    // the trim only moves pages out of the working set, it does not free the
    // heap, so releasing has to come first or the app just reports the same
    // footprint with colder pages. The LIVE engine is untouched - typing keeps
    // working, and only a later version switch pays for a fresh parse.
    AnsiEngineManager.ReleaseIdleEngines(IdleEngineReleaseMinutes);
    TrimAppMemorySize;
    // Idle process: let the OS keep our pages on the block list until the user
    // comes back. The else branch restores normal priority on the next tick.
    SetAvroMemoryPriority(ampLow);
  end
  else
    SetAvroMemoryPriority(ampNormal);
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
  if lngHWND = 0 then
    Exit(True);

  // ১. নিজস্ব ফর্ম ও সিস্টেম ট্রে
  if (lngHWND = FindWindow('Shell_TrayWnd', nil)) or (lngHWND = FindWindowEx(FindWindow('Shell_TrayWnd', nil), 0, 'TrayNotifyWnd', nil)) or
    (lngHWND = Self.Handle) then
    Exit(True);

  if IsFormLoaded('TopBar') and (lngHWND = Topbar.Handle) then
    Exit(True);
  if IsFormLoaded('frmEncodingWarning') and (lngHWND = frmEncodingWarning.Handle) then
    Exit(True);
  if (CurrentPicker <> nil) and (lngHWND = CurrentPicker.Handle) then
    Exit(True);
  if (CurrentLayoutPicker <> nil) and (lngHWND = CurrentLayoutPicker.Handle) then
    Exit(True);
  if IsFormLoaded('frmAvroPasswordDlg') and (frmAvroPasswordDlg <> nil) and (lngHWND = frmAvroPasswordDlg.Handle) then
    Exit(True);
  if IsFormLoaded('TfrmAnsiToast') or IsFormLoaded('TfrmLayoutToast') then
    Exit(True);

  // ২. 🛡️ অত্যন্ত গুরুত্বপূর্ণ: মেনু এবং পপআপ ক্লাস (#32768) যাতে টপবারকে সামনে এনে ক্লিক ব্লক না করে
  ClsName := GetWindowClassName(lngHWND);
  if (ClsName = '#32768') or (ClsName = 'PSDocDragFeedback') or (ClsName = 'ComboLBox') then
    Exit(True);
end;

{$HINTS ON}
{ =============================================================================== }

procedure TAvroMainForm1.Initmenu;
begin
  RefreshLayoutMenuItems;

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

{ Adds an entry for every .avrolayout on disk to the tray's "Select keyboard
  layout" submenu (Selectkeyboardlayout2) and to the TopBar's layout popup
  (Popup_LayoutList), and removes the entry of any layout that is gone.

  The removal half is new: these loops were add-only (ItemFound), so a deleted
  .avrolayout stayed in both menus for the rest of the session - and with
  RefreshLayoutList polling the folder, pruning is what makes a deletion take
  effect at all.

  Membership is a dictionary lookup on both sides.  The older code asked the
  disk list a linear question per menu item (LayoutOnDisk) and re-scanned the
  whole menu for every layout, i.e. O(n*m) on each folder change; the loop
  shapes, the ordering, the anchors and what is created are unchanged. }
procedure TAvroMainForm1.RefreshLayoutMenuItems;
var
  I:             Integer;
  sCaption, Key: string;
  OnDisk:        TDictionary<string, Boolean>;
  PresentTray:   TDictionary<string, Boolean>;
  PresentTopBar: TDictionary<string, Boolean>;

  { The dynamic (Tag = 9903) captions of one menu, keyed lowercase. }
  procedure CollectItems(AMenu: TMenuItem; const AInto: TDictionary<string, Boolean>);
  var
    J: Integer;
  begin
    for J := 0 to AMenu.Count - 1 do
      if AMenu.Items[J].Tag = 9903 then
        AInto.AddOrSetValue(Lowercase((AMenu.Items[J] as TMenuItemExtended).Value), True);
  end;

{ One dynamic item, inserted right below AAfter - the placement both menus
  use.  AOwner stays the popup that owns the item, exactly as before. }
  procedure AddLayoutItem(const AOwner: TComponent; const AInto, AAfter: TMenuItem; const ACaption: string);
  var
    M: TMenuItemExtended;
  begin
    M := TMenuItemExtended.Create(AOwner);
    M.Caption := ACaption;
    M.Value := ACaption;
    M.RadioItem := True;
    M.Tag := 9903;
    M.OnClick := MenuFixedLayoutClick;
    AInto.Insert(AAfter.MenuIndex + 1, M);
  end;

begin
  { A folder read that failed leaves this nil (LoadKeyboardLayoutNames frees it
    first); there is nothing to reconcile then. }
  if KeyboardLayouts = nil then
    Exit;

  OnDisk := TDictionary<string, Boolean>.Create;
  PresentTray := TDictionary<string, Boolean>.Create;
  PresentTopBar := TDictionary<string, Boolean>.Create;
  try
    { RemoveExtension keeps these keys comparable with the item values whatever
      the loader hands over; LoadKeyboardLayoutNames already strips it. }
    for I := 0 to KeyboardLayouts.Count - 1 do
      OnDisk.AddOrSetValue(Lowercase(RemoveExtension(KeyboardLayouts[I])), True);

    CollectItems(Selectkeyboardlayout2, PresentTray);
    CollectItems(Popup_LayoutList.Items, PresentTopBar);

    // Prune first: Tag = 9903 marks the dynamic layout items.  A layout removed
    // from disk must disappear from BOTH menus, not merely stop being added.
    for I := Selectkeyboardlayout2.Count - 1 downto 0 do
      if Selectkeyboardlayout2.Items[I].Tag = 9903 then
      begin
        Key := Lowercase((Selectkeyboardlayout2.Items[I] as TMenuItemExtended).Value);
        if not OnDisk.ContainsKey(Key) then
        begin
          PresentTray.Remove(Key);
          Selectkeyboardlayout2.Items[I].Free;
        end;
      end;

    for I := Popup_LayoutList.Items.Count - 1 downto 0 do
      if Popup_LayoutList.Items[I].Tag = 9903 then
      begin
        Key := Lowercase((Popup_LayoutList.Items[I] as TMenuItemExtended).Value);
        if not OnDisk.ContainsKey(Key) then
        begin
          PresentTopBar.Remove(Key);
          Popup_LayoutList.Items[I].Free;
        end;
      end;

    // Add every layout neither menu carries yet.  Counting DOWN matters: each
    // item goes in at the same index, so the last one inserted ends up on top.
    for I := KeyboardLayouts.Count - 1 downto 0 do
    begin
      sCaption := RemoveExtension(KeyboardLayouts[I]);
      Key := Lowercase(sCaption);

      if not PresentTray.ContainsKey(Key) then
      begin
        AddLayoutItem(Popup_Tray, Selectkeyboardlayout2, AvroPhoneticEnglishtoBangla3, sCaption);
        PresentTray.AddOrSetValue(Key, True);
      end;

      if not PresentTopBar.ContainsKey(Key) then
      begin
        AddLayoutItem(Popup_LayoutList, Popup_LayoutList.Items, AvroPhoneticEnglishtoBangla1, sCaption);
        PresentTopBar.AddOrSetValue(Key, True);
      end;
    end;
  finally
    OnDisk.Free;
    PresentTray.Free;
    PresentTopBar.Free;
  end;
end;

{$HINTS Off}

procedure TAvroMainForm1.InternetCheckTimer(Sender: TObject);
var
  HowMayDay: Integer;
begin
  HowMayDay := 0;
  if AvroUpdateCheck <> 'YES' then
    Exit;

  try
    HowMayDay := DaysBetween(Now, AvroUpdateLastCheck);
  except
    HowMayDay := 7;
  end;

  if HowMayDay >= 7 then
  begin
    if Updater.IsConnected = False then
      Exit;

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

function TAvroMainForm1.GetModeWindow: HWND;
begin
  Result := GetForegroundWindow;
  if (Result = 0) or not IsWindow(Result) then
  begin
    Result := 0;
    Exit;
  end;
  if IgnorableWindow(Result) then
    Result := LastWindow;
  if (Result = 0) or not IsWindow(Result) then
    Result := 0;
end;

procedure TAvroMainForm1.RecordCurrentWindowMode;
var
  ActiveWindow: HWND;
  WindowRecord: TWindowRecord;
  HasRecord: Boolean;
begin
  if (SwitchingMode = SWITCHING_MODE_GLOBAL) or FApplyingWindowMode or (not Assigned(WindowDict)) or (not Assigned(KeyLayout)) then
    Exit;

  ActiveWindow := GetModeWindow;
  if ActiveWindow = 0 then
    Exit;
  if PendingANSISwitch and (PendingANSISwitchWindow = ActiveWindow) then
    Exit;

  HasRecord := WindowDict.TryGetValue(ActiveWindow, WindowRecord);
  if not HasRecord then
  begin
    WindowRecord.Mode := wimEnglish;
    WindowRecord.LastBanglaMode := wbmUnicode;
  end;

  if KeyLayout.KeyboardMode = bangla then
  begin
    if OutputIsBijoy = 'YES' then
    begin
      WindowRecord.Mode := wimBanglaANSI;
      WindowRecord.LastBanglaMode := wbmANSI;
    end
    else
    begin
      WindowRecord.Mode := wimBanglaUnicode;
      WindowRecord.LastBanglaMode := wbmUnicode;
    end;
  end
  else
  begin
    WindowRecord.Mode := wimEnglish;
    if HasRecord then
    begin
      if OutputIsBijoy = 'YES' then
        WindowRecord.LastBanglaMode := wbmANSI
      else
        WindowRecord.LastBanglaMode := wbmUnicode;
    end;
  end;

  WindowDict.AddOrSetValue(ActiveWindow, WindowRecord);
end;

procedure TAvroMainForm1.SetCurrentWindowBanglaPreference(const IsAnsi: Boolean);
var
  ActiveWindow: HWND;
  WindowRecord: TWindowRecord;
begin
  if (SwitchingMode = SWITCHING_MODE_GLOBAL) or (not Assigned(WindowDict)) or (not Assigned(KeyLayout)) then
    Exit;

  ActiveWindow := GetModeWindow;
  if ActiveWindow = 0 then
    Exit;
  if not WindowDict.TryGetValue(ActiveWindow, WindowRecord) then
  begin
    WindowRecord.Mode := wimEnglish;
    WindowRecord.LastBanglaMode := wbmUnicode;
  end;

  if IsAnsi then
    WindowRecord.LastBanglaMode := wbmANSI
  else
    WindowRecord.LastBanglaMode := wbmUnicode;

  if KeyLayout.KeyboardMode = bangla then
  begin
    if IsAnsi then
      WindowRecord.Mode := wimBanglaANSI
    else
      WindowRecord.Mode := wimBanglaUnicode;
  end
  else
    WindowRecord.Mode := wimEnglish;

  WindowDict.AddOrSetValue(ActiveWindow, WindowRecord);
end;

procedure TAvroMainForm1.SyncCurrentWindowMode;
begin
  RecordCurrentWindowMode;
end;

procedure TAvroMainForm1.ApplyWindowMode(const AWindow: HWND; const ARecord: TWindowRecord);
var
  DesiredMode: enumMode;
  DesiredOutput: string;
  OutputChanged: Boolean;
begin
  if (AWindow = 0) or not IsWindow(AWindow) or (not Assigned(KeyLayout)) then
    Exit;

  if ARecord.Mode = wimEnglish then
    DesiredMode := SysDefault
  else
    DesiredMode := bangla;

  if ARecord.Mode = wimBanglaANSI then
    DesiredOutput := 'YES'
  else if ARecord.Mode = wimBanglaUnicode then
    DesiredOutput := 'NO'
  else if ARecord.LastBanglaMode = wbmANSI then
    DesiredOutput := 'YES'
  else
    DesiredOutput := 'NO';

  OutputChanged := OutputIsBijoy <> DesiredOutput;
  FApplyingWindowMode := True;
  try
    if OutputChanged then
      OutputIsBijoy := DesiredOutput;
    if KeyLayout.KeyboardMode <> DesiredMode then
      KeyLayout.KeyboardMode := DesiredMode;
    MyCurrentKeyboardMode := DesiredMode;
  finally
    FApplyingWindowMode := False;
  end;

  if OutputChanged then
    RefreshSettings
  else
    UpdateTrayIcon;
end;

procedure TAvroMainForm1.BeginPendingANSISwitch(const EnablesBangla: Boolean);
begin
  if PendingANSISwitch then
    Exit;

  PreviousModeBeforeANSISwitch := KeyLayout.KeyboardMode;
  PreviousOutputBeforeANSISwitch := OutputIsBijoy;
  PendingANSISwitchWindow := GetModeWindow;
  PendingANSISwitchEnablesBangla := EnablesBangla;
  PendingANSISwitchHadRecord := False;
  if (SwitchingMode <> SWITCHING_MODE_GLOBAL) and Assigned(WindowDict) and IsWindow(PendingANSISwitchWindow) then
  begin
    RecordCurrentWindowMode;
    PendingANSISwitchHadRecord := WindowDict.TryGetValue(PendingANSISwitchWindow, PendingANSISwitchRecord);
  end;
  if not PendingANSISwitchHadRecord then
  begin
    PendingANSISwitchRecord.Mode := wimEnglish;
    PendingANSISwitchRecord.LastBanglaMode := wbmUnicode;
  end;
  PendingANSISwitch := True;
end;

procedure TAvroMainForm1.KeyLayout_KeyboardModeChanged(CurrentMode: enumMode);
var
  hforewnd: HWND;
begin
  { This is for Top Bar, when Keyboard Mode is changed,
    it removes transparency }
  if CurrentMode <> MyCurrentKeyboardMode then
    KeyboardModeChanged := True;

  { GLOBAL: one state for every window.  Nothing is recorded per window, and
    the mode the user just chose stays in force when the foreground window
    changes.  Every entry path lands here - the mode hotkey, both menus and the
    toggle / bn / sys WM_COPYDATA commands - so the scope is applied once. }
  if SwitchingMode = SWITCHING_MODE_GLOBAL then
  begin
    if CurrentMode = bangla then
      MyCurrentKeyboardMode := bangla
    else
      MyCurrentKeyboardMode := SysDefault;
    UpdateTrayIcon;
    Exit;
  end;
  MyCurrentKeyboardMode := CurrentMode;
  hforewnd := GetModeWindow;
  if (hforewnd <> 0) and (not FApplyingWindowMode) and
    not (PendingANSISwitch and (PendingANSISwitchWindow = hforewnd)) then
    RecordCurrentWindowMode;

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
    if (not Result) and IsEncoFile(AFilePath) and (GetAvroEncoProtectionFlag(AFilePath) = AVROENCO_FLAG_USER_PASSWORD) then
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
      if IsEncoFile(AFilePath) and (GetAvroEncoProtectionFlag(AFilePath) = AVROENCO_FLAG_USER_PASSWORD) then
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
  MappingPath:    string;
begin
  StartupLog('LoadApp: begin');
  Set_Process_Priority(HIGH_PRIORITY_CLASS);
  // The user is here: keep normal memory priority until the idle timer decides
  // otherwise (it flips to LOW only when nothing has been touched for a while).
  SetAvroMemoryPriority(ampNormal);
  LogAvroMemStats('startup: before engine load');

  // InitDict is deliberately NOT called here: the auto-correct dictionary is
  // loaded by the first phonetic keystroke that needs it (see
  // TryAutoCorrectWord). Nothing else in the process reads it, so parsing it
  // before the hook is even installed only made the idle footprint bigger.
  //
  // What IS wired here is the failure notice: the load happens inside the
  // keyboard hook, which must never show UI, so uAutoCorrect defers it to
  // this form through OnDictLoadFailed and the balloon is raised from the
  // message loop instead.
  OnDictLoadFailed :=
    procedure
    begin
      ShowAutoCorrectMissingBalloon;
    end;
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
  { Contained: a font that will not load (or a locked-down HKCU) must
    degrade to "no Siyam Rupali this session", never take startup down. }
  try
    InstallVirtualFont(ExtractFilePath(Application.ExeName) + 'Virtual Font\Siyamrupali.ttf');
    // The portable fonts\ folder (shipped set plus downloads) has no
    // registry entries - re-register it every session so fonts stay usable
    // after a reboot or a move of the portable folder.
    RegisterFontFolder(ExtractFilePath(Application.ExeName) + 'fonts\');
  except
    on E: Exception do
      StartupLogException('LoadApp/portable fonts', E);
  end;
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
  // Exact-companion first; the base-name resolver is used only for a legacy
  // value that has not migrated yet. No startup path resolves a companion by
  // base name.
  FActiveMappingLastWriteTime := 0;
  if AnsiMappingDir <> '' then
  begin
    if AnsiVersionFileName <> '' then
      MappingPath := GetExactEncoFilePath(AnsiVersionFileName, AnsiMappingDir)
    else if AnsiVersion <> '' then
      MappingPath := GetActiveEncoFilePath(AnsiVersion, AnsiMappingDir)
    else
      MappingPath := '';
    if MappingPath <> '' then
      try
        FActiveMappingLastWriteTime := TFile.GetLastWriteTime(MappingPath);
      except
        FActiveMappingLastWriteTime := 0;
      end;
  end;

  // Apply the loaded ANSI mapping
  if AnsiMappingDir = '' then
  begin
    AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
    { A read-only data folder (a portable folder extracted into Program Files,
      a network share, a CD) must not abort startup here: the mapping folder is
      simply unavailable and Unicode typing carries on. The path is kept as-is
      so it still matches the persisted setting. }
    try
      ForceDirectories(AnsiMappingDir);
    except
      on E: Exception do
        ReportStartupFailure('LoadApp/AnsiMapping folder', E);
    end;
  end;
  InitializeEncoManager;
  ScanAvroEncoFiles(AnsiMappingDir);
  // Wire up the .AvroEnco loader BEFORE the first engine switch: otherwise
  // an active .AvroEnco mapping (e.g. a password-protected one persisted
  // from the previous session) is silently skipped at startup and ANSI
  // typing stays unavailable.
  OnLoadEncoMapping := HandleLoadEncoMapping;
  // Prime the session password for a password-protected ACTIVE version from
  // the persisted per-file cache (never prompts), so SwitchEngine below can
  // parse it on demand without user interaction. The exact companion is used
  // when present; the legacy base-name resolver only covers an unmigrated
  // setting and never primes a same-base sibling of an exact selection.
  if AnsiMappingDir <> '' then
  begin
    if AnsiVersionFileName <> '' then
      MappingPath := GetExactEncoFilePath(AnsiVersionFileName, AnsiMappingDir)
    else if AnsiVersion <> '' then
      MappingPath := GetActiveEncoFilePath(AnsiVersion, AnsiMappingDir)
    else
      MappingPath := '';
    if (MappingPath <> '') and IsEncoFile(MappingPath) and (GetAvroEncoProtectionFlag(MappingPath) = AVROENCO_FLAG_USER_PASSWORD) then
      CachedEncoPassword := GetEncoCachedPassword(MappingPath);
  end;
  // Build the engine the user actually selected - and NOTHING else.
  //
  // This used to preload every engine that could unlock without a password and
  // then warm all of them, which is where the idle footprint went: a keyboard
  // utility only ever types through ONE engine, so every other mapping sat in
  // RAM as a complete parsed state until the process exited. Switching to a
  // cold mapping now costs one decrypt + parse on the click (tens of ms,
  // cached on disk afterwards), and the warm-limit/LRU release keeps that
  // bounded for the rest of the session.
  //
  // The hook stays removed while the engine globals are (re)built: a parse
  // resets and rebuilds them, and typing must never read a half-built engine.
  WindowCheck.Enabled := False; // never re-install the hook mid-parse
  RemoveHook;
  { The hook must come back on whatever happens (the finally below), but a broken
    mapping file should not take the rest of startup - tray icon, word database,
    missing-database notice - with it. Delphi has no try/except/finally in one
    statement, so the except is nested inside the finally. }
  try
    try
      // Resolve and activate exactly what the settings name. The catalog was
      // already scanned above, so the "completely empty" baseline decision is
      // made against the real folder - locked or corrupt files still count.
      ApplyPersistedAnsiSelection('Startup');
      SyncActiveMappingTimestamp(AnsiVersionFileName);
      // Rotated-container auto-heal, started only now that the engine
      // decision above is settled. It is asynchronous and, when every
      // container still opens, it costs one directory scan and makes no
      // network request at all.
      AvroMigrationCheckAsync;
      if (AnsiVersion = '') and (not FNoMappingBalloonShown) and Assigned(Tray) and Tray.Visible then
      begin
        FNoMappingBalloonShown := True;
        Tray.BalloonTitle := 'Avro Keyboard';
        // Actionable balloon: clicking it opens the resource downloader, which
        // is how a user gets the default mappings back after accidentally
        // deleting them from the mapping folder.
        Tray.BalloonHint := 'No ANSI mapping files found. Click here to download default mappings.' + sLineBreak +
          'Unicode output stays active until a mapping is added.';
        Tray.OnBalloonClick := NoMappingBalloonClick;
        Tray.BalloonTimeout := 10000;
        Tray.ShowBalloonHint;
      end;
    except
      on E: Exception do
        ReportStartupFailure('LoadApp/ANSI mapping', E);
    end;
  finally
    Sethook;
    WindowCheck.Enabled := True;
  end;
  // The switch above parsed exactly one engine; the sweep that used to cache
  // every layout's icon here is gone with it (see uAvroEncoManager).
  LogAvroMemStats('startup: engines ready');
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

  // Same for the layouts folder: nothing watches it, so the throttled poll
  // below is what keeps both menus in step with the files on disk.
  FLayoutCheckCountdown := 5;
  FLayoutSnapshot := BuildLayoutFolderList;

  // Last of the startup notices, once the tray/top bar exist to carry it: the
  // phonetic candidates read Database.db3, and a load that failed because the
  // file is gone reports nothing on its own (uDBase stays silent - see
  // LoadWordDatabase). Raise it here so the user is told what broke and where
  // to get the file back.
  try
    CheckWordDatabasePresence;
  except
    on E: Exception do
      StartupLogException('LoadApp/CheckWordDatabasePresence', E);
  end;
  StartupLog('LoadApp: complete');
end;

{ Resolves and activates the persisted ANSI selection.

  Shared by LoadApp and RefreshSettings so both obey exactly one rule set:
  - a completely empty catalog is the ONLY case that may activate the embedded
    baseline; a locked/corrupt file still counts as a catalog entry;
  - an empty AnsiVersion (or the old unknown "Default" without a companion)
    selects FirstAvailableMappingFileName;
  - a companion that matches the base name is the exact selection, and a
    missing exact file never falls back to a same-base sibling or another row;
  - a legacy base-name value resolves once, is published and persisted before
    activation, and is exact from then on. }
function TAvroMainForm1.ApplyPersistedAnsiSelection(const AContext: string): Boolean;
var
  DesiredFile, DesiredBase, LoadedBase, LoadedFile: string;
  MissingExact, SelectionChanged: Boolean;
begin
  Result := False;
  LoadedBase := AnsiVersion;
  LoadedFile := AnsiVersionFileName;
  MissingExact := False;
  DesiredFile := '';

  if (not Assigned(AvroEncoFiles)) or (AvroEncoFiles.Count = 0) then
  begin
    // LAST RESORT, and only after the mapping folder came up empty: the
    // compiled-in ANSI baseline that ships inside Avro Keyboard.exe. It is a
    // versioned fallback, not a pin: the moment a mapping file appears on disk
    // this branch is no longer reached.
    if Application.Terminated then
      Exit;
    if AnsiEngineManager.ActivateEmbeddedBaseline then
    begin
      Result := True;
      if ((not SameText(AnsiVersion, LoadedBase)) or (not SameText(AnsiVersionFileName, LoadedFile))) and Assigned(KeyLayout) then
        KeyLayout.ResetAnsiTypingState;
      Log(AContext + ': activated the embedded ANSI baseline (mapping folder is empty)');
      if (not SameText(AnsiVersion, LoadedBase)) or (not SameText(AnsiVersionFileName, LoadedFile)) then
        SaveAnsiVersionOnly;
    end
    else
      Log(AContext + ': no ANSI mapping files - Unicode only');
    Exit;
  end;

  if AnsiVersion = '' then
    DesiredFile := FirstAvailableMappingFileName
  else if SameText(AnsiVersion, 'Default') and (AnsiVersionFileName = '') then
    // The old unknown value. A real Default.json is selectable by its exact
    // companion, which is why only the companion-less form is treated this way.
    DesiredFile := FirstAvailableMappingFileName
  else
  begin
    DesiredFile := ResolveAnsiSelectionFile(AnsiVersion, AnsiVersionFileName, AnsiMappingDir, MissingExact);
    if MissingExact then
    begin
      // Do not choose another file and do not activate the baseline - the
      // non-empty catalog blocks it. The persisted values stay untouched.
      Log(AContext + ': selected ANSI mapping file not found: ' + AnsiVersionFileName);
      Exit;
    end;
  end;

  if DesiredFile = '' then
  begin
    Log(AContext + ': stored ANSI selection does not resolve to an exact file - Unicode only');
    Exit;
  end;

  SelectionChanged := not SameText(ExtractFileName(DesiredFile), LoadedFile);

  // Publish/persist the exact pair BEFORE activation, so a legacy migration
  // survives a crash during the switch. This also covers the first migration
  // of an empty or old "Default" setting.
  DesiredBase := ChangeFileExt(ExtractFileName(DesiredFile), '');
  if (not SameText(AnsiVersion, DesiredBase)) or (not SameText(AnsiVersionFileName, ExtractFileName(DesiredFile))) then
  begin
    PublishActiveSelection(ExtractFileName(DesiredFile), DesiredBase);
    SaveAnsiVersionOnly;
  end;

  if Application.Terminated then
    Exit;

  // Two attempts cover the first-run race (cache directory missing, container
  // just installed and still being written). A failure leaves Unicode output
  // (or the engine that was already live) - never a different file.
  if not (AnsiEngineManager.SwitchEngine(DesiredFile) or AnsiEngineManager.SwitchEngine(DesiredFile)) then
  begin
    Log(AContext + ': could not activate "' + DesiredFile + '"');
    Exit;
  end;

  Result := True;
  if SelectionChanged and Assigned(KeyLayout) then
    KeyLayout.ResetAnsiTypingState;
  if (not SameText(AnsiVersion, LoadedBase)) or (not SameText(AnsiVersionFileName, LoadedFile)) then
    SaveAnsiVersionOnly;
end;

procedure TAvroMainForm1.HandleLayoutDirectoryChanged(Sender: TObject);
var
  TargetPath, ActiveFile: string;
  MissingExact: Boolean;
  Snap:         string;
begin
  // The watcher only ever fires from CheckForChanges on the UI timer, but it
  // fires for whatever happens to the folder: a locked file, a vanished
  // directory, an engine that refuses to re-parse.  Nothing here may take the
  // app down, so the body is contained and reported instead of escaping into
  // the timer's caller.
  try
    FAnsiRootIconName := '';
    ScanAvroEncoFiles(AnsiMappingDir);

    ActiveFile := AnsiVersionFileName;
    TargetPath := '';
    if AnsiMappingDir <> '' then
    begin
      if ActiveFile = '' then
      begin
        // One-time legacy migration: an old setting has only a base name. The
        // resolved exact file is published and persisted BEFORE it is used.
        if AnsiVersion <> '' then
        begin
          MissingExact := False;
          TargetPath := ResolveAnsiSelectionFile(AnsiVersion, AnsiVersionFileName, AnsiMappingDir, MissingExact);
          if MissingExact then
            Log('ANSI mapping file not found: ' + AnsiVersionFileName)
          else if TargetPath <> '' then
          begin
            ActiveFile := ExtractFileName(TargetPath);
            PublishActiveSelection(ActiveFile, ChangeFileExt(ActiveFile, ''));
            SaveAnsiVersionOnly;
          end;
        end;
      end
      else
      begin
        // Exact selection: only that file. A disappeared file must not fall
        // back to the same-base sibling; the running engine stays untouched.
        TargetPath := GetExactEncoFilePath(ActiveFile, AnsiMappingDir);
        if TargetPath = '' then
          Log('ANSI mapping file not found: ' + ActiveFile);
      end;

      if (ActiveFile <> '') and (TargetPath <> '') then
      begin
        // Default-key files (flag $00) reload transparently; password
        // protected files reload only when a usable password is cached. The
        // engine cache re-parses the changed file in place, so the active
        // engine stays fresh AND later switches keep using the cached copy.
        if IsEncoFile(TargetPath) then
        begin
          if (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_DEFAULT_KEY) or (GetEncoCachedPassword(TargetPath) <> '') then
            AnsiEngineManager.InvalidateEngine(ActiveFile);
        end
        else
          AnsiEngineManager.InvalidateEngine(ActiveFile);
      end;
    end;

    // New/changed/removed engines are reconciled with the cache as well.
    AnsiEngineManager.RefreshFromDisk;

    { Only the rebuild waits for a tracked menu: the scan, the active-engine
      invalidation and RefreshFromDisk above are menu-independent and have
      already run.  The popup menus hold the dynamic version items built by
      BuildAnsiVersionMenus, and clearing or rebuilding those under a tracked
      menu destroys the HMENU Windows is still displaying.  The snapshot stays
      unadvanced, so the 1.5 s poll re-detects the change and rebuilds once the
      menu is closed. }
    if FTrackedMenusOpen > 0 then
      Exit;

    // Rebuild ONLY when the folder's file list really changed.  The scan ran
    // above, so the snapshot is refreshed BEFORE the rebuild - BuildAnsiVersionMenus
    // skips its own re-scan when nothing changed since this snapshot.  An event
    // for a file that was merely touched used to rebuild both encoding menus and
    // toast "ANSI mappings refreshed" anyway.
    Snap := BuildAnsiMappingFolderList;
    if Snap <> FAnsiMappingSnapshot then
    begin
      FAnsiMappingSnapshot := Snap;
      BuildAnsiVersionMenus;
      ShowAnsiToastNotification('ANSI mappings refreshed');
    end;
  except
    on E: Exception do
      Log('Layout directory handler failed: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

{ refresh_enco: a second process (a double-clicked .AvroEnco import) just
  imported - and possibly activated - a mapping. The directory watcher already
  sees the file on disk; what it cannot see is the AnsiVersion value the other
  process persisted. Re-read that value here and run the normal switch path
  when it moved, then reconcile menus and the engine cache exactly like a
  local folder change. }
procedure TAvroMainForm1.HandleRemoteEncoRefresh;
var
  PersistedBase, PersistedFile, TargetPath: string;
  MissingExact: Boolean;
  ErrorLog:     TStringList;

  procedure NotifySwitched;
  begin
    SyncActiveMappingTimestamp(AnsiVersionFileName);
    UpdateAnsiVersionMenuChecks(AnsiVersionFileName);
    ReplaceAnsiMenuParentIcon;
    UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Encoding: ' + GetMappingDisplayLabel(AnsiVersionFileName));
  end;

begin
  try
    // Pick the freshly imported file into the shared list before anything
    // resolves paths against it.
    ScanAvroEncoFiles(AnsiMappingDir);

    if not ReadActiveAnsiSelection(PersistedBase, PersistedFile) then
      Exit;

    // Compare BOTH values: a same-base switch (one.AvroEnco -> one.json) must
    // be detected even though AnsiVersion itself did not move.
    if SameText(PersistedBase, AnsiVersion) and SameText(PersistedFile, AnsiVersionFileName) then
    begin
      HandleLayoutDirectoryChanged(nil);
      Exit;
    end;

    if PersistedBase = '' then
    begin
      // The other process cleared the selection. Do not guess another file.
      HandleLayoutDirectoryChanged(nil);
      Exit;
    end;

    MissingExact := False;
    TargetPath := ResolveAnsiSelectionFile(PersistedBase, PersistedFile, AnsiMappingDir, MissingExact);
    if MissingExact then
    begin
      Log('refresh_enco: selected ANSI mapping file not found: ' + PersistedFile);
      HandleLayoutDirectoryChanged(nil);
      Exit;
    end;
    if TargetPath = '' then
    begin
      HandleLayoutDirectoryChanged(nil);
      Exit;
    end;

    PersistedFile := ExtractFileName(TargetPath);
    // Legacy value (no/mismatched companion): publish and persist the exact
    // pair before activation, exactly like startup.
    if (not SameText(PersistedFile, AnsiVersionFileName)) or (not SameText(PersistedBase, AnsiVersion)) then
    begin
      PublishActiveSelection(PersistedFile, ChangeFileExt(PersistedFile, ''));
      SaveAnsiVersionOnly;
    end;

    // Same two-step switch as the encoding menu click: instant path first,
    // blocking on-demand repair parse as the fallback.
    if AnsiEngineManager.TrySwitchCached(PersistedFile) then
      NotifySwitched
    else
    begin
      Screen.Cursor := crHourGlass;
      ErrorLog := TStringList.Create;
      try
        if AnsiEngineManager.SwitchEngine(PersistedFile, ErrorLog) then
          NotifySwitched
        else
          ShowAnsiToastNotification('Mapping file not found: ' + PersistedFile);
      finally
        ErrorLog.Free;
        Screen.Cursor := crDefault;
      end;
    end;

    // Reconcile menus, engine cache and snapshot like any other folder change.
    HandleLayoutDirectoryChanged(nil);
  except
    on E: Exception do
      Log('refresh_enco handler failed: ' + E.ClassName + ' - ' + E.Message);
  end;
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
  SR:       TSearchRec;

  procedure AddFound;
  begin
    NameList.Add(Lowercase(SR.Name) + '|' + IntToStr(SR.Size) + '|' + FormatDateTime('yyyy-mm-dd hh:nn:ss', SR.TimeStamp));
  end;

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
          if (SR.Name <> '.') and (SR.Name <> '..') and IsAnsiMappingFileName(SR.Name) then
            AddFound;
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
    end;

    if FindFirst(AnsiMappingDir + '*.json', faAnyFile, SR) = 0 then
    begin
      try
        repeat
          if (SR.Name <> '.') and (SR.Name <> '..') and IsAnsiMappingFileName(SR.Name) then
            AddFound;
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
var
  I: Integer;
begin
  if AnsiMappingNames = nil then
    AnsiMappingNames := TStringList.Create;
  if AnsiMappingFileNames = nil then
    AnsiMappingFileNames := TStringList.Create;

  // AvroEncoFiles is kept fresh by the watcher / periodic poll / import /
  // delete flows, so this is pure memory work - no disk scan. The exact list
  // carries identity; the label list is filled in the same index order so the
  // menus and the picker can never pair a caption with the wrong file.
  GetSortedMappingFileNames(AnsiMappingFileNames);
  AnsiMappingNames.Clear;
  for I := 0 to AnsiMappingFileNames.Count - 1 do
    AnsiMappingNames.Add(GetMappingDisplayLabel(AnsiMappingFileNames[I]));
end;

{ Poll half of the mapping watcher/poll pair (the watcher handler is
  HandleLayoutDirectoryChanged): both feed FAnsiMappingSnapshot, so a change the
  watcher missed - or one deferred below - is still picked up here.

  Contained, because its caller is the 100 ms UI timer: an exception escaping
  here would be swallowed by Application.OnException (one balloon per session)
  and the rest of that tick - the watcher check, the window tracking, the hook
  re-arm - would never run. }
procedure TAvroMainForm1.RefreshAnsiMappingList;
var
  Snap: string;
begin
  if (AnsiMappingDir = '') or (not DirectoryExists(AnsiMappingDir)) then
    Exit;

  { Deferred while a menu carrying these items is tracked (Popup_Tools'
    "Select ANSI Encoding" submenu or the tray's): rebuilding them would destroy
    and rebuild the HMENU Windows is still displaying.  The snapshot is
    deliberately NOT advanced, so the change lands on the first tick after the
    menu closes - the same contract RefreshLayoutList keeps. }
  if FTrackedMenusOpen > 0 then
    Exit;

  try
    Snap := BuildAnsiMappingFolderList;
    if Snap = FAnsiMappingSnapshot then
      Exit; // nothing new added / removed since the last refresh

    FAnsiMappingSnapshot := Snap;
    FAnsiRootIconName := '';
    ScanAvroEncoFiles(AnsiMappingDir);
    BuildAnsiVersionMenus;
    Log('ANSI mapping folder changed - encoding list refreshed');
  except
    on E: Exception do
      Log('RefreshAnsiMappingList failed: ' + E.ClassName + ' - ' + E.Message);
  end;
end;

{ =============================================================================== }
{ Keyboard layouts folder: snapshot + fallback poll, mirroring the mapping one. }
{ This folder has NO directory watcher (FDirectoryWatcher watches AnsiMappingDir }
{ only), so the poll below is the only thing that notices a .avrolayout copied }
{ in or deleted while Avro Keyboard is running. }
{ =============================================================================== }

function TAvroMainForm1.BuildLayoutFolderList: string;
var
  NameList: TStringList;
  SR:       TSearchRec;
  Dir:      string;
begin
  Result := '';
  Dir := GetAvroDataDir + 'Keyboard Layouts\';
  if not DirectoryExists(Dir) then
    Exit;

  NameList := TStringList.Create;
  try
    if FindFirst(Dir + '*.avrolayout', faAnyFile, SR) = 0 then
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

{ Rebuilds the dynamic layout items only when the folder's file list actually
  differs from the snapshot - the same contract RefreshAnsiMappingList keeps.

  Contained, because the caller is the 100 ms UI timer: an exception escaping
  here would be swallowed by Application.OnException (one balloon per session)
  and the rest of that tick - the directory-watcher check, the window tracking,
  the hook re-arm - would never run. }
procedure TAvroMainForm1.RefreshLayoutList;
var
  Snap: string;
begin
  { Rebuilding while a menu carrying these items is tracked would destroy and
    rebuild the HMENU Windows is still displaying (TMenuItem.Free ->
    RebuildHandle), which is how a folder change landing on an open menu became
    a crash.  The snapshot is deliberately NOT advanced here: the change is
    picked up by the first tick after the menu closes, not dropped. }
  if FTrackedMenusOpen > 0 then
    Exit;

  try
    Snap := BuildLayoutFolderList;
    if Snap = FLayoutSnapshot then
      Exit; // nothing added / removed since the last refresh

    LoadKeyboardLayoutNames;
    RefreshLayoutMenuItems;
    { Last, so a failure above leaves the snapshot unadvanced and the next tick
      retries instead of swallowing the change for the whole session. }
    FLayoutSnapshot := Snap;
    Log('Keyboard layouts folder changed - layout menu refreshed');
  except
    on E: Exception do
      Log('RefreshLayoutList failed: ' + E.ClassName + ' - ' + E.Message);
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

procedure TAvroMainForm1.ogglekeyboardmode2Click(Sender: TObject);
begin
  KeyLayout.ToggleMode;
end;

{ =============================================================================== }

{ =============================================================================== }

function TAvroMainForm1.ResolveHelpPdf(const AFileName: string): string;
begin
  Result := '';
  if FileExists(ExtractFilePath(Application.ExeName) + AFileName) then
    Result := ExtractFilePath(Application.ExeName) + AFileName
  else if FileExists(GetAvroDataDir + 'Docs\' + AFileName) then
    Result := GetAvroDataDir + 'Docs\' + AFileName;
end;

procedure TAvroMainForm1.CollectHelpPdfs(AList: TStringList);
var
  I, J: Integer;
  Cur:  string;

  function AlreadyListed(const AName: string): Boolean;
  var
    K: Integer;
  begin
    Result := True;
    for K := 0 to AList.Count - 1 do
      if SameText(ExtractFileName(AList[K]), AName) then
        Exit;
    Result := False;
  end;

  procedure ScanDir(const ADir: string);
  var
    SR: TSearchRec;
  begin
    if not DirectoryExists(ADir) then
      Exit;
    if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*.pdf', faAnyFile, SR) = 0 then
      try
        repeat
          if ((SR.Attr and faDirectory) = 0) and (not AlreadyListed(SR.Name)) then
            AList.Add(IncludeTrailingPathDelimiter(ADir) + SR.Name);
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
  end;

begin
  AList.Clear;
  ScanDir(ExtractFilePath(Application.ExeName));
  ScanDir(GetAvroDataDir + 'Docs\');
  for I := 1 to AList.Count - 1 do
  begin
    Cur := AList[I];
    J := I;
    while (J > 0) and (CompareText(ExtractFileName(AList[J - 1]), ExtractFileName(Cur)) > 0) do
    begin
      AList[J] := AList[J - 1];
      Dec(J);
    end;
    AList[J] := Cur;
  end;
end;

procedure TAvroMainForm1.RebuildDynamicHelp(AParent: TMenuItem; AInsertIndex: Integer);
const
  DynTag = 9911;
var
  I:    Integer;
  Pdfs: TStringList;
  M:    TMenuItem;
begin
  for I := AParent.Count - 1 downto 0 do
    if AParent[I].Tag = DynTag then
      AParent[I].Free;

  Pdfs := TStringList.Create;
  try
    CollectHelpPdfs(Pdfs);
    if Pdfs.Count = 0 then
    begin
      M := TMenuItem.Create(Self);
      M.Caption := 'No help files found';
      M.Enabled := False;
      M.Tag := DynTag;
      AParent.Insert(AInsertIndex, M);
    end
    else
      for I := 0 to Pdfs.Count - 1 do
      begin
        M := TMenuItem.Create(Self);
        M.Caption := ChangeFileExt(ExtractFileName(Pdfs[I]), '');
        M.Hint := Pdfs[I];
        M.ImageIndex := 7;
        M.Tag := DynTag;
        M.OnClick := DynamicHelpClick;
        AParent.Insert(AInsertIndex + I, M);
      end;
  finally
    Pdfs.Free;
  end;
end;

procedure TAvroMainForm1.DynamicHelpPopup(Sender: TObject);
begin
  if Sender = Popup_Help then
    RebuildDynamicHelp(Popup_Help.Items, 0)
  else if Sender = Popup_Tray then
    RebuildDynamicHelp(Helpfiles2, 0);
end;

procedure TAvroMainForm1.DynamicHelpClick(Sender: TObject);
begin
  if (Sender is TMenuItem) and FileExists(TMenuItem(Sender).Hint) then
    Execute_Something(TMenuItem(Sender).Hint);
end;

procedure TAvroMainForm1.OpenHelpFile(const HelpID: Integer);
var
  Request: string;
  Pdf:     string;
begin
  case HelpID of
    23:
      Request := 'Before You Start.pdf';
    24:
      Request := 'Overview.pdf';
    25:
      Request := 'Customizing Avro Keyboard.pdf';
    26:
      Request := 'Bangla Typing with Avro Phonetic.pdf';
    27:
      Request := 'Bangla Typing with Fixed Keyboard Layouts.pdf';
    28:
      Request := 'Bangla Typing with Avro Mouse.pdf';
    29:
      Request := 'faq.pdf';
    35:
      Request := 'Editing Keyboard Layout.pdf';
    else
      Exit;
  end;
  Pdf := ResolveHelpPdf(Request);
  if Pdf <> '' then
    Execute_Something(Pdf)
  else
    Execute_Something('https://www.omicronlab.com/go.php?id=' + IntToStr(HelpID));
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
    if PendingANSISwitch then
      Exit;
    BeginPendingANSISwitch(False);
    CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
    frmEncodingWarning.ShowModal;
  end
  else
  begin
    OutputIsBijoy := 'YES';
    SetCurrentWindowBanglaPreference(True);
    RefreshSettings;
  end;

end;

procedure TAvroMainForm1.OutputasUnicodeRecommended1Click(Sender: TObject);
begin
  OutputIsBijoy := 'NO';
  SetCurrentWindowBanglaPreference(False);
  OptimizeMemoryUsage;
  RefreshSettings;
end;

{ =============================================================================== }

{ =============================================================================== }

procedure TAvroMainForm1.RefreshSettings;
begin
  { Entered from the WH_KEYBOARD_LL callback: the mode/output hotkeys in
    KeyboardHook call us directly from the hook body, which must return within
    LowLevelHooksTimeout (5000 ms - a limit Avro itself sets) or Windows removes
    the hook silently. Everything below is too heavy for that, and
    LoadWordDatabase can even raise a MODAL dialog for a corrupt Database.db3,
    which would block the hook until the user clicks OK.

    The setting itself has already been applied by the caller, so typing stays
    correct; only the re-application (menus, theme, engine, tray, database) is
    posted back to the main loop. }
  if InHookContext then
  begin
    PostMessage(Handle, WM_APP + 11, 0, 0);
    Exit;
  end;

  { The scope of mode switching.  Leaving per-window records behind while
    GLOBAL is in force would resurrect them the moment the user switched back,
    so they are dropped as soon as the scope is global (the Options dialog
    reads the setting directly when it loads). }
  if Assigned(WindowDict) and (SwitchingMode = SWITCHING_MODE_GLOBAL) then
    WindowDict.Clear;

  // Mirror the Global Hotkeys settings onto every menu item that performs the
  // same action.  HotkeyStringToShortCut (not Vcl.Menus.TextToShortCut) reads
  // the stored uppercase / " + " spacing format, so modifier combos show up
  // too; an empty or "None" setting clears the display (ShortCut = 0).
  // ShowShortcutKeysOnMenu = 'NO' clears the display on both tray and topbar
  // menus - the real hotkeys keep working, they are handled by KeyboardHook
  // and never read these menu items.
  if ShowShortcutKeysOnMenu = 'NO' then
  begin
    Spellcheck2.ShortCut := 0;
    Spellcheck4.ShortCut := 0;

    UnicodetoBijoytextconverter1.ShortCut := 0;
    Spellcheck3.ShortCut := 0;

    ogglekeyboardmode1.ShortCut := 0;
    ogglekeyboardmode2.ShortCut := 0;

    mnuTraySelectAnsiEncoding.ShortCut := 0;
    if AnsiVersionSubmenu1 <> nil then
      AnsiVersionSubmenu1.ShortCut := 0;
  end
  else
  begin
    Spellcheck2.ShortCut := HotkeyStringToShortCut(SpellerLauncherKey);
    Spellcheck4.ShortCut := HotkeyStringToShortCut(SpellerLauncherKey);

    UnicodetoBijoytextconverter1.ShortCut := HotkeyStringToShortCut(ConverterLauncherKey);
    Spellcheck3.ShortCut := HotkeyStringToShortCut(ConverterLauncherKey);

    ogglekeyboardmode1.ShortCut := HotkeyStringToShortCut(ModeSwitchKey);
    ogglekeyboardmode2.ShortCut := HotkeyStringToShortCut(ModeSwitchKey);

    mnuTraySelectAnsiEncoding.ShortCut := HotkeyStringToShortCut(AnsiVersionSwitchKey);
    if AnsiVersionSubmenu1 <> nil then
      AnsiVersionSubmenu1.ShortCut := HotkeyStringToShortCut(AnsiVersionSwitchKey);
  end;

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

  // ANSI Encoding version. Apply exactly the startup rules: an empty catalog
  // is the only baseline case, an exact companion is authoritative, and a
  // legacy base name migrates once. The scan makes the empty-catalog decision
  // authoritative even when this runs after files were added outside the
  // watcher's view.
  AnsiMappingDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(AnsiMappingDir);
  ScanAvroEncoFiles(AnsiMappingDir);
  ApplyPersistedAnsiSelection('RefreshSettings');
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
  // LIGHT / DARK force the built-in themes, and any other value names an
  // embedded VCL style (what the Customize dialog's Theme list offers).
  // ApplyAppThemeSetting also switches the VCL style (which is what makes the
  // top bar popup menus and every dialog match) and caches the resolved theme
  // for the hand-painted flyouts. Re-applying an unchanged theme is a no-op,
  // because this runs after every settings change in the app.
  ApplyAppThemeSetting(AppThemeMode);

  // Every caller of this method is a style-switch point: WM_SETTINGCHANGE
  // ('ImmersiveColorSet'), RefreshSettings (the Customize dialog's OK and
  // Apply), and startup. Nothing is refreshed from here on purpose: the style
  // engine announces the switch to every open form (CM_STYLECHANGED), and the
  // dialog uses that message to re-resolve the surface colour its opaque labels
  // were created with and to repaint itself in one pass. Doing it here instead
  // would paint the dialog while the new style is still being loaded, which
  // leaves the controls whose colour is resolved when their window is recreated
  // (the category tree) on the previous style for the rest of the switch.
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

procedure TAvroMainForm1.LocateKeyboardLayoutClick(Sender: TObject);
var
  LayoutDir: string;
begin
  LayoutDir := GetAvroDataDir + 'Keyboard Layouts\';
  ShellExecute(0, 'open', PChar(LayoutDir), nil, nil, SW_SHOWNORMAL);
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
      M.Checked := SameText(M.Hint, AnsiVersionFileName);
  end;
end;

procedure TAvroMainForm1.PopupToolsPopup(Sender: TObject);
begin
  // Open half of that guard too: this menu holds AnsiVersionSubmenu1, which
  // BuildAnsiVersionMenus rebuilds from the timer and the folder watcher, so
  // those rebuilds have to wait while it is up (PopupToolsPopup IS
  // Popup_Tools.OnPopup - RefreshSettings re-wires it).
  TrackedMenusPopup(Sender);

  // Resolve only the active mapping's icon: it is shown on this menu's parent
  // item. Unselected mapping rows remain icon-free.
  EnsureMappingIcon(AnsiVersionFileName);
  // Only update checkmarks on existing items -- do NOT Clear/rebuild during popup
  SyncAnsiVersionChecks(AnsiVersionSubmenu1);
  // Refresh this menu's own "Select ANSI Encoding" parent item too.
  ReplaceAnsiMenuParentIcon;
end;

{ The open/close halves of the tracked-menu guard: RefreshLayoutList and the
  ANSI mapping rebuilds skip while FTrackedMenusOpen > 0, because freeing or
  clearing a TMenuItem calls RebuildHandle (Vcl.Menus) and destroys/rebuilds the
  HMENU Windows is still displaying.  See the wiring note in FormCreate for why
  the pair is balanced. }

procedure TAvroMainForm1.TrackedMenusPopup(Sender: TObject);
begin
  Inc(FTrackedMenusOpen);
end;

procedure TAvroMainForm1.TrackedMenusClose(Sender: TObject);
begin
  if FTrackedMenusOpen > 0 then
    Dec(FTrackedMenusOpen);
end;

procedure TAvroMainForm1.PopupTrayPopup(Sender: TObject);
begin
  // Open half of that guard: PopupTrayPopup IS Popup_Tray.OnPopup (RefreshSettings
  // re-wires it), so the count belongs here rather than in a second assignment.
  TrackedMenusPopup(Sender);

  // Resolve the active mapping icon for the tray menu's parent item.
  EnsureMappingIcon(AnsiVersionFileName);
  SyncAnsiVersionChecks(mnuTraySelectAnsiEncoding);
  ReplaceAnsiMenuParentIcon;
end;

{ =============================================================================== }
{ Per-layout icons (system tray + encoding menus) }
{ =============================================================================== }

{ A cached HICON for the tray at the CURRENT small-icon metric, or 0 when this
  layout has no icon.

  The metric is part of the cache key because it follows the display DPI: 16 px
  at 100%, 20 at 125%, 24 at 150%, 32 at 200%. Asking the icon library for
  exactly that size means Windows is never handed a mismatched handle to
  rescale, which is what made the tray icon look soft on a scaled display. }
function TAvroMainForm1.GetAnsiTrayIcon(const AName: string): HICON;
var
  IconBytes: TBytes;
  Cx, Cy:    Integer;
  Key:       string;
begin
  Result := 0;
  if AName = '' then
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

{ Frees every cached tray handle. Called when the mapping folders are re-scanned
  and on the way out. }
procedure TAvroMainForm1.ReleaseAnsiIconCache;
var
  H: HICON;
begin
  FAnsiRootIconName := '';

  // Remove per-submenu image-list references; the owning PopupMenu.ImageList1
  // remains responsible for the parent icons and the menus' standard artwork.
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

{ Resolve the active mapping's menu-sized icon into one reusable ImageList slot.
  The built-in ANSI image is the fallback when the mapping has no usable icon. }
function TAvroMainForm1.AnsiRootIconSlot(const AName: string): Integer;
var
  IconBytes: TBytes;
  H:         HICON;
  Ico:       TIcon;
begin
  Result := -1;
  if (AName = '') or not Assigned(ImageList1) or (ImageList1.Width <= 0) or (ImageList1.Height <= 0) then
    Exit;

  if SameText(AName, FAnsiRootIconName) and (FAnsiRootIconIndex >= 0) and (FAnsiRootIconIndex < ImageList1.Count) then
  begin
    Result := FAnsiRootIconIndex;
    Exit;
  end;

  IconBytes := GetMappingIconBytes(AName);
  if Length(IconBytes) = 0 then
    Exit;

  H := CreateHIconAtSize(IconBytes, ImageList1.Width, ImageList1.Height);
  if H = 0 then
  begin
    Log('AnsiRootIconSlot: could not decode a ' + IntToStr(ImageList1.Width) + 'x' + IntToStr(ImageList1.Height) +
      ' frame for the layout icon of "' + AName + '"');
    Exit;
  end;

  Ico := TIcon.Create;
  try
    Ico.Handle := H;
    H := 0;
    if (FAnsiRootIconIndex >= 0) and (FAnsiRootIconIndex < ImageList1.Count) then
      ImageList1.ReplaceIcon(FAnsiRootIconIndex, Ico)
    else
      FAnsiRootIconIndex := ImageList1.AddIcon(Ico);
  finally
    Ico.Free;
    if H <> 0 then
      DestroyIcon(H);
  end;

  if (FAnsiRootIconIndex >= 0) and (FAnsiRootIconIndex < ImageList1.Count) then
  begin
    FAnsiRootIconName := AName;
    Result := FAnsiRootIconIndex;
  end
  else
    Log('AnsiRootIconSlot: ImageList1 refused the ' + IntToStr(ImageList1.Width) + 'x' + IntToStr(ImageList1.Height) +
      ' icon of "' + AName + '"');
end;

procedure TAvroMainForm1.ReplaceAnsiMenuParentIcon;
const
  ANSI_ROOT_IMAGE_INDEX = 30;
var
  Slot: Integer;
begin
  if not Assigned(ImageList1) then
    Exit;

  EnsureMappingIcon(AnsiVersionFileName);
  Slot := AnsiRootIconSlot(AnsiVersionFileName);
  if Slot < 0 then
    Slot := ANSI_ROOT_IMAGE_INDEX;

  if Assigned(mnuTraySelectAnsiEncoding) then
    mnuTraySelectAnsiEncoding.ImageIndex := Slot;
  if Assigned(AnsiVersionSubmenu1) then
    AnsiVersionSubmenu1.ImageIndex := Slot;
end;

const
  { The GroupIndex every ANSI version row of both menus carries. }
  ANSI_VERSION_ROW_GROUP = 10;

procedure TAvroMainForm1.UpdateTrayIcon;
var
  ICN:                 TIcon;
  AnsiHIcon, IconCopy: HICON;
  IconBytes:           TBytes;
begin
  // Both parent "Select ANSI Encoding" items are refreshed above the tray /
  // TopBar split, so they stay in sync in either UI mode.
  ReplaceAnsiMenuParentIcon;

  ICN := TIcon.Create;
  try
    if KeyLayout.KeyboardMode = bangla then
    begin
      if OutputIsBijoy = 'YES' then
      begin
        AnsiHIcon := GetAnsiTrayIcon(AnsiVersionFileName);
        IconCopy := 0;
        if AnsiHIcon <> 0 then
          IconCopy := CopyIcon(AnsiHIcon);
        if IconCopy = 0 then
        begin
          IconBytes := GetMappingIconBytes(AnsiVersionFileName);
          if (Length(IconBytes) > 0) and Assigned(ImageList1) and (ImageList1.Width > 0) and (ImageList1.Height > 0) then
            IconCopy := CreateHIconAtSize(IconBytes, ImageList1.Width, ImageList1.Height);
        end;

        if IconCopy <> 0 then
          ICN.Handle := IconCopy
        else
          ImageList1.GetIcon(30, ICN); // built-in ANSI icon
      end
      else if IsWin2000 = True then
        ImageList1.GetIcon(14, ICN)
      else
        ImageList1.GetIcon(20, ICN);

      if OutputIsBijoy = 'YES' then
        Tray.Hint := 'Avro Keyboard.' + #13 + 'Running Bangla Keyboard Mode (ANSI Version).' + #13 + 'Press ' + ModeSwitchKey +
          ' to switch to System default.'
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

  if IsFormVisible('TopBar') then
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
  if (KeyLayout.KeyboardMode = bangla) and (OutputIsBijoy = 'NO') then
    KeyLayout.KeyboardMode := SysDefault
  else
  begin
    if KeyLayout.KeyboardMode <> bangla then
      KeyLayout.KeyboardMode := bangla;
    if OutputIsBijoy = 'YES' then
    begin
      OutputIsBijoy := 'NO';
      SetCurrentWindowBanglaPreference(False);
      OptimizeMemoryUsage;
      RefreshSettings;
      Exit;
    end;
    SetCurrentWindowBanglaPreference(False);
  end;
end;

procedure TAvroMainForm1.SetBengaliANSIMode;
begin
  if PendingANSISwitch then
    Exit;

  if (KeyLayout.KeyboardMode = bangla) and (OutputIsBijoy = 'YES') then
  begin
    { Already in Bangla+ANSI: toggle off to English. No warning needed. }
    KeyLayout.KeyboardMode := SysDefault;
  end
  else
  begin
    if ShowOutputwarning <> 'NO' then
    begin
      { Keep the warning modal until the user chooses or cancels it. }
      BeginPendingANSISwitch(True);
      if KeyLayout.KeyboardMode <> bangla then
        KeyLayout.KeyboardMode := bangla;
      CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
      frmEncodingWarning.ShowModal;
    end
    else
    begin
      { No warning enabled; commit to ANSI directly. }
      if KeyLayout.KeyboardMode <> bangla then
        KeyLayout.KeyboardMode := bangla;
      if OutputIsBijoy <> 'YES' then
        OutputIsBijoy := 'YES';
      SetCurrentWindowBanglaPreference(True);
      RefreshSettings;
    end;
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleAnsiVersionPicker;
begin
  { One popup at a time: the hook routes keys to a single picker and the mouse
    dismiss hook belongs to a single window. }
  if (CurrentLayoutPicker <> nil) and (not CurrentLayoutPicker.Closing) then
    CurrentLayoutPicker.RequestDismiss;
  ShowAnsiVersionPicker;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ToggleLayoutPicker;
begin
  if (CurrentPicker <> nil) and (not CurrentPicker.Closing) then
    CurrentPicker.RequestDismiss;
  ShowLayoutPickerPopup;
end;

{ =============================================================================== }

procedure TAvroMainForm1.WMShowLayoutPicker(var Msg: TMessage);
begin
  ToggleLayoutPicker;
end;

{ =============================================================================== }

procedure TAvroMainForm1.ApplyPendingANSISwitchRevert;
var
  ActiveWindow: HWND;
  WindowRecord: TWindowRecord;
  OutputChanged: Boolean;
begin
  if not PendingANSISwitch then
    Exit;
  PendingANSISwitch := False;

  if (SwitchingMode <> SWITCHING_MODE_GLOBAL) and Assigned(WindowDict) and (PendingANSISwitchWindow <> 0) then
  begin
    if PendingANSISwitchHadRecord then
      WindowDict.AddOrSetValue(PendingANSISwitchWindow, PendingANSISwitchRecord)
    else
      WindowDict.Remove(PendingANSISwitchWindow);
  end;

  ActiveWindow := GetModeWindow;
  if (SwitchingMode = SWITCHING_MODE_GLOBAL) or (ActiveWindow = PendingANSISwitchWindow) then
  begin
    OutputChanged := OutputIsBijoy <> PreviousOutputBeforeANSISwitch;
    FApplyingWindowMode := True;
    try
      OutputIsBijoy := PreviousOutputBeforeANSISwitch;
      if KeyLayout.KeyboardMode <> PreviousModeBeforeANSISwitch then
        KeyLayout.KeyboardMode := PreviousModeBeforeANSISwitch;
      MyCurrentKeyboardMode := PreviousModeBeforeANSISwitch;
    finally
      FApplyingWindowMode := False;
    end;
    if OutputChanged then
      RefreshSettings;
  end
  else if (ActiveWindow <> 0) and Assigned(WindowDict) then
  begin
    if not WindowDict.TryGetValue(ActiveWindow, WindowRecord) then
    begin
      WindowRecord.Mode := wimEnglish;
      WindowRecord.LastBanglaMode := wbmUnicode;
      WindowDict.AddOrSetValue(ActiveWindow, WindowRecord);
    end;
    ApplyWindowMode(ActiveWindow, WindowRecord);
  end;

  PendingANSISwitchWindow := 0;
  PendingANSISwitchHadRecord := False;
end;

{ =============================================================================== }

procedure TAvroMainForm1.CommitPendingANSISwitch;
var
  TargetWindow, ActiveWindow: HWND;
  WindowRecord: TWindowRecord;
begin
  if not PendingANSISwitch then
  begin
    OutputIsBijoy := 'YES';
    SetCurrentWindowBanglaPreference(True);
    Exit;
  end;

  TargetWindow := PendingANSISwitchWindow;
  PendingANSISwitch := False;
  OutputIsBijoy := 'YES';

  if SwitchingMode = SWITCHING_MODE_GLOBAL then
  begin
    if PendingANSISwitchEnablesBangla and (KeyLayout.KeyboardMode <> bangla) then
      KeyLayout.KeyboardMode := bangla;
    RefreshSettings;
  end
  else
  begin
    if Assigned(WindowDict) and IsWindow(TargetWindow) then
    begin
      WindowRecord := PendingANSISwitchRecord;
      WindowRecord.LastBanglaMode := wbmANSI;
      if PendingANSISwitchEnablesBangla or (WindowRecord.Mode = wimBanglaUnicode) then
        WindowRecord.Mode := wimBanglaANSI;
      WindowDict.AddOrSetValue(TargetWindow, WindowRecord);
    end;

    ActiveWindow := GetModeWindow;
    if (ActiveWindow = TargetWindow) and IsWindow(TargetWindow) then
    begin
      FApplyingWindowMode := True;
      try
        if PendingANSISwitchEnablesBangla and (KeyLayout.KeyboardMode <> bangla) then
          KeyLayout.KeyboardMode := bangla;
        MyCurrentKeyboardMode := KeyLayout.KeyboardMode;
      finally
        FApplyingWindowMode := False;
      end;
      SetCurrentWindowBanglaPreference(True);
      RefreshSettings;
    end
    else if (ActiveWindow <> 0) and Assigned(WindowDict) then
    begin
      if not WindowDict.TryGetValue(ActiveWindow, WindowRecord) then
      begin
        WindowRecord.Mode := wimEnglish;
        WindowRecord.LastBanglaMode := wbmUnicode;
        WindowDict.AddOrSetValue(ActiveWindow, WindowRecord);
      end;
      ApplyWindowMode(ActiveWindow, WindowRecord);
    end;
  end;

  PendingANSISwitchWindow := 0;
  PendingANSISwitchHadRecord := False;
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
    Exit;
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

{ Both of these are called from the keyboard hook for every keystroke, so they
  must survive the window in which FormClose has nilled AvroMainForm1 - and the
  one in which ExitApp has freed KeyLayout. "Not handled" is the only sane
  answer there: the key then passes through untouched. }
function TAvroMainForm1.TransferKeyDown(const KeyCode: Integer; var Block: Boolean): string;
begin
  Result := '';
  Block := False;

  { A cold start can fail to activate the persisted mapping (a container still
    locked by an updater or a scanner, a failed decrypt) while the hook is
    installed anyway. The globals then hold the compiled-in canvas instead of
    the user's version, and typing would silently render the built-in
    Avro/V1 glyphs until the version is picked again by hand. Convert only
    through a real engine: repair from the selected file here, on the first
    keystroke, and leave the previous behaviour untouched otherwise. }
  if (OutputIsBijoy = 'YES') and (not AnsiEngineManager.EnginePrepared) then
    AnsiEngineManager.RepairSelectedEngine;

  if Assigned(KeyLayout) then
    Result := KeyLayout.ProcessVKeyDown(KeyCode, Block);
end;

{ =============================================================================== }

procedure TAvroMainForm1.TransferKeyUp(const KeyCode: Integer; var Block: Boolean);
begin
  Block := False;
  if Assigned(KeyLayout) then
    KeyLayout.ProcessVKeyUP(KeyCode, Block);
end;

{ True while either popup is on screen.

  The hook stops feeding the layout engine and takes the navigation keys over
  from the popup's own keyboard handlers only while this is True, so it has to
  cover BOTH popups - and it has to go False the instant one starts closing:
  BeginClose unregisters the picker before the modal dialog its own apply path
  may raise (a mapping password, a layout-load failure), otherwise the hook
  would keep eating the Enter, letters and digits that dialog needs. }
function TAvroMainForm1.IsPickerOpen: Boolean;
begin
  Result := ((CurrentPicker <> nil) and (not CurrentPicker.Closing) and CurrentPicker.HandleAllocated and IsWindow(CurrentPicker.Handle)) or
    ((CurrentLayoutPicker <> nil) and (not CurrentLayoutPicker.Closing) and CurrentLayoutPicker.HandleAllocated and IsWindow(CurrentLayoutPicker.Handle));
end;

{ =============================================================================== }

{ Hands a navigation key to whichever popup is on screen.

  This is what makes the keyboard work on a machine where the popup can not
  steal the foreground: the hook runs in this process regardless of who owns the
  foreground, and PostMessage puts the key on this thread's own queue, where the
  popup's message loop will dispatch it. Focus is never consulted. }
function TAvroMainForm1.RouteKeyToPicker(AVkCode: Integer): Boolean;
begin
  Result := False;
  if (CurrentPicker <> nil) and (not CurrentPicker.Closing) and CurrentPicker.HandleAllocated and IsWindow(CurrentPicker.Handle) then
    Result := PostMessage(CurrentPicker.Handle, WM_PICKER_KEY, AVkCode, 0) <> False
  else if (CurrentLayoutPicker <> nil) and (not CurrentLayoutPicker.Closing) and CurrentLayoutPicker.HandleAllocated and IsWindow(CurrentLayoutPicker.Handle)
  then
    Result := PostMessage(CurrentLayoutPicker.Handle, WM_PICKER_KEY, AVkCode, 0) <> False;
end;

{ =============================================================================== }

{ The process-wide last resort, installed as Application.OnException by the
  program file.

  It must never raise and never block: one debugger line, and at most one tray
  balloon per session. Nothing here touches a file and no keystroke is ever
  recorded (DebugLog writes to the debugger only). }
procedure TAvroMainForm1.ReportUnhandledException(E: Exception);
var
  Msg: string;
begin
  try
    { In the startup log too: this handler is the last stop before an exception
      disappears, and the tray alone cannot show it (see below). Class only:
      unlike a startup step, this one can fire while the user is typing, and an
      exception message may quote the text being handled. }
    StartupLogExceptionClass('Application.OnException', E);

    if Assigned(E) then
      Log('Unhandled ' + E.ClassName + ': ' + E.Message);

    if FUnhandledReported then
      Exit;
    FUnhandledReported := True;

    if Assigned(Tray) and Tray.Visible then
    begin
      Tray.BalloonTitle := 'Avro Keyboard';
      Tray.BalloonHint := 'An internal error was handled and Avro is still running.' + sLineBreak + 'Restart Avro if typing misbehaves.';
      Tray.BalloonTimeout := 5000;
      Tray.ShowBalloonHint;
    end
    else
    begin
      { No tray yet (a failure during FormCreate/LoadApp) or top-bar mode,
        where a balloon has no visible surface: without this the exception
        simply vanished, which is how a half-started Avro looked like "it
        just does not open". }
      Msg := 'Avro Keyboard hit an internal error and handled it.' + sLineBreak + sLineBreak;
      if Assigned(E) then
        Msg := Msg + E.ClassName + ': ' + E.Message + sLineBreak + sLineBreak;
      Msg := Msg + 'Restart Avro if typing misbehaves.' + sLineBreak + StartupLogHint;
      MessageBox(0, PChar(Msg), 'Avro Keyboard', MB_OK or MB_ICONWARNING or MB_SETFOREGROUND);
    end;
  except
    { A crash reporter that raises is worse than the fault it reports. }
  end;
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
begin
  { Kept as the form-level entry point for the existing callers (word database
    load, auto-correct dictionary reload), but the body is now one syscall on
    the current process:

    - OpenProcess(PROCESS_ALL_ACCESS) for our OWN process was pure overhead:
    GetCurrentProcess needs no handle, no access mask, and cannot fail.
    - Application.ProcessMessages does not belong here at all. This routine is
    called from a TTimer handler (IdleTimerTimer) and from inside the word
    database load, so pumping the message queue here re-entered the timer,
    the hook's deferred emit path and every paint handler in the middle of a
    memory operation. }
  TrimProcessWorkingSet;
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
  LaunchAvroTextConverter;
end;

{ Starts the Qt text converter that ships in converter\ beside this exe.  A
  portable edition hands it the portable AnsiMapping folder; an installed one
  lets the converter read the mappings of the Avro Keyboard installation. }
procedure TAvroMainForm1.LaunchAvroTextConverter;
var
  ExePath, WorkDir, Params: string;
begin
  WorkDir := ExtractFilePath(ParamStr(0)) + 'converter\';
  ExePath := WorkDir + 'AvroTextConverter.exe';
  if not FileExists(ExePath) then
  begin
    MessageDlg('The text converter could not be found:' + sLineBreak + ExePath, mtWarning, [mbOK], 0);
    Exit;
  end;

  Params := '';
  {$IFDEF PortableOn}
  Params := '--mapping-dir "' + ExtractFilePath(ParamStr(0)) + 'AnsiMapping"';
  {$ENDIF}
  ShellExecute(Handle, 'open', PChar(ExePath), PChar(Params), PChar(WorkDir), SW_SHOWNORMAL);
end;

procedure TAvroMainForm1.WMLaunchTextConverter(var Msg: TMessage);
begin
  LaunchAvroTextConverter;
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
  Execute_Something('https://t.me/AvroUsersCommunity');
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
  if (AnsiMappingDir <> '') and (AnsiVersionFileName <> '') then
  begin
    Dec(FMappingCheckCountdown);
    if FMappingCheckCountdown <= 0 then
    begin
      FMappingCheckCountdown := 10; // ~1 second at Interval = 100 ms
      try
        MapPath := GetExactEncoFilePath(AnsiVersionFileName, AnsiMappingDir);
        if MapPath <> '' then
        begin
          MapWriteTime := TFile.GetLastWriteTime(MapPath);
          if (MapWriteTime <> 0) and (MapWriteTime <> FActiveMappingLastWriteTime) then
          begin
            FActiveMappingLastWriteTime := MapWriteTime;
            AnsiEngineManager.InvalidateEngine(AnsiVersionFileName);
            Log('ANSI Encoding Auto-Refreshed: ' + AnsiVersionFileName);
          end;
        end;
        // MapPath = '': the selected exact file is gone. No sibling and no
        // auto-refresh; the running engine stays live until the user chooses.
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

    // Learned phonetic suggestion choices (CandidateOptions.dat) are persisted
    // from here on purpose: the only other write point used to be the engine's
    // destructor, so a crash or a forced close threw the session away, and
    // writing straight from the typing path would put disk I/O inside the
    // keyboard hook.
    if Assigned(KeyLayout) then
      KeyLayout.SaveCandidateOptionsIfDirty;
  end;

  // Layouts folder: same cadence, and no watcher at all.  Adding or deleting a
  // .avrolayout rewrites the layout menus without a restart.
  Dec(FLayoutCheckCountdown);
  if FLayoutCheckCountdown <= 0 then
  begin
    FLayoutCheckCountdown := 15; // ~1.5 seconds at Interval = 100 ms
    RefreshLayoutList;
  end;

  if Assigned(FDirectoryWatcher) then
    FDirectoryWatcher.CheckForChanges;

  hforewnd := GetForegroundWindow;
  if hforewnd = 0 then
    Exit;
  if IsWindow(hforewnd) = False then
    Exit; { Experimental use }

  if IgnorableWindow(hforewnd) = True then
    Exit;
  if hforewnd = LastWindow then
    Exit;

  // window z-order has been changed
  // ==================================
  // Aggressive mode
  RemoveHook;
  Sethook;

  if Topbar.Visible = True then
    TOPMOST(Topbar.Handle);
  // ==================================

  { The per-window memory only applies while the user asked for it.  In GLOBAL
    the mode is one state for the whole desktop, so a window change must not
    restore or reset it.  The dead key and the last-window bookkeeping run in
    both scopes: a half-typed dead key must never cross a window boundary. }
  if SwitchingMode <> SWITCHING_MODE_GLOBAL then
  begin
    if not WindowDict.TryGetValue(hforewnd, WindoRecord) then
    begin
      WindoRecord.Mode := wimEnglish;
      WindoRecord.LastBanglaMode := wbmUnicode;
      WindowDict.AddOrSetValue(hforewnd, WindoRecord);
    end;
    ApplyWindowMode(hforewnd, WindoRecord);
  end;
  KeyLayout.ResetDeadKey;
  LastWindow := hforewnd;
end;

procedure TAvroMainForm1.WMShowAnsiPicker(var Msg: TMessage);
begin
  ToggleAnsiVersionPicker;
end;

procedure TAvroMainForm1.WMDeferredRefresh(var Msg: TMessage);
begin
  { Deferred half of RefreshSettings: see the note there. Arriving here means we
    are on the message loop, where modal dialogs (the corrupt-database notice)
    and the engine reload are safe. }
  RefreshSettings;
end;

procedure TAvroMainForm1.WMSwitchToAnsiMode(var Msg: TMessage);
begin
  SetBengaliANSIMode;
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

  if cmd = 'refresh_enco' then
  begin
    HandleRemoteEncoRefresh;

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
  ClickedItem:                         TMenuItem;
  SelectedFile, ErrorMsg, TargetPath:  string;
  Password:                            AnsiString;
  ErrorLog:                            TStringList;
begin
  if not(Sender is TMenuItem) then
    Exit;
  ClickedItem := TMenuItem(Sender);

  // The row's identity is its Hint (the exact file name). A caption is a label
  // only and is never parsed back into an identity.
  SelectedFile := ClickedItem.Hint;
  if SelectedFile = '' then
    Exit;

  // One path for every selection: resolve only this exact file, prompt for a
  // password if this container needs one and none is cached, then switch.
  // There is no compiled-in Default row and no same-base fallback.
  TargetPath := GetExactEncoFilePath(SelectedFile, AnsiMappingDir);
  if TargetPath = '' then
  begin
    Application.MessageBox(PChar('Mapping file not found: ' + SelectedFile), 'Error', MB_ICONWARNING or MB_OK or MB_TOPMOST or MB_SETFOREGROUND);
    Exit;
  end;

  // For a password-protected encrypted file without a usable cached
  // password, ask for the password once up front; SwitchEngine then reuses
  // CachedEncoPassword and never prompts a second time.
  // Default-key files (flag $00) load transparently and never prompt.
  // Ask only when THIS file was never unlocked on this computer; the per-file
  // cache then unlocks every later switch silently (even after a full restart).
  if IsEncoFile(TargetPath) and (GetEncoCachedPassword(TargetPath) = '') and (GetAvroEncoProtectionFlag(TargetPath) = AVROENCO_FLAG_USER_PASSWORD) then
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
  if not AnsiEngineManager.TrySwitchCached(SelectedFile) then
  begin
    Screen.Cursor := crHourGlass;
    ErrorLog := TStringList.Create;
    try
      if not AnsiEngineManager.SwitchEngine(SelectedFile, ErrorLog) then
        ErrorMsg := 'Encoding is still being prepared. Please select it again.';
    finally
      ErrorLog.Free;
      Screen.Cursor := crDefault;
    end;
  end;
  if ErrorMsg = '' then
  begin
    if Assigned(KeyLayout) then
      KeyLayout.ResetAnsiTypingState;

    // The manager published both selection globals from the slot that became
    // live; persist that exact pair and refresh what depends on it.
    SyncActiveMappingTimestamp(AnsiVersionFileName);
    SaveAnsiVersionOnly;
    UpdateAnsiVersionMenuChecks(AnsiVersionFileName);
    ReplaceAnsiMenuParentIcon;
    UpdateTrayIcon;
    if ShowAnsiSwitchNotification = 'YES' then
      ShowAnsiToastNotification('ANSI Encoding: ' + GetMappingDisplayLabel(AnsiVersionFileName));
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
  MapFile: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapFile := (Sender as TMenuItem).Hint;
  if MapFile = '' then
    Exit;
  ShowMappingDescription(MapFile);
end;

{ =============================================================================== }

{ Exporting specific mappings }
procedure TAvroMainForm1.ExportSpecificMappingClick(Sender: TObject);
var
  MapFile: string;
begin
  if not(Sender is TMenuItem) then
    Exit;
  MapFile := (Sender as TMenuItem).Hint;
  if MapFile = '' then
    Exit;
  ExportMappingFile(MapFile);
end;

{ =============================================================================== }

procedure TAvroMainForm1.ImportAnsiMappingClick(Sender: TObject);
var
  OpenDialog:            TOpenDialog;
  ErrMsg, ErrorMessages: string;
  I:                     Integer;

  procedure AddError(const AFileName, AMessage: string);
  begin
    if ErrorMessages <> '' then
      ErrorMessages := ErrorMessages + sLineBreak;
    ErrorMessages := ErrorMessages + ExtractFileName(AFileName) + ': ' + AMessage;
  end;

begin
  OpenDialog := TOpenDialog.Create(nil);
  try
    OpenDialog.Filter := 'ANSI Encoding|*.json;*.AvroEnco';
    OpenDialog.DefaultExt := 'AvroEnco';
    OpenDialog.Title := 'Import ANSI Encoding';
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
        end
        else if SameText(ExtractFileExt(OpenDialog.Files[I]), '.json') then
        begin
          // Structural validation, copy, scan, activation and toast
          // (uAvroEncoImporter.ImportJsonMappingFile - also used by drag &
          // drop). Plain JSON mappings are unprotected, so import activates
          // them.
          if not ImportJsonMappingFile(OpenDialog.Files[I], ErrMsg) and (ErrMsg <> '') then
            AddError(OpenDialog.Files[I], 'ANSI mapping import failed:'#13#10#13#10 + ErrMsg);
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

procedure TAvroMainForm1.DownloadMoreResourcesClick(Sender: TObject);
begin
  ShowResourceBrowser;
end;

{ Balloon click for the "no ANSI mappings found" case - the balloon text says
  "Click here to download default mappings", and this is that click. Restores
  deleted/missing mappings from the resource repository. }

procedure TAvroMainForm1.NoMappingBalloonClick(Sender: TObject);
begin
  ShowResourceBrowser;
end;

{ The auto-correct dictionary could not be read. The load itself has to stay
  silent - it runs inside the WH_KEYBOARD_LL callback, where a dialog would
  get the hook removed - so this is where the user hears about it: once per
  session, from the message loop. Clicking the balloon opens the resource
  downloader, which is where the dictionary comes from. }

procedure TAvroMainForm1.ShowAutoCorrectMissingBalloon;
const
  Msg = 'Auto-correct dictionary (autodict.dct) is missing.' + sLineBreak + 'Typing works normally - only phonetic auto-correct is off.';
begin
  if FNoDictBalloonShown then
    Exit;
  FNoDictBalloonShown := True;

  if Assigned(Tray) and Tray.Visible then
  begin
    Tray.BalloonTitle := 'Avro Keyboard';
    Tray.BalloonHint := Msg + sLineBreak + 'Click here to download the dictionary.';
    Tray.OnBalloonClick := NoDictBalloonClick;
    Tray.BalloonTimeout := 10000;
    Tray.ShowBalloonHint;
    Exit;
  end;

  { Top bar mode has no tray icon, so there is nothing to click. The notice
    still has to reach the user once - it rides the top bar's own hint
    balloon, which the menu route (Resources Management) completes. }
  if Assigned(Topbar) and Topbar.Visible then
  begin
    Topbar.ShowBalloon(Msg + sLineBreak + 'Choose "Tools" - "Resources Management" from the Avro menu.');
  end;
end;

{ =============================================================================== }

procedure TAvroMainForm1.NoDictBalloonClick(Sender: TObject);
begin
  ShowResourceBrowser('dictionary');
end;

{ =============================================================================== }

{ Database.db3 carries the word database the phonetic candidates are built
  from. It loads with the settings refresh at startup, and when the file is
  absent uDBase reports nothing - that load can be reached from the keyboard
  hook, where UI would get the hook removed - so this is where the user hears
  about it. The balloon's click takes them to the downloader that restores
  the file. }

procedure TAvroMainForm1.CheckWordDatabasePresence;
begin
  // The same rule RefreshSettings loads by: without the preview window's
  // candidate lists the database is not read, so there is nothing to report.
  if (ShowPrevWindow = 'NO') or (PhoneticMode = 'ONLYCHAR') then
    Exit;
  if WordDatabaseFilePresent then
    Exit;
  ShowMissingDatabaseBalloon;
end;

procedure TAvroMainForm1.ShowMissingDatabaseBalloon;
const
  Msg = 'Word database (Database.db3) is missing.' + sLineBreak + 'Phonetic suggestions and Bangla word completion are off - typing falls back to English.';
begin
  if FNoDatabaseBalloonShown then
    Exit;
  FNoDatabaseBalloonShown := True;

  if Assigned(Tray) and Tray.Visible then
  begin
    Tray.BalloonTitle := 'Avro Keyboard';
    Tray.BalloonHint := Msg + sLineBreak + 'Click here to download the database.';
    Tray.OnBalloonClick := MissingDatabaseBalloonClick;
    Tray.BalloonTimeout := 10000;
    Tray.ShowBalloonHint;
    Exit;
  end;

  { Top bar mode has no tray icon, so there is nothing to click. The notice
    still has to reach the user once - it rides the top bar's own hint
    balloon, which the menu route (Resources Management) completes. }
  if Assigned(Topbar) and Topbar.Visible then
  begin
    Topbar.ShowBalloon(Msg + sLineBreak + 'Choose "Tools" - "Resources Management" from the Avro menu.');
  end;
end;

procedure TAvroMainForm1.MissingDatabaseBalloonClick(Sender: TObject);
begin
  ShowResourceBrowser('worddatabase');
end;

{ The downloader installed Database.db3 (the shared "dict" resource type -
  same folder autodict.dct goes to). The load that failed silently at startup
  is retried here: RefreshSettings is the only other caller, and it does not
  run on an install, so without this the fix would need an Avro restart. }

procedure TAvroMainForm1.ReloadWordDatabaseIfUsed;
begin
  if (ShowPrevWindow = 'NO') or (PhoneticMode = 'ONLYCHAR') then
    Exit;
  LoadWordDatabase;
end;

{ =============================================================================== }

procedure TAvroMainForm1.DeleteAnsiMappingClick(Sender: TObject);
var
  MapFile: string;
begin
  if Sender is TMenuItem then
  begin
    MapFile := (Sender as TMenuItem).Hint;
    if MapFile = '' then
      Exit;
    DeleteMappingFile(MapFile);
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

{ Fast switch UI update: never scans the directory and never destroys/rebuilds
  menu objects. Full BuildAnsiVersionMenus remains reserved for file changes. }
procedure TAvroMainForm1.SyncActiveMappingTimestamp(const AFileName: string);
var
  P: string;
begin
  FActiveMappingLastWriteTime := 0;
  if (AFileName = '') or (AnsiMappingDir = '') then
    Exit;
  P := GetExactEncoFilePath(AFileName, AnsiMappingDir);
  if P = '' then
    Exit;
  try
    FActiveMappingLastWriteTime := TFile.GetLastWriteTime(P);
  except
    FActiveMappingLastWriteTime := 0;
  end;
end;

procedure TAvroMainForm1.UpdateAnsiVersionMenuChecks(const AFileName: string);
  procedure UpdateOne(AMenu: TMenuItem);
  var
    I: Integer;
    M: TMenuItem;
  begin
    if not Assigned(AMenu) then
      Exit;
    for I := 0 to AMenu.Count - 1 do
    begin
      M := AMenu.Items[I];
      // Only version rows: the "More Options" submenu parent also carries the
      // exact file in its Hint and must not draw a checkmark.
      if M.GroupIndex = 10 then
        M.Checked := SameText(M.Hint, AFileName);
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
  Sep, Item: TMenuItem;
  Snap:                   string;

  procedure AddDirectItem(ParentMenu: TMenuItem; const ALabel, AFileName: string; AChecked: Boolean);
  var
    MItem: TMenuItem;
  begin
    MItem := TMenuItem.Create(ParentMenu);
    MItem.Caption := EscapeAmpersandsForMenu(ALabel);
    MItem.Hint := AFileName; // exact identity; never parsed from the caption
    MItem.GroupIndex := ANSI_VERSION_ROW_GROUP;
    // RadioItem stays FALSE even though the version rows are a mutually
    // exclusive set: Vcl.Menus paints a radio item's bullet dot, while this row
    // has always carried the check glyph every other checked Avro item shows -
    // and that glyph comes straight from the popup style hook (see
    // TStyledMenuBorderHook). The exclusivity itself is not VCL's
    // radio auto-uncheck but UpdateAnsiVersionMenuChecks/SyncAnsiVersionChecks,
    // which re-derive every row's Checked from AnsiVersionFileName on each
    // popup and after each switch. GroupIndex = 10 is what marks a row as a
    // version item.
    MItem.RadioItem := False;
    MItem.Checked := AChecked;
    MItem.OnClick := AnsiVersionMenuClick;
    ParentMenu.Add(MItem);
  end;

  { The actions lead and each one opens the encoding list, so the submenu reads
    action -> encoding instead of one submenu per encoding.  Every leaf carries
    the exact file in Hint (the caption is never parsed back) and calls the same
    handler the old per-mapping submenu used. }
  procedure AddMappingActionMenus(AParent: TMenuItem);

    procedure AddLeaves(ActionMenu: TMenuItem; AHandler: TNotifyEvent);
    var
      I:        Integer;
      FileName: string;
      Leaf:     TMenuItem;
    begin
      if not Assigned(AnsiMappingFileNames) then
        Exit;

      for I := 0 to AnsiMappingFileNames.Count - 1 do
      begin
        FileName := AnsiMappingFileNames[I];
        Leaf := TMenuItem.Create(ActionMenu);
        Leaf.Caption := EscapeAmpersandsForMenu(GetMappingDisplayLabel(FileName));
        Leaf.Hint := FileName;
        Leaf.OnClick := AHandler;
        ActionMenu.Add(Leaf);
      end;
    end;

    procedure AddAction(const ACaption: string; AHandler: TNotifyEvent);
    var
      ActionMenu: TMenuItem;
    begin
      ActionMenu := TMenuItem.Create(AParent);
      ActionMenu.Caption := ACaption;
      AParent.Add(ActionMenu);
      AddLeaves(ActionMenu, AHandler);
    end;

  begin
    AddAction('Information', ReadAnsiDescriptionClick);
    AddAction('Export Mapping...', ExportSpecificMappingClick);
    AddAction('Delete Mapping', DeleteAnsiMappingClick);
  end;

  procedure BuildSingleMenu(AMenu: TMenuItem);
  var
    I:         Integer;
    FileName:  string;
    LabelText: string;
  begin
    if not Assigned(AMenu) then
      Exit;
    AMenu.Clear;

    // The full scanned catalog in shared natural order - no prepended
    // "Default" row. AnsiMappingFileNames carries every exact file, including
    // both members of a same-base pair; AnsiMappingNames holds the matching
    // labels and is filled in the same index order by RefreshAnsiMappingNames.
    if Assigned(AnsiMappingFileNames) then
      for I := 0 to AnsiMappingFileNames.Count - 1 do
      begin
        FileName := AnsiMappingFileNames[I];
        LabelText := GetMappingDisplayLabel(FileName);
        AddDirectItem(AMenu, LabelText, FileName, SameText(AnsiVersionFileName, FileName));
      end;

    // Separator
    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);

    // The actions live in this submenu itself, right below the version rows:
    // there is no "More Options" parent left to open first.
    AddMappingActionMenus(AMenu);

    // Separator
    Sep := TMenuItem.Create(AMenu);
    Sep.Caption := '-';
    AMenu.Add(Sep);

    Item := TMenuItem.Create(AMenu);
    Item.Caption := 'Import Mapping...';
    Item.OnClick := ImportAnsiMappingClick;
    AMenu.Add(Item);

    Item := TMenuItem.Create(AMenu);
    Item.Caption := 'Locate Mapping...';
    Item.OnClick := OpenAnsiMappingDirClick;
    AMenu.Add(Item);
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
    // ScanAvroEncoFiles drops the per-mapping icon bytes; the GDI handles and
    // the parent-menu slot derived from them have to be invalidated with them,
    // or a renamed or deleted mapping would keep drawing its old icon.
    ReleaseAnsiIconCache;
    ScanAvroEncoFiles(AnsiMappingDir);
  end;
  RefreshAnsiMappingNames;
  BuildSingleMenu(AnsiVersionSubmenu1);
  BuildSingleMenu(mnuTraySelectAnsiEncoding);

  // Child rows carry no artwork of their own. Both root parent items use the
  // active mapping icon (or the built-in ANSI fallback) from ImageList1.
end;

initialization
end.
