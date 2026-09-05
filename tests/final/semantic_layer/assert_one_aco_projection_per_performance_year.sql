{{ config(severity = 'warn') }}

{#-
    The current projections should carry one ACO per performance year.

    fact_member_month_benchmark joins its projection to the member-month spine
    on performance year alone, because the spine has no ACO on it and the
    connector is deployed one ACO at a time. Should the benchmark inputs ever
    carry two ACOs for one year the fact keeps one of them — the highest
    quarter, lowest ACO_ID on ties — so it stays one to one with
    fact_member_months rather than doubling, and the other ACO's rates are
    silently not applied. That is a limitation to be told about, not a build
    to stop: the rows it produces are right for the ACO it chose.

    Asserted on fct_projected_savings_current rather than on the fact, where
    the second ACO is by construction absent and the condition invisible.
-#}

select
    PERFORMANCE_YEAR,
    count(distinct ACO_ID)                          as ACO_COUNT
from {{ ref('fct_projected_savings_current') }}
group by PERFORMANCE_YEAR
having count(distinct ACO_ID) > 1
