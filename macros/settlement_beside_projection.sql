{#-
    The settlement columns the savings and benchmark facts carry beside the
    projection (TUVA-160), in one place, so the facts and their test read the
    same list.

    A performance year is settled when fct_settlement has a row for the ACO
    and year. The facts then carry CMS's final figures under SETTLEMENT_<field>
    next to the projection's own columns, which stay exactly as they are; on
    a year without a settlement every one of them is NULL and IS_SETTLED is
    false. The figures are copied from fct_settlement, never recomputed.

    Each entry: (fct_settlement field, fact column).
-#}

{#- The ACO-year facts (fct_projected_savings, its _current version and
    fact_benchmark_aco_quarter): the figures a reader sets against the
    projected savings verdict. -#}
{%- macro settlement_outcome_columns() -%}
    {{ return([
        ('SUBMISSION_ID',                  'SETTLEMENT_SUBMISSION_ID'),
        ('UPDATED_BENCHMARK',              'SETTLEMENT_UPDATED_BENCHMARK'),
        ('PER_CAPITA_EXPENDITURE',         'SETTLEMENT_PER_CAPITA_EXPENDITURE'),
        ('TOTAL_SAVINGS',                  'SETTLEMENT_TOTAL_SAVINGS'),
        ('TOTAL_LOSSES',                   'SETTLEMENT_TOTAL_LOSSES'),
        ('MINIMUM_SAVINGS_RATE',           'SETTLEMENT_MINIMUM_SAVINGS_RATE'),
        ('SAVINGS_OR_LOSSES_REALIZED',     'SETTLEMENT_SAVINGS_OR_LOSSES_REALIZED'),
        ('FINAL_SHARING_RATE',             'SETTLEMENT_FINAL_SHARING_RATE'),
        ('SHARED_SAVINGS',                 'SETTLEMENT_SHARED_SAVINGS'),
        ('EARNED_PERFORMANCE_PAYMENT',     'SETTLEMENT_EARNED_PERFORMANCE_PAYMENT'),
        ('NET_EARNED_PERFORMANCE_PAYMENT', 'SETTLEMENT_NET_EARNED_PERFORMANCE_PAYMENT'),
        ('PAYMENT_DUE_TO_CMS',             'SETTLEMENT_PAYMENT_DUE_TO_CMS')
    ]) }}
{%- endmacro -%}

{#- The enrollment-type facts (fct_projected_benchmark_by_enrollment_type and
    its _current version): fct_settlement's per-type fields, `<field>_<TYPE>`,
    read at the row's own type. -#}
{%- macro settlement_enrollment_type_columns() -%}
    {{ return([
        ('UPDATED_BENCHMARK',                        'SETTLEMENT_UPDATED_BENCHMARK'),
        ('UPDATED_BENCHMARK_BENEFICIARY_PROPORTION', 'SETTLEMENT_BENEFICIARY_PROPORTION'),
        ('PER_CAPITA_EXPENDITURE',                   'SETTLEMENT_PER_CAPITA_EXPENDITURE')
    ]) }}
{%- endmacro -%}

{#- fct_settlement's per-type field `<field>_<TYPE>` at the type in
    `type_column`; NULL for a type that is not one of the four. -#}
{%- macro settlement_field_at_type(relation_alias, field, type_column) -%}
case {{ type_column }}
    {%- for enrollment_type in settlement_enrollment_types() %}
    when '{{ enrollment_type }}' then {{ relation_alias }}.{{ field }}_{{ enrollment_type | upper }}
    {%- endfor %}
end
{%- endmacro -%}

{#- True unless the two are equal or both NULL: a figure copied from
    fct_settlement must come through exactly, NULL included. Never NULL. -#}
{%- macro settlement_copy_differs(left, right) -%}
case
    when ({{ left }}) = ({{ right }}) or (({{ left }}) is null and ({{ right }}) is null) then false
    else true
end
{%- endmacro -%}
