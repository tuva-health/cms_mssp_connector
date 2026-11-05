{#-
    Casts a text column to a date, yielding NULL — never an error — when the
    value is not a date in the layout the caller names.

    date_format names the layout the source writes, in the spelling the
    Postgres branch below has always used: 'YYYY-MM-DD' (the default),
    'YYYYMMDD', 'MM/DD/YYYY' or 'YYYY-MM-DD HH:MI:SS'. Every branch has to read
    the layout it is given. The DuckDB and Snowflake branches once ignored it
    and cast the value as the adapter's default date text, which is ISO on
    both; the excluded-beneficiary MBI crosswalk is a fixed-width file whose
    two identifier dates cms_mssp_pipeline writes as eight-digit 'YYYYMMDD'
    text, and neither adapter accepts that shape in a plain cast (Snowflake's
    AUTO date detection takes 'YYYY-MM-DD', 'DD-MON-YYYY' and 'MM/DD/YYYY'
    only), so both columns came back NULL on every row.

    The default layout stays a plain try_cast. Its callers pass FILE_DATE,
    which the pipeline writes as a DATE and the fixture seeds load as text;
    the cast reads both, and a format-aware parser would need the text form.

    The other three layouts are guarded and then parsed, as the Postgres branch
    does: the guard is a shape check on the whole value, so a seven-digit
    fragment is NULL rather than read leniently (DuckDB's strptime accepts
    '2024011' for '%Y%m%d' and makes it New Year's Day), and the parser then
    rejects a shape that names no calendar day, such as a thirteenth month.
    DuckDB and Snowflake share the shape patterns; SIMILAR TO on DuckDB and
    REGEXP_LIKE on Snowflake both match the whole string. A date_format
    outside the four yields NULL on every adapter, as it always has on
    Postgres and Redshift.

    The BigQuery and default branches still read the adapter's default text
    whatever the layout; no adapter this project installs reaches them.
-#}

{%- macro try_to_cast_date(column_name, date_format='YYYY-MM-DD') -%}

    {{ return(adapter.dispatch('try_to_cast_date')(column_name, date_format)) }}

{%- endmacro -%}

{#-
    The three non-default layouts: the shape every value must match in full,
    DuckDB's strptime spelling of it, and Snowflake's conversion function and
    format. None for a layout the macro does not know.
-#}
{%- macro try_to_cast_date_layout(date_format) -%}

    {%- set layouts = {
        'YYYYMMDD': {
            'shape': '[0-9]{8}',
            'duckdb': '%Y%m%d',
            'snowflake_function': 'try_to_date',
            'snowflake': 'YYYYMMDD'
        },
        'MM/DD/YYYY': {
            'shape': '[0-9]{2}/[0-9]{2}/[0-9]{4}',
            'duckdb': '%m/%d/%Y',
            'snowflake_function': 'try_to_date',
            'snowflake': 'MM/DD/YYYY'
        },
        'YYYY-MM-DD HH:MI:SS': {
            'shape': '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}',
            'duckdb': '%Y-%m-%d %H:%M:%S',
            'snowflake_function': 'try_to_timestamp_ntz',
            'snowflake': 'YYYY-MM-DD HH24:MI:SS'
        }
    } -%}

    {{ return(layouts.get(date_format)) }}

{%- endmacro -%}

{%- macro bigquery__try_to_cast_date(column_name, date_format) -%}

    {%- if date_format == 'YYYY-MM-DD HH:MI:SS' -%}
    safe_cast( date( {{ column_name }} ) as date )
    {%- else -%}
    safe_cast( {{ column_name }} as date )
    {%- endif -%}

{%- endmacro -%}

{%- macro postgres__try_to_cast_date(column_name, date_format) -%}

    {%- if date_format == 'YYYY-MM-DD' -%}
    case
      when {{ column_name }} similar to '[0-9]{4}-[0-9]{2}-[0-9]{2}'
      then to_date( {{ column_name }}, 'YYYY-MM-DD')
      else date(NULL)
    end
    {%- elif date_format == 'YYYYMMDD' -%}
    case
      when {{ column_name }} similar to '[0-9]{4}[0-9]{2}[0-9]{2}'
      then to_date( {{ column_name }}, 'YYYYMMDD')
      else date(NULL)
    end
    {%- elif date_format == 'MM/DD/YYYY' -%}
    case
      when {{ column_name }} similar to '[0-9]{2}/[0-9]{2}/[0-9]{4}'
      then to_date( {{ column_name }}, 'MM/DD/YYYY')
      else date(NULL)
    end
    {%- elif date_format == 'YYYY-MM-DD HH:MI:SS' -%}
    case
      when {{ column_name }} similar to '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}'
      then to_date( {{ column_name }}, 'YYYY-MM-DD HH:MI:SS')
      else date(NULL)
    end
    {%- else -%}
    date(NULL)
    {%- endif -%}

{%- endmacro -%}

{%- macro redshift__try_to_cast_date(column_name, date_format) -%}

    {%- if date_format == 'YYYY-MM-DD' -%}
    case
      when {{ column_name }} similar to '\\d{4}-\\d{2}-\\d{2}'
      then to_date( {{ column_name }}, '%Y-%m-%d')
      else date(NULL)
    end
    {%- elif date_format == 'YYYYMMDD' -%}
    case
      when {{ column_name }} similar to '\\d{4}\\d{2}\\d{2}'
      then to_date( {{ column_name }}, '%Y%m%d')
      else date(NULL)
    end
    {%- elif date_format == 'MM/DD/YYYY' -%}
    case
      when {{ column_name }} similar to '\\d{2}/\\d{2}/\\d{4}'
      then to_date( {{ column_name }}, '%m/%d/%Y')
      else date(NULL)
    end
    {%- elif date_format == 'YYYY-MM-DD HH:MI:SS' -%}
    case
      when {{ column_name }} similar to '\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}'
      then to_date( {{ column_name }}, '%Y-%m-%d %H:%M:%S')
      else date(NULL)
    end
    {%- else -%}
    date(NULL)
    {%- endif -%}

{%- endmacro -%}

{%- macro snowflake__try_to_cast_date(column_name, date_format) -%}

    {%- if date_format == 'YYYY-MM-DD' -%}
    try_cast( {{ column_name }} as date )
    {%- else -%}
    {%- set layout = try_to_cast_date_layout(date_format) -%}
    {%- if layout is none -%}
    cast( null as date )
    {%- else -%}
    {%- set text = 'cast( ' ~ column_name ~ ' as ' ~ dbt.type_string() ~ ' )' -%}
    case
      when regexp_like( {{ text }}, '{{ layout.shape }}' )
      then cast( {{ layout.snowflake_function }}( {{ text }}, '{{ layout.snowflake }}' ) as date )
      else cast( null as date )
    end
    {%- endif -%}
    {%- endif -%}

{%- endmacro -%}

{%- macro duckdb__try_to_cast_date(column_name, date_format) -%}

    {%- if date_format == 'YYYY-MM-DD' -%}
    try_cast( {{ column_name }} as date )
    {%- else -%}
    {%- set layout = try_to_cast_date_layout(date_format) -%}
    {%- if layout is none -%}
    cast( null as date )
    {%- else -%}
    {%- set text = 'cast( ' ~ column_name ~ ' as ' ~ dbt.type_string() ~ ' )' -%}
    case
      when {{ text }} similar to '{{ layout.shape }}'
      then try_cast( try_strptime( {{ text }}, '{{ layout.duckdb }}' ) as date )
      else cast( null as date )
    end
    {%- endif -%}
    {%- endif -%}

{%- endmacro -%}

{%- macro default__try_to_cast_date(column_name, date_format) -%}

    try_cast( {{ column_name }} as date )

{%- endmacro -%}
