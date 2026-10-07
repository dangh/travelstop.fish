# function as the first positional argument
complete -c logs_sls -n "not __fish_seen_subcommand_from (_ts_functions)" -a "(_ts_uniq_completions (_ts_functions))" -d function

complete -c logs_sls -s t -l tail -d 'tail logs'

complete -c logs_sls -x -s f -l function -a "(_ts_functions)" -d 'function to watch'
complete -c logs_sls -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c logs_sls -x -s r -l region -d 'aws region'
complete -c logs_sls -x -s i -l interval -d 'poll interval'
complete -c logs_sls -x -l aws-profile -d 'aws profile'
complete -c logs_sls -x -l startTime -d 'start time'
complete -c logs_sls -x -l filter -d 'filter pattern'
complete -c logs_sls -x -l app -d 'serverless app'
complete -c logs_sls -x -l org -d 'serverless org'
complete -c logs_sls -r -s c -l config -d 'serverless config file'

complete -f -c logs_sls
