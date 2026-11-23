{#-
    Every savings and benchmark fact carries fct_settlement beside its
    projection (TUVA-160):

      * IS_SETTLED is true exactly where fct_settlement has a row for the
        row's ACO and performance year.
      * The ACO-year facts carry fct_settlement's figures as written
        (settlement_outcome_columns), and the enrollment-type facts the
        per-type figures at the row's own type
        (settlement_enrollment_type_columns).
      * fact_member_month_benchmark carries Table 2 [I] / 12, and [G] / 12 at
        the month's settlement type.

    On a year that is not settled each of these is NULL, so the same
    comparison proves that too. A copied figure must match exactly
    (settlement_copy_differs); the two divided by 12 allow float rounding
    (settlement_values_differ).

    One row per fact, ACO, year and column that disagrees.
-#}

{%- set aco_year_facts = [
        'fct_projected_savings',
        'fct_projected_savings_current',
        'fact_benchmark_aco_quarter'
    ] -%}
{%- set enrollment_type_facts = [
        'fct_projected_benchmark_by_enrollment_type',
        'fct_projected_benchmark_by_enrollment_type_current'
    ] -%}

with settlement as (

    select * from {{ ref('fct_settlement') }}

),

mismatches as (

{%- for fact in aco_year_facts %}

    select
        '{{ fact }}'                                    as FACT,
        fact.ACO_ID                                     as ACO_ID,
        fact.PERFORMANCE_YEAR                           as PERFORMANCE_YEAR,
        checks.COLUMN_NAME                              as COLUMN_NAME
    from {{ ref(fact) }} as fact
    left join settlement
        on settlement.ACO_ID = fact.ACO_ID
       and settlement.PERFORMANCE_YEAR = fact.PERFORMANCE_YEAR
    cross join (
        select 'IS_SETTLED' as COLUMN_NAME
        {%- for field, column in settlement_outcome_columns() %}
        union all select '{{ column }}'
        {%- endfor %}
    ) as checks
    where case checks.COLUMN_NAME
            when 'IS_SETTLED'
                then {{ settlement_copy_differs('fact.IS_SETTLED', 'settlement.ACO_ID is not null') }}
            {%- for field, column in settlement_outcome_columns() %}
            when '{{ column }}'
                then {{ settlement_copy_differs('fact.' ~ column, 'settlement.' ~ field) }}
            {%- endfor %}
          end

    union all
{%- endfor %}

{%- for fact in enrollment_type_facts %}

    select
        '{{ fact }}'                                    as FACT,
        fact.ACO_ID                                     as ACO_ID,
        fact.PERFORMANCE_YEAR                           as PERFORMANCE_YEAR,
        checks.COLUMN_NAME                              as COLUMN_NAME
    from {{ ref(fact) }} as fact
    left join settlement
        on settlement.ACO_ID = fact.ACO_ID
       and settlement.PERFORMANCE_YEAR = fact.PERFORMANCE_YEAR
    cross join (
        select 'IS_SETTLED' as COLUMN_NAME
        union all select 'SETTLEMENT_SUBMISSION_ID'
        {%- for field, column in settlement_enrollment_type_columns() %}
        union all select '{{ column }}'
        {%- endfor %}
    ) as checks
    where case checks.COLUMN_NAME
            when 'IS_SETTLED'
                then {{ settlement_copy_differs('fact.IS_SETTLED', 'settlement.ACO_ID is not null') }}
            when 'SETTLEMENT_SUBMISSION_ID'
                then {{ settlement_copy_differs('fact.SETTLEMENT_SUBMISSION_ID', 'settlement.SUBMISSION_ID') }}
            {%- for field, column in settlement_enrollment_type_columns() %}
            when '{{ column }}'
                then {{ settlement_copy_differs('fact.' ~ column, settlement_field_at_type('settlement', field, 'fact.ENROLLMENT_TYPE')) }}
            {%- endfor %}
          end

    union all
{%- endfor %}

    select
        'fact_member_month_benchmark'                   as FACT,
        fact.ACO_ID                                     as ACO_ID,
        fact.PERFORMANCE_YEAR                           as PERFORMANCE_YEAR,
        checks.COLUMN_NAME                              as COLUMN_NAME
    from {{ ref('fact_member_month_benchmark') }} as fact
    left join settlement
        on settlement.ACO_ID = fact.ACO_ID
       and settlement.PERFORMANCE_YEAR = fact.PERFORMANCE_YEAR
    cross join (
        select 'IS_SETTLED' as COLUMN_NAME
        union all select 'SETTLEMENT_SUBMISSION_ID'
        union all select 'SETTLEMENT_FLAT_BENCHMARK_PMPM'
        union all select 'SETTLEMENT_ENROLLMENT_TYPE_BENCHMARK_PMPM'
    ) as checks
    where case checks.COLUMN_NAME
            when 'IS_SETTLED'
                then {{ settlement_copy_differs('fact.IS_SETTLED', 'settlement.ACO_ID is not null') }}
            when 'SETTLEMENT_SUBMISSION_ID'
                then {{ settlement_copy_differs('fact.SETTLEMENT_SUBMISSION_ID', 'settlement.SUBMISSION_ID') }}
            when 'SETTLEMENT_FLAT_BENCHMARK_PMPM'
                then coalesce(
                    {{ settlement_values_differ('fact.SETTLEMENT_FLAT_BENCHMARK_PMPM', to_double('settlement.UPDATED_BENCHMARK') ~ ' / ' ~ to_double(12)) }},
                    (fact.SETTLEMENT_FLAT_BENCHMARK_PMPM is null) <> (settlement.UPDATED_BENCHMARK is null)
                )
            when 'SETTLEMENT_ENROLLMENT_TYPE_BENCHMARK_PMPM'
                then coalesce(
                    {{ settlement_values_differ(
                        'fact.SETTLEMENT_ENROLLMENT_TYPE_BENCHMARK_PMPM',
                        to_double(settlement_field_at_type('settlement', 'UPDATED_BENCHMARK', 'fact.SETTLEMENT_ENROLLMENT_TYPE')) ~ ' / ' ~ to_double(12)) }},
                    (fact.SETTLEMENT_ENROLLMENT_TYPE_BENCHMARK_PMPM is null)
                        <> ({{ settlement_field_at_type('settlement', 'UPDATED_BENCHMARK', 'fact.SETTLEMENT_ENROLLMENT_TYPE') }} is null)
                )
          end

)

select
    FACT,
    ACO_ID,
    PERFORMANCE_YEAR,
    COLUMN_NAME,
    count(*)                                            as MISMATCHED_ROWS
from mismatches
group by FACT, ACO_ID, PERFORMANCE_YEAR, COLUMN_NAME
