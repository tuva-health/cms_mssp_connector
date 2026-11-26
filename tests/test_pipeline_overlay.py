"""Behavioral contract of scripts/pipeline_overlay.py (TUVA-163).

The overlay is the step of scripts/dbt-pipeline-e2e that swaps the seeded
workbook relations for the tables cms_mssp_pipeline's synthetic run wrote.
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import duckdb

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
OVERLAY = REPOSITORY_ROOT / "scripts" / "pipeline_overlay.py"

CELL_COLUMNS = [
    {"name": "row_num", "type": "BIGINT"},
    {"name": "value_text", "type": "VARCHAR"},
    {"name": "aco_id", "type": "VARCHAR"},
]


def contract_with(*relations: tuple[str, bool]) -> dict:
    return {
        "contract": "cms-mssp-workbook-export",
        "version": "9.9.9",
        "schemas": {"cell": {"columns": CELL_COLUMNS}},
        "relations": [
            {"table": table, "schema": "cell", "optional": optional}
            for table, optional in relations
        ],
    }


class PipelineOverlayTest(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.parquet = self.tmp / "parquet"
        self.parquet.mkdir()
        self.database = self.tmp / "cms_mssp_connector_ci.duckdb"
        with duckdb.connect(str(self.database)) as conn:
            conn.execute("create schema raw")
            # Seeded fixtures: a workbook relation and a non-workbook table.
            conn.execute(
                "create table raw.bnmrk_table_1 as "
                "select 1::bigint as row_num, 'seeded' as value_text, 'SEED' as aco_id"
            )
            conn.execute("create table raw.bnmrk_table_6 as select 'SEED' as aco_id")
            conn.execute("create table raw.aalr1_assigned_beneficiaries as select 'SEED' as aco_id")

    def write_parquet(self, table: str, sql: str) -> None:
        with duckdb.connect() as conn:
            conn.execute(f"copy ({sql}) to '{self.parquet / (table + '.parquet')}' (format parquet)")

    def run_overlay(self, spec: dict) -> subprocess.CompletedProcess:
        contract_path = self.tmp / "v1.json"
        contract_path.write_text(json.dumps(spec), encoding="utf-8")
        return subprocess.run(
            [
                sys.executable, str(OVERLAY),
                "--contract", str(contract_path),
                "--parquet", str(self.parquet),
                "--database", str(self.database),
                "--schema", "raw",
            ],
            capture_output=True, text=True, check=False,
        )

    def query(self, sql: str) -> list[tuple]:
        with duckdb.connect(str(self.database), read_only=True) as conn:
            return conn.execute(sql).fetchall()

    def test_pipeline_rows_replace_the_seeded_workbook_relation(self) -> None:
        self.write_parquet("bnmrk_table_1", "select 7::bigint as row_num, 'piped' as value_text, 'PIPE' as aco_id")
        self.write_parquet("bnmrk_table_6", "select 1::bigint as row_num, 'x' as value_text, 'PIPE' as aco_id")

        result = self.run_overlay(contract_with(("bnmrk_table_1", False), ("bnmrk_table_6", True)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.query("select * from raw.bnmrk_table_1"), [(7, "piped", "PIPE")])
        self.assertEqual(self.query("select * from raw.bnmrk_table_6"), [(1, "x", "PIPE")])

    def test_a_relation_the_seeds_lack_is_created(self) -> None:
        self.write_parquet("stlmt_table_1", "select 1::bigint as row_num, 'v' as value_text, 'PIPE' as aco_id")

        result = self.run_overlay(contract_with(("stlmt_table_1", False)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.query("select aco_id from raw.stlmt_table_1"), [("PIPE",)])

    def test_tables_outside_the_contract_keep_their_seeds(self) -> None:
        self.write_parquet("bnmrk_table_1", "select 7::bigint as row_num, 'piped' as value_text, 'PIPE' as aco_id")
        # The pipeline also writes CCLF tables; the overlay must not take them.
        self.write_parquet("aalr1_assigned_beneficiaries", "select 'PIPE' as aco_id")

        result = self.run_overlay(contract_with(("bnmrk_table_1", False)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.query("select aco_id from raw.aalr1_assigned_beneficiaries"), [("SEED",)])

    def test_an_optional_relation_the_run_did_not_write_is_emptied_not_left_seeded(self) -> None:
        self.write_parquet("bnmrk_table_1", "select 7::bigint as row_num, 'piped' as value_text, 'PIPE' as aco_id")

        result = self.run_overlay(contract_with(("bnmrk_table_1", False), ("bnmrk_table_6", True)))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.query("select count(*) from raw.bnmrk_table_6"), [(0,)])
        self.assertEqual(
            [name for name, in self.query(
                "select column_name from information_schema.columns "
                "where table_schema = 'raw' and table_name = 'bnmrk_table_6' order by ordinal_position"
            )],
            ["row_num", "value_text", "aco_id"],
        )

    def test_a_required_relation_the_run_did_not_write_fails_the_overlay(self) -> None:
        result = self.run_overlay(contract_with(("bnmrk_table_1", False)))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("bnmrk_table_1", result.stderr)
        self.assertEqual(self.query("select aco_id from raw.bnmrk_table_1"), [("SEED",)])


if __name__ == "__main__":
    unittest.main()
