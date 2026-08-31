#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'usage: %s IMAGE RELEASE_ID\n' "$0" >&2
  exit 64
fi

image=$1
release_id=$2
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

if [ -n "$(git status --porcelain)" ]; then
  printf 'release builds require a clean canonical clone\n' >&2
  exit 1
fi

source_commit=$(git rev-parse HEAD)
canonical_commit=$(git rev-parse refs/remotes/origin/main)
if [ "$source_commit" != "$canonical_commit" ]; then
  printf 'release source must equal canonical origin/main\n' >&2
  exit 1
fi

exec docker build \
  --platform linux/amd64 \
  --build-arg "SOURCE_COMMIT=$source_commit" \
  --build-arg "RELEASE_ID=$release_id" \
  --tag "$image" \
  .
