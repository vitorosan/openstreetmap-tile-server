#!/bin/bash

set -e

BASE_DIR=/var/lib/mod_tile
OSMOSIS_BIN=osmosis
OSM2PGSQL_BIN=osm2pgsql
OSM2PGSQL_OPTIONS="-d $PGDATABASE --number-processes ${THREADS:-4} -S /opt/openstreetmap-carto/openstreetmap-carto-flex.lua ${OSM2PGSQL_EXTRA_ARGS}"
TRIM_BIN=/opt/regional/trim_osc.py
TRIM_POLY_FILE=/data/updates/region.poly
TRIM_OPTIONS="-d $PGDATABASE --host $PGHOST --user $PGUSER --password "
TRIM_REGION_OPTIONS="-p $TRIM_POLY_FILE"
CHANGE_FILE=$BASE_DIR/changes.osc.gz
LOCK_FILE=/tmp/osmtiles-update.lock
LOG_DIR=/var/log/tiles
WORKOSM_DIR=$BASE_DIR/.osmosis
STATE_FILE=$WORKOSM_DIR/state.txt
LAST_STATE_FILE=$WORKOSM_DIR/last.state.txt
TILE_DIR=/var/cache/renderd/tiles
EXPIRY_FILE=$BASE_DIR/dirty_tiles
LAST_EXPIRY_FILE=$WORKOSM_DIR/.last_expiry_file

OSMOSISLOG=$LOG_DIR/osmosis.log
PGSQLLOG=$LOG_DIR/osm2pgsql.log
EXPIRYLOG=$LOG_DIR/expiry.log
RUNLOG=$LOG_DIR/run.log


EXPIRY_MINZOOM=${EXPIRY_MINZOOM:="13"}
EXPIRY_TOUCHFROM=${EXPIRY_TOUCHFROM:="13"}
EXPIRY_DELETEFROM=${EXPIRY_DELETEFROM:="19"}
EXPIRY_MAXZOOM=${EXPIRY_MAXZOOM:="20"}


m_info()
{
    echo "`date +"%Y-%m-%d %H:%M:%S"` [INFO] $1" >> "$RUNLOG"
}

m_error()
{
    echo "`date +"%Y-%m-%d %H:%M:%S"` [ERROR] $1" >> "$RUNLOG"

    m_info "resetting state"
    cp $LAST_STATE_FILE $STATE_FILE 2>/dev/null

    rm -f "$CHANGE_FILE"
    rm -f "$EXPIRY_FILE.$$"
    rm -f "$LOCK_FILE"

    m_info "exited"
    exit 1
}

getlock() 
{
    if [ -s $1 ]; then
        if [ "$(ps -p `cat $1` | wc -l)" -gt 1 ]; then
            return 1 #false
        fi
    fi
    echo $$ >"$1"
    return 0 #true
}

freelock() 
{
    rm -f "$1"
    rm -f "$CHANGE_FILE"
}

# make sure the lockfile is removed when we exit and then claim it
if ! getlock "$LOCK_FILE"; then
    m_info "pid `cat $LOCK_FILE` still running"
    exit 3
fi

# -----------------------------------------------------------------------------
# Add disk space check from https://github.com/zverik/regional
# -----------------------------------------------------------------------------
MIN_DISK_SPACE_MB=500
if `python3 -c "import os, sys; st=os.statvfs('$BASE_DIR'); sys.exit(1 if st.f_bavail*st.f_frsize/1024/1024 > $MIN_DISK_SPACE_MB else 0)"`; then
    m_info "there is less than $MIN_DISK_SPACE_MB MB left"
    exit 4
fi

mkdir -p $WORKOSM_DIR

if [ ! -f "$WORKOSM_DIR/configuration.txt" ]; then
    echo "baseUrl=${REPLICATION_URL:-https://planet.openstreetmap.org/replication/minute}" > "$WORKOSM_DIR/configuration.txt"
    echo "maxInterval=${MAX_INTERVAL_SECONDS:-60}" >> "$WORKOSM_DIR/configuration.txt"
fi

if [ "${REPLICATION_URL:-}" != "" ]; then
    sed -i "s|baseUrl=.*|baseUrl=$REPLICATION_URL|" $WORKOSM_DIR/configuration.txt
fi
if [ "${MAX_INTERVAL_SECONDS:-}" != "" ]; then
    sed -i "s/maxInterval=.*/maxInterval=$MAX_INTERVAL_SECONDS/" $WORKOSM_DIR/configuration.txt
fi

url=$(sed -rn 's/baseUrl=(.+)/\1/p' $WORKOSM_DIR/configuration.txt)
if [ ! -f $STATE_FILE ]; then
    wget ${WGET_ARGS:-} -q -O $STATE_FILE $url/state.txt || true
fi
seq=$(cat "$STATE_FILE" 2>/dev/null | grep sequenceNumber | cut -d= -f2 || true)
seq_remote=$(wget ${WGET_ARGS:-} -q -O - $url/state.txt | sed -rn 's/sequenceNumber=([0-9]+)/\1/p' || true)

if [ -z "$seq" ]; then
    m_error "fail to read current state sequenceNumber"
fi
if [ -z "$seq_remote" ]; then
    m_error "fail to read remote state sequenceNumber"
fi

if [[ $seq -eq $seq_remote ]]; then
	m_info "database is up to date with seq-nr $seq, replag is `osmosis-db_replag -h`"
    exit 0
fi


DHE=[`date +%Y-%m-%d-%H%M%S`]
echo $DHE > "$OSMOSISLOG"
echo $DHE > "$PGSQLLOG"
while [[ $seq -ne $seq_remote ]]; do
    seq_previous=$seq
    m_info "start import from seq-nr $seq, replag is `osmosis-db_replag -h`"
    yes | cp $STATE_FILE $LAST_STATE_FILE
    

    m_info "downloading diff"
    if ! $OSMOSIS_BIN -v 3 --read-replication-interval workingDirectory=$WORKOSM_DIR --simplify-change --write-xml-change $CHANGE_FILE 1>&2 2>> "$OSMOSISLOG"; then
        m_error "osmosis"
        break;
    fi
    if [ -f $TRIM_POLY_FILE ] ; then
        m_info "filtering diff"
        if ! $TRIM_BIN $TRIM_OPTIONS $TRIM_REGION_OPTIONS  -z $CHANGE_FILE $CHANGE_FILE 1>&2 2>> "$RUNLOG"; then
            m_error "trim_osc error"
        fi
    fi

    m_info "importing diff $(du -sh $CHANGE_FILE | cut -f1)"
    if ! $OSM2PGSQL_BIN -v -a --slim -e$EXPIRY_MINZOOM-$EXPIRY_MAXZOOM $OSM2PGSQL_OPTIONS -o "$EXPIRY_FILE" $CHANGE_FILE 1>&2 2>> "$PGSQLLOG"; then
        m_error "osm2pgsql"
        break;
    fi

    rm -f $LAST_STATE_FILE
    seq=`cat $STATE_FILE | grep sequenceNumber | cut -d= -f2`
    if [[ $seq -eq $seq_previous ]]; then
        m_error "seq-nr $seq is the same as previous state"
        break;
    fi

    m_info "expiring tiles"
    echo "$EXPIRY_FILE" > $LAST_EXPIRY_FILE
    if ! render_expired --map=default --tile-dir=$TILE_DIR --min-zoom=$EXPIRY_MINZOOM --touch-from=$EXPIRY_TOUCHFROM --delete-from=$EXPIRY_DELETEFROM --max-zoom=$EXPIRY_MAXZOOM -s /run/renderd/renderd.sock < "$EXPIRY_FILE" 2>&1 | tail -8 >> "$EXPIRYLOG"; then
        m_info "Expiry failed"
    fi
    rm -f "$EXPIRY_FILE"
done

freelock "$LOCK_FILE"

if [[ $seq -ne $seq_remote ]]; then
    m_error "import aborted"
else
    m_info "done with import until seq-nr $seq, replag is `osmosis-db_replag -h`"
fi
