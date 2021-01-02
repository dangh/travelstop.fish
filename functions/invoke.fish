function invoke --description "invoke lambda function"
  set --local start_time (date -u "+%Y%m%dT%H%M%S")
  set --local function
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
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
      test (string length $key) -eq 1 \
        && set key "-$key" \
        || set key "--$key"
      test "$value" = true \
        && set --erase value
      set --append args $key (string escape --style=script $value)
    end
  end
  set --local command "sls invoke --profile $profile -s $stage -r $region -t $type -f $function $args"
  echo (set_color green)$command(set_color normal)
  eval $command
  logs $function --startTime=$start_time
end
