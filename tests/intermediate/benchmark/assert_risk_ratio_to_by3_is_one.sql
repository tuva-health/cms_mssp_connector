{#-
    [D], the CMS-HCC risk ratio, is each benchmark year's renormalised score
    divided by BY3's, so at BY3 it is 1 by definition — on every enrollment
    type, on every delivery, preliminary or final.

    That makes it the one cell in the sheet whose value is known before the
    workbook is opened, and therefore the one that can bind the pivot to its
    meaning rather than to its shape. A model that read [C] into the ratio
    column, or paired [D] with the wrong benchmark year column, would still
    produce a full grid of plausible numbers near 1; none of the schema tests
    could tell. This one can, because 1.0117 is not 1.

    NULL counts as a failure. The ratio comes from Table 1, which every
    delivery carries, so a BY3 row with no ratio means the [D] row was not
    found for that enrollment type — the completeness test says the same thing
    for the latest delivery, and this one says it for all of them.
-#}

select
    ACO_ID,
    PERFORMANCE_YEAR,
    SUBMISSION_ID,
    FILE_PATH,
    ENROLLMENT_TYPE,
    BY_LABEL,
    RISK_RATIO_TO_BY3
from {{ ref('int_benchmark_risk_scores') }}
where BY_LABEL = 'BY3'
  and (RISK_RATIO_TO_BY3 is null or RISK_RATIO_TO_BY3 <> 1)
