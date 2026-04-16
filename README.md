# cms_mssp_connector

`cms_mssp_connector` is a dbt project that stages raw CMS MSSP source files into a consistent input layer for downstream analytics.

The project currently focuses on lightweight staging models over MSSP raw tables. Most models pass source columns through as-is, with a small set of helper macros for safer type normalization such as date and numeric casting. The CMS source data is then passed into the existing cms_alr_connector and medicare_cclf_connector projects, where it is finally inputted into the Tuva models for analytics.

## What It Builds

Models are organized under `models/staging` and materialized as views by default.

Current staging groups:

- `participants`: participant and provider/supplier lists
- `bnex`: beneficiary exclusions and excluded beneficiary MBI crosswalks
- `mcqm`: beneficiary and quality measure files
- `mssp`: MSSP payment and utilization files
- `cclf`: claims benefit enhancement / demonstration code files
- `shadow_bundles`: shadow bundle source files

Model metadata in the `_models.yml` files configures these staging models into the `_stg_input_layer` schema.

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
- The project includes adapter-dispatched macros in `macros/` for safer cross-database casting.
- Several project vars are already defined: `claims_enabled`, `cms_alr_connector`, and `provider_attribution_enabled`.

## Project Structure

```text
.
|-- models/
|   `-- staging/
|       |-- bnex/
|       |-- cclf/
|       |-- mcqm/
|       |-- mssp/
|       |-- participants/
|       `-- shadow_bundles/
|-- macros/
|-- seeds/
`-- dbt_project.yml
```
