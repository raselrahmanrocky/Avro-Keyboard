// sweep_table.h - single-pass Longest-Match-First replacement engine.
// Port of TSweepTable from clsUnicodeToBijoy2000.pas.  Runs a document
// through ONCE: at each position the LONGEST key that matches wins (the same
// semantics as running the entries in longest-key-first order), and every
// value is emitted without re-scanning.

#pragma once

#include <string>
#include <unordered_map>
#include <vector>

namespace avro {

struct SweepEntry {
    std::wstring key;
    std::wstring value;
};

class SweepTable {
public:
    explicit SweepTable(const std::vector<SweepEntry>& entries);
    ~SweepTable();

    // Sweep the input, replacing every longest-match occurrence.
    std::wstring sweep(const std::wstring& s) const;

    // Sweep `s` into a fresh buffer (linear, no per-hit buffer shifting)
    // and swap it back.  Used for batch replacements where the replacement
    // patterns are known not to re-match inside their own output
    // (e.g. glyph swap-backs, post-inverse, rejoin).
    void sweepInPlace(std::wstring& s) const;

    // Returns true and fills outValue / outKeyLen when the longest key
    // matching at 0-based index i (i in [0, s.size()-1]) is found.
    bool matchAt(const std::wstring& s, size_t i, std::wstring& outValue,
                 size_t& outKeyLen) const;

private:
    // Sparse lookup maps: only allocate entries for characters that actually
    // appear as keys, instead of a fixed 65536-element vector.
    std::unordered_map<wchar_t, std::wstring> single_;
    struct Bucket {
        std::vector<SweepEntry> entries; // sorted longest-key-first
    };
    std::unordered_map<wchar_t, Bucket> buckets_;
    bool allSingle_ = false;
};

// Replace every occurrence of `from` with `to` (Delphi ReplaceStr semantics:
// non-overlapping, left-to-right, empty `from` leaves the string unchanged).
std::wstring replaceStr(const std::wstring& s, const std::wstring& from,
                        const std::wstring& to);

} // namespace avro
