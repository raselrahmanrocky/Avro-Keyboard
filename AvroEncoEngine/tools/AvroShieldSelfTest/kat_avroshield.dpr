program kat_avroshield;

{ End-to-end KAT for the pure-Pascal Shield runtime stack (uAvroShield.pas):
  bytecode parse + deobfuscate, and full container round-trip
  (build -> HMAC verify -> AES-GCM decrypt -> zlib -> bytecode ->
  deobfuscate).

  v2 note: containers are SELF-GENERATED in-memory (no Python toolchain
  fixtures) so the test always matches the current key schedule. The only
  fixture containers left are:
    kat_legacy_v1.AvroEnco - a v1 (Argon2-era) file that MUST now fail
      cleanly with asrBadVersion (there is intentionally no legacy path)
    kat_sample.bytecode    - raw AVROBC bytecode; the bytecode and
      deobfuscation stages are version-independent, so this still parses
  This Delphi unit is the authoritative spec for the v2 KDF. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  uAvroShield;

const
  DemoPassword = 'demo-avroshield-password';

  ExpectedJson =
    '{"Metadata": {"encoding": "UTF-8", "version": 1, "name": "TestLayout"}, '
    + '"FullFormReplacements": {"a": "abc", "b": "def", "k": "'
    + Chr($09AC) + Chr($09BE) + Chr($0982) + Chr($09B2) + Chr($09BE)  { bangla }
    + '"}, "Nested": {"arr": [1, 2.5, true, null, "'
    + Chr($09AC) + Chr($09BE) + Chr($0982) + Chr($09B2) + Chr($09BE)
    + '"]}, "Ints": [-5, 0, 123456789012345678], "Empty": {}}';

var
  Fails: Integer;
  Tampered: TBytes;
  Dummy: string;
  Bc: TBytes;
  Node, Deobf: TAvroNode;
  Json: string;

function StripWS(const S: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    if (S[I] <> ' ') and (S[I] <> #9) and (S[I] <> #10) and (S[I] <> #13) then
      Result := Result + S[I];
end;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  if ACond then
    WriteLn('PASS ' + AName)
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('  ' + ADetail);
    Inc(Fails);
  end;
end;

function ReadAll(const AFileName: string): TBytes;
var
  FS: TFileStream;
begin
  Result := nil;
  if not FileExists(AFileName) then
    Exit;
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.Read(Result[0], FS.Size);
  finally
    FS.Free;
  end;
end;

procedure WriteAll(const AFileName: string; const AData: TBytes);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(AData) > 0 then
      FS.Write(AData[0], Length(AData));
  finally
    FS.Free;
  end;
end;

{ Builds a container from ExpectedJson and loads it back, comparing JSON. }
procedure CheckRoundTrip(const AName, APassword: string;
  ADefaultKey, ABind: Boolean);
var
  C: TBytes;
  Json: string;
  R: TAvroShieldResult;
begin
  R := AvroShieldBuildFromJson(ExpectedJson, APassword,
    ADefaultKey, ABind, False, C);
  Check(AName + ' build', R = asrOk,
    'result=' + IntToStr(Ord(R)) + ' (expected asrOk)');
  if R <> asrOk then
    Exit;
  R := AvroShieldLoadFromBytes(C, APassword, Json, ABind);
  Check(AName + ' load', R = asrOk,
    'result=' + IntToStr(Ord(R)) + ' (expected asrOk)');
  if R = asrOk then
    Check(AName + ' JSON', StripWS(Json) = StripWS(ExpectedJson),
      'json mismatch: ' + Json);
end;

var
  C: TBytes;
  R: TAvroShieldResult;
  TmpFile: string;

begin
  Fails := 0;

  WriteLn('=== bytecode parse + deobfuscate (version-independent) ===');
  begin
    Bc := ReadAll('kat_sample.bytecode');
    Check('bytecode read', Length(Bc) > 0, 'cannot read kat_sample.bytecode');
    if Length(Bc) > 0 then
    begin
      Node := nil;
      Deobf := nil;
      if not AvroShieldParseBytecode(Bc, Node) then
        Check('bytecode parse', False, 'parse failed')
      else
      begin
        Check('bytecode parse', True);
        if AvroShieldDeobfuscate(Node, Deobf) then
        begin
          Json := AvroShieldNodeToJSON(Deobf);
          Check('bytecode deobfuscate+JSON',
            StripWS(Json) = StripWS(ExpectedJson), 'json mismatch: ' + Json);
          Deobf.Free;
        end
        else
          Check('bytecode deobfuscate', False, 'deobfuscate failed');
        Node.Free;
      end;
    end;
  end;

  WriteLn('=== password container round-trip (v2 PBKDF2) ===');
  CheckRoundTrip('password', DemoPassword, False, False);

  WriteLn('=== default-key container round-trip (v2 HKDF) ===');
  CheckRoundTrip('default-key', '', True, False);

  WriteLn('=== machine-bound container round-trip ===');
  CheckRoundTrip('bound', DemoPassword, False, True);
  R := AvroShieldBuildFromJson(ExpectedJson, DemoPassword,
    False, True, False, C);
  if R = asrOk then
    Check('bound with bind off',
      AvroShieldLoadFromBytes(C, DemoPassword, Dummy, False) =
        asrMachineBindRequired, 'expected asrMachineBindRequired')
  else
    Check('bound with bind off', False, 'build failed');

  WriteLn('=== file round-trip (writer -> disk -> loader) ===');
  R := AvroShieldBuildFromJson(ExpectedJson, DemoPassword,
    False, False, False, C);
  Check('file build', R = asrOk, 'result=' + IntToStr(Ord(R)));
  if R = asrOk then
  begin
    TmpFile := 'kat_tmp_roundtrip.AvroEnco';
    WriteAll(TmpFile, C);
    try
      R := AvroShieldLoadFromFile(TmpFile, DemoPassword, Json, False);
      Check('file load', R = asrOk, 'result=' + IntToStr(Ord(R)));
      if R = asrOk then
        Check('file JSON', StripWS(Json) = StripWS(ExpectedJson),
          'json mismatch: ' + Json);
    finally
      DeleteFile(TmpFile);
    end;
  end;

  WriteLn('=== wrong password / tamper / format ===');
  R := AvroShieldBuildFromJson(ExpectedJson, DemoPassword,
    False, False, False, C);
  Check('pw-fixture build', R = asrOk, 'result=' + IntToStr(Ord(R)));
  if R = asrOk then
  begin
    Check('wrong password',
      AvroShieldLoadFromBytes(C, 'wrong-password', Dummy, False) =
        asrHmacFailed, 'expected asrHmacFailed');
    { Tamper: flip one ciphertext byte (offset 100 is past the 58-byte
      header; the container is several hundred bytes). }
    Check('tamper guard', Length(C) > 150,
      'container unexpectedly small: ' + IntToStr(Length(C)));
    if Length(C) > 150 then
    begin
      Tampered := Copy(C, 0, Length(C));
      Tampered[100] := Tampered[100] xor $FF;
      Check('tampered ciphertext',
        AvroShieldLoadFromBytes(Tampered, DemoPassword, Dummy, False) =
          asrHmacFailed, 'expected asrHmacFailed');
    end;
  end;

  { v1 (Argon2-era) container: must fail cleanly with asrBadVersion.
    There is intentionally no legacy Argon2 fallback path. }
  Check('legacy v1 fixture present',
    FileExists('kat_legacy_v1.AvroEnco'), 'missing kat_legacy_v1.AvroEnco');
  if FileExists('kat_legacy_v1.AvroEnco') then
    Check('legacy v1 rejected',
      AvroShieldLoadFromFile('kat_legacy_v1.AvroEnco', DemoPassword,
        Dummy, False) = asrBadVersion, 'expected asrBadVersion');

  SetLength(Tampered, 200);
  FillChar(Tampered[0], 200, Ord('G'));
  Check('bad magic', AvroShieldLoadFromBytes(Tampered,
    DemoPassword, Dummy, False) = asrBadMagic, 'expected asrBadMagic');

  SetLength(Tampered, 40);
  Check('truncated file', AvroShieldLoadFromBytes(Tampered,
    DemoPassword, Dummy, False) = asrFileTooShort, 'expected asrFileTooShort');

  if Fails = 0 then
    WriteLn('ALL AVROSHIELD KATs PASSED')
  else
    WriteLn(IntToStr(Fails) + ' KAT(s) FAILED');

  if Fails > 0 then
    Halt(1);
end.
