function pack --description "package a serverless service"
  set --local profile $AWS_PROFILE
  set --local stage (string lower -- (string replace --regex '.*@' '' -- $AWS_PROFILE))
  set --local region $AWS_DEFAULT_REGION
  set --local yml ./serverless.yml
  set --local args
  getopts $argv | while read --local key value
    switch $key
    case profile
      set profile $value
    case s stage
      set stage $value
    case r region
      set region $value
    case _ c config
      set yml $value
    case \*
      test (string length $key) -eq 1 \
        && set key "-$key" \
        || set key "--$key"
      test "$value" = true \
        && set value
      set --append $key $value
    end
  end
  string match --quiet --regex '\.yml$' "$yml" || set yml $yml/serverless.yml
  if ! test -f "$yml"
    __sls_log invalid serverless config: (__sls_validate_path $yml)
    return 1
  end
  set yml (realpath $yml 2>/dev/null)
  set --local working_dir (dirname $yml)
  set --local name_ver (string match --regex '^service:\s*([^\s]*)' < $yml)[2]
  set --local json (realpath $working_dir/package.json 2>/dev/null)
  test -f "$json" || set --local json (realpath $working_dir/nodejs/package.json 2>/dev/null)
  test -f "$json" && set name_ver $name_ver-(string match --regex '^\s*"version":\s*"([^"]*)"' < $json)[2]
  set --local command "sls package --profile $profile -s $stage -r $region"
  test (basename $yml) != serverless.yml \
    && set --append command "-c" (basename $yml)
  set --append command $args
  __sls_log packaging stack: (set_color magenta)$name_ver(set_color normal)
  __sls_log config: (set_color blue)$yml(set_color normal)
  __sls_log execute command: (set_color green)$command(set_color normal)
  withd "$working_dir" "$command"
end
