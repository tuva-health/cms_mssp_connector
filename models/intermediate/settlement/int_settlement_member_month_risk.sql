{#-
    The settlement population's eligible person-months (TUVA-162, method
    M-SETTLE from TUVA-161): one row per ACO, performance year, beneficiary
    and month that CMS reconciled the year on, with the month's enrollment
    type and the scores CMS printed for it.

    The rows come from cms_alr_connector's aalr_settlement_population, the
    settlement (STLMT) AALR's Table 1-1 joined to its other tables. Only the
    latest delivery of each ACO and performance year is read
    (is_latest_delivery), so an embargoed and an unembargoed copy are never
    pooled. A settlement AALR never governs a month in cms_alr_connector, and
    nothing here changes that: these months reach the facts only as
    settlement columns beside the projection.

    A month is an eligible person-month when its EnrollFlag is 1-4, and the
    flag is its type: 1 ESRD, 2 disabled, 3 aged/dual, 4 aged/non-dual. Any
    other flag is not a person-month CMS counts, so it has no row.

    The score is the month's own BENE_RSK_R_SCRE_NN, as printed. It is
    already on the national-mean-of-1.0 basis (TUVA-161 ruled out dividing
    by A2 again), and it is the performance year's own score, which the
    quarterly and initial lists never carry. A month CMS left unscored keeps
    its row with a NULL score: it still counts as a person-year, and the
    ratio model leaves it out of the mean. The demographic score is the
    beneficiary's DEM_* column for the month's type. New enrollees need no
    special case.

    PERSON_ID maps the MBI to a Tuva person the way int_member_month_risk
    does (alr_mbi_to_person). It is NULL for a beneficiary Tuva does not
    carry; the row stays, because CMS's ratio counts every reconciled
    beneficiary whether or not the claims data has them.
-#}

{%- set months = range(1, 13) -%}

with population as (

    select
        cast(aco_id as {{ dbt.type_string() }})                as ACO_ID,
        {{ cast_year_or_null('cast(performance_year as ' ~ dbt.type_string() ~ ')') }}
                                                                as PERFORMANCE_YEAR,
        cast(delivery_id as {{ dbt.type_string() }})           as DELIVERY_ID,
        cast(bene_mbi_id as {{ dbt.type_string() }})           as BENE_MBI_ID,
        dem_esrd_score                                          as DEM_ESRD_SCORE,
        dem_dis_score                                           as DEM_DIS_SCORE,
        dem_agdu_score                                          as DEM_AGDU_SCORE,
        dem_agnd_score                                          as DEM_AGND_SCORE
        {%- for m in months %},
        cast(enrollflag{{ m }} as integer)                      as ENROLL_FLAG_{{ '%02d' % m }},
        bene_rsk_r_scre_{{ '%02d' % m }}                        as RISK_SCORE_{{ '%02d' % m }}
        {%- endfor %}
    from {{ ref('cms_aalr_connector', 'aalr_settlement_population') }}
    where is_latest_delivery
      and bene_mbi_id is not null

),

-- One row per beneficiary and month of the performance year: month NN of
-- the settlement AALR is calendar month NN of the year.
population_months as (

    {%- for m in months %}
    select
        ACO_ID,
        PERFORMANCE_YEAR,
        DELIVERY_ID,
        BENE_MBI_ID,
        {{ m }}                                                 as MONTH_NUMBER,
        ENROLL_FLAG_{{ '%02d' % m }}                            as ENROLL_FLAG,
        RISK_SCORE_{{ '%02d' % m }}                             as RISK_SCORE,
        DEM_ESRD_SCORE,
        DEM_DIS_SCORE,
        DEM_AGDU_SCORE,
        DEM_AGND_SCORE
    from population
    {%- if not loop.last %}
    union all
    {%- endif %}
    {%- endfor %}

),

eligible_months as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        DELIVERY_ID,
        BENE_MBI_ID,
        {{ dbt.concat([
            'cast(PERFORMANCE_YEAR as ' ~ dbt.type_string() ~ ')',
            "case when MONTH_NUMBER < 10 then '0' else '' end",
            'cast(MONTH_NUMBER as ' ~ dbt.type_string() ~ ')'
        ]) }}                                                   as YEAR_MONTH,
        ENROLL_FLAG,
        case ENROLL_FLAG
            when 1 then 'esrd'
            when 2 then 'disabled'
            when 3 then 'aged_dual'
            when 4 then 'aged_non_dual'
        end                                                     as ENROLLMENT_TYPE,
        {{ to_double('RISK_SCORE') }}                           as RISK_SCORE,
        {{ to_double(
            'case ENROLL_FLAG
                when 1 then DEM_ESRD_SCORE
                when 2 then DEM_DIS_SCORE
                when 3 then DEM_AGDU_SCORE
                when 4 then DEM_AGND_SCORE
            end'
        ) }}                                                    as DEMOGRAPHIC_RISK_SCORE
    from population_months
    where ENROLL_FLAG in (1, 2, 3, 4)

),

persons as (

    select distinct
        cast(person_id as {{ dbt.type_string() }})             as PERSON_ID
    from {{ ref('the_tuva_project', 'core__member_month') }}

),

mbi_keys as (

    select distinct BENE_MBI_ID from eligible_months

),

{{ alr_mbi_to_person() }}

select
    eligible_months.ACO_ID                                      as ACO_ID,
    eligible_months.PERFORMANCE_YEAR                            as PERFORMANCE_YEAR,
    eligible_months.DELIVERY_ID                                 as DELIVERY_ID,
    eligible_months.BENE_MBI_ID                                 as BENE_MBI_ID,
    mbi_resolved.PERSON_ID                                      as PERSON_ID,
    mbi_resolved.MBI_CROSSWALK_SOURCE                           as MBI_CROSSWALK_SOURCE,
    eligible_months.YEAR_MONTH                                  as YEAR_MONTH,
    eligible_months.ENROLL_FLAG                                 as ENROLL_FLAG,
    eligible_months.ENROLLMENT_TYPE                             as ENROLLMENT_TYPE,
    eligible_months.RISK_SCORE                                  as RISK_SCORE,
    eligible_months.DEMOGRAPHIC_RISK_SCORE                      as DEMOGRAPHIC_RISK_SCORE
from eligible_months
left join mbi_resolved
    on mbi_resolved.BENE_MBI_ID = eligible_months.BENE_MBI_ID
