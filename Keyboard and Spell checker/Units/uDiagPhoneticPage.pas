{
  =============================================================================
  TEMPORARY MANUAL-CHECK HARNESS - not part of the product.
  Removed once the Customize dialog has been checked by hand.

  What it does, 3 seconds after the application starts:

    1. selects a VCL style (AVRODIAG_STYLE = light | dark, default light);
    2. opens the Customize dialog and selects the "Avro Phonetic" category;
    3. ticks "Show Preview Window" so the radio buttons and the lower check
       boxes are ENABLED, which is the state they were reported broken in;
    4. scrolls the settings area (AVRODIAG_SCROLL, default 200) so the whole
       "Preview Window and Typing Mode" page and the "Auto correct options"
       group box are on screen together;
    5. writes a structural and pixel report to build\avrocheck.txt and a
       window capture to build\avrocheck-<style>.bmp;
    6. writes DONE and then keeps out of the way: the dialog stays open, the
       application stays running, and every control can be clicked, scrolled
       and restyled by hand.

  Nothing here is killed by the launcher - close the dialog and the tray icon
  when the manual check is finished.
  =============================================================================
}

unit uDiagPhoneticPage;

interface

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Types,
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Themes,
  uThemeManager,
  uWindowHandlers,
  ufrmOptions;

type
  TDiagRunner = class
  private
    FForm: TfrmOptions;
    FWatching: Boolean;
    FWatchDark: Boolean;
    procedure Setup;
    procedure Pass(const AStyleName: string);
    function FinalStyle: string;
  public
    procedure Tick(Sender: TObject);
  end;

var
  FRunner: TDiagRunner;
  FTimer: TTimer;
  FLog: TStringList;
  FOutDir: string;

procedure L(const S: string);
begin
  FLog.Add(S);
  FLog.SaveToFile(FOutDir + 'avrocheck.txt');
end;

function RectStr(const R: TRect): string;
begin
  Result := Format('(%d,%d)-(%d,%d) %dx%d',
    [R.Left, R.Top, R.Right, R.Bottom, R.Right - R.Left, R.Bottom - R.Top]);
end;

function SEStr(const ASet: TStyleElements): string;
begin
  Result := '';
  if seFont in ASet then Result := Result + 'seFont ';
  if seClient in ASet then Result := Result + 'seClient ';
  if seBorder in ASet then Result := Result + 'seBorder ';
  Result := Trim(Result);
  if Result = '' then Result := 'EMPTY';
end;

function FileTag(const ATag: string): string;
var
  I: Integer;
begin
  Result := ATag;
  for I := 1 to Length(Result) do
    if Result[I] = ' ' then
      Result[I] := '-';
end;

function ColorStr(C: TColor): string;
begin
  Result := Format('%02X%02X%02X',
    [GetRValue(ColorToRGB(C)), GetGValue(ColorToRGB(C)), GetBValue(ColorToRGB(C))]);
end;

{ Grab the dialog straight off the screen. PrintWindow is deliberately not used
  here: a styled window answers WM_PRINTCLIENT with a blank white surface, so
  its result says nothing about what the user sees. }
procedure GrabTo(AForm: TWinControl; Bmp: TBitmap);

  procedure DoCopy(DC: HDC; Bmp: TBitmap; W, H: Integer);
  begin
    Bmp.PixelFormat := pf24bit;
    Bmp.Width := W;
    Bmp.Height := H;
    BitBlt(Bmp.Canvas.Handle, 0, 0, W, H, DC, 0, 0, SRCCOPY);
  end;

var
  Rc: TRect;
  DC: HDC;
begin
  GetWindowRect(AForm.Handle, Rc);
  DC := GetWindowDC(AForm.Handle);
  if DC = 0 then
    Exit;
  try
    DoCopy(DC, Bmp, Rc.Right - Rc.Left, Rc.Bottom - Rc.Top);
  finally
    ReleaseDC(AForm.Handle, DC);
  end;
end;

{ Pixel statistics over a region of a grabbed bitmap, in bitmap coordinates:
  how much of the region is the surface colour, how many pixels are ink (the
  glyph and the caption) and which rows carry that ink. A blank control, a
  black bar and a half-erased caption all look different here. }
procedure AnalyzeRegion(Bmp: TBitmap; const R: TRect; const ATag: string);
var
  X, Y: Integer;
  P: PRGBTriple;
  C: Cardinal;
  R2: TRect;
  N, Ink, Surf, White, Black: Integer;
  FirstInk, LastInk: Integer;
  SurfColor: Cardinal;
begin
  R2 := R;
  if R2.Left < 0 then R2.Left := 0;
  if R2.Top < 0 then R2.Top := 0;
  if R2.Right > Bmp.Width then R2.Right := Bmp.Width;
  if R2.Bottom > Bmp.Height then R2.Bottom := Bmp.Height;
  if (R2.Right <= R2.Left) or (R2.Bottom <= R2.Top) then
  begin
    L(Format('%-28s OFFSCREEN req=%s', [ATag, RectStr(R)]));
    Exit;
  end;

  { The surface the active style paints these controls on. Ink is anything
    that is clearly darker than it (the glyph frame) or clearly lighter (a
    light-on-dark style's caption). }
  if StyleServices.Available then
    SurfColor := ColorToRGB(StyleServices.GetStyleColor(scPanel))
  else
    SurfColor := ColorToRGB(clBtnFace);

  N := 0; Ink := 0; Surf := 0; White := 0; Black := 0;
  FirstInk := -1; LastInk := -1;
  for Y := R2.Top to R2.Bottom - 1 do
  begin
    P := Bmp.ScanLine[Y];
    Inc(P, R2.Left);
    for X := R2.Left to R2.Right - 1 do
    begin
      C := (Cardinal(P.rgbtRed) shl 16) or (Cardinal(P.rgbtGreen) shl 8) or P.rgbtBlue;
      if C = SurfColor then
        Inc(Surf)
      else
      begin
        Inc(Ink);
        if FirstInk < 0 then FirstInk := Y;
        LastInk := Y;
      end;
      if C = $FFFFFF then Inc(White);
      if C = $000000 then Inc(Black);
      Inc(N);
      Inc(P);
    end;
  end;

  L(Format('%-28s %s n=%-6d ink=%-5d(%2d%%) surf=%-5d white=%-5d black=%-5d inkRows=%d..%d',
    [ATag, RectStr(R2), N, Ink, (Ink * 100) div N, Surf, White, Black,
     FirstInk, LastInk]));
end;

procedure DumpPage(AForm: TfrmOptions; const ATag: string);
var
  GB: TGroupBox;
  Page: TWinControl;
  I: Integer;
  C: TControl;
  P: TPoint;
  R: TRect;
  Bmp: TBitmap;
  WndRc: TRect;
  Org: TPoint;
begin
  L('--- REPORT ' + ATag + ' ---');
  L(Format('SCREEN ppi=%d  style=%s  available=%s',
    [Screen.PixelsPerInch, StyleServices.Name,
     BoolToStr(StyleServices.Available, True)]));

  GB := AForm.GroupBox3;
  L(Format('GB3 bounds=%s client=%s  GB7 bounds=%s',
    [RectStr(GB.BoundsRect), RectStr(GB.ClientRect), RectStr(AForm.GroupBox7.BoundsRect)]));
  L(Format('ScrollBox2 client=%s  vpos=%d range=%d',
    [RectStr(AForm.ScrollBox2.ClientRect),
     AForm.ScrollBox2.VertScrollBar.Position, AForm.ScrollBox2.VertScrollBar.Range]));

  if GB.ControlCount = 0 then
  begin
    L('GB3 HAS NO CHILDREN - the page was not created');
    Exit;
  end;
  Page := TWinControl(GB.Controls[0]);
  L(Format('PAGE cls=%s bounds=%s visible=%s se=[%s]',
    [Page.ClassName, RectStr(Page.BoundsRect), BoolToStr(Page.Visible, True),
     SEStr(Page.StyleElements)]));

  Bmp := TBitmap.Create;
  try
    GrabTo(AForm, Bmp);
    GetWindowRect(AForm.Handle, WndRc);
    Org := TPoint.Create(WndRc.Left, WndRc.Top);
    Bmp.SaveToFile(FOutDir + 'avrocheck-' + FileTag(ATag) + '.bmp');
    L(Format('CAPTURE avrocheck-%s.bmp window=%s bmp=%dx%d',
      [FileTag(ATag), RectStr(WndRc), Bmp.Width, Bmp.Height]));

    P := Page.ClientToScreen(Point(0, 0));
    R := Rect(P.X - Org.X, P.Y - Org.Y, P.X - Org.X + Page.Width, P.Y - Org.Y + Page.Height);
    AnalyzeRegion(Bmp, R, 'page');

    L(Format('PAGE children=%d', [Page.ControlCount]));
    for I := 0 to Page.ControlCount - 1 do
    begin
      C := Page.Controls[I];
      L(Format('  %-24s %-14s L=%-4d T=%-4d W=%-4d H=%-3d se=[%s] enabled=%s',
        [C.Name, C.ClassName, C.Left, C.Top, C.Width, C.Height,
         SEStr(C.StyleElements), BoolToStr(C.Enabled, True)]));
      P := C.ClientToScreen(Point(0, 0));
      R := Rect(P.X - Org.X, P.Y - Org.Y, P.X - Org.X + C.Width, P.Y - Org.Y + C.Height);
      AnalyzeRegion(Bmp, R, '   ' + C.Name);
    end;

    { The two check boxes outside the embedded page, in the "Auto correct
      options" group box, which were the other two the report marked. }
    for I := 0 to 2 do
    begin
      case I of
        0: C := AForm.CheckAutoCorrect;
        1: C := AForm.CheckEnableJoNukta;
      else
        C := AForm.CheckPipeToDot;
      end;
      P := C.ClientToScreen(Point(0, 0));
      R := Rect(P.X - Org.X, P.Y - Org.Y, P.X - Org.X + C.Width, P.Y - Org.Y + C.Height);
      AnalyzeRegion(Bmp, R, '   ' + C.Name + ' (GB7)');
    end;
  finally
    Bmp.Free;
  end;
  L('--- END REPORT ---');
end;

function TDiagRunner.FinalStyle: string;
begin
  { Where the dialog is left for the manual check. }
  if SameText(GetEnvironmentVariable('AVRODIAG_STYLE'), 'dark') then
    Result := APP_STYLE_DARK
  else
    Result := APP_STYLE_LIGHT;
end;

procedure TDiagRunner.Setup;
var
  ScrollTo: Integer;
begin
  ScrollTo := StrToIntDef(GetEnvironmentVariable('AVRODIAG_SCROLL'), 200);

  CheckCreateForm(TfrmOptions, frmOptions, 'frmOptions');
  FForm := frmOptions;
  if FForm = nil then
    Exit;
  FForm.Show;
  Application.ProcessMessages;
  Sleep(500);
  Application.ProcessMessages;

  if FForm.CategoryTree.Items.Count > 3 then
  begin
    FForm.CategoryTree.Selected := FForm.CategoryTree.Items[3];
    FForm.CategoryTreeClick(nil);
  end;
  Application.ProcessMessages;
  Sleep(300);

  { The state the page was reported broken in: the preview window option is on,
    so the radio buttons and the lower check boxes are ENABLED. }
  FForm.CheckShowPrevWindow.Checked := True;
  FForm.CheckShowPrevWindowClick(nil);
  Application.ProcessMessages;
  Sleep(300);

  { Scroll so the whole "Preview Window and Typing Mode" page and the
    "Auto correct options" group box are on screen together. }
  FForm.ScrollBox2.Perform(WM_VSCROLL, WPARAM(SB_BOTTOM), 0);
  FForm.ScrollBox2.VertScrollBar.Position := ScrollTo;
  Application.ProcessMessages;
  Sleep(500);
  Application.ProcessMessages;
end;

{ Applies one VCL style to the WINDOW THAT IS ALREADY ON SCREEN, lets it
  restyle, and reports what it looks like. Doing this twice in a row is the
  visible part of the harness: the dialog repaints itself under a different
  custom style in front of the person watching, which is exactly the paint and
  repaint path the report is about. }
procedure TDiagRunner.Pass(const AStyleName: string);
begin
  if FForm = nil then
    Exit;
  L('===== setting style ' + AStyleName + ' =====');
  if not TStyleManager.TrySetStyle(AStyleName, False) then
    L('!!! TrySetStyle failed for ' + AStyleName);
  Application.ProcessMessages;
  Sleep(600);
  Application.ProcessMessages;

  RedrawWindow(FForm.Handle, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
  Sleep(400);
  Application.ProcessMessages;

  DumpPage(FForm, AStyleName);
end;

procedure TDiagRunner.Tick(Sender: TObject);
begin
  if FWatching then
  begin
    { AVRODIAG_WATCH=1 keeps the dialog open and flips the style every five
      seconds, so the restyle can be watched for as long as wanted. }
    FWatchDark := not FWatchDark;
    if FWatchDark then
      TStyleManager.TrySetStyle(APP_STYLE_DARK, False)
    else
      TStyleManager.TrySetStyle(APP_STYLE_LIGHT, False);
    Exit;
  end;

  FTimer.Enabled := False;
  FLog.Clear;
  L('MANUAL CHECK START - the dialog stays open, nothing is closed by the harness');
  try
    Setup;
    if FForm = nil then
      L('frmOptions IS NIL')
    else
    begin
      { The demonstration: light, then dark, then the style it is left in. }
      Pass(APP_STYLE_LIGHT);
      Pass(APP_STYLE_DARK);
      if not SameText(FinalStyle, APP_STYLE_DARK) then
        Pass(APP_STYLE_LIGHT)
      else
        Pass(APP_STYLE_DARK);
      L(Format('LEFT OPEN WITH style=%s available=%s',
        [StyleServices.Name, BoolToStr(StyleServices.Available, True)]));

      if GetEnvironmentVariable('AVRODIAG_WATCH') = '1' then
      begin
        FWatching := True;
        FWatchDark := SameText(StyleServices.Name, APP_STYLE_DARK);
        FTimer.Interval := 5000;
        FTimer.Enabled := True;
        L('WATCH MODE: the style flips every 5 seconds. Close the dialog to stop looking.');
      end;
    end;
  except
    on E: Exception do
      L('EXCEPTION ' + E.ClassName + ': ' + E.Message);
  end;
  L('DONE');
end;

initialization
  FOutDir := ExtractFilePath(ParamStr(0));
  FLog := TStringList.Create;
  FRunner := TDiagRunner.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 3000;
  FTimer.OnTimer := FRunner.Tick;
  FTimer.Enabled := True;

finalization
  FTimer.Enabled := False;
  FTimer.Free;
  FRunner.Free;
  FLog.Free;

end.
