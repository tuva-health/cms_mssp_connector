{#-
    Every latest benchmark delivery must carry the full risk score grid: four
    enrollment types by three benchmark years, each row holding the ACO's
    renormalised CMS-HCC risk score [C] and its ratio to BY3 [D].

    int_benchmark_risk_scores is a pivot over two sheets, and a pivot is where
    a missing cell goes quiet. If BNMRK Table 1 dropped an enrollment type row,
    or the seed stopped recognising its label, the [C]/[D] pair for that type
    would not become NULL somewhere visible — it would simply not be a row, and
    a consumer joining on enrollment type would lose the type without a NULL to
    trip over. The 'unmapped' key the models write is loud in the mapping test,
    but that test only sees the label; this one sees the hole it leaves.

    The grid is spelled out here rather than read from the seed on purpose. The
    seed carries `aged_disabled` and `total`, which Table 1 sections [C] and
    [D] do not use, and the sheet has exactly these twelve cells by CMS's
    design. A delivery that produces more rows than that on a latest
    submission — a fifth cohort, a fourth benchmark year, an unmapped label —
    is reported too, because "exactly twelve" is the property, not "at least".

    Only [C] and [D] are required. The national mean [Table 4] is allowed to be
    NULL: a preliminary delivery has been observed shipping 'N/A' for BY3
    there, and that is CMS's statement about the sheet, not a parsing
    failure. The row still exists, which is the point.

    Superseded deliveries are not checked. They were complete when they were
    the latest, and a March workbook cannot be fixed by anything CMS ships in
    June.
-#}

with latest_workbook as (

    select distinct
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_PATH
    from {{ ref('int_benchmark_risk_scores') }}
    where IS_LATEST_SUBMISSION

),

expected_enrollment_type as (

    select 'esrd'          as ENROLLMENT_TYPE union all
    select 'disabled'      as ENROLLMENT_TYPE union all
    select 'aged_dual'     as ENROLLMENT_TYPE union all
    select 'aged_non_dual' as ENROLLMENT_TYPE

),

expected_by_label as (

    select 'BY1' as BY_LABEL union all
    select 'BY2' as BY_LABEL union all
    select 'BY3' as BY_LABEL

),

expected as (

    select
        latest_workbook.ACO_ID,
        latest_workbook.PERFORMANCE_YEAR,
        latest_workbook.SUBMISSION_ID,
        latest_workbook.FILE_PATH,
        expected_enrollment_type.ENROLLMENT_TYPE,
        expected_by_label.BY_LABEL
    from latest_workbook
    cross join expected_enrollment_type
    cross join expected_by_label

),

actual as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_PATH,
        ENROLLMENT_TYPE,
        BY_LABEL,
        ACO_RISK_SCORE,
        RISK_RATIO_TO_BY3
    from {{ ref('int_benchmark_risk_scores') }}
    where IS_LATEST_SUBMISSION

),

compared as (

    select
        coalesce(expected.ACO_ID, actual.ACO_ID)                     as ACO_ID,
        coalesce(expected.PERFORMANCE_YEAR, actual.PERFORMANCE_YEAR) as PERFORMANCE_YEAR,
        coalesce(expected.SUBMISSION_ID, actual.SUBMISSION_ID)       as SUBMISSION_ID,
        coalesce(expected.FILE_PATH, actual.FILE_PATH)               as FILE_PATH,
        coalesce(expected.ENROLLMENT_TYPE, actual.ENROLLMENT_TYPE)   as ENROLLMENT_TYPE,
        coalesce(expected.BY_LABEL, actual.BY_LABEL)                 as BY_LABEL,
        case
            when actual.FILE_PATH is null           then 'row_missing'
            when expected.FILE_PATH is null         then 'unexpected_row'
            when actual.ACO_RISK_SCORE is null      then 'aco_risk_score_missing'
            when actual.RISK_RATIO_TO_BY3 is null   then 'risk_ratio_missing'
        end                                                          as FAILURE
    from expected
    full outer join actual
        on expected.FILE_PATH = actual.FILE_PATH
       and expected.ENROLLMENT_TYPE = actual.ENROLLMENT_TYPE
       and expected.BY_LABEL = actual.BY_LABEL

)

select
    ACO_ID,
    PERFORMANCE_YEAR,
    SUBMISSION_ID,
    FILE_PATH,
    ENROLLMENT_TYPE,
    BY_LABEL,
    FAILURE
from compared
where FAILURE is not null
