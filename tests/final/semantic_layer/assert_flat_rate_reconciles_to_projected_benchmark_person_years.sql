{{ config(severity = 'warn') }}

{#-
    The flat rate times the assigned member-months of a performance year
    should reconcile to [P] times the person years of the quarterly report
    the projection was read from.

    [P] is per person-year and the flat rate is [P]/12, so the identity is
    really about the population: the assigned member-months the fact sees
    against the person years CMS counted. It is the one check that ties the
    member-month spine — Tuva's member months, the assignment list, the MBI
    crosswalks — back to the report the rates came from. A projection paired
    with the wrong year, a rate not divided by twelve, or a spine missing half
    its members would each show up here as a ratio far from one.

    Two facts about the report shape the comparison. First, the quarterly
    person years are annualised: on the PY2025 Q4 delivery TOTAL_PERSON_YEARS
    times twelve is 67,484.0, exactly the member-months of the Q4 assignment
    list for the twelve months of 2025, and on the PY2026 Q2 delivery it is
    within one percent of the Q2 list's six months of 2026 times two. So the
    expected side is [P] x TOTAL_PERSON_YEARS x (months covered / 12), with
    the months covered being three times the projection's quarter, and the
    observed side counts only assigned member-months in those months.

    Second, the two populations are not the same population, and this is the
    reason the test warns rather than fails. The report counts the members on
    the assignment list CMS built for that quarter. The fact counts every
    member-month any assignment list covers, and the lists for the next
    performance year reach back into this one: a PY2026 quarterly list covers
    the twelve months from July 2025, so its members' 2025 months are assigned
    in the fact and absent from the PY2025 report. In the client's dev data
    that puts the observed side 34 percent over the expected for 2025 and
    within one percent of it for 2026, where no later list yet exists. The
    gap is assignment timing, not arithmetic, and it is one-sided: the fact
    can carry more assigned member-months than the report, never fewer, once
    every listed member lands in the spine.

    The band is therefore asymmetric: a ratio below 0.9 means the spine is
    losing members the report counted, and one above 1.5 means more than a
    later list's overlap can explain. Both observed values sit inside it, and
    either of the arithmetic failures above lands well outside.
-#}

with benchmark as (

    select
        PERFORMANCE_YEAR,
        ACO_ID,
        BENCHMARK_PERIOD,
        BENCHMARK_QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        FLAT_BENCHMARK_PMPM,
        YEAR_MONTH,
        IS_ASSIGNED
    from {{ ref('fact_member_month_benchmark') }}
    where HAS_BENCHMARK

),

observed as (

    select
        PERFORMANCE_YEAR,
        ACO_ID,
        BENCHMARK_PERIOD,
        BENCHMARK_QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        max(FLAT_BENCHMARK_PMPM)                    as FLAT_BENCHMARK_PMPM,
        count(*)                                    as ASSIGNED_MEMBER_MONTHS,
        sum(FLAT_BENCHMARK_PMPM)                    as FLAT_BENCHMARK_TOTAL
    from benchmark
    where IS_ASSIGNED
      and cast(substring(YEAR_MONTH, 5, 2) as {{ dbt.type_int() }}) <= 3 * BENCHMARK_QUARTER_NUM
    group by PERFORMANCE_YEAR, ACO_ID, BENCHMARK_PERIOD, BENCHMARK_QUARTER_NUM, BENCHMARK_SUBMISSION_ID

),

-- The Total row's person years are the same on all four enrollment-type rows
-- of a pairing; max collapses them without choosing.
person_years as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        max(TOTAL_PERSON_YEARS)                     as TOTAL_PERSON_YEARS
    from {{ ref('fct_projected_benchmark_by_enrollment_type_current') }}
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

),

compared as (

    select
        observed.PERFORMANCE_YEAR,
        observed.ACO_ID,
        observed.BENCHMARK_PERIOD,
        observed.BENCHMARK_SUBMISSION_ID,
        observed.ASSIGNED_MEMBER_MONTHS,
        person_years.TOTAL_PERSON_YEARS,
        observed.FLAT_BENCHMARK_TOTAL,

        {#- [P] x person years x (months covered / 12), with [P] = 12 x the flat rate -#}
        observed.FLAT_BENCHMARK_PMPM
            * {{ to_double('person_years.TOTAL_PERSON_YEARS') }}
            * {{ to_double('3 * observed.BENCHMARK_QUARTER_NUM') }}
                                                    as EXPECTED_FLAT_BENCHMARK_TOTAL
    from observed
    left join person_years
        on person_years.ACO_ID = observed.ACO_ID
        and person_years.PERFORMANCE_YEAR = observed.PERFORMANCE_YEAR
        and person_years.PERIOD = observed.BENCHMARK_PERIOD
        and person_years.BENCHMARK_SUBMISSION_ID = observed.BENCHMARK_SUBMISSION_ID

),

-- safe_divide, so a missing or zero expectation is a NULL ratio and a
-- reported row rather than a division error.
ratios as (

    select
        compared.*,
        {{ safe_divide('FLAT_BENCHMARK_TOTAL', 'EXPECTED_FLAT_BENCHMARK_TOTAL') }}
                                                    as OBSERVED_TO_EXPECTED_RATIO
    from compared

)

select
    PERFORMANCE_YEAR,
    ACO_ID,
    BENCHMARK_PERIOD,
    BENCHMARK_SUBMISSION_ID,
    ASSIGNED_MEMBER_MONTHS,
    TOTAL_PERSON_YEARS,
    FLAT_BENCHMARK_TOTAL,
    EXPECTED_FLAT_BENCHMARK_TOTAL,
    OBSERVED_TO_EXPECTED_RATIO
from ratios
where OBSERVED_TO_EXPECTED_RATIO is null
   or OBSERVED_TO_EXPECTED_RATIO < 0.9
   or OBSERVED_TO_EXPECTED_RATIO > 1.5
