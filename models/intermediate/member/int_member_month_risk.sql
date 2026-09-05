{#-
    Enrollment type and CMS prospective HCC risk score, one row per Tuva
    person, data source and month.

    The spine is core__member_months and nothing filters it: a month the
    assignment list does not cover keeps its row with IS_ASSIGNED false, so the
    benchmark can be applied to every member-month and the ones it cannot be
    applied to are visible rather than absent.

    The assignment list is keyed on MBI; Tuva is keyed on person_id, which the
    CCLF connector derives from the assignment-list MBI mapped through the CCLF
    beneficiary crosswalk. That mapping is reproduced here, in this order, so
    the two keys land in the same space: the MBI itself where it is already a
    Tuva person, the CCLF crosswalk's current MBI where it is not, and the MSSP
    excluded-beneficiary crosswalk after that. The order matters. The excluded-
    beneficiary crosswalk knows many MBIs that Tuva still carries as the person
    id, because Tuva was built through the CCLF crosswalk and not this one;
    consulting it first would move those members off their own person id.

    Assignment is pinned to one delivery per calendar year. CMS delivers the
    assignment list in performance-year packages, stamped D<YY> in the file
    name, and a package reaches into other years: the PY2026 package carries
    the PY2026 prospective-assignment window across 2025 (its initial AALR
    and its first quarterly lists) and re-delivers 2023 and 2024 as benchmark
    years, scored on the PY2026 model and normalisation basis. Letting those
    rows stand as 2025 or 2024 assignment mixes two performance years' scores
    and over-counts assigned member-months. So each assignment-list row is
    given the year its file reports — the Y<YYYY> token of a benchmark-year
    file, the <YYYY>Q<N> token of a quarterly file, otherwise the delivery
    stamp itself — and a member-month takes rows only from files reporting its
    own calendar year, and among those only from the earliest delivery that
    reports it. For the performance year itself that is its own delivery; for
    a benchmark year it is the delivery in which the year was first reported,
    so a later package never rewrites history. Rows from any other delivery
    are ignored for that month: a member known only to an off-year delivery
    is unassigned there, takes the type fallbacks and carries a NULL score.

    Two ranks keep the grain total against inputs that enforce nothing. Two
    assignment-list MBIs can resolve to one person in one month once a retired
    MBI is crosswalked, and the same person-year can appear in the BEUR under
    more than one delivery. Both are ranked and the first row taken, so a
    collision costs one row's provenance rather than a doubled member-month.

    Enrollment type resolves in priority order and is never defaulted; see the
    column documentation in _models.yml for each step. The score comes only
    from the assignment list, read from whichever layout the row carries: the
    populated per-type column on 2025+ files, or the monthly column for the
    row's own month on 2022-2024 files, where BENE_RSK_R_SCRE_NN holds the
    score for month NN of the performance year. The demographic-only DEM_*
    scores are never read: a new enrollee's score is the one CMS wrote in the
    column of their actual type, and their type is that column's.
-#}

with member_months as (

    select distinct
        cast(person_id as {{ dbt.type_string() }})          as PERSON_ID,
        cast(data_source as {{ dbt.type_string() }})        as DATA_SOURCE,
        cast(year_month as {{ dbt.type_string() }})         as YEAR_MONTH
    from {{ ref('the_tuva_project', 'core__member_months') }}

),

persons as (

    select distinct PERSON_ID
    from member_months

),

assignment_list as (

    select
        cast(current_bene_mbi_id as {{ dbt.type_string() }})   as BENE_MBI_ID,
        cast(bene_member_month as {{ dbt.type_string() }})     as YEAR_MONTH,
        assignment_type                                         as ASSIGNMENT_TYPE,
        new_enrollee                                            as NEW_ENROLLEE,
        cast(hcc_version as {{ dbt.type_string() }})            as HCC_VERSION,

        case
            when esrd_score is not null then 'esrd'
            when dis_score  is not null then 'disabled'
            when agdu_score is not null then 'aged_dual'
            when agnd_score is not null then 'aged_non_dual'
        end                                                     as SCORE_COLUMN_TYPE,

        coalesce(esrd_score, dis_score, agdu_score, agnd_score) as TYPE_SCORE,

        case substring(cast(bene_member_month as {{ dbt.type_string() }}), 5, 2)
            when '01' then bene_rsk_r_scre_01
            when '02' then bene_rsk_r_scre_02
            when '03' then bene_rsk_r_scre_03
            when '04' then bene_rsk_r_scre_04
            when '05' then bene_rsk_r_scre_05
            when '06' then bene_rsk_r_scre_06
            when '07' then bene_rsk_r_scre_07
            when '08' then bene_rsk_r_scre_08
            when '09' then bene_rsk_r_scre_09
            when '10' then bene_rsk_r_scre_10
            when '11' then bene_rsk_r_scre_11
            when '12' then bene_rsk_r_scre_12
        end                                                     as MONTHLY_SCORE,

        cast(file_name as {{ dbt.type_string() }})              as FILE_NAME,
        cast(file_date as date)                                 as FILE_DATE,

        -- D<YY> delivery stamp: the performance-year package the file came in.
        case
            when {{ dbt.position("'.D'", "file_name") }} > 0
            then {{ cast_year_or_null(dbt.concat(["'20'", "substring(file_name, " ~ dbt.position("'.D'", "file_name") ~ " + 2, 2)"])) }}
        end                                                     as DELIVERY_PERFORMANCE_YEAR,

        -- The year the file reports, where the name says so.
        case
            when {{ dbt.position("'.AALR.Y'", "file_name") }} > 0
            then {{ cast_year_or_null("substring(file_name, " ~ dbt.position("'.AALR.Y'", "file_name") ~ " + 7, 4)") }}
            when {{ dbt.position("'.QALR.'", "file_name") }} > 0
            then {{ cast_year_or_null("substring(file_name, " ~ dbt.position("'.QALR.'", "file_name") ~ " + 6, 4)") }}
        end                                                     as FILE_REPORT_YEAR
    from {{ ref('cms_aalr_connector', 'enrollment') }}
    where current_bene_mbi_id is not null

),

assignment_dated as (

    select
        assignment_list.*,
        coalesce(FILE_REPORT_YEAR, DELIVERY_PERFORMANCE_YEAR)   as REPORT_YEAR
    from assignment_list

),

-- One delivery per reported year: the earliest package that reports it.
pinned_delivery as (

    select
        REPORT_YEAR,
        min(DELIVERY_PERFORMANCE_YEAR)                          as DELIVERY_PERFORMANCE_YEAR
    from assignment_dated
    where REPORT_YEAR is not null
      and DELIVERY_PERFORMANCE_YEAR is not null
    group by REPORT_YEAR

),

beur as (

    select
        cast(BENE_MBI_ID as {{ dbt.type_string() }})            as BENE_MBI_ID,
        cast(RPT_YR_NUM as {{ dbt.type_string() }})             as REPORT_YEAR,
        cast(PRFMNC_YR_NUM as {{ dbt.type_string() }})          as PERFORMANCE_YEAR,
        cast(RPT_QTR_NUM as {{ dbt.type_string() }})            as REPORT_QUARTER,
        {{ cast_numeric_or_null('ESRD_FRAC') }}                 as ESRD_FRACTION,
        {{ cast_numeric_or_null('DSBL_FRAC') }}                 as DISABLED_FRACTION,
        {{ cast_numeric_or_null('AGDU_FRAC') }}                 as AGED_DUAL_FRACTION,
        {{ cast_numeric_or_null('AGND_FRAC') }}                 as AGED_NON_DUAL_FRACTION,
        cast(FILE_DATE as date)                                 as FILE_DATE,
        cast(FILE_PATH as {{ dbt.type_string() }})              as FILE_PATH
    from {{ ref('stg_beur_beneficiary_expenditure_utilization_report') }}
    where BENE_MBI_ID is not null

),

cclf_beneficiary_xref as (

    select
        cast(prvs_num as {{ dbt.type_string() }})               as PREVIOUS_MBI,
        cast(crnt_num as {{ dbt.type_string() }})               as CURRENT_MBI
    from {{ ref('medicare_cclf_connector', 'int_beneficiary_xref_deduped') }}
    where prvs_num is not null
      and crnt_num is not null

),

excluded_beneficiary_xref as (

    select
        PREVIOUS_MBI,
        CURRENT_MBI
    from (
        select
            cast(PREVIOUS_BENE_MBI as {{ dbt.type_string() }})  as PREVIOUS_MBI,
            cast(CURRENT_BENE_MBI as {{ dbt.type_string() }})   as CURRENT_MBI,
            row_number() over (
                partition by PREVIOUS_BENE_MBI
                order by PERFORMANCE_YEAR desc, REPORT_MONTH desc, FILE_DATE desc nulls last, FILE_PATH desc
            )                                                   as MAPPING_RANK
        from {{ ref('stg_excluded_beneficiary_mbi_xref') }}
        where PREVIOUS_BENE_MBI is not null
          and CURRENT_BENE_MBI is not null
    ) as ranked
    where MAPPING_RANK = 1

),

-- Every MBI either source carries, resolved to a Tuva person once.
mbi_keys as (

    select BENE_MBI_ID from assignment_dated
    union
    select BENE_MBI_ID from beur

),

mbi_resolved as (

    select
        mbi_keys.BENE_MBI_ID,
        case
            when direct.PERSON_ID is not null        then direct.PERSON_ID
            when via_cclf.PERSON_ID is not null      then via_cclf.PERSON_ID
            when via_excluded.PERSON_ID is not null  then via_excluded.PERSON_ID
        end                                                     as PERSON_ID,
        case
            when direct.PERSON_ID is not null        then 'direct'
            when via_cclf.PERSON_ID is not null      then 'cclf_beneficiary_xref'
            when via_excluded.PERSON_ID is not null  then 'excluded_beneficiary_mbi_xref'
        end                                                     as MBI_CROSSWALK_SOURCE
    from mbi_keys

    left join persons as direct
        on direct.PERSON_ID = mbi_keys.BENE_MBI_ID

    left join cclf_beneficiary_xref
        on cclf_beneficiary_xref.PREVIOUS_MBI = mbi_keys.BENE_MBI_ID
    left join persons as via_cclf
        on via_cclf.PERSON_ID = cclf_beneficiary_xref.CURRENT_MBI

    left join excluded_beneficiary_xref
        on excluded_beneficiary_xref.PREVIOUS_MBI = mbi_keys.BENE_MBI_ID
    left join persons as via_excluded
        on via_excluded.PERSON_ID = excluded_beneficiary_xref.CURRENT_MBI

),

-- Only rows from the pinned delivery of the month's own calendar year.
assignment_ranked as (

    select
        mbi_resolved.PERSON_ID,
        mbi_resolved.MBI_CROSSWALK_SOURCE,
        assignment_dated.*,
        row_number() over (
            partition by mbi_resolved.PERSON_ID, assignment_dated.YEAR_MONTH
            order by
                assignment_dated.FILE_DATE desc nulls last,
                case when mbi_resolved.MBI_CROSSWALK_SOURCE = 'direct' then 0 else 1 end,
                assignment_dated.FILE_NAME desc,
                assignment_dated.BENE_MBI_ID desc
        )                                                       as ASSIGNMENT_RANK
    from assignment_dated
    inner join pinned_delivery
        on pinned_delivery.REPORT_YEAR = assignment_dated.REPORT_YEAR
        and pinned_delivery.DELIVERY_PERFORMANCE_YEAR = assignment_dated.DELIVERY_PERFORMANCE_YEAR
    inner join mbi_resolved
        on mbi_resolved.BENE_MBI_ID = assignment_dated.BENE_MBI_ID
    where mbi_resolved.PERSON_ID is not null
      and assignment_dated.REPORT_YEAR = {{ cast_year_or_null("substring(assignment_dated.YEAR_MONTH, 1, 4)") }}

),

assignment as (

    select *
    from assignment_ranked
    where ASSIGNMENT_RANK = 1

),

-- The BEUR reports a person-year once per delivery: the benchmark years as
-- annual rows under each later performance year, the performance year itself
-- quarter by quarter. The latest performance year's latest quarter wins, an
-- annual row (no quarter) outranking any quarter of the same delivery.
beur_ranked as (

    select
        mbi_resolved.PERSON_ID,
        mbi_resolved.MBI_CROSSWALK_SOURCE,
        beur.*,
        row_number() over (
            partition by mbi_resolved.PERSON_ID, beur.REPORT_YEAR
            order by
                beur.PERFORMANCE_YEAR desc nulls last,
                beur.REPORT_QUARTER desc nulls first,
                beur.FILE_DATE desc nulls last,
                beur.FILE_PATH desc,
                case when mbi_resolved.MBI_CROSSWALK_SOURCE = 'direct' then 0 else 1 end,
                beur.BENE_MBI_ID desc
        )                                                       as BEUR_RANK
    from beur
    inner join mbi_resolved
        on mbi_resolved.BENE_MBI_ID = beur.BENE_MBI_ID
    where mbi_resolved.PERSON_ID is not null

),

beur_type as (

    select
        PERSON_ID,
        REPORT_YEAR,
        case
            when ESRD_FRACTION > 0
             and ESRD_FRACTION >= coalesce(DISABLED_FRACTION, 0)
             and ESRD_FRACTION >= coalesce(AGED_DUAL_FRACTION, 0)
             and ESRD_FRACTION >= coalesce(AGED_NON_DUAL_FRACTION, 0)     then 'esrd'
            when DISABLED_FRACTION > 0
             and DISABLED_FRACTION >= coalesce(AGED_DUAL_FRACTION, 0)
             and DISABLED_FRACTION >= coalesce(AGED_NON_DUAL_FRACTION, 0) then 'disabled'
            when AGED_DUAL_FRACTION > 0
             and AGED_DUAL_FRACTION >= coalesce(AGED_NON_DUAL_FRACTION, 0) then 'aged_dual'
            when AGED_NON_DUAL_FRACTION > 0                                then 'aged_non_dual'
        end                                                     as ENROLLMENT_TYPE
    from beur_ranked
    where BEUR_RANK = 1

),

eligibility as (

    select
        cast(person_id as {{ dbt.type_string() }})                          as PERSON_ID,
        cast(data_source as {{ dbt.type_string() }})                        as DATA_SOURCE,
        cast(enrollment_start_date as date)                                 as ENROLLMENT_START_DATE,
        cast(enrollment_end_date as date)                                   as ENROLLMENT_END_DATE,
        cast(medicare_status_code as {{ dbt.type_string() }})               as MEDICARE_STATUS_CODE,
        cast(original_reason_entitlement_code as {{ dbt.type_string() }})   as ORIGINAL_REASON_ENTITLEMENT_CODE,
        cast(dual_status_code as {{ dbt.type_string() }})                   as DUAL_STATUS_CODE
    from {{ ref('the_tuva_project', 'core__eligibility') }}

),

member_month_dates as (

    select
        PERSON_ID,
        DATA_SOURCE,
        YEAR_MONTH,
        cast({{ dbt.concat(["substring(YEAR_MONTH, 1, 4)", "'-'", "substring(YEAR_MONTH, 5, 2)", "'-01'"]) }} as date)
                                                                as MONTH_START
    from member_months

),

-- The eligibility span overlapping the month, latest-starting span first when
-- more than one does, which is how Tuva itself counts a member-month.
eligibility_ranked as (

    select
        member_month_dates.PERSON_ID,
        member_month_dates.DATA_SOURCE,
        member_month_dates.YEAR_MONTH,
        eligibility.MEDICARE_STATUS_CODE,
        eligibility.ORIGINAL_REASON_ENTITLEMENT_CODE,
        eligibility.DUAL_STATUS_CODE,
        row_number() over (
            partition by member_month_dates.PERSON_ID, member_month_dates.DATA_SOURCE, member_month_dates.YEAR_MONTH
            order by
                eligibility.ENROLLMENT_START_DATE desc,
                eligibility.ENROLLMENT_END_DATE desc nulls last,
                eligibility.MEDICARE_STATUS_CODE,
                eligibility.ORIGINAL_REASON_ENTITLEMENT_CODE,
                eligibility.DUAL_STATUS_CODE
        )                                                       as SPAN_RANK
    from member_month_dates
    inner join eligibility
        on eligibility.PERSON_ID = member_month_dates.PERSON_ID
        and eligibility.DATA_SOURCE = member_month_dates.DATA_SOURCE
        and eligibility.ENROLLMENT_START_DATE <= {{ dbt.last_day('member_month_dates.MONTH_START', 'month') }}
        and coalesce(eligibility.ENROLLMENT_END_DATE, member_month_dates.MONTH_START) >= member_month_dates.MONTH_START

),

-- Dual status arrives as a CMS code (00 and NA non-dual, 01-08 dual) from the
-- CCLF demographics, or as the assignment list's person-year dual fraction
-- where the CCLF connector had one; a fraction of at least one half is dual.
eligibility_dual as (

    select
        PERSON_ID,
        DATA_SOURCE,
        YEAR_MONTH,
        MEDICARE_STATUS_CODE,
        ORIGINAL_REASON_ENTITLEMENT_CODE,
        case
            when DUAL_STATUS_CODE in ('01', '02', '03', '04', '05', '06', '07', '08') then true
            when {{ cast_numeric_or_null('DUAL_STATUS_CODE') }} >= 0.5
             and {{ cast_numeric_or_null('DUAL_STATUS_CODE') }} <= 1                  then true
            else false
        end                                                     as IS_DUAL
    from eligibility_ranked
    where SPAN_RANK = 1

),

eligibility_type as (

    select
        PERSON_ID,
        DATA_SOURCE,
        YEAR_MONTH,
        case
            when MEDICARE_STATUS_CODE in ('11', '21', '31')         then 'esrd'
            when MEDICARE_STATUS_CODE = '20'                        then 'disabled'
            when MEDICARE_STATUS_CODE = '10' and IS_DUAL            then 'aged_dual'
            when MEDICARE_STATUS_CODE = '10'                        then 'aged_non_dual'
            when ORIGINAL_REASON_ENTITLEMENT_CODE in ('2', '3')     then 'esrd'
            when ORIGINAL_REASON_ENTITLEMENT_CODE = '1'             then 'disabled'
            when IS_DUAL                                            then 'aged_dual'
            else                                                         'aged_non_dual'
        end                                                     as ENROLLMENT_TYPE
    from eligibility_dual

)

select
    member_months.PERSON_ID                                     as PERSON_ID,
    member_months.DATA_SOURCE                                   as DATA_SOURCE,
    member_months.YEAR_MONTH                                    as YEAR_MONTH,
    assignment.BENE_MBI_ID                                      as ALR_BENE_MBI_ID,
    assignment.MBI_CROSSWALK_SOURCE                             as MBI_CROSSWALK_SOURCE,
    assignment.PERSON_ID is not null                            as IS_ASSIGNED,

    case
        when assignment.NEW_ENROLLEE = 1 then true
        when assignment.NEW_ENROLLEE = 0 then false
    end                                                         as IS_NEW_ENROLLEE,

    assignment.ASSIGNMENT_TYPE                                  as ASSIGNMENT_TYPE,

    coalesce(
        assignment.SCORE_COLUMN_TYPE,
        beur_type.ENROLLMENT_TYPE,
        eligibility_type.ENROLLMENT_TYPE
    )                                                           as ENROLLMENT_TYPE,

    case
        when assignment.SCORE_COLUMN_TYPE is not null       then 'assignment_list_score_column'
        when beur_type.ENROLLMENT_TYPE is not null          then 'beur_person_year_fraction'
        when eligibility_type.ENROLLMENT_TYPE is not null   then 'eligibility_codes'
    end                                                         as ENROLLMENT_TYPE_SOURCE,

    coalesce(assignment.TYPE_SCORE, assignment.MONTHLY_SCORE)   as RISK_SCORE,

    case
        when assignment.TYPE_SCORE is not null      then 'assignment_list_type_score'
        when assignment.MONTHLY_SCORE is not null   then 'assignment_list_monthly_score'
    end                                                         as RISK_SCORE_SOURCE,

    assignment.HCC_VERSION                                      as HCC_VERSION,
    assignment.DELIVERY_PERFORMANCE_YEAR                        as ALR_DELIVERY_PERFORMANCE_YEAR,
    assignment.REPORT_YEAR                                      as ALR_REPORT_YEAR,
    assignment.FILE_NAME                                        as ALR_FILE_NAME,
    assignment.FILE_DATE                                        as ALR_FILE_DATE

from member_months

left join assignment
    on assignment.PERSON_ID = member_months.PERSON_ID
    and assignment.YEAR_MONTH = member_months.YEAR_MONTH

left join beur_type
    on beur_type.PERSON_ID = member_months.PERSON_ID
    and beur_type.REPORT_YEAR = substring(member_months.YEAR_MONTH, 1, 4)

left join eligibility_type
    on eligibility_type.PERSON_ID = member_months.PERSON_ID
    and eligibility_type.DATA_SOURCE = member_months.DATA_SOURCE
    and eligibility_type.YEAR_MONTH = member_months.YEAR_MONTH
