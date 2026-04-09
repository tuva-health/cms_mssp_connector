select
    cast(MBI                as {{ dbt.type_string() }})  as MBI,
    cast(HICN               as {{ dbt.type_string() }})  as HICN,
    cast(FIRSTNAME          as {{ dbt.type_string() }})  as FIRSTNAME,
    cast(MIDDLENAME         as {{ dbt.type_string() }})  as MIDDLENAME,
    cast(LASTNAME           as {{ dbt.type_string() }})  as LASTNAME,
    cast(DOB                as {{ dbt.type_string() }})  as DOB,
    cast(GENDER             as {{ dbt.type_string() }})  as GENDER,
    cast(BENEEXCREASONS     as {{ dbt.type_string() }})  as BENEEXCREASONS,
    cast(HEADERCODE         as {{ dbt.type_string() }})  as HEADERCODE,
    cast(FILECREATIONDATE   as {{ dbt.type_string() }})  as FILECREATIONDATE,
    cast(PERFORMANCEYEAR    as {{ dbt.type_string() }})  as PERFORMANCEYEAR,
    cast(REPORTMONTH        as {{ dbt.type_string() }})  as REPORTMONTH,
    cast(FILE_PATH          as {{ dbt.type_string() }})  as FILE_PATH,
    cast(DIRECTORY_NAME     as {{ dbt.type_string() }})  as DIRECTORY_NAME,
    cast(FILE_NAME          as {{ dbt.type_string() }})  as FILE_NAME,
    {{ try_to_cast_date('FILE_DATE') }}                   as FILE_DATE
from {{ source('mssp_raw', 'beneficiary_exclusions') }}
