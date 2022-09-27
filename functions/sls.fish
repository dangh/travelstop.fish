function sls -d "wraps sls to provide stage/profile/region implicitly"
  set -l profile $AWS_PROFILE
  set -l stage (string lower -- (string replace -r '.*@' '' -- $AWS_PROFILE))
  set -l region $AWS_DEFAULT_REGION

  argparse -i \
    'profile=' \
    's/stage=' \
    'r/region=' \
    -- $argv
  or return 1

  set -q _flag_profile && set profile $_flag_profile
  set -q _flag_stage && set stage $_flag_stage
  set -q _flag_region && set region $_flag_region

  set -l cmd sls $argv --profile=$profile --stage=$stage --region=$region

  _ts_log execute command: (green (string join ' ' -- (_ts_env --mode=env) $cmd))
  eval (_ts_env --mode=env) command $cmd
end
