# function as the first positional argument
complete -c logs -n "not __fish_seen_subcommand_from (_ts_functions)" -a "(_ts_uniq_completions (_ts_functions))" -d function

complete -c logs -s t -l tail -d 'tail logs'

complete -c logs -x -s f -l function -a "(_ts_functions)" -d 'function to watch'
complete -c logs -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c logs -x -s r -l region -d 'aws region'
complete -c logs -x -s i -l interval -d 'poll interval'
complete -c logs -x -l aws-profile -d 'aws profile'
complete -c logs -x -l startTime -d 'start time'
complete -c logs -x -l filter -d 'filter pattern'
complete -c logs -x -l app -d 'serverless app'
complete -c logs -x -l org -d 'serverless org'
complete -c logs -r -s c -l config -d 'serverless config file'

complete -f -c logs
