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
