{
  Custom justified text box for the Unicode to Bijoy converter.

  Draws multi-line text with full justification (both edges aligned).
  GDI's DrawText has no justification flag and TMemo cannot justify,
  so the text is wrapped and word-spaced manually. The control also
  supports text selection by mouse drag and Shift+arrows, typing at
  caret position, Backspace, Enter, Ctrl+V/Ctrl+C/Ctrl+A, a
  right-click menu, mouse-wheel scrolling, a vertical scroll bar
  and caret blinking like MS Word.
}

unit uJustifiedBox;

interface

uses
  Windows, Messages, SysUtils, Math, Classes, Graphics, Controls, Forms,
  StdCtrls, Clipbrd, Menus, Themes, ExtCtrls;

type
  TWordItem = record
    Text: string;
    StartChar: Integer;
    X: Integer;
    Width: Integer;
  end;

  TLineItem = record
    Words: TArray<TWordItem>;
    Y: Integer;
    LineStartChar: Integer;
  end;

  TJustifiedBox = class(TCustomControl)
  private
    FText: string;
    FFont: TFont;
    FScrollPos: Integer;
    FScrollBar: TScrollBar;
    FPopup: TPopupMenu;
    FLayout: TArray<TLineItem>;
    FLayoutHeight: Integer;
    FLayoutWidth: Integer;
    FSpaceW: Integer;
    FLineH: Integer;
    FAnchorChar: Integer;
    FCaretChar: Integer;
    FCaretVisible: Boolean;
    FCaretTimer: TTimer;
    FMouseDown: Boolean;
    FWordDrag: Boolean;
    FLastClickTime: Cardinal;
    FLastClickX, FLastClickY: Integer;
    procedure SelectWordAt(AChar: Integer);
    function WordStartAt(AChar: Integer): Integer;
    function WordEndAt(AChar: Integer): Integer;
    procedure SetFont(Value: TFont);
    procedure SetText(const Value: string);
    function GetTextRect: TRect;
    function GetDrawRect: TRect;
    procedure AddLine(const L: TArray<TWordItem>; LineW: Integer; IsLast: Boolean;
      AY, ALineStartChar, AWidth: Integer);
    procedure BuildLayout(AWidth: Integer);
    function MeasureHeight: Integer;
    function CharToX(AChar: Integer; const Line: TLineItem): Integer;
    function CharAtXOnLine(const Line: TLineItem; AX: Integer): Integer;
    function CharAtPos(X, Y: Integer): Integer;
    function CaretPos(AChar: Integer; out AX, AY: Integer): Boolean;
    function CaretLineIdx(AChar: Integer): Integer;
    function SelectionText: string;
    procedure EnsureVisible(LineIdx: Integer);
    procedure MoveCaretVertically(Dir: Integer; Shift: TShiftState);
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure InsertAtCaret(const S: string);
    procedure DeleteSelection;
    procedure DeleteAtCaret;
    procedure PasteFromClipboard;
    procedure DrawWordText(X, Y: Integer; const S: string; AColor: TColor);
    procedure MenuPaste(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuClear(Sender: TObject);
    procedure MenuSelectAll(Sender: TObject);
    procedure CaretTimer(Sender: TObject);
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Clear;
    property Text: string read FText write SetText;
  published
    property Align;
    property AlignWithMargins;
    property Anchors;
    property Enabled;
    property Font: TFont read FFont write SetFont;
    property Margins;
    property TabOrder;
    property TabStop;
    property Visible;
  end;

implementation

const
  BORDER = 6;
  TEXT_PAD = 10;

function IsWordBreak(Ch: Char): Boolean;
begin
  case Ch of
    ' ', #9, #10, #13:
      Result := True;
  else
    Result := False;
  end;
end;

constructor TJustifiedBox.Create(AOwner: TComponent);
var
  MI: TMenuItem;
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  Cursor := crIBeam;
  FFont := TFont.Create;

  FCaretTimer := TTimer.Create(Self);
  FCaretTimer.Interval := 500;
  FCaretTimer.OnTimer := CaretTimer;
  FCaretTimer.Enabled := False;

  FScrollBar := TScrollBar.Create(Self);
  FScrollBar.Parent := Self;
  FScrollBar.Kind := sbVertical;
  FScrollBar.Align := alRight;
  FScrollBar.Width := 0;
  FScrollBar.TabStop := False;
  FScrollBar.OnChange := ScrollBarChange;

  FPopup := TPopupMenu.Create(Self);
  MI := TMenuItem.Create(FPopup);
  MI.Caption := 'Paste';
  MI.OnClick := MenuPaste;
  FPopup.Items.Add(MI);
  MI := TMenuItem.Create(FPopup);
  MI.Caption := 'Copy';
  MI.OnClick := MenuCopy;
  FPopup.Items.Add(MI);
  MI := TMenuItem.Create(FPopup);
  MI.Caption := 'Select All';
  MI.OnClick := MenuSelectAll;
  FPopup.Items.Add(MI);
  MI := TMenuItem.Create(FPopup);
  MI.Caption := 'Clear';
  MI.OnClick := MenuClear;
  FPopup.Items.Add(MI);
  PopupMenu := FPopup;
end;

destructor TJustifiedBox.Destroy;
begin
  FFont.Free;
  inherited Destroy;
end;

procedure TJustifiedBox.SetFont(Value: TFont);
begin
  FFont.Assign(Value);
  Invalidate;
end;

procedure TJustifiedBox.SetText(const Value: string);
begin
  FText := Value;
  FCaretChar := Length(FText);
  FAnchorChar := FCaretChar;
  FScrollPos := 0;
  UpdateScrollBar;
  Invalidate;
end;

procedure TJustifiedBox.Clear;
begin
  FText := '';
  FScrollPos := 0;
  FAnchorChar := 0;
  FCaretChar := 0;
  UpdateScrollBar;
  Invalidate;
end;

function TJustifiedBox.GetTextRect: TRect;
begin
  Result := ClientRect;
  InflateRect(Result, -BORDER, -BORDER);
  Dec(Result.Right, FScrollBar.Width);
end;

function TJustifiedBox.GetDrawRect: TRect;
begin
  Result := GetTextRect;
  InflateRect(Result, -TEXT_PAD, -TEXT_PAD);
end;

function TJustifiedBox.MeasureHeight: Integer;
begin
  if not HandleAllocated then
    Exit(0);
  BuildLayout(GetDrawRect.Right - GetDrawRect.Left);
  Result := FLayoutHeight;
end;

procedure TJustifiedBox.AddLine(const L: TArray<TWordItem>; LineW: Integer; IsLast: Boolean;
  AY, ALineStartChar, AWidth: Integer);
var
  I, X, Ww, Extra, GapExtra, GapRem: Integer;
begin
  SetLength(FLayout, Length(FLayout) + 1);
  SetLength(FLayout[High(FLayout)].Words, Length(L));
  FLayout[High(FLayout)].Y := AY;
  FLayout[High(FLayout)].LineStartChar := ALineStartChar;
  X := 0;
  if Length(L) > 0 then
  begin
    if IsLast or (Length(L) <= 1) or (AWidth - LineW <= 0) then
    begin
      for I := 0 to High(L) do
      begin
        FLayout[High(FLayout)].Words[I] := L[I];
        FLayout[High(FLayout)].Words[I].X := X;
        Inc(X, L[I].Width + FSpaceW);
      end;
    end
    else
    begin
      Extra := AWidth - LineW;
      GapExtra := Extra div (Length(L) - 1);
      GapRem := Extra mod (Length(L) - 1);
      for I := 0 to High(L) do
      begin
        Ww := L[I].Width;
        FLayout[High(FLayout)].Words[I] := L[I];
        FLayout[High(FLayout)].Words[I].X := X;
        Inc(X, Ww + FSpaceW + GapExtra);
        if I < GapRem then
          Inc(X);
      end;
    end;
  end;
end;

procedure TJustifiedBox.BuildLayout(AWidth: Integer);
var
  P, WordStart, Y, LineW, LineStart: Integer;
  Line: TArray<TWordItem>;
  W: string;
  Ww: Integer;
begin
  Canvas.Font.Assign(FFont);
  FSpaceW := Canvas.TextWidth(' ');
  FLineH := Canvas.TextHeight('W') + 1;
  SetLength(FLayout, 0);
  Y := 0;
  LineStart := 0;
  SetLength(Line, 0);
  LineW := 0;
  P := 1;
  while P <= Length(FText) do
  begin
    if CharInSet(FText[P], [#13, #10]) then
    begin
      AddLine(Line, LineW, True, Y, LineStart, AWidth);
      Inc(Y, FLineH);
      if FText[P] = #13 then
      begin
        Inc(P);
        if (P <= Length(FText)) and (FText[P] = #10) then
          Inc(P);
      end
      else
        Inc(P);
      SetLength(Line, 0);
      LineW := 0;
      LineStart := P - 1;
    end
    else if IsWordBreak(FText[P]) then
      Inc(P)
    else
    begin
      WordStart := P;
      while (P <= Length(FText)) and not IsWordBreak(FText[P]) do
        Inc(P);
      W := Copy(FText, WordStart, P - WordStart);
      Ww := Canvas.TextWidth(W);
      if (Length(Line) > 0) and (LineW + FSpaceW + Ww > AWidth) then
      begin
        AddLine(Line, LineW, False, Y, LineStart, AWidth);
        Inc(Y, FLineH);
        SetLength(Line, 0);
        LineW := 0;
        LineStart := WordStart - 1;
      end;
      SetLength(Line, Length(Line) + 1);
      Line[High(Line)].Text := W;
      Line[High(Line)].StartChar := WordStart - 1;
      Line[High(Line)].Width := Ww;
      if Length(Line) = 1 then
        LineW := Ww
      else
        Inc(LineW, FSpaceW + Ww);
    end;
  end;
  if Length(Line) > 0 then
  begin
    AddLine(Line, LineW, True, Y, LineStart, AWidth);
    Inc(Y, FLineH);
  end;
  FLayoutHeight := Y;
  FLayoutWidth := AWidth;
end;

function TJustifiedBox.CharToX(AChar: Integer; const Line: TLineItem): Integer;
var
  I, NumSpaces, SpaceIdx, GapW, PrevEnd: Integer;
begin
  if Length(Line.Words) = 0 then
    Exit(0);

  if AChar <= Line.Words[0].StartChar then
    Exit(Line.Words[0].X);

  for I := 0 to High(Line.Words) do
  begin
    if (AChar >= Line.Words[I].StartChar) and
       (AChar <= Line.Words[I].StartChar + Length(Line.Words[I].Text)) then
    begin
      Result := Line.Words[I].X + Canvas.TextWidth(Copy(Line.Words[I].Text, 1,
        AChar - Line.Words[I].StartChar));
      Exit;
    end;

    if I < High(Line.Words) then
    begin
      PrevEnd := Line.Words[I].StartChar + Length(Line.Words[I].Text);
      if (AChar > PrevEnd) and (AChar < Line.Words[I + 1].StartChar) then
      begin
        NumSpaces := Line.Words[I + 1].StartChar - PrevEnd;
        SpaceIdx := AChar - PrevEnd;
        GapW := Line.Words[I + 1].X - (Line.Words[I].X + Line.Words[I].Width);
        Result := (Line.Words[I].X + Line.Words[I].Width) +
          Round(GapW * (SpaceIdx / NumSpaces));
        Exit;
      end;
    end;
  end;

  Result := Line.Words[High(Line.Words)].X + Line.Words[High(Line.Words)].Width;
end;

function TJustifiedBox.CharAtXOnLine(const Line: TLineItem; AX: Integer): Integer;
var
  I, K, CharW, PrevCharW, MidX, GapW, NumSpaces, SpaceIdx: Integer;
  WItem: TWordItem;
  PrevEnd: Integer;
begin
  if Length(Line.Words) = 0 then
    Exit(Line.LineStartChar);

  if AX <= Line.Words[0].X then
    Exit(Line.Words[0].StartChar);

  for I := 0 to High(Line.Words) do
  begin
    WItem := Line.Words[I];

    if (AX >= WItem.X) and (AX <= WItem.X + WItem.Width) then
    begin
      PrevCharW := 0;
      for K := 1 to Length(WItem.Text) do
      begin
        CharW := Canvas.TextWidth(Copy(WItem.Text, 1, K));
        MidX := WItem.X + (PrevCharW + CharW) div 2;
        if AX < MidX then
          Exit(WItem.StartChar + K - 1);
        PrevCharW := CharW;
      end;
      Exit(WItem.StartChar + Length(WItem.Text));
    end;

    if I < High(Line.Words) then
    begin
      if (AX > WItem.X + WItem.Width) and (AX < Line.Words[I + 1].X) then
      begin
        GapW := Line.Words[I + 1].X - (WItem.X + WItem.Width);
        PrevEnd := WItem.StartChar + Length(WItem.Text);
        NumSpaces := Line.Words[I + 1].StartChar - PrevEnd;
        if (GapW > 0) and (NumSpaces > 0) then
        begin
          SpaceIdx := Round(((AX - (WItem.X + WItem.Width)) / GapW) * NumSpaces);
          Exit(PrevEnd + SpaceIdx);
        end
        else
          Exit(PrevEnd);
      end;
    end;
  end;

  Exit(Line.Words[High(Line.Words)].StartChar + Length(Line.Words[High(Line.Words)].Text));
end;

function TJustifiedBox.CharAtPos(X, Y: Integer): Integer;
var
  R: TRect;
  ContentX, ContentY, LineIdx, W, Res: Integer;
begin
  R := GetDrawRect;
  W := R.Right - R.Left;
  if (Length(FLayout) = 0) or (FLayoutWidth <> W) then
    BuildLayout(W);

  if Length(FLayout) = 0 then
    Exit(0);

  ContentX := X - R.Left;
  ContentY := Y - R.Top + FScrollPos;

  if ContentY < 0 then
    LineIdx := 0
  else if ContentY >= FLayoutHeight then
    LineIdx := High(FLayout)
  else
  begin
    LineIdx := 0;
    while (LineIdx < High(FLayout)) and (FLayout[LineIdx + 1].Y <= ContentY) do
      Inc(LineIdx);
  end;

  Res := CharAtXOnLine(FLayout[LineIdx], ContentX);
  Result := Res;
end;

procedure TJustifiedBox.EnsureVisible(LineIdx: Integer);
var
  Y, DrawH: Integer;
begin
  if (LineIdx < 0) or (LineIdx > High(FLayout)) then
    Exit;
  Y := FLayout[LineIdx].Y;
  DrawH := GetDrawRect.Bottom - GetDrawRect.Top;
  if Y < FScrollPos then
    FScrollPos := Y
  else if Y + FLineH > FScrollPos + DrawH then
    FScrollPos := Y + FLineH - DrawH;
  UpdateScrollBar;
end;

procedure TJustifiedBox.MoveCaretVertically(Dir: Integer; Shift: TShiftState);
var
  C, LineIdx, X, NewCaret, I: Integer;
begin
  C := FCaretChar;
  if C < 0 then
    C := 0;
  if C > Length(FText) then
    C := Length(FText);
  LineIdx := -1;
  for I := High(FLayout) downto 0 do
    if FLayout[I].LineStartChar <= C then
    begin
      LineIdx := I;
      Break;
    end;
  if LineIdx < 0 then
    Exit;
  X := CharToX(C, FLayout[LineIdx]);
  Inc(LineIdx, Dir);
  if (LineIdx < 0) or (LineIdx > High(FLayout)) then
    Exit;
  NewCaret := CharAtXOnLine(FLayout[LineIdx], X);
  FCaretChar := NewCaret;
  if not (ssShift in Shift) then
    FAnchorChar := NewCaret;
  EnsureVisible(LineIdx);
  Invalidate;
end;

function TJustifiedBox.CaretPos(AChar: Integer; out AX, AY: Integer): Boolean;
var
  I: Integer;
begin
  Result := True;
  if AChar < 0 then
    AChar := 0;
  if AChar > Length(FText) then
    AChar := Length(FText);
  for I := High(FLayout) downto 0 do
  begin
    if FLayout[I].LineStartChar <= AChar then
    begin
      AX := CharToX(AChar, FLayout[I]);
      AY := FLayout[I].Y;
      Exit;
    end;
  end;
  AX := 0;
  AY := 0;
end;

function TJustifiedBox.CaretLineIdx(AChar: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  if AChar < 0 then
    Exit(0);
  if Length(FLayout) = 0 then
    Exit(0);

  for I := High(FLayout) downto 0 do
  begin
    if AChar >= FLayout[I].LineStartChar then
      Exit(I);
  end;
end;

function TJustifiedBox.SelectionText: string;
var
  S1, S2: Integer;
begin
  S1 := Min(FAnchorChar, FCaretChar);
  S2 := Max(FAnchorChar, FCaretChar);
  if S2 > S1 then
    Result := Copy(FText, S1 + 1, S2 - S1)
  else
    Result := '';
end;

procedure TJustifiedBox.UpdateScrollBar;
var
  Total, MaxPos, Page, Clamped: Integer;
begin
  if FScrollBar = nil then
    Exit;
  Total := MeasureHeight;
  Page := GetDrawRect.Bottom - GetDrawRect.Top;
  if Page < 1 then
    Page := 1;
  MaxPos := Total - Page;
  if MaxPos < 0 then
    MaxPos := 0;
  if FScrollPos > MaxPos then
    FScrollPos := MaxPos;
  if FScrollPos < 0 then
    FScrollPos := 0;
  Clamped := Page;
  if Clamped > Total then
    Clamped := Total;
  with FScrollBar do
  begin
    Min := 0;
    PageSize := Clamped;
    Max := Total;
    PageSize := Clamped;
    SmallChange := 24;
    LargeChange := PageSize;
    if Total > Page then
    begin
      Visible := True;
      Width := 16;
    end
    else
    begin
      Visible := False;
      Width := 0;
    end;
    Position := FScrollPos;
  end;
end;

procedure TJustifiedBox.ScrollBarChange(Sender: TObject);
begin
  FScrollPos := FScrollBar.Position;
  Invalidate;
end;

procedure TJustifiedBox.InsertAtCaret(const S: string);
var
  Pos: Integer;
begin
  if S = '' then
    Exit;
  if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
    DeleteSelection;
  Pos := FCaretChar;
  if Pos < 0 then
    Pos := 0;
  if Pos > Length(FText) then
    Pos := Length(FText);
  Insert(S, FText, Pos + 1);
  FAnchorChar := Pos + Length(S);
  FCaretChar := Pos + Length(S);
  UpdateScrollBar;
  Invalidate;
end;

procedure TJustifiedBox.DeleteSelection;
var
  S1, S2: Integer;
begin
  S1 := Min(FAnchorChar, FCaretChar);
  S2 := Max(FAnchorChar, FCaretChar);
  if S2 > S1 then
  begin
    Delete(FText, S1 + 1, S2 - S1);
    FAnchorChar := S1;
    FCaretChar := S1;
    UpdateScrollBar;
    Invalidate;
  end;
end;

procedure TJustifiedBox.DeleteAtCaret;
var
  Pos: Integer;
begin
  if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
  begin
    DeleteSelection;
    Exit;
  end;
  Pos := FCaretChar;
  if Pos <= 0 then
    Exit;
  if (Pos >= 2) and (FText[Pos] = #10) and (FText[Pos - 1] = #13) then
  begin
    Delete(FText, Pos - 1, 2);
    FAnchorChar := Pos - 2;
    FCaretChar := Pos - 2;
  end
  else
  begin
    Delete(FText, Pos, 1);
    FAnchorChar := Pos - 1;
    FCaretChar := Pos - 1;
  end;
  UpdateScrollBar;
  Invalidate;
end;

procedure TJustifiedBox.PasteFromClipboard;
var
  S: string;
begin
  S := Clipboard.AsText;
  if S = '' then
    Exit;
  InsertAtCaret(S);
end;

procedure TJustifiedBox.DrawWordText(X, Y: Integer; const S: string; AColor: TColor);
var
  R: TRect;
begin
  SetTextColor(Canvas.Handle, ColorToRGB(AColor));
  R := Rect(X, Y, X + Canvas.TextWidth(S) + 2, Y + FLineH);
  DrawText(Canvas.Handle, PChar(S), Length(S), R, DT_SINGLELINE or DT_LEFT or DT_NOPREFIX);
end;

procedure TJustifiedBox.MenuPaste(Sender: TObject);
begin
  PasteFromClipboard;
end;

procedure TJustifiedBox.MenuCopy(Sender: TObject);
var
  S: string;
begin
  S := SelectionText;
  if S = '' then
    S := FText;
  Clipboard.AsText := S;
end;

procedure TJustifiedBox.MenuClear(Sender: TObject);
begin
  Clear;
end;

procedure TJustifiedBox.MenuSelectAll(Sender: TObject);
begin
  FAnchorChar := 0;
  FCaretChar := Length(FText);
  Invalidate;
end;

procedure TJustifiedBox.WndProc(var Message: TMessage);
begin
  if Message.Msg = WM_GETDLGCODE then
    Message.Result := DLGC_WANTALLKEYS
  else
    inherited WndProc(Message);
end;

procedure TJustifiedBox.Paint;
var
  R, SelR: TRect;
  Bg, Fg, SelBg, SelFg: TColor;
  I, J, S1, S2, LineEnd, wS, wE, selFrom, selTo, X, preLen, selLen, px, py, SaveIndex: Integer;
  Line: TLineItem;
  WItem: TWordItem;
begin
  BuildLayout(GetDrawRect.Right - GetDrawRect.Left);

  if StyleServices.Enabled then
  begin
    Bg := StyleServices.GetSystemColor(clWindow);
    Fg := StyleServices.GetSystemColor(clWindowText);
    SelBg := StyleServices.GetSystemColor(clHighlight);
    SelFg := StyleServices.GetSystemColor(clHighlightText);
  end
  else
  begin
    Bg := clWindow;
    Fg := clWindowText;
    SelBg := clHighlight;
    SelFg := clHighlightText;
  end;
  if not Enabled then
    Fg := StyleServices.GetSystemColor(clGrayText);

  R := ClientRect;
  Canvas.Pen.Style := psClear;
  Canvas.Brush.Color := Bg;
  Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 16, 16);
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
  Canvas.Brush.Style := bsClear;
  Canvas.RoundRect(R.Left, R.Top, R.Right - 1, R.Bottom - 1, 16, 16);
  Canvas.Brush.Style := bsSolid;

  R := GetDrawRect;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  S1 := Min(FAnchorChar, FCaretChar);
  S2 := Max(FAnchorChar, FCaretChar);
  SaveIndex := SaveDC(Canvas.Handle);
  IntersectClipRect(Canvas.Handle, R.Left, R.Top, R.Right, R.Bottom);

  for I := 0 to High(FLayout) do
  begin
    Line := FLayout[I];
    py := R.Top + Line.Y - FScrollPos;
    if (py + FLineH <= R.Top) or (py >= R.Bottom) then
      Continue;
    if Length(Line.Words) = 0 then
      Continue;
    LineEnd := Line.Words[High(Line.Words)].StartChar +
      Length(Line.Words[High(Line.Words)].Text);

    if (S2 > Line.LineStartChar) and (S1 < LineEnd) then
    begin
      if S1 <= Line.LineStartChar then
        X := 0
      else
        X := CharToX(S1, Line);
      SelR.Left := R.Left + X;
      if S2 >= LineEnd then
        X := Line.Words[High(Line.Words)].X + Line.Words[High(Line.Words)].Width
      else
        X := CharToX(S2, Line);
      SelR.Right := R.Left + X;
      SelR.Top := py;
      SelR.Bottom := py + FLineH;
      Canvas.Brush.Color := SelBg;
      Canvas.FillRect(SelR);
    end;

    for J := 0 to High(Line.Words) do
    begin
      WItem := Line.Words[J];
      wS := WItem.StartChar;
      wE := wS + Length(WItem.Text);
      selFrom := Max(wS, S1);
      selTo := Min(wE, S2);
      X := R.Left + WItem.X;
      if selTo <= selFrom then
        DrawWordText(X, py, WItem.Text, Fg)
      else
      begin
        preLen := selFrom - wS;
        selLen := selTo - selFrom;
        if preLen > 0 then
          DrawWordText(X, py, Copy(WItem.Text, 1, preLen), Fg);
        X := X + Canvas.TextWidth(Copy(WItem.Text, 1, preLen));
        DrawWordText(X, py, Copy(WItem.Text, preLen + 1, selLen), SelFg);
        X := X + Canvas.TextWidth(Copy(WItem.Text, preLen + 1, selLen));
        if preLen + selLen < Length(WItem.Text) then
          DrawWordText(X, py, Copy(WItem.Text, preLen + selLen + 1, Length(WItem.Text) - preLen - selLen), Fg);
      end;
    end;
  end;

  if Focused and FCaretVisible and CaretPos(FCaretChar, px, py) then
  begin
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Color := Fg;
    Canvas.Pen.Width := 1;
    Canvas.MoveTo(R.Left + px + 1, R.Top + py - FScrollPos);
    Canvas.LineTo(R.Left + px + 1, R.Top + py - FScrollPos + FLineH);
    Canvas.Pen.Width := 1;
  end;

  RestoreDC(Canvas.Handle, SaveIndex);

  if Focused then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Style := psDot;
    Canvas.Pen.Color := Fg;
    Canvas.RoundRect(R.Left - TEXT_PAD, R.Top - TEXT_PAD, R.Right + TEXT_PAD, R.Bottom + TEXT_PAD, 16, 16);
  end;
end;

procedure TJustifiedBox.Resize;
begin
  inherited Resize;
  if FScrollBar <> nil then
    UpdateScrollBar;
end;

procedure TJustifiedBox.KeyDown(var Key: Word; Shift: TShiftState);
var
  Wnd: HWND;
  S: string;
  Pos: Integer;
begin
  inherited KeyDown(Key, Shift);
  FCaretTimer.Enabled := True;
  FCaretVisible := True;
  if (Key <> 0) and (ssCtrl in Shift) then
  begin
    case Key of
      Ord('V'), Ord('v'):
        begin
          PasteFromClipboard;
          Key := 0;
        end;
      Ord('C'), Ord('c'):
        begin
          S := SelectionText;
          if S = '' then
            S := FText;
          Clipboard.AsText := S;
          Key := 0;
        end;
      Ord('A'), Ord('a'):
        begin
          FAnchorChar := 0;
          FCaretChar := Length(FText);
          Invalidate;
          Key := 0;
        end;
    end;
  end;
  case Key of
    VK_BACK:
      begin
        DeleteAtCaret;
        Key := 0;
      end;
    VK_DELETE:
      begin
        if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
          DeleteSelection
        else
        begin
          Pos := FCaretChar;
          if (Pos >= 0) and (Pos < Length(FText)) then
          begin
            if (Pos + 1 < Length(FText)) and (FText[Pos + 1] = #13) and (FText[Pos + 2] = #10) then
              Delete(FText, Pos + 1, 2)
            else
              Delete(FText, Pos + 1, 1);
            UpdateScrollBar;
            Invalidate;
          end;
        end;
        Key := 0;
      end;
    VK_LEFT:
      begin
        if FCaretChar > 0 then
          Dec(FCaretChar);
        if not (ssShift in Shift) then
          FAnchorChar := FCaretChar;
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if FCaretChar < Length(FText) then
          Inc(FCaretChar);
        if not (ssShift in Shift) then
          FAnchorChar := FCaretChar;
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_HOME:
      begin
        FCaretChar := 0;
        if not (ssShift in Shift) then
          FAnchorChar := 0;
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_END:
      begin
        FCaretChar := Length(FText);
        if not (ssShift in Shift) then
          FAnchorChar := Length(FText);
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_RETURN:
      begin
        InsertAtCaret(#13#10);
        Key := 0;
      end;
    VK_TAB:
      begin
        Wnd := GetNextDlgTabItem(GetParent(Handle), Handle, ssShift in Shift);
        if Wnd <> 0 then
          Windows.SetFocus(Wnd);
        Key := 0;
      end;
    VK_UP:
      begin
        MoveCaretVertically(-1, Shift);
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_DOWN:
      begin
        MoveCaretVertically(1, Shift);
        EnsureVisible(CaretLineIdx(FCaretChar));
        Invalidate;
        Key := 0;
      end;
    VK_PRIOR:
      begin
        FScrollPos := FScrollPos - FScrollBar.LargeChange;
        UpdateScrollBar;
        Key := 0;
      end;
    VK_NEXT:
      begin
        FScrollPos := FScrollPos + FScrollBar.LargeChange;
        UpdateScrollBar;
        Key := 0;
      end;
  end;
end;

procedure TJustifiedBox.KeyPress(var Key: Char);
begin
  inherited KeyPress(Key);
  if Ord(Key) < 32 then
    Key := #0
  else
  begin
    InsertAtCaret(Key);
    FCaretTimer.Enabled := True;
    FCaretVisible := True;
    Key := #0;
  end;
end;

procedure TJustifiedBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  IsDblClick: Boolean;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SetFocus;
    BuildLayout(GetDrawRect.Right - GetDrawRect.Left);
    IsDblClick := (GetTickCount - FLastClickTime <= GetDoubleClickTime) and
      (Abs(X - FLastClickX) <= GetSystemMetrics(SM_CXDOUBLECLK)) and
      (Abs(Y - FLastClickY) <= GetSystemMetrics(SM_CYDOUBLECLK));
    FLastClickTime := GetTickCount;
    FLastClickX := X;
    FLastClickY := Y;
    FAnchorChar := CharAtPos(X, Y);
    if IsDblClick then
    begin
      SelectWordAt(FAnchorChar);
      FWordDrag := True;
    end
    else
    begin
      FCaretChar := FAnchorChar;
      FWordDrag := False;
    end;
    FMouseDown := True;
    FCaretTimer.Enabled := True;
    FCaretVisible := True;
    Windows.SetCapture(Handle);
    Invalidate;
  end;
end;

procedure TJustifiedBox.SelectWordAt(AChar: Integer);
var
  S, E: Integer;
begin
  if Length(FText) = 0 then
  begin
    FAnchorChar := 0;
    FCaretChar := 0;
    Exit;
  end;
  if AChar < 0 then
    AChar := 0;
  if AChar > Length(FText) then
    AChar := Length(FText);

  if (AChar < Length(FText)) and (FText[AChar + 1] > ' ') and
     not CharInSet(FText[AChar + 1], [#13, #10]) then
  begin
    S := AChar;
    while (S > 0) and (FText[S + 1] > ' ') and not CharInSet(FText[S + 1], [#13, #10]) do
      Dec(S);
    E := AChar;
    while (E < Length(FText)) and (FText[E + 1] > ' ') and not CharInSet(FText[E + 1], [#13, #10]) do
      Inc(E);
  end
  else
  begin
    E := AChar;
    while (E > 0) and ((FText[E + 1] <= ' ') or CharInSet(FText[E + 1], [#13, #10])) do
      Dec(E);
    S := E;
    while (S > 0) and (FText[S + 1] > ' ') and not CharInSet(FText[S + 1], [#13, #10]) do
      Dec(S);
  end;

  FAnchorChar := S;
  FCaretChar := E;
end;

function TJustifiedBox.WordStartAt(AChar: Integer): Integer;
begin
  if AChar < 0 then
    AChar := 0;
  if AChar > Length(FText) then
    AChar := Length(FText);
  while (AChar > 0) and (FText[AChar] > ' ') and not CharInSet(FText[AChar], [#13, #10]) do
    Dec(AChar);
  Result := AChar;
end;

function TJustifiedBox.WordEndAt(AChar: Integer): Integer;
begin
  if AChar < 0 then
    AChar := 0;
  if AChar > Length(FText) then
    AChar := Length(FText);
  while (AChar < Length(FText)) and ((FText[AChar + 1] <= ' ') or CharInSet(FText[AChar + 1], [#13, #10])) do
    Inc(AChar);
  while (AChar < Length(FText)) and (FText[AChar + 1] > ' ') and not CharInSet(FText[AChar + 1], [#13, #10]) do
    Inc(AChar);
  Result := AChar;
end;

procedure TJustifiedBox.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  C: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if FMouseDown then
  begin
    if Y < 0 then
    begin
      FScrollPos := FScrollPos - 16;
      UpdateScrollBar;
    end
    else if Y > ClientHeight then
    begin
      FScrollPos := FScrollPos + 16;
      UpdateScrollBar;
    end;
    if Y < 0 then
      Y := 0
    else if Y > ClientHeight then
      Y := ClientHeight;
    C := CharAtPos(X, Y);
    if FWordDrag then
    begin
      if C >= FAnchorChar then
        FCaretChar := WordEndAt(C)
      else
        FCaretChar := WordStartAt(C);
    end
    else
      FCaretChar := C;
    Invalidate;
  end;
end;

procedure TJustifiedBox.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FMouseDown := False;
    FWordDrag := False;
    Windows.ReleaseCapture;
    Invalidate;
  end;
end;

procedure TJustifiedBox.DoEnter;
begin
  inherited DoEnter;
  FCaretVisible := True;
  FCaretTimer.Enabled := True;
  Invalidate;
end;

procedure TJustifiedBox.DoExit;
begin
  inherited DoExit;
  FCaretTimer.Enabled := False;
  FCaretVisible := False;
  Invalidate;
end;

procedure TJustifiedBox.CaretTimer(Sender: TObject);
begin
  FCaretVisible := not FCaretVisible;
  Invalidate;
end;

function TJustifiedBox.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  FScrollPos := FScrollPos - (WheelDelta div WHEEL_DELTA) * 48;
  UpdateScrollBar;
end;

initialization
  RegisterClass(TJustifiedBox);

end.
