{#-
    A new enrollee's enrollment type is the type of the score column CMS
    populated, never a default.

    CMS scores a new enrollee with the new-enrollee model and writes that score
    into the column of the beneficiary's actual enrollment type on the 2025+
    assignment list — a disabled new enrollee arrives with DIS_SCORE populated
    and the other three type columns empty. The temptation is to treat "new
    enrollee" as a fifth cohort or to fall back to the demographic score; both
    lose the type. This test reads the assignment list independently of the
    model and fails on any new-enrollee member-month whose ENROLLMENT_TYPE
    disagrees with the populated column, or whose type did not come from that
    column at all.

    Rows carrying no type score are outside this test's reach: there is no
    populated column to compare against, and the fallback they take is what
    ENROLLMENT_TYPE_SOURCE is for.
-#}

with assignment_list as (

    select
        cast(current_bene_mbi_id as {{ dbt.type_string() }})   as BENE_MBI_ID,
        cast(bene_member_month as {{ dbt.type_string() }})     as YEAR_MONTH,
        case
            when esrd_score is not null then 'esrd'
            when dis_score  is not null then 'disabled'
            when agdu_score is not null then 'aged_dual'
            when agnd_score is not null then 'aged_non_dual'
        end                                                     as SCORE_COLUMN_TYPE
    from {{ ref('cms_aalr_connector', 'enrollment') }}
    where new_enrollee = 1

)

select
    risk.PERSON_ID,
    risk.DATA_SOURCE,
    risk.YEAR_MONTH,
    risk.ALR_BENE_MBI_ID,
    assignment_list.SCORE_COLUMN_TYPE,
    risk.ENROLLMENT_TYPE,
    risk.ENROLLMENT_TYPE_SOURCE
from {{ ref('int_member_month_risk') }} as risk
inner join assignment_list
    on assignment_list.BENE_MBI_ID = risk.ALR_BENE_MBI_ID
    and assignment_list.YEAR_MONTH = risk.YEAR_MONTH
where risk.IS_NEW_ENROLLEE
  and assignment_list.SCORE_COLUMN_TYPE is not null
  and (
      risk.ENROLLMENT_TYPE is null
      or risk.ENROLLMENT_TYPE <> assignment_list.SCORE_COLUMN_TYPE
      or risk.ENROLLMENT_TYPE_SOURCE <> 'assignment_list_score_column'
  )
