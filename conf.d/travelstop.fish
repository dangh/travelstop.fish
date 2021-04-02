function _ts_notify --argument-names title message sound --description "send notification to system"
  osascript -e "display notification \"$message\" with title \"$title\"" &
  set sound "/System/Library/Sounds/$sound.aiff"
  test -f "$sound" && afplay $sound &
end

function _ts_aws_creds --on-event clipboard_change --argument-names creds --description "monitor clipboard for AWS credentials and store it"
  set --query ts_aws_creds || return
  if string match --quiet --regex '^\[[[:alnum:]_]+\](\naws_[[:alpha:]_]+=.*)+$' "$creds"
    printf $creds | read --local --line profile aws_access_key_id aws_secret_access_key aws_session_token
    string match --regex '^\[([[:digit:]]+)_([[:alpha:]]+)\]' $profile | read --local --line _ account_id role
    for stage_config in $ts_aws_creds
      echo $stage_config | read --delimiter=, --local _account_id stage region
      test "$account_id" = "$_account_id" || continue
      echo [$role@$stage]\n{$aws_access_key_id}\n{$aws_secret_access_key}\n{$aws_session_token} > ~/.aws/credentials
      set --universal --export AWS_PROFILE $role@$stage
      set --universal --export AWS_DEFAULT_REGION $region
      set --local notif_profile $AWS_PROFILE
      set --local notif_region $region
      set --local title 📮 AWS profile updated
      functions --query fontface &&
        set notif_profile (fontface math_monospace "$notif_profile") &&
        set notif_region (fontface math_monospace "$notif_region")
      _ts_notify "$title" "$notif_profile\n$notif_region"
    end
  end
end

function _ts_opt
  set --local short_flags 0 1 2 3 4 5 6 7 8 9 a b c d e f g h i j k l m n o p q r s t u v w x y z
  for arg in $argv
    if string match --quiet -- '*/*' $arg
      set --local short_flag (string sub --start 1 --length 1 -- $arg)
      set --local index (contains --index -- $short_flag $short_flags)
      test "$index" -gt 0 && set --erase short_flags[$index]
    end
  end
  for arg in $argv
    if ! string match --quiet -- '*/*' $arg
      echo -- "$short_flags[1]-$arg"
      set --erase short_flags[1]
    else
      echo -- $arg
    end
  end
end

status is-interactive || exit

set --query ts_color_profile || set --global ts_color_profile \--bold magenta
set --query ts_color_stage || set --global ts_color_stage \--bold magenta
set --query ts_color_sep || set --global ts_color_sep \--dim magenta
set --query ts_sep || set --global ts_sep @

for color in ts_color_{profile,stage,sep}
  function $color --inherit-variable color
    set colors
    for color_ in {$color}_{$_ts_profile}_{$_ts_stage} {$color}_{$_ts_profile} {$color}_{$_ts_stage} $color
      set --query $color_ && set _color $color_ && break
    end
    set --global _$color (set_color $$_color)
  end
end

function _ts_prompt_repaint --on-variable AWS_PROFILE
  set --global _ts_profile (string replace --regex '@.*' '' "$AWS_PROFILE")
  set --global _ts_stage (string replace --regex '.*@' '' "$AWS_PROFILE")
  ts_color_profile
  ts_color_stage
  ts_color_sep
  commandline --function repaint-mode
end && _ts_prompt_repaint

function _ts_prompt_enable --on-variable PWD
  set --query ts_path || set --local ts_path '/wip/travelstop/'
  if string match --quiet "*$ts_path*" "$PWD/"
    set --global _ts_prompt_enable
  else
    set --erase _ts_prompt_enable
  end
end && _ts_prompt_enable

function _ts_prompt_newline_postexec --on-event fish_postexec --description "new line between commands"
  set -q ts_newline && test -n "$argv" && echo
end

function _ts_prompt_newline_cancel --on-event fish_cancel --description "new line after cancel current commandline"
  set -q ts_newline && echo
end

if ! set --query _ts_fish_right_prompt_backup
  set --global _ts_fish_right_prompt_backup
  functions --query fish_right_prompt && functions --copy fish_right_prompt fish_right_prompt_original
end
function fish_right_prompt --inherit-variable _ts_prompt_version
  if set --query _ts_prompt_enable
    string unescape "$_ts_color_profile$_ts_profile\x1b[0m$_ts_color_sep$ts_sep\x1b[0m$_ts_color_stage$_ts_stage\x1b[0m"
  else
    set --local v $_ts_prompt_version && set --erase _ts_prompt_version
    functions --query fish_right_prompt_original && fish_right_prompt_original
  end
end

set --global _ts_project_dir _ts_project_dir_$fish_pid

function $_ts_project_dir --on-event fish_prompt
  function $_ts_project_dir --on-variable PWD
    set --universal $_ts_project_dir (git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
  end && $_ts_project_dir
  function clear_$_ts_project_dir --on-event fish_exit
    set --erase $_ts_project_dir
  end
end

function _ts_modules --description "list all modules"
  test $status -eq 0 && ls "$$_ts_project_dir/modules"
end

function _ts_substacks --description "list all sub directories contains serverless.yml"
  set files */serverless.yml */*/serverless.yml
  printf -- '%s\n' $files | string replace /serverless.yml ''
end

function _ts_functions --argument-names yml --description "list all lambda functions in serverless.yml"
  test -n "$yml" || set --local yml ./serverless.yml
  awk '{
    if ((y == 1) && ($0 ~ /^[^#[:space:]]/)) exit;
    if ($0 ~ /^[[:space:]]*#/) next;
    if ($0 ~ /^functions:/) { y = 1; next; }
    if ((y == 1) && match($0, /^[[:space:]]{2}[[:alpha:]]+:/)) print substr($0, RSTART+2, RLENGTH-2-1);
  }' $yml 2>/dev/null
end

function _ts_log
  echo '('(set_color yellow)sls(set_color normal)')' $argv
end

function _ts_validate_path --argument-names path --description "validate path existence and print it with colors"
  set path (string replace --regex '^\./?(.*)' '$1' $path)
  string match --quiet --regex '^/' $path || set path (pwd)/$path

  set --local parts (string split --no-empty / $path)
  set --local corrects
  set --local wrongs
  set --local dir

  for p in $parts
    if test -e "$dir/$p"
      set dir "$dir/$p"
      set --append corrects $p
      set --erase parts[1]
    else
      break
    end
  end
  for p in $parts
    set --append wrongs $p
  end

  set --erase path
  for p in $corrects
    set path "$path"(set_color green --dim)/(set_color normal)(set_color green)$p(set_color normal)
  end
  if test -d "$dir"
    set path "$path"(set_color green --dim)/(set_color normal)
  end
  if test -n "$wrongs"
    set path "$path"(set_color red)$wrongs[1](set_color normal)
    set --erase wrongs[1]
    for p in $wrongs
      set path "$path"(set_color red --dim)/(set_color normal)(set_color red)$p(set_color normal)
    end
  end
  echo $path
end

function _ts_uniq_completions
  set --local cmd (commandline --current-process --tokenize --cut-at-cursor)
  set --erase cmd[1]
  for arg in $argv
    if not contains $arg $cmd
      echo $arg
    end
  end
end
