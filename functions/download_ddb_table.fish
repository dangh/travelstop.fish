function download_ddb_table -a table_name
    aws dynamodb scan \
        --table-name $table_name \
        --select ALL_ATTRIBUTES \
        --page-size 500 \
        --max-items 100000 \
        | jq -f ~/.config/fish/functions/ddb_unmarshall.jq >$table_name.json
    echo Got (jq .Count $table_name.json) documents from $table_name table
end
