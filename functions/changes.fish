function changes --argument-names type --description "print list of changes"
  set --local args $argv
  argparse --ignore-unknown f/from= -- $argv
  test -z "$_flag_from" -o "$_flag_from" = merge-base &&
    set --append args --merge-base (git merge-base origin/master HEAD)
  switch "$type"
    case 'stacks'
      _change_stacks $args[2..]
    case 'mappings'
      _change_mappings $args[2..]
    case 'translations'
      _change_translations $args[2..]
    case '*'
      _change_stacks $args | read --null --list --delimiter \n --local changes && set --erase changes[-1]
      if test -n "$changes"
        echo (magenta (reverse (dim '**')(bold 'Packages')(dim '**')))
        echo (magenta (dim '-'))
        echo
        string join \n -- $changes
        set --function changed
      end
      _change_mappings $args | read --null --list --delimiter \n --local changes && set --erase changes[-1]
      if test -n "$changes"
        set --query --function changed && echo
        echo (magenta (reverse (dim '**')(bold 'Mappings')(dim '**')))
        echo (magenta (dim '-'))
        echo
        echo (magenta (dim '```http'))
        string join \n -- $changes
        echo (magenta (dim '```'))
        set --function changed
      end
      _change_translations $args | read --null --list --delimiter \n --local changes && set --erase changes[-1]
      if test -n "$changes"
        set --query --function changed && echo
        echo (magenta (reverse (dim '**')(bold 'Translations')(dim '**')))
        echo (magenta (dim '-'))
        echo
        string join \n -- $changes
      end
  end
end

function _change_stacks --description "print list of changed services and modules"
  argparse --ignore-unknown f/from= t/to= merge-base= -- $argv
  set --local from $_flag_from
  set --local to $_flag_to

  test -z "$from" && set from 'merge-base'
  test "$from" = 'merge-base' && set from $_flag_merge_base
  test -z "$to" && set to 'index'
  if test "$to" = 'index'
    set --function range $from
  else
    set --function range $from...$to
  end

  set --local manifests
  set --local root (git rev-parse --show-toplevel)
  set --local visited_dirs
  git diff --name-only $range | grep -E '^(admin/)?(modules|services|web)/' | while read --line --local file
    set --local dir $file
    set --local found 0
    while test $found -eq 0 && set dir (string replace --regex '/[^/]+$' '' $dir) && ! contains $dir $visited_dirs && set --append visited_dirs $dir
      for manifest in $root/$dir/package.json $root/$dir/nodejs/package.json $root/$dir/serverless.yml
        if test -f $manifest
          set found 1
          if not contains $manifest $manifests
            set --append manifests $manifest
          end
          break
        end
      end
    end
  end
  set --local stack_names
  set --local stack_versions
  for manifest in $manifests
    set --local v
    switch $manifest
    case '*/package.json'
      string match --quiet --regex '"name": "(travelstop-)?(?<name>[^"]+)"' < $manifest
      string match --quiet --regex '"version": "(?<v>[^"]+)"' < $manifest
    case '*/serverless.yml'
      string match --quiet --regex '^service:\s*(?<name>module-\w+|\S+)\S*\s*$' < $manifest
    end
    if test -z "$v"
      set --local changelog (string replace --regex '[^/]+$' 'CHANGELOG.md' $manifest)
      if test -f $changelog
        string match --quiet --regex '# (?<v>\d+(\.\d+)+)' < $changelog
      end
    end
    set --append stack_names $name
    set --append stack_versions "$v"
  end
  for name in $stack_names
    set --local v $stack_versions[(contains --index -- $name $stack_names)]
    set --local group (string match --regex '^\w+' $name | string replace --regex 's$' '')
    set --local group_order 1
    set --local stack_order 1
    switch $name
    case 'module-*'
      set group_order 0
    case '*web'
      set group_order 3
    case 'admin-*'
      set group_order 2
    case '*-resources'
      set stack_order 0
    end
    test -n "$v" && set v -$v
    echo $name$v $group_order $group $stack_order
  end | sort --key=2,2n --key=3,3 --key=4,4n | string replace --regex '^([^\s]+).*' -- (magenta (dim '-'))' $1'
end

function _change_mappings --description "print elasticsearch index mapping changes"
  argparse --ignore-unknown f/from= t/to= merge-base= -- $argv
  set --local from $_flag_from
  set --local to $_flag_to

  test -z "$from" && set from 'merge-base'
  test "$from" = 'merge-base' && set from $_flag_merge_base
  test -z "$to" && set to 'index'
  if test "$to" = 'index'
    set --function range $from
  else
    set --function range $from...$to
  end

  set --local manifests
  set --local root (git rev-parse --show-toplevel)
  set --local visited_dirs
  set --local printed 0

  git diff --name-status $range $root/schema | grep -F 'index-mappings.json' | while read --local state file
    set --local --export ts_indent_size 2
    set --local --export ts_json_bracket_style
    set --local --export ts_json_colon_style
    set --local --export ts_json_quote_style fg=brightblue,dim
    set --local --export ts_json_string_style fg=brightblue,dim
    set --local --export ts_json_key_style fg=brightblue
    string match --quiet --regex '(?<index>[^/]+)-index-mappings.json' -- $file
    switch $state
    case 'D'
      test "$printed" -eq 1 && echo
      echo (red DELETE) (cyan /(bold $index))
      set printed 1
    case 'A'
      test "$printed" -eq 1 && echo
      echo (red PUT) (cyan /(bold $index))
      cat $root/$file | awk -f ~/.config/fish/functions/logs.awk
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
    if (d[k] && (k == 'properties') && (typeof b.type == 'string')) {
      //re-write properties after type
      let properties = d.properties;
      delete d.properties;
      d.type = b.type;
      d.properties = properties;
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
        echo (red PUT) (cyan /(bold $index))/_mapping
        echo $diff | awk -f ~/.config/fish/functions/logs.awk
        set printed 1
      end
    end
  end
end

function _change_translations --description "print list of new translation keys"
  argparse --ignore-unknown f/from= t/to= merge-base= -- $argv
  set --local from $_flag_from
  set --local to $_flag_to

  test -z "$from" && set from origin/master
  test "$from" = 'merge-base' && set from $_flag_merge_base
  test -z "$to" && set to 'index'
  test "$to" = 'index' && set to ''

  set --local jq_transform 'paths(scalars) as $path | ( $path | join(".") ) + " = " + getpath($path)'
  set --local placeholder (ansi-escape --yellow --bold --reverse '$1')
  comm -13 \
    (git show $from:web/locales/en-GB.json | jq --raw-output "$jq_transform" | sort | psub) \
    (git show $to:web/locales/en-GB.json | jq --raw-output "$jq_transform" | sort | psub) |
    while read --delimiter ' = ' --local key value
      if test -n "$value"
        echo (green $key) (dim '=') (string replace --regex '({\w+})' $placeholder -- $value)
      else
        echo (green $key)
      end
    end
end
