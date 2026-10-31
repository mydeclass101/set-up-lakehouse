# LDAP (directory)

สมุดรายชื่อผู้ใช้และกลุ่มของบริษัท Trino ใช้ LDAP 2 อย่าง:

1. **ใครเป็นใคร (authentication):** ตอน login, Trino ส่งชื่อ + รหัสไปเช็กกับ LDAP
2. **อยู่กลุ่มไหน:** Trino ค้นว่าผู้ใช้อยู่กลุ่มอะไร แล้วส่งชื่อกลุ่มให้ OPA ตัดสินว่าทำอะไรได้ (`trino/opa/trino.rego`)

ในองค์กรจริงมักเป็น Active Directory หรือ FreeIPA ที่ทีม IT ดูแล ห้องเรียนใช้ OpenLDAP 2.6 ซึ่งเป็น open source และใช้โปรโตคอลเดียวกัน

| ไฟล์ | คืออะไร |
|---|---|
| `Dockerfile`, `entrypoint.sh` | OpenLDAP บน Alpine · เปิดครั้งแรกสร้าง directory จาก `config/` + `seed/` |
| `config/slapd.ldif` | config ของ server: ชื่อ directory `dc=dataplatform,dc=local`, สิทธิ์การอ่าน |
| `seed/directory.ldif` | ผู้ใช้ + กลุ่มตั้งต้น |

## ผู้ใช้ตั้งต้น

| ผู้ใช้ | รหัส | กลุ่ม | ใน Trino ทำอะไรได้ |
|---|---|---|---|
| `admin` | admin123 | platform-admins | ทุกอย่าง |
| `engineer` | engineer123 | data-engineers | อ่านได้ทุก catalog เขียนไม่ได้ |
| `analyst` | analyst123 | analysts | อ่าน `lakehouse.gold` อย่างเดียว ชื่อ / วันเกิดลูกค้าถูกปิดบัง |
| `airflow` (service account) | airflow-svc | etl | อ่าน shop, เขียน raw / lakehouse |
| `trino` (service account) | trino-bind | - | Trino ใช้อ่านรายชื่อกลุ่ม (login แล้วไม่เห็นข้อมูลอะไร) |

รหัสผ่านเก็บใน LDAP เป็น hash (SSHA) · `cn=root` = ผู้ดูแล LDAP ใช้เพิ่ม / ลบผู้ใช้

## ดู / เพิ่มผู้ใช้

```bash
# ดูว่าใครอยู่กลุ่มไหน
docker exec openldap ldapsearch -x -LLL -D cn=root,dc=dataplatform,dc=local -w ldap-root \
  -b ou=groups,dc=dataplatform,dc=local member

# เพิ่ม analyst คนใหม่ แล้วใส่เข้ากลุ่ม analysts
docker exec -i openldap ldapadd -x -D cn=root,dc=dataplatform,dc=local -w ldap-root <<'EOF'
dn: uid=analyst2,ou=people,dc=dataplatform,dc=local
objectClass: inetOrgPerson
uid: analyst2
cn: Analyst Two
sn: Two
userPassword: analyst2pass

dn: cn=analysts,ou=groups,dc=dataplatform,dc=local
changetype: modify
add: member
member: uid=analyst2,ou=people,dc=dataplatform,dc=local
EOF

docker logs openldap --tail 20      # เห็นทุกการ login / ค้นหา (BIND, SRCH) ที่ Trino ส่งมา
```

เพิ่มคนเข้ากลุ่มแล้วใช้ได้ทันที ไม่ต้อง restart Trino · Trino จำผลการ login ไว้ 5 นาที จึงต้องรอให้ครบก่อน การลบผู้ใช้หรือเปลี่ยนรหัสถึงจะมีผล
แก้ `seed/directory.ldif` มีผลเฉพาะตอนสร้างใหม่ (`docker compose down -v` แล้ว `up -d --build`)
