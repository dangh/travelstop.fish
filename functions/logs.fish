function logs --description 'watch lambda function logs'
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  sls logs --aws-profile $AWS_PROFILE --stage $stage --tail --startTime 2m --function $argv
end
