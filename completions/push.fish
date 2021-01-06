complete --keep-order --no-files --command push --arguments "(__sls_uniq_completions (__sls_modules))" --description "module"
complete --keep-order --no-files --command push --arguments "(__sls_uniq_completions (__sls_functions))" --description "function"
complete --keep-order --no-files --command push --arguments "(__sls_uniq_completions (__sls_substacks))" --description "sub-stack"

# enforce no-files when all completions are selected
complete --no-files --command push
