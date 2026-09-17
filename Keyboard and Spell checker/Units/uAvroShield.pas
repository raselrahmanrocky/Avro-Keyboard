{
  =============================================================================
  uAvroShield - Pure Pascal .AvroShield container reader + bytecode parser
  + deobfuscator, byte-compatible with the AvroShield Python toolchain
  (avroenco\avroshield.py, bytecode.py, bytecode_parser.py, obfuscator.py).

  Data flow (unprotect), all in memory - nothing plain is ever written to
  disk:

    .AvroShield -> verify HMAC-SHA512 -> AES-256-GCM decrypt -> zlib
                -> bytecode -> BytecodeParser -> deobfuscate
                -> in-memory JSON text (returned to the caller)

  Obfuscation (container format v3) and the developer comment domain:

    values         Base64(plain XOR SHA-256-CTR keystream keyed by the value
                   seed and the value's context path), so identical plaintext
                   at different positions encrypts differently.
    metadata blob  masked with HKDF-SHA256(container master key) instead of a
                   constant compiled into this unit - which is what makes the
                   obfuscation keyed: without the container key the value seed
                   and the key map stay unreachable.
    comments       obfuscated in a second domain keyed by
                   HKDF-SHA256(developer IKM, salt = value seed). The runtime
                   never derives that key and never links the IKM, so comment
                   text survives in the container without being readable to
                   anyone who merely opens it (see
                   AvroEncoEngine\docs\obfuscation-codec.md).
    runtime cost   IncludeComments = False drops every comment field before the
                   Base64 decode: no decode, no keystream, no allocation, and
                   the mapping parser never sees the field.

    Format v2 containers keep loading through the legacy path (constant
    metadata mask, comments in the value domain), so the switch is not a
    re-release of every existing file.

  Key derivation (container version 2; the v1 Argon2id schedule was removed
  project-wide, including password files, by explicit owner decision):

    default-key containers (flag $10):
      master = HKDF-SHA256(secret, salt, info, len=32)   // RFC 5869, ~us
    password containers:
      master = PBKDF2-HMAC-SHA256(password, salt, 100000, len=32)  // ~100 ms
    final  = SHA-512(master || machine_factor(16) || hardware_factor(16))
    enc_key = final[0..31], mac_key = final[32..63]

  This Delphi unit is the authoritative spec for the v2 KDF. The former
  'matches avroenco/src/crypto.py' claim no longer holds: that external
  Python toolchain must be migrated separately if it is still in use, and the
  same now applies to the obfuscation stage - format v3 keys the metadata mask
  from the container key, which an obfuscator.py that assumes the old constant
  mask cannot reproduce. (GCM and zlib stages are unchanged.)

  Machine factor: SHA-256(Windows MachineGuid UTF-8)[:16] (fallback: primary
  MAC as decimal string), identical to the Python side (D11). The hardware
  factor falls back to the machine-derived value when no token file exists,
  exactly like the Python engine.
  =============================================================================
}

{$OVERFLOWCHECKS OFF}
{$RANGECHECKS OFF}

{ Inlining OFF because this unit contains VMProtect marker regions. An inlined
  marked routine leaves an unprotected copy of the same logic in its caller,
  which defeats the marker. Only marker-bearing units disable inlining;
  uAvroCryptoUtils (the AES/GCM hot path) deliberately keeps it. }
{$INLINE OFF}

unit uAvroShield;

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections;

type
  { Result codes for AvroShieldLoadFromFile / AvroShieldLoadFromBytes. }
  TAvroShieldResult = (
    asrOk = 0,
    asrFileNotFound,
    asrFileTooShort,
    asrBadMagic,
    asrBadVersion,
    asrMachineMismatch,
    asrMachineBindRequired,
    asrHmacFailed,
    asrDecryptFailed,
    asrDecompressFailed,
    asrBadBytecode,
    asrCorruptPayload,
    asrEmptyPassword,     // writer: password required but none given
    asrNotJsonObject,     // writer: input is not a JSON object
    asrUnknown
  );

  { Options for AvroShieldLoadFromBytesUtf8Ex. The runtime never uses this
    record: it calls AvroShieldLoadForRuntime, which pins IncludeComments to
    False and DefaultSecretIKM to the embedded secret, so the shipped path
    cannot be talked into disclosing comment text or accepting a foreign key. }
  TAvroShieldLoadOptions = record
    UseMachineBind: Boolean;
    { True only for developer tooling (AvroEncoBuilder --unpack): decode the
      comment domain and keep the fields. False drops every comment field
      before it is decoded, allocated or parsed. }
    IncludeComments: Boolean;
    { Default-key IKM from outside the process (builder key file). Empty = the
      secret embedded in this unit. }
    DefaultSecretIKM: TBytes;
    { Developer comment key. The comment obfuscation domain is keyed by this
      IKM, which is never derived from the container key and is never linked
      into the runtime build. Empty = comments cannot be decoded. }
    CommentsIKM: TBytes;
  end;

  { In-memory JSON value model shared by the bytecode parser and the
    deobfuscator. Objects keep Keys parallel to Items so key order is
    preserved exactly like Python's dicts. }
  TAvroNodeKind = (nkNull, nkBool, nkInt, nkFloat, nkString, nkArray, nkObject);

  TAvroNode = class
  public
    Kind: TAvroNodeKind;
    BoolVal: Boolean;
    IntVal: Int64;
    FloatVal: Double;
    StrVal: string;
    Items: TObjectList<TAvroNode>;   // array elements / object values
    Keys: TStringList;               // object keys, parallel to Items
    constructor Create;
    destructor Destroy; override;
  end;

  EAvroShieldError = class(Exception);

{ Fills in the runtime defaults: machine bind on, comments dropped, both IKM
  overrides empty. }
function AvroShieldDefaultLoadOptions: TAvroShieldLoadOptions;

{ Loads, verifies, decrypts, parses and deobfuscates an .AvroShield file.
  On asrOk, AJSONText holds the deobfuscated mapping JSON (in memory only). }
function AvroShieldLoadFromFile(const AFileName, APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ Same, from raw file bytes (used by tests and in-memory callers). The JSON
  is returned as a string, which the caller cannot reliably wipe - prefer
  AvroShieldLoadFromBytesUtf8 or AvroShieldLoadForRuntime on any load path. }
function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ Core loader. Returns the deobfuscated mapping as UTF-8 bytes so the caller
  owns the plaintext buffer and can wipe it deterministically. All derived key
  material and intermediates are wiped before return. }
function AvroShieldLoadFromBytesUtf8(const AData: TBytes; const APassword: string;
  out AJsonUtf8: TBytes; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ Same pipeline with the developer knobs (see TAvroShieldLoadOptions). Used by
  AvroEncoBuilder for the pack/unpack round trip; never by the runtime. }
function AvroShieldLoadFromBytesUtf8Ex(const AData: TBytes; const APassword: string;
  const AOptions: TAvroShieldLoadOptions; out AJsonUtf8: TBytes): TAvroShieldResult;

{ Tooling entry: unwraps a container down to the decrypted but still
  OBFUSCATED bytecode - no parse, no deobfuscation. That is exactly the view an
  attacker has after extracting the container key from the binary, so the
  static-leak gate scans this buffer for legible mapping text (Bengali
  codepoints, '#$' literals, comment words). Never call it at runtime. }
function AvroShieldExtractObfuscatedBytecode(const AData: TBytes;
  const APassword: string; const ADefaultSecretIKM: TBytes;
  AUseMachineBind: Boolean; out ABytecode: TBytes): TAvroShieldResult;

{ True for every container version this build can read. Single source of truth
  for "is this a Shield container we understand": uAvroEncoCrypto used to keep
  its own copy of the version constant, which is how the two could drift. }
function AvroShieldSupportedVersion(AVer: Byte): Boolean;

{ The version written into new containers. Kept public so tooling and the
  header writers cannot hardcode a stale number. }
function AvroShieldCurrentVersion: Byte;

{ The comment domain marker used by the codec: comment fields are addressed
  under a distinct context prefix and encoded with the developer comment key,
  so a comment token can never be mistaken for (or replayed as) a value token.
  Public because the self-test asserts the domain separation directly. }
function AvroShieldIsCommentField(const AName: string): Boolean;
function AvroShieldCommentCtx(const ACtx, AName: string): string;

{ Metadata mask for a container the caller has already opened, derived from
  the container master key. This is what makes the obfuscation keyed: the
  metadata blob carries the value seed and the key map, and it can no longer be
  unmasked without the container key. }
function AvroShieldMetaMask(const AMaster: TBytes): TBytes;

{ Comment domain key: HKDF-SHA256(comment IKM, salt = value seed). Derived per
  container, and layered underneath the metadata mask - the seed it needs is
  only reachable through the keyed blob. Exposed so the self-test can show the
  two domains are independent rather than assuming it. }
function AvroShieldCommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;

{ Runtime entry point: same as AvroShieldLoadFromBytesUtf8 except that every
  failure is collapsed to a single externally visible result code, so a caller
  that can be observed cannot learn which stage rejected the container. The
  detailed codes remain available through the non-runtime entry points for the
  builder, the KATs and support builds. }
function AvroShieldLoadForRuntime(const AData: TBytes; const APassword: string;
  out AJsonUtf8: TBytes; AUseMachineBind: Boolean = True): TAvroShieldResult;

{ 16-byte machine identifier: SHA-256(MachineGuid UTF-8)[:16], MAC fallback. }
function AvroShieldMachineId: TBytes;

{ Parses AvroShield bytecode into a node tree (exposed for the self-test). }
function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;

{ Inverts the obfuscation pipeline on a node tree (exposed for the self-test).
  AValue must be freed by the caller. This is the format-v2 entry point: it
  unmasks the metadata with the fixed legacy seed and decodes comments with the
  value seed, which is exactly how v2 containers were written. Format-v3
  containers must go through AvroShieldDeobfuscateEx with their derived keys. }
function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;

{ Format-v3 deobfuscation. AKeyMeta is the keyed metadata mask (see
  AvroShieldMetaMask); ACommentsIKM is the developer comment IKM, which the
  core turns into the comment key once the value seed is available.
  AIncludeComments=False drops every comment field without decoding it: no
  Base64 decode, no XOR keystream, no UTF-16 allocation. }
function AvroShieldDeobfuscateEx(const AObfuscated: TAvroNode;
  const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean;
  out AValue: TAvroNode): Boolean;

{ Serializes a node tree to compact JSON text (loader/tests). }
function AvroShieldNodeToJSON(const ANode: TAvroNode): string;

{ True when a Shield-format container on disk is protected with the built-in
  default application secret (flag AVROSHLD_FLAG_DEFAULT_KEY) and therefore
  loads transparently without any password. False for password-protected
  Shield containers and for non-Shield / unreadable files. }
function AvroShieldContainerUsesDefaultKey(const AFilePath: string): Boolean;

{ v2 KDF primitives (exposed for the kat_shieldkdf self-test vectors; the
  container loader/writer use them through the unit-private
  ShieldKdfDefaultKey / ShieldKdfPasswordKey wrappers). }
function HkdfExtractSHA256(const ASalt, AIKM: TBytes): TBytes;
function HkdfExpandSHA256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
function Pbkdf2HMACSHA256(const APassword, ASalt: TBytes;
  AIterations, ADkLen: Integer): TBytes;

{ Writer side: builds a Shield-format container from mapping JSON, the exact
  inverse of AvroShieldLoadFromBytes. The pipeline runs entirely in RAM:
    JSON -> obfuscated bytecode -> zlib -> AES-256-GCM -> HMAC-SHA512 trailer.
  ADefaultKey=True protects the container with the built-in default secret
  (no password prompt ever); ADefaultKey=False requires a non-empty
  APassword. ABindToMachine / AUseHardwareFactor set the matching header
  flags (shipped files must stay portable: no bind).

  ADefaultSecretIKM supplies the default-key IKM from outside the process.
  AvroEncoBuilder uses it to drive builds from a key file so the build tool
  binary embeds no secret; leave it empty to use the embedded secret, which
  is what the self-tests and a load-back verification do. Because the loader
  always uses the embedded secret, a key file that does not match it is
  caught by the builder's round-trip verification instead of shipping.

  ACommentsIKM is the developer comment key. When supplied, every comment
  field is encoded in a separate obfuscation domain keyed by it; when empty,
  comments fall back to the value domain (self-tests only). The comment key is
  deliberately NOT derived from any container key, because that is what makes
  comment text unrecoverable from a shipped container while the runtime keeps
  skipping those fields entirely (see the obfuscation codec doc).

  On asrOk, AOutBytes holds the complete container and can be written to a
  .AvroEnco file. All intermediate key material and plaintext buffers are
  wiped before the function returns. }
function AvroShieldBuildFromJson(const AJsonText, APassword: string;
  const ADefaultKey, ABindToMachine, AUseHardwareFactor: Boolean;
  out AOutBytes: TBytes; const ADefaultSecretIKM: TBytes = nil;
  const ACommentsIKM: TBytes = nil): TAvroShieldResult;

implementation

uses
  System.Hash,
  System.ZLib,
  System.NetEncoding,
  System.JSON,
  System.Math,
  Winapi.Windows,
  Winapi.IpHlpApi,
  Winapi.IpTypes,
  uAvroCryptoUtils,
  uAvroSecureMem,
  uAvroShieldVM;

{ Error-text policy for the parse path.

  These messages name the internal structure and the exact check that failed
  ('Truncated entry node', 'Entry checksum mismatch', 'Trailing garbage after
  entries'). Two problems with shipping them: they are a static description of
  the format readable in a 'strings' dump, and any path where they do escape
  hands an attacker a free oracle for iterating on a malformed container and
  for locating fault-injection targets.

  In a Release runtime build the description is therefore gone while the
  result code still reaches the caller. Builds that legitimately need the text
  - the offline builder and support builds - define AVROSHIELD_VERBOSE_ERRORS.

  Note the parse entry point swallows these exceptions internally and reports
  False, so the practical effect of this policy is on the static strings and
  on the paths that do propagate. }

const
  SHIELD_OPAQUE_ERROR_TEXT = 'AvroShield: invalid container';

function ShieldOpaqueError(const AMessage: string): EAvroShieldError;
begin
{$IFDEF AVROSHIELD_VERBOSE_ERRORS}
  Result := EAvroShieldError.Create(AMessage);
{$ELSE}
  Result := EAvroShieldError.Create(SHIELD_OPAQUE_ERROR_TEXT);
{$ENDIF}
end;

{ Writer-side errors are never attacker-facing: the builder is a local offline
  tool, so its diagnostics stay fully descriptive in every build. }
function ShieldWriterError(const AMessage: string): EAvroShieldError;
begin
  Result := EAvroShieldError.Create(AMessage);
end;

const
  // ---- .AvroShield container ----
  // v2: Argon2-free key schedule (HKDF-SHA256 / PBKDF2-HMAC-SHA256).
  // v1 (Argon2id) containers are rejected cleanly as asrBadVersion and must
  // be rebuilt with the current AvroEncoBuilder - there is intentionally no
  // legacy Argon2 fallback path anywhere in the project.
  // v3: same key schedule as v2, but the obfuscation layer is keyed. The
  // metadata blob that carries the value seed and the key map is no longer
  // masked with a constant that ships in this unit; it is masked with a key
  // derived from the container master key, so the obfuscation cannot be
  // inverted without the container key. v2 containers keep loading through the
  // legacy path (constant mask, comments in the value domain).
  AS_VERSION = 3;
  AS_VERSION_LEGACY = 2;
  AS_HEADER_SIZE = 58;
  AS_TRAILER_SIZE = 80;   // auth_tag(16) + hmac(64)
  AS_HMAC_SIZE = 64;

  FLAG_PASSWORD = $01;
  FLAG_HARDWARE = $02;
  FLAG_MACHINE_BIND = $04;
  FLAG_BYTECODE_V1 = $08;

  // Container protected with the built-in default application secret
  // (GetAvroEncoDefaultSecret) instead of a user password: it loads
  // transparently without any prompt. Shipped built-in mappings use this;
  // external/user files keep FLAG_PASSWORD so they always prompt.
  AVROSHLD_FLAG_DEFAULT_KEY = $10;

  // ---- Shield v2 KDF (NO Argon2: removed project-wide, password files
  // included, by explicit owner decision for instant cold start) ----
  // Default-key containers: HKDF-SHA256 (RFC 5869) over the embedded app
  // secret + per-file salt - microseconds, the correct tool for an
  // embedded high-entropy secret (KDF slowness never protected it).
  // Password containers: PBKDF2-HMAC-SHA256 (RFC 2898) - a real
  // password-stretching KDF at ~100 ms/unlock (once per session).
  // Honest trade-off: PBKDF2 has no memory-hardness, so password files
  // are weaker against GPU/ASIC brute force than under Argon2id;
  // accepted explicitly, still safe against casual attack.
  SHIELD_MASTER_LEN = 32;
  SHIELD_HKDF_INFO_DEFAULT = 'AvroShield-v2/hkdf-sha256/default-key';
  SHIELD_PBKDF2_ITERATIONS = 100000;

  // ---- bytecode ----
  BC_HEADER_SIZE = 23;
  BC_XOR_SEED = 'AvroShieldBytecodeXORv1';

  TYPE_NULL = $00;
  TYPE_STRING = $01;
  TYPE_NUMBER = $02;
  TYPE_BOOLEAN = $03;
  TYPE_ARRAY = $04;
  TYPE_OBJECT = $05;
  TYPE_REFERENCE = $06;
  TYPE_OBFUSCATED = $07;

  // ---- obfuscation ----
  META_KEY = '_obf_meta';

  // HKDF info labels for the two obfuscation domains. Changing either one is a
  // format break for v3 containers, so they are written down here rather than
  // inline at the call sites.
  OBF_INFO_META = 'AvroShield-v3/obf-meta';
  OBF_INFO_COMMENTS = 'AvroShield-v3/comments';

  // Fields that carry developer documentation. They are obfuscated in their
  // own domain (see OBF_INFO_COMMENTS) and are dropped by the runtime before
  // any decoding happens. The list is narrow on purpose: it is the set the
  // mapping schema actually uses, and every name in it is a claim that the
  // runtime will never need the value.
  OBF_COMMENT_FIELDS: array [0 .. 2] of string = ('Comment', 'comment', '_comment');

{ =============================================================================
  Byte helpers
  ============================================================================= }

{ Byte-string builders for the fixed obfuscation seeds (Delphi has no
  dynamic-array typed constants). }
function AsMagic: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROSHLD');
end;

function AsMagicBC: TBytes;
begin
  Result := TEncoding.ASCII.GetBytes('AVROBC');
end;

function StrTag: TBytes;
begin
  SetLength(Result, 4);
  Result[0] := $73; // 's'
  Result[1] := $74; // 't'
  Result[2] := $72; // 'r'
  Result[3] := 0;
end;

function MetaSeed: TBytes;
const
  M: array [0 .. 17] of Byte = ($41, $76, $72, $6F, $53, $68, $69, $65,
    $6C, $64, $4D, $65, $74, $61, $56, $31, 0, 1);
begin
  SetLength(Result, Length(M));
  Move(M[0], Result[0], Length(M));
end;

function BE16(const AData: TBytes; AOff: Integer): Word;
begin
  Result := (Word(AData[AOff]) shl 8) or AData[AOff + 1];
end;

function BE32(const AData: TBytes; AOff: Integer): Cardinal;
begin
  Result := (Cardinal(AData[AOff]) shl 24) or (Cardinal(AData[AOff + 1]) shl 16) or
    (Cardinal(AData[AOff + 2]) shl 8) or AData[AOff + 3];
end;

function BcRead(const AData: TBytes; var AOff: Integer; ACount: Integer): TBytes;
begin
  if (AOff < 0) or (ACount < 0) or (AOff + ACount > Length(AData)) then
    raise ShieldOpaqueError('Truncated bytecode');
  SetLength(Result, ACount);
  if ACount > 0 then
    Move(AData[AOff], Result[0], ACount);
  Inc(AOff, ACount);
end;

function BytesEqualAt(const AData: TBytes; AOff: Integer; const AMagic: TBytes): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AOff < 0) or (AOff + Length(AMagic) > Length(AData)) then
    Exit;
  for I := 0 to Length(AMagic) - 1 do
    if AData[AOff + I] <> AMagic[I] then
      Exit;
  Result := True;
end;

function ConstTimeEqual(const A, B: TBytes): Boolean;
var
  I, D: Integer;
begin
  { Virtualised: this is the single comparison that decides whether the HMAC
    matched, the machine binding matched and the GCM tag matched. Its control
    flow is the most valuable thing in the unit to an attacker, and it is a
    leaf with no SEH, so it virtualises cleanly. }
  VMBeginVirtualization('cte');
  D := Length(A) xor Length(B);
  for I := 0 to Min(Length(A), Length(B)) - 1 do
    D := D or (Integer(A[I]) xor Integer(B[I]));
  Result := D = 0;
  VMEnd;
end;

{ =============================================================================
  Hashing / HMAC
  ============================================================================= }

function Sha256Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA256);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

function Sha512Of(const AData: TBytes): TBytes;
var
  H: THashSHA2;
begin
  H := THashSHA2.Create(THashSHA2.TSHA2Version.SHA512);
  H.Update(AData);
  Result := H.HashAsBytes;
end;

{ HMAC-SHA512 (RFC 2104) via System.Hash.GetHMACAsBytes (TBytes overload). }
function HMACSHA512(const AKey, AMessage: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AMessage, AKey, THashSHA2.TSHA2Version.SHA512);
end;

{ HMAC-SHA256 (RFC 2104), same helper family. Basis for the v2 container
  KDF (HKDF + PBKDF2); the v1 Argon2id path was removed entirely. }
function HMACSHA256(const AKey, AMessage: TBytes): TBytes;
begin
  Result := THashSHA2.GetHMACAsBytes(AMessage, AKey, THashSHA2.TSHA2Version.SHA256);
end;

{ HKDF-Extract (RFC 5869 section 2.2): PRK = HMAC-SHA256(salt, IKM).
  Empty salt becomes 32 zero bytes, exactly as the RFC mandates. }
function HkdfExtractSHA256(const ASalt, AIKM: TBytes): TBytes;
var
  ZeroSalt: TBytes;
begin
  if Length(ASalt) = 0 then
  begin
    SetLength(ZeroSalt, 32);
    FillChar(ZeroSalt[0], 32, 0);
    Result := HMACSHA256(ZeroSalt, AIKM);
    FillChar(ZeroSalt[0], 32, 0);
  end
  else
    Result := HMACSHA256(ASalt, AIKM);
end;

{ HKDF-Expand (RFC 5869 section 2.3): OKM = first ALen bytes of
  T(1) | T(2) | ... with T(n) = HMAC-SHA256(PRK, T(n-1) | info | n). }
function HkdfExpandSHA256(const APRK, AInfo: TBytes; ALen: Integer): TBytes;
var
  T, Block: TBytes;
  N, Pos, Take: Integer;
begin
  SetLength(Result, ALen);
  SetLength(T, 0);
  N := 1;
  Pos := 0;
  while Pos < ALen do
  begin
    if N > 255 then
      Break; // RFC 5869: L must be <= 255 * HashLen; never hit (L = 32)
    SetLength(Block, Length(T) + Length(AInfo) + 1);
    if Length(T) > 0 then
      Move(T[0], Block[0], Length(T));
    if Length(AInfo) > 0 then
      Move(AInfo[0], Block[Length(T)], Length(AInfo));
    Block[Length(Block) - 1] := Byte(N);
    T := HMACSHA256(APRK, Block);
    if Length(Block) > 0 then
      FillChar(Block[0], Length(Block), 0);
    Take := ALen - Pos;
    if Take > Length(T) then
      Take := Length(T);
    Move(T[0], Result[Pos], Take);
    Inc(Pos, Take);
    Inc(N);
  end;
  if Length(T) > 0 then
    FillChar(T[0], Length(T), 0);
end;

{ PBKDF2-HMAC-SHA256 (RFC 2898 section 5.2) with AIterations rounds. }
function Pbkdf2HMACSHA256(const APassword, ASalt: TBytes;
  AIterations, ADkLen: Integer): TBytes;
var
  U, Acc, SaltBlock: TBytes;
  BlockNo, I, J, Pos, Take: Integer;
begin
  SetLength(Result, ADkLen);
  if ADkLen > 0 then
    FillChar(Result[0], ADkLen, 0);
  BlockNo := 1;
  Pos := 0;
  while Pos < ADkLen do
  begin
    SetLength(SaltBlock, Length(ASalt) + 4);
    if Length(ASalt) > 0 then
      Move(ASalt[0], SaltBlock[0], Length(ASalt));
    SaltBlock[Length(SaltBlock) - 4] := Byte((Cardinal(BlockNo) shr 24) and $FF);
    SaltBlock[Length(SaltBlock) - 3] := Byte((Cardinal(BlockNo) shr 16) and $FF);
    SaltBlock[Length(SaltBlock) - 2] := Byte((Cardinal(BlockNo) shr 8) and $FF);
    SaltBlock[Length(SaltBlock) - 1] := Byte(Cardinal(BlockNo) and $FF);
    U := HMACSHA256(APassword, SaltBlock);
    if Length(SaltBlock) > 0 then
      FillChar(SaltBlock[0], Length(SaltBlock), 0);
    Acc := Copy(U, 0, Length(U));
    for I := 2 to AIterations do
    begin
      U := HMACSHA256(APassword, U);
      for J := 0 to Length(Acc) - 1 do
        Acc[J] := Acc[J] xor U[J];
    end;
    Take := ADkLen - Pos;
    if Take > Length(Acc) then
      Take := Length(Acc);
    Move(Acc[0], Result[Pos], Take);
    Inc(Pos, Take);
    Inc(BlockNo);
    if Length(U) > 0 then
      FillChar(U[0], Length(U), 0);
    if Length(Acc) > 0 then
      FillChar(Acc[0], Length(Acc), 0);
  end;
end;

{ v2 master-key schedule, default-key containers (flag $10):
  HKDF-SHA256 over the embedded app secret + per-file salt. Microseconds. }
function ShieldKdfDefaultKey(const ASecret, ASalt: TBytes): TBytes;
begin
  VMBeginVirtualization('kdfd');
  Result := HkdfExpandSHA256(
    HkdfExtractSHA256(ASalt, ASecret),
    TEncoding.UTF8.GetBytes(SHIELD_HKDF_INFO_DEFAULT),
    SHIELD_MASTER_LEN);
  VMEnd;
end;

{ v2 master-key schedule, password containers: PBKDF2-HMAC-SHA256 at
  SHIELD_PBKDF2_ITERATIONS rounds (~100 ms per unlock on a typical PC;
  unlocks happen at most once per session, so there is no UI impact).
  Deliberately NOT Argon2 (removed project-wide by owner decision). }
function ShieldKdfPasswordKey(const APassword, ASalt: TBytes): TBytes;
begin
  VMBeginVirtualization('kdfp');
  Result := Pbkdf2HMACSHA256(APassword, ASalt,
    SHIELD_PBKDF2_ITERATIONS, SHIELD_MASTER_LEN);
  VMEnd;
end;

{ =============================================================================
  Machine identity (D11): SHA-256(Windows MachineGuid UTF-8)[:16]
  ============================================================================= }

function ReadMachineGuid: string;
var
  RegKey: HKEY;
  Buf: array [0 .. 127] of WideChar;
  BufSize: DWORD;
begin
  Result := '';
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE,
    'SOFTWARE\Microsoft\Cryptography', 0, KEY_READ or KEY_WOW64_64KEY,
    RegKey) = ERROR_SUCCESS then
  try
    BufSize := SizeOf(Buf);
    if RegQueryValueExW(RegKey, 'MachineGuid', nil, nil, @Buf[0],
      @BufSize) = ERROR_SUCCESS then
      Result := Buf;
  finally
    RegCloseKey(RegKey);
  end;
end;

{ Fallback matching uuid.getnode(): primary MAC rendered as a decimal string
  (Python uses str(uuid.getnode())). Only used when MachineGuid is missing. }
function GetPrimaryMacString: string;
var
  BufSize: DWORD;
  Adapters, P: PIP_ADAPTER_INFO;
  Value: UInt64;
  I: Integer;
begin
  Result := '';
  BufSize := 0;
  Adapters := nil;
  if GetAdaptersInfo(nil, BufSize) = ERROR_BUFFER_OVERFLOW then
  begin
    GetMem(Adapters, BufSize);
    try
      if GetAdaptersInfo(Adapters, BufSize) = NO_ERROR then
      begin
        P := Adapters;
        while Assigned(P) do
        begin
          if P^.Type_ = 6 then   // MIB_IF_TYPE_ETHERNET
          begin
            Value := 0;
            for I := 0 to 5 do
              Value := (Value shl 8) or P^.Address[I];
            Result := IntToStr(Value);
            Break;
          end;
          P := P^.Next;
        end;
      end;
    finally
      FreeMem(Adapters);
    end;
  end;
end;

function AvroShieldMachineId: TBytes;
var
  Guid: string;
begin
  Guid := ReadMachineGuid;
  if Guid = '' then
    Guid := GetPrimaryMacString;
  Result := Sha256Of(TEncoding.UTF8.GetBytes(Guid));
  SetLength(Result, 16);
end;

{ =============================================================================
  Bytecode parser (inverse of avroenco/bytecode.py)
  ============================================================================= }

{ Deterministic XOR mask over string payloads: keystream = SHA-256(
  'AvroShieldBytecodeXORv1' + BE32(len)) repeated. }
function BcMaskString(const AData: TBytes): TBytes;
var
  LenB, Key: TBytes;
  I: Integer;
begin
  SetLength(LenB, 4);
  LenB[0] := Byte(Length(AData) shr 24);
  LenB[1] := Byte(Length(AData) shr 16);
  LenB[2] := Byte(Length(AData) shr 8);
  LenB[3] := Byte(Length(AData));
  Key := Sha256Of(TEncoding.UTF8.GetBytes(BC_XOR_SEED) + LenB);
  SetLength(Result, Length(AData));
  for I := 0 to Length(AData) - 1 do
    Result[I] := AData[I] xor Key[I mod 32];
end;

function BcReadInt64(const AData: TBytes; AOff: Integer): Int64;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Result := Int64(Bits);
end;

function BcReadDouble(const AData: TBytes; AOff: Integer): Double;
var
  Bits: UInt64;
  I: Integer;
begin
  Bits := 0;
  for I := 0 to 7 do
    Bits := (Bits shl 8) or AData[AOff + I];
  Move(Bits, Result, SizeOf(Result));
end;

function ParseNode(const AData: TBytes; var AOff: Integer): TAvroNode;
var
  Typ: Byte;
  Len, Cnt, I, KLen: Integer;
  Masked: TBytes;
begin
  if AOff >= Length(AData) then
    raise ShieldOpaqueError('Truncated node');
  Typ := AData[AOff];
  Inc(AOff);

  Result := TAvroNode.Create;
  try
    case Typ of
      TYPE_NULL:
        Result.Kind := nkNull;

      TYPE_BOOLEAN:
        begin
          if AOff >= Length(AData) then
            raise ShieldOpaqueError('Truncated boolean');
          Result.Kind := nkBool;
          Result.BoolVal := AData[AOff] = $01;
          Inc(AOff);
        end;

      TYPE_NUMBER:
        begin
          if AOff + 9 > Length(AData) then
            raise ShieldOpaqueError('Truncated number');
          if AData[AOff] = 1 then
          begin
            Result.Kind := nkInt;
            Result.IntVal := BcReadInt64(AData, AOff + 1);
          end
          else
          begin
            Result.Kind := nkFloat;
            Result.FloatVal := BcReadDouble(AData, AOff + 1);
          end;
          Inc(AOff, 9);
        end;

      TYPE_STRING:
        begin
          if AOff + 4 > Length(AData) then
            raise ShieldOpaqueError('Truncated string');
          Len := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          Masked := BcRead(AData, AOff, Len);
          Result.Kind := nkString;
          Result.StrVal := TEncoding.UTF8.GetString(BcMaskString(Masked));
        end;

      TYPE_ARRAY:
        begin
          if AOff + 4 > Length(AData) then
            raise ShieldOpaqueError('Truncated array');
          Result.Kind := nkArray;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
            Result.Items.Add(ParseNode(AData, AOff));
        end;

      TYPE_OBJECT:
        begin
          if AOff + 4 > Length(AData) then
            raise ShieldOpaqueError('Truncated object');
          Result.Kind := nkObject;
          Cnt := Integer(BE32(AData, AOff));
          Inc(AOff, 4);
          for I := 0 to Cnt - 1 do
          begin
            if AOff + 2 > Length(AData) then
              raise ShieldOpaqueError('Truncated object key');
            KLen := Integer(BE16(AData, AOff));
            Inc(AOff, 2);
            Result.Keys.Add(TEncoding.UTF8.GetString(BcRead(AData, AOff, KLen)));
            Result.Items.Add(ParseNode(AData, AOff));
          end;
        end;

    else
      raise ShieldOpaqueError(Format('Unsupported bytecode node type: %d', [Typ]));
    end;
  except
    Result.Free;
    raise;
  end;
end;

function AvroShieldParseBytecode(const ABytecode: TBytes; out AValue: TAvroNode): Boolean;
var
  Off, I, TypeCount, EntryCount, KLen, NodeLen, EntryStart, NZero: Integer;
  KeyBytes, NodeBytes, Entry, Calc, BC_MAGIC: TBytes;
  Root: TAvroNode;
  StoredCrc: Cardinal;
begin
  AValue := nil;
  Root := nil;
  Result := False;
  try
    if Length(ABytecode) < BC_HEADER_SIZE + 32 then
      Exit;

    BC_MAGIC := TEncoding.ASCII.GetBytes('AVROBC');
    if not BytesEqualAt(ABytecode, 0, BC_MAGIC) then
      Exit;
    if ABytecode[6] <> 1 then
      Exit;

    // SHA-256 trailer over everything before the last 32 bytes.
    Calc := Sha256Of(Copy(ABytecode, 0, Length(ABytecode) - 32));
    if not ConstTimeEqual(Calc, Copy(ABytecode, Length(ABytecode) - 32, 32)) then
      Exit;

    TypeCount := Integer(BE32(ABytecode, 7));
    EntryCount := Integer(BE32(ABytecode, 11));

    Off := BC_HEADER_SIZE;
    for I := 0 to TypeCount - 1 do
    begin
      Inc(Off, 1);
      if Off + 2 > Length(ABytecode) then
        Exit;
      Inc(Off, 2 + Integer(BE16(ABytecode, Off)));
    end;

    Root := TAvroNode.Create;
    Root.Kind := nkObject;
    for I := 0 to EntryCount - 1 do
    begin
      EntryStart := Off;
      if Off + 2 > Length(ABytecode) then
        raise ShieldOpaqueError('Truncated entry key');
      KLen := Integer(BE16(ABytecode, Off));
      Inc(Off, 2);
      KeyBytes := BcRead(ABytecode, Off, KLen);
      if Off + 4 > Length(ABytecode) then
        raise ShieldOpaqueError('Truncated entry node');
      NodeLen := Integer(BE32(ABytecode, Off));
      Inc(Off, 4);
      NodeBytes := BcRead(ABytecode, Off, NodeLen);
      if Off + 4 > Length(ABytecode) then
        raise ShieldOpaqueError('Truncated entry crc');
      StoredCrc := BE32(ABytecode, Off);
      Inc(Off, 4);

      Entry := Copy(ABytecode, EntryStart, Off - 4 - EntryStart);
      if crc32(0, @Entry[0], Length(Entry)) <> StoredCrc then
        raise ShieldOpaqueError('Entry checksum mismatch');

      NZero := 0;
      Root.Keys.Add(TEncoding.UTF8.GetString(KeyBytes));
      Root.Items.Add(ParseNode(NodeBytes, NZero));
    end;

    if Off <> Length(ABytecode) - 32 then
      raise ShieldOpaqueError('Trailing garbage after entries');

    AValue := Root;
    Root := nil;
    Result := True;
    except
    on E: Exception do
      ; // Result stays False
  end;
  Root.Free;
end;

{ =============================================================================
  Deobfuscator (inverse of avroenco/obfuscator.py)
  ============================================================================= }

{ SHA-256 counter-mode keystream: blocks of SHA-256(key + BE32(counter)). }
function DeobfStream(const AKey: TBytes; ALength: Integer): TBytes;
var
  OutB, CounterB, Block: TBytes;
  Counter, I, Take: Integer;
begin
  SetLength(OutB, ALength);
  Counter := 0;
  I := 0;
  while I < ALength do
  begin
    SetLength(CounterB, 4);
    CounterB[0] := Byte(Counter shr 24);
    CounterB[1] := Byte(Counter shr 16);
    CounterB[2] := Byte(Counter shr 8);
    CounterB[3] := Byte(Counter);
    Block := Sha256Of(AKey + CounterB);
    Take := Min(32, ALength - I);
    Move(Block[0], OutB[I], Take);
    Inc(I, 32);
    Inc(Counter);
  end;
  Result := OutB;
end;

{ XOR codec over (seed, ctx): keystream key = SHA-256('str\0' + seed + '\0' +
  UTF-8(ctx)); XOR is its own inverse. }
function DeobfCodec(const ASeed, AData: TBytes; const ACtx: string): TBytes;
var
  Key, Stream: TBytes;
  I: Integer;
begin
  Key := Sha256Of(StrTag + ASeed + TEncoding.UTF8.GetBytes(#0 + ACtx));
  Stream := DeobfStream(Key, Length(AData));
  SetLength(Result, Length(AData));
  for I := 0 to Length(AData) - 1 do
    Result[I] := AData[I] xor Stream[I];
end;

function ChildCtx(const ACtx, AName: string): string;
begin
  if ACtx = '' then
    Result := AName
  else
    Result := ACtx + '/' + AName;
end;

function IndexCtx(const ACtx: string; AIndex: Integer): string;
begin
  Result := ACtx + '#' + IntToStr(AIndex);
end;

{ =============================================================================
  Obfuscation key domains (format v3)
  ============================================================================= }

{ Generic HKDF-SHA256 (RFC 5869) over arbitrary info. The KDF helpers above are
  bound to the container key schedule; this is the one the obfuscation domains
  use, with an explicit info label so two derivations can never collide. }
function HkdfSha256(const AIKM, ASalt, AInfo: TBytes; ALen: Integer): TBytes;
var
  PRK: TBytes;
begin
  PRK := HkdfExtractSHA256(ASalt, AIKM);
  try
    Result := HkdfExpandSHA256(PRK, AInfo, ALen);
  finally
    AvroWipeAndRelease(PRK);
  end;
end;

{ True when AName is one of the developer-documentation fields. Matched as an
  exact name: 'Comment' and 'comment' are distinct keys in the mapping schema
  and both are documentation, but a value field that merely contains the word
  must not be swept into the comment domain. }
function AvroShieldIsCommentField(const AName: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := Low(OBF_COMMENT_FIELDS) to High(OBF_COMMENT_FIELDS) do
    if AName = OBF_COMMENT_FIELDS[I] then
      Exit(True);
end;

{ Context of a comment field: the ordinary child path under a distinct prefix.
  The prefix matters even though the comment domain already uses a different
  key - it keeps the two keystream namespaces disjoint by construction, so no
  pair of (key, ctx) inputs can ever coincide across domains. }
function AvroShieldCommentCtx(const ACtx, AName: string): string;
begin
  Result := 'cmt/' + ChildCtx(ACtx, AName);
end;

{ Metadata mask for a container the caller has already opened:

    KeyMeta = HKDF-SHA256(IKM = master, info = OBF_INFO_META)

  Master is already a per-container salted secret, so the mask needs no second
  salt. Before this existed the mask was a constant compiled into the unit, so
  anyone could unmask the metadata - and therefore the value seed and the whole
  obfuscation - without any key at all. }
function AvroShieldMetaMask(const AMaster: TBytes): TBytes;
var
  InfoMeta: TBytes;
begin
  Result := nil;
  if Length(AMaster) = 0 then
    Exit;
  InfoMeta := TEncoding.ASCII.GetBytes(OBF_INFO_META);
  try
    Result := HkdfSha256(AMaster, nil, InfoMeta, 32);
  finally
    AvroWipeAndRelease(InfoMeta);
  end;
end;

{ Comment domain key:

    KeyComments = HKDF-SHA256(IKM = comment IKM, salt = value seed,
                              info = OBF_INFO_COMMENTS)

  The developer IKM is what the runtime never has, and the value seed is only
  reachable through the keyed metadata blob, so comment text needs both the
  container key and the developer key. Salting with the per-build seed also
  keeps a comment token from being replayed into another container that used
  the same comment key. }
function AvroShieldCommentKey(const ACommentsIKM, ASeed: TBytes): TBytes;
var
  InfoCmt: TBytes;
begin
  Result := nil;
  if (Length(ACommentsIKM) = 0) or (Length(ASeed) = 0) then
    Exit;
  InfoCmt := TEncoding.ASCII.GetBytes(OBF_INFO_COMMENTS);
  try
    Result := HkdfSha256(ACommentsIKM, ASeed, InfoCmt, 32);
  finally
    AvroWipeAndRelease(InfoCmt);
  end;
end;

{ Recursive deobfuscator.

  AEffSeed is the obfuscation key in force for this subtree: the value seed by
  default, the comment key inside a comment field. ACommentSeed is the comment
  domain key; empty means the domain falls back to the value seed, which is
  what a container built without a comment key used (mirror of the writer).

  ACommentDomain distinguishes the two container formats. Format v3 gives
  comment fields their own context path and key; format v2 had no comment
  domain at all, so its comment fields are ordinary strings and must be decoded
  with the plain child context and the value seed - decoding them at the v3
  comment context produces garbage and, because that garbage is invalid UTF-8,
  used to fail the whole load of every existing v2 container.

  AIncludeComments=False is the runtime behaviour and the reason comments cost
  nothing to load: a comment field is skipped here, before the Base64 decode,
  before the keystream and before the UTF-16 allocation, instead of being
  decoded and then thrown away by the mapping parser. }
function DeobfValue(ANode: TAvroNode; const ACtx: string;
  const AEffSeed, ACommentSeed: TBytes; AIncludeComments, ACommentDomain: Boolean;
  const ARev: TDictionary<string, string>;
  const ASkip: TDictionary<string, Boolean>): TAvroNode;
var
  I: Integer;
  OrigKey, HashedKey: string;
  Child: TAvroNode;
  ChildSeed, EffCmtSeed: TBytes;
  ChildCtxPath: string;
  IsComment: Boolean;
begin
  EffCmtSeed := ACommentSeed;
  if Length(EffCmtSeed) = 0 then
    EffCmtSeed := AEffSeed;

  Result := TAvroNode.Create;
  case ANode.Kind of
    nkObject:
      begin
        Result.Kind := nkObject;
        for I := 0 to ANode.Items.Count - 1 do
        begin
          HashedKey := ANode.Keys[I];
          if ASkip.ContainsKey(HashedKey) then
            Continue;
          if not ARev.TryGetValue(HashedKey, OrigKey) then
            OrigKey := HashedKey;
          IsComment := AvroShieldIsCommentField(OrigKey);
          if IsComment and (not AIncludeComments) then
            Continue;
          if IsComment and ACommentDomain then
          begin
            ChildSeed := EffCmtSeed;
            ChildCtxPath := AvroShieldCommentCtx(ACtx, HashedKey);
          end
          else
          begin
            // Value fields, and every comment field in a v2 container, which
            // has no separate comment domain.
            ChildSeed := AEffSeed;
            ChildCtxPath := ChildCtx(ACtx, HashedKey);
          end;
          Child := DeobfValue(ANode.Items[I], ChildCtxPath, ChildSeed,
            EffCmtSeed, AIncludeComments, ACommentDomain, ARev, ASkip);
          Result.Keys.Add(OrigKey);
          Result.Items.Add(Child);
        end;
      end;
    nkArray:
      begin
        Result.Kind := nkArray;
        for I := 0 to ANode.Items.Count - 1 do
          Result.Items.Add(DeobfValue(ANode.Items[I], IndexCtx(ACtx, I),
            AEffSeed, EffCmtSeed, AIncludeComments, ACommentDomain, ARev,
            ASkip));
      end;
    nkString:
      begin
        Result.Kind := nkString;
        Result.StrVal := TEncoding.UTF8.GetString(DeobfCodec(AEffSeed,
          TNetEncoding.Base64.DecodeStringToBytes(ANode.StrVal), ACtx));
      end;
  else
    Result.Kind := ANode.Kind;
    Result.BoolVal := ANode.BoolVal;
    Result.IntVal := ANode.IntVal;
    Result.FloatVal := ANode.FloatVal;
  end;
end;

{ The shared deobfuscation core: unmasks the metadata blob with AKeyMeta, then
  walks the tree with AKeyComments as the comment-domain key.

  AKeyMeta=nil selects the format-v2 constant mask (MetaSeed), which is what a
  v2 container carries; v3 passes its derived key. An empty ACommentsIKM means
  the comment domain is not separable from the value domain (v2), so comments
  are decoded with the value seed exactly as before. }
function DeobfuscateCore(const AObfuscated: TAvroNode;
  const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean;
  out AValue: TAvroNode): Boolean;
var
  Seed, CommentKey: TBytes;
  MetaMask: TBytes;
  Rev: TDictionary<string, string>;
  Skip: TDictionary<string, Boolean>;
  MetaIdx, I: Integer;
  MetaVal: TAvroNode;
  Json: TJSONValue;
  JObj, KMap: TJSONObject;
  JArr: TJSONArray;
  Pair: TJSONPair;
begin
  AValue := nil;
  Result := False;
  try
    Rev := TDictionary<string, string>.Create;
    Skip := TDictionary<string, Boolean>.Create;
    try
      Skip.Add(META_KEY, True);

      MetaIdx := AObfuscated.Keys.IndexOf(META_KEY);
      if MetaIdx < 0 then
        Exit; // no metadata -> cannot deobfuscate
      MetaVal := AObfuscated.Items[MetaIdx];
      if MetaVal.Kind <> nkString then
        Exit;

      if Length(AKeyMeta) > 0 then
        MetaMask := AKeyMeta
      else
        MetaMask := MetaSeed;

      Json := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(DeobfCodec(
        MetaMask, TNetEncoding.Base64.DecodeStringToBytes(MetaVal.StrVal),
        META_KEY)));
      if not (Json is TJSONObject) then
        Exit;
      try
        JObj := TJSONObject(Json);
        Seed := TNetEncoding.Base64.DecodeStringToBytes(JObj.GetValue('seed').Value);
        KMap := JObj.GetValue('key_map') as TJSONObject;
        if Assigned(KMap) then
          for Pair in KMap do
            Rev.Add(Pair.JsonValue.Value, Pair.JsonString.Value); // hashed -> original
        JArr := JObj.GetValue('dummies') as TJSONArray;
        if Assigned(JArr) then
          for I := 0 to JArr.Count - 1 do
            Skip.Add(JArr.Items[I].Value, True);
      finally
        Json.Free;
      end;

      // The comment key is derived only now, after the metadata blob has been
      // unmasked: the comment domain is layered on top of the container key
      // rather than sitting beside it.
      CommentKey := AvroShieldCommentKey(ACommentsIKM, Seed);
      // A keyed metadata mask is exactly the marker of format v3, and format
      // v3 is the only format with a separate comment domain. The legacy entry
      // point passes no mask, which keeps its v2 semantics.
      AValue := DeobfValue(AObfuscated, '', Seed, CommentKey,
        AIncludeComments, Length(AKeyMeta) > 0, Rev, Skip);
      Result := True;
    finally
      AvroWipeAndRelease(CommentKey);
      AvroWipeAndRelease(Seed);
      Rev.Free;
      Skip.Free;
    end;
  except
    on E: Exception do
      Result := False;
  end;
end;

function AvroShieldDeobfuscate(const AObfuscated: TAvroNode; out AValue: TAvroNode): Boolean;
begin
  // Format v2: constant metadata mask, comments in the value domain, and the
  // caller decides what to do with them (this entry point always keeps them).
  Result := DeobfuscateCore(AObfuscated, nil, nil, True, AValue);
end;

function AvroShieldDeobfuscateEx(const AObfuscated: TAvroNode;
  const AKeyMeta, ACommentsIKM: TBytes; AIncludeComments: Boolean;
  out AValue: TAvroNode): Boolean;
begin
  Result := DeobfuscateCore(AObfuscated, AKeyMeta, ACommentsIKM,
    AIncludeComments, AValue);
end;

{ =============================================================================
  JSON serialization (loader / tests)
  ============================================================================= }

function JsonEscape(const S: string): string;
var
  I: Integer;
  C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
    end;
  end;
end;

function AvroShieldNodeToJSON(const ANode: TAvroNode): string;
var
  I: Integer;
begin
  case ANode.Kind of
    nkNull: Result := 'null';
    nkBool:
      if ANode.BoolVal then Result := 'true' else Result := 'false';
    nkInt: Result := IntToStr(ANode.IntVal);
    nkFloat: Result := FloatToStr(ANode.FloatVal, TFormatSettings.Invariant);
    nkString: Result := '"' + JsonEscape(ANode.StrVal) + '"';
    nkArray:
      begin
        Result := '[';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + AvroShieldNodeToJSON(ANode.Items[I]);
        end;
        Result := Result + ']';
      end;
    nkObject:
      begin
        Result := '{';
        for I := 0 to ANode.Items.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + '"' + JsonEscape(ANode.Keys[I]) + '":' +
            AvroShieldNodeToJSON(ANode.Items[I]);
        end;
        Result := Result + '}';
      end;
  end;
end;

{ =============================================================================
  zlib decompression (Python zlib.compress output)
  ============================================================================= }

function ZlibDecompressBytes(const AData: TBytes): TBytes;
var
  InS, OutS: TMemoryStream;
  Z: TZDecompressionStream;
  Buf: array [0 .. 8191] of Byte;
  N: Integer;
begin
  Result := nil;
  InS := TMemoryStream.Create;
  OutS := TMemoryStream.Create;
  Z := nil;
  try
    try
      if Length(AData) > 0 then
        InS.Write(AData[0], Length(AData));
      InS.Position := 0;
      Z := TZDecompressionStream.Create(InS, 15);
      repeat
        N := Z.Read(Buf, SizeOf(Buf));
        if N > 0 then
          OutS.Write(Buf, N);
      until N < SizeOf(Buf);
      SetLength(Result, OutS.Size);
      if OutS.Size > 0 then
      begin
        OutS.Position := 0;
        OutS.Read(Result[0], OutS.Size);
      end;
    except
      on E: Exception do
        SetLength(Result, 0);
    end;
  finally
    Z.Free;
    OutS.Free;
    InS.Free;
  end;
end;

{ =============================================================================
  Container reader
  ============================================================================= }

{ Crypto stage of the loader: header validation, HMAC-SHA512 verification,
  AES-256-GCM decryption and zlib, leaving the decrypted but still OBFUSCATED
  bytecode. Deobfuscation is deliberately not done here, so the static-leak
  gate can inspect exactly the payload an attacker sees after extracting the
  container key.

  AMaster and ASalt come back because the obfuscation keys are derived from
  them; the caller owns and must wipe all three outs. Every other intermediate
  - derived keys, the GCM tag, the HMAC input, the compressed blob - is wiped
  here, so the container crypto stage exists in exactly one place. }
function ShieldOpenContainer(const AData: TBytes; const APassword: string;
  const ADefaultSecretIKM: TBytes; AUseMachineBind: Boolean;
  out ABytecode, AMaster, ASalt: TBytes): TAvroShieldResult;
var
  Flags: Byte;
  Salt, IV, StoredMachine, Master: TBytes;
  MachineF, HardwareF, FinalKey, EncKey, MacKey: TBytes;
  DefaultIKM, PasswordIKM: TBytes;
  Cipher, Tag, ExpectedMac, HmacData, Compressed, Bytecode: TBytes;
  MacOk, CryptoOk: Boolean;
begin
  ABytecode := nil;
  AMaster := nil;
  ASalt := nil;
  Result := asrUnknown;

  if Length(AData) < AS_HEADER_SIZE + AS_TRAILER_SIZE + 1 then
    Exit(asrFileTooShort);
  if not BytesEqualAt(AData, 0, AsMagic) then
    Exit(asrBadMagic);
  if not AvroShieldSupportedVersion(AData[8]) then
    Exit(asrBadVersion);

  Flags := AData[9];
  Salt := Copy(AData, 10, 16);
  IV := Copy(AData, 26, 16);
  StoredMachine := Copy(AData, 42, 16);

  if (Flags and FLAG_MACHINE_BIND) <> 0 then
  begin
    if not AUseMachineBind then
      Exit(asrMachineBindRequired);
    if not ConstTimeEqual(StoredMachine, AvroShieldMachineId) then
      Exit(asrMachineMismatch);
  end;

  try
    // Default-key containers (flag AVROSHLD_FLAG_DEFAULT_KEY) unlock with the
    // built-in application secret instead of a user password - the caller
    // passes '' and the substitution happens here, so no caller ever needs to
    // know the secret.
    //
    // GetAvroEncoSecretIKM (raw bytes) rather than GetAvroEncoDefaultSecret
    // (string): bytes are what HKDF-SHA256 consumes anyway, so taking the byte
    // form avoids materialising a UTF-16 copy of the secret on the heap for
    // the lifetime of the unlock. The password path converts the caller's
    // password once and wipes that buffer immediately after derivation.
    //
    // v2 schedule (no Argon2 anywhere): instant HKDF for embedded-secret
    // containers, PBKDF2 for password containers.
    if (Flags and AVROSHLD_FLAG_DEFAULT_KEY) <> 0 then
    begin
      // An offline tool (AvroEncoBuilder --unpack) passes the key file in;
      // the runtime passes nothing and gets the embedded secret.
      if Length(ADefaultSecretIKM) > 0 then
        DefaultIKM := Copy(ADefaultSecretIKM, 0, Length(ADefaultSecretIKM))
      else
        DefaultIKM := GetAvroEncoSecretIKM;
      Master := ShieldKdfDefaultKey(DefaultIKM, Salt);
    end
    else
    begin
      PasswordIKM := TEncoding.UTF8.GetBytes(APassword);
      Master := ShieldKdfPasswordKey(PasswordIKM, Salt);
      AvroWipeAndRelease(PasswordIKM);
    end;
    SetLength(MachineF, 16);
    FillChar(MachineF[0], 16, 0);
    if (Flags and FLAG_MACHINE_BIND) <> 0 then
      MachineF := AvroShieldMachineId;
    SetLength(HardwareF, 16);
    FillChar(HardwareF[0], 16, 0);
    if (Flags and FLAG_HARDWARE) <> 0 then
      HardwareF := AvroShieldMachineId; // Python falls back to machine id

    FinalKey := Sha512Of(Master + MachineF + HardwareF);
    EncKey := Copy(FinalKey, 0, 32);
    MacKey := Copy(FinalKey, 32, 32);

    Cipher := Copy(AData, AS_HEADER_SIZE,
      Length(AData) - AS_HEADER_SIZE - AS_TRAILER_SIZE);
    Tag := Copy(AData, Length(AData) - AS_TRAILER_SIZE, 16);
    ExpectedMac := Copy(AData, Length(AData) - AS_HMAC_SIZE, AS_HMAC_SIZE);

    HmacData := Copy(AData, 0, AS_HEADER_SIZE) + Cipher + Tag;

    // Two independent authenticators, both evaluated on every load:
    //   * the outer HMAC-SHA512 binds the 58-byte header, the ciphertext and
    //     the GCM tag under MacKey;
    //   * the AES-GCM tag binds the ciphertext under EncKey.
    // A fault that suppresses the HMAC verdict therefore does not by itself
    // make the GCM tag validate - the redundancy here is cryptographic rather
    // than a repeated branch on the same value.
    MacOk := ConstTimeEqual(HMACSHA512(MacKey, HmacData), ExpectedMac);
    CryptoOk := AES256GCMDecrypt(Cipher + Tag, EncKey, IV, nil, Compressed);

    // The GCM pass runs unconditionally, including when the HMAC already
    // failed. That costs one AES pass on a wrong password and removes the
    // timing oracle that previously let an observer distinguish "wrong
    // password" from "authentic MAC over a damaged payload" by measuring how
    // far the loader got. (A *successful* load is still slower than a failed
    // one - that is inherent to doing the work, and an attacker who can
    // observe success already knows the load succeeded.)
    //
    // The combined verdict is judged through the fused gate, so the policy
    // does not hinge on one short-circuiting branch.
    if not AvroFuseOk(AvroFuse(MacOk and CryptoOk)) then
    begin
      if not MacOk then
        Exit(asrHmacFailed);
      Exit(asrDecryptFailed);
    end;

    Bytecode := ZlibDecompressBytes(Compressed);
    if Length(Bytecode) = 0 then
      Exit(asrDecompressFailed);

    if not BytesEqualAt(Bytecode, 0, TEncoding.ASCII.GetBytes('AVROBC')) then
      Exit(asrBadBytecode);

    // Ownership of the three caller-owned buffers moves out here; the locals
    // are cleared so the wipe list below does not destroy what the caller now
    // holds.
    ABytecode := Bytecode;
    Bytecode := nil;
    AMaster := Master;
    Master := nil;
    ASalt := Salt;
    Salt := nil;
    Result := asrOk;
  finally
    // Every intermediate that held key material or plaintext mapping data is
    // wiped here. The previous version wiped only Master, FinalKey and
    // Compressed, leaving EncKey, MacKey, the GCM tag, the HMAC input and the
    // decompressed bytecode readable in freed heap blocks - which is what a
    // heap-walk pass recovers first.
    AvroWipeAndRelease(PasswordIKM);
    AvroWipeAndRelease(DefaultIKM);
    AvroWipeAndRelease(Master);
    AvroWipeAndRelease(MachineF);
    AvroWipeAndRelease(HardwareF);
    AvroWipeAndRelease(FinalKey);
    AvroWipeAndRelease(EncKey);
    AvroWipeAndRelease(MacKey);
    AvroWipeAndRelease(Salt);
    AvroWipeAndRelease(IV);
    AvroWipeAndRelease(StoredMachine);
    AvroWipeAndRelease(Cipher);
    AvroWipeAndRelease(Tag);
    AvroWipeAndRelease(ExpectedMac);
    AvroWipeAndRelease(HmacData);
    AvroWipeAndRelease(Compressed);
    AvroWipeAndRelease(Bytecode);
  end;
end;

{ Tooling: the decrypted but still obfuscated bytecode of a container. }
function AvroShieldExtractObfuscatedBytecode(const AData: TBytes;
  const APassword: string; const ADefaultSecretIKM: TBytes;
  AUseMachineBind: Boolean; out ABytecode: TBytes): TAvroShieldResult;
var
  Master, Salt: TBytes;
begin
  ABytecode := nil;
  Result := ShieldOpenContainer(AData, APassword, ADefaultSecretIKM,
    AUseMachineBind, ABytecode, Master, Salt);
  AvroWipeAndRelease(Master);
  AvroWipeAndRelease(Salt);
  if Result <> asrOk then
    AvroWipeAndRelease(ABytecode);
end;

function AvroShieldDefaultLoadOptions: TAvroShieldLoadOptions;
begin
  Result.UseMachineBind := True;
  Result.IncludeComments := False;
  Result.DefaultSecretIKM := nil;
  Result.CommentsIKM := nil;
end;

function AvroShieldSupportedVersion(AVer: Byte): Boolean;
begin
  Result := (AVer = AS_VERSION) or (AVer = AS_VERSION_LEGACY);
end;

function AvroShieldCurrentVersion: Byte;
begin
  Result := AS_VERSION;
end;

{ Core loader. Delivers the deobfuscated mapping as UTF-8 bytes rather than a
  Delphi string: a string is reference-counted and may be shared with other
  holders, so the caller cannot reliably wipe the last copy. The byte buffer
  that leaves this function belongs to the caller, which must wipe it with
  AvroWipeAndRelease once the mapping has been parsed into runtime tables.

  Stage 1 unwraps the container; stage 2 parses the bytecode and deobfuscates
  it with the metadata mask derived from the container master key and the
  comment key derived from the caller's comment IKM. Every intermediate - the
  derived keys, the bytecode, the interim UTF-16 JSON - is wiped before
  return. }
function AvroShieldLoadFromBytesUtf8Ex(const AData: TBytes; const APassword: string;
  const AOptions: TAvroShieldLoadOptions; out AJsonUtf8: TBytes): TAvroShieldResult;
var
  Bytecode, Master, Salt, KeyMeta, KeyComments: TBytes;
  Root, Deobf: TAvroNode;
  JsonText: string;
begin
  AJsonUtf8 := nil;
  Root := nil;
  Deobf := nil;
  Result := ShieldOpenContainer(AData, APassword, AOptions.DefaultSecretIKM,
    AOptions.UseMachineBind, Bytecode, Master, Salt);
  if Result <> asrOk then
    Exit;
  try
    // Format v2 keeps the legacy constant metadata mask and has no separate
    // comment domain; format v3 derives the mask from the container key and
    // levels the comment domain on top of it.
    if AData[8] = AS_VERSION then
      KeyMeta := AvroShieldMetaMask(Master)
    else
      KeyMeta := nil;
    try
      if not AvroShieldParseBytecode(Bytecode, Root) then
        Exit(asrBadBytecode);
      try
        if not AvroShieldDeobfuscateEx(Root, KeyMeta, AOptions.CommentsIKM,
          AOptions.IncludeComments, Deobf) then
          Exit(asrCorruptPayload);
        try
          JsonText := AvroShieldNodeToJSON(Deobf);
          try
            AJsonUtf8 := TEncoding.UTF8.GetBytes(JsonText);
            Result := asrOk;
          finally
            // The serializer necessarily builds a UTF-16 string first, so
            // wipe that interim copy here and leave only the caller-owned
            // UTF-8 buffer behind.
            AvroWipeString(JsonText);
          end;
        finally
          Deobf.Free;
          Deobf := nil;
        end;
      finally
        Root.Free;
        Root := nil;
      end;
    finally
      AvroWipeAndRelease(KeyMeta);
      AvroWipeAndRelease(KeyComments);
    end;
  finally
    AvroWipeAndRelease(Master);
    AvroWipeAndRelease(Salt);
    AvroWipeAndRelease(Bytecode);
  end;
end;

function AvroShieldLoadFromBytesUtf8(const AData: TBytes; const APassword: string;
  out AJsonUtf8: TBytes; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Options: TAvroShieldLoadOptions;
begin
  Options := AvroShieldDefaultLoadOptions;
  Options.UseMachineBind := AUseMachineBind;
  Result := AvroShieldLoadFromBytesUtf8Ex(AData, APassword, Options, AJsonUtf8);
end;

{ String-returning wrapper, kept so the builder, the KATs and support tooling
  do not all have to change. The string it returns cannot be reliably wiped by
  the caller (reference-counted, possibly shared), which is exactly why the
  runtime path uses AvroShieldLoadFromBytesUtf8 instead. }
function AvroShieldLoadFromBytes(const AData: TBytes; const APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Utf8: TBytes;
begin
  AJSONText := '';
  Result := AvroShieldLoadFromBytesUtf8(AData, APassword, Utf8, AUseMachineBind);
  if Result = asrOk then
  begin
    AJSONText := TEncoding.UTF8.GetString(Utf8);
    AvroWipeAndRelease(Utf8);
  end;
end;

{ Runtime entry point: one externally visible failure code. }
function AvroShieldLoadForRuntime(const AData: TBytes; const APassword: string;
  out AJsonUtf8: TBytes; AUseMachineBind: Boolean): TAvroShieldResult;
var
  Raw: TAvroShieldResult;
begin
  Raw := AvroShieldLoadFromBytesUtf8(AData, APassword, AJsonUtf8,
    AUseMachineBind);
  if AvroFuseOk(AvroFuse(Raw = asrOk)) then
    Result := asrOk
  else
  begin
    AvroWipeAndRelease(AJsonUtf8);
    Result := asrHmacFailed;
  end;
end;

function AvroShieldLoadFromFile(const AFileName, APassword: string;
  out AJSONText: string; AUseMachineBind: Boolean): TAvroShieldResult;
var
  FS: TFileStream;
  Data: TBytes;
begin
  AJSONText := '';
  if not FileExists(AFileName) then
    Exit(asrFileNotFound);
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Data, FS.Size);
    if FS.Size > 0 then
      FS.Read(Data[0], FS.Size);
  finally
    FS.Free;
  end;
  Result := AvroShieldLoadFromBytes(Data, APassword, AJSONText, AUseMachineBind);
end;

{ =============================================================================
  Container writer (inverse of the loader above)
  ============================================================================= }

function AvroShieldContainerUsesDefaultKey(const AFilePath: string): Boolean;
var
  FS:  TFileStream;
  Hdr: array [0 .. 9] of Byte;
begin
  Result := False;
  if not FileExists(AFilePath) then
    Exit;
  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
    try
      if FS.Size < 10 then
        Exit;
      FS.ReadBuffer(Hdr, 10);
      if not CompareMem(@Hdr[0], @AsMagic[0], 8) then
        Exit;
      if not AvroShieldSupportedVersion(Hdr[8]) then
        Exit;
      Result := (Hdr[9] and AVROSHLD_FLAG_DEFAULT_KEY) <> 0;
    finally
      FS.Free;
    end;
  except
    Result := False;
  end;
end;

{ ---- JSON -> node tree ---------------------------------------------------- }

function JsonValueToNode(const AJson: TJSONValue): TAvroNode;
var
  I:   Integer;
  Arr: TJSONArray;
  Obj: TJSONObject;
  Num: TJSONNumber;
begin
  Result := TAvroNode.Create;
  try
    if AJson is TJSONNull then
      Result.Kind := nkNull
    else if AJson is TJSONBool then
    begin
      Result.Kind := nkBool;
      Result.BoolVal := (AJson as TJSONBool).AsBoolean;
    end
    else if AJson is TJSONNumber then
    begin
      Num := AJson as TJSONNumber;
      // Integers stay integers (bytecode TYPE_NUMBER flag 1); anything else
      // becomes a double (flag 0). Mapping documents use small integers only.
      if TryStrToInt64(Num.Value, Result.IntVal) then
        Result.Kind := nkInt
      else
      begin
        Result.Kind := nkFloat;
        Result.FloatVal := StrToFloat(Num.Value, TFormatSettings.Invariant);
      end;
    end
    else if AJson is TJSONString then
    begin
      Result.Kind := nkString;
      Result.StrVal := (AJson as TJSONString).Value;
    end
    else if AJson is TJSONArray then
    begin
      Result.Kind := nkArray;
      Arr := AJson as TJSONArray;
      for I := 0 to Arr.Count - 1 do
        Result.Items.Add(JsonValueToNode(Arr.Items[I]));
    end
    else if AJson is TJSONObject then
    begin
      Result.Kind := nkObject;
      Obj := AJson as TJSONObject;
      for I := 0 to Obj.Count - 1 do
      begin
        Result.Keys.Add(Obj.Get(I).JsonString.Value);
        Result.Items.Add(JsonValueToNode(Obj.Get(I).JsonValue));
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

{ ---- Obfuscation (mirror of DeobfValue with the same ctx semantics) ------- }

function HexOfSha256(const AData: TBytes): string;
const
  H: array [0 .. 15] of Char = '0123456789abcdef';
var
  D: TBytes;
  I: Integer;
begin
  D := Sha256Of(AData);
  Result := '';
  for I := 0 to Length(D) - 1 do
    Result := Result + H[D[I] shr 4] + H[D[I] and 15];
end;

{ Recursively transforms a plain node tree into the obfuscated tree:
  object keys -> SHA-256 hex (original kept in ARev for the key_map), string
  values -> Base64(DeobfCodec(seed, UTF-8(value), ctx)) with the exact same
  ChildCtx/IndexCtx path semantics the deobfuscator walks, so the round trip
  is exact. Keys present in ASkip are dropped (META_KEY + dummies).

  Developer documentation fields (OBF_COMMENT_FIELDS) are encoded in their own
  domain under AvroShieldCommentCtx, with a key derived from the developer
  comment IKM - which is never derived from anything the runtime holds. }
function ObfuscateTree(ANode: TAvroNode; const ACtx: string;
  const ASeed, ACommentSeed: TBytes;
  ARev: TDictionary<string, string>; const ASkip: TDictionary<string, Boolean>): TAvroNode;
var
  I:         Integer;
  OrigKey, HashedKey: string;
  Child:     TAvroNode;
  ChildSeed, EffCommentSeed: TBytes;
  ChildCtxPath: string;
  IsComment: Boolean;
begin
  // A container built without a comment key keeps comments in the value domain,
  // exactly like format v2, so the reader's fallback matches on both sides.
  EffCommentSeed := ACommentSeed;
  if Length(EffCommentSeed) = 0 then
    EffCommentSeed := ASeed;

  Result := TAvroNode.Create;
  case ANode.Kind of
    nkObject:
      begin
        Result.Kind := nkObject;
        for I := 0 to ANode.Items.Count - 1 do
        begin
          OrigKey := ANode.Keys[I];
          HashedKey := HexOfSha256(TEncoding.UTF8.GetBytes(OrigKey));
          if ASkip.ContainsKey(HashedKey) then
            Continue;
          if not ARev.ContainsKey(HashedKey) then
            ARev.Add(HashedKey, OrigKey);
          IsComment := AvroShieldIsCommentField(OrigKey);
          if IsComment then
          begin
            ChildSeed := EffCommentSeed;
            ChildCtxPath := AvroShieldCommentCtx(ACtx, HashedKey);
          end
          else
          begin
            ChildSeed := ASeed;
            ChildCtxPath := ChildCtx(ACtx, HashedKey);
          end;
          Child := ObfuscateTree(ANode.Items[I], ChildCtxPath, ChildSeed,
            EffCommentSeed, ARev, ASkip);
          Result.Keys.Add(HashedKey);
          Result.Items.Add(Child);
        end;
      end;
    nkArray:
      begin
        Result.Kind := nkArray;
        for I := 0 to ANode.Items.Count - 1 do
          Result.Items.Add(ObfuscateTree(ANode.Items[I], IndexCtx(ACtx, I),
            ASeed, EffCommentSeed, ARev, ASkip));
      end;
    nkString:
      begin
        Result.Kind := nkString;
        // XOR codec is symmetric: encode == decode.
        Result.StrVal := TNetEncoding.Base64.EncodeBytesToString(
          DeobfCodec(ASeed, TEncoding.UTF8.GetBytes(ANode.StrVal), ACtx));
      end;
  else
    Result.Kind := ANode.Kind;
    Result.BoolVal := ANode.BoolVal;
    Result.IntVal := ANode.IntVal;
    Result.FloatVal := ANode.FloatVal;
  end;
end;

{ Injects 4-8 decoy root keys with obfuscated random string values. The decoys
  are listed in ADummies and ASkip, so the deobfuscator drops them while the
  raw bytecode still looks like a larger, non-obvious document. }
procedure AddDummyEntries(ARoot: TAvroNode; const ASeed: TBytes;
  ASkip: TDictionary<string, Boolean>; ADummies: TStringList);
var
  I, N, Guard: Integer;
  KeyBytes, Rand: TBytes;
  Key: string;
  Node: TAvroNode;
begin
  FillRandomBytes(Rand, 4);
  N := 4 + (Integer(Rand[0]) mod 5); // 4..8 decoys
  for I := 0 to N - 1 do
  begin
    Guard := 0;
    repeat
      FillRandomBytes(KeyBytes, 16);
      Key := 'd' + HexOfSha256(KeyBytes);
      Inc(Guard);
    until (not ASkip.ContainsKey(Key)) and (ARoot.Keys.IndexOf(Key) < 0) and
      (Guard < 16);
    if Guard >= 16 then
      Break;
    Node := TAvroNode.Create;
    Node.Kind := nkString;
    FillRandomBytes(Rand, 24);
    Node.StrVal := TNetEncoding.Base64.EncodeBytesToString(
      DeobfCodec(ASeed, Rand, Key));
    ARoot.Keys.Add(Key);
    ARoot.Items.Add(Node);
    ASkip.Add(Key, True);
    ADummies.Add(Key);
  end;
end;

{ _obf_meta JSON carries: seed (base64), key_map and dummies. NOTE the
  inverted key_map order - the deobfuscator reads
  Rev[JsonValue.Value] := JsonString.Value, i.e. hashed <- orig. }
function BuildMetaJson(const ASeed: TBytes;
  const ARev: TDictionary<string, string>; const ADummies: TStringList): string;
var
  Obj, KMap: TJSONObject;
  JArr:      TJSONArray;
  Pair:      TPair<string, string>;
  I:         Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('seed', TNetEncoding.Base64.EncodeBytesToString(ASeed));
    KMap := TJSONObject.Create;
    for Pair in ARev do
      KMap.AddPair(Pair.Value, Pair.Key); // orig -> hashed (inverted)
    Obj.AddPair('key_map', KMap);
    JArr := TJSONArray.Create;
    for I := 0 to ADummies.Count - 1 do
      JArr.Add(ADummies[I]);
    Obj.AddPair('dummies', JArr);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

{ ---- Bytecode serialization (mirror of ParseNode / AvroShieldParseBytecode) - }

procedure StreamWriteBE16(AStrm: TStream; V: Word);
var
  B: array [0 .. 1] of Byte;
begin
  B[0] := Byte(V shr 8);
  B[1] := Byte(V);
  AStrm.WriteBuffer(B, 2);
end;

procedure StreamWriteBE32(AStrm: TStream; V: Cardinal);
var
  B: array [0 .. 3] of Byte;
begin
  B[0] := Byte(V shr 24);
  B[1] := Byte(V shr 16);
  B[2] := Byte(V shr 8);
  B[3] := Byte(V);
  AStrm.WriteBuffer(B, 4);
end;

procedure BcWriteNode(AStrm: TStream; ANode: TAvroNode);
var
  Typ, B:  Byte;
  Bytes:   TBytes;
  Bits:    UInt64;
  I, Cnt:  Integer;
begin
  case ANode.Kind of
    nkNull:   Typ := TYPE_NULL;
    nkBool:   Typ := TYPE_BOOLEAN;
    nkInt, nkFloat: Typ := TYPE_NUMBER;
    nkString: Typ := TYPE_STRING;
    nkArray:  Typ := TYPE_ARRAY;
    nkObject: Typ := TYPE_OBJECT;
  else
    raise ShieldWriterError('Cannot serialize node kind');
  end;
  AStrm.WriteBuffer(Typ, 1);

  case ANode.Kind of
    nkBool:
      begin
        B := 0;
        if ANode.BoolVal then
          B := 1;
        AStrm.WriteBuffer(B, 1);
      end;
    nkInt, nkFloat:
      begin
        if ANode.Kind = nkInt then
        begin
          B := 1;
          Bits := UInt64(ANode.IntVal);
        end
        else
        begin
          B := 0;
          Move(ANode.FloatVal, Bits, 8);
        end;
        AStrm.WriteBuffer(B, 1);
        for I := 7 downto 0 do
        begin
          B := Byte(Bits shr (I * 8));
          AStrm.WriteBuffer(B, 1);
        end;
      end;
    nkString:
      begin
        // String payloads are XOR-masked with the deterministic length-keyed
        // keystream; the reader unmasks with the same function.
        Bytes := BcMaskString(TEncoding.UTF8.GetBytes(ANode.StrVal));
        StreamWriteBE32(AStrm, Cardinal(Length(Bytes)));
        if Length(Bytes) > 0 then
          AStrm.WriteBuffer(Bytes[0], Length(Bytes));
      end;
    nkArray:
      begin
        Cnt := ANode.Items.Count;
        StreamWriteBE32(AStrm, Cardinal(Cnt));
        for I := 0 to Cnt - 1 do
          BcWriteNode(AStrm, ANode.Items[I]);
      end;
    nkObject:
      begin
        Cnt := ANode.Items.Count;
        StreamWriteBE32(AStrm, Cardinal(Cnt));
        for I := 0 to Cnt - 1 do
        begin
          Bytes := TEncoding.UTF8.GetBytes(ANode.Keys[I]);
          StreamWriteBE16(AStrm, Word(Length(Bytes)));
          if Length(Bytes) > 0 then
            AStrm.WriteBuffer(Bytes[0], Length(Bytes));
          BcWriteNode(AStrm, ANode.Items[I]);
        end;
      end;
  end;
end;

{ 'AVROBC' + ver + BE32(TypeCount=0) + BE32(EntryCount) + 8 reserved bytes
  (= 23-byte header) + per-entry: BE16 keyLen, key, BE32 nodeLen, node,
  BE32 crc32 + SHA-256 trailer over everything before the last 32 bytes. }
function AssembleBytecode(ARoot: TAvroNode): TBytes;
var
  MS, EntryMS, NodeMS: TMemoryStream;
  B:      Byte;
  I:      Integer;
  Crc:    Cardinal;
  Trailer, TrailerSrc, KeyBytes: TBytes;
begin
  Result := nil;
  MS := TMemoryStream.Create;
  EntryMS := TMemoryStream.Create;
  NodeMS := TMemoryStream.Create;
  try
    // Magic + version
    MS.WriteBuffer(AsMagicBC[0], 6);
    B := 1;
    MS.WriteBuffer(B, 1);
    // TypeCount = 0 (no type table)
    StreamWriteBE32(MS, 0);
    // EntryCount
    StreamWriteBE32(MS, Cardinal(ARoot.Items.Count));
    // 8 reserved bytes -> 23-byte header (reader does not validate them)
    B := 0;
    for I := 0 to 7 do
      MS.WriteBuffer(B, 1);
    // Entries
    for I := 0 to ARoot.Items.Count - 1 do
    begin
      EntryMS.Size := 0;
      EntryMS.Position := 0;
      // BE16 keyLen + raw key bytes (object keys are stored unmasked)
      KeyBytes := TEncoding.UTF8.GetBytes(ARoot.Keys[I]);
      StreamWriteBE16(EntryMS, Word(Length(KeyBytes)));
      if Length(KeyBytes) > 0 then
        EntryMS.WriteBuffer(KeyBytes[0], Length(KeyBytes));
      // BE32 nodeLen + node bytes
      NodeMS.Size := 0;
      NodeMS.Position := 0;
      BcWriteNode(NodeMS, ARoot.Items[I]);
      StreamWriteBE32(EntryMS, Cardinal(NodeMS.Size));
      if NodeMS.Size > 0 then
        EntryMS.WriteBuffer(NodeMS.Memory^, NodeMS.Size);
      // crc32 over keyLen+key+nodeLen+node
      Crc := crc32(0, PByte(EntryMS.Memory), EntryMS.Size);
      // Append entry + stored crc to the bytecode stream
      MS.WriteBuffer(EntryMS.Memory^, EntryMS.Size);
      StreamWriteBE32(MS, Crc);
    end;
    // SHA-256 trailer over everything written so far
    SetLength(TrailerSrc, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(TrailerSrc[0], MS.Size);
      MS.Position := MS.Size;
    end;
    Trailer := Sha256Of(TrailerSrc);
    FillChar(TrailerSrc[0], Length(TrailerSrc), 0);
    SetLength(TrailerSrc, 0);
    MS.WriteBuffer(Trailer[0], Length(Trailer));
    SetLength(Result, MS.Size);
    if MS.Size > 0 then
    begin
      MS.Position := 0;
      MS.Read(Result[0], MS.Size);
    end;
  finally
    NodeMS.Free;
    EntryMS.Free;
    MS.Free;
  end;
end;

{ ---- zlib compression (Python zlib.compress compatible) -------------------- }

function ZlibCompressBytes(const AData: TBytes): TBytes;
var
  InS, OutS: TMemoryStream;
  Z:   TZCompressionStream;
  Buf: array [0 .. 8191] of Byte;
  N:   Integer;
begin
  Result := nil;
  InS := TMemoryStream.Create;
  OutS := TMemoryStream.Create;
  Z := nil;
  try
    if Length(AData) > 0 then
      InS.Write(AData[0], Length(AData));
    InS.Position := 0;
    Z := TZCompressionStream.Create(OutS, zcDefault, 15);
    try
      repeat
        N := InS.Read(Buf, SizeOf(Buf));
        if N > 0 then
          Z.Write(Buf, N);
      until N < SizeOf(Buf);
    finally
      Z.Free;
    end;
    SetLength(Result, OutS.Size);
    if OutS.Size > 0 then
    begin
      OutS.Position := 0;
      OutS.Read(Result[0], OutS.Size);
    end;
  finally
    OutS.Free;
    InS.Free;
  end;
end;

{ ---- container assembly ---------------------------------------------------- }

function AvroShieldBuildFromJson(const AJsonText, APassword: string;
  const ADefaultKey, ABindToMachine, AUseHardwareFactor: Boolean;
  out AOutBytes: TBytes; const ADefaultSecretIKM: TBytes;
  const ACommentsIKM: TBytes): TAvroShieldResult;
var
  Json:      TJSONValue;
  Root, Obf, MetaNode: TAvroNode;
  Rev:       TDictionary<string, string>;
  Skip:      TDictionary<string, Boolean>;
  Dummies:   TStringList;
  Seed, CommentSeed, MetaMask: TBytes;
  Salt, IV, Machine, Master, FinalKey, EncKey, MacKey: TBytes;
  MachineF, HardwareF: TBytes;
  DefaultIKM, PasswordIKM: TBytes;
  Flags, B:  Byte;
  Compressed, Bytecode, CipherTag, HmacData, Hmac, HeaderSrc: TBytes;
  MetaJson: string;
  AStrm:     TMemoryStream;
begin
  Result := asrUnknown;
  AOutBytes := nil;

  if (not ADefaultKey) and (APassword = '') then
    Exit(asrEmptyPassword);

  Json := TJSONObject.ParseJSONValue(Trim(AJsonText));
  if Json = nil then
    Exit(asrCorruptPayload);
  if not (Json is TJSONObject) then
  begin
    Json.Free;
    Exit(asrNotJsonObject);
  end;
  try
    Root := JsonValueToNode(Json);
  finally
    Json.Free;
  end;
  try
    // ---- container key material ----
    // Salt and the master key must exist before the obfuscation stage: the
    // metadata blob that carries the value seed and the key map is masked with
    // a key derived from the master key (format v3), never with a constant
    // compiled into this unit.
    FillRandomBytes(Salt, 16);
    if ADefaultKey then
    begin
      if Length(ADefaultSecretIKM) > 0 then
        DefaultIKM := Copy(ADefaultSecretIKM, 0, Length(ADefaultSecretIKM))
      else
        DefaultIKM := GetAvroEncoSecretIKM;
      Master := ShieldKdfDefaultKey(DefaultIKM, Salt);
    end
    else
    begin
      PasswordIKM := TEncoding.UTF8.GetBytes(APassword);
      Master := ShieldKdfPasswordKey(PasswordIKM, Salt);
      AvroWipeAndRelease(PasswordIKM);
    end;
    MetaMask := AvroShieldMetaMask(Master);

    // ---- obfuscate ----
    FillRandomBytes(Seed, 32);
    // Comment key: developer IKM salted with this build's value seed. The
    // runtime has neither, so comment text cannot be recovered from a shipped
    // container even by someone who extracted the container key.
    CommentSeed := AvroShieldCommentKey(ACommentsIKM, Seed);
    Rev := TDictionary<string, string>.Create;
    Skip := TDictionary<string, Boolean>.Create;
    Dummies := TStringList.Create;
    try
      Skip.Add(META_KEY, True);
      Obf := ObfuscateTree(Root, '', Seed, CommentSeed, Rev, Skip);
      // Decoys are injected into the OBFUSCATED tree (their keys must appear
      // exactly once, already hashed, and they are dropped by the
      // deobfuscator via ASkip).
      AddDummyEntries(Obf, Seed, Skip, Dummies);
      try
        // _obf_meta entry: Base64(DeobfCodec(MetaMask, metaJson, META_KEY))
        // with MetaMask derived from the container master key, so the value
        // seed and the key map are only reachable by whoever can open the
        // container. MetaNode is owned by Obf.Items (TObjectList with
        // OwnsObjects=True).
        MetaJson := BuildMetaJson(Seed, Rev, Dummies);
        MetaNode := TAvroNode.Create;
        MetaNode.Kind := nkString;
        MetaNode.StrVal := TNetEncoding.Base64.EncodeBytesToString(
          DeobfCodec(MetaMask, TEncoding.UTF8.GetBytes(MetaJson), META_KEY));
        Obf.Keys.Add(META_KEY);
        Obf.Items.Add(MetaNode);
        Bytecode := AssembleBytecode(Obf);
      finally
        Obf.Free;
      end;
    finally
      Dummies.Free;
      Skip.Free;
      Rev.Free;
    end;
    if Length(Bytecode) = 0 then
      Exit(asrCorruptPayload);

    // ---- compress ----
    Compressed := ZlibCompressBytes(Bytecode);
    FillChar(Bytecode[0], Length(Bytecode), 0);
    SetLength(Bytecode, 0);
    if Length(Compressed) = 0 then
      Exit(asrCorruptPayload);

    // ---- header flags (Salt/Master were derived before the obfuscation
    //      stage; the IV is per container and not needed earlier) ----
    FillRandomBytes(IV, 16);
    Flags := FLAG_PASSWORD or FLAG_BYTECODE_V1;
    if ADefaultKey then
      Flags := Flags or AVROSHLD_FLAG_DEFAULT_KEY;
    if ABindToMachine then
      Flags := Flags or FLAG_MACHINE_BIND;
    if AUseHardwareFactor then
      Flags := Flags or FLAG_HARDWARE;

    if (Flags and FLAG_MACHINE_BIND) <> 0 then
      Machine := AvroShieldMachineId
    else
    begin
      SetLength(Machine, 16);
      FillChar(Machine[0], 16, 0);
    end;

    // The key schedule (HKDF for default-key, PBKDF2 for password containers,
    // no Argon2 anywhere) already ran above, before the obfuscation stage.
    try
      SetLength(MachineF, 16);
      FillChar(MachineF[0], 16, 0);
      if (Flags and FLAG_MACHINE_BIND) <> 0 then
        MachineF := AvroShieldMachineId;
      SetLength(HardwareF, 16);
      FillChar(HardwareF[0], 16, 0);
      if (Flags and FLAG_HARDWARE) <> 0 then
        HardwareF := AvroShieldMachineId;

      FinalKey := Sha512Of(Master + MachineF + HardwareF);
      EncKey := Copy(FinalKey, 0, 32);
      MacKey := Copy(FinalKey, 32, 32);

      // ---- encrypt + authenticate ----
      AES256GCMEncrypt(Compressed, EncKey, IV, nil, CipherTag);
      FillChar(Compressed[0], Length(Compressed), 0);
      SetLength(Compressed, 0);

      AStrm := TMemoryStream.Create;
      try
        AStrm.WriteBuffer(AsMagic[0], 8);
        B := AS_VERSION;
        AStrm.WriteBuffer(B, 1);
        AStrm.WriteBuffer(Flags, 1);
        AStrm.WriteBuffer(Salt[0], 16);
        AStrm.WriteBuffer(IV[0], 16);
        AStrm.WriteBuffer(Machine[0], 16);
        // header = 58 bytes; HMAC over header + ciphertext + tag
        SetLength(HeaderSrc, AStrm.Size);
        if AStrm.Size > 0 then
        begin
          AStrm.Position := 0;
          AStrm.Read(HeaderSrc[0], AStrm.Size);
          AStrm.Position := AStrm.Size;
        end;
        HmacData := HeaderSrc + CipherTag;
        Hmac := HMACSHA512(MacKey, HmacData);
        FillChar(HeaderSrc[0], Length(HeaderSrc), 0);
        SetLength(HeaderSrc, 0);
        FillChar(HmacData[0], Length(HmacData), 0);
        SetLength(HmacData, 0);
        AStrm.WriteBuffer(CipherTag[0], Length(CipherTag));
        AStrm.WriteBuffer(Hmac[0], Length(Hmac));
        SetLength(AOutBytes, AStrm.Size);
        if AStrm.Size > 0 then
        begin
          AStrm.Position := 0;
          AStrm.Read(AOutBytes[0], AStrm.Size);
        end;
        Result := asrOk;
      finally
        AStrm.Free;
      end;
    finally
      // Mirror of the loader's hygiene: the writer derives the same key
      // material, so it must wipe the same set. Previously only Master and
      // FinalKey were wiped here, leaving EncKey, MacKey and the HMAC input
      // readable in freed heap memory.
      AvroWipeAndRelease(PasswordIKM);
      AvroWipeAndRelease(DefaultIKM);
      AvroWipeAndRelease(Master);
      AvroWipeAndRelease(MachineF);
      AvroWipeAndRelease(HardwareF);
      AvroWipeAndRelease(FinalKey);
      AvroWipeAndRelease(EncKey);
      AvroWipeAndRelease(MacKey);
      AvroWipeAndRelease(Salt);
      AvroWipeAndRelease(IV);
      AvroWipeAndRelease(Machine);
      AvroWipeAndRelease(CipherTag);
      AvroWipeAndRelease(HmacData);
      AvroWipeAndRelease(Hmac);
      AvroWipeAndRelease(HeaderSrc);
      AvroWipeAndRelease(Compressed);
      AvroWipeAndRelease(Bytecode);
      AvroWipeAndRelease(Seed);
      AvroWipeAndRelease(CommentSeed);
      AvroWipeAndRelease(MetaMask);
    end;
  finally
    Root.Free;
  end;
end;

constructor TAvroNode.Create;
begin
  inherited Create;
  Items := TObjectList<TAvroNode>.Create(True);
  Keys := TStringList.Create;
  Keys.CaseSensitive := True;
end;

destructor TAvroNode.Destroy;
begin
  Items.Free;
  Keys.Free;
  inherited Destroy;
end;

end.
