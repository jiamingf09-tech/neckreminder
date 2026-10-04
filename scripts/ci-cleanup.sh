#!/usr/bin/env bash
# CI helper: keeps the Actions page tidy without ever deleting the newest build.
#
# * Artifacts: the newest one per branch survives (plus this run's own), everything older
#   is deleted. "Newest" is decided across all runs, so two runs finishing at the same time
#   can't delete each other's artifacts.
# * Runs: the newest $KEEP_RUNS completed runs survive, plus any run that owns a surviving
#   artifact (deleting a run would delete its artifact too). Runs still in progress are
#   never touched.
#
# Env: REPO (owner/name), RUN_ID (current run), GH_TOKEN, KEEP_RUNS (default 5).
set -euo pipefail
KEEP_RUNS="${KEEP_RUNS:-5}"

# id <TAB> run id <TAB> branch <TAB> created_at, newest first
artifacts="$(gh api --paginate "repos/$REPO/actions/artifacts?per_page=100" \
  --jq '.artifacts[] | select(.expired == false) | [.id, .workflow_run.id, (.workflow_run.head_branch // "-"), .created_at] | @tsv' \
  | sort -t $'\t' -k4,4r)"

keep_artifacts="$(printf '%s\n' "$artifacts" | awk -F '\t' 'NF && !seen[$3]++ { print $1 }')"
keep_runs="$( (printf '%s\n' "$artifacts" | awk -F '\t' -v keep="$keep_artifacts" '
    BEGIN { n = split(keep, k, "\n"); for (i = 1; i <= n; i++) K[k[i]] = 1 }
    NF && ($1 in K) { print $2 }'; echo "$RUN_ID") | sort -u)"

echo "Keeping artifacts: $(echo $keep_artifacts)"
while IFS=$'\t' read -r id run _branch _created; do
  [ -n "$id" ] || continue
  if ! grep -qx "$id" <<<"$keep_artifacts" && [ "$run" != "$RUN_ID" ]; then
    gh api -X DELETE "repos/$REPO/actions/artifacts/$id" && echo "deleted artifact $id (run $run)"
  fi
done <<<"$artifacts"

gh api --paginate "repos/$REPO/actions/runs?status=completed&per_page=100" --jq '.workflow_runs[].id' |
  tail -n +"$((KEEP_RUNS + 1))" |
  while read -r id; do
    if ! grep -qx "$id" <<<"$keep_runs"; then
      gh api -X DELETE "repos/$REPO/actions/runs/$id" && echo "deleted run $id"
    fi
  done
