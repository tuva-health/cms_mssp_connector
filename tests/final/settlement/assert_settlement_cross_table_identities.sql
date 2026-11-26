{#-
    Fails when the settlement workbook's tables disagree where CMS's report
    footnotes say they are the same figure:

      * Table 2 [C] (capped risk ratio)       = Table A1 [I], per type
      * Table 2 [A] (historical benchmark)    = Table 1 [L], per type
      * Table 3 [D] (beneficiary proportions) = Table 2 [H], per type
      * Table 3 [F] (benchmark per capita)    = Table 2 [I]
      * Table 3 [MM] (net earned payment)     = [HH] - [KK]

    The facts read each figure where it is written, so a disagreement means a
    field is mapped to the wrong cell. The workbook stores doubles, so the
    comparison allows float rounding (settlement_values_differ). A pair with
    a blank side is not compared, except that a blank [KK] (no advance
    investment payment to recoup) counts as 0, so [MM] = [HH] is still
    checked.
-#}

{%- set types = settlement_enrollment_types() -%}

with settlement as (

    select * from {{ ref('fct_settlement') }}

),

risk as (

    select * from {{ ref('fct_settlement_risk') }}

),

historical as (

    select * from {{ ref('fct_settlement_historical_benchmark') }}

),

checks as (

{%- for type in types %}
    select
        settlement.ACO_ID, settlement.PERFORMANCE_YEAR,
        'T2 [C] = A1 [I], {{ type }}'                   as IDENTITY,
        settlement.CAPPED_RISK_RATIO_{{ type | upper }} as LEFT_VALUE,
        risk.FINAL_RISK_RATIO                           as RIGHT_VALUE
    from settlement
    inner join risk
        on settlement.ACO_ID = risk.ACO_ID
       and settlement.PERFORMANCE_YEAR = risk.PERFORMANCE_YEAR
       and risk.ENROLLMENT_TYPE = '{{ type }}'
    union all
    select
        settlement.ACO_ID, settlement.PERFORMANCE_YEAR,
        'T2 [A] = T1 [L], {{ type }}',
        settlement.HISTORICAL_BENCHMARK_{{ type | upper }},
        historical.HISTORICAL_BENCHMARK
    from settlement
    inner join historical
        on settlement.ACO_ID = historical.ACO_ID
       and settlement.PERFORMANCE_YEAR = historical.PERFORMANCE_YEAR
       and historical.ENROLLMENT_TYPE = '{{ type }}'
    union all
    select
        ACO_ID, PERFORMANCE_YEAR,
        'T3 [D] = T2 [H], {{ type }}',
        ASSIGNED_BENEFICIARY_PROPORTION_{{ type | upper }},
        UPDATED_BENCHMARK_BENEFICIARY_PROPORTION_{{ type | upper }}
    from settlement
    union all
{%- endfor %}
    select
        ACO_ID, PERFORMANCE_YEAR,
        'T3 [F] = T2 [I]',
        BENCHMARK_PER_CAPITA,
        UPDATED_BENCHMARK
    from settlement
    union all
    select
        ACO_ID, PERFORMANCE_YEAR,
        'T3 [MM] = [HH] - [KK]',
        NET_EARNED_PERFORMANCE_PAYMENT,
        EARNED_PERFORMANCE_PAYMENT - coalesce(AIP_RECOUPMENT, 0)
    from settlement

)

select *
from checks
where {{ settlement_values_differ('LEFT_VALUE', 'RIGHT_VALUE') }}
