// avroenco_reader.h - reader for the AvroShield ".AvroEnco" mapping container.
//
// The ANSI mappings ship as encrypted containers (magic 'AVROSHLD') instead of
// readable JSON: header -> AES-256-GCM -> zlib -> 'AVROBC' bytecode ->
// deobfuscate -> mapping JSON.  Everything is decrypted in RAM and nothing is
// written back to disk, matching the original engine's contract.
//
// The pipeline is a faithful port of the Delphi units this project is a port
// of (uAvroShield.pas / uAvroShieldSecret.pas / uAvroEncoCrypto.pas), so a
// container built by AvroEncoBuilder loads here with the same result:
//
//   header (58)   'AVROSHLD' + version(1) + flags(1) + salt(16) + nonce(16)
//                 + machine id(16)
//   ciphertext    AES-256-GCM, authentication tag appended
//   trailer (80)  tag(16) + HMAC-SHA512(64) over header + ciphertext + tag
//
//   master  = HKDF-SHA256(secret, salt, 'AvroShield-v2/hkdf-sha256/default-key')
//   final   = SHA-512(master || machine factor || hardware factor)
//   keys    = enc = final[0..31], mac = final[32..63]
//
// Comment fields (developer documentation) live in a separate obfuscation
// domain keyed by an IKM the runtime never holds, so they are dropped before
// any decode - exactly like the original engine's runtime path.

#pragma once

#include <cstddef>
#include <string>

namespace avro {

// True when the buffer starts with a container magic this reader understands
// ('AVROSHLD' v2/v3).  The legacy 'AVROENCO' CBC format is not supported.
bool isAvroEncoContainer(const unsigned char* data, std::size_t size);

// Decrypts and deobfuscates a container into mapping JSON (UTF-8, compact).
// `password` is only used for password-protected containers; default-key
// containers ignore it.  Returns false and fills `error` when the container
// cannot be read (bad magic/version, wrong key, failed MAC, corrupt payload).
bool decodeAvroEncoContainer(const unsigned char* data, std::size_t size,
                             const std::string& password,
                             std::string& utf8Json, std::string& error);

} // namespace avro
