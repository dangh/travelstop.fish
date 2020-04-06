function sls_logs -d 'watch lambda function logs'
  sls logs -s $AWS_PROFILE -t --startTime 2m -f $argv
end

alias logs=sls_logs
