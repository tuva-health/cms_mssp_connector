#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
COMMIT = re.compile(r"[0-9a-f]{40}")
SHA256 = re.compile(r"[0-9a-f]{64}")
IMAGE_REFERENCE = re.compile(r"[^@\s]+@(?P<digest>sha256:[0-9a-f]{64})")
COMMAND_CONTRACT = {
    "build": ["dbt seed", "dbt snapshot", "dbt run"],
    "test": ["dbt test"],
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_metadata(content: dict, output: Path | None) -> None:
    serialized = json.dumps(content, indent=2, sort_keys=True) + "\n"
    if output:
        output.write_text(serialized, encoding="ascii")
    else:
        sys.stdout.write(serialized)


def create_image_metadata(args: argparse.Namespace) -> int:
    errors = []
    if not COMMIT.fullmatch(args.source_commit):
        errors.append("source commit must be a full lowercase Git commit ID")
    if not args.release_id.strip():
        errors.append("release ID must not be empty")
    for path in (
        args.dev_manifest,
        args.prod_manifest,
        REPOSITORY_ROOT / "package-lock.yml",
        REPOSITORY_ROOT / "uv.lock",
    ):
        if not path.is_file():
            errors.append(f"release input is missing: {path}")
    if errors:
        for error in errors:
            print("ERROR: " + error, file=sys.stderr)
        return 1

    write_metadata(
        {
        "command_contract": COMMAND_CONTRACT,
        "dependency_sha256": {
            "package-lock.yml": sha256(REPOSITORY_ROOT / "package-lock.yml"),
            "uv.lock": sha256(REPOSITORY_ROOT / "uv.lock"),
        },
        "manifest_sha256": {
            "dev": sha256(args.dev_manifest),
            "prod": sha256(args.prod_manifest),
        },
        "release_id": args.release_id,
        "source_commit": args.source_commit,
        },
        args.output,
    )
    return 0


def create_release_metadata(args: argparse.Namespace) -> int:
    reference = IMAGE_REFERENCE.fullmatch(args.image_reference)
    if reference is None:
        print("ERROR: image reference must use repository@sha256:digest", file=sys.stderr)
        return 1
    container_id = ""
    try:
        subprocess.run(
            ["docker", "pull", "--platform", "linux/amd64", args.image_reference],
            check=True,
        )
        container_id = subprocess.run(
            ["docker", "create", "--platform", "linux/amd64", args.image_reference],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        with tempfile.TemporaryDirectory() as directory:
            image_metadata = Path(directory) / "release-metadata.json"
            subprocess.run(
                ["docker", "cp", f"{container_id}:/app/release-metadata.json", str(image_metadata)],
                check=True,
            )
            metadata_sha256 = sha256(image_metadata)
            metadata = json.loads(image_metadata.read_text(encoding="ascii"))
    except (OSError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print(f"ERROR: cannot extract digest-addressed image metadata: {error}", file=sys.stderr)
        return 1
    finally:
        if container_id:
            subprocess.run(
                ["docker", "rm", "--force", container_id],
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
    required = {
        "command_contract",
        "dependency_sha256",
        "manifest_sha256",
        "release_id",
        "source_commit",
    }
    if set(metadata) != required:
        print("ERROR: image metadata does not match the release contract", file=sys.stderr)
        return 1
    dependency_sha256 = metadata.get("dependency_sha256", {})
    manifest_sha256 = metadata.get("manifest_sha256", {})
    if (
        not COMMIT.fullmatch(metadata.get("source_commit", ""))
        or not str(metadata.get("release_id", "")).strip()
        or metadata.get("command_contract") != COMMAND_CONTRACT
        or set(dependency_sha256) != {"package-lock.yml", "uv.lock"}
        or set(manifest_sha256) != {"dev", "prod"}
        or not all(SHA256.fullmatch(value) for value in dependency_sha256.values())
        or not all(SHA256.fullmatch(value) for value in manifest_sha256.values())
    ):
        print("ERROR: image metadata values do not match the release contract", file=sys.stderr)
        return 1
    metadata["image_metadata_sha256"] = metadata_sha256
    metadata["image_reference"] = args.image_reference
    metadata["ecr_digest"] = reference.group("digest")
    write_metadata(metadata, args.output)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Record immutable connector release metadata")
    modes = parser.add_subparsers(dest="mode", required=True)

    image = modes.add_parser("image", help="create metadata baked into the image")
    image.add_argument("--dev-manifest", type=Path, required=True)
    image.add_argument("--prod-manifest", type=Path, required=True)
    image.add_argument("--source-commit", required=True)
    image.add_argument("--release-id", required=True)
    image.add_argument("--output", type=Path)
    image.set_defaults(handler=create_image_metadata)

    release = modes.add_parser("release", help="bind baked metadata to an ECR digest")
    release.add_argument("--image-reference", required=True)
    release.add_argument("--output", type=Path)
    release.set_defaults(handler=create_release_metadata)

    args = parser.parse_args()
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main())
