{#-
    SAVINGS_EXCEEDS_MSR and SAVINGS_STATUS must tell the same story.

    They are the same comparison, [W], stored twice: a boolean for the common
    question and a three-valued enum for the case where "false" is ambiguous.
    Nothing in the model ties them together — they are two independent CASE
    expressions over the same two inputs, written out separately — so an edit to
    one and not the other produces a row that contradicts itself while every
    column on it stays inside its accepted values.

    That is not hypothetical. A review of this model found a mutation of the
    enum's final arm that left the real delivery reporting
    SAVINGS_EXCEEDS_MSR = false beside SAVINGS_STATUS = 'above_msr'. Both
    columns individually looked fine; accepted_values passed, because it
    constrains the values that appear and not the ones that should have.

    The assertion is exact and unconditional: the boolean is true exactly when
    the enum says above_msr, and the two are NULL together. There is nothing to
    recompute here and no input is re-read — it is a statement about internal
    consistency, which is the one thing neither column's own test can make.

    Deliberately not asserted: the relationship between
    EXPENDITURES_BELOW_BENCHMARK and SAVINGS_STATUS. [R] > 0 does imply [Q] < [P]
    and vice versa, but only while [P] is positive — the sign flips underneath
    if it is not — and encoding a rule that holds only for the data seen so far
    is how a test becomes something people learn to override.

      boolean_true_without_above_msr    the boolean claims savings clear the
                                        rate, the enum does not
      above_msr_without_boolean_true    the enum claims it, the boolean does not
      one_populated_one_null            one column reached a verdict and the
                                        other did not, from identical inputs
-#}

select
    ACO_ID,
    PERFORMANCE_YEAR,
    PERIOD,
    BENCHMARK_SUBMISSION_ID,
    SAVINGS_EXCEEDS_MSR,
    SAVINGS_STATUS,
    case
        when SAVINGS_EXCEEDS_MSR is null and SAVINGS_STATUS is not null
            then 'one_populated_one_null'
        when SAVINGS_EXCEEDS_MSR is not null and SAVINGS_STATUS is null
            then 'one_populated_one_null'
        when SAVINGS_EXCEEDS_MSR and SAVINGS_STATUS <> 'above_msr'
            then 'boolean_true_without_above_msr'
        when not SAVINGS_EXCEEDS_MSR and SAVINGS_STATUS = 'above_msr'
            then 'above_msr_without_boolean_true'
    end as FAILURE

from {{ ref('fct_projected_savings') }}

where (SAVINGS_EXCEEDS_MSR is null) <> (SAVINGS_STATUS is null)
   or (SAVINGS_EXCEEDS_MSR and SAVINGS_STATUS <> 'above_msr')
   or (not SAVINGS_EXCEEDS_MSR and SAVINGS_STATUS = 'above_msr')
