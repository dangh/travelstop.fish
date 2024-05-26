function invoke -d "invoke lambda function"
    set -l startTime (date -u "+%Y%m%dT%H%M%S")
    set -l function
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_DEFAULT_REGION

    argparse -n 'sls invoke' \
        'aws-profile=' \
        'f/function=' \
        's/stage=' \
        'r/region=' \
        'q/qualifier=' \
        'p/path=' \
        't/type=' \
        l/log \
        'd/data=' \
        raw \
        'context=' \
        'contextPath=' \
        'app=' \
        'org=' \
        'c/config=' \
        tail \
        'startTime=' \
        'filter=' \
        'i/interval=' \
        -- $ts_default_argv_invoke $argv
    or return 1

    # function is the first positional argument
    set -q argv[1] && set function $argv[1]

    set -q _flag_function && set function $_flag_function
    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set region $_flag_region
    set -q _flag_startTime && set startTime $_flag_startTime

    if test -z "$function"
        _ts_log function is required
        return 1
    end

    if string match -q -- '-*' "$function"
        _ts_log invalid function: (red $function)
        return 1
    end

    set -l invoke_cmd sls invoke
    test -n "$function" && set -a invoke_cmd --function=(string escape -- $function)
    test -n "$aws_profile" && set -a invoke_cmd --aws-profile=(string escape -- $aws_profile)
    test -n "$stage" && set -a invoke_cmd --stage=(string escape -- $stage)
    test -n "$region" && set -a invoke_cmd --region=(string escape -- $region)
    test -n "$_flag_type" && set -a invoke_cmd --type=(string escape -- $_flag_type)
    test -n "$_flag_qualifier" && set -a invoke_cmd --qualifier=(string escape -- $_flag_qualifier)
    test -n "$_flag_path" && set -a invoke_cmd --path=(string escape -- $_flag_path)
    set -q _flag_log && set -a invoke_cmd --log
    test -n "$_flag_data" && begin
        set -l data_path (mktemp -t sls-invoke-data-)
        echo $_flag_data >$data_path
        set -a invoke_cmd --path=$data_path
    end
    set -q _flag_raw && set -a invoke_cmd --raw
    test -n "$_flag_context" && set -a invoke_cmd --context=(string escape -- $_flag_context)
    test -n "$_flag_contextPath" && set -a invoke_cmd --contextPath=(string escape -- $_flag_contextPath)
    test -n "$_flag_app" && set -a invoke_cmd --app=(string escape -- $_flag_app)
    test -n "$_flag_org" && set -a invoke_cmd --org=(string escape -- $_flag_org)
    test -n "$_flag_config" && set -a invoke_cmd --config=(string escape -- $_flag_config)

    set -l logs_argv logs
    test -n "$function" && set -a logs_argv --function=(string escape -- $function)
    test -n "$aws_profile" && set -a logs_argv --aws-profile=(string escape -- $aws_profile)
    test -n "$stage" && set -a logs_argv --stage=(string escape -- $stage)
    test -n "$region" && set -a logs_argv --region=(string escape -- $region)
    set -q _flag_tail && set -a logs_argv --tail
    test -n "$startTime" && set -a logs_argv --startTime=(string escape -- $startTime)
    test -n "$_flag_filter" && set -a logs_argv --filter=(string escape -- $_flag_filter)
    test -n "$_flag_interval" && set -a logs_argv --interval=(string escape -- $_flag_interval)
    test -n "$_flag_app" && set -a logs_argv --app=(string escape -- $_flag_app)
    test -n "$_flag_org" && set -a logs_argv --org=(string escape -- $_flag_org)
    test -n "$_flag_config" && set -a logs_argv --config=(string escape -- $_flag_config)

    eval (_ts_env --mode=env) (string escape -- $invoke_cmd)

    logs $logs_argv
end
