#!/usr/bin/env python3
"""Release-notes helper for .github/workflows/release.yml.

``changelog VERSION``
    Print the body of the ``## [VERSION]`` section of CHANGELOG.md. Exits
    non-zero when the section is missing or empty, so a tag cannot be released
    without a changelog entry.

``notes --tag TAG --records DIR [--digests-out FILE]``
    Print the GitHub Release body for TAG from the build records that
    scripts/build_image.sh wrote into DIR (``build-record-<tag>.json`` and
    ``build-record-<tag>-rebuild.json`` for the reproducibility rebuild), the
    workbook contract pinned in pyproject.toml, and the CHANGELOG section.
    Optionally write the same digests as JSON (a release asset).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python 3.10, the project floor
    tomllib = None

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
# Client-facing adoption path (the pipeline repository owns the consumption doc).
CONSUMPTION_DOC_URL = (
    "https://github.com/tuva-health/cms_mssp_pipeline/blob/main/docs/client-release-consumption.md"
)


def changelog_section(version: str) -> str:
    heading = f"## [{version}]"
    lines = (REPOSITORY_ROOT / "CHANGELOG.md").read_text(encoding="utf-8").splitlines()
    body = None
    for line in lines:
        if body is None:
            if line.startswith(heading):
                body = []
            continue
        if line.startswith("## ["):
            break
        body.append(line)
    text = "\n".join(body or []).strip()
    if not text:
        raise SystemExit(f"CHANGELOG.md has no non-empty section {heading}")
    return text


def workbook_contract() -> dict:
    if tomllib is None:
        raise SystemExit("reading pyproject.toml needs Python 3.11+ (tomllib)")
    with (REPOSITORY_ROOT / "pyproject.toml").open("rb") as handle:
        project = tomllib.load(handle)
    contract = project["tool"]["cms_mssp_connector"]["workbook_contract"]
    if set(contract) != {"contract", "version"}:
        raise SystemExit("[tool.cms_mssp_connector] workbook_contract needs contract and version")
    return contract


def load_records(directory: Path, tag: str) -> "tuple[dict, dict | None]":
    def load(name: str) -> "dict | None":
        path = directory / name
        if not path.is_file():
            return None
        record = json.loads(path.read_text(encoding="ascii"))
        if record.get("release_id") != tag:
            raise SystemExit(f"{name}: release_id {record.get('release_id')!r} != {tag}")
        return record

    first = load(f"build-record-{tag}.json")
    if first is None:
        raise SystemExit(f"no build record for {tag} in {directory}")
    return first, load(f"build-record-{tag}-rebuild.json")


def rebuild_check(first: dict, rebuild: "dict | None") -> "dict | None":
    if rebuild is None:
        return None
    return {
        "config_digest_match": first["config_digest"] == rebuild["config_digest"],
        "manifest_digest_match": first["manifest_digest"] == rebuild["manifest_digest"],
        "rebuild": {k: rebuild[k] for k in ("config_digest", "manifest_digest")},
    }


def render(tag: str, record: dict, metadata: dict, check: "dict | None", contract: dict) -> str:
    out = [
        f"Pre-release of `{tag}`. It stays a pre-release until a client deployment "
        "reports a green dev sequence against it.",
        "",
        f"- **Source commit:** `{record['source_commit']}`",
        f"- **Workbook contract:** `{contract['contract']}` {contract['version']} "
        "(the `cms_mssp_pipeline` export this release reads)",
        f"- **Dependencies:** `uv.lock` sha256 `{metadata['dependency_sha256']['uv.lock']}`, "
        f"`package-lock.yml` sha256 `{metadata['dependency_sha256']['package-lock.yml']}`",
        f"- **SOURCE_DATE_EPOCH:** `{record['source_date_epoch']}` (commit time)",
        "",
        "## Recorded image digests",
        "",
        "Built in CI by `scripts/build_image.sh` for `linux/amd64` with the "
        "placeholder profile from `scripts/render_placeholder_profile.sh`. **No "
        "image is published.** These digests and the metadata below are recorded "
        "for Tuva's reproducibility check; they are not a target for a client "
        "build. To adopt this release, follow the consumption doc, "
        f"`cms_mssp_pipeline`'s [`docs/client-release-consumption.md`]({CONSUMPTION_DOC_URL}), "
        "and run its git conformance check.",
        "",
        "| config digest (image ID) | manifest digest |",
        "| --- | --- |",
        f"| `{record['config_digest']}` | `{record['manifest_digest']}` |",
        "",
        "## Reproducibility check",
        "",
    ]
    if check is None:
        out.append("No rebuild was run.")
    else:
        verdict = {True: "match", False: "**differ**"}
        out.append(
            "A second, independent build on a fresh runner with no shared cache: "
            f"config digest {verdict[check['config_digest_match']]}, manifest digest "
            f"{verdict[check['manifest_digest_match']]}."
        )
        if not check["config_digest_match"]:
            out.append(
                "Expected: the dbt manifests baked into the image carry a generation "
                "time and invocation ID, so the digest identifies this CI build only "
                "(see README, *Release digests and metadata*)."
            )
    out += [
        "",
        "## Assets",
        "",
        f"- `release-metadata-{tag}.json`: `scripts/create_release_metadata.py` output "
        "for the CI build. Its `image_reference` / `ecr_digest` name the unpublished "
        "CI image; your own `scripts/build_release_image.sh` run writes the metadata "
        "you deploy from.",
        f"- `image-digests-{tag}.json`: the digests above, machine-readable.",
        "",
        "## Changelog",
        "",
        changelog_section(tag[1:] if tag.startswith("v") else tag),
        "",
    ]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    modes = parser.add_subparsers(dest="mode", required=True)
    changelog = modes.add_parser("changelog")
    changelog.add_argument("version")
    notes = modes.add_parser("notes")
    notes.add_argument("--tag", required=True)
    notes.add_argument("--records", type=Path, required=True)
    notes.add_argument("--metadata", type=Path, required=True)
    notes.add_argument("--digests-out", type=Path)
    args = parser.parse_args()

    if args.mode == "changelog":
        print(changelog_section(args.version))
        return 0

    record, rebuild = load_records(args.records, args.tag)
    metadata = json.loads(args.metadata.read_text(encoding="ascii"))
    if metadata.get("source_commit") != record["source_commit"]:
        raise SystemExit("release metadata and build record disagree on the source commit")
    check = rebuild_check(record, rebuild)
    contract = workbook_contract()
    print(render(args.tag, record, metadata, check, contract))
    if args.digests_out:
        args.digests_out.write_text(
            json.dumps(
                {
                    "tag": args.tag,
                    "source_commit": record["source_commit"],
                    "source_date_epoch": record["source_date_epoch"],
                    "platform": record["platform"],
                    "workbook_contract": contract,
                    "config_digest": record["config_digest"],
                    "manifest_digest": record["manifest_digest"],
                    "rebuild_check": check,
                },
                indent=2,
            )
            + "\n",
            encoding="ascii",
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
