function sls_invoke --description 'invoke lambda function'
  sls invoke --stage $AWS_PROFILE --type Event --function $argv
end

alias invoke=sls_invoke
