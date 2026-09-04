{#-
    The benchmark-year half of the risk adjustment story, from two sheets of
    the BNMRK workbook pivoted to one row per enrollment type and benchmark
    year.

    Table 1 section [C] is the ACO's CMS-HCC risk score for BY1 through BY3,
    renormalised so the national assignable FFS mean is 1.0; section [D] is
    each year's ratio to BY3. Table 4 is that national mean itself, per
    enrollment type and benchmark year — the renormalisation factor the
    parameters sheet names. Table 4 has no section or row labels beyond the
    enrollment type, which is why nothing downstream had found it.

    The two sheets are joined on FILE_PATH, not on the delivery stamp. They
    live in one workbook, so one stamp and one ranking serve both, and the
    IS_LATEST_SUBMISSION flag cannot disagree with itself the way it could if
    each sheet were ranked on its own. That the two sheets are always both
    present is upstream's property; assert_risk_score_sheets_share_the_workbook
    warns when it stops holding.

    The row set is the union of what either sheet carries, so a cell present
    on one sheet and absent from the other keeps its row with a NULL rather
    than vanishing. The pivot over [C] and [D] is where a missing cell would
    otherwise go quiet, and assert_risk_scores_are_complete_per_latest_submission
    is what makes it loud.

    Ranking follows int_benchmark_historical exactly — a dense_rank over the
    rows on (FILE_DATE desc nulls last, SUBMISSION_ID desc, FILE_PATH desc),
    with the same reasons for each key given in that model's header.

    Nothing here is calculated. [C] and [D] are the same numeric cells Table 1
    holds; the national mean is Table 4's cell typed at staging.
-#}

with historical as (

    {#- The 'Benchmark' column is structurally not-applicable for [C] and [D]
        and CMS writes '-' there; only the three benchmark years are cells. -#}
    select * from {{ ref('int_benchmark_historical') }}
    where SECTION_CODE in ('C', 'D')
      and BY_LABEL in ('BY1', 'BY2', 'BY3')

),

renormalization as (

    select * from {{ ref('stg_bnmrk_table_4') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

aco_scores as (

    select
        FILE_PATH,
        ENROLLMENT_TYPE,
        BY_LABEL,
        max(ROW_LABEL)                                          as ACO_ROW_LABEL,
        max(case when SECTION_CODE = 'C' then VALUE_NUMERIC end) as ACO_RISK_SCORE,
        max(case when SECTION_CODE = 'D' then VALUE_NUMERIC end) as RISK_RATIO_TO_BY3
    from historical
    group by FILE_PATH, ENROLLMENT_TYPE, BY_LABEL

),

national_scores as (

    select
        renormalization.FILE_PATH                               as FILE_PATH,
        renormalization.ACO_ID                                  as ACO_ID,
        renormalization.PERFORMANCE_YEAR                        as PERFORMANCE_YEAR,
        renormalization.SUBMISSION_ID                           as SUBMISSION_ID,
        renormalization.FILE_DATE                               as FILE_DATE,
        renormalization.DIRECTORY_NAME                          as DIRECTORY_NAME,
        renormalization.FILE_NAME                               as FILE_NAME,
        coalesce(enrollment_type.ENROLLMENT_TYPE, 'unmapped')   as ENROLLMENT_TYPE,
        renormalization.COLUMN_LABEL                            as BY_LABEL,
        renormalization.ROW_LABEL                               as NATIONAL_ROW_LABEL,
        renormalization.VALUE_NUMERIC                           as NATIONAL_MEAN_RISK_SCORE
    from renormalization
    left join enrollment_type
        on upper(trim(renormalization.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER

),

{# The seed maps labels, not canonical keys, so the display columns are
   looked up by the key the two sheets already agree on. Two labels map to
   'esrd', and both carry the same display form and sort. #}
enrollment_type_display as (

    select distinct
        ENROLLMENT_TYPE,
        ENROLLMENT_TYPE_LABEL,
        ENROLLMENT_TYPE_SORT
    from enrollment_type

),

{# Every workbook cell either sheet carries, at the model grain. The delivery
   columns are properties of the workbook and identical on both sheets, so
   the union collapses them. #}
spine as (

    select
        FILE_PATH,
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_DATE,
        DIRECTORY_NAME,
        FILE_NAME,
        ENROLLMENT_TYPE,
        BY_LABEL
    from historical

    union

    select
        FILE_PATH,
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_DATE,
        DIRECTORY_NAME,
        FILE_NAME,
        ENROLLMENT_TYPE,
        BY_LABEL
    from national_scores

),

ranked as (

    select
        spine.*,
        dense_rank() over (
            partition by spine.ACO_ID, spine.PERFORMANCE_YEAR
            order by spine.FILE_DATE desc nulls last, spine.SUBMISSION_ID desc, spine.FILE_PATH desc
        ) as SUBMISSION_RANK
    from spine

)

select
    ranked.ACO_ID                                       as ACO_ID,
    ranked.PERFORMANCE_YEAR                             as PERFORMANCE_YEAR,
    ranked.SUBMISSION_ID                                as SUBMISSION_ID,
    ranked.FILE_DATE                                    as FILE_DATE,
    ranked.SUBMISSION_RANK                              as SUBMISSION_RANK,
    ranked.SUBMISSION_RANK = 1                          as IS_LATEST_SUBMISSION,
    ranked.ENROLLMENT_TYPE                              as ENROLLMENT_TYPE,
    coalesce(enrollment_type_display.ENROLLMENT_TYPE_LABEL, 'Unmapped')
                                                        as ENROLLMENT_TYPE_LABEL,
    coalesce(enrollment_type_display.ENROLLMENT_TYPE_SORT, 99)
                                                        as ENROLLMENT_TYPE_SORT,
    ranked.BY_LABEL                                     as BY_LABEL,
    aco_scores.ACO_ROW_LABEL                            as ACO_ROW_LABEL,
    aco_scores.ACO_RISK_SCORE                           as ACO_RISK_SCORE,
    aco_scores.RISK_RATIO_TO_BY3                        as RISK_RATIO_TO_BY3,
    national_scores.NATIONAL_ROW_LABEL                  as NATIONAL_ROW_LABEL,
    national_scores.NATIONAL_MEAN_RISK_SCORE            as NATIONAL_MEAN_RISK_SCORE,
    ranked.FILE_PATH                                    as FILE_PATH,
    ranked.DIRECTORY_NAME                               as DIRECTORY_NAME,
    ranked.FILE_NAME                                    as FILE_NAME

from ranked

left join aco_scores
    on ranked.FILE_PATH = aco_scores.FILE_PATH
   and ranked.ENROLLMENT_TYPE = aco_scores.ENROLLMENT_TYPE
   and ranked.BY_LABEL = aco_scores.BY_LABEL

left join national_scores
    on ranked.FILE_PATH = national_scores.FILE_PATH
   and ranked.ENROLLMENT_TYPE = national_scores.ENROLLMENT_TYPE
   and ranked.BY_LABEL = national_scores.BY_LABEL

left join enrollment_type_display
    on ranked.ENROLLMENT_TYPE = enrollment_type_display.ENROLLMENT_TYPE
