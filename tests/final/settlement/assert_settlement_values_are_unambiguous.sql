{#-
    Fails when a settlement field the facts read has more than one real value
    in a workbook, or a Table A1 value sits in a column of no known period.

    fct_settlement takes each Table 2 and Table 3 row's one real cell (not
    empty, not '-') across the row's value columns, without assuming which
    column CMS uses: the layout is not yet checked against a delivered
    workbook (TUVA-158). fct_settlement_risk takes Table A1's BY3 and
    performance-year cells. Both aggregate with max(), so a second real cell
    would be dropped silently. This test makes it loud: a real workbook that
    puts two values on one row needs a column rule, not a guess.

    Every delivery is checked, not only the preferred one.
-#}

with real_cells as (

    select *
    from {{ ref('int_settlement_values') }}
    where not IS_PLACEHOLDER
      and ENROLLMENT_TYPE <> 'unmapped'

),

two_values_on_a_row as (

    select
        FILE_PATH,
        TABLE_CODE,
        SECTION_CODE,
        ENROLLMENT_TYPE,
        cast(null as {{ dbt.type_string() }})  as COLUMN_PERIOD,
        count(*)                               as REAL_CELL_COUNT,
        'two_values_on_a_row'                  as FAILURE
    from real_cells
    where TABLE_CODE in ('2', '3')
    group by FILE_PATH, TABLE_CODE, SECTION_CODE, ENROLLMENT_TYPE
    having count(*) > 1

),

two_values_in_a_period as (

    select
        FILE_PATH,
        TABLE_CODE,
        SECTION_CODE,
        ENROLLMENT_TYPE,
        COLUMN_PERIOD,
        count(*)                               as REAL_CELL_COUNT,
        case
            when COLUMN_PERIOD is null then 'value_in_an_unknown_period'
            else 'two_values_in_a_period'
        end                                    as FAILURE
    from real_cells
    where TABLE_CODE = 'A1'
    group by FILE_PATH, TABLE_CODE, SECTION_CODE, ENROLLMENT_TYPE, COLUMN_PERIOD
    having count(*) > 1 or COLUMN_PERIOD is null

)

select * from two_values_on_a_row
union all
select * from two_values_in_a_period
