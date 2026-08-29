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
                          wrong column was chosen

    Scope is (FILE_PATH, METRIC): the three sections of this sheet are
    populated independently, and a workbook-wide scope lets a section that has
    run ahead drag the others onto a quarter they have no data for.

    A metric that reports no quarter at all is not a failure here — it has no
    quarter to flag. assert_regional_metrics_report_a_quarter warns about it.
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
        when later_reported.LATER_REPORTED_CELL_COUNT > 0       then 'later_quarter'
    end as FAILURE

from flagged

inner join later_reported
    on flagged.FILE_PATH = later_reported.FILE_PATH
   and flagged.METRIC = later_reported.METRIC

where flagged.FLAGGED_QUARTER_COUNT > 1
   or (flagged.FLAGGED_QUARTER_COUNT = 0 and flagged.REPORTED_CELL_COUNT > 0)
   or flagged.FLAGGED_BLANK_CELL_COUNT > 0
   or later_reported.LATER_REPORTED_CELL_COUNT > 0
