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
- `int_member_month_risk`: one row per Tuva person, data source and month
  carrying the MSSP enrollment type and the CMS prospective HCC risk score
  from the assignment list, with the source of each, the new-enrollee and
  assigned flags, and the MBI crosswalk step that joined the assignment list
  to the Tuva person id. Assignment is pinned to one delivery per calendar
  year, the earliest package that reports the year, so a later package's
  prospective-assignment window and benchmark-year re-deliveries never count
  as assignment for those months (TUVA-74).
- `fact_member_month_benchmark` in `semantic_layer`: the benchmark applied to
  every member-month, keyed on the same `MEMBER_MONTH_SK` as the Tuva
  `fact_member_months` for a one-to-one join. Three rates per member per
  month — flat (`[P] / 12`), by enrollment type (`[M] / 12` for the member's
  type) and risk-adjusted, uncapped (the type rate times the member's CMS
  prospective HCC score over the BY3 `[C]` for the type) — with the
  enrollment type, score and source, the BY3 score, the risk ratio, actual
  total paid and the variance to each rate. One projection serves each
  performance year, by default its latest calculable quarter on the latest
  delivery, and its period and submission ids are carried on every row. A
  member with no score gets a NULL risk-adjusted rate and a populated flag;
  a member-month in a year with no calculable projection keeps its row with
  NULL rates. The manifest verifier requires the fact in `semantic_layer`; a
  unit test pins the three rates, and singular tests assert the one-to-one
  join, the per-year-per-type reconciliation of the risk-adjusted rate, and
  (warn) the flat rate against the quarterly report's person years and one
  ACO per performance year (TUVA-75).
- `fact_benchmark_aco_quarter` in `semantic_layer`: one row per ACO,
  performance year and reported quarter on the latest calculable delivery,
  with the benchmark and expenditure PMPM, projected savings percentage,
  estimated MSR and basis, savings status, and the risk adjustment block —
  the per-type PY-to-BY3 risk ratio (assignment-list PY mean over BY3
  `[C]`), the aggregate ratio weighted by person years times historical
  benchmark expenditure per 42 CFR 425.605(a)(1)(ii)(C), the cap bound
  `1 + mssp_risk_score_cap` (new project variable, default `0.03`), the cap
  factor `bound / R` where the aggregate exceeds the bound and 1 otherwise
  — one-sided per 42 CFR 425.605(a)(1)(ii), so a decrease in the aggregate
  ratio passes through uncapped — an `IS_CAP_BINDING` flag, and the risk-adjusted ACO benchmark
  (`Σ enrollment proportion x [M] x ratio x factor`, annual and PMPM). The
  cap is applied at the aggregate and rescales every type by the one
  factor, so relative risk between members is preserved and the capped
  member total reconciles to the capped ACO benchmark. A scenario column set
  (`NATIONAL_GROWTH_PROJECTED`, `CAP_UPPER_BOUND_SCENARIO`,
  `CAP_FACTOR_SCENARIO`, `IS_CAP_BINDING_SCENARIO`) projects the growth term
  the regulation adds to the cap from the BNMRK Table 4 BY1-to-BY3 trend,
  compounded from the parameters sheet's BY3 calendar year; the flat cap is
  the default and the scenario is labelled a projection. The row serving
  `fact_member_month_benchmark` is flagged `IS_CURRENT_PROJECTION`. All
  figures are NULL-safe: a type without scored members leaves the aggregate,
  factor and capped columns NULL. The model docs cite the regulation and the
  CY 2023 PFS final rule (87 FR 69934-69946, 70238) and record where the
  model departs from them: the single-factor rescaling is a project
  convention. The manifest verifier requires the fact in `semantic_layer`; a
  unit test pins the aggregate, the cap above the bound, the pass-through
  below it, the no-cap case, the NULL cascade and the scenario; singular tests assert
  the capped member reconciliation and the projection agreement (TUVA-76).
- `fact_member_month_benchmark` gains `CAP_FACTOR`,
  `RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED` (the uncapped risk-adjusted rate
  times the year's factor) and `VARIANCE_TO_RISK_ADJUSTED_CAPPED`, read off
  the ACO-quarter fact's current row for the same ACO and year (TUVA-76).
- `fact_benchmark_aco_quarter` carries CMS's method of applying the risk
  score cap beside the project's single factor: `RISK_RATIO_CLIPPED_<TYPE>`
  (each type's ratio clipped at `CAP_UPPER_BOUND` where the aggregate
  exceeds it and left as it is where it does not, per 42 CFR
  425.605(a)(1)(ii)(B) and Step 7 at 87 FR 69935), `RISK_ADJUSTED_BENCHMARK_CMS`
  with its `_PMPM` (`Σ enrollment proportion x [M] x clipped ratio`, the
  same inputs and NULL cascade as `RISK_ADJUSTED_BENCHMARK`), and
  `RISK_ADJUSTED_BENCHMARK_METHOD_DIFFERENCE` (CMS minus single-factor,
  exactly 0 wherever the cap does not bind). No existing column changes,
  and `fact_member_month_benchmark` keeps the single factor, the one form
  under which member rows add up to the ACO figure. The unit test pins the
  two methods agreeing within the bound, parting where the types straddle
  it, and parting where every type is above it; the model docs and README
  describe both and why the member fact carries one.

### Changed

- `cms_alr_connector` is pinned at `51e1483`, which keeps CMS-HCC risk scores
  at ten decimals instead of rounding them to two. The member risk ratios and
  the risk-adjusted benchmark rates inherit the recovered precision on the
  next build.

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
