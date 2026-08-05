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
  clsUnicodeToBijoy2000,
  ComCtrls,
  ExtCtrls,
  uJustifiedBox,
  Vcl.AppEvnts;

type
  TForm1 = class(TForm)
    MEMO1: TJustifiedBox;
    MEMO2: TJustifiedBox;
    Label1: TLabel;
    Button1: TButton;
    Progress: TProgressBar;
    Label8: TLabel;
    Label_OmicronLab: TLabel;
    Label4: TLabel;
    AppEvents: TApplicationEvents;
    PanelHeader: TPanel;
    PanelButton: TPanel;
    PanelFooter: TPanel;
    Splitter1: TSplitter;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure FormResize(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure SplitterMoved(Sender: TObject);
    procedure Label_OmicronLabClick(Sender: TObject);
    procedure AppEventsSettingChange(Sender: TObject; Flag: Integer; const Section: string; var Result: LongInt);
    private
      FUniToBijoy: TUnicodeToBijoy2000;
      FSplitterRatio: Double;

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
var
  Src, OutText, EOL, Segment: string;
  P, Q, TotalLen: Integer;
begin
  MEMO1.Enabled := False;
  MEMO2.Enabled := False;
  Button1.Enabled := False;
  Progress.Visible := True;
  Progress.Position := 0;
  MEMO2.Clear;
  application.ProcessMessages;

  // NOTE: MEMO1.Lines must NOT be used here. With WordWrap enabled, Windows
  // counts soft-wrapped (visual) lines as separate lines, which would make
  // each wrapped segment a new paragraph in the output. Split the raw text
  // on real line breaks (CR/LF) only, so only Enter-pressed lines become
  // separate paragraphs.
  Src := MEMO1.Text;
  TotalLen := Length(Src);
  OutText := '';
  P := 1;
  while P <= TotalLen do
  begin
    Q := P;
    while (Q <= TotalLen) and not CharInSet(Src[Q], [#13, #10]) do
      Inc(Q);

    Segment := Copy(Src, P, Q - P);
    OutText := OutText + FUniToBijoy.Convert(Segment);

    if Q <= TotalLen then
    begin
      EOL := Src[Q];
      Inc(Q);
      if (EOL = #13) and (Q <= TotalLen) and (Src[Q] = #10) then
      begin
        EOL := EOL + #10;
        Inc(Q);
      end;
      OutText := OutText + EOL;
    end;

    P := Q;
    Progress.Position := (P * 100) div (TotalLen + 1);
    application.ProcessMessages;
  end;
  MEMO2.Text := OutText;

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
  HandleThemes;
  DoubleBuffered := True;
  
  // Keep DoubleBuffered on to stop panel flickering
  PanelHeader.DoubleBuffered := True;
  PanelButton.DoubleBuffered := True;
  PanelFooter.DoubleBuffered := True;

  FSplitterRatio := MEMO1.Height /
    (ClientHeight - PanelHeader.Height - PanelButton.Height - PanelFooter.Height - Splitter1.Height);
  FUniToBijoy := TUnicodeToBijoy2000.Create;
end;

{ =============================================================================== }

procedure TForm1.FormResize(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height
    - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
  begin
    DisableAlign; // Stop extra re-aligning during resize
    try
      MEMO1.Height := Round(Available * FSplitterRatio);
    finally
      EnableAlign;
    end;
  end;
end;

{ =============================================================================== }

procedure TForm1.SplitterMoved(Sender: TObject);
var
  Available: Integer;
begin
  Available := ClientHeight - PanelHeader.Height - PanelButton.Height
    - PanelFooter.Height - Splitter1.Height;
  if Available > 0 then
    FSplitterRatio := MEMO1.Height / Available;
end;

{ =============================================================================== }

procedure TForm1.Label_OmicronLabClick(Sender: TObject);
begin
  Execute_Something('https://www.omicronlab.com');
end;

{ =============================================================================== }

end.