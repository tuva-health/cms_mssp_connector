{#-
    The select list that pivots one settlement fact's fields out of
    int_settlement_values: one max() per field, over the cell mapped to it.
    A placeholder (a blank, a dash) is no value, so the field is NULL; a
    numeric field reads VALUE_NUMERIC and a text field VALUE_TEXT, as
    written. int_settlement_values' tests fail when a field has two cells in
    one workbook, so max() never picks between values.
-#}

{%- macro settlement_fact_pivot(fact, relation_alias) -%}
{%- for column_name, kind in settlement_fact_columns(fact) %}
    max(case when {{ relation_alias }}.FIELD_NAME = '{{ column_name }}' and not {{ relation_alias }}.IS_PLACEHOLDER
             then {{ relation_alias }}.{{ 'VALUE_TEXT' if kind == 'text' else 'VALUE_NUMERIC' }} end)
                                                        as {{ column_name }}{{ ',' if not loop.last }}
{%- endfor %}
{%- endmacro -%}
