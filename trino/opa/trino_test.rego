# unit test ของ policy (policy as code: แก้สิทธิ์แล้วรัน test ก่อนใช้จริง)
#   docker run --rm -v ./opa:/policies openpolicyagent/opa:1.22.0 test /policies -v
package trino_test

import rego.v1

import data.trino

who(user, groups) := {"identity": {"user": user, "groups": groups}}

select(ctx, catalog, schema, table) := {
	"context": ctx,
	"action": {
		"operation": "SelectFromColumns",
		"resource": {"table": {"catalogName": catalog, "schemaName": schema, "tableName": table, "columns": ["x"]}},
	},
}

insert(ctx, catalog, schema, table) := {
	"context": ctx,
	"action": {
		"operation": "InsertIntoTable",
		"resource": {"table": {"catalogName": catalog, "schemaName": schema, "tableName": table}},
	},
}

airflow := who("airflow", ["etl"])

engineer := who("engineer", ["data-engineers"])

analyst := who("analyst", ["analysts"])

nobody := who("guest", [])

test_etl_writes_lakehouse if trino.allow with input as insert(airflow, "lakehouse", "silver", "orders")

test_etl_reads_shop if trino.allow with input as select(airflow, "shop", "public", "orders")

test_etl_cannot_write_shop if not trino.allow with input as insert(airflow, "shop", "public", "orders")

test_engineer_reads_silver if trino.allow with input as select(engineer, "lakehouse", "silver", "orders")

test_engineer_cannot_write if not trino.allow with input as insert(engineer, "lakehouse", "gold", "daily_sales")

test_analyst_reads_gold if trino.allow with input as select(analyst, "lakehouse", "gold", "daily_sales")

test_analyst_cannot_read_silver if not trino.allow with input as select(analyst, "lakehouse", "silver", "customers")

test_analyst_cannot_read_shop if not trino.allow with input as select(analyst, "shop", "public", "customers")

test_no_group_no_data if not trino.allow with input as select(nobody, "lakehouse", "gold", "daily_sales")

test_admin_everything if trino.allow with input as insert(who("admin", ["platform-admins"]), "shop", "public", "x")

test_analyst_sees_only_gold_schema if {
	shown := trino.batch with input as {
		"context": analyst,
		"action": {
			"operation": "FilterSchemas",
			"filterResources": [
				{"schema": {"catalogName": "lakehouse", "schemaName": "bronze"}},
				{"schema": {"catalogName": "lakehouse", "schemaName": "gold"}},
				{"schema": {"catalogName": "lakehouse", "schemaName": "silver"}},
			],
		},
	}
	shown == {1}
}

test_filter_columns_returns_column_positions if {
	shown := trino.batch with input as {
		"context": analyst,
		"action": {
			"operation": "FilterColumns",
			"filterResources": [{"table": {
				"catalogName": "lakehouse", "schemaName": "gold", "tableName": "dim_customer",
				"columns": ["customer_id", "full_name", "status"],
			}}],
		},
	}
	shown == {0, 1, 2}
}

mask(ctx, column) := {
	"context": ctx,
	"action": {
		"operation": "GetColumnMask",
		"resource": {"column": {
			"catalogName": "lakehouse", "schemaName": "gold", "tableName": "dim_customer",
			"columnName": column, "columnType": "varchar",
		}},
	},
}

test_analyst_name_masked if {
	m := trino.columnMask with input as mask(analyst, "full_name")
	m.expression == "substr(full_name, 1, 1) || '***'"
}

test_engineer_name_not_masked if not trino.columnMask with input as mask(engineer, "full_name")

test_analyst_status_not_masked if not trino.columnMask with input as mask(analyst, "status")
