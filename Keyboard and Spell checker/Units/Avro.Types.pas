{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================}

{$INCLUDE ../ProjectDefines.inc}

unit Avro.Types;

interface

uses
  System.SysUtils;

type
  TCharType = (
    ctConsonant,
    ctVowel,
    ctPreVowel,
    ctPostVowel,
    ctKar,
    ctHasanta,
    ctConjunction,
    ctDiacritic,
    ctSymbol,
    ctSpace,
    ctBoundary
  );

  TBehaviorType = (
    btDirectEmit,
    btPrependIfConsonant,
    btFlushBufferAndEmit,
    btContextVowel,
    btAttachDiacritic
  );

  TEngineState = (
    esIdle,
    esTypingWord,
    esBoundaryReached,
    esReSyncing,
    esPendingPrepend
  );

  TUnicodeUnit = record
    UnicodeChar: Char;
    MappedANSI: string;
    UnitType: TCharType;
    PrependOffset: Integer;
  end;

implementation

end.
