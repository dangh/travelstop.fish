function bold(s) { return sprintf("\x1b[1m%s%s", s, (!s ? "" : "\x1b[22m")) }
function dim(s) { return sprintf("\x1b[2m%s%s", s, (!s ? "" : "\x1b[22m")) }
function italic(s) { return sprintf("\x1b[3m%s%s", s, (!s ? "" : "\x1b[23m")) }
function underline(s) { return sprintf("\x1b[4m%s%s", s, (!s ? "" : "\x1b[24m")) }
function black(s) { return sprintf("\x1b[0m%s%s", s, (!s ? "" : "\x1b[39m")) }
function red(s) { return sprintf("\x1b[31m%s%s", s, (!s ? "" : "\x1b[39m")) }
function green(s) { return sprintf("\x1b[32m%s%s", s, (!s ? "" : "\x1b[39m")) }
function yellow(s) { return sprintf("\x1b[33m%s%s", s, (!s ? "" : "\x1b[39m")) }
function blue(s) { return sprintf("\x1b[34m%s%s", s, (!s ? "" : "\x1b[39m")) }
function magenta(s) { return sprintf("\x1b[35m%s%s", s, (!s ? "" : "\x1b[39m")) }
function cyan(s) { return sprintf("\x1b[36m%s%s", s, (!s ? "" : "\x1b[39m")) }
function noColor(s) { return sprintf("\x1b[39m%s", s) }
function metaStage(s) { return blue(s) }
function metaTimestamp(s) { return blue(s) }
function metaSourceFile(s) { return magenta(s) }
function metaSourceLine(s) { return bold(magenta(s)) }
function metaMethod(s) { return (s == "null") ? blue(s) : cyan(s) }
function metaLogLevel(s) { return (s == "ERROR") ? red(s) : (s == "WARN") ? yellow(s) : (s == "INFO") ? green(s) : blue(s) }
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
  #trim leading/trailing spaces
  gsub(/^[[:space:]]|[[:space:]]$/, "")

  if ($0 ~ /^(START|END|REPORT|XRAY)/) {
    gsub(/\t/, "\n  ")
    gsub(/:/, bold(":") dim())

    if ($0 ~ /^START RequestId/) {
      #mark start of request
      if (!REQUEST_MARK) REQUEST_MARK = "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
      $0 = REQUEST_MARK $0
    } else if ($0 ~ /^END RequestId/) {
      #blank line before end request
      $0 = "\n" $0
    }

    #dim aws messages
    $0 = dim($0)
  } else {
    #remove aws timestamp, log id, log level
    gsub(/^[0-9:. ()+-]{32}\t[[:alnum:]-]{36}\tINFO\t/, "")

    #highlight metadata
    if (match($0, /^\[([[:upper:]-]+)\]\[([[:digit:]TZ:.-]{24})\]\[([[:lower:].-]+):([[:digit:]]+)\]\[[[:alpha:].]+\]\[[[:upper:]]+\]: /)) {
      rest = substr($0, RLENGTH+1)
      split($0, tokens, /[[\]]/)
      stage = tokens[2]
      time = tokens[4]
      split(tokens[6], location, /:/)
      filename = location[1]
      lineno = location[2]
      method = tokens[8]
      level = tokens[10]
      $0 = metaDefault("[") metaStage(stage) metaDefault("]") \
           metaDefault("[") metaTimestamp(time) metaDefault("]") \
           metaDefault("[") metaSourceFile(filename) metaDefault(":") metaSourceLine(lineno) metaDefault("]") \
           metaDefault("[") metaMethod(method) metaDefault("]") \
           metaDefault("[") metaLogLevel(level) metaDefault("]") metaDefault(":") "\n" rest

      #blank line before each log entry
      $0 = "\n" $0
    }

    #yellow uuid
    s0 = ""
    s = $0
    while (match(s, /[^[:alnum:]-][[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}[^[:alnum:]-]/)) {
      uuid = substr(s, RSTART+1, RLENGTH-1-1)
      s0 = s0 substr(s, 1, RSTART) yellow(uuid)
      s = substr(s, RSTART+RLENGTH-1)
    }
    $0 = s0 s

    #format embedded json
    s0 = ""
    s = $0
    if (match(s, /"[{[]/)) {
      spaces = ""
      indent = 0
      tabSize = 2
      if (match(s, /^[[:space:]]+/)) spaces = substr(s, 1, RLENGTH)
      while (match(s, /\\"/) && match(s, /[[{}\],]/)) {
        m = substr(s, RSTART, RLENGTH)
        if (m == "{" || m == "[") {
          n = substr(s, RSTART+RLENGTH, 1)
          if (n == "]" || n == "}") {
            s0 = s0 jsonDefault(m) jsonDefault(n)
            s = substr(s, RSTART+RLENGTH+1)
          } else {
            indent += tabSize
            s0 = s0 substr(s, 1, RSTART-1) jsonDefault(m) "\n" spaces sprintf("%*s", indent, "")
            s = substr(s, RSTART+RLENGTH)
          }
        } else if (m == "}" || m == "]") {
          indent -= tabSize
          s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, "") jsonDefault(m)
          s = substr(s, RSTART+RLENGTH)
        } else if (m == ",") {
          s0 = s0 substr(s, 1, RSTART+RLENGTH-1-1) jsonDefault(m) "\n" spaces sprintf("%*s", indent, "")
          s = substr(s, RSTART+RLENGTH)
        }
        if (match(s, /^\\"[^"]+":/)) {
          key = substr(s, RSTART+2, RLENGTH-2-2-1)
          s0 = s0 substr(s, 1, RSTART+1) jsonKey(key) substr(s, RSTART+RLENGTH-2-1, 2) jsonColon(":") " "
          s = substr(s, RSTART+RLENGTH)
        }
        if (match(s, /^\\"/)) {
          openQuote = substr(s, RSTART, RLENGTH)
          s0 = s0 substr(s, 1, RSTART-1) jsonDefault(openQuote)
          s = substr(s, RSTART+RLENGTH)
          if (match(s, /\\"[,"}\]]/)) {
            closeQuote = substr(s, RSTART, RLENGTH-1)
            value = substr(s, 1, RSTART-1)
            s0 = s0 jsonString(value) jsonDefault(closeQuote)
            s = substr(s, RSTART+RLENGTH-1)
          }
        } else {
          value = ""
          if (match(s, /^-?[[:digit:]]+(.?[[:digit:]]+)?/)) value = jsonNumber(substr(s, RSTART, RLENGTH))
          else if (match(s, /^null/)) value = jsonNull(substr(s, RSTART, RLENGTH))
          else if (match(s, /^undefined/)) value = jsonUndefined(substr(s, RSTART, RLENGTH))
          else if (match(s, /^(true|false)/)) value = jsonBoolean(substr(s, RSTART, RLENGTH))
          if (value != "") {
            s0 = s0 substr(value, 1, RSTART-1) value
            s = substr(s, RSTART+RLENGTH)
          }
        }
      }
      while ((indent > 0) && match(s, /[}\]]/)) {
        m = substr(s, RSTART, RLENGTH)
        indent -= tabSize
        s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, "") jsonDefault(m)
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
      else if (match(value, /^-?[[:digit:]]+(.?[[:digit:]]+)?$/)) value = jsonNumber(value)
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
  }

  print
}
