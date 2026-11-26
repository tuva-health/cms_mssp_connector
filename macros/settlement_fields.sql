{#-
    The settlement (STLMT) workbook fields the settlement facts carry, in one
    place, so the facts, int_settlement_values and the tests read the same map.

    Every field is one cell, found by what labels it, never by position:

      * table:   TABLE_CODE, the sheet ('1', '2', '3', 'A1', 'A2').
      * section: SECTION_KEY, the row's `[X]` code; on Table A2, which has no
                 codes, the block (CMS_HCC or DEMOGRAPHIC); none on Table A1,
                 whose letters label its columns.
      * row:     ROW_KIND, as the pipeline writes it: CODE (the lettered row's
                 own value), TOTAL (an unlettered row closing its section) or
                 DETAIL (an enrollment-type row, or Table A1's Weighted
                 Average row).
      * column:  COLUMN_KEY, the column's letter on Table A1 and its period
                 elsewhere: BY1, BY2, BY3, PY, BENCHMARK_PERIOD (Table 2's
                 'Benchmark Period') or BENCHMARK (Table 1's 'Benchmark').

    The meanings are CMS's report footnotes (FinRec "Report Footnotes", PY2025
    template). A field's kind is 'numeric' or 'text'; Y/N flags and results
    stay text, as written.

    Each entry: (table, section, row kind, column key, field name, kind,
    per type). A per-type entry reads the four enrollment-type rows. On
    fct_settlement, one row per ACO and performance year, it becomes four
    columns, `<field>_<TYPE>`; on the facts whose grain is the enrollment
    type, it is one column, and the type is the row.
-#}

{#- The four per-type columns, in the order mssp_enrollment_type sorts them. -#}
{%- macro settlement_enrollment_types() -%}
    {{ return(['esrd', 'disabled', 'aged_dual', 'aged_non_dual']) }}
{%- endmacro -%}

{#- fct_settlement: Table 2 [A]-[I] and Table 3 [A]-[UU]. -#}
{%- macro settlement_fields() -%}
    {{ return([
        ('2', 'A',  'DETAIL', 'BENCHMARK_PERIOD', 'HISTORICAL_BENCHMARK',                    'numeric', true),
        ('2', 'A',  'TOTAL',  'BENCHMARK_PERIOD', 'HISTORICAL_BENCHMARK',                    'numeric', false),
        ('2', 'B',  'DETAIL', 'BENCHMARK_PERIOD', 'BY3_CMS_HCC_RISK_SCORE',                  'numeric', true),
        ('2', 'B',  'DETAIL', 'PY',               'PY_CMS_HCC_RISK_SCORE',                   'numeric', true),
        ('2', 'C',  'DETAIL', 'PY',               'CAPPED_RISK_RATIO',                       'numeric', true),
        ('2', 'D',  'DETAIL', 'PY',               'RISK_ADJUSTED_HISTORICAL_BENCHMARK',      'numeric', true),
        ('2', 'E',  'DETAIL', 'PY',               'NATIONAL_REGIONAL_UPDATE_FACTOR',         'numeric', true),
        ('2', 'F',  'DETAIL', 'PY',               'THREE_WAY_UPDATE_FACTOR',                 'numeric', true),
        ('2', 'G',  'DETAIL', 'PY',               'UPDATED_BENCHMARK',                       'numeric', true),
        ('2', 'H',  'DETAIL', 'PY',               'UPDATED_BENCHMARK_BENEFICIARY_PROPORTION', 'numeric', true),
        ('2', 'I',  'CODE',   'PY',               'UPDATED_BENCHMARK',                       'numeric', false),

        ('3', 'A',  'CODE',   'PY', 'ASSIGNED_BENEFICIARIES',                 'numeric', false),
        ('3', 'B',  'CODE',   'PY', 'PERSON_YEARS',                           'numeric', false),
        ('3', 'C',  'DETAIL', 'PY', 'PER_CAPITA_EXPENDITURE',                 'numeric', true),
        ('3', 'D',  'DETAIL', 'PY', 'ASSIGNED_BENEFICIARY_PROPORTION',        'numeric', true),
        ('3', 'E',  'CODE',   'PY', 'PER_CAPITA_EXPENDITURE',                 'numeric', false),
        ('3', 'F',  'CODE',   'PY', 'BENCHMARK_PER_CAPITA',                   'numeric', false),
        ('3', 'G',  'CODE',   'PY', 'TOTAL_EXPENDITURES',                     'numeric', false),
        ('3', 'H',  'CODE',   'PY', 'TOTAL_BENCHMARK_EXPENDITURES',           'numeric', false),
        ('3', 'I',  'CODE',   'PY', 'BENCHMARK_MINUS_EXPENDITURES',           'numeric', false),
        ('3', 'J',  'CODE',   'PY', 'TOTAL_SAVINGS',                          'numeric', false),
        ('3', 'K',  'CODE',   'PY', 'TOTAL_LOSSES',                           'numeric', false),
        ('3', 'L',  'CODE',   'PY', 'MINIMUM_SAVINGS_RATE',                   'numeric', false),
        ('3', 'M',  'CODE',   'PY', 'MINIMUM_LOSS_RATE',                      'numeric', false),
        ('3', 'N',  'CODE',   'PY', 'MINIMUM_SAVINGS_AMOUNT',                 'numeric', false),
        ('3', 'O',  'CODE',   'PY', 'MINIMUM_LOSS_AMOUNT',                    'numeric', false),
        ('3', 'P',  'CODE',   'PY', 'SAVINGS_OR_LOSSES_REALIZED',             'text',    false),
        ('3', 'Q',  'CODE',   'PY', 'TWO_WAY_BLEND_BENCHMARK_PER_CAPITA',     'numeric', false),
        ('3', 'R',  'CODE',   'PY', 'TWO_WAY_BLEND_TOTAL_BENCHMARK',          'numeric', false),
        ('3', 'S',  'CODE',   'PY', 'TWO_WAY_BLEND_BENCHMARK_MINUS_EXPENDITURES', 'numeric', false),
        ('3', 'T',  'CODE',   'PY', 'GUARDRAIL_APPLIES',                      'text',    false),
        ('3', 'U',  'CODE',   'PY', 'TOTAL_LOSSES_WITH_GUARDRAIL',            'numeric', false),
        ('3', 'V',  'CODE',   'PY', 'MINIMUM_LOSS_AMOUNT_WITH_GUARDRAIL',     'numeric', false),
        ('3', 'W',  'CODE',   'PY', 'LOSSES_REALIZED_WITH_GUARDRAIL',         'text',    false),
        ('3', 'X',  'CODE',   'PY', 'MAXIMUM_SHARING_RATE',                   'numeric', false),
        ('3', 'Y',  'CODE',   'PY', 'QUALITY_SCORE',                          'numeric', false),
        ('3', 'Z',  'CODE',   'PY', 'MET_QUALITY_STANDARD',                   'text',    false),
        ('3', 'AA', 'CODE',   'PY', 'MET_ALTERNATIVE_QUALITY_STANDARD',       'text',    false),
        ('3', 'BB', 'CODE',   'PY', 'MET_LOW_REVENUE_SHARING_CRITERIA',       'text',    false),
        ('3', 'CC', 'CODE',   'PY', 'FINAL_SHARING_RATE',                     'numeric', false),
        ('3', 'DD', 'CODE',   'PY', 'SHARED_LOSS_RATE',                       'numeric', false),
        ('3', 'EE', 'CODE',   'PY', 'SHARED_SAVINGS',                         'numeric', false),
        ('3', 'FF', 'CODE',   'PY', 'SHARED_SAVINGS_CAP',                     'numeric', false),
        ('3', 'GG', 'CODE',   'PY', 'SEQUESTRATION_ADJUSTMENT',               'numeric', false),
        ('3', 'HH', 'CODE',   'PY', 'EARNED_PERFORMANCE_PAYMENT',             'numeric', false),
        ('3', 'II', 'CODE',   'PY', 'APPLICABLE_PAYMENT',                     'text',    false),
        ('3', 'JJ', 'CODE',   'PY', 'MAXIMUM_AIP_RECOUPMENT',                 'numeric', false),
        ('3', 'KK', 'CODE',   'PY', 'AIP_RECOUPMENT',                         'numeric', false),
        ('3', 'LL', 'CODE',   'PY', 'AIP_STILL_OWED',                         'numeric', false),
        ('3', 'MM', 'CODE',   'PY', 'NET_EARNED_PERFORMANCE_PAYMENT',         'numeric', false),
        ('3', 'NN', 'CODE',   'PY', 'SHARED_LOSSES',                          'numeric', false),
        ('3', 'OO', 'CODE',   'PY', 'PARTICIPANT_FFS_REVENUE',                'numeric', false),
        ('3', 'PP', 'CODE',   'PY', 'SHARED_LOSSES_CAP',                      'numeric', false),
        ('3', 'QQ', 'CODE',   'PY', 'SHARED_LOSSES_AFTER_CAP',                'numeric', false),
        ('3', 'RR', 'CODE',   'PY', 'EUC_BENEFICIARY_SHARE',                  'numeric', false),
        ('3', 'SS', 'CODE',   'PY', 'EUC_YEAR_SHARE',                         'numeric', false),
        ('3', 'TT', 'CODE',   'PY', 'EUC_ADJUSTMENT',                         'numeric', false),
        ('3', 'UU', 'CODE',   'PY', 'PAYMENT_DUE_TO_CMS',                     'numeric', false)
    ]) }}
{%- endmacro -%}

{#- fct_settlement_risk: Table A1, one column per letter. Its rows are the four
    types and the Weighted Average row, which CMS fills only under [D] and [G]. -#}
{%- macro settlement_risk_fields() -%}
    {{ return([
        ('A1', none, 'DETAIL', 'A', 'RISK_SCORE_WEIGHT',          'numeric', true),
        ('A1', none, 'DETAIL', 'B', 'BY3_CMS_HCC_RISK_SCORE',     'numeric', true),
        ('A1', none, 'DETAIL', 'C', 'PY_CMS_HCC_RISK_SCORE',      'numeric', true),
        ('A1', none, 'DETAIL', 'D', 'UNCAPPED_RISK_RATIO',        'numeric', true),
        ('A1', none, 'DETAIL', 'E', 'BY3_DEMOGRAPHIC_RISK_SCORE', 'numeric', true),
        ('A1', none, 'DETAIL', 'F', 'PY_DEMOGRAPHIC_RISK_SCORE',  'numeric', true),
        ('A1', none, 'DETAIL', 'G', 'DEMOGRAPHIC_RISK_RATIO',     'numeric', true),
        ('A1', none, 'DETAIL', 'H', 'AGGREGATE_CAP',              'numeric', true),
        ('A1', none, 'DETAIL', 'I', 'FINAL_RISK_RATIO',           'numeric', true)
    ]) }}
{%- endmacro -%}

{#- The Table A1 rows: the four types, then the Weighted Average row. -#}
{%- macro settlement_risk_rows() -%}
    {{ return(settlement_enrollment_types() + ['weighted_average']) }}
{%- endmacro -%}

{#- fct_settlement_historical_benchmark: Table 1's per-type rows. [A2], [B]-[H]
    by benchmark year; [G], [K] and [L] in the 'Benchmark' column. -#}
{%- macro settlement_historical_benchmark_fields() -%}
    {%- set fields = [] -%}
    {%- for code, name in [
            ('A2', 'PERSON_YEARS'),
            ('B',  'PER_CAPITA_EXPENDITURES'),
            ('C',  'CMS_HCC_RISK_SCORE'),
            ('D',  'CMS_HCC_RISK_RATIO'),
            ('E',  'NATIONAL_REGIONAL_TREND_FACTOR'),
            ('F',  'TRENDED_PER_CAPITA_EXPENDITURES'),
            ('G',  'HISTORICAL_BENCHMARK_BEFORE_ADJUSTMENT'),
            ('H',  'ASSIGNED_BENEFICIARY_PROPORTION')
        ] -%}
        {%- for year in ['BY1', 'BY2', 'BY3'] -%}
            {%- do fields.append(('1', code, 'DETAIL', year, name ~ '_' ~ year, 'numeric', true)) -%}
        {%- endfor -%}
    {%- endfor -%}
    {%- do fields.append(('1', 'G', 'DETAIL', 'BENCHMARK', 'HISTORICAL_BENCHMARK_BEFORE_ADJUSTMENT', 'numeric', true)) -%}
    {%- do fields.append(('1', 'K', 'DETAIL', 'BENCHMARK', 'ADJUSTMENT',                             'numeric', true)) -%}
    {%- do fields.append(('1', 'L', 'DETAIL', 'BENCHMARK', 'HISTORICAL_BENCHMARK',                   'numeric', true)) -%}
    {{ return(fields) }}
{%- endmacro -%}

{#- fct_settlement_renormalization: Table A2's two blocks, by year. -#}
{%- macro settlement_renormalization_fields() -%}
    {%- set fields = [] -%}
    {%- for block in ['CMS_HCC', 'DEMOGRAPHIC'] -%}
        {%- for year in ['BY1', 'BY2', 'BY3', 'PY'] -%}
            {%- do fields.append(('A2', block, 'DETAIL', year, block ~ '_NATIONAL_MEAN_' ~ year, 'numeric', true)) -%}
        {%- endfor -%}
    {%- endfor -%}
    {{ return(fields) }}
{%- endmacro -%}

{#-
    The settlement facts: (fact, its fields, the row values its per-type
    fields are read for), and whether the fact is one row per ACO and
    performance year. On such a fact a per-type field becomes one column per
    type, `<field>_<TYPE>`; on the others the type is the row.
-#}
{%- macro settlement_facts() -%}
    {{ return([
        ('settlement',           settlement_fields(),                      settlement_enrollment_types(), true),
        ('risk',                 settlement_risk_fields(),                 settlement_risk_rows(),        false),
        ('historical_benchmark', settlement_historical_benchmark_fields(), settlement_enrollment_types(), false),
        ('renormalization',      settlement_renormalization_fields(),      settlement_enrollment_types(), false)
    ]) }}
{%- endmacro -%}

{#- A field's column name for one row value: `<field>_<TYPE>` on a fact that is
    one row per ACO and performance year, else the field's own name. -#}
{%- macro settlement_column_name(name, type, types_are_columns) -%}
    {{ return(name ~ '_' ~ (type | upper) if types_are_columns else name) }}
{%- endmacro -%}

{#-
    Every field cell, one row each: the map int_settlement_values joins its
    cells to. A per-type field is one row per enrollment type (FIELD_NAME as
    settlement_column_name gives it); a CODE or TOTAL row's ENROLLMENT_TYPE
    is 'total'.
-#}
{%- macro settlement_field_map() -%}
    {%- set rows = [] -%}
    {%- for fact, fields, types, types_are_columns in settlement_facts() -%}
        {%- for table, section, row_kind, column_key, name, kind, per_type in fields -%}
            {%- for type in (types if per_type else ['total']) -%}
                {%- do rows.append([table, section, row_kind, type, column_key, fact,
                                    settlement_column_name(name, type, types_are_columns and per_type), kind]) -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endfor -%}

    {%- for table, section, row_kind, type, column_key, fact, field_name, kind in rows %}
    select
        cast('{{ table }}' as {{ dbt.type_string() }})       as TABLE_CODE,
        cast({{ "'" ~ section ~ "'" if section is not none else 'null' }} as {{ dbt.type_string() }}) as SECTION_KEY,
        cast('{{ row_kind }}' as {{ dbt.type_string() }})    as ROW_KIND,
        cast('{{ type }}' as {{ dbt.type_string() }})        as ENROLLMENT_TYPE,
        cast('{{ column_key }}' as {{ dbt.type_string() }})  as COLUMN_KEY,
        cast('{{ fact }}' as {{ dbt.type_string() }})        as FACT,
        cast('{{ field_name }}' as {{ dbt.type_string() }})  as FIELD_NAME,
        cast('{{ kind }}' as {{ dbt.type_string() }})        as FIELD_KIND
    {{- '\n    union all' if not loop.last }}
    {%- endfor %}
{%- endmacro -%}

{#- The (column name, kind) of one fact, in map order, for its pivot. -#}
{%- macro settlement_fact_columns(fact) -%}
    {%- set columns = [] -%}
    {%- for this_fact, fields, types, types_are_columns in settlement_facts() if this_fact == fact -%}
        {%- for _table, _section, _row_kind, _column_key, name, kind, per_type in fields -%}
            {%- for type in (types if types_are_columns and per_type else [none]) -%}
                {%- do columns.append((settlement_column_name(name, type, types_are_columns and per_type), kind)) -%}
            {%- endfor -%}
        {%- endfor -%}
    {%- endfor -%}
    {{ return(columns) }}
{%- endmacro -%}
