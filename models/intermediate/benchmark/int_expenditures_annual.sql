{#-
    AEXPU Table 1, typed. One workbook per benchmark year, so a delivery
    contributes three rows' worth of BENCHMARK_YEAR here where the BNMRK models
    contribute one submission.

    BENCHMARK_YEAR_LABEL is derived by counting *back* from the most recent
    benchmark year in the delivery, so the newest workbook is always BY3. Rank
    forward from the oldest and a delivery that shipped only part of its window
    would silently relabel BY3 as BY1 — and [A] is read from BY3.

    ENROLLMENT_TYPE is populated only inside the two sections CMS names for
    enrollment type. Elsewhere — component expenditures, utilization rates — the
    row label names a service category, not a cohort, and the column is NULL by
    design rather than unmapped.
-#}

with source as (

    select * from {{ ref('stg_aexpu_table_1') }}

),

enrollment_type as (

    select * from {{ ref('mssp_enrollment_type') }}

),

ranked as (

    select
        source.*,

        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR, source.BENCHMARK_YEAR
            order by source.FILE_DATE desc nulls last, source.SUBMISSION_ID desc, source.FILE_PATH desc
        ) as SUBMISSION_RANK,

        dense_rank() over (
            partition by source.ACO_ID, source.PERFORMANCE_YEAR, source.SUBMISSION_ID
            order by source.BENCHMARK_YEAR desc
        ) as BENCHMARK_YEAR_RANK_DESC

    from source

)

select
    ranked.ACO_ID                                       as ACO_ID,
    ranked.PERFORMANCE_YEAR                             as PERFORMANCE_YEAR,
    ranked.BENCHMARK_YEAR                               as BENCHMARK_YEAR,

    case
        when ranked.BENCHMARK_YEAR is not null
        then {{ dbt.concat([
                "'BY'",
                "cast(4 - ranked.BENCHMARK_YEAR_RANK_DESC as " ~ dbt.type_string() ~ ")"
             ]) }}
    end                                                 as BENCHMARK_YEAR_LABEL,

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

    {#- Table 1 heads this column 'National Assignable FFS'; Table 4 heads the
        same comparison group 'National Assignable FFS 12-Month'. The prefix
        match folds both, so a consumer never has to guess which spelling a
        sheet used. -#}
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
