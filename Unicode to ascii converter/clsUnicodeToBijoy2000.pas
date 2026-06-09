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
  CustomFullForms: array of TReplacementPair;
  CustomPreReplacements: array of TReplacementPair;
  CustomPostReplacements: array of TReplacementPair; 
  AnsiVersion: string = 'Default';
  AnsiMappingDir: string = '';
  AnsiRegistry: TList<TAnsiVarRec>;
  AnsiRegistryMap: TDictionary<string, TAnsiVarRec>;


procedure ResetAnsiToDefaults;
procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);
procedure ExportAnsiMapping(const Path: string);
procedure LoadCurrentActiveMapping(ErrorLog: TStringList = nil);
function ValidateAnsiMappingFile(const Path: string; out ErrorMessage: string): Boolean;

implementation

uses
  Strutils,
  BanglaChars,
  System.JSON,
  System.SysUtils;

{ Bijoy2000 Font Map Constants }
var
   { Numbers }
  A_0: Char = #$30;
  A_1: Char = #$31;
  A_2: Char = #$32;
  A_3: Char = #$33;
  A_4: Char = #$34;
  A_5: Char = #$35;
  A_6: Char = #$36;
  A_7: Char = #$37;
  A_8: Char = #$38;
  A_9: Char = #$39;

  { Vowels and Kars }
  A_A: Char       = #$41;
  A_AA: string    = #$41#$76;
  A_AAKar: Char   = #$76;
  A_I: Char       = #$42;
  A_IKar: Char    = #$77;
  A_II: Char      = #$43;
  A_IIKar: Char   = #$78;
  A_U: Char       = #$44;
  A_UKar2: Char   = #$79;
  A_UKar1: Char   = #$7A;
  A_UKar3: Char   = #$2013;
  A_UKar4: Char   = #$201C;
  A_UU: Char      = #$45;
  A_UUKar2: Char  = #$7E;
  A_UUKar1: Char  = #$201A;
  A_UUKar3: Char  = #$192;
  A_RRI: Char     = #$46;
  A_RRIKar1: Char = #$201E;
  A_RRIKar2: Char = #$2026;
  A_E: Char       = #$47;
  A_EKar1: Char   = #$2020;
  A_EKar2: Char   = #$2021;
  A_OI: Char      = #$48;
  A_OIKar1: Char  = #$2C6;
  A_OIKar2: Char  = #$2030;
  A_O: Char       = #$49;
  A_OU: Char      = #$4A;
  A_OUKar: Char   = #$160;

  { Symbols }
  A_Taka: Char             = #$24;
  A_Dari: Char             = #$7C;
  A_DoubleDanda: Char      = #$5C;
  A_Hasanta: Char          = #$26;
  A_StartDoubleQuote: Char = #$D2;
  A_EndDoubleQuote: Char   = #$D3;

  A_StartSingleQuote: Char = #$D4;
  A_EndSingleQuote: Char   = #$D5;

  { Consonants }
  A_K: Char        = #$4B;
  A_Kh: Char       = #$4C;
  A_G: Char        = #$4D;
  A_Gh: Char       = #$4E;
  A_NGA: Char      = #$4F;
  A_C: Char        = #$50;
  A_Ch: Char       = #$51;
  A_J: Char        = #$52;
  A_Jh: Char       = #$53;
  A_NYA: Char      = #$54;
  A_Tt: Char       = #$55;
  A_Tth: Char      = #$56;
  A_Dd: Char       = #$57;
  A_Ddh: Char      = #$58;
  A_Nn: Char       = #$59;
  A_T: Char        = #$5A;
  A_Th: Char       = #$5F;
  A_D: Char        = #$60;
  A_Dh: Char       = #$61;
  A_N: Char        = #$62;
  A_P: Char        = #$63;
  A_Ph: Char       = #$64;
  A_B: Char        = #$65;
  A_Bh: Char       = #$66;
  A_M: Char        = #$67;
  A_Z: Char        = #$68;
  A_R: Char        = #$69;
  A_L: Char        = #$6A;
  A_Sh: Char       = #$6B;
  A_SS: Char       = #$6C;
  A_S: Char        = #$6D;
  A_H: Char        = #$6E;
  A_RR: Char       = #$6F;
  A_RRH: Char      = #$70;
  A_Y: Char        = #$71;
  A_Khandata: Char = #$72;
  A_Anushar: Char  = #$73;
  A_Bisharga: Char = #$74;
  A_Chandra: Char  = #$75;

  { Full Forms }
  A_K_K: Char      = #$B0;
  A_K_Tt: Char     = #$B1;
  A_K_Ss_M: Char   = #$B2;
  A_K_T: Char      = #$B3;
  A_K_M: Char      = #$B4;
  A_K_R: Char      = #$B5;
  A_K_Ss: Char     = #$B6;
  A_K_S: Char      = #$B7;
  A_G_Ukar: Char   = #$B8;
  A_G_G: Char      = #$B9;
  A_G_D: Char      = #$BA;
  A_G_Dh: Char     = #$BB;
  A_NGA_K: Char    = #$BC;
  A_NGA_G: Char    = #$BD;
  A_J_J: Char      = #$BE;
  A_J_Jh: Char     = #$C0;
  A_J_NYA: Char    = #$C1;
  A_NYA_C: Char    = #$C2;
  A_NYA_CH: Char   = #$C3;
  A_NYA_J: Char    = #$C4;
  A_NYA_Jh: Char   = #$C5;
  A_Tt_Tt: Char    = #$C6;
  A_Dd_Dd: Char    = #$C7;
  A_Nn_Tt: Char    = #$C8;
  A_Nn_Tth: Char   = #$C9;
  A_NN_Dd: Char    = #$CA;
  A_T_T: Char      = #$CB;
  A_T_Th: Char     = #$CC;
  A_T_M: Char      = #$CD;
  A_T_R: Char      = #$CE;
  A_D_D: Char      = #$CF;
  A_D_Dh: Char     = #$D7;
  A_D_B: Char      = #$D8;
  A_D_M: Char      = #$D9;
  A_N_Tth: Char    = #$DA;
  A_N_Dd: Char     = #$DB;
  A_N_Dh: Char     = #$DC;
  A_N_S: Char      = #$DD;
  A_P_Tt: Char     = #$DE;
  A_P_T: Char      = #$DF;
  A_P_P: Char      = #$E0;
  A_P_S: Char      = #$E1;
  A_B_J: Char      = #$E2;
  A_B_D: Char      = #$E3;
  A_B_Dh: Char     = #$E4;
  A_Bh_R: Char     = #$E5;
  A_M_N: Char      = #$E6;
  A_M_Ph: Char     = #$E7;
  A_L_K: Char      = #$E9;
  A_L_G: Char      = #$EA;
  A_L_Tt: Char     = #$EB;
  A_L_Dd: Char     = #$EC;
  A_L_P: Char      = #$ED;
  A_L_Ph: Char     = #$EE;
  A_Sh_UKar: Char  = #$EF;
  A_Sh_C: Char     = #$F0;
  A_Sh_Ch: Char    = #$F1;
  A_Ss_Nn: Char    = #$F2;
  A_Ss_Tt: Char    = #$F3;
  A_Ss_Tth: Char   = #$F4;
  A_Ss_Ph: Char    = #$F5;
  A_S_Kh: Char     = #$F6;
  A_S_Tt: Char     = #$F7;
  A_S_N: Char      = #$F8;
  A_S_Ph: Char     = #$F9;
  A_H_UKar: Char   = #$FB;
  A_H_RRIKar: Char = #$FC;
  A_H_N: Char      = #$FD;
  A_H_M: Char      = #$FE;
  A_Rr_G: Char     = #$FF;

  { First Half forms }
  A_Reph: Char   = #$A9;
  A_M_1H: Char   = #$A4;
  A_Ss_1H: Char  = #$AE;
  A_S_1H_1: Char = #$AF;
  A_N_1H_1: Char = #$161;
  A_S_1H_2: Char = #$2C9; // -----------Not used
  A_D_1H_1: Char = #$2DC;
  A_C_1H: Char   = #$201D;
  A_NGA_1H: Char = #$2022;
  A_N_1H_2: Char = #$203A;
  A_D_1H_2: Char = #$2122;

  { Second Half forms }
  A_B_2H_1: Char    = #$5E; //
  A_B_2H_2: Char    = #$A1; //
  A_BH_2H: Char     = #$A2; //
  A_BH_R_2H: Char   = #$A3; //
  A_M_2H_1: Char    = #$A5; //
  A_B_2H_3: Char    = #$A6; //
  A_M_2H_2: Char    = #$A7; //
  A_ZFola: Char     = #$A8; //
  A_RFola_1: Char   = #$AA; //
  A_RFola_2: Char   = #$AB; //
  A_L_2H_1: Char    = #$AC; //
  A_L_2H_2: Char    = #$AD; // <--- Not used
  A_T_R_2H: Char    = #$BF; //
  A_RFola_3: Char   = #$D6; //
  A_Nn_2H_1: Char   = #$E8;
  A_K_R_2H: Char    = #$152; //
  A_Nn_2H_2: Char   = #$153;
  A_B_2H_4: Char    = #$178;  //
  A_T_2H: Char      = #$2014; //
  A_T_UKar_2H: Char = #$2018; //
  A_Th_2H: Char     = #$2019; //
  A_K_2H: Char      = #$2039; //
  A_L_2H_3: Char    = #$2212; //


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
  RegVar('A_0', 'Numbers', avChar, @A_0, '#$30', '০');
  RegVar('A_1', 'Numbers', avChar, @A_1, '#$31', '১');
  RegVar('A_2', 'Numbers', avChar, @A_2, '#$32', '২');
  RegVar('A_3', 'Numbers', avChar, @A_3, '#$33', '৩');
  RegVar('A_4', 'Numbers', avChar, @A_4, '#$34', '৪');
  RegVar('A_5', 'Numbers', avChar, @A_5, '#$35', '৫');
  RegVar('A_6', 'Numbers', avChar, @A_6, '#$36', '৬');
  RegVar('A_7', 'Numbers', avChar, @A_7, '#$37', '৭');
  RegVar('A_8', 'Numbers', avChar, @A_8, '#$38', '৮');
  RegVar('A_9', 'Numbers', avChar, @A_9, '#$39', '৯');

  // VowelsAndKars
  RegVar('A_A', 'VowelsAndKars', avChar, @A_A, '#$41', 'অ');
  RegVar('A_AA', 'VowelsAndKars', avString, @A_AA, '#$41#$76', 'আ');
  RegVar('A_AAKar', 'VowelsAndKars', avChar, @A_AAKar, '#$76', 'া (আ-কার)');
  RegVar('A_I', 'VowelsAndKars', avChar, @A_I, '#$42', 'ই');
  RegVar('A_IKar', 'VowelsAndKars', avChar, @A_IKar, '#$77', 'ি (ই-কার)');
  RegVar('A_II', 'VowelsAndKars', avChar, @A_II, '#$43', 'ঈ');
  RegVar('A_IIKar', 'VowelsAndKars', avChar, @A_IIKar, '#$78', 'ী (ঈ-কার)');
  RegVar('A_U', 'VowelsAndKars', avChar, @A_U, '#$44', 'উ');
  RegVar('A_UKar2', 'VowelsAndKars', avChar, @A_UKar2, '#$79', 'ু (উ-কার ২ - ঝুলন্ত)');
  RegVar('A_UKar1', 'VowelsAndKars', avChar, @A_UKar1, '#$7A', 'ু (উ-কার ১ - সাধারণ)');
  RegVar('A_UKar3', 'VowelsAndKars', avChar, @A_UKar3, '#$2013', 'ু (উ-কার ৩ - ড়ু/ঢ়ু)');
  RegVar('A_UKar4', 'VowelsAndKars', avChar, @A_UKar4, '#$201C', 'ু (উ-কার ৪ - রু)');
  RegVar('A_UU', 'VowelsAndKars', avChar, @A_UU, '#$45', 'ঊ');
  RegVar('A_UUKar2', 'VowelsAndKars', avChar, @A_UUKar2, '#$7E', 'ূ (ঊ-কার ২ - ঝুলন্ত)');
  RegVar('A_UUKar1', 'VowelsAndKars', avChar, @A_UUKar1, '#$201A', 'ূ (ঊ-কার ১ - সাধারণ)');
  RegVar('A_UUKar3', 'VowelsAndKars', avChar, @A_UUKar3, '#$192', 'ূ (ঊ-কার ৩ - রূ)');
  RegVar('A_RRI', 'VowelsAndKars', avChar, @A_RRI, '#$46', 'ঋ');
  RegVar('A_RRIKar1', 'VowelsAndKars', avChar, @A_RRIKar1, '#$201E', 'ৃ (ঋ-কার ১)');
  RegVar('A_RRIKar2', 'VowelsAndKars', avChar, @A_RRIKar2, '#$2026', 'ৃ (ঋ-কার ২)');
  RegVar('A_E', 'VowelsAndKars', avChar, @A_E, '#$47', 'এ');
  RegVar('A_EKar1', 'VowelsAndKars', avChar, @A_EKar1, '#$2020', 'ে (এ-কার ১ - সাধারণ)');
  RegVar('A_EKar2', 'VowelsAndKars', avChar, @A_EKar2, '#$2021', 'ে (এ-কার ২ - ঝুলন্ত)');
  RegVar('A_OI', 'VowelsAndKars', avChar, @A_OI, '#$48', 'ঐ');
  RegVar('A_OIKar1', 'VowelsAndKars', avChar, @A_OIKar1, '#$2C6', 'ৈ (ঐ-কার ১ - সাধারণ)');
  RegVar('A_OIKar2', 'VowelsAndKars', avChar, @A_OIKar2, '#$2030', 'ৈ (ঐ-কার ২ - ঝুলন্ত)');
  RegVar('A_O', 'VowelsAndKars', avChar, @A_O, '#$49', 'ও');
  RegVar('A_OU', 'VowelsAndKars', avChar, @A_OU, '#$4A', 'ঔ');
  RegVar('A_OUKar', 'VowelsAndKars', avChar, @A_OUKar, '#$160', 'ৌ (ঔ-কার)');

  // Symbols
  RegVar('A_Taka', 'Symbols', avChar, @A_Taka, '#$24', '৳ (টাকা)');
  RegVar('A_Dari', 'Symbols', avChar, @A_Dari, '#$7C', '। (দাঁড়ি)');
  RegVar('A_DoubleDanda', 'Symbols', avChar, @A_DoubleDanda, '#$5C', '॥ (দ্বিত্ব দাঁড়ি)');
  RegVar('A_Hasanta', 'Symbols', avChar, @A_Hasanta, '#$26', '্ (হসন্ত)');
  RegVar('A_StartDoubleQuote', 'Symbols', avChar, @A_StartDoubleQuote, '#$D2', '" (উদ্ধৃতি শুরু)');
  RegVar('A_EndDoubleQuote', 'Symbols', avChar, @A_EndDoubleQuote, '#$D3', '" (উদ্ধৃতি শেষ)');
  RegVar('A_StartSingleQuote', 'Symbols', avChar, @A_StartSingleQuote, '#$D4', ''' (একক উদ্ধৃতি শুরু)');
  RegVar('A_EndSingleQuote', 'Symbols', avChar, @A_EndSingleQuote, '#$D5', ''' (একক উদ্ধৃতি শেষ)');

  // Consonants
  RegVar('A_K', 'Consonants', avChar, @A_K, '#$4B', 'ক');
  RegVar('A_Kh', 'Consonants', avChar, @A_Kh, '#$4C', 'খ');
  RegVar('A_G', 'Consonants', avChar, @A_G, '#$4D', 'গ');
  RegVar('A_Gh', 'Consonants', avChar, @A_Gh, '#$4E', 'ঘ');
  RegVar('A_NGA', 'Consonants', avChar, @A_NGA, '#$4F', 'ঙ');
  RegVar('A_C', 'Consonants', avChar, @A_C, '#$50', 'চ');
  RegVar('A_Ch', 'Consonants', avChar, @A_Ch, '#$51', 'ছ');
  RegVar('A_J', 'Consonants', avChar, @A_J, '#$52', 'জ');
  RegVar('A_Jh', 'Consonants', avChar, @A_Jh, '#$53', 'ঝ');
  RegVar('A_NYA', 'Consonants', avChar, @A_NYA, '#$54', 'ঞ');
  RegVar('A_Tt', 'Consonants', avChar, @A_Tt, '#$55', 'ট');
  RegVar('A_Tth', 'Consonants', avChar, @A_Tth, '#$56', 'ঠ');
  RegVar('A_Dd', 'Consonants', avChar, @A_Dd, '#$57', 'ড');
  RegVar('A_Ddh', 'Consonants', avChar, @A_Ddh, '#$58', 'ঢ');
  RegVar('A_Nn', 'Consonants', avChar, @A_Nn, '#$59', 'ণ');
  RegVar('A_T', 'Consonants', avChar, @A_T, '#$5A', 'ত');
  RegVar('A_Th', 'Consonants', avChar, @A_Th, '#$5F', 'থ');
  RegVar('A_D', 'Consonants', avChar, @A_D, '#$60', 'দ');
  RegVar('A_Dh', 'Consonants', avChar, @A_Dh, '#$61', 'ধ');
  RegVar('A_N', 'Consonants', avChar, @A_N, '#$62', 'ন');
  RegVar('A_P', 'Consonants', avChar, @A_P, '#$63', 'প');
  RegVar('A_Ph', 'Consonants', avChar, @A_Ph, '#$64', 'ফ');
  RegVar('A_B', 'Consonants', avChar, @A_B, '#$65', 'ব');
  RegVar('A_Bh', 'Consonants', avChar, @A_Bh, '#$66', 'ভ');
  RegVar('A_M', 'Consonants', avChar, @A_M, '#$67', 'ম');
  RegVar('A_Z', 'Consonants', avChar, @A_Z, '#$68', 'য');
  RegVar('A_R', 'Consonants', avChar, @A_R, '#$69', 'র');
  RegVar('A_L', 'Consonants', avChar, @A_L, '#$6A', 'ল');
  RegVar('A_Sh', 'Consonants', avChar, @A_Sh, '#$6B', 'শ');
  RegVar('A_SS', 'Consonants', avChar, @A_SS, '#$6C', 'ষ');
  RegVar('A_S', 'Consonants', avChar, @A_S, '#$6D', 'স');
  RegVar('A_H', 'Consonants', avChar, @A_H, '#$6E', 'হ');
  RegVar('A_RR', 'Consonants', avChar, @A_RR, '#$6F', 'ড়');
  RegVar('A_RRH', 'Consonants', avChar, @A_RRH, '#$70', 'ঢ়');
  RegVar('A_Y', 'Consonants', avChar, @A_Y, '#$71', 'য়');
  RegVar('A_Khandata', 'Consonants', avChar, @A_Khandata, '#$72', 'ৎ');
  RegVar('A_Anushar', 'Consonants', avChar, @A_Anushar, '#$73', 'ং');
  RegVar('A_Bisharga', 'Consonants', avChar, @A_Bisharga, '#$74', 'ঃ');
  RegVar('A_Chandra', 'Consonants', avChar, @A_Chandra, '#$75', 'ঁ');

  // FullForms
  RegVar('A_K_K', 'FullForms', avChar, @A_K_K, '#$B0', 'ক্ক');
  RegVar('A_K_Tt', 'FullForms', avChar, @A_K_Tt, '#$B1', 'ক্ট');
  RegVar('A_K_Ss_M', 'FullForms', avChar, @A_K_Ss_M, '#$B2', 'ক্স্ম');
  RegVar('A_K_T', 'FullForms', avChar, @A_K_T, '#$B3', 'ক্ত');
  RegVar('A_K_M', 'FullForms', avChar, @A_K_M, '#$B4', 'ক্ম');
  RegVar('A_K_R', 'FullForms', avChar, @A_K_R, '#$B5', 'ক্র');
  RegVar('A_K_Ss', 'FullForms', avChar, @A_K_Ss, '#$B6', 'ক্ষ');
  RegVar('A_K_S', 'FullForms', avChar, @A_K_S, '#$B7', 'ক্স');
  RegVar('A_G_Ukar', 'FullForms', avChar, @A_G_Ukar, '#$B8', 'গু');
  RegVar('A_G_G', 'FullForms', avChar, @A_G_G, '#$B9', 'গ্গ');
  RegVar('A_G_D', 'FullForms', avChar, @A_G_D, '#$BA', 'গ্দ');
  RegVar('A_G_Dh', 'FullForms', avChar, @A_G_Dh, '#$BB', 'গ্ধ');
  RegVar('A_NGA_K', 'FullForms', avChar, @A_NGA_K, '#$BC', 'ঙ্ক');
  RegVar('A_NGA_G', 'FullForms', avChar, @A_NGA_G, '#$BD', 'ঙ্গ');
  RegVar('A_J_J', 'FullForms', avChar, @A_J_J, '#$BE', 'জ্জ');
  RegVar('A_J_Jh', 'FullForms', avChar, @A_J_Jh, '#$C0', 'জ্ঝ');
  RegVar('A_J_NYA', 'FullForms', avChar, @A_J_NYA, '#$C1', 'জ্ঞ');
  RegVar('A_NYA_C', 'FullForms', avChar, @A_NYA_C, '#$C2', 'ঞ্চ');
  RegVar('A_NYA_CH', 'FullForms', avChar, @A_NYA_CH, '#$C3', 'ঞ্ছ');
  RegVar('A_NYA_J', 'FullForms', avChar, @A_NYA_J, '#$C4', 'ঞ্জ');
  RegVar('A_NYA_Jh', 'FullForms', avChar, @A_NYA_Jh, '#$C5', 'ঞ্ঝ');
  RegVar('A_Tt_Tt', 'FullForms', avChar, @A_Tt_Tt, '#$C6', 'ট্ট');
  RegVar('A_Dd_Dd', 'FullForms', avChar, @A_Dd_Dd, '#$C7', 'ড্ড');
  RegVar('A_Nn_Tt', 'FullForms', avChar, @A_Nn_Tt, '#$C8', 'ণ্ট');
  RegVar('A_Nn_Tth', 'FullForms', avChar, @A_Nn_Tth, '#$C9', 'ণ্ঠ');
  RegVar('A_NN_Dd', 'FullForms', avChar, @A_NN_Dd, '#$CA', 'ণ্ড');
  RegVar('A_T_T', 'FullForms', avChar, @A_T_T, '#$CB', 'ত্ত');
  RegVar('A_T_Th', 'FullForms', avChar, @A_T_Th, '#$CC', 'ত্থ');
  RegVar('A_T_M', 'FullForms', avChar, @A_T_M, '#$CD', 'ত্ম');
  RegVar('A_T_R', 'FullForms', avChar, @A_T_R, '#$CE', 'ত্র');
  RegVar('A_D_D', 'FullForms', avChar, @A_D_D, '#$CF', 'দ্দ');
  RegVar('A_D_Dh', 'FullForms', avChar, @A_D_Dh, '#$D7', 'দ্ধ');
  RegVar('A_D_B', 'FullForms', avChar, @A_D_B, '#$D8', 'দ্ব');
  RegVar('A_D_M', 'FullForms', avChar, @A_D_M, '#$D9', 'দ্ম');
  RegVar('A_N_Tth', 'FullForms', avChar, @A_N_Tth, '#$DA', 'ন্থ');
  RegVar('A_N_Dd', 'FullForms', avChar, @A_N_Dd, '#$DB', 'ন্ড');
  RegVar('A_N_Dh', 'FullForms', avChar, @A_N_Dh, '#$DC', 'ন্ধ');
  RegVar('A_N_S', 'FullForms', avChar, @A_N_S, '#$DD', 'ন্স');
  RegVar('A_P_Tt', 'FullForms', avChar, @A_P_Tt, '#$DE', 'প্ট');
  RegVar('A_P_T', 'FullForms', avChar, @A_P_T, '#$DF', 'প্ত');
  RegVar('A_P_P', 'FullForms', avChar, @A_P_P, '#$E0', 'প্প');
  RegVar('A_P_S', 'FullForms', avChar, @A_P_S, '#$E1', 'প্স');
  RegVar('A_B_J', 'FullForms', avChar, @A_B_J, '#$E2', 'ব্জ');
  RegVar('A_B_D', 'FullForms', avChar, @A_B_D, '#$E3', 'ব্দ');
  RegVar('A_B_Dh', 'FullForms', avChar, @A_B_Dh, '#$E4', 'ব্ধ');
  RegVar('A_Bh_R', 'FullForms', avChar, @A_Bh_R, '#$E5', 'ভ্র');
  RegVar('A_M_N', 'FullForms', avChar, @A_M_N, '#$E6', 'ম্ন');
  RegVar('A_M_Ph', 'FullForms', avChar, @A_M_Ph, '#$E7', 'ম্ফ');
  RegVar('A_L_K', 'FullForms', avChar, @A_L_K, '#$E9', 'ল্ক');
  RegVar('A_L_G', 'FullForms', avChar, @A_L_G, '#$EA', 'ল্গ');
  RegVar('A_L_Tt', 'FullForms', avChar, @A_L_Tt, '#$EB', 'ল্ট');
  RegVar('A_L_Dd', 'FullForms', avChar, @A_L_Dd, '#$EC', 'ল্ড');
  RegVar('A_L_P', 'FullForms', avChar, @A_L_P, '#$ED', 'ল্প');
  RegVar('A_L_Ph', 'FullForms', avChar, @A_L_Ph, '#$EE', 'ল্ফ');
  RegVar('A_Sh_UKar', 'FullForms', avChar, @A_Sh_UKar, '#$EF', 'শু');
  RegVar('A_Sh_C', 'FullForms', avChar, @A_Sh_C, '#$F0', 'শ্চ');
  RegVar('A_Sh_Ch', 'FullForms', avChar, @A_Sh_Ch, '#$F1', 'শ্ছ');
  RegVar('A_Ss_Nn', 'FullForms', avChar, @A_Ss_Nn, '#$F2', 'ষ্ণ');
  RegVar('A_Ss_Tt', 'FullForms', avChar, @A_Ss_Tt, '#$F3', 'ষ্ট');
  RegVar('A_Ss_Tth', 'FullForms', avChar, @A_Ss_Tth, '#$F4', 'ষ্ঠ');
  RegVar('A_Ss_Ph', 'FullForms', avChar, @A_Ss_Ph, '#$F5', 'স্ফ');
  RegVar('A_S_Kh', 'FullForms', avChar, @A_S_Kh, '#$F6', 'স্খ');
  RegVar('A_S_Tt', 'FullForms', avChar, @A_S_Tt, '#$F7', 'স্ট');
  RegVar('A_S_N', 'FullForms', avChar, @A_S_N, '#$F8', 'স্ন');
  RegVar('A_S_Ph', 'FullForms', avChar, @A_S_Ph, '#$F9', 'স্ফ');
  RegVar('A_H_UKar', 'FullForms', avChar, @A_H_UKar, '#$FB', 'হু');
  RegVar('A_H_RRIKar', 'FullForms', avChar, @A_H_RRIKar, '#$FC', 'হৃ');
  RegVar('A_H_N', 'FullForms', avChar, @A_H_N, '#$FD', 'হ্ন');
  RegVar('A_H_M', 'FullForms', avChar, @A_H_M, '#$FE', 'হ্ম');
  RegVar('A_Rr_G', 'FullForms', avChar, @A_Rr_G, '#$FF', 'র্গ');

  // FirstHalfForms
  RegVar('A_Reph', 'FirstHalfForms', avChar, @A_Reph, '#$A9', '্র (র-এর রেফ)');
  RegVar('A_M_1H', 'FirstHalfForms', avChar, @A_M_1H, '#$A4', 'ম-এর প্রথম খন্ড');
  RegVar('A_Ss_1H', 'FirstHalfForms', avChar, @A_Ss_1H, '#$AE', 'ষ-এর প্রথম খন্ড');
  RegVar('A_S_1H_1', 'FirstHalfForms', avChar, @A_S_1H_1, '#$AF', 'স-এর প্রথম খন্ড ১');
  RegVar('A_N_1H_1', 'FirstHalfForms', avChar, @A_N_1H_1, '#$161', 'ন-এর প্রথম খন্ড ১');
  RegVar('A_S_1H_2', 'FirstHalfForms', avChar, @A_S_1H_2, '#$2C9', 'স-এর প্রথম খন্ড ২');
  RegVar('A_D_1H_1', 'FirstHalfForms', avChar, @A_D_1H_1, '#$2DC', 'দ-এর প্রথম খন্ড ১');
  RegVar('A_C_1H', 'FirstHalfForms', avChar, @A_C_1H, '#$201D', 'চ-এর প্রথম খন্ড');
  RegVar('A_NGA_1H', 'FirstHalfForms', avChar, @A_NGA_1H, '#$2022', 'ঙ-এর প্রথম খন্ড');
  RegVar('A_N_1H_2', 'FirstHalfForms', avChar, @A_N_1H_2, '#$203A', 'ন-এর প্রথম খন্ড ২');
  RegVar('A_D_1H_2', 'FirstHalfForms', avChar, @A_D_1H_2, '#$2122', 'দ-এর প্রথম খন্ড ২');

  // SecondHalfForms
  RegVar('A_B_2H_1', 'SecondHalfForms', avChar, @A_B_2H_1, '#$5E', 'ব-এর দ্বিতীয় খন্ড ১');
  RegVar('A_B_2H_2', 'SecondHalfForms', avChar, @A_B_2H_2, '#$A1', 'ব-এর দ্বিতীয় খন্ড ২');
  RegVar('A_BH_2H', 'SecondHalfForms', avChar, @A_BH_2H, '#$A2', 'ভ-এর দ্বিতীয় খন্ড');
  RegVar('A_BH_R_2H', 'SecondHalfForms', avChar, @A_BH_R_2H, '#$A3', 'ভ্র-এর দ্বিতীয় খন্ড');
  RegVar('A_M_2H_1', 'SecondHalfForms', avChar, @A_M_2H_1, '#$A5', 'ম-এর দ্বিতীয় খন্ড ১');
  RegVar('A_B_2H_3', 'SecondHalfForms', avChar, @A_B_2H_3, '#$A6', 'ব-এর দ্বিতীয় খন্ড ৩');
  RegVar('A_M_2H_2', 'SecondHalfForms', avChar, @A_M_2H_2, '#$A7', 'ম-এর দ্বিতীয় খন্ড ২');
  RegVar('A_ZFola', 'SecondHalfForms', avChar, @A_ZFola, '#$A8', 'য-ফলা');
  RegVar('A_RFola_1', 'SecondHalfForms', avChar, @A_RFola_1, '#$AA', 'র-ফলা ১');
  RegVar('A_RFola_2', 'SecondHalfForms', avChar, @A_RFola_2, '#$AB', 'র-ফলা ২');
  RegVar('A_L_2H_1', 'SecondHalfForms', avChar, @A_L_2H_1, '#$AC', 'ল-এর দ্বিতীয় খন্ড ১');
  RegVar('A_L_2H_2', 'SecondHalfForms', avChar, @A_L_2H_2, '#$AD', 'ল-এর দ্বিতীয় খন্ড ২');
  RegVar('A_T_R_2H', 'SecondHalfForms', avChar, @A_T_R_2H, '#$BF', 'ত্র-এর দ্বিতীয় খন্ড');
  RegVar('A_RFola_3', 'SecondHalfForms', avChar, @A_RFola_3, '#$D6', 'র-ফলা ৩');
  RegVar('A_Nn_2H_1', 'SecondHalfForms', avChar, @A_Nn_2H_1, '#$E8', 'ণ-এর দ্বিতীয় খন্ড ১');
  RegVar('A_K_R_2H', 'SecondHalfForms', avChar, @A_K_R_2H, '#$152', 'ক্র-এর দ্বিতীয় খন্ড');
  RegVar('A_Nn_2H_2', 'SecondHalfForms', avChar, @A_Nn_2H_2, '#$153', 'ণ-এর দ্বিতীয় খন্ড ২');
  RegVar('A_B_2H_4', 'SecondHalfForms', avChar, @A_B_2H_4, '#$178', 'ব-এর দ্বিতীয় খন্ড ৪');
  RegVar('A_T_2H', 'SecondHalfForms', avChar, @A_T_2H, '#$2014', 'ত-এর দ্বিতীয় খন্ড');
  RegVar('A_T_UKar_2H', 'SecondHalfForms', avChar, @A_T_UKar_2H, '#$2018', 'তু-এর দ্বিতীয় খন্ড');
  RegVar('A_Th_2H', 'SecondHalfForms', avChar, @A_Th_2H, '#$2019', 'থ-এর দ্বিতীয় খন্ড');
  RegVar('A_K_2H', 'SecondHalfForms', avChar, @A_K_2H, '#$2039', 'ক-এর দ্বিতীয় খন্ড');
  RegVar('A_L_2H_3', 'SecondHalfForms', avChar, @A_L_2H_3, '#$2212', 'ল-এর দ্বিতীয় খন্ড ৩');
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
      fConvertedText[I] := A_D_1H_1
    else
      fConvertedText[I] := A_D_1H_2;
  until I <= 0;

  { Elevate first-half N-forms }
  repeat
    I := Pos(b_n + b_Hasanta, fConvertedText);
    if I <= 0 then
      break;
    if ((I + 2 <= Length(fConvertedText)) and 
        ((fConvertedText[I + 2] = b_t) or (fConvertedText[I + 2] = b_Th) or 
         (fConvertedText[I + 2] = b_L) or (fConvertedText[I + 2] = b_b) or 
         (fConvertedText[I + 2] = A_T_R_2H) or (fConvertedText[I + 2] = A_T_UKar_2H))) then
      fConvertedText[I] := A_N_1H_1
    else if (I + 2 <= Length(fConvertedText)) and 
            ((fConvertedText[I + 2] = b_m) or (fConvertedText[I + 2] = b_n)) then
      fConvertedText[I] := A_N
    else
      fConvertedText[I] := A_N_1H_2;
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
      if fConvertedText[Len] = string(b_Hasanta)[1] then
        fConvertedText[Len] := A_Hasanta;
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

  // Warning: Hardcoded conversion
  fConvertedText := ReplaceStr(fConvertedText, 'Rz', 'Ry');
  fConvertedText := ReplaceStr(fConvertedText, 'R‚', 'R~');
  fConvertedText := ReplaceStr(fConvertedText, 'o‚', 'o~');
  fConvertedText := ReplaceStr(fConvertedText, 'p‚', 'p~');
  fConvertedText := ReplaceStr(fConvertedText, 'i‚', 'i~');
  
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
  I: Integer;
begin
  { Replace Numbers }
  fConvertedText := ReplaceStr(fConvertedText, b_0, A_0);
  fConvertedText := ReplaceStr(fConvertedText, b_1, A_1);
  fConvertedText := ReplaceStr(fConvertedText, b_2, A_2);
  fConvertedText := ReplaceStr(fConvertedText, b_3, A_3);
  fConvertedText := ReplaceStr(fConvertedText, b_4, A_4);
  fConvertedText := ReplaceStr(fConvertedText, b_5, A_5);
  fConvertedText := ReplaceStr(fConvertedText, b_6, A_6);
  fConvertedText := ReplaceStr(fConvertedText, b_7, A_7);
  fConvertedText := ReplaceStr(fConvertedText, b_8, A_8);
  fConvertedText := ReplaceStr(fConvertedText, b_9, A_9);

  { Replace Symbols }
  fConvertedText := ReplaceStr(fConvertedText, b_Taka, A_Taka);
  fConvertedText := ReplaceStr(fConvertedText, b_Dari, A_Dari);
  fConvertedText := ReplaceStr(fConvertedText, string(#$965), A_DoubleDanda);

  { Replace Other Full Forms }
  fConvertedText := ReplaceStr(fConvertedText, b_Khandatta, A_Khandata);
  fConvertedText := ReplaceStr(fConvertedText, b_Anushar, A_Anushar);
  fConvertedText := ReplaceStr(fConvertedText, b_Bisharga, A_Bisharga);
  fConvertedText := ReplaceStr(fConvertedText, b_Chandra, A_Chandra);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_K, A_K_K);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_tt, A_K_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_ss + b_Hasanta + b_m, A_K_Ss_M);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_t, A_K_T);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_m, A_K_M);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_ss, A_K_Ss);
  fConvertedText := ReplaceStr(fConvertedText, b_K + b_Hasanta + b_s, A_K_S);
  fConvertedText := ReplaceStr(fConvertedText, b_g + b_Hasanta + b_g, A_G_G);
  fConvertedText := ReplaceStr(fConvertedText, b_g + b_Hasanta + b_d, A_G_D);
  fConvertedText := ReplaceStr(fConvertedText, b_g + b_Hasanta + b_dh, A_G_Dh);
  fConvertedText := ReplaceStr(fConvertedText, b_NGA + b_Hasanta + b_K, A_NGA_K);
  fConvertedText := ReplaceStr(fConvertedText, b_NGA + b_Hasanta + b_g, A_NGA_G);
  fConvertedText := ReplaceStr(fConvertedText, b_j + b_Hasanta + b_j, A_J_J);
  fConvertedText := ReplaceStr(fConvertedText, b_j + b_Hasanta + b_jh, A_J_Jh);
  fConvertedText := ReplaceStr(fConvertedText, b_j + b_Hasanta + b_nya, A_J_NYA);
  fConvertedText := ReplaceStr(fConvertedText, b_nya + b_Hasanta + b_C, A_NYA_C);
  fConvertedText := ReplaceStr(fConvertedText, b_nya + b_Hasanta + b_ch, A_NYA_CH);
  fConvertedText := ReplaceStr(fConvertedText, b_nya + b_Hasanta + b_j, A_NYA_J);
  fConvertedText := ReplaceStr(fConvertedText, b_nya + b_Hasanta + b_jh, A_NYA_Jh);
  fConvertedText := ReplaceStr(fConvertedText, b_tt + b_Hasanta + b_tt, A_Tt_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_dd + b_Hasanta + b_dd, A_Dd_Dd);
  fConvertedText := ReplaceStr(fConvertedText, b_Nn + b_Hasanta + b_tt, A_Nn_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_Nn + b_Hasanta + b_tth, A_Nn_Tth);
  fConvertedText := ReplaceStr(fConvertedText, b_Nn + b_Hasanta + b_dd, A_NN_Dd);
  fConvertedText := ReplaceStr(fConvertedText, b_t + b_Hasanta + b_t, A_T_T);
  fConvertedText := ReplaceStr(fConvertedText, b_t + b_Hasanta + b_Th, A_T_Th);
  fConvertedText := ReplaceStr(fConvertedText, b_t + b_Hasanta + b_m, A_T_M);
  fConvertedText := ReplaceStr(fConvertedText, b_d + b_Hasanta + b_d, A_D_D);
  fConvertedText := ReplaceStr(fConvertedText, b_d + b_Hasanta + b_dh, A_D_Dh);
  fConvertedText := ReplaceStr(fConvertedText, b_d + b_Hasanta + b_b, A_D_B);
  fConvertedText := ReplaceStr(fConvertedText, b_d + b_Hasanta + b_m, A_D_M);
  fConvertedText := ReplaceStr(fConvertedText, b_n + b_Hasanta + b_tth, A_N_Tth);
  fConvertedText := ReplaceStr(fConvertedText, b_n + b_Hasanta + b_dd, A_N_Dd);
  fConvertedText := ReplaceStr(fConvertedText, b_n + b_Hasanta + b_dh, A_N_Dh);
  fConvertedText := ReplaceStr(fConvertedText, b_n + b_Hasanta + b_s, A_N_S);
  fConvertedText := ReplaceStr(fConvertedText, b_p + b_Hasanta + b_tt, A_P_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_p + b_Hasanta + b_t, A_P_T);
  fConvertedText := ReplaceStr(fConvertedText, b_p + b_Hasanta + b_p, A_P_P);
  fConvertedText := ReplaceStr(fConvertedText, b_p + b_Hasanta + b_s, A_P_S);
  fConvertedText := ReplaceStr(fConvertedText, b_b + b_Hasanta + b_j, A_B_J);
  fConvertedText := ReplaceStr(fConvertedText, b_b + b_Hasanta + b_d, A_B_D);
  fConvertedText := ReplaceStr(fConvertedText, b_b + b_Hasanta + b_dh, A_B_Dh);
  fConvertedText := ReplaceStr(fConvertedText, b_m + b_Hasanta + b_n, A_M_N);
  fConvertedText := ReplaceStr(fConvertedText, b_m + b_Hasanta + b_ph, A_M_Ph);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_K, A_L_K);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_g, A_L_G);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_tt, A_L_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_dd, A_L_Dd);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_p, A_L_P);
  fConvertedText := ReplaceStr(fConvertedText, b_L + b_Hasanta + b_ph, A_L_Ph);
  fConvertedText := ReplaceStr(fConvertedText, b_sh + b_Hasanta + b_C, A_Sh_C);
  fConvertedText := ReplaceStr(fConvertedText, b_sh + b_Hasanta + b_ch, A_Sh_Ch);
  fConvertedText := ReplaceStr(fConvertedText, b_ss + b_Hasanta + b_Nn, A_Ss_Nn);
  fConvertedText := ReplaceStr(fConvertedText, b_ss + b_Hasanta + b_tt, A_Ss_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_ss + b_Hasanta + b_tth, A_Ss_Tth);
  fConvertedText := ReplaceStr(fConvertedText, b_ss + b_Hasanta + b_ph, A_Ss_Ph);
  fConvertedText := ReplaceStr(fConvertedText, b_s + b_Hasanta + b_kh, A_S_Kh);
  fConvertedText := ReplaceStr(fConvertedText, b_s + b_Hasanta + b_tt, A_S_Tt);
  fConvertedText := ReplaceStr(fConvertedText, b_s + b_Hasanta + b_n, A_S_N);
  fConvertedText := ReplaceStr(fConvertedText, b_s + b_Hasanta + b_ph, A_S_Ph);
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Hasanta + b_n, A_H_N);
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Hasanta + b_m, A_H_M);
  fConvertedText := ReplaceStr(fConvertedText, b_rr + b_Hasanta + b_g, A_Rr_G);

  { Apply custom full form overrides AFTER hardcoded patterns }
  for I := 0 to Length(CustomFullForms) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomFullForms[I].Key, CustomFullForms[I].Value);
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.BaseLineRightCharacter(const wC: string): Boolean;
begin
  Result := False;
  if (wC = b_kh) or (wC = b_g) or (wC = b_gh) or (wC = b_Nn) or (wC = b_Th) or (wC = b_d) or (wC = b_dh) or (wC = b_n) or (wC = b_p) or (wC = b_b) or
    (wC = b_m) or (wC = b_z) or (wC = b_r) or (wC = b_L) or (wC = b_sh) or (wC = b_ss) or (wC = b_s) or (wC = b_h) or (wC = b_y) then
    Result := True;

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
  
  // 1. Apply dynamic pre-placement fixes (if any)
  for I := 0 to Length(CustomPreReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPreReplacements[I].Key, CustomPreReplacements[I].Value);

  // 2. Rearrange Vowels and Reph
  ReArrangeKars;
  ReArrangeReph;

  // 3. Process Vowels FIRST (while consonants are still Unicode)
  ReplaceKarsVowels;

  // 4. Process Conjuncts and Full Forms LATER
  ReplaceFullForms;

  // 5. Apply Glyphs, Halfs, and Consonants
  ConvertRFola_ZFola_Hasanta;
  FirstHalfForms;
  SecondHalfForms;
  Consonants;
  FinalTouch;
  
  Result := fConvertedText;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ConvertRFola_ZFola_Hasanta;
var
  I: Integer;
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
    { P/G + RoFola }
    if ((MidStr(fConvertedText, I - 1, 1) = b_p) or (MidStr(fConvertedText, I - 1, 1) = b_g)) then
      // MidStr(fConvertedText, I, 2) := A_RFola_3
      fConvertedText := WideStuffString(fConvertedText, I, 2, A_RFola_3)
      { V+Rofola, 2nd Half V+Rofola }
    else if MidStr(fConvertedText, I - 1, 1) = b_Bh then
    begin
      if MidStr(fConvertedText, I - 2, 1) = b_Hasanta then
        // MidStr(fConvertedText, I - 1, 3) := A_BH_R_2H
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_BH_R_2H)
      else
        // MidStr(fConvertedText, I - 1, 3) := A_Bh_R;
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_Bh_R);
    end
    { K+Rofola, 2nd Half K+Rofola }
    else if MidStr(fConvertedText, I - 1, 1) = b_K then
    begin
      if MidStr(fConvertedText, I - 2, 1) = b_Hasanta then
        // MidStr(fConvertedText, I - 1, 3) := A_K_R_2H
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_K_R_2H)
      else
        // MidStr(fConvertedText, I - 1, 3) := A_K_R;
        fConvertedText := WideStuffString(fConvertedText, I - 1, 3, A_K_R);
    end
    { T+Rofola, 2nd Half T+Rofola }
    else if MidStr(fConvertedText, I - 1, 1) = b_t then
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
    else
    begin
      if MidStr(fConvertedText, I - 1, 1) = b_ph then
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
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Hasanta, b_Hasanta);
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
          wSTmp := wCTmp + fKar + wSTmp;
          fKar := #0;
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
              wSTmp := fKar + wCTmp + wSTmp;
              // Place pending kar at begining
              fKar := #0;
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
  PrecedingChar: string;
  IsZfola: Boolean;
begin
  // Convert Ekar
  repeat
    I := Pos(b_Ekar, fConvertedText);
    if I <= 0 then
      break;
    if ((I = 1) or (MidStr(fConvertedText, I - 1, 1) = ' ') or (MidStr(fConvertedText, I - 1, 1) = #13) or (MidStr(fConvertedText, I - 1, 1) = #10) or
        (MidStr(fConvertedText, I - 1, 1) = #9)) then
      fConvertedText[I] := A_EKar1
    else
      fConvertedText[I] := A_EKar2;
  until I <= 0;

  // Convert OIKar
  repeat
    I := Pos(b_OIKar, fConvertedText);
    if I <= 0 then
      break;
    if ((I = 1) or (MidStr(fConvertedText, I - 1, 1) = ' ') or (MidStr(fConvertedText, I - 1, 1) = #13) or (MidStr(fConvertedText, I - 1, 1) = #10) or
        (MidStr(fConvertedText, I - 1, 1) = #9)) then
      fConvertedText[I] := A_OIKar1
    else
      fConvertedText[I] := A_OIKar2;
  until I <= 0;

// Convert UKar
  fConvertedText := ReplaceStr(fConvertedText, b_g + b_Ukar, A_G_Ukar);
  fConvertedText := ReplaceStr(fConvertedText, b_sh + b_Ukar, A_Sh_UKar);
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Ukar, A_H_UKar);
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_t + b_Ukar, b_Hasanta + A_T_UKar_2H);
  repeat
    I := Pos(b_Ukar, fConvertedText);
    if I <= 0 then
      break;
    if I - 1 >= 1 then
    begin
      PrecedingChar := fConvertedText[I - 1];      
      IsZfola := (PrecedingChar = b_z) and (I - 2 >= 1) and (fConvertedText[I - 2] = b_Hasanta);
      
      if IsZfola then
      begin
        if I - 3 >= 1 then
          PrecedingChar := fConvertedText[I - 3]
        else
          PrecedingChar := '';
      end;

      if BaseLineRightCharacter(PrecedingChar) = True then
      begin

        if PrecedingChar = b_r then
        begin
          if fRaUKarToggle then
            fConvertedText[I] := A_UKar2
          else
            fConvertedText[I] := A_UKar4;
        end
        else if PrecedingChar = b_L then
        begin
          if ((MidStr(fConvertedText, I - 3, 3) = b_g + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 3, 3) = b_p + b_Hasanta + b_L) or
              (MidStr(fConvertedText, I - 3, 3) = b_b + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 3, 3) = b_sh + b_Hasanta + b_L) or
              (MidStr(fConvertedText, I - 3, 3) = b_s + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 5, 5) = b_s + b_Hasanta + b_p + b_Hasanta + b_L)) then
            fConvertedText[I] := A_UKar4
          else
            fConvertedText[I] := A_UKar2;
        end
        else
          fConvertedText[I] := A_UKar2;

        if MidStr(fConvertedText, I - 3, 3) = b_ss + b_Hasanta + b_Nn then
          fConvertedText[I] := A_UKar1;

      end
      else
      begin
        if ((PrecedingChar = b_rr) or (PrecedingChar = b_rrh)) then
        begin
          fConvertedText[I] := A_UKar1;
        end
        else
          fConvertedText[I] := A_UKar1;
      end;
    end
    else
      fConvertedText[I] := A_UKar1;
  until I <= 0;

  // Convert UUKar
  repeat
    I := Pos(b_UUKar, fConvertedText);
    if I <= 0 then
      break;
    if I - 1 >= 1 then
    begin
      PrecedingChar := fConvertedText[I - 1];
      IsZfola := (PrecedingChar = b_z) and (I - 2 >= 1) and (fConvertedText[I - 2] = b_Hasanta);
      
      if IsZfola then
      begin
        if I - 3 >= 1 then
          PrecedingChar := fConvertedText[I - 3]
        else
          PrecedingChar := '';
      end;

      if BaseLineRightCharacter(PrecedingChar) = True then
      begin
        if PrecedingChar = b_r then
        begin
          if ((MidStr(fConvertedText, I - 3, 3) = b_sh + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 3, 3) = b_d + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_g + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 3, 3) = b_t + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_j + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 3, 3) = b_Th + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_dh + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 5, 5) = b_n + b_Hasanta + b_d + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_p + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 3, 3) = b_b + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_Bh + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 3, 3) = b_m + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 3, 3) = b_s + b_Hasanta + b_r) or (MidStr(fConvertedText, I - 5, 5) = b_m + b_Hasanta + b_p + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 5, 5) = b_ss + b_Hasanta + b_p + b_Hasanta + b_r) or
              (MidStr(fConvertedText, I - 5, 5) = b_s + b_Hasanta + b_p + b_Hasanta + b_r)) then
            fConvertedText[I] := A_UUKar3
          else if MidStr(fConvertedText, I - 2, 1) <> b_Hasanta then
          begin
            if fRaUUKarToggle then
              fConvertedText[I] := A_UUKar2
            else
              fConvertedText[I] := A_UUKar3;
          end
          else
            fConvertedText[I] := A_UUKar2;
        end
        else if PrecedingChar = b_L then
        begin
          if ((MidStr(fConvertedText, I - 3, 3) = b_g + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 3, 3) = b_p + b_Hasanta + b_L) or
              (MidStr(fConvertedText, I - 3, 3) = b_b + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 3, 3) = b_sh + b_Hasanta + b_L) or
              (MidStr(fConvertedText, I - 3, 3) = b_s + b_Hasanta + b_L) or (MidStr(fConvertedText, I - 5, 5) = b_s + b_Hasanta + b_p + b_Hasanta + b_L)) then
            fConvertedText[I] := A_UUKar3
          else
            fConvertedText[I] := A_UUKar2;
        end
        else
          fConvertedText[I] := A_UUKar2;
      end
      else
        fConvertedText[I] := A_UUKar1;
    end
    else
      fConvertedText[I] := A_UUKar1;
  until I <= 0;

  // Convert RRIKar
  fConvertedText := ReplaceStr(fConvertedText, b_h + b_Rrikar, A_H_RRIKar);
  repeat
    I := Pos(b_Rrikar, fConvertedText);
    if I <= 0 then
      break;
    if I - 1 >= 1 then
    begin
      if BaseLineRightCharacter(fConvertedText[I - 1]) = True then
      begin
        fConvertedText[I] := A_RRIKar1;
      end
      else
        fConvertedText[I] := A_RRIKar2;
    end
    else
      fConvertedText[I] := A_RRIKar2;
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
  Temp, HexStr: string;
  Idx, J: Integer;
  Code: Integer;
begin
  Temp := S;
  Idx := 1;
  while Idx <= Length(Temp) do
  begin
    if (Idx < Length(Temp)) and (Temp[Idx] = '#') and (Temp[Idx + 1] = '$') then
    begin
      HexStr := '';
      J := Idx + 2;
      while (J <= Length(Temp)) and (CharInSet(Temp[J], ['0'..'9', 'A'..'F', 'a'..'f'])) do
      begin
        HexStr := HexStr + Temp[J];
        Inc(J);
        if Length(HexStr) = 4 then Break;
      end;

      if HexStr <> '' then
      begin
        try
          Code := StrToInt('$' + HexStr);
          Delete(Temp, Idx, Length(HexStr) + 2);
          Insert(Char(Code), Temp, Idx);
        except
        end;
      end;
      Inc(Idx);
    end
    else
      Inc(Idx);
  end;
  Result := Temp;
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

{ =============================================================================== }

procedure ResetAnsiToDefaults;
var
  Rec: TAnsiVarRec;
  Resolved: string;
begin
  for Rec in AnsiRegistry do
  begin
    Resolved := ProcessHexAndUnicode(Rec.DefaultVal);
    if Rec.VarType = avChar then
      PChar(Rec.Ptr)^ := Resolved[1]
    else
      PString(Rec.Ptr)^ := Resolved;
  end;

  SetLength(CustomFullForms, 0);
  SetLength(CustomPreReplacements, 0);
  SetLength(CustomPostReplacements, 0);
end;

{ =============================================================================== }

procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);
var
  JSON: TJSONObject;
  ConstantsRoot, CategoryObj: TJSONObject;
  FullForms, PreRep, PostRep: TJSONArray;
  I, J: Integer;
  Lines: TStringList;
  ConstName, ConstValue: string;
  ConstItemVal: TJSONValue;
  Rec: TAnsiVarRec;
  IsNested: Boolean;
  KnownConstants: TDictionary<string, Boolean>;
  TempList: TList<TReplacementPair>;
  Pair: TReplacementPair;
  KeyStr, ValueStr: string;
begin
  ResetAnsiToDefaults;

  if not FileExists(Path) then
  begin
    if Assigned(ErrorLog) then
      ErrorLog.Add('Error: JSON file not found at: ' + Path);
    Exit;
  end;

  JSON := nil;
  Lines := TStringList.Create;
  KnownConstants := TDictionary<string, Boolean>.Create;
  try
    try
      Lines.LoadFromFile(Path, TEncoding.UTF8);
      JSON := TJSONObject.ParseJSONValue(Lines.Text) as TJSONObject;
    except
      on E: Exception do
      begin
        if Assigned(ErrorLog) then
          ErrorLog.Add('Critical: Invalid JSON Syntax. Message: ' + E.Message);
        Exit;
      end;
    end;

    if JSON = nil then
    begin
      if Assigned(ErrorLog) then
        ErrorLog.Add('Critical: Failed to parse JSON file.');
      Exit;
    end;

    for Rec in AnsiRegistry do
      if Rec.BengaliChar <> '' then
        KnownConstants.AddOrSetValue(Rec.BengaliChar, True);

    if JSON.TryGetValue<TJSONObject>('Constants', ConstantsRoot) then
    begin
      IsNested := (ConstantsRoot.Count > 0) and (ConstantsRoot.Pairs[0].JsonValue is TJSONObject);

      if IsNested then
      begin
        for I := 0 to ConstantsRoot.Count - 1 do
        begin
          if not (ConstantsRoot.Pairs[I].JsonValue is TJSONObject) then Continue;
          CategoryObj := TJSONObject(ConstantsRoot.Pairs[I].JsonValue);
          for J := 0 to CategoryObj.Count - 1 do
          begin
            try
              ConstName := CategoryObj.Pairs[J].JsonString.Value;
              ConstItemVal := CategoryObj.Pairs[J].JsonValue;
              if ConstItemVal is TJSONObject then
                ConstValue := ProcessHexAndUnicode(TJSONObject(ConstItemVal).GetValue('Value').Value)
              else
                ConstValue := ProcessHexAndUnicode(ConstItemVal.Value);
              if ConstValue = '' then Continue;

              if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
              begin
                if Rec.VarType = avChar then
                  PChar(Rec.Ptr)^ := ConstValue[1]
                else
                  PString(Rec.Ptr)^ := ConstValue;
              end;
            except
              on E: Exception do
              begin
                if Assigned(ErrorLog) then
                  ErrorLog.Add('Error in constant [' + ConstName + ']: ' + E.Message);
              end;
            end;
          end;
        end;
      end
      else
      begin
        for I := 0 to ConstantsRoot.Count - 1 do
        begin
          try
            ConstName := ConstantsRoot.Pairs[I].JsonString.Value;
            ConstValue := ProcessHexAndUnicode(ConstantsRoot.Pairs[I].JsonValue.Value);
            if ConstValue = '' then Continue;

            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              if Rec.VarType = avChar then
                PChar(Rec.Ptr)^ := ConstValue[1]
              else
                PString(Rec.Ptr)^ := ConstValue;
            end;
          except
            on E: Exception do
            begin
              if Assigned(ErrorLog) then
                ErrorLog.Add('Error in constant [' + ConstName + ']: ' + E.Message);
            end;
          end;
        end;
      end;
    end;

    if JSON.TryGetValue<TJSONArray>('FullFormReplacements', FullForms) then
    begin
      TempList := TList<TReplacementPair>.Create;
      try
        for I := 0 to FullForms.Count - 1 do
        begin
          try
            KeyStr := ProcessHexAndUnicode((FullForms.Items[I] as TJSONObject).GetValue('Key').Value);
            ValueStr := ProcessHexAndUnicode((FullForms.Items[I] as TJSONObject).GetValue('Value').Value);

            if KnownConstants.ContainsKey(KeyStr) then
              Continue;

            Pair.Key := KeyStr;
            Pair.Value := ValueStr;
            TempList.Add(Pair);
          except
            on E: Exception do
            begin
              if Assigned(ErrorLog) then
                ErrorLog.Add('Error in FullFormReplacements [' + IntToStr(I) + ']: ' + E.Message);
            end;
          end;
        end;

        SetLength(CustomFullForms, TempList.Count);
        for I := 0 to TempList.Count - 1 do
          CustomFullForms[I] := TempList[I];
      finally
        TempList.Free;
      end;
    end;

    if JSON.TryGetValue<TJSONArray>('PreReplacements', PreRep) then
    begin
      SetLength(CustomPreReplacements, PreRep.Count);
      for I := 0 to PreRep.Count - 1 do
      begin
        try
          CustomPreReplacements[I].Key := (PreRep.Items[I] as TJSONObject).GetValue('Key').Value;
          CustomPreReplacements[I].Value := (PreRep.Items[I] as TJSONObject).GetValue('Value').Value;
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in PreReplacements [' + IntToStr(I) + ']: ' + E.Message);
          end;
        end;
      end;
    end;

    if JSON.TryGetValue<TJSONArray>('PostReplacements', PostRep) then
    begin
      SetLength(CustomPostReplacements, PostRep.Count);
      for I := 0 to PostRep.Count - 1 do
      begin
        try
          CustomPostReplacements[I].Key := (PostRep.Items[I] as TJSONObject).GetValue('Key').Value;
          CustomPostReplacements[I].Value := (PostRep.Items[I] as TJSONObject).GetValue('Value').Value;
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in PostReplacements [' + IntToStr(I) + ']: ' + E.Message);
          end;
        end;
      end;
    end;
  finally
    KnownConstants.Free;
    JSON.Free;
    Lines.Free;
  end;
end;

{ =============================================================================== }

function GetDefaultFullFormsJSONArr: TJSONArray;
var
  Arr: TJSONArray;
  Item: TJSONObject;
begin
  Arr := TJSONArray.Create;
  Item := TJSONObject.Create;
  Item.AddPair('Key', SmartEscape('ক্ব'));
  Item.AddPair('Value', SmartEscape('K¡'));
  Item.AddPair('Comment', 'ক্ব');
  
  Result := Arr;
end;
{ =============================================================================== }

procedure ExportAnsiMapping(const Path: string);
var
  Root, CatObj, CategoryObj, ItemObj: TJSONObject;
  ConstantsRoot: TJSONObject;
  FFArr, PreArr, PostArr: TJSONArray;
  Lines: TStringList;
  I: Integer;
  Val: string;
  Rec: TAnsiVarRec;
begin
  Lines := TStringList.Create;
  Root := TJSONObject.Create;
  try
    ConstantsRoot := TJSONObject.Create;
    Root.AddPair('Constants', ConstantsRoot);

    for Rec in AnsiRegistry do
    begin
      if not ConstantsRoot.TryGetValue<TJSONObject>(Rec.Category, CategoryObj) then
      begin
        CategoryObj := TJSONObject.Create;
        ConstantsRoot.AddPair(Rec.Category, CategoryObj);
      end;

      if Rec.VarType = avChar then
        Val := string(PChar(Rec.Ptr)^)
      else
        Val := PString(Rec.Ptr)^;

      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('Value', SmartEscape(Val));
      ItemObj.AddPair('Comment', Rec.BengaliChar);
      CategoryObj.AddPair(Rec.Name, ItemObj);
    end;

    if Length(CustomFullForms) > 0 then
    begin
      FFArr := TJSONArray.Create;
      for I := 0 to High(CustomFullForms) do
      begin
        ItemObj := TJSONObject.Create;
        ItemObj.AddPair('Key', SmartEscape(CustomFullForms[I].Key));
        ItemObj.AddPair('Value', SmartEscape(CustomFullForms[I].Value));
        ItemObj.AddPair('Comment', CustomFullForms[I].Key);
        FFArr.Add(ItemObj);
      end;
    end
    else
      FFArr := GetDefaultFullFormsJSONArr;
    Root.AddPair('FullFormReplacements', FFArr);

    PreArr := TJSONArray.Create;
    for I := 0 to High(CustomPreReplacements) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('Key', SmartEscape(CustomPreReplacements[I].Key));
      ItemObj.AddPair('Value', SmartEscape(CustomPreReplacements[I].Value));
      ItemObj.AddPair('Comment', CustomPreReplacements[I].Key);
      PreArr.Add(ItemObj);
    end;
    Root.AddPair('PreReplacements', PreArr);

    PostArr := TJSONArray.Create;
    for I := 0 to High(CustomPostReplacements) do
    begin
      ItemObj := TJSONObject.Create;
      ItemObj.AddPair('Key', SmartEscape(CustomPostReplacements[I].Key));
      ItemObj.AddPair('Value', SmartEscape(CustomPostReplacements[I].Value));
      ItemObj.AddPair('Comment', CustomPostReplacements[I].Key);
      PostArr.Add(ItemObj);
    end;
    Root.AddPair('PostReplacements', PostArr);

    Lines.Text := Root.Format(2);
    Lines.SaveToFile(Path, TEncoding.UTF8);
  finally
    Root.Free;
    Lines.Free;
  end;
end;

{ =============================================================================== }

function ValidateAnsiMappingFile(const Path: string; out ErrorMessage: string): Boolean;
const
  REPL_SECTIONS: array[0..2] of string = (
    'FullFormReplacements', 'PreReplacements', 'PostReplacements');
var
  Lines: TStringList;
  Root, Section, KeyVal, ValueVal: TJSONValue;
  Arr: TJSONArray;
  I, Idx: Integer;
  Item: TJSONObject;
begin
  Result := False;
  ErrorMessage := '';

  if not FileExists(Path) then
  begin
    ErrorMessage := 'File does not exist.';
    Exit;
  end;

  Lines := TStringList.Create;
  Root := nil;
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

    try
      Root := TJSONObject.ParseJSONValue(Lines.Text);
    except
      on E: Exception do
      begin
        ErrorMessage := 'Invalid JSON syntax: ' + E.Message;
        Exit;
      end;
    end;

    if (Root = nil) or not (Root is TJSONObject) then
    begin
      ErrorMessage := 'Invalid JSON root: expected an object.';
      Exit;
    end;

    Section := TJSONObject(Root).GetValue('Constants');
    if Section = nil then
    begin
      ErrorMessage := 'Missing section: Constants';
      Exit;
    end;
    if not (Section is TJSONObject) then
    begin
      ErrorMessage := 'Invalid section: Constants must be an object.';
      Exit;
    end;

    for I := 0 to High(REPL_SECTIONS) do
    begin
      Section := TJSONObject(Root).GetValue(REPL_SECTIONS[I]);
      if Section = nil then
      begin
        ErrorMessage := 'Missing section: ' + REPL_SECTIONS[I];
        Exit;
      end;
      if not (Section is TJSONArray) then
      begin
        ErrorMessage := 'Invalid section: ' + REPL_SECTIONS[I] + ' must be an array.';
        Exit;
      end;

      Arr := TJSONArray(Section);
      for Idx := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[Idx] is TJSONObject) then
        begin
          ErrorMessage := 'Missing Key/Value in ' + REPL_SECTIONS[I] + ' at index ' + (Idx + 1).ToString;
          Exit;
        end;
        Item := TJSONObject(Arr.Items[Idx]);
        KeyVal := Item.GetValue('Key');
        ValueVal := Item.GetValue('Value');
        if (KeyVal = nil) or not (KeyVal is TJSONString) or
           TJSONString(KeyVal).Value.IsEmpty or
           (ValueVal = nil) or not (ValueVal is TJSONString) or
           TJSONString(ValueVal).Value.IsEmpty then
        begin
          ErrorMessage := 'Missing Key/Value in ' + REPL_SECTIONS[I] + ' at index ' + (Idx + 1).ToString;
          Exit;
        end;
      end;
    end;

    Result := True;
  finally
    Root.Free;
    Lines.Free;
  end;
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


initialization
  InitializeAnsiRegistry;

finalization
  AnsiRegistry.Free;
  AnsiRegistryMap.Free;

end.