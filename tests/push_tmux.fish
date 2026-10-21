# fishtape spec for push's tmux view (parallel deploys in a private tmux
# session), run against the committed fixture project.
# Run: fishtape tests/push_tmux.fish < /dev/null
#
# push runs in a background child fish (TS_PUSH_TMUX_TEST: tmux mode without a
# terminal and without attaching) so the test can inspect the session from
# outside: panes, headers, focus, and answer the retry prompts with send-keys.
# Only side-effects are stubbed, the same way as tests/push.fish.

if not command -q tmux
    @test "tmux not installed: skipped" 0 -eq 0
    exit 0
end

set -l here (path dirname (status filename))
set -g repo (path dirname $here)
set -g TS_ROOT (mktemp -d)
cp -R $here/fixtures/project/. $TS_ROOT
set -gx XDG_RUNTIME_DIR $TS_ROOT/run
set -gx XDG_CONFIG_HOME $TS_ROOT/cfg
mkdir -p $XDG_RUNTIME_DIR $XDG_CONFIG_HOME/fish/conf.d
# tmux sockets live here, never in the real /tmp/tmux-<uid>. kept short: a unix
# socket path is limited to ~104 bytes
set -gx TMUX_TMPDIR (mktemp -d /tmp/tsx.XXXX)
set -gx TS_PUSH_TMUX_TEST 1

source $repo/functions/push.fish
source (awk '/^function _ts_service_name /{p=1} p{print} /^function _ts_functions /{f=1} f&&/^end$/{exit}' $repo/conf.d/travelstop.fish | psub)

# --- stub only external side-effects -------------------------------------
function _ts_log; echo $argv; end
for c in magenta yellow blue green red dim ansi-escape
    function $c; echo $argv; end
end
function rename_modules; end
function _ts_ensure_session; end
# TS_INSTALL_SLEEP: the dependency install takes that long
function _ts_pm_install
    set -q TS_INSTALL_SLEEP && echo sleep $TS_INSTALL_SLEEP && return
    echo true
end
set -gx TS_NOTIFY_LOG (mktemp)
function _ts_notify; echo "$argv" >>$TS_NOTIFY_LOG; end
set -gx TS_SLS_LOG (mktemp)
# TS_FAIL_FLAG: globs (one per line) matched against the sls argv; a matching
# deploy fails and its line goes, so a retry succeeds. TS_SLS_SLEEP keeps
# deploys running long enough to look at the layout; deploys matching the
# TS_SLOW glob take 15s instead.
set -gx TS_FAIL_FLAG (mktemp)
function _ts_sls
    echo "$argv" >>$TS_SLS_LOG
    echo "sls $argv"
    set -l secs $TS_SLS_SLEEP
    set -q TS_SLOW && string match -q -- $TS_SLOW "$argv" && set secs 15
    # a Ctrl-C interrupts the sleep: exit with its status like sls would
    if test -n "$secs"
        sleep $secs; or return $status
    end
    set -l globs (cat $TS_FAIL_FLAG)
    set -l k 1
    while test $k -le (count $globs)
        if string match -q -- $globs[$k] "$argv"
            set -e globs[$k]
            printf '%s\n' $globs >$TS_FAIL_FLAG
            return 1
        end
        set k (math $k + 1)
    end
    return 0
end
function _ts_cdk
    echo "cdk $argv" >>$TS_SLS_LOG
    echo "cdk $argv"
    test -n "$TS_SLS_SLEEP" && sleep $TS_SLS_SLEEP
    return 0
end
# build_libs (module-libs) builds for TS_BUILD_SLEEP seconds; like the real one
# it does not stop when a step inside it is interrupted
function build_libs
    test -n "$TS_BUILD_SLEEP" && sleep $TS_BUILD_SLEEP
    return 0
end
# the push child, its coordinator and its panes are fresh fish processes: hand
# them the stubs and the listing helpers through the temp conf.d
functions _ts_log magenta yellow blue green red dim ansi-escape \
    rename_modules _ts_ensure_session _ts_pm_install _ts_notify _ts_sls _ts_cdk build_libs \
    >$XDG_CONFIG_HOME/fish/conf.d/ts_stubs.fish
awk '/^function _ts_service_name /{p=1} p{print} /^function _ts_functions /{f=1} f&&/^end$/{exit}' $repo/conf.d/travelstop.fish \
    >$XDG_CONFIG_HOME/fish/conf.d/ts_listing.fish

set -gx AWS_PROFILE acme@dev
set -gx AWS_REGION us-east-1
set -gx _ts_project_dir TS_PD
set -gx TS_PD $TS_ROOT
set -gx PATH $TS_ROOT/bin $PATH
cd $TS_ROOT

mkdir -p $TS_ROOT/modules/libs
printf "service: module-libs\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/modules/libs/serverless.yml
# two more independent services, so 4 deploy at once
for s in cars trains
    mkdir -p $TS_ROOT/$s
    printf "service: $s\nprovider:\n  region: 'us-east-1'\n" >$TS_ROOT/$s/serverless.yml
end

# --- helpers ---------------------------------------------------------------
set -g TS_PUSH_OUT (mktemp)
function ts_push_bg -d "start push in a background child fish"
    echo -n >$TS_SLS_LOG
    echo -n >$TS_NOTIFY_LOG
    fish -C "source $repo/functions/push.fish" -c 'push $argv' -- $argv </dev/null >$TS_PUSH_OUT 2>&1 &
    set -g ts_push_pid $last_pid
    # push names its tmux server after its own pid
    set -g ts_sock ts_push_$ts_push_pid
end
function ts_tmux; command tmux -L $ts_sock $argv; end
function ts_until -a tries -d "poll a condition every 0.1s (the rest of argv, eval'd each time)"
    for n in (seq $tries)
        eval $argv[2..] 2>/dev/null && return 0
        sleep 0.1
    end
    return 1
end
function ts_session_up; ts_tmux has-session -t push; end
function ts_panes; ts_tmux list-panes -t push -F '#{pane_left} #{pane_top} #{pane_width} #{pane_height}'; end
function ts_titles; ts_tmux list-panes -t push -F '#{@ts_title}'; end
function ts_left_text; ts_tmux capture-pane -p -t push:0.0 -S -100; end
function ts_left_says -a text; string match -q -- "*$text*" (ts_left_text); end
function ts_finish -d "close the finished view with a key and wait for push to exit"
    ts_until 300 "ts_left_says 'press any key'"
    ts_tmux send-keys -t push:0.0 q
    wait $ts_push_pid
end
function ts_pane_of -a title -d "pane id whose header shows <title>"
    ts_tmux list-panes -t push -F '#{pane_id} #{@ts_title}' | string match -r -- "^(\S+) $title\$" | tail -1
end
function ts_pane_state -a title
    ts_tmux display -p -t (ts_pane_of $title) '#{@ts_state}'
end
function ts_prompting -a title; test (ts_pane_state $title) = prompt; end

# ===== 4 stacks: stack list + 2 columns x 2 rows =====
set -gx TS_SLS_SLEEP 2
ts_push_bg hotels flights cars trains
ts_until 100 ts_session_up
@test "4 stacks open a tmux session" (ts_session_up; echo $status) -eq 0
ts_until 50 'test (count (ts_panes)) -eq 5'
set -l geo (ts_panes)
@test "4 stacks: stack list + 4 deploy panes" (count $geo) -eq 5
echo $geo[1] | read -l l0 t0 w0 h0
@test "stack list is the left column" $l0 -eq 0
@test "stack list is at least 30 columns wide" $w0 -ge 30
set -l lefts (for g in $geo[2..]; string split -f1 ' ' -- $g; end | sort -u)
set -l tops (for g in $geo[2..]; string split -f2 ' ' -- $g; end | sort -u)
@test "deploy panes form 2 columns" (count $lefts) -eq 2
@test "deploy panes form 2 rows" (count $tops) -eq 2
ts_until 50 'test (count (string match -- "*/serverless.yml" (ts_titles))) -eq 4'
@test "headers show the serverless file relative to the project root" \
    (ts_titles | string match -r -- '^(?:cars|flights|hotels|trains)/serverless.yml$' | count) -eq 4
@test "stack list header" (ts_titles)[1] = stacks
@test "stack list shows every stack" (ts_left_says hotels-service-DEV; and ts_left_says trains-DEV; echo $status) -eq 0
@test "running stacks show their pane number" (ts_left_says '[1]'; echo $status) -eq 0
# numbered row by row: [1] [2] on top, [3] [4] below
@test "pane headers carry their number" (ts_tmux list-panes -t push -F '#{@ts_slot}' | sort | string join ,) = ,1,2,3,4
@test "pane numbers run row by row" (ts_tmux list-panes -t push -F '#{pane_top} #{pane_left} #{@ts_slot}' | sort -n -k1,1 -k2,2 | string replace -r '.* ' '' | string join ,) = ,1,2,3,4
@test "the user's default tmux server is never started" (test -e $TMUX_TMPDIR/tmux-(id -u)/default; echo $status) -eq 1
ts_finish
@test "every stack deployed" (count (cat $TS_SLS_LOG)) -eq 4
@test "summary notification counts the successes" (string match -q '*success: 4, failure: 0*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
@test "the session is gone once push returns" (ts_session_up; echo $status) -ne 0
@test "its socket file is removed too" (test -e $TMUX_TMPDIR/tmux-(id -u)/$ts_sock; echo $status) -eq 1

# ===== 2 stacks: stack list + 2 side-by-side columns =====
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 50 'test (count (ts_panes)) -eq 3'
set -l geo (ts_panes)
@test "2 stacks: stack list + 2 deploy panes" (count $geo) -eq 3
echo $geo[1] | read -l l0 t0 w0 h0
echo $geo[2] | read -l l1 t1 w1 h1
echo $geo[3] | read -l l2 t2 w2 h2
@test "2 stacks sit side by side" "$t1 $t2" = "$t0 $t0"
@test "2 stacks get full-height columns" "$h1 $h2" = "$h0 $h0"
@test "2 stacks get separate columns" $l1 -ne $l2
ts_finish

# ===== 3 stacks with -j 4: 3 deploy panes =====
ts_push_bg hotels flights cars
ts_until 100 ts_session_up
ts_until 50 'test (count (ts_panes)) -eq 4'
@test "3 stacks: stack list + 3 deploy panes" (count (ts_panes)) -eq 4
ts_finish

# ===== cdk app header is its directory =====
ts_push_bg hotels flights chat/resources
ts_until 100 ts_session_up
ts_until 50 'contains chat/resources (ts_titles)'
@test "cdk header is the app directory" (contains chat/resources (ts_titles); echo $status) -eq 0
ts_finish

# ===== no tmux: 1 stack, -j 1, --no-tmux, ts_push_tmux off =====
set -e TS_SLS_SLEEP
function ts_no_server; not count $TMUX_TMPDIR/tmux-*/* >/dev/null; end
command rm -rf $TMUX_TMPDIR/tmux-*
echo -n >$TS_SLS_LOG
push hotels </dev/null >/dev/null 2>&1
@test "1 stack deploys without tmux" (ts_no_server; echo $status) -eq 0
@test "1 stack still deploys" (count (cat $TS_SLS_LOG)) -eq 1
echo -n >$TS_SLS_LOG
push -j 1 hotels flights cars </dev/null >/dev/null 2>&1
@test "-j 1 deploys without tmux" (ts_no_server; echo $status) -eq 0
@test "-j 1 still deploys" (count (cat $TS_SLS_LOG)) -eq 3
push --no-tmux hotels flights </dev/null >/dev/null 2>&1
@test "--no-tmux deploys without tmux" (ts_no_server; echo $status) -eq 0
set -g ts_push_tmux off
push hotels flights </dev/null >/dev/null 2>&1
@test "ts_push_tmux=off deploys without tmux" (ts_no_server; echo $status) -eq 0
set -e ts_push_tmux

# ===== failure: prompt in its own pane, focused, retry right there =====
set -gx TS_SLS_SLEEP 1
echo '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 ts_prompting flights/serverless.yml
@test "a failed deploy asks in its own pane" (ts_prompting flights/serverless.yml; echo $status) -eq 0
set -l failed (ts_pane_of flights/serverless.yml)
function ts_active; ts_tmux display -p -t push '#{pane_id}'; end
ts_until 30 "test (ts_active) = $failed"
@test "the asking pane gets the focus" (ts_active) = $failed
@test "the prompt is in the pane" (string match -q '*[r]etry*' -- (ts_tmux capture-pane -p -t $failed); echo $status) -eq 0
ts_until 30 "ts_left_says 'retry?'"
@test "the stack list flags the waiting stack" (ts_left_says 'retry?'; echo $status) -eq 0
@test "a failure notifies" (string match -q '*push failed*flights*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
ts_tmux send-keys -t $failed r
ts_until 300 "ts_left_says 'press any key'"
@test "the focus is back on the stack list to close the view" (ts_active) = (ts_tmux display -p -t push:0.0 '#{pane_id}')
ts_finish
@test "retry reruns only the failed stack" (count (cat $TS_SLS_LOG)) -eq 3
@test "retry in the pane succeeds" (string match -q '*success: 2, failure: 0*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0

# ===== two prompts: answering one moves the focus to the other =====
printf '%s\n' '*/hotels *' '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 "ts_prompting hotels/serverless.yml; and ts_prompting flights/serverless.yml"
ts_until 30 "contains (ts_active) (ts_pane_of hotels/serverless.yml) (ts_pane_of flights/serverless.yml)"
set -l first (ts_active)
set -l other (ts_pane_of hotels/serverless.yml)
test $other = $first && set other (ts_pane_of flights/serverless.yml)
ts_tmux send-keys -t $first s
ts_until 30 "test (ts_active) = $other"
@test "answering one prompt focuses the other" (ts_active) = $other
ts_tmux send-keys -t $other s
ts_finish
@test "both skips are failures" (string match -q '*success: 0, failure: 2*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0

# ===== the focus stays where the user puts it while a prompt waits =====
echo '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 ts_prompting flights/serverless.yml
ts_until 30 "test (ts_active) = (ts_pane_of flights/serverless.yml)"
set -l list_pane (ts_tmux display -p -t push:0.0 '#{pane_id}')
ts_tmux select-pane -t $list_pane
sleep 1
@test "a click away from a waiting prompt sticks" (ts_active) = $list_pane
ts_tmux send-keys -t (ts_pane_of flights/serverless.yml) s
ts_finish

# ===== an abort ends the other waiting prompts as failures =====
printf '%s\n' '*/hotels *' '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 "ts_prompting hotels/serverless.yml; and ts_prompting flights/serverless.yml"
ts_tmux send-keys -t (ts_pane_of hotels/serverless.yml) a
ts_until 50 "test (ts_pane_state flights/serverless.yml) = failure"
@test "an abort ends the other prompt" (ts_pane_state flights/serverless.yml) = failure
ts_finish
@test "both count as failed, nothing redeployed" (string match -q '*success: 0, failure: 2*' -- (cat $TS_NOTIFY_LOG); and test (count (cat $TS_SLS_LOG)) -eq 2; echo $status) -eq 0

# ===== skip =====
echo '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 ts_prompting flights/serverless.yml
ts_tmux send-keys -t (ts_pane_of flights/serverless.yml) s
ts_finish
@test "skip records the failure" (string match -q '*success: 1, failure: 1*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
@test "skip does not redeploy" (count (cat $TS_SLS_LOG)) -eq 2

# ===== abort: nothing new starts =====
echo '*/modules/auth *' >$TS_FAIL_FLAG
ts_push_bg modules/auth hotels flights
ts_until 100 ts_session_up
ts_until 100 ts_prompting modules/auth/serverless.yml
ts_tmux send-keys -t (ts_pane_of modules/auth/serverless.yml) a
ts_finish
@test "abort starts no further stacks" (count (cat $TS_SLS_LOG)) -eq 1
@test "abort counts the failure" (string match -q '*success: 0, failure: 1*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0

# ===== Ctrl-C in the stack list stops every deploy =====
set -gx TS_SLS_SLEEP 5
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 'test (count (cat $TS_SLS_LOG)) -eq 2'
ts_tmux send-keys -t push:0.0 C-c
ts_finish
@test "Ctrl-C in the stack list ends the run early" (string match -q '*success: 0, failure: 0*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
@test "Ctrl-C leaves the stacks to resume" (string match -q '*remaining*push -C*' -- (cat $TS_PUSH_OUT); echo $status) -eq 0

# ===== Ctrl-C after an abort still stops what runs =====
set -gx TS_SLS_SLEEP 1
set -gx TS_SLOW '*/hotels *'
echo '*/flights *' >$TS_FAIL_FLAG
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 100 ts_prompting flights/serverless.yml
ts_tmux send-keys -t (ts_pane_of flights/serverless.yml) a
sleep 0.5
ts_tmux send-keys -t push:0.0 C-c
ts_until 50 "test (ts_pane_state hotels/serverless.yml) = stopped"
@test "Ctrl-C after an abort stops the running deploy" (ts_pane_state hotels/serverless.yml) = stopped
ts_finish
@test "the stopped deploy is left to resume" (string match -q '*success: 0, failure: 1*' -- (cat $TS_NOTIFY_LOG); echo $status) -eq 0
set -e TS_SLOW

# ===== Ctrl-C during the dependency install deploys nothing =====
set -gx TS_INSTALL_SLEEP 5
ts_push_bg hotels flights
ts_until 100 ts_session_up
ts_until 50 'test (count (string match running (ts_tmux list-panes -t push -F "#{@ts_state}"))) -eq 2'
sleep 1
ts_tmux send-keys -t push:0.0 C-c
ts_finish
@test "Ctrl-C during the install deploys nothing" (count (cat $TS_SLS_LOG)) -eq 0
set -e TS_INSTALL_SLEEP
set -e TS_SLS_SLEEP

# ===== Ctrl-C while build_libs runs deploys nothing =====
set -gx TS_SLS_SLEEP 5
set -gx TS_BUILD_SLEEP 5
ts_push_bg modules/libs modules/auth
ts_until 100 ts_session_up
ts_until 50 'test (count (string match running (ts_tmux list-panes -t push -F "#{@ts_state}"))) -eq 2'
sleep 1
ts_tmux send-keys -t push:0.0 C-c
ts_finish
@test "Ctrl-C during build_libs does not deploy the libs" (string match -q '*/modules/libs *' -- (cat $TS_SLS_LOG); echo $status) -eq 1
set -e TS_BUILD_SLEEP TS_SLS_SLEEP

# ===== no view when nothing deploys side by side =====
command rm -rf $TMUX_TMPDIR/tmux-*
echo -n >$TS_SLS_LOG
push modules/auth hotels </dev/null >/dev/null 2>&1
@test "a module then its service deploy without tmux" (ts_no_server; echo $status) -eq 0
@test "a module then its service still deploy" (count (cat $TS_SLS_LOG)) -eq 2

# --- teardown ------------------------------------------------------------
cd $repo
command tmux -L $ts_sock kill-server 2>/dev/null
rm -rf $TS_ROOT $TMUX_TMPDIR
rm -f $TS_SLS_LOG $TS_NOTIFY_LOG $TS_FAIL_FLAG $TS_PUSH_OUT
