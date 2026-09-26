// bijoy_to_unicode.cpp - ANSI (Bijoy 2000) -> Unicode reverse conversion.
// Port of TBijoy2000ToUnicode from clsBijoy2000ToUnicode.pas.  Mirror of the
// forward converter's data model: reads the current ANSI registry state so
// JSON-driven mappings (Ansi V3, SutonnyMJ, BanglaPedia) work identically.

#include "bijoy_to_unicode.h"

#include <algorithm>
#include <vector>

#include "bangla_chars.h"

namespace avro {

namespace {

// Same cleaning the forward pass applies to BengaliChar registry values.
std::wstring cleanKeyImpl(const std::wstring& s) {
    std::wstring result = s;
    for (const wchar_t sep : {L' ', L'(', L'-'}) {
        size_t p = result.find(sep);
        if (p != std::wstring::npos)
            result = result.substr(0, p);
    }
    size_t b = result.find_first_not_of(L" \t\r\n");
    if (b == std::wstring::npos)
        result.clear();
    else
        result = result.substr(b, result.find_last_not_of(L" \t\r\n") - b + 1);
    return result;
}

} // namespace

BijoyToUnicode::BijoyToUnicode() {}

BijoyToUnicode::~BijoyToUnicode() {}

std::wstring BijoyToUnicode::varGlyph(const std::wstring& name) const {
    return g_registry.getAnsiVarValue(name);
}

std::wstring BijoyToUnicode::cleanKey(const std::wstring& s) {
    return cleanKeyImpl(s);
}

// True for the single ASCII bracket/hyphen characters.  A custom full-form
// glyph that is a bracket or a hyphen (Ansi V3: ণ্ণ = ']', ঙ্ম = '-') is
// indistinguishable from the literal punctuation the forward pass passes
// through - brackets frame citations/numbers ([৫]) and hyphens join year
// ranges (১৯৪৭-১৯৪৮) in prose - so by default those keep their literal
// meaning.  hasLiteralEscape() lifts that default for a glyph the mapping
// rewrites before conversion: Ansi V3 escapes the literal hyphen as 'ô', so a
// bare '-' can only be ঙ্ম and is claimed, while ণ্ণ = ']' - which the mapping
// does not escape - stays literal.  Quotation marks and letters keep their
// conjunct claim (ক্ষ্ম = '"'), since the conjunct is the common meaning there.
bool BijoyToUnicode::isSingleAsciiPunct(const std::wstring& s) {
    if (s.size() != 1)
        return false;
    switch (s[0]) {
        case L'[': case L']': case L'{': case L'}':
        case L'(': case L')': case L'<': case L'>': case L'-':
            return true;
        default:
            return false;
    }
}

// A PreReplacements pair is {the character the user typed, the ANSI glyph the
// forward pass writes for it}.  When the pair's key is the glyph itself (Ansi
// V3: '-' -> 'ô') the literal character never reaches the ANSI text as that
// glyph, so the glyph is free to mean the conjunct on the way back.
bool BijoyToUnicode::hasLiteralEscape(const std::wstring& glyph) const {
    if (glyph.empty())
        return false;
    for (const auto& p : g_registry.customPreReplacements)
        if (p.key == glyph)
            return true;
    return false;
}

bool BijoyToUnicode::hasFirstHalfOwner(const std::wstring& glyph) const {
    if (g_registry.registryMap.empty())
        return false;
    for (const auto& kv : g_registry.registryMap) {
        const AnsiVarRec& r = kv.second;
        if (r.category == L"FirstHalfForms" && varGlyph(r.name) == glyph)
            return true;
    }
    return false;
}

bool BijoyToUnicode::hasNonHalfFormOwner(const std::wstring& glyph) const {
    if (g_registry.registryMap.empty())
        return false;
    for (const auto& kv : g_registry.registryMap) {
        const AnsiVarRec& r = kv.second;
        if (r.name != L"A_StartSingleQuote" && r.name != L"A_EndSingleQuote" &&
            r.name != L"A_StartDoubleQuote" && r.name != L"A_EndDoubleQuote" &&
            r.category != L"FirstHalfForms" && r.category != L"SecondHalfForms" &&
            varGlyph(r.name) == glyph)
            return true;
    }
    return false;
}

static bool endsWithStr(const std::wstring& s, const std::wstring& suffix) {
    return s.size() >= suffix.size() &&
           s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

void BijoyToUnicode::buildTables() {
    g_registry.init();

    // First-claim-wins dictionary (mirror of the Delphi Dict.Add).
    std::map<std::wstring, std::wstring> dict;

    auto add = [&dict](const std::wstring& key, const std::wstring& value) {
        if (!key.empty() && !value.empty() && dict.find(key) == dict.end())
            dict[key] = value;
    };

    // ------------------------------------------------------------------
    // Quotes FIRST: in some mappings (BanglaPedia) the quote glyphs are the
    // raw Unicode codepoints U+2018/2019/201C/201D, which collide with the
    // default second-half glyph A_Th_2H = U+2019.  The quote meaning must
    // win, otherwise a closing quote comes back as the conjunct ্+থ.
    // ------------------------------------------------------------------
    add(varGlyph(L"A_StartSingleQuote"), std::wstring(1, bangla::b_StartSingleQuote));
    add(varGlyph(L"A_EndSingleQuote"), std::wstring(1, bangla::b_EndSingleQuote));
    add(varGlyph(L"A_StartDoubleQuote"), std::wstring(1, bangla::b_StartDoubleQuote));
    add(varGlyph(L"A_EndDoubleQuote"), std::wstring(1, bangla::b_EndDoubleQuote));

    // Raw Unicode quote codepoints win over SECOND-half-form conjunct
    // glyphs, but a codepoint owned by a FIRST-half form keeps its conjunct
    // meaning, and quotes never beat a real letter either.
    if (!hasNonHalfFormOwner(std::wstring(1, bangla::b_StartSingleQuote)) &&
        !hasFirstHalfOwner(std::wstring(1, bangla::b_StartSingleQuote)))
        add(std::wstring(1, bangla::b_StartSingleQuote), std::wstring(1, bangla::b_StartSingleQuote));
    if (!hasNonHalfFormOwner(std::wstring(1, bangla::b_EndSingleQuote)) &&
        !hasFirstHalfOwner(std::wstring(1, bangla::b_EndSingleQuote)))
        add(std::wstring(1, bangla::b_EndSingleQuote), std::wstring(1, bangla::b_EndSingleQuote));
    if (!hasNonHalfFormOwner(std::wstring(1, bangla::b_StartDoubleQuote)) &&
        !hasFirstHalfOwner(std::wstring(1, bangla::b_StartDoubleQuote)))
        add(std::wstring(1, bangla::b_StartDoubleQuote), std::wstring(1, bangla::b_StartDoubleQuote));
    if (!hasNonHalfFormOwner(std::wstring(1, bangla::b_EndDoubleQuote)) &&
        !hasFirstHalfOwner(std::wstring(1, bangla::b_EndDoubleQuote)))
        add(std::wstring(1, bangla::b_EndDoubleQuote), std::wstring(1, bangla::b_EndDoubleQuote));

    // ------------------------------------------------------------------
    // Base LETTERS first.  A glyph shared by a letter and a conjunct
    // half-form keeps its LETTER meaning.  Conjunct full forms are claimed
    // AFTER the half-forms; kars are handled by their own later passes.
    // ------------------------------------------------------------------
    for (const auto& name : g_registry.registryOrder) {
        auto it = g_registry.registryMap.find(name);
        if (it == g_registry.registryMap.end())
            continue;
        const AnsiVarRec& rec = it->second;
        if (rec.bengaliChar.empty())
            continue;
        if (rec.category == L"FirstHalfForms" || rec.category == L"SecondHalfForms" ||
            rec.category == L"FullForms")
            continue;
        // Vowel-sign kars are mapped after the reordering pass.
        if (rec.category == L"VowelsAndKars" && rec.name.size() >= 3 &&
            endsWithStr(rec.name, L"Kar"))
            continue;

        std::wstring glyph = varGlyph(rec.name);
        if (glyph.empty())
            continue;
        // The four quote vars are handled first; skip them here.
        if (rec.name == L"A_StartSingleQuote" || rec.name == L"A_EndSingleQuote" ||
            rec.name == L"A_StartDoubleQuote" || rec.name == L"A_EndDoubleQuote")
            continue;
        std::wstring uni = cleanKey(rec.bengaliChar);
        if (uni.empty())
            continue;
        add(glyph, uni);
    }

    // ------------------------------------------------------------------
    // Half-form glyphs.
    // ------------------------------------------------------------------
    // Special pair: ঙ + ্ + ম is encoded as NGA_1H + plain ম (no hasanta).
    std::wstring nga1h = varGlyph(L"A_NGA_1H");
    std::wstring aM = varGlyph(L"A_M");
    if (!nga1h.empty() && !aM.empty())
        add(nga1h + aM,
            std::wstring(1, bangla::b_NGA) + std::wstring(1, bangla::b_Hasanta) +
                std::wstring(1, bangla::b_M));

    // Conjunct-with-r second halves decode to consonant + ্ + র.
    std::wstring hasanta = varGlyph(L"A_Hasanta");
    std::wstring tR2H = varGlyph(L"A_T_R_2H");
    if (!hasanta.empty() && !tR2H.empty())
        add(hasanta + tR2H,
            std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_t) +
                std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_M_2H_1"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_M));
    add(varGlyph(L"A_M_2H_2"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_M));
    add(varGlyph(L"A_T_R_2H"),
        std::wstring(1, bangla::b_t) + std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_K_R_2H"),
        std::wstring(1, bangla::b_K) + std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_BH_R_2H"),
        std::wstring(1, bangla::b_Bh) + std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));

    add(varGlyph(L"A_B_2H_1"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_B));
    add(varGlyph(L"A_B_2H_2"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_B));
    add(varGlyph(L"A_B_2H_3"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_B));
    add(varGlyph(L"A_B_2H_4"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_B));
    add(varGlyph(L"A_BH_2H"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_Bh));
    add(varGlyph(L"A_L_2H_1"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_L));
    add(varGlyph(L"A_L_2H_2"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_L));
    add(varGlyph(L"A_L_2H_3"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_L));
    // The Nn second-half slots take their Unicode meaning from the registry
    // (BengaliChar), which a mapping may override through UnicodeKey.
    // Defaults keep the Delphi behavior exactly (both decode to ্+ণ); Ansi V1
    // redefines A_Nn_2H_2 as ্+ন, matching the forward encoder, which routes
    // ্+ন through A_Nn_2H_2 (secondHalfForms) - so V1's oe glyph round-trips.
    auto addNnSecondHalf = [&](const wchar_t* name) {
        std::wstring glyph = varGlyph(name);
        if (glyph.empty())
            return;
        auto it = g_registry.registryMap.find(name);
        if (it == g_registry.registryMap.end())
            return;
        std::wstring uni = cleanKey(it->second.bengaliChar);
        if (uni.empty())
            return;
        add(glyph, std::wstring(1, bangla::b_Hasanta) + uni);
    };
    addNnSecondHalf(L"A_Nn_2H_1");
    addNnSecondHalf(L"A_Nn_2H_2");
    add(varGlyph(L"A_T_2H"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_t));
    add(varGlyph(L"A_Th_2H"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_Th));
    add(varGlyph(L"A_K_2H"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_K));

    // First-half forms in forward output ALWAYS keep a trailing হসন্ত glyph.
    // Claim the pair contextually so a forward-produced conjunct like ্-চ
    // still reverses to চ্ via the longer key.
    if (!hasanta.empty()) {
        std::wstring h(1, bangla::b_Hasanta);
        auto pair = [&](const std::wstring& g, wchar_t c) {
            if (!g.empty())
                add(g + hasanta, std::wstring(1, c) + h);
        };
        pair(varGlyph(L"A_M_1H"), bangla::b_M);
        pair(varGlyph(L"A_Ss_1H"), bangla::b_Ss);
        pair(varGlyph(L"A_C_1H"), bangla::b_C);
        pair(varGlyph(L"A_NGA_1H"), bangla::b_NGA);
        pair(varGlyph(L"A_S_1H_1"), bangla::b_s);
        pair(varGlyph(L"A_N_1H_1"), bangla::b_n);
        pair(varGlyph(L"A_N_1H_2"), bangla::b_n);
        pair(varGlyph(L"A_D_1H_1"), bangla::b_d);
        pair(varGlyph(L"A_D_1H_2"), bangla::b_d);
    }

    // Second-half forms that share their glyph with a quote codepoint lose
    // their BARE claim to the quote identity above, so a conjunct written as
    // [1st-half][2nd-half] must be claimed as an explicit multi-glyph pair.
    std::wstring th2h = varGlyph(L"A_Th_2H");
    if (!th2h.empty()) {
        std::wstring s1h1 = varGlyph(L"A_S_1H_1");
        std::wstring n1h1 = varGlyph(L"A_N_1H_1");
        if (!s1h1.empty())
            add(s1h1 + th2h,
                std::wstring(1, bangla::b_s) + std::wstring(1, bangla::b_Hasanta) +
                    std::wstring(1, bangla::b_Th)); // ¯' -> স্থ
        if (!n1h1.empty())
            add(n1h1 + th2h,
                std::wstring(1, bangla::b_n) + std::wstring(1, bangla::b_Hasanta) +
                    std::wstring(1, bangla::b_Th)); // š' -> ন্থ
    }

    add(varGlyph(L"A_M_1H"), std::wstring(1, bangla::b_M) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_Ss_1H"), std::wstring(1, bangla::b_Ss) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_C_1H"), std::wstring(1, bangla::b_C) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_NGA_1H"), std::wstring(1, bangla::b_NGA) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_S_1H_1"), std::wstring(1, bangla::b_s) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_N_1H_1"), std::wstring(1, bangla::b_n) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_N_1H_2"), std::wstring(1, bangla::b_n) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_D_1H_1"), std::wstring(1, bangla::b_d) + std::wstring(1, bangla::b_Hasanta));
    add(varGlyph(L"A_D_1H_2"), std::wstring(1, bangla::b_d) + std::wstring(1, bangla::b_Hasanta));

    // Folas.  (The reph glyph is deliberately NOT expanded here: it needs its
    // own re-ordering pass in convert, and in BanglaPedia it shares a glyph
    // with A_Th_2H, so expanding it blindly would corrupt ্+থ conjuncts.)
    add(varGlyph(L"A_ZFola"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_z));
    add(varGlyph(L"A_RFola_1"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_RFola_2"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_RFola_3"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));

    // Registry conjunct full forms (extra glyphs like ত্ম in SutonnyMJ).
    // Claimed after the half-forms so a half-form clash wins there.
    for (const auto& name : g_registry.registryOrder) {
        auto it = g_registry.registryMap.find(name);
        if (it == g_registry.registryMap.end())
            continue;
        const AnsiVarRec& rec = it->second;
        if (rec.bengaliChar.empty() || rec.category != L"FullForms")
            continue;
        std::wstring glyph = varGlyph(rec.name);
        if (glyph.empty())
            continue;
        std::wstring uni = cleanKey(rec.bengaliChar);
        if (uni.empty())
            continue;
        add(glyph, uni);
    }

    // JSON-driven custom full forms (extra conjuncts).  A glyph that is a
    // single printable ASCII punctuation character is ambiguous and stays
    // literal - unless the mapping escapes that character before conversion
    // (Ansi V3: '-' -> 'ô'), which leaves the bare glyph free for the conjunct
    // (Ansi V3: ঙ্ম = '-' is claimed, ণ্ণ = ']' is not).
    for (const auto& p : g_registry.customFullForms)
        if (!isSingleAsciiPunct(p.value) || hasLiteralEscape(p.value))
            add(p.value, p.key);

    // Ansi V4's r-fola variants 4/5/6.  Delphi claims no glyph for these at
    // all; they are added AFTER every full form so the compiled-in values
    // (#$C7/#$CB/#$CC) keep their ড্ড/ত্ত/ত্থ meaning wherever a mapping puts
    // them there (the built-in base tables and Ansi V1/V2), while Ansi V4 -
    // which moved those full forms elsewhere - gets ্+র back instead of a
    // raw glyph.
    add(varGlyph(L"A_RFola_4"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_RFola_5"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));
    add(varGlyph(L"A_RFola_6"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_R));

    // প's second-half form (Ansi V4 declares it; earlier mappings inherit the
    // compiled-in #$2219 default).  Same class as the r-fola variants above:
    // because the glyph comes from a variable default rather than from the
    // mapping's own tables, every full form the mapping DOES declare is
    // claimed first.  Ansi V3 assigns #$2219 to its own full form ব্দ, so the
    // bare glyph comes back as ব্দ there, while with the built-in base tables
    // and Ansi V1/V2/V4 - which leave the glyph free - ্+প still reverses to
    // প's second half.
    add(varGlyph(L"A_P_2H"), std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_P));

    // Invert the PreReplacements as a FINAL pass (preInverseTable_, stage 8),
    // not as a gap-fill here: Ansi V3's inverted comma ('–' -> ',') would
    // otherwise be produced at stage 3 and then re-matched by the kar sweep,
    // because ',' IS V3's RRI-kar glyph ('–' came back as 'ৃ').  The claim
    // semantics are unchanged either way: a glyph the table above already
    // claimed is converted at stage 3 and never reaches the final pass, so a
    // glyph with a real conjunct/letter meaning keeps it - exactly what the
    // old last-claim-wins gap-fill did.

    // Flatten + sort the sweep table longest-glyph-first so multi-char
    // glyphs always win over the shorter glyphs they contain.
    main_.clear();
    main_.reserve(dict.size());
    for (const auto& kv : dict)
        main_.push_back({kv.first, kv.second});
    std::stable_sort(main_.begin(), main_.end(),
                     [](const ReplacementPair& l, const ReplacementPair& r) {
                         return l.key.size() > r.key.size();
                     });
    std::vector<SweepEntry> mainEntries;
    mainEntries.reserve(main_.size());
    for (const auto& p : main_)
        mainEntries.push_back({p.key, p.value});
    mainTable_.reset(new SweepTable(mainEntries));

    // ------------------------------------------------------------------
    // Kar tables.
    // ------------------------------------------------------------------
    dict.clear();

    // Pre-base kars: the forward pass hoists these in front of the cluster.
    add(varGlyph(L"A_EKar1"), std::wstring(1, bangla::b_Ekar));
    add(varGlyph(L"A_EKar2"), std::wstring(1, bangla::b_Ekar));
    add(varGlyph(L"A_IKar"), std::wstring(1, bangla::b_Ikar));
    add(varGlyph(L"A_OIKar1"), std::wstring(1, bangla::b_OIkar));
    add(varGlyph(L"A_OIKar2"), std::wstring(1, bangla::b_OIkar));

    preBaseKars_.clear();
    preBaseKars_.reserve(dict.size());
    for (const auto& kv : dict)
        preBaseKars_.push_back({kv.first, kv.second});
    std::stable_sort(preBaseKars_.begin(), preBaseKars_.end(),
                     [](const ReplacementPair& l, const ReplacementPair& r) {
                         return l.key.size() > r.key.size();
                     });

    dict.clear();

    add(varGlyph(L"A_AAKar"), std::wstring(1, bangla::b_AAkar));
    add(varGlyph(L"A_IIKar"), std::wstring(1, bangla::b_IIkar));
    add(varGlyph(L"A_UKar1"), std::wstring(1, bangla::b_Ukar));
    add(varGlyph(L"A_UKar2"), std::wstring(1, bangla::b_Ukar));
    add(varGlyph(L"A_UKar3"), std::wstring(1, bangla::b_Ukar));
    add(varGlyph(L"A_UKar4"), std::wstring(1, bangla::b_Ukar));
    add(varGlyph(L"A_UUKar1"), std::wstring(1, bangla::b_UUkar));
    add(varGlyph(L"A_UUKar2"), std::wstring(1, bangla::b_UUkar));
    add(varGlyph(L"A_UUKar3"), std::wstring(1, bangla::b_UUkar));
    add(varGlyph(L"A_RRIKar1"), std::wstring(1, bangla::b_RRIkar));
    add(varGlyph(L"A_RRIKar2"), std::wstring(1, bangla::b_RRIkar));
    add(varGlyph(L"A_OUKar"), std::wstring(1, bangla::b_LengthMark));

    otherKars_.clear();
    otherKars_.reserve(dict.size());
    for (const auto& kv : dict)
        otherKars_.push_back({kv.first, kv.second});
    std::stable_sort(otherKars_.begin(), otherKars_.end(),
                     [](const ReplacementPair& l, const ReplacementPair& r) {
                         return l.key.size() > r.key.size();
                     });

    // Combined kar map (pre-base + others), longest first.
    karMap_.clear();
    karMap_.reserve(preBaseKars_.size() + otherKars_.size());
    karMap_.insert(karMap_.end(), preBaseKars_.begin(), preBaseKars_.end());
    karMap_.insert(karMap_.end(), otherKars_.begin(), otherKars_.end());
    std::stable_sort(karMap_.begin(), karMap_.end(),
                     [](const ReplacementPair& l, const ReplacementPair& r) {
                         return l.key.size() > r.key.size();
                     });
    std::vector<SweepEntry> karEntries;
    karEntries.reserve(karMap_.size());
    for (const auto& p : karMap_)
        karEntries.push_back({p.key, p.value});
    karTable_.reset(new SweepTable(karEntries));

    // ------------------------------------------------------------------
    // FinalTouch swap inversions (glyph sequence -> glyph sequence).
    // The forward pass swaps reph/z-fola/r-fola around the u-kar glyphs at
    // the very end; the reverse swaps them back before anything expands.
    // ------------------------------------------------------------------
    swapBacks_.clear();
    auto addSwap = [this](const std::wstring& key, const std::wstring& value) {
        if (key.empty() || value.empty())
            return;
        swapBacks_.push_back({key, value, L""});
    };

    // Last forward op first: [UKar1][Reph] -> [UKar2][Reph] nets out to
    // [UKar2][Reph] meaning the original [Reph][UKar1].  This is inherently
    // lossy: forward also produces [UKar2][Reph] from [Reph][UKar2], which
    // cannot be told apart afterwards.
    addSwap(varGlyph(L"A_UKar2") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UKar1"));
    addSwap(varGlyph(L"A_UKar3") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UKar3"));
    addSwap(varGlyph(L"A_UKar4") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UKar4"));
    addSwap(varGlyph(L"A_UUKar1") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UUKar1"));
    addSwap(varGlyph(L"A_UUKar2") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UUKar2"));
    addSwap(varGlyph(L"A_UUKar3") + varGlyph(L"A_Reph"), varGlyph(L"A_Reph") + varGlyph(L"A_UUKar3"));

    addSwap(varGlyph(L"A_UKar1") + varGlyph(L"A_RFola_1"), varGlyph(L"A_RFola_1") + varGlyph(L"A_UKar1"));
    addSwap(varGlyph(L"A_UUKar1") + varGlyph(L"A_RFola_1"), varGlyph(L"A_RFola_1") + varGlyph(L"A_UUKar1"));
    addSwap(varGlyph(L"A_UKar1") + varGlyph(L"A_RFola_2"), varGlyph(L"A_RFola_2") + varGlyph(L"A_UKar1"));
    addSwap(varGlyph(L"A_UUKar1") + varGlyph(L"A_RFola_2"), varGlyph(L"A_RFola_2") + varGlyph(L"A_UUKar1"));

    addSwap(varGlyph(L"A_UKar1") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UKar1"));
    addSwap(varGlyph(L"A_UKar2") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UKar2"));
    addSwap(varGlyph(L"A_UKar3") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UKar3"));
    addSwap(varGlyph(L"A_UKar4") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UKar4"));
    addSwap(varGlyph(L"A_UUKar1") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UUKar1"));
    addSwap(varGlyph(L"A_UUKar2") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UUKar2"));
    addSwap(varGlyph(L"A_UUKar3") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_UUKar3"));

    addSwap(varGlyph(L"A_Reph") + varGlyph(L"A_ZFola"), varGlyph(L"A_ZFola") + varGlyph(L"A_Reph"));

    // ------------------------------------------------------------------
    // PostReplacement inversions (undo, last applied first).
    // ------------------------------------------------------------------
    postInverse_.clear();
    postInverse_.reserve(g_registry.customPostReplacements.size());
    for (const auto& p : g_registry.customPostReplacements)
        postInverse_.push_back({p.value, p.key, L""});

    // Inverted PreReplacements: ANSI glyph -> the character the user typed
    // (e.g. Ansi V3: '–' -> ',', '¦' -> '!').  Run dead last in convert().
    preInverse_.clear();
    preInverse_.reserve(g_registry.customPreReplacements.size());
    for (const auto& p : g_registry.customPreReplacements)
        if (!p.value.empty() && !p.key.empty())
            preInverse_.push_back({p.value, p.key, L""});
    std::stable_sort(preInverse_.begin(), preInverse_.end(),
                     [](const ReplacementPair& l, const ReplacementPair& r) {
                         return l.key.size() > r.key.size();
                     });

    // ------------------------------------------------------------------
    // Pre-build sweep tables for batch replacements in convert().
    // ------------------------------------------------------------------
    // Stage 1: post-inverse sweep (longest key first).
    {
        std::vector<SweepEntry> entries;
        entries.reserve(postInverse_.size());
        for (const auto& p : postInverse_)
            if (!p.key.empty() && !p.value.empty())
                entries.push_back({p.key, p.value});
        postInverseTable_.reset(new SweepTable(entries));
    }
    // Stage 2: swap-back sweep.
    {
        std::vector<SweepEntry> entries;
        entries.reserve(swapBacks_.size());
        for (const auto& p : swapBacks_)
            if (!p.key.empty() && !p.value.empty())
                entries.push_back({p.key, p.value});
        swapBackTable_.reset(new SweepTable(entries));
    }
    // Stage 7: rejoin ো/ৌ sweep.
    {
        std::vector<SweepEntry> entries;
        entries.push_back(
            {std::wstring(1, bangla::b_Ekar) + std::wstring(1, bangla::b_AAkar),
             std::wstring(1, bangla::b_Okar)});
        entries.push_back(
            {std::wstring(1, bangla::b_Ekar) + std::wstring(1, bangla::b_LengthMark),
             std::wstring(1, bangla::b_OUkar)});
        rejoinTable_.reset(new SweepTable(entries));
    }
    // Stage 8 (final): invert PreReplacements (punctuation restore).
    {
        std::vector<SweepEntry> entries;
        entries.reserve(preInverse_.size());
        for (const auto& p : preInverse_)
            entries.push_back({p.key, p.value});
        preInverseTable_.reset(new SweepTable(entries));
    }

    tablesBuilt_ = true;
}

void BijoyToUnicode::invalidateTables() {
    tablesBuilt_ = false;
}

bool BijoyToUnicode::isPreBaseKarAt(const std::wstring& text, size_t p,
                                    size_t& gLen) const {
    gLen = 0;
    if (p >= 1 && p <= text.size()) {
        // Already-unicode pre-base kars: some text reaches this pass with the
        // kar glyphs already converted.  Detect the Unicode forms directly.
        if (text[p - 1] == bangla::b_Ekar || text[p - 1] == bangla::b_OIkar ||
            text[p - 1] == bangla::b_Ikar) {
            gLen = 1;
            return true;
        }
    }
    for (const auto& entry : preBaseKars_) {
        const std::wstring& key = entry.key;
        if (key.size() <= text.size() - p + 1 &&
            text.compare(p - 1, key.size(), key) == 0) {
            gLen = key.size();
            return true; // sorted longest-first, so this is the longest match
        }
    }
    return false;
}

// Bengali consonant (or ৎ / ড় / ঢ় / য়)?
bool BijoyToUnicode::isConsonantChar(wchar_t c) {
    const int o = static_cast<int>(c);
    return o == 0x09CE || (o >= 0x0995 && o <= 0x09B9) || o == 0x09DC ||
           o == 0x09DD || o == 0x09DF;
}

// Cluster membership for the kar re-ordering pass.  A cluster is a conjunct
// chain: a first consonant, then only consonants that are PRECEDED by a
// হসন্ত (plus the হসন্ত themselves, and a nukta).  A consonant that is not
// preceded by a হসন্ত starts a fresh syllable, so the kar must stop there.
bool BijoyToUnicode::isClusterMember(const std::wstring& text, size_t p,
                                     bool isFirst) {
    if (isFirst)
        return isConsonantChar(text[p - 1]);
    if (text[p - 1] == bangla::b_Hasanta || text[p - 1] == bangla::b_Nukta)
        return true;
    return isConsonantChar(text[p - 1]) && p > 1 && text[p - 2] == bangla::b_Hasanta;
}

// Scans backwards from P (a consonant) across the conjunct chain
// [consonant (্ consonant)*] that ends at P, returning the 1-based index of
// its first character (0 when P is not a consonant).
size_t BijoyToUnicode::getPrecedingClusterStart(const std::wstring& text, size_t p) {
    if (p < 1 || p > text.size() || !isConsonantChar(text[p - 1]))
        return 0;
    size_t result = p;
    while (result >= 3 && text[result - 2] == bangla::b_Hasanta &&
           isConsonantChar(text[result - 3]))
        result -= 2;
    return result;
}

// The forward pass (ReArrangeReph) places the reph glyph right AFTER the
// consonant cluster it belongs to.  In Unicode the র্ must LEAD the cluster,
// so move each reph glyph to the start of the cluster immediately before it,
// then expand it to র্ (র + হসন্ত).
//
// O(n) two-pass algorithm:
//   Pass 1 (read-only): find every reph and its cluster boundary.
//   Pass 2 (single sequential write): emit gap, reph, cluster for each move.
void BijoyToUnicode::reorderReph(std::wstring& text) {
    std::wstring reph = varGlyph(L"A_Reph");
    if (reph.empty())
        return;
    const size_t rephLen = reph.size();
    if (rephLen == 0)
        return;
    const size_t n = text.size();

    // ── Pass 1: find every reph + its preceding cluster (read-only). ──
    struct Move { size_t rephPos; size_t clusterStart; };
    std::vector<Move> moves;
    moves.reserve(n / 16);
    for (size_t i = 0; i + rephLen <= n; ) {
        bool isR = true;
        for (size_t k = 0; k < rephLen; ++k)
            if (text[i + k] != reph[k]) { isR = false; break; }
        if (isR) {
            if (i > 0 && isConsonantChar(text[i - 1])) {
                size_t cs = i - 1;
                while (cs >= 2 && text[cs - 1] == bangla::b_Hasanta
                       && isConsonantChar(text[cs - 2]))
                    cs -= 2;
                moves.push_back({i, cs});
            }
            i += rephLen;
        } else {
            ++i;
        }
    }
    if (moves.empty())
        return;

    // ── Pass 2: build output.  For each move, emit the gap, then the
    // reph, then the cluster (reordered), then advance past the reph.
    std::wstring out;
    out.reserve(n + n / 4);
    size_t scan = 0;
    for (const auto& mv : moves) {
        if (scan < mv.clusterStart)
            out.append(text, scan, mv.clusterStart - scan);
        out.append(text, mv.rephPos, rephLen);
        out.append(text, mv.clusterStart, mv.rephPos - mv.clusterStart);
        scan = mv.rephPos + rephLen;
    }
    if (scan < n)
        out.append(text, scan, n - scan);
    text = std::move(out);

    // Expand every remaining reph glyph to র্ (র + হসন্ত).
    text = replaceStr(text, reph,
                      std::wstring(1, bangla::b_R) + std::wstring(1, bangla::b_Hasanta));
}

// Reverse of ReArrangeKars: pre-base kars (ে/ৈ/ি) were hoisted in front of
// their consonant cluster by the forward pass; move each one back to just
// after that cluster.  Single left-to-right pass building the output once.
void BijoyToUnicode::reorderPreBaseKars(std::wstring& text) {
    if (text.empty())
        return;
    std::wstring out;
    out.reserve(text.size() + 16);
    size_t i = 1;
    while (i <= text.size()) {
        size_t gLen = 0;
        if (isPreBaseKarAt(text, i, gLen)) {
            size_t j = i + gLen;
            bool isFirst = true;
            while (j <= text.size() && isClusterMember(text, j, isFirst)) {
                ++j;
                isFirst = false;
            }
            if (j > i + gLen) {
                // Cluster [i+gLen .. j-1] first, then the kar moved after it.
                out.append(text, i + gLen - 1, j - i - gLen);
                out.append(text, i - 1, gLen);
                i = j; // continue right after the moved kar
            } else {
                out.append(text, i - 1, gLen);
                i += gLen;
            }
        } else {
            out.push_back(text[i - 1]);
            ++i;
        }
    }
    text = std::move(out);
}

void BijoyToUnicode::reportProgress(int percent, const std::wstring& stage) {
    if (onProgress)
        onProgress(percent, stage);
}

std::wstring BijoyToUnicode::convert(std::wstring_view ansiText) {
    if (ansiText.empty())
        return std::wstring();

    const int totalStages = 9;
    int stageNo = 0;

    // Tables depend on the currently selected ANSI mapping.  They are built
    // once and cached (invalidateTables marks them stale when the mapping
    // changes), so repeated convert calls no longer rebuild and re-sort
    // hundreds of dictionary entries on every single invocation.
    if (!tablesBuilt_)
        buildTables();

    std::wstring text(ansiText);

    // 1. Undo the JSON PostReplacements (forward applies them last).
    //    Batched into a single longest-match-first sweep instead of N
    //    individual replaceStr calls, eliminating N full-string copies.
    if (postInverseTable_)
        postInverseTable_->sweepInPlace(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"post-inverse");

    // 2. Undo the FinalTouch glyph swaps.
    //    Same batch optimization: one sweep pass instead of ~30 copies.
    if (swapBackTable_)
        swapBackTable_->sweepInPlace(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"swap-backs");

    // 3. Combined glyph -> Unicode sweep (longest glyph first).  Kars and the
    // reph glyph survive this pass on purpose.
    text = mainTable_->sweep(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"main-sweep");

    // 3.5 Collapse runs of 2+ hasantas to a single hasanta.
    std::wstring sb;
    sb.reserve(text.size() + 8);
    {
        size_t i = 0;
        while (i < text.size()) {
            if (text[i] == bangla::b_Hasanta) {
                sb.push_back(bangla::b_Hasanta);
                while (i < text.size() && text[i] == bangla::b_Hasanta)
                    ++i;
            } else {
                sb.push_back(text[i]);
                ++i;
            }
        }
    }
    text = std::move(sb);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"hasanta-collapse");

    // 4. Move the reph glyph to the start of its cluster, then expand to র্.
    reorderReph(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"reorder-reph");

    // 5. Put ে/ৈ/ি back after their conjunct-chain clusters.
    reorderPreBaseKars(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"reorder-prebase");

    // 6. Remaining kar glyphs -> Unicode kars.
    text = karTable_->sweep(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"kar-map");

    // 7. Rejoin the split ো and ৌ.
    if (rejoinTable_)
        rejoinTable_->sweepInPlace(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rejoin");

    // 8. Invert the PreReplacements, dead last: this restores the characters
    //    the forward pre-pass consumed (Ansi V3: ',' -> '–', '!' -> '¦', ...).
    //    Running it after every other sweep keeps its output safe from later
    //    re-matching - ',' is V3's RRI-kar glyph, so producing it before the
    //    kar pass turned '–' into 'ৃ'.  A glyph the main table already
    //    claimed never reaches this pass, preserving the old gap-fill's
    //    last-claim-wins meaning.
    if (preInverseTable_)
        preInverseTable_->sweepInPlace(text);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"pre-inverse");

    return text;
}

} // namespace avro
