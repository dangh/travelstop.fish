complete --keep-order --no-files --command push --arguments "(__sls_complete_uniq (__sls_complete_modules))" --description "module"
complete --keep-order --no-files --command push --arguments "(__sls_complete_uniq (__sls_complete_functions))" --description "function"
complete --keep-order --no-files --command push --arguments "(__sls_complete_uniq (__sls_complete_substacks))" --description "sub-stack"

# enforce no-files when all completions are selected
complete --no-files --command push
