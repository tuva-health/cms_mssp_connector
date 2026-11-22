"""Overlay a cms_mssp_pipeline synthetic run's workbook tables onto the seeds.

Used by scripts/dbt-pipeline-e2e (TUVA-163). For every relation in the
pipeline's workbook export contract (contracts/workbook/v1.json), the table
the pipeline wrote as Parquet replaces the seeded table of the same name in
<database>.<schema>, so the connector's mssp_raw source reads the pipeline's
output. A relation the seeds lack (one a newer contract added) is created.
Tables outside the contract, such as the ALR and CCLF fixtures, keep their
seeds: the pipeline's synthetic CCLF rows are placeholders, not a consistent
claims fixture.

An optional relation the run did not write is replaced by an empty table of
the contract's columns, so no seeded row from another ACO is left beside the
pipeline's. A required relation it did not write fails the overlay before
anything is changed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import duckdb


def plan(contract: dict, parquet: Path) -> tuple[list[tuple[str, Path | None, list[dict]]], list[str]]:
    """(table, parquet file or None, contract columns) per relation, and the required ones missing."""
    steps = []
    missing = []
    for relation in contract["relations"]:
        table = relation["table"]
        path = parquet / f"{table}.parquet"
        columns = contract["schemas"][relation["schema"]]["columns"]
        if path.is_file():
            steps.append((table, path, columns))
        elif relation.get("optional", False):
            steps.append((table, None, columns))
        else:
            missing.append(table)
    return steps, missing


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--contract", required=True, type=Path, help="The pipeline's contracts/workbook/v1.json")
    parser.add_argument("--parquet", required=True, type=Path, help="The synthetic run's Parquet output directory")
    parser.add_argument("--database", required=True, type=Path, help="The DuckDB file dbt builds into")
    parser.add_argument("--schema", required=True, help="The schema the seeds load into (var input_schema)")
    args = parser.parse_args(argv)

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    steps, missing = plan(contract, args.parquet)
    if missing:
        print(f"the pipeline run wrote no Parquet for required relation(s): {', '.join(missing)}", file=sys.stderr)
        return 1

    with duckdb.connect(str(args.database)) as conn:
        conn.execute(f'create schema if not exists "{args.schema}"')
        conn.execute("begin")
        for table, path, columns in steps:
            target = f'"{args.schema}"."{table}"'
            if path is None:
                ddl = ", ".join(f'"{c["name"]}" {c["type"]}' for c in columns)
                conn.execute(f"create or replace table {target} ({ddl})")
            else:
                conn.execute(f"create or replace table {target} as select * from read_parquet(?)", [str(path)])
        conn.execute("commit")

    written = sum(1 for _, path, _ in steps if path is not None)
    print(
        f"overlaid {written} pipeline table(s) and emptied {len(steps) - written} optional relation(s) "
        f"from contract {contract.get('contract')} {contract.get('version')} into {args.schema}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
