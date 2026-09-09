@echo off
rem ============================================================
rem  Builds AvroEncoBuilder.exe and regenerates the shipped
rem  ANSI mapping containers (Shield format, default-key).
rem
rem  Requirements: Delphi 10.3+ dcc32. Adjust BDS below if your
rem  Studio version differs from 23.0 (Delphi 12.x).
rem ============================================================
setlocal
cd /d "%~dp0"
set "BDS=C:\Program Files (x86)\Embarcadero\Studio\23.0"
if not exist "%BDS%\bin\dcc32.exe" (
  echo ERROR: dcc32 not found under %BDS%
  exit /b 1
)
set "ROOT=..\..\.."
set "UNITS=%ROOT%\Keyboard and Spell checker\Units"
set "RTL=%BDS%\lib\win32\release"

echo [1/2] Compiling AvroEncoBuilder.exe ...
dcc32 -CC -Q -B -NS"System;Winapi;Data;Xml;Web;Soap" -U"%UNITS%;%RTL%" AvroEncoBuilder.dpr
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)

echo [2/2] Building assets\Ansi V1..V4.AvroEnco (shield, default-key) ...
for %%F in (V1 V2 V3 V4) do (
  AvroEncoBuilder.exe "..\..\source-mappings\Ansi %%F.json" "..\..\..\assets\Ansi %%F.AvroEnco" --default-key --format shield
  if errorlevel 1 (
    echo FAILED: Ansi %%F
    exit /b 1
  )
)
echo Done.
endlocal