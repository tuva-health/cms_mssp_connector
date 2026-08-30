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

    There is one latest quarter per workbook, and it is read off the regional
    expenditure section. Which quarter is current is a property of the delivery,
    not of a section: the three sections are three headings inside one sheet of
    one workbook, written by CMS in one pass, and the reference implementation
    reads the quarter off the Regional Expenditures rows and applies it to [E],
    [G] and [H] alike.

    Anchoring rather than pooling or splitting, because the other two shapes
    each fail in a way this one cannot.

    Per-metric — each section choosing its own quarter — keeps the sections
    independent, and if one ever ran ahead [I] would silently blend a Q1
    regional factor against Q2 weights. [I] combines all three into a single
    number, so mixing quarters inside it is simply wrong.

    Workbook-wide max — the highest quarter any section has reached — fails the
    other way: a section that has run ahead drags the other two onto a quarter
    they hold no data for, and [E] and [H] come back as four rows of NULL while
    the values CMS actually reported sit unflagged.

    Anchored on the regional expenditure section, neither happens. If another
    section runs ahead it necessarily has data for the anchor quarter too, so
    nothing goes NULL and nothing mixes.

    The scope is still FILE_PATH, never wider. One workbook is one delivery of
    one quarter, and a later delivery must not decide which quarter is current
    inside an earlier one.

    One deliberate difference from the reference implementation, which is
    otherwise what this rule reproduces: find_latest_quarter_col reads the
    quarter off the ESRD row specifically, while this takes the highest quarter
    carrying a number anywhere in the section. The two agree unless ESRD is
    blank where another enrollment type is populated — in which case the
    reference would fall back to an earlier quarter and return NULLs for the
    four types that do have data, and this does not. The broader rule is kept
    for that reason, and named here so the divergence is a decision rather than
    a discrepancy.

    That the three sections advance together is an assumption about CMS, not
    something this model can enforce, so it is made checkable:
    assert_regional_metrics_agree_on_the_latest_quarter warns if they ever
    disagree.
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

    {#- One row per workbook. The anchor is the regional expenditure section;
        the weights follow it rather than each finding its own quarter. -#}
    select
        FILE_PATH,
        max(QUARTER_NUM) as LATEST_QUARTER_NUM
    from typed
    where PERIOD_TYPE = 'quarter'
      and METRIC = 'regional_expenditure'
      and VALUE_NUMERIC is not null
    group by FILE_PATH

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
