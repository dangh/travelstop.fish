function push -d "deploy CF stack/lambda function"
  set -l profile $AWS_PROFILE
  set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
  set -l default_region $AWS_DEFAULT_REGION
  set -l targets
  set -l config # config when pushing functions
  set -l modules
  set -l services
  set -l functions

  argparse -n 'sls deploy' \
    'conceal' \
    'profile=' \
    's/stage=' \
    'r/region=' \
    'p/package=' \
    'v/verbose' \
    'force' \
    'f/function=' \
    'u/update-config' \
    'aws-s3-accelerate' \
    'app=' \
    'org=' \
    'c/config=' \
    -- $ts_default_argv_push $argv
  or return 1

  # rename modules before deploy
  rename_modules on

  set -q _flag_profile && set profile $_flag_profile
  set -q _flag_stage && set stage $_flag_stage
  set -q _flag_region && set default_region $_flag_region
  set -q _flag_config && set config $_flag_config
  set -a targets $argv

  # push without any target/config/function
  test -z "$argv" -a -z "$function" && set -a targets .

  for target in $targets
    _ts_resolve_config "$target" "$config" | read -l -d : type name ver region yml
    set -a {$type}s "$type:$name:$ver:$region:$yml:pending"
  end

  # re-order targets
  set targets $modules $services $functions

  set -l success_count 0
  set -l failure_count 0

  # deploy
  for i in (seq (count $targets))
    echo $targets[$i] | read -l -d : type name ver region yml state
    test "$type" != function && test -n "$ver" \
      && set -l name_ver $name-$ver \
      || set -l name_ver $name

    # update progress
    set targets[$i] "$type:$name:$ver:$region:$yml:running"
    test (count $targets) -gt 1 && _ts_progress $targets

    set -l working_dir (dirname $yml)
    set -l deploy_cmd sls deploy
    switch $type
    case function
      set -a deploy_cmd function --function=(string escape -- $name)
      test -n "$profile" && set -a deploy_cmd --profile=(string escape -- $profile)
      test -n "$stage" && set -a deploy_cmd --stage=(string escape -- $stage)
      if test -n "$region"
        set -a deploy_cmd --region=(string escape -- $region)
      else if test -n "$default_region"
        set -a deploy_cmd --region=(string escape -- $default_region)
      end
      set -q _flag_force && set -a deploy_cmd --force
      set -q _flag_update_config && set -a deploy_cmd --update-config
    case \*
      set -q _flag_conceal && set -a deploy_cmd --conceal
      test -n "$profile" && set -a deploy_cmd --profile=(string escape -- $profile)
      test -n "$stage" && set -a deploy_cmd --stage=(string escape -- $stage)
      if test -n "$region"
        set -a deploy_cmd --region=(string escape -- $region)
      else if test -n "$default_region"
        set -a deploy_cmd --region=(string escape -- $default_region)
      end
      test -n "$_flag_package" && set -a deploy_cmd --package=(string escape -- $_flag_package)
      set -q _flag_verbose && set -a deploy_cmd --verbose
      set -q _flag_force && set -a deploy_cmd --force
      set -q _flag_aws_s3_accelerate && set -a deploy_cmd --aws-s3-accelerate
      test -n "$_flag_app" && set -a deploy_cmd --app=(string escape -- $_flag_app)
      test -n "$_flag_org" && set -a deploy_cmd --org=(string escape -- $_flag_org)
      test (path basename $yml) != serverless.yml && set -a deploy_cmd --config=(path basename $yml)
    end
    test "$type" = function \
      && _ts_log deploying function: (magenta $name_ver) \
      || _ts_log deploying stack: (magenta $name_ver)
    _ts_log working directory: (blue $working_dir)
    _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $deploy_cmd))

    if test "$type" = module && string match -q -r libs $name
      build_libs --force
    else
      fish --private --command "
        for d in \"$working_dir\" \"$working_dir\"/nodejs \"$working_dir\"/nodejs*/nodejs
          if test -e \"\$d\"/package.json
            cd \"\$d\"
            type -q nvm && nvm use > /dev/null
            if test (path basename \"\$d\") = web
              npm i --no-proxy --no-optional \$ts_npm_install_options
            else
              npm i --no-proxy --only=prod --no-optional \$ts_npm_install_options
            end
          end
        end
      "
    end
    fish --private --command "
      cd \"$working_dir\"
      type -q nvm && nvm use > /dev/null
      "\ (_ts_env --mode=env)\ "command $deploy_cmd
    "
    set -l result $status

    # update counters
    test $result -eq 0 \
      && set success_count (math $success_count + 1) \
      || set failure_count (math $failure_count + 1)

    # update progress
    test $result -eq 0 \
      && set targets[$i] "$type:$name:$ver:$region:$yml:success" \
      || set targets[$i] "$type:$name:$ver:$region:$yml:failure"

    # show notification
    set -l notif_message
    set -l notif_stage (string upper $stage)
    set -l notif_name $name_ver
    functions -q fontface \
      && set notif_stage (fontface -s monospace $notif_stage) \
      && set notif_name (fontface -s monospace $notif_name)
    test "$type" = function \
      && set notif_message "env: $notif_stage\nfunc: $notif_name" \
      || set notif_message "env: $notif_stage\nstack: $notif_name"
    set -q sls_success_icon || set -l sls_success_icon 🎉
    set -q sls_failure_icon || set -l sls_failure_icon 🤡
    test $result -eq 0 \
      && _ts_notify "$sls_success_icon deployed" "$notif_message" tink \
      || _ts_notify "$sls_failure_icon failed to deploy" "$notif_message" basso

    test $result -eq 0 || break
  end

  # summary
  if test (count $targets) -gt 1
    _ts_progress $targets
    set -l notif_title (math $success_count + $failure_count) stacks/functions deployed
    functions -q fontface \
      && set success_count (fontface -s monospace $success_count) \
      && set failure_count (fontface -s monospace $failure_count)
    set -l notif_message success: $success_count\nfailure: $failure_count
    _ts_notify "$notif_title" "$notif_message"
    _ts_pushover "$notif_title" "$notif_message"
  end
end

function _ts_progress
  set -l count (count $argv)
  set -l color_pending ansi-escape
  set -l color_running magenta
  set -l color_success green
  set -l color_failure red
  set -l caret_pending ' '
  set -l caret_running (magenta '▶︎')
  set -l caret_success ' '
  set -l caret_failure ' '
  set -l indent (test $count -gt 9 && echo 2 || echo 1)
  echo $argv[-1] | read -l -d : _0 _0 _0 _0 state
  if test "$state" = success -o "$state" = failure
    _ts_log (yellow $count) stacks/functions deployed
  else
    _ts_log deploying (yellow $count) stacks/functions
  end
  for i in (seq $count)
    echo $argv[$i] | read -l -d : _0 name ver _0 state
    set -l index (string sub -s -$indent " $i")
    set -l caret caret_$state
    set -l color color_$state
    test -n "$ver" && set ver (dim '-')(yellow $ver)
    echo $$caret (dim $index.) ($$color $name)$ver
  end
end

function _ts_resolve_config -a target config -d "type:name:version:yml"
  set -l type
  set -l name
  set -l ver
  set -l yml
  set -l json
  set -l changelog
  set -l region

  if test -n "$config"
    set yml (realpath "$config")
  else if test -f "$target/serverless.yml"
    set yml (realpath "$target/serverless.yml")
  else if test -f "$$_ts_project_dir/$target/serverless.yml"
    set yml (realpath "$$_ts_project_dir/$target/serverless.yml")
  else if test -f "$PWD/serverless.yml"
    set yml "$PWD/serverless.yml"
  end

  test -n "$yml" || return 1
  string match -q -r '^\s*region:\s*\'(?<region>[a-z0-9-]+)\'' < $yml

  if test -f (dirname "$yml")/package.json
    set json (dirname "$yml")/package.json
  else if test -f "$$_ts_project_dir/modules/$target/nodejs/package.json"
    set json (realpath "$$_ts_project_dir/modules/$target/nodejs/package.json")
  else if test -f (dirname "$yml")/CHANGELOG.md
    set changelog (dirname "$yml")/CHANGELOG.md
  end

  if contains $target (_ts_functions "$yml")
    set type function
    set name $target
  else
    string match -q -r '/modules/' "$yml" \
      && set type module \
      || set type service
    string match -q -r '^service:\s*(?<name>[^\s]*)' < $yml
    if test -n "$json"
      string match -q -r '^\s*"version":\s*"(?<ver>[^"]*)"' < $json
    else if test -n "$changelog"
      string match -q -r '# (?<ver>\d+(\.\d+)+)' < $changelog
    end
  end

  echo "$type:$name:$ver:$region:$yml"
end
