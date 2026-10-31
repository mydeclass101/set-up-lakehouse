# OpenLDAP 2.6 บน Alpine (image สำเร็จรูปยอดนิยมอย่าง osixia / bitnami เลิกอัปเดตแล้ว จึง build เอง ไฟล์เดียวจบ)
FROM alpine:3.24
RUN apk add --no-cache openldap openldap-back-mdb openldap-clients
COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY config/ /opt/ldap/config/
COPY seed/ /opt/ldap/seed/
EXPOSE 389
ENTRYPOINT ["/entrypoint.sh"]
