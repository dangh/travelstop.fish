function push --description "deploy CF stack/lambda function"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local project_dir (git rev-parse --show-toplevel)
  set --local targets
  set --local config #config when pushing functions
  set --local modules
  set --local services
  set --local functions
  getopts $argv | while read --local key value
    switch $key
    case _
      set --append targets $value
    case c config
      set config $value
    case profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case \*
      test (string length $key) -eq 1 \
        && set key "-$key" \
        || set key "--$key"
      test "$value" = true \
        && set --erase value
      set --append args $key (string escape --style=script $value)
    end
  end

  #push without arguments
  test -z "$argv" && set --append targets .

  for target in $targets
    __sls_resolve_config $project_dir $target $config | read --delimiter=: --local type name ver yml
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
    test (count $targets) -gt 1 && __sls_progress $targets

    set --local working_dir (dirname $yml)
    set --local command "-v --profile $profile -s $stage -r $region"
    if test "$type" = function
      set --append command "-f $name"
      set --prepend command "sls deploy function"
    else
      set --prepend command "sls deploy"
      test (basename $yml) != serverless.yml \
        && set --append command "-c "(basename $yml)
    end
    set --append command $args
    test "$type" = function \
      && __sls_log deploying function: (set_color magenta)$name_ver(set_color normal) \
      || __sls_log deploying stack: (set_color magenta)$name_ver(set_color normal)
    __sls_log working directory: (set_color blue)$working_dir(set_color normal)
    __sls_log execute command: (set_color green)$command(set_color normal)

    test "$type" = module && string match --quiet --regex libs $name && build_libs --force
    withd "$working_dir" "test -e package.json && npm i --no-proxy; $command"

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
      && __notify "$sls_success_icon deployed" "$notif_message" tink \
      || __notify "$sls_failure_icon failed to deploy" "$notif_message" basso
  end

  #summary
  if test (count $targets) -gt 1
    __sls_progress $targets
    functions --query fontface \
      && set success_count (fontface math_monospace $success_count) \
      && set failure_count (fontface math_monospace $failure_count)
    set --local notif_title (count $targets) stacks/functions deployed
    set --local notif_message success: $success_count\nfailure: $failure_count
    __notify "$notif_title" "$notif_message"
  end
end

function __notify --argument-names title message sound --description "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  set sound "/System/Library/Sounds/$sound.aiff"
  test -f "$sound" && afplay $sound &
end

function __sls_progress
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
    __sls_log (set_color yellow)$count(set_color normal) stacks/functions deployed
  else
    __sls_log deploying (set_color yellow)$count(set_color normal) stacks/functions
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

function __sls_resolve_config --argument-names project_dir target config --description "type:name:version:yml"
  set --local type
  set --local name
  set --local ver
  set --local yml (realpath $target/serverless.yml 2>/dev/null)
  test -n "$yml" || set yml (realpath $project_dir/modules/$target/serverless.yml 2>/dev/null)
  set --local json (realpath (dirname $yml)/package.json 2>/dev/null)
  test -f "$json" || set json (realpath (dirname $yml)/nodejs/package.json 2>/dev/null)
  if test -f "$yml"
    string match --quiet --regex '/modules/' "$yml" \
      && set type module \
      || set type service
    set name (string match --regex '^service:\s*([^\s]*)' < $yml)[2]
    test -f "$json" && set ver (string match --regex '^\s*"version":\s*"([^"]*)"' < $json)[2]
  else
    test -z "$config" \
      && set yml (realpath ./serverless.yml 2>/dev/null) \
      || set yml (realpath $config 2>/dev/null)
    set type function
    set name $target
  end
  echo "$type:$name:$ver:$yml"
end
