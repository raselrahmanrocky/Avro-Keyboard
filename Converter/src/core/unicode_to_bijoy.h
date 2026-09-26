// unicode_to_bijoy.h - Unicode (Bengali) -> Bijoy ANSI conversion.
// Port of TUnicodeToBijoy2000 from clsUnicodeToBijoy2000.pas.  Uses the
// shared AnsiRegistry for glyph values, rules and replacement tables, so
// JSON-driven mappings (Ansi V3, SutonnyMJ, BanglaPedia) work identically.

#pragma once

#include <functional>
#include <map>
#include <string>
#include <string_view>

#include "ansi_registry.h"
#include "bangla_chars.h"

namespace avro {

struct ClusterMatchInfo {
    std::wstring matchedCluster;
    VowelRuleMapping bestMapping;
    int bestMatchLen = 0;
    int contextEnd = 0;
    bool isZfola = false;
};

class UnicodeToBijoy {
public:
    using ProgressCallback = std::function<void(int percent, const std::wstring& stage)>;

    ProgressCallback onProgress;

    std::wstring convert(std::wstring_view uniText);

private:
    std::wstring uniText_;
    std::wstring convertedText_;
    std::map<std::wstring, bool> toggleStates_;
    std::wstring lastUniText_;

    void reportProgress(int percent, const std::wstring& stage);

    void reArrangeKars();
    void reArrangeReph();
    void replaceFullForms();
    void applyKarInclusiveFullForms();
    void applyVowelKars();
    void replaceKarsVowels();
    void convertRFolaZFolaHasanta();
    void firstHalfForms();
    void secondHalfForms();
    void consonants();
    void finalTouch();
    void deNormalize();
    void replaceNumbers();
    void applyRuleForKar(const std::wstring& karChar, const std::wstring& phase = std::wstring());

    bool baseLineRightCharacter(const std::wstring& wc) const;
    bool isVowel(bangla::Char c) const;
    bool getToggleState(const std::wstring& context, const std::wstring& key,
                        int occurrenceIndex) const;
    void setToggleState(const std::wstring& context, const std::wstring& key,
                        int occurrenceIndex, bool value);
    bool ruleHasAnyToggle(const VowelRule& rule) const;
    bool findMappingToggle(const VowelRule& rule, const std::wstring& consonantPart,
                           bool& mappingToggleOnBackspace,
                           std::wstring& matchedCluster) const;
    ClusterMatchInfo findBestClusterMatch(const std::wstring& text, int karPos,
                                          const VowelRule& rule) const;
};

} // namespace avro
