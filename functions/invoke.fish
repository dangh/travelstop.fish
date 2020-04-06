function sls_invoke -d 'invoke lambda function'
  sls invoke -s $AWS_PROFILE --type=Event -f $argv
end

alias invoke=sls_invoke
