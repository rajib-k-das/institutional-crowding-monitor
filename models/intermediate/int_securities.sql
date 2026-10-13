-- One row per security (CUSIP) with a display name: the issuer name and class most often reported for it.
with names as (
    select cusip, issuer_name, title_of_class, count(*) as lines
    from {{ ref('stg_sec__holding_lines') }}
    where amount_type = 'SH' and put_call is null
    group by cusip, issuer_name, title_of_class
)

select cusip, issuer_name, title_of_class, lines as lines_with_this_name
from names
qualify row_number() over (partition by cusip order by lines desc, issuer_name, title_of_class) = 1
