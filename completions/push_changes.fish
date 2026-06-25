# push_changes resolves changed stacks, then forwards remaining args to push
complete -c push_changes -r -f -l from -s f -d "Change from ref"
complete -c push_changes -r -f -l from -s f -a merge-base -d "Change from merge base"
complete -c push_changes -r -f -l from -s f -a "(_ts_git_refs)"

# common push pass-through flags
complete -c push_changes -x -s s -l stage -a 'dev dev-in test stage prod' -d stage
complete -c push_changes -x -s r -l region -d 'aws region'
complete -c push_changes -s v -l verbose -d 'verbose output'
complete -c push_changes -l force -d 'force deploy'

complete -f -c push_changes
