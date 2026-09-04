{#-
    For every performance year and enrollment type, the risk-adjusted rate
    summed over assigned member-months must equal the enrollment-type rate
    times the sum of the members' risk ratios.

    The risk-adjusted rate is defined row by row as the type rate times the
    row's ratio, so this identity holds exactly when two things are true: the
    type rate is one number across the whole year and type — one projection
    per year, as the model promises — and no row has a ratio without a
    risk-adjusted rate or the other way round. A second projection leaking in
    for a subset of months, or a rate computed from a different type's [M]
    than the ratio's [C], each break it, and neither is visible on any single
    row.

    Rows are restricted to assigned member-months with a type rate, because
    that is the population the benchmark report is about; a NULL type rate
    has nothing to reconcile. Within that set the sums run over every row, so
    a row that carries a ratio but not a rate — or the reverse — moves one sum
    and not the other. NULL contributes nothing to either side, which is what
    a member without a score should do.

    The tolerance is relative, 1e-9 of the expected sum, sized to the
    floating point noise of summing tens of thousands of doubles — of order
    n x 2^-53, so 1e-11 at a hundred thousand rows — and far below any of the
    failures described, which are whole rates. A year and type whose rates
    disagree with themselves is reported separately as rate_not_constant.
-#}

with per_year_and_type as (

    select
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        min(ENROLLMENT_TYPE_BENCHMARK_PMPM)         as MIN_ENROLLMENT_TYPE_BENCHMARK_PMPM,
        max(ENROLLMENT_TYPE_BENCHMARK_PMPM)         as MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM,
        sum(RISK_RATIO)                             as RISK_RATIO_SUM,
        sum(RISK_ADJUSTED_BENCHMARK_PMPM)           as RISK_ADJUSTED_BENCHMARK_SUM
    from {{ ref('fact_member_month_benchmark') }}
    where IS_ASSIGNED
      and ENROLLMENT_TYPE_BENCHMARK_PMPM is not null
    group by PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

compared as (

    select
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        MIN_ENROLLMENT_TYPE_BENCHMARK_PMPM,
        MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM,
        RISK_RATIO_SUM,
        RISK_ADJUSTED_BENCHMARK_SUM,
        MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM * coalesce(RISK_RATIO_SUM, 0)
                                                    as EXPECTED_RISK_ADJUSTED_BENCHMARK_SUM
    from per_year_and_type

)

select
    PERFORMANCE_YEAR,
    ENROLLMENT_TYPE,
    MIN_ENROLLMENT_TYPE_BENCHMARK_PMPM,
    MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM,
    RISK_RATIO_SUM,
    RISK_ADJUSTED_BENCHMARK_SUM,
    EXPECTED_RISK_ADJUSTED_BENCHMARK_SUM,
    case
        when MIN_ENROLLMENT_TYPE_BENCHMARK_PMPM <> MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM
            then 'rate_not_constant'
        else 'sum_does_not_reconcile'
    end                                             as FAILURE
from compared
where MIN_ENROLLMENT_TYPE_BENCHMARK_PMPM <> MAX_ENROLLMENT_TYPE_BENCHMARK_PMPM
   or abs(coalesce(RISK_ADJUSTED_BENCHMARK_SUM, 0) - EXPECTED_RISK_ADJUSTED_BENCHMARK_SUM)
        > 1e-9 * abs(EXPECTED_RISK_ADJUSTED_BENCHMARK_SUM)
