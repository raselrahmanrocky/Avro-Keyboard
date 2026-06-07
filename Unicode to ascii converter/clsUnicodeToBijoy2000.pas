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
  System.Classes;

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

var
  CustomFullForms: array of TReplacementPair;
  CustomPreReplacements: array of TReplacementPair;
  CustomPostReplacements: array of TReplacementPair; 
  AnsiVersion: string = 'Default';
  AnsiMappingDir: string = '';

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
  System.SysUtils,
  System.Generics.Collections;

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
  A_T_UKar_2H: Char = #$7A;   //
  A_Th_2H: Char     = #$2019; //
  A_K_2H: Char      = #$2039; //
  A_L_2H_3: Char    = #$AC;   //

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

  // Applying dynamic post-processing fixes
  for I := 0 to Length(CustomPostReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPostReplacements[I].Key, CustomPostReplacements[I].Value);

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
end;

procedure TUnicodeToBijoy2000.ReplaceFullForms;
var
  I: Integer;
begin
  { Apply custom full form overrides }
  for I := 0 to Length(CustomFullForms) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomFullForms[I].Key, CustomFullForms[I].Value);

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
  begin
    fRaUKarToggle := True;
  end;

    if (fLastUniText = b_r + b_UUKar) and (UniText = b_r) then
  begin
    fRaUUKarToggle := True;
  end;

  if (Pos(' ', UniText) > 0) then
    fRaUKarToggle := False;
    fLastUniText := UniText;
    fLastUniText := UniText;

  fUniText := UniText;
  fConvertedText := fUniText;
  DeNormalize;
  
  // Applying dynamic pre-placement fixes
  for I := 0 to Length(CustomPreReplacements) - 1 do
    fConvertedText := ReplaceStr(fConvertedText, CustomPreReplacements[I].Key, CustomPreReplacements[I].Value);

  ReArrangeKars;
  ReplaceFullForms;
  ReArrangeReph;
  ReplaceKarsVowels;
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
  fConvertedText := ReplaceStr(fConvertedText, string('‘'), A_StartDoubleQuote);
  fConvertedText := ReplaceStr(fConvertedText, string('’'), A_EndDoubleQuote);
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
      if BaseLineRightCharacter(fConvertedText[I - 1]) = True then
      begin

        if fConvertedText[I - 1] = b_r then
        begin
          if fRaUKarToggle then
          fConvertedText[I] := A_UKar2
        else
          fConvertedText[I] := A_UKar4;
        end
        else if fConvertedText[I - 1] = b_L then
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
        { Else
          fConvertedText[I] := A_UKar2; }

      end
      else
      begin
        if ((fConvertedText[I - 1] = b_rr) or (fConvertedText[I - 1] = b_rrh)) then
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
      if BaseLineRightCharacter(fConvertedText[I - 1]) = True then
      begin
        if fConvertedText[I - 1] = b_r then
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
        else if fConvertedText[I - 1] = b_L then
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
  begin
    case C of
      '\': Result := Result + '\\';
      '"': Result := Result + '\"';
      #$08: Result := Result + '\b';
      #$09: Result := Result + '\t';
      #$0A: Result := Result + '\n';
      #$0C: Result := Result + '\f';
      #$0D: Result := Result + '\r';
    else
      if (Ord(C) < 32) or (Ord(C) > 126) then
        Result := Result + '#$' + IntToHex(Ord(C), 4)
      else
        Result := Result + C;
    end;
  end;
end;

{ =============================================================================== }

procedure ResetAnsiToDefaults;
begin
  { Numbers }
  A_0 := #$30;
  A_1 := #$31;
  A_2 := #$32;
  A_3 := #$33;
  A_4 := #$34;
  A_5 := #$35;
  A_6 := #$36;
  A_7 := #$37;
  A_8 := #$38;
  A_9 := #$39;

  { Vowels and Kars }
  A_A       := #$41;
  A_AA      := #$41#$76;
  A_AAKar   := #$76;
  A_I       := #$42;
  A_IKar    := #$77;
  A_II      := #$43;
  A_IIKar   := #$78;
  A_U       := #$44;
  A_UKar2   := #$79;
  A_UKar1   := #$7A;
  A_UKar3   := #$AD;
  A_UKar4   := #$E6;
  A_UU      := #$45;
  A_UUKar2  := #$7E;
  A_UUKar1  := #$201A;
  A_UUKar3  := #$192;
  A_RRI     := #$46;
  A_RRIKar1 := #$201E;
  A_RRIKar2 := #$2026;
  A_E       := #$47;
  A_EKar1   := #$2020;
  A_EKar2   := #$2021;
  A_OI      := #$48;
  A_OIKar1  := #$2C6;
  A_OIKar2  := #$2030;
  A_O       := #$49;
  A_OU      := #$4A;
  A_OUKar   := #$160;

  { Symbols }
  A_Taka             := #$24;
  A_Dari             := #$7C;
  A_DoubleDanda      := #$5C;
  A_Hasanta          := #$26;
  A_StartDoubleQuote := #$D2;
  A_EndDoubleQuote   := #$D3;

  { Consonants }
  A_K        := #$4B;
  A_Kh       := #$4C;
  A_G        := #$4D;
  A_Gh       := #$4E;
  A_NGA      := #$4F;
  A_C        := #$50;
  A_Ch       := #$51;
  A_J        := #$52;
  A_Jh       := #$53;
  A_NYA      := #$54;
  A_Tt       := #$55;
  A_Tth      := #$56;
  A_Dd       := #$57;
  A_Ddh      := #$58;
  A_Nn       := #$59;
  A_T        := #$5A;
  A_Th       := #$5F;
  A_D        := #$60;
  A_Dh       := #$61;
  A_N        := #$62;
  A_P        := #$63;
  A_Ph       := #$64;
  A_B        := #$65;
  A_Bh       := #$66;
  A_M        := #$67;
  A_Z        := #$68;
  A_R        := #$69;
  A_L        := #$6A;
  A_Sh       := #$6B;
  A_SS       := #$6C;
  A_S        := #$6D;
  A_H        := #$6E;
  A_RR       := #$6F;
  A_RRH      := #$70;
  A_Y        := #$71;
  A_Khandata := #$72;
  A_Anushar  := #$73;
  A_Bisharga := #$74;
  A_Chandra  := #$75;

  { Full Forms }
  A_K_K      := #$B0;
  A_K_Tt     := #$B1;
  A_K_Ss_M   := #$B2;
  A_K_T      := #$B3;
  A_K_M      := #$B4;
  A_K_R      := #$B5;
  A_K_Ss     := #$B6;
  A_K_S      := #$B7;
  A_G_Ukar   := #$B8;
  A_G_G      := #$B9;
  A_G_D      := #$BA;
  A_G_Dh     := #$BB;
  A_NGA_K    := #$BC;
  A_NGA_G    := #$BD;
  A_J_J      := #$BE;
  A_J_Jh     := #$C0;
  A_J_NYA    := #$C1;
  A_NYA_C    := #$C2;
  A_NYA_CH   := #$C3;
  A_NYA_J    := #$C4;
  A_NYA_Jh   := #$C5;
  A_Tt_Tt    := #$C6;
  A_Dd_Dd    := #$C7;
  A_Nn_Tt    := #$C8;
  A_Nn_Tth   := #$C9;
  A_NN_Dd    := #$CA;
  A_T_T      := #$CB;
  A_T_Th     := #$CC;
  A_T_M      := #$CD;
  A_T_R      := #$CE;
  A_D_D      := #$CF;
  A_D_Dh     := #$D7;
  A_D_B      := #$D8;
  A_D_M      := #$D9;
  A_N_Tth    := #$DA;
  A_N_Dd     := #$DB;
  A_N_Dh     := #$DC;
  A_N_S      := #$DD;
  A_P_Tt     := #$DE;
  A_P_T      := #$DF;
  A_P_P      := #$E0;
  A_P_S      := #$E1;
  A_B_J      := #$E2;
  A_B_D      := #$E3;
  A_B_Dh     := #$E4;
  A_Bh_R     := #$E5;
  A_M_N      := #$E6;
  A_M_Ph     := #$E7;
  A_L_K      := #$E9;
  A_L_G      := #$EA;
  A_L_Tt     := #$EB;
  A_L_Dd     := #$EC;
  A_L_P      := #$ED;
  A_L_Ph     := #$EE;
  A_Sh_UKar  := #$EF;
  A_Sh_C     := #$F0;
  A_Sh_Ch    := #$F1;
  A_Ss_Nn    := #$F2;
  A_Ss_Tt    := #$F3;
  A_Ss_Tth   := #$F4;
  A_Ss_Ph    := #$F5;
  A_S_Kh     := #$F6;
  A_S_Tt     := #$F7;
  A_S_N      := #$F8;
  A_S_Ph     := #$F9;
  A_H_UKar   := #$FB;
  A_H_RRIKar := #$FC;
  A_H_N      := #$FD;
  A_H_M      := #$FE;
  A_Rr_G     := #$FF;

  { First Half forms }
  A_Reph   := #$A9;
  A_M_1H   := #$A4;
  A_Ss_1H  := #$AE;
  A_S_1H_1 := #$AF;
  A_N_1H_1 := #$161;
  A_S_1H_2 := #$2C9;
  A_D_1H_1 := #$2DC;
  A_C_1H   := #$201D;
  A_NGA_1H := #$2022;
  A_N_1H_2 := #$203A;
  A_D_1H_2 := #$2122;

  { Second Half forms }
  A_B_2H_1    := #$5E;
  A_B_2H_2    := #$A1;
  A_BH_2H     := #$A2;
  A_BH_R_2H   := #$A3;
  A_M_2H_1    := #$A5;
  A_B_2H_3    := #$A6;
  A_M_2H_2    := #$A7;
  A_ZFola     := #$A8;
  A_RFola_1   := #$AA;
  A_RFola_2   := #$AB;
  A_L_2H_1    := #$AC;
  A_L_2H_2    := #$AD;
  A_T_R_2H    := #$BF;
  A_RFola_3   := #$D6;
  A_Nn_2H_1   := #$E8;
  A_K_R_2H    := #$152;
  A_Nn_2H_2   := #$153;
  A_B_2H_4    := #$178;
  A_T_2H      := #$2014;
  A_T_UKar_2H := #$7A;
  A_Th_2H     := #$2019;
  A_K_2H      := #$2039;
  A_L_2H_3    := #$AC;

  SetLength(CustomFullForms, 0);
  SetLength(CustomPreReplacements, 0);
  SetLength(CustomPostReplacements, 0);
end;

{ =============================================================================== }

procedure LoadAnsiMapping(const Path: string; ErrorLog: TStringList = nil);
var
  JSON: TJSONObject;
  Constants: TJSONObject;
  FullForms, PreRep, PostRep: TJSONArray;
  I: Integer;
  Lines: TStringList;
  ConstName, ConstValue: string;
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

    if JSON.TryGetValue<TJSONObject>('Constants', Constants) then
    begin
      for I := 0 to Constants.Count - 1 do
      begin
        try
          ConstName := Constants.Pairs[I].JsonString.Value;
          ConstValue := Constants.Pairs[I].JsonValue.Value;
          ConstValue := ProcessHexAndUnicode(ConstValue);

          if ConstName = 'A_0' then A_0 := ConstValue[1]
          else if ConstName = 'A_1' then A_1 := ConstValue[1]
          else if ConstName = 'A_2' then A_2 := ConstValue[1]
          else if ConstName = 'A_3' then A_3 := ConstValue[1]
          else if ConstName = 'A_4' then A_4 := ConstValue[1]
          else if ConstName = 'A_5' then A_5 := ConstValue[1]
          else if ConstName = 'A_6' then A_6 := ConstValue[1]
          else if ConstName = 'A_7' then A_7 := ConstValue[1]
          else if ConstName = 'A_8' then A_8 := ConstValue[1]
          else if ConstName = 'A_9' then A_9 := ConstValue[1]
          else if ConstName = 'A_A' then A_A := ConstValue[1]
          else if ConstName = 'A_AA' then A_AA := ConstValue
          else if ConstName = 'A_AAKar' then A_AAKar := ConstValue[1]
          else if ConstName = 'A_I' then A_I := ConstValue[1]
          else if ConstName = 'A_IKar' then A_IKar := ConstValue[1]
          else if ConstName = 'A_II' then A_II := ConstValue[1]
          else if ConstName = 'A_IIKar' then A_IIKar := ConstValue[1]
          else if ConstName = 'A_U' then A_U := ConstValue[1]
          else if ConstName = 'A_UKar1' then A_UKar1 := ConstValue[1]
          else if ConstName = 'A_UKar2' then A_UKar2 := ConstValue[1]
          else if ConstName = 'A_UKar3' then A_UKar3 := ConstValue[1]
          else if ConstName = 'A_UKar4' then A_UKar4 := ConstValue[1]
          else if ConstName = 'A_UU' then A_UU := ConstValue[1]
          else if ConstName = 'A_UUKar1' then A_UUKar1 := ConstValue[1]
          else if ConstName = 'A_UUKar2' then A_UUKar2 := ConstValue[1]
          else if ConstName = 'A_UUKar3' then A_UUKar3 := ConstValue[1]
          else if ConstName = 'A_RRI' then A_RRI := ConstValue[1]
          else if ConstName = 'A_RRIKar1' then A_RRIKar1 := ConstValue[1]
          else if ConstName = 'A_RRIKar2' then A_RRIKar2 := ConstValue[1]
          else if ConstName = 'A_E' then A_E := ConstValue[1]
          else if ConstName = 'A_EKar1' then A_EKar1 := ConstValue[1]
          else if ConstName = 'A_EKar2' then A_EKar2 := ConstValue[1]
          else if ConstName = 'A_OI' then A_OI := ConstValue[1]
          else if ConstName = 'A_OIKar1' then A_OIKar1 := ConstValue[1]
          else if ConstName = 'A_OIKar2' then A_OIKar2 := ConstValue[1]
          else if ConstName = 'A_O' then A_O := ConstValue[1]
          else if ConstName = 'A_OU' then A_OU := ConstValue[1]
          else if ConstName = 'A_OUKar' then A_OUKar := ConstValue[1]
          else if ConstName = 'A_Taka' then A_Taka := ConstValue[1]
          else if ConstName = 'A_Dari' then A_Dari := ConstValue[1]
          else if ConstName = 'A_DoubleDanda' then A_DoubleDanda := ConstValue[1]
          else if ConstName = 'A_Hasanta' then A_Hasanta := ConstValue[1]
          else if ConstName = 'A_StartDoubleQuote' then A_StartDoubleQuote := ConstValue[1]
          else if ConstName = 'A_EndDoubleQuote' then A_EndDoubleQuote := ConstValue[1]
          else if ConstName = 'A_K' then A_K := ConstValue[1]
          else if ConstName = 'A_Kh' then A_Kh := ConstValue[1]
          else if ConstName = 'A_G' then A_G := ConstValue[1]
          else if ConstName = 'A_Gh' then A_Gh := ConstValue[1]
          else if ConstName = 'A_NGA' then A_NGA := ConstValue[1]
          else if ConstName = 'A_C' then A_C := ConstValue[1]
          else if ConstName = 'A_Ch' then A_Ch := ConstValue[1]
          else if ConstName = 'A_J' then A_J := ConstValue[1]
          else if ConstName = 'A_Jh' then A_Jh := ConstValue[1]
          else if ConstName = 'A_NYA' then A_NYA := ConstValue[1]
          else if ConstName = 'A_Tt' then A_Tt := ConstValue[1]
          else if ConstName = 'A_Tth' then A_Tth := ConstValue[1]
          else if ConstName = 'A_Dd' then A_Dd := ConstValue[1]
          else if ConstName = 'A_Ddh' then A_Ddh := ConstValue[1]
          else if ConstName = 'A_Nn' then A_Nn := ConstValue[1]
          else if ConstName = 'A_T' then A_T := ConstValue[1]
          else if ConstName = 'A_Th' then A_Th := ConstValue[1]
          else if ConstName = 'A_D' then A_D := ConstValue[1]
          else if ConstName = 'A_Dh' then A_Dh := ConstValue[1]
          else if ConstName = 'A_N' then A_N := ConstValue[1]
          else if ConstName = 'A_P' then A_P := ConstValue[1]
          else if ConstName = 'A_Ph' then A_Ph := ConstValue[1]
          else if ConstName = 'A_B' then A_B := ConstValue[1]
          else if ConstName = 'A_Bh' then A_Bh := ConstValue[1]
          else if ConstName = 'A_M' then A_M := ConstValue[1]
          else if ConstName = 'A_Z' then A_Z := ConstValue[1]
          else if ConstName = 'A_R' then A_R := ConstValue[1]
          else if ConstName = 'A_L' then A_L := ConstValue[1]
          else if ConstName = 'A_Sh' then A_Sh := ConstValue[1]
          else if ConstName = 'A_SS' then A_SS := ConstValue[1]
          else if ConstName = 'A_S' then A_S := ConstValue[1]
          else if ConstName = 'A_H' then A_H := ConstValue[1]
          else if ConstName = 'A_RR' then A_RR := ConstValue[1]
          else if ConstName = 'A_RRH' then A_RRH := ConstValue[1]
          else if ConstName = 'A_Y' then A_Y := ConstValue[1]
          else if ConstName = 'A_Khandata' then A_Khandata := ConstValue[1]
          else if ConstName = 'A_Anushar' then A_Anushar := ConstValue[1]
          else if ConstName = 'A_Bisharga' then A_Bisharga := ConstValue[1]
          else if ConstName = 'A_Chandra' then A_Chandra := ConstValue[1]
          else if ConstName = 'A_K_K' then A_K_K := ConstValue[1]
          else if ConstName = 'A_K_Tt' then A_K_Tt := ConstValue[1]
          else if ConstName = 'A_K_Ss_M' then A_K_Ss_M := ConstValue[1]
          else if ConstName = 'A_K_T' then A_K_T := ConstValue[1]
          else if ConstName = 'A_K_M' then A_K_M := ConstValue[1]
          else if ConstName = 'A_K_R' then A_K_R := ConstValue[1]
          else if ConstName = 'A_K_Ss' then A_K_Ss := ConstValue[1]
          else if ConstName = 'A_K_S' then A_K_S := ConstValue[1]
          else if ConstName = 'A_G_Ukar' then A_G_Ukar := ConstValue[1]
          else if ConstName = 'A_G_G' then A_G_G := ConstValue[1]
          else if ConstName = 'A_G_D' then A_G_D := ConstValue[1]
          else if ConstName = 'A_G_Dh' then A_G_Dh := ConstValue[1]
          else if ConstName = 'A_NGA_K' then A_NGA_K := ConstValue[1]
          else if ConstName = 'A_NGA_G' then A_NGA_G := ConstValue[1]
          else if ConstName = 'A_J_J' then A_J_J := ConstValue[1]
          else if ConstName = 'A_J_Jh' then A_J_Jh := ConstValue[1]
          else if ConstName = 'A_J_NYA' then A_J_NYA := ConstValue[1]
          else if ConstName = 'A_NYA_C' then A_NYA_C := ConstValue[1]
          else if ConstName = 'A_NYA_CH' then A_NYA_CH := ConstValue[1]
          else if ConstName = 'A_NYA_J' then A_NYA_J := ConstValue[1]
          else if ConstName = 'A_NYA_Jh' then A_NYA_Jh := ConstValue[1]
          else if ConstName = 'A_Tt_Tt' then A_Tt_Tt := ConstValue[1]
          else if ConstName = 'A_Dd_Dd' then A_Dd_Dd := ConstValue[1]
          else if ConstName = 'A_Nn_Tt' then A_Nn_Tt := ConstValue[1]
          else if ConstName = 'A_Nn_Tth' then A_Nn_Tth := ConstValue[1]
          else if ConstName = 'A_NN_Dd' then A_NN_Dd := ConstValue[1]
          else if ConstName = 'A_T_T' then A_T_T := ConstValue[1]
          else if ConstName = 'A_T_Th' then A_T_Th := ConstValue[1]
          else if ConstName = 'A_T_M' then A_T_M := ConstValue[1]
          else if ConstName = 'A_T_R' then A_T_R := ConstValue[1]
          else if ConstName = 'A_D_D' then A_D_D := ConstValue[1]
          else if ConstName = 'A_D_Dh' then A_D_Dh := ConstValue[1]
          else if ConstName = 'A_D_B' then A_D_B := ConstValue[1]
          else if ConstName = 'A_D_M' then A_D_M := ConstValue[1]
          else if ConstName = 'A_N_Tth' then A_N_Tth := ConstValue[1]
          else if ConstName = 'A_N_Dd' then A_N_Dd := ConstValue[1]
          else if ConstName = 'A_N_Dh' then A_N_Dh := ConstValue[1]
          else if ConstName = 'A_N_S' then A_N_S := ConstValue[1]
          else if ConstName = 'A_P_Tt' then A_P_Tt := ConstValue[1]
          else if ConstName = 'A_P_T' then A_P_T := ConstValue[1]
          else if ConstName = 'A_P_P' then A_P_P := ConstValue[1]
          else if ConstName = 'A_P_S' then A_P_S := ConstValue[1]
          else if ConstName = 'A_B_J' then A_B_J := ConstValue[1]
          else if ConstName = 'A_B_D' then A_B_D := ConstValue[1]
          else if ConstName = 'A_B_Dh' then A_B_Dh := ConstValue[1]
          else if ConstName = 'A_Bh_R' then A_Bh_R := ConstValue[1]
          else if ConstName = 'A_M_N' then A_M_N := ConstValue[1]
          else if ConstName = 'A_M_Ph' then A_M_Ph := ConstValue[1]
          else if ConstName = 'A_L_K' then A_L_K := ConstValue[1]
          else if ConstName = 'A_L_G' then A_L_G := ConstValue[1]
          else if ConstName = 'A_L_Tt' then A_L_Tt := ConstValue[1]
          else if ConstName = 'A_L_Dd' then A_L_Dd := ConstValue[1]
          else if ConstName = 'A_L_P' then A_L_P := ConstValue[1]
          else if ConstName = 'A_L_Ph' then A_L_Ph := ConstValue[1]
          else if ConstName = 'A_Sh_UKar' then A_Sh_UKar := ConstValue[1]
          else if ConstName = 'A_Sh_C' then A_Sh_C := ConstValue[1]
          else if ConstName = 'A_Sh_Ch' then A_Sh_Ch := ConstValue[1]
          else if ConstName = 'A_Ss_Nn' then A_Ss_Nn := ConstValue[1]
          else if ConstName = 'A_Ss_Tt' then A_Ss_Tt := ConstValue[1]
          else if ConstName = 'A_Ss_Tth' then A_Ss_Tth := ConstValue[1]
          else if ConstName = 'A_Ss_Ph' then A_Ss_Ph := ConstValue[1]
          else if ConstName = 'A_S_Kh' then A_S_Kh := ConstValue[1]
          else if ConstName = 'A_S_Tt' then A_S_Tt := ConstValue[1]
          else if ConstName = 'A_S_N' then A_S_N := ConstValue[1]
          else if ConstName = 'A_S_Ph' then A_S_Ph := ConstValue[1]
          else if ConstName = 'A_H_UKar' then A_H_UKar := ConstValue[1]
          else if ConstName = 'A_H_RRIKar' then A_H_RRIKar := ConstValue[1]
          else if ConstName = 'A_H_N' then A_H_N := ConstValue[1]
          else if ConstName = 'A_H_M' then A_H_M := ConstValue[1]
          else if ConstName = 'A_Rr_G' then A_Rr_G := ConstValue[1]
          else if ConstName = 'A_Reph' then A_Reph := ConstValue[1]
          else if ConstName = 'A_M_1H' then A_M_1H := ConstValue[1]
          else if ConstName = 'A_Ss_1H' then A_Ss_1H := ConstValue[1]
          else if ConstName = 'A_S_1H_1' then A_S_1H_1 := ConstValue[1]
          else if ConstName = 'A_N_1H_1' then A_N_1H_1 := ConstValue[1]
          else if ConstName = 'A_S_1H_2' then A_S_1H_2 := ConstValue[1]
          else if ConstName = 'A_D_1H_1' then A_D_1H_1 := ConstValue[1]
          else if ConstName = 'A_C_1H' then A_C_1H := ConstValue[1]
          else if ConstName = 'A_NGA_1H' then A_NGA_1H := ConstValue[1]
          else if ConstName = 'A_N_1H_2' then A_N_1H_2 := ConstValue[1]
          else if ConstName = 'A_D_1H_2' then A_D_1H_2 := ConstValue[1]
          else if ConstName = 'A_B_2H_1' then A_B_2H_1 := ConstValue[1]
          else if ConstName = 'A_B_2H_2' then A_B_2H_2 := ConstValue[1]
          else if ConstName = 'A_BH_2H' then A_BH_2H := ConstValue[1]
          else if ConstName = 'A_BH_R_2H' then A_BH_R_2H := ConstValue[1]
          else if ConstName = 'A_M_2H_1' then A_M_2H_1 := ConstValue[1]
          else if ConstName = 'A_B_2H_3' then A_B_2H_3 := ConstValue[1]
          else if ConstName = 'A_M_2H_2' then A_M_2H_2 := ConstValue[1]
          else if ConstName = 'A_ZFola' then A_ZFola := ConstValue[1]
          else if ConstName = 'A_RFola_1' then A_RFola_1 := ConstValue[1]
          else if ConstName = 'A_RFola_2' then A_RFola_2 := ConstValue[1]
          else if ConstName = 'A_L_2H_1' then A_L_2H_1 := ConstValue[1]
          else if ConstName = 'A_L_2H_2' then A_L_2H_2 := ConstValue[1]
          else if ConstName = 'A_T_R_2H' then A_T_R_2H := ConstValue[1]
          else if ConstName = 'A_RFola_3' then A_RFola_3 := ConstValue[1]
          else if ConstName = 'A_Nn_2H_1' then A_Nn_2H_1 := ConstValue[1]
          else if ConstName = 'A_K_R_2H' then A_K_R_2H := ConstValue[1]
          else if ConstName = 'A_Nn_2H_2' then A_Nn_2H_2 := ConstValue[1]
          else if ConstName = 'A_B_2H_4' then A_B_2H_4 := ConstValue[1]
          else if ConstName = 'A_T_2H' then A_T_2H := ConstValue[1]
          else if ConstName = 'A_T_UKar_2H' then A_T_UKar_2H := ConstValue[1]
          else if ConstName = 'A_Th_2H' then A_Th_2H := ConstValue[1]
          else if ConstName = 'A_K_2H' then A_K_2H := ConstValue[1]
          else if ConstName = 'A_L_2H_3' then A_L_2H_3 := ConstValue[1];
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in constant [' + ConstName + ']: ' + E.Message);
          end;
        end;
      end;
    end;

    SetLength(CustomFullForms, 0);
    if JSON.TryGetValue<TJSONArray>('FullFormReplacements', FullForms) then
    begin
      SetLength(CustomFullForms, FullForms.Count);
      for I := 0 to FullForms.Count - 1 do
      begin
        try
          CustomFullForms[I].Key := (FullForms.Items[I] as TJSONObject).GetValue('Key').Value;
          ConstValue := (FullForms.Items[I] as TJSONObject).GetValue('Value').Value;

          if not ValidateHexFormat(ConstValue) then
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Warning: Invalid Hex format in Key [' + CustomFullForms[I].Key + ']. Value: ' + ConstValue);
          end;

          CustomFullForms[I].Value := ProcessHexAndUnicode(ConstValue);
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in FullForm item ' + IntToStr(I + 1) + ': ' + E.Message);
          end;
        end;
      end;
    end;

    SetLength(CustomPreReplacements, 0);
    if JSON.TryGetValue<TJSONArray>('PreReplacements', PreRep) then
    begin
      SetLength(CustomPreReplacements, PreRep.Count);
      for I := 0 to PreRep.Count - 1 do
      begin
        try
          CustomPreReplacements[I].Key := (PreRep.Items[I] as TJSONObject).GetValue('Key').Value;
          ConstValue := (PreRep.Items[I] as TJSONObject).GetValue('Value').Value;
          CustomPreReplacements[I].Value := ProcessHexAndUnicode(ConstValue);
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in PreReplacements item ' + IntToStr(I + 1) + ': ' + E.Message);
          end;
        end;
      end;
    end;

    SetLength(CustomPostReplacements, 0);
    if JSON.TryGetValue<TJSONArray>('PostReplacements', PostRep) then
    begin
      SetLength(CustomPostReplacements, PostRep.Count);
      for I := 0 to PostRep.Count - 1 do
      begin
        try
          CustomPostReplacements[I].Key := (PostRep.Items[I] as TJSONObject).GetValue('Key').Value;
          ConstValue := (PostRep.Items[I] as TJSONObject).GetValue('Value').Value;
          CustomPostReplacements[I].Value := ProcessHexAndUnicode(ConstValue);
        except
          on E: Exception do
          begin
            if Assigned(ErrorLog) then
              ErrorLog.Add('Error in PostReplacements item ' + IntToStr(I + 1) + ': ' + E.Message);
          end;
        end;
      end;
    end;

  finally
    Lines.Free;
    if JSON <> nil then JSON.Free;
  end;
end;

{ =============================================================================== }

function GetDefaultFullFormsJSON: string;
begin
  Result :=
    '    {"Key": "ক্ক", "Value": "°"},' + sLineBreak +
    '    {"Key": "ক্ট", "Value": "±"},' + sLineBreak +
    '    {"Key": "ক্ত", "Value": "³"},' + sLineBreak +
    '    {"Key": "ক্ব", "Value": "K¡"},' + sLineBreak +
    '    {"Key": "ক্র", "Value": "µ"},' + sLineBreak +
    '    {"Key": "ক্ল", "Value": "K¬"},' + sLineBreak +
    '    {"Key": "ক্ষ", "Value": "¶"},' + sLineBreak +
    '    {"Key": "ক্স", "Value": "·"},' + sLineBreak +
    '    {"Key": "গ্ধ", "Value": "»"},' + sLineBreak +
    '    {"Key": "গ্ন", "Value": "Mœ"},' + sLineBreak +
    '    {"Key": "গ্ম", "Value": "M¥"},' + sLineBreak +
    '    {"Key": "গ্র", "Value": "MÖ"},' + sLineBreak +
    '    {"Key": "গ্ল", "Value": "Mø"},' + sLineBreak +
    '    {"Key": "ঙ্ক", "Value": "¼"},' + sLineBreak +
    '    {"Key": "ঙ্খ", "Value": "•L"},' + sLineBreak +
    '    {"Key": "ঙ্গ", "Value": "½"},' + sLineBreak +
    '    {"Key": "ঙ্ঘ", "Value": "•N"},' + sLineBreak +
    '    {"Key": "চ্চ", "Value": "”P"},' + sLineBreak +
    '    {"Key": "চ্ছ", "Value": "”Q"},' + sLineBreak +
    '    {"Key": "জ্জ", "Value": "¾"},' + sLineBreak +
    '    {"Key": "জ্ঝ", "Value": "À"},' + sLineBreak +
    '    {"Key": "জ্ঞ", "Value": "Á"},' + sLineBreak +
    '    {"Key": "জ্ব", "Value": "R¡"},' + sLineBreak +
    '    {"Key": "জ্র", "Value": "Rª"},' + sLineBreak +
    '    {"Key": "ঞ্চ", "Value": "Â"},' + sLineBreak +
    '    {"Key": "ঞ্ছ", "Value": "Ã"},' + sLineBreak +
    '    {"Key": "ঞ্জ", "Value": "Ä"},' + sLineBreak +
    '    {"Key": "ঞ্ঝ", "Value": "Å"},' + sLineBreak +
    '    {"Key": "ট্ট", "Value": "Æ"},' + sLineBreak +
    '    {"Key": "ট্ব", "Value": "U¡"},' + sLineBreak +
    '    {"Key": "ট্ম", "Value": "U¥"},' + sLineBreak +
    '    {"Key": "ট্র", "Value": "Uª"},' + sLineBreak +
    '    {"Key": "ড্ড", "Value": "Ç"},' + sLineBreak +
    '    {"Key": "ড্র", "Value": "Wª"},' + sLineBreak +
    '    {"Key": "ঢ্র", "Value": "Xª"},' + sLineBreak +
    '    {"Key": "ণ্ট", "Value": "È"},' + sLineBreak +
    '    {"Key": "ণ্ঠ", "Value": "É"},' + sLineBreak +
    '    {"Key": "ণ্ড", "Value": "Ð"},' + sLineBreak +
    '    {"Key": "ণ্ণ", "Value": "Yœ"},' + sLineBreak +
    '    {"Key": "ণ্ব", "Value": "Y¦"},' + sLineBreak +
    '    {"Key": "ত্ত", "Value": "Ë"},' + sLineBreak +
    '    {"Key": "ত্থ", "Value": "Ì"},' + sLineBreak +
    '    {"Key": "থ্ব", "Value": "_¡"},' + sLineBreak +
    '    {"Key": "ত্ন", "Value": "Zœ"},' + sLineBreak +
    '    {"Key": "ত্ম", "Value": "Z¥"},' + sLineBreak +
    '    {"Key": "ত্র", "Value": "Î"},' + sLineBreak +
    '    {"Key": "দ্দ", "Value": "Ï"},' + sLineBreak +
    '    {"Key": "দ্ধ", "Value": "×"},' + sLineBreak +
    '    {"Key": "দ্ব", "Value": "Ø"},' + sLineBreak +
    '    {"Key": "দ্ভ", "Value": "™¢"},' + sLineBreak +
    '    {"Key": "দ্ম", "Value": "Ù"},' + sLineBreak +
    '    {"Key": "দ্র", "Value": "`ª"},' + sLineBreak +
    '    {"Key": "ধ্ব", "Value": "aŸ"},' + sLineBreak +
    '    {"Key": "ধ্ম", "Value": "a¥"},' + sLineBreak +
    '    {"Key": "ন্ত", "Value": "šÍ"},' + sLineBreak +
    '    {"Key": "ন্থ", "Value": "š’"},' + sLineBreak +
    '    {"Key": "ন্দ", "Value": "›`"},' + sLineBreak +
    '    {"Key": "ন্ধ", "Value": "Ü"},' + sLineBreak +
    '    {"Key": "ন্ন", "Value": "bœ"},' + sLineBreak +
    '    {"Key": "ন্ম", "Value": "b¥"},' + sLineBreak +
    '    {"Key": "প্ট", "Value": "Þ"},' + sLineBreak +
    '    {"Key": "প্ত", "Value": "ß"},' + sLineBreak +
    '    {"Key": "প্প", "Value": "à"},' + sLineBreak +
    '    {"Key": "প্র", "Value": "cÖ"},' + sLineBreak +
    '    {"Key": "প্ল", "Value": "cø"},' + sLineBreak +
    '    {"Key": "প্স", "Value": "á"},' + sLineBreak +
    '    {"Key": "ব্জ", "Value": "â"},' + sLineBreak +
    '    {"Key": "ব্দ", "Value": "ã"},' + sLineBreak +
    '    {"Key": "ব্ধ", "Value": "ä"},' + sLineBreak +
    '    {"Key": "ব্ব", "Value": "eŸ"},' + sLineBreak +
    '    {"Key": "ব্র", "Value": "eª"},' + sLineBreak +
    '    {"Key": "ব্ল", "Value": "eø"},' + sLineBreak +
    '    {"Key": "ভ্র", "Value": "å"},' + sLineBreak +
    '    {"Key": "ম্ন", "Value": "gœ"},' + sLineBreak +
    '    {"Key": "ম্ফ", "Value": "ç"},' + sLineBreak +
    '    {"Key": "ম্ব", "Value": "¤^"},' + sLineBreak +
    '    {"Key": "ম্ভ", "Value": "¤¢"},' + sLineBreak +
    '    {"Key": "ম্ম", "Value": "¤§"},' + sLineBreak +
    '    {"Key": "ম্র", "Value": "gª"},' + sLineBreak +
    '    {"Key": "ল্ক", "Value": "é"},' + sLineBreak +
    '    {"Key": "ল্গ", "Value": "ê"},' + sLineBreak +
    '    {"Key": "ল্ট", "Value": "ë"},' + sLineBreak +
    '    {"Key": "ল্ড", "Value": "ì"},' + sLineBreak +
    '    {"Key": "ল্প", "Value": "í"},' + sLineBreak +
    '    {"Key": "ল্ব", "Value": "j¦"},' + sLineBreak +
    '    {"Key": "ল্ম", "Value": "j¥"},' + sLineBreak +
    '    {"Key": "ল্ল", "Value": "jø"},' + sLineBreak +
    '    {"Key": "শ্চ", "Value": "ð"},' + sLineBreak +
    '    {"Key": "শ্ন", "Value": "kœ"},' + sLineBreak +
    '    {"Key": "শ্ব", "Value": "k¦"},' + sLineBreak +
    '    {"Key": "শ্ম", "Value": "k¥"},' + sLineBreak +
    '    {"Key": "শ্ল", "Value": "kø"},' + sLineBreak +
    '    {"Key": "ষ্ক", "Value": "®‹"},' + sLineBreak +
    '    {"Key": "ষ্ট", "Value": "ó"},' + sLineBreak +
    '    {"Key": "ষ্ঠ", "Value": "ô"},' + sLineBreak +
    '    {"Key": "ষ্ণ", "Value": "ò"},' + sLineBreak +
    '    {"Key": "ষ্প", "Value": "®ú"},' + sLineBreak +
    '    {"Key": "ষ্ফ", "Value": "õ"},' + sLineBreak +
    '    {"Key": "ষ্ম", "Value": "®§"},' + sLineBreak +
    '    {"Key": "স্ক", "Value": "¯‹"},' + sLineBreak +
    '    {"Key": "স্খ", "Value": "ö"},' + sLineBreak +
    '    {"Key": "স্ট", "Value": "÷"},' + sLineBreak +
    '    {"Key": "স্ত", "Value": "¯Í"},' + sLineBreak +
    '    {"Key": "স্থ", "Value": "¯’"},' + sLineBreak +
    '    {"Key": "স্ন", "Value": "mœ"},' + sLineBreak +
    '    {"Key": "স্প", "Value": "¯ú"},' + sLineBreak +
    '    {"Key": "স্ফ", "Value": "ù"},' + sLineBreak +
    '    {"Key": "স্ব", "Value": "¯^"},' + sLineBreak +
    '    {"Key": "স্ম", "Value": "¯§"},' + sLineBreak +
    '    {"Key": "স্ল", "Value": "¯ø"},' + sLineBreak +
    '    {"Key": "হ্ণ", "Value": "nè"},' + sLineBreak +
    '    {"Key": "হ্ন", "Value": "ý"},' + sLineBreak +
    '    {"Key": "হ্ম", "Value": "þ"},' + sLineBreak +
    '    {"Key": "হ্ল", "Value": "n¬"},' + sLineBreak +
    '    {"Key": "হৃ", "Value": "ü"},' + sLineBreak +
    '    {"Key": "গু", "Value": "¸"},' + sLineBreak +
    '    {"Key": "শু", "Value": "ï"},' + sLineBreak +
    '    {"Key": "ক্ট্র", "Value": "³ª"},' + sLineBreak +
    '    {"Key": "ক্ন", "Value": "Kè"},' + sLineBreak +
    '    {"Key": "ক্ষ্ণ", "Value": "òœ"},' + sLineBreak +
    '    {"Key": "ক্ষ্ম", "Value": "²"},' + sLineBreak +
    '    {"Key": "ক্ষ্র", "Value": "ÿ«"},' + sLineBreak +
    '    {"Key": "গ্ব", "Value": "M¦"},' + sLineBreak +
    '    {"Key": "গ্র্য", "Value": "MÖ¨"},' + sLineBreak +
    '    {"Key": "য়ু", "Value": "qy"},' + sLineBreak +
    '    {"Key": "ঘ্ন", "Value": "Nœ"},' + sLineBreak +
    '    {"Key": "ঘ্র", "Value": "Nª"},' + sLineBreak +
    '    {"Key": "ঙ্গু", "Value": "½y"},' + sLineBreak +
    '    {"Key": "জ্জ্ব", "Value": "¾¡"},' + sLineBreak +
    '    {"Key": "ত্ত্ব", "Value": "Ë¡"},' + sLineBreak +
    '    {"Key": "ত্রু", "Value": "Îæ"},' + sLineBreak +
    '    {"Key": "দ্রু", "Value": "`ªæ"},' + sLineBreak +
    '    {"Key": "ভ্রু", "Value": "åæ"},' + sLineBreak +
    '    {"Key": "শ্রু", "Value": "kÖæ"},' + sLineBreak +
    '    {"Key": "য়ূ", "Value": "q~"},' + sLineBreak +
    '    {"Key": "ম্প", "Value": "¤ú"},' + sLineBreak +
    '    {"Key": "ক্য", "Value": "K¨"},' + sLineBreak +
    '    {"Key": "ল্যু", "Value": "j¨y"},' + sLineBreak +
    '    {"Key": "ক্লু", "Value": "K¬z"},' + sLineBreak +
    '    {"Key": "ত্র্য", "Value": "Î¨"},' + sLineBreak +
    '    {"Key": "স্থ্য", "Value": "¯’¨"},' + sLineBreak +
    '    {"Key": "দ্য", "Value": "`¨"},' + sLineBreak +
    '    {"Key": "ভ্য", "Value": "f¨"},' + sLineBreak +
    '    {"Key": "ল্য", "Value": "j¨"},' + sLineBreak +
    '    {"Key": "দ্যু", "Value": "`y¨"},' + sLineBreak +
    '    {"Key": "ম্য", "Value": "g¨"},' + sLineBreak +
    '    {"Key": "ন্য", "Value": "b¨"},' + sLineBreak +
    '    {"Key": "ণ্য", "Value": "Y¨"},' + sLineBreak +
    '    {"Key": "ব্যু", "Value": "ey¨"},' + sLineBreak +
    '    {"Key": "ত্ব", "Value": "Z¡"},' + sLineBreak +
    '    {"Key": "হ্ব", "Value": "nŸ"},' + sLineBreak +
    '    {"Key": "গ্নু", "Value": "Mœy"},' + sLineBreak +
    '    {"Key": "ম্প্ল", "Value": "¤úø"},' + sLineBreak +
    '    {"Key": "স্প্ল", "Value": "¯úø"},' + sLineBreak +
    '    {"Key": "চ্ব", "Value": "P¦"},' + sLineBreak +
    '    {"Key": "ড়্গ", "Value": "—M"}';
end;

{ =============================================================================== }

procedure ExportAnsiMapping(const Path: string);
var
  Lines: TStringList;

  procedure W(const S: string);
  begin
    Lines.Add(S);
  end;

  procedure WConstants;
  begin
    W('    "A_0": "' + SmartEscape(string(A_0)) + '",');
    W('    "A_1": "' + SmartEscape(string(A_1)) + '",');
    W('    "A_2": "' + SmartEscape(string(A_2)) + '",');
    W('    "A_3": "' + SmartEscape(string(A_3)) + '",');
    W('    "A_4": "' + SmartEscape(string(A_4)) + '",');
    W('    "A_5": "' + SmartEscape(string(A_5)) + '",');
    W('    "A_6": "' + SmartEscape(string(A_6)) + '",');
    W('    "A_7": "' + SmartEscape(string(A_7)) + '",');
    W('    "A_8": "' + SmartEscape(string(A_8)) + '",');
    W('    "A_9": "' + SmartEscape(string(A_9)) + '",');
    W('    "A_A": "' + SmartEscape(string(A_A)) + '",');
    W('    "A_AA": "' + SmartEscape(A_AA) + '",');
    W('    "A_AAKar": "' + SmartEscape(string(A_AAKar)) + '",');
    W('    "A_I": "' + SmartEscape(string(A_I)) + '",');
    W('    "A_IKar": "' + SmartEscape(string(A_IKar)) + '",');
    W('    "A_II": "' + SmartEscape(string(A_II)) + '",');
    W('    "A_IIKar": "' + SmartEscape(string(A_IIKar)) + '",');
    W('    "A_U": "' + SmartEscape(string(A_U)) + '",');
    W('    "A_UKar1": "' + SmartEscape(string(A_UKar1)) + '",');
    W('    "A_UKar2": "' + SmartEscape(string(A_UKar2)) + '",');
    W('    "A_UKar3": "' + SmartEscape(string(A_UKar3)) + '",');
    W('    "A_UKar4": "' + SmartEscape(string(A_UKar4)) + '",');
    W('    "A_UU": "' + SmartEscape(string(A_UU)) + '",');
    W('    "A_UUKar1": "' + SmartEscape(string(A_UUKar1)) + '",');
    W('    "A_UUKar2": "' + SmartEscape(string(A_UUKar2)) + '",');
    W('    "A_UUKar3": "' + SmartEscape(string(A_UUKar3)) + '",');
    W('    "A_RRI": "' + SmartEscape(string(A_RRI)) + '",');
    W('    "A_RRIKar1": "' + SmartEscape(string(A_RRIKar1)) + '",');
    W('    "A_RRIKar2": "' + SmartEscape(string(A_RRIKar2)) + '",');
    W('    "A_E": "' + SmartEscape(string(A_E)) + '",');
    W('    "A_EKar1": "' + SmartEscape(string(A_EKar1)) + '",');
    W('    "A_EKar2": "' + SmartEscape(string(A_EKar2)) + '",');
    W('    "A_OI": "' + SmartEscape(string(A_OI)) + '",');
    W('    "A_OIKar1": "' + SmartEscape(string(A_OIKar1)) + '",');
    W('    "A_OIKar2": "' + SmartEscape(string(A_OIKar2)) + '",');
    W('    "A_O": "' + SmartEscape(string(A_O)) + '",');
    W('    "A_OU": "' + SmartEscape(string(A_OU)) + '",');
    W('    "A_OUKar": "' + SmartEscape(string(A_OUKar)) + '",');
    W('    "A_Taka": "' + SmartEscape(string(A_Taka)) + '",');
    W('    "A_Dari": "' + SmartEscape(string(A_Dari)) + '",');
    W('    "A_DoubleDanda": "' + SmartEscape(string(A_DoubleDanda)) + '",');
    W('    "A_Hasanta": "' + SmartEscape(string(A_Hasanta)) + '",');
    W('    "A_StartDoubleQuote": "' + SmartEscape(string(A_StartDoubleQuote)) + '",');
    W('    "A_EndDoubleQuote": "' + SmartEscape(string(A_EndDoubleQuote)) + '",');
    W('    "A_K": "' + SmartEscape(string(A_K)) + '",');
    W('    "A_Kh": "' + SmartEscape(string(A_Kh)) + '",');
    W('    "A_G": "' + SmartEscape(string(A_G)) + '",');
    W('    "A_Gh": "' + SmartEscape(string(A_Gh)) + '",');
    W('    "A_NGA": "' + SmartEscape(string(A_NGA)) + '",');
    W('    "A_C": "' + SmartEscape(string(A_C)) + '",');
    W('    "A_Ch": "' + SmartEscape(string(A_Ch)) + '",');
    W('    "A_J": "' + SmartEscape(string(A_J)) + '",');
    W('    "A_Jh": "' + SmartEscape(string(A_Jh)) + '",');
    W('    "A_NYA": "' + SmartEscape(string(A_NYA)) + '",');
    W('    "A_Tt": "' + SmartEscape(string(A_Tt)) + '",');
    W('    "A_Tth": "' + SmartEscape(string(A_Tth)) + '",');
    W('    "A_Dd": "' + SmartEscape(string(A_Dd)) + '",');
    W('    "A_Ddh": "' + SmartEscape(string(A_Ddh)) + '",');
    W('    "A_Nn": "' + SmartEscape(string(A_Nn)) + '",');
    W('    "A_T": "' + SmartEscape(string(A_T)) + '",');
    W('    "A_Th": "' + SmartEscape(string(A_Th)) + '",');
    W('    "A_D": "' + SmartEscape(string(A_D)) + '",');
    W('    "A_Dh": "' + SmartEscape(string(A_Dh)) + '",');
    W('    "A_N": "' + SmartEscape(string(A_N)) + '",');
    W('    "A_P": "' + SmartEscape(string(A_P)) + '",');
    W('    "A_Ph": "' + SmartEscape(string(A_Ph)) + '",');
    W('    "A_B": "' + SmartEscape(string(A_B)) + '",');
    W('    "A_Bh": "' + SmartEscape(string(A_Bh)) + '",');
    W('    "A_M": "' + SmartEscape(string(A_M)) + '",');
    W('    "A_Z": "' + SmartEscape(string(A_Z)) + '",');
    W('    "A_R": "' + SmartEscape(string(A_R)) + '",');
    W('    "A_L": "' + SmartEscape(string(A_L)) + '",');
    W('    "A_Sh": "' + SmartEscape(string(A_Sh)) + '",');
    W('    "A_SS": "' + SmartEscape(string(A_SS)) + '",');
    W('    "A_S": "' + SmartEscape(string(A_S)) + '",');
    W('    "A_H": "' + SmartEscape(string(A_H)) + '",');
    W('    "A_RR": "' + SmartEscape(string(A_RR)) + '",');
    W('    "A_RRH": "' + SmartEscape(string(A_RRH)) + '",');
    W('    "A_Y": "' + SmartEscape(string(A_Y)) + '",');
    W('    "A_Khandata": "' + SmartEscape(string(A_Khandata)) + '",');
    W('    "A_Anushar": "' + SmartEscape(string(A_Anushar)) + '",');
    W('    "A_Bisharga": "' + SmartEscape(string(A_Bisharga)) + '",');
    W('    "A_Chandra": "' + SmartEscape(string(A_Chandra)) + '",');
    W('    "A_K_K": "' + SmartEscape(string(A_K_K)) + '",');
    W('    "A_K_Tt": "' + SmartEscape(string(A_K_Tt)) + '",');
    W('    "A_K_Ss_M": "' + SmartEscape(string(A_K_Ss_M)) + '",');
    W('    "A_K_T": "' + SmartEscape(string(A_K_T)) + '",');
    W('    "A_K_M": "' + SmartEscape(string(A_K_M)) + '",');
    W('    "A_K_R": "' + SmartEscape(string(A_K_R)) + '",');
    W('    "A_K_Ss": "' + SmartEscape(string(A_K_Ss)) + '",');
    W('    "A_K_S": "' + SmartEscape(string(A_K_S)) + '",');
    W('    "A_G_Ukar": "' + SmartEscape(string(A_G_Ukar)) + '",');
    W('    "A_G_G": "' + SmartEscape(string(A_G_G)) + '",');
    W('    "A_G_D": "' + SmartEscape(string(A_G_D)) + '",');
    W('    "A_G_Dh": "' + SmartEscape(string(A_G_Dh)) + '",');
    W('    "A_NGA_K": "' + SmartEscape(string(A_NGA_K)) + '",');
    W('    "A_NGA_G": "' + SmartEscape(string(A_NGA_G)) + '",');
    W('    "A_J_J": "' + SmartEscape(string(A_J_J)) + '",');
    W('    "A_J_Jh": "' + SmartEscape(string(A_J_Jh)) + '",');
    W('    "A_J_NYA": "' + SmartEscape(string(A_J_NYA)) + '",');
    W('    "A_NYA_C": "' + SmartEscape(string(A_NYA_C)) + '",');
    W('    "A_NYA_CH": "' + SmartEscape(string(A_NYA_CH)) + '",');
    W('    "A_NYA_J": "' + SmartEscape(string(A_NYA_J)) + '",');
    W('    "A_NYA_Jh": "' + SmartEscape(string(A_NYA_Jh)) + '",');
    W('    "A_Tt_Tt": "' + SmartEscape(string(A_Tt_Tt)) + '",');
    W('    "A_Dd_Dd": "' + SmartEscape(string(A_Dd_Dd)) + '",');
    W('    "A_Nn_Tt": "' + SmartEscape(string(A_Nn_Tt)) + '",');
    W('    "A_Nn_Tth": "' + SmartEscape(string(A_Nn_Tth)) + '",');
    W('    "A_NN_Dd": "' + SmartEscape(string(A_NN_Dd)) + '",');
    W('    "A_T_T": "' + SmartEscape(string(A_T_T)) + '",');
    W('    "A_T_Th": "' + SmartEscape(string(A_T_Th)) + '",');
    W('    "A_T_M": "' + SmartEscape(string(A_T_M)) + '",');
    W('    "A_T_R": "' + SmartEscape(string(A_T_R)) + '",');
    W('    "A_D_D": "' + SmartEscape(string(A_D_D)) + '",');
    W('    "A_D_Dh": "' + SmartEscape(string(A_D_Dh)) + '",');
    W('    "A_D_B": "' + SmartEscape(string(A_D_B)) + '",');
    W('    "A_D_M": "' + SmartEscape(string(A_D_M)) + '",');
    W('    "A_N_Tth": "' + SmartEscape(string(A_N_Tth)) + '",');
    W('    "A_N_Dd": "' + SmartEscape(string(A_N_Dd)) + '",');
    W('    "A_N_Dh": "' + SmartEscape(string(A_N_Dh)) + '",');
    W('    "A_N_S": "' + SmartEscape(string(A_N_S)) + '",');
    W('    "A_P_Tt": "' + SmartEscape(string(A_P_Tt)) + '",');
    W('    "A_P_T": "' + SmartEscape(string(A_P_T)) + '",');
    W('    "A_P_P": "' + SmartEscape(string(A_P_P)) + '",');
    W('    "A_P_S": "' + SmartEscape(string(A_P_S)) + '",');
    W('    "A_B_J": "' + SmartEscape(string(A_B_J)) + '",');
    W('    "A_B_D": "' + SmartEscape(string(A_B_D)) + '",');
    W('    "A_B_Dh": "' + SmartEscape(string(A_B_Dh)) + '",');
    W('    "A_Bh_R": "' + SmartEscape(string(A_Bh_R)) + '",');
    W('    "A_M_N": "' + SmartEscape(string(A_M_N)) + '",');
    W('    "A_M_Ph": "' + SmartEscape(string(A_M_Ph)) + '",');
    W('    "A_L_K": "' + SmartEscape(string(A_L_K)) + '",');
    W('    "A_L_G": "' + SmartEscape(string(A_L_G)) + '",');
    W('    "A_L_Tt": "' + SmartEscape(string(A_L_Tt)) + '",');
    W('    "A_L_Dd": "' + SmartEscape(string(A_L_Dd)) + '",');
    W('    "A_L_P": "' + SmartEscape(string(A_L_P)) + '",');
    W('    "A_L_Ph": "' + SmartEscape(string(A_L_Ph)) + '",');
    W('    "A_Sh_UKar": "' + SmartEscape(string(A_Sh_UKar)) + '",');
    W('    "A_Sh_C": "' + SmartEscape(string(A_Sh_C)) + '",');
    W('    "A_Sh_Ch": "' + SmartEscape(string(A_Sh_Ch)) + '",');
    W('    "A_Ss_Nn": "' + SmartEscape(string(A_Ss_Nn)) + '",');
    W('    "A_Ss_Tt": "' + SmartEscape(string(A_Ss_Tt)) + '",');
    W('    "A_Ss_Tth": "' + SmartEscape(string(A_Ss_Tth)) + '",');
    W('    "A_Ss_Ph": "' + SmartEscape(string(A_Ss_Ph)) + '",');
    W('    "A_S_Kh": "' + SmartEscape(string(A_S_Kh)) + '",');
    W('    "A_S_Tt": "' + SmartEscape(string(A_S_Tt)) + '",');
    W('    "A_S_N": "' + SmartEscape(string(A_S_N)) + '",');
    W('    "A_S_Ph": "' + SmartEscape(string(A_S_Ph)) + '",');
    W('    "A_H_UKar" : "' + SmartEscape(string(A_H_UKar)) + '",');
    W('    "A_H_RRIKar": "' + SmartEscape(string(A_H_RRIKar)) + '",');
    W('    "A_H_N": "' + SmartEscape(string(A_H_N)) + '",');
    W('    "A_H_M": "' + SmartEscape(string(A_H_M)) + '",');
    W('    "A_Rr_G": "' + SmartEscape(string(A_Rr_G)) + '",');
    W('    "A_Reph": "' + SmartEscape(string(A_Reph)) + '",');
    W('    "A_M_1H": "' + SmartEscape(string(A_M_1H)) + '",');
    W('    "A_Ss_1H": "' + SmartEscape(string(A_Ss_1H)) + '",');
    W('    "A_S_1H_1": "' + SmartEscape(string(A_S_1H_1)) + '",');
    W('    "A_N_1H_1": "' + SmartEscape(string(A_N_1H_1)) + '",');
    W('    "A_S_1H_2": "' + SmartEscape(string(A_S_1H_2)) + '",');
    W('    "A_D_1H_1": "' + SmartEscape(string(A_D_1H_1)) + '",');
    W('    "A_C_1H": "' + SmartEscape(string(A_C_1H)) + '",');
    W('    "A_NGA_1H": "' + SmartEscape(string(A_NGA_1H)) + '",');
    W('    "A_N_1H_2": "' + SmartEscape(string(A_N_1H_2)) + '",');
    W('    "A_D_1H_2": "' + SmartEscape(string(A_D_1H_2)) + '",');
    W('    "A_B_2H_1": "' + SmartEscape(string(A_B_2H_1)) + '",');
    W('    "A_B_2H_2": "' + SmartEscape(string(A_B_2H_2)) + '",');
    W('    "A_BH_2H": "' + SmartEscape(string(A_BH_2H)) + '",');
    W('    "A_BH_R_2H": "' + SmartEscape(string(A_BH_R_2H)) + '",');
    W('    "A_M_2H_1": "' + SmartEscape(string(A_M_2H_1)) + '",');
    W('    "A_B_2H_3": "' + SmartEscape(string(A_B_2H_3)) + '",');
    W('    "A_M_2H_2": "' + SmartEscape(string(A_M_2H_2)) + '",');
    W('    "A_ZFola": "' + SmartEscape(string(A_ZFola)) + '",');
    W('    "A_RFola_1": "' + SmartEscape(string(A_RFola_1)) + '",');
    W('    "A_RFola_2": "' + SmartEscape(string(A_RFola_2)) + '",');
    W('    "A_L_2H_1": "' + SmartEscape(string(A_L_2H_1)) + '",');
    W('    "A_L_2H_2": "' + SmartEscape(string(A_L_2H_2)) + '",');
    W('    "A_T_R_2H": "' + SmartEscape(string(A_T_R_2H)) + '",');
    W('    "A_RFola_3": "' + SmartEscape(string(A_RFola_3)) + '",');
    W('    "A_Nn_2H_1": "' + SmartEscape(string(A_Nn_2H_1)) + '",');
    W('    "A_K_R_2H": "' + SmartEscape(string(A_K_R_2H)) + '",');
    W('    "A_Nn_2H_2": "' + SmartEscape(string(A_Nn_2H_2)) + '",');
    W('    "A_B_2H_4": "' + SmartEscape(string(A_B_2H_4)) + '",');
    W('    "A_T_2H": "' + SmartEscape(string(A_T_2H)) + '",');
    W('    "A_T_UKar_2H": "' + SmartEscape(string(A_T_UKar_2H)) + '",');
    W('    "A_Th_2H": "' + SmartEscape(string(A_Th_2H)) + '",');
    W('    "A_K_2H": "' + SmartEscape(string(A_K_2H)) + '",');
    W('    "A_L_2H_3": "' + SmartEscape(string(A_L_2H_3)) + '"');
  end;

  procedure WFullForms;
  var
    I: Integer;
  begin
    if Length(CustomFullForms) > 0 then
    begin
      for I := 0 to Length(CustomFullForms) - 1 do
      begin
        W('    {"Key": "' + EscapeJSON(CustomFullForms[I].Key) + '", "Value": "' + SmartEscape(CustomFullForms[I].Value) + '"}');
        if I < Length(CustomFullForms) - 1 then
          Lines[Lines.Count - 1] := Lines[Lines.Count - 1] + ',';
      end;
    end
    else
      W(GetDefaultFullFormsJSON);
  end;

  procedure WPreReplacements;
  var
    I: Integer;
  begin
    if Length(CustomPreReplacements) > 0 then
    begin
      for I := 0 to Length(CustomPreReplacements) - 1 do
      begin
        W('    {"Key": "' + EscapeJSON(CustomPreReplacements[I].Key) + '", "Value": "' + SmartEscape(CustomPreReplacements[I].Value) + '"}');
        if I < Length(CustomPreReplacements) - 1 then
          Lines[Lines.Count - 1] := Lines[Lines.Count - 1] + ',';
      end;
    end;
  end;

  procedure WPostReplacements;
  var
    I: Integer;
  begin
    if Length(CustomPostReplacements) > 0 then
    begin
      for I := 0 to Length(CustomPostReplacements) - 1 do
      begin
        W('    {"Key": "' + EscapeJSON(CustomPostReplacements[I].Key) + '", "Value": "' + SmartEscape(CustomPostReplacements[I].Value) + '"}');
        if I < Length(CustomPostReplacements) - 1 then
          Lines[Lines.Count - 1] := Lines[Lines.Count - 1] + ',';
      end;
    end;
  end;

begin
  Lines := TStringList.Create;
  try
    W('{');
    W('  "Constants": {');
    WConstants;
    W('  },');
    W('  "PreReplacements": [');
    WPreReplacements;
    W('  ],');
    W('  "FullFormReplacements": [');
    WFullForms;
    W('  ],');
    W('  "PostReplacements": [');
    WPostReplacements;
    W('  ]');
    W('}');
    Lines.SaveToFile(Path, TEncoding.UTF8);
  finally
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

end.