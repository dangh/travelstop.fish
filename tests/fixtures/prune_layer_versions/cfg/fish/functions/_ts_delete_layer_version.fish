# Fake _ts_delete_layer_version, autoloaded by the `fish -c ...` subprocess that
# prune_layer_versions spawns. The function points XDG_CONFIG_HOME at this fixture
# tree so the subprocess autoloads THIS file instead of the real conf.d one.
# It records the version it was asked to delete (one per line) into $TS_PRUNE_DEL_LOG
# so the spec can assert the exact deletion set. No AWS call is ever made.
function _ts_delete_layer_version
    set -e argv
    # argv: <layer_name> <version>
    echo $argv[2] >>$TS_PRUNE_DEL_LOG
end
