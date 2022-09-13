function invoke --description "invoke lambda function"
  set --local startTime (date -u "+%Y%m%dT%H%M%S")
  set --local function
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION

  argparse --name='sls invoke' \
    'profile=?' \
    'f/function=?' \
    's/stage=?' \
    'r/region=?' \
    'q/qualifier=?' \
    'p/path=?' \
    't/type=?' \
    'l/log' \
    'd/data=?' \
    'raw' \
    'context=?' \
    'contextPath=?' \
    'app=?' \
    'org=?' \
    'c/config=?' \
    'tail' \
    'startTime=?' \
    'filter=?' \
    'i/interval=?' \
    -- $ts_default_argv_invoke $argv
  or return 1

  # function is the first positional argument
  set --query argv[1] && set function $argv[1]

  set --query _flag_function && set function $_flag_function
  set --query _flag_profile && set profile $_flag_profile
  set --query _flag_stage && set stage $_flag_stage
  set --query _flag_region && set region $_flag_region
  set --query _flag_startTime && set startTime $_flag_startTime

  if test -z "$function"
    _ts_log function is required
    return 1
  end

  if string match --quiet -- '-*' "$function"
    _ts_log invalid function: (red $function)
    return 1
  end

  set --local invoke_cmd sls invoke
  test -n "$function" && set --append invoke_cmd --function=(string escape -- $function)
  test -n "$profile" && set --append invoke_cmd --profile=(string escape -- $profile)
  test -n "$stage" && set --append invoke_cmd --stage=(string escape -- $stage)
  test -n "$region" && set --append invoke_cmd --region=(string escape -- $region)
  test -n "$_flag_type" && set --append invoke_cmd --type=(string escape -- $_flag_type)
  test -n "$_flag_qualifier" && set --append invoke_cmd --qualifier=(string escape -- $_flag_qualifier)
  test -n "$_flag_path" && set --append invoke_cmd --path=(string escape -- $_flag_path)
  set --query _flag_log && set --append invoke_cmd --log
  test -n "$_flag_data" && set --append invoke_cmd --data=(string escape -- $_flag_data)
  set --query _flag_raw && set --append invoke_cmd --raw
  test -n "$_flag_context" && set --append invoke_cmd --context=(string escape -- $_flag_context)
  test -n "$_flag_contextPath" && set --append invoke_cmd --contextPath=(string escape -- $_flag_contextPath)
  test -n "$_flag_app" && set --append invoke_cmd --app=(string escape -- $_flag_app)
  test -n "$_flag_org" && set --append invoke_cmd --org=(string escape -- $_flag_org)
  test -n "$_flag_config" && set --append invoke_cmd --config=(string escape -- $_flag_config)

  set --local logs_argv logs
  test -n "$function" && set --append logs_argv --function=(string escape -- $function)
  test -n "$profile" && set --append logs_argv --profile=(string escape -- $profile)
  test -n "$stage" && set --append logs_argv --stage=(string escape -- $stage)
  test -n "$region" && set --append logs_argv --region=(string escape -- $region)
  set --query _flag_tail && set --append logs_argv --tail
  test -n "$startTime" && set --append logs_argv --startTime=(string escape -- $startTime)
  test -n "$_flag_filter" && set --append logs_argv --filter=(string escape -- $_flag_filter)
  test -n "$_flag_interval" && set --append logs_argv --interval=(string escape -- $_flag_interval)
  test -n "$_flag_app" && set --append logs_argv --app=(string escape -- $_flag_app)
  test -n "$_flag_org" && set --append logs_argv --org=(string escape -- $_flag_org)
  test -n "$_flag_config" && set --append logs_argv --config=(string escape -- $_flag_config)

  eval (_ts_env --mode=env) (string escape -- $invoke_cmd)

  logs $logs_argv
end
