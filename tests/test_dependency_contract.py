import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def locked_version(package: str) -> str:
    lock = (REPOSITORY_ROOT / "uv.lock").read_text(encoding="utf-8")
    match = re.search(
        rf'^name = "{re.escape(package)}"\nversion = "([^"]+)"$',
        lock,
        re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"{package} is missing from uv.lock")
    return match.group(1)


class DependencyContractTests(unittest.TestCase):
    def test_runtime_dependency_inputs_enforce_security_floors(self) -> None:
        pyproject = (REPOSITORY_ROOT / "pyproject.toml").read_text(encoding="utf-8")
        requirements = (REPOSITORY_ROOT / "requirements.txt").read_text(encoding="utf-8")

        for dependency in ("sqlparse>=0.6.0", "urllib3>=2.5.0"):
            self.assertIn(f'"{dependency}"', pyproject)
            self.assertIn(dependency, requirements.splitlines())

        self.assertGreaterEqual(tuple(map(int, locked_version("sqlparse").split("."))), (0, 6, 0))
        self.assertGreaterEqual(tuple(map(int, locked_version("urllib3").split("."))), (2, 5, 0))

    def test_fixed_runtime_packages_remain_pinned(self) -> None:
        pyproject = (REPOSITORY_ROOT / "pyproject.toml").read_text(encoding="utf-8")
        fixed_packages = {
            "dbt-core": "1.11.14",
            "dbt-duckdb": "1.10.1",
            "duckdb": "1.4.3",
            "dbt-snowflake": "1.10.7",
        }

        for package, version in fixed_packages.items():
            self.assertIn(f'"{package}=={version}"', pyproject)
            self.assertEqual(locked_version(package), version)


if __name__ == "__main__":
    unittest.main()
