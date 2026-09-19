# Shield v3: keyed obfuscation, developer comment domain

Status: **implemented**. Format v2 containers still load; every shipped
container is rebuilt as v3 by `AvroEncoEngine\tools\AvroEncoBuilder\build_avroenco.bat`.
Authoritative code: `Keyboard and Spell checker\Units\uAvroShield.pas`.

## What this layer is, and what it is not

The container already encrypts its payload (AES-256-GCM under a key derived
from either the embedded application secret or a user password), with an
HMAC-SHA512 trailer over header + ciphertext + tag. The obfuscation layer does
not replace any of that. It answers a different question:

> A mapping file must keep its author documentation - the Bengali grapheme and
> ligature notes in the `Comment` fields ("০", "চ্ব → P¡", "ম-এর প্রথম খন্ড").
> Those notes must survive inside the container so a developer can maintain the
> tables, but a container must not disclose them to anyone who merely opens it.

So the goals are, in order:

1. **No legible mapping text at rest.** Neither the raw container nor the
   decrypted payload may contain readable `#$` literals, field names, section
   names or Bengali text.
2. **Comments need a second, developer-only key.** Recovering comment text
   requires the container key *and* an IKM the runtime never derives and never
   links. Extracting the application secret from the binary is not enough.
3. **Comments cost nothing at runtime.** The engine never sees them: they are
   dropped before the Base64 decode, so no decode, no keystream, no allocation,
   no parser work per load.
4. **A developer can always get the readable JSON back** with
   `AvroEncoBuilder --unpack`.

Honest limits, stated because they are easy to overclaim:

* **Values are recoverable by whoever holds the container key.** The runtime
  must reproduce the operational rules, so a reverser who recovers the secret
  from the binary (or debugs a running instance) can still decode values. Only
  the comment domain is unrecoverable without the developer key.
* **Obfuscation is not encryption.** It raises the cost of static reading; it
  does not make the payload cryptographically inaccessible.
* **Existing v2 containers keep their weaknesses.** Their metadata mask is the
  old compiled-in constant, so anyone who decrypts one can invert it fully, and
  their comments are in the value domain (legible with the container key). That
  is why every shipped container is rebuilt as v3.

## Threat model, concretely

| Attacker | v2 | v3 |
| --- | --- | --- |
| `strings` / byte scan of the container | nothing (encrypted) | nothing (encrypted) |
| Decrypts the container, knows the format, has no key | everything - the metadata mask is a constant in the unit | nothing: the metadata blob is masked with a key derived from the container master key |
| Decrypts the container, extracted the embedded secret | everything, comments included | values: yes; comments: no (they need the developer comment IKM) |
| Runs the shipped application and watches what it types | values | values |
| Has `keys\avrocomments.key` | - | everything, comments included |

## Pipeline (writer)

```
authoring JSON
  -> node tree
  -> obfuscate (see below)                      + metadata blob
  -> bytecode (AVROBC)
  -> zlib
  -> AES-256-GCM (EncKey)  +  HMAC-SHA512 trailer (MacKey)
  -> .AvroEnco
```

Key material, in order:

```
master        = HKDF-SHA256(default-key IKM, salt)      // or PBKDF2 for passwords
final         = SHA-512(master || machine factor || hardware factor)
enc_key, mac_key = final[0..31], final[32..63]

KeyMeta       = HKDF-SHA256(IKM = master,        info = 'AvroShield-v3/obf-meta',     32)
KeyComments   = HKDF-SHA256(IKM = developer IKM, salt = value seed,
                            info = 'AvroShield-v3/comments',                          32)
```

`Salt` and `master` are derived *before* the obfuscation stage, because the
metadata blob must be masked with a key that depends on them.

`KeyComments` is computed only where the value seed is known - inside the
deobfuscator, after the metadata blob has been unmasked. The comment domain is
therefore *layered underneath* the container key: it is not derivable from the
container key alone, and the developer IKM is never linked into the runtime.

## The codec

Every string value becomes `Base64( plain XOR keystream )`:

```
keystream_key = SHA-256( 'str\0' || domain_key || '\0' || ctx )
keystream     = SHA-256(keystream_key || BE32(counter)) repeated
```

`ctx` is the position of the value in the document, built as
`parentCtx + '/' + hashedKey` for object members and `parentCtx + '#' + index`
for array elements. This is the **positional salting**: identical plaintext at
two different positions gets different keystreams and therefore different
tokens, which is what defeats frequency analysis and precomputed tables. A
comment field's context is additionally prefixed (`'cmt/' + childCtx`) so the
two domains' `(key, ctx)` namespaces stay disjoint by construction.

Object keys are replaced by `SHA-256(name)` in hex, with the reverse map
carried in the metadata blob. 4–8 decoy root keys with random string values are
injected per build.

Metadata blob (`_obf_meta`), masked with `KeyMeta` and Base64-encoded:

```json
{"seed": "<base64>", "key_map": {"Metadata": "<sha256>"}, "dummies": ["d3f1…"]}
```

The value `seed` is freshly random for every build, so a payload never reuses
another build's keystream.

### Comment fields

`Comment`, `comment`, `_comment` (see `OBF_COMMENT_FIELDS`). Exact-name match:
`Comment` and `comment` are both documentation, but a value field that merely
contains the word is not swept into the domain.

* `IncludeComments = True` (developer tooling only): decoded with `KeyComments`
  at the `cmt/` context.
* `IncludeComments = False` (the runtime, and the only option
  `AvroShieldLoadForRuntime` exposes): the field is skipped **before** the
  Base64 decode. Nothing is decoded, allocated or wiped, and the mapping parser
  never sees the field. In the four shipped mappings that removes ~1300 string
  decodes and allocations per load.
* A container built without a comment key (self-tests only) writes comments in
  the value-domain key but keeps the `cmt/` context, so the reader's fallback
  matches exactly.

If the comment key is wrong, the comment domain **fails closed**: the garbage
it decodes is not valid UTF-8, so the load is rejected rather than returning
decoy text. `AvroEncoBuilder --unpack` reacts by retrying with comments
disabled, reporting `comments: NOT decoded`, and still handing the developer
the operational mapping - a rotated comment key must never cost anyone the
mapping itself.

## Container versioning

| | v2 | v3 |
| --- | --- | --- |
| byte 8 | `2` | `3` |
| metadata mask | constant `MetaSeed` compiled into the unit | `KeyMeta` (derived from the container key) |
| comment domain | none (comments are ordinary strings) | `KeyComments` at the `cmt/` context |
| flags (byte 9) | `$01` password, `$02` hardware, `$04` machine bind, `$08` bytecode v1, `$10` default-key | unchanged |

The reader accepts both; the writer emits v3. `uAvroEncoCrypto` no longer keeps
its own copy of the version byte - it asks
`uAvroShield.AvroShieldSupportedVersion`, so detection cannot drift from the
loader again. Older installed builds reject a v3 container with a clean
`asrBadVersion` / "Invalid .AvroEnco file header." instead of decoding garbage;
that is the intended direction for a format change.

## Developer workflow

```bat
rem pack: authoring JSON -> container
AvroEncoBuilder "assets\Ansi V1.json" "assets\Ansi V1.AvroEnco" ^
  --pack --default-key --format shield ^
  --secret-file keys\avroenco.key --comments-key-file keys\avrocomments.key

rem unpack: container -> authoring JSON, comments restored
AvroEncoBuilder --unpack "assets\Ansi V1.AvroEnco" "assets\Ansi V1.json" ^
  --secret-file keys\avroenco.key --comments-key-file keys\avrocomments.key
```

`--unpack` writes exactly the authored shape: UTF-8 with BOM, LF line breaks,
4-space indent, no trailing newline. For the four shipped mappings the output
is **byte-identical** to `assets\Ansi V*.json`; the gate
below asserts that.

`--pack` always runs the load-back verification with comments enabled, so a
comment-codec regression cannot ship.

One interaction worth knowing: the in-app *Export mapping* action copies the
container file when one exists, so the comments travel with it intact. It falls
back to the engine's own serializer (`ExportAnsiMapping`) only for the unbacked
`Default` mapping or when no source file is present - and that serializer has
no comments to write, because the runtime never decoded any. For a mapping with
authored documentation, `--unpack` is the export to use.

### Key handling

* `keys\avroenco.key` - container default-key IKM. Generate with
  `gen_shield_secret.py --out-pas … --key-file …` (the `--out-pas` writes the
  masked constant into `uAvroShieldSecret.pas`).
* `keys\avrocomments.key` - developer comment IKM. Generate with
  `gen_shield_secret.py --random 44 --key-file keys\avrocomments.key`, and
  **never** with `--out-pas`: linking it into the application would put the
  comment key in the hands of exactly the attacker this domain exists to stop.
* Both live under `keys\`, which is git-ignored. **Back the comment key up
  outside the repository.** It is never embedded anywhere, so if it is lost,
  comment text in already-built containers is unrecoverable for good; the
  tracked `assets\Ansi V*.json` sources are the only other record.
* Rotating the comment key means rebuilding the containers; old containers keep
  needing the old key (`--unpack` reports which key is the problem).

### Repository hygiene

The authored `assets\Ansi V*.json` sources are tracked beside the containers
they pack into, so a mapping and its packed form are reviewed and changed in one
place. They are a fully legible copy of every mapping to anyone with repo
access - the deliberate trade for being able to reproduce the packed artifacts
from the repository alone. The *runtime* never reads them: the mapping scanner
prefers `<name>.AvroEnco` over a same-named `.json`, and the installer only ever
ships `*.AvroEnco` (`avro-setup.iss`). The conversion gate compares each
container against the json beside it, so a source/container drift cannot hide -
which is how the V4 ou-kar value stayed wrong in one of them for a release.

## Golden vector

Input record (from `assets\Ansi V1.json`):

```json
"A_0": { "UnicodeKey": "#$09E6", "Value": "#$0030", "Comment": "০" }
```

Observed behaviour (`kat_obfcodec`, checks 1–17):

* Writer: all three leaves become Base64 tokens; `Rec/A_0/UnicodeKey`,
  `Rec/A_0/Value`, `Rec/A_0/Comment` each get a different context, and the
  comment leaf additionally gets the `cmt/` prefix and `KeyComments`.
* Opaque view (decrypted payload, container key only, no deobfuscation):
  contains `_obf_meta`, and **no** `০`, no `#$09E6`, no `#$0030`, no
  `UnicodeKey`, no `Comment`.
* `--unpack` with `keys\avrocomments.key`: all three strings restored verbatim,
  field names restored from `key_map`.
* `--unpack` with a wrong or missing comment key: the comment text is never
  produced (the load is rejected, or the field is absent).
* Runtime load: the record parses into the engine with no `Comment` key
  anywhere and the operational fields intact.
* Positional salting: the same `#$0030` at two object paths, and at two array
  indices, produces pairwise-distinct tokens; rebuilding the same document does
  not reproduce the previous tokens.

## Gates

| Gate | What it proves |
| --- | --- |
| `kat_obfcodec` | the codec contract above, plus the frozen `kat_shield_v2.AvroEnco` fixture still loading on the legacy path |
| `kat_staticleak` | per container: no secret and no authored canary in the raw bytes, **and** none legible in the unwrapped payload (no Bengali, no `#$`, no `Comment`) |
| `kat_flagdetect` | a v3 default-key container is still detected as default-key, so the menu import never prompts |
| `kat_ansiconvert` | the container converts byte-identically to its authored source, and the parser keeps every declared section, entry and group name |
| `kat_engineswitch` | the engine cache keeps the requested mapping installed across preload/switch/re-parse |
| `AvroEncoBuilder` | build-time load-back with comments enabled, and `--unpack` byte-identical to the authored source |

`build_avroenco.bat` runs all of them and refuses to ship a container that
fails any check.
