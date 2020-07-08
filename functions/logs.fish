function logs --argument-names function_name start_time --description "watch lambda function logs"
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  if test -z "$start_time"
    set start_time (date -u "+%Y%m%dT%H%M%S")
  end
  set --local command "sls logs --aws-profile $AWS_PROFILE --stage $stage --tail --startTime $start_time --function $function_name"
  echo (set_color green)$command(set_color normal)
  eval $command
end
