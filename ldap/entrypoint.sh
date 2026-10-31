#!/bin/sh
# เปิดครั้งแรก (volume ว่าง): สร้าง config + ใส่ผู้ใช้ / กลุ่มจาก seed/ · ครั้งต่อไป: เปิด slapd อย่างเดียว ข้อมูลเดิมอยู่ครบ
set -e
HOME_DIR=/var/lib/openldap
CONF=$HOME_DIR/slapd.d

if [ ! -f "$CONF/cn=config.ldif" ]; then
    echo "first start: building directory dc=dataplatform,dc=local"
    mkdir -p "$CONF" "$HOME_DIR/data"
    # รหัสผ่านเก็บเป็น hash (SSHA) ไม่เก็บตัวจริง
    h() { slappasswd -h '{SSHA}' -s "$1"; }
    sed -e "s|@@ROOT@@|$(h "$LDAP_ROOT_PASSWORD")|" \
        /opt/ldap/config/slapd.ldif > /tmp/config.ldif
    sed -e "s|@@TRINO@@|$(h "$TRINO_BIND_PASSWORD")|" \
        -e "s|@@AIRFLOW@@|$(h "$AIRFLOW_PASSWORD")|" \
        -e "s|@@ADMIN@@|$(h "$ADMIN_PASSWORD")|" \
        -e "s|@@ENGINEER@@|$(h "$ENGINEER_PASSWORD")|" \
        -e "s|@@ANALYST@@|$(h "$ANALYST_PASSWORD")|" \
        /opt/ldap/seed/directory.ldif > /tmp/directory.ldif
    slapadd -n 0 -F "$CONF" -l /tmp/config.ldif
    slapadd -n 1 -F "$CONF" -l /tmp/directory.ldif
    rm /tmp/config.ldif /tmp/directory.ldif
    chown -R ldap:ldap "$HOME_DIR"
fi

mkdir -p /run/openldap && chown ldap:ldap /run/openldap
# -d stats = log ทุกการ login / ค้นหา ออกทาง docker logs (ดูได้ว่า Trino มาเช็กรหัสของใคร)
exec slapd -u ldap -g ldap -F "$CONF" -h "ldap:///" -d stats
