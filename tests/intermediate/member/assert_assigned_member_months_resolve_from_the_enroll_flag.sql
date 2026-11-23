{#-
    An assigned member-month whose assignment-list row carries an EnrollFlag
    of 1-4 takes its enrollment type from that flag, not from the type score
    column or the eligibility codes (TUVA-162).

    CMS types a person-month by its EnrollFlag (TUVA-161). A quarterly or
    initial list's type score column holds the most recent payment year's
    score, typed as the member was in that year, so it can disagree with the
    month's flag; a row resolving through it while the flag is set means the
    model has read the wrong input. The row checked is the one the month is
    assigned from (same MBI, month and file).
-#}

with flagged_rows as (

    select
        cast(current_bene_mbi_id as {{ dbt.type_string() }})   as BENE_MBI_ID,
        cast(bene_member_month as {{ dbt.type_string() }})     as YEAR_MONTH,
        cast(file_name as {{ dbt.type_string() }})             as FILE_NAME,
        case cast(enroll_flag as integer)
            when 1 then 'esrd'
            when 2 then 'disabled'
            when 3 then 'aged_dual'
            when 4 then 'aged_non_dual'
        end                                                     as FLAG_TYPE
    from {{ ref('cms_aalr_connector', 'enrollment') }}
    where cast(enroll_flag as integer) in (1, 2, 3, 4)

)

select
    risk.PERSON_ID,
    risk.DATA_SOURCE,
    risk.YEAR_MONTH,
    risk.ALR_BENE_MBI_ID,
    risk.ENROLLMENT_TYPE,
    risk.ENROLLMENT_TYPE_SOURCE,
    flagged_rows.FLAG_TYPE
from {{ ref('int_member_month_risk') }} as risk
inner join flagged_rows
    on flagged_rows.BENE_MBI_ID = risk.ALR_BENE_MBI_ID
    and flagged_rows.YEAR_MONTH = risk.YEAR_MONTH
    and flagged_rows.FILE_NAME = risk.ALR_FILE_NAME
where risk.IS_ASSIGNED
  and (
      coalesce(risk.ENROLLMENT_TYPE_SOURCE, '') <> 'assignment_list_enroll_flag'
      or coalesce(risk.ENROLLMENT_TYPE, '') <> flagged_rows.FLAG_TYPE
  )
