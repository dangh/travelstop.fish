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

# source only the _ts_sls definition (lines 226-282); the file's guarded `exit`
# forbids sourcing it whole in a non-interactive shell.
source (sed -n '226,282p' $repo/conf.d/travelstop.fish | psub)

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
echo "ARGV=$argv" >>'$SLS_LOG >$WD/node_modules/.bin/sls
chmod +x $WD/node_modules/.bin/sls

set -g _ts_project_dir TS_PD
set -g TS_PD $WD

echo -n >$SLS_LOG
_ts_sls --workdir $WD --with-env deploy --conceal -s prod -r us-east-1 -c serverless-waf.yml

@test "runs from the --workdir dir, not the config file name" (string match -q "PWD=*$WD*" -- (cat $SLS_LOG)[1]; echo $status) -eq 0
@test "-c config flag reaches the sls binary" (string match -q '*-c serverless-waf.yml*' -- (cat $SLS_LOG); echo $status) -eq 0
@test "internal --workdir is not forwarded to sls" (string match -q '*--workdir*' -- (cat $SLS_LOG); echo $status) -eq 1
@test "internal --with-env is not forwarded to sls" (string match -q '*--with-env*' -- (cat $SLS_LOG); echo $status) -eq 1

# --- teardown ------------------------------------------------------------
rm -rf $WD
rm -f $SLS_LOG
