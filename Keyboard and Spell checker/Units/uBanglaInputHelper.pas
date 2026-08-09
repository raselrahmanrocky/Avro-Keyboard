{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uBanglaInputHelper;

interface

function ShouldBlockHasanta(const CurrentText: string; SelStart: Integer; NewChar: Char; IsUnicode: Boolean): Boolean;

implementation

function ShouldBlockHasanta(const CurrentText: string; SelStart: Integer; NewChar: Char; IsUnicode: Boolean): Boolean;
var
  HasantaChar: Char;
begin
  Result := False;

  if IsUnicode then
    HasantaChar := #$09CD
  else
    HasantaChar := #$26;

  if NewChar = HasantaChar then
  begin
    if SelStart >= 2 then
    begin
      if (CurrentText[SelStart] = HasantaChar) and (CurrentText[SelStart - 1] = HasantaChar) then
        Result := True;
    end;
  end;
end;

end.
