{#-
    The benchmark applied to every member-month of the Tuva semantic layer,
    on the surrogate key fact_member_months already carries, so a report model
    joins the two one to one and reads a benchmark beside each member's spend.

    Three rates per member per month, each one step more specific than the
    last: [P]/12, the ACO mean projected updated benchmark, the same number
    on every row of a performance year; [M]/12 for the member's enrollment
    type; and that type rate scaled by the member's CMS prospective HCC score
    over the BY3 CMS-HCC score [C] for the type. The last is uncapped, and a
    fourth column caps it: CMS limits how far the ACO's aggregate risk ratio
    may move between BY3 and the performance year, and fact_benchmark_aco_quarter
    computes that cap once per year as a single factor. It is read here off
    the IS_CURRENT_PROJECTION row of the same ACO and year and multiplied
    into every member's rate, so relative risk between members is kept and
    the capped rates sum to the capped ACO benchmark applied to the member
    mix. The contract in _models.yml says so on the columns.

    One projection serves a performance year. The two _current models have
    already reduced the benchmark facts to the latest calculable delivery, so
    all that is chosen here is the quarter: the highest QUARTER_NUM for the
    year, by default the most recent one CMS has reported. The choice is made
    once, on fct_projected_savings_current, and the enrollment-type rates and
    the BY3 scores are then read at exactly that ACO, year, period and
    benchmark submission, so a row's three rates cannot come from three
    deliveries. Their stamps are carried so a reader can see which.

    The spine has no ACO on it, and the connector is deployed one ACO at a
    time, so the projection joins on performance year alone and ACO_ID is
    taken from it. If the benchmark inputs ever carry two ACOs for one year
    the rank below keeps one (lowest ACO_ID) rather than doubling the fact,
    and assert_one_aco_projection_per_performance_year warns. The BY3 scores
    are ranked the same way within a submission: a redelivered workbook under
    the same stamp keeps the grain whole instead of doubling a row.

    Enrollment type and the score arrive from int_member_month_risk and are
    used as they are. A member-month without a score gets a NULL ratio and a
    NULL risk-adjusted rate — RISK_SCORE_SOURCE is NULL on exactly those rows
    — and keeps the flat and type rates; one without a resolved type keeps the
    flat rate only. A member-month in a year that has no calculable projection
    keeps its row with every rate NULL and HAS_BENCHMARK false, because the
    join to fact_member_months has to hold across the whole spine or the
    semantic layer would silently drop members from a report.

    The divisions and products go through to_double and safe_divide like the
    rest of the project; see those macros. The ratio divides by [C] as printed:
    the assignment-list scores are already on the national mean of 1.0 basis
    that [C] is renormalised to, which int_member_month_risk documents.
-#}

with member_months as (

    select
        member_month_sk                                     as MEMBER_MONTH_SK,
        person_id                                           as PERSON_ID,
        data_source                                         as DATA_SOURCE,
        patient_source_key                                  as PATIENT_SOURCE_KEY,
        year_month                                          as YEAR_MONTH,
        {{ cast_year_or_null('year_nbr') }}                 as PERFORMANCE_YEAR,
        total_paid                                          as TOTAL_PAID
    from {{ ref('the_tuva_project', 'semantic_layer__fact_member_months') }}

),

member_risk as (

    select
        PERSON_ID,
        DATA_SOURCE,
        YEAR_MONTH,
        IS_ASSIGNED,
        ENROLLMENT_TYPE,
        ENROLLMENT_TYPE_SOURCE,
        RISK_SCORE,
        RISK_SCORE_SOURCE
    from {{ ref('int_member_month_risk') }}

),

-- One projection per performance year: the latest reported quarter on the
-- latest calculable delivery. Rows arrive already filtered to that delivery.
projection_ranked as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID,
        QUARTERLY_SUBMISSION_ID,
        IS_AGREEMENT_DEFAULTED,
        MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM,
        row_number() over (
            partition by PERFORMANCE_YEAR
            order by QUARTER_NUM desc, ACO_ID
        )                                                   as PROJECTION_RANK
    from {{ ref('fct_projected_savings_current') }}

),

projection as (

    select *
    from projection_ranked
    where PROJECTION_RANK = 1

),

-- [M]/12 by enrollment type, at exactly the projection's pairing.
enrollment_type_rates as (

    select
        rates.ACO_ID,
        rates.PERFORMANCE_YEAR,
        rates.ENROLLMENT_TYPE,
        rates.PROJECTED_UPDATED_BENCHMARK_EXPENDITURE_PMPM
    from {{ ref('fct_projected_benchmark_by_enrollment_type_current') }} as rates
    inner join projection
        on projection.ACO_ID = rates.ACO_ID
        and projection.PERFORMANCE_YEAR = rates.PERFORMANCE_YEAR
        and projection.PERIOD = rates.PERIOD
        and projection.BENCHMARK_SUBMISSION_ID = rates.BENCHMARK_SUBMISSION_ID

),

-- [C] at BY3 by enrollment type, from the projection's benchmark delivery.
by3_scores_ranked as (

    select
        scores.ACO_ID,
        scores.PERFORMANCE_YEAR,
        scores.ENROLLMENT_TYPE,
        scores.ACO_RISK_SCORE,
        row_number() over (
            partition by scores.ACO_ID, scores.PERFORMANCE_YEAR, scores.ENROLLMENT_TYPE
            order by scores.FILE_DATE desc nulls last, scores.FILE_PATH desc
        )                                                   as SCORE_RANK
    from {{ ref('int_benchmark_risk_scores') }} as scores
    inner join projection
        on projection.ACO_ID = scores.ACO_ID
        and projection.PERFORMANCE_YEAR = scores.PERFORMANCE_YEAR
        and projection.BENCHMARK_SUBMISSION_ID = scores.SUBMISSION_ID
    where scores.BY_LABEL = 'BY3'

),

by3_scores as (

    select *
    from by3_scores_ranked
    where SCORE_RANK = 1

),

-- The year's cap factor, from the ACO-quarter fact's row for the same
-- projection. The factor is NULL where a type had no scored members, and
-- the capped rate is then NULL rather than uncapped.
cap_factors as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        CAP_FACTOR
    from {{ ref('fact_benchmark_aco_quarter') }}
    where IS_CURRENT_PROJECTION

),

rates as (

    select
        member_months.MEMBER_MONTH_SK                       as MEMBER_MONTH_SK,
        member_months.PERSON_ID                             as PERSON_ID,
        member_months.DATA_SOURCE                           as DATA_SOURCE,
        member_months.PATIENT_SOURCE_KEY                    as PATIENT_SOURCE_KEY,
        member_months.YEAR_MONTH                            as YEAR_MONTH,
        member_months.PERFORMANCE_YEAR                      as PERFORMANCE_YEAR,
        projection.ACO_ID                                   as ACO_ID,
        coalesce(member_risk.IS_ASSIGNED, false)            as IS_ASSIGNED,
        member_risk.ENROLLMENT_TYPE                         as ENROLLMENT_TYPE,
        member_risk.ENROLLMENT_TYPE_SOURCE                  as ENROLLMENT_TYPE_SOURCE,
        member_risk.RISK_SCORE                              as RISK_SCORE,
        member_risk.RISK_SCORE_SOURCE                       as RISK_SCORE_SOURCE,
        by3_scores.ACO_RISK_SCORE                           as BY3_ENROLLMENT_TYPE_RISK_SCORE,

        {{ safe_divide('member_risk.RISK_SCORE', 'by3_scores.ACO_RISK_SCORE') }}
                                                            as RISK_RATIO,

        {{ to_double('projection.MEAN_PROJECTED_UPDATED_BENCHMARK_PMPM') }}
                                                            as FLAT_BENCHMARK_PMPM,
        {{ to_double('enrollment_type_rates.PROJECTED_UPDATED_BENCHMARK_EXPENDITURE_PMPM') }}
                                                            as ENROLLMENT_TYPE_BENCHMARK_PMPM,

        cap_factors.CAP_FACTOR                              as CAP_FACTOR,

        member_months.TOTAL_PAID                            as TOTAL_PAID,
        projection.PERFORMANCE_YEAR is not null             as HAS_BENCHMARK,
        projection.PERIOD                                   as BENCHMARK_PERIOD,
        projection.QUARTER_NUM                              as BENCHMARK_QUARTER_NUM,
        projection.BENCHMARK_SUBMISSION_ID                  as BENCHMARK_SUBMISSION_ID,
        projection.QUARTERLY_SUBMISSION_ID                  as QUARTERLY_SUBMISSION_ID,
        projection.IS_AGREEMENT_DEFAULTED                   as IS_AGREEMENT_DEFAULTED

    from member_months

    left join member_risk
        on member_risk.PERSON_ID = member_months.PERSON_ID
        and member_risk.DATA_SOURCE = member_months.DATA_SOURCE
        and member_risk.YEAR_MONTH = member_months.YEAR_MONTH

    left join projection
        on projection.PERFORMANCE_YEAR = member_months.PERFORMANCE_YEAR

    left join enrollment_type_rates
        on enrollment_type_rates.ACO_ID = projection.ACO_ID
        and enrollment_type_rates.PERFORMANCE_YEAR = projection.PERFORMANCE_YEAR
        and enrollment_type_rates.ENROLLMENT_TYPE = member_risk.ENROLLMENT_TYPE

    left join by3_scores
        on by3_scores.ACO_ID = projection.ACO_ID
        and by3_scores.PERFORMANCE_YEAR = projection.PERFORMANCE_YEAR
        and by3_scores.ENROLLMENT_TYPE = member_risk.ENROLLMENT_TYPE

    left join cap_factors
        on cap_factors.ACO_ID = projection.ACO_ID
        and cap_factors.PERFORMANCE_YEAR = projection.PERFORMANCE_YEAR

),

adjusted as (

    select
        rates.*,

        {#- type rate x (score / BY3 [C]), uncapped -#}
        ENROLLMENT_TYPE_BENCHMARK_PMPM * RISK_RATIO         as RISK_ADJUSTED_BENCHMARK_PMPM

    from rates

),

capped as (

    select
        adjusted.*,

        {#- the uncapped rate x the year's cap factor -#}
        RISK_ADJUSTED_BENCHMARK_PMPM * CAP_FACTOR           as RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED

    from adjusted

)

select
    MEMBER_MONTH_SK,
    PERSON_ID,
    DATA_SOURCE,
    PATIENT_SOURCE_KEY,
    YEAR_MONTH,
    PERFORMANCE_YEAR,
    ACO_ID,
    IS_ASSIGNED,
    ENROLLMENT_TYPE,
    ENROLLMENT_TYPE_SOURCE,
    RISK_SCORE,
    RISK_SCORE_SOURCE,
    BY3_ENROLLMENT_TYPE_RISK_SCORE,
    RISK_RATIO,
    FLAT_BENCHMARK_PMPM,
    ENROLLMENT_TYPE_BENCHMARK_PMPM,
    RISK_ADJUSTED_BENCHMARK_PMPM,
    CAP_FACTOR,
    RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED,
    TOTAL_PAID,

    {#- actual minus benchmark -#}
    {{ to_double('TOTAL_PAID') }} - FLAT_BENCHMARK_PMPM     as VARIANCE_TO_FLAT,
    {{ to_double('TOTAL_PAID') }} - ENROLLMENT_TYPE_BENCHMARK_PMPM
                                                            as VARIANCE_TO_ENROLLMENT_TYPE,
    {{ to_double('TOTAL_PAID') }} - RISK_ADJUSTED_BENCHMARK_PMPM
                                                            as VARIANCE_TO_RISK_ADJUSTED,
    {{ to_double('TOTAL_PAID') }} - RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED
                                                            as VARIANCE_TO_RISK_ADJUSTED_CAPPED,

    HAS_BENCHMARK,
    BENCHMARK_PERIOD,
    BENCHMARK_QUARTER_NUM,
    BENCHMARK_SUBMISSION_ID,
    QUARTERLY_SUBMISSION_ID,
    IS_AGREEMENT_DEFAULTED

from capped
