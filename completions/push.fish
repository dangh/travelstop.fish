# positional targets: modules, functions, services (and substacks)
complete -c push -a "(_ts_uniq_completions (_ts_modules))" -d module
complete -c push -a "(_ts_uniq_completions (_ts_functions))" -d function
complete -c push -a "(_ts_uniq_completions (_ts_substacks))" -d service

# boolean flags
complete -c push -s a -l all -d 'current service + subservices (or given targets + children)'
complete -c push -s i -l interactive -d 'edit resolved targets in $EDITOR before deploy'
complete -c push -s C -l continue -d 'resume an interrupted/failed run'
complete -c push -s R -l regex -d 'treat targets as regex patterns'
complete -c push -s v -l verbose -d 'verbose output'
complete -c push -s u -l update-config -d 'update function configuration'
complete -c push -l force -d 'force deploy'
complete -c push -l conceal -d 'conceal secrets in output'
complete -c push -l aws-s3-accelerate -d 'use S3 transfer acceleration'

# value flags
complete -c push -x -s f -l function -a "(_ts_functions)" -d 'function to deploy'
complete -c push -x -s e -l exclude -d 'exclude targets matching pattern'
complete -c push -x -s s -l stage -a 'dev dev-in test stage prod' -d 'deploy stage'
complete -c push -x -s r -l region -d 'aws region'
complete -c push -x -l aws-profile -d 'aws profile'
complete -c push -x -l app -d 'serverless app'
complete -c push -x -l org -d 'serverless org'
complete -c push -r -s c -l config -d 'serverless config file'
complete -c push -r -s p -l package -d 'pre-packaged artifact dir'

# enforce no-files when all completions are selected
complete -f -c push
