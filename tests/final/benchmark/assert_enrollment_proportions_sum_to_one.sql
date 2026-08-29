{{ config(severity = 'warn') }}

{#-
    The four enrollment proportions [O] should sum to 1 for each pairing.

    [O] is each enrollment type's person years over the section's Total row, and
    [P] weights the four projected benchmarks by them. If they do not sum to 1,
    [P] is not a mean of anything — it is silently scaled, and every savings
    percentage derived from it is wrong by that scale factor. Nothing else in
    either model would notice.

    Two decisions here follow from one fact, and an earlier version of this test
    got both of them wrong by not following it through.

    The fact is that the denominator is CMS's own Total row and not the sum of
    the four parts, because CMS rounds every row of the sheet independently and
    the four need not add to what it prints. That is why the identity has to be
    tested rather than assumed — the model cannot make it true.

    It is also why this is a warning and not an error, and why the tolerance is
    1e-4 rather than something tight. A gap inside that bound is CMS's rounding,
    not this project's arithmetic, and it is not a state anyone here can fix; a
    build that stops on it strands the operator with no way forward.

    What CMS actually emits, in the deliveries seen so far, is not rounded at
    all: person years arrive at full precision — values running to sixteen
    significant digits, the repeating thirds and twelfths of a monthly average
    — against an integer Total, and the four parts reconstruct that Total to
    within floating point noise. The observed |Sigma[O] - 1| is 0.0 exactly. So
    the bound is not calibrated to observed error; there is none to calibrate
    to.

    It is calibrated to the worst case the premise admits. If a future sheet
    printed person years to two decimal places, the four parts and the Total
    would each carry up to 0.005 of rounding error, so the numerator of
    Sigma[O] - 1 could reach roughly 0.025 — against a total of a few hundred
    person years, of order 1e-4. That is the case this bound is sized to
    tolerate, not the case in front of us.

    Below the bound there is nothing but arithmetic: four double divisions
    summed contribute of order 1e-16, twelve orders down, so this can never
    fire on noise. Above it, 1e-4 is 0.01% of the population — a discrepancy
    that small is already far larger than any rounding of full-precision
    figures, and the test has been checked to fire on one.

    What the warning is really for is the other side of that bound. A gap much
    larger than rounding means the denominator is not the population the parts
    came from at all: a cohort missing from the numerator, or a Total row read
    from the wrong section. Neither is a rounding artefact and neither is
    visible anywhere else.

    Pinning the *value* of [O] is a separate job and is done by the unit tests
    on fct_projected_benchmark_by_enrollment_type, which this test cannot do:
    proportions summing to 1 is exactly the property a wrong-but-self-consistent
    denominator preserves.

    Rows where any of the four proportions is NULL are out of scope: [O] is
    missing rather than wrong there, [P] is NULL by construction, and
    assert_incalculable_rows_are_null_throughout covers that case.
-#}

with proportions as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        count(*)                            as ENROLLMENT_TYPE_COUNT,
        count(ENROLLMENT_PROPORTION)        as POPULATED_COUNT,
        sum(ENROLLMENT_PROPORTION)          as PROPORTION_SUM
    from {{ ref('fct_projected_benchmark_by_enrollment_type') }}
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

)

select
    ACO_ID,
    PERFORMANCE_YEAR,
    PERIOD,
    BENCHMARK_SUBMISSION_ID,
    PROPORTION_SUM,
    abs(PROPORTION_SUM - 1) as ABSOLUTE_DIFFERENCE
from proportions
where POPULATED_COUNT = ENROLLMENT_TYPE_COUNT
  and abs(PROPORTION_SUM - 1) > 0.0001
