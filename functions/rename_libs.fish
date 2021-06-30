function rename_libs --argument-names suffix
  set --local name module-libs
  if test -n "$suffix"
    set name module-libs-$suffix
  end
  if test -d $$_ts_project_dir
    sed -i '' -E 's/module-libs(-.*)?$/'$name'/g' $$_ts_project_dir/modules/libs/serverless.yml
    sed -i '' -E 's/module-libs-(.*)\$/'$name'-$/g' $$_ts_project_dir/services/serverless-layers.yml $$_ts_project_dir/admin/services/serverless-layers.yml
  end
end
