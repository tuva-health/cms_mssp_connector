# Integration tests

`integration_tests` is the dbt project used for local development and CI of
`cms_mssp_connector`. It installs the connector as a local package
(`packages.yml` → `local: ../`), which brings in `cms_alr_connector` v1.0.0,
`medicare_cclf_connector` v1.0.0, Tuva Core v1.0.0 (dbt package name
`the_tuva_project`) and the semantic-layer stack. It loads synthetic fixture
seeds where every `source()` expects raw tables and builds the whole stack
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
- `scripts/export_workbook_seeds.py`: regenerates `seeds/workbooks/`.
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
| `seeds/workbooks/` | the twenty BNMRK / AEXPU / QEXPU relations of the workbook export contract | The `cms_mssp_pipeline` synthetic end-to-end run (`python -m tests.e2e.synthetic_run`, from its openpyxl test builders), exported by `scripts/export_workbook_seeds.py`. Fake ACO `T0000`. |
| `seeds/mssp/` | the other `mssp_raw` tables: BEUR, BAIP, NCBP, MCQM, BNEX, the participant lists and the shadow bundles | Header only, no rows. `seeds/mssp/_seeds.yml` names the source of each header. |

The pipeline's workbook builders are shape- and type-valid but not
CMS-consistent: their labels, sheet bindings and enrollment types are not
what a CMS delivery holds. So the benchmark facts come out empty, and the
benchmark tests that check CMS semantics fail on them. Those tests carry the
`fixture_gap` tag. Their severity is `var('mssp_fixture_gap_severity')`,
which the connector defaults to `error` and this project sets to `warn`, so
they still run and are reported but do not fail the build:

- `assert_benchmark_models_read_their_own_sheet`
- `assert_intermediate_models_read_their_own_sheet`
- `assert_benchmark_enrollment_types_are_mapped`
- `assert_risk_scores_are_complete_per_latest_submission`
- `accepted_values` on `int_benchmark_trend.BY_LABEL`
- `accepted_values` on `int_benchmark_risk_scores.BY_LABEL` and
  `int_benchmark_risk_scores.ENROLLMENT_TYPE`

`--select tag:fixture_gap` runs just these. TUVA-126 replaces the workbook
fixtures with CMS-consistent ones from `cclf-synth`, then removes the tag and
the var. No other test is relaxed.

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
both CMS connectors, Tuva Core and the semantic-layer stack. It takes a few
minutes, most of it Tuva Core, and needs network access the first time
because Tuva loads its terminology seeds from a public bucket.

The connector's unit tests run inside the build: they mock refs, and dbt
reads each mocked relation's columns from the warehouse, so their parents
have to exist first. To run them alone after a build:
`scripts/dbt-local test --select "package:cms_mssp_connector,test_type:unit"`.

Set `DBT_PROFILES_DIR` (and `DBT_PROFILE`) to use another warehouse.

## CI

The `dbt build / duckdb` job in `.github/workflows/ci.yml` runs the same
three steps on every pull request to `main`, with no secrets.
