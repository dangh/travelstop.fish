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
    'e/exclude=+' \
    'R/regex' \
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

  set -l match_flags ''
  set -q _flag_regex && set match_flags '-r'
  set -l patterns $targets
  set targets

  set -l all_stacks (_ts_modules | sort) (_ts_substacks | sort)
  for pattern in $patterns
    if string match -q '!*' $pattern
      set -a _flag_exclude (string sub -s 2 $pattern)
      continue
    end
    string match $match_flags -a "$pattern" $all_stacks | while read -l stack
      if not contains $stack $targets
        set -a targets $stack
      end
    end
  end
  for pattern in $_flag_exclude
    set targets (string match $match_flags -v -a "$pattern" $targets)
  end

  for target in $targets
    _ts_resolve_config "$target" "$config" | read -l -d : target_type __
    set -a {$target_type}s "pending:$target_type:$__:$stage"
  end

  # re-order targets
  set targets $modules $services $functions

  set -l success_count 0
  set -l failure_count 0

  # deploy
  for i in (seq (count $targets))
    echo $targets[$i] | read -l -d : state __
    echo $__ | read -l -d : target_type serverless_yml service_name function_name package_version region stage
    test "$target_type" != function && test -n "$package_version" \
      && set -l fullname $service_name-$_ts_stage-$package_version \
      || set -l fullname $service_name-$_ts_stage-$function_name

    # update progress
    set targets[$i] "running:$__"
    test (count $targets) -gt 1 && _ts_progress $targets

    set -l working_dir (dirname $serverless_yml)
    set -l deploy_cmd sls deploy
    switch $target_type
    case function
      set -a deploy_cmd function --function=(string escape -- $function_name)
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
      test (path basename $serverless_yml) != serverless.yml && set -a deploy_cmd --config=(path basename $serverless_yml)
    end
    test "$target_type" = function \
      && _ts_log deploying function: (magenta $fullname) \
      || _ts_log deploying stack: (magenta $fullname)
    _ts_log working directory: (blue $working_dir)
    _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $deploy_cmd))

    if test "$target_type" = module && string match -q -r module-libs $service_name
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
      && set targets[$i] "success:$__" \
      || set targets[$i] "failure:$__"

    # show notification
    set -l notif_message
    set -l notif_stage (string upper $stage)
    set -l notif_name $fullname
    functions -q fontface \
      && set notif_stage (fontface -s monospace $notif_stage) \
      && set notif_name (fontface -s monospace $notif_name)
    test "$target_type" = function \
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
  echo $argv[-1] | read -l -d : state __
  if test "$state" = 'success' -o "$state" = 'failure'
    _ts_log (yellow $count) 'stacks/functions deployed'
  else
    _ts_log deploying (yellow $count) 'stacks/functions'
  end
  for i in (seq $count)
    echo $argv[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
    set -l index (string sub -s -$indent " $i")
    set -l caret caret_$state
    set -l color color_$state
    set -l fullname $service_name-$stage
    test -n "$package_version" && set package_version (dim '-')(yellow $package_version)
    if test "$target_type" = 'function'
      echo $$caret (dim $index.) ($$color $fullname-$function_name)
    else
      echo $$caret (dim $index.) ($$color $fullname)$package_version
    end
  end
end

function _ts_resolve_config -a target config_file -d "target_type:serverless_yml:service_name:function_name:package_version:region"
  set -l target_type
  set -l service_name
  set -l function_name
  set -l package_version
  set -l serverless_yml
  set -l package_json
  set -l changelog_md
  set -l region

  if test -n "$config_file"
    set serverless_yml (realpath "$config_file")
  else if test -f "$target/serverless.yml"
    set serverless_yml (realpath "$target/serverless.yml")
  else if test -f "$target/serverless-waf.yml"
    set serverless_yml (realpath "$target/serverless-waf.yml")
  else if test -f "$$_ts_project_dir/$target/serverless.yml"
    set serverless_yml (realpath "$$_ts_project_dir/$target/serverless.yml")
  else if test -f "$PWD/serverless.yml"
    set serverless_yml "$PWD/serverless.yml"
  end

  test -n "$serverless_yml" || return 1
  string match -q -r '^\s*region:\s*\'(?<region>[a-z0-9-]+)\'' < $serverless_yml

  if test -f (dirname "$serverless_yml")/package.json
    set package_json (dirname "$serverless_yml")/package.json
  else if test -f "$$_ts_project_dir/modules/$target/nodejs/package.json"
    set package_json (realpath "$$_ts_project_dir/modules/$target/nodejs/package.json")
  else if test -f (dirname "$serverless_yml")/CHANGELOG.md
    set changelog_md (dirname "$serverless_yml")/CHANGELOG.md
  end

  if contains $target (_ts_functions "$serverless_yml")
    set target_type function
    set function_name $target
  else
    string match -q -r '/modules/' "$serverless_yml" \
      && set target_type module \
      || set target_type service
  end
  string match -q -r '^service:\s*(?<service_name>[^\s]*)' < $serverless_yml
  if test -n "$package_json"
    string match -q -r '^\s*"version":\s*"(?<package_version>[^"]*)"' < $package_json
  else if test -n "$changelog_md"
    string match -q -r '# (?<package_version>\d+(\.\d+)+)' < $changelog_md
  end

  echo "$target_type:$serverless_yml:$service_name:$function_name:$package_version:$region"
end
