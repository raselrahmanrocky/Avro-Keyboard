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

function HandleConsecutiveHasanta(var Text: string; var SelStart: Integer; NewChar: Char; IsUnicode: Boolean): Boolean;

implementation

function HandleConsecutiveHasanta(var Text: string; var SelStart: Integer; NewChar: Char; IsUnicode: Boolean): Boolean;
var
  HasantaChar: Char;
  ZWNJ: Char;
begin
  Result := False;
  ZWNJ := #$200C;

  if IsUnicode then
    HasantaChar := #$09CD
  else
    HasantaChar := #$26;

  if NewChar = HasantaChar then
  begin
    if SelStart >= 1 then
    begin
      if Text[SelStart] = HasantaChar then
      begin
        if IsUnicode then
        begin
          Insert(ZWNJ, Text, SelStart + 1);
          SelStart := SelStart + 1;
          Result := True;
        end
        else
        begin
          Result := True;
        end;
      end;
    end;
  end;
end;

end.
