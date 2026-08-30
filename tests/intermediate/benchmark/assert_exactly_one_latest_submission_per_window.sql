{#-
    Two assertions about delivery identity and the latest-submission flag, both
    scoped to each model's own ranking window.

    latest_flag_fans_out
        More than one *workbook* carries IS_LATEST_SUBMISSION inside one window.
        This is the failure the flag exists to prevent: both the preliminary and
        the final BNMRK delivery ship their own historical benchmark
        expenditures, so a consumer that filters on a flag which is true twice
        gets the doubled benchmark.

        Counting workbooks rather than submission ids is the whole point. An
        earlier version of this test counted distinct SUBMISSION_ID among
        rank-1 rows, which is 1 by construction — dense_rank gives rank 1 to
        every row tying on the ordering key, and rows tying on SUBMISSION_ID
        necessarily share it. The test could not fail. FILE_PATH is the only
        identifier that distinguishes two workbooks that claim the same
        delivery, which is exactly the case that broke.

    submission_id_collision
        Two distinct workbooks inside one window carry the same SUBMISSION_ID.
        The ranking now breaks that tie on FILE_PATH so the flag cannot fan
        out, but breaking it arbitrarily is damage control, not correctness:
        one of the two workbooks is being silently ignored, and which one is
        decided by a path. Upstream treats the submission stamp as delivery
        identity — a collision means either a re-bundled duplicate or two
        genuinely different deliveries CMS stamped alike, and both want a human.

    The window differs per family and matches each model's own ranking: BNMRK is
    ranked within the performance year, AEXPU within the benchmark year, QEXPU
    within the reported quarter.
-#}

{%- set ranking_windows = {
    'int_benchmark_historical':   ['ACO_ID', 'PERFORMANCE_YEAR'],
    'int_benchmark_acpt':         ['ACO_ID', 'PERFORMANCE_YEAR'],
    'int_benchmark_trend':        ['ACO_ID', 'PERFORMANCE_YEAR'],
    'int_expenditures_annual':    ['ACO_ID', 'PERFORMANCE_YEAR', 'BENCHMARK_YEAR'],
    'int_expenditures_quarterly': ['ACO_ID', 'PERFORMANCE_YEAR', 'PERIOD'],
    'int_expenditures_regional':  ['ACO_ID', 'PERFORMANCE_YEAR', 'PERIOD']
} -%}

with per_window as (
{% for model_name, window in ranking_windows.items() %}

    select
        '{{ model_name }}'  as MODEL_NAME,
        count(distinct case when IS_LATEST_SUBMISSION then FILE_PATH end)
                            as LATEST_WORKBOOK_COUNT,
        count(distinct FILE_PATH)
                            as WORKBOOK_COUNT,
        count(distinct SUBMISSION_ID)
                            as SUBMISSION_ID_COUNT
    from {{ ref(model_name) }}
    group by {{ window | join(', ') }}

{%- if not loop.last %}

    union all

{% endif %}
{%- endfor %}

)

select
    MODEL_NAME,
    LATEST_WORKBOOK_COUNT,
    WORKBOOK_COUNT,
    SUBMISSION_ID_COUNT,
    case
        when LATEST_WORKBOOK_COUNT <> 1              then 'latest_flag_fans_out'
        when WORKBOOK_COUNT <> SUBMISSION_ID_COUNT   then 'submission_id_collision'
    end as FAILURE
from per_window
where LATEST_WORKBOOK_COUNT <> 1
   or WORKBOOK_COUNT <> SUBMISSION_ID_COUNT
