{#-
    Fails when a cell fct_settlement reads as a number is not one.

    The fact keeps a numeric field's VALUE_NUMERIC. A real cell that does not
    parse (a percentage, a parenthesised negative, a unit suffix) would come
    through as NULL and read as "not reported". The settlement layout is not
    yet checked against a delivered workbook (TUVA-158), so a format the
    parser does not know is reported rather than dropped. Only Table 3 [P],
    whose result is text ('N/A' for a low-revenue ACO), is exempt.
-#}

{%- set numeric_table_3_codes = [] -%}
{%- for _table, section_code, _name, kind, _status in settlement_table_3_fields() -%}
    {%- if kind == 'numeric' -%}{%- do numeric_table_3_codes.append(section_code) -%}{%- endif -%}
{%- endfor -%}

select
    FILE_PATH,
    TABLE_CODE,
    SECTION_CODE,
    ENROLLMENT_TYPE,
    COLUMN_LABEL,
    VALUE_TEXT
from {{ ref('int_settlement_values') }}
where not IS_PLACEHOLDER
  and VALUE_NUMERIC is null
  and (
        (TABLE_CODE = '2' and SECTION_CODE = 'I' and ENROLLMENT_TYPE = 'total')
     or (TABLE_CODE = '2'
         and SECTION_CODE in ('{{ settlement_table_2_type_codes() | join("', '") }}')
         and ENROLLMENT_TYPE in ('{{ settlement_enrollment_types() | join("', '") }}'))
     or (TABLE_CODE = '3' and SECTION_CODE = 'B'
         and ENROLLMENT_TYPE in ('total', '{{ settlement_enrollment_types() | join("', '") }}'))
     or (TABLE_CODE = '3'
         and SECTION_CODE in ('{{ numeric_table_3_codes | join("', '") }}')
         and ENROLLMENT_TYPE = 'total')
  )
