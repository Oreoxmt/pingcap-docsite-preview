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

normalize_preview_target() {
  TARGET_BRANCH="$BASE_BRANCH"
  TARGET_LOCALE=""

  if [[ "$BASE_BRANCH" =~ ^i18n-(.+)-(master|release-.+)$ ]]; then
    TARGET_LOCALE="${BASH_REMATCH[1]}"
    TARGET_BRANCH="${BASH_REMATCH[2]}"
  fi
}

get_destination_suffix() {
  # Determine the product name based on PREVIEW_PRODUCT.
  case "$PREVIEW_PRODUCT" in
  preview)
    DIR_SUFFIX="tidb/${TARGET_BRANCH}"
    ;;
  preview-cloud)
    DIR_SUFFIX="tidbcloud/master"
    IS_CLOUD=true
    ;;
  preview-operator)
    DIR_SUFFIX="tidb-in-kubernetes/${TARGET_BRANCH}"
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
    # Sync all modified or added files from the root dir to markdown-pages/{locale}/.
    SYNC_TASKS=("./,${TARGET_LOCALE:-en}/")
    ;;
  docs-cn)
    # sync all modified or added files from the root dir to markdown-pages/{locale}/.
    SYNC_TASKS=("./,${TARGET_LOCALE:-zh}/")
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

remove_copyable() {
  # Remove copyable strings ({{< copyable "..." >}}\n) from Markdown files.
  $FIND . -name '*.md' | while IFS= read -r FILE; do
    $SED -i '/{{< copyable ".*" >}}/{N;d}' "$FILE"
  done
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

get_preview_page_title() {
  FILE=$1
  TITLE=""

  if [[ -f "$FILE" ]]; then
    TITLE=$(awk '
      BEGIN { in_frontmatter = 0 }
      NR == 1 && $0 == "---" { in_frontmatter = 1; next }
      in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
      in_frontmatter && $0 ~ /^title:[[:space:]]*/ {
        sub(/^title:[[:space:]]*/, "")
        gsub(/^["'\'']|["'\'']$/, "")
        print
        exit
      }
      !in_frontmatter && $0 ~ /^#[[:space:]]+/ {
        sub(/^#[[:space:]]+/, "")
        print
        exit
      }
    ' "$FILE")
  fi

  if [[ -n "$TITLE" ]]; then
    printf "%s" "$TITLE"
  else
    basename "$FILE" .md
  fi
}

get_preview_version_slug() {
  PRODUCT=$1
  BRANCH=$2

  case "$PRODUCT" in
  tidb)
    if [[ "$BRANCH" == "master" ]]; then
      printf "dev"
    elif [[ "$BRANCH" == "$(jq -r '.docs.tidb.stable' docs.json)" ]]; then
      printf "stable"
    else
      printf "%s" "${BRANCH/release-/v}"
    fi
    ;;
  tidb-in-kubernetes)
    if [[ "$BRANCH" == "main" ]]; then
      printf "dev"
    elif [[ "$BRANCH" == "$(jq -r '.docs["tidb-in-kubernetes"].stable' docs.json)" ]]; then
      printf "stable"
    else
      printf "%s" "${BRANCH/release-/v}"
    fi
    ;;
  esac
}

get_preview_doc_url() {
  DEST_DIR=$1
  FILE=$2
  REL_DEST=$(printf "%s" "${DEST_DIR#markdown-pages/}" | tr -s '/')
  LOCALE=$(echo "$REL_DEST" | cut -d'/' -f1)
  PRODUCT=$(echo "$REL_DEST" | cut -d'/' -f2)
  BRANCH=$(echo "$REL_DEST" | cut -d'/' -f3)
  NAME=$(basename "$FILE" .md)
  FIRST_DIR=${FILE%%/*}
  LANG_PREFIX=""

  [[ "$LOCALE" != "en" ]] && LANG_PREFIX="/$LOCALE"

  case "$PRODUCT" in
  tidb)
    if [[ "$BRANCH" == "$(jq -r '.docs.tidb.stable' docs.json)" ]]; then
      case "$FIRST_DIR" in
      develop)
        printf "%s/developer/%s" "$LANG_PREFIX" "$NAME"
        return
        ;;
      ai | best-practices | api)
        printf "%s/%s/%s" "$LANG_PREFIX" "$FIRST_DIR" "$NAME"
        return
        ;;
      esac
    fi
    printf "%s/tidb/%s/%s" "$LANG_PREFIX" "$(get_preview_version_slug tidb "$BRANCH")" "$NAME"
    ;;
  tidbcloud)
    printf "%s/tidbcloud/%s" "$LANG_PREFIX" "$NAME"
    ;;
  tidb-in-kubernetes)
    printf "%s/tidb-in-kubernetes/%s/%s" "$LANG_PREFIX" "$(get_preview_version_slug tidb-in-kubernetes "$BRANCH")" "$NAME"
    ;;
  *)
    printf "%s/%s/%s" "$LANG_PREFIX" "$PRODUCT" "$NAME"
    ;;
  esac
}

escape_html() {
  printf "%s" "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&#39;/g"
}

generate_preview_page() {
  DEST_DIR=$1
  SRC_DIR=$2
  CHANGED_FILES=$3
  PREVIEW_FILE="preview.md"
  SOURCE_PATH="${SRC_DIR#"$REPO_DIR"/}"
  REL_DEST=$(printf "%s" "${DEST_DIR#markdown-pages/}" | tr -s '/')
  TARGET_LOCALE=$(echo "$REL_DEST" | cut -d'/' -f1)
  TARGET_PRODUCT=$(echo "$REL_DEST" | cut -d'/' -f2)
  TARGET_BRANCH=$(echo "$REL_DEST" | cut -d'/' -f3)
  TARGET_VERSION="$TARGET_BRANCH"
  if [[ "$TARGET_PRODUCT" == "tidb" || "$TARGET_PRODUCT" == "tidb-in-kubernetes" ]]; then
    TARGET_VERSION=$(get_preview_version_slug "$TARGET_PRODUCT" "$TARGET_BRANCH")
  fi
  SECTION_KEY=$(printf "%s-%s-%s-%s-%s-%s" "$REPO_OWNER" "$REPO_NAME" "$PR_NUMBER" "$TARGET_LOCALE" "$TARGET_PRODUCT" "$TARGET_BRANCH" | tr -c '[:alnum:]_-' '-')
  SECTION_START="<!-- DOCSITE_PREVIEW_GROUP_${SECTION_KEY}_START -->"
  SECTION_END="<!-- DOCSITE_PREVIEW_GROUP_${SECTION_KEY}_END -->"
  DOC_ROWS=""
  SUPPORT_ROWS=""
  OTHER_ROWS=""

  [[ "$SOURCE_PATH" == "./" ]] && SOURCE_PATH="."

  while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    case "$FILE" in
    *.md)
      BASENAME=$(basename "$FILE")
      if [[ "$BASENAME" == TOC*.md || "$BASENAME" == _*.md ]]; then
        SUPPORT_ROWS+="<tr><td><code>$(escape_html "$FILE")</code></td></tr>"$'\n'
      else
        TITLE=$(get_preview_page_title "$DEST_DIR/$FILE")
        URL=$(get_preview_doc_url "$DEST_DIR" "$FILE")
        DOC_ROWS+="<tr><td><a href=\"$(escape_html "$URL")\">$(escape_html "$TITLE")</a></td><td><code>$(escape_html "$FILE")</code></td></tr>"$'\n'
      fi
      ;;
    *)
      OTHER_ROWS+="<tr><td><code>$(escape_html "$FILE")</code></td></tr>"$'\n'
      ;;
    esac
  done <<<"$CHANGED_FILES"

  TMP_GROUP=$(mktemp)
  cat >"$TMP_GROUP" <<EOF
$SECTION_START

<details open>
<summary><strong><a href="https://github.com/${REPO_OWNER}/${REPO_NAME}/pull/${PR_NUMBER}">$(escape_html "${REPO_OWNER}/${REPO_NAME}#${PR_NUMBER}")</a></strong> / $(escape_html "$TARGET_LOCALE") / $(escape_html "$TARGET_PRODUCT") / $(escape_html "$TARGET_VERSION")</summary>

<table class="meta-table">
<tbody>
<tr><th>Language</th><td><code>$(escape_html "$TARGET_LOCALE")</code></td></tr>
<tr><th>Product</th><td><code>$(escape_html "$TARGET_PRODUCT")</code></td></tr>
<tr><th>Version</th><td><code>$(escape_html "$TARGET_VERSION")</code></td></tr>
<tr><th>Base branch</th><td><code>$(escape_html "$BASE_BRANCH")</code></td></tr>
<tr><th>Source path</th><td><code>$(escape_html "$SOURCE_PATH")</code></td></tr>
</tbody>
</table>
EOF

  if [[ -n "$DOC_ROWS" ]]; then
    {
      printf "\n<h2>Documentation pages</h2>\n"
      printf "<table>\n<thead><tr><th>Page</th><th>File</th></tr></thead>\n<tbody>\n%s</tbody>\n</table>\n" "$DOC_ROWS"
    } >>"$TMP_GROUP"
  else
    printf "\n<p>No changed documentation pages were detected.</p>\n" >>"$TMP_GROUP"
  fi

  if [[ -n "$SUPPORT_ROWS" ]]; then
    {
      printf "\n<h2>Navigation and index files</h2>\n"
      printf "<table>\n<thead><tr><th>File</th></tr></thead>\n<tbody>\n%s</tbody>\n</table>\n" "$SUPPORT_ROWS"
    } >>"$TMP_GROUP"
  fi

  if [[ -n "$OTHER_ROWS" ]]; then
    {
      printf "\n<h2>Other changed files</h2>\n"
      printf "<table>\n<thead><tr><th>File</th></tr></thead>\n<tbody>\n%s</tbody>\n</table>\n" "$OTHER_ROWS"
    } >>"$TMP_GROUP"
  fi

  printf "\n</details>\n\n%s\n" "$SECTION_END" >>"$TMP_GROUP"

  if [[ ! -f "$PREVIEW_FILE" ]]; then
    cat >"$PREVIEW_FILE" <<'EOF'
---
title: Preview links
hide_sidebar: true
hide_commit: true
hide_leftNav: true
summary: Documentation preview links for synced PRs, grouped by PR, language, product, and version.
---

<DocHomeContainer title="Preview links" subTitle="Review documentation preview links for synced PRs, grouped by PR, language, product, and version.">

<DocHomeSection label="Preview links" anchor="preview-links" id="preview-links">

Preview links generated by `pingcap-docsite-preview`.

<!-- DOCSITE_PREVIEW_GROUPS_START -->
<!-- DOCSITE_PREVIEW_GROUPS_END -->

</DocHomeSection>

</DocHomeContainer>
EOF
  fi

  awk -v group_file="$TMP_GROUP" -v groups_end="<!-- DOCSITE_PREVIEW_GROUPS_END -->" -v section_start="$SECTION_START" -v section_end="$SECTION_END" '
    BEGIN {
      while ((getline line < group_file) > 0) group = group line ORS
      close(group_file)
      skipping = 0
    }
    $0 == section_start {
      skipping = 1
      next
    }
    $0 == section_end {
      skipping = 0
      next
    }
    $0 == groups_end {
      printf "%s", group
      print
      next
    }
    !skipping { print }
  ' "$PREVIEW_FILE" >"$PREVIEW_FILE.tmp"

  mv "$PREVIEW_FILE.tmp" "$PREVIEW_FILE"
  rm -f "$TMP_GROUP"
}

restore_preview_page_from_head() {
  # Preserve preview groups across multi-PR sync runs if an earlier step leaves
  # the generated preview index absent from the working tree.
  if [[ ! -f "preview.md" ]] && git cat-file -e HEAD:preview.md 2>/dev/null; then
    git show HEAD:preview.md >preview.md
  fi
}

perform_sync_task() {
  generate_sync_tasks
  restore_preview_page_from_head

  # Set the target branch and folders of TOC namespace per product.
  # These folders are served from a fixed target branch; when TARGET_BRANCH differs, they must also be synced there for the preview to reflect changes at their canonical URLs.
  #  - tidb:               docs.tidb.stable from docs.json (e.g. release-8.5)
  #  - tidb-in-kubernetes: main
  #  - tidbcloud:          master (already the default target, no extra sync needed)
  case "$PREVIEW_PRODUCT" in
  preview)
    TOC_TARGET_BRANCH=$(jq -r '.docs.tidb.stable' docs.json)
    TOC_FOLDERS=("ai" "develop" "best-practices" "api" "releases")
    ;;
  preview-operator)
    TOC_TARGET_BRANCH="main"
    TOC_FOLDERS=("releases")
    ;;
  *)
    TOC_TARGET_BRANCH=""
    TOC_FOLDERS=()
    ;;
  esac

  # Perform sync tasks.
  for TASK in "${SYNC_TASKS[@]}"; do

    SRC_DIR="$REPO_DIR/$(echo "$TASK" | cut -d',' -f1)"
    DEST_DIR="markdown-pages/$(echo "$TASK" | cut -d',' -f2)/$DIR_SUFFIX"
    mkdir -p "$DEST_DIR"

    # Ensure variables.json is always available for processing.
    if [[ -f "$SRC_DIR/variables.json" ]]; then
      rsync -av "$SRC_DIR/variables.json" "$DEST_DIR"
    fi

    # Only sync modified or added files.
    CHANGED_FILES=$(git -C "$SRC_DIR" diff --merge-base --name-only --diff-filter=AMR origin/"$BASE_BRANCH" --relative)
    echo "$CHANGED_FILES" | tee /dev/fd/2 |
      rsync -av --files-from=- "$SRC_DIR" "$DEST_DIR"

    restore_preview_page_from_head

    # Get the current commit SHA.
    CURRENT_COMMIT=$(git -C "$REPO_DIR" rev-parse HEAD)
    commit_changes "Sync files for PR https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER (commit: https://github.com/$REPO_OWNER/$REPO_NAME/pull/$PR_NUMBER/commits/$CURRENT_COMMIT)"

    # Replace variables in Markdown files with values from variables.json.
    if [[ -f "$DEST_DIR/variables.json" ]]; then
      ./scripts/replace_variables.py "$DEST_DIR" "$DEST_DIR/variables.json"
    fi
    # Remove copyable strings.
    (cd "$DEST_DIR" && remove_copyable)

    if [[ "$IS_CLOUD" && -f "$DEST_DIR/TOC-tidb-cloud.md" ]]; then
      process_cloud_toc "$DEST_DIR"
    fi

    generate_preview_page "$DEST_DIR" "$SRC_DIR" "$CHANGED_FILES"

    commit_changes "Post-process docs and update preview links"

    # Sync TOC namespace folders to the target branch path when TARGET_BRANCH differs.
    if [[ -n "$TOC_TARGET_BRANCH" && "$TARGET_BRANCH" != "$TOC_TARGET_BRANCH" ]]; then
      TOC_TARGET_DIR="$(dirname "$DEST_DIR")/$TOC_TARGET_BRANCH"

      if [[ "$TOC_TARGET_DIR" == "$DEST_DIR" ]]; then
        echo "Warning: TOC_TARGET_DIR equals DEST_DIR ($DEST_DIR), skipping TOC namespace sync for task $TASK."
      else
        mkdir -p "$TOC_TARGET_DIR"

        if [[ -f "$SRC_DIR/variables.json" ]]; then
          rsync -av "$SRC_DIR/variables.json" "$TOC_TARGET_DIR/"
        fi

        # Sync changed TOC*.md files.
        CHANGED_TOCS=$(echo "$CHANGED_FILES" | grep "^TOC.*\.md$" || true)
        if [[ -n "$CHANGED_TOCS" ]]; then
          echo "$CHANGED_TOCS" | rsync -av --files-from=- "$SRC_DIR" "$TOC_TARGET_DIR/"
        fi

        # Sync changed files in each TOC namespace folder.
        TOC_FOLDER_SYNCED=false
        for FOLDER in "${TOC_FOLDERS[@]}"; do
          CHANGED=$(echo "$CHANGED_FILES" | grep "^$FOLDER/" || true)
          if [[ -n "$CHANGED" ]]; then
            echo "$CHANGED" | sed "s|^$FOLDER/||" |
              rsync -av --files-from=- "$SRC_DIR/$FOLDER/" "$TOC_TARGET_DIR/$FOLDER/"
            TOC_FOLDER_SYNCED=true
          fi
        done

        if [[ "$TOC_FOLDER_SYNCED" == true ]]; then
          # Use the target branch's variables.json, which might differ from BASE_BRANCH.
          if [[ -f "$TOC_TARGET_DIR/variables.json" ]]; then
            ./scripts/replace_variables.py "$TOC_TARGET_DIR" "$TOC_TARGET_DIR/variables.json"
          fi
          (cd "$TOC_TARGET_DIR" && remove_copyable)
          commit_changes "Sync TOC namespace folders from ${BASE_BRANCH} to ${TOC_TARGET_BRANCH} for preview (task: ${TASK})"
        fi
      fi
    fi

  done

}

commit_changes() {
  mess=$1
  # Return early if TEST is set and not empty.
  test -n "$TEST" && echo "Test mode, returning..." && return 0
  # Handle untracked files.
  git add .
  # Commit changes, if any.
  git commit -m "$mess" || echo "No changes to commit"
}

# Select appropriate versions of find and sed depending on the operating system.
FIND=$(which gfind || which find)
SED=$(which gsed || which sed)

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
normalize_preview_target
get_destination_suffix
clone_repo
perform_sync_task

commit_changes "Finalize preview sync"
