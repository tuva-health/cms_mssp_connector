select *
from {{ source('mssp_raw', 'participants_list') }}
