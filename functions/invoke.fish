function invoke --argument-names function_name --description 'invoke lambda function'
  set --local stage (string replace --regex '.*@' '' -- $AWS_PROFILE)
  sls invoke --stage $stage --type Event --function $argv
  logs $function_name
end
