select *
from {{ source('mssp_raw', 'shadow_bundles_sn') }}
