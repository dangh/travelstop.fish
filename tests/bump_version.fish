# fishtape spec for bump_version (functions/bump_version.fish).
# Run: fishtape tests/bump_version.fish < /dev/null
#
# Real code under test: the whole bump_version function -- ts extraction from the
# branch name, CHANGELOG parsing (last_version/last_release/last_message), the
# "task already in changelog" vs "new task" branches, default minor + release
# bumps, and the sed prepend that writes the new CHANGELOG entry.
#
# Stubs cover ONLY external side-effects, mirroring tests/push.fish:
#   * `git`  -- shadowing fish function returning a controlled branch / tag list,
#               so ts-extraction and release-bump logic are deterministic.
#   * `npm`  -- PATH shim under tests/fixtures/bump_version/bin. bump_version runs
#               `npm version` inside `command env ... fish -P -c`, a fresh subshell
#               that does NOT see fish functions -- only PATH -- so the stub must
#               live on PATH. It mimics npm by writing the version into package.json.
# jq and sed are real (jq is required by the function and present on the box).
#
# Every test runs in its own mktemp dir seeded from the committed fixtures, so the
# checked-in CHANGELOG.md / package.json under tests/fixtures/bump_version stay
# pristine no matter how many entries get prepended.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -g BV_FIX $here/fixtures/bump_version

source $repo/functions/bump_version.fish

# --- per-test sandbox -----------------------------------------------------
# Seed a fresh working dir from the fixtures and cd into it. Returns the dir.
function _bv_sandbox
    set -l d (mktemp -d)
    cp $BV_FIX/CHANGELOG.md $d/CHANGELOG.md
    cp $BV_FIX/package.json $d/package.json
    cd $d
    echo $d
end

# Put the npm shim first on PATH (used by the fish -P subshell inside bump_version).
set -gx PATH $BV_FIX/bin $PATH

# ============================================================================
# ts extraction from the git branch (git --show-current shadowed)
# ============================================================================

# Branch "ts-1234-..." matches an existing changelog entry -> message is reused
# from the changelog, no -t / message needed. (last_message present => no bump.)
function git; echo ts-1234-existing-work; end
set -l d (_bv_sandbox)
bump_version >/dev/null 2>&1
set -l code $status
@test "branch ts-1234: succeeds reusing changelog message" $code -eq 0
@test "branch ts-1234: prepends a new entry for TS-1234" (string match -rq 'TS-1234.*existing feature' -- (cat CHANGELOG.md)[2]; echo $status) -eq 0
@test "branch ts-1234: leaves no sed .ts_bak backup behind" (count *.ts_bak) -eq 0
cd $here; rm -rf $d
functions -e git

# Bare numeric branch "456-fix" also yields ts=456 (the `ts-` prefix is optional).
# 456 is not in the changelog and no message is given -> "message is required".
function git; echo 456-fix; end
set -l d (_bv_sandbox)
set -l out (bump_version 2>&1)
set -l code $status
@test "branch 456-fix: ts derived from bare number, errors on missing msg" $code -ne 0
@test "branch 456-fix: error is 'message is required'" (string match -q '*message is required*' -- "$out"; echo $status) -eq 0
cd $here; rm -rf $d
functions -e git

# Branch with no leading digits (e.g. "main") -> no ts -> "task number is required".
function git; echo main; end
set -l d (_bv_sandbox)
set -l out (bump_version some message 2>&1)
set -l code $status
@test "branch main: no ts -> non-zero exit" $code -ne 0
@test "branch main: error is 'task number is required'" (string match -q '*task number is required*' -- "$out"; echo $status) -eq 0
cd $here; rm -rf $d
functions -e git

# ============================================================================
# -t overrides branch extraction (git branch never consulted for ts)
# ============================================================================

# -t 1234 + existing changelog entry: works even though branch would give no ts.
function git; echo main; end
set -l d (_bv_sandbox)
bump_version -t 1234 >/dev/null 2>&1
@test "-t 1234 overrides branch: succeeds" $status -eq 0
@test "-t 1234 overrides branch: writes TS-1234 entry" (string match -q '*TS-1234*' -- (cat CHANGELOG.md)[2]; echo $status) -eq 0
cd $here; rm -rf $d
functions -e git

# ============================================================================
# new task (not in changelog): default minor bump + release bump from git tag
# ============================================================================

# TS-7777 absent from changelog. last_version=1.2.3 -> minor bump -> 1.3.0.
# git tag list -> latest 4.6 -> release minor bump -> 4.7. npm shim writes 1.3.0
# into package.json, which jq then reads back for the changelog header.
function git
    switch $argv[1]
        case branch
            echo ts-7777-brand-new
        case tag
            printf '1.0\n4.5\n4.6\n'
    end
end
set -l d (_bv_sandbox)
bump_version a brand new task >/dev/null 2>&1
set -l code $status
set -l head1 (cat CHANGELOG.md)[1]
set -l head2 (cat CHANGELOG.md)[2]
@test "new task: succeeds" $code -eq 0
@test "new task: minor version bumped 1.2.3 -> 1.3.0 in header" (string match -rq '^# 1\.3\.0 ' -- $head1; echo $status) -eq 0
@test "new task: release bumped 4.6 -> 4.7 in header" (string match -rq 'Release: \[4\.7\].*tag/4\.7' -- $head1; echo $status) -eq 0
@test "new task: package.json bumped to 1.3.0 by npm shim" (jq -r .version package.json) = 1.3.0
@test "new task: entry carries the supplied message" (string match -rq 'TS-7777.*: a brand new task' -- $head2; echo $status) -eq 0
cd $here; rm -rf $d
functions -e git

# ============================================================================
# explicit -v and -r flags win over the computed defaults (new task)
# ============================================================================

function git
    switch $argv[1]
        case branch
            echo ts-8888-explicit
        case tag
            printf '2.9\n3.0\n'
    end
end
set -l d (_bv_sandbox)
bump_version -v 5.6.7 -r 9.9 explicit version >/dev/null 2>&1
set -l code $status
set -l head1 (cat CHANGELOG.md)[1]
@test "explicit flags: succeeds" $code -eq 0
@test "explicit flags: header uses -v 5.6.7" (string match -rq '^# 5\.6\.7 ' -- $head1; echo $status) -eq 0
@test "explicit flags: header uses -r 9.9" (string match -rq 'Release: \[9\.9\].*tag/9\.9' -- $head1; echo $status) -eq 0
@test "explicit flags: package.json set to 5.6.7" (jq -r .version package.json) = 5.6.7
cd $here; rm -rf $d
functions -e git

# ============================================================================
# release == last_release -> else branch (the `# TODO`): CHANGELOG untouched
# ============================================================================

# Existing task TS-1234 (message reused), -r 4.5 == last_release 4.5, and
# v stays at last_version 1.2.3, so the function hits the empty else branch
# and writes nothing. Observable: CHANGELOG is byte-identical to the seed.
function git; echo ts-1234-x; end
set -l d (_bv_sandbox)
bump_version -r 4.5 >/dev/null 2>&1
@test "release==last_release: CHANGELOG left unchanged" (diff -q CHANGELOG.md $BV_FIX/CHANGELOG.md >/dev/null; echo $status) -eq 0
cd $here; rm -rf $d
functions -e git

# NOTE (skipped): the `npm i --package-lock-only` call and the `package-lock.json`
# branch are pure side-effects with no observable output here -- there is no
# package-lock.json in the fixture, so that line is a no-op and is intentionally
# left untested rather than fabricating behavior for it.
