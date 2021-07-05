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
function repeat(s, times) {
  s1 = ""
  for (i = 0; i < times; i++) s1 = s1 s
  return s1
}
function formatInlineJson(s, baseIndent, s0, key, value, indentLevel) {
  indentLevel = 0
  while (match(s, /[[{}\],]/)) {
    m = substr(s, RSTART, RLENGTH)
    n = substr(s, RSTART+RLENGTH, 1)
    if (m n ~ /{}|\[]/) {
      s0 = s0 substr(s, 1, RSTART-1) jsonBracket(m n)
      s = substr(s, RSTART+RLENGTH+1)
    } else if (m ~ /[{[]/) {
      indentLevel++
      s0 = s0 substr(s, 1, RSTART-1) jsonBracket(m) "\n" baseIndent repeat(TAB_CHAR, indentLevel)
      s = substr(s, RSTART+RLENGTH)
    } else if (m n ~ /[}\]]"/) {
      indentLevel--
      s0 = s0 substr(s, 1, RSTART-1) "\n" baseIndent repeat(TAB_CHAR, indentLevel) jsonBracket(m) jsonQuote(n)
      s = substr(s, RSTART+RLENGTH+1)
      continue  # end of embedded JSON, out to inline JSON
    } else if (m ~ /[}\]]/) {
      indentLevel--
      s0 = s0 substr(s, 1, RSTART-1) "\n" baseIndent repeat(TAB_CHAR, indentLevel) jsonBracket(m)
      s = substr(s, RSTART+RLENGTH)
    } else if (m ~ /,/) {
      s0 = s0 substr(s, 1, RSTART+RLENGTH-1-1) jsonComma(m) "\n" baseIndent repeat(TAB_CHAR, indentLevel)
      s = substr(s, RSTART+RLENGTH)
    }
    if (match(s, /^\\?"[^"]+\\?":/)) {
      quote = ((s ~ /^\\/) ? "\\\"" : "\"")
      colon = ":"
      key = substr(s, RSTART+length(quote), RLENGTH-length(quote)-length(quote)-length(colon))
      s0 = s0 jsonQuote(quote) jsonKey(key) jsonQuote(quote) jsonColon(colon) " "
      s = substr(s, RSTART+RLENGTH)
    }
    if (match(s, /^\\?"/)) {
      quote = substr(s, RSTART, RLENGTH)
      s0 = s0 jsonQuote(quote)
      s = substr(s, RSTART+RLENGTH)
      if (match(s, /\\?"[,"}\]]/)) {
        value = substr(s, 1, RSTART-1)
        s = substr(s, RSTART+RLENGTH-1)
        if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}/) {
          value = jsonUuid(value)
        } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z/) {
          value = jsonDate(value)
        } else if (value ~ /{\\"/) {
          value = formatInlineJson(value, baseIndent)
        } else {
          value = jsonString(value)
        }
        s0 = s0 value jsonQuote(quote)
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
  while ((indentLevel > 0) && match(s, /[}\]]/)) {
    m = substr(s, RSTART, RLENGTH)
    indentLevel--
    s0 = s0 substr(s, 1, RSTART-1) "\n" baseIndent repeat(TAB_CHAR, indentLevel) jsonBracket(m)
    s = substr(s, RSTART+RLENGTH)
  }
  return s0 s
}
function formatJson(s, indent, key, value, comma) {
  if (match(s, /^[[:blank:]]+/)) {
    indent = repeat(TAB_CHAR, int(RLENGTH/2))
    s = substr(s, RSTART+RLENGTH)
  }
  if (match(s, /^"[^"]+": /)) {
    key = jsonQuote("\"") jsonKey(substr(s, RSTART+1, RLENGTH-1-3)) jsonQuote("\"") jsonColon(":") " "
    s = substr(s, RSTART+RLENGTH)
  }
  if (match(s, /,$/)) {
    comma = jsonComma(substr(s, RSTART, RLENGTH))
    s = substr(s, 1, RSTART-1)
  }
  value = s
  if (match(value, /^".*"$/)) {
    value = substr(value, 2, RSTART+RLENGTH-3)
    if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}$/) {
      value = jsonUuid(value)
    } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z$/) {
      value = jsonDate(value)
    } else if (value ~ /\\"/) {
      value = formatInlineJson(value, indent)
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
  return indent key value comma
}
BEGIN {
  TAB_CHAR = noColor(dim(TAB_CHAR ? TAB_CHAR : "  "))
  REQUEST_MARK = REQUEST_MARK ? REQUEST_MARK : "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n"
}
{
  isCloudWatchLog = 0
  if ($0 ~ /^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(INFO|ERROR)\t/) {
    isCloudWatchLog = 1
  }

  if ($0 ~ /^(START|END|REPORT|XRAY)/) {
    level = ""

    gsub(":", bold(":") dim())
    s0 = ""
    s = $0
    while (match(s, /\t/)) {
      s0 = s0 substr(s, 1, RSTART-1)
      s = substr(s, RSTART+1)
      n = substr(s, RSTART+RLENGTH, 1)
      if (n ~ /[^[:blank:]]/) s0 = s0 "\n" TAB_CHAR dim()
    }
    $0 = s0 s

    if ($0 ~ /^START RequestId/) {
      #mark start of request
      $0 = REQUEST_MARK $0
    } else if ($0 ~ /^END RequestId/) {
      #blank line before end request
      $0 = "\n" $0
    }

    #dim aws messages
    $0 = dim($0)
  } else {
    if (isCloudWatchLog) {
      #collapse consecutive spaces
      s0 = ""
      s = $0
      while (match(s, /[^[:blank:]"][[:blank:]]{2,}/)) {
        s0 = s0 substr(s, 1, RSTART) " "
        s = substr(s, RSTART+RLENGTH)
      }
      $0 = s0 s

      #remove aws timestamp, log id, log level
      gsub(/^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(INFO|ERROR)\t/, "")

      #highlight metadata
      if (match($0, /^\[[[:upper:]-]+\]\[[[:digit:]TZ:.-]{24}\]\[[[:lower:].-]+:[[:digit:]]+\](\[[[:alpha:].]+\])?\[[[:upper:]]+\]: /)) {
        rest = substr($0, RLENGTH+1)
        split(substr($0, 2, RLENGTH-3), tokens, /[[\]]+/)
        stage = tokens[1]
        time = tokens[2]
        split(tokens[3], location, /:/)
        filename = location[1]
        lineno = location[2]
        method = tokens[4]
        level = tokens[5]
        if (!level) {
          level = method
          method = ""
        }
        $0 = metaDefault("[") metaStage(stage) metaDefault("]") \
             metaDefault("[") metaTimestamp(time) metaDefault("]") \
             metaDefault("[") metaSourceFile(filename) metaDefault(":") metaSourceLine(lineno) metaDefault("]") \
             (method ? metaDefault("[") metaMethod(method) metaDefault("]") : "") \
             metaDefault("[") metaLogLevel(level) metaDefault("]") metaDefault(":") "\n" rest
      }
    }

    if (match($0, /{"/)) {
      preceeding = substr($0, 1, RSTART-1)
      rest = substr($0, RSTART)
      if (match($0, /^[[:blank:]]+/)) indent = repeat(TAB_CHAR, int(RLENGTH/2))
      $0 = preceeding formatInlineJson(rest, indent)
    }
    if (isJson) {
      if (match($0, /^[\]}]/)) {
        # end of JSON object
        isJson = 0
        rest = substr($0, RSTART+RLENGTH)
        $0 = jsonBracket(substr($0, RSTART, RLENGTH)) rest
      } else {
        # inside JSON object
        $0 = formatJson($0)
      }
    }
    if (match($0, /[{[]$/)) {
      # start of JSON object
      isJson = 1
      $0 = substr($0, 1, RSTART-1) jsonBracket(substr($0, RSTART, RLENGTH))
    }

    if (level == "ERROR") {
      if (match($0, /^[[:blank:]]+/)) {
        $0 = repeat(TAB_CHAR, int(RLENGTH/4)) red(substr($0, RSTART+RLENGTH))
      } else {
        $0 = red($0)
      }
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

    if (isCloudWatchLog) {
      #blank line before each log entry
      $0 = "\n" $0
    }
  }

  print
}
