function build_libs -d "rebuild libs module"
    set -l nodejs_dir "$$_ts_project_dir/modules/libs/nodejs"
    set -l packages_dir "$$_ts_project_dir/packages"
    set -l force_install FALSE
    set -l libs
    set -l tgzs

    argparse f/force -- $argv
    or return 1
    set -q _flag_force && set force_install TRUE

    _ts_log rebuild libs

    _ts_libs | while read -l lib_dir
        set -l lib (string match -r '[^/]+$' $lib_dir)
        set -l lib_changed TRUE
        set -l last_commit_id (command git log --max-count=1 --diff-filter=AM --pretty=format:"%h" HEAD "$packages_dir/$lib")
        if test -n "$last_commit_id"
            set -l changes (command git diff --name-only $last_commit_id "$nodejs_dir/$lib_dir")
            if test -z "$changes"
                set lib_changed FALSE
            end
        end
        if test "$lib_changed" = TRUE
            _ts_log (dim ...) (green (bold $lib): changed .. REBUILD)
            set -a libs $lib
        else if test "$force_install" = TRUE
            _ts_log (dim ...) (magenta (bold $lib): FORCE REBUILD)
            set -a libs $lib
        else
            _ts_log (dim ...) (dim (bold $lib))(dim : no changes .. SKIP)
        end
    end

    if test -n "$libs"
        # wrapper shell to await multiple background processes
        fish --private --command "
            set -l jobs
            for lib in $libs
                set -l lib_dir
                switch \$lib
                case schema
                    set lib_dir $$_ts_project_dir/schema
                case \\*
                    set lib_dir $$_ts_project_dir/lib/\$lib
                end
                mkdir -p $packages_dir/\$lib
                # wrapper shell to cd separately
                fish --private --command \"
                    cd $packages_dir/\$lib
                    command npm pack \$lib_dir 2>&1 | tail -1 | read -l tgz
                    if set -q ts_rewrite_tgz_header
                        set -l tar (string replace .tgz .tar \\\$tgz)
                        # re-compress without filename and timestamp
                        gzip -d \\\$tgz
                        gzip -9n \\\$tar
                        mv \\\$tar.gz \\\$tgz
                        # re-write OS header to unknown
                        printf '\\\xff' | dd of=\\\$tgz bs=1 seek=9 count=1 conv=notrunc status=none
                    end
                \" &
                set -a jobs \$last_pid
                rm -r \"$nodejs_dir/node_modules/\$lib\" 2>/dev/null &
                set -a jobs \$last_pid
            end
            for pid in \$jobs
                wait \$pid
            end
        " >/dev/null
        for lib in $libs
            set -l package_json
            switch "$lib"
                case schema
                    set package_json $$_ts_project_dir/schema/package.json
                case \*
                    set package_json $$_ts_project_dir/lib/$lib/package.json
            end
            string match -q -r '^  "version": "(?<ver>[^"]+)"' <$package_json
            set -a tgzs $packages_dir/$lib/$lib-$ver.tgz
        end
    end

    if test -n "$tgzs"
        rm -f $nodejs_dir/package-lock.json
        set -l cmd npm install --no-proxy --prefix=(string escape -- $nodejs_dir) --omit=dev --omit=optional $ts_npm_install_options
        _ts_log (dim ...) (yellow $cmd \\\n'  '$tgzs | string collect)
        fish --private --command "
            cd $nodejs_dir
            type -q nvm && nvm use > /dev/null
            command $cmd $tgzs
        " >/dev/null
    end
end

function _ts_libs -d "get all libs"
    for line in (string match -r -a 'npm pack \S+' (read -z < $$_ts_project_dir/modules/libs/nodejs/package.json))
        string match -r '\S+$' $line
    end
end
