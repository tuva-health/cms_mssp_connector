# Changelog

All notable changes to `cms_mssp_connector` are recorded here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A data test, `assert_assigned_member_months_are_typed`, that fails if an
  assigned member-month has no enrollment type (TUVA-138).
- `integration_tests/`, a dbt project that builds the connector and
  everything under it on local DuckDB from synthetic fixture seeds, with no
  credentials, and `scripts/dbt-local` to run it (TUVA-124). The seeds are
  `cms_alr_connector` v1.0.0's synthetic ALR and CCLF fixtures,
  CMS-consistent synthetic benchmark workbooks with BEUR and BNEX rows for the
  same beneficiaries (TUVA-126), and header-only tables for the other MSSP
  sources. The benchmark path produces real projected savings, ACO-quarter and
  member-month benchmark output in this build, and every test runs at its own
  severity with no warnings. `integration_tests` appends its synthetic ACO's
  row to `mssp_aco_agreement` with a seed post-hook; the shipped seed is
  unchanged. Each checkout builds into its own DuckDB file,
  `integration_tests/target/cms_mssp_connector_ci.duckdb`, so worktrees can
  build at the same time; `DBT_DUCKDB_PATH` overrides it with any path. A
  file with another stem must be attached as `cms_mssp_connector_ci` to
  read its views outside dbt (TUVA-133).
- Unit tests pinning the risk-score cap with every enrollment type scored,
  binding and not binding, and the capped member-month rates reconciling to
  the ACO benchmark (TUVA-126).
- Tuva's CMS chronic conditions package, `tuva-health/cms_chronic_conditions`
  `v1.0.0` (TUVA-137). Builds now produce
  `chronic_conditions.cms_chronic_conditions_long` and
  `chronic_conditions.cms_chronic_conditions_wide`, Tuva 1.0's replacement
  for the chronic conditions that semantic layer 1.0 dropped with
  `dim_condition` and `fact_member_condition_bridge`.
  `scripts/verify_manifest.py` requires both in `chronic_conditions`.
- The `dbt build / duckdb` CI job, which runs that build on every pull
  request to `main` without secrets. It installs DuckDB's `httpfs` extension
  in a setup step, cached per DuckDB version, and turns off DuckDB's
  extension auto-install, so the build never downloads an extension
  (TUVA-133).
- `MEMBER_MONTH_ID` on `fact_member_month_benchmark`, passed through from
  the semantic layer's `fact_member_months` (TUVA-127). It is the fact's key:
  the `not_null`, `unique` and relationships tests and the one-to-one test
  against `fact_member_months` now use it. Join the two facts on it.
- Scenario unit tests and a README section for the rule that decides which
  member-months count as assigned (TUVA-127, decision D1). The rule is
  unchanged. It differs from `cms_alr_connector` v1.0.0's governing-file rule
  on purpose. With a complete file history the two agree. While a
  benchmark-year file or the year's own Q4 list is missing, ALR governs some
  months from a file that reports another year. Those months are
  member-months in Tuva Core but `IS_ASSIGNED = false` with a NULL score
  here.

### Changed

- **Breaking:** `int_member_month_risk` types a member-month from the
  assignment list's monthly enrollment flag (ALR Table 1-1 `EnrollFlag`:
  1 ESRD, 2 disabled, 3 aged/dual, 4 aged/non-dual) when the month has no
  type score column (TUVA-138). The order is now type score column,
  enrollment flag, eligibility codes, else NULL. The BEUR person-year
  fractions are removed from typing. `ENROLLMENT_TYPE_SOURCE` reports
  `assignment_list_enroll_flag` where it reported
  `beur_person_year_fraction`, and `fact_member_month_benchmark` passes the
  new value through. A month only another performance year's delivery
  covers stays unassigned but takes that row's flag; on those rows
  `ENROLLMENT_TYPE_BENCHMARK_PMPM` and `VARIANCE_TO_ENROLLMENT_TYPE` follow
  the new type. Assigned-month aggregates are unaffected.
- `cms_alr_connector` moves to `v1.1.0`, which publishes the flag as
  `enrollment.enroll_flag`, and the harness's ALR and CCLF seeds are copied
  again from it. They add assigned disabled and aged/dual beneficiaries
  (TUVA-134), so the risk-score cap is populated and binds in the harness
  build.
- **Breaking:** the package stack moves to Tuva 1.0 (TUVA-124).
  `cms_alr_connector` is pinned to `v1.0.0` (from commit `24302c5`), which
  brings `medicare_cclf_connector` `v1.0.0` and Tuva Core `v1.0.0`
  (`tuva-health/tuva-core`, replacing the `the_tuva_project` repository at
  v0.17.2). `packages.yml` also declares Tuva Core and the semantic-layer
  stack, all at `v1.0.0`: `semantic_layer`, `ahrq_quality_indicators`,
  `ccsr`, `cms_hcc`, `nyu_ed_classification` and `quality_measures`. The
  regenerated lock no longer has `elementary`, `dbt_expectations` or
  `dbt_date`. A client project that installs this connector must set the
  `require_ref_searches_node_package_before_root` flag, which
  `dbt_project.yml` now sets.
- **Breaking:** the Tuva semantic layer comes from the separate
  `semantic_layer` package, and its build contract is 19 outputs, down from
  22. Semantic layer 1.0 dropped `dim_condition`, `fact_expected_values` and
  `fact_member_condition_bridge`, so those tables are no longer built.
  `scripts/verify_manifest.py` now expects the unique ids
  `model.semantic_layer.semantic_layer__*`. `fact_member_month_benchmark`
  reads `semantic_layer__fact_member_months` from that package, and
  `int_member_month_risk` uses Tuva 1.0's `core__member_month` spine
  (renamed from `core__member_months`).
- dbt-core is unchanged at 1.11.14, so no action is needed. It is not the
  1.10.20 that `cms_alr_connector` and `medicare_cclf_connector` pin:
  dbt-core 1.10.20 requires sqlparse below 0.5.5, which would drop this
  project's `sqlparse>=0.6.0` security floor.

### Fixed

- Member-months on the 2022-2024 assignment-list layout, which has no type
  columns, now carry CMS's monthly enrollment type (TUVA-138). On
  assignment-list-only months, including the 2022 and 2023 benchmark
  years, there was no status code to fall back on, so every member landed
  in an aged type and those years had no ESRD or disabled members.

### Deprecated

- `MEMBER_MONTH_SK` on `fact_member_month_benchmark` (TUVA-127). It is still
  populated, but semantic layer 1.0 no longer guarantees it unique: a
  person-month with more than one payer or plan has one row per coverage,
  all with the same key. Its relationships test is dropped, and its `unique`
  test now warns instead of failing.

### Removed

- **Breaking:** the `stg_claims_benefit_enhancement_and_demonstration_code_file_cclfa`
  and `stg_cclfb_claims_benefit_enhancement_and_demonstration_code_file_cclfb`
  staging models and their two sources. Nothing read them, and their casts
  followed the pipeline's CCLFB layout, which is not CCLF IP v43.
  `medicare_cclf_connector` v1.0.0 reads Part A and Part B demonstration
  codes from its own `parta_demo_codes` and `partb_demo_codes` sources. The
  MSSP output contract is 20 staging outputs, down from 22.
- The `demo_data_only` and `semantic_layer_enabled` vars, which nothing
  reads any more.

## [0.3.0] - 2026-10-08

### Added

- Tag-triggered release workflow (`.github/workflows/release.yml`, TUVA-68).
  A `v*` tag on `main` whose version matches `pyproject.toml` and has a
  CHANGELOG section is built with `scripts/build_image.sh` against the
  placeholder profile and rebuilt on a second runner. A GitHub pre-release is
  then created with the CHANGELOG section, the workbook contract version, the
  image digests, the rebuild verdict, and the release metadata. No image is
  pushed anywhere. Any trigger other than a tag push is a dry run. The
  workbook contract the models read is pinned in `pyproject.toml`
  (`[tool.cms_mssp_connector] workbook_contract`), and
  `scripts/create_release_metadata.py release --local-image` reads the baked
  metadata from an image that was built but not pushed.
- README *Consuming a release in a client fork* and
  `scripts/check_release_conformance.sh` (TUVA-69): merge the tag through
  `upstream-sync/*`, prove with git that the fork's commit contains the tag
  and differs only in `config/profiles.yml` and `.gitignore`, then build and
  deploy the fork's own commit and pin `CONNECTOR_IMAGE`; the full loop is in
  `cms_mssp_pipeline` `docs/client-release-consumption.md`.
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

- The image build moved from `scripts/build_release_image.sh` into
  `scripts/build_image.sh`, which the push script and the release workflow
  both call. Builds now go through `docker buildx build` with `SOURCE_DATE_EPOCH`
  set to the commit time, layer timestamps rewritten to it, and provenance and
  SBOM attestations off. Needs BuildKit 0.13 or newer.
- `cms_alr_connector` is pinned to a commit in `packages.yml` (`24302c5`,
  the merge of tuva-health/cms_alr_connector#4) instead of tracking its
  default branch; that was the last git dependency pinned only in the lock,
  so regenerating the lock can no longer pull an unreviewed ALR commit
  (P-TUVA-14). Over the release the lock moved from the previous revision to
  `51e1483`, which keeps CMS-HCC risk scores at ten decimals instead of
  rounding them to two (the member risk ratios and the risk-adjusted
  benchmark rates inherit the recovered precision on the next build), and
  then to `24302c5`. The ALR change between those two commits touches only
  its own `packages.yml`, `package-lock.yml`, and `.gitignore`; the resolved
  packages are unchanged (`medicare_cclf_connector` `603a258`,
  `the_tuva_project` from GitHub at `v0.17.2`, `cc3b8ce`).

### Fixed

- `dbt deps` works again. The dbt Hub entry for `the_tuva_project` 1.0.0
  publishes `require_dbt_version` as the single string `">=1.10.5,<3.0.0"`,
  which dbt-core's semver parser rejects, and dbt reads every Hub version of a
  package even when `package-lock.yml` pins one. The lock now installs
  `the_tuva_project` from GitHub at the `v0.17.2` tag commit (`cc3b8ce`), the
  same code the Hub's 0.17.2 served, so `dbt deps` never queries the Hub for
  it. This matches how `medicare_cclf_connector` now installs it.

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

[Unreleased]: https://github.com/tuva-health/cms_mssp_connector/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/tuva-health/cms_mssp_connector/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/tuva-health/cms_mssp_connector/releases/tag/v0.2.0
