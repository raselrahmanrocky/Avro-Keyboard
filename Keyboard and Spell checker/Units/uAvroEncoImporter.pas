{
  =============================================================================
  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at https://mozilla.org/MPL/2.0/.
  =============================================================================
}

{$INCLUDE ../../ProjectDefines.inc}
unit uAvroEncoImporter;

{ =============================================================================
  uAvroEncoImporter - smart conditional import of ".AvroEnco" mapping files.

  Imports branch on the cryptographic container header (see uAvroEncoCrypto):

      [0..8]   9 bytes  magic 'AVROENCO' + version byte ($02 = current)
      [9]      1 byte   protection flag:
                          $00 = password-less / Default Application Key
                          $01 = user password

  * Flag $00 (password-less): NEVER shows uAvroPasswordDlg. The payload is
    test-decrypted in memory with the internal default application master
    key (pure Pascal AES-256-CBC); a valid JSON result (starts with '{')
    allows the import, otherwise an error is reported without a password
    prompt. Default-key imports are silent: the active mapping is not
    changed.
  * Flag $01 (password protected): shows uAvroPasswordDlg via
    PromptForPasswordAndValidate with up to 3 attempts, validates the
    password against the file's salt/payload, then copies the file, caches
    the password and ACTIVATES the imported mapping.
  * Legacy v1 containers ('AVROENCO' + $01, no flag byte) are treated as
    password protected so previously exported files keep importing.
  * Cancel / 3 failed attempts abort cleanly: no file is ever created or
    copied before validation succeeds.
  ============================================================================= }

interface

uses
  Windows,
  SysUtils,
  Classes,
  Dialogs;

// Imports a single .AvroEnco file, branching on its protection flag.
// Returns True on success (file copied, menus rescanned, toast shown;
// password-protected imports also get activated). AErrorMessage is empty
// when the user cancelled a password prompt (not an error condition).
function ImportEncoFile(const ASourcePath: string; out AErrorMessage: string): Boolean;

// File-dialog import: iterates every selected file independently.
function ImportEncoFromDialog: Boolean;

// Drag & drop import (used by uTopBar / HandleEncoDragDrop): iterates every
// dropped .AvroEnco file independently.
procedure HandleEncoDragDrop(AFileNames: TStringList);

function GenerateUniqueFileName(const ATargetDir, AFileName: string): string;

// Shows uAvroPasswordDlg and validates against the file (max 3 attempts).
// True when a valid password is found; APassword is empty on cancel/failure.
function PromptForPasswordAndValidate(const AFilePath: string; out APassword: AnsiString): Boolean;

implementation

uses
  Forms,
  uAvroEncoCrypto,
  uAvroEncoManager,
  uAvroPasswordDlg,
  uFileFolderHandling,
  ufrmAnsiToast,
  uRegistrySettings,
  clsUnicodeToBijoy2000,
  DebugLog;

const
  MAX_PASSWORD_ATTEMPTS = 3;

{ =============================================================================
  Pure Pascal header pre-inspection (zero external DLL calls, reads only the
  first 10 bytes of the file):

      [0..8]  'AVROENCO' + $02        (validated)
      [9]     protection flag        (returned)

  Returns:
      AVROENCO_FLAG_DEFAULT_KEY     ($00, password-less/default key)
      AVROENCO_FLAG_USER_PASSWORD   ($01, password protected; also legacy v1)
      AVROENCO_FLAG_INVALID         (unreadable / bad magic / bad flag)
  ============================================================================= }
function InspectEncoProtectionFlag(const AFilePath: string): Byte;
var
  FS: TFileStream;
  Header: array [0 .. 9] of Byte;
begin
  Result := AVROENCO_FLAG_INVALID;

  if not FileExists(AFilePath) then
    Exit;

  try
    FS := TFileStream.Create(AFilePath, fmOpenRead or fmShareDenyNone);
  except
    Exit;
  end;

  try
    if FS.Size < 10 then
      Exit;
    if FS.Read(Header[0], 10) <> 10 then
      Exit;
  finally
    FS.Free;
  end;

  // Bytes 0..7 must be 'AVROENCO'.
  if not CompareMem(@Header[0], @AVROENCO_MAGIC_BASE[0], 8) then
    Exit;

  case Header[8] of
    AVROENCO_MAGIC_TAIL_V2:
      begin
        // Current container: byte 9 is the protection flag ($00 / $01).
        if (Header[9] = AVROENCO_FLAG_DEFAULT_KEY) or
          (Header[9] = AVROENCO_FLAG_USER_PASSWORD) then
          Result := Header[9];
      end;
    AVROENCO_MAGIC_TAIL_V1:
      // Legacy containers predate the flag byte and are always password
      // protected (kept so previously exported files still import).
      Result := AVROENCO_FLAG_USER_PASSWORD;
  end;
end;

{ ============================================================================= }
function GenerateUniqueFileName(const ATargetDir, AFileName: string): string;
var
  BaseName, Ext: string;
  Counter: Integer;
begin
  Result := ATargetDir + AFileName;
  if not FileExists(Result) then
    Exit;

  BaseName := ChangeFileExt(AFileName, '');
  Ext := ExtractFileExt(AFileName);
  Counter := 1;

  while FileExists(ATargetDir + BaseName + ' (' + IntToStr(Counter) + ')' + Ext) do
    Inc(Counter);

  Result := ATargetDir + BaseName + ' (' + IntToStr(Counter) + ')' + Ext;
end;

{ ============================================================================= }

function PromptForPasswordAndValidate(
  const AFilePath: string;
  out APassword: AnsiString
): Boolean;
var
  Attempt: Integer;
  ErrMsg: string;
begin
  Result := False;
  APassword := '';

  for Attempt := 1 to MAX_PASSWORD_ATTEMPTS do
  begin
    if not ShowPasswordDialog(APassword) then
    begin
      APassword := '';
      Exit;
    end;

    if ValidateAvroEncoPassword(AFilePath, APassword) then
    begin
      Result := True;
      Exit;
    end;

    if Attempt < MAX_PASSWORD_ATTEMPTS then
    begin
      ErrMsg := 'Invalid password. Please try again. (' +
        IntToStr(Attempt) + ' of ' + IntToStr(MAX_PASSWORD_ATTEMPTS) + ' attempts)';
      Application.MessageBox(PChar(ErrMsg), 'Password Error',
        MB_ICONERROR or MB_OK or MB_TOPMOST or MB_SETFOREGROUND);
    end
    else
    begin
      ErrMsg := 'Invalid password after ' + IntToStr(MAX_PASSWORD_ATTEMPTS) +
        ' attempts. Import cancelled.';
      Application.MessageBox(PChar(ErrMsg), 'Import Cancelled',
        MB_ICONERROR or MB_OK or MB_TOPMOST or MB_SETFOREGROUND);
    end;
  end;
end;

{ ============================================================================= }
function ImportEncoFile(
  const ASourcePath: string;
  out AErrorMessage: string
): Boolean;
var
  Password: AnsiString;
  ProtectionFlag: Byte;
  TargetDir, TargetPath, DisplayName, ImportedName, ErrMsg: string;
begin
  Result := False;
  AErrorMessage := '';

  // --- 1. Basic checks ------------------------------------------------------
  if not FileExists(ASourcePath) then
  begin
    AErrorMessage := 'Source file does not exist.';
    Exit;
  end;

  if not SameText(ExtractFileExt(ASourcePath), '.AvroEnco') then
  begin
    AErrorMessage := 'Invalid file extension. Expected .AvroEnco.';
    Exit;
  end;

  // Valid container shape (magic + salt + IV + at least one cipher block).
  if not ValidateAvroEncoHeader(ASourcePath) then
  begin
    AErrorMessage := 'Invalid .AvroEnco file header.';
    Exit;
  end;

  // --- 2. Pre-inspection of the protection flag (no prompt yet) -------------
  // Pure Pascal header check: bytes 0..8 magic ('AVROENCO' + $02) + byte 9
  // protection flag. No crypto DLLs are involved at this stage.
  ProtectionFlag := InspectEncoProtectionFlag(ASourcePath);
  if ProtectionFlag = AVROENCO_FLAG_INVALID then
  begin
    AErrorMessage := 'Invalid .AvroEnco file header.';
    Exit;
  end;

  // --- 3. Destination folder ------------------------------------------------
  TargetDir := GetAvroDataDir + 'AnsiMapping\';
  ForceDirectories(TargetDir);

  if SameText(ExtractFilePath(ASourcePath), TargetDir) then
  begin
    AErrorMessage := 'File is already in the target directory.';
    Exit;
  end;

  DisplayName := GetEncoDisplayName(ASourcePath);

  // --- 4. Flag-driven validation (nothing is copied or created yet) ----------
  if ProtectionFlag = AVROENCO_FLAG_USER_PASSWORD then
  begin
    // Password protected (flag $01, or legacy v1): uAvroPasswordDlg with up
    // to 3 attempts. Cancel / 3 failures abort cleanly BEFORE any file is
    // created or copied (AErrorMessage stays empty - user cancelled).
    if not PromptForPasswordAndValidate(ASourcePath, Password) then
    begin
      AErrorMessage := '';
      Exit;
    end;
  end
  else
  begin
    // Password-less (flag $00 / default application key): NO password dialog.
    // Test-decrypt the payload in memory with the pure Pascal AES engine.
    // A corrupted payload fails the PKCS#7 padding / JSON check and is
    // reported as an error without ever asking for a password.
    if not ValidateAvroEncoPassword(ASourcePath, '') then
    begin
      AErrorMessage := 'Invalid or corrupted .AvroEnco file. Import was not performed.';
      Exit;
    end;
    Password := '';
  end;

  // --- 5. Duplicate-name handling ---------------------------------------------
  TargetPath := TargetDir + ExtractFileName(ASourcePath);

  if FileExists(TargetPath) then
  begin
    if Application.MessageBox(
      PChar('A mapping named "' + DisplayName + '" already exists.' + sLineBreak +
        'Overwrite the existing file?'),
      'Confirm Overwrite',
      MB_ICONQUESTION or MB_YESNO or MB_DEFBUTTON2
    ) <> ID_YES then
    begin
      TargetPath := GenerateUniqueFileName(TargetDir, ExtractFileName(ASourcePath));
      if TargetPath = '' then
      begin
        AErrorMessage := 'Could not generate unique file name.';
        Exit;
      end;
    end;
  end;

  // --- 6. Copy ---------------------------------------------------------------
  if not Windows.CopyFile(PChar(ASourcePath), PChar(TargetPath), False) then
  begin
    AErrorMessage := 'Failed to copy file to target directory. Error: ' +
      SysErrorMessage(GetLastError);
    Exit;
  end;

  ImportedName := GetEncoDisplayName(TargetPath);

  // --- 7. Cache the valid password (password protected only) -----------------
  if Password <> '' then
    CachedEncoPassword := Password;

  // --- 8. Scan / refresh + success feedback ----------------------------------
  ScanAvroEncoFiles(TargetDir);

  Log('Imported AvroEnco file: ' + ImportedName);
  ShowAnsiToastNotification('Mapping imported: ' + ImportedName);
  Result := True;

  // --- 9. Activate the new mapping (password-protected imports only) ---------
  // Default-key imports are silent and never change the active mapping.
  if Password <> '' then
  begin
    if TrySetAnsiVersion(ImportedName, ErrMsg) then
    begin
      SaveSettings; // persist the active AnsiVersion + CachedEncoPassword
      Log('Activated imported mapping: ' + ImportedName);
    end
    else
      Log('Imported but could not activate ' + ImportedName + ': ' + ErrMsg);
  end;
end;

{ =============================================================================
  Shared multi-file iteration. Each file is handled fully independently by
  ImportEncoFile: password-less files import silently in the background,
  password-protected files request their password sequentially.
  ============================================================================= }

procedure DoImportFileList(
  const AFileNames: TStrings;
  out AImported: Integer;
  out AErrorMessages: string
);
var
  I: Integer;
  ErrMsg: string;
begin
  AImported := 0;
  AErrorMessages := '';

  for I := 0 to AFileNames.Count - 1 do
  begin
    if SameText(ExtractFileExt(AFileNames[I]), '.AvroEnco') then
    begin
      if ImportEncoFile(AFileNames[I], ErrMsg) then
        Inc(AImported)
      else if ErrMsg <> '' then
      begin
        if AErrorMessages <> '' then
          AErrorMessages := AErrorMessages + sLineBreak;
        AErrorMessages := AErrorMessages + ExtractFileName(AFileNames[I]) + ': ' + ErrMsg;
      end;
    end;
  end;
end;

{ ============================================================================= }
function ImportEncoFromDialog: Boolean;
var
  OpenDialog: TOpenDialog;
  FileNames: TStringList;
  Imported: Integer;
  ErrorMessages: string;
begin
  Result := False;
  Imported := 0;
  ErrorMessages := '';

  OpenDialog := TOpenDialog.Create(nil);
  FileNames := TStringList.Create;
  try
    OpenDialog.Filter := 'Avro Encoded Mapping|*.AvroEnco';
    OpenDialog.DefaultExt := 'AvroEnco';
    OpenDialog.Title := 'Import Avro Encoded ANSI Mapping';
    OpenDialog.Options := OpenDialog.Options + [ofAllowMultiSelect, ofFileMustExist];

    if OpenDialog.Execute then
    begin
      FileNames.Assign(OpenDialog.Files);
      DoImportFileList(FileNames, Imported, ErrorMessages);

      Result := Imported > 0;

      if ErrorMessages <> '' then
        Application.MessageBox(PChar(ErrorMessages), 'Import Errors',
          MB_ICONWARNING or MB_OK);
    end;
  finally
    FileNames.Free;
    OpenDialog.Free;
  end;
end;

{ ============================================================================= }

procedure HandleEncoDragDrop(AFileNames: TStringList);
var
  Imported: Integer;
  ErrorMessages: string;
begin
  Imported := 0;
  ErrorMessages := '';

  DoImportFileList(AFileNames, Imported, ErrorMessages);

  if ErrorMessages <> '' then
    Application.MessageBox(PChar(ErrorMessages), 'Import Errors',
      MB_ICONWARNING or MB_OK);
end;

end.
