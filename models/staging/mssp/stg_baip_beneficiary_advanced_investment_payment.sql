select *
from {{ source('mssp_raw', 'baip_beneficiary_advanced_investment_payment') }}
