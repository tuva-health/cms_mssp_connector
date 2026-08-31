import hashlib
import json
import os
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

    def test_release_builder_requires_clean_canonical_source_and_bakes_identity(self) -> None:
        builder = BUILD_RELEASE_IMAGE.read_text(encoding="ascii")

        self.assertIn("git status --porcelain", builder)
        self.assertIn("git rev-parse refs/remotes/origin/main", builder)
        self.assertIn('if [ "$source_commit" != "$canonical_commit" ]', builder)
        self.assertIn("--platform linux/amd64", builder)
        self.assertIn('--build-arg "SOURCE_COMMIT=$source_commit"', builder)
        self.assertIn('--build-arg "RELEASE_ID=$release_id"', builder)


if __name__ == "__main__":
    unittest.main()
