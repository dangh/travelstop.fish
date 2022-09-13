function sls --description "wraps sls to provide stage/profile/region implicitly"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION

  argparse --ignore-unknown \
    'profile=?' \
    's/stage=?' \
    'r/region=?' \
    -- $argv
  or return 1

  set --query _flag_profile && set profile $_flag_profile
  set --query _flag_stage && set stage $_flag_stage
  set --query _flag_region && set region $_flag_region

  set --local cmd sls $argv --profile=$profile --stage=$stage --region=$region

  _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $cmd))
  eval (_ts_env --mode=env) command $cmd
end
