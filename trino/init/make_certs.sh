#!/bin/bash
# สร้าง TLS cert ของ Trino ครั้งแรก (มีแล้ว = ข้าม) ด้วย keytool ที่มากับ image ของ Trino
#   certs/private/keystore.p12  = key + cert ของ server (Trino ใช้คนเดียว ห้ามแจก)
#   certs/public/trino.pem      = cert อย่างเดียว (แจก client: Airflow, DBeaver ใช้ยืนยันว่าคุยกับ Trino ตัวจริง)
# ห้องเรียนเป็น self-signed · prod ขอ cert จาก CA ขององค์กร หรือใช้ cert-manager
set -euo pipefail
cd /certs
mkdir -p private public

if [ -f private/keystore.p12 ] && [ -f public/trino.pem ]; then
    echo "ok       certs already exist"
    exit 0
fi

rm -f private/keystore.p12 public/trino.pem
keytool -genkeypair -alias trino -keyalg RSA -keysize 2048 -validity 825 \
    -dname "CN=trino" -ext "SAN=dns:trino,dns:localhost,ip:127.0.0.1" \
    -keystore private/keystore.p12 -storetype PKCS12 -storepass "$TRINO_KEYSTORE_PASSWORD"
keytool -exportcert -rfc -alias trino -keystore private/keystore.p12 \
    -storepass "$TRINO_KEYSTORE_PASSWORD" -file public/trino.pem
echo "created  certs/private/keystore.p12, certs/public/trino.pem (ใช้ได้กับชื่อ trino, localhost)"
