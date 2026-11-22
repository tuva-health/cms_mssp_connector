{#-
    Fails when a per-enrollment-type section fct_settlement reads is missing
    one of the four types.

    fct_settlement reads Table 2 [A]-[H] and Table 3 [B] by enrollment type,
    and the type comes from the row label through mssp_enrollment_type. A
    label CMS spells differently maps to 'unmapped', which the fact never
    reads, so that type's column would go NULL and look like "not reported".
    The settlement layout is not yet checked against a delivered workbook
    (TUVA-158), so a section that carries some types but not all four is
    reported. Placeholder cells count: a '-' row is present, just empty.
-#}

{%- set types = settlement_enrollment_types() -%}

with per_type_sections as (

    select *
    from {{ ref('int_settlement_values') }}
    where (TABLE_CODE = '2' and SECTION_CODE in ('{{ settlement_table_2_type_codes() | join("', '") }}'))
       or (TABLE_CODE = '3' and SECTION_CODE = 'B')

)

select
    FILE_PATH,
    TABLE_CODE,
    SECTION_CODE,
    count(distinct case when ENROLLMENT_TYPE in ('{{ types | join("', '") }}') then ENROLLMENT_TYPE end)
        as MAPPED_TYPE_COUNT
from per_type_sections
group by FILE_PATH, TABLE_CODE, SECTION_CODE
having count(distinct case when ENROLLMENT_TYPE in ('{{ types | join("', '") }}') then ENROLLMENT_TYPE end) between 1 and {{ types | length - 1 }}
