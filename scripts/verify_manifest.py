#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


DBT_VERSION = "1.11.14"
MSSP_OUTPUTS = (
    "stg_participants_list",
    "stg_provider_and_supplier_list",
    "stg_shadow_bundles_dm",
    "stg_shadow_bundles_hh",
    "stg_shadow_bundles_epi",
    "stg_shadow_bundles_opl",
    "stg_shadow_bundles_pb",
    "stg_shadow_bundles_sn",
    "stg_shadow_bundles_hs",
    "stg_shadow_bundles_ip",
    "stg_beneficiary_exclusions",
    "stg_excluded_beneficiary_mbi_xref",
    "stg_claims_benefit_enhancement_and_demonstration_code_file_cclfa",
    "stg_cclfb_claims_benefit_enhancement_and_demonstration_code_file_cclfb",
    "stg_baip_beneficiary_advanced_investment_payment",
    "stg_beur_beneficiary_expenditure_utilization_report",
    "stg_ncbp_non_claims_based_payments",
    "stg_mcqm_bcs_112ssp",
    "stg_mcqm_beneficiaries",
    "stg_mcqm_htn_236ssp",
    "stg_mcqm_dep_134ssp",
    "stg_mcqm_dm_001ssp",
)
BOUNDARY_OUTPUTS = {
    "model.cms_aalr_connector.enrollment": ("enrollment", "raw_data"),
    "model.cms_aalr_connector.provider_attribution": ("provider_attribution", "input_layer"),
    "model.medicare_cclf_connector.eligibility": ("eligibility", "input_layer"),
    "model.medicare_cclf_connector.medical_claim": ("medical_claim", "input_layer"),
    "model.medicare_cclf_connector.pharmacy_claim": ("pharmacy_claim", "input_layer"),
}
PACKAGE_REVISIONS = {
    "dbt_utils": "1.3.3",
    "cms_aalr_connector": "b10d6b6cd54af91b2ca04050d73bad5cb56cc5b0",
    "medicare_cclf_connector": "603a258e3c649d6a4eb7d0835e8efc7d79371204",
    "the_tuva_project": "0.17.2",
    "dbt_expectations": "0.10.10",
    "elementary": "382c570ccf4f8733e5323ae21aa4aa9fa849fedd",
    "dbt_date": "0.17.2",
}


def package_revisions(lock: str) -> Dict[str, str]:
    revisions: Dict[str, str] = {}
    blocks = re.split(r"(?=^  - )", lock, flags=re.MULTILINE)
    for block in blocks:
        name = re.search(r"^\s+(?:- )?name: (.+)$", block, re.MULTILINE)
        revision = re.search(r"^    (?:version|revision): (.+)$", block, re.MULTILINE)
        if name and revision:
            revisions[name.group(1)] = revision.group(1).strip('"')
    return revisions


def enabled_model(nodes: dict, unique_id: str) -> Optional[dict]:
    node = nodes.get(unique_id)
    if (
        not node
        or node.get("resource_type") != "model"
        or not node.get("config", {}).get("enabled", False)
    ):
        return None
    return node


def reaches_enabled_tuva(nodes: dict, start: str) -> bool:
    children: Dict[str, Set[str]] = {}
    for unique_id, node in nodes.items():
        if not node.get("config", {}).get("enabled", False):
            continue
        for dependency in node.get("depends_on", {}).get("nodes", []):
            children.setdefault(dependency, set()).add(unique_id)

    pending = list(children.get(start, ()))
    visited: Set[str] = set()
    while pending:
        unique_id = pending.pop()
        if unique_id in visited:
            continue
        visited.add(unique_id)
        node = nodes.get(unique_id, {})
        if node.get("package_name") == "the_tuva_project" and node.get("resource_type") == "model":
            return True
        pending.extend(children.get(unique_id, ()))
    return False


def placement_database(nodes: dict, database: Optional[str]) -> Tuple[Optional[str], List[str]]:
    """Resolve the expected placement database.

    A database supplied by the caller is the client overlay value and is used
    as-is. When it is omitted the value is derived from the required MSSP
    outputs so the check stays client-neutral: every accepted output must share
    exactly one target database.
    """
    if database:
        return database, []
    observed: Set[str] = set()
    for name in MSSP_OUTPUTS:
        node = enabled_model(nodes, f"model.cms_mssp_connector.{name}")
        if node is not None and node.get("database") is not None:
            observed.add(node["database"])
    if len(observed) != 1:
        return None, [
            "cannot resolve a single target database from the required MSSP "
            f"outputs, found {sorted(observed)}"
        ]
    return observed.pop(), []


def verify(manifest: dict, lock: str, database: Optional[str] = None) -> List[str]:
    errors: List[str] = []
    nodes = manifest.get("nodes", {})

    actual_version = manifest.get("metadata", {}).get("dbt_version")
    if actual_version != DBT_VERSION:
        errors.append(f"dbt version must be {DBT_VERSION}, found {actual_version}")

    actual_revisions = package_revisions(lock)
    for package, expected in PACKAGE_REVISIONS.items():
        if actual_revisions.get(package) != expected:
            errors.append(
                f"package revision for {package} must be {expected}, "
                f"found {actual_revisions.get(package)}"
            )

    database, database_errors = placement_database(nodes, database)
    errors.extend(database_errors)
    if database is None:
        return errors

    for name in MSSP_OUTPUTS:
        unique_id = f"model.cms_mssp_connector.{name}"
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled MSSP relation is missing: {name}")
            continue
        expected = (database, "_stg_input_layer", name)
        actual = (node.get("database"), node.get("schema"), node.get("alias"))
        if actual != expected:
            errors.append(f"{name} relation placement must be {expected}, found {actual}")

    for unique_id, (alias, schema) in BOUNDARY_OUTPUTS.items():
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled package relation is missing: {unique_id}")
            continue
        expected = (database, schema, alias)
        actual = (node.get("database"), node.get("schema"), node.get("alias"))
        if actual != expected:
            errors.append(f"{unique_id} relation placement must be {expected}, found {actual}")
        if not reaches_enabled_tuva(nodes, unique_id):
            errors.append(f"enabled Tuva dependency path is missing from {unique_id}")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify the released dbt manifest contract")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--package-lock", type=Path, required=True)
    parser.add_argument(
        "--database",
        default=None,
        help="expected placement database; derived from the manifest when omitted",
    )
    args = parser.parse_args()

    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
        lock = args.package_lock.read_text(encoding="utf-8")
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read release inputs: {error}", file=sys.stderr)
        return 1

    errors = verify(manifest, lock, args.database)
    if errors:
        for error in errors:
            print("ERROR: " + error, file=sys.stderr)
        return 1
    print(
        "manifest contract passed: 22 MSSP outputs, 5 package outputs, "
        "5 Tuva boundary paths"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
