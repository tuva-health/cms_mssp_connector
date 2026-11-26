{#-
    CMS's final settled result, one row per ACO and performance year, from the
    settlement (STLMT) workbook's Table 2 (updated benchmark) and Table 3
    (shared savings and losses).

    The workbook is read, never recomputed: every field is the one cell
    int_settlement_values maps to it (macros/settlement_fields.sql), by its
    section code, row kind, enrollment type and column. When the embargoed
    and unembargoed deliveries are both present, the unembargoed one is read.

    Outcomes are read, not derived. A low-revenue ACO's sharing shows in
    FINAL_SHARING_RATE ([CC]) and the payment fields ([EE], [HH]);
    MET_LOW_REVENUE_SHARING_CRITERIA ([BB]) is the Y/N criteria flag, as
    written. Y/N and text fields stay text.

    Table 2's per-type fields are `<field>_<TYPE>`. Table A1 is in
    fct_settlement_risk, Table 1's per-type rows in
    fct_settlement_historical_benchmark, Table A2 in
    fct_settlement_renormalization.
-#}

with cells as (

    select *
    from {{ ref('int_settlement_values') }}
    where IS_PREFERRED_SUBMISSION
      and FACT = 'settlement'

),

delivery_count as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        count(distinct FILE_PATH) as SETTLEMENT_DELIVERY_COUNT
    from {{ ref('int_settlement_values') }}
    group by ACO_ID, PERFORMANCE_YEAR

)

select
    cells.ACO_ID                                        as ACO_ID,
    cells.PERFORMANCE_YEAR                              as PERFORMANCE_YEAR,
    cells.SUBMISSION_ID                                 as SUBMISSION_ID,
    cells.IS_EMBARGOED                                  as IS_EMBARGOED,
    cells.FILE_DATE                                     as FILE_DATE,
    cells.FILE_PATH                                     as FILE_PATH,
    delivery_count.SETTLEMENT_DELIVERY_COUNT            as SETTLEMENT_DELIVERY_COUNT,
{{ settlement_fact_pivot('settlement', 'cells') }}

from cells

inner join delivery_count
    on cells.ACO_ID = delivery_count.ACO_ID
   and cells.PERFORMANCE_YEAR = delivery_count.PERFORMANCE_YEAR

group by
    cells.ACO_ID,
    cells.PERFORMANCE_YEAR,
    cells.SUBMISSION_ID,
    cells.IS_EMBARGOED,
    cells.FILE_DATE,
    cells.FILE_PATH,
    delivery_count.SETTLEMENT_DELIVERY_COUNT
