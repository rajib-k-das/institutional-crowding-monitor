-- One row per security (CUSIP): name, class, and whether it counts as common equity in the crowding analysis.
select cusip, issuer_name, title_of_class, is_common_equity
from {{ ref('int_securities') }}
