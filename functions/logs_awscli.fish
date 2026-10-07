function logs_awscli -d "watch lambda function logs"
    set -l function
    set -l aws_profile $AWS_PROFILE
    set -l stage
    set -l region $AWS_REGION
    set -l startTime 2m

    argparse -n logs \
        'f/function=' \
        'log-group=' \
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

    # function as the first positional argument
    set -q argv[1] && set function $argv[1]

    set -q _flag_function && set function $_flag_function
    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set stage (string lower -- (string replace -r '.*@' '' -- $aws_profile))
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set region $_flag_region
    set -q _flag_startTime && set startTime $_flag_startTime

    if test -z "$function"; and not set -q _flag_log_group
        _ts_log function is required
        return 1
    end

    if string match -q -- '-*' "$function"
        _ts_log invalid function: (red $function)
        return 1
    end

    if set -q _flag_interval
        _ts_log '--interval is not supported by aws logs tail (polling is managed by AWS CLI)'
        return 1
    end

    set -l log_group $_flag_log_group
    if not set -q _flag_log_group
        # Use the directory named services as the boundary within the Git repo.
        set -l prefix (command git rev-parse --show-prefix 2>/dev/null)
        set -l parts (string split -n / -- "$prefix")
        set -l boundary (contains -i -- services $parts)
        if test -z "$boundary"; or test "$boundary" -eq (count $parts); or test -z "$stage"
            _ts_log 'cannot infer service/stage; run below a services directory in a Git repo, set --stage, or use --log-group'
            return 1
        end
        set -e parts[1..$boundary]
        # Parent directories become singular; the final component stays as-is.
        for i in (seq 1 (math (count $parts) - 1))
            set parts[$i] (string replace -r 'ies$' y -- $parts[$i] | string replace -r '([^s])s$' '$1')
        end
        set -l service (string join - -- $parts)
        set log_group /aws/lambda/$service-$stage-$function
    end
    if test -z "$log_group"
        _ts_log 'log group is required'
        return 1
    end

    # l0 and invoke supply compact UTC timestamps; AWS expects ISO 8601.
    set startTime (string replace -r '^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$' '$1-$2-$3T$4:$5:$6Z' -- $startTime)
    set -l logs_cmd aws logs tail $log_group --format short --color off --since $startTime
    test -n "$aws_profile" && set -a logs_cmd --profile $aws_profile
    test -n "$region" && set -a logs_cmd --region $region
    set -q _flag_tail && set -a logs_cmd --follow
    test -n "$_flag_filter" && set -a logs_cmd --filter-pattern $_flag_filter

    # Print before authentication too, so a stalled session check is debuggable.
    # Do not expose ts_env values, which may contain credentials.
    printf '%s\n' (string join ' ' -- (string escape -- $logs_cmd)) >&2

    set -l env_pairs $ts_env
    functions -q ts_env && set env_pairs (ts_env)
    # Function-scoped exports reach authentication and every pipeline process,
    # including parse_logs and logs.awk, without changing the caller's env.
    for pair in $env_pairs
        set -l parts (string split -m 1 = -- $pair)
        if test (count $parts) -ne 2
            _ts_log 'ts_env entries must be KEY=value'
            return 1
        end
        set -fx $parts[1] "$parts[2]"; or return 1
    end

    _ts_ensure_session $aws_profile; or return 1

    set -l awk_cmd LC_CTYPE=C awk -f $__fish_config_dir/functions/logs.awk

    # AWS short format prefixes each event with YYYY-MM-DDTHH:MM:SS.
    # Strip it before parse_logs; flush each line so --tail remains streaming.
    set -l strip_cmd awk '{ sub(/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} /, ""); print; fflush() }'

    functions -q ts_styles && ts_styles

    if functions -q parse_logs
        command $logs_cmd | command $strip_cmd | command fish -c parse_logs | command env $awk_cmd
    else
        command $logs_cmd | command $strip_cmd | command env $awk_cmd
    end
    # Do not hide AWS or parser failures behind a successful awk process.
    set -l codes $pipestatus
    for code in $codes
        test $code -eq 0; or return $code
    end
end
