{#-
    An assigned member-month on the 2025+ assignment-list layout takes its
    enrollment type from the populated score column, not from a fallback.

    The fallbacks exist for the 2022-2024 layout, which carries monthly scores
    and no type columns, and for member-months the assignment list does not
    cover at all. Once the layout carries a type column, the BEUR fraction and
    the eligibility codes are inferences standing in for a fact CMS has stated
    outright, and a 2025+ row resolving through either means the model has
    read past the column it should have used.

    Rows CMS shipped without any type score — about two percent of the 2025+
    rows in the client's data, all with NEW_ENROLLEE empty — are excluded,
    since there is no column to resolve from; they take the fallbacks by
    design and ENROLLMENT_TYPE_SOURCE reports that they did.
-#}

with scored_rows as (

    select
        cast(current_bene_mbi_id as {{ dbt.type_string() }})   as BENE_MBI_ID,
        cast(bene_member_month as {{ dbt.type_string() }})     as YEAR_MONTH
    from {{ ref('cms_aalr_connector', 'enrollment') }}
    where coalesce(esrd_score, dis_score, agdu_score, agnd_score) is not null

)

select
    risk.PERSON_ID,
    risk.DATA_SOURCE,
    risk.YEAR_MONTH,
    risk.ALR_BENE_MBI_ID,
    risk.ENROLLMENT_TYPE,
    risk.ENROLLMENT_TYPE_SOURCE
from {{ ref('int_member_month_risk') }} as risk
inner join scored_rows
    on scored_rows.BENE_MBI_ID = risk.ALR_BENE_MBI_ID
    and scored_rows.YEAR_MONTH = risk.YEAR_MONTH
where risk.IS_ASSIGNED
  and risk.YEAR_MONTH >= '202501'
  and coalesce(risk.ENROLLMENT_TYPE_SOURCE, '') <> 'assignment_list_score_column'
