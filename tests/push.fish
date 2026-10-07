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
# parallel tiers spawn child `fish -c` processes: keep their config and the
# per-run log dir inside the temp tree so the real ~/.config and runtime dir
# are never touched (and the children see only the stubs below).
set -gx XDG_RUNTIME_DIR $TS_ROOT/run
set -gx XDG_CONFIG_HOME $TS_ROOT/cfg
mkdir -p $XDG_RUNTIME_DIR $XDG_CONFIG_HOME/fish/conf.d

source $repo/functions/push.fish
# conf.d holds the real listing helpers (_ts_service_name .. _ts_functions); the
# file's top-level `exit` forbids sourcing it whole, so source just that slice.
source (awk '/^function _ts_service_name /{p=1} p{print} /^function _ts_functions /{f=1} f&&/^end$/{exit}' $repo/conf.d/travelstop.fish | psub)

# --- stub only external side-effects -------------------------------------
function _ts_log; echo $argv; end
for c in magenta yellow blue green red dim ansi-escape
    function $c; echo $argv; end
end
set -gx TS_RENAME_LOG (mktemp)
function rename_modules; echo "$argv" >>$TS_RENAME_LOG; end
function _ts_ensure_session; end
function _ts_pm_install; echo true; end
set -gx TS_NOTIFY_LOG (mktemp)
function _ts_notify; echo "$argv" >>$TS_NOTIFY_LOG; end
function _ts_progress; end
set -gx TS_SLS_LOG (mktemp)
# fail one deploy when TS_FAIL_FLAG is non-empty, then clear it so a retry
# succeeds. Content `fail` fails whatever comes first; any other content is a
# glob matched against the sls argv so one specific target of a parallel tier
# fails (a race-free way to pick the victim).
# TS_INT_FLAG simulates Ctrl-C: sls exits with a signal status (130 = SIGINT),
# which fish reports after it resumes the script post-signal.
# TS_SLS_SLEEP (seconds) + TS_ORDER_LOG record `start`/`end` markers around a
# fake deploy so tests can tell overlapping (parallel) from sequential runs.
set -gx TS_FAIL_FLAG (mktemp)
set -gx TS_INT_FLAG (mktemp)
set -gx TS_ORDER_LOG (mktemp)
function _ts_sls
    echo "$argv" >>$TS_SLS_LOG
    echo "sls $argv"
    if test -s $TS_INT_FLAG
        echo -n >$TS_INT_FLAG
        return 130
    end
    if test -s $TS_FAIL_FLAG
        set -l want (cat $TS_FAIL_FLAG)
        if test "$want" = fail || string match -q -- "$want" "$argv"
            echo -n >$TS_FAIL_FLAG
            return 1
        end
    end
    if test -n "$TS_SLS_SLEEP"
        echo "start $argv" >>$TS_ORDER_LOG
        sleep $TS_SLS_SLEEP
        echo "end $argv" >>$TS_ORDER_LOG
    end
    return 0
end
# children (parallel tiers) autoload nothing from the real config: hand them
# the same stubs through the temp conf.d
functions _ts_log magenta yellow blue green red dim ansi-escape \
    rename_modules _ts_ensure_session _ts_pm_install _ts_notify _ts_progress _ts_sls \
    >$XDG_CONFIG_HOME/fish/conf.d/ts_stubs.fish

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -gx _ts_project_dir TS_PD
set -gx TS_PD $TS_ROOT
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

# ===== authorizers deploy before other services =====
# dir name sorts last on purpose: the service name (*authorizer*) decides
mkdir -p $TS_ROOT/hotels/z-authorizers
printf "service: hotels-authorizers\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/hotels/z-authorizers/serverless.yml
echo -n >$TS_SLS_LOG
push -a hotels >/dev/null 2>&1
@test "authorizers deploy first" (string match -q '*/hotels/z-authorizers *' -- (cat $TS_SLS_LOG)[1]; echo $status) -eq 0
@test "authorizers deploy once" (count (string match '*/hotels/z-authorizers *' -- (cat $TS_SLS_LOG))) -eq 1
rm -rf $TS_ROOT/hotels/z-authorizers

# ===== -a from a dir that is not a service itself =====
# a plain parent dir holding services must expand to them, instead of climbing
# to the nearest enclosing service (here: the project root).
mkdir -p $TS_ROOT/group/one $TS_ROOT/group/two
printf "service: group-one\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/group/one/serverless.yml
printf "service: group-two\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/group/two/serverless.yml
echo -n >$TS_SLS_LOG
push -a group </dev/null >/dev/null 2>&1
@test "-a <parent dir> deploys the services it holds" (count (cat $TS_SLS_LOG)) -eq 2
@test "-a <parent dir> does not climb to the project root" (string match -q '*/group/*' -- (cat $TS_SLS_LOG)[1]; echo $status) -eq 0

# ===== authorizers deploy before other services =====
# dir name sorts last on purpose: the service name (*authorizer*) decides
mkdir -p $TS_ROOT/group/z-authorizers
printf "service: group-authorizers\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/group/z-authorizers/serverless.yml
echo -n >$TS_SLS_LOG
push -j 1 -a group </dev/null >/dev/null 2>&1
@test "-a lists authorizers before other services" (string match -q '*/group/z-authorizers *' -- (cat $TS_SLS_LOG)[1]; echo $status) -eq 0
rm -rf $TS_ROOT/group/z-authorizers
echo -n >$TS_SLS_LOG
cd $TS_ROOT/group
push -a </dev/null >/dev/null 2>&1
@test "-a from inside a non-service dir deploys the services below it" (count (cat $TS_SLS_LOG)) -eq 2
cd $TS_ROOT
rm -rf $TS_ROOT/group

# a dir with no service at or below it still walks up to the enclosing service
echo -n >$TS_SLS_LOG
mkdir -p $TS_ROOT/hotels/src/lib
cd $TS_ROOT/hotels/src/lib
push -a </dev/null >/dev/null 2>&1
@test "-a from a plain subdir walks up to the enclosing service" (count (cat $TS_SLS_LOG)) -eq 2
cd $TS_ROOT
rm -rf $TS_ROOT/hotels/src

# ===== regression: taskbar progress percent must stay an integer =====
# previously: `math "$i * 100 / count"` returned a float, and `printf '%d'` then
# failed per target with "value not completely converted". Only shows up when
# the target count does not divide 100 (3 stacks -> 33.333333), which is why the
# 2-stack cases above never caught it.
mkdir -p $TS_ROOT/hotels/mon2
printf "service: hotels-mon2\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/hotels/mon2/serverless.yml
echo -n >$TS_SLS_LOG
set -l out (push -a hotels </dev/null 2>&1)
@test "3 stacks deploy" (count (cat $TS_SLS_LOG)) -eq 3
@test "progress percent does not break printf" (string match -q '*not completely converted*' -- "$out"; echo $status) -eq 1
rm -rf $TS_ROOT/hotels/mon2

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

# regression: the editor runs inside a command substitution, so anything it
# writes to stdout used to be parsed as extra (empty) targets. fake editor
# writes a junk line to stdout and keeps only the last target line.
echo '#!/usr/bin/env fish
set -l f $argv[1]
echo leaked-editor-output
set -l kept (string match -r \'^\d+\' < $f)[-1]
printf \'%s\n\' $kept > $f' >$TS_FAKE_EDITOR
echo -n >$TS_SLS_LOG
push -i -a hotels >/dev/null 2>&1
@test "-i editor stdout does not leak into targets" (count (cat $TS_SLS_LOG)) -eq 1

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

# ===== $ts_push_rename_modules gates the module renaming =====
cd $TS_ROOT
echo -n >$TS_RENAME_LOG
push hotels </dev/null >/dev/null 2>&1
@test "renaming runs by default" (count (cat $TS_RENAME_LOG)) -gt 0

set -g ts_push_rename_modules false
echo -n >$TS_RENAME_LOG
echo -n >$TS_SLS_LOG
push hotels </dev/null >/dev/null 2>&1
@test "ts_push_rename_modules=false skips renaming" (count (cat $TS_RENAME_LOG)) -eq 0
@test "ts_push_rename_modules=false still deploys" (count (cat $TS_SLS_LOG)) -eq 1
set -e ts_push_rename_modules

# ===== parallel tiers =====
# each fake deploy sleeps 1s and logs start/end: two independent services must
# overlap (start,start,end,end); dependent ones must serialize (start,end,...).
function ts_order -d "sequence of start/end markers from the last run"
    string match -r '^\S+' -- (cat $TS_ORDER_LOG) | string join ,
end
cd $TS_ROOT
set -gx TS_SLS_SLEEP 1

echo -n >$TS_ORDER_LOG
push hotels flights </dev/null >/dev/null 2>&1
@test "independent services deploy concurrently" (ts_order) = start,start,end,end

echo -n >$TS_ORDER_LOG
push -j 1 hotels flights </dev/null >/dev/null 2>&1
@test "-j 1 deploys sequentially" (ts_order) = start,end,start,end

echo -n >$TS_ORDER_LOG
push -a hotels </dev/null >/dev/null 2>&1
@test "parent stack finishes before its subservice starts" (ts_order) = start,end,start,end
@test "parent stack goes first" (string match -q '*/hotels *' -- (cat $TS_ORDER_LOG)[1]; echo $status) -eq 0

echo -n >$TS_ORDER_LOG
push modules/auth hotels </dev/null >/dev/null 2>&1
@test "module finishes before the service starts" (ts_order) = start,end,start,end
@test "module goes first" (string match -q '*/modules/auth *' -- (cat $TS_ORDER_LOG)[1]; echo $status) -eq 0

mkdir -p $TS_ROOT/group/z-authorizers
printf "service: group-authorizers\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/group/z-authorizers/serverless.yml
echo -n >$TS_ORDER_LOG
push group/one group/z-authorizers </dev/null >/dev/null 2>&1
@test "authorizers finish before other services start" (ts_order) = start,end,start,end
@test "authorizers go first" (string match -q '*/group/z-authorizers *' -- (cat $TS_ORDER_LOG)[1]; echo $status) -eq 0
rm -rf $TS_ROOT/group/z-authorizers

# ===== per-target logs under $XDG_RUNTIME_DIR/ts_push/latest =====
push hotels flights </dev/null >/dev/null 2>&1
set -l logs $XDG_RUNTIME_DIR/ts_push/latest/*.log
@test "one log file per target" (count $logs) -eq 2
@test "log file holds the deploy output" (string match -q '*sls*deploy*' -- (cat $logs[1]); echo $status) -eq 0

# ===== failure inside a parallel tier: retry re-runs only that target =====
echo -n >$TS_SLS_LOG
echo '*/flights *' >$TS_FAIL_FLAG
printf 'r\n' | push hotels flights >/dev/null 2>&1
@test "retry after a parallel failure makes 3 sls calls" (count (cat $TS_SLS_LOG)) -eq 3
@test "the retried call is the failed target" (string match -q '*/flights *' -- (cat $TS_SLS_LOG)[-1]; echo $status) -eq 0
echo -n >$TS_FAIL_FLAG
set -e TS_SLS_SLEEP

# --- teardown ------------------------------------------------------------
cd $repo
rm -rf $TS_ROOT
rm -f $TS_SLS_LOG $TS_FAKE_EDITOR $TS_FAIL_FLAG $TS_INT_FLAG $TS_NOTIFY_LOG $TS_RENAME_LOG $TS_ORDER_LOG
