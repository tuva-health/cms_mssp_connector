{{ config(severity = 'warn') }}

{#-
    Warns when a benchmark workbook carries one half of the risk score story
    and not the other.

    int_benchmark_risk_scores joins BNMRK Table 1 sections [C] and [D] to
    BNMRK Table 4 on FILE_PATH — the two sheets live in one workbook, so one
    delivery stamp and one ranking serve both, and the flag cannot disagree
    with itself the way it could if each sheet were ranked on its own. That
    is what makes the join safe, and it is also what this test has to check:
    the pairing rests on both sheets being present in every workbook, which
    is upstream's property, not this project's.

    The assertion is made against the two sources, where the two sets of
    workbooks exist independently and can genuinely differ. Asserting it
    against the pivoted model would be worthless: a workbook missing Table 4
    produces rows there with a NULL national mean, and a test that a NULL is
    NULL cannot fail.

    A warning rather than an error because the consequence is already visible
    downstream — the missing sheet's columns are NULL on every row of that
    workbook, and nothing is silently wrong. What the warning adds is the
    reason: a sheet CMS omitted, or a parse that only got halfway through a
    workbook, which the NULL does not carry. Note that a Table 4 sheet whose
    cells read 'N/A' is present and does not fire this; a preliminary
    delivery has been observed doing exactly that for BY3.
-#}

with risk_score_workbook as (

    select distinct
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_PATH
    from {{ ref('int_benchmark_historical') }}
    where SECTION_CODE in ('C', 'D')

),

renormalization_workbook as (

    select distinct
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        FILE_PATH
    from {{ ref('stg_bnmrk_table_4') }}

)

select
    coalesce(risk_score_workbook.ACO_ID, renormalization_workbook.ACO_ID)
        as ACO_ID,
    coalesce(risk_score_workbook.PERFORMANCE_YEAR, renormalization_workbook.PERFORMANCE_YEAR)
        as PERFORMANCE_YEAR,
    coalesce(risk_score_workbook.SUBMISSION_ID, renormalization_workbook.SUBMISSION_ID)
        as SUBMISSION_ID,
    coalesce(risk_score_workbook.FILE_PATH, renormalization_workbook.FILE_PATH)
        as FILE_PATH,
    case
        when renormalization_workbook.FILE_PATH is null then 'table_4_missing'
        when risk_score_workbook.FILE_PATH is null      then 'table_1_risk_sections_missing'
    end as FAILURE
from risk_score_workbook
full outer join renormalization_workbook
    on risk_score_workbook.FILE_PATH = renormalization_workbook.FILE_PATH
where risk_score_workbook.FILE_PATH is null
   or renormalization_workbook.FILE_PATH is null
