for name in (__sls_complete_modules)
  complete --keep-order --no-files --command push --condition "not __fish_seen_subcommand_from $name" --arguments $name --description "module"
end

for name in (__sls_complete_functions)
  complete --keep-order --no-files --command push --condition "not __fish_seen_subcommand_from $name" --arguments $name --description "function"
end

for name in (__sls_complete_substacks)
  complete --keep-order --no-files --command push --condition "not __fish_seen_subcommand_from $name" --arguments $name --description "sub-stack"
end

# enforce no-files when all completions are selected
complete --no-files --command push
