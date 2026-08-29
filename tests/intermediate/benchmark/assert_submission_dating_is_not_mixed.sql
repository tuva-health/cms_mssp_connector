{#-
    A ranking window must not contain both dated and undated deliveries.

    The submission ranking orders on FILE_DATE descending with NULLs last, so an
    undated delivery never outranks a dated one — a placeholder stamp means
    "recency unknown", not "newest". That policy is right in isolation and wrong
    in a mixed population: CMS ships anonymised and sample workbooks whose
    D<YYMMDD> stamp is a placeholder rather than a date, so a window holding one
    real delivery and one placeholder ranks the real one first *whatever order
    they actually arrived in*. Give the March preliminary delivery a genuine stamp, leave June
    as a placeholder, and IS_LATEST_SUBMISSION resolves to March — the older
    benchmark, silently.

    Neither ordering is defensible there, because the undated delivery carries
    no evidence either way. The policy stays as it is; this test makes the one
    situation where it cannot be trusted loud instead of quiet. The fix when it
    fires is upstream: stamp every delivery in the window, or hold the
    placeholder deliveries in a separate file store.

    In practice only BNMRK can trip this. FILE_DATE is the delivery stamp there
    and can fail to parse; for AEXPU and QEXPU it is the benchmark year end and
    the quarter end, both derived from tokens that always parse. The other three
    models are checked anyway rather than assumed — the assumption is upstream's
    and this test does not depend on it.
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
        count(distinct case when FILE_DATE is not null then FILE_PATH end)
                            as DATED_WORKBOOK_COUNT,
        count(distinct case when FILE_DATE is null then FILE_PATH end)
                            as UNDATED_WORKBOOK_COUNT
    from {{ ref(model_name) }}
    group by {{ window | join(', ') }}

{%- if not loop.last %}

    union all

{% endif %}
{%- endfor %}

)

select
    MODEL_NAME,
    DATED_WORKBOOK_COUNT,
    UNDATED_WORKBOOK_COUNT
from per_window
where DATED_WORKBOOK_COUNT > 0
  and UNDATED_WORKBOOK_COUNT > 0
