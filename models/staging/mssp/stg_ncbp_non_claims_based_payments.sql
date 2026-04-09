select *
from {{ source('mssp_raw', 'ncbp_non_claims_based_payments') }}
