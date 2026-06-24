function push -d 'deploy CF stack/lambda function'
    set -l aws_profile $AWS_PROFILE
    set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
    set -l default_region $AWS_REGION
    set -l targets
    set -l config # config when pushing functions
    set -l modules
    set -l services
    set -l functions

    argparse -n 'sls deploy' \
        conceal \
        'aws-profile=' \
        's/stage=' \
        'r/region=' \
        'p/package=' \
        v/verbose \
        force \
        'f/function=' \
        u/update-config \
        aws-s3-accelerate \
        'app=' \
        'org=' \
        'c/config=' \
        'e/exclude=+' \
        R/regex \
        -- $ts_default_argv_push $argv
    or return 1

    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set default_region $_flag_region
    set -q _flag_config && set config $_flag_config
    set -a targets $argv

    if contains -- all $targets
        set -l all_targets (_ts_push_all_targets)
        or return 1
        set -l expanded_targets
        for target in $targets
            if test "$target" = all
                for all_target in $all_targets
                    if not contains -- $all_target $expanded_targets
                        set -a expanded_targets $all_target
                    end
                end
            else if not contains -- $target $expanded_targets
                set -a expanded_targets $target
            end
        end
        set targets $expanded_targets
    end

    if test "$stage" = prod
        while true
            read -l -P 'Do you want to continue pushing to PROD? [y/N] ' confirm
            switch $confirm
                case Y y
                    break
                case '' N n
                    return
            end
        end
    end

    # rename modules before deploy, restore on exit (normal or signal)
    rename_modules on
    function _ts_push_restore_modules -s SIGINT -s SIGTERM -s SIGHUP
        functions -e _ts_push_restore_modules
        rename_modules off
    end

    # push without any target/config/function
    test -z "$argv" -a -z "$function" && set -a targets .

    set -l match_flags
    set -q _flag_regex && set match_flags -r
    set -l patterns $targets
    set targets

    set -l all_stacks (_ts_modules | sort) (_ts_substacks | sort) (_ts_functions | sort)
    set -l matched_patterns
    for pattern in $patterns
        if string match -q '!*' $pattern
            set -a _flag_exclude (string sub -s 2 $pattern)
            set -a matched_patterns $pattern
            continue
        end
        string match $match_flags -a "$pattern" $all_stacks | while read -l stack
            if not contains $stack $targets
                set -a targets $stack
            end
            set -a matched_patterns $pattern
        end
    end
    for pattern in $patterns
        if contains $pattern $matched_patterns
            continue
        end
        set -a targets $pattern
    end
    for pattern in $_flag_exclude
        set targets (string match $match_flags -v -a "$pattern" $targets)
    end

    for target in $targets
        _ts_resolve_config "$target" "$config" | read -l -d : target_type __
        set -a {$target_type}s "pending:$target_type:$__:$stage"
    end

    # re-order targets
    set targets $modules $services $functions

    # rename modules again to apply renamed modules for deploying targets
    set -l ymls
    for target in $targets
        echo $target | read -l -d : state target_type yml __
        set -a ymls $yml
    end
    rename_modules on -s$ymls

    set -l success_count 0
    set -l failure_count 0

    # taskbar progress (OSC 9;4) - indeterminate until first item finishes
    if test (count $targets) -ge 1
        printf '\e]9;4;3;0\a'
    end

    # deploy
    for i in (seq (count $targets))
        echo $targets[$i] | read -l -d : state __
        echo $__ | read -l -d : target_type serverless_yml service_name function_name package_version region stage
        set -l fullname
        switch "$target_type"
            case function
                set fullname $service_name-(string upper $stage)-$function_name
            case service
                if test -n "$package_version"
                    set fullname $service_name-(string upper $stage)-$package_version
                else
                    set fullname $service_name-(string upper $stage)
                end
        end

        # update progress
        set targets[$i] "running:$__"
        _ts_progress $targets

        set -l working_dir (dirname $serverless_yml)
        set -l deploy_cmd deploy
        switch $target_type
            case function
                set -a deploy_cmd function -f $function_name
                test -n "$aws_profile" && set -a deploy_cmd --aws-profile $aws_profile
                test -n "$stage" && set -a deploy_cmd -s $stage
                if test -n "$region"
                    set -a deploy_cmd -r $region
                else if test -n "$default_region"
                    set -a deploy_cmd -r $default_region
                end
                set -q _flag_force && set -a deploy_cmd --force
                set -q _flag_update_config && set -a deploy_cmd -u
            case \*
                set -q _flag_conceal && set -a deploy_cmd --conceal
                test -n "$aws_profile" && set -a deploy_cmd --aws-profile $aws_profile
                test -n "$stage" && set -a deploy_cmd -s $stage
                if test -n "$region"
                    set -a deploy_cmd -r $region
                else if test -n "$default_region"
                    set -a deploy_cmd -r $default_region
                end
                test -n "$_flag_package" && set -a deploy_cmd -p $_flag_package
                set -q _flag_verbose && set -a deploy_cmd -v
                set -q _flag_force && set -a deploy_cmd --force
                set -q _flag_aws_s3_accelerate && set -a deploy_cmd --aws-s3-accelerate
                test -n "$_flag_app" && set -a deploy_cmd --app $_flag_app
                test -n "$_flag_org" && set -a deploy_cmd --org $_flag_org
                test (path basename $serverless_yml) != serverless.yml && set -a deploy_cmd -c (path basename $serverless_yml)
        end
        test "$target_type" = function \
            && _ts_log deploying function: (magenta $fullname) \
            || _ts_log deploying stack: (magenta $fullname)
        _ts_log working directory: (blue $working_dir)

        if test "$target_type" = module && string match -q -r module-libs $service_name
            build_libs --force
        else
            for d in "$working_dir" "$working_dir"/nodejs "$working_dir"/nodejs*/nodejs "$working_dir"/nodejs/node*
                if test -e "$d"/package.json
                    command env -C "$d" fish -P -c "
                        type -q nvm && nvm use > /dev/null
                        if string match -q -r \\\\bweb\\\\b -- \"\$PWD\"
                            npm i --no-proxy \$ts_npm_install_options
                        else
                            npm i --no-proxy --os=linux --cpu=x64 --libc=glibc \$ts_npm_install_options
                        end
                    "
                end
            end
        end
        _ts_sls -C "$working_dir" -E $deploy_cmd
        set -l result $status

        # update counters
        test $result -eq 0 \
            && set success_count (math $success_count + 1) \
            || set failure_count (math $failure_count + 1)

        # update progress
        test $result -eq 0 \
            && set targets[$i] "success:$__" \
            || set targets[$i] "failure:$__"

        # taskbar progress (OSC 9;4) - switch from indeterminate to normal/error with percentage
        if test $result -eq 0
            printf '\e]9;4;1;%d\a' (math "$i * 100 / "(count $targets))
        else
            printf '\e]9;4;2;%d\a' (math "$i * 100 / "(count $targets))
        end

        test $result -eq 0 || break
    end

    # summary notification (single per push, only after everything is done)
    if test (count $targets) -ge 1
        _ts_progress $targets

        set -l branch (git branch --show-current 2>/dev/null)
        test -n "$branch" || set branch deploy
        set -l notif_title (string upper -- $stage)" $branch"

        set -l target_list
        for t in $targets
            echo $t | read -l -d : state target_type serverless_yml service_name function_name package_version region tstage
            set -l fullname $service_name
            switch "$target_type"
                case function
                    set fullname $service_name-$function_name
                case service
                    test -n "$package_version" && set fullname $service_name-$package_version
            end
            set -l bullet
            switch "$state"
                case success
                    set bullet ✅
                case '*'
                    set bullet ❌
            end
            set -a target_list "$bullet $fullname"
        end

        set -l notif_summary "success: $success_count, failure: $failure_count"
        set -l notif_details (string join \n -- $target_list | string collect)

        _ts_notify -t "$notif_title" -m "$notif_summary" -d "$notif_details"
    end

    # clear taskbar progress (OSC 9;4)
    if test (count $targets) -ge 1
        printf '\e]9;4;0\a'
    end

    # restore module names (signal-handler path triggers the same body)
    _ts_push_restore_modules
end

function _ts_push_all_targets -d "expand push all to current service and subservices"
    set -l project_dir
    set -q $_ts_project_dir && set project_dir $$_ts_project_dir

    set -l current_dir $PWD
    while true
        if test -f "$current_dir/serverless.yml"
            break
        end
        if test "$current_dir" = /
            set current_dir
            break
        end
        if test -n "$project_dir"; and test "$current_dir" = "$project_dir"
            set current_dir
            break
        end
        set current_dir (path dirname -- $current_dir)
    end

    if test -z "$current_dir"
        _ts_log cannot resolve current service. run from a service directory
        return 1
    end

    set -l stack_dirs (find "$current_dir" -type d -name node_modules -prune -o -type f -name serverless.yml -print | string replace -r '/serverless.yml$' '' | path sort)
    set -l resource_dirs main_dir subservice_dirs

    for dir in $stack_dirs
        if test "$dir" = "$current_dir"
            set main_dir $dir
        else
            set -l service_name (_ts_service_name "$dir/serverless.yml")
            if string match -q '*-resources' -- $service_name
                set -a resource_dirs $dir
            else
                set -a subservice_dirs $dir
            end
        end
    end

    set -l ordered_targets $resource_dirs
    test -n "$main_dir" && set -a ordered_targets $main_dir
    set -a ordered_targets $subservice_dirs

    for dir in $ordered_targets
        if test -n "$project_dir"; and string match -q -- "$project_dir/*" "$dir"
            set -l offset (math (string length -- "$project_dir") + 2)
            echo (string sub -s $offset -- "$dir")
        else
            echo $dir
        end
    end
end

function _ts_progress
    set -l count (count $argv)
    set -l color_pending ansi-escape
    set -l color_running magenta
    set -l color_success green
    set -l color_failure red
    set -l caret_pending ' '
    set -l caret_running (magenta '▶︎')
    set -l caret_success ' '
    set -l caret_failure ' '
    set -l indent (test $count -gt 9 && echo 2 || echo 1)
    echo $argv[-1] | read -l -d : state __
    if test "$state" = success -o "$state" = failure
        _ts_log (yellow $count) 'stacks/functions deployed'
    else
        _ts_log deploying (yellow $count) stacks/functions
    end
    for i in (seq $count)
        echo $argv[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
        set -l index (string sub -s -$indent " $i")
        set -l caret caret_$state
        set -l color color_$state
        set -l fullname $service_name-(string upper $stage)
        test -n "$package_version" && set package_version (dim '-')(yellow $package_version)
        if test "$target_type" = function
            echo $$caret (dim $index.) ($$color $fullname-$function_name)
        else
            echo $$caret (dim $index.) ($$color $fullname)$package_version
        end
    end
end

function _ts_resolve_config -a target config_file -d "target_type:serverless_yml:service_name:function_name:package_version:region"
    set -l target_type
    set -l service_name
    set -l function_name
    set -l package_version
    set -l serverless_yml
    set -l package_json
    set -l changelog_md
    set -l region

    if test -n "$config_file"
        set serverless_yml (realpath "$config_file")
    else if test -f "$target/serverless.yml"
        set serverless_yml (realpath "$target/serverless.yml")
    else if test -f "$target/serverless-waf.yml"
        set serverless_yml (realpath "$target/serverless-waf.yml")
    else if test -f "$$_ts_project_dir/$target/serverless.yml"
        set serverless_yml (realpath "$$_ts_project_dir/$target/serverless.yml")
    else if test -f "$PWD/serverless.yml"
        set serverless_yml "$PWD/serverless.yml"
    end

    test -n "$serverless_yml" || return 1
    string match -q -r '^\s*region:\s*\'(?<region>[a-z0-9-]+)\'' <$serverless_yml

    if test -f (dirname "$serverless_yml")/package.json
        set package_json (dirname "$serverless_yml")/package.json
    else if test -f "$$_ts_project_dir/modules/$target/nodejs/package.json"
        set package_json (realpath "$$_ts_project_dir/modules/$target/nodejs/package.json")
    else if test -f (dirname "$serverless_yml")/CHANGELOG.md
        set changelog_md (dirname "$serverless_yml")/CHANGELOG.md
    end

    if contains $target (_ts_functions "$serverless_yml")
        set target_type function
        set function_name $target
    else
        string match -q -r /modules/ "$serverless_yml" \
            && set target_type module \
            || set target_type service
    end
    string match -q -r '^service:\s*(?<service_name>[^\s]*)' <$serverless_yml
    if test -n "$package_json"
        string match -q -r '^\s*"version":\s*"(?<package_version>[^"]*)"' <$package_json
    else if test -n "$changelog_md"
        string match -q -r '# (?<package_version>\d+(\.\d+)+)' <$changelog_md
    end

    echo "$target_type:$serverless_yml:$service_name:$function_name:$package_version:$region"
end
