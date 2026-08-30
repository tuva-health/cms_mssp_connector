{#-
    Divides two numeric expressions in 64-bit floating point, yielding NULL —
    never an error, and never an infinity — when the denominator is zero or
    NULL.

    This is the SQL counterpart of `calculator._safe_divide` in the reference
    implementation, and it is deliberately identical in behaviour: a NULL
    numerator, a NULL denominator or a zero denominator all give NULL. Four of
    the benchmark's steps are divisions — `[C]`, `[F]`, `[O]` and `[R]` — and
    each of them can legitimately meet a missing input, because CMS omits whole
    sheets from the preliminary delivery and writes `'-'` for figures that do
    not apply. A row that cannot be divided must still exist, carrying NULL.

    Zero is checked rather than left to the adapter. Snowflake raises on
    division by zero, DuckDB returns NULL, and BigQuery raises; relying on any
    of those would make the model's behaviour an adapter detail. The guard is
    written against the double-cast denominator so that a decimal value which
    is zero only after rounding to double is caught too.

    Both operands go through `to_double` before the division; see that macro
    for why decimal division is not usable here.
-#}

{%- macro safe_divide(numerator, denominator) -%}

    case
        when {{ to_double(denominator) }} is null
             or {{ to_double(denominator) }} = 0
        then {{ to_double('null') }}
        else {{ to_double(numerator) }} / {{ to_double(denominator) }}
    end

{%- endmacro -%}
