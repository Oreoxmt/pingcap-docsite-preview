#!/bin/bash

# Synchronize the content of multiple PRs to the markdown-pages folder to deploy a preview website.

# Usage: ./sync_mult_prs.sh

set -ex

# Get the directory of this script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"


# Define the PRs to sync.
# The PRs will be synced in the order of the following statements.
./sync_pr.sh preview/pingcap/docs-cn/18556
./sync_pr.sh preview/pingcap/docs-cn/18697
./sync_pr.sh preview/pingcap/docs/18829
./sync_pr.sh preview/pingcap/docs/18991

# Synchronize the content from master to release-x.y directories.
rsync -av markdown-pages/zh/tidb/master/ markdown-pages/zh/tidb/release-8.4
rsync -av markdown-pages/en/tidb/master/ markdown-pages/en/tidb/release-8.4

commit_changes() {
  # Exit if TEST is set and not empty.
  test -n "$TEST" && echo "Test mode, exiting..." && exit 0
  # Handle untracked files.
  git add .
  # Commit changes, if any.
  git commit -m "Update the release-8.4 directory" || echo "No changes to commit"
}

commit_changes
