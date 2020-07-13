function logs --argument-names function_name start_time --description "watch lambda function logs"
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  if test -z "$start_time"
    set start_time (date -u "+%Y%m%dT%H%M%S")
  end
  set --local command "sls logs --aws-profile $AWS_PROFILE --stage $stage --tail --startTime $start_time --function $function_name"
  echo (set_color green)$command(set_color normal)
  # eval "$command | __logs_transform"
  set --local logs_and_transform $command '| awk \'
    function resetAfter(s) { return sprintf("%s\x1b[0m", s) }
    function bold(s) { return sprintf("\x1b[1m%s", s) }
    function black(s) { return sprintf("\x1b[30m%s", s) }
    function red(s) { return sprintf("\x1b[31m%s", s) }
    function green(s) { return sprintf("\x1b[32m%s", s) }
    function yellow(s) { return sprintf("\x1b[33m%s", s) }
    function blue(s) { return sprintf("\x1b[34m%s", s) }
    function magenta(s) { return sprintf("\x1b[35m%s", s) }
    function cyan(s) { return sprintf("\x1b[36m%s", s) }
    function brightBlack(s) { return sprintf("\x1b[90m%s", s) }
    {
      #remove aws timestamp, log id, log level
      gsub(/^[0-9:. ()+-]{32}[[:space:]]+[a-z0-9-]{36}[[:space:]]+INFO[[:space:]]+/, "")

      #blue stage
      #cyan timestamp
      #magenta source location
      #blue method name
      if ($0 ~ /^\[([A-Z-]+)\]\[([0-9TZ:.-]{24})\]\[([a-z.-]+):([0-9]+)\]\[[a-zA-Z.]+\]/) {
        match($0, /^\[([A-Z-]+)\]\[([0-9TZ:.-]{24})\]\[([a-z.-]+):([0-9]+)\]\[[a-zA-Z.]+\]/)
        rest = substr($0, RLENGTH+1)
        split($0, tokens, /[\[\]]/)
        stage = tokens[2]
        time = tokens[4]
        split(tokens[6], location, /:/)
        filename = location[1]
        lineno = location[2]
        method = tokens[8]
        $0 = brightBlack("[") blue(stage) brightBlack("]") brightBlack("[") cyan(time) brightBlack("]") brightBlack("[") magenta(filename) brightBlack(":") magenta(lineno) brightBlack("]") brightBlack("[") blue(method) brightBlack("]") rest

        #blank line before each log entry
        printf "\n"
      }

      #blank line after last log entry
      if ($0 ~ /^END RequestId/) printf "\n"

      #blank page before each event
      if ($0 ~ /^START RequestId/) printf "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"

      #bright black aws logs
      gsub(/^(START|END|REPORT|XRAY) (RequestId|TraceId).*/, brightBlack($0))

      #green info
      #yellow warn
      #red error
      #bright black debug
      gsub(/\[INFO\]: /, sprintf("%s%s%s%s", brightBlack("["), resetAfter(bold(green("INFO"))), resetAfter(brightBlack("]\n")), green()))
      gsub(/\[WARN\]: /, sprintf("%s%s%s%s", brightBlack("["), resetAfter(bold(yellow("WARN"))), resetAfter(brightBlack("]\n")), yellow()))
      gsub(/\[ERROR\]: /, sprintf("%s%s%s%s", brightBlack("["), resetAfter(bold(red("ERROR"))), resetAfter(brightBlack("]\n")), red()))
      gsub(/\[DEBUG\]: /, sprintf("%s%s%s%s", brightBlack("["), resetAfter(bold(black("DEBUG"))), resetAfter(brightBlack("]\n")), black()))

      print
    }\'
  '
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
