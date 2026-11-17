{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit ufrmAbout;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  StdCtrls,
  ComCtrls,
  ExtCtrls;

type
  TCreditsViewer = class(TCustomControl)
  private
    FLines: TStringList;
    FScrollPosition: Integer;
    FContentHeight: Integer;
    procedure SetLines(ALines: TStrings);
    procedure SetScrollPosition(AValue: Integer);
    procedure UpdateScrollInfo;
    function IsHeading(AIndex: Integer): Boolean;
    function LineHeight(AIndex: Integer): Integer;
    procedure WMMouseWheel(var Message: TMessage); message WM_MOUSEWHEEL;
    procedure WMVScroll(var Message: TMessage); message WM_VSCROLL;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Lines: TStrings write SetLines;
    property ScrollPosition: Integer read FScrollPosition write SetScrollPosition;
  end;

  TfrmAbout = class(TForm)
    ShapeFooter: TShape;
    ShapeTopLine: TShape;
    Shape1: TShape;
    PanelSidebar: TPanel;
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
    LabelVersion: TLabel;
    LabelEngineBuild: TLabel;
    LabelBrandTagline: TLabel;
    Label4: TLabel;
    LabelFooterSeparator: TLabel;
    Label5: TLabel;
    Label_License: TLabel;
    Label8: TLabel;
    Label_OmicronLab: TLabel;
    CreditsPanel: TPanel;
    lblText: TLabel;
    Credit: TMemo;
    CommunityCredit: TMemo;
    Label_Update: TLabel;
    MemoLicense: TRichEdit;
    LabelViewCredit: TLabel;
    Image2: TImage;
    Label3: TLabel;
    EditDataDirectory: TEdit;
    Label_Help: TLabel;
    Label6: TLabel;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure FormPaint(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Label_OmicronLabClick(Sender: TObject);
    procedure LayoutFooter;
    procedure Label_LicenseClick(Sender: TObject);
    procedure Label_UpdateClick(Sender: TObject);
    procedure LabelViewCreditClick(Sender: TObject);
    procedure EditDataDirectoryClick(Sender: TObject);
    procedure Label_HelpClick(Sender: TObject);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  private
    FActiveCreditTab: Integer;
    FCreditsViewer: TCreditsViewer;
    FCreditsScrollPositions: array[0..1] of Integer;
    FThemeTimer: TTimer;
    procedure ApplyAboutTheme;
    procedure ApplyNativeTheme;
    procedure FormatRichEdit(ARichEdit: TRichEdit);
    function CreditTabBounds(AIndex: Integer): TRect;
    procedure SelectCreditTab(AIndex: Integer);
    procedure ThemeTimerTick(Sender: TObject);
    procedure LoadActiveCredits;
    function ActiveCreditLines: TStrings;
  end;

var
  frmAbout: TfrmAbout;

implementation

{$R *.dfm}

uses
  Math,
  Winapi.UxTheme,
  uWindowHandlers,
  uFileFolderHandling,
  clsFileVersion,
  uForm1,
  uThemeManager,
  Vcl.Imaging.pngimage;

constructor TCreditsViewer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := False;
  ParentColor := False;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  FLines := TStringList.Create;
end;

destructor TCreditsViewer.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

procedure TCreditsViewer.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.Style := Params.Style or WS_VSCROLL;
end;

procedure TCreditsViewer.SetLines(ALines: TStrings);
var
  I: Integer;
  J: Integer;
  LineText: string;
  IsDivider: Boolean;
begin
  FLines.BeginUpdate;
  try
    FLines.Clear;
    for I := 0 to ALines.Count - 1 do
    begin
      LineText := Trim(ALines[I]);
      if LineText = '' then
      begin
        if (FLines.Count > 0) and (FLines[FLines.Count - 1] <> '') then
          FLines.Add('');
        Continue;
      end;

      IsDivider := True;
      for J := 1 to Length(LineText) do
        if LineText[J] <> '_' then
        begin
          IsDivider := False;
          Break;
        end;
      if not IsDivider then
        FLines.Add(ALines[I]);
    end;
    if (FLines.Count > 0) and (FLines[FLines.Count - 1] = '') then
      FLines.Delete(FLines.Count - 1);
  finally
    FLines.EndUpdate;
  end;
  UpdateScrollInfo;
  Invalidate;
end;

procedure TCreditsViewer.SetScrollPosition(AValue: Integer);
var
  MaxScrollPosition: Integer;
begin
  MaxScrollPosition := FContentHeight - ClientHeight;
  if MaxScrollPosition < 0 then
    MaxScrollPosition := 0;
  if AValue < 0 then
    AValue := 0
  else if AValue > MaxScrollPosition then
    AValue := MaxScrollPosition;

  if FScrollPosition <> AValue then
  begin
    FScrollPosition := AValue;
    UpdateScrollInfo;
    Invalidate;
  end;
end;

procedure TCreditsViewer.UpdateScrollInfo;
var
  I: Integer;
  ScrollInfo: TScrollInfo;
begin
  if not Assigned(FLines) then
    Exit;

  HandleNeeded;
  FContentHeight := 8;
  for I := 0 to FLines.Count - 1 do
    Inc(FContentHeight, LineHeight(I));
  FScrollPosition := EnsureRange(FScrollPosition, 0,
    Max(0, FContentHeight - ClientHeight));

  ScrollInfo.cbSize := SizeOf(ScrollInfo);
  ScrollInfo.fMask := SIF_ALL;
  ScrollInfo.nMin := 0;
  ScrollInfo.nMax := Max(0, FContentHeight - 1);
  ScrollInfo.nPage := ClientHeight;
  ScrollInfo.nPos := FScrollPosition;
  SetScrollInfo(Handle, SB_VERT, ScrollInfo, True);
end;

function TCreditsViewer.IsHeading(AIndex: Integer): Boolean;
var
  LineText: string;
begin
  LineText := Trim(FLines[AIndex]);
  Result := (AIndex = 0) or
    ((LineText <> '') and (LineText[Length(LineText)] = ':'));
end;

function TCreditsViewer.LineHeight(AIndex: Integer): Integer;
var
  LineText: string;
  TextRect: TRect;
  TextWidth: Integer;
begin
  Canvas.Font.Assign(Font);
  Canvas.Font.Style := [];
  LineText := FLines[AIndex];
  if Trim(LineText) = '' then
  begin
    Result := Canvas.TextHeight('Ag') div 2 + 2;
    Exit;
  end;

  if IsHeading(AIndex) then
  begin
    Canvas.Font.Style := [fsBold];
    if AIndex = 0 then
      Canvas.Font.Size := Font.Size + 2;
  end;

  TextWidth := ClientWidth - 24;
  if TextWidth < 1 then
    TextWidth := 1;
  TextRect := Rect(0, 0, TextWidth, 0);
  DrawText(Canvas.Handle, PChar(LineText), Length(LineText), TextRect,
    DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
  Result := TextRect.Bottom + 4;
end;

procedure TCreditsViewer.Paint;
var
  I: Integer;
  Y: Integer;
  H: Integer;
  LineText: string;
  TextRect: TRect;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  Y := 8 - FScrollPosition;

  for I := 0 to FLines.Count - 1 do
  begin
    H := LineHeight(I);
    LineText := FLines[I];
    if (Trim(LineText) <> '') and (Y + H > 0) and (Y < ClientHeight) then
    begin
      Canvas.Font.Assign(Font);
      Canvas.Font.Style := [];
      if IsHeading(I) then
      begin
        Canvas.Font.Style := [fsBold];
        if I = 0 then
          Canvas.Font.Size := Font.Size + 2;
      end;
      Canvas.Font.Color := Font.Color;
      TextRect := Rect(12, Y, ClientWidth - 12, Y + H - 4);
      DrawText(Canvas.Handle, PChar(LineText), Length(LineText), TextRect,
        DT_LEFT or DT_TOP or DT_WORDBREAK or DT_NOPREFIX);
    end;
    Inc(Y, H);
  end;
end;

procedure TCreditsViewer.Resize;
begin
  inherited Resize;
  UpdateScrollInfo;
end;

procedure TCreditsViewer.WMMouseWheel(var Message: TMessage);
var
  WheelDelta: SmallInt;
  ScrollStep: Integer;
begin
  WheelDelta := SmallInt((Message.WParam shr 16) and $FFFF);
  ScrollStep := (Canvas.TextHeight('Ag') + 4) * 3;
  ScrollPosition := FScrollPosition -
    (WheelDelta div WHEEL_DELTA) * ScrollStep;
  Message.Result := 1;
end;

procedure TCreditsViewer.WMVScroll(var Message: TMessage);
var
  ScrollInfo: TScrollInfo;
  ScrollCode: Integer;
  ScrollStep: Integer;
begin
  ScrollCode := Integer(Message.WParam and $FFFF);
  ScrollStep := Canvas.TextHeight('Ag') + 4;
  case ScrollCode of
    SB_LINEUP:
      ScrollPosition := FScrollPosition - ScrollStep;
    SB_LINEDOWN:
      ScrollPosition := FScrollPosition + ScrollStep;
    SB_PAGEUP:
      ScrollPosition := FScrollPosition - ClientHeight;
    SB_PAGEDOWN:
      ScrollPosition := FScrollPosition + ClientHeight;
    SB_TOP:
      ScrollPosition := 0;
    SB_BOTTOM:
      ScrollPosition := FContentHeight;
    SB_THUMBTRACK, SB_THUMBPOSITION:
      begin
        ScrollInfo.cbSize := SizeOf(ScrollInfo);
        ScrollInfo.fMask := SIF_TRACKPOS;
        if GetScrollInfo(Handle, SB_VERT, ScrollInfo) then
          ScrollPosition := ScrollInfo.nTrackPos;
      end;
  end;
  Message.Result := 0;
end;

procedure TfrmAbout.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  Params.ExStyle := Params.ExStyle or WS_EX_APPWINDOW and not WS_EX_TOOLWINDOW;
  Params.WndParent := GetDesktopWindow;
end;

procedure TfrmAbout.EditDataDirectoryClick(Sender: TObject);
begin
  EditDataDirectory.SelectAll;
end;

procedure TfrmAbout.CMStyleChanged(var Message: TMessage);
begin
  ApplyAboutTheme;
  if HandleAllocated then
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_FRAME or RDW_ALLCHILDREN or
      RDW_UPDATENOW);
  if Assigned(FThemeTimer) then
  begin
    FThemeTimer.Enabled := False;
    FThemeTimer.Enabled := True;
  end;
end;

procedure TfrmAbout.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
  frmAbout := nil;
end;

procedure TfrmAbout.ApplyAboutTheme;
var
  Palette: TAppThemePalette;
  SurfaceColor: TColor;
  FooterColor: TColor;
  MutedTextColor: TColor;
begin
  Palette := CurrentPalette;
  if Palette.IsDark then
  begin
    SurfaceColor := RGB(41, 41, 41);
    FooterColor := RGB(25, 25, 25);
    MutedTextColor := RGB(180, 180, 180);
  end
  else
  begin
    SurfaceColor := RGB(245, 245, 245);
    FooterColor := RGB(245, 245, 245);
    MutedTextColor := RGB(90, 90, 90);
  end;

  Color := Palette.Background;
  Font.Color := Palette.Text;
  PanelSidebar.Color := Palette.Background;
  ShapeFooter.Brush.Color := FooterColor;
  if Palette.IsDark then
    ShapeFooter.Pen.Color := RGB(35, 35, 35)
  else
    ShapeFooter.Pen.Color := RGB(225, 225, 225);
  if Palette.IsDark then
  begin
    ShapeTopLine.Brush.Color := RGB(54, 54, 54);
    ShapeTopLine.Pen.Color := RGB(54, 54, 54);
  end
  else
  begin
    ShapeTopLine.Brush.Color := RGB(200, 200, 200);
    ShapeTopLine.Pen.Color := RGB(200, 200, 200);
  end;
  // Labels drawn over the sidebar artwork keep fixed light colours: the
  // artwork is dark in both themes, so palette text colours would vanish on it.
  Label1.Font.Color := clWhite;
  Label2.Font.Color := clWhite;
  LabelVersion.Font.Color := clWhite;
  LabelEngineBuild.Font.Color := RGB(210, 210, 210);
  LabelBrandTagline.Font.Color := clWhite;
  Label4.Font.Color := MutedTextColor;
  LabelFooterSeparator.Font.Color := MutedTextColor;
  Label5.Font.Color := MutedTextColor;
  Label8.Font.Color := MutedTextColor;
  Label3.Font.Color := MutedTextColor;
  Label6.Font.Color := MutedTextColor;

  Label_License.Font.Color := RGB(141, 70, 255);
  Label_OmicronLab.Font.Color := RGB(141, 70, 255);
  Label_Update.Font.Color := RGB(141, 70, 255);
  Label_Help.Font.Color := RGB(141, 70, 255);
  LabelViewCredit.Font.Color := RGB(141, 70, 255);

  CreditsPanel.Color := SurfaceColor;
  if Assigned(FCreditsViewer) then
  begin
    FCreditsViewer.Color := SurfaceColor;
    FCreditsViewer.Font.Color := Palette.Text;
    FCreditsViewer.Invalidate;
  end;
  MemoLicense.Color := SurfaceColor;
  MemoLicense.Font.Color := Palette.Text;
  EditDataDirectory.Color := SurfaceColor;
  EditDataDirectory.Font.Color := Palette.Text;
  ApplyNativeTheme;

  FormatRichEdit(MemoLicense);
end;

procedure TfrmAbout.ApplyNativeTheme;
var
  IsDark: Boolean;
  IsActive: Boolean;
begin
  IsDark := CurrentPalette.IsDark;
  if HandleAllocated then
  begin
    ApplyImmersiveDarkMode(Handle, IsDark);
    SetWindowPos(Handle, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or
      SWP_FRAMECHANGED);
    IsActive := GetForegroundWindow = Handle;
    SendMessage(Handle, WM_NCACTIVATE, WPARAM(Ord(not IsActive)), 0);
    SendMessage(Handle, WM_NCACTIVATE, WPARAM(Ord(IsActive)), 0);
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_FRAME or RDW_ALLCHILDREN or
      RDW_UPDATENOW);
  end;

  if IsDark then
  begin
    SetWindowTheme(MemoLicense.Handle, 'DarkMode_Explorer', nil);
    SetWindowTheme(EditDataDirectory.Handle, 'DarkMode_Explorer', nil);
    if Assigned(FCreditsViewer) then
      SetWindowTheme(FCreditsViewer.Handle, 'DarkMode_Explorer', nil);
  end
  else
  begin
    SetWindowTheme(MemoLicense.Handle, nil, nil);
    SetWindowTheme(EditDataDirectory.Handle, nil, nil);
    if Assigned(FCreditsViewer) then
      SetWindowTheme(FCreditsViewer.Handle, nil, nil);
  end;

  if Assigned(FCreditsViewer) then
    FCreditsViewer.Invalidate;
end;

procedure TfrmAbout.FormCreate(Sender: TObject);
var
  Version: TFileVersion;
  IconStream: TResourceStream;
  ArtworkStream: TResourceStream;
  Artwork: TPngImage;
begin
  StyleElements := [];

  IconStream := TResourceStream.Create(HInstance, 'AVRO_ABOUT_ICON',
    RT_RCDATA);
  try
    Icon.LoadFromStream(IconStream);
  finally
    IconStream.Free;
  end;

  // Keep the header links and footer credits inside the client area
  Label_Help.Left := ClientWidth - 10 - Label_Help.Width;
  Label6.Left := Label_Help.Left - 10;
  Label_Update.Left := Label6.Left - Label_Update.Width - 8;
  LayoutFooter;
  Image1.Parent := PanelSidebar;
  Image1.Align := alClient;
  Image1.Stretch := True;
  Image1.Proportional := True;
  Image1.Center := True;
  Shape1.Parent := PanelSidebar;
  Label1.Parent := PanelSidebar;
  Label2.Parent := PanelSidebar;
  LabelVersion.Parent := PanelSidebar;
  LabelEngineBuild.Parent := PanelSidebar;
  LabelBrandTagline.Parent := PanelSidebar;
  // The sidebar credits sit on the artwork, not on a themed surface: a VCL
  // style hook would repaint their font with the style's own colour (black on
  // the light style) and hide them, so opt these labels out of styling.
  Label1.StyleElements := [];
  Label2.StyleElements := [];
  LabelVersion.StyleElements := [];
  LabelEngineBuild.StyleElements := [];
  LabelBrandTagline.StyleElements := [];
  Label2.BringToFront;
  LabelVersion.BringToFront;
  ShapeTopLine.BringToFront;
  ArtworkStream := TResourceStream.Create(HInstance, 'AVRO_ABOUT_SIDEBAR',
    RT_RCDATA);
  Artwork := TPngImage.Create;
  try
    Artwork.LoadFromStream(ArtworkStream);
    Image1.Picture.Assign(Artwork);
  finally
    Artwork.Free;
    ArtworkStream.Free;
  end;

  FCreditsViewer := TCreditsViewer.Create(Self);
  FCreditsViewer.Parent := CreditsPanel;
  FCreditsViewer.Align := alClient;
  FCreditsViewer.StyleElements := [];
  MemoLicense.StyleElements := [];
  MemoLicense.Font.Name := 'Segoe UI';
  MemoLicense.Font.Size := 9;

  FActiveCreditTab := 0;
  FCreditsScrollPositions[0] := 0;
  FCreditsScrollPositions[1] := 0;
  LoadActiveCredits;
  FormatRichEdit(MemoLicense);

  Version := TFileVersion.Create;
  try
    LabelVersion.Caption := 'Version ' + Version.AsString
      {$IFDEF BetaVersion} + ' BETA'{$ENDIF}
      {$IFDEF PortableOn} + ' (Portable)'{$ENDIF};
    LabelEngineBuild.Caption := 'Engine build ' + Version.AsString +
      '  •  Unicode';
  finally
    Version.Free;
  end;

  EditDataDirectory.Text := GetAvroDataDir;
  ApplyAboutTheme;

  FThemeTimer := TTimer.Create(Self);
  FThemeTimer.Interval := 80;
  FThemeTimer.OnTimer := ThemeTimerTick;
  FThemeTimer.Enabled := True;
end;

procedure TfrmAbout.ThemeTimerTick(Sender: TObject);
begin
  FThemeTimer.Enabled := False;
  ApplyNativeTheme;
end;

function TfrmAbout.CreditTabBounds(AIndex: Integer): TRect;
var
  SX, SY: Double;
  IconLeft, TextLeft: Integer;
  Caption: string;
begin
  SX := ClientWidth / 766;
  SY := ClientHeight / 490;
  if AIndex = 0 then
  begin
    IconLeft := 247;
    TextLeft := 266;
    Caption := 'Avro Official';
  end
  else
  begin
    IconLeft := 372;
    TextLeft := 390;
    Caption := 'Avro Community';
  end;
  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;
  Canvas.Font.Style := [fsBold];
  Result := Rect(
    Round((IconLeft - 8) * SX),
    0,
    Round(TextLeft * SX) + Canvas.TextWidth(Caption) + Round(8 * SX),
    Round(32 * SY));
end;

procedure TfrmAbout.FormMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  TabBounds: TRect;
begin
  if Button <> mbLeft then
    Exit;
  TabBounds := CreditTabBounds(0);
  if (X >= TabBounds.Left) and (X < TabBounds.Right) and
    (Y >= TabBounds.Top) and (Y < TabBounds.Bottom) then
    SelectCreditTab(0)
  else
  begin
    TabBounds := CreditTabBounds(1);
    if (X >= TabBounds.Left) and (X < TabBounds.Right) and
      (Y >= TabBounds.Top) and (Y < TabBounds.Bottom) then
      SelectCreditTab(1);
  end;
end;

procedure TfrmAbout.SelectCreditTab(AIndex: Integer);
begin
  if FActiveCreditTab <> AIndex then
  begin
    FCreditsScrollPositions[FActiveCreditTab] :=
      FCreditsViewer.ScrollPosition;
    FActiveCreditTab := AIndex;
    LoadActiveCredits;
  end;
  Invalidate;
end;

procedure TfrmAbout.FormPaint(Sender: TObject);
var
  SX, SY: Double;
  ActiveTab: Integer;
  ActiveText: TColor;
  MutedText: TColor;
  TabBack: TColor;
  TabUnderlineTop: Integer;
  TabBounds: TRect;

  function XV(AValue: Integer): Integer;
  begin
    Result := Round(AValue * SX);
  end;

  function YV(AValue: Integer): Integer;
  begin
    Result := Round(AValue * SY);
  end;

  procedure DrawAtom(AX, AY: Integer);
  begin
    Canvas.Pen.Color := RGB(141, 70, 255);
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Canvas.Ellipse(AX, AY, AX + XV(13), AY + XV(13));
    Canvas.Ellipse(AX + XV(4), AY, AX + XV(9), AY + XV(13));
    Canvas.Ellipse(AX, AY + XV(4), AX + XV(13), AY + XV(9));
  end;

  procedure DrawMonitor(AX, AY: Integer; AColor: TColor);
  begin
    Canvas.Pen.Color := AColor;
    Canvas.Pen.Width := 1;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(AX, AY, AX + XV(13), AY + XV(9));
    Canvas.MoveTo(AX + XV(5), AY + XV(9));
    Canvas.LineTo(AX + XV(5), AY + XV(12));
    Canvas.MoveTo(AX + XV(2), AY + XV(12));
    Canvas.LineTo(AX + XV(8), AY + XV(12));
  end;

begin
  SX := ClientWidth / 766;
  SY := ClientHeight / 490;
  ActiveTab := FActiveCreditTab;

  if CurrentPalette.IsDark then
  begin
    ActiveText := RGB(255, 255, 255);
    MutedText := RGB(180, 180, 180);
    TabBack := RGB(27, 27, 27);
  end
  else
  begin
    ActiveText := RGB(32, 32, 32);
    MutedText := RGB(90, 90, 90);
    TabBack := RGB(245, 245, 245);
  end;

  Canvas.Font.Name := 'Segoe UI';
  Canvas.Font.Size := 9;

  // Avro Official tab
  if ActiveTab = 0 then
  begin
    Canvas.Brush.Color := TabBack;
    Canvas.FillRect(CreditTabBounds(0));
  end;
  DrawAtom(XV(247), YV(9));
  if ActiveTab = 0 then
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ActiveText;
  end
  else
  begin
    Canvas.Font.Style := [];
    Canvas.Font.Color := MutedText;
  end;
  Canvas.TextOut(XV(266), YV(9), 'Avro Official');
  if ActiveTab = 0 then
  begin
    Canvas.Brush.Color := RGB(141, 70, 255);
    TabUnderlineTop := YV(9) + Canvas.TextHeight('Avro Official') + YV(6);
    TabBounds := CreditTabBounds(0);
    TabBounds.Top := TabUnderlineTop;
    TabBounds.Bottom := TabUnderlineTop + YV(3);
    Canvas.FillRect(TabBounds);
  end;

  // Avro Community tab
  if ActiveTab = 1 then
  begin
    Canvas.Brush.Color := TabBack;
    Canvas.FillRect(CreditTabBounds(1));
  end;
  if ActiveTab = 1 then
  begin
    DrawMonitor(XV(372), YV(10), ActiveText);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ActiveText;
  end
  else
  begin
    DrawMonitor(XV(372), YV(10), MutedText);
    Canvas.Font.Style := [];
    Canvas.Font.Color := MutedText;
  end;
  Canvas.TextOut(XV(390), YV(9), 'Avro Community');
  if ActiveTab = 1 then
  begin
    Canvas.Brush.Color := RGB(141, 70, 255);
    TabUnderlineTop := YV(9) + Canvas.TextHeight('Avro Community') + YV(6);
    TabBounds := CreditTabBounds(1);
    TabBounds.Top := TabUnderlineTop;
    TabBounds.Bottom := TabUnderlineTop + YV(3);
    Canvas.FillRect(TabBounds);
  end;

end;

procedure TfrmAbout.FormShow(Sender: TObject);
begin
  TOPMOST(Handle);
  ApplyNativeTheme;
end;

procedure TfrmAbout.LabelViewCreditClick(Sender: TObject);
begin
  MemoLicense.Visible := False;
  CreditsPanel.Visible := True;
  Label5.Visible := True;
  Label_License.Visible := True;
  LabelViewCredit.Visible := False;
  LayoutFooter;
end;

procedure TfrmAbout.Label_LicenseClick(Sender: TObject);
begin
  MemoLicense.Visible := True;
  CreditsPanel.Visible := False;
  Label5.Visible := False;
  Label_License.Visible := False;
  LabelViewCredit.Visible := True;
  LayoutFooter;
end;

procedure TfrmAbout.LayoutFooter;
var
  Labels: array[0..5] of TLabel;
  Gaps: array[0..5] of Integer;
  I, Total, X, Padding, Count: Integer;
begin
  Labels[0] := Label5;
  Labels[1] := Label_License;
  Labels[2] := LabelFooterSeparator;
  Labels[3] := Label4;
  Labels[4] := Label_OmicronLab;
  Labels[5] := Label8;
  Gaps[0] := 0;
  Gaps[1] := 6;
  Gaps[2] := 10;
  Gaps[3] := 10;
  Gaps[4] := 5;
  Gaps[5] := 5;

  if LabelViewCredit.Visible then
  begin
    // In the licence view "View Credit" takes the place of the licence sentence
    Labels[0] := LabelViewCredit;
    Labels[1] := nil;
  end;

  Total := 0;
  Count := 0;
  for I := 0 to 5 do
    if (Labels[I] <> nil) and Labels[I].Visible then
    begin
      if Count > 0 then
        Inc(Total, Gaps[I]);
      Inc(Total, Labels[I].Width);
      Inc(Count);
    end;

  Padding := ShapeFooter.Height div 4;
  X := (ClientWidth - Total) div 2;
  if X < 8 then
    X := 8;

  Count := 0;
  for I := 0 to 5 do
    if (Labels[I] <> nil) and Labels[I].Visible then
    begin
      if Count > 0 then
        Inc(X, Gaps[I]);
      Labels[I].Left := X;
      Labels[I].Top := ShapeFooter.Top + ShapeFooter.Height -
        Labels[I].Height - Padding;
      Inc(X, Labels[I].Width);
      Inc(Count);
    end;
end;

procedure TfrmAbout.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

procedure TfrmAbout.Label_UpdateClick(Sender: TObject);
begin
  AvroMainForm1.CheckupdateforAvroKeyboard1Click(nil);
end;

procedure TfrmAbout.Label_HelpClick(Sender: TObject);
begin
  Execute_Something('https://t.me/AvroUsersCommunity');
end;

function TfrmAbout.ActiveCreditLines: TStrings;
begin
  if FActiveCreditTab = 1 then
    Result := CommunityCredit.Lines
  else
    Result := Credit.Lines;
end;

procedure TfrmAbout.LoadActiveCredits;
begin
  FCreditsViewer.Lines := ActiveCreditLines;
  FCreditsViewer.ScrollPosition := FCreditsScrollPositions[FActiveCreditTab];
end;

procedure TfrmAbout.FormatRichEdit(ARichEdit: TRichEdit);
var
  I: Integer;
  Offset: Integer;
  LineText: string;
  SelectionStart: Integer;
  SelectionLength: Integer;
  ScrollPosition: TPoint;
begin
  SelectionStart := ARichEdit.SelStart;
  SelectionLength := ARichEdit.SelLength;
  ScrollPosition := ARichEdit.ScrollPosition;

  ARichEdit.SelectAll;
  ARichEdit.SelAttributes.Name := 'Segoe UI';
  ARichEdit.SelAttributes.Size := ARichEdit.Font.Size;
  if CurrentPalette.IsDark then
    ARichEdit.SelAttributes.Color := RGB(180, 180, 180)
  else
    ARichEdit.SelAttributes.Color := RGB(90, 90, 90);
  ARichEdit.SelAttributes.Style := [];
  ARichEdit.Paragraph.Alignment := taLeftJustify;
  ARichEdit.Paragraph.FirstIndent := 0;
  ARichEdit.Paragraph.LeftIndent := 12;
  ARichEdit.Paragraph.RightIndent := 12;

  Offset := 0;
  for I := 0 to ARichEdit.Lines.Count - 1 do
  begin
    LineText := Trim(ARichEdit.Lines[I]);
    if LineText <> '' then
    begin
      ARichEdit.SelStart := Offset;
      ARichEdit.SelLength := Length(ARichEdit.Lines[I]);
      if (I = 0) or (LineText[Length(LineText)] = ':') then
      begin
        ARichEdit.SelAttributes.Style := [fsBold];
        if I = 0 then
          ARichEdit.SelAttributes.Size := ARichEdit.Font.Size + 2;
      end;
    end;
    Inc(Offset, Length(ARichEdit.Lines[I]) + 2);
  end;

  ARichEdit.SelStart := SelectionStart;
  ARichEdit.SelLength := SelectionLength;
  ARichEdit.ScrollPosition := ScrollPosition;
end;

end.
