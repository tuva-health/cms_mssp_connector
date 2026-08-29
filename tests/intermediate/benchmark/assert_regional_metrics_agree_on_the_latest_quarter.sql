{{ config(severity = 'warn') }}

{#-
    The three sections of QEXPU Table 2 must agree on how far the workbook has
    got.

    IS_LATEST_QUARTER takes one quarter per workbook from the regional
    expenditure section and applies it to the national and regional weights too,
    because the three are headings inside one sheet of one delivery and [I]
    blends all three into a single factor. That is an assumption about how CMS
    writes the sheet, and it is a good one — but a model that rests on an
    assumption should be able to tell you when the assumption stops holding,
    otherwise the anchor quietly picks a winner and the disagreement never
    surfaces anywhere.

    So: compute the latest populated quarter independently per metric, and
    compare. Today they are identical and this returns nothing. The day CMS
    publishes the weights a quarter ahead of the expenditures, this says so.

    Note what would happen without it. Under the anchor the weights follow the
    expenditure section, so a section running ahead does not produce NULLs and
    does not mix quarters — [G] and [H] simply come back at the anchor quarter,
    which is a defensible answer and an invisible one. The failure this guards
    is not a wrong number; it is a silently discarded fact.

    A warning rather than an error on purpose. If it fires, the right response
    is to look at the sheet and decide what CMS now means, not to stop every
    build until someone does. The product owner's position is that a genuine
    divergence would need the sheet parsing reworked regardless, which is not a
    thing a failing test in this project can accomplish.

    A metric with no populated quarter at all contributes nothing here — it has
    no opinion to disagree with, and assert_regional_metrics_report_a_quarter
    already warns about it separately.
-#}

with latest_quarter_per_metric as (

    select
        FILE_PATH,
        METRIC,
        max(QUARTER_NUM) as LATEST_QUARTER_NUM
    from {{ ref('int_expenditures_regional') }}
    where PERIOD_TYPE = 'quarter'
      and VALUE_NUMERIC is not null
    group by FILE_PATH, METRIC

),

agreement as (

    select
        FILE_PATH,
        count(distinct LATEST_QUARTER_NUM)  as DISTINCT_QUARTER_COUNT,
        count(*)                            as REPORTING_METRIC_COUNT,
        min(LATEST_QUARTER_NUM)             as EARLIEST_REPORTED_QUARTER,
        max(LATEST_QUARTER_NUM)             as LATEST_REPORTED_QUARTER
    from latest_quarter_per_metric
    group by FILE_PATH

)

select
    FILE_PATH,
    REPORTING_METRIC_COUNT,
    DISTINCT_QUARTER_COUNT,
    EARLIEST_REPORTED_QUARTER,
    LATEST_REPORTED_QUARTER
from agreement
where DISTINCT_QUARTER_COUNT > 1
