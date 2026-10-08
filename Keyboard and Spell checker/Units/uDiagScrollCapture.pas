{
  =============================================================================
  TEMPORARY SCROLL-CAPTURE HARNESS - not part of the product.

  What it is for: the "text breaks / ghosts while the settings area is
  scrolled" report. A screenshot cannot say whether a broken row is one frame
  that the next repaint fixes or a state that stays on screen, and neither can
  a video watched at normal speed. This harness drives the scroll itself, so
  every step of it has a known button-down position and a known timestamp, and
  it grabs the screen twice per step:

      * "blit"  - straight after the scroll message, before the queue has been
                  pumped: exactly the pixels ScrollWindow's bit-blit left,
                  which is the frame a fast drag shows on screen;
      * "paint" - after Application.ProcessMessages, i.e. after every paint the
                  message produced: the frame the user sees once the wheel or
                  the thumb has settled.

  A row that is wrong in "blit" and right in "paint" costs one frame; a row
  that is wrong in "paint" is a defect that survives a repaint. The two frames
  together are what tells those apart, and the two reference frames captured
  through a forced full repaint are the truth each of them is compared against
  afterwards (see tools\scrollcap\analyze.py).

  It is opt-in and inert by default: with AVROCAP unset the unit does nothing
  at all - no timer, no window, no file. Set AVROCAP=1 in the environment to
  arm it. Everything it writes lands in <exe dir>\cap\.

  Configuration (all optional):
    AVROCAP=1              arm the harness
    AVROCAP_STYLE=asis     'dark' | 'light' | 'asis' (default: keep the app's)
    AVROCAP_CAT=2          category index to select (2 = "Global Hotkeys")
    AVROCAP_W / _H         dialog size to pin before capturing (default: as is)
    AVROCAP_POS=0          scroll position the drag starts from
    AVROCAP_STEP=8         pixels per drag step
    AVROCAP_BURST=1        scroll messages sent back-to-back before the queue
                           is pumped - 1 is a slow, deliberate drag, 4 or more
                           is a fast one, where the messages arrive faster
                           than the repaints they ask for
    AVROCAP_DELAY=4000     ms to wait for the app to finish starting
    AVROCAP_SELL=600       ms to let a forced repaint settle before a reference
  =============================================================================
}

unit uDiagScrollCapture;

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
  Vcl.ExtCtrls,
  Vcl.Themes,
  uThemeManager,
  uWindowHandlers,
  ufrmOptions;

const
  { Scroll bar codes, spelled out here so the harness does not depend on which
    unit happens to export them. }
  SB_THUMBTRACK_ = 5;
  SB_ENDSCROLL_  = 8;

type
  TScrollCapRunner = class
  private
    FForm: TfrmOptions;
    FBox: TScrollBox;
    FBmp: TBitmap;
    FManifest: TStringList;
    FSBRect: TRect;
    FSeq: Integer;
    FLastFlushed: Integer;
    FStartTick: UInt64;
    FMaxPos: Integer;
    FAbort: Boolean;
    function Occluded(out AWho: string): Boolean;
    procedure Log(const S: string);
    procedure FlushManifest(AForce: Boolean);
    procedure SaveBmp(Bmp: TBitmap; const APath: string);
    function EnvInt(const Name: string; Def: Integer): Integer;
    function EnvStr(const Name: string; const Def: string): string;
    procedure GrabScreen(const R: TRect; Bmp: TBitmap);
    procedure GrabWindow(AWin: TWinControl; Bmp: TBitmap);
    procedure Snap(const APhase: string; AStep: Integer; AReq: Integer; const AKind: string);
    procedure ForceRepaint;
    procedure GoToPos(APos: Integer);
    procedure Pass(const APhase: string; AFrom, ATo: Integer);
    procedure Setup;
  public
    procedure Tick(Sender: TObject);
  end;

var
  FRunner: TScrollCapRunner;
  FTimer: TTimer;
  FCapDir: string;

function RectToStr(const R: TRect): string; forward;

function TScrollCapRunner.EnvStr(const Name: string; const Def: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    Result := Def;
end;

function TScrollCapRunner.EnvInt(const Name: string; Def: Integer): Integer;
begin
  Result := StrToIntDef(GetEnvironmentVariable(Name), Def);
  if Result <= 0 then
    Result := Def;
end;

{ Last-resort file write. Everything this harness writes goes through here,
  because a diagnostic must not be able to raise: an exception thrown out of a
  message handler lands in Avro's own global handler, which puts a modal "Avro
  Keyboard hit an internal error" dialog on top of the very dialog under test.
  That is exactly what happened the first time this ran - the launcher polls
  avroscroll.txt every 400 ms, the harness rewrote it twice per frame, and the
  collision surfaced as a product error dialog. Retrying briefly turns a
  sharing violation into a delayed write instead. }
function TrySave(Lines: TStringList; const APath: string): Boolean;
var
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to 25 do
  begin
    try
      Lines.SaveToFile(APath);
      Result := True;
      Exit;
    except
      Sleep(20);
    end;
  end;
end;

{ Log lines are few and they are the harness's progress channel, so each one is
  flushed immediately. Frame rows are many, so they go out in batches: the file
  is rewritten a handful of times per pass instead of twice per frame, which
  also removes almost all of the window in which anything else can be holding
  it open. }
procedure TScrollCapRunner.Log(const S: string);
begin
  FManifest.Add('LOG,' + S);
  FlushManifest(True);
end;

procedure TScrollCapRunner.FlushManifest(AForce: Boolean);
begin
  if FManifest = nil then
    Exit;
  if not AForce and ((FSeq - FLastFlushed) < 20) then
    Exit;
  if TrySave(FManifest, FCapDir + 'avroscroll.txt') then
    FLastFlushed := FSeq;
end;

{ Is anything other than this process sitting on top of the capture rectangle?

  The frames are grabbed from the screen, so a window that covers the dialog is
  photographed instead of it - and the capture then describes that window, not
  the dialog. That is not hypothetical: one run was measured while another
  application was in front, and the result was 16 frames of another window's
  pixels, reported as if the settings area had torn everywhere. A measurement
  that cannot tell that apart from a defect is worse than no measurement, so a
  covered frame stops the run instead. }
function TScrollCapRunner.Occluded(out AWho: string): Boolean;
var
  Points: array[0..4] of TPoint;
  I: Integer;
  H: HWND;
  Pid: DWORD;
  Cls: array[0..255] of Char;
begin
  Result := False;
  AWho := '';
  Points[0] := Point((FSBRect.Left + FSBRect.Right) div 2, (FSBRect.Top + FSBRect.Bottom) div 2);
  Points[1] := Point(FSBRect.Left + 4, FSBRect.Top + 4);
  Points[2] := Point(FSBRect.Right - 4, FSBRect.Top + 4);
  Points[3] := Point(FSBRect.Left + 4, FSBRect.Bottom - 4);
  Points[4] := Point(FSBRect.Right - 4, FSBRect.Bottom - 4);

  for I := 0 to High(Points) do
  begin
    H := WindowFromPoint(Points[I]);
    if H = 0 then
      Continue;
    Pid := 0;
    GetWindowThreadProcessId(H, Pid);
    if Pid <> GetCurrentProcessId then
    begin
      Result := True;
      Cls := '';
      GetClassName(H, Cls, SizeOf(Cls));
      AWho := Format('%s at (%d,%d)', [string(PChar(@Cls)), Points[I].X, Points[I].Y]);
      Exit;
    end;
  end;
end;

{ Straight off the screen, never PrintWindow: a styled window answers
  WM_PRINTCLIENT with a blank surface, so a PrintWindow grab would say nothing
  about what the user actually sees. The same reasoning as the older
  uDiagPhoneticPage harness. }
procedure TScrollCapRunner.GrabScreen(const R: TRect; Bmp: TBitmap);
var
  DC: HDC;
  W, H: Integer;
begin
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if (W <= 0) or (H <= 0) then
    Exit;

  Bmp.PixelFormat := pf24bit;
  Bmp.Width := W;
  Bmp.Height := H;

  DC := GetDC(0);
  if DC = 0 then
    Exit;
  try
    BitBlt(Bmp.Canvas.Handle, 0, 0, W, H, DC, R.Left, R.Top, SRCCOPY);
  finally
    ReleaseDC(0, DC);
  end;
end;

procedure TScrollCapRunner.GrabWindow(AWin: TWinControl; Bmp: TBitmap);
var
  R: TRect;
  DC: HDC;
begin
  GetWindowRect(AWin.Handle, R);
  DC := GetWindowDC(AWin.Handle);
  if DC = 0 then
    Exit;
  try
    Bmp.PixelFormat := pf24bit;
    Bmp.Width := R.Right - R.Left;
    Bmp.Height := R.Bottom - R.Top;
    BitBlt(Bmp.Canvas.Handle, 0, 0, Bmp.Width, Bmp.Height, DC, 0, 0, SRCCOPY);
  finally
    ReleaseDC(AWin.Handle, DC);
  end;
end;

{ One frame on disk plus the line that ties it to the scroll position it was
  taken at. The position is read back from the scroll bar rather than assumed
  from the request, so the two are logged separately: if they ever disagree the
  manifest shows it instead of the analysis silently going wrong. }
procedure TScrollCapRunner.Snap(const APhase: string; AStep: Integer;
  AReq: Integer; const AKind: string);
var
  Name: string;
  Actual: Integer;
begin
  Inc(FSeq);
  Actual := FBox.VertScrollBar.Position;
  Name := Format('%s_%03d_%s.bmp', [APhase, AStep, AKind]);

  GrabScreen(FSBRect, FBmp);
  SaveBmp(FBmp, FCapDir + Name);

  { seq,phase,step,kind,req_pos,act_pos,ms,file }
  FManifest.Add(Format('%d,%s,%d,%s,%d,%d,%d,%s',
    [FSeq, APhase, AStep, AKind, AReq, Actual,
     Integer(GetTickCount64 - FStartTick), Name]));
  FlushManifest(False);
end;

{ A frame that cannot be written is not worth stopping the run for, and it is
  definitely not worth raising an exception over: the row is still added to the
  manifest, so the analysis reports the frame as missing rather than silently
  counting it. }
procedure TScrollCapRunner.SaveBmp(Bmp: TBitmap; const APath: string);
var
  Attempt: Integer;
begin
  for Attempt := 1 to 25 do
  begin
    try
      Bmp.SaveToFile(APath);
      Exit;
    except
      Sleep(20);
    end;
  end;
  FManifest.Add('LOG,FRAME-SAVE-FAILED ' + APath);
end;

{ The reference frames are taken through this: a complete invalidate + erase +
  immediate repaint of the box and every child. Whatever a reference frame
  shows is by definition what the controls say the content is, so it is the
  only honest yardstick for "this frame is broken". }
procedure TScrollCapRunner.ForceRepaint;
begin
  RedrawWindow(FBox.Handle, nil, 0,
    RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN or RDW_UPDATENOW);
  Application.ProcessMessages;
  Sleep(StrToIntDef(GetEnvironmentVariable('AVROCAP_SELL'), 600));
  Application.ProcessMessages;
end;

{ Position without a drag: for putting the box where a pass starts. The message
  is the same one a scrollbar sends, so this goes through the same code path as
  a real scroll - setting VertScrollBar.Position directly would skip the hook
  and could leave the harness comparing frames it never produced. }
procedure TScrollCapRunner.GoToPos(APos: Integer);
begin
  SendMessage(FBox.Handle, WM_VSCROLL,
    WPARAM((APos shl 16) or SB_THUMBTRACK_), 0);
  SendMessage(FBox.Handle, WM_VSCROLL, WPARAM(SB_ENDSCROLL_), 0);
  Application.ProcessMessages;
end;

{ One drag. Each step is exactly what a held thumb produces: a WM_VSCROLL with
  SB_THUMBTRACK and the new absolute position, then whatever the app does with
  it. Nothing is slept inside the loop - the frames have to be as close
  together as the app itself makes them, otherwise a ghost that only survives
  one frame would be given time to disappear and the harness would report a
  clean scroll that the user never sees. }
procedure TScrollCapRunner.Pass(const APhase: string; AFrom, ATo: Integer);
var
  Step, Burst, Pos, Idx, Inner: Integer;
  Who: string;
begin
  Step := EnvInt('AVROCAP_STEP', 8);
  if ATo < AFrom then
    Step := -Step;
  Burst := EnvInt('AVROCAP_BURST', 1);

  Pos := AFrom;
  Idx := 0;
  Log(Format('PASS %s from=%d to=%d step=%d burst=%d',
    [APhase, AFrom, ATo, Step, Burst]));

  while ((Step > 0) and (Pos < ATo)) or ((Step < 0) and (Pos > ATo)) do
  begin
    if FAbort then
      Exit;
    Inc(Idx);

    { A burst is what a dragged thumb actually produces: the mouse moves in
      several steps while the box is still painting the first one. No pump
      between them, so the frames the queue has not got to yet can be inspected
      exactly as they are on screen. }
    for Inner := 1 to Burst do
    begin
      Pos := Pos + Step;
      if (Step > 0) and (Pos > ATo) then
        Pos := ATo;
      if (Step < 0) and (Pos < ATo) then
        Pos := ATo;
      SendMessage(FBox.Handle, WM_VSCROLL,
        WPARAM((Pos shl 16) or SB_THUMBTRACK_), 0);
    end;

    if Occluded(Who) then
    begin
      Log('OCCLUDED by ' + Who + ' - the frames after this one are not of the dialog');
      FAbort := True;
      Exit;
    end;

    { Before the queue is pumped: the bit-blit result, with every step of the
      burst already applied to it. }
    Snap(APhase, Idx, Pos, 'blit');

    { After it: everything the scroll asked for has painted. }
    Application.ProcessMessages;
    Snap(APhase, Idx, Pos, 'paint');
  end;

  { The thumb is released. The hook repaints the whole box on this one, so the
    frame right after it is the state the drag is left in. }
  SendMessage(FBox.Handle, WM_VSCROLL, WPARAM(SB_ENDSCROLL_), 0);
  Application.ProcessMessages;
  Snap(APhase, Idx + 1, ATo, 'endscroll');

  { And then one more, after the application has had a chance to do anything it
    does between messages (timers, the deferred save, another paint). If this
    one is still wrong, no amount of waiting fixes it. }
  Sleep(500);
  Application.ProcessMessages;
  Snap(APhase, Idx + 1, ATo, 'settled');
end;

procedure TScrollCapRunner.Setup;
var
  S: string;
  W, H, Cat, Pos, Range, ViewH: Integer;
  Left, Top: Integer;
  P: TPoint;
  R: TRect;
begin
  FCapDir := ExtractFilePath(ParamStr(0)) + 'cap\';
  ForceDirectories(FCapDir);
  FManifest := TStringList.Create;

  S := EnvStr('AVROCAP_STYLE', 'asis');
  if SameText(S, 'dark') then
    TStyleManager.TrySetStyle(APP_STYLE_DARK, False)
  else if SameText(S, 'light') then
    TStyleManager.TrySetStyle(APP_STYLE_LIGHT, False);
  Application.ProcessMessages;
  Sleep(400);

  CheckCreateForm(TfrmOptions, frmOptions, 'frmOptions');
  FForm := frmOptions;
  if FForm = nil then
  begin
    Log('FRMOPTIONS NIL');
    Exit;
  end;

  FForm.Show;
  Application.ProcessMessages;

  { The capture reads the screen, so the dialog has to be the window the screen
    actually shows in that rectangle for the whole run. Topmost for the duration
    is the cheapest way to hold it there; it is put back below where it was
    found as soon as the run is over. }
  SetWindowPos(FForm.Handle, HWND_TOPMOST, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);

  { Pin the dialog at a known place and size: every frame of a run is then the
    same rectangle, and two runs of two builds can be compared pixel for pixel
    without any registration.

    The Y origin is deliberately well below 0: the Avro top bar is a topmost
    window, so a dialog placed anywhere near the top of the screen would be
    partly covered by it and the capture would be of the top bar, not of the
    settings area. It is also kept inside the work area, so nothing is captured
    off screen or under the taskbar. }
  W := StrToIntDef(GetEnvironmentVariable('AVROCAP_W'), 0);
  H := StrToIntDef(GetEnvironmentVariable('AVROCAP_H'), 0);
  if (W <= 0) or (H <= 0) then
  begin
    W := FForm.Width;
    H := FForm.Height;
  end;
  Left := 60;
  Top := 140;
  if Top + H > Screen.WorkAreaRect.Bottom then
    Top := Screen.WorkAreaRect.Bottom - H;
  if Top < 0 then
    Top := 0;
  FForm.SetBounds(Left, Top, W, H);
  FForm.BringToFront;
  SetForegroundWindow(FForm.Handle);
  Application.ProcessMessages;
  Sleep(500);
  Application.ProcessMessages;

  Cat := StrToIntDef(GetEnvironmentVariable('AVROCAP_CAT'), 2);
  if (Cat >= 0) and (Cat < FForm.CategoryTree.Items.Count) then
  begin
    FForm.CategoryTree.Selected := FForm.CategoryTree.Items[Cat];
    FForm.CategoryTreeClick(nil);
  end;
  Application.ProcessMessages;
  Sleep(500);
  Application.ProcessMessages;

  FBox := FForm.ScrollBox2;
  FBmp := TBitmap.Create;

  if not FBox.HandleAllocated then
  begin
    Log('SCROLLBOX2 HAS NO HANDLE');
    Exit;
  end;

  { The capture rectangle is the scroll box's client area in screen
    coordinates. Everything the report is about - the labels, the group boxes,
    the edits - is inside it. }
  P := FBox.ClientToScreen(Point(0, 0));
  FSBRect := Rect(P.X, P.Y, P.X + FBox.ClientWidth, P.Y + FBox.ClientHeight);

  GetWindowRect(FForm.Handle, R);
  ViewH := FBox.ClientHeight;
  Range := FBox.VertScrollBar.Range;
  FMaxPos := Range - ViewH;
  if FMaxPos < 0 then
    FMaxPos := 0;

  Pos := StrToIntDef(GetEnvironmentVariable('AVROCAP_POS'), 0);
  if Pos > FMaxPos then
    Pos := FMaxPos;

  Log(Format('STYLE %s available=%s', [StyleServices.Name, BoolToStr(StyleServices.Available, True)]));
  Log(Format('SCREEN ppi=%d  form=%s', [Screen.PixelsPerInch, RectToStr(R)]));
  Log(Format('SCROLLBOX2 handle=0x%x client=%dx%d at=(%d,%d) range=%d viewH=%d maxpos=%d smooth=%s tracking=%s',
    [FBox.Handle, FBox.ClientWidth, FBox.ClientHeight, P.X, P.Y, Range, ViewH, FMaxPos,
     BoolToStr(FBox.VertScrollBar.Smooth, True),
     BoolToStr(FBox.VertScrollBar.Tracking, True)]));
  Log(Format('CAPTURE rect=%s (screenshot region of every frame)',
    [Format('(%d,%d)-(%d,%d) %dx%d', [FSBRect.Left, FSBRect.Top, FSBRect.Right, FSBRect.Bottom,
      FSBRect.Right - FSBRect.Left, FSBRect.Bottom - FSBRect.Top])]));

  FStartTick := GetTickCount64;

  { A picture of the whole dialog for the report, before anything moves. }
  GrabWindow(FForm, FBmp);
  SaveBmp(FBmp, FCapDir + 'window-start.bmp');

  { The two reference frames. Each is taken through a forced full repaint, so
    whatever it holds is what the controls themselves say the content is - the
    yardstick every captured frame is measured against later. Position 0 covers
    the top of the content, position max covers the bottom, so between them the
    whole scrolled range is described. }
  GoToPos(0);
  ForceRepaint;
  GrabScreen(FSBRect, FBmp);
  SaveBmp(FBmp, FCapDir + 'ref-0.bmp');
  Log('REF ref-0.bmp at pos=0');

  GoToPos(FMaxPos);
  ForceRepaint;
  GrabScreen(FSBRect, FBmp);
  SaveBmp(FBmp, FCapDir + Format('ref-%d.bmp', [FMaxPos]));
  Log(Format('REF ref-%d.bmp at pos=%d', [FMaxPos, FMaxPos]));

  { Where the reported screenshot is: a little way into the page, on the
    "Global Hotkeys" category. }
  GoToPos(Pos);
  ForceRepaint;

  { Down the page, then back up it. A drag in the other direction asks the same
    question of the other edge, and the hook treats the band differently for
    the two signs of the step. }
  Pass('down', Pos, FMaxPos);
  if not FAbort then
    Pass('up', FMaxPos, Pos);

  if not FAbort then
  begin
    GoToPos(Pos);
    ForceRepaint;
    GrabScreen(FSBRect, FBmp);
    SaveBmp(FBmp, FCapDir + 'final.bmp');
    GrabWindow(FForm, FBmp);
    SaveBmp(FBmp, FCapDir + 'window-end.bmp');
    Log(Format('FINAL pos=%d frames=%d', [FBox.VertScrollBar.Position, FSeq]));
  end
  else
  begin
    GrabWindow(FForm, FBmp);
    SaveBmp(FBmp, FCapDir + 'window-at-abort.bmp');
    Log('ABORTED-OCCLUDED - this run measured a window that was on top of the dialog');
  end;

  { Put the z-order back the way it was found. }
  SetWindowPos(FForm.Handle, HWND_NOTOPMOST, 0, 0, 0, 0,
    SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
end;

procedure TScrollCapRunner.Tick(Sender: TObject);
begin
  FTimer.Enabled := False;

  { Nothing may escape this handler. An exception out of a window procedure ends
    up in Avro's own global exception handler, which raises a modal dialog over
    the dialog under test and stops the capture - a failure of the diagnostic
    reported as a failure of the product. Every write is already exception
    proof; this is the second line of defence, and it covers the message
    dispatch inside Application.ProcessMessages as well. }
  try
    try
      Setup;
    except
      on E: Exception do
        Log('EXCEPTION ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    Log('DONE');
    FlushManifest(True);
  end;

  { The harness is done with the process: the run has to end by itself,
    otherwise the launcher has no way to tell a finished capture from a hung
    one. }
  Application.Terminate;
end;

function RectToStr(const R: TRect): string;
begin
  Result := Format('(%d,%d)-(%d,%d) %dx%d',
    [R.Left, R.Top, R.Right, R.Bottom, R.Right - R.Left, R.Bottom - R.Top]);
end;

initialization
  { Inert unless the environment asks for it. This is the whole reason the unit
    can sit in a product build while the defect is being chased. }
  if GetEnvironmentVariable('AVROCAP') = '1' then
  begin
    FRunner := TScrollCapRunner.Create;
    FTimer := TTimer.Create(nil);
    FTimer.Interval := StrToIntDef(GetEnvironmentVariable('AVROCAP_DELAY'), 4000);
    FTimer.OnTimer := FRunner.Tick;
    FTimer.Enabled := True;
  end;

finalization
  if FTimer <> nil then
  begin
    FTimer.Enabled := False;
    FTimer.Free;
  end;
  FRunner.Free;

end.
