{#-
    The settlement (STLMT) workbook's Table A1, risk ratios for the annual
    adjustment to the historical benchmark: one row per ACO, performance
    year and enrollment type, from the preferred delivery, one column per
    Table A1 letter [A]-[I].

    Table A1's last row, Weighted Average, is the row whose ENROLLMENT_TYPE
    is 'weighted_average'. CMS fills it only under [D] (UNCAPPED_RISK_RATIO)
    and [G] (DEMOGRAPHIC_RISK_RATIO); its other fields are NULL. The cap
    [H] applies when the weighted-average [D] exceeds it, and then only to
    a type whose [D] is above [H] (specifications section 3.2.4.2).
-#}

with cells as (

    select *
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION
      and FACT = 'risk'

)

select
    cells.ACO_ID                                        as ACO_ID,
    cells.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    cells.SUBMISSION_ID                                 as SUBMISSION_ID,
    cells.IS_EMBARGOED                                  as IS_EMBARGOED,
    cells.FILE_PATH                                     as FILE_PATH,
    cells.ENROLLMENT_TYPE                               as ENROLLMENT_TYPE,
{{ settlement_fact_pivot('risk', 'cells') }}

from cells

group by
    cells.ACO_ID,
    cells.PERFORMANCE_YEAR,
    cells.SUBMISSION_ID,
    cells.IS_EMBARGOED,
    cells.FILE_PATH,
    cells.ENROLLMENT_TYPE
