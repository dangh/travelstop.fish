function logs -d "watch lambda function logs"
    set -l function
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_REGION
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

    set -l logs_cmd (_ts_sls --with-env) logs
    test -n "$function" && set -a logs_cmd -f $function
    test -n "$aws_profile" && set -a logs_cmd --aws-profile $aws_profile
    test -n "$stage" && set -a logs_cmd -s $stage
    test -n "$region" && set -a logs_cmd -r $region
    set -q _flag_tail && set -a logs_cmd -t
    test -n "$startTime" && set -a logs_cmd --startTime $startTime
    test -n "$_flag_filter" && set -a logs_cmd --filter $_flag_filter
    test -n "$_flag_interval" && set -a logs_cmd -i $_flag_interval
    test -n "$_flag_app" && set -a logs_cmd --app $_flag_app
    test -n "$_flag_org" && set -a logs_cmd --org $_flag_org
    test -n "$_flag_config" && set -a logs_cmd -c $_flag_config

    set -l awk_cmd LC_CTYPE=C awk -f $__fish_config_dir/functions/logs.awk

    functions -q ts_styles && ts_styles

    _ts_log execute command: (green (string join ' ' -- $logs_cmd))

    if functions -q parse_logs
        env $logs_cmd | fish -c parse_logs | env $awk_cmd
    else
        env $logs_cmd | env $awk_cmd
    end
end
