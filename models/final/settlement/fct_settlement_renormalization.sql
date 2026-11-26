{#-
    The settlement (STLMT) workbook's Table A2, renormalization: the
    national assignable FFS mean risk scores CMS divides by so the national
    mean is 1.0, one row per ACO, performance year and enrollment type, from
    the preferred delivery. Table A2 has no letters: its two blocks, the
    CMS-HCC means and the demographic means, are told apart by their
    titles (BLOCK_LABEL), each by BY1, BY2, BY3 and PY.
-#}

with cells as (

    select *
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION
      and FACT = 'renormalization'

)

select
    cells.ACO_ID                                        as ACO_ID,
    cells.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    cells.SUBMISSION_ID                                 as SUBMISSION_ID,
    cells.IS_EMBARGOED                                  as IS_EMBARGOED,
    cells.FILE_PATH                                     as FILE_PATH,
    cells.ENROLLMENT_TYPE                               as ENROLLMENT_TYPE,
{{ settlement_fact_pivot('renormalization', 'cells') }}

from cells

group by
    cells.ACO_ID,
    cells.PERFORMANCE_YEAR,
    cells.SUBMISSION_ID,
    cells.IS_EMBARGOED,
    cells.FILE_PATH,
    cells.ENROLLMENT_TYPE
