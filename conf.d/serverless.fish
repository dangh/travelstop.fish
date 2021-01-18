status is-interactive || exit

set --global _sls_project_dir _sls_project_dir_$fish_pid

function $_sls_project_dir --on-event fish_prompt
  function $_sls_project_dir --on-variable PWD
    fish --private --command "
      set --universal $_sls_project_dir (git rev-parse --show-toplevel 2>/dev/null)
    " &
    disown
  end && $_sls_project_dir
end

function _sls_modules
  test $status -eq 0 && ls "$$_sls_project_dir/modules"
end

function _sls_substacks
  find . -name serverless.yml -maxdepth 2 -mindepth 2 | string replace --regex '^\./(.*)/serverless\.yml$' '$1'
end

function _sls_functions --argument-names yml
  test -n "$yml" || set --local yml ./serverless.yml
  awk '{
    if ((y == 1) && ($0 ~ /^[^#[:space:]]/)) exit;
    if ($0 ~ /^[[:space:]]*#/) next;
    if ($0 ~ /^functions:/) { y = 1; next; }
    if ((y == 1) && match($0, /^[[:space:]]{2}[[:alpha:]]+:/)) print substr($0, RSTART+2, RLENGTH-2-1);
  }' $yml 2>/dev/null
end

function _sls_log
  echo '('(set_color yellow)sls(set_color normal)')' $argv
end

function _sls_validate_path --argument-names path
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

function _sls_uniq_completions
  set --local cmd (commandline --current-process --tokenize --cut-at-cursor)
  set --erase cmd[1]
  for arg in $argv
    if not contains $arg $cmd
      echo $arg
    end
  end
end
