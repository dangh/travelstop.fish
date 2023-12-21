function _ts_notify -a title message sound -d "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  set sound "/System/Library/Sounds/$sound.aiff"
  test -f "$sound" && afplay $sound &
end

function _ts_pushover -a title message
  test -n "$PUSHOVER_USER_KEY" -a -n "$PUSHOVER_APP_TOKEN" || return
  wait # queue pushover api calls
  curl -s \
    --form-string "token=$PUSHOVER_APP_TOKEN" \
    --form-string "user=$PUSHOVER_USER_KEY" \
    --form-string "title=$title" \
    --form-string "message=$message" \
    https://api.pushover.net/1/messages.json > /dev/null 2>&1 &
end

function _ts_aws_creds -e clipboard_change -a creds -d "monitor clipboard for AWS credentials and store it"
  set -q ts_aws_creds || return 1
  set -n "$creds" || pbpaste | read -z creds
  if string match -q -r '^\[(?<account_id>[[:digit:]]+)_(?<role>[[:alpha:]]+)\](?<config>(\naws_[[:alpha:]_]+=[^[:space:]]+)+)' -- $creds
    for stage_config in $ts_aws_creds
      string match -q -r $account_id',(?<stage>[^,]+),(?<region>.+)' -- $stage_config || continue
      mkdir -p ~/.aws
      echo [$role@$stage]{$config} > ~/.aws/credentials
      set -U -x AWS_PROFILE $role@$stage
      set -U -x AWS_DEFAULT_REGION $region
      set -l notif_profile $AWS_PROFILE
      set -l notif_region $region
      set -l title 📮 AWS profile updated
      functions -q fontface &&
        set notif_profile (fontface -s monospace "$notif_profile") &&
        set notif_region (fontface -s monospace "$notif_region")
      _ts_notify "$title" "$notif_profile\n$notif_region"
      return 0
    end
  end
  return 1
end

function _ts_log
  echo '('(yellow sls)')' $argv
end

function _ts_env
  test -n "$ts_env" || begin
    echo
    return 0
  end

  argparse 'mode=?' -- $argv
  set -l result

  switch $_flag_mode
  case 'env'
    for pair in $ts_env
      echo $pair | read -l -d = key value
      set -a result $key=(string escape -- $value)
    end
  case 'awk'
    for pair in $ts_env
      echo $pair | read -l -d = key value
      set -a result -v $key=(string escape -- $value)
    end
  end
  echo -n (string join ' ' -- $result)
end

function _ts_project_dir_setup
  set -g _ts_project_dir _ts_project_dir_$fish_pid

  function $_ts_project_dir -e fish_prompt # wait until first prompt evaluated
    functions -e $_ts_project_dir

    function $_ts_project_dir -v PWD
      set -U $_ts_project_dir (git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
      test -n "$$_ts_project_dir" || set -e $_ts_project_dir
    end && $_ts_project_dir

    function clear_$_ts_project_dir -e fish_exit
      set -e $_ts_project_dir
    end
  end

  status is-interactive || $_ts_project_dir
end && _ts_project_dir_setup && functions -e _ts_project_dir_setup

function _ts_modules -d "list all modules"
  set -q $_ts_project_dir || return
  printf '%s\n' $$_ts_project_dir/modules/*/serverless.yml | string replace -r '.*/modules/(\w+)/serverless.yml' 'modules/$1'
end

function _ts_substacks -d "list all sub directories contains serverless.yml"
  set -q $_ts_project_dir || return
  find . -type d -name node_modules -prune -o -type f -name serverless.yml -print | string replace /serverless.yml '' | string replace './' ''
end

function _ts_functions -a yml -d "list all lambda functions in serverless.yml"
  test -n "$yml" || set -l yml ./serverless.yml
  awk '{
    if ((y == 1) && ($0 ~ /^[^#[:space:]]/)) exit;
    if ($0 ~ /^[[:space:]]*#/) next;
    if ($0 ~ /^functions:/) { y = 1; next; }
    if ((y == 1) && match($0, /^[[:space:]]{2}[[:alpha:]]+:/)) print substr($0, RSTART+2, RLENGTH-2-1);
  }' $yml 2>/dev/null
end

function _ts_validate_path -a path -d "validate path existence and print it with colors"
  set path (string replace -r '^\./?(.*)' '$1' $path)
  string match -q -r '^/' $path || set path (pwd)/$path

  set -l parts (string split -n / $path)
  set -l corrects
  set -l wrongs
  set -l dir

  for p in $parts
    if test -e "$dir/$p"
      set dir "$dir/$p"
      set -a corrects $p
      set -e parts[1]
    else
      break
    end
  end
  for p in $parts
    set -a wrongs $p
  end

  set -e path
  for p in $corrects
    set path "$path"(green (dim /)$p)
  end
  if test -d "$dir"
    set path "$path"(green (dim /))
  end
  if test -n "$wrongs"
    set path "$path"(red $wrongs[1])
    set -e wrongs[1]
    for p in $wrongs
      set path "$path"(red (dim /)$p)
    end
  end
  echo $path
end

status is-interactive || exit

set -q ts_color_profile || set -g ts_color_profile bold magenta
set -q ts_color_stage   || set -g ts_color_stage   bold magenta
set -q ts_color_sep     || set -g ts_color_sep     dim magenta
set -q ts_sep           || set -g ts_sep @

for color in ts_color_{profile,stage,sep}
  # function to refresh prompt color when aws config change
  function $color -V color
    # find the most specific variable that has value
    # example of variables specialty
    #   ts_color_profile_ServerlessDeployNonProd_DEV
    #   ts_color_profile_ServerlessDeployNonProd
    #   ts_color_profile_DEV
    #   ts_color_profile
    for color_ in {$color}_{$_ts_profile}_{$_ts_stage} {$color}_{$_ts_profile} {$color}_{$_ts_stage} $color
      set -q $color_ && set _color $color_ && break
    end
    # store color in global variable
    set -g _$color $$_color
  end
end

function _ts_prompt_setup
  functions -q fish_right_prompt && functions -c fish_right_prompt fish_right_prompt_original

  function _ts_prompt_repaint -v AWS_PROFILE
    set -g _ts_profile (string replace -r '(Non)?Prod@.*' '' "$AWS_PROFILE")
    set -g _ts_stage (string replace -r '.*@' '' "$AWS_PROFILE")
    if test -n "$TMUX"
      command tmux set-option -g @status_right_x_content $_ts_profile \; set-option -g @status_right_z_content $_ts_stage \; refresh-client -S 2>/dev/null
    else
      ts_color_profile
      ts_color_stage
      ts_color_sep
      commandline -f repaint-mode
    end
  end && _ts_prompt_repaint

  function _ts_prompt_enable -v PWD
    if string match -q "*WhiteLabs/Travelstop.git" (git config --get remote.origin.url 2>/dev/null)
      set -g _ts_prompt_enable
    else
      set -e _ts_prompt_enable
    end
  end && _ts_prompt_enable

  function fish_right_prompt
    if set -q _ts_prompt_enable
      if test -z "$TMUX"
        ansi-escape '--'$_ts_color_profile $_ts_profile
        ansi-escape '--'$_ts_color_sep     $ts_sep
        ansi-escape '--'$_ts_color_stage   $_ts_stage
      end
    else
      functions -q fish_right_prompt_original && fish_right_prompt_original
    end
  end

  function _ts_prompt_newline_postexec -e fish_postexec -d "new line between commands"
    set -q ts_newline && test -n "$argv" && echo
  end

  function _ts_prompt_newline_cancel -e fish_cancel -d "new line after cancel current commandline"
    set -q ts_newline && echo
  end
end && _ts_prompt_setup && functions -e _ts_prompt_setup

function _ts_uniq_completions
  set -l cmd (commandline -p -o -c)
  set -e cmd[1]
  for arg in $argv
    if not contains $arg $cmd
      echo $arg
    end
  end
end

function _ts_install -e travelstop_install -e travelstop_update
  if not set -qU ts_enable_abbr
    set -U ts_enable_abbr true
  end
end

function _ts_uninstall -e travelstop_uninstall
  set -e ( set -n | string match -r '^_?ts_.*' )
end

if test -n "$ts_enable_abbr"
  abbr -a -- c changes
  abbr -a -- p push
  abbr -a -- l logs
  abbr -a -- i invoke
  abbr -a -- b build_libs
  abbr -a -- r rename_modules
  abbr -a -- l0 'logs --startTime=(date -u +%Y%m%dT%H%M%S)'
  abbr -a -- l5 'logs --startTime=5m'
  abbr -a -- l10 'logs --startTime=10m'
  abbr -a -- l15 'logs --startTime=15m'
  abbr -a -- l30 'logs --startTime=30m'
end
