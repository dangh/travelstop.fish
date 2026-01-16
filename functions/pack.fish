function pack -d "package a serverless service"
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l region $AWS_REGION
    set -l yml ./serverless.yml

    argparse -n 'sls package' \
        'aws-profile=' \
        's/stage=' \
        'r/region=' \
        'p/package=' \
        v/verbose \
        'app=' \
        'org=' \
        'c/config=' \
        -- $ts_default_argv_pack $argv
    or return 1

    # config is the first positional argument
    set -q argv[1] && set yml $argv[1]

    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set region $_flag_region
    set -q _flag_config && set yml $_flag_config

    string match -q -r '\.yml$' "$yml" || set yml $yml/serverless.yml
    if ! test -f "$yml"
        _ts_log invalid serverless config: (_ts_validate_path $yml)
        return 1
    end
    set yml (realpath $yml 2>/dev/null)
    set -l working_dir (dirname $yml)
    set -l name_ver (string match -r '^service:\s*([^\s]*)' < $yml)[2]
    set -l json (realpath $working_dir/package.json 2>/dev/null)
    test -f "$json" || set -l json (realpath $working_dir/nodejs/package.json 2>/dev/null)
    test -f "$json" && set name_ver $name_ver-(string match -r '^\s*"version":\s*"([^"]*)"' < $json)[2]

    set -l package_cmd (_ts_sls --with-env) package
    test -n "$aws_profile" && set -a package_cmd --aws-profile $aws_profile
    test -n "$stage" && set -a package_cmd -s $stage
    test -n "$region" && set -a package_cmd -r $region
    test -n "$_flag_package" && set -a package_cmd -p $_flag_package
    test -n "$_flag_verbose" && set -a package_cmd --verbose
    test -n "$_flag_app" && set -a package_cmd --app $_flag_app
    test -n "$_flag_org" && set -a package_cmd --org $_flag_org
    test (path basename $yml) != serverless.yml && set -a package_cmd -c (path basename $yml)

    _ts_log packaging stack: (magenta $name_ver)
    _ts_log config: (blue $yml)
    _ts_log execute command: (green (string join ' ' -- $package_cmd))

    fish --private --command "
cd $working_dir
type -q nvm && nvm use >/dev/null
$package_cmd"
end
