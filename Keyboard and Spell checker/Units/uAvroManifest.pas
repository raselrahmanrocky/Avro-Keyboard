{ =============================================================================
  uAvroManifest - parses and verifies the two signed trust artifacts:

    manifest.json         the resource catalog the browser / updater reads
                          (keys, versions, status, download URLs).
    resources.lock.json   the pinned inventory of the containers committed to
                          the public repository (sha256 + size + version), so
                          the offline gates verify containers WITHOUT the
                          private plaintext sources.

  Both are JSON wrappers around a canonical, line-based PAYLOAD. The wrapper is
  a JSON object with the keys manifestVersion (or lockVersion), keyId,
  signature and payload. (No literal braces are written in this comment: a
  brace would end the Delphi comment early, the same trap uAvroShieldVM
  documents.)

  The signature is Ed25519 over the exact UTF-8 bytes of the payload. The payload
  is signed as text, not as JSON, because two independent implementations
  (this unit and tools/resource-sync/sign_manifest.py) cannot agree byte-for-
  byte on JSON serialization, but can trivially agree on:

    avro-manifest-v1                 <- format tag (line 1)
    generated=<iso8601>
    keyid=<key id>
    keyepoch=<integer>
    resource<TAB>id<TAB>file<TAB>category<TAB>name<TAB>version
             <TAB>formatVersion<TAB>minAppVersion<TAB>size<TAB>sha256<TAB>url<TAB>status
             <TAB>keyEpoch
    ... one resource line per item, sorted by id ...

  (the lock tag is 'avro-lock-v1' and its resource columns are
   id, file, version, formatVersion, size, sha256, keyEpoch)

  keyEpoch is the only column APPENDED rather than inserted, and that is
  deliberate: an older reader requires at least the columns it knows and ignores
  the rest, so appending keeps a signed payload readable by both sides. Inserting
  it in the middle would have broken every existing reader. The value identifies
  which AvroShield IKM epoch a container was written for, which is how the
  runtime tells a stale rotation from ordinary corruption; 0 means the signer did
  not state one.

  COLUMN ORDER IS PART OF THE SIGNED BYTES, so a column added or moved here
  silently invalidates every existing signature. 'file' is the second manifest
  column and is what lookup-by-file-name and the installer's on-disk name both
  key off; it was missing from this list once already.

  TRUST RULES
  -----------
  * A manifest whose signed payload names a keyId that is neither the embedded
    one nor, while its window is open, the embedded PREDECESSOR, is REFUSED -
    not verified against whichever key happens to fit. That is what makes key
    rotation detectable instead of silently failing, and the predecessor entry
    is only there so a document published before a rotation is not refused the
    moment the client updates: it is dropped by regenerating uAvroManifestKey
    without --previous-pas.
  * The wrapper's own keyId/manifestVersion fields are NOT trusted; the payload
    is the only authority.
  * Nothing here decides policy (download, uninstall). It parses, verifies and
    answers the capability questions; the callers apply them.
  ============================================================================= }

unit uAvroManifest;

interface

uses
  System.SysUtils;

type
  TAvroManifestKind = (amkManifest, amkLock);

  { One resource. In a manifest the descriptive fields are populated; in a lock
    only Id/FileName/Version/FormatVersion/Size/Sha256 are. }
  TAvroResource = record
    Id:            string;
    FileName:      string; // repo-relative path, e.g. 'AnsiMapping/Ansi V1.AvroEnco'
    Category:      string;
    Name:          string;
    Version:       string;
    FormatVersion: Integer;
    MinAppVersion: string;
    Size:          Int64;
    Sha256:        string;
    Url:           string;
    Status:        string; // active | deprecated | revoked
    { IKM epoch the container was written for (0 = the signer did not state one).
      Not secret: it is a version number, and it is what lets the runtime decide
      between "this file is corrupt" and "this build predates the rotation". }
    KeyEpoch:      Integer;
  end;

  TAvroManifest = class
  public
    Kind:      TAvroManifestKind;
    Generated: string;
    KeyId:     string;
    KeyEpoch:  Integer;
    Signature: TBytes;
    Payload:   string;
    Resources: TArray<TAvroResource>;
    destructor Destroy; override;
  end;

{ Parses the JSON wrapper and its payload. Does NOT verify the signature. }
function AvroManifestParse(const AJsonText: string; out AManifest: TAvroManifest; out AError: string): Boolean;

{ Parses a bare canonical payload (no JSON wrapper). Exposed for tests. }
function AvroManifestParsePayload(const APayload: string; out AManifest: TAvroManifest; out AError: string): Boolean;

{ Selects the embedded key that the payload's keyId names - the current one,
  or the predecessor while its window is open - and verifies the signature with
  it. Any other keyId is refused without trying a signature. Assumes AManifest
  came from AvroManifestParse. }
function AvroManifestVerifySignature(const AManifest: TAvroManifest; out AError: string): Boolean;

{ Parse + verify in one call - the runtime entry point. On failure AManifest is
  nil and AError carries a caller-displayable reason. }
function AvroManifestLoadAndVerify(const AJsonText: string; out AManifest: TAvroManifest; out AError: string): Boolean;

function AvroManifestFind(const AManifest: TAvroManifest; const AId: string; out AResource: TAvroResource): Boolean;
function AvroManifestFindByFileName(const AManifest: TAvroManifest; const AFileName: string; out AResource: TAvroResource): Boolean;

{ Dotted-numeric version compare ('1.2' < '1.10'). Non-numeric segments are 0.
  Returns -1, 0 or 1. }
function AvroCompareVersions(const A, B: string): Integer;

{ Capability + policy question for one resource against this application.
  AReason is 'active', 'deprecated', 'revoked' or an 'update required (...)'
  message. True means the resource may be downloaded/kept. }
function AvroManifestResourceUsable(const AResource: TAvroResource; AAppFormatVersion: Integer; const AAppVersion: string; out AReason: string): Boolean;

{ SHA-256 of a file as lowercase hex ('' on failure), and of a byte buffer. }
function AvroSha256HexFile(const APath: string): string;
function AvroSha256Hex(const AData: TBytes): string;

implementation

uses
  System.Classes,
  System.Generics.Collections,
  System.Hash,
  System.JSON,
  System.NetEncoding,
  uAvroSecureMem,
  uAvroEd25519,
  uAvroManifestKey;

const
  MANIFEST_TAG = 'avro-manifest-v1';
  LOCK_TAG     = 'avro-lock-v1';

function BytesToHexLower(const B: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  Result := '';
  for I := 0 to Length(B) - 1 do
    Result := Result + H[B[I] shr 4] + H[B[I] and 15];
end;

function AvroSha256Hex(const AData: TBytes): string;
var
  Hash: THashSHA2;
begin
  Hash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  if Length(AData) > 0 then
    Hash.Update(AData);
  Result := BytesToHexLower(Hash.HashAsBytes);
end;

function AvroSha256HexFile(const APath: string): string;
var
  Stream: TFileStream;
  Hash:   THashSHA2;
  Buf:    array [0 .. 65535] of Byte;
  N:      Integer;
begin
  Result := '';
  if not FileExists(APath) then
    Exit;
  Hash := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    repeat
      N := Stream.Read(Buf, SizeOf(Buf));
      if N > 0 then
        Hash.Update(Buf, N);
    until N <= 0;
  finally
    Stream.Free;
  end;
  Result := BytesToHexLower(Hash.HashAsBytes);
end;

{ Constant-time equality for key identifiers (a length mismatch is not secret
  here, so a plain length check first is fine). }
function ConstEqStr(const A, B: string): Boolean;
var
  I: Integer;
  D: Cardinal;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  D := 0;
  for I := 1 to Length(A) do
    D := D or Cardinal(Ord(A[I]) xor Ord(B[I]));
  Result := D = 0;
end;

destructor TAvroManifest.Destroy;
begin
  AvroWipeAndRelease(Signature);
  AvroWipeString(Payload);
  inherited;
end;

function SplitLines(const AText: string): TArray<string>;
var
  List: TStringList;
  I:    Integer;
begin
  List := TStringList.Create;
  try
    List.LineBreak := #10;
    List.Text := AText;
    // TStringList drops a trailing empty line; that matches our canonical
    // "one LF after the last line" rule.
    SetLength(Result, List.Count);
    for I := 0 to List.Count - 1 do
      Result[I] := TrimRight(List[I]);
  finally
    List.Free;
  end;
end;

function SplitTabs(const ALine: string): TArray<string>;
begin
  Result := ALine.Split([#9]);
end;

function ParseIntDef(const AText: string; ADefault: Integer): Integer;
begin
  Result := StrToIntDef(Trim(AText), ADefault);
end;

function ParseInt64Def(const AText: string; ADefault: Int64): Int64;
begin
  Result := StrToInt64Def(Trim(AText), ADefault);
end;

function AvroManifestParsePayload(const APayload: string; out AManifest: TAvroManifest; out AError: string): Boolean;
var
  Lines: TArray<string>;
  I:     Integer;
  Line:  string;
  Fields: TArray<string>;
  Res:   TAvroResource;
  List:  TList<TAvroResource>;
begin
  Result := False;
  AError := '';
  AManifest := nil;

  if Trim(APayload) = '' then
  begin
    AError := 'The signed payload is empty.';
    Exit;
  end;

  Lines := SplitLines(APayload);
  if Length(Lines) = 0 then
  begin
    AError := 'The signed payload has no lines.';
    Exit;
  end;

  AManifest := TAvroManifest.Create;
  AManifest.Payload := APayload;
  if Lines[0] = MANIFEST_TAG then
    AManifest.Kind := amkManifest
  else if Lines[0] = LOCK_TAG then
    AManifest.Kind := amkLock
  else
  begin
    AError := 'Unknown signed payload format: ' + Lines[0];
    FreeAndNil(AManifest);
    Exit;
  end;

  List := TList<TAvroResource>.Create;
  try
    for I := 1 to Length(Lines) - 1 do
    begin
      Line := Lines[I];
      if Line = '' then
        Continue;
      if Copy(Line, 1, 10) = 'generated=' then
        AManifest.Generated := Copy(Line, 11, MaxInt)
      else if Copy(Line, 1, 6) = 'keyid=' then
        AManifest.KeyId := Copy(Line, 7, MaxInt)
      else if Copy(Line, 1, 9) = 'keyepoch=' then
        AManifest.KeyEpoch := ParseIntDef(Copy(Line, 10, MaxInt), 0)
      else if Copy(Line, 1, 9) = 'resource' + #9 then
      begin
        Fields := SplitTabs(Line);
        // Fields[0] is the literal 'resource'.
        Res := Default(TAvroResource);
        Res.Status := 'active';
        Res.FormatVersion := 1;
        if AManifest.Kind = amkLock then
        begin
          if Length(Fields) < 7 then
          begin
            AError := Format('Malformed lock resource line (%d fields).', [Length(Fields)]);
            Exit;
          end;
          Res.Id := Fields[1];
          Res.FileName := Fields[2];
          Res.Name := Fields[2]; // lock has no separate display name
          Res.Version := Fields[3];
          Res.FormatVersion := ParseIntDef(Fields[4], 1);
          Res.Size := ParseInt64Def(Fields[5], 0);
          Res.Sha256 := Fields[6];
          // Trailing column, so a lock written before keyEpoch existed still
          // parses to 0 instead of failing the length check above.
          if Length(Fields) >= 8 then
            Res.KeyEpoch := ParseIntDef(Fields[7], 0);
        end
        else
        begin
          if Length(Fields) < 12 then
          begin
            AError := Format('Malformed manifest resource line (%d fields).', [Length(Fields)]);
            Exit;
          end;
          Res.Id := Fields[1];
          Res.FileName := Fields[2];
          Res.Category := Fields[3];
          Res.Name := Fields[4];
          Res.Version := Fields[5];
          Res.FormatVersion := ParseIntDef(Fields[6], 1);
          Res.MinAppVersion := Fields[7];
          Res.Size := ParseInt64Def(Fields[8], 0);
          Res.Sha256 := Fields[9];
          Res.Url := Fields[10];
          Res.Status := Fields[11];
          // Same forward-compatibility rule as the lock: appended, so an older
          // manifest without it parses to 0.
          if Length(Fields) >= 13 then
            Res.KeyEpoch := ParseIntDef(Fields[12], 0);
        end;
        List.Add(Res);
      end
      // Unknown header lines are ignored so the format can grow without
      // breaking older clients (they are still covered by the signature).
    end;
    AManifest.Resources := List.ToArray;
  finally
    List.Free;
  end;

  Result := True;
end;

function JsonStr(const AObj: TJSONObject; const AName: string): string;
var
  V: TJSONValue;
begin
  Result := '';
  V := AObj.Values[AName];
  if V is TJSONString then
    Result := TJSONString(V).Value
  else if (V <> nil) and not(V is TJSONNull) then
    Result := V.Value;
end;

function AvroManifestParse(const AJsonText: string; out AManifest: TAvroManifest; out AError: string): Boolean;
var
  Text:    string;
  Root:    TJSONValue;
  Obj:     TJSONObject;
  Payload: string;
  SigB64:  string;
begin
  Result := False;
  AError := '';
  AManifest := nil;

  Text := AJsonText;
  if (Length(Text) >= 1) and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);
  if Trim(Text) = '' then
  begin
    AError := 'The signed file is empty.';
    Exit;
  end;

  Root := TJSONObject.ParseJSONValue(Text);
  if Root = nil then
  begin
    AError := 'The signed file is not valid JSON.';
    Exit;
  end;
  try
    if not(Root is TJSONObject) then
    begin
      AError := 'The signed file has an unexpected shape.';
      Exit;
    end;
    Obj := TJSONObject(Root);

    Payload := JsonStr(Obj, 'payload');
    SigB64 := JsonStr(Obj, 'signature');
    if Payload = '' then
    begin
      AError := 'The signed file has no payload.';
      Exit;
    end;

    if not AvroManifestParsePayload(Payload, AManifest, AError) then
      Exit;

    try
      AManifest.Signature := TNetEncoding.Base64.DecodeStringToBytes(SigB64);
    except
      AError := 'The signature is not valid base64.';
      FreeAndNil(AManifest);
      Exit;
    end;

    Result := True;
  finally
    Root.Free;
  end;
end;

function AvroManifestVerifySignature(const AManifest: TAvroManifest; out AError: string): Boolean;
var
  Pub:         TBytes;
  PayloadUtf8: TBytes;
  PrevKeyId:   string;
begin
  Result := False;
  AError := '';
  if AManifest = nil then
  begin
    AError := 'Nothing to verify.';
    Exit;
  end;

  { WHICH key decides, not whether SOME key fits. The payload's own keyId picks
    the candidate - the current key first, the predecessor second while its
    transition window is open (a rotation republished the document under the new
    key, but builds shipped before it still exist and must not lose the ability
    to install until they update). An id with no entry is refused here, before
    any signature work: verifying against whatever key happens to match would
    make the keyId line decorative, and it is the line that makes rotation a
    detectable event rather than a silent swap. }
  PrevKeyId := AvroManifestPreviousKeyId;
  if ConstEqStr(AManifest.KeyId, AvroManifestKeyId) then
    Pub := AvroManifestPublicKey
  else if (PrevKeyId <> '') and ConstEqStr(AManifest.KeyId, PrevKeyId) then
    Pub := AvroManifestPreviousPublicKey
  else
  begin
    AError := 'Signed with an unknown key (' + AManifest.KeyId + '); refusing.';
    Exit;
  end;

  PayloadUtf8 := TEncoding.UTF8.GetBytes(AManifest.Payload);
  try
    if not AvroEd25519Verify(Pub, PayloadUtf8, AManifest.Signature) then
    begin
      AError := 'The signature does not match the payload.';
      Exit;
    end;
    Result := True;
  finally
    AvroWipeAndRelease(Pub);
    AvroWipeAndRelease(PayloadUtf8);
  end;
end;

function AvroManifestLoadAndVerify(const AJsonText: string; out AManifest: TAvroManifest; out AError: string): Boolean;
var
  Parsed: TAvroManifest;
begin
  Result := False;
  AManifest := nil;
  if not AvroManifestParse(AJsonText, Parsed, AError) then
    Exit;
  if not AvroManifestVerifySignature(Parsed, AError) then
  begin
    Parsed.Free;
    Exit;
  end;
  AManifest := Parsed;
  Result := True;
end;

function AvroManifestFind(const AManifest: TAvroManifest; const AId: string; out AResource: TAvroResource): Boolean;
var
  I: Integer;
begin
  Result := False;
  AResource := Default(TAvroResource);
  if AManifest = nil then
    Exit;
  for I := 0 to Length(AManifest.Resources) - 1 do
    if SameText(AManifest.Resources[I].Id, AId) then
    begin
      AResource := AManifest.Resources[I];
      Exit(True);
    end;
end;

{ Matches by the file's last path component, because the manifest stores a
  repo-relative path ('AnsiMapping/Ansi V1.AvroEnco') while callers deal in the
  bare on-disk file name - the same normalization uResourceInstaller applies. }
function LastPathComponent(const APath: string): string;
begin
  Result := ExtractFileName(StringReplace(APath, '/', '\', [rfReplaceAll]));
end;

function AvroManifestFindByFileName(const AManifest: TAvroManifest; const AFileName: string; out AResource: TAvroResource): Boolean;
var
  I: Integer;
  Want: string;
begin
  Result := False;
  AResource := Default(TAvroResource);
  if AManifest = nil then
    Exit;
  Want := LastPathComponent(AFileName);
  for I := 0 to Length(AManifest.Resources) - 1 do
    if SameText(LastPathComponent(AManifest.Resources[I].FileName), Want) or SameText(AManifest.Resources[I].Name, Want) then
    begin
      AResource := AManifest.Resources[I];
      Exit(True);
    end;
end;

function NextVersionSegment(const AText: string; var AIndex: Integer): Integer;
var
  Start: Integer;
begin
  Result := 0;
  while (AIndex <= Length(AText)) and (AText[AIndex] <> '.') do
  begin
    if (AText[AIndex] >= '0') and (AText[AIndex] <= '9') then
      Result := Result * 10 + (Ord(AText[AIndex]) - Ord('0'))
    else
    begin
      // Stop at the first non-numeric character in this segment.
      Start := AIndex;
      while (AIndex <= Length(AText)) and (AText[AIndex] <> '.') do
        Inc(AIndex);
      AIndex := Start + (AIndex - Start);
      Break;
    end;
    Inc(AIndex);
  end;
  if (AIndex <= Length(AText)) and (AText[AIndex] = '.') then
    Inc(AIndex);
end;

function AvroCompareVersions(const A, B: string): Integer;
var
  IA, IB: Integer;
  NA, NB: Integer;
begin
  IA := 1;
  IB := 1;
  repeat
    NA := NextVersionSegment(A, IA);
    NB := NextVersionSegment(B, IB);
    if NA < NB then
      Exit(-1);
    if NA > NB then
      Exit(1);
  until (IA > Length(A)) and (IB > Length(B));
  Result := 0;
end;

function AvroManifestResourceUsable(const AResource: TAvroResource; AAppFormatVersion: Integer; const AAppVersion: string; out AReason: string): Boolean;
begin
  if SameText(AResource.Status, 'revoked') then
  begin
    AReason := 'revoked';
    Exit(False);
  end;
  if SameText(AResource.Status, 'deprecated') then
  begin
    AReason := 'deprecated';
    Exit(False);
  end;
  if AResource.FormatVersion > AAppFormatVersion then
  begin
    AReason := Format('update required (resource format %d newer than this app''s %d)', [AResource.FormatVersion, AAppFormatVersion]);
    Exit(False);
  end;
  if (AResource.MinAppVersion <> '') and (AvroCompareVersions(AAppVersion, AResource.MinAppVersion) < 0) then
  begin
    AReason := 'update required (needs Avro Keyboard ' + AResource.MinAppVersion + ' or newer)';
    Exit(False);
  end;
  AReason := 'active';
  Result := True;
end;

end.
