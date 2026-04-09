select *
from {{ source('mssp_raw', 'provider_and_supplier_list') }}
