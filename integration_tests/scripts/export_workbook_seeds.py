"""Export the synthetic benchmark workbook relations as integration_tests seeds.

The twenty BNMRK / AEXPU / QEXPU seeds in integration_tests/seeds/workbooks
are the cms_mssp_pipeline synthetic end-to-end output: its openpyxl test
builders write a fake delivery, mssp-process unpivots it, and the run loads
every relation into a DuckDB database (schema raw_data). Every value is fake.

Regenerate them from a cms_mssp_pipeline checkout at the release the
workbook contract names (pyproject.toml [tool.cms_mssp_connector]):

    # in cms_mssp_pipeline
    uv run --frozen python -m tests.e2e.synthetic_run --workdir /tmp/e2e
    # in this repo
    uv run --frozen python integration_tests/scripts/export_workbook_seeds.py \
        --database /tmp/e2e/e2e.duckdb --workdir /tmp/e2e

The run records absolute local paths in file_path / directory_name; they are
rewritten to start at /synthetic/store so no local path is committed. The
pipeline's CCLF output is not exported: the CCLF seeds come from
cms_alr_connector (seeds/alr_cclf).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import duckdb

SEED_DIR = Path(__file__).resolve().parents[1] / "seeds" / "workbooks"
FAMILIES = ("bnmrk_", "aexpu_", "qexpu_")
NEUTRAL_STORE = "/synthetic/store"


def literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--database", type=Path, required=True, help="synthetic_run DuckDB file")
    parser.add_argument("--workdir", type=Path, required=True, help="synthetic_run --workdir")
    args = parser.parse_args()

    store = str((args.workdir / "store").resolve())
    connection = duckdb.connect(str(args.database), read_only=True)
    tables = [
        name
        for (name,) in connection.execute(
            "select table_name from information_schema.tables "
            "where table_schema = 'raw_data' order by table_name"
        ).fetchall()
        if name.startswith(FAMILIES)
    ]
    if len(tables) != 20:
        raise SystemExit(f"expected 20 workbook relations, found {len(tables)}: {tables}")

    SEED_DIR.mkdir(parents=True, exist_ok=True)
    for table in tables:
        columns = [
            name
            for (name,) in connection.execute(
                "select column_name from information_schema.columns "
                "where table_schema = 'raw_data' and table_name = ? order by ordinal_position",
                [table],
            ).fetchall()
        ]
        select = ", ".join(
            f'replace("{c}", {literal(store)}, {literal(NEUTRAL_STORE)}) as "{c}"'
            if c in ("file_path", "directory_name")
            else f'"{c}"'
            for c in columns
        )
        out = SEED_DIR / f"{table}.csv"
        connection.execute(
            f'copy (select {select} from raw_data."{table}" order by all) '
            f"to {literal(str(out))} (header, delimiter ',')"
        )
        print(f"wrote {out.relative_to(SEED_DIR.parents[1])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
