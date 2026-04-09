select
    * exclude (FILE_DATE),
    {{ try_to_cast_date('FILE_DATE') }} as FILE_DATE
from {{ source('mssp_raw', 'mcqm_dm_001ssp') }}
