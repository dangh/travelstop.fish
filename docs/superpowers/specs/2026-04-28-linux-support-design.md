# Linux support for travelstop.fish

## Goal

Make the plugin work on Linux while remaining functional on macOS. Achieve this without introducing OS-detection branches in the codebase — every changed call site uses a portable form that runs unmodified on both platforms.

## Inventory of macOS-specific usages

| File | Line(s) | Issue |
| --- | --- | --- |
| `conf.d/travelstop.fish` | 1–9 | `_ts_notify` uses `osascript`, `afplay`, `/System/Library/Sounds/*.aiff` |
| `functions/push.fish` | 201, 202, 215 | Calls `_ts_notify` |
| `functions/invoke.fish` | 66, 67 | `md5 -q` (BSD `md5`) |
| `functions/prune_functions_versions.fish` | 8, 10 | `tail -r` (BSD-only flag) |
| `functions/prune_layer_versions.fish` | 8 | `tail -r` |
| `functions/bump_version.fish` | 64 | `sed -i ''` (BSD in-place form) |
| `functions/rename_modules.fish` | 39, 45, 52, 87, 89 | `sed -i ''` |
| `functions/daily_report.fish` | 29, 30 | `date -v` arithmetic (BSD only) |
| `README.md` | 6, 110, 117 | Install instructions assume Homebrew |

## Approach

Replace each macOS-specific call with a portable equivalent inline. No helper functions, no OS detection, no `if (uname) = Darwin` branches.

### `_ts_notify` removal → inline OSC 777

Remove `_ts_notify` from `conf.d/travelstop.fish` entirely. At each of the three call sites in `push.fish`, emit an OSC 777 desktop-notification escape sequence directly:

```fish
printf '\e]777;notify;%s;%s\a' "$title" "$message"
```

The `sound` argument that callers used to pass (`tink`, `basso`) is dropped — sounds are not used on Linux and we don't want OS-branched sound logic.

OSC 777 is rendered by the user's terminal emulator (foot, kitty, urxvt, wezterm, alacritty with config, etc.) on Linux. macOS users running iTerm2 / Terminal.app will not see desktop notifications from this — that is a deliberate trade-off the user has accepted.

### `md5 -q` → `md5sum`

`md5sum` ships in coreutils on Linux and is also available on macOS. Replace inline:

```fish
md5sum $function_js | string split -f1 ' '
```

### `tail -r` → portable `awk` reverse

GNU `tail` does not have `-r`. Replace each `command tail -r` in the pipelines with:

```fish
awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}'
```

Same logic, no platform dependency.

### `sed -i ''` → `sed -i.ts_bak` + cleanup

Both BSD and GNU `sed` accept `-i.SUFFIX` to do an in-place edit while leaving a backup at `<file>.SUFFIX`. We use a project-specific suffix (`.ts_bak`) to avoid colliding with any pre-existing `.bak` files.

Pattern, applied at each call site:

```fish
sed -i.ts_bak -E '...' $files
and command rm $files.ts_bak
```

Fish's element-wise expansion (`$files.ts_bak` → `a.ts_bak b.ts_bak c.ts_bak`) handles both single-file and list cases without a loop.

### `date -v...` → `node` one-liner

`functions/daily_report.fish` already shells out to `node -e` on line 76 to parse JS source, so node is already a hard dependency in this file. Use it for the date arithmetic too:

```fish
node -e 'const e=new Date();e.setHours(12,0,0,0);console.log(e.getTime()-86400000+" "+e.getTime())' \
    | read -d ' ' start_time end_time
```

This produces milliseconds directly, so the trailing `000` literal that the URL builder used to append is dropped.

### README updates

- Add a Linux install note alongside the `brew install jq` instruction (e.g., reference `apt install jq` / `pacman -S jq` / distro equivalent).
- Flag the cowsay example block (currently referencing `/opt/homebrew/share/cows/*.cow`) as macOS-specific, or replace its path with one that works on Linux too.

## Non-goals

- No support for Windows / WSL beyond whatever falls out of the Linux work.
- No new abstractions, helpers, or compatibility layers.
- No changes to behavior beyond what's required to make the listed call sites portable.
- No sound on either platform after this change.

## Verification

For each changed call site, exercise the function on Linux. Where possible, verify on macOS too (or at least confirm the new form is valid BSD syntax) — the portable forms above are chosen so this should hold without further testing, but it should be confirmed before declaring done:

- `bump_version` — run on a test repo, confirm CHANGELOG.md edit succeeds and no `.ts_bak` is left behind.
- `rename_modules` — dry-run on a test branch, same checks.
- `prune_functions_versions` / `prune_layer_versions` — confirm the awk reversal produces the same line ordering as `tail -r` on a sample input.
- `invoke` (file-change detection via md5) — confirm cache invalidation triggers correctly on file edit.
- `push` — trigger a deploy, confirm the terminal emits an OSC 777 sequence (visible in the terminal log if rendering is unsupported).
- `daily_report` — confirm the URL contains plausible millisecond timestamps for yesterday-noon and today-noon in the user's local timezone.
