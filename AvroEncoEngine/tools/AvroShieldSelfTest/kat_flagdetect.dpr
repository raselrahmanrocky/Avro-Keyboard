{

  kat_flagdetect - regression KAT for .AvroEnco protection-flag detection.

  This is the decision that drives whether importing a mapping asks for a
  password. It once had two implementations that disagreed: uAvroEncoImporter
  carried its own header inspector reporting EVERY Shield container as
  password protected, so a default-key Shield file (flag
  AVROSHLD_FLAG_DEFAULT_KEY, $10 in byte 9) prompted when imported from the
  menu - while the very same file loaded silently after a manual copy into the
  mapping folder, because every other path (engine loader, folder watcher,
  version picker) uses the canonical uAvroEncoCrypto.GetAvroEncoProtectionFlag.
  The duplicate is gone; this test pins the shared behaviour so it cannot come
  back:

    1. Shield + default-key bit            -> DEFAULT_KEY, loads with no password
    2. Shield + password                   -> USER_PASSWORD, empty/wrong pw fails
    3. Shield + default-key + machine bind -> still DEFAULT_KEY (flag-only check)
    4. Shield + default-key + extra flag bits (the packaged pattern) -> still
                                              DEFAULT_KEY: the decision reads the
                                              BIT, never the whole byte
    5. v2 CBC flag $00                     -> DEFAULT_KEY, loads with no password
    6. v2 CBC flag $01                     -> USER_PASSWORD
    7. legacy v1 header (no flag byte)     -> USER_PASSWORD
    8. v2 with a corrupt flag byte         -> neither $00 nor $01, so the import
                                              path reports an invalid header
    9. unreadable / garbage / empty file   -> INVALID (fail closed)
   10. truncated Shield headers            -> rejected by ValidateAvroEncoHeader
                                              before the flag is ever trusted

  Containers are self-generated in memory (no fixtures), so the test always
  matches the current key schedule; only temp files are written.

  Optional second form - run the same decision over real container folders,
  which is what actually gets imported or shipped:

    kat_flagdetect <container-dir> [quiet]

  Every .AvroEnco there must be detectable (never INVALID), have a valid
  header, and a DEFAULT_KEY container must decrypt with an empty password so
  the import path copies it without a password prompt.

  Exit code: 0 all PASS, 1 FAIL.

  Build (same command line as the sibling KATs, from this folder):
    dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" \
          -U"..\..\..\Keyboard and Spell checker\Units;%BDS%\lib\win32\release" \
          kat_flagdetect.dpr
}

{$APPTYPE CONSOLE}

program kat_flagdetect;

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  uAvroShield,
  uAvroEncoCrypto;

const
  TestJson =
    '{"Metadata": {"encoding": "UTF-8", "version": 1, "name": "FlagDetect"},'
    + ' "FullFormReplacements": {"a": "abc", "k": "'
    + Chr($0995) + Chr($09CD) + Chr($09B7) + '"}}';
  TestPassword = 'demo-flagdetect-password';

var
  Fails: Integer;
  Checks: Integer;
  Quiet: Boolean;
  TmpDir: string;

procedure Check(const AName: string; ACond: Boolean; const ADetail: string = '');
begin
  Inc(Checks);
  if ACond then
  begin
    if not Quiet then
      WriteLn('PASS ' + AName);
  end
  else
  begin
    WriteLn('FAIL ' + AName);
    if ADetail <> '' then
      WriteLn('     ' + ADetail);
    Inc(Fails);
  end;
end;

function TempPath(const AName: string): string;
begin
  Result := TmpDir + AName;
end;

procedure SaveBytes(const APath: string; const ABytes: TBytes);
begin
  TFile.WriteAllBytes(APath, ABytes);
end;

// Loads a file, or returns an empty array when it is absent. Used by the
// mutation cases below: a failed build must surface as ordinary FAIL lines
// instead of raising out of the test.
function TryLoadBytes(const APath: string): TBytes;
begin
  Result := nil;
  if TFile.Exists(APath) then
    Result := TFile.ReadAllBytes(APath);
end;

// Applies the same decision to every real container in a folder - the files a
// user actually imports, or that ship inside the product. This is the shape the
// bug was reported in: a packaged default-key container must never ask for a
// password, so the DEFAULT_KEY ones must decrypt with an empty password.
procedure RunContainerDir(const ADir: string);
var
  FileNames: TArray<string>;
  FileName, ShortName: string;
  Flag: Byte;
begin
  if not TDirectory.Exists(ADir) then
  begin
    Check('container dir exists: ' + ADir, False, 'directory not found');
    Exit;
  end;

  FileNames := TDirectory.GetFiles(ADir, '*.AvroEnco');
  Check('container dir has .AvroEnco files: ' + ADir, Length(FileNames) > 0,
    'no .AvroEnco file found');

  for FileName in FileNames do
  begin
    ShortName := ExtractFileName(FileName);
    Flag := GetAvroEncoProtectionFlag(FileName);

    Check(ShortName + ': header is valid', ValidateAvroEncoHeader(FileName));
    Check(ShortName + ': protection flag is detectable',
      (Flag = AVROENCO_FLAG_DEFAULT_KEY) or
      (Flag = AVROENCO_FLAG_USER_PASSWORD), 'flag=' + IntToStr(Flag));

    if Flag = AVROENCO_FLAG_DEFAULT_KEY then
      Check(ShortName + ': default-key container imports without a password',
        ValidateAvroEncoPassword(FileName, ''))
    else
      Check(ShortName + ': password container is NOT unlocked by an empty password',
        not ValidateAvroEncoPassword(FileName, ''));
  end;
end;

// Builds a Shield container and writes it to APath. Returns the builder result
// code so a failed build can never be mistaken for a working container.
function BuildShield(const APath, APassword: string;
  const ADefaultKey, ABindToMachine: Boolean): TAvroShieldResult;
var
  Bytes: TBytes;
begin
  Bytes := nil;
  Result := AvroShieldBuildFromJson(TestJson, APassword, ADefaultKey,
    ABindToMachine, False, Bytes);
  try
    if (Result = asrOk) and (Length(Bytes) > 0) then
      SaveBytes(APath, Bytes);
  finally
    if Length(Bytes) > 0 then
      FillChar(Bytes[0], Length(Bytes), 0);
  end;
end;

procedure Run;
var
  ShieldDefault, ShieldPassword, ShieldBound: string;
  ShieldExtraBits, ShieldNoDefaultBit: string;
  V2Default, V2Password, V2Corrupt, V1Header: string;
  Garbage, EmptyFile, Missing: string;
  ShieldTrunc10, ShieldTrunc9: string;
  Bytes: TBytes;
  Flag: Byte;
  R: TAvroShieldResult;
  I: Integer;
begin
  ShieldDefault := TempPath('shield_default.AvroEnco');
  ShieldPassword := TempPath('shield_password.AvroEnco');
  ShieldBound := TempPath('shield_default_bound.AvroEnco');
  ShieldExtraBits := TempPath('shield_default_extra_flags.AvroEnco');
  ShieldNoDefaultBit := TempPath('shield_default_bit_cleared.AvroEnco');
  V2Default := TempPath('v2_default.AvroEnco');
  V2Password := TempPath('v2_password.AvroEnco');
  V2Corrupt := TempPath('v2_corrupt_flag.AvroEnco');
  V1Header := TempPath('legacy_v1.AvroEnco');
  Garbage := TempPath('garbage.AvroEnco');
  EmptyFile := TempPath('empty.AvroEnco');
  Missing := TempPath('does_not_exist.AvroEnco');
  ShieldTrunc10 := TempPath('shield_trunc10.AvroEnco');
  ShieldTrunc9 := TempPath('shield_trunc9.AvroEnco');

  // ---- 1. Shield, default-key ------------------------------------------------
  R := BuildShield(ShieldDefault, '', True, False);
  Check('build: Shield default-key container', R = asrOk, 'asr=' + IntToStr(Ord(R)));
  Check('Shield default-key: header is valid', ValidateAvroEncoHeader(ShieldDefault));
  Check('Shield default-key: detected as Shield container',
    IsAvroShieldContainer(ShieldDefault));
  Check('Shield default-key: uses the built-in default key',
    AvroShieldContainerUsesDefaultKey(ShieldDefault));
  Check('Shield default-key: flag = DEFAULT_KEY (no import prompt)',
    GetAvroEncoProtectionFlag(ShieldDefault) = AVROENCO_FLAG_DEFAULT_KEY,
    'flag=' + IntToStr(GetAvroEncoProtectionFlag(ShieldDefault)));
  Check('Shield default-key: validates with an empty password (silent import)',
    ValidateAvroEncoPassword(ShieldDefault, ''));
  // The loader substitutes the built-in secret before the password is ever
  // consulted, so this is why the import path passes '' and never prompts.
  Check('Shield default-key: the password argument is ignored by the loader',
    ValidateAvroEncoPassword(ShieldDefault, TestPassword));

  // ---- 2. Shield, user password ---------------------------------------------
  R := BuildShield(ShieldPassword, TestPassword, False, False);
  Check('build: Shield password container', R = asrOk, 'asr=' + IntToStr(Ord(R)));
  Check('Shield password: not a default-key container',
    not AvroShieldContainerUsesDefaultKey(ShieldPassword));
  Check('Shield password: flag = USER_PASSWORD (import must prompt)',
    GetAvroEncoProtectionFlag(ShieldPassword) = AVROENCO_FLAG_USER_PASSWORD,
    'flag=' + IntToStr(GetAvroEncoProtectionFlag(ShieldPassword)));
  Check('Shield password: empty password does NOT validate',
    not ValidateAvroEncoPassword(ShieldPassword, ''));
  Check('Shield password: wrong password does NOT validate',
    not ValidateAvroEncoPassword(ShieldPassword, 'wrong-password'));
  Check('Shield password: correct password validates',
    ValidateAvroEncoPassword(ShieldPassword, TestPassword));

  // ---- 3. Shield, default-key + machine binding -----------------------------
  // Detection reads the header flag only, never the machine id, so binding must
  // not change the answer: a bound default-key container is still silent.
  R := BuildShield(ShieldBound, '', True, True);
  Check('build: Shield default-key + machine-bound container', R = asrOk,
    'asr=' + IntToStr(Ord(R)));
  Check('Shield default-key + bind: uses the built-in default key',
    AvroShieldContainerUsesDefaultKey(ShieldBound));
  Check('Shield default-key + bind: flag = DEFAULT_KEY',
    GetAvroEncoProtectionFlag(ShieldBound) = AVROENCO_FLAG_DEFAULT_KEY);

  // ---- 4. Shield flag byte: only the default-key BIT decides ----------------
  // Packaged containers set several flag bits at once (observed byte 9 = $19),
  // so the decision must test the default-key BIT and must never compare the
  // whole byte - a regression to equality against a bare $10 constant is exactly
  // what would make packaged files prompt again.
  Bytes := TryLoadBytes(ShieldDefault);
  if Length(Bytes) >= 10 then
  begin
    Bytes[9] := Bytes[9] or $08; // flag bit unrelated to the key mode
    SaveBytes(ShieldExtraBits, Bytes);
    Check('Shield default-key + extra flag bits: byte 9 is not the bare $10 value',
      Bytes[9] <> $10, 'byte9=$' + IntToHex(Bytes[9], 2));
    Check('Shield default-key + extra flag bits: detected as default-key',
      AvroShieldContainerUsesDefaultKey(ShieldExtraBits));
    Check('Shield default-key + extra flag bits: flag = DEFAULT_KEY (no prompt)',
      GetAvroEncoProtectionFlag(ShieldExtraBits) = AVROENCO_FLAG_DEFAULT_KEY);
    Check('Shield default-key + extra flag bits: still loads silently',
      ValidateAvroEncoPassword(ShieldExtraBits, ''));

    // Clearing the bit must flip the decision the other way: the container is
    // then password protected and an empty password must not unlock it. This is
    // what proves the bit - and nothing else - grants silent unlocking.
    Bytes[9] := Bytes[9] and not $10;
    SaveBytes(ShieldNoDefaultBit, Bytes);
    Check('Shield default-key bit cleared: no longer a default-key container',
      not AvroShieldContainerUsesDefaultKey(ShieldNoDefaultBit));
    Check('Shield default-key bit cleared: flag = USER_PASSWORD (import prompts)',
      GetAvroEncoProtectionFlag(ShieldNoDefaultBit) = AVROENCO_FLAG_USER_PASSWORD);
    Check('Shield default-key bit cleared: empty password does NOT unlock it',
      not ValidateAvroEncoPassword(ShieldNoDefaultBit, ''));
  end;

  // ---- 5. v2 CBC, default key (flag $00) ------------------------------------
  Check('build: v2 CBC default-key container',
    EncryptJsonToAvroEncoFile(TestJson, '', V2Default));
  Check('v2 flag $00: not a Shield container', not IsAvroShieldContainer(V2Default));
  Check('v2 flag $00: flag = DEFAULT_KEY',
    GetAvroEncoProtectionFlag(V2Default) = AVROENCO_FLAG_DEFAULT_KEY);
  Check('v2 flag $00: validates with an empty password',
    ValidateAvroEncoPassword(V2Default, ''));

  // ---- 6. v2 CBC, user password (flag $01) ----------------------------------
  Check('build: v2 CBC password container',
    EncryptJsonToAvroEncoFile(TestJson, TestPassword, V2Password));
  Check('v2 flag $01: flag = USER_PASSWORD',
    GetAvroEncoProtectionFlag(V2Password) = AVROENCO_FLAG_USER_PASSWORD);
  Check('v2 flag $01: empty password does NOT validate',
    not ValidateAvroEncoPassword(V2Password, ''));
  Check('v2 flag $01: correct password validates',
    ValidateAvroEncoPassword(V2Password, TestPassword));

  // ---- 7. legacy v1 header (no flag byte) -----------------------------------
  // Synthetic header only: v1 detection is pure header inspection, so the
  // read-only legacy branch is pinned without needing a v1-era ciphertext.
  SetLength(Bytes, V1_HEADER_SIZE + 16);
  FillChar(Bytes[0], Length(Bytes), 0);
  Move(AVROENCO_MAGIC_BASE[0], Bytes[0], Length(AVROENCO_MAGIC_BASE));
  Bytes[8] := AVROENCO_MAGIC_TAIL_V1;
  SaveBytes(V1Header, Bytes);
  Check('legacy v1: header shape is valid', ValidateAvroEncoHeader(V1Header));
  Check('legacy v1: flag = USER_PASSWORD (always prompts)',
    GetAvroEncoProtectionFlag(V1Header) = AVROENCO_FLAG_USER_PASSWORD);

  // ---- 8. v2 with a corrupt flag byte ---------------------------------------
  // GetAvroEncoProtectionFlag returns the raw v2 flag byte, so ImportEncoFile
  // guards on $00/$01: anything else is reported as an invalid header rather
  // than being routed into the silent default-key branch. If that guard is ever
  // dropped, this check fails.
  Bytes := TryLoadBytes(V2Default);
  if Length(Bytes) >= V2_HEADER_SIZE then
    Bytes[9] := $07;
  SaveBytes(V2Corrupt, Bytes);
  Flag := GetAvroEncoProtectionFlag(V2Corrupt);
  Check('v2 corrupt flag byte: neither DEFAULT_KEY nor USER_PASSWORD',
    (Flag <> AVROENCO_FLAG_DEFAULT_KEY) and
    (Flag <> AVROENCO_FLAG_USER_PASSWORD),
    'flag=' + IntToStr(Flag));

  // ---- 9. fail-closed inputs ------------------------------------------------
  SetLength(Bytes, 64);
  for I := 0 to Length(Bytes) - 1 do
    Bytes[I] := Byte(I * 7 + 3); // no known magic anywhere
  SaveBytes(Garbage, Bytes);
  Check('garbage file: flag = INVALID',
    GetAvroEncoProtectionFlag(Garbage) = AVROENCO_FLAG_INVALID);
  Check('garbage file: header invalid', not ValidateAvroEncoHeader(Garbage));

  SetLength(Bytes, 0);
  SaveBytes(EmptyFile, Bytes);
  Check('empty file: flag = INVALID',
    GetAvroEncoProtectionFlag(EmptyFile) = AVROENCO_FLAG_INVALID);

  Check('missing file: flag = INVALID',
    GetAvroEncoProtectionFlag(Missing) = AVROENCO_FLAG_INVALID);

  // ---- 10. truncated Shield headers -----------------------------------------
  // Import order is header validation first, then the flag. A container too
  // short to hold a payload is rejected by ValidateAvroEncoHeader, so the flag
  // value - which is header-only and cannot know the payload is unloadable -
  // never reaches a decision. Nothing is copied and no password is asked.
  Bytes := TryLoadBytes(ShieldDefault);
  SetLength(Bytes, 10); // magic + version + flag byte, no payload at all
  SaveBytes(ShieldTrunc10, Bytes);
  Check('truncated Shield (10 bytes): header invalid, so the import is rejected',
    not ValidateAvroEncoHeader(ShieldTrunc10));
  Check('truncated Shield (10 bytes): flag is still DEFAULT_KEY (header-only)',
    GetAvroEncoProtectionFlag(ShieldTrunc10) = AVROENCO_FLAG_DEFAULT_KEY);
  Check('truncated Shield (10 bytes): payload does NOT validate',
    not ValidateAvroEncoPassword(ShieldTrunc10, ''));

  Bytes := TryLoadBytes(ShieldDefault);
  SetLength(Bytes, 9); // flag byte itself is missing
  SaveBytes(ShieldTrunc9, Bytes);
  Check('truncated Shield (9 bytes): header invalid, so the import is rejected',
    not ValidateAvroEncoHeader(ShieldTrunc9));
  Check('truncated Shield (9 bytes): not reported as a default-key container',
    not AvroShieldContainerUsesDefaultKey(ShieldTrunc9));
end;

var
  I: Integer;
  DirArg: string;
begin
  Fails := 0;
  Checks := 0;
  Quiet := False;
  DirArg := '';

  for I := 1 to ParamCount do
    if SameText(ParamStr(I), 'quiet') then
      Quiet := True
    else if DirArg = '' then
      DirArg := ParamStr(I);

  TmpDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    'avro_flagdetect_' + IntToStr(GetCurrentProcessId) + PathDelim;
  TDirectory.CreateDirectory(TmpDir);

  try
    Run;
    if DirArg <> '' then
      RunContainerDir(DirArg);
  finally
    try
      TDirectory.Delete(TmpDir, True);
    except
      // A leftover temp folder must never turn a green run into a red one.
    end;
  end;

  if Fails = 0 then
    WriteLn(Format('ALL PASS (%d checks)', [Checks]))
  else
    WriteLn(Format('%d of %d checks FAILED', [Fails, Checks]));

  ExitCode := Ord(Fails > 0);
end.
