# OpenStreetMap Tile Server

Enterprise-ready OpenStreetMap tile server based on AlmaLinux 9.

Stateless architecture with external PostgreSQL/PostGIS, automatic map updates, structured logging and production-grade security.

## Architecture

Unlike many OpenStreetMap tile server images, this project does not embed PostgreSQL/PostGIS inside the container.

Instead, the tile server and the database are deployed independently, resulting in a stateless application that is easier to operate in modern container platforms such as Docker, Kubernetes and OpenShift.

## Features

- AlmaLinux 9 (RHEL compatible)
- Latest Mapnik compiled from source
- Latest mod_tile compiled from source
- External PostgreSQL/PostGIS managed separately
- Non-root container
- Automatic OSM updates
- Structured JSON logs
- Apache HTTPD
- Renderd
- Optional persistent tile cache
- Automatic import from Geofabrik
- Custom PBF support
- Ready for Kubernetes/OpenShift

## Requirements

Before running the container, ensure the following requirements are met.

### PostgreSQL with PostGIS

This image is **stateless** and requires an **external PostgreSQL/PostGIS database**. The database is used to store OpenStreetMap data and is **not** bundled with the container.

Requirements:

* PostgreSQL 16 or later (18 recommended)
* PostGIS 3.6 or later
* A dedicated database for OpenStreetMap data
* A user with permission to create tables, indexes and extensions
* A reliable network connection between the tile server and the database

The database should be provisioned before starting the container.

---

### Storage

Depending on the imported region, a significant amount of disk space may be required for:

* PostgreSQL database
* Rendered tile cache
* Import files
* Update state files
* Log files

Using SSD or NVMe storage is strongly recommended for production deployments.

---

### Memory

The required amount of memory depends on the imported dataset.

Typical recommendations are:

| Dataset         | Recommended RAM |
| --------------- | --------------: |
| Small region    |          4–8 GB |
| Country         |        16–32 GB |
| Large continent |   64 GB or more |

---

### CPU

Tile rendering is CPU intensive.

For production deployments, multiple CPU cores are recommended to allow concurrent rendering requests and background update processing.

---

### Example PostgreSQL Container

The following example starts a PostgreSQL/PostGIS container suitable for development or evaluation purposes.

```bash
docker run -d \
  --name postgis \
  -e POSTGRES_DB=osm \
  -e POSTGRES_USER=renderer \
  -e POSTGRES_PASSWORD=renderer \
  -v osm-db:/var/lib/postgresql/data \
  postgis/postgis:18-3.6-alpine
```

For production environments, database configuration should be adjusted according to the available hardware and expected workload.


## Quick Start

docker run \
  -e PGHOST=...
  -e PGPORT=5432 \
  -e PGDATABASE=osm \
  -e PGUSER=osm \
  -e PGPASSWORD=secret \
  -p 8080:8080 \
  vitorosan/openstreetmap-tile-server:latest

## Environment Variables

The container behavior can be customized through the following environment variables.

### Database Configuration

These variables are **required** and define the connection to an external PostgreSQL/PostGIS database.

| Variable     | Required | Description                               | Example                |
| ------------ | -------- | ----------------------------------------- | ---------------------- |
| `PGHOST`     | Yes      | PostgreSQL server hostname or IP address. | `postgres.example.com` |
| `PGPORT`     | Yes      | PostgreSQL server port.                   | `5432`                 |
| `PGDATABASE` | Yes      | Name of the PostGIS database.             | `gis`                  |
| `PGUSER`     | Yes      | PostgreSQL username.                      | `osm`                  |
| `PGPASSWORD` | Yes      | PostgreSQL user password.                 | `secret`               |

> **Note**
>
> The database must already exist and have the PostGIS extension installed. The configured user must have sufficient privileges to create tables, indexes and extensions required during the import process.

---

### HTTP Server

| Variable     | Default    | Description                                                                                                                                             |
| ------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ALLOW_CORS` | *(none)* | Enables Cross-Origin Resource Sharing (CORS) headers for tile requests. Set to `enabled` to allow access from web applications hosted on other domains. |

---

### Initial Data Download

These variables control how the initial OpenStreetMap dataset is obtained.

| Variable        | Default             | Description                                                                                                                                                |
| --------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DOWNLOAD_PBF`  | https://download.geofabrik.de/south-america/uruguay-latest.osm.pbf | URL of the `.osm.pbf` file to import.                                                                                                                      |
| `DOWNLOAD_POLY` | https://download.geofabrik.de/south-america/uruguay.poly | URL of the corresponding `.poly` polygon file used to limit updates to the imported region.                                                                |
| `WGET_ARGS`     | *(none)*            | Additional command-line arguments passed to `wget` when downloading files. Useful for configuring proxies, authentication, certificates or retry behavior. |

---

### Automatic Updates

These variables configure the replication process that keeps the imported dataset synchronized with OpenStreetMap changes.

| Variable               | Default                              | Description                                                                                             |
| ---------------------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------- |
| `UPDATES`              | *(none)*                            | Enables or disables automatic incremental updates. |
| `UPDATES_CRON`         | `* * * * *`                          | Cron expression that defines how often update jobs are executed.                                        |
| `REPLICATION_URL`      | https://planet.openstreetmap.org/replication/hour | Base URL of the replication server used for incremental updates. Can be changed to use a custom mirror. |
| `MAX_INTERVAL_SECONDS` | 3600                  | Maximum allowed replication interval. Prevents importing excessively old replication sequences.         |

---

### Tile Expiration

These variables control the tile expiration process after database updates. Expired tiles are automatically re-rendered when requested.

| Variable              | Default             | Description                                                                             |
| --------------------- | ------------------- | --------------------------------------------------------------------------------------- |
| `EXPIRY_MINZOOM`    | 13 | Minimum zoom level for tile expiration.                                                 |
| `EXPIRY_TOUCHFROM`  | 13 | Zoom level from which tiles are marked for expiration ("touch").                        |
| `EXPIRY_DELETEFROM` | 19 | Zoom level from which cached tiles are deleted instead of only being marked as expired. |
| `EXPIRY_MAXZOOM`    | 20 | Maximum zoom level considered during tile expiration.                                   |


## Using an Existing PBF

By default, the container downloads the required OpenStreetMap dataset during the initial startup. However, if you already have a downloaded dataset, you can skip this step by mounting a host directory to `/data/import`.

The directory must contain the following files:

| File                | Description                                                                                                                                                        |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `region.osm.pbf`    | OpenStreetMap dataset to be imported into the database.                                                                                                            |
| `region.poly`       | Polygon file defining the geographic boundaries used for incremental updates. This file is optional.                                                                                      |
| `state.txt`         | Replication state file corresponding to the downloaded PBF. It allows incremental updates to continue from the correct sequence without requiring a full reimport. |
| `configuration.txt` | This file defines the data source and download parameters. It must contain at least the baseUrl (pointing to the OSM replication directory, e.g., https://planet.openstreetmap.org/replication/minute/) and maxInterval (controlling how many seconds of changes to download per run).                                                                    |

Example:

```text
/data/import
├── region.osm.pbf
├── region.poly
├── state.txt
└── configuration.txt
```

When all required files are present, the container skips the download step and imports the local dataset instead.

This approach is recommended when:

* Using a previously downloaded dataset.
* Deploying in environments without Internet access.
* Speeding up deployments by avoiding large downloads.
* Reusing the same dataset across multiple environments.

> **Important**
>
> The `state.txt` and `configuration.txt` files must correspond to the same dataset version as the `.osm.pbf` file. Otherwise, incremental updates may fail or produce inconsistent results.


## Automatic Download

TODO: document this section

## Automatic Updates

TODO: document this section

## Volumes

The container supports mounting the following directories to persist data and customize its behavior.

| Container Path             | Description                                                                       |
| -------------------------- | --------------------------------------------------------------------------------- |
| `/data/import`             | Import data used during the initial database import command.                      |
| `/data/updates`            | Osmosis replication configuration and state files used for incremental updates.   |
| `/var/log/tiles`           | Log files generated during database import, update and tile rendering operations. |
| `/var/cache/renderd/tiles` | Persistent cache of rendered map tiles.                                           |

### `/data/import`

This directory contains the files required for the initial database import. If a valid dataset is already present, the container skips the download step and imports the local data instead.

Typical contents:

```text
/data/import
├── region.osm.pbf
├── region.poly
├── state.txt
└── configuration.txt
```

See the **Using an Existing PBF** section for more details.

---

### `/data/updates`

This directory stores the files required by Osmosis to perform incremental OpenStreetMap updates.

Typical contents include:

* `state.txt`
* `configuration.txt`
* replication working files

Persisting this directory allows update processing to continue from the last successfully applied replication sequence after a container restart.

---

### `/var/log/tiles`

This directory contains operational logs generated by the container, including:

* database import (`osm2pgsql`)
* incremental update (`osmosis`)
* update orchestration
* tile expiration

Mounting this directory is recommended for troubleshooting and long-term log retention.

---

### `/var/cache/renderd/tiles`

This directory stores the rendered tile cache generated by `renderd`.

Persisting this directory avoids re-rendering tiles after container restarts, significantly reducing startup time and improving response latency for previously requested map tiles.

If this volume is not persisted, the tile cache is recreated on demand as tiles are requested.

## Production recommendations

- Use SSD storage
- Keep PostgreSQL on dedicated host
- Enable persistent tile cache
- Use at least 32 GB RAM for Brazil region
- Prefer PostGIS on NVMe

## PostgreSQL Performance Tuning

OpenStreetMap imports and tile rendering place a significantly different workload on PostgreSQL than a typical OLTP application. For best performance, it is recommended to dedicate the database server exclusively to the tile server and tune PostgreSQL accordingly.

The following example demonstrates a PostgreSQL/PostGIS container configured for importing and serving a large OpenStreetMap dataset. The values shown are intended as a starting point and should be adjusted based on the available CPU, memory and storage.

```bash
docker run --rm -d \
    --name=openstreetmap-tile-postgis \
    --shm-size=1g \
    -v osmtiles-database:/var/lib/postgresql \
    -p 5432:5432 \
    -e TZ=America/Sao_Paulo \
    -e POSTGRES_PASSWORD=renderer \
    -e POSTGRES_USER=renderer \
    -e POSTGRES_DB=osm \
    -e POSTGRES_HOST_AUTH_METHOD=trust \
    postgis/postgis:18-3.6-alpine \
    -c max_connections=250 \
    -c shared_buffers=2GB \
    -c temp_buffers=32MB \
    -c maintenance_work_mem=1GB \
    -c work_mem=256MB \
    -c synchronous_commit=off \
    -c effective_cache_size=24GB \
    -c wal_writer_delay=500ms \
    -c wal_level=minimal \
    -c wal_buffers=1024kB \
    -c min_wal_size=1GB \
    -c max_wal_size=2GB \
    -c commit_delay=10000 \
    -c checkpoint_timeout=15min \
    -c checkpoint_completion_target=0.9 \
    -c max_wal_senders=0 \
    -c default_statistics_target=10000 \
    -c random_page_cost=1.1 \
    -c autovacuum_work_mem=2GB \
    -c track_activity_query_size=16384 \
    -c fsync=off \
    -c jit=off
```

### Notes

* These settings are intended for a **dedicated PostgreSQL/PostGIS instance** used exclusively by this tile server.
* The optimal values depend on the amount of available RAM, CPU cores and storage performance.
* SSD or NVMe storage is strongly recommended.
* `fsync=off` and `synchronous_commit=off` improve import performance but increase the risk of data loss in the event of an unexpected power failure. Consider enabling these settings in production environments where durability is required.
* `wal_level=minimal` and `max_wal_senders=0` are appropriate for standalone deployments that do not use replication.
* Review PostgreSQL settings before using them in shared database servers or high-availability environments.

## Further Reading

The following resources provide additional information about running a production-grade OpenStreetMap tile server:

- [osm2pgsql Manual](https://osm2pgsql.org/doc/manual.html)
- [Switch2OSM – Serving Tiles](https://switch2osm.org/serving-tiles/)
- [OpenStreetMap Wiki – Tile Servers](https://wiki.openstreetmap.org/wiki/Tile_servers)
- [PostgreSQL Runtime Configuration](https://www.postgresql.org/docs/current/runtime-config.html)
- [PostGIS Documentation](https://postgis.net/documentation/)


## Examples

TODO: document this section

## Troubleshooting

TODO: document this section

## Roadmap

- Upgrade to the latest relase of LEAFLET
- Parametrization of log levels
- Exposing monitoring metrics

## Acknowledgements

This project is based on the excellent work of the Overv/openstreetmap-tile-server project.

The original repository can be found at:

https://github.com/Overv/openstreetmap-tile-server

Many thanks to Alexander Overvoorde and all contributors to the original project.
