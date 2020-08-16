function pack --description "package a serverless service"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local args
  getopts $argv | while read --local key value
    switch $key
    case aws-profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case \*
      if test (string length $key) = 1
        set args $args "-$key"
      else
        set args $args "--$key"
      end
      if test "$value" != "true"
        set args $args=(string escape $value)
      end
    end
  end
  set --local command "sls package --aws-profile=$profile --stage=$stage --region=$region $args"
  echo (set_color green)$command(set_color normal)
  eval $command
end
