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
rem  The generated containers are gated four times: kat_staticleak proves no
rem  plaintext secret or payload leaked into them, kat_flagdetect proves every
rem  one is still detected as a default-key container, kat_ansiconvert
rem  proves the container converts exactly like the source JSON and that the
rem  mapping parser keeps every section, entry and group name it declared, and
rem  kat_engineswitch proves the in-RAM engine cache around them keeps the
rem  requested mapping installed through preload, switch and background
rem  re-parse - a hollowed engine there showed the version as selected while
rem  every kar emitted nothing.
rem
rem  The first two are about shipping safely, the rest about shipping the
rem  mapping that was authored: a container that starts reporting itself as
rem  password protected would prompt on import, one whose rules are dropped on
rem  load would silently convert with the engine's built-in defaults instead of
rem  the mapping's own tables, and a cache that loses the live engine would do
rem  the same thing to a correctly built container at runtime.
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
set "APP=%ROOT%\Keyboard and Spell checker"
set "UNITS=%APP%\Units"
set "CONVERTER=%ROOT%\Unicode to ascii converter"
set "RTL=%BDS%\lib\win32\release"
set "KEYFILE=%ROOT%\keys\avroenco.key"
set "GATEDIR=..\..\tools\AvroShieldSelfTest"

if exist "%KEYFILE%" goto havekey
echo ERROR: default-key secret file not found: %KEYFILE%
echo Generate it with AvroShieldSecretGen\gen_shield_secret.py, e.g.:
echo   python gen_shield_secret.py --secret PHRASE --out-pas "%UNITS%\uAvroShieldSecret.pas" --key-file "%KEYFILE%"
exit /b 1
:havekey

echo [1/7] Compiling AvroEncoBuilder.exe ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" AvroEncoBuilder.dpr
if errorlevel 1 goto buildfailed

echo [2/7] Building assets\Ansi V1..V4.AvroEnco (shield, default-key) ...
for %%F in (V1 V2 V3 V4) do call :onecontainer %%F
if errorlevel 1 goto containfailed

echo [3/7] Compiling the gates ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_staticleak.dpr"
if errorlevel 1 goto gatebuildfailed

dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_flagdetect.dpr"
if errorlevel 1 goto gatebuildfailed

rem  kat_ansiconvert also links the mapping engine, so it needs the converter
rem  folder and VCL on the unit search path; the namespace list adds Vcl and
rem  System.Win for that reason.
dcc32 -CC -Q -B -NS"System;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Xml;Web;Soap" -U"%UNITS%;%CONVERTER%;%RTL%" "%GATEDIR%\kat_ansiconvert.dpr"
if errorlevel 1 goto gatebuildfailed

rem  kat_engineswitch links the engine cache itself, which reaches the
rem  application's registry, layout and forms units, so it needs those folders
rem  on the unit search path. -I"%APP%" resolves the ProjectDefines.inc those
rem  units include relative to their own location.
dcc32 -CC -Q -B -I"%APP%" -NS"System;System.Win;Winapi;Vcl;Vcl.Imaging;Data;Xml;Web;Soap" -U"%UNITS%;%CONVERTER%;%APP%\Classes;%APP%\Forms;%APP%\Layout;%APP%\SpellChecker;%RTL%" "%GATEDIR%\kat_engineswitch.dpr"
if errorlevel 1 goto gatebuildfailed

echo [4/7] Static-leak gate over the generated containers ...
"%GATEDIR%\kat_staticleak.exe" "" "%ROOT%\assets" "..\..\source-mappings"
if errorlevel 1 goto gatefailed

echo [5/7] Protection-flag gate over the generated containers ...
rem  Every shipped container must report the default-key flag AND decrypt with
rem  an empty password, which is exactly what the menu import relies on. The
rem  quiet flag keeps the PASS lines out of the build log; only failures speak.
"%GATEDIR%\kat_flagdetect.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto flaggatefailed

echo [6/7] Conversion + parser-fidelity gate over the generated containers ...
rem  Each container must convert byte-identically to its source JSON sibling,
rem  and loading it must not drop or shrink any section the mapping declares.
"%GATEDIR%\kat_ansiconvert.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto convertgatefailed

echo [7/7] Engine-cache gate over the generated containers ...
rem  Drives the real engine cache: preload, switching, background re-parse and a
rem  deliberately hollowed live engine. Every step must leave the requested
rem  mapping installed and behaving exactly like its fresh-loaded reference.
"%GATEDIR%\kat_engineswitch.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto switchgatefailed

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
echo GATE DID NOT BUILD - no container was shipped
exit /b 1

:gatefailed
echo STATIC LEAK GATE FAILED - no container was shipped
exit /b 1

:flaggatefailed
echo PROTECTION-FLAG GATE FAILED - a container would prompt for a password
exit /b 1

:convertgatefailed
echo CONVERSION GATE FAILED - a container does not match its source mapping
exit /b 1

:switchgatefailed
echo ENGINE-CACHE GATE FAILED - the engine cache does not keep the active mapping
exit /b 1

:nodcc
echo ERROR: dcc32 not found under %BDS%
exit /b 1
