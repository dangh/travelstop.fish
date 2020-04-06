function sls_logs --description 'watch lambda function logs'
  sls logs --stage $AWS_PROFILE --tail --startTime 2m --function $argv
end

alias logs=sls_logs
