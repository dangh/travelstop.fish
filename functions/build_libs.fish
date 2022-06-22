function build_libs --description "rebuild libs module"
  set --local nodejs_dir "$$_ts_project_dir/modules/libs/nodejs"
  set --local packages_dir "$$_ts_project_dir/packages"
  set --local force_install FALSE
  set --local tgzs

  argparse 'f/force' -- $argv
  or return 1
  set --query _flag_force && set force_install TRUE

  _ts_log rebuild libs

  _ts_libs | while read --local lib_dir
    set --local lib (string match --regex '[^/]+$' $lib_dir)
    set --local lib_changed TRUE
    set --local last_commit_id (command git rev-list --max-count=1 HEAD "$packages_dir/$lib")
    if test -n "$last_commit_id"
      set --local changes (command git diff --name-only $last_commit_id "$nodejs_dir/$lib_dir")
      if test -z "$changes"
        set lib_changed FALSE
      end
    end
    if test "$lib_changed" = TRUE
      _ts_log (set_color --dim)... (set_color normal)(set_color --bold green)$lib(set_color normal)(set_color green): changed .. REBUILD(set_color normal)
      set --local tgz (command npm run --prefix (string escape -- $nodejs_dir) --silent build-$lib)
      set --append tgzs (string escape -- $packages_dir/$lib/$tgz)
      rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
    else if test "$force_install" = TRUE
      _ts_log (set_color --dim)... (set_color normal)(set_color --bold magenta)$lib(set_color normal)(set_color magenta): FORCE REINSTALL(set_color normal)
      rm -r "$nodejs_dir/node_modules/$lib" 2>/dev/null
      set --append tgzs "$packages_dir/$lib/"(_ts_lib_tgz $lib)
    else
      _ts_log (set_color --dim)... (set_color normal)(set_color --bold --dim)$lib(set_color normal)(set_color --dim): no changes .. SKIP(set_color normal)
    end
  end

  if test -n "$tgzs"
    set --local cmd npm install --no-proxy --loglevel=error --prefix=(string escape -- $nodejs_dir)
    _ts_log (set_color --dim)... (set_color normal)(set_color yellow)$cmd \\\n"  "$tgzs (set_color normal)
    withd "$nodejs_dir" (string escape -- command $cmd $tgzs) ">/dev/null"
  end
end

function _ts_libs --argument-names --description "get all libs"
  for line in (string match --regex --all 'npm pack \S+' (read --null < $$_ts_project_dir/modules/libs/nodejs/package.json))
    string match --regex '\S+$' $line
  end
end

function _ts_lib_tgz --argument-names lib --description "get tgz"
  test -n "$lib" || return 1
  string match --regex '/'$lib'-[[:digit:]]+.[[:digit:]]+.[[:digit:]]+.tgz' (read --null < $$_ts_project_dir/modules/libs/nodejs/package.json) | string sub --start 2
end
