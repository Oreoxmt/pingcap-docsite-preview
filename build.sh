#!/bin/bash

set -e

# Get the directory of this script.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "$SCRIPT_DIR"

# Select appropriate versions of find and sed depending on the operating system.
FIND=$(which gfind || which find)
SED=$(which gsed || which sed)

replace_image_path() {
  # Update image paths in Markdown files.
  ( cd markdown-pages
    $FIND . -maxdepth 3 -mindepth 3 | while IFS= read -r DIR; do
      DIR="${DIR#./}"
      PREFIX="$(dirname "$DIR")"
      $FIND "$DIR" -name '*.md' | while IFS= read -r FILE; do
        $SED -r -i "s~]\(/media(/$PREFIX)?~](/media/$PREFIX~g" "$FILE"
      done
    done
  )
}

move_images() {
  # Move all image files to the target directory.
  ( cd markdown-pages
    $FIND . -maxdepth 3 -mindepth 3 | while IFS= read -r DIR; do
      PREFIX="$(dirname "$DIR")"
      # Check if the media directory exists.
      if [ -d "$PREFIX/master/media" ]; then
        # Create the target directory.
        mkdir -p "../website-docs/public/media/$PREFIX"
        # Copy all image files to the target directory.
        cp -r "$PREFIX/master/media/." "../website-docs/public/media/$PREFIX"
      fi
    done
  )
}

copy_preview_to_mdx_source() {
  if [ -f "preview.md" ]; then
    DEST="markdown-pages/en/tidb/master/_preview.md"
    mkdir -p "$(dirname "$DEST")"
    cp preview.md "$DEST"
  fi
}

patch_create_doc_home_preview() {
  MARKER="DOCSITE_PREVIEW_DOC_HOME"
  FILE="website-docs/gatsby/create-pages/create-doc-home.ts"

  grep -q "$MARKER" "$FILE" && return 0

  PATCH=$(mktemp)
  cat >"$PATCH" <<'EOF'
  // DOCSITE_PREVIEW_DOC_HOME: build /preview/ using the same DocTemplate.
  const previewQueryStr = `
  {
    allMdx(
      filter: {
        fileAbsolutePath: { regex: "/_preview.md$/" }
        frontmatter: { draft: { ne: true } }
      }
    ) {
      nodes {
        id
        frontmatter {
          aliases
        }
        slug
      }
    }
  }
`;
  const previewDocs = await graphql<PageQueryData>(previewQueryStr);
  if (previewDocs.errors) {
    sig.error(previewDocs.errors);
  }

  const previewNodes = (previewDocs.data?.allMdx.nodes ?? []).map((node) => {
    const { config, name, filePath } = generateConfig(node.slug);
    return { ...node, pathConfig: config, name, filePath };
  });

  previewNodes.forEach((node) => {
    const { id, name, pathConfig, filePath } = node;
    const previewPath = "/preview/";
    const namespace = TOCNamespace.Home;
    const namespaceSlug = TOCNamespaceSlugMap[namespace];
    const navUrl = generateNavTOCPath(pathConfig, namespaceSlug);
    const starterNavUrl = generateNavTOCPath(pathConfig, "tidb-cloud-starter");
    const essentialNavUrl = generateNavTOCPath(
      pathConfig,
      "tidb-cloud-essential"
    );
    const premiumNavUrl = generateNavTOCPath(pathConfig, "tidb-cloud-premium");

    createPage({
      path: previewPath,
      component: template,
      context: {
        id,
        name,
        pathConfig,
        filePath,
        navUrl,
        starterNavUrl,
        essentialNavUrl,
        premiumNavUrl,
        pageUrl: previewPath,
        availIn: {
          locale: [Locale.en],
          version: [],
        },
        buildType: (process.env.WEBSITE_BUILD_TYPE ??
          DEFAULT_BUILD_TYPE) as BuildType,
        feature: {
          banner: true,
          feedback: false,
          globalHome: true,
        },
        namespace,
      },
    });
  });
EOF

  awk -v patch_file="$PATCH" '
    /^};$/ && !patched {
      while ((getline line < patch_file) > 0) print line
      close(patch_file)
      patched = 1
    }
    { print }
  ' "$FILE" >"$FILE.tmp"

  mv "$FILE.tmp" "$FILE"
  rm -f "$PATCH"
}

patch_gatsby_config_build_all() {
  MARKER="DOCSITE_PREVIEW_BUILD_ALL"
  FILE="website-docs/gatsby-config.js"

  grep -q "$MARKER" "$FILE" && return 0

  awk '
    /^const isDevelopment = process\.env\.NODE_ENV === "development";$/ {
      print "// DOCSITE_PREVIEW_BUILD_ALL: include all markdown pages in local preview dev builds."
      print "const isDevelopment ="
      print "  process.env.NODE_ENV === \"development\" &&"
      print "  process.env.DOCSITE_PREVIEW_BUILD_ALL !== \"1\";"
      next
    }
    { print }
  ' "$FILE" >"$FILE.tmp"

  mv "$FILE.tmp" "$FILE"
}

# The default command is build, which builds the website for production.
CMD=build

# If the argument is develop or dev, change the command to start, which builds the website for development.
if [ "$1" == "develop" ] || [ "$1" == "dev" ]; then
  CMD=start
fi

if [ ! -e website-docs/.git ]; then
  if [ -d "website-docs" ]; then
    rm -rf website-docs
  fi
  # Clone the pingcap/website-docs repository.
  git clone --single-branch --branch master https://github.com/pingcap/website-docs
fi

# Create a symlink to markdown-pages in website-docs/docs.
if [ ! -e website-docs/docs/markdown-pages ]; then
  ln -s ../../markdown-pages website-docs/docs/markdown-pages
fi

# Copy docs.json and tooltip-terms.json to website-docs/docs.
cp docs.json website-docs/docs/docs.json
[ -f tooltip-terms.json ] && cp tooltip-terms.json website-docs/docs/tooltip-terms.json
copy_preview_to_mdx_source
patch_create_doc_home_preview
patch_gatsby_config_build_all

# Run the start command for development environment. <https://www.gatsbyjs.com/docs/reference/gatsby-cli/#develop>
if [ "$CMD" == "start" ]; then
  mkdir -p website-docs/.cache
  (cd website-docs && pnpm install --frozen-lockfile && DOCSITE_PREVIEW_BUILD_ALL="${DOCSITE_PREVIEW_BUILD_ALL:-1}" pnpm start)
fi

# Run the build command for production environment. <https://www.gatsbyjs.com/docs/reference/gatsby-cli/#build>
if [ "$CMD" == "build" ]; then
  replace_image_path
  (cd website-docs && pnpm install --frozen-lockfile && pnpm build)
  move_images
fi
