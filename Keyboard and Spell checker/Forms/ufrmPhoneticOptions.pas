{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit ufrmPhoneticOptions;

interface

uses
  Windows,
  Messages,
  SysUtils,
  Classes,
  Graphics,
  Controls,
  Forms,
  StdCtrls;

type
  { The Avro Phonetic page of the Customize dialog ("Preview Window and
    Typing Mode"). It used to live directly inside TfrmOptions.GroupBox3;
    it is now its own form, parented into that group box (Parent + alClient)
    by TfrmOptions.FormCreate, which also re-points the dialog's published
    fields at the controls below so LoadSettings / SaveSettings /
    CheckShowPrevWindowClick are unchanged.

    Why this exists: with an active custom VCL style every check box and
    radio button is painted by the style engine (seClient present in
    StyleElements), and that paint path used to produce solid black bars
    behind the controls of this page. TStyleHook.WMPaint paints into a
    fresh bitmap that only comes out right when PaintBackground fills it
    first; whenever a parent of that chain answered the fill with nothing,
    the unwritten bitmap pixels stayed black. That defect is now repaired
    for the whole process by TCheckBoxStyleHookFix / TRadioButtonStyleHookFix
    in Units\uScrollBoxStyleHookFix.pas - those hooks fill the button surface
    with the active style's scPanel colour before the caption and glyph are
    drawn, so the uninitialised-bitmap path is never reached. The page no
    longer needs to opt out of the style engine.

    The form and all six windowed controls therefore carry the default
    StyleElements (seFont + seClient + seBorder), which lets the style engine
    paint them in the active style - identical to every other check box and
    radio button in the Customize dialog. The five labels keep the default
    too: a TLabel is a TGraphicControl - no window, no style hook - so it
    cannot take part in the old black-bar path at all, while seFont keeps
    the style resolving its text colour on a dark style, and
    MakeLabelsOpaque (Units\uScrollBoxStyleHookFix.pas, which walks ScrollBox2
    recursively and therefore still reaches into this embedded form) gives
    them the same scPanel surface colour as every other label in the dialog. }
  TfrmPhoneticOptions = class(TForm)
    Label_PhoneticTypingMode: StdCtrls.TLabel;
    Label1: StdCtrls.TLabel;
    Label4: StdCtrls.TLabel;
    Label9: StdCtrls.TLabel;
    Label12: StdCtrls.TLabel;
    CheckShowPrevWindow: TCheckBox;
    optPhoneticMode_Dict: TRadioButton;
    optPhoneticMode_Char: TRadioButton;
    optPhoneticMode_OnlyChar: TRadioButton;
    CheckRememberCandidate: TCheckBox;
    CheckTabBrowsing: TCheckBox;
  protected
    { A runtime style switch broadcasts CM_STYLECHANGED down the whole child
      tree (Vcl.Controls.pas, TWinControl.WndProc -> Broadcast), so an
      embedded form receives it through its parent just like every other
      control. The explicit local redraw keeps the page in step with the new
      style: without it the page would keep showing the previous style's
      pixels until something else invalidated it. }
    procedure CMStyleChanged(var Message: TMessage); message CM_STYLECHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    { Resolves this form's background from the ACTIVE style: scPanel is the
      surface the surrounding GroupBox3, panels and scroll box paint with,
      so the embedded page matches its frame exactly on both the light and
      the dark style. Never a literal colour - the dark style's scPanel is
      black, the light style's is $F3F3F3. With no custom style active the
      system style answers scPanel with clBtnFace, i.e. the plain Windows
      look. Called from the constructor and again from
      TfrmOptions.FormCreate right after the page has been parented. }
    procedure ApplyTheme;
  end;

implementation

{$R *.dfm}

uses
  Themes;

{ =============================================================================== }

constructor TfrmPhoneticOptions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { The .dfm carries no Color of its own, so this value survives streaming in
    either order; TfrmOptions.FormCreate calls ApplyTheme once more after
    parenting the page, which is cheap and makes the result independent of
    when the style was last set. }
  ApplyTheme;
end;

{ =============================================================================== }

procedure TfrmPhoneticOptions.ApplyTheme;
begin
  if StyleServices.Available then
    Color := StyleServices.GetStyleColor(scPanel);
end;

{ =============================================================================== }

procedure TfrmPhoneticOptions.CMStyleChanged(var Message: TMessage);
begin
  inherited;
  ApplyTheme;
  if HandleAllocated then
    RedrawWindow(Handle, nil, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

end.
