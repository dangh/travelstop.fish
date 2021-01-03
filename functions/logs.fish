function logs --description "watch lambda function logs"
  set --local function
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local start_time 2m
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
    case startTime
      set start_time $value
    case \*
      test (string length $key) -eq 1 \
        && set key "-$key" \
        || set key "--$key"
      test "$value" = true \
        && set --erase value
      set --append args $key (string escape --style=script $value)
    end
  end
  set --local command "sls logs --profile $profile -s $stage -r $region -t --startTime $start_time -f $function $args"
  echo (set_color green)$command(set_color normal)
  set --local transform "awk -f ~/.config/fish/functions/logs_transform.awk"
  eval $command \| $transform
end
