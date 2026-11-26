{#-
    Fails when a settlement workbook lacks the cell for a field.

    Every field of macros/settlement_fields.sql, per enrollment type where it
    has one, must find its cell in every workbook: a renamed section, a
    missing type row or a moved column would otherwise leave the field NULL
    and read as "CMS left it blank". A blank cell is present; only an absent
    one fails.

    Every delivery is checked, not only the preferred one.
-#}

with workbooks as (

    select distinct FILE_PATH
    from {{ ref('int_settlement_values') }}

),

field_map as (

    {{ settlement_field_map() }}

),

expected as (

    select
        workbooks.FILE_PATH,
        field_map.FACT,
        field_map.FIELD_NAME,
        field_map.ENROLLMENT_TYPE
    from workbooks
    cross join field_map

),

found as (

    select distinct FILE_PATH, FACT, FIELD_NAME, ENROLLMENT_TYPE
    from {{ ref('int_settlement_values') }}
    where FIELD_NAME is not null

)

select expected.*
from expected
left join found
    on expected.FILE_PATH = found.FILE_PATH
   and expected.FACT = found.FACT
   and expected.FIELD_NAME = found.FIELD_NAME
   and expected.ENROLLMENT_TYPE = found.ENROLLMENT_TYPE
where found.FILE_PATH is null
