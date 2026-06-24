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
set -g TS_ROOT $here/fixtures/project

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
function _ts_notify; end
function _ts_progress; end
set -g TS_SLS_LOG (mktemp)
function _ts_sls; echo "$argv" >>$TS_SLS_LOG; return 0; end

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

# ===== regression: unresolvable target must not crash =====
# previously: empty _ts_resolve_config output left target_type as 0 elements ->
# `set -a {$target_type}s ...` failed with "invalid variable name".
# Run from a dir without serverless.yml so the $PWD fallback can't resolve it.
cd $here/fixtures/empty
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

# --- teardown ------------------------------------------------------------
cd $repo
rm -f $TS_SLS_LOG
