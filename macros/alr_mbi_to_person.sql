{#-
    The CTEs that map an ALR MBI to a Tuva person id, emitted into the
    caller's WITH list (TUVA-162 shares them between int_member_month_risk and
    int_settlement_member_month_risk, so the two key spaces agree).

    The caller defines two CTEs first: `mbi_keys` (one row per BENE_MBI_ID to
    resolve) and `persons` (one row per Tuva PERSON_ID). The macro adds
    `cclf_beneficiary_xref`, `excluded_beneficiary_xref` and `mbi_resolved`
    (BENE_MBI_ID, PERSON_ID, MBI_CROSSWALK_SOURCE), with no trailing comma.

    The order is the CCLF connector's: the MBI itself where it is already a
    Tuva person, the CCLF crosswalk's current MBI where it is not, and the
    MSSP excluded-beneficiary crosswalk after that. int_member_month_risk
    documents why the order matters.
-#}
{% macro alr_mbi_to_person() %}
cclf_beneficiary_xref as (

    select
        cast(prvs_num as {{ dbt.type_string() }})               as PREVIOUS_MBI,
        cast(crnt_num as {{ dbt.type_string() }})               as CURRENT_MBI
    from {{ ref('medicare_cclf_connector', 'int_beneficiary_xref_deduped') }}
    where prvs_num is not null
      and crnt_num is not null

),

excluded_beneficiary_xref as (

    select
        PREVIOUS_MBI,
        CURRENT_MBI
    from (
        select
            cast(PREVIOUS_BENE_MBI as {{ dbt.type_string() }})  as PREVIOUS_MBI,
            cast(CURRENT_BENE_MBI as {{ dbt.type_string() }})   as CURRENT_MBI,
            row_number() over (
                partition by PREVIOUS_BENE_MBI
                order by PERFORMANCE_YEAR desc, REPORT_MONTH desc, FILE_DATE desc nulls last, FILE_PATH desc
            )                                                   as MAPPING_RANK
        from {{ ref('stg_excluded_beneficiary_mbi_xref') }}
        where PREVIOUS_BENE_MBI is not null
          and CURRENT_BENE_MBI is not null
    ) as ranked
    where MAPPING_RANK = 1

),

mbi_resolved as (

    select
        mbi_keys.BENE_MBI_ID,
        case
            when direct.PERSON_ID is not null        then direct.PERSON_ID
            when via_cclf.PERSON_ID is not null      then via_cclf.PERSON_ID
            when via_excluded.PERSON_ID is not null  then via_excluded.PERSON_ID
        end                                                     as PERSON_ID,
        case
            when direct.PERSON_ID is not null        then 'direct'
            when via_cclf.PERSON_ID is not null      then 'cclf_beneficiary_xref'
            when via_excluded.PERSON_ID is not null  then 'excluded_beneficiary_mbi_xref'
        end                                                     as MBI_CROSSWALK_SOURCE
    from mbi_keys

    left join persons as direct
        on direct.PERSON_ID = mbi_keys.BENE_MBI_ID

    left join cclf_beneficiary_xref
        on cclf_beneficiary_xref.PREVIOUS_MBI = mbi_keys.BENE_MBI_ID
    left join persons as via_cclf
        on via_cclf.PERSON_ID = cclf_beneficiary_xref.CURRENT_MBI

    left join excluded_beneficiary_xref
        on excluded_beneficiary_xref.PREVIOUS_MBI = mbi_keys.BENE_MBI_ID
    left join persons as via_excluded
        on via_excluded.PERSON_ID = excluded_beneficiary_xref.CURRENT_MBI

)
{% endmacro %}
