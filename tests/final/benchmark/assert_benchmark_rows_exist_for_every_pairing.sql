{#-
    Every reported quarter, paired with every benchmark delivery of its
    performance year, must appear in both final models — with four enrollment
    type rows and one savings row — whether or not the pairing computes
    anything.

    This is the test that guards the phase's central design decision. The March
    preliminary delivery ships no Table 6, so [J] is absent and [K], [M], [P]
    and [R] cannot be derived for anything paired with it. The reference
    implementation refuses that delivery outright. This project keeps the row
    and NULLs what it cannot compute, because a quarter that vanished from a
    report is far harder to notice than one full of NULLs — and the only thing
    standing between "kept with NULLs" and "silently dropped" is a `left join`
    that a future edit could turn into an `inner join` without changing a single
    value in the output.

    The expected pairings are rebuilt here from the intermediate models rather
    than read back off the fact, so the fact is checked against its sources and
    not against itself. Turn any of the ten input joins into an inner join,
    or pin the benchmark side to its latest submission, and the pairing
    disappears from the fact while remaining in the expectation.

    ENROLLMENT_TYPE_COUNT is checked against the literal 4, which is not a
    restatement of anything the model computes: it is the number of Medicare
    enrollment types CMS's blend has, fixed by the calculation rather than by
    the data. A pairing carrying three of them is broken even if every one of
    the three is right.

      missing_from_enrollment_fact   the pairing produced no per-type rows
      wrong_enrollment_type_count    it produced some, but not all four
      missing_from_savings_fact      the pairing produced no savings row
      duplicated_in_savings_fact     it produced more than one
-#}

with expected_pairing as (

    select distinct
        quarterly.ACO_ID            as ACO_ID,
        quarterly.PERFORMANCE_YEAR  as PERFORMANCE_YEAR,
        quarterly.PERIOD            as PERIOD,
        benchmark.SUBMISSION_ID     as BENCHMARK_SUBMISSION_ID
    from {{ ref('int_expenditures_quarterly') }} as quarterly
    inner join {{ ref('int_benchmark_historical') }} as benchmark
        on quarterly.ACO_ID = benchmark.ACO_ID
       and quarterly.PERFORMANCE_YEAR = benchmark.PERFORMANCE_YEAR
    where quarterly.IS_LATEST_SUBMISSION

),

enrollment_fact as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        count(distinct ENROLLMENT_TYPE) as ENROLLMENT_TYPE_COUNT
    from {{ ref('fct_projected_benchmark_by_enrollment_type') }}
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

),

savings_fact as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        count(*) as SAVINGS_ROW_COUNT
    from {{ ref('fct_projected_savings') }}
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

)

select
    expected_pairing.ACO_ID,
    expected_pairing.PERFORMANCE_YEAR,
    expected_pairing.PERIOD,
    expected_pairing.BENCHMARK_SUBMISSION_ID,
    enrollment_fact.ENROLLMENT_TYPE_COUNT,
    savings_fact.SAVINGS_ROW_COUNT,
    case
        when enrollment_fact.ENROLLMENT_TYPE_COUNT is null then 'missing_from_enrollment_fact'
        when enrollment_fact.ENROLLMENT_TYPE_COUNT <> 4    then 'wrong_enrollment_type_count'
        when savings_fact.SAVINGS_ROW_COUNT is null        then 'missing_from_savings_fact'
        when savings_fact.SAVINGS_ROW_COUNT <> 1           then 'duplicated_in_savings_fact'
    end as FAILURE

from expected_pairing

left join enrollment_fact
    on expected_pairing.ACO_ID = enrollment_fact.ACO_ID
   and expected_pairing.PERFORMANCE_YEAR = enrollment_fact.PERFORMANCE_YEAR
   and expected_pairing.PERIOD = enrollment_fact.PERIOD
   and expected_pairing.BENCHMARK_SUBMISSION_ID = enrollment_fact.BENCHMARK_SUBMISSION_ID

left join savings_fact
    on expected_pairing.ACO_ID = savings_fact.ACO_ID
   and expected_pairing.PERFORMANCE_YEAR = savings_fact.PERFORMANCE_YEAR
   and expected_pairing.PERIOD = savings_fact.PERIOD
   and expected_pairing.BENCHMARK_SUBMISSION_ID = savings_fact.BENCHMARK_SUBMISSION_ID

where enrollment_fact.ENROLLMENT_TYPE_COUNT is null
   or enrollment_fact.ENROLLMENT_TYPE_COUNT <> 4
   or savings_fact.SAVINGS_ROW_COUNT is null
   or savings_fact.SAVINGS_ROW_COUNT <> 1
