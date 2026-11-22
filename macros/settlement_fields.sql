{#-
    The settlement workbook fields fct_settlement carries, in one place, so
    the fact and its tests read the same list.

    A field has a meaningful name only where the settlement handoff pins one
    letter to one meaning (CONFIRMED below). A field the handoff names only
    as part of a range is named by its code, T3_<code> (CODED). The layouts
    are not yet checked against a delivered workbook (TUVA-158), so TUVA-160
    or a real-workbook check renames a coded field once its meaning is
    confirmed.

    Each entry: table code, section code, column name, kind ('numeric' or
    'text'), and whether the name is 'confirmed' or 'coded'.
-#}

{%- macro settlement_table_3_fields() -%}
    {{ return([
        ('3', 'A',  'ASSIGNED_BENEFICIARIES', 'numeric', 'confirmed'),
        ('3', 'E',  'PER_CAPITA_EXPENDITURE', 'numeric', 'confirmed'),
        ('3', 'F',  'BENCHMARK_PER_CAPITA',   'numeric', 'confirmed'),
        ('3', 'G',  'T3_G',  'numeric', 'coded'),
        ('3', 'H',  'T3_H',  'numeric', 'coded'),
        ('3', 'I',  'T3_I',  'numeric', 'coded'),
        ('3', 'J',  'T3_J',  'numeric', 'coded'),
        ('3', 'L',  'T3_L',  'numeric', 'coded'),
        ('3', 'N',  'T3_N',  'numeric', 'coded'),
        ('3', 'P',  'SAVINGS_REALIZED',       'text',    'confirmed'),
        ('3', 'X',  'T3_X',  'numeric', 'coded'),
        ('3', 'Y',  'T3_Y',  'numeric', 'coded'),
        ('3', 'Z',  'T3_Z',  'numeric', 'coded'),
        ('3', 'AA', 'T3_AA', 'numeric', 'coded'),
        ('3', 'BB', 'T3_BB', 'numeric', 'coded'),
        ('3', 'CC', 'T3_CC', 'numeric', 'coded'),
        ('3', 'EE', 'T3_EE', 'numeric', 'coded'),
        ('3', 'FF', 'T3_FF', 'numeric', 'coded'),
        ('3', 'GG', 'T3_GG', 'numeric', 'coded'),
        ('3', 'HH', 'T3_HH', 'numeric', 'coded'),
        ('3', 'II', 'T3_II', 'numeric', 'coded'),
        ('3', 'JJ', 'T3_JJ', 'numeric', 'coded'),
        ('3', 'KK', 'T3_KK', 'numeric', 'coded'),
        ('3', 'LL', 'T3_LL', 'numeric', 'coded'),
        ('3', 'MM', 'T3_MM', 'numeric', 'coded')
    ]) }}
{%- endmacro -%}

{#- Table 2 [A]-[H] are per enrollment type, coded T2_<code>_<type>. -#}
{%- macro settlement_table_2_type_codes() -%}
    {{ return(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) }}
{%- endmacro -%}

{#- The four per-type columns, in the order mssp_enrollment_type sorts them. -#}
{%- macro settlement_enrollment_types() -%}
    {{ return(['esrd', 'disabled', 'aged_dual', 'aged_non_dual']) }}
{%- endmacro -%}
