// bangla_chars.h - Bengali Unicode code-point constants and predicates.
// Faithful port of BanglaChars.pas.  All values are Unicode code units
// (UTF-16), matching the Delphi UnicodeString semantics exactly.

#pragma once

#include <string>

namespace bangla {

using Char = wchar_t;

// Unusual Bangla Characters
inline constexpr Char b_Vocalic_L  = 0x098C;
inline constexpr Char b_Vocalic_LL = 0x09E1;
inline constexpr Char b_Vocalic_RR = 0x09E0;
// Vowel signs (Kar/Matra)
inline constexpr Char b_Vocalic_RR_Kar = 0x09C4;
inline constexpr Char b_Vocalic_L_Kar  = 0x09E2;
inline constexpr Char b_Vocalic_LL_Kar = 0x09E3;
// Signs
inline constexpr Char b_Nukta      = 0x09BC;
inline constexpr Char b_Avagraha   = 0x09BD;
inline constexpr Char b_LengthMark = 0x09D7;
// Additional
inline constexpr Char b_RupeeMark        = 0x09F2;
inline constexpr Char b_CurrencyNumerator1 = 0x09F4;
inline constexpr Char b_CurrencyNumerator2 = 0x09F5;
inline constexpr Char b_CurrencyNumerator3 = 0x09F6;
inline constexpr Char b_CurrencyNumerator4 = 0x09F7;
inline constexpr Char b_CurrencyNumerator1LessThanDenominator = 0x09F8;
inline constexpr Char b_CurrencyDenominator16 = 0x09F9;
inline constexpr Char b_CurrencyEsshar = 0x09FA;

// Bangla Numbers
inline constexpr Char b_0 = 0x09E6, b_1 = 0x09E7, b_2 = 0x09E8, b_3 = 0x09E9,
                      b_4 = 0x09EA, b_5 = 0x09EB, b_6 = 0x09EC, b_7 = 0x09ED,
                      b_8 = 0x09EE, b_9 = 0x09EF;

// Bangla Vowels and Kars
inline constexpr Char b_A = 0x0985, b_AA = 0x0986, b_AAkar = 0x09BE,
                      b_I = 0x0987, b_II = 0x0988, b_IIkar = 0x09C0,
                      b_Ikar = 0x09BF, b_U = 0x0989, b_Ukar = 0x09C1,
                      b_UU = 0x098A, b_UUkar = 0x09C2, b_RRI = 0x098B,
                      b_RRIkar = 0x09C3, b_E = 0x098F, b_Ekar = 0x09C7,
                      b_O = 0x0993, b_OI = 0x0990, b_OIkar = 0x09C8,
                      b_Okar = 0x09CB, b_OU = 0x0994, b_OUkar = 0x09CC;

// Bangla Consonants
inline constexpr Char b_Anushar  = 0x0982;
inline constexpr Char b_B        = 0x09AC;
inline constexpr Char b_Bh       = 0x09AD;
inline constexpr Char b_Bisharga = 0x0983;
inline constexpr Char b_C        = 0x099A;
inline constexpr Char b_CH       = 0x099B;
inline constexpr Char b_Chandra  = 0x0981;
inline constexpr Char b_D        = 0x09A6;
inline constexpr Char b_Dd       = 0x09A1;
inline constexpr Char b_Ddh      = 0x09A2;
inline constexpr Char b_Dh       = 0x09A7;
inline constexpr Char b_G        = 0x0997;
inline constexpr Char b_GH       = 0x0998;
inline constexpr Char b_H        = 0x09B9;
inline constexpr Char b_J        = 0x099C;
inline constexpr Char b_JH       = 0x099D;
inline constexpr Char b_K        = 0x0995;
inline constexpr Char b_KH       = 0x0996;
inline constexpr Char b_L        = 0x09B2;
inline constexpr Char b_M        = 0x09AE;
inline constexpr Char b_N        = 0x09A8;
inline constexpr Char b_NGA      = 0x0999;
inline constexpr Char b_Nn       = 0x09A3;
inline constexpr Char b_NYA      = 0x099E;
inline constexpr Char b_P        = 0x09AA;
inline constexpr Char b_Ph       = 0x09AB;
inline constexpr Char b_R        = 0x09B0;
inline constexpr Char b_Rr       = 0x09DC;
inline constexpr Char b_Rrh      = 0x09DD;
inline constexpr Char b_S        = 0x09B8;
inline constexpr Char b_Sh       = 0x09B6;
inline constexpr Char b_Ss       = 0x09B7;
inline constexpr Char b_T        = 0x09A4;
inline constexpr Char b_Th       = 0x09A5;
inline constexpr Char b_Tt       = 0x099F;
inline constexpr Char b_Tth      = 0x09A0;
inline constexpr Char b_Y        = 0x09DF;
inline constexpr Char b_Z        = 0x09AF;
inline constexpr Char AssamRa    = 0x09F0;
inline constexpr Char AssamVa    = 0x09F1;
inline constexpr Char b_Khandatta = 0x09CE;

// Bangla Others
inline constexpr Char b_Dari    = 0x0964;
inline constexpr Char b_Hasanta = 0x09CD;
inline constexpr Char b_Taka    = 0x09F3;
inline constexpr Char ZWJ       = 0x200D;
inline constexpr Char ZWNJ      = 0x200C;
inline constexpr Char b_StartSingleQuote = 0x2018; // '
inline constexpr Char b_EndSingleQuote   = 0x2019; // '
inline constexpr Char b_StartDoubleQuote = 0x201C; // "
inline constexpr Char b_EndDoubleQuote   = 0x201D; // "

// Lower-case aliases used throughout the converter (Delphi identifiers are
// case-insensitive; the source mixes b_s / b_S etc.).
inline constexpr Char b_s = b_S, b_ss = b_Ss, b_m = b_M, b_n = b_N, b_d = b_D,
                      b_dh = b_Dh, b_b = b_B, b_h = b_H, b_sh = b_Sh, b_g = b_G,
                      b_p = b_P, b_t = b_T,
                      b_kh = b_KH, b_gh = b_GH, b_ch = b_CH, b_j = b_J,
                      b_jh = b_JH, b_nya = b_NYA, b_tt = b_Tt, b_tth = b_Tth,
                      b_dd = b_Dd, b_ddh = b_Ddh, b_ph = b_Ph, b_r = b_R,
                      b_y = b_Y, b_z = b_Z, b_rr = b_Rr, b_rrh = b_Rrh;

inline bool IsVowel(Char wc) {
    return wc == b_A || wc == b_AA || wc == b_AAkar || wc == b_I || wc == b_II ||
           wc == b_IIkar || wc == b_Ikar || wc == b_U || wc == b_Ukar ||
           wc == b_UU || wc == b_UUkar || wc == b_RRI || wc == b_RRIkar ||
           wc == b_E || wc == b_Ekar || wc == b_OI || wc == b_OIkar ||
           wc == b_O || wc == b_Okar || wc == b_OU || wc == b_OUkar ||
           wc == b_Vocalic_L || wc == b_Vocalic_LL || wc == b_Vocalic_RR ||
           wc == b_Vocalic_RR_Kar || wc == b_Vocalic_L_Kar || wc == b_Vocalic_LL_Kar;
}

inline bool IsPureConsonent(Char wc) {
    return wc == b_B || wc == b_Bh || wc == b_C || wc == b_CH || wc == b_D ||
           wc == b_Dd || wc == b_Ddh || wc == b_Dh || wc == b_G || wc == b_GH ||
           wc == b_H || wc == b_J || wc == b_JH || wc == b_K || wc == b_KH ||
           wc == b_L || wc == b_M || wc == b_N || wc == b_NGA || wc == b_Nn ||
           wc == b_NYA || wc == b_P || wc == b_Ph || wc == b_R || wc == b_Rr ||
           wc == b_Rrh || wc == b_S || wc == b_Sh || wc == b_Ss || wc == b_T ||
           wc == b_Th || wc == b_Tt || wc == b_Tth || wc == b_Z || wc == b_Y ||
           wc == b_Khandatta || wc == AssamRa || wc == AssamVa;
}

inline bool IsKar(Char wc) {
    return wc == b_AAkar || wc == b_IIkar || wc == b_Ikar || wc == b_Ukar ||
           wc == b_UUkar || wc == b_RRIkar || wc == b_Ekar || wc == b_OIkar ||
           wc == b_OUkar || wc == b_Vocalic_RR_Kar || wc == b_Vocalic_L_Kar ||
           wc == b_Vocalic_LL_Kar;
}

} // namespace bangla
