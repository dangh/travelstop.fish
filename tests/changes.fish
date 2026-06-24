# fishtape spec for `changes` (functions/changes.fish), exercising the real
# git-diff logic via a throwaway fixture repo built at runtime under mktemp.
#
# Real code under test: changes, _change_stacks, _change_mappings,
# _change_translations. No git is stubbed -- a deterministic fixture repo
# (fixed GIT_AUTHOR_*/GIT_COMMITTER_*) with a base commit on master and a
# feature branch produces known `git diff`/`merge-base` output.
#
# Only stubbed: the color/style helpers (magenta, dim, bold, ... ) which are
# not defined in this repo (they live in the user's global fish config). They
# are turned into pass-through echoes so the textual content can be asserted.
# Mapping output is colorised by ~/.config/fish/functions/logs.awk (an external
# awk filter we do not stub), so for mappings we only assert the clean header
# lines it emits (PUT /<index>, etc.), not the colourised JSON body.
#
# Run: fishtape tests/changes.fish < /dev/null

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

# --- stub only the missing color/style helpers (pass-through) ------------
for c in magenta yellow blue green red dim bold reverse cyan
    function $c; echo $argv; end
end

source $repo/functions/changes.fish

# --- build a deterministic throwaway git repo ----------------------------
set -gx GIT_AUTHOR_NAME tester
set -gx GIT_AUTHOR_EMAIL tester@example.com
set -gx GIT_AUTHOR_DATE '2020-01-01T00:00:00 +0000'
set -gx GIT_COMMITTER_NAME tester
set -gx GIT_COMMITTER_EMAIL tester@example.com
set -gx GIT_COMMITTER_DATE '2020-01-01T00:00:00 +0000'

set -g FIX (mktemp -d)
cd $FIX
git init -q >/dev/null 2>&1
git symbolic-ref HEAD refs/heads/master
git config user.email tester@example.com
git config user.name tester

# base tree on master --------------------------------------------------
mkdir -p services/hotels services/flights modules/auth \
    modules/templates/translations web/locales schema
printf 'service: hotels-service\n' >services/hotels/serverless.yml
printf '{\n  "name": "travelstop-hotels-service",\n  "version": "1.2.3"\n}\n' >services/hotels/package.json
printf 'service: flights-service\n' >services/flights/serverless.yml
printf '{\n  "name": "flights-service",\n  "version": "4.5.6"\n}\n' >services/flights/package.json
printf 'service: module-auth\n' >modules/auth/serverless.yml
printf '{\n  "name": "module-auth",\n  "version": "2.0.0"\n}\n' >modules/auth/package.json
printf '{"hello":"Hi","bye":"Bye"}\n' >modules/templates/translations/en-GB.json
printf '{"home":"Home"}\n' >web/locales/en-GB.json
printf '{"mappings":{"properties":{"id":{"type":"keyword"}}}}\n' >schema/foo-index-mappings.json
git add -A
git commit -qm base

# feature branch with known changes -----------------------------------
git checkout -qb feature
printf 'service: hotels-service\nx: 1\n' >services/hotels/serverless.yml
printf 'service: flights-service\nx: 1\n' >services/flights/serverless.yml
printf 'service: module-auth\ny: 2\n' >modules/auth/serverless.yml
printf '{"hello":"Hi","bye":"Bye","welcome":"Welcome {name}"}\n' >modules/templates/translations/en-GB.json
printf '{"home":"Home","about":"About"}\n' >web/locales/en-GB.json
printf '{"mappings":{"properties":{"id":{"type":"keyword"},"name":{"type":"text"}}}}\n' >schema/foo-index-mappings.json
printf '{"mappings":{"properties":{"x":{"type":"long"}}}}\n' >schema/bar-index-mappings.json
git add -A
git commit -qm feat

# origin/master = master tip so `merge-base origin/master HEAD` resolves
git update-ref refs/remotes/origin/master refs/heads/master

# ===== changes stacks (default = merge-base..index) =====================
set -l stacks (changes stacks)
@test "stacks: emits one line per changed package" (count $stacks) -eq 3
# ordering: module-* group first, then services sorted by group name
@test "stacks: module-auth listed first"   "$stacks[1]" = "- module-auth-2.0.0"
@test "stacks: flights before hotels"       "$stacks[2]" = "- flights-service-4.5.6"
@test "stacks: hotels last (name minus travelstop- prefix, with version)" "$stacks[3]" = "- hotels-service-1.2.3"

# ===== changes stacks --output=path (raw package dirs, git-diff order) ==
set -l paths (changes stacks --output=path)
@test "path: three package dirs" (count $paths) -eq 3
@test "path: modules/auth dir"   (contains modules/auth $paths; echo $status) -eq 0
@test "path: services/flights dir" (contains services/flights $paths; echo $status) -eq 0
@test "path: services/hotels dir"  (contains services/hotels $paths; echo $status) -eq 0

# ===== --exclude drops matching files (anchored regex) ==================
set -l ex (changes stacks --exclude='services/flights/serverless.yml')
@test "exclude: flights removed" (count $ex) -eq 2
@test "exclude: flights not present" (string match -q '*flights*' -- $ex; echo $status) -eq 1
@test "exclude: hotels still present" (contains -- "- hotels-service-1.2.3" $ex; echo $status) -eq 0

# ===== --from=<ref> explicit range (master == merge-base here) ==========
set -l fromref (changes stacks --from=master)
@test "from=master: same 3 stacks as merge-base default" (count $fromref) -eq 3
@test "from=master: equals default output" "$fromref" = "$stacks"

# ===== changes (no type) = combined report with a Packages section ======
set -l all (changes 2>/dev/null)
@test "all: contains Packages header" (string match -q '*Packages*' -- $all; echo $status) -eq 0
@test "all: lists the hotels stack" (contains -- "- hotels-service-1.2.3" $all; echo $status) -eq 0

# ===== changes mappings (real index-mapping diff via node) ==============
# foo had a 'name' property added -> PUT /foo/_mapping ; bar is brand new -> PUT /bar
set -l maps (changes mappings)
@test "mappings: PUT for the new bar index"        (contains -- "PUT /bar" $maps; echo $status) -eq 0
@test "mappings: PUT _mapping for the changed foo" (contains -- "PUT /foo/_mapping" $maps; echo $status) -eq 0

# ===== changes translations (from=origin/master by default) =============
set -l tr (changes translations)
@test "translations: Services section" (string match -q '*Services*' -- $tr; echo $status) -eq 0
@test "translations: Web section"      (string match -q '*Web*' -- $tr; echo $status) -eq 0
# the only new service key is `welcome`; only new web key is `about`
@test "translations: new service key welcome" (string match -q '*`welcome`*' -- $tr; echo $status) -eq 0
@test "translations: new web key about"       (string match -q '*`about`*' -- $tr; echo $status) -eq 0
@test "translations: unchanged keys are not reported" (string match -q '*`hello`*' -- $tr; echo $status) -eq 1

# --- teardown ------------------------------------------------------------
cd $repo
rm -rf $FIX
