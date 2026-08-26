# fishtape spec for `_ts_env` (conf.d/travelstop.fish).
# Run: fishtape tests/ts_env.fish < /dev/null
#
# Code under test: _ts_env. It emits the environment pairs that `sls --with-env`
# injects. A user-defined `ts_env` FUNCTION wins if present (dynamic pairs, e.g.
# a per-AWS-profile proxy); otherwise the `ts_env` VARIABLE is the fallback.
# Each pair is one KEY=value entry; values are `string escape`d. --mode=env emits
# `KEY=value`, --mode=awk emits `-v KEY=value`.
#
# conf.d/travelstop.fish ends with `status is-interactive || exit`, so we can't
# source it in a non-interactive test. Extract just the `_ts_env` definition.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -l conf $repo/conf.d/travelstop.fish

source (awk '/^function _ts_env$/{p=1} p{print} p&&/^end$/{exit}' $conf | psub)

# clean slate: no function, no var
functions -e ts_env 2>/dev/null
set -e ts_env

# ===== variable fallback =================================================
set -g ts_env SLS_DEPRECATION_DISABLE='*'
set -l out (_ts_env --mode=env)
@test "var: pair is emitted" "$out" = "SLS_DEPRECATION_DISABLE='*'"

set -g ts_env HTTPS_PROXY=http://localhost:8888 SLS_DEPRECATION_DISABLE='*'
set out (_ts_env --mode=env)
@test "var: multiple pairs, order preserved" "$out" = "HTTPS_PROXY=http://localhost:8888 SLS_DEPRECATION_DISABLE='*'"

# ===== awk mode ==========================================================
set -g ts_env FOO=bar
set out (_ts_env --mode=awk)
@test "awk mode prefixes -v" "$out" = "-v FOO=bar"

# ===== function wins over variable =======================================
set -g ts_env FROM_VAR=1
function ts_env; echo FROM_FUNC=1; end
set out (_ts_env --mode=env)
@test "func wins: uses function output" "$out" = "FROM_FUNC=1"
@test "func wins: variable is ignored" (string match -q '*FROM_VAR*' -- $out; echo $status) -eq 1

# ===== function computes pairs dynamically (per AWS profile) =============
function ts_env
    switch "$AWS_PROFILE"
        case '*@prod'
            echo HTTPS_PROXY=http://localhost:9999
        case '*'
            echo HTTPS_PROXY=http://localhost:8888
    end
end
set -gx AWS_PROFILE acme@prod
set out (_ts_env --mode=env)
@test "func: prod profile proxy" "$out" = "HTTPS_PROXY=http://localhost:9999"
set -gx AWS_PROFILE acme@dev
set out (_ts_env --mode=env)
@test "func: dev profile proxy" "$out" = "HTTPS_PROXY=http://localhost:8888"

# a function may emit several pairs, one per line
function ts_env
    echo HTTPS_PROXY=http://localhost:8888
    echo SLS_DEPRECATION_DISABLE='*'
end
set out (_ts_env --mode=env)
@test "func: multi-line pairs" "$out" = "HTTPS_PROXY=http://localhost:8888 SLS_DEPRECATION_DISABLE='*'"

# ===== empty: neither function nor variable ==============================
functions -e ts_env
set -e ts_env
set out (_ts_env --mode=env)
@test "empty: nothing set yields empty output" -z "$out"
