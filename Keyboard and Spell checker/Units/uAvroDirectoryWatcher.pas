{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroDirectoryWatcher;

interface

uses
  Windows,
  SysUtils,
  Classes;

type
  TLayoutChangeEvent = procedure(Sender: TObject) of object;

  TAvroDirectoryWatcher = class
  private
    FWatchHandle: THandle;
    FDirectory: string;
    FDebounceCountdown: Integer;
    FOnChanged: TLayoutChangeEvent;
    FActive: Boolean;
    procedure ResetWatchHandle;
  public
    constructor Create(const ADirectory: string);
    destructor Destroy; override;
    procedure CheckForChanges;
    property OnChanged: TLayoutChangeEvent read FOnChanged write FOnChanged;
    property Active: Boolean read FActive write FActive;
  end;

implementation

uses
  DebugLog;

const
  DEBOUNCE_TICKS = 3;
  WATCH_FLAGS = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_LAST_WRITE;

{ TAvroDirectoryWatcher }

constructor TAvroDirectoryWatcher.Create(const ADirectory: string);
begin
  inherited Create;
  FDirectory := ADirectory;
  FDebounceCountdown := DEBOUNCE_TICKS;
  FActive := False;
  FWatchHandle := INVALID_HANDLE_VALUE;
  if DirectoryExists(FDirectory) then
    ResetWatchHandle;
end;

destructor TAvroDirectoryWatcher.Destroy;
begin
  if FWatchHandle <> INVALID_HANDLE_VALUE then
    FindCloseChangeNotification(FWatchHandle);
  FWatchHandle := INVALID_HANDLE_VALUE;
  inherited;
end;

procedure TAvroDirectoryWatcher.ResetWatchHandle;
begin
  if FWatchHandle <> INVALID_HANDLE_VALUE then
    FindCloseChangeNotification(FWatchHandle);
  FWatchHandle := FindFirstChangeNotification(
    PChar(FDirectory),
    False,
    WATCH_FLAGS
  );
  if FWatchHandle = INVALID_HANDLE_VALUE then
    Log('DirectoryWatcher: FindFirstChangeNotification failed for ' + FDirectory)
  else
    Log('DirectoryWatcher: Watching ' + FDirectory);
end;

procedure TAvroDirectoryWatcher.CheckForChanges;
var
  WaitResult: DWORD;
begin
  if not FActive then
    Exit;
  if FWatchHandle = INVALID_HANDLE_VALUE then
  begin
    if DirectoryExists(FDirectory) then
      ResetWatchHandle;
    Exit;
  end;

  WaitResult := WaitForSingleObject(FWatchHandle, 0);

  if WaitResult = WAIT_OBJECT_0 then
  begin
    ResetWatchHandle;
    Dec(FDebounceCountdown);
    if FDebounceCountdown <= 0 then
    begin
      FDebounceCountdown := DEBOUNCE_TICKS;
      Log('DirectoryWatcher: Change detected, firing OnChanged');
      if Assigned(FOnChanged) then
        FOnChanged(Self);
    end;
  end
  else
    FDebounceCountdown := DEBOUNCE_TICKS;
end;

end.
