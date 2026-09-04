# Changelog

All notable changes to `cms_mssp_connector` are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The Tuva semantic layer is part of the build contract. `dbt_project.yml`
  sets `semantic_layer_enabled: true`, so the `build` phase materialises the
  22 semantic layer facts and dimensions (with their staging models and
  value-set seeds) in the `semantic_layer` schema, and
  `scripts/verify_manifest.py` requires each of them to be enabled and placed
  there. Before this the connector never set the var, so the schema was a
  stale artifact of an earlier run with an empty member-months fact
  (TUVA-71).
- Current-projection models `fct_projected_benchmark_by_enrollment_type_current`
  and `fct_projected_savings_current` in `input_layer`: the two benchmark facts
  filtered to the latest calculable benchmark delivery, one row per ACO,
  performance year, quarter (and enrollment type), with the projected updated
  benchmark and the ACO's expenditure also expressed per member per month.
  They are the default read path; the full-grain facts remain for
  reconciliation against a particular delivery. The manifest verifier checks
  their placement, and unit tests pin the filter and the division (TUVA-72).
- `int_benchmark_risk_scores`: the benchmark-year half of the risk adjustment
  story, typed. BNMRK Table 1 sections [C] (the ACO's renormalised CMS-HCC
  risk score) and [D] (its ratio to BY3) joined to BNMRK Table 4 (the
  national assignable FFS mean score the renormalisation divides by), one row
  per delivery, enrollment type and benchmark year, ranked and flagged like
  the other intermediate benchmark models. Tests assert the full four-by-three
  grid on every latest delivery, that [D] is 1 at BY3, and that Table 4 is
  bound to its own sheet by magnitude; a warning reports a workbook carrying
  only one of the two sheets (TUVA-73).

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
