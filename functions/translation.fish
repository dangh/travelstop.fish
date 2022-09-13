function translation --description "print list of new translation keys"
  comm -13 \
    (git show master:web/locales/en-GB.json | jq --raw-output 'paths(scalars) as $path | ( $path | join(".") )' | sort | psub) \
    (git show :web/locales/en-GB.json | jq --raw-output 'paths(scalars) as $path | ( $path | join(".") )' | sort | psub)
end
