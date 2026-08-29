{#-
    The per-enrollment-type half of the three-way blended benchmark update:
    steps [A] through [O] of the CMS calculation, one row per enrollment type
    per (reported quarter x benchmark delivery).

    Three things about the shape of this model are deliberate and are the
    reason it looks the way it does.

    Every pairing is a row. CMS delivers the historical benchmark up to three
    times for one performance year — March preliminary, June preliminary-final,
    October final — and the three carry different numbers. The quarterly report
    arrives four times. Which benchmark delivery a given quarter should be
    measured against is a question about what the caller is doing: reconciling
    against what CMS said in June is a different question from projecting with
    the final. So all pairings are materialised and none is chosen.
    IS_LATEST_BENCHMARK_SUBMISSION is the filter that collapses this back to one
    row per quarter, and an unfiltered query multiplies rows by the number of
    deliveries.

    One delivery supplies three inputs coherently. The AEXPU workbooks ship
    inside the BNMRK bundle and carry the bundle's own submission stamp, so
    BENCHMARK_SUBMISSION_ID selects [A] from the AEXPU BY3 workbook, [J] from
    BNMRK Table 6 and [L] from BNMRK Table 1 out of one delivery rather than
    mixing March's benchmark with June's national expenditures. That property is
    upstream's, not this model's; assert_annual_expenditures_share_the_benchmark_delivery
    checks it rather than assuming it.

    No row is ever dropped for a missing input. The March delivery ships no
    Table 6, so [J] is absent and [K], [M] and everything downstream of them
    cannot be computed. That pairing still gets its four rows, carrying NULL,
    flagged IS_CALCULABLE = false. A quarter that quietly vanished from a report
    is far harder to notice than one sitting there full of NULLs, and
    assert_benchmark_rows_exist_for_every_pairing fails if one does.

    All arithmetic is done in 64-bit floating point via to_double and
    safe_divide. See those macros for why: the inputs are Excel doubles, and
    decimal division would round an update factor in its seventh significant
    digit on Snowflake.
-#}

with enrollment_type as (

    {#- The four cohorts the calculation blends. The seed carries two labels for
        ESRD and a fifth `aged_disabled` key that only BNMRK Table 6's first two
        sections use, so the four are named explicitly and deduplicated. -#}
    select
        ENROLLMENT_TYPE                 as ENROLLMENT_TYPE,
        min(ENROLLMENT_TYPE_LABEL)      as ENROLLMENT_TYPE_LABEL,
        min(ENROLLMENT_TYPE_SORT)       as ENROLLMENT_TYPE_SORT
    from {{ ref('mssp_enrollment_type') }}
    where ENROLLMENT_TYPE in ('esrd', 'disabled', 'aged_dual', 'aged_non_dual')
    group by ENROLLMENT_TYPE

),

quarterly_delivery as (

    {#- One row per reported quarter. The quarterly report is pinned to its
        latest submission here, unlike the benchmark: a redelivery of one
        quarter supersedes the earlier one rather than standing beside it. -#}
    select distinct
        ACO_ID                          as ACO_ID,
        PERFORMANCE_YEAR                as PERFORMANCE_YEAR,
        PERIOD                          as PERIOD,
        QUARTER_NUM                     as QUARTER_NUM,
        SUBMISSION_ID                   as QUARTERLY_SUBMISSION_ID
    from {{ ref('int_expenditures_quarterly') }}
    where IS_LATEST_SUBMISSION

),

benchmark_delivery as (

    {#- One row per benchmark delivery, all of them. Table 1 is the sheet that
        every delivery carries, including the March preliminary one that omits
        Table 6, so it — not Table 6 — is what defines the delivery set. -#}
    select distinct
        ACO_ID                          as ACO_ID,
        PERFORMANCE_YEAR                as PERFORMANCE_YEAR,
        SUBMISSION_ID                   as BENCHMARK_SUBMISSION_ID,
        IS_LATEST_SUBMISSION            as IS_LATEST_BENCHMARK_SUBMISSION
    from {{ ref('int_benchmark_historical') }}

),

agreement as (

    select
        ACO_ID                          as ACO_ID,
        PERFORMANCE_YEAR                as PERFORMANCE_YEAR,
        ACPT_PERFORMANCE_YEAR_LABEL     as ACPT_PERFORMANCE_YEAR_LABEL
    from {{ ref('mssp_aco_agreement') }}

),

spine as (

    select
        quarterly_delivery.ACO_ID                       as ACO_ID,
        quarterly_delivery.PERFORMANCE_YEAR             as PERFORMANCE_YEAR,
        quarterly_delivery.PERIOD                       as PERIOD,
        quarterly_delivery.QUARTER_NUM                  as QUARTER_NUM,
        quarterly_delivery.QUARTERLY_SUBMISSION_ID      as QUARTERLY_SUBMISSION_ID,
        benchmark_delivery.BENCHMARK_SUBMISSION_ID      as BENCHMARK_SUBMISSION_ID,
        benchmark_delivery.IS_LATEST_BENCHMARK_SUBMISSION
                                                        as IS_LATEST_BENCHMARK_SUBMISSION,

        coalesce(agreement.ACPT_PERFORMANCE_YEAR_LABEL, 'PY1')
                                                        as ACPT_PERFORMANCE_YEAR_LABEL,
        agreement.ACO_ID is null                        as IS_AGREEMENT_DEFAULTED,

        enrollment_type.ENROLLMENT_TYPE                 as ENROLLMENT_TYPE,
        enrollment_type.ENROLLMENT_TYPE_LABEL           as ENROLLMENT_TYPE_LABEL,
        enrollment_type.ENROLLMENT_TYPE_SORT            as ENROLLMENT_TYPE_SORT

    from quarterly_delivery

    inner join benchmark_delivery
        on quarterly_delivery.ACO_ID = benchmark_delivery.ACO_ID
       and quarterly_delivery.PERFORMANCE_YEAR = benchmark_delivery.PERFORMANCE_YEAR

    left join agreement
        on quarterly_delivery.ACO_ID = agreement.ACO_ID
       and quarterly_delivery.PERFORMANCE_YEAR = agreement.PERFORMANCE_YEAR

    cross join enrollment_type

),

{#- ------------------------------------------------------------------------
    The eleven measured inputs, one flat predicate each. Nothing is aggregated
    and nothing is ranked here: the intermediate models have already done both,
    and each of these returns at most one row per join key.
------------------------------------------------------------------------- -#}

national_base_candidates as (

    {#- [A] National assignable FFS per capita, benchmark year 3, from the
        AEXPU BY3 workbook of the benchmark delivery.

        COLUMN_VARIANT folds two spellings CMS uses for this column —
        'National Assignable FFS' and 'National Assignable FFS 12-Month' — and a
        prospective-assignment workbook can carry both at once. The reference
        implementation looks for the 12-Month column first and falls back to the
        plain one, so the preference is reproduced rather than left to chance:
        without it a workbook carrying both returns two rows per join key and
        the left join fans out to eight enrollment rows per pairing. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        BENCHMARK_YEAR      as BENCHMARK_YEAR,
        COLUMN_LABEL        as COLUMN_LABEL,
        VALUE_NUMERIC       as VALUE_NUMERIC,
        case
            when upper(trim(COLUMN_LABEL)) like '%12-MONTH%' then 1
            else 2
        end                 as COLUMN_PREFERENCE
    from {{ ref('int_expenditures_annual') }}
    where METRIC = 'total_expenditures_per_capita'
      and COLUMN_VARIANT = 'national_assignable_ffs'
      and BENCHMARK_YEAR_LABEL = 'BY3'
      and ENROLLMENT_TYPE <> 'total'

),

national_base as (

    {#- ROW_NUMBER in a subquery rather than QUALIFY: Postgres and Redshift have
        no QUALIFY, and the macros in this project are dispatched for them. -#}
    select
        ACO_ID,
        PERFORMANCE_YEAR,
        SUBMISSION_ID,
        ENROLLMENT_TYPE,
        BENCHMARK_YEAR,
        COLUMN_LABEL,
        VALUE_NUMERIC
    from (
        select
            national_base_candidates.*,
            row_number() over (
                partition by ACO_ID, PERFORMANCE_YEAR, SUBMISSION_ID, ENROLLMENT_TYPE
                order by COLUMN_PREFERENCE, COLUMN_LABEL
            ) as COLUMN_RANK
        from national_base_candidates
    ) as ranked
    where COLUMN_RANK = 1

),

national_current_candidates as (

    {#- [B] National assignable FFS per capita for the reported quarter. Same
        two spellings and the same preference as [A] above. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        COLUMN_LABEL        as COLUMN_LABEL,
        VALUE_NUMERIC       as VALUE_NUMERIC,
        case
            when upper(trim(COLUMN_LABEL)) like '%12-MONTH%' then 1
            else 2
        end                 as COLUMN_PREFERENCE
    from {{ ref('int_expenditures_quarterly') }}
    where METRIC = 'total_expenditures_per_capita'
      and COLUMN_VARIANT = 'national_assignable_ffs'
      and ENROLLMENT_TYPE <> 'total'

),

national_current as (

    select
        ACO_ID,
        PERFORMANCE_YEAR,
        PERIOD,
        SUBMISSION_ID,
        ENROLLMENT_TYPE,
        COLUMN_LABEL,
        VALUE_NUMERIC
    from (
        select
            national_current_candidates.*,
            row_number() over (
                partition by ACO_ID, PERFORMANCE_YEAR, PERIOD, SUBMISSION_ID, ENROLLMENT_TYPE
                order by COLUMN_PREFERENCE, COLUMN_LABEL
            ) as COLUMN_RANK
        from national_current_candidates
    ) as ranked
    where COLUMN_RANK = 1

),

regional_base as (

    {#- [D] Regional expenditures, benchmark year 3 column of QEXPU Table 2. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_regional') }}
    where METRIC = 'regional_expenditure'
      and PERIOD_TYPE = 'benchmark_year_3'

),

regional_current as (

    {#- [E] Regional expenditures, latest quarter column CMS has populated. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_regional') }}
    where METRIC = 'regional_expenditure'
      and IS_LATEST_QUARTER

),

national_weight as (

    {#- [G] -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_regional') }}
    where METRIC = 'national_weight'
      and IS_LATEST_QUARTER

),

regional_weight as (

    {#- [H] -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_regional') }}
    where METRIC = 'regional_weight'
      and IS_LATEST_QUARTER

),

accountable_care_prospective_trend as (

    {#- [J] BNMRK Table 6 section F, at the agreement performance year. Absent
        from the March preliminary delivery, which is why this join is a left
        join and why IS_CALCULABLE exists. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID,
        PY_LABEL            as PY_LABEL,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_benchmark_acpt') }}
    where SECTION_CODE = 'F'

),

historical_benchmark as (

    {#- [L] BNMRK Table 1 section L, blended Benchmark column. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_benchmark_historical') }}
    where SECTION_CODE = 'L'
      and BY_LABEL = 'Benchmark'

),

person_years as (

    {#- [N] ACO-specific person years, by enrollment type and in total. The
        total is a row of the same section, not a sum of the four: CMS rounds
        each row independently and the four do not add up to it. -#}
    select
        ACO_ID              as ACO_ID,
        PERFORMANCE_YEAR    as PERFORMANCE_YEAR,
        PERIOD              as PERIOD,
        SUBMISSION_ID       as SUBMISSION_ID,
        ENROLLMENT_TYPE     as ENROLLMENT_TYPE,
        VALUE_NUMERIC       as VALUE_NUMERIC
    from {{ ref('int_expenditures_quarterly') }}
    where METRIC = 'person_years'
      and COLUMN_VARIANT = 'aco_specific'

),

inputs as (

    select
        spine.ACO_ID                                    as ACO_ID,
        spine.PERFORMANCE_YEAR                          as PERFORMANCE_YEAR,
        spine.PERIOD                                    as PERIOD,
        spine.QUARTER_NUM                               as QUARTER_NUM,
        spine.QUARTERLY_SUBMISSION_ID                   as QUARTERLY_SUBMISSION_ID,
        spine.BENCHMARK_SUBMISSION_ID                   as BENCHMARK_SUBMISSION_ID,
        spine.IS_LATEST_BENCHMARK_SUBMISSION            as IS_LATEST_BENCHMARK_SUBMISSION,
        spine.ACPT_PERFORMANCE_YEAR_LABEL               as ACPT_PERFORMANCE_YEAR_LABEL,
        spine.IS_AGREEMENT_DEFAULTED                    as IS_AGREEMENT_DEFAULTED,
        spine.ENROLLMENT_TYPE                           as ENROLLMENT_TYPE,
        spine.ENROLLMENT_TYPE_LABEL                     as ENROLLMENT_TYPE_LABEL,
        spine.ENROLLMENT_TYPE_SORT                      as ENROLLMENT_TYPE_SORT,

        national_base.BENCHMARK_YEAR                    as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
        national_base.SUBMISSION_ID                     as ANNUAL_EXPENDITURE_SUBMISSION_ID,

        national_base.VALUE_NUMERIC                     as NATIONAL_BASE_EXPENDITURE_PER_CAPITA,
        national_current.VALUE_NUMERIC                  as NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
        regional_base.VALUE_NUMERIC                     as REGIONAL_BASE_EXPENDITURE_PER_CAPITA,
        regional_current.VALUE_NUMERIC                  as REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
        national_weight.VALUE_NUMERIC                   as NATIONAL_WEIGHT,
        regional_weight.VALUE_NUMERIC                   as REGIONAL_WEIGHT,
        accountable_care_prospective_trend.VALUE_NUMERIC
                                                        as ACCOUNTABLE_CARE_PROSPECTIVE_TREND,
        historical_benchmark.VALUE_NUMERIC              as HISTORICAL_BENCHMARK_EXPENDITURE,
        person_years.VALUE_NUMERIC                      as PERSON_YEARS,
        total_person_years.VALUE_NUMERIC                as TOTAL_PERSON_YEARS

    from spine

    left join national_base
        on spine.ACO_ID = national_base.ACO_ID
       and spine.PERFORMANCE_YEAR = national_base.PERFORMANCE_YEAR
       and spine.BENCHMARK_SUBMISSION_ID = national_base.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = national_base.ENROLLMENT_TYPE

    left join national_current
        on spine.ACO_ID = national_current.ACO_ID
       and spine.PERFORMANCE_YEAR = national_current.PERFORMANCE_YEAR
       and spine.PERIOD = national_current.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = national_current.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = national_current.ENROLLMENT_TYPE

    left join regional_base
        on spine.ACO_ID = regional_base.ACO_ID
       and spine.PERFORMANCE_YEAR = regional_base.PERFORMANCE_YEAR
       and spine.PERIOD = regional_base.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = regional_base.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = regional_base.ENROLLMENT_TYPE

    left join regional_current
        on spine.ACO_ID = regional_current.ACO_ID
       and spine.PERFORMANCE_YEAR = regional_current.PERFORMANCE_YEAR
       and spine.PERIOD = regional_current.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = regional_current.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = regional_current.ENROLLMENT_TYPE

    left join national_weight
        on spine.ACO_ID = national_weight.ACO_ID
       and spine.PERFORMANCE_YEAR = national_weight.PERFORMANCE_YEAR
       and spine.PERIOD = national_weight.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = national_weight.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = national_weight.ENROLLMENT_TYPE

    left join regional_weight
        on spine.ACO_ID = regional_weight.ACO_ID
       and spine.PERFORMANCE_YEAR = regional_weight.PERFORMANCE_YEAR
       and spine.PERIOD = regional_weight.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = regional_weight.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = regional_weight.ENROLLMENT_TYPE

    left join accountable_care_prospective_trend
        on spine.ACO_ID = accountable_care_prospective_trend.ACO_ID
       and spine.PERFORMANCE_YEAR = accountable_care_prospective_trend.PERFORMANCE_YEAR
       and spine.BENCHMARK_SUBMISSION_ID = accountable_care_prospective_trend.SUBMISSION_ID
       and spine.ACPT_PERFORMANCE_YEAR_LABEL = accountable_care_prospective_trend.PY_LABEL
       and spine.ENROLLMENT_TYPE = accountable_care_prospective_trend.ENROLLMENT_TYPE

    left join historical_benchmark
        on spine.ACO_ID = historical_benchmark.ACO_ID
       and spine.PERFORMANCE_YEAR = historical_benchmark.PERFORMANCE_YEAR
       and spine.BENCHMARK_SUBMISSION_ID = historical_benchmark.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = historical_benchmark.ENROLLMENT_TYPE

    left join person_years
        on spine.ACO_ID = person_years.ACO_ID
       and spine.PERFORMANCE_YEAR = person_years.PERFORMANCE_YEAR
       and spine.PERIOD = person_years.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = person_years.SUBMISSION_ID
       and spine.ENROLLMENT_TYPE = person_years.ENROLLMENT_TYPE

    left join person_years as total_person_years
        on spine.ACO_ID = total_person_years.ACO_ID
       and spine.PERFORMANCE_YEAR = total_person_years.PERFORMANCE_YEAR
       and spine.PERIOD = total_person_years.PERIOD
       and spine.QUARTERLY_SUBMISSION_ID = total_person_years.SUBMISSION_ID
       and total_person_years.ENROLLMENT_TYPE = 'total'

),

update_factors as (

    {#- [C] = [B] / [A], [F] = [E] / [D], [O] = [N]_type / [N]_total -#}
    select
        inputs.*,

        {{ safe_divide('NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA',
                       'NATIONAL_BASE_EXPENDITURE_PER_CAPITA') }}
                                        as NATIONAL_EXPENDITURE_UPDATE_FACTOR,

        {{ safe_divide('REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA',
                       'REGIONAL_BASE_EXPENDITURE_PER_CAPITA') }}
                                        as REGIONAL_EXPENDITURE_UPDATE_FACTOR,

        {{ safe_divide('PERSON_YEARS', 'TOTAL_PERSON_YEARS') }}
                                        as ENROLLMENT_PROPORTION

    from inputs

),

blended as (

    {#- [I] = ([C] x [G]) + ([F] x [H]). NULL in any of the four gives NULL. -#}
    select
        update_factors.*,

        {{ to_double('NATIONAL_EXPENDITURE_UPDATE_FACTOR') }}
            * {{ to_double('NATIONAL_WEIGHT') }}
        + {{ to_double('REGIONAL_EXPENDITURE_UPDATE_FACTOR') }}
            * {{ to_double('REGIONAL_WEIGHT') }}
                                        as NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR

    from update_factors

),

three_way_blended as (

    {#- [K] = (2/3)[I] + (1/3)[J]. The two thirds are cast to double before
        the division rather than written as bare literals, because a bare
        literal quotient is not the same number on every adapter. DuckDB's `/`
        always returns DOUBLE, so `2 / 3` there is 0.6666666666666666.
        Snowflake divides in fixed point and derives the result scale from the
        operands: `S = max(S1, min(S1 + 6, 12))`, so `2 / 3` at scale 0 yields
        six fractional digits, 0.666667, and `2.0 / 3.0` at scale 1 yields
        seven. Weighting a benchmark with 0.666667 moves it in the sixth
        significant digit. -#}
    select
        blended.*,

        ( {{ to_double(2) }} / {{ to_double(3) }} )
            * NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR
        + ( {{ to_double(1) }} / {{ to_double(3) }} )
            * {{ to_double('ACCOUNTABLE_CARE_PROSPECTIVE_TREND') }}
                                        as THREE_WAY_BLENDED_UPDATE_FACTOR

    from blended

),

projected as (

    {#- [M] = [K] x [L] -#}
    select
        three_way_blended.*,

        THREE_WAY_BLENDED_UPDATE_FACTOR
            * {{ to_double('HISTORICAL_BENCHMARK_EXPENDITURE') }}
                                        as PROJECTED_UPDATED_BENCHMARK_EXPENDITURE

    from three_way_blended

)

select
    ACO_ID                                              as ACO_ID,
    PERFORMANCE_YEAR                                    as PERFORMANCE_YEAR,
    PERIOD                                              as PERIOD,
    QUARTER_NUM                                         as QUARTER_NUM,
    BENCHMARK_SUBMISSION_ID                             as BENCHMARK_SUBMISSION_ID,
    IS_LATEST_BENCHMARK_SUBMISSION                      as IS_LATEST_BENCHMARK_SUBMISSION,
    ENROLLMENT_TYPE                                     as ENROLLMENT_TYPE,
    ENROLLMENT_TYPE_LABEL                               as ENROLLMENT_TYPE_LABEL,
    ENROLLMENT_TYPE_SORT                                as ENROLLMENT_TYPE_SORT,

    NATIONAL_BASE_EXPENDITURE_PER_CAPITA                as NATIONAL_BASE_EXPENDITURE_PER_CAPITA,
    NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA             as NATIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
    NATIONAL_EXPENDITURE_UPDATE_FACTOR                  as NATIONAL_EXPENDITURE_UPDATE_FACTOR,
    REGIONAL_BASE_EXPENDITURE_PER_CAPITA                as REGIONAL_BASE_EXPENDITURE_PER_CAPITA,
    REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA             as REGIONAL_CURRENT_EXPENDITURE_PER_CAPITA,
    REGIONAL_EXPENDITURE_UPDATE_FACTOR                  as REGIONAL_EXPENDITURE_UPDATE_FACTOR,
    NATIONAL_WEIGHT                                     as NATIONAL_WEIGHT,
    REGIONAL_WEIGHT                                     as REGIONAL_WEIGHT,
    NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR             as NATIONAL_REGIONAL_BLENDED_UPDATE_FACTOR,
    ACCOUNTABLE_CARE_PROSPECTIVE_TREND                  as ACCOUNTABLE_CARE_PROSPECTIVE_TREND,
    THREE_WAY_BLENDED_UPDATE_FACTOR                     as THREE_WAY_BLENDED_UPDATE_FACTOR,
    HISTORICAL_BENCHMARK_EXPENDITURE                    as HISTORICAL_BENCHMARK_EXPENDITURE,
    PROJECTED_UPDATED_BENCHMARK_EXPENDITURE             as PROJECTED_UPDATED_BENCHMARK_EXPENDITURE,
    PERSON_YEARS                                        as PERSON_YEARS,
    TOTAL_PERSON_YEARS                                  as TOTAL_PERSON_YEARS,
    ENROLLMENT_PROPORTION                               as ENROLLMENT_PROPORTION,

    PROJECTED_UPDATED_BENCHMARK_EXPENDITURE is not null  as IS_CALCULABLE,

    QUARTERLY_SUBMISSION_ID                             as QUARTERLY_SUBMISSION_ID,
    ANNUAL_EXPENDITURE_BENCHMARK_YEAR                   as ANNUAL_EXPENDITURE_BENCHMARK_YEAR,
    ANNUAL_EXPENDITURE_SUBMISSION_ID                    as ANNUAL_EXPENDITURE_SUBMISSION_ID,
    ACPT_PERFORMANCE_YEAR_LABEL                         as ACPT_PERFORMANCE_YEAR_LABEL,
    IS_AGREEMENT_DEFAULTED                              as IS_AGREEMENT_DEFAULTED

from projected
