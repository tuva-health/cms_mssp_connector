{#-
    Fails when one performance year has more than one latest AEXPU workbook
    under the same benchmark-year label.

    assert_exactly_one_latest_submission_per_window checks the flag inside
    int_expenditures_annual's own ranking window, (ACO, performance year,
    benchmark year). That window cannot see this failure. A workbook for a
    different benchmark year forms a window of its own, ranks first in it and
    labels itself from its own submission. The final settlement bundle's AEXPU
    did exactly that (TUVA-159): its submission ('STLMT.' plus the stamp) holds
    one workbook, for the performance year, so it ranked first for that year
    and counted itself BY3. Every consumer that reads the latest BY3 then got
    two workbooks for one performance year.

    A consumer finds a workbook by label, not by benchmark year, so this test
    counts by label: one latest workbook per (ACO, performance year,
    BENCHMARK_YEAR_LABEL).
-#}

select
    ACO_ID,
    PERFORMANCE_YEAR,
    BENCHMARK_YEAR_LABEL,
    count(distinct FILE_PATH)       as LATEST_WORKBOOK_COUNT,
    count(distinct BENCHMARK_YEAR)  as BENCHMARK_YEAR_COUNT,
    min(SUBMISSION_ID)              as FIRST_SUBMISSION_ID,
    max(SUBMISSION_ID)              as LAST_SUBMISSION_ID
from {{ ref('int_expenditures_annual') }}
where IS_LATEST_SUBMISSION
group by ACO_ID, PERFORMANCE_YEAR, BENCHMARK_YEAR_LABEL
having count(distinct FILE_PATH) > 1
