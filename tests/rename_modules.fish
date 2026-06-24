# fishtape spec for rename_modules (functions/rename_modules.fish).
# Run: fishtape tests/rename_modules.fish < /dev/null
#
# rename_modules MUTATES the module serverless.yml files, so this spec never
# touches the committed tree: the pristine namespaced fixture under
# tests/fixtures/rename_modules is copied into a `mktemp -d` and _ts_project_dir
# is pointed there. The temp dir is rm -rf'd in teardown.
#
# Deterministic, git-independent path under test: the `-f/--force` (force) mode
# renames every module unconditionally, so we drive `rename_modules -f <name>`
# as the "on" toggle and `rename_modules off` as the restore, asserting the
# `service:` lines (and the layer `cf:` ref) change then restore. The
# branch/diff-driven paths (`on` with no force, default changed-modules path)
# depend on `git branch`/`git merge-base` and are intentionally not exercised.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/rename_modules.fish

# --- throwaway copy of the fixture tree (committed fixtures stay pristine) ---
set -g TS_TMP (mktemp -d)
cp -R $here/fixtures/rename_modules/ $TS_TMP/

# _ts_project_dir indirection: the function reads `$$_ts_project_dir`.
set -g _ts_project_dir TS_PD
set -g TS_PD $TS_TMP

set -l auth_yml $TS_TMP/modules/auth/serverless.yml
set -l bill_yml $TS_TMP/modules/billing/serverless.yml
set -l layer_yml $TS_TMP/services/serverless-layers.yml

function service_line -a yml
    string match -qr '^service:\s*(?<name>\S+)' <$yml
    echo $name
end

# ===== baseline: fixture copy starts un-suffixed =====
@test "baseline auth service line" (service_line $auth_yml) = module-auth
@test "baseline billing service line" (service_line $bill_yml) = module-billing
@test "baseline layer cf ref" (cat $layer_yml | string match -q '*cf:module-auth-LayerLambdaArn*'; echo $status) -eq 0

# ===== rename ON (force mode -> deterministic suffix from the action arg) =====
rename_modules -f MyFeature

@test "on: auth gets lowercased suffix" (service_line $auth_yml) = module-auth-myfeature
@test "on: billing gets lowercased suffix" (service_line $bill_yml) = module-billing-myfeature
@test "on: layer cf ref gets suffix" (cat $layer_yml | string match -q '*cf:module-auth-myfeature-LayerLambdaArn*'; echo $status) -eq 0
@test "on: no stray .ts_bak files left behind" (count $TS_TMP/modules/*/*.ts_bak $TS_TMP/services/*.ts_bak 2>/dev/null) -eq 0

# ===== rename OFF (empty suffix -> restore) =====
rename_modules off

@test "off: auth restored" (service_line $auth_yml) = module-auth
@test "off: billing restored" (service_line $bill_yml) = module-billing
@test "off: layer cf ref restored" (cat $layer_yml | string match -q '*cf:module-auth-LayerLambdaArn*'; echo $status) -eq 0
@test "off: no stray .ts_bak files left behind" (count $TS_TMP/modules/*/*.ts_bak $TS_TMP/services/*.ts_bak 2>/dev/null) -eq 0

# ===== full file content round-trips back to the pristine fixture =====
@test "auth yml round-trips to pristine fixture" (diff $auth_yml $here/fixtures/rename_modules/modules/auth/serverless.yml; echo $status) -eq 0
@test "layer yml round-trips to pristine fixture" (diff $layer_yml $here/fixtures/rename_modules/services/serverless-layers.yml; echo $status) -eq 0

# --- teardown ----------------------------------------------------------------
rm -rf $TS_TMP
