{#
  CrateDB lists OBJECT sub-fields (e.g. `classification['type']`) as separate
  columns in information_schema. They are not independently insertable / DDL-able
  -- only the parent OBJECT column is. Reuse the postgres implementation, then drop
  the bracketed sub-fields so incremental INSERT column lists, contracts, and
  schema-change detection operate on real top-level columns only. See issue #10.
#}
{% macro cratedb__get_columns_in_relation(relation) -%}
  {%- set columns = postgres__get_columns_in_relation(relation) -%}
  {%- set filtered = [] -%}
  {%- for column in columns if '[' not in column.name -%}
    {%- do filtered.append(column) -%}
  {%- endfor -%}
  {{ return(filtered) }}
{%- endmacro %}

{% macro get_create_table_as_sql(temporary, relation, sql) -%}
  {{ adapter.dispatch('get_create_table_as_sql', 'cratedb')(False, relation, sql) }}
{%- endmacro %}

{% macro cratedb__get_create_table_as_sql(temporary, relation, sql) -%}
  {{ return(cratedb__create_table_as(False, relation, sql)) }}
{% endmacro %}

{% macro default__get_create_table_as_sql(temporary, relation, sql) -%}
  {{ return(cratedb__create_table_as(False, relation, sql)) }}
{% endmacro %}

{# Needs an override because CrateDB lacks support for `CREATE TEMPORARY TABLE` #}
{% macro cratedb__create_table_as(temporary, relation, sql) -%}
  {%- set unlogged = config.get('unlogged', default=false) -%}
  {%- set sql_header = config.get('sql_header', none) -%}

  {{ sql_header if sql_header is not none }}

  create {% if temporary -%}
  {%- elif unlogged -%}
    unlogged
  {%- endif %} table {{ relation }}
  {% set contract_config = config.get('contract') %}
  {% if contract_config.enforced %}
    {{ get_assert_columns_equivalent(sql) }}
  {% endif -%}
  {% if contract_config.enforced and (not temporary) -%}
      {{ get_table_columns_and_constraints() }} ;
    insert into {{ relation }} (
      {{ adapter.dispatch('get_column_names', 'dbt')() }}
    )
    {%- set sql = get_select_subquery(sql) %}
  {% else %}
    as
  {% endif %}
  (
    {{ sql }}
  );
  REFRESH TABLE {{ relation }};
{%- endmacro %}

{% macro cratedb__drop_relation(relation) -%}
  {% call statement('drop_relation', auto_begin=False) -%}
    drop {{ relation.type }} if exists {{ relation.render() }}
  {%- endcall %}
{% endmacro %}

{% macro cratedb__truncate_relation(relation) -%}
  {% call statement('truncate_relation') -%}
    delete from {{ relation }}
  {%- endcall %}
{% endmacro %}

{% macro cratedb__create_schema(relation) -%}
  {% if relation.database -%}
    {{ adapter.verify_database(relation.database) }}
  {%- endif -%}
  {%- call statement('create_schema') -%}
  {# create schema if not exists {{ relation.without_identifier().include(database=False) }} #}
    SELECT 1
  {%- endcall -%}
{% endmacro %}

{% macro cratedb__drop_schema(relation) -%}
  {% if relation.database -%}
    {{ adapter.verify_database(relation.database) }}
  {%- endif -%}
  {%- call statement('drop_schema') -%}
  {# drop schema if exists {{ relation.without_identifier().include(database=False) }} cascade #}
    SELECT 1
  {%- endcall -%}
{% endmacro %}


{# CrateDB: `COMMENT ON` not supported. #}
{% macro cratedb__alter_relation_comment(relation, comment) %}
  {% set escaped_comment = postgres_escape_comment(comment) %}
  {% if relation.type == 'materialized_view' -%}
    {% set relation_type = "materialized view" %}
  {%- else -%}
    {%- set relation_type = relation.type -%}
  {%- endif -%}
  {# comment on {{ relation_type }} {{ relation }} is {{ escaped_comment }}; #}
  SELECT 1;
{% endmacro %}

{# CrateDB: `COMMENT ON` not supported. #}
{% macro cratedb__alter_column_comment(relation, column_dict) %}
  {% set existing_columns = adapter.get_columns_in_relation(relation) | map(attribute="name") | list %}
  {% for column_name in column_dict if (column_name in existing_columns) %}
    {% set comment = column_dict[column_name]['description'] %}
    {% set escaped_comment = postgres_escape_comment(comment) %}
    {# comment on column {{ relation }}.{{ adapter.quote(column_name) if column_dict[column_name]['quote'] else column_name }} is {{ escaped_comment }}; #}
    SELECT 1;
  {% endfor %}
{% endmacro %}
