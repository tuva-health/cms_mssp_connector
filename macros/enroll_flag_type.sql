{#-
    The MSSP enrollment type an ALR Table 1-1 EnrollFlag states, per the CMS
    ALR data dictionary: 1 esrd, 2 disabled, 3 aged_dual, 4 aged_non_dual.
    Any other value, 0 (not eligible) included, maps to NULL. Shared by
    int_member_month_risk and int_settlement_member_month_risk (TUVA-162), so
    the projection and the settlement type a month alike. `flag` is an
    integer expression.
-#}
{% macro enroll_flag_type(flag) -%}
    case {{ flag }}
        when 1 then 'esrd'
        when 2 then 'disabled'
        when 3 then 'aged_dual'
        when 4 then 'aged_non_dual'
    end
{%- endmacro %}
