function rename_libs --argument-names suffix
  set --local name module-libs
  if test -d $$_ts_project_dir
    if test -z "$suffix" && string match --quiet --regex 'module-libs$' -- (cat $$_ts_project_dir/modules/libs/serverless.yml)
      set --local branch (git branch --show-current)
      if test "$branch" != 'master'
        set suffix (string replace --all --regex '\W+' '-' -- $branch)
      end
    end
    if test -n "$suffix"
      set name $name-$suffix
    end
    sed -i '' -E 's/module-libs(-.*)?$/'$name'/g' $$_ts_project_dir/modules/libs/serverless.yml
    sed -i '' -E 's/module-libs-(.*)\$/'$name'-$/g' $$_ts_project_dir/services/serverless-layers.yml $$_ts_project_dir/admin/services/serverless-layers.yml
  end
end
