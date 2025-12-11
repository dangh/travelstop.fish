function changes -a type -d "print list of changes"
    set -l args $argv
    argparse -i f/from= -- $argv
    test -z "$_flag_from" -o "$_flag_from" = merge-base &&
        set -a args --merge-base (git merge-base origin/master HEAD)
    switch "$type"
        case stacks
            _change_stacks $args[2..]
        case mappings
            _change_mappings $args[2..]
        case translations
            _change_translations $args[2..]
        case '*'
            _change_stacks $args | read -l -z -a -d \n changes && set -e changes[-1]
            if test -n "$changes"
                echo (magenta (reverse (dim '**')(bold 'Packages')(dim '**')))
                echo (magenta (dim '-'))
                echo
                string join \n -- $changes
                set -f changed
            end
            _change_mappings $args | read -l -z -a -d \n changes && set -e changes[-1]
            if test -n "$changes"
                set -q -f changed && echo
                echo (magenta (reverse (dim '**')(bold 'Mappings')(dim '**')))
                echo (magenta (dim '-'))
                echo
                echo (magenta (dim '```http'))
                string join \n -- $changes
                echo (magenta (dim '```'))
                set -f changed
            end
            _change_translations $args | read -l -z -a -d \n changes && set -e changes[-1]
            if test -n "$changes"
                set -q -f changed && echo
                echo (magenta (reverse (dim '**')(bold 'Translations')(dim '**')))
                echo (magenta (dim '-'))
                echo
                string join \n -- $changes
            end
    end
end

function _change_stacks -d "print list of changed services and modules"
    argparse -i f/from= t/to= merge-base= v/verbose x/exclude= -- $argv
    set -l from $_flag_from
    set -l to $_flag_to

    test -z "$from" && set from merge-base
    test "$from" = merge-base && set from $_flag_merge_base
    test -z "$to" && set to index
    if test "$to" = index
        set -f range $from
    else
        set -f range $from...$to
    end

    set -l root # root dir
    set -l files_at_to # list of files at `to' to validate manifest existence

    function file-exists -S -a file -d "check file existence at `to'"
        switch "$to"
            case index
                test -n "$root" || set root (git rev-parse --show-toplevel)
                test -f $root/$file
            case '*'
                test -n "$files_at_to" || git ls-tree -r --name-only $to | read -z -a -d \n files_at_to
                contains $file $files_at_to
        end
    end

    function parse-manifest -S -a file -d "parse manifest file at `to'"
        set -l patterns $argv[2..]
        switch "$to"
            case index
                for pattern in $patterns
                    string match -q -r $pattern <$root/$file
                end
            case '*'
                git show $to:$file | read -l -z file_content
                for pattern in $patterns
                    string match -q -r $pattern -- $file_content
                end
        end
    end

    set -l git_cmd "git diff --name-only --no-renames $range | grep -E '^(admin/)?(modules|services|web)/'"
    if test -n "$_flag_exclude"
        set git_cmd "$git_cmd | grep -v '\($_flag_exclude\)\$'"
    end

    if set -q _flag_verbose
        echo (yellow \$ $git_cmd)
        eval $git_cmd
        echo
    end

    # collect manifest files
    set -l package_dirs
    set -l visited_dirs
    eval $git_cmd | while read -l -L file
        set -l dir $file
        set -l found 0
        while test $found -eq 0 && set dir (string replace -r '/[^/]+$' '' $dir) && not contains $dir $visited_dirs && set -a visited_dirs $dir
            if file-exists $dir/serverless.yml
                set found 1
                if not contains $dir $package_dirs
                    set -a package_dirs $dir
                end
                break
            end
        end
    end

    # extract names and versions
    set -l stack_names
    set -l stack_versions
    for dir in $package_dirs
        set -l name
        set -l v
        if file-exists $dir/package.json
            parse-manifest $dir/package.json '"name": "(travelstop-)?(?<name>[^"]+)"' '"version": "(?<v>[^"]+)"'
        else if file-exists $dir/nodejs/package.json
            parse-manifest $dir/nodejs/package.json '"name": "(travelstop-)?(?<name>[^"]+)"' '"version": "(?<v>[^"]+)"'
        else
            parse-manifest $dir/serverless.yml '^service:\s*(?<name>module-\w+|\S+)\S*\s*$'
            if file-exists $dir/CHANGELOG.md
                parse-manifest $dir/CHANGELOG.md '# (?<v>\d+(\.\d+)+)'
            end
        end
        set -a stack_names $name
        set -a stack_versions "$v"
    end

    # sort
    for name in $stack_names
        set -l v $stack_versions[(contains -i -- $name $stack_names)]
        set -l group (string match -r '^\w+' $name | string replace -r 's$' '')
        set -l group_order 1
        set -l stack_order 1
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
    end | sort --key=2,2n --key=3,3 --key=4,4n | string replace -r '^([^\s]+).*' -- (magenta (dim '-'))' $1'
end

function _change_mappings -d "print elasticsearch index mapping changes"
    argparse -i f/from= t/to= merge-base= v/verbose -- $argv
    set -l from $_flag_from
    set -l to $_flag_to

    test -z "$from" && set from merge-base
    test "$from" = merge-base && set from $_flag_merge_base
    test -z "$to" && set to index
    if test "$to" = index
        set -f range $from
    else
        set -f range $from...$to
    end

    set -l manifests
    set -l root (git rev-parse --show-toplevel)
    set -l visited_dirs
    set -l printed 0

    set -l git_cmd "git diff --name-status --no-renames $range $root/schema | grep -F 'index-mappings.json'"

    if set -q _flag_verbose
        echo (yellow \$ $git_cmd)
        eval $git_cmd
        echo
    end

    eval $git_cmd | while read -l state file
        set -l -x ts_indent_size 2
        set -l -x ts_json_bracket_style
        set -l -x ts_json_colon_style
        set -l -x ts_json_quote_style fg=brightblue,dim
        set -l -x ts_json_string_style fg=brightblue,dim
        set -l -x ts_json_key_style fg=brightblue
        string match -q -r '(?<index>[^/]+)-index-mappings.json' -- $file
        switch $state
            case D
                test "$printed" -eq 1 && echo
                echo (red DELETE) (cyan /(bold $index))
                set printed 1
            case A
                test "$printed" -eq 1 && echo
                echo (red PUT) (cyan /(bold $index))
                cat $root/$file | awk -f ~/.config/fish/functions/logs.awk
                set printed 1
            case M
                set -l diff (node -e "
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
                if test "$diff" != undefined
                    test "$printed" -eq 1 && echo
                    echo (red PUT) (cyan /(bold $index))/_mapping
                    echo $diff | awk -f ~/.config/fish/functions/logs.awk
                    set printed 1
                end
        end
    end
end

function _change_translations -d "print list of new translation keys"
    argparse -i f/from= t/to= merge-base= v/verbose -- $argv
    set -l from $_flag_from
    set -l to $_flag_to

    test -z "$from" && set from origin/master
    test "$from" = merge-base && set from $_flag_merge_base
    test -z "$to" && set to index
    test "$to" = index && set to ''

    set -l jq_transform 'paths(scalars) as $path | ( $path | join(".") ) + " = " + getpath($path)'
    set -l placeholder (dim `)(yellow --bold --reverse '$1')(dim `)
    set -l pipe (dim '**\|**')
    set -l printed 0

    set -l json_names Services Web
    set -l jsons modules/templates/translations/en-GB.json web/locales/en-GB.json

    for i in (seq (count $jsons))
        set -l json_name $json_names[$i]
        set -l json $jsons[$i]
        comm -13 \
            (git show $from:$json | jq --raw-output "$jq_transform" | sort | psub) \
            (git show $to:$json | jq --raw-output "$jq_transform" | sort | psub) | read -l -z diff

        if set -q _flag_verbose
            echo (yellow \$ git show $from:$json)
            echo (yellow \$ git show $to:$json)
            echo
            echo $diff
        end

        if test -n "$diff"
            test "$printed" -eq 1 && echo
            echo (green (reverse (dim '**')(bold $json_name)(dim '**')))
            echo
            echo (yellow --bold Key) (dim \|) (yellow --bold en-GB)
            echo (dim ':--- | :---')
            echo -n $diff | while read -l -d ' = ' key value
                if test -n "$value"
                    echo (dim `)(green $key)(dim `) (dim \|) (string replace -a \| $pipe -- (string replace -ar '({\w+})' $placeholder -- $value))
                else
                    echo (dim `)(green $key)(dim `)
                end
            end
            set printed 1
        end
    end
end
