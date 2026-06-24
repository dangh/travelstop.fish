complete -c push_changes -r -f -l from -s f -d "Change from ref"
complete -c push_changes -r -f -l from -s f -a merge-base -d "Change from merge base"
complete -c push_changes -r -f -l from -s f -a "(_git_refs)"
