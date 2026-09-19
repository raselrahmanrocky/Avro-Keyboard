@echo off
rem ============================================================
rem  Builds AvroEncoBuilder.exe and regenerates the shipped
rem  ANSI mapping containers (Shield v3 format, default-key).
rem
rem  Two secrets drive this build, and the builder embeds neither:
rem
rem    keys\avroenco.key     default-key IKM for the container itself
rem    keys\avrocomments.key developer comment IKM
rem
rem  The comment key is what keeps the authored Bengali documentation in the
rem  mapping ("0", "the first half of m", ligature notes) unreadable to anyone
rem  who opens a container, while still letting a developer recover it with
rem  AvroEncoBuilder --unpack. It is never derived from a container key and is
rem  never linked into the runtime, so extracting the app secret does not
rem  disclose it. Losing it means the comments in already-built containers are
rem  gone for good - the tracked authored sources in assets\Ansi V*.json are
rem  the other record, so keep a backup of the key outside the repository.
rem
rem  Rotate the container secret with AvroShieldSecretGen\gen_shield_secret.py
rem  --out-pas, then rerun this script to regenerate every container. Generate
rem  the comment key the same way but WITHOUT --out-pas:
rem
rem    python gen_shield_secret.py --random 44 --key-file keys\avrocomments.key
rem
rem  The generated containers are gated six times: kat_staticleak proves that
rem  no plaintext secret or payload leaked into them AND that the unwrapped
rem  payload (the view an attacker has after recovering the key) carries no
rem  legible Bengali, no '#$' literal and no authored mapping text;
rem  kat_flagdetect proves every one is still detected as a default-key
rem  container; kat_ansiconvert proves the container converts exactly like the
rem  authored source JSON beside it in assets\ and that the mapping parser keeps
rem  every section, entry and group name it declared; kat_engineswitch proves
rem  the in-RAM engine cache around them keeps the requested mapping installed
rem  through preload, switch and background re-parse - a hollowed engine there
rem  showed the version as selected while every kar emitted nothing; and
rem  kat_obfcodec proves the obfuscation codec and the developer comment domain
rem  behave (keyed metadata mask, comment text unrecoverable without the
rem  comment key, comments skipped for free at runtime); and kat_iconsection
rem  proves every container carries a usable per-layout icon, in a frame set
rem  the tray and the menus actually draw at 100/125/150/200% display scaling.
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
set "COMMENTKEY=%ROOT%\keys\avrocomments.key"
set "GATEDIR=..\..\tools\AvroShieldSelfTest"

if exist "%KEYFILE%" goto havekey
echo ERROR: default-key secret file not found: %KEYFILE%
echo Generate it with AvroShieldSecretGen\gen_shield_secret.py, e.g.:
echo   python gen_shield_secret.py --secret PHRASE --out-pas "%UNITS%\uAvroShieldSecret.pas" --key-file "%KEYFILE%"
exit /b 1
:havekey

if exist "%COMMENTKEY%" goto havecommentkey
echo ERROR: developer comment key not found: %COMMENTKEY%
echo Generate it with AvroShieldSecretGen\gen_shield_secret.py (no --out-pas:
echo this key must never be linked into the application), e.g.:
echo   python gen_shield_secret.py --random 44 --key-file "%COMMENTKEY%"
exit /b 1
:havecommentkey

echo [1/9] Compiling AvroEncoBuilder.exe ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" AvroEncoBuilder.dpr
if errorlevel 1 goto buildfailed

echo [2/9] Building assets\Ansi V1..V4.AvroEnco from assets\Ansi V*.json (shield v3, default-key) ...
for %%F in (V1 V2 V3 V4) do call :onecontainer %%F
if errorlevel 1 goto containfailed

echo [3/9] Compiling the gates ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_staticleak.dpr"
if errorlevel 1 goto gatebuildfailed

dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_flagdetect.dpr"
if errorlevel 1 goto gatebuildfailed

dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_obfcodec.dpr"
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

rem  kat_iconsection synthesises its own ICOs and builds a password-protected
rem  container of its own, so unlike the others it needs no key file and no
rem  asset folder to be runnable.
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" "%GATEDIR%\kat_iconsection.dpr"
if errorlevel 1 goto gatebuildfailed

echo [4/9] Static-leak gate over the generated containers ...
rem  Scans both the container bytes and the unwrapped payload. The second pass
rem  is the one that would catch a build that shipped legible mapping text or
rem  fell back to a non-keyed obfuscation mask. The authored json sources now
rem  sit beside the containers in assets\, so the container folder is also the
rem  canary source: every container is paired with the <name>.json beside it.
"%GATEDIR%\kat_staticleak.exe" "" "%ROOT%\assets" "%ROOT%\assets"
if errorlevel 1 goto gatefailed

echo [5/9] Protection-flag gate over the generated containers ...
rem  Every shipped container must report the default-key flag AND decrypt with
rem  an empty password, which is exactly what the menu import relies on. The
rem  quiet flag keeps the PASS lines out of the build log; only failures speak.
"%GATEDIR%\kat_flagdetect.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto flaggatefailed

echo [6/9] Conversion + parser-fidelity gate over the generated containers ...
rem  Each container must convert byte-identically to the authored json source
rem  beside it in assets\, and loading it must not drop or shrink any
rem  section the mapping declares.
"%GATEDIR%\kat_ansiconvert.exe" "%ROOT%\assets" "%ROOT%\assets" quiet
if errorlevel 1 goto convertgatefailed

echo [7/9] Engine-cache gate over the generated containers ...
rem  Drives the real engine cache: preload, switching, background re-parse and a
rem  deliberately hollowed live engine. Every step must leave the requested
rem  mapping installed and behaving exactly like its fresh-loaded reference.
rem  It also pins the encoding-list order the menus and picker share, the
rem  picker's number (row + numpad) and first-letter shortcut resolution, the
rem  application theme contract (SYSTEM / LIGHT / DARK resolution against
rem  Windows' AppsUseLightTheme plus the dark and light palettes), and the
rem  "Select ANSI Encoding" items: the tray one present in the DFM directly
rem  under "Select keyboard layout", an empty shell there, wired into the same
rem  build and checkmark-sync routines as the other two ANSI menus, and BOTH
rem  parent items given the active layout's badge - resolved through the one
rem  lookup the submenu rows use, at ImageList1's own metric rather than from
rem  the DPI-scaled tray handle, and before the tray/TopBar split so the TopBar
rem  branch refreshes it too.
"%GATEDIR%\kat_engineswitch.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto switchgatefailed

echo [8/9] Obfuscation codec + comment domain gate ...
rem  Pins the codec contract: keyed metadata mask, positional salting, comment
rem  text unrecoverable without the comment key (and not even held in memory on
rem  the runtime path), plus the frozen v2 fixture that proves the legacy read
rem  path still works.
"%GATEDIR%\kat_obfcodec.exe" "%ROOT%\assets" "%COMMENTKEY%" quiet
if errorlevel 1 goto obfcodecfailed

echo [9/9] Layout-icon gate over the generated containers ...
rem  Proves the icon section itself: the frame-selection rule (an exact frame
rem  wins, otherwise the smallest frame that is at least as large, so the 125%
rem  and 150% tray metrics never fall back to the largest frame), that
rem  CreateHIconAtSize hands Windows a handle measuring EXACTLY the requested
rem  metric, that the icon survives the whole container pipeline byte-for-byte,
rem  that a container without it still loads, and - for every shipped
rem  container - that a 16 px frame is present and nothing above
rem  AVRO_ICON_MAX_FRAME_SIZE is carried.
"%GATEDIR%\kat_iconsection.exe" "%ROOT%\assets" quiet
if errorlevel 1 goto icongatefailed

echo Done.
endlocal
exit /b 0

:onecontainer
rem Explicit path: some Windows configurations set
rem NoDefaultCurrentDirectoryInExePath, which makes a bare
rem "AvroEncoBuilder.exe" fail with "not recognized" even though the file is
rem sitting in the current directory.
rem  The per-layout icon is embedded INSIDE the payload (one scalar Base64
rem  member), so it inherits the container's HMAC verdict, AES-GCM tag and
rem  obfuscation instead of needing a second container format or a sidecar file.
rem  Only the frames the tray and the menus actually draw are embedded - the
rem  authored 256 px frame alone is 270 KB, five times a whole container.
rem  kat_iconsection fails the build if that ever regresses.
"%~dp0AvroEncoBuilder.exe" "%ROOT%\assets\Ansi %1.json" "%ROOT%\assets\Ansi %1.AvroEnco" --pack --default-key --format shield --secret-file "%KEYFILE%" --comments-key-file "%COMMENTKEY%" --icon "%ROOT%\assets\icons\Ansi%1.ico"
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
echo STATIC LEAK GATE FAILED - legible text or a secret leaked into a container
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

:obfcodecfailed
echo OBFUSCATION GATE FAILED - the codec or the comment domain regressed
exit /b 1

:icongatefailed
echo LAYOUT-ICON GATE FAILED - a container's icon is missing, oversized or mis-sized
exit /b 1

:nodcc
echo ERROR: dcc32 not found under %BDS%
exit /b 1
