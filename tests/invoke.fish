# fishtape spec for the real `invoke` function (functions/invoke.fish).
# Run: fishtape tests/invoke.fish < /dev/null
#
# Code under test: invoke. It builds a `serverless invoke` argv and hands it to
# `_ts_sls -E ...`, then calls `logs`. We intercept the serverless invocation by
# shadowing `_ts_sls` (logs argv to a file) and stub the other side-effects
# (`logs`, `push`, `_ts_log`, colors). Nothing real runs; no network.
#
# We assert ARGUMENT CONSTRUCTION across observable branches:
#   - the `invoke` subcommand is first
#   - injected -f/--function, --aws-profile, -s/--stage (dev), -r/--region
#   - the -d/--data path: data is written to a temp file and passed via -p
#   - passthrough flags: -t/type, -q/qualifier, --log, --raw
#
# stage is derived from $AWS_PROFILE (acme@dev -> dev). region from $AWS_REGION.
# We run from a cwd with NO ./functions/<name>.js so the auto-push branch
# (invoke.fish:62-75) stays dormant; `push` is stubbed regardless. A dedicated
# fixture exercises the auto-push branch explicitly.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/invoke.fish

# --- stub only external side-effects -------------------------------------
function _ts_log; echo $argv; end
for c in red green yellow blue magenta dim ansi-escape
    function $c; echo $argv; end
end

set -g TS_SLS_LOG (mktemp)
# Intercept the serverless invocation: invoke calls `_ts_sls -E $invoke_cmd`.
function _ts_sls
    # drop the leading -E so the log holds the bare sls argv
    set -l a $argv
    test "$a[1]" = -E && set a $a[2..-1]
    string join \n -- $a >>$TS_SLS_LOG
end

set -g TS_PUSH_LOG (mktemp)
function push; string join \n -- $argv >>$TS_PUSH_LOG; end
function logs; end

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -e ts_default_argv_invoke

# Run from a clean temp dir: no ./functions/<name>.js -> auto-push dormant.
set -g SANDBOX (mktemp -d)
cd $SANDBOX

# helper: nth occurrence value after a flag in the captured sls argv
function _val_after
    set -l flag $argv[1]
    set -l lines (cat $TS_SLS_LOG)
    for i in (seq (count $lines))
        if test "$lines[$i]" = "$flag"
            echo $lines[(math $i + 1)]
            return 0
        end
    end
    return 1
end

# ===== plain invoke =====
echo -n >$TS_SLS_LOG
invoke myFn
set -l first (cat $TS_SLS_LOG)[1]
@test "plain: invoke subcommand is first" $first = invoke
@test "plain: -f carries the function" (_val_after -f) = myFn
@test "plain: stage derived from AWS_PROFILE is dev" (_val_after -s) = dev
@test "plain: region from AWS_REGION" (_val_after -r) = us-east-1
@test "plain: aws-profile is injected" (_val_after --aws-profile) = acme@dev
@test "plain: no stray -p (no data)" (string match -q -- '-p' (cat $TS_SLS_LOG); echo $status) -eq 1

# ===== explicit -f/--function flag overrides positional default =====
echo -n >$TS_SLS_LOG
invoke -f explicitFn
@test "flag -f overrides: function is explicitFn" (_val_after -f) = explicitFn

# ===== -s / -r overrides =====
echo -n >$TS_SLS_LOG
invoke myFn -s staging -r eu-west-1
@test "override: -s staging wins over derived dev" (_val_after -s) = staging
@test "override: -r eu-west-1 wins over env" (_val_after -r) = eu-west-1

# ===== data-passing path (-d) =====
# invoke writes $_flag_data to a mktemp file and appends `-p <file>`.
echo -n >$TS_SLS_LOG
invoke myFn -d '{"hello":"world"}'
set -l data_file (_val_after -p)
@test "data: a -p file path is injected" -n "$data_file"
@test "data: the temp file exists" -f "$data_file"
@test "data: temp file holds the json payload" (cat $data_file) = '{"hello":"world"}'
@test "data: -f still present alongside data" (_val_after -f) = myFn

# ===== explicit -p path passthrough (path branch) =====
echo -n >$TS_SLS_LOG
invoke myFn -p ./event.json
@test "path: explicit -p is forwarded" (_val_after -p) = ./event.json

# ===== passthrough flags: -t/type, -q/qualifier =====
echo -n >$TS_SLS_LOG
invoke myFn -t RequestResponse -q '$LATEST'
@test "type: -t value forwarded" (_val_after -t) = RequestResponse
@test "qualifier: -q value forwarded" (_val_after -q) = '$LATEST'

# ===== boolean flags: --log, --raw =====
echo -n >$TS_SLS_LOG
invoke myFn -l --raw
@test "boolean: --log forwarded" (string match -q -- '--log' (cat $TS_SLS_LOG); echo $status) -eq 0
@test "boolean: --raw forwarded" (string match -q -- '--raw' (cat $TS_SLS_LOG); echo $status) -eq 0

# ===== error: missing function =====
echo -n >$TS_SLS_LOG
set -l out (invoke 2>&1)
set -l code $status
@test "missing fn: exits non-zero" $code -ne 0
@test "missing fn: complains function is required" (string match -q '*function is required*' -- "$out"; echo $status) -eq 0
@test "missing fn: no sls call made" (count (string match -e -r . -- (cat $TS_SLS_LOG))) -eq 0

# ===== error: function that looks like a flag =====
echo -n >$TS_SLS_LOG
set -l out (invoke -- -bogus 2>&1)
@test "bad fn: rejects leading-dash function" (string match -q '*invalid function*' -- "$out"; echo $status) -eq 0

# ===== auto-push branch (invoke.fish:62-75) =====
# Fires only when ./functions/<kebab-name>.js exists and its md5 changed.
# Fixture gives a getHotel -> functions/get-hotel.js file; push is stubbed so we
# only assert the push argv (function + --aws-profile/-s/-r) is constructed.
echo -n >$TS_PUSH_LOG
echo -n >$TS_SLS_LOG
cd $repo/tests/fixtures/invoke
# clear any cached md5 so the branch is guaranteed to trigger
set -l keyvar (string escape --style var -- getHotel)
set -e $keyvar
invoke getHotel
@test "auto-push: push was invoked with the function" (string match -q '*getHotel*' -- (cat $TS_PUSH_LOG); echo $status) -eq 0
@test "auto-push: push gets -s dev" (string match -q '*dev*' -- (cat $TS_PUSH_LOG); echo $status) -eq 0
@test "auto-push: invoke still issues the sls call" (string match -q '*invoke*' -- (cat $TS_SLS_LOG); echo $status) -eq 0

# NOTE (skipped, unobservable without a TTY): the prod-confirmation prompt
# (invoke.fish:31-41) calls `read -P`; under `< /dev/null` it cannot be driven
# deterministically, so it is intentionally not asserted here.

# --- teardown ------------------------------------------------------------
cd $repo
rm -rf $SANDBOX
rm -f $TS_SLS_LOG $TS_PUSH_LOG
