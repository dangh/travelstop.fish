function invoke --argument-names function_name --description "invoke lambda function"
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  set --local start_time (date -u "+%Y%m%dT%H%M%S")
  set --local region
  if not contains -- --region $argv
    if test "$AWS_DEFAULT_REGION" != ""
      set region "--region $AWS_DEFAULT_REGION"
    end
  end
  set --local command "sls invoke --aws-profile $AWS_PROFILE --stage $stage $region --type Event --function $function_name"
  for i in $argv[2..-1]
    set command $command "'$i'"
  end
  echo (set_color green)$command(set_color normal)
  eval $command
  logs $function_name $start_time
end
