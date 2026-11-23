{#-
    The settlement (STLMT) workbook's Tables 1, 2, 3, A1 and A2, typed and
    stacked, one row per cell, each mapped to the field it is.

    Nothing reads a fixed position. A cell is found by what labels it (see
    macros/settlement_fields.sql):

      * TABLE_CODE: the sheet.
      * SECTION_KEY: the row's `[X]` code; on Table A2, which has no codes,
        its block (CMS_HCC or DEMOGRAPHIC, from BLOCK_LABEL); NULL on Table
        A1, whose letters label its columns.
      * ROW_KIND: CODE, DETAIL or TOTAL, as the pipeline writes it.
      * ENROLLMENT_TYPE: a DETAIL row's label mapped through
        mssp_enrollment_type; 'weighted_average' for Table A1's Weighted
        Average row; 'unmapped' for any other DETAIL row. 'total' on a CODE
        or TOTAL row: the ACO's own value.
      * COLUMN_KEY: Table A1's column letter (COLUMN_CODE); elsewhere the
        column's period from its label: BY1, BY2, BY3, PY ('PY' or
        'Performance Year'), BENCHMARK_PERIOD (Table 2's 'Benchmark
        Period') or BENCHMARK (Table 1's 'Benchmark'). NULL for any other.

    FACT, FIELD_NAME and FIELD_KIND name the field a cell is, from
    settlement_field_map(); NULL on a cell no settlement fact reads.

    Deliveries are ranked, not filtered. CMS can deliver the bundle twice,
    embargoed and unembargoed, with the same workbook. The unembargoed copy
    ranks first, then one whose state is unknown, then the embargoed one;
    within each, the newest. FILE_PATH breaks any remaining tie, so exactly
    one workbook ranks first per ACO and performance year. The tables come
    from one workbook, so ranking the stacked rows ranks the workbooks.

    IS_PLACEHOLDER marks a cell CMS left blank: empty, or a dash (the en dash
    U+2013 CMS writes, or a hyphen). Y/N and other text are values.
-#}

with source as (

    select '1'  as TABLE_CODE, * from {{ ref('stg_stlmt_table_1') }}
    union all
    select '2'  as TABLE_CODE, * from {{ ref('stg_stlmt_table_2') }}
    union all
    select '3'  as TABLE_CODE, * from {{ ref('stg_stlmt_table_3') }}
    union all
    select 'A1' as TABLE_CODE, * from {{ ref('stg_stlmt_table_a1') }}
    union all
    select 'A2' as TABLE_CODE, * from {{ ref('stg_stlmt_table_a2') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

field_map as (

    {{ settlement_field_map() }}

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

),

keyed as (

    select
        ranked.*,

        case
            when ranked.TABLE_CODE = 'A2' then
                case
                    when upper(ranked.BLOCK_LABEL) like '%MEAN CMS-HCC RISK SCORES%'     then 'CMS_HCC'
                    when upper(ranked.BLOCK_LABEL) like '%MEAN DEMOGRAPHIC RISK SCORES%' then 'DEMOGRAPHIC'
                end
            else ranked.SECTION_CODE
        end                                             as SECTION_KEY,

        case
            when ranked.ROW_KIND in ('CODE', 'TOTAL') then 'total'
            when ranked.TABLE_CODE = 'A1'
             and upper(trim(ranked.ROW_LABEL)) = 'WEIGHTED AVERAGE' then 'weighted_average'
            else coalesce(enrollment_type.ENROLLMENT_TYPE, 'unmapped')
        end                                             as ENROLLMENT_TYPE,

        case
            when ranked.COLUMN_CODE is not null then upper(trim(ranked.COLUMN_CODE))
            when upper(trim(ranked.COLUMN_LABEL)) in ('BY1', 'BY2', 'BY3')
                then upper(trim(ranked.COLUMN_LABEL))
            when upper(trim(ranked.COLUMN_LABEL)) in ('PY', 'PERFORMANCE YEAR') then 'PY'
            when upper(trim(ranked.COLUMN_LABEL)) = 'BENCHMARK PERIOD'          then 'BENCHMARK_PERIOD'
            when upper(trim(ranked.COLUMN_LABEL)) = 'BENCHMARK'                 then 'BENCHMARK'
        end                                             as COLUMN_KEY

    from ranked

    left join enrollment_type
        on upper(trim(ranked.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER

)

select
    keyed.ACO_ID                                        as ACO_ID,
    keyed.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    keyed.SUBMISSION_ID                                 as SUBMISSION_ID,
    keyed.IS_EMBARGOED                                  as IS_EMBARGOED,
    keyed.FILE_DATE                                     as FILE_DATE,
    keyed.SUBMISSION_RANK                               as SUBMISSION_RANK,
    keyed.SUBMISSION_RANK = 1                           as IS_PREFERRED_SUBMISSION,
    keyed.TABLE_CODE                                    as TABLE_CODE,
    keyed.BLOCK_LABEL                                   as BLOCK_LABEL,
    keyed.GROUP_LABEL                                   as GROUP_LABEL,
    keyed.SECTION_CODE                                  as SECTION_CODE,
    keyed.SECTION_KEY                                   as SECTION_KEY,
    keyed.SECTION_LABEL                                 as SECTION_LABEL,
    keyed.ROW_LABEL                                     as ROW_LABEL,
    keyed.ROW_KIND                                      as ROW_KIND,
    keyed.ENROLLMENT_TYPE                               as ENROLLMENT_TYPE,
    keyed.COLUMN_GROUP_LABEL                            as COLUMN_GROUP_LABEL,
    keyed.COLUMN_CODE                                   as COLUMN_CODE,
    keyed.COLUMN_LABEL                                  as COLUMN_LABEL,
    keyed.COLUMN_KEY                                    as COLUMN_KEY,
    field_map.FACT                                      as FACT,
    field_map.FIELD_NAME                                as FIELD_NAME,
    field_map.FIELD_KIND                                as FIELD_KIND,
    keyed.VALUE_TEXT                                    as VALUE_TEXT,
    keyed.VALUE_NUMERIC                                 as VALUE_NUMERIC,
    coalesce(trim(keyed.VALUE_TEXT), '') in ('', '-', '–') as IS_PLACEHOLDER,
    keyed.FILE_PATH                                     as FILE_PATH,
    keyed.DIRECTORY_NAME                                as DIRECTORY_NAME,
    keyed.FILE_NAME                                     as FILE_NAME,
    keyed.ROW_NUM                                       as ROW_NUM

from keyed

left join field_map
    on keyed.TABLE_CODE = field_map.TABLE_CODE
   and coalesce(keyed.SECTION_KEY, '') = coalesce(field_map.SECTION_KEY, '')
   and keyed.ROW_KIND = field_map.ROW_KIND
   and keyed.ENROLLMENT_TYPE = field_map.ENROLLMENT_TYPE
   and keyed.COLUMN_KEY = field_map.COLUMN_KEY
