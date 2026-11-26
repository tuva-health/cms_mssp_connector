{{ config(severity='warn') }}

{#-
    A settled year's Table A1, as fact_benchmark_aco_quarter carries it from
    the settlement population (TUVA-162, M-SETTLE), reproduces the settlement
    workbook's own A1 (fct_settlement_risk): [A], [C], [D], [F], [G], [H] and
    [I] per type, and the weighted-average [D] and [G], each within a
    relative 1e-4. Every quarter row of the year is checked.

    Warn, not error: the method reproduced A1 on real data (TUVA-161), but
    CMS can leave out a decedent's death month from the demographic mean,
    which no general rule reproduces, so a small [F]/[G] gap is possible and
    is reported rather than failing a client's build. The unit test
    test_settlement_risk_ratio_reproduces_table_a1 pins the arithmetic to
    1e-12. Only a year with a settlement population is compared: a year with
    a workbook but no settlement AALR has nothing to reproduce from.
-#}

{%- set tolerance = 1e-4 -%}
{%- set enrollment_types = ['esrd', 'disabled', 'aged_dual', 'aged_non_dual'] -%}
{%- set per_type = [
    ('RISK_SCORE_WEIGHT', 'SETTLEMENT_RISK_SCORE_WEIGHT'),
    ('PY_CMS_HCC_RISK_SCORE', 'SETTLEMENT_PY_RISK_SCORE'),
    ('UNCAPPED_RISK_RATIO', 'SETTLEMENT_RISK_RATIO'),
    ('PY_DEMOGRAPHIC_RISK_SCORE', 'SETTLEMENT_PY_DEMOGRAPHIC_RISK_SCORE'),
    ('DEMOGRAPHIC_RISK_RATIO', 'SETTLEMENT_DEMOGRAPHIC_RISK_RATIO'),
    ('FINAL_RISK_RATIO', 'SETTLEMENT_FINAL_RISK_RATIO'),
] -%}

with computed as (

    {%- for enrollment_type in enrollment_types %}
    {%- set t = enrollment_type | upper %}
    {%- for workbook_column, fact_column in per_type %}
    select ACO_ID, PERFORMANCE_YEAR, PERIOD, '{{ enrollment_type }}' as ENROLLMENT_TYPE,
           '{{ workbook_column }}' as FIELD, {{ fact_column }}_{{ t }} as COMPUTED
    from {{ ref('fact_benchmark_aco_quarter') }}
    union all
    {%- endfor %}
    select ACO_ID, PERFORMANCE_YEAR, PERIOD, '{{ enrollment_type }}', 'AGGREGATE_CAP', SETTLEMENT_AGGREGATE_CAP
    from {{ ref('fact_benchmark_aco_quarter') }}
    union all
    {%- endfor %}
    select ACO_ID, PERFORMANCE_YEAR, PERIOD, 'weighted_average', 'UNCAPPED_RISK_RATIO', SETTLEMENT_AGGREGATE_RISK_RATIO
    from {{ ref('fact_benchmark_aco_quarter') }}
    union all
    select ACO_ID, PERFORMANCE_YEAR, PERIOD, 'weighted_average', 'DEMOGRAPHIC_RISK_RATIO', SETTLEMENT_AGGREGATE_DEMOGRAPHIC_RISK_RATIO
    from {{ ref('fact_benchmark_aco_quarter') }}

),

settled_years as (

    select distinct ACO_ID, PERFORMANCE_YEAR
    from {{ ref('int_settlement_risk_ratio') }}

),

workbook as (

    {%- for workbook_column in (per_type | map('first') | list) + ['AGGREGATE_CAP'] %}
    select ACO_ID, PERFORMANCE_YEAR, ENROLLMENT_TYPE, '{{ workbook_column }}' as FIELD,
           {{ to_double(workbook_column) }} as PRINTED
    from {{ ref('fct_settlement_risk') }}
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}

)

select
    computed.ACO_ID,
    computed.PERFORMANCE_YEAR,
    computed.PERIOD,
    computed.ENROLLMENT_TYPE,
    computed.FIELD,
    computed.COMPUTED,
    workbook.PRINTED
from computed
inner join settled_years
    on settled_years.ACO_ID = computed.ACO_ID
    and settled_years.PERFORMANCE_YEAR = computed.PERFORMANCE_YEAR
inner join workbook
    on workbook.ACO_ID = computed.ACO_ID
    and workbook.PERFORMANCE_YEAR = computed.PERFORMANCE_YEAR
    and workbook.ENROLLMENT_TYPE = computed.ENROLLMENT_TYPE
    and workbook.FIELD = computed.FIELD
where workbook.PRINTED is not null
  and (
      computed.COMPUTED is null
      or abs(computed.COMPUTED - workbook.PRINTED)
         > {{ tolerance }} * greatest(abs(workbook.PRINTED), {{ to_double(1e-9) }})
  )
