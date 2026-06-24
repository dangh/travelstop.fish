# fishtape spec for functions/prune_functions_versions.fish
# Run: fishtape tests/prune_functions_versions.fish < /dev/null
#
# Real code under test:
#   _delete_function_versions <fn> <keep>  -- the jq/tail/awk version-selection
#                                              logic and the xargs delete fan-out
#   prune_functions_versions <keep>        -- iteration over _ts_substacks|_ts_functions
#
# No real AWS, no network. Only side-effects are faked, all under
# tests/fixtures/prune_functions_versions/ (namespaced, never mutated):
#   bin/aws  -- prints canned `list-versions-by-function` JSON per --function-name
#   bin/fish -- intercepts `(which fish) -c _ts_delete_function_version <fn> <ver>`
#               (fixture bin is first on PATH so `which fish` resolves here) and
#               records "<fn> <ver>" to $DEL_LOG instead of spawning a real fish.
#
# Expected deletion sets were COMPUTED from the real pipeline, not guessed:
#   aws output order is "$LATEST" then versions ascending (1..N).
#     tail -n +2        drops $LATEST            -> 1..N
#     awk reverse       newest first            -> N..1
#     tail -n +$keep    drops first (keep-1)     -> keeps newest (keep-1), rest deleted
#     awk reverse       restore ascending
#   So with N numeric versions, it deletes the oldest N-(keep-1), i.e. preserves
#   the newest (keep-1). (Note the off-by-one: keep=K preserves K-1 newest.)
#   Fixtures:
#     fn15: 1..15, keep=3  -> delete 1..13   (preserve 14,15)
#     fn12: 1..12, default -> keep=10 deletes 1..3 (preserve 4..12)
#     fn5:  1..5,  keep=1  -> delete 1..5    (preserve none; tail -n +1 keeps all to delete)

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -l fix $here/fixtures/prune_functions_versions

source $repo/functions/prune_functions_versions.fish

# fixture bin first on PATH: shadows `aws` and the `fish` that the delete
# fan-out shells out to via `(which fish) -c ...`.
set -gx PATH $fix/bin $PATH
set -gx DEL_LOG (mktemp)

# --- _delete_function_versions: explicit keep, partial deletion --------------
echo -n >$DEL_LOG
_delete_function_versions fn15 3
set -l got (cat $DEL_LOG | sort -n)
@test "fn15 keep=3 deletes 13 versions" (count $got) -eq 13
@test "fn15 keep=3 deletes the oldest (1)" (contains 'fn15 1' $got; echo $status) -eq 0
@test "fn15 keep=3 deletes version 13" (contains 'fn15 13' $got; echo $status) -eq 0
@test "fn15 keep=3 preserves newest (14)" (contains 'fn15 14' $got; echo $status) -eq 1
@test "fn15 keep=3 preserves newest (15)" (contains 'fn15 15' $got; echo $status) -eq 1

# --- _delete_function_versions: default keep (10) ----------------------------
echo -n >$DEL_LOG
_delete_function_versions fn12
set -l got (cat $DEL_LOG | sort -n)
@test "fn12 default keep deletes 3 versions" (count $got) -eq 3
@test "fn12 default keep deletes 1" (contains 'fn12 1' $got; echo $status) -eq 0
@test "fn12 default keep deletes 3" (contains 'fn12 3' $got; echo $status) -eq 0
@test "fn12 default keep preserves 4" (contains 'fn12 4' $got; echo $status) -eq 1
@test "fn12 default keep preserves 12" (contains 'fn12 12' $got; echo $status) -eq 1

# --- _delete_function_versions: keep=1 deletes everything --------------------
echo -n >$DEL_LOG
_delete_function_versions fn5 1
set -l got (cat $DEL_LOG | sort -n)
@test "fn5 keep=1 deletes all 5 versions" (count $got) -eq 5
@test "fn5 keep=1 deletes 1" (contains 'fn5 1' $got; echo $status) -eq 0
@test "fn5 keep=1 deletes 5" (contains 'fn5 5' $got; echo $status) -eq 0

# --- _delete_function_versions: missing function name is a no-op, non-zero ---
echo -n >$DEL_LOG
_delete_function_versions
set -l code $status
@test "missing function name returns non-zero" $code -eq 1
@test "missing function name deletes nothing" (count (cat $DEL_LOG)) -eq 0

# --- prune_functions_versions: iterates the function list --------------------
# Shadow the listing helpers to yield a known set without touching real conf.d.
function _ts_substacks; echo stack; end
function _ts_functions; printf '%s\n' fn5 fn12; end

echo -n >$DEL_LOG
set -l out (prune_functions_versions 1 2>/dev/null)
@test "prune prints a Pruning line per function" (count (string match -r 'Pruning all versions' $out)) -eq 2
@test "prune mentions fn5" (string match -q '*fn5*' -- $out; echo $status) -eq 0
@test "prune mentions fn12" (string match -q '*fn12*' -- $out; echo $status) -eq 0
# keep=1 -> deletes all of fn5 (1..5) and all of fn12 (1..12) = 17 deletions.
@test "prune keep=1 deletes all versions of both functions" (count (cat $DEL_LOG)) -eq 17

# --- teardown ----------------------------------------------------------------
rm -f $DEL_LOG
