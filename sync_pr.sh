#!/bin/bash

# Synchronize the content of a PR to the markdown-pages folder to deploy a preview website.

# Usage: ./sync_pr.sh [BRANCH_NAME]

# BRANCH_NAME is optional and defaults to the current branch name.
# The branch name should follow the pattern r"preview(-cloud|-operator)?/pingcap/docs(-cn|-tidb-operator)?/[0-9]+".
# Examples:
# preview/pingcap/docs/1234: sync pingcap/docs/pull/1234 to markdown-pages/en/tidb/{PR_BASE_BRANCH}
# preview/pingcap/docs-cn/1234: sync pingcap/docs-cn/pull/1234 to markdown-pages/zh/tidb/{PR_BASE_BRANCH}
# preview-cloud/pingcap/docs/1234: sync pingcap/docs/pull/1234 to markdown-pages/en/tidbcloud/{PR_BASE_BRANCH}
# preview-operator/pingcap/docs-tidb-operator/1234: sync pingcap/docs-tidb-operator/pull/1234 to markdown-pages/en/tidb-in-kubernetes/{PR_BASE_BRANCH} and markdown-pages/zh/tidb-in-kubernetes/{PR_BASE_BRANCH}

# Prerequisites:
# 1. Install jq
# 2. Set the GITHUB_TOKEN environment variable

set -ex

check_prerequisites() {
  # Verify if jq is installed and GITHUB_TOKEN is set.
  which jq &>/dev/null || (echo "Error: jq is required but not installed. You can download and install jq from <https://stedolan.github.io/jq/download/>." && exit 1)

  set +x

  test -n "$GITHUB_TOKEN" || (echo "Error: GITHUB_TOKEN (repo scope) is required but not set." && exit 1)

  set -x
}

get_pr_base_branch() {
  # Get the base branch of a PR using GitHub API <https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#get-a-pull-request>
  set +x

  BASE_BRANCH=$(curl -fsSL -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/pulls/$PR_NUMBER" |
    jq -r '.base.ref')

  set -x

  # Ensure that BASE_BRANCH is not empty
  test -n "$BASE_BRANCH" || (echo "Error: Cannot get BASE_BRANCH." && exit 1)

}

get_destination_suffix() {
  # Determine the product name based on PREVIEW_PRODUCT.
  case "$PREVIEW_PRODUCT" in
  preview)
    DIR_SUFFIX="tidb/${BASE_BRANCH}"
    ;;
  preview-cloud)
    DIR_SUFFIX="tidbcloud/master"
    IS_CLOUD=true
    ;;
  preview-operator)
    DIR_SUFFIX="tidb-in-kubernetes/${BASE_BRANCH}"
    ;;
  *)
    echo "Error: Branch name must start with preview/, preview-cloud/, or preview-operator/."
    exit 1
    ;;
  esac
}

generate_sync_tasks() {
  # Define sync tasks for different repositories.
  case "$REPO_NAME" in
  docs)
    # Sync all modified or added files from the root dir to markdown-pages/en/.
    SYNC_TASKS=("./,en/")
    ;;
  docs-cn)
    # sync all modified or added files from the root dir to markdown-pages/zh/.
    SYNC_TASKS=("./,zh/")
    ;;
  docs-tidb-operator)
    # Task 1: sync all modified or added files from en/ to markdown-pages/en/.
    # Task 2: sync all modified or added files from zh/ to markdown-pages/zh/.
    SYNC_TASKS=("en/,en/" "zh/,zh/")
    ;;
  *)
    echo "Error: Invalid repo name. Only docs, docs-cn, and docs-tidb-operator are supported."
    exit 1
    ;;
  esac
}

clone_repo() {

  # Clone repo if it doesn't exist already.
  test -e "$REPO_DIR/.git" || git clone "https://github.com/$REPO_OWNER/$REPO_NAME.git" "$REPO_DIR"
  # --update-head-ok: By default git fetch refuses to update the head which corresponds to the current branch. This flag disables the check. This is purely for the internal use for git pull to communicate with git fetch, and unless you are implementing your own Porcelain you are not supposed to use it.
  # use --force to overwrite local branch when remote branch is force pushed.
  git -C "$REPO_DIR" fetch origin "$BASE_BRANCH" #<https://stackoverflow.com/questions/33152725/git-diff-gives-ambigious-argument-error>
  git -C "$REPO_DIR" fetch origin pull/"$PR_NUMBER"/head:PR-"$PR_NUMBER" --update-head-ok --force
  git -C "$REPO_DIR" checkout PR-"$PR_NUMBER"
}

process_cloud_toc() {
  DIR=$1
  mv "$DIR/TOC-tidb-cloud.md" "$DIR/TOC.md"
}

perform_sync_task() {
  generate_sync_tasks
  # Perform sync tasks.
  for TASK in "${SYNC_TASKS[@]}"; do

    SRC_DIR="$REPO_DIR/$(echo "$TASK" | cut -d',' -f1)"
    DEST_DIR="markdown-pages/$(echo "$TASK" | cut -d',' -f2)/$DIR_SUFFIX"
    mkdir -p "$DEST_DIR"
    # Only sync modified or added files.
    git -C "$SRC_DIR" diff --merge-base --name-only --diff-filter=AMR origin/"$BASE_BRANCH" --relative | tee /dev/fd/2 |
      rsync -av --files-from=- "$SRC_DIR" "$DEST_DIR"

    if [[ "$IS_CLOUD" && -f "$DEST_DIR/TOC-tidb-cloud.md" ]]; then
      process_cloud_toc "$DEST_DIR"
    fi

  done

}

commit_changes() {
  # Exit if TEST is set and not empty.
  test -n "$TEST" && echo "Test mode, exiting..." && exit 0
  # Handle untracked files.
  git add .
  # Commit changes, if any.
  git commit -m "$COMMIT_MESS" || echo "No changes to commit"
}

# Get the directory of this script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"

check_prerequisites

# If the branch name is not provided as an argument, use the current branch.
BRANCH_NAME=${1:-$(git branch --show-current)}

# Extract product, repo owner, repo name, and PR number from the branch name.
PREVIEW_PRODUCT=$(echo "$BRANCH_NAME" | cut -d'/' -f1)
REPO_OWNER=$(echo "$BRANCH_NAME" | cut -d'/' -f2)
REPO_NAME=$(echo "$BRANCH_NAME" | cut -d'/' -f3)
PR_NUMBER=$(echo "$BRANCH_NAME" | cut -d'/' -f4)
REPO_DIR="temp/$REPO_NAME"

get_pr_base_branch
get_destination_suffix
clone_repo
perform_sync_task

# Get the current commit SHA
CURRENT_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
COMMIT_MESS="Preview PR https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER and this preview is triggered from commit https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER/commits/$CURRENT_COMMIT"

commit_changes
