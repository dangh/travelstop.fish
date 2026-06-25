# fishtape spec for daily_report (functions/daily_report.fish).
# Run: fishtape tests/daily_report.fish < /dev/null
#
# Real code under test: the pure helpers _pluralize, _find_dir, _get_error_message
# and the main daily_report function. Fixtures live under tests/fixtures/daily_report
# and are never mutated. The only external stubbed is AWS_BROWSER, pointed at a fake
# script (tests/fixtures/daily_report/bin/fakebrowser) so we can assert the launch
# path without opening a real browser. node is required (used by the function itself)
# and is exercised for real against the JS/yml fixtures.
#
# Assertions reflect ACTUAL behaviour read from the source, including the known bug
# in _pluralize's `*y` branch (it echoes the literal command instead of running it).

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -g DR_ROOT $here/fixtures/daily_report
set -g DR_MASTER $DR_ROOT/master
set -g DR_SERVICES $DR_ROOT/services

source $repo/functions/daily_report.fish

# ===== _pluralize: singular/plural/-s/-y rules =====
@test "_pluralize appends s to a bare word" (_pluralize hotel) = hotels
@test "_pluralize leaves an -s word unchanged" (_pluralize hotels) = hotels
@test "_pluralize leaves another -s word unchanged" (_pluralize bus) = bus
# Known bug: the `*y` branch echoes the literal `string replace ...` command
# instead of executing it. We assert the real (buggy) output, not the intent.
@test "_pluralize -y branch returns the literal command string" (_pluralize country) = "string replace -r y\$ ies country"

# ===== _find_dir: resolve a stack dir under a root via pluralized parts =====
@test "_find_dir resolves single-part stack to pluralized dir" (_find_dir $DR_SERVICES hotel) = $DR_SERVICES/hotels
@test "_find_dir resolves hyphenated multi-part stack" (_find_dir $DR_SERVICES flight-booking) = $DR_SERVICES/flight-bookings
@test "_find_dir returns 0 on a hit" (_find_dir $DR_SERVICES hotel >/dev/null; echo $status) -eq 0
@test "_find_dir returns 1 when nothing matches" (_find_dir $DR_SERVICES nope >/dev/null; echo $status) -eq 1
@test "_find_dir prints nothing when nothing matches" (count (_find_dir $DR_SERVICES nope)) -eq 0

# ===== _get_error_message: parse the last catch clause's log message =====
@test "_get_error_message extracts a log.error message" (_get_error_message $DR_SERVICES/js/error.js) = "Failed to fetch hotel"
@test "_get_error_message extracts a log.info message" (_get_error_message $DR_SERVICES/js/info.js) = "Could not load data"
@test "_get_error_message uses the LAST catch clause" (_get_error_message $DR_SERVICES/js/nested.js) = "second error here"
@test "_get_error_message reads a 6-space-indented log statement" (_get_error_message $DR_SERVICES/js/deep.js) = "deep nested message"

# ===== daily_report: guard + end-to-end URL =====
@test "daily_report returns 1 without ts_master_dir" (begin; set -lx ts_master_dir; daily_report a-prod-b; echo $status; end) -eq 1
@test "daily_report prints error when ts_master_dir unset" (begin; set -lx ts_master_dir; daily_report a-prod-b 2>&1 >/dev/null; end | string match -q '*is not set*'; echo $status) -eq 0
@test "daily_report returns 1 when ts_master_dir missing" (begin; set -lx ts_master_dir /no/such/dir; daily_report a-prod-b; echo $status; end) -eq 1
@test "daily_report prints error when ts_master_dir missing" (begin; set -lx ts_master_dir /no/such/dir; daily_report a-prod-b 2>&1 >/dev/null; end | string match -q '*does not exist*'; echo $status) -eq 0

set -gx ts_master_dir $DR_MASTER
set -e AWS_BROWSER

set -l url (daily_report hotels-prod-getHotel)
@test "daily_report container is the upper-cased stage" (string match -q '*name=PROD*' -- $url; echo $status) -eq 0
@test "daily_report defaults to ap-southeast-1 region" (string match -q '*region=ap-southeast-1*' -- $url; echo $status) -eq 0
@test "daily_report log-group encodes stack-stage-function" (string match -q '*hotels-prod-getHotel*' -- $url; echo $status) -eq 0
@test "daily_report filter query comes from the handler's catch log" (string match -q '*$2522Failed to fetch hotel$2522*' -- $url; echo $status) -eq 0
@test "daily_report emits a numeric start window" (string match -rq 'start\$3D[0-9]+' -- $url; echo $status) -eq 0

# dev-in stage selects the ap-south-1 region
set -l url_in (daily_report hotels-dev-in-getHotel)
@test "daily_report dev-in stage uses ap-south-1" (string match -q '*region=ap-south-1*' -- $url_in; echo $status) -eq 0

# /opt/<handler> resolves into the master modules dir
set -l url_opt (daily_report hotels-prod-optFn)
@test "daily_report resolves /opt handler from modules dir" (string match -q '*$2522module level failure$2522*' -- $url_opt; echo $status) -eq 0

# admin-* stack resolves into admin/services and keeps the full log-group name
set -l url_admin (daily_report admin-hotels-prod-getHotel)
@test "daily_report admin stack reads admin/services handler" (string match -q '*$2522Failed to fetch admin hotel$2522*' -- $url_admin; echo $status) -eq 0
@test "daily_report admin stack keeps full log-group name" (string match -q '*admin-hotels-prod-getHotel*' -- $url_admin; echo $status) -eq 0

# unresolvable service -> fallback query "Failed to"
set -l url_fb (daily_report unknownsvc-prod-doThing)
@test "daily_report falls back to 'Failed to' query" (string match -q '*$2522Failed to$2522*' -- $url_fb; echo $status) -eq 0

# ===== daily_report: AWS_BROWSER launch path (stubbed fake browser) =====
set -gx AWS_BROWSER $DR_ROOT/bin/fakebrowser

set -e AWS_BROWSER_NEW_WINDOW
set -l b (daily_report hotels-prod-getHotel)
@test "daily_report invokes AWS_BROWSER instead of printing" (string match -q 'BROWSER_CALLED*' -- $b; echo $status) -eq 0
@test "daily_report passes the url to the browser" (string match -q '*hotels-prod-getHotel*' -- $b; echo $status) -eq 0

set -gx AWS_BROWSER_NEW_WINDOW 1
set -l bw (daily_report hotels-prod-getHotel)
@test "daily_report adds --new-window when AWS_BROWSER_NEW_WINDOW=1" (string match -q '*--new-window*' -- $bw; echo $status) -eq 0

# --- teardown ------------------------------------------------------------
set -e ts_master_dir
set -e AWS_BROWSER
set -e AWS_BROWSER_NEW_WINDOW
