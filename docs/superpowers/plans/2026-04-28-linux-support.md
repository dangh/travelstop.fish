# Linux support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every macOS-specific shell call in the plugin with a portable form so it runs unmodified on Linux while continuing to work on macOS.

**Architecture:** No new helpers, no OS detection. Each call site is rewritten inline using a portable equivalent (POSIX/coreutils features available on both platforms, or — for the date arithmetic — a node one-liner since `daily_report.fish` already depends on node).

**Tech Stack:** fish shell, GNU coreutils on Linux (already available on macOS too: `md5sum`), node (already required by `daily_report.fish`), terminal-side OSC 777 for notifications.

**Spec:** [`docs/superpowers/specs/2026-04-28-linux-support-design.md`](../specs/2026-04-28-linux-support-design.md)

---

## File Structure

Files modified (no files created, no files renamed):

- `conf.d/travelstop.fish` — remove `_ts_notify` function (lines 1–9)
- `functions/push.fish` — replace 3 `_ts_notify` calls (lines 201, 202, 215) with inline OSC 777
- `functions/invoke.fish` — replace `md5 -q` with `md5sum | string split` (lines 66, 67)
- `functions/prune_functions_versions.fish` — replace `tail -r` with awk reverse (lines 8, 10)
- `functions/prune_layer_versions.fish` — replace `tail -r` with awk reverse (line 8)
- `functions/bump_version.fish` — replace `sed -i ''` with `sed -i.ts_bak` + cleanup (line 64)
- `functions/rename_modules.fish` — replace 5 `sed -i ''` calls with `sed -i.ts_bak` + cleanup (lines 39, 45, 52, 87, 89)
- `functions/daily_report.fish` — replace BSD `date -v` arithmetic with a node one-liner (lines 29–30)
- `README.md` — add Linux install note next to `brew install jq`; flag the `cowsay` example as macOS-specific

Each task touches one file (except Task 1 which touches `conf.d/travelstop.fish` and `functions/push.fish` together, since removing `_ts_notify` while leaving callers in place would break `push`).

A note on testing: the project has no automated test suite. Verification at each step uses `fish -n <file>` to syntax-check, plus a targeted manual exercise (e.g., piping known input through the changed pipeline and comparing output). Where the function depends on AWS / a project workspace and can't be exercised in isolation, the verification is limited to syntax-check plus reading the diff to confirm semantics are preserved.

---

## Task 1: Replace `_ts_notify` with inline OSC 777

**Why first:** removing the function while leaving callers would break `push`. Both files must change in the same commit.

**Files:**
- Modify: `conf.d/travelstop.fish:1-9` (delete the `_ts_notify` function)
- Modify: `functions/push.fish:200-202, 215` (replace 3 callers)

- [ ] **Step 1: Delete `_ts_notify` from `conf.d/travelstop.fish`**

Remove lines 1–9 entirely. The block to delete is:

```fish
function _ts_notify -a title message sound -d "send notification to system"
    osascript -e "display notification \"$message\" with title \"$title\"" &
    disown
    set sound "/System/Library/Sounds/$sound.aiff"
    if test -f "$sound"
        afplay $sound &
        disown
    end
end
```

Leave the blank line that separates the next function (`_ts_pushover`).

- [ ] **Step 2: Replace the three `_ts_notify` calls in `functions/push.fish`**

At line 200–202, replace:

```fish
        test $result -eq 0 \
            && _ts_notify "$sls_success_icon deployed" "$notif_message" tink \
            || _ts_notify "$sls_failure_icon failed to deploy" "$notif_message" basso
```

with:

```fish
        if test $result -eq 0
            printf '\e]777;notify;%s;%s\a' "$sls_success_icon deployed" "$notif_message"
        else
            printf '\e]777;notify;%s;%s\a' "$sls_failure_icon failed to deploy" "$notif_message"
        end
```

(The original used `&&`/`||` chaining, which is fine for two side-effects. Switching to `if/else` is clearer when each branch is a multi-arg `printf` and avoids re-typing the format string twice on one logical line.)

At line 215, replace:

```fish
        _ts_notify "$notif_title" "$notif_message"
```

with:

```fish
        printf '\e]777;notify;%s;%s\a' "$notif_title" "$notif_message"
```

- [ ] **Step 3: Syntax-check both files**

Run:
```bash
fish -n conf.d/travelstop.fish && fish -n functions/push.fish && echo OK
```
Expected: `OK`. Any syntax error means the edit was malformed — fix and re-run.

- [ ] **Step 4: Smoke-test the OSC 777 emission**

Run:
```bash
fish -c 'printf "\e]777;notify;%s;%s\a" "test title" "test message"'
```
Expected: on a terminal that supports OSC 777 (foot, kitty, urxvt, wezterm, etc.) a desktop notification appears. On a terminal that doesn't, the sequence is silently swallowed (no visible garbage) — that's the intended fallback.

- [ ] **Step 5: Confirm `_ts_notify` has no other callers**

Run:
```bash
grep -rn '_ts_notify' --include='*.fish' .
```
Expected: no matches (the function was removed and the 3 call sites were rewritten).

- [ ] **Step 6: Commit**

```bash
git add conf.d/travelstop.fish functions/push.fish
git commit -m "feat: replace _ts_notify with inline OSC 777"
```

---

## Task 2: Replace `md5 -q` with `md5sum`

**Files:**
- Modify: `functions/invoke.fish:66-67`

- [ ] **Step 1: Replace both `md5 -q` calls**

At lines 66 and 67, replace:

```fish
        if test "$$last_function_js" != (md5 -q $function_js)
            set -g $last_function_js (md5 -q $function_js)
```

with:

```fish
        if test "$$last_function_js" != (md5sum $function_js | string split -f1 ' ')
            set -g $last_function_js (md5sum $function_js | string split -f1 ' ')
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
fish -n functions/invoke.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Verify the substitution semantics**

Run on a known file:
```bash
fish -c 'echo (md5sum README.md | string split -f1 " ")'
```
Expected: a 32-character hex string, identical to what `md5 -q README.md` would produce on macOS. Cross-check against `md5sum README.md | cut -d" " -f1` if uncertain.

- [ ] **Step 4: Commit**

```bash
git add functions/invoke.fish
git commit -m "fix: use md5sum instead of BSD md5 -q"
```

---

## Task 3: Replace `tail -r` with awk reverse in `prune_functions_versions.fish`

**Files:**
- Modify: `functions/prune_functions_versions.fish:8, 10`

- [ ] **Step 1: Replace both `command tail -r` lines**

At lines 8 and 10, replace each occurrence of:

```fish
        | command tail -r \
```

with:

```fish
        | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}' \
```

The full pipeline (lines 5–11) becomes:

```fish
    aws lambda list-versions-by-function --function-name $function_name \
        | jq -r '.Versions.[].Version' \
        | command tail -n +2 \
        | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}' \
        | command tail -n +$keep \
        | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}' \
        | xargs -n1 -P $batch_size -I {} (which fish) -c _ts_delete_function_version $function_name {}
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
fish -n functions/prune_functions_versions.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Verify the awk reversal produces the same ordering as `tail -r`**

Run:
```bash
printf '1\n2\n3\n4\n5\n' | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}'
```
Expected output:
```
5
4
3
2
1
```
This must match what `tail -r` would produce — same sequence reversed.

- [ ] **Step 4: Commit**

```bash
git add functions/prune_functions_versions.fish
git commit -m "fix: replace BSD tail -r with portable awk reverse"
```

---

## Task 4: Replace `tail -r` with awk reverse in `prune_layer_versions.fish`

**Files:**
- Modify: `functions/prune_layer_versions.fish:8`

- [ ] **Step 1: Replace the single `command tail -r`**

At line 8, replace:

```fish
        | command tail -r \
```

with:

```fish
        | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}' \
```

The full pipeline (lines 5–9) becomes:

```fish
    aws lambda list-layer-versions --layer-name $layer_name \
        | jq -r '.LayerVersions.[].Version' \
        | command tail -n +(math $keep + 1) \
        | awk '{a[NR]=$0} END{for(i=NR;i;i--) print a[i]}' \
        | xargs -n1 -P $batch_size -I {} (which fish) -c _ts_delete_layer_version $layer_name {}
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
fish -n functions/prune_layer_versions.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add functions/prune_layer_versions.fish
git commit -m "fix: replace BSD tail -r with portable awk reverse"
```

---

## Task 5: Replace `sed -i ''` with `sed -i.ts_bak` + cleanup in `bump_version.fish`

**Files:**
- Modify: `functions/bump_version.fish:64`

- [ ] **Step 1: Replace the single `sed -i ''` call**

At line 64, replace:

```fish
        sed -i '' "1s;^;$changelog;" CHANGELOG.md
```

with:

```fish
        sed -i.ts_bak "1s;^;$changelog;" CHANGELOG.md
        and command rm CHANGELOG.md.ts_bak
```

- [ ] **Step 2: Syntax-check**

Run:
```bash
fish -n functions/bump_version.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Verify the `sed -i.ts_bak` form works on a throwaway file**

Run:
```bash
mkdir -p /tmp/sed-test && cd /tmp/sed-test && printf 'line1\nline2\n' > t.txt && \
  sed -i.ts_bak '1s/^/PREFIX-/' t.txt && \
  cat t.txt && ls && rm t.txt.ts_bak && cd - && rm -rf /tmp/sed-test
```
Expected output (order may vary on `ls`):
```
PREFIX-line1
line2
t.txt  t.txt.ts_bak
```
This confirms `sed -i.ts_bak` edits in place and creates a `.ts_bak` companion on this system.

- [ ] **Step 4: Commit**

```bash
git add functions/bump_version.fish
git commit -m "fix: use portable sed -i.ts_bak in bump_version"
```

---

## Task 6: Replace `sed -i ''` with `sed -i.ts_bak` + cleanup in `rename_modules.fish`

**Files:**
- Modify: `functions/rename_modules.fish:39, 44-45, 52, 87, 89`

The file has five `sed -i ''` invocations across three `if/else if/else` branches. Each replacement uses `sed -i.ts_bak`, then removes the `.ts_bak` companion files. Fish's element-wise expansion (`$ymls.ts_bak` → `a.ts_bak b.ts_bak ...`) makes the cleanup a one-liner for both single-file and list cases.

- [ ] **Step 1: Replace the line-39 call (clean-all-suffix branch)**

Replace:

```fish
        sed -i '' -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1\4/g' $ymls
```

with:

```fish
        sed -i.ts_bak -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1\4/g' $ymls
        and command rm $ymls.ts_bak
```

- [ ] **Step 2: Replace the line-44/45 call (force-add-suffix-to-modules branch)**

Replace:

```fish
        test -n "$ymls" &&
            sed -i '' -E 's/^service: module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/service: module-\1'"$suffix"'\4/g' $ymls
```

with:

```fish
        if test -n "$ymls"
            sed -i.ts_bak -E 's/^service: module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/service: module-\1'"$suffix"'\4/g' $ymls
            and command rm $ymls.ts_bak
        end
```

(The original `&&`-on-newline form mixes a guard and the action; switching to `if/end` makes the cleanup line fit naturally inside the same guard.)

- [ ] **Step 3: Replace the line-52 call (force-add-suffix-to-services branch)**

Replace:

```fish
        test -n "$ymls" && sed -i '' -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1'"$suffix"'\4/g' $ymls
```

with:

```fish
        if test -n "$ymls"
            sed -i.ts_bak -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1'"$suffix"'\4/g' $ymls
            and command rm $ymls.ts_bak
        end
```

- [ ] **Step 4: Replace the line-87 call (changed-modules service edit)**

Replace:

```fish
                sed -i '' -E 's/^service:.*$/service: '$module_name$suffix'/g' $$_ts_project_dir/modules/$d/serverless.yml
```

with:

```fish
                set -l _yml $$_ts_project_dir/modules/$d/serverless.yml
                sed -i.ts_bak -E 's/^service:.*$/service: '$module_name$suffix'/g' $_yml
                and command rm $_yml.ts_bak
```

(Capturing the path in a local makes the cleanup line readable. The variable is local to the `for d in ...` body, so it's safe to reuse the name `_yml` per iteration.)

- [ ] **Step 5: Replace the line-89 call (changed-modules layer edit)**

Replace:

```fish
                if test -n "$services_dirs"
                    sed -i '' -E 's/cf:'$module_name'[^$]*\$/cf:'$module_name$suffix'-$/g' $$_ts_project_dir/$services_dirs/serverless-layers.yml
                end
```

with:

```fish
                if test -n "$services_dirs"
                    set -l _layer_yml $$_ts_project_dir/$services_dirs/serverless-layers.yml
                    sed -i.ts_bak -E 's/cf:'$module_name'[^$]*\$/cf:'$module_name$suffix'-$/g' $_layer_yml
                    and command rm $_layer_yml.ts_bak
                end
```

- [ ] **Step 6: Syntax-check**

Run:
```bash
fish -n functions/rename_modules.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 7: Verify fish element-wise expansion of `$list.ts_bak`**

Run:
```bash
fish -c 'set -l xs a.yml b.yml c.yml; echo $xs.ts_bak'
```
Expected: `a.yml.ts_bak b.yml.ts_bak c.yml.ts_bak`. This confirms the cleanup loop logic in steps 1–3 will work for list-of-files cases.

- [ ] **Step 8: Commit**

```bash
git add functions/rename_modules.fish
git commit -m "fix: use portable sed -i.ts_bak in rename_modules"
```

---

## Task 7: Replace `date -v` with a node one-liner in `daily_report.fish`

**Files:**
- Modify: `functions/daily_report.fish:29-32`

- [ ] **Step 1: Replace the BSD date arithmetic**

At lines 29–32, replace:

```fish
    set -l start_time (date -v-1d -v12H -v0M -v0S +%s)000
    set -l end_time (date -v12H -v0M -v0S +%s)000

    set url "ext+container:name=$container&url=https://$region.console.aws.amazon.com/cloudwatch/home?region=$region#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$stack-$stage-$functionName/log-events\$3FfilterPattern\$3D\$2522$query\$2522\$26start\$3D$start_time\$26end\$3D$end_time"
```

with:

```fish
    node -e 'const e=new Date();e.setHours(12,0,0,0);console.log(e.getTime()-86400000+" "+e.getTime())' \
        | read -d ' ' start_time end_time

    set url "ext+container:name=$container&url=https://$region.console.aws.amazon.com/cloudwatch/home?region=$region#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$stack-$stage-$functionName/log-events\$3FfilterPattern\$3D\$2522$query\$2522\$26start\$3D$start_time\$26end\$3D$end_time"
```

The node expression returns milliseconds directly, so the URL no longer needs the trailing `000` literal (it's already part of the value).

- [ ] **Step 2: Syntax-check**

Run:
```bash
fish -n functions/daily_report.fish && echo OK
```
Expected: `OK`.

- [ ] **Step 3: Verify timestamp values look correct**

Run:
```bash
fish -c '
    node -e "const e=new Date();e.setHours(12,0,0,0);console.log(e.getTime()-86400000+\" \"+e.getTime())" \
        | read -d " " start_time end_time
    echo "start=$start_time end=$end_time"
    echo "start human: "(date -d @(math $start_time / 1000) 2>/dev/null; or date -r (math $start_time / 1000))
    echo "end human:   "(date -d @(math $end_time / 1000) 2>/dev/null; or date -r (math $end_time / 1000))
'
```
Expected: `start_time` is yesterday at 12:00:00 local time in ms, `end_time` is today at 12:00:00 local time in ms; the human-readable lines confirm this. The `date -d` / `date -r` fallback works on Linux / macOS respectively.

- [ ] **Step 4: Commit**

```bash
git add functions/daily_report.fish
git commit -m "fix: use node for date arithmetic instead of BSD date -v"
```

---

## Task 8: Update README install instructions

**Files:**
- Modify: `README.md:5-10` (Installation section)
- Modify: `README.md:107-112` (cowsay example block)

- [ ] **Step 1: Update the Installation section**

Replace:

```markdown
## Installation

```sh
brew install jq
fisher install \
  dangh/ansi-escape.fish \
  dangh/travelstop.fish
```
```

with:

```markdown
## Installation

Install `jq`:
- macOS: `brew install jq`
- Debian/Ubuntu: `sudo apt install jq`
- Arch: `sudo pacman -S jq`
- Other: see https://jqlang.github.io/jq/download/

Then:

```sh
fisher install \
  dangh/ansi-escape.fish \
  dangh/travelstop.fish
```
```

- [ ] **Step 2: Flag the cowsay example as macOS-specific**

Replace:

```markdown
### Random rainbow cowsay fortune before each request log:

```sh
brew install cowsay fortune lolcat
set -Ux ts_blank_page_cmd fortune \| cowsay -f \$\( ls /opt/homebrew/share/cows/*.cow \| sort -R \| head -1 \) \| lolcat -F 0.01
```
```

with:

```markdown
### Random rainbow cowsay fortune before each request log (macOS — Homebrew paths):

```sh
brew install cowsay fortune lolcat
set -Ux ts_blank_page_cmd fortune \| cowsay -f \$\( ls /opt/homebrew/share/cows/*.cow \| sort -R \| head -1 \) \| lolcat -F 0.01
```

On Linux, the cow files live elsewhere depending on your distro (e.g. `/usr/share/cowsay/cows` on Debian/Ubuntu, `/usr/share/cows` on Arch). Adjust the path in `ls ...` accordingly.
```

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add Linux install instructions"
```

---

## Final verification (after all tasks)

- [ ] **Step 1: Confirm no macOS-specific call remains**

Run:
```bash
grep -rn -E "osascript|afplay|/System/Library/Sounds|/opt/homebrew|md5 -q|tail -r|sed -i ''|date -[vjrf]" \
  --include='*.fish' --include='*.awk' --include='*.jq' .
```
Expected: no matches in code files. (The README block flagged in Task 8 may still mention `/opt/homebrew` and `brew` — that's intentional.)

- [ ] **Step 2: Confirm every changed file still parses**

Run:
```bash
for f in conf.d/travelstop.fish functions/*.fish; do
    fish -n "$f" || echo "SYNTAX ERROR: $f"
done
echo done
```
Expected: only the final `done` printed; no `SYNTAX ERROR` lines.

- [ ] **Step 3: Confirm git tree is clean and all changes are committed**

Run:
```bash
git status
```
Expected: `nothing to commit, working tree clean`.
