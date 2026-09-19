{
  Persistent encrypted ANSI mapping cache.

  Cache location:
    %APPDATA%\AvroKeyboard\Cache\<SHA-256 of source file>.cache

  The cache stores the decrypted UTF-8 mapping JSON encrypted with
  AES-256-GCM.  Its key includes the application secret, the source digest,
  and (for password containers) the user's password.  Therefore a cache made
  with one password cannot be opened with another password.

  IMPORTANT: this is the persistent/disk level of the cache. uAnsiEngineManager
  still turns the JSON into an in-memory engine; version clicks then swap the
  already prepared RAM engines and perform no file/decrypt/parse work.
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAnsiPersistentCache;

interface

uses
  System.SysUtils;

function LoadAnsiJSONCached(const ASourcePath: string;
  const APassword: AnsiString; out AJSON: string): Boolean;
procedure DeleteAnsiCache(const ASourcePath: string);
procedure CleanupAnsiCache;
function GetAnsiCacheDirectory: string;

implementation

uses
  System.Classes,
  System.Hash,
  System.IOUtils,
  System.SyncObjs,
  uAvroCryptoUtils,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uFileFolderHandling,
  DebugLog;

var
  { Serializes cache file writes. The startup preload decrypts engines in
    parallel worker threads and every worker can create a cache file; without
    this lock two workers writing different files would still be safe, but
    DeleteFile+RenameFile pairs could interleave with a reader of the same
    (digest-colliding) file, and force-closing the app mid-write could leave
    partial files. With the lock, writes are atomic and ordered. }
  CacheWriteLock: TCriticalSection;

const
  CACHE_MAGIC: array[0..7] of AnsiChar = ('A','V','R','O','C','A','C','H');
  CACHE_FORMAT_VERSION = 1;
  CACHE_PARSER_VERSION = 1; // increment whenever mapping parser semantics change
  CACHE_NONCE_SIZE = 12;
  CACHE_DIGEST_SIZE = 32;

type
  TAnsiCacheHeader = packed record
    Magic: array[0..7] of AnsiChar;
    FormatVersion: Cardinal;
    ParserVersion: Cardinal;
    SourceSize: Int64;
    SourceWriteTimeUtc: TDateTime;
    SourceSHA256: array[0..31] of Byte;
    Nonce: array[0..11] of Byte;
    PayloadSize: UInt64; // ciphertext + 16-byte GCM tag
  end;

function HashBytes(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

{ Size of one hashing read. 64 KB keeps the buffer in the allocator's medium
  block class and small enough that the read itself never dominates. }
const
  HASH_CHUNK_SIZE = 64 * 1024;

{ SHA-256 of a file, streamed in fixed-size chunks.

  This used to be TFile.ReadAllBytes + one Update: a full private copy of the
  container (114 KB for the largest shipped mapping) allocated, hashed and then
  zeroed, on every load path - on top of the decrypt buffer and the UTF-16
  string the caller builds next, with the parsed engine parked in RAM behind
  all three. Hashing needs none of that to exist at once, and the digest is
  identical because SHA-256 is defined over a stream. }
function HashFile(const APath: string; out ASize: Int64): TBytes;
var
  FS: TFileStream;
  Chunk: TBytes;
  BytesRead: Integer;
  H: THashSHA2;
begin
  Result := nil;
  ASize := 0;
  SetLength(Chunk, HASH_CHUNK_SIZE);
  FS := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
    repeat
      BytesRead := FS.Read(Chunk[0], HASH_CHUNK_SIZE);
      if BytesRead <= 0 then
        Break;
      H.Update(Chunk, Cardinal(BytesRead));
      Inc(ASize, BytesRead);
    until False;
    Result := H.HashAsBytes;
  finally
    if Length(Chunk) > 0 then
      FillChar(Chunk[0], Length(Chunk), 0);
    FS.Free;
  end;
end;

function BytesToHex(const ABytes: TBytes): string;
const
  Hex: array[0..15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  SetLength(Result, Length(ABytes) * 2);
  for I := 0 to High(ABytes) do
  begin
    Result[I * 2 + 1] := Hex[ABytes[I] shr 4];
    Result[I * 2 + 2] := Hex[ABytes[I] and $0F];
  end;
end;

function GetAnsiCacheDirectory: string;
begin
  // Per-user Roaming AppData: always writable without elevated rights, so
  // the cache actually persists across runs (ProgramData required
  // installer-created ACLs and could silently fall back to decrypting
  // every startup). Format stays <SHA-256>.cache.
  Result := IncludeTrailingPathDelimiter(
    GetEnvironmentVariable('APPDATA')) + 'AvroKeyboard\Cache\';
  ForceDirectories(Result);
end;

function GetLegacyAnsiCacheDirectory: string;
begin
  // Cache location used by versions before the AppData move (ProgramData).
  Result := IncludeTrailingPathDelimiter(GetAvroDataDir) + 'Cache\';
end;

function CachePathForDigest(const ADigest: TBytes): string;
begin
  Result := GetAnsiCacheDirectory + BytesToHex(ADigest) + '.cache';
end;

function SameDigest(const A: array of Byte; const B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(B) = 0) or CompareMem(@A[0], @B[0], Length(B)));
end;

function BuildCacheKey(const ASourceDigest: TBytes;
  const APassword: AnsiString): TBytes;
var
  Secret: string;
  Material: TBytes;
begin
  // Password becomes key material for password-protected containers. For
  // default-key containers the application's obfuscated secret is sufficient.
  Secret := GetAvroEncoDefaultSecret + '|ANSI-CACHE-V1|' + string(APassword);
  Material := TEncoding.UTF8.GetBytes(Secret);
  try
    Result := DeriveKeySHA256FromRawBytes(Material, ASourceDigest);
  finally
    if Length(Material) > 0 then
      FillChar(Material[0], Length(Material), 0);
    Secret := '';
  end;
end;

function HeaderAAD(const H: TAnsiCacheHeader): TBytes;
var
  AADSize: Integer;
begin
  // Authenticate every header field except Nonce/PayloadSize; those are
  // validated separately and nonce is already an input to GCM.
  AADSize := NativeInt(@H.Nonce) - NativeInt(@H);
  SetLength(Result, AADSize);
  Move(H, Result[0], AADSize);
end;

function TryReadCache(const ACachePath: string; const ADigest: TBytes;
  const ASourceSize: Int64; const ASourceTime: TDateTime;
  const APassword: AnsiString; out AJSON: string): Boolean;
var
  FS: TFileStream;
  H: TAnsiCacheHeader;
  Cipher, Plain, Key, Nonce, AAD: TBytes;
begin
  Result := False;
  AJSON := '';
  if not FileExists(ACachePath) then Exit;
  try
    FS := TFileStream.Create(ACachePath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < SizeOf(H) then Exit;
      FS.ReadBuffer(H, SizeOf(H));
      if not CompareMem(@H.Magic[0], @CACHE_MAGIC[0], SizeOf(CACHE_MAGIC)) then Exit;
      if H.FormatVersion <> CACHE_FORMAT_VERSION then Exit;
      if H.ParserVersion <> CACHE_PARSER_VERSION then Exit;
      if H.SourceSize <> ASourceSize then Exit;
      if H.SourceWriteTimeUtc <> ASourceTime then Exit;
      if not SameDigest(H.SourceSHA256, ADigest) then Exit;
      if (H.PayloadSize < 16) or (H.PayloadSize > UInt64(MaxInt)) then Exit;
      if UInt64(FS.Size - SizeOf(H)) <> H.PayloadSize then Exit;
      SetLength(Cipher, Integer(H.PayloadSize));
      FS.ReadBuffer(Cipher[0], Length(Cipher));
    finally
      FS.Free;
    end;

    SetLength(Nonce, CACHE_NONCE_SIZE);
    Move(H.Nonce[0], Nonce[0], CACHE_NONCE_SIZE);
    AAD := HeaderAAD(H);
    Key := BuildCacheKey(ADigest, APassword);
    if not AES256GCMDecrypt(Cipher, Key, Nonce, AAD, Plain) then Exit;
    AJSON := Trim(TEncoding.UTF8.GetString(Plain));
    Result := (AJSON <> '') and (AJSON[1] = '{');
  except
    Result := False;
    AJSON := '';
  end;
  if Length(Plain) > 0 then FillChar(Plain[0], Length(Plain), 0);
  if Length(Key) > 0 then FillChar(Key[0], Length(Key), 0);
end;

procedure WriteCache(const ACachePath: string; const ADigest: TBytes;
  const ASourceSize: Int64; const ASourceTime: TDateTime;
  const APassword: AnsiString; const AJSON: string);
var
  H: TAnsiCacheHeader;
  Plain, Cipher, Key, Nonce, AAD: TBytes;
  FS: TFileStream;
  TempPath: string;
begin
  FillChar(H, SizeOf(H), 0);
  Move(CACHE_MAGIC[0], H.Magic[0], SizeOf(CACHE_MAGIC));
  H.FormatVersion := CACHE_FORMAT_VERSION;
  H.ParserVersion := CACHE_PARSER_VERSION;
  H.SourceSize := ASourceSize;
  H.SourceWriteTimeUtc := ASourceTime;
  Move(ADigest[0], H.SourceSHA256[0], CACHE_DIGEST_SIZE);

  FillRandomBytes(Nonce, CACHE_NONCE_SIZE);
  Move(Nonce[0], H.Nonce[0], CACHE_NONCE_SIZE);
  Plain := TEncoding.UTF8.GetBytes(AJSON);
  Key := BuildCacheKey(ADigest, APassword);
  // Payload size is deterministic for GCM: plaintext + 16-byte tag.
  H.PayloadSize := UInt64(Length(Plain) + 16);
  AAD := HeaderAAD(H);
  AES256GCMEncrypt(Plain, Key, Nonce, AAD, Cipher);

  TempPath := ACachePath + '.tmp';
  CacheWriteLock.Enter;
  try
    FS := TFileStream.Create(TempPath, fmCreate);
    try
      FS.WriteBuffer(H, SizeOf(H));
      if Length(Cipher) > 0 then
        FS.WriteBuffer(Cipher[0], Length(Cipher));
    finally
      FS.Free;
    end;
    if FileExists(ACachePath) then
      DeleteFile(ACachePath);
    if not RenameFile(TempPath, ACachePath) then
      DeleteFile(TempPath);
  finally
    CacheWriteLock.Leave;
  end;

  if Length(Plain) > 0 then FillChar(Plain[0], Length(Plain), 0);
  if Length(Key) > 0 then FillChar(Key[0], Length(Key), 0);
end;

function LoadAnsiJSONCached(const ASourcePath: string;
  const APassword: AnsiString; out AJSON: string): Boolean;
var
  Digest: TBytes;
  SourceSize: Int64;
  SourceTime: TDateTime;
  CachePath: string;
  LegacyPath: string;
begin
  Result := False;
  AJSON := '';
  if not FileExists(ASourcePath) then Exit;
  try
    Digest := HashFile(ASourcePath, SourceSize);
    SourceTime := TFile.GetLastWriteTimeUtc(ASourcePath);
    CachePath := CachePathForDigest(Digest);

    if TryReadCache(CachePath, Digest, SourceSize, SourceTime,
      APassword, AJSON) then
    begin
      Log('ANSI persistent cache HIT: ' + ExtractFileName(ASourcePath));
      Exit(True);
    end;

    // Legacy location (ProgramData, versions before the AppData move):
    // read-only fallback. On a valid hit the entry is migrated to AppData.
    LegacyPath := GetLegacyAnsiCacheDirectory + BytesToHex(Digest) + '.cache';
    if (LegacyPath <> CachePath) and
      TryReadCache(LegacyPath, Digest, SourceSize, SourceTime,
        APassword, AJSON) then
    begin
      Log('ANSI persistent cache LEGACY HIT (migrated): ' +
        ExtractFileName(LegacyPath));
      try
        WriteCache(CachePath, Digest, SourceSize, SourceTime, APassword, AJSON);
      except
        // Migration write failure is non-fatal: the JSON is already loaded.
      end;
      Exit(True);
    end;

    // Cache miss: perform the expensive operation once, then persist it.
    if IsEncoFile(ASourcePath) then
      AJSON := Trim(DecryptAvroEncoToString(ASourcePath, APassword))
    else
      AJSON := Trim(TFile.ReadAllText(ASourcePath, TEncoding.UTF8));
    if (AJSON = '') or (AJSON[1] <> '{') then Exit;

    try
      WriteCache(CachePath, Digest, SourceSize, SourceTime, APassword, AJSON);
      Log('ANSI persistent cache CREATED: ' + ExtractFileName(CachePath));
    except
      on E: Exception do
        Log('ANSI persistent cache write failed: ' + E.Message);
    end;
    Result := True;
  except
    on E: Exception do
      Log('ANSI persistent cache load failed: ' + E.Message);
  end;
end;

procedure DeleteAnsiCache(const ASourcePath: string);
var
  Digest: TBytes;
  N: Int64;
  P, LegacyP: string;
begin
  if not FileExists(ASourcePath) then Exit;
  try
    Digest := HashFile(ASourcePath, N);
    P := CachePathForDigest(Digest);
    LegacyP := GetLegacyAnsiCacheDirectory + BytesToHex(Digest) + '.cache';
    CacheWriteLock.Enter;
    try
      if FileExists(P) then DeleteFile(P);
      if (LegacyP <> P) and FileExists(LegacyP) then DeleteFile(LegacyP);
    finally
      CacheWriteLock.Leave;
    end;
  except
    // Cache maintenance must never affect normal application operation.
  end;
end;

procedure CleanupAnsiCache;
var
  SR: TSearchRec;
  Dir: string;
begin
  Dir := GetAnsiCacheDirectory;
  CacheWriteLock.Enter;
  try
    if FindFirst(Dir + '*.tmp', faAnyFile, SR) = 0 then
      try
        repeat
          DeleteFile(Dir + SR.Name);
        until FindNext(SR) <> 0;
      finally
        FindClose(SR);
      end;
  finally
    CacheWriteLock.Leave;
  end;
end;

initialization
  CacheWriteLock := TCriticalSection.Create;

finalization
  FreeAndNil(CacheWriteLock);

end.
