#!/usr/bin/env python3
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
anything is changed. The contract is trusted input: its column types go
into the DDL as written.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import NamedTuple

import duckdb


class Replacement(NamedTuple):
    """One contract relation: the Parquet the run wrote for it, or None to empty it."""

    table: str
    parquet: Path | None
    columns: list[dict]


def replacements(contract: dict, parquet_dir: Path) -> tuple[list[Replacement], list[str]]:
    """The replacement for every contract relation, and the required relations the run did not write."""
    found = []
    missing = []
    for relation in contract["relations"]:
        table = relation["table"]
        path = parquet_dir / f"{table}.parquet"
        columns = contract["schemas"][relation["schema"]]["columns"]
        if path.is_file():
            found.append(Replacement(table, path, columns))
        elif relation.get("optional", False):
            found.append(Replacement(table, None, columns))
        else:
            missing.append(table)
    return found, missing


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--contract", required=True, type=Path, help="The pipeline's contracts/workbook/v1.json")
    parser.add_argument("--parquet", required=True, type=Path, help="The synthetic run's Parquet output directory")
    parser.add_argument("--database", required=True, type=Path, help="The DuckDB file dbt builds into")
    parser.add_argument("--schema", required=True, help="The schema the seeds load into (var input_schema)")
    args = parser.parse_args(argv)

    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    steps, missing = replacements(contract, args.parquet)
    if missing:
        print(f"the pipeline run wrote no Parquet for required relation(s): {', '.join(missing)}", file=sys.stderr)
        return 1

    with duckdb.connect(str(args.database)) as conn:
        conn.execute(f'create schema if not exists "{args.schema}"')
        conn.execute("begin")
        for step in steps:
            target = f'"{args.schema}"."{step.table}"'
            if step.parquet is None:
                ddl = ", ".join(f'"{c["name"]}" {c["type"]}' for c in step.columns)
                conn.execute(f"create or replace table {target} ({ddl})")
            else:
                conn.execute(f"create or replace table {target} as select * from read_parquet(?)", [str(step.parquet)])
        conn.execute("commit")

    written = sum(1 for step in steps if step.parquet is not None)
    print(
        f"overlaid {written} pipeline table(s) and emptied {len(steps) - written} optional relation(s) "
        f"from contract {contract.get('contract')} {contract.get('version')} into {args.schema}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
