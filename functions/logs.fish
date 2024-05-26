function logs -d "watch lambda function logs"
    set -l function
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_DEFAULT_REGION
    set -l startTime 2m

    argparse -n 'sls logs' \
        'f/function=' \
        'aws-profile=' \
        's/stage=' \
        'r/region=' \
        t/tail \
        'startTime=' \
        'filter=' \
        'i/interval=' \
        'app=' \
        'org=' \
        'c/config=' \
        -- $ts_default_argv_logs $argv
    or return 1

    # function as the the first positional argument
    set -q argv[1] && set function $argv[1]

    set -q _flag_function && set function $_flag_function
    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set region $_flag_region
    set -q _flag_type && set type $_flag_type
    set -q _flag_startTime && set startTime $_flag_startTime

    if test -z "$function"
        _ts_log function is required
        return 1
    end

    if string match -q -- '-*' "$function"
        _ts_log invalid function: (red $function)
        return 1
    end

    set -l logs_cmd sls logs
    test -n "$function" && set -a logs_cmd --function=(string escape -- $function)
    test -n "$aws_profile" && set -a logs_cmd --aws-profile=(string escape -- $aws_profile)
    test -n "$stage" && set -a logs_cmd --stage=(string escape -- $stage)
    test -n "$region" && set -a logs_cmd --region=(string escape -- $region)
    set -q _flag_tail && set -a logs_cmd --tail
    test -n "$startTime" && set -a logs_cmd --startTime=(string escape -- $startTime)
    test -n "$_flag_filter" && set -a logs_cmd --filter=(string escape -- $_flag_filter)
    test -n "$_flag_interval" && set -a logs_cmd --interval=(string escape -- $_flag_interval)
    test -n "$_flag_app" && set -a logs_cmd --app=(string escape -- $_flag_app)
    test -n "$_flag_org" && set -a logs_cmd --org=(string escape -- $_flag_org)
    test -n "$_flag_config" && set -a logs_cmd --config=(string escape -- $_flag_config)

    set -l awk_cmd LC_CTYPE=C awk -f (string escape -- $__fish_config_dir/functions/logs.awk)

    test function = (type -t ts_styles) && ts_styles

    _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $logs_cmd \| $awk_cmd))
    eval (_ts_env --mode=env) (string escape -- command $logs_cmd) \| $awk_cmd
end
