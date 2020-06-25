function push --description "deploy CF stack/lambda function"
  if count $argv > /dev/null
    for name in $argv
      switch $name
        case libs
          build_libs
          __sls_deploy_module $name
        case templates
          __sls_deploy_module $name
        case \*
          __sls_deploy_function $name
      end
    end
  else
    __sls_deploy
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
  __sls_deploy
  popd

  functions --erase on_ctrl_c
end

function __sls_deploy_function --argument-names function_name --description "deploy single function in current stack"
  echo (set_color --background green)(set_color black)deploying function $function_name(set_color normal)
  __sls_deploy --function $function_name
end

function __sls_deploy --description "wrap around sls deploy command"
  set --local stage (string replace --regex '.*@' '' -- $AWS_PROFILE)
  set --local command "sls deploy --verbose --stage $stage $argv"

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
