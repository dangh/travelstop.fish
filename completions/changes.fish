set -l types all stacks mappings translations

function _git_refs
  git for-each-ref --format='%(refname:strip=2)' refs 2>/dev/null
end

complete -c changes -n "not __fish_seen_subcommand_from $types" -a all -d "Print all changes"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a stacks -d "Print changed stacks"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a mappings -d "Print changed index mappings"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a translations -d "Print changed translation keys"
complete -c changes -r -f -l from -s f -d "Change from ref"
complete -c changes -r -f -l from -s f -a merge-base -d "Change from merge base"
complete -c changes -r -f -l from -s f -a "(_git_refs)"
complete -c changes -r -f -l to -s t -d "Change to ref"
complete -c changes -r -f -l to -s t -a "index" -d "Change compare to index"
complete -c changes -r -f -l to -s t -a "(_git_refs)"
complete -f -c changes
