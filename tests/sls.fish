# fishtape spec for the `sls` wrapper (functions/sls.fish).
# Run: fishtape tests/sls.fish < /dev/null
#
# Real code under test: the `sls` function's ARGUMENT CONSTRUCTION -- how it
# derives the stage from $AWS_PROFILE (acme@dev -> dev), forwards profile/region,
# lets explicit -s/--stage, -r/--region, --aws-profile override the defaults,
# applies the serverless.yml `region:` override, threads user flags through, and
# routes help/version/empty invocations straight to the CLI without injection.
#
# Only the final exec is stubbed: `_ts_sls` is shadowed to append its argv to a
# log file, so no real serverless/npm/network runs. Fixtures under
# tests/fixtures/sls/ are read-only (never mutated). The sls function reads
# `serverless.yml` from $PWD, so each case cd's into the relevant fixture dir.
#
# Not observable here (skipped): the interactive prod-confirm "Y" path needs a
# typed "y" on stdin, which fishtape runs with </dev/null; we only assert the
# decline/abort side of that branch.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -g TS_SLS_FIX $here/fixtures/sls

source $repo/functions/sls.fish

# --- stub only the final exec --------------------------------------------
set -g LOG (mktemp)
function _ts_sls; echo "$argv" >>$LOG; return 0; end

# helper: clear the log, run sls, return the single captured command line
function _run --inherit-variable LOG
    echo -n >$LOG
    sls $argv </dev/null >/dev/null 2>&1
    cat $LOG
end

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1

# noregion/serverless.yml has no `region:` line, so $AWS_REGION is forwarded.
cd $TS_SLS_FIX/noregion

# ===== stage derived from AWS_PROFILE (acme@dev -> dev) ==================
# The command line is exec'd as `_ts_sls -E <subcommand> ...`, so the captured
# log line is `-E deploy --aws-profile ... --stage ... -r ...`.
set -l out (_run deploy)
@test "exec is invoked with -E then the subcommand" (string match -q -- '-E deploy *' $out; echo $status) -eq 0
@test "stage is derived from AWS_PROFILE" (string match -q -- '*--stage dev*' $out; echo $status) -eq 0
@test "profile is forwarded from AWS_PROFILE" (string match -q -- '*--aws-profile acme@dev*' $out; echo $status) -eq 0
@test "region is forwarded from AWS_REGION" (string match -q -- '*-r us-east-1*' $out; echo $status) -eq 0

# ===== user flags pass through unchanged =================================
set -l out (_run deploy --force)
@test "unknown user flag is passed through" (string match -q -- '*deploy --force *' $out; echo $status) -eq 0
@test "injected flags still present alongside user flag" (string match -q -- '*--stage dev*' $out; echo $status) -eq 0

# ===== a different subcommand keeps the same injection ===================
set -l out (_run info)
@test "info subcommand keeps stage/profile/region injection" (string match -q -- '-E info --aws-profile acme@dev --stage dev -r us-east-1*' $out; echo $status) -eq 0

# ===== explicit overrides win ============================================
set -l out (_run deploy --stage staging)
@test "--stage overrides the derived stage" (string match -q -- '*--stage staging*' $out; echo $status) -eq 0
@test "--stage override removes the flag from positionals" (not string match -q -- '*--stage dev*' $out; echo $status) -eq 0

set -l out (_run deploy -s qa)
@test "-s overrides the derived stage" (string match -q -- '*--stage qa*' $out; echo $status) -eq 0

set -l out (_run deploy -r eu-west-1)
@test "-r overrides the region" (string match -q -- '*-r eu-west-1*' $out; echo $status) -eq 0
@test "-r override drops the AWS_REGION default" (not string match -q -- '*us-east-1*' $out; echo $status) -eq 0

set -l out (_run deploy --region ap-southeast-1)
@test "--region overrides the region" (string match -q -- '*-r ap-southeast-1*' $out; echo $status) -eq 0

set -l out (_run deploy --aws-profile other@qa)
@test "--aws-profile overrides the forwarded profile" (string match -q -- '*--aws-profile other@qa*' $out; echo $status) -eq 0
# stage is derived once from the *original* AWS_PROFILE, not the overriding one.
@test "--aws-profile override does not re-derive the stage" (string match -q -- '*--stage dev*' $out; echo $status) -eq 0

# ===== --data writes a temp file and appends -p =========================
set -l out (_run invoke -d '{"k":1}')
@test "-d appends a -p <path> pair" (string match -q -- '*-p /*sls-data-*' $out; echo $status) -eq 0

# ===== passthrough: help / version / empty (no flag injection) ==========
set -l out (_run --version)
@test "--version passes through verbatim" (test "$out" = "--version"; echo $status) -eq 0
@test "--version does not inject --stage" (not string match -q -- '*--stage*' $out; echo $status) -eq 0

set -l out (_run help)
@test "help passes through without injection" (not string match -q -- '*--aws-profile*' $out; echo $status) -eq 0

# empty invocation: _ts_sls is called with no args -> a single blank log line.
echo -n >$LOG
sls </dev/null >/dev/null 2>&1
@test "empty invocation injects nothing" (string match -q -- '*--stage*' (cat $LOG); echo $status) -eq 1

# ===== serverless.yml region: overrides AWS_REGION ======================
# withregion/serverless.yml pins region: 'ap-south-1'.
cd $TS_SLS_FIX/withregion
set -l out (_run deploy)
@test "yml region: overrides AWS_REGION" (string match -q -- '*-r ap-south-1*' $out; echo $status) -eq 0
@test "yml region override drops AWS_REGION value" (not string match -q -- '*us-east-1*' $out; echo $status) -eq 0
# The yml region: line is applied AFTER the -r flag (sls.fish lines 29 vs 33-34),
# so the yml region wins even over an explicit -r when a region: is present.
set -l out (_run deploy -r us-west-2)
@test "yml region: is applied after -r and wins over it" (string match -q -- '*-r ap-south-1*' $out; echo $status) -eq 0
@test "explicit -r is discarded when yml has a region:" (not string match -q -- '*us-west-2*' $out; echo $status) -eq 0

# ===== prod deploy aborts when confirmation is declined (stdin EOF) =====
cd $TS_SLS_FIX/noregion
set -gx AWS_PROFILE acme@prod
echo -n >$LOG
sls deploy </dev/null >/dev/null 2>&1
@test "prod deploy with no confirmation does not exec" (count (string match -v -- '' (cat $LOG))) -eq 0
# a non-deploy/invoke subcommand on prod still runs (no confirmation gate).
set -l out (_run info)
@test "prod info runs without a confirmation gate" (string match -q '*--stage prod*' -- $out; echo $status) -eq 0
set -gx AWS_PROFILE acme@dev

# --- teardown ------------------------------------------------------------
cd $repo
rm -f $LOG
