#!/bin/bash

set -e

# The repository to sync from
REPO_URL="https://github.com/pingcap/docs-staging"
CLONE_DIR="temp/docs-staging"

# Files to sync from the repository
SYNC_FILES=("TOC.md" "_index.md" "_docHome.md")
SYNC_JSON_FILE="docs.json"

# Get the current script's directory and change to it
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR"

# Verify if CLONE_DIR is a git repository
if [ ! -e "$CLONE_DIR/.git" ]; then
  if [ -d "$CLONE_DIR" ]; then
    # If CLONE_DIR is not a git repository, delete it
    rm -rf "$CLONE_DIR"
  fi
  # Shallow clone the repository
  git clone --depth 1 "$REPO_URL" "$CLONE_DIR"

else
  # If the directory already exists, switch to main branch and pull the latest changes
  git -C "$CLONE_DIR" checkout main
  git -C "$CLONE_DIR" pull origin main
fi

# Set source and destination directories for rsync
SRC="$CLONE_DIR/markdown-pages/"
DEST="markdown-pages/"

# Create an array of --include options for rsync
INCLUDES=('--include=*/')
for file in "${SYNC_FILES[@]}"; do
  INCLUDES+=("--include=$file")
done

# Synchronize SRC and DEST
rsync -av --checksum "${INCLUDES[@]}" --exclude='*' "$SRC" "$DEST"

# Copy SYNC_JSON_FILE from CLONE_DIR to the current directory
cp "$CLONE_DIR/$SYNC_JSON_FILE" "./$SYNC_JSON_FILE"

## Commit changes with the commit SHA from the cloned repository
CURRENT_SHA=$(git -C "$CLONE_DIR" rev-parse HEAD)
git add . || true
git commit -m "Sync the scaffold from $REPO_URL/commit/$CURRENT_SHA" || echo "No changes detected"
