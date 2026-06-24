# fishtape spec for build_libs (functions/build_libs.fish).
# Run: fishtape tests/build_libs.fish < /dev/null
#
# Real code under test: _ts_libs (pure lister) and build_libs (orchestrator).
#
# The whole fixture tree is built in a fresh `mktemp -d` at runtime and removed
# in teardown, so nothing under tests/fixtures or the repo is ever touched.
#
# build_libs' real side-effects -- `command git`, `command npm pack`,
# `command npm install` -- bypass fish functions, so they are shadowed with
# tiny fake executables placed first on PATH. We assert on the deterministic
# `_ts_log` output that build_libs emits in the main shell (which libs it
# decides to rebuild + the exact npm-install command line it composes); the
# real packing/installing inside the nested `fish -P -c` subshells is the
# side-effect-heavy part and is rendered a harmless no-op rather than verified.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/build_libs.fish

# --- stub only presentation helpers --------------------------------------
for c in magenta yellow blue green red dim bold ansi-escape
    function $c; echo $argv; end
end

# --- runtime fixture root (never the committed tree) ---------------------
set -g TS_ROOT (mktemp -d)
set -g TS_BIN $TS_ROOT/bin
set -g TS_LOG $TS_ROOT/ts.log
set -g _ts_project_dir TS_PD
set -g TS_PD $TS_ROOT

# _ts_log is captured to a file so each test can inspect what build_libs decided.
function _ts_log; echo $argv >>$TS_LOG; end

# fake `git`: behaviour is swapped per-test by rewriting these scripts.
mkdir -p $TS_BIN
function _fake_git_changed # empty log -> last_commit_id empty -> lib treated as changed
    printf '#!/bin/sh\nexit 0\n' >$TS_BIN/git
    chmod +x $TS_BIN/git
end
function _fake_git_unchanged # log -> a hash, diff -> empty -> lib has no changes
    printf '#!/bin/sh\ncase "$1" in\n  log) echo abc123;;\nesac\nexit 0\n' >$TS_BIN/git
    chmod +x $TS_BIN/git
end
# fake `npm`: prints a tgz name for `pack`, otherwise a no-op success.
printf '#!/bin/sh\n[ "$1" = pack ] && echo fake.tgz\nexit 0\n' >$TS_BIN/npm
chmod +x $TS_BIN/npm
set -gx PATH $TS_BIN $PATH

# build a libs/nodejs/package.json whose pack script lists the given lib paths.
# each `npm pack <path>` is followed by whitespace so _ts_libs' trailing-token
# match captures a clean path (a value-terminating `"` with no space would
# otherwise be glued onto the last token).
function _write_libs_pkg
    mkdir -p $TS_ROOT/modules/libs/nodejs
    set -l cmds
    for p in $argv
        set -a cmds "npm pack $p "
    end
    printf '{"scripts":{"pack":"%s"}}\n' (string join '&& ' $cmds) \
        >$TS_ROOT/modules/libs/nodejs/package.json
end

function _write_lib_pkg # dir version
    mkdir -p $argv[1]
    printf '{\n  "version": "%s"\n}\n' $argv[2] >$argv[1]/package.json
end

# =========================================================================
# _ts_libs -- the pure lister
# =========================================================================
_write_libs_pkg ../../../lib/auth ../../../schema ../../../lib/utils
set -l libs (_ts_libs)
@test "_ts_libs lists one entry per 'npm pack'" (count $libs) -eq 3
@test "_ts_libs returns the full pack path verbatim" $libs[1] = ../../../lib/auth
@test "_ts_libs keeps the schema path" $libs[2] = ../../../schema
@test "_ts_libs keeps the last path clean (no trailing quote)" $libs[3] = ../../../lib/utils

# basenames are what build_libs derives via `string match -r '[^/]+$'`
set -l bases
for d in $libs
    set -a bases (string match -r '[^/]+$' $d)
end
@test "_ts_libs basenames resolve to lib names" "$bases" = "auth schema utils"

_write_libs_pkg ../../../lib/only
@test "_ts_libs handles a single lib" (count (_ts_libs)) -eq 1

# no `npm pack` in the package.json -> empty listing
mkdir -p $TS_ROOT/modules/libs/nodejs
printf '{"scripts":{"build":"tsc"}}\n' >$TS_ROOT/modules/libs/nodejs/package.json
@test "_ts_libs is empty when no pack scripts" (count (_ts_libs)) -eq 0

# =========================================================================
# build_libs -- orchestration (side-effects shadowed)
# =========================================================================

# ----- argparse -----
printf '{"scripts":{"build":"tsc"}}\n' >$TS_ROOT/modules/libs/nodejs/package.json
@test "build_libs rejects unknown flags" (build_libs --nonsense 2>/dev/null; echo $status) -eq 1

# ----- no libs -> noop happy path (no subshell, no npm) -----
: >$TS_LOG
build_libs >/dev/null 2>&1
@test "build_libs with no libs succeeds" $status -eq 0
@test "build_libs always logs 'rebuild libs'" (string match -q '*rebuild libs*' -- (cat $TS_LOG); echo $status) -eq 0
@test "build_libs with no libs runs no npm install" (string match -q '*npm install*' -- (cat $TS_LOG); echo $status) -eq 1

# ----- changed libs -> REBUILD + composed install command -----
_write_libs_pkg ../../../lib/auth ../../../schema
_write_lib_pkg $TS_ROOT/lib/auth 1.0.0
_write_lib_pkg $TS_ROOT/schema 2.0.0
_fake_git_changed
: >$TS_LOG
build_libs >/dev/null 2>&1
set -l out (cat $TS_LOG)
@test "build_libs marks auth as changed" (string match -q '*auth: changed*REBUILD*' -- $out; echo $status) -eq 0
@test "build_libs marks schema as changed" (string match -q '*schema: changed*REBUILD*' -- $out; echo $status) -eq 0
@test "build_libs composes an npm install command" (string match -q '*npm install --no-proxy*' -- $out; echo $status) -eq 0
# version is parsed from each lib's own package.json; schema uses the schema/
# dir, others use lib/<name>/ -- both reflected in the tgz paths.
@test "build_libs derives the auth tgz from lib/auth version" (string match -q '*/packages/auth/auth-1.0.0.tgz*' -- $out; echo $status) -eq 0
@test "build_libs derives the schema tgz from schema dir version" (string match -q '*/packages/schema/schema-2.0.0.tgz*' -- $out; echo $status) -eq 0

# ----- unchanged lib -> SKIP, no install -----
_write_libs_pkg ../../../lib/auth
_write_lib_pkg $TS_ROOT/lib/auth 1.0.0
_fake_git_unchanged
: >$TS_LOG
build_libs >/dev/null 2>&1
set -l out (cat $TS_LOG)
@test "build_libs skips an unchanged lib" (string match -q '*auth: no changes*SKIP*' -- $out; echo $status) -eq 0
@test "build_libs runs no install when everything is unchanged" (string match -q '*npm install*' -- $out; echo $status) -eq 1

# ----- --force overrides 'no changes' -----
: >$TS_LOG
build_libs --force >/dev/null 2>&1
set -l out (cat $TS_LOG)
@test "build_libs --force rebuilds an unchanged lib" (string match -q '*auth: FORCE REBUILD*' -- $out; echo $status) -eq 0
@test "build_libs --force triggers an install" (string match -q '*npm install*' -- $out; echo $status) -eq 0

# --- teardown ------------------------------------------------------------
rm -rf $TS_ROOT
