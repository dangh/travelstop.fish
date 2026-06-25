# config/dir as the first positional argument
complete -c pack -a "(_ts_uniq_completions (_ts_substacks))" -d service

complete -c pack -s v -l verbose -d 'verbose output'

complete -c pack -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c pack -x -s r -l region -d 'aws region'
complete -c pack -x -l aws-profile -d 'aws profile'
complete -c pack -x -l app -d 'serverless app'
complete -c pack -x -l org -d 'serverless org'
complete -c pack -r -s p -l package -d 'output package dir'
complete -c pack -r -s c -l config -d 'serverless config file'

complete -f -c pack
