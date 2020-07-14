function logs --argument-names function_name start_time --description "watch lambda function logs"
  set --local stage (string lower -- (string replace --regex ".*@" "" -- $AWS_PROFILE))
  if test -z "$start_time"
    set start_time (date -u "+%Y%m%dT%H%M%S")
  end
  set --local command "sls logs --aws-profile $AWS_PROFILE --stage $stage --tail --startTime $start_time --function $function_name"
  echo (set_color green)$command(set_color normal)
  set --local transform 'awk \'
    function bold(s) { if (s == "") { return "\x1b[1m" } else { return sprintf("\x1b[1m%s\x1b[21m", s) } }
    function dim(s) { if (s == "") { return "\x1b[2m" } else { return sprintf("\x1b[2m%s\x1b[22m", s) } }
    function italic(s) { if (s == "") { return "\x1b[3m" } else { return sprintf("\x1b[3m%s\x1b[23m", s) } }
    function underline(s) { if (s == "") { return "\x1b[4m" } else { return sprintf("\x1b[4m%s\x1b[24m", s) } }
    function black(s) { if (s == "") { return "\x1b[0m" } else { return sprintf("\x1b[0m%s\x1b[39m", s) } }
    function red(s) { if (s == "") { return "\x1b[31m" } else { return sprintf("\x1b[31m%s\x1b[39m", s) } }
    function green(s) { if (s == "") { return "\x1b[32m" } else { return sprintf("\x1b[32m%s\x1b[39m", s) } }
    function yellow(s) { if (s == "") { return "\x1b[33m" } else { return sprintf("\x1b[33m%s\x1b[39m", s) } }
    function blue(s) { if (s == "") { return "\x1b[34m" } else { return sprintf("\x1b[34m%s\x1b[39m", s) } }
    function magenta(s) { if (s == "") { return "\x1b[35m" } else { return sprintf("\x1b[35m%s\x1b[39m", s) } }
    function cyan(s) { if (s == "") { return "\x1b[36m" } else { return sprintf("\x1b[36m%s\x1b[39m", s) } }
    function noColor(s) { return sprintf("\x1b[39m%s", s) }
    {
      #blank page before each event
      if ($0 ~ /^START RequestId/) printf "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"

      #blank line after last log entry
      if ($0 ~ /^END RequestId/) printf "\n"

      #dim aws logs
      gsub(/^(START|END|REPORT|XRAY) (RequestId|TraceId).*/, dim($0))

      #remove aws timestamp, log id, log level
      gsub(/^[0-9:. ()+-]{32}[[:space:]]+[a-z0-9-]{36}[[:space:]]+INFO[[:space:]]+/, "")

      #blue stage
      #cyan timestamp
      #magenta source location
      #blue method name
      if (match($0, /^\[([A-Z-]+)\]\[([0-9TZ:.-]{24})\]\[([a-z.-]+):([0-9]+)\]\[[a-zA-Z.]+\]\[[A-Z]+\]: /)) {
        rest = substr($0, RLENGTH+1)
        split($0, tokens, /[\[\]]/)
        stage = tokens[2]
        time = tokens[4]
        split(tokens[6], location, /:/)
        filename = location[1]
        lineno = location[2]
        method = tokens[8]
        level = tokens[10]
        if (level == "ERROR") level = red(level)
        if (level == "WARN") level = yellow(level)
        if (level == "INFO") level = green(level)
        $0 = dim("[") bold(blue(stage)) dim("][") cyan(time) dim("][") magenta(filename) dim(":") magenta(lineno) dim("][") blue(method) dim("][") bold(level) dim("]:") "\n" rest

        #blank line before each log entry
        printf "\n"
        #reset all format
        printf "\x1b[0m"
      }

      #highlight json
      #start of json object/array
      if (match($0, /[{\[]$/)) $0 = substr($0, 1, RSTART-1) dim(substr($0, RSTART, RLENGTH))
      #end of json object/array
      if (match($0, /^[}\]]/)) $0 = noColor() dim(substr($0, RSTART, RLENGTH)) substr($0, RSTART+RLENGTH)
      #inside json object/array
      if (match($0, /^[[:space:]]+/)) {
        indent = substr($0, RSTART, RLENGTH)
        line = substr($0, RSTART+RLENGTH)
        key = ""
        value = ""
        if (match(line, /^"[^"]+": /)) {
          #line start with key
          key = substr(line, RSTART+1, RLENGTH-4)
          value = substr(line, RSTART+RLENGTH)
        } else {
          value = line
        }
        if (match(value, /^"/)) value = dim("\"") green() substr(value, 2)
        else if (match(value, /^[0-9.]+/)) value = yellow() value
        else if (match(value, /^null|undefined/)) value = green(dim(value))
        else if (match(value, /^true|false/)) value = green() value
        if (key) line = dim("\"") magenta(key) dim("\": ") value
        else line = value
        #eol
        if (match(line, /",?$/)) line = substr(line, 1, RSTART-1) noColor() dim(substr(line, RSTART))
        if (match(line, /\[?\],?$/)) line = substr(line, 1, RSTART-1) noColor() dim(substr(line, RSTART))
        if (match(line, /{?},?$/)) line = substr(line, 1, RSTART-1) noColor() dim(substr(line, RSTART))
        $0 = indent line
      }

      #yellow uuid
      while (match($0, /\[[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}\]/)) {
        $0 = substr($0, 1, RSTART) yellow(substr($0, RSTART+1, RLENGTH-2)) substr($0, RSTART+RLENGTH-1)
      }

      #dim \n
      gsub(/\\\\\n/, dim("\\\\\n"))

      #dim backslashes
      gsub(/\\\\\/, dim("\\\\\"))

      print
    }\'
  '
  eval $command \| $transform
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
