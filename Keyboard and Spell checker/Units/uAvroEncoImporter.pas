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

  Imports branch on the protection flag of the cryptographic container header.
  The flag is read through the canonical uAvroEncoCrypto.GetAvroEncoProtectionFlag
  helper - the single source of truth shared with the engine loader, the folder
  watcher and the version picker - so every code path agrees on whether a file
  needs a password. It covers BOTH container formats that share the .AvroEnco
  extension:

    * v2 CBC containers (magic 'AVROENCO' + $02):
          byte 9 = protection flag: $00 = Default Application Key,
                                     $01 = user password
    * Shield containers (magic 'AVROSHLD' + $02, AES-GCM + HMAC trailer):
          byte 9 carries AVROSHLD_FLAG_DEFAULT_KEY ($10). A file WITH that bit
          unlocks with the built-in application secret exactly like a v2 flag
          $00 file; a file WITHOUT it is password protected.

  * Default-key containers (v2 flag $00, or Shield with the default-key bit):
    NEVER show uAvroPasswordDlg. The payload is test-decrypted in memory with
    the built-in application secret; a valid JSON result (starts with '{')
    allows the import, otherwise an error is reported without a password
    prompt. Default-key imports are silent: the active mapping is not
    changed.
  * Password-protected containers (v2 flag $01, Shield without the default-key
    bit, legacy v1): show uAvroPasswordDlg via PromptForPasswordAndValidate
    with up to 3 attempts, validate the password against the file's
    salt/payload, then copy the file, cache the password and ACTIVATE the
    imported mapping.
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

// Imports a single .AvroEnco file, branching on its protection flag
// (uAvroEncoCrypto.GetAvroEncoProtectionFlag). Default-key containers - v2
// flag $00, or a Shield container carrying the default-key bit - are copied
// silently, without any password dialog.
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
  uAnsiEngineManager,
  DebugLog;

const
  MAX_PASSWORD_ATTEMPTS = 3;

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
  try

  for Attempt := 1 to MAX_PASSWORD_ATTEMPTS do
  begin
    if not ShowPasswordDialog(APassword, GetEncoDisplayName(AFilePath)) then
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
  except
    // A password dialog that fails while opening/closing (user clicking the
    // X) must abort exactly like a cancel - never an access violation dialog.
    Result := False;
    APassword := '';
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
  ErrorLog: TStringList;
begin
  Result := False;
  AErrorMessage := '';
  try

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
  // Canonical inspector (uAvroEncoCrypto): the same helper the engine loader,
  // folder watcher and version picker use. Shield containers carrying the
  // AVROSHLD_FLAG_DEFAULT_KEY bit report DEFAULT_KEY - exactly like v2 flag
  // $00 - so they import silently instead of prompting. Only v2 flag $01,
  // legacy v1 and Shield containers without the default-key bit are treated
  // as password protected.
  ProtectionFlag := GetAvroEncoProtectionFlag(ASourcePath);

  // Fail closed on anything the inspector could not classify (unreadable file,
  // bad magic, corrupt v2 flag byte). GetAvroEncoProtectionFlag returns the raw
  // v2 flag byte, so this guard is what keeps a malformed flag from being
  // silently routed into the default-key branch.
  if (ProtectionFlag <> AVROENCO_FLAG_DEFAULT_KEY) and
    (ProtectionFlag <> AVROENCO_FLAG_USER_PASSWORD) then
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

  // --- 7. Remember the valid password (password protected only) ---------------
  // Stored per encoding, so switching to this mapping later never asks for the
  // password again on this computer (survives app and PC restarts).
  if Password <> '' then
  begin
    CachedEncoPassword := Password;
    RememberEncoPassword(TargetPath, Password);
  end;

  // --- 8. Scan / refresh + success feedback ----------------------------------
  ScanAvroEncoFiles(TargetDir);

  Log('Imported AvroEnco file: ' + ImportedName);
  ShowAnsiToastNotification('Mapping imported: ' + ImportedName);
  Result := True;

  // --- 9. Activate the new mapping (password-protected imports only) ---------
  // Default-key imports are silent and never change the active mapping.
  // InvalidateEngine first: when the imported name was already cached, the
  // freshly copied file must replace the stale parked engine.
  if Password <> '' then
  begin
    AnsiEngineManager.InvalidateEngine(ImportedName);
    ErrorLog := TStringList.Create;
    try
      if AnsiEngineManager.SwitchEngine(ImportedName, ErrorLog) then
      begin
        SaveSettings; // persist the active AnsiVersion + CachedEncoPassword
        Log('Activated imported mapping: ' + ImportedName);
      end
      else
      begin
        ErrMsg := ErrorLog.Text;
        Log('Imported but could not activate ' + ImportedName + ': ' + ErrMsg);
      end;
    finally
      ErrorLog.Free;
    end;
  end;
  except
    on E: Exception do
    begin
      // A crash inside the import flow (e.g. the password dialog being
      // closed abruptly) must surface as a clean error message, never an
      // access violation dialog.
      Result := False;
      AErrorMessage := 'Unexpected error while importing the file.';
      Log('ImportEncoFile exception: ' + E.ClassName + ': ' + E.Message + ' - ' + ASourcePath);
    end;
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
