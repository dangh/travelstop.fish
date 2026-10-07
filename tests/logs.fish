# Dispatcher tests: backends are stubbed, no AWS or Serverless calls.
set -l repo (path dirname (path dirname (status filename)))
source $repo/functions/logs.fish
set -l original_pwd $PWD
set -l tmp (mktemp -d)
cd $tmp
function logs_sls
    printf '%s\n' sls $argv
    return 17
end
function logs_awscli
    printf '%s\n' awscli $argv
    return 23
end

set -l out (logs create -s prod --filter 'ERROR warning')
set -l code $status
@test "without serverless.yml selects AWS CLI" "$out[1]" = awscli
@test "AWS arguments retain boundaries" "$out[2..-1]" = 'create -s prod --filter ERROR warning'
@test "filter is a single argument" (count $out) -eq 6
@test "AWS exit status propagates" $code -eq 23

touch serverless.yml
set -l out (logs create -s dev)
set -l code $status
@test "with serverless.yml selects Serverless" "$out[1]" = sls
@test "Serverless arguments are forwarded" "$out[2..-1]" = 'create -s dev'
@test "Serverless exit status propagates" $code -eq 17

mkdir child
cd child
set -l out (logs create)
@test "only checks the current directory" "$out[1]" = awscli
cd $original_pwd
rm -rf $tmp
