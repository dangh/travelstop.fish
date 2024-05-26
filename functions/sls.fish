function sls -d "wraps sls to provide stage/profile/region implicitly"
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_DEFAULT_REGION
    set -l data

    set -l args $argv

    argparse -i -s -- $args
    set -l sub_command $argv[1]

    argparse -i \
        'aws-profile=' \
        's/stage=' \
        'r/region=' \
        'd/data=' \
        'c/config=' \
        -- $args
    or return 1

    set -l cmd
    if test -z "$sub_command"
        set cmd sls $args
    else
        set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
        set -q _flag_stage && set stage $_flag_stage
        set -q _flag_region && set region $_flag_region

        set -l yml serverless.yml
        set -q _flag_config && set yml $_flag_config
        string match -q -r '^\s*region:\s*\'(?<yml_region>[a-z0-9-]+)\'' <$yml
        test -n "$yml_region" && set region $yml_region

        set cmd sls $argv --aws-profile=$aws_profile --stage=$stage --region=$region
        test -n "$_flag_data" && begin
            set -l data_path (mktemp -t sls-data-)
            echo $_flag_data >$data_path
            set -a cmd --path=$data_path
        end

        _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $cmd))
    end
    eval (_ts_env --mode=env) command $cmd
end
