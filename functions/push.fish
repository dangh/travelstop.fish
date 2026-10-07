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
        a/all \
        i/interactive \
        C/continue \
        force \
        'f/function=' \
        u/update-config \
        aws-s3-accelerate \
        'app=' \
        'org=' \
        'c/config=' \
        'e/exclude=+' \
        R/regex \
        'j/jobs=!_validate_int --min 1' \
        -- $ts_default_argv_push $argv
    or return 1

    # -j/--jobs: how many independent targets deploy at once (1 = strictly
    # sequential in list order, the pre-tier behavior)
    set -l jobs 4
    set -q _flag_jobs && set jobs $_flag_jobs

    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set default_region $_flag_region
    set -q _flag_config && set config $_flag_config
    set -a targets $argv

    # -a/--all: expand each base (or PWD if none) to its service dir + subservices
    if set -q _flag_all
        set -l bases $targets
        test -z "$bases" && set bases $PWD
        set -l expanded_targets
        for base in $bases
            # resolve a stack name to its service dir; dirs pass through
            set -l dir $base
            if not test -d "$dir"
                set -l yml (_ts_resolve_config "$base" "" | string split -f2 -- :)
                test -n "$yml"; or begin
                    _ts_log cannot resolve target: (magenta $base)
                    return 1
                end
                set dir (path dirname -- $yml)
            end
            set -l base_targets (_ts_push_all_targets "$dir")
            or return 1
            for t in $base_targets
                contains -- $t $expanded_targets || set -a expanded_targets $t
            end
        end
        set targets $expanded_targets
    end

    if test "$stage" = prod
        _ts_confirm_prod "continue pushing"
        or return 0
    end

    # verify the AWS session up-front: an expired login surfaces here at a clean
    # prompt instead of halting buried mid-deploy (and before any side-effects)
    _ts_ensure_session $aws_profile; or return 1

    # rename modules before deploy, restore on exit (normal or signal)
    _ts_push_rename_modules on
    function _ts_push_restore_modules -s SIGINT -s SIGTERM -s SIGHUP
        functions -e _ts_push_restore_modules
        # parallel deploy children live in their own process group under job
        # control, so a terminal Ctrl-C never reaches them: stop them here
        for p in $_ts_push_pids
            command kill -- -$p 2>/dev/null || command kill $p 2>/dev/null
        end
        set -e _ts_push_pids
        _ts_push_rename_modules off
    end

    if set -q _flag_continue
        # -C/--continue: resume a prior interrupted/failed run from saved state
        # (the resolved targets and their per-target success/failure status).
        set targets $_ts_push_state
        if test -z "$targets"
            _ts_log nothing to continue
            _ts_push_restore_modules
            return
        end
    else
        # push without any target/config/function
        test -z "$argv" && not set -q _flag_function && not set -q _flag_all && set -a targets .

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
            if test -z "$target_type"
                _ts_log cannot resolve target: (magenta $target)
                _ts_push_restore_modules
                return 1
            end
            set -a {$target_type}s "pending:$target_type:$__:$stage"
        end

        # re-order targets
        set targets $modules $services $functions

        # interactive: let the user delete/re-order resolved targets in $EDITOR
        if set -q _flag_interactive
            set targets (_ts_push_edit_targets $targets)
            or begin
                _ts_push_restore_modules
                return 1
            end
            if test -z "$targets"
                _ts_log no targets selected
                _ts_push_restore_modules
                return
            end
        end
    end

    # rename modules again to apply renamed modules for deploying targets
    set -l ymls
    for target in $targets
        echo $target | read -l -d : state target_type yml __
        set -a ymls $yml
    end
    _ts_push_rename_modules on -s$ymls

    set -l success_count 0
    set -l failure_count 0
    # count already-deployed targets carried over from a resumed run
    for t in $targets
        string match -q 'success:*' -- $t && set success_count (math $success_count + 1)
    end

    # persist resolved targets so an interrupted run can be resumed with -C
    _ts_push_save_state $targets

    # taskbar progress (OSC 9;4) - indeterminate until first item finishes
    if test (count $targets) -ge 1
        printf '\e]9;4;3;0\a'
    end

    # deploy tier by tier: targets inside a tier are independent and run
    # concurrently (up to -j jobs); tiers run in dependency order. targets the
    # user asks to retry form the next tier. see _ts_push_tiers for the order.
    set -l run_dir (_ts_push_run_dir)
    set -l tiers (_ts_push_tiers $jobs $targets)
    set -l aborted
    set -g _ts_push_pids
    while test (count $tiers) -gt 0
        set -l tier (string split ' ' -- $tiers[1])
        set -e tiers[1]

        for i in $tier
            echo $targets[$i] | read -l -d : state __
            set targets[$i] "running:$__"
        end
        _ts_progress $targets

        # launch: single job runs here (live output, tee'd to its log); a
        # multi-job tier runs each target in a child fish, output to its log
        set -l tier_logs
        set -l tier_names
        set -l pids
        for i in $tier
            echo $targets[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
            set -l fullname (_ts_push_fullname "$target_type" "$service_name" "$function_name" "$package_version" "$stage")
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
                    # serverless-web service (has serverless.yml, no
                    # serverless-resources.yml, uses the serverless-web plugin):
                    # deploy the web app instead of the CF stack.
                    if test -e "$working_dir"/serverless.yml \
                            && not test -e "$working_dir"/serverless-resources.yml \
                            && grep -q -- serverless-web "$working_dir"/serverless.yml
                        set deploy_cmd deploy web
                    end
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

            set -l log $run_dir/(printf '%02d-%s.log' $i $fullname)
            set -a tier_logs $log
            set -a tier_names $fullname
            if test (count $tier) -eq 1
                _ts_push_deploy "$target_type" "$service_name" "$working_dir" $deploy_cmd 2>&1 | tee $log
                echo $pipestatus[1] >$log.exit
            else
                # fish cannot background a function, so the child is a fresh
                # fish: it gets _ts_push_deploy from here and the rest (_ts_sls,
                # _ts_pm_install, build_libs, ...) from its own config
                while test (count $pids) -ge $jobs
                    wait -n $pids
                    set -l alive
                    for p in $pids
                        command kill -0 $p 2>/dev/null && set -a alive $p
                    end
                    set pids $alive
                end
                fish --init-command (functions _ts_push_deploy | string collect) \
                    -c '_ts_push_deploy $argv; echo $status >'(string escape -- $log.exit) \
                    -- "$target_type" "$service_name" "$working_dir" $deploy_cmd >$log 2>&1 &
                set -a pids $last_pid
                set -ga _ts_push_pids $last_pid
            end
        end
        test -n "$pids" && wait $pids
        set -g _ts_push_pids

        # collect: mark each target, then prompt for every failure in the tier
        set -l retry
        for k in (seq (count $tier))
            set -l i $tier[$k]
            set -l log $tier_logs[$k]
            set -l fullname $tier_names[$k]
            echo $targets[$i] | read -l -d : state __
            set -l deploy_status (cat $log.exit 2>/dev/null)
            test -n "$deploy_status" || set deploy_status 1

            if test $deploy_status -eq 0
                set success_count (math $success_count + 1)
                set targets[$i] "success:$__"
                _ts_push_save_state $targets
                printf '\e]9;4;1;%d\a' (_ts_push_percent $targets)
                continue
            end

            set targets[$i] "failure:$__"
            _ts_push_save_state $targets
            printf '\e]9;4;2;%d\a' (_ts_push_percent $targets)

            # Ctrl-C during deploy: fish keeps running the script after the
            # signal kills sls (exit status 128+signum). Treat that as an
            # interrupt and stop the whole run instead of prompting retry/abort.
            if test $deploy_status -ge 128
                set failure_count (math $failure_count + 1)
                set aborted 1
                _ts_log (red interrupted)
                break
            end

            # failure: show progress (and the log tail a background job hid),
            # then prompt. default is abort.
            _ts_progress $targets
            test (count $tier) -gt 1 && tail -n 20 $log
            # notify (native + pushover) that a deploy failed and needs input
            _ts_notify -t "push failed: $fullname" \
                -m 'deploy failed — waiting for [r]etry / [s]kip / [a]bort'
            read -l -n 1 -P (red 'push failed for')" $fullname"'. [r]etry / [s]kip / [a]bort? [a] ' answer
            switch $answer
                case R r retry
                    _ts_log retrying: (magenta $fullname)
                    set -a retry $i
                case S s skip
                    _ts_log skipping: (magenta $fullname)
                    set failure_count (math $failure_count + 1)
                case '*'
                    set failure_count (math $failure_count + 1)
                    set aborted 1
                    break
            end
        end

        test -n "$aborted" && break
        test -n "$retry" && set -p tiers (string join ' ' -- $retry)
    end
    set -e _ts_push_pids

    # an abort mid-tier leaves the rest of that tier marked running: they did
    # finish (we waited), but were never judged, so -C must redo them
    for i in (seq (count $targets))
        set targets[$i] (string replace -r '^running:' 'pending:' -- $targets[$i])
    end

    # resume state: clear it when everything is done, otherwise keep it and tell
    # the user how to pick up where this run stopped (after a failure or Ctrl-C)
    set -l remaining 0
    for t in $targets
        string match -q 'success:*' -- $t || set remaining (math $remaining + 1)
    end
    if test $remaining -eq 0
        _ts_push_clear_state
    else
        _ts_push_save_state $targets
        _ts_log (yellow $remaining) 'remaining — run' (green 'push -C') 'to continue'
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

function _ts_push_rename_modules -d "rename_modules unless \$ts_push_rename_modules disables it"
    # opt out of the branch-suffix renaming (e.g. deploying a shared branch that
    # must keep the plain module names)
    contains -- "$ts_push_rename_modules" 0 false no off && return 0
    rename_modules $argv
end

function _ts_push_save_state -d "persist resolved targets (with per-target status) for -C"
    set -g _ts_push_state $argv
end

function _ts_push_clear_state -d "drop the saved resume state"
    set -e _ts_push_state
end

function _ts_push_fullname -a target_type service_name function_name package_version stage -d "<service>-<STAGE>[-<function>|-<version>]"
    switch "$target_type"
        case function
            echo $service_name-(string upper $stage)-$function_name
        case service
            if test -n "$package_version"
                echo $service_name-(string upper $stage)-$package_version
            else
                echo $service_name-(string upper $stage)
            end
        case '*'
            echo $service_name-(string upper $stage)
    end
end

function _ts_push_percent -d "percent of targets in a final state (for OSC 9;4)"
    set -l done (string match -r '^(success|failure):' -- $argv | count)
    math -s0 "$done * 100 / "(count $argv)
end

function _ts_push_run_dir -d "make this run's log dir under \$XDG_RUNTIME_DIR/ts_push and point 'latest' at it"
    set -l root $XDG_RUNTIME_DIR
    test -n "$root" -a -d "$root" || set root /tmp
    mkdir -p $root/ts_push
    set -l dir (mktemp -d $root/ts_push/(date +%Y%m%d-%H%M%S)-XXXX)
    ln -sfn $dir $root/ts_push/latest
    echo $dir
end

function _ts_push_tiers -a jobs -d "group target indices into dependency tiers, one line per tier"
    # order that matters: modules (layers) -> *-resources stacks -> other
    # services, shallower dirs first (a parent stack before its subservices) ->
    # *monitoring* stacks -> functions. functions of one service share its
    # .serverless/ dir, so the n-th function of a service waits for the (n-1)-th.
    # -j 1 puts every target in its own tier, in list order. already-succeeded
    # targets (a -C resume) are left out.
    set -l targets $argv[2..]
    set -l entries # "<sort key> <index>"
    set -l seen_ymls
    for i in (seq (count $targets))
        echo $targets[$i] | read -l -d : state target_type serverless_yml service_name __
        test "$state" = success && continue
        set -l key
        if test "$jobs" -le 1
            set key (printf '%04d' $i)
        else
            switch $target_type
                case module
                    set key 0000
                case function
                    set -a seen_ymls $serverless_yml
                    set key 8(printf '%03d' (count (string match -- $serverless_yml $seen_ymls)))
                case '*'
                    if string match -q -- '*-resources' $service_name
                        set key 0001
                    else if string match -q -- '*monitoring*' $service_name
                        set key 5000
                    else
                        set key 1(printf '%03d' (count (string split / -- $serverless_yml)))
                    end
            end
        end
        set -a entries "$key $i"
    end

    set -l last
    set -l tier
    for entry in (printf '%s\n' $entries | sort -s -k1,1)
        echo $entry | read -l key i
        if test "$key" != "$last"
            test -n "$tier" && echo $tier
            set tier $i
            set last $key
        else
            set tier "$tier $i"
        end
    end
    test -n "$tier" && echo $tier
end

function _ts_push_deploy -a target_type service_name working_dir -d "install deps, then run one sls deploy (also runs inside a child fish)"
    set -l deploy_cmd $argv[4..]
    if test "$target_type" = module && string match -q -r module-libs -- $service_name
        build_libs --force
    else
        for d in "$working_dir" "$working_dir"/nodejs "$working_dir"/nodejs*/nodejs "$working_dir"/nodejs/node*
            if test -e "$d"/package.json
                # web app: install all deps; lambda code: target linux/x64/glibc
                set -l pm_flags --no-proxy
                string match -q -r '\bweb\b' -- "$d"
                or set -a pm_flags --os=linux --cpu=x64 --libc=glibc
                set -l install_cmd (_ts_pm_install "$d" $pm_flags $ts_npm_install_options)
                command env -C "$d" fish -P -c "
                    type -q nvm && nvm use > /dev/null
                    command $install_cmd
                "
            end
        end
    end
    _ts_sls --workdir "$working_dir" --with-env $deploy_cmd
end

function _ts_push_all_targets -a base -d "expand a dir to every service in it (or to the nearest enclosing service)"
    set -l project_dir
    set -q $_ts_project_dir && set project_dir $$_ts_project_dir

    test -n "$base" || set base $PWD
    set -l current_dir (path resolve -- $base)
    # a dir holding services (itself or below) is the root of the expansion, so
    # -a works from a plain parent dir too. only when it holds none do we walk
    # up to the nearest enclosing service dir.
    set -l stack_dirs (_ts_push_stack_dirs "$current_dir")
    while test -z "$stack_dirs"
        if test "$current_dir" = /
            set current_dir
            break
        end
        if test -n "$project_dir"; and test "$current_dir" = "$project_dir"
            set current_dir
            break
        end
        set current_dir (path dirname -- $current_dir)
        test -f "$current_dir/serverless.yml"
        and set stack_dirs (_ts_push_stack_dirs "$current_dir")
    end

    if test -z "$current_dir"
        _ts_log cannot resolve current service. run from a service directory
        return 1
    end
    set -l resource_dirs
    set -l main_dir
    set -l subservice_dirs
    set -l monitoring_dirs

    for dir in $stack_dirs
        if test "$dir" = "$current_dir"
            set main_dir $dir
        else
            set -l service_name (_ts_service_name "$dir/serverless.yml")
            if string match -q '*-resources' -- $service_name
                set -a resource_dirs $dir
            else if string match -q '*monitoring*' -- $service_name
                set -a monitoring_dirs $dir
            else
                set -a subservice_dirs $dir
            end
        end
    end

    # monitoring stacks deploy last (they observe the rest)
    set -l ordered_targets $resource_dirs
    test -n "$main_dir" && set -a ordered_targets $main_dir
    set -a ordered_targets $subservice_dirs $monitoring_dirs

    for dir in $ordered_targets
        if test -n "$project_dir"; and string match -q -- "$project_dir/*" "$dir"
            set -l offset (math (string length -- "$project_dir") + 2)
            echo (string sub -s $offset -- "$dir")
        else
            echo $dir
        end
    end
end

function _ts_push_stack_dirs -a dir -d "dirs of every serverless.yml at or below <dir>, node_modules pruned"
    find "$dir" -type d -name node_modules -prune -o -type f -name serverless.yml -print \
        | string replace -r '/serverless.yml$' '' | path sort
end

function _ts_push_edit_targets -d "edit resolved push targets in \$EDITOR; echoes kept targets in new order"
    set -l editor $EDITOR
    test -n "$editor" || set editor $VISUAL
    test -n "$editor" || set editor vi

    set -l tmp (mktemp -t ts_push.XXXXXX)
    begin
        echo '# travelstop push — reorder or delete lines, then save and close.'
        echo '# Targets deploy in dependency tiers (top to bottom only with -j 1). Delete a line to skip it. Keep the leading number.'
        for i in (seq (count $argv))
            echo $argv[$i] | read -l -d : state target_type serverless_yml service_name function_name __
            set -l label $service_name
            test -n "$function_name" && set label $service_name:$function_name
            printf '%d\t%s\t%s\n' $i $target_type $label
        end
    end >$tmp

    # stdout is captured by the caller's command substitution: send the editor's
    # screen output to stderr (the terminal) so it renders and nothing leaks into
    # the target list.
    command $editor $tmp >&2
    or begin
        rm -f $tmp
        _ts_log editor exited non-zero, aborting
        return 1
    end

    set -l result
    while read -l line
        # skip comments/blank; map the leading number back to the original target
        set -l idx (string match -r '^\s*(\d+)' -- $line)[2]
        test -n "$idx"; and test "$idx" -ge 1 -a "$idx" -le (count $argv)
        and set -a result $argv[$idx]
    end <$tmp
    rm -f $tmp

    for r in $result
        echo $r
    end
    return 0
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
