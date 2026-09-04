{#-
    The default read path over fct_projected_savings: the same figures,
    filtered to the latest calculable benchmark delivery, with [P] and [Q]
    also expressed per member per month.

    One row per ACO, performance year and quarter — the grain of
    fct_projected_benchmark_by_enrollment_type_current with the enrollment
    types collapsed, and the same two predicates applied for the same reason:
    the full-grain fact carries every pairing of a quarter with a benchmark
    delivery, and every downstream consumer wants only the latest one that
    computed. IS_LATEST_BENCHMARK_SUBMISSION and IS_CALCULABLE are not carried,
    because they are true on every row by construction.

    Nothing is derived here except the two divisions, and they are not quite
    alike. [P] is already a double, so casting it is a formality. [Q] arrives
    as the fixed-point decimal the staging layer typed it as, and without the
    cast its quotient would be whatever the adapter's fixed-point rule makes
    it — a double on DuckDB, a 24-scale decimal on Snowflake — see to_double.
    Both go through the same macro so the two PMPMs are the same kind of
    number and can be set beside each other.

    Questions about a delivery other than the latest, or about which pairings
    could not be computed, belong on the full-grain fact.
-#}

with projected_savings as (

    select *
    from {{ ref('fct_projected_savings') }}
    where IS_LATEST_BENCHMARK_SUBMISSION
      and IS_CALCULABLE

)

select
    ACO_ID                                              as ACO_ID,
    PERFORMANCE_YEAR                                    as PERFORMANCE_YEAR,
    PERIOD                                              as PERIOD,
    QUARTER_NUM                                         as QUARTER_NUM,
    BENCHMARK_SUBMISSION_ID                             as BENCHMARK_SUBMISSION_ID,

    MEAN_PROJECTED_UPDATED_BENCHMARK                    as MEAN_PROJECTED_UPDATED_BENCHMARK,

    {#- [P] / 12 -#}
    {{ to_double('MEAN_PROJECTED_UPDATED_BENCHMARK') }} / {{ to_double(12) }}
                                                        as MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM,

    ACO_EXPENDITURE_PER_CAPITA                          as ACO_EXPENDITURE_PER_CAPITA,

    {#- [Q] / 12 -#}
    {{ to_double('ACO_EXPENDITURE_PER_CAPITA') }} / {{ to_double(12) }}
                                                        as ACO_EXPENDITURE_PER_CAPITA_PMPM,

    PROJECTED_SAVINGS_PERCENTAGE                        as PROJECTED_SAVINGS_PERCENTAGE,
    ASSIGNED_BENEFICIARIES                              as ASSIGNED_BENEFICIARIES,
    MSR_TYPE                                            as MSR_TYPE,
    FIXED_MSR_RATE                                      as FIXED_MSR_RATE,
    ACO_TRACK                                           as ACO_TRACK,
    MSR_BASIS_APPLIED                                   as MSR_BASIS_APPLIED,
    ESTIMATED_MSR                                       as ESTIMATED_MSR,
    EXPENDITURES_BELOW_BENCHMARK                        as EXPENDITURES_BELOW_BENCHMARK,
    SAVINGS_EXCEEDS_MSR                                 as SAVINGS_EXCEEDS_MSR,
    SAVINGS_STATUS                                      as SAVINGS_STATUS,

    QUARTERLY_SUBMISSION_ID                             as QUARTERLY_SUBMISSION_ID,
    ANNUAL_EXPENDITURE_BENCHMARK_YEAR                   as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
    ANNUAL_EXPENDITURE_SUBMISSION_ID                    as ANNUAL_EXPENDITURE_SUBMISSION_ID,
    ACPT_PERFORMANCE_YEAR_LABEL                         as ACPT_PERFORMANCE_YEAR_LABEL,
    IS_AGREEMENT_DEFAULTED                              as IS_AGREEMENT_DEFAULTED

from projected_savings
