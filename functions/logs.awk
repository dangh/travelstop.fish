function bold(s) { return sprintf("\x1b[1m%s%s", s, (!s ? "" : "\x1b[22m")) }
function dim(s) { return sprintf("\x1b[2m%s%s", s, (!s ? "" : "\x1b[22m")) }
function noDim() { return "\x1b[22m" }
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
function uuid(s) { gsub("-", dim("-"), s); return yellow(s); }
function jsonKey(s) { return magenta(s) }
function jsonString(s) { return noColor(s) }
function jsonBoolean(s) { return green(s) }
function jsonNumber(s) { return green(s) }
function jsonNull(s) { return bold(s) }
function jsonUndefined(s) { return dim(s) }
function jsonDate(s) { return jsonString(s) }
function jsonUuid(s) { return uuid(s) }
function jsonColon(s) { return dim(bold(s)) }
function jsonQuote(s) { return dim(noColor(s)) }
function jsonBracket(s) { return dim(noColor(s)) }
function jsonComma(s) { return dim(noColor(s)) }
{
  if ($0 ~ /^(START|END|REPORT|XRAY)/) {
    gsub("\t", "\n  ")
    gsub(":", bold(":") dim())

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
    if ($0 ~ /^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(INFO|ERROR)\t/) {
      isCloudWatchLog = 1
    }

    if (isCloudWatchLog) {
      #remove consecutive spaces
      s0 = ""
      s = $0
      while (match(s, /[^[:space:]][[:space:]]{2,}/)) {
        s0 = s0 substr(s, 1, RSTART) " "
        s = substr(s, RSTART+RLENGTH)
      }
      $0 = s0 s

      #remove aws timestamp, log id, log level
      gsub(/^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(INFO|ERROR)\t/, "")

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

      #format embedded json
      if (s ~ /"[{[]/) {
        s0 = ""
        s = $0
        spaces = ""
        indent = 0
        tabSize = 2
        if (match(s, /^[[:space:]]+/)) {
          spaces = substr(s, 1, RLENGTH)
        }
        while ((s ~ /\\?"/) && match(s, /[[{}\],]/)) {
          m = substr(s, RSTART, RLENGTH)
          if (m == "{" || m == "[") {
            n = substr(s, RSTART+RLENGTH, 1)
            if (n == "]" || n == "}") {
              s0 = s0 substr(s, 1, RSTART-1) jsonBracket(m) jsonBracket(n)
              s = substr(s, RSTART+RLENGTH+1)
            } else {
              indent += tabSize
              s0 = s0 substr(s, 1, RSTART-1) jsonBracket(m) "\n" spaces sprintf("%*s", indent, "")
              s = substr(s, RSTART+RLENGTH)
            }
          } else if (m == "}" || m == "]") {
            indent -= tabSize
            s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, "") jsonBracket(m)
            s = substr(s, RSTART+RLENGTH)
          } else if (m == ",") {
            s0 = s0 substr(s, 1, RSTART+RLENGTH-1-1) jsonComma(m) "\n" spaces sprintf("%*s", indent, "")
            s = substr(s, RSTART+RLENGTH)
          }
          if (match(s, /^\\?"[^"]+\\?":/)) {
            quote = substr(s, 0, 1) == "\\" ? "\\\"" : "\""
            colon = ":"
            key = substr(s, RSTART+length(quote), RLENGTH-length(quote)-length(quote)-length(colon))
            quote = (substr(quote, 0, 1) == "\\" ? "\\" : "") jsonQuote("\"")
            s0 = s0 jsonQuote(quote) jsonKey(key) jsonQuote(quote) jsonColon(colon) " "
            s = substr(s, RSTART+RLENGTH)
          }
          if (match(s, /^\\?"/)) {
            quote = substr(s, RSTART, RLENGTH)
            s0 = s0 jsonQuote(quote)
            s = substr(s, RSTART+RLENGTH)
            if (s ~ /^[[{]/) {
              #begin of embedded json
              continue
            }
            if (match(s, /\\?"[,"}\]]/)) {
              value = substr(s, 1, RSTART-1)
              if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}/) {
                value = jsonUuid(value)
              } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z/) {
                value = jsonDate(value)
              } else {
                value = jsonString(value)
              }
              s0 = s0 value jsonQuote(quote)
              s = substr(s, RSTART+RLENGTH-1)
            }
          } else {
            value = ""
            if (match(s, /^-?[[:digit:]]+(\.?[[:digit:]]+)?/)) {
              value = jsonNumber(substr(s, RSTART, RLENGTH))
            } else if (match(s, /^null/)) {
              value = jsonNull(substr(s, RSTART, RLENGTH))
            } else if (match(s, /^undefined/)) {
              value = jsonUndefined(substr(s, RSTART, RLENGTH))
            } else if (match(s, /^(true|false)/)) {
              value = jsonBoolean(substr(s, RSTART, RLENGTH))
            }
            if (value != "") {
              s0 = s0 substr(value, 1, RSTART-1) value
              s = substr(s, RSTART+RLENGTH)
            }
          }
        }
        while ((indent > 0) && match(s, /[}\]]/)) {
          m = substr(s, RSTART, RLENGTH)
          indent -= tabSize
          s0 = s0 substr(s, 1, RSTART-1) "\n" spaces sprintf("%*s", indent, "") jsonBracket(m)
          s = substr(s, RSTART+RLENGTH)
        }
        $0 = s0 s
      }

      #highlight json
      #open/close of json object/array
      gsub(/[{[]$|^[}\]]/, jsonBracket("&"))
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
          key = jsonQuote("\"") jsonKey(key) jsonQuote("\"") jsonColon(":") " "
          s = substr(s, RSTART+RLENGTH)
        }
        value = s
        if (match(value, /,$/)) {
          comma = substr(value, RSTART, RLENGTH)
          comma = jsonComma(comma)
          value = substr(value, 1, RSTART-1)
        }
        if (match(value, /^".*"$/)) {
          value = substr(value, 2, RSTART+RLENGTH-3)
          if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}$/) {
            value = jsonUuid(value)
          } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z$/) {
            value = jsonDate(value)
          } else {
            value = jsonString(value)
          }
          value = jsonQuote("\"") value jsonQuote("\"")
        } else if (value ~ /^-?[[:digit:]]+(\.?[[:digit:]]+)?$/) {
          value = jsonNumber(value)
        } else if (value ~ /^null$/) {
          value = jsonNull(value)
        } else if (value ~ /^undefined$/) {
          value = jsonUndefined(value)
        } else if (value ~ /^(true|false)$/) {
          value = jsonBoolean(value)
        } else {
          value = jsonBracket(value)
        }
        #eol
        $0 = indent key value comma
      }

      #yellow uuid
      s0 = ""
      s = $0
      while (match(s, /[^[:alnum:]-][[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}[^[:alnum:]-]/)) {
        value = substr(s, RSTART+1, RLENGTH-1-1)
        s0 = s0 substr(s, 1, RSTART) uuid(value)
        s = substr(s, RSTART+RLENGTH-1)
      }
      $0 = s0 s
    }
  }

  print
}
