{

  kat_karcall - isolated-kar resolver probe.

  The conversion gate (kat_ansiconvert) proves what a mapping *emits*; it cannot
  see what happens to a kar keystroke that never reaches the converter.  That
  keystroke is handled earlier: when the word buffer is empty the layout code
  asks the engine to attach the kar to whatever sits before the caret
  (TGenericLayoutOld.HandleIsolatedModifier), and if the resolver reports
  success the key is swallowed - whatever it emitted (possibly nothing) is all
  the user sees.

  This program drives that resolver directly for every mapping and every kar,
  with the context shapes the layout code can produce (a committed Bangla
  letter, a conjunct, and the raw ANSI mirror of both, which the caret sniffer
  yields when the text came from another application), and prints:

    * the normal (word-buffer) conversion of context + kar,
    * whether the isolated resolver claims the keystroke, and what it would
      emit - flagged when it claims it while emitting nothing.

  Usage: kat_karcall <mapping-dir>
  Exit code: 0 no swallowed keystroke, 1 at least one.
}

{$APPTYPE CONSOLE}

program kat_karcall;

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  uAvroEncoCrypto,
  clsUnicodeToBijoy2000;

const
  U_HASANTA = $09CD;
  U_K = $0995; U_T = $09A4; U_R = $09B0; U_N = $09A8;
  U_AAKAR = $09BE; U_IKAR = $09BF; U_IIKAR = $09C0; U_UKAR = $09C1;
  U_UUKAR = $09C2; U_RIKAR = $09C3; U_EKAR = $09C7; U_OIKAR = $09C8;
  U_OKAR = $09CB; U_OUKAR = $09CC; U_ANUSVARA = $0982;

var
  Fails: Integer;

function HexBytes(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    if I > 1 then
      Result := Result + ' ';
    Result := Result + IntToHex(Ord(S[I]), 2);
  end;
  if Result = '' then
    Result := '(empty)';
end;

function StripBom(const S: string): string;
begin
  Result := S;
  if (Result <> '') and (Result[1] = #$FEFF) then
    Delete(Result, 1, 1);
end;

function LoadMappingText(const APath: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(APath), '.AvroEnco') then
    Result := Trim(DecryptAvroEncoToString(APath, ''))
  else
    Result := Trim(StripBom(TFile.ReadAllText(APath, TEncoding.UTF8)));
end;

function InstallMapping(const AJsonText: string): Boolean;
var
  Log: TStringList;
  Root: TJSONValue;
begin
  Result := False;
  if AJsonText = '' then
    Exit;
  Root := TJSONObject.ParseJSONValue(AJsonText);
  if Root = nil then
    Exit;
  Root.Free;
  Log := TStringList.Create;
  try
    ResetAnsiToDefaults;
    LoadAnsiMappingFromJSON(AJsonText, Log);
  finally
    Log.Free;
  end;
  Result := True;
end;

// Kar candidates as the layout's kar keys deliver them.
function Kars: TArray<TPair<string, string>>;
begin
  SetLength(Result, 10);
  Result[0] := TPair<string, string>.Create('aa-kar', Chr(U_AAKAR));
  Result[1] := TPair<string, string>.Create('i-kar', Chr(U_IKAR));
  Result[2] := TPair<string, string>.Create('ii-kar', Chr(U_IIKAR));
  Result[3] := TPair<string, string>.Create('u-kar', Chr(U_UKAR));
  Result[4] := TPair<string, string>.Create('uu-kar', Chr(U_UUKAR));
  Result[5] := TPair<string, string>.Create('ri-kar', Chr(U_RIKAR));
  Result[6] := TPair<string, string>.Create('e-kar', Chr(U_EKAR));
  Result[7] := TPair<string, string>.Create('oi-kar', Chr(U_OIKAR));
  Result[8] := TPair<string, string>.Create('o-kar', Chr(U_OKAR));
  Result[9] := TPair<string, string>.Create('ou-kar', Chr(U_OUKAR));
end;

// Contexts the isolated path can be handed, in the two flavours the caret
// sniffer produces: what we typed (Unicode) and what the document holds (ANSI).
function Contexts: TArray<TPair<string, string>>;
begin
  SetLength(Result, 4);
  Result[0] := TPair<string, string>.Create('ka', Chr(U_K));
  Result[1] := TPair<string, string>.Create('k-ss', Chr(U_K) + Chr(U_HASANTA) + Chr($09B7));
  Result[2] := TPair<string, string>.Create('r-ka', Chr(U_R) + Chr(U_HASANTA) + Chr(U_K));
  Result[3] := TPair<string, string>.Create('k-anusvara', Chr(U_K) + Chr(U_ANUSVARA));
end;

procedure ProbeMapping(const APath, ATag: string);
var
  Conv: TUnicodeToBijoy2000;
  Json_: string;
  Kar, Ctx: TPair<string, string>;
  KarName, CtxName, AnsiCtx, Plain, Isolated, Matched: string;
  Erase: Integer;
  IsToggle, UsedAlt: Boolean;
  Claimed, Visible, EmitsNothing: Boolean;
  Kind: string;
begin
  Json_ := LoadMappingText(APath);
  if not InstallMapping(Json_) then
  begin
    WriteLn('FAIL ' + ATag + ': mapping not usable');
    Inc(Fails);
    Exit;
  end;

  Conv := TUnicodeToBijoy2000.Create;
  try
    WriteLn('--- ' + ATag + ' ---');
    for Ctx in Contexts do
    begin
      AnsiCtx := Conv.Convert(Ctx.Value);
      for Kar in Kars do
      begin
        KarName := Kar.Key;
        Plain := Conv.Convert(Ctx.Value + Kar.Value);

        // (1) Unicode context, as the word buffer supplies it.
        Claimed := Conv.ResolveAnsiSequence(Ctx.Value, Kar.Value, Isolated, Erase, Matched, IsToggle, UsedAlt);
        Visible := (Isolated <> '') or (Erase > 0);
        EmitsNothing := Claimed and (Isolated = '') and (Erase = 0);
        Kind := 'uni';
        if Not EmitsNothing then
        begin
          // (2) ANSI context, as the caret sniffer supplies it.
          Claimed := Conv.ResolveAnsiSequence(AnsiCtx, Kar.Value, Isolated, Erase, Matched, IsToggle, UsedAlt);
          Visible := (Isolated <> '') or (Erase > 0);
          EmitsNothing := Claimed and (Isolated = '') and (Erase = 0);
          Kind := 'ansi';
        end;

        if EmitsNothing then
        begin
          Inc(Fails);
          WriteLn(Format('SWALLOWED %s: %s after %s (%s) -> claimed, emitted nothing; normal path would be %s',
            [ATag, KarName, Ctx.Key, Kind, HexBytes(Plain)]));
        end
        else if Claimed then
          WriteLn(Format('  %-22s %-14s %-6s emits %-18s erase=%d  normal=%s',
            [ATag, KarName, Ctx.Key, HexBytes(Isolated), Erase, HexBytes(Plain)]))
        else
          WriteLn(Format('  %-22s %-14s %-6s not claimed (falls through)  normal=%s',
            [ATag, KarName, Ctx.Key, HexBytes(Plain)]));
      end;
    end;
  finally
    Conv.Free;
  end;
end;

var
  SR: TSearchRec;
  Dir, Name: string;
begin
  Fails := 0;
  Dir := '';
  if ParamCount >= 1 then
    Dir := ParamStr(1);
  if (Dir = '') or not DirectoryExists(Dir) then
  begin
    WriteLn('usage: kat_karcall <mapping-dir>');
    ExitCode := 2;
    Exit;
  end;

  Dir := IncludeTrailingPathDelimiter(Dir);
  if FindFirst(Dir + 'Ansi *.AvroEnco', faAnyFile, SR) = 0 then
    try
      repeat
        if (SR.Attr and faDirectory) = 0 then
        begin
          Name := ChangeFileExt(SR.Name, '');
          ProbeMapping(Dir + SR.Name, Name);
        end;
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;

  if Fails = 0 then
    WriteLn('ALL PASS (no kar keystroke is claimed while emitting nothing)')
  else
    WriteLn(Format('%d swallowed kar keystroke(s)', [Fails]));
  ExitCode := Ord(Fails > 0);
end.
