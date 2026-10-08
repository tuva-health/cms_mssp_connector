"""scripts/check_release_conformance.sh proves a fork carries a release.

A fork conforms to release vX.Y.Z when the tag is an ancestor of the fork's
commit and the two trees differ only in client-specific paths
(config/profiles.yml and .gitignore). The script runs for real against a
throwaway git repository; synthetic names only.
"""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "check_release_conformance.sh"
TAG = "v1.2.3"
CANONICAL_IGNORE = "config/profiles.yml\n"


def git_environment() -> "dict[str, str]":
    environment = dict(os.environ)
    # Hermetic git: no user/system config (signing, hooks, identity guards).
    environment.update(
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_NOSYSTEM="1",
        GIT_AUTHOR_NAME="test",
        GIT_AUTHOR_EMAIL="test@example.com",
        GIT_COMMITTER_NAME="test",
        GIT_COMMITTER_EMAIL="test@example.com",
    )
    return environment


class ReleaseConformanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.repository = Path(self.directory.name)
        self.git("init", "-q", "-b", "main")
        self.commit(
            {"models/a.sql": "select 0\n", "dbt_project.yml": "name: x\n", ".gitignore": CANONICAL_IGNORE},
            "canonical v0",
        )
        self.git("switch", "-q", "-c", "fork-main")
        self.commit(
            {"config/profiles.yml": "fork: {}\n", ".gitignore": "\n"},
            "fork commits its profile",
        )
        self.git("switch", "-q", "main")
        self.commit({"models/a.sql": "select 1\n"}, "canonical v1")
        self.git("tag", "-a", TAG, "-m", TAG)
        self.git("switch", "-q", "fork-main")
        self.git("merge", "-q", "--no-ff", TAG, "-m", "Merge " + TAG)

    def tearDown(self) -> None:
        self.directory.cleanup()

    def git(self, *arguments: str) -> None:
        subprocess.run(
            ["git", *arguments], cwd=self.repository, env=git_environment(),
            check=True, capture_output=True, text=True,
        )

    def commit(self, files: "dict[str, str]", message: str) -> None:
        for name, text in files.items():
            path = self.repository / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)

    def check(self, *arguments: str) -> "subprocess.CompletedProcess[str]":
        return subprocess.run(
            ["sh", str(SCRIPT), *arguments], cwd=self.repository, env=git_environment(),
            capture_output=True, text=True,
        )

    def test_pass_when_only_client_paths_differ(self) -> None:
        result = self.check(TAG)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS", result.stdout)
        self.assertIn("  config/profiles.yml\n", result.stdout)
        self.assertIn("  .gitignore\n", result.stdout)

    def test_fail_names_canonical_paths_the_fork_changed(self) -> None:
        self.commit({"models/a.sql": "select 2\n", "dbt_project.yml": "name: y\n"}, "fork patch")
        result = self.check(TAG)
        self.assertEqual(result.returncode, 1)
        self.assertIn("FAIL", result.stdout)
        self.assertIn("  models/a.sql\n", result.stdout)
        self.assertIn("  dbt_project.yml\n", result.stdout)
        self.assertNotIn("config/profiles.yml", result.stdout)

    def test_fail_when_tag_is_not_an_ancestor(self) -> None:
        self.git("switch", "-q", "--orphan", "rebased")
        self.commit({"models/a.sql": "select 1\n"}, "copied content")
        result = self.check(TAG)
        self.assertEqual(result.returncode, 1)
        self.assertIn("not an ancestor", result.stdout)

    def test_fail_when_head_carries_unreleased_upstream_commits(self) -> None:
        self.git("switch", "-q", "main")
        self.commit({"models/a.sql": "select 3\n"}, "canonical after tag")
        self.git("switch", "-q", "fork-main")
        self.git("merge", "-q", "--no-ff", "main", "-m", "Merge main tip")
        result = self.check(TAG)
        self.assertEqual(result.returncode, 1)
        self.assertIn("  models/a.sql\n", result.stdout)

    def test_fail_when_tag_is_missing(self) -> None:
        result = self.check("v9.9.9")
        self.assertEqual(result.returncode, 1)
        self.assertIn("no tag v9.9.9", result.stdout)

    def test_explicit_rev_is_checked(self) -> None:
        self.commit({"models/a.sql": "select 2\n"}, "fork patch")
        self.assertEqual(self.check(TAG, "HEAD~1").returncode, 0)
        self.assertEqual(self.check(TAG, "HEAD").returncode, 1)


if __name__ == "__main__":
    unittest.main()
