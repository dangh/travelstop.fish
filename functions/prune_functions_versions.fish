function _delete_function_versions -a function_name -a keep
    test -n "$function_name" || return 1
    test -n "$keep" || set keep 10
    set -l batch_size 20
    aws lambda list-versions-by-function --function-name $function_name \
        | jq -r '.Versions.[].Version' \
        | tail -n +2 \
        | tail -r \
        | tail -n +$keep \
        | tail -r \
        | xargs -n1 -P $batch_size -I {} (which fish) -c _ts_delete_function_version $function_name {}
end

function prune_functions_versions -a keep
    test -n "$keep" || set keep 10
    for f in (_ts_substacks | _ts_functions -l)
        echo Pruning all versions of function $f except the last $keep
        _delete_function_versions $f $keep
    end
end
