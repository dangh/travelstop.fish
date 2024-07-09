function daily_report -a lambda
    test -n "$ts_master_dir" || return 1
    string match -qr '(?<stack>[\w-]+?)-(?<stage>prod|stage|test|dev-in|dev)-(?<functionName>\w+)' $lambda
    set -l dir (_find_dir $ts_master_dir/services $stack)
    set -l query
    if test -n "$dir"
        set -l yml $dir/serverless.yml
        string match -qr $functionName'\s*:\n\s*handler\s*:\s*(?<handler>[^\s.]+)' ( string split0 < $yml )
        set -l js_file $dir/$handler.js
        set query (_get_error_message $js_file)
    end

    if test -z "$query"
        set query 'Failed to'
    end

    set -l region
    switch $stage
        case dev-in
            set region ap-south-1
        case '*'
            set region ap-southeast-1
    end

    set -l container (string upper $stage)
    set -l start_time (date -v-1d -v12H -v0M -v0S +%s)000
    set -l end_time (date -v12H -v0M -v0S +%s)000

    set url "ext+container:name=$container&url=https://$region.console.aws.amazon.com/cloudwatch/home?region=$region#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$lambda/log-events\$3FfilterPattern\$3D\$2522$query\$2522\$26start\$3D$start_time\$26end\$3D$end_time"

    /Applications/Firefox\ Developer\ Edition.app/Contents/MacOS/firefox $url
end

function _pluralize -a word
    if string match -q '*s' $word
        echo $word
    else if string match -q '*y' $word
        echo string replace -r 'y$' ies $word
    else
        echo "$word"s
    end
end

function _find_dir -a root -a stack
    set -l remains (string split - $stack)
    set -l try_parts
    set -l dir $root
    while test -n "$remains"
        set -a try_parts $remains[1]
        set -e remains[1]
        set -l try_dir $dir/( _pluralize ( string join - $try_parts ) )
        if test -d $try_dir
            set dir $try_dir
            set -e try_parts
            if test -z "$remains"
                echo $dir
                return 0
            end
        end
    end
    return 1
end

function _get_error_message -a js_file
    set -l patterns \
        'exports.handler = async ($$$_) => { $$$_ try { $$$_ } catch($$$_) { log.error(\'$MSG\', $$$_) } }' \
        'exports.handler = async ($$$_) => { $$$_ try { $$$_ } catch($$$_) { log.error(\'$MSG\', $$$_); $$$_ } }' \
        'exports.handler = async ($$$_) => { $$$_ try { $$$_ } catch($$$_) { log.error(\'$MSG\', $$$_) } finally { $$$_ } }'
    for pattern in $patterns
        ast-grep -p $pattern --strictness signature --json $js_file \
            | jq -er '.[0].metaVariables.single.MSG.text | select( . != null )' \
            | grep -E '\w+(\s+\w+)*' -m1 -o \
            | head -1 \
            | read -l msg
        if test -n "$msg"
            echo $msg
            return 0
        end
    end
    return 1
end
