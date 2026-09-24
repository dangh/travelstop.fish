function _ts_notify -d 'send terminal notification (OSC 777) and pushover'
    argparse 't/title=' 'm/message=' 'd/details=' -- $argv
    or return 1
    # convert literal \n (backslash-n) to real newlines for ergonomic input
    set -l title (string replace -ra '\\\\n' \n -- $_flag_title)
    set -l message (string replace -ra '\\\\n' \n -- $_flag_message)
    set -l details (string replace -ra '\\\\n' \n -- $_flag_details)

    # terminal notification (title + message only)
    printf '\e]777;notify;%s;%s\a' "$title" "$message"

    # pushover: message + details (if provided), only when configured
    if test -n "$PUSHOVER_USER_KEY" -a -n "$PUSHOVER_APP_TOKEN"
        set -l body $message
        test -n "$details" && set body (string join \n -- $message $details | string collect)
        wait # queue pushover api calls
        curl -s \
            --form-string "token=$PUSHOVER_APP_TOKEN" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "title=$title" \
            --form-string "message=$body" \
            https://api.pushover.net/1/messages.json >/dev/null 2>&1 &
    end
end

function _ts_log
    echo '('(yellow sls)')' $argv
end

function _ts_env
    # a user-defined `ts_env` function wins (compute pairs dynamically, e.g. a
    # per-AWS-profile proxy); otherwise fall back to the `ts_env` universal var.
    # each pair is one KEY=value entry.
    set -l pairs $ts_env
    functions -q ts_env && set pairs (ts_env)

    test -n "$pairs" || begin
        echo
        return 0
    end

    argparse 'mode=?' -- $argv
    set -l result

    switch $_flag_mode
        case env
            for pair in $pairs
                echo $pair | read -l -d = key value
                set -a result $key=(string escape -- $value)
            end
        case awk
            for pair in $pairs
                echo $pair | read -l -d = key value
                set -a result -v $key=(string escape -- $value)
            end
    end
    echo -n (string join ' ' -- $result)
end

function _ts_project_dir_setup
    set -g _ts_project_dir _ts_project_dir_$fish_pid

    function $_ts_project_dir -e fish_prompt # wait until first prompt evaluated
        functions -e $_ts_project_dir

        function $_ts_project_dir -v PWD
            set -U $_ts_project_dir (git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
            test -n "$$_ts_project_dir" || set -e $_ts_project_dir
        end && $_ts_project_dir

        function clear_$_ts_project_dir -e fish_exit
            set -e $_ts_project_dir
        end
    end

    status is-interactive || $_ts_project_dir
end && _ts_project_dir_setup && functions -e _ts_project_dir_setup

function _ts_service_name -d "print service name"
    argparse s/short l/long -- $argv
    set -l ymls $argv
    if not test -t 0
        while read -l yml
            set -a ymls $yml
        end
    end
    test -n "$ymls" || set ymls ./serverless.yml
    for yml in $ymls
        string match -eq "*.yml" $yml || set yml $yml/serverless.yml
        string match -qr '^service: (?<name>\S+)' <$yml
        if set -q _flag_long
            echo $name-(string lower $AWS_PROFILE)
        else
            echo $name
        end
    end
end

function _ts_modules -d "list all modules"
    set -q $_ts_project_dir || return
    argparse a/absolute r/relative -- $argv
    if set -q _flag_absolute
        path dirname $$_ts_project_dir/modules/*/serverless.yml
        return
    end
    if set -q _flag_relative
        set -l len (string length $$_ts_project_dir/)
        set -l rel_path (string sub -s $len $PWD | string replace -ar '/[^/]+' '../')
        test -n "$rel_path" || set rel_path './'
        path dirname $$_ts_project_dir/modules/*/serverless.yml | string sub -s (math 1+$len) | string replace -r '^' $rel_path
        return
    end
    set -l len (string length $$_ts_project_dir/)
    path dirname $$_ts_project_dir/modules/*/serverless.yml | string sub -s (math 1+$len)
end

function _ts_substacks -d "list all sub directories contains serverless.yml"
    set -q $_ts_project_dir || return
    find . -type d -name node_modules -prune -o -type f -name serverless.yml -print | string replace /serverless.yml '' | string replace './' '' | path sort
end

function _ts_functions -d "list all lambda functions in serverless.yml"
    argparse -i s/short l/long -- $argv
    set -l ymls $argv
    if not test -t 0
        while read -L yml
            set -a ymls $yml
        end
    end
    test -n "$ymls" || set ymls ./serverless.yml
    for yml in $ymls
        string match -eq "*.yml" $yml || set yml $yml/serverless.yml
        set -l prefix ''
        if set -q _flag_long
            set prefix (_ts_service_name -l $yml)-
        end
        awk '{
            if ((y == 1) && ($0 ~ /^[^#[:space:]]/)) exit;
            if ($0 ~ /^[[:space:]]*#/) next;
            if ($0 ~ /^functions:/) { y = 1; next; }
            if ((y == 1) && match($0, /^[[:space:]]{2}[[:alpha:]]+:/)) print "'$prefix'" substr($0, RSTART+2, RLENGTH-2-1);
        }' $yml 2>/dev/null
    end
end

function _ts_validate_path -a path -d "validate path existence and print it with colors"
    set path (string replace -r '^\./?(.*)' '$1' $path)
    string match -q -r '^/' $path || set path (pwd)/$path

    set -l parts (string split -n / $path)
    set -l corrects
    set -l wrongs
    set -l dir

    for p in $parts
        if test -e "$dir/$p"
            set dir "$dir/$p"
            set -a corrects $p
            set -e parts[1]
        else
            break
        end
    end
    for p in $parts
        set -a wrongs $p
    end

    set -e path
    for p in $corrects
        set path "$path"(green (dim /)$p)
    end
    if test -d "$dir"
        set path "$path"(green (dim /))
    end
    if test -n "$wrongs"
        set path "$path"(red $wrongs[1])
        set -e wrongs[1]
        for p in $wrongs
            set path "$path"(red (dim /)$p)
        end
    end
    echo $path
end

function _ts_delete_layer_version
    set -e argv
    set -l layer_name $argv[1]
    set -l v $argv[2]
    echo Deleting layer $layer_name:$v
    aws lambda delete-layer-version --layer-name $layer_name --version-number $v
end

function _ts_delete_function_version
    set -e argv
    set -l function_name $argv[1]
    set -l v $argv[2]
    echo Deleting function $function_name:$v
    aws lambda delete-function --function-name $function_name --qualifier $v
end

function _ts_pm_install -d "npm/pnpm install command for a dir; uses pnpm when pnpm-lock.yaml present, translating npm-style flags"
    set -l dir $argv[1]
    set -e argv[1]
    if test -f "$dir"/pnpm-lock.yaml
        set -l cmd pnpm install
        for a in $argv
            switch $a
                case '--prefix=*'
                    set -a cmd --dir=(string replace -- '--prefix=' '' $a)
                case '--omit=dev'
                    set -a cmd --prod
                case '--omit=optional'
                    set -a cmd --no-optional
                case '--no-proxy'
                    # pnpm honors proxy via env/config; npm-only flag, drop it
                case '*'
                    set -a cmd $a
            end
        end
        printf '%s\n' $cmd
    else
        printf '%s\n' npm install $argv
    end
end

function _ts_sls
    # long-only flags on purpose: fish argparse derives an implicit short flag
    # from a long name's first char, and short flags match case-insensitively.
    # `workdir` and `with-env` share the first char `w`, so the implicit short
    # is disabled for both — otherwise `--workdir` would claim serverless's
    # `-c/--config` and `--with-env` its `-e`, swallowing those values.
    argparse -i workdir= with-env -- $argv
    # discover where serverless is installed: walk up from the current dir (or
    # the --workdir target) to the nearest package.json that declares the
    # `serverless` package. that dir owns node_modules/.bin/sls. don't search
    # above git root.
    set -l start $PWD
    set -q _flag_workdir && set start $_flag_workdir
    set -l groot
    set -q $_ts_project_dir && set groot $$_ts_project_dir
    set -l pkg_dir
    set -l d $start
    while test -n "$d"
        test -f "$d"/package.json && grep -qE '"serverless"[[:space:]]*:' "$d"/package.json
        and set pkg_dir $d && break
        test "$d" = "$groot" && break
        set -l parent (path dirname $d)
        test "$parent" = "$d" && break
        set d $parent
    end
    set -l dirs $pkg_dir
    test -n "$dirs" || set dirs $start
    set -l sls
    for dir in $dirs
        if test -x "$dir"/node_modules/.bin/sls
            set sls "$dir"/node_modules/.bin/sls
            break
        end
    end
    # env-key mode (granted `assume -x --exec`): the role's temp creds live in the
    # shell env, not a profile. Strip `--aws-profile` so serverless authenticates
    # from those env creds instead of a named profile — a named profile would read
    # and refresh ~/.aws/credentials on disk, and serverless prefers AWS_PROFILE
    # over env keys (serverless#9821). AWS_PROFILE is also hidden from the child
    # (see the `-u AWS_PROFILE` on the env call below) for the same reason.
    if set -q AWS_ACCESS_KEY_ID
        set -l filtered
        set -l skip 0
        for a in $argv
            test $skip -eq 1; and set skip 0; and continue
            switch $a
                case --aws-profile
                    set skip 1
                case '--aws-profile=*'
                    # drop the inline form too
                case '*'
                    set -a filtered $a
            end
        end
        set argv $filtered
    end
    set -l cmd
    if set -q _flag_with_env
        set -a cmd (_ts_env --mode=env)
    end
    if test -z "$sls"
        # not found anywhere: install into the git project root (fallback to cwd)
        set -l target $dirs[-1]
        _ts_log sls command not found. Installing...
        set -l install_cmd (_ts_pm_install "$target" --prefix=$target)
        $install_cmd
        set sls "$target"/node_modules/.bin/sls
    end
    set -a cmd $sls $argv
    _ts_log execute command: (green (string join ' ' -- $cmd))
    set -l env
    # env-key mode: hide AWS_PROFILE from the child so serverless can't fall back
    # to the named profile (and its on-disk credential_process). See the strip above.
    set -q AWS_ACCESS_KEY_ID; and set -a env -u AWS_PROFILE
    if set -q _flag_workdir
        set -a env -C "$_flag_workdir"
    end
    command env $env fish -P -c "
        type -q nvm && nvm use > /dev/null
        $cmd
    "
end

function _ts_git_refs -d "list git refs for completion"
    git for-each-ref --format='%(refname:strip=2)' refs 2>/dev/null
end

function _ts_confirm_prod -a action -d "prompt y/N before a PROD action; return 1 if declined"
    while true
        read -l -P "Do you want to $action on PROD? [y/N] " confirm
        switch $confirm
            case Y y
                return 0
            case '' N n
                return 1
        end
    end
end

status is-interactive || exit

function _ts_uniq_completions
    set -l cmd (commandline -p -o -c)
    set -e cmd[1]
    for arg in $argv
        if not contains $arg $cmd
            echo $arg
        end
    end
end

abbr -a -- c changes
abbr -a -- p push
abbr -a -- pc push_changes
abbr -a -- l logs
abbr -a -- i invoke
abbr -a -- b build_libs
abbr -a -- r rename_modules
abbr -a -- v bump_version

function logs_minutes -a lm
    string match -qr 'l(?<m>\d+)' $lm
    if test "$m" -eq 0
        echo 'logs --startTime=(date -u +%Y%m%dT%H%M%S)'
    else
        echo 'logs --startTime='$m'm'
    end
end

abbr -a logs_minutes -r '^l\d+$' -f logs_minutes

function _ts_ensure_session -d 'verify the AWS session up-front; offer inline re-auth and continue if expired'
    type -q aws; or return 0 # no aws CLI -> nothing to gate
    # env-key mode (granted `assume -x --exec` subshell): creds are in the shell
    # env, not a profile. Verify with those env creds (no --profile); we can't
    # self-heal here (no profile to re-assume), so on expiry tell the user to exit
    # the subshell and re-assume to mint fresh creds.
    if set -q AWS_ACCESS_KEY_ID
        aws sts get-caller-identity >/dev/null 2>&1; and return 0
        _ts_log (red "AWS env session expired — exit this shell and re-assume to refresh")
        return 1
    end
    set -l profile $argv[1]
    test -n "$profile"; or set profile $AWS_PROFILE
    if test -z "$profile"
        _ts_log (yellow 'no AWS_PROFILE set — skipping session check')
        return 0
    end
    while true
        # credential_process runs with --auto-login: an expired SSO session
        # surfaces the login URL here (via ~/sso-print-url.sh -> /dev/tty), at a
        # clean prompt instead of buried mid-deploy. Complete it and we continue.
        # Both streams are dropped: stdout is the identity JSON and stderr is the
        # ExpiredToken noise; the login URL goes to /dev/tty, bypassing both.
        if aws sts get-caller-identity --profile $profile >/dev/null 2>&1
            return 0
        end
        # not authenticated — offer to re-auth inline and continue instead of
        # aborting the whole run
        _ts_log (red "AWS session expired for $profile.")
        read -l -n 1 -P (yellow "log in to $profile now? [Y/n] ") ans
        or return 1 # non-interactive / EOF -> abort
        switch $ans
            case n N
                _ts_log aborted": run "(yellow "assume $profile")" to log in, then retry"
                return 1
        end
        # cached creds in ~/.aws/credentials shadow the credential_process, so a
        # bare re-check can't self-heal — force a fresh granted login (refreshes
        # ~/.aws/credentials + the SSO token), then loop to re-verify.
        if type -q assume
            assume $profile
        else
            aws sso login --profile $profile
        end
    end
end

if type -q assume
    # classic in-shell assume: sets AWS_PROFILE in the current shell; granted's
    # credential_process caches the temp creds to ~/.aws/credentials on disk.
    alias d='assume DEV'
    alias di='assume DEV-IN'
    alias t='assume TEST'
    alias s='assume STAGE'

    function a -a profile
        test -n "$profile" || set profile $AWS_PROFILE
        set args $argv[2..-1]
        test -n "$args" || set args -s cloudwatch
        assume $profile $args
    end

    # isolated subshell: `-x` puts the role's temp creds in the shell ENV only —
    # never written to ~/.aws/credentials — scoped to this subshell. Every tool
    # run inside inherits them; apps outside the subshell can't use the role.
    # Exit the subshell to drop the creds. The travelstop commands detect env-key
    # mode and stop passing --aws-profile so serverless/aws auth from the env.
    function assume-shell -a profile -d 'open an isolated subshell with a role assumed via env-only creds'
        test -n "$profile"; or begin
            _ts_log profile required
            return 1
        end
        # `-x` exports the role's temp creds into the subshell env. Pin AWS_PROFILE
        # via fish's `-C` (runs after config, before the interactive prompt) so the
        # travelstop commands still derive the right stage/service name — and the
        # PROD-confirm guard still fires — even if granted omits AWS_PROFILE in
        # export mode. env-key mode leaves this profile untouched (retain_aws_vars
        # is guarded off), so it stays consistent with the assumed creds.
        assume $profile -x --exec -- $SHELL -C "set -gx AWS_PROFILE $profile"
    end
    function prod -d 'open an isolated PROD subshell (env-only creds, nothing written to disk)'
        assume-shell PROD $argv
    end
end

function retain_aws_vars
    # universal-var prefix for the current git project; fails when not in a repo.
    # `string escape --style=var` turns the toplevel path into a valid var name.
    function _ts_aws_project_key
        set -l dir (git --no-optional-locks rev-parse --show-toplevel 2>/dev/null)
        test -n "$dir" || return 1
        echo _ts_aws_(string escape --style=var -- $dir)
    end

    # persist the current profile/region on every prompt: globally (fallback) and
    # per-project so each git project/worktree remembers its own last profile.
    function _ts_store_aws_vars -e fish_prompt -e fish_cancel
        # env-key subshell (granted `assume -x`): the profile is ephemeral and its
        # creds live only in this shell's env. Don't persist it as a project/global
        # default, and don't let a later restore desync AWS_PROFILE from the creds.
        set -q AWS_ACCESS_KEY_ID; and return
        set -U LAST_AWS_PROFILE $AWS_PROFILE
        set -U LAST_AWS_REGION $AWS_REGION
        set -l key (_ts_aws_project_key)
        or return
        set -U {$key}_profile $AWS_PROFILE
        set -U {$key}_region $AWS_REGION
    end

    # on entering a directory, restore that project's last-used profile/region.
    # returns non-zero when there is nothing project-specific to restore.
    function _ts_restore_aws_vars -v PWD
        # env-key subshell: keep the assumed profile granted set; never override it.
        set -q AWS_ACCESS_KEY_ID; and return
        set -l key (_ts_aws_project_key)
        or return
        set -l pv {$key}_profile
        set -l rv {$key}_region
        set -q $pv || return
        set -gx AWS_PROFILE $$pv
        set -gx AWS_REGION $$rv
    end

    # seed the shell: prefer this project's saved profile, else the global last-used.
    # env-key subshell: leave AWS_PROFILE/creds exactly as granted `assume -x` set them.
    if set -q AWS_ACCESS_KEY_ID
        # nothing to seed — the subshell already carries its assumed identity
    else if not _ts_restore_aws_vars
        set -gx AWS_PROFILE $LAST_AWS_PROFILE
        set -gx AWS_REGION $LAST_AWS_REGION
    end
end && retain_aws_vars && functions -e retain_aws_vars
