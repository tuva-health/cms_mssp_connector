select
    cast(A              as {{ dbt.type_string() }})  as A,
    cast(PERIOD_COLUMN  as {{ dbt.type_string() }})  as PERIOD_COLUMN,
    cast(VALUE          as {{ dbt.type_string() }})  as VALUE,
    cast(FILE_PATH      as {{ dbt.type_string() }})  as FILE_PATH,
    cast(DIRECTORY_NAME as {{ dbt.type_string() }})  as DIRECTORY_NAME,
    cast(FILE_NAME      as {{ dbt.type_string() }})  as FILE_NAME,
    {{ try_to_cast_date('FILE_DATE') }}               as FILE_DATE,
    cast(PERIOD         as {{ dbt.type_string() }})  as PERIOD
from {{ source('mssp_raw', 'expu_table_2') }}
