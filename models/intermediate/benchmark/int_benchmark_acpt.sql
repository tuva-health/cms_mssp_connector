{#-
    BNMRK Table 6, typed. [J] is section F ('ACPT') read at the performance year
    the consumer is calculating; sections A-E are the derivation behind it and
    are kept for audit.

    CMS omits this sheet from the March preliminary delivery, so this model
    legitimately covers fewer submissions than int_benchmark_historical, and is
    empty altogether for an ACO whose only delivery is preliminary.
-#}

with source as (

    select * from {{ ref('stg_bnmrk_table_6') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

ranked as (

    select
        source.*,
        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR
            order by source.FILE_DATE desc nulls last, source.SUBMISSION_ID desc, source.FILE_PATH desc
        ) as SUBMISSION_RANK
    from source

)

select
    ranked.ACO_ID                                       as ACO_ID,
    ranked.PERFORMANCE_YEAR                             as PERFORMANCE_YEAR,
    ranked.SUBMISSION_ID                                as SUBMISSION_ID,
    ranked.FILE_DATE                                    as FILE_DATE,
    ranked.SUBMISSION_RANK                              as SUBMISSION_RANK,
    ranked.SUBMISSION_RANK = 1                          as IS_LATEST_SUBMISSION,
    ranked.SECTION_CODE                                 as SECTION_CODE,
    ranked.SECTION_LABEL                                as SECTION_LABEL,
    ranked.ROW_LABEL                                    as ROW_LABEL,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE,
        case when ranked.ROW_LABEL = ranked.SECTION_LABEL then 'total' end,
        'unmapped'
    )                                                   as ENROLLMENT_TYPE,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE_LABEL,
        case when ranked.ROW_LABEL = ranked.SECTION_LABEL then 'Total' end,
        'Unmapped'
    )                                                   as ENROLLMENT_TYPE_LABEL,

    coalesce(
        enrollment_type.ENROLLMENT_TYPE_SORT,
        case when ranked.ROW_LABEL = ranked.SECTION_LABEL then 9 end,
        99
    )                                                   as ENROLLMENT_TYPE_SORT,

    ranked.COLUMN_LABEL                                 as COLUMN_LABEL,

    {#- The sheet carries one BY3 column alongside PY1..PY5; only the PY
        columns are performance years. -#}
    case
        when upper(trim(ranked.COLUMN_LABEL)) in ('PY1', 'PY2', 'PY3', 'PY4', 'PY5')
        then upper(trim(ranked.COLUMN_LABEL))
    end                                                 as PY_LABEL,

    case
        when upper(trim(ranked.COLUMN_LABEL)) in ('PY1', 'PY2', 'PY3', 'PY4', 'PY5')
        then cast(substring(trim(ranked.COLUMN_LABEL), 3, 1) as {{ dbt.type_int() }})
    end                                                 as PY_NUMBER,

    ranked.VALUE_TEXT                                   as VALUE_TEXT,
    ranked.VALUE_NUMERIC                                as VALUE_NUMERIC,
    ranked.FILE_PATH                                    as FILE_PATH,
    ranked.DIRECTORY_NAME                               as DIRECTORY_NAME,
    ranked.FILE_NAME                                    as FILE_NAME,
    ranked.ROW_NUM                                      as ROW_NUM

from ranked

left join enrollment_type
    on upper(trim(ranked.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER
