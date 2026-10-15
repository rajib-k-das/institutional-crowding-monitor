-- 03_evidence.sql: what the Snowflake run used (docs/snowflake_guide.md, step 10).
-- ACCOUNT_USAGE views lag by up to 3 hours: run this a few hours after the last build.

use role accountadmin;
use warehouse crowding_wh;

-- Credits used by the warehouse.
select warehouse_name, round(sum(credits_used), 2) as credits_used
from snowflake.account_usage.warehouse_metering_history
where start_time >= dateadd(day, -30, current_timestamp())
group by warehouse_name
order by credits_used desc;

-- Work by stage: crowding:load (PUT + COPY), crowding:dbt (models), crowding:parity (engine comparison).
select query_tag,
       count(*)                                         as queries,
       round(sum(total_elapsed_time) / 1000 / 60, 1)    as minutes,
       round(sum(bytes_scanned) / 1e9, 1)               as gb_scanned
from snowflake.account_usage.query_history
where query_tag like 'crowding:%'
  and start_time >= dateadd(day, -30, current_timestamp())
group by query_tag
order by query_tag;

-- Size of each layer.
select table_schema, count(*) as tables, sum(row_count) as rows, round(sum(bytes) / 1e9, 2) as gb
from crowding.information_schema.tables
where table_type = 'BASE TABLE'
group by table_schema
order by table_schema;

show resource monitors;
