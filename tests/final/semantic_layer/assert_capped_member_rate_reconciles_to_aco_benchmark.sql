{#-
    The capped risk-adjusted rate summed over a performance year's assigned,
    scored member-months must equal the ACO-quarter fact's capped per-type
    ratios and cap factor applied to that same member mix:

        sum_members  RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED
      = sum_types    n_t x ([M]_t / 12) x r_t x c

    where n_t is the member fact's count of assigned, scored member-months of
    type t in the year, [M]_t / 12 its enrollment-type rate, and r_t and c
    are fact_benchmark_aco_quarter's RISK_RATIO_<T> and CAP_FACTOR on the
    IS_CURRENT_PROJECTION row for the ACO and year. The right-hand side is
    the risk-adjusted ACO benchmark (sum_t proportion_t x [M]_t x r_t x c)
    with the report's enrollment proportions replaced by the spine's own mix,
    which is the form the identity holds in exactly; the report's proportions
    are the quarterly list's, not the spine's, and the two mixes differ by
    assignment timing (see assert_flat_rate_reconciles_to_projected_benchmark_
    person_years).

    The identity holds only when three things are true at once: every member's
    capped rate carries the one factor of its year, the ACO fact's per-type
    mean was taken over the same member-months the member fact counts, and
    the factor was actually multiplied in. Drop the factor from the member
    fact and every year where the cap binds fails here by the size of the
    cap; read the factor off the wrong quarter, or the mean off a different
    population, and the two sides part by that much.

    A year with an ACO row but no factor (a type without scored members) has
    a NULL right-hand side and a NULL left-hand side, and reconciles by
    construction. A year whose members carry capped rates but whose ACO row
    is missing is reported as aco_row_missing.

    The tolerance is relative, 1e-9 of the expected sum, as in the uncapped
    reconciliation test and for the same reason.
-#}

{%- set enrollment_types = ['esrd', 'disabled', 'aged_dual', 'aged_non_dual'] -%}

with members as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        ENROLLMENT_TYPE,
        count(*)                                    as ASSIGNED_SCORED_MEMBER_MONTHS,
        max(ENROLLMENT_TYPE_BENCHMARK_PMPM)         as ENROLLMENT_TYPE_BENCHMARK_PMPM,
        sum(RISK_ADJUSTED_BENCHMARK_PMPM_CAPPED)    as CAPPED_SUM
    from {{ ref('fact_member_month_benchmark') }}
    where HAS_BENCHMARK
      and IS_ASSIGNED
      and RISK_SCORE is not null
      and ENROLLMENT_TYPE is not null
      and ENROLLMENT_TYPE_BENCHMARK_PMPM is not null
    group by ACO_ID, PERFORMANCE_YEAR, ENROLLMENT_TYPE

),

-- The ACO fact's per-type ratios, unpivoted to the member grain.
aco_ratios as (

    {%- for enrollment_type in enrollment_types %}
    select
        ACO_ID,
        PERFORMANCE_YEAR,
        '{{ enrollment_type }}'                     as ENROLLMENT_TYPE,
        RISK_RATIO_{{ enrollment_type | upper }}    as RISK_RATIO,
        CAP_FACTOR
    from {{ ref('fact_benchmark_aco_quarter') }}
    where IS_CURRENT_PROJECTION
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}

),

per_type as (

    select
        members.ACO_ID,
        members.PERFORMANCE_YEAR,
        members.ENROLLMENT_TYPE,
        members.ASSIGNED_SCORED_MEMBER_MONTHS,
        members.CAPPED_SUM,
        aco_ratios.ACO_ID is not null               as HAS_ACO_ROW,
        aco_ratios.CAP_FACTOR                       as CAP_FACTOR,

        {#- n_t x [M]_t / 12 x r_t x c -#}
        {{ to_double('members.ASSIGNED_SCORED_MEMBER_MONTHS') }}
            * members.ENROLLMENT_TYPE_BENCHMARK_PMPM
            * aco_ratios.RISK_RATIO
            * aco_ratios.CAP_FACTOR                 as EXPECTED_CAPPED_SUM
    from members
    left join aco_ratios
        on aco_ratios.ACO_ID = members.ACO_ID
        and aco_ratios.PERFORMANCE_YEAR = members.PERFORMANCE_YEAR
        and aco_ratios.ENROLLMENT_TYPE = members.ENROLLMENT_TYPE

),

per_year as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        sum(ASSIGNED_SCORED_MEMBER_MONTHS)          as ASSIGNED_SCORED_MEMBER_MONTHS,
        max(CAP_FACTOR)                             as CAP_FACTOR,
        sum(CAPPED_SUM)                             as CAPPED_SUM,
        sum(EXPECTED_CAPPED_SUM)                    as EXPECTED_CAPPED_SUM,
        sum(case when HAS_ACO_ROW then 0 else 1 end)
                                                    as TYPES_WITHOUT_ACO_ROW
    from per_type
    group by ACO_ID, PERFORMANCE_YEAR

)

select
    ACO_ID,
    PERFORMANCE_YEAR,
    ASSIGNED_SCORED_MEMBER_MONTHS,
    CAP_FACTOR,
    CAPPED_SUM,
    EXPECTED_CAPPED_SUM,
    case
        when TYPES_WITHOUT_ACO_ROW > 0              then 'aco_row_missing'
        when (CAPPED_SUM is null) <> (EXPECTED_CAPPED_SUM is null)
                                                    then 'one_side_null'
        else 'sum_does_not_reconcile'
    end                                             as FAILURE
from per_year
where TYPES_WITHOUT_ACO_ROW > 0
   or (CAPPED_SUM is null) <> (EXPECTED_CAPPED_SUM is null)
   or abs(CAPPED_SUM - EXPECTED_CAPPED_SUM) > 1e-9 * abs(EXPECTED_CAPPED_SUM)
