# Avro Keyboard

Unicode compliant open source Bangla typing software (IME).
Visit: [https://www.omicronlab.com](https://www.omicronlab.com "OmicronLab") for latest version.

## Required Delphi Version

Was tested with **Delphi 12 community edition**

The community edition can be download from here:
https://www.embarcadero.com/products/delphi/starter/free-download

## Development/Contributing

- Please use project specific code formatting profile

  - Go to `Tools > Options > Language > Formatter` in Delphi IDE
  - Load `Formatter_Profile.config` from the root of this project
  - Please make sure to format the sources using this profile before creating a PR

- Debug logs can be viewed using [DebugView](https://learn.microsoft.com/en-us/sysinternals/downloads/debugview) when `{$Define DebugLog}` compiler directive is set in the `ProjectDefines.inc` file from the root of this project.

  `Log()` writes to the debugger only and never to a file: it is called from the
  keyboard hook, and a hook callback must not touch the disk. Startup diagnostics
  go to a separate log file instead - see [Startup log](#startup-log) below and
  `docs/TROUBLESHOOTING.md`.

## Building Standard and Portable editions

### Compiler Directives

Open `ProjectDefines.inc` file in the root folder of the source.

For building portable edition, add the following line in this file and compile:

    {$Define PortableOn}

For building standard edition, remove the above line from the
file or make it a comment like the following and then compile:

    {.$Define PortableOn}

or,

    //{$Define PortableOn}

The file is checked in with the portable switch **commented out**, and it stays
that way: the standard (installed) edition is the source default. Portables are
built only by `tools/release/build-installers.ps1`, which forces the switch on
for its portable passes and restores `ProjectDefines.inc` byte-for-byte
before it finishes - so a release does not leave the working tree switched to
portable.

### Building Projects

Delphi community edition doesn't come with command line compiler. In order to build projects:

- Run `build-ce.bat`
- Open `WholeProject.groupproj` in Delphi IDE and run `Build All` from the project group
- Built and renamed files will be under `build` directory

### The root secret and default-key containers

`Keyboard and Spell checker/Units/Private/uAvroShieldSecret.pas` is checked in
as a **public stub** with no key material, so a clone builds and runs offline with
no token and no key file. In that state the keyboard cannot open a **default-key**
`.AvroEnco` container: it reports that the secret is unavailable instead of
failing with a confusing decode error, and the release guard refuses the build.

To build with the real unit, fetch it from the private extension repository:

    tools\secrets\fetch_secrets.ps1            # needs AVRO_SECRETS_TOKEN

Then put the stub back before you commit:

    tools\secrets\fetch_secrets.ps1 -Clean

Setup, rotation and the leak gate are documented in `SECRETS_SETUP.md`, and the
rotation procedure itself in `docs\ROTATION_RUNBOOK.md`. Do not add key material
to the stub: `tools\secrets\check-no-secret-bytes.ps1` fails the
build if it appears.

## Where Avro keeps its data

| Edition | Settings | Data (database, mappings, layouts, skins, logs) |
| --- | --- | --- |
| Standard (installed) | `HKEY_CURRENT_USER\Software\OmicronLab\Avro Keyboard` | `%ProgramData%\Avro Keyboard\` |
| Portable | `Settings.xml` next to `Avro Keyboard.exe` | the folder that holds `Avro Keyboard.exe` |

Both editions touch the registry, so "no registry changes" is not an accurate
description of the portable edition. What it writes:

- `HKCU\Control Panel\Desktop\LowLevelHooksTimeout` (5000 ms) - keeps Windows
  from silently dropping the keyboard hook when another application blocks for a
  while
- the IE per-script font values under
  `HKCU\Software\Microsoft\Internet Explorer\International\Scripts\11`
  (`IEFixedFontName`, `IEPropFontName`, with the previous values preserved in the
  `_Prev` values) while the portable Siyam Rupali font is registered
- `AvroStartup.log` beside its data files (see below)

Nothing is installed or registered system-wide, and the portable folder can be
moved or deleted freely; the three registry entries above are the only trace that
is left, and the font ones are restored when the font is removed.

### Startup log

`AvroStartup.log` is written beside the data files, rotating to
`AvroStartup.log.old` once it passes 256 KB, and records the startup phases, the
edition, the exe and data paths, folder writability, the database file size and
mtime, the OS build, and the class and message of any exception raised by a
startup step. When the data folder cannot be written to it falls back to
`%LOCALAPPDATA%\AvroKeyboard\` and then `%TEMP%\AvroKeyboard\`, and with nothing
writable it skips silently - startup never depends on the log. It never contains
keystrokes or typed text; the runtime catch-all records only an exception class.
`docs/TROUBLESHOOTING.md` explains how to read and send it.

## Avro Text Converter (Qt)

The Bengali text converter also ships as a Qt application under `Converter/` -
a C++ port of the Delphi converter, which now lives in
`legacy-delphi-converter/` (deprecated: kept as a reference and no longer built
or packaged).

- **Requirements**: Qt 6.11.1 `mingw_64` with the MinGW, CMake and Ninja from
  the same Qt installation (`C:\Qt\Tools\...`) - nothing else.
- **Build**: run `Converter\MakeDist.bat` (double-clickable).  It finds the Qt
  kit and the shared `assets\` folder and leaves a runnable deployment in
  `Converter\dist\`.
- **Command line**: `AvroTextConverter.exe [--mapping-dir <dir>]`.  The switch
  is what the portable packaging uses to point the converter at the
  `AnsiMapping\` folder beside the keyboard executable; a second launch only
  restores the window of the running copy.
- See `Converter/README.md` for the feature list, settings and dev hooks.

## Notable contributions

- [@JayedAhsan](https://github.com/JayedAhsan) (PR [#32](https://github.com/mugli/Avro-Keyboard/pull/32)) - 3rd party dependencies are no longer necessary to compile the source, can be compiled with the latest free Community Edition of Delphi, and perf improvements.

## License

Avro Keyboard is licensed under **MOZILLA PUBLIC LICENSE Version 2.0**. You should receive a copy of the license in LICENSE.txt file with both binaries and source. An online version of the license can be found at: [https://www.mozilla.org/en-US/MPL/2.0/](https://www.mozilla.org/en-US/MPL/2.0/ "https://www.mozilla.org/en-US/MPL/2.0/")

### License notes

- Avro Keyboard's own code - the Delphi projects and the Qt converter under
  `Converter/` - is **MPL-2.0**.
- The Qt converter links Qt **dynamically**: its Qt runtime DLLs
  (`Qt6Core.dll`, `Qt6Gui.dll`, `Qt6Widgets.dll` and the plugins) ship as
  separate files in the `converter\` folder of a release, so they can be
  replaced with a compatible Qt build.  Qt is used under the **LGPLv3**; the
  license texts and obligations are described at
  [https://www.qt.io/licensing/open-source-lgpl-obligations](https://www.qt.io/licensing/open-source-lgpl-obligations).
