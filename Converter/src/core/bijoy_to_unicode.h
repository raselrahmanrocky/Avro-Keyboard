// bijoy_to_unicode.h - ANSI (Bijoy 2000) -> Unicode reverse conversion.
// Port of TBijoy2000ToUnicode from clsBijoy2000ToUnicode.pas.  Reads the
// current ANSI registry state the same way the forward converter does, so
// JSON-driven mappings (Ansi V3, SutonnyMJ, BanglaPedia) work identically.

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

#include "ansi_registry.h"
#include "sweep_table.h"

namespace avro {

class BijoyToUnicode {
public:
    using ProgressCallback = std::function<void(int percent, const std::wstring& stage)>;

    ProgressCallback onProgress;

    BijoyToUnicode();
    ~BijoyToUnicode();

    // Convert ANSI (Bijoy) text to Unicode.
    std::wstring convert(std::wstring_view ansiText);

    // Call after the ANSI mapping changes (JSON re-loaded / defaults
    // restored) so the cached lookup tables are rebuilt on the next call.
    void invalidateTables();

    // Debug/diagnostic: current main sweep table entries (glyph -> Unicode).
    const std::vector<ReplacementPair>& mainTableDump() const { return main_; }

private:
    // glyph sequence -> glyph sequence (undo PostReplacements, last-first)
    std::vector<ReplacementPair> postInverse_;
    // glyph sequence -> glyph sequence (undo FinalTouch swaps)
    std::vector<ReplacementPair> swapBacks_;
    // combined glyph -> Unicode sweep table, sorted longest-glyph first
    std::vector<ReplacementPair> main_;
    // pre-base kar glyphs (ে/ৈ/ি), sorted longest first
    std::vector<ReplacementPair> preBaseKars_;
    // all other kar glyphs (া/ী/ু/ূ/ৃ/ৗ)
    std::vector<ReplacementPair> otherKars_;
    // kar glyph -> Unicode kar, sorted longest first
    std::vector<ReplacementPair> karMap_;
    // Inverted PreReplacements (ANSI glyph -> the character the user typed),
    // applied as the very last stage so no later sweep can re-match what it
    // produces, sorted longest first.
    std::vector<ReplacementPair> preInverse_;
    // True once buildTables has populated the arrays for the currently
    // loaded ANSI mapping.
    bool tablesBuilt_ = false;

    // Fast longest-match sweep tables (see SweepTable).
    std::unique_ptr<SweepTable> mainTable_;
    std::unique_ptr<SweepTable> karTable_;
    // Pre-built sweep tables for batch replacements in convert().
    // Stage 1: undo post-replacements (last-first, longest-key-first).
    std::unique_ptr<SweepTable> postInverseTable_;
    // Stage 2: undo final-touch swaps (glyph reordering).
    std::unique_ptr<SweepTable> swapBackTable_;
    // Stage 7: rejoin split ো/ৌ.
    std::unique_ptr<SweepTable> rejoinTable_;
    // Stage 8 (final): invert PreReplacements (punctuation restore).
    std::unique_ptr<SweepTable> preInverseTable_;

    void reportProgress(int percent, const std::wstring& stage);
    void buildTables();

    std::wstring varGlyph(const std::wstring& name) const;
    static std::wstring cleanKey(const std::wstring& s);
    static bool isSingleAsciiPunct(const std::wstring& s);
    // True when the mapping rewrites this literal character before conversion
    // (a PreReplacements key equal to the glyph), so a bare glyph equal to it
    // cannot have come from literal punctuation.
    bool hasLiteralEscape(const std::wstring& glyph) const;
    bool hasNonHalfFormOwner(const std::wstring& glyph) const;
    bool hasFirstHalfOwner(const std::wstring& glyph) const;
    bool isPreBaseKarAt(const std::wstring& text, size_t p, size_t& gLen) const; // 1-based p
    static bool isConsonantChar(wchar_t c);
    static bool isClusterMember(const std::wstring& text, size_t p, bool isFirst); // 1-based p
    static size_t getPrecedingClusterStart(const std::wstring& text, size_t p);   // 1-based p
    void reorderReph(std::wstring& text);
    void reorderPreBaseKars(std::wstring& text);
};

} // namespace avro
