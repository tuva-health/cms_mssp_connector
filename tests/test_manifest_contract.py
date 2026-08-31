import unittest
from pathlib import Path

from scripts import verify_manifest

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]

# Neutral placement database standing in for the client overlay value. The
# generic verifier derives it from the manifest, so no identity is required.
DATABASE = "ANALYTICS_DEV"

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
    "model.cms_aalr_connector.enrollment": ("cms_aalr_connector", "enrollment", "raw_data"),
    "model.cms_aalr_connector.provider_attribution": (
        "cms_aalr_connector",
        "provider_attribution",
        "input_layer",
    ),
    "model.medicare_cclf_connector.eligibility": (
        "medicare_cclf_connector",
        "eligibility",
        "input_layer",
    ),
    "model.medicare_cclf_connector.medical_claim": (
        "medicare_cclf_connector",
        "medical_claim",
        "input_layer",
    ),
    "model.medicare_cclf_connector.pharmacy_claim": (
        "medicare_cclf_connector",
        "pharmacy_claim",
        "input_layer",
    ),
}


def model(package: str, name: str, schema: str, depends_on: "list[str] | None" = None) -> dict:
    return {
        "resource_type": "model",
        "package_name": package,
        "name": name,
        "database": DATABASE,
        "schema": schema,
        "alias": name,
        "config": {"enabled": True},
        "depends_on": {"nodes": depends_on or []},
    }


def valid_manifest() -> dict:
    nodes = {
        f"model.cms_mssp_connector.{name}": model(
            "cms_mssp_connector", name, "_stg_input_layer"
        )
        for name in MSSP_OUTPUTS
    }
    for unique_id, (package, name, schema) in BOUNDARY_OUTPUTS.items():
        nodes[unique_id] = model(package, name, schema)
    nodes["model.medicare_cclf_connector.eligibility"]["depends_on"]["nodes"] = [
        "model.cms_aalr_connector.enrollment"
    ]
    for name, dependency in {
        "input_layer__eligibility": "model.medicare_cclf_connector.eligibility",
        "input_layer__medical_claim": "model.medicare_cclf_connector.medical_claim",
        "input_layer__pharmacy_claim": "model.medicare_cclf_connector.pharmacy_claim",
        "input_layer__provider_attribution": "model.cms_aalr_connector.provider_attribution",
    }.items():
        nodes[f"model.the_tuva_project.{name}"] = model(
            "the_tuva_project", name, "input_layer", [dependency]
        )
    return {"metadata": {"dbt_version": "1.11.14"}, "nodes": nodes}


class ManifestContractTests(unittest.TestCase):
    def verify(self, manifest: dict, lock: "str | None" = None, database=None) -> list:
        return verify_manifest.verify(
            manifest,
            lock or (REPOSITORY_ROOT / "package-lock.yml").read_text(encoding="ascii"),
            database,
        )

    def test_accepts_the_released_output_set_contract(self) -> None:
        self.assertEqual(self.verify(valid_manifest()), [])

    def test_derives_the_target_database_and_enforces_one_placement(self) -> None:
        # A supplied (client overlay) database is honored...
        self.assertEqual(self.verify(valid_manifest(), database=DATABASE), [])
        # ...and a supplied database that disagrees with placement is rejected.
        mismatched = self.verify(valid_manifest(), database="SOMEWHERE_ELSE")
        self.assertTrue(any("placement must be" in error for error in mismatched))
        # A manifest whose required outputs disagree on the database fails to derive.
        divergent = valid_manifest()
        divergent["nodes"]["model.cms_mssp_connector.stg_participants_list"][
            "database"
        ] = "OTHER_DB"
        self.assertTrue(
            any("single target database" in error for error in self.verify(divergent))
        )

    def test_rejects_missing_or_disabled_required_relations(self) -> None:
        missing = valid_manifest()
        del missing["nodes"]["model.cms_mssp_connector.stg_participants_list"]
        disabled = valid_manifest()
        disabled["nodes"]["model.medicare_cclf_connector.medical_claim"]["config"][
            "enabled"
        ] = False

        missing_errors = self.verify(missing)
        disabled_errors = self.verify(disabled)

        self.assertTrue(any("stg_participants_list" in error for error in missing_errors))
        self.assertTrue(any("medical_claim" in error for error in disabled_errors))

    def test_rejects_wrong_version_relation_placement_and_dependency_path(self) -> None:
        manifest = valid_manifest()
        manifest["metadata"]["dbt_version"] = "1.11.13"
        manifest["nodes"]["model.cms_aalr_connector.enrollment"]["schema"] = "input_layer"
        manifest["nodes"]["model.the_tuva_project.input_layer__eligibility"]["depends_on"][
            "nodes"
        ] = []

        errors = self.verify(manifest)

        self.assertTrue(any("dbt version" in error for error in errors))
        self.assertTrue(any("raw_data" in error for error in errors))
        self.assertTrue(any("Tuva dependency" in error for error in errors))

    def test_rejects_an_unapproved_package_revision(self) -> None:
        lock = (REPOSITORY_ROOT / "package-lock.yml").read_text(encoding="ascii")
        errors = self.verify(valid_manifest(), lock.replace("0.17.2", "0.17.1", 1))

        self.assertTrue(any("the_tuva_project" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
