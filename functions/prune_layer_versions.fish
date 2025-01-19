function prune_layer_versions -a layer_name -a keep
    test -n "$layer_name" || return 1
    test -n "$keep" || set keep 10
    set -l batch_size 20
    aws lambda list-layer-versions --layer-name $layer_name \
        | jq -r '.LayerVersions.[].Version' \
        | command tail -n +(math $keep + 1) \
        | command tail -r \
        | xargs -n1 -P $batch_size -I {} (which fish) -c _ts_delete_layer_version $layer_name {}
end
