# Integration tests

`integration_tests` is the dbt project used for local development and CI of
`cms_mssp_connector`. It installs the connector as a local package
(`packages.yml` → `local: ../`), which brings in `cms_alr_connector` v1.0.0,
`medicare_cclf_connector` v1.0.0, Tuva Core v1.0.0 (dbt package name
`the_tuva_project`), the semantic-layer stack and CMS chronic conditions. It
loads synthetic fixture seeds where every `source()` expects raw tables and builds the whole stack
against them on local DuckDB, with no warehouse and no credentials. All CI
and local runs use `--project-dir integration_tests`.

## Layout

- `dbt_project.yml`: the canonical, commented inventory of the vars the
  connector and the packages it installs read. They are set here as global
  vars, so they reach every package exactly as in a client project. It also
  sets `require_ref_searches_node_package_before_root`, which Tuva Core 1.0
  requires and dbt reads only from the root project.
- `packages.yml`: the connector only. `dbt deps` resolves its packages from
  `../packages.yml` on every run; the `package-lock.yml` it writes here is
  gitignored. The root `package-lock.yml` records the set a release was
  built with.
- `seeds/`: one seed per raw table, loaded into
  `var('input_database')`.`var('input_schema')` so the connectors read them
  exactly as they read a client's raw tables. See Fixtures.
- `macros/`: schema naming and `ensure_unit_test_schemas` (an on-run-start
  hook that creates the schemas unit tests need).
- `profiles/local_duckdb`: the DuckDB profile for local runs and the
  `dbt build / duckdb` CI job (`/tmp/cms_mssp_connector_ci.duckdb` unless
  `DBT_DUCKDB_PATH` is set).

## Fixtures

Every seed is synthetic or header-only. No real beneficiary, provider or ACO
data is committed, and every CSV must pass the `cclf-synth` leak-check
before it is committed.

| Seeds | Source tables | Origin |
| --- | --- | --- |
| `seeds/alr_cclf/` | the six ALR tables (source `cms_ssp_reports`) and the CCLF tables (source `medicare_cclf`) | Copied unchanged from `cms_alr_connector` v1.0.0 `integration_tests/seeds/`, which the `cclf-synth` generator builds. Shared fake beneficiaries `9TT0FK…`, ACO `A0000`. Copy them again when the ALR pin moves. |
| `seeds/workbooks/` | the twenty BNMRK / AEXPU / QEXPU relations of the workbook export contract | `cclf-synth generate-mssp`: CMS-consistent synthetic workbooks for ACO `A0000`, PY2025 (see below). |
| `seeds/mssp/` | the other `mssp_raw` tables: BEUR, BAIP, NCBP, MCQM, BNEX, the participant lists and the shadow bundles | BEUR, `beneficiary_exclusions` and `excluded_beneficiary_mbi_xref` carry rows from `cclf-synth generate-mssp` for the ALR fixture beneficiaries; the rest are header only. `seeds/mssp/_seeds.yml` names the source of each header. |

The workbook relations follow the delivered CMS workbooks' grammar: the
labels, the cells CMS leaves empty or writes `-` in, and the sheets each
delivery carries come from a header-only profile of real workbooks run
through `cms_mssp_pipeline`'s own parser; every value is generated. The
deliveries are a PY2025 preliminary historical benchmark without Table 6 (its
pairings are not calculable), the final one with Table 6, each with its AEXPU
BY1-BY3 workbooks, and QEXPU 2025Q1-Q3 plus a 2025Q3 redelivery. Stamps match
the ALR fixture packages. The values are consistent with each other and with
the CMS calculation: [D] is 1 at BY3, [L] is the blended benchmark plus the
regional adjustment, QEXPU weights sum to 1 and quarter columns stop at the
reported quarter. Person years and assigned-beneficiary counts are counted
from the ALR seeds, so the member-month benchmark reconciles to the report.
The three quarters land in `no_savings`, `below_msr` and `above_msr`.

The BEUR rows give 2024 member-months their enrollment type, because the
benchmark-year ALR carries monthly scores and no type column. One BEUR row
uses a previous MBI that only the BNEX MBI crosswalk resolves.

Every test runs at its own severity, and the build has no warnings. The
connector's `mssp_aco_agreement` seed ships to clients with only its
`EXAMPLE-ACO` row, so `dbt_project.yml` here appends `A0000`'s row (variable
MSR, ACPT at PY1) to it with a seed post-hook; a root seed of the same name
cannot replace a package's.

The ALR seeds have no disabled or aged/dual beneficiary assigned with a score
in 2025, so `fact_benchmark_aco_quarter`'s aggregate risk ratio and cap
factor, and `fact_member_month_benchmark`'s capped rate, are NULL by design
here. The flat, enrollment-type and uncapped risk-adjusted rates are
populated. Two unit tests pin the cap with every type scored, binding and
not binding, and the capped member rates reconciling to the ACO benchmark:
`fact_benchmark_aco_quarter::test_cap_with_every_enrollment_type_scored` and
`fact_member_month_benchmark::test_capped_rates_reconcile_with_every_enrollment_type_scored`.
TUVA-134 adds such beneficiaries to the cclf-synth ALR fixtures for the
next `cms_alr_connector` release.

## Local runs

From the repo root, `scripts/dbt-local` runs dbt with the uv-locked
toolchain against this project and the local DuckDB profile:

```sh
scripts/dbt-local deps
scripts/dbt-local seed --full-refresh --select package:integration_tests
scripts/dbt-local build --full-refresh --exclude package:integration_tests,resource_type:seed
```

Load the seeds first. The connectors' staging views read the seeded tables,
and on an empty database a plain `build` starts them before the seeds have
loaded. Once the seeds are in place, `scripts/dbt-local build` on its own
also works. The build covers everything a client builds: this connector,
both CMS connectors, Tuva Core, the semantic-layer stack and CMS chronic
conditions. It takes a few minutes, most of it Tuva Core, and needs network access the first time
because Tuva loads its terminology seeds from a public bucket.

The connector's unit tests run inside the build: they mock refs, and dbt
reads each mocked relation's columns from the warehouse, so their parents
have to exist first. To run them alone after a build:
`scripts/dbt-local test --select "package:cms_mssp_connector,test_type:unit"`.

Set `DBT_PROFILES_DIR` (and `DBT_PROFILE`) to use another warehouse.

## CI

The `dbt build / duckdb` job in `.github/workflows/ci.yml` runs the same
three steps on every pull request to `main`, with no secrets.
