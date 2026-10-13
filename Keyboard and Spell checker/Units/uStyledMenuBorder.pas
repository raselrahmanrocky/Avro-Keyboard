{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uStyledMenuBorder;

{
  Keeps the border of VCL-styled popup menus intact.

  TSysPopupStyleHook paints the styled frame (tmPopupBorders) first and each
  menu item afterwards. The item background is inflated by 2px on every side
  (see TCustomStyleMenuElements.DrawElement, tmPopupBackground), so on
  machines whose menu metrics leave little bottom padding the last item can
  reach the bottom border row of the menu and paint over it - users then
  report the bottom border as "cut off". Which rows of the geometry land
  inside the border depends on the font and menu metrics of the machine,
  which is why the defect appears only on some computers.

  This unit registers a descendant of TSysPopupStyleHook for the system
  popup-menu window class (#32768). After every item has been drawn, the
  edge bands of the freshly rendered frame are stamped back over the border
  area. On machines that already render correctly the stamp copies the very
  pixels that are already there (no visual change); where an item background
  covered the border it restores it.

  Coordinate note: the DC handed to DrawItem comes from GetDC on the menu
  window and, depending on the window geometry (some menus have a one pixel
  non-client edge on top), may cover fewer rows than the frame painted by
  PaintBackground. The frame's bottom border row is always the DC's last
  row, so the vertical offset between frame coordinates and DC coordinates
  is derived as FrameHeight - DCHeight instead of being assumed.

  The frame is rendered once per hook instance into a bitmap and re-rendered
  when the style changes (UpdateColors).

  The same DrawItem also asks the application for a row's trailing badge
  (MenuRowBadge above): an ANSI version row carries the icon of the layout it
  activates on its right, which is the one thing this hook has no way to know.
  The badge is stamped last, so neither the border stamp nor a later item can
  erase it, and the request is answered False for every other row - those rows
  keep exactly the painting this unit inherits.
}

interface

uses
  Winapi.Windows,     // BitBlt, GetClipBox, SRCCOPY
  System.Classes,     // TBitmap
  System.SysUtils,    // FreeAndNil
  System.Types,       // TRect helper
  Vcl.Graphics,
  Vcl.Menus,          // TMenuItem
  Vcl.Themes,         // TCustomStyleEngine, StyleServices
  Vcl.SysStyles;      // TSysPopupStyleHook

type
  { A row that carries a trailing badge of its own - an ANSI version row shows
    the icon of the layout it activates on its right.  This hook knows nothing
    about layouts, so the application installs the painter (uForm1) and the hook
    only asks for it while it paints.  True means the badge was drawn. }
  TMenuRowBadgeFunc = function(ACanvas: TCanvas; const AItemRect: TRect;
    AMenuItem: TMenuItem): Boolean;

var
  { Set by the application; nil leaves every row to the native painting. }
  MenuRowBadge: TMenuRowBadgeFunc = nil;

type
  TStyledMenuBorderHook = class(TSysPopupStyleHook)
  private
    FFrameBitmap: TBitmap;
    FFrameValid: Boolean;
    function FrameBitmap: TBitmap;
    procedure StampBorder(ACanvas: TCanvas);
  protected
    procedure DrawItem(Canvas: TCanvas; Index: Integer; ItemRect: TRect;
      ItemText: string; State: TSysPopupItemState;
      Style: TSysPopupItemStyle); override;
    procedure UpdateColors; override;
  public
    destructor Destroy; override;
  end;

implementation

const
  { The frame border itself is 1px high; the inflated item background may
    reach two rows above it, so three rows cover every reachable overdraw
    without touching item content on machines with normal bottom padding. }
  BottomBandRows = 3;

destructor TStyledMenuBorderHook.Destroy;
begin
  FreeAndNil(FFrameBitmap);
  inherited;
end;

procedure TStyledMenuBorderHook.UpdateColors;
begin
  inherited;
  FFrameValid := False;
end;

function TStyledMenuBorderHook.FrameBitmap: TBitmap;
var
  LRect: TRect;
begin
  if not FFrameValid then
  begin
    if FFrameBitmap = nil then
      FFrameBitmap := TBitmap.Create;
    LRect := SysControl.ClientRect;
    FFrameBitmap.SetSize(LRect.Width, LRect.Height);
    PaintBackground(FFrameBitmap.Canvas);
    FFrameValid := True;
  end;
  Result := FFrameBitmap;
end;

procedure TStyledMenuBorderHook.StampBorder(ACanvas: TCanvas);
var
  LFrame: TBitmap;
  LWidth, LHeight: Integer;
  LClip: TRect;
  LDCRows, LOffset: Integer;
begin
  LWidth := SysControl.Width;
  LHeight := SysControl.Height;
  if (LWidth < 2) or (LHeight < 2) then
    Exit;
  LFrame := FrameBitmap;
  if (LFrame.Width <> LWidth) or (LFrame.Height <> LHeight) then
  begin
    FFrameValid := False; // re-render at the right size on the next call
    Exit;
  end;
  { How many rows of the frame does this DC cover? The frame's bottom border
    row is always the DC's last row (that is the row an item background can
    overwrite), so the offset between frame rows and DC rows follows from
    the clip box. Menus with a one pixel non-client edge report one row less
    than the frame; menus without it report the full height. }
  GetClipBox(ACanvas.Handle, LClip);
  LDCRows := LClip.Bottom - LClip.Top;
  if (LClip.Left <> 0) or (LClip.Top <> 0) or (LDCRows < 2) then
    Exit;
  LOffset := LHeight - LDCRows;
  if (LOffset < 0) or (LOffset > 2) then
    Exit; // unexpected geometry - leave the window alone

  { Bottom band: border row plus the two rows an inflated item background
    can reach, translated into DC coordinates. }
  if LHeight - BottomBandRows - LOffset >= 0 then
    BitBlt(ACanvas.Handle, 0, LHeight - BottomBandRows - LOffset, LWidth,
      BottomBandRows, LFrame.Canvas.Handle, 0, LHeight - BottomBandRows,
      SRCCOPY);
  { Top border row: only exists inside the DC when there is no non-client
    edge; with a non-client edge it is drawn by Windows and unreachable for
    item backgrounds. }
  if LOffset = 0 then
    BitBlt(ACanvas.Handle, 0, 0, LWidth, 1, LFrame.Canvas.Handle, 0, 0,
      SRCCOPY);
  { Left / right border line across the rows the DC covers. }
  BitBlt(ACanvas.Handle, 0, 0, 1, LDCRows, LFrame.Canvas.Handle, 0, LOffset,
    SRCCOPY);
  BitBlt(ACanvas.Handle, LWidth - 1, 0, 1, LDCRows, LFrame.Canvas.Handle,
    LWidth - 1, LOffset, SRCCOPY);
end;

procedure TStyledMenuBorderHook.DrawItem(Canvas: TCanvas; Index: Integer;
  ItemRect: TRect; ItemText: string; State: TSysPopupItemState;
  Style: TSysPopupItemStyle);
var
  Item: TMenuItem;
begin
  // The row itself: the painting of the hook this one descends from.
  inherited;
  StampBorder(Canvas);

  // ...then the trailing badge of a row that carries one, last of all so that
  // nothing painted above can cover it.
  if (not Assigned(MenuRowBadge)) or (Index < 0) or (Index >= Count) then
    Exit;
  Item := Items[Index].VCLMenuItem;
  if Item <> nil then
    MenuRowBadge(Canvas, ItemRect, Item);
end;

initialization

if StyleServices.Available then
  TCustomStyleEngine.RegisterSysStyleHook('#32768', TStyledMenuBorderHook);

end.
