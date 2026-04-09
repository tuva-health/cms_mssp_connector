select
    cast(PERFORMANCE_YEAR                   as {{ dbt.type_string() }})  as PERFORMANCE_YEAR,
    cast(REPORT_MONTH                       as {{ dbt.type_string() }})  as REPORT_MONTH,
    cast(CURRENT_BENE_MBI                   as {{ dbt.type_string() }})  as CURRENT_BENE_MBI,
    cast(PREVIOUS_BENE_MBI                  as {{ dbt.type_string() }})  as PREVIOUS_BENE_MBI,
    {{ try_to_cast_date('PREVIOUS_IDENTIFIER_EFFECTIVE_DATE', 'YYYYMMDD') }}
        as PREVIOUS_IDENTIFIER_EFFECTIVE_DATE,
    {{ try_to_cast_date('PREVIOUS_IDENTIFIER_OBSOLETE_DATE', 'YYYYMMDD') }}
        as PREVIOUS_IDENTIFIER_OBSOLETE_DATE,
    cast(FILE_PATH                          as {{ dbt.type_string() }})  as FILE_PATH,
    cast(DIRECTORY_NAME                     as {{ dbt.type_string() }})  as DIRECTORY_NAME,
    cast(FILE_NAME                          as {{ dbt.type_string() }})  as FILE_NAME,
    {{ try_to_cast_date('FILE_DATE') }}                                   as FILE_DATE
from {{ source('mssp_raw', 'excluded_beneficiary_mbi_xref') }}
