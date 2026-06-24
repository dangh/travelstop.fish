# fishtape spec for `logs` (functions/logs.fish).
# Run: fish -c 'fishtape tests/logs.fish' < /dev/null
#
# Code under test: the real `logs` function, end-to-end through argparse and the
# `logs_cmd` argument-construction block (lines 43-54). We intercept the only
# external side effect, `_ts_sls`, by shadowing it to record its full argv to a
# log file and emit nothing on stdout. Because it emits nothing, the downstream
# `command env … awk -f logs.awk` pipeline (which is real, not stubbed) just
# reads empty input and exits, so no network/serverless ever runs.
#
# We assert on the argument vector serverless is invoked with: the `logs`
# subcommand and the injected -f/--aws-profile/-s/-r/--startTime flags, the
# optional -t (tail) flag, pass-throughs (--filter/-i/--app/--org/-c), the
# defaults derived from $AWS_PROFILE/$AWS_REGION, and that explicit overrides win.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/logs.fish

# --- stub only external side effects -------------------------------------
function _ts_log; echo $argv; end
for c in red dim
    function $c; echo $argv; end
end
# Record serverless argv; emit nothing so the real awk pipeline is a no-op.
set -g TS_SLS_LOG (mktemp)
function _ts_sls; echo "$argv" >>$TS_SLS_LOG; return 0; end
# Make sure the optional pre-pipeline helpers are absent so neither
# parse_logs nor ts_styles can run; the function falls back to the awk-only
# branch, which still records via _ts_sls above.
functions -e parse_logs ts_styles 2>/dev/null

# Default environment-derived inputs.
set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -e ts_default_argv_logs

# helper: run logs, return the recorded serverless argv line
function _run
    echo -n >$TS_SLS_LOG
    logs $argv >/dev/null 2>&1
    cat $TS_SLS_LOG
end

# ===== defaults: function from positional, stage/region/startTime derived =====
set -l c (_run myFn)
@test "logs: invokes _ts_sls with -E + logs subcommand" (string match -q -- '-E logs *' "$c"; echo $status) -eq 0
@test "logs: injects -f <function> from positional" (string match -q '* -f myFn *' -- "$c"; echo $status) -eq 0
@test "logs: forwards --aws-profile from \$AWS_PROFILE" (string match -q '* --aws-profile acme@dev *' -- "$c"; echo $status) -eq 0
@test "logs: stage defaults to lowercased part after @ (dev)" (string match -q '* -s dev *' -- "$c"; echo $status) -eq 0
@test "logs: region defaults to \$AWS_REGION" (string match -q '* -r us-east-1 *' -- "$c"; echo $status) -eq 0
@test "logs: startTime defaults to 2m" (string match -q '* --startTime 2m*' -- "$c"; echo $status) -eq 0
@test "logs: no -t flag when tail not requested" (string match -q '* -t *' -- "$c"; echo $status) -eq 1

# ===== --function flag overrides positional ====================================
set -l c (_run --function explicitFn ignoredPositional)
@test "logs: --function wins over positional" (string match -q '* -f explicitFn *' -- "$c"; echo $status) -eq 0
@test "logs: positional not used when --function given" (string match -q '* -f ignoredPositional *' -- "$c"; echo $status) -eq 1

# ===== explicit stage / region overrides win ===================================
set -l c (_run -s prod -r eu-west-1 myFn)
@test "logs: -s override wins over derived stage" (string match -q '* -s prod *' -- "$c"; echo $status) -eq 0
@test "logs: -r override wins over \$AWS_REGION" (string match -q '* -r eu-west-1 *' -- "$c"; echo $status) -eq 0

# ===== --aws-profile override flows through ====================================
set -l c (_run --aws-profile other@stg myFn)
@test "logs: --aws-profile override is forwarded" (string match -q '* --aws-profile other@stg *' -- "$c"; echo $status) -eq 0

# ===== startTime override ======================================================
set -l c (_run --startTime 1h myFn)
@test "logs: --startTime override wins over 2m default" (string match -q '* --startTime 1h*' -- "$c"; echo $status) -eq 0
@test "logs: default 2m absent when --startTime overridden" (string match -q '* --startTime 2m*' -- "$c"; echo $status) -eq 1

# ===== tail flag ===============================================================
set -l c (_run -t myFn)
@test "logs: -t appended when tail requested" (string match -q '* -t *' -- "$c"; echo $status) -eq 0

# ===== pass-through flags: --filter / -i / --app / --org / -c ==================
set -l c (_run --filter ERROR -i 5 --app myapp --org myorg -c custom.yml myFn)
@test "logs: --filter passed through" (string match -q '* --filter ERROR *' -- "$c"; echo $status) -eq 0
@test "logs: -i (interval) passed through" (string match -q '* -i 5 *' -- "$c"; echo $status) -eq 0
@test "logs: --app passed through" (string match -q '* --app myapp *' -- "$c"; echo $status) -eq 0
@test "logs: --org passed through" (string match -q '* --org myorg *' -- "$c"; echo $status) -eq 0
@test "logs: -c (config) passed through" (string match -q '* -c custom.yml*' -- "$c"; echo $status) -eq 0

# ===== validation: missing function errors, no invocation ======================
echo -n >$TS_SLS_LOG
set -l out (logs 2>&1)
set -l code $status
@test "logs: missing function exits non-zero" $code -ne 0
@test "logs: missing function logs 'function is required'" (string match -q '*function is required*' -- "$out"; echo $status) -eq 0
@test "logs: missing function never invokes _ts_sls" (test -s $TS_SLS_LOG; echo $status) -eq 1

# ===== validation: a flag-looking function (positional starts with -) ==========
# A bare `-x` is consumed by argparse as unknown, so use `--` to force it
# positional and hit the `string match '-*'` guard.
echo -n >$TS_SLS_LOG
set -l out (logs -- -notaflag 2>&1)
set -l code $status
@test "logs: dash-leading function exits non-zero" $code -ne 0
@test "logs: dash-leading function reports invalid function" (string match -q '*invalid function*' -- "$out"; echo $status) -eq 0
@test "logs: dash-leading function never invokes _ts_sls" (test -s $TS_SLS_LOG; echo $status) -eq 1

# --- skipped (unobservable without a real serverless/awk run) ----------------
# - The choice between the parse_logs branch (line 61) and the awk-only branch
#   (line 63) and the actual stdout formatting: stubbing _ts_sls to emit nothing
#   makes the pipeline a no-op by design; we assert argv, not rendered output.
# - The `set type` line (30) reads a non-existent `_flag_type` (no t/type option
#   in argparse, `t` is tail), so it is dead and unobservable in logs_cmd.

# --- teardown ------------------------------------------------------------
rm -f $TS_SLS_LOG
