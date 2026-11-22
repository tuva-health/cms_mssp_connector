# Integration tests

`integration_tests` is the dbt project used for local development and CI of
`cms_mssp_connector`. It installs the connector as a local package
(`packages.yml` → `local: ../`), which brings in `cms_alr_connector` v1.1.1,
`medicare_cclf_connector` v1.0.2, Tuva Core v1.0.0 (dbt package name
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
  `dbt build / duckdb` CI job. It attaches the file `DBT_DUCKDB_PATH` names
  as catalog `cms_mssp_connector_ci`, the `input_database` the seeds load
  into, so dbt accepts any file name. It has no default path:
  `scripts/dbt-local` and CI each set one (see Local runs).

## Fixtures

Every seed is synthetic or header-only. No real beneficiary, provider or ACO
data is committed, and every CSV must pass the `cclf-synth` leak-check
before it is committed.

| Seeds | Source tables | Origin |
| --- | --- | --- |
| `seeds/alr_cclf/` | the six ALR tables (source `cms_ssp_reports`) and the CCLF tables (source `medicare_cclf`) | Copied unchanged from `cms_alr_connector` v1.1.1 `integration_tests/seeds/`, which the `cclf-synth` generator builds. Shared fake beneficiaries `9TT0FK…`, ACO `A0000`. Copy them again when the ALR pin moves. |
| `seeds/workbooks/` | the twenty BNMRK / AEXPU / QEXPU relations of the workbook export contract, and the three STLMT relations `fct_settlement` reads | `cclf-synth generate-mssp`: CMS-consistent synthetic workbooks for ACO `A0000`, PY2025 (see below). The STLMT seeds are header only (see the exception below). |
| `seeds/mssp/` | the other `mssp_raw` tables: BEUR, BAIP, NCBP, MCQM, BNEX, the participant lists and the shadow bundles | BEUR, `beneficiary_exclusions` and `excluded_beneficiary_mbi_xref` carry rows from `cclf-synth generate-mssp` for the ALR fixture beneficiaries; the rest are header only. `seeds/mssp/_seeds.yml` names the source of each header. |

**Exception: the STLMT seeds are header only.** `stlmt_table_2`,
`stlmt_table_3` and `stlmt_table_a1` carry the workbook contract's columns,
`is_embargoed` included, and no rows. They are not generated: cclf-synth does
not write a settlement workbook yet. CI therefore builds the settlement models
(`int_settlement_values`, `fct_settlement`, `fct_settlement_risk`) empty, and
their unit tests carry the logic. `scripts/dbt-pipeline-e2e` runs them on the
pipeline's synthetic STLMT workbook. Replace the headers with generated rows
once cclf-synth writes one.

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

The 2024 member-months take their enrollment type from the ALR monthly
enrollment flag, because the benchmark-year ALR carries monthly scores and
no type column. No ALR fixture MBI resolves through the BNEX crosswalk, so
the build does not exercise that path; the `int_member_month_risk` unit
tests `test_enrollment_type_priority_and_score_selection` (P6) and
`test_mbi_resolves_through_the_excluded_beneficiary_crosswalk` do.

Every test runs at its own severity, and the build has no warnings. The
connector's `mssp_aco_agreement` seed ships to clients with only its
`EXAMPLE-ACO` row, so `dbt_project.yml` here appends `A0000`'s row (variable
MSR, ACPT at PY1) to it with a seed post-hook; a root seed of the same name
cannot replace a package's.

The ALR seeds assign and score every enrollment type in 2025, including the
disabled and aged/dual beneficiaries TUVA-134 added, so
`fact_benchmark_aco_quarter`'s aggregate risk ratio and cap factor are
populated, and the cap binds in every 2025 quarter (`CAP_FACTOR` below 1).
`fact_member_month_benchmark` carries a capped rate on every assigned,
scored 2025 member-month. Two unit tests also pin the cap with every type
scored, binding and not binding, and the capped member rates reconciling to
the ACO benchmark:
`fact_benchmark_aco_quarter::test_cap_with_every_enrollment_type_scored` and
`fact_member_month_benchmark::test_capped_rates_reconcile_with_every_enrollment_type_scored`.

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

Each checkout builds into its own database,
`integration_tests/target/cms_mssp_connector_ci.duckdb` (git-ignored, and
removed by `scripts/dbt-local clean`), so two worktrees can seed and build
at the same time without touching each other's file. Point
`DBT_DUCKDB_PATH` at a shared path only if nothing else builds there.

`DBT_DUCKDB_PATH` takes any path; `scripts/dbt-local` creates its folder and
refuses a path containing `'`, which dbt-duckdb does not escape in its
`ATTACH`. dbt reads the file under the catalog name `cms_mssp_connector_ci`
whatever it is called, and every view it creates names that catalog. A tool
that opens the file directly names the catalog after the file's stem, so
the default file, and any file named `cms_mssp_connector_ci.duckdb`, opens as
is. Attach a file with another stem under the fixed name, or its views fail
with `Catalog "cms_mssp_connector_ci" does not exist`:

```sh
duckdb -cmd "ATTACH '/path/to/other.duckdb' AS cms_mssp_connector_ci; USE cms_mssp_connector_ci"
```

Set `DBT_PROFILES_DIR` (and `DBT_PROFILE`) to use another warehouse.

## Against cms_mssp_pipeline's synthetic output

The seeds above are this repo's copy of what the pipeline writes. To check a
pipeline change against the connector's models and tests, or a connector
change against a pipeline table that is not seeded yet, run the pipeline's
own synthetic end-to-end build through the connector:

```sh
scripts/dbt-pipeline-e2e <pipeline-checkout> [dbt build args...]
scripts/dbt-pipeline-e2e ../cms_mssp_pipeline --select +int_expenditures_annual --indirect-selection cautious
```

`<pipeline-checkout>` is any cms_mssp_pipeline checkout or worktree, merged
or not. The script changes nothing tracked there (`uv run` may sync its
`.venv`). It then:

1. Runs the pipeline's `tests/e2e/synthetic_run.py` there, writing its
   output under this checkout.
2. Seeds this project into a fresh database of its own and replaces every
   relation of the pipeline's workbook export contract
   (`contracts/workbook/v1.json` in that checkout) with the table the run
   wrote, creating any the seeds lack, such as the STLMT tables
   (`scripts/pipeline_overlay.py`). The ALR, CCLF and other `mssp_raw`
   seeds stay: the pipeline's CCLF rows are placeholders.
3. Runs `dbt build` with your arguments (none builds everything), always
   excluding this project's seeds so the build cannot reload them over the
   pipeline's tables.

Use it whenever a connector change reads a table the pipeline changed:
prove the change here before the pipeline merges, then add the generated
seeds as usual so the `dbt build / duckdb` job covers it.

Things to know:

- Everything lives in `integration_tests/target/pipeline_e2e/` of this
  checkout: the run in `pipeline/`, the database in
  `cms_mssp_connector_ci.duckdb`, dbt's artifacts in `target/`. It never
  touches `scripts/dbt-local`'s database, and worktrees never share a file.
  `PIPELINE_E2E_DIR` moves it; give each worktree its own, because every run
  deletes the database there first.
- The pipeline's workbooks are its test builders' minimal fixtures for ACO
  `T0000`, not the CMS-consistent `cclf-synth` workbooks for `A0000`. Several
  benchmark tests that check CMS consistency fail on them (BY labels,
  enrollment-type mapping, risk-score completeness), as do tests that join
  the workbooks to the `A0000` ALR seeds or agreement row. Select the models
  you are proving, and compare against a run on the pipeline's `main` to see
  what your change adds.
- Pass `--indirect-selection cautious` with a narrow selection. Singular
  tests with several parents are otherwise selected with any one of them and
  fail on the parents the selection did not build. Your own `--exclude`
  adds to the script's: dbt merges repeated `--exclude` flags.
- `pyproject.toml`'s `workbook_contract` pin is release metadata, not a
  runtime check, so a newer contract runs as is; the script prints a note
  when the two differ. Bump the pin in the connector change that reads the
  newer contract's tables or columns.

## CI

The `dbt build / duckdb` job in `.github/workflows/ci.yml` runs the same
three steps on every pull request to `main`, with no secrets, on
`$GITHUB_WORKSPACE/cms_mssp_connector_ci.duckdb`. Before dbt runs, it
installs DuckDB's `httpfs` extension (Tuva Core's terminology seeds are read
from S3) and caches `~/.duckdb/extensions` keyed on the DuckDB version. It
sets `DBT_DUCKDB_AUTOINSTALL_EXTENSIONS=false`, which the profile passes to
DuckDB as `autoinstall_known_extensions`, so the build loads extensions only
from that cache and never downloads one mid-run. If the build needs another
extension, add it to that install step. Local runs leave auto-install on.
