function get_style(name) {
  if ( name == "meta_stage"       ) { return env( "meta_stage_style"       , "fg=blue"         ) }
  if ( name == "meta_timestamp"   ) { return env( "meta_timestamp_style"   , "fg=blue"         ) }
  if ( name == "meta_source_file" ) { return env( "meta_source_file_style" , "fg=magenta"      ) }
  if ( name == "meta_source_line" ) { return env( "meta_source_line_style" , "fg=magenta,bold" ) }
  if ( name == "meta_method"      ) { return env( "meta_method_style"      , "fg=cyan"         ) }
  if ( name == "meta_log_level"   ) { return env( "meta_log_level_style"   , "fg=blue"         ) }
  if ( name == "meta"             ) { return env( "meta_style"             , "fg=blue,dim"     ) }
  if ( name == "json_key"         ) { return env( "json_key_style"         , "fg=magenta"      ) }
  if ( name == "json_string"      ) { return env( "json_string_style"      , ""                ) }
  if ( name == "json_boolean"     ) { return env( "json_boolean_style"     , "fg=green"        ) }
  if ( name == "json_number"      ) { return env( "json_number_style"      , "fg=green"        ) }
  if ( name == "json_null"        ) { return env( "json_null_style"        , "bold"            ) }
  if ( name == "json_undefined"   ) { return env( "json_undefined_style"   , "dim"             ) }
  if ( name == "json_date"        ) { return env( "json_date_style"        , ""                ) }
  if ( name == "json_uuid"        ) { return env( "json_uuid_style"        , "fg=yellow"       ) }
  if ( name == "json_colon"       ) { return env( "json_colon_style"       , "dim,bold"        ) }
  if ( name == "json_quote"       ) { return env( "json_quote_style"       , "dim"             ) }
  if ( name == "json_bracket"     ) { return env( "json_bracket_style"     , "dim"             ) }
  if ( name == "json_comma"       ) { return env( "json_comma_style"       , "dim"             ) }
  if ( name == "uuid"             ) { return env( "uuid_style"             , "fg=yellow"       ) }
  if ( name == "indent_guide"     ) { return env( "indent_guide_style"     , "reverse"         ) }
  if ( name == "blank_page"       ) { return env( "blank_page_style"       , ""                ) }
  return env(name, name)
}
function repeat(s, n, sep, out) { if (n > 0) out = s; for (i = 2; i <= n; i++) out = out sep s; return out; }
function default(value, fallback) { return !value ? fallback : value }
function env(key, default) { return "ts_" key in ENVIRON ? ENVIRON["ts_" key] : default }
function format(style_str, s, force, on, off, style_arr, count) {
  if (NO_COLOR == 1) return s

  count = split(get_style(style_str), style_arr, ",")
  for (i = 1; i <= count; i++) {
    style = style_arr[i]
    if (style ~ /^none$/) on = on ";0"
    if (style ~ /^(bold|bright)$/) on = on ";1"
    if (style ~ /^(no)?(bold|bright)$/) off = off ";22"
    if (style ~ /^dim$/) on = on ";2"
    if (style ~ /^(no)?dim$/) off = off ";22"
    if (style ~ /^italics$/) on = on ";3"
    if (style ~ /^(no)?italics$/) off = off ";23"
    if (style ~ /^under(score|line)$/) on = on ";4"
    if (style ~ /^(no)?under(score|line)$/) off = off ";24"
    if (style ~ /^blink$/) on = on ";5"
    if (style ~ /^(no)?blink$/) off = off ";25"
    if (style ~ /^reverse$/) on = on ";7"
    if (style ~ /^(no)?reverse$/) off = off ";27"
    if (style ~ /^hidden$/) on = on ";8"
    if (style ~ /^(no)?hidden$/) off = off ";28"
    if (style ~ /^strikethrough$/) on = on ";9"
    if (style ~ /^(no)?strikethrough$/) off = off ";29"
    if (style ~ /^overline$/) on = on ";53"
    if (style ~ /^(no)?overline$/) off = off ";55"
    if (style ~ /^fg=/) {
      if (style ~ /^fg=black$/) on = on ";30"
      if (style ~ /^fg=red$/) on = on ";31"
      if (style ~ /^fg=green$/) on = on ";32"
      if (style ~ /^fg=yellow$/) on = on ";33"
      if (style ~ /^fg=blue$/) on = on ";34"
      if (style ~ /^fg=magenta$/) on = on ";35"
      if (style ~ /^fg=cyan$/) on = on ";36"
      if (style ~ /^fg=[0-9]+$/) on = on ";38;5;" substr(style, 4)
      if (style ~ /^fg=#[A-Fa-f0-9]{6}$/) on = on ";38;2;" sprintf("%d;%d;%d", "0x" substr(style, 5, 2), "0x" substr(style, 7, 2), "0x" substr(style, 9, 2))
      if (style ~ /^fg=none$/) {
        on = on ";39"
      } else {
        off = off ";39"
      }
    }
    if (style ~ /^bg=/) {
      if (style ~ /^bg=black$/) on = on ";40"
      if (style ~ /^bg=red$/) on = on ";41"
      if (style ~ /^bg=green$/) on = on ";42"
      if (style ~ /^bg=yellow$/) on = on ";43"
      if (style ~ /^bg=blue$/) on = on ";44"
      if (style ~ /^bg=magenta$/) on = on ";45"
      if (style ~ /^bg=cyan$/) on = on ";46"
      if (style ~ /^bg=[0-9]+$/) on = on ";48;5;" substr(style, 4)
      if (style ~ /^bg=#[A-Fa-f0-9]{6}$/) on = on ";48;2;" sprintf("%d;%d;%d", "0x" substr(style, 5, 2), "0x" substr(style, 7, 2), "0x" substr(style, 9, 2))
      if (style ~ /^bg=none$/) {
        on = on ";49"
      } else {
        off = off ";49"
      }
    }
  }
  if (on) on = "\x1b[" substr(on, 2) "m"
  if (off) off = "\x1b[" substr(off, 2) "m"
  if (s || force) return on s off
}
function indent_guide(level) { if (level) return format("none", "", 1) repeat(INDENT_GUIDE, level) format("none", "", 1) }
function format_inline_json(s, base_indent, key, value, indent_level, quote, open_bracket, close_bracket, close_quote, m, n, colon, inline_object) {
  indent_level = 0
  inline_object = 0
  while (match(s, /[[{}\],]/)) {
    m = substr(s, RSTART, RLENGTH)
    n = substr(s, RSTART+RLENGTH, 1)
    if (m n ~ /{}|\[]/) {
      open_bracket = m
      close_bracket = n
      printf "%s", substr(s, 1, RSTART-1) format("json_bracket", open_bracket close_bracket)
      s = substr(s, RSTART+RLENGTH+1)
    } else if (m ~ /[{[]/) {
      open_bracket = m
      printf "%s", substr(s, 1, RSTART-1) format("json_bracket", open_bracket)
      s = substr(s, RSTART+RLENGTH)
      # inline simple object
      if (env("inline_simple_object", 1) && s ~ /^"[^"]+":("[^"]{1,40}"|(\d+(\.\d+))")[}\]]/) {
        inline_object = 1
        printf " "
      } else {
        indent_level++
        printf "\n"
        printf "%s", base_indent indent_guide(indent_level)
      }
    } else if (m n ~ /[}\]]"/) {
      indent_level--
      close_bracket = m
      close_quote = n
      printf "%s", substr(s, 1, RSTART-1) "\n"
      printf "%s", base_indent indent_guide(indent_level)
      printf "%s", format("json_bracket", close_bracket) format("json_quote", close_quote)
      s = substr(s, RSTART+RLENGTH+1)
      continue  # end of embedded JSON, out to inline JSON
    } else if (m ~ /[}\]]/) {
      close_bracket = m
      if (env("inline_simple_object", 1) && inline_object) {
        inline_object = 0
        printf " "
      } else {
        indent_level--
        printf "%s", substr(s, 1, RSTART-1) "\n"
        printf "%s", base_indent indent_guide(indent_level)
      }
      printf "%s", format("json_bracket", close_bracket)
      s = substr(s, RSTART+RLENGTH)
    } else if (m ~ /,/) {
      comma = m
      printf "%s", substr(s, 1, RSTART+RLENGTH-1-1) format("json_comma", comma) "\n"
      printf "%s", base_indent indent_guide(indent_level)
      s = substr(s, RSTART+RLENGTH)
    }
    if (match(s, /^\\?"[^"]+\\?"[[:space:]]*:[[:space:]]*/)) {
      quote = ((s ~ /^\\/) ? "\\\"" : "\"")
      key = substr(s, RSTART+length(quote), RLENGTH-length(quote))
      s = substr(s, RSTART+RLENGTH)
      match(key, /[[:space:]]*:[[:space:]]*$/)
      colon = substr(key, RSTART, RLENGTH)
      key = substr(key, 1, length(key)-length(quote)-length(colon))
      printf "%s", format("json_quote", quote) format("json_key", key) format("json_quote", quote) format("json_colon", colon) " "
    }
    if (match(s, /^\\?"/)) {
      quote = substr(s, RSTART, RLENGTH)
      printf "%s", format("json_quote", quote)
      s = substr(s, RSTART+RLENGTH)
      if (match(s, /\\?"[,"}\]]/)) {
        value = substr(s, 1, RSTART-1)
        s = substr(s, RSTART+RLENGTH-1)
        if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}/) {
          printf "%s", format("json_uuid", value)
        } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z/) {
          printf "%s", format("json_date", value)
        } else if (value ~ /{\\"/) {
          format_inline_json(value, base_indent)
        } else {
          printf "%s", format("json_string", value)
        }
        printf "%s", format("json_quote", quote)
      }
    } else {
      value = ""
      if (match(s, /^-?[[:digit:]]+(\.?[[:digit:]]+)?(e-?[[:digit:]]+)?/)) {
        value = substr(s, RSTART, RLENGTH)
        printf "%s", format("json_number", value)
      } else if (match(s, /^null/)) {
        value = substr(s, RSTART, RLENGTH)
        printf "%s", format("json_null", value)
      } else if (match(s, /^undefined/)) {
        value = substr(s, RSTART, RLENGTH)
        printf "%s", format("json_undefined", value)
      } else if (match(s, /^(true|false)/)) {
        value = substr(s, RSTART, RLENGTH)
        printf "%s", format("json_boolean", value)
      }
      if (value != "") {
        s = substr(s, RSTART+RLENGTH)
      }
    }
  }
  while ((indent_level > 0) && match(s, /[}\]]/)) {
    m = substr(s, RSTART, RLENGTH)
    indent_level--
    printf "%s", substr(s, 1, RSTART-1) "\n"
    printf "%s", base_indent indent_guide(indent_level)
    printf "%s", format("json_bracket", m)
    s = substr(s, RSTART+RLENGTH)
  }
  return s
}
function format_json(s, indent, key, value, comma) {
  if (match(s, /^[[:blank:]]+/)) {
    indent = indent_guide(int(RLENGTH/2))
    printf "%s", indent
    s = substr(s, RSTART+RLENGTH)
  }
  if (match(s, /^"[^"]+"[[:space:]]*:[[:space:]]*/)) {
    quote = "\""
    key = substr(s, RSTART+length(quote), RLENGTH-length(quote))
    s = substr(s, RSTART+RLENGTH)
    match(key, /[[:space:]]*:[[:space:]]*$/)
    colon = substr(key, RSTART, RLENGTH)
    key = substr(key, 1, length(key)-length(quote)-length(colon))
    printf "%s", format("json_quote", quote) format("json_key", key) format("json_quote", quote) format("json_colon", ":") " "
  }
  if (match(s, /,$/)) {
    comma = substr(s, RSTART, RLENGTH)
    s = substr(s, 1, RSTART-1)
  }
  value = s
  if (match(value, /^".*"$/)) {
    quote = "\""
    printf "%s", format("json_quote", quote)
    value = substr(value, 2, RSTART+RLENGTH-3)
    if (value ~ /^[[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}$/) {
      printf "%s", format("json_uuid", value)
    } else if (value ~ /^[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}T[[:digit:]]{2}:[[:digit:]]{2}:[[:digit:]]{2}(\.[[:digit:]]{3})?Z$/) {
      printf "%s", format("json_date", value)
    } else if (value ~ /\\"/) {
      s = format_inline_json(value, indent)
    } else {
      printf "%s", format("json_string", value)
    }
    printf "%s", format("json_quote", quote)
  } else if (value ~ /^-?[[:digit:]]+(\.?[[:digit:]]+)?(e-?[[:digit:]]+)?$/) {
    printf "%s", format("json_number", value)
  } else if (value ~ /^null$/) {
    printf "%s", format("json_null", value)
  } else if (value ~ /^undefined$/) {
    printf "%s", format("json_undefined", value)
  } else if (value ~ /^(true|false)$/) {
    printf "%s", format("json_boolean", value)
  } else {
    printf "%s", format("json_bracket", value)
  }
  printf "%s", format("json_comma", comma)
}
BEGIN {
  INDENT_GUIDE = format("indent_guide", default(substr(env("indent_chars"), 1, 1), " ")) repeat(default(substr(env("indent_chars"), 2, 1), " "), default(env("indent_size"), 4) - 1)
  BLANK_PAGE = default(env("blank_page"), format("blank_page") repeat("\x1b[2K", default(env("blank_page_height"), 1), "\n"))
  NO_COLOR = "NO_COLOR" in ENVIRON ? 1 : 0
}
{
  is_cloudwatch_log = 0
  if ($0 ~ /^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(ERROR|WARN|INFO|DEBUG)\t/) {
    is_cloudwatch_log = 1
  }

  if ($0 ~ /^(START|END|REPORT|XRAY)/) {
    level = ""

    if ($0 ~ /^START RequestId/) {
      #blank lines before each request
      print format("none", "", 1)
      if (env("blank_page_cmd")) {
        system(env("blank_page_cmd"))
      } else {
        print BLANK_PAGE
      }
      print format("none", "", 1)
    } else if ($0 ~ /^END RequestId/) {
      #blank line before end request
      printf "%s", "\n"
    }

    gsub(":", format("bold,dim", ":") format("dim", "", 1))
    s0 = ""
    s = $0
    while (match(s, /\t+/)) {
      s0 = s0 substr(s, 1, RSTART-1)
      s = substr(s, RSTART+RLENGTH)
      if (s ~ /[^[:blank:]]/) {
        s0 = s0 "\n" indent_guide(RLENGTH) format("dim", "", 1)
      }
    }
    $0 = s0 s

    #dim aws messages
    $0 = format("dim", $0)
  } else {
    if (is_cloudwatch_log) {
      #collapse consecutive spaces
      s0 = ""
      s = $0
      while (match(s, /[^[:blank:]"][[:blank:]]{2,}/)) {
        s0 = s0 substr(s, 1, RSTART) " "
        s = substr(s, RSTART+RLENGTH)
      }
      $0 = s0 s

      #remove aws timestamp, log id, log level
      gsub(/^[0-9:. ()+-]{32}\t([[:alnum:]-]{36}|undefined)\t(ERROR|WARN|INFO|DEBUG)\t/, "")

      #highlight metadata
      if (match($0, /^\[[[:upper:]-]+\]\[[[:digit:]TZ:.-]{24}\]\[[[:lower:].-]+:[[:digit:]]+\](\[[[:alpha:]. ]+\])?\[[[:upper:]]+\]: /)) {
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
        $0 = format("meta", "[") format("meta_stage", stage) format("meta", "]") \
             format("meta", "[") format("meta_timestamp", time) format("meta", "]") \
             format("meta", "[") format("meta_source_file", filename) format("meta", ":") format("meta_source_line", lineno) format("meta", "]") \
             (method ? format("meta", "[") format("meta_method", method) format("meta", "]") : "") \
             format("meta", "[") format("meta_log_level", level) format("meta", "]") format("meta", ":") "\n" rest
      }
    }

    if (match($0, /{"/)) {
      preceeding = substr($0, 1, RSTART-1)
      rest = substr($0, RSTART)
      if (match($0, /^[[:blank:]]+/)) indent = indent_guide(int(RLENGTH/2))
      $0 = preceeding format_inline_json(rest, indent)
    }
    if (isJson) {
      if (match($0, /^[\]}]/)) {
        # end of JSON object
        isJson = 0
        rest = substr($0, RSTART+RLENGTH)
        $0 = format("json_bracket", substr($0, RSTART, RLENGTH)) rest
      } else {
        # inside JSON object
        $0 = format_json($0)
      }
    }
    if (match($0, /[{[]$/)) {
      # start of JSON object
      isJson = 1
      $0 = substr($0, 1, RSTART-1) format("json_bracket", substr($0, RSTART, RLENGTH))
    }

    if (level == "ERROR") {
      if (match($0, /^[[:blank:]]+/)) {
        $0 = indent_guide(int(RLENGTH/4)) format("fg=red", substr($0, RSTART+RLENGTH))
      } else {
        $0 = format("fg=red", $0)
      }
    }

    #highlight uuid
    s0 = ""
    s = $0
    while (match(s, /[^[:alnum:]-][[:alnum:]]{8}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{4}-[[:alnum:]]{12}[^[:alnum:]-]/)) {
      value = substr(s, RSTART+1, RLENGTH-1-1)
      s0 = s0 substr(s, 1, RSTART) format("uuid", value)
      s = substr(s, RSTART+RLENGTH-1)
    }
    $0 = s0 s

    if (is_cloudwatch_log) {
      #blank line before each log entry
      $0 = "\n" $0
    }
  }

  print
}
