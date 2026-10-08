#!/bin/sh
# Build one connector release image into the local image store.
#
#   scripts/build_image.sh REPOSITORY RELEASE_ID [--record FILE] [--check-only]
#
# This is the one build recipe. scripts/build_release_image.sh calls it before
# pushing to a client registry; .github/workflows/release.yml calls it to prove a
# tag builds and to record the digests a client build should reproduce. The image
# is tagged REPOSITORY:RELEASE_ID and loaded into the local image store; nothing
# is pushed here.
#
# --check-only runs the clean-clone and RELEASE_REF guards and exits, so a caller
# can refuse before it touches a registry.
# --record FILE writes the build record: source commit, release ID,
# SOURCE_DATE_EPOCH and the config (image ID) and manifest digests buildx reports.
#
# Reproducibility: SOURCE_DATE_EPOCH is the commit time of HEAD, layer file
# timestamps are rewritten to it and attestations are off. The dbt manifests
# baked into the image still carry a generation time and invocation ID, so two
# builds of one commit do not produce the same digest; see README "Releases".
#
# Environment:
#   RELEASE_REF  Commit that HEAD must equal before a release is built. Defaults
#                to origin/main; set it to the local canonical (for example
#                canonical-local/main) or to a full commit ID when convergence is
#                local-only and no published main exists.
set -eu

fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

record_file=
check_only=false
repository=
release_id=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --record)
      [ "$#" -ge 2 ] || fail '--record needs a file'
      record_file=$2
      shift 2
      ;;
    --check-only) check_only=true; shift ;;
    -*) fail "unknown option: $1" ;;
    *)
      if [ -z "$repository" ]; then repository=$1
      elif [ -z "$release_id" ]; then release_id=$1
      else fail "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done
if [ -z "$repository" ] || [ -z "$release_id" ]; then
  printf 'usage: %s REPOSITORY RELEASE_ID [--record FILE] [--check-only]\n' "$0" >&2
  exit 64
fi

release_ref=${RELEASE_REF:-origin/main}
root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
cd "$root"

for tool in docker git python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "required command not found: $tool"
done

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
[ "$check_only" = false ] || exit 0
source_date_epoch=$(git log -1 --format=%ct HEAD)

tagged_image="$repository:$release_id"
printf '[info] release=%s source=%s ref=%s image=%s epoch=%s\n' \
  "$release_id" "$source_commit" "$release_ref" "$tagged_image" "$source_date_epoch"

build_metadata=$(mktemp)
trap 'rm -f "$build_metadata"' EXIT

docker buildx build \
  --platform linux/amd64 \
  --provenance=false \
  --sbom=false \
  --build-arg "SOURCE_COMMIT=$source_commit" \
  --build-arg "RELEASE_ID=$release_id" \
  --build-arg "SOURCE_DATE_EPOCH=$source_date_epoch" \
  --output "type=docker,name=$tagged_image,rewrite-timestamp=true" \
  --metadata-file "$build_metadata" \
  .

python3 - "$build_metadata" "$repository" "$source_commit" "$release_id" \
  "$source_date_epoch" "$record_file" <<'PY'
import json
import re
import sys
from pathlib import Path

build_metadata, repository, source_commit, release_id, epoch, record_path = sys.argv[1:]
built = json.loads(Path(build_metadata).read_text(encoding="ascii"))
digest = built.get("containerimage.digest", "")
config_digest = built.get("containerimage.config.digest", "")
for label, value in (("manifest", digest), ("config", config_digest)):
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", value):
        raise SystemExit(f"buildx reported no {label} digest (got {value!r})")
if record_path:
    record = {
        "image": f"{repository}@{digest}",
        "manifest_digest": digest,
        "config_digest": config_digest,
        "source_commit": source_commit,
        "release_id": release_id,
        "source_date_epoch": int(epoch),
        "platform": "linux/amd64",
    }
    Path(record_path).parent.mkdir(parents=True, exist_ok=True)
    Path(record_path).write_text(json.dumps(record, indent=2) + "\n", encoding="ascii")
print(f"[ok] built {repository}:{release_id} (config {config_digest}, manifest {digest})")
PY
