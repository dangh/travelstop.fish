# Run: fish -c 'fishtape tests/logs_awscli.fish' < /dev/null
set -l repo (path dirname (path dirname (status filename)))
source $repo/functions/logs_awscli.fish
function _ts_ensure_session
    printf '%s' "$HTTPS_PROXY" >$TS_LOGS_TMP/session-env
    return 0
end
function _ts_log; echo $argv >&2; end
function red; echo $argv; end
function _ts_service_name
    echo called >$TS_LOGS_TMP/serverless-called
    return 99
end
function _ts_sls; return 99; end
functions -e parse_logs ts_styles ts_env
set -l original_pwd $PWD
set -g TS_LOGS_TMP (mktemp -d)
set -l project $TS_LOGS_TMP/project
mkdir -p $project/services/users/groups $project/anything/users/groups $project/services/orders $project/services/categories/items
mkdir -p $project/backend/services/users/groups
git -C $project init -q
cd $project/services/orders
mkdir $TS_LOGS_TMP/functions
ln -s $repo/functions/logs.awk $TS_LOGS_TMP/functions/logs.awk
set -l __fish_config_dir $TS_LOGS_TMP
set -gx TS_AWS_LOG $TS_LOGS_TMP/args
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$@" > "$TS_AWS_LOG"' 'printf "%s" "$HTTPS_PROXY" > "$TS_AWS_LOG.env"' 'case " $* " in *" --format raw "*) echo "invalid format: raw" >&2; exit 2;; esac' 'printf "%s\n" "2026-09-10T12:34:56 ${TS_AWS_MESSAGE:-log message}" "  continuation line"' 'exit "${TS_AWS_EXIT:-0}"' >$TS_LOGS_TMP/aws
touch $TS_AWS_LOG.env
chmod +x $TS_LOGS_TMP/aws
set -lx PATH $TS_LOGS_TMP $PATH
set -gx AWS_PROFILE acme@DEV
set -gx AWS_REGION us-east-1
set -e ts_default_argv_logs
set -g ts_env HTTPS_PROXY=http://proxy:8888
function _run
    echo -n >$TS_AWS_LOG
    logs_awscli $argv >/dev/null
    string join ' ' < $TS_AWS_LOG
end

logs_awscli myFn --filter 'ERROR warning' >/dev/null 2>$TS_LOGS_TMP/debug
set -l debug (string collect <$TS_LOGS_TMP/debug)
@test "prints copyable AWS command to stderr" "$debug" = "aws logs tail /aws/lambda/orders-dev-myFn --format short --color off --since 2m --profile acme@DEV --region us-east-1 --filter-pattern 'ERROR warning'"
@test "debug command does not expose ts_env" (string match -q '*proxy:8888*' -- "$debug"; echo $status) -eq 1

set -l output (logs_awscli myFn)
@test "short timestamp removed before formatting" "$output[1]" = 'log message'
@test "multiline message remains intact" "$output[2]" = '  continuation line'

set -l c (_run myFn)
@test "AWS tail uses service-stage-function group" "$c" = 'logs tail /aws/lambda/orders-dev-myFn --format short --color off --since 2m --profile acme@DEV --region us-east-1'
@test "ts_env reaches session check" (string collect <$TS_LOGS_TMP/session-env) = http://proxy:8888
@test "ts_env reaches AWS" (string collect < $TS_AWS_LOG.env) = http://proxy:8888
set -l c (_run --function explicit ignored --aws-profile other@PROD -r eu-west-1 -t --filter 'ERROR warning' --startTime 1h)
@test "overrides and filter are translated" "$c" = 'logs tail /aws/lambda/orders-prod-explicit --format short --color off --since 1h --profile other@PROD --region eu-west-1 --follow --filter-pattern ERROR warning'
@test "filter stays one argument" (count (cat $TS_AWS_LOG)) -eq 16
set -l c (_run myFn -s test --startTime 20260910T123456)
@test "compact UTC timestamp becomes ISO" (string match -q '*--since 2026-09-10T12:34:56Z*' -- "$c"; echo $status) -eq 0
set -l c (_run --log-group /custom/logs)
@test "explicit group needs no function" (string match -q 'logs tail /custom/logs *' -- "$c"; echo $status) -eq 0
set -l c (_run myFn -c custom.yml --app legacy --org legacy)
@test "legacy config does not trigger a Serverless lookup" (test -e $TS_LOGS_TMP/serverless-called; echo $status) -eq 1
cd $project/services/users/groups
set -l c (_run create)
@test "nested path resolves user-groups-dev-create" (string split ' ' -- "$c")[3] = /aws/lambda/user-groups-dev-create
cd $project/anything/users/groups
logs_awscli create >/dev/null 2>&1
@test "path without services cannot infer a service" $status -ne 0
cd $project/backend/services/users/groups
set -l c (_run create -s prod)
@test "named services boundary can be nested" (string split ' ' -- "$c")[3] = /aws/lambda/user-groups-prod-create
cd $project/services/categories/items
set -l c (_run list)
@test "parent ies becomes y and leaf stays plural" (string split ' ' -- "$c")[3] = /aws/lambda/category-items-dev-list
cd $project
logs_awscli create >/dev/null 2>&1
@test "git root cannot infer a service" $status -ne 0
cd $project/services
logs_awscli create >/dev/null 2>&1
@test "container directory cannot infer a service" $status -ne 0
cd $TS_LOGS_TMP
logs_awscli create >/dev/null 2>&1
@test "outside Git cannot infer a service" $status -ne 0
set -l c (_run --log-group /custom/outside)
@test "explicit group works outside Git" (string split ' ' -- "$c")[3] = /custom/outside
cd $project/services/orders
set -l saved_proxy "$HTTPS_PROXY"
set -g ts_env HTTPS_PROXY=http://proxy:8888 NO_COLOR=1 'ts_blank_page=custom blank page' 'TS_AWS_MESSAGE=START RequestId: test'
set -l styled (logs_awscli myFn | string collect)
@test "ts_env reaches real AWK formatter" (string match -q '*custom blank page*' -- "$styled"; echo $status) -eq 0
@test "ts_env does not leak to caller" "$HTTPS_PROXY" = "$saved_proxy"
set -g ts_env HTTPS_PROXY=http://proxy:8888
function ts_env; echo HTTPS_PROXY=http://dynamic:8888; end
set -l c (_run myFn)
@test "dynamic ts_env reaches session check" (string collect <$TS_LOGS_TMP/session-env) = http://dynamic:8888
@test "dynamic ts_env wins over variable" (cat $TS_AWS_LOG.env) = http://dynamic:8888
functions -e ts_env
mkdir -p $TS_LOGS_TMP/parser-config/fish/functions
printf '%s\n' 'function parse_logs' '    echo "parser proxy: $HTTPS_PROXY"' '    cat' 'end' >$TS_LOGS_TMP/parser-config/fish/functions/parse_logs.fish
function parse_logs; end
set -g ts_env HTTPS_PROXY=http://parser:8888 XDG_CONFIG_HOME=$TS_LOGS_TMP/parser-config
set -l parsed (logs_awscli myFn)
@test "ts_env reaches optional parse_logs process" "$parsed[1]" = 'parser proxy: http://parser:8888'
@test "parser still receives stripped log messages" "$parsed[2]" = 'log message'
functions -e parse_logs
set -g ts_env HTTPS_PROXY=http://proxy:8888
set -l c (_run myFn --startTime 2026-09-10T12:34:56Z)
@test "ISO timestamps pass through" (string match -q '*--since 2026-09-10T12:34:56Z*' -- "$c"; echo $status) -eq 0
set -g ts_default_argv_logs --tail --startTime=5m
set -l c (_run myFn --startTime=30m)
@test "user time overrides defaults" (string match -q '*--since 30m*--follow*' -- "$c"; echo $status) -eq 0
set -e ts_default_argv_logs
logs_awscli >/dev/null 2>&1
@test "missing function fails" $status -ne 0
logs_awscli -- -invalid >/dev/null 2>&1
@test "invalid function fails" $status -ne 0
logs_awscli myFn -i 5 >/dev/null 2>&1
@test "unsupported interval fails" $status -ne 0
set -gx TS_AWS_EXIT 42
logs_awscli myFn >/dev/null
@test "AWS failure survives formatting pipeline" $status -eq 42
set -e TS_AWS_EXIT
function _ts_ensure_session; return 1; end
echo -n >$TS_AWS_LOG
logs_awscli myFn >/dev/null 2>$TS_LOGS_TMP/debug
@test "session failure aborts" $status -ne 0
@test "command is printed even when session check fails" (string match -q 'aws logs tail *' -- (cat $TS_LOGS_TMP/debug); echo $status) -eq 0
@test "session failure makes no AWS call" (test -s $TS_AWS_LOG; echo $status) -eq 1
set -lx NO_COLOR 1
set -l formatted (printf '%s\n' '2026-09-10T12:34:56.000Z\t12345678-1234-1234-1234-123456789abc\tINFO\t[DEV][2026-09-10T12:34:56.000Z][test.js:1][INFO]: hello' | string unescape | awk -f $repo/functions/logs.awk | string collect)
@test "raw Lambda timestamp is stripped for metadata formatting" (string match -q '*[DEV]*hello*' -- "$formatted"; echo $status) -eq 0
@test "raw Lambda request id is stripped" (string match -q '*12345678-1234*' -- "$formatted"; echo $status) -eq 1
cd $original_pwd
rm -rf $TS_LOGS_TMP
