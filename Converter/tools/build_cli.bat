@echo off
rem ---------------------------------------------------------------------------
rem build_cli.bat - builds AvroConvertCLI.exe, the standalone converter.
rem
rem No Qt and no RAD Studio needed, but the ANSI mappings now arrive as
rem encrypted .AvroEnco containers, so the CLI links the same reader the GUI
rem uses: that reader inflates with zlib and hashes/decrypts through Windows
rem CNG (bcrypt).  The Embarcadero C++ toolchain ships no zlib headers or
rem import library, so this builds with MinGW-w64 g++ (-lbcrypt -lz) - the
rem same compiler the Qt build uses, and the recipe tools\enco_dump.cpp
rem documents for the reader.
rem
rem   tools\build_cli.bat [g++ path]
rem
rem g++ is taken from the argument, then %CXX%, then PATH, then the MinGW that
rem sits next to a Qt installation (C:\Qt\Tools\mingw*_64).
rem
rem No shared assets are involved: the CLI bundles no fonts and no mappings -
rem the ANSI mapping is a command-line argument (usage is printed below).
rem ---------------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion
set "CORE=%~dp0..\src\core"
set "OUT=%~dp0AvroConvertCLI.exe"

set "GXX=%~1"
if not defined GXX set "GXX=%CXX%"
if not defined GXX set "GXX=g++"
where "!GXX!" >nul 2>nul
if errorlevel 1 (
    set "MINGW="
    for /d %%d in ("C:\Qt\Tools\mingw*_64") do set "MINGW=%%~fd"
    if not defined MINGW (
        echo ERROR: "!GXX!" not found.  Pass the compiler, e.g.
        echo        tools\build_cli.bat C:\Qt\Tools\mingw1310_64\bin\g++.exe
        exit /b 1
    )
    set "PATH=!MINGW!\bin;!PATH!"
)

echo ==^> compile with !GXX!
"!GXX!" -std=c++17 -O2 -I"!CORE!" -o "!OUT!" ^
    "%~dp0cli_converter.cpp" ^
    "!CORE!\ansi_registry.cpp" "!CORE!\avroenco_reader.cpp" ^
    "!CORE!\sweep_table.cpp" "!CORE!\unicode_to_bijoy.cpp" ^
    "!CORE!\bijoy_to_unicode.cpp" ^
    -lbcrypt -lz -ladvapi32 -lpsapi
if errorlevel 1 goto :fail

for %%f in ("!OUT!") do echo built: %%~ff (%%~zf bytes)
echo.
echo usage: AvroConvertCLI.exe ^<u2a^|a2u^> ^<mapping^> ^<in.txt^> ^<out.txt^> [--bench]
echo        (mapping: "Ansi V3", "SutonnyMJ", "BanglaPedia v1.3")
endlocal
exit /b 0

:fail
echo.
echo BUILD FAILED
endlocal
exit /b 1
