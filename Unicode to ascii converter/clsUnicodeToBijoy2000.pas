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
  TVowelRuleMapping = record
    Consonants: string;
    Value: string;
    Alt: string;
    ToggleOnBackspace: Boolean;
    MatchMode: Integer;   // 0 = Full Cluster (default), 1 = Last Char only
    ProcessPhase: string; // 'pre' or 'post' (empty = main, existing behavior)
  end;

  TVowelRule = record
    KarChar: string;
    DefaultVal: string;
    Toggle: string;
    ToggleOnBackspace: Boolean;
    Mappings: TArray<TVowelRuleMapping>;
  end;

  TClusterMatchInfo = record
    MatchedCluster: string;
    BestMapping: TVowelRuleMapping;
    BestMatchLen: Integer;
    ContextEnd: Integer;
    IsZfola: Boolean;
  end;

type
  // Fired by Convert at each pipeline stage so a caller can show progress.
  // Percent is 0..100; Stage is a short ASCII identifier of the current pass.
  TConverterProgress = procedure(Sender: TObject; Percent: Integer; const Stage: string) of object;

type
  TUnicodeToBijoy2000 = class
    private
      fUniText:       string;
      fConvertedText: string;
      fToggleStates:  TDictionary<string, Boolean>;
      fLastUniText:   string;
      FOnProgress:    TConverterProgress;
      procedure ReportProgress(Percent: Integer; const Stage: string);
      procedure ReArrangeKars;
      procedure ReArrangeReph;
      procedure ReplaceFullForms;
      procedure ApplyKarInclusiveFullForms;
      procedure ApplyVowelKars;
      procedure ReplaceKarsVowels;
      procedure ConvertRFola_ZFola_Hasanta;
      procedure FirstHalfForms;
      procedure SecondHalfForms;
      procedure Consonants;
      procedure FinalTouch;
      procedure DeNormalize;
      procedure ReplaceNumbers;

      // Utility Functions
      function BaseLineRightCharacter(const wC: string): Boolean;
      function IsVowel(C: Char): Boolean;
      function GetToggleState(const Context, Key: string; OccurrenceIndex: Integer): Boolean;
      procedure SetToggleState(const Context, Key: string; OccurrenceIndex: Integer; Value: Boolean);
      function RuleHasAnyToggle(const Rule: TVowelRule): Boolean;
      function FindMappingToggle(const Rule: TVowelRule; const ConsonantPart: string; out MappingToggleOnBackspace: Boolean;
        out MatchedCluster: string): Boolean;
      function FindBestClusterMatch(const Text: string; KarPos: Integer; const Rule: TVowelRule): TClusterMatchInfo;
      procedure ApplyRuleForKar(const KarChar: string; const Phase: string = '');
    public
      destructor Destroy; override;
      function Convert(const UniText: string): string;
      // Optional progress callback fired by Convert between pipeline stages.
      property OnProgress: TConverterProgress read FOnProgress write FOnProgress;
  end;

  TReplacementPair = record
    Key: string;
    Value: string;
    Comment: string;
  end;

  TAnsiVarType = (avChar, avString);

  TAnsiVarRec = record
    Name: string;
    Category: string;
    VarType: TAnsiVarType;
    Ptr: Pointer;
    DefaultVal: string;
    BengaliChar: string;
    Comment: string;
  end;

  TRfolaRule = record
    Consonants: string;
    Value: string;
    HalfValue: string;
    ReplaceLen: Integer;
    ContextGroup: string;
    ContextReplaceLen: Integer;
    ContextValue: string;
    RawValue: string;
    RawHalfValue: string;
    RawContextValue: string;
    Comment: string;
  end;

  TKarCorrection = record
    RawCharStr: string;
    CharStr: string;
    RawFromKar: string;
    FromKar: string;
    RawToKar: string;
    ToKar: string;
    Comment: string;
  end;

  TGroupKarCorrection = record
    Group: string;
    From: string;
    To_: string;
  end;

var
  CustomFullForms:          TArray<TReplacementPair>;
  CustomPreReplacements:    TArray<TReplacementPair>;
  CustomPostReplacements:   TArray<TReplacementPair>;
  AnsiVersion:              string = 'Default';
  AnsiMappingDir:           string = '';
  AnsiRegistry:             TList<TAnsiVarRec>;
  AnsiRegistryMap:          TDictionary<string, TAnsiVarRec>;
  ActiveReplacements:       TArray<TReplacementPair>;
  KarInclusiveReplacements: TArray<TReplacementPair>;
  AnsiOverrides:            TDictionary<string, string>;
  VowelRules:               TArray<TVowelRule>;
  ConsonantGroupMap:        TDictionary<string, TArray<string>>;
  AnsiGroupMap:             TDictionary<string, TArray<string>>;
  AnsiGroupRawMap:          TDictionary<string, TArray<string>>;
  RfolaRules:               TArray<TRfolaRule>;
  KarCorrections:           TArray<TKarCorrection>;
  GroupKarCorrections:      TArray<TGroupKarCorrection>;
  ConsonantGroupRawMap:     TDictionary<string, TArray<string>>;

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
  A_A:       Char   = #$41;
  A_AA:      string = #$41#$76;
  A_AAKar:   Char   = #$76;
  A_I:       Char   = #$42;
  A_IKar:    Char   = #$77;
  A_II:      Char   = #$43;
  A_IIKar:   Char   = #$78;
  A_U:       Char   = #$44;
  A_UKar2:   Char   = #$79;
  A_UKar1:   Char   = #$7A;
  A_UKar3:   Char   = #$2013;
  A_UKar4:   Char   = #$201C;
  A_UU:      Char   = #$45;
  A_UUKar2:  Char   = #$7E;
  A_UUKar1:  Char   = #$201A;
  A_UUKar3:  Char   = #$192;
  A_RRI:     Char   = #$46;
  A_RRIKar1: Char   = #$201E;
  A_RRIKar2: Char   = #$2026;
  A_E:       Char   = #$47;
  A_EKar1:   Char   = #$2020;
  A_EKar2:   Char   = #$2021;
  A_OI:      Char   = #$48;
  A_OIKar1:  Char   = #$2C6;
  A_OIKar2:  Char   = #$2030;
  A_O:       Char   = #$49;
  A_OU:      Char   = #$4A;
  A_OUKar:   Char   = #$160;

  { Symbols }
  A_Taka:             string = #$24;
  A_Dari:             string = #$7C;
  A_DoubleDanda:      string = #$5C;
  A_Hasanta:          string = #$26;
  A_StartDoubleQuote: string = #$D2;
  A_EndDoubleQuote:   string = #$D3;

  A_StartSingleQuote: string = #$D4;
  A_EndSingleQuote:   string = #$D5;

  { Consonants }
  A_K:        string = #$4B;
  A_Kh:       string = #$4C;
  A_G:        string = #$4D;
  A_Gh:       string = #$4E;
  A_NGA:      string = #$4F;
  A_C:        string = #$50;
  A_Ch:       string = #$51;
  A_J:        string = #$52;
  A_Jh:       string = #$53;
  A_NYA:      string = #$54;
  A_Tt:       string = #$55;
  A_Tth:      string = #$56;
  A_Dd:       string = #$57;
  A_Ddh:      string = #$58;
  A_Nn:       string = #$59;
  A_T:        string = #$5A;
  A_Th:       string = #$5F;
  A_D:        string = #$60;
  A_Dh:       string = #$61;
  A_N:        string = #$62;
  A_P:        string = #$63;
  A_Ph:       string = #$64;
  A_B:        string = #$65;
  A_Bh:       string = #$66;
  A_M:        string = #$67;
  A_Z:        string = #$68;
  A_R:        string = #$69;
  A_L:        string = #$6A;
  A_Sh:       string = #$6B;
  A_SS:       string = #$6C;
  A_S:        string = #$6D;
  A_H:        string = #$6E;
  A_RR:       string = #$6F;
  A_RRH:      string = #$70;
  A_Y:        string = #$71;
  A_Khandata: string = #$72;
  A_Anushar:  string = #$73;
  A_Bisharga: string = #$74;
  A_Chandra:  string = #$75;

  { Full Forms }
  A_K_K:      string = #$B0;
  A_K_Tt:     string = #$B1;
  A_K_Ss_M:   string = #$B2;
  A_K_T:      string = #$B3;
  A_K_M:      string = #$B4;
  A_K_R:      string = #$B5;
  A_K_Ss:     string = #$B6;
  A_K_S:      string = #$B7;
  A_G_Ukar:   string = #$B8;
  A_G_G:      string = #$B9;
  A_G_D:      string = #$BA;
  A_G_Dh:     string = #$BB;
  A_NGA_K:    string = #$BC;
  A_NGA_G:    string = #$BD;
  A_J_J:      string = #$BE;
  A_J_Jh:     string = #$C0;
  A_J_NYA:    string = #$C1;
  A_NYA_C:    string = #$C2;
  A_NYA_CH:   string = #$C3;
  A_NYA_J:    string = #$C4;
  A_NYA_Jh:   string = #$C5;
  A_Tt_Tt:    string = #$C6;
  A_Dd_Dd:    string = #$C7;
  A_Nn_Tt:    string = #$C8;
  A_Nn_Tth:   string = #$C9;
  A_NN_Dd:    string = #$CA;
  A_T_T:      string = #$CB;
  A_T_Th:     string = #$CC;
  A_T_M:      string = #$CD;
  A_T_R:      string = #$CE;
  A_D_D:      string = #$CF;
  A_D_Dh:     string = #$D7;
  A_D_B:      string = #$D8;
  A_D_M:      string = #$D9;
  A_N_Tth:    string = #$DA;
  A_N_Dd:     string = #$DB;
  A_N_Dh:     string = #$DC;
  A_N_S:      string = #$DD;
  A_P_Tt:     string = #$DE;
  A_P_T:      string = #$DF;
  A_P_P:      string = #$E0;
  A_P_S:      string = #$E1;
  A_B_J:      string = #$E2;
  A_B_D:      string = #$E3;
  A_B_Dh:     string = #$E4;
  A_Bh_R:     string = #$E5;
  A_M_N:      string = #$E6;
  A_M_Ph:     string = #$E7;
  A_L_K:      string = #$E9;
  A_L_G:      string = #$EA;
  A_L_Tt:     string = #$EB;
  A_L_Dd:     string = #$EC;
  A_L_P:      string = #$ED;
  A_L_Ph:     string = #$EE;
  A_Sh_UKar:  string = #$EF;
  A_Sh_C:     string = #$F0;
  A_Sh_Ch:    string = #$F1;
  A_Ss_Nn:    string = #$F2;
  A_Ss_Tt:    string = #$F3;
  A_Ss_Tth:   string = #$F4;
  A_Ss_Ph:    string = #$F5;
  A_S_Kh:     string = #$F6;
  A_S_Tt:     string = #$F7;
  A_S_N:      string = #$F8;
  A_S_Ph:     string = #$F9;
  A_H_UKar:   string = #$FB;
  A_H_RRIKar: string = #$FC;
  A_H_N:      string = #$FD;
  A_H_M:      string = #$FE;
  A_Rr_G:     string = #$FF;

  { First Half forms }
  A_Reph:   Char = #$A9;
  A_M_1H:   Char = #$A4;
  A_Ss_1H:  Char = #$AE;
  A_S_1H_1: Char = #$AF;
  A_N_1H_1: Char = #$161;
  A_S_1H_2: Char = #$2C9; // -----------Not used
  A_D_1H_1: Char = #$2DC;
  A_C_1H:   Char = #$201D;
  A_NGA_1H: Char = #$2022;
  A_N_1H_2: Char = #$203A;
  A_D_1H_2: Char = #$2122;

  { Second Half forms }
  A_B_2H_1:    Char = #$5E; //
  A_B_2H_2:    Char = #$A1; //
  A_BH_2H:     Char = #$A2; //
  A_BH_R_2H:   Char = #$A3; //
  A_M_2H_1:    Char = #$A5; //
  A_B_2H_3:    Char = #$A6; //
  A_M_2H_2:    Char = #$A7; //
  A_ZFola:     Char = #$A8; //
  A_RFola_1:   Char = #$AA; //
  A_RFola_2:   Char = #$AB; //
  A_L_2H_1:    Char = #$AC; //
  A_L_2H_2:    Char = #$AD; // <--- Not used
  A_T_R_2H:    Char = #$BF; //
  A_RFola_3:   Char = #$D6; //
  A_Nn_2H_1:   Char = #$E8;
  A_K_R_2H:    Char = #$152; //
  A_Nn_2H_2:   Char = #$153;
  A_B_2H_4:    Char = #$178;  //
  A_T_2H:      Char = #$2014; //
  A_T_UKar_2H: Char = #$2018; //
  A_Th_2H:     Char = #$2019; //
  A_K_2H:      Char = #$2039; //
  A_L_2H_3:    Char = #$2212; //

  { ============================================================================= }
  { Registry Initialization }
  { ============================================================================= }

function CountOccurrences(const SubStr, S: string): Integer;
var
  PosIdx: Integer;
begin
  Result := 0;
  if (SubStr = '') or (S = '') then
    Exit;
  PosIdx := Pos(SubStr, S);
  while PosIdx > 0 do
  begin
    Inc(Result);
    PosIdx := PosEx(SubStr, S, PosIdx + Length(SubStr));
  end;
end;

// DEPRECATED: Use FindBestClusterMatch instead. This function is kept only for
// backward compatibility. It returns a single character which causes toggle key
// collisions between different clusters ending in the same letter.
function ResolveContextChar(const Text: string; KarPos: Integer): string;
var
  PrecedingChar: string;
  ContextEnd:    Integer;
  IsZfola:       Boolean;
begin
  if KarPos - 1 < 1 then
    Exit('');
  PrecedingChar := Text[KarPos - 1];
  ContextEnd := KarPos - 1;
  IsZfola := (PrecedingChar = b_z) and (KarPos - 2 >= 1) and (Text[KarPos - 2] = b_Hasanta);
  if IsZfola then
  begin
    ContextEnd := KarPos - 3;
    if ContextEnd >= 1 then
      PrecedingChar := Text[ContextEnd]
    else
      PrecedingChar := '';
  end;
  Result := PrecedingChar;
end;

procedure InitializeAnsiRegistry;

  procedure RegVar(const AName, ACategory: string; AVarType: TAnsiVarType; APtr: Pointer; const ADefaultVal, ABengali: string);
  var
    Rec: TAnsiVarRec;
  begin
    Rec.Name := AName;
    Rec.Category := ACategory;
    Rec.VarType := AVarType;
    Rec.Ptr := APtr;
    Rec.DefaultVal := ADefaultVal;
    Rec.BengaliChar := ABengali;
    Rec.Comment := ABengali;
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
  RegVar('A_RRIKar1', 'VowelsAndKars', avChar, @A_RRIKar1, '#$201E', 'ৃ (ঋ-কার ১ - সাধারণ)');
  RegVar('A_RRIKar2', 'VowelsAndKars', avChar, @A_RRIKar2, '#$2026', 'ৃ (ঋ-কার ২ - ঝুলন্ত)');
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
  wT: Char;
  SB: TStringBuilder;

  function PickB2H(const wC: Char): Char;
  begin
    if (wC = b_s) or (wC = b_ss) or (wC = b_m) or (wC = b_n) or (wC = b_d) or (wC = A_M_1H) or (wC = A_Ss_1H) or (wC = A_S_1H_1) or (wC = A_N_1H_1) or
        (wC = A_D_1H_2) then
      Result := A_B_2H_1
    else if (wC = b_dh) or (wC = b_b) or (wC = b_h) then
      Result := A_B_2H_4
    else if (wC = b_sh) or (wC = b_g) or (wC = b_p) then
      Result := A_B_2H_3
    else
      Result := A_B_2H_2;
  end;

  function PickM2H(const wC: Char): Char;
  begin
    if (wC = A_M_1H) or (wC = A_Ss_1H) or (wC = A_C_1H) or (wC = A_S_1H_1) or (wC = A_D_1H_2) or (wC = A_N_1H_1) or (wC = A_N_1H_2) then
      Result := A_M_2H_2
    else if wC = A_NGA_1H then
      Result := A_M[1]
    else
      Result := A_M_2H_1;
  end;

  function PickL2H(const wC: Char): Char;
  begin
    if BaseLineRightCharacter(string(wC)) then
      Result := A_L_2H_3
    else
      Result := A_L_2H_1;
  end;

  // Replace every (hasanta + C) pair in one left-to-right pass, reading the
  // character before the hasanta from the output built so far (the in-place
  // version read the same evolved prefix). The old repeat/Pos + WideStuffString
  // loops restarted the scan from the top and rebuilt the whole string for
  // every match - O(N^2) on conjunct-heavy text.

  procedure ScanB2H;
  begin
    SB := TStringBuilder.Create(Length(fConvertedText) + 8);
    try
      I := 1;
      while I <= Length(fConvertedText) do
      begin
        if (fConvertedText[I] = b_Hasanta) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_b) then
        begin
          if SB.Length >= 1 then
            wT := SB.Chars[SB.Length - 1]
          else
            wT := #0;
          SB.Append(PickB2H(wT));
          Inc(I, 2);
        end
        else
        begin
          SB.Append(fConvertedText[I]);
          Inc(I);
        end;
      end;
      fConvertedText := SB.ToString;
    finally
      SB.Free;
    end;
  end;

  procedure ScanM2H;
  begin
    SB := TStringBuilder.Create(Length(fConvertedText) + 8);
    try
      I := 1;
      while I <= Length(fConvertedText) do
      begin
        if (fConvertedText[I] = b_Hasanta) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_m) then
        begin
          if SB.Length >= 1 then
            wT := SB.Chars[SB.Length - 1]
          else
            wT := #0;
          SB.Append(PickM2H(wT));
          Inc(I, 2);
        end
        else
        begin
          SB.Append(fConvertedText[I]);
          Inc(I);
        end;
      end;
      fConvertedText := SB.ToString;
    finally
      SB.Free;
    end;
  end;

  procedure ScanL2H;
  begin
    SB := TStringBuilder.Create(Length(fConvertedText) + 8);
    try
      I := 1;
      while I <= Length(fConvertedText) do
      begin
        if (fConvertedText[I] = b_Hasanta) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_L) then
        begin
          if SB.Length >= 1 then
            wT := SB.Chars[SB.Length - 1]
          else
            wT := #0;
          SB.Append(PickL2H(wT));
          Inc(I, 2);
        end
        else
        begin
          SB.Append(fConvertedText[I]);
          Inc(I);
        end;
      end;
      fConvertedText := SB.ToString;
    finally
      SB.Free;
    end;
  end;

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
  ScanB2H;

  { A_M_2H_1  and  A_M_2H_2 }
  ScanM2H;

  { A_L_2H_1  and  A_L_2H_3 }
  ScanL2H;

  { A_Nn_2H_1 }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_Nn, A_Nn_2H_1);
  { A_Nn_2H_2 }
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_n, A_Nn_2H_2);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.FirstHalfForms;
var
  I:  Integer;
  SB: TStringBuilder;
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

  // Replace every (d + hasanta) pair in one left-to-right pass. The old
  // repeat/Pos loops restarted the scan from the top for every match - O(N^2)
  // on conjunct-heavy text. Replacements are 1->1 so positions never shift;
  // the look-ahead at I+2 always reads the original character.
  { A_D_1H_1  and  A_D_1H_2 }
  SB := TStringBuilder.Create(Length(fConvertedText) + 8);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if (fConvertedText[I] = b_d) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_Hasanta) then
      begin
        if (I + 2 <= Length(fConvertedText)) and (fConvertedText[I + 2] = b_g) then
          SB.Append(A_D_1H_1)
        else
          SB.Append(A_D_1H_2);
        SB.Append(b_Hasanta);
        Inc(I, 2);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;

  { Elevate first-half N-forms }
  SB := TStringBuilder.Create(Length(fConvertedText) + 8);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if (fConvertedText[I] = b_n) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_Hasanta) then
      begin
        if (I + 2 <= Length(fConvertedText)) and ((fConvertedText[I + 2] = b_t) or (fConvertedText[I + 2] = b_Th) or (fConvertedText[I + 2] = b_L) or
              (fConvertedText[I + 2] = b_b) or (fConvertedText[I + 2] = A_T_R_2H) or (fConvertedText[I + 2] = A_T_UKar_2H)) then
          SB.Append(A_N_1H_1)
        else if (I + 2 <= Length(fConvertedText)) and ((fConvertedText[I + 2] = b_m) or (fConvertedText[I + 2] = b_n)) then
          SB.Append(A_N[1])
        else
          SB.Append(A_N_1H_2);
        SB.Append(b_Hasanta);
        Inc(I, 2);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;
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

  // --- Special consonants and symbols (codepoint constants, encoding-safe) ---
  fConvertedText := ReplaceStr(fConvertedText, b_Khandatta, A_Khandata);
  fConvertedText := ReplaceStr(fConvertedText, b_Anushar, A_Anushar);
  fConvertedText := ReplaceStr(fConvertedText, b_Bisharga, A_Bisharga);
  fConvertedText := ReplaceStr(fConvertedText, b_Chandra, A_Chandra);
  fConvertedText := ReplaceStr(fConvertedText, b_Dari, A_Dari);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.FinalTouch;
var
  Len: Integer;
  I:   Integer;
  C:   Char;
  SB:  TStringBuilder; // TStringBuilder declared
begin
  fConvertedText := ReplaceStr(fConvertedText, string(b_Hasanta) + string(zwnj), string(A_Hasanta));

  Len := Length(fConvertedText);
  if Len > 0 then
  begin
    if string(b_Hasanta) <> '' then
    begin
      if (Len >= 2) and (fConvertedText[Len] = string(b_Hasanta)[1]) and (fConvertedText[Len - 1] = string(b_Hasanta)[1]) then
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
  fConvertedText := ReplaceStr(fConvertedText, string(A_UKar1) + string(A_Reph), string(A_UKar2) + string(A_Reph));

  // Reorder Reph and all variants of UU-Kar glyphs
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar1), string(A_UUKar1) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar2), string(A_UUKar2) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_Reph) + string(A_UUKar3), string(A_UUKar3) + string(A_Reph));
  fConvertedText := ReplaceStr(fConvertedText, string(A_UUKar1) + string(A_Reph), string(A_UUKar2) + string(A_Reph));

  // Dynamic Post-processing Corrections (JSON-driven)
  if Length(KarCorrections) > 0 then
    for I := 0 to high(KarCorrections) do
      fConvertedText := ReplaceStr(fConvertedText, KarCorrections[I].CharStr + KarCorrections[I].FromKar, KarCorrections[I].CharStr + KarCorrections[I].ToKar);

  // --- STRICT SANITIZATION FOR ANSI OUTPUT (Optimized with TStringBuilder) ---
  SB := TStringBuilder.Create;
  try
    for I := 1 to Length(fConvertedText) do
    begin
      C := fConvertedText[I];
      if (Ord(C) >= $0980) and (Ord(C) <= $09FF) then
        Continue;
      if ((Ord(C) >= $200B) and (Ord(C) <= $200F)) or (Ord(C) = $FEFF) then
        Continue;
      SB.Append(C); // Added directly to buffer, no copy
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free; // Memory freed
  end;

  // Applying dynamic post-processing fixes (LAST)
  for I := 0 to Length(CustomPostReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPostReplacements[I].Key, CustomPostReplacements[I].Value);
end;

procedure TUnicodeToBijoy2000.ReplaceFullForms;
var
  I: Integer;
begin
  for I := 0 to Length(ActiveReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, ActiveReplacements[I].Key, ActiveReplacements[I].Value);
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.BaseLineRightCharacter(const wC: string): Boolean;
begin
  Result := False;
  if (wC = b_kh) or (wC = b_g) or (wC = b_gh) or (wC = b_Nn) or (wC = b_Th) or (wC = b_d) or (wC = b_dh) or (wC = b_n) or (wC = b_p) or (wC = b_b) or
    (wC = b_m) or (wC = b_z) or (wC = b_r) or (wC = b_L) or (wC = b_sh) or (wC = b_ss) or (wC = b_s) or (wC = b_h) or (wC = b_y) or
  // Also support ANSI conjunct characters that end with baseline-right consonants
    (wC = string(A_K_Ss_M)) or (wC = string(A_K_M)) or (wC = string(A_K_Ss)) or (wC = string(A_K_S)) or (wC = string(A_G_G)) or (wC = string(A_G_D)) or
    (wC = string(A_G_Dh)) or (wC = string(A_NGA_G)) or (wC = string(A_T_Th)) or (wC = string(A_T_M)) or (wC = string(A_D_D)) or (wC = string(A_D_Dh)) or
    (wC = string(A_D_B)) or (wC = string(A_D_M)) or (wC = string(A_N_Tth)) or (wC = string(A_N_Dh)) or (wC = string(A_N_S)) or (wC = string(A_P_P)) or
    (wC = string(A_P_S)) or (wC = string(A_B_D)) or (wC = string(A_B_Dh)) or (wC = string(A_Bh_R)) or (wC = string(A_M_N)) or (wC = string(A_L_G)) or
    (wC = string(A_L_P)) or (wC = string(A_Ss_Nn)) or (wC = string(A_S_Kh)) or (wC = string(A_S_N)) or (wC = string(A_H_N)) or (wC = string(A_H_M)) or
    (wC = string(A_Rr_G)) then
    Result := True;

end;

{ =============================================================================== }

function TUnicodeToBijoy2000.IsVowel(C: Char): Boolean;
begin
  Result := (C = b_A) or (C = b_AA) or (C = b_I) or (C = b_II) or (C = b_U) or (C = b_UU) or (C = b_RRI) or (C = b_E) or (C = b_OI) or (C = b_O) or (C = b_OU);
end;

{ =============================================================================== }

destructor TUnicodeToBijoy2000.Destroy;
begin
  fToggleStates.Free;
  inherited;
end;

function TUnicodeToBijoy2000.GetToggleState(const Context, Key: string; OccurrenceIndex: Integer): Boolean;
var
  CombinedKey: string;
begin
  // Contextual key: Consonant + Index + KarChar (e.g. ra_1_#$09C1)
  CombinedKey := Context + '_' + IntToStr(OccurrenceIndex) + '_' + Key;
  if fToggleStates = nil then
    fToggleStates := TDictionary<string, Boolean>.Create;
  if not fToggleStates.TryGetValue(CombinedKey, Result) then
    Result := False;
end;

procedure TUnicodeToBijoy2000.SetToggleState(const Context, Key: string; OccurrenceIndex: Integer; Value: Boolean);
var
  CombinedKey: string;
begin
  CombinedKey := Context + '_' + IntToStr(OccurrenceIndex) + '_' + Key;
  if fToggleStates = nil then
    fToggleStates := TDictionary<string, Boolean>.Create;
  fToggleStates.AddOrSetValue(CombinedKey, Value);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReportProgress(Percent: Integer; const Stage: string);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Self, Percent, Stage);
end;

function TUnicodeToBijoy2000.Convert(const UniText: string): string;
const
  TotalStages = 21;
var
  I:                  Integer;
  HasTrailingHasanta: Boolean;
  Rule:               TVowelRule;
  ConsonantPart:      string;
  MapToggleBack:      Boolean;
  MatchedCluster:     string;
  StageNo:            Integer;
begin
  StageNo := 0;

  if UniText = '' then
  begin
    if fToggleStates <> nil then
      fToggleStates.Clear;
    fLastUniText := '';
    Result := '';
    Exit;
  end;

  if (Pos(' ', UniText) > 0) then
  begin
    if fToggleStates <> nil then
      fToggleStates.Clear;
  end;

  fUniText := UniText;
  fConvertedText := fUniText;

  // 1. Dynamic pre-placement fixes - runs at the very beginning on raw Unicode input
  for I := 0 to Length(CustomPreReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPreReplacements[I].Key, CustomPreReplacements[I].Value);
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'pre-replacements');

  for Rule in VowelRules do
  begin
    if not RuleHasAnyToggle(Rule) then
      Continue;

    if fLastUniText <> '' then
    begin
      ConsonantPart := UniText;
      if (Length(fLastUniText) = Length(ConsonantPart) + Length(Rule.KarChar)) and (Copy(fLastUniText, 1, Length(ConsonantPart)) = ConsonantPart) and
        (Copy(fLastUniText, Length(ConsonantPart) + 1, Length(Rule.KarChar)) = Rule.KarChar) then
      begin
        FindMappingToggle(Rule, ConsonantPart, MapToggleBack, MatchedCluster);
        if MapToggleBack then
        begin
          SetToggleState(MatchedCluster, Rule.KarChar, CountOccurrences(Rule.KarChar, fLastUniText),
            not GetToggleState(MatchedCluster, Rule.KarChar, CountOccurrences(Rule.KarChar, fLastUniText)));
        end;
      end;
    end;
  end;

  fLastUniText := UniText;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'toggle-state');

  // 2. Resolve kar-inclusive full forms BEFORE the vowel-rule pass
  ApplyKarInclusiveFullForms;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'kar-inclusive');

  // === Phase A: Pre-phase vowel rule pass (raw Unicode text) ===
  ApplyRuleForKar(b_Ukar, 'pre');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'u-kar-pre');
  ApplyRuleForKar(b_UUKar, 'pre');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'uu-kar-pre');
  ApplyRuleForKar(b_Rrikar, 'pre');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rri-kar-pre');

  // Clean start
  DeNormalize;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'denormalize');
  ReplaceNumbers;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'numbers');

  // 3. Rearrange Vowels and Reph
  ReArrangeKars;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rearrange-kars');
  ReArrangeReph;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rearrange-reph');

  // 4. Apply the U/UU/RRI main pass
  ApplyVowelKars;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'vowel-kars');

  // 5. Process remaining Conjuncts and Full Forms
  ReplaceFullForms;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'full-forms');

  // 6. Process remaining Vowels
  ReplaceKarsVowels;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'kar-vowels');

  // 7. Apply Glyphs, Halfs, and Consonants
  ConvertRFola_ZFola_Hasanta;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rfola-zfola');

  { ==========================================================
    (Flicker-Free Half Form Protection)
    ========================================================== }
  HasTrailingHasanta := False;
  if (Length(fConvertedText) > 0) and (fConvertedText[Length(fConvertedText)] = b_Hasanta) then
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
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'first-half-forms');
  SecondHalfForms;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'second-half-forms');
  Consonants;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'consonants');
  // === Post-phase vowel rule pass ===
  ApplyRuleForKar(b_Ukar, 'post');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'u-kar-post');
  ApplyRuleForKar(b_UUKar, 'post');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'uu-kar-post');
  ApplyRuleForKar(b_Rrikar, 'post');
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'rri-kar-post');
  FinalTouch;
  Inc(StageNo);
  ReportProgress((StageNo * 100) div TotalStages, 'final-touch');

  Result := fConvertedText;
end;

{ =============================================================================== }

function CharInGroup(const Ch: string; const GroupName: string): Boolean;
var
  Arr: TArray<string>;
  S:   string;
begin
  Result := False;
  if GroupName = '' then
    Exit;
  if GroupName = 'default' then
    Exit(True);
  if ConsonantGroupMap <> nil then
  begin
    if ConsonantGroupMap.TryGetValue(GroupName, Arr) then
      for S in Arr do
        if S = Ch then
          Exit(True);
  end;
  if AnsiGroupMap <> nil then
  begin
    if AnsiGroupMap.TryGetValue(GroupName, Arr) then
      for S in Arr do
        if S = Ch then
          Exit(True);
  end;
end;

procedure TUnicodeToBijoy2000.ConvertRFola_ZFola_Hasanta;
var
  I:          Integer;
  PrevC:      Char;
  IsHalfForm: Boolean;
  Rule:       TRfolaRule;
  SB:         TStringBuilder;
  Val:        string;
  Take:       Integer;
  C2, C3:     Char;

  // Resolve which glyph replaces this r-fola and how far it reaches back into
  // the output (0 = only hasanta+ra, 1 = also the consonant before them).
  // Mirrors the rule/fallback logic of the in-place version exactly.
  procedure MatchRfola;
  var
    Matched:  Boolean;
    LoopRule: TRfolaRule;
  begin
    Matched := False;
    if Length(RfolaRules) > 0 then
    begin
      // The loop variable must be local to this nested routine (Delphi
      // requires for-loop control variables to be simple locals); Rule is
      // copied out so the matched rule stays visible to the caller.
      for LoopRule in RfolaRules do
      begin
        Rule := LoopRule;
        // Check context group first (e.g., t preceded by K/t)
        if (Rule.ContextGroup <> '') and CharInGroup(string(PrevC), Rule.Consonants) then
        begin
          // Check if the character before PrevC's Hasanta is in ContextGroup
          if IsHalfForm and (C3 <> #0) then
          begin
            if CharInGroup(string(C3), Rule.ContextGroup) then
            begin
              Val := Rule.ContextValue;
              Take := 0; // ContextReplaceLen is 2 in the mappings: hasanta + ra
              Matched := True;
              break;
            end;
          end;
        end;
        // Check main consonant group
        if CharInGroup(string(PrevC), Rule.Consonants) then
        begin
          if Rule.ReplaceLen > 2 then
          begin
            // Dynamic replace length (3, 4, 5, etc.) - reaches one char back
            Take := Rule.ReplaceLen - 2;
            if IsHalfForm and (Rule.HalfValue <> '') then
              Val := Rule.HalfValue
            else
              Val := Rule.Value;
          end
          else
          begin
            // Default 2-char: replace hasanta + ra
            Val := Rule.Value;
            Take := 0;
          end;
          Matched := True;
          break;
        end;
      end;
    end;

    // Fallback to hardcoded defaults if no rule matched
    if not Matched then
    begin
      if (PrevC = b_p) or (PrevC = b_g) or (PrevC = b_sh) then
      begin
        Val := A_RFola_3;
        Take := 0;
      end
      else if PrevC = b_Bh then
      begin
        if IsHalfForm then
          Val := A_BH_R_2H
        else
          Val := A_Bh_R;
        Take := 1;
      end
      else if PrevC = b_K then
      begin
        if IsHalfForm then
          Val := A_K_R_2H
        else
          Val := A_K_R;
        Take := 1;
      end
      else if PrevC = b_t then
      begin
        if IsHalfForm then
        begin
          if (C3 <> #0) and ((C3 = b_K) or (C3 = b_t)) then
          begin
            Val := A_RFola_2;
            Take := 0;
          end
          else
          begin
            Val := A_T_R_2H;
            Take := 1;
          end;
        end
        else
        begin
          Val := A_T_R;
          Take := 1;
        end;
      end
      else if (PrevC = A_K_T[1]) or (PrevC = A_T_T[1]) or (PrevC = A_P_T[1]) then
      begin
        Val := A_RFola_2;
        Take := 0;
      end
      else if PrevC = b_ph then
      begin
        Val := A_RFola_2;
        Take := 0;
      end
      else
      begin
        Val := A_RFola_1;
        Take := 0;
      end;
    end;
  end;

begin
  // Convert Z-Fola
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_z, A_ZFola);
  // Convert Hasanta
  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + zwnj, A_Hasanta);

  // Convert R-Fola - single left-to-right pass. The old repeat/Pos +
  // WideStuffString loop rescanned from the top and rebuilt the whole string
  // for every r-fola - O(N^2) on conjunct-heavy text. The (hasanta + ra) match
  // is always found in the input here; the consonant before it (and the
  // 3-char reach-back) is read from the output built so far, exactly like the
  // in-place version's evolved prefix.
  SB := TStringBuilder.Create(Length(fConvertedText) + 16);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if (fConvertedText[I] = b_Hasanta) and (I < Length(fConvertedText)) and (fConvertedText[I + 1] = b_r) then
      begin
        if SB.Length >= 1 then
          PrevC := SB.Chars[SB.Length - 1]
        else
          PrevC := #0;
        if SB.Length >= 2 then
          C2 := SB.Chars[SB.Length - 2]
        else
          C2 := #0;
        if SB.Length >= 3 then
          C3 := SB.Chars[SB.Length - 3]
        else
          C3 := #0;
        IsHalfForm := (C2 = b_Hasanta);

        MatchRfola;

        if Take > SB.Length then
          Take := SB.Length;
        SB.Length := SB.Length - Take;
        SB.Append(Val);
        Inc(I, 2);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.DeNormalize;
var
  SB:         TStringBuilder;
  I, J, RunLen: Integer;
begin
  fConvertedText := ReplaceStr(fConvertedText, b_z + b_Nukta, b_y);
  fConvertedText := ReplaceStr(fConvertedText, b_dd + b_Nukta, b_rr);
  fConvertedText := ReplaceStr(fConvertedText, b_ddh + b_Nukta, b_rrh);

  // The old while Pos(HHH) + ReplaceStr loop rescanned the whole string for
  // every long hasanta run - O(N^2) on pathological input. Collapse every run
  // of 3+ hasantas to a pair in a single pass (a pair is a valid joiner and
  // must be preserved).
  SB := TStringBuilder.Create(Length(fConvertedText) + 8);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if fConvertedText[I] = b_Hasanta then
      begin
        J := I;
        while (J <= Length(fConvertedText)) and (fConvertedText[J] = b_Hasanta) do
          Inc(J);
        RunLen := J - I;
        if RunLen > 2 then
          RunLen := 2;
        while RunLen > 0 do
        begin
          SB.Append(b_Hasanta);
          Dec(RunLen);
        end;
        I := J;
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;

  fConvertedText := ReplaceStr(fConvertedText, b_Hasanta + b_z + b_Hasanta + b_r, b_Hasanta + b_r + b_Hasanta + b_z);
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReplaceNumbers;
begin
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
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReArrangeKars;
var
  I, OutIdx: Integer;
  wCTmp, fKar: Char;
  Len: Integer;
  TempList: TList<Char>;

  function MoveAbleKar(const wKar: Char): Boolean;
  begin
    Result := (wKar = b_Ekar) or (wKar = b_IKar) or (wKar = b_OIKar);
  end;

begin
  // Break O-kar and OU-Kar
  fConvertedText := ReplaceStr(fConvertedText, b_OKar, b_Ekar + b_AAKar);
  fConvertedText := ReplaceStr(fConvertedText, b_OUKar, b_Ekar + b_LengthMark);

  Len := Length(fConvertedText);
  if Len = 0 then
    Exit;

  // The old code prepended characters to a string inside the loop
  // (wSTmp := wCTmp + wSTmp), re-allocating and copying the whole string on
  // every character - O(N^2), the main cause of the freeze on large texts.
  // Instead we append to a pre-allocated list while scanning backwards, then
  // write the result back in a single O(N) pass.
  TempList := TList<Char>.Create;
  try
    TempList.Capacity := Len + (Len div 4);
    fKar := #0;
    I := Len;

    while I >= 1 do
    begin
      wCTmp := fConvertedText[I];

      if MoveAbleKar(wCTmp) then
      begin
        if fKar <> #0 then
          TempList.Add(fKar);
        fKar := wCTmp;
      end
      else
      begin
        if fKar = #0 then
        begin // No Kar is pending
          TempList.Add(wCTmp);
        end
        else
        begin
          if (IsPureConsonent(wCTmp) = False) and (wCTmp <> b_Hasanta) and (wCTmp <> zwj) and (wCTmp <> zwnj) then
          begin
            TempList.Add(fKar);
            fKar := #0;
            TempList.Add(wCTmp);
          end
          else
          begin
            if (wCTmp = b_Hasanta) or (wCTmp = zwj) or (wCTmp = zwnj) then
            begin
              TempList.Add(wCTmp);
            end
            else if IsPureConsonent(wCTmp) then
            begin
              if (I > 1) and ((fConvertedText[I - 1] = b_Hasanta) or (fConvertedText[I - 1] = zwj) or (fConvertedText[I - 1] = zwnj)) then
                TempList.Add(wCTmp)
              else
              begin
                TempList.Add(wCTmp);
                TempList.Add(fKar);
                // Place pending kar at beginning
                fKar := #0;
              end;
            end;
          end;
        end;
      end;
      Dec(I);
    end;

    if fKar <> #0 then
      TempList.Add(fKar);

    // TempList holds the output in reverse order - copy it back front-to-back.
    SetLength(fConvertedText, TempList.Count);
    OutIdx := 1;
    for I := TempList.Count - 1 downto 0 do
    begin
      fConvertedText[OutIdx] := TempList[I];
      Inc(OutIdx);
    end;
  finally
    TempList.Free;
  end;
end;

{ =============================================================================== }

procedure TUnicodeToBijoy2000.ReArrangeReph;
var
  I:           Integer;
  wCTmp:       Char;
  Len:         Integer;
  SB:          TStringBuilder;
  RephPending: Boolean;

  function MoveAbleReph: Boolean;
  begin
    Result := False;
    if I + 1 >= Len then
      Exit;

    // To avoid reph: if the character right before 'ra' is a hasanta (b_Hasanta)
    // then it is not a reph, but rather a ra-phala of the previous letter (e.g., mrya, krya)
    if (I > 1) and (fConvertedText[I - 1] = b_Hasanta) then
      Exit;

    if (fConvertedText[I] = b_r) and (fConvertedText[I + 1] = b_Hasanta) then
    begin
      if (I + 2 <= Len) and ((fConvertedText[I + 2] = ' ') or (fConvertedText[I + 2] = #13)) then
        Result := False
      else
        Result := True;
    end;
  end;

begin
  Len := Length(fConvertedText);
  if Len < 3 then
    Exit;

  // The old code appended to a string inside the loop (wSTmp := wSTmp + wCTmp),
  // re-allocating on every character - O(N^2). TStringBuilder appends in place.
  SB := TStringBuilder.Create(Len + 64);
  try
    I := 1;
    RephPending := False;

    while I <= Len do
    begin
      wCTmp := fConvertedText[I];

      if MoveAbleReph then
      begin
        RephPending := True;
        I := I + 2;
        Continue;
      end;

      SB.Append(wCTmp);

      if RephPending then
      begin
        if IsVowel(wCTmp) then
        begin
          // Keep moving
        end
        else if (I + 1 <= Len) and (fConvertedText[I + 1] = b_Hasanta) then
        begin
        end
        else if (wCTmp <> b_Hasanta) and (wCTmp <> zwj) and (wCTmp <> zwnj) then
        begin
          SB.Append(A_Reph);
          RephPending := False;
        end;
      end;
      Inc(I);
    end;

    if RephPending then
      SB.Append(A_Reph);
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ =============================================================================== }

function GetAnsiVarValue(const Name: string): string;
var
  Rec: TAnsiVarRec;
begin
  if (AnsiOverrides <> nil) and AnsiOverrides.TryGetValue(name, Result) then
    Exit;
  if (AnsiRegistryMap <> nil) and AnsiRegistryMap.TryGetValue(name, Rec) then
  begin
    if Rec.VarType = avChar then
      Result := string(PChar(Rec.Ptr)^)
    else
      Result := PString(Rec.Ptr)^;
  end
  else
    Result := '';
end;

function ProcessHexAndUnicode(const S: string): string;
var
  SB:      TStringBuilder;
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
        while (I <= Length(S)) and (CharInSet(S[I], ['0' .. '9', 'A' .. 'F', 'a' .. 'f'])) do
        begin
          Code := Code * 16;
          if CharInSet(S[I], ['0' .. '9']) then
            Code := Code + Ord(S[I]) - Ord('0')
          else if CharInSet(S[I], ['A' .. 'F']) then
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

function ResolveValue(const S: string): string;
var
  I, J:    Integer;
  VarName: string;
  VarVal:  string;
  Rec:     TAnsiVarRec;
begin
  Result := ProcessHexAndUnicode(S);
  I := 1;
  while I <= Length(Result) do
  begin
    if (I < Length(Result)) and (Result[I] = '#') and (Result[I + 1] = '#') then // Fallback to handle possible syntax anomalies
      Inc(I);
    if (I < Length(Result)) and (Result[I] = '#') and (Result[I + 1] = '{') then
    begin
      J := I + 2;
      while (J <= Length(Result)) and (Result[J] <> '}') do
        Inc(J);
      if J <= Length(Result) then
      begin
        VarName := Copy(Result, I + 2, J - I - 2);
        VarVal := GetAnsiVarValue(VarName);
        Result := Copy(Result, 1, I - 1) + VarVal + Copy(Result, J + 1, Length(Result));
        I := I + Length(VarVal);
      end
      else
        Inc(I);
    end
    else
      Inc(I);
  end;
end;

function HasHasantaBefore(const Text: string; Pos: Integer): Boolean; forward;

// Returns the length of the longest group entry that matches ending at
// CharIndex, or 0 if no entry matches.  Groups are compared as atomic
// literal blocks (block-based matching — never character-by-character).
function MatchGroupLength(const FullText: string; CharIndex: Integer; const GroupName: string): Integer;
var
  Arr:        TArray<string>;
  S:          string;
  SLen:       Integer;
  CompareStr: string;
  MatchStart: Integer;
begin
  Result := 0;
  if (CharIndex < 1) or (CharIndex > Length(FullText)) then
    Exit;

  if AnsiGroupMap <> nil then
  begin
    if AnsiGroupMap.TryGetValue(GroupName, Arr) then
      for S in Arr do
      begin
        SLen := Length(S);
        if (SLen <= CharIndex) then
        begin
          MatchStart := CharIndex - SLen + 1;
          CompareStr := Copy(FullText, MatchStart, SLen);
          if (CompareStr = S) and not HasHasantaBefore(FullText, MatchStart) then
          begin
            if SLen > Result then
              Result := SLen;
          end;
        end;
      end;
  end;

  if ConsonantGroupMap <> nil then
  begin
    if ConsonantGroupMap.TryGetValue(GroupName, Arr) then
      for S in Arr do
      begin
        SLen := Length(S);
        if (SLen <= CharIndex) then
        begin
          MatchStart := CharIndex - SLen + 1;
          if (Copy(FullText, MatchStart, SLen) = S) and not HasHasantaBefore(FullText, MatchStart) then
          begin
            if SLen > Result then
              Result := SLen;
          end;
        end;
      end;
  end;
end;

procedure TUnicodeToBijoy2000.ApplyRuleForKar(const KarChar: string; const Phase: string = '');
const
  // Maximum look-back depth needed by the cluster match (longest group entry
  // plus the hasanta walk). Far larger than any real conjunct.
  LookBackWindow = 64;
var
  Rule:            TVowelRule;
  UseAlt:          Boolean;
  Found:           Boolean;
  Resolved:        string;
  SearchChar:      string;
  OccurrenceIndex: Integer;
  ClusterInfo:     TClusterMatchInfo;
  SB:              TStringBuilder;
  I, LW:           Integer;
  Win:             string;
begin
  Found := False;
  for Rule in VowelRules do
    if Rule.KarChar = KarChar then
    begin
      Found := True;
      break;
    end;

  if not Found then
    Exit;

  if Phase = 'post' then
    SearchChar := ResolveValue(Rule.DefaultVal)
  else
    SearchChar := KarChar;

  // The old code rebuilt the whole string for every kar occurrence
  // (WideStuffString inside the loop) - O(N^2) on texts full of u/uu/rri.
  // Build the output once, left to right. The cluster match must see the
  // evolving string exactly as the in-place version would, so it is given a
  // window = the last LookBackWindow chars of the output built so far (the
  // evolved prefix) with the kar sitting right after the window.
  SB := TStringBuilder.Create(Length(fConvertedText) + 16);
  try
    OccurrenceIndex := 0;
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if fConvertedText[I] = SearchChar[1] then
      begin
        Inc(OccurrenceIndex);

        if SB.Length >= 1 then
        begin
          LW := SB.Length;
          if LW > LookBackWindow then
            LW := LookBackWindow;
          Win := SB.ToString(SB.Length - LW, LW);
          ClusterInfo := FindBestClusterMatch(Win, LW + 1, Rule);

          if ClusterInfo.BestMatchLen > 0 then
          begin
            if (Phase <> '') and (ClusterInfo.BestMapping.ProcessPhase <> '') and (ClusterInfo.BestMapping.ProcessPhase <> Phase) then
            begin
              Resolved := ResolveValue(Rule.DefaultVal);
            end
            else
            begin
              if ClusterInfo.BestMapping.ToggleOnBackspace then
                UseAlt := GetToggleState(ClusterInfo.MatchedCluster, KarChar, OccurrenceIndex)
              else
                UseAlt := False;

              if UseAlt and (ClusterInfo.BestMapping.Alt <> '') then
                Resolved := ResolveValue(ClusterInfo.BestMapping.Alt)
              else
                Resolved := ResolveValue(ClusterInfo.BestMapping.Value);
            end;
          end
          else
            Resolved := ResolveValue(Rule.DefaultVal);
        end
        else
          Resolved := ResolveValue(Rule.DefaultVal);

        SB.Append(Resolved);
        Inc(I);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;
end;

function HasHasantaBefore(const Text: string; Pos: Integer): Boolean;
var
  I: Integer;
begin
  Result := False;
  if Pos - 1 < 1 then
    Exit;

  I := Pos - 1; // Start checking for hasanta from the cell just before Pos (ra)

  // Skip ZWJ / ZWNJ characters if present
  while (I >= 1) and ((Text[I] = zwj) or (Text[I] = zwnj)) do
    Dec(I);

  // If the character immediately before is hasanta (b_Hasanta)
  if (I >= 1) and (Text[I] = b_Hasanta) then
    Result := True;
end;

function TUnicodeToBijoy2000.FindBestClusterMatch(const Text: string; KarPos: Integer; const Rule: TVowelRule): TClusterMatchInfo;
var
  PrecedingChar: string;
  Mapping:       TVowelRuleMapping;
  MatchLen:      Integer;
  GroupMatchLen: Integer;
begin
  Result.MatchedCluster := '';
  Result.BestMatchLen := 0;
  Result.ContextEnd := 0;
  Result.IsZfola := False;
  Result.BestMapping.Consonants := '';
  Result.BestMapping.Value := '';
  Result.BestMapping.Alt := '';
  Result.BestMapping.ToggleOnBackspace := False;
  Result.BestMapping.MatchMode := 0;
  Result.BestMapping.ProcessPhase := '';

  if KarPos - 1 < 1 then
    Exit;

  // Resolve Z-fola context
  PrecedingChar := Text[KarPos - 1];
  Result.ContextEnd := KarPos - 1;
  Result.IsZfola := (PrecedingChar = b_z) and (KarPos - 2 >= 1) and (Text[KarPos - 2] = b_Hasanta);

  if Result.IsZfola then
  begin
    Result.ContextEnd := KarPos - 3;
    if Result.ContextEnd >= 1 then
      PrecedingChar := Text[Result.ContextEnd]
    else
      PrecedingChar := '';
  end;

  if Result.ContextEnd < 1 then
    Exit;

  // Evaluate best match across rule mappings
  for Mapping in Rule.Mappings do
  begin
    if Mapping.Consonants = '' then
      Continue;

    MatchLen := 0;

    // 1. Direct single-character match (skip if preceded by Hasanta = half-form conjunct)
    if (PrecedingChar <> '') and (PrecedingChar = Mapping.Consonants) and not HasHasantaBefore(Text, KarPos - 1) then
    begin
      if Mapping.MatchMode = 1 then
        MatchLen := 1
      else
        MatchLen := Length(Mapping.Consonants);
    end
    else
    begin
      // 2. Group-based cluster match
      GroupMatchLen := MatchGroupLength(Text, Result.ContextEnd, Mapping.Consonants);
      if GroupMatchLen > 0 then
      begin
        if Mapping.MatchMode = 1 then
          MatchLen := 1 // Force matched length to 1 for matchMode = 1
        else
          MatchLen := GroupMatchLen; // Use exact cluster length for matchMode = 0
      end;
    end;

    if MatchLen > Result.BestMatchLen then
    begin
      Result.BestMatchLen := MatchLen;
      Result.BestMapping := Mapping;
    end;
  end;

  if Result.BestMatchLen > 0 then
    Result.MatchedCluster := Copy(Text, Result.ContextEnd - Result.BestMatchLen + 1, Result.BestMatchLen);
end;

procedure TUnicodeToBijoy2000.ApplyKarInclusiveFullForms;
const
  // HasHasantaBefore only walks back over ZWJ/ZWNJ characters; this bound
  // keeps the check O(1) while covering every realistic run.
  LookBackWindow = 64;
var
  I, J, P:   Integer;
  K, V:      string;
  SB:        TStringBuilder;
  KLen:      Integer;
  StartPos:  Integer;
  ResumePos: Integer; // 1-based output position where the next occurrence may start
  HPos:      Integer;
  Match:     Boolean;
  HasH:      Boolean;
begin
  for I := 0 to Length(KarInclusiveReplacements) - 1 do
  begin
    K := KarInclusiveReplacements[I].Key;
    V := KarInclusiveReplacements[I].Value;
    if (K = '') or (V = '') then
      Continue;

    KLen := Length(K);

    // The old code rescanned with PosEx and rebuilt the whole string with
    // WideStuffString for every occurrence - O(N^2) on texts full of the
    // pattern. Scan once: append each character, and whenever the output tail
    // forms K (starting at/after the resume position), apply the same
    // hasanta-before rule as the in-place version.
    SB := TStringBuilder.Create(Length(fConvertedText) + 8);
    try
      ResumePos := 1;
      for J := 1 to Length(fConvertedText) do
      begin
        SB.Append(fConvertedText[J]);

        if SB.Length < KLen then
          Continue;
        StartPos := SB.Length - KLen + 1;
        if StartPos < ResumePos then
          Continue;

        Match := True;
        for P := 0 to KLen - 1 do
          if SB.Chars[StartPos - 1 + P] <> K[P + 1] then
          begin
            Match := False;
            Break;
          end;
        if not Match then
          Continue;

        // Hasanta immediately before the match? (e.g., 'gu' inside 'nggu')
        HPos := StartPos - 1;
        while (HPos >= 1) and (StartPos - HPos <= LookBackWindow) and
              ((SB.Chars[HPos - 1] = zwj) or (SB.Chars[HPos - 1] = zwnj)) do
          Dec(HPos);
        HasH := (HPos >= 1) and (SB.Chars[HPos - 1] = b_Hasanta);

        if HasH then
        begin
          // Part of a conjunct - keep it; continue searching right after it.
          ResumePos := StartPos + KLen;
        end
        else
        begin
          SB.Length := StartPos - 1;
          SB.Append(V);
          ResumePos := SB.Length + 1;
        end;
      end;
      fConvertedText := SB.ToString;
    finally
      SB.Free;
    end;
  end;
end;

procedure TUnicodeToBijoy2000.ApplyVowelKars;
begin
  // Convert UKar
  ApplyRuleForKar(b_Ukar);
  fConvertedText := ReplaceStr(fConvertedText, b_Ukar, GetAnsiVarValue('A_UKar1'));

  // Convert UUKar
  ApplyRuleForKar(b_UUKar);
  fConvertedText := ReplaceStr(fConvertedText, b_UUKar, GetAnsiVarValue('A_UUKar1'));

  // Convert RRIKar
  ApplyRuleForKar(b_Rrikar);
  fConvertedText := ReplaceStr(fConvertedText, b_Rrikar, GetAnsiVarValue('A_RRIKar1'));
end;

procedure TUnicodeToBijoy2000.ReplaceKarsVowels;
var
  I:  Integer;
  SB: TStringBuilder;
begin
  // Convert Ekar - single left-to-right pass. The old repeat/Pos loop
  // restarted the scan and rebuilt the string for every e-kar - O(N^2) on
  // kar-heavy text. Replacements are 1->1 so positions never shift; the
  // predecessor check reads the output tail (the same evolved prefix).
  SB := TStringBuilder.Create(Length(fConvertedText) + 8);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if fConvertedText[I] = b_Ekar then
      begin
        if (SB.Length = 0) or (SB.Chars[SB.Length - 1] = ' ') or (SB.Chars[SB.Length - 1] = #13) or (SB.Chars[SB.Length - 1] = #10) or
            (SB.Chars[SB.Length - 1] = #9) then
          SB.Append(A_EKar1)
        else
          SB.Append(GetAnsiVarValue('A_EKar2'));
        Inc(I);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;

  // Convert OIKar
  SB := TStringBuilder.Create(Length(fConvertedText) + 8);
  try
    I := 1;
    while I <= Length(fConvertedText) do
    begin
      if fConvertedText[I] = b_OIKar then
      begin
        if (SB.Length = 0) or (SB.Chars[SB.Length - 1] = ' ') or (SB.Chars[SB.Length - 1] = #13) or (SB.Chars[SB.Length - 1] = #10) or
            (SB.Chars[SB.Length - 1] = #9) then
          SB.Append(A_OIKar1)
        else
          SB.Append(GetAnsiVarValue('A_OIKar2'));
        Inc(I);
      end
      else
      begin
        SB.Append(fConvertedText[I]);
        Inc(I);
      end;
    end;
    fConvertedText := SB.ToString;
  finally
    SB.Free;
  end;

  // Convert rest of the Kars
  fConvertedText := ReplaceStr(fConvertedText, b_AAKar, A_AAKar);
  fConvertedText := ReplaceStr(fConvertedText, b_IKar, A_IKar);
  fConvertedText := ReplaceStr(fConvertedText, b_IIKar, A_IIKar);
  fConvertedText := ReplaceStr(fConvertedText, b_LengthMark, A_OUKar);

  // Convert Vowels
  fConvertedText := ReplaceStr(fConvertedText, b_A, A_A);
  fConvertedText := ReplaceStr(fConvertedText, b_AA, A_AA);
  fConvertedText := ReplaceStr(fConvertedText, b_I, GetAnsiVarValue('A_I'));
  fConvertedText := ReplaceStr(fConvertedText, b_II, A_II);
  fConvertedText := ReplaceStr(fConvertedText, b_U, GetAnsiVarValue('A_U'));
  fConvertedText := ReplaceStr(fConvertedText, b_UU, A_UU);
  fConvertedText := ReplaceStr(fConvertedText, b_RRI, A_RRI);
  fConvertedText := ReplaceStr(fConvertedText, b_E, A_E);
  fConvertedText := ReplaceStr(fConvertedText, b_OI, A_OI);
  fConvertedText := ReplaceStr(fConvertedText, b_O, A_O);
  fConvertedText := ReplaceStr(fConvertedText, b_OU, A_OU);
end;

{ =============================================================================== }

function TUnicodeToBijoy2000.RuleHasAnyToggle(const Rule: TVowelRule): Boolean;
var
  M: TVowelRuleMapping;
begin
  Result := Rule.ToggleOnBackspace;
  if not Result then
    for M in Rule.Mappings do
      if M.ToggleOnBackspace then
      begin
        Result := True;
        Exit;
      end;
end;

function TUnicodeToBijoy2000.FindMappingToggle(const Rule: TVowelRule; const ConsonantPart: string; out MappingToggleOnBackspace: Boolean;
  out MatchedCluster: string): Boolean;
var
  Mapping:                               TVowelRuleMapping;
  BestMapping:                           TVowelRuleMapping;
  BestMatchLen, MatchLen, GroupMatchLen: Integer;
  LastC:                                 string;
  ActualConsonantPart:                   string;
  Len:                                   Integer;
begin
  MappingToggleOnBackspace := Rule.ToggleOnBackspace;
  Result := False;
  MatchedCluster := '';

  if ConsonantPart = '' then
    Exit;

  ActualConsonantPart := ConsonantPart;
  Len := Length(ActualConsonantPart);

  // Strip Z-fola suffix if present
  if (Len >= 2) and (Copy(ActualConsonantPart, Len, 1) = b_z) and (Copy(ActualConsonantPart, Len - 1, 1) = b_Hasanta) then
  begin
    ActualConsonantPart := Copy(ActualConsonantPart, 1, Len - 2);
    Len := Length(ActualConsonantPart);
  end;

  if ActualConsonantPart = '' then
    Exit;

  LastC := Copy(ActualConsonantPart, Len, 1);

  BestMatchLen := 0;
  BestMapping.Consonants := '';
  BestMapping.ToggleOnBackspace := False;

  for Mapping in Rule.Mappings do
  begin
    if Mapping.Consonants = '' then
      Continue;

    MatchLen := 0;

    // 1. Direct character match (skip if preceded by Hasanta = half-form conjunct)
    if (LastC = Mapping.Consonants) and not HasHasantaBefore(ActualConsonantPart, Len) then
    begin
      if Mapping.MatchMode = 1 then
        MatchLen := 1
      else
        MatchLen := Length(Mapping.Consonants);
    end
    else
    begin
      // 2. Group match
      GroupMatchLen := MatchGroupLength(ActualConsonantPart, Len, Mapping.Consonants);
      if GroupMatchLen > 0 then
      begin
        if Mapping.MatchMode = 1 then
          MatchLen := 1
        else
          MatchLen := GroupMatchLen;
      end;
    end;

    if MatchLen > BestMatchLen then
    begin
      BestMatchLen := MatchLen;
      BestMapping := Mapping;
    end;
  end;

  if BestMatchLen > 0 then
  begin
    MappingToggleOnBackspace := BestMapping.ToggleOnBackspace;
    MatchedCluster := Copy(ActualConsonantPart, Len - BestMatchLen + 1, BestMatchLen);
    Result := True;
  end;
end;

{ =============================================================================== }

{ =============================================================================== }

function EscapeJSON(const S: string): string;
var
  C: Char;
begin
  Result := '';
  for C in S do
  begin
    case C of
      '\':
        Result := Result + '\\';
      '"':
        Result := Result + '\"';
      '/':
        Result := Result + '\/';
      #$08:
        Result := Result + '\b';
      #$09:
        Result := Result + '\t';
      #$0A:
        Result := Result + '\n';
      #$0C:
        Result := Result + '\f';
      #$0D:
        Result := Result + '\r';
      else
        if Ord(C) < 32 then
          Result := Result + '\u' + IntToHex(Ord(C), 4)
        else
          Result := Result + C;
    end;
  end;
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
    if (I < Length(S)) and (S[I] = '#') and (S[I + 1] = '$') then
    begin
      if (I + 2 > Length(S)) or not(CharInSet(S[I + 2], ['0' .. '9', 'A' .. 'F', 'a' .. 'f'])) then
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
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
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
  while (P <= Length(S)) and (S[P] <= ' ') do
    Inc(P);
end;

function JReadString(const S: string; var P: Integer): string;
var
  SB: TStringBuilder;
begin
  Result := '';
  JSkipWS(S, P);
  if (P > Length(S)) or (S[P] <> '"') then
    Exit;
  Inc(P);
  SB := TStringBuilder.Create;
  try
    while P <= Length(S) do
    begin
      if S[P] = '"' then
      begin
        Inc(P);
        Result := SB.ToString;
        Exit;
      end;
      if S[P] = '\' then
      begin
        Inc(P);
        if P > Length(S) then
          Exit;
        case S[P] of
          '"':
            SB.Append('"');
          '\':
            SB.Append('\');
          '/':
            SB.Append('/');
          'n':
            SB.Append(#10);
          'r':
            SB.Append(#13);
          't':
            SB.Append(#9);
          'u':
            begin
              if P + 4 <= Length(S) then
                SB.Append(Char(StrToIntDef('$' + Copy(S, P + 1, 4), Ord('?'))))
              else
                SB.Append('?');
              Inc(P, 4);
            end;
          else
            SB.Append(S[P]);
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

function JReadInt(const S: string; var P: Integer; Default: Integer): Integer;
var
  Start: Integer;
  Neg:   Boolean;
begin
  Result := default;
  JSkipWS(S, P);
  if (P > Length(S)) then
    Exit;
  Neg := False;
  if S[P] = '-' then
  begin
    Neg := True;
    Inc(P);
  end;
  if (P > Length(S)) or not CharInSet(S[P], ['0' .. '9']) then
    Exit;
  Start := P;
  while (P <= Length(S)) and CharInSet(S[P], ['0' .. '9']) do
    Inc(P);
  Result := StrToIntDef(Copy(S, Start, P - Start), default);
  if Neg then
    Result := -Result;
end;

procedure JSkipValue(const S: string; var P: Integer);
var
  Depth: Integer;
begin
  JSkipWS(S, P);
  if P > Length(S) then
    Exit;
  case S[P] of
    '{', '[':
      begin
        Depth := 1;
        Inc(P);
        while (P <= Length(S)) and (Depth > 0) do
        begin
          if S[P] = '"' then
          begin
            Inc(P);
            while P <= Length(S) do
              if S[P] = '\' then
              begin
                Inc(P);
                if P <= Length(S) then
                  Inc(P);
              end
              else if S[P] = '"' then
              begin
                Inc(P);
                break;
              end
              else
                Inc(P);
          end
          else if CharInSet(S[P], ['{', '[']) then
            Inc(Depth)
          else if CharInSet(S[P], ['}', ']']) then
            Dec(Depth);
          if Depth > 0 then
            Inc(P);
        end;
        if P <= Length(S) then
          Inc(P);
      end;
    '"':
      JReadString(S, P);
    else
      Inc(P);
  end;
end;

{ =============================================================================== }

function JSONPrettyPrint(const JSON: string): string;
var
  SB:       TStringBuilder;
  P, Depth: Integer;
  C, NextC: Char;
  InString: Boolean;

  procedure AppendIndent;
  begin
    SB.Append(sLineBreak);
    if Depth > 0 then
      SB.Append(StringOfChar(' ', Depth * 2));
  end;

begin
  if JSON = '' then
    Exit('');
  SB := TStringBuilder.Create;
  try
    Depth := 0;
    InString := False;
    P := 1;
    while P <= Length(JSON) do
    begin
      C := JSON[P];

      if InString then
      begin
        SB.Append(C);
        if (C = '"') and (JSON[P - 1] <> '\') then
          InString := False;
        Inc(P);
        Continue;
      end;

      case C of
        '"':
          begin
            InString := True;
            SB.Append(C);
            Inc(P);
          end;

        '{', '[':
          begin
            SB.Append(C);

            NextC := #0;
            var
            LookAhead := P + 1;
            while LookAhead <= Length(JSON) do
            begin
              if JSON[LookAhead] > ' ' then
              begin
                NextC := JSON[LookAhead];
                break;
              end;
              Inc(LookAhead);
            end;

            if ((C = '{') and (NextC = '}')) or ((C = '[') and (NextC = ']')) then
            begin
              Inc(P);
              while (P <= Length(JSON)) and (JSON[P] <= ' ') do
                Inc(P);
              if (P <= Length(JSON)) and ((JSON[P] = '}') or (JSON[P] = ']')) then
              begin
                SB.Append(JSON[P]);
                Inc(P);
              end;
            end
            else
            begin
              Inc(Depth);
              AppendIndent;
              Inc(P);
            end;
          end;

        '}', ']':
          begin
            Dec(Depth);
            AppendIndent;
            SB.Append(C);
            Inc(P);
          end;

        ',':
          begin
            SB.Append(C);
            AppendIndent;
            Inc(P);
          end;

        ':':
          begin
            SB.Append(': ');
            Inc(P);
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

{ =============================================================================== }
// Lazy initialization for AnsiRegistry and AnsiOverrides
procedure EnsureAnsiRegistry;
begin
  if AnsiRegistry = nil then
  begin
    AnsiRegistry := TList<TAnsiVarRec>.Create;
    AnsiRegistryMap := TDictionary<string, TAnsiVarRec>.Create;
    InitializeAnsiRegistry;
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
  I:             Integer;
  UniqueMap:     TDictionary<string, string>;
  Rec:           TAnsiVarRec;
  Key:           string;
  Val:           string;
  ExcludedNames: TDictionary<string, Boolean>;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  ExcludedNames := TDictionary<string, Boolean>.Create;
  UniqueMap := TDictionary<string, string>.Create;
  try
    // FIX: Loop through AnsiRegistryMap.Values instead of AnsiRegistry list
    // This ensures we use the updated BengaliChar (UnicodeKey) loaded from JSON
    for Rec in AnsiRegistryMap.Values do
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
        if (Rec.Name <> 'A_Khandata') and (Rec.Name <> 'A_Anushar') and (Rec.Name <> 'A_Bisharga') and (Rec.Name <> 'A_Chandra') then
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
      begin
        if Rec.VarType = avChar then
          Val := string(PChar(Rec.Ptr)^)
        else
          Val := PString(Rec.Ptr)^;
      end;

      if Val = '' then
        Continue;

      UniqueMap.AddOrSetValue(Key, Val);
    end;

    // 2. Merge custom full-form overrides
    for I := 0 to Length(CustomFullForms) - 1 do
      UniqueMap.AddOrSetValue(CustomFullForms[I].Key, CustomFullForms[I].Value);

    // 3. Populate ActiveReplacements and KarInclusiveReplacements
    SetLength(ActiveReplacements, 0);
    SetLength(KarInclusiveReplacements, 0);
    for Key in UniqueMap.Keys do
    begin
      Val := UniqueMap.Items[Key];
      if (Key.EndsWith(string(b_Ukar))) or (Key.EndsWith(string(b_UUKar))) or (Key.EndsWith(string(b_Rrikar))) then
      begin
        SetLength(KarInclusiveReplacements, Length(KarInclusiveReplacements) + 1);
        KarInclusiveReplacements[high(KarInclusiveReplacements)].Key := Key;
        KarInclusiveReplacements[high(KarInclusiveReplacements)].Value := Val;
      end
      else
      begin
        SetLength(ActiveReplacements, Length(ActiveReplacements) + 1);
        ActiveReplacements[high(ActiveReplacements)].Key := Key;
        ActiveReplacements[high(ActiveReplacements)].Value := Val;
      end;
    end;

    // 4. Sort by key length descending (Longest Match First)
    TArray.Sort<TReplacementPair>(ActiveReplacements, TComparer<TReplacementPair>.Construct(
          function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
        if Result = 0 then
        begin
          // If lengths are equal, priority is given to ordinary conjuncts (excluding 'ra-phala') first.
          if L.Key.EndsWith(string(b_r)) and not R.Key.EndsWith(string(b_r)) then
            Result := 1
          else if not L.Key.EndsWith(string(b_r)) and R.Key.EndsWith(string(b_r)) then
            Result := -1;
        end;
      end));
    TArray.Sort<TReplacementPair>(KarInclusiveReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));
  finally
    UniqueMap.Free;
    ExcludedNames.Free;
  end;
end;

{ =============================================================================== }

procedure ResetAnsiToDefaults;
var
  Rec:      TAnsiVarRec;
  Resolved: string;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  for Rec in AnsiRegistry do
  begin
    Resolved := ProcessHexAndUnicode(Rec.DefaultVal);
    if Rec.VarType = avChar then
      PChar(Rec.Ptr)^ := Resolved[1]
    else
      PString(Rec.Ptr)^ := Resolved;
  end;

  AnsiOverrides.Clear;
  Finalize(CustomFullForms);
  CustomFullForms := nil;
  Finalize(CustomPreReplacements);
  CustomPreReplacements := nil;
  Finalize(CustomPostReplacements);
  CustomPostReplacements := nil;
  Finalize(ActiveReplacements);
  ActiveReplacements := nil;
  Finalize(KarInclusiveReplacements);
  KarInclusiveReplacements := nil;
  Finalize(VowelRules);
  VowelRules := nil;
  Finalize(RfolaRules);
  RfolaRules := nil;
  Finalize(KarCorrections);
  KarCorrections := nil;
  Finalize(GroupKarCorrections);
  GroupKarCorrections := nil;
  if AnsiGroupMap <> nil then
    AnsiGroupMap.Clear;
  if AnsiGroupRawMap <> nil then
    AnsiGroupRawMap.Clear;
  if ConsonantGroupMap <> nil then
    ConsonantGroupMap.Clear;
  if ConsonantGroupRawMap <> nil then
    ConsonantGroupRawMap.Clear;
  PrepareActiveReplacements;
end;

{ =============================================================================== }

procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);

  function ParseSection(const S: string; var Pos: Integer): TArray<TReplacementPair>;
  var
    Items: TList<TReplacementPair>;
    Pair:  TReplacementPair;
    Field: string;
  begin
    Items := TList<TReplacementPair>.Create;
    try
      JSkipWS(S, Pos);
      if (Pos <= Length(S)) and (S[Pos] = '[') then
        Inc(Pos)
      else
        Exit;
      while Pos <= Length(S) do
      begin
        JSkipWS(S, Pos);
        if (Pos > Length(S)) or (S[Pos] = ']') then
        begin
          Inc(Pos);
          break;
        end;
        if S[Pos] = ',' then
        begin
          Inc(Pos);
          Continue;
        end;
        if S[Pos] = '{' then
        begin
          Inc(Pos);
          Pair.Key := '';
          Pair.Value := '';
          Pair.Comment := '';
          while Pos <= Length(S) do
          begin
            JSkipWS(S, Pos);
            if (Pos > Length(S)) or (S[Pos] = '}') then
            begin
              Inc(Pos);
              break;
            end;
            if S[Pos] = ',' then
            begin
              Inc(Pos);
              Continue;
            end;
            Field := JReadString(S, Pos);
            JSkipWS(S, Pos);
            if S[Pos] = ':' then
              Inc(Pos);
            if Field = 'Key' then
              Pair.Key := ResolveValue(JReadString(S, Pos))
            else if Field = 'Value' then
              Pair.Value := ResolveValue(JReadString(S, Pos))
            else if Field = 'Comment' then
              Pair.Comment := JReadString(S, Pos)
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
  JSON:                                                                       string;
  P:                                                                          Integer;
  Key, ConstName, ConstValue, UnicodeKeyValue, CatName, FieldName, ToggleVal, ConstComment: string;
  Rec:                                                                        TAnsiVarRec;
  Lines:                                                                      TStringList;
  Items:                                                                      TList<string>;
  RawItems:                                                                   TList<string>;
  RawStr:                                                                     string;
  GCorrGroup, GCorrFrom, GCorrTo:                                             string;
  GroupMembers:                                                               TArray<string>;
  GCorrMember:                                                                string;
  GCorrPair:                                                                  TReplacementPair;
begin
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
  if (P > Length(JSON)) or (JSON[P] <> '{') then
    Exit;
  Inc(P);

  while P <= Length(JSON) do
  begin
    JSkipWS(JSON, P);
    if (P > Length(JSON)) or (JSON[P] = '}') then
      break;
    if JSON[P] = ',' then
    begin
      Inc(P);
      Continue;
    end;

    Key := JReadString(JSON, P);
    JSkipWS(JSON, P);
    if (P <= Length(JSON)) and (JSON[P] = ':') then
      Inc(P);
    JSkipWS(JSON, P);

    if Key = 'Constants' then
    begin
      // Constants: { "Cat": { "Name": { "Value": "...", ... } } }
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        CatName := JReadString(JSON, P); // skip category name
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
          Inc(P)
        else
          Continue;
        while P <= Length(JSON) do
        begin
          JSkipWS(JSON, P);
          if (P > Length(JSON)) or (JSON[P] = '}') then
          begin
            Inc(P);
            break;
          end;
          if JSON[P] = ',' then
          begin
            Inc(P);
            Continue;
          end;
          ConstName := JReadString(JSON, P);
          JSkipWS(JSON, P);
          if JSON[P] = ':' then
            Inc(P);
          JSkipWS(JSON, P);
          if (P <= Length(JSON)) and (JSON[P] = '{') then
          begin
            Inc(P);
            ConstValue := '';
            UnicodeKeyValue := '';
            ConstComment := '';
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = '}') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              FieldName := JReadString(JSON, P);
              JSkipWS(JSON, P);
              if JSON[P] = ':' then
                Inc(P);
              if FieldName = 'Value' then
                ConstValue := JReadString(JSON, P)
              else if FieldName = 'UnicodeKey' then
                UnicodeKeyValue := ResolveValue(JReadString(JSON, P))
              else if FieldName = 'Comment' then
                ConstComment := JReadString(JSON, P)
              else
                JSkipValue(JSON, P);
            end;
            if ConstValue <> '' then
            begin
              ConstValue := ProcessHexAndUnicode(ConstValue);
              if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
              begin
                if Rec.VarType = avChar then
                begin
                  if Length(ConstValue) = 1 then
                    PChar(Rec.Ptr)^ := ConstValue[1]
                  else
                  begin
                    EnsureAnsiOverrides;
                    AnsiOverrides.AddOrSetValue(ConstName, ConstValue);
                  end;
                end
                else
                  PString(Rec.Ptr)^ := ConstValue;
              end;
            end;
            if UnicodeKeyValue <> '' then
            begin
              if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
              begin
                Rec.BengaliChar := UnicodeKeyValue;
                AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
              end;
            end;
            if ConstComment <> '' then
            begin
              if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
              begin
                Rec.Comment := ConstComment;
                AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
              end;
            end;
          end
          else
            JSkipValue(JSON, P);
        end;
      end;
    end
    else if Key = 'VowelsAndKars' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        ConstName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
        begin
          Inc(P);
          ConstValue := '';
          UnicodeKeyValue := '';
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
            begin
              Inc(P);
              break;
            end;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            FieldName := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
            if FieldName = 'Value' then
              ConstValue := JReadString(JSON, P)
            else if FieldName = 'UnicodeKey' then
              UnicodeKeyValue := ResolveValue(JReadString(JSON, P))
            else
              JSkipValue(JSON, P);
          end;
          if ConstValue <> '' then
          begin
            ConstValue := ResolveValue(ConstValue);
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              if Rec.VarType = avChar then
              begin
                if Length(ConstValue) = 1 then
                  PChar(Rec.Ptr)^ := ConstValue[1]
                else
                begin
                  EnsureAnsiOverrides;
                  AnsiOverrides.AddOrSetValue(ConstName, ConstValue);
                end;
              end
              else
                PString(Rec.Ptr)^ := ConstValue;
            end;
          end;
          if UnicodeKeyValue <> '' then
          begin
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              Rec.BengaliChar := UnicodeKeyValue;
              AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
            end;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'Symbols' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        ConstName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
        begin
          Inc(P);
          ConstValue := '';
          UnicodeKeyValue := '';
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
            begin
              Inc(P);
              break;
            end;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            FieldName := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
            if FieldName = 'Value' then
              ConstValue := JReadString(JSON, P)
            else if FieldName = 'UnicodeKey' then
              UnicodeKeyValue := ResolveValue(JReadString(JSON, P))
            else
              JSkipValue(JSON, P);
          end;
          if ConstValue <> '' then
          begin
            ConstValue := ResolveValue(ConstValue);
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              if Rec.VarType = avChar then
              begin
                if Length(ConstValue) = 1 then
                  PChar(Rec.Ptr)^ := ConstValue[1]
                else
                begin
                  EnsureAnsiOverrides;
                  AnsiOverrides.AddOrSetValue(ConstName, ConstValue);
                end;
              end
              else
                PString(Rec.Ptr)^ := ConstValue;
            end;
          end;
          if UnicodeKeyValue <> '' then
          begin
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              Rec.BengaliChar := UnicodeKeyValue;
              AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
            end;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'Consonants' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        ConstName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
        begin
          Inc(P);
          ConstValue := '';
          UnicodeKeyValue := '';
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
            begin
              Inc(P);
              break;
            end;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            FieldName := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
            if FieldName = 'Value' then
              ConstValue := JReadString(JSON, P)
            else if FieldName = 'UnicodeKey' then
              UnicodeKeyValue := ResolveValue(JReadString(JSON, P))
            else
              JSkipValue(JSON, P);
          end;
          if ConstValue <> '' then
          begin
            ConstValue := ResolveValue(ConstValue);
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              if Rec.VarType = avChar then
              begin
                if Length(ConstValue) = 1 then
                  PChar(Rec.Ptr)^ := ConstValue[1]
                else
                begin
                  EnsureAnsiOverrides;
                  AnsiOverrides.AddOrSetValue(ConstName, ConstValue);
                end;
              end
              else
                PString(Rec.Ptr)^ := ConstValue;
            end;
          end;
          if UnicodeKeyValue <> '' then
          begin
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              Rec.BengaliChar := UnicodeKeyValue;
              AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
            end;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'FullForms' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        ConstName := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
        begin
          Inc(P);
          ConstValue := '';
          UnicodeKeyValue := '';
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
            begin
              Inc(P);
              break;
            end;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            FieldName := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
            if FieldName = 'Value' then
              ConstValue := JReadString(JSON, P)
            else if FieldName = 'UnicodeKey' then
              UnicodeKeyValue := ResolveValue(JReadString(JSON, P))
            else
              JSkipValue(JSON, P);
          end;
          if ConstValue <> '' then
          begin
            ConstValue := ResolveValue(ConstValue);
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              if Rec.VarType = avChar then
              begin
                if Length(ConstValue) = 1 then
                  PChar(Rec.Ptr)^ := ConstValue[1]
                else
                begin
                  EnsureAnsiOverrides;
                  AnsiOverrides.AddOrSetValue(ConstName, ConstValue);
                end;
              end
              else
                PString(Rec.Ptr)^ := ConstValue;
            end;
          end;
          if UnicodeKeyValue <> '' then
          begin
            if AnsiRegistryMap.TryGetValue(ConstName, Rec) then
            begin
              Rec.BengaliChar := UnicodeKeyValue;
              AnsiRegistryMap.AddOrSetValue(ConstName, Rec);
            end;
          end;
        end
        else
          JSkipValue(JSON, P);
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
      SetLength(VowelRules, 0);
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        // Read KarChar key
        Key := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '{') then
        begin
          Inc(P);
          SetLength(VowelRules, Length(VowelRules) + 1);
          with VowelRules[high(VowelRules)] do
          begin
            KarChar := ProcessHexAndUnicode(Key);
            DefaultVal := '';
            Toggle := 'none';
            ToggleOnBackspace := False;
            SetLength(Mappings, 0);
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = '}') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              FieldName := JReadString(JSON, P);
              JSkipWS(JSON, P);
              if JSON[P] = ':' then
                Inc(P);
              JSkipWS(JSON, P);
              if FieldName = 'default' then
                DefaultVal := JReadString(JSON, P)
              else if FieldName = 'toggle' then
              begin
                Toggle := JReadString(JSON, P);
                // Only "backspace" enables backspace-to-toggle.
                // "none", "both", "repeat", and any unknown value are treated as fixed.
                ToggleOnBackspace := (Toggle = 'backspace');
              end
              else if FieldName = 'mappings' then
              begin
                if (P <= Length(JSON)) and (JSON[P] = '[') then
                  Inc(P);
                while P <= Length(JSON) do
                begin
                  JSkipWS(JSON, P);
                  if (P > Length(JSON)) or (JSON[P] = ']') then
                  begin
                    Inc(P);
                    break;
                  end;
                  if JSON[P] = ',' then
                  begin
                    Inc(P);
                    Continue;
                  end;
                  if JSON[P] = '{' then
                  begin
                    Inc(P);
                    SetLength(Mappings, Length(Mappings) + 1);
                    with Mappings[high(Mappings)] do
                    begin
                      Consonants := '';
                      Value := '';
                      Alt := '';
                      ToggleOnBackspace := False;
                      MatchMode := 0;
                      ProcessPhase := '';
                      while P <= Length(JSON) do
                      begin
                        JSkipWS(JSON, P);
                        if (P > Length(JSON)) or (JSON[P] = '}') then
                        begin
                          Inc(P);
                          break;
                        end;
                        if JSON[P] = ',' then
                        begin
                          Inc(P);
                          Continue;
                        end;
                        FieldName := JReadString(JSON, P);
                        JSkipWS(JSON, P);
                        if JSON[P] = ':' then
                          Inc(P);
                        JSkipWS(JSON, P);
                        if FieldName = 'consonants' then
                          Consonants := JReadString(JSON, P)
                        else if FieldName = 'value' then
                          Value := JReadString(JSON, P)
                        else if FieldName = 'alt' then
                          Alt := JReadString(JSON, P)
                        else if FieldName = 'toggle' then
                        begin
                          ToggleVal := JReadString(JSON, P);
                          // Only "backspace" enables backspace-to-toggle.
                          ToggleOnBackspace := (ToggleVal = 'backspace');
                        end
                        else if FieldName = 'matchMode' then
                        begin
                          if (P <= Length(JSON)) and (JSON[P] = '"') then
                            MatchMode := StrToIntDef(JReadString(JSON, P), 0)
                          else
                            MatchMode := JReadInt(JSON, P, 0);
                        end
                        else if FieldName = 'process' then
                          ProcessPhase := LowerCase(JReadString(JSON, P))
                        else
                          JSkipValue(JSON, P);
                      end;
                      Consonants := ProcessHexAndUnicode(Consonants);
                    end;
                  end
                  else
                    JSkipValue(JSON, P);
                end;
              end
              else
                JSkipValue(JSON, P);
            end;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'RfolaRules' then
    begin
      SetLength(RfolaRules, 0);
      if (P <= Length(JSON)) and (JSON[P] = '[') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = ']') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        if JSON[P] = '{' then
        begin
          Inc(P);
          SetLength(RfolaRules, Length(RfolaRules) + 1);
          with RfolaRules[high(RfolaRules)] do
          begin
            Consonants := '';
            Value := '';
            HalfValue := '';
            ReplaceLen := 2;
            ContextGroup := '';
            ContextReplaceLen := 0;
            ContextValue := '';
            RawValue := '';
            RawHalfValue := '';
            RawContextValue := '';
            Comment := '';
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = '}') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              FieldName := JReadString(JSON, P);
              JSkipWS(JSON, P);
              if JSON[P] = ':' then
                Inc(P);
              JSkipWS(JSON, P);
              if FieldName = 'consonants' then
                Consonants := JReadString(JSON, P)
              else if FieldName = 'value' then
              begin
                RawValue := JReadString(JSON, P);
                Value := RawValue;
              end
              else if FieldName = 'halfValue' then
              begin
                RawHalfValue := JReadString(JSON, P);
                HalfValue := RawHalfValue;
              end
              else if FieldName = 'replaceLen' then
                ReplaceLen := JReadInt(JSON, P, 2)
              else if FieldName = 'contextGroup' then
                ContextGroup := JReadString(JSON, P)
              else if FieldName = 'contextReplaceLen' then
                ContextReplaceLen := JReadInt(JSON, P, 0)
              else if FieldName = 'contextValue' then
              begin
                RawContextValue := JReadString(JSON, P);
                ContextValue := RawContextValue;
              end
              else if FieldName = 'Comment' then
                Comment := JReadString(JSON, P)
              else
                JSkipValue(JSON, P);
            end;
            Consonants := ProcessHexAndUnicode(Consonants);
            Value := ResolveValue(Value);
            if HalfValue <> '' then
              HalfValue := ResolveValue(HalfValue);
            if ContextValue <> '' then
              ContextValue := ResolveValue(ContextValue);
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'KarCorrections' then
    begin
      SetLength(KarCorrections, 0);
      if (P <= Length(JSON)) and (JSON[P] = '[') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = ']') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        if JSON[P] = '{' then
        begin
          Inc(P);
          SetLength(KarCorrections, Length(KarCorrections) + 1);
          with KarCorrections[high(KarCorrections)] do
          begin
            RawCharStr := '';
            CharStr := '';
            RawFromKar := '';
            FromKar := '';
            RawToKar := '';
            ToKar := '';
            Comment := '';
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = '}') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              FieldName := JReadString(JSON, P);
              JSkipWS(JSON, P);
              if JSON[P] = ':' then
                Inc(P);
              JSkipWS(JSON, P);
              if FieldName = 'char' then
                RawCharStr := JReadString(JSON, P)
              else if FieldName = 'from' then
                RawFromKar := JReadString(JSON, P)
              else if FieldName = 'to' then
                RawToKar := JReadString(JSON, P)
              else if (FieldName = 'Comment') or (FieldName = 'comment') then
                Comment := JReadString(JSON, P)
              else
                JSkipValue(JSON, P);
            end;
            CharStr := ResolveValue(RawCharStr);
            FromKar := ResolveValue(RawFromKar);
            ToKar := ResolveValue(RawToKar);
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'GroupKarCorrections' then
    begin
      if (P <= Length(JSON)) and (JSON[P] = '[') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = ']') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        if JSON[P] = '{' then
        begin
          Inc(P);
          GCorrGroup := '';
          GCorrFrom := '';
          GCorrTo := '';
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
            begin
              Inc(P);
              break;
            end;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            FieldName := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
            JSkipWS(JSON, P);
            if FieldName = 'group' then
              GCorrGroup := JReadString(JSON, P)
            else if FieldName = 'from' then
              GCorrFrom := JReadString(JSON, P)
            else if FieldName = 'to' then
              GCorrTo := JReadString(JSON, P)
            else
              JSkipValue(JSON, P);
          end;
          if (GCorrGroup <> '') and (GCorrFrom <> '') and (GCorrTo <> '') and (AnsiGroupMap <> nil) then
          begin
            if AnsiGroupMap.TryGetValue(GCorrGroup, GroupMembers) then
            begin
              for GCorrMember in GroupMembers do
              begin
                // 1. Main sequence (RFola + Kar)
                GCorrPair.Key := ResolveValue(GCorrMember + GCorrFrom);
                GCorrPair.Value := ResolveValue(GCorrMember + GCorrTo);
                if (GCorrPair.Key <> '') and (GCorrPair.Key <> GCorrPair.Value) then
                begin
                  SetLength(CustomPostReplacements, Length(CustomPostReplacements) + 1);
                  CustomPostReplacements[high(CustomPostReplacements)] := GCorrPair;
                end;

                // 2. Swapped sequence (Kar + RFola) - to match the swap in FinalTouch
                GCorrPair.Key := ResolveValue(GCorrFrom + GCorrMember);
                GCorrPair.Value := ResolveValue(GCorrTo + GCorrMember);
                if (GCorrPair.Key <> '') and (GCorrPair.Key <> GCorrPair.Value) then
                begin
                  SetLength(CustomPostReplacements, Length(CustomPostReplacements) + 1);
                  CustomPostReplacements[high(CustomPostReplacements)] := GCorrPair;
                end;
              end;
            end;
          end;
          SetLength(GroupKarCorrections, Length(GroupKarCorrections) + 1);
          GroupKarCorrections[high(GroupKarCorrections)].Group := GCorrGroup;
          GroupKarCorrections[high(GroupKarCorrections)].From := GCorrFrom;
          GroupKarCorrections[high(GroupKarCorrections)].To_ := GCorrTo;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else if Key = 'RaPhalaGroups' then
    begin
      if AnsiGroupMap = nil then
        AnsiGroupMap := TDictionary < string, TArray < string >>.Create
      else
        AnsiGroupMap.Clear;
      if AnsiGroupRawMap = nil then
        AnsiGroupRawMap := TDictionary < string, TArray < string >>.Create
      else
        AnsiGroupRawMap.Clear;
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        Key := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '[') then
        begin
          Inc(P);
          Items := TList<string>.Create;
          RawItems := TList<string>.Create;
          try
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = ']') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              RawStr := JReadString(JSON, P);
              Items.Add(ResolveValue(RawStr));
              RawItems.Add(RawStr);
            end;
            AnsiGroupMap.AddOrSetValue(Key, Items.ToArray);
            AnsiGroupRawMap.AddOrSetValue(Key, RawItems.ToArray);
          finally
            Items.Free;
            RawItems.Free;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;

    end
    else if Key = 'ConsonantGroups' then
    begin
      if ConsonantGroupMap = nil then
        ConsonantGroupMap := TDictionary < string, TArray < string >>.Create
      else
        ConsonantGroupMap.Clear;
      if ConsonantGroupRawMap = nil then
        ConsonantGroupRawMap := TDictionary < string, TArray < string >>.Create
      else
        ConsonantGroupRawMap.Clear;
      if (P <= Length(JSON)) and (JSON[P] = '{') then
        Inc(P)
      else
        Continue;
      while P <= Length(JSON) do
      begin
        JSkipWS(JSON, P);
        if (P > Length(JSON)) or (JSON[P] = '}') then
        begin
          Inc(P);
          break;
        end;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        Key := JReadString(JSON, P);
        JSkipWS(JSON, P);
        if JSON[P] = ':' then
          Inc(P);
        JSkipWS(JSON, P);
        if (P <= Length(JSON)) and (JSON[P] = '[') then
        begin
          Inc(P);
          Items := TList<string>.Create;
          RawItems := TList<string>.Create;
          try
            while P <= Length(JSON) do
            begin
              JSkipWS(JSON, P);
              if (P > Length(JSON)) or (JSON[P] = ']') then
              begin
                Inc(P);
                break;
              end;
              if JSON[P] = ',' then
              begin
                Inc(P);
                Continue;
              end;
              RawStr := JReadString(JSON, P);
              Items.Add(ResolveValue(RawStr));
              RawItems.Add(RawStr);
            end;
            ConsonantGroupMap.AddOrSetValue(Key, Items.ToArray);
            ConsonantGroupRawMap.AddOrSetValue(Key, RawItems.ToArray);
          finally
            Items.Free;
            RawItems.Free;
          end;
        end
        else
          JSkipValue(JSON, P);
      end;
    end
    else
      JSkipValue(JSON, P);
  end;

  // Sort replacement arrays by key length (longest first)
  if Length(CustomFullForms) > 0 then
    TArray.Sort<TReplacementPair>(CustomFullForms, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));
  if Length(CustomPreReplacements) > 0 then
    TArray.Sort<TReplacementPair>(CustomPreReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));
  if Length(CustomPostReplacements) > 0 then
    TArray.Sort<TReplacementPair>(CustomPostReplacements, TComparer<TReplacementPair>.Construct(
      function(const L, R: TReplacementPair): Integer
      begin
        Result := R.Key.Length - L.Key.Length;
      end));

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
      if Rec.VarType = avChar then
        Val := string(PChar(Rec.Ptr)^)
      else
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
  I:  Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for I := 0 to high(Pairs) do
    begin
      if I > 0 then
        SB.Append(',');
      SB.Append('{');
      SB.Append('"Key":"').Append(SmartEscape(Pairs[I].Key)).Append('",');
      SB.Append('"Value":"').Append(SmartEscape(Pairs[I].Value)).Append('",');
      SB.Append('"Comment":"').Append(JSONEscape(Pairs[I].Comment)).Append('"');
      SB.Append('}');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ =============================================================================== }

function IsGroupName(const S: string): Boolean;
var
  I: Integer;
begin
  Result := True;
  if S = '' then
    Exit(False);
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['a' .. 'z', 'A' .. 'Z', '0' .. '9', '_']) then
      Exit(False);
end;

function ValueToHexOrName(const S: string): string;
begin
  if IsGroupName(S) then
    Result := S
  else
    Result := SmartEscape(S);
end;

function HasUnicodeKeyCategory(const Category: string): Boolean;
begin
  Result := (Category <> 'FirstHalfForms') and (Category <> 'SecondHalfForms');
end;

{ =============================================================================== }

procedure ExportAnsiMapping(const Path: string);
var
  Lines:               TStringList;
  SB:                  TStringBuilder;
  CatSB:               TStringBuilder;
  CategoryOrder:       TList<string>;
  CatEntries:          TDictionary<string, TStringBuilder>;
  I, J, K:             Integer;
  Val:                 string;
  Rec, MapRec:         TAnsiVarRec;
  CatName, KarCharHex: string;
  Arr:                 TArray<string>;
begin
  EnsureAnsiRegistry;
  EnsureAnsiOverrides;
  CategoryOrder := TList<string>.Create;
  CatEntries := TDictionary<string, TStringBuilder>.Create;
  Lines := TStringList.Create;
  try
    for Rec in AnsiRegistry do
    begin
      MapRec := Rec;
      AnsiRegistryMap.TryGetValue(Rec.Name, MapRec);

      Val := GetAnsiVarValue(MapRec.Name);

      if not CatEntries.ContainsKey(MapRec.Category) then
      begin
        CatEntries.Add(MapRec.Category, TStringBuilder.Create);
        CategoryOrder.Add(MapRec.Category);
      end;

      CatSB := CatEntries[MapRec.Category];
      if CatSB.Length > 0 then
        CatSB.Append(',');

      CatSB.Append('"').Append(MapRec.Name).Append('":{');

      if HasUnicodeKeyCategory(MapRec.Category) and (MapRec.BengaliChar <> '') then
        CatSB.Append('"UnicodeKey":"').Append(SmartEscape(MapRec.BengaliChar)).Append('",');

      CatSB.Append('"Value":"').Append(SmartEscape(Val)).Append('",');
      CatSB.Append('"Comment":"').Append(JSONEscape(MapRec.Comment)).Append('"');
      CatSB.Append('}');
    end;

    SB := TStringBuilder.Create;
    try
      SB.Append('{');

      SB.Append('"Constants":{');
      for I := 0 to CategoryOrder.Count - 1 do
      begin
        if I > 0 then
          SB.Append(',');
        CatName := CategoryOrder[I];
        CatSB := CatEntries[CatName];
        SB.Append('"').Append(CatName).Append('":{');
        SB.Append(CatSB.ToString);
        SB.Append('}');
      end;
      SB.Append('}');

      if Length(CustomFullForms) > 0 then
        SB.Append(',"FullFormReplacements":').Append(MakeJSONArrOfReplPairs(CustomFullForms))
      else
        SB.Append(',"FullFormReplacements":').Append(MakeJSONArrOfReplPairs(GetDefaultFullForms));
      SB.Append(',"PreReplacements":').Append(MakeJSONArrOfReplPairs(CustomPreReplacements));
      SB.Append(',"PostReplacements":').Append(MakeJSONArrOfReplPairs(CustomPostReplacements));

      if Length(VowelRules) > 0 then
      begin
        SB.Append(',"VowelRules":{');
        for I := 0 to high(VowelRules) do
        begin
          if I > 0 then
            SB.Append(',');
          KarCharHex := SmartEscape(VowelRules[I].KarChar);
          SB.Append('"').Append(KarCharHex).Append('":{');
          SB.Append('"default":"').Append(VowelRules[I].DefaultVal).Append('"');
          if VowelRules[I].Toggle <> 'none' then
            SB.Append(',"toggle":"').Append(VowelRules[I].Toggle).Append('"');
          SB.Append(',"mappings":[');
          for J := 0 to high(VowelRules[I].Mappings) do
          begin
            if J > 0 then
              SB.Append(',');
            SB.Append('{');
            SB.Append('"consonants":"').Append(ValueToHexOrName(VowelRules[I].Mappings[J].Consonants)).Append('"');
            SB.Append(',"value":"').Append(VowelRules[I].Mappings[J].Value).Append('"');
            if VowelRules[I].Mappings[J].Alt <> '' then
              SB.Append(',"alt":"').Append(VowelRules[I].Mappings[J].Alt).Append('"');
            if VowelRules[I].Mappings[J].ToggleOnBackspace then
              SB.Append(',"toggle":"backspace"');
            if VowelRules[I].Mappings[J].ProcessPhase <> '' then
              SB.Append(',"process":"').Append(VowelRules[I].Mappings[J].ProcessPhase).Append('"');
            SB.Append(',"matchMode":').Append(IntToStr(VowelRules[I].Mappings[J].MatchMode));
            SB.Append('}');
          end;
          SB.Append(']');
          SB.Append('}');
        end;
        SB.Append('}');
      end;

      if (AnsiGroupRawMap <> nil) and (AnsiGroupRawMap.Count > 0) then
      begin
        SB.Append(',"RaPhalaGroups":{');
        K := 0;
        for CatName in AnsiGroupRawMap.Keys do
        begin
          if K > 0 then
            SB.Append(',');
          SB.Append('"').Append(CatName).Append('":[');
          Arr := AnsiGroupRawMap[CatName];
          for J := 0 to high(Arr) do
          begin
            if J > 0 then
              SB.Append(',');
            SB.Append('"').Append(Arr[J]).Append('"');
          end;
          SB.Append(']');
          Inc(K);
        end;
        SB.Append('}');
      end
      else if (AnsiGroupMap <> nil) and (AnsiGroupMap.Count > 0) then
      begin
        SB.Append(',"RaPhalaGroups":{');
        K := 0;
        for CatName in AnsiGroupMap.Keys do
        begin
          if K > 0 then
            SB.Append(',');
          SB.Append('"').Append(CatName).Append('":[');
          Arr := AnsiGroupMap[CatName];
          for J := 0 to high(Arr) do
          begin
            if J > 0 then
              SB.Append(',');
            SB.Append('"').Append(ValueToHexOrName(Arr[J])).Append('"');
          end;
          SB.Append(']');
          Inc(K);
        end;
        SB.Append('}');
      end;

      SB.Append(',"GroupKarCorrections":[');
      for I := 0 to Length(GroupKarCorrections) - 1 do
      begin
        if I > 0 then
          SB.Append(',');
        SB.Append('{');
        SB.Append('"group":"').Append(GroupKarCorrections[I].Group).Append('",');
        SB.Append('"from":"').Append(JSONEscape(GroupKarCorrections[I].From)).Append('",');
        SB.Append('"to":"').Append(JSONEscape(GroupKarCorrections[I].To_)).Append('"');
        SB.Append('}');
      end;
      SB.Append(']');

      if (ConsonantGroupRawMap <> nil) and (ConsonantGroupRawMap.Count > 0) then
      begin
        SB.Append(',"ConsonantGroups":{');
        K := 0;
        for CatName in ConsonantGroupRawMap.Keys do
        begin
          if K > 0 then
            SB.Append(',');
          SB.Append('"').Append(CatName).Append('":[');
          Arr := ConsonantGroupRawMap[CatName];
          for J := 0 to high(Arr) do
          begin
            if J > 0 then
              SB.Append(',');
            SB.Append('"').Append(Arr[J]).Append('"');
          end;
          SB.Append(']');
          Inc(K);
        end;
        SB.Append('}');
      end
      else if (ConsonantGroupMap <> nil) and (ConsonantGroupMap.Count > 0) then
      begin
        SB.Append(',"ConsonantGroups":{');
        K := 0;
        for CatName in ConsonantGroupMap.Keys do
        begin
          if K > 0 then
            SB.Append(',');
          SB.Append('"').Append(CatName).Append('":[');
          Arr := ConsonantGroupMap[CatName];
          for J := 0 to high(Arr) do
          begin
            if J > 0 then
              SB.Append(',');
            SB.Append('"').Append(ValueToHexOrName(Arr[J])).Append('"');
          end;
          SB.Append(']');
          Inc(K);
        end;
        SB.Append('}');
      end;

      if Length(RfolaRules) > 0 then
      begin
        SB.Append(',"RfolaRules":[');
        for I := 0 to high(RfolaRules) do
        begin
          if I > 0 then
            SB.Append(',');
          SB.Append('{');
          SB.Append('"consonants":"').Append(ValueToHexOrName(RfolaRules[I].Consonants)).Append('",');
          if RfolaRules[I].RawValue <> '' then
            SB.Append('"value":"').Append(RfolaRules[I].RawValue).Append('"')
          else
            SB.Append('"value":"').Append(SmartEscape(RfolaRules[I].Value)).Append('"');
          if RfolaRules[I].HalfValue <> '' then
          begin
            if RfolaRules[I].RawHalfValue <> '' then
              SB.Append(',"halfValue":"').Append(RfolaRules[I].RawHalfValue).Append('"')
            else
              SB.Append(',"halfValue":"').Append(SmartEscape(RfolaRules[I].HalfValue)).Append('"');
          end;
          if RfolaRules[I].ReplaceLen > 0 then
            SB.Append(',"replaceLen":').Append(IntToStr(RfolaRules[I].ReplaceLen));
          if RfolaRules[I].ContextGroup <> '' then
            SB.Append(',"contextGroup":"').Append(RfolaRules[I].ContextGroup).Append('"');
          if RfolaRules[I].ContextReplaceLen > 0 then
            SB.Append(',"contextReplaceLen":').Append(IntToStr(RfolaRules[I].ContextReplaceLen));
          if RfolaRules[I].ContextValue <> '' then
          begin
            if RfolaRules[I].RawContextValue <> '' then
              SB.Append(',"contextValue":"').Append(RfolaRules[I].RawContextValue).Append('"')
            else
              SB.Append(',"contextValue":"').Append(SmartEscape(RfolaRules[I].ContextValue)).Append('"');
          end;
          if RfolaRules[I].Comment <> '' then
            SB.Append(',"Comment":"').Append(JSONEscape(RfolaRules[I].Comment)).Append('"');
          SB.Append('}');
        end;
        SB.Append(']');
      end;

      if Length(KarCorrections) > 0 then
      begin
        SB.Append(',"KarCorrections":[');
        for I := 0 to high(KarCorrections) do
        begin
          if I > 0 then
            SB.Append(',');
          SB.Append('{');
          if KarCorrections[I].RawCharStr <> '' then
            SB.Append('"char":"').Append(JSONEscape(KarCorrections[I].RawCharStr)).Append('",')
          else
            SB.Append('"char":"').Append(JSONEscape(KarCorrections[I].CharStr)).Append('",');
          if KarCorrections[I].RawFromKar <> '' then
            SB.Append('"from":"').Append(JSONEscape(KarCorrections[I].RawFromKar)).Append('",')
          else
            SB.Append('"from":"').Append(JSONEscape(KarCorrections[I].FromKar)).Append('",');
          if KarCorrections[I].RawToKar <> '' then
            SB.Append('"to":"').Append(JSONEscape(KarCorrections[I].RawToKar)).Append('"')
          else
            SB.Append('"to":"').Append(JSONEscape(KarCorrections[I].ToKar)).Append('"');
          if KarCorrections[I].Comment <> '' then
            SB.Append(',"Comment":"').Append(JSONEscape(KarCorrections[I].Comment)).Append('"');
          SB.Append('}');
        end;
        SB.Append(']');
      end;

      SB.Append('}');

      Lines.Text := JSONPrettyPrint(SB.ToString);
      Lines.SaveToFile(Path, TEncoding.UTF8);
    finally
      SB.Free;
    end;
  finally
    for CatName in CategoryOrder do
      if CatEntries.ContainsKey(CatName) then
        CatEntries[CatName].Free;
    CatEntries.Free;
    CategoryOrder.Free;
    Lines.Free;
  end;
end;

{ =============================================================================== }

function ValidateAnsiMappingFile(const Path: string; out ErrorMessage: string): Boolean;
const
  REPL_SECTIONS: array [0 .. 2] of string = ('FullFormReplacements', 'PreReplacements', 'PostReplacements');
var
  JSON:         string;
  Lines:        TStringList;
  P:            Integer;
  Key:          string;
  ArrIdx:       Integer;
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
    if (P > Length(JSON)) or (JSON[P] = '}') then
      break;
    if JSON[P] = ',' then
    begin
      Inc(P);
      Continue;
    end;

    Key := JReadString(JSON, P);
    JSkipWS(JSON, P);
    if (P <= Length(JSON)) and (JSON[P] = ':') then
      Inc(P);
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
        if (P > Length(JSON)) or (JSON[P] = ']') then
          break;
        if JSON[P] = ',' then
        begin
          Inc(P);
          Continue;
        end;
        if JSON[P] = '{' then
        begin
          Inc(P);
          // Check for Key and Value fields
          while P <= Length(JSON) do
          begin
            JSkipWS(JSON, P);
            if (P > Length(JSON)) or (JSON[P] = '}') then
              break;
            if JSON[P] = ',' then
            begin
              Inc(P);
              Continue;
            end;
            Key := JReadString(JSON, P);
            JSkipWS(JSON, P);
            if JSON[P] = ':' then
              Inc(P);
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

EnsureAnsiRegistry;
EnsureAnsiOverrides;

finalization

AnsiRegistry.Free;
AnsiRegistryMap.Free;
AnsiOverrides.Free;
AnsiGroupMap.Free;
AnsiGroupRawMap.Free;
ConsonantGroupMap.Free;
ConsonantGroupRawMap.Free;

end.
