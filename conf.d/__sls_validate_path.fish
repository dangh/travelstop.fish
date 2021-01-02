function __sls_validate_path --argument-names path
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
