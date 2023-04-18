function build_libs -d "rebuild libs module"
  set -l nodejs_dir "$$_ts_project_dir/modules/libs/nodejs"
  set -l packages_dir "$$_ts_project_dir/packages"
  set -l force_install FALSE
  set -l tgzs

  argparse 'f/force' -- $argv
  or return 1
  set -q _flag_force && set force_install TRUE

  _ts_log rebuild libs

  _ts_libs | while read -l lib_dir
    set -l lib (string match -r '[^/]+$' $lib_dir)
    set -l lib_changed TRUE
    set -l last_commit_id (command git rev-list --max-count=1 HEAD "$packages_dir/$lib")
    if test -n "$last_commit_id"
      set -l changes (command git diff --name-only $last_commit_id "$nodejs_dir/$lib_dir")
      if test -z "$changes"
        set lib_changed FALSE
      end
    end
    if test "$lib_changed" = TRUE
      _ts_log (dim ...) (green (bold $lib): changed .. REBUILD)
      set -l tgz (command npm run --prefix (string escape -- $nodejs_dir) --silent build-$lib)
      set -a tgzs (string escape -- $packages_dir/$lib/$tgz)
      rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
    else if test "$force_install" = TRUE
      _ts_log (dim ...) (magenta (bold $lib): FORCE REINSTALL)
      rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
      set -a tgzs "$packages_dir/$lib/"(_ts_lib_tgz $lib)
    else
      _ts_log (dim ...) (dim (bold $lib))(dim : no changes .. SKIP)
    end
  end

  if test -n "$tgzs"
    set -l cmd npm install --no-proxy --prefix=(string escape -- $nodejs_dir) --only=prod --no-optional $ts_npm_install_options
    _ts_log (dim ...) (yellow $cmd \\\n'  '$tgzs | string collect)
    fish --private --command "
      cd $nodejs_dir
      type -q nvm && nvm use > /dev/null
      command $cmd $tgzs
    " >/dev/null
  end
end

function _ts_libs -a -d "get all libs"
  for line in (string match -r -a 'npm pack \S+' (read -z < $$_ts_project_dir/modules/libs/nodejs/package.json))
    string match -r '\S+$' $line
  end
end

function _ts_lib_tgz -a lib -d "get tgz"
  test -n "$lib" || return 1
  string match -r '/'$lib'-[[:digit:]]+.[[:digit:]]+.[[:digit:]]+.tgz' (read -z < $$_ts_project_dir/modules/libs/nodejs/package.json) | string sub -s 2
end
