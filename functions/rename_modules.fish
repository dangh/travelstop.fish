function rename_modules
    # ensure we're inside workspace
    test -d $$_ts_project_dir || exit 1

    argparse -i f/force s/service=+ -- $argv

    set -l action $argv[1]
    set -l suffix

    switch "$action"
        case off
            set suffix
        case on
            set suffix (_ts_module_get_suffix)
        case toggle
            # if any module already has suffix
            if _ts_modules_have_suffix
                # toggle off suffix
                set suffix
            else
                set suffix (_ts_module_get_suffix)
            end
        case \*
            set suffix (_ts_module_get_suffix $action)
    end

    # rename modules
    test -n "$suffix" && set suffix (string lower -- "-$suffix")

    if test -z "$suffix"
        # clean all suffix
        set ymls
        for f in \
            $$_ts_project_dir/modules/*/serverless.yml \
            $$_ts_project_dir/services/serverless-layers.yml \
            $$_ts_project_dir/admin/services/serverless-layers.yml
            test -f $f && set -a ymls $f
        end
        sed -i.ts_bak -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1\4/g' $ymls
        and command rm $ymls.ts_bak
    else if set -q _flag_force
        # add suffix to all modules
        set ymls \
            $$_ts_project_dir/modules/*/serverless.yml
        if test -n "$ymls"
            sed -i.ts_bak -E 's/^service: module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/service: module-\1'"$suffix"'\4/g' $ymls
            and command rm $ymls.ts_bak
        end
        set ymls
        for f in \
            $$_ts_project_dir/services/serverless-layers.yml \
            $$_ts_project_dir/admin/services/serverless-layers.yml
            test -f $f && set -a ymls $f
        end
        if test -n "$ymls"
            sed -i.ts_bak -E 's/module-([a-z]+)((-+[a-z0-9]+)*)(.*)?$/module-\1'"$suffix"'\4/g' $ymls
            and command rm $ymls.ts_bak
        end

    else
        # add suffix to changed modules

        set -l changed_modules
        set -l services_dirs
        set -l merge_base (git merge-base origin/master HEAD)

        # find changed modules
        begin
            git diff --name-only $merge_base -- $$_ts_project_dir/{modules,services,admin/services,lib,schema}/
            string replace $$_ts_project_dir/ '' -- $_flag_service
        end | while read -l -L file
            switch $file
                case \*/package-lock.json
                    # ignore it
                case lib/\* schema/\*
                    contains libs $changed_modules || set -a changed_modules libs
                case modules/\*/\*
                    string match -q -r '^modules/(?<module_name>[^/]+)' $file
                    if not contains $module_name $changed_modules
                        set -a changed_modules $module_name
                    end
                case services/\* admin/services/\*
                    string match -q -r '(?<services_dir>.*\bservices\b)' $file
                    if not contains $services_dir $services_dirs; and test -d $$_ts_project_dir/$services_dir
                        set -a services_dirs $services_dir
                    end
            end
        end

        if test -n "$changed_modules"
            for d in $changed_modules
                string match -q -r '^# Layer: (?<module_name>\S+)' <$$_ts_project_dir/modules/$d/serverless.yml
                set -l _yml $$_ts_project_dir/modules/$d/serverless.yml
                sed -i.ts_bak -E 's/^service:.*$/service: '$module_name$suffix'/g' $_yml
                and command rm $_yml.ts_bak
                if test -n "$services_dirs"
                    set -l _layer_yml $$_ts_project_dir/$services_dirs/serverless-layers.yml
                    sed -i.ts_bak -E 's/cf:'$module_name'[^$]*\$/cf:'$module_name$suffix'-$/g' $_layer_yml
                    and command rm $_layer_yml.ts_bak
                end
            end
        end
    end
end

function _ts_modules_have_suffix -d 'check if any module already has suffix'
    for dir in $$_ts_project_dir/modules/*/
        string match -q -r '^service:\s*(?<service_name>[^\s]+)' <$dir/serverless.yml
        if test "$service_name" != "module-$dir"
            return 0
        end
    end
    return 1
end

function _ts_module_get_suffix -a name -d 'get module name suffix'
    if test -z "$name"
        set -l branch (git branch --show-current)
        switch "$branch"
        case master release 'release-*'
            # don't rename modules
        case \*
            set name $branch
        end
    end
    string replace -a -r '\W+' - -- $name
end
