// avroenco_reader.cpp - implementation of the AvroShield container reader.
//
// Stage by stage, mirroring the original engine:
//
//   1. header check + key schedule   (ShieldOpenContainer)
//   2. HMAC-SHA512 verdict + AES-256-GCM decrypt
//   3. zlib inflate -> 'AVROBC' bytecode
//   4. bytecode parse -> node tree   (AvroShieldParseBytecode)
//   5. deobfuscate                    (AvroShieldDeobfuscateEx, no comments)
//   6. serialize to mapping JSON      (AvroShieldNodeToJSON)
//
// SHA-256 is implemented here rather than taken from a provider because the
// obfuscation keystream calls it once per 32 bytes of decoded text - tens of
// thousands of times per container - and a per-call provider round trip makes
// that visibly slow.  Everything that runs once per load (SHA-512,
// HMAC-SHA512, AES-256-GCM, and PBKDF2 for password containers) goes through
// CNG/BCrypt instead of hand-rolled arithmetic.  zlib comes from the toolchain.

#include "avroenco_reader.h"

#include <windows.h>
#include <bcrypt.h>
#include <zlib.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <map>
#include <set>
#include <vector>

namespace avro {
namespace {

using Bytes = std::vector<unsigned char>;

// ---------------------------------------------------------------------------
// Byte helpers
// ---------------------------------------------------------------------------

unsigned be16(const unsigned char* p) {
    return (static_cast<unsigned>(p[0]) << 8) | p[1];
}

uint32_t be32(const unsigned char* p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | static_cast<uint32_t>(p[3]);
}

Bytes fromAscii(const char* s) {
    return Bytes(s, s + std::strlen(s));
}

Bytes concat(const Bytes& a, const Bytes& b) {
    Bytes out(a);
    out.insert(out.end(), b.begin(), b.end());
    return out;
}

bool constantTimeEqual(const Bytes& a, const Bytes& b) {
    unsigned diff = static_cast<unsigned>(a.size() ^ b.size());
    const size_t n = std::min(a.size(), b.size());
    for (size_t i = 0; i < n; ++i)
        diff |= static_cast<unsigned>(a[i] ^ b[i]);
    return diff == 0;
}

// ---------------------------------------------------------------------------
// SHA-256 (FIPS 180-4)
// ---------------------------------------------------------------------------

class Sha256 {
public:
    Sha256() { reset(); }

    void reset() {
        h_[0] = 0x6a09e667u; h_[1] = 0xbb67ae85u; h_[2] = 0x3c6ef372u;
        h_[3] = 0xa54ff53au; h_[4] = 0x510e527fu; h_[5] = 0x9b05688cu;
        h_[6] = 0x1f83d9abu; h_[7] = 0x5be0cd19u;
        total_ = 0;
        bufLen_ = 0;
    }

    void update(const void* data, size_t n) {
        const unsigned char* p = static_cast<const unsigned char*>(data);
        total_ += n;
        while (n > 0) {
            const size_t take = std::min<size_t>(n, 64 - bufLen_);
            std::memcpy(buf_ + bufLen_, p, take);
            bufLen_ += take;
            p += take;
            n -= take;
            if (bufLen_ == 64) {
                block(buf_);
                bufLen_ = 0;
            }
        }
    }

    void finish(unsigned char out[32]) {
        const uint64_t bits = total_ * 8;
        const unsigned char one = 0x80;
        update(&one, 1);
        const unsigned char zero = 0;
        while (bufLen_ != 56)
            update(&zero, 1);
        unsigned char lenBytes[8];
        for (int i = 0; i < 8; ++i)
            lenBytes[i] = static_cast<unsigned char>(bits >> (56 - 8 * i));
        update(lenBytes, 8);
        for (int i = 0; i < 8; ++i) {
            out[i * 4 + 0] = static_cast<unsigned char>(h_[i] >> 24);
            out[i * 4 + 1] = static_cast<unsigned char>(h_[i] >> 16);
            out[i * 4 + 2] = static_cast<unsigned char>(h_[i] >> 8);
            out[i * 4 + 3] = static_cast<unsigned char>(h_[i]);
        }
    }

private:
    static uint32_t rotr(uint32_t v, int n) { return (v >> n) | (v << (32 - n)); }

    void block(const unsigned char* p) {
        static const uint32_t K[64] = {
            0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu,
            0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u, 0xd807aa98u, 0x12835b01u,
            0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u,
            0xc19bf174u, 0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu,
            0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau, 0x983e5152u,
            0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u,
            0x06ca6351u, 0x14292967u, 0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu,
            0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
            0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u,
            0xd6990624u, 0xf40e3585u, 0x106aa070u, 0x19a4c116u, 0x1e376c08u,
            0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu,
            0x682e6ff3u, 0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u,
            0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u};

        uint32_t w[64];
        for (int i = 0; i < 16; ++i)
            w[i] = (static_cast<uint32_t>(p[i * 4]) << 24) |
                   (static_cast<uint32_t>(p[i * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(p[i * 4 + 2]) << 8) |
                   static_cast<uint32_t>(p[i * 4 + 3]);
        for (int i = 16; i < 64; ++i) {
            const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }

        uint32_t a = h_[0], b = h_[1], c = h_[2], d = h_[3];
        uint32_t e = h_[4], f = h_[5], g = h_[6], h = h_[7];
        for (int i = 0; i < 64; ++i) {
            const uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            const uint32_t ch = (e & f) ^ (~e & g);
            const uint32_t t1 = h + S1 + ch + K[i] + w[i];
            const uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            const uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
            const uint32_t t2 = S0 + maj;
            h = g; g = f; f = e; e = d + t1;
            d = c; c = b; b = a; a = t1 + t2;
        }
        h_[0] += a; h_[1] += b; h_[2] += c; h_[3] += d;
        h_[4] += e; h_[5] += f; h_[6] += g; h_[7] += h;
    }

    uint32_t h_[8];
    uint64_t total_;
    size_t bufLen_;
    unsigned char buf_[64];
};

Bytes sha256(const Bytes& data) {
    Sha256 h;
    if (!data.empty())
        h.update(data.data(), data.size());
    Bytes out(32);
    h.finish(out.data());
    return out;
}

// ---------------------------------------------------------------------------
// HMAC-SHA256 / HKDF-SHA256 / PBKDF2-HMAC-SHA256
// ---------------------------------------------------------------------------

Bytes hmacSha256(const Bytes& key, const Bytes& msg) {
    Bytes k = key;
    if (k.size() > 64)
        k = sha256(k);
    k.resize(64, 0);
    Bytes inner(64);
    Bytes outer(64);
    for (size_t i = 0; i < 64; ++i) {
        inner[i] = static_cast<unsigned char>(k[i] ^ 0x36);
        outer[i] = static_cast<unsigned char>(k[i] ^ 0x5c);
    }
    return sha256(concat(outer, sha256(concat(inner, msg))));
}

// RFC 5869 2.2 - an empty salt becomes HashLen zero bytes.
Bytes hkdfExtractSha256(const Bytes& salt, const Bytes& ikm) {
    if (salt.empty())
        return hmacSha256(Bytes(32, 0), ikm);
    return hmacSha256(salt, ikm);
}

// RFC 5869 2.3
Bytes hkdfExpandSha256(const Bytes& prk, const Bytes& info, int len) {
    Bytes out;
    out.reserve(static_cast<size_t>(len));
    Bytes t;
    for (int counter = 1; static_cast<int>(out.size()) < len && counter <= 255; ++counter) {
        Bytes block = t;
        block.insert(block.end(), info.begin(), info.end());
        block.push_back(static_cast<unsigned char>(counter));
        t = hmacSha256(prk, block);
        const size_t take = std::min<size_t>(t.size(), static_cast<size_t>(len) - out.size());
        out.insert(out.end(), t.begin(), t.begin() + static_cast<long>(take));
    }
    return out;
}

Bytes hkdfSha256(const Bytes& ikm, const Bytes& salt, const Bytes& info, int len) {
    return hkdfExpandSha256(hkdfExtractSha256(salt, ikm), info, len);
}

Bytes pbkdf2HmacSha256(const Bytes& password, const Bytes& salt, int iterations, int dkLen) {
    Bytes out;
    out.reserve(static_cast<size_t>(dkLen));
    Bytes saltBlock;
    for (uint32_t blockNo = 1; static_cast<int>(out.size()) < dkLen; ++blockNo) {
        saltBlock = salt;
        saltBlock.push_back(static_cast<unsigned char>(blockNo >> 24));
        saltBlock.push_back(static_cast<unsigned char>(blockNo >> 16));
        saltBlock.push_back(static_cast<unsigned char>(blockNo >> 8));
        saltBlock.push_back(static_cast<unsigned char>(blockNo));
        Bytes u = hmacSha256(password, saltBlock);
        Bytes acc = u;
        for (int i = 2; i <= iterations; ++i) {
            u = hmacSha256(password, u);
            for (size_t j = 0; j < acc.size(); ++j)
                acc[j] = static_cast<unsigned char>(acc[j] ^ u[j]);
        }
        const size_t take = std::min<size_t>(acc.size(), static_cast<size_t>(dkLen) - out.size());
        out.insert(out.end(), acc.begin(), acc.begin() + static_cast<long>(take));
    }
    return out;
}

// ---------------------------------------------------------------------------
// CNG/BCrypt primitives (SHA-512, HMAC-SHA512, AES-256-GCM)
// ---------------------------------------------------------------------------

bool bcryptHash(const wchar_t* algorithm, const void* secret, size_t secretLen,
                const Bytes& input, Bytes& out, bool hmac) {
    BCRYPT_ALG_HANDLE alg = nullptr;
    if (BCryptOpenAlgorithmProvider(&alg, algorithm, nullptr,
                                    hmac ? BCRYPT_ALG_HANDLE_HMAC_FLAG : 0) < 0)
        return false;
    DWORD hashLen = 0;
    DWORD written = 0;
    if (BCryptGetProperty(alg, BCRYPT_HASH_LENGTH,
                          reinterpret_cast<PUCHAR>(&hashLen), sizeof(hashLen),
                          &written, 0) < 0) {
        BCryptCloseAlgorithmProvider(alg, 0);
        return false;
    }
    out.resize(hashLen);
    const NTSTATUS st = BCryptHash(
        alg, const_cast<PUCHAR>(static_cast<const unsigned char*>(secret)),
        static_cast<ULONG>(secretLen),
        const_cast<PUCHAR>(input.empty() ? nullptr : input.data()),
        static_cast<ULONG>(input.size()), out.data(), hashLen);
    BCryptCloseAlgorithmProvider(alg, 0);
    return st >= 0;
}

Bytes sha512(const Bytes& data) {
    Bytes out;
    if (!bcryptHash(BCRYPT_SHA512_ALGORITHM, nullptr, 0, data, out, false))
        out.clear();
    return out;
}

Bytes hmacSha512(const Bytes& key, const Bytes& msg) {
    Bytes out;
    if (!bcryptHash(BCRYPT_SHA512_ALGORITHM, key.data(), key.size(), msg, out, true))
        out.clear();
    return out;
}

// AES-256 block encryption through CNG (ECB; GCM is built on top of it below),
// plus the GCM mode itself.
//
// CNG's own GCM entry point only accepts a 12-byte nonce (a 16-byte nonce is
// rejected with STATUS_INVALID_PARAMETER, verified on this toolchain), while
// the container stores a 16-byte IV.  The mode is therefore implemented here
// on top of the provider's AES block function, following NIST SP 800-38D.
class Aes256Ecb {
public:
    bool init(const Bytes& key) {
        if (BCryptOpenAlgorithmProvider(&alg_, BCRYPT_AES_ALGORITHM, nullptr, 0) < 0)
            return false;
        if (BCryptSetProperty(alg_, BCRYPT_CHAINING_MODE,
                              reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(BCRYPT_CHAIN_MODE_ECB)),
                              sizeof(BCRYPT_CHAIN_MODE_ECB), 0) < 0)
            return false;
        DWORD objLen = 0;
        DWORD written = 0;
        if (BCryptGetProperty(alg_, BCRYPT_OBJECT_LENGTH,
                              reinterpret_cast<PUCHAR>(&objLen), sizeof(objLen),
                              &written, 0) < 0)
            return false;
        keyObj_.assign(objLen, 0);
        if (BCryptGenerateSymmetricKey(alg_, &key_, keyObj_.data(), objLen,
                                       const_cast<PUCHAR>(key.data()),
                                       static_cast<ULONG>(key.size()), 0) < 0)
            return false;
        return true;
    }

    ~Aes256Ecb() {
        if (key_)
            BCryptDestroyKey(key_);
        if (alg_)
            BCryptCloseAlgorithmProvider(alg_, 0);
    }

    bool encryptBlock(const unsigned char in[16], unsigned char out[16]) {
        ULONG done = 0;
        return BCryptEncrypt(key_, const_cast<PUCHAR>(in), 16, nullptr, nullptr, 0,
                             out, 16, &done, 0) >= 0 && done == 16;
    }

private:
    BCRYPT_ALG_HANDLE alg_ = nullptr;
    BCRYPT_KEY_HANDLE key_ = nullptr;
    Bytes keyObj_;
};

void ghashMul(const unsigned char X[16], const unsigned char Y[16],
              unsigned char out[16]) {
    unsigned char v[16];
    std::memcpy(v, X, 16);
    std::memset(out, 0, 16);
    for (int i = 0; i < 128; ++i) {
        if ((Y[i >> 3] >> (7 - (i & 7))) & 1) {
            for (int j = 0; j < 16; ++j)
                out[j] = static_cast<unsigned char>(out[j] ^ v[j]);
        }
        const unsigned char lsb = static_cast<unsigned char>(v[15] & 1);
        for (int j = 15; j > 0; --j)
            v[j] = static_cast<unsigned char>((v[j] >> 1) | (v[j - 1] << 7));
        v[0] >>= 1;
        if (lsb)
            v[0] = static_cast<unsigned char>(v[0] ^ 0xE1);
    }
}

// GHASH over a byte range whose length is not necessarily a multiple of 16.
void ghashBytes(const unsigned char H[16], const unsigned char* data, size_t len,
                unsigned char out[16]) {
    unsigned char block[16];
    for (size_t off = 0; off < len; off += 16) {
        std::memset(block, 0, sizeof(block));
        const size_t take = std::min<size_t>(16, len - off);
        std::memcpy(block, data + off, take);
        for (int i = 0; i < 16; ++i)
            out[i] = static_cast<unsigned char>(out[i] ^ block[i]);
        ghashMul(out, H, out);
    }
}

void increment32(unsigned char block[16]) {
    for (int i = 15; i >= 12; --i) {
        block[i] = static_cast<unsigned char>(block[i] + 1);
        if (block[i] != 0)
            break;
    }
}

// AES-256-GCM open.  `input` is ciphertext followed by the 16-byte tag, which
// is how the container stores them.  The tag is verified; AAD is empty.
bool aes256GcmDecrypt(const Bytes& input, const Bytes& key, const Bytes& nonce,
                      Bytes& plain) {
    if (input.size() < 16 || key.size() != 32 || nonce.size() < 1)
        return false;
    const size_t ctLen = input.size() - 16;
    const unsigned char* cipher = input.data();
    const unsigned char* tag = input.data() + ctLen;

    Aes256Ecb aes;
    if (!aes.init(key))
        return false;

    unsigned char H[16];
    const unsigned char zeroBlock[16] = {0};
    if (!aes.encryptBlock(zeroBlock, H))
        return false;

    unsigned char j0[16];
    if (nonce.size() == 12) {
        std::memcpy(j0, nonce.data(), 12);
        j0[12] = 0; j0[13] = 0; j0[14] = 0; j0[15] = 1;
    } else {
        // J0 = GHASH_H(IV || 0^(s+64) || [len(IV)]_64), SP 800-38D 7.1 step 2.
        Bytes ghashInput(nonce.begin(), nonce.end());
        while (ghashInput.size() % 16 != 0)
            ghashInput.push_back(0);
        for (int i = 0; i < 8; ++i)
            ghashInput.push_back(0);
        const uint64_t bits = static_cast<uint64_t>(nonce.size()) * 8;
        for (int i = 0; i < 8; ++i)
            ghashInput.push_back(static_cast<unsigned char>(bits >> (56 - 8 * i)));
        std::memset(j0, 0, sizeof(j0));
        ghashBytes(H, ghashInput.data(), ghashInput.size(), j0);
    }

    // CTR keystream starting at inc32(J0).
    plain.assign(ctLen, 0);
    unsigned char counter[16];
    std::memcpy(counter, j0, 16);
    unsigned char keystream[16];
    for (size_t off = 0; off < ctLen; off += 16) {
        increment32(counter);
        if (!aes.encryptBlock(counter, keystream))
            return false;
        const size_t take = std::min<size_t>(16, ctLen - off);
        for (size_t i = 0; i < take; ++i)
            plain[off + i] = static_cast<unsigned char>(cipher[off + i] ^ keystream[i]);
    }

    // Tag = GHASH_H(A || 0^v || C || 0^u || [len(A)]_64 || [len(C)]_64) ^ E_K(J0)
    unsigned char s[16] = {0};
    ghashBytes(H, cipher, ctLen, s);
    unsigned char lengths[16] = {0};
    const uint64_t cbits = static_cast<uint64_t>(ctLen) * 8;
    for (int i = 0; i < 8; ++i)
        lengths[8 + i] = static_cast<unsigned char>(cbits >> (56 - 8 * i));
    for (int i = 0; i < 16; ++i)
        s[i] = static_cast<unsigned char>(s[i] ^ lengths[i]);
    ghashMul(s, H, s);

    unsigned char ekJ0[16];
    if (!aes.encryptBlock(j0, ekJ0))
        return false;
    Bytes computedTag(16);
    for (int i = 0; i < 16; ++i)
        computedTag[i] = static_cast<unsigned char>(s[i] ^ ekJ0[i]);

    if (!constantTimeEqual(computedTag, Bytes(tag, tag + 16))) {
        Bytes().swap(plain);
        return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// zlib inflate (the container stores a standard zlib stream)
// ---------------------------------------------------------------------------

bool inflateBytes(const Bytes& in, Bytes& out) {
    z_stream zs;
    std::memset(&zs, 0, sizeof(zs));
    if (inflateInit(&zs) != Z_OK)
        return false;
    zs.next_in = const_cast<Bytef*>(in.data());
    zs.avail_in = static_cast<uInt>(in.size());
    out.assign(in.size() * 4 + 4096, 0);
    int ret = Z_OK;
    for (;;) {
        if (zs.total_out == out.size())
            out.resize(out.size() * 2);
        zs.next_out = out.data() + zs.total_out;
        zs.avail_out = static_cast<uInt>(out.size() - zs.total_out);
        ret = inflate(&zs, Z_NO_FLUSH);
        if (ret == Z_STREAM_END)
            break;
        if (ret != Z_OK || (zs.avail_in == 0 && zs.avail_out != 0)) {
            inflateEnd(&zs);
            return false;
        }
    }
    out.resize(zs.total_out);
    inflateEnd(&zs);
    return true;
}

// ---------------------------------------------------------------------------
// Embedded default-key secret (port of uAvroShieldSecret)
//
// The IKM is a 44-byte secret masked with a rotl-indexed xorshift32 keystream,
// so a string dump of the binary shows only random-looking tables.
// ---------------------------------------------------------------------------

const unsigned char kSecretBlob[48] = {
    0x69, 0x4E, 0xE0, 0x42, 0xC6, 0x73, 0x63, 0x1E, 0x8D, 0xF2, 0xED, 0xC2,
    0xAE, 0xBA, 0x7B, 0x5F, 0x97, 0xB6, 0x91, 0x8C, 0x9D, 0xE9, 0x37, 0xA2,
    0x3D, 0xAB, 0xCD, 0xF7, 0x3A, 0x80, 0xC3, 0x6E, 0xAA, 0x63, 0x37, 0x02,
    0x43, 0x40, 0x57, 0xE9, 0x2F, 0x02, 0xB1, 0xB6, 0x8D, 0xBA, 0x4A, 0x06};
const uint32_t kSecretSeed = 0x5F3A17C9;
const int kSecretLen = 44;

uint32_t secretXorShift32(uint32_t state) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

unsigned char secretRotl8(unsigned char value, int rot) {
    rot &= 7;
    if (rot == 0)
        return value;
    return static_cast<unsigned char>((value << rot) | (value >> (8 - rot)));
}

Bytes shieldSecretIkm() {
    Bytes out;
    uint32_t state = kSecretSeed;
    for (int i = 0; i < static_cast<int>(sizeof(kSecretBlob)); ++i) {
        if ((i % 4) == 0)
            state = secretXorShift32(state);
        const unsigned char plain = static_cast<unsigned char>(
            kSecretBlob[i] ^ secretRotl8(static_cast<unsigned char>(state >> (8 * (i % 4))), i));
        if (plain == 0)
            break;
        out.push_back(plain);
    }
    if (out.size() > static_cast<size_t>(kSecretLen))
        out.resize(kSecretLen);
    return out;
}

// ---------------------------------------------------------------------------
// Machine identity: SHA-256(MachineGuid UTF-8)[:16], MAC fallback
// ---------------------------------------------------------------------------

Bytes machineId() {
    std::string guid;
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Cryptography", 0,
                      KEY_READ | KEY_WOW64_64KEY, &key) == ERROR_SUCCESS) {
        wchar_t buf[128] = {0};
        DWORD bufSize = sizeof(buf) - sizeof(wchar_t);
        DWORD type = 0;
        if (RegQueryValueExW(key, L"MachineGuid", nullptr, &type,
                             reinterpret_cast<LPBYTE>(buf), &bufSize) == ERROR_SUCCESS) {
            // MachineGuid is ASCII; the GUID is taken up to the terminator,
            // exactly like the WideChar buffer cast in the original engine.
            const std::wstring w(buf);
            guid.assign(w.begin(), w.end());
        }
        RegCloseKey(key);
    }
    if (guid.empty())
        guid = ""; // no fallback: portable containers never need it
    Bytes out = sha256(Bytes(reinterpret_cast<const unsigned char*>(guid.data()),
                            reinterpret_cast<const unsigned char*>(guid.data()) + guid.size()));
    out.resize(16);
    return out;
}

// ---------------------------------------------------------------------------
// Container
// ---------------------------------------------------------------------------

const int kHeaderSize = 58;
const int kTrailerSize = 80;
const int kHmacSize = 64;

const unsigned char kShieldMagic[8] = {'A', 'V', 'R', 'O', 'S', 'H', 'L', 'D'};

// Bytecode
const int kBcHeaderSize = 23;
const char kBcXorSeed[] = "AvroShieldBytecodeXORv1";

// Node types
enum : unsigned char {
    kTypeNull = 0x00,
    kTypeString = 0x01,
    kTypeNumber = 0x02,
    kTypeBoolean = 0x03,
    kTypeArray = 0x04,
    kTypeObject = 0x05
};

// Obfuscation
const char kMetaKey[] = "_obf_meta";
const char kObfInfoMeta[] = "AvroShield-v3/obf-meta";
const char kObfInfoComments[] = "AvroShield-v3/comments";

struct Node {
    enum class Kind { Null, Bool, Int, Float, String, Array, Object };
    Kind kind = Kind::Null;
    bool boolVal = false;
    long long intVal = 0;
    double floatVal = 0;
    std::string strVal;              // UTF-8
    std::vector<Node> items;         // array elements / object values
    std::vector<std::string> keys;   // object keys, parallel to items
};

// Base64 (standard alphabet, padding optional on decode).
const char* kBase64Alphabet =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

bool base64Decode(const std::string& in, Bytes& out) {
    int table[256];
    for (int i = 0; i < 256; ++i)
        table[i] = -1;
    for (int i = 0; i < 64; ++i)
        table[static_cast<unsigned char>(kBase64Alphabet[i])] = i;
    out.clear();
    int buffer = 0;
    int bits = 0;
    for (unsigned char c : in) {
        if (c == '=' || c == '\n' || c == '\r')
            continue;
        const int v = table[c];
        if (v < 0)
            return false;
        buffer = (buffer << 6) | v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out.push_back(static_cast<unsigned char>((buffer >> bits) & 0xFF));
        }
    }
    return true;
}

// Bytecode string mask: keystream = SHA-256(seed || BE32(len)), repeated.
Bytes bcMaskString(const Bytes& data) {
    Bytes lenBytes(4);
    const uint32_t len = static_cast<uint32_t>(data.size());
    lenBytes[0] = static_cast<unsigned char>(len >> 24);
    lenBytes[1] = static_cast<unsigned char>(len >> 16);
    lenBytes[2] = static_cast<unsigned char>(len >> 8);
    lenBytes[3] = static_cast<unsigned char>(len);
    const Bytes key = sha256(concat(fromAscii(kBcXorSeed), lenBytes));
    Bytes out(data.size());
    for (size_t i = 0; i < data.size(); ++i)
        out[i] = static_cast<unsigned char>(data[i] ^ key[i % 32]);
    return out;
}

// Obfuscation codec: XOR a Base64 token with the positional keystream.
// key = SHA-256("str\0" || seed || "\0" || ctx), stream = SHA-256(key || BE32(i)).
Bytes obfCodec(const Bytes& seed, const Bytes& data, const std::string& ctx) {
    Bytes material = {'s', 't', 'r', 0};
    material.insert(material.end(), seed.begin(), seed.end());
    material.push_back(0);
    material.insert(material.end(), ctx.begin(), ctx.end());
    const Bytes key = sha256(material);

    Bytes out(data.size());
    Bytes counterBytes(4);
    size_t pos = 0;
    uint32_t counter = 0;
    while (pos < data.size()) {
        counterBytes[0] = static_cast<unsigned char>(counter >> 24);
        counterBytes[1] = static_cast<unsigned char>(counter >> 16);
        counterBytes[2] = static_cast<unsigned char>(counter >> 8);
        counterBytes[3] = static_cast<unsigned char>(counter);
        const Bytes block = sha256(concat(key, counterBytes));
        for (size_t i = 0; i < block.size() && pos < data.size(); ++i, ++pos)
            out[pos] = static_cast<unsigned char>(data[pos] ^ block[i]);
        ++counter;
    }
    return out;
}

std::string childCtx(const std::string& ctx, const std::string& name) {
    if (ctx.empty())
        return name;
    return ctx + "/" + name;
}

std::string indexCtx(const std::string& ctx, int index) {
    return ctx + "#" + std::to_string(index);
}

bool isCommentField(const std::string& name) {
    return name == "Comment" || name == "comment" || name == "_comment";
}

// ---------------------------------------------------------------------------
// Minimal JSON reader (metadata blob + node serialization)
// ---------------------------------------------------------------------------

class JsonParser {
public:
    explicit JsonParser(const std::string& text) : s_(text) {}

    bool parse(Node& out) {
        skipWs();
        if (!parseValue(out))
            return false;
        skipWs();
        return pos_ >= s_.size();
    }

private:
    void skipWs() {
        while (pos_ < s_.size()) {
            const char c = s_[pos_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++pos_;
            } else {
                break;
            }
        }
    }

    bool parseValue(Node& out) {
        if (pos_ >= s_.size())
            return false;
        const char c = s_[pos_];
        if (c == '{')
            return parseObject(out);
        if (c == '[')
            return parseArray(out);
        if (c == '"') {
            out.kind = Node::Kind::String;
            return parseString(out.strVal);
        }
        if (s_.compare(pos_, 4, "true") == 0) {
            out.kind = Node::Kind::Bool;
            out.boolVal = true;
            pos_ += 4;
            return true;
        }
        if (s_.compare(pos_, 5, "false") == 0) {
            out.kind = Node::Kind::Bool;
            out.boolVal = false;
            pos_ += 5;
            return true;
        }
        if (s_.compare(pos_, 4, "null") == 0) {
            out.kind = Node::Kind::Null;
            pos_ += 4;
            return true;
        }
        return parseNumber(out);
    }

    bool parseObject(Node& out) {
        out.kind = Node::Kind::Object;
        ++pos_; // '{'
        skipWs();
        if (pos_ < s_.size() && s_[pos_] == '}') {
            ++pos_;
            return true;
        }
        for (;;) {
            skipWs();
            std::string key;
            if (!parseString(key))
                return false;
            skipWs();
            if (pos_ >= s_.size() || s_[pos_] != ':')
                return false;
            ++pos_;
            skipWs();
            Node child;
            if (!parseValue(child))
                return false;
            out.keys.push_back(key);
            out.items.push_back(std::move(child));
            skipWs();
            if (pos_ < s_.size() && s_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (pos_ < s_.size() && s_[pos_] == '}') {
                ++pos_;
                return true;
            }
            return false;
        }
    }

    bool parseArray(Node& out) {
        out.kind = Node::Kind::Array;
        ++pos_; // '['
        skipWs();
        if (pos_ < s_.size() && s_[pos_] == ']') {
            ++pos_;
            return true;
        }
        for (;;) {
            skipWs();
            Node child;
            if (!parseValue(child))
                return false;
            out.items.push_back(std::move(child));
            skipWs();
            if (pos_ < s_.size() && s_[pos_] == ',') {
                ++pos_;
                continue;
            }
            if (pos_ < s_.size() && s_[pos_] == ']') {
                ++pos_;
                return true;
            }
            return false;
        }
    }

    bool parseString(std::string& out) {
        if (pos_ >= s_.size() || s_[pos_] != '"')
            return false;
        ++pos_;
        out.clear();
        while (pos_ < s_.size()) {
            const char c = s_[pos_++];
            if (c == '"')
                return true;
            if (c != '\\') {
                out.push_back(c);
                continue;
            }
            if (pos_ >= s_.size())
                return false;
            const char esc = s_[pos_++];
            switch (esc) {
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                case '/': out.push_back('/'); break;
                case 'b': out.push_back('\b'); break;
                case 'f': out.push_back('\f'); break;
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case 'u': {
                    if (pos_ + 4 > s_.size())
                        return false;
                    unsigned cp = 0;
                    for (int i = 0; i < 4; ++i) {
                        const char h = s_[pos_++];
                        cp <<= 4;
                        if (h >= '0' && h <= '9') cp |= static_cast<unsigned>(h - '0');
                        else if (h >= 'a' && h <= 'f') cp |= static_cast<unsigned>(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') cp |= static_cast<unsigned>(h - 'A' + 10);
                        else return false;
                    }
                    appendUtf8(out, cp);
                    break;
                }
                default:
                    return false;
            }
        }
        return false;
    }

    static void appendUtf8(std::string& out, unsigned cp) {
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }

    bool parseNumber(Node& out) {
        const size_t start = pos_;
        while (pos_ < s_.size() && std::strchr("-+.eE0123456789", s_[pos_]) != nullptr)
            ++pos_;
        if (pos_ == start)
            return false;
        const std::string token = s_.substr(start, pos_ - start);
        const bool isFloat = token.find_first_of(".eE") != std::string::npos;
        try {
            if (isFloat) {
                out.kind = Node::Kind::Float;
                out.floatVal = std::stod(token);
            } else {
                out.kind = Node::Kind::Int;
                out.intVal = std::stoll(token);
            }
        } catch (...) {
            return false;
        }
        return true;
    }

    const std::string& s_;
    size_t pos_ = 0;
};

void jsonEscape(const std::string& in, std::string& out) {
    static const char* kHex = "0123456789abcdef";
    for (unsigned char c : in) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    out += "\\u00";
                    out.push_back(kHex[(c >> 4) & 0xF]);
                    out.push_back(kHex[c & 0xF]);
                } else {
                    out.push_back(static_cast<char>(c));
                }
        }
    }
}

void appendNumber(const Node& node, std::string& out) {
    char buf[64];
    if (node.kind == Node::Kind::Int) {
        std::snprintf(buf, sizeof(buf), "%lld", node.intVal);
        out += buf;
    } else {
        std::snprintf(buf, sizeof(buf), "%.17g", node.floatVal);
        out += buf;
    }
}

void nodeToJson(const Node& node, std::string& out) {
    switch (node.kind) {
        case Node::Kind::Null:
            out += "null";
            break;
        case Node::Kind::Bool:
            out += node.boolVal ? "true" : "false";
            break;
        case Node::Kind::Int:
        case Node::Kind::Float:
            appendNumber(node, out);
            break;
        case Node::Kind::String:
            out.push_back('"');
            jsonEscape(node.strVal, out);
            out.push_back('"');
            break;
        case Node::Kind::Array:
            out.push_back('[');
            for (size_t i = 0; i < node.items.size(); ++i) {
                if (i)
                    out.push_back(',');
                nodeToJson(node.items[i], out);
            }
            out.push_back(']');
            break;
        case Node::Kind::Object:
            out.push_back('{');
            for (size_t i = 0; i < node.items.size(); ++i) {
                if (i)
                    out.push_back(',');
                out.push_back('"');
                jsonEscape(node.keys[i], out);
                out += "\":";
                nodeToJson(node.items[i], out);
            }
            out.push_back('}');
            break;
    }
}

// ---------------------------------------------------------------------------
// Bytecode parsing ('AVROBC' v1)
// ---------------------------------------------------------------------------

bool parseNode(const unsigned char* data, size_t size, size_t& off, Node& out);

bool parseBytecode(const Bytes& bc, Node& root, std::string& error) {
    if (bc.size() < static_cast<size_t>(kBcHeaderSize) + 32) {
        error = "bytecode too short";
        return false;
    }
    if (std::memcmp(bc.data(), "AVROBC", 6) != 0) {
        error = "bytecode magic missing";
        return false;
    }
    if (bc[6] != 1) {
        error = "unsupported bytecode version";
        return false;
    }
    Bytes body(bc.begin(), bc.end() - 32);
    if (!constantTimeEqual(sha256(body), Bytes(bc.end() - 32, bc.end()))) {
        error = "bytecode checksum mismatch";
        return false;
    }

    const uint32_t typeCount = be32(bc.data() + 7);
    const uint32_t entryCount = be32(bc.data() + 11);
    size_t off = kBcHeaderSize;
    for (uint32_t i = 0; i < typeCount; ++i) {
        ++off;
        if (off + 2 > bc.size()) {
            error = "bytecode type table truncated";
            return false;
        }
        off += 2 + be16(bc.data() + off);
    }

    root.kind = Node::Kind::Object;
    for (uint32_t i = 0; i < entryCount; ++i) {
        const size_t entryStart = off;
        if (off + 2 > bc.size()) {
            error = "bytecode entry truncated";
            return false;
        }
        const unsigned keyLen = be16(bc.data() + off);
        off += 2;
        if (off + keyLen > bc.size()) {
            error = "bytecode entry key truncated";
            return false;
        }
        const std::string key(reinterpret_cast<const char*>(bc.data() + off), keyLen);
        off += keyLen;
        if (off + 4 > bc.size()) {
            error = "bytecode entry length truncated";
            return false;
        }
        const uint32_t nodeLen = be32(bc.data() + off);
        off += 4;
        if (off + nodeLen > bc.size()) {
            error = "bytecode entry node truncated";
            return false;
        }
        const unsigned char* nodeBytes = bc.data() + off;
        off += nodeLen;
        if (off + 4 > bc.size()) {
            error = "bytecode entry checksum truncated";
            return false;
        }
        const uint32_t storedCrc = be32(bc.data() + off);
        off += 4;
        const uint32_t crc = static_cast<uint32_t>(
            ::crc32(0, bc.data() + entryStart, static_cast<uInt>(off - 4 - entryStart)));
        if (crc != storedCrc) {
            error = "bytecode entry checksum mismatch";
            return false;
        }

        Node child;
        size_t nodeOff = 0;
        if (!parseNode(nodeBytes, nodeLen, nodeOff, child)) {
            error = "malformed bytecode node";
            return false;
        }
        root.keys.push_back(key);
        root.items.push_back(std::move(child));
    }

    if (off != bc.size() - 32) {
        error = "trailing bytecode data";
        return false;
    }
    return true;
}

bool parseNode(const unsigned char* data, size_t size, size_t& off, Node& out) {
    if (off >= size)
        return false;
    const unsigned char type = data[off++];
    switch (type) {
        case kTypeNull:
            out.kind = Node::Kind::Null;
            return true;
        case kTypeBoolean:
            if (off >= size)
                return false;
            out.kind = Node::Kind::Bool;
            out.boolVal = data[off] == 0x01;
            ++off;
            return true;
        case kTypeNumber: {
            if (off + 9 > size)
                return false;
            unsigned long long bits = 0;
            for (int i = 0; i < 8; ++i)
                bits = (bits << 8) | data[off + 1 + i];
            if (data[off] == 1) {
                out.kind = Node::Kind::Int;
                out.intVal = static_cast<long long>(bits);
            } else {
                out.kind = Node::Kind::Float;
                double d = 0;
                std::memcpy(&d, &bits, sizeof(d));
                out.floatVal = d;
            }
            off += 9;
            return true;
        }
        case kTypeString: {
            if (off + 4 > size)
                return false;
            const uint32_t len = be32(data + off);
            off += 4;
            if (off + len > size)
                return false;
            const Bytes masked(data + off, data + off + len);
            off += len;
            const Bytes plain = bcMaskString(masked);
            out.kind = Node::Kind::String;
            out.strVal.assign(plain.begin(), plain.end());
            return true;
        }
        case kTypeArray: {
            if (off + 4 > size)
                return false;
            const uint32_t count = be32(data + off);
            off += 4;
            out.kind = Node::Kind::Array;
            for (uint32_t i = 0; i < count; ++i) {
                Node child;
                if (!parseNode(data, size, off, child))
                    return false;
                out.items.push_back(std::move(child));
            }
            return true;
        }
        case kTypeObject: {
            if (off + 4 > size)
                return false;
            const uint32_t count = be32(data + off);
            off += 4;
            out.kind = Node::Kind::Object;
            for (uint32_t i = 0; i < count; ++i) {
                if (off + 2 > size)
                    return false;
                const unsigned keyLen = be16(data + off);
                off += 2;
                if (off + keyLen > size)
                    return false;
                out.keys.push_back(
                    std::string(reinterpret_cast<const char*>(data + off), keyLen));
                off += keyLen;
                Node child;
                if (!parseNode(data, size, off, child))
                    return false;
                out.items.push_back(std::move(child));
            }
            return true;
        }
        default:
            return false;
    }
}

// ---------------------------------------------------------------------------
// Deobfuscation (format v3)
// ---------------------------------------------------------------------------

bool deobfValue(const Node& node, const std::string& ctx, const Bytes& seed,
                const Bytes& commentSeed, bool includeComments,
                bool commentDomain, const std::map<std::string, std::string>& rev,
                const std::set<std::string>& skip, Node& out) {
    Bytes commentSeedEff = commentSeed.empty() ? seed : commentSeed;

    switch (node.kind) {
        case Node::Kind::Object: {
            out.kind = Node::Kind::Object;
            for (size_t i = 0; i < node.items.size(); ++i) {
                const std::string& hashedKey = node.keys[i];
                if (skip.count(hashedKey))
                    continue;
                const auto it = rev.find(hashedKey);
                const std::string origKey = it == rev.end() ? hashedKey : it->second;
                const bool isComment = isCommentField(origKey);
                if (isComment && !includeComments)
                    continue; // dropped before any decode, like the runtime
                Bytes childSeed = seed;
                std::string childCtxPath = childCtx(ctx, hashedKey);
                if (isComment && commentDomain) {
                    childSeed = commentSeedEff;
                    childCtxPath = "cmt/" + childCtx(ctx, hashedKey);
                }
                Node child;
                if (!deobfValue(node.items[i], childCtxPath, childSeed,
                                commentSeedEff, includeComments, commentDomain,
                                rev, skip, child))
                    return false;
                out.keys.push_back(origKey);
                out.items.push_back(std::move(child));
            }
            return true;
        }
        case Node::Kind::Array: {
            out.kind = Node::Kind::Array;
            for (size_t i = 0; i < node.items.size(); ++i) {
                Node child;
                if (!deobfValue(node.items[i], indexCtx(ctx, static_cast<int>(i)),
                                seed, commentSeedEff, includeComments,
                                commentDomain, rev, skip, child))
                    return false;
                out.items.push_back(std::move(child));
            }
            return true;
        }
        case Node::Kind::String: {
            Bytes token;
            if (!base64Decode(node.strVal, token))
                return false;
            const Bytes plain = obfCodec(seed, token, ctx);
            out.kind = Node::Kind::String;
            out.strVal.assign(plain.begin(), plain.end());
            return true;
        }
        default:
            out = node;
            return true;
    }
}

bool deobfuscate(const Node& root, const Bytes& keyMeta, bool includeComments,
                 Node& out, std::string& error) {
    if (root.kind != Node::Kind::Object) {
        error = "payload root is not an object";
        return false;
    }
    size_t metaIndex = root.keys.size();
    for (size_t i = 0; i < root.keys.size(); ++i) {
        if (root.keys[i] == kMetaKey) {
            metaIndex = i;
            break;
        }
    }
    if (metaIndex == root.keys.size() || root.items[metaIndex].kind != Node::Kind::String) {
        error = "payload metadata missing";
        return false;
    }

    Bytes metaToken;
    if (!base64Decode(root.items[metaIndex].strVal, metaToken)) {
        error = "payload metadata is not base64";
        return false;
    }
    const Bytes metaPlain = obfCodec(keyMeta, metaToken, kMetaKey);
    const std::string metaJson(metaPlain.begin(), metaPlain.end());

    Node meta;
    JsonParser parser(metaJson);
    if (!parser.parse(meta) || meta.kind != Node::Kind::Object) {
        error = "payload metadata is not JSON";
        return false;
    }

    Bytes seed;
    std::map<std::string, std::string> rev;
    std::set<std::string> skip;
    skip.insert(kMetaKey);
    for (size_t i = 0; i < meta.items.size(); ++i) {
        if (meta.keys[i] == "seed" && meta.items[i].kind == Node::Kind::String) {
            if (!base64Decode(meta.items[i].strVal, seed))
                return false;
        } else if (meta.keys[i] == "key_map" && meta.items[i].kind == Node::Kind::Object) {
            const Node& kmap = meta.items[i];
            for (size_t k = 0; k < kmap.items.size(); ++k) {
                if (kmap.items[k].kind == Node::Kind::String)
                    rev[kmap.items[k].strVal] = kmap.keys[k]; // hashed -> original
            }
        } else if (meta.keys[i] == "dummies" && meta.items[i].kind == Node::Kind::Array) {
            for (const Node& dummy : meta.items[i].items) {
                if (dummy.kind == Node::Kind::String)
                    skip.insert(dummy.strVal);
            }
        }
    }
    if (seed.empty()) {
        error = "payload seed missing";
        return false;
    }

    // The comment key is derived from a developer IKM the runtime never holds,
    // so comments stay unreadable; they are dropped above and never decoded.
    return deobfValue(root, std::string(), seed, Bytes(), includeComments,
                      !keyMeta.empty(), rev, skip, out);
}

// ---------------------------------------------------------------------------
// Container open
// ---------------------------------------------------------------------------

struct OpenedContainer {
    Bytes bytecode;
    Bytes master;
    Bytes salt;
};

bool openContainer(const unsigned char* data, size_t size,
                   const std::string& password, OpenedContainer& out,
                   std::string& error) {
    if (size < static_cast<size_t>(kHeaderSize + kTrailerSize + 1)) {
        error = "container is too short";
        return false;
    }
    if (std::memcmp(data, kShieldMagic, 8) != 0) {
        error = "not an AvroShield container";
        return false;
    }
    const unsigned char version = data[8];
    if (version != 2 && version != 3) {
        error = "unsupported container version";
        return false;
    }

    const unsigned char flags = data[9];
    const Bytes salt(data + 10, data + 26);
    const Bytes nonce(data + 26, data + 42);
    const Bytes storedMachine(data + 42, data + 58);

    const unsigned char flagPassword = 0x01;
    const unsigned char flagHardware = 0x02;
    const unsigned char flagMachineBind = 0x04;
    const unsigned char flagDefaultKey = 0x10;
    (void)flagPassword;

    if ((flags & flagMachineBind) != 0 &&
        !constantTimeEqual(storedMachine, machineId())) {
        error = "container is bound to another machine";
        return false;
    }

    Bytes master;
    if ((flags & flagDefaultKey) != 0) {
        master = hkdfSha256(shieldSecretIkm(), salt,
                            fromAscii("AvroShield-v2/hkdf-sha256/default-key"), 32);
    } else {
        const Bytes passwordBytes(password.begin(), password.end());
        master = pbkdf2HmacSha256(passwordBytes, salt, 100000, 32);
    }
    if (master.size() != 32) {
        error = "key derivation failed";
        return false;
    }

    Bytes machineF(16, 0);
    Bytes hardwareF(16, 0);
    if ((flags & flagMachineBind) != 0)
        machineF = machineId();
    if ((flags & flagHardware) != 0)
        hardwareF = machineId();

    Bytes finalKey = sha512(concat(concat(master, machineF), hardwareF));
    if (finalKey.size() != 64) {
        error = "SHA-512 unavailable";
        return false;
    }
    const Bytes encKey(finalKey.begin(), finalKey.begin() + 32);
    const Bytes macKey(finalKey.begin() + 32, finalKey.begin() + 64);

    const size_t cipherLen = size - kHeaderSize - kTrailerSize;
    const Bytes cipher(data + kHeaderSize, data + kHeaderSize + cipherLen);
    const Bytes tag(data + size - kTrailerSize, data + size - kTrailerSize + 16);
    const Bytes expectedMac(data + size - kHmacSize, data + size);

    Bytes hmacInput(data, data + kHeaderSize);
    hmacInput.insert(hmacInput.end(), cipher.begin(), cipher.end());
    hmacInput.insert(hmacInput.end(), tag.begin(), tag.end());

    if (!constantTimeEqual(hmacSha512(macKey, hmacInput), expectedMac)) {
        error = "container authentication failed";
        return false;
    }

    Bytes compressed;
    if (!aes256GcmDecrypt(concat(cipher, tag), encKey, nonce, compressed)) {
        error = "container decryption failed";
        return false;
    }

    Bytes bytecode;
    if (!inflateBytes(compressed, bytecode) || bytecode.size() == 0) {
        error = "container payload could not be decompressed";
        return false;
    }
    if (bytecode.size() < 6 || std::memcmp(bytecode.data(), "AVROBC", 6) != 0) {
        error = "container payload is not bytecode";
        return false;
    }

    out.bytecode = std::move(bytecode);
    out.master = std::move(master);
    out.salt = salt;
    return true;
}

} // namespace

bool isAvroEncoContainer(const unsigned char* data, std::size_t size) {
    return data != nullptr && size >= 9 && std::memcmp(data, kShieldMagic, 8) == 0 &&
           (data[8] == 2 || data[8] == 3);
}

bool decodeAvroEncoContainer(const unsigned char* data, std::size_t size,
                             const std::string& password, std::string& utf8Json,
                             std::string& error) {
    utf8Json.clear();
    error.clear();

    OpenedContainer container;
    if (!openContainer(data, size, password, container, error))
        return false;

    Node root;
    if (!parseBytecode(container.bytecode, root, error))
        return false;

    // Format v3 keys the metadata mask from the container key; v2 used a
    // constant compiled into the unit (not reproduced here - containers built
    // by the current builder are v3).
    Bytes keyMeta;
    if (data[8] == 3)
        keyMeta = hkdfSha256(container.master, Bytes(), fromAscii(kObfInfoMeta), 32);

    Node payload;
    if (!deobfuscate(root, keyMeta, false, payload, error))
        return false;

    std::string json;
    json.reserve(256 * 1024);
    nodeToJson(payload, json);
    utf8Json = std::move(json);
    return true;
}

} // namespace avro
