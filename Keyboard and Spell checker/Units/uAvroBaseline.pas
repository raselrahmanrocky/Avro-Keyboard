(*
  uAvroBaseline.pas - the embedded ANSI baseline (versioned last-resort fallback)

  WHY
  ---
  On a fresh, wiped or portable install the AnsiMapping folder is empty. Today
  the application then falls back to Unicode and the user cannot type ANSI at
  all until a mapping is installed by hand. This unit exposes one mapping
  container that is compiled into Avro Keyboard.exe so the very first run
  already produces correct ANSI output, with no download and no file on disk.

  PRIORITY
  --------
  This is the LOWEST-priority source. Callers must try, in order:
    1. a user-installed container in AnsiMapping
    2. the signed remote manifest (uAvroManifest)
    3. this embedded baseline
  A user mapping therefore always wins.

  SECURITY
  --------
  The payload is an AvroShield v3 container - ciphertext, not plaintext JSON -
  so linking it into the executable discloses no mapping. It is decrypted in
  memory only, through AvroShieldLoadForRuntime, which pins the embedded dev
  secret and cannot be talked into emitting comments or accepting a foreign
  key. The decrypted UTF-8 buffer is wiped by the caller as soon as the JSON is
  parsed. Nothing is ever written to disk.

  BUILD
  -----
  Layout\AvroBaseline.res is produced from Layout\AvroBaseline.rc with brcc32
  and is checked in, matching how Internal_Layout.res / Internal_Skin.res are
  handled. Rebuild it whenever assets\Ansi V1.AvroEnco changes.
*)

unit uAvroBaseline;

interface

uses
  System.SysUtils;

const
  (* Resource name inside AvroBaseline.res (ANSI_BASELINE RCDATA). *)
  AVRO_BASELINE_RES_NAME = 'ANSI_BASELINE';

  (* Identity of the shipped baseline. BaselineName is the display name shown
     in the resource browser; BaselineFileName is the name an on-disk copy
     would have. Version / FormatVersion are compared against a manifest
     entry so that a newer signed container supersedes this baseline. *)
  AVRO_BASELINE_NAME           = 'Ansi V1';
  AVRO_BASELINE_FILE_NAME      = 'Ansi V1.AvroEnco';
  AVRO_BASELINE_VERSION        = '1.2';
  AVRO_BASELINE_FORMAT_VERSION = 3;

(* True when the RCDATA resource is present in the image. Cheap; safe to call
  even if the resource was stripped. *)
function AvroBaselineAvailable: Boolean;

(* Raw container bytes copied out of the RCDATA resource. Empty when the
  resource is absent. The caller owns and must wipe the result. *)
function AvroBaselineBytes: TBytes;

(* Reads, decrypts and verifies the embedded baseline. On success AJsonUtf8
  holds the mapping JSON as UTF-8 (caller wipes it) and True is returned. On
  failure AJsonUtf8 is empty and AError explains why - callers fall back to
  Unicode exactly as they do today. *)
function AvroBaselineLoad(out AJsonUtf8: TBytes; out AError: string): Boolean;

implementation

uses
  System.Classes,
  Winapi.Windows,
  uAvroShield,
  uAvroSecureMem;

{$R ../Layout/AvroBaseline.res}

function AvroBaselineAvailable: Boolean;
begin
  Result := FindResource(HInstance, PChar(AVRO_BASELINE_RES_NAME), RT_RCDATA) <> 0;
end;

function AvroBaselineBytes: TBytes;
var
  Stream: TResourceStream;
begin
  Result := nil;
  if not AvroBaselineAvailable then
    Exit;
  Stream := TResourceStream.Create(HInstance, AVRO_BASELINE_RES_NAME, RT_RCDATA);
  try
    SetLength(Result, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Result[0], Stream.Size);
  finally
    Stream.Free;
  end;
end;

function AvroBaselineLoad(out AJsonUtf8: TBytes; out AError: string): Boolean;
var
  Container: TBytes;
  Res: TAvroShieldResult;
begin
  AJsonUtf8 := nil;
  AError := '';

  if not AvroBaselineAvailable then
  begin
    AError := 'embedded baseline resource is missing';
    Exit(False);
  end;

  Container := AvroBaselineBytes;
  try
    if (Container = nil) or (Length(Container) < 16) then
    begin
      AError := 'embedded baseline resource is empty';
      Exit(False);
    end;

    Res := AvroShieldLoadForRuntime(Container, '', AJsonUtf8, True);
    if Res <> asrOk then
    begin
      AJsonUtf8 := nil;
      AError := Format('embedded baseline rejected (AvroShield result %d)',
        [Ord(Res)]);
      Exit(False);
    end;

    if Length(AJsonUtf8) = 0 then
    begin
      AError := 'embedded baseline decrypted to an empty mapping';
      Exit(False);
    end;

    Result := True;
  finally
    (* The ciphertext copy is disposable; wipe it even on the failure path. *)
    AvroWipeAndRelease(Container);
  end;
end;

end.
