{#-
    Casts a numeric expression to a 64-bit binary float.

    The benchmark calculation is a chain of ratios and products, and every
    figure entering it arrives as `numeric(38,24)` from `cast_numeric_or_null`.
    Fixed-point arithmetic derives the result's scale from the operands rather
    than from what the value needs, and at this width that goes wrong in two
    different ways.

    Multiplying two of them overflows. DuckDB refuses outright —
    `decimal(38,24) * decimal(38,24)` raises `Out of Range Error: Needed scale
    48 to accurately represent the multiplication result`. Snowflake's rule is
    `S = min(S1 + S2, max(S1, S2, 12))` with total precision capped at 38, so
    the same product is silently truncated to fit instead.

    Dividing them yields a scale nobody chose. Snowflake's rule is
    `S = max(S1, min(S1 + 6, 12))`, so a quotient of two low-scale operands —
    `2 / 3`, the weights in `[K]` — comes back with six fractional digits.

    Doing the arithmetic in binary floating point instead is not a compromise
    made for the warehouse's convenience — it is what the source data already
    is. Excel stores every one of these cells as a double, and the reference
    implementation converts to Python `float` before it computes. Casting back
    to double at the point of use reproduces those operations bit for bit
    rather than approximately.

    Why this cannot just be `cast(x as {{ dbt.type_float() }})`: on DuckDB
    `float` is `REAL`, four bytes — `cast(1.0852658864540152 as float)` comes
    back as 1.085265874862671, wrong from the eighth significant digit, which
    would destroy the very precision this macro exists to protect. `float` is 64-bit
    on Snowflake, Postgres, Redshift and BigQuery, so only DuckDB needs its own
    branch, and it gets `double`. The two spellings are not interchangeable in
    the other direction either: `double` alone is not a type name on Postgres
    or Redshift, which want `double precision`.
-#}

{%- macro to_double(column_name) -%}

    {{ return(adapter.dispatch('to_double')(column_name)) }}

{%- endmacro -%}

{%- macro default__to_double(column_name) -%}

    cast( {{ column_name }} as {{ dbt.type_float() }} )

{%- endmacro -%}

{%- macro duckdb__to_double(column_name) -%}

    cast( {{ column_name }} as double )

{%- endmacro -%}
