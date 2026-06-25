# sls wraps serverless, injecting stage/profile/region; complete common subcommands + shared flags
set -l sls_cmds deploy invoke logs package remove info print rollback metrics create

complete -c sls -n "not __fish_seen_subcommand_from $sls_cmds" -a "$sls_cmds"
complete -c sls -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c sls -x -s r -l region -d 'aws region'
complete -c sls -x -s d -l data -d 'inline input data'
complete -c sls -r -s c -l config -d 'serverless config file'
complete -c sls -x -l aws-profile -d 'aws profile'
complete -c sls -s h -l help -d 'show help'
complete -c sls -s v -l version -d 'show version'
