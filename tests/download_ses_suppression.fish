# fishtape spec for download_ses_suppression (functions/download_ses_suppression.fish).
# Run: fish -c 'fishtape tests/download_ses_suppression.fish' < /dev/null
#
# Real code under test: the pagination loop (follow NextToken until null) and the
# `jq -s` merge/sort. The only external stubbed is `aws`, via a fake executable on
# PATH (tests/fixtures/download_ses_suppression/bin/aws). jq + mktemp are real.
#
# The fake aws returns two pages keyed off the presence of --next-token:
#   page 1 -> NextToken "PAGE2TOKEN" + 2 summaries
#   page 2 -> NextToken null         + 2 summaries
# so the function must make exactly one follow-up call to see all 4 items.
#
# NOTE on the real merge: `jq -s '{...: .[].SuppressedDestinationSummaries | ...}'`
# evaluates the object constructor once per slurped page, so the code emits ONE
# JSON object PER PAGE, each sorted by LastUpdateTime descending WITHIN that page;
# the pages are not concatenated into a single array. We assert the code's real
# behaviour, not an idealised single merged array.

set -l here (path dirname (status filename))
set -l repo (path dirname $here)
set -l fix $here/fixtures/download_ses_suppression

source $repo/functions/download_ses_suppression.fish

# put the fake `aws` first on PATH; jq/mktemp stay real
set -gx PATH $fix/bin $PATH

# run the real function once, capture stdout
set -l out (download_ses_suppression)

# flatten the whole emitted stream into the ordered list of email addresses
set -l emails (printf '%s\n' $out | jq -s '[.[].SuppressedDestinationSummaries[].EmailAddress]' | jq -r '.[]')

# ---- pagination: both pages' items are present --------------------------
@test "page 1 item present (pagination started)" (contains p1-new@example.com $emails; echo $status) -eq 0
@test "page 1 second item present" (contains p1-old@example.com $emails; echo $status) -eq 0
@test "page 2 item present (NextToken was followed)" (contains p2-newest@example.com $emails; echo $status) -eq 0
@test "page 2 second item present" (contains p2-mid@example.com $emails; echo $status) -eq 0
@test "all 4 summaries across both pages emitted" (count $emails) -eq 4

# ---- output shape (per the jq in the code) ------------------------------
# two slurped pages -> two emitted objects, each with a SuppressedDestinationSummaries array
@test "emits one object per page (2 objects)" (printf '%s\n' $out | jq -s 'length') -eq 2
@test "each emitted object keyed by SuppressedDestinationSummaries" (printf '%s\n' $out | jq -s 'all(.[]; has("SuppressedDestinationSummaries"))') = true

# ---- sort: LastUpdateTime descending within each page -------------------
# page 1: 2024-03-15 (p1-new) must precede 2024-01-10 (p1-old)
@test "page 1 sorted desc by LastUpdateTime (new before old)" "$emails[1]" = p1-new@example.com
@test "page 1 older item second" "$emails[2]" = p1-old@example.com
# page 2: 2024-05-20 (p2-newest) must precede 2024-02-01 (p2-mid)
@test "page 2 sorted desc by LastUpdateTime (newest before mid)" "$emails[3]" = p2-newest@example.com
@test "page 2 older item second" "$emails[4]" = p2-mid@example.com

# full emitted email order across the stream is deterministic
@test "deterministic emitted order across both pages" "$emails" = "p1-new@example.com p1-old@example.com p2-newest@example.com p2-mid@example.com"
