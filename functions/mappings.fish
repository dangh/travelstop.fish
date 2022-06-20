function mappings --argument-names from --description "print index mapping changes"
  argparse --ignore-unknown 'i/index' -- $argv
  if set --query _flag_index
    set --function from (git merge-base origin/master HEAD)
    set --function range $from
  else if test -z "$from"
    set --function from origin/master
    set --function range $from...
  else
    set --function range $from...
  end
  set --local manifests
  set --local root (git rev-parse --show-toplevel)
  set --local visited_dirs
  set --local printed 0

  set --function RED ''
  set --function CYAN ''
  set --function NORMAL ''
  if isatty stdout && ! set -q NO_COLOR
    set RED (set_color red)
    set CYAN (set_color cyan)
    set NORMAL (set_color normal)
    set BOLD (set_color --bold)
  end

  git diff --name-status $range $root/schema | grep -F 'index-mappings.json' | while read --local state file
    string match --quiet --regex '(?<index>[^/]+)-index-mappings.json' -- $file
    switch $state
    case 'D'
      test "$printed" -eq 1 && echo
      echo {$RED}DELETE{$NORMAL} {$CYAN}/{$BOLD}$index{$NORMAL}
      set printed 1
    case 'A'
      test "$printed" -eq 1 && echo
      echo {$RED}PUT{$NORMAL} {$CYAN}/{$BOLD}$index{$NORMAL}
      cat $root/$file | ts_indent_size=2 ts_json_quote_style= ts_json_bracket_style= ts_json_colon_style= awk -f ~/.config/fish/functions/logs.awk
      set printed 1
    case 'M'
      set --local diff (node -e "
const fs = require('fs');

let a = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
let b = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
console.log(JSON.stringify(diff(a.mappings, b.mappings)));

function diff(a, b) {
  let d = {};
  for (let k in b) {
    if (typeof a[k] != typeof b[k]) {
      d[k] = b[k];
    } else if(typeof a[k] != 'object') {
      if (a[k] != b[k]) {
        d[k] = b[k];
      }
    } else if (Array.isArray(a[k]) && Array.isArray(b[k])) {
      if (a.length != b.length || a[k].some((v, i) => v != b[k][i])) {
        d[k] = b[k];
      }
    } else {
      d[k] = diff(a[k], b[k]);
    }
  }
  //sanitize undefined values
  d = JSON.parse(JSON.stringify(d));
  if (Object.keys(d).length == 0) return undefined;
  return d;
}
" (git show $from:$file | psub) $root/$file)
      if test "$diff" != "undefined"
        test "$printed" -eq 1 && echo
        echo {$RED}PUT{$NORMAL} {$CYAN}/{$BOLD}$index{$NORMAL}/_mapping
        echo $diff | ts_indent_size=2 ts_json_quote_style= ts_json_bracket_style= ts_json_colon_style= awk -f ~/.config/fish/functions/logs.awk
        set printed 1
      end
    end
  end
end
