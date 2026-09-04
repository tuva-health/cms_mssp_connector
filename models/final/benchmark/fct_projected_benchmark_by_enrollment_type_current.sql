{#-
    The default read path over fct_projected_benchmark_by_enrollment_type: the
    same figures, filtered to the latest calculable benchmark delivery, with
    [M] also expressed per member per month.

    That fact materialises every pairing of a reported quarter with a benchmark
    delivery, so an unfiltered query over it returns up to three answers per
    quarter and a naive aggregate averages across them. Every downstream
    consumer wants the same two predicates, and this model applies them once:
    IS_LATEST_BENCHMARK_SUBMISSION, for one delivery per performance year, and
    IS_CALCULABLE, for rows that have an [M] at all. The result is one row per
    ACO, performance year, quarter and enrollment type. The two flags are not
    carried, because they are true on every row by construction.

    Nothing is derived here except the division. [M] is an annual per
    person-year figure; twelve months is the whole of the conversion. Both
    operands go through to_double so it is the same operation as every other
    division in the calculation and stays in floating point however the
    operands arrive — [M] is already a double today, and the cast costs
    nothing while making that not a thing the reader has to know.

    Questions about a delivery other than the latest — reconciliation against
    a June preliminary-final, or which quarters the March preliminary could not
    compute — belong on the full-grain fact, where every pairing is a row and
    none is chosen.
-#}

with per_enrollment_type as (

    select *
    from {{ ref('fct_projected_benchmark_by_enrollment_type') }}
    where IS_LATEST_BENCHMARK_SUBMISSION
      and IS_CALCULABLE

)

select
    ACO_ID                                              as ACO_ID,
    PERFORMANCE_YEAR                                    as PERFORMANCE_YEAR,
    PERIOD                                              as PERIOD,
    QUARTER_NUM                                         as QUARTER_NUM,
    BENCHMARK_SUBMISSION_ID                             as BENCHMARK_SUBMISSION_ID,
    ENROLLMENT_TYPE                                     as ENROLLMENT_TYPE,
    ENROLLMENT_TYPE_LABEL                               as ENROLLMENT_TYPE_LABEL,
    ENROLLMENT_TYPE_SORT                                as ENROLLMENT_TYPE_SORT,

    NATIONAL_BASE_EXPENDITURE_PER_CAPITA                as NATIONAL_BASE_EXPENDITURE_PER_CAPITA,
    NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA             as NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
    NATIONAL_EXPENDITURE_UPDATE_FACTOR                  as NATIONAL_EXPENDITURE_UPDATE_FACTOR,
    REGIONAL_BASE_EXPENDITURE_PER_CAPITA                as REGIONAL_BASE_EXPENDITURE_PER_CAPITA,
    REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA             as REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
    REGIONAL_EXPENDITURE_UPDATE_FACTOR                  as REGIONAL_EXPENDITURE_UPDATE_FACTOR,
    NATIONAL_WEIGHT                                     as NATIONAL_WEIGHT,
    REGIONAL_WEIGHT                                     as REGIONAL_WEIGHT,
    NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR             as NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR,
    ACCOUNTABLE_CARE_PROSPECTIVE_TREND                  as ACCOUNTABLE_CARE_PROSPECTIVE_TREND,
    THREE_WAY_BLENDED_UPDATE_FACTOR                     as THREE_WAY_BLENDED_UPDATE_FACTOR,
    HISTORICAL_BENCHMARK_EXPENDITURE                    as HISTORICAL_BENCHMARK_EXPENDITURE,
    PROJECTED_UPDATED_BENCHMARK_EXPENDITURE             as PROJECTED_UPDATED_BENCHMARK_EXPENDITURE,

    {#- [M] / 12 -#}
    {{ to_double('PROJECTED_UPDATED_BENCHMARK_EXPENDITURE') }} / {{ to_double(12) }}
                                                        as PROJECTED_UPDATED_BENCHMARK_EXPENDITURE_PMPM,

    PERSON_YEARS                                        as PERSON_YEARS,
    TOTAL_PERSON_YEARS                                  as TOTAL_PERSON_YEARS,
    ENROLLMENT_PROPORTION                               as ENROLLMENT_PROPORTION,

    QUARTERLY_SUBMISSION_ID                             as QUARTERLY_SUBMISSION_ID,
    ANNUAL_EXPENDITURE_BENCHMARK_YEAR                   as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
    ANNUAL_EXPENDITURE_SUBMISSION_ID                    as ANNUAL_EXPENDITURE_SUBMISSION_ID,
    ACPT_PERFORMANCE_YEAR_LABEL                         as ACPT_PERFORMANCE_YEAR_LABEL,
    IS_AGREEMENT_DEFAULTED                              as IS_AGREEMENT_DEFAULTED

from per_enrollment_type
