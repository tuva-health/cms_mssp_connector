{#-
    QEXPU Table 1, typed — the quarterly counterpart of int_expenditures_annual,
    and the source of [B], [N], [Q] and [S].

    PERIOD carries the quarter CMS reported ('<YYYY>Q<N>'); QUARTER_NUM splits
    the quarter out of it so the report period can be ordered. Unlike QEXPU
    Table 2, this sheet reports one period per workbook — the quarter here is a
    property of the delivery, not of a column.
-#}

with source as (

    select * from {{ ref('stg_qexpu_table_1') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

ranked as (

    select
        source.*,
        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR, source.PERIOD
            order by source.FILE_DATE desc nulls last, source.SUBMISSION_ID desc, source.FILE_PATH desc
        ) as SUBMISSION_RANK
    from source

)

select
    ranked.ACO_ID                                       as ACO_ID,
    ranked.PERFORMANCE_YEAR                             as PERFORMANCE_YEAR,
    ranked.PERIOD                                       as PERIOD,

    {#- '____Q_' is a shape check, not a regex: SIMILAR TO is unavailable on
        Snowflake, and the literal digit list is what actually makes the cast
        safe on every adapter. -#}
    case
        when upper(trim(ranked.PERIOD)) like '____Q_'
             and substring(trim(ranked.PERIOD), 6, 1) in ('1', '2', '3', '4')
        then cast(substring(trim(ranked.PERIOD), 6, 1) as {{ dbt.type_int() }})
    end                                                 as QUARTER_NUM,

    ranked.SUBMISSION_ID                                as SUBMISSION_ID,
    ranked.FILE_DATE                                    as FILE_DATE,
    ranked.SUBMISSION_RANK                              as SUBMISSION_RANK,
    ranked.SUBMISSION_RANK = 1                          as IS_LATEST_SUBMISSION,
    ranked.SECTION_LABEL                                as SECTION_LABEL,

    case
        when nullif(trim(ranked.SECTION_LABEL), '') is null
             and upper(trim(ranked.ROW_LABEL)) = 'TOTAL ASSIGNED BENEFICIARIES'
            then 'total_assigned_beneficiaries'
        when nullif(trim(ranked.SECTION_LABEL), '') is null
             and upper(trim(ranked.ROW_LABEL)) = 'NUMBER OF ACOS'
            then 'number_of_acos'
        when upper(trim(ranked.SECTION_LABEL))
                = 'TOTAL EXPENDITURES BY ASSIGNED BENEFICIARY MEDICARE ENROLLMENT TYPE'
            then 'total_expenditures_per_capita'
        when upper(trim(ranked.SECTION_LABEL))
                = 'PERSON YEARS BY ASSIGNED BENEFICIARY MEDICARE ENROLLMENT TYPE'
            then 'person_years'
        when upper(trim(ranked.SECTION_LABEL))
                = 'COMPONENT EXPENDITURES PER ASSIGNED BENEFICIARY'
            then 'component_expenditures_per_beneficiary'
        when upper(trim(ranked.SECTION_LABEL))
                = 'ADDITIONAL UTILIZATION RATES (PER 1,000 PERSON YEARS)'
            then 'additional_utilization_rates'
        when upper(trim(ranked.SECTION_LABEL))
                = 'ASSIGNED BENEFICIARIES WITH NON-CLAIMS BASED PAYMENTS'
            then 'non_claims_based_payments'
        when upper(trim(ranked.SECTION_LABEL))
                = 'ASSIGNED BENEFICIARIES WHO DECLINED DATA SHARING'
            then 'declined_data_sharing'
        else 'unmapped'
    end                                                 as METRIC,

    ranked.ROW_LABEL                                    as ROW_LABEL,

    case
        when upper(trim(ranked.SECTION_LABEL)) like '%ENROLLMENT TYPE%'
        then coalesce(enrollment_type.ENROLLMENT_TYPE, 'unmapped')
    end                                                 as ENROLLMENT_TYPE,

    case
        when upper(trim(ranked.SECTION_LABEL)) like '%ENROLLMENT TYPE%'
        then coalesce(enrollment_type.ENROLLMENT_TYPE_LABEL, 'Unmapped')
    end                                                 as ENROLLMENT_TYPE_LABEL,

    case
        when upper(trim(ranked.SECTION_LABEL)) like '%ENROLLMENT TYPE%'
        then coalesce(enrollment_type.ENROLLMENT_TYPE_SORT, 99)
    end                                                 as ENROLLMENT_TYPE_SORT,

    ranked.COLUMN_LABEL                                 as COLUMN_LABEL,

    case
        when upper(trim(ranked.COLUMN_LABEL)) = 'ACO-SPECIFIC'
            then 'aco_specific'
        when upper(trim(ranked.COLUMN_LABEL)) = 'ALL MSSP ACOS'
            then 'all_mssp_acos'
        when upper(trim(ranked.COLUMN_LABEL)) like 'NATIONAL ASSIGNABLE FFS%'
            then 'national_assignable_ffs'
        else 'unmapped'
    end                                                 as COLUMN_VARIANT,

    ranked.VALUE_TEXT                                   as VALUE_TEXT,
    ranked.VALUE_NUMERIC                                as VALUE_NUMERIC,
    ranked.FILE_PATH                                    as FILE_PATH,
    ranked.DIRECTORY_NAME                               as DIRECTORY_NAME,
    ranked.FILE_NAME                                    as FILE_NAME,
    ranked.ROW_NUM                                      as ROW_NUM

from ranked

left join enrollment_type
    on upper(trim(ranked.ROW_LABEL)) = enrollment_type.ROW_LABEL_UPPER
