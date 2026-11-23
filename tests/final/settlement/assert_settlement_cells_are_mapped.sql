{#-
    Fails when a settlement workbook cell holds a value no field reads.

    Each field is mapped to its column explicitly (macros/settlement_fields.sql):
    Table 2 [A] in Benchmark Period, [B] in both Benchmark Period (BY3) and
    Performance Year, the rest in Performance Year, and so on. A value in a
    column, row or block the map does not expect would be silently dropped;
    this test makes it loud, so a changed layout gets a mapping, not a
    guess. Blank cells pass.

    Scope: every cell of Tables 2, 3, A1 and A2, and Table 1's
    per-enrollment-type rows (its single-valued rows are not read). An
    enrollment-type label the mssp_enrollment_type seed does not know shows
    here as 'unmapped'.

    Every delivery is checked, not only the preferred one.
-#}

select
    FILE_PATH,
    TABLE_CODE,
    SECTION_KEY,
    ROW_KIND,
    ROW_LABEL,
    ENROLLMENT_TYPE,
    COLUMN_LABEL,
    COLUMN_KEY
from {{ ref('int_settlement_values') }}
where FIELD_NAME is null
  and not IS_PLACEHOLDER
  and (
        TABLE_CODE in ('2', '3', 'A1', 'A2')
     or (TABLE_CODE = '1' and ROW_KIND = 'DETAIL')
  )
