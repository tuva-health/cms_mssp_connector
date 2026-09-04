#!/bin/sh
# Render a placeholder dbt profile from config/profiles.example.yml.
#
#   scripts/render_placeholder_profile.sh > config/profiles.yml
#
# Every env_var() reference in the example gains a placeholder default, so the
# rendered profile carries no warehouse identity and parses with nothing
# exported. It exists for offline checks only (CI `dbt parse`, the image build
# verification); a real overlay is supplied by the operator at runtime.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
sed -E "s/env_var\('(SNOWFLAKE_[A-Z_]+)'\)/env_var('\1', 'build-verification')/g" \
  "$root/config/profiles.example.yml"
