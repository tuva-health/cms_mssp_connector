import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
RUN_DBT = REPOSITORY_ROOT / "scripts" / "run_dbt.sh"

# Neutral target -> database / input-schema values standing in for the
# client-specific runtime overlay. The generic entrypoint reads these from the
# environment; no identity is baked into the reviewed tree.
DEV_DATABASE = "ANALYTICS_DEV"
PROD_DATABASE = "ANALYTICS_PROD"
INPUT_SCHEMA = "SOURCE_DATA"


class RuntimeContractTests(unittest.TestCase):
    def invoke(
        self,
        environment: str,
        phase: str,
        failing_command: str = "",
        dbt_output: str = "",
    ) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as directory:
            dbt = Path(directory) / "dbt"
            dbt.write_text(
                "#!/bin/sh\n"
                "printf 'dbt'\n"
                "printf ' %s' \"$@\"\n"
                "printf '\\n'\n"
                "[ -z \"${DBT_OUTPUT:-}\" ] || printf '%s\\n' \"$DBT_OUTPUT\"\n"
                "[ \"${FAIL_DBT_COMMAND:-}\" != \"$1\" ]\n",
                encoding="ascii",
            )
            dbt.chmod(0o755)
            env = {
                **os.environ,
                "DBT_OUTPUT": dbt_output,
                "FAIL_DBT_COMMAND": failing_command,
                "MSSP_DEV_DATABASE": DEV_DATABASE,
                "MSSP_PROD_DATABASE": PROD_DATABASE,
                "MSSP_INPUT_SCHEMA": INPUT_SCHEMA,
                "PATH": f"{directory}:{os.environ['PATH']}",
            }
            return subprocess.run(
                [str(RUN_DBT), environment, phase],
                cwd=REPOSITORY_ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

    def test_dev_build_has_fixed_target_and_source_boundary(self) -> None:
        result = self.invoke("dev", "build")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                f"dbt seed --target dev --vars {{input_database: {DEV_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
                f"dbt snapshot --target dev --vars {{input_database: {DEV_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
                f"dbt run --target dev --vars {{input_database: {DEV_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
            ],
        )

    def test_prod_tests_have_fixed_target_and_source_boundary(self) -> None:
        result = self.invoke("prod", "test")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                f"dbt test --target prod --vars {{input_database: {PROD_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
            ],
        )

    def test_build_stops_when_a_model_command_fails(self) -> None:
        result = self.invoke("prod", "build", failing_command="run")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                f"dbt seed --target prod --vars {{input_database: {PROD_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
                f"dbt snapshot --target prod --vars {{input_database: {PROD_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
                f"dbt run --target prod --vars {{input_database: {PROD_DATABASE}, input_schema: {INPUT_SCHEMA}}}",
            ],
        )

    def test_test_results_remain_visible_and_preserve_dbt_status(self) -> None:
        warning = self.invoke("dev", "test", dbt_output="WARN 1 warning-severity test")
        error = self.invoke("dev", "test", failing_command="test")

        self.assertIn("WARN 1 warning-severity test", warning.stdout)
        self.assertEqual(warning.returncode, 0)
        self.assertIn("dbt test", error.stdout)
        self.assertNotEqual(error.returncode, 0)

    def test_rejects_commands_outside_the_contract(self) -> None:
        result = self.invoke("prod", "run-operation")

        self.assertEqual(result.returncode, 64)
        self.assertIn("usage:", result.stderr)

    def test_requires_the_runtime_overlay_to_supply_target_database(self) -> None:
        env = {
            key: value
            for key, value in os.environ.items()
            if key not in {"MSSP_DEV_DATABASE", "MSSP_PROD_DATABASE", "MSSP_INPUT_SCHEMA"}
        }
        result = subprocess.run(
            [str(RUN_DBT), "dev", "build"],
            cwd=REPOSITORY_ROOT,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
