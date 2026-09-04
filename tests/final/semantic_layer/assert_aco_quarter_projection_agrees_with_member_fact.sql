{#-
    fact_benchmark_aco_quarter and fact_member_month_benchmark must choose the
    same projection for every performance year.

    Each carries its own copy of the rule — the highest QUARTER_NUM of the
    year on fct_projected_savings_current, lowest ACO_ID on ties — rather
    than sharing a model, so nothing but this test holds the two together.
    The member fact reads its cap factor off the ACO fact's
    IS_CURRENT_PROJECTION row, so a disagreement would pair one quarter's
    rates with another quarter's cap and the reconciliation test would report
    a mismatch it could not explain.

    Compared on every performance year the member fact has a benchmark for:
    the ACO fact's current row and the member fact's distinct benchmark
    provenance must match on period, quarter and both submission ids. A year
    the member fact has no member-months in is outside the comparison; it has
    nothing to agree about.

      missing_from_aco_fact       the member fact's projection has no current
                                  row in the ACO fact
      missing_from_member_fact    the ACO fact's current row is not what the
                                  member fact read, or the member fact read
                                  more than one
-#}

with member_projection as (

    select distinct
        ACO_ID,
        PERFORMANCE_YEAR,
        BENCHMARK_PERIOD                            as PERIOD,
        BENCHMARK_QUARTER_NUM                       as QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        QUARTERLY_SUBMISSION_ID
    from {{ ref('fact_member_month_benchmark') }}
    where HAS_BENCHMARK

),

aco_projection as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        QUARTERLY_SUBMISSION_ID
    from {{ ref('fact_benchmark_aco_quarter') }}
    where IS_CURRENT_PROJECTION
      and PERFORMANCE_YEAR in (select PERFORMANCE_YEAR from member_projection)

)

select
    coalesce(member_projection.PERFORMANCE_YEAR, aco_projection.PERFORMANCE_YEAR)
                                                    as PERFORMANCE_YEAR,
    coalesce(member_projection.ACO_ID, aco_projection.ACO_ID)
                                                    as ACO_ID,
    coalesce(member_projection.PERIOD, aco_projection.PERIOD)
                                                    as PERIOD,
    coalesce(member_projection.BENCHMARK_SUBMISSION_ID, aco_projection.BENCHMARK_SUBMISSION_ID)
                                                    as BENCHMARK_SUBMISSION_ID,
    case
        when aco_projection.PERFORMANCE_YEAR is null    then 'missing_from_aco_fact'
        when member_projection.PERFORMANCE_YEAR is null then 'missing_from_member_fact'
    end                                             as FAILURE
from member_projection
full outer join aco_projection
    on aco_projection.ACO_ID = member_projection.ACO_ID
    and aco_projection.PERFORMANCE_YEAR = member_projection.PERFORMANCE_YEAR
    and aco_projection.PERIOD = member_projection.PERIOD
    and aco_projection.QUARTER_NUM = member_projection.QUARTER_NUM
    and aco_projection.BENCHMARK_SUBMISSION_ID = member_projection.BENCHMARK_SUBMISSION_ID
    and coalesce(aco_projection.QUARTERLY_SUBMISSION_ID, '')
        = coalesce(member_projection.QUARTERLY_SUBMISSION_ID, '')
where aco_projection.PERFORMANCE_YEAR is null
   or member_projection.PERFORMANCE_YEAR is null
