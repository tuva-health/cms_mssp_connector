{{ config(severity = 'warn') }}

{#-
    Warns when a QEXPU Table 2 metric reports no quarter at all.

    IS_LATEST_QUARTER is then false on every row of that metric and [E], [G] or
    [H] returns nothing. That is the correct behaviour — there is no quarter to
    flag — but "CMS reported no quarter yet" and "the flag broke" look identical
    downstream, and the second is worth knowing about.

    A warning rather than an error, because the first reading is a legitimate
    state: a workbook can be delivered before the quarter it would report is
    closed. What is not legitimate is finding out by way of an empty benchmark
    input.
-#}

select
    FILE_PATH,
    METRIC,
    count(*)                as QUARTER_CELL_COUNT,
    count(VALUE_NUMERIC)    as REPORTED_CELL_COUNT
from {{ ref('int_expenditures_regional') }}
where PERIOD_TYPE = 'quarter'
group by FILE_PATH, METRIC
having count(VALUE_NUMERIC) = 0
