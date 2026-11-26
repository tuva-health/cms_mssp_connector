{{ config(severity='warn') }}

{#-
    fact_benchmark_aco_quarter's SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO,
    the sum of Table A1 [A] x [D] over the four enrollment types, agrees
    with the Weighted Average [D] that Table A1 prints (fct_settlement_risk,
    ENROLLMENT_TYPE = 'weighted_average') on every quarter row of a settled
    year (TUVA-160, 2026-11-25).

    The fact computes the sum rather than reading the printed row so that
    the per-type and aggregate figures beside the projection come from the
    same cells. CMS writes [A] and the weighted [D] rounded to about ten
    digits, so the two can differ by a few parts in 1e10; the tolerance is a
    relative 1e-8, well above that and well below any real disagreement.
    Warn, not error: a disagreement means CMS's weights and its printed
    aggregate do not agree, which is reported, not resolved here. A year
    whose sum or printed row is blank is not compared.

    One row per ACO, year and quarter that disagrees.
-#}

{%- set tolerance = 1e-8 -%}

with printed as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        {{ to_double('UNCAPPED_RISK_RATIO') }}              as PRINTED_WEIGHTED_AVERAGE
    from {{ ref('fct_settlement_risk') }}
    where ENROLLMENT_TYPE = 'weighted_average'

)

select
    fact.ACO_ID,
    fact.PERFORMANCE_YEAR,
    fact.PERIOD,
    fact.SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO            as WEIGHTED_SUM,
    printed.PRINTED_WEIGHTED_AVERAGE                        as PRINTED_WEIGHTED_AVERAGE
from {{ ref('fact_benchmark_aco_quarter') }} as fact
inner join printed
    on printed.ACO_ID = fact.ACO_ID
   and printed.PERFORMANCE_YEAR = fact.PERFORMANCE_YEAR
where fact.SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO is not null
  and printed.PRINTED_WEIGHTED_AVERAGE is not null
  and abs(fact.SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO - printed.PRINTED_WEIGHTED_AVERAGE)
      > {{ tolerance }} * greatest(
            1.0,
            abs(fact.SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO),
            abs(printed.PRINTED_WEIGHTED_AVERAGE)
        )
