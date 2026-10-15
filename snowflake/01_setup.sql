-- 01_setup.sql: run once in a Snowsight SQL worksheet, as ACCOUNTADMIN, with "Run All".
-- Before running, replace PASTE_PUBLIC_KEY_HERE (near the bottom) with your public key (docs/snowflake_guide.md, step 3).

use role accountadmin;

-- Spending guard: email at 75% of 20 credits a month, suspend the warehouse at 100%.
create or replace resource monitor crowding_monitor
    with credit_quota = 20 frequency = monthly start_timestamp = immediately
    triggers on 75 percent do notify
             on 100 percent do suspend
             on 110 percent do suspend_immediate;

-- The smallest warehouse, paused after 60 seconds idle.
create warehouse if not exists crowding_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true;
alter warehouse crowding_wh set resource_monitor = crowding_monitor;

-- Two databases: the real SEC data, and the hand-built test filings.
create database if not exists crowding;
create database if not exists crowding_test;

-- Roles: the transformer loads and builds everything; the analyst can only read the marts.
create role if not exists crowding_transformer;
create role if not exists crowding_analyst;
grant role crowding_transformer to role sysadmin;
grant role crowding_analyst to role sysadmin;
set me = current_user();
grant role crowding_transformer to user identifier($me);
grant role crowding_analyst to user identifier($me);

grant usage on warehouse crowding_wh to role crowding_transformer;
grant usage on warehouse crowding_wh to role crowding_analyst;
grant create database on account to role crowding_transformer;   -- for the zero-copy clone in 02_features.sql
grant ownership on database crowding to role crowding_transformer copy current grants;
grant ownership on database crowding_test to role crowding_transformer copy current grants;

-- The marts schema exists from the start, so the analyst's read access can be granted now and covers every table
-- dbt creates in it later.
use role crowding_transformer;
create schema if not exists crowding.marts;
use role accountadmin;
grant usage on database crowding to role crowding_analyst;
grant usage on schema crowding.marts to role crowding_analyst;
grant select on future tables in schema crowding.marts to role crowding_analyst;
grant select on future views in schema crowding.marts to role crowding_analyst;

-- The service user dbt and the loader sign in as: key pair only, no password.
create user if not exists dbt_user
    type = service
    default_role = crowding_transformer
    default_warehouse = crowding_wh
    rsa_public_key = 'PASTE_PUBLIC_KEY_HERE';
grant role crowding_transformer to user dbt_user;

-- Check: expect DBT_USER with HAS_RSA_PUBLIC_KEY = true.
show users like 'DBT_USER';
