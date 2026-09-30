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
  DebugLog,
  uFileFolderHandling;

{ Creates the empty dictionary on first use and reads the file into it.
  Returns True when the dictionary is usable: an existing good one, or a
  fresh load that succeeded. A load that already failed returns False
  without touching the disk again. }
function InitDict: Boolean;

{ Parses autodict.dct into Dict. Returns True when the file was read.


  Deliberately silent on failure: the first call comes from inside the
  WH_KEYBOARD_LL callback (committing a word while typing), and a modal
  dialog opened there keeps the hook procedure from returning. Past
  LowLevelHooksTimeout Windows unhooks the process without an error, and
  Avro then receives no keys at all - in every mode, not just phonetic.
  Failures are reported through OnDictLoadFailed instead, which the main
  form raises from the message loop as a one-shot tray balloon. }
function LoadDict: Boolean;

procedure DestroyDict;

{ Clears the failure state so a dictionary installed while Avro is already
  running (resource download, editor save) is picked up by the next
  keystroke instead of waiting for a restart. }
procedure ResetDictLoadState;

{ True when the dictionary is in memory and did not fail to load - what the
  auto-correct editor asks after InitDict to decide between the entry list
  and a "download the dictionary" affordance. }
function AutoCorrectDictionaryOK: Boolean;

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

  { Assigned once by the main form at startup. Fired from TThread.ForceQueue,
    i.e. from the message loop - never from the hook callback itself. }
var
  OnDictLoadFailed: TProc;

implementation

var
  { Set the moment a load attempt fails: InitDict then stops re-reading the
    file on every keystroke and TryAutoCorrectWord answers "no match" without
    touching the disk again - one failed read per session, never one per
    Space/Enter. }
  DictLoadFailed: Boolean = False;
  { The failure is surfaced to the user exactly once per session. }
  DictLoadNotified: Boolean = False;

  { =============================================================================== }

  { The caller runs inside the WH_KEYBOARD_LL callback, so no UI may happen
    here. ForceQueue - not Queue, which would run the notify inline when the
    caller IS the main thread and therefore still inside the hook - defers it
    to the message loop, after the hook callback has returned. }
procedure NotifyDictLoadFailed;
begin
  if DictLoadNotified then
    Exit;
  DictLoadNotified := True;
  TThread.ForceQueue(nil,
      procedure
    begin
      if Assigned(OnDictLoadFailed) then
        OnDictLoadFailed();
    end);
end;

{ =============================================================================== }

function InitDict: Boolean;
begin
  // Idempotent: the lookup path calls this on every keystroke until the
  // dictionary exists, and the auto-correct editor calls it after saving.
  // A load that already failed stops the retries outright - see DictLoadFailed.
  if DictLoadFailed then
    Exit(False);
  if Assigned(Dict) then
    Exit(True);
  Dict := TDictionary<string, string>.create;
  Result := LoadDict;
end;

function TryAutoCorrectWord(const AWord: string; out AReplacement: string): Boolean;
begin
  AReplacement := '';
  if (AWord = '') or DictLoadFailed then
    Exit(False);
  if not Assigned(Dict) then
    InitDict;
  if (not Assigned(Dict)) or DictLoadFailed then
    Exit(False); // dictionary file missing/corrupt: behave as "no match"
  Result := Dict.TryGetValue(AWord, AReplacement);
end;

{ =============================================================================== }

procedure DestroyDict;
begin
  FreeAndNil(Dict);
end;

{ =============================================================================== }

procedure ResetDictLoadState;
begin
  DictLoadFailed := False;
  DictLoadNotified := False;
  FreeAndNil(Dict);
end;

{ =============================================================================== }

function AutoCorrectDictionaryOK: Boolean;
begin
  Result := Assigned(Dict) and (not DictLoadFailed);
end;

{ =============================================================================== }

function LoadDict: Boolean;
var
  List:                  TStringList;
  I, P:                  Integer;
  Path:                  string;
  FirstPart, SecondPart: string;
begin
  Result := False;
  Path := GetAvroDataDir + 'autodict.dct';
  List := nil;
  try
    try
      List := TStringList.create;
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

      DictLoadFailed := False;
      Result := True;
    except
      on E: Exception do
      begin
        { Never a MessageBox here - see the interface comment. The dictionary
          stays assigned but empty, so typing goes on without auto-correct. }
        DictLoadFailed := True;
        Log('Auto-correct dictionary not loaded: ' + E.Message);
        NotifyDictLoadFailed;
      end;
    end;
  finally
    FreeAndNil(List);
  end;

end;

{ =============================================================================== }

end.
