@echo off
rem ============================================================
rem  Builds AvroEncoBuilder.exe and regenerates the shipped
rem  ANSI mapping containers (Shield format, default-key).
rem
rem  The default-key secret is supplied through --secret-file from
rem  keys\avroenco.key: the builder deliberately embeds no secret of its own,
rem  so building or running the tool never exposes one. Rotate with
rem  AvroShieldSecretGen\gen_shield_secret.py --out-pas, then rerun this
rem  script to regenerate every container against the new secret.
rem
rem  STYLE NOTE: this script uses labels and goto, never parenthesised
rem  if-blocks. The Delphi path expands to "C:\Program Files (x86)\..."
rem  and an unquoted (x86) inside a parenthesised block ends the block early,
rem  producing the thoroughly misleading "was unexpected at this time" error.
rem
rem  Requirements: Delphi 10.3+ dcc32. Adjust BDS below if your Studio
rem  version differs from 23.0 (Delphi 12.x).
rem ============================================================
setlocal
cd /d "%~dp0"

set "BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0"
if not exist "%BDS%\bin\dcc32.exe" goto nodcc

set "ROOT=..\..\.."
set "UNITS=%ROOT%\Keyboard and Spell checker\Units"
set "RTL=%BDS%\lib\win32\release"
set "KEYFILE=%ROOT%\keys\avroenco.key"
set "GATEDIR=..\..\tools\AvroShieldSelfTest"

if exist "%KEYFILE%" goto havekey
echo ERROR: default-key secret file not found: %KEYFILE%
echo Generate it with AvroShieldSecretGen\gen_shield_secret.py, e.g.:
echo   python gen_shield_secret.py --secret PHRASE --out-pas "%UNITS%\uAvroShieldSecret.pas" --key-file "%KEYFILE%"
exit /b 1
:havekey

echo [1/4] Compiling AvroEncoBuilder.exe ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" AvroEncoBuilder.dpr
if errorlevel 1 goto buildfailed

echo [2/4] Building assets\Ansi V1..V4.AvroEnco (shield, default-key) ...
for %%F in (V1 V2 V3 V4) do call :onecontainer %%F
if errorlevel 1 goto containfailed

echo [3/4] Compiling the static-leak gate ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_staticleak.dpr"
if errorlevel 1 goto gatebuildfailed

echo [4/4] Static-leak gate over the generated containers ...
"%GATEDIR%\kat_staticleak.exe" "" "%ROOT%\assets" "..\..\source-mappings"
if errorlevel 1 goto gatefailed

echo Done.
endlocal
exit /b 0

:onecontainer
rem Explicit path: some Windows configurations set
rem NoDefaultCurrentDirectoryInExePath, which makes a bare
rem "AvroEncoBuilder.exe" fail with "not recognized" even though the file is
rem sitting in the current directory.
"%~dp0AvroEncoBuilder.exe" "..\..\source-mappings\Ansi %1.json" "..\..\..\assets\Ansi %1.AvroEnco" --default-key --format shield --secret-file "%KEYFILE%"
if errorlevel 1 echo FAILED: Ansi %1
exit /b %errorlevel%

:buildfailed
echo BUILD FAILED
exit /b 1

:containfailed
echo CONTAINER BUILD FAILED - no container was shipped
exit /b 1

:gatebuildfailed
echo STATIC LEAK GATE DID NOT BUILD - no container was shipped
exit /b 1

:gatefailed
echo STATIC LEAK GATE FAILED - no container was shipped
exit /b 1

:nodcc
echo ERROR: dcc32 not found under %BDS%
exit /b 1
