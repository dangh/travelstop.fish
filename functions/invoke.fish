function invoke --description "invoke lambda function"
  set --local start_time (date -u "+%Y%m%dT%H%M%S")
  set --local function
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local type Event
  set --local args
  getopts $argv | while read --local key value
    switch $key
    case f function _
      set function $value
    case profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case t type
      set type $value
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
  set --local command "sls invoke --profile=$profile --stage=$stage --region=$region --type=$type --function=$function $args"
  echo (set_color green)$command(set_color normal)
  eval $command
  logs $function --startTime=$start_time
end
