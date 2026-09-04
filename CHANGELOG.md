# Changelog

All notable changes to `cms_mssp_connector` are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `int_member_month_risk`: one row per Tuva person, data source and month
  carrying the MSSP enrollment type and the CMS prospective HCC risk score
  from the assignment list, with the source of each, the new-enrollee and
  assigned flags, and the MBI crosswalk step that joined the assignment list
  to the Tuva person id (TUVA-74).

## [0.2.0] - 2026-09-04

First formal release of the converged baseline. Validated end to end in a
client dev and prod deployment on 2026-09-03/04.

### Added

- Pinned runtime and dependency baseline. `dbt-core`, `dbt-duckdb`, `duckdb`,
  and `dbt-snowflake` are pinned exactly, with `sqlparse` and `urllib3`
  security floors; `uv.lock` and `package-lock.yml` are tracked so a clean
  checkout builds the same environment. A dependency contract test guards the
  pins.
- Generic profile scaffold and env-var contract. The dbt profile is named
  `cms_mssp_connector` and is resolved from a git-ignored `config/profiles.yml`
  overlay; `config/profiles.example.yml` documents the profile structure, with
  every warehouse identity supplied as an `env_var()` reference so no account,
  user, role, warehouse, database, or schema literal enters the tree.
- Parameterized phase-grammar entrypoint (`scripts/run_dbt.sh`): a
  seed, snapshot, run build phase and an isolated test phase, fail-fast per
  command, with the target-to-database mapping and input schema read from
  `MSSP_DEV_DATABASE`, `MSSP_PROD_DATABASE`, and `MSSP_INPUT_SCHEMA` and a
  missing value failing closed. A runtime contract test covers the grammar.
- Output-set and placement verifier (`scripts/verify_manifest.py`). It checks
  the dbt version and locked package revisions against `requirements.txt` and
  `package-lock.yml`, the 22 enabled MSSP outputs, the 5 AALR/CCLF boundary
  outputs, the 20 benchmark staging views (BNMRK, AEXPU, QEXPU) and the 2
  final benchmark facts, their schema and alias placement, and a transitive
  enabled path into Tuva. The placement database is supplied with
  `--database` or derived from the manifest when omitted, so the tree carries
  no placement identity, and no full-graph hash is checked (TUVA-26).
- Hardened two-stage runtime image: a uv build on a digest-pinned
  `python:3.10.21-slim-bookworm` with snapshot-pinned apt packages; the
  runtime stage removes pip, runs as a non-root user, keeps `/app` read-only
  with a writable log path, and gates the build on `dbt parse`, the manifest
  verifier, and a non-root smoke parse.
- Release provenance scripts: `scripts/create_release_metadata.py` bakes the
  source commit, release id, and dependency and manifest digests into the
  image and binds them to the pushed image digest, and
  `scripts/build_release_image.sh` refuses a dirty or non-canonical source
  before building. Neither runs a full-graph manifest hash or a separate
  repository verification step. A release contract test covers both.

### Changed

- The release builder takes a configurable `RELEASE_REF` (default
  `origin/main`) so a local-only release needs no ref rewriting, and now
  pushes the image, requires an immutable ECR repository, captures the pushed
  `repository@sha256` digest, and binds it to the baked metadata in
  `release-metadata/<release-id>.json`; the interpreter is checked before
  anything is pushed, and `release-metadata/` is git-ignored (TUVA-54).
- README setup instructions refer to the `cms_mssp_connector` profile name.

[Unreleased]: https://github.com/tuva-health/cms_mssp_connector/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/tuva-health/cms_mssp_connector/releases/tag/v0.2.0
