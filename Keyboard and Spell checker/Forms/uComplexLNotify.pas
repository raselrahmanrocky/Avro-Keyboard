{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit uComplexLNotify;

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
  ExtCtrls;

type
  TComplexLNotify = class(TForm)
    Label1: TLabel;
    Image1: TImage;
    Label2: TLabel;
    Label3: TLabel;
    ButtonOk: TButton;
    ButtonSkip: TButton;
    CheckNotDisplay: TCheckBox;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ButtonOkClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure ButtonSkipClick(Sender: TObject);
    private
      { Private declarations }
    public
      { Public declarations }
  end;

var
  ComplexLNotify: TComplexLNotify;

implementation

{$R *.dfm}

uses
  uFileFolderHandling,
  uRegistrySettings;

{ ==========================================Z===================================== }

procedure TComplexLNotify.ButtonOkClick(Sender: TObject);
begin
  Execute_Something(ExtractFilePath(Application.ExeName) + 'iComplex\IComplex.exe');
  ModalResult := mrOK;
end;

{ =============================================================================== }

procedure TComplexLNotify.ButtonSkipClick(Sender: TObject);
begin
  if CheckNotDisplay.Checked then
    DontShowComplexLNotification := 'YES';
  ModalResult := mrCancel;
end;

{ =============================================================================== }

procedure TComplexLNotify.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;

  ComplexLNotify := nil;
end;

{ =============================================================================== }

procedure TComplexLNotify.FormCreate(Sender: TObject);
begin
  {$IFDEF PortableOn}
  CheckNotDisplay.Enabled := True;
  {$ELSE}
  CheckNotDisplay.Enabled := False;
  {$ENDIF}
end;

{ =============================================================================== }

end.
