{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================

  "Avro Mouse - Click 'n' Type".

  The Bangla keys are captions, not pictures: each button's character is set as its
  Caption in the first Bangla face the machine can draw (uMouseKeyFace), and the VCL
  style paints it with the live ink. Nothing here is baked with a theme colour any
  more, which is what used to make a theme switch leave the previous ink on the
  keys - and what made the letters soft, since a raster baked for one box size was
  then drawn at another.
}

{$INCLUDE ../ProjectDefines.inc}

unit ufrmAvroMouse;

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
  uMouseKeyFace;

type
  TfrmAvroMouse = class(TForm)
    Panel1: TPanel;
    BitBtn3: TBitBtn;
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    BitBtn4: TBitBtn;
    BitBtn5: TBitBtn;
    BitBtn6: TBitBtn;
    BitBtn7: TBitBtn;
    BitBtn8: TBitBtn;
    BitBtn9: TBitBtn;
    BitBtn10: TBitBtn;
    BitBtn11: TBitBtn;
    BitBtn12: TBitBtn;
    BitBtn13: TBitBtn;
    BitBtn14: TBitBtn;
    BitBtn15: TBitBtn;
    BitBtn16: TBitBtn;
    BitBtn17: TBitBtn;
    BitBtn18: TBitBtn;
    BitBtn19: TBitBtn;
    BitBtn20: TBitBtn;
    BitBtn21: TBitBtn;
    BitBtn24: TBitBtn;
    BitBtn25: TBitBtn;
    BitBtn28: TBitBtn;
    BitBtn29: TBitBtn;
    BitBtn22: TBitBtn;
    BitBtn23: TBitBtn;
    BitBtn26: TBitBtn;
    BitBtn27: TBitBtn;
    BitBtn30: TBitBtn;
    BitBtn31: TBitBtn;
    BitBtn32: TBitBtn;
    BitBtn33: TBitBtn;
    BitBtn34: TBitBtn;
    BitBtn35: TBitBtn;
    BitBtn36: TBitBtn;
    BitBtn37: TBitBtn;
    BitBtn38: TBitBtn;
    BitBtn39: TBitBtn;
    BitBtn41: TBitBtn;
    Panel2: TPanel;
    BitBtn40: TBitBtn;
    BitBtn42: TBitBtn;
    BitBtn43: TBitBtn;
    BitBtn44: TBitBtn;
    BitBtn45: TBitBtn;
    BitBtn46: TBitBtn;
    BitBtn47: TBitBtn;
    BitBtn48: TBitBtn;
    BitBtn49: TBitBtn;
    BitBtn50: TBitBtn;
    BitBtn51: TBitBtn;
    BitBtn52: TBitBtn;
    BitBtn53: TBitBtn;
    BitBtn54: TBitBtn;
    BitBtn55: TBitBtn;
    BitBtn56: TBitBtn;
    BitBtn57: TBitBtn;
    BitBtn58: TBitBtn;
    BitBtn59: TBitBtn;
    BitBtn60: TBitBtn;
    BitBtn61: TBitBtn;
    Panel3: TPanel;
    BitBtn62: TBitBtn;
    BitBtn63: TBitBtn;
    BitBtn64: TBitBtn;
    BitBtn65: TBitBtn;
    BitBtn66: TBitBtn;
    BitBtn67: TBitBtn;
    BitBtn68: TBitBtn;
    BitBtn69: TBitBtn;
    BitBtn70: TBitBtn;
    BitBtn71: TBitBtn;
    GroupBox1: TGroupBox;
    BitBtn72: TBitBtn;
    BitBtn73: TBitBtn;
    BitBtn74: TBitBtn;
    BitBtn75: TBitBtn;
    BitBtn76: TBitBtn;
    BitBtn77: TBitBtn;
    BitBtn78: TBitBtn;
    BitBtn79: TBitBtn;
    BitBtn80: TBitBtn;
    BitBtn81: TBitBtn;
    BitBtn82: TBitBtn;
    BitBtn83: TBitBtn;
    BitBtn84: TBitBtn;
    BitBtn85: TBitBtn;
    BitBtn86: TBitBtn;
    BitBtn87: TBitBtn;
    BitBtn88: TBitBtn;
    GroupBox2: TGroupBox;
    But_KSs: TBitBtn;
    But_NGK: TBitBtn;
    But_NgG: TBitBtn;
    But_JNYA: TBitBtn;
    But_NYAC: TBitBtn;
    But_NYACh: TBitBtn;
    But_NYAJ: TBitBtn;
    But_T_T: TBitBtn;
    But_SsNYA: TBitBtn;
    But_HM: TBitBtn;
    But_ND: TBitBtn;
    But_ZFola: TBitBtn;
    But_RFola: TBitBtn;
    BitBtn102: TBitBtn;
    BitBtn103: TBitBtn;
    BitBtn104: TBitBtn;
    BitBtn105: TBitBtn;
    BitBtn106: TBitBtn;
    btnTab: TButton;
    btnBackspace: TButton;
    btnSpace: TButton;
    btnEnter: TButton;
    BitBtn89: TBitBtn;
    BitBtn90: TBitBtn;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure BitBtn1Click(Sender: TObject);
    procedure btnTabClick(Sender: TObject);
    procedure But_KSsClick(Sender: TObject);
    procedure But_NGKClick(Sender: TObject);
    procedure But_NgGClick(Sender: TObject);
    procedure But_JNYAClick(Sender: TObject);
    procedure But_NYACClick(Sender: TObject);
    procedure But_NYAChClick(Sender: TObject);
    procedure But_NYAJClick(Sender: TObject);
    procedure But_T_TClick(Sender: TObject);
    procedure But_SsNYAClick(Sender: TObject);
    procedure But_HMClick(Sender: TObject);
    procedure But_NDClick(Sender: TObject);
    procedure But_RFolaClick(Sender: TObject);
    procedure But_ZFolaClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    private
      { Which face the Bangla keys are captioned with, decided once per window by
        uMouseKeyFace. Kept so a style change can tell whether anything on the keys
        carries a colour of its own (only the mkfBitmap fallback does). }
      FFace: TMouseKeyFace;
      procedure TypeIt(const tStr: string);
      procedure DetectLeftClickOnTitleBar(var Msg: TWMNCLButtonDown); message WM_NCLBUTTONDOWN;
      procedure DetectRightClickOnTitleBar(var Msg: TWMNCLButtonDown); message WM_NCRBUTTONDOWN;
      procedure ApplyKeyFaces;
      function DisplayTextOf(const ABtn: TBitBtn): string;
      function BanglaFontFile: string;
    public
      { Public declarations }
    protected
      procedure CreateParams(var Params: TCreateParams); override;
      { Delivered whenever the active VCL style changes - the Customize dialog's
        theme setting (LIGHT / DARK / SYSTEM) and Windows' own theme change both
        end up here. Captions need nothing from this handler: the style paints them
        with the live ink. Only the baked-bitmap fallback carries a colour of its
        own, and ApplyKeyFaces re-tints it. }
      procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  end;

var
  frmAvroMouse: TfrmAvroMouse;

implementation

{$R *.dfm}

uses
  uForm1,
  BanglaChars,
  KeyboardFunctions,
  uWindowHandlers,
  uRegistrySettings,
  clsLayout,
  WindowsDarkMode,
  uFileFolderHandling,
  Vcl.Themes;

const
  Show_Window_in_Taskbar = True;

procedure TfrmAvroMouse.BitBtn1Click(Sender: TObject);
var
  WC: Char;
begin
  WC := Char((Sender as TBitBtn).Tag);
  TypeIt(WC);
end;

procedure TfrmAvroMouse.btnTabClick(Sender: TObject);
begin
  SendKey_SendInput((Sender as TButton).Tag);
end;

procedure TfrmAvroMouse.But_HMClick(Sender: TObject);
begin
  TypeIt(b_H + b_Hasanta + b_M);
end;

procedure TfrmAvroMouse.But_JNYAClick(Sender: TObject);
begin
  TypeIt(b_J + b_Hasanta + b_NYA);
end;

procedure TfrmAvroMouse.But_KSsClick(Sender: TObject);
begin
  TypeIt(b_K + b_Hasanta + b_Ss);
end;

procedure TfrmAvroMouse.But_NDClick(Sender: TObject);
begin
  TypeIt(b_Nn + b_Hasanta + b_Dd);
end;

procedure TfrmAvroMouse.But_NgGClick(Sender: TObject);
begin
  TypeIt(b_NGA + b_Hasanta + b_G);
end;

procedure TfrmAvroMouse.But_NGKClick(Sender: TObject);
begin
  TypeIt(b_NGA + b_Hasanta + b_K);
end;

procedure TfrmAvroMouse.But_NYACClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_C);
end;

procedure TfrmAvroMouse.But_NYAChClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_CH);
end;

procedure TfrmAvroMouse.But_NYAJClick(Sender: TObject);
begin
  TypeIt(b_NYA + b_Hasanta + b_J);
end;

procedure TfrmAvroMouse.But_RFolaClick(Sender: TObject);
begin
  TypeIt(b_Hasanta + b_R);
end;

procedure TfrmAvroMouse.But_SsNYAClick(Sender: TObject);
begin
  TypeIt(b_Ss + b_Hasanta + b_Nn);
end;

procedure TfrmAvroMouse.But_T_TClick(Sender: TObject);
begin
  TypeIt(b_T + b_Hasanta + b_T);
end;

procedure TfrmAvroMouse.But_ZFolaClick(Sender: TObject);
begin
  TypeIt(b_Hasanta + b_Z);
end;

procedure TfrmAvroMouse.CreateParams(var Params: TCreateParams);
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

procedure TfrmAvroMouse.DetectLeftClickOnTitleBar(var Msg: TWMNCLButtonDown);
begin
  if (Msg.HitTest = htCaption) then
    SetForegroundWindow(Self.Handle);
  inherited;
end;

procedure TfrmAvroMouse.DetectRightClickOnTitleBar(var Msg: TWMNCLButtonDown);
begin
  if (Msg.HitTest = htCaption) then
    SetForegroundWindow(Self.Handle);
  inherited;
end;

procedure TfrmAvroMouse.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if Self.Top >= 0 then
    AvroMousePosX := intToStr(Self.Top);
  if Self.Left >= 0 then
    AvroMousePosY := intToStr(Self.Left);

  Action := caFree;

  frmAvroMouse := nil;
end;

procedure TfrmAvroMouse.FormCreate(Sender: TObject);
begin
  try
    if (StrToInt(AvroMousePosX) > Screen.Width) or (StrToInt(AvroMousePosX) < 0) then
      AvroMousePosX := '0';
    if (StrToInt(AvroMousePosY) > Screen.Height) or (StrToInt(AvroMousePosY) < 0) then
      AvroMousePosY := '0';

    Self.Top := StrToInt(AvroMousePosX);
    Self.Left := StrToInt(AvroMousePosY);
  except
    on E: Exception do
    begin
      AvroMousePosX := '0';
      AvroMousePosY := '0';
      Self.Top := 0;
      Self.Left := 0;
    end;
  end;

  { Once per window: the face is a property of the machine, not of a key, and the
    bundled font has to be registered before the first key can be captioned with
    it. }
  FFace := PickMouseKeyFace(BanglaFontFile);
  ApplyKeyFaces;
end;

function TfrmAvroMouse.BanglaFontFile: string;
var
  ExeDir: string;
  I: Integer;
begin
  ExeDir := ExtractFilePath(ParamStr(0));
  for I := 0 to 3 do
  begin
    case I of
      0: Result := ExeDir + 'kalpurush.ttf';
      1: Result := ExeDir + 'fonts\kalpurush.ttf';
      2: Result := ExeDir + '..\assets\fonts\kalpurush.ttf';
      3: Result := GetAvroDataDir + 'fonts\kalpurush.ttf';
    end;
    if FileExists(Result) then
      Exit;
  end;
  Result := '';
end;

{ Every Bangla-looking key gets its character as its caption; uMouseKeyFace owns
  what that means per tier (caption and font, or the tinted baked bitmap when no
  Bangla font exists). DisplayTextOf stays the single source of the characters, so
  what a key shows and what it types cannot drift apart. }
procedure TfrmAvroMouse.ApplyKeyFaces;
var
  I: Integer;
  Btn: TBitBtn;
  Display: string;
begin
  for I := 0 to ComponentCount - 1 do
    if Components[I] is TBitBtn then
    begin
      Btn     := TBitBtn(Components[I]);
      Display := DisplayTextOf(Btn);
      if Display <> '' then
        ApplyMouseKeyFace(Btn, Display, FFace);
    end;
end;

procedure TfrmAvroMouse.CMStyleChanged(var Message: TMessage);
begin
  { Captions are drawn by the style itself, so the normal case needs nothing here.
    The mkfBitmap fallback is the one thing on these keys that carries its own
    colour, and a Windows theme change announces itself to every window even while
    a forced LIGHT/DARK theme ignores it - hence the guard. }
  if FFace = mkfBitmap then
  begin
    ApplyKeyFaces;
    if HandleAllocated then
      RedrawWindow(Handle, nil, 0,
        RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
  end;
end;

function TfrmAvroMouse.DisplayTextOf(const ABtn: TBitBtn): string;
begin
  if (ABtn.Tag = $200C) or (ABtn.Tag = $200D) then
    Result := ''
  else if ABtn.Tag <> 0 then
    Result := WideChar(ABtn.Tag)
  else if ABtn.Name = 'But_KSs' then
    Result := b_K + b_Hasanta + b_Ss
  else if ABtn.Name = 'But_NGK' then
    Result := b_NGA + b_Hasanta + b_K
  else if ABtn.Name = 'But_NgG' then
    Result := b_NGA + b_Hasanta + b_G
  else if ABtn.Name = 'But_JNYA' then
    Result := b_J + b_Hasanta + b_NYA
  else if ABtn.Name = 'But_NYAC' then
    Result := b_NYA + b_Hasanta + b_C
  else if ABtn.Name = 'But_NYACh' then
    Result := b_NYA + b_Hasanta + b_CH
  else if ABtn.Name = 'But_NYAJ' then
    Result := b_NYA + b_Hasanta + b_J
  else if ABtn.Name = 'But_T_T' then
    Result := b_T + b_Hasanta + b_T
  else if ABtn.Name = 'But_SsNYA' then
    Result := b_Ss + b_Hasanta + b_Nn
  else if ABtn.Name = 'But_HM' then
    Result := b_H + b_Hasanta + b_M
  else if ABtn.Name = 'But_ND' then
    Result := b_Nn + b_Hasanta + b_Dd
  else if ABtn.Name = 'But_ZFola' then
    Result := b_Hasanta + b_Z
  else if ABtn.Name = 'But_RFola' then
    Result := b_Hasanta + b_R
  else
    Result := '';
end;

procedure TfrmAvroMouse.TypeIt(const tStr: string);
begin
  SendKey_Char(tStr);
end;

end.
