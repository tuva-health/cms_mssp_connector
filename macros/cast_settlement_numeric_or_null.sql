{#-
    cast_numeric_or_null for the settlement (STLMT) workbook: the same cast,
    after removing thousands separators.

    The pipeline keeps every cell verbatim, and the settlement's dollar
    figures can arrive formatted, as '-1,234' (TUVA-158). cast_numeric_or_null
    reads that as not a number and yields NULL, which would drop a payment
    from the fact. Commas are removed and nothing else: '-', 'N/A', '' and
    percentages still yield NULL, and VALUE_TEXT keeps the original.

    Only the settlement models use this. The benchmark families have no
    formatted figures, and their staging tests pin cast_numeric_or_null as is.
-#}

{%- macro cast_settlement_numeric_or_null(column_name) -%}

    {{ cast_numeric_or_null("replace(" ~ column_name ~ ", ',', '')") }}

{%- endmacro -%}
