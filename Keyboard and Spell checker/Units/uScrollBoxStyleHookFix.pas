{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uScrollBoxStyleHookFix;

{
  Removes the text smearing / ghost trails a TScrollBox shows while it is
  scrolled quickly under the "Windows10 Dark" VCL style (the Customize dialog's
  ScrollBox2 in Forms\ufrmOptions.pas is the case this was written for). The
  "Windows10" light style shows the same bit-blit behaviour but the residue is
  invisible against its bright surfaces, which is why this looks like a
  dark-style-only bug.

  Why the stock behaviour smears (all line numbers: RAD Studio 23.0 sources):

  1. TScrollBox is painted by TScrollBoxStyleHook (Vcl.Forms.pas:2370, 21077).
     Its constructor sets OverrideEraseBkgnd and fills the client rect with
     StyleServices.GetStyleColor(scPanel) - an OPAQUE colour. So the erase is
     not see-through; the problem is that during a scroll the erase is not run
     for the surfaces that moved.
  2. TWinControl.ScrollBy (Vcl.Controls.pas:13179) bit-blits the client area
     with ScrollWindow and invalidates only the uncovered band. The category
     panels are not invalidated at all - they are only repositioned
     (SetWindowPos from Realign), so their pixels come from the cached surface.
     Under the dark style those pixels are re-composited through the
     alpha-bitmap parent-background path (Vcl.ExtCtrls.pas:12589), and a
     partially stale destination survives every partial repaint: the trail.
  3. A control-side WM_ERASEBKGND override cannot help: while a style is
     active the style hook handles that message first and marks it handled
     (Vcl.Themes.pas:7611), so the control never sees it. The erase has to be
     ASKED FOR again, which is what the forced repaint below does.

  The fix is therefore two things in one hook, registered for TScrollBox:

  * PaintBackground is answered with a solid, opaque fill whose colour still
    comes from the active style, so nothing here is hardcoded and both styles
    keep their own surface colour;
  * after every scroll message (WM_VSCROLL / WM_HSCROLL / WM_MOUSEWHEEL) the
    whole scrollbox, children included, is invalidated, erased and repainted
    synchronously - RDW_ERASE is the load-bearing flag, because it runs exactly
    the opaque erase above.

  Base class note: there is no TScrollingWinControlStyleHook in the VCL. The
  hierarchy is TStyleHook -> TScrollingStyleHook -> TScrollBoxStyleHook, all
  declared in the interface section of Vcl.Forms, and TScrollBoxStyleHook is
  the one for TScrollBox. Deriving from it keeps the styled scrollbar windows
  and the styled border that TScrollingStyleHook provides. (TCustomScrollBox
  does not exist either; TScrollBox derives from TScrollingWinControl.)
}

interface

uses
  Winapi.Windows,   // RedrawWindow, RDW_*, HWND
  Winapi.Messages,  // WM_VSCROLL, WM_HSCROLL, WM_MOUSEWHEEL
  System.Classes,   // TComponent
  Vcl.Controls,     // TControl, TWinControl
  Vcl.Graphics,     // TCanvas, TColor
  Vcl.StdCtrls,     // TLabel
  Vcl.Themes,       // TCustomStyleEngine, TStyleManager, StyleServices, TStyleColor
  Vcl.Forms;        // TScrollBox, TScrollBoxStyleHook

type
  { Opaque-erase + forced-repaint style hook for TScrollBox. Registered for the
    whole process by this unit's initialization; the styled appearance itself
    (scrollbars, border, colours) is inherited unchanged. }
  TScrollBoxStyleHookFix = class(TScrollBoxStyleHook)
  strict private
    function SurfaceColor: TColor;
    procedure RepaintAfterScroll;
  strict protected
    procedure PaintBackground(Canvas: TCanvas); override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AControl: TWinControl); override;
  end;

{ Runtime hygiene for one scrollbox and everything inside it. Call it once the
  control's children exist (end of a form's OnCreate):

    ApplyStyledScrollFix(ScrollBox2);

  It enables double buffering, turns off smooth thumb-drag scrolling and makes
  every TLabel in the control tree erase its own background with the style's
  surface colour. See the implementation for what each part is for. }
procedure ApplyStyledScrollFix(const AScrollBox: TScrollBox);

implementation

var
  // True once this unit's initialization registered the hook, so the
  // finalization only unregisters a pair that is really there
  // (TCustomStyleEngine.UnRegisterStyleHook raises when it is not).
  FHookRegistered: Boolean = False;

{ =============================================================================== }

constructor TScrollBoxStyleHookFix.Create(AControl: TWinControl);
begin
  inherited Create(AControl);
  { The base constructor already reads scPanel once; repeating it here keeps
    the erase brush and the PaintBackground override below from ever drifting
    apart if that base implementation changes. }
  Brush.Color := SurfaceColor;
end;

function TScrollBoxStyleHookFix.SurfaceColor: TColor;
begin
  { scPanel is the surface the style paints a scrollbox with (it is what the
    stock hook erases with). If no style is available at all - unreachable for
    a hook, since the engine only calls one while a style is active - the
    system colour is used instead; nothing here is a literal colour. }
  if StyleServices.Available then
    Result := StyleServices.GetStyleColor(scPanel)
  else
    Result := StyleServices.GetSystemColor(clBtnFace);
end;

procedure TScrollBoxStyleHookFix.PaintBackground(Canvas: TCanvas);
begin
  { Deliberately not calling inherited: that fills with the hook's brush and
    nothing else, while this states the two properties the fix depends on -
    a solid brush and a colour resolved from the ACTIVE style - at the point a
    reader looks for them. No alpha blending, no style bitmap element. }
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := SurfaceColor;
  Canvas.FillRect(Control.ClientRect);
end;

procedure TScrollBoxStyleHookFix.WndProc(var Message: TMessage);
begin
  { inherited dispatches the message to the hook's message methods, and for a
    scroll that means TScrollingStyleHook.WMVScroll (Vcl.Forms.pas:16300) ->
    CallDefaultProc -> the control's own WndProc, i.e. the scroll already
    happened by the time this returns. The bit-blit it performed is what left
    stale pixels behind, so the repair goes right here. }
  inherited;
  case Message.Msg of
    WM_VSCROLL, WM_HSCROLL, WM_MOUSEWHEEL:
      RepaintAfterScroll;
  end;
end;

procedure TScrollBoxStyleHookFix.RepaintAfterScroll;
begin
  if (Control = nil) or not Control.HandleAllocated then
    Exit;

  { RDW_INVALIDATE - the whole client area, not just the band the scroll
    invalidated.
    RDW_ERASE      - re-sends WM_ERASEBKGND, which this hook answers with the
    opaque fill above; this is the flag that actually removes a ghost.
    RDW_ALLCHILDREN - takes the category panels and their controls with it;
    TWinControl.ScrollBy moved them without invalidating them.
    RDW_UPDATENOW  - completes paint and erase before the next queued scroll
    message is handled, so a fast wheel spin cannot coalesce frames. }
  RedrawWindow(Control.Handle, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
end;

{ =============================================================================== }

{ Recursive: in this dialog the labels sit inside the category panels and the
  group boxes, so walking Controls would stop one level too early. }
procedure MakeLabelsOpaque(const AParent: TControl);
var
  I: Integer;
  LChild: TControl;
begin
  if not (AParent is TWinControl) then
    Exit;

  for I := 0 to TWinControl(AParent).ControlCount - 1 do
  begin
    LChild := TWinControl(AParent).Controls[I];
    if LChild is TLabel then
    begin
      { Under styles a TLabel is transparent by default (TCustomLabel.Create
        clears csOpaque while StyleServices.Enabled), so its glyphs are written
        straight over whatever the parent last drew. Opaque, it fills its own
        rect first (TCustomLabel.Paint) and a moved label can no longer leave
        its old text behind. Colour from the style, never from a literal: the
        default clBtnFace would paint light boxes in dark mode. }
      TLabel(LChild).Transparent := False;
      TLabel(LChild).Color := StyleServices.GetStyleColor(scPanel);
    end;
    MakeLabelsOpaque(LChild);
  end;
end;

procedure ApplyStyledScrollFix(const AScrollBox: TScrollBox);
begin
  if AScrollBox = nil then
    Exit;

  { No DoubleBuffered here, deliberately. TWinControl.SetDoubleBuffered does not
    stop at the scrollbox: it walks the whole child tree and every child window
    ends up DoubleBuffered = True. TWinControl.WMEraseBkgnd then hands a child's
    erase to PerformEraseBackground, which asks the PARENT to erase - and a
    styled parent whose hook is double buffered answers that with nothing at all
    (TStyleHook.WMEraseBkgnd does not paint while FDoubleBuffered is set). A
    child left with an unpainted background is what makes a click on a check box
    or radio button flash for one frame. The forced repaint in the hook above is
    what removes the scroll residue, and it needs no double buffering. }

  { With VertScrollBar.Tracking (set in the .dfm) a thumb drag sends a stream
    of scroll messages, and with Smooth = True the box follows every one of
    them. Deferring to the end of the drag removes most intermediate frames; the
    mouse wheel and the arrow buttons are not affected. }
  AScrollBox.VertScrollBar.Smooth := False;

  MakeLabelsOpaque(AScrollBox);
end;

{ =============================================================================== }

initialization

{ Supersede the stock hook. The engine keeps a list of hook classes per control
  class and instantiates the LAST one registered (Vcl.Styles.pas,
  TStyleEngine.CreateStyleHook), so the default TScrollBoxStyleHook does not
  need unregistering - and unregistering it would raise EStyleEngineException
  on any build where that exact pair is not in the list. The class method is
  used because it works before any style has been set, exactly the way
  Vcl.Forms registers its own hooks. }
TCustomStyleEngine.RegisterStyleHook(TScrollBox, TScrollBoxStyleHookFix);
FHookRegistered := True;

finalization

{ Symmetry with the registration above, the way TScrollBox's class destructor
  unregisters Vcl.Forms' hook. It matters for a host that unloads this unit at
  runtime: a registered class reference must not outlive its unit. }
if FHookRegistered then
  TCustomStyleEngine.UnRegisterStyleHook(TScrollBox, TScrollBoxStyleHookFix);

end.
