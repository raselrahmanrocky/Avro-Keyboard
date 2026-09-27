{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmUpdateNotify;

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
  Buttons,
  ExtCtrls,
  System.Types;

type
  { Which release channel the offered update belongs to. The value comes from
    the <channel> node of the version manifest; manifests published before
    that node existed fall back to a heuristic in clsUpdateInfoDownloader. }
  TUpdateChannel = (ucStable, ucBeta, ucUnknown);

  TfrmUpdateNotify = class(TForm)
    Image1: TImage;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Button1: TButton;
    lblWhatsNew: TLabel;
    Label6: TLabel;
    lblOldVer: TLabel;
    lblNewVer: TLabel;
    lblDate: TLabel;
    but_Download: TButton;
    pnlChannel: TPanel;
    lblChannel: TLabel;
    lblWarning: TLabel;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure lblWhatsNewClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure but_DownloadClick(Sender: TObject);
    private
      { Private declarations }
      WhatsNewURL: string;
      DownloadURL: string;
      { ClientWidth as drawn in the .dfm (design PixelsPerInch 144). VCL scales
        the whole form when the running DPI differs, so every position and
        height this class computes at runtime has to be scaled from it too. }
      function DesignScale: Double;
      { Height lblWarning needs to show AText without clipping, measured with
        the label's own font so DPI scaling and line wrapping are exact. }
      function WarningHeightFor(const AText: string): Integer;
      { Grows the dialog when lblWarning is shown so the buttons never sit on
        top of the beta/cross-channel note; shrinks it again otherwise. }
      procedure LayoutForWarning(AWarningVisible: Boolean);
    public
      { Public declarations }
      procedure SetupAndShow(const mNewVer, mDate, mWhatsNew, mDownload: string;
        AChannel: TUpdateChannel = ucUnknown; const ANamedVersion: string = '');
    protected
      procedure CreateParams(var Params: TCreateParams); override;
  end;

var
  frmUpdateNotify: TfrmUpdateNotify;

implementation

{$R *.dfm}

uses
  uFileFolderHandling,
  clsFileVersion,
  uWindowHandlers;

const
  Show_Window_in_Taskbar = True;

  { =============================================================================== }

procedure TfrmUpdateNotify.Button1Click(Sender: TObject);
begin
  self.Close;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.but_DownloadClick(Sender: TObject);
begin
  Execute_Something(DownloadURL);
  self.Close;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  with Params do
  begin
    if Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle or WS_EX_APPWINDOW and not WS_EX_TOOLWINDOW;
      ExStyle := ExStyle or WS_EX_TOPMOST or WS_EX_NOACTIVATE;
      WndParent := GetDesktopwindow;
    end
    else if not Show_Window_in_Taskbar then
    begin
      ExStyle := ExStyle and not WS_EX_APPWINDOW;
    end;
  end;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;

  frmUpdateNotify := nil;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.lblWhatsNewClick(Sender: TObject);
begin
  Execute_Something(WhatsNewURL);
end;

{ =============================================================================== }

const
  { ClientWidth as drawn in the .dfm, whose design PixelsPerInch is 144. VCL
    scales the whole form when the running DPI differs, so anything this class
    computes at runtime has to be scaled from it as well - the form arrives
    already scaled, but ClientHeight takes raw pixels. }
  DESIGN_CLIENT_WIDTH = 555;
  DESIGN_GAP          = 12;

function TfrmUpdateNotify.DesignScale: Double;
begin
  Result := ClientWidth / DESIGN_CLIENT_WIDTH;
end;

{ =============================================================================== }

function TfrmUpdateNotify.WarningHeightFor(const AText: string): Integer;
var
  R:   TRect;
  { Winapi.Windows also declares a TBitmap record; the class we need is the
    VCL one. }
  Bmp: Graphics.TBitmap;
begin
  { DT_CALCRECT returns the height AText actually needs at this DPI, wrapping
    included - so neither a long beta notice nor a one-line cross-channel note
    can ever be clipped or leave a hole. Measured on an off-screen bitmap with
    the label's own font, i.e. exactly what the label will paint. }
  Bmp := Graphics.TBitmap.Create;
  try
    Bmp.Width := lblWarning.Width;
    Bmp.Height := 8;
    Bmp.Canvas.Font.Assign(lblWarning.Font);
    R := Rect(0, 0, lblWarning.Width, 0);
    DrawText(Bmp.Canvas.Handle, PChar(AText), -1, R, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    Result := (R.Bottom - R.Top) + Integer(Round(4 * DesignScale));
  finally
    Bmp.Free;
  end;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.LayoutForWarning(AWarningVisible: Boolean);
var
  Gap, ButtonTop: Integer;
begin
  Gap := Integer(Round(DESIGN_GAP * DesignScale));

  { Note only lblWarning and pnlChannel are positioned in form coordinates -
    lblChannel sits inside the panel with Align = alClient, so its Top is 0
    relative to the panel and would put the buttons near the title bar. }
  if AWarningVisible then
    ButtonTop := lblWarning.Top + lblWarning.Height + Gap
  else
    ButtonTop := pnlChannel.Top + pnlChannel.Height + Gap;

  Button1.Top := ButtonTop;
  but_Download.Top := ButtonTop;
  ClientHeight := ButtonTop + Button1.Height + Gap;
end;

{ =============================================================================== }

procedure TfrmUpdateNotify.SetupAndShow(const mNewVer, mDate, mWhatsNew, mDownload: string;
  AChannel: TUpdateChannel; const ANamedVersion: string);
var
  Version: TFileVersion;
  mOldVer: string;
begin
  Version := TFileVersion.Create();
  mOldVer := IntToStr(Version.VerMajor) + '.' + IntToStr(Version.VerMinor) + '.' + IntToStr(Version.VerRelease) + '.' + IntToStr(Version.VerBuild);

  lblOldVer.Caption := mOldVer{$IFDEF BetaVersion} + ' (Beta build)'{$ENDIF};
  lblDate.Caption := mDate;

  { The app runs a VCL style (Windows10 / theme), and a styled control paints
    with the theme's fill and font instead of its own Color and Font.Color -
    which turns this badge into plain form-grey with black text. Opt just the
    badge out so the channel colour and its white bold text always show. }
  pnlChannel.StyleElements := [];
  lblChannel.StyleElements := [];

  { The marketing name sits on its own line above the badge: a bare number
    stays put, and "Avro Keyboard 6.0.2-beta (6.0.2.0)" never runs past the
    right edge of the dialog. }
  if ANamedVersion <> '' then
    lblNewVer.Caption := ANamedVersion + ' (' + mNewVer + ')'
  else
    lblNewVer.Caption := mNewVer;

  case AChannel of
    ucBeta:
      begin
        Caption := 'Beta update available for Avro Keyboard';
        pnlChannel.Color := RGB(191, 85, 0);
        lblChannel.Caption := '  BETA RELEASE  ';
        lblWarning.Caption := 'Beta builds are pre-release software and may contain bugs.Your feedback on GitHub helps us improve the final release.';
        lblWarning.Visible := True;
        but_Download.Caption := 'Download beta now!';
      end;
  else
    begin
      Caption := 'Update available for Avro Keyboard';
      pnlChannel.Color := RGB(27, 110, 60);
      lblChannel.Caption := '  STABLE RELEASE  ';
      lblWarning.Visible := False;
      but_Download.Caption := 'Download now!';

      {$IFDEF BetaVersion}
      { Offered a stable (or unknown-channel) update while running a beta
        build: say so, because the download replaces the beta the user is on. }
      lblWarning.Caption := 'This stable release will replace your current beta build.';
      lblWarning.Visible := True;
      {$ENDIF}
    end;
  end;

  if lblWarning.Visible then
    lblWarning.Height := WarningHeightFor(lblWarning.Caption);

  pnlChannel.Visible := True;
  lblChannel.Visible := True;
  LayoutForWarning(lblWarning.Visible);

  WhatsNewURL := mWhatsNew;
  DownloadURL := mDownload;
  TOPMOST(self.Handle);
  self.Show;
end;
{ =============================================================================== }

end.
