# VCL Styles Utils (vendored)

Upstream: <https://github.com/RRUZ/vcl-styles-utils> (Rodrigo Ruz V.)
Vendored commit: `bc159dda844e96a9a168f03370a5997c80de5467` (2026-08-03, upstream `main`)
License: Mozilla Public License 1.1, as stated in each unit header.

## What is here

`Common/*.pas` and `Common/VCL.Styles.Utils.inc` - the library units, verbatim.

## What is deliberately not here

| Upstream path | Why it is left out |
| --- | --- |
| `Common/fontawesome.ttf`, `Common/*.RES`, `Common/*.RC`, `Common/CompileResources*.bat` | Resources for `Vcl.Styles.FontAwesome.pas`, which this project does not use. Add the font resource files together with that unit if it is ever needed. |
| `Common/delphi-detours-library/` | Not part of the upstream repository either. `Vcl.Styles.Hooks.pas` (`uses DDetours`) needs the Delphi Detours library on the unit search path - see the note in `Avro_Keyboard.dpr`. |
| `Demos/`, `Packages/`, `Tools/`, `Docs/`, `images/` | Upstream sample projects, design-time package and tooling; nothing the build needs. |

## How the project consumes it

`Avro_Keyboard.dproj` adds `..\third_party\vcl-styles-utils\Common` to the unit
search path (Base configuration, so Win32 and Win64 both get it), and
`Avro_Keyboard.dpr` lists the units that are actually compiled into the program.
Today that is `Vcl.Styles.Utils` only; the opt-in extras are written out, but
commented, in the same `uses` clause.

## Updating

```bash
git clone --depth 1 https://github.com/RRUZ/vcl-styles-utils /tmp/vcl-styles-utils
cp /tmp/vcl-styles-utils/Common/*.pas /tmp/vcl-styles-utils/Common/*.inc \
   third_party/vcl-styles-utils/Common/
git -C /tmp/vcl-styles-utils log -1 --format=%H   # record the new commit here
```

Then rebuild both platforms and re-run the scroll smoke test described in the
fix unit (`Units/uScrollBoxStyleHookFix.pas`), because a newer drop can change
both the units that are compiled in and the hooks the fix relies on.
