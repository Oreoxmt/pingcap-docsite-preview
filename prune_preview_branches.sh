#!/usr/bin/env bash

set -e

check_prerequisites() {
  # Verify if jq is installed and GITHUB_TOKEN is set.
  which jq &>/dev/null || (echo "Error: jq is required but not installed. You can download and install jq from <https://stedolan.github.io/jq/download/>." && exit 1)

  test -n "$GITHUB_TOKEN" || (echo "Error: GITHUB_TOKEN (repo scope) is required but not set." && exit 1)
}

is_pr_merged() {
  # Verify if a PR is merged.
  local repo_owner="$1" repo_name="$2" pr_number="$3"
  local api_url="https://api.github.com/repos/${repo_owner}/${repo_name}/pulls/${pr_number}"
  local is_merged
  is_merged=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "$api_url" | jq -r '.merged_at')
  [[ -n "$is_merged" && "$is_merged" != "null" ]]
}

process_branch() {
  # If the branch starts with 'preview', it checks if the associated pull request is merged.
  # If it is merged, the branch is added to a list of branches to be pruned. Otherwise, the branch is skipped.
  local branch="$1"
  if [[ $branch == preview* ]]; then
    IFS='/' read -r _ repo_owner repo_name pr_number <<< "$branch"
    if is_pr_merged "$repo_owner" "$repo_name" "$pr_number"; then
      echo "$branch: This preview PR is merged, will be pruned."
      PRUNE_BRANCHES+=("$branch")
    else
      echo "$branch: This preview PR is not merged, skipping."
    fi
  fi
}

delete_branch() {
  # Delete a branch based on the specified mode (local or remote).
  local branch="$1" mode="$2"
  echo "Deleting branch: $branch"
  case "$mode" in
    local)  git branch -D "$branch" ;;
    remote) git push origin --delete "$branch" ;;
    *)      echo "No action specified for branch deletion." ;;
  esac
}

# Get the directory of this script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"

check_prerequisites

# Check if arguments are passed.
if [ "$#" -eq 0 ]; then
  set +o posix
  mapfile -t BRANCHES < <(git branch --list | sed 's/^[*[:space:]]*//')
else
  BRANCHES=("$@")
fi

PRUNE_BRANCHES=()

for branch in "${BRANCHES[@]}"; do
  process_branch "$branch"
done

# Delete branches in the prune list.
for branch in "${PRUNE_BRANCHES[@]}"; do
  delete_branch "$branch" "${DELETE_BRANCHES:-}"
done
