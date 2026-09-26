// ansi_registry.h - the Bijoy ANSI glyph registry plus the JSON mapping
// loader.  Port of the registry half of clsUnicodeToBijoy2000.pas: holds the
// A_* glyph variables, the AnsiRegistry metadata table, AnsiOverrides,
// group maps, vowel/rfola/kar-correction rule arrays and the replacement
// tables (ActiveReplacements / KarInclusiveReplacements).

#pragma once

#include <functional>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace avro {

struct AnsiVars; // forward declaration (member-pointer usage below)

struct ReplacementPair {
    std::wstring key;
    std::wstring value;
    std::wstring comment;
};

struct VowelRuleMapping {
    std::wstring consonants;  // resolved (ProcessHexAndUnicode applied)
    std::wstring value;       // raw JSON string (ResolveValue applied at use)
    std::wstring alt;         // raw JSON string
    bool toggleOnBackspace = false;
    int matchMode = 0;        // 0 = Full Cluster, 1 = Last Char only
    std::wstring processPhase; // 'pre' / 'post' / ''
};

struct VowelRule {
    std::wstring karChar;
    std::wstring defaultVal;  // raw JSON string
    std::wstring toggle;      // 'none' / 'backspace' / ...
    bool toggleOnBackspace = false;
    std::vector<VowelRuleMapping> mappings;
};

struct RfolaRule {
    std::wstring consonants;
    std::wstring value;        // resolved
    std::wstring halfValue;    // resolved
    int replaceLen = 2;
    std::wstring contextGroup;
    int contextReplaceLen = 0;
    std::wstring contextValue; // resolved
    std::wstring rawValue, rawHalfValue, rawContextValue;
    std::wstring comment;
};

struct KarCorrection {
    std::wstring rawCharStr, charStr, rawFromKar, fromKar, rawToKar, toKar, comment;
};

struct GroupKarCorrection {
    std::wstring group, from, to_;
};

enum class AnsiVarType { Char, String };

// One registry entry.  `member` is a pointer-to-member into AnsiVars so a
// write through the registry lands on the real glyph variable, mirroring the
// Delphi PChar/PString indirection.
struct AnsiVarRec {
    std::wstring name;
    std::wstring category;
    AnsiVarType varType;
    std::wstring AnsiVars::*member = nullptr;
    std::wstring defaultVal;   // raw ('#$30' style)
    std::wstring bengaliChar;  // raw Bengali key ('০' style)
    std::wstring comment;
};

// All A_* glyph variables (default-mapping values).  The registry can
// overwrite them (ResetAnsiToDefaults / JSON Constants).
struct AnsiVars {
    // Numbers
    std::wstring A_0 = L"\x30", A_1 = L"\x31", A_2 = L"\x32", A_3 = L"\x33",
                 A_4 = L"\x34", A_5 = L"\x35", A_6 = L"\x36", A_7 = L"\x37",
                 A_8 = L"\x38", A_9 = L"\x39";
    // Vowels and Kars
    std::wstring A_A = L"\x41", A_AA = L"\x41\x76", A_AAKar = L"\x76",
                 A_I = L"\x42", A_IKar = L"\x77", A_II = L"\x43",
                 A_IIKar = L"\x78", A_U = L"\x44", A_UKar2 = L"\x79",
                 A_UKar1 = L"\x7A", A_UKar3 = L"\x2013", A_UKar4 = L"\x201C",
                 A_UU = L"\x45", A_UUKar2 = L"\x7E", A_UUKar1 = L"\x201A",
                 A_UUKar3 = L"\x192", A_RRI = L"\x46", A_RRIKar1 = L"\x201E",
                 A_RRIKar2 = L"\x2026", A_E = L"\x47", A_EKar1 = L"\x2020",
                 A_EKar2 = L"\x2021", A_OI = L"\x48", A_OIKar1 = L"\x2C6",
                 A_OIKar2 = L"\x2030", A_O = L"\x49", A_OU = L"\x4A",
                 A_OUKar = L"\x160";
    // Symbols
    std::wstring A_Taka = L"\x24", A_Dari = L"\x7C", A_DoubleDanda = L"\x5C",
                 A_Hasanta = L"\x26", A_StartDoubleQuote = L"\xD2",
                 A_EndDoubleQuote = L"\xD3", A_StartSingleQuote = L"\xD4",
                 A_EndSingleQuote = L"\xD5";
    // Consonants
    std::wstring A_K = L"\x4B", A_Kh = L"\x4C", A_G = L"\x4D", A_Gh = L"\x4E",
                 A_NGA = L"\x4F", A_C = L"\x50", A_Ch = L"\x51", A_J = L"\x52",
                 A_Jh = L"\x53", A_NYA = L"\x54", A_Tt = L"\x55", A_Tth = L"\x56",
                 A_Dd = L"\x57", A_Ddh = L"\x58", A_Nn = L"\x59", A_T = L"\x5A",
                 A_Th = L"\x5F", A_D = L"\x60", A_Dh = L"\x61", A_N = L"\x62",
                 A_P = L"\x63", A_Ph = L"\x64", A_B = L"\x65", A_Bh = L"\x66",
                 A_M = L"\x67", A_Z = L"\x68", A_R = L"\x69", A_L = L"\x6A",
                 A_Sh = L"\x6B", A_SS = L"\x6C", A_S = L"\x6D", A_H = L"\x6E",
                 A_RR = L"\x6F", A_RRH = L"\x70", A_Y = L"\x71",
                 A_Khandata = L"\x72", A_Anushar = L"\x73", A_Bisharga = L"\x74",
                 A_Chandra = L"\x75";
    // Full Forms
    std::wstring A_K_K = L"\xB0", A_K_Tt = L"\xB1", A_K_Ss_M = L"\xB2",
                 A_K_T = L"\xB3", A_K_M = L"\xB4", A_K_R = L"\xB5",
                 A_K_Ss = L"\xB6", A_K_S = L"\xB7", A_G_Ukar = L"\xB8",
                 A_G_G = L"\xB9", A_G_D = L"\xBA", A_G_Dh = L"\xBB",
                 A_NGA_K = L"\xBC", A_NGA_G = L"\xBD", A_J_J = L"\xBE",
                 A_J_Jh = L"\xC0", A_J_NYA = L"\xC1", A_NYA_C = L"\xC2",
                 A_NYA_CH = L"\xC3", A_NYA_J = L"\xC4", A_NYA_Jh = L"\xC5",
                 A_Tt_Tt = L"\xC6", A_Dd_Dd = L"\xC7", A_Nn_Tt = L"\xC8",
                 A_Nn_Tth = L"\xC9", A_NN_Dd = L"\xCA", A_T_T = L"\xCB",
                 A_T_Th = L"\xCC", A_T_M = L"\xCD", A_T_R = L"\xCE",
                 A_D_D = L"\xCF", A_D_Dh = L"\xD7", A_D_B = L"\xD8",
                 A_D_M = L"\xD9", A_N_Tth = L"\xDA", A_N_Dd = L"\xDB",
                 A_N_Dh = L"\xDC", A_N_S = L"\xDD", A_P_Tt = L"\xDE",
                 A_P_T = L"\xDF", A_P_P = L"\xE0", A_P_S = L"\xE1",
                 A_B_J = L"\xE2", A_B_D = L"\xE3", A_B_Dh = L"\xE4",
                 A_Bh_R = L"\xE5", A_M_N = L"\xE6", A_M_Ph = L"\xE7",
                 A_L_K = L"\xE9", A_L_G = L"\xEA", A_L_Tt = L"\xEB",
                 A_L_Dd = L"\xEC", A_L_P = L"\xED", A_L_Ph = L"\xEE",
                 A_Sh_UKar = L"\xEF", A_Sh_C = L"\xF0", A_Sh_Ch = L"\xF1",
                 A_Ss_Nn = L"\xF2", A_Ss_Tt = L"\xF3", A_Ss_Tth = L"\xF4",
                 A_Ss_Ph = L"\xF5", A_S_Kh = L"\xF6", A_S_Tt = L"\xF7",
                 A_S_N = L"\xF8", A_S_Ph = L"\xF9", A_H_UKar = L"\xFB",
                 A_H_RRIKar = L"\xFC", A_H_N = L"\xFD", A_H_M = L"\xFE",
                 A_Rr_G = L"\xFF";
    // First Half forms
    std::wstring A_Reph = L"\xA9", A_M_1H = L"\xA4", A_Ss_1H = L"\xAE",
                 A_S_1H_1 = L"\xAF", A_N_1H_1 = L"\x161", A_S_1H_2 = L"\x2C9",
                 A_D_1H_1 = L"\x2DC", A_C_1H = L"\x201D", A_NGA_1H = L"\x2022",
                 A_N_1H_2 = L"\x203A", A_D_1H_2 = L"\x2122";
    // Second Half forms
    std::wstring A_B_2H_1 = L"\x5E", A_B_2H_2 = L"\xA1", A_BH_2H = L"\xA2",
                 A_BH_R_2H = L"\xA3", A_M_2H_1 = L"\xA5", A_B_2H_3 = L"\xA6",
                 A_M_2H_2 = L"\xA7", A_ZFola = L"\xA8", A_RFola_1 = L"\xAA",
                 A_RFola_2 = L"\xAB", A_L_2H_1 = L"\xAC", A_L_2H_2 = L"\xAD",
                 A_T_R_2H = L"\xBF", A_RFola_3 = L"\xD6", A_Nn_2H_1 = L"\xE8",
                 A_K_R_2H = L"\x152", A_Nn_2H_2 = L"\x153", A_B_2H_4 = L"\x178",
                 A_T_2H = L"\x2014", A_T_UKar_2H = L"\x2018", A_Th_2H = L"\x2019",
                 A_K_2H = L"\x2039", A_L_2H_3 = L"\x2212",
                 // Glyph variables introduced by Ansi V4, mirroring the Delphi
                 // typed constants exactly - including their compiled-in values:
                 // A_P_2H is substituted for hasanta+p in EVERY mapping, and the
                 // r-fola 4/5/6 values are what #{A_RFola_4/5/6} resolve to.
                 A_P_2H = L"\x2219", A_RFola_4 = L"\xC7",
                 A_RFola_5 = L"\xCB", A_RFola_6 = L"\xCC";
};

class AnsiRegistry {
public:
    AnsiVars v;

    // Current state: the active folder mapping's name - empty until one has
    // been selected (the built-in base tables stay active until then).
    std::wstring ansiVersion;
    std::wstring ansiMappingDir;

    // Metadata / state
    std::vector<AnsiVarRec> registry;
    std::map<std::wstring, AnsiVarRec> registryMap;
    std::map<std::wstring, std::wstring> overrides;
    // Registry names in the exact enumeration order of the Delphi
    // TDictionary<string, TAnsiVarRec>.  The reverse converter's
    // first-claim-wins table build iterates the registry, so glyph
    // collisions (e.g. Ansi V3: A_UKar2 and A_Taka both '\x24') resolve
    // exactly as the Delphi app resolves them.
    std::vector<std::wstring> registryOrder;

    // Replacement tables
    std::vector<ReplacementPair> customFullForms;
    std::vector<ReplacementPair> customPreReplacements;
    std::vector<ReplacementPair> customPostReplacements;
    std::vector<ReplacementPair> activeReplacements;
    std::vector<ReplacementPair> karInclusiveReplacements;

    // Rules and groups
    std::vector<VowelRule> vowelRules;
    std::vector<RfolaRule> rfolaRules;
    std::vector<KarCorrection> karCorrections;
    std::vector<GroupKarCorrection> groupKarCorrections;
    std::map<std::wstring, std::vector<std::wstring>> consonantGroupMap;
    std::map<std::wstring, std::vector<std::wstring>> consonantGroupRawMap;
    std::map<std::wstring, std::vector<std::wstring>> ansiGroupMap;
    std::map<std::wstring, std::vector<std::wstring>> ansiGroupRawMap;

    AnsiRegistry();
    void init(); // EnsureAnsiRegistry + EnsureAnsiOverrides

    // Value resolution helpers
    std::wstring getAnsiVarValue(const std::wstring& name) const;
    void setAnsiVarValue(const std::wstring& name, const std::wstring& value);

    // Public API (mirrors the unit-level procedures)
    void resetToDefaults();
    bool loadAnsiMapping(const std::wstring& path, std::vector<std::wstring>* errorLog = nullptr);
    void loadCurrentActiveMapping(std::vector<std::wstring>* errorLog = nullptr);
    bool trySetAnsiVersion(const std::wstring& newVersion, std::wstring& errorMessage);
    bool validateAnsiMappingFile(const std::wstring& path, std::wstring& errorMessage);
    void prepareActiveReplacements();

    // Group helpers used by the converter
    bool charInGroup(const std::wstring& ch, const std::wstring& groupName) const;
    int matchGroupLength(const std::wstring& fullText, int charIndex, const std::wstring& groupName) const;
    static bool hasHasantaBefore(const std::wstring& text, int pos); // 1-based pos

    std::wstring resolveValue(const std::wstring& s);      // ResolveValue
    void clearResolveCache(); // call after overrides change
    static std::wstring processHexAndUnicode(const std::wstring& s);

private:
    void buildRegistry();
    void parseJson(const std::wstring& json, std::vector<std::wstring>* errorLog);
    // Cache for resolveValue() — same input always yields the same output
    // within a single mapping version, so caching avoids redundant
    // processHexAndUnicode + variable-substitution parsing.
    std::map<std::wstring, std::wstring> resolveCache_;
};

// Shared instance (mirrors the unit-level global variables).
extern AnsiRegistry g_registry;

// Free helpers mirroring unit-level functions.
int countOccurrences(const std::wstring& sub, const std::wstring& s);

} // namespace avro
