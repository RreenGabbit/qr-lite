#!/bin/bash

# this script generates a release zip ball and a source code zip ball for the specified browser
# specify the browser in the first argument (firefox/chrome)

set -x # echo on

BROWSER="$1"

case "$BROWSER" in
  firefox)
    ;;
  chrome)
    ;;
  *)
    echo "You need to specify which browser to build for - pass 'firefox' or 'chrome' as the first argument."
    exit 1
    ;;
esac

zip_paths() {
  local output="$1"
  shift

  if command -v zip >/dev/null 2>&1; then
    zip -r -9 "$output" "$@"
    return
  fi

  python3 - "$output" "$@" <<'PY'
import os
import sys
import zipfile

output = sys.argv[1]
inputs = sys.argv[2:]

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for base in inputs:
        if not os.path.exists(base):
            continue
        if os.path.isdir(base):
            for root, _, files in os.walk(base):
                for name in files:
                    path = os.path.join(root, name)
                    zf.write(path, path)
        else:
            zf.write(base, base)
PY
}

zip_stdin_paths() {
  local output="$1"

  if command -v zip >/dev/null 2>&1; then
    zip -9 "$output" --exclude 'promo/*' -@
    return
  fi

  python3 - "$output" <<'PY'
import os
import sys
import zipfile

output = sys.argv[1]
paths = [line.rstrip("\n") for line in sys.stdin if line.strip() and not line.startswith("promo/")]

with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for path in paths:
        if os.path.exists(path):
          zf.write(path, path)
PY
}

pushd "$(dirname `dirname "$0"`)" || exit

if output=$(git status --porcelain) && [ -z "$output" ]; then
  echo "Working tree clean."
else
  read -p "Working tree dirty, new files won't be included. Continue(y/N)? " -n 1 -r
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      exit 1;
  fi
fi

PROJECT_ROOT="$(pwd)"
DIST_DIR="$PROJECT_ROOT/dist/$BROWSER"
RELEASE_DIR="$PROJECT_ROOT/release"
VERSION=$(node src/manifest.js "$BROWSER" | node -e "process.stdin.setEncoding('utf8');let data='';process.stdin.on('data',chunk=>data+=chunk);process.stdin.on('end',()=>console.log(JSON.parse(data).version));")

TAG="${GITHUB_REF_NAME}"
if [ -z "$TAG" ]; then
  TAG="$(git describe --tags --exact-match 2>/dev/null)"
fi
if [ -z "$TAG" ]; then
  TAG="v$VERSION"
fi

RELEASE_FILE="$RELEASE_DIR/qr-lite-$TAG-$BROWSER-release.zip"
SOURCE_FILE="$RELEASE_DIR/qr-lite-$TAG-$BROWSER-source.zip"

corepack yarn install && corepack yarn run eslint src && corepack yarn run webpack --mode production --env browser="$BROWSER"

if [ $? -eq 0 ]; then

  if [ ! -e "$RELEASE_DIR" ]; then
    mkdir "$RELEASE_DIR"
  fi
  if [ -e "$RELEASE_FILE" ]; then
    rm "$RELEASE_FILE"
  fi
  if [ -e "$SOURCE_FILE" ]; then
    rm "$SOURCE_FILE"
  fi

  cd "$DIST_DIR" || exit
  zip_paths "$RELEASE_FILE" ./*

  cd "$PROJECT_ROOT" || exit
  git ls-tree --name-only -r HEAD | zip_stdin_paths "$SOURCE_FILE"
fi
