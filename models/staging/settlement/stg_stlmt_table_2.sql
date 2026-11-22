select
    cast(ROW_NUM                            as {{ dbt.type_bigint() }})  as ROW_NUM,
    cast(GROUP_LABEL                        as {{ dbt.type_string() }})  as GROUP_LABEL,
    cast(SECTION_CODE                       as {{ dbt.type_string() }})  as SECTION_CODE,
    cast(SECTION_LABEL                      as {{ dbt.type_string() }})  as SECTION_LABEL,
    cast(ROW_LABEL                          as {{ dbt.type_string() }})  as ROW_LABEL,
    cast(COLUMN_GROUP_LABEL                 as {{ dbt.type_string() }})  as COLUMN_GROUP_LABEL,
    cast(COLUMN_LABEL                       as {{ dbt.type_string() }})  as COLUMN_LABEL,
    cast(VALUE_TEXT                         as {{ dbt.type_string() }})  as VALUE_TEXT,
    {{ cast_settlement_numeric_or_null('cast(VALUE_TEXT as ' ~ dbt.type_string() ~ ')') }}
        as VALUE_NUMERIC,
    cast(FILE_PATH                          as {{ dbt.type_string() }})  as FILE_PATH,
    cast(DIRECTORY_NAME                     as {{ dbt.type_string() }})  as DIRECTORY_NAME,
    cast(FILE_NAME                          as {{ dbt.type_string() }})  as FILE_NAME,
    {{ try_to_cast_date('cast(FILE_DATE as ' ~ dbt.type_string() ~ ')') }}
        as FILE_DATE,
    cast(ACO_ID                             as {{ dbt.type_string() }})  as ACO_ID,
    {{ cast_year_or_null('PERFORMANCE_YEAR') }}                          as PERFORMANCE_YEAR,
    cast(SUBMISSION_ID                      as {{ dbt.type_string() }})  as SUBMISSION_ID,
    cast(PERIOD                             as {{ dbt.type_string() }})  as PERIOD,
    cast(IS_EMBARGOED                       as {{ dbt.type_boolean() }}) as IS_EMBARGOED
from {{ source('mssp_raw', 'stlmt_table_2') }}
