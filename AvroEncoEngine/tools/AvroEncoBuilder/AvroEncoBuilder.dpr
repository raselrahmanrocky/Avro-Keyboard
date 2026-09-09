{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

program AvroEncoBuilder;

{ =============================================================================
  AvroEncoBuilder - offline .AvroEnco container builder.

  Compiles a raw ANSI mapping JSON document into a protected .AvroEnco
  container using the same pure-Pascal crypto stack the runtime loads:

    shield (default):
      JSON -> obfuscated bytecode -> zlib -> AES-256-GCM -> HMAC-SHA512
      trailer. Protected either with a user password (-p, prompts once at
      load time) or with the built-in default application secret
      (--default-key, loads transparently - use for shipped built-ins).

    v2:
      AES-256-CBC container (legacy runtime format). Empty password selects
      the default-key mode; -p selects user-password protection.

  After building, the tool ALWAYS loads the container back through the
  runtime reader and verifies the recovered JSON is semantically identical to
  the input (unless --no-verify), so a format regression can never ship.

  Usage:
    AvroEncoBuilder <input.json> <output.avroenco> [options]

  Options:
    -p, --password <pw>   User password protection (prompts at load time).
    --default-key         Shield: protect with the built-in default secret.
    --format <fmt>        shield (default) | v2
    --bind                Shield: bind the container to this machine.
    --hardware            Shield: add the hardware factor to the KDF.
    --no-verify           Skip the load-back round-trip verification.
    --quiet               Only print errors.

  Exit codes: 0 OK, 1 usage, 2 input read failure, 3 invalid JSON,
              4 build failure, 5 output write failure, 6 verification failure.
  ============================================================================= }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.IOUtils,
  uAvroEncoCrypto,
  uAvroShield;

const
  EXIT_OK       = 0;
  EXIT_USAGE    = 1;
  EXIT_READ     = 2;
  EXIT_PARSE    = 3;
  EXIT_BUILD    = 4;
  EXIT_WRITE    = 5;
  EXIT_VERIFY   = 6;

  FORMAT_SHIELD = 1;
  FORMAT_V2     = 2;

var
  InputPath, OutputPath, Password, ErrMsg: string;
  ContainerFormat: Integer;
  UseDefaultKey, BindMachine, UseHardware, NoVerify, Quiet: Boolean;

procedure Usage;
begin
  WriteLn('AvroEncoBuilder - offline .AvroEnco container builder');
  WriteLn;
  WriteLn('Usage: AvroEncoBuilder <input.json> <output.avroenco> [options]');
  WriteLn;
  WriteLn('Options:');
  WriteLn('  -p, --password <pw>   User password protection (prompts at load time).');
  WriteLn('  --default-key         Shield: protect with the built-in default secret.');
  WriteLn('  --format <fmt>        shield (default) | v2');
  WriteLn('  --bind                Shield: bind the container to this machine.');
  WriteLn('  --hardware            Shield: add the hardware factor to the KDF.');
  WriteLn('  --no-verify           Skip the load-back round-trip verification.');
  WriteLn('  --quiet               Only print errors.');
  WriteLn;
  WriteLn('Exit codes: 0 OK, 1 usage, 2 input read failure, 3 invalid JSON,');
  WriteLn('            4 build failure, 5 output write failure, 6 verification failure.');
end;

{ Reads a UTF-8 text file, strips a leading BOM. }
function ReadUtf8File(const APath: string; out AText: string): Boolean;
begin
  Result := False;
  AText := '';
  try
    if not FileExists(APath) then
      Exit;
    AText := TFile.ReadAllText(APath, TEncoding.UTF8);
    if (Length(AText) >= 3) and (AText[1] = #$EF) and (AText[2] = #$BB) and
      (AText[3] = #$BF) then
      Delete(AText, 1, 3);
    Result := Trim(AText) <> '';
  except
    on E: Exception do
      AText := '';
  end;
end;

{ Semantic JSON equality: key order is preserved by System.JSON on both
  sides, so objects are compared pairwise; numbers are compared as values
  (string form for integers, double for anything else). }
function JsonTreesEqual(const A, B: TJSONValue): Boolean;
var
  I: Integer;
  NumA, NumB: Double;
begin
  Result := False;
  if (A = nil) or (B = nil) then
    Exit;

  if (A is TJSONNull) and (B is TJSONNull) then
    Exit(True);

  if (A is TJSONBool) and (B is TJSONBool) then
    Exit((A as TJSONBool).AsBoolean = (B as TJSONBool).AsBoolean);

  if (A is TJSONNumber) and (B is TJSONNumber) then
  begin
    if (A as TJSONNumber).Value = (B as TJSONNumber).Value then
      Exit(True);
    NumA := StrToFloat((A as TJSONNumber).Value, TFormatSettings.Invariant);
    NumB := StrToFloat((B as TJSONNumber).Value, TFormatSettings.Invariant);
    Exit(Abs(NumA - NumB) < 1e-9);
  end;

  if (A is TJSONString) and (B is TJSONString) then
    Exit((A as TJSONString).Value = (B as TJSONString).Value);

  if (A is TJSONArray) and (B is TJSONArray) then
  begin
    if (A as TJSONArray).Count <> (B as TJSONArray).Count then
      Exit;
    for I := 0 to (A as TJSONArray).Count - 1 do
      if not JsonTreesEqual((A as TJSONArray).Items[I],
        (B as TJSONArray).Items[I]) then
        Exit;
    Exit(True);
  end;

  if (A is TJSONObject) and (B is TJSONObject) then
  begin
    if (A as TJSONObject).Count <> (B as TJSONObject).Count then
      Exit;
    for I := 0 to (A as TJSONObject).Count - 1 do
    begin
      if (A as TJSONObject).Get(I).JsonString.Value <>
        (B as TJSONObject).Get(I).JsonString.Value then
        Exit;
      if not JsonTreesEqual((A as TJSONObject).Get(I).JsonValue,
        (B as TJSONObject).Get(I).JsonValue) then
        Exit;
    end;
    Exit(True);
  end;

  // Mixed kinds: not equal.
end;

{ Loads AOutBytes back through the runtime loader and compares the recovered
  JSON against the input document. For default-key containers APassword is
  ignored by the loader (it substitutes the built-in secret itself). }
function VerifyRoundTrip(const AJsonText, APassword: string;
  const ADefaultKey: Boolean; const AOutBytes: TBytes; out AErr: string): Boolean;
var
  Loaded: string;
  R: TAvroShieldResult;
  JsonA, JsonB: TJSONValue;
begin
  Result := False;
  AErr := '';
  R := AvroShieldLoadFromBytes(AOutBytes, APassword, Loaded, True);
  if R <> asrOk then
  begin
    AErr := 'runtime loader rejected the container (code ' + IntToStr(Ord(R)) + ')';
    Exit;
  end;
  if Trim(Loaded) = '' then
  begin
    AErr := 'runtime loader returned empty JSON';
    Exit;
  end;
  JsonA := TJSONObject.ParseJSONValue(Trim(AJsonText));
  JsonB := TJSONObject.ParseJSONValue(Trim(Loaded));
  if (JsonA = nil) or (JsonB = nil) then
  begin
    AErr := 'cannot re-parse the round-tripped JSON';
    JsonA.Free;
    JsonB.Free;
    Exit;
  end;
  try
    Result := JsonTreesEqual(JsonA, JsonB);
    if not Result then
      AErr := 'recovered JSON differs from the input document';
  finally
    JsonA.Free;
    JsonB.Free;
  end;
end;

function ParseArgs: Boolean;
var
  I: Integer;
  Arg: string;
begin
  Result := False;
  ContainerFormat := FORMAT_SHIELD;
  UseDefaultKey := False;
  BindMachine := False;
  UseHardware := False;
  NoVerify := False;
  Quiet := False;
  Password := '';

  if ParamCount < 2 then
    Exit;

  InputPath := ParamStr(1);
  OutputPath := ParamStr(2);

  I := 3;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '-p') or (Arg = '--password') then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      Password := ParamStr(I);
    end
    else if Arg = '--default-key' then
      UseDefaultKey := True
    else if Arg = '--bind' then
      BindMachine := True
    else if Arg = '--hardware' then
      UseHardware := True
    else if Arg = '--no-verify' then
      NoVerify := True
    else if Arg = '--quiet' then
      Quiet := True
    else if Arg = '--format' then
    begin
      if I + 1 > ParamCount then
        Exit;
      Inc(I);
      if SameText(ParamStr(I), 'v2') then
        ContainerFormat := FORMAT_V2
      else if SameText(ParamStr(I), 'shield') then
        ContainerFormat := FORMAT_SHIELD
      else
        Exit;
    end
    else
      Exit; // unknown argument
    Inc(I);
  end;

  // Protection-mode validation per format.
  if UseDefaultKey and (Password <> '') then
    Exit; // contradictory: both default-key and password requested
  if (ContainerFormat = FORMAT_SHIELD) and (not UseDefaultKey) and (Password = '') then
    Exit; // shield always needs one of the two
  if (ContainerFormat = FORMAT_V2) and UseDefaultKey then
    Exit; // v2 selects default-key automatically with an empty password

  Result := True;
end;

function WriteOutputBytes(const APath: string; const AData: TBytes): Boolean;
var
  FS: TFileStream;
begin
  Result := False;
  try
    FS := TFileStream.Create(APath, fmCreate);
    try
      if Length(AData) > 0 then
        FS.WriteBuffer(AData[0], Length(AData));
      Result := True;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

var
  JsonText: string;
  OutBytes: TBytes;
  ExitCode: Integer;
  SrcSize, OutSize: Integer;

begin
  ExitCode := EXIT_USAGE;

  if not ParseArgs then
  begin
    Usage;
    ExitCode := EXIT_USAGE;
  end
  else if not ReadUtf8File(InputPath, JsonText) then
  begin
    WriteLn('ERROR: cannot read input file: ' + InputPath);
    ExitCode := EXIT_READ;
  end
  else
  begin
    // Validate the input parses as a JSON object before doing any crypto.
    var RootJson: TJSONValue := TJSONObject.ParseJSONValue(Trim(JsonText));
    if (RootJson = nil) or not (RootJson is TJSONObject) then
    begin
      WriteLn('ERROR: input is not a valid JSON object: ' + InputPath);
      RootJson.Free;
      ExitCode := EXIT_PARSE;
    end
    else
    begin
      RootJson.Free;
      ExitCode := EXIT_BUILD;

      if ContainerFormat = FORMAT_SHIELD then
      begin
        var R: TAvroShieldResult := AvroShieldBuildFromJson(JsonText, Password,
          UseDefaultKey, BindMachine, UseHardware, OutBytes);
        if R <> asrOk then
        begin
          WriteLn('ERROR: shield build failed (code ' + IntToStr(Ord(R)) + ')');
          ExitCode := EXIT_BUILD;
        end
        else if not WriteOutputBytes(OutputPath, OutBytes) then
        begin
          WriteLn('ERROR: cannot write output file: ' + OutputPath);
          ExitCode := EXIT_WRITE;
        end
        else
        begin
          ExitCode := EXIT_OK;
          if not NoVerify then
          begin
            if not VerifyRoundTrip(JsonText, Password, UseDefaultKey, OutBytes, ErrMsg) then
            begin
              WriteLn('ERROR: verification failed - ' + ErrMsg);
              ExitCode := EXIT_VERIFY;
            end
            else if not Quiet then
              WriteLn('verify: PASS (runtime loader round-trip)');
          end;
        end;
      end
      else // FORMAT_V2
      begin
        if not EncryptJsonToAvroEncoFile(JsonText, AnsiString(Password), OutputPath) then
        begin
          WriteLn('ERROR: v2 build failed');
          ExitCode := EXIT_BUILD;
        end
        else
        begin
          ExitCode := EXIT_OK;
          if not NoVerify then
          begin
            // Load the v2 container back through the runtime reader.
            var Loaded: string := Trim(DecryptAvroEncoToString(OutputPath, AnsiString(Password)));
            var JsonA: TJSONValue := TJSONObject.ParseJSONValue(Trim(JsonText));
            var JsonB: TJSONValue := TJSONObject.ParseJSONValue(Loaded);
            if (JsonA = nil) or (JsonB = nil) or (not JsonTreesEqual(JsonA, JsonB)) then
            begin
              WriteLn('ERROR: verification failed - v2 round-trip mismatch');
              ExitCode := EXIT_VERIFY;
            end
            else if not Quiet then
              WriteLn('verify: PASS (v2 runtime loader round-trip)');
            JsonA.Free;
            JsonB.Free;
          end;
        end;
      end;
    end;
  end;

  if not Quiet then
  begin
    if ExitCode = EXIT_OK then
    begin
      SrcSize := Length(TEncoding.UTF8.GetBytes(JsonText));
      OutSize := 0;
      if FileExists(OutputPath) then
      begin
        try
          OutSize := Integer(TFile.GetSize(OutputPath));
        except
          OutSize := 0;
        end;
      end;
      if ContainerFormat = FORMAT_SHIELD then
      begin
        Write('format: shield, flags: ');
        if UseDefaultKey then
          Write('default-key')
        else
          Write('password');
        if BindMachine then
          Write(' +machine-bind');
        if UseHardware then
          Write(' +hardware');
        WriteLn;
      end
      else
      begin
        Write('format: v2 (');
        if Password = '' then
          Write('default-key')
        else
          Write('password');
        WriteLn(')');
      end;
      WriteLn('input : ' + IntToStr(SrcSize) + ' bytes');
      Write('output: ' + IntToStr(OutSize) + ' bytes');
      if (SrcSize > 0) and (OutSize > 0) then
        Write(Format(' (%.1f%% of source)', [100.0 * OutSize / SrcSize]));
      WriteLn;
      WriteLn('OK: ' + OutputPath);
    end;
  end;

  Halt(ExitCode);
end.