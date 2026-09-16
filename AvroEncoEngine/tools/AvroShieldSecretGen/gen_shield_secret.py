#!/usr/bin/env python3
"""Offline generator for the AvroShield root-secret constants.

WHY THIS EXISTS
---------------
uAvroCryptoUtils.pas used to carry the default application secret as two
adjacent 64-byte arrays (AVROENCO_KEY_MASK and AVROENCO_KEY_XOR) whose XOR is
the plaintext phrase. That is a five-line recovery for any analyst with a hex
editor, so the protection of every .AvroEnco container reduced to it.

This tool emits a single obfuscated blob instead. Each byte is masked with a
keystream derived from a small xorshift32 PRNG seeded by a 32-bit constant,
rotated by its own index:

    blob[i] = ikm[i] XOR rotl8(ks_byte(i), i mod 8)
    ks_byte(i): advance xorshift32 once per 4 bytes, take byte (i mod 4)

Recovering the IKM now requires reimplementing the PRNG (and, once the
expansion routine is VMProtect-virtualized, extracting it from the VM), rather
than XORing two constant arrays that sit next to each other in .rdata.

The emitted unit is byte-compatible: decoding the blob yields exactly the same
IKM bytes that were encoded, so rotating the secret is a deliberate, explicit
act controlled by whoever runs this tool.

USAGE
-----
  # Regenerate the constants for the existing secret (no rotation):
  python gen_shield_secret.py --secret "<phrase>" --key-file keys/avroenco.key

  # Rotate to a fresh 38-byte secret:
  python gen_shield_secret.py --random 38 --key-file keys/avroenco.key

  # Just print the unit body for review:
  python gen_shield_secret.py --secret "<phrase>"

The --key-file output is the raw IKM (no trailing newline, no padding) and is
what `AvroEncoBuilder --default-key --secret-file <path>` consumes, so the
build tool never has to embed the secret at all.
"""

from __future__ import annotations

import argparse
import os
import secrets
import sys

MASK32 = 0xFFFFFFFF
DEFAULT_BLOB_LEN = 48

# Must match AVRO_SECRET_SEED in the emitted unit: this is the only free
# parameter of the obfuscation, not a secret.
DEFAULT_SEED = 0x5F3A17C9


def xorshift32(state: int) -> int:
    state ^= (state << 13) & MASK32
    state ^= state >> 17
    state ^= (state << 5) & MASK32
    return state & MASK32


def rotl8(value: int, rot: int) -> int:
    rot &= 7
    value &= 0xFF
    return ((value << rot) | (value >> (8 - rot))) & 0xFF


def keystream_bytes(seed: int, count: int) -> list[int]:
    """Mirrors the Delphi AVRO_SECRET_KS decoder exactly."""
    out: list[int] = []
    state = seed & MASK32
    for i in range(count):
        if i % 4 == 0:
            state = xorshift32(state)
        out.append((state >> (8 * (i % 4))) & 0xFF)
    return out


def encode(ikm: bytes, seed: int, blob_len: int) -> bytes:
    if len(ikm) >= blob_len:
        raise SystemExit(
            f"secret is {len(ikm)} bytes; blob length {blob_len} must exceed it "
            "(the decoder needs at least one decoded NUL as a terminator)"
        )
    if 0 in ikm:
        # The decoder stops at the first decoded NUL, so an embedded NUL would
        # silently truncate the secret.
        raise SystemExit("secret must not contain a NUL byte")

    ks = keystream_bytes(seed, blob_len)
    blob = bytearray(blob_len)
    for i, b in enumerate(ikm):
        blob[i] = b ^ rotl8(ks[i], i % 8)
    # Padding decodes to 0x00, which terminates the decoded IKM.
    for i in range(len(ikm), blob_len):
        blob[i] = rotl8(ks[i], i % 8)
    return bytes(blob)


def decode(blob: bytes, seed: int) -> bytes:
    """Inverse of encode(); used to self-check the emitted constants."""
    ks = keystream_bytes(seed, len(blob))
    out = bytearray()
    for i, b in enumerate(blob):
        plain = b ^ rotl8(ks[i], i % 8)
        if plain == 0:
            break
        out.append(plain)
    return bytes(out)


def pascal_byte_array(name: str, data: bytes, indent: str = "    ") -> str:
    lines = []
    for start in range(0, len(data), 12):
        chunk = data[start : start + 12]
        lines.append(indent + ", ".join(f"${b:02X}" for b in chunk))
    body = (",\n" + indent).join(lines)
    return (
        f"{name}: array [0 .. {len(data) - 1}] of Byte = (\n"
        f"{indent}{body}\n"
        f"  );"
    )


def emit_unit(blob: bytes, seed: int, ikm_len: int) -> str:
    return f"""{{=---------------------------------------------------------------------------
  uAvroShieldSecret - obfuscated root secret for default-key containers.

  GENERATED FILE - do not edit by hand. Regenerate with
  AvroEncoEngine\\tools\\AvroShieldSecretGen\\gen_shield_secret.py

  The IKM is a {ikm_len}-byte secret masked with a rotl-indexed xorshift32
  keystream. It is NOT two complementary arrays: recovering the plaintext
  requires reproducing AVRO_SECRET_KS, and that routine is the one marked
  VMProtectBeginUltra in Phase 2 of the hardening plan.

  AvroShieldSecretIKM returns raw bytes and never builds a Delphi string, so
  the secret never exists as a UTF-16 heap allocation on the default-key load
  path. AvroShieldSecretString exists only for the deprecated legacy CBC
  reader and the persistent-cache key, and is documented as such.

  ROTATION: run the generator with --random N and regenerate every shipped
  container with AvroEncoBuilder. Until containers are rebuilt, old and new
  secrets do not interoperate (by design - that is what rotation means). The
  pinned digest in kat_shieldsecret.dpr intentionally fails on rotation so a
  new secret cannot be adopted by accident.
  ---------------------------------------------------------------------------}}

unit uAvroShieldSecret;

{{ Inlining OFF for this unit only. The secret expansion below is the
  VMProtectBeginUltra region; if Delphi inlines a marked routine into its
  caller, the identical logic survives unprotected in the caller as well, so
  the virtualised copy is not the only copy an analyst can reach. This costs
  nothing measurable on the load path, which is the only path that uses it.
  (Units without markers keep inlining - notably uAvroCryptoUtils, whose AES
  and GCM round functions are genuinely hot.) }}
{{$INLINE OFF}}

interface

uses
  System.SysUtils; // TBytes

{{ Decoded root secret IKM, exactly the bytes fed to HKDF-SHA256 for
  default-key containers. Terminated at the first decoded NUL byte. }}
function AvroShieldSecretIKM: TBytes;

{{ Legacy accessor: the same IKM interpreted as an ASCII string. Deprecated -
  used only by uAvroEncoCrypto's v1/v2 CBC reader and uAnsiPersistentCache's
  cache-key derivation. Do not use on the Shield load path. }}
function AvroShieldSecretString: string;

{{ Length of the decoded IKM, without allocating it. Used by self-checks. }}
function AvroShieldSecretLength: Integer;

implementation

uses
  uAvroSecureMem,
  uAvroShieldVM;

const
  {{ xorshift32 seed. Not a secret; the only free parameter of the mask. }}
  AVRO_SECRET_SEED = ${seed:08X};

  {{ Decoded IKM length (excludes the NUL terminator). }}
  AVRO_SECRET_LEN = {ikm_len};

  {{ Masked secret. blob[i] XOR rotl8(keystream(i), i mod 8) == ikm[i]. }}
  {pascal_byte_array("AVRO_SECRET_BLOB", blob)}

{{ One xorshift32 step (Marsaglia). Kept trivial on purpose: this function and
  its caller are the VMProtectBeginUltra region. }}
function AvroSecretXorShift32(AState: Cardinal): Cardinal; inline;
begin
  AState := AState xor (AState shl 13);
  AState := AState xor (AState shr 17);
  AState := AState xor (AState shl 5);
  Result := AState;
end;

{{ Rotate-left within a byte. ARot of 0 must return the value unchanged, so the
  right-shift by (8 - ARot) has to be evaluated on a promoted Integer (a Byte
  shifted right by 8 is 0, and Delphi promotes before shifting). }}
function AvroSecretRotl8(AValue: Byte; ARot: Integer): Byte; inline;
begin
  ARot := ARot and 7;
  Result := Byte(((Integer(AValue) shl ARot) or (Integer(AValue) shr (8 - ARot)))
    and $FF);
end;

function AvroShieldSecretIKM: TBytes;
var
  I: Integer;
  State: Cardinal;
  Plain: Byte;
begin
  {{ The single highest-value VMProtect region in the project: every
    container's confidentiality reduces to these bytes. Marker pair without
    try/finally on purpose - VMProtect handles the plain form reliably, while
    SEH inside a virtualised block is a known source of protection-time
    breakage, and nothing here raises in normal operation. }}
  VMBeginUltra('sk');
  SetLength(Result, Length(AVRO_SECRET_BLOB));
  State := AVRO_SECRET_SEED;
  I := 0;
  while I < Length(AVRO_SECRET_BLOB) do
  begin
    if (I mod 4) = 0 then
      State := AvroSecretXorShift32(State);
    Plain := AVRO_SECRET_BLOB[I] xor
      AvroSecretRotl8(Byte(State shr (8 * (I mod 4))), I);
    Result[I] := Plain;
    if Plain = 0 then
    begin
      // Terminator: trim to the declared length and stop.
      SetLength(Result, I);
      Break;
    end;
    Inc(I);
  end;
  if Length(Result) > AVRO_SECRET_LEN then
    SetLength(Result, AVRO_SECRET_LEN);
  VMEnd;
end;

function AvroShieldSecretLength: Integer;
begin
  Result := Length(AvroShieldSecretIKM);
end;

function AvroShieldSecretString: string;
var
  IKM: TBytes;
begin
  IKM := AvroShieldSecretIKM;
  try
    Result := TEncoding.ASCII.GetString(IKM);
  finally
    // The caller keeps the string (legacy contract); only the raw byte copy
    // is wiped here.
    AvroWipeAndRelease(IKM);
  end;
end;

end.
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--secret", help="existing secret phrase to re-encode")
    src.add_argument("--random", type=int, metavar="N",
                     help="generate a fresh random N-byte secret (rotation)")
    ap.add_argument("--seed", type=lambda v: int(v, 0), default=DEFAULT_SEED,
                    help=f"xorshift32 seed (default 0x{DEFAULT_SEED:08X})")
    ap.add_argument("--blob-len", type=int, default=DEFAULT_BLOB_LEN,
                    help=f"masked blob length (default {DEFAULT_BLOB_LEN})")
    ap.add_argument("--out-pas", help="write the generated unit here")
    ap.add_argument("--key-file", help="write the raw IKM here (for --secret-file)")
    ap.add_argument("--print-key-hex", action="store_true",
                    help="print the IKM as hex for cross-checking")
    args = ap.parse_args()

    if args.secret is not None:
        ikm = args.secret.encode("ascii")
    else:
        if args.random < 8:
            raise SystemExit("refusing to generate a secret shorter than 8 bytes")
        ikm = secrets.token_bytes(args.random)

    blob = encode(ikm, args.seed, args.blob_len)

    # Self-check: the emitted constants must decode back to the exact IKM.
    if decode(blob, args.seed) != ikm:
        raise SystemExit("internal error: encode/decode round-trip mismatch")

    unit_src = emit_unit(blob, args.seed, len(ikm))

    if args.out_pas:
        with open(args.out_pas, "w", encoding="utf-8", newline="\r\n") as fh:
            fh.write(unit_src)
        print(f"wrote {args.out_pas}")
    else:
        sys.stdout.write(unit_src)

    if args.key_file:
        d = os.path.dirname(os.path.abspath(args.key_file))
        if d:
            os.makedirs(d, exist_ok=True)
        with open(args.key_file, "wb") as fh:
            fh.write(ikm)
        print(f"wrote {args.key_file} ({len(ikm)} bytes)")

    if args.print_key_hex:
        print(f"IKM ({len(ikm)} bytes): {ikm.hex()}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
