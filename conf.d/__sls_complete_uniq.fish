function __sls_complete_uniq
  set --local cmd (commandline --current-process --tokenize --cut-at-cursor)
  set --erase cmd[1]
  for arg in $argv
    if not contains $arg $cmd
      echo $arg
    end
  end
end
