{#-
    cast_numeric_or_null for the settlement (STLMT) workbook: the same cast,
    after removing thousands separators.

    The pipeline keeps every cell verbatim. A dollar figure can arrive
    formatted ('-1,234'), and a large one in E-notation ('1.25E8', which
    the sheet reader writes for some real cells). Commas are removed and
    nothing else; cast_numeric_or_null reads E-notation on DuckDB and
    Snowflake (its default branch does not, see that macro). CMS's blank,
    the en dash U+2013, and '-', '', 'N/A' and text still yield NULL, and
    VALUE_TEXT keeps the original.

    Only the settlement models use this. The benchmark families have no
    formatted figures, and their staging tests pin cast_numeric_or_null as is.
-#}

{%- macro cast_settlement_numeric_or_null(column_name) -%}

    {{ cast_numeric_or_null("replace(" ~ column_name ~ ", ',', '')") }}

{%- endmacro -%}
