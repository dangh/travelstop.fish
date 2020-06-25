function logs --description 'watch lambda function logs'
  set --local stage (string replace --regex '.*@' '' -- $AWS_PROFILE)
  sls logs --stage $stage --tail --startTime 2m --function $argv
end
