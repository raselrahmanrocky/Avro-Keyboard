{
  Custom justified text box for the Unicode to Bijoy converter.

  Draws multi-line text with full justification (both edges aligned).
  GDI's DrawText has no justification flag and TMemo cannot justify,
  so the text is wrapped and word-spaced manually. The control also
  supports text selection by mouse drag and Shift+arrows, typing
  (append at end), Backspace, Enter, Ctrl+V/Ctrl+C/Ctrl+A, a
  right-click menu, mouse-wheel scrolling and a vertical scroll bar.
}

unit uJustifiedBox;

interface

uses
  Windows, Messages, SysUtils, Math, Classes, Graphics, Controls, Forms,
  StdCtrls, Clipbrd, Menus, Themes;

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
    FMouseDown: Boolean;
    procedure SetFont(Value: TFont);
    procedure SetText(const Value: string);
    function GetTextRect: TRect;
    function GetDrawRect: TRect;
    procedure AddLine(const L: TArray<TWordItem>; LineW: Integer; IsLast: Boolean;
      AY, ALineStartChar, AWidth: Integer);
    procedure BuildLayout(AWidth: Integer);
    function MeasureHeight: Integer;
    function CharToX(AChar: Integer; const Line: TLineItem): Integer;
    function CharAtPos(X, Y: Integer): Integer;
    function CaretPos(AChar: Integer; out AX, AY: Integer): Boolean;
    function SelectionText: string;
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure Append(const S: string);
    procedure DeleteSelection;
    procedure DeleteLastChar;
    procedure PasteFromClipboard;
    procedure DrawWordText(X, Y: Integer; const S: string; AColor: TColor);
    procedure MenuPaste(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuClear(Sender: TObject);
    procedure MenuSelectAll(Sender: TObject);
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

constructor TJustifiedBox.Create(AOwner: TComponent);
var
  MI: TMenuItem;
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  TabStop := True;
  Cursor := crIBeam;
  FFont := TFont.Create;

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
  FAnchorChar := 0;
  FCaretChar := Length(FText);
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
    else if FText[P] = ' ' then
      Inc(P)
    else
    begin
      WordStart := P;
      while (P <= Length(FText)) and not CharInSet(FText[P], [' ', #13, #10]) do
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
  I: Integer;
begin
  if Length(Line.Words) = 0 then
    Exit(0);
  for I := 0 to High(Line.Words) do
  begin
    if AChar < Line.Words[I].StartChar + Length(Line.Words[I].Text) then
    begin
      Result := Line.Words[I].X + Canvas.TextWidth(Copy(Line.Words[I].Text, 1,
        Max(0, AChar - Line.Words[I].StartChar)));
      Exit;
    end;
  end;
  Result := Line.Words[High(Line.Words)].X + Line.Words[High(Line.Words)].Width;
end;

function TJustifiedBox.CharAtPos(X, Y: Integer): Integer;
var
  R: TRect;
  ContentX, ContentY, LineIdx, W: Integer;
  WItem: TWordItem;
  I: Integer;
begin
  Result := Length(FText);
  R := GetDrawRect;
  W := R.Right - R.Left;
  if (Length(FLayout) = 0) or (FLayoutWidth <> W) then
    BuildLayout(W);
  ContentX := X - R.Left;
  ContentY := Y - R.Top + FScrollPos;
  if ContentY <= 0 then
    Exit(0);
  if ContentY >= FLayoutHeight then
    Exit(Length(FText));
  LineIdx := ContentY div FLineH;
  if LineIdx > High(FLayout) then
    Exit(Length(FText));
  with FLayout[LineIdx] do
  begin
    if Length(Words) = 0 then
      Exit(LineStartChar);
    if ContentX < Words[0].X then
      Exit(Words[0].StartChar);
    for I := 0 to High(Words) do
    begin
      WItem := Words[I];
      if ContentX <= WItem.X + WItem.Width then
      begin
        Result := WItem.StartChar;
        while (Result - WItem.StartChar < Length(WItem.Text)) and
          (Canvas.TextWidth(Copy(WItem.Text, 1, Result - WItem.StartChar + 1)) <
           ContentX - WItem.X) do
          Inc(Result);
        Exit;
      end;
    end;
    Exit(Words[High(Words)].StartChar + Length(Words[High(Words)].Text));
  end;
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

procedure TJustifiedBox.Append(const S: string);
begin
  if S = '' then
    Exit;
  if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
    DeleteSelection;
  FText := FText + S;
  FAnchorChar := Length(FText);
  FCaretChar := Length(FText);
  FScrollPos := MaxInt;
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

procedure TJustifiedBox.DeleteLastChar;
begin
  if FText = '' then
    Exit;
  if (Length(FText) >= 2) and (FText[Length(FText) - 1] = #13) and (FText[Length(FText)] = #10) then
    Delete(FText, Length(FText) - 1, 2)
  else
    Delete(FText, Length(FText), 1);
  FAnchorChar := Length(FText);
  FCaretChar := Length(FText);
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
  Append(S);
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
      if SelR.Right > SelR.Left then
      begin
        SelR.Top := py;
        SelR.Bottom := py + FLineH;
        Canvas.Brush.Color := SelBg;
        Canvas.FillRect(SelR);
      end;
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
        selLen := selTo - wS;
        if preLen > 0 then
          DrawWordText(X, py, Copy(WItem.Text, 1, preLen), Fg);
        X := X + Canvas.TextWidth(Copy(WItem.Text, 1, preLen));
        DrawWordText(X, py, Copy(WItem.Text, preLen + 1, selLen), SelFg);
        X := X + Canvas.TextWidth(Copy(WItem.Text, preLen + 1, selLen));
        if selLen < Length(WItem.Text) then
          DrawWordText(X, py, Copy(WItem.Text, selLen + 1, Length(WItem.Text) - selLen), Fg);
      end;
    end;
  end;

  if Focused and CaretPos(FCaretChar, px, py) then
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
begin
  inherited KeyDown(Key, Shift);
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
        if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
          DeleteSelection
        else
          DeleteLastChar;
        Key := 0;
      end;
    VK_DELETE:
      begin
        if Min(FAnchorChar, FCaretChar) < Max(FAnchorChar, FCaretChar) then
          DeleteSelection;
        Key := 0;
      end;
    VK_LEFT:
      begin
        if FCaretChar > 0 then
          Dec(FCaretChar);
        if not (ssShift in Shift) then
          FAnchorChar := FCaretChar;
        Invalidate;
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if FCaretChar < Length(FText) then
          Inc(FCaretChar);
        if not (ssShift in Shift) then
          FAnchorChar := FCaretChar;
        Invalidate;
        Key := 0;
      end;
    VK_HOME:
      begin
        FCaretChar := 0;
        if not (ssShift in Shift) then
          FAnchorChar := 0;
        Invalidate;
        Key := 0;
      end;
    VK_END:
      begin
        FCaretChar := Length(FText);
        if not (ssShift in Shift) then
          FAnchorChar := Length(FText);
        Invalidate;
        Key := 0;
      end;
    VK_RETURN:
      begin
        Append(#13#10);
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
        FScrollPos := FScrollPos - FScrollBar.SmallChange;
        UpdateScrollBar;
        Key := 0;
      end;
    VK_DOWN:
      begin
        FScrollPos := FScrollPos + FScrollBar.SmallChange;
        UpdateScrollBar;
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
    Append(Key);
    Key := #0;
  end;
end;

procedure TJustifiedBox.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    SetFocus;
    BuildLayout(GetDrawRect.Right - GetDrawRect.Left);
    FAnchorChar := CharAtPos(X, Y);
    FCaretChar := FAnchorChar;
    FMouseDown := True;
    Windows.SetCapture(Handle);
    Invalidate;
  end;
end;

procedure TJustifiedBox.MouseMove(Shift: TShiftState; X, Y: Integer);
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
    FCaretChar := CharAtPos(X, Y);
    Invalidate;
  end;
end;

procedure TJustifiedBox.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FMouseDown := False;
    Windows.ReleaseCapture;
    Invalidate;
  end;
end;

procedure TJustifiedBox.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TJustifiedBox.DoExit;
begin
  inherited DoExit;
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
