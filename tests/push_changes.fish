# fishtape spec for push_changes (functions/push_changes.fish).
# push_changes is a thin wrapper: it runs `changes stacks --output=path [--from=<ref>]`,
# logs the changed stacks, then calls `push <paths> <remaining argv>`.
# Run: fishtape tests/push_changes.fish < /dev/null
#
# We source the real function and stub its two collaborators (`changes`, `push`)
# plus the logging/color helpers (echo passthrough), mirroring tests/push.fish.
# No fixtures, no network, no git: the stubs are fully self-contained.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/push_changes.fish

# --- stub logging + colors (echo passthrough) ----------------------------
function _ts_log; echo $argv; end
for c in magenta yellow blue green red dim ansi-escape
    function $c; echo $argv; end
end

# --- stub collaborators --------------------------------------------------
# `changes`: records its argv (so we can assert --from forwarding) and echoes
# back whatever paths the current test wants via $CHANGES_OUT.
set -g CHANGES_ARGV_LOG (mktemp)
set -g CHANGES_OUT ''
function changes
    echo "$argv" >>$CHANGES_ARGV_LOG
    for p in $CHANGES_OUT
        echo $p
    end
end

# `push`: capture its full argv to a temp file, one arg per line, so we can
# assert the exact paths + extra argv passed through.
set -g PUSH_ARGV_LOG (mktemp)
function push
    printf '%s\n' $argv >>$PUSH_ARGV_LOG
end

# ===== (1) no changes: logs message, returns 0, never calls push =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT ''
set -l out (push_changes)
set -l code $status
@test "no changes returns 0" $code -eq 0
@test "no changes logs 'no changed stacks'" (string match -q '*no changed stacks to push*' -- "$out"; echo $status) -eq 0
@test "no changes does not call push" (count (string split -n \n -- (cat $PUSH_ARGV_LOG))) -eq 0

# ===== (2) with changes: push gets exactly those paths =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT a/one b/two
push_changes >/dev/null 2>&1
@test "push receives both changed paths" (count (cat $PUSH_ARGV_LOG)) -eq 2
@test "push receives path a/one" (string match -q 'a/one' -- (cat $PUSH_ARGV_LOG)[1]; echo $status) -eq 0
@test "push receives path b/two" (string match -q 'b/two' -- (cat $PUSH_ARGV_LOG)[2]; echo $status) -eq 0

# ===== (3a) -f <ref> forwards --from=<ref> to changes =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT a/one
push_changes -f main >/dev/null 2>&1
@test "-f main forwards --from=main to changes" (string match -q '*--from=main*' -- (cat $CHANGES_ARGV_LOG); echo $status) -eq 0

# ===== (3b) --from=<ref> forwards --from=<ref> to changes =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT a/one
push_changes --from=develop >/dev/null 2>&1
@test "--from=develop forwards --from=develop to changes" (string match -q '*--from=develop*' -- (cat $CHANGES_ARGV_LOG); echo $status) -eq 0

# ===== (3c) without --from, changes gets no --from flag =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT a/one
push_changes >/dev/null 2>&1
@test "no -f means no --from passed to changes" (string match -q '*--from*' -- (cat $CHANGES_ARGV_LOG); echo $status) -eq 1

# ===== (4) extra args after flags are forwarded to push =====
echo -n >$CHANGES_ARGV_LOG
echo -n >$PUSH_ARGV_LOG
set -g CHANGES_OUT a/one b/two
push_changes -f main --dry extra >/dev/null 2>&1
@test "push gets paths plus extra argv" (count (cat $PUSH_ARGV_LOG)) -eq 4
@test "push forwards --dry passthrough arg" (contains -- --dry (cat $PUSH_ARGV_LOG); echo $status) -eq 0
@test "push forwards extra passthrough arg" (contains -- extra (cat $PUSH_ARGV_LOG); echo $status) -eq 0

# --- teardown ------------------------------------------------------------
rm -f $CHANGES_ARGV_LOG $PUSH_ARGV_LOG
