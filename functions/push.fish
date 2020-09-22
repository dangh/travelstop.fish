function push --description "deploy CF stack/lambda function"
  set --local names
  set --local project_dir (git rev-parse --show-toplevel)
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
  if test (count $names) -eq 0
    set --append names .
  end
  #deploy modules first
  for name in $names
    if test -e "$project_dir/modules/$name/serverless.yml"
      if test "$name" = "libs"
        build_libs --force
      end
      __sls_deploy_stack "$project_dir/modules/$name" $args
      set --erase names[(contains --index $name $names)]
    end
  end
  #deploy services/functions
  for name in $names
    if test -e "$name/serverless.yml"
      __sls_deploy_stack "$name" $args
    else
      __sls_deploy_function $name $args
    end
  end
end

function __sls_deploy_stack --argument-names stack_dir --description "deploy single stack"
  set --local stack_name (__sls_stack_name $stack_dir)
  echo (set_color --background green)(set_color black)deploying stack $stack_name(set_color normal)

  function on_ctrl_c --on-job-exit %self
    functions --erase on_ctrl_c
    popd
  end

  pushd "$stack_dir"
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
  set --local stack_name (__sls_stack_name .)
  set --local function_name
  getopts $argv | while read --local key value
    switch $key
    case profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case function
      set function_name $value
      set args $args "--function="(string escape $value)
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

  set --local command "sls deploy --verbose --profile=$profile --stage=$stage --region=$region $args"

  echo (set_color blue)(pwd)(set_color normal)
  echo (set_color green)$command(set_color normal)

  set --local --export SLS_DEBUG \*
  echo $command | source

  set --local message "𝚎𝚗𝚟: "(string upper $stage)"\n𝚜𝚝𝚊𝚌𝚔: $stack_name"
  if test -n "$function_name"
    set message $message\n"𝚏𝚞𝚗𝚌: $function_name"
  end

  if test $status -eq 0
    __notify "🎉 deployed" "$message" tink
  else
    __notify "🤡 failed to deploy" "$message" basso
  end
end

function __notify --argument-names title message sound --description "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  afplay "/System/Library/Sounds/$sound.aiff" &
end

function __sls_stack_name --argument-names stack_dir
  sed -n 's/^service:[[:space:]]*\([[:alnum:]-]*\)[[:space:]]*$/\1/p' "$stack_dir/serverless.yml"
end
