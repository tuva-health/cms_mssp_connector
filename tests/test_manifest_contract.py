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
# The benchmark staging tier: twenty long/tidy views over the sectioned CMS
# workbook families (BNMRK / AEXPU / QEXPU), materialised alongside the other
# MSSP staging outputs in _stg_input_layer.
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
# The two final benchmark facts: the calculated three-way blended benchmark
# update and projected savings, placed in the input_layer boundary schema.
BENCHMARK_FACT_OUTPUTS = (
    "fct_projected_benchmark_by_enrollment_type",
    "fct_projected_savings",
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
    for name in BENCHMARK_STAGING_OUTPUTS:
        nodes[f"model.cms_mssp_connector.{name}"] = model(
            "cms_mssp_connector", name, "_stg_input_layer"
        )
    for name in BENCHMARK_FACT_OUTPUTS:
        nodes[f"model.cms_mssp_connector.{name}"] = model(
            "cms_mssp_connector", name, "input_layer"
        )
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

    def test_rejects_missing_or_misplaced_benchmark_staging_relation(self) -> None:
        missing = valid_manifest()
        del missing["nodes"]["model.cms_mssp_connector.stg_bnmrk_table_1"]
        misplaced = valid_manifest()
        misplaced["nodes"]["model.cms_mssp_connector.stg_qexpu_parameters"][
            "schema"
        ] = "input_layer"

        missing_errors = self.verify(missing)
        misplaced_errors = self.verify(misplaced)

        self.assertTrue(any("stg_bnmrk_table_1" in error for error in missing_errors))
        self.assertTrue(
            any("stg_qexpu_parameters" in error for error in misplaced_errors)
        )

    def test_rejects_missing_or_misplaced_benchmark_fact(self) -> None:
        missing = valid_manifest()
        del missing["nodes"]["model.cms_mssp_connector.fct_projected_savings"]
        misplaced = valid_manifest()
        misplaced["nodes"][
            "model.cms_mssp_connector.fct_projected_benchmark_by_enrollment_type"
        ]["schema"] = "_stg_input_layer"

        missing_errors = self.verify(missing)
        misplaced_errors = self.verify(misplaced)

        self.assertTrue(any("fct_projected_savings" in error for error in missing_errors))
        self.assertTrue(
            any(
                "fct_projected_benchmark_by_enrollment_type" in error
                for error in misplaced_errors
            )
        )

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

    def test_dbt_version_is_parsed_from_the_pin(self) -> None:
        # The expected dbt version is read from the dbt-core pin, not baked in:
        # a synthetic pin with a distinct version parses to that version.
        pin = "duckdb==1.4.3\ndbt-core==9.9.9\ndbt-duckdb==1.10.1\n"
        self.assertEqual(verify_manifest.dbt_version_pin(pin), "9.9.9")

    def test_version_and_package_fields_are_sourced_not_hardcoded(self) -> None:
        # The module constants track the repo pin + lock rather than a hand-kept
        # copy, so the verifier cannot silently drift from what the repo pins.
        requirements = (REPOSITORY_ROOT / "requirements.txt").read_text(encoding="ascii")
        lock = (REPOSITORY_ROOT / "package-lock.yml").read_text(encoding="ascii")
        self.assertEqual(
            verify_manifest.DBT_VERSION, verify_manifest.dbt_version_pin(requirements)
        )
        self.assertEqual(
            verify_manifest.PACKAGE_REVISIONS, verify_manifest.package_revisions(lock)
        )


if __name__ == "__main__":
    unittest.main()
