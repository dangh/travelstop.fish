function push_all -d 'deploy all changed stacks/modules in current branch'
    set -l paths (changes stacks --output=path)
    if test -z "$paths"
        _ts_log no changed stacks to push
        return 0
    end
    _ts_log pushing (yellow (count $paths)) changed stacks:
    for p in $paths
        echo (magenta (dim '-')) $p
    end
    push $paths $argv
end
