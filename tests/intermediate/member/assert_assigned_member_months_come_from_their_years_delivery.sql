{#-
    Every assigned member-month comes from the one assignment-list delivery
    pinned to its calendar year.

    CMS delivers the assignment list in performance-year packages that reach
    into other years: the next package's prospective-assignment window runs
    across the current year, and it re-delivers the benchmark years, scored on
    its own model and normalisation basis. A month that takes rows from more
    than one package mixes two performance years' assignment and scores, and
    that showed up downstream as a third more assigned member-months in 2025
    than the PY2025 list carries.

    Three things are asserted on every assigned row, each read from the row's
    own file name so the check does not lean on the model's parsing:

      * the file reports the row's calendar year — a Y<YYYY> or <YYYY>Q<N>
        token equal to the year of YEAR_MONTH, or no token and a delivery
        stamp equal to it;
      * the delivery stamp in the file name agrees with
        ALR_DELIVERY_PERFORMANCE_YEAR;
      * every assigned row of the same calendar year carries the same
        delivery year — one package per year.
-#}

with assigned as (

    select
        PERSON_ID,
        DATA_SOURCE,
        YEAR_MONTH,
        ALR_FILE_NAME,
        ALR_DELIVERY_PERFORMANCE_YEAR,
        ALR_REPORT_YEAR,
        {{ cast_year_or_null("substring(YEAR_MONTH, 1, 4)") }}     as CALENDAR_YEAR,
        {{ dbt.concat(["'.D'", "substring(cast(ALR_DELIVERY_PERFORMANCE_YEAR as " ~ dbt.type_string() ~ "), 3, 2)"]) }}
                                                                    as EXPECTED_STAMP,
        min(ALR_DELIVERY_PERFORMANCE_YEAR) over (partition by substring(YEAR_MONTH, 1, 4))
                                                                    as YEAR_DELIVERY
    from {{ ref('int_member_month_risk') }}
    where IS_ASSIGNED

)

select
    PERSON_ID,
    DATA_SOURCE,
    YEAR_MONTH,
    ALR_FILE_NAME,
    ALR_DELIVERY_PERFORMANCE_YEAR,
    ALR_REPORT_YEAR,
    YEAR_DELIVERY
from assigned
where ALR_DELIVERY_PERFORMANCE_YEAR is null
   or ALR_REPORT_YEAR is null
   or ALR_REPORT_YEAR <> CALENDAR_YEAR
   or ALR_DELIVERY_PERFORMANCE_YEAR <> YEAR_DELIVERY
   or {{ dbt.position("EXPECTED_STAMP", "ALR_FILE_NAME") }} = 0
   or (
          {{ dbt.position("'.AALR.Y'", "ALR_FILE_NAME") }} > 0
      and {{ dbt.position(dbt.concat(["'.AALR.Y'", "cast(CALENDAR_YEAR as " ~ dbt.type_string() ~ ")"]), "ALR_FILE_NAME") }} = 0
   )
   or (
          {{ dbt.position("'.QALR.'", "ALR_FILE_NAME") }} > 0
      and {{ dbt.position(dbt.concat(["'.QALR.'", "cast(CALENDAR_YEAR as " ~ dbt.type_string() ~ ")"]), "ALR_FILE_NAME") }} = 0
   )
   or (
          {{ dbt.position("'.AALR.Y'", "ALR_FILE_NAME") }} = 0
      and {{ dbt.position("'.QALR.'", "ALR_FILE_NAME") }} = 0
      and ALR_DELIVERY_PERFORMANCE_YEAR <> CALENDAR_YEAR
   )
