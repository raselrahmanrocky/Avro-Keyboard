{
  Custom justified text box for the Unicode to Bijoy converter.

  Draws multi-line text with full justification (both edges aligned).
  GDI's DrawText has no justification flag and TMemo cannot justify,
  so the text is wrapped and word-spaced manually. The control also
  supports typing (append at end), Backspace, Enter, Ctrl+V/Ctrl+C,
  a right-click menu, mouse-wheel scrolling and a vertical scroll bar.
}

unit uJustifiedBox;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  StdCtrls, Clipbrd, Menus, Themes;

type
  TJustifiedBox = class(TCustomControl)
  private
    FText: string;
    FFont: TFont;
    FScrollPos: Integer;
    FScrollBar: TScrollBar;
    FPopup: TPopupMenu;
    procedure SetFont(Value: TFont);
    procedure SetText(const Value: string);
    function GetTextRect: TRect;
    function MeasureHeight: Integer;
    function MeasureAndDraw(ADraw: Boolean; ARect: TRect; YOffset: Integer): Integer;
    procedure UpdateScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure Append(const S: string);
    procedure DeleteLastChar;
    procedure PasteFromClipboard;
    procedure MenuPaste(Sender: TObject);
    procedure MenuCopy(Sender: TObject);
    procedure MenuClear(Sender: TObject);
  protected
    procedure WndProc(var Message: TMessage); override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
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
  BORDER = 3;

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
  UpdateScrollBar;
  Invalidate;
end;

procedure TJustifiedBox.Clear;
begin
  FText := '';
  FScrollPos := 0;
  UpdateScrollBar;
  Invalidate;
end;

function TJustifiedBox.GetTextRect: TRect;
begin
  Result := ClientRect;
  InflateRect(Result, -BORDER, -BORDER);
  Dec(Result.Right, FScrollBar.Width);
end;

function TJustifiedBox.MeasureHeight: Integer;
begin
  if not HandleAllocated then
    Exit(0);
  Result := MeasureAndDraw(False, GetTextRect, 0);
end;

function TJustifiedBox.MeasureAndDraw(ADraw: Boolean; ARect: TRect; YOffset: Integer): Integer;
var
  Paras: TArray<string>;
  Words: TArray<string>;
  Line: TArray<string>;
  ParaIdx, I: Integer;
  W: string;
  SpaceW, LineH, AvailW, LineW, Ww, Y: Integer;

  procedure FlushLine(const L: TArray<string>; LCount, LWidth: Integer; IsLast: Boolean);
  var
    I, X, Ww, Extra, GapExtra, GapRem: Integer;
    R: TRect;
  begin
    if ADraw and (Y + YOffset + LineH > ARect.Top) and (Y + YOffset < ARect.Bottom) then
    begin
      X := 0;
      if IsLast or (LCount <= 1) then
      begin
        for I := 0 to LCount - 1 do
        begin
          Ww := Canvas.TextWidth(L[I]);
          R := Rect(ARect.Left + X, ARect.Top + Y + YOffset,
                    ARect.Left + X + Ww + 2, ARect.Top + Y + YOffset + LineH);
          DrawText(Canvas.Handle, PChar(L[I]), Length(L[I]), R,
                   DT_SINGLELINE or DT_LEFT or DT_NOPREFIX);
          Inc(X, Ww + SpaceW);
        end;
      end
      else
      begin
        Extra := AvailW - LWidth;
        GapExtra := Extra div (LCount - 1);
        GapRem := Extra mod (LCount - 1);
        for I := 0 to LCount - 1 do
        begin
          Ww := Canvas.TextWidth(L[I]);
          R := Rect(ARect.Left + X, ARect.Top + Y + YOffset,
                    ARect.Left + X + Ww + 2, ARect.Top + Y + YOffset + LineH);
          DrawText(Canvas.Handle, PChar(L[I]), Length(L[I]), R,
                   DT_SINGLELINE or DT_LEFT or DT_NOPREFIX);
          Inc(X, Ww + SpaceW + GapExtra);
          if I < GapRem then
            Inc(X);
        end;
      end;
    end;
    Inc(Y, LineH);
  end;

begin
  Canvas.Font.Assign(FFont);
  SpaceW := Canvas.TextWidth(' ');
  LineH := Canvas.TextHeight('W') + 1;
  AvailW := ARect.Right - ARect.Left;
  Y := 0;
  Paras := FText.Split([#13#10, #13, #10]);
  for ParaIdx := 0 to High(Paras) do
  begin
    Words := Paras[ParaIdx].Split([' ']);
    SetLength(Line, 0);
    LineW := 0;
    for I := 0 to High(Words) do
    begin
      W := Words[I];
      Ww := Canvas.TextWidth(W);
      if (Length(Line) > 0) and (LineW + SpaceW + Ww > AvailW) then
      begin
        FlushLine(Line, Length(Line), LineW, False);
        SetLength(Line, 0);
        LineW := 0;
      end;
      SetLength(Line, Length(Line) + 1);
      Line[High(Line)] := W;
      if Length(Line) = 1 then
        LineW := Ww
      else
        Inc(LineW, SpaceW + Ww);
    end;
    if Length(Line) > 0 then
      FlushLine(Line, Length(Line), LineW, True);
  end;
  Result := Y;
end;

procedure TJustifiedBox.UpdateScrollBar;
var
  Total, MaxPos, Page: Integer;
begin
  if FScrollBar = nil then
    Exit;
  Total := MeasureHeight;
  Page := ClientHeight - 2 * BORDER;
  if Page < 1 then
    Page := 1;
  FScrollBar.Min := 0;
  FScrollBar.PageSize := Page;
  FScrollBar.Max := Total;
  FScrollBar.SmallChange := 24;
  FScrollBar.LargeChange := Page;
  MaxPos := Total - Page;
  if MaxPos < 0 then
    MaxPos := 0;
  if FScrollPos > MaxPos then
    FScrollPos := MaxPos;
  if FScrollPos < 0 then
    FScrollPos := 0;
  if Total > Page then
  begin
    FScrollBar.Visible := True;
    FScrollBar.Width := 16;
  end
  else
  begin
    FScrollBar.Visible := False;
    FScrollBar.Width := 0;
  end;
  FScrollBar.Position := FScrollPos;
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
  FText := FText + S;
  FScrollPos := MaxInt;
  UpdateScrollBar;
  Invalidate;
end;

procedure TJustifiedBox.DeleteLastChar;
begin
  if FText = '' then
    Exit;
  if (Length(FText) >= 2) and (FText[Length(FText) - 1] = #13) and (FText[Length(FText)] = #10) then
    Delete(FText, Length(FText) - 1, 2)
  else
    Delete(FText, Length(FText), 1);
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

procedure TJustifiedBox.MenuPaste(Sender: TObject);
begin
  PasteFromClipboard;
end;

procedure TJustifiedBox.MenuCopy(Sender: TObject);
begin
  Clipboard.AsText := FText;
end;

procedure TJustifiedBox.MenuClear(Sender: TObject);
begin
  Clear;
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
  R: TRect;
  Bg, Fg: TColor;
begin
  Canvas.Font.Assign(FFont);
  if StyleServices.Enabled then
  begin
    Bg := StyleServices.GetSystemColor(clWindow);
    Fg := StyleServices.GetSystemColor(clWindowText);
  end
  else
  begin
    Bg := clWindow;
    Fg := clWindowText;
  end;
  Canvas.Brush.Color := Bg;
  Canvas.FillRect(ClientRect);

  R := ClientRect;
  Canvas.Pen.Style := psSolid;
  Canvas.Pen.Color := StyleServices.GetSystemColor(clBtnShadow);
  Canvas.Brush.Style := bsClear;
  Canvas.Rectangle(R.Left, R.Top, R.Right - 1, R.Bottom - 1);
  Canvas.Brush.Style := bsSolid;

  R := GetTextRect;
  if not Enabled then
    Fg := StyleServices.GetSystemColor(clGrayText);
  Canvas.Font.Color := Fg;
  SetBkMode(Canvas.Handle, TRANSPARENT);
  MeasureAndDraw(True, R, -FScrollPos);

  if Focused then
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Pen.Style := psDot;
    Canvas.Pen.Color := Fg;
    Canvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
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
          Clipboard.AsText := FText;
          Key := 0;
        end;
      Ord('A'), Ord('a'):
        Key := 0;
    end;
  end;
  case Key of
    VK_BACK:
      begin
        DeleteLastChar;
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
    VK_HOME:
      begin
        FScrollPos := 0;
        UpdateScrollBar;
        Key := 0;
      end;
    VK_END:
      begin
        FScrollPos := MaxInt;
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
