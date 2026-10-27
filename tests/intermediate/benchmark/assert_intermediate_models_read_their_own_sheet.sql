{#-
    Binds every benchmark intermediate model to the worksheet it is supposed to
    read — the intermediate counterpart of
    assert_benchmark_models_read_their_own_sheet.

    The need is sharper here than in staging. All twenty raw tables share one
    column contract, so a mispointed ref() compiles; but an intermediate model
    also *reshapes* what it reads, and the reshaping succeeds on the wrong
    sheet. Point int_expenditures_quarterly at stg_aexpu_table_1 and every
    schema test still passes, while [B] quietly returns three benchmark years'
    worth of annual figures instead of one quarter's, and [S] returns three
    values where the calculation expects one. Nothing in the model or its column
    tests can tell.

    A marker is a structural property no other benchmark sheet can produce, and
    is built only from CMS worksheet headings — identical for every ACO — and
    from lineage, never from values.

    The three BNMRK sheets carry section labels that are unique across all
    twenty sheets, so the label alone identifies them. The two Table 1 sheets
    share every section heading with each other, so they are separated the way
    the staging test separates their families: AEXPU is the only family with
    BENCHMARK_YEAR populated, and only a quarterly PERIOD parses to a
    QUARTER_NUM. Pointing the quarterly model at the annual sheet leaves
    QUARTER_NUM NULL on every row, which is exactly the mutation above.

    int_benchmark_risk_scores is the exception to "never from values", for the
    same reason its Table 4 half is in the staging test: Table 4 has no section
    or group heading and shares its row and column labels with Table 3, so the
    two are separated by magnitude, which is a property of the sheets rather
    than of any ACO. Table 4 holds risk score renormalization factors near 1
    where Table 3 holds dollar truncation thresholds, and Table 1 section [C]
    holds risk scores near 1 where section [C] of Table 2 holds regional per
    capita dollars. Both halves are bound on the BY1 column rather than BY3
    because a preliminary delivery has been observed shipping 'N/A' for the
    BY3 national mean.

    Empty is not failure. int_benchmark_acpt is legitimately empty for an ACO
    whose only delivery is the March preliminary one, and a model with no rows
    is skipped, matching how the staging test behaves.
-#}

{%- set sheet_markers = {
    'int_benchmark_historical':
        "SECTION_LABEL = 'CMS-HCC Risk Ratio'",
    'int_benchmark_trend':
        "SECTION_LABEL = 'National Expenditure Trend Factor'",
    'int_benchmark_acpt':
        "SECTION_LABEL = 'ACPT'",
    'int_benchmark_risk_scores':
        "BY_LABEL = 'BY1' and ACO_RISK_SCORE < 100 and NATIONAL_MEAN_RISK_SCORE < 100",
    'int_expenditures_annual':
        "BENCHMARK_YEAR is not null and METRIC = 'component_expenditures_per_beneficiary'",
    'int_expenditures_quarterly':
        "QUARTER_NUM is not null and METRIC = 'component_expenditures_per_beneficiary'",
    'int_expenditures_regional':
        "PERIOD_TYPE = 'benchmark_year_3' and METRIC = 'regional_expenditure'"
} -%}

with sheet_marker_counts as (
{% for model_name, marker in sheet_markers.items() %}
    select
        '{{ model_name }}'                              as MODEL_NAME,
        count(*)                                       as ROW_COUNT,
        sum(case when {{ marker }} then 1 else 0 end)   as MARKER_ROW_COUNT
    from {{ ref(model_name) }}
{%- if not loop.last %}

    union all
{% endif %}
{%- endfor %}

)

select
    MODEL_NAME,
    ROW_COUNT,
    MARKER_ROW_COUNT
from sheet_marker_counts
where ROW_COUNT > 0
  and MARKER_ROW_COUNT = 0
