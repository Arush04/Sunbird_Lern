#!/bin/bash

set -eu -o pipefail

echo "Get the standalone-ha.xml template file and module.xml"
curl -sS https://github.com/Sunbird-Lern/sunbird-auth/blob/release-3.8.0/keycloak/scripts/ansible/roles/keycloak/templates/standalone-ha.xml --output standalone-ha.xml
curl -sS https://github.com/Sunbird-Lern/sunbird-auth/blob/release-3.8.0/keycloak/scripts/ansible/roles/keycloak/templates/module.xml.j2 --output module.xml

echo "Get the current VM IP"
#ip="$(ipconfig | grep -A 1 'eth0' | tail -1 | cut -d ':' -f 2 | cut -d ' ' -f 1)"
export ip = "192.168.111.1"
export PG_HOST='kc_postgres'
export PG_USER='kcpgadmin'
export PG_DB='quartz'
export PGPASSWORD='kcpgpassword'

echo "Replace ansible variables with postgres details"
sed -i "s/{{keycloak_postgres_host}}/$PG_HOST/g" standalone-ha.xml
sed -i "s/{{keycloak_postgres_database}}/${PG_DB}7/g" standalone-ha.xml
sed -i "s/{{keycloak_postgres_user}}/$PG_USER/g" standalone-ha.xml
sed -i "s/{{keycloak_postgres_password}}/$PGPASSWORD/g" standalone-ha.xml
sed -i "s/{{ansible_default_ipv4.address}}/$ip/g" standalone-ha.xml
sed -i "s/8080/8081/g" standalone-ha.xml
sed -i "s/\"900\"/\"3600\"/g" standalone-ha.xml

echo "Get keycloak package"
wget -q https://github.com/keycloak/keycloak/releases/download/12.0.0/keycloak-12.0.0.tar.gz

echo "Extract keycloak package"
tar -xf keycloak-12.0.0.tar.gz

echo "Get the postgres jar"
wget -q https://jdbc.postgresql.org/download/postgresql-42.2.23.jar

echo "Copy standalone-ha.xml, postgres jar and module.xml file to keycloak package"
cp standalone-ha.xml keycloak-12.0.0/standalone/configuration
mkdir -p keycloak-12.0.0/modules/system/layers/keycloak/org/postgresql/main
cp postgresql-42.2.23.jar keycloak-12.0.0/modules/system/layers/keycloak/org/postgresql/main
cp module.xml keycloak-12.0.0/modules/system/layers/keycloak/org/postgresql/main

echo "Backup the existing keycloak db"
pg_dump -Fd -j 4 -h 192.168.139.82 -U $PG_USER -d $PG_DB -f ${PG_DB}_backup

echo "Create a new db for keycloak 12"
psql -h $PG_HOST -U $PG_USER -p 5432 -d postgres -c "CREATE DATABASE ${PG_DB}12"

echo "Restore the existing keycloak 7 db to the new database"
pg_restore -O -j 4 -h $PG_HOST -U $PG_USER -d ${PG_DB}12 ${PG_DB}_backup

echo "Clear the DB of duplicate values"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "delete from public.COMPOSITE_ROLE a using public.COMPOSITE_ROLE b where a=b and a.ctid < b.ctid"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "delete from public.REALM_EVENTS_LISTENERS a using public.REALM_EVENTS_LISTENERS b where a=b and a.ctid < b.ctid"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "delete from public.REDIRECT_URIS a using public.REDIRECT_URIS b where a=b and a.ctid < b.ctid"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "delete from public.WEB_ORIGINS a using public.WEB_ORIGINS b where a=b and a.ctid < b.ctid"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "truncate offline_user_session"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "truncate offline_client_session"
psql -h $PG_HOST -U $PG_USER -p 5432 -d ${PG_DB}12 -c "truncate jgroupsping" || true

echo "Migrate the DB to keycloak 12"
cd keycloak-12.0.0
bin/standalone.sh -b=$ip -bprivate=$ip --server-config standalone-ha.xml
