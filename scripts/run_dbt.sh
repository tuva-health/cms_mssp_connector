#!/bin/sh
set -eu

usage() {
  printf 'usage: %s {dev|prod} {build|test}\n' "$0" >&2
  exit 64
}

[ "$#" -eq 2 ] || usage
environment=$1
phase=$2

# The target -> database mapping and the input schema are client-specific
# values supplied by the runtime overlay (git-ignored config/profiles.yml plus
# these environment variables). The phase grammar below is generic: the build
# phase runs seed -> snapshot -> run as separate fail-fast commands, and the
# test phase is isolated so warning-severity results stay visible while model
# and error-severity test failures return nonzero.
case "$environment" in
  dev) database=${MSSP_DEV_DATABASE:?MSSP_DEV_DATABASE must be supplied by the runtime overlay} ;;
  prod) database=${MSSP_PROD_DATABASE:?MSSP_PROD_DATABASE must be supplied by the runtime overlay} ;;
  *) usage ;;
esac

schema=${MSSP_INPUT_SCHEMA:?MSSP_INPUT_SCHEMA must be supplied by the runtime overlay}

variables="{input_database: $database, input_schema: $schema}"

case "$phase" in
  build)
    dbt seed --target "$environment" --vars "$variables"
    dbt snapshot --target "$environment" --vars "$variables"
    exec dbt run --target "$environment" --vars "$variables"
    ;;
  test)
    exec dbt test --target "$environment" --vars "$variables"
    ;;
  *) usage ;;
esac
