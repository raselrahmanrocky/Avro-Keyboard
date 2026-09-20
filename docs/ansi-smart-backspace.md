# Smart ANSI backspace (one press, one Bengali glyph)

Applies to: Avro Keyboard's **ANSI output mode** (`OutputIsBijoy = YES`), where the
keyboard prints one of the ANSI (Bijoy-font-range) mappings. In Unicode mode this
feature never wakes up — see *Unicode mode is untouched* below.

---

## 1. The problem, and what this does

In ANSI output a visible Bengali character is usually **several ANSI units**: `ই` is
two, `উ` is two, a conjunct such as `ক্ক` is three, and the widest characters the
shipped mappings draw are four. Before this feature, one Backspace deleted one
*byte-character*, so a user had to press it two to four times for one letter.

Now one press deletes one **visible character**:

* For text the keyboard itself typed, nothing had to change: each engine already
  keeps a ledger of the text it committed (`CommittedBanglaT`), and the screen
  behind the caret is exactly `Convert(CommittedBanglaT)`. The ledger is exact, so
  the engines answer from it first.
* For text the ledger does **not** describe — text the user pasted, text typed in
  another mapping, text that was already in the document when they clicked into it
  — the width comes from a *reading* of what is in front of the caret plus the
  active mapping's own compiled glyph table (`uAnsiBackspace.AnsiHostClusterUnits`,
  using `clsAnsiAtomMap.TAnsiAtomMap` and `AnsiTailClusterUnits`).

Everything below is about the second case.

If the width cannot be established, the press falls back to exactly the behaviour
that shipped before this feature: the application deletes one ANSI unit. There is
no guessing and no over-delete — see the decision table in section 5.

---

## 2. The reading layers, and what each one costs

`uCaretWatch.TCaretReader.ReadContext` tries them in order and stops at the first
that answers.

| | Layer | How it reads | Side effects | Hosts |
|---|---|---|---|---|
| **A** | Message path — `uCaretContextSniffer.SniffTextBeforeCaret` | `EM_GETSEL` + `WM_GETTEXT` via `SendTimed` (100 ms timeout) | **none** | standard `EDIT` and `RICHEDIT*` |
| **B** | UI Automation — `uUIAText.TUiaTextReader` | `ElementFromHandle` → `TextPattern2` → `Clone` → move both endpoints back → `GetText` | **none** (no synthetic keys, no clipboard, no focus change) | Word, Excel, Chrome/Edge, VS Code, LibreOffice, and anything else with a text pattern |
| **C** | Clipboard round-trip — `uCaretContextSniffer.SniffTextViaClipboard` | `Shift+Left ×N`, `Ctrl+C`, read, `Right`, put the old clipboard back | **injects keys into the foreground window and rewrites the clipboard — default NO, experimental** | the hosts A and B cannot reach |

Layer B is only used while `AnsiBackspaceUIA = YES`, layer C only while
`AnsiBackspaceClipboard = YES`, and **neither is installed while the master switch is
off** (`AnsiSmartBackspace = NO` / `AnsiBackspaceHostErase = NO`): a disabled
feature does not create the UIA client and never runs the clipboard round-trip
(`uCaretWatch.AnsiCaretWatchTick`, `TCaretReader.ReadContext`).

Layer C is written defensively because it is the only layer that touches things
outside this process:

* password fields (`ES_PASSWORD`) are refused before anything is pressed;
* an active selection is refused — it is the user's, and the round-trip would
  collapse it;
* it **refuses outright unless the clipboard holds text and nothing but text**
  (`ClipboardIsTextOnly`: only `CF_TEXT`, `CF_UNICODETEXT`, `CF_OEMTEXT`,
  `CF_LOCALE`). A screenshot or a copied file list cannot be put back by a
  text-only restore, and `TClipboard.AsText` answers `''` for a bitmap *without
  raising*, so without this check the loss would have been silent;
* every injected modifier is confirmed against the desktop (`GetAsyncKeyState`)
  before the key that depends on it is pressed, and the **control** is asked what
  it actually selected (`EM_GETSEL`) instead of trusting the injected keys — a
  machine whose input stack reshapes injected modifiers then gets "no reading"
  instead of a corrupted document;
* the previous clipboard text is restored with retries, and a restore that still
  fails is traced rather than swallowed;
* if a modifier cannot be released at all, the layer latches: that selection is
  named in the log, nothing further is pressed until the desktop reports a clean
  keyboard, and the latch clears itself the moment it does (a transient glitch
  must not disable the layer for the session).

### Why the reading is taken on a timer, never inside a hook

`uCaretWatch` installs three WinEvent hooks (`EVENT_OBJECT_LOCATIONCHANGE`,
`EVENT_OBJECT_FOCUS`, `EVENT_SYSTEM_FOREGROUND`, with
`WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS`) and a `WH_MOUSE_LL` hook. A
callback does exactly three things: `AnsiCaretContextDrop` (invalidate, O(1)),
`FPending := True`, `CallNextHookEx`. No window text, no UIA, no allocation, no
blocking call — a hook that blocks is a system-wide stall.

The work happens in `AnsiCaretWatchTick`, on the main thread, from the
application's window-check timer: it opens **one burst**
(`AnsiCaretBurstBegin`/`AnsiCaretBurstEnd`) and asks
`uCaretContextCache.AnsiCaretContextRefresh(32)` for a reading. The cache keeps at
most one reading per burst, and a reading carries a *fingerprint* (`TCaretFingerprint`:
the caret window, the caret X/Y) that is re-read at press time. A press is answered
only while the fingerprint still matches (`AnsiCaretContextVerify`); a caret move, a
focus change, a foreground change, a real mouse click or a key press all drop the
reading first, so a stale description can never justify an erase.

Word boundaries deliberately do **not** invalidate: `IsCaretMovingKey` and the
engine's own `InvalidateAnsiTail` / `TLayout.ResetDeadKey` / layout and mode
switches do (`clsLayout.InvalidateAnsiTail` → `AnsiBackspaceInvalidate`).

---

## 3. Settings

All eight keys are read from the registry in a normal install
(`HKCU\Software\OmicronLab\Avro Keyboard`, via `uRegistrySettings.LoadSettingsFromRegistry`)
and from `Settings.xml` in the Avro data directory in a portable build
(`LoadSettingsFromFile`; `%COMMONAPPDATA%\Avro Keyboard\Settings.xml`, or next to
the executable when built with `PortableOn`). Both writers are kept in step, so a
file copied between the two layouts carries every key.

| Key | Values | Default | What it does | Takes effect |
|---|---|---|---|---|
| `AnsiSmartBackspace` | `YES` / `NO` | `YES` | **Master switch.** `NO` means no reading is taken at all: no UIA client, no clipboard round-trip, `AnsiBackspaceEnabled = False`. An **empty value means YES** (a key that was never written). | next caret-watch start — i.e. immediately when saved from Options |
| `AnsiBackspaceHostErase` | `YES` / `NO` | `YES` | The key the master switch replaced: "the host may erase whole glyphs". Still read, so older builds, the options dialog and the harnesses keep working. `NO` behaves like the master switch being off. | next press (live) |
| `AnsiBackspaceLegacy` | `YES` / `NO` | `NO` | Erase **policy** for the engine's own ledger: `NO` follows UAX#29 (one cluster per press); `YES` keeps the pre-feature boundary. Example `র্ক`: with `NO` one press removes the whole thing; with `YES` the reph survives and the consonant stays, so it costs a second press. | next press (live) |
| `AnsiBackspaceUnitCap` | `1` … `64` | `8` | Safety bound: a reading wider than this is not believed and the press falls back. A single glyph is far narrower, so this only fires on a corrupt reading. | next press (live) |
| `AnsiBackspaceUIA` | `YES` / `NO` | `YES` | Enables layer B (UI Automation). `NO` keeps COM out of the process entirely. | caret-watch start |
| `AnsiBackspaceClipboard` | `YES` / `NO` | `NO` | Enables layer C (the clipboard round-trip). Experimental: it injects keys into the foreground window. | caret-watch start |
| `AnsiBackspaceApps` | see below | `''` | Per-application override: which applications keep the pre-feature behaviour. | next press (live) |
| `AnsiBackspaceLog` | `YES` / `NO` | `NO` | Debug trace to `OutputDebugString` (section 5). Off by default, and off the hot path. | caret-watch start |

Related keys that already existed: `EnableCaretSniffer` (default `Yes`) and
`FollowCaretByDefault`.

**Migration.** `AnsiSmartBackspace` is read as *"the new key, else the value of
`AnsiBackspaceHostErase`"* — so an installation that had the feature switched off
stays off, and a fresh one gets `YES`. Both storage paths do this
(`uRegistrySettings.LoadSettingsFromFile` / `LoadSettingsFromRegistry`).

**A test or an old build that only ever sets `AnsiBackspaceHostErase`** keeps
working: an unset `AnsiSmartBackspace` counts as on
(`uAnsiBackspace.AnsiBackspaceEnabled` → its local `SettingOn`).

### `AnsiBackspaceApps` grammar

A `;`-separated list of `class=value` pairs (a `:` also works as the separator):

* a token **without** `=` or `:` is ignored — a bare class name does nothing;
* the class is matched **case-insensitively** and as a **substring**, against both
  the focused control's class and the foreground window's class;
* the **last** matching entry wins;
* a class that is not listed stays **ON** (an empty setting means ON);
* the value is ON only for `''`, `on`, `yes`, `1`, `all`, `default`, `cluster`.
  **Anything else counts as OFF**, so a typo can never make the eraser more
  aggressive than the setting says.

Examples

```
Chrome_RenderWidgetHostHWND=off;Chrome_WidgetWin_1=off   # leave Chromium alone
wordpad=off;winword=on                                    # but keep Word
```

`off` means "that application keeps the behaviour it had before this feature: one
ANSI unit per press". Implemented by `AnsiAppAllowsHostErase`, `ClassMatches` and
`ValueAllows` in `Keyboard and Spell checker/Units/uAnsiBackspace.pas`.

---

## 4. The user interface

**Options → Global Output → "ANSI backspace (smart erase)"** (built in code by
`TfrmOptions.BuildAnsiContextOptions` in `Forms/ufrmOptions.pas`; the group appears
at the bottom of the Global Output page).

| Control | Effect |
|---|---|
| Enable smart ANSI backspace | `AnsiSmartBackspace` — the master switch |
| Erase whole glyphs in the application | `AnsiBackspaceHostErase`; off means one ANSI unit per press, exactly as before this feature |
| Read the text in front of the caret with UI Automation | `AnsiBackspaceUIA` |
| Clipboard round-trip as a last resort | `AnsiBackspaceClipboard` (experimental) |
| Use the older erase rule | `AnsiBackspaceLegacy` — the compatibility policy of section 3 |
| Log the caret decisions for troubleshooting | `AnsiBackspaceLog` |
| Never erase more than (ANSI units, 1-64) | `AnsiBackspaceUnitCap`; digits only, and a value outside 1…64 is corrected **in the field, on Save**, not silently at the next launch |
| Per-application override | `AnsiBackspaceApps`; the grammar of section 3 is printed under the field |

**Saving restarts the caret watch** (`ApplyAnsiContextSettings` →
`AnsiCaretWatchStop` + `AnsiCaretWatchStart`; called from Apply and OK): `UIA`,
`Clipboard` and `Log` are read when the watch starts, so the change applies without
a relaunch. The per-application list and the erase policy are read per press and
were already live.

---

## 5. Troubleshooting

1. Options → Global Output → tick **Log the caret decisions for troubleshooting**
   (`AnsiBackspaceLog = YES`), then apply.
2. Run [Sysinternals DebugView](https://learn.microsoft.com/sysinternals/downloads/debugview)
   and filter for `[AvroCaret]`. Every line comes from
   `uCaretContextCache.AnsiTrace` (`OutputDebugString`).
3. Reproduce the press. You will see which layer answered, why a refusal happened,
   and — for the clipboard layer — exactly which step failed.

Decision names come from `uAnsiBackspace.AnsiDecisionName`:

| Decision | Meaning | What to check first |
|---|---|---|
| `not ours` (`edNotMine`) | No reading, or the feature is off: the application handles the press itself | the master switch; `AnsiCaretWatchActive`; is the target a password field? |
| `one unit` (`edOneUnit`) | The reading is one unit wide — the host deletes it, exactly as before | nothing; this is the correct answer for a Latin letter |
| `cluster` (`edCluster`) | A multi-unit cluster was erased through the engine's own atomic emission | nothing |
| `above the cap` (`edCapped`) | The reading claimed more units than `AnsiBackspaceUnitCap` | raise the cap only if the glyph really is that wide; otherwise the reading is corrupt |
| `stale reading` (`edStale`) | The caret moved between the reading and the press | nothing — the next press reads again; a *constant* `edStale` means the host raises no caret events |
| `unknown glyph` (`edUnknown`) | The active mapping has no compiled glyph table | the mapping failed to load; try another ANSI version |
| `this application is excluded` (`edAppBlocked`) | `AnsiBackspaceApps` matches this application | section 3 |

The reader's own diagnosis lives in `uUIAText.TUiaTextReader.GetElementInfo`
(`class / hwnd / controlType / textPatternAvailable / kind / range trace`), and the
host harness prints the same line — see section 7.

---

## 6. Known limits

* **The clipboard layer is off by default, and should stay off** unless a specific
  host needs it. It injects keys into whatever is in the foreground and it rewrites
  the user's clipboard (text-only, restored, but still). It refuses whenever the
  clipboard holds anything but text.
* **Hosts with no UI Automation text pattern** (or with `GetText` empty) fall back
  to the pre-feature behaviour: one ANSI unit per press.
* **Some desktops reshape injected modifiers**: an injected Shift-down can be
  answered by a Shift-up nobody sent, so `Shift+Left` arrives unshifted. The layer
  detects this (it asks the control, not itself), presses nothing further and
  reports it; the keyboard-driven part of layer C then simply does not work there.
  Measured on a normal Windows 11 desktop with a third-party input stack; the
  message path and UIA are unaffected.
* **The unit cap (1…64, default 8) is a safety bound, not a policy.** It exists so
  that a corrupt reading cannot delete a word.
* **A mouse click is observed as an event, not as a caret position.** The
  `WH_MOUSE_LL` hook only drops the cached reading; the new caret is read on the
  next tick.
* **The master switch stops the reading, not the hooks.** The WinEvent and mouse
  hooks stay installed while the feature is off (they are two OS callbacks that set
  a flag); what stops is every read, including the clipboard round-trip.
* **The erase-decision trace hook** (`uAnsiBackspace.AnsiBackspaceSetTrace`, the
  one the harnesses use to read units/decision/reason) is **not wired in the shipped
  application yet**; the shipped log is the caret-context one described in
  section 5.
* `OBJID_CLIENT` location-change events are chatty: a control that repaints can
  produce many of them. They only invalidate a cached reading, and a reading costs
  one burst per tick.
* **Unicode mode is untouched.** The engines gate the whole path on
  `OutputIsBijoy = 'YES'`, and `kat_grapheme` asserts that a Unicode/English press
  emits the host's own stream, leaves the ledger alone and never touches the cache.

---

## 7. Building and running the harnesses

Both are plain `dcc32` console projects in `AvroEncoEngine/tools/AvroShieldSelfTest/`
and need no GUI. Build them from that folder with the unit search path of the
application, for example:

```bat
set DCC="C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\dcc32.exe"
set U=<repo>\Keyboard and Spell checker\Units;<repo>\Keyboard and Spell checker\Classes;<repo>\Keyboard and Spell checker\Forms;<repo>\Keyboard and Spell checker\SpellChecker;<repo>\Unicode to ascii converter
%DCC% -B -U"%U%" kat_grapheme.dpr
%DCC% -B -U"%U%" kat_host.dpr
```

### `kat_grapheme` — the head-less gate

```bat
kat_grapheme "<repo>\assets"
```

Drives every mapping in `assets` (Default + Ansi V1…V4) through the real engine
path with the host replaced by `OnRawEmit`, and checks the surviving ledger, the
width and the emitted diff after every press. **Baseline: 5968 checks, 0 failures**
(rows: width, mapping/atom/state, host text, delimiters, repeated presses, caret
moves, pending host characters, atom table, host-text eraser, English mode,
Unicode output mode). Bengali literals are written as `#$XXXX`, so the file stays
ASCII.

### `kg_golden` and `kg_old` — the Unicode-mode golden

Row 15 asserts the Unicode-mode stream against a table of literals
(`UNI_GOLDEN`). `kg_golden` prints that stream for the whole corpus, so a
*deliberate* change to an engine's Unicode path is re-recorded on purpose rather
than by editing the table from memory. `kg_old` is the same measurement written
to compile against **any** revision: build it in a worktree of the pre-feature
tree (`git worktree add /tmp/base34 34deb37`) and in this one, and diff the two
outputs — on the machine this was written on they were identical.

### `kat_host` — the real controls

```bat
kat_host
```

Starts a second copy of itself with `--serve`; that copy owns real windows (a
standard `Edit`, a multi-line `Edit`, a `RICHEDIT50W` and a password `Edit`) in
**another process** — which is what makes UIA and the WinEvent hooks behave the way
the product sees them — and answers focus requests. The parent then exercises the
message path, a real COM UIA client, the clipboard refusals and the quarantine
(the desktop's Shift state is declared through
`AnsiClipboardConfigureForTest`), and finally a real `WH_KEYBOARD_LL` hook driven
by a real `SendInput` press.

* Evidence: `%TEMP%\kat_host.child.log` — every key the target control received,
  with its modifier state, plus the parent's marks and who held the foreground.
* A **SKIP** is not a failure. Two things cause it, and both are named on screen:
  the desktop did not hand the foreground to the harness window (exit code 2), or
  the desktop does not deliver injected keys (section 6), in which case the
  keyboard-driven clipboard cases cannot judge the layer and are skipped — with the
  failing step printed.
* **Baseline: 64 checks, 0 failures, 1 skip** on a desktop that reshapes injected
  modifiers (the skipped case is the keyboard-driven clipboard round-trip; its
  safety and refusal cases run everywhere).

Sibling KATs worth running after a change here: `kat_ansiconvert`,
`kat_engineswitch`, `kat_enginecache`, `kat_karcall`.

### What a contributor must not weaken

* no window text, UIA, clipboard or cross-process message inside a hook callback;
* one emission path per engine (`RawSend` / `EmitBatch` / `SendAnsiDiff`), always an
  atomic erase + type batch;
* never over-delete: an unknown glyph, a failed read, a timeout, a disabled feature
  or a value above the cap means one unit;
* password fields are never read, an active selection is never destroyed, the
  clipboard is always restored (or the failure is traced);
* new settings follow the "empty string means the documented default" rule, so an
  installation or a test that never writes the key keeps working.
