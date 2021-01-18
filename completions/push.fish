complete --keep-order --no-files --command push --arguments "(_sls_uniq_completions (_sls_modules))" --description "module"
complete --keep-order --no-files --command push --arguments "(_sls_uniq_completions (_sls_functions))" --description "function"
complete --keep-order --no-files --command push --arguments "(_sls_uniq_completions (_sls_substacks))" --description "sub-stack"

# enforce no-files when all completions are selected
complete --no-files --command push
