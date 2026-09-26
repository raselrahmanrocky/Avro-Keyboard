#include "unicode_to_bijoy.h"

#include <algorithm>

#include "sweep_table.h"

namespace avro {

using bangla::Char;

// Free helpers mirroring unit-level functions ---------------------------------

// CharInGroup: true when Ch is a member of the named group ('default' is a
// wildcard).  Consonant groups are checked before ANSI groups.
static bool charInGroup(const std::wstring& ch, const std::wstring& groupName) {
    if (groupName.empty())
        return false;
    if (groupName == L"default")
        return true;
    auto it = g_registry.consonantGroupMap.find(groupName);
    if (it != g_registry.consonantGroupMap.end())
        for (const auto& s : it->second)
            if (s == ch)
                return true;
    auto ait = g_registry.ansiGroupMap.find(groupName);
    if (ait != g_registry.ansiGroupMap.end())
        for (const auto& s : ait->second)
            if (s == ch)
                return true;
    return false;
}

// ---------------------------------------------------------------------------
// Convert pipeline
// ---------------------------------------------------------------------------

std::wstring UnicodeToBijoy::convert(std::wstring_view uniText) {
    int stageNo = 0;
    constexpr int totalStages = 21;

    if (uniText.empty()) {
        toggleStates_.clear();
        lastUniText_.clear();
        return std::wstring();
    }

    if (uniText.find(L' ') != std::wstring_view::npos)
        toggleStates_.clear();

    uniText_ = std::wstring(uniText);
    convertedText_ = uniText_;

    // 1. Dynamic pre-placement fixes on raw Unicode input
    for (const auto& p : g_registry.customPreReplacements)
        convertedText_ = replaceStr(convertedText_, p.key, p.value);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"pre-replacements");

    for (const auto& rule : g_registry.vowelRules) {
        if (!ruleHasAnyToggle(rule))
            continue;
        if (!lastUniText_.empty()) {
            std::wstring consonantPart = uniText_;
            if (lastUniText_.size() == consonantPart.size() + rule.karChar.size() &&
                lastUniText_.compare(0, consonantPart.size(), consonantPart) == 0 &&
                lastUniText_.compare(consonantPart.size(), rule.karChar.size(),
                                     rule.karChar) == 0) {
                bool mapToggleBack = false;
                std::wstring matchedCluster;
                if (findMappingToggle(rule, consonantPart, mapToggleBack, matchedCluster)) {
                    if (mapToggleBack) {
                        setToggleState(matchedCluster, rule.karChar,
                                       countOccurrences(rule.karChar, lastUniText_),
                                       !getToggleState(matchedCluster, rule.karChar,
                                                       countOccurrences(rule.karChar, lastUniText_)));
                    }
                }
            }
        }
    }
    lastUniText_ = uniText_;
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"toggle-state");

    // 2. Resolve kar-inclusive full forms BEFORE the vowel-rule pass
    applyKarInclusiveFullForms();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"kar-inclusive");

    // Phase A: pre-phase vowel rule pass (raw Unicode text)
    applyRuleForKar(std::wstring(1, bangla::b_Ukar), L"pre");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"u-kar-pre");
    applyRuleForKar(std::wstring(1, bangla::b_UUkar), L"pre");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"uu-kar-pre");
    applyRuleForKar(std::wstring(1, bangla::b_RRIkar), L"pre");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rri-kar-pre");

    deNormalize();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"denormalize");
    replaceNumbers();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"numbers");

    // 3. Rearrange Vowels and Reph
    reArrangeKars();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rearrange-kars");
    reArrangeReph();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rearrange-reph");

    // 4. Apply the U/UU/RRI main pass
    applyVowelKars();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"vowel-kars");

    // 5. Conjuncts and Full Forms
    replaceFullForms();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"full-forms");

    // 6. Remaining Vowels
    replaceKarsVowels();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"kar-vowels");

    // 7. Glyphs, Halfs, Consonants
    convertRFolaZFolaHasanta();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rfola-zfola");

    // Flicker-Free Half Form Protection
    bool hasTrailingHasanta = false;
    if (!convertedText_.empty() &&
        convertedText_[convertedText_.size() - 1] == bangla::b_Hasanta) {
        hasTrailingHasanta = true;
        convertedText_.pop_back();
    }
    firstHalfForms();
    if (hasTrailingHasanta)
        convertedText_.push_back(bangla::b_Hasanta);
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"first-half-forms");

    secondHalfForms();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"second-half-forms");
    consonants();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"consonants");

    // Post-phase vowel rule pass
    applyRuleForKar(std::wstring(1, bangla::b_Ukar), L"post");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"u-kar-post");
    applyRuleForKar(std::wstring(1, bangla::b_UUkar), L"post");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"uu-kar-post");
    applyRuleForKar(std::wstring(1, bangla::b_RRIkar), L"post");
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"rri-kar-post");

    finalTouch();
    ++stageNo;
    reportProgress((stageNo * 100) / totalStages, L"final-touch");

    return convertedText_;
}

void UnicodeToBijoy::reportProgress(int percent, const std::wstring& stage) {
    if (onProgress)
        onProgress(percent, stage);
}

// ---------------------------------------------------------------------------
// Toggle state helpers
// ---------------------------------------------------------------------------

bool UnicodeToBijoy::getToggleState(const std::wstring& context,
                                    const std::wstring& key,
                                    int occurrenceIndex) const {
    std::wstring combined =
        context + L"_" + std::to_wstring(occurrenceIndex) + L"_" + key;
    auto it = toggleStates_.find(combined);
    return it != toggleStates_.end() && it->second;
}

void UnicodeToBijoy::setToggleState(const std::wstring& context,
                                    const std::wstring& key, int occurrenceIndex,
                                    bool value) {
    // Guard against unbounded growth: the toggle map stores one entry per
    // unique (context, kar, occurrence) triple.  For very large documents
    // this can balloon to millions of entries.  Cap at 50k; beyond that
    // the toggle state is unreliable anyway (the Delphi original had no
    // such guard because its TDictionary also grew unbounded).
    constexpr size_t kMaxToggleStates = 50000;
    if (toggleStates_.size() >= kMaxToggleStates)
        toggleStates_.clear();
    std::wstring combined =
        context + L"_" + std::to_wstring(occurrenceIndex) + L"_" + key;
    toggleStates_[combined] = value;
}

bool UnicodeToBijoy::ruleHasAnyToggle(const VowelRule& rule) const {
    if (rule.toggleOnBackspace)
        return true;
    for (const auto& m : rule.mappings)
        if (m.toggleOnBackspace)
            return true;
    return false;
}

bool UnicodeToBijoy::isVowel(Char c) const {
    return c == bangla::b_A || c == bangla::b_AA || c == bangla::b_I ||
           c == bangla::b_II || c == bangla::b_U || c == bangla::b_UU ||
           c == bangla::b_RRI || c == bangla::b_E || c == bangla::b_OI ||
           c == bangla::b_O || c == bangla::b_OU;
}

bool UnicodeToBijoy::baseLineRightCharacter(const std::wstring& wc) const {
    using bangla::b_kh; using bangla::b_g; using bangla::b_gh; using bangla::b_Nn;
    using bangla::b_Th; using bangla::b_d; using bangla::b_dh; using bangla::b_n;
    using bangla::b_p; using bangla::b_b; using bangla::b_m; using bangla::b_z;
    using bangla::b_r; using bangla::b_L; using bangla::b_sh; using bangla::b_ss;
    using bangla::b_s; using bangla::b_h; using bangla::b_y;

    // Fast path for single-characters: compare wchar_t directly, avoiding
    // the heap allocation of std::wstring(1, ch) on every comparison.
    if (wc.size() == 1) {
        const wchar_t c = wc[0];
        if (c == b_kh || c == b_g || c == b_gh || c == b_Nn ||
            c == b_Th || c == b_d || c == b_dh || c == b_n ||
            c == b_p || c == b_b || c == b_m || c == b_z ||
            c == b_r || c == b_L || c == b_sh || c == b_ss ||
            c == b_s || c == b_h || c == b_y)
            return true;
    }

    // Multi-character ANSI glyph names (full-form conjuncts, etc.)
    if (wc == g_registry.v.A_K_Ss_M || wc == g_registry.v.A_K_M ||
        wc == g_registry.v.A_K_Ss || wc == g_registry.v.A_K_S ||
        wc == g_registry.v.A_G_G || wc == g_registry.v.A_G_D ||
        wc == g_registry.v.A_G_Dh || wc == g_registry.v.A_NGA_G ||
        wc == g_registry.v.A_T_Th || wc == g_registry.v.A_T_M ||
        wc == g_registry.v.A_D_D || wc == g_registry.v.A_D_Dh ||
        wc == g_registry.v.A_D_B || wc == g_registry.v.A_D_M ||
        wc == g_registry.v.A_N_Tth || wc == g_registry.v.A_N_Dh ||
        wc == g_registry.v.A_N_S || wc == g_registry.v.A_P_P ||
        wc == g_registry.v.A_P_S || wc == g_registry.v.A_B_D ||
        wc == g_registry.v.A_B_Dh || wc == g_registry.v.A_Bh_R ||
        wc == g_registry.v.A_M_N || wc == g_registry.v.A_L_G ||
        wc == g_registry.v.A_L_P || wc == g_registry.v.A_Ss_Nn ||
        wc == g_registry.v.A_S_Kh || wc == g_registry.v.A_S_N ||
        wc == g_registry.v.A_H_N || wc == g_registry.v.A_H_M ||
        wc == g_registry.v.A_Rr_G)
        return true;
    return false;
}

// ---------------------------------------------------------------------------
// Kar rules
// ---------------------------------------------------------------------------

bool UnicodeToBijoy::findMappingToggle(const VowelRule& rule,
                                       const std::wstring& consonantPart,
                                       bool& mappingToggleOnBackspace,
                                       std::wstring& matchedCluster) const {
    mappingToggleOnBackspace = rule.toggleOnBackspace;
    if (consonantPart.empty())
        return false;

    std::wstring actual = consonantPart;
    int len = static_cast<int>(actual.size());

    // Strip Z-fola suffix if present
    if (len >= 2 && actual[len - 1] == bangla::b_z &&
        actual[len - 2] == bangla::b_Hasanta) {
        actual = actual.substr(0, len - 2);
        len = static_cast<int>(actual.size());
    }
    if (actual.empty())
        return false;

    std::wstring lastC = actual.substr(len - 1, 1);
    int bestMatchLen = 0;
    VowelRuleMapping bestMapping;

    for (const auto& mapping : rule.mappings) {
        if (mapping.consonants.empty())
            continue;
        int matchLen = 0;
        if (lastC == mapping.consonants &&
            !g_registry.hasHasantaBefore(actual, len)) {
            matchLen = (mapping.matchMode == 1) ? 1 : static_cast<int>(mapping.consonants.size());
        } else {
            int groupMatchLen =
                g_registry.matchGroupLength(actual, len, mapping.consonants);
            if (groupMatchLen > 0)
                matchLen = (mapping.matchMode == 1) ? 1 : groupMatchLen;
        }
        if (matchLen > bestMatchLen) {
            bestMatchLen = matchLen;
            bestMapping = mapping;
        }
    }

    if (bestMatchLen > 0) {
        mappingToggleOnBackspace = bestMapping.toggleOnBackspace;
        matchedCluster = actual.substr(len - bestMatchLen, bestMatchLen);
        return true;
    }
    return false;
}

ClusterMatchInfo UnicodeToBijoy::findBestClusterMatch(const std::wstring& text,
                                                      int karPos,
                                                      const VowelRule& rule) const {
    ClusterMatchInfo result;
    result.bestMatchLen = 0;
    result.contextEnd = 0;
    result.isZfola = false;

    if (karPos - 1 < 1)
        return result;

    std::wstring precedingChar = text.substr(karPos - 2, 1);
    result.contextEnd = karPos - 1;
    result.isZfola = (precedingChar == std::wstring(1, bangla::b_z)) &&
                     (karPos - 2 >= 1) &&
                     (text[karPos - 3] == bangla::b_Hasanta);

    if (result.isZfola) {
        result.contextEnd = karPos - 3;
        if (result.contextEnd >= 1)
            precedingChar = text.substr(result.contextEnd - 1, 1);
        else
            precedingChar.clear();
    }

    if (result.contextEnd < 1)
        return result;

    for (const auto& mapping : rule.mappings) {
        if (mapping.consonants.empty())
            continue;
        int matchLen = 0;
        // 1. Direct single-character match
        if (!precedingChar.empty() && precedingChar == mapping.consonants &&
            !g_registry.hasHasantaBefore(text, karPos - 1)) {
            matchLen = (mapping.matchMode == 1)
                           ? 1
                           : static_cast<int>(mapping.consonants.size());
        } else {
            // 2. Group-based cluster match
            int groupMatchLen =
                g_registry.matchGroupLength(text, result.contextEnd, mapping.consonants);
            if (groupMatchLen > 0)
                matchLen = (mapping.matchMode == 1) ? 1 : groupMatchLen;
        }
        if (matchLen > result.bestMatchLen) {
            result.bestMatchLen = matchLen;
            result.bestMapping = mapping;
        }
    }

    if (result.bestMatchLen > 0)
        result.matchedCluster =
            text.substr(result.contextEnd - result.bestMatchLen, result.bestMatchLen);
    return result;
}

void UnicodeToBijoy::applyRuleForKar(const std::wstring& karChar,
                                     const std::wstring& phase) {
    constexpr int lookBackWindow = 64;

    bool found = false;
    VowelRule rule;
    for (const auto& r : g_registry.vowelRules)
        if (r.karChar == karChar) {
            rule = r;
            found = true;
            break;
        }
    if (!found)
        return;

    std::wstring searchChar =
        (phase == L"post") ? g_registry.resolveValue(rule.defaultVal) : karChar;

    std::wstring out;
    out.reserve(convertedText_.size() + 16);
    int occurrenceIndex = 0;
    size_t i = 0;
    const size_t n = convertedText_.size();
    while (i < n) {
        if (convertedText_[i] == searchChar[0]) {
            ++occurrenceIndex;
            std::wstring resolved;
            if (out.size() >= 1) {
                int lw = static_cast<int>(out.size());
                if (lw > lookBackWindow)
                    lw = lookBackWindow;
                std::wstring win = out.substr(out.size() - lw, lw);
                ClusterMatchInfo info = findBestClusterMatch(win, lw + 1, rule);
                if (info.bestMatchLen > 0) {
                    if (!phase.empty() && !info.bestMapping.processPhase.empty() &&
                        info.bestMapping.processPhase != phase) {
                        resolved = g_registry.resolveValue(rule.defaultVal);
                    } else {
                        bool useAlt = false;
                        if (info.bestMapping.toggleOnBackspace)
                            useAlt = getToggleState(info.matchedCluster, karChar,
                                                    occurrenceIndex);
                        if (useAlt && !info.bestMapping.alt.empty())
                            resolved = g_registry.resolveValue(info.bestMapping.alt);
                        else
                            resolved = g_registry.resolveValue(info.bestMapping.value);
                    }
                } else {
                    resolved = g_registry.resolveValue(rule.defaultVal);
                }
            } else {
                resolved = g_registry.resolveValue(rule.defaultVal);
            }
            out.append(resolved);
            ++i;
        } else {
            out.push_back(convertedText_[i]);
            ++i;
        }
    }
    convertedText_ = std::move(out);
}

// ---------------------------------------------------------------------------
// Pipeline passes
// ---------------------------------------------------------------------------

void UnicodeToBijoy::applyKarInclusiveFullForms() {
    constexpr int lookBackWindow = 64;
    if (g_registry.karInclusiveReplacements.empty())
        return;

    std::vector<SweepEntry> entries;
    entries.reserve(g_registry.karInclusiveReplacements.size());
    for (const auto& p : g_registry.karInclusiveReplacements) {
        if (!p.key.empty() && !p.value.empty())
            entries.push_back({p.key, p.value});
    }
    SweepTable table(entries);

    std::wstring out;
    out.reserve(convertedText_.size() + 8);
    size_t n = convertedText_.size();
    size_t i = 0;
    while (i < n) {
        std::wstring v;
        size_t klen = 0;
        if (table.matchAt(convertedText_, i, v, klen)) {
            // Hasanta immediately before the match?
            size_t hpos = out.size();
            while (hpos >= 1 && (out.size() - hpos) < static_cast<size_t>(lookBackWindow) &&
                   (out[hpos - 1] == bangla::ZWJ || out[hpos - 1] == bangla::ZWNJ))
                --hpos;
            bool hasH = (hpos >= 1) && (out[hpos - 1] == bangla::b_Hasanta);
            if (hasH) {
                out.push_back(convertedText_[i]);
                ++i;
            } else {
                out.append(v);
                i += klen;
            }
        } else {
            out.push_back(convertedText_[i]);
            ++i;
        }
    }
    convertedText_ = std::move(out);
}

void UnicodeToBijoy::applyVowelKars() {
    applyRuleForKar(std::wstring(1, bangla::b_Ukar));
    convertedText_ = replaceStr(convertedText_, std::wstring(1, bangla::b_Ukar),
                                g_registry.getAnsiVarValue(L"A_UKar1"));
    applyRuleForKar(std::wstring(1, bangla::b_UUkar));
    convertedText_ = replaceStr(convertedText_, std::wstring(1, bangla::b_UUkar),
                                g_registry.getAnsiVarValue(L"A_UUKar1"));
    applyRuleForKar(std::wstring(1, bangla::b_RRIkar));
    convertedText_ = replaceStr(convertedText_, std::wstring(1, bangla::b_RRIkar),
                                g_registry.getAnsiVarValue(L"A_RRIKar1"));
}

void UnicodeToBijoy::replaceKarsVowels() {
    // Merge Ekar + OIKar into a single pass: both use the same
    // context-dependent rule (whitespace before → kar1, else → kar2).
    {
        const auto isWS = [](wchar_t c) {
            return c == L' ' || c == L'\r' || c == L'\n' || c == L'\t';
        };
        const std::wstring ekar1 = g_registry.v.A_EKar1;
        const std::wstring ekar2 = g_registry.getAnsiVarValue(L"A_EKar2");
        const std::wstring oikar1 = g_registry.v.A_OIKar1;
        const std::wstring oikar2 = g_registry.getAnsiVarValue(L"A_OIKar2");
        std::wstring out;
        out.reserve(convertedText_.size() + 8);
        size_t i = 0;
        while (i < convertedText_.size()) {
            const Char c = convertedText_[i];
            if (c == bangla::b_Ekar) {
                const bool atStart = out.empty() || isWS(out.back());
                out.append(atStart ? ekar1 : ekar2);
                ++i;
            } else if (c == bangla::b_OIkar) {
                const bool atStart = out.empty() || isWS(out.back());
                out.append(atStart ? oikar1 : oikar2);
                ++i;
            } else {
                out.push_back(c);
                ++i;
            }
        }
        convertedText_ = std::move(out);
    }

    // Remaining kars and vowels - single sweep
    std::vector<SweepEntry> entries(15);
    entries[0] = {std::wstring(1, bangla::b_AAkar), g_registry.v.A_AAKar};
    entries[1] = {std::wstring(1, bangla::b_Ikar), g_registry.v.A_IKar};
    entries[2] = {std::wstring(1, bangla::b_IIkar), g_registry.v.A_IIKar};
    entries[3] = {std::wstring(1, bangla::b_LengthMark), g_registry.v.A_OUKar};
    entries[4] = {std::wstring(1, bangla::b_A), g_registry.v.A_A};
    entries[5] = {std::wstring(1, bangla::b_AA), g_registry.v.A_AA};
    entries[6] = {std::wstring(1, bangla::b_I), g_registry.getAnsiVarValue(L"A_I")};
    entries[7] = {std::wstring(1, bangla::b_II), g_registry.v.A_II};
    entries[8] = {std::wstring(1, bangla::b_U), g_registry.getAnsiVarValue(L"A_U")};
    entries[9] = {std::wstring(1, bangla::b_UU), g_registry.v.A_UU};
    entries[10] = {std::wstring(1, bangla::b_RRI), g_registry.v.A_RRI};
    entries[11] = {std::wstring(1, bangla::b_E), g_registry.v.A_E};
    entries[12] = {std::wstring(1, bangla::b_OI), g_registry.v.A_OI};
    entries[13] = {std::wstring(1, bangla::b_O), g_registry.v.A_O};
    entries[14] = {std::wstring(1, bangla::b_OU), g_registry.v.A_OU};
    SweepTable table(entries);
    convertedText_ = table.sweep(convertedText_);
}

void UnicodeToBijoy::convertRFolaZFolaHasanta() {
    // Batch z-fola + hasanta substitution into a single sweep.
    {
        const std::wstring H(1, bangla::b_Hasanta);
        std::vector<SweepEntry> entries = {
            {H + std::wstring(1, bangla::b_z),  g_registry.v.A_ZFola},
            {H + std::wstring(1, bangla::ZWNJ), g_registry.v.A_Hasanta},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    // R-Fola single left-to-right pass
    std::wstring out;
    out.reserve(convertedText_.size() + 16);
    size_t i = 0;
    const size_t n = convertedText_.size();
    while (i < n) {
        if (convertedText_[i] == bangla::b_Hasanta && i + 1 < n &&
            convertedText_[i + 1] == bangla::b_r) {
            Char prevC = 0, c2 = 0, c3 = 0;
            if (out.size() >= 1) prevC = out[out.size() - 1];
            if (out.size() >= 2) c2 = out[out.size() - 2];
            if (out.size() >= 3) c3 = out[out.size() - 3];
            bool isHalfForm = (c2 == bangla::b_Hasanta);

            std::wstring val;
            int take = 0;

            // MatchRfola
            bool matched = false;
            if (!g_registry.rfolaRules.empty()) {
                for (const auto& r : g_registry.rfolaRules) {
                    if (!r.contextGroup.empty() &&
                        charInGroup(std::wstring(1, prevC), r.consonants)) {
                        if (isHalfForm && c3 != 0) {
                            if (charInGroup(std::wstring(1, c3), r.contextGroup)) {
                                val = r.contextValue;
                                take = 0; // ContextReplaceLen is 2 in the mappings
                                matched = true;
                                break;
                            }
                        }
                    }
                    if (charInGroup(std::wstring(1, prevC), r.consonants)) {
                        if (r.replaceLen > 2) {
                            take = r.replaceLen - 2;
                            if (isHalfForm && !r.halfValue.empty())
                                val = r.halfValue;
                            else
                                val = r.value;
                        } else {
                            val = r.value;
                            take = 0;
                        }
                        matched = true;
                        break;
                    }
                }
            }
            if (!matched) {
                if (prevC == bangla::b_p || prevC == bangla::b_g || prevC == bangla::b_sh) {
                    val = g_registry.v.A_RFola_3;
                    take = 0;
                } else if (prevC == bangla::b_Bh) {
                    val = isHalfForm ? g_registry.v.A_BH_R_2H : g_registry.v.A_Bh_R;
                    take = 1;
                } else if (prevC == bangla::b_K) {
                    val = isHalfForm ? g_registry.v.A_K_R_2H : g_registry.v.A_K_R;
                    take = 1;
                } else if (prevC == bangla::b_t) {
                    if (isHalfForm) {
                        if (c3 != 0 && (c3 == bangla::b_K || c3 == bangla::b_t)) {
                            val = g_registry.v.A_RFola_2;
                            take = 0;
                        } else {
                            val = g_registry.v.A_T_R_2H;
                            take = 1;
                        }
                    } else {
                        val = g_registry.v.A_T_R;
                        take = 1;
                    }
                } else if (prevC == g_registry.v.A_K_T[0] ||
                           prevC == g_registry.v.A_T_T[0] ||
                           prevC == g_registry.v.A_P_T[0]) {
                    val = g_registry.v.A_RFola_2;
                    take = 0;
                } else if (prevC == bangla::b_ph) {
                    val = g_registry.v.A_RFola_2;
                    take = 0;
                } else {
                    val = g_registry.v.A_RFola_1;
                    take = 0;
                }
            }

            if (take > static_cast<int>(out.size()))
                take = static_cast<int>(out.size());
            out.resize(out.size() - take);
            out.append(val);
            i += 2;
        } else {
            out.push_back(convertedText_[i]);
            ++i;
        }
    }
    convertedText_ = std::move(out);
}

void UnicodeToBijoy::deNormalize() {
    // Batch nukta normalizations into a single sweep.
    {
        std::vector<SweepEntry> entries = {
            {std::wstring(1, bangla::b_z)   + std::wstring(1, bangla::b_Nukta), std::wstring(1, bangla::b_y)},
            {std::wstring(1, bangla::b_dd)  + std::wstring(1, bangla::b_Nukta), std::wstring(1, bangla::b_rr)},
            {std::wstring(1, bangla::b_ddh) + std::wstring(1, bangla::b_Nukta), std::wstring(1, bangla::b_rrh)},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    // Collapse every run of 3+ hasantas to a pair
    std::wstring out;
    out.reserve(convertedText_.size() + 8);
    size_t i = 0;
    const size_t n = convertedText_.size();
    while (i < n) {
        if (convertedText_[i] == bangla::b_Hasanta) {
            size_t j = i;
            while (j < n && convertedText_[j] == bangla::b_Hasanta)
                ++j;
            int runLen = static_cast<int>(j - i);
            if (runLen > 2)
                runLen = 2;
            while (runLen-- > 0)
                out.push_back(bangla::b_Hasanta);
            i = j;
        } else {
            out.push_back(convertedText_[i]);
            ++i;
        }
    }
    convertedText_ = std::move(out);

    convertedText_ = replaceStr(
        convertedText_,
        std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_z) +
            std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_r),
        std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_r) +
            std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::b_z));
}

void UnicodeToBijoy::replaceNumbers() {
    std::vector<SweepEntry> entries(10);
    entries[0] = {std::wstring(1, bangla::b_0), g_registry.v.A_0};
    entries[1] = {std::wstring(1, bangla::b_1), g_registry.v.A_1};
    entries[2] = {std::wstring(1, bangla::b_2), g_registry.v.A_2};
    entries[3] = {std::wstring(1, bangla::b_3), g_registry.v.A_3};
    entries[4] = {std::wstring(1, bangla::b_4), g_registry.v.A_4};
    entries[5] = {std::wstring(1, bangla::b_5), g_registry.v.A_5};
    entries[6] = {std::wstring(1, bangla::b_6), g_registry.v.A_6};
    entries[7] = {std::wstring(1, bangla::b_7), g_registry.v.A_7};
    entries[8] = {std::wstring(1, bangla::b_8), g_registry.v.A_8};
    entries[9] = {std::wstring(1, bangla::b_9), g_registry.v.A_9};
    SweepTable table(entries);
    convertedText_ = table.sweep(convertedText_);
}

void UnicodeToBijoy::reArrangeKars() {
    // Expand Okar and OUkar into multi-char equivalents in a single sweep.
    {
        std::vector<SweepEntry> entries = {
            {std::wstring(1, bangla::b_Okar),  std::wstring(1, bangla::b_Ekar) + std::wstring(1, bangla::b_AAkar)},
            {std::wstring(1, bangla::b_OUkar), std::wstring(1, bangla::b_Ekar) + std::wstring(1, bangla::b_LengthMark)},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    const size_t len = convertedText_.size();
    if (len == 0)
        return;

    auto moveAbleKar = [](Char wKar) {
        return wKar == bangla::b_Ekar || wKar == bangla::b_Ikar ||
               wKar == bangla::b_OIkar;
    };

    std::vector<Char> tempList;
    tempList.reserve(len + len / 4);
    Char fKar = 0;
    size_t i = len;
    while (i >= 1) {
        Char wCTmp = convertedText_[i - 1];
        if (moveAbleKar(wCTmp)) {
            if (fKar != 0)
                tempList.push_back(fKar);
            fKar = wCTmp;
        } else {
            if (fKar == 0) {
                tempList.push_back(wCTmp);
            } else {
                if (!bangla::IsPureConsonent(wCTmp) && wCTmp != bangla::b_Hasanta &&
                    wCTmp != bangla::ZWJ && wCTmp != bangla::ZWNJ) {
                    tempList.push_back(fKar);
                    fKar = 0;
                    tempList.push_back(wCTmp);
                } else {
                    if (wCTmp == bangla::b_Hasanta || wCTmp == bangla::ZWJ ||
                        wCTmp == bangla::ZWNJ) {
                        tempList.push_back(wCTmp);
                    } else if (bangla::IsPureConsonent(wCTmp)) {
                        if (i > 1 &&
                            (convertedText_[i - 2] == bangla::b_Hasanta ||
                             convertedText_[i - 2] == bangla::ZWJ ||
                             convertedText_[i - 2] == bangla::ZWNJ)) {
                            tempList.push_back(wCTmp);
                        } else {
                            tempList.push_back(wCTmp);
                            tempList.push_back(fKar);
                            fKar = 0;
                        }
                    }
                }
            }
        }
        --i;
    }
    if (fKar != 0)
        tempList.push_back(fKar);

    // TempList holds the output in reverse order.
    convertedText_.assign(tempList.rbegin(), tempList.rend());
}

void UnicodeToBijoy::reArrangeReph() {
    const size_t len = convertedText_.size();
    if (len < 3)
        return;

    auto moveAbleReph = [&](size_t idx) {
        // idx is 0-based position of 'ra' candidate
        if (idx + 1 >= len)
            return false;
        if (idx > 0 && convertedText_[idx - 1] == bangla::b_Hasanta)
            return false;
        if (convertedText_[idx] == bangla::b_r &&
            convertedText_[idx + 1] == bangla::b_Hasanta) {
            if (idx + 2 < len &&
                (convertedText_[idx + 2] == L' ' || convertedText_[idx + 2] == L'\r'))
                return false;
            return true;
        }
        return false;
    };

    std::wstring out;
    out.reserve(len + 64);
    size_t i = 0;
    bool rephPending = false;
    while (i < len) {
        Char wCTmp = convertedText_[i];
        if (moveAbleReph(i)) {
            rephPending = true;
            i += 2;
            continue;
        }
        out.push_back(wCTmp);
        if (rephPending) {
            if (isVowel(wCTmp)) {
                // keep moving
            } else if (i + 1 < len && convertedText_[i + 1] == bangla::b_Hasanta) {
                // keep moving
            } else if (wCTmp != bangla::b_Hasanta && wCTmp != bangla::ZWJ &&
                       wCTmp != bangla::ZWNJ) {
                out.push_back(g_registry.v.A_Reph[0]);
                rephPending = false;
            }
        }
        ++i;
    }
    if (rephPending)
        out.push_back(g_registry.v.A_Reph[0]);
    convertedText_ = std::move(out);
}

void UnicodeToBijoy::firstHalfForms() {
    // Batch the 5 simple consonant+hasanta -> half-form replacements into
    // a single SweepTable pass instead of 5 sequential full-document scans.
    {
        const std::wstring H(1, bangla::b_Hasanta);
        std::vector<SweepEntry> entries = {
            {std::wstring(1, bangla::b_m)  + H, g_registry.v.A_M_1H   + H},
            {std::wstring(1, bangla::b_ss) + H, g_registry.v.A_Ss_1H  + H},
            {std::wstring(1, bangla::b_C)  + H, g_registry.v.A_C_1H   + H},
            {std::wstring(1, bangla::b_NGA)+ H, g_registry.v.A_NGA_1H + H},
            {std::wstring(1, bangla::b_s)  + H, g_registry.v.A_S_1H_1 + H},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    // d + hasanta
    {
        std::wstring out;
        out.reserve(convertedText_.size() + 8);
        size_t i = 0;
        const size_t n = convertedText_.size();
        while (i < n) {
            if (convertedText_[i] == bangla::b_d && i + 1 < n &&
                convertedText_[i + 1] == bangla::b_Hasanta) {
                if (i + 2 < n && convertedText_[i + 2] == bangla::b_g)
                    out.append(g_registry.v.A_D_1H_1);
                else
                    out.append(g_registry.v.A_D_1H_2);
                out.push_back(bangla::b_Hasanta);
                i += 2;
            } else {
                out.push_back(convertedText_[i]);
                ++i;
            }
        }
        convertedText_ = std::move(out);
    }
    // n + hasanta (elevate first-half N-forms)
    {
        std::wstring out;
        out.reserve(convertedText_.size() + 8);
        size_t i = 0;
        const size_t n = convertedText_.size();
        while (i < n) {
            if (convertedText_[i] == bangla::b_n && i + 1 < n &&
                convertedText_[i + 1] == bangla::b_Hasanta) {
                Char nxt = (i + 2 < n) ? convertedText_[i + 2] : 0;
                if (i + 2 < n &&
                    (nxt == bangla::b_t || nxt == bangla::b_Th || nxt == bangla::b_L ||
                     nxt == bangla::b_b || nxt == g_registry.v.A_T_R_2H[0] ||
                     nxt == g_registry.v.A_T_UKar_2H[0]))
                    out.append(g_registry.v.A_N_1H_1);
                else if (i + 2 < n && (nxt == bangla::b_m || nxt == bangla::b_n))
                    out.append(g_registry.v.A_N.substr(0, 1));
                else
                    out.append(g_registry.v.A_N_1H_2);
                out.push_back(bangla::b_Hasanta);
                i += 2;
            } else {
                out.push_back(convertedText_[i]);
                ++i;
            }
        }
        convertedText_ = std::move(out);
    }
}

void UnicodeToBijoy::secondHalfForms() {
    // Batch the simple second-half-form replacements into a single sweep.
    {
        const std::wstring H(1, bangla::b_Hasanta);
        std::vector<SweepEntry> entries = {
            {H + std::wstring(1, bangla::b_Bh), g_registry.v.A_BH_2H},
            {H + std::wstring(1, bangla::b_t),  g_registry.v.A_T_2H},
            {H + std::wstring(1, bangla::b_Th), g_registry.v.A_Th_2H},
            {H + std::wstring(1, bangla::b_K),  g_registry.v.A_K_2H},
        };
        // Delphi applies this unconditionally: A_P_2H carries the compiled-in
        // #$2219 default, so EVERY mapping turns hasanta+প into the প
        // second-half glyph.  The empty guard is only defensive.
        if (!g_registry.v.A_P_2H.empty())
            entries.push_back({H + std::wstring(1, bangla::b_p), g_registry.v.A_P_2H});
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    auto pickB2H = [&](Char wC) {
        if (wC == bangla::b_s || wC == bangla::b_ss || wC == bangla::b_m ||
            wC == bangla::b_n || wC == bangla::b_d ||
            wC == g_registry.v.A_M_1H[0] || wC == g_registry.v.A_Ss_1H[0] ||
            wC == g_registry.v.A_S_1H_1[0] || wC == g_registry.v.A_N_1H_1[0] ||
            wC == g_registry.v.A_D_1H_2[0])
            return g_registry.v.A_B_2H_1[0];
        if (wC == bangla::b_dh || wC == bangla::b_b || wC == bangla::b_h)
            return g_registry.v.A_B_2H_4[0];
        if (wC == bangla::b_sh || wC == bangla::b_g || wC == bangla::b_p)
            return g_registry.v.A_B_2H_3[0];
        return g_registry.v.A_B_2H_2[0];
    };
    auto pickM2H = [&](Char wC) {
        if (wC == g_registry.v.A_M_1H[0] || wC == g_registry.v.A_Ss_1H[0] ||
            wC == g_registry.v.A_C_1H[0] || wC == g_registry.v.A_S_1H_1[0] ||
            wC == g_registry.v.A_D_1H_2[0] || wC == g_registry.v.A_N_1H_1[0] ||
            wC == g_registry.v.A_N_1H_2[0])
            return g_registry.v.A_M_2H_2[0];
        if (wC == g_registry.v.A_NGA_1H[0])
            return g_registry.v.A_M[0];
        return g_registry.v.A_M_2H_1[0];
    };
    auto pickL2H = [&](Char wC) {
        if (baseLineRightCharacter(std::wstring(1, wC)))
            return g_registry.v.A_L_2H_3[0];
        return g_registry.v.A_L_2H_1[0];
    };

    auto scan = [&](Char pairChar, std::function<Char(Char)> pick) {
        std::wstring out;
        out.reserve(convertedText_.size() + 8);
        size_t i = 0;
        const size_t n = convertedText_.size();
        while (i < n) {
            if (convertedText_[i] == bangla::b_Hasanta && i + 1 < n &&
                convertedText_[i + 1] == pairChar) {
                Char wT = out.empty() ? 0 : out[out.size() - 1];
                out.push_back(pick(wT));
                i += 2;
            } else {
                out.push_back(convertedText_[i]);
                ++i;
            }
        }
        convertedText_ = std::move(out);
    };
    scan(bangla::b_b, pickB2H);
    scan(bangla::b_m, pickM2H);
    scan(bangla::b_L, pickL2H);

    {
        const std::wstring H(1, bangla::b_Hasanta);
        std::vector<SweepEntry> entries = {
            {H + std::wstring(1, bangla::b_Nn), g_registry.v.A_Nn_2H_1},
            {H + std::wstring(1, bangla::b_n),  g_registry.v.A_Nn_2H_2},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }
}

void UnicodeToBijoy::consonants() {
    std::vector<SweepEntry> entries(40);
    size_t e = 0;
    auto add = [&](Char key, const std::wstring& val) {
        entries[e++] = {std::wstring(1, key), val};
    };
    add(bangla::b_K, g_registry.v.A_K);
    add(bangla::b_kh, g_registry.v.A_Kh);
    add(bangla::b_g, g_registry.v.A_G);
    add(bangla::b_gh, g_registry.v.A_Gh);
    add(bangla::b_NGA, g_registry.v.A_NGA);
    add(bangla::b_C, g_registry.v.A_C);
    add(bangla::b_ch, g_registry.v.A_Ch);
    add(bangla::b_j, g_registry.v.A_J);
    add(bangla::b_jh, g_registry.v.A_Jh);
    add(bangla::b_nya, g_registry.v.A_NYA);
    add(bangla::b_tt, g_registry.v.A_Tt);
    add(bangla::b_tth, g_registry.v.A_Tth);
    add(bangla::b_dd, g_registry.v.A_Dd);
    add(bangla::b_ddh, g_registry.v.A_Ddh);
    add(bangla::b_Nn, g_registry.v.A_Nn);
    add(bangla::b_t, g_registry.v.A_T);
    add(bangla::b_Th, g_registry.v.A_Th);
    add(bangla::b_d, g_registry.v.A_D);
    add(bangla::b_dh, g_registry.v.A_Dh);
    add(bangla::b_n, g_registry.v.A_N);
    add(bangla::b_p, g_registry.v.A_P);
    add(bangla::b_ph, g_registry.v.A_Ph);
    add(bangla::b_b, g_registry.v.A_B);
    add(bangla::b_Bh, g_registry.v.A_Bh);
    add(bangla::b_m, g_registry.v.A_M);
    add(bangla::b_z, g_registry.v.A_Z);
    add(bangla::b_r, g_registry.v.A_R);
    add(bangla::b_L, g_registry.v.A_L);
    add(bangla::b_sh, g_registry.v.A_Sh);
    add(bangla::b_ss, g_registry.v.A_SS);
    add(bangla::b_s, g_registry.v.A_S);
    add(bangla::b_h, g_registry.v.A_H);
    add(bangla::b_y, g_registry.v.A_Y);
    add(bangla::b_rr, g_registry.v.A_RR);
    add(bangla::b_rrh, g_registry.v.A_RRH);
    add(bangla::b_Khandatta, g_registry.v.A_Khandata);
    add(bangla::b_Anushar, g_registry.v.A_Anushar);
    add(bangla::b_Bisharga, g_registry.v.A_Bisharga);
    add(bangla::b_Chandra, g_registry.v.A_Chandra);
    add(bangla::b_Dari, g_registry.v.A_Dari);
    SweepTable table(entries);
    convertedText_ = table.sweep(convertedText_);
}

void UnicodeToBijoy::finalTouch() {
    convertedText_ = replaceStr(
        convertedText_,
        std::wstring(1, bangla::b_Hasanta) + std::wstring(1, bangla::ZWNJ),
        g_registry.v.A_Hasanta);

    const size_t len = convertedText_.size();
    if (len > 0) {
        if (len >= 2 && convertedText_[len - 1] == bangla::b_Hasanta &&
            convertedText_[len - 2] == bangla::b_Hasanta) {
            convertedText_[len - 1] = g_registry.v.A_Hasanta[0];
            convertedText_[len - 2] = g_registry.v.A_Hasanta[0];
        } else if (convertedText_[len - 1] == bangla::b_Hasanta) {
            convertedText_[len - 1] = g_registry.v.A_Hasanta[0];
        }
    }

    // Remove all remaining Hasanta/ZWJ/ZWNJ in a single sweep.
    {
        std::vector<SweepEntry> entries = {
            {std::wstring(1, bangla::b_Hasanta), std::wstring()},
            {std::wstring(1, bangla::ZWJ),       std::wstring()},
            {std::wstring(1, bangla::ZWNJ),      std::wstring()},
        };
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    // Reph / Z-Fola / R-Fola <> kar glyph reordering in a single sweep.
    std::vector<SweepEntry> entries;
    entries.reserve(21);
    auto addSwap = [&](const std::wstring& aKey, const std::wstring& aValue) {
        if (aKey.empty() || aValue.empty() || aKey == aValue)
            return;
        entries.push_back({aKey, aValue});
    };
    const std::wstring& A_ZFola = g_registry.v.A_ZFola;
    const std::wstring& A_Reph = g_registry.v.A_Reph;
    const std::wstring& A_UKar1 = g_registry.v.A_UKar1;
    const std::wstring& A_UKar2 = g_registry.v.A_UKar2;
    const std::wstring& A_UKar3 = g_registry.v.A_UKar3;
    const std::wstring& A_UKar4 = g_registry.v.A_UKar4;
    const std::wstring& A_UUKar1 = g_registry.v.A_UUKar1;
    const std::wstring& A_UUKar2 = g_registry.v.A_UUKar2;
    const std::wstring& A_UUKar3 = g_registry.v.A_UUKar3;
    const std::wstring& A_RFola_1 = g_registry.v.A_RFola_1;
    const std::wstring& A_RFola_2 = g_registry.v.A_RFola_2;

    addSwap(A_ZFola + A_Reph, A_Reph + A_ZFola);
    addSwap(A_ZFola + A_UKar1, A_UKar1 + A_ZFola);
    addSwap(A_ZFola + A_UKar2, A_UKar2 + A_ZFola);
    addSwap(A_ZFola + A_UKar3, A_UKar3 + A_ZFola);
    addSwap(A_ZFola + A_UKar4, A_UKar4 + A_ZFola);
    addSwap(A_ZFola + A_UUKar1, A_UUKar1 + A_ZFola);
    addSwap(A_ZFola + A_UUKar2, A_UUKar2 + A_ZFola);
    addSwap(A_ZFola + A_UUKar3, A_UUKar3 + A_ZFola);
    addSwap(A_RFola_1 + A_UKar1, A_UKar1 + A_RFola_1);
    addSwap(A_RFola_1 + A_UUKar1, A_UUKar1 + A_RFola_1);
    addSwap(A_RFola_2 + A_UKar1, A_UKar1 + A_RFola_2);
    addSwap(A_RFola_2 + A_UUKar1, A_UUKar1 + A_RFola_2);
    addSwap(A_Reph + A_UKar1, A_UKar2 + A_Reph);
    addSwap(A_Reph + A_UKar2, A_UKar2 + A_Reph);
    addSwap(A_Reph + A_UKar3, A_UKar3 + A_Reph);
    addSwap(A_Reph + A_UKar4, A_UKar4 + A_Reph);
    addSwap(A_UKar1 + A_Reph, A_UKar2 + A_Reph);
    addSwap(A_Reph + A_UUKar1, A_UUKar2 + A_Reph);
    addSwap(A_Reph + A_UUKar2, A_UUKar2 + A_Reph);
    addSwap(A_Reph + A_UUKar3, A_UUKar3 + A_Reph);
    addSwap(A_UUKar1 + A_Reph, A_UUKar2 + A_Reph);
    SweepTable table(entries);
    convertedText_ = table.sweep(convertedText_);

    // Dynamic Post-processing Corrections (JSON-driven) - single sweep.
    if (!g_registry.karCorrections.empty()) {
        std::vector<SweepEntry> entries;
        entries.reserve(g_registry.karCorrections.size());
        for (const auto& kc : g_registry.karCorrections)
            entries.push_back({kc.charStr + kc.fromKar, kc.charStr + kc.toKar});
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }

    // STRICT SANITIZATION FOR ANSI OUTPUT
    std::wstring out;
    out.reserve(convertedText_.size());
    for (size_t i = 0; i < convertedText_.size(); ++i) {
        Char c = convertedText_[i];
        if (c >= 0x0980 && c <= 0x09FF)
            continue;
        if ((c >= 0x200B && c <= 0x200F) || c == 0xFEFF)
            continue;
        out.push_back(c);
    }
    convertedText_ = std::move(out);

    // Applying dynamic post-processing fixes (LAST) - single sweep.
    if (!g_registry.customPostReplacements.empty()) {
        std::vector<SweepEntry> entries;
        entries.reserve(g_registry.customPostReplacements.size());
        for (const auto& p : g_registry.customPostReplacements)
            entries.push_back({p.key, p.value});
        SweepTable table(entries);
        convertedText_ = table.sweep(convertedText_);
    }
}

void UnicodeToBijoy::replaceFullForms() {
    if (g_registry.activeReplacements.empty())
        return;
    std::vector<SweepEntry> entries;
    entries.reserve(g_registry.activeReplacements.size());
    for (const auto& p : g_registry.activeReplacements)
        entries.push_back({p.key, p.value});
    SweepTable table(entries);
    convertedText_ = table.sweep(convertedText_);
}

} // namespace avro
