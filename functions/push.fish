function push --description "deploy CF stack/lambda function"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local targets
  set --local config #config when pushing functions
  set --local modules
  set --local services
  set --local functions

  #push without arguments
  test -z "$argv" && set --append targets .

  argparse --ignore-unknown \
    '0-conceal' \
    '1-profile=?' \
    's/stage=?' \
    'r/region=?' \
    'p/package=?' \
    'v/verbose' \
    '3-force' \
    'f/function=?' \
    'u/update-config' \
    '4-aws-s3-accelerate' \
    '5-app=?' \
    '6-org=?' \
    'c/config=?' -- $ts_default_argv_push $argv

  set --query _flag_profile && set profile $_flag_profile
  set --query _flag_stage && set stage $_flag_stage
  set --query _flag_region && set region $_flag_region
  set --query _flag_config && set config $_flag_config
  set targets $argv

  for target in $targets
    _ts_resolve_config "$target" "$config" | read --delimiter=: --local type name ver yml
    set --append {$type}s "$type:$name:$ver:$yml:pending"
  end

  #re-order targets
  set targets $modules $services $functions

  set --local success_count 0
  set --local failure_count 0

  #deploy
  for i in (seq (count $targets))
    echo $targets[$i] | read --delimiter=: --local type name ver yml state
    test "$type" != function && test -n "$ver" \
      && set --local name_ver $name-$ver \
      || set --local name_ver $name

    #update progress
    set targets[$i] "$type:$name:$ver:$yml:running"
    test (count $targets) -gt 1 && _ts_progress $targets

    set --local working_dir (dirname $yml)
    set --local cmd
    switch $type
    case function
      set cmd sls deploy function --function=(string escape "$name")
      test -n "$profile" && set --append cmd --profile=(string escape "$profile")
      test -n "$stage" && set --append cmd --stage=(string escape "$stage")
      test -n "$region" && set --append cmd --region=(string escape "$region")
      set --query _flag_force && set --append cmd --force
      set --query _flag_update_config && set --append cmd --update-config
    case \*
      set cmd sls deploy
      set --query _flag_conceal && set --append cmd --conceal
      test -n "$profile" && set --append cmd --profile=(string escape "$profile")
      test -n "$stage" && set --append cmd --stage=(string escape "$stage")
      test -n "$region" && set --append cmd --region=(string escape "$region")
      test -n "$_flag_package" && set --append cmd --package=(string escape "$_flag_package")
      set --query _flag_verbose && set --append cmd --verbose
      set --query _flag_force && set --append cmd --force
      set --query _flag_aws_s3_accelerate && set --append cmd --aws-s3-accelerate
      test -n "$_flag_app" && set --append cmd --app=(string escape "$_flag_app")
      test -n "$_flag_org" && set --append cmd --org=(string escape "$_flag_org")
      test (basename $yml) != serverless.yml && set --append cmd --config=(basename $yml)
    end
    test "$type" = function \
      && _ts_log deploying function: (set_color magenta)$name_ver(set_color normal) \
      || _ts_log deploying stack: (set_color magenta)$name_ver(set_color normal)
    _ts_log working directory: (set_color blue)$working_dir(set_color normal)
    _ts_log execute command: (set_color green)$cmd(set_color normal)

    test "$type" = module && string match --quiet --regex libs $name && build_libs --force
    withd "$working_dir" "test -e package.json && npm i --no-proxy; command $cmd"

    set --local result $status

    #update counters
    test $result -eq 0 \
      && set success_count (math $success_count + 1) \
      || set failure_count (math $failure_count + 1)

    #update progress
    test $result -eq 0 \
      && set targets[$i] "$type:$name:$ver:$yml:success" \
      || set targets[$i] "$type:$name:$ver:$yml:failure"

    #show notification
    set --local notif_message
    set --local notif_stage (string upper $stage)
    set --local notif_name $name_ver
    functions --query fontface \
      && set notif_stage (fontface math_monospace $notif_stage) \
      && set notif_name (fontface math_monospace $notif_name)
    test "$type" = function \
      && set notif_message "env: $notif_stage\nfunc: $notif_name" \
      || set notif_message "env: $notif_stage\nstack: $notif_name"
    set --query sls_success_icon || set --local sls_success_icon 🎉
    set --query sls_failure_icon || set --local sls_failure_icon 🤡
    test $result -eq 0 \
      && _ts_notify "$sls_success_icon deployed" "$notif_message" tink \
      || _ts_notify "$sls_failure_icon failed to deploy" "$notif_message" basso
  end

  #summary
  if test (count $targets) -gt 1
    _ts_progress $targets
    functions --query fontface \
      && set success_count (fontface math_monospace $success_count) \
      && set failure_count (fontface math_monospace $failure_count)
    set --local notif_title (count $targets) stacks/functions deployed
    set --local notif_message success: $success_count\nfailure: $failure_count
    _ts_notify "$notif_title" "$notif_message"
  end
end

function _ts_progress
  set --local count (count $argv)
  set --local color_pending (set_color normal)
  set --local color_running (set_color magenta)
  set --local color_success (set_color green)
  set --local color_failure (set_color red)
  set --local caret_pending ' '
  set --local caret_running (set_color magenta)'▶︎'(set_color normal)
  set --local caret_success ' '
  set --local caret_failure ' '
  set --local indent (test $count -gt 9 && echo 2 || echo 1)
  echo $argv[-1] | read --delimiter=: --local _ _ _ _ state
  if test "$state" = success -o "$state" = failure
    _ts_log (set_color yellow)$count(set_color normal) stacks/functions deployed
  else
    _ts_log deploying (set_color yellow)$count(set_color normal) stacks/functions
  end
  for i in (seq $count)
    echo $argv[$i] | read --delimiter=: --local _ name ver _ state
    set --local index (string sub --start=-$indent " $i")
    set --local caret caret_$state
    set --local color color_$state
    test -n "$ver" && set ver (set_color --dim)-(set_color normal)(set_color yellow)$ver(set_color normal)
    echo $$caret (set_color --dim)$index.(set_color normal) {$$color}$name(set_color normal)$ver
  end
end

function _ts_resolve_config --argument-names target config --description "type:name:version:yml"
  set --local type
  set --local name
  set --local ver
  set --local yml
  set --local json

  if test -f "$target/serverless.yml"
    set yml (realpath "$target/serverless.yml")
  else if test -f "$$_ts_project_dir/modules/$target/serverless.yml"
    set yml (realpath "$$_ts_project_dir/modules/$target/serverless.yml")
  else if test -n "$config"
    set yml (realpath "$config")
  else if test -f "$PWD/serverless.yml"
    set yml "$PWD/serverless.yml"
  end

  test -n "$yml" || return 1

  if test -f (dirname "$yml")/package.json
    set json (dirname "$yml")/package.json
  else if test -f "$$_ts_project_dir/modules/$target/nodejs/package.json"
    set json (realpath "$$_ts_project_dir/modules/$target/nodejs/package.json")
  end

  if contains $target (_ts_functions "$yml")
    set type function
    set name $target
  else
    string match --quiet --regex '/modules/' "$yml" \
      && set type module \
      || set type service
    set name (string match --regex '^service:\s*([^\s]*)' < $yml)[2]
    test -n "$json" \
      && set ver (string match --regex '^\s*"version":\s*"([^"]*)"' < $json)[2]
  end

  echo "$type:$name:$ver:$yml"
end
