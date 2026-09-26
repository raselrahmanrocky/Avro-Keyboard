@echo off
rem ---------------------------------------------------------------------------
rem build_release.bat - one-command release build.
rem
rem   tools\build_release.bat [Qt kit dir] [shared assets dir]
rem
rem 1. configures build\ with -DCMAKE_BUILD_TYPE=Release and builds it,
rem 2. copies the fresh AvroTextConverter.exe and its runtime .ico into dist\,
rem 3. runs windeployqt on it with the trimmed plugin set, then deletes the
rem    plugins this widgets-only app never loads (Qt6Svg + qsvg/qgif/qjpeg;
rem    never imageformats\qico.dll - that is what decodes the app logo),
rem 4. prints the size of the executable and of the whole deployment.
rem
rem The Qt kit defaults to C:\Qt\6.11.1\mingw_64 (or the newest 6.*\mingw_64
rem under C:\Qt); MinGW, CMake and Ninja are looked up next to it.  The second
rem argument is optional and becomes -DAVRO_SHARED_ASSETS=<dir>, the directory
rem whose fonts\ folder is copied next to the executable.  Left out, the shared
rem assets default to ..\assets (the monorepo folder next to Converter\).
rem
rem dist\AvroTextConverter.ini is settings, not build output: it is never
rem touched, so an existing deployment keeps its theme/version/font.
rem ---------------------------------------------------------------------------
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0.." || exit /b 1

set "QT_PREFIX=%~1"
if not defined QT_PREFIX set "QT_PREFIX=C:\Qt\6.11.1\mingw_64"
if not exist "%QT_PREFIX%\bin\windeployqt.exe" (
    rem FindFirstFile only wildcards the last component, so walk C:\Qt\6.* and
    rem look for a mingw_64 kit inside each of them.
    set "PICKED="
    for /d %%v in ("C:\Qt\6.*") do (
        if exist "%%~fv\mingw_64\bin\windeployqt.exe" set "PICKED=%%~fv\mingw_64"
    )
    if not defined PICKED (
        echo ERROR: no Qt kit found.  Pass one as the first argument, e.g.
        echo        tools\build_release.bat C:\Qt\6.11.1\mingw_64
        goto :fail
    )
    set "QT_PREFIX=!PICKED!"
)
echo Qt kit       : !QT_PREFIX!
set "QT_ROOT=!QT_PREFIX!\..\.."

rem Tools shipped with the Qt installation (only added when present, so a
rem shell that already has cmake/ninja/mingw on PATH keeps working).
for /d %%d in ("!QT_ROOT!\Tools\mingw*_64") do set "MINGW_DIR=%%~fd"
for /d %%d in ("!QT_ROOT!\Tools\CMake*")    do set "CMAKE_DIR=%%~fd"
for /d %%d in ("!QT_ROOT!\Tools\Ninja")     do set "NINJA_DIR=%%~fd"
if defined MINGW_DIR set "PATH=!MINGW_DIR!\bin;!PATH!"
if defined CMAKE_DIR set "PATH=!CMAKE_DIR!\bin;!PATH!"
if defined NINJA_DIR set "PATH=!NINJA_DIR!;!PATH!"

where cmake >nul 2>nul || (echo ERROR: cmake not found on PATH & goto :fail)
where ninja >nul 2>nul || (echo ERROR: ninja not found on PATH & goto :fail)

rem Converter\ is one level below the repository root, so %~dp0..\..\assets is
rem the shared assets folder: the default when no directory was passed.  CMake
rem gets it as a normalised absolute path, so it never has to guess what a
rem relative -DAVRO_SHARED_ASSETS would be relative to.
set "ASSETS_DIR=%~2"
if not defined ASSETS_DIR (
    for %%p in ("%~dp0..\..\assets") do (
        if exist "%%~fp\fonts" set "ASSETS_DIR=%%~fp"
    )
)
if defined ASSETS_DIR (
    echo ==^> configure ^(Release, shared assets "!ASSETS_DIR!"^)
    cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="!QT_PREFIX!" ^
          -DCMAKE_BUILD_TYPE=Release "-DAVRO_SHARED_ASSETS=!ASSETS_DIR!" || goto :fail
) else (
    echo ==^> configure ^(Release^)
    echo     no shared assets with a fonts folder at %~dp0..\..\assets - the
    echo     fonts installed on the machine are used instead
    cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH="!QT_PREFIX!" ^
          -DCMAKE_BUILD_TYPE=Release || goto :fail
)

echo ==^> build
cmake --build build || goto :fail

where windeployqt >nul 2>nul || set "PATH=!QT_PREFIX!\bin;!PATH!"
echo ==^> deploy to dist\
if not exist "dist"                 mkdir "dist"
if not exist "dist\assets\icon"     mkdir "dist\assets\icon"
copy /y "build\AvroTextConverter.exe" "dist\AvroTextConverter.exe" >nul || goto :fail

rem The runtime logo (title bar, taskbar, Alt-Tab, tray) is read from
rem <exe dir>\assets\icon\Converter.ico, so the deployment gets its own copy of
rem the shared multi-size icon: the single source of truth, never a file under
rem dist\ (dist is build output) and never the build tree's copy.
if not defined ASSETS_DIR set "ASSETS_DIR=%~dp0..\..\assets"
if exist "!ASSETS_DIR!\icons\Converter.ico" (
    copy /y "!ASSETS_DIR!\icons\Converter.ico" "dist\assets\icon\Converter.ico" >nul || goto :fail
) else (
    echo WARNING: no icon at "!ASSETS_DIR!\icons\Converter.ico" - the runtime
    echo          logo falls back to the drawn accent tile
)

rem The bundled Bengali fonts travel with the executable too: loadBundledFonts
rem reads <exe dir>\assets\fonts, so a machine that does not have them installed
rem still renders correctly.  The build only produces them when a shared assets
rem directory was found or passed (see AVRO_SHARED_ASSETS in CMakeLists.txt).
if exist "build\assets\fonts" (
    if not exist "dist\assets\fonts" mkdir "dist\assets\fonts"
    xcopy /y /q /i "build\assets\fonts\*.*" "dist\assets\fonts\" >nul
    set "FONTS_NOTE=dist\assets\fonts"
) else (
    set "FONTS_NOTE=none ^(pass the shared assets dir to bundle them^)"
)

windeployqt --release --no-translations --no-system-d3d-compiler --no-opengl-sw ^
    --skip-plugin-types generic,iconengines,networkinformation,styles,tls ^
    "dist\AvroTextConverter.exe" || goto :fail

rem windeployqt still copies the image formats and the SVG runtime even when
rem the plugin types are skipped; the app uses none of them.
echo ==^> trim unused Qt plugins
del /q "dist\Qt6Svg.dll" "dist\imageformats\qsvg.dll" ^
       "dist\imageformats\qgif.dll" "dist\imageformats\qjpeg.dll" 2>nul
for %%d in (translations styles tls generic networkinformation) do (
    if exist "dist\%%d" rd /s /q "dist\%%d"
)

if not exist "dist\imageformats\qico.dll" (
    echo ERROR: imageformats\qico.dll is missing - the app logo would not load
    goto :fail
)

rem Size of the executable and of everything that ships in dist\ (batched with
rem dir + %%~zf: no PowerShell or localized `dir` summary parsing needed).
for %%f in ("dist\AvroTextConverter.exe") do set "EXE_BYTES=%%~zf"
set /a TOTAL_BYTES=0
set /a FILE_COUNT=0
for /f "delims=" %%f in ('dir /s /b /a-d "dist"') do (
    set /a TOTAL_BYTES+=%%~zf
    set /a FILE_COUNT+=1
)
set /a EXE_KB=!EXE_BYTES!/1024
set /a TOTAL_MB=!TOTAL_BYTES!/1000000

echo.
echo Release build ready:
echo   dist\AvroTextConverter.exe   !EXE_BYTES! bytes ^(!EXE_KB! KB^)
echo   dist\ total                  !TOTAL_BYTES! bytes ^(~!TOTAL_MB! MB, !FILE_COUNT! files^)
echo   bundled fonts                !FONTS_NOTE!
echo   runtime: Qt6Core/Qt6Gui/Qt6Widgets + platforms\qwindows.dll + imageformats\qico.dll
echo   run   : dist\AvroTextConverter.exe
popd
endlocal
exit /b 0

:fail
echo.
echo BUILD FAILED
popd
endlocal
exit /b 1
