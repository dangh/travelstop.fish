complete -c logs_awscli -s t -l tail -d 'tail logs'

complete -c logs_awscli -x -s f -l function -d 'function to watch'
complete -c logs_awscli -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c logs_awscli -x -s r -l region -d 'aws region'
complete -c logs_awscli -x -l log-group -d 'explicit CloudWatch log group'
complete -c logs_awscli -x -l aws-profile -d 'aws profile'
complete -c logs_awscli -x -l startTime -d 'start time'
complete -c logs_awscli -x -l filter -d 'filter pattern'

complete -f -c logs_awscli
