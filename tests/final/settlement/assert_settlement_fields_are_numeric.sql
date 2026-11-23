{#-
    Fails when a cell a settlement fact reads as a number is not one.

    A numeric field keeps VALUE_NUMERIC. A real cell that does not parse (a
    percentage, a parenthesised negative, a unit suffix) would come through
    as NULL and read as "not reported", so a format the parser does not know
    is reported rather than dropped. Blanks (an en dash, a hyphen, empty) are
    no value and pass. Text fields (Y/N flags, results) are exempt.

    Every delivery is checked, not only the preferred one.
-#}

select
    FILE_PATH,
    TABLE_CODE,
    SECTION_CODE,
    ENROLLMENT_TYPE,
    COLUMN_LABEL,
    FIELD_NAME,
    VALUE_TEXT
from {{ ref('int_settlement_values') }}
where FIELD_KIND = 'numeric'
  and not IS_PLACEHOLDER
  and VALUE_NUMERIC is null
