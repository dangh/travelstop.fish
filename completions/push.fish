complete --keep-order --no-files --command push --arguments "(_ts_uniq_completions (_ts_modules))" --description "module"
complete --keep-order --no-files --command push --arguments "(_ts_uniq_completions (_ts_functions))" --description "function"
complete --keep-order --no-files --command push --arguments "(_ts_uniq_completions (_ts_substacks))" --description "sub-stack"

# enforce no-files when all completions are selected
complete --no-files --command push
