{{ config(severity = 'warn') }}

{#-
    Warns when a delivery that arrived produced nothing in the final layer.

    This exists because of a hole that a green build hid. The final models pair
    a reported quarter with the benchmark deliveries of its own performance
    year, and assert_benchmark_rows_exist_for_every_pairing checks that every
    such pairing is present. But that test rebuilds its expectation with the same
    inner join on PERFORMANCE_YEAR that the model uses, so when the join is
    legitimately unsatisfiable — a QEXPU delivery for a performance year with no
    BNMRK delivery, or the reverse — the expectation empties at exactly the
    moment the fact does, and the two agree on nothing. Point the whole layer at
    a file store holding a benchmark for one year and quarterly reports for
    another and both facts come back with zero rows on a fully green build, with
    not one test firing.

    That is not a tautology in the pairing test; it is vacuity, and the fix is
    not to make that test stricter but to say the thing it cannot: workbooks
    came in, and nothing came out. The models' own header states that a
    silently vanished quarter is harder to notice than one full of NULLs. This
    is the same failure one level up — the entire layer vanishing rather than a
    row — and it deserves the same treatment.

      quarter_without_benchmark_delivery
          A reported quarter has no benchmark delivery for its performance
          year, so it contributes no rows. Ordinary early in a performance year,
          before CMS has shipped the March preliminary benchmark, and the reason
          this is a warning.

      benchmark_delivery_without_quarter
          A benchmark delivery has no reported quarter for its performance year,
          so it contributes no rows either. Also ordinary — the benchmark
          arrives before the first quarter closes.

    Both are legitimate mid-year states, which is exactly why neither can be an
    error and why both have to be audible. The difference between "CMS has not
    shipped it yet" and "the file store is misassembled and this layer is empty"
    is invisible in the output and obvious in this list.
-#}

with quarterly_delivery as (

    select distinct
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD
    from {{ ref('int_expenditures_quarterly') }}
    where IS_LATEST_SUBMISSION

),

benchmark_delivery as (

    select distinct
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID
    from {{ ref('int_benchmark_historical') }}

)

select
    quarterly_delivery.ACO_ID,
    quarterly_delivery.PERFORMANCE_YEAR,
    quarterly_delivery.PERIOD               as PERIOD,
    cast(null as {{ dbt.type_string() }})   as BENCHMARK_SUBMISSION_ID,
    'quarter_without_benchmark_delivery'    as FAILURE
from quarterly_delivery
left join benchmark_delivery
    on quarterly_delivery.ACO_ID = benchmark_delivery.ACO_ID
   and quarterly_delivery.PERFORMANCE_YEAR = benchmark_delivery.PERFORMANCE_YEAR
where benchmark_delivery.SUBMISSION_ID is null

union all

select
    benchmark_delivery.ACO_ID,
    benchmark_delivery.PERFORMANCE_YEAR,
    cast(null as {{ dbt.type_string() }})   as PERIOD,
    benchmark_delivery.SUBMISSION_ID        as BENCHMARK_SUBMISSION_ID,
    'benchmark_delivery_without_quarter'    as FAILURE
from benchmark_delivery
left join quarterly_delivery
    on benchmark_delivery.ACO_ID = quarterly_delivery.ACO_ID
   and benchmark_delivery.PERFORMANCE_YEAR = quarterly_delivery.PERFORMANCE_YEAR
where quarterly_delivery.PERIOD is null
