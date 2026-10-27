{#-
    fact_member_month_benchmark and fact_member_months must carry exactly the
    same member-months.

    The fact exists to be joined one to one on MEMBER_MONTH_ID, and a report
    model that inner-joins the two would silently lose every member-month that
    is on one side only. The model contract already asserts uniqueness and the
    one direction a relationships test can express — every benchmark row
    points at a member-month. This test asserts the other direction as well:
    every member-month has a benchmark row, whether or not a rate could be
    filled, because the rule is that a year with no projection keeps its rows
    with NULL rates rather than dropping them.

    The key is member_month_id, Core's coverage-grain identifier. The
    deprecated member_month_sk (person_id|year_month) is not unique once a
    person-month has more than one payer or plan, so it cannot carry this
    check.

      missing_from_benchmark        a member-month with no benchmark row
      missing_from_member_months    a benchmark row with no member-month
-#}

with member_months as (

    select member_month_id as MEMBER_MONTH_ID
    from {{ ref('semantic_layer', 'semantic_layer__fact_member_months') }}

),

benchmark as (

    select MEMBER_MONTH_ID
    from {{ ref('fact_member_month_benchmark') }}

)

select
    coalesce(member_months.MEMBER_MONTH_ID, benchmark.MEMBER_MONTH_ID) as MEMBER_MONTH_ID,
    case
        when benchmark.MEMBER_MONTH_ID is null      then 'missing_from_benchmark'
        when member_months.MEMBER_MONTH_ID is null  then 'missing_from_member_months'
    end                                                                 as FAILURE
from member_months
full outer join benchmark
    on benchmark.MEMBER_MONTH_ID = member_months.MEMBER_MONTH_ID
where member_months.MEMBER_MONTH_ID is null
   or benchmark.MEMBER_MONTH_ID is null
