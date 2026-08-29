{{ config(severity = 'warn') }}

{#-
    Warns for every ACO and performance year present in the benchmark data but
    absent from the mssp_aco_agreement seed.

    Two facts the CMS workbooks do not carry have to come from somewhere: which
    minimum savings rate the ACO elected, and which of BNMRK Table 6's five
    performance year columns [J] should be read from. With no seed row both are
    defaulted — Variable, and PY1 — and both defaults are the product owner's
    explicit choice rather than a fallback invented here.

    A default is a guess, though, and the two it makes are not free. A
    two-sided ACO that elected a fixed rate gets an MSR from the wrong schedule
    entirely, and an ACO past the first year of its agreement gets [J] from the
    wrong column, which moves [K], [M], [P] and [R] with it. The output rows say
    so: IS_AGREEMENT_DEFAULTED is true on every one of them.

    Deliberately a warning. The pipeline must run for an ACO nobody has
    configured yet — that is the whole point of having a default — so failing
    the build would make the default useless. What must not happen is the guess
    passing unremarked, and that is what this covers.
-#}

with observed as (

    select distinct
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR
    from {{ ref('fct_projected_savings') }}

),

configured as (

    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR
    from {{ ref('mssp_aco_agreement') }}

)

select
    observed.ACO_ID,
    observed.PERFORMANCE_YEAR
from observed
left join configured
    on observed.ACO_ID = configured.ACO_ID
   and observed.PERFORMANCE_YEAR = configured.PERFORMANCE_YEAR
where configured.ACO_ID is null
