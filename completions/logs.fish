complete -c logs -s t -l tail -d 'tail logs'

complete -c logs -x -s f -l function -d 'function to watch'
complete -c logs -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c logs -x -s r -l region -d 'aws region'
complete -c logs -n 'not test -f serverless.yml' -x -l log-group -d 'explicit CloudWatch log group'
complete -c logs -x -l aws-profile -d 'aws profile'
complete -c logs -x -l startTime -d 'start time'
complete -c logs -x -l filter -d 'filter pattern'

complete -f -c logs

# Serverless-only suggestions are available only when the dispatcher uses it.
complete -c logs -n 'test -f serverless.yml' -a '(_ts_functions)' -d function
complete -c logs -n 'test -f serverless.yml' -x -s i -l interval -d 'poll interval'
complete -c logs -n 'test -f serverless.yml' -x -l app -d 'serverless app'
complete -c logs -n 'test -f serverless.yml' -x -l org -d 'serverless org'
complete -c logs -n 'test -f serverless.yml' -r -s c -l config -d 'serverless config file'
