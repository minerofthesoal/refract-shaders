#!/usr/bin/env bash
# Packages Refract Shaders for manual upload to Modrinth/CurseForge/the
# in-game shaderpacks folder.
#
# Why this exists: Modrinth (and Iris/OptiFine's own shaderpacks folder)
# expect the zip to contain "shaders/" AT THE ROOT of the archive. If you
# instead zip up the checked-out repo folder itself - or use GitHub's
# green "Code -> Download ZIP" button, which wraps everything in a
# "refract-shaders-main/" folder - the zip ends up looking like
# "refract-shaders-main/shaders/..." instead of "shaders/...". Modrinth
# can't find a shaders directory sitting at the root of a zip like that,
# so it reports the pack as having no Iris/OptiFine shader folder even
# though the shaders are right there, just one level too deep.
#
# Run from the repo root: ./package.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -d "shaders" ]; then
  echo "error: run this from the repo root (no shaders/ directory found here)" >&2
  exit 1
fi

VERSION=$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' shaders/shaders.properties | head -1)
ZIP_NAME="refract-shaders-${VERSION:-dev}.zip"

rm -f "${ZIP_NAME}"
zip -r "${ZIP_NAME}" shaders CHANGELOG.md

echo
echo "Wrote ${ZIP_NAME}"
echo "shaders/ sits at the root of this zip - safe to upload as-is to Modrinth/CurseForge, or drop straight into .minecraft/shaderpacks/."
