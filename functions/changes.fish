function changes --argument-names from --description "print list of changed services and modules"
  argparse --ignore-unknown 'i/index' -- $argv
  if set --query _flag_index
    set --function range (git merge-base origin/master HEAD)
  else if test -z "$from"
    set --function range origin/master...
  else
    set --function range $from...
  end
  set --local manifests
  set --local root (git rev-parse --show-toplevel)
  set --local visited_dirs
  for file in (git diff --name-only $range | grep -E '^(admin/)?(modules|services|web)/')
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
    switch $manifest
    case '*/package.json'
      string match --quiet --regex '"name": "(travelstop-)?(?<name>[^"]+)"' < $manifest
      string match --quiet --regex '"version": "(?<v>[^"]+)"' < $manifest
    case '*/serverless.yml'
      string match --quiet --regex '^service:\s*(?<name>module-\w+|\S+)\S*\s*$' < $manifest
    end
    set --append stack_names $name
    set --append stack_versions $v
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
  end | sort --key=2,2n --key=3,3 --key=4,4n | sed -E 's/ .+//'
end
