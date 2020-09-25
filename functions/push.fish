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
      __sls_deploy --stack-dir="$project_dir/modules/$name" $args
      set --erase names[(contains --index $name $names)]
    end
  end
  #deploy services/functions
  for name in $names
    if test -e "$name/serverless.yml"
      __sls_deploy --stack-dir="$name" $args
    else
      __sls_deploy --function=$name $args
    end
  end
end

function __sls_deploy --description "wrap around sls deploy command"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local args
  set --local stack_name
  set --local function_name
  set --local config
  set --local stack_dir .

  getopts $argv | while read --local key value
    #getopts prepend single flag value with equal sign
    #need to get rid of it
    set value (string replace --regex '^=*' '' $value)

    switch $key
    case stack-dir
      set stack_dir $value
    case profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case f function
      set function_name $value
      set args $args "--function="(string escape $value)
    case c config
      set config $value
      set args $args "--config="(string escape $value)
    case \*
      set --local arg
      if test (string length $key) = 1
        set arg "-$key"
      else
        set arg "--$key"
      end
      if test "$value" != "true"
        set arg "$arg="(string escape $value)
      end
      set args $args $arg
    end
  end

  if test -z "$config"
    set config ./serverless.yml
  end
  if ! test -e "$config"
    __sls_print_log (set_color red)error: (realpath $config) does not exist!(set_color normal)
    return 1
  end
  set stack_name (__sls_stack_name $config)

  set --local command "sls deploy --verbose --profile=$profile --stage=$stage --region=$region $args"

  if test -n "$function_name"
    __sls_print_log deploying function: (set_color magenta)$function_name(set_color normal)
  else
    __sls_print_log deploying stack: (set_color magenta)$stack_name(set_color normal)
  end

  __sls_print_log working directory: (set_color blue)(pwd)(set_color normal)
  __sls_print_log execute command: (set_color green)$command(set_color normal)

  set --local --export SLS_DEBUG \*
  withd $stack_dir $command

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
  if ! string match --quiet --regex '.yml$' $stack_dir
    set stack_dir $stack_dir/serverless.yml
  end
  sed -n 's/^service:[[:space:]]*\([[:alnum:]-]*\)[[:space:]]*$/\1/p' "$stack_dir"
end

function __sls_print_log
  echo '('(set_color yellow)sls(set_color normal)')' $argv
end
