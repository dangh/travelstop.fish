# fishtape spec for prune_layer_versions (functions/prune_layer_versions.fish).
# Run: fish -c 'fishtape tests/prune_layer_versions.fish' < /dev/null
#
# Real code under test: the selection pipeline
#     aws list-layer-versions | jq | tail -n +(keep+1) | awk(reverse) | xargs ... _ts_delete_layer_version
# i.e. "keep the newest <keep> versions, delete all older ones".
#
# Nothing real is hit:
#   * A fake `aws` (tests/fixtures/prune_layer_versions/bin/aws) prints a canned
#     list-layer-versions JSON of 15 versions, newest first (15..1) like real AWS.
#   * The delete step runs `(which fish) -c _ts_delete_layer_version ...` in a NEW
#     fish subprocess. That subprocess does NOT inherit our parent function defs or
#     fish_function_path, but it DOES autoload from $XDG_CONFIG_HOME/fish/functions.
#     So we point XDG_CONFIG_HOME at the fixture cfg tree, whose
#     _ts_delete_layer_version.fish just appends the targeted version to a temp log.
#   * The fixture JSON/bin/cfg are read-only; only the per-run $TS_PRUNE_DEL_LOG is written.
#
# Expected deletion math (derived from the code, NOT guessed):
#   aws order (newest first): 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1
#   tail -n +(keep+1) drops the first <keep> (the newest <keep>); awk reverses the rest.
#   keep=3  -> preserve {13,14,15}, delete {1,2,...,12}
#   keep=10 -> preserve {6..15},   delete {1,2,3,4,5}   (default when keep omitted)

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -g FIX $here/fixtures/prune_layer_versions

source $repo/functions/prune_layer_versions.fish

# fake aws on PATH (in front), and route the delete subprocess to our fake function.
set -gx PATH $FIX/bin $PATH
set -gx XDG_CONFIG_HOME $FIX/cfg

# helper: run prune with the given args, capture sorted (ascending, numeric) deletions.
function _run_prune
    set -gx TS_PRUNE_DEL_LOG (mktemp)
    prune_layer_versions $argv >/dev/null 2>&1
    set -l code $status
    # parallel xargs writes in arbitrary order -> sort numerically for stable asserts.
    set -g LAST_DEL (sort -n $TS_PRUNE_DEL_LOG)
    rm -f $TS_PRUNE_DEL_LOG
    return $code
end

# sanity: the fake aws + jq pipeline yields the 15-version list newest-first.
@test "fake aws list yields 15 versions newest-first" (aws lambda list-layer-versions --layer-name x | jq -r '.LayerVersions.[].Version' | string join ' ') = "15 14 13 12 11 10 9 8 7 6 5 4 3 2 1"

# ===== keep=3 : delete the 12 oldest, preserve the newest 3 =====
_run_prune mylayer 3
set -l del3 $LAST_DEL
@test "keep=3 deletes exactly 12 versions" (count $del3) -eq 12
@test "keep=3 deletes versions 1..12 (oldest)" (string join ' ' $del3) = "1 2 3 4 5 6 7 8 9 10 11 12"
@test "keep=3 preserves newest 13" (contains 13 $del3; echo $status) -eq 1
@test "keep=3 preserves newest 14" (contains 14 $del3; echo $status) -eq 1
@test "keep=3 preserves newest 15" (contains 15 $del3; echo $status) -eq 1

# ===== default keep (omitted) == 10 : delete the 5 oldest, preserve newest 10 =====
_run_prune mylayer
set -l deld $LAST_DEL
@test "default keep deletes exactly 5 versions" (count $deld) -eq 5
@test "default keep deletes versions 1..5 (oldest)" (string join ' ' $deld) = "1 2 3 4 5"
@test "default keep preserves version 6 (10th newest)" (contains 6 $deld; echo $status) -eq 1
@test "default keep preserves version 15 (newest)" (contains 15 $deld; echo $status) -eq 1

# ===== explicit keep=10 matches the default =====
_run_prune mylayer 10
@test "explicit keep=10 == default keep" (string join ' ' $LAST_DEL) = "1 2 3 4 5"

# ===== missing layer name: non-zero, no deletions, no aws call =====
set -gx TS_PRUNE_DEL_LOG (mktemp)
prune_layer_versions >/dev/null 2>&1
set -l nocode $status
set -l nodel (cat $TS_PRUNE_DEL_LOG)
rm -f $TS_PRUNE_DEL_LOG
@test "missing layer name returns non-zero" $nocode -ne 0
@test "missing layer name deletes nothing" (count $nodel) -eq 0
