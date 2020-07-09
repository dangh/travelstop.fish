function logs --argument-names function_name start_time --description "watch lambda function logs"
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  if test -z "$start_time"
    set start_time (date -u "+%Y%m%dT%H%M%S")
  end
  set --local command "sls logs --aws-profile $AWS_PROFILE --stage $stage --tail --startTime $start_time --function $function_name"
  echo (set_color green)$command(set_color normal)
  # eval "$command | __logs_transform"
  set --local logs_and_transform $command '| awk \'{
    gsub(/^[0-9:. ()+-]{32}[[:space:]]+[a-z0-9-]{36}[[:space:]]+INFO[[:space:]]+/, "")
    if ($0 ~ /^\[([A-Z-]+)\]\[([0-9TZ:.-]{24})\]\[([a-z.-]+):([0-9]+)\]\[[a-z.]+\]/) {
      match($0, /^\[([A-Z-]+)\]\[([0-9TZ:.-]{24})\]\[([a-z.-]+):([0-9]+)\]\[[a-z.]+\]/)
      rest = substr($0, RLENGTH+1)
      split($0, tokens, /[\[\]]/)
      stage = tokens[2]
      time = tokens[4]
      split(tokens[6], location, /:/)
      filename = location[1]
      lineno = location[2]
      method = tokens[8]
      $0 = "\x1b[90m[\x1b[34m"stage"\x1b[90m][\x1b[36m"time"\x1b[90m][\x1b[35m"filename"\x1b[90m:\x1b[35m"lineno"\x1b[90m][\x1b[34m"method"\x1b[90m]\x1b[0m"rest
    }
    if ($0 ~ /^(START|END|REPORT) RequestId.*/) {
      $0 = "\x1b[90m"$0"\x1b[0m"
    } else if ($0 ~ /^XRAY TraceId.*/) {
      $0 = "\x1b[90m"$0"\x1b[0m"
    }
    gsub(/\[INFO\]:/, "[INFO]:\x1b[32m")
    gsub(/\[WARN\]:/, "[WARN]:\x1b[33m")
    gsub(/\[ERROR\]:/, "[ERROR]:\x1b[31m")
    gsub(/\[DEBUG\]:/, "[DEBUG]:\x1b[90m")
    print
  }\''
  eval $logs_and_transform
end

function __logs_transform
  #https://github.com/fish-shell/fish-shell/issues/206#issuecomment-255232968
  #add blank lines between requests
  #remove aws timestamp, log id, log level
  #green info
  #yellow warning
  #red error
  #blue stage
  #cyan timestamp
  #magenta filename
  cat 1>| \
  string replace --all --regex "^REPORT RequestId.*" '$0\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n' \
  | string replace --all --regex "^(START|END|REPORT) RequestId.*" '\x1b[90m$0\x1b[0m' \
  | string replace --all --regex "^[0-9-+ :.()]{32}\s+[a-z0-9-]{36}\s+INFO\s+" "" \
  | string replace --all --regex "^.*\[INFO\]:" '$0\x1b[32m' \
  | string replace --all --regex "^.*\[WARN\]:" '$0\x1b[33m' \
  | string replace --all --regex "^.*\[ERROR\]:" '$0\x1b[31m' \
  | string replace --all --regex "^\[([A-Z-]+)\]\[([0-9-:.TZ]{24})\]\[([a-z-.]+):([0-9]+)\]" '\x1b[0m[\x1b[34m$1\x1b[0m][\x1b[36m$2\x1b[0m][\x1b[35m$3\x1b[0m:\x1b[90m$4\x1b[0m]'
end
