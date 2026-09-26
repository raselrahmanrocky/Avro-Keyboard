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

### Building Projects

Delphi community edition doesn't come with command line compiler. In order to build projects:

- Run `build-ce.bat`
- Open `WholeProject.groupproj` in Delphi IDE and run `Build All` from the project group
- Built and renamed files will be under `build` directory

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
