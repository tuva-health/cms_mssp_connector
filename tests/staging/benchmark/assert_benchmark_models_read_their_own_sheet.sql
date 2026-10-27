{#-
    Binds every benchmark staging model to the worksheet it is supposed to read.

    Every other test on these twenty models is schema-shaped: all twenty raw
    tables share one column contract, so a model pointed at the wrong sheet
    still passes not_null, the grain test and the VALUE_NUMERIC tests. This one
    asserts content — each model must contain at least one row carrying a
    structural marker that no other benchmark model can produce.

    A marker is (family predicate) AND (a label unique to that sheet within the
    family). The family predicate comes from lineage alone: AEXPU ships one
    workbook per benchmark year and is the only family with BENCHMARK_YEAR
    populated; BNMRK deliveries are not periodic, so PERIOD repeats
    SUBMISSION_ID; QEXPU carries a quarter label there instead. The labels are
    CMS worksheet headings, identical for every ACO — never values.

    BNMRK Tables 3 and 4 are the one pair with no distinguishing label at all:
    same row labels, same column labels, no section or group headings. They are
    separated by magnitude instead, which is a property of the sheets rather
    than of any ACO — Table 3 holds expenditure truncation thresholds, which are
    dollar amounts, and Table 4 holds risk score renormalization factors, which
    are dimensionless multipliers near 1.

    Empty is not failure. A model whose sheet is legitimately absent from a
    delivery — BNMRK Table 6 before the June submission, AEXPU Tables 1A and 4A
    for BY3 — has no rows and is skipped, matching how every other test on these
    models behaves.
-#}

{%- set benchmark_delivery = "BENCHMARK_YEAR is null and PERIOD = SUBMISSION_ID" -%}
{%- set annual_delivery    = "BENCHMARK_YEAR is not null" -%}
{%- set quarterly_delivery = "BENCHMARK_YEAR is null and PERIOD <> SUBMISSION_ID" -%}

{%- set sheet_markers = {
    'stg_bnmrk_table_1':
        benchmark_delivery ~ " and SECTION_LABEL = 'CMS-HCC Risk Ratio'",
    'stg_bnmrk_table_1a':
        benchmark_delivery ~ " and SECTION_LABEL = 'Regional Adjustment Offset Factor'",
    'stg_bnmrk_table_1b':
        benchmark_delivery ~ " and SECTION_LABEL = 'Proration Factor'",
    'stg_bnmrk_table_1c':
        benchmark_delivery ~ " and SECTION_LABEL = 'Health Equity Benchmark Adjustment Scaler ($)'",
    'stg_bnmrk_table_2':
        benchmark_delivery ~ " and SECTION_LABEL = 'National Expenditure Trend Factor'",
    'stg_bnmrk_table_3':
        benchmark_delivery ~ " and SECTION_LABEL is null and COLUMN_LABEL = 'BY1' and VALUE_NUMERIC >= 1000",
    'stg_bnmrk_table_4':
        benchmark_delivery ~ " and SECTION_LABEL is null and COLUMN_LABEL = 'BY1' and VALUE_NUMERIC < 100",
    'stg_bnmrk_table_5':
        benchmark_delivery ~ " and COLUMN_LABEL = 'Percentage Weight Used to Calculate Regional Adjustment'",
    'stg_bnmrk_table_6':
        benchmark_delivery ~ " and SECTION_LABEL = 'ACPT'",
    'stg_bnmrk_parameters':
        benchmark_delivery ~ " and COLUMN_LABEL = 'VALUE' and SECTION_LABEL = 'Benchmark Year Weights'",
    'stg_aexpu_table_1':
        annual_delivery ~ " and SECTION_LABEL = 'Component Expenditures per Assigned Beneficiary'",
    'stg_aexpu_table_1a':
        annual_delivery ~ " and SECTION_LABEL = 'Component Expenditures per Assigned Beneficiary, Excluding COVID-19 Episodes'",
    'stg_aexpu_table_3':
        annual_delivery ~ " and SECTION_LABEL = 'Number of SNF Stays'",
    'stg_aexpu_table_4':
        annual_delivery ~ " and SECTION_LABEL = 'Person Years among Assigned Beneficiaries with Truncated Expenditures by Medicare Enrollment Type'",
    'stg_aexpu_table_4a':
        annual_delivery ~ " and SECTION_LABEL = 'Person Years among Assigned Beneficiaries with Truncated Expenditures by Medicare Enrollment Type, Excluding COVID-19 Episodes'",
    'stg_aexpu_parameters':
        annual_delivery ~ " and COLUMN_LABEL = 'VALUE'",
    'stg_qexpu_table_1':
        quarterly_delivery ~ " and SECTION_LABEL = 'Component Expenditures per Assigned Beneficiary'",
    'stg_qexpu_table_2':
        quarterly_delivery ~ " and SECTION_LABEL = 'Regional Expenditures ($)'",
    'stg_qexpu_table_3':
        quarterly_delivery ~ " and SECTION_LABEL = 'Number of SNF Stays'",
    'stg_qexpu_parameters':
        quarterly_delivery ~ " and COLUMN_LABEL = 'VALUE'"
} -%}

with sheet_marker_counts as (
{% for model_name, marker in sheet_markers.items() %}
    select
        '{{ model_name }}'                                        as model_name,
        count(*)                                                  as row_count,
        sum(case when {{ marker }} then 1 else 0 end)              as marker_row_count
    from {{ ref(model_name) }}
{%- if not loop.last %}

    union all
{% endif %}
{%- endfor %}

)

select
    model_name,
    row_count,
    marker_row_count
from sheet_marker_counts
where row_count > 0
  and marker_row_count = 0
