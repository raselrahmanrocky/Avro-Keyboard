{ =============================================================================
  uAvroSecureMem - memory hygiene and fused-gate primitives shared by the
  AvroShield loader, the ANSI engine cache and the legacy container reader.

  WHY THIS UNIT EXISTS
  --------------------
  The previous code wiped secrets with FillChar on a TBytes that was dead after
  the call. Delphi is free to delete a store to a variable that is never read
  again, and it does so at optimization level that Release builds enable. The
  wipes therefore were not guaranteed, and several key buffers were never
  touched at all.

  AvroSecureZero routes through RtlZeroMemory, an opaque external call that the
  Delphi optimizer cannot eliminate as a dead store. The Pascal fallback is a
  pointer walk for non-Windows targets.

  WIPE DISCIPLINE - the two mistakes this unit exists to prevent:
    1. Wiping a Buffer via FillChar on a dead local: eliminated by the compiler.
    2. Zeroing PChar(S)^ without UniqueString: a Delphi string is a shared,
       reference-counted buffer, so writing into it corrupts every other
       variable holding the same value. AvroWipeString breaks the sharing
       first.

  THE FUSED GATE - what it does and does not buy
  ----------------------------------------------
  AvroFuse/AvroFuseOk turn the fail-closed decision into an equality test on an
  arithmetic value rather than a branch on a Boolean flag, so a single flipped
  flag bit does not silently invert the policy. That is a real but LIMITED
  gain: an attacker who can fault-inject twice defeats it.

  The genuine redundancy in this system is cryptographic and already present:
  HMAC-SHA512 over header+ciphertext+tag, and the AES-GCM tag itself are two
  independent authenticators computed over different key material. A glitch
  that suppresses the HMAC verdict still cannot make the GCM tag validate.
  The fused gate is defence in depth for the policy edge only - it is not a
  substitute for the authenticators, and this unit does not pretend otherwise.
  ============================================================================= }

unit uAvroSecureMem;

interface

uses
  System.SysUtils;

{ ---- secure wipe -------------------------------------------------------- }

{ Zeroes ACount bytes at ABuf. Untyped like FillChar so call sites read the
  same, but the stores cannot be optimized away. No-op for ACount = 0. }
procedure AvroSecureZero(const ABuf; ACount: NativeUInt);

{ Zeroes the contents of AData without releasing it. The caller keeps its
  reference; other references to the same buffer observe the wipe, which is
  the intended behaviour for shared key material. }
procedure AvroWipeBytes(const AData: TBytes);

{ Zeroes then releases AData. Prefer this to a bare SetLength(...,0). }
procedure AvroWipeAndRelease(var AData: TBytes);

{ Zeroes a string's characters and clears the variable. Breaks copy-on-write
  first, so a string shared with another variable - or a literal - is never
  corrupted. }
procedure AvroWipeString(var AValue: string);

{ Wipes each element in place. The array is shared with the caller (dynamic
  arrays are references), so the caller's strings are wiped too. }
procedure AvroWipeStringArray(AValues: TArray<string>);

{ ---- fused fail-closed gate -------------------------------------------- }

const
  { Golden-ratio 32-bit multiplier; the low 32 bits of 2^32 / phi. }
  AVRO_FUSE_MUL: Cardinal = $9E3779B1;
  { Murmur3 32-bit finalizer constant. }
  AVRO_FUSE_XOR: Cardinal = $85EBCA6B;
  { AvroFuse(True) for the constants above: $9E3779B1 xor $85EBCA6B. Verified
    at run time by kat_shieldsecret so the two cannot drift apart. }
  AVRO_FUSE_OPEN: Cardinal = $1BDCB3DA;

{ Maps a correctness verdict onto a value that must equal AVRO_FUSE_OPEN for
  the operation to be allowed to continue. }
function AvroFuse(AOk: Boolean): Cardinal;

{ The single place the fused value is judged. }
function AvroFuseOk(AFuse: Cardinal): Boolean;

implementation

{$IFDEF MSWINDOWS}
{ Verified on Windows 11 24H2 with GetProcAddress: kernel32 and ntdll export
  RtlZeroMemory but NOT RtlSecureZeroMemory. That is expected and not a mistake
  to be "fixed" - winnt.h defines RtlSecureZeroMemory as a FORCEINLINE wrapper
  around volatile byte stores, so it is a header intrinsic with no DLL export.
  Importing it would produce a binary that fails in the loader with no message.

  RtlZeroMemory is the correct choice: it is an opaque external call, so the
  Delphi optimizer cannot prove anything about the destination and cannot
  eliminate the stores - which is the entire property being relied on here.
  Declared locally, following this codebase's existing RtlGenRandom pattern. }
procedure AvroRtlZeroMemory(ADest: Pointer; ACount: NativeUInt); stdcall;
  external 'kernel32.dll' name 'RtlZeroMemory';
{$ENDIF}

procedure AvroSecureZero(const ABuf; ACount: NativeUInt);
var
  P: PByte;
begin
  if ACount = 0 then
    Exit;
  P := PByte(@ABuf);
{$IFDEF MSWINDOWS}
  AvroRtlZeroMemory(P, ACount);
{$ELSE}
  while ACount > 0 do
  begin
    P^ := 0;
    Inc(P);
    Dec(ACount);
  end;
{$ENDIF}
end;

procedure AvroWipeBytes(const AData: TBytes);
begin
  if Length(AData) > 0 then
    AvroSecureZero(AData[0], NativeUInt(Length(AData)));
end;

procedure AvroWipeAndRelease(var AData: TBytes);
begin
  AvroWipeBytes(AData);
  if Length(AData) > 0 then
    SetLength(AData, 0);
end;

procedure AvroWipeString(var AValue: string);
var
  L: Integer;
begin
  L := Length(AValue);
  if L = 0 then
    Exit;
  { Mandatory: without this, writing into a shared or literal buffer would
    corrupt every other holder of the same string. }
  UniqueString(AValue);
  { UniqueString cannot change the length. }
  AvroSecureZero(PChar(AValue)^, NativeUInt(L) * SizeOf(Char));
  AValue := '';
end;

procedure AvroWipeStringArray(AValues: TArray<string>);
var
  I: Integer;
begin
  for I := 0 to Length(AValues) - 1 do
    AvroWipeString(AValues[I]);
end;

function AvroFuse(AOk: Boolean): Cardinal;
begin
  Result := (Cardinal(Ord(AOk)) * AVRO_FUSE_MUL) xor AVRO_FUSE_XOR;
end;

function AvroFuseOk(AFuse: Cardinal): Boolean;
begin
  Result := AFuse = AVRO_FUSE_OPEN;
end;

end.
