function changes --argument-names from --description "print list of changed services and modules"
  test -n "$from" || set --local from (git merge-base master HEAD)
  set --local changes (git diff --name-only --line-prefix=(git rev-parse --show-toplevel)/ $from | string split0)
  set --local jsons (echo $changes | sed -E 's/[^/]+$/package.json/' | grep -v '/lib/' | grep -v '/schema/' | sort | uniq)
  set --local ymls (echo $changes | grep '.yml' | grep -v 'modules/' | grep -v 'serverless-layers' | sed -E 's/[^/]+$/serverless.yml/' | sort | uniq)
  set --local stack_names
  set --local stack_versions
  for yml in $ymls
    test -f $yml || continue
    string match --quiet --regex '^service:\s*(?<name>\S+)\s*$' < $yml
    if not contains -- $name $stack_names
      set --append stack_names $name
      set --append stack_versions ''
    end
  end
  for json in $jsons
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
  for index in (seq (count $stack_names))
    echo $stack_names[$index]$stack_versions[$index]
  end | sort
end
