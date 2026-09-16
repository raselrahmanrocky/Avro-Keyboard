{ =============================================================================
  uAvroShieldVM - VMProtect SDK integration, compiled out by default.

  A NOTE ON COMMENT SAFETY IN THIS FILE

  Delimiter characters are avoided inside prose here. In Delphi a dollar
  immediately after an opening brace starts a real compiler directive, so a
  comment that shows such a sequence verbatim is terminated early at its
  closing brace and the remainder of the comment is compiled as code. Likewise
  a paren-star pair appearing inside a paren-star comment closes that comment.
  Both mistakes were made in this file's first draft and produced a confusing
  shower of errors far from the real cause.

  DESIGN: THE MARKERS MUST BE OPTIONAL

  VMProtect's marker functions live in VMProtectSDK32/64.dll. The VMProtect
  tool recognises the calls at protection time and REPLACES them, so a
  protected binary carries no runtime dependency on the DLL. An unprotected
  build that still referenced them would fail to start on a machine without
  the SDK installed, so the imports are gated behind the AVROSHIELD_VMPROTECT
  compile-time symbol and compile to no-ops otherwise. That keeps CI, the KAT
  suite, the builder and every developer build working with no SDK present,
  while the release build defines the symbol and then runs

      VMProtect_Con.exe avroshield.vmp

  in marker mode over the built executable.

  MARKER PLACEMENT RULES, FROM THE SHAPE OF THIS CODEBASE

    * Mark LEAF routines. Do not wrap AvroShieldLoadFromBytesUtf8 or
      AvroShieldBuildFromJson: they are long, contain try/finally (SEH),
      TMemoryStream and string temporaries, and virtualising that shape is the
      classic VMProtect breakage and performance trap. The secret lives in the
      leaf routines that touch key material, not in the plumbing.
    * Keep the marker pair free of SEH where the routine cannot raise.
    * Compile marker-bearing units with inlining disabled (see the unit
      headers). With inlining enabled Delphi may inline a marked routine into
      its caller, leaving an unprotected copy of exactly the logic that was
      virtualised.

  WHAT THIS BUYS, HONESTLY

  The embedded secret is the single point of failure for every container.
  Virtualising its expansion turns "XOR two adjacent arrays" into "reverse a
  VM with no meaningful static structure": a cost increase from minutes to
  days or weeks, not a proof. An attacker with a debugger and unlimited time
  can still recover a value the process must reconstruct. Pair it with the
  static-leak gate, which catches the far more likely failure where protection
  is configured wrong and the secret ends up in the clear anyway.
  ============================================================================= }

unit uAvroShieldVM;

interface

{$IFDEF AVROSHIELD_VMPROTECT}

{$IFDEF CPUX64}
procedure _VMBeginVirtualization(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectBeginVirtualization';
procedure _VMBeginMutation(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectBeginMutation';
procedure _VMBeginUltra(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectBeginUltra';
procedure _VMEnd; stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectEnd';
function _VMIsDebuggerPresent(const ACheckKernelMode: Boolean): Boolean; stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectIsDebuggerPresent';
function _VMIsVirtualMachinePresent: Boolean; stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectIsVirtualMachinePresent';
function _VMIsValidImageCRC: Boolean; stdcall;
  external 'VMProtectSDK64.dll' name 'VMProtectIsValidImageCRC';
{$ELSE}
procedure _VMBeginVirtualization(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectBeginVirtualization';
procedure _VMBeginMutation(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectBeginMutation';
procedure _VMBeginUltra(const AName: PAnsiChar); stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectBeginUltra';
procedure _VMEnd; stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectEnd';
function _VMIsDebuggerPresent(const ACheckKernelMode: Boolean): Boolean; stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectIsDebuggerPresent';
function _VMIsVirtualMachinePresent: Boolean; stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectIsVirtualMachinePresent';
function _VMIsValidImageCRC: Boolean; stdcall;
  external 'VMProtectSDK32.dll' name 'VMProtectIsValidImageCRC';
{$ENDIF}

{$ENDIF}

{ Marker wrappers. The marker names are short and deliberately meaningless:
  VMProtect records them in its protection report, and they are visible in a
  strings dump of the unprotected binary. }

{ Heaviest transform: the secret expansion and the field-id resolver. }
procedure VMBeginUltra(const AName: PAnsiChar);

{ Full virtualisation: key derivation and the constant-time comparisons. }
procedure VMBeginVirtualization(const AName: PAnsiChar);

{ Code mutation only, for hot paths where VM overhead would be measurable. }
procedure VMBeginMutation(const AName: PAnsiChar);

procedure VMEnd;

{ Environment self-check. Returns True when nothing suspicious was detected.

  With AVROSHIELD_VMPROTECT undefined this always returns True: the absence of
  a check must be reported as "no signal", never as "tampering", or every
  developer and CI build would take the fail-closed path. These signals are
  advisory inputs to the fail-closed policy, never an authority - each of them
  is individually defeatable. }
function ShieldSelfCheck(out ADebuggerUserMode, ADebuggerKernelMode: Boolean;
  out AVirtualMachine, AImageIntact: Boolean): Boolean;

implementation

{$IFDEF AVROSHIELD_VMPROTECT}

procedure VMBeginUltra(const AName: PAnsiChar);
begin
  _VMBeginUltra(AName);
end;

procedure VMBeginVirtualization(const AName: PAnsiChar);
begin
  _VMBeginVirtualization(AName);
end;

procedure VMBeginMutation(const AName: PAnsiChar);
begin
  _VMBeginMutation(AName);
end;

procedure VMEnd;
begin
  _VMEnd;
end;

function ShieldSelfCheck(out ADebuggerUserMode, ADebuggerKernelMode: Boolean;
  out AVirtualMachine, AImageIntact: Boolean): Boolean;
begin
  ADebuggerUserMode := _VMIsDebuggerPresent(False);
  ADebuggerKernelMode := _VMIsDebuggerPresent(True);
  AVirtualMachine := _VMIsVirtualMachinePresent;
  { False means the executable image was modified, including by a debugger
    patching code in memory. }
  AImageIntact := _VMIsValidImageCRC;
  Result := (not ADebuggerUserMode) and (not ADebuggerKernelMode) and
    AImageIntact;
end;

{$ELSE}

procedure VMBeginUltra(const AName: PAnsiChar);
begin
end;

procedure VMBeginVirtualization(const AName: PAnsiChar);
begin
end;

procedure VMBeginMutation(const AName: PAnsiChar);
begin
end;

procedure VMEnd;
begin
end;

function ShieldSelfCheck(out ADebuggerUserMode, ADebuggerKernelMode: Boolean;
  out AVirtualMachine, AImageIntact: Boolean): Boolean;
begin
  ADebuggerUserMode := False;
  ADebuggerKernelMode := False;
  AVirtualMachine := False;
  AImageIntact := True;
  Result := True;
end;

{$ENDIF}

end.
