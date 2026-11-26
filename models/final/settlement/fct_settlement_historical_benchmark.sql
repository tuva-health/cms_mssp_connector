{#-
    The settlement (STLMT) workbook's Table 1, historical benchmark: its
    per-enrollment-type rows, one row per ACO, performance year and type,
    from the preferred delivery. [A2] and [B]-[H] come by benchmark year
    (`<field>_BY1` ... `_BY3`); [G], [K] and [L] also in the sheet's
    Benchmark column. HISTORICAL_BENCHMARK ([L]) is the per-type benchmark
    Table 2 [A] carries forward.

    Table 1's single-valued rows ([A1], the [A2] total, [I], [J], [M]) are
    not read.
-#}

with cells as (

    select *
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION
      and FACT = 'historical_benchmark'

)

select
    cells.ACO_ID                                        as ACO_ID,
    cells.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    cells.SUBMISSION_ID                                 as SUBMISSION_ID,
    cells.IS_EMBARGOED                                  as IS_EMBARGOED,
    cells.FILE_PATH                                     as FILE_PATH,
    cells.ENROLLMENT_TYPE                               as ENROLLMENT_TYPE,
{{ settlement_fact_pivot('historical_benchmark', 'cells') }}

from cells

group by
    cells.ACO_ID,
    cells.PERFORMANCE_YEAR,
    cells.SUBMISSION_ID,
    cells.IS_EMBARGOED,
    cells.FILE_PATH,
    cells.ENROLLMENT_TYPE
