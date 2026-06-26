FROM almalinux:9 AS setup

# ============================================
# Basic system dependencies
# ============================================
RUN dnf -y install epel-release dnf-plugins-core && \
    dnf config-manager --set-enabled crb && \
    dnf -y update && \
    dnf -y groupinstall "Development Tools" && \
    dnf -y install \
        wget \
        cmake3 \
        python3-devel \
        python3-psycopg2 \
        python3-yaml \
        python3-pyyaml \
        python3-requests \
        python3-lxml \
        python3-shapely \
        sqlite-devel \
        libtiff-devel \
        libcurl-devel \
        libicu-devel \
        harfbuzz-devel \
        cairo-devel \
        libwebp-devel \
        libpng-devel \
        libjpeg-turbo-devel \
        postgresql \
        postgresql-devel \
        httpd \
        httpd-devel \
        lua \
        lua-devel \
        java-25-openjdk-headless \
        bc \
        nodejs \
        npm \
        bash \
        util-linux \
        procps-ng \
        tini \
        jq \
        && \
    dnf clean all
RUN alternatives --set java "$(ls -d /usr/lib/jvm/java-25-openjdk/bin/java 2>/dev/null | head -1)"
RUN rm --force /etc/httpd/conf.d/welcome.conf


FROM setup AS libbuild

# ----------------------------------------------
# BOOST
# ----------------------------------------------
ARG BOOST_VERSION=1.85.0
ARG BOOST_VERSION_UNDERSCORED=1_85_0
RUN cd /tmp && \
    wget https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION_UNDERSCORED}.tar.gz && \
    tar xf boost_${BOOST_VERSION_UNDERSCORED}.tar.gz && \
    cd boost_${BOOST_VERSION_UNDERSCORED} && \
    ./bootstrap.sh --prefix=/usr/local --with-python=python3 --with-libraries=system,filesystem,thread,program_options,regex,date_time,atomic,iostreams,python,context,url && \
    ./b2 -j $(nproc) install
RUN rm -rf /tmp/boost_${BOOST_VERSION_UNDERSCORED}*


# ----------------------------------------------
# PROJ
# ----------------------------------------------
ARG PROJ_VERSION=9.8.1
RUN cd /tmp && \
    wget https://download.osgeo.org/proj/proj-${PROJ_VERSION}.tar.gz && \
    tar xzf proj-${PROJ_VERSION}.tar.gz && \
    cd proj-${PROJ_VERSION} && \
    mkdir build && \
    cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_APPS=ON \
        -DBUILD_TESTING=OFF \
        -DENABLE_CURL=ON \
        -DENABLE_TIFF=ON \
        -DCMAKE_PREFIX_PATH="/usr/local" && \
    cmake --build . -j $(nproc) && \
    cmake --build . --target install
RUN rm -rf /tmp/proj-${PROJ_VERSION}*
RUN projsync --system-directory --all


# ----------------------------------------------
# GDAL
# ----------------------------------------------
ARG GDAL_VERSION=3.13.1
RUN cd /tmp && \
    wget https://github.com/OSGeo/gdal/releases/download/v${GDAL_VERSION}/gdal-${GDAL_VERSION}.tar.gz && \
    tar xzf gdal-${GDAL_VERSION}.tar.gz && \
    cd gdal-${GDAL_VERSION} && \
    mkdir build && cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_PREFIX_PATH="/usr/local" \
        -DBUILD_APPS=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
        -DBUILD_PYTHON_BINDINGS=OFF \
        -DGDAL_USE_PROJ=ON \
        -DGDAL_USE_SQLITE3=ON \
        -DGDAL_USE_LIBKML=OFF \
        -DGDAL_USE_GEOTIFF=OFF \
        -DGDAL_USE_GEOTIFF_INTERNAL=ON \
        -DGDAL_USE_NETCDF=OFF \
        -DGDAL_USE_HDF5=OFF \
        -DGDAL_USE_GEOS=OFF \
        -DGDAL_ENABLE_DRIVER_GTIFF=ON && \
    cmake --build . -j $(nproc) && \
    cmake --build . --target install
RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/gdal.conf && \
    echo "/usr/local/lib64" >> /etc/ld.so.conf.d/gdal.conf && \
    ldconfig && \
    rm -rf /tmp/gdal-${GDAL_VERSION}*
ENV GDAL_DATA=/usr/local/share/gdal
ENV GDAL_DRIVER_PATH=/usr/local/lib/gdalplugins


# ----------------------------------------------
# MAPNIK
# ----------------------------------------------
ARG MAPNIK_VERSION=4.2.2
RUN cd /tmp && \
    git clone --branch v${MAPNIK_VERSION} --depth 1 https://github.com/mapnik/mapnik.git && \
    cd mapnik && \
    git submodule update --init --depth 1 && \
    python3 scons/scons.py configure \
        CUSTOM_CXXFLAGS="-w" \
        CUSTOM_CFLAGS="-w" \
        PREFIX=/usr/local \
        BOOST_INCLUDES=/usr/local/include \
        BOOST_LIBS=/usr/local/lib \
        PROJ_INCLUDES=/usr/local/include \
        PROJ_LIBS=/usr/local/lib \
        INPUT_PLUGINS='postgis' \
        GDAL_CONFIG=/usr/local/bin/gdal-config && \
    python3 scons/scons.py -j $(nproc) --quiet && \
    python3 scons/scons.py install && \
    ldconfig
RUN rm -rf /tmp/mapnik


# ============================================
# LIBINIPARSER
# ============================================
ARG INIPARSER_VERSION=4.2.6
RUN cd /tmp && \
    wget -O /tmp/iniparser.zip https://github.com/ndevilla/iniparser/archive/refs/tags/v${INIPARSER_VERSION}.zip && \
    unzip /tmp/iniparser.zip && \
    cd iniparser-${INIPARSER_VERSION} && \
    mkdir -p build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
          -DBUILD_SHARED_LIBS=ON \
          -DBUILD_STATIC_LIBS=ON \
          -DBUILD_DOCS=OFF \
          -DBUILD_EXAMPLES=OFF \
          -DBUILD_TESTING=OFF .. && \
    make all && \
    make install && \
    ldconfig
RUN rm -rf /tmp/iniparser*


# ============================================
# MOD_TILE
# ============================================
ARG MODTILE_VERSION=0.8.1
RUN cd /tmp && \
    wget -O /tmp/mod_tile.zip https://github.com/openstreetmap/mod_tile/archive/refs/tags/v${MODTILE_VERSION}.zip && \
    unzip mod_tile.zip && \
    cd mod_tile-${MODTILE_VERSION} && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    make install-mod_tile
RUN rm -rf /tmp/mod_tile*
RUN echo "LoadModule tile_module modules/mod_tile.so" \
  | tee --append /etc/httpd/conf.modules.d/11-mod_tile.conf


# ============================================
# NLOHMANN
# ============================================
ARG NLOHMANN_VERSION=3.12.0
RUN cd /tmp && \
    wget -O /tmp/json.zip https://github.com/nlohmann/json/archive/refs/tags/v${NLOHMANN_VERSION}.zip && \
    unzip json.zip && \
    cd json-${NLOHMANN_VERSION} && \
    mkdir -p build && \
    cd build && \
    cmake -D CMAKE_INSTALL_PREFIX=/usr/local \
          -D CMAKE_BUILD_TYPE=Release \
          -D JSON_BuildTests=OFF \
          ..  && \
    make install
RUN rm -rf /tmp/json*


# ============================================
# OSM2PGSQL
# ============================================
ARG OSM2PGSQL_VERSION=2.3.0
RUN cd /tmp && \
    wget -O /tmp/osm2pgsql.zip https://github.com/osm2pgsql-dev/osm2pgsql/archive/refs/tags/${OSM2PGSQL_VERSION}.zip && \
    unzip osm2pgsql.zip && \
    cd osm2pgsql-${OSM2PGSQL_VERSION} && \
    mkdir -p build && \
    cd build && \
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_TESTS=OFF \
        -DWITH_PROJ=ON \
        -DWITH_LUAJIT=OFF && \
    make -j$(nproc) && \
    make install
RUN rm -rf /tmp/osm2pgsql*


# ============================================
# OSMOSIS
# ============================================
ARG OSMOSIS_VERSION=0.49.2
RUN cd /tmp && \
    wget -O /tmp/osmosis-${OSMOSIS_VERSION}.zip https://github.com/openstreetmap/osmosis/releases/download/${OSMOSIS_VERSION}/osmosis-${OSMOSIS_VERSION}.zip && \
    unzip /tmp/osmosis-${OSMOSIS_VERSION}.zip && \
    mkdir -p /opt/osmosis && \
    cp -r /tmp/osmosis-${OSMOSIS_VERSION}/* /opt/osmosis/ && \
    chmod +x /opt/osmosis/bin/osmosis && \
    ln -s /opt/osmosis/bin/osmosis /usr/local/bin/osmosis && \
    rm -rf /tmp/osmosis*


# ============================================
# OpenStreetMap Carto
# ============================================
ARG OPENSTREETMAP_CARTO_VERSION=6.0.0
RUN cd /opt && \
    wget -O /opt/openstreetmap-carto.zip https://github.com/openstreetmap-carto/openstreetmap-carto/archive/refs/tags/v${OPENSTREETMAP_CARTO_VERSION}.zip && \
    unzip openstreetmap-carto.zip && \
    rm -f openstreetmap-carto.zip && \
    mv openstreetmap-carto-${OPENSTREETMAP_CARTO_VERSION} openstreetmap-carto && \
    cd /opt/openstreetmap-carto && \
    python3 scripts/get-fonts.py
RUN npm install -g carto@1.2.0


# ============================================
# REGIONAL SCRIPTS HELPER
# ============================================
ARG REGIONAL_HELPER_VERSION=db24f93deacde92f48e703d8c07409c6c6729449
RUN cd /opt && \
    git clone https://github.com/zverik/regional regional && \
    cd regional && \
    git checkout ${REGIONAL_HELPER_VERSION} && \
    rm -rf .git && \
    chmod +x /opt/regional/trim_osc.py


# ============================================
# REPLAG UTILITY
# ============================================
ARG TILES_UPDATE_SCRIPT_VERSION=fef7225b8f1e1854e6245337388e67d21bb036aa
RUN curl -o /opt/osmosis-db_replag-${TILES_UPDATE_SCRIPT_VERSION} https://raw.githubusercontent.com/SomeoneElseOSM/mod_tile/${TILES_UPDATE_SCRIPT_VERSION}/osmosis-db_replag && \
    cd /opt && \
    chmod +x /opt/osmosis-db_replag-${TILES_UPDATE_SCRIPT_VERSION} && \
    ln -s osmosis-db_replag-${TILES_UPDATE_SCRIPT_VERSION} osmosis-db_replag && \
    ln -s /opt/osmosis-db_replag /usr/local/bin/osmosis-db_replag


# ============================================
# LEAFLET
# ============================================
ARG HTTP_SERVER_BASE_URL="http:\/\/\'\+window.location.host\+\'\/tiles"
RUN mkdir -p /var/www/html/ && \
    curl -o /var/www/html/index.html https://raw.githubusercontent.com/SomeoneElseOSM/mod_tile/switch2osm/extra/sample_leaflet.html && \
    sed -i s#http://127.0.0.1/hot#${HTTP_SERVER_BASE_URL}# /var/www/html/index.html && \
    sed -i s/40.36629,\ 49.83335],\ 18/15.96,\ 348.40],\ 3/ /var/www/html/index.html


# ============================================
# SUPERCRONIC
# ============================================
ARG SUPERCRONIC_VERSION=v0.2.46
RUN wget -qO /usr/local/bin/supercronic https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-linux-amd64 && \
    chmod +x /usr/local/bin/supercronic


FROM libbuild AS final

LABEL org.opencontainers.image.title="AlmaLinux 9 OSM Tiles Server" \
      org.opencontainers.image.description="Optimized OpenStreetMap tile server based on AlmaLinux 9 with decoupled PostgreSQL" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.source="https://github.com/vitorosan/openstreetmap-tile-server" \
      org.opencontainers.image.authors="Vitor Rodrigo Rosan <vitorosan@gmail.com>"

RUN cp /opt/openstreetmap-carto/fonts/* /usr/local/lib/mapnik/fonts/
RUN sed -i 's/logging\.basicConfig(level=logging\.\(DEBUG\|WARNING\|INFO\))/logging.basicConfig(level=logging.\1, datefmt="%Y-%m-%d %H:%M:%S", format="%(asctime)s [%(levelname)s] %(message)s")/g' /opt/openstreetmap-carto/scripts/get-external-data.py

RUN mkdir -p /var/run/renderd \
        /var/cache/renderd/tiles \
        /var/lib/mod_tile \
        /var/log/tiles \
        /data/updates \
        /data/import \
        /home/renderer

COPY files/apache.conf /etc/httpd/conf.d/default.conf
COPY files/renderd.conf /usr/local/etc/renderd.conf
COPY files/update.sh /opt/osmtiles-update.sh
COPY files/run.sh /

RUN useradd renderer --shell /bin/bash --home-dir /var/run/renderd --system

RUN chown -R renderer:renderer \
    /data/updates \
    /data/import \
    /etc/httpd/conf.d/default.conf \
    /var/lib/mod_tile \
    /var/log/tiles \
    /var/log/httpd \
    /var/run/renderd \
    /var/cache/httpd \
    /var/cache/renderd/tiles \
    /home/renderer \
    /opt/openstreetmap-carto \
    /usr/local/etc/renderd.conf

RUN chown -R root:root /opt/openstreetmap-carto/scripts /opt/openstreetmap-carto/openstreetmap-carto-flex.lua
RUN chmod +r -R /opt/regional
RUN chmod +x /run.sh
RUN chmod +x /opt/osmtiles-update.sh
RUN chmod -R 755 /opt/openstreetmap-carto
RUN usermod -aG renderer apache

USER renderer

ENV PGPORT=5432
ENV REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/
ENV MAX_INTERVAL_SECONDS=3600
ENV UPDATES=disabled
ENV PGOPTIONS="-c client_min_messages=warning -c jit=off -c max_parallel_workers_per_gather=0"

WORKDIR /home/renderer

ENTRYPOINT [ "/usr/bin/tini", "--", "/run.sh" ]
CMD []

EXPOSE 8080


