-- One row per line of a filing's information table, typed. A security can appear on several lines of the
-- same filing (split by investment discretion or by other managers); lines are combined in intermediate.
select
    trim(accession_number)                         as accession_number,
    {{ to_number('infotable_sk') }}                as line_id,
    upper(trim(cusip))                             as cusip,
    trim(nameofissuer)                             as issuer_name,
    trim(titleofclass)                             as title_of_class,
    nullif(trim(figi), '')                         as figi,
    {{ to_number('value') }}                       as reported_value,
    {{ to_number('sshprnamt') }}                   as amount,
    upper(trim(sshprnamttype))                     as amount_type,      -- SH = shares, PRN = principal amount
    upper(nullif(trim(putcall), ''))               as put_call,         -- PUT / CALL for options, else null
    upper(nullif(trim(investmentdiscretion), ''))  as investment_discretion,
    nullif(trim(othermanager), '')                 as other_manager,
    source_data_set
from {{ source('raw', 'infotable') }}
