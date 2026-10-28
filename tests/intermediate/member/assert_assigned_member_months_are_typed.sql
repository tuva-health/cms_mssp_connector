{#-
    Every assigned member-month has an enrollment type.

    An assigned month comes from an assignment-list row, and cms_alr_connector
    publishes that row's monthly EnrollFlag, which it requires to be 1-4. So
    the score column or the flag always types an assigned month, and a NULL
    type there means the flag was lost on the way (TUVA-138). Unassigned
    months may still end untyped when no eligibility span covers them; that
    is by design and not tested here.
-#}

select
    PERSON_ID,
    DATA_SOURCE,
    YEAR_MONTH,
    ALR_FILE_NAME
from {{ ref('int_member_month_risk') }}
where IS_ASSIGNED
  and ENROLLMENT_TYPE is null
