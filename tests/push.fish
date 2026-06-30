# fishtape spec for push, run against the committed fixture project under
# tests/fixtures/project (no function mocks for the resolution logic).
# Run: fishtape tests/push.fish < /dev/null
#
# Real code under test: push, _ts_resolve_config, _ts_push_all_targets (push.fish)
# and _ts_service_name / _ts_modules / _ts_substacks / _ts_functions (conf.d slice).
# Only true side-effects are stubbed: sls deploy, npm (PATH shim), notify, colors.
# The fixtures are never mutated (rename_modules/_ts_sls/npm are no-ops), so the
# checked-in tree stays pristine across runs.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
# Work on a throwaway copy: push runs `nvm use` + real `npm i` against any
# service with a package.json, which would write package-lock.json into the
# committed fixtures. Copy to a temp dir so the checked-in tree stays pristine.
set -g TS_ROOT (mktemp -d)
cp -R $here/fixtures/project/. $TS_ROOT
mkdir -p $TS_ROOT/empty

source $repo/functions/push.fish
# conf.d lines 73-138 hold the real listing helpers; the file's `exit` (line 221)
# forbids sourcing it whole, so source just that slice.
source (sed -n '73,138p' $repo/conf.d/travelstop.fish | psub)

# --- stub only external side-effects -------------------------------------
function _ts_log; echo $argv; end
for c in magenta yellow blue green red dim ansi-escape
    function $c; echo $argv; end
end
function rename_modules; end
set -g TS_NOTIFY_LOG (mktemp)
function _ts_notify; echo "$argv" >>$TS_NOTIFY_LOG; end
function _ts_progress; end
set -g TS_SLS_LOG (mktemp)
# fail one deploy when TS_FAIL_FLAG is non-empty, then clear it so a retry succeeds.
# TS_INT_FLAG simulates Ctrl-C: sls exits with a signal status (130 = SIGINT),
# which fish reports after it resumes the script post-signal.
set -g TS_FAIL_FLAG (mktemp)
set -g TS_INT_FLAG (mktemp)
function _ts_sls
    echo "$argv" >>$TS_SLS_LOG
    if test -s $TS_INT_FLAG
        echo -n >$TS_INT_FLAG
        return 130
    end
    if test -s $TS_FAIL_FLAG
        echo -n >$TS_FAIL_FLAG
        return 1
    end
    return 0
end

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -g _ts_project_dir TS_PD
set -g TS_PD $TS_ROOT
set -gx PATH $TS_ROOT/bin $PATH
cd $TS_ROOT

# ===== real _ts_resolve_config =====
_ts_resolve_config hotels '' | read -l -d : tt yml sn fn ver region
@test "resolve hotels -> service type" $tt = service
@test "resolve hotels -> service name from yml" $sn = hotels-service
@test "resolve hotels -> version from package.json" $ver = 1.2.3
@test "resolve hotels -> region from yml" $region = us-east-1

# ===== real listing helpers against fixtures =====
@test "_ts_modules lists the module" (contains modules/auth (_ts_modules); echo $status) -eq 0
@test "_ts_functions parses functions block" (contains getHotel (_ts_functions $TS_ROOT/hotels/serverless.yml); echo $status) -eq 0

# ===== push happy path =====
echo -n >$TS_SLS_LOG
push hotels >/dev/null 2>&1
@test "push hotels deploys in the hotels dir" (string match -q '*/hotels *' -- (cat $TS_SLS_LOG); echo $status) -eq 0

# ===== push -a recursion (service + subservices) =====
echo -n >$TS_SLS_LOG
push -a hotels >/dev/null 2>&1
@test "-a hotels deploys 2 stacks" (count (cat $TS_SLS_LOG)) -eq 2
@test "-a hotels includes the subservice" (string match -q '*/hotels/sub *' -- (cat $TS_SLS_LOG); echo $status) -eq 0

# ===== monitoring subservice deploys last =====
# temp monitoring stack; removed after so later tests still see 2 targets
mkdir -p $TS_ROOT/hotels/monitoring
printf "service: hotels-monitoring\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/hotels/monitoring/serverless.yml
echo -n >$TS_SLS_LOG
push -a hotels >/dev/null 2>&1
@test "monitoring deploys last" (string match -q '*/hotels/monitoring *' -- (cat $TS_SLS_LOG)[-1]; echo $status) -eq 0
@test "monitoring is not first" (string match -q '*/hotels/monitoring *' -- (cat $TS_SLS_LOG)[1]; echo $status) -eq 1
rm -rf $TS_ROOT/hotels/monitoring

# ===== regression: unresolvable target must not crash =====
# previously: empty _ts_resolve_config output left target_type as 0 elements ->
# `set -a {$target_type}s ...` failed with "invalid variable name".
# Run from a dir without serverless.yml so the $PWD fallback can't resolve it.
cd $TS_ROOT/empty
set -l out (push bogus 2>&1)
set -l code $status
@test "push bogus exits non-zero" $code -ne 0
@test "push bogus has no 'invalid variable name' crash" (string match -q '*invalid variable name*' -- "$out"; echo $status) -eq 1
@test "push bogus logs a clear error" (string match -q '*cannot resolve target*' -- "$out"; echo $status) -eq 0

# ===== -a with unresolvable base errors cleanly =====
set -l out (push -a nope 2>&1)
set -l code $status
@test "-a nope exits non-zero" $code -ne 0
@test "-a nope no crash" (string match -q '*invalid variable name*' -- "$out"; echo $status) -eq 1

# ===== interactive mode: $EDITOR can reorder/delete targets =====
# fake editor: keep only the last target line (drops the rest)
set -g TS_FAKE_EDITOR (mktemp)
echo '#!/usr/bin/env fish
set -l f $argv[1]
set -l kept (string match -r \'^\d+\' < $f)[-1]
printf \'%s\n\' $kept > $f' >$TS_FAKE_EDITOR
chmod +x $TS_FAKE_EDITOR
set -gx EDITOR $TS_FAKE_EDITOR

cd $TS_ROOT
echo -n >$TS_SLS_LOG
push -i -a hotels >/dev/null 2>&1
@test "-i keeps only the editor-selected target" (count (cat $TS_SLS_LOG)) -eq 1

# fake editor that deletes everything -> no deploy
echo '#!/usr/bin/env fish
printf \'\' > $argv[1]' >$TS_FAKE_EDITOR
echo -n >$TS_SLS_LOG
set -l out (push -i -a hotels 2>&1)
@test "-i with all lines deleted deploys nothing" (count (cat $TS_SLS_LOG)) -eq 0
@test "-i empty selection logs a notice" (string match -q '*no targets selected*' -- "$out"; echo $status) -eq 0
set -e EDITOR

# ===== retry on failure: 'r' redeploys the failed target =====
cd $TS_ROOT
echo -n >$TS_SLS_LOG
echo fail >$TS_FAIL_FLAG
printf 'r\n' | push hotels >/dev/null 2>&1
@test "retry redeploys the failed target (2 sls calls)" (count (cat $TS_SLS_LOG)) -eq 2

# ===== skip on failure: 's' skips the failed target, continues with the rest =====
cd $TS_ROOT
echo -n >$TS_SLS_LOG
echo fail >$TS_FAIL_FLAG
printf 's\n' | push -a hotels >/dev/null 2>&1
@test "skip continues to the next target (2 calls)" (count (cat $TS_SLS_LOG)) -eq 2
@test "skip moves on to the subservice" (string match -q '*/hotels/sub *' -- (cat $TS_SLS_LOG)[-1]; echo $status) -eq 0

# ===== abort on failure (default/EOF) stops the run =====
echo -n >$TS_SLS_LOG
echo -n >$TS_NOTIFY_LOG
echo fail >$TS_FAIL_FLAG
push -a hotels >/dev/null 2>&1 </dev/null
set -l code $status
@test "abort on first failure deploys only once" (count (cat $TS_SLS_LOG)) -eq 1
@test "failure sends a notification" (string match -q '*push failed*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
echo -n >$TS_FAIL_FLAG

# ===== Ctrl-C during deploy interrupts the run (no retry/abort prompt) =====
# No stdin is fed: a real failure would block on `read`, but an interrupt must
# stop the run on its own without ever prompting.
cd $TS_ROOT
echo -n >$TS_SLS_LOG
echo -n >$TS_NOTIFY_LOG
echo int >$TS_INT_FLAG
set -l out (push -a hotels 2>&1 </dev/null)
@test "interrupt makes only 1 attempt" (count (cat $TS_SLS_LOG)) -eq 1
@test "interrupt logs 'interrupted'" (string match -q '*interrupted*' -- "$out"; echo $status) -eq 0
@test "interrupt does NOT send a push-failed notification" (string match -q '*push failed*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 1
@test "interrupt prints the continue hint" (string match -q '*push -C*' -- "$out"; echo $status) -eq 0
# resume works after an interrupt (fail flag is clear, so the rest succeed)
echo -n >$TS_SLS_LOG
push -C </dev/null >/dev/null 2>&1
@test "continue after interrupt deploys the remaining targets" (count (cat $TS_SLS_LOG)) -eq 2
echo -n >$TS_INT_FLAG

# ===== -C/--continue resumes a failed/interrupted run =====
cd $TS_ROOT
echo -n >$TS_SLS_LOG
echo fail >$TS_FAIL_FLAG
# first target fails -> abort -> state saved with one failure + one pending
set -l out (push -a hotels </dev/null 2>&1)
@test "aborted run made 1 attempt" (count (cat $TS_SLS_LOG)) -eq 1
@test "abort prints continue hint" (string match -q '*push -C*' -- "$out"; echo $status) -eq 0
# continue: redeploys the failed + remaining target (fail flag already cleared)
echo -n >$TS_SLS_LOG
push -C </dev/null >/dev/null 2>&1
@test "continue deploys the 2 remaining targets" (count (cat $TS_SLS_LOG)) -eq 2
# state cleared after a clean finish
set -l out2 (push -C </dev/null 2>&1)
@test "continue with no saved state says so" (string match -q '*nothing to continue*' -- "$out2"; echo $status) -eq 0

# --- teardown ------------------------------------------------------------
cd $repo
rm -rf $TS_ROOT
rm -f $TS_SLS_LOG $TS_FAKE_EDITOR $TS_FAIL_FLAG $TS_NOTIFY_LOG
