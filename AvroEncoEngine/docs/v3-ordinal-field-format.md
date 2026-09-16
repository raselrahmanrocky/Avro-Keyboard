# AVROBC v3: ordinal field ids, pooled strings, validated records

Status: **designed, not yet implemented.** The v2 format remains what ships.
This document exists so the switch is a wiring task rather than a guess.

## Why v3 exists

In Shield v2 the bytecode stores object keys as `SHA-256(field name)`
(`ObfuscateTree` in `uAvroShield.pas`) and carries the complete reverse mapping
inside the payload as `_obf_meta`:

```
{"seed": "<base64>", "key_map": {"Metadata": "<sha256>"}, "dummies": [...]}
```

Two consequences, both verified against the current build:

1. The key map is **in the payload**. Anyone who decrypts one container gets
   every field name back as plain text, so the SHA-256 step buys nothing
   against anyone who has the key.
2. The field vocabulary is **already in the binary**, because
   `LoadAnsiMappingFromJSON` matches those names literally. So the hashes are
   dictionary-attackable using the binary itself as the dictionary.

`kat_staticleak` reports the v2 tokens (`_obf_meta`, `key_map`, `dummies`,
`AvroShieldBytecodeXORv1`) in any executable that links the runtime. That
warning list becomes empty when v3 lands.

## The validated vocabulary

Extracted from the four shipped sources (`AvroEncoEngine/source-mappings`,
which carry a UTF-8 BOM). Union across all four files:

Top-level sections (11, identical set in all four files):

| Section | JSON type |
| --- | --- |
| `Metadata` | object |
| `Constants` | object |
| `FullFormReplacements` | array |
| `PreReplacements` | array |
| `PostReplacements` | array |
| `VowelRules` | object |
| `RfolaRules` | array |
| `KarCorrections` | array |
| `GroupKarCorrections` | array |
| `ConsonantGroups` | object |
| `RaPhalaGroups` | object |

Schema-level keys below the top level (exact case matters — `TAvroNode.Keys` is
case sensitive and the vocabulary mixes conventions deliberately):

| Key | Occurrences | Where |
| --- | --- | --- |
| `Comment` | 1309 | pairs, kar and rfola records |
| `Value` | 1299 | pairs, rfola records |
| `UnicodeKey` | 620 | pairs |
| `Key` | 539 | pairs |
| `consonants` | 129 | vowel mappings, rfola |
| `value` | 129 | vowel mappings |
| `process` | 109 | vowel mappings |
| `matchMode` | 109 | vowel mappings |
| `replaceLen` | 20 | rfola |
| `alt` | 16 | vowel mappings |
| `toggle` | 16 | vowel mappings |
| `from` | 13 | group kar corrections |
| `to` | 13 | group kar corrections |
| `default` | 12 | vowel rules |
| `mappings` | 12 | vowel rules |
| `char` | 10 | vowel rules |
| `Encoding`, `Type`, `Version`, `Company`, `Developer`, `Modified By`, `Suggested Font` | 4 each | `Metadata` |

272 distinct keys exist at any depth, but roughly 200 of them are the
`A_*` scalar names under `Constants` (`A_0` … `A_9`, `A_A`, `A_AAKar`, …) plus
the group names. Those are **data**, addressed through `AnsiRegistry` and
`AnsiOverrides`, not schema. v3 must keep them as strings; only the 11 section
names and the ~16 schema keys above need ordinals.

## On-disk layout

```
+0   24-byte header      magic 'AVROBC', version 3, flags, sectionCount,
                         totalLen, reserved
+24  section directory   sectionCount x { offset:UInt32, length:UInt32 }
     STRPOOL             one UTF-8 blob, LENGTH-prefixed frames
     SECTION_*           flat, 4-aligned record arrays
+end SHA-256 trailer     over everything before it (corruption check only)
```

Header fields are fixed width and little-endian; the target is Win32/Win64
only. `totalLen` must equal the sum of the section lengths, and every section
offset must be 4-aligned and in range. The loader validates all of that in one
pass **before** it allocates or dereferences anything, and rejects on the first
violation - malformed input never reaches an allocation.

### String pool

One blob, frames of `Length:UInt32` followed by that many UTF-8 bytes. Every
string reference in the record arrays is a `TAvroOffset` (offset, length) pair
into it. Keeping the pool as a single `TBytes` rather than a `string` per value
is the point: the loader holds one buffer of plaintext instead of a UTF-16 heap
graph, and conversion happens only at the point of use.

### Records

```pascal
type
  TAvroOffset = packed record Off, Len: UInt32; end;   // 8 bytes, 4-aligned

  TAvroPairRec = record          // 16 bytes
    Key: TAvroOffset;            // -> STRPOOL
    Val: TAvroOffset;            // -> STRPOOL
  end;

  TAvroVowelRec = record         // 16 bytes
    Suffix, ReplaceWith: TAvroOffset;
    RuleClass, Flags: UInt16;    // ordinals, never names
  end;

  TAvroRfolaRec = record         // 24 bytes
    Pattern, Replacement: TAvroOffset;
    GroupId, Priority: UInt16;
    Reserved: UInt32;            // keeps 8-byte alignment across the array
  end;
```

`Reserved` is not padding for its own sake: it makes every record in the array
land on an 8-byte boundary so a whole section can be validated and bounded with
one multiplication instead of a per-element walk.

### Field ids

```pascal
type
  TAvroFieldId = (
    fidNone = 0,
    fidMetadata, fidConstants, fidFullFormReplacements, fidPreReplacements,
    fidPostReplacements, fidVowelRules, fidRfolaRules, fidKarCorrections,
    fidGroupKarCorrections, fidConsonantGroups, fidRaPhalaGroups,
    // ... schema keys at any depth, in the order of the validated table above
    fidComment, fidValue, fidUnicodeKey, fidKey, fidConsonants, fidValueLower,
    fidProcess, fidMatchMode, fidReplaceLen, fidAlt, fidToggle, fidFrom,
    fidTo, fidDefault, fidMappings, fidChar, // metadata keys ...
  );

const
  AVRO_FIELD_COUNT = Ord(High(TAvroFieldId)) + 1;
```

Ids are dense ordinals `UInt16`. There is no name, no hash and no key map on
the wire, and therefore nothing to dictionary-attack. An id outside the table
is a fail-closed reject rather than a silently skipped section - note this is a
behaviour change from v2, whose parser silently ignores unknown sections.

### What v3 deletes

* `ObfuscateTree`'s key hashing and `Rev` (`TDictionary<string, string>`).
* `BuildMetaJson`, `MetaSeed`, `META_KEY`, the `_obf_meta` entry.
* `AddDummyEntries` and the decoy machinery.
* Base64 of string values (`DeobfCodec` + `TEncodeBytesToString`). The payload
  is authenticated-encrypted already; base64 costs 33% size and a second
  allocation per value for no gain. The cheap length-keyed XOR can stay as
  defence in depth.

The largest security improvement here is deleted code.

## Migration

1. `uAvroEncoSchema.pas`: `TAvroFieldId`, the ordinal-to-name table (needed
   because the runtime's consumer, `LoadAnsiMappingFromJSON`, still keys on
   names), and the record types above.
2. Writer: replace `AssembleBytecode` with a two-pass builder - pass one
   interns every string into the pool while assigning ids, pass two emits the
   aligned record arrays and the section directory.
3. Reader: `AvroShieldParseBytecodeV3`, selected by the bytecode version byte
   (`ABytecode[6]`), so v2 containers keep loading from the same loader.
4. `AvroShieldLoadFromBytesUtf8` needs no change: it already treats the
   bytecode as opaque bytes between the zlib stage and the parse.
5. Rebuild all containers: `build_avroenco.bat`.
6. Extend `kat_avroshield` with v3 vectors, including a malformed-container
   case per validation rule (bad `totalLen`, misaligned section, out-of-range
   offset, unknown field id).
7. `kat_staticleak`'s warning list should then be empty; make that a hard
   failure at that point.

## Residual exposure after v3

The field *names* remain in the executable, because the mapping parser needs
them. Removing that last copy means giving the loader a name-free consumer as
well - i.e. populating the runtime tables directly from the record arrays
instead of going through `System.JSON` and `LoadAnsiMappingFromJSON`. That is
the natural follow-on to v3 and is what makes the pooled offset layout pay off
twice: it removes both the plaintext JSON text and the JSON parse tree from
the process.
