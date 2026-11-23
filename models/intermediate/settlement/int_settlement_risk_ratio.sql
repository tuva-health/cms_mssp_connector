{#-
    The settled performance year's Table A1, computed from the settlement
    population (TUVA-162, method M-SETTLE from TUVA-161): one row per ACO,
    performance year and enrollment type, a column per A1 letter, named as
    in fct_settlement_risk so the two compare column for column.

    Per type t, over the eligible person-months int_settlement_member_month_risk
    types t:
      PY person years   eligible months / 12 (CMS's sum of BENE_PSNYRS, T3 [B])
      [C]  PY CMS-HCC   mean monthly score, as printed; unscored months are
                        left out of the mean (an assumption: real data had
                        none) but still count as person years
      [F]  PY demog.    mean DEM_* score of the month's type
    From the settlement (STLMT) workbook of the same ACO and year:
      [B]  BY3 CMS-HCC  A1 [B];   [E] BY3 demographic: A1 [E]
      [L]               Table 1 [L], the historical benchmark per type
    Then
      [A]  w_t = L_t x PY_t / sum(L x PY)
      [D]  r_t = [C] / [B];   [G] g_t = [F] / [E]
      R    = sum(w x r);      [H] = sum(w x g) + mssp_risk_score_cap
      [I]  = [H] when R > [H], else r_t   (A1's own rule: every type takes
             the cap when the aggregate exceeds it)

    BY3 comes from the STLMT workbook, not the benchmark report: CMS rescores
    some BY3 beneficiaries at reconciliation, which the ALR inputs cannot
    reproduce (TUVA-161).

    Nothing is defaulted. A type with person years but no [L] leaves every
    weight of the year NULL; one with weight but no [B] or [E] leaves the
    aggregates, the cap and [I] NULL for the year, as
    fact_benchmark_aco_quarter does. A type CMS lists in the workbook with
    no eligible month keeps its row with zero person years and weight 0.
-#}

{%- set cap = var('mssp_risk_score_cap') -%}

with member_months as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        RISK_SCORE,
        DEMOGRAPHIC_RISK_SCORE
    from {{ ref('int_settlement_member_month_risk') }}

),

population as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        count(*)                                                as ELIGIBLE_MEMBER_MONTHS,
        count(RISK_SCORE)                                       as SCORED_MEMBER_MONTHS,
        avg(RISK_SCORE)                                         as PY_CMS_HCC_RISK_SCORE,
        avg(DEMOGRAPHIC_RISK_SCORE)                             as PY_DEMOGRAPHIC_RISK_SCORE
    from member_months
    group by ACO_ID, PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

workbook_risk as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        {{ to_double('BY3_CMS_HCC_RISK_SCORE') }}               as BY3_CMS_HCC_RISK_SCORE,
        {{ to_double('BY3_DEMOGRAPHIC_RISK_SCORE') }}           as BY3_DEMOGRAPHIC_RISK_SCORE
    from {{ ref('fct_settlement_risk') }}
    where ENROLLMENT_TYPE <> 'weighted_average'

),

workbook_benchmark as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        {{ to_double('HISTORICAL_BENCHMARK') }}                 as HISTORICAL_BENCHMARK
    from {{ ref('fct_settlement_historical_benchmark') }}

),

-- Every ACO, year and type either side knows, for a year with a settlement
-- population.
type_keys as (

    select ACO_ID, PERFORMANCE_YEAR, ENROLLMENT_TYPE from population
    union distinct
    select workbook_risk.ACO_ID, workbook_risk.PERFORMANCE_YEAR, workbook_risk.ENROLLMENT_TYPE
    from workbook_risk
    inner join (select distinct ACO_ID, PERFORMANCE_YEAR from population) as settled
        on settled.ACO_ID = workbook_risk.ACO_ID
        and settled.PERFORMANCE_YEAR = workbook_risk.PERFORMANCE_YEAR

),

typed as (

    select
        type_keys.ACO_ID,
        type_keys.PERFORMANCE_YEAR,
        type_keys.ENROLLMENT_TYPE,
        coalesce(population.ELIGIBLE_MEMBER_MONTHS, 0)          as ELIGIBLE_MEMBER_MONTHS,
        coalesce(population.SCORED_MEMBER_MONTHS, 0)            as SCORED_MEMBER_MONTHS,
        coalesce(population.ELIGIBLE_MEMBER_MONTHS, 0) / {{ to_double(12) }}
                                                                as PERSON_YEARS,
        workbook_benchmark.HISTORICAL_BENCHMARK,
        workbook_risk.BY3_CMS_HCC_RISK_SCORE,
        {{ to_double('population.PY_CMS_HCC_RISK_SCORE') }}     as PY_CMS_HCC_RISK_SCORE,
        {{ safe_divide('population.PY_CMS_HCC_RISK_SCORE', 'workbook_risk.BY3_CMS_HCC_RISK_SCORE') }}
                                                                as UNCAPPED_RISK_RATIO,
        workbook_risk.BY3_DEMOGRAPHIC_RISK_SCORE,
        {{ to_double('population.PY_DEMOGRAPHIC_RISK_SCORE') }} as PY_DEMOGRAPHIC_RISK_SCORE,
        {{ safe_divide('population.PY_DEMOGRAPHIC_RISK_SCORE', 'workbook_risk.BY3_DEMOGRAPHIC_RISK_SCORE') }}
                                                                as DEMOGRAPHIC_RISK_RATIO
    from type_keys
    left join population
        on population.ACO_ID = type_keys.ACO_ID
        and population.PERFORMANCE_YEAR = type_keys.PERFORMANCE_YEAR
        and population.ENROLLMENT_TYPE = type_keys.ENROLLMENT_TYPE
    left join workbook_risk
        on workbook_risk.ACO_ID = type_keys.ACO_ID
        and workbook_risk.PERFORMANCE_YEAR = type_keys.PERFORMANCE_YEAR
        and workbook_risk.ENROLLMENT_TYPE = type_keys.ENROLLMENT_TYPE
    left join workbook_benchmark
        on workbook_benchmark.ACO_ID = type_keys.ACO_ID
        and workbook_benchmark.PERFORMANCE_YEAR = type_keys.PERFORMANCE_YEAR
        and workbook_benchmark.ENROLLMENT_TYPE = type_keys.ENROLLMENT_TYPE

),

weighted as (

    select
        typed.*,
        -- A type with person years and no benchmark leaves the weights incomplete.
        max(case when PERSON_YEARS > 0 and HISTORICAL_BENCHMARK is null then 1 else 0 end)
            over (partition by ACO_ID, PERFORMANCE_YEAR)        as HAS_MISSING_WEIGHT,
        {{ safe_divide(
            'HISTORICAL_BENCHMARK * PERSON_YEARS',
            'sum(HISTORICAL_BENCHMARK * PERSON_YEARS) over (partition by ACO_ID, PERFORMANCE_YEAR)'
        ) }}                                                    as WEIGHT_FROM_KNOWN_TYPES
    from typed

),

weights as (

    select
        weighted.*,
        -- Incomplete weights are unknown weights, for every type of the year.
        case when HAS_MISSING_WEIGHT = 0 then WEIGHT_FROM_KNOWN_TYPES end
                                                                as RISK_SCORE_WEIGHT
    from weighted

),

aggregated as (

    select
        weights.*,
        case when HAS_MISSING_WEIGHT = 0 then
            sum(RISK_SCORE_WEIGHT * UNCAPPED_RISK_RATIO) over (partition by ACO_ID, PERFORMANCE_YEAR)
        end                                                     as WEIGHTED_UNCAPPED_RISK_RATIO,
        case when HAS_MISSING_WEIGHT = 0 then
            sum(RISK_SCORE_WEIGHT * DEMOGRAPHIC_RISK_RATIO) over (partition by ACO_ID, PERFORMANCE_YEAR)
        end                                                     as WEIGHTED_DEMOGRAPHIC_RISK_RATIO,
        -- A weighted type with no ratio makes both aggregates unknown.
        max(case when RISK_SCORE_WEIGHT > 0 and UNCAPPED_RISK_RATIO is null then 1 else 0 end)
            over (partition by ACO_ID, PERFORMANCE_YEAR)        as HAS_MISSING_RATIO,
        max(case when RISK_SCORE_WEIGHT > 0 and DEMOGRAPHIC_RISK_RATIO is null then 1 else 0 end)
            over (partition by ACO_ID, PERFORMANCE_YEAR)        as HAS_MISSING_DEMOGRAPHIC_RATIO
    from weights

),

-- The aggregates, NULL where a weighted type's ratio is unknown, and [H].
aggregates as (

    select
        aggregated.*,
        case when HAS_MISSING_RATIO = 0 then WEIGHTED_UNCAPPED_RISK_RATIO end
                                                                as AGGREGATE_UNCAPPED_RISK_RATIO,
        case when HAS_MISSING_DEMOGRAPHIC_RATIO = 0 then WEIGHTED_DEMOGRAPHIC_RISK_RATIO end
                                                                as AGGREGATE_DEMOGRAPHIC_RISK_RATIO,
        case when HAS_MISSING_DEMOGRAPHIC_RATIO = 0 then WEIGHTED_DEMOGRAPHIC_RISK_RATIO end
            + {{ to_double(cap) }}                              as AGGREGATE_CAP
    from aggregated

)

select
    ACO_ID,
    PERFORMANCE_YEAR,
    ENROLLMENT_TYPE,
    ELIGIBLE_MEMBER_MONTHS,
    SCORED_MEMBER_MONTHS,
    PERSON_YEARS,
    HISTORICAL_BENCHMARK,
    RISK_SCORE_WEIGHT,
    BY3_CMS_HCC_RISK_SCORE,
    PY_CMS_HCC_RISK_SCORE,
    UNCAPPED_RISK_RATIO,
    BY3_DEMOGRAPHIC_RISK_SCORE,
    PY_DEMOGRAPHIC_RISK_SCORE,
    DEMOGRAPHIC_RISK_RATIO,
    AGGREGATE_UNCAPPED_RISK_RATIO,
    AGGREGATE_DEMOGRAPHIC_RISK_RATIO,
    AGGREGATE_CAP,
    case
        when AGGREGATE_UNCAPPED_RISK_RATIO is null
          or AGGREGATE_CAP is null then cast(null as {{ dbt.type_boolean() }})
        else AGGREGATE_UNCAPPED_RISK_RATIO > AGGREGATE_CAP
    end                                                         as IS_CAP_BINDING,
    case
        when AGGREGATE_UNCAPPED_RISK_RATIO is null
          or AGGREGATE_CAP is null then {{ to_double('null') }}
        when AGGREGATE_UNCAPPED_RISK_RATIO > AGGREGATE_CAP then AGGREGATE_CAP
        else UNCAPPED_RISK_RATIO
    end                                                         as FINAL_RISK_RATIO
from aggregates
