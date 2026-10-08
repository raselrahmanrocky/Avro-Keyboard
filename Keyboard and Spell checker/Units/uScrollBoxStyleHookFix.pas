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
  * after a DISCRETE scroll message (one wheel notch, one arrow click, one
    page, one key, and the SB_ENDSCROLL that ends a thumb drag) the whole
    scrollbox, children included, is invalidated and erased - RDW_ERASE is the
    load-bearing flag, because it runs exactly the opaque erase above.

    The continuous part of a thumb drag (SB_THUMBTRACK) gets neither of those
    two. The bit-blit ScrollWindow already performed is what the user sees while
    the thumb is held, and repainting EVERY child after each of those messages
    is what made the text advance in irregular lumps instead of following the
    pointer (see RepaintAfterScroll for the measurements). What it gets instead
    is the one strip the scroll uncovered, painted before the message returns -
    see RepaintUncoveredBand, and the frame captures that made the case for
    painting it immediately rather than leaving it to the next paint.

  Base class note: there is no TScrollingWinControlStyleHook in the VCL. The
  hierarchy is TStyleHook -> TScrollingStyleHook -> TScrollBoxStyleHook, all
  declared in the interface section of Vcl.Forms, and TScrollBoxStyleHook is
  the one for TScrollBox. Deriving from it keeps the styled scrollbar windows
  and the styled border that TScrollingStyleHook provides. (TCustomScrollBox
  does not exist either; TScrollBox derives from TScrollingWinControl.)

  The unit also replaces the VCL's own check-box and radio-button hooks
  (TCheckBoxStyleHookFix / TRadioButtonStyleHookFix below) in two ways:

  * their background is stated instead of asked for. Those two controls are the
    only ones whose client area is not painted by their own hook at all: their
    paint is double buffered, the buffer is a freshly allocated bitmap, and the
    only thing the stock code puts in it is a request to the PARENT to paint -
    which either paints nothing (uninitialised buffer: a solid black bar) or
    paints the parent's own frame and caption into the control, offset by the
    control's position (stray edges and a half-erased caption, in the surface
    colour of the active style). Filling the buffer with the active style's
    surface colour, and nothing else, makes that background deterministic under
    every style - this is the repair for the black bars the Avro Phonetic page
    used to opt out of the style engine to avoid (that opt-out is gone now:
    ufrmPhoneticOptions no longer sets StyleElements = []).
  * their message interception steps aside for a control that paints itself
    (StyleElements without seClient - see the class comment below). The stock
    hook answers every click, every Checked := and every .Enabled := with a
    SetRedraw(False)/SetRedraw(True) pair and a non-erasing invalidate, i.e.
    one suppressed frame and one half-erased repaint per interaction. A control
    that paints itself is given the message and an erasing invalidate instead,
    which is exactly what happens when no custom style is active at all.

  This file documents the scroll smearing fix; see the class comments below for
  the button background and the message take-over.
}

interface

uses
  Winapi.Windows,   // RedrawWindow, InvalidateRect, RDW_*, HWND
  Winapi.Messages,  // WM_VSCROLL, WM_HSCROLL, WM_MOUSEWHEEL, WM_LBUTTON*
  System.Types,     // TRect
  System.Classes,   // TComponent
  Vcl.Controls,     // TControl, TWinControl, seClient
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
    { The scroll positions the last scroll was measured against, so the band a
      scroll just uncovered can be computed without being told what the scroll
      code was. }
    FLastTop: Integer;
    FLastLeft: Integer;
    FHasLast: Boolean;
    function SurfaceColor: TColor;
    procedure RepaintAfterScroll;
    procedure RepaintUncoveredBand;
  strict protected
    procedure PaintBackground(Canvas: TCanvas); override;
    procedure WndProc(var Message: TMessage); override;
  public
    constructor Create(AControl: TWinControl); override;
  end;

  { Backstop for TCheckBox, in two parts.

    1. PaintBackground defines the whole background of the control, so the
       style engine's double-buffered paint always starts from a known surface
       instead of an uninitialised bitmap or a copy of the parent's frame.
    2. WndProc steps out of the way for a control that paints itself
       (StyleElements without seClient). The stock TCheckBoxStyleHook answers
       every mouse message, BM_SETCHECK, CM_ENABLEDCHANGED and VK_SPACE by
       switching the control's redraw off, letting it handle the message with
       redrawing suppressed, switching it back on and then invalidating
       WITHOUT an erase. That is one dropped frame and one half-erased repaint
       per interaction - the flicker a control does not show when no custom
       style is active, because then no hook exists at all. For a control that
       paints itself both parts have to be dropped: the message goes straight
       to the control, and the invalidate that follows asks for an erase, so
       the previous state's glyph and caption are cleared before the new ones
       are drawn.

    Registered for the whole process by this unit's initialization, after
    Vcl.StdCtrls's own registration. The engine looks the hook class up by
    walking up from the control's own class and instantiates the LAST class
    registered for the first class it finds (Vcl.Styles.pas,
    TStyleEngine.HandleMessage), so this supersedes TCheckBox's stock hook
    without touching its registration. }
  TCheckBoxStyleHookFix = class(TCheckBoxStyleHook)
  strict private
    { True while the control is painted by Windows rather than by the style
      engine: TStyleHook.AcceptMessage refuses WM_PAINT, WM_ERASEBKGND and
      WM_CTLCOLOR* as soon as seClient is missing from StyleElements, so every
      paint override of the stock hook is dead code for such a control and
      only the message interception below still has an effect. }
    function NativePaint: Boolean;
  strict protected
    procedure PaintBackground(Canvas: TCanvas); override;
    procedure WndProc(var Message: TMessage); override;
  end;

  { Same for TRadioButton. Its stock hook descends from TCheckBoxStyleHook,
    not from the fix above, so the two overrides are repeated here - that is
    the only way to keep the radio glyphs of the styled case (they come from
    TRadioButtonStyleHook.GetDrawState) while getting the same background and
    the same message take-over. The bodies below say what they do; the reasons
    are in the check-box class comment. }
  TRadioButtonStyleHookFix = class(TRadioButtonStyleHook)
  strict private
    function NativePaint: Boolean;
  strict protected
    procedure PaintBackground(Canvas: TCanvas); override;
    procedure WndProc(var Message: TMessage); override;
  end;

{ The surface colour of the style that is active right now. One resolution rule
  for every hook in this unit, so the scrollbox fill and the button backstop can
  never drift apart. }
function StyleSurfaceColor: TColor;

{ Runtime hygiene for one scrollbox and everything inside it. Call it once the
  control's children exist (end of a form's OnCreate):

    ApplyStyledScrollFix(ScrollBox2);

  It turns off smooth thumb-drag scrolling and makes every TLabel in the
  control tree erase its own background with the style's surface colour. It
  deliberately does NOT enable double buffering - see the implementation for
  what each part is for and why that one is left alone. }
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
  Result := StyleSurfaceColor;
end;

function StyleSurfaceColor: TColor;
begin
  { scPanel is the surface the style paints a scrollbox, a panel and a group box
    with (it is what the stock scrollbox hook erases with, Vcl.Forms.pas:21082,
    and what the parent chain of a check box ends up filling its buffer with).
    If no style is available at all - unreachable for a hook, since the engine
    only calls one while a style is active - the system colour is used instead;
    nothing here is a literal colour. }
  if StyleServices.Available then
    Result := StyleServices.GetStyleColor(scPanel)
  else
    Result := StyleServices.GetSystemColor(clBtnFace);
end;

procedure PaintButtonSurface(AControl: TWinControl; Canvas: TCanvas);
begin
  if (AControl = nil) or not StyleServices.Available then
    Exit;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := StyleSurfaceColor;
  Canvas.FillRect(AControl.ClientRect);
end;

procedure TCheckBoxStyleHookFix.PaintBackground(Canvas: TCanvas);
begin
  { The whole background of a check box, in one statement, with no help asked
    from the parent.

    Why the stock code cannot be reused here (RAD Studio 23.0 sources):
    TStyleHook.WMPaint (Vcl.Themes.pas:7538) paints the control into a fresh
    TBitmap and blits that bitmap over the whole client area, so every pixel
    the paint below does not touch keeps the bitmap's initial content - black.
    There are exactly two things that used to put pixels in it:

      * TStyleHook.WMEraseBkgnd paints nothing at all, because the hook sets
        DoubleBuffered (Vcl.Themes.pas:7617);
      * TCheckBoxStyleHook.PaintBackground (Vcl.StdCtrls.pas:12163) asks
        LStyle.DrawParentBackground for the parent's surface, and for a custom
        style that ends in DrawControlBackground (Vcl.StyleAPI.pas:7012), which
        runs the PARENT's window procedure with a DC whose origin has been
        moved to this control (MoveWindowOrg(DC, -P.X, -P.Y)).

    The parent is a styled window as well - TCustomGroupBox, TCustomForm and
    TScrollBox all have hooks - and TGroupBoxStyleHook.Paint (Vcl.StdCtrls.pas:
    12406) and TFormStyleHook.Paint draw the parent's FRAME and its CAPTION,
    not just a background. Those strokes land in this control's bitmap, offset
    by the control's position inside the parent, so a check box can show a piece
    of the group box's border or of the form's edge across its own caption. A
    link of the chain that paints nothing leaves the untouched bitmap black
    instead. Both are the same defect from either end, and neither can be
    predicted from here.

    Stating the colour ourselves removes the dependency: FillRect below covers
    the control's whole client rect, so the bitmap is fully defined before the
    caption and the glyph are drawn onto it, and nothing else ever writes into
    it. The colour is the active style's surface (StyleSurfaceColor), never a
    literal, so both the light and the dark style keep their own appearance. }
  PaintButtonSurface(Control, Canvas);
end;

function TCheckBoxStyleHookFix.NativePaint: Boolean;
begin
  Result := (Control <> nil) and not (seClient in Control.StyleElements);
end;

procedure TCheckBoxStyleHookFix.WndProc(var Message: TMessage);
var
  OldBounds: TRect;
  OldVisible: Boolean;
begin
  { See the class comment for why these messages are taken over. The set is
    exactly the one the stock hook wraps in SetRedraw(False)/SetRedraw(True) -
    WM_LBUTTONDOWN / WM_LBUTTONUP / WM_LBUTTONDBLCLK / WM_KEYDOWN / WM_KEYUP
    (the last two only for VK_SPACE, which the control itself ignores),
    BM_SETCHECK (what Checked := True sends) and CM_ENABLEDCHANGED (what
    .Enabled := False sends). The control still handles the message itself
    through CallDefaultProc, so nothing about its behaviour changes; only the
    repaint that follows is different, and it is now an invoking one: the
    erasing InvalidateRect below sends WM_ERASEBKGND first, so no part of the
    previous glyph, caption or state colour can survive underneath. }
  if NativePaint then
    case Message.Msg of
      WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK,
      WM_KEYDOWN, WM_KEYUP, BM_SETCHECK, CM_ENABLEDCHANGED:
        begin
          { Only WM_LBUTTONUP can resize or hide the control - the other
            messages never do - so the parent is asked to repaint the old
            rectangle exactly where the stock hook asks for it. }
          OldBounds := Control.BoundsRect;
          OldVisible := Control.Visible;
          CallDefaultProc(Message);
          InvalidateRect(Control.Handle, nil, True);
          if (Message.Msg = WM_LBUTTONUP) and
             ((OldBounds <> Control.BoundsRect) or (OldVisible <> Control.Visible)) and
             (Control.Parent <> nil) then
            InvalidateRect(Control.Parent.Handle, OldBounds, True);
          Handled := True;
          Exit;
        end;
    end;

  { Every other message, and every message of a control that is still painted
    by the style engine, keeps going through the stock chain: TStyleHook's
    WndProc does the drawing and the Dispatch that reaches the stock
    TCheckBoxStyleHook handlers. }
  inherited;
end;

procedure TRadioButtonStyleHookFix.PaintBackground(Canvas: TCanvas);
begin
  { Identical reason as the check-box hook above: TRadioButtonStyleHook derives
    from TCheckBoxStyleHook and inherits the same parent-chain fill. }
  PaintButtonSurface(Control, Canvas);
end;

function TRadioButtonStyleHookFix.NativePaint: Boolean;
begin
  Result := (Control <> nil) and not (seClient in Control.StyleElements);
end;

procedure TRadioButtonStyleHookFix.WndProc(var Message: TMessage);
var
  OldBounds: TRect;
  OldVisible: Boolean;
begin
  { Same take-over as TCheckBoxStyleHookFix.WndProc above; see its comment for
    the whole reasoning. It has to be written out again here because this
    class descends from TRadioButtonStyleHook, not from the check-box fix, and
    the stock handler it replaces (TRadioButtonStyleHook.WndProc) is the one
    that would otherwise reach TCheckBoxStyleHook's SetRedraw wrapper. }
  if NativePaint then
    case Message.Msg of
      WM_LBUTTONDOWN, WM_LBUTTONUP, WM_LBUTTONDBLCLK,
      WM_KEYDOWN, WM_KEYUP, BM_SETCHECK, CM_ENABLEDCHANGED:
        begin
          OldBounds := Control.BoundsRect;
          OldVisible := Control.Visible;
          CallDefaultProc(Message);
          InvalidateRect(Control.Handle, nil, True);
          if (Message.Msg = WM_LBUTTONUP) and
             ((OldBounds <> Control.BoundsRect) or (OldVisible <> Control.Visible)) and
             (Control.Parent <> nil) then
            InvalidateRect(Control.Parent.Handle, OldBounds, True);
          Handled := True;
          Exit;
        end;
    end;
  inherited;
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
    WM_VSCROLL, WM_HSCROLL:
      { The scroll code sits in the low word of WParam: SB_THUMBTRACK while the
        thumb is held, SB_ENDSCROLL when it is released, SB_LINEUP / SB_LINEDOWN
        for a wheel notch or an arrow click, SB_PAGEUP / SB_PAGEDOWN for a page.
        Only the drag itself is skipped; everything else is a step the user
        cannot be in the middle of, and those are the ones the erase is for.
        SB_ENDSCROLL is one of them, so the drag still ends with the box fully
        repainted - see RepaintAfterScroll for why the intermediate ones have
        to go. }
      if Message.WParamLo <> SB_THUMBTRACK then
        RepaintAfterScroll
      else
        { The drag itself. The bit-blit moved the page, but the band the scroll
          uncovered still holds the previous page's pixels - that band is the
          "glued", half-drawn line that shows up against the edge being
          scrolled towards. Repainting only that band keeps the step cheap
          enough to follow the pointer: see RepaintUncoveredBand. }
        RepaintUncoveredBand;
    WM_MOUSEWHEEL:
      RepaintAfterScroll;
  end;
end;

{ Repaint just the strip the scroll uncovered, on the scrollbox and on every
  child that reaches into it. This is what a native scroll does; the difference
  here is that the strip also has to be erased with the style's surface colour,
  which is the whole point of the hook.

  Why not invalidate the whole box instead: every control in a settings page
  paints through the style engine, and TStyleHook.WMPaint rebuilds the control
  into a bitmap the size of the whole control and blits it (Vcl.Themes.pas:7554)
  - so a full invalidation costs a full repaint of the page whatever changed,
  which is what made a drag advance in ~30 Hz lumps. A band only makes the
  controls that intersect the band paint, so a step costs a fraction of that.

  The band is derived from the scroll position rather than from the message, so
  it works for the thumb, the wheel, the arrows, the keys and the touch
  gestures alike.

  RDW_UPDATENOW is the load-bearing flag here, and it is the one thing this
  used to leave out. Without it the strip is only invalidated: ScrollWindow has
  moved the page but the strip still holds the pixels of the content that used
  to be there, and it keeps them until the queue gets around to the WM_PAINT.
  A captured drag says exactly what that looks like on screen - the harness in
  Units\uDiagScrollCapture.pas grabs the frame twice per step, once straight
  after the scroll and once after the queue has been pumped, and every scroll
  step moves the content while leaving a strip of the previous content behind
  it (measured: with four scroll messages per repaint, all 16 "before the queue
  was pumped" frames were wrong, by up to 32 rows spread over up to 5 bands,
  against 0 of 16 "after" frames). That strip IS the "text breaks / half-drawn
  line" that gets reported, the more so the faster the thumb is dragged, and
  nothing short of painting it before this returns can remove it: leaving it to
  the next paint is what produced it.

  Painting the strip now is affordable where painting the whole box was not,
  because the work is bounded by the controls the strip actually crosses rather
  than by the page. The full-box path below stays without RDW_UPDATENOW and
  stays out of the drag for exactly that reason; see its comment. }
procedure TScrollBoxStyleHookFix.RepaintUncoveredBand;
var
  Band: TRect;
  Dy, Dx, Top, Left: Integer;
begin
  if (Control = nil) or not Control.HandleAllocated then
    Exit;
  if not (Control is TScrollBox) then
    Exit;

  Top := TScrollBox(Control).VertScrollBar.Position;
  Left := TScrollBox(Control).HorzScrollBar.Position;

  if not FHasLast then
  begin
    FLastTop := Top;
    FLastLeft := Left;
    FHasLast := True;
    Exit;
  end;

  Dy := Top - FLastTop;
  Dx := Left - FLastLeft;
  FLastTop := Top;
  FLastLeft := Left;

  if Dx <> 0 then
  begin
    if Dx > 0 then
      Band := Rect(Control.ClientWidth - Dx, 0, Control.ClientWidth, Control.ClientHeight)
    else
      Band := Rect(0, 0, -Dx, Control.ClientHeight);
    { RDW_ERASE - the strip gets the style's own surface colour under it before
      anything is drawn on top (see PaintBackground), so no pixel of the old
      content can survive underneath a control that does not cover every row of
      the band.
      RDW_UPDATENOW - paint it now, while the scroll is still being handled,
      instead of leaving the stale pixels on screen until the next WM_PAINT. }
    RedrawWindow(Control.Handle, @Band, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
  end;

  if Dy <> 0 then
  begin
    { A larger position means the page moved up, so the strip that needs the
      new page in it is the one at the bottom, and the other way round. }
    if Dy > 0 then
      Band := Rect(0, Control.ClientHeight - Dy, Control.ClientWidth, Control.ClientHeight)
    else
      Band := Rect(0, 0, Control.ClientWidth, -Dy);
    RedrawWindow(Control.Handle, @Band, 0,
      RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
  end;
end;

procedure TScrollBoxStyleHookFix.RepaintAfterScroll;
begin
  if (Control = nil) or not Control.HandleAllocated then
    Exit;

  { Whatever the band pass above did, this is the state the drag is compared
    against next time; keeping it current here too means a discrete scroll right
    after a drag cannot compute a band from a stale position. }
  if Control is TScrollBox then
  begin
    FLastTop := TScrollBox(Control).VertScrollBar.Position;
    FLastLeft := TScrollBox(Control).HorzScrollBar.Position;
    FHasLast := True;
  end;

  { RDW_INVALIDATE - the whole client area, not just the band the scroll
    invalidated.
    RDW_ERASE      - re-sends WM_ERASEBKGND when the window is repainted,
    which this hook answers with the opaque fill above; this is the flag that
    actually removes a ghost.
    RDW_ALLCHILDREN - takes the category panels and their controls with it;
    TWinControl.ScrollBy moved them without invalidating them.

    RDW_UPDATENOW is deliberately NOT set. It used to be, and it is what made
    the text shimmer while scrolling: it completes the erase and the repaint
    before every single scroll message returns, and the scroll box is built
    with VertScrollBar.Tracking = True, so one thumb drag is a stream of
    WM_VSCROLL messages - a full erase and repaint of the box and of every
    child for each of them, several times per frame. Without it the blit that
    ScrollWindow already performed is what the user sees immediately (so the
    scroll still tracks the thumb), and the invalid region above simply
    accumulates, so Windows merges the whole burst into one erased repaint
    that removes the ghost exactly the same way.

    This is still the expensive path - every control in the page paints through
    the style engine, each into a freshly allocated bitmap - so WndProc keeps it
    out of the continuous part of a drag. Two measurements say so:

      * the reported recording (1111.mp4, 680x510 @ 60 fps, Win64, Windows10Dark)
        shows the settings area advancing in irregular lumps of 2, 2, 4, 5 and
        8 px at roughly 30 updates per second, with 12-20% of the content region
        repainted per update and recorder frames repeated in pairs - one whole
        page repaint per scroll message, which is what the eye reads as the text
        shivering instead of moving. The pixels themselves were fine: apart from
        the newly exposed strip each frame was a clean translation of the one
        before it (best-fit aligned MAD 3.1 of 255).
      * build\scrollprobe (a throwaway probe that loads this same unit and
        scrolls a styled box with the same messages) times one drag step at
        11.7 ms with no residue outside the exposed strip, against 33.2 ms for
        a step that carries the erase and repaint below. The erase is what
        costs 20 ms of it, so at 60 Hz it could never keep up: about 30 steps
        a second is the ceiling with it, which is exactly the rate the video
        shows.

    SB_ENDSCROLL still comes through WndProc, so a drag ends with the full
    erase and repaint and cannot leave anything behind. }
  RedrawWindow(Control.Handle, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN);
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

  { No DoubleBuffered here, deliberately. It would apply to the scrollbox alone
    (TWinControl.SetDoubleBuffered only sets the flag, Vcl.Controls.pas:12138 -
    it does not walk the child tree), and it buys nothing: every control in this
    dialog already paints through the style engine, which builds its own bitmap
    per paint (TStyleHook.WMPaint, Vcl.Themes.pas:7538), so the box's solid
    background fill cannot flicker anyway. What used to flicker was the page,
    and that is what the hook above and ApplyStyledScrollFix below are for. }

  { Smooth = True (set in the .dfm) is not about the thumb: TControlScrollBar
    splits a LINE or PAGE scroll into FLineDiv (4) / FPageDiv (12) animated
    sub-steps and scrolls once per part (Vcl.Forms.pas:3135, 3412). Each part is
    a separate scroll of the whole page, so an arrow click or a wheel notch ends
    up rebuilding the page four times instead of once. False makes it one step;
    thumb tracking and the range are untouched by this (Vcl.Forms.pas:2973,
    IsIncrementStored, is the only other reader). }
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

{ The check-box and radio-button backstops go in after Vcl.StdCtrls' own
  registrations, and the engine instantiates the last hook registered for a
  control class, so these supersede TCheckBoxStyleHook / TRadioButtonStyleHook
  without touching their registration. }
TCustomStyleEngine.RegisterStyleHook(TCheckBox, TCheckBoxStyleHookFix);
TCustomStyleEngine.RegisterStyleHook(TRadioButton, TRadioButtonStyleHookFix);
FHookRegistered := True;

finalization

{ Symmetry with the registrations above, the way TScrollBox's class destructor
  unregisters Vcl.Forms' hook. It matters for a host that unloads this unit at
  runtime: a registered class reference must not outlive its unit. }
if FHookRegistered then
begin
  TCustomStyleEngine.UnRegisterStyleHook(TScrollBox, TScrollBoxStyleHookFix);
  TCustomStyleEngine.UnRegisterStyleHook(TCheckBox, TCheckBoxStyleHookFix);
  TCustomStyleEngine.UnRegisterStyleHook(TRadioButton, TRadioButtonStyleHookFix);
end;

end.
