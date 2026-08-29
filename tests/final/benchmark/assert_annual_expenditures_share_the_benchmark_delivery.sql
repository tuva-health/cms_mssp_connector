{{ config(severity = 'warn') }}

{#-
    Warns when a benchmark delivery has no AEXPU benchmark-year-3 workbook
    carrying its own submission stamp.

    CMS ships the three annual expenditure workbooks *inside* the BNMRK bundle,
    so all four files carry one delivery stamp. Both final models rely on that:
    BENCHMARK_SUBMISSION_ID is what selects [A] from the AEXPU BY3 workbook,
    [J] from BNMRK Table 6 and [L] from BNMRK Table 1, and using one key for all
    three is what stops a row mixing March's benchmark with June's national
    expenditures. The property was checked against a full delivery set before it
    was relied on and held for both the preliminary and the preliminary-final
    bundle, but it is upstream's property rather than this project's.

    Note what this test does NOT do, because the obvious version of it is
    worthless. Asserting that the fact's ANNUAL_EXPENDITURE_SUBMISSION_ID equals
    its BENCHMARK_SUBMISSION_ID cannot fail: the model joins [A] on submission id
    equality, so the column it would compare against is the join key itself. The
    first draft of this test did exactly that and was structurally unable to
    return a row under any mutation.

    What is asserted instead is the upstream property that join depends on —
    that the two families agree on delivery identity — and it is asserted
    against the intermediate models, where the two sets of stamps exist
    independently and can genuinely disagree.

    A warning, not an error, because the consequence is already visible: a
    benchmark delivery with no matching AEXPU workbook finds no [A], and every
    row it produces is flagged IS_CALCULABLE = false. Nothing is silently wrong.
    What the warning adds is the reason, which the NULL does not carry.
-#}

with benchmark_delivery as (

    select distinct
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID
    from {{ ref('int_benchmark_historical') }}

),

annual_delivery as (

    select distinct
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID
    from {{ ref('int_expenditures_annual') }}
    where BENCHMARK_YEAR_LABEL = 'BY3'

)

select
    benchmark_delivery.ACO_ID,
    benchmark_delivery.PERFORMANCE_YEAR,
    benchmark_delivery.SUBMISSION_ID as BENCHMARK_SUBMISSION_ID
from benchmark_delivery
left join annual_delivery
    on benchmark_delivery.ACO_ID = annual_delivery.ACO_ID
   and benchmark_delivery.PERFORMANCE_YEAR = annual_delivery.PERFORMANCE_YEAR
   and benchmark_delivery.SUBMISSION_ID = annual_delivery.SUBMISSION_ID
where annual_delivery.SUBMISSION_ID is null
