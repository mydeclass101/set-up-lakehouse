# สิทธิ์ของ Trino (Open Policy Agent)
#
# ทุกครั้งที่จะทำอะไร Trino ถาม OPA ว่า "ผู้ใช้ X (อยู่กลุ่ม G) ทำ operation Y กับ catalog.schema.table นี้ได้ไหม"
#   allow       = ตอบ true / false ทีละเรื่อง
#   batch       = ตอบทีละหลายรายการ (ตอน SHOW / DBeaver ดึงรายชื่อ schema, ตาราง, คอลัมน์) → ซ่อนสิ่งที่ไม่มีสิทธิ์
#   columnMask  = คอลัมน์ไหนต้องปิดบังสำหรับใคร
# กลุ่มมาจาก LDAP (ldap/seed/directory.ldif) · แก้ไฟล์นี้แล้ว: รัน test → docker compose restart opa
package trino

import rego.v1

# ---------------------------------------------------------------------------
# 1. สิทธิ์ต่อกลุ่ม (แก้ตรงนี้ที่เดียว)
#    read  = SELECT, ดูรายชื่อ schema / ตาราง / คอลัมน์
#    write = INSERT / MERGE / UPDATE / DELETE / CREATE / ALTER / DROP / CALL
#    schema "*" = ทุก schema ใน catalog นั้น
# ---------------------------------------------------------------------------
grants := {
	"etl": [
		{"catalog": "shop", "schema": "*", "write": false},
		{"catalog": "raw", "schema": "*", "write": true},
		{"catalog": "lakehouse", "schema": "*", "write": true},
	],
	"data-engineers": [
		{"catalog": "shop", "schema": "*", "write": false},
		{"catalog": "raw", "schema": "*", "write": false},
		{"catalog": "lakehouse", "schema": "*", "write": false},
	],
	"analysts": [{"catalog": "lakehouse", "schema": "gold", "write": false}],
}

# ทุกคนที่ login ได้: catalog system (metadata ที่ DBeaver / JDBC ใช้ และฟังก์ชันพื้นฐานอย่าง sum, date_trunc)
everyone := [{"catalog": "system", "schema": "*", "write": false}]

# ข้อมูลส่วนตัวลูกค้า: ปิดบังสำหรับทุกคน ยกเว้นกลุ่มใน unmasked_groups
masks := {
	"lakehouse.gold.dim_customer.full_name": "substr(full_name, 1, 1) || '***'",
	"lakehouse.gold.dim_customer.birth_date": "date_trunc('year', birth_date)",
}

unmasked_groups := {"platform-admins", "etl", "data-engineers"}

# ---------------------------------------------------------------------------
# 2. กลไก (ปกติไม่ต้องแก้)
# ---------------------------------------------------------------------------
user := input.context.identity.user

groups := {g | some g in object.get(input.context.identity, "groups", [])}

is_admin if "platform-admins" in groups

my_grants contains g if {
	some group in groups
	some g in grants[group]
}

my_grants contains g if some g in everyone

# operation ที่อ่านอย่างเดียว · operation อื่นทั้งหมดถือว่าเป็นการเขียน
read_operations := {
	"AccessCatalog", "FilterCatalogs",
	"ShowSchemas", "FilterSchemas", "ShowCreateSchema",
	"ShowTables", "FilterTables", "ShowColumns", "FilterColumns", "ShowCreateTable",
	"SelectFromColumns",
	"ShowFunctions", "FilterFunctions", "ExecuteFunction",
	"SetCatalogSessionProperty",
}

# operation ส่วนตัว: query ของตัวเอง ดู / ยกเลิกได้
own_query_operations := {"ViewQueryOwnedBy", "FilterViewQueryOwnedBy", "KillQueryOwnedBy"}

# resource ที่ถูกถามอยู่ใน catalog / schema ไหน ("*" = ถามระดับ catalog)
location := {"catalog": r.catalogName, "schema": r.schemaName} if {
	r := input.action.resource.table
} else := {"catalog": r.catalogName, "schema": r.schemaName} if {
	r := input.action.resource.schema
} else := {"catalog": r.catalogName, "schema": r.schemaName} if {
	r := input.action.resource.function
} else := {"catalog": input.action.resource.catalog.name, "schema": "*"} if {
	input.action.resource.catalog
} else := {"catalog": input.action.resource.catalogSessionProperty.catalogName, "schema": "*"}

covers(g) if {
	g.catalog == location.catalog
	g.schema in {"*", location.schema}
}

# ถามระดับ catalog หรือ information_schema: มีสิทธิ์ schema ใดก็ได้ใน catalog นั้นก็พอ (เพื่อให้มองเห็น catalog)
covers(g) if {
	g.catalog == location.catalog
	location.schema in {"*", "information_schema"}
}

default allow := false

allow if is_admin

allow if input.action.operation == "ExecuteQuery"

allow if {
	input.action.operation in own_query_operations
	input.action.resource.user.user == user
}

allow if {
	input.action.operation in read_operations
	some g in my_grants
	covers(g)
}

allow if {
	not input.action.operation in read_operations
	not input.action.operation in own_query_operations
	some g in my_grants
	g.write
	covers(g)
}

# batch: คืนเลขลำดับของรายการที่อนุญาต
batch contains i if {
	input.action.operation != "FilterColumns"
	some i, resource in input.action.filterResources
	allow with input.action.resource as resource
}

# FilterColumns ส่งมาเป็นตารางเดียวที่มีหลายคอลัมน์ → เลขลำดับ = ลำดับคอลัมน์
batch contains i if {
	input.action.operation == "FilterColumns"
	table := input.action.filterResources[0].table
	some i, column in table.columns
	allow with input.action.resource as {"table": object.union(table, {"columns": [column]})}
}

columnMask := {"expression": expression} if {
	count(groups & unmasked_groups) == 0
	c := input.action.resource.column
	expression := masks[concat(".", [c.catalogName, c.schemaName, c.tableName, c.columnName])]
}
