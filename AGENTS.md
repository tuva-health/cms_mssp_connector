# AGENTS.md

This file provides guidance to Agents when working with code in this repository.

## Project Overview

This is a dbt project (`cms_mssp_connector`, repo [tuva-health/cms_mssp_connector](https://github.com/tuva-health/cms_mssp_connector)) that stages the raw CMS Medicare Shared Savings Program files [cms_mssp_pipeline](https://github.com/tuva-health/cms_mssp_pipeline) loads, derives the benchmark and projected-savings facts from the CMS benchmark workbooks, and adds member-month benchmark facts beside the Tuva semantic layer. `packages.yml` pins [cms_alr_connector](https://github.com/tuva-health/cms_alr_connector) `v1.0.0`, which brings [medicare_cclf_connector](https://github.com/tuva-health/medicare_cclf_connector) `v1.0.0` and [Tuva Core](https://github.com/tuva-health/tuva-core) `v1.0.0` (dbt package name `the_tuva_project`). It also pins the semantic-layer package, the five marts it builds on and [CMS chronic conditions](https://github.com/tuva-health/cms_chronic_conditions), all at `v1.0.0`; move these pins together. The release is a container image (see the README). Client forks deploy it.

## Before you start

- **Running dbt, tests or CI**: read [integration_tests/README.md](integration_tests/README.md).
  Every local run goes through `scripts/dbt-local` (`--project-dir integration_tests`); the toolchain is `uv` and `uv.lock`.
- **Changing anything user-visible**: add it to `CHANGELOG.md` under `[Unreleased]` in the same PR, marking breaking changes **Breaking**.
- **Releasing or bumping `version`**: read the Releases section of [README.md](README.md#releases). `pyproject.toml` carries the release version.

## Common Commands

```bash
# Install dependencies (resolved from ../packages.yml; integration_tests/package-lock.yml is not committed)
scripts/dbt-local deps

# Load the synthetic fixture seeds (before the build: the staging views read them)
scripts/dbt-local seed --full-refresh --select package:integration_tests

# Build and test everything on local DuckDB (what the dbt build / duckdb check runs)
scripts/dbt-local build --full-refresh --exclude package:integration_tests,resource_type:seed

# Contract tests and the lock check (the test and lock checks)
uv run --frozen python -m unittest discover -s tests
uv lock --check
```

The build covers this connector, both CMS connectors, Tuva Core, the semantic-layer stack and CMS chronic conditions. The fixtures are CMS-consistent, so every test runs at its own severity; don't relax a test to make a build pass. The synthetic ACO `A0000`'s agreement row is appended to the `mssp_aco_agreement` seed by a post-hook in `integration_tests/dbt_project.yml`; never add it to the shipped seed.

## Data rules

This repository is public. Commit synthetic data only:

- No PHI, no real beneficiary, provider or ACO identifiers, and no counts, totals or other aggregates from real data. That applies to commits, PR bodies and issues alike.
- When you profile real deliveries locally, use aggregate-only scripts and never print rows. Real column headers are fine; read the header line only.
- Fixtures come from the `cclf-synth` generator, a local-only repo that is not in this repository and has no remote (on the maintainer's machine at `~/Code/clients/tuvahealth/cclf-synth`; ask the maintainer for access): `cclf-synth generate-mssp` writes the workbook relations and the BEUR / BNEX rows (see `integration_tests/README.md`). Never hand-edit a generated fixture; regenerate it. Copy the ALR and CCLF seeds from `cms_alr_connector` at the pinned tag.
- Run the `cclf-synth` leak-check on every CSV you commit (`mise exec --cd ~/Code/clients/tuvahealth/cclf-synth -- uv run leak-check <absolute path>`), and commit only when it passes.

## Raw-table contract with cms_mssp_pipeline

The pipeline writes every raw table to `{{ var('input_database') }}.{{ var('input_schema') }}`. This connector reads them through three sources:

- `mssp_raw` (this repo): the twenty BNMRK/AEXPU/QEXPU cell-grain relations, versioned by the workbook export contract (`contracts/workbook/v1.json` in the pipeline). `pyproject.toml` `[tool.cms_mssp_connector] workbook_contract` names the version the models read; bump it together with the models. It also covers the CSV, XML and fixed-width families (BEUR, BAIP, NCBP, MCQM, BNEX, participant lists, shadow bundles). The pipeline upper-cases the CSV headers and appends `FILE_PATH`, `DIRECTORY_NAME`, `FILE_NAME` and `FILE_DATE` to every family; MCQM also gets `PERIOD`.
- `cms_ssp_reports` (cms_alr_connector): the six ALR tables.
- `medicare_cclf` (medicare_cclf_connector): the CCLF tables. CCLF v1.0.0 reads Part A and Part B demonstration codes as `parta_demo_codes` and `partb_demo_codes`; aligning the pipeline's table names and its CCLFB layout is TUVA-125.

A change to a table name or column set is a change to both repos. Update the seeds under `integration_tests/seeds/` to match, so that `dbt build / duckdb` exercises the change.
