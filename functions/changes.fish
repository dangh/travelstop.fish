function changes --argument-names from --description "print list of changed services and modules"
  test -n "$from" || set --local from HEAD~1
  set --local jsons (git diff --name-only --line-prefix=(git rev-parse --show-toplevel)/ $from | sed -E 's/[^/]+$/package.json/' | sort | uniq | grep -v /lib/ | grep -v /schema/)
  for json in $jsons
    test -f $json || continue
    set --local name (echo (string match --regex '"name": "([^"]+)"' < $json)[2] | sed 's/travelstop-//')
    set --local v (string match --regex '"version": "([^"]+)"' < $json)[2]
    echo $name-$v
  end
end
