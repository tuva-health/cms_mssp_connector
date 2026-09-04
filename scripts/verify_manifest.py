#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
# The dbt-core version pin (requirements.txt) and the package lock
# (package-lock.yml) are the single sources of truth for the runtime version
# and dependency revisions the released manifest must match. They are read from
# those files rather than duplicated as literals here so the verifier cannot
# drift from what the repository actually pins.
PIN_FILE = REPOSITORY_ROOT / "requirements.txt"
LOCK_FILE = REPOSITORY_ROOT / "package-lock.yml"

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
# Benchmark staging tier: the twenty long/tidy views over the sectioned CMS
# workbook families (BNMRK / AEXPU / QEXPU), materialised in _stg_input_layer
# alongside the other MSSP staging outputs. Enumerated from the connector's own
# benchmark dbt models, not driven by an external contract.
BENCHMARK_STAGING_OUTPUTS = (
    "stg_bnmrk_table_1",
    "stg_bnmrk_table_1a",
    "stg_bnmrk_table_1b",
    "stg_bnmrk_table_1c",
    "stg_bnmrk_table_2",
    "stg_bnmrk_table_3",
    "stg_bnmrk_table_4",
    "stg_bnmrk_table_5",
    "stg_bnmrk_table_6",
    "stg_bnmrk_parameters",
    "stg_aexpu_table_1",
    "stg_aexpu_table_1a",
    "stg_aexpu_table_3",
    "stg_aexpu_table_4",
    "stg_aexpu_table_4a",
    "stg_aexpu_parameters",
    "stg_qexpu_table_1",
    "stg_qexpu_table_2",
    "stg_qexpu_table_3",
    "stg_qexpu_parameters",
)
# The two final benchmark facts: the three-way blended benchmark update and the
# projected-savings verdict, placed in the input_layer boundary schema.
BENCHMARK_FACT_OUTPUTS = (
    "fct_projected_benchmark_by_enrollment_type",
    "fct_projected_savings",
)
# The Tuva semantic layer: the facts and dimensions the connector build
# materialises in the semantic_layer schema because dbt_project.yml sets
# semantic_layer_enabled. Package model names are semantic_layer__<name> with
# alias <name>; the semantic_layer__stg_* staging models feed these and are not
# part of the contract.
SEMANTIC_LAYER_OUTPUTS = (
    "dim_condition",
    "dim_data_source",
    "dim_date",
    "dim_encounter_group",
    "dim_encounter_provider",
    "dim_encounter_type",
    "dim_member",
    "dim_member_months",
    "dim_service_category",
    "fact_admissions",
    "fact_claims",
    "fact_ed_visits",
    "fact_encounter_service_bridge",
    "fact_encounters",
    "fact_expected_values",
    "fact_hcc_gaps",
    "fact_member_condition_bridge",
    "fact_member_months",
    "fact_pharmacy_claims",
    "fact_quality_measures",
    "fact_risk_factors",
    "fact_risk_scores",
)

# The two current-projection models over those facts: the same figures
# filtered to the latest calculable benchmark delivery and carrying PMPM
# columns. Placed beside the facts in input_layer (TUVA-72).
BENCHMARK_CURRENT_OUTPUTS = (
    "fct_projected_benchmark_by_enrollment_type_current",
    "fct_projected_savings_current",
)
# The connector's own semantic layer fact: the member-month benchmark rates,
# keyed like the Tuva member-months fact and placed in semantic_layer beside it
# (TUVA-75). A connector model, so its unique id is model.cms_mssp_connector.*
# and its alias is its name; the SEMANTIC_LAYER_OUTPUTS set above is the Tuva
# package's and cannot carry it.
CONNECTOR_SEMANTIC_LAYER_OUTPUTS = (
    "fact_member_month_benchmark",
)
BOUNDARY_OUTPUTS = {
    "model.cms_aalr_connector.enrollment": ("enrollment", "raw_data"),
    "model.cms_aalr_connector.provider_attribution": ("provider_attribution", "input_layer"),
    "model.medicare_cclf_connector.eligibility": ("eligibility", "input_layer"),
    "model.medicare_cclf_connector.medical_claim": ("medical_claim", "input_layer"),
    "model.medicare_cclf_connector.pharmacy_claim": ("pharmacy_claim", "input_layer"),
}


def dbt_version_pin(requirements: str) -> Optional[str]:
    """Extract the pinned dbt-core version from a requirements pin file."""
    match = re.search(r"^dbt-core==(.+)$", requirements, re.MULTILINE)
    return match.group(1).strip() if match else None


def package_revisions(lock: str) -> Dict[str, str]:
    revisions: Dict[str, str] = {}
    blocks = re.split(r"(?=^  - )", lock, flags=re.MULTILINE)
    for block in blocks:
        name = re.search(r"^\s+(?:- )?name: (.+)$", block, re.MULTILINE)
        revision = re.search(r"^    (?:version|revision): (.+)$", block, re.MULTILINE)
        if name and revision:
            revisions[name.group(1)] = revision.group(1).strip('"')
    return revisions


# Sourced from the pin + lock, not hardcoded (TUVA-26): the released manifest
# must record this dbt version and the released lock must carry these revisions.
DBT_VERSION = dbt_version_pin(PIN_FILE.read_text(encoding="utf-8"))
PACKAGE_REVISIONS = package_revisions(LOCK_FILE.read_text(encoding="utf-8"))


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

    for name in MSSP_OUTPUTS + BENCHMARK_STAGING_OUTPUTS:
        unique_id = f"model.cms_mssp_connector.{name}"
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled MSSP relation is missing: {name}")
            continue
        expected = (database, "_stg_input_layer", name)
        actual = (node.get("database"), node.get("schema"), node.get("alias"))
        if actual != expected:
            errors.append(f"{name} relation placement must be {expected}, found {actual}")

    for name in BENCHMARK_FACT_OUTPUTS + BENCHMARK_CURRENT_OUTPUTS:
        unique_id = f"model.cms_mssp_connector.{name}"
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled benchmark fact is missing: {name}")
            continue
        expected = (database, "input_layer", name)
        actual = (node.get("database"), node.get("schema"), node.get("alias"))
        if actual != expected:
            errors.append(f"{name} relation placement must be {expected}, found {actual}")

    for name in CONNECTOR_SEMANTIC_LAYER_OUTPUTS:
        unique_id = f"model.cms_mssp_connector.{name}"
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled semantic layer fact is missing: {name}")
            continue
        expected = (database, "semantic_layer", name)
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

    for name in SEMANTIC_LAYER_OUTPUTS:
        unique_id = f"model.the_tuva_project.semantic_layer__{name}"
        node = enabled_model(nodes, unique_id)
        if node is None:
            errors.append(f"required enabled semantic layer relation is missing: {name}")
            continue
        expected = (database, "semantic_layer", name)
        actual = (node.get("database"), node.get("schema"), node.get("alias"))
        if actual != expected:
            errors.append(f"{name} relation placement must be {expected}, found {actual}")

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
        f"manifest contract passed: {len(MSSP_OUTPUTS)} MSSP outputs, "
        f"{len(BENCHMARK_STAGING_OUTPUTS)} benchmark staging outputs, "
        f"{len(BENCHMARK_FACT_OUTPUTS)} benchmark facts, "
        f"{len(BENCHMARK_CURRENT_OUTPUTS)} current projections, "
        f"{len(BOUNDARY_OUTPUTS)} package outputs, "
        f"{len(BOUNDARY_OUTPUTS)} Tuva boundary paths, "
        f"{len(SEMANTIC_LAYER_OUTPUTS)} semantic layer outputs, "
        f"{len(CONNECTOR_SEMANTIC_LAYER_OUTPUTS)} connector semantic layer facts"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
