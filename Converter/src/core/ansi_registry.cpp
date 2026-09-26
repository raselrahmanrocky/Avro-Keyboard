#include "ansi_registry.h"

#include "avroenco_reader.h"

#include <algorithm>
#include <cctype>
#include <cwctype>
#include <fstream>
#include <sstream>

namespace avro {

// Short-hand used by the registry table (matches the enum values).
static const AnsiVarType String = AnsiVarType::String;
static const AnsiVarType Char = AnsiVarType::Char;

AnsiRegistry g_registry;

AnsiRegistry::AnsiRegistry() {}

void AnsiRegistry::init() {
    if (registry.empty())
        buildRegistry();
}

static bool isHexDigit(wchar_t c) {
    return (c >= L'0' && c <= L'9') || (c >= L'A' && c <= L'F') ||
           (c >= L'a' && c <= L'f');
}

static int hexVal(wchar_t c) {
    if (c >= L'0' && c <= L'9') return c - L'0';
    if (c >= L'A' && c <= L'F') return c - L'A' + 10;
    return c - L'a' + 10;
}

std::wstring AnsiRegistry::processHexAndUnicode(const std::wstring& s) {
    std::wstring out;
    out.reserve(s.size());
    size_t i = 0;
    const size_t n = s.size();
    while (i < n) {
        if (i + 1 < n && s[i] == L'#' && s[i + 1] == L'$') {
            int code = 0;
            i += 2;
            while (i < n && isHexDigit(s[i])) {
                code = code * 16 + hexVal(s[i]);
                ++i;
            }
            out.push_back(static_cast<wchar_t>(code));
        } else {
            out.push_back(s[i]);
            ++i;
        }
    }
    return out;
}

std::wstring AnsiRegistry::getAnsiVarValue(const std::wstring& name) const {
    auto it = overrides.find(name);
    if (it != overrides.end())
        return it->second;
    auto mit = registryMap.find(name);
    if (mit != registryMap.end() && mit->second.member)
        return v.*(mit->second.member);
    return std::wstring();
}

void AnsiRegistry::setAnsiVarValue(const std::wstring& name, const std::wstring& value) {
    auto mit = registryMap.find(name);
    if (mit == registryMap.end())
        return;
    if (mit->second.varType == AnsiVarType::Char) {
        if (value.size() == 1)
            v.*(mit->second.member) = value;
        else
            overrides[name] = value; // multi-char cannot fit a Char var
    } else {
        v.*(mit->second.member) = value;
    }
}

std::wstring AnsiRegistry::resolveValue(const std::wstring& s) {
    // Fast path: check the cache first.  The same raw JSON value string
    // always resolves to the same ANSI glyph within a single mapping
    // version, and resolveValue() is called thousands of times per
    // conversion (once per kar character in applyRuleForKar).
    auto it = resolveCache_.find(s);
    if (it != resolveCache_.end())
        return it->second;

    std::wstring result = processHexAndUnicode(s);
    size_t i = 0;
    while (i < result.size()) {
        if (i + 1 < result.size() && result[i] == L'#' && result[i + 1] == L'#')
            ++i; // Fallback to handle possible syntax anomalies
        if (i + 1 < result.size() && result[i] == L'#' && result[i + 1] == L'{') {
            size_t j = i + 2;
            while (j < result.size() && result[j] != L'}')
                ++j;
            if (j < result.size()) {
                std::wstring varName = result.substr(i + 2, j - i - 2);
                std::wstring varVal = getAnsiVarValue(varName);
                result = result.substr(0, i) + varVal + result.substr(j + 1);
                i = i + varVal.size();
                continue;
            } else {
                ++i;
            }
        } else {
            ++i;
        }
    }
    resolveCache_[s] = result;
    return result;
}

void AnsiRegistry::clearResolveCache() {
    resolveCache_.clear();
}

int countOccurrences(const std::wstring& sub, const std::wstring& s) {
    if (sub.empty() || s.empty())
        return 0;
    int result = 0;
    size_t pos = 0;
    while (true) {
        size_t hit = s.find(sub, pos);
        if (hit == std::wstring::npos)
            break;
        ++result;
        pos = hit + sub.size();
    }
    return result;
}

// ---------------------------------------------------------------------------
// Registry table
// ---------------------------------------------------------------------------

void AnsiRegistry::buildRegistry() {
    auto reg = [this](const wchar_t* name, const wchar_t* cat, AnsiVarType t,
                      std::wstring AnsiVars::*m, const wchar_t* def,
                      const wchar_t* beng) {
        AnsiVarRec r;
        r.name = name;
        r.category = cat;
        r.varType = t;
        r.member = m;
        r.defaultVal = def;
        r.bengaliChar = beng;
        r.comment = beng;
        registry.push_back(r);
        registryMap[r.name] = r;
    };

    // Numbers
    reg(L"A_0", L"Numbers", String, &AnsiVars::A_0, L"#$30", L"\x9E6");
    reg(L"A_1", L"Numbers", String, &AnsiVars::A_1, L"#$31", L"\x9E7");
    reg(L"A_2", L"Numbers", String, &AnsiVars::A_2, L"#$32", L"\x9E8");
    reg(L"A_3", L"Numbers", String, &AnsiVars::A_3, L"#$33", L"\x9E9");
    reg(L"A_4", L"Numbers", String, &AnsiVars::A_4, L"#$34", L"\x9EA");
    reg(L"A_5", L"Numbers", String, &AnsiVars::A_5, L"#$35", L"\x9EB");
    reg(L"A_6", L"Numbers", String, &AnsiVars::A_6, L"#$36", L"\x9EC");
    reg(L"A_7", L"Numbers", String, &AnsiVars::A_7, L"#$37", L"\x9ED");
    reg(L"A_8", L"Numbers", String, &AnsiVars::A_8, L"#$38", L"\x9EE");
    reg(L"A_9", L"Numbers", String, &AnsiVars::A_9, L"#$39", L"\x9EF");
    // VowelsAndKars
    reg(L"A_A", L"VowelsAndKars", Char, &AnsiVars::A_A, L"#$41", L"\x985");
    reg(L"A_AA", L"VowelsAndKars", String, &AnsiVars::A_AA, L"#$41#$76", L"\x986");
    reg(L"A_AAKar", L"VowelsAndKars", Char, &AnsiVars::A_AAKar, L"#$76", L"\x9BE");
    reg(L"A_I", L"VowelsAndKars", Char, &AnsiVars::A_I, L"#$42", L"\x987");
    reg(L"A_IKar", L"VowelsAndKars", Char, &AnsiVars::A_IKar, L"#$77", L"\x9BF");
    reg(L"A_II", L"VowelsAndKars", Char, &AnsiVars::A_II, L"#$43", L"\x988");
    reg(L"A_IIKar", L"VowelsAndKars", Char, &AnsiVars::A_IIKar, L"#$78", L"\x9C0");
    reg(L"A_U", L"VowelsAndKars", Char, &AnsiVars::A_U, L"#$44", L"\x989");
    reg(L"A_UKar2", L"VowelsAndKars", Char, &AnsiVars::A_UKar2, L"#$79", L"\x9C1");
    reg(L"A_UKar1", L"VowelsAndKars", Char, &AnsiVars::A_UKar1, L"#$7A", L"\x9C1");
    reg(L"A_UKar3", L"VowelsAndKars", Char, &AnsiVars::A_UKar3, L"#$2013", L"\x9C1");
    reg(L"A_UKar4", L"VowelsAndKars", Char, &AnsiVars::A_UKar4, L"#$201C", L"\x9C1");
    reg(L"A_UU", L"VowelsAndKars", Char, &AnsiVars::A_UU, L"#$45", L"\x98A");
    reg(L"A_UUKar2", L"VowelsAndKars", Char, &AnsiVars::A_UUKar2, L"#$7E", L"\x9C2");
    reg(L"A_UUKar1", L"VowelsAndKars", Char, &AnsiVars::A_UUKar1, L"#$201A", L"\x9C2");
    reg(L"A_UUKar3", L"VowelsAndKars", Char, &AnsiVars::A_UUKar3, L"#$192", L"\x9C2");
    reg(L"A_RRI", L"VowelsAndKars", Char, &AnsiVars::A_RRI, L"#$46", L"\x98B");
    reg(L"A_RRIKar1", L"VowelsAndKars", Char, &AnsiVars::A_RRIKar1, L"#$201E", L"\x9C3");
    reg(L"A_RRIKar2", L"VowelsAndKars", Char, &AnsiVars::A_RRIKar2, L"#$2026", L"\x9C3");
    reg(L"A_E", L"VowelsAndKars", Char, &AnsiVars::A_E, L"#$47", L"\x98F");
    reg(L"A_EKar1", L"VowelsAndKars", Char, &AnsiVars::A_EKar1, L"#$2020", L"\x9C7");
    reg(L"A_EKar2", L"VowelsAndKars", Char, &AnsiVars::A_EKar2, L"#$2021", L"\x9C7");
    reg(L"A_OI", L"VowelsAndKars", Char, &AnsiVars::A_OI, L"#$48", L"\x990");
    reg(L"A_OIKar1", L"VowelsAndKars", Char, &AnsiVars::A_OIKar1, L"#$2C6", L"\x9C8");
    reg(L"A_OIKar2", L"VowelsAndKars", Char, &AnsiVars::A_OIKar2, L"#$2030", L"\x9C8");
    reg(L"A_O", L"VowelsAndKars", Char, &AnsiVars::A_O, L"#$49", L"\x993");
    reg(L"A_OU", L"VowelsAndKars", Char, &AnsiVars::A_OU, L"#$4A", L"\x994");
    reg(L"A_OUKar", L"VowelsAndKars", Char, &AnsiVars::A_OUKar, L"#$160", L"\x9CC");
    // Symbols
    reg(L"A_Taka", L"Symbols", String, &AnsiVars::A_Taka, L"#$24", L"\x9F3");
    reg(L"A_Dari", L"Symbols", String, &AnsiVars::A_Dari, L"#$7C", L"\x964");
    reg(L"A_DoubleDanda", L"Symbols", String, &AnsiVars::A_DoubleDanda, L"#$5C", L"\x965");
    reg(L"A_Hasanta", L"Symbols", String, &AnsiVars::A_Hasanta, L"#$26", L"\x9CD");
    reg(L"A_StartDoubleQuote", L"Symbols", String, &AnsiVars::A_StartDoubleQuote, L"#$D2", L"\x22");
    reg(L"A_EndDoubleQuote", L"Symbols", String, &AnsiVars::A_EndDoubleQuote, L"#$D3", L"\x22");
    reg(L"A_StartSingleQuote", L"Symbols", String, &AnsiVars::A_StartSingleQuote, L"#$D4", L"\x27");
    reg(L"A_EndSingleQuote", L"Symbols", String, &AnsiVars::A_EndSingleQuote, L"#$D5", L"\x27");
    // Consonants
    reg(L"A_K", L"Consonants", String, &AnsiVars::A_K, L"#$4B", L"\x995");
    reg(L"A_Kh", L"Consonants", String, &AnsiVars::A_Kh, L"#$4C", L"\x996");
    reg(L"A_G", L"Consonants", String, &AnsiVars::A_G, L"#$4D", L"\x997");
    reg(L"A_Gh", L"Consonants", String, &AnsiVars::A_Gh, L"#$4E", L"\x998");
    reg(L"A_NGA", L"Consonants", String, &AnsiVars::A_NGA, L"#$4F", L"\x999");
    reg(L"A_C", L"Consonants", String, &AnsiVars::A_C, L"#$50", L"\x99A");
    reg(L"A_Ch", L"Consonants", String, &AnsiVars::A_Ch, L"#$51", L"\x99B");
    reg(L"A_J", L"Consonants", String, &AnsiVars::A_J, L"#$52", L"\x99C");
    reg(L"A_Jh", L"Consonants", String, &AnsiVars::A_Jh, L"#$53", L"\x99D");
    reg(L"A_NYA", L"Consonants", String, &AnsiVars::A_NYA, L"#$54", L"\x99E");
    reg(L"A_Tt", L"Consonants", String, &AnsiVars::A_Tt, L"#$55", L"\x99F");
    reg(L"A_Tth", L"Consonants", String, &AnsiVars::A_Tth, L"#$56", L"\x9A0");
    reg(L"A_Dd", L"Consonants", String, &AnsiVars::A_Dd, L"#$57", L"\x9A1");
    reg(L"A_Ddh", L"Consonants", String, &AnsiVars::A_Ddh, L"#$58", L"\x9A2");
    reg(L"A_Nn", L"Consonants", String, &AnsiVars::A_Nn, L"#$59", L"\x9A3");
    reg(L"A_T", L"Consonants", String, &AnsiVars::A_T, L"#$5A", L"\x9A4");
    reg(L"A_Th", L"Consonants", String, &AnsiVars::A_Th, L"#$5F", L"\x9A5");
    reg(L"A_D", L"Consonants", String, &AnsiVars::A_D, L"#$60", L"\x9A6");
    reg(L"A_Dh", L"Consonants", String, &AnsiVars::A_Dh, L"#$61", L"\x9A7");
    reg(L"A_N", L"Consonants", String, &AnsiVars::A_N, L"#$62", L"\x9A8");
    reg(L"A_P", L"Consonants", String, &AnsiVars::A_P, L"#$63", L"\x9AA");
    reg(L"A_Ph", L"Consonants", String, &AnsiVars::A_Ph, L"#$64", L"\x9AB");
    reg(L"A_B", L"Consonants", String, &AnsiVars::A_B, L"#$65", L"\x9AC");
    reg(L"A_Bh", L"Consonants", String, &AnsiVars::A_Bh, L"#$66", L"\x9AD");
    reg(L"A_M", L"Consonants", String, &AnsiVars::A_M, L"#$67", L"\x9AE");
    reg(L"A_Z", L"Consonants", String, &AnsiVars::A_Z, L"#$68", L"\x9AF");
    reg(L"A_R", L"Consonants", String, &AnsiVars::A_R, L"#$69", L"\x9B0");
    reg(L"A_L", L"Consonants", String, &AnsiVars::A_L, L"#$6A", L"\x9B2");
    reg(L"A_Sh", L"Consonants", String, &AnsiVars::A_Sh, L"#$6B", L"\x9B6");
    reg(L"A_SS", L"Consonants", String, &AnsiVars::A_SS, L"#$6C", L"\x9B7");
    reg(L"A_S", L"Consonants", String, &AnsiVars::A_S, L"#$6D", L"\x9B8");
    reg(L"A_H", L"Consonants", String, &AnsiVars::A_H, L"#$6E", L"\x9B9");
    reg(L"A_RR", L"Consonants", String, &AnsiVars::A_RR, L"#$6F", L"\x9DC");
    reg(L"A_RRH", L"Consonants", String, &AnsiVars::A_RRH, L"#$70", L"\x9DD");
    reg(L"A_Y", L"Consonants", String, &AnsiVars::A_Y, L"#$71", L"\x9DF");
    reg(L"A_Khandata", L"Consonants", String, &AnsiVars::A_Khandata, L"#$72", L"\x9CE");
    reg(L"A_Anushar", L"Consonants", String, &AnsiVars::A_Anushar, L"#$73", L"\x982");
    reg(L"A_Bisharga", L"Consonants", String, &AnsiVars::A_Bisharga, L"#$74", L"\x983");
    reg(L"A_Chandra", L"Consonants", String, &AnsiVars::A_Chandra, L"#$75", L"\x981");
    // FullForms
    reg(L"A_K_K", L"FullForms", String, &AnsiVars::A_K_K, L"#$B0", L"\x995\x9CD\x995");
    reg(L"A_K_Tt", L"FullForms", String, &AnsiVars::A_K_Tt, L"#$B1", L"\x995\x9CD\x99F");
    reg(L"A_K_Ss_M", L"FullForms", String, &AnsiVars::A_K_Ss_M, L"#$B2", L"\x995\x9CD\x9B8\x9CD\x9AE");
    reg(L"A_K_T", L"FullForms", String, &AnsiVars::A_K_T, L"#$B3", L"\x995\x9CD\x9A4");
    reg(L"A_K_M", L"FullForms", String, &AnsiVars::A_K_M, L"#$B4", L"\x995\x9CD\x9AE");
    reg(L"A_K_R", L"FullForms", String, &AnsiVars::A_K_R, L"#$B5", L"\x995\x9CD\x9B0");
    reg(L"A_K_Ss", L"FullForms", String, &AnsiVars::A_K_Ss, L"#$B6", L"\x995\x9CD\x9B7");
    reg(L"A_K_S", L"FullForms", String, &AnsiVars::A_K_S, L"#$B7", L"\x995\x9CD\x9B8");
    reg(L"A_G_Ukar", L"FullForms", String, &AnsiVars::A_G_Ukar, L"#$B8", L"\x997\x9C1");
    reg(L"A_G_G", L"FullForms", String, &AnsiVars::A_G_G, L"#$B9", L"\x997\x9CD\x997");
    reg(L"A_G_D", L"FullForms", String, &AnsiVars::A_G_D, L"#$BA", L"\x997\x9CD\x9A6");
    reg(L"A_G_Dh", L"FullForms", String, &AnsiVars::A_G_Dh, L"#$BB", L"\x997\x9CD\x9A7");
    reg(L"A_NGA_K", L"FullForms", String, &AnsiVars::A_NGA_K, L"#$BC", L"\x999\x9CD\x995");
    reg(L"A_NGA_G", L"FullForms", String, &AnsiVars::A_NGA_G, L"#$BD", L"\x999\x9CD\x997");
    reg(L"A_J_J", L"FullForms", String, &AnsiVars::A_J_J, L"#$BE", L"\x99C\x9CD\x99C");
    reg(L"A_J_Jh", L"FullForms", String, &AnsiVars::A_J_Jh, L"#$C0", L"\x99C\x9CD\x99D");
    reg(L"A_J_NYA", L"FullForms", String, &AnsiVars::A_J_NYA, L"#$C1", L"\x99C\x9CD\x99E");
    reg(L"A_NYA_C", L"FullForms", String, &AnsiVars::A_NYA_C, L"#$C2", L"\x99E\x9CD\x99A");
    reg(L"A_NYA_CH", L"FullForms", String, &AnsiVars::A_NYA_CH, L"#$C3", L"\x99E\x9CD\x99B");
    reg(L"A_NYA_J", L"FullForms", String, &AnsiVars::A_NYA_J, L"#$C4", L"\x99E\x9CD\x99C");
    reg(L"A_NYA_Jh", L"FullForms", String, &AnsiVars::A_NYA_Jh, L"#$C5", L"\x99E\x9CD\x99D");
    reg(L"A_Tt_Tt", L"FullForms", String, &AnsiVars::A_Tt_Tt, L"#$C6", L"\x99F\x9CD\x99F");
    reg(L"A_Dd_Dd", L"FullForms", String, &AnsiVars::A_Dd_Dd, L"#$C7", L"\x9A1\x9CD\x9A1");
    reg(L"A_Nn_Tt", L"FullForms", String, &AnsiVars::A_Nn_Tt, L"#$C8", L"\x9A3\x9CD\x99F");
    reg(L"A_Nn_Tth", L"FullForms", String, &AnsiVars::A_Nn_Tth, L"#$C9", L"\x9A3\x9CD\x9A0");
    reg(L"A_NN_Dd", L"FullForms", String, &AnsiVars::A_NN_Dd, L"#$CA", L"\x9A3\x9CD\x9A1");
    reg(L"A_T_T", L"FullForms", String, &AnsiVars::A_T_T, L"#$CB", L"\x9A4\x9CD\x9A4");
    reg(L"A_T_Th", L"FullForms", String, &AnsiVars::A_T_Th, L"#$CC", L"\x9A4\x9CD\x9A5");
    reg(L"A_T_M", L"FullForms", String, &AnsiVars::A_T_M, L"#$CD", L"\x9A4\x9CD\x9AE");
    reg(L"A_T_R", L"FullForms", String, &AnsiVars::A_T_R, L"#$CE", L"\x9A4\x9CD\x9B0");
    reg(L"A_D_D", L"FullForms", String, &AnsiVars::A_D_D, L"#$CF", L"\x9A6\x9CD\x9A6");
    reg(L"A_D_Dh", L"FullForms", String, &AnsiVars::A_D_Dh, L"#$D7", L"\x9A6\x9CD\x9A7");
    reg(L"A_D_B", L"FullForms", String, &AnsiVars::A_D_B, L"#$D8", L"\x9A6\x9CD\x9AC");
    reg(L"A_D_M", L"FullForms", String, &AnsiVars::A_D_M, L"#$D9", L"\x9A6\x9CD\x9AE");
    reg(L"A_N_Tth", L"FullForms", String, &AnsiVars::A_N_Tth, L"#$DA", L"\x9A8\x9CD\x9A5");
    reg(L"A_N_Dd", L"FullForms", String, &AnsiVars::A_N_Dd, L"#$DB", L"\x9A8\x9CD\x9A1");
    reg(L"A_N_Dh", L"FullForms", String, &AnsiVars::A_N_Dh, L"#$DC", L"\x9A8\x9CD\x9A7");
    reg(L"A_N_S", L"FullForms", String, &AnsiVars::A_N_S, L"#$DD", L"\x9A8\x9CD\x9B8");
    reg(L"A_P_Tt", L"FullForms", String, &AnsiVars::A_P_Tt, L"#$DE", L"\x9AA\x9CD\x99F");
    reg(L"A_P_T", L"FullForms", String, &AnsiVars::A_P_T, L"#$DF", L"\x9AA\x9CD\x9A4");
    reg(L"A_P_P", L"FullForms", String, &AnsiVars::A_P_P, L"#$E0", L"\x9AA\x9CD\x9AA");
    reg(L"A_P_S", L"FullForms", String, &AnsiVars::A_P_S, L"#$E1", L"\x9AA\x9CD\x9B8");
    reg(L"A_B_J", L"FullForms", String, &AnsiVars::A_B_J, L"#$E2", L"\x9AC\x9CD\x99C");
    reg(L"A_B_D", L"FullForms", String, &AnsiVars::A_B_D, L"#$E3", L"\x9AC\x9CD\x9A6");
    reg(L"A_B_Dh", L"FullForms", String, &AnsiVars::A_B_Dh, L"#$E4", L"\x9AC\x9CD\x9A7");
    reg(L"A_Bh_R", L"FullForms", String, &AnsiVars::A_Bh_R, L"#$E5", L"\x9AD\x9CD\x9B0");
    reg(L"A_M_N", L"FullForms", String, &AnsiVars::A_M_N, L"#$E6", L"\x9AE\x9CD\x9A8");
    reg(L"A_M_Ph", L"FullForms", String, &AnsiVars::A_M_Ph, L"#$E7", L"\x9AE\x9CD\x9AB");
    reg(L"A_L_K", L"FullForms", String, &AnsiVars::A_L_K, L"#$E9", L"\x9B2\x9CD\x995");
    reg(L"A_L_G", L"FullForms", String, &AnsiVars::A_L_G, L"#$EA", L"\x9B2\x9CD\x997");
    reg(L"A_L_Tt", L"FullForms", String, &AnsiVars::A_L_Tt, L"#$EB", L"\x9B2\x9CD\x99F");
    reg(L"A_L_Dd", L"FullForms", String, &AnsiVars::A_L_Dd, L"#$EC", L"\x9B2\x9CD\x9A1");
    reg(L"A_L_P", L"FullForms", String, &AnsiVars::A_L_P, L"#$ED", L"\x9B2\x9CD\x9AA");
    reg(L"A_L_Ph", L"FullForms", String, &AnsiVars::A_L_Ph, L"#$EE", L"\x9B2\x9CD\x9AB");
    reg(L"A_Sh_UKar", L"FullForms", String, &AnsiVars::A_Sh_UKar, L"#$EF", L"\x9B6\x9C1");
    reg(L"A_Sh_C", L"FullForms", String, &AnsiVars::A_Sh_C, L"#$F0", L"\x9B6\x9CD\x99A");
    reg(L"A_Sh_Ch", L"FullForms", String, &AnsiVars::A_Sh_Ch, L"#$F1", L"\x9B6\x9CD\x99B");
    reg(L"A_Ss_Nn", L"FullForms", String, &AnsiVars::A_Ss_Nn, L"#$F2", L"\x9B7\x9CD\x9A3");
    reg(L"A_Ss_Tt", L"FullForms", String, &AnsiVars::A_Ss_Tt, L"#$F3", L"\x9B7\x9CD\x99F");
    reg(L"A_Ss_Tth", L"FullForms", String, &AnsiVars::A_Ss_Tth, L"#$F4", L"\x9B7\x9CD\x9A0");
    reg(L"A_Ss_Ph", L"FullForms", String, &AnsiVars::A_Ss_Ph, L"#$F5", L"\x9B8\x9CD\x9AB");
    reg(L"A_S_Kh", L"FullForms", String, &AnsiVars::A_S_Kh, L"#$F6", L"\x9B8\x9CD\x996");
    reg(L"A_S_Tt", L"FullForms", String, &AnsiVars::A_S_Tt, L"#$F7", L"\x9B8\x9CD\x99F");
    reg(L"A_S_N", L"FullForms", String, &AnsiVars::A_S_N, L"#$F8", L"\x9B8\x9CD\x9A8");
    reg(L"A_S_Ph", L"FullForms", String, &AnsiVars::A_S_Ph, L"#$F9", L"\x9B8\x9CD\x9AB");
    reg(L"A_H_UKar", L"FullForms", String, &AnsiVars::A_H_UKar, L"#$FB", L"\x9B9\x9C1");
    reg(L"A_H_RRIKar", L"FullForms", String, &AnsiVars::A_H_RRIKar, L"#$FC", L"\x9B9\x9C3");
    reg(L"A_H_N", L"FullForms", String, &AnsiVars::A_H_N, L"#$FD", L"\x9B9\x9CD\x9A8");
    reg(L"A_H_M", L"FullForms", String, &AnsiVars::A_H_M, L"#$FE", L"\x9B9\x9CD\x9AE");
    reg(L"A_Rr_G", L"FullForms", String, &AnsiVars::A_Rr_G, L"#$FF", L"\x9B0\x9CD\x997");
    // FirstHalfForms
    reg(L"A_Reph", L"FirstHalfForms", Char, &AnsiVars::A_Reph, L"#$A9", L"\x9CD\x9B0");
    reg(L"A_M_1H", L"FirstHalfForms", Char, &AnsiVars::A_M_1H, L"#$A4", L"\x9AE");
    reg(L"A_Ss_1H", L"FirstHalfForms", Char, &AnsiVars::A_Ss_1H, L"#$AE", L"\x9B7");
    reg(L"A_S_1H_1", L"FirstHalfForms", Char, &AnsiVars::A_S_1H_1, L"#$AF", L"\x9B8");
    reg(L"A_N_1H_1", L"FirstHalfForms", Char, &AnsiVars::A_N_1H_1, L"#$161", L"\x9A8");
    reg(L"A_S_1H_2", L"FirstHalfForms", Char, &AnsiVars::A_S_1H_2, L"#$2C9", L"\x9B8");
    reg(L"A_D_1H_1", L"FirstHalfForms", Char, &AnsiVars::A_D_1H_1, L"#$2DC", L"\x9A6");
    reg(L"A_C_1H", L"FirstHalfForms", Char, &AnsiVars::A_C_1H, L"#$201D", L"\x99A");
    reg(L"A_NGA_1H", L"FirstHalfForms", Char, &AnsiVars::A_NGA_1H, L"#$2022", L"\x999");
    reg(L"A_N_1H_2", L"FirstHalfForms", Char, &AnsiVars::A_N_1H_2, L"#$203A", L"\x9A8");
    reg(L"A_D_1H_2", L"FirstHalfForms", Char, &AnsiVars::A_D_1H_2, L"#$2122", L"\x9A6");
    // SecondHalfForms
    reg(L"A_B_2H_1", L"SecondHalfForms", Char, &AnsiVars::A_B_2H_1, L"#$5E", L"\x9AC");
    reg(L"A_B_2H_2", L"SecondHalfForms", Char, &AnsiVars::A_B_2H_2, L"#$A1", L"\x9AC");
    reg(L"A_BH_2H", L"SecondHalfForms", Char, &AnsiVars::A_BH_2H, L"#$A2", L"\x9AD");
    reg(L"A_BH_R_2H", L"SecondHalfForms", Char, &AnsiVars::A_BH_R_2H, L"#$A3", L"\x9AD\x9CD\x9B0");
    reg(L"A_M_2H_1", L"SecondHalfForms", Char, &AnsiVars::A_M_2H_1, L"#$A5", L"\x9AE");
    reg(L"A_B_2H_3", L"SecondHalfForms", Char, &AnsiVars::A_B_2H_3, L"#$A6", L"\x9AC");
    reg(L"A_M_2H_2", L"SecondHalfForms", Char, &AnsiVars::A_M_2H_2, L"#$A7", L"\x9AE");
    reg(L"A_ZFola", L"SecondHalfForms", Char, &AnsiVars::A_ZFola, L"#$A8", L"\x9AF");
    reg(L"A_RFola_1", L"SecondHalfForms", Char, &AnsiVars::A_RFola_1, L"#$AA", L"\x9B0");
    reg(L"A_RFola_2", L"SecondHalfForms", Char, &AnsiVars::A_RFola_2, L"#$AB", L"\x9B0");
    reg(L"A_L_2H_1", L"SecondHalfForms", Char, &AnsiVars::A_L_2H_1, L"#$AC", L"\x9B2");
    reg(L"A_L_2H_2", L"SecondHalfForms", Char, &AnsiVars::A_L_2H_2, L"#$AD", L"\x9B2");
    reg(L"A_T_R_2H", L"SecondHalfForms", Char, &AnsiVars::A_T_R_2H, L"#$BF", L"\x9A4\x9CD\x9B0");
    reg(L"A_RFola_3", L"SecondHalfForms", Char, &AnsiVars::A_RFola_3, L"#$D6", L"\x9B0");
    // Glyph variables introduced by Ansi V4.  The defaults mirror the Delphi
    // typed constants exactly; the Ansi V4 JSON overrides all four.
    reg(L"A_RFola_4", L"SecondHalfForms", Char, &AnsiVars::A_RFola_4, L"#$C7", L"\x9B0");
    reg(L"A_RFola_5", L"SecondHalfForms", Char, &AnsiVars::A_RFola_5, L"#$CB", L"\x9B0");
    reg(L"A_RFola_6", L"SecondHalfForms", Char, &AnsiVars::A_RFola_6, L"#$CC", L"\x9B0");
    reg(L"A_Nn_2H_1", L"SecondHalfForms", Char, &AnsiVars::A_Nn_2H_1, L"#$E8", L"\x9A3");
    reg(L"A_K_R_2H", L"SecondHalfForms", Char, &AnsiVars::A_K_R_2H, L"#$152", L"\x995\x9CD\x9B0");
    reg(L"A_Nn_2H_2", L"SecondHalfForms", Char, &AnsiVars::A_Nn_2H_2, L"#$153", L"\x9A3");
    reg(L"A_B_2H_4", L"SecondHalfForms", Char, &AnsiVars::A_B_2H_4, L"#$178", L"\x9AC");
    reg(L"A_T_2H", L"SecondHalfForms", Char, &AnsiVars::A_T_2H, L"#$2014", L"\x9A4");
    reg(L"A_T_UKar_2H", L"SecondHalfForms", Char, &AnsiVars::A_T_UKar_2H, L"#$2018", L"\x9A4\x9C1");
    reg(L"A_Th_2H", L"SecondHalfForms", Char, &AnsiVars::A_Th_2H, L"#$2019", L"\x9A5");
    reg(L"A_K_2H", L"SecondHalfForms", Char, &AnsiVars::A_K_2H, L"#$2039", L"\x995");
    reg(L"A_L_2H_3", L"SecondHalfForms", Char, &AnsiVars::A_L_2H_3, L"#$2212", L"\x9B2");
    reg(L"A_P_2H", L"SecondHalfForms", Char, &AnsiVars::A_P_2H, L"#$2219", L"\x9AA");

    // Registry names in the exact iteration order of the Delphi
    // TDictionary<string, TAnsiVarRec> (AnsiRegistryMap).  Collisions
    // resolve first-claim-wins during the reverse converter's table build,
    // so this order must match Delphi's to reproduce its winners.
    static const wchar_t* const kDelphiOrder[] = {
        L"A_L_2H_2", L"A_IIKar", L"A_N",
        L"A_Ss_1H", L"A_Kh", L"A_NYA_C",
        L"A_1", L"A_P_P", L"A_Bisharga",
        L"A_4", L"A_S", L"A_B_2H_2",
        L"A_RRI", L"A_Th_2H", L"A_StartDoubleQuote",
        L"A_K_Tt", L"A_DoubleDanda", L"A_D_D",
        L"A_T_M", L"A_G_Ukar", L"A_Y",
        L"A_T_R", L"A_B_D", L"A_Ss_Nn",
        L"A_S_1H_1", L"A_G_Dh", L"A_UKar2",
        L"A_G", L"A_K_K", L"A_Dd_Dd",
        L"A_OI", L"A_Nn_Tt", L"A_B_J",
        L"A_NYA_J", L"A_J", L"A_M_2H_2",
        L"A_G_G", L"A_M", L"A_UUKar3",
        L"A_P_T", L"A_H_RRIKar", L"A_0",
        L"A_Ss_Tth", L"A_OIKar2", L"A_NYA_CH",
        L"A_S_N", L"A_R", L"A_B_2H_1",
        L"A_Ss_Ph", L"A_RRH", L"A_Reph",
        L"A_U", L"A_B_2H_4", L"A_Ch",
        L"A_Gh", L"A_EKar1", L"A_K_T",
        L"A_K_2H", L"A_RFola_1", L"A_Taka",
        L"A_C", L"A_L_Ph", L"A_L_K",
        L"A_Tt_Tt", L"A_UKar3", L"A_L_2H_1",
        L"A_NYA", L"A_I", L"A_N_Dd",
        L"A_K_Ss_M", L"A_Khandata", L"A_L",
        L"A_NGA_K", L"A_UUKar2", L"A_J_NYA",
        L"A_StartSingleQuote", L"A_7", L"A_Tth",
        L"A_Nn_2H_2", L"A_D_1H_1", L"A_ZFola",
        L"A_AA", L"A_T", L"A_K_R_2H",
        L"A_Tt", L"A_Sh_UKar", L"A_NGA",
        L"A_K_S", L"A_NGA_1H", L"A_Chandra",
        L"A_N_Tth", L"A_RRIKar1", L"A_T_T",
        L"A_K_Ss", L"A_B", L"A_C_1H",
        L"A_M_1H", L"A_E", L"A_N_Dh",
        L"A_S_Tt", L"A_SS", L"A_H",
        L"A_OUKar", L"A_B_Dh", L"A_T_R_2H",
        L"A_3", L"A_T_UKar_2H", L"A_UUKar1",
        L"A_Rr_G", L"A_OIKar1", L"A_NYA_Jh",
        L"A_L_Dd", L"A_IKar", L"A_BH_R_2H",
        L"A_Sh_C", L"A_6", L"A_P_S",
        L"A_Nn_Tth", L"A_L_P", L"A_Bh",
        L"A_9", L"A_P", L"A_D_B",
        L"A_Dd", L"A_EKar2", L"A_N_1H_1",
        L"A_H_UKar", L"A_H_M", L"A_RFola_2",
        L"A_OU", L"A_EndDoubleQuote", L"A_Ss_Tt",
        L"A_K_R", L"A_NN_Dd", L"A_A",
        L"A_UKar4", L"A_Ddh", L"A_K_M",
        L"A_S_1H_2", L"A_Sh", L"A_J_Jh",
        L"A_UKar1", L"A_D", L"A_L_2H_3",
        L"A_O", L"A_G_D", L"A_P_Tt",
        L"A_L_G", L"A_2", L"A_BH_2H",
        L"A_Dari", L"A_M_N", L"A_Nn_2H_1",
        L"A_Jh", L"A_D_1H_2", L"A_5",
        L"A_B_2H_3", L"A_T_2H", L"A_II",
        L"A_Hasanta", L"A_D_Dh", L"A_Dh",
        L"A_M_Ph", L"A_8", L"A_AAKar",
        L"A_J_J", L"A_Bh_R", L"A_Sh_Ch",
        L"A_L_Tt", L"A_N_1H_2", L"A_S_Ph",
        L"A_Z", L"A_H_N", L"A_RR",
        L"A_RRIKar2", L"A_RFola_3", L"A_T_Th",
        L"A_N_S", L"A_Nn", L"A_D_M",
        L"A_Anushar", L"A_Ph", L"A_EndSingleQuote",
        L"A_NGA_G", L"A_Th", L"A_S_Kh",
        L"A_M_2H_1", L"A_K", L"A_UU",
    };
    registryOrder.assign(kDelphiOrder,
                         kDelphiOrder + sizeof(kDelphiOrder) / sizeof(kDelphiOrder[0]));
}

// ---------------------------------------------------------------------------
// Reset / defaults
// ---------------------------------------------------------------------------

void AnsiRegistry::resetToDefaults() {
    init();
    for (const auto& rec : registry) {
        std::wstring resolved = processHexAndUnicode(rec.defaultVal);
        if (rec.varType == AnsiVarType::Char) {
            if (!resolved.empty())
                v.*(rec.member) = std::wstring(1, resolved[0]);
            else
                v.*(rec.member) = std::wstring();
        } else {
            v.*(rec.member) = resolved;
        }
    }
    overrides.clear();
    customFullForms.clear();
    customPreReplacements.clear();
    customPostReplacements.clear();
    activeReplacements.clear();
    karInclusiveReplacements.clear();
    vowelRules.clear();
    rfolaRules.clear();
    karCorrections.clear();
    groupKarCorrections.clear();
    ansiGroupMap.clear();
    ansiGroupRawMap.clear();
    consonantGroupMap.clear();
    consonantGroupRawMap.clear();
    clearResolveCache();
    prepareActiveReplacements();
}

static bool endsWith(const std::wstring& s, const std::wstring& suffix) {
    return s.size() >= suffix.size() &&
           s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

void AnsiRegistry::prepareActiveReplacements() {
    init();
    std::set<std::wstring> excludedNames; // always empty in the original
    std::map<std::wstring, std::wstring> uniqueMap;

    for (const auto& recIt : registryMap) {
        const AnsiVarRec& rec = recIt.second;
        if (rec.bengaliChar.empty())
            continue;

        if (rec.category == L"Numbers") {
            // all included
        } else if (rec.category == L"Symbols") {
            if (rec.name != L"A_Taka" && rec.name != L"A_Dari" &&
                rec.name != L"A_DoubleDanda")
                continue;
        } else if (rec.category == L"Consonants") {
            if (rec.name != L"A_Khandata" && rec.name != L"A_Anushar" &&
                rec.name != L"A_Bisharga" && rec.name != L"A_Chandra")
                continue;
        } else if (rec.category == L"FullForms") {
            if (excludedNames.count(rec.name))
                continue;
        } else {
            continue;
        }

        // CleanBengaliChar: strip at ' ', '(', '-'
        std::wstring key = rec.bengaliChar;
        for (const wchar_t sep : {L' ', L'(', L'-'}) {
            size_t p = key.find(sep);
            if (p != std::wstring::npos)
                key = key.substr(0, p);
        }
        // Trim
        size_t b = key.find_first_not_of(L" \t\r\n");
        if (b == std::wstring::npos)
            key.clear();
        else
            key = key.substr(b, key.find_last_not_of(L" \t\r\n") - b + 1);
        if (key.empty())
            continue;

        std::wstring val;
        auto oit = overrides.find(rec.name);
        if (oit != overrides.end())
            val = oit->second;
        else if (rec.member)
            val = v.*(rec.member);
        if (val.empty())
            continue;

        uniqueMap[key] = val;
    }

    // Merge custom full-form overrides
    for (const auto& p : customFullForms)
        uniqueMap[p.key] = p.value;

    // Populate ActiveReplacements and KarInclusiveReplacements
    activeReplacements.clear();
    karInclusiveReplacements.clear();
    for (const auto& kv : uniqueMap) {
        const std::wstring& key = kv.first;
        const std::wstring& val = kv.second;
        if (endsWith(key, std::wstring(1, L'\x9C1')) || // b_Ukar
            endsWith(key, std::wstring(1, L'\x9C2')) || // b_UUkar
            endsWith(key, std::wstring(1, L'\x9C3'))) { // b_Rrikar
            karInclusiveReplacements.push_back({key, val, L""});
        } else {
            activeReplacements.push_back({key, val, L""});
        }
    }

    // Sort by key length descending (Longest Match First).  Equal lengths:
    // ordinary conjuncts (not ending in 'ra') get priority.
    auto sortRepl = [](std::vector<ReplacementPair>& arr) {
        std::stable_sort(arr.begin(), arr.end(),
                         [](const ReplacementPair& l, const ReplacementPair& r) {
                             if (l.key.size() != r.key.size())
                                 return l.key.size() > r.key.size();
                             bool lRa = endsWith(l.key, std::wstring(1, L'\x9B0'));
                             bool rRa = endsWith(r.key, std::wstring(1, L'\x9B0'));
                             if (lRa != rRa)
                                 return !lRa; // ordinary conjunct first
                             return false;
                         });
    };
    sortRepl(activeReplacements);
    sortRepl(karInclusiveReplacements);
}

// ---------------------------------------------------------------------------
// Group helpers
// ---------------------------------------------------------------------------

bool AnsiRegistry::charInGroup(const std::wstring& ch, const std::wstring& groupName) const {
    if (groupName.empty())
        return false;
    if (groupName == L"default")
        return true;
    auto it = consonantGroupMap.find(groupName);
    if (it != consonantGroupMap.end())
        for (const auto& s : it->second)
            if (s == ch)
                return true;
    auto ait = ansiGroupMap.find(groupName);
    if (ait != ansiGroupMap.end())
        for (const auto& s : ait->second)
            if (s == ch)
                return true;
    return false;
}

bool AnsiRegistry::hasHasantaBefore(const std::wstring& text, int pos) {
    // 1-based pos; check the character just before it, skipping ZWJ/ZWNJ.
    if (pos - 1 < 1)
        return false;
    int i = pos - 1;
    while (i >= 1 && (text[i - 1] == L'\x200D' || text[i - 1] == L'\x200C'))
        --i;
    if (i >= 1 && text[i - 1] == L'\x9CD')
        return true;
    return false;
}

int AnsiRegistry::matchGroupLength(const std::wstring& fullText, int charIndex,
                                   const std::wstring& groupName) const {
    int result = 0;
    if (charIndex < 1 || charIndex > static_cast<int>(fullText.size()))
        return result;

    auto tryMap = [&](const std::map<std::wstring, std::vector<std::wstring>>& map) {
        auto it = map.find(groupName);
        if (it == map.end())
            return;
        for (const auto& s : it->second) {
            int slen = static_cast<int>(s.size());
            if (slen <= charIndex) {
                int matchStart = charIndex - slen + 1; // 1-based
                if (fullText.compare(matchStart - 1, slen, s) == 0 &&
                    !hasHasantaBefore(fullText, matchStart)) {
                    if (slen > result)
                        result = slen;
                }
            }
        }
    };
    tryMap(ansiGroupMap);
    tryMap(consonantGroupMap);
    return result;
}

// ---------------------------------------------------------------------------
// JSON parser (faithful port of the hand-rolled loader)
// ---------------------------------------------------------------------------

static void jSkipWS(const std::wstring& s, size_t& p) {
    while (p < s.size() && s[p] <= L' ')
        ++p;
}

static std::wstring jReadString(const std::wstring& s, size_t& p) {
    std::wstring out;
    jSkipWS(s, p);
    if (p >= s.size() || s[p] != L'"')
        return out;
    ++p;
    while (p < s.size()) {
        if (s[p] == L'"') {
            ++p;
            return out;
        }
        if (s[p] == L'\\') {
            ++p;
            if (p >= s.size())
                return out;
            switch (s[p]) {
                case L'"': out.push_back(L'"'); break;
                case L'\\': out.push_back(L'\\'); break;
                case L'/': out.push_back(L'/'); break;
                case L'n': out.push_back(L'\n'); break;
                case L'r': out.push_back(L'\r'); break;
                case L't': out.push_back(L'\t'); break;
                case L'u': {
                    if (p + 4 < s.size()) {
                        int code = 0;
                        for (int k = 1; k <= 4; ++k) {
                            wchar_t c = s[p + k];
                            code = code * 16 + (isHexDigit(c) ? hexVal(c) : -16);
                        }
                        if (code < 0)
                            code = 0x3F; // '?' fallback
                        out.push_back(static_cast<wchar_t>(code));
                    } else {
                        out.push_back(L'?');
                    }
                    p += 4;
                    break;
                }
                default:
                    out.push_back(s[p]);
            }
            ++p;
        } else {
            out.push_back(s[p]);
            ++p;
        }
    }
    return out;
}

static int jReadInt(const std::wstring& s, size_t& p, int def) {
    int result = def;
    jSkipWS(s, p);
    if (p >= s.size())
        return result;
    bool neg = false;
    if (s[p] == L'-') {
        neg = true;
        ++p;
    }
    if (p >= s.size() || s[p] < L'0' || s[p] > L'9')
        return result;
    size_t start = p;
    while (p < s.size() && s[p] >= L'0' && s[p] <= L'9')
        ++p;
    long long v = 0;
    for (size_t k = start; k < p; ++k)
        v = v * 10 + (s[k] - L'0');
    result = static_cast<int>(v);
    if (neg)
        result = -result;
    return result;
}

static void jSkipValue(const std::wstring& s, size_t& p) {
    jSkipWS(s, p);
    if (p >= s.size())
        return;
    switch (s[p]) {
        case L'{':
        case L'[': {
            int depth = 1;
            ++p;
            while (p < s.size() && depth > 0) {
                if (s[p] == L'"') {
                    ++p;
                    while (p < s.size()) {
                        if (s[p] == L'\\') {
                            ++p;
                            if (p < s.size())
                                ++p;
                        } else if (s[p] == L'"') {
                            ++p;
                            break;
                        } else {
                            ++p;
                        }
                    }
                } else if (s[p] == L'{' || s[p] == L'[') {
                    ++depth;
                    ++p;
                } else if (s[p] == L'}' || s[p] == L']') {
                    --depth;
                    ++p;
                } else {
                    ++p;
                }
            }
            if (p <= s.size())
                ++p;
            break;
        }
        case L'"':
            jReadString(s, p);
            break;
        default:
            ++p;
    }
}

// ReplaceStr over the whole string (Delphi PosEx loop).
static std::wstring replaceAll(const std::wstring& s, const std::wstring& from,
                               const std::wstring& to) {
    if (from.empty())
        return s;
    std::wstring out;
    size_t pos = 0;
    while (pos <= s.size()) {
        size_t hit = s.find(from, pos);
        if (hit == std::wstring::npos) {
            out.append(s, pos, s.size() - pos);
            break;
        }
        out.append(s, pos, hit - pos);
        out.append(to);
        pos = hit + from.size();
    }
    return out;
}

static std::wstring toLowerAscii(const std::wstring& s) {
    std::wstring out = s;
    for (auto& c : out)
        if (c >= L'A' && c <= L'Z')
            c = static_cast<wchar_t>(c - L'A' + L'a');
    return out;
}

void AnsiRegistry::parseJson(const std::wstring& json, std::vector<std::wstring>* errorLog) {
    size_t p = 0;
    jSkipWS(json, p);
    if (p >= json.size() || json[p] != L'{')
        return;
    ++p;

    while (p < json.size()) {
        jSkipWS(json, p);
        if (p >= json.size() || json[p] == L'}')
            break;
        if (json[p] == L',') {
            ++p;
            continue;
        }
        std::wstring key = jReadString(json, p);
        jSkipWS(json, p);
        if (p < json.size() && json[p] == L':')
            ++p;
        jSkipWS(json, p);

        if (key == L"Constants") {
            if (p < json.size() && json[p] == L'{')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L'}') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                jReadString(json, p); // category name (ignored)
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L':')
                    ++p;
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L'{')
                    ++p;
                else
                    continue;
                while (p < json.size()) {
                    jSkipWS(json, p);
                    if (p >= json.size() || json[p] == L'}') {
                        ++p;
                        break;
                    }
                    if (json[p] == L',') {
                        ++p;
                        continue;
                    }
                    std::wstring constName = jReadString(json, p);
                    jSkipWS(json, p);
                    if (p < json.size() && json[p] == L':')
                        ++p;
                    jSkipWS(json, p);
                    if (p < json.size() && json[p] == L'{') {
                        ++p;
                        std::wstring constValue, unicodeKey;
                        while (p < json.size()) {
                            jSkipWS(json, p);
                            if (p >= json.size() || json[p] == L'}') {
                                ++p;
                                break;
                            }
                            if (json[p] == L',') {
                                ++p;
                                continue;
                            }
                            std::wstring field = jReadString(json, p);
                            jSkipWS(json, p);
                            if (p < json.size() && json[p] == L':')
                                ++p;
                            if (field == L"Value")
                                constValue = jReadString(json, p);
                            else if (field == L"UnicodeKey")
                                unicodeKey = resolveValue(jReadString(json, p));
                            else
                                jSkipValue(json, p);
                        }
                        if (!constValue.empty()) {
                            // NOTE: Constants uses ProcessHexAndUnicode only.
                            constValue = processHexAndUnicode(constValue);
                            auto it = registryMap.find(constName);
                            if (it != registryMap.end())
                                setAnsiVarValue(constName, constValue);
                        }
                        if (!unicodeKey.empty()) {
                            auto it = registryMap.find(constName);
                            if (it != registryMap.end()) {
                                AnsiVarRec rec = it->second;
                                rec.bengaliChar = unicodeKey;
                                registryMap[constName] = rec;
                            }
                        }
                    } else {
                        jSkipValue(json, p);
                    }
                }
            }
        } else if (key == L"VowelsAndKars" || key == L"Symbols" ||
                   key == L"Consonants" || key == L"FullForms") {
            if (p < json.size() && json[p] == L'{')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L'}') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                std::wstring constName = jReadString(json, p);
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L':')
                    ++p;
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L'{') {
                    ++p;
                    std::wstring constValue, unicodeKey;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        if (field == L"Value")
                            constValue = jReadString(json, p);
                        else if (field == L"UnicodeKey")
                            unicodeKey = resolveValue(jReadString(json, p));
                        else
                            jSkipValue(json, p);
                    }
                    if (!constValue.empty()) {
                        // NOTE: these sections use ResolveValue.
                        constValue = resolveValue(constValue);
                        auto it = registryMap.find(constName);
                        if (it != registryMap.end())
                            setAnsiVarValue(constName, constValue);
                    }
                    if (!unicodeKey.empty()) {
                        auto it = registryMap.find(constName);
                        if (it != registryMap.end()) {
                            AnsiVarRec rec = it->second;
                            rec.bengaliChar = unicodeKey;
                            registryMap[constName] = rec;
                        }
                    }
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"FullFormReplacements" || key == L"PreReplacements" ||
                   key == L"PostReplacements") {
            // ParseSection
            std::vector<ReplacementPair> items;
            jSkipWS(json, p);
            if (p < json.size() && json[p] == L'[')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L']') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                if (json[p] == L'{') {
                    ++p;
                    ReplacementPair pair;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        if (field == L"Key")
                            pair.key = resolveValue(jReadString(json, p));
                        else if (field == L"Value")
                            pair.value = resolveValue(jReadString(json, p));
                        else if (field == L"Comment")
                            pair.comment = jReadString(json, p);
                        else
                            jSkipValue(json, p);
                    }
                    if (!pair.key.empty())
                        items.push_back(pair);
                } else {
                    jSkipValue(json, p);
                }
            }
            if (key == L"FullFormReplacements")
                customFullForms = items;
            else if (key == L"PreReplacements")
                customPreReplacements = items;
            else
                customPostReplacements = items;
        } else if (key == L"VowelRules") {
            vowelRules.clear();
            if (p < json.size() && json[p] == L'{')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L'}') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                std::wstring kc = jReadString(json, p);
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L':')
                    ++p;
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L'{') {
                    ++p;
                    VowelRule rule;
                    rule.karChar = processHexAndUnicode(kc);
                    rule.toggle = L"none";
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        jSkipWS(json, p);
                        if (field == L"default") {
                            rule.defaultVal = jReadString(json, p);
                        } else if (field == L"toggle") {
                            rule.toggle = jReadString(json, p);
                            rule.toggleOnBackspace = (rule.toggle == L"backspace");
                        } else if (field == L"mappings") {
                            if (p < json.size() && json[p] == L'[')
                                ++p;
                            while (p < json.size()) {
                                jSkipWS(json, p);
                                if (p >= json.size() || json[p] == L']') {
                                    ++p;
                                    break;
                                }
                                if (json[p] == L',') {
                                    ++p;
                                    continue;
                                }
                                if (json[p] == L'{') {
                                    ++p;
                                    VowelRuleMapping m;
                                    while (p < json.size()) {
                                        jSkipWS(json, p);
                                        if (p >= json.size() || json[p] == L'}') {
                                            ++p;
                                            break;
                                        }
                                        if (json[p] == L',') {
                                            ++p;
                                            continue;
                                        }
                                        std::wstring mf = jReadString(json, p);
                                        jSkipWS(json, p);
                                        if (p < json.size() && json[p] == L':')
                                            ++p;
                                        jSkipWS(json, p);
                                        if (mf == L"consonants") {
                                            m.consonants = jReadString(json, p);
                                        } else if (mf == L"value") {
                                            m.value = jReadString(json, p);
                                        } else if (mf == L"alt") {
                                            m.alt = jReadString(json, p);
                                        } else if (mf == L"toggle") {
                                            m.toggleOnBackspace = (jReadString(json, p) == L"backspace");
                                        } else if (mf == L"matchMode") {
                                            if (p < json.size() && json[p] == L'"')
                                                m.matchMode = std::stoi(jReadString(json, p), nullptr, 10);
                                            else
                                                m.matchMode = jReadInt(json, p, 0);
                                        } else if (mf == L"process") {
                                            m.processPhase = toLowerAscii(jReadString(json, p));
                                        } else {
                                            jSkipValue(json, p);
                                        }
                                    }
                                    m.consonants = processHexAndUnicode(m.consonants);
                                    rule.mappings.push_back(m);
                                } else {
                                    jSkipValue(json, p);
                                }
                            }
                        } else {
                            jSkipValue(json, p);
                        }
                    }
                    vowelRules.push_back(rule);
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"RfolaRules") {
            rfolaRules.clear();
            if (p < json.size() && json[p] == L'[')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L']') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                if (json[p] == L'{') {
                    ++p;
                    RfolaRule rule;
                    rule.replaceLen = 2;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        jSkipWS(json, p);
                        if (field == L"consonants") {
                            rule.consonants = jReadString(json, p);
                        } else if (field == L"value") {
                            rule.rawValue = jReadString(json, p);
                            rule.value = rule.rawValue;
                        } else if (field == L"halfValue") {
                            rule.rawHalfValue = jReadString(json, p);
                            rule.halfValue = rule.rawHalfValue;
                        } else if (field == L"replaceLen") {
                            rule.replaceLen = jReadInt(json, p, 2);
                        } else if (field == L"contextGroup") {
                            rule.contextGroup = jReadString(json, p);
                        } else if (field == L"contextReplaceLen") {
                            rule.contextReplaceLen = jReadInt(json, p, 0);
                        } else if (field == L"contextValue") {
                            rule.rawContextValue = jReadString(json, p);
                            rule.contextValue = rule.rawContextValue;
                        } else if (field == L"Comment" || field == L"comment") {
                            rule.comment = jReadString(json, p);
                        } else {
                            jSkipValue(json, p);
                        }
                    }
                    rule.consonants = processHexAndUnicode(rule.consonants);
                    rule.value = resolveValue(rule.value);
                    if (!rule.halfValue.empty())
                        rule.halfValue = resolveValue(rule.halfValue);
                    if (!rule.contextValue.empty())
                        rule.contextValue = resolveValue(rule.contextValue);
                    rfolaRules.push_back(rule);
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"KarCorrections") {
            karCorrections.clear();
            if (p < json.size() && json[p] == L'[')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L']') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                if (json[p] == L'{') {
                    ++p;
                    KarCorrection kc;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        if (field == L"char")
                            kc.rawCharStr = jReadString(json, p);
                        else if (field == L"from")
                            kc.rawFromKar = jReadString(json, p);
                        else if (field == L"to")
                            kc.rawToKar = jReadString(json, p);
                        else if (field == L"Comment" || field == L"comment")
                            kc.comment = jReadString(json, p);
                        else
                            jSkipValue(json, p);
                    }
                    kc.charStr = resolveValue(kc.rawCharStr);
                    kc.fromKar = resolveValue(kc.rawFromKar);
                    kc.toKar = resolveValue(kc.rawToKar);
                    karCorrections.push_back(kc);
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"GroupKarCorrections") {
            if (p < json.size() && json[p] == L'[')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L']') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                if (json[p] == L'{') {
                    ++p;
                    std::wstring gCorrGroup, gCorrFrom, gCorrTo;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring field = jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        if (field == L"group")
                            gCorrGroup = jReadString(json, p);
                        else if (field == L"from")
                            gCorrFrom = jReadString(json, p);
                        else if (field == L"to")
                            gCorrTo = jReadString(json, p);
                        else
                            jSkipValue(json, p);
                    }
                    if (!gCorrGroup.empty() && !gCorrFrom.empty() && !gCorrTo.empty()) {
                        auto git = ansiGroupMap.find(gCorrGroup);
                        if (git != ansiGroupMap.end()) {
                            for (const auto& member : git->second) {
                                // 1. Main sequence (RFola + Kar)
                                ReplacementPair pair;
                                pair.key = resolveValue(member + gCorrFrom);
                                pair.value = resolveValue(member + gCorrTo);
                                if (!pair.key.empty() && pair.key != pair.value)
                                    customPostReplacements.push_back(pair);
                                // 2. Swapped sequence (Kar + RFola)
                                pair.key = resolveValue(gCorrFrom + member);
                                pair.value = resolveValue(gCorrTo + member);
                                if (!pair.key.empty() && pair.key != pair.value)
                                    customPostReplacements.push_back(pair);
                            }
                        }
                    }
                    groupKarCorrections.push_back({gCorrGroup, gCorrFrom, gCorrTo});
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"RaPhalaGroups") {
            ansiGroupMap.clear();
            ansiGroupRawMap.clear();
            if (p < json.size() && json[p] == L'{')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L'}') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                std::wstring gk = jReadString(json, p);
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L':')
                    ++p;
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L'[') {
                    ++p;
                    std::vector<std::wstring> items, rawItems;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L']') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring rawStr = jReadString(json, p);
                        items.push_back(resolveValue(rawStr));
                        rawItems.push_back(rawStr);
                    }
                    ansiGroupMap[gk] = items;
                    ansiGroupRawMap[gk] = rawItems;
                } else {
                    jSkipValue(json, p);
                }
            }
        } else if (key == L"ConsonantGroups") {
            consonantGroupMap.clear();
            consonantGroupRawMap.clear();
            if (p < json.size() && json[p] == L'{')
                ++p;
            else
                continue;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L'}') {
                    ++p;
                    break;
                }
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                std::wstring gk = jReadString(json, p);
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L':')
                    ++p;
                jSkipWS(json, p);
                if (p < json.size() && json[p] == L'[') {
                    ++p;
                    std::vector<std::wstring> items, rawItems;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L']') {
                            ++p;
                            break;
                        }
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        std::wstring rawStr = jReadString(json, p);
                        items.push_back(resolveValue(rawStr));
                        rawItems.push_back(rawStr);
                    }
                    consonantGroupMap[gk] = items;
                    consonantGroupRawMap[gk] = rawItems;
                } else {
                    jSkipValue(json, p);
                }
            }
        } else {
            jSkipValue(json, p);
        }
    }

    auto sortRepl = [](std::vector<ReplacementPair>& arr) {
        std::stable_sort(arr.begin(), arr.end(),
                         [](const ReplacementPair& l, const ReplacementPair& r) {
                             return l.key.size() > r.key.size();
                         });
    };
    sortRepl(customFullForms);
    sortRepl(customPreReplacements);
    sortRepl(customPostReplacements);

    prepareActiveReplacements();
}

namespace {

// Decode UTF-8 -> UTF-16 (wchar_t) and strip a leading BOM.
void decodeUtf8ToWide(const std::string& bytes, std::wstring& json) {
    json.clear();
    json.reserve(bytes.size());
    for (size_t i = 0; i < bytes.size();) {
        unsigned char c = static_cast<unsigned char>(bytes[i]);
        if (c < 0x80) {
            json.push_back(static_cast<wchar_t>(c));
            ++i;
        } else if ((c >> 5) == 0x6) { // 2-byte
            if (i + 2 > bytes.size())
                break;
            const unsigned cp = ((c & 0x1F) << 6) |
                                (static_cast<unsigned char>(bytes[i + 1]) & 0x3F);
            json.push_back(static_cast<wchar_t>(cp));
            i += 2;
        } else if ((c >> 4) == 0xE) { // 3-byte
            if (i + 3 > bytes.size())
                break;
            const unsigned cp = ((c & 0x0F) << 12) |
                                ((static_cast<unsigned char>(bytes[i + 1]) & 0x3F) << 6) |
                                (static_cast<unsigned char>(bytes[i + 2]) & 0x3F);
            json.push_back(static_cast<wchar_t>(cp));
            i += 3;
        } else { // 4-byte -> surrogate pair
            if (i + 4 > bytes.size())
                break;
            unsigned cp = ((c & 0x07) << 18) |
                          ((static_cast<unsigned char>(bytes[i + 1]) & 0x3F) << 12) |
                          ((static_cast<unsigned char>(bytes[i + 2]) & 0x3F) << 6) |
                          (static_cast<unsigned char>(bytes[i + 3]) & 0x3F);
            cp -= 0x10000;
            json.push_back(static_cast<wchar_t>(0xD800 + (cp >> 10)));
            json.push_back(static_cast<wchar_t>(0xDC00 + (cp & 0x3FF)));
            i += 4;
        }
    }
    if (!json.empty() && json[0] == 0xFEFF)
        json.erase(0, 1);
}

std::wstring widenAscii(const std::string& s) {
    return std::wstring(s.begin(), s.end());
}

enum class MappingRead { Ok, Missing, Unreadable };

// Reads a mapping file as JSON text.  A mapping may be plain UTF-8 JSON or an
// encrypted AvroShield container (.AvroEnco, magic 'AVROSHLD') - the form the
// installed Avro Keyboard ships.  Containers are decrypted and deobfuscated in
// memory right here, so every consumer below keeps working on JSON text; the
// plaintext never touches the disk.
MappingRead readMappingJson(const std::wstring& path, std::wstring& json,
                            std::wstring& error) {
    std::ifstream f(path.c_str(), std::ios::binary);
    if (!f.good()) {
        error = L"File does not exist.";
        return MappingRead::Missing;
    }
    const std::string bytes((std::istreambuf_iterator<char>(f)),
                            std::istreambuf_iterator<char>());

    if (avro::isAvroEncoContainer(
            reinterpret_cast<const unsigned char*>(bytes.data()), bytes.size())) {
        std::string decoded;
        std::string decodeError;
        if (!avro::decodeAvroEncoContainer(
                reinterpret_cast<const unsigned char*>(bytes.data()),
                bytes.size(), std::string(), decoded, decodeError)) {
            error = L"Encrypted mapping could not be read: " +
                    widenAscii(decodeError);
            return MappingRead::Unreadable;
        }
        decodeUtf8ToWide(decoded, json);
        return MappingRead::Ok;
    }

    decodeUtf8ToWide(bytes, json);
    return MappingRead::Ok;
}

// Version name -> mapping file.  Encrypted containers win over a same-named
// readable .json, exactly like the original engine's mapping scanner.
std::wstring resolveMappingPath(const std::wstring& dir,
                                const std::wstring& version) {
    const std::wstring base = dir + version;
    const std::wstring container = base + L".AvroEnco";
    std::ifstream probe(container.c_str(), std::ios::binary);
    if (probe.good())
        return container;
    return base + L".json";
}

} // namespace

bool AnsiRegistry::loadAnsiMapping(const std::wstring& path,
                                   std::vector<std::wstring>* errorLog) {
    resetToDefaults();

    std::wstring json;
    std::wstring readError;
    const MappingRead read = readMappingJson(path, json, readError);
    if (read == MappingRead::Missing) {
        if (errorLog)
            errorLog->push_back(L"Error: mapping file not found at: " + path);
        return false;
    }
    if (read != MappingRead::Ok) {
        if (errorLog)
            errorLog->push_back(L"Error: " + readError + L" (" + path + L")");
        return false;
    }

    try {
        parseJson(json, errorLog);
    } catch (...) {
        if (errorLog)
            errorLog->push_back(L"Critical: Invalid JSON Syntax.");
        return false;
    }
    return true;
}

void AnsiRegistry::loadCurrentActiveMapping(std::vector<std::wstring>* errorLog) {
    // No folder mapping selected (or no folder): keep the built-in base
    // tables - there is no built-in "Default" version to switch to any more.
    if (ansiVersion.empty() || ansiMappingDir.empty())
        resetToDefaults();
    else
        loadAnsiMapping(resolveMappingPath(ansiMappingDir, ansiVersion), errorLog);
}

// Faithful port: checks root object + Constants + the three replacement
// sections exist (>= 4 sections counted).  Takes the already-decoded JSON so a
// caller that holds the text (see trySetAnsiVersion) can validate it without
// decrypting the container a second time.
static bool validateMappingJson(const std::wstring& json,
                                std::wstring& errorMessage);

bool AnsiRegistry::validateAnsiMappingFile(const std::wstring& path,
                                           std::wstring& errorMessage) {
    std::wstring json;
    std::wstring readError;
    switch (readMappingJson(path, json, readError)) {
    case MappingRead::Missing:
        errorMessage = L"File does not exist.";
        return false;
    case MappingRead::Unreadable:
        errorMessage = readError;
        return false;
    case MappingRead::Ok:
        break;
    }
    return validateMappingJson(json, errorMessage);
}

bool validateMappingJson(const std::wstring& json,
                         std::wstring& errorMessage) {
    size_t p = 0;
    jSkipWS(json, p);
    if (p >= json.size() || json[p] != L'{') {
        errorMessage = L"Invalid JSON root: expected an object.";
        return false;
    }
    ++p;
    int sectionCount = 0;
    while (p < json.size()) {
        jSkipWS(json, p);
        if (p >= json.size() || json[p] == L'}')
            break;
        if (json[p] == L',') {
            ++p;
            continue;
        }
        std::wstring k = jReadString(json, p);
        jSkipWS(json, p);
        if (p < json.size() && json[p] == L':')
            ++p;
        jSkipWS(json, p);
        if (k == L"Constants") {
            ++sectionCount;
            if (p >= json.size() || json[p] != L'{') {
                errorMessage = L"Invalid section: Constants must be an object.";
                return false;
            }
            jSkipValue(json, p);
        } else if (k == L"FullFormReplacements" || k == L"PreReplacements" ||
                   k == L"PostReplacements") {
            ++sectionCount;
            if (p >= json.size() || json[p] != L'[') {
                errorMessage = L"Invalid section: " + k + L" must be an array.";
                return false;
            }
            ++p;
            while (p < json.size()) {
                jSkipWS(json, p);
                if (p >= json.size() || json[p] == L']')
                    break;
                if (json[p] == L',') {
                    ++p;
                    continue;
                }
                if (json[p] == L'{') {
                    ++p;
                    while (p < json.size()) {
                        jSkipWS(json, p);
                        if (p >= json.size() || json[p] == L'}')
                            break;
                        if (json[p] == L',') {
                            ++p;
                            continue;
                        }
                        jReadString(json, p);
                        jSkipWS(json, p);
                        if (p < json.size() && json[p] == L':')
                            ++p;
                        jSkipValue(json, p);
                    }
                } else {
                    jSkipValue(json, p);
                }
            }
        } else {
            jSkipValue(json, p);
        }
    }
    if (sectionCount < 4) {
        errorMessage = L"Missing sections in mapping file.";
        return false;
    }
    return true;
}

bool AnsiRegistry::trySetAnsiVersion(const std::wstring& newVersion,
                                     std::wstring& errorMessage) {
    // Every version resolves to a file in the mapping folder; there is no
    // built-in "Default" entry to switch to any more.
    if (ansiMappingDir.empty()) {
        errorMessage = L"ANSI Mapping directory is not set.";
        return false;
    }
    const std::wstring filePath = resolveMappingPath(ansiMappingDir, newVersion);

    // Decode once: a container costs a decrypt + inflate, so validating the
    // text and then loading it share this single pass instead of reading the
    // file twice.  The version only advances once the file has been proven
    // loadable, so a bad file leaves the active mapping untouched.
    std::wstring json;
    std::wstring readError;
    switch (readMappingJson(filePath, json, readError)) {
    case MappingRead::Missing:
        errorMessage = L"File does not exist.";
        return false;
    case MappingRead::Unreadable:
        errorMessage = readError;
        return false;
    case MappingRead::Ok:
        break;
    }
    if (!validateMappingJson(json, errorMessage))
        return false;

    ansiVersion = newVersion;
    resetToDefaults();
    try {
        parseJson(json, nullptr);
    } catch (...) {
        errorMessage = L"Critical: Invalid JSON Syntax.";
        return false;
    }
    return true;
}

} // namespace avro
