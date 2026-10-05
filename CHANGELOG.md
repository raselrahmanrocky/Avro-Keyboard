# Changelog

All notable user-visible changes to Avro Keyboard. Entries describe what a user
would notice, not the implementation.

## Unreleased

### Fixed

- **The Customize window smeared while scrolling in Dark Theme.** Spinning the
  mouse wheel fast, or dragging the scrollbar, could leave ghost trails of text
  behind the rows while the “Windows10 Dark” style was active. Every scroll step
  now repaints its surface opaquely before the next one is drawn; the light
  style looks exactly as before.

### Changed

- **The 64-bit installer now installs to `C:\Program Files\Avro Keyboard`**
  instead of `C:\Program Files (x86)\Avro Keyboard`, as Windows expects for a
  64-bit application. The 32-bit installer keeps
  `C:\Program Files (x86)\Avro Keyboard` (or `C:\Program Files` on 32-bit
  Windows). Each edition is its own application identity with its own uninstall
  entry, so both can be installed side by side without touching each other, and
  the 64-bit installer no longer starts on 32-bit Windows, where its files could
  never run.

## 6.0.1-beta - 28 September 2026

### Fixed

- **Avro could refuse to start, invisibly.** A bad setting, a locked-down
  registry, a missing font or a failed mapping load could raise before any window
  existed: Task Manager showed `Avro Keyboard`, but there was no top bar, no tray
  icon and no working keyboard hook, and nothing said why. Each of those steps is
  contained now, and a failure is reported with a dialog and written to a log.
- **A corrupt `Database.db3` disabled the word database for the whole session**
  and aborted the rest of startup (no tray icon, no hook). The database failure is
  reported once, and the remaining startup steps run.
- **Installing a keyboard layout or a skin gave an "Application Error" immediately
  after "installed successfully".** The installer finished the copy, reported it,
  and then crashed while releasing its XML document.
- **"Avro Keyboard is already running" appeared on a normal first start.** The
  single-instance check read the last-error code instead of specifically asking
  whether the mutex already existed.
- **A non-numeric setting could stop startup entirely.** `TopBarPosX` (and the
  other numbered settings) are parsed leniently now, and empty or invalid values
  are replaced with their documented defaults instead of crashing startup.
- **Typography/engine startup could hang on a missing font resource**: the font
  installer opened the temporary file it had just failed to create.
- **The ANSI mapping cache could end up written next to random working
  directories** in profiles without `%APPDATA%`, so it was never reused. It now
  falls back through `%LOCALAPPDATA%`, `%TEMP%` and the Avro data folder.
- **A failed settings refresh from the keyboard hook could silently kill the
  keyboard hook.** A modal dialog (or a slow reload) inside the low-level keyboard
  callback makes Windows drop the hook after `LowLevelHooksTimeout`; the refresh
  now defers itself to the main loop when it is entered from the hook.
- **The installed Avro Text Converter never remembered its settings.** Switching
  the theme (or a font, or the ANSI version) and restarting always came back to
  the same values: the settings location was picked with a writability check
  that ignores Windows permissions and called `Program Files` writable, so every
  save failed silently. The converter now probes for real, keeps its settings in
  `%LOCALAPPDATA%\OmicronLab\Avro Text Converter\` when the folder beside the
  exe is not writable (carrying an existing INI over once so an upgrade keeps
  it), and reports a failed write instead of swallowing it. The installer also
  stopped shipping the developer's local `AvroTextConverter.ini`.

### Added

- **`AvroStartup.log`** - a startup log beside the data files (rotated at 256 KB,
  falling back to `%LOCALAPPDATA%\AvroKeyboard\` and then `%TEMP%\AvroKeyboard\`
  when the data folder is not writable). It records the startup phases, the
  edition, the exe and data paths, folder writability, the database file, the OS
  build and startup-step exceptions. It never records what you type. See
  `docs/TROUBLESHOOTING.md`.
- **`tools/verify/`** - startup regression harnesses (portable, installed,
  installer path, missing `%APPDATA%`, unwritable data folder) that break one
  input at a time and check that Avro still starts visibly.
