{#-
    Every member-month in Tuva's core__member_months has exactly one row here.

    The model is a left join from that spine, so a missing row can only mean a
    join fanned in the wrong direction or a filter crept in. The benchmark is
    applied per member-month downstream; a month without a row is a month
    silently left out of the ACO's expenditure, which is the failure this
    test makes loud.

    The semantic-layer member-months fact mirrors this spine one to one; the
    relationship test against it is added with the semantic layer (TUVA-75).
-#}

with spine as (

    select distinct
        cast(person_id as {{ dbt.type_string() }})     as PERSON_ID,
        cast(data_source as {{ dbt.type_string() }})   as DATA_SOURCE,
        cast(year_month as {{ dbt.type_string() }})    as YEAR_MONTH
    from {{ ref('the_tuva_project', 'core__member_months') }}

)

select
    spine.PERSON_ID,
    spine.DATA_SOURCE,
    spine.YEAR_MONTH
from spine
left join {{ ref('int_member_month_risk') }} as risk
    on risk.PERSON_ID = spine.PERSON_ID
    and risk.DATA_SOURCE = spine.DATA_SOURCE
    and risk.YEAR_MONTH = spine.YEAR_MONTH
where risk.PERSON_ID is null
