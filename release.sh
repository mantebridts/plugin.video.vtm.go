#!/usr/bin/env bash
# release.sh - build this add-on under its own id and publish it to the kodi-repo catalog.
# Usage: ./release.sh 1.0.1
set -euo pipefail

VERSION="${1:?Usage: ./release.sh <version>  (e.g. 1.0.1)}"
OLD_ID="plugin.video.vtm.go"           # the makers' add-on id
NEW_ID="plugin.video.vtm.go.htpc"      # our own add-on id
NEW_NAME="VTM GO htpc"                 # name shown in Kodi
KEEP="add-ons/"                        # don't rename after this (links to the makers' GitHub)
SRC="$(cd "$(dirname "$0")" && pwd)"   # this repository
CATALOG="$SRC/../kodi-repo"            # the catalog repository next to it
BUILD="$(mktemp -d)"; trap 'rm -rf "$BUILD"' EXIT
ZIP="$CATALOG/zips/$NEW_ID/$NEW_ID-$VERSION.zip"
step() { printf '\n==> %s\n' "$*"; }

step "1. Checks"
[ -d "$CATALOG/.git" ] || { echo "Catalog not found: $CATALOG"; exit 1; }
git -C "$SRC" diff --quiet HEAD || { echo "Uncommitted changes in source - commit first"; exit 1; }
[ ! -e "$ZIP" ] || { echo "Version $VERSION already exists"; exit 1; }
echo "Source: $(git -C "$SRC" rev-parse --abbrev-ref HEAD) @ $(git -C "$SRC" rev-parse --short HEAD)"

step "2. Copy source (without git, tests, docs)"
rsync -a --exclude .git --exclude .github --exclude tests --exclude README.md \
  --exclude .gitignore --exclude release.sh "$SRC/" "$BUILD/$NEW_ID/"

step "3. Rename $OLD_ID -> $NEW_ID (GitHub links kept)"
grep -rlIF "$OLD_ID" "$BUILD/$NEW_ID" | OLD="$OLD_ID" NEW="$NEW_ID" KEEP="$KEEP" \
  xargs perl -pi -e 's/(?<!\Q$ENV{KEEP}\E)\Q$ENV{OLD}\E/$ENV{NEW}/g'
# Search from inside the build dir: the full path itself contains $NEW_ID and would hide every hit.
LEFT="$(cd "$BUILD/$NEW_ID" && grep -rlIF "$OLD_ID" . | OLD="$OLD_ID" NEW="$NEW_ID" KEEP="$KEEP" \
  xargs perl -ne '$l = $_; $l =~ s/\Q$ENV{NEW}\E//g; $l =~ s/\Q$ENV{KEEP}$ENV{OLD}\E//g;
    print "  $ARGV:$.: $_" if index($l, $ENV{OLD}) >= 0; close ARGV if eof')" || true
echo "GitHub links kept: $(cd "$BUILD/$NEW_ID" && grep -rIF "$KEEP$OLD_ID" . | wc -l | tr -d ' ')"
if [ -n "$LEFT" ]; then echo "Old id left outside GitHub links:"; echo "$LEFT"; exit 1; fi
echo "Old id left outside GitHub links: (none)"

step "4. Set name and version in addon.xml"
NAME="$NEW_NAME" VER="$VERSION" perl -0pi -e \
  's/(<addon\b[^>]*?\bname=")[^"]*"/$1$ENV{NAME}"/; s/(<addon\b[^>]*?\bversion=")[^"]*"/$1$ENV{VER}"/' \
  "$BUILD/$NEW_ID/addon.xml"
grep -m1 '<addon ' "$BUILD/$NEW_ID/addon.xml"

step "5. Zip"
mkdir -p "$(dirname "$ZIP")"
(cd "$BUILD" && zip -qr "$ZIP" "$NEW_ID")
ls -lh "$ZIP"

step "6. Rebuild addons.xml (latest version of every add-on) and checksum"
{
  echo '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
  echo '<addons>'
  for d in "$CATALOG"/zips/*/; do
    id="$(basename "$d")"
    latest="$(ls "$d" | grep -E "^$id-.*\.zip$" | sort -V | tail -1)"
    unzip -p "$d$latest" "$id/addon.xml" | sed '/<?xml/d'; echo
  done
  echo '</addons>'
} > "$CATALOG/addons.xml"
if command -v md5 >/dev/null; then md5 -q "$CATALOG/addons.xml"; else md5sum "$CATALOG/addons.xml" | cut -d' ' -f1; fi > "$CATALOG/addons.xml.md5"
grep -E '<addon ' "$CATALOG/addons.xml"

step "7. Publish"
git -C "$CATALOG" add zips addons.xml addons.xml.md5
git -C "$CATALOG" status --short
read -r -p "Commit and push catalog, and tag the source as htpc-$VERSION? [y/N] " ok
if [[ "$ok" == [yY] ]]; then
  git -C "$CATALOG" commit -m "$NEW_ID $VERSION" && git -C "$CATALOG" push
  git -C "$SRC" tag "htpc-$VERSION" && git -C "$SRC" push origin "htpc-$VERSION"
  echo "Done. Kodi will see $NEW_ID $VERSION."
else
  echo "Not published. Changes are staged in $CATALOG (undo: git -C \"$CATALOG\" reset --hard)."
fi