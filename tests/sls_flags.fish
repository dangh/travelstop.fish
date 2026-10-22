# fishtape spec guarding _ts_sls's flag parsing against the serverless CLI's
# short flags. Regression for the `-c/--config` collision: fish argparse derives
# an implicit short flag from a long option's first char AND matches short flags
# case-insensitively, so the old `C/cwd=` silently swallowed serverless's
# `-c serverless-waf.yml`, using the config file name as both the cwd and the
# npm install target. See conf.d/travelstop.fish `_ts_sls`.
#
# Run: fishtape tests/sls_flags.fish < /dev/null
#
# Real code under test: _ts_sls. We source just its definition (conf.d exits when
# non-interactive) and stub only its side-effect helpers. A fake sls binary
# records its PWD + argv so we can assert what actually reached serverless.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

# source only the _ts_sls definition; the file's guarded `exit` forbids sourcing
# it whole in a non-interactive shell. Its inner `end`s are indented, so `^end$`
# matches only the function's closer.
awk '/^function _ts_sls/,/^end$/' $repo/conf.d/travelstop.fish | source

# --- stub _ts_sls's helpers ----------------------------------------------
function _ts_log; end
function green; echo $argv; end
function _ts_env; end # --with-env then appends nothing

# --- fake serverless install in a real working dir -----------------------
set -g WD (mktemp -d)
mkdir -p $WD/node_modules/.bin
printf '{"dependencies":{"serverless":"3"}}' >$WD/package.json
set -g SLS_LOG (mktemp)
echo '#!/usr/bin/env fish
echo "PWD=$PWD" >>'$SLS_LOG'
echo "ARGV=$argv" >>'$SLS_LOG'
echo "AWSPROFILE=$AWS_PROFILE" >>'$SLS_LOG >$WD/node_modules/.bin/sls
chmod +x $WD/node_modules/.bin/sls

set -g _ts_project_dir TS_PD
set -g TS_PD $WD

echo -n >$SLS_LOG
_ts_sls --workdir $WD --with-env deploy --conceal -s prod -r us-east-1 -c serverless-waf.yml

@test "runs from the --workdir dir, not the config file name" (string match -q "PWD=*$WD*" -- (cat $SLS_LOG)[1]; echo $status) -eq 0
@test "-c config flag reaches the sls binary" (string match -q '*-c serverless-waf.yml*' -- (cat $SLS_LOG); echo $status) -eq 0
@test "internal --workdir is not forwarded to sls" (string match -q '*--workdir*' -- (cat $SLS_LOG); echo $status) -eq 1
@test "internal --with-env is not forwarded to sls" (string match -q '*--with-env*' -- (cat $SLS_LOG); echo $status) -eq 1

# --- env-key mode: --aws-profile stripped, AWS_PROFILE hidden from child ---
# granted `assume -x` puts creds in the env; serverless must auth from them, not
# a named profile (which reads/writes ~/.aws/credentials on disk).
set -gx AWS_ACCESS_KEY_ID AKIAENVKEY
set -gx AWS_PROFILE PROD
echo -n >$SLS_LOG
_ts_sls --workdir $WD --with-env deploy -s prod -r us-east-1 --aws-profile PROD -c serverless-waf.yml
@test "env-key strips --aws-profile from sls args" (string match -q '*--aws-profile*' -- (cat $SLS_LOG); echo $status) -eq 1
@test "env-key keeps other flags (-c reaches sls)" (string match -q '*-c serverless-waf.yml*' -- (cat $SLS_LOG); echo $status) -eq 0
@test "env-key hides AWS_PROFILE from the sls child" (string match -q 'AWSPROFILE=' -- (cat $SLS_LOG); echo $status) -eq 0
set -e AWS_ACCESS_KEY_ID
set -e AWS_PROFILE

# --- teardown ------------------------------------------------------------
rm -rf $WD
rm -f $SLS_LOG
