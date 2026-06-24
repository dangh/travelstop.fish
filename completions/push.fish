complete -c push -s a -l all -d 'current service + subservices (or given targets + children)'
complete -c push -a "(_ts_uniq_completions (_ts_modules))" -d module
complete -c push -a "(_ts_uniq_completions (_ts_functions))" -d function
complete -c push -a "(_ts_uniq_completions (_ts_substacks))" -d service

# enforce no-files when all completions are selected
complete -f -c push
