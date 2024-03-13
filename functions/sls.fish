function sls -d "wraps sls to provide stage/profile/region implicitly"
    set -l profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_DEFAULT_REGION
    set -l data

    argparse -i \
        'profile=' \
        's/stage=' \
        'r/region=' \
        'd/data=' \
        'c/config=' \
        -- $argv
    or return 1

    set -q _flag_profile && set profile $_flag_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set region $_flag_region

    set -l yml serverless.yml
    set -q _flag_config && set yml $_flag_config
    string match -q -r '^\s*region:\s*\'(?<yml_region>[a-z0-9-]+)\'' <$yml
    test -n "$yml_region" && set region $yml_region

    set -l cmd sls $argv --profile=$profile --stage=$stage --region=$region
    test -n "$_flag_data" && set -a cmd --data=(string replace -r -a '\s*\n\s*' ' ' -- $_flag_data | string collect | string escape)

    _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $cmd))
    eval (_ts_env --mode=env) command $cmd
end
