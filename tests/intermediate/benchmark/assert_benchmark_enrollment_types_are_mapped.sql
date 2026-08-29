{#-
    No enrollment type label may reach the intermediate models unrecognised.

    The models never drop a row they cannot map — they mark it `unmapped` and
    keep it, so a new or reworded CMS label is visible in the data rather than
    silently missing from it. This test is the other half of that policy: it
    turns visible into loud.

    An `unmapped` row means one of three things, in rough order of likelihood:
    CMS reworded a label and the seed needs the new spelling; CMS added an
    enrollment cohort and the seed needs a new canonical key; or a section that
    is not split by enrollment type gained a row whose label no longer repeats
    its heading, in which case the aggregate rule in the model needs revisiting.
    All three want a human, which is why this is an error and not a warning.

    Scope note: the AEXPU and QEXPU Table 1 models leave `ENROLLMENT_TYPE` NULL
    outside the sections CMS names for enrollment type, because a row labelled
    `Ambulance` is a service category rather than an unmapped cohort. NULL is
    therefore not a failure here; only `unmapped` is.
-#}

{%- set models = [
    'int_benchmark_historical',
    'int_benchmark_acpt',
    'int_benchmark_trend',
    'int_expenditures_annual',
    'int_expenditures_quarterly',
    'int_expenditures_regional'
] -%}

{% for model_name in models %}

    select
        '{{ model_name }}'  as MODEL_NAME,
        SECTION_LABEL       as SECTION_LABEL,
        ROW_LABEL           as ROW_LABEL,
        count(*)            as UNMAPPED_ROW_COUNT
    from {{ ref(model_name) }}
    where ENROLLMENT_TYPE = 'unmapped'
    group by SECTION_LABEL, ROW_LABEL

{%- if not loop.last %}

    union all

{% endif %}
{%- endfor %}
