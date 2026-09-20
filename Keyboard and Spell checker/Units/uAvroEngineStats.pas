{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroEngineStats;

{ =============================================================================
  uAvroEngineStats - per-process memory instrumentation for the idle-RAM work.

  Three numbers that must never be confused with each other:

  Heap     - bytes the RTL allocator has handed out, summed over its small,
  medium and large block classes (GetMemoryManagerState). This is
  the number the lazy-loading / arena / dedup work actually moves.
  Private  - committed private bytes of the process (GetProcessMemoryInfo).
  Heap + thread stacks + the image's own writable data.
  Working  - the physical working set. It also contains file-backed image
  pages (.text/.rsrc), which a working-set trim can drop but
  private bytes cannot. A "2 MB -> 6 MB" report is usually this
  number, so it must be read next to Private, never instead of it.

  Deliberately free of VCL and of DebugLog: the GUI application and every
  console gate can link it, and callers decide where the line goes (a global
  hook for the app, WriteLn for the gates).
  ============================================================================= }

interface

uses
  System.SysUtils;

type
  TAvroMemStats = record
    { Bytes the allocator has allocated, small + medium + large classes. }
    HeapBytes: Int64;
    { Address space the allocator reserves for its own pools (allocated AND
      free blocks). Grows with peak usage and only shrinks when a whole pool
      group is returned to the OS, so it is the honest "high-water" signal. }
    HeapReservedBytes: Int64;
    { Allocated block count across all classes - node/record churn shows here
      before it shows in bytes. }
    BlockCount: Int64;
    { PROCESS_MEMORY_COUNTERS: private + working set + peaks. }
    PrivateBytes: Int64;
    WorkingSetBytes: Int64;
    PeakWorkingSetBytes: Int64;
  end;

  { Snapshot of the current process. Never raises: a failed query reports 0. }
function GetAvroMemStats: TAvroMemStats;

{ One log line, e.g.
  MEM [startup] heap=812 KB (reserved 1.4 MB, 9k blocks) private=3.1 MB working=5.8 MB (peak 7.2 MB) }
function AvroMemStatsText(const ATag: string): string; overload;
function AvroMemStatsText(const ATag: string; const AStats: TAvroMemStats): string; overload;

{ Same line shape, plus the delta against ABefore for the numbers that a
  load/release burst is supposed to move. }
function AvroMemDeltaText(const ATag: string; const ABefore, AAfter: TAvroMemStats): string;

{ Formats + forwards to OnAvroMemLog. Cheap no-op when no hook is installed,
  so call sites can sit on hot-ish paths without a DebugLog dependency. }
procedure LogAvroMemStats(const ATag: string);

type
  { How willing the OS should be to keep this process resident. LOW lets the
    memory manager reclaim our pages under pressure without us having to trim
    on a timer; NORMAL is what a keyboard hook's responsiveness wants. }
  TAvroMemoryPriority = (ampLow, ampNormal);

  { Seconds since the last input anywhere on the system (GetLastInputInfo).
    This is the definition the idle release needs: a keyboard utility is used
    from other windows, so "no input in this process" would be wrong. }
function GetSystemIdleSeconds: Cardinal;

{ Returns the process's working set to the OS. One syscall on the current
  process: no handle is opened, no access mask is requested, and - unlike the
  helper this replaces - no message pump is run, so it cannot re-enter a timer
  handler or the keyboard hook. Safe to call from a timer or after a load
  burst; the pages come back on demand, which is why it must never be called
  while the user is typing. }
procedure TrimProcessWorkingSet;

{ Best-effort memory priority. Silently does nothing where the API is missing
  (SetProcessInformation is a delayed import, so an old Windows surfaces it as
  an exception rather than a load failure). }
procedure SetAvroMemoryPriority(const APriority: TAvroMemoryPriority);

{ Assign in the host's initialization: the app points it at DebugLog.Log, a
  gate at WriteLn. }
var
  OnAvroMemLog: procedure(const ALine: string);

implementation

uses
  Winapi.Windows,
  Winapi.PsAPI;

function GetAvroMemStats: TAvroMemStats;
var
  MM: TMemoryManagerState;
  I:  Integer;
  C:  TProcessMemoryCounters;
begin
  Result.HeapBytes := 0;
  Result.HeapReservedBytes := 0;
  Result.BlockCount := 0;
  Result.PrivateBytes := 0;
  Result.WorkingSetBytes := 0;
  Result.PeakWorkingSetBytes := 0;

  try
    {$WARN SYMBOL_PLATFORM OFF} // the whole unit is a Win32 census by design
    GetMemoryManagerState(MM);
    {$WARN SYMBOL_PLATFORM ON}
    for I := low(MM.SmallBlockTypeStates) to high(MM.SmallBlockTypeStates) do
    begin
      Result.HeapBytes := Result.HeapBytes + Int64(MM.SmallBlockTypeStates[I].AllocatedBlockCount) * Int64(MM.SmallBlockTypeStates[I].InternalBlockSize);
      Result.HeapReservedBytes := Result.HeapReservedBytes + Int64(MM.SmallBlockTypeStates[I].ReservedAddressSpace);
      Result.BlockCount := Result.BlockCount + Int64(MM.SmallBlockTypeStates[I].AllocatedBlockCount);
    end;
    Result.HeapBytes := Result.HeapBytes + Int64(MM.TotalAllocatedMediumBlockSize) + Int64(MM.TotalAllocatedLargeBlockSize);
    Result.HeapReservedBytes := Result.HeapReservedBytes + Int64(MM.ReservedMediumBlockAddressSpace) + Int64(MM.ReservedLargeBlockAddressSpace);
    Result.BlockCount := Result.BlockCount + Int64(MM.AllocatedMediumBlockCount) + Int64(MM.AllocatedLargeBlockCount);
  except
    // A memory-manager census must never be able to break a load path.
  end;

  try
    FillChar(C, SizeOf(C), 0);
    C.cb := SizeOf(C);
    if GetProcessMemoryInfo(GetCurrentProcess, @C, SizeOf(C)) then
    begin
      Result.PrivateBytes := Int64(C.PagefileUsage);
      Result.WorkingSetBytes := Int64(C.WorkingSetSize);
      Result.PeakWorkingSetBytes := Int64(C.PeakWorkingSetSize);
    end;
  except
  end;
end;

function BytesToText(const ABytes: Int64): string;
begin
  if ABytes >= 1024 * 1024 then
    Result := FormatFloat('0.00 MB', ABytes / (1024 * 1024))
  else if ABytes >= 1024 then
    Result := FormatFloat('0.0 KB', ABytes / 1024)
  else
    Result := IntToStr(ABytes) + ' B';
end;

function AvroMemStatsText(const ATag: string; const AStats: TAvroMemStats): string;
begin
  Result := 'MEM [' + ATag + '] heap=' + BytesToText(AStats.HeapBytes) + ' (reserved ' + BytesToText(AStats.HeapReservedBytes) + ', ' +
    IntToStr(AStats.BlockCount) + ' blocks)' + ' private=' + BytesToText(AStats.PrivateBytes) + ' working=' + BytesToText(AStats.WorkingSetBytes) + ' (peak ' +
    BytesToText(AStats.PeakWorkingSetBytes) + ')';
end;

function AvroMemStatsText(const ATag: string): string;
begin
  Result := AvroMemStatsText(ATag, GetAvroMemStats);
end;

function SignedBytesToText(const ABytes: Int64): string;
begin
  if ABytes >= 0 then
    Result := '+' + BytesToText(ABytes)
  else
    Result := '-' + BytesToText(-ABytes);
end;

function AvroMemDeltaText(const ATag: string; const ABefore, AAfter: TAvroMemStats): string;
begin
  Result := AvroMemStatsText(ATag, AAfter) + ' | delta heap=' + SignedBytesToText(AAfter.HeapBytes - ABefore.HeapBytes) + ' private=' +
    SignedBytesToText(AAfter.PrivateBytes - ABefore.PrivateBytes) + ' working=' + SignedBytesToText(AAfter.WorkingSetBytes - ABefore.WorkingSetBytes);
end;

procedure LogAvroMemStats(const ATag: string);
begin
  if Assigned(OnAvroMemLog) then
    OnAvroMemLog(AvroMemStatsText(ATag));
end;

function GetSystemIdleSeconds: Cardinal;
var
  Info: TLastInputInfo;
begin
  Result := 0;
  try
    Info.cbSize := SizeOf(TLastInputInfo);
    if GetLastInputInfo(Info) then
      Result := (GetTickCount - Info.dwTime) div 1000;
  except
  end;
end;

procedure TrimProcessWorkingSet;
begin
  try
    SetProcessWorkingSetSize(GetCurrentProcess, NativeUInt(-1), NativeUInt(-1));
  except
    // Trimming is an optimization of the reported footprint, never a
    // correctness requirement: never let it break the caller.
  end;
end;

procedure SetAvroMemoryPriority(const APriority: TAvroMemoryPriority);
var
  Info: TMemoryPriorityInformation;
begin
  try
    if APriority = ampLow then
      Info.MemoryPriority := MEMORY_PRIORITY_LOW
    else
      Info.MemoryPriority := MEMORY_PRIORITY_NORMAL;
    SetProcessInformation(GetCurrentProcess, ProcessMemoryPriority, @Info, SizeOf(Info));
  except
    // Pre-Windows-8 (or a locked-down process): keep the default priority.
  end;
end;

initialization

OnAvroMemLog := nil;

end.
