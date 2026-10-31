# Trino (compute layer)

| ไฟล์ | คืออะไร |
|---|---|
| `catalog/lakehouse.properties` | Iceberg บน RustFS (REST catalog `http://rustfs:9000/iceberg`) อ่าน / เขียน bronze, silver, gold |
| `catalog/raw.properties` | ไฟล์ CSV / JSON ใน bucket `raw` (Hive connector, metastore เก็บที่ `s3://raw/_trino_metastore`) |
| `catalog/shop.properties` | postgres ของร้าน (`shop-db`) ผ่าน role `student` อ่านอย่างเดียว |
| `etc/config.properties` | HTTPS port 8443 + login ด้วยรหัสผ่าน |
| `etc/password-authenticator.properties` | เช็กรหัสผ่านกับ LDAP (`ldap/`) |
| `etc/group-provider.properties` | ดึงกลุ่มของผู้ใช้จาก LDAP |
| `etc/access-control.properties` | ถามสิทธิ์จาก OPA |
| `opa/trino.rego` | **policy สิทธิ์** ใครอ่าน / เขียนอะไรได้ คอลัมน์ไหนปิดบัง · `opa/trino_test.rego` = unit test |
| `init/make_certs.sh` | สร้าง TLS cert ครั้งแรก → `certs/private/` (key ของ Trino) และ `certs/public/trino.pem` (แจก client) |

ชื่อตารางใน Trino = `catalog.schema.table` เช่น `lakehouse.gold.daily_sales`, `shop.public.orders`

เปิด Trino ใหม่ catalog `lakehouse` จะว่าง ยังไม่มี schema / ตาราง: ตารางถูกสร้างโดย pipeline ที่เป็นเจ้าของตอนรันครั้งแรก
(`CREATE TABLE IF NOT EXISTS` หัวไฟล์ SQL ใน `airflow/dags/lakehouse/sql/`) Trino เป็นแค่ engine ไม่ต้องรู้ว่าธุรกิจมีตารางอะไร

## Security: ใครเป็นใคร แล้วทำอะไรได้

```
DBeaver / Airflow ──HTTPS + user/password──▶ Trino ──เช็กรหัส + ดูกลุ่ม──▶ LDAP
                                              │
                                              └──"analyst (analysts) SELECT gold.daily_sales ได้ไหม"──▶ OPA ──▶ allow / deny / mask
```

| กลุ่ม (ใน LDAP) | ผู้ใช้ | shop | raw | lakehouse | ข้อมูลส่วนตัวลูกค้า |
|---|---|---|---|---|---|
| platform-admins | admin | ทุกอย่าง | ทุกอย่าง | ทุกอย่าง | เห็น |
| etl | airflow | อ่าน | อ่าน / เขียน | อ่าน / เขียน | เห็น |
| data-engineers | engineer | อ่าน | อ่าน | อ่าน | เห็น |
| analysts | analyst | - | - | อ่านเฉพาะ `gold` | ชื่อเหลือตัวแรก, วันเกิดเหลือแค่ปี |

- Schema / ตารางที่ไม่มีสิทธิ์จะถูกซ่อน (analyst เห็นแค่ catalog `lakehouse` schema `gold`)
- แก้สิทธิ์: แก้ `grants` / `masks` ใน `opa/trino.rego` → รัน test → `docker compose restart opa` (มีผลทันที ไม่ต้อง restart Trino)
- เพิ่มคนเข้ากลุ่ม: ทำที่ LDAP (ดู `ldap/README.md`) ไม่ต้องแก้ Trino

```bash
# unit test ของ policy (ทำทุกครั้งที่แก้ trino.rego)
docker run --rm -v ./opa:/policies openpolicyagent/opa:1.22.0 test /policies -v
```

## ต่อด้วย DBeaver

1. New Database Connection → **Trino**
2. Host `localhost` · Port `8443` · Username / Password ตามตารางใน `ldap/README.md` (เช่น `analyst` / `analyst123`)
3. แท็บ **Driver properties**: `SSL` = `true`, `SSLTrustStorePath` = ที่อยู่ไฟล์ `trino/certs/public/trino.pem` บนเครื่อง
   (ทางลัดในห้องเรียน: `SSLVerification` = `NONE` แทน แต่จะไม่ได้เช็กว่าคุยกับ Trino ตัวจริง)
4. Test Connection (ครั้งแรก DBeaver ขอดาวน์โหลด driver) → Finish

ลองต่อ 2 connection เป็น `analyst` กับ `engineer` แล้วเปิดตารางเดียวกันเทียบกัน:

```sql
SELECT customer_id, full_name, birth_date, membership_tier, valid_from, is_current
FROM lakehouse.gold.dim_customer WHERE customer_id = 1;               -- analyst เห็น "ก***" / engineer เห็นชื่อจริง
SELECT count(*) FROM lakehouse.silver.customers;                      -- analyst: Access Denied
DELETE FROM lakehouse.gold.daily_sales WHERE false;                   -- engineer: Access Denied (เขียนผ่าน pipeline เท่านั้น)
SELECT * FROM lakehouse.gold.daily_overview ORDER BY order_date DESC LIMIT 10;
SELECT * FROM lakehouse.silver."orders$partitions";                  -- (engineer) partition รายเดือนของ Iceberg
SELECT query_id, "user", state, query FROM system.runtime.queries;    -- เห็นเฉพาะ query ของตัวเอง (admin เห็นทั้งหมด)
```

หน้าเว็บ https://localhost:8443/ui (browser เตือนเรื่อง cert เพราะเป็น self-signed ให้กดยอมรับ) แล้ว login ด้วยผู้ใช้ข้างบน

## ดู log / ปัญหาที่พบบ่อย

```bash
docker logs trino --tail 50            # รอจนเห็น "SERVER STARTED"
docker logs openldap --tail 20         # การ login (BIND) ที่ Trino ส่งไปเช็ก
```

- `Authentication over HTTP is not enabled`: ใช้ `http://` → ต้องเป็น `https://...:8443`
- `Invalid credentials`: ชื่อหรือรหัสผิด หรือยังไม่ได้เปิด `ldap/`
- `Access Denied: Cannot ...`: login ได้แต่ policy ไม่ให้ → ดูตารางสิทธิ์ด้านบน / `opa/trino.rego`
- `PKIX path building failed` / `certificate verify failed`: client ไม่รู้จัก cert → ใส่ `trino/certs/public/trino.pem`
- `Schema 'silver' does not exist` / `Table ... does not exist`: pipeline ที่เป็นเจ้าของตารางนั้นยังไม่เคยรันสำเร็จ
- เพิ่ม catalog: วางไฟล์ `.properties` ใหม่ใน `catalog/` แล้ว `docker compose restart trino` และเพิ่มสิทธิ์ใน `opa/trino.rego`
- ลบ `certs/` แล้ว `docker compose up -d` = ได้ cert ใหม่ (ต้อง restart airflow และตั้ง DBeaver ใหม่)
