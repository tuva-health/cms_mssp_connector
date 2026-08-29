# cms_mssp_connector

`cms_mssp_connector` is a dbt project that stages raw CMS MSSP source files into a consistent input layer for downstream analytics.

The project stages MSSP raw tables into a lightweight input layer, and adds a
thin intermediate layer over the CMS benchmark workbooks. Most models pass source columns through as-is, with a small set of helper macros for safer type normalization such as date and numeric casting. The CMS source data is then passed into the existing cms_alr_connector and medicare_cclf_connector projects, where it is finally inputted into the Tuva models for analytics.

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
- `int_expenditures_annual` — AEXPU Table 1, by benchmark year
- `int_expenditures_quarterly` — QEXPU Table 1
- `int_expenditures_regional` — QEXPU Table 2, regional expenditures and weights

They calculate nothing. Deriving the benchmark from these inputs is a separate
concern and deliberately lives downstream of this project.

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
2. Ensure the profile name used by this project is available as `default` or update `profile:` in `dbt_project.yml`.
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

## Project Notes

- Staging models are configured as views in `dbt_project.yml`.
- The project includes adapter-dispatched macros in `macros/` for safer cross-database casting. `cast_numeric_or_null` and `cast_year_or_null` return NULL instead of raising when a source value is not a number or not a four-digit year, which the benchmark workbooks require because every worksheet cell — figures, `-` markers and free text alike — arrives in one text column.
- Several project vars are already defined: `claims_enabled`, `cms_alr_connector`, and `provider_attribution_enabled`.
- Intermediate models are configured as tables in `dbt_project.yml`.
- `seeds/mssp_enrollment_type.csv` maps the Medicare enrollment type labels CMS writes in the benchmark workbooks to canonical keys. The labels are inconsistent between report families and even between sheets of one workbook, so the mapping is seeded rather than hardcoded; matching is case-insensitive, and a label the seed does not cover is marked `unmapped` and fails a test rather than being dropped.

## Project Structure

```text
.
|-- models/
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
