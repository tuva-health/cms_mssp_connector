{#-
    IS_LATEST_QUARTER must mark a quarter QEXPU Table 2 actually reports, and
    the last one, for each metric of each workbook.

    This test states the requirement rather than recomputing the model's
    definition. The distinction matters and an earlier version of this test got
    it wrong: it derived "the last reported quarter" exactly as the model does
    and then checked the model against it, so every branch was structurally
    unreachable and it returned zero rows under every mutation, including one
    that left [E] and [H] returning nothing but NULLs.

    What makes the checks below real is that they are stricter than the rule the
    model applies. The model flags the highest quarter carrying *any* number;
    the requirement is that the flagged quarter is one CMS reported, and CMS
    reports a quarter for every enrollment type at once. So a quarter populated
    for one enrollment type and blank for the other three satisfies the model
    and fails incomplete_quarter here — no recomputation involved, just a
    statement about what a reported quarter looks like.

      too_many_quarters   more than one quarter flagged for a metric, so [E],
                          [G] or [H] returns several values where one is due
      no_quarter_flagged  the metric reports a quarter but none is flagged, so
                          those inputs come back empty
      incomplete_quarter  the flagged quarter is blank on at least one of its
                          rows — the failure mode this column exists to
                          prevent, since CMS ships all four quarter columns
                          from Q1 onward and leaves the unreported ones blank
      later_quarter       a quarter after the flagged one carries data, so the
                          wrong column was chosen. Anchor section only — see
                          the scope note below

    Scope: three of the four branches apply to every metric. Only later_quarter
    is restricted to the regional expenditure section, and the asymmetry is the
    point.

    IS_LATEST_QUARTER is derived from the regional expenditure section and
    applied to all three, so "does a later quarter carry data" means two
    different things depending on which metric is asked. Of the anchor it is a
    statement about the flag, and a failure. Of a weight metric it is a
    statement about whether the sections agree — which is a real question, but
    one that belongs to assert_regional_metrics_agree_on_the_latest_quarter at
    warn severity, because a genuine change in how CMS writes the sheet needs a
    human reading the sheet rather than a build that will not run. Asserting it
    here as well would make that warning unreachable: this test would error
    first.

    The other three say the same thing about every metric, and under the anchor
    they say it about the weights more sharply than before, not less.
    incomplete_quarter in particular is what stands between a blank weight
    column and a silently empty answer: the flag is set from the anchor, so if
    National Weight is blank at the flagged quarter then [G] is NULL for those
    enrollment types, [I] and [M] collapse with it, and [P], [R] and
    SAVINGS_STATUS go NULL for the whole ACO while every row still looks
    well-formed. An earlier revision of this test narrowed all four branches to
    the anchor at once and lost exactly that, which is why the scope is now set
    per branch instead of per test.

    A workbook whose anchor section reports no quarter at all is not a failure
    here — there is no quarter to flag, IS_LATEST_QUARTER is false everywhere
    and no_quarter_flagged needs a metric that does report one.
    assert_regional_metrics_report_a_quarter warns about that case.
-#}

with quarters as (

    select
        FILE_PATH,
        METRIC,
        QUARTER_NUM,
        IS_LATEST_QUARTER,
        VALUE_NUMERIC
    from {{ ref('int_expenditures_regional') }}
    where PERIOD_TYPE = 'quarter'

),

flagged as (

    select
        FILE_PATH,
        METRIC,
        count(distinct case when IS_LATEST_QUARTER then QUARTER_NUM end)
            as FLAGGED_QUARTER_COUNT,
        max(case when IS_LATEST_QUARTER then QUARTER_NUM end)
            as FLAGGED_QUARTER_NUM,
        count(case when IS_LATEST_QUARTER and VALUE_NUMERIC is null then 1 end)
            as FLAGGED_BLANK_CELL_COUNT,
        count(VALUE_NUMERIC)
            as REPORTED_CELL_COUNT
    from quarters
    group by FILE_PATH, METRIC

),

later_reported as (

    select
        flagged.FILE_PATH,
        flagged.METRIC,
        count(quarters.QUARTER_NUM) as LATER_REPORTED_CELL_COUNT
    from flagged
    left join quarters
        on quarters.FILE_PATH = flagged.FILE_PATH
       and quarters.METRIC = flagged.METRIC
       and quarters.QUARTER_NUM > flagged.FLAGGED_QUARTER_NUM
       and quarters.VALUE_NUMERIC is not null
    group by flagged.FILE_PATH, flagged.METRIC

)

select
    flagged.FILE_PATH,
    flagged.METRIC,
    flagged.FLAGGED_QUARTER_COUNT,
    flagged.FLAGGED_QUARTER_NUM,
    flagged.FLAGGED_BLANK_CELL_COUNT,
    later_reported.LATER_REPORTED_CELL_COUNT,
    case
        when flagged.FLAGGED_QUARTER_COUNT > 1                  then 'too_many_quarters'
        when flagged.FLAGGED_QUARTER_COUNT = 0
             and flagged.REPORTED_CELL_COUNT > 0                then 'no_quarter_flagged'
        when flagged.FLAGGED_BLANK_CELL_COUNT > 0               then 'incomplete_quarter'
        when later_reported.LATER_REPORTED_CELL_COUNT > 0
             and flagged.METRIC = 'regional_expenditure'        then 'later_quarter'
    end as FAILURE

from flagged

inner join later_reported
    on flagged.FILE_PATH = later_reported.FILE_PATH
   and flagged.METRIC = later_reported.METRIC

where flagged.FLAGGED_QUARTER_COUNT > 1
   or (flagged.FLAGGED_QUARTER_COUNT = 0 and flagged.REPORTED_CELL_COUNT > 0)
   or flagged.FLAGGED_BLANK_CELL_COUNT > 0
   or (later_reported.LATER_REPORTED_CELL_COUNT > 0
       and flagged.METRIC = 'regional_expenditure')
