# OpenStreetMap Tile Server

Enterprise-ready OpenStreetMap tile server based on AlmaLinux 9.

Stateless architecture with external PostgreSQL/PostGIS, automatic map updates, structured logging and production-grade security.

## Features

- AlmaLinux 9 (RHEL compatible)
- Latest Mapnik compiled from source
- Latest mod_tile compiled from source
- External PostgreSQL/PostGIS
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

TODO: document this section

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
| `region.poly`       | Polygon file defining the geographic boundaries used for incremental updates.                                                                                      |
| `state.txt`         | Replication state file corresponding to the downloaded PBF. It allows incremental updates to continue from the correct sequence without requiring a full reimport. |
| `configuration.txt` | Configuration file containing the download and replication metadata associated with the dataset.                                                                   |

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
