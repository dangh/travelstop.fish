function push --description "deploy CF stack/lambda function"
  set --local names
  getopts $argv | while read --local key value
    switch $key
    case _
      set --append names $value
    case \*
      if test (string length $key) = 1
        set args $args "-$key"
      else
        set args $args "--$key"
      end
      if test "$value" != "true"
        set args $args=(string escape $value)
      end
    end
  end
  if count $names > /dev/null
    for name in $names
      switch $name
      case libs
        build_libs --force
        __sls_deploy_module $name $args
      case templates
        __sls_deploy_module $name $args
      case \*
        __sls_deploy_function $name $args
      end
    end
  else
    __sls_deploy $args
  end
end

function __sls_deploy_module --argument-names module_name --description "deploy single module"
  echo (set_color --background green)(set_color black)deploying module $module_name(set_color normal)

  set --local project_dir (git rev-parse --show-toplevel)

  function on_ctrl_c --on-job-exit %self
    functions --erase on_ctrl_c
    popd
  end

  pushd "$project_dir/modules/$module_name"
  __sls_deploy $argv[2..-1]
  popd

  functions --erase on_ctrl_c
end

function __sls_deploy_function --argument-names function_name --description "deploy single function in current stack"
  echo (set_color --background green)(set_color black)deploying function $function_name(set_color normal)
  __sls_deploy --function=$function_name $argv[2..-1]
end

function __sls_deploy --description "wrap around sls deploy command"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local args
  getopts $argv | while read --local key value
    switch $key
    case aws-profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case \*
      if test (string length $key) = 1
        set args $args "-$key"
      else
        set args $args "--$key"
      end
      if test "$value" != "true"
        set args $args=(string escape $value)
      end
    end
  end

  set --local command "sls deploy --verbose --aws-profile=$profile --stage=$stage --region=$region $args"

  echo (set_color blue)(pwd)(set_color normal)
  echo (set_color green)$command(set_color normal)

  set --local --export SLS_DEBUG \*
  eval $command

  if test $status -eq 0
    __notify "🎉 𝚜𝚞𝚌𝚌𝚎𝚜𝚜" "$command" tink
  else
    __notify "🤡 𝚏𝚊𝚒𝚕𝚎𝚍" "$command" basso
  end
end

function __notify --argument-names title message sound --description "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  afplay "/System/Library/Sounds/$sound.aiff" &
end
