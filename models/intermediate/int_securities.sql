-- One row per security (CUSIP) with a display name: the issuer name and class most often reported for it, and
-- whether it looks like an operating company's common stock rather than a fund, ETF, preferred share or warrant.
-- The classification is a name-based heuristic (decision 010).
with names as (
    select cusip, issuer_name, title_of_class, count(*) as lines
    from {{ ref('stg_sec__holding_lines') }}
    where amount_type = 'SH' and put_call is null
    group by cusip, issuer_name, title_of_class
),

best as (
    select cusip, issuer_name, title_of_class, lines as lines_with_this_name
    from names
    qualify row_number() over (partition by cusip order by lines desc, issuer_name, title_of_class) = 1
)

select
    cusip,
    issuer_name,
    title_of_class,
    lines_with_this_name,
    not (
        -- funds and exchange-traded products
           upper(issuer_name) like '%ETF%'      or upper(title_of_class) like '%ETF%'
        or upper(issuer_name) like '%ISHARES%'  or upper(issuer_name) like '%SPDR%'
        or upper(issuer_name) like '%PROSHARES%' or upper(issuer_name) like '%INVESCO QQQ%'
        or upper(issuer_name) like 'VANGUARD%'  or upper(issuer_name) like '%SELECT SECTOR%'
        or upper(issuer_name) like '%WISDOMTREE%' or upper(issuer_name) like '%DIREXION%'
        or upper(issuer_name) like '%VANECK%'   or upper(issuer_name) like '%SCHWAB STRATEGIC%'
        or upper(issuer_name) like '% FUND%'    or upper(issuer_name) like '% FD%'
        or upper(issuer_name) like '%INDEX%'    or upper(issuer_name) like '% ETN%'
        -- securities that are not common equity
        or upper(title_of_class) like '%PFD%'   or upper(title_of_class) like '%PREF%'
        or upper(title_of_class) like '%WARRANT%' or upper(title_of_class) like '%RIGHT%'
        or upper(title_of_class) like '%NOTE%'  or upper(title_of_class) like '%UNIT%'
    ) as is_common_equity
from best
