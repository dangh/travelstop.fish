function sls_invoke --argument-names function_name --description 'invoke lambda function'
  sls invoke --stage $AWS_PROFILE --type Event --function $argv
  sls_logs $function_name
end

alias invoke=sls_invoke
