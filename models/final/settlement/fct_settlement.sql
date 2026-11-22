{#-
    CMS's final settled result, one row per ACO and performance year, from the
    settlement (STLMT) workbook's Table 2 and Table 3.

    The workbook is read, never recomputed. When the embargoed and
    unembargoed deliveries are both present, the unembargoed one is read
    (int_settlement_values ranks them). A low-revenue ACO below its MSR can
    still share savings, at half the rate: Table 3 [P] then reads 'N/A' and
    [BB] carries the result. Both come through as written; nothing here
    infers "no savings" from savings below the MSR.

    Each field is a row's one real value: the cell across the row's value
    columns that is neither empty nor '-'. Which column CMS puts it in is not
    assumed (TUVA-158: the layout is unverified).
    assert_settlement_values_are_unambiguous fails if a row carries two, so
    max() below never picks between them.

    Column names: see macros/settlement_fields.sql. Fields the handoff pins to
    one meaning have a name; fields it names only as a range are T3_<code>
    and T2_<code>_<type>.

    Table A1 is in fct_settlement_risk.
-#}

{%- set types = settlement_enrollment_types() -%}

with preferred as (

    {#- A placeholder ('-' or empty) is no value, so it never wins max(). -#}
    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        IS_EMBARGOED,
        FILE_DATE,
        FILE_PATH,
        TABLE_CODE,
        SECTION_CODE,
        ENROLLMENT_TYPE,
        case when not IS_PLACEHOLDER then VALUE_TEXT end    as VALUE_TEXT,
        case when not IS_PLACEHOLDER then VALUE_NUMERIC end as VALUE_NUMERIC
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION

),

delivery_count as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        count(distinct FILE_PATH) as SETTLEMENT_DELIVERY_COUNT
    from {{ ref('int_settlement_values') }}
    group by ACO_ID, PERFORMANCE_YEAR

)

select
    preferred.ACO_ID                                    as ACO_ID,
    preferred.PERFORMANCE_YEAR                          as PERFORMANCE_YEAR,
    preferred.SUBMISSION_ID                             as SUBMISSION_ID,
    preferred.IS_EMBARGOED                              as IS_EMBARGOED,
    preferred.FILE_DATE                                 as FILE_DATE,
    preferred.FILE_PATH                                 as FILE_PATH,
    delivery_count.SETTLEMENT_DELIVERY_COUNT            as SETTLEMENT_DELIVERY_COUNT,

    -- Table 2
    max(case when preferred.TABLE_CODE = '2' and preferred.SECTION_CODE = 'I'
              and preferred.ENROLLMENT_TYPE = 'total'
             then preferred.VALUE_NUMERIC end)        as UPDATED_BENCHMARK,
{%- for code in settlement_table_2_type_codes() %}
{%- for type in types %}
    max(case when preferred.TABLE_CODE = '2' and preferred.SECTION_CODE = '{{ code }}'
              and preferred.ENROLLMENT_TYPE = '{{ type }}'
             then preferred.VALUE_NUMERIC end)        as T2_{{ code }}_{{ type | upper }},
{%- endfor %}
{%- endfor %}

    -- Table 3 [B], person years: the ACO total and each type.
    max(case when preferred.TABLE_CODE = '3' and preferred.SECTION_CODE = 'B'
              and preferred.ENROLLMENT_TYPE = 'total'
             then preferred.VALUE_NUMERIC end)        as PERSON_YEARS,
{%- for type in types %}
    max(case when preferred.TABLE_CODE = '3' and preferred.SECTION_CODE = 'B'
              and preferred.ENROLLMENT_TYPE = '{{ type }}'
             then preferred.VALUE_NUMERIC end)        as PERSON_YEARS_{{ type | upper }},
{%- endfor %}

    -- Table 3, ACO-level rows
{%- for table_code, section_code, column_name, kind, _status in settlement_table_3_fields() %}
    max(case when preferred.TABLE_CODE = '{{ table_code }}' and preferred.SECTION_CODE = '{{ section_code }}'
              and preferred.ENROLLMENT_TYPE = 'total'
             then preferred.{{ 'VALUE_TEXT' if kind == 'text' else 'VALUE_NUMERIC' }} end)
                                                        as {{ column_name }}{{ ',' if not loop.last }}
{%- endfor %}

from preferred

inner join delivery_count
    on preferred.ACO_ID = delivery_count.ACO_ID
   and preferred.PERFORMANCE_YEAR = delivery_count.PERFORMANCE_YEAR

group by
    preferred.ACO_ID,
    preferred.PERFORMANCE_YEAR,
    preferred.SUBMISSION_ID,
    preferred.IS_EMBARGOED,
    preferred.FILE_DATE,
    preferred.FILE_PATH,
    delivery_count.SETTLEMENT_DELIVERY_COUNT
