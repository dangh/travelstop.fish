function push_changes -d 'deploy all changed stacks/modules in current branch'
    argparse -i f/from= i/interactive -- $argv
    or return
    set -l from_arg
    set -q _flag_from && set from_arg --from=$_flag_from
    set -l paths (changes stacks --output=path $from_arg)
    if test -z "$paths"
        _ts_log no changed stacks to push
        return 0
    end
    # -i/--interactive: hand the changed stacks to push, which opens them in
    # $EDITOR so they can be reordered/removed before deploy.
    if set -q _flag_interactive
        push -i $paths $argv
        return
    end
    _ts_log pushing (yellow (count $paths)) changed stacks:
    for p in $paths
        echo (magenta (dim '-')) $p
    end
    push $paths $argv
end
