{#-
    QEXPU Table 2, typed — the source of [D], [E], [G] and [H].

    This sheet is the one place where the reporting period is a *column* rather
    than a property of the workbook: one 'Benchmark Year 3' column sits beside
    Q1..Q4, and CMS ships all four quarter columns from the first quarter of the
    year onward, leaving the ones it has not reported yet empty. So the column
    is split into PERIOD_TYPE plus QUARTER_NUM, and IS_LATEST_QUARTER marks the
    highest-numbered quarter that actually carries a number.

    "Carries a number" is VALUE_NUMERIC is not null, which also excludes CMS's
    '-' not-applicable marker.

    The scope is (FILE_PATH, METRIC), not FILE_PATH alone. One workbook is one
    delivery of one quarter, so a later delivery must not decide which quarter
    is current inside an earlier one — but the three sections of this sheet are
    also populated independently, and pooling them lets one section that has
    run ahead drag the other two onto a quarter they have no data for. [E] and
    [H] would then return four rows of NULL while the values CMS actually
    reported sat unflagged.
-#}

with source as (

    select * from {{ ref('stg_qexpu_table_2') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

typed as (

    select
        source.*,

        case
            when upper(trim(source.SECTION_LABEL)) = 'REGIONAL EXPENDITURES ($)'
                then 'regional_expenditure'
            when upper(trim(source.SECTION_LABEL)) = 'NATIONAL WEIGHT'
                then 'national_weight'
            when upper(trim(source.SECTION_LABEL)) = 'REGIONAL WEIGHT'
                then 'regional_weight'
            else 'unmapped'
        end as METRIC,

        case
            when upper(trim(source.COLUMN_LABEL)) = 'BENCHMARK YEAR 3'
                then 'benchmark_year_3'
            when upper(trim(source.COLUMN_LABEL)) in ('Q1', 'Q2', 'Q3', 'Q4')
                then 'quarter'
            else 'unmapped'
        end as PERIOD_TYPE,

        case
            when upper(trim(source.COLUMN_LABEL)) in ('Q1', 'Q2', 'Q3', 'Q4')
            then cast(substring(upper(trim(source.COLUMN_LABEL)), 2, 1) as {{ dbt.type_int() }})
        end as QUARTER_NUM,

        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR, source.PERIOD
            order by source.FILE_DATE desc nulls last, source.SUBMISSION_ID desc, source.FILE_PATH desc
        ) as SUBMISSION_RANK

    from source

),

latest_quarter as (

    select
        FILE_PATH,
        METRIC,
        max(QUARTER_NUM) as LATEST_QUARTER_NUM
    from typed
    where PERIOD_TYPE = 'quarter'
      and VALUE_NUMERIC is not null
    group by FILE_PATH, METRIC

)

select
    typed.ACO_ID                                        as ACO_ID,
    typed.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    typed.PERIOD                                        as PERIOD,
    typed.SUBMISSION_ID                                 as SUBMISSION_ID,
    typed.FILE_DATE                                     as FILE_DATE,
    typed.SUBMISSION_RANK                               as SUBMISSION_RANK,
    typed.SUBMISSION_RANK = 1                           as IS_LATEST_SUBMISSION,
    typed.SECTION_LABEL                                 as SECTION_LABEL,
    typed.METRIC                                        as METRIC,
    typed.ROW_LABEL                                     as ROW_LABEL,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE,
        case when typed.ROW_LABEL = typed.SECTION_LABEL then 'total' end,
        'unmapped'
    )                                                   as ENROLLMENT_TYPE,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE_LABEL,
        case when typed.ROW_LABEL = typed.SECTION_LABEL then 'Total' end,
        'Unmapped'
    )                                                   as ENROLLMENT_TYPE_LABEL,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE_SORT,
        case when typed.ROW_LABEL = typed.SECTION_LABEL then 9 end,
        99
    )                                                   as ENROLLMENT_TYPE_SORT,

    typed.COLUMN_LABEL                                  as COLUMN_LABEL,
    typed.PERIOD_TYPE                                   as PERIOD_TYPE,
    typed.QUARTER_NUM                                   as QUARTER_NUM,

    coalesce(
        typed.PERIOD_TYPE = 'quarter'
            and typed.QUARTER_NUM = latest_quarter.LATEST_QUARTER_NUM,
        false
    )                                                   as IS_LATEST_QUARTER,

    typed.VALUE_TEXT                                    as VALUE_TEXT,
    typed.VALUE_NUMERIC                                 as VALUE_NUMERIC,
    typed.FILE_PATH                                     as FILE_PATH,
    typed.DIRECTORY_NAME                                as DIRECTORY_NAME,
    typed.FILE_NAME                                     as FILE_NAME,
    typed.ROW_NUM                                       as ROW_NUM

from typed

left join enrollment_type
    on upper(trim(typed.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER

left join latest_quarter
    on typed.FILE_PATH = latest_quarter.FILE_PATH
   and typed.METRIC = latest_quarter.METRIC
