@echo off
rem ---------------------------------------------------------------------------
rem MakeDist.bat - one double-click and dist\ is ready to run.
rem
rem Double-click this file (or run it from a prompt) and it produces a complete
rem deployment in dist\:
rem
rem   1. finds the Qt kit            (C:\Qt\6.11.1\mingw_64, else the newest
rem                                   C:\Qt\6.*\mingw_64 with a windeployqt)
rem   2. finds the shared assets     (..\assets - the monorepo's shared assets
rem                                   folder next to this directory, whose
rem                                   fonts\ directory carries the bundled
rem                                   Bengali fonts)
rem   3. configures + builds Release into build\   (CMake + Ninja, MinGW from the
rem                                   Qt installation - nothing else needed)
rem   4. copies the executable, its .ico and the bundled fonts into dist\
rem   5. deploys the Qt runtime with the trimmed plugin set and drops the plugins
rem                                   this widgets-only app never loads
rem   6. prints the deployment size, then the line to run
rem
rem dist\AvroTextConverter.ini (theme, fonts, ANSI version) is settings, not
rem build output: it is never touched, so the run in dist\ keeps its settings.
rem
rem Usage:  MakeDist.bat [Qt kit dir] [shared assets dir]
rem
rem Both arguments are optional - when they are left out the folders above are
rem searched.  The real work lives in tools\build_release.bat, which is also
rem usable on its own (and by CI); this file is the double-clickable front door.
rem ---------------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0" || exit /b 1

echo ===========================================================================
echo  Avro Text Converter - release build for dist\
echo ===========================================================================
echo.

rem ---- 1. Qt kit ------------------------------------------------------------
set "QT_PREFIX=%~1"
if not defined QT_PREFIX set "QT_PREFIX=C:\Qt\6.11.1\mingw_64"
if not exist "!QT_PREFIX!\bin\windeployqt.exe" (
    set "PICKED="
    for /d %%v in ("C:\Qt\6.*") do (
        if exist "%%~fv\mingw_64\bin\windeployqt.exe" set "PICKED=%%~fv\mingw_64"
    )
    if not defined PICKED (
        echo ERROR: no Qt kit found ^(neither C:\Qt\6.11.1\mingw_64 nor any
        echo        C:\Qt\6.*\mingw_64^).  Pass one as the first argument, e.g.
        echo        MakeDist.bat C:\Qt\6.11.1\mingw_64
        goto :fail
    )
    set "QT_PREFIX=!PICKED!"
)
echo Qt kit        : !QT_PREFIX!

rem ---- 2. shared assets (bundled Bengali fonts) -----------------------------
rem Converter\ sits one level below the repository root, so ..\assets is the
rem shared assets folder.  %~dp0 keeps that true whichever directory this file
rem was started from.
set "ASSETS_DIR=%~2"
if not defined ASSETS_DIR (
    for %%c in ("%~dp0..\assets") do (
        if exist "%%~fc\fonts" set "ASSETS_DIR=%%~fc"
    )
)
if defined ASSETS_DIR (
    echo shared assets : !ASSETS_DIR!  ^(fonts\ gets bundled^)
) else (
    echo shared assets : not found - the build falls back to the fonts installed
    echo                 on the machine ^(pass the folder as the second argument
    echo                 to bundle the Bengali fonts^)
)
echo.

rem ---- 3.-6. build + deploy -------------------------------------------------
if defined ASSETS_DIR (
    call "tools\build_release.bat" "!QT_PREFIX!" "!ASSETS_DIR!"
) else (
    call "tools\build_release.bat" "!QT_PREFIX!"
)
if errorlevel 1 goto :fail

echo.
echo ===========================================================================
echo  READY TO RUN:  !CD!\dist\AvroTextConverter.exe
echo ===========================================================================
popd
endlocal
pause
exit /b 0

:fail
echo.
echo ===========================================================================
echo  BUILD FAILED - dist\ was left as it was
echo ===========================================================================
popd
endlocal
pause
exit /b 1
