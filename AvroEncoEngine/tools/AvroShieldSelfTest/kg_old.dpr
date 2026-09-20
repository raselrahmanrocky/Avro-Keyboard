{

  =============================================================================
  kg_old - the cross-revision half of kat_grapheme's row 15 ("Unicode output
  mode non-regression"). It exists to be built TWICE, against two revisions:

      git worktree add /tmp/base34 34deb37
      copy this file into the worktree's AvroShieldSelfTest folder
      <dcc> -B <the worktree's unit search path> kg_old.dpr   -> run it
      <dcc> -B <this tree's unit search path>     kg_old.dpr   -> run it

  It uses ONLY what both revisions have: the engine's real entry point
  (ProcessVKeyDown), the OnRawEmit capture and the keyboard-mode override - so
  the same source compiles and runs against the pre-feature tree and against
  this one. Pressing Backspace with an EMPTY ledger in Unicode mode is the one
  state a head-less program can create in both trees (the seeding hooks arrived
  with the feature), and its emitted stream must be byte-identical:

      unicode modern empty ledger block=False emits=0 erase=0 text=[]
      unicode old empty ledger    block=False emits=0 erase=0 text=[]

  which is what those two builds printed on the machine this was written on.
}

{$APPTYPE CONSOLE}

program kg_old;

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  uRegistrySettings,
  uAvroEncoManager,
  uAnsiEngineManager,
  clsUnicodeToBijoy2000,
  BanglaChars,
  clsLayout,
  clsGenericLayoutModern,
  clsGenericLayoutOld;

type
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
  Rec:    TRec;
  ErrLog: TStringList;
  Modern: TGenericLayoutModern;
  Old:    TGenericLayoutOld;

procedure Once(const AName: string; const ABackspace: Boolean);
var
  Block: Boolean;
begin
  Rec.Erases := 0;
  Rec.Text := '';
  Rec.Emits := 0;
  Block := False;
  if ABackspace then
  begin
    Modern.SetKeyboardModeOverride(True, Ord(bangla));
    Old.SetKeyboardModeOverride(True, Ord(bangla));
    Modern.ProcessVKeyDown(VK_BACK, Block);
  end
  else
    Old.ProcessVKeyDown(VK_BACK, Block);
  WriteLn(Format('unicode %s block=%s emits=%d erase=%d text=[%s]', [AName, BoolToStr(Block, True), Rec.Emits, Rec.Erases,
    Rec.Text]));
end;

begin
  { Only keys both revisions declare: the ANSI settings arrived with the feature,
    and this probe exists to compile against the tree from before it. }
  OutputIsBijoy := 'NO';
  EnableCaretSniffer := 'YES';

  Modern := TGenericLayoutModern.Create;
  Old := TGenericLayoutOld.Create;
  Rec := TRec.Create;
  ErrLog := TStringList.Create;
  try
    if not AnsiEngineManager.SwitchEngine('Default', ErrLog) then
    begin
      WriteLn('FAIL mapping');
      Halt(1);
    end;
    Modern.OnRawEmit := Rec.Sink;
    Old.OnRawEmit := Rec.Sink;

    Modern.SetKeyboardModeOverride(True, Ord(bangla));
    Old.SetKeyboardModeOverride(True, Ord(bangla));

    Once('modern empty ledger', True);
    Once('old empty ledger', False);
    Once('modern again', True);
  finally
    Modern.OnRawEmit := nil;
    Old.OnRawEmit := nil;
    ErrLog.Free;
    Rec.Free;
    Old.Free;
    Modern.Free;
  end;
end.
