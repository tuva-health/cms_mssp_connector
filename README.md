# cms_mssp_connector

`cms_mssp_connector` is a dbt project that stages raw CMS MSSP source files into a consistent input layer for downstream analytics.

The project stages MSSP raw tables into a lightweight input layer, adds a
thin intermediate layer over the CMS benchmark workbooks, and derives the
three-way blended benchmark update and projected savings from them. Most models pass source columns through as-is, with a small set of helper macros for safer type normalization such as date and numeric casting. The CMS source data is then passed into the existing cms_alr_connector and medicare_cclf_connector projects, where it is finally inputted into the Tuva models for analytics.

## What It Builds

Models are organized under `models/staging` and materialized as views by default.

Current staging groups:

- `participants`: participant and provider/supplier lists
- `bnex`: beneficiary exclusions and excluded beneficiary MBI crosswalks
- `mcqm`: beneficiary and quality measure files
- `mssp`: MSSP payment and utilization files
- `cclf`: claims benefit enhancement / demonstration code files
- `shadow_bundles`: shadow bundle source files
- `benchmark`: historical benchmark and expenditure/utilization workbooks

Model metadata in the `_models.yml` files configures these staging models into the `_stg_input_layer` schema.

Intermediate models live under `models/intermediate` and are materialized as
tables, configured into the `_int_input_layer` schema:

- `benchmark`: typed facts over the BNMRK / AEXPU / QEXPU workbooks

The staging models are faithful but untyped — one row per worksheet cell, every
value in a text column — so an input to the historical benchmark is a
`(section_code, column_label)` lookup. The intermediate models turn the sheets
the benchmark depends on into facts with canonical dimensions (enrollment type,
benchmark year, report period, comparison column), and rank the repeated CMS
deliveries without choosing between them:

- `int_benchmark_historical` — BNMRK Table 1, every section of the benchmark derivation
- `int_benchmark_acpt` — BNMRK Table 6, the Accountable Care Prospective Trend
- `int_benchmark_trend` — BNMRK Table 2, the trend factor audit trail
- `int_benchmark_risk_scores` — BNMRK Table 1 sections [C] and [D] with Table 4,
  the CMS-HCC risk score inputs by enrollment type and benchmark year
- `int_expenditures_annual` — AEXPU Table 1, by benchmark year
- `int_expenditures_quarterly` — QEXPU Table 1
- `int_expenditures_regional` — QEXPU Table 2, regional expenditures and weights

They calculate nothing. Deriving the benchmark from these inputs is the job of
the final layer.

Final models live under `models/final`, are materialized as tables and are
configured into the `input_layer` schema alongside the other connectors' final
models:

- `fct_projected_benchmark_by_enrollment_type` — the per-enrollment-type inputs
  and update factors, ending in the projected updated benchmark expenditure
- `fct_projected_savings` — the ACO-level mean projected benchmark, the
  projected savings percentage, the estimated minimum savings rate, and the two
  comparisons between them
- `fct_projected_benchmark_by_enrollment_type_current` and
  `fct_projected_savings_current` — the default read path over the two facts
  above: the same figures filtered to the latest calculable benchmark delivery,
  one row per ACO, performance year, quarter (and enrollment type), with the
  projected updated benchmark and the ACO's expenditure also expressed per
  member per month (`*_PMPM`, the annual figure divided by twelve)

Two things about their grain govern how they must be queried, and both are
documented at length in `models/final/benchmark/_models.yml`:

- CMS delivers the historical benchmark up to three times for one performance
  year and the deliveries carry different numbers, so every pairing of a
  reported quarter with a benchmark delivery is a row. Filter on
  `IS_LATEST_BENCHMARK_SUBMISSION` for one row per quarter; an unfiltered query
  multiplies rows and averages over three answers to the same question.
- A pairing whose inputs are incomplete keeps its row and carries NULLs, flagged
  `IS_CALCULABLE = false`. The March preliminary delivery ships no Table 6, so
  the prospective trend and everything below it cannot be derived for anything
  paired with it. Dropping the row would be tidier and much harder to notice.

The two `_current` models apply both predicates once, so a consumer that wants
one answer per quarter reads them and never sees the multiplicity. Read the
full-grain facts for reconciliation against a particular delivery.

Two seeds supply what the workbooks do not carry: `seeds/mssp_msr_lookup.csv`,
the minimum savings rate band schedule, and `seeds/mssp_aco_agreement.csv`, the
per-ACO minimum savings rate election and agreement performance year. The second
ships with a synthetic example row only; an ACO with no row takes documented
defaults and every output row it produces is flagged `IS_AGREEMENT_DEFAULTED`.

### Tuva semantic layer

`dbt_project.yml` sets `semantic_layer_enabled: true`, so the same `build`
phase that populates the Tuva marts also builds the Tuva semantic layer: 22
facts and dimensions (`fact_member_months`, `fact_claims`, `fact_risk_scores`,
`dim_member`, `dim_date`, and the rest) plus their `semantic_layer__stg_*`
staging models and three value-set seeds, all placed in the `semantic_layer`
schema. The 22 facts and dimensions are part of the build contract:
`scripts/verify_manifest.py` requires every one of them to be enabled and
placed in `semantic_layer`, so a manifest that drops the semantic layer fails
the verifier before anything is released. After a run, `fact_member_months`
carries one row per person, data source, and month with the paid amounts and
risk scores populated.

## Expected Source Data

Sources are defined against a single source named `mssp_raw` and are read from:

- `database: {{ var('input_database') }}`
- `schema: {{ var('input_schema') }}`

Default values in `dbt_project.yml`:

- `input_database: tuva`
- `input_schema: raw_data`

Expected source tables include:

- `participants_list`
- `provider_and_supplier_list`
- `beneficiary_exclusions`
- `excluded_beneficiary_mbi_xref`
- `mcqm_beneficiaries`
- `mcqm_dm_001ssp`
- `mcqm_bcs_112ssp`
- `mcqm_dep_134ssp`
- `mcqm_htn_236ssp`
- `baip_beneficiary_advanced_investment_payment`
- `beur_beneficiary_expenditure_utilization_report`
- `ncbp_non_claims_based_payments`
- `claims_benefit_enhancement_and_demonstration_code_file_cclfa`
- `cclfb_claims_benefit_enhancement_and_demonstration_code_file_cclfb`
- `shadow_bundles_dm`
- `shadow_bundles_epi`
- `shadow_bundles_hh`
- `shadow_bundles_hs`
- `shadow_bundles_ip`
- `shadow_bundles_opl`
- `shadow_bundles_pb`
- `shadow_bundles_sn`

The `benchmark` group reads the CMS report workbooks, which arrive as three
families — `BNMRK` (Historical Benchmark), `AEXPU` (annual Expenditure &
Utilization, one workbook per benchmark year) and `QEXPU` (quarterly). Their
worksheets are loaded one row per cell, so all twenty tables share a single
long/tidy column contract:

- `bnmrk_table_1`
- `bnmrk_table_1a`
- `bnmrk_table_1b`
- `bnmrk_table_1c`
- `bnmrk_table_2`
- `bnmrk_table_3`
- `bnmrk_table_4`
- `bnmrk_table_5`
- `bnmrk_table_6`
- `bnmrk_parameters`
- `aexpu_table_1`
- `aexpu_table_1a`
- `aexpu_table_3`
- `aexpu_table_4`
- `aexpu_table_4a`
- `aexpu_parameters`
- `qexpu_table_1`
- `qexpu_table_2`
- `qexpu_table_3`
- `qexpu_parameters`

Some of these are legitimately absent from a given delivery rather than missing:
`bnmrk_table_6` does not appear in the preliminary benchmark delivery, and
`aexpu_table_1a` / `aexpu_table_4a` are shipped for the first two benchmark
years only.

## Dependencies

This project depends on:

- `dbt-labs/dbt_utils`
- `tuva-health/cms_alr_connector`

Install packages with:

```bash
dbt deps
```

## Setup

1. Configure your dbt profile so the project can connect to your warehouse.
2. Ensure the profile name used by this project is available as `cms_mssp_connector` or update `profile:` in `dbt_project.yml`.
3. Load the MSSP raw tables into the configured `input_database` and `input_schema`.
4. Install dependencies with `dbt deps`.

If your raw data lives somewhere other than the defaults, override the vars at runtime:

```bash
dbt run --vars '{input_database: my_database, input_schema: my_schema}'
```

## Common Commands

Install dependencies:

```bash
dbt deps
```

Build everything:

```bash
dbt build
```

Run only staging models:

```bash
dbt run --select staging
```

Run a single model group:

```bash
dbt run --select staging.mcqm
```

Run tests:

```bash
dbt test
```

Generate docs:

```bash
dbt docs generate
dbt docs serve
```

## Release Image

A release is one immutable image built from a clean clone whose `HEAD` is the
agreed release commit. `scripts/build_release_image.sh` builds it for
`linux/amd64`, pushes it under the release ID as its tag, resolves the pushed
`repository@sha256:` digest from ECR and binds that digest to the metadata baked
into the image:

```bash
uv run --frozen scripts/build_release_image.sh <registry>/<repository> <release-id>
```

- The clone must be clean (git-ignored tooling and `release-metadata/` do not
  count) and `HEAD` must equal `RELEASE_REF`, which defaults to `origin/main`.
  When convergence is local-only and no published `main` exists, point it at the
  ref you actually release from instead — a local branch such as
  `RELEASE_REF=main`, the remote-tracking ref of a local canonical clone such as
  `canonical-local/main`, or a full commit ID — no ref rewriting is needed.
- The ECR repository must enforce `IMMUTABLE` tags; `AWS_REGION` defaults to the
  region encoded in the registry host name.
- The script writes `release-metadata/<release-id>.json` (git-ignored) whose
  `image_reference` is the `repository@sha256:` digest. Pin task definitions to
  that digest, never to the tag.

## Continuous Integration

`.github/workflows/ci.yml` runs on every pull request to `main` and on every
push to `main`, with no warehouse access and no client secrets. Its five jobs
are the checks to require on `main`:

- `test` — `uv sync --frozen` then the contract tests under `tests/`
  (runtime, manifest, release and dependency contracts).
- `lock` — `uv lock --check`: `uv.lock` agrees with `pyproject.toml`.
- `dbt-parse` — `dbt deps`, then `dbt parse` for the `dev` and `prod` targets
  against a placeholder Snowflake profile rendered from
  `config/profiles.example.yml` by `scripts/render_placeholder_profile.sh`,
  followed by `scripts/verify_manifest.py` on each manifest with that target's
  placeholder database. `dbt parse` opens no connection, so this proves the
  project parses under the pinned dbt and that the accepted output set and its
  placement hold, without a warehouse.
- `shell` — `shellcheck` on `scripts/*.sh`.
- `image` — `docker build` of the release image for `linux/amd64` with the
  same build arguments as `scripts/build_release_image.sh`, without a push.
  The Dockerfile copies `config/profiles.yml` into the image, so the job
  renders the same placeholder profile into the build context first.

Live `dbt build` and `dbt test` runs against a warehouse remain in the client
repositories; this workflow never runs them.

## Releases

Releases are semver tags `vX.Y.Z` on `main`. Each one has an entry in
[`CHANGELOG.md`](CHANGELOG.md) and a GitHub Release carrying the immutable
image digest and the release metadata produced by
`scripts/build_release_image.sh`. A release stays marked pre-release until a
client deployment has validated it end to end.

## Project Notes

- Staging models are configured as views in `dbt_project.yml`.
- The project includes adapter-dispatched macros in `macros/` for safer cross-database casting. `cast_numeric_or_null` and `cast_year_or_null` return NULL instead of raising when a source value is not a number or not a four-digit year, which the benchmark workbooks require because every worksheet cell — figures, `-` markers and free text alike — arrives in one text column.
- Several project vars are already defined: `claims_enabled`, `cms_alr_connector`, and `provider_attribution_enabled`.
- Intermediate models and final models are configured as tables in `dbt_project.yml`.
- `macros/to_double.sql` and `macros/safe_divide.sql` exist for the final layer.
  The benchmark calculation is a chain of ratios and products over cells Excel
  stores as doubles, and doing that arithmetic in `numeric(38,24)` goes wrong
  both ways: the products overflow — DuckDB raises `Out of Range Error: Needed
  scale 48`, Snowflake truncates to its 38-digit cap — and the quotients come
  back at a scale derived from the operands rather than from the value, so
  Snowflake's `2 / 3` carries six fractional digits. `safe_divide` also returns
  NULL on a zero or NULL denominator rather than raising, which the preliminary
  delivery and CMS's `'-'` marker both require.
- `seeds/mssp_enrollment_type.csv` maps the Medicare enrollment type labels CMS writes in the benchmark workbooks to canonical keys. The labels are inconsistent between report families and even between sheets of one workbook, so the mapping is seeded rather than hardcoded; matching is case-insensitive, and a label the seed does not cover is marked `unmapped` and fails a test rather than being dropped.

## Project Structure

```text
.
|-- models/
|   |-- final/
|   |   `-- benchmark/
|   |-- intermediate/
|   |   `-- benchmark/
|   `-- staging/
|       |-- benchmark/
|       |-- bnex/
|       |-- cclf/
|       |-- mcqm/
|       |-- mssp/
|       |-- participants/
|       `-- shadow_bundles/
|-- macros/
|-- seeds/
|-- tests/
`-- dbt_project.yml
```
