# action: on/off/toggle (or a branch/suffix name)
complete -c rename_modules -n "not __fish_seen_subcommand_from on off toggle" -a 'on off toggle' -d 'rename action'

complete -c rename_modules -s f -l force -d 'rename all modules (not just changed)'
complete -c rename_modules -x -s s -l service -d 'limit to changed files under this service'

complete -f -c rename_modules
