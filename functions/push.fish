function push -d 'deploy CF stack/lambda function'
    set -l aws_profile $AWS_PROFILE
    set -l stage (string replace -r '.*@' '' -- $AWS_PROFILE)
    set -l default_region $AWS_REGION
    set -l targets
    set -l config # config when pushing functions
    set -l modules
    set -l services
    set -l cdks
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
        no-tmux \
        -- $ts_default_argv_push $argv
    or return 1

    # how many independent targets deploy at once
    set -l jobs 4

    set -q _flag_aws_profile && set aws_profile $_flag_aws_profile
    set -q _flag_stage && set stage $_flag_stage
    set -q _flag_region && set default_region $_flag_region
    # CDK apps take their region from the environment, not a flag
    set -q _flag_region && set -lx AWS_REGION $_flag_region
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
        # the tmux view's server (and every deploy in it) goes too
        if set -q _ts_push_tmux_socket
            _ts_push_tmux kill-server 2>/dev/null
            set -e _ts_push_tmux_socket
        end
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
        set targets $modules $services $cdks $functions

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
    # concurrently (up to $jobs); tiers run in dependency order. targets the
    # user asks to retry form the next tier. see _ts_push_tiers for the order.
    set -l run_dir (_ts_push_run_dir)
    or begin
        printf '\e]9;4;0\a'
        _ts_push_restore_modules
        return 1
    end
    set -l tiers (_ts_push_tiers $targets)
    set -l aborted
    # tmux view: the same tiers deploy in a private tmux session instead (see
    # _ts_push_tmux_run), which leaves nothing for the loop below
    if not set -q _flag_no_tmux; and _ts_push_tmux_wanted $targets
        for i in (seq (count $targets))
            _ts_push_build_cmd $targets[$i] >$run_dir/(printf '%02d' $i).cmd
        end
        if _ts_push_tmux_run $run_dir $jobs $targets
            test -s $run_dir/state && set targets (cat $run_dir/state)
            set success_count (string match -- 'success:*' $targets | count)
            # failures of this run only (a -C resume carries older ones)
            touch $run_dir/judged
            set failure_count (string match -- failure (cat $run_dir/judged) | count)
            set tiers
        end
    end
    set -g _ts_push_pids
    while test (count $tiers) -gt 0
        set -l tier (string split ' ' -- $tiers[1])
        set -e tiers[1]

        # only the first $jobs targets start right away; the rest of the tier is
        # marked running when its slot frees up
        for i in $tier[1..$jobs]
            echo $targets[$i] | read -l -d : state __
            set targets[$i] "running:$__"
        end
        _ts_progress $targets

        # launch: single job runs here (live output, tee'd to its log); a
        # multi-job tier runs each target in a child fish, output to its log
        set -l tier_logs
        set -l tier_names
        set -l pids
        set -l pid_ks # position in $tier of each pid
        for k in (seq (count $tier))
            set -l i $tier[$k]
            echo $targets[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
            set -l fullname (_ts_push_fullname "$target_type" "$service_name" "$function_name" "$package_version" "$stage")
            set -l working_dir (dirname $serverless_yml)
            set -l cmd (_ts_push_build_cmd $targets[$i])
            set -l runner $cmd[1]
            set -l deploy_cmd $cmd[2..]

            # wait for a free slot (at most $jobs deploys at once) before this
            # target is announced as deploying
            _ts_push_wait_slots $jobs
            set targets[$i] (string replace -r '^[a-z]+:' 'running:' -- $targets[$i])

            test "$target_type" = function \
                && _ts_log deploying function: (magenta $fullname) \
                || _ts_log deploying stack: (magenta $fullname)
            _ts_log working directory: (blue $working_dir)

            set -l log $run_dir/(printf '%02d-%s.log' $i $fullname)
            set -a tier_logs $log
            set -a tier_names $fullname
            if test (count $tier) -eq 1
                _ts_push_deploy "$target_type" "$service_name" "$working_dir" $runner $deploy_cmd 2>&1 | tee $log
                echo $pipestatus[1] >$log.exit
                _ts_push_done $k
            else
                # fish cannot background a function, so the child is a fresh
                # fish: it gets _ts_push_deploy from here and the rest (_ts_sls,
                # _ts_pm_install, build_libs, ...) from its own config
                fish --init-command (functions _ts_push_deploy | string collect) \
                    -c '_ts_push_deploy $argv; echo $status >'(string escape -- $log.exit) \
                    -- "$target_type" "$service_name" "$working_dir" $runner $deploy_cmd >$log 2>&1 &
                set -a pids $last_pid
                set -a pid_ks $k
                set -ga _ts_push_pids $last_pid
            end
        end
        _ts_push_wait_slots 1
        set -g _ts_push_pids

        # every target is marked done by now: prompt for each failure
        set -l retry
        for k in (seq (count $tier))
            set -l i $tier[$k]
            set -l log $tier_logs[$k]
            set -l fullname $tier_names[$k]
            string match -q 'success:*' -- $targets[$i] && continue
            set -l deploy_status (cat $log.exit 2>/dev/null)
            test -n "$deploy_status" || set deploy_status 1

            # Ctrl-C during deploy: fish keeps running the script after the
            # signal kills sls (exit status 128+signum). Treat that as an
            # interrupt and stop the whole run instead of prompting retry/abort.
            if test $deploy_status -ge 128
                set failure_count (math $failure_count + 1)
                set aborted 1
                _ts_log (red interrupted)
                break
            end

            # failure: show the log tail a background job hid, then prompt.
            # default is abort.
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
        _ts_progress --final $targets

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

    # restore module names (unless a signal already ran the handler, which
    # erases itself)
    functions -q _ts_push_restore_modules && _ts_push_restore_modules
end

function _ts_push_build_cmd -S -d "print the runner and the deploy args of target \$argv[1], one per line (reads push's flags)"
    echo $argv[1] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
    set -l working_dir (dirname $serverless_yml)
    set -l runner _ts_sls
    set -l deploy_cmd deploy
    switch $target_type
        case cdk
            # every stack of the app, in its dependency order. no approval
            # prompt: a parallel deploy has no terminal, and prod was already
            # confirmed up-front
            set runner _ts_cdk
            set -a deploy_cmd --all --require-approval never
            test -n "$stage" && set -a deploy_cmd -c stage=$stage
            test -n "$aws_profile" && set -a deploy_cmd --profile $aws_profile
            set -q _flag_verbose && set -a deploy_cmd --verbose
            set -q _flag_force && set -a deploy_cmd --force
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
            # serverless-resources.yml, uses the serverless-web plugin): deploy
            # the web app instead of the CF stack.
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
    printf '%s\n' $runner $deploy_cmd
end

function _ts_push_wait_slots -S -d "wait until fewer than \$argv[1] deploys run, marking each finished one done (runs in push's scope)"
    while test (count $pids) -ge $argv[1]
        wait -n $pids
        set -l alive_pids
        set -l alive_ks
        for _n in (seq (count $pids))
            if command kill -0 $pids[$_n] 2>/dev/null
                set -a alive_pids $pids[$_n]
                set -a alive_ks $pid_ks[$_n]
            else
                _ts_push_done $pid_ks[$_n]
            end
        end
        set pids $alive_pids
        set pid_ks $alive_ks
    end
end

function _ts_push_done -S -d "mark the \$argv[1]-th target of the tier success/failure from its exit file and redraw the progress (runs in push's scope)"
    set -l _i $tier[$argv[1]]
    set -l _status (cat $tier_logs[$argv[1]].exit 2>/dev/null)
    echo $targets[$_i] | read -l -d : _state _rest
    if test "$_status" = 0
        set success_count (math $success_count + 1)
        set targets[$_i] "success:$_rest"
        printf '\e]9;4;1;%d\a' (_ts_push_percent $targets)
    else
        set targets[$_i] "failure:$_rest"
        printf '\e]9;4;2;%d\a' (_ts_push_percent $targets)
    end
    _ts_push_save_state $targets
    _ts_progress $targets
end

function _ts_push_rename_modules -d "rename_modules unless \$ts_push_rename_modules disables it; off only once no other push of this project runs"
    # opt out of the branch-suffix renaming (e.g. deploying a shared branch that
    # must keep the plain module names)
    contains -- "$ts_push_rename_modules" 0 false no off && return 0
    # `off` strips every suffix: another push of the same checkout still
    # deploying would read the plain module names. each push registers its pid
    # per project; the last one out restores (dead pids don't count)
    set -l project
    set -q $_ts_project_dir && set project $$_ts_project_dir
    test -n "$project" || set project $PWD
    set -l pushes
    if set -l home (_ts_push_home)
        set pushes $home/pushes/(string escape --style=var -- (path resolve -- $project))
        mkdir -p -m 700 $pushes 2>/dev/null
        test -L $home/pushes -o -L $pushes; or not test -O $pushes
        and set pushes
    end
    # no registry of ours (see _ts_push_home): rename/restore as before
    if test -n "$pushes"
        switch "$argv[1]"
            case on
                touch $pushes/$fish_pid
            case off
                command rm -f -- $pushes/$fish_pid
                for f in $pushes/*
                    # only our pid files
                    set -l pid (path basename -- $f)
                    string match -qr '^[0-9]+$' -- $pid; and test -f $f; and not test -L $f
                    or continue
                    if command kill -0 $pid 2>/dev/null
                        _ts_log another push of this project still runs \(pid $pid\): module names stay renamed
                        return 0
                    end
                    command rm -f -- $f
                end
        end
    end
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

function _ts_push_tmux -d "tmux on push's private server: its own socket, no user config"
    command tmux -L $_ts_push_tmux_socket -f /dev/null $argv
end

function _ts_push_tmux_conf -a nested -d "print the tmux config of push's view: defaults, the user's \$ts_push_tmux_conf, then what the view needs"
    set -l user_conf $ts_push_tmux_conf
    if test -z "$user_conf"
        set -l config_home $XDG_CONFIG_HOME
        test -n "$config_home" || set config_home ~/.config
        set user_conf $config_home/travelstop/push.tmux.conf
    end
    # nested in the user's tmux, theirs takes the prefix: press it twice
    set -l prefix '#{prefix}'
    test -n "$nested" && set prefix '#{prefix} #{prefix}'
    # pane header: [slot] state icon and the target's manifest, on the
    # state's @ts_header_<state> style; bold in the focused pane
    set -l style '#{@ts_header_idle}'
    for state in stopped prompt failure success running
        set style '#{?#{==:#{@ts_state},'$state'},#{@ts_header_'$state'},'$style'}'
    end
    set -l border '#['$style']#{?pane_active,#[bold],} '
    set -a border '#{?@ts_slot,[#{@ts_slot}] ,}'
    set -a border '#{?#{==:#{@ts_state},running},▶ ,}'
    set -a border '#{?#{==:#{@ts_state},success},✓ ,}'
    set -a border '#{?#{==:#{@ts_state},failure},✗ ,}'
    set -a border '#{?#{==:#{@ts_state},prompt},? ,}'
    set -a border '#{?#{==:#{@ts_state},stopped},■ ,}'
    set -a border '#{@ts_title} #[default]'
    printf '%s\n' \
        '# defaults: change any of them in '$user_conf \
        'set -g default-terminal tmux-256color' \
        'set -g escape-time 0' \
        'set -g focus-events on' \
        'set -g history-limit 50000' \
        'set -g mouse on' \
        'set -g set-clipboard on' \
        'set -g pane-border-lines heavy' \
        'set -g pane-border-style fg=colour240' \
        'set -g pane-active-border-style fg=magenta,bold' \
        '# pane header colors by state' \
        "set -g @ts_header_idle 'bg=colour238,fg=colour250'" \
        "set -g @ts_header_running 'bg=magenta,fg=black'" \
        "set -g @ts_header_success 'bg=green,fg=black'" \
        "set -g @ts_header_failure 'bg=red,fg=white'" \
        "set -g @ts_header_prompt 'bg=red,fg=white'" \
        "set -g @ts_header_stopped 'bg=yellow,fg=black'" \
        'set -g status-style bg=default,fg=colour245' \
        "set -g status-left ' push '" \
        "set -g status-right 'click: focus · wheel: scroll · $prefix [: scroll mode '" \
        'set -g status-right-length 80' \
        "set -g window-status-format ''" \
        "set -g window-status-current-format ''" \
        '' \
        '# yours' \
        "source-file -q '$user_conf'" \
        '' \
        '# what the view needs: finished panes keep their output and exit status;' \
        '# no "exited" line under it (it scrolls the first line away), the header' \
        '# shows the result; no detach or suspend, push wraps up when it closes;' \
        '# notifications pass through to the terminal' \
        'set -g remain-on-exit on' \
        "set -g remain-on-exit-format ''" \
        'set -g pane-border-status top' \
        "set -g pane-border-format '"(string join '' -- $border)"'" \
        'set -g allow-passthrough on' \
        'unbind d' \
        'unbind D' \
        'unbind C-z'
end

function _ts_push_widest_tier -d "how many of targets \$argv can deploy at once (the largest tier)"
    set -l widest 0
    for tier in (_ts_push_tiers $argv)
        set -l n (count (string split ' ' -- $tier))
        test $n -gt $widest && set widest $n
    end
    echo $widest
end

function _ts_push_tmux_wanted -d "whether push shows the deploys of targets \$argv in a tmux view"
    contains -- "$ts_push_tmux" 0 false no off && return 1
    command -q tmux || return 1
    # nothing ever deploys alongside another one (a single target, a module
    # then its service, functions of one service): deploy right here
    test (_ts_push_widest_tier $argv) -ge 2 || return 1
    set -q TS_PUSH_TMUX_TEST && return 0
    isatty stdin && isatty stdout
end

function _ts_push_tmux_run -a run_dir jobs -d "deploy the targets in a private tmux session and attach to it; leaves their final state in <run_dir>/state"
    set -l targets $argv[3..]
    # a server of our own (not the user's default one, so their `tmux ls`
    # never shows it), started without their tmux.conf. exported: the
    # coordinator and the panes talk to it too
    set -gx _ts_push_tmux_socket ts_push_$fish_pid
    # inside the user's tmux the view is nested: notifications need wrapping
    # for both servers, and the outer one owns the plain prefix
    set -l nested
    set -q TMUX && set nested 1 && set -gx _ts_push_outer_tmux 1
    set -l self (functions --details _ts_push_tmux_run)

    # files the coordinator and the panes read: the targets, and per target
    # its deploy command (written by push) and its pane header, the manifest
    # relative to the project root (a cdk app: its dir)
    printf '%s\n' $targets >$run_dir/targets
    set -l root
    set -q $_ts_project_dir && set root $$_ts_project_dir
    test -n "$root" || set root (git rev-parse --show-toplevel 2>/dev/null)
    test -n "$root" && set root (path resolve -- $root)
    set -l name_width 0
    for i in (seq (count $targets))
        echo $targets[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
        set -l title (path resolve -- $serverless_yml)
        test "$target_type" = cdk && set title (path dirname -- $title)
        test -n "$root" && set title (string replace -- "$root/" '' $title)
        test -n "$function_name" && set title $title:$function_name
        echo $title >$run_dir/(printf '%02d' $i).title
        set -l len (string length -- $service_name-$stage-$function_name-$package_version)
        test $len -gt $name_width && set name_width $len
    end

    set -l width 200
    set -l height 50
    if isatty stdout
        test -n "$COLUMNS" && set width $COLUMNS
        test -n "$LINES" && set height $LINES
    end
    # stack list: wide enough for "▶︎ 12. <name> [4] retry?" (longer lines are
    # cut), 30 columns up to 40% of the width
    set -l list_width (math "max(30, $name_width + 20)")
    set list_width (math -s0 "min($list_width, $width * 0.4)")

    # its own config (never the user's tmux.conf): the defaults, then
    # $ts_push_tmux_conf, then what the view needs (see _ts_push_tmux_conf)
    _ts_push_tmux_conf $nested >$run_dir/tmux.conf
    command tmux -L $_ts_push_tmux_socket -f $run_dir/tmux.conf \
        new-session -d -s push -x $width -y $height tail -f /dev/null
    or begin
        set -e _ts_push_tmux_socket _ts_push_outer_tmux
        return 1
    end

    # the stack list on the left, then deploy panes ("slots") in 2 rows of
    # 2 columns (2 slots: 2 full-height columns), listed row by row: one per
    # target that can deploy at once, up to $jobs
    set -l n (math "min($jobs, "(_ts_push_widest_tier $targets)")")
    set -l cols 2
    # a narrow terminal: a 30-column list leaves the deploys more room
    set -l area (math $width - $list_width - 1)
    if test $area -lt 80
        set list_width (math "min($list_width, 30)")
        set area (math $width - $list_width - 1)
    end
    set -l left (_ts_push_tmux display -p -t push '#{pane_id}')
    # tmux leaves its socket file behind: removed once the run is over
    set -l socket_path (_ts_push_tmux display -p '#{socket_path}')
    _ts_push_tmux set -p -t $left @ts_title stacks
    set -l columns (_ts_push_tmux split-window -h -d -t $left -l $area -P -F '#{pane_id}' tail -f /dev/null)
    while test (count $columns) -lt $cols
        # the last column holds k columns' worth of space: give k-1 away
        set -l k (math $cols - (count $columns) + 1)
        set -l column (_ts_push_tmux split-window -h -d -t $columns[-1] -l (math -s0 "($k - 1) * 100 / $k")% -P -F '#{pane_id}' tail -f /dev/null)
        test -n "$column" || break # no room left
        set -a columns $column
    end
    set -l bottoms
    for c in $columns
        test (math (count $columns) + (count $bottoms)) -lt $n || break
        set -l bottom (_ts_push_tmux split-window -v -d -t $c -l 50% -P -F '#{pane_id}' tail -f /dev/null)
        test -n "$bottom" || break
        set -a bottoms $bottom
    end
    set -l slots $columns $bottoms
    # each slot is a deploy lane for the whole run: it deploys one target
    # after another, earlier output stays in its scrollback
    for k in (seq (count $slots))
        _ts_push_tmux set -p -t $slots[$k] @ts_title idle \; set -p -t $slots[$k] @ts_slot $k
        _ts_push_tmux respawn-pane -k -t $slots[$k] \
            fish --init-command "source "(string escape -- $self) -c '_ts_push_tmux_lane $argv' -- $run_dir $k
    end
    printf '%s\n' $slots >$run_dir/slots

    _ts_push_tmux respawn-pane -k -t $left \
        fish --init-command "source "(string escape -- $self) -c '_ts_push_tmux_main $argv' -- $run_dir
    _ts_push_tmux select-pane -t $left

    # attach in this terminal (nested when already inside tmux); the
    # coordinator starts deploying once a client is attached. attach again
    # if the client goes away while the run is on
    while _ts_push_tmux has-session -t push 2>/dev/null
        if set -q TS_PUSH_TMUX_TEST
            sleep 0.2
            continue
        end
        env -u TMUX tmux -L $_ts_push_tmux_socket attach -t push
        and continue
        # attach failed (no usable terminal) or the run just ended
        _ts_push_tmux has-session -t push 2>/dev/null || break
        _ts_push_tmux kill-server
        if not test -e $run_dir/started
            # nothing deployed yet: push deploys without the view
            test -S "$socket_path" && command rm -f -- $socket_path
            set -e _ts_push_tmux_socket _ts_push_outer_tmux
            return 1
        end
    end
    test -S "$socket_path" && command rm -f -- $socket_path
    set -e _ts_push_tmux_socket _ts_push_outer_tmux
    return 0
end

function _ts_push_tmux_main -a run_dir -d "stack list pane of push's tmux view: deploy the targets tier by tier into the other panes"
    set -l self (functions --details _ts_push_tmux_main)
    set -l targets (cat $run_dir/targets)
    set -l slots (cat $run_dir/slots)
    set -l busy # per slot: index of the target it deploys, 0 when free
    for s in $slots
        set -a busy 0
    end
    set -l logs
    for t in $targets
        echo $t | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
        set -a logs $run_dir/(printf '%02d-%s.log' (math (count $logs) + 1) (_ts_push_fullname "$target_type" "$service_name" "$function_name" "$package_version" "$stage"))
    end

    # Ctrl-C here stops the whole run (a deploy pane's Ctrl-C stops only it)
    function _ts_push_tmux_on_int --on-signal SIGINT
        set -g _ts_push_tmux_stop 1
    end

    set -l aborted
    set -l prompts
    set -l ended # prompting panes ended after an abort
    set -l progress_flags # --final for the closing screen
    set -l hint 'Ctrl-C here stops every deploy'
    _ts_push_tmux_draw $hint
    # deploy only once someone watches (push attaches right after this starts)
    if not set -q TS_PUSH_TMUX_TEST
        while test (_ts_push_tmux display -p -t push '#{session_attached}') = 0
            sleep 0.1
        end
    end
    touch $run_dir/started

    set -l tiers (_ts_push_tiers $targets)
    while test (count $tiers) -gt 0
        set -l queue (string split ' ' -- $tiers[1])
        set -e tiers[1]
        while test (count $queue) -gt 0; or string match -qv 0 -- $busy
            set -l changed
            # stop: deploys get a Ctrl-C and stay pending for push -C (also
            # after an abort, which only stops new deploys)
            if set -q _ts_push_tmux_stop; and test "$aborted" != stopped
                set aborted stopped
                touch $run_dir/abort
                for s in (seq (count $slots))
                    test $busy[$s] = 0 || _ts_push_tmux send-keys -t $slots[$s] C-c
                end
            end
            test -n "$aborted" && set queue

            # start queued targets in free panes
            for s in (seq (count $slots))
                test (count $queue) -gt 0 || break
                test $busy[$s] = 0 || continue
                set -l i $queue[1]
                set -e queue[1]
                set busy[$s] $i
                set targets[$i] (string replace -r '^[a-z]+:' 'running:' -- $targets[$i])
                _ts_push_tmux set -p -t $slots[$s] @ts_title (cat $run_dir/(printf '%02d' $i).title) \; \
                    set -p -t $slots[$s] @ts_state running
                # the lane picks it up (written whole, then moved in place)
                echo $i $logs[$i] >$run_dir/lane-$s.job.tmp
                mv $run_dir/lane-$s.job.tmp $run_dir/lane-$s.job
                set changed 1
            end

            # finished targets: the lane leaves their exit status. a lane that
            # died (it should not) fails its target and starts over
            for s in (seq (count $slots))
                set -l i $busy[$s]
                test $i = 0 && continue
                set -l st
                if test -e $run_dir/lane-$s.result
                    read st <$run_dir/lane-$s.result
                    command rm -f $run_dir/lane-$s.result
                else if test (_ts_push_tmux display -p -t $slots[$s] '#{pane_dead}') = 1
                    command rm -f $run_dir/lane-$s.job
                    _ts_push_tmux respawn-pane -k -t $slots[$s] \
                        fish --init-command "source "(string escape -- $self) -c '_ts_push_tmux_lane $argv' -- $run_dir $s
                else
                    continue
                end
                set busy[$s] 0
                set -l state failure
                switch "$st"
                    case 0
                        set state success
                    case 2
                        test -z "$aborted" && set aborted aborted
                        touch $run_dir/abort
                    case 130 ''
                        test "$aborted" = stopped && set state pending
                end
                set targets[$i] (string replace -r '^[a-z]+:' "$state:" -- $targets[$i])
                # what this run did, for push's counts (a -C resume carries
                # older results in the state)
                test $state != pending && echo $state >>$run_dir/judged
                set -l pane_state $state
                test $state = pending && set pane_state stopped
                _ts_push_tmux set -p -t $slots[$s] @ts_state $pane_state
                test $state = success \
                    && _ts_push_osc "9;4;1;"(_ts_push_percent $targets) \
                    || _ts_push_osc "9;4;2;"(_ts_push_percent $targets)
                set changed 1
            end

            # panes waiting for retry/skip/abort. after an abort they get no
            # answer: end them (a Ctrl-C), they failed
            set -l now
            for s in (seq (count $slots))
                test $busy[$s] = 0 && continue
                test -e $logs[$busy[$s]].prompt && set -a now $slots[$s]
            end
            if test -n "$aborted"
                for p in $now
                    contains -- $p $ended || _ts_push_tmux send-keys -t $p C-c
                    set -a ended $p
                end
            end
            # focus moves only when a prompt shows up (unless one has it
            # already) or the one in focus got its answer: the user may click
            # elsewhere meanwhile
            set -l active (_ts_push_tmux display -p -t push '#{pane_id}')
            set -l fresh (for p in $now; contains -- $p $prompts || echo $p; end)
            if test -n "$fresh"; and not contains -- $active $now
                _ts_push_tmux select-pane -t $fresh[1]
            else if contains -- $active $prompts; and not contains -- $active $now
                test -n "$now" && _ts_push_tmux select-pane -t $now[1] || _ts_push_tmux select-pane -t $TMUX_PANE
            end
            test "$now" != "$prompts" && set changed 1
            set prompts $now

            if test -n "$changed"
                printf '%s\n' $targets >$run_dir/state
                _ts_push_tmux_draw $hint
            end
            sleep 0.3
        end
        test -n "$aborted" && break
    end

    # whatever never ran stays pending for push -C
    for i in (seq (count $targets))
        set targets[$i] (string replace -r '^running:' 'pending:' -- $targets[$i])
    end
    printf '%s\n' $targets >$run_dir/state
    touch $run_dir/judged
    set -l summary (_ts_log (green (string match -- 'success:*' $targets | count)) deployed, \
        (red (string match -v -- success (cat $run_dir/judged) | count)) failed, \
        (yellow (string match -- 'pending:*' $targets | count)) not run)
    set -l progress_flags --final
    _ts_push_tmux_draw $summary (dim "logs: $run_dir")
    # the key goes to the focused pane: make that this one. nobody watching
    # (the client went away): no key to wait for
    _ts_push_tmux select-pane -t $TMUX_PANE
    if set -q TS_PUSH_TMUX_TEST; or test (_ts_push_tmux display -p -t push '#{session_attached}') != 0
        printf '\e[?25h'
        read -l -n 1 -s -P (dim 'press any key to close') __
    end
    _ts_push_tmux kill-server
end

function _ts_push_tmux_draw -S -d "redraw the stack list, each running target with its pane, then the footer lines \$argv (runs in _ts_push_tmux_main's scope)"
    set -l footer $argv
    set -g _ts_progress_slots
    for t in $targets
        set -a _ts_progress_slots ''
    end
    for s in (seq (count $slots))
        set -l i $busy[$s]
        test $i = 0 && continue
        set -l mark (dim "[$s]")
        test -e $logs[$i].prompt && set -a mark (red 'retry?')
        set _ts_progress_slots[$i] "$mark"
    end
    set -l lines (_ts_progress $progress_flags $targets)
    _ts_push_tmux display -p -t $TMUX_PANE '#{pane_width} #{pane_height}' | read -l width height

    # more targets than rows: keep the running and failed ones, then the
    # first pending and the last done ones, and count the rest
    # heading, blank line, footer (a long line wraps), and the prompt
    set -l footer_rows 0
    for line in $footer
        set footer_rows (math "$footer_rows + max(1, ceil("(string length --visible -- $line)" / $width))")
    end
    set -l rows (math $height - 3 - $footer_rows)
    set -l shown (seq (count $targets))
    if test (count $targets) -gt $rows
        set rows (math "max(1, $rows - 1)")
        set -l picks
        for pass in '^(running|failure):' '^pending:' '^success:'
            set -l matches
            for i in (seq (count $targets))
                string match -qr -- $pass $targets[$i] && set -a matches $i
            end
            test $pass = '^success:' -a (count $matches) -gt 1 && set matches $matches[-1..1]
            for i in $matches
                test (count $picks) -lt $rows || break
                set -a picks $i
            end
        end
        set shown (printf '%s\n' $picks | sort -n)
    end

    set -l out $lines[1]
    for i in $shown
        set -a out $lines[(math $i + 1)]
    end
    set -l hidden (math (count $targets) - (count $shown))
    if test $hidden -gt 0
        set -l more
        for state in success pending failure running
            set -l c 0
            for i in (seq (count $targets))
                contains -- $i $shown && continue
                string match -q -- "$state:*" $targets[$i] && set c (math $c + 1)
            end
            test $c -gt 0 && set -a more "$c "(string replace success deployed -- $state)
        end
        set -a out (dim "  … $hidden more: "(string join ', ' -- $more))
    end
    # rewrite the screen in place from the top (no `clear`: tmux would keep
    # every old frame in the scrollback, and it flickers): each line erases
    # the rest of its row, then everything below goes. one row per list line,
    # a long one is cut; footer lines wrap. no cursor while it updates
    printf '\e[?25l\e[H'
    for line in $out
        printf '%s%s\e[K\n' (string shorten -m $width -- $line) (set_color normal)
    end
    printf '\e[K\n'
    for line in $footer
        printf '%s\e[K\n' $line
    end
    printf '\e[J'
end

function _ts_push_tmux_lane -a run_dir lane -d "deploy lane of push's tmux view: deploy each target the coordinator hands over (<run_dir>/lane-<n>.job), leave its exit status in lane-<n>.result"
    # Ctrl-C stops the deploy, not the lane: the target then asks what to do
    function _ts_push_tmux_lane_on_int --on-signal SIGINT
        set -g _ts_push_interrupted 1
    end
    set -l job $run_dir/lane-$lane.job
    set -l first 1
    while true
        while not test -e $job
            sleep 0.2
        end
        read -l i log <$job
        command rm -f $job
        # earlier targets stay above: a rule between them
        test -z "$first" && echo && echo (dim (string repeat -n (math "max(10, $COLUMNS)") ─))
        set first
        _ts_push_tmux_pane $run_dir $i $log
        echo $status >$run_dir/lane-$lane.result.tmp
        mv $run_dir/lane-$lane.result.tmp $run_dir/lane-$lane.result
    end
end

function _ts_push_tmux_pane -a run_dir i log -d "one target in a deploy lane: deploy target \$i, ask retry/skip/abort on failure. returns 0 deployed, 1 failed, 2 abort, 130 stopped"
    set -l targets (cat $run_dir/targets)
    echo $targets[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
    set -l fullname (_ts_push_fullname "$target_type" "$service_name" "$function_name" "$package_version" "$stage")
    set -l cmd (cat $run_dir/(printf '%02d' $i).cmd)
    set -l working_dir (path dirname -- $serverless_yml)
    while true
        set -e _ts_push_interrupted
        test "$target_type" = function \
            && _ts_log deploying function: (magenta $fullname) \
            || _ts_log deploying stack: (magenta $fullname)
        _ts_log working directory: (blue $working_dir)
        _ts_push_deploy "$target_type" "$service_name" "$working_dir" $cmd 2>&1 | tee -a $log
        set -l deploy_status $pipestatus[1]
        echo $deploy_status >$log.exit
        test $deploy_status -eq 0 && return 0
        # the run is over (abort, or Ctrl-C in the stack list): no prompt
        if test -e $run_dir/abort
            test $deploy_status -ge 128 && return 130
            return 1
        end

        # the coordinator sees the .prompt file and moves the focus here
        touch $log.prompt
        _ts_push_tmux set -p -t $TMUX_PANE @ts_state prompt
        _ts_notify -t "push failed: $fullname" \
            -m 'deploy failed — waiting for [r]etry / [s]kip / [a]bort'
        # choices on their own lines: a narrow pane would cut a long prompt
        echo (red 'push failed for') $fullname
        echo '[r]etry / [s]kip / [a]bort'
        read -l -n 1 -P 'r/s/a? [a] ' answer
        rm -f $log.prompt
        # the run was aborted or stopped meanwhile: this one failed
        test -e $run_dir/abort && return 1
        switch "$answer"
            case R r
                _ts_log retrying: (magenta $fullname)
                _ts_push_tmux set -p -t $TMUX_PANE @ts_state running
            case S s
                _ts_log skipping: (magenta $fullname)
                return 1
            case '*'
                return 2
        end
    end
end

function _ts_push_osc -a seq -d "print OSC <seq>; inside tmux wrapped for passthrough"
    # once only: an outer tmux forwards OSC 9;4 itself, a second wrap would
    # need its allow-passthrough
    set -l osc \e\]$seq\a
    set -q TMUX && set osc \ePtmux\;(string replace -a \e \e\e -- $osc)\e\\
    printf '%s' $osc
end

function _ts_push_percent -d "percent of targets in a final state (for OSC 9;4)"
    set -l done (string match -r '^(success|failure):' -- $argv | count)
    math -s0 "$done * 100 / "(count $argv)
end

function _ts_push_home -d "push's private dir (ts_push under \$XDG_RUNTIME_DIR, else \$TMPDIR, else /tmp); fails unless it is ours"
    set -l root $XDG_RUNTIME_DIR
    test -n "$root" -a -d "$root" || set root $TMPDIR
    test -n "$root" -a -d "$root" || set root /tmp
    set -l home (string trim -r -c / -- $root)/ts_push
    mkdir -p -m 700 $home 2>/dev/null
    # in a shared /tmp another user could have planted it (or a symlink)
    if test -L $home; or not test -O $home
        _ts_log refusing (red $home): not a directory of ours >&2
        return 1
    end
    echo $home
end

function _ts_push_run_dir -d "make this run's log dir under _ts_push_home and point 'latest' at it"
    set -l home (_ts_push_home)
    or return 1
    set -l dir (mktemp -d $home/(date +%Y%m%d-%H%M%S)-XXXX)
    # `command`: a user `ln` wrapper must not rewrite the link (e.g. relative to
    # the old run dir `latest` still points at, leaving it dangling)
    command ln -sfn $dir $home/latest
    echo $dir
end

function _ts_push_tiers -d "group target indices into dependency tiers, one line per tier"
    # order that matters: modules (layers) -> *-resources stacks ->
    # *authorizer* stacks (other services attach their authorizers) -> other
    # services -> admin-* services -> *web apps -> *www edge stacks (they read
    # the APIs' and web apps' outputs), in each group a parent stack
    # before its subservices (by how many of the pushed stacks sit above it,
    # not by path depth, so services/a/x does not wait for an unrelated
    # services/b) -> *monitoring* stacks ->
    # functions. functions of one service share its .serverless/ dir, so the
    # n-th function of a service waits for the (n-1)-th. already-succeeded
    # targets (a -C resume) are left out.
    set -l targets $argv
    set -l entries # "<sort key> <index>"
    set -l seen_ymls
    set -l stack_dirs # dirs of the stacks still to deploy, to find parents
    for t in $targets
        echo $t | read -l -d : state target_type serverless_yml __
        test "$state" != success
        and contains -- "$target_type" service cdk
        and set -a stack_dirs (path dirname -- $serverless_yml)
    end
    for i in (seq (count $targets))
        echo $targets[$i] | read -l -d : state target_type serverless_yml service_name __
        test "$state" = success && continue
        set -l key
        switch $target_type
            case module
                set key 0000
            case function
                set -a seen_ymls $serverless_yml
                set key 8(printf '%03d' (count (string match -- $serverless_yml $seen_ymls)))
            case '*'
                if string match -q -- '*-resources' $service_name
                    set key 0001
                else if string match -q -- '*authorizer*' $service_name
                    set key 0002
                else if string match -q -- '*monitoring*' $service_name
                    set key 5000
                else
                    # same group order as `changes`: services ->
                    # admin-* (they read services' outputs) -> *web,
                    # then the *www edge stacks that front them all
                    set -l group 1
                    switch $service_name
                        case '*www'
                            set group 4
                        case '*web'
                            set group 3
                        case 'admin-*'
                            set group 2
                    end
                    set -l dir (path dirname -- $serverless_yml)
                    set -l parents 0
                    for d in $stack_dirs
                        string match -q -- "$d/*" $dir && set parents (math $parents + 1)
                    end
                    set key $group(printf '%03d' $parents)
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

function _ts_push_deploy -a target_type service_name working_dir runner -d "install deps, then run one deploy with \$runner (_ts_sls/_ts_cdk; also runs inside a child fish)"
    set -l deploy_cmd $argv[5..]
    if test "$target_type" = module && string match -q -r module-libs -- $service_name
        build_libs --force
        # interrupted (Ctrl-C): don't deploy half-built libs
        or begin
            set -l build_status $status
            test $build_status -ge 128 && return $build_status
        end
    else
        for d in "$working_dir" "$working_dir"/nodejs "$working_dir"/nodejs*/nodejs "$working_dir"/nodejs/node*
            if test -e "$d"/package.json
                # web app / CDK app (runs here): install all deps; lambda
                # code: target linux/x64/glibc
                set -l pm_flags --no-proxy
                string match -q -r '\bweb\b' -- "$d"
                or test "$target_type" = cdk
                or set -a pm_flags --os=linux --cpu=x64 --libc=glibc
                set -l install_cmd (_ts_pm_install "$d" $pm_flags $ts_npm_install_options)
                command env -C "$d" fish -P -c "
                    type -q nvm && nvm use > /dev/null
                    command $install_cmd
                "
                # interrupted (Ctrl-C): don't deploy half-installed deps
                or begin
                    set -l install_status $status
                    test $install_status -ge 128 && return $install_status
                end
            end
        end
    end
    # a Ctrl-C during the install/build (the tmux pane's fish survives it):
    # don't deploy what may be half done
    set -q _ts_push_interrupted && return 130
    $runner --workdir "$working_dir" --with-env $deploy_cmd
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
        test -f "$current_dir/serverless.yml" -o -f "$current_dir/cdk.json"
        and set stack_dirs (_ts_push_stack_dirs "$current_dir")
    end

    if test -z "$current_dir"
        _ts_log cannot resolve current service. run from a service directory
        return 1
    end
    set -l resource_dirs
    set -l authorizer_dirs
    set -l main_dir
    set -l subservice_dirs
    set -l monitoring_dirs

    for dir in $stack_dirs
        if test "$dir" = "$current_dir"
            set main_dir $dir
        else
            set -l service_name (_ts_resolve_config "$dir" "" | string split -f3 -- :)
            if string match -q '*-resources' -- $service_name
                set -a resource_dirs $dir
            else if string match -q '*authorizer*' -- $service_name
                set -a authorizer_dirs $dir
            else if string match -q '*monitoring*' -- $service_name
                set -a monitoring_dirs $dir
            else
                set -a subservice_dirs $dir
            end
        end
    end

    # authorizers deploy before the services that use them, monitoring stacks
    # deploy last (they observe the rest)
    set -l ordered_targets $resource_dirs $authorizer_dirs
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

function _ts_push_stack_dirs -a dir -d "dirs of every serverless.yml or cdk.json at or below <dir>, node_modules/cdk.out pruned"
    find "$dir" -type d \( -name node_modules -o -name cdk.out \) -prune \
        -o -type f \( -name serverless.yml -o -name cdk.json \) -print \
        | string replace -r '/(serverless\.yml|cdk\.json)$' '' | path sort -u
end

function _ts_push_edit_targets -d "edit resolved push targets in \$EDITOR; echoes kept targets in new order"
    set -l editor $EDITOR
    test -n "$editor" || set editor $VISUAL
    test -n "$editor" || set editor vi

    set -l tmp (mktemp -t ts_push.XXXXXX)
    begin
        echo '# travelstop push — reorder or delete lines, then save and close.'
        echo '# Targets deploy in dependency tiers (top to bottom within a tier). Delete a line to skip it. Keep the leading number.'
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

function _ts_progress -d "print the targets with their state; --final once the run is over"
    argparse final -- $argv
    or return 1
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
    if not set -q _flag_final
        _ts_log deploying (yellow $count) stacks/functions
    else if string match -q -- 'pending:*' $argv
        # stopped or aborted: the rest never ran
        _ts_log (yellow $count) stacks/functions, (yellow (string match -- 'pending:*' $argv | count)) not run
    else
        _ts_log (yellow $count) 'stacks/functions deployed'
    end
    for i in (seq $count)
        echo $argv[$i] | read -l -d : state target_type serverless_yml service_name function_name package_version region stage
        set -l index (string sub -s -$indent " $i")
        set -l caret caret_$state
        set -l color color_$state
        set -l fullname $service_name-(string upper $stage)
        test -n "$package_version" && set package_version (dim '-')(yellow $package_version)
        # the tmux view marks which pane deploys each running target
        set -l slot
        set -q _ts_progress_slots[$i] && test -n "$_ts_progress_slots[$i]" && set slot $_ts_progress_slots[$i]
        # before the name: a long name may be cut
        if test "$target_type" = function
            echo $$caret (dim $index.) $slot ($$color $fullname-$function_name)
        else
            echo $$caret (dim $index.) $slot ($$color $fullname)$package_version
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
    else if test -f "$target/cdk.json"
        set serverless_yml (realpath "$target/cdk.json")
    else if test -f "$target/resources/cdk.json"
        # a CDK service keeps its app in resources/ (see _change_stacks)
        set serverless_yml (realpath "$target/resources/cdk.json")
    else if test -f "$$_ts_project_dir/$target/serverless.yml"
        set serverless_yml (realpath "$$_ts_project_dir/$target/serverless.yml")
    else if test -f "$$_ts_project_dir/$target/cdk.json"
        set serverless_yml (realpath "$$_ts_project_dir/$target/cdk.json")
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

    if test (path basename -- $serverless_yml) = cdk.json
        # a CDK app is named by its package.json (stack names live in its code)
        set target_type cdk
        test -n "$package_json"
        and string match -q -r '^\s*"name":\s*"(?<service_name>[^"]*)"' <$package_json
    else if contains $target (_ts_functions "$serverless_yml")
        set target_type function
        set function_name $target
    else
        string match -q -r /modules/ "$serverless_yml" \
            && set target_type module \
            || set target_type service
    end
    test -n "$service_name"
    or string match -q -r '^service:\s*(?<service_name>[^\s]*)' <$serverless_yml
    if test -n "$package_json"
        string match -q -r '^\s*"version":\s*"(?<package_version>[^"]*)"' <$package_json
    else if test -n "$changelog_md"
        string match -q -r '# (?<package_version>\d+(\.\d+)+)' <$changelog_md
    end

    echo "$target_type:$serverless_yml:$service_name:$function_name:$package_version:$region"
end
