{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit Unit1;

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
  ExtCtrls,
  clsUnicodeToBijoy2000,
  ComCtrls,
  Vcl.AppEvnts;

type
  TForm1 = class(TForm)
    MEMO1: TMemo;
    MEMO2: TMemo;
    Label1: TLabel;
    Button1: TButton;
    Progress: TProgressBar;
    Label8: TLabel;
    Label_OmicronLab: TLabel;
    Label4: TLabel;
    AppEvents: TApplicationEvents;
    PanelFooter: TPanel;
    PanelHeader: TPanel;
    PanelButton: TPanel;
    Splitter1: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Splitter1Moved(Sender: TObject);
    procedure Label_OmicronLabClick(Sender: TObject);
    procedure AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
    private
      { Private declarations }
      FUniToBijoy: TUnicodeToBijoy2000;
      FSplitterRatio: Double;
      FSplitterUsed: Boolean;

      procedure HandleThemes;
    public
      { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  uFileFolderHandling,
  WindowsDarkMode;

{ =============================================================================== }

procedure TForm1.HandleThemes;
begin
  SetAppropriateThemeMode('Windows10 Dark', 'Windows10');
end;

{ =============================================================================== }

procedure TForm1.AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
begin
  if SameText('ImmersiveColorSet', string(Section)) then
    HandleThemes;
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO2.Clear;
  application.ProcessMessages;

  MEMO2.Text := FUniToBijoy.Convert(MEMO1.Text);

  Progress.Position := 100;
  application.ProcessMessages;
  Progress.Visible := False;
  MEMO1.Enabled := True;
  MEMO2.Enabled := True;
  Button1.Enabled := True;
end;

{ =============================================================================== }

procedure TForm1.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  FUniToBijoy.Free;
  Action := caFree;
  Form1 := nil;
end;

{ =============================================================================== }

procedure TForm1.FormCreate(Sender: TObject);
begin
  PanelFooter.DoubleBuffered := True;
  FSplitterRatio := 0.5;
  FSplitterUsed := False;
  HandleThemes;
  FUniToBijoy := TUnicodeToBijoy2000.Create;
end;

{ =============================================================================== }

procedure TForm1.FormResize(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height - PanelFooter.Height - Splitter1.Height;
  if Available < 100 then
    Available := 100;
  MEMO1.Height := Round(Available * FSplitterRatio);
end;

{ =============================================================================== }

procedure TForm1.Splitter1Moved(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    FSplitterRatio := MEMO1.Height / Available;
    FSplitterUsed := True;
  end;
end;

{ =============================================================================== }

procedure TForm1.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

{ =============================================================================== }

end.
