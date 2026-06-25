# function as the first positional argument
complete -c invoke -n "not __fish_seen_subcommand_from (_ts_functions)" -a "(_ts_uniq_completions (_ts_functions))" -d function

# boolean flags
complete -c invoke -s l -l log -d 'show invocation logs'
complete -c invoke -l raw -d 'raw input'
complete -c invoke -l tail -d 'tail logs after invoke'

# value flags
complete -c invoke -x -s f -l function -a "(_ts_functions)" -d 'function to invoke'
complete -c invoke -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c invoke -x -s r -l region -d 'aws region'
complete -c invoke -x -s q -l qualifier -d 'version/alias qualifier'
complete -c invoke -x -s t -l type -d 'invocation type'
complete -c invoke -x -s d -l data -d 'inline input data'
complete -c invoke -x -s i -l interval -d 'log poll interval'
complete -c invoke -x -l aws-profile -d 'aws profile'
complete -c invoke -x -l context -d 'inline context'
complete -c invoke -x -l app -d 'serverless app'
complete -c invoke -x -l org -d 'serverless org'
complete -c invoke -x -l startTime -d 'logs start time'
complete -c invoke -x -l filter -d 'logs filter pattern'
complete -c invoke -r -s p -l path -d 'input data file'
complete -c invoke -r -l contextPath -d 'context file'
complete -c invoke -r -s c -l config -d 'serverless config file'

complete -f -c invoke
