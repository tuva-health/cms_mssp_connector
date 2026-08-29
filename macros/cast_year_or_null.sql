{#-
    Casts a text column holding a four-digit calendar year to an integer,
    yielding NULL for anything else.

    PERFORMANCE_YEAR and BENCHMARK_YEAR arrive as VARCHAR from the file path and
    file name. BENCHMARK_YEAR is NULL for the BNMRK and QEXPU families, and a
    file whose name carries no parseable year token leaves either column NULL or
    holding a fragment, so the cast has to tolerate non-years rather than raise.
-#}

{%- macro cast_year_or_null(column_name) -%}

    {{ return(adapter.dispatch('cast_year_or_null')(column_name)) }}

{%- endmacro -%}

{#-
    The pattern guard makes the cast itself safe, so DuckDB, Postgres and
    Redshift all share the default implementation.
-#}
{%- macro default__cast_year_or_null(column_name) -%}

    case
      when {{ column_name }} similar to '[0-9]{4}'
      then cast( {{ column_name }} as {{ dbt.type_int() }} )
      else cast( null as {{ dbt.type_int() }} )
    end

{%- endmacro -%}

{#-
    Snowflake has no SIMILAR TO; REGEXP_LIKE is implicitly anchored there.
-#}
{%- macro snowflake__cast_year_or_null(column_name) -%}

    case
      when regexp_like( {{ column_name }}, '[0-9]{4}' )
      then cast( {{ column_name }} as {{ dbt.type_int() }} )
      else cast( null as {{ dbt.type_int() }} )
    end

{%- endmacro -%}

{%- macro bigquery__cast_year_or_null(column_name) -%}

    case
      when regexp_contains( {{ column_name }}, r'^[0-9]{4}$' )
      then safe_cast( {{ column_name }} as {{ dbt.type_int() }} )
      else cast( null as {{ dbt.type_int() }} )
    end

{%- endmacro -%}
