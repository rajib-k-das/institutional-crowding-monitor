{#-
    The models run on two warehouses: DuckDB (local development and CI) and Snowflake.
    Where the SQL differs, a macro picks the right version for the target (dbt's adapter.dispatch).
-#}

{#- SEC dates are DD-MON-YYYY, e.g. 10-FEB-2024. Unparseable values become null and are caught by tests. -#}
{% macro parse_sec_date(column) %}{{ return(adapter.dispatch('parse_sec_date')(column)) }}{% endmacro %}
{% macro duckdb__parse_sec_date(column) %}cast(try_strptime({{ column }}, '%d-%b-%Y') as date){% endmacro %}
{% macro snowflake__parse_sec_date(column) %}try_to_date({{ column }}, 'DD-MON-YYYY'){% endmacro %}

{#- Text to number; blanks and non-numeric text become null. -#}
{% macro to_number(column, type='bigint') %}{{ return(adapter.dispatch('to_number')(column, type)) }}{% endmacro %}
{% macro duckdb__to_number(column, type) %}try_cast(nullif(trim({{ column }}), '') as {{ type }}){% endmacro %}
{% macro snowflake__to_number(column, type) %}try_cast(nullif(trim({{ column }}), '') as {{ 'number(38,0)' if type == 'bigint' else type }}){% endmacro %}

{#- Reported values and share counts. DuckDB keeps whole numbers and divides them as doubles; Snowflake would divide
    NUMBER(38,0) with only 6-12 decimal places, enough to blur tiny ratios (a swapped filing's ~1/price²), so on
    Snowflake these are FLOAT, exact for whole numbers below 2^53 (decision 015). -#}
{% macro to_measure(column) %}{{ return(adapter.dispatch('to_measure')(column)) }}{% endmacro %}
{% macro duckdb__to_measure(column) %}try_cast(nullif(trim({{ column }}), '') as bigint){% endmacro %}
{% macro snowflake__to_measure(column) %}try_cast(nullif(trim({{ column }}), '') as float){% endmacro %}

{#- Saturday or Sunday. ISO day numbers (Monday = 1) do not depend on a session's week-start setting. -#}
{% macro is_weekend(column) %}{{ return(adapter.dispatch('is_weekend')(column)) }}{% endmacro %}
{% macro duckdb__is_weekend(column) %}isodow({{ column }}) in (6, 7){% endmacro %}
{% macro snowflake__is_weekend(column) %}dayofweekiso({{ column }}) in (6, 7){% endmacro %}
