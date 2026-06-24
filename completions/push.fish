complete -c push -a all -d 'current service + subservices'
complete -c push -a "(_ts_uniq_completions (_ts_modules))" -d module
complete -c push -a "(_ts_uniq_completions (_ts_functions))" -d function
complete -c push -a "(_ts_uniq_completions (_ts_substacks))" -d service

# enforce no-files when all completions are selected
complete -f -c push
