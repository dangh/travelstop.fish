set --local types all stacks mappings translations

function _git_refs
  git for-each-ref --format='%(refname:strip=2)' refs 2>/dev/null
end

complete --command changes --condition "not __fish_seen_subcommand_from $types" --arguments all --description "Print all changes"
complete --command changes --condition "not __fish_seen_subcommand_from $types" --arguments stacks --description "Print changed stacks"
complete --command changes --condition "not __fish_seen_subcommand_from $types" --arguments mappings --description "Print changed index mappings"
complete --command changes --condition "not __fish_seen_subcommand_from $types" --arguments translations --description "Print changed translation keys"
complete --command changes --require-parameter --no-files --long from --short f --description "Change from ref"
complete --command changes --require-parameter --no-files --long from --short f --arguments merge-base --description "Change from merge base"
complete --command changes --require-parameter --no-files --long from --short f --arguments "(_git_refs)"
complete --command changes --require-parameter --no-files --long to --short t --description "Change to ref"
complete --command changes --require-parameter --no-files --long to --short t --arguments "index" --description "Change compare to index"
complete --command changes --require-parameter --no-files --long to --short t --arguments "(_git_refs)"
complete --no-files --command changes
