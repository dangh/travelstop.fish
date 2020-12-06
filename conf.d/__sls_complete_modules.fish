function __sls_complete_modules
  set --local project_dir (git rev-parse --show-toplevel 2>/dev/null)
  test $status -eq 0 && ls "$project_dir/modules"
end
