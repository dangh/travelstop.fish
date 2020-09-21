function __sls_complete_modules
  set --local project_dir (git rev-parse --show-toplevel)
  ls "$project_dir/modules"
end
