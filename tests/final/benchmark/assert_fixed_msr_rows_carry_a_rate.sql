{#-
    An agreement row that declares a fixed MSR must say what the rate is.

    MSR_TYPE = 'Fixed' with no FIXED_MSR_RATE describes an election that cannot
    be applied. The model does not fail on it — it falls through to the variable
    schedule, matching the reference implementation, which reaches the same
    place by failing to parse the rate string. That is the right runtime
    behaviour and the wrong thing to leave unsaid: the row asserts one schedule
    and gets the other, and every column on the output agrees with itself, so
    nothing downstream looks wrong.

    An error rather than a warning, unlike the missing-row case next door. A
    missing row is a legitimate state with a documented default behind it. This
    is a contradiction inside a file the operator wrote by hand, and there is no
    reading of it that was intended.
-#}

select
    ACO_ID,
    PERFORMANCE_YEAR,
    MSR_TYPE,
    FIXED_MSR_RATE
from {{ ref('mssp_aco_agreement') }}
where MSR_TYPE = 'Fixed'
  and FIXED_MSR_RATE is null
