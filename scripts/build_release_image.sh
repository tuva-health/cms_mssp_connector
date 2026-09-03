#!/bin/sh
# Build, push and digest-bind one immutable connector release image.
#
#   scripts/build_release_image.sh REGISTRY/REPOSITORY RELEASE_ID
#
# The image is tagged REPOSITORY:RELEASE_ID, pushed, resolved to its immutable
# repository@sha256 digest and bound to the baked release metadata in
# release-metadata/RELEASE_ID.json (via scripts/create_release_metadata.py).
#
# Environment:
#   RELEASE_REF  Commit that HEAD must equal before a release is cut. Defaults to
#                origin/main; set it to the local canonical (for example
#                canonical-local/main) or to a full commit ID when convergence is
#                local-only and no published main exists.
#   AWS_REGION   ECR region. Defaults to the region encoded in the ECR registry
#                host name.
#
# Run through the project toolchain so python3 resolves to the locked
# interpreter: uv run --frozen scripts/build_release_image.sh ...
set -eu

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 2 ]; then
  printf 'usage: %s REGISTRY/REPOSITORY RELEASE_ID\n' "$0" >&2
  exit 64
fi

repository=$1
release_id=$2
release_ref=${RELEASE_REF:-origin/main}
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

for tool in aws docker git python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "required command not found: $tool"
done
# The digest-binding step needs the locked interpreter; check it before anything
# is pushed under an immutable tag that could not be re-pushed.
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null \
  || fail 'python3 must be 3.10 or newer: run this script via uv run --frozen'

case "$repository" in
  */*) ;;
  *) fail "repository must be REGISTRY/REPOSITORY, got: $repository" ;;
esac
case "${repository##*/}" in
  *:*|*@*) fail "repository must not carry a tag or digest; the release ID is the tag: $repository" ;;
esac
printf '%s' "$release_id" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' \
  || fail "invalid release ID: $release_id"

# Release builds must reproduce from source alone: refuse a clone with tracked
# changes or untracked non-ignored files (gitignored tooling does not count).
if [ -n "$(git status --porcelain)" ]; then
  fail 'release builds require a clean canonical clone'
fi

source_commit=$(git rev-parse HEAD)
if ! release_commit=$(git rev-parse --verify --quiet "$release_ref^{commit}"); then
  fail "release reference $release_ref does not resolve to a commit (set RELEASE_REF)"
fi
if [ "$source_commit" != "$release_commit" ]; then
  fail "release source $source_commit must equal release reference $release_ref ($release_commit)"
fi

registry=${repository%%/*}
repository_name=${repository#*/}
region=${AWS_REGION:-}
if [ -z "$region" ]; then
  case "$registry" in
    *.dkr.ecr.*.amazonaws.com)
      region=${registry#*.dkr.ecr.}
      region=${region%.amazonaws.com}
      ;;
    *) fail "AWS_REGION must be set when the registry host does not encode a region: $registry" ;;
  esac
fi

# The repository must reject mutable tags so a release ID resolves to one digest.
mutability=$(aws ecr describe-repositories \
  --repository-names "$repository_name" \
  --region "$region" \
  --query 'repositories[0].imageTagMutability' \
  --output text)
[ "$mutability" = IMMUTABLE ] || fail "ECR repository $repository_name must enforce IMMUTABLE tags, got: $mutability"

tagged_image="$repository:$release_id"
printf '[info] release=%s source=%s ref=%s image=%s\n' \
  "$release_id" "$source_commit" "$release_ref" "$tagged_image"

# Fetch the token first: POSIX sh has no pipefail, so a failed token fetch must
# not hide behind docker login's exit status.
login_token=$(aws ecr get-login-password --region "$region")
printf '%s' "$login_token" \
  | docker login --username AWS --password-stdin "$registry" >/dev/null

docker build \
  --platform linux/amd64 \
  --build-arg "SOURCE_COMMIT=$source_commit" \
  --build-arg "RELEASE_ID=$release_id" \
  --tag "$tagged_image" \
  .
docker push "$tagged_image"

digest=$(aws ecr describe-images \
  --repository-name "$repository_name" \
  --region "$region" \
  --image-ids "imageTag=$release_id" \
  --query 'imageDetails[0].imageDigest' \
  --output text)
printf '%s' "$digest" | grep -Eq '^sha256:[0-9a-f]{64}$' \
  || fail "ECR returned an invalid image digest: $digest"

image_reference="$repository@$digest"
metadata_file="release-metadata/$release_id.json"
mkdir -p release-metadata
python3 scripts/create_release_metadata.py release \
  --image-reference "$image_reference" \
  --output "$metadata_file"

printf '[ok] released immutable image: %s\n' "$image_reference"
printf '[ok] wrote release metadata: %s\n' "$metadata_file"
