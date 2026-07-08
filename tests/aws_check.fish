# fishtape spec for the AWS session pre-flight (functions/aws_check.fish +
# the _ts_ensure_session helper in conf.d/travelstop.fish).
# Run: fishtape tests/aws_check.fish < /dev/null
#
# Real code under test: _ts_ensure_session (session gate + inline re-auth retry
# loop) and aws_check (its public wrapper). The conf.d file has a top-level
# `exit`, so we can't source it whole — extract just the helper's function block
# by name. Its inner `end`s are indented, so `^end$` matches only the closer.
#
# Only external side-effect stubbed: the `aws` CLI (a fish function so
# `type -q aws` is true and we can control exit code + capture args). _ts_log and
# the color helpers are passthrough shims that append to a log for assertions.
# The retry prompt reads one char from stdin; tests pipe 'y'/'n' to drive it.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/aws_check.fish
awk '/^function _ts_ensure_session/,/^end$/' $repo/conf.d/travelstop.fish | source

# --- stubs ---------------------------------------------------------------
set -g TS_LOG (mktemp)
function _ts_log; echo $argv >>$TS_LOG; end
for c in magenta yellow blue green red dim
    function $c; echo $argv; end
end

# fake aws: record args, exit with $AWS_RC (default 0)
set -g AWS_LOG (mktemp)
set -g AWS_RC 0
function aws; echo "$argv" >>$AWS_LOG; return $AWS_RC; end

# fake assume (the re-auth on retry): record the profile it was asked to log in
set -g ASSUME_LOG (mktemp)
function assume; echo "$argv" >>$ASSUME_LOG; end

# ===== valid session: aws exits 0 -> helper returns 0 (no prompt) =====
set AWS_RC 0
echo -n >$TS_LOG; echo -n >$AWS_LOG
_ts_ensure_session STAGE </dev/null
@test "valid session returns 0" $status -eq 0
@test "valid session calls sts for the given profile" (string match -q '*sts get-caller-identity*--profile STAGE*' -- (cat $AWS_LOG); echo $status) -eq 0
@test "valid session is silent" (test -s $TS_LOG; echo $status) -eq 1
@test "valid session checks exactly once" (count (cat $AWS_LOG)) -eq 1

# ===== empty profile + no arg -> skip (returns 0, no aws) =====
set AWS_RC 0
set -e AWS_PROFILE
echo -n >$TS_LOG; echo -n >$AWS_LOG
_ts_ensure_session </dev/null
@test "empty profile returns 0" $status -eq 0
@test "empty profile logs skipping" (string match -q '*skipping session check*' -- (cat $TS_LOG); echo $status) -eq 0
@test "empty profile never calls aws" (test -s $AWS_LOG; echo $status) -eq 1

# ===== arg overrides $AWS_PROFILE =====
set AWS_RC 0
set -gx AWS_PROFILE envprof
echo -n >$AWS_LOG
_ts_ensure_session ARGPROF </dev/null
@test "arg profile wins over AWS_PROFILE" (string match -q '*--profile ARGPROF*' -- (cat $AWS_LOG); echo $status) -eq 0
@test "arg profile does not use AWS_PROFILE" (string match -q '*--profile envprof*' -- (cat $AWS_LOG); echo $status) -eq 1

# ===== aws_check wrapper delegates to the helper =====
set AWS_RC 0
echo -n >$AWS_LOG
aws_check TEST </dev/null
@test "aws_check returns 0 on a valid session" $status -eq 0
@test "aws_check checks the passed profile" (string match -q '*--profile TEST*' -- (cat $AWS_LOG); echo $status) -eq 0

# ===== expired + non-interactive (EOF at the prompt) -> abort (1) =====
# aws always fails; no stdin to answer the retry prompt -> read hits EOF -> abort.
function aws; echo "$argv" >>$AWS_LOG; return 1; end
echo -n >$TS_LOG; echo -n >$AWS_LOG
_ts_ensure_session STAGE </dev/null
@test "expired + EOF returns 1" $status -eq 1
@test "expired logs the expired line" (string match -q '*AWS session expired for STAGE*' -- (cat $TS_LOG); echo $status) -eq 0
@test "expired + EOF tried exactly once" (count (cat $AWS_LOG)) -eq 1

# ===== expired + user declines ('n') -> abort (1), no re-auth =====
echo -n >$TS_LOG; echo -n >$AWS_LOG; echo -n >$ASSUME_LOG
printf 'n' | _ts_ensure_session STAGE
@test "decline returns 1" $status -eq 1
@test "decline logs the assume guidance" (string match -q '*assume STAGE*' -- (cat $TS_LOG); echo $status) -eq 0
@test "decline tried exactly once" (count (cat $AWS_LOG)) -eq 1
@test "decline does not re-auth" (test -s $ASSUME_LOG; echo $status) -eq 1

# ===== expired then re-auth via assume ('y') -> continue (0) =====
# aws fails while state=failing; the assume re-auth flips it to ok; on the next
# loop the re-check passes -> helper returns 0.
set -g RETRY_STATE (mktemp); echo failing >$RETRY_STATE
function aws; echo "$argv" >>$AWS_LOG; test (cat $RETRY_STATE) = ok; end
function assume; echo "$argv" >>$ASSUME_LOG; echo ok >$RETRY_STATE; end
echo -n >$TS_LOG; echo -n >$AWS_LOG; echo -n >$ASSUME_LOG
printf 'y' | _ts_ensure_session STAGE
@test "retry after re-auth returns 0" $status -eq 0
@test "retry re-authenticated the profile via assume" (string match -q '*STAGE*' -- (cat $ASSUME_LOG); echo $status) -eq 0
@test "retry re-checked the session (2 sts calls)" (count (cat $AWS_LOG)) -eq 2
