function bold(s) { if (s == "") { return "\x1b[1m" } else { return sprintf("\x1b[1m%s\x1b[22m", s) } }
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
function metaStage(s) { return blue(s) }
function metaTimestamp(s) { return blue(s) }
function metaSourceFile(s) { return magenta(s) }
function metaSourceLocation(s) { return bold(magenta(s)) }
function metaMethod(s) { if (s == "null") { return blue(s) } else { return cyan(s) } }
function metaLogLevel(s) { if (s == "ERROR") { return red(s) } else if (s == "WARN") { return yellow(s) } else if (s == "INFO") { return green(s) } else { return blue(s) } }
function metaDefault(s) { return dim(blue(s)) }
function jsonKey(s) { return magenta(s) }
function jsonString(s) { return noColor(s) }
function jsonBoolean(s) { return green(s) }
function jsonNumber(s) { return green(s) }
function jsonNull(s) { return bold(s) }
function jsonUndefined(s) { return dim(s) }
function jsonDate(s) { return magenta(s) }
function jsonDefault(s) { return dim(noColor(s)) }
function jsonColon(s) { return dim(bold(s)) }
{
  #blank page before each event
  if ($0 ~ /^START RequestId/) printf "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"

  #blank line after last log entry
  if ($0 ~ /^END RequestId/) printf "\n"

  #dim aws logs
  gsub(/^(START|END|REPORT|XRAY) (RequestId|TraceId).*/, dim($0))

  #remove aws timestamp, log id, log level
  gsub(/^[0-9:. ()+-]{32}[[:space:]]+[a-z0-9-]{36}[[:space:]]+INFO[[:space:]]+/, "")

  #highlight metadata
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
    $0 = metaDefault("[") metaStage(stage) metaDefault("][") metaTimestamp(time) metaDefault("][") metaSourceFile(filename) metaDefault(":") metaSourceLocation(lineno) metaDefault("][") metaMethod(method) metaDefault("][") metaLogLevel(level) metaDefault("]:") "\n" rest

    #blank line before each log entry
    printf "\n"
    #reset all format
    printf "\x1b[0m"
  }

  #yellow uuid
  s0 = ""
  s = $0
  while (match(s, /[^a-z0-9-][a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}[^a-z0-9-]/)) {
    uuid = substr(s, RSTART+1, RLENGTH-1-1)
    s0 = s0 substr(s, 1, RSTART) yellow(uuid)
    s = substr(s, RSTART+RLENGTH-1)
  }
  $0 = s0 s

  #format embedded json
  s0 = ""
  s = $0
  spaces = ""
  indent = 0
  tabSize = 2
  if (match(s, /"[{[]/)) {
    if (match(s, "^[[:space:]]*")) {
      spaces = substr(s, 1, RLENGTH)
    }
    while (match(s, /\\"/) && match(s, /[[{}\],]/)) {
      m = substr(s, RSTART, RLENGTH)
      if (m == "{" || m == "[") {
        n = substr(s, RSTART+RLENGTH, 1)
        if (n == "]" || n == "}") {
          s0 = s0 jsonDefault(m) jsonDefault(n)
          s = substr(s, RSTART+RLENGTH+1)
        } else {
          indent += tabSize
          s0 = s0 substr(s, 1, RSTART-1) jsonDefault(m) "\n" spaces sprintf("%*s", indent, ((indent > 0)?" ":""))
          s = substr(s, RSTART+RLENGTH)
        }
      } else if (m == "}" || m == "]") {
        indent -= tabSize
        s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, ((indent > 0)?" ":"")) jsonDefault(m)
        s = substr(s, RSTART+RLENGTH)
      } else if (m == ",") {
        s0 = s0 substr(s, 1, RSTART+RLENGTH-1-1) jsonDefault(m) "\n" spaces sprintf("%*s", indent, ((indent > 0)?" ":""))
        s = substr(s, RSTART+RLENGTH)
      }
      if (match(s, /^\\"[^"]+":/)) {
        key = substr(s, RSTART+2, RLENGTH-2-2-1)
        s0 = s0 substr(s, 1, RSTART+1) jsonKey(key) substr(s, RSTART+RLENGTH-2-1, 2) jsonColon(":") " "
        s = substr(s, RSTART+RLENGTH)
      }
      if (match(s, /^\\"/)) {
        m = substr(s, RSTART, RLENGTH)
        s0 = s0 substr(s, 1, RSTART-1) jsonDefault(m)
        s = substr(s, RSTART+RLENGTH)
        if (match(s, /\\"[,"}\]]/)) {
          m = substr(s, RSTART, RLENGTH-1)
          value = substr(s, 1, RSTART-1)
          s0 = s0 jsonString(value) jsonDefault(m)
          s = substr(s, RSTART+RLENGTH-1)
        }
      } else if (match(s, /^[0-9.]+/)) {
        value = substr(s, RSTART, RLENGTH)
        s0 = s0 substr(s, 1, RSTART-1) jsonNumber(value)
        s = substr(s, RSTART+RLENGTH)
      } else if (match(s, /^null/)) {
        value = substr(s, RSTART, RLENGTH)
        s0 = s0 substr(s, 1, RSTART-1) jsonNull(value)
        s = substr(s, RSTART+RLENGTH)
      } else if (match(s, /^undefined/)) {
        value = substr(s, RSTART, RLENGTH)
        s0 = s0 substr(s, 1, RSTART-1) jsonUndefined(value)
        s = substr(s, RSTART+RLENGTH)
      } else if (match(s, /^(true|false)/)) {
        value = substr(s, RSTART, RLENGTH)
        s0 = s0 substr(s, 1, RSTART-1) jsonBoolean(value)
        s = substr(s, RSTART+RLENGTH)
      }
    }
    while ((indent > 0) && match(s, /[}\]]/)) {
      m = substr(s, RSTART, RLENGTH)
      indent -= tabSize
      s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, ((indent > 0)?" ":"")) jsonDefault(m)
      s = substr(s, RSTART+RLENGTH)
    }
  }
  $0 = s0 s

  #highlight json
  #start of json object/array
  if (match($0, /[{[]$/)) $0 = substr($0, 1, RSTART-1) jsonDefault(substr($0, RSTART, RLENGTH))
  #end of json object/array
  if (match($0, /^[}\]]/)) $0 = jsonDefault(substr($0, RSTART, RLENGTH)) substr($0, RSTART+RLENGTH)
  #inside json object/array
  if (match($0, /^[[:space:]]+/)) {
    s = $0
    indent = substr(s, RSTART, RLENGTH)
    s = substr(s, RSTART+RLENGTH)
    key = ""
    value = ""
    comma = ""
    if (match(s, /^"[^"]+": /)) {
      #line start with key
      key = substr(s, RSTART+1, RLENGTH-1-3)
      key = jsonDefault("\"") jsonKey(key) jsonDefault("\"") jsonColon(":") " "
      s = substr(s, RSTART+RLENGTH)
    }
    value = s
    if (match(value, /,$/)) {
      comma = substr(value, RSTART, RLENGTH)
      comma = jsonDefault(comma)
      value = substr(value, 1, RSTART-1)
    }
    if (match(value, /^".*"$/)) value = jsonDefault("\"") jsonString(substr(value, 2, RSTART+RLENGTH-3)) jsonDefault("\"")
    else if (match(value, /^[0-9.]+$/)) value = jsonNumber(value)
    else if (match(value, /^null$/)) value = jsonNull(value)
    else if (match(value, /^undefined$/)) value = jsonUndefined(value)
    else if (match(value, /^(true|false)$/)) value = jsonBoolean(value)
    else value = jsonDefault(value)
    #eol
    $0 = indent key value comma
  }

  #dim backslashes
  s0 = ""
  s = $0
  while (match(s, /\\/)) {
    s0 = s0 substr(s, 1, RSTART-1) dim(substr(s, RSTART, RLENGTH+1))
    s = substr(s, RSTART+RLENGTH+1)
  }
  $0 = s0 s

  print
}