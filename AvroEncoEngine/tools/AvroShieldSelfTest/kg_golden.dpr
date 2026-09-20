{

  =============================================================================
  kg_golden - records the Unicode-mode backspace stream for the corpus that
  kat_grapheme's row 15 ("Unicode output mode non-regression") asserts. It is
  kept next to the harness for one reason: when an engine's Unicode path changes
  on purpose, this is how the golden in kat_grapheme is re-recorded - run it,
  compare with the UNI_GOLDEN table there, and update the table deliberately.

  Build it exactly like kat_grapheme (see the repository's build note for the
  unit search path) and run it with no arguments:

      kg_golden > unicode_golden.txt

  Output: one line per engine (modern, old, e2b), corpus item and press:

      <engine>/<item> press<N> before=[..] block=<bool> emits=<n>
          erase=<n> text=[..] after=[..]

  For the CROSS-REVISION comparison use kg_old.dpr instead: that one compiles
  against both this tree and the tree from before the feature.
}

{$APPTYPE CONSOLE}

program kg_golden;

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  uRegistrySettings,
  uAvroEncoManager,
  uAnsiEngineManager,
  clsUnicodeToBijoy2000,
  BanglaChars,
  clsAnsiGrapheme,
  clsAnsiAtomMap,
  clsLayout,
  clsGenericLayoutModern,
  clsGenericLayoutOld,
  clsE2BCharBased,
  uCaretContextCache;

type
  TKind = (kModern, kOld, kE2B);

  TRec = class
    Erases: Integer;
    Text:   string;
    Emits:  Integer;
    procedure Sink(const AEraseCount: Integer; const AText: string);
  end;

procedure TRec.Sink(const AEraseCount: Integer; const AText: string);
begin
  Erases := AEraseCount;
  Text := AText;
  Inc(Emits);
end;

var
  Rec:       TRec;
  ErrLog:    TStringList;
  Modern:    TGenericLayoutModern;
  Old:       TGenericLayoutOld;
  CharBased: TE2BCharBased;

function Hex(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + IntToHex(Ord(S[I]), 4) + ' ';
end;

function Ledger(const K: TKind): string;
begin
  case K of
    kModern: Result := Modern.CommittedForTest;
    kOld: Result := Old.CommittedForTest;
  else
    Result := CharBased.CommittedForTest;
  end;
end;

procedure Seed(const K: TKind; const S: string);
begin
  case K of
    kModern: Modern.SeedCommittedForTest(S);
    kOld: Old.SeedCommittedForTest(S);
  else
    CharBased.SeedCommittedForTest(S);
  end;
end;

procedure Press(const K: TKind; var Block: Boolean);
begin
  case K of
    kModern: Modern.BackspaceForTest(Block);
    kOld: Old.BackspaceForTest(Block);
  else
    CharBased.BackspaceForTest(Block);
  end;
end;

procedure PinBangla(const K: TKind);
begin
  case K of
    kModern: Modern.SetKeyboardModeOverride(True, Ord(bangla));
    kOld: Old.SetKeyboardModeOverride(True, Ord(bangla));
  else
    CharBased.SetKeyboardModeOverride(True, Ord(bangla));
  end;
end;

const
  KINDS: array [0 .. 2] of TKind = (kModern, kOld, kE2B);
  KINDS_NAME: array [0 .. 2] of string = ('modern', 'old', 'e2b');
  CORPUS: array [0 .. 10] of string = (
    #$0987,                                            // ই
    #$0989,                                            // উ
    #$0995#$09CD#$0995,                                // ক্ক
    #$09B0#$09CD#$0995,                                // র্ক
    #$0995#$09CD#$09B7,                                // ক্ষ
    #$09B9#$09CD#$09B0,                                // হ্র
    #$0995#$09CD#$200D#$09B7,                          // ka + hasanta + ZWJ + ssa
    #$0995#$09CD#$200C#$09B7,                          // ka + hasanta + ZWNJ + ssa
    #$0995#$09BF,                                      // কি  (a kar run)
    #$0995#$09BF#$09B0,                                // কি + র
    #$0995#$09BF' '                                    // কি + space
    );
  CORPUS_NAME: array [0 .. 10] of string = ('i', 'u', 'kka', 'rka', 'kssa', 'hra', 'zwj', 'zwnj', 'ki', 'kira', 'ki space');

var
  K, C, P: Integer;
  Block:   Boolean;
  Before:  string;
begin
  OutputIsBijoy := 'NO';
  EnableCaretSniffer := 'YES';
  AnsiSmartBackspace := 'YES';
  AnsiBackspaceHostErase := 'YES';
  AnsiBackspaceLegacy := 'NO';
  AnsiBackspaceUnitCap := '8';

  Modern := TGenericLayoutModern.Create;
  Old := TGenericLayoutOld.Create;
  CharBased := TE2BCharBased.Create;
  Rec := TRec.Create;
  ErrLog := TStringList.Create;
  if not AnsiEngineManager.SwitchEngine('Default', ErrLog) then
  begin
    WriteLn('FAIL mapping: ' + Trim(ErrLog.Text));
    Halt(1);
  end;

  Modern.OnRawEmit := Rec.Sink;
  Old.OnRawEmit := Rec.Sink;
  CharBased.OnRawEmit := Rec.Sink;

  WriteLn('mapping=' + AnsiVersion + ' outputIsBijoy=' + OutputIsBijoy);

  for K := 0 to 2 do
  begin
    PinBangla(KINDS[K]);
    for C := 0 to high(CORPUS) do
    begin
      Seed(KINDS[K], CORPUS[C]);
      for P := 1 to 3 do
      begin
        Before := Ledger(KINDS[K]);
        Rec.Erases := 0;
        Rec.Text := '';
        Rec.Emits := 0;
        Block := False;
        Press(KINDS[K], Block);
        WriteLn(Format('%s/%s press%d before=[%s] block=%s emits=%d erase=%d text=[%s] after=[%s]',
          [KINDS_NAME[K], CORPUS_NAME[C], P, Hex(Before), BoolToStr(Block, True), Rec.Emits, Rec.Erases, Hex(Rec.Text),
          Hex(Ledger(KINDS[K]))]));
      end;
    end;
  end;

  Modern.OnRawEmit := nil;
  Old.OnRawEmit := nil;
  CharBased.OnRawEmit := nil;
  ErrLog.Free;
  Rec.Free;
  CharBased.Free;
  Old.Free;
  Modern.Free;
end.
