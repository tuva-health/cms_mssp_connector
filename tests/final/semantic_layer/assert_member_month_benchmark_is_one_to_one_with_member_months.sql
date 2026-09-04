{#-
    fact_member_month_benchmark and fact_member_months must carry exactly the
    same member-months.

    The fact exists to be joined one to one on MEMBER_MONTH_SK, and a report
    model that inner-joins the two would silently lose every member-month that
    is on one side only. The model contract already asserts uniqueness and the
    one direction a relationships test can express — every benchmark row
    points at a member-month. This test asserts the other direction as well:
    every member-month has a benchmark row, whether or not a rate could be
    filled, because the rule is that a year with no projection keeps its rows
    with NULL rates rather than dropping them.

      missing_from_benchmark        a member-month with no benchmark row
      missing_from_member_months    a benchmark row with no member-month
-#}

with member_months as (

    select member_month_sk as MEMBER_MONTH_SK
    from {{ ref('the_tuva_project', 'semantic_layer__fact_member_months') }}

),

benchmark as (

    select MEMBER_MONTH_SK
    from {{ ref('fact_member_month_benchmark') }}

)

select
    coalesce(member_months.MEMBER_MONTH_SK, benchmark.MEMBER_MONTH_SK) as MEMBER_MONTH_SK,
    case
        when benchmark.MEMBER_MONTH_SK is null      then 'missing_from_benchmark'
        when member_months.MEMBER_MONTH_SK is null  then 'missing_from_member_months'
    end                                                                 as FAILURE
from member_months
full outer join benchmark
    on benchmark.MEMBER_MONTH_SK = member_months.MEMBER_MONTH_SK
where member_months.MEMBER_MONTH_SK is null
   or benchmark.MEMBER_MONTH_SK is null
