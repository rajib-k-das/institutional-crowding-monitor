-- 02_features.sql: Snowflake features on the built warehouse (docs/snowflake_guide.md, step 9).
-- Run one block at a time in a Snowsight worksheet (select the lines, then Cmd+Enter) and screenshot each result.

use role crowding_transformer;
use warehouse crowding_wh;

-- A. Zero-copy clone: a full copy of the whole warehouse in seconds. No data is copied; the clone shares storage
--    with the original until either side changes.
create or replace database crowding_dev clone crowding;
select count(*) as decile_rows_in_clone from crowding_dev.marts.fct_crowding_deciles;

-- B. Time Travel: delete rows in the clone, read the table as it was before the delete, then put the rows back.
delete from crowding_dev.marts.fct_crowding_deciles where crowding_decile = 10;
set delete_query = last_query_id();
select count(*) as rows_after_delete from crowding_dev.marts.fct_crowding_deciles;
select count(*) as rows_before_delete
from crowding_dev.marts.fct_crowding_deciles before (statement => $delete_query);
insert into crowding_dev.marts.fct_crowding_deciles
select * from crowding_dev.marts.fct_crowding_deciles before (statement => $delete_query)
where crowding_decile = 10;
select count(*) as rows_after_restore from crowding_dev.marts.fct_crowding_deciles;

-- C. UNDROP: a dropped table comes back.
drop table crowding_dev.marts.dim_security;
undrop table crowding_dev.marts.dim_security;
select count(*) as dim_security_rows_after_undrop from crowding_dev.marts.dim_security;

-- D. Role-based access: the analyst role reads the marts but not the raw filings.
use role crowding_analyst;
select issuer_name, holders_previous_quarter, holders_at_deadline, round(100 * breadth_change, 1) as breadth_change_pct
from crowding.marts.fct_security_quarter
where quarter_index = (select max(quarter_index) from crowding.marts.fct_security_quarter where breadth_change is not null)
  and is_common_equity and not is_likely_corporate_event and holders_previous_quarter >= 10
order by breadth_change desc
limit 10;
select count(*) from crowding.raw.infotable;   -- expected to FAIL: the analyst has no access to raw data
use role crowding_transformer;

-- E. MATCH_RECOGNIZE: the longest runs of rising ownership, found by row pattern matching.
select issuer_name, first_period, last_period, quarters_rising, reversed_after
from crowding.marts.fct_breadth_streaks_mr
order by quarters_rising desc, total_breadth_change desc
limit 10;

-- F. Clean up the clone.
drop database crowding_dev;
