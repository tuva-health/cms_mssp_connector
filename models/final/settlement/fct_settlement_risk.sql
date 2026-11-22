{#-
    The settlement (STLMT) workbook's Table A1, risk adjustment: one row per
    ACO, performance year, section and enrollment type, from the preferred
    delivery, with the BY3 and performance-year values side by side.

    Tall rather than pivoted into fct_settlement: Table A1's section codes
    are not yet checked against a delivered workbook (TUVA-158), so no code
    is given a meaning here. SECTION_CODE and SECTION_LABEL say what each
    row is. Pivot into named columns once the codes are confirmed
    (TUVA-161, TUVA-162).

    Each value is the one real cell in its period's column;
    assert_settlement_values_are_unambiguous fails on two, and on a real
    cell in a column that is neither BY3 nor the performance year.
-#}

with preferred as (

    select *
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION
      and TABLE_CODE = 'A1'
      and ENROLLMENT_TYPE <> 'unmapped'

)

select
    ACO_ID                                              as ACO_ID,
    PERFORMANCE_YEAR                                    as PERFORMANCE_YEAR,
    SUBMISSION_ID                                       as SUBMISSION_ID,
    IS_EMBARGOED                                        as IS_EMBARGOED,
    FILE_PATH                                           as FILE_PATH,
    SECTION_CODE                                        as SECTION_CODE,
    max(SECTION_LABEL)                                  as SECTION_LABEL,
    ENROLLMENT_TYPE                                     as ENROLLMENT_TYPE,
    max(case when COLUMN_PERIOD = 'BY3' and not IS_PLACEHOLDER then VALUE_NUMERIC end) as BY3_VALUE,
    max(case when COLUMN_PERIOD = 'BY3' and not IS_PLACEHOLDER then VALUE_TEXT end)    as BY3_VALUE_TEXT,
    max(case when COLUMN_PERIOD = 'PY'  and not IS_PLACEHOLDER then VALUE_NUMERIC end) as PY_VALUE,
    max(case when COLUMN_PERIOD = 'PY'  and not IS_PLACEHOLDER then VALUE_TEXT end)    as PY_VALUE_TEXT
from preferred
group by
    ACO_ID,
    PERFORMANCE_YEAR,
    SUBMISSION_ID,
    IS_EMBARGOED,
    FILE_PATH,
    SECTION_CODE,
    ENROLLMENT_TYPE
