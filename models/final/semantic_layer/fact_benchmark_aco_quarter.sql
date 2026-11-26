{#-
    The ACO-quarter benchmark fact: one row per ACO, performance year and
    reported quarter on the latest calculable benchmark delivery, carrying
    the projected savings verdict beside the risk adjustment that CMS would
    apply to the benchmark at reconciliation — the aggregate PY-to-BY3 risk
    ratio, the cap on it, and the risk-adjusted benchmark that results.

    The savings columns are fct_projected_savings_current's, carried as they
    are. What is computed here is the risk block, in five steps.

    1. Per enrollment type, the PY risk ratio r_t: the mean CMS prospective
       HCC score over the assigned, scored member-months of that type and
       calendar year (int_member_month_risk), divided by [C] at BY3 for the
       type from the projection's benchmark delivery (int_benchmark_risk_scores).
       Both are on the renormalised national-mean-of-1.0 basis, so the
       division is as printed; int_member_month_risk documents why.

    2. The aggregate ratio R: the weighted mean of r_t with weights
       w_t = PERSON_YEARS_t x HISTORICAL_BENCHMARK_EXPENDITURE_t taken from
       the quarter row's own enrollment-type projection. Those are the
       weights 42 CFR 425.605(a)(1)(ii)(C) names — "the product of the
       historical benchmark expenditures for that enrollment type and the
       performance year person years for that enrollment type" — as
       finalised at 87 FR 69946, where CMS dropped the term "dollar-weighted"
       precisely because the weights are expenditure times person years and
       not dollars alone.

    3. The cap. 425.605(a)(1)(ii)(A) caps positive growth at the ACO's
       aggregate demographic risk score growth plus 3 percentage points, and
       it is one-sided: nothing in the rule limits a decrease, and at 87 FR
       69942 CMS declined a floor on decreases, so a fall in the aggregate
       ratio passes through uncapped. The demographic growth term needs BY3
       demographic scores the workbook does not carry, so the default here
       is the flat cap: CAP_UPPER_BOUND = 1 + mssp_risk_score_cap (0.03
       unless overridden). The scenario columns beside it project the
       missing growth term from the BNMRK Table 4 national mean scores
       instead: per type, the BY1-to-BY3 growth annualised over two years
       and compounded from the BY3 calendar year (the parameters sheet's
       "Benchmark Year 3 (BY3)" expenditure and risk score period) to the
       performance year, then aggregated with the same weights, and added to
       the cap. It is a projection and is labelled so.

    4. When R exceeds the bound the cap factor c = bound / R rescales every
       type's ratio by the one number, so the aggregate lands on the bound
       and the relative risk between members is preserved; at or below the
       bound c = 1. The risk-adjusted benchmark is then
       sum_t ENROLLMENT_PROPORTION_t x [M]_t x r_t x c, an annual per capita
       figure, with its PMPM. fact_member_month_benchmark reads c off the
       IS_CURRENT_PROJECTION row of each year, so the capped member rates
       sum to exactly this figure applied to the member mix. The single
       factor is a deliberate choice for the member-level fact: one number
       per year keeps every member's capped rate its uncapped rate times
       that number, so relative risk between members of different types is
       preserved and the member rows add up to the ACO figure. The header
       of _models.yml records it. CMS's own application differs, and step
       5 carries it beside this.

    5. The CMS method. 425.605(a)(1)(ii)(B), and Step 7 of the worked
       application at 87 FR 69935, apply the cap per type: when R exceeds
       the bound each type's ratio is clipped at the bound, min(r_t, bound),
       so a type below the bound keeps its ratio and a type above it is cut
       to the bound; when R is within the bound no type is clipped, even
       one above the bound on its own. RISK_RATIO_CLIPPED_<TYPE> carries
       those ratios, RISK_ADJUSTED_BENCHMARK_CMS the benchmark they give,
       sum_t ENROLLMENT_PROPORTION_t x [M]_t x clipped_t, with its PMPM,
       and RISK_ADJUSTED_BENCHMARK_METHOD_DIFFERENCE is CMS minus
       single-factor. The two are equal wherever the cap does not bind and
       differ, in general, wherever it does: with types on both sides of
       the bound only the types above it are cut, and even with every type
       above it — when both methods land the aggregate on the bound — the
       benchmarks agree only if the [M]-weighted mix of the types matches
       the ratio weights. The member fact keeps the single factor of step
       4; the CMS columns are for stating the ACO figure as CMS would, and
       for sizing what the choice is worth.

    Everything is NULL-safe and nothing is defaulted. A type with no
    assigned, scored member-months in the year has a NULL r_t, which makes
    R, c, the binding flag, the capped benchmark and every CMS-method
    column — the clipped ratio of a type whose own ratio is known included,
    since whether to clip it is then unknown — NULL for every quarter of
    that year rather than quietly treating the type as unchanged. A
    quarter with no enrollment-type rows keeps its savings columns and a
    NULL risk block. The Table 4 national means are NULL on the preliminary
    March delivery, which cascades into the scenario columns alone.

    The projection rule is fact_member_month_benchmark's: the row with the
    highest QUARTER_NUM in a performance year (lowest ACO_ID on ties) is
    IS_CURRENT_PROJECTION, and every other quarter of the year is carried
    with its own risk block so a report can show the cap moving with each
    quarterly delivery. The CTE is duplicated rather than shared, so as not
    to reach into that model; assert_aco_quarter_projection_agrees_with_
    member_fact holds the two together.

    IS_SETTLED and the settlement outcome columns (TUVA-160) come through
    from fct_projected_savings_current as they are, the same on every quarter
    row of a settled year, with the settled savings percentage and each
    quarter's difference from it.

    Beside each quarter's own risk ratios the fact carries CMS's printed
    Table A1 (fct_settlement_risk) for a settled year: [D], the uncapped
    ratio, per type, the weighted aggregate sum [A] x [D], and each one
    minus the quarter's projected RISK_RATIO_<TYPE> or AGGREGATE_RISK_RATIO
    — how far off the quarter's report was from the final. These are the
    printed final figures, not the M-SETTLE SETTLEMENT_* ratios above.
    There is no capped difference: the projection's CMS-method clipped
    ratios (RISK_RATIO_CLIPPED_<TYPE>, step 5) clip at a flat 1 + cap and
    omit the aggregate demographic growth that CMS adds to the cap
    ([H] = sum(w x g) + 0.03, specifications section 3.2.4.2, 87 FR
    69935), so a difference against A1 [I] would measure the cap level,
    not projection error.

    All arithmetic goes through to_double and safe_divide; see the macros.
-#}

{%- set cap = var('mssp_risk_score_cap') -%}
{%- set enrollment_types = ['esrd', 'disabled', 'aged_dual', 'aged_non_dual'] -%}

{#- r_t clipped at the flat bound, for the CMS method (step 5 above). The
    NULL guard is not decoration: least() ignores a NULL argument on DuckDB
    and Postgres but returns NULL on Snowflake, and a type without a ratio
    must stay NULL on every adapter rather than come back as the bound. -#}
{%- set clipped_ratio -%}
case
    when RISK_RATIO is null then {{ to_double('null') }}
    else least(RISK_RATIO, {{ to_double(1) }} + {{ to_double(cap) }})
end
{%- endset -%}

{#- The five sums over the types, each (name, per-type term). They are added
    as four named terms in the order above rather than with sum(), as
    fct_projected_savings adds [P]: double addition is not associative, and
    sum() would leave the order to the rows' physical order and the query
    plan, so the last bit of a ratio could change with nothing else. -#}
{%- set totals = [
        ('WEIGHT_TOTAL',                     'WEIGHT'),
        ('WEIGHTED_RISK_RATIO_TOTAL',        'WEIGHT * RISK_RATIO'),
        ('WEIGHTED_GROWTH_TOTAL',            'WEIGHT * NATIONAL_GROWTH_PROJECTED'),
        ('RISK_ADJUSTED_BENCHMARK_UNCAPPED', 'ENROLLMENT_PROPORTION * ENROLLMENT_TYPE_BENCHMARK * RISK_RATIO'),
        ('RISK_ADJUSTED_BENCHMARK_CLIPPED',  'ENROLLMENT_PROPORTION * ENROLLMENT_TYPE_BENCHMARK * ' ~ clipped_ratio)
    ] -%}

with projections as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        QUARTERLY_SUBMISSION_ID,
        MEAN_PROJECTED_UPDATED_BENCHMARK,
        MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM,
        ACO_EXPENDITURE_PER_CAPITA,
        ACO_EXPENDITURE_PER_CAPITA_PMPM,
        PROJECTED_SAVINGS_PERCENTAGE,
        ASSIGNED_BENEFICIARIES,
        MSR_TYPE,
        FIXED_MSR_RATE,
        ACO_TRACK,
        MSR_BASIS_APPLIED,
        ESTIMATED_MSR,
        EXPENDITURES_BELOW_BENCHMARK,
        SAVINGS_EXCEEDS_MSR,
        SAVINGS_STATUS,
        ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
        ANNUAL_EXPENDITURE_SUBMISSION_ID,
        ACPT_PERFORMANCE_YEAR_LABEL,
        IS_AGREEMENT_DEFAULTED,
        IS_SETTLED,
        {%- for field, column in settlement_outcome_columns() %}
        {{ column }},
        {%- endfor %}
        {%- for column in settlement_savings_columns() %}
        {{ column }},
        {%- endfor %}

        {#- the member fact's rule: latest quarter of the year, lowest ACO on ties -#}
        row_number() over (
            partition by PERFORMANCE_YEAR
            order by QUARTER_NUM desc, ACO_ID
        ) = 1                                               as IS_CURRENT_PROJECTION
    from {{ ref('fct_projected_savings_current') }}

),

-- The PY half of each type's ratio: assigned, scored member-months of the
-- calendar year. The spine carries no ACO; the join below is on year alone,
-- as in fact_member_month_benchmark.
member_months as (

    select
        {{ cast_year_or_null('substring(YEAR_MONTH, 1, 4)') }}
                                                            as PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        {{ to_double('RISK_SCORE') }}                       as RISK_SCORE,
        RISK_SCORE_SOURCE
    from {{ ref('int_member_month_risk') }}
    where IS_ASSIGNED
      and RISK_SCORE is not null
      and ENROLLMENT_TYPE is not null

),

member_scores as (

    select
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        count(*)                                            as ASSIGNED_SCORED_MEMBER_MONTHS,
        avg(RISK_SCORE)                                     as PY_MEAN_RISK_SCORE
    from member_months
    group by PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

-- What the PY scores are (TUVA-162), over the same member-months as the
-- means. A quarterly or initial list's type score column holds the most
-- recent payment year CMS has scored, the BY3 year's mid-PY (TUVA-161); a
-- monthly BENE_RSK_R_SCRE_NN column holds the year's own score.
score_basis as (

    select
        PERFORMANCE_YEAR,
        case
            when min(RISK_SCORE_SOURCE) = 'assignment_list_type_score'
             and max(RISK_SCORE_SOURCE) = 'assignment_list_type_score'
                then 'by3_year_scores'
            when min(RISK_SCORE_SOURCE) = 'assignment_list_monthly_score'
             and max(RISK_SCORE_SOURCE) = 'assignment_list_monthly_score'
                then 'performance_year_scores'
            else 'mixed'
        end                                                 as PY_RISK_SCORE_BASIS
    from member_months
    group by PERFORMANCE_YEAR

),

-- The settled year's Table A1 as computed from the settlement population
-- (TUVA-162, M-SETTLE), one row per ACO and year, beside the projection.
settlement_ratios as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        max(AGGREGATE_UNCAPPED_RISK_RATIO)                  as SETTLEMENT_AGGREGATE_RISK_RATIO,
        max(AGGREGATE_DEMOGRAPHIC_RISK_RATIO)               as SETTLEMENT_AGGREGATE_DEMOGRAPHIC_RISK_RATIO,
        max(AGGREGATE_CAP)                                  as SETTLEMENT_AGGREGATE_CAP,
        max(case when IS_CAP_BINDING then 1 when not IS_CAP_BINDING then 0 end)
                                                            as SETTLEMENT_CAP_BINDING_FLAG
        {%- for enrollment_type in enrollment_types %}
        {%- set t = enrollment_type | upper %},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then RISK_SCORE_WEIGHT end)
                                                            as SETTLEMENT_RISK_SCORE_WEIGHT_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then PY_CMS_HCC_RISK_SCORE end)
                                                            as SETTLEMENT_PY_RISK_SCORE_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then UNCAPPED_RISK_RATIO end)
                                                            as SETTLEMENT_RISK_RATIO_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then PY_DEMOGRAPHIC_RISK_SCORE end)
                                                            as SETTLEMENT_PY_DEMOGRAPHIC_RISK_SCORE_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then DEMOGRAPHIC_RISK_RATIO end)
                                                            as SETTLEMENT_DEMOGRAPHIC_RISK_RATIO_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then FINAL_RISK_RATIO end)
                                                            as SETTLEMENT_FINAL_RISK_RATIO_{{ t }}
        {%- endfor %}
    from {{ ref('int_settlement_risk_ratio') }}
    group by ACO_ID, PERFORMANCE_YEAR

),

-- CMS's printed Table A1 (fct_settlement_risk), one row per ACO and year:
-- [A] and [D] per type, for the settled-minus-projected differences
-- (TUVA-160, 2026-11-25). Not the M-SETTLE figures above, which are
-- recomputed from the settlement population.
settlement_a1_types as (

    select
        ACO_ID,
        PERFORMANCE_YEAR
        {%- for enrollment_type in enrollment_types %}
        {%- set t = enrollment_type | upper %},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}'
                 then {{ to_double('RISK_SCORE_WEIGHT') }} end)        as A1_WEIGHT_{{ t }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}'
                 then {{ to_double('UNCAPPED_RISK_RATIO') }} end)      as A1_UNCAPPED_RISK_RATIO_{{ t }}
        {%- endfor %}
    from {{ ref('fct_settlement_risk') }}
    group by ACO_ID, PERFORMANCE_YEAR

),

-- The weighted uncapped aggregate, sum of [A] x [D] over the four types,
-- as four named terms in a fixed order, for the reason `totals` gives.
-- Unlike `summed`, any missing term makes it NULL: Table A1 fills [A] and
-- [D] for every type, so a blank one is a gap in the delivery, and a
-- weighted mean over three of four types is not CMS's.
-- It agrees with A1's printed Weighted Average [D] to its rounding;
-- assert_settlement_weighted_average_risk_ratio_is_the_weighted_sum holds
-- the two together.
settlement_a1 as (

    select
        settlement_a1_types.*,
        {% for enrollment_type in enrollment_types -%}
        A1_WEIGHT_{{ enrollment_type | upper }} * A1_UNCAPPED_RISK_RATIO_{{ enrollment_type | upper }}
        {%- if not loop.last %}
            + {% endif %}
        {%- endfor %}
                                                            as A1_WEIGHTED_UNCAPPED_RISK_RATIO
    from settlement_a1_types

),

-- [M], the enrollment proportion, and the two weight factors, at every
-- quarter row of the latest calculable delivery.
enrollment_types as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        ENROLLMENT_TYPE,
        PROJECTED_UPDATED_BENCHMARK_EXPENDITURE,
        HISTORICAL_BENCHMARK_EXPENDITURE,
        PERSON_YEARS,
        ENROLLMENT_PROPORTION
    from {{ ref('fct_projected_benchmark_by_enrollment_type_current') }}

),

-- [C] at BY3 and the Table 4 national means at BY1 and BY3, from the
-- projection's benchmark delivery. Ranked within a submission as
-- fact_member_month_benchmark ranks them, so a redelivery under one stamp
-- keeps the grain.
risk_scores_ranked as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        ENROLLMENT_TYPE,
        BY_LABEL,
        ACO_RISK_SCORE,
        NATIONAL_MEAN_RISK_SCORE,
        row_number() over (
            partition by ACO_ID, PERFORMANCE_YEAR, SUBMISSION_ID, ENROLLMENT_TYPE, BY_LABEL
            order by FILE_DATE desc nulls last, FILE_PATH desc
        )                                                   as SCORE_RANK
    from {{ ref('int_benchmark_risk_scores') }}
    where BY_LABEL in ('BY1', 'BY3')

),

risk_scores as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        ENROLLMENT_TYPE,
        max(case when BY_LABEL = 'BY3' then ACO_RISK_SCORE end)
                                                            as BY3_RISK_SCORE,
        max(case when BY_LABEL = 'BY1' then NATIONAL_MEAN_RISK_SCORE end)
                                                            as BY1_NATIONAL_MEAN_RISK_SCORE,
        max(case when BY_LABEL = 'BY3' then NATIONAL_MEAN_RISK_SCORE end)
                                                            as BY3_NATIONAL_MEAN_RISK_SCORE
    from risk_scores_ranked
    where SCORE_RANK = 1
    group by ACO_ID, PERFORMANCE_YEAR, SUBMISSION_ID, ENROLLMENT_TYPE

),

-- The BY3 calendar year, from the parameters sheet of the same delivery:
-- the "Benchmark Year 3 (BY3)" row of the expenditure and risk score period
-- group, whose value is a date range like "01/01/2021 - 12/31/2021".
by3_calendar_year_ranked as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        {{ cast_year_or_null('right(trim(VALUE_TEXT), 4)') }}
                                                            as BY3_CALENDAR_YEAR,
        row_number() over (
            partition by ACO_ID, PERFORMANCE_YEAR, SUBMISSION_ID
            order by FILE_DATE desc nulls last, FILE_PATH desc
        )                                                   as PARAMETER_RANK
    from {{ ref('stg_bnmrk_parameters') }}
    where upper(trim(ROW_LABEL)) = 'BENCHMARK YEAR 3 (BY3)'
      and upper(trim(GROUP_LABEL)) like 'EXPENDITURE & RISK SCORE PERIOD%'

),

by3_calendar_year as (

    select *
    from by3_calendar_year_ranked
    where PARAMETER_RANK = 1

),

-- One row per quarter row and enrollment type: the ratio, its weight, and
-- the projected national growth for the scenario.
per_type as (

    select
        projections.ACO_ID                                  as ACO_ID,
        projections.PERFORMANCE_YEAR                        as PERFORMANCE_YEAR,
        projections.PERIOD                                  as PERIOD,
        projections.BENCHMARK_SUBMISSION_ID                 as BENCHMARK_SUBMISSION_ID,
        enrollment_types.ENROLLMENT_TYPE                    as ENROLLMENT_TYPE,
        by3_calendar_year.BY3_CALENDAR_YEAR                 as BY3_CALENDAR_YEAR,

        {{ to_double('enrollment_types.PROJECTED_UPDATED_BENCHMARK_EXPENDITURE') }}
                                                            as ENROLLMENT_TYPE_BENCHMARK,
        {{ to_double('enrollment_types.ENROLLMENT_PROPORTION') }}
                                                            as ENROLLMENT_PROPORTION,

        {#- 425.605(a)(1)(ii)(C): historical benchmark expenditure x PY person years -#}
        {{ to_double('enrollment_types.PERSON_YEARS') }}
            * {{ to_double('enrollment_types.HISTORICAL_BENCHMARK_EXPENDITURE') }}
                                                            as WEIGHT,

        member_scores.ASSIGNED_SCORED_MEMBER_MONTHS         as ASSIGNED_SCORED_MEMBER_MONTHS,
        member_scores.PY_MEAN_RISK_SCORE                    as PY_MEAN_RISK_SCORE,
        {{ to_double('risk_scores.BY3_RISK_SCORE') }}       as BY3_RISK_SCORE,

        {#- r_t = PY assignment-list mean / BY3 [C] -#}
        {{ safe_divide('member_scores.PY_MEAN_RISK_SCORE', 'risk_scores.BY3_RISK_SCORE') }}
                                                            as RISK_RATIO,

        {#- (Table 4 BY3 / Table 4 BY1) ^ ((PY - BY3 year) / 2): the two-year
            trend annualised and compounded to the performance year -#}
        case
            when by3_calendar_year.BY3_CALENDAR_YEAR is not null
            then power(
                {{ safe_divide('risk_scores.BY3_NATIONAL_MEAN_RISK_SCORE', 'risk_scores.BY1_NATIONAL_MEAN_RISK_SCORE') }},
                {{ to_double('projections.PERFORMANCE_YEAR - by3_calendar_year.BY3_CALENDAR_YEAR') }}
                    / {{ to_double(2) }}
            )
        end                                                 as NATIONAL_GROWTH_PROJECTED

    from projections

    inner join enrollment_types
        on enrollment_types.ACO_ID = projections.ACO_ID
        and enrollment_types.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
        and enrollment_types.PERIOD = projections.PERIOD
        and enrollment_types.BENCHMARK_SUBMISSION_ID = projections.BENCHMARK_SUBMISSION_ID

    left join member_scores
        on member_scores.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
        and member_scores.ENROLLMENT_TYPE = enrollment_types.ENROLLMENT_TYPE

    left join risk_scores
        on risk_scores.ACO_ID = projections.ACO_ID
        and risk_scores.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
        and risk_scores.SUBMISSION_ID = projections.BENCHMARK_SUBMISSION_ID
        and risk_scores.ENROLLMENT_TYPE = enrollment_types.ENROLLMENT_TYPE

    left join by3_calendar_year
        on by3_calendar_year.ACO_ID = projections.ACO_ID
        and by3_calendar_year.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
        and by3_calendar_year.SUBMISSION_ID = projections.BENCHMARK_SUBMISSION_ID

),

-- The aggregate over the types of a quarter row, NULL as soon as any type
-- lacks the inputs — sum() would silently drop the missing type instead.
aggregated as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        BENCHMARK_SUBMISSION_ID,
        max(BY3_CALENDAR_YEAR)                              as BY3_CALENDAR_YEAR,

        sum(case
                when RISK_RATIO is null or WEIGHT is null then 1
                else 0
            end) = 0                                        as HAS_COMPLETE_RATIOS,
        sum(case
                when RISK_RATIO is null or ENROLLMENT_PROPORTION is null
                     or ENROLLMENT_TYPE_BENCHMARK is null then 1
                else 0
            end) = 0                                        as HAS_COMPLETE_BENCHMARK,
        sum(case
                when NATIONAL_GROWTH_PROJECTED is null or WEIGHT is null then 1
                else 0
            end) = 0                                        as HAS_COMPLETE_GROWTH,

        {#- the five sums' terms, one per type, added in a fixed order below -#}
        {%- for total, term in totals %}
        {%- for enrollment_type in enrollment_types %}
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then {{ term | indent(12) }} end)
                                                            as {{ total }}_TERM_{{ enrollment_type | upper }}
        {%- if not loop.last %},{% endif %}
        {%- endfor %}
        {%- if not loop.last %},{% endif %}
        {%- endfor %}

        {%- for enrollment_type in enrollment_types %},

        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then ASSIGNED_SCORED_MEMBER_MONTHS end)
                                                            as ASSIGNED_SCORED_MEMBER_MONTHS_{{ enrollment_type | upper }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then PY_MEAN_RISK_SCORE end)
                                                            as PY_MEAN_RISK_SCORE_{{ enrollment_type | upper }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then BY3_RISK_SCORE end)
                                                            as BY3_RISK_SCORE_{{ enrollment_type | upper }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then RISK_RATIO end)
                                                            as RISK_RATIO_{{ enrollment_type | upper }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then {{ clipped_ratio | indent(12) }} end)
                                                            as RISK_RATIO_CLIPPED_{{ enrollment_type | upper }},
        max(case when ENROLLMENT_TYPE = '{{ enrollment_type }}' then WEIGHT end)
                                                            as WEIGHT_{{ enrollment_type | upper }}
        {%- endfor %}

    from per_type
    group by ACO_ID, PERFORMANCE_YEAR, PERIOD, BENCHMARK_SUBMISSION_ID

),

-- Each sum as four named terms in a fixed order. A NULL term is left out,
-- as sum() leaves out a NULL row, and the total is NULL only when every
-- term is; adding the 0 that stands in for a missing term is exact.
summed as (

    select
        aggregated.*
        {%- for total, term in totals %},
        case
            when {% for enrollment_type in enrollment_types %}{{ total }}_TERM_{{ enrollment_type | upper }} is null{% if not loop.last %} and {% endif %}{% endfor %}
                then {{ to_double('null') }}
            else {% for enrollment_type in enrollment_types %}coalesce({{ total }}_TERM_{{ enrollment_type | upper }}, {{ to_double(0) }}){% if not loop.last %}
               + {% endif %}{% endfor %}
        end                                                 as {{ total }}
        {%- endfor %}
    from aggregated

),

ratios as (

    select
        summed.*,

        case
            when HAS_COMPLETE_RATIOS
            then {{ safe_divide('WEIGHTED_RISK_RATIO_TOTAL', 'WEIGHT_TOTAL') }}
        end                                                 as AGGREGATE_RISK_RATIO,

        case
            when HAS_COMPLETE_RATIOS and HAS_COMPLETE_GROWTH
            then {{ safe_divide('WEIGHTED_GROWTH_TOTAL', 'WEIGHT_TOTAL') }}
        end                                                 as NATIONAL_GROWTH_PROJECTED,

        {{ to_double(cap) }}                                as RISK_SCORE_CAP,
        {{ to_double(1) }} + {{ to_double(cap) }}           as CAP_UPPER_BOUND

    from summed

),

capped as (

    select
        ratios.*,

        {#- 1 + cap + growth - 1 -#}
        RISK_SCORE_CAP + NATIONAL_GROWTH_PROJECTED          as CAP_UPPER_BOUND_SCENARIO,

        {#- one-sided: bound / R above the bound, 1 at or below it -#}
        case
            when AGGREGATE_RISK_RATIO is null then {{ to_double('null') }}
            when AGGREGATE_RISK_RATIO > CAP_UPPER_BOUND
                then {{ safe_divide('CAP_UPPER_BOUND', 'AGGREGATE_RISK_RATIO') }}
            else {{ to_double(1) }}
        end                                                 as CAP_FACTOR,

        case
            when AGGREGATE_RISK_RATIO is null then null
            else AGGREGATE_RISK_RATIO > CAP_UPPER_BOUND
        end                                                 as IS_CAP_BINDING

    from ratios

),

scenario as (

    select
        capped.*,

        case
            when AGGREGATE_RISK_RATIO is null
                 or CAP_UPPER_BOUND_SCENARIO is null then {{ to_double('null') }}
            when AGGREGATE_RISK_RATIO > CAP_UPPER_BOUND_SCENARIO
                then {{ safe_divide('CAP_UPPER_BOUND_SCENARIO', 'AGGREGATE_RISK_RATIO') }}
            else {{ to_double(1) }}
        end                                                 as CAP_FACTOR_SCENARIO,

        case
            when AGGREGATE_RISK_RATIO is null
                 or CAP_UPPER_BOUND_SCENARIO is null then null
            else AGGREGATE_RISK_RATIO > CAP_UPPER_BOUND_SCENARIO
        end                                                 as IS_CAP_BINDING_SCENARIO,

        case
            when HAS_COMPLETE_BENCHMARK
            then RISK_ADJUSTED_BENCHMARK_UNCAPPED * CAP_FACTOR
        end                                                 as RISK_ADJUSTED_BENCHMARK,

        {#- CMS method: the clipped ratios where the cap binds, the ratios
            as they are where it does not, NULL where that is unknown -#}
        case
            when not HAS_COMPLETE_BENCHMARK or IS_CAP_BINDING is null
                then {{ to_double('null') }}
            when IS_CAP_BINDING then RISK_ADJUSTED_BENCHMARK_CLIPPED
            else RISK_ADJUSTED_BENCHMARK_UNCAPPED
        end                                                 as RISK_ADJUSTED_BENCHMARK_CMS

    from capped

)

select
    projections.ACO_ID                                      as ACO_ID,
    projections.PERFORMANCE_YEAR                            as PERFORMANCE_YEAR,
    projections.PERIOD                                      as PERIOD,
    projections.QUARTER_NUM                                 as QUARTER_NUM,
    projections.IS_CURRENT_PROJECTION                       as IS_CURRENT_PROJECTION,
    projections.BENCHMARK_SUBMISSION_ID                     as BENCHMARK_SUBMISSION_ID,
    projections.QUARTERLY_SUBMISSION_ID                     as QUARTERLY_SUBMISSION_ID,

    projections.MEAN_PROJECTED_UPDATED_BENCHMARK            as MEAN_PROJECTED_UPDATED_BENCHMARK,
    projections.MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM       as MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM,
    projections.ACO_EXPENDITURE_PER_CAPITA                  as ACO_EXPENDITURE_PER_CAPITA,
    projections.ACO_EXPENDITURE_PER_CAPITA_PMPM             as ACO_EXPENDITURE_PER_CAPITA_PMPM,
    projections.PROJECTED_SAVINGS_PERCENTAGE                as PROJECTED_SAVINGS_PERCENTAGE,
    projections.ASSIGNED_BENEFICIARIES                      as ASSIGNED_BENEFICIARIES,
    projections.MSR_TYPE                                    as MSR_TYPE,
    projections.FIXED_MSR_RATE                              as FIXED_MSR_RATE,
    projections.ACO_TRACK                                   as ACO_TRACK,
    projections.MSR_BASIS_APPLIED                           as MSR_BASIS_APPLIED,
    projections.ESTIMATED_MSR                               as ESTIMATED_MSR,
    projections.EXPENDITURES_BELOW_BENCHMARK                as EXPENDITURES_BELOW_BENCHMARK,
    projections.SAVINGS_EXCEEDS_MSR                         as SAVINGS_EXCEEDS_MSR,
    projections.SAVINGS_STATUS                              as SAVINGS_STATUS,

    scenario.BY3_CALENDAR_YEAR                              as BY3_CALENDAR_YEAR,
    score_basis.PY_RISK_SCORE_BASIS                         as PY_RISK_SCORE_BASIS

    {%- for enrollment_type in enrollment_types %},
    scenario.ASSIGNED_SCORED_MEMBER_MONTHS_{{ enrollment_type | upper }}
                                                            as ASSIGNED_SCORED_MEMBER_MONTHS_{{ enrollment_type | upper }},
    scenario.PY_MEAN_RISK_SCORE_{{ enrollment_type | upper }}
                                                            as PY_MEAN_RISK_SCORE_{{ enrollment_type | upper }},
    scenario.BY3_RISK_SCORE_{{ enrollment_type | upper }}   as BY3_RISK_SCORE_{{ enrollment_type | upper }},
    scenario.RISK_RATIO_{{ enrollment_type | upper }}       as RISK_RATIO_{{ enrollment_type | upper }},
    {{ safe_divide('scenario.WEIGHT_' ~ (enrollment_type | upper), 'scenario.WEIGHT_TOTAL') }}
                                                            as RISK_RATIO_WEIGHT_{{ enrollment_type | upper }}
    {%- endfor %},

    scenario.AGGREGATE_RISK_RATIO                           as AGGREGATE_RISK_RATIO,

    {#- the cap and its bound are constants of the run, carried on every
        row — including a quarter with no enrollment-type rows -#}
    {{ to_double(cap) }}                                    as RISK_SCORE_CAP,
    {{ to_double(1) }} + {{ to_double(cap) }}               as CAP_UPPER_BOUND,
    scenario.CAP_FACTOR                                     as CAP_FACTOR,
    scenario.IS_CAP_BINDING                                 as IS_CAP_BINDING,

    case
        when scenario.HAS_COMPLETE_BENCHMARK
        then scenario.RISK_ADJUSTED_BENCHMARK_UNCAPPED
    end                                                     as RISK_ADJUSTED_BENCHMARK_UNCAPPED,
    scenario.RISK_ADJUSTED_BENCHMARK                        as RISK_ADJUSTED_BENCHMARK,

    {#- annual per capita / 12 -#}
    scenario.RISK_ADJUSTED_BENCHMARK / {{ to_double(12) }}  as RISK_ADJUSTED_BENCHMARK_PMPM

    {#- the CMS method: each type's ratio clipped at the bound where the cap
        binds, untouched where it does not, NULL where the binding is
        unknown — the ratio of a type the quarter has no row for stays NULL -#}
    {%- for enrollment_type in enrollment_types %},
    case
        when scenario.IS_CAP_BINDING
            then scenario.RISK_RATIO_CLIPPED_{{ enrollment_type | upper }}
        when not scenario.IS_CAP_BINDING
            then scenario.RISK_RATIO_{{ enrollment_type | upper }}
    end                                                     as RISK_RATIO_CLIPPED_{{ enrollment_type | upper }}
    {%- endfor %},

    scenario.RISK_ADJUSTED_BENCHMARK_CMS                    as RISK_ADJUSTED_BENCHMARK_CMS,
    scenario.RISK_ADJUSTED_BENCHMARK_CMS / {{ to_double(12) }}
                                                            as RISK_ADJUSTED_BENCHMARK_CMS_PMPM,

    {#- exactly 0 wherever the cap does not bind: both are then the uncapped sum -#}
    scenario.RISK_ADJUSTED_BENCHMARK_CMS - scenario.RISK_ADJUSTED_BENCHMARK
                                                            as RISK_ADJUSTED_BENCHMARK_METHOD_DIFFERENCE,

    scenario.NATIONAL_GROWTH_PROJECTED                      as NATIONAL_GROWTH_PROJECTED,
    scenario.CAP_UPPER_BOUND_SCENARIO                       as CAP_UPPER_BOUND_SCENARIO,
    scenario.CAP_FACTOR_SCENARIO                            as CAP_FACTOR_SCENARIO,
    scenario.IS_CAP_BINDING_SCENARIO                        as IS_CAP_BINDING_SCENARIO,

    projections.ANNUAL_EXPENDITURE_BENCHMARK_YEAR           as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
    projections.ANNUAL_EXPENDITURE_SUBMISSION_ID            as ANNUAL_EXPENDITURE_SUBMISSION_ID,
    projections.ACPT_PERFORMANCE_YEAR_LABEL                 as ACPT_PERFORMANCE_YEAR_LABEL,
    projections.IS_AGREEMENT_DEFAULTED                      as IS_AGREEMENT_DEFAULTED,

    {#- the settlement view beside the projection (TUVA-162): the settled
        year's A1 computed from the settlement population, the same on every
        quarter row of the year, NULL for a year not settled -#}
    {%- for enrollment_type in enrollment_types %}
    {%- set t = enrollment_type | upper %}
    settlement_ratios.SETTLEMENT_RISK_SCORE_WEIGHT_{{ t }}  as SETTLEMENT_RISK_SCORE_WEIGHT_{{ t }},
    settlement_ratios.SETTLEMENT_PY_RISK_SCORE_{{ t }}      as SETTLEMENT_PY_RISK_SCORE_{{ t }},
    settlement_ratios.SETTLEMENT_RISK_RATIO_{{ t }}         as SETTLEMENT_RISK_RATIO_{{ t }},
    settlement_ratios.SETTLEMENT_PY_DEMOGRAPHIC_RISK_SCORE_{{ t }}
                                                            as SETTLEMENT_PY_DEMOGRAPHIC_RISK_SCORE_{{ t }},
    settlement_ratios.SETTLEMENT_DEMOGRAPHIC_RISK_RATIO_{{ t }}
                                                            as SETTLEMENT_DEMOGRAPHIC_RISK_RATIO_{{ t }},
    settlement_ratios.SETTLEMENT_FINAL_RISK_RATIO_{{ t }}   as SETTLEMENT_FINAL_RISK_RATIO_{{ t }},
    {%- endfor %}
    settlement_ratios.SETTLEMENT_AGGREGATE_RISK_RATIO       as SETTLEMENT_AGGREGATE_RISK_RATIO,
    settlement_ratios.SETTLEMENT_AGGREGATE_DEMOGRAPHIC_RISK_RATIO
                                                            as SETTLEMENT_AGGREGATE_DEMOGRAPHIC_RISK_RATIO,
    settlement_ratios.SETTLEMENT_AGGREGATE_CAP              as SETTLEMENT_AGGREGATE_CAP,
    case settlement_ratios.SETTLEMENT_CAP_BINDING_FLAG
        when 1 then true
        when 0 then false
    end                                                     as SETTLEMENT_IS_CAP_BINDING,

    {#- CMS's printed Table A1 against this quarter's projection (TUVA-160,
        2026-11-25): settled minus projected, NULL in a year not settled.
        Uncapped only: RISK_RATIO_CLIPPED_<TYPE> clips at a flat 1 + cap,
        without the aggregate demographic growth CMS adds to A1 [H]
        (sum(w x g) + 0.03), so a capped difference would measure the cap
        level, not projection error. -#}
    {%- for enrollment_type in enrollment_types %}
    {%- set t = enrollment_type | upper %}
    settlement_a1.A1_UNCAPPED_RISK_RATIO_{{ t }}            as SETTLEMENT_UNCAPPED_RISK_RATIO_{{ t }},
    settlement_a1.A1_UNCAPPED_RISK_RATIO_{{ t }} - scenario.RISK_RATIO_{{ t }}
                                                            as SETTLEMENT_UNCAPPED_RISK_RATIO_DIFFERENCE_{{ t }},
    {%- endfor %}
    settlement_a1.A1_WEIGHTED_UNCAPPED_RISK_RATIO           as SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO,
    settlement_a1.A1_WEIGHTED_UNCAPPED_RISK_RATIO - scenario.AGGREGATE_RISK_RATIO
                                                            as SETTLEMENT_WEIGHTED_UNCAPPED_RISK_RATIO_DIFFERENCE,

    {#- CMS's settled result (TUVA-160), from fct_settlement through
        fct_projected_savings_current: the same on every quarter row of a
        settled year, IS_SETTLED false and NULL for a year not settled -#}
    projections.IS_SETTLED                                  as IS_SETTLED
    {%- for field, column in settlement_outcome_columns() %},
    projections.{{ column }}{{ ' ' * (44 - column | length) }}as {{ column }}
    {%- endfor %}
    {%- for column in settlement_savings_columns() %},
    projections.{{ column }}{{ ' ' * (44 - column | length) }}as {{ column }}
    {%- endfor %}

from projections

left join scenario
    on scenario.ACO_ID = projections.ACO_ID
    and scenario.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
    and scenario.PERIOD = projections.PERIOD
    and scenario.BENCHMARK_SUBMISSION_ID = projections.BENCHMARK_SUBMISSION_ID

left join score_basis
    on score_basis.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR

left join settlement_ratios
    on settlement_ratios.ACO_ID = projections.ACO_ID
    and settlement_ratios.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR

left join settlement_a1
    on settlement_a1.ACO_ID = projections.ACO_ID
    and settlement_a1.PERFORMANCE_YEAR = projections.PERFORMANCE_YEAR
