#!/bin/bash

set -euo pipefail

required_vars=("PGDATABASE" "PGHOST" "PGPORT" "PGUSER" "PGPASSWORD")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "ERROR: Env $var not defined"
        exit 1
    fi
done

args=("$@")


mkdir -p /data/updates
ln -s /data/updates /var/lib/mod_tile/.osmosis


if [[ " ${args[@]} " =~ " import " ]]; then
    # TODO: validar se o banco já está populado, existe tabelas?

    TABLE_EXISTS=$(psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -t -c "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'planet_osm_point');" | xargs)
    if [ "$TABLE_EXISTS" = "t" ]; then
        echo "ERROR: Database is not empty"
        exit 1
    fi

    if [ ! -f /data/import/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
        echo "WARNING: No import file at /data/region.osm.pbf, so importing Uruguay as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/south-america/uruguay-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/south-america/uruguay.poly"
    fi

    if [ -n "${DOWNLOAD_PBF:-}" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget ${WGET_ARGS:-} "$DOWNLOAD_PBF" -O /data/import/region.osm.pbf
        if [ -n "${REPLICATION_URL:-}" ]; then
            echo "baseUrl=${REPLICATION_URL}" > /data/updates/configuration.txt
            echo "maxInterval=${MAX_INTERVAL_SECONDS:-60}" >> /data/updates/configuration.txt
            wget ${WGET_ARGS:-} -q O /data/updates/state.txt $REPLICATION_URL/state.txt || true
        fi
    fi
    
    psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -c 'CREATE EXTENSION IF NOT EXISTS hstore;' > /dev/null
    osm2pgsql --create \
        --slim \
        -O flex \
        --database "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" \
        -S /opt/openstreetmap-carto/openstreetmap-carto-flex.lua \
        -C 8000 \
        --number-processes 8 \
        /data/import/region.osm.pbf
        
    if [ -f /data/import/state.txt ]; then
        cp /data/import/state.txt /data/updates/state.txt
    fi
    if [ -f /data/import/region.poly ]; then
        cp /data/import/region.poly /data/updates/region.poly
    fi
    if [ -f /data/import/configuration.txt ]; then
        cp /data/import/configuration.txt /data/updates/configuration.txt
    fi

    cd /opt/openstreetmap-carto
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] Creating database indexes"
    psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f indexes.sql > /dev/null
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] Creating database functions"
    psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f functions.sql > /dev/null
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] Uploading common-values"
    psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -f common-values.sql > /dev/null
    python3 scripts/get-external-data.py --host $PGHOST --port $PGPORT --database $PGDATABASE --username $PGUSER --password $PGPASSWORD    
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] ==> Import finished"
fi

TABLE_EXISTS=$(psql "postgresql://$PGUSER:$PGPASSWORD@$PGHOST:$PGPORT/$PGDATABASE" -t -c "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'planet_osm_point');" | xargs)
if [ "$TABLE_EXISTS" = "f" ]; then
    echo "ERROR: Database is not initialized"
    exit 1
fi

if [ ! -f /data/updates/region.poly ] && [ -n "${DOWNLOAD_POLY:-}" ]; then
    echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
    wget ${WGET_ARGS:-} "$DOWNLOAD_POLY" -O /data/updates/region.poly
fi

# Build default carto
if [ ! -f /opt/openstreetmap-carto/mapnik.xml ] || [ ! -s /opt/openstreetmap-carto/mapnik.xml ]; then
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] Building mapnik.xml"
    cd /opt/openstreetmap-carto
    cat project.mml | \
    sed "s/dbname: \"[^\"]*\"/dbname: \"$PGDATABASE\"/" | \
    sed "/host:/d" | \
    sed "/port:/d" | \
    sed "/user:/d" | \
    sed "/password:/d" | \
    sed "/dbname: \"$PGDATABASE\"/a \    host: \"$PGHOST\"\n    port: \"$PGPORT\"\n    user: \"$PGUSER\"\n    password: \"$PGPASSWORD\"" > /tmp/project.mml
    /bin/cp -f /tmp/project.mml project.mml
    rm -f /tmp/project.mml
    carto --quiet project.mml > mapnik.xml
fi


# Configure Apache CORS
if [[ "${ALLOW_CORS:-}" =~ ^(enabled|1|on|true|yes)$ ]]; then
    cat /etc/httpd/conf.d/default.conf | sed '/<\/VirtualHost>/i \    Header set Access-Control-Allow-Origin "*"' | tee /etc/httpd/conf.d/default.conf > /dev/null
fi

# Configure renderd threads
cat /usr/local/etc/renderd.conf | sed -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" | tee /usr/local/etc/renderd.conf > /dev/null

# Start cron job for updates
if [[ "${UPDATES:-}" =~ ^(enabled|1|on|true|yes)$ ]]; then
    CRON_SCHEDULE="${UPDATES_CRON:-* * * * *}"
    CRONTAB_FILE="/tmp/crontab.evict"
    echo "$CRON_SCHEDULE /opt/osmtiles-update.sh" > "$CRONTAB_FILE"
    /usr/local/bin/supercronic -json "$CRONTAB_FILE" 2>&1 | jq --unbuffered -r '"\(.time) [\(.level | ascii_upcase)] \(.msg)"' &
fi

httpd
/usr/local/bin/renderd -f -c /usr/local/etc/renderd.conf 2>&1 | sed -E -u "
    s/^\*\* ([A-Z]+): ([0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]{3}: (.*)/$(date +'%Y-%m-%d') \2 [INFO] \3/;"
