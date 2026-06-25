set -l types all stacks mappings translations

complete -c changes -n "not __fish_seen_subcommand_from $types" -a all -d "Print all changes"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a stacks -d "Print changed stacks"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a mappings -d "Print changed index mappings"
complete -c changes -n "not __fish_seen_subcommand_from $types" -a translations -d "Print changed translation keys"
complete -c changes -r -f -l from -s f -d "Change from ref"
complete -c changes -r -f -l from -s f -a merge-base -d "Change from merge base"
complete -c changes -r -f -l from -s f -a "(_ts_git_refs)"
complete -c changes -r -f -l to -s t -d "Change to ref"
complete -c changes -r -f -l to -s t -a index -d "Change compare to index"
complete -c changes -r -f -l to -s t -a "(_ts_git_refs)"
complete -f -c changes -s o -l output -x -a 'path markdown' -d "Output format (default: markdown)"
complete -f -c changes -s x -l exclude -x -d "Exclude paths matching pattern"
complete -f -c changes -s v -l verbose -d "Print the underlying git command"
complete -f -c changes
