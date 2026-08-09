{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmOptions;

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
  ExtCtrls,
  CategoryButtons,
  StdCtrls,
  ComCtrls;

type
  TfrmOptions = class(TForm)
    Panel1: TPanel;
    Image1: TImage;
    TopLabel: TLabel;
    ButtonPanel: TPanel;
    Button_OK: TButton;
    Button_Cancel: TButton;
    CategoryTree: TTreeView;
    butEditCustomDict: TButton;
    CheckAddNewWords: TCheckBox;
    ScrollBox2: TScrollBox;
    FixedLayout_Panel: TPanel;
    GroupBox6: TGroupBox;
    Label10: TLabel;
    Label11: TLabel;
    optTypingStyle_Modern: TRadioButton;
    chkOldReph: TCheckBox;
    chkVowelFormat: TCheckBox;
    CheckChandraPosition: TCheckBox;
    optTypingStyle_Old: TRadioButton;
    CheckNumPadBangla: TCheckBox;
    KeyboardMode_Panel: TPanel;
    GroupBox4: TGroupBox;
    Label7: TLabel;
    comboFunctionKeys: TComboBox;
    General_Panel: TPanel;
    Label3: TLabel;
    GroupBox1: TGroupBox;
    Label2: TLabel;
    checkStartUp: TCheckBox;
    CheckShowSplash: TCheckBox;
    optStartupUIMode_TopBar: TRadioButton;
    optStartupUIMode_Tray: TRadioButton;
    optStartupUIMode_Last: TRadioButton;
    optTopBarXButton_Close: TRadioButton;
    optTopBarXButton_Minimize: TRadioButton;
    optTopBarXButton_ShowMenu: TRadioButton;
    CheckUpdate: TCheckBox;
    Interface_Panel: TPanel;
    Captionl_Transparency: TLabel;
    Label_Transparency: TLabel;
    checkTopBarTransparent: TCheckBox;
    TrackBar_Transparency: TTrackBar;
    GroupBox2: TGroupBox;
    Label5: TLabel;
    Label6: TLabel;
    comboSkin: TComboBox;
    ScrollBox1: TScrollBox;
    SkinPreviewPic: TImage;
    ccmdAboutSkin: TButton;
    AvroPhonetic_Panel: TPanel;
    GroupBox3: TGroupBox;
    Label_PhoneticTypingMode: TLabel;
    Label1: TLabel;
    Label4: TLabel;
    CheckShowPrevWindow: TCheckBox;
    optPhoneticMode_Dict: TRadioButton;
    optPhoneticMode_Char: TRadioButton;
    optPhoneticMode_OnlyChar: TRadioButton;
    CheckRememberCandidate: TCheckBox;
    CheckTabBrowsing: TCheckBox;
    Label9: TLabel;
    Label12: TLabel;
    GroupBox7: TGroupBox;
    CheckAutoCorrect: TCheckBox;
    cmdAutoCorrect: TButton;
    CheckEnableJoNukta: TCheckBox;
    CheckPipeToDot: TCheckBox;
    Label13: TLabel;
    Label14: TLabel;
    Button_Apply: TButton;
    Button_Help: TButton;
    LabelStatus: TLabel;
    GlobalOutput_Panel: TPanel;
    optOutputUnicode: TRadioButton;
    optOutputANSI: TRadioButton;
    CheckWarningAnsi: TCheckBox;
    CheckUnicodeToggleShortcut: TCheckBox;
    CheckANSIToggleShortcut: TCheckBox;
    CheckIgnoreCapsLockShortcut: TCheckBox;
    LabelHideTimer: TTimer;
    GroupBox8: TGroupBox;
    Label16: TLabel;
    comboFunctionKeys_OutputMode: TComboBox;
    GroupBox9: TGroupBox;
    Label18: TLabel;
    comboFunctionKeys_SpellerLauncher: TComboBox;
    Label20: TLabel;
    LabelGlobalHotkeysLink: TLabel;
    GroupBox10: TGroupBox;
    CheckShowAnsiSwitchNotification: TCheckBox;
    GroupBox11: TGroupBox;
    CheckShowLayoutSwitchNotification: TCheckBox;

    edtModeSwitch: TEdit;
    edtOutputMode: TEdit;
    edtSpellerLauncher: TEdit;
    edtLayoutSwitch: TEdit;
    edtAnsiVersion: TEdit;
    procedure FormCreate(Sender: TObject);
    procedure CategoryTreeClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure CategoryTreeKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure checkTopBarTransparentClick(Sender: TObject);
    procedure TrackBar_TransparencyChange(Sender: TObject);
    procedure comboSkinChange(Sender: TObject);
    procedure CheckShowPrevWindowClick(Sender: TObject);
    procedure butEditCustomDictClick(Sender: TObject);
    procedure cmdAutoCorrectClick(Sender: TObject);
    procedure Button_CancelClick(Sender: TObject);
    procedure Button_OKClick(Sender: TObject);
    procedure Button_HelpClick(Sender: TObject);
    procedure optTypingStyle_ModernClick(Sender: TObject);
    procedure ccmdAboutSkinClick(Sender: TObject);
    procedure CheckAddNewWordsClick(Sender: TObject);
    procedure Button_ApplyClick(Sender: TObject);
    procedure optOutputANSIMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure LabelHideTimerTimer(Sender: TObject);
    procedure LabelGlobalHotkeysLinkClick(Sender: TObject);
    procedure ShortcutEditClick(Sender: TObject);
    private
      { Private declarations }
      procedure LoadSettings;
      procedure SaveSettings;
      function GetListIndex(List: TStrings; SearchS: string): Integer;
    public
      { Public declarations }
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  frmOptions: TfrmOptions;

implementation

{$R *.dfm}

uses
  uRegistrySettings,
  uFileFolderHandling,
  SkinLoader,
  uWindowHandlers,
  ufrmAutoCorrect,
  WindowsVersion,
  uForm1,
  u_Admin,
  ufrmEncodingWarning,
  uKeyboardMacro;

const
  Show_Window_in_Taskbar = True;

  { =============================================================================== }

function IsHotkeyNone(const Text: string): Boolean;
var
  U: string;
begin
  U := UpperCase(Trim(Text));
  Result := (U = '') or (U = 'NONE') or (U = 'SET SHORTCUT') or (U = 'PRESS ANY KEY...');
end;

{ =============================================================================== }

procedure TfrmOptions.butEditCustomDictClick(Sender: TObject);
begin
  { TODO : Incomplete }
  Application.MessageBox('This feature is not yet implemented.', 'Avro Keyboard', MB_OK + MB_ICONEXCLAMATION + MB_DEFBUTTON1 + MB_APPLMODAL);
end;

{ =============================================================================== }

procedure TfrmOptions.Button_ApplyClick(Sender: TObject);
begin
  if Assigned(RecordingTargetEdit) then
    RecordingTargetEdit.Color := clWindow;
  IsRecordingHotkey := False;
  RecordingFinalized := False;
  RecordingTargetEdit := nil;
  Self.SaveSettings;
  AvroMainForm1.RefreshSettings;

  { Surface the "Settings saved!" status, auto-hidden after 2s
    by LabelHideTimer. Reset the timer in case the user clicks
    Apply again before the previous countdown finishes. }
  LabelStatus.Visible := True;
  LabelHideTimer.Enabled := False;
  LabelHideTimer.Enabled := True;
end;

{ =============================================================================== }

procedure TfrmOptions.Button_CancelClick(Sender: TObject);
begin
  if IsRecordingHotkey and Assigned(RecordingTargetEdit) then
  begin
    RecordingTargetEdit.Text := RecordingOldText;
    RecordingTargetEdit.Color := clWindow;
  end;
  IsRecordingHotkey := False;
  RecordingFinalized := False;
  RecordingTargetEdit := nil;
  Self.Close;
end;

{ =============================================================================== }

procedure TfrmOptions.Button_HelpClick(Sender: TObject);
begin
  AvroMainForm1.OpenHelpFile(25);
end;

{ =============================================================================== }

procedure TfrmOptions.Button_OKClick(Sender: TObject);
begin
  IsRecordingHotkey := False;
  RecordingFinalized := False;
  RecordingTargetEdit := nil;
  Self.SaveSettings;
  AvroMainForm1.RefreshSettings;
  Self.Close;
end;

{ =============================================================================== }

procedure TfrmOptions.CategoryTreeClick(Sender: TObject);
begin
  { Hide every settings panel first, then show only the one
    matching the selected tree node. This is robust against
    the Locale/Language node (added at runtime) being left
    visible when other categories are clicked. }
  General_Panel.Visible := False;
  Interface_Panel.Visible := False;
  KeyboardMode_Panel.Visible := False;
  AvroPhonetic_Panel.Visible := False;
  FixedLayout_Panel.Visible := False;
  GlobalOutput_Panel.Visible := False;

  case CategoryTree.Selected.Index of
    0:
      General_Panel.Visible := True;
    1:
      Interface_Panel.Visible := True;
    2:
      KeyboardMode_Panel.Visible := True; { "Global Hotkeys" }
    3:
      AvroPhonetic_Panel.Visible := True;
    4:
      FixedLayout_Panel.Visible := True;
    5:
      GlobalOutput_Panel.Visible := True;
  end;

  TopLabel.Caption := CategoryTree.Selected.Text + ' Settings...';
end;

{ =============================================================================== }

procedure TfrmOptions.CategoryTreeKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  CategoryTreeClick(nil);
end;

{ =============================================================================== }

procedure TfrmOptions.ccmdAboutSkinClick(Sender: TObject);
begin
  if comboSkin.Items[comboSkin.ItemIndex] = 'None' then
    GetSkinDescription('internalskin*')
  else
    GetSkinDescription(GetAvroDataDir + 'Skin\' + comboSkin.Items[comboSkin.ItemIndex] + '.avroskin');
end;

{ =============================================================================== }

procedure TfrmOptions.CheckAddNewWordsClick(Sender: TObject);
begin
  { TODO : Incomplete }

  // Application.MessageBox('This feature is not yet implemented.', 'Avro Keyboard', MB_OK + MB_ICONEXCLAMATION + MB_DEFBUTTON1 + MB_APPLMODAL);

end;

{ =============================================================================== }

procedure TfrmOptions.CheckShowPrevWindowClick(Sender: TObject);
begin
  if CheckShowPrevWindow.Checked = True then
  begin
    Label_PhoneticTypingMode.Enabled := True;
    optPhoneticMode_Dict.Enabled := True;
    optPhoneticMode_Char.Enabled := True;
    optPhoneticMode_OnlyChar.Enabled := True;
    CheckRememberCandidate.Enabled := True;
    CheckAddNewWords.Enabled := True;
    CheckTabBrowsing.Enabled := True;
  end
  else
  begin
    Label_PhoneticTypingMode.Enabled := False;
    optPhoneticMode_Dict.Enabled := False;
    optPhoneticMode_Char.Enabled := False;
    optPhoneticMode_OnlyChar.Enabled := False;
    CheckRememberCandidate.Enabled := False;
    CheckAddNewWords.Enabled := False;
    CheckTabBrowsing.Enabled := False;
  end;

end;

{ =============================================================================== }

procedure TfrmOptions.checkTopBarTransparentClick(Sender: TObject);
begin
  if checkTopBarTransparent.Checked = True then
  begin
    Captionl_Transparency.Enabled := True;
    TrackBar_Transparency.Enabled := True;
    Label_Transparency.Enabled := True;
  end
  else
  begin
    Captionl_Transparency.Enabled := False;
    TrackBar_Transparency.Enabled := False;
    Label_Transparency.Enabled := False;
  end;
end;

{ =============================================================================== }

procedure TfrmOptions.cmdAutoCorrectClick(Sender: TObject);
begin
  CheckCreateForm(TfrmAutoCorrect, frmAutoCorrect, 'frmAutoCorrect');
  frmAutoCorrect.Show;
end;

{ =============================================================================== }

procedure TfrmOptions.comboSkinChange(Sender: TObject);
begin
  try
    { Show skin preview for selected skin }
    if comboSkin.Items[comboSkin.ItemIndex] = 'None' then
      GetSkinPreviewPicture('internalskin*', SkinPreviewPic.Picture)
    else
      GetSkinPreviewPicture(GetAvroDataDir + 'Skin\' + comboSkin.Items[comboSkin.ItemIndex] + '.avroskin', SkinPreviewPic.Picture);
  except
    on E: Exception do
    begin
      // Nothing
    end;
  end;
end;

{ =============================================================================== }

procedure TfrmOptions.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  with Params do
  begin
    if Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle or WS_EX_APPWINDOW and not WS_EX_TOOLWINDOW;
      WndParent := GetDesktopwindow;
    end
    else if not Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle and not WS_EX_APPWINDOW;
    end;
  end;
end;

{ =============================================================================== }

procedure TfrmOptions.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  frmOptions := nil;
end;

{ =============================================================================== }

procedure TfrmOptions.FormCreate(Sender: TObject);
const
  LEFT_MARGIN   = 24;
  EDIT_WIDTH    = 180;
  GROUP_HEIGHT  = 75;
  GROUP_SPACING = 12;
begin

  { Arrange Panels }

  // Bring General_Panel to Top
  General_Panel.Visible := True;
  FixedLayout_Panel.Visible := False;
  AvroPhonetic_Panel.Visible := False;
  KeyboardMode_Panel.Visible := False;
  General_Panel.Visible := False;
  Interface_Panel.Visible := False;
  GlobalOutput_Panel.Visible := False;

  Interface_Panel.Top := 0;
  General_Panel.Top := 0;
  KeyboardMode_Panel.Top := 0;
  AvroPhonetic_Panel.Top := 0;
  FixedLayout_Panel.Top := 0;
  GlobalOutput_Panel.Top := 0;

  Interface_Panel.Left := 0;
  General_Panel.Left := 0;
  KeyboardMode_Panel.Left := 0;
  AvroPhonetic_Panel.Left := 0;
  FixedLayout_Panel.Left := 0;
  GlobalOutput_Panel.Left := 0;

  Interface_Panel.Width := Self.Width - CategoryTree.Width - 20;
  General_Panel.Width := Self.Width - CategoryTree.Width - 20;
  KeyboardMode_Panel.Width := Self.Width - CategoryTree.Width - 20;
  AvroPhonetic_Panel.Width := Self.Width - CategoryTree.Width - 20;
  FixedLayout_Panel.Width := Self.Width - CategoryTree.Width - 20;
  GlobalOutput_Panel.Width := Self.Width - CategoryTree.Width - 20;

  Interface_Panel.BevelKind := bknone { bkTile };
  General_Panel.BevelKind := bknone { bkTile };
  KeyboardMode_Panel.BevelKind := bknone { bkTile };
  AvroPhonetic_Panel.BevelKind := bknone { bkTile };
  FixedLayout_Panel.BevelKind := bknone { bkTile };
  GlobalOutput_Panel.BevelKind := bknone;

  if CategoryTree.Items.Count > 0 then
    CategoryTree.Items[0].Selected := True;

  // =======================================================
  // Replace ComboBoxes with interactive TEdit shortcut recorders
  // Hide the existing ComboBoxes
  comboFunctionKeys.Visible := False;
  comboFunctionKeys_OutputMode.Visible := False;
  comboFunctionKeys_SpellerLauncher.Visible := False;

  // =======================================================
  // Standardize GroupBox layout inside KeyboardMode_Panel
  GroupBox4.Left := 16;
  GroupBox4.Width := KeyboardMode_Panel.Width - 60;
  GroupBox4.Top := 12;
  GroupBox4.Height := GROUP_HEIGHT;

  GroupBox8.Left := GroupBox4.Left;
  GroupBox8.Width := GroupBox4.Width;
  GroupBox8.Top := GroupBox4.Top + GroupBox4.Height + GROUP_SPACING;
  GroupBox8.Height := GROUP_HEIGHT;

  GroupBox9.Left := GroupBox4.Left;
  GroupBox9.Width := GroupBox4.Width;
  GroupBox9.Top := GroupBox8.Top + GroupBox8.Height + GROUP_SPACING;
  GroupBox9.Height := GROUP_HEIGHT;

  // Shift sub-labels upward within their GroupBoxes
  Label7.Top := 16;
  Label16.Top := 16;
  Label18.Top := 16;

  // Create TEdit for Keyboard Mode Switch (in GroupBox4)
  edtModeSwitch := TEdit.Create(GroupBox4);
  edtModeSwitch.Parent := GroupBox4;
  edtModeSwitch.Left := LEFT_MARGIN;
  edtModeSwitch.Top := 35;
  edtModeSwitch.Width := EDIT_WIDTH;
  edtModeSwitch.ReadOnly := True;
  edtModeSwitch.Text := 'Set Shortcut';
  edtModeSwitch.Color := clWindow;
  edtModeSwitch.OnClick := ShortcutEditClick;

  // Create TEdit for Output Mode Toggle (in GroupBox8)
  edtOutputMode := TEdit.Create(GroupBox8);
  edtOutputMode.Parent := GroupBox8;
  edtOutputMode.Left := LEFT_MARGIN;
  edtOutputMode.Top := 35;
  edtOutputMode.Width := EDIT_WIDTH;
  edtOutputMode.ReadOnly := True;
  edtOutputMode.Text := 'Set Shortcut';
  edtOutputMode.Color := clWindow;
  edtOutputMode.OnClick := ShortcutEditClick;

  // Create TEdit for Speller Launcher (in GroupBox9)
  edtSpellerLauncher := TEdit.Create(GroupBox9);
  edtSpellerLauncher.Parent := GroupBox9;
  edtSpellerLauncher.Left := LEFT_MARGIN;
  edtSpellerLauncher.Top := 35;
  edtSpellerLauncher.Width := EDIT_WIDTH;
  edtSpellerLauncher.ReadOnly := True;
  edtSpellerLauncher.Text := 'Set Shortcut';
  edtSpellerLauncher.Color := clWindow;
  edtSpellerLauncher.OnClick := ShortcutEditClick;

  // =======================================================
  // Layout Switcher Hotkey UI (runtime-created)
  GroupBox11 := TGroupBox.Create(KeyboardMode_Panel);
  GroupBox11.Parent := KeyboardMode_Panel;
  GroupBox11.Left := GroupBox4.Left;
  GroupBox11.Width := GroupBox4.Width;
  GroupBox11.Top := GroupBox9.Top + GroupBox9.Height + GROUP_SPACING;
  GroupBox11.Height := GROUP_HEIGHT;
  GroupBox11.Caption := 'Layout Switcher';

  // Create TEdit for Layout Switcher (in GroupBox11)
  edtLayoutSwitch := TEdit.Create(GroupBox11);
  edtLayoutSwitch.Parent := GroupBox11;
  edtLayoutSwitch.Left := LEFT_MARGIN;
  edtLayoutSwitch.Top := 30;
  edtLayoutSwitch.Width := EDIT_WIDTH;
  edtLayoutSwitch.ReadOnly := True;
  edtLayoutSwitch.Text := 'Set Shortcut';
  edtLayoutSwitch.Color := clWindow;
  edtLayoutSwitch.OnClick := ShortcutEditClick;

  CheckShowLayoutSwitchNotification := TCheckBox.Create(GroupBox11);
  CheckShowLayoutSwitchNotification.Parent := GroupBox11;
  CheckShowLayoutSwitchNotification.Left := edtLayoutSwitch.Left + edtLayoutSwitch.Width + 16;
  CheckShowLayoutSwitchNotification.Top := edtLayoutSwitch.Top + 1;
  CheckShowLayoutSwitchNotification.Caption := 'Show notification on switch';
  CheckShowLayoutSwitchNotification.Width := 150;

  // =======================================================
  // ANSI Version Switcher Hotkey UI (runtime-created)
  GroupBox10 := TGroupBox.Create(KeyboardMode_Panel);
  GroupBox10.Parent := KeyboardMode_Panel;
  GroupBox10.Left := GroupBox4.Left;
  GroupBox10.Width := GroupBox4.Width;
  GroupBox10.Top := GroupBox11.Top + GroupBox11.Height + GROUP_SPACING;
  GroupBox10.Height := GROUP_HEIGHT;
  GroupBox10.Caption := 'ANSI Version Switcher';

  // Create TEdit for ANSI Version Switcher (in GroupBox10)
  edtAnsiVersion := TEdit.Create(GroupBox10);
  edtAnsiVersion.Parent := GroupBox10;
  edtAnsiVersion.Left := LEFT_MARGIN;
  edtAnsiVersion.Top := 30;
  edtAnsiVersion.Width := EDIT_WIDTH;
  edtAnsiVersion.ReadOnly := True;
  edtAnsiVersion.Text := 'Set Shortcut';
  edtAnsiVersion.Color := clWindow;
  edtAnsiVersion.OnClick := ShortcutEditClick;

  CheckShowAnsiSwitchNotification := TCheckBox.Create(GroupBox10);
  CheckShowAnsiSwitchNotification.Parent := GroupBox10;
  CheckShowAnsiSwitchNotification.Left := edtAnsiVersion.Left + edtAnsiVersion.Width + 16;
  CheckShowAnsiSwitchNotification.Top := edtAnsiVersion.Top + 1;
  CheckShowAnsiSwitchNotification.Caption := 'Show notification on switch';
  CheckShowAnsiSwitchNotification.Width := 150;

  KeyboardMode_Panel.Height := GroupBox10.Top + GroupBox10.Height + 16;

  // Load Settings (AFTER controls are created)
  Self.LoadSettings;

  // Register hotkeys for conflict detection
  RegisterHotkeyFeature(@ModeSwitchKey, 'Keyboard Mode Switch', edtModeSwitch);
  RegisterHotkeyFeature(@ToggleOutputModeKey, 'Output Mode Toggle', edtOutputMode);
  RegisterHotkeyFeature(@SpellerLauncherKey, 'Spell Checker Launcher', edtSpellerLauncher);
  RegisterHotkeyFeature(@LayoutSwitchKey, 'Layout Switch', edtLayoutSwitch);
  RegisterHotkeyFeature(@AnsiVersionSwitchKey, 'ANSI Version Switch', edtAnsiVersion);
end;

{ =============================================================================== }

function TfrmOptions.GetListIndex(List: TStrings; SearchS: string): Integer;
var
  I: Integer;
begin
  Result := 0;

  for I := 0 to List.Count - 1 do
  begin
    if LowerCase(List[I]) = LowerCase(SearchS) then
    begin
      Result := I;
      Break;
    end;
  end;

end;

{ =============================================================================== }

procedure TfrmOptions.LabelGlobalHotkeysLinkClick(Sender: TObject);
begin
  CategoryTree.Items[2].Selected := True;
  CategoryTreeClick(nil);
end;

procedure TfrmOptions.LabelHideTimerTimer(Sender: TObject);
begin
  LabelStatus.Visible := False;
end;

{ =============================================================================== }

procedure TfrmOptions.ShortcutEditClick(Sender: TObject);
begin
  // If we were already recording on a different edit box, restore its original state first
  if IsRecordingHotkey and Assigned(RecordingTargetEdit) and (RecordingTargetEdit <> TEdit(Sender)) then
  begin
    RecordingTargetEdit.Text := RecordingOldText;
    RecordingTargetEdit.Color := clWindow;
  end;

  // Keep the existing text, treating placeholder/empty as "None"
  if IsHotkeyNone(TEdit(Sender).Text) then
    RecordingOldText := 'None'
  else
    RecordingOldText := TEdit(Sender).Text;
  IsRecordingHotkey := True;
  RecordingFinalized := False;
  RecordingTargetEdit := TEdit(Sender);

  // Highlight the background to show it is active for recording
  TEdit(Sender).Color := clYellow;
end;

{ =============================================================================== }

procedure TfrmOptions.LoadSettings;
var
  Skins:    TStringList;
  I, Count: Integer;
begin
  // =========================================================
  // General Settings
  if StartWithWindows = 'YES' then
    checkStartUp.Checked := True
  else
    checkStartUp.Checked := False;

  if ShowSplash = 'YES' then
    CheckShowSplash.Checked := True
  else
    CheckShowSplash.Checked := False;

  if DefaultUIMode = 'TOP BAR' then
    optStartupUIMode_TopBar.Checked := True
  else if DefaultUIMode = 'ICON' then
    optStartupUIMode_Tray.Checked := True
  else
    optStartupUIMode_Last.Checked := True;

  if AvroUpdateCheck = 'YES' then
    CheckUpdate.Checked := True
  else
    CheckUpdate.Checked := False;

  if TopBarXButton = 'MINIMIZE' then
    optTopBarXButton_Minimize.Checked := True
  else if TopBarXButton = 'EXIT' then
    optTopBarXButton_Close.Checked := True
  else
    optTopBarXButton_ShowMenu.Checked := True;

  // ===========================================================
  // Interface Settings
  if TopBarTransparent = 'YES' then
  begin
    checkTopBarTransparent.Checked := True;
    Captionl_Transparency.Enabled := True;
    TrackBar_Transparency.Enabled := True;
    Label_Transparency.Enabled := True;
  end
  else
  begin
    checkTopBarTransparent.Checked := False;
    Captionl_Transparency.Enabled := False;
    TrackBar_Transparency.Enabled := False;
    Label_Transparency.Enabled := False;
  end;

  TrackBar_Transparency.Position := StrToInt(TopBarTransparencyLevel);
  { Load Skin Names }
  Skins := TStringList.Create;
  Count := GetFileList(GetAvroDataDir + 'Skin\*.avroskin', Skins);

  { Set skin combo }
  comboSkin.Clear;
  comboSkin.Items.Add('None');

  if Count > 0 then
  begin

    for I := 0 to Count - 1 do
    begin
      Skins[I] := RemoveExtension(Skins[I]);
    end;

    for I := 0 to Skins.Count - 1 do
    begin
      comboSkin.Items.Add(Skins[I]);
    end;
  end;

  if LowerCase(InterfaceSkin) = 'internalskin*' then
    comboSkin.ItemIndex := GetListIndex(comboSkin.Items, 'None')
  else
    comboSkin.ItemIndex := GetListIndex(comboSkin.Items, InterfaceSkin);

  try
    { Show skin preview for selected skin }
    if comboSkin.Items[comboSkin.ItemIndex] = 'None' then
      GetSkinPreviewPicture('internalskin*', SkinPreviewPic.Picture)
    else
      GetSkinPreviewPicture(GetAvroDataDir + 'Skin\' + comboSkin.Items[comboSkin.ItemIndex] + '.avroskin', SkinPreviewPic.Picture);
  except
    on E: Exception do
    begin
      // Nothing
    end;
  end;

  Skins.Free;

  // =======================================================
  // Hotkeys Settings
  if ModeSwitchKey <> '' then
    edtModeSwitch.Text := ModeSwitchKey
  else
    edtModeSwitch.Text := 'None';

  if ToggleOutputModeKey <> '' then
    edtOutputMode.Text := ToggleOutputModeKey
  else
    edtOutputMode.Text := 'None';

  if SpellerLauncherKey <> '' then
    edtSpellerLauncher.Text := SpellerLauncherKey
  else
    edtSpellerLauncher.Text := 'None';

  if LayoutSwitchKey <> '' then
    edtLayoutSwitch.Text := LayoutSwitchKey
  else
    edtLayoutSwitch.Text := 'None';

  CheckShowLayoutSwitchNotification.Checked := (ShowLayoutSwitchNotification = 'YES');

  if AnsiVersionSwitchKey <> '' then
    edtAnsiVersion.Text := AnsiVersionSwitchKey
  else
    edtAnsiVersion.Text := 'None';

  CheckShowAnsiSwitchNotification.Checked := (ShowAnsiSwitchNotification = 'YES');

  // =========================================================
  // Avro Phonetic Options
  if PhoneticAutoCorrect = 'YES' then
    CheckAutoCorrect.Checked := True
  else
    CheckAutoCorrect.Checked := False;

  if ShowPrevWindow = 'YES' then
    CheckShowPrevWindow.Checked := True
  else
    CheckShowPrevWindow.Checked := False;

  if CheckShowPrevWindow.Checked = True then
  begin
    Label_PhoneticTypingMode.Enabled := True;
    optPhoneticMode_Dict.Enabled := True;
    optPhoneticMode_Char.Enabled := True;
    optPhoneticMode_OnlyChar.Enabled := True;
    CheckRememberCandidate.Enabled := True;
    CheckAddNewWords.Enabled := True;
    CheckTabBrowsing.Enabled := True;
  end
  else
  begin
    Label_PhoneticTypingMode.Enabled := False;
    optPhoneticMode_Dict.Enabled := False;
    optPhoneticMode_Char.Enabled := False;
    optPhoneticMode_OnlyChar.Enabled := False;
    CheckRememberCandidate.Enabled := False;
    CheckAddNewWords.Enabled := False;
    CheckTabBrowsing.Enabled := False;
  end;

  if PhoneticMode = 'DICT' then
    optPhoneticMode_Dict.Checked := True
  else if PhoneticMode = 'CHAR' then
    optPhoneticMode_Char.Checked := True
  else if PhoneticMode = 'ONLYCHAR' then
    optPhoneticMode_OnlyChar.Checked := True
  else
    optPhoneticMode_Char.Checked := True;

  if SaveCandidate = 'YES' then
    CheckRememberCandidate.Checked := True
  else
    CheckRememberCandidate.Checked := False;

  if AddToPhoneticDict = 'YES' then
    CheckAddNewWords.Checked := True
  else
    CheckAddNewWords.Checked := False;

  if TabBrowsing = 'YES' then
    CheckTabBrowsing.Checked := True
  else
    CheckTabBrowsing.Checked := False;

  if PipeToDot = 'YES' then
    CheckPipeToDot.Checked := True
  else
    CheckPipeToDot.Checked := False;

  if EnableJoNukta = 'YES' then
    CheckEnableJoNukta.Checked := True
  else
    CheckEnableJoNukta.Checked := False;

  // =========================================================
  // Fixed Layout Options
  if FullOldStyleTyping = 'YES' then
    optTypingStyle_Old.Checked := True
  else
    optTypingStyle_Modern.Checked := True;

  if optTypingStyle_Modern.Checked = True then
  begin
    chkOldReph.Enabled := True;
    chkVowelFormat.Enabled := True;
    CheckChandraPosition.Enabled := True;
  end
  else
  begin
    chkOldReph.Enabled := False;
    chkVowelFormat.Enabled := False;
    CheckChandraPosition.Enabled := False;
  end;

  if OldStyleReph = 'YES' then
    chkOldReph.Checked := True
  else
    chkOldReph.Checked := False;

  if VowelFormating = 'YES' then
    chkVowelFormat.Checked := True
  else
    chkVowelFormat.Checked := False;

  if AutomaticallyFixChandra = 'YES' then
    CheckChandraPosition.Checked := True
  else
    CheckChandraPosition.Checked := False;

  if NumPadBangla = 'YES' then
    CheckNumPadBangla.Checked := True
  else
    CheckNumPadBangla.Checked := False;

  // Global output settings
  if OutputIsBijoy = 'NO' then
  begin
    optOutputUnicode.Checked := True;
    optOutputANSI.Checked := False;
  end
  else
  begin
    optOutputANSI.Checked := True;
    optOutputUnicode.Checked := False;
  end;

  if ShowOutputwarning = 'YES' then
    CheckWarningAnsi.Checked := True
  else
    CheckWarningAnsi.Checked := False;

  if UnicodeToggleShortcut = 'YES' then
    CheckUnicodeToggleShortcut.Checked := True
  else
    CheckUnicodeToggleShortcut.Checked := False;

  if ANSIToggleShortcut = 'YES' then
    CheckANSIToggleShortcut.Checked := True
  else
    CheckANSIToggleShortcut.Checked := False;

  if IgnoreCapsLock = 'YES' then
    CheckIgnoreCapsLockShortcut.Checked := True
  else
    CheckIgnoreCapsLockShortcut.Checked := False;

end;

{ =============================================================================== }

procedure TfrmOptions.optOutputANSIMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if ShowOutputwarning <> 'NO' then
  begin
    CheckCreateForm(TfrmEncodingWarning, frmEncodingWarning, 'frmEncodingWarning');
    frmEncodingWarning.ShowModal;

    if OutputIsBijoy = 'NO' then
    begin
      optOutputUnicode.Checked := True;
      optOutputANSI.Checked := False;
    end
    else
    begin
      optOutputANSI.Checked := True;
      optOutputUnicode.Checked := False;
    end;

    if ShowOutputwarning = 'YES' then
      CheckWarningAnsi.Checked := True
    else
      CheckWarningAnsi.Checked := False;
  end;
end;

{ =============================================================================== }

procedure TfrmOptions.optTypingStyle_ModernClick(Sender: TObject);
begin
  if optTypingStyle_Modern.Checked = True then
  begin
    chkOldReph.Enabled := True;
    chkVowelFormat.Enabled := True;
    CheckChandraPosition.Enabled := True;
  end
  else
  begin
    chkOldReph.Enabled := False;
    chkVowelFormat.Enabled := False;
    CheckChandraPosition.Enabled := False;
  end;
end;

{ =============================================================================== }

procedure TfrmOptions.SaveSettings;
begin
  // =========================================================
  // General Settings
  if checkStartUp.Checked = True then
    StartWithWindows := 'YES'
  else
    StartWithWindows := 'NO';

  if CheckShowSplash.Checked = True then
    ShowSplash := 'YES'
  else
    ShowSplash := 'NO';

  if optStartupUIMode_TopBar.Checked = True then
    DefaultUIMode := 'TOP BAR'
  else if optStartupUIMode_Tray.Checked = True then
    DefaultUIMode := 'ICON'
  else
    DefaultUIMode := 'LASTUI';

  if CheckUpdate.Checked = True then
    AvroUpdateCheck := 'YES'
  else
    AvroUpdateCheck := 'NO';

  if optTopBarXButton_Minimize.Checked = True then
    TopBarXButton := 'MINIMIZE'
  else if optTopBarXButton_Close.Checked = True then
    TopBarXButton := 'EXIT'
  else
    TopBarXButton := 'SHOW MENU';

  // ===========================================================
  // Interface Settings
  if checkTopBarTransparent.Checked = True then
    TopBarTransparent := 'YES'
  else
    TopBarTransparent := 'NO';

  TopBarTransparencyLevel := IntToStr(TrackBar_Transparency.Position);

  if comboSkin.Items[comboSkin.ItemIndex] = 'None' then
    InterfaceSkin := 'internalskin*'
  else
    InterfaceSkin := comboSkin.Items[comboSkin.ItemIndex];



  // =======================================================
  // Hotkeys Settings

  if IsHotkeyNone(edtModeSwitch.Text) then
    ModeSwitchKey := ''
  else
    ModeSwitchKey := edtModeSwitch.Text;

  if IsHotkeyNone(edtOutputMode.Text) then
    ToggleOutputModeKey := ''
  else
    ToggleOutputModeKey := edtOutputMode.Text;

  if IsHotkeyNone(edtSpellerLauncher.Text) then
    SpellerLauncherKey := ''
  else
    SpellerLauncherKey := edtSpellerLauncher.Text;

  if IsHotkeyNone(edtLayoutSwitch.Text) then
    LayoutSwitchKey := ''
  else
    LayoutSwitchKey := UpperCase(edtLayoutSwitch.Text);

  if CheckShowLayoutSwitchNotification.Checked then
    ShowLayoutSwitchNotification := 'YES'
  else
    ShowLayoutSwitchNotification := 'NO';

  if IsHotkeyNone(edtAnsiVersion.Text) then
    AnsiVersionSwitchKey := ''
  else
    AnsiVersionSwitchKey := UpperCase(edtAnsiVersion.Text);

  if CheckShowAnsiSwitchNotification.Checked then
    ShowAnsiSwitchNotification := 'YES'
  else
    ShowAnsiSwitchNotification := 'NO';

  // =========================================================
  // Avro Phonetic Options
  if CheckAutoCorrect.Checked = True then
    PhoneticAutoCorrect := 'YES'
  else
    PhoneticAutoCorrect := 'NO';

  if CheckShowPrevWindow.Checked = True then
    ShowPrevWindow := 'YES'
  else
    ShowPrevWindow := 'NO';

  if optPhoneticMode_Dict.Checked = True then
    PhoneticMode := 'DICT'
  else if optPhoneticMode_Char.Checked = True then
    PhoneticMode := 'CHAR'
  else if optPhoneticMode_OnlyChar.Checked = True then
    PhoneticMode := 'ONLYCHAR'
  else
    PhoneticMode := 'CHAR';

  if CheckRememberCandidate.Checked = True then
    SaveCandidate := 'YES'
  else
    SaveCandidate := 'NO';

  if CheckAddNewWords.Checked = True then
    AddToPhoneticDict := 'YES'
  else
    AddToPhoneticDict := 'NO';

  if CheckTabBrowsing.Checked = True then
    TabBrowsing := 'YES'
  else
    TabBrowsing := 'NO';

  if CheckPipeToDot.Checked = True then
    PipeToDot := 'YES'
  else
    PipeToDot := 'NO';

  if CheckEnableJoNukta.Checked = True then
    EnableJoNukta := 'YES'
  else
    EnableJoNukta := 'NO';

  // =========================================================
  // Fixed Layout Options
  if optTypingStyle_Old.Checked = True then
    FullOldStyleTyping := 'YES'
  else
    FullOldStyleTyping := 'NO';

  if chkOldReph.Checked = True then
    OldStyleReph := 'YES'
  else
    OldStyleReph := 'NO';

  if chkVowelFormat.Checked = True then
    VowelFormating := 'YES'
  else
    VowelFormating := 'NO';

  if CheckChandraPosition.Checked = True then
    AutomaticallyFixChandra := 'YES'
  else
    AutomaticallyFixChandra := 'NO';

  if CheckNumPadBangla.Checked = True then
    NumPadBangla := 'YES'
  else
    NumPadBangla := 'NO';

  // Global output settings
  if optOutputUnicode.Checked = True then
    OutputIsBijoy := 'NO'
  else
    OutputIsBijoy := 'YES';

  if CheckWarningAnsi.Checked = True then
    ShowOutputwarning := 'YES'
  else
    ShowOutputwarning := 'NO';

  if CheckUnicodeToggleShortcut.Checked = True then
    UnicodeToggleShortcut := 'YES'
  else
    UnicodeToggleShortcut := 'NO';

  if CheckANSIToggleShortcut.Checked = True then
    ANSIToggleShortcut := 'YES'
  else
    ANSIToggleShortcut := 'NO';

  if CheckIgnoreCapsLockShortcut.Checked = True then
    IgnoreCapsLock := 'YES'
  else
    IgnoreCapsLock := 'NO';

  uRegistrySettings.SaveSettings;
end;

{ =============================================================================== }

procedure TfrmOptions.TrackBar_TransparencyChange(Sender: TObject);
begin
  Label_Transparency.Caption := IntToStr(TrackBar_Transparency.Position);
end;

{ =============================================================================== }

end.
