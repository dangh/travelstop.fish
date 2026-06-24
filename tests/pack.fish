# fishtape spec for pack (functions/pack.fish).
# Run: fishtape tests/pack.fish < /dev/null
#
# Real code under test: pack — it derives stage from $AWS_PROFILE (acme@dev->dev),
# region from $AWS_REGION, profile from $AWS_PROFILE, resolves the serverless.yml,
# and builds the `package` subcommand + flags handed to serverless.
#
# We intercept the FINAL serverless invocation by shadowing _ts_sls so its full
# argv is logged; pack calls `_ts_sls -C "$working_dir" -E $package_cmd`. Asserting
# on that log verifies the argument construction without any real sls/npm/network.
# Only side-effects are stubbed (_ts_log, colors, _ts_sls). No fixture is mutated.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -g TS_FIX $here/fixtures/pack

source $repo/functions/pack.fish
# _ts_validate_path (used in the invalid-config branch) lives in conf.d; the
# file's trailing `exit` forbids sourcing it whole, so source just that slice.
source (sed -n '140,177p' $repo/conf.d/travelstop.fish | psub)

# --- stub only external side-effects -------------------------------------
function _ts_log; echo $argv; end
for c in magenta yellow blue green red dim ansi-escape
    function $c; echo $argv; end
end
set -g TS_SLS_LOG (mktemp)
function _ts_sls; echo "$argv" >>$TS_SLS_LOG; return 0; end

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -e ts_default_argv_pack
set -g _ts_project_dir TS_PD
set -g TS_PD $TS_FIX
cd $TS_FIX/svc

# helper: run pack and return the logged _ts_sls argv as one string
function _run
    echo -n >$TS_SLS_LOG
    pack $argv >/dev/null 2>&1
    cat $TS_SLS_LOG
end

# ===== happy path: stage derived from AWS_PROFILE, region/profile injected =====
set -l line (_run)
@test "pack invokes the package subcommand" (string match -q '* package *' -- "$line"; echo $status) -eq 0
@test "pack injects -s with stage from AWS_PROFILE (acme@dev -> dev)" (string match -q '* -s dev *' -- "$line"; echo $status) -eq 0
@test "pack injects --aws-profile from AWS_PROFILE" (string match -q '* --aws-profile acme@dev *' -- "$line"; echo $status) -eq 0
@test "pack injects -r with region from AWS_REGION" (string match -q '* -r us-east-1*' -- "$line"; echo $status) -eq 0
@test "pack runs with -C cwd pointing at the working dir" (string match -q "*-C $TS_FIX/svc*" -- "$line"; echo $status) -eq 0
@test "pack does not inject -p when no package flag given" (string match -q '* -p *' -- "$line"; echo $status) -eq 1
@test "pack does not inject -c for plain serverless.yml" (string match -q '* -c *' -- "$line"; echo $status) -eq 1

# ===== -p/--package flag is injected =====
set -l line (_run -p .artifacts)
@test "pack -p injects -p with the package dir" (string match -q '* -p .artifacts*' -- "$line"; echo $status) -eq 0

# ===== explicit flags override the AWS_PROFILE/AWS_REGION derivation =====
set -l line (_run -s prod)
@test "explicit -s overrides derived stage" (string match -q '* -s prod *' -- "$line"; echo $status) -eq 0
@test "explicit -s replaces (not appends) the derived stage" (string match -q '* -s dev *' -- "$line"; echo $status) -eq 1

set -l line (_run -r eu-west-1)
@test "explicit -r overrides AWS_REGION" (string match -q '* -r eu-west-1*' -- "$line"; echo $status) -eq 0
@test "explicit -r replaces the derived region" (string match -q '* -r us-east-1 *' -- "$line"; echo $status) -eq 1

set -l line (_run --aws-profile other@staging)
@test "explicit --aws-profile overrides AWS_PROFILE" (string match -q '* --aws-profile other@staging *' -- "$line"; echo $status) -eq 0
@test "explicit --aws-profile leaves stage derived from AWS_PROFILE" (string match -q '* -s dev *' -- "$line"; echo $status) -eq 0

# ===== --verbose / --app / --org pass-through =====
set -l line (_run --verbose)
@test "--verbose is forwarded" (string match -q '* --verbose*' -- "$line"; echo $status) -eq 0

set -l line (_run --app myapp --org myorg)
@test "--app is forwarded" (string match -q '* --app myapp *' -- "$line"; echo $status) -eq 0
@test "--org is forwarded" (string match -q '* --org myorg*' -- "$line"; echo $status) -eq 0

# ===== alternate config basename triggers -c <basename> =====
set -l line (_run -c serverless.staging.yml)
@test "-c with non-default basename injects -c <basename>" (string match -q '* -c serverless.staging.yml*' -- "$line"; echo $status) -eq 0

# ===== positional config arg: a directory resolves to its serverless.yml =====
cd $TS_FIX
set -l line (_run svc)
@test "positional dir arg resolves to its serverless.yml (-C working dir)" (string match -q "*-C $TS_FIX/svc*" -- "$line"; echo $status) -eq 0
cd $TS_FIX/svc

# ===== invalid config: missing serverless.yml errors, does not invoke sls =====
echo -n >$TS_SLS_LOG
set -l out (pack /no/such/place.yml 2>&1)
set -l code $status
@test "missing config exits non-zero" $code -ne 0
@test "missing config logs invalid serverless config" (string match -q '*invalid serverless config*' -- "$out"; echo $status) -eq 0
@test "missing config never invokes _ts_sls" (count (string match -v '' -- (cat $TS_SLS_LOG))) -eq 0

# NOTE skipped/unobservable: AWS_PROFILE without an `@` (e.g. plain "dev") — the
# string replace leaves it unchanged so stage==profile; covered implicitly. The
# empty-profile branch (skips --aws-profile/-s) is not exercised here because the
# test environment always sets AWS_PROFILE/AWS_REGION.

# --- teardown ------------------------------------------------------------
cd $repo
rm -f $TS_SLS_LOG
