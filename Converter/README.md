# Avro Text Converter (Qt / C++ port)

A C++ / Qt 6 (Widgets) port of the Delphi VCL application **"Avro Text
Converter"** (`Unicode to ascii converter/` in the repo root).  It converts
Bengali text between Unicode and the ANSI Bijoy encodings (Ansi V3,
SutonnyMJ, BanglaPedia v1.3) with the **exact same conversion results** as
the original Delphi code - verified byte-for-byte on a 20 MB sample across
all three mappings, both directions.

```
src/
  core/            Pure, dependency-free C++17 conversion engine
                     bangla_chars.h          Bengali Unicode code points
                     sweep_table.h/.cpp      longest-match-first sweep engine
                     ansi_registry.h/.cpp    ANSI glyph registry + mapping loader
                     avroenco_reader.h/.cpp  encrypted .AvroEnco container reader
                     unicode_to_bijoy.h/.cpp Unicode (Bengali) -> Bijoy ANSI
                     bijoy_to_unicode.h/.cpp Bijoy ANSI -> Unicode
  ui/              Qt Widgets layer
                     mainwindow.h/.cpp       main window
                     memoedit.h/.cpp         memo with Ctrl+wheel zoom + menu
                     fontpicker.h/.cpp       searchable font picker
tools/
  cli_converter.cpp      standalone CLI converter (no Qt required)
  build_cli.bat          builds AvroConvertCLI.exe with bcc32x
  enco_dump.cpp          decode an .AvroEnco container to JSON (debug helper)
  make_multi_size_ico.py regenerate the multi-resolution app icon
```

## Features (Qt GUI)

- **Faithful layout** - toolbar with *Unicode to ANSI* / *ANSI to Unicode*
  buttons, ANSI-version picker, searchable font picker and a gear menu
  (*Settings...*, *About*, theme entries); two memo panels split by a vertical
  splitter; footer with a context tip, live character counter and a progress
  bar.
- **Polished, modern styling** - `#E67E22` accent, rounded memo cards with
  focus highlighting, styled buttons/combos/scrollbars/menus, and full
  **Light / Dark / System** themes (System follows the Windows
  `AppsUseLightTheme` setting).  Theme switching is instant and flicker-free.
- **No UI freezes** - conversion runs on a background thread
  (`QtConcurrent`); progress is throttled to a few updates per second and
  the footer shows the current stage ("Converting… consonants (63%)").
  Multi-megabyte documents convert without locking the window.  ANSI
  mappings are decrypted and parsed on a worker thread as well, so a slow
  mapping folder never stalls the picker or the reload either.
- **Flicker-free memo loading** - converted text is streamed into the memo
  with repaints and the undo stack suspended and restored in a single edit
  block, and the caret is restored to its pre-conversion position.
- **Quick to start** - the window is up in a fraction of a second: the font
  collection is walked once, the window-button glyphs are *painted* instead of
  typeset (asking Qt for an icon font that is not installed - "Segoe Fluent
  Icons" on Windows 10, where only "Segoe MDL2 Assets" exists - made it search
  the whole font collection for a fallback, ~0.4 s on the first paint), and the
  ANSI mapping is decrypted on a worker thread.
- **Zoom** - `Ctrl+wheel`, `Ctrl++` / `Ctrl+-` / `Ctrl+0` per memo, and a
  rich right-click menu (Cut/Copy/Paste/Select All/Clear + zoom).
- **Bundled fonts** - the repo's `assets/fonts` (.ttf) are loaded
  automatically, so Bengali renders correctly even if **Bornomala** /
  **Kalpurush ANSI** are not installed system-wide.
- **Persistence** - theme, ANSI version and converter font are stored in a
  portable `AvroTextConverter.ini` next to the executable (the same keys the
  original Delphi app keeps in the registry).
- **Settings dialog** - a single sheet behind the gear icon's *Settings...*
  entry: per-box font family and point size, an optional font per ANSI mapping
  picked on the mapping's own row, and OK / Apply / Cancel / Reset to Defaults -
  see [Settings](#settings).
- **Logo everywhere** - the bundled `assets/icon/Converter.ico` is embedded in
  the `.exe` (Explorer, taskbar, Alt-Tab), reused for the title bar and for a
  notification-area icon with a *Show / Hide window* + *Exit* menu.  The icon
  carries one bitmap per size (16-128px), so the 16px tray renditions stay
  sharp instead of being rescaled from a single large master.

## Building with Qt

The project was built and tested with **Qt 6.11.1 (mingw_64)** and the
bundled **MinGW 13.1** + **CMake 3.30** + **Ninja** from the Qt installation
(`C:\Qt\Tools\...`).  From a Git Bash / cmd with those tools on the PATH:

```bash
export PATH="/c/Qt/Tools/mingw1310_64/bin:/c/Qt/Tools/CMake_64/bin:/c/Qt/Tools/Ninja:$PATH"
cd Qt-Avro-Converter
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=C:/Qt/6.11.1/mingw_64 -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

`MakeDist.bat` in the repository root is the double-clickable front door: it
looks for the Qt kit and for the shared assets folder (the one whose `fonts\`
directory carries the bundled Bengali fonts), then runs the release script
below, so one double-click leaves `dist\` ready to run - the
`dist\AvroTextConverter.ini` already sitting there keeps its settings.  Both
steps it finds can be overridden with the same two optional arguments.

`tools\build_release.bat` does the whole release in one step: configure and
build Release into `build\`, copy the executable, its `.ico` and the bundled
Bengali fonts into `dist\`, deploy the Qt runtime with the trimmed plugin set
below, delete the plugins the app never loads (`Qt6Svg.dll`,
`imageformats\qsvg|qgif|qjpeg.dll` - never `qico.dll`), and print the size of
the executable, the bundled fonts and the whole deployment.
It leaves `dist\AvroTextConverter.ini` (settings, not build output) alone.

```bash
MakeDist.bat                                  # double-click: Qt kit + assets found for you
tools\build_release.bat                                  # from cmd.exe
cmd //c tools\\build_release.bat                         # from Git Bash
cmd //c "tools\\build_release.bat C:\Qt\6.11.1\mingw_64 ..\assets"
```

The optional arguments are the Qt kit (default `C:\Qt\6.11.1\mingw_64`, else
the newest `6.*\mingw_64` under `C:\Qt`) and the shared assets directory whose
`fonts\` folder gets bundled (`-DAVRO_SHARED_ASSETS`).  The commands below are
what the script runs, for a manual build.

The bundled Bengali fonts are copied next to the executable at build
time.  The ANSI mappings are **not** bundled at all: the app reads them from
the system-wide Avro Keyboard installation
(`C:\ProgramData\Avro Keyboard\AnsiMapping`), exactly like the original
Delphi app's `AnsiMappingDir` - see [ANSI mappings](#ansi-mappings).  To make
the build folder self-contained (so the `.exe` runs on any machine with Avro
Keyboard installed), deploy the Qt runtime DLLs once:

```bash
cd build
windeployqt --release --no-translations --no-system-d3d-compiler --no-opengl-sw \
    --skip-plugin-types generic,iconengines,networkinformation,styles,tls \
    AvroTextConverter.exe
```

Then just double-click `build\AvroTextConverter.exe`.

The app is widgets-only and never uses the network, SVG, GIF/JPEG, touch input
or the Windows 11 style plugin (`main.cpp` forces `Fusion`), so the flags above
produce a working ~35 MB deployment instead of ~42 MB - each skipped plugin
family would otherwise drag in `Qt6Network.dll`, `Qt6Svg.dll` or the 4 MB
`D3Dcompiler_47.dll` (only loaded by the Qt Quick/D3D RHI backends).
`windeployqt` still copies `imageformats/qsvg.dll`, `qgif.dll` and `qjpeg.dll`;
they are unused, but **never remove `imageformats/qico.dll`** - that is the
plugin Qt decodes the bundled `.ico` logo with.

### Application icon

Explorer, the taskbar and Alt-Tab read a Windows executable's icon from an
`RT_GROUP_ICON` resource compiled into it - a runtime `QIcon`
(`MainWindow::makeAppIcon`) is not enough, which is why a build without a
resource file shows the generic "application" glyph instead of a logo.
CMake therefore compiles `assets/icon/Converter.ico` into the binary through
`src/app_icon.rc.in`.  Point `-DAVRO_APP_ICON=<file>.ico` at a different icon
to override it (CMake prints the one it picked at configure time).

The same file drives the runtime icons: `MainWindow::makeAppIcon()` loads it
from `assets/icon/` next to the executable (falling back to the drawn accent
tile when the asset is missing) and registers *every* size stored inside it,
so the title bar, taskbar, Alt-Tab and notification area each pick their own
bitmap instead of rescaling the 128px master.

A multi-resolution icon is generated from a single-size master with the
stdlib-only helper (area-average downscale, premultiplied alpha, one AND mask
per size):

```bash
python tools/make_multi_size_ico.py assets/icon/Converter.ico assets/icon/Converter.ico
```

The fonts are only copied next to the executable when the shared assets
directory exists; override it with `-DAVRO_SHARED_ASSETS=<dir>` (it must
contain `fonts/`).  A build without it still succeeds and the app falls back
to the fonts installed system-wide.

### ANSI mappings

The converter ships **no** mapping tables.  At startup (and on every version
change in the toolbar combo) it reads them from the Avro Keyboard
installation, taking whichever file it finds first:

- `Ansi V1.AvroEnco` ... - the encrypted container the current Avro Keyboard
  ships.  It is decrypted and deobfuscated **in RAM** (`src/core/avroenco_reader.*`,
  a port of `uAvroShield`/`uAvroShieldSecret`/`uAvroEncoCrypto`): header ->
  AES-256-GCM (authenticated) -> zlib -> `AVROBC` bytecode -> deobfuscate ->
  mapping JSON.  The plaintext never touches the disk.  Developer `Comment`
  fields are dropped, exactly as in the original engine's runtime path.
- `Ansi V1.json` - the readable form, still accepted for older installations.

A same-named `.AvroEnco` wins over a `.json`, so an installation that has both
loads the container.  The combo lists every version found (deduplicated by
name, naturally sorted), and a missing/corrupt mapping is reported in a dialog
without disturbing the mapping that is already active.

`AVRO_MAPPING_DIR` points the app at a different mapping folder instead of
ProgramData - handy for a portable copy, and for testing a mapping change
without touching the installed Avro Keyboard.

#### Live refresh

The mapping folder is watched (`QFileSystemWatcher`), so nothing needs a
restart when the files change while the window is open:

- a version added or removed shows up in the combo immediately (the current
  pick is kept; a version that disappears falls back to the first mapping the
  folder offers, and comes back when the file does);
- rewriting the file behind the **active** version - e.g. `AvroEncoBuilder`
  shipping an update - reloads that mapping in place and says so in the footer.
  The container is decrypted and parsed on a worker thread and only the
  finished mapping is installed on the UI thread;
- a file that is unreadable while it is being written is retried for a couple
  of seconds, and a mapping update that never loads is reported while the
  mapping already in memory keeps working;
- a mapping change that arrives mid-conversion is installed once the conversion
  finishes, because the worker thread is reading the registry.  A conversion
  requested while a mapping is still loading waits for that load first, so it
  never converts against the mapping that is being replaced.

`tools/enco_dump.cpp` is a Qt-free dev tool that decodes any container to JSON
with the same reader, which makes debugging a mapping change easy:

```bash
g++ -std=c++17 -O2 -Isrc -o tools/enco_dump.exe tools/enco_dump.cpp \
    src/core/avroenco_reader.cpp -lbcrypt -lz -ladvapi32
./tools/enco_dump.exe "/c/ProgramData/Avro Keyboard/AnsiMapping/Ansi V3.AvroEnco" out.json
```

Container support is Windows-only (the reader uses CNG/`bcrypt` for SHA-512,
HMAC and AES, and zlib from the toolchain; CMake links `bcrypt` and `z`).

### Settings

The gear icon in the title bar opens a menu with *Settings...* (above
*About Avro Text Converter*).  The sheet is **one page**, top to bottom:

- **Unicode box** - the family and point size the top (Unicode) editor uses.
- **ANSI box** - the same for the bottom (ANSI) editor.  It is also the font
  every mapping follows unless that mapping has a font of its own, so changing
  it moves those rows along with it.  The font picker in the main window's
  toolbar edits this same font - *and only this one*: a per-mapping font is set
  here, in the sheet, and the toolbar never rewrites a mapping's row.
- **ANSI mappings** - one row per mapping found in the mapping folder: its
  switch, its name, and the family that renders it, selectable right next to
  the name.  The list hugs its rows and only grows a scrollbar when a folder
  offers more mappings than fit.

There are deliberately no tabs, no preview panes and no filter box: every
setting is on one screen, and a font is edited on the row that carries it
instead of in a separate "selected mapping" panel.

On a mapping row the font and the switch are *two independent things* - the
switch says whether the font is used, and nothing else:

- **switch on** - the mapping renders with the family shown next to it.  Picking
  a family turns the switch on by itself, so a pick is never silently dropped,
  and switching a row on for the first time starts from the ANSI box font.
- **switch off** - the mapping renders with the ANSI box font (and follows it
  when that font changes) *for now*.  What the row shows does not change: the
  family the user selected stays selected and stays on screen, the switch just
  stops it from being used.  It survives Apply and a restart that way, because
  the family is stored even while the switch is off.

So the toggle never resets a font: whatever was picked stays where it was put,
in either position.  A row that has never been given a family of its own shows
(and follows) the ANSI box font until one is picked.

*Toggle OFF All Mapping* is a master toggle: while any row is
on it switches every row off at once (each row keeps the family it had, so this
is a "follow the box font" action rather than a wipe), and with every row off
the same button switches them all back on, each with its own font.  Its caption
follows the rows - it reads *Toggle ON All Mapping* whenever a press would
switch the list back on - so the action always says which way it goes next.

The sheet opens at the size its content asks for (a little over 480 x 400 for
the four mappings Avro Keyboard ships) instead of a fixed, mostly empty box, and
it can never be resized smaller than that: the minimum is the page the rows ask
for, so a corner drag can only give the sheet more room - which collects under
the footer.  The row list hugs the rows it holds and only scrolls once a folder
offers more mappings than fit in the band.

The theme is deliberately **not** in this dialog: System / Light / Dark are
one-click entries in the gear menu itself, where their check marks already
show the current mode.

*OK* hands the settings over and closes the sheet, *Apply* hands them over and
keeps it open so the window changes while you work, *Cancel* discards
everything that was not applied, and *Reset to Defaults* stages the built-in
first-run fonts (still needing an Apply).  The reset hands every mapping the
same default ANSI family as its own font, switched on: the mapping rows then
hold what the reset gave them, so editing the ANSI box font afterwards leaves
Ansi V1...Vn alone (a row that has no family of its own is the one that follows
the box font, and the reset never leaves the list in that state).  A mapping is
handed back to the box font deliberately - switch its row off, or use *Use the
ANSI box font for every mapping* to do it for the whole list.

The values live in the portable INI as `UnicodeFont` + `UnicodeFontSize`,
`ConverterAnsiFont` + `AnsiFontSize`, `ThemeMode` (written from the gear menu),
one entry per remembered family under the `[MappingFonts]` group, and one
`false` entry per switched-off mapping under `[MappingSwitches]` (the mapping
name is the key in both).  A mapping that is *not* listed in
`[MappingSwitches]` is switched on, so settings files written before that group
existed keep their exact meaning.

### Dev / test hooks

- `--screenshot out.png [--wait ms]` - render the window in front into a PNG
  and exit (visual verification; `--wait` delays the grab, so a test can change
  files on disk while the window is live).  Sub-windows count: with
  `AVRO_OPEN_SETTINGS` set, the Settings dialog or the gear menu is captured.
- `AVRO_OPEN_SETTINGS=1` (or `=menu` for the gear menu) - open the Settings
  sheet or the gear menu shortly after the window appears, so either can be
  screenshotted without clicking.  `=mapping` was the sheet's old per-page form
  and still opens it.
- `AVRO_MAPPING_DIR=<dir>` - read the ANSI mappings from `<dir>` instead of
  the installed Avro Keyboard.
- `AVRO_AUTOTEST_IN/OUT=path` (+ `AVRO_AUTOTEST_REV=1` to run the reverse
  direction, `AVRO_AUTOTEST_SHOT=path` to also grab a screenshot) - load a
  UTF-8 file, run one conversion through the real UI/worker path, write the
  result and exit.  Used to verify the GUI end-to-end:
  `cmp gui_out.txt cli_out.txt` gives byte-identical results (the one known
  exception: a mapping can produce U+00A0, which the editors hold as an
  ordinary space - a Qt text-document detail on the memo side, not a
  difference in the conversion itself).
  `AVRO_AUTOTEST_DELAY=ms` postpones that conversion, which is how the live
  mapping refresh is tested: point `AVRO_MAPPING_DIR` at a copy of the
  mappings, swap the file mid-run, and the output is compared against a
  baseline conversion using the swapped-in mapping.
- `AVRO_MAPPING_LOAD_DELAY_MS=ms` makes every mapping load artificially slow,
  so the background load path is testable on a fast local folder: the window
  stays live, and a conversion requested in the meantime waits for the mapping
  it is about to use instead of running against the previous one.

## Testing the converter core without Qt

A standalone console tool verifies the conversion engine immediately - no Qt
and no RAD Studio needed.  `tools\build_cli.bat` builds it with the MinGW g++
that ships with the Qt installation (zlib for the container's deflate stream
and Windows CNG for its crypto are what the reader needs; the Embarcadero C++
toolchain ships no zlib headers or import library):

```bat
cd tools
build_cli.bat
```

Then convert any UTF-8 text file:

```
AvroConvertCLI.exe u2a "Ansi V3" input.txt output.txt    (Unicode -> ANSI)
AvroConvertCLI.exe a2u "Ansi V3" input.txt output.txt    (ANSI -> Unicode)
```

Mappings: `Ansi V3`, `SutonnyMJ`, `BanglaPedia v1.3`
(loaded from `C:\ProgramData\Avro Keyboard\AnsiMapping`).

## Fonts

Rendering the converted text needs the Bengali fonts used by the original
app: **Bornomala** (Unicode input) and **Kalpurush ANSI** (ANSI output).
Both are the defaults the app picks at first start; *Settings* lets any
installed font be used instead, per box and per ANSI mapping.
The Qt GUI loads the bundled copies from `assets/fonts` automatically and
falls back to `Vrinda` / `Nirmala UI` etc. when they are absent, so text
stays readable everywhere.

## Notes / differences from the Delphi app

- The Qt GUI is a faithful functional port of the layout rather than a
  pixel-identical clone, and it is deliberately *nicer*: rounded memo
  cards, accent styling, smooth scrolling, zoom, live counters and a
  flicker-free dark mode.
- Conversion runs on a background thread with throttled progress, so
  multi-megabyte documents do not freeze the window.
- RTF / Word-table preservation is not ported in v1; paste is plain text.
- Registry persistence uses the same keys as the Delphi app
  (`HKCU\Software\OmicronLab\Avro Keyboard`).
