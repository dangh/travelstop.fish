function _ts_notify -a title message sound -d "send notification to system"
    osascript -e "display notification \"$message\" with title \"$title\"" &
    disown
    set sound "/System/Library/Sounds/$sound.aiff"
    if test -f "$sound"
        afplay $sound &
        disown
    end
end

function _ts_pushover -a title message
    test -n "$PUSHOVER_USER_KEY" -a -n "$PUSHOVER_APP_TOKEN" || return
    wait # queue pushover api calls
    curl -s \
        --form-string "token=$PUSHOVER_APP_TOKEN" \
        --form-string "user=$PUSHOVER_USER_KEY" \
        --form-string "title=$title" \
        --form-string "message=$message" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1 &
end

function _ts_log
    echo '('(yellow sls)')' $argv
end

function _ts_env
    test -n "$ts_env" || begin
        echo
        return 0
    end

    argparse 'mode=?' -- $argv
    set -l result

    switch $_flag_mode
        case env
            for pair in $ts_env
                echo $pair | read -l -d = key value
                set -a result $key=(string escape -- $value)
            end
        case awk
            for pair in $ts_env
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
abbr -a -- l logs
abbr -a -- i invoke
abbr -a -- b build_libs
abbr -a -- r rename_modules

function logs_minutes -a lm
    string match -qr 'l(?<m>\d+)' $lm
    if test "$m" -eq 0
        echo 'logs --startTime=(date -u +%Y%m%dT%H%M%S)'
    else
        echo 'logs --startTime='$m'm'
    end
end

abbr -a logs_minutes -r '^l\d+$' -f logs_minutes

function ts_env_vpn -e vpn -a action -a proxy
    set -l var HTTPS_PROXY=$proxy
    switch "$action"
        case connect
            set -q ts_env || set -Ux ts_env
            contains $var $ts_env || set -a ts_env $proxy
        case disconnect
            set -e ts_env
            contains --index $var $ts_env | read -l idx
            if test -n "$idx"
                set -e ts_env[$idx]
            end
    end
end

if type -q assume
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
end

function retain_aws_vars
    function store_aws_vars -e fish_prompt -e fish_cancel
        set -U LAST_AWS_PROFILE $AWS_PROFILE
        set -U LAST_AWS_REGION $AWS_REGION
    end
    set -gx AWS_PROFILE $LAST_AWS_PROFILE
    set -gx AWS_REGION $LAST_AWS_REGION
end && retain_aws_vars && functions -e retain_aws_vars
