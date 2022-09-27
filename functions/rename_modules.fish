function rename_modules
  # ensure we're inside workspace
  test -d $$_ts_project_dir || exit 1

  set -l modules
  set -l suffix

  # find changed modules
  git diff --name-only master | while read -l -L file
    switch $file
      case modules/libs\* lib/\* schema/\*
        contains libs $modules || set -a modules libs
      case modules/chrome/\*
        contains chrome $modules || set -a modules chrome
      case modules/ghostscript/\*
        contains ghostscript $modules || set -a modules ghostscript
      case modules/sharp/\*
        contains sharp $modules || set -a modules sharp
      case modules/templates/\*
        contains templates $modules || set -a modules templates
    end
  end

  # if any module already has suffix
  if not string match -q -r 'module-('(string join '|' $modules)')-\$' -- < $$_ts_project_dir/services/serverless-layers.yml
    # toggle off suffix
    set suffix ''
  else
    # use git branch as suffix
    set -l branch (git branch --show-current)
    if test "$branch" != 'master'
      set suffix (string replace -a -r '\W+' '-' -- $branch)
    end
  end

  # rename modules
  test -n "$suffix" && set suffix "-$suffix"
  sed -i '' -E 's/module-('(string join '|' $modules)')([^$]*)(-\$.*)?$/module-\1'"$suffix"'\3/g' \
    $$_ts_project_dir/modules/libs/serverless.yml \
    $$_ts_project_dir/modules/templates/serverless.yml \
    $$_ts_project_dir/services/serverless-layers.yml \
    $$_ts_project_dir/admin/services/serverless-layers.yml
end
