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
  ComCtrls,
  ufrmPhoneticOptions;

type
  { Interposer for every TLabel of this dialog. No .dfm edit is needed for it:
    System.Classes.TReader.GetFieldClass resolves a class name found in a .dfm
    from the FORM's own field table first (it walks the form class hierarchy and
    matches by ClassName), so this declaration is what the .dfm's "TLabel"
    objects bind to.

    Why it exists: ApplyStyledScrollFix (Units\uScrollBoxStyleHookFix.pas) makes
    the labels inside ScrollBox1/ScrollBox2 opaque and paints them with
    StyleServices.GetStyleColor(scPanel). That call resolves the colour at the
    moment it is made, and a runtime style switch updates the label's font but
    never its Color property - so the label keeps painting the previous style's
    surface as its own background (black bars on the light style after a
    dark->light switch, pale bars on the dark style after light->dark).
    CM_STYLECHANGED is delivered whenever the active style changes, so
    re-resolving the colour here keeps the labels in step no matter what
    triggered the switch. }
  TLabel = class(StdCtrls.TLabel)
  protected
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  end;

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
    CheckBetaUpdate: TCheckBox;
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
    Label_AppTheme: TLabel;
    cboAppTheme: TComboBox;
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
    CheckShowMenuShortcuts: TCheckBox;
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
    GroupBox12: TGroupBox;
    GroupBox13: TGroupBox;
    Label_SwitchingMode: TLabel;
    cboSwitchingMode: TComboBox;

    edtModeSwitch: TEdit;
    edtOutputMode: TEdit;
    edtSpellerLauncher: TEdit;
    edtConverterLauncher: TEdit;
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
      { The Avro Phonetic page: created in FormCreate and embedded into
        GroupBox3. The dialog's published fields are re-pointed at its
        controls right after creation, so LoadSettings, SaveSettings and
        CheckShowPrevWindowClick keep working without a single change. }
      FPhoneticPage: TfrmPhoneticOptions;
      procedure LoadSettings;
      procedure SaveSettings;
      function GetListIndex(List: TStrings; SearchS: string): Integer;
    public
      { Public declarations }
    protected
      procedure CreateParams(var Params: TCreateParams); override;
      { Runs while VCL switches this dialog to another style: after the style
        engine has rebuilt the form's window and every child window, and after
        CM_STYLECHANGED has been broadcast to the children (TWinControl.WndProc
        broadcasts first and dispatches the message to the form afterwards).
        See the implementation for why the refresh has to sit here. }
      procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  end;

var
  frmOptions: TfrmOptions;

implementation

{$R *.dfm}

uses
  Themes,
  uRegistrySettings,
  uFileFolderHandling,
  SkinLoader,
  uWindowHandlers,
  ufrmAutoCorrect,
  WindowsVersion,
  uForm1,
  u_Admin,
  ufrmEncodingWarning,
  uKeyboardMacro,
  uThemeManager,
  uScrollBoxStyleHookFix;

const
  Show_Window_in_Taskbar = True;

{ =============================================================================== }
{ TLabel interposer (see the type declaration in the interface section). }
{ =============================================================================== }

procedure TLabel.CMStyleChanged(var Message: TMessage);
begin
  { Vcl.StdCtrls.pas keeps csOpaque in step with Transparent in its own
    CM_STYLECHANGED handler, which is private and cannot be reached with
    "inherited" from here; the same two lines are repeated so the label's
    opaque/transparent bookkeeping is unchanged. }
  if not Transparent then
    ControlStyle := ControlStyle + [csOpaque]
  else if StyleServices(Self).Enabled and (seClient in StyleElements) then
    ControlStyle := ControlStyle - [csOpaque];

  { The part that fixes the stale bars: the colour is resolved when it is
    assigned, so a runtime style change has to re-assign it. Only the labels the
    scroll fix made opaque are touched - a transparent label ignores its Color,
    so those are left exactly as before. }
  if (not Transparent) and StyleServices.Available then
    Color := StyleServices.GetStyleColor(scPanel);
end;

{ =============================================================================== }

procedure TfrmOptions.CMStyleChanged(var Message: TMessage);
begin
  { Everything the dialog needs after a live style switch happens here, and
    deliberately not earlier. Timing is what makes this tricky:

      * The style engine repaints a form's windowed children one at a time while
        it rebuilds them, and a common control resolves the colour it fills its
        client area with from the brush its style hook holds (TTreeView asks for
        scTreeView when its window is created). Forcing a repaint *while the new
        style is still being loaded* therefore paints the category tree with the
        previous style's surface - the light column in the middle of an
        otherwise dark dialog - for as long as it takes VCL to get around to
        recreating that window (measured: ~450 ms, see the burst captures).

      * By the time this message is dispatched to the form, that recreation has
        already happened for the whole dialog, so one erased, forced repaint of
        the form and all of its children puts every control in the new style in
        the same pass: the dialog flips over as a whole instead of control by
        control.

    ApplyStyledScrollFix only assigns properties (it makes the labels inside the
    scroll boxes opaque and paints them with the current style's surface
    colour), so it has to run again before the repaint to keep them in step. }
  ApplyStyledScrollFix(ScrollBox2);
  ApplyStyledScrollFix(ScrollBox1);
  if HandleAllocated then
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

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
  BroadcastAppThemeChanged;

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

{ The Help button of this dialog opens the users' community rather than the
  "Customizing Avro Keyboard" PDF: questions about a setting are answered there,
  and in one place, instead of in a document that has to be re-published.

  The help documents are not lost - the application's own Help menu lists the
  PDFs it finds beside the executable (uForm1.RebuildDynamicHelp), and this
  button was the only caller of OpenHelpFile(25). }
procedure TfrmOptions.Button_HelpClick(Sender: TObject);
begin
  Execute_Something('https://t.me/AvroUsersCommunity');
end;

{ =============================================================================== }

procedure TfrmOptions.Button_OKClick(Sender: TObject);
begin
  IsRecordingHotkey := False;
  RecordingFinalized := False;
  RecordingTargetEdit := nil;
  Self.SaveSettings;
  AvroMainForm1.RefreshSettings;
  BroadcastAppThemeChanged;
  Self.Close;
end;

{ =============================================================================== }

procedure TfrmOptions.CategoryTreeClick(Sender: TObject);
var
  Page: TPanel;
  ScrollPos: Integer;
begin
  { This handler is wired to three events in the .dfm (OnEnter, OnClick and
    OnDblClick), so one click on a category runs it more than once: OnEnter
    when the click moves the focus into the tree, then OnClick, then
    OnDblClick on a double click. It is also what puts the first page on
    screen when the dialog opens, because FormCreate leaves every panel
    hidden and the tree takes the focus on activation. }
  if CategoryTree.Selected = nil then
    Exit;

  Page := nil;
  case CategoryTree.Selected.Index of
    0: Page := General_Panel;
    1: Page := Interface_Panel;
    2: Page := KeyboardMode_Panel; { "Global Hotkeys" }
    3: Page := AvroPhonetic_Panel;
    4: Page := FixedLayout_Panel;
    5: Page := GlobalOutput_Panel;
  end;

  { The repeated "jump" when a category is clicked again is this redundant
    second pass: hiding a page that is already on screen and showing it again
    makes its window disappear for a frame and makes the scroll box
    recalculate its range twice, so the page flickers and the position it had
    is lost. When the page asked for is already the visible one there is
    nothing to do. }
  if (Page <> nil) and Page.Visible then
  begin
    TopLabel.Caption := CategoryTree.Selected.Text + ' Settings...';
    Exit;
  end;

  { The scroll position is kept across the switch. Every page sits at the top
    of the same scroll box, and the pages do not have the same height, so
    hiding one and showing another used to move the content under the user
    (the other half of the same jump). }
  ScrollPos := ScrollBox2.VertScrollBar.Position;

  { One visible transition, not one per pass. Six panels are hidden and one is
    shown, and every one of those Visible := calls makes the scroll box paint
    whatever the call just uncovered - so a single click used to be two to four
    full repaints of the settings area in a row, which is the flicker that reads
    as the content jumping. Measured on the reported recording (1111.mp4,
    680x510 @ 60 fps): one category click produced 2-4 repaints of ~9.4% of the
    settings area, spread over 4-6 frames.

    With the box's own redrawing switched off, those intermediate paints are
    dropped (the window simply keeps the picture it already had on screen), the
    visibility and the layout still take effect, and the one repaint below shows
    the page that was actually asked for. WM_SETREDRAW only turns the box's
    paints off; the panels are its children, so nothing inside it can flash
    either. The forced repaint afterwards is what makes the new page appear -
    WM_SETREDRAW back to True does not invalidate anything by itself. }
  SendMessage(ScrollBox2.Handle, WM_SETREDRAW, Ord(False), 0);
  try
    { Hide every settings panel first, then show only the one
      matching the selected tree node. This is robust against
      a node that has no page of its own being left visible
      when other categories are clicked. }
    General_Panel.Visible := False;
    Interface_Panel.Visible := False;
    KeyboardMode_Panel.Visible := False;
    AvroPhonetic_Panel.Visible := False;
    FixedLayout_Panel.Visible := False;
    GlobalOutput_Panel.Visible := False;

    if Page <> nil then
      Page.Visible := True;

    if ScrollBox2.VertScrollBar.Position <> ScrollPos then
      ScrollBox2.VertScrollBar.Position := ScrollPos;

    TopLabel.Caption := CategoryTree.Selected.Text + ' Settings...';
  finally
    SendMessage(ScrollBox2.Handle, WM_SETREDRAW, Ord(True), 0);
  end;

  { The one repaint the switch is allowed to make. RDW_UPDATENOW so it is done
    before this returns: a click must never leave the box on screen in a state
    that is neither the old page nor the new one. }
  RedrawWindow(ScrollBox2.Handle, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
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
var
  I: Integer;
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

  // =======================================================
  // Keyboard mode switching scope (runtime-created, Global output page)
  // Right under the output-mode radios: the scope of the Bangla /
  // system-default state - one state for the whole desktop, or the per-window
  // memory this build has always had.  The same two choices are in each Tools
  // menu (the tray's and the Top Bar's); all three read and write the one
  // SwitchingMode setting.
  //
  // This control is created after the form has loaded and scaled its own
  // controls (this is a 144-DPI design and the form is 96 DPI here), so its
  // geometry has to be measured from the controls that WERE scaled: the top
  // from the ANSI radio, and the settings below it are moved by the group's
  // own height rather than by a fixed .dfm value.  Fixed Top values in the
  // .dfm put this group on top of those settings once already.
  GroupBox13 := TGroupBox.Create(GlobalOutput_Panel);
  GroupBox13.Parent := GlobalOutput_Panel;
  GroupBox13.Left := 24;
  GroupBox13.Top := optOutputANSI.Top + optOutputANSI.Height + GROUP_SPACING;
  GroupBox13.Width := GlobalOutput_Panel.Width - 60;
  GroupBox13.Height := GROUP_HEIGHT;
  GroupBox13.Caption := 'Keyboard Mode Switching';

  Label_SwitchingMode := TLabel.Create(GroupBox13);
  Label_SwitchingMode.Parent := GroupBox13;
  Label_SwitchingMode.Left := LEFT_MARGIN;
  Label_SwitchingMode.Top := 16;
  Label_SwitchingMode.Caption := 'Switching Mode:';

  cboSwitchingMode := TComboBox.Create(GroupBox13);
  cboSwitchingMode.Parent := GroupBox13;
  cboSwitchingMode.Left := LEFT_MARGIN;
  cboSwitchingMode.Top := 35;
  cboSwitchingMode.Width := 220;
  cboSwitchingMode.Style := csDropDownList;
  cboSwitchingMode.Items.Add('Global (All Windows)');
  cboSwitchingMode.Items.Add('Per Application/Window');

  { Nothing on the page may end up under the new group, whatever its height
    turns out to be: the settings below it move down by exactly that height. }
  I := GroupBox13.Height + GROUP_SPACING;
  CheckShowMenuShortcuts.Top := CheckShowMenuShortcuts.Top + I;
  CheckWarningAnsi.Top := CheckWarningAnsi.Top + I;
  CheckUnicodeToggleShortcut.Top := CheckUnicodeToggleShortcut.Top + I;
  CheckANSIToggleShortcut.Top := CheckANSIToggleShortcut.Top + I;
  CheckIgnoreCapsLockShortcut.Top := CheckIgnoreCapsLockShortcut.Top + I;
  Label20.Top := Label20.Top + I;
  LabelGlobalHotkeysLink.Top := LabelGlobalHotkeysLink.Top + I;
  GlobalOutput_Panel.Height := GlobalOutput_Panel.Height + I;

  { The Avro Phonetic page lives in its own form (ufrmPhoneticOptions). Its
    check boxes and radio buttons used to carry StyleElements = [] so the style
    engine left their painting to Windows (TStyleHook.AcceptMessage refuses
    WM_PAINT / WM_ERASEBKGND / WM_CTLCOLOR* once seClient is gone) - that was
    defence in depth against the black-bar defect, not the fix itself; the paint
    path that produced the black bars and the white blocks is repaired in
    Units\uScrollBoxStyleHookFix.pas, and the opt-out has since been removed so
    those controls now paint in the active style like every other check box and
    radio button in the program. The form is embedded into GroupBox3 over the
    group box's client area (alClient), which is the exact spot the controls used
    to occupy, so no coordinate changes, and every reference the dialog keeps to
    a moved control is re-pointed below. }
  FPhoneticPage := TfrmPhoneticOptions.Create(Self);
  FPhoneticPage.Parent := GroupBox3;
  FPhoneticPage.Align := alClient;
  { TCustomForm.InitializeNewForm starts every form with Visible = False
    (Vcl.Forms.pas) - fine for a top-level window that calls Show later, but
    an embedded form would otherwise stay hidden forever: its group box
    frame draws while the whole page inside it stays blank. The property
    only turns this form's own window on; hiding AvroPhonetic_Panel still
    hides the page visually, exactly like every other control inside it. }
  FPhoneticPage.Visible := True;
  FPhoneticPage.ApplyTheme;

  { Re-point all eleven moved controls. The five labels come across as
    StdCtrls.TLabel (the new unit cannot see this unit's TLabel interposer -
    that would be a circular reference), so they need the explicit cast;
    the instance itself is untouched by a cast, it only silences the type
    mismatch. }
  Label_PhoneticTypingMode := TLabel(FPhoneticPage.Label_PhoneticTypingMode);
  Label1 := TLabel(FPhoneticPage.Label1);
  Label4 := TLabel(FPhoneticPage.Label4);
  Label9 := TLabel(FPhoneticPage.Label9);
  Label12 := TLabel(FPhoneticPage.Label12);
  CheckShowPrevWindow := FPhoneticPage.CheckShowPrevWindow;
  optPhoneticMode_Dict := FPhoneticPage.optPhoneticMode_Dict;
  optPhoneticMode_Char := FPhoneticPage.optPhoneticMode_Char;
  optPhoneticMode_OnlyChar := FPhoneticPage.optPhoneticMode_OnlyChar;
  CheckRememberCandidate := FPhoneticPage.CheckRememberCandidate;
  CheckTabBrowsing := FPhoneticPage.CheckTabBrowsing;

  { The OnClick entry left the .dfm with the moved control (the new form has
    no event handlers - a leftover entry would raise EResNotFound while
    streaming and silently kill this constructor), so the dialog wires it
    back up now that the field points at the moved check box. }
  CheckShowPrevWindow.OnClick := CheckShowPrevWindowClick;

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
  // Text Converter Launcher Hotkey UI (runtime-created)
  GroupBox12 := TGroupBox.Create(KeyboardMode_Panel);
  GroupBox12.Parent := KeyboardMode_Panel;
  GroupBox12.Left := GroupBox4.Left;
  GroupBox12.Width := GroupBox4.Width;
  GroupBox12.Top := GroupBox9.Top + GroupBox9.Height + GROUP_SPACING;
  GroupBox12.Height := GROUP_HEIGHT;
  GroupBox12.Caption := 'Text Converter Launcher';

  // Create TEdit for Text Converter Launcher (in GroupBox12)
  edtConverterLauncher := TEdit.Create(GroupBox12);
  edtConverterLauncher.Parent := GroupBox12;
  edtConverterLauncher.Left := LEFT_MARGIN;
  edtConverterLauncher.Top := 35;
  edtConverterLauncher.Width := EDIT_WIDTH;
  edtConverterLauncher.ReadOnly := True;
  edtConverterLauncher.Text := 'Set Shortcut';
  edtConverterLauncher.Color := clWindow;
  edtConverterLauncher.OnClick := ShortcutEditClick;

  // =======================================================
  // Layout Switcher Hotkey UI (runtime-created)
  GroupBox11 := TGroupBox.Create(KeyboardMode_Panel);
  GroupBox11.Parent := KeyboardMode_Panel;
  GroupBox11.Left := GroupBox4.Left;
  GroupBox11.Width := GroupBox4.Width;
  GroupBox11.Top := GroupBox12.Top + GroupBox12.Height + GROUP_SPACING;
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
  // ANSI Encoding Switcher Hotkey UI (runtime-created)
  GroupBox10 := TGroupBox.Create(KeyboardMode_Panel);
  GroupBox10.Parent := KeyboardMode_Panel;
  GroupBox10.Left := GroupBox4.Left;
  GroupBox10.Width := GroupBox4.Width;
  GroupBox10.Top := GroupBox11.Top + GroupBox11.Height + GROUP_SPACING;
  GroupBox10.Height := GROUP_HEIGHT;
  GroupBox10.Caption := 'ANSI Encoding Switcher';

  // Create TEdit for ANSI Encoding Switcher (in GroupBox10)
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

  // =======================================================
  // Theme selector (Interface Settings page, control created in the DFM).
  // Item 0 is "Default" (the plain native look - what every fresh install
  // starts with), item 1 is "System" (follow Windows), and every item after
  // that is the caption of a VCL style this build embeds (Project Options ->
  // Appearance -> Custom Styles), so enabling a style in the IDE is all it
  // takes for it to show up here. The two built-ins are listed as what they are,
  // "Light Theme" and "Dark Theme", since their style names say nothing about
  // which is which (AppStyleCaption).
  GetAppThemeStyleNames(cboAppTheme.Items);
  for I := 0 to cboAppTheme.Items.Count - 1 do
    cboAppTheme.Items[I] := AppStyleCaption(cboAppTheme.Items[I]);
  cboAppTheme.Items.Insert(0, AppThemeModeCaption(atmSystemDefault));
  cboAppTheme.Items.Insert(0, AppThemeModeCaption(atmWindows));

  // Load Settings (AFTER controls are created)
  Self.LoadSettings;

  // Register hotkeys for conflict detection
  RegisterHotkeyFeature(@ModeSwitchKey, 'Keyboard Mode Switch', edtModeSwitch);
  RegisterHotkeyFeature(@ToggleOutputModeKey, 'Output Mode Toggle', edtOutputMode);
  RegisterHotkeyFeature(@SpellerLauncherKey, 'Spell Checker Launcher', edtSpellerLauncher);
  RegisterHotkeyFeature(@ConverterLauncherKey, 'Text Converter Launcher', edtConverterLauncher);
  RegisterHotkeyFeature(@LayoutSwitchKey, 'Layout Switch', edtLayoutSwitch);
  RegisterHotkeyFeature(@AnsiVersionSwitchKey, 'ANSI Version Switch', edtAnsiVersion);

  // =======================================================
  // VCL-style scroll hygiene for both scrollboxes; the smearing fix itself is
  // the TScrollBox style hook in Units\uScrollBoxStyleHookFix.pas. Must run
  // after every control above is created - the label walk only sees controls
  // that already exist.
  ApplyStyledScrollFix(ScrollBox2);
  ApplyStyledScrollFix(ScrollBox1);
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

  if CheckBetaUpdates = 'YES' then
    CheckBetaUpdate.Checked := True
  else
    CheckBetaUpdate.Checked := False;

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

  // Application theme: item 0 is "Default" (plain native look), item 1 is
  // "System" (follow Windows), every other item is a style caption - "Light
  // Theme" / "Dark Theme" for the two built-ins, its own name for anything else
  // (AppStyleCaption). LIGHT / DARK are mapped to their built-in style so a
  // setting written before this list became dynamic still lands on the right row;
  // GetListIndex answers 0 for a style that is no longer embedded, which is
  // exactly the fallback we want (the plain Windows look).
  if (AppThemeMode = '') or SameText(AppThemeMode, APP_THEME_SETTING_WINDOWS) then
    cboAppTheme.ItemIndex := 0
  else if SameText(AppThemeMode, APP_THEME_SETTING_SYSTEM) then
    cboAppTheme.ItemIndex := 1
  else if SameText(AppThemeMode, APP_THEME_SETTING_LIGHT) then
    cboAppTheme.ItemIndex := GetListIndex(cboAppTheme.Items, AppStyleCaption(APP_STYLE_LIGHT))
  else if SameText(AppThemeMode, APP_THEME_SETTING_DARK) then
    cboAppTheme.ItemIndex := GetListIndex(cboAppTheme.Items, AppStyleCaption(APP_STYLE_DARK))
  else
    // An embedded style name - AppStyleCaption gives it its hinted caption when
    // it is one of the two built-ins, and the name itself otherwise.
    cboAppTheme.ItemIndex := GetListIndex(cboAppTheme.Items, AppStyleCaption(AppThemeMode));

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

  if ConverterLauncherKey <> '' then
    edtConverterLauncher.Text := ConverterLauncherKey
  else
    edtConverterLauncher.Text := 'None';

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

  { Item 0 is Global (All Windows), item 1 is Per Application/Window; anything
    that is not GLOBAL is the per-window behaviour, exactly as the settings
    unit normalises it. }
  if SwitchingMode = SWITCHING_MODE_GLOBAL then
    cboSwitchingMode.ItemIndex := 0
  else
    cboSwitchingMode.ItemIndex := 1;

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

  if ShowShortcutKeysOnMenu = 'YES' then
    CheckShowMenuShortcuts.Checked := True
  else
    CheckShowMenuShortcuts.Checked := False;

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

  if CheckBetaUpdate.Checked = True then
    CheckBetaUpdates := 'YES'
  else
    CheckBetaUpdates := 'NO';

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

  if IsHotkeyNone(edtConverterLauncher.Text) then
    ConverterLauncherKey := ''
  else
    ConverterLauncherKey := UpperCase(edtConverterLauncher.Text);

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

  if cboSwitchingMode.ItemIndex = 0 then
    SwitchingMode := SWITCHING_MODE_GLOBAL
  else
    SwitchingMode := SWITCHING_MODE_WINDOW;

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

  if CheckShowMenuShortcuts.Checked = True then
    ShowShortcutKeysOnMenu := 'YES'
  else
    ShowShortcutKeysOnMenu := 'NO';

  // Application theme (Interface Settings). Item 0 ("Default") is the plain
  // native look and the application default; item 1 ("System") follows
  // Windows; every other item is a style caption, which AppThemeSettingFromCaption
  // turns into the setting: "Light Theme" / "Dark Theme" as LIGHT / DARK, so a
  // build that does not know about the dynamic list still reads them back
  // correctly, and any other style under its own name. A missing selection means
  // "Default".
  // AvroMainForm1.RefreshSettings then applies it to the whole application.
  if cboAppTheme.ItemIndex <= 0 then
    AppThemeMode := APP_THEME_SETTING_WINDOWS
  else if cboAppTheme.ItemIndex = 1 then
    AppThemeMode := APP_THEME_SETTING_SYSTEM
  else
    AppThemeMode := AppThemeSettingFromCaption(cboAppTheme.Items[cboAppTheme.ItemIndex]);

  uRegistrySettings.SaveSettings;
end;

{ =============================================================================== }

procedure TfrmOptions.TrackBar_TransparencyChange(Sender: TObject);
begin
  Label_Transparency.Caption := IntToStr(TrackBar_Transparency.Position);
end;

{ =============================================================================== }

end.
