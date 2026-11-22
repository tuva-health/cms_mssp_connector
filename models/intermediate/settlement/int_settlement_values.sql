{#-
    The settlement (STLMT) workbook's Table 2, Table 3 and Table A1, typed and
    stacked, one row per cell in a lettered section.

    Nothing reads a fixed position. The sheet layouts are not yet checked
    against a delivered workbook (TUVA-158), so a value is found by what
    labels it:

      * TABLE_CODE and SECTION_CODE: the sheet, and the `[X]` code on the
        section heading (`I`, `P`, `BB`).
      * ENROLLMENT_TYPE: the row label mapped through mssp_enrollment_type;
        'total' for the lettered row's own value, whose row label is the
        section label, as int_benchmark_historical reads BNMRK; 'unmapped'
        for any other row.
      * COLUMN_PERIOD: 'BY3' or 'PY' from the column label, for the sheets
        that split a value by year (Table A1). NULL for any other column,
        such as Table 3's 'Result'.

    Deliveries are ranked, not filtered. CMS can deliver the bundle twice,
    embargoed and unembargoed, with the same workbook. The unembargoed copy
    ranks first, then one whose state is unknown, then the embargoed one;
    within each, the newest. FILE_PATH breaks any remaining tie, so exactly
    one workbook ranks first per ACO and performance year. The three tables
    come from one workbook, so ranking the stacked rows ranks the workbooks.

    IS_PLACEHOLDER marks an empty cell or CMS's '-'. 'N/A' is not a
    placeholder: on Table 3 [P] it is the result (a low-revenue ACO below
    its MSR, TUVA-159).
-#}

with source as (

    select '2'  as TABLE_CODE, * from {{ ref('stg_stlmt_table_2') }}
    union all
    select '3'  as TABLE_CODE, * from {{ ref('stg_stlmt_table_3') }}
    union all
    select 'A1' as TABLE_CODE, * from {{ ref('stg_stlmt_table_a1') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

ranked as (

    select
        source.*,
        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR
            order by
                case
                    when source.IS_EMBARGOED = false then 0
                    when source.IS_EMBARGOED is null then 1
                    else 2
                end,
                source.FILE_DATE desc nulls last,
                source.SUBMISSION_ID desc,
                source.FILE_PATH desc
        ) as SUBMISSION_RANK
    from source
    where source.SECTION_CODE is not null

)

select
    ranked.ACO_ID                                       as ACO_ID,
    ranked.PERFORMANCE_YEAR                             as PERFORMANCE_YEAR,
    ranked.SUBMISSION_ID                                as SUBMISSION_ID,
    ranked.IS_EMBARGOED                                 as IS_EMBARGOED,
    ranked.FILE_DATE                                    as FILE_DATE,
    ranked.SUBMISSION_RANK                              as SUBMISSION_RANK,
    ranked.SUBMISSION_RANK = 1                          as IS_PREFERRED_SUBMISSION,
    ranked.TABLE_CODE                                   as TABLE_CODE,
    ranked.GROUP_LABEL                                  as GROUP_LABEL,
    ranked.SECTION_CODE                                 as SECTION_CODE,
    ranked.SECTION_LABEL                                as SECTION_LABEL,
    ranked.ROW_LABEL                                    as ROW_LABEL,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE,
        case when upper(trim(ranked.ROW_LABEL)) = upper(trim(ranked.SECTION_LABEL)) then 'total' end,
        'unmapped'
    )                                                   as ENROLLMENT_TYPE,

    ranked.COLUMN_GROUP_LABEL                           as COLUMN_GROUP_LABEL,
    ranked.COLUMN_LABEL                                 as COLUMN_LABEL,

    case
        when upper(trim(ranked.COLUMN_LABEL)) = 'BY3'                  then 'BY3'
        when upper(trim(ranked.COLUMN_LABEL)) in ('PERFORMANCE YEAR', 'PY') then 'PY'
    end                                                 as COLUMN_PERIOD,

    ranked.VALUE_TEXT                                   as VALUE_TEXT,
    ranked.VALUE_NUMERIC                                as VALUE_NUMERIC,
    coalesce(trim(ranked.VALUE_TEXT), '') in ('', '-')  as IS_PLACEHOLDER,
    ranked.FILE_PATH                                    as FILE_PATH,
    ranked.DIRECTORY_NAME                               as DIRECTORY_NAME,
    ranked.FILE_NAME                                    as FILE_NAME,
    ranked.ROW_NUM                                      as ROW_NUM

from ranked

left join enrollment_type
    on upper(trim(ranked.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER
