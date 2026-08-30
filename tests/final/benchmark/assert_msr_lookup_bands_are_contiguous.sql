{#-
    The MSR bands must tile every beneficiary count exactly once, and the rate
    must be continuous where two bands meet.

    [U] is produced by joining a beneficiary count to whichever band contains
    it. That join is written as two guarded comparisons against nullable bounds,
    which means the seed — not the SQL — is what stops it from matching twice or
    not at all. A gap between two bands silently NULLs the MSR, and the row's
    savings verdict quietly becomes undeterminable. An overlap silently fans the
    savings fact out, duplicating a row that the grain test would then fail on
    with no indication of why.

    Continuity is checked because the bands interpolate. Each band runs from its
    own rate at its lower bound to its own rate at its upper bound, and the
    schedule is only a single function of beneficiary count if one band's rate
    at its top equals the next band's rate at its bottom. A transcription slip
    of one digit in one of those twenty-eight numbers would put a step in the
    curve that nothing else here would catch.

      unbounded_low_band_count    exactly one band may be open at the bottom
      unbounded_high_band_count   exactly one band may be open at the top
      inverted_bounds             a band whose lower bound exceeds its upper
      gap_or_overlap              a band that does not start one above the
                                  previous band's end
      rate_discontinuity          a band whose starting rate is not the previous
                                  band's ending rate
-#}

with bands as (

    select
        ASSIGNED_BENEFICIARIES_LOW,
        ASSIGNED_BENEFICIARIES_HIGH,
        MSR_AT_LOW,
        MSR_AT_HIGH,
        lag(ASSIGNED_BENEFICIARIES_HIGH) over (
            order by ASSIGNED_BENEFICIARIES_LOW nulls first
        ) as PREVIOUS_HIGH,
        lag(MSR_AT_HIGH) over (
            order by ASSIGNED_BENEFICIARIES_LOW nulls first
        ) as PREVIOUS_MSR_AT_HIGH
    from {{ ref('mssp_msr_lookup') }}

),

open_ended as (

    select
        count(case when ASSIGNED_BENEFICIARIES_LOW is null then 1 end)  as UNBOUNDED_LOW_BAND_COUNT,
        count(case when ASSIGNED_BENEFICIARIES_HIGH is null then 1 end) as UNBOUNDED_HIGH_BAND_COUNT
    from {{ ref('mssp_msr_lookup') }}

),

band_failures as (

    select
        ASSIGNED_BENEFICIARIES_LOW,
        ASSIGNED_BENEFICIARIES_HIGH,
        case
            when ASSIGNED_BENEFICIARIES_LOW is not null
                 and ASSIGNED_BENEFICIARIES_HIGH is not null
                 and ASSIGNED_BENEFICIARIES_LOW > ASSIGNED_BENEFICIARIES_HIGH
                then 'inverted_bounds'
            when PREVIOUS_HIGH is not null
                 and ASSIGNED_BENEFICIARIES_LOW <> PREVIOUS_HIGH + 1
                then 'gap_or_overlap'
            when PREVIOUS_MSR_AT_HIGH is not null
                 and MSR_AT_LOW <> PREVIOUS_MSR_AT_HIGH
                then 'rate_discontinuity'
        end as FAILURE
    from bands

)

select
    ASSIGNED_BENEFICIARIES_LOW,
    ASSIGNED_BENEFICIARIES_HIGH,
    FAILURE
from band_failures
where FAILURE is not null

union all

select
    cast(null as {{ dbt.type_bigint() }}),
    cast(null as {{ dbt.type_bigint() }}),
    case
        when UNBOUNDED_LOW_BAND_COUNT <> 1  then 'unbounded_low_band_count'
        else 'unbounded_high_band_count'
    end
from open_ended
where UNBOUNDED_LOW_BAND_COUNT <> 1
   or UNBOUNDED_HIGH_BAND_COUNT <> 1
