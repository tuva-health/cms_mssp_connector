{#-
    Steps [P] through [W] of the CMS calculation: the ACO-level projected
    savings percentage and how it compares to the minimum savings rate. One row
    per (reported quarter x benchmark delivery), collapsing the four
    enrollment-type rows of fct_projected_benchmark_by_enrollment_type.

    It inherits that model's grain and its warnings. Every pairing of a quarter
    with a benchmark delivery is a row, so an unfiltered query returns up to
    three rows per quarter carrying three different answers;
    IS_LATEST_BENCHMARK_SUBMISSION collapses it to one. A pairing whose inputs
    are incomplete — the March delivery ships no Table 6, so [J] and everything
    below it is missing — still gets its row, with NULLs and IS_CALCULABLE =
    false.

    [P] is summed as four named terms added in a fixed order rather than with
    an aggregate. Floating point addition is not associative, and the reference
    implementation sums the enrollment types in CMS's own order; an aggregate
    would leave the order to the query planner and put the last bit of a
    dollars-and-cents figure at its discretion.

    The verdicts CMS states in prose are stored as a boolean and an enum. The
    reference implementation returns English sentences for [V] and [W] because
    it renders them straight onto a page; a warehouse column that has to be
    string-matched to be used is a worse version of the same fact.
-#}

with per_enrollment_type as (

    select * from {{ ref('fct_projected_benchmark_by_enrollment_type') }}

),

aco_expenditure as (

    {#- [Q] The ACO's own total per capita expenditure for the quarter. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_quarterly') }}
    where METRIC = 'total_expenditures_per_capita'
      and COLUMN_VARIANT = 'aco_specific'
      and ENROLLMENT_TYPE = 'total'

),

assigned_beneficiaries as (

    {#- [S] Total assigned beneficiaries, the input to the MSR schedule. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_quarterly') }}
    where METRIC = 'total_assigned_beneficiaries'
      and COLUMN_VARIANT = 'aco_specific'

),

agreement as (

    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        MSR_TYPE            as MSR_TYPE,
        FIXED_MSR_RATE      as FIXED_MSR_RATE,
        ACO_TRACK           as ACO_TRACK
    from {{ ref('mssp_aco_agreement') }}

),

msr_band as (

    select
        ASSIGNED_BENEFICIARIES_LOW      as ASSIGNED_BENEFICIARIES_LOW,
        ASSIGNED_BENEFICIARIES_HIGH     as ASSIGNED_BENEFICIARIES_HIGH,
        MSR_AT_LOW                      as MSR_AT_LOW,
        MSR_AT_HIGH                     as MSR_AT_HIGH
    from {{ ref('mssp_msr_lookup') }}

),

sum_product as (

    {#- [P] = SUMPRODUCT([O], [M]), as four ordered terms. Any missing term
        makes the whole sum NULL, which is the behaviour wanted: a mean over
        three of four cohorts is not a mean. -#}
    select
        ACO_ID                                          as ACO_ID,
        PERFORMANCE_YEAR                                as PERFORMANCE_YEAR,
        PERIOD                                          as PERIOD,
        QUARTER_NUM                                     as QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID                         as BENCHMARK_SUBMISSION_ID,
        min(case when IS_LATEST_BENCHMARK_SUBMISSION then 1 else 0 end) = 1
                                                        as IS_LATEST_BENCHMARK_SUBMISSION,
        min(QUARTERLY_SUBMISSION_ID)                    as QUARTERLY_SUBMISSION_ID,
        min(ANNUAL_EXPENDITURE_BENCHMARK_YEAR)          as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
        min(ANNUAL_EXPENDITURE_SUBMISSION_ID)           as ANNUAL_EXPENDITURE_SUBMISSION_ID,
        min(ACPT_PERFORMANCE_YEAR_LABEL)                as ACPT_PERFORMANCE_YEAR_LABEL,
        min(case when IS_AGREEMENT_DEFAULTED then 1 else 0 end) = 1
                                                        as IS_AGREEMENT_DEFAULTED,

        max(case when ENROLLMENT_TYPE = 'esrd'
                 then ENROLLMENT_PROPORTION * PROJECTED_UPDATED_BENCHMARK_EXPENDITURE end)
                                                        as TERM_ESRD,
        max(case when ENROLLMENT_TYPE = 'disabled'
                 then ENROLLMENT_PROPORTION * PROJECTED_UPDATED_BENCHMARK_EXPENDITURE end)
                                                        as TERM_DISABLED,
        max(case when ENROLLMENT_TYPE = 'aged_dual'
                 then ENROLLMENT_PROPORTION * PROJECTED_UPDATED_BENCHMARK_EXPENDITURE end)
                                                        as TERM_AGED_DUAL,
        max(case when ENROLLMENT_TYPE = 'aged_non_dual'
                 then ENROLLMENT_PROPORTION * PROJECTED_UPDATED_BENCHMARK_EXPENDITURE end)
                                                        as TERM_AGED_NON_DUAL

    from per_enrollment_type
    group by
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        QUARTER_NUM,
        BENCHMARK_SUBMISSION_ID

),

mean_benchmark as (

    select
        sum_product.*,
        TERM_ESRD + TERM_DISABLED + TERM_AGED_DUAL + TERM_AGED_NON_DUAL
                                                        as MEAN_PROJECTED_UPDATED_BENCHMARK
    from sum_product

),

with_expenditure as (

    select
        mean_benchmark.*,

        aco_expenditure.VALUE_NUMERIC                   as ACO_EXPENDITURE_PER_CAPITA,
        assigned_beneficiaries.VALUE_NUMERIC            as ASSIGNED_BENEFICIARIES,

        {#- The MSR schedule is indexed by a whole beneficiary count. FLOOR,
            not CAST: rounding half-up would move a count sitting exactly on a
            band boundary into the next band. -#}
        floor({{ to_double('assigned_beneficiaries.VALUE_NUMERIC') }})
                                                        as ASSIGNED_BENEFICIARY_COUNT,

        coalesce(agreement.MSR_TYPE, 'Variable')        as MSR_TYPE,
        agreement.FIXED_MSR_RATE                        as FIXED_MSR_RATE,
        agreement.ACO_TRACK                             as ACO_TRACK

    from mean_benchmark

    left join aco_expenditure
        on mean_benchmark.ACO_ID = aco_expenditure.ACO_ID
       and mean_benchmark.PERFORMANCE_YEAR = aco_expenditure.PERFORMANCE_YEAR
       and mean_benchmark.PERIOD = aco_expenditure.PERIOD
       and mean_benchmark.QUARTERLY_SUBMISSION_ID = aco_expenditure.SUBMISSION_ID

    left join assigned_beneficiaries
        on mean_benchmark.ACO_ID = assigned_beneficiaries.ACO_ID
       and mean_benchmark.PERFORMANCE_YEAR = assigned_beneficiaries.PERFORMANCE_YEAR
       and mean_benchmark.PERIOD = assigned_beneficiaries.PERIOD
       and mean_benchmark.QUARTERLY_SUBMISSION_ID = assigned_beneficiaries.SUBMISSION_ID

    left join agreement
        on mean_benchmark.ACO_ID = agreement.ACO_ID
       and mean_benchmark.PERFORMANCE_YEAR = agreement.PERFORMANCE_YEAR

),

with_msr_band as (

    {#- The band the beneficiary count falls in. Both bounds are inclusive and
        either may be NULL, meaning unbounded on that side, so the join has to
        be written as two guarded comparisons rather than a BETWEEN. -#}
    select
        with_expenditure.*,

        msr_band.ASSIGNED_BENEFICIARIES_LOW             as MSR_BAND_LOW,
        msr_band.ASSIGNED_BENEFICIARIES_HIGH            as MSR_BAND_HIGH,
        msr_band.MSR_AT_LOW                             as MSR_BAND_RATE_AT_LOW,
        msr_band.MSR_AT_HIGH                            as MSR_BAND_RATE_AT_HIGH

    from with_expenditure

    left join msr_band
        on (msr_band.ASSIGNED_BENEFICIARIES_LOW is null
            or with_expenditure.ASSIGNED_BENEFICIARY_COUNT >= msr_band.ASSIGNED_BENEFICIARIES_LOW)
       and (msr_band.ASSIGNED_BENEFICIARIES_HIGH is null
            or with_expenditure.ASSIGNED_BENEFICIARY_COUNT <= msr_band.ASSIGNED_BENEFICIARIES_HIGH)

),

msr as (

    select
        with_msr_band.*,

        {#- A fixed rate is only reachable by an ACO that elected one and has at
            least 5,000 assigned beneficiaries. Below that threshold the
            election does not apply and the variable schedule governs, which is
            why this is a property of the row and not of the agreement. A
            `Fixed` row that carries no rate has elected nothing usable and
            falls through here the same way. -#}
        case
            when ASSIGNED_BENEFICIARY_COUNT is null         then cast(null as {{ dbt.type_string() }})
            when MSR_TYPE = 'Fixed'
                 and FIXED_MSR_RATE is not null
                 and ASSIGNED_BENEFICIARY_COUNT >= 5000     then 'fixed'
            else 'variable'
        end                                             as MSR_BASIS_APPLIED,

        {#- Linear interpolation between the band's endpoints. A band whose two
            rates are equal, or which is unbounded on either side, is flat and
            has nothing to interpolate across. -#}
        case
            when MSR_BAND_RATE_AT_LOW = MSR_BAND_RATE_AT_HIGH
                then {{ to_double('MSR_BAND_RATE_AT_LOW') }}
            when MSR_BAND_LOW is null or MSR_BAND_HIGH is null
                then {{ to_double('MSR_BAND_RATE_AT_LOW') }}
            else {{ to_double('MSR_BAND_RATE_AT_LOW') }}
                 + ( {{ to_double('ASSIGNED_BENEFICIARY_COUNT') }} - {{ to_double('MSR_BAND_LOW') }} )
                   / ( {{ to_double('MSR_BAND_HIGH') }} - {{ to_double('MSR_BAND_LOW') }} )
                   * ( {{ to_double('MSR_BAND_RATE_AT_HIGH') }} - {{ to_double('MSR_BAND_RATE_AT_LOW') }} )
        end                                             as VARIABLE_MSR

    from with_msr_band

),

savings as (

    select
        msr.*,

        {#- [R] = ([P] - [Q]) / [P] -#}
        {{ safe_divide(
               'MEAN_PROJECTED_UPDATED_BENCHMARK - '
               ~ to_double('ACO_EXPENDITURE_PER_CAPITA'),
               'MEAN_PROJECTED_UPDATED_BENCHMARK') }}
                                                        as PROJECTED_SAVINGS_PERCENTAGE,

        {#- [U] -#}
        case
            when MSR_BASIS_APPLIED = 'fixed'    then {{ to_double('FIXED_MSR_RATE') }}
            when MSR_BASIS_APPLIED = 'variable' then VARIABLE_MSR
        end                                             as ESTIMATED_MSR

    from msr

)

select
    ACO_ID                                              as ACO_ID,
    PERFORMANCE_YEAR                                    as PERFORMANCE_YEAR,
    PERIOD                                              as PERIOD,
    QUARTER_NUM                                         as QUARTER_NUM,
    BENCHMARK_SUBMISSION_ID                             as BENCHMARK_SUBMISSION_ID,
    IS_LATEST_BENCHMARK_SUBMISSION                      as IS_LATEST_BENCHMARK_SUBMISSION,

    MEAN_PROJECTED_UPDATED_BENCHMARK                    as MEAN_PROJECTED_UPDATED_BENCHMARK,
    ACO_EXPENDITURE_PER_CAPITA                          as ACO_EXPENDITURE_PER_CAPITA,
    PROJECTED_SAVINGS_PERCENTAGE                        as PROJECTED_SAVINGS_PERCENTAGE,
    ASSIGNED_BENEFICIARIES                              as ASSIGNED_BENEFICIARIES,
    MSR_TYPE                                            as MSR_TYPE,
    FIXED_MSR_RATE                                      as FIXED_MSR_RATE,
    ACO_TRACK                                           as ACO_TRACK,
    MSR_BASIS_APPLIED                                   as MSR_BASIS_APPLIED,
    ESTIMATED_MSR                                       as ESTIMATED_MSR,

    {#- [V] Expenditures against the projected updated benchmark. Equality
        reads as false: two doubles are equal essentially never, and "not
        below" is the honest reading of it. -#}
    case
        when MEAN_PROJECTED_UPDATED_BENCHMARK is null
             or ACO_EXPENDITURE_PER_CAPITA is null      then cast(null as {{ dbt.type_boolean() }})
        else {{ to_double('ACO_EXPENDITURE_PER_CAPITA') }}
             < MEAN_PROJECTED_UPDATED_BENCHMARK
    end                                                 as EXPENDITURES_BELOW_BENCHMARK,

    {#- [W] Savings against the minimum savings rate. -#}
    case
        when PROJECTED_SAVINGS_PERCENTAGE is null
             or ESTIMATED_MSR is null                   then cast(null as {{ dbt.type_boolean() }})
        else PROJECTED_SAVINGS_PERCENTAGE > 0
             and PROJECTED_SAVINGS_PERCENTAGE > ESTIMATED_MSR
    end                                                 as SAVINGS_EXCEEDS_MSR,

    case
        when PROJECTED_SAVINGS_PERCENTAGE is null
             or ESTIMATED_MSR is null                   then cast(null as {{ dbt.type_string() }})
        when PROJECTED_SAVINGS_PERCENTAGE <= 0          then 'no_savings'
        when PROJECTED_SAVINGS_PERCENTAGE > ESTIMATED_MSR
                                                        then 'above_msr'
        else 'below_msr'
    end                                                 as SAVINGS_STATUS,

    MEAN_PROJECTED_UPDATED_BENCHMARK is not null        as IS_CALCULABLE,

    QUARTERLY_SUBMISSION_ID                             as QUARTERLY_SUBMISSION_ID,
    ANNUAL_EXPENDITURE_BENCHMARK_YEAR                   as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
    ANNUAL_EXPENDITURE_SUBMISSION_ID                    as ANNUAL_EXPENDITURE_SUBMISSION_ID,
    ACPT_PERFORMANCE_YEAR_LABEL                         as ACPT_PERFORMANCE_YEAR_LABEL,
    IS_AGREEMENT_DEFAULTED                              as IS_AGREEMENT_DEFAULTED

from savings
