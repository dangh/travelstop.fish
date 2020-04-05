function sls_deploy -d "deploy CF stack/lambda function"
  if count $argv > /dev/null
    for name in $argv
      switch $name
        case libs
          __build_libs
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

function __sls_deploy_module -a module_name -d "deploy single module"
  echo (set_color -b green)(set_color black)deploying module $module_name(set_color normal)

  set -l current_dir (pwd)
  set -l project_dir (string replace -r '(ravelstop)/.*' '$1' "$current_dir")

  function on_ctrl_c -j %self -V current_dir
    functions -e on_ctrl_c
    cd "$current_dir"
  end

  cd "$project_dir/modules/$module_name"
  __sls_deploy
  cd "$current_dir"

  functions -e on_ctrl_c
end

function __sls_deploy_function -a function_name -d "deploy single function in current stack"
  echo (set_color -b green)(set_color black)deploying function $function_name(set_color normal)
  __sls_deploy -f $function_name
end

function __sls_deploy -d "wrap around sls deploy command"
  set -l command "sls deploy -s $AWS_ENV $argv --verbose"

  echo (set_color blue)(pwd)(set_color normal)
  echo (set_color green)$command(set_color normal)

  set -lx SLS_DEBUG \*
  eval $command

  if test $status -eq 0
    __notify "🎉 𝚜𝚞𝚌𝚌𝚎𝚜𝚜" "$command" tink
  else
    __notify "🤡 𝚏𝚊𝚒𝚕𝚎𝚍" "$command" basso
  end
end

function __build_libs -d "rebuild libs module"
  set -l current_dir (pwd)
  set -l project_dir (string replace -r '(ravelstop)/.*' '$1' "$current_dir")
  set -l nodejs_dir "$project_dir/modules/libs/nodejs"

  # repackaging libs
  echo (set_color -b green)(set_color black)repackaging libs(set_color normal)
  npm run --prefix "$nodejs_dir" --silent build

  # invalidate libs and package-lock
  set -l libs (awk '/\"build-/ {print $1}' package.json | awk -F 'build-' '{print $2}' | awk -F '"' '{print $1}')
  rm -r "$nodejs_dir/package-lock.json" 2>/dev/null
  for lib in $libs
    echo (set_color red)invalidate $lib(set_color normal)
    rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
  end
  echo (set_color red)invalidate package-lock.json(set_color normal)

  # rebuild package-lock and reinstall libs
  echo (set_color -b green)(set_color black)reinstall packages(set_color normal)
  npm i --prefix "$nodejs_dir"
end

function __notify -a title message sound -d "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  afplay "/System/Library/Sounds/$sound.aiff" &
end

alias push=sls_deploy
alias psuh=sls_deploy
alias puhs=sls_deploy
