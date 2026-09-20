{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../ProjectDefines.inc}
{ COMPLETE TRANSFERING! }

unit uAutoCorrect;

interface

uses
  Windows,
  Classes,
  SysUtils,
  StrUtils,
  Generics.Collections,
  Forms,
  uFileFolderHandling;

procedure InitDict;
procedure LoadDict;
procedure DestroyDict;

{ Lookup used by the typing path. Loads the dictionary on FIRST use instead of
  at application start.

  The 42 KB autodict.dct parses into a TDictionary<string,string> of ~2500
  entries with two heap strings each - a few hundred KB that used to sit in RAM
  from startup for every user, including the ones who never type
  phonetically. Nothing but typing needs it, and the first keystroke pays for
  it once (single-digit milliseconds; the file is in the page cache by then). }
function TryAutoCorrectWord(const AWord: string; out AReplacement: string): Boolean;

var
  Dict: TDictionary<string, string>;

implementation

{ =============================================================================== }

procedure InitDict;
begin
  // Idempotent: the lookup path calls this on every keystroke until the
  // dictionary exists, and the auto-correct editor calls it after saving.
  if Assigned(Dict) then
    Exit;
  Dict := TDictionary<string, string>.create;
  LoadDict;
end;

function TryAutoCorrectWord(const AWord: string; out AReplacement: string): Boolean;
begin
  AReplacement := '';
  if AWord = '' then
    Exit(False);
  if not Assigned(Dict) then
    InitDict;
  if not Assigned(Dict) then
    Exit(False); // dictionary file missing/corrupt: behave as "no match"
  Result := Dict.TryGetValue(AWord, AReplacement);
end;

{ =============================================================================== }

procedure DestroyDict;
begin
  FreeAndNil(Dict);
end;

{ =============================================================================== }

procedure LoadDict;
var
  List:                  TStringList;
  I, P:                  Integer;
  Path:                  string;
  FirstPart, SecondPart: string;
begin
  try
    try
      List := TStringList.create;
      Path := GetAvroDataDir + 'autodict.dct';
      List.LoadFromFile(Path);

      for I := 0 to List.Count - 1 do
      begin
        if (LeftStr(Trim(List[I]), 1) <> '/') and (Trim(List[I]) <> '') then
        begin
          P := Pos(' ', Trim(List[I]));
          FirstPart := LeftStr(Trim(List[I]), P - 1);
          SecondPart := MidStr(Trim(List[I]), P + 1, Length(Trim(List[I])));
          Dict.AddOrSetValue(FirstPart, SecondPart);
        end;
      end;
    except
      on E: Exception do
      begin
        Application.MessageBox(Pchar('Cannot load auto-correct dictionary!' + #10 + '' + #10 + '-> Make sure ''autodict.dct'' file is present in ' + Path +
              ' folder, or' + #10 + '-> ''autodict.dct'' file is not corrupt.' + #10 + '' + #10 + 'Reinstalling Avro Keyboard may solve this problem.'),
          'Avro Keyboard', MB_OK + MB_ICONHAND + MB_DEFBUTTON1 + MB_APPLMODAL);
      end;
    end;
  finally
    FreeAndNil(List);
  end;

end;

{ =============================================================================== }

end.
