function pack --description "package a serverless service"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local yml ./serverless.yml

  argparse --name='sls package' \
    'profile=?' \
    's/stage=?' \
    'r/region=?' \
    'app=?' \
    'org=?' \
    'c/config=?' \
    -- $ts_default_argv_pack $argv
  or return 1

  # config is the first positional argument
  set --query argv[1] && set yml $argv[1]

  set --query _flag_profile && set profile $_flag_profile
  set --query _flag_stage && set stage $_flag_stage
  set --query _flag_region && set region $_flag_region
  set --query _flag_config && set yml $_flag_config

  string match --quiet --regex '\.yml$' "$yml" || set yml $yml/serverless.yml
  if ! test -f "$yml"
    _ts_log invalid serverless config: (_ts_validate_path $yml)
    return 1
  end
  set yml (realpath $yml 2>/dev/null)
  set --local working_dir (dirname $yml)
  set --local name_ver (string match --regex '^service:\s*([^\s]*)' < $yml)[2]
  set --local json (realpath $working_dir/package.json 2>/dev/null)
  test -f "$json" || set --local json (realpath $working_dir/nodejs/package.json 2>/dev/null)
  test -f "$json" && set name_ver $name_ver-(string match --regex '^\s*"version":\s*"([^"]*)"' < $json)[2]

  set --local package_cmd sls package
  test -n "$profile" && set --append package_cmd --profile=(string escape "$profile")
  test -n "$stage" && set --append package_cmd --stage=(string escape "$stage")
  test -n "$region" && set --append package_cmd --region=(string escape "$region")
  test -n "$_flag_package" && set --append package_cmd --package=(string escape "$_flag_package")
  test -n "$_flag_app" && set --append package_cmd --app=(string escape "$_flag_app")
  test -n "$_flag_org" && set --append package_cmd --org=(string escape "$_flag_org")
  test (basename $yml) != serverless.yml && set --append package_cmd --config (basename $yml)

  _ts_log packaging stack: (magenta $name_ver)
  _ts_log config: (blue $yml)
  _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $package_cmd))

  withd "$working_dir" (_ts_env --mode=env) "command $package_cmd"
end
