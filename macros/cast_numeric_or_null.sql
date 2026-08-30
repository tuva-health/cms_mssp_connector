{#-
    Casts a text column to numeric, yielding NULL — never an error — when the
    value is not a number.

    The sectioned CMS workbooks (BNMRK / AEXPU / QEXPU) carry every worksheet
    cell verbatim in a single VARCHAR column, so figures share that column with
    '-' (CMS's "not applicable"), '', 'N/A', percentages, date ranges and free
    text. A bare cast raises on all of those on DuckDB and Snowflake alike,
    which is why cast_numeric() cannot be used directly here.

    Precision and scale are chosen against what these workbooks actually hold,
    not from habit. The widest integer part observed across a full delivery set
    is 8 digits; the deepest fraction is 17 decimal places, and a non-trivial
    number of trend and county weights sit at exactly that depth. Excel stores
    these as doubles, which round-trip in at most 17 significant digits, so the
    scale a value needs is (its leading zeros after the point) + 17. The default
    numeric(38,24) therefore leaves 14 integer digits — six orders of magnitude
    above anything observed, and ample for a national aggregate in dollars and
    cents — while carrying a weight down to a magnitude of 1e-7 without losing
    a digit. cast_numeric()'s numeric(38,2) would round most of these cells and
    destroy every risk ratio, which is why this macro exists.

    Known divergences between the branches below, none of them reachable from
    CMS-issued values but recorded rather than hidden:

      * scientific notation ('1e5') and digit separators ('1_000') parse on
        DuckDB and Snowflake but yield NULL on the default branch, whose guard
        deliberately accepts only plain decimal literals it can prove will fit;
      * '1_000' parses on DuckDB and yields NULL on Snowflake, a disagreement
        inside the primary adapter pair itself. Left alone: no spreadsheet cell
        arrives that way, and engineering around it would cost more clarity
        than it buys.
-#}

{%- macro cast_numeric_or_null(column_name, precision=38, scale=24) -%}

    {{ return(adapter.dispatch('cast_numeric_or_null')(column_name, precision, scale)) }}

{%- endmacro -%}

{#-
    Postgres and Redshift have no TRY_CAST, so they fall through to the default
    implementation, which has to guard the cast rather than catch its failure.

    The guard bounds the integer part to (precision - scale) digits and rejects
    exponents outright, so every literal it admits is one the following cast can
    hold: there is no input for which this branch raises. An unbounded guard
    would not be enough — '1e400' is six characters and overflows any precision.

    TRIM strips spaces only, so tabs, newlines and the other whitespace DuckDB
    and Snowflake tolerate around a number are folded to spaces first. That
    matters because the upstream pipeline normalises whitespace in labels but
    deliberately leaves it untouched in values, so a wrapped worksheet cell
    arrives here raw.
-#}
{%- macro default__cast_numeric_or_null(column_name, precision, scale) -%}
{%- set normalized -%}
trim(translate( {{ column_name }} , chr(9) || chr(10) || chr(11) || chr(12) || chr(13), '     '))
{%- endset -%}

    case
      when {{ normalized }} similar to '[+-]?([0-9]{1,{{ precision - scale }}}([.][0-9]*)?|[.][0-9]+)'
      then cast( {{ normalized }} as numeric({{ precision }},{{ scale }}) )
      else cast( null as numeric({{ precision }},{{ scale }}) )
    end

{%- endmacro -%}

{%- macro duckdb__cast_numeric_or_null(column_name, precision, scale) -%}

    try_cast( {{ column_name }} as decimal({{ precision }},{{ scale }}) )

{%- endmacro -%}

{%- macro snowflake__cast_numeric_or_null(column_name, precision, scale) -%}

    try_cast( {{ column_name }} as numeric({{ precision }},{{ scale }}) )

{%- endmacro -%}

{#-
    BigQuery ignores precision and scale: CAST does not accept a parameterized
    type there, so the only choices are NUMERIC, whose scale is fixed at 9 and
    would round these weights, and BIGNUMERIC, whose fixed (76,38) is strictly
    wider than anything this macro is asked for. The arguments stay in the
    signature because adapter.dispatch passes them; they are deliberately unused.
-#}
{%- macro bigquery__cast_numeric_or_null(column_name, precision, scale) -%}

    safe_cast( {{ column_name }} as bignumeric )

{%- endmacro -%}
