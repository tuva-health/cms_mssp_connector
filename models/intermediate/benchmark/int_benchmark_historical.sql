{#-
    BNMRK Table 1, typed. Every section code is kept, not only [L], so the whole
    historical benchmark derivation stays auditable.

    Deliveries are ranked but never filtered: choosing between the March, June
    and October submissions belongs to the consumer, not here.

    SUBMISSION_RANK is a dense_rank over every row rather than a join back to a
    ranked list of submissions. FILE_DATE, SUBMISSION_ID and FILE_PATH are all
    constant within a workbook, so ranking the rows ranks the workbooks.

    FILE_PATH is in the ordering key as a last resort, and it is what makes the
    ranking total: it is unique per workbook, so no two workbooks can ever share
    rank 1 and IS_LATEST_SUBMISSION cannot fan out. Without it the rank rests on
    (FILE_DATE, SUBMISSION_ID) being unique across deliveries, which is true of
    every delivery CMS has shipped and enforced by nothing — two workbooks
    carrying one submission id would both rank 1, and a downstream sum() over
    section [L] would silently double the benchmark. That the tie is now broken
    arbitrarily rather than meaningfully is the point: it bounds the damage, and
    assert_exactly_one_latest_submission_per_window reports the collision.
-#}

with source as (

    select * from {{ ref('stg_bnmrk_table_1') }}

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
    ranked.GROUP_LABEL                                  as GROUP_LABEL,
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
