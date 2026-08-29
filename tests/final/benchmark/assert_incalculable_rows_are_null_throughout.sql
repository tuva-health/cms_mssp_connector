{#-
    IS_CALCULABLE must mean what it says, in both directions.

    The flag exists so that a consumer can tell a pairing whose inputs were
    incomplete from one that was computed, without inspecting a dozen columns
    for NULLs. That is only useful if the flag and the columns agree, and the
    two ways they can disagree are both damaging and both silent:

      * a row flagged calculable that is missing an input somewhere upstream of
        the number it published. Every consumer trusts the number.
      * a row flagged incalculable that published a number anyway. Half a
        calculation looks like a whole one.

    The checks are deliberately stricter than the definitions the models use.
    Each model derives IS_CALCULABLE from a single column — [M] on the per-type
    fact, [P] on the savings fact — so restating that would prove nothing. What
    is asserted instead is that the flag implies the *whole chain* resolved:
    every one of the eleven measured inputs and every intermediate factor.
    [M] is a product of two numbers, and a product being non-NULL says nothing
    about, say, [D] having been found — only about [K] and [L].

      calculable_but_input_missing   flagged true with a NULL somewhere in the
                                     chain that produced it
      incalculable_but_derived       flagged false with [K] or [M] populated
      savings_calculable_but_incomplete
                                     [P] published while one of the four
                                     enrollment types has no [M] or no [O]
      savings_incalculable_but_derived
                                     flagged false with [P] populated

    [O] and [N] are checked under the savings fact's flag rather than the
    per-type fact's, because they are inputs to [P] and not to [M]. Person years
    can legitimately be missing on a pairing whose [M] is complete; what cannot
    happen is [P] being published over them.
-#}

with per_enrollment_type as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        ENROLLMENT_TYPE,
        IS_CALCULABLE,
        NATIONAL_BASE_EXPENDITURE_PER_CAPITA,
        NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
        NATIONAL_EXPENDITURE_UPDATE_FACTOR,
        REGIONAL_BASE_EXPENDITURE_PER_CAPITA,
        REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
        REGIONAL_EXPENDITURE_UPDATE_FACTOR,
        NATIONAL_WEIGHT,
        REGIONAL_WEIGHT,
        NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR,
        ACCOUNTABLE_CARE_PROSPECTIVE_TREND,
        THREE_WAY_BLENDED_UPDATE_FACTOR,
        HISTORICAL_BENCHMARK_EXPENDITURE,
        PROJECTED_UPDATED_BENCHMARK_EXPENDITURE,
        ENROLLMENT_PROPORTION
    from {{ ref('fct_projected_benchmark_by_enrollment_type') }}

),

enrollment_type_failures as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        ENROLLMENT_TYPE,
        case
            when IS_CALCULABLE
                 and (NATIONAL_BASE_EXPENDITURE_PER_CAPITA is null
                   or NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA is null
                   or NATIONAL_EXPENDITURE_UPDATE_FACTOR is null
                   or REGIONAL_BASE_EXPENDITURE_PER_CAPITA is null
                   or REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA is null
                   or REGIONAL_EXPENDITURE_UPDATE_FACTOR is null
                   or NATIONAL_WEIGHT is null
                   or REGIONAL_WEIGHT is null
                   or NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR is null
                   or ACCOUNTABLE_CARE_PROSPECTIVE_TREND is null
                   or THREE_WAY_BLENDED_UPDATE_FACTOR is null
                   or HISTORICAL_BENCHMARK_EXPENDITURE is null)
                then 'calculable_but_input_missing'
            when not IS_CALCULABLE
                 and (THREE_WAY_BLENDED_UPDATE_FACTOR is not null
                   or PROJECTED_UPDATED_BENCHMARK_EXPENDITURE is not null)
                then 'incalculable_but_derived'
        end as FAILURE
    from per_enrollment_type

),

savings as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        IS_CALCULABLE,
        MEAN_PROJECTED_UPDATED_BENCHMARK
    from {{ ref('fct_projected_savings') }}

),

enrollment_type_completeness as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        count(PROJECTED_UPDATED_BENCHMARK_EXPENDITURE)  as POPULATED_BENCHMARK_COUNT,
        count(ENROLLMENT_PROPORTION)                    as POPULATED_PROPORTION_COUNT
    from per_enrollment_type
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

),

savings_failures as (

    select
        savings.ACO_ID,
        savings.PERFORMANCE_YEAR,
        savings.PERIOD,
        savings.BENCHMARK_SUBMISSION_ID,
        cast(null as {{ dbt.type_string() }}) as ENROLLMENT_TYPE,
        case
            when savings.IS_CALCULABLE
                 and (enrollment_type_completeness.POPULATED_BENCHMARK_COUNT <> 4
                   or enrollment_type_completeness.POPULATED_PROPORTION_COUNT <> 4)
                then 'savings_calculable_but_incomplete'
            when not savings.IS_CALCULABLE
                 and savings.MEAN_PROJECTED_UPDATED_BENCHMARK is not null
                then 'savings_incalculable_but_derived'
        end as FAILURE
    from savings
    left join enrollment_type_completeness
        on savings.ACO_ID = enrollment_type_completeness.ACO_ID
       and savings.PERFORMANCE_YEAR = enrollment_type_completeness.PERFORMANCE_YEAR
       and savings.PERIOD = enrollment_type_completeness.PERIOD
       and savings.BENCHMARK_SUBMISSION_ID = enrollment_type_completeness.BENCHMARK_SUBMISSION_ID

)

select * from enrollment_type_failures where FAILURE is not null

union all

select * from savings_failures where FAILURE is not null
