function changes --argument-names from --description "print list of changed services and modules"
  argparse --ignore-unknown 'i/index' -- $argv
  if set --query _flag_index
    set --function range (git merge-base origin/master HEAD)
  else if test -z "$from"
    set --function range origin/master...
  else
    set --function range $from...
  end
  set --local package_jsons
  set --local serverless_ymls
  set --local stack_names
  set --local stack_versions
  set --local root (git rev-parse --show-toplevel)
  for path in (git diff --name-only $range | grep -E '^(modules|services|web)/')
    while set path (string replace --regex '/[^/]+$' '' $path)
      contains $root/$path/package.json $package_jsons || set --append package_jsons $root/$path/package.json
      contains $root/$path/serverless.yml $serverless_ymls || set --append serverless_ymls $root/$path/serverless.yml
    end
  end
  for json in $package_jsons
    test -f $json || continue
    string match --quiet --regex '"name": "(travelstop-)?(?<name>[^"]+)"' < $json
    string match --quiet --regex '"version": "(?<v>[^"]+)"' < $json
    if set --local index (contains --index -- $name $stack_names)
      set stack_versions[$index] -$v
    else
      set --append stack_names $name
      set --append stack_versions -$v
    end
  end
  for yml in $serverless_ymls
    test -f $yml || continue
    string match --quiet --regex '^service:\s*(?<name>module-\w+|\S+)\S*\s*$' < $yml
    if not contains -- $name $stack_names
      set --append stack_names $name
      set --append stack_versions ''
    end
  end
  for name in $stack_names
    set --local v $stack_versions[(contains --index -- $name $stack_names)]
    echo $name$v
  end | sort
end
