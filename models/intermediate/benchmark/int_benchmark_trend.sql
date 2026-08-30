{#-
    BNMRK Table 2, typed — the trend factor audit trail: national and regional
    per capita expenditures, the two trend factors, the weights CMS blends them
    with, and the blended factor itself, all by benchmark year.

    No section here is an input to the performance year benchmark calculation;
    the model exists so the trend factor that Table 1 section E carries can be
    traced back to its components.
-#}

with source as (

    select * from {{ ref('stg_bnmrk_table_2') }}

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

    ranked.COLUMN_LABEL                                 as BY_LABEL,
    ranked.VALUE_TEXT                                   as VALUE_TEXT,
    ranked.VALUE_NUMERIC                                as VALUE_NUMERIC,
    ranked.FILE_PATH                                    as FILE_PATH,
    ranked.DIRECTORY_NAME                               as DIRECTORY_NAME,
    ranked.FILE_NAME                                    as FILE_NAME,
    ranked.ROW_NUM                                      as ROW_NUM

from ranked

left join enrollment_type
    on upper(trim(ranked.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER
