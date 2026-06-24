# fishtape spec for download_ddb_table (functions/download_ddb_table.fish).
# Run: fish -c 'fishtape tests/download_ddb_table.fish' < /dev/null
#
# Real code under test: download_ddb_table + the real jq unmarshalling via
# ~/.config/fish/functions/ddb_unmarshall.jq (path is hardcoded in the function).
# Only the AWS side-effect is stubbed: a fake `aws` on PATH (tests/fixtures/
# download_ddb_table/bin) prints a canned marshalled DynamoDB scan response.
# Work happens in a fresh mktemp -d so the generated <table>.json never lands
# in the repo; it's removed in teardown.
#
# NOTE: the function hardcodes the jq script path to
#   ~/.config/fish/functions/ddb_unmarshall.jq
# That file exists here and is byte-identical to the repo's
# functions/ddb_unmarshall.jq, so the unmarshalling assertions run for real.
# A guard test below confirms the dependency; if it were missing the
# unmarshalling assertions would be meaningfully degraded.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)

source $repo/functions/download_ddb_table.fish

# --- stub only the external side-effect (aws) via a PATH shim ------------
set -gx PATH $here/fixtures/download_ddb_table/bin $PATH

# --- isolated working dir so <table>.json doesn't pollute the repo -------
set -g TS_TMP (mktemp -d)
cd $TS_TMP

# ===== dependency guard: hardcoded jq script must exist ==================
@test "ddb_unmarshall.jq dependency present" -f ~/.config/fish/functions/ddb_unmarshall.jq

# ===== run the function against the fake aws =============================
set -l out (download_ddb_table mytable)

# ===== output file is created ============================================
@test "mytable.json is created" -f $TS_TMP/mytable.json

# ===== printed message reports the correct document count ================
# fake aws emits Count: 2, which survives unmarshalling at the top level.
@test "reports correct document count" "$out" = "Got 2 documents from mytable table"

# ===== jq unmarshalling was actually applied =============================
# Raw scan had {"id": {"S": "abc-123"}}; after unmarshalling the type wrapper
# is gone and .Items[0].id is the bare string "abc-123".
@test "unmarshalled S wrapper -> bare string" (jq -r '.Items[0].id' $TS_TMP/mytable.json) = abc-123

# {"age": {"N": "42"}} -> bare number 42 (N becomes a JSON number, not a string).
@test "unmarshalled N wrapper -> bare number" (jq -r '.Items[0].age' $TS_TMP/mytable.json) = 42
@test "unmarshalled N is a number type" (jq -r '.Items[0].age | type' $TS_TMP/mytable.json) = number

# {"active": {"BOOL": false}} on item 2 -> bare boolean false.
@test "unmarshalled BOOL wrapper -> bare boolean" (jq -r '.Items[1].active' $TS_TMP/mytable.json) = false

# Negative check: no DDB type-wrapper keys remain anywhere in the file.
@test "no DDB type wrappers remain" (jq '[.. | objects | keys[] | select(. == "S" or . == "N" or . == "BOOL")] | length' $TS_TMP/mytable.json) -eq 0

# --- teardown ------------------------------------------------------------
cd $repo
rm -rf $TS_TMP
