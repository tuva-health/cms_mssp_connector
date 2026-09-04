import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
GENERATOR = REPOSITORY_ROOT / "scripts" / "create_release_metadata.py"
BUILD_RELEASE_IMAGE = REPOSITORY_ROOT / "scripts" / "build_release_image.sh"

# Neutral release identifiers standing in for client release evidence.
RELEASE_ID = "2026-08-22.1"
IMAGE_REFERENCE = "registry.example.com/mssp-connector@sha256:" + "b" * 64


class ReleaseContractTests(unittest.TestCase):
    def fake_docker_environment(self, directory: str, image_metadata: Path) -> "dict[str, str]":
        binary_directory = Path(directory) / "bin"
        binary_directory.mkdir()
        docker = binary_directory / "docker"
        docker.write_text(
            "#!/bin/sh\n"
            "case \"$1\" in\n"
            "  pull) [ \"$2\" = --platform ] && [ \"$3\" = linux/amd64 ] ;;\n"
            "  create) [ \"$2\" = --platform ] && [ \"$3\" = linux/amd64 ] && printf 'test-container\\n' ;;\n"
            "  cp) /bin/cp \"$FAKE_IMAGE_METADATA\" \"$3\" ;;\n"
            "  rm) exit 0 ;;\n"
            "  *) exit 1 ;;\n"
            "esac\n",
            encoding="ascii",
        )
        docker.chmod(0o755)
        return {
            **os.environ,
            "FAKE_IMAGE_METADATA": str(image_metadata),
            "PATH": f"{binary_directory}:{os.environ['PATH']}",
        }

    def test_metadata_records_all_immutable_release_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image_metadata = Path(directory) / "image.json"
            release_metadata = Path(directory) / "release.json"
            dev_manifest = Path(directory) / "dev-manifest.json"
            prod_manifest = Path(directory) / "prod-manifest.json"
            dev_manifest.write_text(
                '{"metadata":{"dbt_version":"1.11.14"},"target":"dev"}\n',
                encoding="ascii",
            )
            prod_manifest.write_text(
                '{"metadata":{"dbt_version":"1.11.14"},"target":"prod"}\n',
                encoding="ascii",
            )
            manifest_sha256 = {
                "dev": hashlib.sha256(dev_manifest.read_bytes()).hexdigest(),
                "prod": hashlib.sha256(prod_manifest.read_bytes()).hexdigest(),
            }
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "image",
                    "--dev-manifest",
                    str(dev_manifest),
                    "--prod-manifest",
                    str(prod_manifest),
                    "--source-commit",
                    "a" * 40,
                    "--release-id",
                    RELEASE_ID,
                    "--output",
                    str(image_metadata),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            image_metadata_sha256 = hashlib.sha256(image_metadata.read_bytes()).hexdigest()
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "release",
                    "--image-reference",
                    IMAGE_REFERENCE,
                    "--output",
                    str(release_metadata),
                ],
                text=True,
                capture_output=True,
                env=self.fake_docker_environment(directory, image_metadata),
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            metadata = json.loads(release_metadata.read_text(encoding="ascii"))

        self.assertEqual(metadata["source_commit"], "a" * 40)
        self.assertEqual(metadata["release_id"], RELEASE_ID)
        self.assertEqual(metadata["ecr_digest"], "sha256:" + "b" * 64)
        self.assertEqual(metadata["image_reference"], IMAGE_REFERENCE)
        self.assertEqual(metadata["image_metadata_sha256"], image_metadata_sha256)
        self.assertEqual(
            metadata["manifest_sha256"],
            manifest_sha256,
        )
        self.assertEqual(
            metadata["dependency_sha256"],
            {
                "package-lock.yml": hashlib.sha256(
                    (REPOSITORY_ROOT / "package-lock.yml").read_bytes()
                ).hexdigest(),
                "uv.lock": hashlib.sha256(
                    (REPOSITORY_ROOT / "uv.lock").read_bytes()
                ).hexdigest(),
            },
        )
        self.assertEqual(
            metadata["command_contract"],
            {
                "build": ["dbt seed", "dbt snapshot", "dbt run"],
                "test": ["dbt test"],
            },
        )

    def test_rejects_mutable_or_malformed_release_identifiers(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            dev_manifest = Path(directory) / "dev-manifest.json"
            prod_manifest = Path(directory) / "prod-manifest.json"
            dev_manifest.write_text("{}", encoding="ascii")
            prod_manifest.write_text("{}", encoding="ascii")
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "image",
                    "--dev-manifest",
                    str(dev_manifest),
                    "--prod-manifest",
                    str(prod_manifest),
                    "--source-commit",
                    "main",
                    "--release-id",
                    "candidate",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
        self.assertNotEqual(result.returncode, 0)

    def test_release_rejects_a_mutable_digest_or_untrusted_metadata_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            image_metadata = Path(directory) / "image.json"
            image_metadata.write_text('{"source_commit":"untrusted"}\n', encoding="ascii")
            result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "release",
                    "--image-reference",
                    "latest",
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            invalid_metadata_result = subprocess.run(
                [
                    sys.executable,
                    str(GENERATOR),
                    "release",
                    "--image-reference",
                    "repository@sha256:" + "b" * 64,
                ],
                text=True,
                capture_output=True,
                env=self.fake_docker_environment(directory, image_metadata),
                check=False,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertNotEqual(invalid_metadata_result.returncode, 0)

    def test_runtime_image_has_no_dependency_installer(self) -> None:
        dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="ascii")

        self.assertIn("AS build", dockerfile)
        runtime = dockerfile.split("FROM python:", 2)[-1]
        self.assertNotIn("COPY --from=uv", runtime)
        self.assertNotIn("apt-get install", runtime)
        self.assertIn("rm -rf /usr/local/lib/python3.10/site-packages/pip", runtime)
        self.assertIn("COPY --from=build /app/.venv /app/.venv", runtime)
        self.assertIn(
            "COPY --from=build /app/dbt_packages /app/dbt_packages",
            runtime,
        )
        self.assertNotIn("/app/packages.yml", runtime)
        self.assertNotIn("/app/package-lock.yml", runtime)
        self.assertIn("/app/target/release-metadata.json /app/release-metadata.json", runtime)
        self.assertIn("COPY --from=build --chown=dbt:dbt /app/target/manifest.json", runtime)
        self.assertIn(
            "COPY --from=build --chown=dbt:dbt /app/target/prod/manifest.json", runtime
        )

    def test_runtime_image_verifies_writable_dbt_paths(self) -> None:
        dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="ascii")
        runtime = dockerfile.split("FROM python:", 2)[-1]

        self.assertIn("DBT_LOG_PATH=/tmp/dbt-logs", runtime)
        self.assertEqual(dockerfile.count("DBT_SEND_ANONYMOUS_USAGE_STATS=false"), 2)
        self.assertIn("USER dbt", runtime)
        self.assertIn("RUN test ! -w /app", runtime)
        self.assertIn("test ! -w /app/config", runtime)
        self.assertIn("test ! -w /app/models", runtime)
        self.assertIn("test ! -w /app/scripts", runtime)
        self.assertIn("test -w /app/target", runtime)
        self.assertIn('test ! -e "$DBT_LOG_PATH"', runtime)
        self.assertIn("> /tmp/runtime-smoke-output 2>&1", runtime)
        self.assertIn("test -s /tmp/runtime-smoke-output", runtime)
        self.assertIn('test -w "$DBT_LOG_PATH"', runtime)
        self.assertIn("dbt parse --target dev --target-path /tmp/runtime-smoke-target", runtime)
        self.assertIn("cat /tmp/runtime-smoke-output", runtime)
        self.assertGreaterEqual(runtime.count("test ! -e /app/config/.user.yml"), 2)

    def test_runtime_image_keeps_owned_inputs_read_only(self) -> None:
        dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="ascii")
        runtime = dockerfile.split("FROM python:", 2)[-1]

        self.assertIn(
            "COPY --from=build /app/config/profiles.yml /app/config/profiles.yml",
            runtime,
        )
        for path in ("analyses", "macros", "models", "scripts", "seeds", "snapshots"):
            self.assertIn(f"COPY --from=build /app/{path} /app/{path}", runtime)
            self.assertNotIn(f"COPY --from=build --chown=dbt:dbt /app/{path}", runtime)

    def test_ci_workflow_pins_the_dockerfile_uv_release(self) -> None:
        dockerfile = (REPOSITORY_ROOT / "Dockerfile").read_text(encoding="ascii")
        workflow = (REPOSITORY_ROOT / ".github" / "workflows" / "ci.yml").read_text(
            encoding="ascii"
        )
        uv_image = re.search(r"^FROM ghcr\.io/astral-sh/uv:([0-9.]+)@sha256:", dockerfile, re.MULTILINE)
        uv_workflow = re.search(r'^  UV_VERSION: "([0-9.]+)"$', workflow, re.MULTILINE)

        self.assertIsNotNone(uv_image)
        self.assertIsNotNone(uv_workflow)
        self.assertEqual(uv_workflow.group(1), uv_image.group(1))

    def test_release_evidence_and_agent_tooling_do_not_dirty_the_clone(self) -> None:
        ignored = (REPOSITORY_ROOT / ".gitignore").read_text(encoding="ascii").splitlines()

        for path in (".claude", ".pi/", "release-metadata/"):
            self.assertIn(path, ignored)


ECR_DIGEST = "sha256:" + "b" * 64
REPOSITORY = "123456789012.dkr.ecr.us-west-2.amazonaws.com/mssp-connector"


class ReleaseBuilderTests(unittest.TestCase):
    """Behavioral contract of scripts/build_release_image.sh.

    The builder runs in a throwaway git clone with fake docker/aws on PATH, so
    the assertions cover the guard, the build, the push and the digest capture
    without a registry. Each clone starts with origin/main at HEAD.
    """

    def setUp(self) -> None:
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.root = self.directory / "clone"
        (self.root / "scripts").mkdir(parents=True)
        for script in (BUILD_RELEASE_IMAGE, GENERATOR):
            target = self.root / "scripts" / script.name
            target.write_bytes(script.read_bytes())
            target.chmod(0o755)
        self.git("init", "--quiet", "--initial-branch=main")
        self.git("config", "user.email", "release@example.com")
        self.git("config", "user.name", "Release Contract")
        (self.root / "README.md").write_text("connector\n", encoding="ascii")
        (self.root / ".gitignore").write_text(
            "ignored-tooling/\nrelease-metadata/\n", encoding="ascii"
        )
        self.git("add", "README.md", ".gitignore", "scripts")
        self.git("commit", "--quiet", "--message", "initial")
        self.head = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", self.head)
        self.call_log = self.directory / "calls.log"
        self.image_metadata = self.directory / "image-metadata.json"
        self.write_image_metadata(self.head)
        self.write_fake_tools()

    def git(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.root), *arguments],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def commit(self, message: str) -> str:
        (self.root / "README.md").write_text(message + "\n", encoding="ascii")
        self.git("commit", "--quiet", "--all", "--message", message)
        head = self.git("rev-parse", "HEAD")
        self.write_image_metadata(head)
        return head

    def write_image_metadata(self, source_commit: str) -> None:
        self.image_metadata.write_text(
            json.dumps(
                {
                    "command_contract": {
                        "build": ["dbt seed", "dbt snapshot", "dbt run"],
                        "test": ["dbt test"],
                    },
                    "dependency_sha256": {"package-lock.yml": "c" * 64, "uv.lock": "d" * 64},
                    "manifest_sha256": {"dev": "e" * 64, "prod": "f" * 64},
                    "release_id": RELEASE_ID,
                    "source_commit": source_commit,
                }
            )
            + "\n",
            encoding="ascii",
        )

    def write_fake_tools(self) -> None:
        binary_directory = self.directory / "bin"
        binary_directory.mkdir()
        fakes = {
            "docker": (
                "#!/bin/sh\n"
                "printf 'docker %s\\n' \"$*\" >> \"$FAKE_CALL_LOG\"\n"
                "case \"$1\" in\n"
                "  login) cat >/dev/null ;;\n"
                "  build|push|pull|rm) exit 0 ;;\n"
                "  create) printf 'test-container\\n' ;;\n"
                "  cp) /bin/cp \"$FAKE_IMAGE_METADATA\" \"$3\" ;;\n"
                "  *) exit 1 ;;\n"
                "esac\n"
            ),
            "aws": (
                "#!/bin/sh\n"
                "printf 'aws %s\\n' \"$*\" >> \"$FAKE_CALL_LOG\"\n"
                "case \"$2\" in\n"
                "  get-login-password) printf 'fake-token\\n' ;;\n"
                "  describe-repositories) printf '%s\\n' \"${FAKE_TAG_MUTABILITY:-IMMUTABLE}\" ;;\n"
                "  describe-images) printf '%s\\n' \"$FAKE_ECR_DIGEST\" ;;\n"
                "  *) exit 1 ;;\n"
                "esac\n"
            ),
            "python3": (
                "#!/bin/sh\n"
                "[ -z \"${FAKE_PYTHON_TOO_OLD:-}\" ] || exit 1\n"
                "exec \"$FAKE_PYTHON\" \"$@\"\n"
            ),
        }
        for name, body in fakes.items():
            fake = binary_directory / name
            fake.write_text(body, encoding="ascii")
            fake.chmod(0o755)
        self.environment = {
            **os.environ,
            "FAKE_CALL_LOG": str(self.call_log),
            "FAKE_ECR_DIGEST": ECR_DIGEST,
            "FAKE_IMAGE_METADATA": str(self.image_metadata),
            "FAKE_PYTHON": sys.executable,
            "PATH": f"{binary_directory}:{os.environ['PATH']}",
        }
        self.environment.pop("RELEASE_REF", None)

    def run_builder(
        self, *arguments: str, **environment: str
    ) -> "subprocess.CompletedProcess[str]":
        self.call_log.write_text("", encoding="ascii")
        return subprocess.run(
            [str(self.root / "scripts" / "build_release_image.sh"), *arguments],
            env={**self.environment, **environment},
            text=True,
            capture_output=True,
            check=False,
        )

    def calls(self) -> "list[str]":
        return self.call_log.read_text(encoding="ascii").splitlines()

    def test_guard_accepts_a_configured_release_reference(self) -> None:
        head = self.commit("advance past origin/main")
        self.git("update-ref", "refs/remotes/canonical-local/main", head)

        result = self.run_builder(REPOSITORY, RELEASE_ID, RELEASE_REF="canonical-local/main")

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        build = [call for call in self.calls() if call.startswith("docker build ")]
        self.assertEqual(len(build), 1, self.calls())
        self.assertIn("--platform linux/amd64", build[0])
        self.assertIn(f"--build-arg SOURCE_COMMIT={head}", build[0])
        self.assertIn(f"--build-arg RELEASE_ID={RELEASE_ID}", build[0])
        self.assertIn(f"--tag {REPOSITORY}:{RELEASE_ID}", build[0])

    def test_guard_rejects_source_that_is_not_the_release_reference(self) -> None:
        head = self.commit("advance past origin/main")

        default_ref = self.run_builder(REPOSITORY, RELEASE_ID)
        stale_ref = self.run_builder(REPOSITORY, RELEASE_ID, RELEASE_REF="origin/main")
        exact_commit = self.run_builder(REPOSITORY, RELEASE_ID, RELEASE_REF=head)
        unknown_ref = self.run_builder(REPOSITORY, RELEASE_ID, RELEASE_REF="no-such-remote/main")

        self.assertNotEqual(default_ref.returncode, 0)
        self.assertIn("origin/main", default_ref.stderr)
        self.assertNotEqual(stale_ref.returncode, 0)
        self.assertEqual(exact_commit.returncode, 0, exact_commit.stderr)
        self.assertNotEqual(unknown_ref.returncode, 0)
        self.assertIn("RELEASE_REF", unknown_ref.stderr)

    def test_clean_check_ignores_excluded_tooling_but_not_source_changes(self) -> None:
        tooling = self.root / "ignored-tooling"
        tooling.mkdir()
        (tooling / "extension.ts").write_text("export {}\n", encoding="ascii")

        clean = self.run_builder(REPOSITORY, RELEASE_ID)
        (self.root / "README.md").write_text("edited\n", encoding="ascii")
        modified = self.run_builder(REPOSITORY, RELEASE_ID)
        self.git("checkout", "--", "README.md")
        (self.root / "stray.sql").write_text("select 1\n", encoding="ascii")
        untracked = self.run_builder(REPOSITORY, RELEASE_ID)

        self.assertEqual(clean.returncode, 0, clean.stderr)
        self.assertNotEqual(modified.returncode, 0)
        self.assertNotEqual(untracked.returncode, 0)

    def test_release_pushes_and_binds_the_immutable_digest(self) -> None:
        result = self.run_builder(REPOSITORY, RELEASE_ID)

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.calls()
        image_reference = f"{REPOSITORY}@{ECR_DIGEST}"
        self.assertIn(f"docker push {REPOSITORY}:{RELEASE_ID}", calls)
        self.assertIn(
            "aws ecr describe-repositories --repository-names mssp-connector"
            " --region us-west-2 --query repositories[0].imageTagMutability --output text",
            calls,
        )
        self.assertIn(
            f"aws ecr describe-images --repository-name mssp-connector --region us-west-2"
            f" --image-ids imageTag={RELEASE_ID}"
            " --query imageDetails[0].imageDigest --output text",
            calls,
        )
        self.assertLess(
            calls.index(f"docker push {REPOSITORY}:{RELEASE_ID}"),
            calls.index(f"docker pull --platform linux/amd64 {image_reference}"),
        )
        self.assertIn(image_reference, result.stdout)
        metadata = json.loads(
            (self.root / "release-metadata" / f"{RELEASE_ID}.json").read_text(encoding="ascii")
        )
        self.assertEqual(metadata["image_reference"], image_reference)
        self.assertEqual(metadata["ecr_digest"], ECR_DIGEST)
        self.assertEqual(metadata["source_commit"], self.head)
        self.assertEqual(metadata["release_id"], RELEASE_ID)

    def test_release_refuses_mutable_tags_and_malformed_identifiers(self) -> None:
        mutable_repository = self.run_builder(
            REPOSITORY, RELEASE_ID, FAKE_TAG_MUTABILITY="MUTABLE"
        )
        mutable_calls = self.calls()
        bad_digest = self.run_builder(REPOSITORY, RELEASE_ID, FAKE_ECR_DIGEST="None")
        tagged_repository = self.run_builder(f"{REPOSITORY}:{RELEASE_ID}", RELEASE_ID)
        bad_release_id = self.run_builder(REPOSITORY, "latest tag")

        self.assertNotEqual(mutable_repository.returncode, 0)
        self.assertIn("IMMUTABLE", mutable_repository.stderr)
        self.assertFalse([call for call in mutable_calls if call.startswith("docker ")])
        self.assertNotEqual(bad_digest.returncode, 0)
        self.assertNotEqual(tagged_repository.returncode, 0)
        self.assertNotEqual(bad_release_id.returncode, 0)
        self.assertFalse((self.root / "release-metadata").exists())

    def test_release_checks_the_interpreter_before_anything_is_pushed(self) -> None:
        result = self.run_builder(REPOSITORY, RELEASE_ID, FAKE_PYTHON_TOO_OLD="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("uv run --frozen", result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
