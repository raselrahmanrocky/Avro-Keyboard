{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
unit clsUnicodeToBijoy2000;

interface

uses
  System.Classes,
  System.Generics.Collections;

type
  TUnicodeToBijoy2000 = class
    private
      fUniText:       string;
      fConvertedText: string;
      fRaUKarToggle:  Boolean;
      fRaUUKarToggle: Boolean;
      fLastUniText:   string;
      procedure ReArrangeKars;
      procedure ReArrangeReph;
      procedure ReplaceFullForms;
      procedure ReplaceKarsVowels;
      procedure ConvertRFola_ZFola_Hasanta;
      procedure FirstHalfForms;
      procedure SecondHalfForms;
      procedure Consonants;
      procedure FinalTouch;
      procedure DeNormalize;

      // Utility Functions
      function BaseLineRightCharacter(const wC: string): Boolean;
      function GetVowelGlyph(const AVowel, AConsonant: string; UseAlt: Boolean): string;
      function WideStuffString(Source: string; Start, Len: Integer; SubString: string): string;
      function IsVowel(C: Char): Boolean;
    public
      function Convert(const UniText: string): string;
      property RaUKarToggle: Boolean read fRaUKarToggle write fRaUKarToggle;
      property RaUUKarToggle: Boolean read fRaUUKarToggle write fRaUUKarToggle;
  end;

  TReplacementPair = record
    Key: string;
    Value: string;
  end;

  TVowelMapping = record
    Consonants: string;
    Value: string;
    AltValue: string;
  end;

  TVowelRule = record
    Vowel: string;
    DefaultVal: string;
    BaselineRightVal: string;
    Mappings: TArray<TVowelMapping>;
  end;

  TAnsiVarType = (avChar, avString);

  TAnsiVarRec = record
    Name: string;
    Category: string;
    VarType: TAnsiVarType;
    Ptr: Pointer;
    DefaultVal: string;
    BengaliChar: string;
  end;

var
  CustomFullForms: TArray<TReplacementPair>;
  CustomPreReplacements: TArray<TReplacementPair>;
  CustomPostReplacements: TArray<TReplacementPair>; 
  AnsiVersion: string = 'Default';
  AnsiMappingDir: string = '';
  AnsiRegistry: TList<TAnsiVarRec>;
  AnsiRegistryMap: TDictionary<string, TAnsiVarRec>;
  ActiveReplacements: TArray<TReplacementPair>;
  AnsiOverrides: TDictionary<string, string>;
  ConsonantGroupsMap: TDictionary<string, TList<string>> = nil;
  VowelRulesList: TList<TVowelRule> = nil;


procedure ResetAnsiToDefaults;
procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);
procedure ExportAnsiMapping(const Path: string);
procedure LoadCurrentActiveMapping(ErrorLog: TStringList = nil);
function ValidateAnsiMappingFile(const Path: string; out ErrorMessage: string): Boolean;
function TrySetAnsiVersion(const NewVersion: string; out ErrorMessage: string): Boolean;
procedure OptimizeMemoryUsage;

implementation

uses
  Windows,
  Strutils,
  BanglaChars,
  System.SysUtils,
  System.Generics.Defaults;

{ Bijoy2000 Font Map Constants }
var
   { Numbers }
  A_0: string = #$30;
  A_1: string = #$31;
  A_2: string = #$32;
  A_3: string = #$33;
  A_4: string = #$34;
  A_5: string = #$35;
  A_6: string = #$36;
  A_7: string = #$37;
  A_8: string = #$38;
  A_9: string = #$39;

   { Vowels and Kars }
   A_A: string     = #$41;
   A_AA: string    = #$41#$76;
   A_AAKar: string = #$76;
   A_I: string     = #$42;
   A_IKar: string  = #$77;
   A_II: string    = #$43;
   A_IIKar: string = #$78;
   A_U: string     = #$44;
   A_UKar2: string = #$79;
   A_UKar1: string = #$7A;
   A_UKar3: string = #$2013;
   A_UKar4: string = #$201C;
   A_UU: string    = #$45;
   A_UUKar2: string= #$7E;
   A_UUKar1: string= #$201A;
   A_UUKar3: string= #$192;
   A_RRI: string   = #$46;
   A_RRIKar1: string=#$201E;
   A_RRIKar2: string=#$2026;
   A_E: string     = #$47;
   A_EKar1: string = #$2020;
   A_EKar2: string = #$2021;
   A_OI: string    = #$48;
   A_OIKar1: string= #$2C6;
   A_OIKar2: string= #$2030;
   A_O: string     = #$49;
   A_OU: string    = #$4A;
   A_OUKar: string = #$160;

   { Symbols }
  A_Taka: string             = #$24;
  A_Dari: string             = #$7C;
  A_DoubleDanda: string      = #$5C;
  A_Hasanta: string          = #$26;
  A_StartDoubleQuote: string = #$D2;
  A_EndDoubleQuote: string   = #$D3;

  A_StartSingleQuote: string = #$D4;
  A_EndSingleQuote: string   = #$D5;

   { Consonants }
  A_K: string        = #$4B;
  A_Kh: string       = #$4C;
  A_G: string        = #$4D;
  A_Gh: string       = #$4E;
  A_NGA: string      = #$4F;
  A_C: string        = #$50;
  A_Ch: string       = #$51;
  A_J: string        = #$52;
  A_Jh: string       = #$53;
  A_NYA: string      = #$54;
  A_Tt: string       = #$55;
  A_Tth: string      = #$56;
  A_Dd: string       = #$57;
  A_Ddh: string      = #$58;
  A_Nn: string       = #$59;
  A_T: string        = #$5A;
  A_Th: string       = #$5F;
  A_D: string        = #$60;
  A_Dh: string       = #$61;
  A_N: string        = #$62;
  A_P: string        = #$63;
  A_Ph: string       = #$64;
  A_B: string        = #$65;
  A_Bh: string       = #$66;
  A_M: string        = #$67;
  A_Z: string        = #$68;
  A_R: string        = #$69;
  A_L: string        = #$6A;
  A_Sh: string       = #$6B;
  A_SS: string       = #$6C;
  A_S: string        = #$6D;
  A_H: string        = #$6E;
  A_RR: string       = #$6F;
  A_RRH: string      = #$70;
  A_Y: string        = #$71;
  A_Khandata: string = #$72;
  A_Anushar: string  = #$73;
  A_Bisharga: string = #$74;
  A_Chandra: string  = #$75;

  { Full Forms }
  A_K_K: string      = #$B0;
  A_K_Tt: string     = #$B1;
  A_K_Ss_M: string   = #$B2;
  A_K_T: string      = #$B3;
  A_K_M: string      = #$B4;
  A_K_R: string      = #$B5;
  A_K_Ss: string     = #$B6;
  A_K_S: string      = #$B7;
  A_G_Ukar: string   = #$B8;
  A_G_G: string      = #$B9;
  A_G_D: string      = #$BA;
  A_G_Dh: string     = #$BB;
  A_NGA_K: string    = #$BC;
  A_NGA_G: string    = #$BD;
  A_J_J: string      = #$BE;
  A_J_Jh: string     = #$C0;
  A_J_NYA: string    = #$C1;
  A_NYA_C: string    = #$C2;
  A_NYA_CH: string   = #$C3;
  A_NYA_J: string    = #$C4;
  A_NYA_Jh: string   = #$C5;
  A_Tt_Tt: string    = #$C6;
  A_Dd_Dd: string    = #$C7;
  A_Nn_Tt: string    = #$C8;
  A_Nn_Tth: string   = #$C9;
  A_NN_Dd: string    = #$CA;
  A_T_T: string      = #$CB;
  A_T_Th: string     = #$CC;
  A_T_M: string      = #$CD;
  A_T_R: string      = #$CE;
  A_D_D: string      = #$CF;
  A_D_Dh: string     = #$D7;
  A_D_B: string      = #$D8;
  A_D_M: string      = #$D9;
  A_N_Tth: string    = #$DA;
  A_N_Dd: string     = #$DB;
  A_N_Dh: string     = #$DC;
  A_N_S: string      = #$DD;
  A_P_Tt: string     = #$DE;
  A_P_T: string      = #$DF;
  A_P_P: string      = #$E0;
  A_P_S: string      = #$E1;
  A_B_J: string      = #$E2;
  A_B_D: string      = #$E3;
  A_B_Dh: string     = #$E4;
  A_Bh_R: string     = #$E5;
  A_M_N: string      = #$E6;
  A_M_Ph: string     = #$E7;
  A_L_K: string      = #$E9;
  A_L_G: string      = #$EA;
  A_L_Tt: string     = #$EB;
  A_L_Dd: string     = #$EC;
  A_L_P: string      = #$ED;
  A_L_Ph: string     = #$EE;
  A_Sh_UKar: string  = #$EF;
  A_Sh_C: string     = #$F0;
  A_Sh_Ch: string    = #$F1;
  A_Ss_Nn: string    = #$F2;
  A_Ss_Tt: string    = #$F3;
  A_Ss_Tth: string   = #$F4;
  A_Ss_Ph: string    = #$F5;
  A_S_Kh: string     = #$F6;
  A_S_Tt: string     = #$F7;
  A_S_N: string      = #$F8;
  A_S_Ph: string     = #$F9;
  A_H_UKar: string   = #$FB;
  A_H_RRIKar: string = #$FC;
  A_H_N: string      = #$FD;
  A_H_M: string      = #$FE;
  A_Rr_G: string     = #$FF;

   { First Half forms }
   A_Reph: string   = #$A9;
   A_M_1H: string   = #$A4;
   A_Ss_1H: string  = #$AE;
   A_S_1H_1: string = #$AF;
   A_N_1H_1: string = #$161;
   A_S_1H_2: string = #$2C9; // -----------Not used
   A_D_1H_1: string = #$2DC;
   A_C_1H: string   = #$201D;
   A_NGA_1H: string = #$2022;
   A_N_1H_2: string = #$203A;
   A_D_1H_2: string = #$2122;

   { Second Half forms }
   A_B_2H_1: string    = #$5E; //
   A_B_2H_2: string    = #$A1; //
   A_BH_2H: string     = #$A2; //
   A_BH_R_2H: string   = #$A3; //
   A_M_2H_1: string    = #$A5; //
   A_B_2H_3: string    = #$A6; //
   A_M_2H_2: string    = #$A7; //
   A_ZFola: string     = #$A8; //
   A_RFola_1: string   = #$AA; //
   A_RFola_2: string   = #$AB; //
   A_L_2H_1: string    = #$AC; //
   A_L_2H_2: string    = #$AD; // <--- Not used
   A_T_R_2H: string    = #$BF; //
   A_RFola_3: string   = #$D6; //
   A_Nn_2H_1: string   = #$E8;
   A_K_R_2H: string    = #$152; //
   A_Nn_2H_2: string   = #$153;
   A_B_2H_4: string    = #$178;  //
   A_T_2H: string      = #$2014; //
   A_T_UKar_2H: string = #$2018; //
   A_Th_2H: string     = #$2019; //
   A_K_2H: string      = #$2039; //
   A_L_2H_3: string    = #$2212; //


{ ============================================================================= }
{ Registry Initialization }
{ ============================================================================= }

procedure InitializeAnsiRegistry;

  procedure RegVar(const AName, ACategory: string; AVarType: TAnsiVarType;
    APtr: Pointer; const ADefaultVal, ABengali: string);
  var
    Rec: TAnsiVarRec;
  begin
    Rec.Name := AName;
    Rec.Category := ACategory;
    Rec.VarType := AVarType;
    Rec.Ptr := APtr;
    Rec.DefaultVal := ADefaultVal;
    Rec.BengaliChar := ABengali;
    AnsiRegistry.Add(Rec);
    AnsiRegistryMap.AddOrSetValue(AName, Rec);
  end;

begin
  AnsiRegistry := TList<TAnsiVarRec>.Create;
  AnsiRegistryMap := TDictionary<string, TAnsiVarRec>.Create;

  // Numbers
  RegVar('A_0', 'Numbers', avString, @A_0, '#$30', '০');
  RegVar('A_1', 'Numbers', avString, @A_1, '#$31', '১');
  RegVar('A_2', 'Numbers', avString, @A_2, '#$32', '২');
  RegVar('A_3', 'Numbers', avString, @A_3, '#$33', '৩');
  RegVar('A_4', 'Numbers', avString, @A_4, '#$34', '৪');
  RegVar('A_5', 'Numbers', avString, @A_5, '#$35', '৫');
  RegVar('A_6', 'Numbers', avString, @A_6, '#$36', '৬');
  RegVar('A_7', 'Numbers', avString, @A_7, '#$37', '৭');
  RegVar('A_8', 'Numbers', avString, @A_8, '#$38', '৮');
  RegVar('A_9', 'Numbers', avString, @A_9, '#$39', '৯');

   // VowelsAndKars
   RegVar('A_A', 'VowelsAndKars', avString, @A_A, '#$41', 'অ');
   RegVar('A_AA', 'VowelsAndKars', avString, @A_AA, '#$41#$76', 'আ');
   RegVar('A_AAKar', 'VowelsAndKars', avString, @A_AAKar, '#$76', 'া (আ-কার)');
   RegVar('A_I', 'VowelsAndKars', avString, @A_I, '#$42', 'ই');
   RegVar('A_IKar', 'VowelsAndKars', avString, @A_IKar, '#$77', 'ি (ই-কার)');
   RegVar('A_II', 'VowelsAndKars', avString, @A_II, '#$43', 'ঈ');
   RegVar('A_IIKar', 'VowelsAndKars', avString, @A_IIKar, '#$78', 'ী (ঈ-কার)');
   RegVar('A_U', 'VowelsAndKars', avString, @A_U, '#$44', 'উ');
   RegVar('A_UKar2', 'VowelsAndKars', avString, @A_UKar2, '#$79', 'ু (উ-কার ২ - ঝুলন্ত)');
   RegVar('A_UKar1', 'VowelsAndKars', avString, @A_UKar1, '#$7A', 'ু (উ-কার ১ - সাধারণ)');
   RegVar('A_UKar3', 'VowelsAndKars', avString, @A_UKar3, '#$2013', 'ু (উ-কার ৩ - ড়ু/ঢ়ু)');
   RegVar('A_UKar4', 'VowelsAndKars', avString, @A_UKar4, '#$201C', 'ু (উ-কার ৪ - রু)');
   RegVar('A_UU', 'VowelsAndKars', avString, @A_UU, '#$45', 'ঊ');
   RegVar('A_UUKar2', 'VowelsAndKars', avString, @A_UUKar2, '#$7E', 'ূ (ঊ-কার ২ - ঝুলন্ত)');
   RegVar('A_UUKar1', 'VowelsAndKars', avString, @A_UUKar1, '#$201A', 'ূ (ঊ-কার ১ - সাধারণ)');
   RegVar('A_UUKar3', 'VowelsAndKars', avString, @A_UUKar3, '#$192', 'ূ (ঊ-কার ৩ - রূ)');
   RegVar('A_RRI', 'VowelsAndKars', avString, @A_RRI, '#$46', 'ঋ');
   RegVar('A_RRIKar1', 'VowelsAndKars', avString, @A_RRIKar1, '#$201E', 'ৃ (ঋ-কার ১)');
   RegVar('A_RRIKar2', 'VowelsAndKars', avString, @A_RRIKar2, '#$2026', 'ৃ (ঋ-কার ২)');
   RegVar('A_E', 'VowelsAndKars', avString, @A_E, '#$47', 'এ');
   RegVar('A_EKar1', 'VowelsAndKars', avString, @A_EKar1, '#$2020', 'ে (এ-কার ১ - সাধারণ)');
   RegVar('A_EKar2', 'VowelsAndKars', avString, @A_EKar2, '#$2021', 'ে (এ-কার ২ - ঝুলন্ত)');
   RegVar('A_OI', 'VowelsAndKars', avString, @A_OI, '#$48', 'ঐ');
   RegVar('A_OIKar1', 'VowelsAndKars', avString, @A_OIKar1, '#$2C6', 'ৈ (ঐ-কার ১ - সাধারণ)');
   RegVar('A_OIKar2', 'VowelsAndKars', avString, @A_OIKar2, '#$2030', 'ৈ (ঐ-কার ২ - ঝুলন্ত)');
   RegVar('A_O', 'VowelsAndKars', avString, @A_O, '#$49', 'ও');
   RegVar('A_OU', 'VowelsAndKars', avString, @A_OU, '#$4A', 'ঔ');
   RegVar('A_OUKar', 'VowelsAndKars', avString, @A_OUKar, '#$160', 'ৌ (ঔ-কার)');

  // Symbols
  RegVar('A_Taka', 'Symbols', avString, @A_Taka, '#$24', '৳ (টাকা)');
  RegVar('A_Dari', 'Symbols', avString, @A_Dari, '#$7C', '। (দাঁড়ি)');
  RegVar('A_DoubleDanda', 'Symbols', avString, @A_DoubleDanda, '#$5C', '॥ (দ্বিত্ব দাঁড়ি)');
  RegVar('A_Hasanta', 'Symbols', avString, @A_Hasanta, '#$26', '্ (হসন্ত)');
  RegVar('A_StartDoubleQuote', 'Symbols', avString, @A_StartDoubleQuote, '#$D2', '" (উদ্ধৃতি শুরু)');
  RegVar('A_EndDoubleQuote', 'Symbols', avString, @A_EndDoubleQuote, '#$D3', '" (উদ্ধৃতি শেষ)');
  RegVar('A_StartSingleQuote', 'Symbols', avString, @A_StartSingleQuote, '#$D4', ''' (একক উদ্ধৃতি শুরু)');
  RegVar('A_EndSingleQuote', 'Symbols', avString, @A_EndSingleQuote, '#$D5', ''' (একক উদ্ধৃতি শেষ)');

  // Consonants
  RegVar('A_K', 'Consonants', avString, @A_K, '#$4B', 'ক');
  RegVar('A_Kh', 'Consonants', avString, @A_Kh, '#$4C', 'খ');
  RegVar('A_G', 'Consonants', avString, @A_G, '#$4D', 'গ');
  RegVar('A_Gh', 'Consonants', avString, @A_Gh, '#$4E', 'ঘ');
  RegVar('A_NGA', 'Consonants', avString, @A_NGA, '#$4F', 'ঙ');
  RegVar('A_C', 'Consonants', avString, @A_C, '#$50', 'চ');
  RegVar('A_Ch', 'Consonants', avString, @A_Ch, '#$51', 'ছ');
  RegVar('A_J', 'Consonants', avString, @A_J, '#$52', 'জ');
  RegVar('A_Jh', 'Consonants', avString, @A_Jh, '#$53', 'ঝ');
  RegVar('A_NYA', 'Consonants', avString, @A_NYA, '#$54', 'ঞ');
  RegVar('A_Tt', 'Consonants', avString, @A_Tt, '#$55', 'ট');
  RegVar('A_Tth', 'Consonants', avString, @A_Tth, '#$56', 'ঠ');
  RegVar('A_Dd', 'Consonants', avString, @A_Dd, '#$57', 'ড');
  RegVar('A_Ddh', 'Consonants', avString, @A_Ddh, '#$58', 'ঢ');
  RegVar('A_Nn', 'Consonants', avString, @A_Nn, '#$59', 'ণ');
  RegVar('A_T', 'Consonants', avString, @A_T, '#$5A', 'ত');
  RegVar('A_Th', 'Consonants', avString, @A_Th, '#$5F', 'থ');
  RegVar('A_D', 'Consonants', avString, @A_D, '#$60', 'দ');
  RegVar('A_Dh', 'Consonants', avString, @A_Dh, '#$61', 'ধ');
  RegVar('A_N', 'Consonants', avString, @A_N, '#$62', 'ন');
  RegVar('A_P', 'Consonants', avString, @A_P, '#$63', 'প');
  RegVar('A_Ph', 'Consonants', avString, @A_Ph, '#$64', 'ফ');
  RegVar('A_B', 'Consonants', avString, @A_B, '#$65', 'ব');
  RegVar('A_Bh', 'Consonants', avString, @A_Bh, '#$66', 'ভ');
  RegVar('A_M', 'Consonants', avString, @A_M, '#$67', 'ম');
  RegVar('A_Z', 'Consonants', avString, @A_Z, '#$68', 'য');
  RegVar('A_R', 'Consonants', avString, @A_R, '#$69', 'র');
  RegVar('A_L', 'Consonants', avString, @A_L, '#$6A', 'ল');
  RegVar('A_Sh', 'Consonants', avString, @A_Sh, '#$6B', 'শ');
  RegVar('A_SS', 'Consonants', avString, @A_SS, '#$6C', 'ষ');
  RegVar('A_S', 'Consonants', avString, @A_S, '#$6D', 'স');
  RegVar('A_H', 'Consonants', avString, @A_H, '#$6E', 'হ');
  RegVar('A_RR', 'Consonants', avString, @A_RR, '#$6F', 'ড়');
  RegVar('A_RRH', 'Consonants', avString, @A_RRH, '#$70', 'ঢ়');
  RegVar('A_Y', 'Consonants', avString, @A_Y, '#$71', 'য়');
  RegVar('A_Khandata', 'Consonants', avString, @A_Khandata, '#$72', 'ৎ');
  RegVar('A_Anushar', 'Consonants', avString, @A_Anushar, '#$73', 'ং');
  RegVar('A_Bisharga', 'Consonants', avString, @A_Bisharga, '#$74', 'ঃ');
  RegVar('A_Chandra', 'Consonants', avString, @A_Chandra, '#$75', 'ঁ');

  // FullForms
  RegVar('A_K_K', 'FullForms', avString, @A_K_K, '#$B0', 'ক্ক');
  RegVar('A_K_Tt', 'FullForms', avString, @A_K_Tt, '#$B1', 'ক্ট');
  RegVar('A_K_Ss_M', 'FullForms', avString, @A_K_Ss_M, '#$B2', 'ক্স্ম');
  RegVar('A_K_T', 'FullForms', avString, @A_K_T, '#$B3', 'ক্ত');
  RegVar('A_K_M', 'FullForms', avString, @A_K_M, '#$B4', 'ক্ম');
  RegVar('A_K_R', 'FullForms', avString, @A_K_R, '#$B5', 'ক্র');
  RegVar('A_K_Ss', 'FullForms', avString, @A_K_Ss, '#$B6', 'ক্ষ');
  RegVar('A_K_S', 'FullForms', avString, @A_K_S, '#$B7', 'ক্স');
  RegVar('A_G_Ukar', 'FullForms', avString, @A_G_Ukar, '#$B8', 'গু');
  RegVar('A_G_G', 'FullForms', avString, @A_G_G, '#$B9', 'গ্গ');
  RegVar('A_G_D', 'FullForms', avString, @A_G_D, '#$BA', 'গ্দ');
  RegVar('A_G_Dh', 'FullForms', avString, @A_G_Dh, '#$BB', 'গ্ধ');
  RegVar('A_NGA_K', 'FullForms', avString, @A_NGA_K, '#$BC', 'ঙ্ক');
  RegVar('A_NGA_G', 'FullForms', avString, @A_NGA_G, '#$BD', 'ঙ্গ');
  RegVar('A_J_J', 'FullForms', avString, @A_J_J, '#$BE', 'জ্জ');
  RegVar('A_J_Jh', 'FullForms', avString, @A_J_Jh, '#$C0', 'জ্ঝ');
  RegVar('A_J_NYA', 'FullForms', avString, @A_J_NYA, '#$C1', 'জ্ঞ');
  RegVar('A_NYA_C', 'FullForms', avString, @A_NYA_C, '#$C2', 'ঞ্চ');
  RegVar('A_NYA_CH', 'FullForms', avString, @A_NYA_CH, '#$C3', 'ঞ্ছ');
  RegVar('A_NYA_J', 'FullForms', avString, @A_NYA_J, '#$C4', 'ঞ্জ');
  RegVar('A_NYA_Jh', 'FullForms', avString, @A_NYA_Jh, '#$C5', 'ঞ্ঝ');
  RegVar('A_Tt_Tt', 'FullForms', avString, @A_Tt_Tt, '#$C6', 'ট্ট');
  RegVar('A_Dd_Dd', 'FullForms', avString, @A_Dd_Dd, '#$C7', 'ড্ড');
  RegVar('A_Nn_Tt', 'FullForms', avString, @A_Nn_Tt, '#$C8', 'ণ্ট');
  RegVar('A_Nn_Tth', 'FullForms', avString, @A_Nn_Tth, '#$C9', 'ণ্ঠ');
  RegVar('A_NN_Dd', 'FullForms', avString, @A_NN_Dd, '#$CA', 'ণ্ড');
  RegVar('A_T_T', 'FullForms', avString, @A_T_T, '#$CB', 'ত্ত');
  RegVar('A_T_Th', 'FullForms', avString, @A_T_Th, '#$CC', 'ত্থ');
  RegVar('A_T_M', 'FullForms', avString, @A_T_M, '#$CD', 'ত্ম');
  RegVar('A_T_R', 'FullForms', avString, @A_T_R, '#$CE', 'ত্র');
  RegVar('A_D_D', 'FullForms', avString, @A_D_D, '#$CF', 'দ্দ');
  RegVar('A_D_Dh', 'FullForms', avString, @A_D_Dh, '#$D7', 'দ্ধ');
  RegVar('A_D_B', 'FullForms', avString, @A_D_B, '#$D8', 'দ্ব');
  RegVar('A_D_M', 'FullForms', avString, @A_D_M, '#$D9', 'দ্ম');
  RegVar('A_N_Tth', 'FullForms', avString, @A_N_Tth, '#$DA', 'ন্থ');
  RegVar('A_N_Dd', 'FullForms', avString, @A_N_Dd, '#$DB', 'ন্ড');
  RegVar('A_N_Dh', 'FullForms', avString, @A_N_Dh, '#$DC', 'ন্ধ');
  RegVar('A_N_S', 'FullForms', avString, @A_N_S, '#$DD', 'ন্স');
  RegVar('A_P_Tt', 'FullForms', avString, @A_P_Tt, '#$DE', 'প্ট');
  RegVar('A_P_T', 'FullForms', avString, @A_P_T, '#$DF', 'প্ত');
  RegVar('A_P_P', 'FullForms', avString, @A_P_P, '#$E0', 'প্প');
  RegVar('A_P_S', 'FullForms', avString, @A_P_S, '#$E1', 'প্স');
  RegVar('A_B_J', 'FullForms', avString, @A_B_J, '#$E2', 'ব্জ');
  RegVar('A_B_D', 'FullForms', avString, @A_B_D, '#$E3', 'ব্দ');
  RegVar('A_B_Dh', 'FullForms', avString, @A_B_Dh, '#$E4', 'ব্ধ');
  RegVar('A_Bh_R', 'FullForms', avString, @A_Bh_R, '#$E5', 'ভ্র');
  RegVar('A_M_N', 'FullForms', avString, @A_M_N, '#$E6', 'ম্ন');
  RegVar('A_M_Ph', 'FullForms', avString, @A_M_Ph, '#$E7', 'ম্ফ');
  RegVar('A_L_K', 'FullForms', avString, @A_L_K, '#$E9', 'ল্ক');
  RegVar('A_L_G', 'FullForms', avString, @A_L_G, '#$EA', 'ল্গ');
  RegVar('A_L_Tt', 'FullForms', avString, @A_L_Tt, '#$EB', 'ল্ট');
  RegVar('A_L_Dd', 'FullForms', avString, @A_L_Dd, '#$EC', 'ল্ড');
  RegVar('A_L_P', 'FullForms', avString, @A_L_P, '#$ED', 'ল্প');
  RegVar('A_L_Ph', 'FullForms', avString, @A_L_Ph, '#$EE', 'ল্ফ');
  RegVar('A_Sh_UKar', 'FullForms', avString, @A_Sh_UKar, '#$EF', 'শু');
  RegVar('A_Sh_C', 'FullForms', avString, @A_Sh_C, '#$F0', 'শ্চ');
  RegVar('A_Sh_Ch', 'FullForms', avString, @A_Sh_Ch, '#$F1', 'শ্ছ');
  RegVar('A_Ss_Nn', 'FullForms', avString, @A_Ss_Nn, '#$F2', 'ষ্ণ');
  RegVar('A_Ss_Tt', 'FullForms', avString, @A_Ss_Tt, '#$F3', 'ষ্ট');
  RegVar('A_Ss_Tth', 'FullForms', avString, @A_Ss_Tth, '#$F4', 'ষ্ঠ');
  RegVar('A_Ss_Ph', 'FullForms', avString, @A_Ss_Ph, '#$F5', 'স্ফ');
  RegVar('A_S_Kh', 'FullForms', avString, @A_S_Kh, '#$F6', 'স্খ');
  RegVar('A_S_Tt', 'FullForms', avString, @A_S_Tt, '#$F7', 'স্ট');
  RegVar('A_S_N', 'FullForms', avString, @A_S_N, '#$F8', 'স্ন');
  RegVar('A_S_Ph', 'FullForms', avString, @A_S_Ph, '#$F9', 'স্ফ');
  RegVar('A_H_UKar', 'FullForms', avString, @A_H_UKar, '#$FB', 'হু');
  RegVar('A_H_RRIKar', 'FullForms', avString, @A_H_RRIKar, '#$FC', 'হৃ');
  RegVar('A_H_N', 'FullForms', avString, @A_H_N, '#$FD', 'হ্ন');
  RegVar('A_H_M', 'FullForms', avString, @A_H_M, '#$FE', 'হ্ম');
  RegVar('A_Rr_G', 'FullForms', avString, @A_Rr_G, '#$FF', 'র্গ');

   // FirstHalfForms
   RegVar('A_Reph', 'FirstHalfForms', avString, @A_Reph, '#$A9', '্র (র-এর রেফ)');
   RegVar('A_M_1H', 'FirstHalfForms', avString, @A_M_1H, '#$A4', 'ম-এর প্রথম খন্ড');
   RegVar('A_Ss_1H', 'FirstHalfForms', avString, @A_Ss_1H, '#$AE', 'ষ-এর প্রথম খন্ড');
   RegVar('A_S_1H_1', 'FirstHalfForms', avString, @A_S_1H_1, '#$AF', 'স-এর প্রথম খন্ড ১');
   RegVar('A_N_1H_1', 'FirstHalfForms', avString, @A_N_1H_1, '#$161', 'ন-এর প্রথম খন্ড ১');
   RegVar('A_S_1H_2', 'FirstHalfForms', avString, @A_S_1H_2, '#$2C9', 'স-এর প্রথম খন্ড ২');
   RegVar('A_D_1H_1', 'FirstHalfForms', avString, @A_D_1H_1, '#$2DC', 'দ-এর প্রথম খন্ড ১');
   RegVar('A_C_1H', 'FirstHalfForms', avString, @A_C_1H, '#$201D', 'চ-এর প্রথম খন্ড');
   RegVar('A_NGA_1H', 'FirstHalfForms', avString, @A_NGA_1H, '#$2022', 'ঙ-এর প্রথম খন্ড');
   RegVar('A_N_1H_2', 'FirstHalfForms', avString, @A_N_1H_2, '#$203A', 'ন-এর প্রথম খন্ড ২');
   RegVar('A_D_1H_2', 'FirstHalfForms', avString, @A_D_1H_2, '#$2122', 'দ-এর প্রথম খন্ড ২');

   // SecondHalfForms
   RegVar('A_B_2H_1', 'SecondHalfForms', avString, @A_B_2H_1, '#$5E', 'ব-এর দ্বিতীয় খন্ড ১');
   RegVar('A_B_2H_2', 'SecondHalfForms', avString, @A_B_2H_2, '#$A1', 'ব-এর দ্বিতীয় খন্ড ২');
   RegVar('A_BH_2H', 'SecondHalfForms', avString, @A_BH_2H, '#$A2', 'ভ-এর দ্বিতীয় খন্ড');
   RegVar('A_BH_R_2H', 'SecondHalfForms', avString, @A_BH_R_2H, '#$A3', 'ভ্র-এর দ্বিতীয় খন্ড');
   RegVar('A_M_2H_1', 'SecondHalfForms', avString, @A_M_2H_1, '#$A5', 'ম-এর দ্বিতীয় খন্ড ১');
   RegVar('A_B_2H_3', 'SecondHalfForms', avString, @A_B_2H_3, '#$A6', 'ব-এর দ্বিতীয় খন্ড ৩');
   RegVar('A_M_2H_2', 'SecondHalfForms', avString, @A_M_2H_2, '#$A7', 'ম-এর দ্বিতীয় খন্ড ২');
   RegVar('A_ZFola', 'SecondHalfForms', avString, @A_ZFola, '#$A8', 'য-ফলা');
   RegVar('A_RFola_1', 'SecondHalfForms', avString, @A_RFola_1, '#$AA', 'র-ফলা ১');
   RegVar('A_RFola_2', 'SecondHalfForms', avString, @A_RFola_2, '#$AB', 'র-ফলা ২');
   RegVar('A_L_2H_1', 'SecondHalfForms', avString, @A_L_2H_1, '#$AC', 'ল-এর দ্বিতীয় খন্ড ১');
   RegVar('A_L_2H_2', 'SecondHalfForms', avString, @A_L_2H_2, '#$AD', 'ল-এর দ্বিতীয় খন্ড ২');
   RegVar('A_T_R_2H', 'SecondHalfForms', avString, @A_T_R_2H, '#$BF', 'ত্র-এর দ্বিতীয় খন্ড');
   RegVar('A_RFola_3', 'SecondHalfForms', avString, @A_RFola_3, '#$D6', 'র-ফলা ৩');
   RegVar('A_Nn_2H_1', 'SecondHalfForms', avString, @A_Nn_2H_1, '#$E8', 'ণ-এর দ্বিতীয় খন্ড ১');
   RegVar('A_K_R_2H', 'SecondHalfForms', avString, @A_K_R_2H, '#$152', 'ক্র-এর দ্বিতীয় খন্ড');
   RegVar('A_Nn_2H_2', 'SecondHalfForms', avString, @A_Nn_2H_2, '#$153', 'ণ-এর দ্বিতীয় খন্ড ২');
   RegVar('A_B_2H_4', 'SecondHalfForms', avString, @A_B_2H_4, '#$178', 'ব-এর দ্বিতীয় খন্ড ৪');
   RegVar('A_T_2H', 'SecondHalfForms', avString, @A_T_2H, '#$2014', 'ত-এর দ্বিতীয় খন্ড');
   RegVar('A_T_UKar_2H', 'SecondHalfForms', avString, @A_T_UKar_2H, '#$2018', 'তু-এর দ্বিতীয় খন্ড');
   RegVar('A_Th_2H', 'SecondHalfForms', avString, @A_Th_2H, '#$2019', 'থ-এর দ্বিতীয় খন্ড');
   RegVar('A_K_2H', 'SecondHalfForms', avString, @A_K_2H, '#$2039', 'ক-এর দ্বিতীয় খন্ড');
   RegVar('A_L_2H_3', 'SecondHalfForms', avString, @A_L_2H_3, '#$2212', 'ল-এর দ্বিতীয় খন্ড ৩');
end;
{ TUnicodeToBijoy2000 }
{ =============================================================================== }

procedure TUnicodeToBijoy2000.SecondHalfForms;
var
  I:  Integer;
  wT: string;
begin
  { A_BH_2H }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Bh, A_BH_2H);
  { A_T_2H }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_t, A_T_2H);
  { A_Th_2H }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Th, A_Th_2H);
  { A_K_2H }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_K, A_K_2H);

  { A_B_2H_1, A_B_2H_2, A_B_2H_3, A_B_2H_4 }
  repeat
    I := Pos(b_Hasanta + b_b, fConvertedText);
    if I <= 0 then
      break;
    wT := MidStr(fConvertedText, I - 1, 1);

    if ((wT = b_s) or (wT = b_ss) or (wT = b_m) or (wT = b_n) or (wT = b_d) or (wT = A_M_1H) or (wT = A_Ss_1H) or (wT = A_S_1H_1) or (wT = A_N_1H_1) or
        (wT = A_D_1H_2)) then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_B_2H_1)
    else if ((wT = b_dh) or (wT = b_b) or (wT = b_h)) then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_B_2H_4)
    else if ((wT = b_sh) or (wT = b_g) or (wT = b_p)) then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_B_2H_3)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_B_2H_2);
  until I <= 0;

  { A_M_2H_1  and  A_M_2H_2 }
  repeat
    I := Pos(b_Hasanta + b_m, fConvertedText);
    if I <= 0 then
      break;
    wT := MidStr(fConvertedText, I - 1, 1);
    if ((wT = A_M_1H) or (wT = A_Ss_1H) or (wT = A_C_1H) or (wT = A_S_1H_1) or (wT = A_D_1H_2) or (wT = A_N_1H_1) or (wT = A_N_1H_2)) then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_M_2H_2)
    else if wT = A_NGA_1H then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_M)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_M_2H_1);
  until I <= 0;

  { A_L_2H_1  and  A_L_2H_3 }
  repeat
    I := Pos(b_Hasanta + b_L, fConvertedText);
    if I <= 0 then
      break;
    wT := MidStr(fConvertedText, I - 1, 1);
    if BaseLineRightCharacter(wT) then
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_L_2H_3)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_L_2H_1);
  until I <= 0;

  { A_Nn_2H_1 }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Nn, A_Nn_2H_1);
  { A_Nn_2H_2 }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_n, A_Nn_2H_2);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.FirstHalfForms;
var
  I: Integer;
begin
  { A_M_1H }
  fConvertedText := ReplaceStr(fConvertedText, b_m + b_Hasanta, A_M_1H + b_Hasanta);
  { A_Ss_1H }
  fConvertedText := ReplaceStr(fConvertedText, b_ss + b_Hasanta, A_Ss_1H + b_Hasanta);
  { A_C_1H }
  fConvertedText := ReplaceStr(fConvertedText, b_C + b_Hasanta, A_C_1H + b_Hasanta);
  { A_NGA_1H }
  fConvertedText := ReplaceStr(fConvertedText, b_NGA + b_Hasanta, A_NGA_1H + b_Hasanta);
  { A_S_1H_1 }
  fConvertedText := ReplaceStr(fConvertedText, b_s + b_Hasanta, A_S_1H_1 + b_Hasanta);

  { A_D_1H_1  and  A_D_1H_2 }
  repeat
    I := Pos(b_d + b_Hasanta, fConvertedText);
    if I <= 0 then
      break;
    if MidStr(fConvertedText, I + 2, 1) = b_g then
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_D_1H_1)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_D_1H_2);
  until I <= 0;

  { Elevate first-half N-forms }
  repeat
    I := Pos(b_n + b_Hasanta, fConvertedText);
    if I <= 0 then
      break;
    if ((I + 2 <= Length(fConvertedText)) and 
        ((fConvertedText[I + 2] = b_t) or (fConvertedText[I + 2] = b_Th) or 
         (fConvertedText[I + 2] = b_L) or (fConvertedText[I + 2] = b_b) or 
         (MidStr(fConvertedText, I + 2, 1) = A_T_R_2H) or (MidStr(fConvertedText, I + 2, 1) = A_T_UKar_2H))) then
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_N_1H_1)
    else if (I + 2 <= Length(fConvertedText)) and 
            ((fConvertedText[I + 2] = b_m) or (fConvertedText[I + 2] = b_n)) then
      fConvertedText[I] := A_N[1]
    else
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_N_1H_2);
  until I <= 0;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.Consonants;
begin
  fConvertedText := ReplaceStr(fConvertedText, b_K, A_K);
  fConvertedText := ReplaceStr(fConvertedText, b_kh, A_Kh);
  fConvertedText := ReplaceStr(fConvertedText, b_g, A_G);
  fConvertedText := ReplaceStr(fConvertedText, b_gh, A_Gh);
  fConvertedText := ReplaceStr(fConvertedText, b_NGA, A_NGA);
  fConvertedText := ReplaceStr(fConvertedText, b_C, A_C);
  fConvertedText := ReplaceStr(fConvertedText, b_ch, A_Ch);
  fConvertedText := ReplaceStr(fConvertedText, b_j, A_J);
  fConvertedText := ReplaceStr(fConvertedText, b_jh, A_Jh);
  fConvertedText := ReplaceStr(fConvertedText, b_nya, A_NYA);
  fConvertedText := ReplaceStr(fConvertedText, b_tt, A_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_tth, A_Tth);
  fConvertedText := ReplaceStr(fConvertedText, b_dd, A_Dd);
  fConvertedText := ReplaceStr(fConvertedText, b_ddh, A_Ddh);
  fConvertedText := ReplaceStr(fConvertedText, b_Nn, A_Nn);
  fConvertedText := ReplaceStr(fConvertedText, b_t, A_T);
  fConvertedText := ReplaceStr(fConvertedText, b_Th, A_Th);
  fConvertedText := ReplaceStr(fConvertedText, b_d, A_D);
  fConvertedText := ReplaceStr(fConvertedText, b_dh, A_Dh);
  fConvertedText := ReplaceStr(fConvertedText, b_n, A_N);
  fConvertedText := ReplaceStr(fConvertedText, b_p, A_P);
  fConvertedText := ReplaceStr(fConvertedText, b_ph, A_Ph);
  fConvertedText := ReplaceStr(fConvertedText, b_b, A_B);
  fConvertedText := ReplaceStr(fConvertedText, b_Bh, A_Bh);
  fConvertedText := ReplaceStr(fConvertedText, b_m, A_M);
  fConvertedText := ReplaceStr(fConvertedText, b_z, A_Z);
  fConvertedText := ReplaceStr(fConvertedText, b_r, A_R);
  fConvertedText := ReplaceStr(fConvertedText, b_L, A_L);
  fConvertedText := ReplaceStr(fConvertedText, b_sh, A_Sh);
  fConvertedText := ReplaceStr(fConvertedText, b_ss, A_SS);
  fConvertedText := ReplaceStr(fConvertedText, b_s, A_S);
  fConvertedText := ReplaceStr(fConvertedText, b_h, A_H);
  fConvertedText := ReplaceStr(fConvertedText, b_y, A_Y);
  fConvertedText := ReplaceStr(fConvertedText, b_rr, A_RR);
  fConvertedText := ReplaceStr(fConvertedText, b_rrh, A_RRH);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.FinalTouch;
var
  Len: Integer;
  I: Integer;
  CleanedText: string;
  C: Char;
begin
  fConvertedText := ReplaceStr(fConvertedText, string(b_Hasanta) + string(zwnj), string(A_Hasanta));
  
  Len := Length(fConvertedText);
  if Len > 0 then
  begin
    if string(b_Hasanta) <> '' then
    begin
      if (Len >= 2) and (fConvertedText[Len] = string(b_Hasanta)[1])
         and (fConvertedText[Len - 1] = string(b_Hasanta)[1]) then
      begin
        fConvertedText[Len] := A_Hasanta[1];
        fConvertedText[Len - 1] := A_Hasanta[1];
      end
      else if fConvertedText[Len] = string(b_Hasanta)[1] then
        fConvertedText[Len] := A_Hasanta[1];
    end;
  end;
  
  fConvertedText := ReplaceStr(fConvertedText, string(b_Hasanta), '');
  fConvertedText := ReplaceStr(fConvertedText, string(zwj), '');
  fConvertedText := ReplaceStr(fConvertedText, string(zwnj), '');
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_Reph), string(A_Reph) + string(A_ZFola));

  // Swap Z-Fola (A_ZFola) and all types of U-Kar
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UKar1), string(A_UKar1) + string(A_ZFola));
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UKar2), string(A_UKar2) + string(A_ZFola));
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UKar3), string(A_UKar3) + string(A_ZFola));
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UKar4), string(A_UKar4) + string(A_ZFola));

  // Swap Z-Fola (A_ZFola) and all types of UU-Kar
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UUKar1), string(A_UUKar1) + string(A_ZFola));
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UUKar2), string(A_UUKar2) + string(A_ZFola));
  fConvertedText := ReplaceStr(fConvertedText, string(A_ZFola) + string(A_UUKar3), string(A_UUKar3) + string(A_ZFola));
  
  // Swap Z-Fola (A_ZFola) and all types of Rfola
  fConvertedText := ReplaceStr(fConvertedText, string(A_RFola_1) + string(A_UKar1), string(A_UKar1) + string(A_RFola_1));
  fConvertedText := ReplaceStr(fConvertedText, string(A_RFola_1) + string(A_UUKar1), string(A_UUKar1) + string(A_RFola_1));
  fConvertedText := ReplaceStr(fConvertedText, string(A_RFola_2) + string(A_UKar1), string(A_UKar1) + string(A_RFola_2));
  fConvertedText := ReplaceStr(fConvertedText, string(A_RFola_2) + string(A_UUKar1), string(A_UUKar1) + string(A_RFola_2));

  // Reorder Reph and all variants of U-Kar glyphs
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UKar1), string(A_UKar1) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UKar2), string(A_UKar2) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UKar3), string(A_UKar3) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UKar4), string(A_UKar4) + string(A_Reph));
  // This makes the U-kar "hang" lower so it doesn't clash with the Reph.
  fConvertedText := ReplaceStr(fConvertedText, string(A_UKar1) + string(A_Reph), string(A_UKar2) + string(A_Reph));

  // Reorder Reph and all variants of UU-Kar glyphs
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar1), string(A_UUKar1) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar2), string(A_UUKar2) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar3), string(A_UUKar3) + string(A_Reph));
  // If UU-Kar1 and Reph are together, you might want to use UU-Kar2
  fConvertedText := ReplaceStr(fConvertedText, string(A_UUKar1) + string(A_Reph), string(A_UUKar2) + string(A_Reph));

  { =========================================================================
    লিগ্যাসি পোস্ট-প্রসেসিং কারেকশন (শুধু Default ভার্সনের জন্য)
    ========================================================================= }
  if AnsiVersion = 'Default' then
  begin
    fConvertedText := ReplaceStr(fConvertedText, string(A_T) + string(A_UKar1), string(A_T) + string(A_UKar2));
    fConvertedText := ReplaceStr(fConvertedText, string(A_T) + string(A_UUKar1), string(A_T) + string(A_UUKar2));
    fConvertedText := ReplaceStr(fConvertedText, string(A_RR) + string(A_UUKar1), string(A_RR) + string(A_UUKar2));
    fConvertedText := ReplaceStr(fConvertedText, string(A_RRH) + string(A_UUKar1), string(A_RRH) + string(A_UUKar2));
    fConvertedText := ReplaceStr(fConvertedText, string(A_R) + string(A_UUKar1), string(A_R) + string(A_UUKar2));
  end;
  { ========================================================================= }
  
  // --- STRICT SANITIZATION FOR ANSI OUTPUT ---
  CleanedText := '';
  for I := 1 to Length(fConvertedText) do
  begin
    C := fConvertedText[I];
    if (Ord(C) >= $0980) and (Ord(C) <= $09FF) then Continue;
    if ((Ord(C) >= $200B) and (Ord(C) <= $200F)) or (Ord(C) = $FEFF) then Continue;
    CleanedText := CleanedText + C;
  end;
  fConvertedText := CleanedText;

  // Applying dynamic post-processing fixes (LAST)
  for I := 0 to Length(CustomPostReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPostReplacements[I].Key, CustomPostReplacements[I].Value);
end;

procedure TUnicodeToBijoy2000.ReplaceFullForms;
var
  I, J, BestLen: Integer;
  BestMatch: string;
  SourceText: string;
  Map: TDictionary<string, string>;
begin
  Map := TDictionary<string, string>.Create;
  try
    for I := 0 to Length(ActiveReplacements) - 1 do
      Map.AddOrSetValue(ActiveReplacements[I].Key, ActiveReplacements[I].Value);

    SourceText := fConvertedText;
    fConvertedText := '';
    J := 1;
    while J <= Length(SourceText) do
    begin
      BestLen := 0;
      BestMatch := '';
      for I := 0 to Length(ActiveReplacements) - 1 do
      begin
        if (Length(ActiveReplacements[I].Key) > BestLen) and
           (Copy(SourceText, J, Length(ActiveReplacements[I].Key)) = ActiveReplacements[I].Key) then
        begin
          BestLen := Length(ActiveReplacements[I].Key);
          BestMatch := ActiveReplacements[I].Key;
        end;
      end;
      if BestLen > 0 then
      begin
        fConvertedText := fConvertedText + Map[BestMatch];
        J := J + BestLen;
      end
      else
      begin
        fConvertedText := fConvertedText + SourceText[J];
        Inc(J);
      end;
    end;
  finally
    Map.Free;
  end;
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.BaseLineRightCharacter(const wC: string): Boolean;
var
  GroupList: TList<string>;
begin
  Result := False;
  if ConsonantGroupsMap <> nil then
    if ConsonantGroupsMap.TryGetValue('BaseLineRight', GroupList) then
      Result := GroupList.Contains(wC);
end;

function TUnicodeToBijoy2000.GetVowelGlyph(const AVowel, AConsonant: string; UseAlt: Boolean): string;
var
  Rule: TVowelRule;
  Map: TVowelMapping;
  GroupList: TList<string>;
  IsMatched: Boolean;
begin
  Result := '';
  if VowelRulesList = nil then
  begin
    if AVowel = b_Ukar then Exit(A_UKar1);
    if AVowel = b_UUKar then Exit(A_UUKar1);
    if AVowel = b_Rrikar then Exit(A_RRIKar2);
    Exit;
  end;
  for Rule in VowelRulesList do
  begin
    if Rule.Vowel = AVowel then
    begin
      for Map in Rule.Mappings do
      begin
        IsMatched := False;

        if (ConsonantGroupsMap <> nil) and ConsonantGroupsMap.TryGetValue(Map.Consonants, GroupList) then
          IsMatched := GroupList.Contains(AConsonant)
        else
          IsMatched := (AConsonant <> '') and (Pos(AConsonant, Map.Consonants) > 0);

        if IsMatched then
        begin
          if UseAlt and (Map.AltValue <> '') then
            Exit(Map.AltValue)
          else
            Exit(Map.Value);
        end;
      end;
      Exit(Rule.DefaultVal);
    end;
  end;
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.IsVowel(C: Char): Boolean;
begin
  Result := (C = b_A) or (C = b_AA) or (C = b_I) or (C = b_II) or 
            (C = b_U) or (C = b_UU) or (C = b_RRI) or (C = b_E) or 
            (C = b_OI) or (C = b_O) or (C = b_OU);
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.Convert(const UniText: string): string;
var
  I: Integer;
  HasTrailingHasanta: Boolean;
begin
  if UniText = '' then
  begin
    fRaUKarToggle := False;
    fRaUUKarToggle := False;
    fLastUniText := '';
    Result := '';
    exit;
  end;

  if (Pos(' ', UniText) > 0) then
  begin
    fRaUKarToggle := False;
    fRaUUKarToggle := False;
  end;

  fUniText := UniText;
  fConvertedText := fUniText;

  if (fLastUniText = b_r + b_Ukar) and (UniText = b_r) then
    fRaUKarToggle := True;

  if (fLastUniText = b_r + b_UUKar) and (UniText = b_r) then
    fRaUUKarToggle := True;

  fLastUniText := UniText;
  
  // Clean start
  DeNormalize;
  
  // 1. Apply dynamic pre-placement fixes
  for I := 0 to Length(CustomPreReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPreReplacements[I].Key, CustomPreReplacements[I].Value);

  // 2. Rearrange Vowels and Reph
  ReArrangeKars;
  ReArrangeReph;

  // 3. Process Conjuncts and Full Forms FIRST
  ReplaceFullForms;

  // 4. Process Vowels LATER
  ReplaceKarsVowels;

  // 5. Apply Glyphs, Halfs, and Consonants
  ConvertRFola_ZFola_Hasanta;
  
  { ==========================================================
    (Flicker-Free Half Form Protection)
    ========================================================== }
  HasTrailingHasanta := False;
  if (Length(fConvertedText) > 0) and 
     (fConvertedText[Length(fConvertedText)] = b_Hasanta) then
  begin
    HasTrailingHasanta := True;
    Delete(fConvertedText, Length(fConvertedText), 1);
  end;
  { =========================================================== }
  FirstHalfForms;
  { =========================================================== }
  if HasTrailingHasanta then
  begin
    fConvertedText := fConvertedText + b_Hasanta;
  end;
  { =========================================================== }
  SecondHalfForms;
  Consonants;
  FinalTouch;
  
  Result := fConvertedText;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ConvertRFola_ZFola_Hasanta;
var
  I: Integer;
  PrevC: string;
begin
  // Convert Z-Fola
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_z, A_ZFola);
  // Convert Hasanta
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + zwnj, A_Hasanta);
  // Convert R-Fola
  repeat
    I := Pos(b_Hasanta + b_r, fConvertedText);
    if I <= 0 then
      break;

    PrevC := MidStr(fConvertedText, I - 1, 1);

    { P/G + RoFola }
    if (PrevC = b_p) or (PrevC = b_g) or (PrevC = b_sh) then
    // MidStr(fConvertedText, I, 2) := A_RFola_3
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_3)
      { V+Rofola, 2nd Half V+Rofola }
    else if PrevC = b_Bh then
    begin
      if MidStr(fConvertedText, I - 2, 1) = b_Hasanta then
        // MidStr(fConvertedText, I - 1, 3) := A_BH_R_2H
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_BH_R_2H)
      else
        // MidStr(fConvertedText, I - 1, 3) := A_Bh_R;
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_Bh_R);
    end
    { K+Rofola, 2nd Half K+Rofola }
    else if PrevC = b_K then
    begin
      if MidStr(fConvertedText, I - 2, 1) = b_Hasanta then
        // MidStr(fConvertedText, I - 1, 3) := A_K_R_2H
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_K_R_2H)
      else
        // MidStr(fConvertedText, I - 1, 3) := A_K_R;
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_K_R);
    end
    { T+Rofola, 2nd Half T+Rofola }
    else if PrevC = b_t then
    begin
      if MidStr(fConvertedText, I - 2, 1) = b_Hasanta then
      begin
      // MidStr(fConvertedText, I - 1, 3) := A_T_R_2H
        if (MidStr(fConvertedText, I - 3, 1) = b_K) or (MidStr(fConvertedText, I - 3, 1) = b_t) then
          fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_2)
        else
          fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_T_R_2H);
      end
      else
        // MidStr(fConvertedText, I - 1, 3) := A_T_R;
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_T_R);
    end
    else if (PrevC = A_K_T) or (PrevC = A_T_T) or (PrevC = A_P_T) then
    begin
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_2);
    end
    else
    begin
      if PrevC = b_ph then
        // MidStr(fConvertedText, I, 2) := A_RFola_2
        fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_2)
      else
        // MidStr(fConvertedText, I, 2) := A_RFola_1;
        fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_1);
    end;

  until I <= 0;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.DeNormalize;
begin
  fConvertedText := ReplaceStr(fUniText, b_z + b_Nukta, b_y);
  fConvertedText := ReplaceStr(fConvertedText, b_dd + b_Nukta, b_rr);
  fConvertedText := ReplaceStr(fConvertedText, b_ddh + b_Nukta, b_rrh);
  while Pos(b_Hasanta + b_Hasanta + b_Hasanta, fConvertedText) > 0 do
    fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Hasanta + b_Hasanta, b_Hasanta + b_Hasanta);
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_z + b_Hasanta + b_r, b_Hasanta + b_r + b_Hasanta + b_z);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReArrangeKars;
var
  I:           Integer;
  fKar, wCTmp: Char;
  wSTmp:       string;

  function MoveAbleKar(const wKar: Char): Boolean;
  begin
    Result := (wKar = b_Ekar) or (wKar = b_IKar) or (wKar = b_OIKar);
  end;

begin
  // Break O-kar and OU-Kar
  fConvertedText := ReplaceStr(fConvertedText, b_OKar, b_Ekar + b_AAKar);
  fConvertedText := ReplaceStr(fConvertedText, b_OUKar, b_Ekar + b_LengthMark);

  // Bring IKar,EKar and OIkar to beginning of consonant/conjuncts
  I := Length(fConvertedText);
  wSTmp := '';
  fKar := #0;
  
  repeat
    if I < 1 then break;
    wCTmp := fConvertedText[I];
    
    if MoveAbleKar(wCTmp) then
    begin
      if fKar <> #0 then wSTmp := fKar + wSTmp;
      fKar := wCTmp;
    end
    else
    begin
      if fKar = #0 then
      begin // No Kar is pending
        wSTmp := wCTmp + wSTmp;
      end
      else
      begin
        if (IsPureConsonent(wCTmp) = False) and (wCTmp <> b_Hasanta) and (wCTmp <> zwj) and (wCTmp <> zwnj) then
        begin
          if fKar <> #0 then
          begin
            wSTmp := wCTmp + fKar + wSTmp;
            fKar := #0;
          end
          else
            wSTmp := wCTmp + wSTmp;
        end
        else
        begin
          if (wCTmp = b_Hasanta) or (wCTmp = zwj) or (wCTmp = zwnj) then
          begin
            wSTmp := wCTmp + wSTmp;
          end
          else if IsPureConsonent(wCTmp) then
          begin
            if (I > 1) and ((fConvertedText[I - 1] = b_Hasanta) or (fConvertedText[I - 1] = zwj) or (fConvertedText[I - 1] = zwnj)) then
              wSTmp := wCTmp + wSTmp
            else
            begin
              if fKar <> #0 then
              begin
                wSTmp := fKar + wCTmp + wSTmp;
                // Place pending kar at begining
                fKar := #0;
              end
              else
                wSTmp := wCTmp + wSTmp;
            end;
          end;
        end;
      end;
    end;
    I := I - 1;
  until I < 1;

  if fKar <> #0 then wSTmp := fKar + wSTmp;

  fConvertedText := wSTmp;
  fConvertedText := ReplaceStr(fConvertedText, string(b_StartSingleQuote), A_StartSingleQuote);
  fConvertedText := ReplaceStr(fConvertedText, string(b_EndSingleQuote), A_EndSingleQuote);
  fConvertedText := ReplaceStr(fConvertedText, string(b_StartDoubleQuote), A_StartDoubleQuote);
  fConvertedText := ReplaceStr(fConvertedText, string(b_EndDoubleQuote), A_EndDoubleQuote);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReArrangeReph;
var
  I: Integer;
  wCTmp: Char;
  wSTmp: string;
  RephPending: Boolean;

  function MoveAbleReph: Boolean;
  begin
    Result := False;
    if I + 1 >= Length(fConvertedText) then exit;
    
// To avoid reph: if the character right before 'ra' is a hasanta (b_Hasanta)
// then it is not a reph, but rather a ra-phala of the previous letter (e.g., mrya, krya)
    if (I > 1) and (fConvertedText[I - 1] = b_Hasanta) then
      Exit;

    if (fConvertedText[I] = b_r) and (fConvertedText[I + 1] = b_Hasanta) then
    begin
      if (I + 2 <= Length(fConvertedText)) and 
         ((fConvertedText[I + 2] = ' ') or (fConvertedText[I + 2] = #13)) then
        Result := False
      else
        Result := True;
    end;
  end;

begin
  if Length(fConvertedText) < 3 then exit;
  I := 1;
  wSTmp := '';
  RephPending := False;

  while I <= Length(fConvertedText) do
  begin
    wCTmp := fConvertedText[I];

    if MoveAbleReph then
    begin
       RephPending := True;
       I := I + 2;
       continue;
    end;

    wSTmp := wSTmp + wCTmp;

    if RephPending then
    begin
      if IsVowel(wCTmp) then 
      begin
        // Keep moving
      end
      else if (I + 1 <= Length(fConvertedText)) and (fConvertedText[I+1] = b_Hasanta) then
      begin
      end
      else if (wCTmp <> b_Hasanta) and (wCTmp <> zwj) and (wCTmp <> zwnj) then
      begin
        wSTmp := wSTmp + A_Reph;
        RephPending := False;
      end;
    end;
    Inc(I);
  end;
  
  if RephPending then wSTmp := wSTmp + A_Reph;
  fConvertedText := wSTmp;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReplaceKarsVowels;
var
  I: Integer;
  PrecedingChar, VowelGlyph: string;
  IsZfola: Boolean;
begin
  // Convert Ekar
  repeat
    I := Pos(b_Ekar, fConvertedText);
    if I <= 0 then
      break;
      if ((I = 1) or (MidStr(fConvertedText, I - 1, 1) = ' ') or (MidStr(fConvertedText, I - 1, 1) = #13) or (MidStr(fConvertedText, I - 1, 1) = #10) or
        (MidStr(fConvertedText, I - 1, 1) = #9)) then
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_EKar1)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_EKar2);
  until I <= 0;

  // Convert OIKar
  repeat
    I := Pos(b_OIKar, fConvertedText);
    if I <= 0 then
      break;
    if ((I = 1) or (MidStr(fConvertedText, I - 1, 1) = ' ') or (MidStr(fConvertedText, I - 1, 1) = #13) or (MidStr(fConvertedText, I - 1, 1) = #10) or
        (MidStr(fConvertedText, I - 1, 1) = #9)) then
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_OIKar1)
    else
      fConvertedText := WideStuffString(fConvertedText, I, 1, A_OIKar2);
  until I <= 0;

// Convert UKar (ু)
  fConvertedText := ReplaceStr(fConvertedText, b_g + b_Ukar, A_G_Ukar);
  fConvertedText := ReplaceStr(fConvertedText, b_sh + b_Ukar, A_Sh_UKar);
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Ukar, A_H_UKar);
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_t + b_Ukar, b_Hasanta + A_T_UKar_2H);
  repeat
    I := Pos(b_Ukar, fConvertedText);
    if I <= 0 then break;
    VowelGlyph := '';
    if I - 1 >= 1 then
    begin
      PrecedingChar := fConvertedText[I - 1];
      IsZfola := (PrecedingChar = b_z) and (I - 2 >= 1) and (fConvertedText[I - 2] = b_Hasanta);
      if IsZfola then
      begin
        if I - 3 >= 1 then PrecedingChar := fConvertedText[I - 3] else PrecedingChar := '';
      end;
      VowelGlyph := GetVowelGlyph(b_Ukar, PrecedingChar, fRaUKarToggle);
    end;
    if VowelGlyph = '' then
      VowelGlyph := GetVowelGlyph(b_Ukar, '', False);
    fConvertedText := WideStuffString(fConvertedText, I, 1, VowelGlyph);
  until I <= 0;

  // Convert UUKar (ূ)
  repeat
    I := Pos(b_UUKar, fConvertedText);
    if I <= 0 then break;
    VowelGlyph := '';
    if I - 1 >= 1 then
    begin
      PrecedingChar := fConvertedText[I - 1];
      IsZfola := (PrecedingChar = b_z) and (I - 2 >= 1) and (fConvertedText[I - 2] = b_Hasanta);
      if IsZfola then
      begin
        if I - 3 >= 1 then PrecedingChar := fConvertedText[I - 3] else PrecedingChar := '';
      end;
      VowelGlyph := GetVowelGlyph(b_UUKar, PrecedingChar, fRaUUKarToggle);
    end;
    if VowelGlyph = '' then
      VowelGlyph := GetVowelGlyph(b_UUKar, '', False);
    fConvertedText := WideStuffString(fConvertedText, I, 1, VowelGlyph);
  until I <= 0;

  // Convert RRIKar (ৃ)
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Rrikar, A_H_RRIKar);
  repeat
    I := Pos(b_Rrikar, fConvertedText);
    if I <= 0 then break;
    VowelGlyph := '';
    if I - 1 >= 1 then
      VowelGlyph := GetVowelGlyph(b_Rrikar, fConvertedText[I - 1], False);
    if VowelGlyph = '' then
      VowelGlyph := GetVowelGlyph(b_Rrikar, '', False);
    fConvertedText := WideStuffString(fConvertedText, I, 1, VowelGlyph);
  until I <= 0;

  // Convert rest of the Kars
  fConvertedText := ReplaceStr(fConvertedText, b_AAKar, A_AAKar);
  fConvertedText := ReplaceStr(fConvertedText, b_IKar, A_IKar);
  fConvertedText := ReplaceStr(fConvertedText, b_IIKar, A_IIKar);
  fConvertedText := ReplaceStr(fConvertedText, b_LengthMark, A_OUKar);

  // Convert Vowels
  fConvertedText := ReplaceStr(fConvertedText, b_A, A_A);
  fConvertedText := ReplaceStr(fConvertedText, b_AA, A_AA);
  fConvertedText := ReplaceStr(fConvertedText, b_I, A_I);
  fConvertedText := ReplaceStr(fConvertedText, b_II, A_II);
  fConvertedText := ReplaceStr(fConvertedText, b_U, A_U);
  fConvertedText := ReplaceStr(fConvertedText, b_UU, A_UU);
  fConvertedText := ReplaceStr(fConvertedText, b_RRI, A_RRI);
  fConvertedText := ReplaceStr(fConvertedText, b_E, A_E);
  fConvertedText := ReplaceStr(fConvertedText, b_OI, A_OI);
  fConvertedText := ReplaceStr(fConvertedText, b_O, A_O);
  fConvertedText := ReplaceStr(fConvertedText, b_OU, A_OU);
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.WideStuffString(Source: string; Start, Len: Integer; SubString: string): string;
var
  FirstPart, LastPart: string;
begin
  FirstPart := LeftStr(Source, Start - 1);
  LastPart := MidStr(Source, Start + Len, Length(Source));
  Result := FirstPart + SubString + LastPart;
end;

{ =============================================================================== }

function EscapeJSON(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
  begin
    case C of
      '\': Result := Result + '\\';
      '"': Result := Result + '\"';
      '/': Result := Result + '\/';
      #$08: Result := Result + '\b';
      #$09: Result := Result + '\t';
      #$0A: Result := Result + '\n';
      #$0C: Result := Result + '\f';
      #$0D: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

{ =============================================================================== }

function ProcessHexAndUnicode(const S: string): string;
var
  SB: TStringBuilder;
  I, Code: Integer;
begin
  SB := TStringBuilder.Create;
  try
    I := 1;
    while I <= Length(S) do
    begin
      if (I < Length(S)) and (S[I] = '#') and (S[I + 1] = '$') then
      begin
        Code := 0;
        I := I + 2;
        while (I <= Length(S)) and (CharInSet(S[I], ['0'..'9', 'A'..'F', 'a'..'f'])) do
        begin
          Code := Code * 16;
          if CharInSet(S[I], ['0'..'9']) then
            Code := Code + Ord(S[I]) - Ord('0')
          else if CharInSet(S[I], ['A'..'F']) then
            Code := Code + Ord(S[I]) - Ord('A') + 10
          else
            Code := Code + Ord(S[I]) - Ord('a') + 10;
          Inc(I);
        end;
        SB.Append(Char(Code));
      end
      else
      begin
        SB.Append(S[I]);
        Inc(I);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ =============================================================================== }

procedure EnsureAnsiRegistry;
begin
  if AnsiRegistry = nil then
  begin
    AnsiRegistry := TList<TAnsiVarRec>.Create;
    AnsiRegistryMap := TDictionary<string, TAnsiVarRec>.Create;
    InitializeAnsiRegistry;
  end;
end;

function ExpandVarRefs(const S: string): string;
var
  I, J: Integer;
  VarName, VarVal: string;
  Rec: TAnsiVarRec;
begin
  Result := S;
  I := Pos('#{', Result);
  while I > 0 do
  begin
    J := PosEx('}', Result, I + 2);
    if J > 0 then
    begin
      VarName := Copy(Result, I + 2, J - I - 2);
      EnsureAnsiRegistry;
      if AnsiRegistryMap.TryGetValue(VarName, Rec) then
      begin
        if Rec.VarType = avChar then
          VarVal := string(PChar(Rec.Ptr)^)
        else
          VarVal := PString(Rec.Ptr)^;
      end
      else
        VarVal := ''; // Skip unrecognized variables

      Result := Copy(Result, 1, I - 1) + VarVal + Copy(Result, J + 1, MaxInt);
      I := Pos('#{', Result);
    end
    else
      Break;
  end;
end;

function ResolveStringValue(const S: string): string;
begin
  Result := ProcessHexAndUnicode(ExpandVarRefs(S));
end;

{ =============================================================================== }

function ValidateHexFormat(const S: string): Boolean;
var
  I: Integer;
begin
  Result := True;
  I := 1;
  while I <= Length(S) do
  begin
    if (I < Length(S)) and (S[I] = '#') and (S[I+1] = '$') then
    begin
      if (I + 2 > Length(S)) or not (CharInSet(S[I+2], ['0'..'9', 'A'..'F', 'a'..'f'])) then
      begin
        Result := False;
        Exit;
      end;
    end;
    Inc(I);
  end;
end;

{ =============================================================================== }

function SmartEscape(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    Result := Result + '#$' + IntToHex(Ord(C), 4);
end;

function JSONEscape(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + '\u' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
end;

{ =============================================================================== }

function CleanBengaliChar(const S: string): string;
var
  SpaceIdx, ParenIdx, DashIdx: Integer;
begin
  Result := S;
  SpaceIdx := Pos(' ', Result);
  if SpaceIdx > 0 then
    Result := Copy(Result, 1, SpaceIdx - 1);
  ParenIdx := Pos('(', Result);
  if ParenIdx > 0 then
    Result := Copy(Result, 1, ParenIdx - 1);
  DashIdx := Pos('-', Result);
  if DashIdx > 0 then
    Result := Copy(Result, 1, DashIdx - 1);
  Result := Trim(Result);
end;

{ =============================================================================== }
// Lightweight JSON utilities (replaces System.JSON to reduce ~1MB RTL)
procedure JSkipWS(const S: string; var P: Integer);
begin
  while (P <= Length(S)) and (S[P] <= ' ') do Inc(P);
end;

function JReadString(const S: string; var P: Integer): string;
var
  SB: TStringBuilder;
begin
  Result := '';
  JSkipWS(S, P);
  if (P > Length(S)) or (S[P] <> '"') then Exit;
  Inc(P);
  SB := TStringBuilder.Create;
  try
    while P <= Length(S) do
    begin
      if S[P] = '"' then begin Inc(P); Result := SB.ToString; Exit; end;
      if S[P] = '\' then
      begin
        Inc(P);
        if P > Length(S) then Exit;
        case S[P] of
          '"': SB.Append('"');
          '\': SB.Append('\');
          '/': SB.Append('/');
          'n': SB.Append(#10);
          'r': SB.Append(#13);
          't': SB.Append(#9);
          'u': begin
                 if P + 4 <= Length(S) then
                   SB.Append(Char(StrToIntDef('$' + Copy(S, P+1, 4), Ord('?'))))
                 else SB.Append('?');
                 Inc(P, 4);
               end;
        else SB.Append(S[P]);
        end;
        Inc(P);
      end
      else
      begin
        SB.Append(S[P]);
        Inc(P);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure JSkipValue(const S: string; var P: Integer);
var
  Depth: Integer;
begin
  JSkipWS(S, P);
  if P > Length(S) then Exit;
  case S[P] of
    '{','[': begin
               Depth := 1; Inc(P);
               while (P <= Length(S)) and (Depth > 0) do
               begin
                 if S[P] = '"' then
                begin
                    Inc(P);
                    while P <= Length(S) do
                      if S[P] = '\' then
                      begin
                        Inc(P);
                        if P <= Length(S) then Inc(P);
                      end
                      else if S[P] = '"' then begin Inc(P); Break; end
                      else Inc(P);
                  end
                  else if CharInSet(S[P], ['{', '[']) then Inc(Depth)
                  else if CharInSet(S[P], ['}', ']']) then Dec(Depth);
                 if Depth > 0 then Inc(P);
               end;
               if P <= Length(S) then Inc(P);
             end;
    '"': JReadString(S, P);
    else Inc(P);
  end;
end;

{ =============================================================================== }

function JSONPrettyPrint(const JSON: string): string;
var
  SB: TStringBuilder;
  P, Depth: Integer;
  C: Char;
begin
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    P := 1;
    while P <= Length(JSON) do
    begin
      C := JSON[P];
      case C of
        '{', '[':
          begin
            SB.Append(C);
            Inc(Depth);
            SB.Append(sLineBreak);
            SB.Append(StringOfChar(' ', Depth * 2));
            Inc(P);
          end;
        '}', ']':
          begin
            SB.Append(sLineBreak);
            Dec(Depth);
            SB.Append(StringOfChar(' ', Depth * 2));
            SB.Append(C);
            Inc(P);
          end;
        ',':
          begin
            SB.Append(',');
            SB.Append(sLineBreak);
            SB.Append(StringOfChar(' ', Depth * 2));
            Inc(P);
          end;
        ':':
          begin
            SB.Append(': ');
            Inc(P);
          end;
        '"':
          begin
            SB.Append('"');
            Inc(P);
            while P <= Length(JSON) do
            begin
              C := JSON[P];
              SB.Append(C);
              Inc(P);
              if C = '\' then
              begin
                if P <= Length(JSON) then
                begin
                  SB.Append(JSON[P]);
                  Inc(P);
                end;
              end
              else if C = '"' then
                Break;
            end;
          end;
      else
        if C > ' ' then
          SB.Append(C);
        Inc(P);
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure EnsureAnsiOverrides;
begin
  if AnsiOverrides = nil then
    AnsiOverrides := TDictionary<string, string>.Create;
end;

{ =============================================================================== }

procedure PrepareActiveReplacements;
var
  I: Integer;
  UniqueMap: TDictionary<string, string>;
  Rec: TAnsiVarRec;
  Key: string;
  Val: string;
  ExcludedNames: TDictionary<string, Boolean>;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  ExcludedNames := TDictionary<string, Boolean>.Create;
  UniqueMap := TDictionary<string, string>.Create;
  try
    // 1. Load default mappings from AnsiRegistry
    for Rec in AnsiRegistry do
    begin
      if Rec.BengaliChar = '' then
        Continue;

      if Rec.Category = 'Numbers' then
      begin
        // All numbers are included
      end
      else if Rec.Category = 'Symbols' then
      begin
        if (Rec.Name <> 'A_Taka') and (Rec.Name <> 'A_Dari') and (Rec.Name <> 'A_DoubleDanda') then
          Continue;
      end
      else if Rec.Category = 'Consonants' then
      begin
        if (Rec.Name <> 'A_Khandata') and (Rec.Name <> 'A_Anushar') and
           (Rec.Name <> 'A_Bisharga') and (Rec.Name <> 'A_Chandra') then
          Continue;
      end
      else if Rec.Category = 'FullForms' then
      begin
        if ExcludedNames.ContainsKey(Rec.Name) then
          Continue;
      end
      else
        Continue;

      Key := CleanBengaliChar(Rec.BengaliChar);
      if Key = '' then
        Continue;

      if not AnsiOverrides.TryGetValue(Rec.Name, Val) then
        Val := PString(Rec.Ptr)^;

      if Val = '' then
        Continue;

      UniqueMap.AddOrSetValue(Key, Val);
    end;

    // 2. Merge custom full-form overrides (same Key overwrites default value)
    for I := 0 to Length(CustomFullForms) - 1 do
      UniqueMap.AddOrSetValue(CustomFullForms[I].Key, CustomFullForms[I].Value);

    // 3. Populate ActiveReplacements from the deduplicated map
    SetLength(ActiveReplacements, UniqueMap.Count);
    I := 0;
    for Key in UniqueMap.Keys do
    begin
      ActiveReplacements[I].Key := Key;
      ActiveReplacements[I].Value := UniqueMap.Items[Key];
      Inc(I);
    end;

    // 4. Sort by key length descending (Longest Match First)
    TArray.Sort<TReplacementPair>(ActiveReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end
    ));
  finally
    UniqueMap.Free;
    ExcludedNames.Free;
  end;
end;

{ =============================================================================== }

procedure InitializeDefaultConsonantGroups;
var
  DefaultList: TList<string>;
  GroupPair: TPair<string, TList<string>>;
begin
  if ConsonantGroupsMap = nil then
    ConsonantGroupsMap := TDictionary<string, TList<string>>.Create
  else
  begin
    for GroupPair in ConsonantGroupsMap do
      GroupPair.Value.Free;
    ConsonantGroupsMap.Clear;
  end;

  DefaultList := TList<string>.Create;
  DefaultList.AddRange([
    b_kh, b_g, b_gh, b_Nn, b_Th, b_d, b_dh, b_n, b_p, b_b,
    b_m, b_z, b_r, b_L, b_sh, b_ss, b_s, b_h, b_y,
    string(A_K_Ss_M), string(A_K_M), string(A_K_Ss), string(A_K_S),
    string(A_G_G), string(A_G_D), string(A_G_Dh), string(A_NGA_G),
    string(A_T_Th), string(A_T_M),
    string(A_D_D), string(A_D_Dh), string(A_D_B), string(A_D_M),
    string(A_N_Tth), string(A_N_Dh), string(A_N_S),
    string(A_P_P), string(A_P_S),
    string(A_B_D), string(A_B_Dh), string(A_Bh_R), string(A_M_N),
    string(A_L_G), string(A_L_P),
    string(A_Ss_Nn), string(A_S_Kh), string(A_S_N),
    string(A_H_N), string(A_H_M), string(A_Rr_G)
  ]);
  ConsonantGroupsMap.Add('BaseLineRight', DefaultList);
end;

{ =============================================================================== }

procedure ResetAnsiToDefaults;
var
  Rec: TAnsiVarRec;
  Resolved: string;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  for Rec in AnsiRegistry do
  begin
    Resolved := ProcessHexAndUnicode(Rec.DefaultVal);
    PString(Rec.Ptr)^ := Resolved;
  end;

  AnsiOverrides.Clear;
  Finalize(CustomFullForms); CustomFullForms := nil;
  Finalize(CustomPreReplacements); CustomPreReplacements := nil;
  Finalize(CustomPostReplacements); CustomPostReplacements := nil;
  Finalize(ActiveReplacements); ActiveReplacements := nil;
  PrepareActiveReplacements;
  InitializeDefaultConsonantGroups;
end;

{ =============================================================================== }

procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);

  function ParseSection(const S: string; var Pos: Integer): TArray<TReplacementPair>;
  var
    Items: TList<TReplacementPair>;
    Pair: TReplacementPair;
    Field: string;
  begin
    Items := TList<TReplacementPair>.Create;
    try
      JSkipWS(S, Pos);
      if (Pos <= Length(S)) and (S[Pos] = '[') then Inc(Pos) else Exit;
      while Pos <= Length(S) do
      begin
        JSkipWS(S, Pos);
        if (Pos > Length(S)) or (S[Pos] = ']') then begin Inc(Pos); Break; end;
        if S[Pos] = ',' then begin Inc(Pos); Continue; end;
        if S[Pos] = '{' then
        begin
          Inc(Pos); Pair.Key := ''; Pair.Value := '';
          while Pos <= Length(S) do
          begin
            JSkipWS(S, Pos);
            if (Pos > Length(S)) or (S[Pos] = '}') then begin Inc(Pos); Break; end;
            if S[Pos] = ',' then begin Inc(Pos); Continue; end;
            Field := JReadString(S, Pos);
            JSkipWS(S, Pos); if S[Pos] = ':' then Inc(Pos);
            if Field = 'Key' then
              Pair.Key := ResolveStringValue(JReadString(S, Pos))
            else if Field = 'Value' then
              Pair.Value := ResolveStringValue(JReadString(S, Pos))
            else
              JSkipValue(S, Pos);
          end;
          if Pair.Key <> '' then
            Items.Add(Pair);
        end
        else
          JSkipValue(S, Pos);
      end;
      Result := Items.ToArray;
    finally
      Items.Free;
    end;
  end;

var
  JSON: string;
  P: Integer;
  Key, ConstName, ConstValue, CatName, FieldName, VowelName, Field, MapField: string;
  Rec: TAnsiVarRec;
  Lines: TStringList;
  ConsonantGroupsFound: Boolean;
  GroupList: TList<string>;
  GroupPair: TPair<string, TList<string>>;
  Rule: TVowelRule;
  Map: TVowelMapping;
begin
  ConsonantGroupsFound := False;
  ResetAnsiToDefaults;

  if not FileExists(Path) then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: JSON file not found at: ' + Path);
    Exit;
  end;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
      JSON := Lines.Text;
      if (Length(JSON) >= 3) and (JSON[1] = #$EF) and (JSON[2] = #$BB) and (JSON[3] = #$BF) then
        Delete(JSON, 1, 3);
    except
      on E: Exception do
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Critical: Invalid JSON Syntax. Message: ' + E.Message);
        Exit;
      end;
    end;
  finally
    Lines.Free;
  end;

  P := 1;
  JSkipWS(JSON, P);
  if (P > Length(JSON)) or (JSON[P] <> '{') then Exit;
  Inc(P);

  while P <= Length(JSON) do
  begin
    JSkipWS(JSON, P);
    if (P > Length(JSON)) or (JSON[P] = '}') then Break;
    if JSON[P] = ',' then begin Inc(P); Continue; end;

    Key := JReadString(JSON, P);
    JSkipWS(JSON, P);
    if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
    JSkipWS(JSON, P);

    if Key = 'Constants' then
    begin
      // Constants: { "Cat": { "Name": { "Value": "...", ... } } }
      if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
        if JSON[P] = ',' then begin Inc(P); Continue; end;
        CatName := JReadString(JSON, P); // skip category name
        JSkipWS(JSON, P); if JSON[P] = ':' then Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;
        while P <= Length(JSON) do
        begin
          JSkipWS(JSON, P);
          if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
          if JSON[P] = ',' then begin Inc(P); Continue; end;
          ConstName := JReadString(JSON, P);
          JSkipWS(JSON, P); if JSON[P] = ':' then Inc(P);
          JSkipWS(JSON, P);
          if (P <= Length(JSON)) and (JSON[P] = '{') then
          begin
            Inc(P); ConstValue := '';
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
              if JSON[P] = ',' then begin Inc(P); Continue; end;
              FieldName := JReadString(JSON, P);
              JSkipWS(JSON, P); if JSON[P] = ':' then Inc(P);
              if FieldName = 'Value' then
                ConstValue := JReadString(JSON, P)
              else
                JSkipValue(JSON, P);
            end;
            if ConstValue <> '' then
            begin
              ConstValue := ResolveStringValue(ConstValue);
              if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
                PString(Rec.Ptr)^ := ConstValue;
            end;
          end
          else JSkipValue(JSON, P);
        end;
      end;
    end
    else if Key = 'FullFormReplacements' then
      CustomFullForms := ParseSection(JSON, P)
    else if Key = 'PreReplacements' then
      CustomPreReplacements := ParseSection(JSON, P)
    else if Key = 'PostReplacements' then
      CustomPostReplacements := ParseSection(JSON, P)
    else if Key = 'VowelRules' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;
      if VowelRulesList = nil then
        VowelRulesList := TList<TVowelRule>.Create;
      VowelRulesList.Clear;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
        if JSON[P] = ',' then begin Inc(P); Continue; end;
        VowelName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;
        Rule.Vowel := ResolveStringValue(VowelName);
        Rule.DefaultVal := '';
        Rule.BaselineRightVal := '';
        SetLength(Rule.Mappings, 0);
        while P <= Length(JSON) do
        begin
          JSkipWS(JSON, P);
          if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
          if JSON[P] = ',' then begin Inc(P); Continue; end;
          Field := JReadString(JSON, P);
          JSkipWS(JSON, P);
          if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
          JSkipWS(JSON, P);
          if Field = 'default' then
            Rule.DefaultVal := ResolveStringValue(JReadString(JSON, P))
          else if Field = 'baselineRight' then
            Rule.BaselineRightVal := ResolveStringValue(JReadString(JSON, P))
          else if Field = 'mappings' then
          begin
            if (P <= Length(JSON)) and (JSON[P] = '[') then Inc(P) else Continue;
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = ']') then begin Inc(P); Break; end;
              if JSON[P] = ',' then begin Inc(P); Continue; end;
              if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;
              Map.Consonants := '';
              Map.Value := '';
              Map.AltValue := '';
              while P <= Length(JSON) do
              begin
                JSkipWS(JSON, P);
                if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
                if JSON[P] = ',' then begin Inc(P); Continue; end;
                MapField := JReadString(JSON, P);
                JSkipWS(JSON, P);
                if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
                JSkipWS(JSON, P);
                if MapField = 'consonants' then
                  Map.Consonants := ResolveStringValue(JReadString(JSON, P))
                else if MapField = 'value' then
                  Map.Value := ResolveStringValue(JReadString(JSON, P))
                else if MapField = 'alt' then
                  Map.AltValue := ResolveStringValue(JReadString(JSON, P))
                else
                  JSkipValue(JSON, P);
              end;
              SetLength(Rule.Mappings, Length(Rule.Mappings) + 1);
              Rule.Mappings[High(Rule.Mappings)] := Map;
            end;
          end
          else
            JSkipValue(JSON, P);
        end;
        VowelRulesList.Add(Rule);
      end;
    end
    else if Key = 'ConsonantGroups' then
    begin
      ConsonantGroupsFound := True;
      if (P <= Length(JSON)) and (JSON[P] = '{') then Inc(P) else Continue;

      if ConsonantGroupsMap = nil then
        ConsonantGroupsMap := TDictionary<string, TList<string>>.Create
      else
      begin
        for GroupPair in ConsonantGroupsMap do
          GroupPair.Value.Free;
        ConsonantGroupsMap.Clear;
      end;

      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then begin Inc(P); Break; end;
        if JSON[P] = ',' then begin Inc(P); Continue; end;

        CatName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
        JSkipWS(JSON, P);

        if (P <= Length(JSON)) and (JSON[P] = '[') then Inc(P) else Continue;

        GroupList := TList<string>.Create;
        while P <= Length(JSON) do
        begin
          JSkipWS(JSON, P);
          if (P > Length(JSON)) or (JSON[P] = ']') then begin Inc(P); Break; end;
          if JSON[P] = ',' then begin Inc(P); Continue; end;
          if JSON[P] = '"' then
            GroupList.Add(ResolveStringValue(JReadString(JSON, P)))
          else
            JSkipValue(JSON, P);
        end;
        ConsonantGroupsMap.AddOrSetValue(CatName, GroupList);
      end;
    end
    else
      JSkipValue(JSON, P);
  end;

  // Sort replacement arrays by key length (longest first)
  if Length(CustomFullForms) > 0 then
    TArray.Sort<TReplacementPair>(CustomFullForms, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin Result := R.Key.Length - L.Key.Length; end));
  if Length(CustomPreReplacements) > 0 then
    TArray.Sort<TReplacementPair>(CustomPreReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin Result := R.Key.Length - L.Key.Length; end));
  if Length(CustomPostReplacements) > 0 then
    TArray.Sort<TReplacementPair>(CustomPostReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin Result := R.Key.Length - L.Key.Length; end));

  if not ConsonantGroupsFound then
    InitializeDefaultConsonantGroups;

  PrepareActiveReplacements;
  JSON := '';
  OptimizeMemoryUsage;
end;

{ =============================================================================== }

function GetDefaultFullForms: TArray<TReplacementPair>;
var
  Rec: TAnsiVarRec;
  Val: string;
begin
  EnsureAnsiRegistry;
  for Rec in AnsiRegistry do
  begin
    if (Rec.Category = 'FullForms') and (Rec.BengaliChar <> '') then
    begin
      Val := PString(Rec.Ptr)^;
      SetLength(Result, 1);
      Result[0].Key := Rec.BengaliChar;
      Result[0].Value := Val;
      Exit;
    end;
  end;
  SetLength(Result, 0);
end;

function MakeJSONArrOfReplPairs(const Pairs: array of TReplacementPair): string;
var
  SB: TStringBuilder;
  I: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to High(Pairs) do
    begin
      if I > 0 then SB.Append(',');
      SB.Append('{');
      SB.Append('"Key":"').Append(SmartEscape(Pairs[I].Key)).Append('",');
      SB.Append('"Value":"').Append(SmartEscape(Pairs[I].Value)).Append('",');
      SB.Append('"Comment":"').Append(JSONEscape(Pairs[I].Key)).Append('"');
      SB.Append('}');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ =============================================================================== }

procedure ExportAnsiMapping(const Path: string);
var
  Lines: TStringList;
  SB: TStringBuilder;
  CatSB: TStringBuilder;
  CatMap: TDictionary<string, TStringBuilder>;
  I: Integer;
  Val: string;
  Rec: TAnsiVarRec;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  CatMap := TDictionary<string, TStringBuilder>.Create;
  Lines := TStringList.Create;
  try
    for Rec in AnsiRegistry do
    begin
      Val := PString(Rec.Ptr)^;

      if not CatMap.TryGetValue(Rec.Category, CatSB) then
      begin
        CatSB := TStringBuilder.Create;
        CatSB.Append('"').Append(Rec.Category).Append('":{');
        CatMap.Add(Rec.Category, CatSB);
      end
      else
        CatSB.Append(',');
        CatSB.Append('"').Append(Rec.Name).Append('":{');
      CatSB.Append('"Value":"').Append(SmartEscape(Val)).Append('",');
      CatSB.Append('"Comment":"').Append(JSONEscape(Rec.BengaliChar)).Append('"');
      CatSB.Append('}');
    end;

    SB := TStringBuilder.Create;
    try
      SB.Append('{');
      SB.Append('"Constants":{');
      I := 0;
      for CatSB in CatMap.Values do
      begin
        if I > 0 then SB.Append(',');
        CatSB.Append('}');
        SB.Append(CatSB.ToString);
        Inc(I);
      end;
      SB.Append('}');

      if Length(CustomFullForms) > 0 then
        SB.Append(',"FullFormReplacements":').Append(MakeJSONArrOfReplPairs(CustomFullForms))
      else
        SB.Append(',"FullFormReplacements":').Append(MakeJSONArrOfReplPairs(GetDefaultFullForms));
      SB.Append(',"PreReplacements":').Append(MakeJSONArrOfReplPairs(CustomPreReplacements));
      SB.Append(',"PostReplacements":').Append(MakeJSONArrOfReplPairs(CustomPostReplacements));
      SB.Append('}');

      Lines.Text := JSONPrettyPrint(SB.ToString);
      Lines.SaveToFile(Path, TEncoding.UTF8);
    finally
      SB.Free;
    end;
  finally
    for CatSB in CatMap.Values do CatSB.Free;
    CatMap.Free;
    Lines.Free;
  end;
end;

{ =============================================================================== }

function ValidateAnsiMappingFile(const Path: string; out ErrorMessage: string): Boolean;
const
  REPL_SECTIONS: array[0..2] of string = (
    'FullFormReplacements', 'PreReplacements', 'PostReplacements');
var
  JSON: string;
  Lines: TStringList;
  P: Integer;
  Key: string;
  ArrIdx: Integer;
  SectionCount: Integer;
begin
  Result := False;
  ErrorMessage := '';

  if not FileExists(Path) then
  begin
    ErrorMessage := 'File does not exist.';
    Exit;
  end;

  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
    except
      on E: Exception do
      begin
        ErrorMessage := 'Unable to read file: ' + E.Message;
        Exit;
      end;
    end;
    JSON := Lines.Text;
    if Copy(JSON, 1, 3) = #$EF#$BB#$BF then
      Delete(JSON, 1, 3);
  finally
    Lines.Free;
  end;

  P := 1;
  JSkipWS(JSON, P);
  if (P > Length(JSON)) or (JSON[P] <> '{') then
  begin
    ErrorMessage := 'Invalid JSON root: expected an object.';
    Exit;
  end;
  Inc(P);

  SectionCount := 0;
  while P <= Length(JSON) do
  begin
    JSkipWS(JSON, P);
    if (P > Length(JSON)) or (JSON[P] = '}') then Break;
    if JSON[P] = ',' then begin Inc(P); Continue; end;

    Key := JReadString(JSON, P);
    JSkipWS(JSON, P);
    if (P <= Length(JSON)) and (JSON[P] = ':') then Inc(P);
    JSkipWS(JSON, P);

    if Key = 'Constants' then
    begin
      Inc(SectionCount);
      // Must be an object
      if (P > Length(JSON)) or (JSON[P] <> '{') then
      begin
        ErrorMessage := 'Invalid section: Constants must be an object.';
        Exit;
      end;
      JSkipValue(JSON, P);
    end
    else if (Key = REPL_SECTIONS[0]) or (Key = REPL_SECTIONS[1]) or (Key = REPL_SECTIONS[2]) then
    begin
      Inc(SectionCount);
      // Must be an array
      if (P > Length(JSON)) or (JSON[P] <> '[') then
      begin
        ErrorMessage := 'Invalid section: ' + Key + ' must be an array.';
        Exit;
      end;
      Inc(P);
      ArrIdx := 0;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = ']') then Break;
        if JSON[P] = ',' then begin Inc(P); Continue; end;
        if JSON[P] = '{' then
        begin
          Inc(P);
          // Check for Key and Value fields
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then Break;
            if JSON[P] = ',' then begin Inc(P); Continue; end;
            Key := JReadString(JSON, P);
            JSkipWS(JSON, P); if JSON[P] = ':' then Inc(P);
            JSkipValue(JSON, P);
          end;
          // Actually validate Key/Value exist - basic check
          Inc(ArrIdx);
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else
      JSkipValue(JSON, P);
  end;

  if SectionCount < 4 then
  begin
    ErrorMessage := 'Missing sections in mapping file.';
    Exit;
  end;

  Result := True;
end;

{ =============================================================================== }

procedure LoadCurrentActiveMapping(ErrorLog: TStringList = nil);
begin
  if AnsiVersion = 'Default' then
    ResetAnsiToDefaults
  else if AnsiMappingDir <> '' then
    LoadAnsiMapping(AnsiMappingDir + AnsiVersion + '.json', ErrorLog);
end;

{ =============================================================================== }

function TrySetAnsiVersion(const NewVersion: string; out ErrorMessage: string): Boolean;
var
  FilePath: string;
begin
  Result := False;
  ErrorMessage := '';

  if NewVersion = 'Default' then
  begin
    AnsiVersion := 'Default';
    ResetAnsiToDefaults;
    OptimizeMemoryUsage;
    Result := True;
    Exit;
  end;

  if AnsiMappingDir = '' then
  begin
    ErrorMessage := 'ANSI Mapping directory is not set.';
    Exit;
  end;

  FilePath := AnsiMappingDir + NewVersion + '.json';

  if not ValidateAnsiMappingFile(FilePath, ErrorMessage) then
  begin
    Exit;
  end;

  AnsiVersion := NewVersion;
  LoadAnsiMapping(FilePath);
  OptimizeMemoryUsage;
  Result := True;
end;

procedure OptimizeMemoryUsage;
begin
  SetProcessWorkingSetSize(GetCurrentProcess, $FFFFFFFF, $FFFFFFFF);
end;

initialization
  { AnsiRegistry, AnsiRegistryMap, AnsiOverrides are lazily initialized on first use }

finalization
  AnsiRegistry.Free;
  AnsiRegistryMap.Free;
  AnsiOverrides.Free;
  if ConsonantGroupsMap <> nil then
  begin
    for var GroupPair in ConsonantGroupsMap do
      GroupPair.Value.Free;
    ConsonantGroupsMap.Free;
  end;
  VowelRulesList.Free;

end.