{#-
    True when two settlement figures differ by more than float rounding:
    by more than one part in a billion of the larger, or of 1 when both are
    smaller. The workbook stores doubles and the pipeline keeps up to
    seventeen significant digits, so an identity CMS's footnotes state holds
    well inside that. NULL (not compared) when either side is NULL.
-#}

{%- macro settlement_values_differ(left, right) -%}
    abs(cast({{ left }} as {{ dbt.type_float() }}) - cast({{ right }} as {{ dbt.type_float() }}))
        > 1e-9 * greatest(
            1.0,
            abs(cast({{ left }} as {{ dbt.type_float() }})),
            abs(cast({{ right }} as {{ dbt.type_float() }}))
        )
{%- endmacro -%}
