{#-
    The settled year's member-month settlement columns agree with the ACO
    fact's settlement A1 (TUVA-162), so both facts carry one settlement:

    1. Every member-month's SETTLEMENT_FINAL_RISK_RATIO is the [I] that
       fact_benchmark_aco_quarter carries for its settlement type and year.
    2. Where the member fact carries every scored settlement person-month of
       a type and year (the count matches int_settlement_risk_ratio's
       SCORED_MEMBER_MONTHS), their mean SETTLEMENT_RISK_SCORE is the ACO
       fact's [C] for the type, within a relative 1e-9. Where it carries
       fewer (beneficiaries Tuva has no member-month for), there is no mean
       to compare, and the year is skipped for that type.

    Only years with a current projection row are compared, since the ACO
    fact has no row for a year without one. assert_settlement_risk_reproduces_table_a1
    holds the ACO fact itself to the workbook.
-#}

{%- set enrollment_types = ['esrd', 'disabled', 'aged_dual', 'aged_non_dual'] -%}

with aco_settlement as (

    {%- for enrollment_type in enrollment_types %}
    {%- set t = enrollment_type | upper %}
    select
        PERFORMANCE_YEAR,
        '{{ enrollment_type }}'                             as ENROLLMENT_TYPE,
        SETTLEMENT_PY_RISK_SCORE_{{ t }}                    as PY_CMS_HCC_RISK_SCORE,
        SETTLEMENT_FINAL_RISK_RATIO_{{ t }}                 as FINAL_RISK_RATIO
    from {{ ref('fact_benchmark_aco_quarter') }}
    where IS_CURRENT_PROJECTION
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}

),

member_months as (

    select
        PERFORMANCE_YEAR,
        SETTLEMENT_ENROLLMENT_TYPE                          as ENROLLMENT_TYPE,
        SETTLEMENT_RISK_SCORE,
        SETTLEMENT_FINAL_RISK_RATIO
    from {{ ref('fact_member_month_benchmark') }}
    where SETTLEMENT_ENROLLMENT_TYPE is not null

),

final_ratio_mismatch as (

    select
        member_months.PERFORMANCE_YEAR,
        member_months.ENROLLMENT_TYPE,
        'final risk ratio'                                  as CHECK_NAME,
        member_months.SETTLEMENT_FINAL_RISK_RATIO           as MEMBER_VALUE,
        aco_settlement.FINAL_RISK_RATIO                     as ACO_VALUE
    from member_months
    inner join aco_settlement
        on aco_settlement.PERFORMANCE_YEAR = member_months.PERFORMANCE_YEAR
        and aco_settlement.ENROLLMENT_TYPE = member_months.ENROLLMENT_TYPE
    where (member_months.SETTLEMENT_FINAL_RISK_RATIO is null) <> (aco_settlement.FINAL_RISK_RATIO is null)
       or abs(member_months.SETTLEMENT_FINAL_RISK_RATIO - aco_settlement.FINAL_RISK_RATIO)
          > 1e-9 * greatest(abs(aco_settlement.FINAL_RISK_RATIO), {{ to_double(1e-9) }})

),

member_means as (

    select
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        count(SETTLEMENT_RISK_SCORE)                        as SCORED_MEMBER_MONTHS,
        avg({{ to_double('SETTLEMENT_RISK_SCORE') }})       as PY_CMS_HCC_RISK_SCORE
    from member_months
    group by PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

settlement_counts as (

    select
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        sum(SCORED_MEMBER_MONTHS)                           as SCORED_MEMBER_MONTHS
    from {{ ref('int_settlement_risk_ratio') }}
    group by PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

mean_mismatch as (

    select
        member_means.PERFORMANCE_YEAR,
        member_means.ENROLLMENT_TYPE,
        'PY CMS-HCC mean'                                   as CHECK_NAME,
        member_means.PY_CMS_HCC_RISK_SCORE                  as MEMBER_VALUE,
        aco_settlement.PY_CMS_HCC_RISK_SCORE                as ACO_VALUE
    from member_means
    inner join settlement_counts
        on settlement_counts.PERFORMANCE_YEAR = member_means.PERFORMANCE_YEAR
        and settlement_counts.ENROLLMENT_TYPE = member_means.ENROLLMENT_TYPE
        and settlement_counts.SCORED_MEMBER_MONTHS = member_means.SCORED_MEMBER_MONTHS
    inner join aco_settlement
        on aco_settlement.PERFORMANCE_YEAR = member_means.PERFORMANCE_YEAR
        and aco_settlement.ENROLLMENT_TYPE = member_means.ENROLLMENT_TYPE
    where member_means.SCORED_MEMBER_MONTHS > 0
      and (
          aco_settlement.PY_CMS_HCC_RISK_SCORE is null
          or abs(member_means.PY_CMS_HCC_RISK_SCORE - aco_settlement.PY_CMS_HCC_RISK_SCORE)
             > 1e-9 * greatest(abs(aco_settlement.PY_CMS_HCC_RISK_SCORE), {{ to_double(1e-9) }})
      )

)

select * from final_ratio_mismatch
union all
select * from mean_mismatch
