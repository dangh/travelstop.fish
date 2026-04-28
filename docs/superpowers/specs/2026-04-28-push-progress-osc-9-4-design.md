# OSC 9;4 progress reporting for `push`

## Goal

While `push` is deploying targets, emit OSC 9;4 escape sequences so terminals that support taskbar/title-bar progress (iTerm2, WezTerm, ConEmu, Windows Terminal, Ghostty, Foot, etc.) display a live progress indicator. The visual feedback complements the existing `_ts_progress` text output and the OSC 777 desktop notification.

## OSC 9;4 reference

```
\e]9;4;<state>;<percent>\a
```

| State | Meaning |
| --- | --- |
| 0 | Clear / off |
| 1 | Normal progress (uses `<percent>`) |
| 2 | Error (red, uses `<percent>`) |
| 3 | Indeterminate (`<percent>` ignored, but include `;0` for terminals that require it) |
| 4 | Paused / warning (uses `<percent>`) |

## Design

All emissions are inline `printf` calls in `functions/push.fish`. No helper function (matches the OSC 777 inlining pattern).

### Multi-target case (`count $targets` > 1)

| Moment | Sequence |
| --- | --- |
| Before the deploy loop | `\e]9;4;1;0\a` |
| After each target succeeds | `\e]9;4;1;<pct>\a` where `pct = i * 100 / count` |
| After a target fails | `\e]9;4;2;<pct>\a` |
| After the loop (success or failure) | `\e]9;4;0\a` |

Failure aborts the loop (`break`), so state 2 is visible for the duration of the summary block (notification + pushover) before being cleared.

### Single-target case (`count $targets` == 1)

| Moment | Sequence |
| --- | --- |
| Before the deploy loop | `\e]9;4;3;0\a` |
| After the target fails | `\e]9;4;2;0\a` |
| After the loop | `\e]9;4;0\a` |

Single-target success has no intermediate update — the indicator stays indeterminate, then clears.

### Zero targets

No progress emission. Pre-loop conditional (`if test $count -gt 1 / else if test $count -eq 1`) covers this implicitly.

### Early function returns

The function can return early at the prod-confirmation prompt (line 41–49) before any progress sequence is emitted, so no clear is needed there.

## Insertion points in `functions/push.fish`

- **Before the deploy loop**: after `set -l failure_count 0` (line 101), before `for i in (seq (count $targets))` (line 104). One `if/else` block selects state 1 or state 3 based on count.
- **Inside the loop, after success/failure determination**: just after the existing per-target progress update (lines 184–186, where `targets[$i]` is rewritten to `success:...` or `failure:...`). Add a count-gated progress emission with state 1 or 2.
- **After the loop**: at the very end of the summary block (after line 218 `_ts_pushover ...`), unconditionally emit `\e]9;4;0\a` if any progress had been emitted (gate on `count $targets >= 1`).

## Non-goals

- No intra-`sls deploy` progress (deploy is opaque from the shell's perspective).
- No new helper function.
- No OS-conditional logic — OSC 9;4 is terminal-side and silently ignored by terminals that don't support it.
- No change to `_ts_progress` text output, which remains the primary in-shell progress display.

## Verification

- Multi-target push: deploy two known-good targets, observe the progress bar advancing 0 → 50 → 100 → cleared.
- Multi-target push with a failing target: deploy a stack with a forced failure mid-list, observe the bar transition to red on the failing iteration, then clear after summary.
- Single-target push: deploy one target, observe indeterminate animation in supported terminals; deploy one failing target, observe red briefly before clear.
- Zero/early-exit: run `push` and answer `n` to the prod prompt, confirm no stale progress remains in the terminal.
