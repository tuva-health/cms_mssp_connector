#!/bin/sh
# Check that a client fork carries a canonical release unchanged.
#
#   scripts/check-release-conformance.sh vX.Y.Z [REV]
#
# PASS when the tag vX.Y.Z is an ancestor of REV (default HEAD) and every path
# that differs between the tag and REV is client-specific (see allowed below).
# Otherwise FAIL, naming the offending paths. Exit 0 on PASS, 1 on FAIL.
# See README, "Consuming a release in a client fork".
set -eu

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'usage: %s vX.Y.Z [REV]\n' "$0" >&2
  exit 64
fi
tag=$1
rev=${2:-HEAD}

# Client-specific paths: the fork's dbt profile, and .gitignore, which a fork
# edits to commit that profile. Database, schema and target come from the
# runtime overlay (scripts/run_dbt.sh --vars), so dbt_project.yml stays
# canonical. Anything else is a change to canonical code and belongs upstream.
allowed() {
  case $1 in
    config/profiles.yml | .gitignore) return 0 ;;
    *) return 1 ;;
  esac
}

if ! tag_commit=$(git rev-parse -q --verify "refs/tags/$tag^{commit}"); then
  printf 'FAIL: no tag %s in this clone (git fetch upstream --tags)\n' "$tag"
  exit 1
fi
if ! rev_commit=$(git rev-parse -q --verify "$rev^{commit}"); then
  printf 'FAIL: %s is not a commit\n' "$rev"
  exit 1
fi
printf 'tag %s: %s\nrev %s: %s\n' "$tag" "$tag_commit" "$rev" "$rev_commit"

if ! git merge-base --is-ancestor "$tag_commit" "$rev_commit"; then
  printf 'FAIL: %s is not an ancestor of %s (merge the tag, do not rebase)\n' "$tag" "$rev"
  exit 1
fi

changed=$(git -c core.quotePath=false diff --name-only --no-renames "$tag_commit" "$rev_commit")
client=''
offending=''
while IFS= read -r path; do
  [ -n "$path" ] || continue
  if allowed "$path"; then
    client="$client  $path
"
  else
    offending="$offending  $path
"
  fi
done <<EOF
$changed
EOF

if [ -n "$offending" ]; then
  printf 'FAIL: %s changes canonical paths relative to %s:\n%s' "$rev" "$tag" "$offending"
  exit 1
fi
printf 'PASS: %s carries %s; client-specific paths that differ:\n%s' "$rev" "$tag" "${client:-  (none)
}"
